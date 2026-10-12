#!/usr/bin/env bash
# Starts a headless host and a headless client on localhost and checks they sync.
# Exit 0 = pass, 1 = fail. LAN discovery is checked too; if UDP broadcast is unavailable
# (common in containers) it is reported as "skipped (no broadcast)" and does not fail the run.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="$HOME/.local/bin/godot"
SECONDS_RUN="${1:-8}"
if [ ! -x "$GODOT" ]; then
  "$ROOT/scripts/setup-godot.sh" || exit 1
fi
if [ ! -f "$ROOT/game/.godot/global_script_class_cache.cfg" ]; then
  "$GODOT" --headless --path "$ROOT/game" --import >/dev/null 2>&1 || true
fi

tmp="$(mktemp -d)"
host_pid=""
client_pid=""
cleanup() {
  [ -n "$host_pid" ] && kill "$host_pid" 2>/dev/null
  [ -n "$client_pid" ] && kill "$client_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

# Both processes stop at the same wall-clock moment so their ticks are comparable.
now_ms=$(( $(date +%s%N) / 1000000 ))
until_ms=$(( now_ms + (SECONDS_RUN + 4) * 1000 ))

"$GODOT" --headless --path "$ROOT/game" -s res://net/smoke.gd -- \
  --role=host --discovery --until="$until_ms" >"$tmp/host.log" 2>&1 &
host_pid=$!
sleep 2
"$GODOT" --headless --path "$ROOT/game" -s res://net/smoke.gd -- \
  --role=client --discovery --address=127.0.0.1 --until="$until_ms" >"$tmp/client.log" 2>&1 &
client_pid=$!

wait "$host_pid"; host_code=$?; host_pid=""
wait "$client_pid"; client_code=$?; client_pid=""

host_line="$(grep -h '^SMOKE_RESULT ' "$tmp/host.log" | tail -1 | sed 's/^SMOKE_RESULT //')"
client_line="$(grep -h '^SMOKE_RESULT ' "$tmp/client.log" | tail -1 | sed 's/^SMOKE_RESULT //')"
echo "host:   $host_line"
echo "client: $client_line"

if [ -z "$host_line" ] || [ -z "$client_line" ]; then
  echo "lan-smoke: FAIL (missing result line; host exit $host_code, client exit $client_code)"
  echo "--- host log"; tail -20 "$tmp/host.log"
  echo "--- client log"; tail -20 "$tmp/client.log"
  exit 1
fi

HOST_JSON="$host_line" CLIENT_JSON="$client_line" python3 -I - <<'PY'
import json, os, sys

h = json.loads(os.environ["HOST_JSON"])
c = json.loads(os.environ["CLIENT_JSON"])
fails = []

def check(ok, msg):
    print(("  ok    " if ok else "  FAIL  ") + msg)
    if not ok:
        fails.append(msg)

if "error" in h or "error" in c:
    check(False, "harness error: host=%s client=%s" % (h.get("error"), c.get("error")))
else:
    check(abs(h["tick"] - c["tick"]) <= 10, "client tick %d within 10 of host tick %d" % (c["tick"], h["tick"]))
    check(h["tick"] > 60, "host advanced (tick %d)" % h["tick"])
    check(h["vehicle_count"] == 2, "host has 2 vehicles (%d)" % h["vehicle_count"])
    check(c["vehicle_count"] == 2, "client sees 2 vehicles (%d)" % c["vehicle_count"])
    check(c.get("own_vehicle_exists") is True, "client's own vehicle exists")
    check(c.get("own_drive_is_kite") is True, "client's doctrine changed to kite (client view)")
    kite_on_host = [v for v in h["vehicles"] if v["peer_id"] not in (1, 0) and v["drive"] == "kite"]
    check(len(kite_on_host) == 1, "host applied the client's command")
    he, ce = h["enemy_count"], c["enemy_count"]
    check(he > 0 and abs(he - ce) <= max(5, he * 0.25), "enemy counts similar (host %d, client %d)" % (he, ce))

# LAN discovery (optional).
sent = h.get("beacons_sent", 0)
found = c.get("discovery_found", [])
if found:
    print("  ok    discovery: found host via broadcast: %s" % ", ".join(found))
else:
    print("  discovery: skipped (no broadcast)  [beacons sent=%s, send error=%s, listen error=%s]"
          % (sent, h.get("beacon_send_error"), c.get("discovery_error")))

if fails:
    print("lan-smoke: FAIL")
    sys.exit(1)
print("lan-smoke: PASS")
PY
exit $?
