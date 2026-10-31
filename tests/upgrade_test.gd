class_name UpgradeTest
extends WaveTestBase
## LT-24 §2 upgrade command (sim): L1 -> L2 -> L3 branch, the refusal order, build phase
## only (Decision 3), events, command log + replay, sanity cost, the refund over everything
## spent (Decision 4), cooldown kept, branch stats through the existing combat code.
## Balance numbers are read from config.

const T := SimEvent.Type
const S := SimState.SanityState
const RIFLE := "rifleman"
const HARP := "harpooner"
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"


# --- helpers ---------------------------------------------------------------------------

func _rich(sim: Simulation) -> Simulation:
	sim.state.gold = 10000
	sim.drain_events()
	return sim


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _up(sim: Simulation, t: SimTower, branch := "") -> void:
	var r := sim.upgrade_tower(t.id, branch)
	assert_int(r).override_failure_message("upgrade %s %s -> %d" % [t.def.id, branch, r]) \
		.is_equal(R.OK)


## Snapshot of everything a refused upgrade must leave alone.
func _snap(sim: Simulation, t: SimTower) -> Array:
	return [sim.state.gold, sim.state.sanity, t.level, t.branch, t.spent,
		sim.state.command_log.duplicate(true), t.cooldown_ticks]


func _assert_refused(sim: Simulation, t: SimTower, branch: String, want: R) -> void:
	var before := _snap(sim, t)
	sim.drain_events()
	var id := t.id
	assert_int(sim.can_upgrade(id, branch)).override_failure_message(
		"can_upgrade(%s) at L%d" % [branch, t.level + 1]).is_equal(want)
	assert_int(sim.upgrade_tower(id, branch)).is_equal(want)
	assert_array(_snap(sim, t)).is_equal(before)
	assert_array(sim.drain_events()).is_empty()


## Wave sim (build timer 25 s) in BUILD with a rifleman at TOWER and plenty of gold.
func _build_phase_sim() -> Array:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 25)
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	_rich(sim)
	var t := build(sim, RIFLE)
	sim.drain_events()
	return [sim, t]


## The same, with the first wave called and running.
func _wave_sim() -> Array:
	var pair := _build_phase_sim()
	var sim: Simulation = pair[0]
	assert_int(sim.call_wave()).is_equal(R.OK)
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	sim.drain_events()
	return pair


# --- 1, 2: L1 -> L2 -> L3 ----------------------------------------------------------------

func test_l1_to_l2_pays_the_level_upgrade_cost_and_adds_it_to_spent() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	var def: TowerDef = sim.config.towers[RIFLE]
	var cost := def.levels[1].upgrade_cost
	assert_int(cost).is_greater(0)
	var gold := sim.state.gold
	var id := t.id
	var cell := t.cell
	var built_at := t.build_tick
	assert_array(sim.upgrade_branches(t)).is_equal(PackedStringArray([""]))
	assert_object(sim.upgrade_target(t, "")).is_same(def.levels[1])
	_up(sim, t)
	assert_int(t.level).is_equal(1)
	assert_str(t.branch).is_equal("")
	assert_int(sim.state.gold).is_equal(gold - cost)
	assert_int(t.spent).is_equal(def.cost + cost)
	assert_object(t.stats()).is_same(def.levels[1])
	assert_int(t.id).is_equal(id)
	assert_object(sim.tower_by_id(id)).is_same(t)
	assert_vector(t.cell).is_equal(cell)
	assert_int(t.build_tick).is_equal(built_at)


func test_l2_to_l3_takes_the_chosen_branch_and_its_stats() -> void:
	for branch: String in ["a", "b"]:
		var sim := _rich(tsim())
		var t := build(sim, RIFLE)
		var def: TowerDef = sim.config.towers[RIFLE]
		_up(sim, t)
		assert_array(sim.upgrade_branches(t)).is_equal(TowerDef.BRANCH_IDS)
		var gold := sim.state.gold
		var cost := def.branches[branch].upgrade_cost
		_up(sim, t, branch)
		assert_int(t.level).is_equal(2)
		assert_str(t.branch).is_equal(branch)
		assert_object(t.stats()).is_same(def.branches[branch])
		assert_int(sim.state.gold).is_equal(gold - cost)
		assert_int(t.spent).is_equal(def.cost + def.levels[1].upgrade_cost + cost)
		assert_array(sim.upgrade_branches(t)).is_empty()
		assert_object(sim.upgrade_target(t, "")).is_null()
		assert_object(sim.upgrade_target(t, "a")).is_null()


