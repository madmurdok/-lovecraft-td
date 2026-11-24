class_name EnemyRecord
extends RefCounted
## LT-85 §3.1: a read-only copy of one live enemy for presentation, built by
## Simulation.snapshot(). Holds no SimEnemy and has no is_fake / status field: every field is
## the same for a real enemy and a fake of the same kind on the same tick (LT-12), so a
## presentation script cannot tell them apart. Fields are read-only by contract.

var id: int
var def: EnemyDef  ## shared immutable config (name, flying, traits, base armor)
var hp: float
var max_hp: float
var speed: float  ## cells/s this tick: the units it moves by (wave multiplier, slows, madness)
var base_speed: float  ## cells/s with the wave multiplier, no per-tick modifiers
var armor: float  ## effective armor, the apply_damage formula: max(0, def.armor + bonus)
var markers: PackedStringArray  ## SimEnemy.markers() at build time
var madness_buffed: bool  ## got the MADNESS buff this tick (SimEnemy.madness_buffed, slot 2)
var lit: bool
var revealed: bool  ## a revealed fake (LT-12): a game rule, shown on the board
var prev_distance: int  ## route distance before the last tick's move (interpolation)
var distance: int
var pos: Vector2  ## cell units at alpha 1 (= position(1.0))
var _route: SimRoute  ## shared immutable route; read only by position()


## The only code that reads a live SimEnemy for presentation.
static func from_enemy(e: SimEnemy) -> EnemyRecord:
	var r := EnemyRecord.new()
	r.id = e.id
	r.def = e.def
	r.hp = e.hp
	r.max_hp = e.max_hp
	r.speed = roundi(e.base_units_per_tick * e.speed_mult) * float(SimTime.TICK_RATE) \
		/ SimTime.UNITS_PER_CELL
	r.base_speed = e.base_units_per_tick * float(SimTime.TICK_RATE) / SimTime.UNITS_PER_CELL
	r.armor = maxf(0.0, e.def.armor + e.armor_bonus)
	r.markers = e.markers()
	r.madness_buffed = e.madness_buffed
	r.lit = e.lit
	r.revealed = e.revealed
	r.prev_distance = e.prev_distance
	r.distance = e.distance
	r._route = e.route
	r.pos = e.route.position_at(e.distance)
	return r


## Position in cell units between the last two ticks by `alpha` (0..1): the exact
## Simulation.enemy_position formula (along the route, not a straight lerp).
func position(alpha: float) -> Vector2:
	return _route.position_at(roundi(lerpf(float(prev_distance), float(distance), alpha)))
