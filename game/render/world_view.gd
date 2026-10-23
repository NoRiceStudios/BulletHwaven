class_name WorldView
extends Node2D
## Renders a SimWorld every frame without mutating it (docs/architecture.md, "render/").
## Display positions are extrapolated by velocity since the last sim tick and then eased toward
## that target, so 30 Hz host ticks and 15 Hz client snapshots both look smooth at 60 fps.
## Events are consumed once per sim tick (when world.tick changes), never once per frame.

const SMOOTH_RATE := 22.0  ## 1/s, easing toward the extrapolated sim position
const SNAP_DIST := 48.0  ## px, farther jumps (respawn, snapshot correction) snap instead of easing
const MAX_LEAD := 0.1  ## s, never extrapolate further than this past the last tick
const TRAIL_STEP := 3.0  ## px of travel between tyre-track stamps
const SHOT_EFFECT_TICKS := 10  ## screenshot mode: transient effects from the last N ticks
const WORKSHOP_CAM_LIFT := 88.0  ## px: in the workshop the camped rig sits between the top bar and the cards
const SPECTATE_CAM_LIFT := 84.0  ## the same for the watched rig in the spectator workshop (above the standings)
const CAM_EASE := 4.0  ## 1/s, easing of that lift

var world: SimWorld = null
var local_peer: int = 1
## Menu backdrop: with no local rig the camera drifts slowly over the arena (driven by world.tick,
## so screenshots are deterministic) instead of staying put.
var attract: bool = false
## HUD, workshop and game over overlays (hidden behind the menus).
var ui_visible: bool = true:
	set(value):
		ui_visible = value
		if _hud_layer != null:
			_hud_layer.visible = value
## Screenshot mode: no extrapolation, easing or effect ageing; the frame shows the sim state as is.
var frozen: bool = false:
	set(value):
		frozen = value
		if _effects != null:
			_effects.frozen = value
		if _kill_fx != null:
			_kill_fx.frozen = value
		if _species != null:
			_species.frozen = value

var _ground: Sprite2D
var _decals: DecalLayer
var _effects: EffectsLayer
var _enemy_layers: Array[SheetLayer] = []
var _tracers: SheetLayer
var _evo_tracers: SheetLayer  ## shots of evolved weapons (Ammo.EVO_BIT): gatling streaks, grinder slugs, giant shells
var _acid: SheetLayer
var _halos: Node2D
var _boss_view: BossView  ## boss bodies, telegraphs and moments (the HUD reads its moment ticks: boss_view())
var _combat: CombatFx
var _kill_fx: KillFx
var _species: SpeciesFx
## Kill combo of the watched rig and the hive surge warning (read by the HUD).
var juice: JuiceState = JuiceState.new()
var _labels: Node2D
var _camera: Camera2D
var _hud: Hud
var rules_live: RulesLive  ## live rule monitor on the right edge (combat, L toggles)
var minimap: Minimap
var rig_status: RigStatus  ## the watched rig's guns and active effects (left edge)
var ranges: RangeOverlay  ## weapon range rings around the watched rig (R)
var _hud_layer: CanvasLayer
var workshop: WorkshopUi
var game_over: GameOverUi
var rules: DoctrineEditor  ## the rule editor (P), on top of the workshop
var _cam_lift: float = 0.0
var _shake: float = 0.0  ## 0..1, screen shake from rigs blowing up (decays; never in screenshot mode)
var _shake_t: float = 0.0
var _ring: Node2D
var zones: ZoneView  ## PvP control zones on the ground (beacons, stakes, capture arcs)
## world.tick at which PvP last switched on (-1 = not seen): the HUD's "PVP ON" banner.
var pvp_on_tick: int = -1
var _pvp_prev: bool = false
## Match log for the information UI (kill feed, workshop recap), filled from world events once per
## sim tick (and by prime() in screenshot mode), so it works the same on host and clients:
## kill_log: player kills {tick, round, killer, victim, weapon}; wreck_log: rigs destroyed
## {tick, round, id, cause, killer}; drain_log: fuel drained at a workshop {tick, round, id, amount}.
var kill_log: Array[Dictionary] = []
var wreck_log: Array[Dictionary] = []
var drain_log: Array[Dictionary] = []
## PvP control zones (sim/zones.gd events): captures and the zone king bonus, for the feed and the recap.
var zone_log: Array[Dictionary] = []
var zones_open_tick: int = -1  ## tick of the last "zones_open" (the HUD's CONTROL ZONES OPEN banner)
const LOG_CAP := 96
## Spectator mode (local rig eliminated): vehicle id picked with Tab / arrows (-1 = auto: the
## nearest fight, else the leader). The auto choice is re-evaluated every SPECTATE_RECHECK ticks.
var spectate_id: int = -1
const SPECTATE_RECHECK := 90
const ELIM_HOLD_TICKS := 90  ## after the local rig is eliminated: 3 s on the wreck before spectating
const FIGHT_DIST := 300.0
var _auto_id: int = -1
var _auto_tick: int = -100000

