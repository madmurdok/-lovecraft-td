class_name RelicUiTest
extends GdUnitTestSuite
## LT-27 §4 presentation (behaviour 16): relic tokens fly on sim ticks + the clock's alpha,
## land on their credit and dissolve on their vanish; the HUD shows money and the relic stash,
## "Sell relics" works by day only; no player-facing text says "gold".

const T := SimEvent.Type
const R := Simulation.CommandResult
const GOLD_WORD := "(?i)\\bgold\\b"

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
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
	await get_tree().process_frame


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


## Kills a fresh `def_id` (a fake when `fake`) between steps and lets the view consume the
## events; returns the token id.
func _kill(def_id: String, fake := false) -> int:
	var before := _game.relic_tokens.tokens.keys()
	var id := _game.sim.spawn_enemy(def_id, fake)
	_game.sim.apply_damage(id, 1.0e9, "test")
	_game.advance(0.0)
	var added: Array = _game.relic_tokens.tokens.keys().filter(
		func(k: int) -> bool: return not before.has(k))
	assert_int(added.size()).is_equal(1)
	return added[0]


func _steps(n: int) -> void:
	for i in n:
		_game.sim.step()


func _texts() -> Array[String]:
	var out: Array[String] = []
	for n in _game.find_children("*", "", true, false):
		if n is Label:
			out.append((n as Label).text)
		elif n is Button:
			out.append((n as Button).text)
		if n is Control:
			out.append((n as Control).tooltip_text)
	return out


func _assert_no_gold_word(when: String) -> void:
	var re := RegEx.create_from_string(GOLD_WORD)
	for s in _texts():
		assert_bool(re.search(s) == null).override_failure_message(
			"%s: player-facing text says gold: \"%s\"" % [when, s]).is_true()


# --- tokens ---------------------------------------------------------------------------

func test_token_flight_follows_sim_ticks_and_the_clock_alpha() -> void:
	var view := _game.relic_tokens
	var id := _kill("hybrid")
	var tok := view.tokens[id]
	var drop: int = tok["drop_tick"]
	var span: int = tok["arrive_tick"] - drop
	assert_int(span).is_equal(SimTime.ticks(_config.economy.token_fly_seconds))
	assert_float(view.progress(tok)).is_equal(0.0)
	_steps(span / 2)
	_game.advance(0.0)
	assert_float(view.progress(tok)).is_equal_approx(0.5, 1e-6)
	# Paused: real time passes, the token does not move.
	_game.toggle_pause()
	_game.advance(1.0)
	assert_float(view.progress(tok)).is_equal_approx(0.5, 1e-6)
	_game.toggle_pause()
	# Half a tick of real time: no step, the alpha moves the token by half a tick.
	_game.advance(0.5 / SimTime.TICK_RATE)
	assert_int(_game.sim.state.tick).is_equal(drop + span / 2)
	assert_float(view.progress(tok)).is_equal_approx((span / 2 + _game.clock.alpha()) / span,
		1e-6)
	assert_float(_game.clock.alpha()).is_greater(0.0)
	# At progress 1 the token sits on the HUD relic counter.
	var done := {"kind": "bone", "from": Vector2.ZERO, "drop_tick": _game.sim.state.tick - span,
		"arrive_tick": _game.sim.state.tick, "fade": -1.0, "at": Vector2.ZERO}
	assert_float(view.progress(done)).is_equal(1.0)
	var landed: Vector2 = view.pose(done)[0]
	assert_float(landed.distance_to(view.target())).is_less(0.01)
	# The credit event removes it and the counter shows the relic.
	_steps(drop + span - _game.sim.state.tick)
	_game.advance(0.0)
	assert_bool(view.tokens.has(id)).is_false()
	assert_str(_game.hud.relics_label.text).starts_with("Relics: 1 ")


