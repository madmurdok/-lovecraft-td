extends SimTestBase
## LT-101: tools/bot/strategies.json and its loader tools/bot/strategy_table.gd (design
## docs/design/LT-101-bot-strategies-data.md §3, §8): the shipped file loads; each malformed
## case is rejected with its message; the interpreter (tools/bot/bot_strategies.gd) reads the
## row it is given (on_blocked skip vs fallback, fallback_max, cap_floor, branch picks, the
## tunables) rather than the shipped strategies; the harness (tools/bot_runs.gd) quits 1 on a
## bad table before any run and derives its run cap from the config's wave count.
## The 20-seed baseline and tests/bot_upgrade_test.gd cover the shipped rows; this suite uses
## tables built by parse_text() so a hard-coded strategy name or constant cannot pass.

const Table := preload("res://tools/bot/strategy_table.gd")
const Strategies := preload("res://tools/bot/bot_strategies.gd")
const BOT_PATH := "res://tools/bot_runs.gd"
const SHIPPED_PATH := "res://tools/bot/strategies.json"
const R := SimCommand.CommandResult
const RIFLE := "rifleman"
const HARP := "harpooner"
const SIGN := "elder_sign"
const SHIPPED_NAMES := ["mundane", "occult", "mixed", "madness", "demolition", "battery",
	"resonator", "gate", "circle", "light"]
const TUNABLES := {"build_first": 5, "flare_min_live": 4}
const WAVES3_DIR := "user://lt101_waves3"

var _saved_default: Table
var _objs: Array[Object] = []
var _bot_script: GDScript
var _main_script: GDScript


func before_test() -> void:
	_saved_default = Table._default


func after_test() -> void:
	Table._default = _saved_default  # a test may inject a table into the harness
	for o in _objs:
		if is_instance_valid(o):
			o.free()
	_objs.clear()


# --- helpers -----------------------------------------------------------------------------------

## The JSON text of a table with `rows` (and the shipped tunables unless given).
func _text(rows: Array, tunables: Variant = TUNABLES) -> String:
	return JSON.stringify({"tunables": tunables, "strategies": rows})


func _parse(rows: Array, tunables: Variant = TUNABLES) -> Table:
	return Table.parse_text(_text(rows, tunables))


## Asserts `t` has an error containing `fragment` (case label `what`).
func _assert_error(t: Table, fragment: String, what: String) -> void:
	var hit := t.errors.any(func(e: String) -> bool: return e.contains(fragment))
	assert_bool(hit).override_failure_message("%s: no error containing <%s> in %s" \
		% [what, fragment, t.errors]).is_true()


## The shipped rows as parsed JSON (plain, writable dictionaries).
func _shipped_json() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIPPED_PATH))


## A fresh res://data config the test may edit.
func _fresh() -> GameConfig:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config


func _sim(gold := 0, cfg: GameConfig = null) -> Simulation:
	if cfg == null:
		cfg = real_config()
	var sim := Simulation.new(cfg, 1000)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	sim.state.gold = gold
	sim.drain_events()
	return sim


## A policy object playing `table` on `cfg` (the way the harness's _policy() sets it up).
func _strat(table: Table, cfg: GameConfig = null, lighthouse := true) -> Strategies:
	assert_array(table.errors).is_empty()
	var st := Strategies.new()
	st.table = table
	st.cfg = cfg if cfg != null else real_config()
	st.lighthouse = lighthouse
	return st


## Builds `def_id` on the first free buildable cell, raised to `level` (0-based).
func _place(sim: Simulation, def_id: String, level := 0) -> SimTower:
	var gold := sim.state.gold
	sim.state.gold = 100000
	var cell := Vector2i(-1, -1)
	var m := sim.state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if cell.x < 0 and m.is_buildable(c) and not sim.state.tower_at.has(c):
				cell = c
	assert_int(sim.build_tower(def_id, cell)).is_equal(R.OK)
	var t := sim.tower_by_id(sim.state.tower_at[cell])
	for i in level:
		assert_int(sim.upgrade_tower(t.id)).is_equal(R.OK)
	sim.state.gold = gold
	return t


