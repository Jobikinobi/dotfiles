# dotfiles — Portable Development Environment

Cross-platform environment as code. One command bootstraps a fully configured dev machine — macOS or Linux.

> **Source directory**: `~/dotfiles` on macOS. Do not clone elsewhere — chezmoi reads from this path only.

---

## Platform Overview

```
Layer 1: Tailscale         mesh network — connects all machines
Layer 2: chezmoi/dotfiles  identity — makes any machine "yours"  ← this repo
Layer 3: Containers        workloads — Weaviate, transparency engine
Layer 4: Backups           durability — R2, GHCR, Doppler
```

This repo owns **Layer 2**. For container stacks and infrastructure, see [hole-devenv](https://github.com/Jobikinobi/hole-devenv).

### What's Included

| Component | macOS | Linux | Source |
|-----------|:-----:|:-----:|--------|
| Shell (zsh + Powerlevel10k + zinit) | Yes | Yes | `dot_zshrc.tmpl` |
| Core CLI tools (bat, eza, fd, fzf, helix, jq, nnn, ripgrep, uv) | Yes | Yes | `dot_Brewfile.core` |
| Full tool suite (100+ packages, GUI apps) | Yes | — | `dot_Brewfile` |
| Git config + GitHub credential helper | Yes | Yes | `dot_gitconfig` |
| SSH config (1Password agent, Tailscale hosts) | Yes | Partial | `private_dot_ssh/config.tmpl` |
| Editor configs (helix, kitty, btop, htop) | Yes | Yes | `dot_config/` |
| Node LTS + Claude Code | Yes | Yes | `run_once_after_install-brewfile.sh.tmpl` |
| Tailscale auto-join | — | Yes | `run_once_before_install-toolchains.sh.tmpl` |
| Secrets via Doppler (baked at apply time) | Yes | Optional | `dot_zshrc.tmpl` |
| Docker image (GHCR) | — | Pre-built | `Dockerfile.test` |

---

## Quick Start

### Fresh Mac

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi && chezmoi init --apply Jobikinobi
```

### Fresh Linux (interactive)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply Jobikinobi
```

### Docker (pre-built, instant)

```bash
docker pull ghcr.io/jobikinobi/dotfiles:latest
docker run -d --name devbox \
  --cap-add=NET_ADMIN --device=/dev/net/tun \
  -e TS_AUTHKEY=tskey-auth-... \
  -e TS_HOSTNAME=devbox \
  -v ts-state:/var/lib/tailscale \
  ghcr.io/jobikinobi/dotfiles:latest
```

Then: `ssh jth@devbox` (via Tailscale SSH, no keys needed).

### Already restored?

```bash
mac-restore     # pull repo + restore full environment
mac-save        # snapshot current state → commit → push
mac-check       # show what has drifted (chezmoi diff)
```

---

## Core Tool Stack (Linux + macOS)

Installed via `dot_Brewfile.core` on Linux, included in the full `dot_Brewfile` on macOS:

| Tool | Replaces | Purpose |
|------|----------|---------|
| `bat` | `cat` | Syntax-highlighted file viewer |
| `eza` | `ls` | Modern file listing with icons |
| `fd` | `find` | Fast file finder |
| `fzf` | — | Fuzzy finder (Ctrl+R, Ctrl+T) |
| `helix` | `vim` | Modal editor (`$EDITOR`) |
| `jq` | — | JSON processor |
| `nnn` | — | Terminal file manager |
| `ripgrep` | `grep` | Fast content search |
| `uv` | `pip` | Python package manager |
| `direnv` | — | Per-directory env vars |
| `doppler` | `.env` files | Secrets management |
| `fnm` | `nvm` | Node version manager |
| `powerlevel10k` | — | zsh prompt theme |

---

## Tailscale Mesh

All machines connected via tailnet `lemming-likert.ts.net`:

| Host | Role | Access |
|------|------|--------|
| `jth-macstudio` | Primary workstation | Local |
| `mac-mini` | Weaviate + Docker infrastructure | `ssh mac-mini` |
| `hole-dev` | Transparency Engine (DigitalOcean) | `ssh root@hole-dev` |
| `foia-scraper` | FOIA scraper (DigitalOcean) | `ssh root@foia-scraper` |
| `macbook-air` | Laptop | Local |

Docker containers join the tailnet automatically when launched with `TS_AUTHKEY`.

---

## Secrets Management

All secrets live in **Doppler** — never hardcoded, never in `.env` files.

chezmoi templates call Doppler at `chezmoi apply` time and bake values into the generated files:
```
# In dot_zshrc.tmpl (what git sees):
export API_KEY='{{ output "doppler" "secrets" "get" "API_KEY" "--plain" ... | trim }}'

# In ~/.zshrc (what the shell sees):
export API_KEY='actual-value-from-doppler'
```

---

## CI/CD

Every PR runs two jobs (both must pass to merge):

| Job | What it tests |
|-----|--------------|
| **Linux** | Builds Docker image, verifies all core tools installed |
| **macOS** | Runs `chezmoi apply`, verifies key files deploy and templates render |

On merge to main: pushes updated image to `ghcr.io/jobikinobi/dotfiles:latest`.

---

## Repo Structure

```
dotfiles/
├── .github/workflows/ci.yml          # CI: Docker build + macOS test
├── .chezmoi.toml.tmpl                 # chezmoi config (prompts or defaults)
├── .chezmoiignore                     # files chezmoi skips
│
├── dot_zshrc.tmpl                     # → ~/.zshrc (main shell config)
├── dot_zshenv                         # → ~/.zshenv
├── dot_zprofile                       # → ~/.zprofile
├── dot_gitconfig                      # → ~/.gitconfig
├── dot_p10k.zsh                       # → ~/.p10k.zsh
├── dot_Brewfile                       # → ~/.Brewfile (macOS full)
├── dot_Brewfile.core                  # → ~/.Brewfile.core (Linux core)
│
├── dot_config/                        # → ~/.config/
│   ├── helix/                         #   editor config
│   ├── kitty/                         #   terminal config
│   ├── nnn/plugins/                   #   file manager plugins
│   ├── fish/                          #   fish shell (secondary)
│   ├── btop/, htop/, gh/              #   tool configs
│
├── private_dot_ssh/config.tmpl        # → ~/.ssh/config (OS-conditional)
│
├── run_once_before_install-homebrew.sh.tmpl    # 1. Install Homebrew
├── run_once_before_install-toolchains.sh.tmpl  # 2. Tailscale + macOS toolchains
├── run_once_after_install-brewfile.sh.tmpl     # 3. brew bundle + Node + Claude
├── run_once_after_install-launchagent.sh.tmpl  # 4. macOS auto-save agent
│
├── Dockerfile.test                    # Ubuntu 24.04 dev node image
├── entrypoint.sh                      # Tailscale + sshd startup
├── com.jth.mac-save.plist             # macOS launchd auto-save
├── docs/                              # Project documentation
└── scripts/                           # Legacy/utility scripts
```

---

## Managing Dotfiles

```bash
# See what chezmoi would change
chezmoi diff

# Capture local changes into chezmoi source
chezmoi re-add ~/.ssh/config          # for plain files
# For .tmpl files: edit the template directly in ~/dotfiles/

# Apply chezmoi source to live files
chezmoi apply                         # ⚠ check diff first!

# Add a new file to chezmoi
chezmoi add ~/.some-config

# Full save cycle (re-add + commit + push)
mac-save
```

> **Warning**: `chezmoi apply` overwrites live files with the source version. Always run `chezmoi diff` first. See [docs/chezmoi-workflow.md](docs/chezmoi-workflow.md) for details.

---

## Related

- [hole-devenv](https://github.com/Jobikinobi/hole-devenv) — Infrastructure stacks, deployment profiles, backup automation
- [hole-backend](https://github.com/The-HOLE-Foundation/hole-backend) — Backend services and Weaviate schemas
- [transparency-engine](https://github.com/The-HOLE-Foundation/transparency-engine) — FOIA drafting agent