func test_ghost_token_flies_like_a_real_one_then_dissolves_where_it_is() -> void:
	var view := _game.relic_tokens
	var real := _kill("hybrid")
	var ghost := _kill("hybrid", true)
	var vanish := SimTime.ticks(_config.economy.ghost_vanish_seconds)
	_steps(vanish - 1)
	_game.advance(0.0)
	for key: String in ["drop_tick", "arrive_tick", "fade"]:
		assert_that(view.tokens[ghost][key]).is_equal(view.tokens[real][key])
	assert_float(view.progress(view.tokens[ghost])).is_equal(view.progress(view.tokens[real]))
	var pos: Vector2 = view.pose(view.tokens[ghost])[0]
	_steps(1)
	_game.advance(0.0)
	assert_float(view.tokens[ghost]["fade"]).is_greater_equal(0.0)
	assert_float(view.tokens[real]["fade"]).is_less(0.0)
	var frozen: Vector2 = view.tokens[ghost]["at"]
	_steps(10)
	_game.advance(0.0)
	assert_vector(view.tokens[ghost]["at"]).is_equal(frozen)
	assert_float(frozen.distance_to(pos)).is_less(view.target().distance_to(pos))
	_game.advance(RelicTokens.DISSOLVE_SECONDS + 0.01)
	assert_bool(view.tokens.has(ghost)).is_false()
	assert_bool(view.tokens.has(real)).is_true()


# --- HUD ------------------------------------------------------------------------------

func test_hud_shows_money_and_the_relic_stash_and_sells_it_by_day() -> void:
	var s := _game.sim.state
	var hud := _game.hud
	for k: String in {"bone": 2, "amber": 1, "idol": 0, "star_stone": 1}:
		s.relics[k] = {"bone": 2, "amber": 1, "idol": 0, "star_stone": 1}[k]
	var value := 2 * 5 + 15 + 200
	_game.advance(0.0)
	assert_str(hud.gold_label.text).is_equal("Money: $%d" % s.gold)
	assert_str(hud.relics_label.text).is_equal("Relics: 4 (≈ $%d)" % value)
	assert_str(hud.relics_label.tooltip_text).is_equal("\n".join([
		"Bone fragment: 2 × $5", "Amber: 1 × $15", "Idol fragment: 0 × $50",
		"Star-stone of Mnar: 1 × $200"]))
	assert_str(hud.sell_relics_button.text).is_equal("Sell relics (+$%d)" % value)
	assert_bool(hud.sell_relics_button.disabled).is_false()
	var gold := s.gold
	hud.sell_relics_button.pressed.emit()
	_game.advance(0.0)
	assert_int(s.gold).is_equal(gold + value)
	assert_str(hud.gold_label.text).is_equal("Money: $%d" % s.gold)
	assert_str(hud.relics_label.text).is_equal("Relics: 0 (≈ $0)")
	assert_bool(hud.sell_relics_button.disabled).is_true()  # empty stash
	# At night the button is disabled with a stash, and pressing it sells nothing.
	s.relics["amber"] = 3
	assert_int(_game.call_wave()).is_equal(R.OK)
	_game.advance(0.0)
	assert_bool(hud.sell_relics_button.disabled).is_true()
	hud.sell_relics_button.pressed.emit()
	assert_int(s.relics["amber"]).is_equal(3)


func test_no_player_facing_text_says_gold() -> void:
	var cell := Vector2i(-1, -1)
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if cell.x < 0 and m.is_buildable(Vector2i(x, y)):
				cell = Vector2i(x, y)
	assert_int(_game.build("rifleman", cell)).is_equal(R.OK)
	_game.sim.state.gold = 0  # refusal reasons on the picker and upgrade buttons
	_game.sim.state.relics["bone"] = 1
	_game.picker.open_for(cell + Vector2i.RIGHT)
	_game.advance(0.0)
	_assert_no_gold_word("day, picker")
	_game.tower_panel.open_for(_game.sim.state.tower_at[cell])
	_game.advance(0.0)
	_assert_no_gold_word("day, tower view")
	_game.call_wave()
	_game.advance(0.0)
	_assert_no_gold_word("night, tower view")
	_game.sim.state.lighthouse_hp = 0
	_game.sim.step()
	_game.advance(0.0)
	assert_bool(_game.end_screen.visible).is_true()
	_assert_no_gold_word("end screen")
