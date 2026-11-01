class_name SearchlightTest
extends TowerTestBase
## LT-49 Coast Guard searchlight in the sim (docs/design/LT-46-tower-roster.md §2.2 Q1 B,
## §3, §4 P8, §5 LT-49): an aura like Elder Sign's (same _apply_auras path, detected on
## `reveal_fakes` too) that sets `revealed` for good on every live fake inside, in slot 2
## before towers fire; a real enemy is never revealed. A revealed fake leaves every tower's
## target candidates (single, burst, pierce, aoe, fuse): a tower with only a revealed fake in
## range holds fire with its cooldown at 0. It is still hit as collateral and still in the
## madness "fake" astray pool. Slows 0.2 (L1) / 0.4 + x1.2 taken (b), not stacked with Elder
## Sign (max), not scaled when lit (mundane). No damage, no shots, no regen;
## debug_is_fake is unchanged by a reveal.
## Searchlight at SL, centre (3.5, 1.5); an enemy `put` at c cells is at (c + 0.5, 0.5), so
## it is inside the L1 radius 3 iff (c - 3)^2 + 1 <= 9, i.e. c in [0.18, 5.82]. The default
## tower cell (7, 1) reaches c in [4.18, 9.82] at range 3.

const T := SimEvent.Type
const SLT := "searchlight"
const SL := Vector2i(3, 1)
const SIGN := "elder_sign"


# --- helpers ---------------------------------------------------------------------------

func _sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	return sim


## tsim with the beam on and still (phase NONE shines): the default tower cell is lit.
func _lit_sim() -> Simulation:
	lit_beam = true
	var sim := tsim()
	lit_beam = false
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	return sim


func _fake(sim: Simulation, cells: float) -> SimEnemy:
	var e := put(sim, "cultist", cells, HUGE_HP, true)
	assert_bool(e.is_fake).is_true()
	return e


func _sl(sim: Simulation, cell := SL) -> SimTower:
	return build(sim, SLT, cell)


## Builds `def_id` at `cell` and sets it to L3 `branch` (no gold or event).
func _l3(sim: Simulation, def_id: String, branch: String, cell := TOWER) -> SimTower:
	var t := build(sim, def_id, cell)
	t.level = TowerDef.LEVEL_COUNT
	t.branch = branch
	sim.drain_events()
	return t


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _move_to(e: SimEnemy, cells: float) -> void:
	e.distance = roundi(cells * SimTime.UNITS_PER_CELL)
	e.prev_distance = e.distance


# --- reveal -----------------------------------------------------------------------------

func test_a_fake_inside_is_revealed_the_same_tick_and_the_rifleman_shoots_the_real_one() -> void:
	var sim := _sim()
	_sl(sim)
	var rifle := build(sim, "rifleman")
	assert_str(rifle.target_priority).is_equal("first")
	var real := put(sim, "cultist", 4.5)  # inside the aura and the rifle's range
	var fake := _fake(sim, 5.5)  # inside both, and ahead: "first" if it were a candidate
	sim.drain_events()
	assert_bool(fake.revealed).is_false()
	var shots := of_type(run(sim, 1), T.SHOT)
	assert_bool(fake.revealed).is_true()
	assert_bool(real.revealed).is_false()
	assert_int(shots.size()).is_equal(1)
	assert_int(shots[0].id).is_equal(rifle.id)
	assert_int(shots[0].data["target"]).is_equal(real.id)
	assert_float(fake.hp).is_equal(HUGE_HP)


func test_a_real_enemy_inside_is_never_revealed() -> void:
	var sim := _sim()
	_sl(sim)
	var real := put(sim, "cultist", 3.0)
	sim.drain_events()
	run(sim, 60)
	assert_bool(real.revealed).is_false()


func test_revealed_stays_after_the_fake_leaves_and_after_the_searchlight_is_sold() -> void:
	var sim := _sim()
	var sl := _sl(sim)
	var fake := _fake(sim, 3.0)
	sim.drain_events()
	run(sim, 1)
	assert_bool(fake.revealed).is_true()
	_move_to(fake, 12.0)  # (12.5, 0.5): 9 cells off the aura centre
	run(sim, 5)
	assert_bool(fake.revealed).is_true()
	assert_int(sim.sell_tower(sl.id)).is_equal(Simulation.CommandResult.OK)
	assert_array(sim.state.towers).is_empty()
	# Back in a rifle's range with no searchlight left: still revealed, still not a target.
	var rifle := build(sim, "rifleman")
	_move_to(fake, 7.0)
	sim.drain_events()
	assert_array(of_type(run(sim, 60), T.SHOT)).is_empty()
	assert_bool(fake.revealed).is_true()
	assert_int(rifle.cooldown_ticks).is_equal(0)


