# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Sandbox environment for experimenting with Istio. Initial target is Istio running in **ambient mode** (sidecar-less data plane using ztunnel + waypoints) on a local **kind** cluster with **2 nodes**.

## Current state

The repository is empty — no scripts, manifests, or tooling have been added yet. When extending it, prefer adding:

- A kind cluster config (2 nodes) under a predictable path (e.g. `kind/cluster.yaml`).
- A bootstrap script or Makefile target that creates the cluster and installs Istio in ambient profile (`istioctl install --set profile=ambient` or the Helm equivalent).
- Sample workloads in a `samples/` directory for exercising L4/L7 ambient features (ztunnel, waypoint proxies, authorization policies).

Update this file with concrete commands (build, install, teardown, run-a-single-sample) once they exist — do not invent commands that aren't actually wired up.
