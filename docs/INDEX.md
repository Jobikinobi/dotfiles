# docs/INDEX

Navigation map for the `dotfiles` repo's documentation tree.

## Conventions

Policy docs that govern how this repo is used day-to-day.

| File | One-line rule |
|---|---|
| [`conventions/workspace-directory-layout.md`](conventions/workspace-directory-layout.md) | Canonical `~/` tree — `projects/`, `docs/`, `bin/`, `scratch/`, etc. |
| [`conventions/nix-ci.md`](conventions/nix-ci.md) | What Nix checks run in CI, what doesn't (darwin cost), and local smoke-test path. |

## Standards (imported — Legal-Assistant-v3)

> These docs in `docs/standards/` were imported from the Legal-Assistant-v3 project.
> They are preserved as reference but are NOT dotfiles-native conventions.
> See open follow-up: reconcile `docs/standards/` vs `docs/conventions/` scope.

| File | Summary |
|---|---|
| [`standards/branches-and-worktrees.md`](standards/branches-and-worktrees.md) | Branch naming, worktree lifecycle, merge strategy |
| [`standards/issues.md`](standards/issues.md) | Issue scope and planning rules |
| [`standards/labels.md`](standards/labels.md) | Label taxonomy |
| [`standards/milestones.md`](standards/milestones.md) | Milestone policy |
| [`standards/projects.md`](standards/projects.md) | GitHub Projects setup |

## Architecture

| File | Summary |
|---|---|
| [`architecture.md`](architecture.md) | System topology: tailnet, headscale, Caddy, services |

## Homelab

| File | Summary |
|---|---|
| [`homelab/README.md`](homelab/README.md) | Homelab goal, architectural pins, PVE hub + Mac thin-client plan |
| [`homelab/nfs-corpus-mount.md`](homelab/nfs-corpus-mount.md) | Mount the `corpus` NFS drive (`/data/corpus` → `/Volumes/corpus`): LAN Bonjour, off-LAN NetBird, fallbacks |
| [`homelab/recovery.md`](homelab/recovery.md) | Homelab recovery procedures |

## ADR (Architecture Decision Records)

| File | Decision |
|---|---|
| *(none yet in this worktree — see `docs/adr/` on `docs/adr-001-doppler-standard` branch)* | |

## Profiles

See [`profiles/README.md`](profiles/README.md) for per-project tooling profile onboarding.

## Roadmap

[`roadmap.md`](roadmap.md) — current workstream priorities (updated from GitHub issues backlog).
