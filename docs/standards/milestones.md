# Milestones

> **Rule.** Every issue belongs to exactly one milestone. Milestones are stages of work, not calendar buckets.

## What a milestone is

A milestone is **one stage of work** with a bounded scope and a definition of done. It groups all the issues whose closure is required for that stage to be complete.

The reason this matters: as the issue tracker fills up (it will — the project carries multiple deferred audits, a v3 design surface, ongoing v2 production work), the question "what's actually in scope right now?" needs a one-click answer. Milestones provide the filter. Filter `milestone:<active>` and you see exactly what closure of the current stage requires.

If the answer to "what's the current milestone?" is "uh, several" — the system has already failed.

## Naming

`<phase-letter>-<short-name>`. Examples:

- `0-extraction-and-bootstrap` — the transplant from `hole-backend` and standing up the workspace
- `1-corpus-consolidation` — bring all corpus sources into one accountable place
- `2-corpus-cleaning` — dedup, normalize, validate
- `3-v2-diagnostics` — inventory v2 tools, link tools to code, assess production state
- `4-azure-corpus-analysis` — what Azure produced, what's missing for courtroom use
- `5-current-schema-analysis` — what's in `billofreviewv2` and siblings; keep / migrate / rebuild
- `6-v3-design` — the design decisions informed by 1-5

Phase letters/numbers are sequential and sticky once assigned — don't renumber when you insert a milestone; instead use `2.5-…` or revisit the sequence at a wave boundary.

## Lifecycle

- **Active**: at most one milestone is `state:active` at a time. Rare exceptions only at transitions (closing one while opening the next).
- **Open** (not active): future stages, queued. Issues can be filed against them; just don't work them yet.
- **Closed**: stage is done. All child issues either closed or **explicitly migrated** to another milestone with a comment explaining why.

When a milestone closes, no orphan issues. Either:
- the issue is genuinely complete (close it), or
- the issue is no longer relevant (close as `status:obsolete` with a one-line explanation), or
- the issue is real but belongs in a later stage (move milestone, leave a note, keep it open).

## Description body — required structure

```
## Goal
One sentence. What the world looks like when this milestone closes.

## Scope (in)
- Bullet 1
- Bullet 2

## Scope (out)
- Bullet — explicitly excluded; deferred to milestone <X> or to deferred-decisions log

## Definition of done
- Concrete, falsifiable conditions
```

## Decision-issues vs work-issues

A milestone may contain a mix of work-issues (build / fix / refactor) and decision-issues (decide / record / defer). When a stage's closure depends on a decision, the decision-issue is in-scope for that milestone — not pushed off to the next one. Stages that depend on a yet-to-be-made decision tend to slip; surface that dependency by putting the decision-issue in the same milestone as the work it blocks.

## Linking

- Issue → milestone: required at issue creation. If you don't yet know the milestone, you don't yet know the scope.
- PR → milestone: inherited from its issue automatically; don't set it directly.
- Project board: filter views by milestone (see [`projects.md`](projects.md)).

## When to create a new milestone

When a stage of work has clearly differentiated goals from the current one, *and* it has a definition of done that doesn't depend on the current milestone's open issues. If those conditions don't hold, you don't have a new milestone — you have either a continuation or a sub-task.
