class_name SimTestBase
extends ConfigTestBase
## Shared helpers for the LT-4 simulation suites: configs built from a copy of res://data
## with a replaced map / lighthouse HP / enemy stats, event filters and step helpers.

const MAP := "map.json"
const ECON := "economy.json"
const ENEMIES := "enemies.json"

var _real: GameConfig
## LT-30: make_config (tsim, ...) darkens the lighthouse beam (reach ~0) so suites about
## other mechanics are not lit in phase NONE, where the beam shines; a beam suite sets this.
var lit_beam := false


## The unedited res://data config (loaded once per suite).
func real_config() -> GameConfig:
	if _real == null:
		var r := GameConfig.load_from_dir("res://data")
		assert_bool(r.ok).override_failure_message("res://data: %s" % "\n".join(r.errors)) \
			.is_true()
		_real = r.config
	return _real


## Single-row map "S##..#L" whose route is `cells` cells long (cells + 1 path cells).
func line_map(cells: int) -> Array:
	return ["S" + "#".repeat(cells - 1) + "L"]


## Config from res://data with the map replaced by `rows` (empty keeps the real map;
## width/height come from the rows), lighthouse HP `hp` (-1 keeps it) and enemy fields
## overridden by `enemy_edits` ({enemy_id: {field: value}}).
func make_config(rows: Array, hp := -1, enemy_edits := {}) -> GameConfig:
	var r := load_edited(func(dir: String) -> void: _apply_edits(dir, rows, hp, enemy_edits))
	assert_bool(r.ok).override_failure_message("config rejected:\n%s" % "\n".join(r.errors)) \
		.is_true()
	return r.config


func _apply_edits(dir: String, rows: Array, hp: int, enemy_edits: Dictionary) -> void:
	if not rows.is_empty():
		edit(dir, MAP, func(root: Dictionary) -> void:
			root["width"] = String(rows[0]).length()
			root["height"] = rows.size()
			root["rows"] = rows)
	if hp >= 0:
		edit(dir, ECON, func(root: Dictionary) -> void: root["lighthouse"]["hp"] = hp)
	if not lit_beam:
		dark_beam(dir)
	for id: String in enemy_edits:
		var fields: Dictionary = enemy_edits[id]
		edit(dir, ENEMIES, func(root: Dictionary) -> void:
			for k: String in fields:
				root["enemies"][id][k] = fields[k])


## LT-30: shrinks the beam's reach to ~0 in the copied economy.json: nothing is ever lit.
## LT-57: the flare circle too (radius_cells must stay within reach_cells): radius 0.
func dark_beam(dir: String) -> void:
	edit(dir, ECON, func(root: Dictionary) -> void:
		var lh: Dictionary = root["lighthouse"]
		lh["beam"]["reach_cells"] = 0.0001
		if lh.has("flare"):
			var zeros := []
			for i in lh["beam"]["levels"].size():
				zeros.append(0)
			lh["flare"]["radius_cells"] = zeros)


## Route length in units of a ground path of `path_cells` cells (each step one cell).
func ground_length(path_cells: int) -> int:
	return (path_cells - 1) * SimTime.UNITS_PER_CELL


## First tick on which an enemy spawned on `spawn_tick` reaches distance `length`.
func expected_leak_tick(spawn_tick: int, length: int, units_per_tick: int) -> int:
	return spawn_tick + (length + units_per_tick - 1) / units_per_tick


## LT-63: ticks from a pack's first member entering to its last one at the max pack size.
func pack_span_ticks(cfg: GameConfig, def_id: String) -> int:
	var pack: Dictionary = cfg.enemies[def_id].traits["pack"]
	return (int(pack["max"]) - 1) * SimTime.ticks(pack["spacing_s"])


## Steps `n` times (or until the outcome freezes the sim) and returns the drained events.
func run(sim: Simulation, n: int) -> Array[SimEvent]:
	for i in n:
		sim.step()
	return sim.drain_events()


## Steps until state.tick == `tick`; returns the drained events.
func run_to(sim: Simulation, tick: int) -> Array[SimEvent]:
	assert_int(tick).is_greater_equal(sim.state.tick)
	return run(sim, tick - sim.state.tick)


func of_type(events: Array[SimEvent], t: SimEvent.Type) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in events:
		if e.type == t:
			out.append(e)
	return out


func ids_of(events: Array[SimEvent]) -> Array[int]:
	var out: Array[int] = []
	for e in events:
		out.append(e.id)
	return out


func strings_of(events: Array[SimEvent]) -> Array[String]:
	var out: Array[String] = []
	for e in events:
		out.append(str(e))
	return out
