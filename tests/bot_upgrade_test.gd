class_name BotUpgradeTest
extends SimTestBase
## LT-24 §5 bot "wide then deep" (Decision 6): build BUILD_FIRST towers first, then the
## cheapest upgrade (ties -> lower id), L3 from BRANCH_PICK (or `--branch=`, LT-29), pending
## branches skipped (none since LT-29), the occult sanity guard, no upgrade during a wave, and
## `--upgrades=0`.
## tools/bot_runs.gd is a SceneTree script whose _init plays every run and quits, so the
## suite compiles a copy of its source with _init renamed and calls the bot's functions on
## constructed sims (real res://data config). The L3 pick is pinned here, not on full runs:
## with today's config no bot reaches L3 (LT-24/S2 behaviour 13 correction).

const BOT_PATH := "res://tools/bot_runs.gd"
const R := Simulation.CommandResult
const RIFLE := "rifleman"
const HARP := "harpooner"
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"
## RUN keys of the pre-LT-24 harness (`--upgrades=0` must print exactly these).
const BASELINE_KEYS := ["strategy", "seed", "outcome", "waves_survived", "gold",
	"final_sanity", "wave_end_sanity", "seconds", "fakes", "astray", "missed", "shots",
	"towers", "lighthouse_hp", "ticks"]
## RUN keys LT-23 §4 appends to every line, upgrades on or off.
const LT23_KEYS := ["min_sanity", "final_cap", "cap_per_wave", "madness_tick", "reserve_peak",
	"free_reserve", "hp_lost_per_wave", "towers_final"]
## RUN keys LT-27 §5 appends to every line, upgrades on or off.
const LT27_KEYS := ["relics_sold", "drops", "star_stones", "wage"]
## RUN keys LT-30 §3.4 appends to every line, upgrades on or off.
const LT30_KEYS := ["lighthouse_level", "flares", "oil_bought", "oil_gold", "lit_shots"]

var _bot_script: GDScript
var _bots: Array[Object] = []


func after_test() -> void:
	for b in _bots:
		if is_instance_valid(b):
			b.free()
	_bots.clear()


## A bot harness instance whose constructor does nothing; `_cfg` is the real config.
func _bot(upgrades := true, lighthouse := true, flare := true) -> Object:
	if _bot_script == null:
		var src := FileAccess.get_file_as_string(BOT_PATH)
		assert_bool(src.contains("func _init() -> void:")).is_true()
		_bot_script = GDScript.new()
		_bot_script.source_code = src.replace("func _init() -> void:", "func _unused_init() -> void:")
		assert_int(_bot_script.reload()).is_equal(OK)
	var b: Object = _bot_script.new()
	_bots.append(b)
	b.set("_cfg", real_config())
	b.set("_upgrades", upgrades)
	b.set("_lighthouse", lighthouse)
	b.set("_flare", flare)
	return b


## LT-30: money the bot spends by day topping the lamp oil up from oil.start to
## BOT_OIL_TARGET, before any build or upgrade.
func _oil_topup() -> int:
	var target: int = _bot().get_script().get_script_constant_map()["BOT_OIL_TARGET"]
	var oil := real_config().economy.oil
	return maxi(0, target - oil.start) * oil.price


## A fresh res://data config the test may edit (real_config() is shared by the suite).
func _fresh() -> GameConfig:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config


## Real-config (or `cfg`) sim with a WaveDirector, stepped into the first build phase.
func _sim(gold := 0, cfg: GameConfig = null) -> Simulation:
	if cfg == null:
		cfg = real_config()
	var sim := Simulation.new(cfg, 1000)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	sim.state.gold = gold
	sim.drain_events()
	return sim


func _cells(sim: Simulation) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var m := sim.state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m.is_buildable(c) and not sim.state.tower_at.has(c):
				out.append(c)
	return out


