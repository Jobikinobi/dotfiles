# CLAUDE.md — dotfiles

Cross-platform development environment managed by chezmoi.

## Critical Safety Rules

1. **NEVER run `chezmoi apply` without checking `chezmoi diff` first** — it overwrites live files
2. **NEVER run `chezmoi apply` in Claude sessions** — the user manages apply manually
3. Use `chezmoi re-add <file>` to update source from a live file (not the other way around)
4. For `.tmpl` files, edit the template directly — `re-add` would destroy template logic

## chezmoi Conventions

### File Naming
- `dot_` prefix → deployed as `.` (e.g., `dot_zshrc.tmpl` → `~/.zshrc`)
- `private_dot_` → deployed with restricted permissions
- `.tmpl` suffix → processed as Go template before deployment
- `run_once_before_` → runs before files are deployed
- `run_once_after_` → runs after files are deployed

### Template Patterns
```
{{ if eq .chezmoi.os "darwin" }}   # macOS-only block
{{ if lookPath "doppler" }}        # only if binary exists
{{ if stdinIsATTY }}               # interactive vs headless
{{ output "cmd" "args" | trim }}   # run command, capture output
```

### Script Execution Order
1. `run_once_before_00-apt-bootstrap.sh.tmpl` — Linux apt prereqs (incl. Avahi packages)
2. `run_once_before_install-homebrew.sh.tmpl` — Install Homebrew
3. `run_once_before_install-tailscale.sh.tmpl` — Install Tailscale
4. chezmoi deploys all files (Brewfiles, configs, etc.)
5. `run_once_after_configure-avahi.sh.tmpl` — Configure mDNS/nsswitch.conf (Linux)
6. `run_once_after_install-brewfile.sh.tmpl` — `brew bundle` + Node + Claude Code
7. `run_once_after_install-launchagent.sh.tmpl` — macOS auto-save agent
8. `run_once_after_install-tailscale-ssh.sh.tmpl` — Tailscale SSH setup

### Brewfile Strategy
- `dot_Brewfile.core` — single cross-platform core (macOS + Linux)
- `brew bundle` only installs, never removes — so machine-specific tools you
  install manually with `brew install` are left alone
- Keep this file short. If you find yourself reaching for it to track every
  package on a machine, stop — that's not its job

## Project profiles

Per-project tooling is gated by the `projects` list in `~/.config/chezmoi/chezmoi.toml` (rendered from `.chezmoi.toml.tmpl`). A profile is a sibling `dot_Brewfile.<key>` + `run_once_after_install-project-<key>.sh.tmpl` + `docs/profiles/<key>.md`, activated by adding `<key>` to `projects`. Default is `projects = []` (core only).

When adding, removing, or modifying a profile, follow the 10-step onboarding checklist in [docs/profiles/README.md](docs/profiles/README.md). Per-project work belongs in `dot_Brewfile.<key>`, never in `dot_Brewfile.core`.

## Secrets

- Legacy secrets stay in Doppler — never hardcoded
- The new `dotfiles-dotenvxx` profile uses dotenvx-managed encrypted `.env` files at shell runtime
- `dot_zshrc.tmpl` uses `{{ output "doppler" ... }}` to bake secrets at apply time
- Guarded by `{{ if lookPath "doppler" }}` — skipped if Doppler isn't installed
- Known issue: Doppler fails over SSH (keyring inaccessible) — see dotfiles#5

## Network Discovery

### Tailscale + MagicDNS (primary, all environments)
- Installed via `run_once_before_install-tailscale.sh.tmpl` on macOS, bundled in Docker image
- Provides secure WireGuard overlay on tailnet `lemming-likert.ts.net`
- Use MagicDNS hostnames (`<hostname>.lemming-likert.ts.net`) for cross-machine access

### Avahi / mDNS (LAN-local complement, Linux/real hosts)
- Installed via `run_once_before_00-apt-bootstrap.sh.tmpl`: `avahi-daemon avahi-utils libnss-mdns`
- Configured via `run_once_after_configure-avahi.sh.tmpl`: patches `/etc/nsswitch.conf` to add `mdns4_minimal [NOTFOUND=return]` before `dns`
- Enabled at boot via systemd on real hosts/VMs; skipped silently in Docker build layers
- macOS ships Bonjour natively — no install needed; `.local` resolution works out of the box
- **Docker-bridge caveat**: containers on Docker's default bridge (`docker0`) cannot participate in LAN mDNS because multicast is not forwarded. Containers should use Tailscale MagicDNS for peer discovery. For LAN mDNS in a container, run with `--network=host`

## Docker Image

- Base: Ubuntu 24.04 with Homebrew + core Brewfile + Tailscale
- Published to `ghcr.io/jobikinobi/dotfiles:latest` on merge to main
- `.chezmoi.toml.tmpl` uses `stdinIsATTY` to detect headless builds and skip prompts
- `entrypoint.sh` starts tailscaled + sshd

## CI

- Linux job: build Docker image, verify 10 core tools
- macOS job: `chezmoi apply --exclude=scripts`, verify key files + template rendering
- Both must pass before PR merges to main

## Related

- [hole-devenv](https://github.com/Jobikinobi/hole-devenv) — Infrastructure layer (container stacks, backups)
- Tailnet: `lemming-likert.ts.net` (MagicDNS)
- Doppler secrets: multiple projects (`backend/prd`, dotfiles config)
- dotenvx profile: `dotfiles-dotenvxx` runtime env file under `~/.config/dotfiles/dotfiles-dotenvxx/.env`
