# Part 1 — Understanding Istio

*Istio in Action* (Posta & Maloku, Manning). Part 1 is the foundation — two
chapters, no deep config yet.

> Note: this project runs Istio in **ambient mode** (ztunnel + waypoints, no
> sidecars), while the book is **sidecar**-based. The concepts below map across;
> the data-plane mechanics differ.

## Ch. 1 — Introducing the Istio service mesh

**The problem.** Moving from monoliths to distributed services makes the network
the weak link: unreliable, slow, constantly changing. Every service needs service
discovery, load balancing, retries, timeouts, circuit breaking, mTLS, and
telemetry just to talk to its neighbors safely.

**The old answer and why it failed.** These concerns used to be baked into the app
via language-specific libraries (the Netflix OSS stack — Hystrix, Ribbon, Eureka).
That couples networking logic to the app, forces a library per language, and drifts
out of sync across teams and versions.

**The service-mesh idea.** Push application-networking concerns *out* of the app and
*down* into the infrastructure:

- **Data plane** — Envoy proxies beside each service (sidecars), transparently
  intercepting traffic (iptables). They do discovery, LB, retries, timeouts,
  circuit breaking, mTLS, metrics.
- **Control plane** — `istiod`, which configures all proxies from high-level
  intent. (Earlier Istio split this into Pilot/Citadel/Galley; later consolidated.)

**What Istio gives you:** traffic management (routing, canary, shifting),
resilience, observability (metrics/traces/logs), and security (mTLS + SPIFFE-based
workload identity, authn/authz). Runs naturally on Kubernetes but isn't limited to
it (VM support).

**The cost.** Extra network hops add latency, sidecars consume resources, and you
now have a mesh to operate. A mesh is for service-to-service (east-west) traffic —
not a re-centralized ESB.

## Ch. 2 — First steps with Istio

A hands-on tour using the book's sample apps (`catalog` / `webapp`):

- **Install** `istioctl`, apply the demo profile; you get `istiod` plus
  ingress/egress gateways.
- **Sidecar injection** — automatic via the `istio-injection=enabled` namespace
  label, or manual with `istioctl kube-inject`.
- **Get traffic in** — expose a service with an Istio `Gateway` + `VirtualService`.
- **Observability** — install the Prometheus/Grafana/Jaeger/Kiali addons; see
  metrics, distributed traces, and the Kiali service graph with zero app changes.
- **Resilience & routing demos** — fault injection, retries/timeouts on a
  `VirtualService`, header-based routing, and traffic shifting between versions.

## Takeaway

A mesh moves cross-cutting networking *out of your code*. Istio realizes it with
Envoy (data plane) + istiod (control plane).