## Builds `def_id` on the first free buildable cell and raises it to `level` (0-based;
## 2 needs `branch`), paying from a temporary gold top-up.
func _place(sim: Simulation, def_id: String, level := 0, branch := "") -> SimTower:
	var gold := sim.state.gold
	sim.state.gold = 100000
	var cell := _cells(sim)[0]
	assert_int(sim.build_tower(def_id, cell)).is_equal(R.OK)
	var t := sim.tower_by_id(sim.state.tower_at[cell])
	if level >= 1:
		assert_int(sim.upgrade_tower(t.id)).is_equal(R.OK)
	if level >= 2:
		assert_int(sim.upgrade_tower(t.id, branch)).is_equal(R.OK)
	sim.state.gold = gold
	sim.drain_events()
	return t


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _next(sim: Simulation, strat: String) -> Array:
	return _bot().call("_next_upgrade", sim, strat)


# --- _next_upgrade: L3 picks ---------------------------------------------------------------

## LT-29: the Marksman is wired (not pending), so the occult bot buys it too, cheapest first.
func test_occult_buys_the_marksman_and_the_pure_branches_cheapest_first() -> void:
	var sim := _sim()
	var rifle := _place(sim, RIFLE, 1)
	var sign := _place(sim, SIGN, 1)
	var necro := _place(sim, NECRO, 1)
	var cfg := real_config()
	assert_bool(cfg.towers[RIFLE].branches["a"].has_pending()).is_false()
	assert_int(cfg.towers[RIFLE].branches["a"].upgrade_cost) \
		.is_less(cfg.towers[SIGN].branches["a"].upgrade_cost)
	assert_int(cfg.towers[SIGN].branches["a"].upgrade_cost) \
		.is_less(cfg.towers[NECRO].branches["a"].upgrade_cost)
	assert_array(_next(sim, "occult")).is_equal([rifle.id, "a"])
	sim.state.towers.erase(rifle)
	assert_array(_next(sim, "occult")).is_equal([sign.id, "a"])
	sim.state.towers.erase(sign)
	assert_array(_next(sim, "occult")).is_equal([necro.id, "a"])
	sim.state.towers.erase(necro)
	assert_array(_next(sim, "occult")).is_empty()


## LT-29: the Corrupted Seal is wired, so the madness bot buys it (cheaper than the Rite).
func test_madness_buys_the_corrupted_seal_then_the_corrupted_rite() -> void:
	var sim := _sim()
	var sign := _place(sim, SIGN, 1)
	var necro := _place(sim, NECRO, 1)
	assert_bool(real_config().towers[SIGN].branches["b"].has_pending()).is_false()
	assert_int(real_config().towers[SIGN].branches["b"].upgrade_cost) \
		.is_less(real_config().towers[NECRO].branches["b"].upgrade_cost)
	assert_array(_next(sim, "madness")).is_equal([sign.id, "b"])
	sim.state.towers.erase(sign)
	assert_array(_next(sim, "madness")).is_equal([necro.id, "b"])


## LT-29: both mundane picks (Marksman, Barbed) are wired, so the bot takes them to L3.
func test_mundane_buys_the_marksman_then_barbed() -> void:
	var sim := _sim()
	var rifle := _place(sim, RIFLE, 1)
	var harp := _place(sim, HARP, 1)
	assert_int(real_config().towers[RIFLE].branches["a"].upgrade_cost) \
		.is_less(real_config().towers[HARP].branches["a"].upgrade_cost)
	assert_array(_next(sim, "mundane")).is_equal([rifle.id, "a"])
	sim.state.towers.erase(rifle)
	assert_array(_next(sim, "mundane")).is_equal([harp.id, "a"])


## LT-29 §4.3: `--branch=<tower>:<a|b>` wins over BRANCH_PICK for that tower (in every
## strategy, even one without a pick for it); other towers keep the strategy's pick.
func test_branch_override_wins_over_branch_pick() -> void:
	var sim := _sim()
	var rifle := _place(sim, RIFLE, 1)
	var harp := _place(sim, HARP, 1)
	var b := _bot()
	b.set("_branch_override", {RIFLE: "b"})
	assert_array(b.call("_next_upgrade", sim, "mundane")).is_equal([rifle.id, "b"])
	sim.state.towers.erase(rifle)
	assert_array(b.call("_next_upgrade", sim, "mundane")).is_equal([harp.id, "a"])
	b.set("_branch_override", {HARP: "b"})
	assert_array(b.call("_next_upgrade", sim, "mundane")).is_equal([harp.id, "b"])
	# madness has no harpooner pick: the override alone makes it buyable.
	assert_array(b.call("_next_upgrade", sim, "madness")).is_equal([harp.id, "b"])
	# The strategy table itself is untouched.
	var picks: Dictionary = b.get_script().get_script_constant_map()["BRANCH_PICK"]
	assert_str(picks["mundane"][HARP]).is_equal("a")


