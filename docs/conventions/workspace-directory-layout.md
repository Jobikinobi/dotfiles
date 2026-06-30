# Workspace Directory Layout

Canonical home-directory tree for all machines in the fleet. Every new machine should have this structure before doing real work.

## Authoritative tree

```
~/
├── projects/
│   ├── gh/<org>/<repo>      # mirrors github.com URL (e.g. projects/gh/Jobikinobi/dotfiles)
│   └── local/               # non-GitHub / private experiments
├── docs/
│   ├── notes/               # freeform personal notes (not version-controlled)
│   └── references/          # reference materials (PDFs, specs, saved pages)
├── apps/                    # third-party binaries / app bundles not in PATH
├── bin/                     # personal scripts; already on PATH via $PATH in .zshrc
├── scratch/                 # throw-away area; globally gitignored — treat as /tmp
└── .config/                 # XDG config base (chezmoi-managed; do not edit directly)
```

## Rationale

| Dir | Why it exists |
|---|---|
| `projects/gh/<org>/<repo>` | Mirrors the GitHub URL so you can infer the remote from the path, and so the shell's `cd` autocomplete matches `github.com/…`. |
| `projects/local/` | Experiments that don't (yet) have a remote. Avoids polluting `projects/gh/` with non-GitHub paths. |
| `docs/notes/` | Freeform personal notes — not version-controlled by design. Keep transient; promote to a proper repo when the content grows scope. |
| `docs/references/` | Long-lived reference material: PDFs, saved specs, bookmarked pages. Not version-controlled but backed up. |
| `apps/` | Third-party bundles that don't belong in `/usr/local/` or `brew --prefix`. Keeps app binaries off `$PATH` unless you symlink from `bin/`. |
| `bin/` | Personal scripts that should be on `$PATH`. chezmoi manages `~/.zshrc` to include `~/bin` in `$PATH`. |
| `scratch/` | Throw-away area. Safe to nuke. Treat it like `/tmp` — do not store anything here that isn't recoverable. (The global gitignore ignores `scratch/` directories inside repos.) |
| `.config/` | XDG config base (`$XDG_CONFIG_HOME`). chezmoi-managed; do not edit source files directly. Use `chezmoi re-add` if you need to update from a live file. |

## Provisioning

The script `run_once_after_create-workspace-dirs.sh.tmpl` creates this structure on each new machine via `chezmoi apply`. It is idempotent — safe to re-run.

## What does NOT live here

- `/opt/` or `/usr/local/` — system or Homebrew-managed binaries
- `~/Library/` — macOS app data (managed by apps themselves)
- Source for deployed configs — that is the chezmoi source tree (this repo), not `~/.config/`

## See also

- [`docs/standards/branches-and-worktrees.md`](../standards/branches-and-worktrees.md) — branch and worktree policy
- [`CLAUDE.md`](../../CLAUDE.md) — critical chezmoi safety rules
