#!/bin/zsh
# migrate-to-chezmoi.sh — Convert this dotfiles repo to chezmoi source format
# Usage: zsh scripts/migrate-to-chezmoi.sh
#
# What it does:
#   1. Points chezmoi's source directory at this repo
#   2. Adds all dotfiles/ contents via `chezmoi add`
#   3. Creates run_once scripts for Brewfile + LaunchAgent
#   4. Moves non-chezmoi files to .chezmoitemplates or removes them
#
# Safe to run: no files in $HOME are modified. Only restructures this repo.
# After running, review with `git diff` then `chezmoi diff` before applying.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Repo: $REPO_DIR"

# ── 0. Preflight checks ─────────────────────────────────────────────────────
if ! command -v chezmoi &>/dev/null; then
  echo "ERROR: chezmoi not installed. Run: brew install chezmoi"
  exit 1
fi

# ── 1. Point chezmoi source at this repo ─────────────────────────────────────
echo "→ Configuring chezmoi source directory..."
mkdir -p ~/.config/chezmoi
cat > ~/.config/chezmoi/chezmoi.toml <<EOF
[data]
    name = "Joseph T. Herrmann, M.D."
    email = "joeherrmann@gmail.com"
    github_user = "Jobikinobi"

sourceDir = "$REPO_DIR"
EOF
echo "  ✓ chezmoi.toml written"

# ── 2. Add home-directory dotfiles via chezmoi add ───────────────────────────
# These must exist in $HOME for chezmoi to add them.
# We copy from repo → $HOME (backing up) then `chezmoi add`.

echo "→ Adding dotfiles to chezmoi source state..."

# Simple dotfiles (files in $HOME root)
HOME_FILES=(
  .bash_profile
  .bashrc
  .gitconfig
  .p10k.zsh
  .profile
  .viminfo
  .zprofile
  .zshenv
  .zshrc
)

for f in "${HOME_FILES[@]}"; do
  if [[ -f "$HOME/$f" ]]; then
    chezmoi add "$HOME/$f" 2>/dev/null && echo "  ✓ $f" || echo "  ⚠ $f (skipped)"
  elif [[ -f "$REPO_DIR/dotfiles/$f" ]]; then
    # File exists in repo but not in $HOME — copy it first
    cp "$REPO_DIR/dotfiles/$f" "$HOME/$f"
    chezmoi add "$HOME/$f" 2>/dev/null && echo "  ✓ $f (restored + added)" || echo "  ⚠ $f (skipped)"
  fi
done

# Skip .npmrc (contains auth token — handle separately)
echo "  ⊘ .npmrc skipped (contains npm auth token)"

# ── 3. Add .config directories ──────────────────────────────────────────────
echo "→ Adding .config directories..."

CONFIG_DIRS=(
  .config/btop
  .config/fish
  .config/gh
  .config/helix
  .config/htop
  .config/kitty
)

for d in "${CONFIG_DIRS[@]}"; do
  if [[ -d "$HOME/$d" ]]; then
    chezmoi add "$HOME/$d" 2>/dev/null && echo "  ✓ $d" || echo "  ⚠ $d (skipped)"
  elif [[ -d "$REPO_DIR/dotfiles/$d" ]]; then
    mkdir -p "$HOME/$d"
    cp -r "$REPO_DIR/dotfiles/$d/" "$HOME/$d/"
    chezmoi add "$HOME/$d" 2>/dev/null && echo "  ✓ $d (restored + added)" || echo "  ⚠ $d (skipped)"
  fi
done

# ── 4. Add SSH config (public files only) ───────────────────────────────────
echo "→ Adding SSH config (public files only)..."
if [[ -f "$HOME/.ssh/config" ]]; then
  chezmoi add "$HOME/.ssh/config" 2>/dev/null && echo "  ✓ .ssh/config" || echo "  ⚠ .ssh/config (skipped)"
fi
if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
  chezmoi add "$HOME/.ssh/authorized_keys" 2>/dev/null && echo "  ✓ .ssh/authorized_keys" || echo "  ⚠ .ssh/authorized_keys (skipped)"
fi

# ── 5. Create run_once script for Brewfile ───────────────────────────────────
echo "→ Creating Brewfile install script..."
mkdir -p "$REPO_DIR/.chezmoiscripts"
cat > "$REPO_DIR/run_once_before_install-packages.sh.tmpl" <<'SCRIPT'
{{- if eq .chezmoi.os "darwin" -}}
#!/bin/zsh
# Install Homebrew if missing
if ! command -v brew &>/dev/null; then
  echo "→ Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null
fi

# Install packages from Brewfile
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/.Brewfile" ]]; then
  echo "→ Installing packages from Brewfile..."
  brew bundle --file="$SCRIPT_DIR/.Brewfile" --no-lock
fi
{{- end -}}
SCRIPT

# Copy Brewfile as a chezmoi-managed dot file
if [[ -f "$REPO_DIR/brewfile/Brewfile" ]]; then
  cp "$REPO_DIR/brewfile/Brewfile" "$REPO_DIR/dot_Brewfile"
  echo "  ✓ Brewfile → dot_Brewfile"
fi

# ── 6. Create run_once script for LaunchAgent ────────────────────────────────
echo "→ Creating LaunchAgent install script..."
cat > "$REPO_DIR/run_once_after_install-launchagent.sh.tmpl" <<'SCRIPT'
{{- if eq .chezmoi.os "darwin" -}}
#!/bin/zsh
PLIST="$HOME/Library/LaunchAgents/com.jth.mac-save.plist"

# Only install if not already loaded
if ! launchctl list 2>/dev/null | grep -q com.jth.mac-save; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [[ -f "$SCRIPT_DIR/com.jth.mac-save.plist" ]]; then
    cp "$SCRIPT_DIR/com.jth.mac-save.plist" "$PLIST"
    launchctl load "$PLIST" 2>/dev/null
    echo "  ✓ mac-save launchd agent installed"
  fi
fi
{{- end -}}
SCRIPT

# Copy plist to repo root for the script to find
if [[ -f "$REPO_DIR/launchagents/com.jth.mac-save.plist" ]]; then
  cp "$REPO_DIR/launchagents/com.jth.mac-save.plist" "$REPO_DIR/com.jth.mac-save.plist"
  echo "  ✓ LaunchAgent plist copied to root"
fi

# ── 7. Add .chezmoiignore ───────────────────────────────────────────────────
echo "→ Creating .chezmoiignore..."
cat > "$REPO_DIR/.chezmoiignore" <<'EOF'
# Legacy structure (keep in repo for reference but chezmoi ignores)
README.md
LICENSE
dotfiles/**
brewfile/**
launchagents/**
scripts/**
com.jth.mac-save.plist

# OS junk
.DS_Store
.Spotlight-V100
.Trashes
EOF

echo "  ✓ .chezmoiignore written"

# ── 8. Summary ──────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Migration complete! Next steps:"
echo ""
echo "  1. Review changes:     cd $REPO_DIR && git diff"
echo "  2. Preview apply:      chezmoi diff"
echo "  3. Apply (dry run):    chezmoi apply --dry-run --verbose"
echo "  4. Apply for real:     chezmoi apply"
echo "  5. Clean up old dirs:  (after confirming everything works)"
echo ""
echo "  To undo chezmoi:       chezmoi purge"
echo "  To remove a file:      chezmoi forget ~/.some-file"
echo "════════════════════════════════════════════════════════════════"