## A WAVE sim with exactly `live` live enemies and oil for a flare (as bot_upgrade_test).
func _night_with_live(live: int) -> Simulation:
	var sim := _sim()
	assert_int(sim.call_wave()).is_equal(R.OK)
	for i in live:
		sim.spawn_enemy("cultist", false)
	assert_int(sim.state.enemies.filter(func(e: SimEnemy) -> bool: return e.is_live()).size()) \
		.is_equal(live)
	sim.state.oil = sim.config.economy.flare.cost_oil
	sim.drain_events()
	return sim


## A copy of the harness whose constructor does nothing; `_cfg` is `cfg`.
func _bot(cfg: GameConfig) -> Object:
	if _bot_script == null:
		var src := FileAccess.get_file_as_string(BOT_PATH)
		assert_bool(src.contains("func _init() -> void:")).is_true()
		_bot_script = GDScript.new()
		_bot_script.source_code = src.replace("func _init() -> void:", "func _unused_init() -> void:")
		assert_int(_bot_script.reload()).is_equal(OK)
	var b: Object = _bot_script.new()
	_objs.append(b)
	b.set("_cfg", cfg)
	return b


## Runs the harness's _init on `args` with `table` as StrategyTable.default() (the same source
## rewrite as bot_upgrade_test: _play, quit and printerr recorded, see its MAIN_HARNESS).
func _run_main(table: Table, args: Array) -> Object:
	Table._default = table
	if _main_script == null:
		var src := FileAccess.get_file_as_string(BOT_PATH)
		for s in ["func _init() -> void:", "OS.get_cmdline_user_args()",
				"var r := _play(strat, 1000 + s)", "quit(", "printerr(",
				"StrategyTable.default()"]:
			assert_bool(src.contains(s)).override_failure_message(s).is_true()
		src = src.replace("func _init() -> void:", "func _test_main() -> void:") \
			.replace("OS.get_cmdline_user_args()", "_test_args") \
			.replace("var r := _play(strat, 1000 + s)", "var r := _test_play(strat, 1000 + s)") \
			.replace("quit(", "_test_quit(").replace("printerr(", "_test_printerr(")
		_main_script = GDScript.new()
		_main_script.source_code = src + BotUpgradeTest.MAIN_HARNESS
		assert_int(_main_script.reload()).is_equal(OK)
	var b: Object = _main_script.new()
	_objs.append(b)
	b.set("_test_args", PackedStringArray(args))
	b.call("_test_main")
	return b


# --- loader: the shipped file ------------------------------------------------------------------

func test_shipped_file_loads_in_row_order_with_its_tunables() -> void:
	var t := Table.load_file()
	assert_array(t.errors).is_empty()
	assert_array(t.names).is_equal(SHIPPED_NAMES)
	# The tunables come from the file, not from a constant of the loader.
	var raw: Dictionary = _shipped_json().tunables
	assert_int(t.build_first).is_equal(int(raw.build_first))
	assert_int(t.flare_min_live).is_equal(int(raw.flare_min_live))
	assert_int(t.build_first).is_equal(5)
	assert_int(t.flare_min_live).is_equal(4)
	assert_array(Table.default().names).is_equal(SHIPPED_NAMES)
	assert_array(t.check_towers(real_config())).is_empty()
	var golden := GameConfig.load_from_dir("res://tests/fixtures/golden_data")
	assert_bool(golden.ok).is_true()
	assert_array(t.check_towers(golden.config)).is_empty()


func test_tunables_follow_the_file() -> void:
	var t := _parse([{"name": "a", "cycle": [RIFLE]}], {"build_first": 2, "flare_min_live": 7})
	assert_array(t.errors).is_empty()
	assert_int(t.build_first).is_equal(2)
	assert_int(t.flare_min_live).is_equal(7)


