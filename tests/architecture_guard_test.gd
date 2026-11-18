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
## light / shadow multipliers, the flare's oil cost or speed, the oil cap, sanity_factor( or
## in_cast_radius( (comments and strings blanked); they ask TowerRules, LightRules or the
## Simulation facade instead. The denylist is pinned (LT-65 §4).
const G1_DIRS := ["res://ui", "res://scenes", "res://tools"]
const G1_DENY := "\\.(occult_power_mult|mundane_fire_interval_mult|mundane_ignore_miss" \
	+ "|mundane_miss_chance_add|enemy_speed_mult)\\b|flare\\.cost_oil|oil\\.cap\\b" \
	+ "|sanity_factor\\(|in_cast_radius\\("


func test_g1_no_rule_copies_outside_the_sim() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var scanned := 0
	for dir: String in G1_DIRS:
		for f in scan._gd_files(dir):
			scanned += 1
			hits.append_array(scan._find(f, scan._code_lines(FileAccess.get_file_as_string(f)),
				G1_DENY))
	var probe := scan._find("probe.gd", scan._code_lines("x = eco.flare.cost_oil"), G1_DENY)
	scan.free()
	assert_int(scanned).is_greater(20)  # the scan really walked ui/, scenes/ and tools/
	assert_int(probe.size()).is_equal(1)  # the pattern really matches a copy
	assert_array(hits).override_failure_message(
		"rule copy outside sim/ (use TowerRules / LightRules / the Simulation facade): "
		+ ", ".join(hits)).is_empty()


## G3 (LT-76, B2; sim and bot part, the view joins in B4): one cell centre. `.x + 0.5` /
## `.y + 0.5` appears under sim/ and tools/ only in sim/rules/sim_grid.gd (SimGrid.centre).
const G3_DIRS := ["res://sim", "res://tools"]
const G3_HOME := "res://sim/rules/sim_grid.gd"
const G3_CENTRE := "\\.(x|y)\\s*\\+\\s*0\\.5"


func test_g3_one_cell_centre_in_sim_and_bot() -> void:
	var scan := SimBoundaryTest.new()
	var hits: Array[String] = []
	var home_hits := 0
	for dir: String in G3_DIRS:
		for f in scan._gd_files(dir):
			var found := scan._find(f, scan._code_lines(FileAccess.get_file_as_string(f)),
				G3_CENTRE)
			if f == G3_HOME:
				home_hits = found.size()
			else:
				hits.append_array(found)
	scan.free()
	assert_int(home_hits).is_equal(2)  # the rule itself: x and y
	assert_array(hits).override_failure_message(
		"cell centre written by hand (use SimGrid.centre): " + ", ".join(hits)).is_empty()
