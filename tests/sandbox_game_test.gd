class_name SandboxGameTest
extends GdUnitTestSuite
## LT-67 scene side of `--sandbox`: Game.skip_ahead (key N), the SANDBOX HUD marker, and a
## run without the flag. The flag itself comes from the command line, which a test cannot
## set: a sandbox run is a Game whose `sandbox` is switched on before it enters the tree.

const R := Simulation.CommandResult

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


func _start(sandbox: bool) -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	assert_bool(_game.sandbox).is_false()  # the test process has no --sandbox
	_game.sandbox = sandbox
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)


func _press(keycode: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.pressed = pressed
		_vp.push_input(ev)
	await get_tree().process_frame


func _log_names() -> Array:
	return _game.sim.state.command_log.map(func(c: Array) -> String: return c[1])


# --- behaviour 7: HUD marker ------------------------------------------------------------

func test_hud_shows_the_sandbox_label_only_in_a_sandbox_run() -> void:
	await _start(true)
	assert_object(_game.hud.sandbox_label).is_not_null()
	assert_str(_game.hud.sandbox_label.text).is_equal("SANDBOX")
	assert_bool(_game.hud.get_node_or_null("SandboxLabel") != null).is_true()
	assert_bool(_game.hud.board_rect().encloses(_game.hud.sandbox_label.get_rect())).is_true()


func test_hud_has_no_sandbox_label_without_the_flag() -> void:
	await _start(false)
	assert_object(_game.hud.sandbox_label).is_null()
	assert_object(_game.hud.get_node_or_null("SandboxLabel")).is_null()


# --- behaviour 3/4: skipping ahead ------------------------------------------------------

func test_skip_ahead_by_day_starts_the_night_and_at_night_ends_it() -> void:
	await _start(true)
	var s := _game.sim.state
	assert_int(_game.skip_ahead()).is_equal(R.OK)
	assert_int(s.phase).is_equal(SimState.Phase.WAVE)
	assert_array(_log_names()).is_equal(["call_wave"])
	_game.sim.step()  # first spawns
	assert_int(_game.skip_ahead()).is_equal(R.OK)
	assert_array(_log_names()).is_equal(["call_wave", "debug_end_night"])
	_game.sim.step()
	assert_int(s.phase).is_equal(SimState.Phase.BUILD)
	assert_int(s.wave_index).is_equal(1)


func test_key_n_skips_ahead_and_other_keys_do_not() -> void:
	await _start(true)
	await _press(KEY_M)
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)
	await _press(KEY_N)
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.WAVE)
	assert_array(_log_names()).is_equal(["call_wave"])


# --- behaviour 1/5: without the flag nothing changes ------------------------------------

func test_without_the_flag_skip_ahead_and_key_n_do_nothing() -> void:
	await _start(false)
	var s := _game.sim.state
	assert_int(s.gold).is_equal(_config.economy.starting_gold)
	assert_int(s.oil).is_equal(_config.economy.oil.start)
	assert_int(_game.skip_ahead()).is_equal(R.NOT_BUILD_PHASE)
	await _press(KEY_N)
	assert_int(s.phase).is_equal(SimState.Phase.BUILD)
	assert_array(s.command_log).is_empty()
	# And at night too: call the wave the normal way, N must not end it.
	assert_int(_game.call_wave()).is_equal(R.OK)
	assert_int(_game.skip_ahead()).is_equal(R.NOT_BUILD_PHASE)
	await _press(KEY_N)
	assert_array(_log_names()).is_equal(["call_wave"])
	assert_int(s.phase).is_equal(SimState.Phase.WAVE)
