# Import notes — phase 3A

Source: `the-hole-foundation/Legal-Assistant-v3` @ commit reference (see git log).

## What this commit does

Verbatim import of the conventions docs + supporting artifacts, with no edits. The next commit on this branch will generalize them so they apply to any repo, not just Legal-Assistant-v3.

## What's here

| Path | Source | Status |
|---|---|---|
| `docs/standards/{README,issues,labels,branches-and-worktrees,milestones,projects}.md` | `docs/conventions/*.md` | **Verbatim**, awaits generalization |
| `docs/standards/_LA-V3-SETUP-LOG.reference.md` | `docs/conventions/SETUP-LOG.md` | **Reference only** — record of how LA-v3 was bootstrapped; the per-repo equivalent is generated when the script runs |
| `scripts/standards/setup-github-governance.sh.proposed` | `scripts/setup-github-governance.sh` | **Verbatim**, awaits parameterization |
| `docs/standards/reference/build-and-test.yml.example` | `.github/workflows/build-and-test.yml` | Template for required-status-check workflow |
| `docs/standards/reference/copilot-instructions.example.md` | `.github/copilot-instructions.md` | Template for Copilot project guide |
| `docs/standards/reference/CLAUDE.example.md` | `CLAUDE.md` | Template for Claude Code project memory |

## Generalization plan (next commit on this branch)

For each doc, strip LA-v3-specific content and parameterize:

- **`labels.md`** — keep `type:*` and `status:*` tables verbatim (universal). Replace the `area:*` table with a placeholder + meta-rule: "each repo enumerates its own areas in this file."
- **`milestones.md`** — keep all rules. Replace LA-v3 example milestones with generic phase examples + a per-repo note.
- **`projects.md`** — keep all rules. Replace project name placeholder. Update `<current-active-milestone>` filter syntax.
- **`branches-and-worktrees.md`** — keep all rules. Replace worktree-location example with `<your-org-conventions>` placeholder.
- **`issues.md`** — fully transferable, minimal edits.
- **`README.md`** — rewrite the framing from "Legal-Assistant-v3 governance" to "org-wide conventions; per-repo instantiation lives in this file."

For the setup script: parameterize repo name, area labels (read from a per-repo config file), milestone seed list (also per-repo config).

## Then

Phase 3B (separate work): push the generalized version up to `the-hole-foundation/.github` (community health files) and a template repo (full conv stack, `is_template: true`).
