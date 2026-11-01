class_name ResonatorTest
extends TowerTestBase
## LT-50 Tillinghast Resonator in the sim (docs/design/LT-46-tower-roster.md §2.2, §3, §4
## P7/P8/P13/P14, §6; §7 Q2 "current sanity on the full bar"): a shot every 6 ticks, damage
## x (1 + sanity_scaling x (1 - sanity / max)) on the full 100 bar, before the lit x0.7 and
## the madness x2; armor ignored; the beam keeps its target while that one stays a live
## candidate, re-picks when it dies or leaves range, and a target_priority change drops the
## lock; Pure reveals a fake it hits and then lets go of it, the other levels never reveal;
## a Pure tower is no reveal aura; its SHOT carries beam and sanity_factor.
## Tower centre (7.5, 1.5); an enemy `put` at c cells is at (c + 0.5, 0.5), inside L1 range 3
## iff c in [4.18, 9.82].

const T := SimEvent.Type
const RS := "resonator"


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


func _l1(sim: Simulation) -> TowerDef.Level:
	return sim.config.towers[RS].levels[0]


## Builds the Resonator on the default cell and sets it to L3 `branch` (no gold or event).
func _l3(sim: Simulation, branch: String) -> SimTower:
	var t := build(sim, RS)
	t.level = TowerDef.LEVEL_COUNT
	t.branch = branch
	sim.drain_events()
	return t


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _fake(sim: Simulation, cells: float) -> SimEnemy:
	var e := put(sim, "cultist", cells, HUGE_HP, true)
	assert_bool(e.is_fake).is_true()
	return e


func _move_to(e: SimEnemy, cells: float) -> void:
	e.distance = roundi(cells * SimTime.UNITS_PER_CELL)
	e.prev_distance = e.distance


## Steps once; asserts exactly one SHOT that tick and returns it.
func _one_shot(sim: Simulation) -> SimEvent:
	var shots := of_type(run(sim, 1), T.SHOT)
	assert_int(shots.size()).is_equal(1)
	return shots[0]


## Steps to the tower's next shot (cooldown ticks) and returns that SHOT.
func _next_shot(sim: Simulation, t: SimTower) -> SimEvent:
	var shots := of_type(run(sim, t.cooldown_ticks), T.SHOT)
	assert_int(shots.size()).is_equal(1)
	return shots[0]


func _madness(sim: Simulation) -> void:
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	var m := sim.config.sanity.madness
	m.shot_real = 1.0  # every astray shot lands on a real enemy (the only one in range)
	m.shot_fake = 0.0
	m.shot_empty = 0.0


# --- rate and the sanity factor -------------------------------------------------------------

func test_l1_at_sanity_40_fires_every_6_ticks_for_3_x_2_2() -> void:
	var sim := _sim()
	var t := build(sim, RS)
	var e := put(sim, "cultist", 6.0)
	_set_sanity(sim, 40.0)
	var ev := run(sim, 13)
	assert_array(shot_ticks(ev)).is_equal([1, 7, 13])
	assert_float(e.hp).is_equal_approx(HUGE_HP - 3 * 6.6, 1e-6)
	var shot := of_type(ev, T.SHOT)[0]
	assert_bool(shot.data["beam"]).is_true()
	assert_float(shot.data["sanity_factor"]).is_equal_approx(2.2, 1e-9)
	assert_int(shot.id).is_equal(t.id)


func test_at_full_sanity_the_factor_is_one() -> void:
	var sim := _sim()
	_l1(sim).sanity_reserve = 0.0  # keeps the cap at max, so sanity can sit at 100
	build(sim, RS)
	var e := put(sim, "cultist", 6.0)
	_set_sanity(sim, sim.config.sanity.max_sanity)
	var shot := _one_shot(sim)
	assert_float(shot.data["sanity_factor"]).is_equal(1.0)
	assert_float(e.hp).is_equal(HUGE_HP - 3.0)


func test_the_factor_reads_the_full_bar_not_the_cap() -> void:
	# Q2: L1's own reserve 8 makes the cap 92; sanity 92 is x1.16, not x1.
	var sim := _sim()
	build(sim, RS)
	assert_float(sim.state.sanity_cap).is_equal(92.0)
	var e := put(sim, "cultist", 6.0)
	_set_sanity(sim, 92.0)
	var shot := _one_shot(sim)
	assert_float(shot.data["sanity_factor"]).is_equal_approx(1.16, 1e-9)
	assert_float(e.hp).is_equal_approx(HUGE_HP - 3.0 * 1.16, 1e-6)


func test_a_lit_resonator_scales_the_sanity_factor_by_0_7() -> void:
	var sim := _lit_sim()
	var t := build(sim, RS)
	var e := put(sim, "cultist", 6.0)
	_set_sanity(sim, 40.0)
	assert_float(sim.config.economy.beam.occult_power_mult).is_equal(0.7)
	var shot := _one_shot(sim)
	assert_bool(t.lit).is_true()
	assert_float(shot.data["sanity_factor"]).is_equal_approx(2.2, 1e-9)
	assert_float(e.hp).is_equal_approx(HUGE_HP - 3.0 * 2.2 * 0.7, 1e-6)


