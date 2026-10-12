#!/usr/bin/env bash
# Runs the headless test suite. Exits non-zero on any failure (or script error).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="$HOME/.local/bin/godot"
if [ ! -x "$GODOT" ]; then
  "$ROOT/scripts/setup-godot.sh" || exit 1
fi
# First run (or after adding class_name scripts) the global class cache must be built.
if [ ! -f "$ROOT/game/.godot/global_script_class_cache.cfg" ]; then
  "$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
fi
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
"$GODOT" --headless --path "$ROOT/game" -s res://tests/run_tests.gd 2>&1 | tee "$out"
code=${PIPESTATUS[0]}
if [ "$code" -eq 0 ] && grep -qE "SCRIPT ERROR|Parse Error|^ERROR:" "$out"; then
  echo "test.sh: script errors detected in output" >&2
  code=1
fi
exit "$code"
