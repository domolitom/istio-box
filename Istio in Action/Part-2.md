# Part 2 — Securing, observing, and controlling your service's network traffic

*Istio in Action* (Posta & Maloku, Manning). Part 2 is the working core of the
book — the Envoy data plane, getting traffic in, routing, resilience,
observability, and security.

> Note: this project runs Istio in **ambient mode** (ztunnel + waypoints, no
> sidecars), while the book is **sidecar**-based. Most of this part maps cleanly:
> L4 (mTLS, identity, basic routing) moves into ztunnel; L7 (gateways, retries,
> traffic shifting, `VirtualService`/`DestinationRule`) needs a **waypoint**.

## Ch. 3 — Istio's data plane: the Envoy proxy

Envoy is the proxy Istio configures. Core nouns: **listeners** (ports it accepts
on), **routes** (match → cluster), **clusters** (upstream service + LB policy),
**endpoints** (the actual instances). Istio's value-add is feeding these
dynamically over **xDS** (LDS/RDS/CDS/EDS) from istiod instead of static config.
Envoy also does the resilience primitives in hardware-agnostic C++: retries,
timeouts, circuit breaking, observability.

## Ch. 4 — Istio gateways: getting traffic into a cluster

North-south ingress. A **`Gateway`** resource binds a port/protocol/host on the
ingress gateway proxy; a **`VirtualService`** attaches routing rules to it. TLS
options: simple (server) and **mutual** TLS termination at the edge. The gateway
is just an Envoy with no app beside it. (Ambient: the ingress gateway / Gateway
API plays this role, and you route gateway traffic *through* a waypoint for L7.)

## Ch. 5 — Traffic control: fine-grained routing

The two workhorse resources:

- **`VirtualService`** — match requests (headers, path, weight) and route them.
- **`DestinationRule`** — define **subsets** (e.g. `v1`/`v2` by label) and
  per-destination policy (LB, connection pools, outlier detection).

Patterns: **dark launch** (route internal/test traffic to a new version),
**canary / traffic shifting** by weight, and header/cookie-based routing. Combine
with outlier detection to eject bad endpoints.

## Ch. 6 — Resilience: solving application networking challenges

Push resilience out of the app and into the proxy:

- **Timeouts & retries** (with per-try timeout, retry budgets, retriable codes).
- **Circuit breaking** via `DestinationRule` connection pools (max connections /
  pending requests) and **outlier detection** (eject hosts that error).
- **Fault injection** — deliberately inject delays/aborts to test resilience.

Key point: these are client-side, applied by the *caller's* proxy.

## Ch. 7 — Observability: understanding service behavior

Istio's proxies emit consistent **metrics** (requests, latency, sizes) for free.
istiod exposes its own control-plane metrics. Standard (golden) signals come out
of the box; you can **customize and extend Istio's metrics** (new dimensions, new
metrics) via Telemetry/EnvoyFilter without touching apps. Scraped by Prometheus.

## Ch. 8 — Observability: visualizing network behavior

The dashboards on top of those metrics:

- **Grafana** — time-series dashboards (per-service / per-workload).
- **Jaeger** — distributed tracing; apps must **propagate trace headers**
  (b3/W3C) for spans to stitch together — Istio can't infer causality.
- **Kiali** — live service-graph topology, config validation, and health.

## Ch. 9 — Securing microservice communication

The security payoff:

- **Identity** — each workload gets a **SPIFFE** ID, delivered as an X.509 cert
  (SVID); istiod is the CA. This is the basis of mTLS.
- **mTLS** — `PeerAuthentication` sets the mode (`PERMISSIVE` during migration →
  `STRICT`). Encrypts and authenticates service-to-service traffic transparently.
- **Authorization** — `AuthorizationPolicy` (ALLOW/DENY/CUSTOM) gates access by
  source identity, namespace, method, path, etc. Deny-by-default once a policy
  selects a workload.
- **End-user auth** — `RequestAuthentication` validates JWTs; pair with an
  `AuthorizationPolicy` on claims.

(Ambient: ztunnel does mTLS + L4 `AuthorizationPolicy` for the whole namespace;
L7 policy and JWT auth require a waypoint.)

## Takeaway

Part 2 is Istio doing its job: route and shift traffic declaratively, stay
resilient under failure, see everything without app changes, and get
zero-trust mTLS + identity-based authz for free.
