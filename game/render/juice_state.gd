class_name JuiceState
extends RefCounted
## Render-only bookkeeping for the combat "juice" (docs/architecture.md "Combat visuals"): the kill
## combo of the watched rig, the hive surge warning and the watched rig's weapon evolving (the
## EVOLVED banner; WorldView detects the flip of a weapon's "evo" flag). Fed from sim events once per sim tick by
## WorldView (and by prime() in screenshot mode); everything is keyed on sim ticks, so host, clients
## and screenshots agree. Never touches the sim.

const COMBO_WINDOW := 45  ## ticks (1.5 s): a kill within this of the last one chains the combo
const COMBO_MIN := 3  ## the counter shows from this many chained kills on
const COMBO_FADE := 18  ## ticks the final count lingers after the chain breaks
## Milestone words (Mad Max tone) and the combo that calls them out.
const MILESTONES: Array = [[10, "ROADKILL"], [25, "SHREDDED"], [50, "BUG BLENDER"], [100, "HIVE BREAKER"],
	[200, "WASTELAND LEGEND"]]
const MILESTONE_TICKS := 40  ## how long a milestone word stays up
const SURGE_DEFAULT_TICKS := 60  ## "surge" events without in_ticks: the sim's 2 s warning
const SURGE_HOLD := 24  ## ticks the banner stays up after the surge hits ("HERE THEY COME")

var focus_id: int = -1
var combo: int = 0
var combo_last: int = -100000  ## tick of the latest chained kill
var combo_best: int = 0  ## best chain this match (for a future recap)
var milestone_word: String = ""
var milestone_tick: int = -100000
var surge_tick: int = -100000  ## tick the "surge" warning arrived
var surge_in: int = 0  ## ticks from the warning to the surge
## The watched rig's latest weapon evolution: when, the evolved weapon's name and the recipe line.
const EVO_BANNER_TICKS := 105  ## 3.5 s
var evo_tick: int = -100000
var evo_word: String = ""
var evo_sub: String = ""
var evo_kind: String = ""


func reset() -> void:
	focus_id = -1
	combo = 0
	combo_last = -100000
	combo_best = 0
	milestone_word = ""
	milestone_tick = -100000
	surge_tick = -100000
	surge_in = 0
	evo_tick = -100000
	evo_word = ""


## The watched rig; switching rigs (spectator) drops the running chain.
func set_focus(id: int) -> void:
	if id == focus_id:
		return
	focus_id = id
	combo = 0
	combo_last = -100000
	milestone_word = ""
	milestone_tick = -100000
	evo_tick = -100000
	evo_word = ""


## An alien kill credited to vehicle `owner` at sim tick `tick`. Returns true when it hit a milestone.
func on_kill(owner: int, tick: int) -> bool:
	if owner < 0 or owner != focus_id:
		return false
	if tick - combo_last > COMBO_WINDOW or tick < combo_last:
		combo = 0
	combo += 1
	combo_last = tick
	combo_best = maxi(combo_best, combo)
	var word: String = milestone_at(combo)
	if word != "":
		milestone_word = word
		milestone_tick = tick
		return true
	return false


## A "surge" warning: the sim spawns a wave surge `in_ticks` from now.
func on_surge(tick: int, in_ticks: int) -> void:
	surge_tick = tick
	surge_in = in_ticks if in_ticks > 0 else SURGE_DEFAULT_TICKS


## Weapon `kind` of the watched rig just evolved into `word` ("GATLING HELL"); `sub` names the recipe.
func on_evolve(owner: int, tick: int, kind: String, word: String, sub: String) -> void:
	if owner < 0 or owner != focus_id:
		return
	evo_tick = tick
	evo_kind = kind
	evo_word = word
	evo_sub = sub


## Ticks since the watched rig's latest evolution while its banner shows (-1 = none showing).
func evo_age(tick: int) -> int:
	var a: int = tick - evo_tick
	return a if evo_word != "" and a >= 0 and a < EVO_BANNER_TICKS else -1


## The chained count to show at `tick` (0 = hide the counter).
func combo_shown(tick: int) -> int:
	if combo < COMBO_MIN or tick < combo_last or tick - combo_last > COMBO_WINDOW + COMBO_FADE:
		return 0
	return combo


## True while the chain can still grow (inside the window); false while the final count fades.
func combo_live(tick: int) -> bool:
	return tick >= combo_last and tick - combo_last <= COMBO_WINDOW


## Ticks since the latest milestone (-1 = none showing).
func milestone_age(tick: int) -> int:
	var a: int = tick - milestone_tick
	return a if milestone_word != "" and a >= 0 and a < MILESTONE_TICKS else -1


## The milestone word reached at exactly `n` kills ("" = none).
static func milestone_at(n: int) -> String:
	for m: Array in MILESTONES:
		if int(m[0]) == n:
			return str(m[1])
	return ""


## 0..1 heat of a combo: drives size and colour (pale to deep fire) of the counter.
static func heat(n: int) -> float:
	return clampf(float(n - COMBO_MIN) / 97.0, 0.0, 1.0)


## True while the surge banner shows (the warning, then a short "here they come").
func surge_active(tick: int) -> bool:
	var a: int = tick - surge_tick
	return a >= 0 and a < surge_in + SURGE_HOLD


## Ticks until the surge hits (<= 0 once it has).
func surge_left(tick: int) -> int:
	return surge_tick + surge_in - tick
