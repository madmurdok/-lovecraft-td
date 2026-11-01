class_name BranchEffectsTest
extends TowerTestBase
## LT-29 L3 branch effects in the sim (design note docs/design/LT-29-l3-branch-effects.md
## §1, §2, §5 S4): Marksman crits on their own CRIT stream, Gangsters bursts (round robin
## over the ranked targets), Barbed bleed (one pulse per second through armor, refresh not
## stack), Chain harpoon pull (primary only, <= pull_max_hp, immunity, clamped at the
## path start, flyers along their line), Corrupted Seal armor strip (aura, max not sum,
## then the Elder Sign multiplier). L3 towers are set directly (level 2 + branch); numbers
## are read from config where the rule is generic, pinned where the note fixes them.

const T := SimEvent.Type
const RIFLE := "rifleman"
const HARP := "harpooner"
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"


# --- helpers ---------------------------------------------------------------------------

func _sim(enemy_edits := {}) -> Simulation:
	var sim := tsim(enemy_edits)
	sim.state.gold = 1000000
	return sim


## tsim with the beam on and still (phase NONE shines): the default tower cell is lit.
func _lit_sim(enemy_edits := {}) -> Simulation:
	lit_beam = true
	var sim := tsim(enemy_edits)
	lit_beam = false
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	return sim


## Builds `def_id` on `cell` and sets it to L3 `branch` (no gold, reserve or event).
func _l3(sim: Simulation, def_id: String, branch: String, cell := TOWER) -> SimTower:
	var t := build(sim, def_id, cell)
	t.level = TowerDef.LEVEL_COUNT
	t.branch = branch
	sim.drain_events()
	return t


func _branch(sim: Simulation, def_id: String, branch: String) -> TowerDef.Level:
	return sim.config.towers[def_id].branches[branch]


func _set_crit(sim: Simulation, chance: float) -> void:
	_branch(sim, RIFLE, "a").effects["crit_chance"] = chance


## A sanity value in the middle of Fraying (misses on).
func _fray(sim: Simulation) -> void:
	var th := sim.config.sanity.thresholds
	var v := (float(th["fraying"].min_sanity) + float(th["whispers"].min_sanity)) * 0.5
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.FRAYING)


## Every mundane shot misses in the current state (Lucid at full sanity).
func _always_miss(sim: Simulation) -> void:
	sim.threshold().miss_chance = 1.0


## Steps until `n` SHOT events (re-setting Fraying each tick when `fray`).
func _shots(sim: Simulation, n: int, fray := false) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	var guard := 0
	while out.size() < n and guard < 100000:
		if fray:
			_fray(sim)
		sim.step()
		out.append_array(of_type(sim.drain_events(), T.SHOT))
		guard += 1
	assert_int(out.size()).is_equal(n)
	return out


func _targets(shots: Array[SimEvent]) -> Array:
	return shots.map(func(s: SimEvent) -> int: return s.data["target"])


func _one_shot(sim: Simulation) -> SimEvent:
	var shots := of_type(run(sim, 1), T.SHOT)
	assert_int(shots.size()).is_equal(1)
	return shots[0]


func _crit_state(sim: Simulation) -> int:
	return sim.rng(SimRng.Stream.CRIT).state


func _combat_state(sim: Simulation) -> int:
	return sim.rng(SimRng.Stream.COMBAT).state


# --- §1.1 Marksman crits ----------------------------------------------------------------

func test_crit_doubles_the_hit_and_marks_the_shot() -> void:
	var sim := _sim()
	_l3(sim, RIFLE, "a")
	_set_crit(sim, 1.0)
	var l := _branch(sim, RIFLE, "a")
	var e := put(sim, "cultist", 7.0)
	var shot := _one_shot(sim)
	assert_bool(shot.data.get("crit", false)).is_true()
	assert_float(e.hp).is_equal(HUGE_HP - l.damage * l.effects["crit_multiplier"])
	assert_float(l.damage).is_equal(18.0)  # spec numbers: 18 -> 36
	assert_float(e.hp).is_equal(HUGE_HP - 36.0)


