# chezmoi project profiles

A **profile** is the per-project slice of this dotfiles repo: the brew formulae, run-once setup steps, and documentation needed to make a machine ready to work on a specific project (`legal`, `godocs`, `oversight`, …). The core stack stays in `dot_Brewfile.core` and the cross-cutting `run_once_*` scripts; everything project-specific lives in a sibling `dot_Brewfile.<key>` + `run_once_after_install-project-<key>.sh.tmpl` + `docs/profiles/<key>.md`, activated by adding `<key>` to the `projects` list in `~/.config/chezmoi/chezmoi.toml`. One machine can carry many profiles; an LXD container usually carries one.

## Active profiles

| Key | Repo | Brewfile | run_once | Docs | Notes |
|---|---|---|---|---|---|
| `legal` | [Legal-Assistant-v3](https://github.com/The-HOLE-Foundation/Legal-Assistant-v3) | [`dot_Brewfile.legal`](../../dot_Brewfile.legal) | [`run_once_after_install-project-legal.sh.tmpl`](../../run_once_after_install-project-legal.sh.tmpl) | [`legal.md`](legal.md) | OCR fallback pending CEO Q1 ([THE-51](/THE/issues/THE-51)). |
| `godocs` | [hole-godocs](https://github.com/the-hole-foundation/hole-godocs) | [`dot_Brewfile.godocs`](../../dot_Brewfile.godocs) | [`run_once_after_install-project-godocs.sh.tmpl`](../../run_once_after_install-project-godocs.sh.tmpl) | [`godocs.md`](godocs.md) | Go 1.25 pin (keg-only); LibreOffice via apt/cask in run_once ([THE-66](/THE/issues/THE-66)). |
| `oversight` | [org-governance](https://github.com/the-hole-foundation/org-governance) | [`dot_Brewfile.oversight`](../../dot_Brewfile.oversight) *(empty)* | [`run_once_after_install-project-oversight.sh.tmpl`](../../run_once_after_install-project-oversight.sh.tmpl) | [`oversight.md`](oversight.md) | **docs-only** in v1 per board Q3 ([THE-51](/THE/issues/THE-51)); promote when a container workload lands. |

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

## New-project hook

Adding a chezmoi profile is wired into the Paperclip flow so it is a default step, not a memory test.

**Mechanism: a Paperclip routine** — `Weekly chezmoi profile audit` ([routine `f841b530`](/THE/projects/dotfiles)), assigned to CTO, in the `dotfiles` project.

- **Schedule trigger** (`0 9 * * 1` UTC, weekly Monday 09:00 UTC) — safety net that catches profiles missed during project creation.
- **API trigger** — fired manually right after a new project is created, so the audit runs immediately instead of waiting for Monday.

On each fire the routine creates one audit run-issue assigned to CTO. The CTO heartbeat:

1. Reads all non-archived projects via `GET /api/companies/{companyId}/projects`.
2. Skips meta projects (`onboarding`, `dotfiles` — they do not need profiles).
3. Diffs project names against `dot_Brewfile.<key>` files in this repo. The mapping is intentionally loose (`legal-assistant-v3` → `legal`, `org-governance` → `oversight`); the agent applies judgement rather than insisting on exact string equality.
4. For each genuine gap, searches open issues with `q=chezmoi profile <name>` first. If an open profile-onboarding issue already exists, it is skipped — **this is the spam gate that satisfies "fire exactly once per genuinely-new project"**.
5. Files one child issue per new gap with the 10-step checklist inlined, then closes the audit run with a one-line summary.

### Firing manually after creating a project

```bash
# Fire the API trigger right after `paperclip project create` (see api-reference for the trigger id).
curl -X POST "$PAPERCLIP_API_URL/api/routines/f841b530-7249-4db8-9c46-ad4aa6530fd1/run" \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  -H "X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID" \
  -H "Content-Type: application/json" \
  -d '{"source":"manual","triggerId":"425f333a-79c7-4d97-804a-64a2e5c4919c","idempotencyKey":"profile-audit:'"$(date -u +%Y%m%d)"'"}'
```

The `idempotencyKey` plus `concurrencyPolicy: skip_if_active` ensure repeated manual fires on the same day do not pile up runs.

### Disable / maintain

- **Pause:** `PATCH /api/routines/f841b530-7249-4db8-9c46-ad4aa6530fd1 {"status":"paused"}`.
- **Change cadence:** `PATCH /api/routine-triggers/610c994f-c52e-44f2-87e2-35f69f261674 {"cronExpression":"…"}`.
- **Archive (terminal):** `PATCH /api/routines/f841b530-7249-4db8-9c46-ad4aa6530fd1 {"status":"archived"}`.

If the routine is paused or archived, fall back to filing the issue by hand using the template below.

### Manual fallback — issue template

Use this exact template if the routine is disabled or you would rather not wait for Monday:

```md
**Title:** Add chezmoi profile for `<key>`

**Parent:** dotfiles project · **Assignee:** CTO · **Priority:** low

## Scope

Add a chezmoi profile for the newly created Paperclip project `<project-name>`. Follow the 10-step checklist in [`docs/profiles/README.md`](https://github.com/Jobikinobi/dotfiles/blob/main/docs/profiles/README.md#adding-a-new-project).

## Acceptance

- `dot_Brewfile.<key>` + `run_once_after_install-project-<key>.sh.tmpl` + `docs/profiles/<key>.md` merged on `main`.
- `scripts/test-profile.sh <key>` passes locally.
- Profile row added to the table in `docs/profiles/README.md`.
```

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

## Verification

Each profile doc declares the binaries it promises to put on `PATH` in a fenced ` ```text ` block under a fixed `## Installed binaries` heading. [`scripts/test-profile.sh`](../../scripts/test-profile.sh) parses that block and turns it into a build+assert harness — the verification gate that catches profile drift before it lands on `main`.

**CI enforces this on every PR.** The GitHub Actions workflow ([.github/workflows/ci.yml](../../.github/workflows/ci.yml)) runs a `fail-fast: false` matrix that calls `scripts/test-profile.sh --project <key>` once per active profile (`core, legal, godocs, oversight`). A PR that breaks the binary contract declared in any `docs/profiles/<key>.md` — e.g. removing `tesseract` from `dot_Brewfile.legal` while leaving it listed in `docs/profiles/legal.md` — fails that profile's matrix leg and blocks merge to `main`. The other legs still run so multiple regressions surface in a single CI run. Adding a new profile leg requires shipping its `docs/profiles/<key>.md` in the same PR (see *Adding a new project*, step 5).

### The convention

In each `docs/profiles/<key>.md`, immediately after the "What this profile installs" prose, add a section that looks like this:

````markdown
## Installed binaries

<one-sentence explanation>

```text
gs
tesseract
# Lines starting with `#` are comments. Blank lines are ignored.
```
````

Rules:

- The heading must be exactly `## Installed binaries`.
- The block must be a fenced ` ```text ` block. Other languages are ignored by the parser.
- One binary name per line. **Binary names, not formula names** — e.g. `gs` not `ghostscript`, `aws` not `awscli`, `mutool` not `mupdf-tools`.
- Lines starting with `#` and blank lines are ignored, so you can annotate why a brew is intentionally not asserted (keg-only formulae like `go@1.25` whose PATH wiring lives in `~/.zshrc.d/`, for example).
- An **empty block** (only comments and blanks) means "this profile installs nothing beyond the core baseline" — the harness enforces that invariant with a `brew list --formula` diff against a fresh core build. This is how [`oversight.md`](oversight.md) is verified.

### Running the harness

```bash
# Validate a populated profile end-to-end. Builds Dockerfile.test with
# CHEZMOI_PROJECT=<key> baked in, then asserts each declared binary is
# on PATH via `docker run --rm <image> command -v <bin>`.
scripts/test-profile.sh --project legal
scripts/test-profile.sh --project godocs

# Validate the docs-only invariant. Builds both core and oversight images,
# diffs `brew list --formula`, and fails if oversight has any extras.
scripts/test-profile.sh --project oversight

# Build the core baseline only (no per-profile asserts).
scripts/test-profile.sh --project core

# Build from a non-default branch. Useful when iterating on profile changes
# in a feature branch — the harness pushes --branch through as a build-arg
# so chezmoi clones the right ref inside the container.
scripts/test-profile.sh --project legal --branch my-feature-branch
```

Exit codes: `0` on success, non-zero on any missing binary or any docs-only extra. Failures print the offending profile + binary so the cause is obvious in CI logs.

Run requirements: a reachable Docker daemon (`docker info` succeeds). No Tailscale, Doppler, or external network access beyond Docker Hub / GHCR is required — profile verification is binary-presence only, not a full functional smoke. Build cache is reused across profile keys (no `--no-cache` by default) so reruns are fast.

## Provisioning a container

Once a profile exists, stand up a per-project LXD container on the canonical Proxmox host with [`scripts/provision-lxd.sh`](../../scripts/provision-lxd.sh):

```bash
# inspect first — prints the rendered cloud-init + proposed remote command,
# never touches Doppler or the Proxmox host
scripts/provision-lxd.sh --project legal --name the-legal-01 --dry-run

# launch for real (requires doppler login + tailnet reachability)
scripts/provision-lxd.sh --project legal --name the-legal-01
```

The script:

- validates `<key>` against `dot_Brewfile.<key>` so typos fail fast,
- fetches a **single-use, ephemeral** Tailscale auth key from Doppler scope `dotfiles/lxd-bootstrap` (secret `TAILSCALE_AUTHKEY`),
- renders a cloud-init that pre-seeds `~/.config/chezmoi/chezmoi.toml` with `projects = ["<key>"]` + `lxd_profile = "<key>"` and runs `chezmoi init --apply jobikinobi`,
- SSHes to the Proxmox host (default `proxmox.lemming-likert.ts.net`; override with `--host` or `$LXD_PROXMOX_HOST`) and runs `lxc init` / `lxc config set user.user-data` / `lxc start` — the user-data is streamed over stdin so the auth key never lands in remote `ps` output.

The age decryption key (`~/.config/chezmoi/key.txt`) is intentionally **not** baked into cloud-init. Provision it out-of-band after the container is reachable on the tailnet if the dotfiles include encrypted files you need on that host. See [THE-68](/THE/issues/THE-68) for the design notes.

## Related

- Parent plan: [THE-51 plan document](/THE/issues/THE-51#document-plan)
- Top-level repo entry point: [`README.md`](../../README.md)
- Agent-facing repo guide: [`CLAUDE.md`](../../CLAUDE.md)
