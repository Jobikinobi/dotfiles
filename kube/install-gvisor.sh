#!/usr/bin/env bash
# Install gVisor (runsc) on kiac worker nodes and register it with containerd.
# Safe to re-run. Usage: ./install-gvisor.sh [node ...]   (default: all kiac-dev workers)
set -euo pipefail

VERSION="${GVISOR_VERSION:-release-20261026.0}"
ARCH=aarch64
URL="https://github.com/google/gvisor/releases/download/${VERSION}"

NODES=("$@")
if [ ${#NODES[@]} -eq 0 ]; then
  read -r -a NODES <<<"$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}')"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "Downloading gVisor ${VERSION} (${ARCH})..."
curl -fsSLO "${URL}/gvisor-${ARCH}.tar.bz2"
curl -fsSLO "${URL}/SHA256SUMS"
grep " gvisor-${ARCH}.tar.bz2\$" SHA256SUMS | shasum -a 256 -c -
mkdir bin && tar xjf "gvisor-${ARCH}.tar.bz2" -C bin

for N in "${NODES[@]}"; do
  echo "==> ${N}"
  # COPYFILE_DISABLE stops macOS tar from adding Apple-only metadata
  COPYFILE_DISABLE=1 tar cf - -C bin --no-xattrs . | container exec -i "$N" sh -c '
    set -e
    tar xf - --no-same-owner -C /usr/local/bin 2>/dev/null
    chown -R root:root /usr/local/bin/runsc /usr/local/bin/containerd-shim-runsc-v1 /usr/local/bin/gvisor-bin

    cp -n /etc/containerd/config.toml /etc/containerd/config.toml.pre-gvisor
    printf "[runsc_config]\n  systemd-cgroup = \"true\"\n" > /etc/containerd/runsc.toml
    if ! grep -q "runtimes.runsc\]" /etc/containerd/config.toml; then
      cat >> /etc/containerd/config.toml <<EOF

# gVisor sandbox runtime (RuntimeClass handler: runsc)
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc.options]
    TypeUrl = "io.containerd.runsc.v1.options"
    ConfigPath = "/etc/containerd/runsc.toml"
EOF
      systemctl restart containerd
    fi
    /usr/local/bin/runsc --version | head -1
  '
  kubectl label node "$N" sandbox.gvisor.dev/ready=true --overwrite
done

echo "Done. Apply the RuntimeClass with: kubectl apply -f gvisor-runtime.yaml"
