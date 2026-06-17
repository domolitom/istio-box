# Request Hedging

Request hedging is a tail-latency optimization: if a request to an upstream is taking too long, send a **second** copy to another endpoint and use whichever response comes back first. It trades a little extra load for a tighter p99.

## Why it exists

In any fleet, a few replicas are momentarily slow — GC pause, cold cache, a noisy neighbour. Retries only help *after* a request fails; hedging helps when a request is just *slow but not yet failed*. By racing a backup request, you stop one straggler replica from dominating your tail latency.

## How it differs from retries

| | Retry | Hedge |
|---|---|---|
| Trigger | response failed (5xx, reset, timeout) | request exceeds a time threshold |
| Original | abandoned | left in flight, races the new one |
| Goal | recover from failure | cut tail latency |

Hedging is essentially a *speculative* retry fired before the first attempt has finished.

## In Istio / Envoy

Envoy implements hedging via the retry policy — it is "hedging on a per-try timeout". The first attempt is left running; when its per-try timeout elapses, Envoy issues another attempt to a different host and returns the first response to arrive.

Key knobs (Envoy `HedgePolicy` / route retry config):

- **`hedge_on_per_try_timeout`** — fire a hedged attempt when the per-try timeout fires, instead of only on a hard failure.
- **per-try timeout** — the threshold that decides "too slow"; set it near your normal p95–p99, not the overall timeout.
- **retry budget / `num_retries`** — bounds how many extra requests can be in flight, capping the load amplification.

Note: at the Istio API level there is no first-class "hedge" field on `VirtualService` — hedging is configured through Envoy's retry policy (per-try timeout + hedge-on-per-try-timeout), often applied with an `EnvoyFilter`.

## When to use it

Good fit:

- **Idempotent, read-mostly** calls (GETs, lookups) where a duplicate is harmless.
- Latency-sensitive paths fronting a fleet with occasional slow replicas.

Avoid when:

- The operation is **non-idempotent** (writes, payments) — a duplicate could double-apply.
- The upstream is already **saturated** — hedging adds load exactly when you can least afford it, risking a feedback loop. Keep a strict retry budget.

## Rule of thumb

Set the per-try timeout so only the slow tail gets hedged (e.g. p95). If you hedge everything, you've just doubled your traffic for nothing.