# --- 3: refusals in order ---------------------------------------------------------------

func test_outcome_reached_comes_first_and_changes_nothing() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	sim.state.outcome = SimState.Outcome.LOST
	_assert_refused(sim, t, "", R.OUTCOME_REACHED)
	_assert_refused(sim, t, "c", R.OUTCOME_REACHED)
	assert_int(sim.upgrade_tower(9999)).is_equal(R.OUTCOME_REACHED)


func test_unknown_or_sold_tower_is_no_such_tower() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	var log_size := sim.state.command_log.size()
	sim.drain_events()
	assert_int(sim.can_upgrade(9999)).is_equal(R.NO_SUCH_TOWER)
	assert_int(sim.upgrade_tower(9999, "c")).is_equal(R.NO_SUCH_TOWER)
	assert_int(sim.sell_tower(t.id)).is_equal(R.OK)
	sim.drain_events()
	var gold := sim.state.gold
	assert_int(sim.upgrade_tower(t.id)).is_equal(R.NO_SUCH_TOWER)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.state.command_log.size()).is_equal(log_size + 1)  # the sell only
	assert_array(sim.drain_events()).is_empty()


func test_max_level_beats_branch_phase_and_gold_checks() -> void:
	var pair := _build_phase_sim()
	var sim: Simulation = pair[0]
	var t: SimTower = pair[1]
	_up(sim, t)
	_up(sim, t, "a")
	assert_int(sim.call_wave()).is_equal(R.OK)
	sim.step()
	sim.state.gold = 0
	for branch: String in ["", "a", "b", "c"]:
		_assert_refused(sim, t, branch, R.MAX_LEVEL)


func test_need_branch_and_bad_branch_beat_phase_and_gold() -> void:
	var pair := _wave_sim()
	var sim: Simulation = pair[0]
	var t: SimTower = pair[1]
	# L1: any non-empty branch is bad (also "a"), even mid-wave without gold.
	sim.state.gold = 0
	_assert_refused(sim, t, "a", R.BAD_BRANCH)
	_assert_refused(sim, t, "c", R.BAD_BRANCH)
	# L2 (forced: upgrades are refused mid-wave): "" needs a branch, "c" is bad.
	t.level = 1
	t.spent += sim.config.towers[RIFLE].levels[1].upgrade_cost
	_assert_refused(sim, t, "", R.NEED_BRANCH)
	_assert_refused(sim, t, "c", R.BAD_BRANCH)
	_assert_refused(sim, t, "A", R.BAD_BRANCH)


func test_not_build_phase_beats_not_enough_gold() -> void:
	var pair := _wave_sim()
	var sim: Simulation = pair[0]
	var t: SimTower = pair[1]
	sim.state.gold = 0
	_assert_refused(sim, t, "", R.NOT_BUILD_PHASE)


func test_not_enough_gold_below_the_cost_and_ok_at_exactly_the_cost() -> void:
	var sim := tsim()
	var t := build(sim, RIFLE)
	var cost := sim.config.towers[RIFLE].levels[1].upgrade_cost
	sim.state.gold = cost - 1
	_assert_refused(sim, t, "", R.NOT_ENOUGH_GOLD)
	sim.state.gold = cost
	assert_int(sim.can_upgrade(t.id)).is_equal(R.OK)
	_up(sim, t)
	assert_int(sim.state.gold).is_equal(0)


func test_can_upgrade_changes_nothing_when_ok() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	sim.drain_events()
	var before := _snap(sim, t)
	assert_int(sim.can_upgrade(t.id)).is_equal(R.OK)
	assert_array(_snap(sim, t)).is_equal(before)
	assert_array(sim.drain_events()).is_empty()


# --- 4: build phase only ----------------------------------------------------------------

func test_upgrade_is_refused_during_a_wave_even_with_gold() -> void:
	var pair := _wave_sim()
	var sim: Simulation = pair[0]
	var t: SimTower = pair[1]
	assert_int(sim.state.gold).is_greater(sim.config.towers[RIFLE].levels[1].upgrade_cost)
	_assert_refused(sim, t, "", R.NOT_BUILD_PHASE)