var _vehicle_nodes: Dictionary = {}  # vehicle id -> RigView
var _veh_disp: Dictionary = {}  # vehicle id -> Vector3(x, y, heading)
var _veh_trail: Dictionary = {}  # vehicle id -> [position, wheel positions...] at the last track stamp
var _veh_steps: Dictionary = {}  # vehicle id -> int, track stamps so far (dust cadence)
var _enemy_disp: Dictionary = {}  # enemy id -> Vector3(x, y, frame)
var _acid_pos: PackedVector2Array = PackedVector2Array()
var _burn_start: Dictionary = {}  ## enemy id -> tick it caught fire (fresh ignitions flare: napalm spreading)
var _owner_mask: Dictionary = {}  ## vehicle id -> ammo bits loaded (client fallback for tracer colours)
var _rings: Array = []  ## expanding rings from events: [pos, radius px, born tick, life ticks, colour]
var _decoys: Dictionary = {}  ## vehicle id -> RigView, the faint phantom decoy copy
var _last_tick: int = -1
var _tick_age: float = 0.0
var _chain_from: Vector2 = Vector2.ZERO  ## thunderclap: where the last chain bolt started
## Aliens hit this tick flash white for that tick: Vector2i cell (HIT_CELL px) -> hit positions,
## each hit registered in its cell and the 8 around it. Empty in screenshot mode.
var _hit_cells: Dictionary = {}
const HIT_CELL := 24.0
const HITS_PER_TICK := 96
const HIT_FLASH := 0.85
## Cannon shells in flight at the previous tick, Vector3(x, y, owner): a "hit" next to one is a cannon hit.
var _shells_prev: PackedVector3Array = PackedVector3Array()
## Weapon evolutions (render-detected): vehicle id -> RigArt.evo_mask last seen; a new bit is the moment a
## weapon evolved (workshop pick, or a snapshot that brings it). evo_flash: vehicle id -> [tick, kind index]
## of the latest one (CombatFx draws the flash, the hull glows). Earthshaker blasts of this tick (one per spot).
var _evo_masks: Dictionary = {}
var evo_flash: Dictionary = {}
const EVO_FLASH_TICKS := 40
var _quakes: PackedVector2Array = PackedVector2Array()
const QUAKE_SHAKE := 0.5


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground = Sprite2D.new()
	_ground.texture = Gfx.TEX_GROUND
	_ground.centered = false
	_ground.position = SimWorld.ARENA.position
	_ground.z_index = Gfx.Z_GROUND
	add_child(_ground)

	_decals = DecalLayer.new()
	_decals.z_index = Gfx.Z_DECALS
	add_child(_decals)

	_ring = Node2D.new()
	_ring.z_index = Gfx.Z_RING
	_ring.draw.connect(_draw_ring)
	add_child(_ring)

	zones = ZoneView.new()
	zones.view = self
	add_child(zones)

	var kinds: Array = [  # [texture, glow, rows, shadow offset, shadow alpha] per SimWorld enemy kind
		[Gfx.TEX_MITE, Gfx.TEX_MITE_GLOW, 2, Vector2(1, 2), 0.45],
		# boulders cast a longer, darker shadow so a pile reads as separate rocks (#12)
		[Gfx.TEX_BOULDER, Gfx.TEX_BOULDER_GLOW, 2, Vector2(4, 6), 0.62],
		[Gfx.TEX_SPITTER, Gfx.TEX_SPITTER_GLOW, 1, Vector2(2, 3), 0.45],
		# glass wings fly: no ground silhouette (SpeciesFx draws the soft shadow offset by GLASS_SHADOW_OFFSET), drawn over the rigs
		[Gfx.TEX_GLASS, Gfx.TEX_GLASS_GLOW, 4, Vector2.ZERO, 0.0, Gfx.Z_PROJECTILES],
		[Gfx.TEX_BROOD, Gfx.TEX_BROOD_GLOW, 4, Vector2(2, 3), 0.5],
		[Gfx.TEX_SHRIEKER, Gfx.TEX_SHRIEKER_GLOW, 2, Vector2(2, 3), 0.45],
	]
	_species = SpeciesFx.new()
	_species.view = self
	_species.frozen = frozen
	add_child(_species)
	for k in kinds:
		var layer := SheetLayer.new()
		add_child(layer)
		layer.setup(k[0], Gfx.ENEMY_DIRS, k[2], k[5] if k.size() > 5 else Gfx.Z_ENEMIES, k[1], k[3], 1.0, k[4])
		_enemy_layers.append(layer)

	_tracers = SheetLayer.new()
	add_child(_tracers)
	_tracers.setup(Gfx.TEX_TRACER, Gfx.FX_DIRS, Gfx.TRACER_ROWS, Gfx.Z_PROJECTILES, Gfx.TEX_TRACER_GLOW)
	_evo_tracers = SheetLayer.new()
	add_child(_evo_tracers)
	_evo_tracers.setup(Gfx.TEX_TRACER_EVO, Gfx.FX_DIRS, Gfx.EVO_TRACER_ROWS, Gfx.Z_PROJECTILES, Gfx.TEX_TRACER_EVO_GLOW, Vector2.ZERO, 0.9)
	_acid = SheetLayer.new()
	add_child(_acid)
	_acid.setup(Gfx.TEX_ACID, Gfx.FX_DIRS, 1, Gfx.Z_PROJECTILES, Gfx.TEX_ACID_GLOW)

	_halos = Node2D.new()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halos.material = add_mat
	_halos.z_index = Gfx.Z_GLOW
	_halos.draw.connect(_draw_halos)
	add_child(_halos)

	_effects = EffectsLayer.new()
	_effects.frozen = frozen
	add_child(_effects)

	_boss_view = BossView.new()
	_boss_view.view = self
	add_child(_boss_view)

	_combat = CombatFx.new()
	_combat.view = self
	add_child(_combat)

	_kill_fx = KillFx.new()
	_kill_fx.view = self
	_kill_fx.frozen = frozen
	add_child(_kill_fx)

	_labels = Node2D.new()
	_labels.z_index = Gfx.Z_LABELS
	_labels.draw.connect(_draw_labels)
	add_child(_labels)

	_camera = Camera2D.new()
	_camera.limit_left = int(SimWorld.ARENA.position.x)
	_camera.limit_top = int(SimWorld.ARENA.position.y)
	_camera.limit_right = int(SimWorld.ARENA.end.x)
	_camera.limit_bottom = int(SimWorld.ARENA.end.y)
	_camera.position = SimWorld.ARENA.get_center()
	add_child(_camera)
	_camera.make_current()

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.visible = ui_visible
	_hud_layer = hud_layer
	# The world renders into a 640x360 SubViewport (pixel exact, scaled up by whole pixels); the
	# HUD and overlays live on the full-resolution root canvas so their text stays crisp.
	if owner != null and owner.get_viewport() != get_viewport():
		owner.add_child.call_deferred(hud_layer)
	else:
		add_child(hud_layer)
	ranges = RangeOverlay.new()  # under the HUD panels
	ranges.view = self
	hud_layer.add_child(ranges)
	_hud = Hud.new()
	_hud.view = self
	hud_layer.add_child(_hud)
	minimap = Minimap.new()
	minimap.view = self
	hud_layer.add_child(minimap)
	rules_live = RulesLive.new()
	rules_live.view = self
	hud_layer.add_child(rules_live)
	rig_status = RigStatus.new()
	rig_status.view = self
	hud_layer.add_child(rig_status)
	workshop = WorkshopUi.new()
	workshop.view = self
	hud_layer.add_child(workshop)
	game_over = GameOverUi.new()
	game_over.view = self
	hud_layer.add_child(game_over)
	rules = DoctrineEditor.new()
	rules.send_command = func(cmd: Dictionary) -> void:
		if workshop.send_command.is_valid():
			workshop.send_command.call(cmd)
	hud_layer.add_child(rules)
	workshop.rules = rules
	rules.workshop = workshop


func hud() -> Hud:
	return _hud


## Viewport / HUD position of the world point `p`.
func to_screen(p: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform() * Gfx.snap(p)).floor()


