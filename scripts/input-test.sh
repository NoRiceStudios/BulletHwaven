#!/usr/bin/env bash
# Real-input end-to-end test: drives the actual game window under Xvfb with REAL X11 mouse and
# keyboard events (XTEST), so clicks must hit real UI Controls (see tools/input_test/).
#   scripts/input-test.sh [out_dir]
# Needs: Xvfb, python3 with python-xlib (apt install xvfb python3-xlib). Screenshots go to
# <out_dir> (default: a fresh temp dir, printed at the end). Prints PASS/FAIL per step and
# exits non-zero on any failure.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
if [ ! -x "$GODOT" ]; then
  "$ROOT/scripts/setup-godot.sh" || exit 1
fi
if ! python3 -c "import Xlib" 2>/dev/null; then
  echo "input-test.sh: python-xlib missing (apt install python3-xlib or pip install python-xlib)" >&2
  exit 1
fi
command -v Xvfb >/dev/null || { echo "input-test.sh: Xvfb missing (apt install xvfb)" >&2; exit 1; }

WORK="$(mktemp -d)"
OUT="${1:-$WORK/shots}"
mkdir -p "$OUT"
LOG="$WORK/game.log"
XPID=""
GPID=""
cleanup() {
  [ -n "$GPID" ] && kill "$GPID" 2>/dev/null
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null
  [ -n "$GPID" ] && wait "$GPID" 2>/dev/null
  [ -n "$XPID" ] && wait "$XPID" 2>/dev/null
  rm -rf "$WORK/disp"
}
trap cleanup EXIT

# Make sure the project is imported (fresh CI checkouts have no .godot cache).
"$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true

# Xvfb picks a free display number itself and reports it through -displayfd.
Xvfb -displayfd 3 -screen 0 1920x1080x24 -nolisten tcp 3>"$WORK/disp" >"$WORK/xvfb.log" 2>&1 &
XPID=$!
for _ in $(seq 1 50); do
  [ -s "$WORK/disp" ] && break
  sleep 0.1
done
if [ ! -s "$WORK/disp" ]; then
  echo "input-test.sh: Xvfb did not start" >&2
  cat "$WORK/xvfb.log" >&2
  exit 1
fi
export DISPLAY=":$(tr -d '[:space:]' <"$WORK/disp")"

"$GODOT" --path "$ROOT/game" --rendering-driver opengl3 --audio-driver Dummy -- --fast >"$LOG" 2>&1 &
GPID=$!

python3 "$ROOT/tools/input_test/run.py" --display "$DISPLAY" --log "$LOG" --out "$OUT" --godot-pid "$GPID"
code=$?
if [ "$code" -ne 0 ]; then
  echo "---- game log (tail) ----" >&2
  grep -v ALSA "$LOG" | tail -30 >&2
fi
echo "screenshots: $OUT"
exit "$code"
