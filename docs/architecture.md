# Architecture

## Four-Layer Platform

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 4: BACKUPS                                           │
│  R2 (Weaviate vectors) · GHCR (Docker images) · Doppler    │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: CONTAINERS                                        │
│  OrbStack (dev) · Colima (infra) · LXD (production)        │
│  Weaviate · Transparency Engine · hole-legal-assistant      │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: IDENTITY (this repo)                              │
│  chezmoi · zsh/p10k · helix · nnn · Brewfiles · SSH config  │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: NETWORK                                           │
│  Tailscale mesh · MagicDNS · Tailscale SSH                  │
└─────────────────────────────────────────────────────────────┘
```

## Tailscale Mesh

Tailnet: `lemming-likert.ts.net` (MagicDNS enabled)

```
jth-macstudio ──────┐
                    │
macbook-air ────────┤
                    │
mac-mini ───────────┼──── Tailscale mesh ──── hole-dev (DO)
  └─ Weaviate       │                          └─ Transparency Engine
  └─ Colima/Docker  │                          └─ Prometheus/Grafana
                    │
                    └──── foia-scraper (DO)
                    │
                    └──── dotfiles-test (Docker container)
```

All hosts use MagicDNS hostnames (e.g., `ssh mac-mini`, `curl http://hole-dev:8000`).
Docker containers join via `TS_AUTHKEY` environment variable.

## Scope Boundaries

### This repo (dotfiles) owns:
- Shell configuration (zsh, bash, fish)
- Editor and tool configs (helix, nnn, kitty, btop)
- Package management (Brewfiles — full macOS + core Linux)
- Git identity and credentials
- SSH host configuration
- Doppler secret injection into shell environment
- Docker image for "personal dev node" (GHCR)
- CI that validates chezmoi + Docker build

### hole-devenv repo owns:
- Docker Compose stacks (Weaviate, transparency engine)
- OrbStack/Colima/LXD deployment profiles
- Weaviate backup automation (R2)
- Architecture Decision Records
- Health checks and migration guides

## Secrets Model

All secrets managed via Doppler. Never in git, never in `.env` files.

| Doppler Project | Contains | Used By |
|----------------|----------|---------|
| `backend/prd` | API keys, Tailscale auth, Cloudflare R2 | Weaviate, containers |
| dotfiles config | Cloudflare S3 keys, global tool tokens | chezmoi templates |
| `mcp-servers` | MCP server API keys | Claude Code plugins |

### How secrets reach the shell
```
Doppler (cloud) ──→ chezmoi template ({{ output "doppler" ... }})
                          │
                          ▼
                    ~/.zshrc (baked values)
                          │
                          ▼
                    shell environment ($POSTMAN_API_KEY, etc.)
```

## Container Runtime Strategy

See [ADR-001](https://github.com/Jobikinobi/hole-devenv/blob/main/docs/adr/001-three-runtime-strategy.md) in hole-devenv.

| Runtime | Location | Use Case |
|---------|----------|----------|
| OrbStack | Mac Studio, Mac Mini | Dev/staging, filesystem sharing, testing |
| Colima | Mac Mini | Long-running infrastructure (Weaviate) |
| LXD | DigitalOcean | Production, snapshot portability |

## Bootstrap Flow

What happens when you run `chezmoi init --apply Jobikinobi` on a bare machine:

```
1. chezmoi clones github.com/Jobikinobi/dotfiles
2. .chezmoi.toml.tmpl prompts for name/email/github_user (or uses defaults)
3. run_once_before_install-homebrew.sh installs Homebrew
4. run_once_before_install-toolchains.sh installs Tailscale (Linux) or dev tools (macOS)
5. chezmoi deploys all config files (.zshrc, .gitconfig, .Brewfile, etc.)
6. run_once_after_install-brewfile.sh runs brew bundle + installs Node + Claude Code
7. run_once_after_install-launchagent.sh sets up daily auto-save (macOS only)
```

Total time: ~2 minutes on macOS (cached Homebrew), ~10 minutes on Linux (fresh Homebrew + compile).