func test_no_crit_at_chance_zero_no_key_and_no_crit_draw() -> void:
	var sim := _sim()
	_l3(sim, RIFLE, "a")
	_set_crit(sim, 0.0)
	var e := put(sim, "cultist", 7.0)
	var before := _crit_state(sim)
	var shot := _one_shot(sim)
	assert_bool(shot.data.has("crit")).is_false()
	assert_float(e.hp).is_equal(HUGE_HP - _branch(sim, RIFLE, "a").damage)
	assert_int(_crit_state(sim)).is_equal(before)


func test_crit_applies_before_armor() -> void:
	var sim := _sim({"cultist": {"armor": 5}})
	_l3(sim, RIFLE, "a")
	_set_crit(sim, 1.0)
	var e := put(sim, "cultist", 7.0)
	_one_shot(sim)
	assert_float(e.hp).is_equal(HUGE_HP - 31.0)  # 18 x 2 - 5, not (18 - 5) x 2 = 26
	var plain := _sim({"cultist": {"armor": 5}})
	_l3(plain, RIFLE, "a")
	_set_crit(plain, 0.0)
	var p := put(plain, "cultist", 7.0)
	_one_shot(plain)
	assert_float(p.hp).is_equal(HUGE_HP - 13.0)


func test_crit_rolls_on_the_crit_stream_not_combat() -> void:
	var sim := _sim()
	_l3(sim, RIFLE, "a")
	_set_crit(sim, 1.0)
	put(sim, "cultist", 7.0)
	var crit0 := _crit_state(sim)
	var combat0 := _combat_state(sim)
	_one_shot(sim)  # Lucid: miss chance 0, so no COMBAT draw
	assert_int(_crit_state(sim)).is_not_equal(crit0)
	assert_int(_combat_state(sim)).is_equal(combat0)


## §1.1: crits never shift the miss sequence: the same seed in Fraying gives the same
## misses (and the same COMBAT state) with crit_chance 0 and 1.
func test_fraying_miss_sequence_is_identical_with_and_without_crits() -> void:
	var runs := []
	for chance: float in [0.0, 1.0]:
		var sim := _sim()
		_fray(sim)
		_l3(sim, RIFLE, "a")
		_set_crit(sim, chance)
		put(sim, "hybrid", 7.0)
		var shots := _shots(sim, 120, true)
		var misses := shots.map(func(s: SimEvent) -> bool: return s.data["miss"])
		var crits := shots.filter(func(s: SimEvent) -> bool: return s.data.get("crit", false))
		runs.append([misses, _combat_state(sim), crits.size()])
	assert_array(runs[1][0]).is_equal(runs[0][0])
	assert_int(runs[1][1]).is_equal(runs[0][1])
	assert_bool(runs[0][0].has(true)).is_true()  # Fraying did miss
	assert_int(runs[0][2]).is_equal(0)
	assert_int(runs[1][2]).is_equal(runs[1][0].count(false))  # every hit crits


func test_a_miss_never_crits_and_draws_no_crit() -> void:
	var sim := _sim()
	_always_miss(sim)
	_l3(sim, RIFLE, "a")
	_set_crit(sim, 1.0)
	var e := put(sim, "cultist", 7.0)
	var before := _crit_state(sim)
	var shot := _one_shot(sim)
	assert_bool(shot.data["miss"]).is_true()
	assert_bool(shot.data.has("crit")).is_false()
	assert_int(_crit_state(sim)).is_equal(before)
	assert_float(e.hp).is_equal(HUGE_HP)


func test_crits_at_the_configured_rate_and_the_same_seed_repeats_them() -> void:
	var seqs := []
	for i in 2:
		var sim := _sim()
		_l3(sim, RIFLE, "a")
		var l := _branch(sim, RIFLE, "a")
		var p: float = l.effects["crit_chance"]
		assert_float(p).is_equal(0.2)
		var e := put(sim, "cultist", 7.0)
		var shots := _shots(sim, 300)
		var seq := shots.map(func(s: SimEvent) -> bool: return s.data.get("crit", false))
		var n := seq.count(true)
		var sd := sqrt(300.0 * p * (1.0 - p))
		assert_float(absf(n - 300.0 * p)).override_failure_message("%d crits of 300" % n) \
			.is_less_equal(4.0 * sd)
		var m: float = l.effects["crit_multiplier"]
		assert_float(e.hp).is_equal_approx(
			HUGE_HP - (300 - n) * l.damage - n * l.damage * m, 1e-3)
		seqs.append(seq)
	assert_array(seqs[1]).is_equal(seqs[0])


