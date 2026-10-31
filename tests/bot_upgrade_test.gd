class_name BotUpgradeTest
extends SimTestBase
## LT-24 §5 bot "wide then deep" (Decision 6): build BUILD_FIRST towers first, then the
## cheapest upgrade (ties -> lower id), L3 from BRANCH_PICK, pending branches skipped, the
## occult sanity guard, no upgrade during a wave, and `--upgrades=0`.
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

var _bot_script: GDScript
var _bots: Array[Object] = []


func after_test() -> void:
	for b in _bots:
		if is_instance_valid(b):
			b.free()
	_bots.clear()


## A bot harness instance whose constructor does nothing; `_cfg` is the real config.
func _bot(upgrades := true) -> Object:
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
	return b


## Real-config sim with a WaveDirector, stepped into the first build phase.
func _sim(gold := 0) -> Simulation:
	var sim := Simulation.new(real_config(), 1000)
	sim.set_spawner(WaveDirector.new(real_config().waves))
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

func test_occult_buys_the_pure_branches_and_skips_the_pending_marksman() -> void:
	var sim := _sim()
	var rifle := _place(sim, RIFLE, 1)
	var sign := _place(sim, SIGN, 1)
	var necro := _place(sim, NECRO, 1)
	var branches := real_config().towers[SIGN].branches
	assert_int(branches["a"].upgrade_cost).is_less(real_config().towers[NECRO].branches["a"].upgrade_cost)
	assert_array(_next(sim, "occult")).is_equal([sign.id, "a"])
	# Without the sign the next pick is the Pure Rite, never the (pending) Marksman.
	sim.state.towers.erase(sign)
	assert_array(_next(sim, "occult")).is_equal([necro.id, "a"])
	sim.state.towers.erase(necro)
	assert_bool(real_config().towers[RIFLE].branches["a"].has_pending()).is_true()
	assert_array(_next(sim, "occult")).is_empty()
	assert_int(rifle.level).is_equal(1)


func test_madness_buys_the_corrupted_rite_and_skips_the_pending_seal() -> void:
	var sim := _sim()
	_place(sim, SIGN, 1)
	var necro := _place(sim, NECRO, 1)
	assert_bool(real_config().towers[SIGN].branches["b"].has_pending()).is_true()
	assert_array(_next(sim, "madness")).is_equal([necro.id, "b"])


func test_mundane_stops_at_l2_while_both_picks_are_pending() -> void:
	var sim := _sim()
	_place(sim, RIFLE, 1)
	_place(sim, HARP, 1)
	assert_array(_next(sim, "mundane")).is_empty()


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


func test_occult_guard_skips_an_upgrade_leaving_sanity_below_25() -> void:
	var sim := _sim()
	var sign := _place(sim, SIGN)
	var rifle := _place(sim, RIFLE, 1)  # pending Marksman: nothing else to buy
	var cost := real_config().towers[SIGN].levels[1].upgrade_sanity_cost
	var guard: float = _bot().get_script().get_script_constant_map()["SANITY_GUARD"]
	assert_float(guard).is_equal(25.0)
	_set_sanity(sim, guard + cost)  # leaves exactly 25: allowed
	assert_array(_next(sim, "occult")).is_equal([sign.id, ""])
	_set_sanity(sim, guard + cost - 0.5)  # leaves 24.5: skipped
	assert_array(_next(sim, "occult")).is_empty()
	# The guard skips only that upgrade: another candidate is still bought.
	var necro := _place(sim, NECRO)
	assert_array(_next(sim, "occult")).is_equal([necro.id, ""])
	assert_int(rifle.level).is_equal(1)


func test_madness_has_no_sanity_guard() -> void:
	var sim := _sim()
	var sign := _place(sim, SIGN)
	_set_sanity(sim, 1.0)
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
	var sim := _sim(_mundane_builds(5) + up)
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
	_bot(false).call("_act", sim, "mundane", 0, {})
	assert_array(_levels(sim)).is_equal([0, 0, 0, 0, 0, 0, 0])


func test_run_lines_carry_upgrade_keys_only_with_upgrades_on() -> void:
	var off: Dictionary = _bot(false).call("_play", "mundane", 1000)
	assert_array(off.keys()).is_equal(BASELINE_KEYS)
	var on: Dictionary = _bot(true).call("_play", "mundane", 1000)
	assert_array(on.keys()).is_equal(BASELINE_KEYS + ["upgrades", "upgrade_gold"])
	# Mundane today: L2s only (both of its L3 picks are pending).
	assert_dict(on["upgrades"]).is_not_empty()
	for k: String in on["upgrades"]:
		assert_bool(k.ends_with("_L2")).override_failure_message(k).is_true()
	assert_int(on["upgrade_gold"]).is_greater_equal(0)
	# Same strategy and seed twice: the same RUN line.
	var again: Dictionary = _bot(true).call("_play", "mundane", 1000)
	assert_str(JSON.stringify(again)).is_equal(JSON.stringify(on))
