#!/usr/bin/env bash
# Installs the pinned Godot version to ~/.local/bin/godot (idempotent; used by the SessionStart hook).
set -euo pipefail
GODOT_VERSION="4.7.2"
DEST="$HOME/.local/share/godot/$GODOT_VERSION"
BIN="$DEST/Godot_v${GODOT_VERSION}-stable_linux.x86_64"
if [ ! -x "$BIN" ]; then
  mkdir -p "$DEST"
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  curl -sSfL --retry 3 -o "$DEST/godot.zip" "$url"
  unzip -qo "$DEST/godot.zip" -d "$DEST" && rm "$DEST/godot.zip"
  chmod +x "$BIN"
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$BIN" "$HOME/.local/bin/godot"
echo "godot $GODOT_VERSION ready at $HOME/.local/bin/godot"
