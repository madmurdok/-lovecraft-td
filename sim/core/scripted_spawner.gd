class_name ScriptedSpawner
extends SimSpawner
## Spawns a fixed list of [tick, enemy_id] entries (tests; replaced by waves in LT-5).
## An entry fires on the first step whose tick is >= its tick; entries of one tick fire
## in list order. A pack enemy expands into a pack (Simulation.spawn_enemy).

var _pending: Array = []


func _init(entries: Array = []) -> void:
	_pending = entries.duplicate(true)


func tick(sim: Simulation) -> void:
	var now := sim.state.tick
	var keep: Array = []
	for entry: Array in _pending:
		if int(entry[0]) <= now:
			sim.spawn_enemy(String(entry[1]))
		else:
			keep.append(entry)
	_pending = keep


func is_exhausted() -> bool:
	return _pending.is_empty()
