#!/usr/bin/env bash
# gpu-passthrough-lxc-host.sh — host-side half of NVIDIA GPU passthrough for
# a Proxmox LXC container.
#
# Run ON THE PROXMOX HOST as root (not inside the container). Adds the
# dev0..dev5 device-passthrough lines to an unprivileged LXC container's
# config, matching the pattern already used by CTs 149 (ubuntu-nvidia), 1001
# (docker-gpu-template), and 113 (Portainer, wired up 2026-08-24).
#
# This assumes the host itself already has a working NVIDIA driver with the
# kernel module loaded (check: `nvidia-smi` on the host itself). This script
# does not install or touch the host driver — only the per-container device
# passthrough. It is the LXC equivalent of PCI passthrough for a VM: the
# container shares the host kernel, so there's no separate driver/module
# needed on the host side per container, only these device nodes.
#
# After running this, REBOOT the container (`pct reboot <ctid>`) so the
# devices attach, then run scripts/gpu-provision-lxc.sh inside it to install
# the matching userspace driver + nvidia-container-toolkit.
#
# Companion to scripts/gpu-provision-lxc.sh. See
# docs/homelab/gpu-passthrough-lxc.md for the full pattern.
#
# Idempotent — `pct set` overwrites existing dev0..dev5 keys, so re-running
# against the same CTID is safe.
#
# Usage:
#   gpu-passthrough-lxc-host.sh <ctid> [--reboot] [--dry-run]
#
# Options:
#   --reboot    Reboot the container immediately after applying the config.
#               Without this flag the config is written but NOT applied to
#               a running container until it's next rebooted — the caller
#               decides when that's safe (see docs/homelab/gpu-passthrough-lxc.md
#               on checking restart policies of Docker containers within it
#               before rebooting a container with a live workload).
#   --dry-run   Print the `pct set` command that would run; make no changes.
#   -h, --help  Show this help and exit.

set -euo pipefail

PROG="$(basename "$0")"

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
  cat >&2 <<EOF
Usage: $PROG <ctid> [--reboot] [--dry-run]

Adds the standard NVIDIA device passthrough (nvidia0, nvidiactl, nvidia-uvm,
nvidia-uvm-tools, nvidia-caps/nvidia-cap1, nvidia-caps/nvidia-cap2 — all
gid=44/video) to an unprivileged LXC container's config via \`pct set\`.

Options:
  --reboot    Reboot the container immediately after applying.
  --dry-run   Print the command; make no changes.
  -h, --help  Show this help and exit.

Example:
  $PROG 113 --dry-run
  $PROG 113 --reboot
EOF
}

ctid=""
do_reboot=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reboot) do_reboot=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) err "unknown argument: $1"; usage; exit 2 ;;
    *)
      [[ -z "$ctid" ]] || die "unexpected extra argument: $1"
      ctid="$1"; shift ;;
  esac
done

[[ -n "$ctid" ]] || { err "<ctid> is required"; usage; exit 2; }
[[ "$ctid" =~ ^[0-9]+$ ]] || die "invalid ctid '$ctid': must be numeric"

command -v pct >/dev/null 2>&1 || die "pct not found — this script must run on the Proxmox host, not inside a container"

pct config "$ctid" >/dev/null 2>&1 || die "no such container: $ctid"

# Sanity: warn (don't block) if the host itself has no working NVIDIA driver.
if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
  err "WARNING: nvidia-smi is not working on this host — is the host driver installed and the kernel module loaded? Continuing anyway; the container will have no usable GPU until that's fixed."
fi

cmd=(pct set "$ctid"
  -dev0 /dev/nvidia0,gid=44
  -dev1 /dev/nvidiactl,gid=44
  -dev2 /dev/nvidia-uvm,gid=44
  -dev3 /dev/nvidia-uvm-tools,gid=44
  -dev4 /dev/nvidia-caps/nvidia-cap1,gid=44
  -dev5 /dev/nvidia-caps/nvidia-cap2,gid=44
)

if (( dry_run )); then
  printf '[dry-run] %s\n' "${cmd[*]}"
  (( do_reboot )) && printf '[dry-run] pct reboot %s\n' "$ctid"
  exit 0
fi

"${cmd[@]}"
printf '%s: GPU device passthrough applied to CT %s\n' "$PROG" "$ctid"

if (( do_reboot )); then
  printf '%s: rebooting CT %s\n' "$PROG" "$ctid"
  pct reboot "$ctid"
else
  printf '%s: config written but NOT applied — reboot CT %s when safe: pct reboot %s\n' "$PROG" "$ctid" "$ctid"
  printf '%s: then run scripts/gpu-provision-lxc.sh as root inside the container.\n' "$PROG"
fi
