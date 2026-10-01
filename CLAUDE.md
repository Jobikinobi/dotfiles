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
{{ if lookPath "infisical" }}      # only if Infisical CLI exists
{{ if stdinIsATTY }}               # interactive vs headless
{{ if .fileExists "path" }}        # check if agent-rendered file exists
{{ output "cmd" "args" | trim }}   # run command, capture output (legacy Doppler)
```

### Secrets Management
- **Infisical Agent** renders secrets to files (`~/.infisical/*.env`) via persistent daemon
- Agents use Universal Auth (machine identity) with per-project reader roles
- `dot_zshrc.tmpl` sources pre-rendered files — no network call at apply time
- Legacy Doppler calls remain as fallbacks during the migration period
- See `.infisical/README.md` for provisioning and architecture details

### Script Execution Order
1. `run_once_before_install-homebrew.sh.tmpl` — Install Homebrew
2. `run_once_before_install-toolchains.sh.tmpl` — Tailscale + macOS dev tools
3. chezmoi deploys all files (Brewfiles, configs, etc.)
4. `run_once_after_install-brewfile.sh.tmpl` — `brew bundle` + Node + Claude Code
5. `run_once_after_install-launchagent.sh.tmpl` — macOS auto-save agent

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

- **Primary: Infisical Agent** — persistent daemon renders secrets to `~/.infisical/*.env` files
  - Machine identity (Universal Auth) with per-project reader roles
  - Provisioning key creates child identities but cannot read secrets
  - See `.infisical/README.md` for architecture and provisioning steps
- **Legacy: Doppler** — still present as fallback during migration
  - `dot_zshrc.tmpl` sources pre-rendered files (no `{{ output "doppler" ... }}`)
  - Shell scripts try agent file → Infisical CLI → Doppler fallback
- Known issue: Doppler fails over SSH (keyring inaccessible) — see dotfiles#5

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
- Infisical Cloud org: `99ad52da-...` (secrets management)
- Self-hosted Infisical Core: `infisical.wolverine-wyrm.ts.net` (PKI/cert-manager only)
- Doppler secrets: multiple projects (`backend/prd`, dotfiles config) — legacy/fallback