func test_a_tower_missing_from_branch_pick_stays_at_l2() -> void:
	var sim := _sim()
	_place(sim, RIFLE, 1)  # madness has no rifleman pick
	_place(sim, HARP, 1)
	assert_array(_next(sim, "madness")).is_empty()


func test_l3_towers_offer_nothing() -> void:
	var sim := _sim()
	_place(sim, NECRO, 2, "a")
	_place(sim, SIGN, 2, "a")
	assert_array(_next(sim, "occult")).is_empty()


# --- _next_upgrade: cheapest first, ties, guard ------------------------------------------

func test_cheapest_upgrade_first_over_all_towers() -> void:
	var sim := _sim()
	var cfg := real_config()
	var necro := _place(sim, NECRO, 1)
	var harp := _place(sim, HARP)
	var rifle := _place(sim, RIFLE)
	assert_int(cfg.towers[RIFLE].levels[1].upgrade_cost).is_less(cfg.towers[HARP].levels[1].upgrade_cost)
	assert_array(_next(sim, "mundane")).is_equal([rifle.id, ""])
	sim.state.towers.erase(rifle)
	assert_array(_next(sim, "mundane")).is_equal([harp.id, ""])
	sim.state.towers.erase(harp)
	assert_array(_next(sim, "occult")).is_equal([necro.id, "a"])


func test_equal_costs_go_to_the_lower_tower_id_whatever_the_list_order() -> void:
	var sim := _sim()
	var first := _place(sim, RIFLE)
	var second := _place(sim, RIFLE)
	assert_int(first.id).is_less(second.id)
	assert_array(_next(sim, "mundane")).is_equal([first.id, ""])
	sim.state.towers.reverse()
	assert_array(_next(sim, "mundane")).is_equal([first.id, ""])


## LT-23 pin 20: the occult cap guard skips an upgrade whose reserve delta would leave the
## cap below CAP_FLOOR (30), exactly 30 passes; other candidates are still bought.
func test_occult_cap_guard_skips_an_upgrade_leaving_the_cap_below_30() -> void:
	var cfg := _fresh()
	var floors: Dictionary = _bot().get_script().get_script_constant_map()["CAP_FLOOR"]
	assert_dict(floors).is_equal({"occult": 30.0, "mixed": 60.0})
	var top := cfg.sanity.max_sanity
	var sim := _sim(0, cfg)
	var sign := _place(sim, SIGN)
	var rifle := _place(sim, RIFLE, 2, "a")  # L3 (LT-29: no pending branch left): nothing to buy
	cfg.towers[SIGN].levels[1].sanity_reserve = top - 30.0  # leaves exactly 30: allowed
	assert_array(_next(sim, "occult")).is_equal([sign.id, ""])
	cfg.towers[SIGN].levels[1].sanity_reserve = top - 29.5  # leaves 29.5: skipped
	assert_array(_next(sim, "occult")).is_empty()
	# The guard skips only that upgrade: another candidate is still bought.
	var necro := _place(sim, NECRO)
	assert_array(_next(sim, "occult")).is_equal([necro.id, ""])
	assert_int(rifle.level).is_equal(2)


func test_madness_has_no_cap_guard() -> void:
	var cfg := _fresh()
	var sim := _sim(0, cfg)
	var sign := _place(sim, SIGN)
	cfg.towers[SIGN].levels[1].sanity_reserve = cfg.sanity.max_sanity  # cap to 0
	assert_array(_next(sim, "madness")).is_equal([sign.id, ""])


# --- _act: wide then deep, waves, --upgrades=0 --------------------------------------------

## Gold for the first `n` items of the mundane build order (rifle, rifle, harp, ...).
func _mundane_builds(n: int) -> int:
	var total := 0
	for i in n:
		total += real_config().towers[HARP if i % 3 == 2 else RIFLE].cost
	return total


func _levels(sim: Simulation) -> Array:
	var out := []
	for t in sim.state.towers:
		out.append(t.level)
	return out


