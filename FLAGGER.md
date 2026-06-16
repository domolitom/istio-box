# Istio + Flagger — progressive delivery

[Flagger](https://flagger.app) is a Kubernetes operator that automates canary / A-B / blue-green rollouts by shifting traffic and watching metrics, rolling back a bad release before it reaches everyone.

## How it works with Istio

You hand Flagger a `Deployment` via a `Canary` resource. Flagger then:

1. Clones it into `<name>-primary` (the stable version) and rewires the apex Service.
2. On each new revision, **gradually shifts `VirtualService` weight** primary → canary.
3. At every step queries Prometheus (success rate, latency). In range → bump weight; out of range → **roll back** and halt.
4. Once the canary holds full weight, promotes (syncs primary, routes 100% back).

You never edit the `VirtualService` — Flagger generates and reconciles it:

```yaml
http:
  - route:
      - { destination: { host: podinfo-primary }, weight: 90 }
      - { destination: { host: podinfo-canary  }, weight: 10 }
```

## The `analysis` knobs

`interval` (step cadence), `stepWeight` / `maxWeight` (how fast, how far), `threshold` (failed checks before rollback), `metrics` (`request-success-rate`, `request-duration`, or custom `MetricTemplate`), `webhooks` (lifecycle gates + the **load tester** that synthesizes traffic so there are metrics to judge).

## Need running

Flagger controller (`--set meshProvider=istio`) + Prometheus scraping Istio telemetry + (optional) load tester.

## Ambient caveat

Weighted HTTP routing is **L7**, so the service needs a **waypoint** to enforce the `VirtualService` (ztunnel alone can't split by weight). Metrics now come from the waypoint/ztunnel — confirm `MetricTemplate` label queries match. Verify with `istioctl proxy-config routes <waypoint-pod>` before trusting auto-rollback.

## Refs

- https://docs.flagger.app/tutorials/istio-progressive-delivery
- https://istio.io/latest/docs/tasks/traffic-management/traffic-shifting/
