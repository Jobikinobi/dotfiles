#!/usr/bin/env bash
# Create a kiac cluster whose node VMs can run Kata (nested virtualization, M3+ Mac),
# then install agent-sandbox + Kata on it.
# Usage: ./kiac-create-kata.sh [extra kiac create flags]   (NAME=kata by default)
# After a reboot, resume with the shim too:  PATH="$PWD/shim:$PATH" kiac resume cluster --name kata
set -euo pipefail

NAME="${NAME:-kata}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NODES_DIR="$HOME/.kiac/gpu-nodes/nodes"
KEY="$HOME/.kiac/gpu-nodes/id_ed25519"

# kiac reaches krunkit nodes at <node>.local, but the node VMs came up with mDNS off,
# so kiac's SSH-ready wait times out. Turn mDNS on (persistently) in each node as it boots.
enable_mdns() {
  local done=" "
  while :; do
    for d in "$NODES_DIR"/kiac-"$NAME"-*; do
      [ -f "$d/serial.log" ] || continue
      local n ip
      n="$(basename "$d")"
      [[ "$done" == *" $n "* ]] && continue
      ip="$(LC_ALL=C grep -aoE 'eth0: [0-9]+(\.[0-9]+){3}' "$d/serial.log" | tail -1 | cut -d' ' -f2)" || true
      [ -n "$ip" ] || continue
      if ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "fedora@$ip" \
           'sudo mkdir -p /etc/systemd/resolved.conf.d &&
            printf "[Resolve]\nMulticastDNS=yes\n" | sudo tee /etc/systemd/resolved.conf.d/mdns.conf >/dev/null &&
            sudo systemctl restart systemd-resolved && sudo resolvectl mdns eth0 yes' 2>/dev/null; then
        echo "  mDNS enabled on $n ($ip)"
        done+="$n "
      fi
    done
    sleep 3
  done
}
enable_mdns &
MDNS_PID=$!
trap 'kill $MDNS_PID 2>/dev/null || true' EXIT

# --gpu-workers moves kiac to the krunkit backend; the shim adds krunkit --nested.
# With --workers 0 the control plane is untainted and runs the Kata pods.
PATH="$HERE/shim:$PATH" kiac create cluster --name "$NAME" --workers 0 --gpu-workers 1 "$@"

kubectl config use-context "kiac-$NAME"
"$HERE/bootstrap.sh" kata
