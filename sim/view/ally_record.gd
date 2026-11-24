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


## The only code that reads a live SimAlly for presentation.
static func from_ally(a: SimAlly) -> AllyRecord:
	var r := AllyRecord.new()
	r.id = a.id
	r.tower = a.tower
	r.source = a.source
	r.prev_pos = a.prev_pos
	r.pos = a.pos
	r.hp = a.hp
	r.max_hp = a.max_hp
	r.flying = a.flying
	r.held_id = a.held_id
	return r


## Position in cell units between the last two ticks by `alpha` (0..1): the
## AllySystem.ally_position formula.
func position(alpha: float) -> Vector2:
	return prev_pos.lerp(pos, alpha)
