#!/usr/bin/env bash
# Exports release builds: scripts/export.sh [linux|windows|all]   (default: all)
# Ensures Godot and the matching export templates, runs an import pass, exports headless
# and zips the results into build/. Idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_VERSION="4.7.2"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
GODOT="$HOME/.local/bin/godot"
target="${1:-all}"
case "$target" in linux|windows|all) ;; *) echo "usage: $0 [linux|windows|all]" >&2; exit 2 ;; esac

if [ ! -x "$GODOT" ]; then "$ROOT/scripts/setup-godot.sh"; fi

# Export templates (~1 GB download). Only the x86_64 release templates for Linux and Windows
# are installed (~0.4 GB instead of 2 GB). Skipped when already installed.
if [ ! -f "$TEMPLATE_DIR/version.txt" ] || [ ! -f "$TEMPLATE_DIR/linux_release.x86_64" ] \
   || [ ! -f "$TEMPLATE_DIR/windows_release_x86_64.exe" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  echo "export.sh: downloading export templates"
  curl -sSfL --retry 3 -o "$tmp/templates.tpz" "$url"
  unzip -q "$tmp/templates.tpz" -d "$tmp/x"
  mkdir -p "$TEMPLATE_DIR"
  for f in version.txt icudt_godot.dat linux_release.x86_64 windows_release_x86_64.exe windows_release_x86_64_console.exe; do
    cp -a "$tmp/x/templates/$f" "$TEMPLATE_DIR/"
  done
  rm -rf "$tmp"
fi

# Import pass (builds .godot/ with imported assets and the class cache).
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true

export_one() { # <preset> <out dir> <binary name> <zip name>
  local preset="$1" dir="$2" bin="$3" zip="$4"
  rm -rf "$ROOT/build/$dir"
  mkdir -p "$ROOT/build/$dir"
  "$GODOT" --headless --path "$ROOT/game" --export-release "$preset" "../build/$dir/$bin"
  [ -s "$ROOT/build/$dir/$bin" ] || { echo "export.sh: $preset export produced no $bin" >&2; exit 1; }
  rm -f "$ROOT/build/$zip"
  (cd "$ROOT/build/$dir" && zip -qr "../$zip" .)
  echo "export.sh: build/$zip ready"
}

if [ "$target" = linux ] || [ "$target" = all ]; then
  export_one "Linux" linux BulletHwaven.x86_64 BulletHwaven-linux-x86_64.zip
fi
if [ "$target" = windows ] || [ "$target" = all ]; then
  export_one "Windows Desktop" windows BulletHwaven.exe BulletHwaven-windows-x86_64.zip
fi
