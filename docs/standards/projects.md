# Projects (GitHub Projects v2)

> **Rule.** One Project per repo. Four standard views. New issues auto-add. Filtering is by milestone and label, not by improvised columns.

## The Project

Name: `Legal-Assistant-v3 — work`

One project, this repo only. Cross-repo aggregation is not in scope today; if it becomes useful (e.g., when coordinating with `hole-backend` on shared interfaces), we'd file a `type:chore area:planning` issue to add a second project, not improvise.

## Standard views

The board is set up with four saved views. Each view is a filter, not a separate project.

### 1. `Active`

The default view. Filter:
```
is:open milestone:<current-active-milestone>
```

What you should see most of the time. If this view is overflowing, the active milestone is too big — split it.

### 2. `Backlog`

Issues filed against future (non-active) milestones, plus issues with no milestone (which should be empty per the [milestones rule](milestones.md), but the view exists to catch leaks).

```
is:open -milestone:<current-active-milestone>
```

### 3. `In review`

Open PRs across the repo. Useful when you have multiple branches and want to see at a glance what's awaiting merge.

```
is:pr is:open
```

### 4. `Blocked / decisions`

Issues currently pinned by a `status:blocked` or `status:needs-decision` label. The point: never lose track of what's stuck on what.

```
is:open label:status:blocked,status:needs-decision
```

## Columns

Columns reflect lifecycle, not categorization. Standard:

- **Backlog** — open, no `status:in-progress`
- **In progress** — `status:in-progress` issues
- **In review** — has an open PR
- **Blocked** — `status:blocked` or `status:needs-decision`
- **Done** — closed (auto-archive after 14 days)

GitHub's automation rules drive transitions where possible:

- Issue opens → Backlog
- Issue gets `status:in-progress` → In progress
- Linked PR opens → In review
- Issue closes → Done

## What goes on the project board

Every issue and every PR. Auto-add via project automation. Don't curate — the conventions are what define what's tracked, not your moment-to-moment decision about which issues are "real."

## What does NOT go on the project board

- Issues from other repos. (One project, this repo only — see top.)
- Discussions. GitHub Discussions are not used in this repo today; if they ever are, that's a `type:chore area:planning` decision, not an unannounced switch.

## Drift to watch for

- **Custom columns multiply.** If you find yourself wanting "Triaging" or "Up next" or "Maybe", you're trying to substitute board-state for label-state. Use labels and views; the columns are lifecycle only.
- **Issues stuck in In Progress for weeks.** Either work is genuinely blocked (use the label), or the work is complete and the issue/PR didn't get closed. Audit weekly.
- **The Done column overflowing.** Auto-archive should keep this small. If it doesn't, the auto-archive isn't running — fix the project setting.

## Bootstrap (Stage 1c)

The actual GH project + columns + automations get configured during Stage 1c, after the planning-doc reconciliation in Stage 1b tells us what the active milestone and first issues should be. This file describes the intended end state; Stage 1c implements it.
