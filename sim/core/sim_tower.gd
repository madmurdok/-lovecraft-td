class_name SimTower
extends RefCounted
## One placed tower in the simulation (LT-6; design note LT-4 §1.4, §6).
## Upgrades (LT-24, Simulation.upgrade_tower) raise `level`, set `branch` at L3 and add to
## `spent`. Simulation.set_target_priority (LT-31) sets `target_priority`.

## Target priority modes (LT-31), in panel order: "first" = closest to the lighthouse
## (least route left), "strongest" = highest current hp, "fastest" = highest current speed.
const TARGET_PRIORITIES: PackedStringArray = ["first", "strongest", "fastest"]
const DEFAULT_TARGET_PRIORITY := "first"

var id: int  ## shared entity id counter (SimState.next_id)
var def: TowerDef
var cell: Vector2i
var pos: Vector2  ## the cell centre in cell units; set when built and by a lift (LT-117)
var level := 0  ## 0 = L1, 1 = L2 (indices into def.levels), 2 = L3 (def.branches[branch])
var branch := ""  ## "" below L3; "a" or "b" at L3
var spent := 0  ## total gold paid for this tower (build + upgrades); the sell refund base
var build_tick := 0
## LT-32 §2.2: men on board (a crewed tower's per_tower, a post's post.crew); 0 when crew
## is off or the tower needs no crew. Returned to the reserve on sell and (posts) at dawn.
var crew := 0
## LT-32: whose men stand on a post (a crew kind); "" on towers (their kind is def.id).
var crew_kind := ""
## LT-32 Q3 (a): a reserve post, not a tower: def is the synthetic CrewConfig.POST_ID def,
## never sold or upgraded (NOT_A_TOWER), removed at dawn. Fights like any shooter.
var post := false
## Ticks until the tower may fire again; 0 = ready. A new tower is ready at once.
var cooldown_ticks := 0
## One of TARGET_PRIORITIES; whom _fire_towers picks among the live enemies in range.
var target_priority := DEFAULT_TARGET_PRIORITY
## LT-29 §1.2 (Gangsters): round-robin position over the ranked `burst_targets`; persists
## between shots, wraps to the ranked set's size at each shot.
var burst_index := 0
## LT-50 (Resonator beam): the enemy a beam level keeps firing at while it stays a live
## candidate; -1 = none, the next shot picks by target_priority. Cleared by
## Simulation.set_target_priority so a new mode applies at once.
var locked_id := -1
## LT-30, LT-70 §2.1: net light, set in slot 2 at night only: inside a lighthouse beam,
## the flare or another tower's casts_light radius (centre test) and not shadowed. Never
## true together with `shadowed`; persists between ticks, a flip of either emits
## TOWER_LIT {lit, shadowed}.
var lit := false
## LT-70 §2.1: net shadow, set in slot 2 at night only: inside another tower's casts_shadow
## radius (centre test) and not lit by the beam, the flare or a casts_light tower.
var shadowed := false

## LT-105 (LT-96 S9): the tower modifier channel, what the tower fires with this tick.
## Reset to neutral in slot 1 (Simulation.step, reset_modifiers); slot-2 writers compose
## into it through add_modifiers only, in a fixed order (light first, LightSystem.
## update_beam); slot-2 apply_auras and slot-5 fire_towers / _cast_banish / _summon read it.
## Between ticks it holds the last tick's values (the UI reads it there, Simulation.
## tower_mults). No timers here: a timed effect keeps its timer with its owner and rewrites
## the channel every tick while active.
var power_mult := 1.0  ## damage / aura / banish / summon multiplier (composed by *)
var interval_mult := 1.0  ## fire interval multiplier, shooters only (composed by *)
var miss_add := 0.0  ## added to a mundane shot's miss chance (composed by +)
var ignore_miss := false  ## no miss roll at all, wins over miss_add (composed by OR)
var disabled := false  ## no shot, cast or aura; the cooldown keeps counting (OR)

## LT-117: ticks left of a night-gaunt lift's disable, the timer's owner (not part of the
## channel): set by Simulation._lift_tower, rewritten into `disabled` and counted down by
## TraitSystem.near_tower each tick while > 0. A tower with a running timer is not lifted.
var lift_ticks_left := 0


func stats() -> TowerDef.Level:
	if level >= TowerDef.LEVEL_COUNT:
		return def.branches[branch]
	return def.levels[level]


## LT-105 D2: slot 1 of every tick, before any writer. The literals are the neutral values
## the golden replay relies on (1.0 * x == x, 0.0 + x == x exactly).
func reset_modifiers() -> void:
	power_mult = 1.0
	interval_mult = 1.0
	miss_add = 0.0
	ignore_miss = false
	disabled = false


## LT-105 D1/D4: the only write path into the channel. Multipliers multiply in call order
## (float * is not associative: writer order is part of determinism), miss_add sums, the
## bools OR.
func add_modifiers(power: float, interval: float, miss: float, no_miss := false,
		off := false) -> void:
	power_mult *= power
	interval_mult *= interval
	miss_add += miss
	ignore_miss = ignore_miss or no_miss
	disabled = disabled or off


## LT-105 D7: the channel as {power_mult, interval_mult, miss_add, ignore_miss, disabled}.
func modifiers() -> Dictionary:
	return {
		"power_mult": power_mult,
		"interval_mult": interval_mult,
		"miss_add": miss_add,
		"ignore_miss": ignore_miss,
		"disabled": disabled,
	}



## Cell centre in cell units (same frame as SimRoute.position_at).
func centre() -> Vector2:
	return pos