func test_a_reveal_only_aura_reveals_inside_and_not_outside_its_radius() -> void:
	var sim := _sim()
	var l: TowerDef.Level = sim.config.towers[SLT].levels[0]
	l.effects = {"reveal_fakes": 1.0}  # no slow, no multiplier: detected on reveal_fakes
	assert_float(l.range_cells).is_equal(3.0)
	_sl(sim)
	var inside := _fake(sim, 5.0)  # 2.24 cells
	var edge := _fake(sim, 5.75)  # 2.93 cells
	var outside := _fake(sim, 6.0)  # 3.16 cells
	sim.drain_events()
	run(sim, 1)
	assert_bool(inside.revealed).is_true()
	assert_bool(edge.revealed).is_true()
	assert_bool(outside.revealed).is_false()
	assert_float(inside.speed_mult).is_equal(1.0)


# --- candidates -----------------------------------------------------------------------------

## [def_id, branch ("" = L1), parked cell of the fake] for every targeting style: single,
## burst (Gangsters), pierce, aoe, fuse, and a dead-zone tower (the fake outside min_range).
const STYLES := [
	["rifleman", "", 7.0],
	["rifleman", "b", 7.0],
	["harpooner", "", 7.0],
	["necronomicon_reader", "", 7.0],
	["dynamite_crew", "", 7.0],
	["coast_battery", "", 3.0],
]


func test_no_tower_style_targets_a_revealed_fake_and_each_holds_fire_ready() -> void:
	for row: Array in STYLES:
		var id: String = row[0]
		var branch: String = row[1]
		var msg := "%s %s" % [id, branch]
		var sim := _sim()
		var t: SimTower = _l3(sim, id, branch) if branch != "" else build(sim, id)
		if branch == "b":
			assert_float(t.stats().effects.get("burst_targets", 0.0)).is_equal(3.0)
		var fake := _fake(sim, row[2])
		fake.revealed = true
		sim.drain_events()
		var ev := run(sim, 60)
		assert_array(of_type(ev, T.SHOT)).override_failure_message(msg).is_empty()
		assert_int(t.cooldown_ticks).override_failure_message(msg).is_equal(0)
		assert_float(fake.hp).override_failure_message(msg).is_equal(HUGE_HP)
		# A real enemy steps in: shot on the very next tick, at it.
		var real := put(sim, "cultist", row[2])
		var shots := of_type(run(sim, 1), T.SHOT)
		assert_int(shots.size()).override_failure_message(msg).is_equal(1)
		assert_int(shots[0].data["target"]).override_failure_message(msg).is_equal(real.id)


func test_gangsters_round_robin_skips_a_revealed_fake() -> void:
	var sim := _sim()
	_l3(sim, "rifleman", "b")
	var real := put(sim, "cultist", 6.0)
	var fake := _fake(sim, 8.0)  # ahead of the real one: in the top 3 if it were a candidate
	fake.revealed = true
	var shots := of_type(run(sim, 60), T.SHOT)
	assert_int(shots.size()).is_greater(3)
	for s in shots:
		assert_int(s.data["target"]).is_equal(real.id)
	assert_float(fake.hp).is_equal(HUGE_HP)


# --- collateral and astray ------------------------------------------------------------------

func test_a_revealed_fake_is_still_hit_by_a_line_shot_and_a_blast_on_another_target() -> void:
	# Each fake stands on the real target's spot: inside any line or blast centred on it.
	for id: String in ["harpooner", "necronomicon_reader", "dynamite_crew"]:
		var sim := _sim()
		build(sim, id)
		var real := put(sim, "cultist", 7.0)
		var fake := _fake(sim, 7.0)
		fake.revealed = true
		sim.drain_events()
		var l: TowerDef.Level = sim.config.towers[id].levels[0]
		var ev := run(sim, 1 + SimTime.ticks(float(l.effects.get("fuse_seconds", 0.0))))
		var shots := of_type(ev, T.SHOT)
		assert_int(shots.size()).override_failure_message(id).is_equal(1)
		assert_int(shots[0].data["target"]).override_failure_message(id).is_equal(real.id)
		assert_float(fake.hp).override_failure_message(id).is_less(HUGE_HP)
		assert_float(fake.hp).override_failure_message(id).is_equal(real.hp)


