class_name SimRuleQueriesTest
extends TowerTestBase
## LT-76 (LT-65 §3.2): the Simulation's read-only rule queries (light_at, tower_mults,
## tower_at_cell, oil_for_flare, oil_cap, flare_cost_oil, flare_burn), and the one-source
## property: the UI, the HUD and the bot read these same answers, never a copy.
## Map: tower row y = 1, a tower at cell (x, 1) has its centre at (x + 0.5, 1.5). Searchlight
## L1 range 3, Elder Sign L1 range 2.5. Phase NONE shines (night); the default fixture
## beam is dark, so only casters and the flare light or shadow a tower. No DPS from ticks
## here (LT-89).

const SL := "searchlight"
const SIGN := "elder_sign"
const RIFLE := "rifleman"
const RES := "resonator"
const BOT_PATH := "res://tools/bot_runs.gd"
const Placement := preload("res://tools/bot/bot_placement.gd")

var _bot_script: GDScript
var _bots: Array[Object] = []


func after_test() -> void:
	for b in _bots:
		if is_instance_valid(b):
			b.free()
	_bots.clear()


func _sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	return sim


## A still lighthouse beam that lights the default tower cell (as light_shadow_test).
func _beam_sim() -> Simulation:
	lit_beam = true
	var sim := tsim()
	lit_beam = false
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	return sim


func _at(x: int) -> Vector2i:
	return Vector2i(x, 1)


func _c(x: float) -> Vector2:
	return Vector2(x, 1.5)


func _fire_flare(sim: Simulation) -> void:
	sim.state.oil = 2 * sim.config.economy.flare.cost_oil
	assert_int(sim.fire_flare()).is_equal(SimCommand.CommandResult.OK)


## A bot harness instance whose constructor does nothing (see bot_upgrade_test).
func _bot() -> Object:
	if _bot_script == null:
		var src := FileAccess.get_file_as_string(BOT_PATH)
		assert_bool(src.contains("func _init() -> void:")).is_true()
		_bot_script = GDScript.new()
		_bot_script.source_code = src.replace("func _init() -> void:", "func _unused_init() -> void:")
		assert_int(_bot_script.reload()).is_equal(OK)
	var b: Object = _bot_script.new()
	_bots.append(b)
	return b


# --- light_at ---------------------------------------------------------------------------

func test_light_at_counts_casters_inclusive_and_skips_the_asker() -> void:
	var sim := _sim()
	var sl := build(sim, SL, _at(3))  # centre (3.5, 1.5), range 3
	var edge := sim.light_at(_c(6.5))
	assert_int(edge["light_casters"]).is_equal(1)
	assert_int(edge["shadow_casters"]).is_equal(0)
	assert_bool(edge["lit"]).is_true()
	assert_bool(edge["shadowed"]).is_false()
	assert_bool(edge["beam"]).is_false()  # a caster is not the beam
	var out := sim.light_at(_c(6.51))
	assert_int(out["light_casters"]).is_equal(0)
	assert_bool(out["lit"]).is_false()
	# The caster's own centre: counted for anyone else, never for itself (skip_id).
	assert_int(sim.light_at(sl.centre())["light_casters"]).is_equal(1)
	assert_int(sim.light_at(sl.centre(), sl.id)["light_casters"]).is_equal(0)
	assert_bool(sim.light_at(sl.centre(), sl.id)["lit"]).is_false()


func test_light_at_shadow_and_cancel() -> void:
	var sim := _sim()
	build(sim, SIGN, _at(7))  # centre 7.5, range 2.5
	var p := _c(5.5)  # 2 cells away
	var dark := sim.light_at(p)
	assert_bool(dark["shadowed"]).is_true()
	assert_bool(dark["lit"]).is_false()
	assert_int(dark["shadow_casters"]).is_equal(1)
	build(sim, SL, _at(3))  # centre 3.5, range 3: 2 cells from p
	var both := sim.light_at(p)
	assert_int(both["light_casters"]).is_equal(1)
	assert_int(both["shadow_casters"]).is_equal(1)
	assert_bool(both["lit"]).is_false()  # light and shadow cancel to neither
	assert_bool(both["shadowed"]).is_false()


