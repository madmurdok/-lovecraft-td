class_name SimSnapshot
extends RefCounted
## LT-85 §3.4: everything presentation reads from the simulation, as one fresh copy built
## by Simulation.snapshot(): the live entities as records and the scalars of SimState.
## Holds no live sim object (only shared immutable config: defs, MapDef). Read-only by
## contract; a new reader adds a field here and in Simulation.snapshot().

# Entities, live only, id order.
var enemies: Array[EnemyRecord] = []
var towers: Array[TowerRecord] = []
var allies: Array[AllyRecord] = []

# Scalars, copied from SimState.
var tick := 0
var outcome := SimState.Outcome.NONE
var phase := SimState.Phase.NONE
var wave_index := 0
var waves_total := 0
var build_ticks_left := 0
var gold := 0
var relics: Dictionary[String, int] = {}  ## a copy: writing it changes nothing in the sim
var sanity := 0.0
var sanity_cap := 0.0
var sanity_state := SimState.SanityState.LUCID
var lighthouse_hp := 0
var lighthouse_level := 0
var night_luck := 1.0
var oil := 0
var flare_ticks_left := 0
var flare_cooldown_ticks := 0
var map: MapDef  ## shared immutable config

# Lookups, built once by index().
var _enemy_by_id: Dictionary[int, EnemyRecord] = {}
var _tower_by_id: Dictionary[int, TowerRecord] = {}
var _tower_at: Dictionary[Vector2i, TowerRecord] = {}


## Builds the id lookups from the entity arrays and `tower_cells` (occupied cell -> tower
## id, SimState.tower_at). Called once by Simulation.snapshot().
func index(tower_cells: Dictionary[Vector2i, int]) -> void:
	for e in enemies:
		_enemy_by_id[e.id] = e
	for t in towers:
		_tower_by_id[t.id] = t
	for cell: Vector2i in tower_cells:
		var t: TowerRecord = _tower_by_id.get(tower_cells[cell])
		if t != null:
			_tower_at[cell] = t


## The live enemy `id`, or null.
func enemy(id: int) -> EnemyRecord:
	return _enemy_by_id.get(id)


## The tower `id`, or null.
func tower(id: int) -> TowerRecord:
	return _tower_by_id.get(id)


## The tower standing on `cell` (built or building), or null: replaces state.tower_at.
func tower_at(cell: Vector2i) -> TowerRecord:
	return _tower_at.get(cell)
