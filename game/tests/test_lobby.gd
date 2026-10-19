extends TestCase
## Lobby, player identity and match lifecycle of NetSession. The network layer itself is not needed:
## a NetSession outside the scene tree sends no RPCs, and peers "connect" through the same
## _on_peer_connected / _handle_command paths the real RPCs use (scripts/lan-smoke.sh covers ENet).


func _host() -> NetSession:
	var s := NetSession.new()
	s._mode = NetSession.Mode.HOST
	s._open_lobby()
	return s


func _profile(name_s: Variant, color: Variant) -> Dictionary:
	return {"type": "profile", "name": name_s, "color_index": color}


func _names(s: NetSession) -> Array:
	var out: Array = []
	for e in s.lobby_players:
		out.append(e["name"])
	return out


func _colors(s: NetSession) -> Array:
	var out: Array = []
	for e in s.lobby_players:
		out.append(e["color_index"])
	return out


func _count_signal(sig: Signal) -> Array:
	var box: Array = [0]
	sig.connect(func() -> void: box[0] += 1)
	return box


func test_sanitize_names() -> void:
	assert_eq(SimVehicle.sanitize_name("Bob"), "Bob")
	assert_eq(SimVehicle.sanitize_name("  Bob   the   Builder  "), "Bob the Builder", "trim and collapse spaces")
	assert_eq(SimVehicle.sanitize_name("a\nb\tc\u0007d"), "abcd", "control chars dropped")
	var fancy: String = "caf" + char(0xE9) + " " + char(0x202E) + "evil " + char(0x1F600)
	assert_eq(SimVehicle.sanitize_name(fancy), "caf evil", "non-ASCII dropped")
	assert_eq(SimVehicle.sanitize_name(""), SimVehicle.DEFAULT_NAME)
	assert_eq(SimVehicle.sanitize_name("   "), SimVehicle.DEFAULT_NAME)
	assert_eq(SimVehicle.sanitize_name("\u0001\u0002"), SimVehicle.DEFAULT_NAME)
	assert_eq(SimVehicle.sanitize_name("X".repeat(100)), "X".repeat(16), "max 16 chars")
	assert_eq(SimVehicle.sanitize_name("0123456789abcde fghij"), "0123456789abcde", "cut then trimmed again")
	assert_eq(SimVehicle.sanitize_name("A".repeat(1000000)).length(), 16, "huge input is cheap")


func test_profile_validation() -> void:
	var ok: Dictionary = NetSession.validate_command(_profile("  Bob  ", 3))
	assert_eq(ok, {"type": "profile", "name": "Bob", "color_index": 3}, "sanitised")
	assert_eq(NetSession.validate_command(_profile("Bob", 3.0))["color_index"], 3, "integral float colour")
	assert_eq(NetSession.validate_command({"type": "profile", "name": "Bob", "color_index": 2, "hp": 9, "x": [1]}).size(), 3, "extra keys dropped")
	var junk: Array = [
		_profile("Bob", 8), _profile("Bob", -1), _profile("Bob", 2.5), _profile("Bob", "3"), _profile("Bob", null),
		_profile("Bob", INF), _profile("Bob", NAN), _profile(5, 1), _profile(null, 1), _profile(["Bob"], 1),
		_profile("x".repeat(65), 1), _profile("x".repeat(100000), 1),
		{"type": "profile"}, {"type": "profile", "name": "Bob"}, {"type": "profile", "color_index": 1},
		{"type": "lobby_ready"}, {"type": "lobby_ready", "value": 1}, {"type": "lobby_ready", "value": "true"},
		{"type": "lobby_ready", "value": null}, {"type": "lobby_ready", "value": [true]},
		{"type": "Profile", "name": "a", "color_index": 1}, {"type": "start_match"}, {"type": "rematch"},
		{"type": "kick", "value": "2"},
	]
	for j: Variant in junk:
		assert_true(NetSession.validate_command(j).is_empty(), "rejected: %s" % str(j).left(50))
	assert_eq(NetSession.validate_command({"type": "lobby_ready", "value": true}), {"type": "lobby_ready", "value": true})
	assert_eq(NetSession.validate_command({"type": "lobby_ready", "value": false, "x": 1}), {"type": "lobby_ready", "value": false})


