#!/usr/bin/env bash
# Install Istio in ambient mode via Helm.
#
# Four charts are installed in order:
#   1. base    — Istio CRDs and the validating webhook.
#   2. istiod  — the control plane (Pilot).
#   3. cni     — the istio-cni plugin (ambient redirection lives here).
#   4. ztunnel — the per-node L4 proxy DaemonSet (the ambient data plane).
#
# Each chart's values live in helm/istio/values-<chart>.yaml so you can
# tweak any of them independently and re-run this script — `helm upgrade
# --install` will apply the changes.

set -euo pipefail

ISTIO_VERSION="1.30.0"
NAMESPACE="istio-system"
HELM_REPO_URL="https://istio-release.storage.googleapis.com/charts"
VALUES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../helm/istio" && pwd)"

# Add or refresh the Istio chart repo.
helm repo add istio "$HELM_REPO_URL" >/dev/null 2>&1 || true
helm repo update istio >/dev/null

# Ensure the istio-system namespace exists.
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
  || kubectl create namespace "$NAMESPACE"

install_chart() {
  local release="$1" chart="$2" values="$3"
  echo ">>> installing $release ($chart) @ $ISTIO_VERSION"
  helm upgrade --install "$release" "istio/$chart" \
    --version "$ISTIO_VERSION" \
    --namespace "$NAMESPACE" \
    --values "$values" \
    --wait
}

install_chart istio-base base    "$VALUES_DIR/values-base.yaml"
install_chart istiod     istiod  "$VALUES_DIR/values-istiod.yaml"
install_chart istio-cni  cni     "$VALUES_DIR/values-cni.yaml"
install_chart ztunnel    ztunnel "$VALUES_DIR/values-ztunnel.yaml"

echo
echo "Istio $ISTIO_VERSION (ambient) installed in namespace $NAMESPACE."
echo "Verify with:  kubectl -n $NAMESPACE get pods"
