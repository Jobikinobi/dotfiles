# Issues

> **Rule.** One issue = one bounded deliverable. Planning lives in `docs/planning/`; issues reference it, they don't carry it.

## What an issue *is*

- **Work** — something to build, fix, refactor, audit, or remove. Closes when acceptance criteria are met.
- **Decision** — something to decide. Closes when the outcome is recorded in a planning doc or `docs/planning/deferred-decisions.md` and any follow-up issues are filed.

Either kind has a defined endpoint. If you can't say what "closed" looks like, you don't have an issue yet.

## What an issue is **not**

- Free-form notes or session observations → planning doc
- Status updates without action → project board
- Speculative future work → `status:proposal` label or `deferred-decisions.md`
- Unbounded scope → decompose first, then open issues

## Issue body — lightweight structure

```
## What and why
One or two sentences. Link to the relevant planning doc or parent issue
instead of restating context that already lives there.

## Done when
- Falsifiable condition 1
- Falsifiable condition 2
- Out of scope: <anything explicitly excluded>
```

That's it. Add a `## Notes` section if something genuinely needs to travel with the issue — but if it belongs in a planning doc, put it there instead.

## One issue, one purpose

If the work outgrows one PR or worktree, split it:

1. Edit the original into an **umbrella** issue.
2. Open child issues, each independently closable.
3. Track children with `- [ ] #N` checklist in the umbrella body.
4. Umbrella closes when all children close.

Don't reopen closed issues for follow-up work — file new ones that link back.

## Lifecycle and labels

- (no status label) — open, awaiting work
- `status:in-progress` — branch / worktree active
- `status:blocked` — explain in a comment; remove when unblocked
- `status:needs-decision` — waiting on a decision issue
- `status:proposal` — candidate, not committed; may close without action

Closing: default = completed. Otherwise: `status:wontfix`, `status:duplicate`, `status:obsolete` (one-line reason in closing comment).

## Linking

- Issue → milestone: required (see [`milestones.md`](milestones.md))
- Issue → branch / PR: auto-linked via `<type>/<slug>-<num>` branch naming
- Umbrella ↔ children: `- [ ] #N` checklist in umbrella body

## Title

Imperative, present tense, names the deliverable:

- ✓ "Inventory v2 MCP tools and link each to its source"
- ✓ "Decide: keep LangChain/LangGraph vs rebuild as FastMCP"
- ✗ "v2 tooling problems"
- ✗ "Look into the Azure JSONs"
