# Observability

Istio's proxies sit on every hop, so they can emit consistent telemetry for *all* service traffic without touching application code. This covers the two observability chapters of *Istio in Action* — Ch. 7 (metrics) and Ch. 8 (visualizing) — and what changes in ambient mode.

## The three pillars

| Pillar | What it answers | Istio's source |
|---|---|---|
| **Metrics** | How much / how fast / how often failing? | proxy-emitted, scraped by Prometheus |
| **Traces** | Where did *this* request spend its time? | proxy-generated spans → Jaeger |
| **Logs** | What exactly happened on one request? | Envoy access logs |

Metrics are aggregate (cheap, always on); traces follow a single request across services (sampled); logs are the per-request detail.

## Metrics (Ch. 7)

Every Istio proxy reports request-level metrics with consistent labels, so you get the **four golden signals** out of the box:

- **`istio_requests_total`** — request count (rate → traffic; by response code → errors).
- **`istio_request_duration_milliseconds`** — latency histogram (saturation shows up here too).
- **`istio_request_bytes` / `istio_response_bytes`** — payload sizes.

Each carries dimensions like `source_workload`, `destination_service`, `response_code`, `connection_security_policy` (e.g. `mutual_tls`) — enough to slice traffic by who/what/how without app changes. istiod also exposes its own **control-plane** metrics (xDS push latency, config convergence, cert issuance).

**Customizing** — the `Telemetry` API (and, for deeper changes, `EnvoyFilter`) lets you add dimensions to standard metrics or define new ones. Use it to tag a metric with a request header, or drop a high-cardinality label that's blowing up Prometheus.

Prometheus scrapes the proxies; everything downstream (Grafana, Kiali, alerting) reads from there.

## Visualizing (Ch. 8)

Three tools stack on top of the same metrics/traces:

- **Grafana** — time-series dashboards. Istio ships per-service, per-workload, and control-plane dashboards built on the golden-signal metrics.
- **Jaeger** (or Zipkin) — distributed tracing. The proxy creates spans, but **apps must propagate the trace headers** (`b3` or W3C `traceparent`) from inbound to outbound requests. Istio can't infer causality across a hop — drop the headers and the trace fragments into disconnected spans.
- **Kiali** — live service-graph topology from the metrics, plus config validation and health. The "what's talking to what, and is it healthy" view.

Tracing is **sampled** (default ~1%); raise the rate for debugging, lower it for cost. Sampling is a control-plane setting, not per-request.

## Ambient caveat

The telemetry source shifts with the data plane:

- **L4 metrics** (TCP bytes, connections, mTLS status) come from **ztunnel** for the whole namespace, no proxy injection needed.
- **L7 metrics** (HTTP codes, paths, per-route latency) require a **waypoint** — ztunnel doesn't parse L7. No waypoint → no `istio_requests_total` with HTTP dimensions for that service.
- **Tracing** spans for L7 originate at the waypoint; the app-side header-propagation requirement is unchanged.

So when a Grafana panel or `MetricTemplate` query comes back empty in ambient, the usual cause is **no waypoint** on the workload, not a scrape problem. Confirm the metric exists with `istioctl` / a direct Prometheus query before debugging the dashboard.

## Refs

- https://istio.io/latest/docs/tasks/observability/
- https://istio.io/latest/docs/tasks/observability/metrics/customize-metrics/
- https://istio.io/latest/docs/ambient/usage/observability/
