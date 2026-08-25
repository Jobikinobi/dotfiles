#!/usr/bin/env bash
# test-incus.sh — ephemeral-Incus deployment test rig.
#
# Launches a throwaway Incus instance on a remote, waits for it to provision,
# reports whether the provisioning layer (cloud-init → users → NetBird) came
# up, optionally applies the dotfiles via chezmoi, verifies a handful of core
# tools, then tears the instance down.
#
# It doubles as the reproduction harness for the "Debian guests don't finish
# provisioning" bug (#114): run it against an Ubuntu image and a Debian image
# and diff the "provisioning" section of the report. The root cause surfaces
# immediately — the Incus profiles put users/NetBird in cloud-init.user-data,
# which is a no-op on non-cloud image variants (plain `images:debian/12` ships
# no cloud-init), whereas Ubuntu images bundle it.
#
# Design mirrors scripts/provision-lxd.sh: pure bash, ShellCheck-clean,
# --dry-run prints the plan and touches nothing.
#
# Ephemerality: instances are launched with `--ephemeral`, so Incus deletes
# them automatically the moment they stop — nothing is left behind even if this
# script is killed mid-run (the trap stops the instance on exit).
#
# Usage:
#   scripts/test-incus.sh [options]
#
# Options:
#   --remote <name>    Incus remote to launch on         (default: $INCUS_REMOTE or incus2)
#   --image <image>    Image to launch                    (default: images:ubuntu/24.04)
#   --profile <name>   Incus profile to apply             (default: default)
#   --name <name>      Instance name                      (default: tst-<distro>-<rand>)
#   --branch <branch>  chezmoi source branch to apply     (default: main)
#   --apply-dotfiles   Run `chezmoi init --apply` in the guest (adds minutes)
#   --keep             Do NOT tear the instance down on exit (for debugging)
#   --dry-run          Print the plan and exit; launch nothing
#   -h, --help         This help

set -euo pipefail

PROG="$(basename "$0")"

# ── Defaults (overridable via flags / env) ───────────────────────────────────
REMOTE="${INCUS_REMOTE:-incus2}"
IMAGE="images:ubuntu/24.04"
PROFILE="default"
NAME=""
BRANCH="main"
APPLY_DOTFILES=0
KEEP=0
DRY_RUN=0

err()  { printf '%s: %s\n' "$PROG" "$*" >&2; }
die()  { err "$*"; exit 1; }
info() { printf '→ %s\n' "$*"; }
sect() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ── Arg parsing ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --remote)         REMOTE="${2:?}"; shift 2 ;;
    --image)          IMAGE="${2:?}"; shift 2 ;;
    --profile)        PROFILE="${2:?}"; shift 2 ;;
    --name)           NAME="${2:?}"; shift 2 ;;
    --branch)         BRANCH="${2:?}"; shift 2 ;;
    --apply-dotfiles) APPLY_DOTFILES=1; shift ;;
    --keep)           KEEP=1; shift ;;
    --dry-run)        DRY_RUN=1; shift ;;
    -h|--help)        usage 0 ;;
    *)                err "unknown argument: $1"; usage 1 ;;
  esac
done

command -v incus >/dev/null 2>&1 || die "incus CLI not found on PATH"

# Derive a stable-ish instance name from the image if the caller didn't pass one.
# (No RNG dependency beyond the shell's $RANDOM, which is fine for a scratch name.)
if [ -z "$NAME" ]; then
  distro="$(printf '%s' "$IMAGE" | sed -E 's#^[^:]*:##; s#[/.].*$##')"
  NAME="tst-${distro:-guest}-${RANDOM}"
fi

TARGET="${REMOTE}:${NAME}"

# ── ex(): run a command inside the guest ─────────────────────────────────────
ex() { incus exec "$TARGET" -- "$@"; }

# Best-effort check: is a binary present in the guest? Swallow incus's own
# "Error: Command not found" chatter so a missing binary reads as a clean no.
guest_has() { ex sh -c "command -v $1 >/dev/null 2>&1" >/dev/null 2>&1; }