func test_madness_numbers_of_l1_pure_and_open() -> void:
	# §2.2 at sanity 0 with the madness enemy buff (x0.37 taken): L1 3 x 3 x 2, Pure 6 x 2
	# (not madness_affected: no x2, never astray), Open 4.5 x 5 x 2.
	var taken := 0.37
	for row: Array in [["", 6.66, true], ["a", 4.44, false], ["b", 16.65, true]]:
		var sim := _sim()
		assert_float(sim.config.sanity.madness.enemy_damage_taken_multiplier).is_equal(taken)
		if row[0] == "":
			build(sim, RS)
		else:
			_l3(sim, row[0])
		var e := put(sim, "cultist", 6.0)
		_madness(sim)
		var shot := _one_shot(sim)
		assert_bool(shot.data.has("astray")).override_failure_message(row[0]).is_equal(row[2])
		assert_array(shot.data["hits"]).is_equal([e.id])
		assert_float(HUGE_HP - e.hp).override_failure_message(row[0]) \
			.is_equal_approx(row[1], 1e-6)


func test_armor_is_ignored() -> void:
	var sim := _sim()
	_l1(sim).sanity_reserve = 0.0
	build(sim, RS)
	var e := put(sim, "shoggoth", 6.0)
	assert_float(e.def.armor).is_equal(5.0)
	_set_sanity(sim, sim.config.sanity.max_sanity)
	_one_shot(sim)
	assert_float(e.hp).is_equal(HUGE_HP - 3.0)


func test_a_rifle_shot_carries_no_beam_fields() -> void:
	var sim := _sim()
	build(sim, "rifleman")
	put(sim, "cultist", 6.0)
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_bool(shot.data.has("beam")).is_false()
	assert_bool(shot.data.has("sanity_factor")).is_false()


# --- the held target ------------------------------------------------------------------------

func test_the_beam_keeps_its_target_while_a_better_one_is_in_range() -> void:
	var sim := _sim()
	var t := build(sim, RS)
	assert_str(t.target_priority).is_equal("first")
	var a := put(sim, "cultist", 5.0)
	sim.drain_events()
	assert_int(_one_shot(sim).data["target"]).is_equal(a.id)
	var b := put(sim, "cultist", 9.0)  # ahead of a: "first" would pick it now
	for i in 3:
		assert_int(_next_shot(sim, t).data["target"]).is_equal(a.id)
	assert_float(b.hp).is_equal(HUGE_HP)
	# a leaves range: the beam re-picks.
	_move_to(a, 2.0)
	assert_int(_next_shot(sim, t).data["target"]).is_equal(b.id)
	_move_to(a, 9.5)  # back in range and ahead of b: b stays the target
	assert_int(_next_shot(sim, t).data["target"]).is_equal(b.id)


func test_the_beam_re_picks_when_its_target_dies() -> void:
	var sim := _sim()
	var t := build(sim, RS)
	var a := put(sim, "cultist", 5.0, HUGE_HP)
	sim.drain_events()
	assert_int(_one_shot(sim).data["target"]).is_equal(a.id)
	var b := put(sim, "cultist", 4.5)
	a.hp = 1.0
	var died := of_type(run(sim, t.cooldown_ticks), T.DIED)
	assert_array(ids_of(died)).is_equal([a.id])
	assert_int(_next_shot(sim, t).data["target"]).is_equal(b.id)


func test_a_target_priority_change_applies_at_the_next_shot() -> void:
	var sim := _sim()
	var t := build(sim, RS)
	var a := put(sim, "cultist", 5.0)
	var b := put(sim, "cultist", 4.5, HUGE_HP * 2.0)  # behind a, stronger
	sim.drain_events()
	assert_int(_one_shot(sim).data["target"]).is_equal(a.id)
	assert_int(_next_shot(sim, t).data["target"]).is_equal(a.id)
	assert_int(sim.set_target_priority(t.id, "strongest")).is_equal(Simulation.CommandResult.OK)
	assert_int(t.locked_id).is_equal(-1)
	assert_int(_next_shot(sim, t).data["target"]).is_equal(b.id)


# --- fakes ----------------------------------------------------------------------------------

func test_pure_reveals_the_fake_it_hits_then_lets_go_of_it() -> void:
	var sim := _sim()
	var t := _l3(sim, "a")
	var real := put(sim, "cultist", 6.0)
	var fake := _fake(sim, 8.0)  # ahead: "first" picks it
	sim.drain_events()
	var first := _one_shot(sim)
	assert_int(first.data["target"]).is_equal(fake.id)
	assert_array(first.data["hits"]).is_equal([fake.id])
	assert_bool(fake.revealed).is_true()
	assert_bool(real.revealed).is_false()
	for i in 3:
		assert_int(_next_shot(sim, t).data["target"]).is_equal(real.id)


func test_l1_l2_and_open_never_reveal_a_fake_they_hit() -> void:
	for lv: Array in [[0, ""], [1, ""], [TowerDef.LEVEL_COUNT, "b"]]:
		var sim := _sim()
		var t := build(sim, RS)
		t.level = lv[0]
		t.branch = lv[1]
		var fake := _fake(sim, 6.0)
		sim.drain_events()
		var shots := of_type(run(sim, 13), T.SHOT)
		assert_int(shots.size()).is_equal(3)
		for s in shots:
			assert_int(s.data["target"]).is_equal(fake.id)
		assert_bool(fake.revealed).override_failure_message(str(lv)).is_false()


func test_pure_is_no_reveal_aura_a_fake_it_does_not_hit_stays_hidden() -> void:
	var sim := _sim()
	var t := _l3(sim, "a")
	var real := put(sim, "cultist", 8.0)  # ahead: the beam's target
	var fake := _fake(sim, 6.0)  # inside range, behind
	sim.drain_events()
	var shots := of_type(run(sim, 13), T.SHOT)
	assert_int(shots.size()).is_equal(3)
	for s in shots:
		assert_array(s.data["hits"]).is_equal([real.id])
	assert_bool(fake.revealed).is_false()
	assert_float(t.stats().damage).is_greater(0.0)
