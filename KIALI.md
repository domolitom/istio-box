# Kiali — the mesh console

[Kiali](https://kiali.io) is Istio's observability console: a live **service-graph topology**, per-service/workload health, mTLS status, and — uniquely — **config validation** of your Istio CRDs. It doesn't store anything itself; it stitches together three sources.

## Where its data comes from

| Source | What Kiali reads | Used for |
|---|---|---|
| **Prometheus** | `istio_*` request metrics | the traffic graph, health, golden-signal charts |
| **Kubernetes API** | Istio + Gateway API CRDs, workloads | config validation, the object views |
| **Tracing** (Jaeger/Tempo, optional) | spans | per-request drill-down from the graph |

No Prometheus → no graph. The graph is *derived from metrics*, not sniffed from the wire — so it shows exactly what the proxies report, no more (see the ambient caveat).

## What you actually use it for

- **Traffic graph** — who calls what, request rates, error %, and a **lock icon** per edge when `connection_security_policy=mutual_tls`. The fastest "is mTLS actually on?" check.
- **Config validation** — catches a `VirtualService` pointing at a host with no `DestinationRule` subset, an `AuthorizationPolicy` selecting nothing, orphaned Gateways, etc. Surfaced as warnings/errors on the object.
- **Health** — rolls up pod status + error-rate metrics per service/workload.

## Install (addon)

The repo pins Istio `1.30.0`; use the matching addon manifest. Kiali needs Prometheus first (see [`OBSERVABILITY.md`](./OBSERVABILITY.md)).

```sh
# Prometheus + Kiali addons for the pinned release
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/kiali.yaml
kubectl -n istio-system rollout status deploy/kiali

# Open the dashboard
istioctl dashboard kiali
```

## Ambient

Kiali's graph is only as complete as the metrics behind it, and in ambient the **emitter depends on the hop**:

- **L4 edges** (TCP bytes, connections, mTLS lock) come from **ztunnel** for every ambient workload — no waypoint, no injection needed. So even a bare ambient namespace shows up with secured edges.
- **L7 detail** (HTTP request rates, response codes, per-route latency) needs a **waypoint**. Without one, ztunnel reports the connection but not `istio_requests_total` with HTTP dimensions — Kiali draws the edge as **TCP-only**: no error %, no RPS, no HTTP health. This reads like "missing traffic" but it's a missing waypoint, not a Kiali bug.
- Recent Kiali versions render **ztunnel and waypoint as infrastructure nodes** in the graph (toggle in the graph display options), so you can see the `client → ztunnel → ztunnel → server` (and `→ waypoint →`) path rather than just a logical app edge.

> **Rule of thumb**: an ambient edge with a lock but no HTTP stats = traffic is secured (ztunnel) but no waypoint is parsing L7. Add a waypoint on the destination (see README step 4) to light up the L7 view.

Confirm the underlying metric exists with a direct Prometheus query before blaming the graph.

## Refs

- https://kiali.io/docs/
- https://istio.io/latest/docs/tasks/observability/kiali/
- https://kiali.io/docs/features/ambient/
