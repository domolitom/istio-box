# istio-box

A small, hands-on tutorial for running **Istio in ambient mode** on a local **kind** cluster.

Each commit is one tutorial step. Walk the history with:

```sh
git log --oneline --reverse
```

## Prerequisites

Docker, [kind](https://kind.sigs.k8s.io/), `kubectl`, and `istioctl`.

## Steps

### 1. Create the kind cluster

We use three nodes (1 control-plane + 2 workers) so that, later on, ambient traffic can travel between two `ztunnel` instances on different nodes — that's the interesting case to observe.

```sh
kind create cluster --config kind/cluster.yaml
kubectl get nodes
```

Teardown when finished:

```sh
kind delete cluster --name istio-ambient
```

### 2. Install Istio (ambient) with Helm

Ambient mode is made of four Helm charts that must be installed in a specific order. Each chart owns one moving part of the data plane, and each has its own values file under [`helm/istio/`](./helm/istio/) so you can configure them independently.

| Chart | Release name | Values file | Role |
|---|---|---|---|
| `istio/base` | `istio-base` | [`values-base.yaml`](./helm/istio/values-base.yaml) | CRDs and the validating webhook |
| `istio/istiod` | `istiod` | [`values-istiod.yaml`](./helm/istio/values-istiod.yaml) | Control plane (Pilot) |
| `istio/cni` | `istio-cni` | [`values-cni.yaml`](./helm/istio/values-cni.yaml) | CNI plugin — programs in-pod redirection for ambient |
| `istio/ztunnel` | `ztunnel` | [`values-ztunnel.yaml`](./helm/istio/values-ztunnel.yaml) | Per-node L4 proxy DaemonSet (ambient data plane) |

The version is pinned in [`scripts/install-istio.sh`](./scripts/install-istio.sh) (currently `1.30.0`) so the tutorial is reproducible. Run:

```sh
./scripts/install-istio.sh
```

Verify the control plane and data plane are up:

```sh
kubectl -n istio-system get pods
```

You should see `istiod`, `istio-cni-node` (one per node), and `ztunnel` (one per node). To change any setting — say, the istiod resource requests — edit the matching values file and re-run the script; `helm upgrade --install` will apply the diff.

Uninstall with:

```sh
./scripts/uninstall-istio.sh
```