func test_no_upgrade_before_five_towers() -> void:
	var first := _bot().get_script().get_script_constant_map()["BUILD_FIRST"] as int
	assert_int(first).is_equal(5)
	# Gold for 4 builds + one rifleman L2: the bot builds 4 and saves for the 5th.
	var sim := _sim(_mundane_builds(4) + real_config().towers[RIFLE].levels[1].upgrade_cost)
	_bot().call("_act", sim, "mundane", 0, {})
	assert_array(_levels(sim)).is_equal([0, 0, 0, 0])


func test_after_five_towers_the_cheapest_upgrade_is_bought() -> void:
	var up := real_config().towers[RIFLE].levels[1].upgrade_cost
	var sim := _sim(_mundane_builds(5) + up + _oil_topup())
	var built := {}
	var idx: int = _bot().call("_act", sim, "mundane", 0, built)
	assert_int(idx).is_equal(5)
	assert_array(_levels(sim)).is_equal([1, 0, 0, 0, 0])
	assert_int(sim.state.gold).is_greater_equal(0)
	assert_bool(sim.state.command_log.any(
		func(c: Array) -> bool: return c[1] == "upgrade" and c[2] == sim.state.towers[0].id)) \
		.is_true()


func test_a_refused_upgrade_mid_wave_ends_the_round_without_building() -> void:
	var sim := _sim()
	for i in 5:
		_place(sim, RIFLE)
	assert_int(sim.call_wave()).is_equal(R.OK)
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	sim.state.gold = 10000
	sim.drain_events()
	var log_size := sim.state.command_log.size()
	_bot().call("_act", sim, "mundane", 5, {})
	assert_int(sim.state.towers.size()).is_equal(5)
	assert_array(_levels(sim)).is_equal([0, 0, 0, 0, 0])
	assert_int(sim.state.gold).is_equal(10000)
	assert_int(sim.state.command_log.size()).is_equal(log_size)


func test_upgrades_off_keeps_building_and_never_upgrades() -> void:
	var sim := _sim(_mundane_builds(7))
	sim.state.gold += _oil_topup()
	_bot(false).call("_act", sim, "mundane", 0, {})
	assert_array(_levels(sim)).is_equal([0, 0, 0, 0, 0, 0, 0])


func test_run_lines_carry_upgrade_keys_only_with_upgrades_on() -> void:
	# LT-30: --upgrades=0 --lighthouse=0 --flare=0 still prints the LT-30 keys, all zero.
	var off: Dictionary = _bot(false, false, false).call("_play", "mundane", 1000)
	assert_array(off.keys()).is_equal(BASELINE_KEYS + LT23_KEYS + LT27_KEYS + LT30_KEYS)
	assert_array([off["lighthouse_level"], off["flares"], off["oil_bought"], off["oil_gold"]]) \
		.is_equal([0, 0, 0, 0])
	var on: Dictionary = _bot(true).call("_play", "mundane", 1000)
	assert_array(on.keys()).is_equal(BASELINE_KEYS + LT23_KEYS + LT27_KEYS + LT30_KEYS
		+ ["upgrades", "upgrade_gold"])
	var oil := real_config().economy.oil
	assert_int(on["oil_gold"]).is_equal(on["oil_bought"] * oil.price)
	assert_int(on["flares"] * real_config().economy.flare.cost_oil) \
		.is_less_equal(oil.start + on["oil_bought"])
	assert_int(on["lit_shots"]).is_between(0, on["shots"])
	assert_int(on["lighthouse_level"]).is_between(0, real_config().economy.beam.levels.size() - 1)
	# LT-29: L2s and the mundane L3 picks (branch "a" for both), never another branch.
	assert_dict(on["upgrades"]).is_not_empty()
	var allowed := [RIFLE + "_L2", HARP + "_L2", RIFLE + "_a", HARP + "_a"]
	for k: String in on["upgrades"]:
		assert_bool(k in allowed).override_failure_message(k).is_true()
	assert_int(on["upgrade_gold"]).is_greater_equal(0)
	# Same strategy and seed twice: the same RUN line.
	var again: Dictionary = _bot(true).call("_play", "mundane", 1000)
	assert_str(JSON.stringify(again)).is_equal(JSON.stringify(on))


