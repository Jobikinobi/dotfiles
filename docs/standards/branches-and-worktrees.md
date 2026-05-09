# Branches and worktrees

> **Rule.** One branch per issue, one worktree per feature, **the whole feature in one worktree**.

These two topics live in one doc because they're tightly coupled — a branch without a worktree is a half-thought, and a worktree without a clear branch+issue mapping is how repos get junk-drawer scope creep.

## Branches

### Naming

`<type>/<short-slug>-<issue-number>`

Where `<type>` is one of:

- `feat` — new functionality
- `fix` — bug fix
- `chore` — infra / config / housekeeping
- `docs` — documentation only
- `refactor` — code reorganization, no behavior change
- `test` — test additions / fixes only

Examples:
- `feat/unstructured-pdf-ingestion-42`
- `fix/billofreviewv2-empty-result-handling-58`
- `chore/extract-from-hole-backend-3`
- `docs/conventions-bootstrap-1`

Slug rules: lowercase, hyphenated, 4 words max, descriptive of the *outcome* not the activity (`unstructured-pdf-ingestion`, not `add-pdf-stuff`).

### Base branch

Always `main`. No long-lived feature branches; no `develop`/`release` branches. If a feature is too big for one branch, split the issue (see [`issues.md`](issues.md)).

### Force-push policy

- Force-push **allowed** on a PR branch that hasn't yet been reviewed.
- Force-push **discouraged** on a PR after review has started — push fix-up commits or a clean rebase, but communicate.
- Force-push **forbidden** on `main`, except for project wide conventions, github workflows, or other matters in which code quality is not a serious concern and the interest in immediately establishing something as the baseline overrides the normal commit, review, merge worflow. As a rule of thumb, the primary pathway is to add to a branch away from main, commit a pr, submit work, obtain feedback from coderabbit, and once all CR feedback is merely nitpicking, it is green to merge. (One anticipated exception: the legal-assistant extraction's single force-push to wipe the prologue commits and seed `main` with filtered history from `hole-backend`. To be documented in advance in `docs/planning/extraction-plan.md` — the Stage 1b deliverable. After that, never again on `main`.)

### Merge strategy

- **Squash merge** for `feat`, `fix`, `chore` — keeps `main` history readable, one commit per closed issue
- **Rebase merge** for `docs`, `refactor`, `test` — preserves the commit-level breakdown when it's useful
- **No merge commits on `main`** — repo setting enforces this when GitHub config is bootstrapped (Stage 1c)
- **Delete branch on merge** — repo setting enforces; clean up worktrees too (see below)

## Worktrees

### Why worktrees at all

Multiple concurrent feature efforts without `git stash` juggling. Each worktree is a checkout of one branch in its own filesystem path; moving between worktrees is `cd`, not `git checkout`.

### One worktree per feature, whole feature

A "feature" here means **one closable issue** (or a tightly-bound umbrella of sub-issues whose acceptance criteria collectively define one head of work).

If the work is partial — "I'll handle part A in one worktree and part B in another" — that's the failure mode this rule exists to prevent. Symptoms include: shared changes that should be one commit drift across worktrees, you forget which worktree has which fragment, merging the two halves becomes a small ordeal.

The fix when you encounter the urge to spawn a second worktree mid-feature:

1. **Stop.** Don't open the second worktree.
2. Re-evaluate scope. If the feature really is two independent pieces, split the issue into two issues (umbrella-and-children pattern), close out the original branch/worktree at a sensible state, then create new branches and worktrees for the new sub-issues.
3. If the feature is genuinely one piece and you're tempted to split it for filesystem convenience, that's not a real reason. Push through in the existing worktree.

### Worktree location convention

`/Volumes/HOLE-RAID-DRIVE/Projects/Legal-Assistant-v3-worktrees/<branch-name>`

Sibling to the canonical checkout, not nested inside it. Each worktree is its own filesystem root for a clean Claude Code / IDE session.

### Creating a worktree

```bash
cd /Volumes/HOLE-RAID-DRIVE/Projects/Legal-Assistant-v3
git worktree add ../Legal-Assistant-v3-worktrees/feat/unstructured-pdf-42 \
  -b feat/unstructured-pdf-ingestion-42 main
```

(Or use the `using-git-worktrees` skill if you have it loaded — same outcome.)

### Lifecycle

- **Open** when issue moves to `status:in-progress`
- **Active** while the PR is in flight
- **Removed** when the PR merges (and the branch deletes — see merge policy)

```bash
git worktree remove ../Legal-Assistant-v3-worktrees/feat/unstructured-pdf-42
```

### Stale-worktree audit

Before starting any new feature: `git worktree list` and remove anything for a merged or abandoned branch. Stale worktrees confuse subsequent sessions; the audit is cheap.

## What to do when reality breaks the rule

Some rule violations are tells:

- **Two worktrees touching the same files**: scope was wrong; split the issue.
- **A long-running branch with multiple unrelated commits**: scope was wrong; split into multiple issues, cherry-pick the commits to focused branches, abandon the original.
- **A worktree on `main`**: you don't need a worktree to read `main` — use the canonical checkout.

Don't paper over a broken-rule symptom. Fix the underlying scope problem.
