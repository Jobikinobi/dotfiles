#!/usr/bin/env bash
# gpu-provision-lxc.sh — in-container half of NVIDIA GPU passthrough for a
# Proxmox LXC container.
#
# Run as root INSIDE the container, after the host-side device passthrough
# (see scripts/gpu-passthrough-lxc-host.sh and
# docs/homelab/gpu-passthrough-lxc.md) has attached /dev/nvidia* and the
# container has been rebooted (or the devices otherwise appeared).
#
# What it does:
#   1. Detects the *host* driver version via /proc/driver/nvidia/version —
#      readable from inside an LXC because NVIDIA's proc entries aren't
#      namespaced, even though the container has its own kernel-independent
#      rootfs.
#   2. Installs the exactly-matching userspace-only driver with
#      --no-kernel-module. The host already owns the loaded kernel module
#      (LXC shares the host kernel); the container only needs matching
#      userspace libraries (libcuda, libnvidia-ml, nvidia-smi, …).
#   3. Installs nvidia-container-toolkit from NVIDIA's apt repo.
#   4. Sets nvidia-container-cli.no-cgroups=true — mandatory for an
#      unprivileged LXC container, which cannot manage device cgroups itself
#      (the host already restricted them via the dev0..dev5 passthrough).
#   5. Generates a CDI spec (/etc/cdi/nvidia.yaml) and enables the toolkit's
#      refresh unit so it regenerates on driver upgrade/reboot.
#   6. Wires the nvidia runtime into whichever Docker daemon it finds:
#        - system/rootful dockerd  → edits /etc/docker/daemon.json,
#          restarts docker.service.
#        - rootless per-user dockerd → edits
#          ~<user>/.config/docker/daemon.json, restarts the user's
#          `systemctl --user` docker.service. Auto-detected by scanning for
#          an installed rootless docker.service unit; override with
#          --docker-user if the daemon hasn't been started yet (so its user
#          unit isn't visible to the scan).
#        - no Docker at all → skipped; driver + toolkit + CDI are still left
#          ready for whatever runtime shows up later.
#
# Generalized from the recipe first proven on Proxmox CT 1001
# (docker-gpu-template, rootless) and applied as-is to CT 113 (Portainer,
# rootful) on 2026-08-24. See docs/homelab/gpu-passthrough-lxc.md for the
# full story and the host-side half of the setup.
#
# Idempotent — safe to re-run. Exits 0 (not an error) on a container with no
# GPU passed through, so it's safe to run unconditionally across a fleet of
# mixed GPU/non-GPU containers.
#
# Usage:
#   gpu-provision-lxc.sh [--docker-user <name>] [--dry-run]
#
# Options:
#   --docker-user <name>  Force rootless wiring for this user instead of
#                         auto-detecting from installed systemd --user units.
#   --dry-run             Print what would happen; do not download, install,
#                         write config, or restart anything.
#   -h, --help            Show this help and exit.

set -euo pipefail

PROG="$(basename "$0")"
LOG=/var/log/gpu-provision.log

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { err "$*"; exit 1; }
log() {
  local message="[$(date -Is)] $*"
  if (( dry_run )); then
    printf '%s\n' "$message"
  else
    printf '%s\n' "$message" | tee -a "$LOG"
  fi
}

usage() {
  cat >&2 <<EOF
Usage: $PROG [--docker-user <name>] [--dry-run]

Options:
  --docker-user <name>  Force rootless Docker wiring for this user instead
                         of auto-detecting.
  --dry-run              Print what would happen; make no changes.
  -h, --help             Show this help and exit.
EOF
}

docker_user_override=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker-user)
      [[ $# -ge 2 ]] || die "--docker-user requires a value"
      docker_user_override="$2"; shift 2 ;;
    --docker-user=*)
      docker_user_override="${1#--docker-user=}"; shift ;;
    --dry-run)
      dry_run=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      err "unknown argument: $1"; usage; exit 2 ;;
  esac
