class_name SimEvent
extends RefCounted
## A one-shot fact the sim reports to scenes and tests (design note LT-4 §2).

## New types are appended so existing values never change.
enum Type {SPAWNED, LEAKED, DIED, OUTCOME, TOWER_BUILT, TOWER_SOLD, GOLD_CHANGED, SHOT,
		BUILD_STARTED, WAVE_STARTED, WAVE_CLEARED}

var type: Type
var tick: int
var id: int  ## entity id; 0 when the event is not about an entity (OUTCOME)
var data: Dictionary


func _init(p_type: Type, p_tick: int, p_id: int, p_data: Dictionary = {}) -> void:
	type = p_type
	tick = p_tick
	id = p_id
	data = p_data


func _to_string() -> String:
	return "%s@%d#%d%s" % [Type.keys()[type], tick, id, data]
