# AGENTS.md — dotfiles

See **[CLAUDE.md](CLAUDE.md)** — it is the single source of truth for this
repo's agent instructions, and it applies to any agent, Codex included.

This file used to be a verbatim copy of CLAUDE.md with "Claude" swapped for
"Codex". Two copies meant two things to keep current, and the copy had already
started to drift. A pointer cannot drift.

In particular, note the Critical Safety Rules in CLAUDE.md:

1. **NEVER run `chezmoi apply` without checking `chezmoi diff` first** — it overwrites live files
2. **NEVER run `chezmoi apply` in an agent session** — the user manages apply manually
3. Use `chezmoi re-add <file>` to update source from a live file (not the other way around)
4. For `.tmpl` files, edit the template directly — `re-add` would destroy template logic
