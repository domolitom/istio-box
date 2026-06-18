# Load Testing

Load testing pushes synthetic traffic at a service to measure how it behaves under
pressure — throughput, latency percentiles, error rate. In a mesh you do it for two
distinct reasons: to **size the mesh overhead** (what do ztunnel and the waypoint cost
you?) and to **feed traffic to automation** (Flagger needs requests to judge a canary).

## What you're actually measuring

A request in ambient mode crosses more hops than a bare pod:

```
client → ztunnel (src node) → [waypoint, if L7] → ztunnel (dst node) → server
```

Each hop adds latency and CPU. Load testing tells you the *real* numbers for your
workload rather than the synthetic ones from a benchmark blog. Watch:

- **p50 vs p99** — the mean hides tail latency; mesh overhead shows up first in the tail.
- **CPU of ztunnel / waypoint** — the data plane is what you're paying for. Correlate
  `kubectl top pod` with the load.
- **Error rate under saturation** — where retries, timeouts, and circuit breakers kick in.

> Always compare **with mesh vs without** (move the namespace out of ambient, or hit the
> pod directly) so you can attribute the delta to Istio and not to the app.

## Tools

| Tool | Niche |
|---|---|
| [`fortio`](https://github.com/fortio/fortio) | Istio's own load generator — QPS-driven, prints latency histograms, has an HTTP UI. The default choice in the mesh world, the tool used throughout *Istio in Action* (Ch. 6 drives it to trip circuit breakers), and what Flagger's load tester runs under the hood. |
| [`k6`](https://k6.io) | Scriptable (JS) scenarios, good for realistic multi-step traffic and CI gates. |
| [`hey`](https://github.com/rakyll/hey) / [`wrk`](https://github.com/wg/wrk) | Quick one-shot CLI benchmarks when you just want a number. |

Fortio is QPS-oriented (hold a target rate and report latency), `wrk` is
connections-oriented (saturate and report throughput) — pick by the question you're asking.

## Driving it from inside the mesh

Run the generator **inside** an ambient namespace so the traffic actually crosses ztunnel
(an external `hey` from your laptop hits the gateway, not the L4 path). Fortio as a quick
in-cluster client:

```sh
# 50 QPS for 30s from an ambient pod to httpbin, with a latency histogram
kubectl -n netshoot exec deploy/netshoot -- \
  fortio load -qps 50 -t 30s -c 8 \
  http://httpbin.httpbin.svc.cluster.local:8000/get
```

(`netshoot` doesn't ship `fortio`; either use a `fortio/fortio` pod or swap in `hey`.)
Then read the histogram's p99 and check `istioctl proxy-config` / `kubectl top` on the
ztunnel and waypoint pods during the run.

## Relation to Flagger

Flagger's `analysis.webhooks` include a **load tester** that synthesizes traffic on each
canary step — otherwise a low-traffic service generates no metrics and the analysis stalls
with "no values found". That load tester is Fortio. See [`FLAGGER.md`](./FLAGGER.md).

## Pitfalls

- **Test from inside the mesh**, or you measure the gateway, not the ambient path.
- **Open vs closed model**: a fixed-QPS run (open) exposes saturation; a fixed-connections
  run (closed) backs off when the server slows, hiding it. Use open-model for capacity work.
- **Warm up** — first requests pay JIT, cache, and connection-setup costs. Discard them.
- **The client can be the bottleneck** — if the generator's own CPU saturates, your numbers
  are about the client, not the server.

## Refs

- https://github.com/fortio/fortio
- https://istio.io/latest/docs/ops/deployment/performance-and-scalability/
- https://k6.io/docs/
