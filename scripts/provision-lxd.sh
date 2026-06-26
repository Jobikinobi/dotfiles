#!/usr/bin/env bash
# provision-lxd.sh — host-side launcher for Ubuntu 24.04 LXD containers on
# the canonical Proxmox host (reached over the tailnet).
#
# Renders cloud-init from a chezmoi profile key, fetches a single-use
# Tailscale auth key from Doppler, then SSHes to the Proxmox host and
# launches an LXD container that pre-seeds ~/.config/chezmoi/chezmoi.toml
# with the chosen profile and runs `chezmoi init --apply jobikinobi`.
#
# Usage:
#   scripts/provision-lxd.sh --project <key> --name <container-name> [--dry-run]
#                            [--host <ssh-target>] [--image <image>]
#                            [--nix-profile <profile>]
#
# Constraints (see THE-68):
#   - No long-lived secrets in user-data; only the single-use Tailscale auth key.
#   - Pure bash, ShellCheck-clean.
#   - --dry-run prints the rendered cloud-init and the proposed remote
#     `lxc launch` command without executing or fetching real secrets.
#
# Tailscale auth key is read from Doppler:
#   project=dotfiles  config=lxd-bootstrap  secret=TAILSCALE_AUTHKEY
# Generate it as an ephemeral, single-use, tag:server key, store it in Doppler
# immediately before running this script, and rotate it out after the container
# boots (the in-VM consumer shreds /run/ts-authkey on first run).

set -euo pipefail

PROG="$(basename "$0")"

# Defaults — overridable via flags or environment.
DEFAULT_HOST="${LXD_PROXMOX_HOST:-proxmox.lemming-likert.ts.net}"
DEFAULT_IMAGE="${LXD_IMAGE:-ubuntu:24.04}"
DOPPLER_PROJECT="${DOPPLER_PROJECT_OVERRIDE:-dotfiles}"
DOPPLER_CONFIG="${DOPPLER_CONFIG_OVERRIDE:-lxd-bootstrap}"
DOPPLER_SECRET="${DOPPLER_SECRET_OVERRIDE:-TAILSCALE_AUTHKEY}"

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
  cat >&2 <<EOF
Usage: $PROG --project <key> --name <container-name> [--dry-run]
                              [--host <ssh-target>] [--image <image>]
                              [--nix-profile <profile>]

Required:
  --project <key>       chezmoi profile key (must match dot_Brewfile.<key> in repo)
  --name <name>         LXD container name (e.g. the-legal-01)

Optional:
  --nix-profile <p>     Nix workspace profile to activate [joe|agent] (blank = no Nix).
                        Seeds nix_profile in the pre-seeded chezmoi.toml so
                        run_once_after_nix-profile.sh.tmpl activates the right flake output.
                        NOTE: 'agent' requires user 'agent' in the flake (see agent-linux);
                        the container user is 'jth' — activation will fail until HOL-510.
  --dry-run             print rendered cloud-init + proposed remote command; do
                        NOT call doppler, do NOT contact the Proxmox host
  --host <target>       SSH target for the Proxmox host
                        (default: $DEFAULT_HOST; env: LXD_PROXMOX_HOST)
  --image <image>       LXD image alias (default: $DEFAULT_IMAGE; env: LXD_IMAGE)
  -h, --help            show this help and exit

Examples:
  $PROG --project legal --name the-legal-01 --dry-run
  $PROG --project legal --name the-legal-01
  $PROG --project legal --name the-legal-01 --nix-profile agent --dry-run
EOF
}

# ── parse args ──────────────────────────────────────────────────────────────
project=""
name=""
nix_profile=""
dry_run=0
host="$DEFAULT_HOST"
image="$DEFAULT_IMAGE"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "--project requires a value"
      project="$2"; shift 2 ;;
    --project=*)
      project="${1#--project=}"; shift ;;
    --name)
      [[ $# -ge 2 ]] || die "--name requires a value"
      name="$2"; shift 2 ;;
    --name=*)
      name="${1#--name=}"; shift ;;
    --nix-profile)
      [[ $# -ge 2 ]] || die "--nix-profile requires a value"
      nix_profile="$2"; shift 2 ;;
    --nix-profile=*)
      nix_profile="${1#--nix-profile=}"; shift ;;
    --host)
      [[ $# -ge 2 ]] || die "--host requires a value"
      host="$2"; shift 2 ;;
    --host=*)
      host="${1#--host=}"; shift ;;
    --image)
      [[ $# -ge 2 ]] || die "--image requires a value"
      image="$2"; shift 2 ;;
    --image=*)
      image="${1#--image=}"; shift ;;
    --dry-run)
      dry_run=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      err "unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