func test_a_minimal_row_is_normalized_and_read_only() -> void:
	var t := _parse([{"name": "a", "cycle": [RIFLE]}])
	assert_array(t.errors).is_empty()
	var r := t.row("a")
	assert_dict(r).is_equal({"name": "a", "about": "", "prefix": [], "cycle": [RIFLE],
		"branches": {}, "cap_floor": null, "on_blocked": "", "fallback": "", "fallback_max": 0,
		"buy_sanity": false})
	assert_bool(r.is_read_only()).is_true()
	assert_bool((r.prefix as Array).is_read_only()).is_true()
	assert_bool((r.cycle as Array).is_read_only()).is_true()
	assert_bool((r.branches as Dictionary).is_read_only()).is_true()
	assert_dict(t.row("nosuch")).is_empty()


func test_names_are_read_only_on_every_table_and_a_copy_is_writable() -> void:
	assert_bool(_parse([{"name": "a", "cycle": [RIFLE]}]).names.is_read_only()).is_true()
	assert_bool(_parse([{"name": "a"}]).names.is_read_only()).is_true()  # with errors
	assert_bool(Table.load_file("res://no/such/strategies.json").names.is_read_only()).is_true()
	assert_bool(Table.load_file().names.is_read_only()).is_true()
	assert_bool(Table.default().names.is_read_only()).is_true()
	assert_bool(Table.default().names.duplicate().is_read_only()).is_false()


func test_load_file_reads_a_file_and_reports_a_missing_one() -> void:
	var path := "user://lt101_strategies_test.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(_text([{"name": "b", "cycle": [HARP]}, {"name": "a", "cycle": [RIFLE]}]))
	f.close()
	var t := Table.load_file(path)
	DirAccess.remove_absolute(path)
	assert_array(t.errors).is_empty()
	assert_array(t.names).is_equal(["b", "a"])
	var missing := Table.load_file("res://no/such/strategies.json")
	_assert_error(missing, "file not found", "missing file")
	assert_array(missing.names).is_empty()


# --- loader: rejections ------------------------------------------------------------------------

