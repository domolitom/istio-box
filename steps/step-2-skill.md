# Step 2 — Test workloads (httpbin + netshoot)

Companion spec for `diagrams/step-2.excalidraw`. Extends step 1 by filling in the abstract "app pod" slots with real workloads we can actually call: **httpbin** on worker 1 (the server / header dumper) and **netshoot** on worker 2 (the client, with curl + tcpdump for inspection). The diagram differs from step 1 in only five places — everything else (boundaries, ztunnels, istio-cni, istiod, colors) is identical and intentionally so.

## Differences from step 1

| Element | Step 1 | Step 2 |
|---|---|---|
| Title | "Step 1 · Initial setup" | "Step 2 · Test workloads" |
| Subtitle | "kind cluster · 1 control-plane + 2 workers · istio ambient installed" | "netshoot (worker 2) → httpbin (worker 1) — observing the cross-node mTLS" |
| Worker 1 middle slot | generic "app pod (in mesh)" | **httpbin** |
| Worker 2 middle slot | generic "app pod (in mesh)" | **netshoot** |
| Arrow direction | left → right (app1 → app2, hypothetical) | right → left (netshoot → httpbin, the real test call) |

## Data path (read right to left, following the arrows)

The arrows are reversed compared to step 1 because the client (netshoot) lives on worker 2 and the server (httpbin) on worker 1 — that's how the manifests in `samples/` pin them. The three hops:

1. **netshoot → ztunnel (worker 2)**: dashed slate, "plain TCP · no mTLS". The pod's outbound TCP is intercepted by istio-cni's redirect rules and steered to the local node's ztunnel without leaving the node.
2. **ztunnel (worker 2) → ztunnel (worker 1)**: solid green, "mTLS · HBONE". The only encrypted hop — HBONE (HTTP/2 CONNECT) carrying mTLS over the pod network.
3. **ztunnel (worker 1) → httpbin**: dashed slate, "plain TCP · no mTLS". Local hop on the destination node.

## Visual contract — preserved from step 1

- `dashed slate = plain TCP`, `solid thick green = mTLS · HBONE`.
- App pods stay as green ellipses (in-mesh, eligible for mTLS).
- Three node boundaries unchanged in size, shape, and position.

## How to verify the mTLS claim

```sh
# Send a request from netshoot to httpbin (returns the request headers httpbin received):
kubectl -n netshoot exec deploy/netshoot -- curl -s httpbin.httpbin.svc.cluster.local:8000/headers

# Find the ztunnel pod on worker 1, then tcpdump its HBONE port (15008):
ZTUNNEL_W1=$(kubectl -n istio-system get pod -l app=ztunnel -o jsonpath='{.items[?(@.spec.nodeName=="istio-ambient-worker")].metadata.name}')
kubectl -n istio-system exec "$ZTUNNEL_W1" -- tcpdump -i any -n -X port 15008
```

You should see TLS handshakes and encrypted payloads on port 15008 — proof that the middle hop is mTLS. The pod-↔-ztunnel hops use loopback / node-local sockets and won't show up there.

## Intentionally still omitted (later steps)

- An out-of-mesh pod calling httpbin for contrast (plaintext, no green ellipse).
- L7 routing via a waypoint proxy.
- AuthorizationPolicy restricting which client identities can call httpbin.
- SPIFFE identity strings shown on the mTLS link.