## §2: a lit Marksman skips the miss roll (beam) but still crits.
func test_a_lit_marksman_never_misses_and_still_crits() -> void:
	var sim := _lit_sim()
	_always_miss(sim)
	_l3(sim, RIFLE, "a")
	_set_crit(sim, 1.0)
	put(sim, "cultist", 7.0)
	var combat0 := _combat_state(sim)
	var shot := _one_shot(sim)
	assert_bool(sim.tower_by_id(shot.id).lit).is_true()
	assert_bool(shot.data["miss"]).is_false()
	assert_bool(shot.data.get("crit", false)).is_true()
	assert_int(_combat_state(sim)).is_equal(combat0)


## §2: power_mult (lit occult) x crit, all before armor (no shipped tower has both; the
## order is fixed for later occult crits).
func test_lit_occult_power_and_crit_multiply_before_armor() -> void:
	var sim := _lit_sim({"hybrid": {"armor": 2}})
	var t := build(sim, NECRO)
	var l: TowerDef.Level = sim.config.towers[NECRO].levels[0]
	l.effects["crit_chance"] = 1.0
	l.effects["crit_multiplier"] = 2.0
	var e := put(sim, "hybrid", 8.0)
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_bool(t.lit).is_true()
	assert_bool(shot.data.get("crit", false)).is_true()
	var pm := sim.config.economy.beam.occult_power_mult
	assert_float(e.hp).is_equal_approx(HUGE_HP - (l.damage * pm * 2.0 - 2.0), 1e-3)


# --- §1.2 Gangsters bursts ------------------------------------------------------------------

## Four parked at route cells 6..9 (all in range 3 of the default tower); "first" ranks
## 9, 8, 7, 6. Returns them by cell.
func _gang(sim: Simulation, cells: Array, def_id := "cultist") -> Dictionary:
	var out := {}
	for c: float in cells:
		out[c] = put(sim, def_id, c)
	return out


func test_gangsters_round_robin_over_three_ranked_targets() -> void:
	var sim := _sim()
	var t := _l3(sim, RIFLE, "b")
	assert_float(_branch(sim, RIFLE, "b").effects["burst_targets"]).is_equal(3.0)
	var g := _gang(sim, [6.0, 7.0, 8.0, 9.0])
	var r: Array = [g[9.0].id, g[8.0].id, g[7.0].id]
	assert_array(_targets(_shots(sim, 7))).is_equal(r + r + [r[0]])
	assert_int(t.burst_index).is_equal(1)
	assert_float(g[6.0].hp).is_equal(HUGE_HP)  # the 4th ranked is never shot


func test_gangsters_with_two_targets_alternate_and_with_one_repeat() -> void:
	var sim := _sim()
	_l3(sim, RIFLE, "b")
	var g := _gang(sim, [7.0, 8.0])
	assert_array(_targets(_shots(sim, 4))).is_equal([g[8.0].id, g[7.0].id, g[8.0].id, g[7.0].id])
	var one := _sim()
	_l3(one, RIFLE, "b")
	var e := put(one, "cultist", 7.0)
	assert_array(_targets(_shots(one, 3))).is_equal([e.id, e.id, e.id])


## The ranked set shrinks when a target dies: target = ranked[index % m], nothing locked.
func test_gangsters_ranked_set_shrinks_when_a_target_dies() -> void:
	var sim := _sim()
	var t := _l3(sim, RIFLE, "b")
	var g := _gang(sim, [7.0, 8.0, 9.0])
	assert_array(_targets(_shots(sim, 2))).is_equal([g[9.0].id, g[8.0].id])
	assert_int(t.burst_index).is_equal(2)
	g[9.0].hp = 1.0  # dies to the next bullet aimed at it, not this one
	g[8.0].dead = true
	# Ranked now [9, 7] (m = 2): index 2 % 2 = 0 -> cell 9, then cell 7.
	assert_array(_targets(_shots(sim, 2))).is_equal([g[9.0].id, g[7.0].id])


