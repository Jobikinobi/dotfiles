# `webdev` profile

Generic chezmoi profile for **web and frontend development projects**. Adds alternative JS runtimes, an efficient package manager, and deployment tooling on top of the core stack (`fnm` + Node LTS, `git`, `gh`, `jq`, `doppler`).

Activate by adding `"webdev"` to the `projects` list in `~/.config/chezmoi/chezmoi.toml`, then re-run `chezmoi apply`. With `projects = []` the profile is a no-op.

## What this profile installs

Brews from [`dot_Brewfile.webdev`](../../dot_Brewfile.webdev):

| Package | Binary | Purpose |
|---|---|---|
| `bun` | `bun` | Fast all-in-one JS runtime, bundler, and package manager. Drop-in for node/npm/npx in most contexts; especially fast for scripts and test runners. |
| `pnpm` | `pnpm` | Efficient npm alternative — links packages from a global content-addressed store so monorepos share deps without duplicate downloads. |
| `vercel-cli` | `vercel` | Deploy to Vercel, pull env vars (`vercel env pull`), run the local edge-config dev server (`vercel dev`). |

Already provided by [`dot_Brewfile.core`](../../dot_Brewfile.core) and therefore not duplicated here: `fnm` (Node version manager), `git`, `gh`, `jq`, `fd`, `ripgrep`, `helix`, `direnv`, `doppler`.

Node LTS is installed by [`run_once_after_install-brewfile.sh.tmpl`](../../run_once_after_install-brewfile.sh.tmpl) via `fnm install --lts` as part of the core setup; this profile's run-once script verifies it and emits the activation banner.

## Installed binaries

[`scripts/test-profile.sh`](../../scripts/test-profile.sh) asserts each entry below is on `PATH` inside an applied container. Binary names, not formula names. Comment lines and blank lines are ignored.

```text
bun
pnpm
vercel
```

## Quick start

```bash
# Start a new Next.js project with pnpm
pnpm create next-app my-app && cd my-app
pnpm dev

# Or with Bun
bun create next my-app && cd my-app
bun dev

# Link to a Vercel project and pull env vars
vercel link
vercel env pull .env.local

# Deploy
vercel deploy          # preview deployment
vercel deploy --prod   # production
```

## What you must do manually

1. **Authenticate with Vercel** the first time:
   ```bash
   vercel login
   ```

2. **Link your project** to a Vercel team/org:
   ```bash
   vercel link    # inside the project directory
   ```

3. **Pull environment variables** from Vercel:
   ```bash
   vercel env pull .env.local
   ```

4. **Set a Node version** if the project requires a specific release:
   ```bash
   fnm install 20.19.0
   fnm use 20.19.0
   echo "20.19.0" > .node-version    # persisted per repo via fnm
   ```

## Notes

- **`bun` vs `node`:** Bun is a full runtime — you can run `bun <file>.ts` directly without a build step. For packages that require native Node.js bindings, fall back to `node`.
- **`pnpm` workspaces:** add a `pnpm-workspace.yaml` to the repo root to declare a monorepo. All sub-packages share the global store.
- **`vercel-cli` is team-aware:** `vercel link` persists team context in `.vercel/project.json`. Commit that file (it contains no secrets) for teammates.
- **macOS vs Linux:** all three tools install identically on both platforms via Homebrew/Linuxbrew.