## World position under `p`, a point in viewport / HUD units (the inverse of screen_pos).
func world_at(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p


## Shows `w` from the point of view of `peer` (camera, HUD). Clears all marks of a previous world.
func set_world(w: SimWorld, peer: int) -> void:
	world = w
	local_peer = peer
	_last_tick = w.tick if w != null else -1
	_tick_age = 0.0
	_enemy_disp.clear()
	_veh_disp.clear()
	_veh_trail.clear()
	_veh_steps.clear()
	for id in _vehicle_nodes:
		(_vehicle_nodes[id] as Node).queue_free()
	_vehicle_nodes.clear()
	_decals.clear()
	_effects.clear()
	_combat.clear()
	_kill_fx.clear()
	_boss_view.clear()
	_species.clear()
	zones.clear()
	juice.reset()
	_hit_cells.clear()
	_shells_prev.clear()
	_burn_start.clear()
	_evo_masks.clear()
	evo_flash.clear()
	_shake = 0.0
	pvp_on_tick = -1
	kill_log.clear()
	wreck_log.clear()
	drain_log.clear()
	zone_log.clear()
	zones_open_tick = -1
	spectate_id = -1
	_auto_id = -1
	_auto_tick = -100000
	_pvp_prev = w != null and w.pvp_enabled()
	_hud.world = w
	_hud.local_peer = peer
	workshop.world = w
	workshop.local_peer = peer
	game_over.world = w
	game_over.local_peer = peer
	rules.world = w
	rules.local_peer = peer
	rules.close()


## Snapshot of one tick for prime(): events plus vehicle poses (for tyre tracks).
static func record_tick(w: SimWorld) -> Dictionary:
	var veh: Array = []
	for v in w.vehicles:
		veh.append([v.id, v.pos, v.heading, v.alive, RigArt.evo_mask(v)])
	return {"tick": w.tick, "round": w.round, "events": w.events.duplicate(), "vehicles": veh, "pvp": w.pvp_enabled(),
		"shells": cannon_shells(w)}


## Cannon shells in flight, Vector3(x, y, owner vehicle id). The host knows each shot's weapon; a client
## tells shells by their speed.
static func cannon_shells(w: SimWorld) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cannon: int = Cards.weapon_kind_index("cannon")
	var speed: float = float(Cards.WEAPONS["cannon"]["speed"])
	var host: bool = w.proj_weapon.size() >= w.proj_count
	for i in w.proj_count:
		var o: int = w.proj_owner[i]
		if o < 0:
			continue
		if (w.proj_weapon[i] == cannon) if host else absf(w.proj_vel[i].length() - speed) < 4.0:
			out.append(Vector3(w.proj_pos[i].x, w.proj_pos[i].y, float(o)))
	return out


## Screenshot mode: replays recorded ticks so the frame shows the match's history (persistent goo,
## scorch and tracks from every tick, transient effects from the last few ticks at their age).
func prime(history: Array) -> void:
	if world == null or history.is_empty():
		return
	var last_tick: int = history[-1]["tick"]
	var was_pvp: bool = bool(history[0].get("pvp", false))
	_update_camera(1.0)  # kill bursts only spawn on screen
	for h: Dictionary in history:
		var pvp: bool = bool(h.get("pvp", false))
		if pvp and not was_pvp:
			pvp_on_tick = int(h["tick"])
		was_pvp = pvp
		var age: float = float(last_tick - int(h["tick"])) * SimWorld.DT
		for vd: Array in h["vehicles"]:
			if vd[3]:
				_trail(vd[0], vd[1], vd[2], age if age < EffectsLayer.LIFE[EffectsLayer.Kind.DUST] else -1.0)
			if vd.size() > 4:
				_note_evo(int(vd[0]), int(vd[4]), int(h["tick"]))
		_consume_events(h["events"], age, last_tick - int(h["tick"]) < SHOT_EFFECT_TICKS, int(h["tick"]), int(h.get("round", world.round)))
		_shells_prev = h.get("shells", PackedVector3Array())
	_last_tick = world.tick
	_veh_trail.clear()


func _process(delta: float) -> void:
	if world == null:
		return
	if world.tick != _last_tick:
		for v in world.vehicles:
			_note_evo(v.id, RigArt.evo_mask(v), world.tick)
		_consume_events(world.events, 0.0, true, world.tick, world.round)
		_shells_prev = cannon_shells(world)
		_last_tick = world.tick
		_tick_age = 0.0
		var pvp: bool = world.pvp_enabled()
		if pvp and not _pvp_prev:
			pvp_on_tick = world.tick
		_pvp_prev = pvp
	elif not frozen:
		_tick_age += delta
	var lead: float = 0.0 if frozen else minf(_tick_age, MAX_LEAD)
	var k: float = 1.0 if frozen else 1.0 - exp(-SMOOTH_RATE * delta)
	_update_vehicles(lead, k)
	_update_enemies(lead, k)
	_update_projectiles(lead)
	_combat.update(world)
	zones.update(world)
	_update_camera(1.0 if frozen else 1.0 - exp(-CAM_EASE * delta))
	if not frozen:
		_shake = maxf(0.0, _shake - delta * 2.2)
		_shake_t += delta
	_halos.queue_redraw()
	_labels.queue_redraw()
	_ring.queue_redraw()


# ---------------------------------------------------------------- vehicles

func _vehicle_display(v: SimVehicle) -> Vector3:
	var d: Variant = _veh_disp.get(v.id)
	return d if d != null else Vector3(v.pos.x, v.pos.y, v.heading)


func _update_vehicles(lead: float, k: float) -> void:
	var seen: Dictionary = {}
	for v in world.vehicles:
		seen[v.id] = true
		var target: Vector2 = v.pos + (v.vel * lead if v.alive else Vector2.ZERO)
		var d: Vector3 = _vehicle_display(v)
		var p := Vector2(d.x, d.y)
		var head: float = d.z
		if p.distance_to(target) > SNAP_DIST or not _veh_disp.has(v.id):
			p = target
			head = v.heading
		else:
			p = p.lerp(target, k)
			head = lerp_angle(head, v.heading, k)
		_veh_disp[v.id] = Vector3(p.x, p.y, head)

		var rv: RigView = _rig_node(v.id)
		rv.jitter = _jitter(v)
		rv.place(v, Gfx.snap(p), head, world.tick, frozen)
		rv.set_flash(maxf(_protect_flash(v), _evo_hull_flash(v)))
		_update_decoy(v, head)
		if v.alive:
			_trail(v.id, p, head, -1.0 if frozen else 0.0)
	for id in _vehicle_nodes.keys():
		if not seen.has(id):
			(_vehicle_nodes[id] as Node).queue_free()
			_vehicle_nodes.erase(id)
			_veh_disp.erase(id)
			if _decoys.has(id):
				(_decoys[id] as Node).queue_free()
				_decoys.erase(id)


## The RigView of vehicle `id`, created (and its sprite stack built) on first use; null for no such vehicle.
func _rig_node(id: int) -> RigView:
	var v: SimVehicle = _vehicle(id)
	if v == null:
		return null
	var rv: RigView = _vehicle_nodes.get(id)
	if rv == null:
		rv = RigView.new()
		add_child(rv)
		_vehicle_nodes[id] = rv
	rv.setup(v)
	return rv


## Phantom drive: a faint copy of the rig stands where the nitro was cast while the decoy lasts.
func _update_decoy(v: SimVehicle, head: float) -> void:
	var dv: RigView = _decoys.get(v.id)
	if v.decoy_ticks <= 0 or not v.alive:
		if dv != null:
			dv.visible = false
		return
	if dv == null:
		dv = RigView.new()
		add_child(dv)
		_decoys[v.id] = dv
	dv.visible = true
	dv.setup(v)
	var flick: bool = (world.tick / 2 + v.id) % 3 == 0
	dv.place(v, Gfx.snap(v.decoy_pos) + (Vector2(1, 0) if flick else Vector2.ZERO), head, world.tick, frozen)
	dv.modulate = Color(1.0, 0.86, 0.66, 0.22 if flick else 0.42)  # a warm, flickering ghost


## Per gun: 1 while a hot-loads barrel is jammed (it stutters).
func _jitter(v: SimVehicle) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not v.alive or float(v.tech_fx.get("jam", 0.0)) <= 0.0 or float(v.tech_fx.get("overheat", 0.0)) > 0.0:
		return out
	for w in v.weapons:
		out.append(1 if int(w.get("jam", 0)) > 0 else 0)
	return out


# ---------------------------------------------------------------- display state for CombatFx

## Boss bodies, telegraphs and moments (the HUD reads the moment ticks).
func boss_view() -> BossView:
	return _boss_view


## The RigView of vehicle `id` (null before its first frame).
func rig_view(id: int) -> RigView:
	return _vehicle_nodes.get(id)


func display(v: SimVehicle) -> Vector3:
	return _vehicle_display(v)


func display_pos(v: SimVehicle) -> Vector2:
	var d: Vector3 = _vehicle_display(v)
	return Gfx.snap(Vector2(d.x, d.y))


## A persistent ground mark: cell `col` of a one-row decal sheet with `cols` cells.
func stamp_decal(tex: Texture2D, cols: int, col: int, pos: Vector2) -> void:
	_decals.stamp(tex, cols, 1, col, 0, pos)


## Protection shimmer strength for this frame (third-party protection, respawn shields).
func _protect_flash(v: SimVehicle) -> float:
	if not v.alive or protect_ticks(v) <= 0:
		return 0.0
	var t: int = world.tick
	return 0.15 if (t / 3) % 2 == 0 else 0.0


## Ticks of damage protection left: PvP third-party protection plus any respawn/round-start shield
## the sim may add (read by name so render keeps working whichever field exists).
static func protect_ticks(v: SimVehicle) -> int:
	var n: int = v.protect_ticks
	for f: String in ["invuln_ticks", "spawn_protect_ticks", "shield_ticks"]:
		var x: Variant = v.get(f)
		if x != null:
			n = maxi(n, int(x))
	return n


## Tyre tracks (persistent) and dust puffs (transient, `dust_age` < 0 = none) behind the rear wheels.
func _trail(id: int, p: Vector2, head: float, dust_age: float) -> void:
	var last: Variant = _veh_trail.get(id)
	if last != null and p.distance_to(last[0]) < TRAIL_STEP:
		return
	var rot: float = head + PI / 2.0
	var cur: Array = [p]
	var rv: RigView = _vehicle_nodes.get(id)
	var foot: int = rv.foot if rv != null else 0
	for w: Vector2 in RigArt.REAR_WHEELS[foot]:
		cur.append(p + w.rotated(rot))
	_veh_trail[id] = cur
	if last == null or p.distance_to(last[0]) > SNAP_DIST:
		return
	var steps: int = int(_veh_steps.get(id, 0)) + 1
	_veh_steps[id] = steps
	for i in range(1, cur.size()):
		_decals.track(last[i], cur[i], _track_width(id))
		if dust_age >= 0.0 and steps % 3 == 0:
			_effects.spawn(EffectsLayer.Kind.DUST, cur[i] - Vector2.from_angle(head) * 4.0, 0.0, dust_age, steps * 31 + i)


# ---------------------------------------------------------------- enemies and projectiles

func _update_enemies(lead: float, k: float) -> void:
	var n: int = world.enemy_count
	for layer in _enemy_layers:
		layer.begin(n)
	_species.begin(n)
	var disp: Dictionary = {}
	_combat.begin_frame()
	var burn_n: int = world.enemy_burn_ticks.size()
	var stun_n: int = world.enemy_status.size()
	var fv: SimVehicle = focus_vehicle()
	var warn: bool = fv != null and float(fv.tech_fx.get("spit_warn", 0.0)) > 0.0
	# contract targets near the watched rig carry a banner (boulder / spitter contracts)
	var ckind: int = -1
	if fv != null and fv.alive and (fv.contract_kind == Salvage.K_BOULDERS or fv.contract_kind == Salvage.K_SPITTERS):
		ckind = SimWorld.BOULDER if fv.contract_kind == Salvage.K_BOULDERS else SimWorld.SPITTER
	var starts: Dictionary = {}
	for i in n:
		var id: int = world.enemy_id[i]
		var vel: Vector2 = world.enemy_vel[i]
		var target: Vector2 = world.enemy_pos[i] + vel * lead
		var prev: Variant = _enemy_disp.get(id)
		var p: Vector2 = target
		var frame: int = 0
		if prev != null:
			var pv: Vector3 = prev
			frame = int(pv.z)
			var old := Vector2(pv.x, pv.y)
			if old.distance_to(target) < SNAP_DIST:
				p = old.lerp(target, k)
		if vel.length_squared() > 4.0:
			frame = Gfx.frame_for_angle(vel.angle(), Gfx.ENEMY_DIRS)
		disp[id] = Vector3(p.x, p.y, frame)
		var kind: int = world.enemy_kind[i]
		if i < burn_n and world.enemy_burn_ticks[i] > 0:
			var st: int = int(_burn_start.get(id, world.tick - (SimWorld.BURN_TICKS - world.enemy_burn_ticks[i])))
			starts[id] = st
			var fresh: int = 1 if world.tick - st < 5 else 0
			_combat.burn_pos.append(Gfx.snap(p))
			_combat.burn_meta.append(mini(kind, 7) | (fresh << 3) | (id << 4))
		if i < stun_n and (world.enemy_status[i] & 255) > 0:
			_combat.stun_pos.append(Gfx.snap(p))
		if warn and kind == SimWorld.SPITTER and SimWorld.spit_warning(world.tick, id):
			_combat.warn_pos.append(Gfx.snap(p))
		if kind == ckind and _combat.target_pos.size() < CombatFx.CONTRACT_BANNERS and p.distance_squared_to(fv.pos) < 280.0 * 280.0:
			_combat.target_pos.append(Gfx.snap(p))
		if kind < _enemy_layers.size():
			var fl: float = 0.0
			if not _hit_cells.is_empty():
				fl = _hit_flash(world.enemy_pos[i], kind)
			var row: int = SpeciesFx.row_for(kind, id, world.tick)
			_enemy_layers[kind].add(p, frame, row, fl)
			if kind == SimWorld.GLASS:
				_species.add_glass_shadow(p, frame, row)
	_enemy_disp = disp
	_burn_start = starts
	for layer in _enemy_layers:
		layer.finish()
	_species.finish()


func _update_projectiles(lead: float) -> void:
	var n: int = world.proj_count
	_tracers.begin(n)
	_acid.begin(0)
	_acid_pos.clear()
	# The host knows each shot's ammo and weapon; a client falls back to the shooter's loaded ammo and
	# tells saws and flamer jets by their speed.
	var host: bool = world.proj_ammo.size() >= n and world.proj_weapon.size() >= n
	_owner_mask.clear()
	for v in world.vehicles:
		_owner_mask[v.id] = CombatFx.rig_mask(v)
	var flamer: int = Cards.weapon_kind_index("flamer")
	var flamer_speed: float = float(Cards.WEAPONS["flamer"]["speed"]) if Cards.WEAPONS.has("flamer") else 230.0
	_evo_tracers.begin(0)
	var evo_owner: Dictionary = {}  ## vehicle id -> evolved kinds bit mask (client fallback)
	for v in world.vehicles:
		var em: int = RigArt.evo_mask(v)
		if em != 0:
			evo_owner[v.id] = em
	for i in n:
		var vel: Vector2 = world.proj_vel[i]
		var p: Vector2 = world.proj_pos[i] + vel * lead
		var frame: int = Gfx.frame_for_angle(vel.angle(), Gfx.FX_DIRS)
		var owner: int = world.proj_owner[i]
		if owner >= 0:
			var weapon: int = world.proj_weapon[i] if host else 255
			var mask: int = world.proj_ammo[i] if host else int(_owner_mask.get(owner, 0))
			var spd: float = vel.length()
			if weapon == 255 and absf(spd - Salvage.SAW_SPEED) < 3.0 and (mask & Ammo.SHARD_BIT) == 0:
				_tracers.add(p, (world.tick + i * 5) % Gfx.FX_DIRS, Gfx.TRACER_SAW)
			elif (mask & Ammo.SHARD_BIT) != 0:
				_tracers.add(p, frame, Gfx.TRACER_SHARD)
			elif evo_owner.has(owner) and _evo_shot(i, host, spd, int(evo_owner[owner]), p, frame, vel):
				pass
			elif weapon == flamer or (not host and absf(spd - flamer_speed) < 4.0):
				_combat.flamer_pos.append(Gfx.snap(p))
			else:
				_tracers.add(p, frame, CombatFx.ammo_row(mask, i))
		elif not BossView.is_ring_shard(world, i):  # the Colossus' ring shards are drawn by BossView
			_acid.add(p, frame)
			_acid_pos.append(Gfx.snap(p))
	_tracers.finish()
	_evo_tracers.finish()
	_acid.finish()


## Draws projectile `i` as an evolved shot if it is one (host: Ammo.EVO_BIT and its weapon; client: the
## owner has an evolved gun of the kind its speed gives away). False = draw it as a normal shot.
func _evo_shot(i: int, host: bool, spd: float, owner_mask: int, p: Vector2, frame: int, vel: Vector2) -> bool:
	var ki: int = -1
	if host:
		if (world.proj_ammo[i] & Ammo.EVO_BIT) == 0:
			return false
		ki = world.proj_weapon[i]
	else:
		for k in Cards.WEAPON_KINDS.size():
			if (owner_mask >> k) & 1 and absf(spd - float(Cards.WEAPONS[Cards.WEAPON_KINDS[k]]["speed"])) < 4.0:
				ki = k
				break
	if ki < 0 or ki >= Cards.WEAPON_KINDS.size():
		return false
	match Cards.WEAPON_KINDS[ki]:
		"mg":
			_evo_tracers.add(p, frame, Gfx.EVO_GATLING)
		"shotgun":
			_evo_tracers.add(p, frame, Gfx.EVO_GRINDER)
			_combat.grinder_pos.append(Gfx.snap(p))
			_combat.grinder_dir.append(vel.normalized())
		"cannon":
			_evo_tracers.add(p, frame, Gfx.EVO_SHELL)
		"flamer":
			_combat.inferno_pos.append(Gfx.snap(p))
			_combat.inferno_dir.append(vel.normalized())
		_:
			return false
	return true


func _draw_halos() -> void:
	var s := Vector2(Gfx.TEX_HALO_CYAN.get_size())
	for p in _acid_pos:
		_halos.draw_texture_rect(Gfx.TEX_HALO_CYAN, Rect2(p - s / 2.0, s), false, Color(1, 1, 1, 0.6))
	# Burning enemies: a warm halo that flickers (tick-hash, no randomness); ember zones: a dim warm glow.
	var ws := Vector2(Gfx.TEX_HALO_WARM.get_size())
	for bi in _combat.burn_pos.size():
		if bi % 2 == 1 and _combat.burn_pos.size() > 12:  # a burning horde: half the halos, or it washes out
			continue
		var bp: Vector2 = _combat.burn_pos[bi]
		var fl: float = 0.18 + 0.08 * float((world.tick + bi * 5) % 4)
		_halos.draw_texture_rect(Gfx.TEX_HALO_WARM, Rect2(bp - ws / 2.0, ws), false, Color(1, 1, 1, fl))
	for zi in mini(world.zone_count, world.zone_pos.size()):
		if world.zone_kind[zi] != SimWorld.ZONE_EMBER and world.zone_kind[zi] != SimWorld.ZONE_FIRE:
			continue
		var zr: float = world.zone_radius[zi] * 2.0
		var zk := Vector2(zr, zr)
		var za: float = clampf(float(world.zone_ttl[zi]) / 30.0, 0.0, 1.0) * 0.2
		_halos.draw_texture_rect(Gfx.TEX_HALO_WARM_BIG, Rect2(Gfx.snap(world.zone_pos[zi]) - zk / 2.0, zk), false, Color(1, 1, 1, za))
	for wp in _combat.warn_pos:  # spitter about to spit: a warm warning glow
		_halos.draw_texture_rect(Gfx.TEX_HALO_WARM, Rect2(wp - ws / 2.0, ws), false, Color(1, 0.5, 0.35, 0.45 if (world.tick / 3) % 2 == 0 else 0.2))


## HIT_FLASH when a hit of this tick landed on the alien at sim position `p`, else 0.
func _hit_flash(p: Vector2, kind: int) -> float:
	var hits: Variant = _hit_cells.get(Vector2i(floori(p.x / HIT_CELL), floori(p.y / HIT_CELL)))
	if hits == null:
		return 0.0
	var r: float = SimWorld.ENEMY_RADIUS[kind] + 5.0
	for q: Vector2 in (hits as PackedVector2Array):
		if q.distance_squared_to(p) <= r * r:
			return HIT_FLASH
	return 0.0


func _register_hit(pos: Vector2) -> void:
	var c := Vector2i(floori(pos.x / HIT_CELL), floori(pos.y / HIT_CELL))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dy)
			var arr: PackedVector2Array = _hit_cells.get(k, PackedVector2Array())
			arr.append(pos)
			_hit_cells[k] = arr