[[ -n "$project" ]] || { err "--project is required"; usage; exit 2; }
[[ -n "$name" ]]    || { err "--name is required";    usage; exit 2; }

# ── validate inputs ─────────────────────────────────────────────────────────
# Profile key: lowercase, kebab-case, ≤12 chars, starts with a letter.
# Matches the convention documented in docs/profiles/README.md.
if ! [[ "$project" =~ ^[a-z][a-z0-9-]{0,11}$ ]]; then
  die "invalid --project '$project': must be lowercase kebab-case, ≤12 chars, start with a letter"
fi

# Container name: LXD requires DNS-label-ish names.
if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
  die "invalid --name '$name': lowercase alphanumeric + hyphens, ≤63 chars, first char alphanumeric"
fi

# Nix profile: optional; when set must be a known flake key (joe or agent).
if [[ -n "$nix_profile" ]] && ! [[ "$nix_profile" =~ ^(joe|agent)$ ]]; then
  die "invalid --nix-profile '$nix_profile': must be 'joe' or 'agent' (or omit for no Nix)"
fi

# Resolve repo root from this script's directory.
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
brewfile="$repo_root/dot_Brewfile.$project"

if [[ ! -f "$brewfile" ]]; then
  err "unknown profile '$project': expected $brewfile (not found)."
  err "Existing profiles:"
  for f in "$repo_root"/dot_Brewfile.*; do
    [[ -f "$f" ]] || continue
    key="${f##*/dot_Brewfile.}"
    case "$key" in
      core|save) ;;  # not a project profile
      *) printf '  - %s\n' "$key" >&2 ;;
    esac
  done
  exit 1
fi

# ── fetch single-use Tailscale auth key from Doppler ────────────────────────
ts_authkey=""
if (( dry_run )); then
  ts_authkey="DRY-RUN-PLACEHOLDER-TAILSCALE-AUTHKEY-NOT-FETCHED"
else
  command -v doppler >/dev/null 2>&1 \
    || die "doppler not on PATH; install + authenticate Doppler before running this script."

  if ! ts_authkey="$(
    doppler secrets get "$DOPPLER_SECRET" \
      --plain \
      --project "$DOPPLER_PROJECT" \
      --config "$DOPPLER_CONFIG" 2>/dev/null
  )"; then
    die "could not fetch $DOPPLER_SECRET from doppler scope $DOPPLER_PROJECT/$DOPPLER_CONFIG. Verify login + scope."
  fi

  [[ -n "$ts_authkey" ]] \
    || die "$DOPPLER_SECRET was empty in doppler scope $DOPPLER_PROJECT/$DOPPLER_CONFIG."
fi

# ── render cloud-init ───────────────────────────────────────────────────────
# The rendered YAML is the literal cloud-init handed to LXD as user.user-data.
# It pre-seeds ~/.config/chezmoi/chezmoi.toml with projects + lxd_profile so
# chezmoi's non-interactive (`stdinIsATTY = false`) branch in
# .chezmoi.toml.tmpl does NOT overwrite our values: chezmoi only renders the
# config template when the destination is absent.
render_cloud_init() {
  local _project="$1" _name="$2" _authkey="$3" _nix_profile="$4"
  cat <<CLOUDINIT
#cloud-config
# Rendered by $PROG for project=$_project name=$_name
hostname: $_name
manage_etc_hosts: localhost

users:
  - name: jth
    gecos: Joseph T. Herrmann, M.D.
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [sudo, adm]
    lock_passwd: true
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGd21xodn8bnXQN9Ud0XZy9l+ow30AL2llbwOztxoFnL jth@workstation

package_update: true
package_upgrade: false
packages:
  - build-essential
  - ca-certificates
  - curl
  - file
  - git
  - gnupg
  - jq
  - procps
  - zsh

write_files:
  # Single-use Tailscale auth key. Consumed and shredded by runcmd below;
  # never lives in process argv (tailscale reads via file: URI).
  - path: /run/ts-authkey
    permissions: '0600'
    owner: root:root
    content: |
      $_authkey

  # Pre-seed chezmoi config so the non-interactive .chezmoi.toml.tmpl branch
  # does not clobber projects/lxd_profile/nix_profile with their empty defaults.
  - path: /home/jth/.config/chezmoi/chezmoi.toml
    permissions: '0600'
    owner: jth:jth
    defer: true
    content: |
      [data]
          name = "Joseph T. Herrmann, M.D."
          email = "joeherrmann@gmail.com"
          github_user = "Jobikinobi"
          projects = ["$_project"]
          lxd_profile = "$_project"
          nix_profile = "$_nix_profile"

  # Bootstrap script run as jth: install chezmoi, init+apply from GitHub.
  # The age decryption key (~/.config/chezmoi/key.txt) is NOT provisioned here
  # by design — it must be installed out-of-band before any encrypted file in
  # the dotfiles can be applied. The pre-seeded config above leaves chezmoi
  # init's template render a no-op (config already present), so init only
  # clones the source dir and runs apply.
  - path: /usr/local/bin/bootstrap-chezmoi
    permissions: '0755'
    owner: root:root
    content: |
      #!/usr/bin/env bash
      set -euo pipefail
      sudo -u jth -H bash -lc '
        mkdir -p "\$HOME/.local/bin"
        if ! command -v chezmoi >/dev/null 2>&1 && [ ! -x "\$HOME/.local/bin/chezmoi" ]; then
          sh -c "\$(curl -fsLS https://get.chezmoi.io)" -- -b "\$HOME/.local/bin"
        fi
        export PATH="\$HOME/.local/bin:\$PATH"
        chezmoi init --apply jobikinobi
      '

runcmd:
  - sh -c "curl -fsSL https://tailscale.com/install.sh | sh"
  - [ systemctl, enable, --now, tailscaled ]
  - sh -c "tailscale up --auth-key=file:/run/ts-authkey --advertise-tags=tag:server --ssh --hostname=$_name && (shred -u /run/ts-authkey 2>/dev/null || rm -f /run/ts-authkey)"
  - /usr/local/bin/bootstrap-chezmoi

final_message: |
  cloud-init complete for $_name (project=$_project). Uptime: \$UPTIME s.
  Login: ssh jth@$_name   (over tailnet, MagicDNS)
CLOUDINIT
}

