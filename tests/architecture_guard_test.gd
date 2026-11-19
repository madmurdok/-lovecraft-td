class_name ArchitectureGuardTest
extends GdUnitTestSuite
## LT-65 architecture guards beyond the sim boundary (docs/design/LT-65-architecture-review.md
## section 4). Static scans reusing SimBoundaryTest's `_gd_files` and `_code_lines` (comments
## and strings blanked). Each guard lands in the block that makes it pass.

const SUPPORT_DIR := "res://tests/support/"


## G8 (LT-74, B1): a Game is built in tests/ only by tests/support/ (GameFixture).
func test_g8_game_is_built_only_by_the_shared_fixture() -> void:
	var scan := SimBoundaryTest.new()
	var re := RegEx.create_from_string("\\bGame\\.new\\(")
	var hits: Array[String] = []
	var scanned := 0
	for f in scan._gd_files("res://tests"):
		if f.begins_with(SUPPORT_DIR):
			continue
		scanned += 1
		for entry: Array in scan._code_lines(FileAccess.get_file_as_string(f)):
			if re.search(entry[1]) != null:
				hits.append("%s:%d" % [f, entry[0]])
	scan.free()
	assert_int(scanned).is_greater(20)  # the scan really walked tests/
	assert_array(hits).override_failure_message(
		"Game.new() outside tests/support/ (use GameFixture.make_game): " + ", ".join(hits)
	).is_empty()



## G1 (LT-76, B2): no rule copies outside the sim. ui/, scenes/ and tools/ name none of the
## light / shadow multipliers, the flare's oil cost (any `.cost_oil`) or speed, the oil
## cap, sanity_factor(, in_cast_radius( or a flare burn rebuilt from flare_seconds() ticks
## (comments and strings blanked, continuation lines joined); they ask TowerRules,
## LightRules or the Simulation facade instead. The denylist is pinned (LT-65 §4, widened
## by the LT-76 review F6).
const G1_DIRS := ["res://ui", "res://scenes", "res://tools"]
const G1_DENY := "\\.(occult_power_mult|mundane_fire_interval_mult|mundane_ignore_miss" \
	+ "|mundane_miss_chance_add|enemy_speed_mult|cost_oil)\\b|oil\\.cap\\b" \
	+ "|sanity_factor\\(|in_cast_radius\\(|ticks\\(\\s*(\\w+\\.)?flare_seconds\\("