func test_gangsters_priority_modes_change_the_ranking() -> void:
	var sim := _sim()
	var t := _l3(sim, RIFLE, "b")
	var g := _gang(sim, [6.0, 7.0, 8.0, 9.0])
	for c: float in g:  # hp rises against the route: strongest is the reverse of first
		g[c].hp = 1000.0 * (10.0 - c)
	assert_int(sim.set_target_priority(t.id, "strongest")).is_equal(Simulation.CommandResult.OK)
	var r: Array = [g[6.0].id, g[7.0].id, g[8.0].id]
	assert_array(_targets(_shots(sim, 4))).is_equal(r + [r[0]])
	var f := _sim()
	var tf := _l3(f, RIFLE, "b")
	var fg := _gang(f, [6.0, 7.0, 8.0, 9.0])
	fg[6.0].base_units_per_tick = 3
	fg[8.0].base_units_per_tick = 2
	fg[7.0].base_units_per_tick = 1
	assert_int(f.set_target_priority(tf.id, "fastest")).is_equal(Simulation.CommandResult.OK)
	assert_array(_targets(_shots(f, 3))).is_equal([fg[6.0].id, fg[8.0].id, fg[7.0].id])


func test_gangsters_ties_go_to_the_lower_id() -> void:
	var sim := _sim()
	var t := _l3(sim, RIFLE, "b")
	var a := put(sim, "cultist", 7.0)
	var b := put(sim, "cultist", 8.0)
	var c := put(sim, "cultist", 9.0)
	assert_int(sim.set_target_priority(t.id, "strongest")).is_equal(Simulation.CommandResult.OK)
	for e in [a, b, c]:
		e.hp = 50000.0
	# Equal hp at the first ranking: lower id first.
	assert_array(_targets(_shots(sim, 1))).is_equal([a.id])


func test_gangsters_each_bullet_rolls_its_own_miss_and_a_miss_moves_on() -> void:
	var sim := _sim()
	_fray(sim)
	_l3(sim, RIFLE, "b")
	var g := _gang(sim, [7.0, 8.0, 9.0], "hybrid")  # no traits
	var mirror := _sim()
	var combat0 := _combat_state(sim)
	assert_int(_combat_state(mirror)).is_equal(combat0)
	var shots := _shots(sim, 60, true)
	for i in shots.size():
		mirror.rng(SimRng.Stream.COMBAT).randf()
	assert_int(_combat_state(sim)).is_equal(_combat_state(mirror))  # one draw per bullet
	var r: Array = [g[9.0].id, g[8.0].id, g[7.0].id]
	var want := []
	for i in shots.size():
		want.append(r[i % 3])
	assert_array(_targets(shots)).is_equal(want)  # misses advance the round robin too
	var misses := shots.filter(func(s: SimEvent) -> bool: return s.data["miss"]).size()
	assert_int(misses).is_greater(0)
	assert_int(misses).is_less(shots.size())


func test_gangsters_fire_every_6_ticks_and_5_when_lit() -> void:
	var gaps := []
	for lit: bool in [false, true]:
		var sim := _lit_sim() if lit else _sim()
		_l3(sim, RIFLE, "b")
		put(sim, "cultist", 7.0)
		var ticks := _shots(sim, 3).map(func(s: SimEvent) -> int: return s.tick)
		gaps.append([ticks[1] - ticks[0], ticks[2] - ticks[1]])
		var fi := _branch(sim, RIFLE, "b").fire_interval
		var want := SimTime.ticks(fi)
		if lit:
			want = maxi(1, SimTime.ticks(fi * sim.config.economy.beam.mundane_fire_interval_mult))
		assert_array(gaps[-1]).override_failure_message("lit %s" % lit).is_equal([want, want])
	assert_array(gaps).is_equal([[6, 6], [5, 5]])  # owner decision Q3: whole ticks


# --- §1.3 Barbed bleed ----------------------------------------------------------------------

## A Barbed harpooner on the default cell, its second shot pushed far away after tick 1.
func _barbed_once(sim: Simulation, e: SimEnemy) -> SimTower:
	var t := _l3(sim, HARP, "a")
	_one_shot(sim)
	t.cooldown_ticks = 1000000
	assert_int(sim.state.tick).is_equal(1)
	assert_bool(e.status.has("bleed_ticks")).is_true()
	return t


## hp of `e` after each tick from the current one to `last`, keyed by tick.
func _hp_by_tick(sim: Simulation, e: SimEnemy, last: int) -> Dictionary:
	var out := {}
	while sim.state.tick < last:
		sim.step()
		out[sim.state.tick] = e.hp
	return out


