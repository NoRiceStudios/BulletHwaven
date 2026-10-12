#!/usr/bin/env bash
# Renders a scenario under Xvfb and saves a screenshot.
#   scripts/shot.sh <scenario> <seed> <ticks> <out.png>
# Writes <out.png> (native 640x360) and <out>_1080p.png (3x nearest). Exits non-zero on failure.
set -uo pipefail
if [ $# -ne 4 ]; then
  echo "usage: $0 <scenario> <seed> <ticks> <out.png>" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="$HOME/.local/bin/godot"
if [ ! -x "$GODOT" ]; then
  "$ROOT/scripts/setup-godot.sh" || exit 1
fi
mkdir -p "$(dirname "$4")"
OUT="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
rm -f "$OUT"
# (Re)import assets and refresh the global class cache.
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$ROOT/game" --rendering-driver opengl3 --audio-driver Dummy \
  -- --shot="$OUT" --scenario="$1" --seed="$2" --ticks="$3" >"$log" 2>&1
code=$?
grep -E "SHOT_OK|SCRIPT ERROR|Parse Error|^ERROR:|^USER ERROR" "$log" | grep -v "ALSA" >&2
if [ "$code" -ne 0 ] || ! grep -q "SHOT_OK" "$log" || [ ! -s "$OUT" ]; then
  echo "shot.sh: failed (exit $code)" >&2
  exit 1
fi
if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
  echo "shot.sh: script errors detected" >&2
  exit 1
fi
echo "$OUT"
