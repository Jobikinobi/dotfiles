---
name: but
version: 0.23.2
description: "Commit, push, branch, and manage version control with GitButler. Use for commits, selective dirty-file or hunk commits, branches, diffs, PRs, history edits, squashes, amends, undo, merge, fetching, pulling and syncing a branch with its remote, apply, unapply, and linked worktrees. For selected dirty files or hunks, inspect with `but diff`; use compact `but status` for commit order, branch/stack placement, or conflict overview; use `but status -fv` when file IDs or per-commit file details matter. Replaces git write commands, including fetch and pull. Applies in every checkout of the repository, even when a plain branch is checked out, including linked worktrees such as `.claude/worktrees/*`, and to git writes made while testing or cleaning up (stash, checkout -- <file>, restore, reset)."
author: GitButler Team
stub: true
allowed-tools: Bash(but skill:*)
---

# GitButler CLI Skill

This file is a discovery stub. The usage guide is printed by the CLI, so it always matches the installed version. Before your first `but` command, run it on its own and read all of it; it is about 200 lines, and other commands in the same call get buried under it:

```bash
but skill
```

The guide covers the loop, IDs, rules, and task recipes. When you need a flag it does not mention, `but skill reference` prints each command's syntax and flags.

Follow the guide's applicable recipes and stopping rules.