func test_light_at_by_day_has_counts_but_no_light_or_beam() -> void:
	var sim := _sim()
	build(sim, SL, _at(3))
	assert_bool(sim.light_at(_c(5.5))["lit"]).is_true()  # night
	sim.state.phase = SimState.Phase.BUILD
	var day := sim.light_at(_c(5.5))
	assert_int(day["light_casters"]).is_equal(1)  # geometry does not depend on the hour
	assert_bool(day["lit"]).is_false()
	assert_bool(day["beam"]).is_false()


func test_light_at_flare_is_beam_everywhere_while_it_burns() -> void:
	var sim := _sim()
	var far := _c(0.5)
	assert_bool(sim.light_at(far)["beam"]).is_false()
	_fire_flare(sim)
	var burning := sim.light_at(far)
	assert_bool(burning["beam"]).is_true()
	assert_bool(burning["lit"]).is_true()
	assert_int(burning["light_casters"]).is_equal(0)  # the flare is not a caster tower


func test_light_at_a_tower_centre_equals_the_flags_the_sim_sets() -> void:
	# Beam only, beam + sign (cancel), sign only, searchlight only: the query and the
	# per-tick _update_beam agree on every tower (one _light_flags).
	var cases := [[true, false], [true, true], [false, true], [false, false]]
	for case: Array in cases:
		var sim := _beam_sim() if case[0] else _sim()
		var t := build(sim, RIFLE)
		if case[1]:
			build(sim, SIGN, _at(9))
		else:
			build(sim, SL, _at(9))  # range 3 covers cell 7? 2 cells away: lights it
		for i in 2:
			sim.step()
		var q := sim.light_at(t.centre(), t.id)
		assert_array([q["lit"], q["shadowed"]]).override_failure_message(
			"case %s" % [case]).is_equal([t.lit, t.shadowed])
	# Beam alone really lights the default cell, and the query says it was the beam.
	var b := _beam_sim()
	var rb := build(b, RIFLE)
	b.step()
	assert_bool(rb.lit).is_true()
	assert_bool(b.light_at(rb.centre(), rb.id)["beam"]).is_true()


func test_light_at_is_read_only() -> void:
	var sim := _beam_sim()
	var t := build(sim, RIFLE)
	build(sim, SIGN, _at(9))
	sim.step()
	var before := [t.lit, t.shadowed, sim.state.tick, sim.state.beam_dx, sim.state.beam_dy,
		sim.drain_events().size()]
	for i in 5:
		sim.light_at(t.centre(), t.id)
	assert_array([t.lit, t.shadowed, sim.state.tick, sim.state.beam_dx, sim.state.beam_dy,
		sim.drain_events().size()]).is_equal(before.slice(0, 5) + [0])


# --- tower_at_cell, tower_mults -----------------------------------------------------------

func test_tower_at_cell_returns_the_tower_or_null() -> void:
	var sim := _sim()
	assert_object(sim.tower_at_cell(TOWER)).is_null()
	var t := build(sim, RIFLE)
	assert_object(sim.tower_at_cell(TOWER)).is_same(t)
	assert_object(sim.tower_at_cell(_at(8))).is_null()


func _distinct_mults(sim: Simulation) -> void:
	var beam := sim.config.economy.beam
	beam.mundane_fire_interval_mult = 0.5
	beam.mundane_ignore_miss = true
	beam.occult_power_mult = 0.5
	var shadow := sim.config.economy.shadow
	shadow.mundane_fire_interval_mult = 2.0
	shadow.mundane_miss_chance_add = 0.25
	shadow.occult_power_mult = 3.0


