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


func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
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
	assert_int(_game.build(NECRO, _buildable_cell())).is_equal(Simulation.CommandResult.OK)


func _set_sanity(v: float) -> void:
	_game.sim.state.sanity = v
	_game.sim.state.sanity_state = _game.sim.sanity_state_for(v)
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
		"The world turns hostile: enemies +20 % speed, −20 % damage taken")


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
