# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

A sandbox and a tutorial for Istio in ambient mode on a local kind cluster. The history is meant to be readable — each commit is a tutorial step.

## Conventions

- One small, self-contained change per commit. Update `README.md`'s steps section in the same commit that introduces the step.
- Keep all prose short, human-readable, and educational — explain the *why* a learner needs, not more.
- No `Co-Authored-By: Claude` trailer in commit messages.
- **Never `Write` an existing file to apply changes — use targeted `Edit` calls, no matter how many fields change.** `Write` is for first creation only. This applies to all files, including diagrams (`.excalidraw`).

## State

- `kind/cluster.yaml` — 1 control-plane + 2 workers, ports 80/443 mapped on the control-plane, cluster name `istio-ambient`.
- `helm/istio/values-{base,istiod,cni,ztunnel}.yaml` — one values file per Istio Helm chart, each documented with a header comment.
- `scripts/install-istio.sh` / `scripts/uninstall-istio.sh` — install the four ambient charts in order (and remove them in reverse). Istio version is pinned at the top of the install script.
- No sample workloads yet.