func test_tower_mults_follow_the_tower_state() -> void:
	var sim := _beam_sim()
	_distinct_mults(sim)
	assert_dict(sim.tower_mults(12345)).is_empty()  # no such tower
	var lit := build(sim, RIFLE)
	var dark := build(sim, RIFLE, _at(10))
	build(sim, SIGN, _at(12))  # shadows cell 10, not cell 7 (5 cells away)
	var occ := build(sim, RES, _at(9))  # in the beam? only its flags matter below
	sim.step()
	assert_array([lit.lit, lit.shadowed]).is_equal([true, false])
	assert_dict(sim.tower_mults(lit.id)).is_equal({"power_mult": 1.0, "interval_mult": 0.5,
		"ignore_miss": true, "miss_add": 0.0, "disabled": false})
	assert_array([dark.lit, dark.shadowed]).is_equal([false, true])
	assert_dict(sim.tower_mults(dark.id)).is_equal({"power_mult": 1.0, "interval_mult": 2.0,
		"ignore_miss": false, "miss_add": 0.25, "disabled": false})
	# Whatever the flags are, the answer is the rule applied to them.
	assert_dict(sim.tower_mults(occ.id)).is_equal(
		TowerRules.light_effect(occ.def, sim.config, occ.lit, occ.shadowed).merged(
			{"disabled": false}))


# --- oil and flare ------------------------------------------------------------------------

func test_oil_for_flare_at_cap_empty_and_partial() -> void:
	var sim := _sim()
	var eco := sim.config.economy
	eco.oil.cap = 16
	eco.flare.cost_oil = 12
	var got := []
	for oil: int in [0, 3, 4, 8, 12, 15, 16]:
		sim.state.oil = oil
		got.append(sim.oil_for_flare())
	assert_array(got).is_equal([12, 12, 12, 8, 4, 1, 0])  # min(cost, cap - oil)


func test_oil_for_flare_without_blocks() -> void:
	var sim := _sim()
	var eco := sim.config.economy
	eco.oil.cap = 16
	sim.state.oil = 5
	eco.flare = null  # no flare block: one unit a click
	assert_int(sim.oil_for_flare()).is_equal(1)
	sim.state.oil = 16
	assert_int(sim.oil_for_flare()).is_equal(0)
	eco.oil = null  # no oil block: nothing to buy
	assert_int(sim.oil_for_flare()).is_equal(0)


func test_oil_cap_and_flare_cost_oil_read_the_config_and_are_zero_without_the_block() -> void:
	var sim := _sim()
	var eco := sim.config.economy
	eco.oil.cap = 9
	eco.flare.cost_oil = 7
	assert_int(sim.oil_cap()).is_equal(9)
	assert_int(sim.flare_cost_oil()).is_equal(7)
	eco.oil = null
	eco.flare = null
	assert_int(sim.oil_cap()).is_equal(0)
	assert_int(sim.flare_cost_oil()).is_equal(0)


func test_flare_burn_total_never_below_left_and_follows_the_level() -> void:
	var sim := _sim()
	var seconds := sim.config.economy.flare.seconds
	seconds[0] = 5.0
	seconds[2] = 7.0
	assert_dict(sim.flare_burn()).is_equal({"left_ticks": 0, "total_ticks": 0})
	_fire_flare(sim)
	var n := SimTime.ticks(5.0)
	assert_dict(sim.flare_burn()).is_equal({"left_ticks": n, "total_ticks": n})
	sim.step()
	sim.step()
	assert_dict(sim.flare_burn()).is_equal({"left_ticks": n - 2, "total_ticks": n})
	# The total is a flare fired now at the current level: an upgrade lengthens it.
	sim.state.lighthouse_level = 2
	assert_dict(sim.flare_burn()).is_equal({"left_ticks": n - 2, "total_ticks": SimTime.ticks(7.0)})
	# ... and never reads below what is left (a flare fired at L3, level dropped).
	var sim2 := _sim()
	sim2.config.economy.flare.seconds[0] = 5.0
	sim2.config.economy.flare.seconds[2] = 7.0
	sim2.state.lighthouse_level = 2
	_fire_flare(sim2)
	sim2.state.lighthouse_level = 0
	var m := SimTime.ticks(7.0)
	assert_dict(sim2.flare_burn()).is_equal({"left_ticks": m, "total_ticks": m})
	# Burnt out: back to zeros.
	for i in m + 1:
		sim2.step()
	assert_dict(sim2.flare_burn()).is_equal({"left_ticks": 0, "total_ticks": 0})


