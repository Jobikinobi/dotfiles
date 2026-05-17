# GitHub governance — bootstrap log (Stage 1c)

**Bootstrap date**: 2026-05-08
**Repo**: [`The-HOLE-Foundation/Legal-Assistant-v3`](https://github.com/The-HOLE-Foundation/Legal-Assistant-v3)
**Script**: [`scripts/setup-github-governance.sh`](../../scripts/setup-github-governance.sh) (idempotent; safe to re-run)

This is the record of what was created on GitHub during Stage 1c, and the manual GUI steps that the script could not automate. After Stage 1c, the bootstrap exception ends — every subsequent change to conventions, code, or governance flows through the normal PR process (see [`README.md`](README.md) "Bootstrap exception").

## Labels (24 total)

The script removes the 9 default GitHub labels (none are in our taxonomy — see [`labels.md`](labels.md)) and creates the labels listed below. Color families are presentational; the rules are in `labels.md`.

### `type:*` — exactly one per issue (8 labels)

| Label | Color | Meaning |
|---|---|---|
| `type:feat`     | `#0e8a16` | New functionality (mirrors `feat/` branch type) |
| `type:fix`      | `#b60205` | Bug fix (mirrors `fix/`) |
| `type:chore`    | `#1d76db` | Infra / config / housekeeping |
| `type:docs`     | `#0075ca` | Documentation only |
| `type:refactor` | `#5319e7` | Code reorganization, no behavior change |
| `type:test`     | `#0052cc` | Test additions / fixes only |
| `type:decision` | `#8b5cf6` | Tracks a decision; closes when recorded |
| `type:audit`    | `#6f42c1` | Investigative work whose deliverable is a finding |

### `area:*` — one or more per issue (9 labels)

| Label | Color | Where |
|---|---|---|
| `area:corpus`     | `#1abc9c` | Document corpus content + organization |
| `area:ingestion`  | `#16a085` | Document parsing, chunking, embedding pipeline |
| `area:weaviate`   | `#0e9aa7` | Weaviate schema, collections, queries, deployment |
| `area:mcp`        | `#00bcd4` | MCP server surface |
| `area:enrichment` | `#00838f` | CF Workers / R2 / D1 enrichment pipeline |
| `area:provenance` | `#006064` | Bates-numbered chain of custody |
| `area:v2-prod`    | `#455a64` | Anything touching the running v2 instance |
| `area:infra`      | `#546e7a` | Repo / build / CI / Doppler / Tailscale / deploy |
| `area:planning`   | `#78909c` | Planning docs, ADRs, decision records, conventions |

### `status:*` — optional, reflects state (7 labels)

Active states get attention colors (yellow / pink / lavender / pale-yellow); terminal states get gray.

| Label | Color | When |
|---|---|---|
| `status:in-progress`    | `#fbca04` | Branch / worktree active, work moving |
| `status:blocked`        | `#e99695` | Paused on external input or another issue |
| `status:needs-decision` | `#d4c5f9` | Paused pending a `type:decision` issue |
| `status:proposal`       | `#fef2c0` | Open candidate; not yet committed |
| `status:wontfix`        | `#cccccc` | Closed: not going to do this |
| `status:duplicate`      | `#cfd3d7` | Closed; link the surviving issue |
| `status:obsolete`       | `#bdbdbd` | Closed; underlying premise no longer holds |

### Default labels removed

`bug`, `documentation`, `duplicate` (superseded by `status:duplicate`), `enhancement`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix` (superseded by `status:wontfix`).

## Milestones (7 total)

Each milestone has the body structure required by [`milestones.md`](milestones.md): `## Goal` / `## Scope (in)` / `## Scope (out)` / `## Definition of done`. Numbers are sticky once assigned.

| # | Title | State | Active? | Description |
|---|---|---|---|---|
| 2 | `0-extraction-and-bootstrap`  | open | **Active** | Move legal-assistant code out of `hole-backend` into this repo with workspace scaffolding in place. |
| 3 | `1-corpus-consolidation`      | open | future | Bring all corpus sources into one accountable place. |
| 4 | `2-corpus-cleaning`           | open | future | Dedup, normalize, validate the consolidated corpus. |
| 5 | `3-v2-diagnostics`            | open | future | Inventory v2 tools, link tools to code, identify deployed-elsewhere code. |
| 6 | `4-azure-corpus-analysis`     | open | future | What Azure DI produced; the provenance gap; comparison set for unstructured. |
| 7 | `5-current-schema-analysis`   | open | future | Per-collection assessment of Weaviate schema; keep / migrate / rebuild. |
| 8 | `6-v3-design`                 | open | future | v3 architecture choices grounded in the prior milestones' findings. |

> Note on numbering: milestone numbers go 2–8, not 1–7. Milestone #1 was `test-milestone-debug` created during script smoke-testing and immediately deleted; GitHub does not reuse milestone numbers.

> "Active" is convention, not a GitHub state. Per [`milestones.md`](milestones.md): at most one milestone is treated as active at a time. Today: `0-extraction-and-bootstrap`.

## Project (Projects v2)

**Name**: [`Legal-Assistant-v3 — work`](https://github.com/orgs/The-HOLE-Foundation/projects/15)
**Number**: 15
**Owner**: `The-HOLE-Foundation` org
**Items at bootstrap**: 16 (all foundational issues; see below)

The script creates the project and adds every foundational issue as an item. Some configuration the gh CLI cannot script today and must be done in the GH UI (see "Manual GUI follow-ups" below).

## Foundational issues (16 total)

| # | Title | Type | Area(s) | Milestone |
|---|---|---|---|---|
| 1  | Extract legal-assistant code from hole-backend monorepo (Stage 3) | chore | infra, planning | 0-extraction-and-bootstrap |
| 2  | Bootstrap GitHub governance for Legal-Assistant-v3 (Stage 1c) | chore | infra, planning | 0-extraction-and-bootstrap |
| 3  | Run pre-extraction verification (Stage 2) | chore | infra, planning | 0-extraction-and-bootstrap |
| 4  | Bootstrap PR — workspace scaffolding after extraction (Stage 3 follow-up) | chore | infra | 0-extraction-and-bootstrap |
| 5  | Open Phase 1E cleanup PR on hole-backend (Stage 4) | chore | infra | 0-extraction-and-bootstrap |
| 6  | Transfer in-scope hole-backend issues to Legal-Assistant-v3 | chore | planning | 0-extraction-and-bootstrap |
| 7  | D-1 — Decide disposition of legacy hole-langchain repo | decision | planning, corpus | 1-corpus-consolidation |
| 8  | D-2 — Decide disposition of Jobikinobi/HOLE-Legal-Intelligence-alpha | decision | planning, corpus | 4-azure-corpus-analysis |
| 9  | D-3 — Disposition of stray RAID-resident clones | decision | planning, corpus | 1-corpus-consolidation |
| 10 | D-4 — Decide v3 redesign: LangChain or FastMCP | decision | mcp, planning | 6-v3-design |
| 11 | D-5 — Decide MCP tool-surface reduction | decision | mcp, planning | 6-v3-design |
| 12 | D-6 — Decide disposition of apps/legal-research-mcp | decision | mcp, planning | 3-v2-diagnostics |
| 13 | D-7 — Decide disposition of apps/langchain-backend | decision | mcp, planning | 3-v2-diagnostics |
| 14 | D-8 — Decide data-archive storage strategy | decision | corpus, infra | 1-corpus-consolidation |
| 15 | D-9 — Identify deployed MCP server code location | decision | mcp, v2-prod | 3-v2-diagnostics |
| 16 | D-11 — Decide unstructured-llms-full.txt retention | decision | planning, ingestion | 6-v3-design |

Issue #1 was a pre-existing placeholder filed before Stage 1c; the script repurposed it in place (renamed, relabeled, milestoned, body rewritten).

**D-10 (photos / videos ingest) is intentionally not filed.** Convention requires every issue have a milestone; D-10's target stage is post-`6-v3-design` and that milestone doesn't exist yet. D-10 stays in [`docs/planning/deferred-decisions.md`](../planning/deferred-decisions.md) until the multimedia milestone is defined, at which point the script can be amended to seed it.

## CI

- [`.github/workflows/build-and-test.yml`](../../.github/workflows/build-and-test.yml) — stub workflow whose job name `build-and-test` matches the org-level ruleset's required status check.
- The Stage 3 bootstrap PR replaces the stub with a real Python + workspace test pipeline (per [`docs/planning/extraction-plan.md`](../planning/extraction-plan.md) §7).

## Branch protection (org-level ruleset)

Inherited from the `New-Work-Goes-On-Worktrees` ruleset on the `The-HOLE-Foundation` org (id `14383446`). It enforces:

- Changes to `main` must be made through a pull request
- Required status check: `build-and-test`

The Stage 1a / 1b / 1c commits each landed under a one-time admin bypass — see "Bootstrap exception" in [`README.md`](README.md). After Stage 1c the bypass should not be used; the `build-and-test` stub workflow now exists, so PRs to `main` can pass the check.

## Manual GUI follow-ups

Things the script could not do via gh CLI; complete these in the GitHub UI when convenient. Issue #2 (Bootstrap GitHub governance) **does not close** until these are verified.

### Project Status field options

The default Status options that GitHub creates with a new project (`Todo`, `In Progress`, `Done`) don't match our [`projects.md`](projects.md) column scheme. Edit Status to:

- `Backlog`     — open, no `status:in-progress`
- `In progress` — has `status:in-progress` label
- `In review`   — has an open PR
- `Blocked`     — has `status:blocked` or `status:needs-decision`
- `Done`        — closed

### Project workflow automations

In project Settings → Workflows, enable:

- **Auto-add to project** — filter `is:issue is:pr repo:The-HOLE-Foundation/Legal-Assistant-v3`
- **Item closed → Done**
- **Pull request linked → In review**
- **Auto-archive items closed > 14 days**

### Project saved views

Add four views (filters from [`projects.md`](projects.md)):

| View | Filter |
|---|---|
| `Active`               | `is:open milestone:"0-extraction-and-bootstrap"` |
| `Backlog`              | `is:open -milestone:"0-extraction-and-bootstrap"` |
| `In review`            | `is:pr is:open` |
| `Blocked / decisions`  | `is:open label:"status:blocked","status:needs-decision"` |

Update the active milestone in the `Active` and `Backlog` view filters whenever the active milestone changes.

### Verify the build-and-test workflow

After the Stage 1c push, check that a workflow run appears on the commit and that the check `build-and-test` is reported. If the org-ruleset's required check is named differently than expected, adjust the job name in `.github/workflows/build-and-test.yml`.

## What ends here

This is the **last** bootstrap-exception commit. From this commit forward, every change to this repo (including subsequent updates to the conventions docs, the script, this log, the workflows) flows through the normal PR process: branch off `main` per [`branches-and-worktrees.md`](branches-and-worktrees.md), open a PR, get CodeRabbit + Copilot review, merge once feedback is nitpick-only.

If the script needs to be extended (e.g., to add D-10's milestone when multimedia ingest becomes scope, or to amend a label color), do it on a branch in a normal PR. Re-running the script on `main` is safe — it's idempotent — but its mutations to GitHub are not gated by code review and are therefore not the place to evolve governance behavior.
