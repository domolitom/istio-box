# Monitoring — Prometheus + Grafana

Where [`OBSERVABILITY.md`](./OBSERVABILITY.md) covers *what* Istio emits, this is the operational side: how to **scrape** it with Prometheus and **chart** it in Grafana, and what changes when the data plane is ambient.

## The quick way (demo addons)

Good enough for this sandbox; do **not** use in production (no persistence, no HA, in-cluster only):

```sh
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/grafana.yaml
kubectl -n istio-system rollout status deploy/prometheus deploy/grafana

istioctl dashboard grafana      # opens Grafana, Istio dashboards pre-provisioned
istioctl dashboard prometheus   # raw PromQL
```

The addon Prometheus ships with the scrape jobs below already wired and Grafana with the Istio dashboards provisioned. For anything real, point an existing Prometheus / `kube-prometheus-stack` at the same targets instead.

## What Prometheus scrapes in ambient

The targets differ from sidecar mode — there are no per-pod Envoy sidecars to scrape. Sources:

| Target | Port / path | Provides |
|---|---|---|
| **ztunnel** (DaemonSet, every node) | `15020/stats/prometheus` | **L4** metrics for *all* ambient workloads — TCP bytes, connections, mTLS status |
| **waypoint** proxies | `15020/stats/prometheus` | **L7** metrics (`istio_requests_total`, durations, codes) for namespaces/services that have one |
| **istiod** | `15014/metrics` | control-plane — xDS push latency, config convergence, cert issuance |
| ingress/egress gateways | `15020/stats/prometheus` | edge L7 metrics |

Discovery is the standard Istio annotation contract: Prometheus finds these via `prometheus.io/scrape` + `prometheus.io/port` on the pods, merged with app metrics on `15020`. **No sidecar means no per-app-pod scrape job** — the L7 signal lives on the waypoint, not the workload.

## Grafana dashboards

The bundled Istio dashboards work unchanged on top of the scraped metrics:

- **Istio Mesh / Service / Workload** — golden signals (rate, errors, duration) per service and workload. Populated only where L7 metrics exist (i.e. behind a waypoint).
- **Istio Control Plane** — istiod health, push/convergence latency, connected proxies.
- **Ztunnel** — the ambient-specific one: per-node connections, bytes, and mTLS handshake stats from the ztunnel DaemonSet. This is your L4 view even where no waypoint is deployed.

Import IDs (if not using the addon's provisioned set): grafana.com dashboards **7639** (Mesh), **7636** (Service), **7630** (Workload), **7645** (Control Plane), **21306** (Ztunnel).

## Ambient gotcha: empty service/workload panels

Same root cause as the Kiali graph (see [`KIALI.md`](./KIALI.md)): **L7 metrics require a waypoint.**

- A Service / Workload dashboard that's blank for an ambient app usually means **no waypoint** on it, not a broken scrape. ztunnel reports the connection at L4 but never emits `istio_requests_total` with HTTP dimensions.
- The Ztunnel dashboard and L4 panels *should* be populated regardless — if those are empty too, then it's a real scrape problem (check the Prometheus **Targets** page).

Confirm the metric exists before debugging the panel:

```sh
# does the L7 metric exist for the workload at all?
kubectl -n istio-system exec deploy/prometheus -- \
  wget -qO- 'localhost:9090/api/v1/query?query=istio_requests_total{destination_workload="httpbin"}'
```

Empty result + no waypoint → add a waypoint (README step 4). Empty result + waypoint present → scrape/target issue.

## Cardinality

Istio's per-request labels (`source_workload`, `destination_service`, `response_code`, …) multiply fast. Use the `Telemetry` API to **drop** high-cardinality dimensions (or add only the ones you need) rather than letting Prometheus blow up — see the customizing note in [`OBSERVABILITY.md`](./OBSERVABILITY.md).

## Refs

- https://istio.io/latest/docs/ops/integrations/prometheus/
- https://istio.io/latest/docs/ops/integrations/grafana/
- https://istio.io/latest/docs/ambient/usage/observability/
