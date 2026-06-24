# ztunnel — the ambient L4 data plane

`ztunnel` ("zero-trust tunnel") is the per-node proxy that *is* ambient mode's secure overlay. It's a **DaemonSet** (one pod per node, installed by the `istio/ztunnel` chart — see [`values-ztunnel.yaml`](./helm/istio/values-ztunnel.yaml)) written in **Rust**, deliberately small and not Envoy. Its whole job: terminate and originate **mTLS over HBONE** for every ambient pod on its node, enforce **L4** identity/policy, and emit L4 telemetry. Anything HTTP-aware is *not* its job — that's the [waypoint](./README.md#step-4--waypoint-proxy-in-the-httpbin-namespace).

## Why a new proxy instead of a sidecar

| | Sidecar (Envoy) | ztunnel (ambient) |
|---|---|---|
| Placement | one per pod | one per **node** (DaemonSet) |
| Lifecycle | coupled to the app pod (restart app → restart proxy) | decoupled — upgrade the mesh without restarting apps |
| Cost | CPU/mem tax on every pod | amortized per node |
| Scope | full L7 Envoy on every pod | **L4 only**, L7 is opt-in via waypoint |
| Identity | pod's SA cert in the sidecar | ztunnel holds **every local pod's** cert, keyed by identity |

The trade is the "ambient promise": pay for L7 only where you need it. A bare ambient namespace gets mTLS, identity, and L4 authz for free; HTTP routing/retries/JWT/path-based authz cost a waypoint.

## How traffic reaches ztunnel