func test_lobby_join_unique_names_and_colors() -> void:
	var s := _host()
	s.set_profile("Hosty", 4)  # while in the lobby: a command to ourselves
	assert_eq(s.lobby_players.size(), 1)
	assert_true(bool(s.lobby_players[0]["is_host"]) and int(s.lobby_players[0]["peer_id"]) == 1)
	assert_eq(s.lobby_players[0]["name"], "Hosty")
	assert_eq(s.lobby_players[0]["color_index"], 4)
	var changed: Array = _count_signal(s.lobby_changed)
	s._on_peer_connected(2)
	s._on_peer_connected(3)
	assert_eq(s.lobby_players.size(), 3)
	assert_eq(changed[0], 2, "lobby_changed per join")
	# Hello with the same colour as the host and a name that differs only by case.
	s._handle_command(2, _profile("HOSTY", 4))
	assert_eq(s.lobby_players[1]["name"], "HOSTY 2", "name made unique (case-insensitive)")
	assert_ne(s.lobby_players[1]["color_index"], 4, "taken colour not given twice")
	s._handle_command(3, _profile("Hosty", 1))
	assert_eq(s.lobby_players[2]["name"], "Hosty 3")
	assert_eq(s.lobby_players[2]["color_index"], 1, "preferred colour used when free")
	# Peer 2 took the lowest free colour (0), unique across the lobby.
	assert_eq(s.lobby_players[1]["color_index"], 0)
	var seen: Dictionary = {}
	for c in _colors(s):
		seen[c] = true
	assert_eq(seen.size(), 3, "colours unique")
	# A long name leaves room for the suffix.
	s._on_peer_connected(4)
	s._handle_command(4, _profile("X".repeat(30), 7))
	s._on_peer_connected(5)
	s._handle_command(5, _profile("X".repeat(30), 7))
	assert_eq(s.lobby_players[4]["name"], "XXXXXXXXXXXXXX 2", "16 chars including the suffix")
	assert_eq(s.lobby_players[4]["color_index"], 2, "next free colour")
	s.free()


func test_lobby_profile_changes_and_ready() -> void:
	var s := _host()
	s._on_peer_connected(2)
	s._handle_command(2, _profile("Bob", 3))
	var changed: Array = _count_signal(s.lobby_changed)
	# Taking the host's colour is refused: Bob keeps his.
	s._handle_command(2, _profile("Bobby", int(s.lobby_players[0]["color_index"])))
	assert_eq(s.lobby_players[1]["name"], "Bobby")
	assert_eq(s.lobby_players[1]["color_index"], 3, "taken colour refused, current kept")
	assert_eq(changed[0], 1)
	# Re-sending the same profile changes nothing and stays quiet.
	s._handle_command(2, _profile("Bobby", 3))
	assert_eq(changed[0], 1, "no-op profile does not notify")
	# Renaming to your own name in another case is fine; to someone else's is made unique.
	s._handle_command(2, _profile("BOBBY", 3))
	assert_eq(s.lobby_players[1]["name"], "BOBBY")
	s._handle_command(2, _profile(String(s.lobby_players[0]["name"]).to_lower(), 3))
	assert_eq(s.lobby_players[1]["name"], "driver 2")
	# Ready toggles per player.
	assert_false(s.lobby_all_ready())
	s._handle_command(2, {"type": "lobby_ready", "value": true})
	assert_true(s.lobby_players[1]["ready"])
	assert_false(s.lobby_players[0]["ready"])
	assert_true(s.lobby_all_ready(), "host's own flag is not required")
	s._handle_command(2, {"type": "lobby_ready", "value": false})
	assert_false(s.lobby_all_ready())
	s.set_lobby_ready(true)  # the host toggles itself
	assert_true(s.lobby_players[0]["ready"])
	# Commands from strangers and junk are ignored.
	var before: Array = s.lobby_players.duplicate(true)
	s._handle_command(99, _profile("Evil", 5))
	s._handle_command(99, {"type": "lobby_ready", "value": true})
	s._handle_command(2, _profile("Evil", 99))
	s._handle_command(2, "garbage")
	s._handle_command(2, {"type": "start_match"})
	assert_eq(s.lobby_players, before, "junk changes nothing")
	s.free()


