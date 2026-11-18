class_name LightRulesTest
extends GdUnitTestSuite
## LT-76 (LT-65 §3.2): LightRules and SimGrid on hand-checked cases, and the lighthouse
## panel's coverage reading the same rule as LightRules (one source for sim, UI and bot).

const EPS := 1e-9


func test_cell_centre_is_the_cell_plus_a_half() -> void:
	assert_object(SimGrid.centre(Vector2i(0, 0))).is_equal(Vector2(0.5, 0.5))
	assert_object(SimGrid.centre(Vector2i(7, 1))).is_equal(Vector2(7.5, 1.5))
	assert_object(SimGrid.centre(Vector2i(-1, 3))).is_equal(Vector2(-0.5, 3.5))


func test_cast_radius_boundary_is_inclusive() -> void:
	var c := Vector2(3.5, 1.5)
	assert_bool(LightRules.in_cast_radius(c, 3.0, Vector2(6.5, 1.5))).is_true()  # exactly 3
	assert_bool(LightRules.in_cast_radius(c, 3.0, Vector2(6.51, 1.5))).is_false()
	assert_bool(LightRules.in_cast_radius(c, 3.0, Vector2(0.5, 1.5))).is_true()
	assert_bool(LightRules.in_cast_radius(c, 5.0, Vector2(6.5, 5.5))).is_true()  # 3-4-5
	assert_bool(LightRules.in_cast_radius(c, 4.9, Vector2(6.5, 5.5))).is_false()
	assert_bool(LightRules.in_cast_radius(c, 0.0, c)).is_true()  # its own point


func test_covers_measures_from_the_cell_centre_not_its_corner() -> void:
	var cell := Vector2i(3, 1)  # centre (3.5, 1.5)
	assert_bool(LightRules.covers(cell, 3.0, Vector2(6.5, 1.5))).is_true()
	assert_bool(LightRules.covers(cell, 3.0, Vector2(6.51, 1.5))).is_false()
	# Corner (3, 1) would flip both of these: 6.4 is 3.4 from it, 0.4 is 2.6 from it.
	assert_bool(LightRules.covers(cell, 3.0, Vector2(6.4, 1.5))).is_true()  # 2.9 from centre
	assert_bool(LightRules.covers(cell, 3.0, Vector2(0.4, 1.5))).is_false()  # 3.1 from centre


func test_beam_coverage_is_the_cone_share_capped_at_one() -> void:
	# k = 1: each beam is 2 atan(1) = 90 degrees wide, a quarter of the circle.
	assert_float(LightRules.beam_coverage(1, 1.0)).is_equal_approx(0.25, EPS)
	assert_float(LightRules.beam_coverage(2, 1.0)).is_equal_approx(0.5, EPS)
	assert_float(LightRules.beam_coverage(4, 1.0)).is_equal_approx(1.0, EPS)
	assert_float(LightRules.beam_coverage(8, 1.0)).is_equal(1.0)  # overlaps cap at 1
	assert_float(LightRules.beam_coverage(0, 1.0)).is_equal(0.0)
	assert_float(LightRules.beam_coverage(1, 0.0)).is_equal(0.0)  # a zero-width beam
	# Half-width ratio tan(PI/8): a beam PI/4 wide, an eighth of the circle; two make a quarter.
	assert_float(LightRules.beam_coverage(2, tan(PI / 8.0))).is_equal_approx(0.25, EPS)


## UI one-source: the lighthouse panel's percent is round(100 x LightRules.beam_coverage),
## for the helper and for the text the panel shows from the sim's own config.
func test_lighthouse_coverage_percent_is_the_light_rules_share() -> void:
	for beams: int in [1, 2, 3, 4, 8]:
		for k: float in [0.245, 0.5, 1.0, 2.0]:
			assert_int(LighthousePanel.coverage_percent(beams, k)).is_equal(
				roundi(100.0 * LightRules.beam_coverage(beams, k)))
	# Hand check on the shipped width: one beam of ratio 0.245 covers atan(0.245) / PI.
	assert_int(LighthousePanel.coverage_percent(1, 0.245)).is_equal(
		roundi(100.0 * atan(0.245) / PI))


func test_lighthouse_panel_text_shows_the_light_rules_coverage() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var vp := GameFixture.make_viewport(self)
	var game := GameFixture.make_game(vp, r.config, 7)
	await get_tree().process_frame
	var eco := game.sim.config.economy
	eco.beam.half_width_ratio = 0.5  # not the shipped value: the text must follow the config
	game.lighthouse_panel.open()
	game.lighthouse_panel.refresh()
	var beams: int = eco.beam.levels[game.sim.state.lighthouse_level].beams
	var want := roundi(100.0 * LightRules.beam_coverage(beams, 0.5))
	assert_str(game.lighthouse_panel.stats_label.text).contains("Coverage: %d %%" % want)
	vp.queue_free()