func test_build_and_sell_still_work_during_a_wave() -> void:
	var pair := _wave_sim()
	var sim: Simulation = pair[0]
	var t: SimTower = pair[1]
	assert_int(sim.build_tower(RIFLE, Vector2i(3, 1))).is_equal(R.OK)
	assert_int(sim.sell_tower(t.id)).is_equal(R.OK)


func test_upgrade_is_allowed_in_build_and_in_phase_none() -> void:
	var pair := _build_phase_sim()
	var sim: Simulation = pair[0]
	_up(sim, pair[1])
	var bare := _rich(tsim())
	assert_int(bare.state.phase).is_equal(SimState.Phase.NONE)
	var t := build(bare, RIFLE)
	_up(bare, t)


func test_upgrade_is_allowed_again_in_the_next_build_phase() -> void:
	var pair := _wave_sim()
	var sim: Simulation = pair[0]
	var t: SimTower = pair[1]
	_assert_refused(sim, t, "", R.NOT_BUILD_PHASE)
	for i in 3000:
		if sim.state.phase == SimState.Phase.BUILD:
			break
		kill_real(sim)
		sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	_up(sim, t)


# --- 5: events ---------------------------------------------------------------------------

func test_upgrade_emits_tower_upgraded_then_gold_changed() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	sim.drain_events()
	var gold := sim.state.gold
	_up(sim, t)
	var ev := sim.drain_events()
	var cost := sim.config.towers[RIFLE].levels[1].upgrade_cost
	assert_int(ev.size()).is_equal(2)
	assert_int(ev[0].type).is_equal(T.TOWER_UPGRADED)
	assert_int(ev[0].id).is_equal(t.id)
	assert_dict(ev[0].data).is_equal({"def": RIFLE, "cell": t.cell, "level": 1, "branch": "",
		"cost": cost})
	assert_int(ev[1].type).is_equal(T.GOLD_CHANGED)
	assert_str(ev[1].data["reason"]).is_equal("upgrade")
	assert_int(ev[1].data["delta"]).is_equal(-cost)
	assert_int(ev[1].data["gold"]).is_equal(gold - cost)
	_up(sim, t, "b")
	ev = sim.drain_events()
	assert_int(ev[0].type).is_equal(T.TOWER_UPGRADED)
	assert_int(ev[0].data["level"]).is_equal(2)
	assert_str(ev[0].data["branch"]).is_equal("b")
	assert_int(ev[0].data["cost"]).is_equal(sim.config.towers[RIFLE].branches["b"].upgrade_cost)


func test_elder_sign_upgrade_also_pays_sanity_after_the_gold() -> void:
	var sim := _rich(tsim())
	var t := build(sim, SIGN)
	sim.drain_events()
	var lvl := sim.config.towers[SIGN].levels[1]
	assert_float(lvl.upgrade_sanity_cost).is_greater(0.0)
	var sanity := sim.state.sanity
	_up(sim, t)
	var ev := sim.drain_events()
	assert_int(ev.size()).is_equal(3)
	assert_array([ev[0].type, ev[1].type, ev[2].type]) \
		.is_equal([T.TOWER_UPGRADED, T.GOLD_CHANGED, T.SANITY_CHANGED])
	assert_str(ev[2].data["reason"]).is_equal("upgrade")
	assert_int(ev[2].id).is_equal(t.id)
	assert_float(ev[2].data["delta"]).is_equal_approx(-lvl.upgrade_sanity_cost, 0.0001)
	assert_float(sim.state.sanity).is_equal_approx(sanity - lvl.upgrade_sanity_cost, 0.0001)


# --- 6: command log + replay -------------------------------------------------------------

func test_upgrade_is_logged_with_tick_id_and_branch() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	run(sim, 4)
	_up(sim, t)
	run(sim, 3)
	_up(sim, t, "a")
	var log := sim.state.command_log
	assert_array(log[log.size() - 2]).is_equal([4, "upgrade", t.id, ""])
	assert_array(log[log.size() - 1]).is_equal([7, "upgrade", t.id, "a"])


