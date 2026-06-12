# Legal-Assistant-v3 — project guide

This file is read at the start of every Claude Code session opened in this repo. Keep it short. Detailed material lives in `docs/conventions/` and `docs/planning/`; this file points to it.

## What this project is

A personal legal-research and casefile system the user (JTH) designed and uses to litigate his own case. It does one thing very well today and that capability must be preserved through the v3 refactor: **finding case law in `billofreviewv2` (Weaviate) to support legal-document drafting** — the "research stage" workflow.

The reason for v3 is the **courtroom stage**: when arguing a motion or questioning a witness, finding a fact in the casefile is necessary but not sufficient. The user must be able to produce the **original document at a precise Bates-numbered location** and pull it from a physical binder. The prior Azure Document Intelligence pipeline (now exhausted) handled retrieval but not provenance; the v3 refactor fixes that gap using `unstructured` for ingestion and a metadata schema that preserves the chunk → page → Bates-stamp chain.

> **Provenance test for any architectural decision**: does this preserve or strengthen Bates-numbered provenance from corpus chunk to original-document binder? If a proposal trades provenance for retrieval cleverness, push back. If it locks down provenance at the cost of some elegance, prefer it.

## Stewardship and topology

- **This repo** owns v3 design + v2 production stewardship (transfer happens at the end of the hole-backend extraction).
- **v2 in production** runs on the Mac Mini (Colima) and locally on OrbStack. Don't break it during v3 work.
- **Sister repo**: [`The-HOLE-Foundation/hole-backend`](https://github.com/The-HOLE-Foundation/hole-backend) — FOIA / TransparencyAI tooling. Legal-assistant code is being extracted *from* there *into* here (see `docs/planning/`).
- **Productization**: this *may* eventually become a feature offering on `theholetruth.org`, but that is not a present-day driver and should not weight architectural decisions.

## Governance — read these before opening issues, branches, or PRs

| Topic | Doc |
|---|---|
| What goes in an issue (and what doesn't) | [`docs/conventions/issues.md`](docs/conventions/issues.md) |
| How milestones map to stages of work | [`docs/conventions/milestones.md`](docs/conventions/milestones.md) |
| Branch naming + worktree scope rules | [`docs/conventions/branches-and-worktrees.md`](docs/conventions/branches-and-worktrees.md) |
| Label taxonomy | [`docs/conventions/labels.md`](docs/conventions/labels.md) |
| Project board configuration | [`docs/conventions/projects.md`](docs/conventions/projects.md) |
| Index | [`docs/conventions/README.md`](docs/conventions/README.md) |

These conventions are personal/solo-discipline rigor today (no formal CODEOWNERS or branch protection). They are **load-bearing** for managing scope as the project grows — if you find yourself wanting to violate one, treat that as a signal to slow down, not a hint to skip the rule.

## Pace discipline

- **Move stepwise.** Defer every decision that doesn't have to be made *right now* to make the current step work. Capture deferred decisions in `docs/planning/deferred-decisions.md` (or the active plan's deferred-log section), not as half-built code.
- **Consolidate before investigating.** When multiple sources of truth exist for one thing (legacy folders, parallel repos, scattered config), bring them into one accountable place before forming opinions about disposition.
- **Don't break what works.** v2 in production must keep serving legal queries through the v3 transition. Every change is a candidate regression.
- **The user controls scope.** Ask before widening; never add scope on your own.

## Stack (current; subject to v3 design)

- Python · LangChain · LangGraph (currently — possible FastMCP rebuild is an open v3 design question)
- Weaviate (Mac Mini, version 1.37.x) — vector store
- Voyage embeddings
- Cloudflare Workers (legal-enrichment queue) + R2 (data archive: `hole-r2:hole-legal-assistant`)
- Doppler for legacy secrets and dotenvx for the new `dotfiles-dotenvxx` profile — never read raw config files (`.env`, `~/.config/rclone/rclone.conf`, etc.) when a managed loader (`doppler run -- <cmd>` or `dotenvx run -f ... -- <cmd>`) will do
- Tailscale: Mac Mini host

## Repo location

Working tree: `/Volumes/HOLE-RAID-DRIVE/Projects/Legal-Assistant-v3` (canonical).
Origin: `https://github.com/The-HOLE-Foundation/Legal-Assistant-v3.git`.

## What to expect during the extraction phase

This repo is *being populated* from `hole-backend` via `git filter-repo`. Expect:
- A side-branch import of filtered history merged into `main` with `--allow-unrelated-histories`. No force-push; existing main lineage (governance docs) preserved as one merge parent, imported hole-backend history as the other.
- A bootstrap PR that adds the Python/uv workspace scaffolding (`pyproject.toml`, `uv.lock`, `.python-version`, `.mcp.json`, GHA workflows, Postman repo-sync scaffold, README) and re-applies the governance docs above. This is a Python project; no `package.json`/`turbo.json` at the root (the one CF Worker subapp manages itself).
- The v3 design wave begins **after** that bootstrap settles. Do not start v3 implementation work mid-extraction.

See `docs/planning/extraction-plan.md` (once written in Stage 1b) for the canonical extraction sequence.
