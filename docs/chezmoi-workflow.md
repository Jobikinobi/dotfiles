# chezmoi Workflow Guide

## The Mental Model

chezmoi maintains a **source** (this repo) and a **target** (your live files). The source is the truth. `chezmoi apply` writes source → target.

```
~/dotfiles/dot_zshrc.tmpl   ←── source (what git tracks)
        │
        │  chezmoi apply
        ▼
~/.zshrc                     ←── target (what your shell reads)
```

## Common Operations

### See what's different
```bash
chezmoi diff                    # full diff (source vs target)
chezmoi diff ~/.zshrc           # single file
```

### Capture a local change
If you edited a live file (e.g., `~/.gitconfig`) and want chezmoi to track it:
```bash
chezmoi re-add ~/.gitconfig     # updates source from target
```

### Apply source to target
```bash
chezmoi diff                    # ALWAYS check first
chezmoi apply                   # writes source → target
chezmoi apply ~/.gitconfig      # single file only
```

### Add a new file to chezmoi
```bash
chezmoi add ~/.some-config      # copies into source with correct naming
```

### The mac-save shortcut
```bash
mac-save    # = chezmoi re-add + brew bundle dump + git commit + push
```

## Template Files (.tmpl)

Files ending in `.tmpl` are Go templates that get rendered before deployment.

**Important**: You cannot `chezmoi re-add` a template file. If you run `chezmoi re-add ~/.zshrc` and the source is `dot_zshrc.tmpl`, it will overwrite the template with the rendered output — destroying all template logic (`{{ if }}`, `{{ output }}`, etc.).

### To edit a template:
```bash
# Option 1: Edit the source directly
$EDITOR ~/dotfiles/dot_zshrc.tmpl

# Option 2: Use chezmoi edit (opens the source file)
chezmoi edit ~/.zshrc
```

### To test a template renders correctly:
```bash
chezmoi execute-template < ~/dotfiles/dot_zshrc.tmpl | tail -20
```

## OS-Conditional Blocks

Templates use `.chezmoi.os` to include/exclude sections:

```
{{ if eq .chezmoi.os "darwin" }}
  # macOS-only content (1Password agent, Colima, OrbStack)
{{ else }}
  # Linux-only content (Linuxbrew paths)
{{ end }}
```

The SSH config (`private_dot_ssh/config.tmpl`) wraps macOS-specific includes (OrbStack, Colima, 1Password) in these guards.

## Secrets in Templates

Secrets are injected via Doppler at `chezmoi apply` time:

```
{{ if lookPath "doppler" -}}
export KEY='{{ output "doppler" "secrets" "get" "KEY" "--plain" "-p" "backend" "-c" "prd" | trim }}'
{{- end }}
```

- `lookPath` checks if `doppler` binary exists (skips on machines without it)
- The actual secret value is baked into `~/.zshrc` — never visible in git
- You must have Doppler authenticated (`doppler login`) for this to work
- **Known issue**: Fails over SSH due to keychain access — see issue #5

## Troubleshooting

### "chezmoi wants to overwrite my changes"
Run `chezmoi re-add <file>` to make your local version the new baseline. For `.tmpl` files, edit the template directly instead.

### "Tools are missing after opening a new terminal"
Check if `.zshrc` loaded fully: `which fnm && which bat`. If not, a zinit plugin download may have failed. Open a new terminal tab — it usually resolves on retry.

### "Git asks for password on every push"
Run `gh auth setup-git` to configure the credential helper. This is now baked into `dot_gitconfig` but may need a one-time setup on existing machines.
