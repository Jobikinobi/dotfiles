# chezmoi workflows cheat sheet

Quick reference for everyday chezmoi operations in this repo.

## Mental model

- **Source** = files in `~/dotfiles` (this repo, symlinked to `~/.local/share/chezmoi`)
- **Live** = the actual files in your home directory (`~/.zshrc`, `~/.gitconfig`, etc.)
- chezmoi never auto-syncs in either direction. You explicitly run a command.

## Direction: source → live (deploy)

You edited a file in the repo and want it to take effect.

```zsh
chezmoi diff                  # preview every pending change
chezmoi apply                 # deploy all
chezmoi apply ~/.zshrc        # deploy one file
```

You don't need to do anything special after editing files in `~/dotfiles` — `chezmoi apply` reads whatever's there.

## Direction: live → source (capture)

You edited the live file directly (a new alias in `~/.zshrc`, say) and want it back in the repo.

| File type | Command | Notes |
|---|---|---|
| Plain (e.g., `dot_gitconfig`) | `chezmoi re-add ~/.gitconfig` | Verbatim copy live → source |
| **Template (`*.tmpl`)** | `chezmoi merge ~/.zshrc` **or** edit source directly | `re-add` will destroy template syntax |
| New file, not yet managed | `chezmoi add ~/.newfile` | Imports into source |
| New file, mark as encrypted | `chezmoi add --encrypt ~/.secret` | Stores as `encrypted_*.age` |

### Why `re-add` is dangerous for templates

`dot_zshrc.tmpl` contains `{{ if eq .chezmoi.os "darwin" }}` blocks. The live file has those resolved to literal text. `chezmoi re-add` blindly overwrites source with live — so template syntax becomes hardcoded values, breaking cross-platform support.

For a templated file, use one of:

**Option A — `chezmoi merge`** (3-way merge, you reconcile):
```zsh
chezmoi merge ~/.zshrc
```

**Option B — edit the source directly** (preferred when you know the change):
```zsh
chezmoi edit ~/.zshrc        # opens dot_zshrc.tmpl in $EDITOR
chezmoi apply ~/.zshrc       # deploy
```

## Safety net: undo a botched edit

`git checkout -- <file>` restores a file from your last local commit. **Local only — does not touch remote.**

| Goal | Command |
|---|---|
| Undo uncommitted changes to a file | `git checkout -- dot_zshrc.tmpl` (or `git restore dot_zshrc.tmpl`) |
| Get file from another local branch | `git checkout other-branch -- dot_zshrc.tmpl` |
| Get file from remote main (after `git fetch`) | `git checkout origin/main -- dot_zshrc.tmpl` |
| Get file from a specific commit | `git checkout abc123 -- dot_zshrc.tmpl` |

If a bad change is already committed and pushed: `git revert <commit-sha>` creates a new commit that undoes it. Never `git push --force` to `main`.

## Inspection commands

```zsh
chezmoi status                # what's out of sync, in which direction?
chezmoi managed | grep zshrc  # is this file managed?
chezmoi cat ~/.zshrc          # show what chezmoi WOULD write (decrypts + renders templates)
chezmoi data                  # all template variables available
chezmoi cat-config            # resolved chezmoi.toml
chezmoi source-path           # where chezmoi looks for source (should be ~/.local/share/chezmoi)
chezmoi source-path ~/.zshrc  # where the source for one file lives
```

## Secrets (age encryption)

See [README.md](../README.md#secrets-age-encryption) for full setup. Quick reference:

```zsh
chezmoi add --encrypt ~/.config/some/secret    # add new secret
chezmoi edit ~/.config/some/secret             # edit (auto decrypt/re-encrypt)
chezmoi cat ~/.config/some/secret              # view decrypted
```

The private key lives at `~/.config/chezmoi/key.txt`. Backup is in Gmail (search "chezmoi age key backup"). **If lost, encrypted files are unrecoverable.**

## Common gotchas

- **Doppler keychain locked → template render fails.** Doppler lookups in this repo run at shell-startup, not template-render, to avoid this. Don't add `{{ output "doppler" ... }}` calls to templates.
- **Symlinked source.** chezmoi expects `~/.local/share/chezmoi`. On this machine it's symlinked to `~/dotfiles`. If `chezmoi source-path` returns the wrong path, recreate: `ln -sfn ~/dotfiles ~/.local/share/chezmoi`.
- **Forgot to `chezmoi apply` after editing source.** `chezmoi diff` will show you everything that's out of sync.
- **Live file modified by an installer (OrbStack, gh, etc.).** chezmoi will detect drift on next `apply`. Decide: keep the installer's change (`chezmoi re-add` for plain files) or overwrite (`chezmoi apply --force`).