# --- one source: UI reads the sim's answers ------------------------------------------------

## LT-89: the seconds between shots the sim fires at `interval_s`: whole 30 Hz ticks.
func _period(interval_s: float) -> float:
	return maxi(1, roundi(interval_s * SimTime.TICK_RATE)) / float(SimTime.TICK_RATE)


## LT-89: a mundane fire-rate percent at multiplier `m`: base period / period at m - 1.
func _rate(interval_s: float, m: float) -> float:
	return (_period(interval_s) / _period(interval_s * m) - 1.0) * 100.0


func test_tower_info_lit_text_equals_the_sims_tower_mults() -> void:
	var sim := _beam_sim()
	_distinct_mults(sim)
	var cfg := sim.config
	var lit := build(sim, RIFLE)
	var dark := build(sim, RIFLE, _at(10))
	build(sim, SIGN, _at(12))
	sim.step()
	var lvl := lit.stats()
	var m_lit := sim.tower_mults(lit.id)
	var m_dark := sim.tower_mults(dark.id)
	# Lit: every cell, the percent and the no-miss tail come from the same multipliers.
	var v_lit := TowerText.lit_values(lit.def, lvl, cfg)
	assert_str(v_lit["every"]).is_equal(
		TowerText.every_text(_period(lvl.fire_interval * m_lit["interval_mult"]))
		+ TowerText.LIT_MARK)
	assert_str(TowerText.lit_line(lit.def, lvl, cfg)).is_equal(
		TowerText.NOW_LIT + "fire +%s%%, no misses" % TowerText.num(
			roundf(_rate(lvl.fire_interval, m_lit["interval_mult"]))))
	# Shadowed: the same, with the sim's miss_add.
	var v_dark := TowerText.lit_values(dark.def, dark.stats(), cfg, -1.0, true)
	assert_str(v_dark["every"]).is_equal(
		TowerText.every_text(_period(dark.stats().fire_interval * m_dark["interval_mult"]))
		+ TowerText.LIT_MARK)
	assert_str(TowerText.lit_line(dark.def, dark.stats(), cfg, true)).is_equal(
		TowerText.NOW_SHADOW + "fire %s%s%%, +%s%% misses" % [TowerText.MINUS,
			TowerText.num(roundf(absf(_rate(dark.stats().fire_interval, m_dark["interval_mult"])))),
			TowerText.num(m_dark["miss_add"] * 100.0)])
	assert_float(m_dark["miss_add"]).is_equal(0.25)


func test_tower_info_occult_lit_damage_equals_the_sims_power_mult() -> void:
	var sim := _beam_sim()
	_distinct_mults(sim)
	var res := build(sim, RES, TOWER)
	sim.step()
	assert_bool(res.lit).is_true()
	var pm: float = sim.tower_mults(res.id)["power_mult"]
	assert_float(pm).is_equal(0.5)
	var s := res.stats()
	var v := TowerText.lit_values(res.def, s, sim.config, -1.0)
	assert_str(v["damage"]).is_equal(TowerText.num(s.damage * pm) + TowerText.LIT_MARK)
	assert_float(TowerStatsModel.beam_percent(res.def, s, sim.config)).is_equal((pm - 1.0) * 100.0)


