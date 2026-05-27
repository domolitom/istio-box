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