## Plays `commands` ([tick, name, ...]) on a fresh wave sim with plenty of gold; returns
## [event strings + final state line, command_log]. "upgrade_at" resolves the tower on a
## cell (first run only); the log then holds the real "upgrade" entry the replay applies.
func _play(run_seed: int, commands: Array, ticks: int) -> Array:
	var sim := wsim([[group("deep_one", 2, 0.5), group("cultist", 2, 0.5, 0.3)],
		[group("deep_one", 1)]], 2, -1, run_seed)
	sim.state.gold = 10000
	var out: Array[String] = []
	for tk in ticks:
		for c: Array in commands:
			if int(c[0]) == sim.state.tick:
				_apply(sim, c)
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("tick=%d gold=%d hp=%d phase=%d wave=%d" % [sim.state.tick, sim.state.gold,
		sim.state.lighthouse_hp, sim.state.phase, sim.state.wave_index])
	return [out, sim.state.command_log.duplicate(true)]


func _apply(sim: Simulation, c: Array) -> void:
	match c[1]:
		"build": sim.build_tower(c[2], c[3])
		"sell": sim.sell_tower(c[2])
		"call_wave": sim.call_wave()
		"upgrade": sim.upgrade_tower(c[2], c[3])
		"upgrade_at": sim.upgrade_tower(sim.state.tower_at[c[2]], c[3])
		"set_target_priority": sim.set_target_priority(c[2], c[3])
		"set_target_priority_at": sim.set_target_priority(sim.state.tower_at[c[2]], c[3])


func test_replaying_a_log_with_upgrades_gives_the_same_run() -> void:
	var cmds := [[5, "build", RIFLE, TOWER], [8, "upgrade_at", TOWER, ""],
		[9, "upgrade_at", TOWER, "b"], [20, "call_wave"]]
	var first := _play(SEED, cmds, 400)
	var log: Array = first[1]
	var ups := log.filter(func(c: Array) -> bool: return c[1] == "upgrade")
	assert_int(ups.size()).is_equal(2)
	assert_array([ups[0][0], ups[0][3], ups[1][0], ups[1][3]]).is_equal([8, "", 9, "b"])
	var replay := _play(SEED, log, 400)
	assert_array(replay[0]).is_equal(first[0])
	assert_array(replay[1]).is_equal(first[1])
	# Control: without the upgrades the run differs.
	var without := _play(SEED, [[5, "build", RIFLE, TOWER], [20, "call_wave"]], 400)
	assert_bool(without[0] == first[0]).is_false()


## LT-31: target priority switches mid-wave (and one across an upgrade) are logged and a
## replay of the log gives the same run; without them the run differs.
func test_replaying_a_log_with_target_priority_switches_gives_the_same_run() -> void:
	var base := [[5, "build", RIFLE, TOWER], [6, "build", HARP, Vector2i(9, 1)],
		[20, "call_wave"]]
	var cmds := base + [[7, "set_target_priority_at", TOWER, "strongest"],
		[8, "upgrade_at", TOWER, ""], [60, "set_target_priority_at", Vector2i(9, 1), "fastest"],
		[90, "set_target_priority_at", TOWER, "fastest"],
		[140, "set_target_priority_at", TOWER, "strongest"]]
	var first := _play(SEED, cmds, 400)
	var log: Array = first[1]
	var stp := log.filter(func(c: Array) -> bool: return c[1] == "set_target_priority")
	assert_array(stp.map(func(c: Array) -> Array: return [c[0], c[3]])).is_equal(
		[[7, "strongest"], [60, "fastest"], [90, "fastest"], [140, "strongest"]])
	var replay := _play(SEED, log, 400)
	assert_array(replay[0]).is_equal(first[0])
	assert_array(replay[1]).is_equal(first[1])
	# Control: the same run without the switches differs in its effects, not only in the
	# TARGET_PRIORITY_SET events the switches emit.
	var without := _play(SEED, base + [[8, "upgrade_at", TOWER, ""]], 400)
	var effects := func(evs: Array) -> Array:
		return evs.filter(func(s: String) -> bool: return not s.begins_with("TARGET_PRIORITY_SET"))
	assert_bool(effects.call(without[0]) == effects.call(first[0])).is_false()


# --- 7: sanity cost and madness ----------------------------------------------------------