func test_bleed_pulses_once_a_second_through_armor_then_ends() -> void:
	var sim := _sim({"hybrid": {"armor": 2}})
	var l := _branch(sim, HARP, "a")
	assert_float(l.effects["bleed_dps"]).is_equal(6.0)
	assert_float(l.effects["bleed_seconds"]).is_equal(3.0)
	var e := put(sim, "hybrid", 10.0)
	_barbed_once(sim, e)
	var hp0 := HUGE_HP - (l.damage - 2.0)
	assert_float(e.hp).is_equal(hp0)
	assert_int(e.status["bleed_ticks"]).is_equal(90)
	assert_str(e.status["bleed_source"]).is_equal(HARP)
	var hp := _hp_by_tick(sim, e, 120)
	var pulse := 6.0 - 2.0  # armor once per pulse (Q1)
	for tick: int in hp:
		var n := 0
		for p in [31, 61, 91]:
			if tick >= p:
				n += 1
		assert_float(hp[tick]).override_failure_message("tick %d" % tick) \
			.is_equal(hp0 - n * pulse)
	for key: String in ["bleed_ticks", "bleed_dps", "bleed_pulse", "bleed_source"]:
		assert_bool(e.status.has(key)).override_failure_message(key).is_false()


func test_bleed_status_is_gone_the_tick_of_the_last_pulse() -> void:
	var sim := _sim()
	var e := put(sim, "cultist", 10.0)
	_barbed_once(sim, e)
	run_to(sim, 90)
	assert_bool(e.status.has("bleed_ticks")).is_true()
	run_to(sim, 91)
	assert_dict(e.status).is_empty()


func test_a_second_barbed_hit_refreshes_the_bleed_never_stacks() -> void:
	var sim := _sim()
	var e := put(sim, "cultist", 10.0)
	_barbed_once(sim, e)
	run_to(sim, 45)
	assert_int(e.status["bleed_ticks"]).is_equal(46)
	# Another Barbed tower hits on tick 46: duration back to 90, same dps, pulse kept.
	var other := _l3(sim, HARP, "a", Vector2i(8, 1))
	var shot := _one_shot(sim)
	assert_int(shot.id).is_equal(other.id)
	other.cooldown_ticks = 1000000
	assert_int(e.status["bleed_ticks"]).is_equal(90)
	assert_float(e.status["bleed_dps"]).is_equal(6.0)
	assert_int(e.status["bleed_pulse"]).is_equal(15)
	var dmg := _branch(sim, HARP, "a").damage
	run_to(sim, 140)
	# Pulses at 31, 61, 91, 121 (the refreshed bleed ends on 136): 4 x 6, never 12/s.
	assert_float(e.hp).is_equal(HUGE_HP - 2.0 * dmg - 4.0 * 6.0)
	assert_dict(e.status).is_empty()


func test_refresh_keeps_the_higher_dps_and_its_source() -> void:
	var sim := _sim()
	var e := put(sim, "cultist", 10.0)
	sim._apply_bleed(e, 6.0, 3.0, "a")
	sim._apply_bleed(e, 3.0, 1.0, "b")
	assert_array([e.status["bleed_dps"], e.status["bleed_source"], e.status["bleed_ticks"]]) \
		.is_equal([6.0, "a", 90])
	sim._apply_bleed(e, 10.0, 1.0, "c")
	assert_array([e.status["bleed_dps"], e.status["bleed_source"], e.status["bleed_ticks"]]) \
		.is_equal([10.0, "c", 90])
	assert_int(e.status["bleed_pulse"]).is_equal(SimTime.TICK_RATE)  # set once, on the new bleed


func test_fakes_bleed_like_real_enemies() -> void:
	var sim := _sim()
	var f := put(sim, "cultist", 10.0, HUGE_HP, true)
	_barbed_once(sim, f)
	var hp0 := f.hp
	run_to(sim, 31)
	assert_float(f.hp).is_equal(hp0 - 6.0)


