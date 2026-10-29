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
var is_fake := false  ## hallucination (LT-12): never damages the lighthouse
var revealed := false  ## fake made visible (LT-12); the renderer sees this, never is_fake
var spawn_tick: int
## Set during a tick; the enemy is removed at the end of that tick (step 8).
var dead := false
var leaked := false

# Per-tick modifiers: reset every tick, rebuilt by effect systems (LT-6/LT-11).
var speed_mult := 1.0
var damage_taken_mult := 1.0
var armor_bonus := 0.0

## Trait timers (stun, harass stop, ...) added by later tasks.
var status: Dictionary = {}


func reset_modifiers() -> void:
	speed_mult = 1.0
	damage_taken_mult = 1.0
	armor_bonus = 0.0


## Still in play: neither killed nor leaked.
func is_live() -> bool:
	return not dead and not leaked
