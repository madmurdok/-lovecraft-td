class_name HudBuyOilTest
extends GdUnitTestSuite
## LT-119: the HUD footer's day "Buy oil" button (Hud.buy_oil_button): shown by day and hidden
## at night, disabled with the sim's refusal as its tooltip, one press = the lighthouse
## panel's Buy oil (GameCommands.buy_flare_oil), re-read on GOLD_CHANGED, and its text is
## LighthousePanel.buy_oil_text over the config. The config's oil numbers are edited to values
## no shipped file has (LT-98), so nothing here pins the roster.

const R := SimCommand.CommandResult
const PRICE := 7
const FLARE_OIL := 5
const CAP := 9
const RICH := 100000

var _vp: SubViewport
var _game: Game
var _hud: Hud
var _s: SimState


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	r.config.economy.oil.price = PRICE
	r.config.economy.oil.cap = CAP
	r.config.economy.flare.cost_oil = FLARE_OIL
	_vp = GameFixture.make_viewport(self)
	_game = GameFixture.make_game(_vp, r.config, 7)
	await get_tree().process_frame
	assert_int(_game.sim.state.phase).is_equal(SimState.Phase.BUILD)
	_hud = _game.hud
	_s = _game.sim.state


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null
	_hud = null
	_s = null


func _upper_first(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1)


func test_the_button_is_shown_by_day_and_hidden_at_night() -> void:
	assert_object(_hud.buy_oil_button).is_not_null()
	_s.gold = RICH
	_hud.refresh()
	assert_bool(_hud.buy_oil_button.visible).is_true()
	assert_bool(_hud.flare_button.visible).is_false()
	assert_int(_game.commands.call_wave()).is_equal(R.OK)  # night: events flush the HUD
	assert_int(_s.phase).is_equal(SimState.Phase.WAVE)
	assert_bool(_hud.buy_oil_button.visible).is_false()
	assert_bool(_hud.flare_button.visible).is_true()


func test_disabled_with_the_refusal_as_its_tooltip() -> void:
	var b := _hud.buy_oil_button
	_s.oil = 0
	_s.gold = RICH
	_hud.refresh()
	assert_bool(b.disabled).is_false()
	# Not enough gold.
	_s.gold = PRICE - 1
	_hud.refresh()
	assert_bool(b.disabled).is_true()
	var poor := _upper_first(CommandText.reason(R.NOT_ENOUGH_GOLD, "buy_oil"))
	assert_str(b.tooltip_text).is_not_empty().is_equal(poor)
	# Tank full (checked before gold, so rich or poor does not matter).
	_s.oil = CAP
	_s.gold = RICH
	_hud.refresh()
	assert_bool(b.disabled).is_true()
	var full := _upper_first(CommandText.reason(R.OIL_FULL, "buy_oil"))
	assert_str(b.tooltip_text).is_not_empty().is_equal(full)
	assert_str(full).is_not_equal(poor)
	# Back to buyable: no refusal text left.
	_s.oil = 0
	_hud.refresh()
	assert_bool(b.disabled).is_false()
	assert_str(b.tooltip_text).is_not_equal(poor).is_not_equal(full)


## One press of the footer button and one press of the panel's button, from the same state,
## do the same thing: gold down by the price, oil up, the same logged commands.
func test_pressing_buys_oil_exactly_like_the_panel() -> void:
	var p := _game.lighthouse_panel
	p.open()
	var seen := []
	for press: Callable in [
			func() -> void: _hud.buy_oil_button.pressed.emit(),
			func() -> void: p.oil_button.pressed.emit()]:
		_s.oil = 0
		_s.gold = RICH
		var n := _s.command_log.size()
		press.call()
		var names := _s.command_log.slice(n).map(func(c: Array) -> String: return c[1])
		seen.append([_s.oil, RICH - _s.gold, names])
	var want_names := []
	for i in FLARE_OIL:
		want_names.append("buy_oil")
	assert_array(seen[0]).is_equal([FLARE_OIL, FLARE_OIL * PRICE, want_names])
	assert_array(seen[1]).is_equal(seen[0])


## GOLD_CHANGED alone (REFRESH_ON) re-reads the button: the gold is changed silently, so only
## the event and the flush can bring the button up to date.
func test_a_gold_event_re_evaluates_the_button() -> void:
	var b := _hud.buy_oil_button
	_s.oil = 0
	_s.gold = 0
	_hud.refresh()
	assert_bool(b.disabled).is_true()
	_s.gold = RICH  # no event yet
	assert_bool(b.disabled).is_true()
	_hud.on_event(SimEvent.new(SimEvent.Type.GOLD_CHANGED, _s.tick, 0,
		{"delta": RICH, "gold": RICH, "reason": "wave_bonus"}))
	_hud.flush()
	assert_bool(b.disabled).is_false()
	_s.gold = 0
	_hud.on_event(SimEvent.new(SimEvent.Type.GOLD_CHANGED, _s.tick, 0,
		{"delta": -RICH, "gold": 0, "reason": "build"}))
	_hud.flush()
	assert_bool(b.disabled).is_true()


## The label is LighthousePanel.buy_oil_text over the config price: a flare's missing oil
## times the price (a full flare's worth when nothing is missing), same as the panel's.
func test_text_is_the_panels_with_the_config_price() -> void:
	var p := _game.lighthouse_panel
	p.open()
	_s.gold = RICH
	_s.oil = 0
	_hud.refresh()
	p.refresh()
	assert_str(_hud.buy_oil_button.text).is_equal(
		"Buy oil for a flare (%s)" % TowerText.money(FLARE_OIL * PRICE))
	assert_str(_hud.buy_oil_button.text).is_equal(LighthousePanel.buy_oil_text(_game.sim))
	assert_str(p.oil_button.text).starts_with(_hud.buy_oil_button.text)
	_s.oil = CAP - 2  # room for 2 units: less than a flare's 5
	_hud.refresh()
	assert_str(_hud.buy_oil_button.text).is_equal(
		"Buy oil for a flare (%s)" % TowerText.money(2 * PRICE))
	_game.sim.config.economy.oil.price = 11  # edited config: the label follows
	_hud.refresh()
	assert_str(_hud.buy_oil_button.text).is_equal(
		"Buy oil for a flare (%s)" % TowerText.money(2 * 11))