func test_hud_and_game_flare_oil_equal_the_sims_oil_rules() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var vp := GameFixture.make_viewport(self)
	var game := GameFixture.make_game(vp, r.config, 7)
	await get_tree().process_frame
	var sim := game.sim
	sim.config.economy.oil.cap = 9
	sim.config.economy.flare.cost_oil = 6
	var got := []
	for oil: int in [0, 2, 5, 9]:
		sim.state.oil = oil
		assert_int(game.sim.oil_for_flare()).is_equal(sim.oil_for_flare())
		got.append(game.sim.oil_for_flare())
	assert_array(got).is_equal([6, 6, 4, 0])
	sim.state.oil = 4
	GameFixture.sync(game)  # LT-85: poked on the sim directly
	game.hud.refresh()
	assert_str(game.hud.oil_label.text).is_equal("Oil 4 / %d" % sim.oil_cap())
	assert_int(sim.oil_cap()).is_equal(9)
	sim.state.phase = SimState.Phase.WAVE  # the flare button shows at night
	GameFixture.sync(game)
	game.hud.refresh()
	assert_str(game.hud.flare_button.text).is_equal("Flare (%d oil)" % sim.flare_cost_oil())
	game.lighthouse_panel.open()
	game.lighthouse_panel.refresh()
	assert_str(game.lighthouse_panel.oil_label.text).contains(
		"Lamp oil: 4 / %d" % sim.oil_cap())
	assert_str(game.lighthouse_panel.oil_label.text).contains(
		"Flare: %d oil" % sim.flare_cost_oil())
	vp.queue_free()


func test_flare_strength_reads_the_sims_burn() -> void:
	var sim := _sim()
	assert_float(Lighting.flare_strength(sim)).is_equal(0.0)
	_fire_flare(sim)
	var burn := sim.flare_burn()
	assert_int(burn["left_ticks"]).is_greater(0)
	assert_float(Lighting.flare_strength(sim)).is_greater(0.0)
	# Burn edited out from under it: strength follows flare_burn, nothing of its own.
	sim.state.flare_ticks_left = 0
	assert_float(Lighting.flare_strength(sim)).is_equal(0.0)


# --- one source: the bot asks the sim's light_at --------------------------------------------

func test_bot_light_checks_equal_the_sims_light_at() -> void:
	var bot := _bot()
	var sim := _beam_sim()
	var rifle := build(sim, RIFLE)
	sim.step()
	# Beam only: the bot's lit check, the sim's flag and light_at's casters agree.
	assert_bool(rifle.lit).is_true()
	assert_bool(bot.call("_beam_lit", sim, rifle)).is_true()
	# A Searchlight in range lights it too, but not by the beam: the bot's check is
	# light_at's light_casters == 0, so it drops to false while the sim flag stays lit.
	build(sim, SL, _at(9))
	sim.step()
	assert_bool(rifle.lit).is_true()
	var q := sim.light_at(rifle.centre(), rifle.id)
	assert_int(q["light_casters"]).is_equal(1)
	assert_bool(bot.call("_beam_lit", sim, rifle)).is_equal(int(q["light_casters"]) == 0)
	assert_bool(bot.call("_beam_lit", sim, rifle)).is_false()
	# Shadow radius: the bot asks light_at's shadow_casters on a cell centre.
	var s2 := _sim()
	build(s2, SIGN, _at(7))
	for x in [4, 5, 6, 8, 9, 10]:
		var cell := _at(x)
		var want: bool = int(s2.light_at(s2.state.map.grid.centre(cell))["shadow_casters"]) > 0
		assert_bool(Placement.in_shadow_radius(s2, cell)).override_failure_message(
			"cell %d" % x).is_equal(want)
	assert_bool(Placement.in_shadow_radius(s2, _at(6))).is_true()
	assert_bool(Placement.in_shadow_radius(s2, _at(3))).is_false()
