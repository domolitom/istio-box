# istio-box

A small, hands-on tutorial for running **Istio in ambient mode** on a local **kind** cluster.

Each commit is one tutorial step. Walk the history with:

```sh
git log --oneline --reverse
```

## Prerequisites

Docker, [kind](https://kind.sigs.k8s.io/), `kubectl`, and `istioctl`.

## Steps

### Step 1 — Initial setup (kind cluster + Istio ambient)

Brings up the kind cluster and installs Istio in ambient mode. See [`diagrams/step-1.excalidraw`](./diagrams/step-1.excalidraw) and [`steps/step-1-skill.md`](./steps/step-1-skill.md) for the end-state of this step.

#### Create the kind cluster

We use three nodes (1 control-plane + 2 workers) so that, later on, ambient traffic can travel between two `ztunnel` instances on different nodes — that's the interesting case to observe.

```sh
# Create the kind cluster
kind create cluster --config kind/cluster.yaml
kubectl get nodes
```

Teardown when finished:

```sh
# Tear down the kind cluster
kind delete cluster --name istio-ambient
```

#### Install Istio (ambient) with Helm

Ambient mode is made of four Helm charts that must be installed in a specific order. Each chart owns one moving part of the data plane, and each has its own values file under [`helm/istio/`](./helm/istio/) so you can configure them independently.

| Chart | Release name | Values file | Role |
|---|---|---|---|
| `istio/base` | `istio-base` | [`values-base.yaml`](./helm/istio/values-base.yaml) | CRDs and the validating webhook |
| `istio/istiod` | `istiod` | [`values-istiod.yaml`](./helm/istio/values-istiod.yaml) | Control plane (Pilot) |
| `istio/cni` | `istio-cni` | [`values-cni.yaml`](./helm/istio/values-cni.yaml) | CNI plugin — programs in-pod redirection for ambient |
| `istio/ztunnel` | `ztunnel` | [`values-ztunnel.yaml`](./helm/istio/values-ztunnel.yaml) | Per-node L4 proxy DaemonSet (ambient data plane) |

The version is pinned in [`scripts/install-istio.sh`](./scripts/install-istio.sh) (currently `1.30.0`) so the tutorial is reproducible. Run:

```sh
# Install Istio (ambient) via Helm
./scripts/install-istio.sh
```

Verify the control plane and data plane are up:

```sh
# Verify istio-system pods are running
kubectl -n istio-system get pods
```

You should see `istiod`, `istio-cni-node` (one per node), and `ztunnel` (one per node). To change any setting — say, the istiod resource requests — edit the matching values file and re-run the script; `helm upgrade --install` will apply the diff.

Uninstall with:

```sh
# Uninstall Istio
./scripts/uninstall-istio.sh
```

### Step 2 — Test workloads (httpbin + netshoot)

See [`diagrams/step-2.excalidraw`](./diagrams/step-2.excalidraw) and [`steps/step-2-skill.md`](./steps/step-2-skill.md) for the data path this step exercises.

We need something to actually push traffic through the mesh. Two minimal in-mesh pods, deliberately scheduled on **different nodes** so requests cross the ztunnel-to-ztunnel mTLS path:

| Workload | Namespace | Role | Pinned to |
|---|---|---|---|
| `httpbin` ([`mccutchen/go-httpbin`](https://github.com/mccutchen/go-httpbin)) | `httpbin` | server — echoes request headers, status codes, etc. | `istio-ambient-worker` |
| `netshoot` ([`nicolaka/netshoot`](https://github.com/nicolaka/netshoot)) | `netshoot` | client — has `curl`, `tcpdump`, `dig`, `mtr`, … | `istio-ambient-worker2` |

Both namespaces carry the label `istio.io/dataplane-mode=ambient`, which opts every pod inside them into the data plane — no per-pod annotation needed.

> **Key label — enable ambient**: `istio.io/dataplane-mode=ambient` on the Namespace (or on a single Pod). Without it, ztunnel won't intercept traffic for those workloads. This is the *only* thing that makes a pod ambient-mesh-aware.

```sh
# Deploy httpbin and netshoot
kubectl apply -f samples/httpbin.yaml -f samples/netshoot.yaml
kubectl -n httpbin   rollout status deploy/httpbin
kubectl -n netshoot  rollout status deploy/netshoot
```

Send a request from netshoot to httpbin — traffic flows `netshoot → ztunnel (worker 2) → ztunnel (worker 1) → httpbin`, with mTLS·HBONE only on the middle (ztunnel-to-ztunnel) hop:

```sh
# Call httpbin from netshoot (traffic crosses ztunnel mTLS)
kubectl -n netshoot exec deploy/netshoot -- \
  curl -s httpbin.httpbin.svc.cluster.local:8000/headers
```

Tear the workloads down with:

```sh
# Tear down the test workloads
kubectl delete -f samples/httpbin.yaml -f samples/netshoot.yaml
```

### Step 3 — Ingress gateway (Gateway API)

Brings up an Istio ingress gateway declared as a **Kubernetes Gateway API** `Gateway` (not the legacy Istio `gateway.networking.istio.io` CRD), pins the data-plane pod to the kind control-plane node so it inherits the `hostPort: 80` mapping, exposes httpbin through an HTTPRoute, and reaches it from your host with `curl localhost`. Traffic flow this step exercises: **host → gateway (L7) → mesh → httpbin**.

Istio doesn't bundle the Gateway API CRDs, so install them first:

```sh
# Install the Gateway API standard CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

#### Create the Gateway

```sh
# Apply the Gateway — Istio auto-creates a Deployment + Service named "ingress-istio"
kubectl apply -f samples/ingress-gateway.yaml
kubectl -n istio-system wait --for=condition=Available deploy/ingress-istio --timeout=60s
```

The Service comes up as type `LoadBalancer` (stays `<pending>` in kind, which is fine — we use hostPort instead). The pod by default lands on a worker node, so it can't bind to the host's port 80.

#### Patch the gateway pod for kind reachability

```sh
# Move the pod to the control-plane node and bind hostPort 80 → containerPort 80
kubectl -n istio-system patch deploy ingress-istio --patch-file samples/ingress-gateway-patch.yaml
kubectl -n istio-system wait --for=condition=Ready pod -l 'gateway.networking.k8s.io/gateway-name=ingress' --timeout=60s
```

The patch adds `nodeSelector: ingress-ready=true` (the label set in [`kind/cluster.yaml`](./kind/cluster.yaml)) plus a control-plane toleration, and gives the istio-proxy container a `containerPort: 80, hostPort: 80` entry so kubelet binds the node's port 80 to it.

> **Why the control-plane node?** Only that node has `hostPort 80` mapped to the host in kind — a tutorial shortcut. In a real cluster the gateway would run on a worker behind a load balancer.

#### Expose httpbin via HTTPRoute

```sh
# HTTPRoute (in the httpbin namespace) binds the httpbin Service to the Gateway under hostname httpbin.local
kubectl apply -f samples/httpbin-route.yaml
```

The HTTPRoute's `parentRefs` crosses namespaces (it lives in `httpbin` and references the Gateway in `istio-system`). The Gateway allows this because its `allowedRoutes.namespaces.from: All`.

#### Test from the host

```sh
# Request goes: Mac:80 → kind control-plane:80 → gateway (L7) → ztunnel → httpbin
curl -s -H "Host: httpbin.local" http://localhost/headers
```

You'll see `X-Envoy-*` and `X-Forwarded-*` headers in the response — these are added by the gateway (L7). The hop from the gateway to httpbin is still ambient mTLS via ztunnel.

> **Why `-H "Host: httpbin.local"` and not `http://httpbin.local/headers`?** `httpbin.local` isn't registered in DNS or `/etc/hosts`, so curl can't resolve it. We connect to `localhost` (which does resolve) and forge the `Host:` header so the gateway's Envoy picks the right `HTTPRoute`. To skip the flag, add `127.0.0.1 httpbin.local` to `/etc/hosts`.

#### Tear down

```sh
# Remove the HTTPRoute, the Gateway, and the Gateway API CRDs
kubectl delete -f samples/httpbin-route.yaml
kubectl delete -f samples/ingress-gateway.yaml
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

### Step 4 — Waypoint proxy in the httpbin namespace

A **waypoint** is Istio ambient's optional **L7 proxy**. ztunnel does L4 only (mTLS, identity, simple policy); anything HTTP-aware — route rules, retries, fault injection, AuthorizationPolicy on path/method/headers, JWT validation — needs an Envoy. The waypoint *is* that Envoy, scoped per namespace (or per service / per workload). When httpbin's namespace is labelled to use a waypoint, every request to a service in it goes through the waypoint before reaching the workload's ztunnel.

```sh
# Deploy the waypoint and patch the httpbin namespace to use it
kubectl apply -f samples/waypoint.yaml
kubectl -n httpbin wait --for=condition=Available deploy/waypoint --timeout=60s
```

The manifest does two things:
1. Patches the `httpbin` Namespace, adding `istio.io/use-waypoint: waypoint` (the existing `istio.io/dataplane-mode: ambient` label is preserved by the apply).

> **Key label — route through a waypoint**: `istio.io/use-waypoint=<waypoint-name>` on the Namespace (or per Service / per Pod). The value is the name of the `Gateway` resource that backs the waypoint. Without this label the waypoint pod exists but no traffic is steered through it.
2. Declares a Kubernetes `Gateway` named `waypoint` with class `istio-waypoint`. Istio's gatewayClass controller auto-creates a Deployment + Service named `waypoint` listening on port 15008 (HBONE).

Verify the pod is up and the namespace label is set:

```sh
kubectl -n httpbin get pod -l gateway.networking.k8s.io/gateway-name=waypoint -o wide
kubectl get ns httpbin -o jsonpath='{.metadata.labels.istio\.io/use-waypoint}{"\n"}'
```

Re-run the curl from step 3 — it works the same from your perspective, but the data path now includes the waypoint: `host → gateway → waypoint → ztunnel (worker 1) → httpbin`.

```sh
curl -i -H "Host: httpbin.local" http://localhost/headers
```

Tear down with:

```sh
kubectl delete -f samples/waypoint.yaml
```

### Step 5 — Route gateway traffic through the waypoint

By default, Istio's ingress gateway **bypasses** the waypoint when forwarding to mesh workloads. The gateway is itself an L7 Envoy, so Istio assumes one L7 hop is enough and routes the request directly from the gateway to the destination ztunnel — the waypoint pod exists but no gateway traffic reaches it.

To opt-in for `gateway → waypoint → ztunnel → pod` routing, label the destination namespace (or Service) with `istio.io/ingress-use-waypoint=true`. The updated `samples/waypoint.yaml` includes this label on the `httpbin` namespace.

```sh
# Re-apply with the new label
kubectl apply -f samples/waypoint.yaml
```

> **Key label — route gateway traffic through the waypoint**: `istio.io/ingress-use-waypoint=true` on the destination Namespace (or per Service). Without it, gateway-originated traffic skips the waypoint even when `istio.io/use-waypoint` is set on the namespace.

Verify by hitting the gateway again:

```sh
curl -i -H "Host: httpbin.local" http://localhost/headers
```

Compare the response headers to step 4's: with the label in place, the request now traverses the waypoint as an additional L7 hop before reaching httpbin.

### Step 6 — Kiali (the mesh console)

Kiali draws a live **service-graph** from Prometheus metrics and validates your Istio config. The graph is *derived from metrics*, not sniffed from the wire — so Prometheus is a hard dependency, and what shows up is exactly what the proxies report. See [`KIALI.md`](./KIALI.md) for the concepts and [`OBSERVABILITY.md`](./OBSERVABILITY.md) for the metrics behind it.

Install Prometheus (the metrics backend) and Kiali, pinned to the same release as Istio (`1.30`):

```sh
# Kiali needs Prometheus first
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/kiali.yaml
kubectl -n istio-system rollout status deploy/kiali
```

The graph is built from request-rate metrics, so it decays without traffic — drive some through the gateway first:

```sh
# Generate ~1 min of traffic so edges appear in the graph
for i in $(seq 1 200); do curl -s -H "Host: httpbin.local" http://localhost/headers >/dev/null; sleep 0.3; done
```

Open the dashboard and select the **httpbin** namespace in the *Graph* view:

```sh
istioctl dashboard kiali
```

This step is where the ambient L4/L7 split becomes visible. With steps 4–5's waypoint in place, the httpbin edge shows full **L7** detail — request rate, error %, and a **lock** (mTLS). Toggle the **ztunnel** and **waypoint** infrastructure nodes in the graph display options to see the real `gateway → waypoint → ztunnel → httpbin` path rather than a single logical edge.

> **Ambient gotcha**: a **locked but TCP-only** edge (lock, no RPS/error %) means traffic is secured by ztunnel but *no waypoint is parsing L7*. Remove the waypoint (`kubectl delete -f samples/waypoint.yaml`) and the same edge falls back to TCP-only — the clearest demonstration that L4 comes from ztunnel and L7 from the waypoint. Re-apply to light L7 back up.

Tear down with:

```sh
# Remove Kiali and Prometheus
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/kiali.yaml
kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/prometheus.yaml
```
