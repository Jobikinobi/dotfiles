# Labels

> **Rule.** Every issue gets exactly one `type:` label and at least one `area:` label. `status:` labels are optional and reflect state. No improvised labels.

A small, fixed taxonomy is the price of filter-ability. The cost of a sprawling label set is that no two issues share quite the same label and filtering becomes useless.

## Type — exactly one

| Label | Meaning |
|---|---|
| `type:feat` | New functionality (mirrors the `feat/` branch type) |
| `type:fix` | Bug fix (mirrors `fix/`) |
| `type:chore` | Infra / config / housekeeping (mirrors `chore/`) |
| `type:docs` | Documentation only |
| `type:refactor` | Code reorganization, no behavior change |
| `type:test` | Test additions / fixes only |
| `type:decision` | Issue tracks a decision, not work — closure is a recorded outcome |
| `type:audit` | Investigative work whose deliverable is a finding/report; common in early stages |

If you're tempted to add a second `type:` label, you have two issues, not one with mixed types — split.

## Area — one or more

Areas reflect where in the system the work lives. The taxonomy below is **project-specific** — these are the areas that exist in `Legal-Assistant-v3` today. The *meta-rule* — taxonomy is enumerated here in the conventions doc, never invented at issue-creation time — is the convention; the specific labels listed are this repo's instantiation. A different repo would have a different list.

Extend the list by editing this file (and updating the GH labels in lockstep). New areas don't appear ad hoc.

| Label | Where |
|---|---|
| `area:corpus` | Document corpus content + organization (`legal-assistant-v3-corpus/`, R2 archive) |
| `area:ingestion` | Document parsing, chunking, embedding pipeline (`unstructured`, etc.) |
| `area:weaviate` | Schema, collections, queries, deployment of Weaviate |
| `area:mcp` | MCP server surface — tools, schemas, transports (stdio, HTTP) |
| `area:enrichment` | CF Workers / R2 / D1 enrichment pipeline |
| `area:provenance` | Bates-numbered chain-of-custody from chunk → original document |
| `area:v2-prod` | Anything touching the running v2 instance (OrbStack local or Mac Mini Colima) |
| `area:infra` | Repo / build / CI / Doppler / Tailscale / deployment plumbing |
| `area:planning` | Planning docs, ADRs, decision records, conventions |

A new area means a new `area:` label and an entry in this table — not a free-form tag.

## Status — optional, reflects state

(See [`issues.md`](issues.md) for lifecycle context.)

| Label | When |
|---|---|
| `status:in-progress` | Branch / worktree active, work moving |
| `status:blocked` | Paused on external input or another issue; comment explains |
| `status:needs-decision` | Work paused pending a `type:decision` issue's resolution |
| `status:proposal` | Open candidate; not yet committed to be done; may close without action |
| `status:wontfix` | Closed as: not going to do this. Reason in closing comment. |
| `status:duplicate` | Closed; link the surviving issue. |
| `status:obsolete` | Closed because the underlying premise no longer holds. Reason in closing comment. |

## Priority — *intentionally absent*

Priority labels (P0 / P1 / …) tend to lie. The active milestone IS the priority filter. If something genuinely jumps the queue, move it to the active milestone (and document why in a comment). If everything in the active milestone is "P1", reorder the milestone's issues with the project board's drag-to-reorder.

If priority labeling proves necessary later, add it deliberately to this file — don't sneak labels in via the GH UI.

## Color convention (for the GH bootstrap, Stage 1c)

- `type:*`, `area:*`, and `status:*` each get a visually distinct color family
- Within `status:*`, active-work states (`status:in-progress`, `status:needs-decision`, `status:blocked`) get an attention color (yellow / orange family); terminal states (`status:wontfix`, `status:duplicate`, `status:obsolete`) get gray

Specific shades chosen at Stage 1c bootstrap. This is presentational only — the rules above are the substance.

## Forbidden patterns

- Free-form labels invented at issue creation. If a new label seems needed, propose it in a `type:chore area:planning` issue first.
- Multiple `type:` labels on one issue (split instead).
- A label that means the same thing as another (`needs-info` vs `needs-decision` — pick one and delete the other).