## A "hit" by `owner` at `pos` right next to one of its cannon shells of the previous tick.
func _cannon_hit(owner: int, pos: Vector2) -> bool:
	var reach: float = float(Cards.WEAPONS["cannon"]["speed"]) * SimWorld.DT * 1.5 + 20.0
	for s: Vector3 in _shells_prev:
		if int(s.z) == owner and Vector2(s.x, s.y).distance_squared_to(pos) <= reach * reach:
			return true
	return false


# ---------------------------------------------------------------- events

func _consume_events(events: Array, age: float, transient: bool, tick: int = -1, rnd: int = 0) -> void:
	_kill_fx.begin_tick()
	_hit_cells.clear()
	_quakes.clear()
	var hits: int = 0
	var fv0: SimVehicle = focus_vehicle()
	juice.set_focus(fv0.id if fv0 != null else -1)
	for e: Dictionary in events:
		_log_event(e, tick, rnd)
		zones.note_event(e, tick)
		if transient and str(e.get("type", "")) == "zone_bonus":
			_zone_king_toast(e)
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var owner: int = int(e.get("owner", -1))
		var kind: int = int(e.get("kind", -1))
		var h: int = Gfx.hash_pos(pos, owner + 7)
		var type: String = str(e.get("type", ""))
		match type:
			"emp":
				if transient:
					_effects.spawn(EffectsLayer.Kind.EMP, pos, 0.0, age, h, Abilities.EMP_RADIUS)
			"boom":  # turbine boom: a dust and fire shockwave off the exhaust
				if transient:
					_effects.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, Mobility.BOOM_RADIUS)
					_effects.spawn(EffectsLayer.Kind.SPARK_BURST, pos, 0.0, age, h, 16.0)
			"sparks":  # ram bumper / thermite
				if transient:
					_effects.spawn(EffectsLayer.Kind.SPARK_BURST, pos, 0.0, age, h, Mobility.SPARKS_RADIUS)
					_effects.spawn(EffectsLayer.Kind.SPARKS, pos, float(h % 628) / 100.0, age, h)
			"nitro":
				if transient:
					var nv: SimVehicle = _vehicle(owner)
					var nrv: RigView = _vehicle_nodes.get(owner) if nv != null else null
					if nrv != null:
						for ex: Vector2 in nrv.exhausts():
							_effects.spawn(EffectsLayer.Kind.SOOT if kind == 1 else EffectsLayer.Kind.FLARE, ex, 0.0, age, h)
					if kind == 1:
						_effects.spawn(EffectsLayer.Kind.SOOT, pos, 0.0, age, h + 3)
			"shockwave":  # war machine
				if transient:
					_effects.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, Fusions.WAR_RADIUS)
					_effects.spawn(EffectsLayer.Kind.DUST, pos, 0.0, age, h)
			"jerry_blast":  # the jerrycans go up with the rig
				if transient:
					_effects.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, Salvage.JERRY_RADIUS)
					for i in 3:
						var jo := Vector2.from_angle(float(i) * 2.1 + float(h % 7)) * 14.0
						_effects.spawn(EffectsLayer.Kind.EXPLOSION, pos + jo, 0.0, age + 0.05 * float(i), h + i)
						_effects.spawn(EffectsLayer.Kind.FLARE, pos + jo * 1.4, 0.0, age + 0.1, h + 7 + i)
			"chain":  # thunderclap: a crackling stun ring, then bolts jumping to the next aliens
				if kind == 0:
					_chain_from = pos
					if transient:
						_effects.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 1, Fusions.CLAP_RADIUS)
				elif transient:
					_effects.spawn(EffectsLayer.Kind.BOLT, _chain_from, 0.0, age, h, pos)
					_chain_from = pos
			"saw":
				_add_ring(pos, 14.0, tick, 6, Gfx.STEEL[4])
			"contract_done":
				_add_ring(pos, 30.0, tick, 14, Gfx.FIRE[5])
			"smoke":
				if transient:
					for i in 4:
						_effects.spawn(EffectsLayer.Kind.STEAM, pos + Vector2.from_angle(float(i) * 1.57) * 8.0, 0.0, age, h + i)
			"salvo":
				_add_ring(pos, 30.0, tick, 10, Gfx.FIRE[5])
			"dodge":
				if transient:
					var dv: SimVehicle = _vehicle(owner)
					_effects.spawn(EffectsLayer.Kind.DODGE, pos, (dv.heading if dv != null else 0.0) + PI / 2.0, age, h)
			"shrapnel":
				if transient:
					_effects.spawn(EffectsLayer.Kind.SHARDS, pos, 0.0, age, h)
			"execute":  # one shot, one kill: the KILL pop and a small camera kick
				if transient:
					_effects.spawn(EffectsLayer.Kind.KILL, pos, 0.0, age, h)
					_effects.spawn(EffectsLayer.Kind.AP_FLASH, pos, float(h % 628) / 100.0, age, h)
					var fv: SimVehicle = focus_vehicle()
					if age < 0.05 and not frozen and fv != null and fv.id == owner:
						_shake = maxf(_shake, 0.45)
			"jam", "overheat":
				if transient:
					_effects.spawn(EffectsLayer.Kind.SOOT if type == "jam" else EffectsLayer.Kind.STEAM, pos, 0.0, age, h)
					_effects.spawn(EffectsLayer.Kind.SPARKS, pos, float(h % 628) / 100.0, age, h)
			"shed":  # scrap armour: a plate flies off
				if transient:
					_effects.spawn(EffectsLayer.Kind.DEBRIS, pos, 0.0, age, h)
			"fire":
				var frv: RigView = _rig_node(owner)
				if frv != null:
					frv.note_fire(kind, tick if tick >= 0 else world.tick)
				if transient:
					_muzzle_flash(owner, pos, kind, age, h)
			"hit":
				var heavy: bool = owner >= 0 and _cannon_hit(owner, pos)
				if heavy and _evolved(owner, "cannon"):  # the earthshaker's shell: a blast and a scorch mark
					_earthshake(pos, age, h, transient)
				if transient:
					var ang: float = float(h % 628) / 100.0
					if owner < 0:  # acid splashing on a rig
						_effects.spawn(EffectsLayer.Kind.ICHOR, pos, ang, age, h)
					else:
						_impact(owner, pos, age, h, heavy)
						if kind >= 0 and not frozen and hits < HITS_PER_TICK:
							hits += 1
							_register_hit(pos)
			"boss", "boss_spawn", "boss_phase", "boss_split", "boss_kill", "boss_retreat", "boss_shell", "boss_blast", "boss_ring", \
					"boss_charge", "boss_brood":
				_boss_view.on_event(type, e, age, transient, tick if tick >= 0 else world.tick)
			"shriek", "brood":  # a shrieker's buff ring; a brood carrier's burst frame
				if transient:
					_species.on_event(e, age)
					if type == "brood" and kind == 0:  # burned or blasted: the brood dies with it, a puff of flame instead of mites
						_effects.spawn(EffectsLayer.Kind.FIRE_PUFF, pos, 0.0, age, h)
			"surge":  # the hive surges in `in_ticks`: the HUD's SWARM INCOMING banner
				juice.on_surge(tick if tick >= 0 else world.tick, int(e.get("in_ticks", JuiceState.SURGE_DEFAULT_TICKS)))
			"kill":
				if kind >= SimWorld.BOSS_A:  # boss bodies: their own bursts and carcasses (BossView)
					_boss_view.on_event(type, e, age, transient, tick if tick >= 0 else world.tick)
					continue
				if kind < 0:
					continue  # player kill: the wreck comes from "vehicle_destroyed", no alien goo
				_kill_decal(pos, kind, h)
				juice.on_kill(owner, tick if tick >= 0 else world.tick)
				if transient and _on_screen(pos) and _kill_fx.burst(kind, pos, age, h + 1):
					if kind == SimWorld.BOULDER:  # a cracked shell: a dust ring and a light jolt
						_effects.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, 20.0)
						if age < 0.05 and not frozen:
							_shake = maxf(_shake, 0.42)
					if owner >= 0 and owner == juice.focus_id:
						_kill_fx.scrap(pos, SimWorld.ENEMY_SCRAP[kind], age, h)
			"vehicle_destroyed":  # a rig goes up: big blast, flying scrap, shake (#11)
				_decals.stamp(Gfx.TEX_SCORCH, 2, 1, h % 2, 0, pos)
				for i in 3:
					var off := Vector2(float((h >> (i * 4)) % 33 - 16), float((h >> (i * 4 + 2)) % 25 - 12))
					_decals.stamp(Gfx.TEX_WRECK, 4, 1, (h + i) % 4, 0, pos + off)
				if transient:
					_effects.spawn(EffectsLayer.Kind.EXPLOSION_BIG, pos, 0.0, age, h)
					_effects.spawn(EffectsLayer.Kind.DEBRIS, pos, 0.0, age, h + 5)
					for i in 3:
						_effects.spawn(EffectsLayer.Kind.SPARKS, pos, float(i) * 2.1, age, h + 3 + i)
					_effects.spawn(EffectsLayer.Kind.EXPLOSION, pos + Vector2(9, -6), 0.0, age + 0.12, h + 9)
					if age < 0.05 and not frozen and _on_screen(pos):
						_shake = 1.0