func test_upgrade_sanity_cost_clamps_at_zero_and_enters_madness() -> void:
	var sim := _rich(tsim())
	var t := build(sim, SIGN)
	var cost := sim.config.towers[SIGN].levels[1].upgrade_sanity_cost
	_set_sanity(sim, cost - 3.0)
	_up(sim, t)
	assert_int(t.level).is_equal(1)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	var ev := sim.drain_events()
	var ch := of_type(ev, T.SANITY_CHANGED)
	assert_int(ch.size()).is_equal(1)
	assert_float(ch[0].data["delta"]).is_equal_approx(-(cost - 3.0), 0.0001)
	var st := of_type(ev, T.SANITY_STATE_CHANGED)
	assert_int(st.size()).is_equal(1)
	assert_int(st[0].data["new"]).is_equal(S.MADNESS)


func test_upgrade_in_madness_applies_but_moves_no_sanity() -> void:
	var sim := _rich(tsim())
	var t := build(sim, SIGN)
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	var gold := sim.state.gold
	_up(sim, t)
	assert_int(t.level).is_equal(1)
	assert_int(sim.state.gold).is_equal(gold - sim.config.towers[SIGN].levels[1].upgrade_cost)
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_array(of_type(sim.drain_events(), T.SANITY_CHANGED)).is_empty()


# --- 8: refund over everything spent -----------------------------------------------------

func _refund_after(def_id: String, path: Array) -> Array:
	var sim := _rich(tsim())
	var t := build(sim, def_id)
	for b: String in path:
		_up(sim, t, b)
	return [sim, t]


func test_sell_refunds_the_ratio_of_build_plus_upgrades() -> void:
	var cfg := tconfig()
	var ratio := cfg.economy.sell_refund_ratio
	var r: TowerDef = cfg.towers[RIFLE]
	var h: TowerDef = cfg.towers[HARP]
	var s: TowerDef = cfg.towers[SIGN]
	var cases := [
		[RIFLE, ["", "a"], r.cost + r.levels[1].upgrade_cost + r.branches["a"].upgrade_cost],
		[HARP, [""], h.cost + h.levels[1].upgrade_cost],
		[SIGN, ["", "b"], s.cost + s.levels[1].upgrade_cost + s.branches["b"].upgrade_cost],
	]
	for c: Array in cases:
		var pair := _refund_after(c[0], c[1])
		var sim: Simulation = pair[0]
		var t: SimTower = pair[1]
		assert_int(t.spent).is_equal(c[2])
		var want := roundi(c[2] * ratio)
		assert_int(sim.sell_refund(t)).override_failure_message("%s: refund" % c[0]) \
			.is_equal(want)
		var gold := sim.state.gold
		var sanity := sim.state.sanity
		assert_int(sim.sell_tower(t.id)).is_equal(R.OK)
		assert_int(sim.state.gold).is_equal(gold + want)
		assert_float(sim.state.sanity).is_equal(sanity)  # sanity is never refunded


func test_spec_refund_examples_at_today_config() -> void:
	# LT-24 §2: Rifleman L3 170 -> 119, Harpooner L2 125 -> 87.5 -> 88 (at ratio 0.7).
	if not is_equal_approx(tconfig().economy.sell_refund_ratio, 0.7):
		return
	var rifle := _refund_after(RIFLE, ["", "a"])
	assert_int((rifle[0] as Simulation).sell_refund(rifle[1])).is_equal(119)
	var harp := _refund_after(HARP, [""])
	assert_int((harp[0] as Simulation).sell_refund(harp[1])).is_equal(88)


func test_refund_is_rounded_once_on_the_total() -> void:
	var sim := _rich(tsim())
	sim.config.economy.sell_refund_ratio = 0.7
	var def: TowerDef = sim.config.towers[RIFLE]
	def.cost = 5
	def.levels[1].upgrade_cost = 5
	var t := build(sim, RIFLE)
	_up(sim, t)
	# Per part: round(3.5) + round(3.5) = 8; once on the total: round(7.0) = 7.
	assert_int(sim.sell_refund(t)).is_equal(7)


# --- 9: cooldown kept, new stats from the next shot --------------------------------------