# --- LT-23 pin 20: cap guard, true occult, mixed, RUN metrics -------------------------------

func _cap_allows(strat: String, sim: Simulation, delta: float) -> bool:
	return _bot().call("_cap_allows", sim, strat, delta)


func test_cap_allows_at_and_above_the_strategy_floor_only() -> void:
	var cfg := _fresh()
	var sim := _sim(0, cfg)
	var cap := sim.state.sanity_cap
	assert_bool(_cap_allows("occult", sim, cap - 30.0)).is_true()
	assert_bool(_cap_allows("occult", sim, cap - 29.5)).is_false()
	assert_bool(_cap_allows("mixed", sim, cap - 60.0)).is_true()
	assert_bool(_cap_allows("mixed", sim, cap - 59.5)).is_false()
	for strat: String in ["mundane", "madness"]:
		assert_bool(_cap_allows(strat, sim, cap)).override_failure_message(strat).is_true()
	# A delta <= 0 (a lower reserve) always passes.
	assert_bool(_cap_allows("mixed", sim, 0.0)).is_true()
	assert_bool(_cap_allows("mixed", sim, -5.0)).is_true()


## A bot whose `_cfg` is `cfg` (edited reserves).
func _bot_on(cfg: GameConfig) -> Object:
	var b := _bot()
	b.set("_cfg", cfg)
	return b


func test_occult_order_falls_back_to_riflemen_below_three_then_saves() -> void:
	var cfg := _fresh()
	var sim := _sim(0, cfg)
	var b := _bot_on(cfg)
	assert_int(b.get_script().get_script_constant_map()["OCCULT_MAX_RIFLEMEN"]).is_equal(3)
	assert_str(b.call("_order", "occult", 0, sim, {})).is_equal(RIFLE)
	# Item 1 is an Elder Sign: allowed while the cap stays >= 30.
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap - 30.0
	assert_str(b.call("_order", "occult", 1, sim, {RIFLE: 1})).is_equal(SIGN)
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap - 29.5
	assert_str(b.call("_order", "occult", 1, sim, {RIFLE: 1})).is_equal(RIFLE)
	assert_str(b.call("_order", "occult", 1, sim, {RIFLE: 2})).is_equal(RIFLE)
	assert_str(b.call("_order", "occult", 1, sim, {RIFLE: 3})).is_equal("")


func test_blocked_occult_bot_out_of_riflemen_upgrades_below_build_first() -> void:
	var cfg := _fresh()
	var sim := _sim(0, cfg)
	var necro := _place(sim, NECRO)
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap  # blocks every Sign
	var up := cfg.towers[NECRO].levels[1].upgrade_cost
	sim.state.gold = up + _oil_topup()
	var log_size := sim.state.command_log.size()
	var idx: int = _bot_on(cfg).call("_act", sim, "occult", 1, {RIFLE: 3})
	assert_int(idx).is_equal(1)
	assert_int(sim.state.towers.size()).is_equal(1)
	assert_int(necro.level).is_equal(1)
	# LT-30: the oil top-up first, then one upgrade (all the gold left), then the round's
	# call_wave (its bonus is the only gold).
	var cmds := sim.state.command_log.slice(log_size).map(func(c: Array) -> String: return c[1])
	assert_array(cmds).is_equal(["buy_oil", "buy_oil", "upgrade", "call_wave"])


func test_blocked_occult_bot_with_nothing_to_upgrade_saves_its_gold() -> void:
	var cfg := _fresh()
	var sim := _sim(10000, cfg)
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap
	var log_size := sim.state.command_log.size()
	var idx: int = _bot_on(cfg).call("_act", sim, "occult", 1, {RIFLE: 3})
	assert_int(idx).is_equal(1)
	assert_int(sim.state.towers.size()).is_equal(0)
	# Only the oil top-up (LT-30) and the call_wave of the round: no build, no upgrade.
	var cmds := sim.state.command_log.slice(log_size).map(func(c: Array) -> String: return c[1])
	assert_array(cmds).is_equal(["buy_oil", "buy_oil", "call_wave"])


