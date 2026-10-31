class_name MadnessBuffTest
extends WaveTestBase
## LT-23 §3 madness hostility (design note §6, pins 12-16): in MADNESS every live enemy,
## real and fake alike, on the map or spawned later, gets speed x enemy_speed_multiplier and
## damage taken x enemy_damage_taken_multiplier per tick, on top of an Elder Sign aura; the
## buff starts the step after MADNESS starts and is gone the step after it ends. Multipliers
## are read from config.

const T := SimEvent.Type
const S := SimState.SanityState
const SIGN := "elder_sign"
const RIFLE := "rifleman"
const FAR := 1.0  ## path cell 1: outside every aura of a tower at TOWER (7, 1)
const NEAR := 7.0  ## path cell 7: 1 cell from TOWER's centre


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _m(sim: Simulation) -> SanityConfig.Madness:
	return sim.config.sanity.madness


func _mods(e: SimEnemy) -> Array:
	return [snappedf(e.speed_mult, 0.0001), snappedf(e.damage_taken_mult, 0.0001)]


func _mad_sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 100000
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	return sim


# --- 12: the buff and its effect -----------------------------------------------------------

func test_shipped_multipliers_are_the_q8_values() -> void:
	var m := _m(tsim())
	assert_float(m.enemy_speed_multiplier).is_equal(1.2)
	assert_float(m.enemy_damage_taken_multiplier).is_equal(0.8)


func test_in_madness_every_live_enemy_gets_both_modifiers() -> void:
	var sim := _mad_sim()
	var m := _m(sim)
	var a := put(sim, "cultist", FAR)
	var b := put(sim, "deep_one", 3.0)
	sim.step()
	for e: SimEnemy in [a, b]:
		assert_array(_mods(e)).is_equal([snappedf(m.enemy_speed_multiplier, 0.0001),
			snappedf(m.enemy_damage_taken_multiplier, 0.0001)])


func test_outside_madness_both_modifiers_are_one_without_auras() -> void:
	var sim := tsim()
	for v: float in [sim.config.sanity.max_sanity, 50.0, 0.5]:
		_set_sanity(sim, v)
		var e := put(sim, "cultist", FAR)
		sim.step()
		assert_array(_mods(e)).override_failure_message(str(v)).is_equal([1.0, 1.0])


func test_a_buffed_enemy_moves_faster_and_takes_less_damage() -> void:
	var sim := _mad_sim()
	var m := _m(sim)
	var e := put(sim, "cultist", FAR)
	e.base_units_per_tick = 100
	var before := e.distance
	sim.step()
	assert_int(e.distance - before).is_equal(roundi(100 * m.enemy_speed_multiplier))
	var armor: float = sim.config.enemies["cultist"].armor
	var removed := sim.apply_damage(e.id, armor + 50.0, "test")
	assert_float(removed).is_equal_approx(50.0 * m.enemy_damage_taken_multiplier, 0.0001)


func test_multipliers_of_one_mean_no_buff() -> void:
	var sim := _mad_sim()
	_m(sim).enemy_speed_multiplier = 1.0
	_m(sim).enemy_damage_taken_multiplier = 1.0
	var e := put(sim, "cultist", FAR)
	sim.step()
	assert_array(_mods(e)).is_equal([1.0, 1.0])


# --- 13: enemies already on the map and new spawns ----------------------------------------

func test_the_buff_reaches_an_enemy_already_on_the_map_and_one_spawned_after() -> void:
	var sim := tsim()
	var m := _m(sim)
	var old := put(sim, "cultist", FAR)
	sim.step()
	assert_array(_mods(old)).is_equal([1.0, 1.0])
	_set_sanity(sim, 0.0)
	sim.step()
	var want := [snappedf(m.enemy_speed_multiplier, 0.0001),
		snappedf(m.enemy_damage_taken_multiplier, 0.0001)]
	assert_array(_mods(old)).is_equal(want)
	var late := put(sim, "cultist", 3.0)
	sim.step()
	assert_array(_mods(late)).is_equal(want)
	assert_array(_mods(old)).is_equal(want)  # every tick, not once


# --- 14: fakes are buffed like reals ------------------------------------------------------

func test_a_fake_and_a_real_of_one_def_have_identical_modifiers_in_madness() -> void:
	var sim := _mad_sim()
	var real := put(sim, "cultist", FAR)
	var fake := put(sim, "cultist", FAR, HUGE_HP, true)
	assert_bool(fake.is_fake).is_true()
	sim.step()
	assert_array(_mods(fake)).is_equal(_mods(real))
	assert_float(real.speed_mult).is_not_equal(1.0)
	assert_bool(sim._madness_buff_blocked(real)).is_false()
	assert_bool(sim._madness_buff_blocked(fake)).is_false()


# --- 15: stacking with an Elder Sign --------------------------------------------------------

func test_with_an_elder_sign_the_modifiers_are_the_product() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	build(sim, SIGN)
	_set_sanity(sim, 0.0)
	var m := _m(sim)
	var fx: Dictionary = sim.config.towers[SIGN].levels[0].effects
	var inside := put(sim, "cultist", NEAR)
	var outside := put(sim, "cultist", FAR)
	sim.step()
	assert_float(inside.speed_mult).is_equal_approx(
		(1.0 - fx["slow"]) * m.enemy_speed_multiplier, 0.0001)
	assert_float(inside.damage_taken_mult).is_equal_approx(
		fx["damage_taken_multiplier"] * m.enemy_damage_taken_multiplier, 0.0001)
	assert_float(outside.speed_mult).is_equal_approx(m.enemy_speed_multiplier, 0.0001)


# --- 16: entry and exit ticks -----------------------------------------------------------------

func test_the_step_after_a_command_that_enters_madness_has_the_buff() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var e := put(sim, "cultist", FAR)
	sim.step()
	assert_array(_mods(e)).is_equal([1.0, 1.0])
	sim.config.towers["necronomicon_reader"].levels[0].sanity_reserve = \
		sim.config.sanity.max_sanity
	build(sim, "necronomicon_reader", Vector2i(1, 1))
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	sim.step()
	assert_float(e.speed_mult).is_equal_approx(_m(sim).enemy_speed_multiplier, 0.0001)


func test_madness_reached_by_horror_buffs_from_the_next_tick() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	build(sim, RIFLE)
	var e := put(sim, "shoggoth", NEAR)
	var drain: float = sim.config.enemies["shoggoth"].horror_drain * SimTime.DT
	assert_float(drain).is_greater(0.0)
	_set_sanity(sim, drain / 2.0)
	sim.step()  # slot 6 drains to 0: MADNESS after slot 2 of this tick
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_array(_mods(e)).is_equal([1.0, 1.0])
	sim.step()
	assert_float(e.speed_mult).is_equal_approx(_m(sim).enemy_speed_multiplier, 0.0001)


func test_the_step_after_a_buyout_has_no_buff() -> void:
	var sim := _mad_sim()
	_m(sim).exit_rule = "buyout"
	var e := put(sim, "cultist", FAR)
	sim.step()
	assert_float(e.speed_mult).is_equal_approx(_m(sim).enemy_speed_multiplier, 0.0001)
	assert_int(sim.buy_sanity()).is_equal(Simulation.CommandResult.OK)
	assert_int(sim.state.sanity_state).is_not_equal(S.MADNESS)
	sim.step()
	assert_array(_mods(e)).is_equal([1.0, 1.0])
