# nnn: Terminal File Manager (Finder Replacement)

nnn is configured as a fast, keyboard-driven Finder replacement. This doc is the complete reference for the keybindings, plugins, and workflow.

> **TL;DR:** Type `n` in your shell to launch. Press `?` inside nnn for built-in help. Press `q` to quit (shell auto-cd's to the last folder you navigated to).

---

## Launching

| Command | What it does |
|---------|--------------|
| `n` | Open nnn in the current directory |
| `n ~/Downloads` | Open nnn at a specific path |
| `n path/that/does/not/exist/` | Creates the directory tree and opens it |

The `n` function is defined in `~/.zshrc` section 16 (chezmoi source: `~/dotfiles/dot_zshrc.tmpl`). It runs `nnn` directly and sources the cd-on-quit marker file on exit.

---

## Navigation

| Key | Action |
|-----|--------|
| `h` / `←` | Go to parent directory |
| `l` / `→` / `Enter` | Enter directory / open file |
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `b` | Bookmarks menu |
| `/` | Live filter (narrows current dir) |
| `Tab` / `` ` `` / `~` | Switch between 4 contexts (tabs) |
| `G` | Jump to last entry |
| `'` | Jump to first entry |
| `-` | Jump to last visited directory |
| `.` | Toggle hidden files |
| `t` | Open sort menu (see Sorting below) |
| `?` | Built-in help |
| `q` | Quit (shell cd's to last dir) |
| `Ctrl+G` | Quit immediately + cd to current dir |

---

## File & Folder Operations

| Key | Action |
|-----|--------|
| `Space` | Toggle select (file or folder) |
| `a` | Select all in current directory |
| `A` | Invert selection |
| `p` / `Ctrl+P` | **COPY** selected items to current dir |
| `v` / `Ctrl+V` | **MOVE** selected items to current dir |
| `x` | **DELETE** selected/hovered (sends to Trash) |
| `Ctrl+R` | Rename hovered item |
| `r` | Batch rename selection in `$EDITOR` (Helix) |
| `n` | Create new file or folder |
| `o` | Open with system default app |
| `e` | Edit in `$EDITOR` (Helix) |
| `Ctrl+X` | Toggle executable permission |
| `y` | Copy hovered path to clipboard |
| `Y` | Copy all selected paths to clipboard |

### Creating files and folders

When you press `n`, you get a prompt. The trailing slash determines the type:

| Input | Result |
|-------|--------|
| `notes.md` | Creates a file called `notes.md` |
| `new-folder/` | Creates a folder called `new-folder` |
| `2026/q2/reports/` | Creates the nested tree `2026/q2/reports` |
| `docs/readme.md` | Creates `docs/` folder + `readme.md` inside it |

### Cross-directory copy/move workflow

This is the killer feature — **select files across multiple directories**, then paste them all at once:

1. Navigate to source folder A
2. Press `Space` on files you want
3. Navigate to source folder B
4. Press `Space` on more files
5. Navigate to destination folder
6. Press `p` to copy all selected, or `v` to move them

---

## Sorting

Press `t` to open the sort menu, then one of:

| Key | Sort by |
|-----|---------|
| `n` | Name |
| `t` | Time modified |
| `s` | Size |
| `e` | Extension |
| `r` | Reverse current sort |
| `c` | Clear (default) |

**Example:** Press `t` then `t` to sort by date modified (newest first). Press `t` then `r` to flip to oldest first.

---

## Bookmarks

Press `b` to open the bookmarks menu, then one of these keys:

### macOS (HOLE Foundation RAID drive)

| Key | Path |
|-----|------|
| `p` | `/Volumes/HOLE-RAID-DRIVE/Projects` |
| `t` | `…/Projects/transparency-engine` |
| `f` | `…/Projects/HOLE-FUSE` |
| `a` | `…/Projects/AstroTruthProject/HOLE-Astro-Dev-Container` |
| `h` | `$HOME` |
| `d` | `~/Downloads` |
| `D` | `~/Documents` |

### Linux

| Key | Path |
|-----|------|
| `p` | `~/Projects` |
| `h` | `$HOME` |
| `d` | `~/Downloads` |
| `D` | `~/Documents` |

> Bookmarks are defined in `NNN_BMS` in `~/.zshrc`. Edit `~/dotfiles/dot_zshrc.tmpl` to change them.

---

## Plugin Shortcuts

Press `;` (semicolon) then the plugin key. Press `;` then `Enter` to browse all plugins.

### Search
| Key | Plugin | Purpose |
|-----|--------|---------|
| `;f` | fzcd | Fuzzy find directories |
| `;o` | fzopen | Fuzzy find and open files |
| `;z` | fzz | Fuzzy navigate everything |
| `;S` | spotlight | **Spotlight-like search with type specifiers** |
| `;m` | mdfind | Quick filename search (macOS only) |

### Git
| Key | Plugin | Purpose |
|-----|--------|---------|
| `;d` | diffs | Show git diffs |
| `;g` | !git log | Show git log |
| `;s` | !git status | Show git status |

### File operations
| Key | Plugin | Purpose |
|-----|--------|---------|
| `;r` | renamer | Batch rename (vidir/qmv) |
| `;x` | togglex | Toggle executable bit |
| `;c` | cbcopy-mac / x2sel | Copy to system clipboard |
| `;V` | cbpaste-mac | Paste from clipboard (macOS) |

### OS integration
| Key | Plugin | Purpose |
|-----|--------|---------|
| `;F` | (inline) | **Open current folder in Finder / file manager** |

---

## Spotlight Search (`;S`)

The custom spotlight plugin supports **type specifiers**. Prefix your query with a type to filter results:

| Prefix | Finds |
|--------|-------|
| `app:slack` | Applications (macOS) |
| `folder:proj` | Folders only |
| `file:budget` | Files only (not folders) |
| `img:vacation` | Images (jpg, png, gif, svg, etc.) |
| `pdf:report` | PDF files |
| `txt:notes` | Plain text files |
| `md:readme` | Markdown files |
| `code:main` | Source code files (py, js, ts, go, rs, etc.) |
| *(no prefix)* | Everything, by name |

**Behavior by OS:**
- **macOS:** Uses Spotlight (`mdfind`) with content-type metadata queries
- **Linux:** Uses `locate` (or `find` as fallback) with extension filtering

Results are piped through `fzf` with a live preview pane. Select with Enter.

Plugin source: `~/.config/nnn/plugins/spotlight` (chezmoi-managed at `~/dotfiles/dot_config/nnn/plugins/executable_spotlight`)

---

## Text Editor Integration

`EDITOR` and `VISUAL` are set to `hx` (Helix) in `~/.zshrc`. Combined with the `E` flag in `NNN_OPTS`, this means:

- Press `e` on any file → opens in Helix
- Press `o` on a text file (`.txt`, `.md`, `.py`, `.json`, etc.) → opens in Helix
- Press `r` for batch rename → uses Helix as the editor
- Press `o` on a non-text file (image, PDF, video) → uses macOS `open` / Linux `xdg-open`

The routing is handled by the `nuke` plugin (set as `NNN_OPENER`), which detects file types and dispatches accordingly.

---

## Quick Workflows

### "Move files from Downloads to a project"
```
n ~/Downloads
Space Space Space    (select files)
b p                  (bookmark to Projects)
l                    (enter project subfolder)
p                    (paste)
```

### "Find a PDF by content type"
```
n
;S
pdf:tax         (enter at prompt)
                (fzf picker appears with preview)
Enter           (opens folder containing the file)
```

### "Rename a bunch of files at once"
```
n ~/Downloads
a               (select all)
r               (batch rename — opens in Helix)
                (edit filenames, save, :q)
```

### "Quick escape to Finder"
```
n
b p             (jump to Projects)
l               (drill into a project)
;F              (open in Finder)
```

### "Sort by newest first"
```
n ~/Downloads
t t             (sort by time)
t r             (reverse — newest at top)
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `~/dotfiles/dot_zshrc.tmpl` | nnn env vars, `n()` wrapper, all shortcuts (chezmoi source) |
| `~/dotfiles/dot_config/nnn/plugins/executable_spotlight` | Custom Spotlight plugin |
| `~/.config/nnn/plugins/` | Installed plugin library (downloaded via `getplugs`) |
| `~/.config/nnn/.lastd` | Temporary cd-on-quit marker (auto-managed) |
| `~/.config/nnn/sessions/` | Saved session snapshots |

### Environment Variables (set in `~/.zshrc`)

| Variable | Value | Purpose |
|----------|-------|---------|
| `NNN_OPTS` | `cEdrux` | c=context colors, E=use `$EDITOR`, d=detail mode, r=cp/mv progress, u=use selection, x=clipboard |
| `NNN_TRASH` | `1` | Delete sends to Trash (not `rm`) |
| `NNN_OPENER` | `…/plugins/nuke` | Smart file opener by type |
| `NNN_BMS` | *(bookmarks)* | Key→path shortcuts |
| `NNN_PLUG` | *(plugins)* | Key→plugin bindings |
| `NNN_FCOLORS` | `c1e2272e006033f7c6d6abc4` | File type colors |
| `NNN_ARCHIVE` | `\.(7z|bz2|gz|tar|tgz|zip|rar|xz|zst)$` | Archive extensions |
| `NNN_TMPFILE` | `~/.config/nnn/.lastd` | cd-on-quit marker path |

---

## Troubleshooting

### "Text files open in vi, not Helix"
Check that `EDITOR` is set: `echo $EDITOR` should return `hx`. If not, open a new terminal (env vars don't update in existing shells).

### "The bookmarks menu shows wrong paths"
On macOS, bookmarks point to `/Volumes/HOLE-RAID-DRIVE/Projects`. If the RAID drive isn't mounted, the bookmarks still exist but navigation will fail. Mount the drive or edit `NNN_BMS` in the zshrc template.

### "`;F` doesn't open Finder"
Verify `open` (macOS) or `xdg-open` (Linux) is on your PATH. On Linux, install `xdg-utils`.

### "Spotlight search returns nothing"
- **macOS:** Spotlight indexing may be paused. Check `mdutil -s /`.
- **Linux:** `locate` database may be stale. Run `sudo updatedb`.

### "Deleted files aren't in Trash"
On macOS, `NNN_TRASH=1` requires the built-in `trash` command (`/usr/bin/trash`). On Linux, install `trash-cli` (`sudo apt install trash-cli` or equivalent).

---

## See Also

- **Inline quick reference:** `~/.zshrc` section 16 (shorter, same info)
- **Upstream wiki:** https://github.com/jarun/nnn/wiki
- **Plugin library:** https://github.com/jarun/nnn/tree/master/plugins
- **Memory (AI searchable):** `mem0 search "nnn shortcuts"` or `mem0 search "nnn bookmarks"`
