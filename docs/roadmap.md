# Dotfiles Roadmap

Generated 2026-06-13 from `gh issue list` backlog sync ([HOL-233](/HOL/issues/HOL-233)).
This is a *rough ordering*, not a committed schedule. CEO validates priority.

---

## Testing Infrastructure

Two environments are available. Use the right one:

| Environment | Good for | Limitation |
|---|---|---|
| **OrbStack** (`orb create ubuntu <name>`) | Fast chezmoi deploy/teardown, zshrc testing | Limited cloud-init: user-creation cloud-init steps silently fail; set user/password via orb flags instead |
| **Proxmox** (`ssh root@192.168.68.86`) | Full cloud-init → chezmoi round-trip, multi-distro matrix | Slower cycle; use for cloud-init changes |

For simple dotfile changes: use OrbStack. For cloud-init or bootstrap script changes: use Proxmox.

---

## Workstream 1 — Immediate Bugs & Cleanup

These are small, high-friction items that block daily use. Do these first.

| Issue | Title | Notes |
|---|---|---|
| [#62](https://github.com/Jobikinobi/dotfiles/issues/62) | `bugfix/ubuntu-zprofile-error` | `/opt/homebrew/bin/brew` path hardcoded; Linux gets an error on login |
| [#61](https://github.com/Jobikinobi/dotfiles/issues/61) | `bugfix/remove projects from zshrc` | Mac-Studio-specific shortcut polluting all Linux deploys |
| [#64](https://github.com/Jobikinobi/dotfiles/issues/64) | `bugfix/fnm setup` | fnm installs but can't find default node version; add `.node-version` or equivalent and standard fnm config to dotfiles |
| [#56](https://github.com/Jobikinobi/dotfiles/issues/56) | `bug/brew+chezmoi problems` | **Root cause item** — brew install fails on some Linux; fix before alpine work |
| [#55](https://github.com/Jobikinobi/dotfiles/issues/55) | `bug/alpine-failure` | Likely downstream of #56; investigate after brew fix |
| [#5](https://github.com/Jobikinobi/dotfiles/issues/5) | VS Code SSH keychain unlock | Tracked as [HOL-228](/HOL/issues/HOL-228) |

Owner: FoundingEngineer for code changes; DevOpsManager for CI verification.

---

## Workstream 2 — Network Stack Pivot (tailscale → cloudflare)

**Direction**: replace tailscale with Cloudflare tunnel/WARP. Already confirmed by `wontfix` labels on tailscale funnel and tailscale aperture.

Dependency: #59 (remove tailscale) must land before #50 (add cloudflare tunnel).

| Issue | Title | Notes |
|---|---|---|
| [#59](https://github.com/Jobikinobi/dotfiles/issues/59) | `remove tailscale` | Priority label; uninstall + remove from chezmoi |
| [#50](https://github.com/Jobikinobi/dotfiles/issues/50) | `feat/cloudflare tunnel` | Priority label; replace tailscale egress |
| [#58](https://github.com/Jobikinobi/dotfiles/issues/58) | `feat/ssh standard` — known_hosts | Priority label; independent of tunnel choice |
| [#33](https://github.com/Jobikinobi/dotfiles/issues/33) | `feat/tailscale universal access` | **Superseded** by cloudflare pivot — close if not needed |

---

## Workstream 3 — Auth Stack Pivot (Doppler → dotenvx)

**Direction**: migrate from Doppler to dotenvx/dotenv-vault. PR #63 is already open.

This pivot **resolves [HOL-228](/HOL/issues/HOL-228)** (Doppler-over-SSH keyring failure) as a side effect — dotenvx doesn't use the macOS keychain. Check HOL-228 for closure after #52 lands.

| Issue | Title | Notes |
|---|---|---|
| [#52](https://github.com/Jobikinobi/dotfiles/issues/52) | `chore/switch auth to dotenvx` | PR #63 open; needs review + merge |
| [#29](https://github.com/Jobikinobi/dotfiles/issues/29) | `feat/add age encryption` | Finalize age key integration alongside dotenvx |
| [HOL-228](/HOL/issues/HOL-228) | Doppler-over-SSH failure | Re-evaluate for closure after #52 merges |

---

## Workstream 4 — Linux/Cross-Platform Improvements

Improves deployment reliability across distros. Depends on Workstream 1 (brew fix) being stable first.

| Issue | Title | Notes |
|---|---|---|
| [#53](https://github.com/Jobikinobi/dotfiles/issues/53) | `chore/autodetect linux version` | Bootstrap distro detection; unblocks [HOL-230](/HOL/issues/HOL-230) |
| [#24](https://github.com/Jobikinobi/dotfiles/issues/24) | `cloud-init failure` | OrbStack cloud-init; compare against `linux-dotfiles-handoff.yaml` |
| [#23](https://github.com/Jobikinobi/dotfiles/issues/23) | `cloud-init password` | Default password for cloud-init VMs |
| [HOL-230](/HOL/issues/HOL-230) | `chezmoi diff` smoke test in CI | Depends on distro detection |
| [HOL-232](/HOL/issues/HOL-232) | Document cloud-init handoff path | Doc work, can run parallel |

---

## Workstream 5 — Shell & UX Improvements

Quality-of-life for daily use. Can land incrementally without blocking other workstreams.

| Issue | Title | Notes |
|---|---|---|
| [#60](https://github.com/Jobikinobi/dotfiles/issues/60) | `Add zoxide` | Remove tailscale from zshrc, add zoxide — natural pairing with #59 |
| [#14](https://github.com/Jobikinobi/dotfiles/issues/14) | Zshrc QoL + project-scoped GitHub PAT | WIP diff preserved in issue; apply selectively |
| [#34](https://github.com/Jobikinobi/dotfiles/issues/34) | Advanced terminal support (ghostty/alacritty) | `TERM` remapping in SSH wrapper |
| [#22](https://github.com/Jobikinobi/dotfiles/issues/22) | Quick reference system (cheat sheets) | Evaluate gocheat vs alternative first |
| [#49](https://github.com/Jobikinobi/dotfiles/issues/49) | Headscale cert functionality | Lower priority given cloudflare direction |

---

## Workstream 6 — Infrastructure Scale

Longer-horizon items. Require Proxmox access for full validation.

| Issue | Title | Notes |
|---|---|---|
| [#26](https://github.com/Jobikinobi/dotfiles/issues/26) | `Feat/Complete Proxmox Setup` | Ongoing infra work; see Proxmox-Server project |
| [#51](https://github.com/Jobikinobi/dotfiles/issues/51) | Refresh headscale per-OS recipes | Doc update from 2026-06-05 rollout data |
| [#20](https://github.com/Jobikinobi/dotfiles/issues/20) | Generalize imported LA-v3 standards | Phase 3A — strip LA-v3 specifics from imported docs |
| [#11](https://github.com/Jobikinobi/dotfiles/issues/11) | Windows Addition | VS Code server on high-RAM Windows box |
| [HOL-229](/HOL/issues/HOL-229) | Verify GHCR image publish | Ops/docs |
| [HOL-231](/HOL/issues/HOL-231) | Audit `dot_Brewfile.core` | Hygiene |

---

## Future / Not Yet Scoped

| Item | Notes |
|---|---|
| Ansible for Proxmox fleet control | Mentioned as future DevOps project; no issue yet |
| `#33` tailscale universal access | Likely moot after cloudflare pivot |

---

## Already Tracked on Board (Paperclip backlog seeds)

| HOL Issue | Maps to |
|---|---|
| [HOL-228](/HOL/issues/HOL-228) | GitHub #5 (VS Code SSH / Doppler keychain) |
| [HOL-229](/HOL/issues/HOL-229) | GHCR image publish verification |
| [HOL-230](/HOL/issues/HOL-230) | chezmoi diff smoke test in CI |
| [HOL-231](/HOL/issues/HOL-231) | dot_Brewfile.core audit |
| [HOL-232](/HOL/issues/HOL-232) | cloud-init handoff documentation |

---

## Candidate Issues to Promote to Paperclip Board

CEO to select. DevOpsManager will create HOL issues for those chosen.

- **[#59] remove tailscale** — unblocks cloudflare pivot; priority label
- **[#50] feat/cloudflare tunnel** — priority label; network direction
- **[#58] feat/ssh standard** — priority label; independent quick win
- **[#62] ubuntu-zprofile bug** — daily-friction bug; small fix
- **[#52] switch auth to dotenvx** — PR #63 open; resolves HOL-228 as side effect
- **[#53] autodetect linux version** — unblocks CI matrix
- **[#60] add zoxide** — pairs with #59 zshrc cleanup
