class_name SceneGameTest
extends GdUnitTestSuite
## LT-7 scene tests: real mouse events pushed into a 1152x648 SubViewport (the headless
## root is 64x64 and drops GUI clicks) drive the Game scene; assertions read sim state.

const RIFLE := "rifleman"

var _vp: SubViewport
var _game: Game
var _main: Node
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null
	_main = null


## A Game that only advances through advance(): its own _process is switched off.
func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		_vp.push_input(ev)
	await get_tree().process_frame


func _click_control(c: Control) -> void:
	await _click(c.get_global_rect().get_center())


func _click_cell(cell: Vector2i) -> void:
	await _click(_game.board.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Board.CELL)


func _buildable_cell() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _cost(def_id: String) -> int:
	return _config.towers[def_id].cost


func _build_via_ui(cell: Vector2i) -> void:
	await _click_cell(cell)
	await _click_control(_game.picker.buttons[RIFLE])


func test_clicking_buildable_cell_opens_picker_and_choosing_tower_builds_it() -> void:
	await _start_game()
	var cell := _buildable_cell()
	var gold := _game.sim.state.gold
	await _click_cell(cell)
	assert_bool(_game.picker.visible).is_true()
	assert_vector(_game.picker.cell).is_equal(cell)
	assert_bool(_game.sell_panel.visible).is_false()
	await _click_control(_game.picker.buttons[RIFLE])
	assert_bool(_game.sim.state.tower_at.has(cell)).is_true()
	assert_int(_game.sim.state.gold).is_equal(gold - _cost(RIFLE))
	assert_bool(_game.picker.visible).is_false()
	assert_array(_game.sim.drain_events()).is_empty()  # drained right after the command


func test_picker_has_one_button_per_config_tower_with_name_and_cost() -> void:
	await _start_game()
	await _click_cell(_buildable_cell())
	assert_int(_game.picker.buttons.size()).is_equal(_config.towers.size())
	for def_id: String in _config.towers:
		var def: TowerDef = _config.towers[def_id]
		assert_str(_game.picker.buttons[def_id].text).contains("%s - %d gold" % [def.name, def.cost])


func test_picker_disables_unaffordable_and_unavailable_towers() -> void:
	await _start_game()
	var cell := _buildable_cell()
	await _click_cell(cell)
	assert_bool(_game.picker.buttons[RIFLE].disabled).is_false()
	var occult := ""
	for def_id: String in _config.towers:
		if _game.sim.can_build(def_id, cell) == Simulation.CommandResult.NOT_AVAILABLE:
			occult = def_id
	assert_str(occult).is_not_empty()
	assert_bool(_game.picker.buttons[occult].disabled).is_true()
	assert_str(_game.picker.buttons[occult].text).contains("not available yet")
	# Gold drops below the cost while the panel is open: re-evaluated on the next frame.
	_game.sim.state.gold = _cost(RIFLE) - 1
	_game.advance(0.0)
	assert_bool(_game.picker.buttons[RIFLE].disabled).is_true()
	assert_str(_game.picker.buttons[RIFLE].text).contains("not enough gold")
	# A disabled button builds nothing.
	await _click_control(_game.picker.buttons[RIFLE])
	assert_int(_game.sim.state.towers.size()).is_equal(0)
	assert_int(_game.sim.state.gold).is_equal(_cost(RIFLE) - 1)


func test_clicking_a_tower_opens_sell_panel_and_selling_refunds() -> void:
	await _start_game()
	var cell := _buildable_cell()
	await _build_via_ui(cell)
	var tower := _game.sim.tower_by_id(_game.sim.state.tower_at[cell])
	var refund := _game.sim.sell_refund(tower)
	assert_int(refund).is_greater(0)
	await _click_cell(cell)
	assert_bool(_game.sell_panel.visible).is_true()
	assert_bool(_game.picker.visible).is_false()
	assert_str(_game.sell_panel.sell_button.text).contains("+%d gold" % refund)
	var gold := _game.sim.state.gold
	await _click_control(_game.sell_panel.sell_button)
	assert_bool(_game.sim.state.tower_at.has(cell)).is_false()
	assert_int(_game.sim.state.gold).is_equal(gold + refund)
	assert_bool(_game.sell_panel.visible).is_false()