cloud_init="$(render_cloud_init "$project" "$name" "$ts_authkey" "$nix_profile")"

# ── dry-run: print and exit ────────────────────────────────────────────────
if (( dry_run )); then
  cat <<EOF
# ── rendered cloud-init ── (project=$project name=$name nix_profile=${nix_profile:-<none>}; auth key REDACTED)
$cloud_init

# ── proposed remote invocation ──
# (executed over SSH; the cloud-init body is streamed on stdin so the
#  auth key never appears in remote process argv)
ssh $host bash -s -- '$image' '$name' <<'REMOTE'
set -euo pipefail
IMAGE="\$1"
NAME="\$2"
TMP="\$(mktemp /tmp/lxd-userdata.XXXXXX)"
trap 'shred -u "\$TMP" 2>/dev/null || rm -f "\$TMP"' EXIT
cat > "\$TMP"
chmod 600 "\$TMP"
lxc init "\$IMAGE" "\$NAME"
lxc config set "\$NAME" user.user-data - < "\$TMP"
lxc start "\$NAME"
REMOTE
# (cloud-init body is piped into the ssh stdin above)

# Equivalent single-line form for quick inspection:
#   ssh $host lxc launch '$image' '$name' --config=user.user-data="\$(cat <rendered>)"
EOF
  exit 0
fi

# ── execute: SSH and launch ─────────────────────────────────────────────────
command -v ssh >/dev/null 2>&1 || die "ssh not on PATH"

# Remote command: read cloud-init from stdin into a mode-0600 tmpfile, init
# the container, set user.user-data from the file (no argv exposure of the
# auth key), start. Image and container name are baked in via printf %q so we
# can keep stdin entirely for the cloud-init body — multiplexing both a pipe
# and a heredoc into a single ssh invocation is ambiguous in bash, so we
# avoid that by passing the script as a single quoted command string.
#
# The $TMP references below are intentionally literal — they expand on the
# remote host, not locally. ShellCheck SC2016 warnings are expected.
# shellcheck disable=SC2016
printf -v remote_cmd '%s' '
set -euo pipefail
TMP="$(mktemp /tmp/lxd-userdata.XXXXXX)"
trap '\''shred -u "$TMP" 2>/dev/null || rm -f "$TMP"'\'' EXIT
cat > "$TMP"
chmod 600 "$TMP"
'
printf -v remote_cmd '%slxc init %q %q\n' "$remote_cmd" "$image" "$name"
# shellcheck disable=SC2016
printf -v remote_cmd '%slxc config set %q user.user-data - < "$TMP"\n' "$remote_cmd" "$name"
printf -v remote_cmd '%slxc start %q\n' "$remote_cmd" "$name"

if ! printf '%s' "$cloud_init" | ssh -T "$host" "$remote_cmd"; then
  die "remote lxc launch failed on $host (image=$image name=$name); cloud-init was not applied."
fi

printf '%s: launched %s on %s (image=%s, project=%s, nix_profile=%s)\n' \
  "$PROG" "$name" "$host" "$image" "$project" "${nix_profile:-<none>}"
