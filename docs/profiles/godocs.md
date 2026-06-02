# `godocs` profile

Per-project chezmoi profile for the [hole-godocs](https://github.com/the-hole-foundation/hole-godocs) repo — the HOLE Foundation's Go-based document ingestion and corpus management pipeline (Cloudflare R2 storage, layout-aware PDF extraction, headless LibreOffice conversion).

Activate by adding `"godocs"` to the `projects` list in `~/.config/chezmoi/chezmoi.toml`, then re-run `chezmoi apply`. With `projects = []` the profile is a no-op.

## What this profile installs

Brews from [`dot_Brewfile.godocs`](../../dot_Brewfile.godocs):

| Package | Purpose |
|---|---|
| `go@1.25` | Pinned Go toolchain matching the `toolchain` directive in upstream `hole-godocs/go.mod`. Keg-only; wired onto PATH by the run_once shim. |
| `rclone` | Primary sync tool for the R2 corpus buckets. |
| `awscli` | AWS SDK v2 CLI used for operator-side R2 debugging (presign, head-object, listing) against the S3-compatible endpoint. |
| `mupdf` | `mupdf` viewer used during ad-hoc PDF inspection. |
| `mupdf-tools` | `mutool` for layout-aware page extraction — invoked by `test-mupdf.sh` in the godocs repo. |

LibreOffice is installed by the [run_once script](../../run_once_after_install-project-godocs.sh.tmpl) rather than the Brewfile because Linuxbrew has no `libreoffice` formula and Homebrew Cask is macOS-only:

- **macOS** — `brew install --cask libreoffice` (skipped if `/Applications/LibreOffice.app` already exists).
- **Linux** — `sudo apt-get install -y libreoffice --no-install-recommends`.

Already provided by [`dot_Brewfile.core`](../../dot_Brewfile.core) and therefore not duplicated here: `git`, `gh`, `lazygit`, `jq`, `fd`, `ripgrep`, `doppler`, `uv`, `pyenv`, unversioned `go`.

## Installed binaries

[`scripts/test-profile.sh`](../../scripts/test-profile.sh) asserts each entry below is on `PATH` inside an applied container (`docker run --rm <image> command -v <bin>`). Names are binary names, not brew formula names — e.g. `aws` (not `awscli`), `mutool` (not `mupdf-tools`). Lines starting with `#` and blank lines are ignored. See [`docs/profiles/README.md#verification`](README.md#verification) for the parser convention.

```text
rclone
aws
mutool
# soffice is installed by run_once_after_install-project-godocs.sh.tmpl
# (apt libreoffice on Linux, brew cask on macOS) — assert it on PATH too.
soffice
# go@1.25 is intentionally NOT asserted: it is a keg-only brew formula whose
# PATH wiring lives in ~/.zshrc.d/godocs-go125.zsh and only fires for
# interactive shells. The core profile already provides an unversioned `go`
# on PATH for non-interactive `command -v` checks.
```

The [`run_once_after_install-project-godocs.sh.tmpl`](../../run_once_after_install-project-godocs.sh.tmpl) script self-gates with `{{ if not (has "godocs" .projects) }}exit 0{{ end }}` and on activation:

- Installs LibreOffice per the platform branch above.
- Drops `~/.zshrc.d/godocs-go125.zsh`, which prepends Homebrew's keg-only `go@1.25` to `PATH` for any new shell. The shim is a safe no-op when `go@1.25` is not installed.
- If `doppler` and `rclone` are both on PATH **and** the configured Doppler scope holds `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ACCOUNT_ID`, writes a `[r2]` remote into `~/.config/rclone/rclone.conf` (mode `0600`). An existing `[r2]` block is left alone.
- Prints a manual-next-steps banner.

## What you must do manually

The script intentionally stops short of any step that needs credentials a fresh host does not yet have:

1. **Authenticate Doppler** so the R2 creds are available, then re-run the script (idempotent):
   ```bash
   doppler login
   doppler setup --project godocs --config dev
   chezmoi apply --include=scripts
   ```
2. **Clone the repo and verify the pinned Go toolchain**:
   ```bash
   git clone git@github.com:the-hole-foundation/hole-godocs.git ~/src/hole-godocs
   cd ~/src/hole-godocs
   go version           # should report go1.25.x via the PATH shim
   go build ./...
   ```
3. **Smoke-test the doc-extraction pipeline**:
   ```bash
   bash test-mupdf.sh
   soffice --headless --version
   ```
4. **(Optional) Verify R2 reachability** once Doppler creds are loaded:
   ```bash
   rclone lsd r2:
   ```

## Doppler scopes

| Scope | Used by | Required secrets |
|---|---|---|
| project `godocs`, config `dev` (override via `DOPPLER_GODOCS_PROJECT` / `DOPPLER_GODOCS_CONFIG` env vars) | Non-interactive `rclone` R2 configuration in the run_once script; runtime use by the godocs Go binaries. | `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ACCOUNT_ID` |

`doppler setup` writes the scope binding to `~/.doppler` so subsequent `doppler run --` invocations resolve automatically.

## Known limitations

- **LibreOffice on Linux is heavy.** `apt-get install libreoffice --no-install-recommends` still pulls ~400 MB. Acceptable for a self-sufficient godocs container per board Q2; not appropriate for the bare core image. Profile activation is opt-in.
- **`go@1.25` is keg-only.** The brew formula does not symlink into `/opt/homebrew/bin` (or `/home/linuxbrew/.linuxbrew/bin`). The run_once shim handles PATH for interactive shells, but cron jobs, launchd plists, and other non-shell consumers must call `$(brew --prefix go@1.25)/bin/go` directly or set PATH themselves.
- **R2 credential rotation is not automated.** When the Doppler `R2_*` secrets rotate, the existing `[r2]` block in `~/.config/rclone/rclone.conf` is **not** overwritten by re-running the script. Operators must delete the block (or remove the rclone.conf) before re-applying.
- **No interactive SSO logins are performed.** `aws sso login`, `gh auth login`, and `doppler login` are deliberately left for the operator — fresh containers have no browser and these would block cloud-init.
- **Git+SSH credentials required.** Cloning over SSH assumes a working `~/.ssh/id_*` and a key registered with GitHub. Fresh containers must run `ssh-keygen` and add the public key to GitHub before step 2 above.

## Related

- Parent task: [THE-66](/THE/issues/THE-66)
- Parent plan: [THE-51 plan document](/THE/issues/THE-51#document-plan)
- Profile system overview: [`docs/profiles/README.md`](README.md)
- Pilot profile: [`legal.md`](legal.md)
- Upstream repo: [hole-godocs](https://github.com/the-hole-foundation/hole-godocs)
