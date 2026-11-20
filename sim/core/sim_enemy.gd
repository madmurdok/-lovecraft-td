class_name SimEnemy
extends RefCounted
## One live enemy in the simulation (design note LT-4 §1.4).

var id: int
var def: EnemyDef
var hp: float
var max_hp: float
## LT-111: max HP before the wave's hp_mult (= def.hp at spawn). The size class the
## pull/banish HP caps compare, so a wave multiplier never switches tower roles.
var base_max_hp: float
var route: SimRoute
var distance: int = 0  ## along `route`, in SimTime.UNITS_PER_CELL units
var prev_distance: int = 0  ## distance before this tick's movement (render interpolation)
var base_units_per_tick: int
## Hallucination (LT-12): never damages the lighthouse. Sim only: no script outside sim/
## and tests/ names it (render isolation, LT-12 §1); scenes use Simulation.debug_is_fake.
var is_fake := false
var revealed := false  ## fake made visible (LT-12); the renderer sees this, never is_fake
var spawn_tick: int
## LT-63: id of the first member of its pack (itself for the first), 0 = not a pack enemy.
## Members enter one by one, so a pack's ids need not be consecutive.
var pack_of := 0
## Set during a tick; the enemy is removed at the end of that tick (step 8).
var dead := false
var leaked := false
var dissolved := false  ## fake gone at the lighthouse or at wave end (LT-12)

# Per-tick modifiers: reset every tick, rebuilt by effect systems (LT-6/LT-11).
var speed_mult := 1.0
var damage_taken_mult := 1.0
var armor_bonus := 0.0
## LT-30, LT-70 §2.4: lit this tick (slot 2, night only): inside a lighthouse beam, the
## flare or a casts_light tower's radius (Searchlight). Enemies have no shadow.
var lit := false

## Status timers, ticked in slot 2 by CombatSystem.tick_statuses; `*_ticks` keys are erased
## at 0 (LT-29 P6). LT-106: the keys are listed per status in StatusRules.ROWS (bleed:
## `bleed_ticks`, `bleed_dps`, `bleed_pulse`, `bleed_source`; `banish_immune_ticks`;
## `pull_immune_ticks`); a trait keeps its own state here under keys prefixed with its id.
## Sim only: presentation reads markers(), never this (guard G14).
var status: Dictionary = {}


func reset_modifiers() -> void:
	speed_mult = 1.0
	damage_taken_mult = 1.0
	armor_bonus = 0.0
	lit = false


## LT-25 §2 / LT-106 T8: the markers it shows, from its per-tick aura state and its
## StatusRules rows with a marker, in that order: slow, vuln, then ROWS order.
func markers() -> PackedStringArray:
	var out := PackedStringArray()
	if speed_mult < 0.999:
		out.append("slow")
	if damage_taken_mult > 1.001:
		out.append("vuln")
	if status.is_empty():
		return out
	for row: Dictionary in StatusRules.ROWS.values():
		if row["marker"] != "" and int(status.get(row["ticks"], 0)) > 0:
			out.append(row["marker"])
	return out


## Still in play: neither killed, leaked nor dissolved.
func is_live() -> bool:
	return not dead and not leaked and not dissolved
