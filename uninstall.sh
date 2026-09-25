#!/usr/bin/env bash
set -euo pipefail

TARGET="$HOME/.local/bin/switch-acc"

if [[ -L "$TARGET" || -f "$TARGET" ]]; then
  rm -f "$TARGET"
  echo "[OK] Removed $TARGET"
else
  echo "[INFO] $TARGET not found."
fi

echo ""
echo "Note: Your saved profiles in ~/.gemini/antigravity/profiles/ were kept intact."
echo "If you wish to delete stored profile tokens, run:"
echo "  rm -rf ~/.gemini/antigravity/profiles/"
