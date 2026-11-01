class_name SanityFeedbackTest
extends GdUnitTestSuite
## LT-14: the sanity feedback layer follows sim sanity (level per threshold, flicker only
## from Fraying on), keeps the HUD above the distortion and clickable, offers the madness
## buyout only with exit_rule "buyout" in madness, and draws an empty astray shot off its aim point.
## The real check of the look is by render (screenshots); these pin the wiring.

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = Vector2i(1200, 675)
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame


func _set_sanity(v: float) -> void:
	_game.sim._add_sanity(v - _game.sim.state.sanity, "test", 0)
	_game.advance(0.0)
	_game.sanity_fx._snap()


func test_effect_level_rises_through_the_thresholds() -> void:
	await _start_game()
	var levels: Array[float] = []
	for v in [100.0, 69.0, 41.0, 39.0, 1.0, 0.0]:
		_set_sanity(v)
		levels.append(_game.sanity_fx.level)
	assert_float(levels[0]).is_equal(0.0)
	for i in range(1, levels.size()):
		assert_float(levels[i]).is_greater_equal(levels[i - 1])
	assert_float(levels[5]).is_equal(1.0)
	assert_bool(_game.sanity_fx.screen_rect.visible).is_true()


func test_lucid_hides_the_screen_layer_and_whispers_has_no_flicker() -> void:
	await _start_game()
	_set_sanity(100.0)
	assert_bool(_game.sanity_fx.screen_rect.visible).is_false()
	assert_float(_game.sanity_fx.flicker).is_equal(0.0)
	_set_sanity(55.0)
	assert_float(_game.sanity_fx.flicker).is_equal(0.0)
	assert_float(_game.sanity_fx.ui_jitter_material.get_shader_parameter("jitter_px")) \
		.is_greater(0.0)
	_set_sanity(20.0)
	assert_float(_game.sanity_fx.flicker).is_greater(0.0)


func test_madness_keeps_fraying_flicker_at_its_maximum() -> void:
	await _start_game()
	_set_sanity(0.0)
	assert_float(_game.sanity_fx.flicker).is_equal_approx(_game.sanity_fx.max_flicker, 1e-5)
	assert_float(_game.sanity_fx.madness).is_equal(1.0)


func test_hud_is_above_the_distortion_and_it_never_takes_clicks() -> void:
	await _start_game()
	var ui := _game.hud.get_parent() as CanvasLayer
	assert_int(ui.layer).is_greater(_game.sanity_fx.screen_layer.layer)
	assert_int(_game.sanity_fx.screen_rect.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_object(_game.hud.call_wave_button.material).is_same(
		_game.sanity_fx.ui_jitter_material)


func test_buyout_button_follows_the_exit_rule_and_can_buy_sanity() -> void:
	await _start_game()
	assert_bool(_game.hud.buyout_button.visible).is_false()  # data: exit_rule permanent
	_game.queue_free()
	_config.sanity.madness.exit_rule = "buyout"
	await _start_game()
	var b := _game.hud.buyout_button
	_game.hud.refresh()
	assert_bool(b.visible).is_false()  # buyout rule, but not in madness
	_game.sim.state.gold = 1000
	_set_sanity(0.0)
	_game.hud.refresh()
	assert_bool(b.visible).is_true()
	assert_str(b.text).contains(str(_config.sanity.madness.buyout_cost))
	assert_bool(b.disabled).is_false()
	# The whole HUD bar, buyout button included, fits the window width.
	var bar := _game.hud.get_node("Bar") as Control
	assert_float(bar.position.x + bar.get_combined_minimum_size().x).is_less_equal(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")))
	b.pressed.emit()
	assert_float(_game.sim.state.sanity).is_equal(_config.sanity.madness.restore_sanity)
	assert_int(_game.sim.state.gold).is_equal(1000 - _config.sanity.madness.buyout_cost)


## LT-36: the HUD shows the buyout button exactly while the sim query buyout_applies() holds,
## for every exit rule, in and out of madness, and does not re-derive the rule itself.
func test_buyout_button_visibility_is_the_sim_buyout_query() -> void:
	await _start_game()
	var b := _game.hud.buyout_button
	var m := _game.sim.config.sanity.madness
	for mad: bool in [false, true]:
		if mad:
			m.exit_rule = "buyout"
			_set_sanity(0.0)
			assert_int(_game.sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
		for rule: String in ["permanent", "buyout", "auto_restore"]:
			m.exit_rule = rule
			_game.hud.refresh()
			assert_bool(b.visible).override_failure_message("%s mad=%s" % [rule, mad]) \
				.is_equal(_game.sim.buyout_applies())
			assert_bool(b.visible).override_failure_message("%s mad=%s" % [rule, mad]) \
				.is_equal(mad and rule == "buyout")
	var hud := FileAccess.get_file_as_string("res://ui/hud.gd")
	assert_str(hud).contains("buyout_button.visible = game.sim.buyout_applies()")
	assert_str(hud).not_contains(".exit_rule")  # no own copy of the rule


func test_an_empty_astray_shot_lands_off_its_aim_point() -> void:
	await _start_game()
	assert_int(_game.build("rifleman", _first_buildable()) as int) \
		.is_equal(Simulation.CommandResult.OK)
	var tower: SimTower = _game.sim.state.towers[0]
	var aim := Vector2(3.5, 1.5)
	var ev := SimEvent.new(SimEvent.Type.SHOT, 0, tower.id, {"def": "rifleman", "target": 0,
		"hits": [], "to": aim, "miss": false, "astray": true})
	_game.board.on_event(ev)
	var fx: Dictionary = _game.board.effects.back()
	assert_str(fx["kind"]).is_equal("astray")
	var d: float = (fx["to"] as Vector2).distance_to(aim)
	assert_float(d).is_between(Board.ASTRAY_MIN_CELLS - 0.001, Board.ASTRAY_MAX_CELLS + 0.001)


func test_sanity_arg_parses_only_its_own_flag() -> void:
	assert_float(Game.debug_sanity_arg(PackedStringArray(["--seed=3"]))).is_equal(-1.0)
	assert_float(Game.debug_sanity_arg(PackedStringArray(["--sanity=55"]))).is_equal(55.0)
	assert_float(Game.debug_sanity_arg(PackedStringArray(["--sanity=-4"]))).is_equal(0.0)


func test_sanity_arg_accepts_the_space_separated_form() -> void:
	assert_float(Game.debug_sanity_arg(PackedStringArray(["--sanity", "10"]))).is_equal(10.0)
	assert_float(Game.debug_sanity_arg(PackedStringArray(["--x", "--sanity", "7.5"]))).is_equal(7.5)


func test_sanity_arg_without_a_number_is_ignored() -> void:
	for args: Array in [["--sanity"], ["--sanity", "abc"], ["--sanity="], ["--sanity=abc"],
			["--sanityx=5"]]:
		assert_float(Game.debug_sanity_arg(PackedStringArray(args))).is_equal(-1.0)


func _first_buildable() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)