func test_a_bleed_kill_is_a_mundane_kill() -> void:
	var sim := _sim()
	sim.state.sanity = 80.0
	sim.state.sanity_state = sim.sanity_state_for(80.0)
	var dmg := _branch(sim, HARP, "a").damage
	var e := put(sim, "cultist", 10.0, dmg + 6.0)
	_barbed_once(sim, e)
	assert_bool(e.is_live()).is_true()
	var ev := run_to(sim, 31)
	var died := of_type(ev, T.DIED)
	assert_int(died.size()).is_equal(1)
	assert_int(died[0].id).is_equal(e.id)
	assert_int(died[0].tick).is_equal(31)
	assert_str(died[0].data["source"]).is_equal(HARP)
	var kill := of_type(ev, T.SANITY_CHANGED).filter(
		func(s: SimEvent) -> bool: return s.data["reason"] == "mundane_kill")
	assert_int(kill.size()).is_equal(1)
	assert_float(kill[0].data["delta"]).is_equal(sim.config.sanity.regen_mundane_kill)


func test_bleed_pulse_sees_the_seal_strip_and_exposure() -> void:
	var sim := _sim({"hybrid": {"armor": 2}})
	_l3(sim, SIGN, "b", Vector2i(8, 1))
	var mult: float = _branch(sim, SIGN, "b").effects["damage_taken_multiplier"]
	var e := put(sim, "hybrid", 10.0)
	_barbed_once(sim, e)
	var hp0 := e.hp
	assert_float(hp0).is_equal(HUGE_HP - (_branch(sim, HARP, "a").damage - 1.0) * mult)
	run_to(sim, 31)
	assert_float(e.hp).is_equal(hp0 - (6.0 - 1.0) * mult)  # 7.5 per pulse


func test_shots_without_bleed_or_pull_leave_status_alone() -> void:
	var sim := _sim()
	build(sim, HARP)  # L1: pierce only
	var e := put(sim, "cultist", 10.0)
	var shot := _one_shot(sim)
	assert_dict(e.status).is_empty()
	assert_bool(shot.data.has("pulled")).is_false()


# --- §1.4 Chain harpoon pull ----------------------------------------------------------------

const PULL_UNITS := 45000  ## 1.5 cells x 30000


func test_chain_pulls_only_the_primary_back_one_and_a_half_cells() -> void:
	var sim := _sim()
	var l := _branch(sim, HARP, "b")
	assert_int(roundi(float(l.effects["pull_cells"]) * SimTime.UNITS_PER_CELL)).is_equal(PULL_UNITS)
	_l3(sim, HARP, "b")
	var other := put(sim, "cultist", 9.0, 400.0)
	var primary := put(sim, "cultist", 10.0, 400.0)
	var d_other := other.distance
	var d0 := primary.distance
	var shot := _one_shot(sim)
	assert_int(shot.data["target"]).is_equal(primary.id)
	assert_array(shot.data["hits"]).contains_exactly_in_any_order([other.id, primary.id])
	assert_array(shot.data["pulled"]).is_equal([primary.id])
	assert_int(primary.distance).is_equal(d0 - PULL_UNITS)
	assert_int(primary.prev_distance).is_equal(primary.distance)
	assert_int(other.distance).is_equal(d_other)  # hit, not pulled
	assert_int(primary.status["pull_immune_ticks"]).is_equal(90)


func test_pull_clamps_at_the_path_start() -> void:
	var sim := _sim()
	_l3(sim, HARP, "b", Vector2i(1, 1))
	var e := put(sim, "cultist", 1.0, 400.0)
	assert_int(e.distance).is_less(PULL_UNITS)
	var shot := _one_shot(sim)
	assert_array(shot.data["pulled"]).is_equal([e.id])
	assert_int(e.distance).is_equal(0)
	assert_int(e.prev_distance).is_equal(0)


func test_pull_hp_cap_is_inclusive_and_bigger_foes_are_never_pulled() -> void:
	for hp: float in [500.0, 501.0]:
		var sim := _sim()
		assert_float(_branch(sim, HARP, "b").effects["pull_max_hp"]).is_equal(500.0)
		_l3(sim, HARP, "b")
		var e := put(sim, "cultist", 10.0, hp)
		var d0 := e.distance
		var shot := _one_shot(sim)
		var pulled := hp <= 500.0
		assert_array(shot.data["pulled"]).override_failure_message("hp %s" % hp) \
			.is_equal([e.id] if pulled else [])
		assert_int(e.distance).is_equal(d0 - PULL_UNITS if pulled else d0)
		assert_bool(e.status.has("pull_immune_ticks")).is_equal(pulled)