func test_g1_no_rule_copies_outside_the_sim() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var scanned := 0
	for dir: String in G1_DIRS:
		for f in scan._gd_files(dir):
			scanned += 1
			hits.append_array(_find_joined(scan, f, FileAccess.get_file_as_string(f), G1_DENY))
	var probes := ["x = eco.flare.cost_oil", "var f := eco.flare\nx = f.cost_oil",
		"x = maxi(left, SimTime.ticks(\n\tsim.flare_seconds()))", "x = eco.oil.cap",
		"x = cfg.economy.beam \\\n\t.occult_power_mult"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += _find_joined(scan, "probe.gd", p, G1_DENY).size()
	var near := _find_joined(scan, "near.gd", "x = sim.flare_cost_oil()\ny = sim.oil_cap()",
		G1_DENY)
	scan.free()
	assert_int(scanned).is_greater(20)  # the scan really walked ui/, scenes/ and tools/
	assert_int(probe_hits).is_equal(probes.size())  # each copy form is caught
	assert_array(near).is_empty()  # the facade calls are not
	assert_array(hits).override_failure_message(
		"rule copy outside sim/ (use TowerRules / LightRules / the Simulation facade): "
		+ ", ".join(hits)).is_empty()


## G2 (LT-35, B4): pixels only in the view. The pixel scale and the board origin (`CELL`,
## `BOARD_ORIGIN`, `ORIGIN`; `/ CELL` picking included) are named only in
## scenes/board/board_view.gd (BoardView). sim/, tools/, scenes/ (the board layers too),
## ui/ and tests/ (but tests/support/) ask the view: cell_at_screen, cell_to_world,
## cells_to_px, world_rect.
const G2_DIRS := ["res://sim", "res://tools", "res://scenes", "res://ui", "res://tests"]
const G2_HOME := "res://scenes/board/board_view.gd"
const G2_DENY := "\\b(CELL|BOARD_ORIGIN|ORIGIN)\\b"


func test_g2_pixels_only_in_the_view() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var scanned := 0
	var home_hits := 0
	for dir: String in G2_DIRS:
		for f in scan._gd_files(dir):
			if f.begins_with(SUPPORT_DIR):
				continue
			var found := _find_joined(scan, f, FileAccess.get_file_as_string(f), G2_DENY)
			if f == G2_HOME:
				home_hits = found.size()
				continue
			scanned += 1
			hits.append_array(found)
	var probes := ["p = cells * Board.CELL", "board.position = Game.BOARD_ORIGIN",
		"r = CELL * 0.25", "c = Vector2i(floori(p.x / CELL), 0)", "o = BoardView.ORIGIN",
		"x = Rect2(o, Vector2(\n\tBoard.CELL, 1))"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += _find_joined(scan, "probe.gd", p, G2_DENY).size()
	var clean := _find_joined(scan, "near.gd",
		"r = view.cells_to_px(MARK_SLOW_CELLS)\np = view.cell_to_world(c)\nb = view.world_rect()",
		G2_DENY)
	scan.free()
	assert_int(scanned).is_greater(100)  # sim/, tools/, scenes/, ui/ and tests/ were walked
	assert_int(home_hits).is_greater(0)  # the view itself holds them
	assert_int(probe_hits).is_equal(probes.size())  # each pixel form is caught
	assert_array(clean).is_empty()  # the view calls are not
	assert_array(hits).override_failure_message(
		"pixel scale or board origin outside BoardView (ask the view): " + ", ".join(hits)) \
		.is_empty()


## G3 (LT-76, LT-77, LT-35): one cell centre. Under sim/, tools/, scenes/ and ui/ a
## hand-written centre (`.x + 0.5`, `0.5 + .y`, `Vector2(c) + Vector2(0.5, 0.5)`,
## continuation lines joined) appears only in sim/rules/square_grid.gd (SquareGrid.centre).
## B4: the scan covers BoardView and the board layers (scenes/), which take centres from
## GridTopology.centre and map them with BoardView.cell_to_world.
const G3_DIRS := ["res://sim", "res://tools", "res://scenes", "res://ui"]
const G3_HOME := "res://sim/rules/square_grid.gd"
const G3_CENTRE := "\\.(x|y)\\s*\\+\\s*0\\.5\\b|\\b0\\.5\\s*\\+\\s*[\\w.]*\\.(x|y)\\b" \
	+ "|\\+\\s*Vector2\\(\\s*0\\.5\\s*,\\s*0\\.5\\s*\\)"


func test_g3_one_cell_centre() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var home_hits := 0
	var view_scanned := false
	for dir: String in G3_DIRS:
		for f in scan._gd_files(dir):
			view_scanned = view_scanned or f == G2_HOME
			var found := _find_joined(scan, f, FileAccess.get_file_as_string(f), G3_CENTRE)
			if f == G3_HOME:
				home_hits = found.size()
			else:
				hits.append_array(found)
	var probes := ["p = Vector2(cell) + Vector2(0.5, 0.5)", "p = Vector2(0.5 + c.x, 1)",
		"p = Vector2(cell.x\n\t+ 0.5, cell.y)",
		"p = view.cell_to_world(Vector2(cell) + Vector2(0.5, 0.5))"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += _find_joined(scan, "probe.gd", p, G3_CENTRE).size()
	scan.free()
	assert_int(probe_hits).is_equal(probes.size())  # each centre form is caught
	assert_int(home_hits).is_equal(2)  # the rule itself: x and y
	assert_bool(view_scanned).is_true()  # BoardView is in the scope
	assert_array(hits).override_failure_message(
		"cell centre written by hand (use GridTopology.centre): " + ", ".join(hits)).is_empty()


## G7 (LT-84, B9): selection via the model. Under ui/, scenes/ and tools/ nothing assigns the
## board's selection fields (`selected_cell / _range / _glyph / _cast =`, the 21 UI writes
## LT-65 #12 found) nor a SelectionModel field outside scenes/board/selection_model.gd: the
## panels call its methods, which emit `changed`. Forms caught (LT-84 F2): `selection.cell =`,
## compound `selection.range_cells += 1`, an alias (`var s := game.selection` or any name
## typed `: SelectionModel`) then `s.cell = c`, the private `_assign(` and `selection.set(`.
## Comparisons (`==`, `!=`, `<=`, `>=`) are reads and pass.
const G7_DIRS := ["res://ui", "res://scenes", "res://tools"]
const G7_HOME := "res://scenes/board/selection_model.gd"
const G7_WRITE_OP := "\\s*[-+*/%|&^]?=(?!=)"
const G7_DENY := "\\bselected_(cell|range|glyph|cast)" + G7_WRITE_OP \
	+ "|\\bselection\\.(cell|range_cells|glyph|cast)" + G7_WRITE_OP \
	+ "|\\bselection\\.(set|_assign)\\(|\\b_assign\\("
## A name that holds a SelectionModel: typed `: SelectionModel` (var, parameter) or `var x =
## <anything>.selection` / `SelectionModel.new()`.
const G7_ALIAS := "\\b(\\w+)\\s*:\\s*SelectionModel\\b" \
	+ "|\\bvar\\s+(\\w+)\\s*:?=\\s*(?:[\\w.]*\\.)?selection\\s*$" \
	+ "|\\b(\\w+)\\s*:?=\\s*SelectionModel\\.new\\("


## `file:line: match` for every selection write in `text`: G7_DENY plus a field write through
## any alias of a SelectionModel found in the same file.
func _g7_hits(scan: SimBoundaryTest, file: String, text: String) -> Array[String]:
	var alias_re := RegEx.create_from_string(G7_ALIAS)
	var aliases: Array[String] = []
	for st: Array in _statements(scan, text):
		for m in alias_re.search_all(st[1]):
			for g in range(1, 4):
				var n := m.get_string(g)
				if not n.is_empty() and n != "selection" and not aliases.has(n):
					aliases.append(n)
	var hits := _find_joined(scan, file, text, G7_DENY)
	if not aliases.is_empty():
		hits.append_array(_find_joined(scan, file, text,
			"\\b(" + "|".join(aliases) + ")\\.(cell|range_cells|glyph|cast)" + G7_WRITE_OP))
	return hits


func test_g7_selection_is_written_only_through_the_model() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var home_scanned := false
	for dir: String in G7_DIRS:
		for f in scan._gd_files(dir):
			if f == G7_HOME:
				home_scanned = true
				continue
			hits.append_array(_g7_hits(scan, f, FileAccess.get_file_as_string(f)))
	scan.free()
	assert_bool(home_scanned).is_true()  # the model is in the scope
	assert_array(hits).override_failure_message(
		"selection written outside SelectionModel: " + ", ".join(hits)).is_empty()


## The guard fires on planted violations (each source string is one violation) and not on
## reads, comparisons, method calls or other objects' `.cell`.
func test_g7_catches_planted_writes_and_passes_reads() -> void:
	var scan := SimBoundaryTest.new()
	var planted := {
		"board field": "game.board.selected_cell = c",
		"board field spaced": "board.selected_range=0.0",
		"board glyph": "b.selected_glyph = \"\"",
		"board cast compound": "b.selected_cast += \"x\"",
		"direct cell": "game.selection.cell = c",
		"direct range": "game.selection.range_cells = r",
		"direct compound": "game.selection.range_cells += 1.0",
		"direct compound minus": "selection.range_cells -= 1.0",
		"alias var": "var s = game.selection\ns.cell = c",
		"alias inferred": "var sel := board.selection\nsel.glyph = \"R\"",
		"alias compound": "var sel := board.selection\nsel.range_cells *= 2.0",
		"alias typed var": "var m: SelectionModel = make()\nm.cast = \"light\"",
		"alias typed param": "func f(m: SelectionModel, c: Vector2i) -> void:\n\tm.cell = c",
		"alias new": "var m := SelectionModel.new()\nm.cell = c",
		"alias multiline": "var s := game.selection\ns.range_cells \\\n\t= 3.0",
		"private _assign": "game.selection._assign(c, 0.0, \"\", \"\")",
		"bare _assign": "_assign(c, 0.0, \"\", \"\")",
		"set()": "game.selection.set(\"cell\", c)",
	}
	var missed: Array[String] = []
	for k: String in planted:
		if _g7_hits(scan, "probe.gd", planted[k]).is_empty():
			missed.append(k)
	var reads := {
		"compare": "if game.board.selected_range != r:",
		"equals": "x = sel.cell == c",
		"alias compare": "var s := game.selection\nif s.cell == c and s.range_cells >= 1.0:",
		"alias read": "var s := game.selection\nx = s.cell",
		"alias le": "var s := game.selection\nok = s.range_cells <= 2.0",
		"methods": "game.selection.set_ring(r, cast)\ngame.selection.clear()",
		"other object": "var t := sim.tower_at_cell(c)\nt.cell = c",
		"comment": "# game.selection.cell = c",
		"string": "x = \"selection.cell = c\"",
	}
	var false_hits: Array[String] = []
	for k: String in reads:
		if not _g7_hits(scan, "probe.gd", reads[k]).is_empty():
			false_hits.append(k)
	scan.free()
	assert_array(missed).override_failure_message(
		"G7 did not fire on: " + ", ".join(missed)).is_empty()
	assert_array(false_hits).override_failure_message(
		"G7 fired on a read: " + ", ".join(false_hits)).is_empty()


## G10 (LT-77): one topology. Outside the topology files (sim/rules/*grid*.gd) no
## neighbour arithmetic, board-size loops, bounds test, NEIGHBOURS table or hand-written
## centre-to-centre length: those are GridTopology.neighbours / cells / contains / distance.
const G10_DIRS := ["res://sim", "res://tools", "res://scenes", "res://ui"]
const G10_HOME_DIR := "res://sim/rules/"
const G10_DENY := "Vector2i\\.(LEFT|RIGHT|UP|DOWN)\\b" \
	+ "|\\bfor\\s+\\w+\\s+in\\s+[\\w.]*\\.(width|height)\\b" \
	+ "|\\.in_bounds\\(|\\bNEIGHBOURS\\b" \
	+ "|Vector2\\(\\s*\\w+\\s*-\\s*\\w+\\s*\\)\\.length\\(\\)"


func _is_g10_home(f: String) -> bool:
	return f.begins_with(G10_HOME_DIR) and f.get_file().contains("grid")


func test_g10_one_topology() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var scanned := 0
	var home_scanned := 0
	for dir: String in G10_DIRS:
		for f in scan._gd_files(dir):
			if _is_g10_home(f):
				home_scanned += 1
				continue
			scanned += 1
			hits.append_array(_find_joined(scan, f, FileAccess.get_file_as_string(f), G10_DENY))
	var probes := ["n = c + Vector2i.LEFT", "for x in map.width:", "for y in m.height:",
		"if map.in_bounds(c):", "for d in NEIGHBOURS:", "d = Vector2(a - b).length()",
		"n = c + Vector2i(\n\tVector2i.UP)"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += _find_joined(scan, "probe.gd", p, G10_DENY).size()
	var clean := _find_joined(scan, "near.gd",
		"for c in grid.cells():\nx = grid.neighbours(c)\nd = grid.distance(a, b)", G10_DENY)
	scan.free()
	assert_int(scanned).is_greater(40)  # sim/, tools/, scenes/ and ui/ really were walked
	assert_int(home_scanned).is_equal(2)  # grid_topology.gd and square_grid.gd are the exempt ones
	assert_int(probe_hits).is_equal(probes.size())  # each form is caught
	assert_array(clean).is_empty()  # the topology calls are not
	assert_array(hits).override_failure_message(
		"grid geometry outside the topology files (use GridTopology): " + ", ".join(hits)) \
		.is_empty()


## G11 (LT-77): the sim is trig-free (determinism: no libm sin/cos in replayed code). Code
## lines only (comments and strings blanked), a superset of beam_test's raw-text TRIG check
## (adds deg_to_rad and a bare angle(); that test stays as the LT-26 beam proof).
const G11_DENY := "\\b(sin|cos|tan|atan2?|asin|acos|deg_to_rad|rotated|angle)\\("


func test_g11_the_sim_is_trig_free() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var files: Array[String] = scan._gd_files("res://sim")
	for f in files:
		hits.append_array(scan._find(f, scan._code_lines(FileAccess.get_file_as_string(f)),
			G11_DENY))
	var probes := ["a = sin(t)", "a = cos(t)", "a = atan2(y, x)", "a = atan(x)",
		"a = deg_to_rad(d)", "v = v.rotated(1.0)", "a = v.angle()", "a = tan(x)",
		"a = asin(x)", "a = acos(x)"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += scan._find("probe.gd", scan._code_lines(p), G11_DENY).size()
	var clean := scan._find("near.gd", scan._code_lines("x = half_angle(y)\nz = sqrt(w)"),
		G11_DENY)
	scan.free()
	assert_int(files.size()).is_greater(20)
	assert_int(probe_hits).is_equal(probes.size())
	assert_array(clean).is_empty()
	assert_array(hits).override_failure_message(
		"trig in sim/ (cross-platform determinism): " + ", ".join(hits)).is_empty()


## G6 (LT-78, B8): the UI follows sim events. Four static scans (comments and strings blanked).
## G6a: `drain_events(` is called only in scenes/game.gd, tools/ and tests/ (and defined in
## sim/): one consumer per drain. G6b: every SimEvent.Type is named as `SimEvent.Type.<KEY>`
## in scenes/ or ui/ (a match arm, an if, a REFRESH_ON key), or is pinned in UNCONSUMED_OK
## (the board draws those from state); both ways, so the list stays exact. G6c: no
## `_process` / `_physics_process` in ui/ except PROCESS_OK (decor, gated by set_process:
## B6 pins the gating). G6d: scenes/game.gd calls `.refresh()` on no panel except the one
## `hud.refresh()` in `_ready`.
const G6_DRAIN_HOMES := ["res://scenes/game.gd"]
const UNCONSUMED_OK: PackedStringArray = ["SPAWNED", "ALLY_SUMMONED", "ALLY_GONE"]
const PROCESS_OK: PackedStringArray = ["res://ui/sanity_bar.gd"]
const G6_PROCESS := "\\bfunc\\s+_(physics_)?process\\s*\\("
const G6_REFRESH := "\\b(hud|picker|tower_panel|lighthouse_panel)\\.refresh\\(\\)"


func test_g6a_drain_events_only_in_the_frame_driver() -> void:
	var scan := SimBoundaryTest.new()
	var pattern := "(?<!func )\\bdrain_events\\("
	var hits: Array[String] = []
	var files: Array[String] = []
	for dir in ["res://ui", "res://scenes", "res://sim"]:
		files.append_array(scan._gd_files(dir))
	for f in files:
		if G6_DRAIN_HOMES.has(f):
			continue
		hits.append_array(scan._find(f, scan._code_lines(FileAccess.get_file_as_string(f)),
			pattern))
	var home_hits := scan._find("game.gd", scan._code_lines(
		FileAccess.get_file_as_string(G6_DRAIN_HOMES[0])), pattern)
	var probe := scan._find("probe.gd", scan._code_lines("var e = sim.drain_events()"), pattern)
	var decl := scan._find("decl.gd", scan._code_lines("func drain_events() -> void:"), pattern)
	scan.free()
	assert_int(files.size()).is_greater(20)
	assert_int(home_hits.size()).is_greater(0)  # the home really drains
	assert_int(probe.size()).is_equal(1)
	assert_array(decl).is_empty()  # the declaration is not a call
	assert_array(hits).override_failure_message(
		"drain_events( outside scenes/game.gd, tools/, tests/: " + ", ".join(hits)).is_empty()


func test_g6b_every_sim_event_type_is_consumed_by_the_ui_or_pinned() -> void:
	var scan := SimBoundaryTest.new()
	var named := {}  # key -> first "file:line"
	var files: Array[String] = []
	for dir in ["res://scenes", "res://ui"]:
		files.append_array(scan._gd_files(dir))
	var re := RegEx.create_from_string("\\bSimEvent\\.Type\\.([A-Z_0-9]+)\\b")
	for f in files:
		for entry: Array in scan._code_lines(FileAccess.get_file_as_string(f)):
			for m in re.search_all(entry[1]):
				if not named.has(m.get_string(1)):
					named[m.get_string(1)] = "%s:%d" % [f, entry[0]]
	scan.free()
	var keys: Array = SimEvent.Type.keys()
	assert_int(keys.size()).is_greater(20)
	var unconsumed: Array[String] = []
	var wrongly_pinned: Array[String] = []
	for key: String in keys:
		if not named.has(key) and not UNCONSUMED_OK.has(key):
			unconsumed.append(key)
		if named.has(key) and UNCONSUMED_OK.has(key):
			wrongly_pinned.append("%s (%s)" % [key, named[key]])
	for key in UNCONSUMED_OK:
		assert_bool(keys.has(key)).override_failure_message(
			"UNCONSUMED_OK names no SimEvent.Type: " + key).is_true()
	assert_array(unconsumed).override_failure_message(
		"SimEvent.Type never named in scenes/ or ui/ (consume it or pin it in UNCONSUMED_OK): "
		+ ", ".join(unconsumed)).is_empty()
	assert_array(wrongly_pinned).override_failure_message(
		"in UNCONSUMED_OK but consumed (drop it from the list): " + ", ".join(wrongly_pinned)
	).is_empty()


func test_g6c_no_process_in_ui_except_the_pinned_decor() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var files: Array[String] = scan._gd_files("res://ui")
	for f in files:
		if PROCESS_OK.has(f):
			continue
		hits.append_array(scan._find(f, scan._code_lines(FileAccess.get_file_as_string(f)),
			G6_PROCESS))
	var pinned := scan._find("sanity_bar.gd", scan._code_lines(
		FileAccess.get_file_as_string(PROCESS_OK[0])), G6_PROCESS)
	var probes := scan._find("probe.gd", scan._code_lines(
		"func _process(delta: float) -> void:\nfunc _physics_process(d) -> void:"), G6_PROCESS)
	scan.free()
	assert_int(files.size()).is_greater(8)
	assert_int(pinned.size()).override_failure_message(
		"PROCESS_OK entry has no _process: stale pin").is_equal(1)
	assert_int(probes.size()).is_equal(2)
	assert_array(hits).override_failure_message(
		"_process in ui/ (panels change on events; pin decor in PROCESS_OK): "
		+ ", ".join(hits)).is_empty()


func test_g6d_game_refreshes_no_panel_except_the_hud_in_ready() -> void:
	var scan := SimBoundaryTest.new()
	var text := FileAccess.get_file_as_string("res://scenes/game.gd")
	var code := scan._code_lines(text)
	var hits := scan._find("game.gd", code, G6_REFRESH)
	# The one allowed call lives between `func _ready(` and the next top-level `func`.
	var ready_from := 0
	var ready_to := 0
	for entry: Array in code:
		var line: String = entry[1]
		if ready_from == 0 and line.begins_with("func _ready("):
			ready_from = entry[0]
		elif ready_from != 0 and ready_to == 0 and line.begins_with("func "):
			ready_to = entry[0]
	var outside: Array[String] = []
	var inside := 0
	for h in hits:
		var n := int(h.get_slice(":", 1))
		if n > ready_from and n < ready_to and h.ends_with("hud.refresh()"):
			inside += 1
		else:
			outside.append(h)
	var probe := scan._find("probe.gd", scan._code_lines("tower_panel.refresh()"), G6_REFRESH)
	var near := scan._find("near.gd", scan._code_lines("hud.refresh_readouts()"), G6_REFRESH)
	scan.free()
	assert_int(ready_from).is_greater(0)
	assert_int(ready_to).is_greater(ready_from)
	assert_int(probe.size()).is_equal(1)
	assert_array(near).is_empty()
	assert_int(inside).override_failure_message("hud.refresh() in _ready").is_equal(1)
	assert_array(outside).override_failure_message(
		"panel refresh() in game.gd outside _ready (events drive the panels): "
		+ ", ".join(outside)).is_empty()


## `file:line: match` for `pattern` over the code lines of `text` (comments and strings
## blanked) with each statement joined into one line: a line ending in `\` or with an
## unclosed ( [ { takes the next one; the match is reported at the statement's first line.
func _find_joined(scan: SimBoundaryTest, file: String, text: String,
		pattern: String) -> Array[String]:
	return scan._find(file, _statements(scan, text), pattern)


## The statements of `text` as [first line, joined code] (see _find_joined).
func _statements(scan: SimBoundaryTest, text: String) -> Array:
	var joined := []
	var buf := ""
	var first := 0
	var depth := 0
	for entry: Array in scan._code_lines(text):
		var code: String = entry[1]
		if buf.is_empty():
			first = entry[0]
		var cont := code.strip_edges(false, true).ends_with("\\")
		if cont:
			code = code.strip_edges(false, true).trim_suffix("\\")
		buf += " " + code.strip_edges()
		for ch in code:
			if ch in "([{":
				depth += 1
			elif ch in ")]}":
				depth = maxi(0, depth - 1)
		if not cont and depth == 0:
			joined.append([first, buf])
			buf = ""
	if not buf.is_empty():
		joined.append([first, buf])
	return joined


# --- G4 (LT-80, B5): systems are internal, one writer per state field ----------------------

const G4_SYSTEMS_DIR := "res://sim/core/systems/"
const G4_CONTEXT := "res://sim/core/systems/sim_context.gd"
const G4_FACADE := "res://sim/core/simulation.gd"
const G4_STATE := "res://sim/core/sim_state.gd"
const G4_NEW_DIRS := ["res://sim", "res://scenes", "res://ui", "res://tools"]
const G4A_SIMULATION := "\\bSimulation\\b"
const G4A_PRIVATE := "\\b(?!self\\b)\\w+\\._\\w+"
const G4A_RNG := "\\bRandomNumberGenerator\\.new\\("
## Spec gap: §3.4 says SimContext is the only SimRng.new, §4 bans it under systems/ (where
## sim_context.gd lives). Pinned as the §3.4 intent: allowed in sim_context.gd only, like SimEvent.
const G4A_SIM_RNG := "\\bSimRng\\.new\\("
const G4A_EVENT := "\\bSimEvent\\.new\\("
## A state head: `state` / `_state` (bare member, also `self.`), `ctx.state` / `sim.state` behind
## any chain. The field is the first `.name` after it.
const G4B_HEAD := "(?<![\\w.])(?:self\\.)?(?:(?:\\w+\\.)*_?(?:sim|ctx)\\.)?_?state"
## Writer files per SimState field, relative to res://sim/ (LT-80 §4, owner decision Q4:
## every field). B6-B8 edit only this table.
const G4B_OWNERS := {
	"lighthouse_level": ["core/systems/light_system.gd"],
	"beam_dx": ["core/systems/light_system.gd"],
	"beam_dy": ["core/systems/light_system.gd"],
	"prev_beam_dx": ["core/systems/light_system.gd"],
	"prev_beam_dy": ["core/systems/light_system.gd"],
	"beam_sign": ["core/systems/light_system.gd"],
	"flare_ticks_left": ["core/systems/light_system.gd"],
	"flare_cooldown_ticks": ["core/systems/light_system.gd"],
	"oil": ["core/systems/light_system.gd"],
	"sanity": ["core/systems/sanity_system.gd"],
	"sanity_cap": ["core/systems/sanity_system.gd"],
	"sanity_state": ["core/systems/sanity_system.gd"],
	"gold": ["core/systems/economy_system.gd"],
	"command_log": ["core/systems/sim_context.gd"],
	"phase": ["core/wave_director.gd"],
	"wave_index": ["core/wave_director.gd"],
	"waves_total": ["core/wave_director.gd"],
	"build_ticks_left": ["core/wave_director.gd"],
	"night_luck": ["core/simulation.gd", "core/wave_director.gd"],
	"tick": ["core/simulation.gd"],
	"outcome": ["core/simulation.gd"],
	"lighthouse_hp": ["core/simulation.gd", "core/systems/spawn_system.gd"],
	"map": ["core/simulation.gd"],
	"enemies": ["core/systems/spawn_system.gd"],
	"next_id": ["core/systems/sim_context.gd"],
	"relics": ["core/systems/economy_system.gd"],
	"relic_tokens": ["core/systems/economy_system.gd"],
	"next_token_id": ["core/systems/economy_system.gd"],
	"blasts": ["core/systems/combat_system.gd"],
	"next_blast_id": ["core/systems/combat_system.gd"],
	"allies": ["core/systems/ally_system.gd"],
	"towers": ["core/simulation.gd"],
	"tower_at": ["core/simulation.gd"],
}


## G4a hits of one systems file, `file:line: match`.
func _g4a_hits(scan: SimBoundaryTest, file: String, text: String) -> Array[String]:
	var code := scan._code_lines(text)
	var out: Array[String] = []
	for p: String in [G4A_SIMULATION, G4A_PRIVATE, G4A_RNG]:
		out.append_array(scan._find(file, code, p))
	if file != G4_CONTEXT:
		out.append_array(scan._find(file, code, G4A_EVENT))
		out.append_array(scan._find(file, code, G4A_SIM_RNG))
	return out


## `\b(A|B|...)\.new\(` for the classes declared in the systems dir.
func _g4_new_pattern(scan: SimBoundaryTest) -> String:
	var names: Array[String] = []
	var re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	for f in scan._gd_files(G4_SYSTEMS_DIR):
		var m := re.search(FileAccess.get_file_as_string(f))
		if m != null:
			names.append(m.get_string(1))
	return "\\b(?:%s)\\.new\\(" % "|".join(names)


func test_g4a_systems_are_internal() -> void:
	var scan := SimBoundaryTest.new()
	var files := scan._gd_files(G4_SYSTEMS_DIR)
	var hits: Array[String] = []
	for f in files:
		hits.append_array(_g4a_hits(scan, f, FileAccess.get_file_as_string(f)))
	# near misses: each form is caught, its look-alike is not
	var must_hit := [
		"var s: Simulation", "x = Simulation.new(c, 1)", "_ctx._rng.randf()", "sim._emit(1)",
		"r = SimRng.new(3)", "r = RandomNumberGenerator.new()", "e = SimEvent.new(t, 1, 2, {})"]
	var must_miss := [
		"self._x = 1\nself._f()", "var _ctx: SimContext", "_ctx.emit(t, 1, {})",
		"# Simulation._x\nvar a := 1", "var s := \"Simulation SimEvent.new( a._b\"",
		"var r := _ctx.rng(SimRng.Stream.A)", "var x := SimulationX", "func _f() -> void:"]
	var missed: Array[String] = []
	for s: String in must_hit:
		if _g4a_hits(scan, "probe.gd", s).is_empty():
			missed.append(s)
	var false_hits: Array[String] = []
	for s: String in must_miss:
		false_hits.append_array(_g4a_hits(scan, "probe.gd", s))
	var home := _g4a_hits(scan, G4_CONTEXT, "e = SimEvent.new(t, 1, 2, {})\nr = SimRng.new(3)")
	var home_rng := _g4a_hits(scan, G4_CONTEXT, "r = RandomNumberGenerator.new()")
	# G4a also bans every new() of a system class outside simulation.gd
	var pattern := _g4_new_pattern(scan)
	var new_hits: Array[String] = []
	var scanned := 0
	for dir: String in G4_NEW_DIRS:
		for f in scan._gd_files(dir):
			scanned += 1
			if f != G4_FACADE:
				new_hits.append_array(scan._find(f, scan._code_lines(
					FileAccess.get_file_as_string(f)), pattern))
	var facade_hits := scan._find(G4_FACADE, scan._code_lines(
		FileAccess.get_file_as_string(G4_FACADE)), pattern)
	var new_probe := scan._find("p.gd", scan._code_lines("a = LightSystem.new(c, e)"), pattern)
	var new_near := scan._find("p.gd", scan._code_lines(
		"a = Light.new()\nb = HallucinationSystem.new()\nvar s: LightSystem"), pattern)
	scan.free()
	assert_int(files.size()).is_greater_equal(4)
	assert_int(scanned).is_greater(40)
	assert_array(missed).override_failure_message("G4a misses: " + ", ".join(missed)).is_empty()
	assert_array(false_hits).override_failure_message("G4a near-miss hit: " + ", ".join(false_hits)) \
		.is_empty()
	assert_array(home).is_empty()  # sim_context.gd is the one place SimEvent.new / SimRng.new live
	assert_int(home_rng.size()).is_equal(1)  # but not even there a raw RandomNumberGenerator
	assert_array(facade_hits).is_not_empty()  # the facade really builds the systems
	assert_int(new_probe.size()).is_equal(1)
	assert_array(new_near).is_empty()  # other classes, and a system outside systems/
	for n in ["SimContext", "LightSystem", "SanitySystem", "EconomySystem", "CombatSystem",
			"AllySystem", "SpawnSystem"]:
		assert_bool(pattern.contains(n)).override_failure_message(n + " not in " + pattern).is_true()
	assert_array(hits).override_failure_message(
		"systems must be internal (no Simulation, no foreign _private, no own RNG, SimEvent.new "
		+ "only in sim_context.gd): " + ", ".join(hits)).is_empty()
	assert_array(new_hits).override_failure_message(
		"a system or SimContext is built outside simulation.gd: " + ", ".join(new_hits)).is_empty()


## The `var` names of sim_state.gd's class body, in file order.
func _g4b_fields(scan: SimBoundaryTest, text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("^var\\s+(\\w+)")
	for entry: Array in scan._code_lines(text):
		var m := re.search(entry[1])
		if m != null:
			out.append(m.get_string(1))
	return out


## Field -> true for every SimState field the text writes: through the state heads and, per
## func, through names bound to the state (`var s := sim.state`, `s: SimState`). Entity writes
## (`t.lit`, `e.hp`) have no state head and are out of scope.
func _g4b_written(scan: SimBoundaryTest, text: String) -> Dictionary:
	var code := scan._code_lines(text)
	var mut := scan._mutators()
	var bind := RegEx.create_from_string(
		"\\bvar\\s+(\\w+)\\s*(?::\\s*SimState\\s*=|:=|=)\\s*(?:self\\.)?(?:\\w+\\.)*_?state\\s*$")
	var typed := RegEx.create_from_string("(\\w+)\\s*:\\s*SimState\\b")
	var state_field := RegEx.create_from_string(
		"^(?:self\\.)?(?:(?:\\w+\\.)*_?(?:sim|ctx)\\.)?_?state\\.(\\w+)")
	var alias_field := RegEx.create_from_string("^(?:self\\.)?\\w+\\.(\\w+)")
	var out := {}
	for s: Dictionary in scan._scopes(code):
		var heads: Array[String] = [G4B_HEAD]
		if s.kind == "func":
			var names: Array[String] = []
			for entry: Array in s.lines:
				var b := bind.search(entry[1])
				if b != null:
					names.append(b.get_string(1))
			for t in typed.search_all(s.lines[0][1]):
				names.append(t.get_string(1))
			if not names.is_empty():
				heads.append("(?<![\\w.])(?:self\\.)?(?:%s)" % "|".join(names))
		for h: String in heads:
			var field_re := state_field if h == G4B_HEAD else alias_field
			for p: String in scan._write_patterns(h, mut):
				var re := RegEx.create_from_string(p)
				for entry: Array in s.lines:
					for m in re.search_all(entry[1]):
						var f := field_re.search(m.get_string())
						if f != null:
							out[f.get_string(1)] = true
	return out


## field -> sorted writer files (relative to res://sim/) over every .gd under res://sim.
func _g4b_writers(scan: SimBoundaryTest) -> Dictionary:
	var writers := {}
	for f in scan._gd_files("res://sim"):
		var rel := f.trim_prefix("res://sim/")
		for field: String in _g4b_written(scan, FileAccess.get_file_as_string(f)):
			if not writers.has(field):
				writers[field] = []
			writers[field].append(rel)
	for field: String in writers:
		writers[field].sort()
	return writers


func test_g4b_one_writer_file_per_state_field() -> void:
	var scan := SimBoundaryTest.new()
	var fields := _g4b_fields(scan, FileAccess.get_file_as_string(G4_STATE))
	var writers := _g4b_writers(scan)
	var wrong: Array[String] = []
	for field in fields:
		var want: Array = G4B_OWNERS.get(field, [])
		var got: Array = writers.get(field, [])
		if want != got:
			wrong.append("%s: written by %s, pinned %s" % [field, got, want])
	var unknown: Array[String] = []
	for field: String in writers:
		if not fields.has(field):
			unknown.append(field)  # a write the scan took for a state field but SimState lacks
	var stale: Array[String] = []
	for field: String in G4B_OWNERS:
		if not fields.has(field):
			stale.append(field)
	scan.free()
	assert_array(fields).contains(["tick", "gold", "command_log", "sanity", "oil", "phase"])
	assert_int(fields.size()).is_equal(G4B_OWNERS.size())
	assert_array(stale).override_failure_message("pinned but not in SimState: %s" % [stale]).is_empty()
	assert_array(unknown).override_failure_message("written, not a SimState field: %s" % [unknown]) \
		.is_empty()
	assert_array(wrong).override_failure_message(
		"state field writers differ from G4B_OWNERS:\n" + "\n".join(wrong)).is_empty()


func test_g4b_scan_hits_each_write_form() -> void:
	var scan := SimBoundaryTest.new()
	var cases := {
		"_state.gold += 1": "gold",
		"self._state.oil = 3": "oil",
		"_ctx.state.command_log.append(e)": "command_log",
		"ctx.state.sanity = clampf(a, 0.0, b)": "sanity",
		"sim.state.phase = P.BUILD": "phase",
		"state.tower_at[c] = 1": "tower_at",
		"_state.relics[\"x\"] += 1": "relics",
		"func f() -> void:\n\tvar s := sim.state\n\ts.night_luck = 1.0": "night_luck",
		"func f() -> void:\n\tvar s: SimState = sim.state\n\ts.towers.append(t)": "towers",
		"func f(st: SimState) -> void:\n\tst.build_ticks_left -= 1": "build_ticks_left",
		"func f() -> void:\n\tvar s := sim.state\n\ts.enemies.clear()": "enemies",
	}
	var missed: Array[String] = []
	for text: String in cases:
		if not _g4b_written(scan, text).has(cases[text]):
			missed.append(text)
	scan.free()
	assert_array(missed).override_failure_message("G4b misses: %s" % [missed]).is_empty()


func test_g4b_scan_skips_near_misses() -> void:
	var scan := SimBoundaryTest.new()
	var near := [
		"var g := _state.gold\nif _state.gold == 3:\n\tpass",
		"label.text = str(_state.gold)\nx = _state.sanity",
		"if _state.oil >= cap and _state.gold <= 2:\n\tpass",
		"_state.gold.to_string()\n_state.towers.size()\n_state.towers.back()",
		# entity writes are out of scope
		"func f(t: SimTower) -> void:\n\tt.lit = true",
		"func f() -> void:\n\tfor e in _state.enemies:\n\t\te.speed_mult = 0.5",
		# an alias of another function does not leak into this one
		"func a() -> void:\n\tvar s := sim.state\n\tvar g := s.gold\nfunc b(s) -> void:\n\ts.phase = 1",
		# the same name bound to something else is not an alias
		"func f() -> void:\n\tvar s := other.thing\n\ts.gold = 1",
		"func f() -> void:\n\tvar s := sim.state.towers\n\ts.size()\nvar _mystate := 1\n_mystate.gold = 1",
		"mystate.gold = 1\nother_state.sanity = 1\nx.state.gold = 1",
		"# _state.gold = 1\nvar s := \"_state.gold = 1\"",
	]
	var false_hits: Array[String] = []
	for text: String in near:
		var got := _g4b_written(scan, text)
		if not got.is_empty():
			false_hits.append("%s -> %s" % [text.replace("\n", " | "), got.keys()])
	scan.free()
	assert_array(false_hits).override_failure_message(
		"G4b near-miss hit:\n" + "\n".join(false_hits)).is_empty()


## wave_director.gd writes through `var s := sim.state` aliases in several funcs (owner
## decision): the scan must resolve them, and only the four wave fields plus night_luck.
func test_g4b_resolves_the_wave_director_aliases() -> void:
	var scan := SimBoundaryTest.new()
	var text := FileAccess.get_file_as_string("res://sim/core/wave_director.gd")
	var written := _g4b_written(scan, text)
	scan.free()
	assert_array(written.keys()).contains(["phase", "wave_index", "build_ticks_left",
		"waves_total", "night_luck"])
	assert_bool(text.contains("var s := sim.state")).is_true()  # the alias form is still in use


## LT-81 (B6): the stash and the tokens belong to EconomySystem alone.
const G4B_ECONOMY_WRITES := {
	"relics": "_state.relics[kind] += 1",
	"relic_tokens": "_state.relic_tokens.append(tok)",
	"next_token_id": "_state.next_token_id += 1",
}


func test_g4b_economy_stash_and_token_fields_have_economy_system_as_the_only_writer() -> void:
	var scan := SimBoundaryTest.new()
	var writers := _g4b_writers(scan)
	scan.free()
	for field: String in G4B_ECONOMY_WRITES:
		assert_array(writers.get(field, [])).override_failure_message(field) \
			.is_equal(["core/systems/economy_system.gd"])
		assert_array(G4B_OWNERS[field]).is_equal(["core/systems/economy_system.gd"])


## A write from a file that is not the owner lands in the writer list, so the guard's
## comparison with G4B_OWNERS fails for that field (and only for it).
func test_g4b_a_planted_write_to_an_economy_field_makes_the_guard_fail() -> void:
	var scan := SimBoundaryTest.new()
	var writers := _g4b_writers(scan)
	for field: String in G4B_ECONOMY_WRITES:
		var planted := "func f() -> void:\n\t%s\n" % G4B_ECONOMY_WRITES[field]
		var hit := _g4b_written(scan, planted)
		assert_bool(hit.has(field)).override_failure_message("scan misses %s" % field).is_true()
		var with_plant: Array = writers.get(field, []).duplicate()
		with_plant.append("core/simulation.gd")
		with_plant.sort()
		assert_array(with_plant).override_failure_message(field).is_not_equal(G4B_OWNERS[field])
	scan.free()


## LT-82 (B7): the charges and the allied units belong to Combat and Ally; the shared entity
## id counter has one writer, SimContext.next_id (LT-83).
const G4B_COMBAT_ALLY_WRITES := {
	"blasts": "_state.blasts.append(b)",
	"next_blast_id": "_state.next_blast_id += 1",
	"allies": "_state.allies.append(a)",
	"next_id": "state.next_id += 1",
}
const G4B_COMBAT_ALLY_OWNERS := {
	"blasts": ["core/systems/combat_system.gd"],
	"next_blast_id": ["core/systems/combat_system.gd"],
	"allies": ["core/systems/ally_system.gd"],
	"next_id": ["core/systems/sim_context.gd"],
}


func test_g4b_blasts_and_allies_have_combat_and_ally_system_as_the_only_writers() -> void:
	var scan := SimBoundaryTest.new()
	var writers := _g4b_writers(scan)
	scan.free()
	for field: String in G4B_COMBAT_ALLY_OWNERS:
		assert_array(writers.get(field, [])).override_failure_message(field) \
			.is_equal(G4B_COMBAT_ALLY_OWNERS[field])
		assert_array(G4B_OWNERS[field]).override_failure_message(field + " pinned row") \
			.is_equal(G4B_COMBAT_ALLY_OWNERS[field])


## A write from a file that is not an owner lands in the writer list, so the guard's
## comparison with G4B_OWNERS fails for that field (and only for it).
func test_g4b_a_planted_write_to_a_combat_or_ally_field_makes_the_guard_fail() -> void:
	var scan := SimBoundaryTest.new()
	var writers := _g4b_writers(scan)
	for field: String in G4B_COMBAT_ALLY_WRITES:
		var planted := "func f() -> void:\n\t%s\n" % G4B_COMBAT_ALLY_WRITES[field]
		var hit := _g4b_written(scan, planted)
		assert_bool(hit.has(field)).override_failure_message("scan misses %s" % field).is_true()
		var with_plant: Array = writers.get(field, []).duplicate()
		with_plant.append("core/wave_director.gd")  # an owner of neither
		with_plant.sort()
		assert_array(with_plant).override_failure_message(field).is_not_equal(G4B_OWNERS[field])
	scan.free()


## LT-83 (B8): next_id has one writer file (SimContext), lighthouse_hp two (facade, SpawnSystem),
## enemies one (SpawnSystem). A write from any other file lands in the writer list and so
## differs from the pinned row.
const G4B_SPAWN_ROWS := {
	"next_id": ["core/systems/sim_context.gd"],
	"lighthouse_hp": ["core/simulation.gd", "core/systems/spawn_system.gd"],
	"enemies": ["core/systems/spawn_system.gd"],
}


func test_g4b_next_id_enemies_and_lighthouse_hp_have_the_pinned_writers() -> void:
	var scan := SimBoundaryTest.new()
	var writers := _g4b_writers(scan)
	scan.free()
	for field: String in G4B_SPAWN_ROWS:
		assert_array(writers.get(field, [])).override_failure_message(field) \
			.is_equal(G4B_SPAWN_ROWS[field])
		assert_array(G4B_OWNERS[field]).override_failure_message(field + " pinned row") \
			.is_equal(G4B_SPAWN_ROWS[field])


## [planted text, field, file the plant is in]: a second next_id writer in the ally system or
## the facade, and a third lighthouse_hp writer, make the guard's comparison fail.
func test_g4b_a_planted_next_id_or_lighthouse_hp_write_makes_the_guard_fail() -> void:
	var scan := SimBoundaryTest.new()
	var writers := _g4b_writers(scan)
	var plants := [
		["_state.next_id += 1", "next_id", "core/systems/ally_system.gd"],
		["_ctx.state.next_id = 5", "next_id", "core/systems/ally_system.gd"],
		["state.next_id += 1", "next_id", "core/simulation.gd"],
		["_state.lighthouse_hp -= 1", "lighthouse_hp", "core/systems/combat_system.gd"],
		["_ctx.state.lighthouse_hp = 0", "lighthouse_hp", "core/systems/economy_system.gd"],
		["state.lighthouse_hp = 0", "lighthouse_hp", "core/wave_director.gd"],
	]
	for p: Array in plants:
		var hit := _g4b_written(scan, "func f() -> void:\n\t%s\n" % p[0])
		assert_bool(hit.has(p[1])).override_failure_message("scan misses %s" % p[0]).is_true()
		var with_plant: Array = writers.get(p[1], []).duplicate()
		if not with_plant.has(p[2]):
			with_plant.append(p[2])
		with_plant.sort()
		assert_array(with_plant).override_failure_message(p[0] + " in " + p[2]) \
			.is_not_equal(G4B_OWNERS[p[1]])
	# the owners themselves stay accepted: a plant in an owner file changes nothing
	for owner: String in G4B_OWNERS["lighthouse_hp"]:
		var same: Array = writers["lighthouse_hp"].duplicate()
		if not same.has(owner):
			same.append(owner)
		same.sort()
		assert_array(same).is_equal(G4B_OWNERS["lighthouse_hp"])
	scan.free()