func test_start_match_builds_world() -> void:
	var s := _host()
	s.world_seed = 77
	s.set_profile("Hosty", 5)
	s._on_peer_connected(2)
	s._handle_command(2, _profile("Bob", 2))
	var started: Array = _count_signal(s.match_started)
	assert_true(s.in_lobby())
	assert_eq(s.start_match(), OK, "host may force the start without ready flags")
	assert_true(s.in_match())
	assert_eq(started[0], 1, "match_started emitted")
	assert_eq(s.world.seed, 77)
	assert_true(s.world.spawning_enabled)
	assert_eq(s.world.vehicles.size(), 2)
	assert_eq(s.world.vehicles[0].peer_id, 1)
	assert_eq(s.world.vehicles[0].player_name, "Hosty")
	assert_eq(s.world.vehicles[0].color_index, 5)
	assert_eq(s.world.vehicles[1].peer_id, 2)
	assert_eq(s.world.vehicles[1].player_name, "Bob")
	assert_eq(s.world.vehicles[1].color_index, 2)
	assert_eq(s.start_match(), ERR_UNAVAILABLE, "not twice")
	# Game commands now reach the vehicles; lobby ready is a no-op in a match.
	s._handle_command(2, {"type": "set_drive", "value": "kite"})
	assert_eq(s.world.vehicles[1].doctrine["drive"], "kite")
	s._handle_command(2, {"type": "lobby_ready", "value": true})
	assert_false(s.lobby_players[1]["ready"])
	# A mid-match rename shows up on the vehicle.
	s._handle_command(2, _profile("Robert", 6))
	assert_eq(s.world.vehicles[1].player_name, "Robert")
	assert_eq(s.world.vehicles[1].color_index, 6)
	s.free()

	var client := NetSession.new()
	client._mode = NetSession.Mode.CLIENT
	assert_eq(client.start_match(), ERR_UNAUTHORIZED, "clients cannot start")
	assert_eq(client.rematch(), ERR_UNAUTHORIZED, "clients cannot rematch")
	client.free()


func test_lobby_does_not_step_the_sim() -> void:
	var s := _host()
	s._on_peer_connected(2)
	for i in 30:
		s._physics_process(1.0 / 30.0)
	assert_eq(s.world.tick, 0, "lobby world is not stepped")
	assert_eq(s.world.vehicles.size(), 0, "and has no vehicles")
	s.start_match()
	for i in 30:
		s._physics_process(1.0 / 30.0)
	assert_eq(s.world.tick, 30, "match is stepped")
	s.free()


func test_start_match_needs_a_player() -> void:
	var s := NetSession.new()
	s._mode = NetSession.Mode.HOST
	assert_eq(s.start_match(), ERR_UNAVAILABLE, "idle: no lobby")
	s._open_lobby()
	s.lobby_players.clear()
	assert_eq(s.start_match(), ERR_UNCONFIGURED, "empty roster")
	s.free()


func test_late_join_policy() -> void:
	# Lobby-driven session: late joiners are refused and leave no trace.
	var s := _host()
	s.start_match()
	assert_false(s.allow_late_join)
	s._on_peer_connected(2)
	assert_eq(s.lobby_players.size(), 1)
	assert_eq(s.world.vehicles.size(), 1)
	s._on_peer_disconnected(2)  # the refused peer's disconnect is silent
	assert_eq(s.lobby_players.size(), 1)
	s.free()

	# Legacy auto-start session: late joiners get a vehicle with a unique identity.
	var l := _host()
	l.allow_late_join = true
	l.start_match()
	l._on_peer_connected(2)
	assert_eq(l.world.vehicles.size(), 2)
	assert_eq(l.lobby_players.size(), 2)
	assert_eq(l.world.vehicles[1].peer_id, 2)
	assert_ne(l.world.vehicles[1].color_index, l.world.vehicles[0].color_index)
	assert_eq(l.world.vehicles[1].player_name, "DRIVER 2")
	l._handle_command(2, _profile("Late", l.world.vehicles[1].color_index))
	assert_eq(l.world.vehicles[1].player_name, "Late", "hello after connecting renames the vehicle")
	l._on_peer_disconnected(2)
	assert_true(l.world.vehicles[1].eliminated)
	assert_eq(l.lobby_players.size(), 1, "left the roster")
	l._on_peer_connected(3)
	assert_eq(l.world.vehicles.size(), 2, "departed slot reused")
	assert_eq(l.world.vehicles[1].peer_id, 3)
	l.free()


