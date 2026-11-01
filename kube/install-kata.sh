#!/usr/bin/env bash
# Install Kata Containers (VM-per-pod) on the current kubectl cluster.
# Needs nodes that expose /dev/kvm, which on a Mac means an M3-or-newer chip,
# macOS 15+, and node VMs started with nested virtualization turned on.
# Safe to re-run. Usage: ./install-kata.sh [node ...]   (default: every node; ones without /dev/kvm are skipped)
set -euo pipefail

KATA_VERSION="${KATA_VERSION:-4.3.1}"
# GitHub release tarball, not the ghcr OCI chart: helm OCI pulls can hang on the macOS Keychain credential helper
CHART="https://github.com/kata-containers/kata-containers/releases/download/${KATA_VERSION}/kata-deploy-${KATA_VERSION}.tgz"
HERE="$(cd "$(dirname "$0")" && pwd)"

# --- 1. Host check (informational: the node check below is what counts) ---
CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
echo "Host chip: ${CHIP}, macOS $(sw_vers -productVersion 2>/dev/null || echo '?')"
if [[ "$CHIP" =~ Apple\ M[12]( |$) ]]; then
  echo "WARNING: ${CHIP} cannot do nested virtualization; Kata will not run here. Use gVisor (install-gvisor.sh)." >&2
fi

# --- 2. Find nodes and check each one for /dev/kvm ---
NODES=("$@")
if [ ${#NODES[@]} -eq 0 ]; then
  read -r -a NODES <<<"$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')"
fi

node_has_kvm() {
  local n="$1"
  # kiac/kind nodes are apple/container VMs; Lima nodes are reached with limactl
  if [ -f "$HOME/.kiac/gpu-nodes/nodes/$n/state.json" ]; then
    # kiac krunkit (GPU-backend) nodes: reachable over ssh as fedora@<node>.local
    ssh -i "$HOME/.kiac/gpu-nodes/id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$HOME/.kiac/gpu-nodes/nodes/$n/known_hosts" \
      "fedora@$n.local" test -c /dev/kvm || {
        # 255 = ssh itself failed; don't mistake an unreachable node for one without KVM
        rc=$?; [ "$rc" -eq 255 ] && { echo "ERROR: can't reach $n over ssh (is mDNS on?)" >&2; exit 1; }
        return "$rc"; }
  elif command -v container >/dev/null && container inspect "$n" >/dev/null 2>&1; then
    container exec "$n" test -c /dev/kvm
  elif command -v limactl >/dev/null && limactl list -q 2>/dev/null | grep -qx "$n"; then
    limactl shell "$n" test -c /dev/kvm
  else
    echo "  (can't reach $n directly; checking with a debug pod)" >&2
    kubectl debug "node/$n" -q --image=busybox:1.36 --profile=sysadmin --attach=true -- test -c /host/dev/kvm
  fi
}

READY=0
for n in "${NODES[@]}"; do
  if node_has_kvm "$n"; then
    echo "  ${n}: /dev/kvm present"
    kubectl label node "$n" sandbox.kata.dev/kvm=true --overwrite >/dev/null
    READY=$((READY + 1))
  else
    echo "  ${n}: NO /dev/kvm, skipping"
    kubectl label node "$n" sandbox.kata.dev/kvm- >/dev/null 2>&1 || true
  fi
done

if [ "$READY" -eq 0 ]; then
  cat >&2 <<'EOF'

No node has /dev/kvm, so Kata cannot start VMs. Nothing was installed.
On an M3+ Mac this usually means the node VMs were created without nested
virtualization. See kube/README.md, "Kata on the Mac Studio".
EOF
  exit 1
fi

# --- 3. Remove a hand-made "kata" RuntimeClass so Helm can own it ---
if kubectl get runtimeclass kata >/dev/null 2>&1 &&
   [ "$(kubectl get runtimeclass kata -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')" != "kata-deploy" ] &&
   [ "$(kubectl get runtimeclass kata -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')" != "Helm" ]; then
  echo "Replacing old hand-made 'kata' RuntimeClass"
  kubectl delete runtimeclass kata
fi

# --- 4. Install kata-deploy ---
# Local file: given a URL, helm also consults configured repos and fails if their caches are stale
TGZ="$(mktemp -d)/kata-deploy.tgz"
curl -fsSL -o "$TGZ" "$CHART"
helm upgrade --install kata-deploy "$TGZ" \
  --namespace kube-system -f "$HERE/kata-values.yaml" --wait --timeout 10m

kubectl get runtimeclass kata
echo "Done. Try it: kubectl apply -f $HERE/vm-sandbox-kata.yaml"