func test_pull_immunity_refuses_any_chain_for_90_ticks() -> void:
	var sim := _sim()
	var t1 := _l3(sim, HARP, "b")
	var t2 := _l3(sim, HARP, "b", Vector2i(8, 1))
	var e := put(sim, "cultist", 10.0, 400.0)
	var d0 := e.distance
	var shots := of_type(run(sim, 1), T.SHOT)
	assert_int(shots.size()).is_equal(2)
	assert_array(shots[0].data["pulled"]).is_equal([e.id])
	assert_array(shots[1].data["pulled"]).is_empty()  # the second tower respects it
	assert_int(e.distance).is_equal(d0 - PULL_UNITS)
	run_to(sim, 89)
	t2.cooldown_ticks = 1000000
	t1.cooldown_ticks = 0
	var at90 := _one_shot(sim)  # tick 90: 1 immune tick left
	assert_int(at90.tick).is_equal(90)
	assert_array(at90.data["pulled"]).is_empty()
	assert_int(e.distance).is_equal(d0 - PULL_UNITS)
	t1.cooldown_ticks = 0
	var at91 := _one_shot(sim)  # tick 91: immunity erased in slot 2
	assert_array(at91.data["pulled"]).is_equal([e.id])
	assert_int(e.distance).is_equal(d0 - 2 * PULL_UNITS)


func test_pull_immunity_counts_down_and_is_erased() -> void:
	var sim := _sim()
	var t := _l3(sim, HARP, "b")
	var e := put(sim, "cultist", 10.0, 400.0)
	_one_shot(sim)
	t.cooldown_ticks = 1000000
	run_to(sim, 31)
	assert_int(e.status["pull_immune_ticks"]).is_equal(60)
	run_to(sim, 91)
	assert_bool(e.status.has("pull_immune_ticks")).is_false()


func test_a_killed_or_missed_primary_is_not_pulled() -> void:
	var sim := _sim()
	_l3(sim, HARP, "b")
	var e := put(sim, "cultist", 10.0, 10.0)  # dies to the harpoon
	var d0 := e.distance
	var shot := _one_shot(sim)
	assert_bool(e.is_live()).is_false()
	assert_array(shot.data["pulled"]).is_empty()
	assert_int(e.distance).is_equal(d0)
	var m := _sim()
	_always_miss(m)
	_l3(m, HARP, "b")
	var me := put(m, "cultist", 10.0, 400.0)
	var md := me.distance
	var ms := _one_shot(m)
	assert_bool(ms.data["miss"]).is_true()
	assert_array(ms.data["pulled"]).is_empty()
	assert_int(me.distance).is_equal(md)


## An L-shaped path: the flyer's straight S -> L line is not the ground path.
const L_ROWS := [
	"S......",
	"#......",
	"#......",
	"######L",
]


func test_a_flyer_is_pulled_back_along_its_straight_line() -> void:
	var sim := Simulation.new(make_config(L_ROWS), SEED)
	sim.state.gold = 1000000
	_l3(sim, HARP, "b", Vector2i(2, 1))
	var f := put(sim, "night_gaunt", 3.0, 400.0)
	assert_bool(f.def.flying).is_true()
	var d0 := f.distance
	var shot := _one_shot(sim)
	assert_array(shot.data["pulled"]).is_equal([f.id])
	assert_int(f.distance).is_equal(d0 - PULL_UNITS)
	assert_int(f.prev_distance).is_equal(f.distance)
	# Still on the S -> L segment: (0.5, 0.5) -> (6.5, 3.5).
	var p := f.route.position_at(f.distance)
	var s := Vector2(0.5, 0.5)
	var dir := Vector2(6.5, 3.5) - s
	assert_float(absf((Vector2(p) - s).cross(dir))).is_less(1e-3)
	assert_float(p.x).is_greater(0.6)  # off the ground path's first column


func test_a_barbed_shot_has_no_pulled_key() -> void:
	var sim := _sim()
	_l3(sim, HARP, "a")
	put(sim, "cultist", 10.0, 400.0)
	assert_bool(_one_shot(sim).data.has("pulled")).is_false()


# --- §1.5 Corrupted Seal armor strip --------------------------------------------------------

## Hit of `amount` on `e` after one tick with the auras of the board.
func _hit_after_tick(sim: Simulation, e: SimEnemy, amount := 10.0) -> float:
	sim.step()
	return sim.apply_damage(e.id, amount, "test")