## Books kills, wrecks, fuel drains and zone captures for the UI (feed, recap). `tick` / `rnd`: when it happened.
func _log_event(e: Dictionary, tick: int, rnd: int) -> void:
	var type: String = str(e.get("type", ""))
	var log: Array[Dictionary]
	var entry: Dictionary = {"tick": tick, "round": rnd}
	match type:
		"kill":
			if int(e.get("kind", 0)) >= 0 or not e.has("victim"):
				return
			entry.merge({"killer": int(e.get("owner", -1)), "victim": int(e["victim"]), "weapon": int(e.get("weapon", -1))})
			log = kill_log
		"vehicle_destroyed":
			entry.merge({"id": int(e.get("owner", -1)), "cause": int(e.get("cause", -1)), "killer": int(e.get("killer", -1)), "pos": e.get("pos", Vector2.ZERO)})
			log = wreck_log
		"drain":
			entry.merge({"id": int(e.get("owner", -1)), "amount": int(e.get("kind", 0))})
			log = drain_log
		"zone_captured":
			entry.merge({"type": "captured", "owner": int(e.get("owner", -1)), "zone": int(e.get("kind", -1)), "prev": int(e.get("prev", -1))})
			log = zone_log
		"zone_bonus":
			entry.merge({"type": "bonus", "owner": int(e.get("owner", -1)), "fuel": int(e.get("kind", 0))})
			log = zone_log
		"zones_open":
			zones_open_tick = tick
			return
		_:
			return
	log.append(entry)
	if log.size() > LOG_CAP:
		log.remove_at(0)


