# Conventions

Project governance for `Legal-Assistant-v3`. Personal/solo-discipline rigor — not org-wide formality. Each doc states one rule and the *why* behind it.

| File | One-line rule |
|---|---|
| [`issues.md`](issues.md) | One issue = one bounded deliverable. Planning lives in `docs/planning/`; issues reference it, they don't carry it. |
| [`milestones.md`](milestones.md) | Every issue belongs to exactly one milestone. Milestones are stages of work, not calendar buckets. |
| [`branches-and-worktrees.md`](branches-and-worktrees.md) | One branch per issue, one worktree per feature, the whole feature in one worktree. |
| [`labels.md`](labels.md) | One `type:`, one or more `area:`, optional `status:`. No improvised labels. |
| [`projects.md`](projects.md) | One Project per repo, four standard views, auto-add new issues. |
| [`SETUP-LOG.md`](SETUP-LOG.md) | Record of what the Stage 1c bootstrap script created (label colors, milestone numbers, project URL, foundational issues, manual GUI follow-ups). |

## Why bother for a solo project

These rules exist to keep the planning surface readable as scope grows. The project will accumulate dozens of legacy artifacts to investigate (the manifest already lists six deferred audits), several v3 design decisions, v2 production tickets, and ongoing data-pipeline work. Without filterability you'd be reading every issue every time. With filterability — `milestone:active`, `area:corpus`, `status:blocked` — the question "what's in scope for me right now?" answers itself.

## When to violate a rule

When you find a real reason that wasn't anticipated. Then:

1. Stop.
2. Update the convention doc with the new case and the rationale.
3. Apply the updated convention going forward — don't carve a one-off exception.

If the rule itself turns out to be wrong, scrap and replace it. Conventions are governance, not theology.

## Bootstrap exception

Three bootstrap commits land directly on `main` without PRs:

1. **Stage 1a — governance protocol definitions** (this conventions tree + `CLAUDE.md` + `.gitignore`). The rule that says "PRs only" doesn't yet exist when it's being authored.
2. **Stage 1b — documentation reconciliation** (canonical extraction plan, deferred-decisions log, verbatim manifest copy, archive of the prompt docs that bootstrapped this work, relocation of `unstructured-llms-full.txt` to `docs/reference/`). The normal PR flow requires issues-and-branches scaffolding that depends on Stage 1c (GitHub labels, milestones, project board) — not yet in place.
3. **Stage 1c — governance implementation** (the `setup-github-governance.sh` script, `build-and-test` GHA workflow stub, `SETUP-LOG.md` record, this README update). The commit that documents the end of the bootstrap exception is itself the last bootstrap-exception commit — self-referential by necessity, since the issues-and-branches scaffolding only exists once 1c has run.

After Stage 1c lands, the normal flow applies to every change to these files (and to all code): branch off `main`, open a PR, get CodeRabbit + Copilot review, merge once feedback is nitpick-only.

## Pointers

- Project identity: [`/CLAUDE.md`](../../CLAUDE.md)
- Active planning: [`docs/planning/`](../planning/)
- Memory (Claude-side context, not committed): your machine's Claude project memory dir for this checkout
