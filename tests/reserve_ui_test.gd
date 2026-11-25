class_name ReserveUiTest
extends GdUnitTestSuite
## LT-23 S7 presentation (design note §6, pins 22-24): the sanity bar's cap ratio and its
## "Sanity n / cap" label, and the HUD hostility line built from the madness multipliers,
## shown only in MADNESS. Texts from the design note, numbers from config. The drawn
## reserved block and the enemy tint (pins 21, 22 drawing) are checked by render.

const NECRO := "necronomicon_reader"

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


func _set_sanity(v: float) -> void:
	_game.sim.state.sanity = v
	_game.sim.state.sanity_state = _game.sim.sanity_state_for(v)
	GameFixture.sync(_game)  # LT-85: poked on the sim directly
	_game.hud.refresh()


# --- 22, 23: sanity bar -------------------------------------------------------------------

func test_cap_ratio_is_cap_over_max() -> void:
	await _start_game()
	var bar := _game.hud.sanity_bar
	assert_float(bar.cap_ratio()).is_equal(1.0)
	var top := _config.sanity.max_sanity
	_build_reserve(top * 0.25)
	assert_float(bar.cap_ratio()).is_equal_approx(0.75, 0.0001)
	_build_reserve(top)  # the sum exceeds max: the cap floors at 0
	assert_float(bar.cap_ratio()).is_equal(0.0)


func test_label_shows_the_cap_only_while_it_is_below_max() -> void:
	await _start_game()
	_config.sanity.madness.exit_rule = "permanent"  # LT-121: the shipped default "recover" changes the madness text / lets debug through
	var bar := _game.hud.sanity_bar
	var top := _config.sanity.max_sanity
	assert_str(bar.label_text()).is_equal("Sanity %d  Lucid" % roundi(top))
	_build_reserve(20.0)
	_set_sanity(63.0)
	assert_str(bar.label_text()).is_equal("Sanity 63 / %d  Whispers" % roundi(top - 20.0))
	_set_sanity(0.0)
	assert_str(bar.label_text()).is_equal("Sanity 0 / %d  Madness" % roundi(top - 20.0))


# --- 24: HUD hostility line ---------------------------------------------------------------

func test_hostile_text_from_the_shipped_multipliers() -> void:
	assert_str(Hud.hostile_text(_config.sanity.madness)).is_equal(
		"The world turns hostile: enemies +70 % speed, −63 % damage taken")


func test_hostile_text_follows_the_config_and_leaves_out_a_part_at_one() -> void:
	var m := _config.sanity.madness
	m.enemy_speed_multiplier = 1.0
	m.enemy_damage_taken_multiplier = 0.7
	assert_str(Hud.hostile_text(m)).is_equal(
		"The world turns hostile: enemies −30 % damage taken")
	m.enemy_speed_multiplier = 1.5
	m.enemy_damage_taken_multiplier = 1.0
	assert_str(Hud.hostile_text(m)).is_equal("The world turns hostile: enemies +50 % speed")
	m.enemy_speed_multiplier = 0.9
	m.enemy_damage_taken_multiplier = 1.1
	assert_str(Hud.hostile_text(m)).is_equal(
		"The world turns hostile: enemies −10 % speed, +10 % damage taken")
	m.enemy_speed_multiplier = 1.0
	m.enemy_damage_taken_multiplier = 1.0
	assert_str(Hud.hostile_text(m)).is_equal("The world turns hostile")


func test_hostile_label_is_visible_only_in_madness() -> void:
	await _start_game()
	_config.sanity.madness.exit_rule = "permanent"  # LT-121: the shipped default "recover" changes the madness text / lets debug through
	var label := _game.hud.hostile_label
	_game.hud.refresh()
	assert_bool(label.visible).is_false()
	for v: float in [50.0, 20.0, 0.5]:
		_set_sanity(v)
		assert_bool(label.visible).override_failure_message(str(v)).is_false()
	_set_sanity(0.0)
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal(Hud.hostile_text(_config.sanity.madness))
	_set_sanity(30.0)  # out again (an exit rule)
	assert_bool(label.visible).is_false()


# --- LT-121: the way out of madness ---------------------------------------------------------

## Rule "recover", exit_sanity 20 and the regen set here; MADNESS at sanity `v` (the state is
## set by hand: sanity_state_for(v) is MADNESS only at 0).
func _recovering(v: float) -> void:
	var cfg := _config.sanity
	cfg.madness.exit_rule = "recover"
	cfg.madness.exit_sanity = 20.0
	cfg.regen_between_waves = 12.0
	cfg.regen_mundane_kill = 0.5
	_game.sim.state.sanity = v
	_game.sim.state.sanity_state = SimState.SanityState.MADNESS
	GameFixture.sync(_game)  # LT-85: poked on the sim directly
	_game.hud.refresh()


func test_recover_text_names_the_target_and_the_regen_from_config() -> void:
	var cfg := _config.sanity
	cfg.regen_between_waves = 12.0
	cfg.regen_mundane_kill = 0.5
	assert_str(Hud.recover_text(cfg, 20.0)).is_equal(
		"Recover at 20 sanity: +12 each dawn, +0.5 per mundane kill")
	assert_str(Hud.recover_text(cfg, 8.0)).is_equal(
		"Recover at 8 sanity: +12 each dawn, +0.5 per mundane kill")
	cfg.regen_mundane_kill = 0.0
	assert_str(Hud.recover_text(cfg, 20.0)).is_equal("Recover at 20 sanity: +12 each dawn")
	assert_str(Hud.recover_text(cfg, 0.0)).is_equal("No room to recover: sell an occult tower")


func test_sanity_bar_shows_the_exit_mark_and_label_only_while_recovering() -> void:
	await _start_game()
	var bar := _game.hud.sanity_bar
	_recovering(7.0)
	assert_float(bar.exit_ratio()).is_equal_approx(20.0 / _config.sanity.max_sanity, 0.0001)
	assert_str(bar.label_text()).is_equal("Sanity 7 / 20 to recover")
	# Not mad, or mad under another rule: no mark, the ordinary label.
	_config.sanity.madness.exit_rule = "permanent"
	assert_float(bar.exit_ratio()).is_equal(0.0)
	assert_str(bar.label_text()).is_equal("Sanity 7  Madness")
	_recovering(7.0)
	_game.sim.state.sanity = 50.0
	_game.sim.state.sanity_state = _game.sim.sanity_state_for(50.0)
	GameFixture.sync(_game)
	assert_float(bar.exit_ratio()).is_equal(0.0)
	assert_bool(bar.label_text().contains("to recover")).is_false()


func test_the_madness_line_adds_the_recover_line_and_at_cap_zero_the_sell_hint() -> void:
	await _start_game()
	var label := _game.hud.hostile_label
	_recovering(7.0)
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal(Hud.hostile_text(_config.sanity.madness) + "\n"
		+ "Recover at 20 sanity: +12 each dawn, +0.5 per mundane kill")
	# Cap 0: reserves fill the bar, so there is nothing to climb to.
	_build_reserve(_config.sanity.max_sanity)
	assert_float(_game.sim.state.sanity_cap).is_equal(0.0)
	_recovering(0.0)
	assert_str(label.text).is_equal(Hud.hostile_text(_config.sanity.madness) + "\n"
		+ "No room to recover: sell an occult tower")
	assert_float(_game.hud.sanity_bar.exit_ratio()).is_equal(0.0)
	assert_bool(_game.hud.sanity_bar.label_text().contains("to recover")).is_false()