func test_seal_strips_one_armor_before_the_exposure() -> void:
	var sim := _sim({"cultist": {"armor": 5}})
	_l3(sim, SIGN, "b")
	var l := _branch(sim, SIGN, "b")
	assert_float(l.effects["strip_armor"]).is_equal(1.0)
	var mult: float = l.effects["damage_taken_multiplier"]
	var inside := put(sim, "cultist", 7.0)
	var outside := put(sim, "cultist", 0.0)
	sim.step()
	assert_float(inside.armor_bonus).is_equal(-1.0)
	assert_float(outside.armor_bonus).is_equal(0.0)
	assert_float(sim.apply_damage(inside.id, 10.0, "test")).is_equal((10.0 - 4.0) * mult)
	assert_float((10.0 - 4.0) * mult).is_equal(9.0)  # spec example: rifle 10 vs Shoggoth armor
	assert_float(sim.apply_damage(outside.id, 10.0, "test")).is_equal(5.0)


func test_a_plain_elder_sign_strips_nothing() -> void:
	var sim := _sim({"cultist": {"armor": 5}})
	build(sim, SIGN)
	var e := put(sim, "cultist", 7.0)
	var mult: float = sim.config.towers[SIGN].levels[0].effects["damage_taken_multiplier"]
	assert_float(_hit_after_tick(sim, e)).is_equal((10.0 - 5.0) * mult)
	assert_float(e.armor_bonus).is_equal(0.0)


func test_two_seals_strip_the_max_not_the_sum() -> void:
	var sim := _sim({"cultist": {"armor": 5}})
	_l3(sim, SIGN, "b", Vector2i(6, 1))
	_l3(sim, SIGN, "b", Vector2i(8, 1))
	var e := put(sim, "cultist", 7.0)
	var mult: float = _branch(sim, SIGN, "b").effects["damage_taken_multiplier"]
	assert_float(_hit_after_tick(sim, e)).is_equal((10.0 - 4.0) * mult)
	assert_float(e.armor_bonus).is_equal(-1.0)


func test_strip_never_takes_armor_below_zero() -> void:
	var sim := _sim()
	_l3(sim, SIGN, "b")
	var e := put(sim, "cultist", 7.0)
	assert_float(e.def.armor).is_equal(0.0)
	var mult: float = _branch(sim, SIGN, "b").effects["damage_taken_multiplier"]
	assert_float(_hit_after_tick(sim, e)).is_equal(10.0 * mult)


func test_strip_ends_the_tick_the_enemy_leaves_the_ring() -> void:
	var sim := _sim({"cultist": {"armor": 5}})
	_l3(sim, SIGN, "b")
	var e := put(sim, "cultist", 7.0)
	sim.step()
	assert_float(e.armor_bonus).is_equal(-1.0)
	e.distance = 0
	e.prev_distance = 0
	sim.step()
	assert_float(e.armor_bonus).is_equal(0.0)
	assert_float(sim.apply_damage(e.id, 10.0, "test")).is_equal(5.0)


func test_a_seal_with_only_strip_armor_is_still_an_aura() -> void:
	var sim := _sim({"cultist": {"armor": 5}})
	_l3(sim, SIGN, "b")
	_branch(sim, SIGN, "b").effects = {"strip_armor": 2.0}
	var e := put(sim, "cultist", 7.0)
	assert_float(_hit_after_tick(sim, e)).is_equal(10.0 - 3.0)
	assert_float(e.speed_mult).is_equal(1.0)


func test_a_lit_seal_strips_at_power_mult() -> void:
	var sim := _lit_sim({"cultist": {"armor": 5}})
	var t := _l3(sim, SIGN, "b")
	var e := put(sim, "cultist", 7.0)
	var pm := sim.config.economy.beam.occult_power_mult
	var mult: float = _branch(sim, SIGN, "b").effects["damage_taken_multiplier"]
	var got := _hit_after_tick(sim, e)
	assert_bool(t.lit).is_true()
	assert_float(e.armor_bonus).is_equal_approx(-pm, 1e-6)
	assert_float(got).is_equal_approx((10.0 - (5.0 - pm)) * (1.0 + (mult - 1.0) * pm), 1e-4)