func test_mixed_skips_a_blocked_occult_item_and_builds_the_next() -> void:
	var cfg := _fresh()
	var order: Array = _bot().get_script().get_script_constant_map()["MIXED_ORDER"]
	assert_str(order[2]).is_equal(SIGN)
	assert_str(order[3]).is_equal(RIFLE)
	var sim := _sim(cfg.towers[RIFLE].cost + _oil_topup(), cfg)
	# Cap 100 - 41 = 59: under the mixed floor 60 (the occult floor 30 would allow it).
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap - 59.0
	var built := {}
	var idx: int = _bot_on(cfg).call("_act", sim, "mixed", 2, built)
	assert_int(idx).is_equal(4)
	assert_int(sim.state.towers.size()).is_equal(1)
	assert_str(sim.state.towers[0].def.id).is_equal(RIFLE)
	assert_dict(built).is_equal({RIFLE: 1})
	# Not blocked: the Sign is built.
	cfg.towers[SIGN].levels[0].sanity_reserve = sim.state.sanity_cap - 60.0
	sim = _sim(cfg.towers[SIGN].cost + _oil_topup(), cfg)
	idx = _bot_on(cfg).call("_act", sim, "mixed", 2, {})
	assert_int(idx).is_equal(3)
	assert_str(sim.state.towers[0].def.id).is_equal(SIGN)


## RUN metrics hold together: no sells, so the cap only falls and the final cap is max minus
## the peak reserve; free_reserve (reserve not taken from current sanity) lies in 0..peak and
## is below the peak, since the first occult build happens at full sanity.
func test_occult_run_line_metrics_are_consistent() -> void:
	var cfg := real_config()
	var run_line: Dictionary = _bot(true).call("_play", "occult", 1000)
	var top := cfg.sanity.max_sanity
	var peak: float = run_line["reserve_peak"]
	assert_float(peak).is_greater(0.0)
	assert_float(run_line["final_cap"]).is_equal_approx(maxf(0.0, top - peak), 0.1)
	var free: float = run_line["free_reserve"]
	assert_float(free).is_greater_equal(0.0)
	assert_float(free).is_less(peak)
	var caps: Array = run_line["cap_per_wave"]
	assert_int(caps.size()).is_equal(run_line["waves_survived"])
	for i in range(1, caps.size()):
		assert_float(caps[i]).is_less_equal(caps[i - 1])
	assert_float(run_line["min_sanity"]).is_less_equal(run_line["final_sanity"])
	assert_bool(run_line["madness_tick"] >= 0).is_equal(run_line["seconds"]["madness"] > 0.0)
	var lost := 0
	for h: int in run_line["hp_lost_per_wave"]:
		lost += h
	assert_int(lost).is_equal(cfg.economy.lighthouse_hp - run_line["lighthouse_hp"])
	var standing := 0
	for k: String in run_line["towers_final"]:
		standing += run_line["towers_final"][k]
	var built := 0
	for k: String in run_line["towers"]:
		built += run_line["towers"][k]
	assert_int(standing).is_equal(built)  # no sells
	# The occult bot keeps the cap at or above its floor.
	assert_float(run_line["final_cap"]).is_greater_equal(30.0)
	assert_int(run_line["towers"].get(RIFLE, 0)).is_less_equal(3)


## LT-31 decision 12: bots never switch target priority, so their towers keep "first" and
## their runs are those of before LT-31.
func test_bots_never_set_target_priority() -> void:
	var src := FileAccess.get_file_as_string(BOT_PATH)
	assert_bool(src.contains("set_target_priority")).is_false()
	var sim := _sim(_mundane_builds(7) + 1000)
	_bot().call("_act", sim, "mundane", 0, {})
	assert_int(sim.state.towers.size()).is_greater(0)
	for t in sim.state.towers:
		assert_str(t.target_priority).is_equal(SimTower.DEFAULT_TARGET_PRIORITY)
	assert_bool(sim.state.command_log.any(
		func(c: Array) -> bool: return c[1] == "set_target_priority")).is_false()


# --- LT-30: the lighthouse, lamp oil and the flare -----------------------------------------

