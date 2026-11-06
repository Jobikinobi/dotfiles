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
{{ if stat "path" }}               # check if agent-rendered file exists
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

<!-- gitbutler-agent-setup:start -->
## Version control

- Use GitButler (`but`) for version-control inspection and write operations, including status, diffs, branching, committing, pushing, and history edits.
- Assume multiple agents may be working in this repository. Do not move, amend, squash, discard, commit, push, or otherwise modify another agent's work unless the user asks.
- For commit just/only/specific changes on a new branch (selected-change requests), use the two-command fast path from the GitButler skill: `but diff`, then `but commit -b <branch> -m "message" <id> <id>`.
- For that fast path, after the commit succeeds, stop and summarize; do not run separate branch, staging, status, or diff commands unless the commit output is missing information you need.
- Use the installed GitButler skill for command recipes and syntax before guessing flags, using `--help`, or translating Git habits directly.
- Mutation commands report their result without appending workspace status. Add `--status-after` only when the next step needs resulting workspace IDs or details; otherwise do not rerun status or diff to verify success.
- Use a dedicated GitButler branch for each agent session, unless the user asks for a different branch structure. Commit only changes that belong to that session.
- Do not push or open pull requests unless the user asks.
- Keep commit messages and pull request descriptions succinct: explain what changed, why it changed, and any important decision.

### Amend local fixes into the right commits

- For small cleanup or follow-up fixes, amend an unpublished local commit when the change clearly belongs with that commit's intent.
- Do not create tiny fixup commits unless the user asks.
- Use GitButler to move the relevant changes into the commit where they belong.
- Ask before rewriting pushed, reviewed, shared, or ambiguous history.

### Split unrelated changes into separate commits

- If one file contains unrelated changes, split them by hunk instead of committing the whole file.
- Keep tests with the behavior they verify.
- Split generated output, docs-only edits, or mechanical cleanup into separate commits when each commit remains coherent on its own.
- If the split is ambiguous, summarize the options before committing.

### Update from the target branch automatically

- When GitButler status shows new changes on the target branch and the workspace holds only this session's branches, update with `but pull` directly — its output reports the result and `but undo` reverts it.
- If an update you started on your own initiative reports conflicted commits, stop and ask before resolving them (`but undo` reverts the pull if the user prefers).
- When other agents' branches are applied, run `but pull --check` first and ask before updating if it reports conflicts or their branches would move.
- If the user asks you to handle update conflicts, use GitButler's conflict tools. Ask before resolving semantic conflicts, dependency updates, generated files, or conflicts involving another person's work.
<!-- gitbutler-agent-setup:end -->
