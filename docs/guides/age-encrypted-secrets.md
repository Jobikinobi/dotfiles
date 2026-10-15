# Age-encrypted secrets in a public repo

**This repository is public.** Every secret in it is encrypted with [age](https://age-encryption.org)
to a single recipient. The ciphertext is safe to publish; the private identity that
opens it is never committed and lives only in Doppler and in an offline backup.

| | |
|---|---|
| Recipient (public) | `age1l2n5sqj8eg0728vlj6che0vas474svdxej2ceypr6046z5ylwqusr00mzj` |
| Identity (private) | Doppler → project `dotfiles`, config `prd`, secret `AGE_IDENTITY` |
| Offline backup | `~/Documents/Archive/__RECOVERY__/` (text + QR) |
| Local install path | `~/.config/chezmoi/key.txt`, mode `0600` |

There is deliberately **no passphrase-wrapped copy of the identity in the repo**. A public
repo cannot be un-published, so anything committed is brute-forceable forever with no
revocation. Keeping the identity in Doppler preserves both revocation and an audit trail.

## Deploying to a new machine

Bootstrap is two passes, and the first works with no credentials at all.

```bash
# Pass 1 — ordinary dotfiles. No key needed; encrypted files are skipped.
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply Jobikinobi

# Pass 2 — secrets.
doppler login
dotfiles-unlock
```

`dotfiles-unlock` fetches `AGE_IDENTITY`, **verifies it derives the repository's recipient**
before installing it, writes it to `~/.config/chezmoi/key.txt` at `0600`, and re-applies.

```
dotfiles-unlock              fetch key, then chezmoi apply
dotfiles-unlock --key-only   fetch key, skip apply
dotfiles-unlock --verify     check the local key without contacting Doppler
```

`doppler` is only required when a key actually has to be fetched. A machine whose key is
already installed and valid unlocks without the Doppler CLI present at all.

### On a machine that has been in use

Unlocking runs `chezmoi apply`, and on a long-lived machine that can mean rewriting files
that have nothing to do with your secrets. The script counts pending changes **excluding**
the encrypted ones — that is, drift unrelated to unlocking — and if more than
`DOTFILES_DRIFT_LIMIT` (default 10) it asks first, or refuses outright when there is no TTY.

To unlock without touching anything else:

```bash
dotfiles-unlock --key-only
chezmoi diff                                    # review
chezmoi apply ~/.config/rclone/rclone.conf      # apply selectively
```

After pass 2, `rclone ncdu r2:`, `aws`, `gh` and every SSH key work immediately.

## What is encrypted

| Target | Notes |
|---|---|
| `~/.config/rclone/rclone.conf` | 23 remotes — R2, B2, Dropbox, OCI, Proxmox, S3 |
| `~/.aws/credentials`, `~/.aws/config` | keys plus SSO account IDs and internal endpoints |
| `~/.config/gh/hosts.yml` | GitHub OAuth token |
| `~/.kube/config` | OrbStack cluster — machine-local, low value elsewhere |
| `~/.skm/default/id_ed25519` | the primary key; `~/.ssh/id_ed25519` is an skm symlink to it |
| `~/.ssh/` × 8 | `do_ed25519`, `hetzner_id_exe`, `hole_cloud_oci`, `id_ed25519_incus`, `id_exe`, `id_lab`, `id_mac2mac`, `mac-mini` |
| `~/.ssh/` × 3 | `id_ed25519_pve`, `id_ed25519_pve_admin`, `id_ed25519_macstudio` (pre-existing) |
| `~/.local/share/infra/` | Proxmox runbooks (pre-existing) |

**Deliberately not encrypted:** `~/.docker/config.json` uses `credsStore: osxkeychain` and
holds no inline tokens — the real credentials are in the macOS Keychain. Committing it would
add no security and would break on Linux guests, where `osxkeychain` does not exist.

**Encrypting keys here does not add passphrases to them on disk.** They deploy exactly as
they are today, so existing automation keeps working. Passphrase protection is a separate
decision.

## The `.chezmoiignore` guard

Without the identity, `age` exits 1 and **`chezmoi apply` hard-fails** — it does not skip
gracefully. So encrypted targets must be ignored when no key is present, or a fresh machine
cannot bootstrap at all.

That list used to be maintained by hand, and went stale the moment a file was added — a
missed entry breaks bootstrap *silently*. It is now derived by globbing the source tree:

```
{{- if not (stat (joinPath .chezmoi.homeDir ".config/chezmoi/key.txt")) }}
{{- range $p := glob (joinPath .chezmoi.sourceDir "**" "encrypted_*") }}
...derive the target path from the source name...
{{- end }}
{{- end }}
```

**Adding a new encrypted file requires no edit here.** `chezmoi add --encrypt <file>` is the
whole procedure.

## Incus guests

`incus/profile-dotfiles.yaml` composes on top of `default` and follows the same two-pass
shape:

```bash
incus profile create dotfiles
incus profile edit dotfiles < incus/profile-dotfiles.yaml
incus launch images:ubuntu/24.04/cloud <name> -p default -p dotfiles

incus exec <name> -- tailscale-login
incus exec <name> -- su - jth -c 'doppler login'
incus exec <name> -- su - jth -c 'dotfiles-unlock'
```

Two details that are load-bearing:

- **It adds a `/dev/net/tun` device.** Without one, `tailscaled` falls back to userspace
  networking: `tailscale up` still appears to succeed and outbound works, but inbound
  connections to services on the guest do not. The failure is quiet.
- **It carries no `$6$` password hashes and sets `ssh_pwauth: false`.** Shadow hashes in a
  public repo are offline-crackable. Access is by SSH key or Tailscale SSH, with
  `incus exec` from the host as the always-available backdoor — so you cannot lock
  yourself out.

## Rotating the identity

Only necessary if the private key is believed exposed. It is not a routine operation.

```bash
age-keygen -o /tmp/new-key.txt                       # note the printed public key
chezmoi forget <each encrypted target>               # or re-add after switching recipient
# update `recipient` in .chezmoi.toml.tmpl and this file
chezmoi init                                         # regenerate ~/.config/chezmoi/chezmoi.toml
chezmoi add --encrypt <each file>                    # re-encrypt to the new recipient
doppler secrets set AGE_IDENTITY -p dotfiles -c prd < /tmp/new-key.txt
shred -u /tmp/new-key.txt
```

Git history still holds ciphertext readable by the **old** key, so rotation alone does not
retract anything already published. Rotate the underlying credentials too.

## Verifying

```bash
dotfiles-unlock --verify                             # local key matches the recipient

# every encrypted file decrypts with the key Doppler hands out
doppler secrets get AGE_IDENTITY --plain -p dotfiles -c prd > /tmp/k && chmod 600 /tmp/k
find . -name 'encrypted_*' -not -path './.git/*' \
  -exec sh -c 'age -d -i /tmp/k "$1" >/dev/null 2>&1 && echo "ok   $1" || echo "FAIL $1"' _ {} \;
rm -f /tmp/k
```

A full fresh-machine test — no access to the recovery archive, both passes — runs in a
container:

```bash
docker run --rm -v "$PWD":/src:ro ubuntu:24.04 bash -c \
  'apt-get update -qq && apt-get install -y -qq curl age git &&
   sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b /usr/local/bin &&
   chezmoi init --source=/src && chezmoi apply --exclude=scripts'
```

Pass 1 must succeed with no key and leave encrypted targets absent.
