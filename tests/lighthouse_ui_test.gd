class_name LighthouseUiTest
extends GdUnitTestSuite
## LT-30 §3.2 presentation: the beams are drawn from sim state (count from the level,
## rotation from beam_directions at tick + alpha, flare width from the config), the lighthouse
## panel (opened by a click on its cell) with its upgrade and oil buttons, the HUD flare
## button and oil label, and the Game command forwards.

const R := Simulation.CommandResult

var _vp: SubViewport
var _game: Game


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_vp = SubViewport.new()
	_vp.size = Vector2i(1152, 648)
	add_child(_vp)
	_game = Game.new()
	_game.setup(r.config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _steps(n: int) -> void:
	for i in n:
		_game.sim.step()


# --- beams (Lighting) ------------------------------------------------------------------------

func test_beam_count_follows_the_lighthouse_level() -> void:
	var l := _game.lighting
	assert_int(l.beams.size()).is_equal(1)
	assert_object(l.beam).is_same(l.beams[0])
	_game.sim.state.gold = 100000
	for want: int in [2, 4]:
		assert_int(_game.upgrade_lighthouse()).is_equal(R.OK)
		await get_tree().process_frame
		assert_int(l.beams.size()).is_equal(want)
		assert_int(l.beams.size()).is_equal(_game.sim.beam_count())
	_game.sim.state.lighthouse_level = 0  # shrinks too
	await get_tree().process_frame
	assert_int(l.beams.size()).is_equal(1)


func test_beams_follow_the_sim_directions_and_have_no_timer() -> void:
	var l := _game.lighting
	_game.sim.state.gold = 100000
	_game.upgrade_lighthouse()
	await get_tree().process_frame
	var day := [l.beams[0].rotation, l.beams[1].rotation]
	_steps(5)  # by day the sim gives no directions: the rotation stays
	await get_tree().process_frame
	assert_array([l.beams[0].rotation, l.beams[1].rotation]).is_equal(day)
	_game.call_wave()
	_steps(5)
	await get_tree().process_frame
	var dirs := _game.sim.beam_directions(_game.clock.alpha())
	assert_int(dirs.size()).is_equal(2)
	for i in 2:
		assert_float(l.beams[i].rotation).is_equal_approx(dirs[i].angle(), 1e-5)
	var held := [l.beams[0].rotation, l.beams[1].rotation]
	for i in 3:
		await get_tree().process_frame
	assert_array([l.beams[0].rotation, l.beams[1].rotation]).is_equal(held)
	assert_bool(held[0] != day[0]).is_true()  # the night ticks did turn it


func test_flare_widens_the_drawn_cone_while_it_burns() -> void:
	var l := _game.lighting
	var eco := _game.sim.config.economy
	var normal := Lighting._beam_texture(atan(eco.beam.half_width_ratio))
	assert_object(l.beam.texture).is_same(normal)
	_game.call_wave()
	assert_int(_game.fire_flare()).is_equal(R.OK)
	await get_tree().process_frame
	var wide := Lighting._beam_texture(atan(eco.beam.half_width_ratio * eco.flare.width_mult))
	assert_object(wide).is_not_same(normal)
	assert_object(l.beam.texture).is_same(wide)
	_steps(SimTime.ticks(eco.flare.seconds))
	await get_tree().process_frame
	assert_int(_game.sim.state.flare_ticks_left).is_equal(0)
	assert_object(l.beam.texture).is_same(normal)


# --- lighthouse panel --------------------------------------------------------------------------

func test_a_click_on_the_lighthouse_opens_its_panel_and_close_panels_closes_it() -> void:
	var p := _game.lighthouse_panel
	assert_bool(p.visible).is_false()
	_game._on_cell_clicked(_game.sim.state.map.lighthouse)
	assert_bool(p.visible).is_true()
	assert_bool(_game.tower_panel.visible).is_false()
	assert_bool(_game.picker.visible).is_false()
	assert_str(p.title_label.text).is_equal("Lighthouse  L1")
	_game.close_panels()
	assert_bool(p.visible).is_false()


func test_panel_upgrade_button_states() -> void:
	var p := _game.lighthouse_panel
	var s := _game.sim.state
	p.open()
	s.gold = 0
	p.refresh()
	assert_bool(p.upgrade_button.disabled).is_true()
	assert_str(p.upgrade_button.text).contains("2 beams")
	assert_str(p.upgrade_button.text).contains("Not enough money")
	s.gold = 100000
	p.refresh()
	assert_bool(p.upgrade_button.disabled).is_false()
	assert_int(_game.upgrade_lighthouse()).is_equal(R.OK)
	p.refresh()
	assert_str(p.title_label.text).is_equal("Lighthouse  L2")
	assert_str(p.upgrade_button.text).contains("4 beams")
	assert_int(_game.upgrade_lighthouse()).is_equal(R.OK)
	p.refresh()
	assert_str(p.upgrade_button.text).is_equal("Max level")
	assert_bool(p.upgrade_button.disabled).is_true()
	s.lighthouse_level = 0
	_game.call_wave()
	p.refresh()
	assert_bool(p.upgrade_button.disabled).is_true()
	assert_str(p.upgrade_button.text).contains("By day only")


func test_panel_oil_button_states() -> void:
	var p := _game.lighthouse_panel
	var s := _game.sim.state
	var oil := _game.sim.config.economy.oil
	p.open()
	s.gold = 100000
	p.refresh()
	assert_str(p.oil_label.text).contains("Lamp oil: %d / %d" % [s.oil, oil.cap])
	assert_bool(p.oil_button.disabled).is_false()
	var before := s.oil
	assert_int(_game.buy_oil()).is_equal(R.OK)  # Game forwards to the sim
	assert_int(s.oil).is_equal(before + 1)
	s.oil = oil.cap
	p.refresh()
	assert_bool(p.oil_button.disabled).is_true()
	assert_str(p.oil_button.text).contains("Tank full")
	s.oil = 0
	_game.call_wave()
	p.refresh()
	assert_bool(p.oil_button.disabled).is_true()
	assert_str(p.oil_button.text).contains("By day only")


func test_coverage_percent() -> void:
	assert_int(LighthousePanel.coverage_percent(2, 1.0)).is_equal(50)
	assert_int(LighthousePanel.coverage_percent(4, 1.0)).is_equal(100)
	assert_int(LighthousePanel.coverage_percent(8, 1.0)).is_equal(100)  # capped
	assert_int(LighthousePanel.coverage_percent(1, 1.0)).is_equal(25)


# --- HUD flare button and oil label -----------------------------------------------------------

func test_flare_button_shows_at_night_with_its_states() -> void:
	var h := _game.hud
	var s := _game.sim.state
	var f := _game.sim.config.economy.flare
	h.refresh()
	assert_bool(h.flare_button.visible).is_false()  # by day
	assert_str(h.oil_label.text).is_equal("Oil %d / %d" % [s.oil, _game.sim.config.economy.oil.cap])
	assert_bool(h.oil_label.visible).is_true()
	_game.call_wave()
	h.refresh()
	assert_bool(h.flare_button.visible).is_true()
	assert_bool(h.flare_button.disabled).is_false()
	assert_str(h.flare_button.text).is_equal("Flare (%d oil)" % f.cost_oil)
	assert_int(_game.fire_flare()).is_equal(R.OK)
	h.refresh()
	assert_str(h.flare_button.text).is_equal("Flare burning")
	assert_bool(h.flare_button.disabled).is_true()
	_steps(SimTime.ticks(f.seconds))
	h.refresh()
	var left := SimTime.ticks(f.cooldown_seconds) - SimTime.ticks(f.seconds)
	assert_str(h.flare_button.text).is_equal("Flare %d s" % ceili(float(left) / SimTime.TICK_RATE))
	assert_bool(h.flare_button.disabled).is_true()
	s.flare_cooldown_ticks = 0
	s.oil = 0
	h.refresh()
	assert_bool(h.flare_button.disabled).is_true()  # NO_OIL
	assert_str(h.oil_label.text).is_equal("Oil 0 / %d" % _game.sim.config.economy.oil.cap)