func test_lobby_peer_leaves_and_capacity() -> void:
	var s := _host()
	var left: Array = [0]
	s.peer_left.connect(func(_id: int) -> void: left[0] += 1)
	s._on_peer_connected(2)
	s._handle_command(2, _profile("Bob", 5))
	assert_eq(s.lobby_players[1]["color_index"], 5)
	s._on_peer_disconnected(2)
	assert_eq(s.lobby_players.size(), 1)
	assert_eq(left[0], 1)
	s._on_peer_connected(3)
	s._handle_command(3, _profile("Eve", 5))
	assert_eq(s.lobby_players[1]["color_index"], 5, "freed colour is reusable")
	s._on_peer_disconnected(3)
	# Fill the lobby: the 9th peer is refused.
	for p in range(2, 2 + NetSession.MAX_PLAYERS - 1):
		s._on_peer_connected(p)
	assert_eq(s.lobby_players.size(), NetSession.MAX_PLAYERS)
	assert_eq(_colors(s).size(), 8)
	var uniq: Dictionary = {}
	for c in _colors(s):
		uniq[c] = true
	assert_eq(uniq.size(), 8, "8 players, 8 distinct colours")
	s._on_peer_connected(50)
	assert_eq(s.lobby_players.size(), NetSession.MAX_PLAYERS, "lobby full")
	s.free()


