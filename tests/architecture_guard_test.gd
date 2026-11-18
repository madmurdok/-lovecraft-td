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


## G3 (LT-76, LT-77): one cell centre. Under sim/, tools/, scenes/ and ui/ a hand-written
## centre (`.x + 0.5`, `0.5 + .y`, `Vector2(c) + Vector2(0.5, 0.5)`, continuation lines
## joined) appears only in sim/rules/square_grid.gd (SquareGrid.centre).
const G3_DIRS := ["res://sim", "res://tools", "res://scenes", "res://ui"]
const G3_HOME := "res://sim/rules/square_grid.gd"
const G3_CENTRE := "\\.(x|y)\\s*\\+\\s*0\\.5\\b|\\b0\\.5\\s*\\+\\s*[\\w.]*\\.(x|y)\\b" \
	+ "|\\+\\s*Vector2\\(\\s*0\\.5\\s*,\\s*0\\.5\\s*\\)"


func test_g3_one_cell_centre() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var home_hits := 0
	for dir: String in G3_DIRS:
		for f in scan._gd_files(dir):
			var found := _find_joined(scan, f, FileAccess.get_file_as_string(f), G3_CENTRE)
			if f == G3_HOME:
				home_hits = found.size()
			else:
				hits.append_array(found)
	var probes := ["p = Vector2(cell) + Vector2(0.5, 0.5)", "p = Vector2(0.5 + c.x, 1)",
		"p = Vector2(cell.x\n\t+ 0.5, cell.y)"]
	var probe_hits := 0
	for p: String in probes:
		probe_hits += _find_joined(scan, "probe.gd", p, G3_CENTRE).size()
	scan.free()
	assert_int(probe_hits).is_equal(probes.size())  # each centre form is caught
	assert_int(home_hits).is_equal(2)  # the rule itself: x and y
	assert_array(hits).override_failure_message(
		"cell centre written by hand (use GridTopology.centre): " + ", ".join(hits)).is_empty()


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
