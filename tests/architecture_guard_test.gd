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
## LT-65 #12 found) nor a SelectionModel field (`selection.cell = ...`) outside
## scenes/board/selection_model.gd: the panels call its methods, which emit `changed`.
## Comparisons (`==`, `!=`) are reads and pass.
const G7_DIRS := ["res://ui", "res://scenes", "res://tools"]
const G7_HOME := "res://scenes/board/selection_model.gd"
const G7_DENY := "\\bselected_(cell|range|glyph|cast)\\s*=(?!=)" \
	+ "|\\bselection\\.(cell|range_cells|glyph|cast)\\s*=(?!=)"


func test_g7_selection_is_written_only_through_the_model() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var home_scanned := false
	for dir: String in G7_DIRS:
		for f in scan._gd_files(dir):
			if f == G7_HOME:
				home_scanned = true
				continue
			hits.append_array(_find_joined(scan, f, FileAccess.get_file_as_string(f), G7_DENY))
	var probes := ["game.board.selected_cell = c", "board.selected_range=0.0",
		"b.selected_glyph = \"\"", "game.selection.cast = \"light\"",
		"game.selection.range_cells = r"]
	var reads := ["if game.board.selected_range != r:", "x = sel.cell == c",
		"game.selection.set_ring(r, cast)"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += _find_joined(scan, "probe.gd", p, G7_DENY).size()
	var read_hits := 0
	for p: String in reads:
		read_hits += _find_joined(scan, "probe.gd", p, G7_DENY).size()
	scan.free()
	assert_int(probe_hits).is_equal(probes.size())  # each write form is caught
	assert_int(read_hits).is_equal(0)  # reads and method calls pass
	assert_bool(home_scanned).is_true()  # the model is in the scope
	assert_array(hits).override_failure_message(
		"selection written outside SelectionModel: " + ", ".join(hits)).is_empty()


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
	return scan._find(file, joined, pattern)
