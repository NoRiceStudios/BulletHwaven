#!/usr/bin/env bash
# Starts a headless host and a headless client on localhost and checks the whole flow: the host opens
# a lobby, the client joins and readies up, the host starts the match, both play and must agree on
# names and colours; a third client that joins mid-match must be refused.
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
late_pid=""
cleanup() {
  [ -n "$host_pid" ] && kill "$host_pid" 2>/dev/null
  [ -n "$client_pid" ] && kill "$client_pid" 2>/dev/null
  [ -n "$late_pid" ] && kill "$late_pid" 2>/dev/null
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

sleep 4  # the match has started by now (lobby -> ready -> start takes about a second)
"$GODOT" --headless --path "$ROOT/game" -s res://net/smoke.gd -- \
  --role=late --address=127.0.0.1 --until="$until_ms" >"$tmp/late.log" 2>&1 &
late_pid=$!

wait "$host_pid"; host_code=$?; host_pid=""
wait "$client_pid"; client_code=$?; client_pid=""
wait "$late_pid"; late_code=$?; late_pid=""

host_line="$(grep -h '^SMOKE_RESULT ' "$tmp/host.log" | tail -1 | sed 's/^SMOKE_RESULT //')"
client_line="$(grep -h '^SMOKE_RESULT ' "$tmp/client.log" | tail -1 | sed 's/^SMOKE_RESULT //')"
late_line="$(grep -h '^SMOKE_RESULT ' "$tmp/late.log" | tail -1 | sed 's/^SMOKE_RESULT //')"
echo "host:   $host_line"
echo "client: $client_line"
echo "late:   $late_line"

if [ -z "$host_line" ] || [ -z "$client_line" ] || [ -z "$late_line" ]; then
  echo "lan-smoke: FAIL (missing result line; exits: host $host_code, client $client_code, late $late_code)"
  echo "--- host log"; tail -20 "$tmp/host.log"
  echo "--- client log"; tail -20 "$tmp/client.log"
  echo "--- late log"; tail -20 "$tmp/late.log"
  exit 1
fi

HOST_JSON="$host_line" CLIENT_JSON="$client_line" LATE_JSON="$late_line" python3 -I - <<'PY'
import json, os, sys

h = json.loads(os.environ["HOST_JSON"])
c = json.loads(os.environ["CLIENT_JSON"])
late = json.loads(os.environ["LATE_JSON"])
fails = []

def check(ok, msg):
    print(("  ok    " if ok else "  FAIL  ") + msg)
    if not ok:
        fails.append(msg)

if "error" in h or "error" in c or "error" in late:
    check(False, "harness error: host=%s client=%s late=%s" % (h.get("error"), c.get("error"), late.get("error")))
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

    # Lobby -> start_match: identity must survive and agree on both sides.
    hv = {v["peer_id"]: v for v in h["vehicles"]}
    cl_peer = c["local_peer_id"]
    check(h["in_match"] and c["in_match"], "both sides got match_started")
    check(len(h["lobby_at_start"]) == 2 and all(e["ready"] for e in h["lobby_at_start"] if e["peer_id"] != 1),
          "host started from a lobby of 2 with the client ready")
    check(hv.get(1, {}).get("name") == "Hosty" and hv.get(1, {}).get("color") == 3, "host is Hosty / colour 3 (%s)" % hv.get(1))
    check(hv.get(cl_peer, {}).get("name") == "hosty 2", "client name made unique by the host (%s)" % hv.get(cl_peer, {}).get("name"))
    check(hv.get(cl_peer, {}).get("color") not in (None, 3), "client colour made unique (%s)" % hv.get(cl_peer, {}).get("color"))
    cv = {v["peer_id"]: v for v in c["vehicles"]}
    check({k: (v["name"], v["color"]) for k, v in hv.items()} == {k: (v["name"], v["color"]) for k, v in cv.items()},
          "client sees the same names and colours as the host")
    check(c["lobby_at_start"] == h["lobby_at_start"] or
          [(e["name"], e["color_index"]) for e in c["lobby_at_start"]] == [(e["name"], e["color_index"]) for e in h["lobby_at_start"]],
          "client's roster at match start matches the host's")
    # A client joining mid-match is refused and leaves no vehicle behind.
    check(late.get("rejected") == "match in progress", "late joiner refused (%r)" % late.get("rejected"))
    check(not late.get("in_match"), "late joiner never entered the match")

# LAN discovery (optional).
sent = h.get("beacons_sent", 0)
found = c.get("discovery_found", [])
if found:
    print("  ok    discovery: found host via broadcast: %s (state/players: %s)" % (", ".join(found), ", ".join(c.get("discovery_states", []))))
    check(all(s.split("/")[0] in ("lobby", "match") for s in c.get("discovery_states", [])), "beacon carries a valid state")
else:
    print("  discovery: skipped (no broadcast)  [beacons sent=%s, send error=%s, listen error=%s]"
          % (sent, h.get("beacon_send_error"), c.get("discovery_error")))

if fails:
    print("lan-smoke: FAIL")
    sys.exit(1)
print("lan-smoke: PASS")
PY
exit $?
