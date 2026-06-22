# ADR-001: Standardize on Doppler for secrets management; reject dotenvx pivot

## Status

Accepted

## Date

2026-06-19

## Context

Doppler has been the incumbent secrets system in `dotfiles` since the repo's inception.
It is baked into `dot_zshrc.tmpl` (via `{{ output "doppler" ... }}` template calls), referenced
in `docs/architecture.md`, and used across `hole-devenv` (see `hole-devenv` ADR-003: doppler-service-tokens).

In early 2026, a cost-saving evaluation of **dotenvx** was initiated. Dotenvx encrypts secrets
directly in `.env` files using ECIES, allowing self-hosted storage with no SaaS subscription.
The proposed architecture centralized secrets on `/Volumes/HOLE-RAID-DRIVE/dotenvx/` — a local RAID
drive serving as the master vault. Exploration branches were cut:

- `feat/dotenvx` — added encrypted `.env`, `.env.dev`, `.env.x` files to `dotfiles`, installed
  dotenvx via `dot_Brewfile.core`, and created a DOTENVX_PROJECT_ID (`prj_8678f538...`)
- `chore/dotfiles-dotenvxx` — added a chezmoi-managed `dot_config/dotfiles-dotenvxx/` profile,
  Brewfile tap, and shell helpers (`dotfiles_dotenvxx_run`, `dotfiles_dotenvxx_encrypt`) in
  `dot_zshrc.tmpl`

Separately, `The-HOLE-Foundation/foundation-meta` produced a full
`DOTENVX-SECRETS-WORKFLOW.md` (dated 2026-02-01) treating dotenvx as org-wide standard. Several
other repos (`hole-terraformer`, `HOLE-Vector`) shipped live dotenvx integrations during this
evaluation period.

As the Proxmox server footprint and multi-container workloads grow, the evaluation concluded that
**Doppler Team tier ($27/month) is worth the cost** for the reliability and operational simplicity
it provides.

## Decision

**Standardize on Doppler (Team tier) for all secret management across dotfiles and the HOLE
Foundation ecosystem. The dotenvx evaluation is officially aborted.**

Doppler remains the single source of truth for all secrets. Dotenvx is not adopted; any
code, config, or documentation that landed during the evaluation period is contamination to
be cleaned up.

## Alternatives Considered

### dotenvx (centralized RAID-based vault)
- **Pros**: No SaaS cost; encryption-at-rest in git; no external network dependency; ECIES
  encryption is cryptographically sound
- **Cons**:
  - Master vault on a single physical drive (`/Volumes/HOLE-RAID-DRIVE/dotenvx/`) — a hard
    availability dependency with no HA story
  - No audit logs, no fine-grained access controls, no per-service token rotation
  - Ops overhead grows with footprint: distributing the vault or its keys to containers/VMs
    is a manual, error-prone process
  - Multi-environment management (dev/staging/prod per project) requires discipline the
    current toolchain doesn't enforce
  - `dotenvx` binary must be present on every machine that decrypts secrets; adds a
    bootstrap dependency
- **Rejected**: The infrastructure footprint (Proxmox, LXD containers, CI runners, cloud VMs)
  has grown past the point where a drive-anchored, self-managed vault is lower-friction than
  a purpose-built secrets service.

### Status quo Doppler (Free tier)
- Not a distinct alternative — the decision is to commit to **Team tier** explicitly, rather
  than leaving tier selection ambiguous.

## Consequences

### Immediate
- The exploration branches (`feat/dotenvx`, `chore/dotfiles-dotenvxx`) are not merged and
  can be closed. The orphaned worktree `.git/worktrees/dotfiles-dotenvxx/` is a cleanup target.
- No dotenvx references exist on `main` in `dotfiles` today — this ADR confirms and locks
  that position.

### Follow-up (identified by HOL-418 contamination audit)
A cross-project audit revealed dotenvx contamination at two depths:

**Live implementations requiring migration:**
- `The-HOLE-Foundation/hole-terraformer` — `tf-with-dotenvx.sh` loads Cloudflare API token
  via `dotenvx get` from the RAID vault; must be replaced with a Doppler service token call.
- `The-HOLE-Foundation/HOLE-Vector` — `mcp-server/start.sh` uses `exec dotenvx run -- node`;
  must be replaced with Doppler-injected environment or a service-token-based pattern.
- `The-HOLE-Foundation/HOLE-Latex` — `.env.keys` committed (dotenvx key file); must be
  removed and any referenced secrets migrated to Doppler.
- `Jobikinobi/hole-token-studio` and `Jobikinobi/hole-design-system` — `.env.x` files with
  a shared DOTENVX_PROJECT_ID; must be removed and secrets moved to Doppler.

**Planning/documentation requiring update or removal:**
- `The-HOLE-Foundation/foundation-meta` — `docs/infrastructure/DOTENVX-SECRETS-WORKFLOW.md`
  documents dotenvx as org-wide standard; superseded by this decision.
- `The-HOLE-Foundation/hole-gofonts` — `CLAUDE.md` states dotenvx is standard secrets
  management; must be corrected to reference Doppler.
- `The-HOLE-Foundation/claude-plugins` — README mentions dotenvx integration; update.
- `The-HOLE-Foundation/hole-turborepo` — `TURBOREPO-DOTENVX-SETUP-VERIFIED.md` references
  runtime dotenvx commands against the RAID vault; update or remove.
- `The-HOLE-Foundation/mcp-server-pdf` — `PROJECT_STATE.md` recommends dotenvx; update.
- `The-HOLE-Foundation/hole-r2` — `.holespace/RESOURCES.md` lists dotenvx as secrets
  manager; update.

Remediation issues are proposed in [HOL-418](/HOL/issues/HOL-418) after the board reviews
the full landscape.

## ADR Directory Note

This is the first ADR in `dotfiles`. The directory `docs/adr/` is established here following
the convention used in the sibling repo `hole-devenv` (sequential `NNN-kebab-case.md` files
in `docs/adr/`). Significant architectural decisions for `dotfiles` should be recorded here
going forward.