# ---------------------------------------------------------------- weapon evolutions

## Vehicle `id` shows evolved-kind bits `mask` at `tick`: a bit that was not there before is the moment a
## weapon evolved. The first sighting of a rig (joining, a new world) only records.
func _note_evo(id: int, mask: int, tick: int) -> void:
	var prev: int = int(_evo_masks.get(id, -1))
	_evo_masks[id] = mask
	if prev < 0:
		return
	var fresh: int = mask & ~prev
	for k in Cards.WEAPON_KINDS.size():
		if (fresh >> k) & 1:
			_evolve(id, k, tick)


## The flash on the rig (CombatFx and the hull glow read evo_flash) and, for the watched rig, the banner.
func _evolve(id: int, k: int, tick: int) -> void:
	evo_flash[id] = [tick, k]
	var kind: String = Cards.WEAPON_KINDS[k]
	var card: String = RigArt.evolution_card(kind)
	var d: Dictionary = Cards.def(card)
	var sub: String = "%s + %s" % [UiKit.card_name(kind), UiKit.card_name(str(d.get("partner", "")))]
	var fv: SimVehicle = focus_vehicle()
	juice.set_focus(fv.id if fv != null else -1)
	juice.on_evolve(id, tick, kind, UiKit.card_name(card), sub)
	var v: SimVehicle = _vehicle(id)
	var age: float = float(world.tick - tick) * SimWorld.DT
	if v != null and v.alive and age < 1.0:  # a burst of sparks, a dust ring and flares off the new gun
		var p: Vector2 = display_pos(v) if _veh_disp.has(id) else v.pos
		var h: int = Gfx.hash_pos(p, id + 41)
		_effects.spawn(EffectsLayer.Kind.SHOCK, p, 0.0, age, 0, 56.0)
		_effects.spawn(EffectsLayer.Kind.SPARK_BURST, p, 0.0, age, h, 40.0)
		_effects.spawn(EffectsLayer.Kind.SPARK_BURST, p, 0.0, age + 0.08, h + 1, 26.0)
		for i in 3:
			_effects.spawn(EffectsLayer.Kind.FLARE, p + Vector2.from_angle(float(i) * 2.1 + 0.4) * 9.0, 0.0, age + 0.05 * float(i), h + 2 + i)


## Age in ticks of vehicle `id`'s evolution flash (-1 = none).
func evo_flash_age(id: int) -> int:
	var f: Variant = evo_flash.get(id)
	if f == null or world == null:
		return -1
	var a: int = world.tick - int(f[0])
	return a if a >= 0 and a < EVO_FLASH_TICKS else -1


## The hull lights up warm white as the weapon evolves, then pulses out.
func _evo_hull_flash(v: SimVehicle) -> float:
	var a: int = evo_flash_age(v.id)
	if a < 0 or not v.alive:
		return 0.0
	if a < 3:
		return 0.8
	return maxf(0.0, 1.0 - float(a) / 24.0) * (0.15 + 0.2 * float((a / 3) % 2))


## True if vehicle `id` has an evolved gun of weapon kind `kind`.
func _evolved(id: int, kind: String) -> bool:
	var v: SimVehicle = _vehicle(id)
	return v != null and (RigArt.evo_mask(v) >> Cards.weapon_kind_index(kind)) & 1 == 1


## An earthshaker shell lands: a big fireball, a dust shockwave the size of its splash, flung sparks, a
## scorch mark and a light camera jolt. One per spot and tick (pierce and splash report several hits).
func _earthshake(pos: Vector2, age: float, h: int, transient: bool) -> void:
	for q in _quakes:
		if q.distance_squared_to(pos) < 40.0 * 40.0:
			return
	_quakes.append(pos)
	_decals.stamp(Gfx.TEX_BURN, 4, 1, h % 4, 0, pos)
	_decals.stamp(Gfx.TEX_BURN, 4, 1, (h / 4) % 4, 0, pos + Vector2(float(h % 9) - 4.0, float((h / 9) % 7) - 3.0))
	if not transient:
		return
	_effects.spawn(EffectsLayer.Kind.EXPLOSION_BIG, pos, 0.0, age, h)
	_effects.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, float(Cards.EVOLVED["cannon"]["splash"]))
	_effects.spawn(EffectsLayer.Kind.SPARK_BURST, pos, 0.0, age, h + 1, 26.0)
	_effects.spawn(EffectsLayer.Kind.DUST, pos, 0.0, age + 0.1, h + 2)
	if age < 0.05 and not frozen and _on_screen(pos):
		_shake = maxf(_shake, QUAKE_SHAKE)


## An expanding ring of `radius` px that fades over `life` ticks (EMP, boom, sparks, ability casts).
func _add_ring(pos: Vector2, radius: float, tick: int, life: int, col: Color) -> void:
	if _rings.size() < 32:
		_rings.append([pos, radius, tick if tick >= 0 else world.tick, life, col])


func _vehicle(id: int) -> SimVehicle:
	return world.vehicles[id] if id >= 0 and id < world.vehicles.size() else null