## Each malformed row is rejected with its message; the good row next to it is kept.
func test_each_malformed_row_is_rejected_with_its_message() -> void:
	var fb := {"cap_floor": 30, "on_blocked": "fallback", "fallback": RIFLE, "fallback_max": 3}
	var cases := [
		[{"name": "x", "cycle": [RIFLE], "colour": 1}, "unknown key \"colour\""],
		[{"cycle": [RIFLE]}, ".name: must match"],
		[{"name": 5, "cycle": [RIFLE]}, ".name: must match"],
		[{"name": "good", "cycle": [RIFLE]}, "duplicate name \"good\""],
		[{"name": "x", "about": 3, "cycle": [RIFLE]}, ".about: must be a string"],
		[{"name": "x", "prefix": RIFLE, "cycle": [RIFLE]}, ".prefix: must be an array"],
		[{"name": "x", "prefix": [""], "cycle": [RIFLE]}, ".prefix: must be an array"],
		[{"name": "x"}, ".cycle: must be a non-empty array"],
		[{"name": "x", "cycle": []}, ".cycle: must be a non-empty array"],
		[{"name": "x", "cycle": RIFLE}, ".cycle: must be a non-empty array"],
		[{"name": "x", "cycle": [1]}, ".cycle: must be a non-empty array"],
		[{"name": "x", "cycle": [RIFLE], "branches": [RIFLE]}, ".branches: must be an object"],
		[{"name": "x", "cycle": [RIFLE], "branches": {RIFLE: "c"}},
			".branches.rifleman: must be \"a\" or \"b\""],
		[{"name": "x", "cycle": [RIFLE], "cap_floor": "30", "on_blocked": "skip"},
			".cap_floor: must be a number"],
		[{"name": "x", "cycle": [RIFLE], "cap_floor": 30}, "cap_floor and on_blocked go together"],
		[{"name": "x", "cycle": [RIFLE], "on_blocked": "skip"},
			"cap_floor and on_blocked go together"],
		[{"name": "x", "cycle": [RIFLE], "cap_floor": 30, "on_blocked": "wait"},
			".on_blocked: must be one of"],
		[{"name": "x", "cycle": [RIFLE], "cap_floor": 30, "on_blocked": "skip", "fallback": RIFLE},
			".fallback: only with on_blocked \"fallback\""],
		[{"name": "x", "cycle": [RIFLE], "cap_floor": 30, "on_blocked": "skip", "fallback_max": 1},
			".fallback_max: only with on_blocked \"fallback\""],
		[{"name": "x", "cycle": [RIFLE], "fallback": RIFLE, "fallback_max": 1},
			".fallback: only with on_blocked \"fallback\""],
		[{"name": "x", "cycle": [RIFLE], "cap_floor": 30, "on_blocked": "fallback",
			"fallback_max": 1}, ".fallback: required by on_blocked \"fallback\""],
		[{"name": "x", "cycle": [RIFLE], "cap_floor": 30, "on_blocked": "fallback",
			"fallback": RIFLE}, ".fallback_max: required by on_blocked \"fallback\""],
		[_with({"name": "x", "cycle": [RIFLE]}, fb, {"fallback": ""}), ".fallback: must be a tower id"],
		[_with({"name": "x", "cycle": [RIFLE]}, fb, {"fallback": 3}), ".fallback: must be a tower id"],
		[_with({"name": "x", "cycle": [RIFLE]}, fb, {"fallback_max": 1.5}),
			".fallback_max: must be an integer >= 0"],
		[_with({"name": "x", "cycle": [RIFLE]}, fb, {"fallback_max": -1}),
			".fallback_max: must be an integer >= 0"],
		[_with({"name": "x", "cycle": [RIFLE]}, fb, {"fallback_max": "3"}),
			".fallback_max: must be an integer >= 0"],
		[{"name": "x", "cycle": [RIFLE], "buy_sanity": "yes"}, ".buy_sanity: must be a bool"],
		["x", "strategies[1]: must be an object"],
	]
	for c: Array in cases:
		var what := JSON.stringify(c[0])
		var t := _parse([{"name": "good", "cycle": [RIFLE]}, c[0]])
		_assert_error(t, c[1], what)
		# The bad row is not played; the good one is kept.
		assert_array(t.names).override_failure_message(what).is_equal(["good"])
	# The same rows made valid are accepted (the cases above fail for their stated reason).
	var ok := _parse([{"name": "good", "cycle": [RIFLE]},
		_with({"name": "x", "cycle": [RIFLE], "buy_sanity": true, "about": "y", "prefix": [HARP],
			"branches": {RIFLE: "b"}}, fb, {"fallback_max": 0}),
		{"name": "y", "cycle": [RIFLE, SIGN], "cap_floor": 60.5, "on_blocked": "skip"}])
	assert_array(ok.errors).is_empty()
	assert_array(ok.names).is_equal(["good", "x", "y"])


func _with(a: Dictionary, b: Dictionary, c: Dictionary) -> Dictionary:
	var d := a.duplicate()
	d.merge(b, true)
	d.merge(c, true)
	return d


## A name is a --strategies= item, a log file name part and a golden key: the whole string
## must match ^[a-z][a-z0-9_]*$.
func test_names_must_match_the_pattern_as_a_whole_string() -> void:
	for bad: String in ["a,b", "a/b", " ", "", "Mundane", "a\n", "1a", "_a", "a-b", "a b"]:
		var t := _parse([{"name": bad, "cycle": [RIFLE]}])
		_assert_error(t, ".name: must match", JSON.stringify(bad))
		assert_array(t.names).override_failure_message(JSON.stringify(bad)).is_empty()
	for good: String in ["ok_1", "a", "light2"]:
		var t := _parse([{"name": good, "cycle": [RIFLE]}])
		assert_array(t.errors).override_failure_message(good).is_empty()
		assert_array(t.names).is_equal([good])


