#!/bin/zsh
# bootstrap.sh — restore your Mac environment from mac-setup
# Usage: zsh bootstrap.sh

set -e

SETUP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
echo "Running from: $SETUP_DIR"

# ── 1. Homebrew ──────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "→ Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  echo "✓ Homebrew already installed"
fi

# ── 2. Packages ──────────────────────────────────────────────────────────────
echo "→ Installing packages from Brewfile..."
brew bundle --file="$SETUP_DIR/brewfile/Brewfile" --no-lock

# ── 3. Dotfiles ──────────────────────────────────────────────────────────────
echo "→ Restoring dotfiles..."
for f in "$SETUP_DIR"/dotfiles/.*; do
  name=$(basename "$f")
  [ "$name" = "." ] || [ "$name" = ".." ] || [ "$name" = ".ssh" ] || [ "$name" = ".config" ] && continue
  if [ -f "$f" ]; then
    cp "$f" "$HOME/$name" && echo "  restored $name"
  fi
done

# ── 4. SSH keys (manual step) ────────────────────────────────────────────────
echo ""
echo "⚠️  SSH keys: copy manually and set permissions:"
echo "    cp -r $SETUP_DIR/dotfiles/.ssh ~/.ssh"
echo "    chmod 700 ~/.ssh && chmod 600 ~/.ssh/*"

# ── 5. AWS credentials ───────────────────────────────────────────────────────
echo ""
echo "→ AWS: configure via Doppler after setup:"
echo "    doppler run --project master --config prd -- aws configure"

# ── 6. Done ──────────────────────────────────────────────────────────────────
echo ""
echo "✓ Done. Open a new terminal for changes to take effect."
