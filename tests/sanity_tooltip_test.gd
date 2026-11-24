class_name SanityTooltipTest
extends GdUnitTestSuite
## LT-120: hovering the sanity bar explains what drains sanity (the occult towers' hold on the
## cap, horror within horror_radius_cells of a tower) and what restores it (each dawn, per
## mundane kill), plus the madness line per exit rule. Every number comes from config, so the
## tests set values the shipped data does not use and read the texts back from them.

const NECRO := "necronomicon_reader"
const MINUS := "−"

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game() -> void:
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame


func _buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)) and not _game.sim.state.tower_at.has(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _build_reserve(reserve: float) -> void:
	_config.towers[NECRO].levels[0].sanity_reserve = reserve
	_game.sim.state.gold = 100000
	assert_int(_game.commands.build(NECRO, _buildable_cell())).is_equal(SimCommand.CommandResult.OK)


## Non-shipped numbers for every figure the tooltip prints; one horror enemy, as shipped.
func _set_numbers() -> void:
	var cfg := _config.sanity
	cfg.regen_between_waves = 7.0
	cfg.regen_mundane_kill = 0.25
	cfg.horror_radius_cells = 4.5
	cfg.madness.exit_rule = "recover"
	cfg.madness.exit_sanity = 35.0
	for e: EnemyDef in _config.enemies.values():
		if e.horror_drain > 0.0:
			e.horror_drain = 1.5


func _horror_defs() -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for e: EnemyDef in _config.enemies.values():
		if e.horror_drain > 0.0:
			out.append(e)
	return out


func _lines() -> PackedStringArray:
	return Hud.sanity_tooltip(_game.sim).split("\n")


# --- the bar is hoverable and carries the text ---------------------------------------------

func test_the_sanity_bar_receives_mouse_hover() -> void:
	await _start_game()
	assert_int(_game.hud.sanity_bar.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)


func test_refresh_sets_the_bar_tooltip_from_the_current_state() -> void:
	await _start_game()
	var bar := _game.hud.sanity_bar
	_game.hud.refresh()
	assert_str(bar.tooltip_text).is_not_empty()
	assert_str(bar.tooltip_text).is_equal(Hud.sanity_tooltip(_game.sim))
	assert_bool(bar.tooltip_text.contains(" now")).is_false()
	_build_reserve(20.0)
	_game.hud.refresh()
	assert_str(bar.tooltip_text).is_equal(Hud.sanity_tooltip(_game.sim))
	assert_bool(bar.tooltip_text.contains("20 now")).is_true()


# --- every number follows config ------------------------------------------------------------

func test_the_texts_follow_non_shipped_config_numbers() -> void:
	await _start_game()
	_set_numbers()
	var horror := _horror_defs()
	assert_int(horror.size()).is_greater(0)
	var lines := _lines()
	assert_str(lines[0]).is_equal("Drains sanity:")
	for e in horror:
		assert_bool(lines.has("· %s within 4.5 cells of a tower: %s1.5 per s" % [e.name, MINUS])) \
			.override_failure_message("\n".join(lines)).is_true()
	assert_bool(lines.has("Restores: +7 each dawn, +0.25 per mundane kill")) \
		.override_failure_message("\n".join(lines)).is_true()
	assert_str(lines[lines.size() - 1]).is_equal("At 0: madness until sanity is back to 35")


func test_a_regen_source_at_zero_is_left_out_and_none_drops_the_restores_line() -> void:
	await _start_game()
	_set_numbers()
	_config.sanity.regen_mundane_kill = 0.0
	assert_bool(_lines().has("Restores: +7 each dawn")).is_true()
	_config.sanity.regen_between_waves = 0.0
	for l in _lines():
		assert_bool(l.begins_with("Restores")).is_false()


func test_regen_parts_lists_the_sources_from_config() -> void:
	var cfg := _config.sanity
	cfg.regen_between_waves = 7.0
	cfg.regen_mundane_kill = 0.25
	assert_array(Array(Hud.regen_parts(cfg))).is_equal(["+7 each dawn", "+0.25 per mundane kill"])
	cfg.regen_between_waves = 0.0
	assert_array(Array(Hud.regen_parts(cfg))).is_equal(["+0.25 per mundane kill"])
	cfg.regen_mundane_kill = 0.0
	assert_bool(Hud.regen_parts(cfg).is_empty()).is_true()


func test_recover_text_still_shows_the_regen_sources_of_regen_parts() -> void:
	var cfg := _config.sanity
	cfg.regen_between_waves = 7.0
	cfg.regen_mundane_kill = 0.25
	assert_str(Hud.recover_text(cfg, 35.0)).is_equal(
		"Recover at 35 sanity: " + ", ".join(Hud.regen_parts(cfg)))
	assert_str(Hud.recover_text(cfg, 35.0)).is_equal(
		"Recover at 35 sanity: +7 each dawn, +0.25 per mundane kill")


# --- the occult hold shows its amount only when > 0 -----------------------------------------

func test_the_occult_line_shows_the_held_amount_only_while_a_reserve_stands() -> void:
	await _start_game()
	var bare := "· occult towers hold part of it (the hatched end)"
	assert_bool(_lines().has(bare)).override_failure_message("\n".join(_lines())).is_true()
	_build_reserve(30.0)
	var held := _config.sanity.max_sanity - _game.sim.state.sanity_cap
	assert_float(held).is_greater(0.0)
	assert_bool(_lines().has(bare + ": %d now" % roundi(held))) \
		.override_failure_message("\n".join(_lines())).is_true()
	assert_bool(_lines().has(bare)).is_false()


# --- the madness line per exit rule -----------------------------------------------------------

func test_recover_rule_names_the_exit_sanity_from_config() -> void:
	await _start_game()
	_set_numbers()
	assert_bool(_game.sim.recover_rule()).is_true()
	_config.sanity.madness.exit_sanity = 12.0
	assert_str(_lines()[-1]).is_equal("At 0: madness until sanity is back to 12")


func test_recover_rule_at_cap_zero_says_there_is_no_way_back() -> void:
	await _start_game()
	_set_numbers()
	_build_reserve(_config.sanity.max_sanity)
	assert_float(_game.sim.exit_target()).is_equal(0.0)
	assert_str(_lines()[-1]).is_equal(
		"At 0: madness, with no way back while occult towers hold it all")


func test_other_exit_rules_say_plain_madness_even_with_an_exit_sanity_set() -> void:
	await _start_game()
	_set_numbers()
	for rule in ["permanent", "buyout", "auto_restore"]:
		_config.sanity.madness.exit_rule = rule
		assert_bool(_game.sim.recover_rule()).override_failure_message(rule).is_false()
		assert_str(_lines()[-1]).override_failure_message(rule).is_equal("At 0: madness")
