# `oversight` profile

Per-project chezmoi profile for the [org-governance](https://github.com/the-hole-foundation/org-governance) repo — The HOLE Foundation's board minutes, policies, bylaws, and meta-governance documents.

**Status in v1: docs-only.** This profile intentionally installs nothing beyond what [`dot_Brewfile.core`](../../dot_Brewfile.core) already ships. It exists to prove out the docs-only profile shape so the [profile table](README.md#active-profiles) and downstream tooling handle a profile that has no per-project brews and no container-bound setup steps.

Activate by adding `"oversight"` to the `projects` list in `~/.config/chezmoi/chezmoi.toml`, then re-run `chezmoi apply`. With `projects = []` the profile is a no-op.

## Why docs-only in v1

The governance project is markdown + scripts. Editing it requires no language toolchain beyond what the core dotfiles already provide (`git`, `gh`, an editor, `jq`, `fd`, `ripgrep`). There is no service to run, no Docker image to build, no database to seed, and no off-box dependency to reach.

Per board decision **Q3** on the [THE-51 plan](/THE/issues/THE-51#document-plan):

> `oversight`: real container target or docs-only row? — **Docs-only for v1. Promote when a real container workload lands.**

Shipping a populated `dot_Brewfile.oversight` or a real per-project run-once script today would add install cost (and CI matrix cost in T8) for no functional benefit. The profile shape is preserved so promotion is a follow-up edit, not a refactor.

## What this profile installs

Nothing. [`dot_Brewfile.oversight`](../../dot_Brewfile.oversight) is intentionally empty (header comment only). `brew bundle install --file=~/.Brewfile.oversight` is a clean no-op against an empty file, which is the behavior we want.

Already provided by [`dot_Brewfile.core`](../../dot_Brewfile.core) and therefore not duplicated here: `git`, `gh`, `lazygit`, `jq`, `fd`, `ripgrep`, `pyenv`, `uv`, `doppler`, `go`.

The [`run_once_after_install-project-oversight.sh.tmpl`](../../run_once_after_install-project-oversight.sh.tmpl) script self-gates with `{{ if not (has "oversight" .projects) }}exit 0{{ end }}`. On activation it prints a single line:

> oversight profile is docs-only in v1; promote when a container workload is defined.

That is the entirety of the active branch. No installs, no banner block, no manual-steps list — because there are none.

## What you must do manually

Clone the repo when you want to edit it:

```bash
git clone git@github.com:the-hole-foundation/org-governance.git ~/src/org-governance
```

No Doppler scope, no language sync, no service binding. Edit markdown, open a PR, done.

## Promotion triggers

Promote this profile from docs-only to a real profile when **any** of the following becomes true:

1. **A container workload is defined for governance work** — e.g. a static-site generator (Hugo, MkDocs), a board-portal web app, or an automation that needs to run inside an LXD container rather than on the editor's laptop. The profile then needs the toolchain to build/run that workload.
2. **A language-specific linter or formatter becomes mandatory** for governance PRs — e.g. `vale` for prose linting, `markdownlint-cli2` enforced in CI, or a custom Python/Go tool that lives in the governance repo. Add it to `dot_Brewfile.oversight` so contributors do not have to install it by hand.
3. **The repo grows non-doc artifacts** — e.g. signed PDFs that require a deterministic Ghostscript version, a meeting-recording transcription pipeline, or an export script with system-package dependencies. Anything that says "you also need X installed to work in this repo" is a promotion trigger.
4. **An LXD container is provisioned with `lxd_profile = "oversight"`** — at that point the profile must stand on its own end-to-end, not just on a laptop that already has the core dotfiles.

When promoting:

- Populate [`dot_Brewfile.oversight`](../../dot_Brewfile.oversight) with the new project-specific brews (never duplicate anything already in `dot_Brewfile.core`).
- Replace the one-line banner in [`run_once_after_install-project-oversight.sh.tmpl`](../../run_once_after_install-project-oversight.sh.tmpl) with the real setup steps, modeled on [`run_once_after_install-project-legal.sh.tmpl`](../../run_once_after_install-project-legal.sh.tmpl).
- Update the row in [`docs/profiles/README.md`](README.md) to drop the `docs-only` marker and link the new artifacts.
- Replace this section with the usual "What you must do manually" / "Doppler scopes" / "Known limitations" sections.

## Related

- Parent plan: [THE-51 plan document](/THE/issues/THE-51#document-plan) — see board decision Q3.
- Parent epic: [THE-50](/THE/issues/THE-50).
- This task: [THE-67](/THE/issues/THE-67).
- Profile system overview: [`docs/profiles/README.md`](README.md).
- Sibling profile (real, populated): [`legal.md`](legal.md) — use as the template when promoting.
- Upstream repo: [org-governance](https://github.com/the-hole-foundation/org-governance).
