#!/usr/bin/env bash
# Uninstall Istio in the reverse order of install-istio.sh.
# Leaves the istio-system namespace and CRDs in place by default —
# delete those manually if you want a fully clean slate.

set -euo pipefail

NAMESPACE="istio-system"

uninstall_release() {
  local release="$1"
  if helm status "$release" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo ">>> uninstalling $release"
    helm uninstall "$release" -n "$NAMESPACE"
  else
    echo ">>> $release not installed, skipping"
  fi
}

uninstall_release ztunnel
uninstall_release istio-cni
uninstall_release istiod
uninstall_release istio-base

echo
echo "Done. Namespace $NAMESPACE and Istio CRDs are left in place."
echo "To remove them too:"
echo "  kubectl delete namespace $NAMESPACE"
echo "  kubectl get crd -oname | grep 'istio.io' | xargs -r kubectl delete"
