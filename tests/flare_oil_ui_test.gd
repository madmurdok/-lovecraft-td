class_name FlareOilUiTest
extends GdUnitTestSuite
## LT-57 §4/§7 b9: Game.buy_flare_oil() buys min(flare.cost_oil, cap - oil) units, one logged
## sim buy_oil each, stops at the first refusal; and the flare texts in the lighthouse panel
## and the HUD come from the config (price, oil cost, radius by level, seconds).

const R := Simulation.CommandResult

var _vp: SubViewport
var _game: Game


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_vp = SubViewport.new()
	_vp.size = Vector2i(1200, 675)
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


## [result, oil bought, gold spent, new command_log entries] of one buy_flare_oil() click.
func _click(oil: int, gold: int) -> Array:
	var s := _game.sim.state
	s.oil = oil
	s.gold = gold
	var n := s.command_log.size()
	var r := _game.buy_flare_oil()
	var names := s.command_log.slice(n).map(func(c: Array) -> String: return c[1])
	return [r, s.oil - oil, gold - s.gold, names]


func _buys(k: int) -> Array:
	var out := []
	for i in k:
		out.append("buy_oil")
	return out


func test_buy_flare_oil_buys_one_flare_up_to_the_tank_one_logged_unit_each() -> void:
	var eco := _game.sim.config.economy
	var cost := eco.flare.cost_oil
	var price := eco.oil.price
	assert_array([cost, price, eco.oil.cap, eco.oil.start]).is_equal([8, 10, 16, 0])
	assert_int(_game.sim.state.oil).is_equal(0)  # oil.start
	var rich := 100000
	assert_array(_click(0, rich)).is_equal([R.OK, cost, cost * price, _buys(cost)])
	assert_int(cost * price).is_equal(80)  # Q1: a flare's oil is $80
	# min(cost, cap - oil): held oil does not shrink the click below a flare's worth.
	assert_array(_click(3, rich)).is_equal([R.OK, cost, cost * price, _buys(cost)])
	assert_array(_click(12, rich)).is_equal([R.OK, 4, 4 * price, _buys(4)])
	assert_array(_click(16, rich)).is_equal([R.OIL_FULL, 0, 0, []])
	# Poor: buys what it can afford, then stops at the first refusal.
	assert_array(_click(0, 3 * price + 5)).is_equal([R.OK, 3, 3 * price, _buys(3)])
	assert_array(_click(0, price - 1)).is_equal([R.NOT_ENOUGH_GOLD, 0, 0, []])
	assert_int(_game.call_wave()).is_equal(R.OK)
	assert_array(_click(0, rich)).is_equal([R.NOT_BUILD_PHASE, 0, 0, []])


func test_flare_oil_to_buy_is_min_of_cost_and_room_in_the_tank() -> void:
	var s := _game.sim.state
	var got := []
	for oil: int in [0, 3, 8, 12, 15, 16]:
		s.oil = oil
		got.append(_game.flare_oil_to_buy())
	assert_array(got).is_equal([8, 8, 8, 4, 1, 0])


## The panel and HUD texts follow the config, not hard-coded numbers.
func test_panel_and_hud_flare_texts_come_from_the_config() -> void:
	var p := _game.lighthouse_panel
	var h := _game.hud
	var s := _game.sim.state
	var eco := _game.sim.config.economy
	s.gold = 100000
	p.open()
	p.refresh()
	assert_str(p.oil_button.text).starts_with("Buy oil for a flare (%s)" % TowerInfo.money(80))
	assert_str(p.oil_label.text).contains("Flare: 8 oil, radius 6 cells, 5 s")
	assert_str(p.upgrade_button.text).contains("flare radius 8")
	s.oil = 12
	p.refresh()
	assert_str(p.oil_button.text).starts_with("Buy oil for a flare (%s)" % TowerInfo.money(40))
	# Edited config: every number follows.
	eco.oil.price = 7
	eco.flare.cost_oil = 5
	eco.flare.seconds = 3.0
	eco.flare.radius_cells[0] = 4.5
	eco.flare.radius_cells[1] = 7.5
	s.oil = 0
	p.refresh()
	assert_str(p.oil_button.text).starts_with("Buy oil for a flare (%s)" % TowerInfo.money(35))
	assert_str(p.oil_label.text).contains("Flare: 5 oil, radius 4.5 cells, 3 s")
	assert_str(p.upgrade_button.text).contains("flare radius 7.5")
	s.oil = 5
	assert_int(_game.call_wave()).is_equal(R.OK)
	h.refresh()
	assert_str(h.flare_button.text).is_equal("Flare (5 oil)")
	assert_str(h.flare_button.tooltip_text).is_equal("Lights everything within 4.5 cells for 3 s")
	# The radius in the texts follows the lighthouse level.
	s.lighthouse_level = 1
	h.refresh()
	assert_str(h.flare_button.tooltip_text).is_equal("Lights everything within 7.5 cells for 3 s")