func test_clicking_water_closes_open_panels_and_opens_nothing() -> void:
	await _start_game()
	await _click_cell(_buildable_cell())
	assert_bool(_game.picker.visible).is_true()
	var water := Vector2i(0, 0)
	assert_bool(_game.sim.state.map.is_buildable(water)).is_false()
	await _click_cell(water)
	assert_bool(_game.picker.visible).is_false()
	assert_bool(_game.sell_panel.visible).is_false()


func test_building_while_paused_works_and_tick_does_not_advance() -> void:
	await _start_game()
	await _click_control(_game.hud.pause_button)
	assert_int(_game.clock.speed).is_equal(0)
	_game.advance(0.0)  # Game._process is off in tests: refresh the HUD as a frame would
	assert_str(_game.hud.pause_button.text).is_equal("Resume")
	var tick := _game.sim.state.tick
	for i in 30:
		_game.advance(0.25)
	assert_int(_game.sim.state.tick).is_equal(tick)
	var gold := _game.sim.state.gold
	var cell := _buildable_cell()
	await _build_via_ui(cell)
	assert_bool(_game.sim.state.tower_at.has(cell)).is_true()
	assert_int(_game.sim.state.gold).is_equal(gold - _cost(RIFLE))
	for i in 30:
		_game.advance(0.25)
	assert_int(_game.sim.state.tick).is_equal(tick)
	# Resume: time flows again.
	await _click_control(_game.hud.pause_button)
	_game.advance(0.0)
	assert_str(_game.hud.pause_button.text).is_equal("Pause")
	_game.advance(0.25)
	assert_int(_game.sim.state.tick).is_greater(tick)


func test_speed_button_toggles_clock_speed_and_survives_pause() -> void:
	await _start_game()
	assert_int(_game.clock.speed).is_equal(1)
	await _click_control(_game.hud.speed_button)
	assert_int(_game.clock.speed).is_equal(2)
	_game.advance(0.0)
	assert_str(_game.hud.speed_button.text).is_equal("x2")
	await _click_control(_game.hud.pause_button)
	assert_int(_game.clock.speed).is_equal(0)
	await _click_control(_game.hud.pause_button)
	assert_int(_game.clock.speed).is_equal(2)
	# x2 really runs twice the ticks for the same real time.
	var t0 := _game.sim.state.tick
	_game.advance(2.0 / SimTime.TICK_RATE)
	assert_int(_game.sim.state.tick - t0).is_equal(4)
	await _click_control(_game.hud.speed_button)
	assert_int(_game.clock.speed).is_equal(1)
	_game.advance(0.0)
	assert_str(_game.hud.speed_button.text).is_equal("x1")
	t0 = _game.sim.state.tick
	_game.advance(2.0 / SimTime.TICK_RATE)
	assert_int(_game.sim.state.tick - t0).is_equal(2)


func test_call_wave_button_starts_wave_and_pays_the_bonus_shown_on_it() -> void:
	await _start_game()
	_game.advance(1.0)  # let some build time pass
	var s := _game.sim.state
	var bonus := _game.sim.early_call_bonus()
	assert_int(bonus).is_greater(0)
	assert_str(_game.hud.call_wave_button.text).contains("+%d" % bonus)
	assert_bool(_game.hud.call_wave_button.disabled).is_false()
	var gold := s.gold
	await _click_control(_game.hud.call_wave_button)
	assert_int(s.phase).is_equal(SimState.Phase.WAVE)
	assert_int(s.wave_index).is_equal(1)
	assert_int(s.gold).is_equal(gold + bonus)
	assert_bool(_game.hud.call_wave_button.disabled).is_true()
	assert_int(_game.sim.early_call_bonus()).is_equal(0)