done

(( EUID == 0 )) || die "must run as root inside the LXC container"

# Run a command normally, or print it without executing when dry-run mode is set.
run() {
  if (( dry_run )); then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

log "=== gpu-provision-lxc starting (dry_run=$dry_run) ==="

# ---------------------------------------------------------------------------
# 1. No GPU passed through? Not an error — leave the container CPU-only.
# ---------------------------------------------------------------------------
if [[ ! -e /dev/nvidia0 ]]; then
  log "No /dev/nvidia0 — no GPU passed through to this container. Skipping."
  exit 0
fi

if [[ ! -r /proc/driver/nvidia/version ]]; then
  die "/dev/nvidia0 exists but /proc/driver/nvidia/version is unreadable. \
Is the NVIDIA kernel module loaded on the Proxmox host?"
fi

# ---------------------------------------------------------------------------
# 2. Determine host driver version; the CT userspace must match it exactly.
# ---------------------------------------------------------------------------
HOST_VER="$(grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' /proc/driver/nvidia/version | head -1)"
[[ -n "$HOST_VER" ]] || die "Could not parse driver version from /proc/driver/nvidia/version"
log "Host NVIDIA driver version: $HOST_VER"

CT_VER=""
if command -v nvidia-smi >/dev/null 2>&1; then
  CT_VER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
fi

# ---------------------------------------------------------------------------
# 3. Install matching userspace driver (no kernel module — host owns it).
# ---------------------------------------------------------------------------
if [[ "$CT_VER" == "$HOST_VER" ]]; then
  log "In-CT userspace driver already at $HOST_VER — skipping driver install."
else
  log "In-CT driver is '${CT_VER:-none}', need $HOST_VER — installing."
  RUNFILE="NVIDIA-Linux-x86_64-${HOST_VER}.run"
  URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/${HOST_VER}/${RUNFILE}"

  if (( dry_run )); then
    log "[dry-run] would download $URL and run it with --no-kernel-module"
  else
    # Deliberately /var/tmp, not /tmp: /tmp is tmpfs on small containers, and
    # the installer self-extracts ~1 GB, which OOM-kills a small CT.
    TMP="$(mktemp -d -p /var/tmp gpu-provision.XXXXXX)"
    trap 'rm -rf "$TMP"' EXIT

    log "Downloading $URL"
    curl -fsSL --retry 3 --retry-delay 5 -o "${TMP}/${RUNFILE}" "$URL" \
      || die "Download failed for driver $HOST_VER. Check that this version exists at $URL"

    chmod +x "${TMP}/${RUNFILE}"
    log "Installing userspace driver (--no-kernel-module)"
    "${TMP}/${RUNFILE}" \
      --silent \
      --no-kernel-module \
      --no-questions \
      --ui=none \
      --no-nouveau-check \
      --no-nvidia-modprobe \
      --target "${TMP}/extract" \
      >>"$LOG" 2>&1 \
      || die "Driver install failed — see $LOG"

    ldconfig
    log "Driver install complete."
  fi
fi

if ! (( dry_run )); then
  command -v nvidia-smi >/dev/null 2>&1 || die "nvidia-smi still missing after install"
  nvidia-smi >>"$LOG" 2>&1 || die "nvidia-smi runs but fails — driver/host version mismatch?"
  log "nvidia-smi OK"
fi

# ---------------------------------------------------------------------------
# 4. NVIDIA Container Toolkit.
# ---------------------------------------------------------------------------
if command -v nvidia-ctk >/dev/null 2>&1; then
  log "nvidia-container-toolkit already present"
else
  log "Installing nvidia-container-toolkit"
  run install -d -m 0755 /usr/share/keyrings
  if ! (( dry_run )); then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvidia-container-toolkit >>"$LOG" 2>&1 \
      || die "nvidia-container-toolkit install failed"
  fi
fi

# ---------------------------------------------------------------------------
# 5. no-cgroups — mandatory for an unprivileged LXC container, which cannot
#    manage device cgroups itself.
# ---------------------------------------------------------------------------
log "Setting nvidia-container-cli.no-cgroups=true"
run nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place

# ---------------------------------------------------------------------------
# 6. CDI spec — preferred mode, works for both rootful and rootless.
# ---------------------------------------------------------------------------
log "Generating CDI spec"
run mkdir -p /etc/cdi
if ! (( dry_run )); then
  nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml >>"$LOG" 2>&1 \
    || die "CDI generation failed"
  nvidia-ctk cdi list >>"$LOG" 2>&1 || true
fi

if systemctl list-unit-files 2>/dev/null | grep -q nvidia-cdi-refresh; then
  log "Enabling nvidia-cdi-refresh (regenerates CDI spec on driver install/upgrade/reboot)"
  run systemctl enable --now nvidia-cdi-refresh.path
fi

# ---------------------------------------------------------------------------
# 7. Wire the nvidia runtime into whichever Docker daemon this container has.
# ---------------------------------------------------------------------------
# Print the override user, or the first user with a rootless Docker service unit.
detect_rootless_user() {
  [[ -n "$docker_user_override" ]] && { echo "$docker_user_override"; return; }
  local f user
  for f in /home/*/.config/systemd/user/docker.service; do
    [[ -e "$f" ]] || continue
    user="${f#/home/}"; user="${user%%/*}"
    echo "$user"
    return
  done
}

# Run command text as a user with the environment pointed at their rootless
# Docker daemon.
as_user() {
  local user="$1"; shift
  local uid; uid="$(id -u "$user")"
  su - "$user" -c "export XDG_RUNTIME_DIR=/run/user/${uid}; \
    export DOCKER_HOST=unix:///run/user/${uid}/docker.sock; \
    export PATH=/usr/bin:/usr/sbin:\$PATH; $*"
}

if [[ -z "$docker_user_override" ]] && systemctl is-active --quiet docker 2>/dev/null; then
  log "Rootful system dockerd detected — configuring /etc/docker/daemon.json"
  run nvidia-ctk runtime configure --runtime=docker
  log "Restarting docker.service"
  run systemctl restart docker
  run systemctl is-active docker
elif rootless_user="$(detect_rootless_user)" && [[ -n "$rootless_user" ]]; then
  log "Rootless dockerd detected for user '$rootless_user' — configuring \$HOME/.config/docker/daemon.json"
  if ! id -nG "$rootless_user" | tr ' ' '\n' | grep -qx video; then
    log "Adding $rootless_user to group video (device nodes are root:video 0660)"
    run usermod -aG video "$rootless_user"
  fi
  if ! (( dry_run )); then
    as_user "$rootless_user" "nvidia-ctk runtime configure --runtime=docker \
      --config=\$HOME/.config/docker/daemon.json --cdi.enabled" >>"$LOG" 2>&1 \
      || die "nvidia-ctk runtime configure failed for $rootless_user"
    as_user "$rootless_user" "systemctl --user restart docker" >>"$LOG" 2>&1 \
      || die "rootless docker restart failed for $rootless_user"
    for _ in $(seq 1 15); do
      as_user "$rootless_user" "docker info" >/dev/null 2>&1 && break
      sleep 1
    done
  fi
else
  log "No active Docker daemon (rootful or rootless) found — driver + toolkit + CDI are ready; nothing to wire up yet."
fi

# ---------------------------------------------------------------------------
# 8. Summary.
# ---------------------------------------------------------------------------
if ! (( dry_run )); then
  log "--- GPU inventory ---"
  nvidia-smi --query-gpu=index,name,memory.total,driver_version \
    --format=csv,noheader | tee -a "$LOG"
fi

log "=== gpu-provision-lxc complete ==="
