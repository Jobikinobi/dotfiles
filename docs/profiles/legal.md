# `legal` profile

Per-project chezmoi profile for the [Legal-Assistant-v3](https://github.com/The-HOLE-Foundation/Legal-Assistant-v3) repo — the HOLE Foundation's legal-research and casefile system (Weaviate corpus, LangChain MCP, Apple Vision OCR rebuild pipeline).

Activate by adding `"legal"` to the `projects` list in `~/.config/chezmoi/chezmoi.toml`, then re-run `chezmoi apply`. With `projects = []` the profile is a no-op.

## What this profile installs

Brews from [`dot_Brewfile.legal`](../../dot_Brewfile.legal):

| Package | Purpose |
|---|---|
| `ghostscript` | Post-OCR linearization / optimization pass invoked by `av-ocr-rebuild --optimize`. |
| `tesseract` *(pending)* | OCR fallback for non-macOS hosts (Apple Vision is macOS-only). **Pending CEO answer** to plan Q1 — commented placeholder in the Brewfile until confirmed. |

Already provided by [`dot_Brewfile.core`](../../dot_Brewfile.core) and therefore not duplicated here: `pyenv`, `uv`, `doppler`, `go`, `git`, `gh`, `lazygit`, `jq`, `fd`, `ripgrep`.

The [`run_once_after_install-project-legal.sh.tmpl`](../../run_once_after_install-project-legal.sh.tmpl) script self-gates with `{{ if not (has "legal" .projects) }}exit 0{{ end }}` and on activation:

- Defensively installs `uv` via `curl -LsSf https://astral.sh/uv/install.sh | sh` when `uv` is not already on PATH (the brew formula is the primary install).
- Prints a setup banner with the manual next steps below.

## What you must do manually

The script intentionally stops short of any step that needs credentials a fresh host does not yet have:

1. **Authenticate Doppler**:
   ```bash
   doppler login
   doppler setup --project mcp-servers --config dev
   ```
2. **Clone the repo and sync the uv workspace**:
   ```bash
   git clone git@github.com:The-HOLE-Foundation/Legal-Assistant-v3.git ~/src/Legal-Assistant-v3
   cd ~/src/Legal-Assistant-v3
   uv sync --all-packages --all-extras
   ```
3. **(macOS only) Build the Apple Vision OCR Swift helper**:
   ```bash
   bash packages/av-ocr-rebuild/scripts/build.sh
   ```
   Requires Xcode CLI tools: `xcode-select --install`.
4. **Verify reachability of the production Weaviate** over Tailscale:
   ```bash
   curl -sf http://mac-mini:8080/v1/.well-known/ready
   ```

## Doppler scopes

| Scope | Used by |
|---|---|
| project `mcp-servers`, config `dev` | The dev HTTP MCP (`apps/legal-mcp-container/`) and the production stdio MCP launched from the production-deployment worktree. |

`doppler setup` writes the scope binding to `~/.doppler` so subsequent `doppler run --` invocations resolve automatically.

## Known limitations

- **OCR backend is macOS-only.** The primary `av-ocr-rebuild` OCR engine is a Swift binary that calls Apple's Vision framework. On Linux containers there is currently no built-in fallback. *Pending CEO answer* to Q1 of the [parent plan](/THE/issues/THE-51#document-plan) on whether to ship Tesseract as the Linux fallback.
- **Weaviate is hosted off-box.** This profile does not stand up a local Weaviate; the production corpus lives on the Mac Mini at `mac-mini:8080` via Tailscale. Local OrbStack sandboxes (`localhost:8082`) are an operator choice, not provisioned here.
- **Git+SSH credentials required.** Cloning over SSH assumes a working `~/.ssh/id_*` and a key registered with GitHub. Fresh containers must run `ssh-keygen` and add the public key to GitHub before step 2 above.

## Related

- Parent plan: [THE-51 plan document](/THE/issues/THE-51#document-plan)
- Profile system overview: [`docs/profiles/README.md`](README.md)
- Upstream repo: [Legal-Assistant-v3](https://github.com/The-HOLE-Foundation/Legal-Assistant-v3)