func test_a_madness_fake_astray_shot_may_still_land_on_a_revealed_fake() -> void:
	var sim := _sim()
	var m := sim.config.sanity.madness
	m.enemy_speed_multiplier = 1.0
	m.enemy_damage_taken_multiplier = 1.0
	m.shot_real = 0.0
	m.shot_fake = 1.0
	m.shot_empty = 0.0
	var t := build(sim, "necronomicon_reader")
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	var real := put(sim, "cultist", 6.0)  # the only candidate: the tower fires
	var fake := _fake(sim, 9.0)  # 2.24 cells: in range, revealed
	fake.revealed = true
	sim.drain_events()
	t.cooldown_ticks = 0
	var shots := of_type(run(sim, 1), T.SHOT)
	assert_int(shots.size()).is_equal(1)
	assert_bool(shots[0].data["astray"]).is_true()
	assert_int(shots[0].data["target"]).is_equal(fake.id)
	assert_array(shots[0].data["hits"]).contains([fake.id])
	assert_float(fake.hp).is_less(HUGE_HP)
	assert_float(real.hp).is_equal(HUGE_HP)


# --- slow and multiplier ----------------------------------------------------------------------

func test_l1_slows_by_its_slow_and_branch_b_slows_harder_and_marks() -> void:
	var sim := _sim()
	var sl := _sl(sim)
	var e := put(sim, "cultist", 3.0)
	sim.drain_events()
	run(sim, 1)
	var l1: TowerDef.Level = sim.config.towers[SLT].levels[0]
	assert_float(float(l1.effects["slow"])).is_equal(0.2)
	assert_float(e.speed_mult).is_equal_approx(0.8, 1e-9)
	assert_float(e.damage_taken_mult).is_equal(1.0)
	sl.level = TowerDef.LEVEL_COUNT
	sl.branch = "b"
	run(sim, 1)
	assert_float(e.speed_mult).is_equal_approx(0.6, 1e-9)
	assert_float(e.damage_taken_mult).is_equal_approx(1.2, 1e-9)


func test_a_lit_searchlight_is_not_scaled_by_the_occult_power_mult() -> void:
	var sim := _lit_sim()
	var pm := sim.config.economy.beam.occult_power_mult
	assert_float(pm).is_not_equal(1.0)  # else the check below tells nothing
	var sl := _l3(sim, SLT, "b")
	var e := put(sim, "cultist", 7.0)
	sim.drain_events()
	run(sim, 1)
	assert_bool(sl.lit).is_true()
	assert_float(e.speed_mult).is_equal_approx(0.6, 1e-9)
	assert_float(e.damage_taken_mult).is_equal_approx(1.2, 1e-9)


func test_with_elder_sign_the_slow_is_the_max_and_reveal_comes_from_any_aura() -> void:
	var sim := _sim()
	_sl(sim)  # built first: the sign comes later in the tower list
	build(sim, SIGN, Vector2i(5, 1))  # centre (5.5, 1.5), radius 2.5
	var es: TowerDef.Level = sim.config.towers[SIGN].levels[0]
	var both := _fake(sim, 4.5)  # 1.80 off the light, 1.41 off the sign
	var sign_only := _fake(sim, 7.5)  # 4.61 off the light, 2.24 off the sign
	sim.drain_events()
	run(sim, 1)
	var slow := maxf(0.2, float(es.effects["slow"]))
	assert_float(both.speed_mult).is_equal_approx(1.0 - slow, 1e-9)
	assert_float(both.damage_taken_mult) \
		.is_equal_approx(float(es.effects["damage_taken_multiplier"]), 1e-9)
	assert_bool(both.revealed).is_true()
	assert_bool(sign_only.revealed).is_false()


# --- no damage ------------------------------------------------------------------------------

func test_the_searchlight_never_shoots_kills_or_restores_sanity() -> void:
	var sim := _sim()
	_set_sanity(sim, 60.0)
	var sl := _sl(sim)
	assert_float(sl.stats().damage).is_equal(0.0)
	assert_bool(sim.has_targeting(sl)).is_false()
	var real := put(sim, "cultist", 3.0, 1.0)
	var fake := _fake(sim, 4.0)
	sim.drain_events()
	var ev := run(sim, 120)
	assert_array(of_type(ev, T.SHOT)).is_empty()
	assert_array(of_type(ev, T.DIED)).is_empty()
	assert_array(of_type(ev, T.SANITY_CHANGED).filter(
		func(s: SimEvent) -> bool: return s.data["reason"] == "mundane_kill")).is_empty()
	assert_float(real.hp).is_equal(1.0)
	assert_float(fake.hp).is_equal(HUGE_HP)
	assert_int(sl.cooldown_ticks).is_equal(0)


# --- render isolation -----------------------------------------------------------------------

func test_a_reveal_does_not_change_debug_is_fake() -> void:
	var sim := _sim()
	_sl(sim)
	var fake := _fake(sim, 3.0)
	sim.drain_events()
	run(sim, 1)
	assert_bool(fake.revealed).is_true()
	assert_bool(sim.debug_reveal_fakes).is_false()
	assert_bool(sim.debug_is_fake(fake)).is_false()
	sim.debug_reveal_fakes = true
	assert_bool(sim.debug_is_fake(fake)).is_true()