func test_day_tops_the_oil_up_to_the_target_before_building() -> void:
	var target: int = _bot().get_script().get_script_constant_map()["BOT_OIL_TARGET"]
	assert_int(target).is_equal(4)
	var sim := _sim(1000)
	var start := sim.state.oil
	_bot().call("_act", sim, "mundane", 0, {})
	assert_int(sim.state.oil).is_equal(target)
	var names: Array = sim.state.command_log.map(func(c: Array) -> String: return c[1])
	var n := target - start
	var buys := []
	for i in n:
		buys.append("buy_oil")
	assert_int(n).is_greater(0)
	assert_array(names.slice(0, n)).is_equal(buys)
	assert_str(names[n]).is_equal("build")
	# Too poor for the whole top-up: buys what it can, then stops.
	var poor := _sim(real_config().economy.oil.price + 5)
	_bot().call("_act", poor, "mundane", 0, {})
	assert_int(poor.state.oil).is_equal(start + 1)


func test_flare_off_never_buys_oil_nor_fires() -> void:
	var day := _sim(1000)
	_bot(true, true, false).call("_act", day, "mundane", 0, {})
	assert_int(day.state.oil).is_equal(real_config().economy.oil.start)
	var night := _night_with_lit(3)
	_bot(true, true, false).call("_act", night, "mundane", 5, {})
	assert_int(night.state.flare_cooldown_ticks).is_equal(0)
	for c: Array in day.state.command_log + night.state.command_log:
		assert_bool(c[1] in ["buy_oil", "fire_flare"]).override_failure_message(str(c)).is_false()


## A WAVE sim with `lit` live enemies flagged lit (and one unlit), oil for a flare.
func _night_with_lit(lit: int) -> Simulation:
	var sim := _sim()
	assert_int(sim.call_wave()).is_equal(R.OK)
	for e in sim.state.enemies:
		e.lit = false
	for i in lit + 1:
		var e := sim.enemy_by_id(sim.spawn_enemy("cultist", false))
		e.lit = i < lit
	sim.state.oil = 4
	sim.drain_events()
	return sim


func test_night_fires_the_flare_at_three_lit_enemies() -> void:
	var min_lit: int = _bot().get_script().get_script_constant_map()["FLARE_MIN_LIT"]
	assert_int(min_lit).is_equal(3)
	var sim := _night_with_lit(min_lit)
	_bot().call("_act", sim, "mundane", 5, {})
	assert_array(sim.state.command_log.back()).is_equal([sim.state.tick, "fire_flare"])
	assert_int(sim.state.oil).is_equal(4 - real_config().economy.flare.cost_oil)
	var few := _night_with_lit(min_lit - 1)
	var log_size := few.state.command_log.size()
	_bot().call("_act", few, "mundane", 5, {})
	assert_int(few.state.command_log.size()).is_equal(log_size)
	assert_int(few.state.oil).is_equal(4)


## Five L3 Marksmen: mundane has no tower upgrade left (LT-29: L2 riflemen now buy the
## Marksman, cheaper than a lighthouse level).
func _five_l3_rifles(gold: int) -> Simulation:
	var sim := _sim(gold)
	for i in 5:
		_place(sim, RIFLE, 2, "a")
	sim.state.oil = 4  # no oil top-up in the way
	return sim


func test_bot_buys_lighthouse_levels_when_no_tower_upgrade_is_cheaper() -> void:
	var levels := real_config().economy.beam.levels
	var both := levels[1].upgrade_cost + levels[2].upgrade_cost
	var sim := _five_l3_rifles(both)
	_bot().call("_act", sim, "mundane", 5, {})
	assert_int(sim.state.lighthouse_level).is_equal(2)
	var names: Array = sim.state.command_log.map(func(c: Array) -> String: return c[1])
	assert_int(names.count("upgrade_lighthouse")).is_equal(2)
	# --lighthouse=0 and --upgrades=0 never buy it.
	for flags: Array in [[true, false], [false, true]]:
		var off := _five_l3_rifles(both)
		_bot(flags[0], flags[1]).call("_act", off, "mundane", 5, {})
		assert_int(off.state.lighthouse_level).override_failure_message(str(flags)).is_equal(0)
		assert_bool(off.state.command_log.any(func(c: Array) -> bool:
			return c[1] == "upgrade_lighthouse")).is_false()