## The muzzle flash of the gun that fired, in its ammo's colour; mixed belts flash two-tone.
func _muzzle_flash(vehicle_id: int, muzzle: Vector2, kind: int, age: float, h: int = 0) -> void:
	var v: SimVehicle = _vehicle(vehicle_id)
	if v == null:
		return
	var rv: RigView = _vehicle_nodes.get(v.id)
	if rv == null:
		return
	# Put the flash on the drawn barrel tip of that gun rather than the sim's muzzle point.
	var m: Array = rv.muzzle(kind, (muzzle - v.pos).angle())
	var kname: String = Cards.WEAPON_KINDS[kind] if kind >= 0 and kind < Cards.WEAPON_KINDS.size() else "mg"
	var mask: int = Ammo.mask(v, kname)
	var rows: PackedInt32Array = CombatFx.ammo_rows(mask)
	var first: int = (h / 3) % 2
	_effects.spawn(EffectsLayer.Kind.MUZZLE, m[0], m[1], age, rows[first])
	if rows[0] != rows[1]:  # two-tone: the other belt's colour just ahead of it
		_effects.spawn(EffectsLayer.Kind.MUZZLE, m[0] + Vector2.from_angle(m[1]) * 3.0, m[1], age, rows[1 - first])
	if kind == Cards.weapon_kind_index("cannon"):  # the cannon kicks: back-sparks, a muzzle flare and a smoke puff
		_effects.spawn(EffectsLayer.Kind.SPARKS, m[0], m[1] + PI, age, Gfx.hash_pos(m[0], 3))
		_effects.spawn(EffectsLayer.Kind.FLARE, m[0] + Vector2.from_angle(m[1]) * 2.0, m[1], age, h)
		_effects.spawn(EffectsLayer.Kind.STEAM, m[0] + Vector2.from_angle(m[1]) * 4.0, 0.0, age + 0.15, h)
	if (RigArt.evo_mask(v) >> kind) & 1:  # evolved guns: a bigger bark
		var fwd: Vector2 = Vector2.from_angle(m[1])
		match kname:
			"mg":  # the gatling's flash is a long double tongue
				_effects.spawn(EffectsLayer.Kind.MUZZLE, m[0] + fwd * 4.0, m[1], age, rows[1 - first])
			"shotgun":  # the grinder spits a cone of sparks
				_effects.spawn(EffectsLayer.Kind.SPARKS, m[0] + fwd * 3.0, m[1], age, h + 1)
				_effects.spawn(EffectsLayer.Kind.SPARKS, m[0] + fwd * 3.0, m[1] + 0.3, age, h + 2)
				_effects.spawn(EffectsLayer.Kind.MUZZLE, m[0] + fwd * 4.0, m[1], age, rows[first])
			"cannon":  # the earthshaker: a blast ring off the brake and smoke both ways
				_effects.spawn(EffectsLayer.Kind.SHOCK, m[0] + fwd * 3.0, 0.0, age, 0, 12.0)
				_effects.spawn(EffectsLayer.Kind.EXPLOSION, m[0] + fwd * 6.0, 0.0, age + 0.25, h)
				_effects.spawn(EffectsLayer.Kind.STEAM, m[0] - fwd * 3.0 + fwd.orthogonal() * 5.0, 0.0, age + 0.1, h + 3)
				_effects.spawn(EffectsLayer.Kind.STEAM, m[0] - fwd * 3.0 - fwd.orthogonal() * 5.0, 0.0, age + 0.1, h + 4)


## A shot landing: plain sparks, an incendiary flame lick, a shrapnel spray or an armour-piercing flash;
## a cannon shell (`heavy`) also lands with a hard white-hot flash.
func _impact(owner: int, pos: Vector2, age: float, h: int, heavy: bool = false) -> void:
	var v: SimVehicle = _vehicle(owner)
	var ang: float = float(h % 628) / 100.0
	var row: int = CombatFx.ammo_row(CombatFx.rig_mask(v), h / 5) if v != null else Gfx.TRACER_PLAIN
	if v != null:
		ang = (v.pos - pos).angle()  # sparks fly back toward the shooter
	if heavy:
		_effects.spawn(EffectsLayer.Kind.IMPACT_HEAVY, pos, ang, age, h)
	match row:
		Gfx.TRACER_FIRE:
			_effects.spawn(EffectsLayer.Kind.FIRE_PUFF, pos, ang, age, h)
		Gfx.TRACER_SHRAPNEL:
			_effects.spawn(EffectsLayer.Kind.SPARKS, pos, ang, age, h)
			_effects.spawn(EffectsLayer.Kind.SPARKS, pos, ang + 0.8, age, h + 1)
		Gfx.TRACER_AP:
			_effects.spawn(EffectsLayer.Kind.AP_FLASH, pos, ang + PI, age, h)
		_:
			_effects.spawn(EffectsLayer.Kind.SPARKS, pos, ang, age, h)


func _track_width(id: int) -> float:
	if id >= 0 and id < world.vehicles.size() and RigArt.uses_tracks(world.vehicles[id]):
		return 5.0
	return 3.0


func _kill_decal(pos: Vector2, kind: int, h: int) -> void:
	match kind:
		SimWorld.BOULDER:
			_decals.stamp(Gfx.TEX_GOO_BIG, 2, 1, h % 2, 0, pos)
		SimWorld.SPITTER:
			_decals.stamp(Gfx.TEX_GOO, 4, 1, 3, 0, pos)
			_decals.stamp(Gfx.TEX_GOO, 4, 1, h % 3, 0, pos + Vector2(4, -3))
		SimWorld.GLASS:  # bleached wing husks, no goo
			_decals.stamp(Gfx.TEX_CARCASS_WINGS, 2, 1, h % 2, 0, pos)
		SimWorld.BROOD:
			_decals.stamp(Gfx.TEX_GOO_BIG, 2, 1, h % 2, 0, pos)
			_decals.stamp(Gfx.TEX_CARCASS_BROOD, 2, 1, (h / 3) % 2, 0, pos)
		SimWorld.SHRIEKER:
			_decals.stamp(Gfx.TEX_GOO, 4, 1, h % 3, 0, pos + Vector2(3, 2))
			_decals.stamp(Gfx.TEX_CARCASS_SHRIEKER, 2, 1, (h / 5) % 2, 0, pos)
		_:
			_decals.stamp(Gfx.TEX_GOO, 4, 1, h % 4, 0, pos)
			if h % 10 < 6:
				_decals.stamp(Gfx.TEX_CARCASS, 4, 1, (h / 7) % 4, 0, pos + Vector2(h % 3 - 1, (h / 3) % 3 - 1))


# ---------------------------------------------------------------- camera and labels

func _on_screen(p: Vector2) -> bool:
	var half: Vector2 = get_viewport_rect().size / 2.0
	return Rect2(_camera.position - half, half * 2.0).grow(24.0).has_point(p)


## Where the local rig (or the spectated one) is drawn, in viewport pixels (UI vignettes centre on it).
func local_screen_pos() -> Vector2:
	var vs: Vector2 = get_viewport_rect().size
	if world == null:
		return vs / 2.0
	var v: SimVehicle = focus_vehicle()
	if v == null:
		return vs / 2.0
	return screen_pos(v)


## Collision radius of `v`'s drawn rig (buggy or truck footprint), in pixels.
func rig_radius(v: SimVehicle) -> float:
	var rv: RigView = _vehicle_nodes.get(v.id)
	return RigArt.RADIUS[rv.foot if rv != null else 0]


## Where vehicle `v` is drawn, in viewport pixels (may be off-screen).
func screen_pos(v: SimVehicle) -> Vector2:
	var d: Vector3 = _vehicle_display(v)
	return (get_viewport().get_canvas_transform() * Gfx.snap(Vector2(d.x, d.y))).floor()


# ---------------------------------------------------------------- spectator

## True while the local rig is eliminated and the match goes on with others (spectator mode). The
## camera stays on the wreck for ELIM_HOLD_TICKS first (the HUD shows ELIMINATED meanwhile).
func spectating() -> bool:
	if world == null or attract or world.phase == SimWorld.PHASE_GAME_OVER:
		return false
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer)
	if me == null or not me.eliminated or spectate_candidates().is_empty():
		return false
	return world.tick - last_wreck_tick(me.id) >= ELIM_HOLD_TICKS


## Tick of the latest "vehicle_destroyed" of vehicle `id` seen (very old if none).
## Fuel vehicle `id` got as zone king at the end of round `rnd` (0 = none), from the zone log.
func zone_bonus_for(id: int, rnd: int) -> int:
	for i in range(zone_log.size() - 1, -1, -1):
		var e: Dictionary = zone_log[i]
		if str(e["type"]) == "bonus" and int(e["owner"]) == id and int(e["round"]) == rnd:
			return int(e["fuel"])
	return 0


## The round's best zone holder gets fuel as the workshop opens: a toast there.
func _zone_king_toast(e: Dictionary) -> void:
	var v: SimVehicle = _vehicle(int(e.get("owner", -1)))
	if v == null or workshop == null:
		return
	var fuel: int = int(e.get("kind", 0))
	if v.peer_id == local_peer:
		workshop.say("ZONE KING - YOU HELD THE MOST GROUND: +%d FUEL" % fuel)
	else:
		workshop.say("%s IS ZONE KING: +%d FUEL" % [UiKit.player_name(v), fuel])


func last_wreck_tick(id: int) -> int:
	for i in range(wreck_log.size() - 1, -1, -1):
		if int(wreck_log[i]["id"]) == id:
			return int(wreck_log[i]["tick"])
	return -(1 << 30)


## Rigs still in the game, other than the local one (in vehicle order).
func spectate_candidates() -> Array[SimVehicle]:
	var out: Array[SimVehicle] = []
	if world == null:
		return out
	for v in world.vehicles:
		if not v.eliminated and v.peer_id != local_peer:
			out.append(v)
	return out


