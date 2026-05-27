# istio-box

A hands-on sandbox and tutorial for learning **Istio in ambient mode** on a local **kind** cluster.

Each step in this tutorial corresponds to a small, focused commit — you can follow the journey with:

```sh
git log --oneline --reverse
```

…and check out any commit to see the repo state at that step.

## What you'll build

A 3-node kind cluster (1 control-plane + 2 workers) running Istio's ambient data plane (ztunnel + waypoints), with sample workloads for exploring L4 and L7 features without sidecars.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (or another container runtime kind supports)
- [kind](https://kind.sigs.k8s.io/) — local Kubernetes in Docker
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [istioctl](https://istio.io/latest/docs/setup/install/istioctl/) — used later to install Istio

## Tutorial steps

### Step 1 — Create the kind cluster

The cluster manifest at [`kind/cluster.yaml`](./kind/cluster.yaml) defines:

- 1 control-plane node + 2 worker nodes (so we can exercise cross-node ambient traffic).
- Host ports `80` and `443` mapped into the control-plane container, with the node labelled `ingress-ready=true` so an Istio ingress gateway can be pinned there with a `nodeSelector` later.

Create it:

```sh
kind create cluster --config kind/cluster.yaml
```

Verify the three nodes are up:

```sh
kubectl get nodes
```

When you're done experimenting:

```sh
kind delete cluster --name istio-ambient
```
