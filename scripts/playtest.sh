#!/usr/bin/env bash
# Playtest harness: lets an agent (or a person) play BulletHwaven turn by turn and see what a player sees.
# A session is a seed + config + the log of the human's commands per decision point (workshop); every call
# replays the deterministic sim from tick 0, so no live process is needed.
#
#   scripts/playtest.sh new <dir> --seed N --mode solo|ffa [--opponents balanced,pvp_hunter,random]
#                       [--name NAME] [--color 0..7] [--doctrine-drive circle|kite|charge]
#                       [--doctrine-target nearest|strongest|players_first] [--fast]
#       Creates <dir>/session.json and plays to the first workshop (<dir>/step_01).
#   scripts/playtest.sh advance <dir> [--commands '<JSON array>'] [--stay] [--no-shots]
#       Records the commands for the current decision point (applied in order on the tick the workshop
#       opens; set_drive / set_target allowed too), then plays the next combat to the next workshop (or
#       game over) and writes <dir>/step_NN/{summary.txt,state.json,*.png}. --stay only records the
#       commands (e.g. a reroll) and re-renders the same decision point without playing on.
#   scripts/playtest.sh status <dir>
#       Prints the latest summary.txt.
#
# Commands: {"type":"pick_card","value":0..2} {"type":"reroll"} {"type":"buy_tech","value":"<id>"}
#   {"type":"ready"} {"type":"set_drive","value":"circle|kite|charge"}
#   {"type":"set_target","value":"nearest|strongest|players_first"}
# Screenshots per step: combat_early/mid/late.png and workshop.png (or gameover.png), native 640x360 plus
# *_1080p.png. Prints timing. Exit code 0 ok, 1 failure, 2 usage error.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="$HOME/.local/bin/godot"

usage() { sed -n 2,23p "${BASH_SOURCE[0]}" >&2; exit 2; }
[ $# -ge 2 ] || usage
CMD="$1"
DIR_ARG="$2"
shift 2
case "$CMD" in
  new|advance|status) ;;
  *) usage ;;
esac
mkdir -p "$DIR_ARG" || exit 1
DIR="$(cd "$DIR_ARG" && pwd)"

if [ "$CMD" = "status" ]; then
  last="$(ls -d "$DIR"/step_* 2>/dev/null | sort | tail -n 1)"
  if [ -z "$last" ] || [ ! -f "$last/summary.txt" ]; then
    echo "playtest.sh: no summary in $DIR (run 'new' first)" >&2
    exit 1
  fi
  cat "$last/summary.txt"
  exit 0
fi

if [ ! -x "$GODOT" ]; then
  "$ROOT/scripts/setup-godot.sh" || exit 1
fi
# The global class cache must exist (first run, or after class_name scripts were added).
if [ ! -f "$ROOT/game/.godot/global_script_class_cache.cfg" ]; then
  "$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
fi

# Split our own flags from the ones passed through to tools/playtest.gd.
SHOTS=1
PASS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-shots) SHOTS=0; shift ;;
    --commands) PASS+=("--commands=$2"); shift 2 ;;
    --commands=*) PASS+=("$1"); shift ;;
    --seed|--mode|--opponents|--name|--color|--doctrine-drive|--doctrine-target) PASS+=("$1=$2"); shift 2 ;;
    --stay|--fast) PASS+=("$1"); shift ;;
    -h|--help) usage ;;
    *) echo "playtest.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "$CMD" = "new" ] && [ -f "$DIR/session.json" ]; then
  echo "playtest.sh: $DIR already holds a session (pick another directory)" >&2
  exit 2
fi
if [ "$CMD" = "advance" ] && [ ! -f "$DIR/session.json" ]; then
  echo "playtest.sh: no session.json in $DIR (run 'new' first)" >&2
  exit 2
fi

t_start=$(date +%s.%N)
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
"$GODOT" --headless --path "$ROOT/game" -s res://tools/playtest.gd -- --op="$CMD" --dir="$DIR" ${PASS[@]+"${PASS[@]}"} >"$log" 2>&1
code=$?
if [ "$code" -ne 0 ] || ! grep -q "^PLAYTEST_OK" "$log"; then
  if grep -q "PLAYTEST_GAME_OVER" "$log"; then
    echo "game over"
    cat "$(ls -d "$DIR"/step_* | sort | tail -n 1)/summary.txt"
    exit 0
  fi
  grep -E "PLAYTEST_ERROR|SCRIPT ERROR|Parse Error|^ERROR:" "$log" >&2
  [ "$code" -eq 2 ] && exit 2
  echo "playtest.sh: simulation replay failed (exit $code)" >&2
  exit 1
fi
if grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
  grep -E "SCRIPT ERROR|Parse Error" "$log" >&2
  echo "playtest.sh: script errors detected" >&2
  exit 1
fi
okline="$(grep "^PLAYTEST_OK" "$log" | tail -n 1)"
step_dir="$(echo "$okline" | sed -E 's/.* dir=([^ ]+) .*/\1/')"
over="$(echo "$okline" | sed -E 's/.* over=([01]) .*/\1/')"
sim_ms="$(echo "$okline" | sed -E 's/.* sim_ms=([0-9]+).*/\1/')"
t_sim=$(date +%s.%N)

render_s=0
if [ "$SHOTS" = "1" ]; then
  rlog="$(mktemp)"
  xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$ROOT/game" --rendering-driver opengl3 --audio-driver Dummy \
    -- --shot="$step_dir/frames" --scenario=replay --session="$DIR" --frames="$step_dir/frames.json" >"$rlog" 2>&1
  rcode=$?
  grep -E "SCRIPT ERROR|Parse Error|^ERROR:|^USER ERROR|main: " "$rlog" | grep -v "ALSA" >&2
  nshots=$(grep -c "^SHOT_OK" "$rlog")
  rm -f "$rlog"
  if [ "$rcode" -ne 0 ]; then
    echo "playtest.sh: screenshot rendering failed (exit $rcode); summary.txt is still valid" >&2
    exit 1
  fi
  t_end=$(date +%s.%N)
  render_s=$(echo "$t_end - $t_sim" | bc)
fi
t_all=$(echo "$(date +%s.%N) - $t_start" | bc)

if [ "$over" = "1" ]; then
  echo "game over"
fi
cat "$step_dir/summary.txt"
printf "timing: sim replay %.1fs (in-process %d ms), screenshots %.1fs, total %.1fs\n" "$(echo "$t_sim - $t_start" | bc)" "$sim_ms" "$render_s" "$t_all"
echo "files: $step_dir/{summary.txt,state.json,*.png}"
