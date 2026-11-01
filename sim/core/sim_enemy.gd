class_name SimEnemy
extends RefCounted
## One live enemy in the simulation (design note LT-4 §1.4).

var id: int
var def: EnemyDef
var hp: float
var max_hp: float
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
var lit := false  ## LT-30: inside a lighthouse beam this tick (slot 2)

## Status timers, ticked in slot 2 by Simulation._tick_statuses; `*_ticks` keys are erased
## at 0 (LT-29 P6). Keys: `bleed_ticks` (int, ticks left), `bleed_dps` (float),
## `bleed_pulse` (int, ticks to the next pulse), `bleed_source` (String, tower def id),
## `pull_immune_ticks` (int). Later tasks add theirs (stun, harass stop, banish immunity).
var status: Dictionary = {}


func reset_modifiers() -> void:
	speed_mult = 1.0
	damage_taken_mult = 1.0
	armor_bonus = 0.0
	lit = false


## Still in play: neither killed, leaked nor dissolved.
func is_live() -> bool:
	return not dead and not leaked and not dissolved
