# chezmoi project profiles

A **profile** is the per-project slice of this dotfiles repo: the brew formulae, run-once setup steps, and documentation needed to make a machine ready to work on a specific project (`legal`, `godocs`, `oversight`, …). The core stack stays in `dot_Brewfile.core` and the cross-cutting `run_once_*` scripts; everything project-specific lives in a sibling `dot_Brewfile.<key>` + `run_once_after_install-project-<key>.sh.tmpl` + `docs/profiles/<key>.md`, activated by adding `<key>` to the `projects` list in `~/.config/chezmoi/chezmoi.toml`. One machine can carry many profiles; an LXD container usually carries one.

## Active profiles

| Key | Repo | Brewfile | run_once | Docs | Notes |
|---|---|---|---|---|---|
| `legal` | [Legal-Assistant-v3](https://github.com/The-HOLE-Foundation/Legal-Assistant-v3) | [`dot_Brewfile.legal`](../../dot_Brewfile.legal) | [`run_once_after_install-project-legal.sh.tmpl`](../../run_once_after_install-project-legal.sh.tmpl) | [`legal.md`](legal.md) | OCR fallback pending CEO Q1 ([THE-51](/THE/issues/THE-51)). |
| `oversight` | [org-governance](https://github.com/the-hole-foundation/org-governance) | [`dot_Brewfile.oversight`](../../dot_Brewfile.oversight) *(empty)* | [`run_once_after_install-project-oversight.sh.tmpl`](../../run_once_after_install-project-oversight.sh.tmpl) | [`oversight.md`](oversight.md) | **docs-only** in v1 per board Q3 ([THE-51](/THE/issues/THE-51)); promote when a container workload lands. |

> Remaining row lands in a subsequent task: `godocs` in T4.

## Adding a new project

This is the 10-step checklist for adding a new chezmoi profile. The Paperclip "Add new project" routine links here, and the top-level `README.md` + `CLAUDE.md` cross-link to it so AI agents and new engineers see it before touching the repo.

1. Pick a short profile key — lowercase, kebab-case, ≤12 chars (e.g. `legal`, `godocs`, `oversight`).
2. Create `dot_Brewfile.<key>` with project-specific brew formulae only.
   Leave it empty if the project has no extra brews — file presence is the signal.
3. Create `run_once_after_install-project-<key>.sh.tmpl`. Start with the guard:
   `{{- if not (has "<key>" .projects) }}exit 0{{ end }}`
   Add any toolchain pins, language-runtime installs, or doppler-login hints.
4. Create `docs/profiles/<key>.md`: what's installed, what's manual, Doppler scope, repo URL.
5. Add a row for the new profile to `docs/profiles/README.md`.
6. Run `scripts/test-profile.sh <key>` locally — builds the Linux Docker image with `CHEZMOI_PROJECT=<key>` baked in, verifies key binaries are on PATH.
7. Open a PR titled `profile(<key>): add` with the `profile` label. CI runs the test-profile matrix.
8. After merge, validate end-to-end: `scripts/provision-lxd.sh --project <key> --name the-<key>-01`.
9. SSH in, run the project's own smoke (e.g. `uv sync` for python, `go build ./...` for go) and confirm it passes.
10. Update the project's own README to point at the profile so future engineers know it exists.

## Data variables

The profile system reads two variables from `~/.config/chezmoi/chezmoi.toml` (rendered from `.chezmoi.toml.tmpl`):

- `projects` — list of active profile keys for this machine. Example: `projects = ["legal", "godocs"]`. Empty list `[]` means "core only". Multiple profiles compose freely.
- `lxd_profile` — single scalar naming the LXD profile when this machine was provisioned as a container (e.g. `lxd_profile = "legal"`). Empty string on laptops. Used by host-side tooling, not by chezmoi itself.

In templates, gate per-project work with the existing `has` idiom:

```gotemplate
{{- if not (has "legal" .projects) }}exit 0{{ end }}
```

The interactive `chezmoi init` path prompts for both; the non-interactive (cloud-init pre-seed) path expects the values to be written into `~/.config/chezmoi/chezmoi.toml` before `chezmoi init` runs. Defaults are `projects = []` and `lxd_profile = ""` — a fresh machine with no answers does nothing project-specific.

## How it works

Per-project Brewfiles are installed by [`run_once_after_install-brewfile.sh.tmpl`](../../run_once_after_install-brewfile.sh.tmpl). After the core install block, the template ranges over `.projects` and emits one literal bash block per active profile:

```gotemplate
{{`{{- range .projects }}
if [[ -f "$HOME/.Brewfile.{{ . }}" ]]; then
  echo "→ Installing {{ . }} packages from ~/.Brewfile.{{ . }}..."
  brew bundle install --file="$HOME/.Brewfile.{{ . }}"
fi
{{- end }}`}}
```

The list is expanded by chezmoi at apply time, so the rendered script is plain bash — no runtime loop, no dependence on a `projects` env var. File presence is the gating signal: a key in `.projects` without a matching `~/.Brewfile.<key>` is a silent no-op, which lets profiles ship with only a `run_once_after_install-project-<key>.sh.tmpl` and no brews.

Per-project run-once scripts (`run_once_after_install-project-<key>.sh.tmpl`) self-gate with the `has` idiom shown in *Data variables* above. They run on every machine but exit early when their key is not in `.projects`.

## Related

- Parent plan: [THE-51 plan document](/THE/issues/THE-51#document-plan)
- Top-level repo entry point: [`README.md`](../../README.md)
- Agent-facing repo guide: [`CLAUDE.md`](../../CLAUDE.md)
