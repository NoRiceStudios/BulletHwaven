class_name LanDiscovery
extends Node
## LAN host discovery over UDP broadcast. See docs/architecture.md ("Net contract").
##
## Host: start_beacon() sends a small JSON beacon to 255.255.255.255:24681 once per second.
## Client: start_listening() binds 24681 and emits host_found(address, info) for each new host
## (or when a known host's info changes / it reappears after EXPIRE_SEC). Beacons come from
## the network and are untrusted: they are size limited and every field is validated.

signal host_found(address: String, info: Dictionary)
signal host_lost(address: String)

const DISCOVERY_PORT := 24681
const GAME_NAME := "BulletHwaven"
const PROTOCOL_VERSION := 1
const BEACON_INTERVAL := 1.0
const EXPIRE_SEC := 5.0
const MAX_PACKET := 512

## Shown in the host's beacon (set by the lobby/main script).
var player_count: int = 1
var host_name: String = ""
var match_state: String = "lobby"  ## "lobby" or "match"
## Optional: when set, every beacon refreshes player_count, host_name and match_state from the
## session (so the beacon stays current as people join, leave and the match starts).
var session: NetSession = null
## Last error returned by a failed beacon send (OK if none). Useful to detect "no broadcast".
var last_send_error: Error = OK
var beacons_sent: int = 0

## address -> {"info": Dictionary, "seen": float}
var hosts: Dictionary = {}

var _udp: PacketPeerUDP = null
var _beaconing: bool = false
var _listening: bool = false
var _game_port: int = 24680
var _accum: float = 0.0


func start_beacon(game_port: int = 24680) -> Error:
	stop()
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	var err: Error = _udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	if err != OK:
		_udp.close()
		_udp = null
		return err
	_game_port = game_port
	_beaconing = true
	_accum = BEACON_INTERVAL  # send the first beacon immediately
	set_process(true)
	return OK


func start_listening() -> Error:
	stop()
	_udp = PacketPeerUDP.new()
	var err: Error = _udp.bind(DISCOVERY_PORT)
	if err != OK:
		_udp.close()
		_udp = null
		return err
	_listening = true
	hosts.clear()
	set_process(true)
	return OK


func stop() -> void:
	_beaconing = false
	_listening = false
	if _udp != null:
		_udp.close()
		_udp = null
	set_process(false)


func is_active() -> bool:
	return _beaconing or _listening


func _process(delta: float) -> void:
	if _udp == null:
		return
	if _beaconing:
		_accum += delta
		if _accum >= BEACON_INTERVAL:
			_accum = 0.0
			_send_beacon()
	elif _listening:
		_poll()


func _refresh_from_session() -> void:
	if session != null and is_instance_valid(session):
		player_count = session.player_count()
		match_state = session.state_name()
		var me: Dictionary = session.local_player()
		if not me.is_empty():
			host_name = me["name"]


func _send_beacon() -> void:
	_refresh_from_session()
	var beacon := {
		"game": GAME_NAME,
		"version": PROTOCOL_VERSION,
		"port": _game_port,
		"players": player_count,
		"name": host_name,
		"state": match_state,
	}
	last_send_error = _udp.put_packet(JSON.stringify(beacon).to_utf8_buffer())
	if last_send_error == OK:
		beacons_sent += 1


func _poll() -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	while _udp.get_available_packet_count() > 0:
		var pkt: PackedByteArray = _udp.get_packet()
		var addr: String = _udp.get_packet_ip()
		if _udp.get_packet_error() != OK or pkt.size() > MAX_PACKET or addr.is_empty():
			continue
		var info: Dictionary = parse_beacon(pkt)
		if info.is_empty():
			continue
		var known: Dictionary = hosts.get(addr, {})
		var changed: bool = known.is_empty() or known["info"] != info \
			or now - float(known["seen"]) > EXPIRE_SEC
		hosts[addr] = {"info": info, "seen": now}
		if changed:
			host_found.emit(addr, info)
	for addr: String in hosts.keys():
		if now - float(hosts[addr]["seen"]) > EXPIRE_SEC:
			hosts.erase(addr)
			host_lost.emit(addr)


## Parses and validates a beacon; returns the sanitised info dict or {} if invalid.
static func parse_beacon(pkt: PackedByteArray) -> Dictionary:
	if pkt.is_empty() or pkt.size() > MAX_PACKET:
		return {}
	var json := JSON.new()
	if json.parse(pkt.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = json.data
	if d.get("game") != GAME_NAME:
		return {}
	# JSON numbers parse as float.
	if typeof(d.get("version")) not in [TYPE_FLOAT, TYPE_INT] or int(d["version"]) != PROTOCOL_VERSION:
		return {}
	if typeof(d.get("port")) not in [TYPE_FLOAT, TYPE_INT]:
		return {}
	var port: int = int(d["port"])
	if port < 1 or port > 65535:
		return {}
	var players: int = 0
	if typeof(d.get("players")) in [TYPE_FLOAT, TYPE_INT]:
		players = clampi(int(d["players"]), 0, 64)
	var host_name_s: String = ""
	if typeof(d.get("name")) == TYPE_STRING:
		host_name_s = String(d["name"]).substr(0, 32)
	var state_s: String = "lobby"
	if d.get("state") == "match":
		state_s = "match"
	return {
		"game": GAME_NAME, "version": PROTOCOL_VERSION, "port": port, "players": players,
		"name": host_name_s, "state": state_s,
	}
