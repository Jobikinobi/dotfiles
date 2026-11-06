#!/usr/bin/env bash
# Set up agent sandboxes on the current kubectl cluster.
# Usage: ./bootstrap.sh gvisor|kata
#   gvisor - works on any Apple silicon Mac (user-space kernel, no nested virt)
#   kata   - full VM per pod; needs nodes with /dev/kvm (M3+ Mac, nested virt on)
set -euo pipefail

RUNTIME="${1:?usage: $0 gvisor|kata}"
AGENT_SANDBOX_VERSION="${AGENT_SANDBOX_VERSION:-v1.0.9}"
NAMESPACE="${NAMESPACE:-kiac-dev}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "Cluster: $(kubectl config current-context)"

# 1. Namespace the sandboxes live in
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. agent-sandbox controller + CRDs (Sandbox, SandboxTemplate, SandboxClaim, SandboxWarmPool)
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${AGENT_SANDBOX_VERSION}/sandbox-with-extensions.yaml"
kubectl -n agent-sandbox-system rollout status deployment/agent-sandbox-controller --timeout=180s

# 3. Sandbox runtime
case "$RUNTIME" in
  gvisor)
    "$HERE/install-gvisor.sh"
    kubectl apply -f "$HERE/gvisor-runtime.yaml"
    SANDBOX="$HERE/vm-sandbox.yaml"
    ;;
  kata)
    "$HERE/install-kata.sh"
    SANDBOX="$HERE/vm-sandbox-kata.yaml"
    ;;
  *)
    echo "unknown runtime: $RUNTIME (use gvisor or kata)" >&2
    exit 2
    ;;
esac

echo
echo "Ready. Start a sandbox with: kubectl apply -f $SANDBOX"
