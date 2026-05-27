# Step 1 — Cluster state diagram

Companion spec for `diagrams/step-1.excalidraw`. Describes the visual intent in plain English so the diagram can be maintained, extended, or recreated from this document.

## What this diagram shows

A snapshot of the kind cluster right after Istio ambient is installed via Helm. The headline argument is the data-flow story: **pods in the mesh don't talk to each other directly**; their traffic flows through the local node's ztunnel, and **mTLS only exists between ztunnels** — not between a pod and its local ztunnel.

## Layout

- **Title** top-left at y≈30: "Step 1 · Initial setup" — title-blue, 24px.
- **Subtitle** just below at y≈68: "kind cluster · 1 control-plane + 2 workers · istio ambient installed" — slate body, 14px.

- **Three node boundaries** show the kind cluster's full topology (1 control-plane + 2 workers), each drawn as a thin dashed rectangle with no fill, labeled in title-blue at its top-left:
  - **node · control-plane** at the top, sized like the worker boundaries: contains the per-node **ztunnel** at the top (DaemonSet, runs on every node) and **istiod** in the middle slot (the Deployment that only runs here).
  - **node · worker 1** and **node · worker 2** below the control-plane node, side-by-side, holding the data-plane components.

The control-plane node sits visually above the workers — that vertical position conveys the control/data plane hierarchy without needing an explicit arrow.

- **Inside each worker**, vertically stacked on the node's horizontal centerline:
  1. **ztunnel** rectangle at the top (y≈290) — primary-blue fill, white "ztunnel" text. Represents the per-node ztunnel pod from the `ztunnel` DaemonSet.
  2. **app pod** ellipse in the middle (y≈380) — success-green fill, green stroke, dark text "app pod\n(in mesh)". Green encodes "in-mesh, eligible for mTLS".
  3. **istio-cni** rectangle at the bottom (y≈520) — tertiary light-blue fill, dark text. Drawn separately from the data path because its role is plumbing (it installs the traffic-redirect rules on the node), not part of the flow itself.

## Arrows — the data-flow story

The diagram traces a **single forward request: app1 → app2**. Each arrow is unidirectional (one arrowhead) so the path is unambiguous. The reply would simply traverse the same components in reverse.

The three hops, in order:

1. **app1 → ztunnel1** (vertical, inside worker 1): **dashed slate** arrow, strokeWidth 2, arrowhead at ztunnel1. A slate **"plain TCP · no mTLS"** label sits next to it. Plain TCP — istio-cni's node-level redirect steers the pod's traffic to the local ztunnel without leaving the node.
2. **ztunnel1 → ztunnel2** (horizontal, spanning the worker boundaries and the gap): **solid thick green** arrow (strokeWidth 3), arrowhead at ztunnel2, with a green **"mTLS · HBONE"** label above. The only encrypted segment — HBONE (HTTP/2 CONNECT) carrying mTLS between the two ztunnels.
3. **ztunnel2 → app2** (vertical, inside worker 2): mirror of hop 1 — **dashed slate** arrow, arrowhead at app2, with a slate **"plain TCP · no mTLS"** label. Plain TCP again on the destination node.

The complete data path is **app1 → zt1 → zt2 → app2**. mTLS exists only on the middle hop; the pod-ztunnel hops on either side are plaintext.

**Visual contract**: `dashed slate = unencrypted` and `solid thick green = mTLS`. Preserve this encoding across all future steps.

## Color palette

| Element | Fill | Stroke | Text |
|---|---|---|---|
| Title | — | — | `#1e40af` |
| Subtitle, captions, plain arrows | — | `#64748b` | `#64748b` |
| istiod, ztunnel | `#3b82f6` | `#1e3a5f` | `#ffffff` |
| istio-cni | `#93c5fd` | `#1e3a5f` | `#374151` |
| App pod (in mesh) | `#a7f3d0` | `#047857` | `#374151` |
| mTLS arrow and label | — | `#047857` | `#047857` |

## Intentionally omitted (to be added in later steps)

- An istiod → ztunnel arrow showing the xDS config push (control plane wire).
- The concrete istio-cni mechanism (socket-redirect / iptables) visualized.
- A waypoint proxy and the L7 path traffic takes when a service has one.
- An out-of-mesh pod for contrast (no green fill, no mTLS connection).
- SPIFFE identities on the mTLS link.

## Maintenance rule

If you change the diagram, update this document in the same commit. The `.excalidraw` is the rendered artifact; this document is the spec.
