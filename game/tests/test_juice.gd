extends TestCase
## Render-only combat juice state (render/juice_state.gd): kill combo of the watched rig and the
## hive surge banner, derived from sim events by tick.


func test_combo_chains_within_window_and_breaks_after() -> void:
	var j := JuiceState.new()
	j.set_focus(0)
	for t in [10, 20, 30]:
		j.on_kill(0, t)
	assert_eq(j.combo, 3)
	assert_eq(j.combo_shown(30), 3, "shows from COMBO_MIN")
	assert_true(j.combo_live(30 + JuiceState.COMBO_WINDOW))
	assert_true(not j.combo_live(31 + JuiceState.COMBO_WINDOW), "window lapsed")
	assert_eq(j.combo_shown(30 + JuiceState.COMBO_WINDOW + JuiceState.COMBO_FADE), 3, "lingers while fading")
	assert_eq(j.combo_shown(31 + JuiceState.COMBO_WINDOW + JuiceState.COMBO_FADE), 0, "then hides")
	j.on_kill(0, 31 + JuiceState.COMBO_WINDOW)
	assert_eq(j.combo, 1, "a late kill starts a new chain")
	assert_eq(j.combo_best, 3)


func test_combo_ignores_other_rigs_and_resets_on_focus_change() -> void:
	var j := JuiceState.new()
	j.set_focus(1)
	j.on_kill(0, 5)
	j.on_kill(-1, 5)
	assert_eq(j.combo, 0, "kills by others or the hive do not count")
	j.on_kill(1, 5)
	j.on_kill(1, 5)
	assert_eq(j.combo, 2, "several kills in one tick all count")
	j.set_focus(2)
	assert_eq(j.combo, 0, "switching the watched rig drops the chain")
	assert_eq(j.combo_shown(5), 0)


func test_milestones() -> void:
	var j := JuiceState.new()
	j.set_focus(0)
	var hits: Array[int] = []
	for i in 100:
		if j.on_kill(0, 100 + i / 3):
			hits.append(j.combo)
	assert_eq(hits, [10, 25, 50, 100] as Array[int])
	assert_eq(j.milestone_word, "HIVE BREAKER")
	assert_eq(j.milestone_age(100 + 99 / 3), 0)
	assert_eq(j.milestone_age(100 + 99 / 3 + JuiceState.MILESTONE_TICKS), -1)
	assert_eq(JuiceState.milestone_at(7), "")
	assert_true(JuiceState.heat(3) == 0.0 and JuiceState.heat(100) == 1.0 and JuiceState.heat(40) > 0.3)


func test_surge_banner_is_dormant_until_announced() -> void:
	var j := JuiceState.new()
	for t in [0, 50, 100000]:
		assert_true(not j.surge_active(t), "no surge event, no banner at %d" % t)
	j.on_surge(200, 60)
	assert_true(not j.surge_active(199))
	assert_true(j.surge_active(200))
	assert_eq(j.surge_left(230), 30)
	assert_true(j.surge_active(260 + JuiceState.SURGE_HOLD - 1), "holds as the surge hits")
	assert_true(not j.surge_active(260 + JuiceState.SURGE_HOLD))
	j.on_surge(500, 0)
	assert_eq(j.surge_in, JuiceState.SURGE_DEFAULT_TICKS, "missing in_ticks falls back to 2 s")
	j.reset()
	assert_true(not j.surge_active(500))
