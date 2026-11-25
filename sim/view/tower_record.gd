class_name TowerRecord
extends RefCounted
## LT-85 §3.2: a read-only copy of one tower for presentation, built by
## Simulation.snapshot(). Holds no SimTower. Fields are read-only by contract; the modifier
## numbers are read through Simulation.tower_mults(id).

const TARGET_PRIORITIES := SimTower.TARGET_PRIORITIES

var id: int
var def: TowerDef  ## shared immutable config
var cell: Vector2i
var centre: Vector2  ## cell centre in cell units (SimTower.centre())
var level: int
var branch: String
var stats: TowerDef.Level  ## SimTower.stats(): the shared config level it acts with now
var post: bool
var crew: int
var crew_kind: String
var lit: bool
var shadowed: bool
var disabled: bool
var target_priority: String


## The only code that reads a live SimTower for presentation.
static func from_tower(t: SimTower) -> TowerRecord:
	var r := TowerRecord.new()
	r.id = t.id
	r.def = t.def
	r.cell = t.cell
	r.centre = t.centre()
	r.level = t.level
	r.branch = t.branch
	r.stats = t.stats()
	r.post = t.post
	r.crew = t.crew
	r.crew_kind = t.crew_kind
	r.lit = t.lit
	r.shadowed = t.shadowed
	r.disabled = t.disabled
	r.target_priority = t.target_priority
	return r


## True when every field equals what from_tower(t) would copy now. Simulation.snapshot(prev)
## then shares this record with the new snapshot instead of building an equal one: records
## are read-only, so sharing an unchanged one is unobservable (LT-85/S15). A new field goes
## here as well as in from_tower.
func copies(t: SimTower) -> bool:
	return id == t.id and def == t.def and cell == t.cell and centre == t.centre() \
		and level == t.level and branch == t.branch and stats == t.stats() \
		and post == t.post and crew == t.crew and crew_kind == t.crew_kind and lit == t.lit \
		and shadowed == t.shadowed and disabled == t.disabled \
		and target_priority == t.target_priority
