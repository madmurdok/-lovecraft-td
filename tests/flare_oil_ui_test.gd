class_name FlareOilUiTest
extends GdUnitTestSuite
## LT-57 §4/§7 b9: GameCommands.buy_flare_oil() buys min(flare.cost_oil, cap - oil) units, one
## logged
## sim buy_oil each, stops at the first refusal; and the flare texts in the lighthouse panel
## and the HUD come from the config (price, oil cost, seconds by level).

const R := SimCommand.CommandResult

var _vp: SubViewport
var _game: Game


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_vp = GameFixture.make_viewport(self)
	_game = GameFixture.make_game(_vp, r.config, 7)
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
	var r := _game.commands.buy_flare_oil()
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
	assert_array([cost, price, eco.oil.cap, eco.oil.start]).is_equal([12, 10, 16, 0])
	assert_int(_game.sim.state.oil).is_equal(0)  # oil.start
	var rich := 100000
	assert_array(_click(0, rich)).is_equal([R.OK, cost, cost * price, _buys(cost)])
	assert_int(cost * price).is_equal(120)  # LT-71: a flare's oil is $120
	# min(cost, cap - oil): held oil does not shrink the click below a flare's worth.
	assert_array(_click(3, rich)).is_equal([R.OK, cost, cost * price, _buys(cost)])
	assert_array(_click(12, rich)).is_equal([R.OK, 4, 4 * price, _buys(4)])
	assert_array(_click(16, rich)).is_equal([R.OIL_FULL, 0, 0, []])
	# Poor: buys what it can afford, then stops at the first refusal.
	assert_array(_click(0, 3 * price + 5)).is_equal([R.OK, 3, 3 * price, _buys(3)])
	assert_array(_click(0, price - 1)).is_equal([R.NOT_ENOUGH_GOLD, 0, 0, []])
	assert_int(_game.commands.call_wave()).is_equal(R.OK)
	assert_array(_click(0, rich)).is_equal([R.NOT_BUILD_PHASE, 0, 0, []])


func test_flare_oil_to_buy_is_min_of_cost_and_room_in_the_tank() -> void:
	var s := _game.sim.state
	var got := []
	for oil: int in [0, 3, 8, 12, 15, 16]:
		s.oil = oil
		got.append(_game.sim.oil_for_flare())
	assert_array(got).is_equal([12, 12, 8, 4, 1, 0])


## The panel and HUD texts follow the config, not hard-coded numbers.
func test_panel_and_hud_flare_texts_come_from_the_config() -> void:
	var p := _game.lighthouse_panel
	var h := _game.hud
	var s := _game.sim.state
	var eco := _game.sim.config.economy
	s.gold = 100000
	p.open()
	p.refresh()
	assert_str(p.oil_button.text).starts_with("Buy oil for a flare (%s)" % TowerText.money(120))
	assert_str(p.oil_label.text).contains("Flare: 12 oil, whole map, 5 s")
	assert_str(p.upgrade_button.text).contains("flare 6 s")
	s.oil = 12
	p.refresh()
	assert_str(p.oil_button.text).starts_with("Buy oil for a flare (%s)" % TowerText.money(40))
	# Edited config: every number follows.
	eco.oil.price = 7
	eco.flare.cost_oil = 5
	eco.flare.seconds[0] = 3.0
	eco.flare.seconds[1] = 4.5
	s.oil = 0
	p.refresh()
	assert_str(p.oil_button.text).starts_with("Buy oil for a flare (%s)" % TowerText.money(35))
	assert_str(p.oil_label.text).contains("Flare: 5 oil, whole map, 3 s")
	assert_str(p.upgrade_button.text).contains("flare 4.5 s")
	s.oil = 5
	assert_int(_game.commands.call_wave()).is_equal(R.OK)
	h.refresh()
	assert_str(h.flare_button.text).is_equal("Flare (5 oil)")
	assert_str(h.flare_button.tooltip_text).is_equal("Lights the whole map for 3 s")
	# LT-69: the seconds in the texts follow the lighthouse level.
	s.lighthouse_level = 1
	h.refresh()
	assert_str(h.flare_button.tooltip_text).is_equal("Lights the whole map for 4.5 s")


## LT-69/S2: shipped seconds 5 / 6 / 7 reach the HUD tooltip and the panel at every level;
## the upgrade line names the next level's seconds and none at the top.
func test_shipped_flare_seconds_reach_the_hud_and_the_panel_per_level() -> void:
	var p := _game.lighthouse_panel
	var h := _game.hud
	var s := _game.sim.state
	s.gold = 100000
	s.oil = _game.sim.config.economy.flare.cost_oil
	assert_int(_game.commands.call_wave()).is_equal(R.OK)
	p.open()
	var seconds := ["5", "6", "7"]
	for level in 3:
		s.lighthouse_level = level
		h.refresh()
		p.refresh()
		assert_str(h.flare_button.tooltip_text).is_equal(
			"Lights the whole map for %s s" % seconds[level])
		assert_str(p.oil_label.text).contains("whole map, %s s" % seconds[level])
		if level < 2:
			assert_str(p.upgrade_button.text).contains("flare %s s" % seconds[level + 1])
		else:
			assert_str(p.upgrade_button.text).is_equal("Max level")
