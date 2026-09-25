#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[ERROR] switch-acc is designed specifically for macOS (Apple Keychain)."
  exit 1
fi

INSTALL_DIR="$HOME/.local/bin"
PROFILES_DIR="$HOME/.gemini/antigravity/profiles"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/switch-acc.zsh"

echo "==> Installing switch-acc for Google Antigravity..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$PROFILES_DIR"
chmod 700 "$PROFILES_DIR"

chmod +x "$SOURCE_FILE"
ln -sf "$SOURCE_FILE" "$INSTALL_DIR/switch-acc"

echo "[OK] Installed to $INSTALL_DIR/switch-acc"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo ""
  echo "Notice: $INSTALL_DIR is not in your PATH."
  echo "Add the following line to your ~/.zshrc or ~/.bash_profile:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "==> Optional: For Zsh tab-completion (switch-acc switch <TAB>), add this to ~/.zshrc:"
echo "  source \"$SOURCE_FILE\""
echo ""
echo "[SUCCESS] Installation complete! Run 'switch-acc help' to get started."
