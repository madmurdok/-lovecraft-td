class_name AllyRecord
extends RefCounted
## LT-85 §3.3: a read-only copy of one live summoned unit for presentation, built by
## Simulation.snapshot(). Holds no SimAlly. Fields are read-only by contract.

var id: int
var tower: int  ## the summoning tower's id
var source: String
var prev_pos: Vector2  ## cell units before the last tick's move (interpolation)
var pos: Vector2  ## cell units
var hp: float
var max_hp: float
var flying: bool
var held_id: int  ## the enemy it holds; -1 = none


## Same as AllyRecord.new(a).
static func from_ally(a: SimAlly) -> AllyRecord:
	return AllyRecord.new(a)


## The only code that reads a live SimAlly for presentation; `a` null leaves a blank record.
## Built in _init so the field writes are member writes (LT-85/S15).
func _init(a: SimAlly = null) -> void:
	if a == null:
		return
	id = a.id
	tower = a.tower
	source = a.source
	prev_pos = a.prev_pos
	pos = a.pos
	hp = a.hp
	max_hp = a.max_hp
	flying = a.flying
	held_id = a.held_id


## Position in cell units between the last two ticks by `alpha` (0..1): the
## AllySystem.ally_position formula.
func position(alpha: float) -> Vector2:
	return prev_pos.lerp(pos, alpha)
