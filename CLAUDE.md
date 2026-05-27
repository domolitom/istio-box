# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Sandbox environment for experimenting with Istio. Initial target is Istio running in **ambient mode** (sidecar-less data plane using ztunnel + waypoints) on a local **kind** cluster with **2 nodes**.

## Tutorial-shaped history

This repo is also a tutorial. Each commit should be a small, self-contained tutorial step so readers can walk the history with `git log --oneline --reverse`. When adding new functionality:

- Make one logical change per commit (e.g. "add kind manifest", "install Istio ambient", "deploy bookinfo sample") rather than bundling unrelated work.
- Update `README.md`'s "Tutorial steps" section in the same commit that introduces the step, so the narrative stays in sync with the code.
- Prefer a commit message that names the step (e.g. `tutorial: step N — <what it does>` or a conventional-commit style scope that mirrors the area touched, e.g. `kind:`, `istio:`).

## Current state

- `kind/cluster.yaml` — 1 control-plane + 2 workers, ports 80/443 mapped to host, cluster name `istio-ambient`.
- No Istio install scripts or sample workloads yet.

## Next likely steps

- A bootstrap script or Makefile target that installs Istio in the ambient profile (`istioctl install --set profile=ambient`).
- Sample workloads in a `samples/` directory for exercising L4/L7 ambient features (ztunnel, waypoint proxies, authorization policies).

Update this file with concrete commands once they exist — do not invent commands that aren't actually wired up.
