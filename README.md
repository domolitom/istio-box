# istio-box

A small, hands-on tutorial for running **Istio in ambient mode** on a local **kind** cluster.

Each commit is one tutorial step. Walk the history with:

```sh
git log --oneline --reverse
```

## Prerequisites

Docker, [kind](https://kind.sigs.k8s.io/), `kubectl`, and `istioctl`.

## Steps

### Step 1 — Initial setup (kind cluster + Istio ambient)

Brings up the kind cluster and installs Istio in ambient mode. See [`diagrams/step-1.excalidraw`](./diagrams/step-1.excalidraw) and [`steps/step-1-skill.md`](./steps/step-1-skill.md) for the end-state of this step.

#### Create the kind cluster

We use three nodes (1 control-plane + 2 workers) so that, later on, ambient traffic can travel between two `ztunnel` instances on different nodes — that's the interesting case to observe.

```sh
# Create the kind cluster
kind create cluster --config kind/cluster.yaml
kubectl get nodes
```

Teardown when finished:

```sh
# Tear down the kind cluster
kind delete cluster --name istio-ambient
```

#### Install Istio (ambient) with Helm

Ambient mode is made of four Helm charts that must be installed in a specific order. Each chart owns one moving part of the data plane, and each has its own values file under [`helm/istio/`](./helm/istio/) so you can configure them independently.

| Chart | Release name | Values file | Role |
|---|---|---|---|
| `istio/base` | `istio-base` | [`values-base.yaml`](./helm/istio/values-base.yaml) | CRDs and the validating webhook |
| `istio/istiod` | `istiod` | [`values-istiod.yaml`](./helm/istio/values-istiod.yaml) | Control plane (Pilot) |
| `istio/cni` | `istio-cni` | [`values-cni.yaml`](./helm/istio/values-cni.yaml) | CNI plugin — programs in-pod redirection for ambient |
| `istio/ztunnel` | `ztunnel` | [`values-ztunnel.yaml`](./helm/istio/values-ztunnel.yaml) | Per-node L4 proxy DaemonSet (ambient data plane) |

The version is pinned in [`scripts/install-istio.sh`](./scripts/install-istio.sh) (currently `1.30.0`) so the tutorial is reproducible. Run:

```sh
# Install Istio (ambient) via Helm
./scripts/install-istio.sh
```

Verify the control plane and data plane are up:

```sh
# Verify istio-system pods are running
kubectl -n istio-system get pods
```

You should see `istiod`, `istio-cni-node` (one per node), and `ztunnel` (one per node). To change any setting — say, the istiod resource requests — edit the matching values file and re-run the script; `helm upgrade --install` will apply the diff.

Uninstall with:

```sh
# Uninstall Istio
./scripts/uninstall-istio.sh
```

### Step 2 — Test workloads (httpbin + netshoot)

See [`diagrams/step-2.excalidraw`](./diagrams/step-2.excalidraw) and [`steps/step-2-skill.md`](./steps/step-2-skill.md) for the data path this step exercises.

We need something to actually push traffic through the mesh. Two minimal in-mesh pods, deliberately scheduled on **different nodes** so requests cross the ztunnel-to-ztunnel mTLS path:

| Workload | Namespace | Role | Pinned to |
|---|---|---|---|
| `httpbin` ([`mccutchen/go-httpbin`](https://github.com/mccutchen/go-httpbin)) | `httpbin` | server — echoes request headers, status codes, etc. | `istio-ambient-worker` |
| `netshoot` ([`nicolaka/netshoot`](https://github.com/nicolaka/netshoot)) | `netshoot` | client — has `curl`, `tcpdump`, `dig`, `mtr`, … | `istio-ambient-worker2` |

Both namespaces carry the label `istio.io/dataplane-mode=ambient`, which opts every pod inside them into the data plane — no per-pod annotation needed.

```sh
# Deploy httpbin and netshoot
kubectl apply -f samples/httpbin.yaml -f samples/netshoot.yaml
kubectl -n httpbin   rollout status deploy/httpbin
kubectl -n netshoot  rollout status deploy/netshoot
```

Send a request from netshoot to httpbin — traffic flows `netshoot → ztunnel (worker 2) → ztunnel (worker 1) → httpbin`, with mTLS·HBONE only on the middle (ztunnel-to-ztunnel) hop:

```sh
# Call httpbin from netshoot (traffic crosses ztunnel mTLS)
kubectl -n netshoot exec deploy/netshoot -- \
  curl -s httpbin.httpbin.svc.cluster.local:8000/headers
```

Tear the workloads down with:

```sh
# Tear down the test workloads
kubectl delete -f samples/httpbin.yaml -f samples/netshoot.yaml
```