func test_solo_defaults_and_rematch() -> void:
	var s := NetSession.new()
	s.world_seed = 10
	s.start_solo()
	var v: SimVehicle = s.world.vehicles[0]
	assert_eq(v.player_name, "DRIVER")
	assert_eq(v.color_index, 0)
	assert_eq(s.world.seed, 10)
	assert_eq(s.rematch(), ERR_UNAVAILABLE, "only after game over")
	var ended: Array = [0, 99]
	s.match_ended.connect(func(w: int) -> void:
		ended[0] += 1
		ended[1] = w)
	v.eliminated = true
	s._physics_process(1.0 / 30.0)
	assert_eq(s.world.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(ended[0], 1, "match_ended emitted once")
	assert_eq(ended[1], -1, "solo loss: no winner")
	s._physics_process(1.0 / 30.0)
	assert_eq(ended[0], 1)
	var old_world: SimWorld = s.world
	var started: Array = _count_signal(s.match_started)
	assert_eq(s.rematch(), OK)
	assert_eq(started[0], 1)
	assert_true(s.world != old_world, "fresh world")
	assert_eq(s.world.seed, 11, "new seed")
	assert_eq(s.world.phase, SimWorld.PHASE_DEPLOY)
	assert_eq(s.world.vehicles.size(), 1)
	assert_false(s.world.vehicles[0].eliminated)
	assert_true(s.in_match())
	# match_ended fires again for the next game.
	s.world.vehicles[0].eliminated = true
	s._physics_process(1.0 / 30.0)
	assert_eq(ended[0], 2)
	s.free()

	var n := NetSession.new()
	n.start_solo("Ace of Spades Deluxe", 5)
	assert_eq(n.world.vehicles[0].player_name, "Ace of Spades De")
	assert_eq(n.world.vehicles[0].color_index, 5)
	n.start_solo("Ace", 99)
	assert_eq(n.world.vehicles[0].color_index, 7, "colour clamped")
	n.free()


func test_multiplayer_rematch_keeps_players() -> void:
	var s := _host()
	s.world_seed = 5
	s.set_profile("Hosty", 3)
	s._on_peer_connected(2)
	s._handle_command(2, _profile("Bob", 6))
	s._handle_command(2, {"type": "lobby_ready", "value": true})
	s.start_match()
	assert_eq(s.rematch(), ERR_UNAVAILABLE, "match still running")
	s.world.vehicles[1].eliminated = true
	s._physics_process(1.0 / 30.0)
	assert_eq(s.world.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(s.world.winner_peer, 1)
	assert_eq(s.rematch(), OK)
	assert_eq(s.world.seed, 6)
	assert_eq(s.world.vehicles.size(), 2)
	assert_eq(s.world.vehicles[0].player_name, "Hosty")
	assert_eq(s.world.vehicles[1].player_name, "Bob")
	assert_eq(s.world.vehicles[1].color_index, 6)
	assert_eq(s.world.phase, SimWorld.PHASE_DEPLOY)
	assert_false(s.lobby_players[1]["ready"], "ready flags reset")
	s.free()


func test_fast_rounds_flag_applies_to_matches() -> void:
	var s := NetSession.new()
	s.fast_rounds = true
	s.start_solo()
	assert_true(s.world.fast_rounds)
	assert_eq(s.world.phase_ticks_left, SimWorld.FAST_DEPLOY_TICKS)
	s.free()


func test_parse_lobby_rejects_junk() -> void:
	var good: Array = [
		{"peer_id": 1, "name": "Hosty", "color_index": 0, "ready": false, "is_host": true},
		{"peer_id": 7, "name": "  Bob\n", "color_index": 3, "ready": true, "is_host": false},
	]
	var parsed: Array[Dictionary] = NetSession.parse_lobby(good)
	assert_eq(parsed.size(), 2)
	assert_eq(parsed[1]["name"], "Bob", "names sanitised on receipt")
	var bad_lists: Array = [
		null, 5, "x", {}, [], [1], [{}],
		[good[1]],  # no host
		[good[0], good[0]],  # duplicate peer / two hosts
		[good[0], {"peer_id": 7, "name": "B", "color_index": 0, "ready": false, "is_host": false}],  # duplicate colour
		[good[0], {"peer_id": 7, "name": "B", "color_index": 9, "ready": false, "is_host": false}],
		[good[0], {"peer_id": 7, "name": 5, "color_index": 3, "ready": false, "is_host": false}],
		[good[0], {"peer_id": 0, "name": "B", "color_index": 3, "ready": false, "is_host": false}],
		[good[0], {"peer_id": "7", "name": "B", "color_index": 3, "ready": false, "is_host": false}],
		[good[0], {"peer_id": 7, "name": "B", "color_index": 3, "ready": 1, "is_host": false}],
		[good[0], {"peer_id": 7, "name": "B", "color_index": 3, "ready": false}],
		[good[0], {"peer_id": 7, "name": "x".repeat(500), "color_index": 3, "ready": false, "is_host": false}],
	]
	for b: Variant in bad_lists:
		assert_true(NetSession.parse_lobby(b).is_empty(), "rejected: %s" % str(b).left(60))
	var too_many: Array = []
	for i in 9:
		too_many.append({"peer_id": i + 1, "name": "P%d" % i, "color_index": i % 8, "ready": false, "is_host": i == 0})
	assert_true(NetSession.parse_lobby(too_many).is_empty(), "more than 8 players")


func test_beacon_carries_state() -> void:
	var s := _host()
	var lan := LanDiscovery.new()
	lan.session = s
	s.set_profile("Hosty", 1)
	s._on_peer_connected(2)
	lan._refresh_from_session()
	assert_eq(lan.player_count, 2)
	assert_eq(lan.match_state, "lobby")
	assert_eq(lan.host_name, "Hosty")
	s.start_match()
	lan._refresh_from_session()
	assert_eq(lan.match_state, "match")
	var pkt: PackedByteArray = JSON.stringify({"game": "BulletHwaven", "version": 1, "port": 24680, "players": 2, "name": "H", "state": "match"}).to_utf8_buffer()
	assert_eq(LanDiscovery.parse_beacon(pkt).get("state"), "match")
	var odd: PackedByteArray = JSON.stringify({"game": "BulletHwaven", "version": 1, "port": 24680, "state": "<script>"}).to_utf8_buffer()
	assert_eq(LanDiscovery.parse_beacon(odd).get("state"), "lobby", "unknown state falls back")
	var old: PackedByteArray = JSON.stringify({"game": "BulletHwaven", "version": 1, "port": 24680}).to_utf8_buffer()
	assert_eq(LanDiscovery.parse_beacon(old).get("state"), "lobby", "beacons without state still parse")
	lan.free()
	s.free()


func test_lobby_command_rate_limit() -> void:
	var s := NetSession.new()
	var ok: int = 0
	for i in 50:
		if s._window_ok(s._lobby_rate, 5, 1000 + i, NetSession.MAX_LOBBY_COMMANDS_PER_SEC):
			ok += 1
	assert_eq(ok, NetSession.MAX_LOBBY_COMMANDS_PER_SEC)
	s.free()