## The rig the camera follows: the local one, or the spectated one when eliminated.
func focus_vehicle() -> SimVehicle:
	if world == null:
		return null
	if spectating():
		return spectated()
	return world.get_vehicle_for_peer(local_peer)


## The rig being watched in spectator mode (manual pick, else the auto choice).
func spectated() -> SimVehicle:
	var cands: Array[SimVehicle] = spectate_candidates()
	if cands.is_empty():
		return null
	for v in cands:
		if v.id == spectate_id:
			return v
	spectate_id = -1
	var cur: SimVehicle = null
	for v in cands:
		if v.id == _auto_id:
			cur = v
	if cur == null or absi(world.tick - _auto_tick) >= SPECTATE_RECHECK:
		cur = _auto_pick(cands)
		_auto_id = cur.id
		_auto_tick = world.tick
	return cur


## Auto camera: one side of the closest rival pair within FIGHT_DIST (the leader, else the higher
## score), else the bounty leader, else the best score.
func _auto_pick(cands: Array[SimVehicle]) -> SimVehicle:
	var best_d: float = FIGHT_DIST
	var pair: Array[SimVehicle] = []
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			var a: SimVehicle = cands[i]
			var b: SimVehicle = cands[j]
			if not a.alive or not b.alive:
				continue
			var d: float = a.pos.distance_to(b.pos)
			if d < best_d:
				best_d = d
				pair = [a, b]
	var pool: Array[SimVehicle] = pair if not pair.is_empty() else cands
	var top: SimVehicle = pool[0]
	for v in pool:
		if v.peer_id == world.leader_peer:
			return v
		if world.leader_score(v) > world.leader_score(top):
			top = v
	return top


## Tab / arrows: step through the remaining rigs (dir +1 / -1); leaves auto mode.
func cycle_spectate(dir: int) -> void:
	var cands: Array[SimVehicle] = spectate_candidates()
	if cands.is_empty():
		return
	var cur: SimVehicle = spectated()
	var i: int = cands.find(cur)
	spectate_id = cands[posmod(i + dir, cands.size())].id


## Back to the automatic camera.
func spectate_auto() -> void:
	spectate_id = -1
	_auto_tick = -100000


## Selects a rig to watch by vehicle id (spectator panel clicks).
func spectate_vehicle(id: int) -> void:
	spectate_id = id


func _update_camera(k: float) -> void:
	var v: SimVehicle = focus_vehicle()
	if v == null:
		if attract:
			var t: float = float(world.tick) / float(SimWorld.TICK_RATE)
			var half := get_viewport_rect().size / 2.0
			var c: Vector2 = SimWorld.ARENA.get_center() + Vector2(sin(t * 0.045) * 300.0, sin(t * 0.032 + 1.3) * 170.0)
			c.x = clampf(c.x, SimWorld.ARENA.position.x + half.x, SimWorld.ARENA.end.x - half.x)
			c.y = clampf(c.y, SimWorld.ARENA.position.y + half.y, SimWorld.ARENA.end.y - half.y)
			_camera.position = Gfx.snap(c)
			_camera.force_update_scroll()
		return
	var d: Vector3 = _vehicle_display(v)
	var half := get_viewport_rect().size / 2.0
	var lift: float = (SPECTATE_CAM_LIFT if spectating() else WORKSHOP_CAM_LIFT) if world.phase == SimWorld.PHASE_WORKSHOP else 0.0
	_cam_lift = lerpf(_cam_lift, lift, k)
	var c := Vector2(d.x, d.y + _cam_lift)
	c.x = clampf(c.x, SimWorld.ARENA.position.x + half.x, SimWorld.ARENA.end.x - half.x)
	c.y = clampf(c.y, SimWorld.ARENA.position.y + half.y, SimWorld.ARENA.end.y - half.y)
	_camera.position = Gfx.snap(c)
	# shake: whole-pixel jolts on top of the clamped camera (the ground has margin to spare)
	_camera.offset = Gfx.snap(Vector2(sin(_shake_t * 61.0), cos(_shake_t * 47.0)) * 4.0 * _shake * _shake)
	_camera.force_update_scroll()


## Your own rig stands on a ring of its paint colour, so you find it at a glance (#6).
func _draw_ring() -> void:
	if world == null or attract:
		return
	var v: SimVehicle = focus_vehicle()
	if v == null or not v.alive:
		return
	var rv: RigView = _vehicle_nodes.get(v.id)
	var d: Vector3 = _vehicle_display(v)
	var c: Vector2 = Gfx.snap(Vector2(d.x, d.y))
	var r: float = RigArt.RADIUS[rv.foot if rv != null else 0]
	var col: Color = Gfx.PLAYER_COLORS[Gfx.player_index(v)]
	if v.color_index == Gfx.DARK_PAINT:
		col = Gfx.STEEL[3]
	var n: int = int(r * 4.0)
	var spin: int = world.tick / 3
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var p: Vector2 = Gfx.snap(c + Vector2(cos(a), sin(a) * 0.8) * r)
		var dash: bool = ((i + spin) / 3) % 2 == 0
		_ring.draw_rect(Rect2(p, Vector2.ONE), Color(col, 0.75 if dash else 0.3))
		_ring.draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(Gfx.OUTLINE, 0.25))


## Driver names in paint colour and hp ticks over rival rigs (readability, design doc section 11c).
func _draw_labels() -> void:
	if world == null or attract:
		return
	_draw_effects_overlay()
	for v in world.vehicles:
		if not v.alive:
			continue
		var d: Vector3 = _vehicle_display(v)
		var p: Vector2 = Gfx.snap(Vector2(d.x, d.y))
		var rv: RigView = _vehicle_nodes.get(v.id)
		var r: float = RigArt.RADIUS[rv.foot if rv != null else 0]
		var top: float = p.y - r - 9.0
		if protect_ticks(v) > 0:
			_draw_shield(p, r, v.id)
		if v.momentum >= Mobility.FULL_MOMENTUM:  # full momentum: sparks fly off the rig
			for k in 3:
				var a: float = float((world.tick * 7 + k * 5 + v.id * 3) % 63) / 10.0
				var sp: Vector2 = Gfx.snap(p + Vector2(cos(a), sin(a)) * (r + 1.0 + float((world.tick + k) % 3)))
				_labels.draw_rect(Rect2(sp, Vector2.ONE), Gfx.FIRE[5] if k % 2 == 0 else Gfx.FIRE[4])
		if v.peer_id == world.leader_peer:  # bounty mark (#11)
			var bob: float = float((world.tick / 10) % 2)
			var s := Vector2(Gfx.TEX_SKULL.get_size())
			var sy: float = top - (s.y + 4.0 if v.peer_id != local_peer else 0.0) - bob
			_labels.draw_texture(Gfx.TEX_SKULL, Vector2(p.x - floorf(s.x / 2.0), sy))
		# rival name tags and hp bars are drawn by the HUD (crisp text): Hud._draw_rival_tags


## Thin rings from a few events (saw launch, contract paid, salvo); the big effects live in EffectsLayer / CombatFx.
func _draw_effects_overlay() -> void:
	var keep: Array = []
	for rg: Array in _rings:
		var age: float = float(world.tick - int(rg[2])) / float(rg[3])
		if age >= 1.0 or age < 0.0:
			continue
		keep.append(rg)
		var col: Color = rg[4]
		var rad: float = float(rg[1]) * minf(1.0, age * 2.5 + 0.2)
		var n: int = maxi(int(rad * 1.4), 12)
		var c: Vector2 = Gfx.snap(rg[0])
		for i in n:
			var a: float = TAU * float(i) / float(n)
			_labels.draw_rect(Rect2(Gfx.snap(c + Vector2(cos(a), sin(a) * 0.85) * rad), Vector2.ONE), Color(col, 0.9 * (1.0 - age)))
	_rings = keep


## Protection shimmer: a broken ring of warm-white sparks orbiting the rig (never cyan: cold = alien).
func _draw_shield(c: Vector2, r: float, sd: int) -> void:
	var n: int = 22
	var t: float = float(world.tick) * 0.09 + float(sd)
	for i in n:
		var a: float = TAU * float(i) / float(n) + t
		if (i + world.tick / 2) % 4 == 0:
			continue
		var p: Vector2 = Gfx.snap(c + Vector2(cos(a), sin(a) * 0.85) * (r + 2.0))
		var col: Color = Gfx.FIRE[6] if i % 3 == 0 else Gfx.FIRE[5]
		_labels.draw_rect(Rect2(p, Vector2.ONE), Color(col, 0.85))