# ── Dry-run: print the plan and stop ─────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  sect "DRY RUN — nothing will be launched"
  cat <<EOF
remote          : $REMOTE
image           : $IMAGE
profile         : $PROFILE
instance name   : $NAME
chezmoi branch  : $BRANCH
apply dotfiles  : $([ "$APPLY_DOTFILES" -eq 1 ] && echo yes || echo no)
keep on exit    : $([ "$KEEP" -eq 1 ] && echo yes || echo no)

would run:
  incus launch $IMAGE $TARGET --profile $PROFILE --ephemeral
  # wait for agent, then diagnostics: cloud-init / users / netbird
$([ "$APPLY_DOTFILES" -eq 1 ] && echo "  # in guest: chezmoi init --apply --branch $BRANCH Jobikinobi")
  incus stop $TARGET   # --ephemeral => auto-deleted
EOF
  exit 0
fi

# ── Teardown trap ────────────────────────────────────────────────────────────
cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    info "leaving $TARGET running (--keep). Delete with: incus delete -f $TARGET"
    return
  fi
  info "tearing down $TARGET"
  incus stop "$TARGET" >/dev/null 2>&1 || incus delete -f "$TARGET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ── Launch ───────────────────────────────────────────────────────────────────
sect "Launch"
info "incus launch $IMAGE $TARGET --profile $PROFILE --ephemeral"
incus launch "$IMAGE" "$TARGET" --profile "$PROFILE" --ephemeral

# Wait for the guest agent to answer exec (containers come up in seconds).
info "waiting for guest to accept exec..."
for _ in $(seq 1 30); do
  if ex true >/dev/null 2>&1; then break; fi
  sleep 2
done
ex true >/dev/null 2>&1 || die "guest never became reachable via incus exec"

# ── Provisioning diagnostics (the #114-relevant section) ─────────────────────
sect "Provisioning"

if guest_has cloud-init; then
  info "cloud-init: PRESENT — waiting for it to finish"
  ex cloud-init status --wait >/dev/null 2>&1 || true
  cistatus="$(ex cloud-init status 2>/dev/null | tr -d '\r' || echo 'status: unknown')"
  printf '   %s\n' "$cistatus"
else
  err  "cloud-init: ABSENT — profile cloud-init.user-data will NOT run on this image"
  err  "   (this is the #114 failure mode: users/network/netbird never get provisioned)"
fi

# Users the profile's cloud-init is supposed to create.
printf '   users : '
for u in jth paperclip; do
  if ex id "$u" >/dev/null 2>&1; then printf '%s✓ ' "$u"; else printf '%s✗ ' "$u"; fi
done
printf '\n'

# NetBird enrollment.
if guest_has netbird; then
  nbstat="$(ex netbird status 2>/dev/null | grep -iE 'Management:|Signal:|NetBird IP|Status:' | tr -d '\r' | paste -sd '; ' - || true)"
  info "netbird: INSTALLED — ${nbstat:-no status}"
else
  err  "netbird: NOT INSTALLED"
fi

# ── Optional: apply the dotfiles ─────────────────────────────────────────────
if [ "$APPLY_DOTFILES" -eq 1 ]; then
  sect "Dotfiles (chezmoi init --apply, branch=$BRANCH)"
  # Install chezmoi to /root/.local/bin (no brew dependency), then apply.
  ex sh -c '
    set -e
    export PATH="$HOME/.local/bin:$PATH"
    command -v git  >/dev/null 2>&1 || (command -v apt-get >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl) || true
    command -v chezmoi >/dev/null 2>&1 || sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$HOME/.local/bin"
  '
  ex sh -c "export PATH=\"\$HOME/.local/bin:\$PATH\"; chezmoi init --apply --branch '$BRANCH' Jobikinobi" \
    || err "chezmoi apply returned non-zero (see output above)"

  sect "Verify core tools"
  for tool in zsh git curl chezmoi; do
    if guest_has "$tool"; then printf '   %-8s ✓\n' "$tool"; else printf '   %-8s ✗\n' "$tool"; fi
  done
fi

sect "Done"
info "instance $TARGET tested (teardown on exit)"