ztunnel never sits *inside* the app pod's process, but it does intercept the pod's traffic. The [`istio-cni`](./README.md#install-istio-ambient-with-helm) plugin programs redirection **when the pod's network namespace is created**, then exits — it's a configurer, not a runtime hop:

- Outbound from an ambient pod is redirected (via in-netns sockets / iptables) to the **local** ztunnel.
- ztunnel looks up the destination's identity and workload info (pushed by istiod over xDS) and opens an **HBONE** tunnel to the **destination node's** ztunnel.
- The destination ztunnel terminates mTLS and delivers plaintext to the target pod.

The label that opts a pod in is `istio.io/dataplane-mode=ambient` on the Namespace or Pod — without it, CNI programs no redirect and ztunnel ignores the pod (see [README step 2](./README.md#step-2--test-workloads-httpbin--netshoot)).

## The data path (this repo's step 2)

```
netshoot (worker2)                              httpbin (worker1)
    │  plaintext (redirected in-netns)               ▲ plaintext
    ▼                                                 │
ztunnel (worker2) ───── mTLS · HBONE (CONNECT/H2) ── ztunnel (worker1)
        client identity              port 15008          server identity
```

mTLS exists **only on the ztunnel-to-ztunnel hop**. The pod↔local-ztunnel segments are plaintext on the loopback/netns path — they never leave the node, and the kernel redirect keeps them off the wire. So "is the app encrypted on the wire?" → yes; "is localhost encrypted?" → no, by design.

## HBONE — the tunnel protocol

**H**TTP-**B**ased **O**verlay **N**etwork **E**nvelope. ztunnel-to-ztunnel traffic is **HTTP/2 `CONNECT` over mTLS on port 15008**. The original L4 stream is tunneled inside the CONNECT; the outer TLS carries the SPIFFE identities. Consequences worth knowing:

- A `tcpdump` between nodes shows TLS to `:15008`, not your app's port — the real destination is inside the encrypted CONNECT.
- One H2 connection between a node pair multiplexes many logical streams (connection reuse, less handshake churn).
- Pooling/keep-alive is per node-pair, so the *first* cross-node request to a new peer pays a handshake; later ones don't.

## Identity & mTLS

- Each workload gets a **SPIFFE** identity: `spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>` — derived from the pod's **Kubernetes ServiceAccount**.
- istiod is the CA; ztunnel fetches and rotates the **per-identity** certs for the pods on its node. It does *not* use one node cert — it presents the calling pod's identity, which is what makes L4 `AuthorizationPolicy` by principal meaningful.
- mTLS is **PERMISSIVE→STRICT** as usual via `PeerAuthentication`, but in ambient the enforcement point is ztunnel, not a sidecar.

## What ztunnel enforces (L4) vs. what needs a waypoint (L7)

| Want to… | Enforced by | Why |
|---|---|---|
| mTLS, peer identity | **ztunnel** | it terminates the HBONE/mTLS |
| `AuthorizationPolicy` on port, identity (principal), namespace, SNI | **ztunnel** | all visible at L4 |
| `AuthorizationPolicy` on HTTP path / method / header, JWT claims | **waypoint** | ztunnel doesn't parse HTTP |
| HTTP routing, retries, fault injection, mirroring, `VirtualService` rules | **waypoint** | L7 logic |
| `istio_requests_total` with HTTP code/path dimensions | **waypoint** | ztunnel emits L4 metrics only |

Rule of thumb: if the policy/route can be decided **without reading the HTTP bytes**, ztunnel does it; otherwise you need a waypoint on the destination. A waypoint doesn't replace ztunnel — traffic still rides HBONE; the waypoint is an extra L7 Envoy hop *before* the destination ztunnel (see [README steps 4–5](./README.md#step-4--waypoint-proxy-in-the-httpbin-namespace)).

## Inspecting ztunnel

ztunnel's view of the world (workloads, services, certs, policies) is its xDS-pushed state — query it with `istioctl ztunnel-config`:

```sh
# Workloads ztunnel knows about (identity, node, protocol, waypoint binding)
istioctl ztunnel-config workloads
# Services and their backends
istioctl ztunnel-config services
# L4 authorization policies ztunnel will enforce
istioctl ztunnel-config policies
# Certs ztunnel currently holds (per identity, with expiry)
istioctl ztunnel-config certificates
# Everything, for one ztunnel pod
istioctl ztunnel-config all -n istio-system ztunnel-<node>
```

Logs are structured and surprisingly readable — a denied connection, a cert rotation, or an HBONE dial failure each log a clear line:

```sh
kubectl -n istio-system logs ds/ztunnel -f
```

## Observability

ztunnel exposes Prometheus metrics on **:15020** and is the **sole source of L4 telemetry** in ambient: `istio_tcp_connections_opened_total`, `istio_tcp_{sent,received}_bytes_total`, with `connection_security_policy=mutual_tls` on secured edges. This is exactly why an ambient edge can show a **lock but no RPS** in Kiali — ztunnel reports the secured L4 connection, but nothing is parsing L7 until a waypoint exists. See [`OBSERVABILITY.md`](./OBSERVABILITY.md), [`MONITORING.md`](./MONITORING.md), and the ambient section of [`KIALI.md`](./KIALI.md).

## Troubleshooting cheatsheet

| Symptom | Likely cause |
|---|---|
| Pod not intercepted (plaintext on the wire) | namespace/pod missing `istio.io/dataplane-mode=ambient`, or CNI didn't run (pod predates the label — restart it) |
| Connection refused / RST after labeling | a too-strict L4 `AuthorizationPolicy` — check `ztunnel-config policies` |
| mTLS lock but no HTTP metrics | no waypoint on the destination — expected, not a bug |
| Cross-node request hangs | HBONE dial to peer ztunnel failing — check both ztunnel logs and that :15008 is reachable node-to-node |
| Cert errors in logs | istiod CA / SA token issue; verify `ztunnel-config certificates` shows fresh, non-expired certs |

## Refs

- https://istio.io/latest/docs/ambient/architecture/ztunnel/
- https://istio.io/latest/docs/ambient/architecture/data-plane/ (HBONE)
- https://github.com/istio/ztunnel — the Rust source (~10k LOC, readable end-to-end)
- https://istio.io/latest/docs/reference/commands/istioctl/#istioctl-ztunnel-config