func test_bad_roots_are_rejected() -> void:
	var row := {"name": "a", "cycle": [RIFLE]}
	_assert_error(Table.parse_text("{\"strategies\": ["), "invalid JSON at line", "bad JSON")
	_assert_error(Table.parse_text("[]"), "root must be an object", "array root")
	_assert_error(Table.parse_text(JSON.stringify({"tunables": TUNABLES, "strategies": [row],
		"extra": 1})), "unknown key \"extra\"", "unknown root key")
	_assert_error(Table.parse_text(JSON.stringify({"tunables": TUNABLES})),
		"strategies: must be an array", "no strategies")
	_assert_error(Table.parse_text(JSON.stringify({"tunables": TUNABLES, "strategies": {}})),
		"strategies: must be an array", "strategies not an array")
	var empty := _parse([])
	_assert_error(empty, "strategies: must name at least one strategy", "empty list")
	assert_array(empty.names).is_empty()
	var dup := "{\"tunables\": %s, \"strategies\": [%s], \"tunables\": %s}" \
		% [JSON.stringify(TUNABLES), JSON.stringify(row), JSON.stringify(TUNABLES)]
	_assert_error(Table.parse_text(dup), "duplicate key", "duplicate root key")
	var dup_row := "{\"tunables\": %s, \"strategies\": [{\"name\": \"a\", \"cycle\": [\"%s\"], \"name\": \"b\"}]}" \
		% [JSON.stringify(TUNABLES), RIFLE]
	_assert_error(Table.parse_text(dup_row), "duplicate key", "duplicate row key")


func test_bad_tunables_are_rejected() -> void:
	var row := {"name": "a", "cycle": [RIFLE]}
	_assert_error(Table.parse_text(JSON.stringify({"strategies": [row]})),
		"tunables: must be an object", "no tunables")
	_assert_error(_parse([row], [5, 4]), "tunables: must be an object", "tunables array")
	_assert_error(_parse([row], {"flare_min_live": 4}), "tunables.build_first: missing",
		"missing build_first")
	_assert_error(_parse([row], {"build_first": 5}), "tunables.flare_min_live: missing",
		"missing flare_min_live")
	_assert_error(_parse([row], {"build_first": 5, "flare_min_live": 4, "speed": 1}),
		"tunables: unknown key \"speed\"", "unknown tunable")
	for bad: Variant in [2.5, -1, "5", true, null]:
		_assert_error(_parse([row], {"build_first": bad, "flare_min_live": 4}),
			"tunables.build_first: must be an integer >= 0", "build_first " + str(bad))
		_assert_error(_parse([row], {"build_first": 5, "flare_min_live": bad}),
			"tunables.flare_min_live: must be an integer >= 0", "flare_min_live " + str(bad))
	# 0 and an integral float are counts.
	var zero := _parse([row], {"build_first": 0, "flare_min_live": 3.0})
	assert_array(zero.errors).is_empty()
	assert_int(zero.flare_min_live).is_equal(3)


# --- loader: tower ids (validation 6) -----------------------------------------------------------

func test_check_towers_names_unknown_ids_occult_fallbacks_and_all_occult_skip_cycles() -> void:
	var fb := {"cap_floor": 30, "on_blocked": "fallback", "fallback_max": 1}
	var t := _parse([
		{"name": "p", "prefix": ["nosuch_p"], "cycle": [RIFLE]},
		{"name": "c", "cycle": ["nosuch_c"]},
		{"name": "b", "cycle": [RIFLE], "branches": {"nosuch_b": "a"}},
		_with({"name": "f", "cycle": [SIGN]}, fb, {"fallback": "nosuch_f"}),
		_with({"name": "o", "cycle": [SIGN]}, fb, {"fallback": "necronomicon_reader"}),
		{"name": "s", "cycle": [SIGN, "necronomicon_reader"], "cap_floor": 60, "on_blocked": "skip"},
		{"name": "fine", "cycle": [SIGN, RIFLE], "cap_floor": 60, "on_blocked": "skip"},
	])
	assert_array(t.errors).is_empty()
	var errs := t.check_towers(real_config())
	assert_array(errs).contains_exactly_in_any_order([
		"strategy p: unknown tower \"nosuch_p\"",
		"strategy c: unknown tower \"nosuch_c\"",
		"strategy b: unknown tower \"nosuch_b\"",
		"strategy f: unknown tower \"nosuch_f\"",
		"strategy o: fallback \"necronomicon_reader\" is occult",
		"strategy s: a \"skip\" cycle needs a non-occult tower",
	])


# --- interpreter: rows it is given ---------------------------------------------------------------

