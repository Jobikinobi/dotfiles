#!/usr/bin/env bash
# agent-provision.sh — root/provisioning phase for the "deploy into an agent
# space" model (#99).
#
# Run this as root (or via sudo) to prepare a machine/container so that an
# UNPRIVILEGED agent user can then deploy dotfiles with `chezmoi apply` and
# needs no sudo of its own. This is the counterpart to the sudo-less run_once
# scripts: everything that requires privilege happens here, once, up front.
#
# What it does (all the privileged work):
#   1. Installs system prerequisites via the distro's package manager
#   2. Creates the agent user (if missing) with a zsh login shell
#   3. Installs Homebrew into the shared /home/linuxbrew prefix (glibc only;
#      skipped on Alpine/musl) and exposes it via /etc/profile.d
#
# What it deliberately does NOT do:
#   - Grant the agent sudo. The whole point is a sudo-less agent space. Pass
#     --with-sudo only if you explicitly want passwordless sudo for the agent.
#
# Usage:
#   sudo scripts/agent-provision.sh <username> [--with-sudo]
#
# Afterwards, deploy as the agent (no root needed):
#   su - <username> -c 'chezmoi init --apply Jobikinobi'

set -euo pipefail

AGENT_USER="${1:-agent}"
WITH_SUDO=0
for arg in "$@"; do
  [ "$arg" = "--with-sudo" ] && WITH_SUDO=1
done

if [ "$(id -u)" -ne 0 ]; then
  echo "✗ Must run as root (or via sudo). Try: sudo $0 $AGENT_USER" >&2
  exit 1
fi

# ── Distro detection (mirrors run_once_before_00-linux-bootstrap) ─────────────
OS_FAMILY="unknown"
if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian|linuxmint|pop|kali)                 OS_FAMILY="debian" ;;
    alpine)                                           OS_FAMILY="alpine" ;;
    rhel|centos|fedora|rocky|almalinux|ol|scientific) OS_FAMILY="rhel" ;;
    arch|manjaro|endeavouros)                         OS_FAMILY="arch" ;;
    *)
      case "${ID_LIKE:-}" in
        *debian*)                 OS_FAMILY="debian" ;;
        *rhel*|*fedora*|*centos*) OS_FAMILY="rhel"   ;;
        *arch*)                   OS_FAMILY="arch"   ;;
      esac
      ;;
  esac
fi
echo "→ OS family: ${OS_FAMILY} (ID=${ID:-unknown}); agent user: ${AGENT_USER}"

# ── 1. System prerequisites ───────────────────────────────────────────────────
case "$OS_FAMILY" in
  debian)
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      build-essential ca-certificates curl file git gnupg procps sudo zsh
    ;;
  alpine)
    if ! grep -qE '^[^#].*/community' /etc/apk/repositories 2>/dev/null; then
      MAIN_REPO=$(grep -m1 'http' /etc/apk/repositories 2>/dev/null | sed 's|/main||')
      [ -n "$MAIN_REPO" ] && echo "${MAIN_REPO}/community" >> /etc/apk/repositories
    fi
    apk update -q
    apk add --no-cache bash build-base ca-certificates curl file git gnupg procps shadow sudo zsh
    # Core CLI tools too: a sudo-less agent can't apk these itself during apply
    # (the brewfile step's apk fallback is skipped under PRIV=none), so the root
    # phase must provide them. Mirrors APK_CORE_PACKAGES in install-brewfile.
    apk add --no-cache age bat direnv eza fd fzf go helix jq nnn ripgrep 2>/dev/null \
      || echo "  ⚠ some core apk tools unavailable in this Alpine version — continuing"
    ;;
  rhel)
    PKG_MGR=$(command -v dnf || command -v yum)
    [ -n "$PKG_MGR" ] || { echo "✗ no dnf/yum" >&2; exit 1; }
    command -v dnf >/dev/null 2>&1 && ! rpm -q epel-release >/dev/null 2>&1 \
      && dnf install -y epel-release 2>/dev/null || true
    "$PKG_MGR" install -y \
      ca-certificates file findutils gcc gcc-c++ git glibc-devel gnupg2 make procps-ng sudo zsh
    ;;
  arch)
    pacman -Sy --noconfirm --needed \
      base-devel ca-certificates curl file git gnupg procps-ng sudo zsh
    ;;
  *)
    echo "⚠ Unrecognised distro — install manually: build-tools curl git gnupg zsh" ;;
esac

# ── 2. Create the agent user with a zsh login shell ───────────────────────────
ZSH_PATH="$(command -v zsh || echo /bin/zsh)"
if ! grep -qxF "$ZSH_PATH" /etc/shells 2>/dev/null; then
  echo "$ZSH_PATH" >> /etc/shells
fi
if ! id "$AGENT_USER" >/dev/null 2>&1; then
  echo "→ Creating user ${AGENT_USER}"
  if [ "$OS_FAMILY" = "alpine" ]; then
    adduser -D -s "$ZSH_PATH" "$AGENT_USER"
  else
    useradd -m -s "$ZSH_PATH" "$AGENT_USER"
  fi
else
  # Ensure the shell is zsh even if the user pre-existed.
  usermod -s "$ZSH_PATH" "$AGENT_USER" 2>/dev/null || true
fi

if [ "$WITH_SUDO" -eq 1 ]; then
  echo "→ Granting passwordless sudo to ${AGENT_USER} (--with-sudo)"
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$AGENT_USER" > "/etc/sudoers.d/90-agent-${AGENT_USER}"
  chmod 0440 "/etc/sudoers.d/90-agent-${AGENT_USER}"
else
  echo "→ Leaving ${AGENT_USER} WITHOUT sudo (rootless agent space)"
fi

# ── 3. Shared Homebrew (glibc only; Alpine uses apk in the apply phase) ───────
if [ "$OS_FAMILY" != "alpine" ]; then
  if [ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    # Pre-create and hand ownership of the prefix to the agent so the installer
    # runs without root — the standard rootless-Homebrew pattern. Without this,
    # Homebrew's installer shells out to sudo, which a sudo-less agent lacks.
    mkdir -p /home/linuxbrew/.linuxbrew
    chown -R "$AGENT_USER" /home/linuxbrew
    echo "→ Installing Homebrew (shared prefix, agent-owned) as ${AGENT_USER}"
    su - "$AGENT_USER" -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  fi
  cat > /etc/profile.d/linuxbrew.sh <<'PROFILE'
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
PROFILE
  chmod 0644 /etc/profile.d/linuxbrew.sh
fi

echo "✓ Agent space provisioned for ${AGENT_USER}."
echo "  Deploy dotfiles (no root needed):"
echo "    su - ${AGENT_USER} -c 'chezmoi init --apply Jobikinobi'"
