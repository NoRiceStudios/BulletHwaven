extends TestCase
## Audio: every event maps to a sound that exists, music per phase, settings, throttling.

const TMP_PROFILE := "user://test_audio_profile.cfg"


func test_every_sound_and_track_loads() -> void:
	for n: String in AudioDirector.SOUNDS:
		assert_true(load(AudioDirector.SFX_DIR + n + ".wav") is AudioStream, "sfx %s loads" % n)
	for t: String in AudioDirector.TRACKS:
		var s: Resource = load(AudioDirector.MUSIC_DIR + t + ".ogg")
		assert_true(s is AudioStreamOggVorbis, "music %s loads" % t)
		assert_true(s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop, "music %s loops" % t)


func test_event_sounds_exist() -> void:
	for type: String in Snapshot.EVENT_TYPES:
		for kind in range(-1, 9):
			var s: String = AudioDirector.sound_for({"type": type, "kind": kind, "owner": 1})
			assert_true(s == "" or AudioDirector.SOUNDS.has(s), "%s/%d -> %s" % [type, kind, s])
	for f: String in AudioDirector.FLAT:
		assert_true(AudioDirector.SOUNDS.has(f), "flat %s is a sound" % f)
	for c: String in AudioDirector.COMMAND_SOUNDS:
		assert_true(AudioDirector.SOUNDS.has(AudioDirector.COMMAND_SOUNDS[c]), "command %s" % c)


func test_event_mapping() -> void:
	assert_eq(AudioDirector.sound_for({"type": "fire", "kind": 2}), "cannon")
	assert_eq(AudioDirector.sound_for({"type": "hit", "kind": 0, "owner": -1}), "acid_hit")
	assert_eq(AudioDirector.sound_for({"type": "kill", "kind": SimWorld.BOULDER}), "kill_boulder")
	assert_eq(AudioDirector.sound_for({"type": "kill", "kind": SimWorld.BOSS_A}), "")
	assert_eq(AudioDirector.sound_for({"type": "kill", "kind": -1}), "")
	assert_eq(AudioDirector.sound_for({"type": "vehicle_destroyed"}), "explosion")
	assert_eq(AudioDirector.sound_for({"type": "retreat"}), "")


func test_music_follows_the_phase() -> void:
	var w := SimWorld.new(3)
	assert_eq(AudioDirector.track_for(null, false), "menu")
	assert_eq(AudioDirector.track_for(w, true), "menu")
	assert_eq(AudioDirector.track_for(w, false), "combat")
	w.boss_state = Bosses.ST_ACTIVE
	assert_eq(AudioDirector.track_for(w, false), "boss")
	w.phase = SimWorld.PHASE_WORKSHOP
	assert_eq(AudioDirector.track_for(w, false), "workshop")
	w.phase = SimWorld.PHASE_GAME_OVER
	assert_eq(AudioDirector.track_for(w, false), "menu")


func test_levels_clamp_and_persist() -> void:
	assert_eq(AudioDirector.clamp_level(1.7), 1.0)
	assert_eq(AudioDirector.clamp_level(-3), 0.0)
	assert_eq(AudioDirector.clamp_level("loud"), 1.0)
	assert_true(absf(AudioDirector.clamp_level(0.43) - 0.4) < 0.001, "snaps to tenths")
	assert_eq(AudioDirector.level_db(0.0), -80.0)
	assert_eq(AudioDirector.level_db(1.0), 0.0)
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", "KEEP ME")
	cfg.save(TMP_PROFILE)
	var a := AudioDirector.new()
	AudioDirector.ensure_buses()
	a.levels["music"] = 0.3
	a.muted = true
	a.save_settings(TMP_PROFILE)
	var b := AudioDirector.new()
	b.load_settings(TMP_PROFILE)
	assert_true(absf(float(b.levels["music"]) - 0.3) < 0.001, "music level restored")
	assert_true(b.muted, "mute restored")
	var back := ConfigFile.new()
	back.load(TMP_PROFILE)
	assert_eq(back.get_value("profile", "name", ""), "KEEP ME")
	a.free()
	b.free()
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PROFILE))


func test_throttle_limits_repeats() -> void:
	var a := AudioDirector.new()
	assert_true(a.admit("mg"), "first shot plays")
	assert_true(not a.admit("mg"), "inside the interval: throttled")
	assert_true(a.admit("mg", true), "the focus rig's gun has its own lane")
	assert_true(a.admit("kill_mite"), "other sounds still play")
	assert_true(not a.admit("no_such_sound"), "unknown names are ignored")
	a.free()
