#!/usr/bin/env bash
# Headless bot league: plays many bot-vs-bot matches (solo + 4-player ffa) and writes
# docs/balance/report.md plus CSVs. Prints the findings section at the end.
#
#   scripts/bot-league.sh [--solo-seeds N] [--ffa-matches M] [--random-seeds K] [--rounds R] [--jobs J]
#                         [--out DIR] [--policies a,b,c] [--report-only] [--project DIR]
#
# Defaults: 8 solo seeds per policy (the unbiased `random` policy gets 200: it is the control group for
# card/tech lift), 60 ffa matches, 20-round cap, one process per CPU core (max 8). About 9 minutes on
# 4 cores; the committed docs/balance/report.md used a larger run (see its header). Raw per-match data goes to <out>/raw/*.jsonl
# (git-ignored); --report-only re-aggregates existing raw data. --project runs against another
# copy of the Godot project (e.g. a frozen snapshot, to compare balance changes in isolation).
# If <out>/proposed_changes.md exists it is appended to the report ("Proposed changes").
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="$HOME/.local/bin/godot"
SEEDS=8
MATCHES=60
RANDOM_SEEDS=200
ROUNDS=20
OUT="$ROOT/docs/balance"
POLICIES=""
PROJECT="$ROOT/game"
REPORT_ONLY=0
JOBS="$(nproc 2>/dev/null || echo 4)"
[ "$JOBS" -gt 8 ] && JOBS=8
while [ $# -gt 0 ]; do
  case "$1" in
    --solo-seeds) SEEDS="$2"; shift 2 ;;
    --ffa-matches) MATCHES="$2"; shift 2 ;;
    --random-seeds) RANDOM_SEEDS="$2"; shift 2 ;;
    --rounds) ROUNDS="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --out) OUT="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2 ;;
    --policies) POLICIES="$2"; shift 2 ;;
    --project) PROJECT="$(cd "$2" && pwd)"; shift 2 ;;
    --report-only) REPORT_ONLY=1; shift ;;
    -h|--help) sed -n 2,15p "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ ! -x "$GODOT" ]; then
  "$ROOT/scripts/setup-godot.sh" || exit 1
fi
if ! grep -q "BotPolicy" "$PROJECT/.godot/global_script_class_cache.cfg" 2>/dev/null; then
  "$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
fi
mkdir -p "$OUT/raw"
G=("$GODOT" --headless --path "$PROJECT" -s res://tools/bot_league.gd --)
EXTRA=()
[ -f "$OUT/proposed_changes.md" ] && EXTRA=(--extra="$OUT/proposed_changes.md")
POL=()
[ -n "$POLICIES" ] && POL=(--policies="$POLICIES")

if [ "$REPORT_ONLY" -eq 0 ]; then
  rm -f "$OUT"/raw/raw_*.jsonl
  echo "bot-league: solo seeds=$SEEDS (random $RANDOM_SEEDS) ffa matches=$MATCHES round cap=$ROUNDS processes=$JOBS"
  start=$(date +%s)
  pids=()
  for ((i = 0; i < JOBS; i++)); do
    "${G[@]}" --stage=run --mode=all --seeds="$SEEDS" --matches="$MATCHES" --rounds="$ROUNDS" \
      --random-extra=$((RANDOM_SEEDS > SEEDS ? RANDOM_SEEDS - SEEDS : 0)) --shard="$i/$JOBS" --out="$OUT/raw" "${POL[@]}" 2>&1 \
      | grep --line-buffered -E "^\[shard|ERROR|Parse Error" &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  echo "bot-league: matches done in $(( $(date +%s) - start )) s"
fi

"${G[@]}" --stage=report --rounds="$ROUNDS" --in="$OUT/raw" --out="$OUT" "${EXTRA[@]}" 2>&1 | grep -E "report|ERROR|Parse Error"
echo
echo "================ FINDINGS (full report: $OUT/report.md) ================"
cat "$OUT/findings.txt"