func test_upgrade_keeps_the_running_cooldown_and_the_next_shot_uses_the_new_stats() -> void:
	var sim := _rich(tsim())
	var t := build(sim, RIFLE)
	var def: TowerDef = sim.config.towers[RIFLE]
	var l1 := def.levels[0]
	var l2 := def.levels[1]
	var n1 := SimTime.ticks(l1.fire_interval)
	var n2 := SimTime.ticks(l2.fire_interval)
	assert_int(n2).is_not_equal(n1)
	assert_float(l2.damage).is_not_equal(l1.damage)
	var e := put(sim, "cultist", 8.0)
	sim.drain_events()
	var ev := run(sim, 3)  # shot at tick 1, cooldown running
	var cd := t.cooldown_ticks
	assert_int(cd).is_greater(0)
	_up(sim, t)
	assert_int(t.cooldown_ticks).is_equal(cd)
	var hp_before := e.hp
	ev.append_array(run(sim, n1 + n2))
	var ticks := shot_ticks(ev)
	assert_array(ticks.slice(0, 3)).is_equal([1, 1 + n1, 1 + n1 + n2])
	# The first shot after the upgrade deals L2 damage.
	var after: Array[SimEvent] = []
	for s in of_type(ev, T.SHOT):
		if s.tick == 1 + n1:
			after.append(s)
	assert_int(after.size()).is_equal(1)
	assert_float(hp_before - e.hp).is_equal_approx(l2.damage * 2.0, 0.0001)


# --- 10: branch stats through the existing combat code -----------------------------------

func test_pure_ward_aura_reaches_its_branch_range() -> void:
	var sim := _rich(tsim())
	var t := build(sim, SIGN)
	var ward := sim.config.towers[SIGN].branches["a"]
	# Path cell 10 is sqrt(10) ~ 3.16 cells from the tower centre (7.5, 1.5).
	var far := put(sim, "cultist", 10.0)
	assert_float(sim.config.towers[SIGN].levels[1].range_cells).is_less(3.16)
	assert_float(ward.range_cells).is_greater(3.17)
	_up(sim, t)
	sim.step()
	assert_float(far.damage_taken_mult).is_equal(1.0)
	_up(sim, t, "a")
	sim.step()
	assert_float(far.damage_taken_mult).is_greater(1.0)
	assert_float(far.speed_mult).is_less(1.0)


func _necro_l3(branch: String) -> Array:
	var sim := _rich(tsim())
	var t := build(sim, NECRO)
	_up(sim, t)
	_up(sim, t, branch)
	sim.drain_events()
	return [sim, t]


func test_pure_rite_in_madness_is_not_doubled_and_never_astray() -> void:
	var pair := _necro_l3("a")
	var sim: Simulation = pair[0]
	var rite := sim.config.towers[NECRO].branches["a"]
	assert_bool(rite.madness_affected).is_false()
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	var e := put(sim, "cultist", 7.0)
	sim.drain_events()
	var n := 20
	var shots: Array[SimEvent] = []
	for i in n:
		for t in sim.state.towers:
			t.cooldown_ticks = 0  # one cast per tick
		sim.step()
		shots.append_array(of_type(sim.drain_events(), T.SHOT))
	assert_int(shots.size()).is_equal(n)
	for s in shots:
		assert_bool(s.data.has("astray")).is_false()
		assert_int(s.data["target"]).is_equal(e.id)
	var armor: float = sim.config.enemies["cultist"].armor
	assert_float(HUGE_HP - e.hp).is_equal_approx(n * maxf(rite.damage - armor, 0.0), 0.0001)


func test_corrupted_rite_cast_costs_its_branch_sanity_per_cast() -> void:
	var pair := _necro_l3("b")
	var sim: Simulation = pair[0]
	var t: SimTower = pair[1]
	var rite := sim.config.towers[NECRO].branches["b"]
	assert_float(rite.sanity_per_cast).is_not_equal(sim.config.towers[NECRO].levels[1].sanity_per_cast)
	put(sim, "cultist", 7.0)
	sim.drain_events()
	var casts: Array[SimEvent] = []
	for c in of_type(run(sim, 1), T.SANITY_CHANGED):
		if c.data["reason"] == "cast":
			casts.append(c)
	assert_int(casts.size()).is_equal(1)
	assert_int(casts[0].id).is_equal(t.id)
	assert_float(casts[0].data["delta"]).is_equal_approx(-rite.sanity_per_cast, 0.0001)