func test_lighthouse_waits_for_cheaper_tower_upgrades() -> void:
	var cfg := _fresh()
	var lh_cost: int = cfg.economy.beam.levels[1].upgrade_cost
	var sim := _sim(0, cfg)
	for i in 5:
		_place(sim, RIFLE)
	var b := _bot_on(cfg)
	cfg.towers[RIFLE].levels[1].upgrade_cost = lh_cost - 1
	assert_bool(b.call("_lighthouse_next", sim, "mundane")).is_false()
	cfg.towers[RIFLE].levels[1].upgrade_cost = lh_cost  # equal: the lighthouse first
	assert_bool(b.call("_lighthouse_next", sim, "mundane")).is_true()
	sim.state.lighthouse_level = cfg.economy.beam.levels.size() - 1
	assert_bool(b.call("_lighthouse_next", sim, "mundane")).is_false()  # at the top


# --- LT-30 S10: a refused lighthouse buy falls through to the day's builds -----------------

## A sim that counts upgrade_lighthouse() calls (refused ones included). Past
## RETRY_GUARD calls it lifts the lighthouse to its top level, so _lighthouse_next turns
## false and a bot retrying a refused buy in one day ends instead of hanging the suite.
class CountingSim extends Simulation:
	const RETRY_GUARD := 20
	var lighthouse_calls := 0

	func _init(p_config: GameConfig, run_seed: int) -> void:
		super(p_config, run_seed)

	func upgrade_lighthouse() -> Simulation.CommandResult:
		lighthouse_calls += 1
		if lighthouse_calls > RETRY_GUARD:
			state.lighthouse_level = config.economy.beam.levels.size() - 1
		return super()


## _five_l3_rifles on a CountingSim: no tower upgrade left, so the lighthouse is next.
func _counting_five_l3(gold: int) -> CountingSim:
	var cfg := real_config()
	var sim := CountingSim.new(cfg, 1000)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	sim.state.gold = gold
	sim.drain_events()
	for i in 5:
		_place(sim, RIFLE, 2, "a")
	sim.state.oil = 4  # no oil top-up in the way
	assert_bool(_bot().call("_lighthouse_next", sim, "mundane")).is_true()
	return sim


func test_a_refused_lighthouse_buy_falls_through_to_the_days_build() -> void:
	var lh_cost: int = real_config().economy.beam.levels[1].upgrade_cost
	var id: String = _bot().call("_order", "mundane", 5, null, {})
	var build_cost: int = real_config().towers[id].cost
	assert_int(build_cost).is_less(lh_cost)  # affords the build, not the lighthouse
	var sim := _five_l3_rifles(build_cost)
	var idx: int = _bot().call("_act", sim, "mundane", 5, {})
	assert_int(idx).is_equal(6)
	assert_int(sim.state.towers.size()).is_equal(6)
	assert_str(sim.state.towers[5].def.id).is_equal(id)
	assert_int(sim.state.lighthouse_level).is_equal(0)
	assert_int(sim.state.gold).is_equal(0)


func test_a_refused_lighthouse_buy_is_not_retried_the_same_day() -> void:
	var sim := _counting_five_l3(real_config().economy.beam.levels[1].upgrade_cost - 1)
	_bot().call("_act", sim, "mundane", 5, {})
	assert_int(sim.lighthouse_calls).is_equal(1)
	assert_int(sim.state.lighthouse_level).is_equal(0)


func test_the_lighthouse_is_tried_again_the_next_day() -> void:
	var lh_cost: int = real_config().economy.beam.levels[1].upgrade_cost
	var sim := _counting_five_l3(0)  # day 1: refused, nothing affordable, the wave is called
	var b := _bot()
	b.call("_act", sim, "mundane", 5, {})
	assert_int(sim.lighthouse_calls).is_equal(1)
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	var steps := 0
	while sim.state.phase != SimState.Phase.BUILD and steps < 100000:
		sim.step()
		steps += 1
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)
	sim.state.gold = lh_cost  # day 2: the same bot affords the level
	sim.state.oil = 4
	sim.drain_events()
	b.call("_act", sim, "mundane", 5, {})
	assert_int(sim.state.lighthouse_level).is_equal(1)
	# Day 2: level 1 bought, level 2 refused once (too poor), not retried.
	assert_int(sim.lighthouse_calls).is_equal(3)