func test_order_plays_prefix_once_then_the_cycle_of_a_new_row() -> void:
	var t := _parse([{"name": "probe", "prefix": [HARP], "cycle": [RIFLE, SIGN]}])
	var st := _strat(t)
	var sim := _sim()
	var got: Array = []
	for i in 6:
		got.append(st.order("probe", i, sim, {}))
	assert_array(got).is_equal([HARP, RIFLE, SIGN, RIFLE, SIGN, RIFLE])


## A "fallback" row returns its own fallback tower for a blocked occult item while the run
## has fewer than fallback_max of it, then "" (save); unblocked it returns the item.
func test_fallback_row_uses_its_fallback_tower_until_fallback_max() -> void:
	var cfg := _fresh()
	var sim := _sim(0, cfg)
	var t := _parse([
		{"name": "fb", "cycle": [SIGN], "cap_floor": 45, "on_blocked": "fallback",
			"fallback": HARP, "fallback_max": 2},
		{"name": "fb0", "cycle": [SIGN], "cap_floor": 45, "on_blocked": "fallback",
			"fallback": HARP, "fallback_max": 0},
		{"name": "free", "cycle": [SIGN]},
	])
	var st := _strat(t, cfg)
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap - 44.0  # blocked at 45
	assert_str(st.order("fb", 0, sim, {})).is_equal(HARP)
	assert_str(st.order("fb", 0, sim, {HARP: 1, RIFLE: 5})).is_equal(HARP)
	assert_str(st.order("fb", 0, sim, {HARP: 2})).is_equal("")
	assert_str(st.order("fb0", 0, sim, {})).is_equal("")
	assert_str(st.order("free", 0, sim, {})).is_equal(SIGN)  # no cap_floor: no guard
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap - 45.0  # exactly 45: allowed
	assert_str(st.order("fb", 0, sim, {HARP: 2})).is_equal(SIGN)


## The same blocked occult item: a "skip" row's act() moves past it and builds the next item;
## a "fallback" row out of fallback towers saves (no build, the index stays).
func test_skip_row_moves_past_a_blocked_item_and_a_fallback_row_does_not() -> void:
	var cfg := _fresh()
	var t := _parse([
		{"name": "sk", "cycle": [SIGN, HARP], "cap_floor": 45, "on_blocked": "skip"},
		{"name": "fb", "cycle": [SIGN, HARP], "cap_floor": 45, "on_blocked": "fallback",
			"fallback": RIFLE, "fallback_max": 0},
	])
	var sim := _sim(cfg.towers[HARP].cost, cfg)
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap - 44.0
	var built := {}
	assert_str(_strat(t, cfg).order("sk", 0, sim, built)).is_equal(SIGN)  # act() skips it
	var idx: int = _strat(t, cfg).act(sim, "sk", 0, built)
	assert_int(sim.state.towers.size()).is_equal(1)
	assert_str(sim.state.towers[0].def.id).is_equal(HARP)
	assert_dict(built).is_equal({HARP: 1})
	# Sign skipped (1), harpooner built (2), the next Sign skipped (3), no gold for item 3.
	assert_int(idx).is_equal(3)
	var fsim := _sim(cfg.towers[HARP].cost, cfg)
	var fbuilt := {}
	idx = _strat(t, cfg).act(fsim, "fb", 0, fbuilt)
	assert_int(idx).is_equal(0)
	assert_int(fsim.state.towers.size()).is_equal(0)
	assert_dict(fbuilt).is_empty()