func test_hud_labels_track_sim_state() -> void:
	await _start_game()
	var s := _game.sim.state
	var hud := _game.hud
	assert_str(hud.gold_label.text).is_equal("Gold: %d" % s.gold)
	assert_str(hud.hp_label.text).is_equal("Lighthouse: %d / %d" % [s.lighthouse_hp, _config.economy.lighthouse_hp])
	assert_str(hud.wave_label.text).is_equal("Wave %d / %d" % [s.wave_index, s.waves_total])
	assert_int(s.waves_total).is_equal(_config.waves.waves.size())
	await _build_via_ui(_buildable_cell())
	s.lighthouse_hp -= 3
	_game.sim.call_wave()
	_game.advance(0.0)
	assert_str(hud.gold_label.text).is_equal("Gold: %d" % s.gold)
	assert_str(hud.hp_label.text).is_equal("Lighthouse: %d / %d" % [s.lighthouse_hp, _config.economy.lighthouse_hp])
	assert_str(hud.wave_label.text).contains("Wave 1 / %d" % s.waves_total)
	assert_str(hud.phase_label.text).contains("in progress")


func test_build_timer_shows_floored_seconds_matching_the_bonus() -> void:
	await _start_game()
	var s := _game.sim.state
	var rate := _config.economy.early_call_gold_per_second
	# One tick short of 25 whole seconds must read 24, never 25.
	s.build_ticks_left = SimTime.ticks(25.0) - 1
	_game.advance(0.0)
	assert_str(_game.hud.phase_label.text).contains("in 24 s")
	assert_int(_game.sim.early_call_bonus()).is_equal(floori(rate * 24))
	assert_str(_game.hud.call_wave_button.text).contains("+%d" % floori(rate * 24))
	s.build_ticks_left = SimTime.ticks(25.0)
	_game.advance(0.0)
	assert_str(_game.hud.phase_label.text).contains("in 25 s")
	assert_int(_game.sim.early_call_bonus()).is_equal(floori(rate * 25))


func test_end_screen_appears_on_outcome_and_closes_panels() -> void:
	await _start_game()
	await _click_cell(_buildable_cell())
	assert_bool(_game.picker.visible).is_true()
	assert_bool(_game.end_screen.visible).is_false()
	_game.sim.state.lighthouse_hp = 0
	_game.sim.step()
	_game.advance(0.0)
	assert_bool(_game.end_screen.visible).is_true()
	assert_str(_game.end_screen.result_label.text).contains("fallen")
	assert_bool(_game.picker.visible).is_false()
	assert_bool(_game.hud.call_wave_button.disabled).is_true()
	# Board clicks after the outcome open nothing.
	await _click_cell(_buildable_cell())
	assert_bool(_game.picker.visible).is_false()


func test_restart_button_creates_a_fresh_game() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_vp.add_child(_main)
	await get_tree().process_frame
	var old: Game = _main.game
	old.set_process(false)
	await _click_cell_of(old, Vector2i(2, 3))
	old.sim.state.gold = 1
	old.sim.state.lighthouse_hp = 0
	old.sim.step()
	old.advance(0.0)
	assert_bool(old.end_screen.visible).is_true()
	await _click_control(old.end_screen.restart_button)
	await get_tree().process_frame
	await get_tree().process_frame
	var fresh: Game = _main.game
	assert_bool(fresh != old).is_true()
	assert_bool(is_instance_valid(old)).is_false()
	assert_int(fresh.sim.state.outcome).is_equal(SimState.Outcome.NONE)
	assert_int(fresh.sim.state.lighthouse_hp).is_equal(_config.economy.lighthouse_hp)
	assert_int(fresh.sim.state.towers.size()).is_equal(0)
	assert_bool(fresh.end_screen.visible).is_false()
	assert_int(fresh.sim.state.gold).is_greater_equal(_config.economy.starting_gold)


func _click_cell_of(g: Game, cell: Vector2i) -> void:
	await _click(g.board.position + (Vector2(cell) + Vector2(0.5, 0.5)) * Board.CELL)