## cap_floor is the row's: delta leaving exactly the floor passes, half a point less fails; a
## delta <= 0 passes; a row without cap_floor and an unknown name have no guard.
func test_cap_floor_boundary_comes_from_the_row() -> void:
	var t := _parse([
		{"name": "g", "cycle": [RIFLE], "cap_floor": 45, "on_blocked": "skip"},
		{"name": "none", "cycle": [RIFLE]},
	])
	var st := _strat(t)
	var sim := _sim()
	var cap := sim.state.sanity_cap
	assert_bool(st.cap_allows(sim, "g", cap - 45.0)).is_true()
	assert_bool(st.cap_allows(sim, "g", cap - 44.5)).is_false()
	assert_bool(st.cap_allows(sim, "g", 0.0)).is_true()
	assert_bool(st.cap_allows(sim, "g", -5.0)).is_true()
	assert_bool(st.cap_allows(sim, "none", cap)).is_true()
	assert_bool(st.cap_allows(sim, "nosuch", cap)).is_true()
	# The shipped floors do not leak in: a row named like a shipped one plays its own floor.
	var renamed := _parse([{"name": "occult", "cycle": [RIFLE], "cap_floor": 80,
		"on_blocked": "skip"}])
	assert_bool(_strat(renamed).cap_allows(sim, "occult", cap - 30.0)).is_false()
	assert_bool(_strat(renamed).cap_allows(sim, "occult", cap - 80.0)).is_true()


## L3 picks come from the row's branches; a tower missing from them stays at L2 unless
## --branch= names it, and the override leaves the row unchanged.
func test_branch_picks_come_from_the_row() -> void:
	var t := _parse([{"name": "bp", "cycle": [RIFLE], "branches": {RIFLE: "b"}}])
	var sim := _sim()
	var rifle := _place(sim, RIFLE, 1)
	assert_array(_strat(t).next_upgrade(sim, "bp")).is_equal([rifle.id, "b"])
	var hsim := _sim()
	var harp := _place(hsim, HARP, 1)
	assert_array(_strat(t).next_upgrade(hsim, "bp")).is_empty()
	var st := _strat(t)
	st.branch_override = {HARP: "a"}
	assert_array(st.next_upgrade(hsim, "bp")).is_equal([harp.id, "a"])
	assert_dict(t.row("bp").branches).is_equal({RIFLE: "b"})


## build_first is read from the table: with 2 the bot upgrades after its second tower; with a
## value above what the gold buys it never upgrades.
func test_build_first_from_the_table_decides_when_upgrades_start() -> void:
	var rows := [{"name": "r", "cycle": [RIFLE], "branches": {RIFLE: "a"}}]
	var cfg := real_config()
	var oil := cfg.economy.oil
	var topup := maxi(0, cfg.economy.flare.cost_oil - oil.start) * oil.price
	var gold: int = 2 * cfg.towers[RIFLE].cost + cfg.towers[RIFLE].levels[1].upgrade_cost + topup
	var two := _sim(gold)
	_strat(_parse(rows, {"build_first": 2, "flare_min_live": 4}), null, false).act(two, "r", 0, {})
	assert_array(two.state.towers.map(func(x: SimTower) -> int: return x.level)).is_equal([1, 0])
	var many := _sim(gold)
	_strat(_parse(rows, {"build_first": 50, "flare_min_live": 4}), null, false).act(many, "r", 0, {})
	assert_int(many.state.towers.size()).is_greater_equal(2)
	for x: SimTower in many.state.towers:
		assert_int(x.level).is_equal(0)


## flare_min_live is read from the table.
func test_flare_min_live_from_the_table_sets_the_flare_threshold() -> void:
	var rows := [{"name": "r", "cycle": [RIFLE]}]
	var at2 := _night_with_live(2)
	_strat(_parse(rows, {"build_first": 5, "flare_min_live": 2})).night_flare(at2)
	assert_array(at2.state.command_log.back()).is_equal([at2.state.tick, "fire_flare"])
	var at3 := _night_with_live(2)
	var n := at3.state.command_log.size()
	_strat(_parse(rows, {"build_first": 5, "flare_min_live": 3})).night_flare(at3)
	assert_int(at3.state.command_log.size()).is_equal(n)


# --- harness: a bad table, a new row, the run cap ------------------------------------------------

## A bad strategies.json makes the bot print its errors and quit 1 before any run (it used to
## assert in default(), which hangs a headless run).
func test_a_table_with_errors_quits_1_before_any_run() -> void:
	var raw := _shipped_json()
	raw.strategies[0]["colour"] = "red"
	var bad := Table.parse_text(JSON.stringify(raw))
	assert_array(bad.errors).is_not_empty()
	var b := _run_main(bad, ["--seeds=1"])
	assert_int(b.get("_test_exit")).is_equal(1)
	assert_array(b.get("_test_played")).is_empty()
	assert_str(b.get("_test_errors")).contains("strategies.json errors:")
	assert_str(b.get("_test_errors")).contains("colour")
	b = _run_main(Table.load_file("res://no/such/strategies.json"), ["--seeds=1"])
	assert_int(b.get("_test_exit")).is_equal(1)
	assert_array(b.get("_test_played")).is_empty()
	assert_str(b.get("_test_errors")).contains("file not found")


func test_a_table_with_an_unknown_tower_quits_1_before_any_run() -> void:
	var t := _parse([{"name": "a", "cycle": [RIFLE]}, {"name": "z", "cycle": ["nosuch"]}])
	assert_array(t.errors).is_empty()
	var b := _run_main(t, ["--seeds=1", "--strategies=a"])
	assert_int(b.get("_test_exit")).is_equal(1)
	assert_array(b.get("_test_played")).is_empty()
	assert_str(b.get("_test_errors")).contains("strategies.json errors:")
	assert_str(b.get("_test_errors")).contains("nosuch")


## A row added to the data is a strategy: --strategies= accepts it and the bot plays it.
func test_a_new_row_is_played_by_strategies_flag_and_by_default() -> void:
	var raw := _shipped_json()
	raw.strategies.append({"name": "probe", "cycle": [RIFLE, HARP],
		"branches": {RIFLE: "a", HARP: "a"}})
	var t := Table.parse_text(JSON.stringify(raw))
	assert_array(t.errors).is_empty()
	var b := _run_main(t, ["--seeds=2", "--strategies=probe"])
	assert_int(b.get("_test_exit")).is_equal(0)
	assert_array(b.get("_test_played")).is_equal(["probe", "probe"])
	b = _run_main(t, ["--seeds=1"])
	assert_int(b.get("_test_exit")).is_equal(0)
	assert_array(b.get("_test_played")).is_equal(SHIPPED_NAMES + ["probe"])


## The run cap is TICKS_PER_WAVE per wave of the loaded config: a data dir with 3 waves gives
## a different cap than the shipped 5; `_max_ticks` (golden cuts) wins.
func test_run_cap_follows_the_wave_count_of_the_config() -> void:
	var per_wave: int = _bot(real_config()).get_script().get_script_constant_map()["TICKS_PER_WAVE"]
	assert_int(per_wave).is_equal(10800)
	var five := real_config().waves.waves.size()
	assert_int(_bot(real_config()).call("_tick_cap")).is_equal(per_wave * five)
	var cfg3 := _waves3_config()
	assert_int(cfg3.waves.waves.size()).is_equal(3)
	assert_int(_bot(cfg3).call("_tick_cap")).is_equal(per_wave * 3)
	assert_int(_bot(cfg3).call("_tick_cap")).is_not_equal(_bot(real_config()).call("_tick_cap"))
	var cut := _bot(cfg3)
	cut.set("_max_ticks", 777)
	assert_int(cut.call("_tick_cap")).is_equal(777)


## res://data copied to user:// with waves.json cut to its first 3 waves, loaded from there.
func _waves3_config() -> GameConfig:
	DirAccess.make_dir_recursive_absolute(WAVES3_DIR)
	for file in DirAccess.get_files_at("res://data"):
		if not file.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("res://data".path_join(file))
		if file == "waves.json":
			var w: Dictionary = JSON.parse_string(text)
			assert_int((w.waves as Array).size()).is_greater(3)
			w.waves = (w.waves as Array).slice(0, 3)
			text = JSON.stringify(w)
		var f := FileAccess.open(WAVES3_DIR.path_join(file), FileAccess.WRITE)
		f.store_string(text)
		f.close()
	var r := GameConfig.load_from_dir(WAVES3_DIR)
	for file in DirAccess.get_files_at(WAVES3_DIR):
		DirAccess.remove_absolute(WAVES3_DIR.path_join(file))
	DirAccess.remove_absolute(WAVES3_DIR)
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config
