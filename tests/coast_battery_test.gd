class_name CoastBatteryTest
extends TowerTestBase
## LT-48 Coast battery in the sim (docs/design/LT-46-tower-roster.md §2.2, §4 P4/P7, §6):
## enemies whose cell-centre distance is strictly less than `min_range` are not candidates
## (the battery fires past them, or holds fire with its cooldown at 0); it hits flyers (Q6);
## an `ignore_armor` hit skips armor (base and bonus) but keeps damage_taken_mult; AP shells
## ignore armor, HE shells splash onto enemies inside the dead zone too; a fused blast with
## ignore_armor skips armor; a Fraying miss spends the 3 s cooldown, a lit battery never
## misses and fires x0.8; a kill is a mundane kill.
## Tower centre (7.5, 1.5); an enemy `put` at c cells is at (c + 0.5, 0.5), so its distance
## from the tower is sqrt((c - 7)^2 + 1): c = 8 -> 1.41 (inside 2), c = 9 -> 2.24, c = 3 -> 4.12.

const T := SimEvent.Type
const CB := "coast_battery"
const DYN := "dynamite_crew"


# --- helpers ---------------------------------------------------------------------------

func _sim(enemy_edits := {}) -> Simulation:
	var sim := tsim(enemy_edits)
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
	return sim.config.towers[CB].levels[0]


## Builds the battery on the default cell and sets it to L3 `branch` (no gold or event).
func _l3(sim: Simulation, branch: String) -> SimTower:
	var t := build(sim, CB)
	t.level = TowerDef.LEVEL_COUNT
	t.branch = branch
	sim.drain_events()
	return t


## A sanity value in the middle of Fraying, where every mundane shot misses.
func _fray_always_miss(sim: Simulation) -> void:
	var th := sim.config.sanity.thresholds
	var v := (float(th["fraying"].min_sanity) + float(th["whispers"].min_sanity)) * 0.5
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.FRAYING)
	sim.threshold().miss_chance = 1.0


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)


## Steps once; asserts exactly one SHOT that tick and returns it.
func _one_shot(sim: Simulation) -> SimEvent:
	var shots := of_type(run(sim, 1), T.SHOT)
	assert_int(shots.size()).is_equal(1)
	return shots[0]


func _dist(t: SimTower, e: SimEnemy) -> float:
	return t.centre().distance_to(e.route.position_at(e.distance))


# --- dead zone ----------------------------------------------------------------------------

func test_an_enemy_exactly_at_min_range_is_a_candidate_and_one_inside_is_not() -> void:
	# Boundary: a min_range edit that lands exactly on an enemy's cell-centre distance.
	var sim := _sim()
	_l1(sim).min_range = 1.0
	var t := build(sim, CB)
	var edge := put(sim, "cultist", 7.0)
	assert_float(_dist(t, edge)).is_equal(1.0)
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_int(shot.data["target"]).is_equal(edge.id)
	assert_float(edge.hp).is_equal(HUGE_HP - _l1(sim).damage)

	# Shipped min_range 2: an enemy at 1.41 is not a candidate.
	var sim2 := _sim()
	assert_float(_l1(sim2).min_range).is_equal(2.0)
	var t2 := build(sim2, CB)
	var inside := put(sim2, "cultist", 8.0)
	assert_float(_dist(t2, inside)).is_less(2.0)
	sim2.drain_events()
	assert_array(of_type(run(sim2, 5), T.SHOT)).is_empty()
	assert_float(inside.hp).is_equal(HUGE_HP)


func test_the_battery_fires_past_an_enemy_inside_its_dead_zone_under_every_priority() -> void:
	for mode: String in SimTower.TARGET_PRIORITIES:
		var sim := _sim()
		var t := build(sim, CB)
		t.target_priority = mode
		# Lower id, farther along, more hp and moving: the inside one wins every mode
		# if it were a candidate.
		var inside := put(sim, "cultist", 8.0, HUGE_HP * 2.0)
		inside.base_units_per_tick = 10
		var outside := put(sim, "cultist", 3.0)
		sim.drain_events()
		var shot := _one_shot(sim)
		assert_int(shot.data["target"]).override_failure_message(mode).is_equal(outside.id)
		assert_array(shot.data["hits"]).override_failure_message(mode).is_equal([outside.id])
		assert_float(inside.hp).override_failure_message(mode).is_equal(HUGE_HP * 2.0)
		assert_float(outside.hp).override_failure_message(mode) \
			.is_equal(HUGE_HP - _l1(sim).damage)


func test_with_only_enemies_inside_it_holds_fire_and_fires_the_tick_one_leaves() -> void:
	var sim := _sim()
	var t := build(sim, CB)
	var e := put(sim, "cultist", 8.0)
	put(sim, "cultist", 6.5)
	sim.drain_events()
	var ev := run(sim, 120)  # longer than the 90-tick interval
	assert_array(of_type(ev, T.SHOT)).is_empty()
	assert_int(t.cooldown_ticks).is_equal(0)
	assert_float(e.hp).is_equal(HUGE_HP)
	# One steps out of the dead zone (to 2.24 cells): shot on the very next tick.
	e.distance = roundi(9.0 * SimTime.UNITS_PER_CELL)
	e.prev_distance = e.distance
	var shot := _one_shot(sim)
	assert_int(shot.tick).is_equal(121)
	assert_int(shot.data["target"]).is_equal(e.id)
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(_l1(sim).fire_interval))


# --- flyers -----------------------------------------------------------------------------------

func test_the_battery_hits_a_flyer_outside_its_dead_zone() -> void:
	var sim := _sim()
	var t := build(sim, CB)
	assert_bool(t.def.ground_only()).is_false()
	var flyer := put(sim, "night_gaunt", 3.0)
	assert_bool(flyer.def.flying).is_true()
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_int(shot.data["target"]).is_equal(flyer.id)
	assert_float(flyer.hp).is_equal(HUGE_HP - _l1(sim).damage)  # night_gaunt armor 0


# --- armor ----------------------------------------------------------------------------------

func test_apply_damage_ignore_armor_skips_base_and_bonus_armor_but_keeps_the_multiplier() -> void:
	var sim := _sim()
	var a := put(sim, "shoggoth", 3.0)
	var b := put(sim, "shoggoth", 4.0)
	for e: SimEnemy in [a, b]:
		assert_float(e.def.armor).is_equal(5.0)
		e.armor_bonus = 3.0
		e.damage_taken_mult = 1.5
	assert_float(sim.apply_damage(a.id, 100.0, "x", true)).is_equal(150.0)
	assert_float(a.hp).is_equal(HUGE_HP - 150.0)
	assert_float(sim.apply_damage(b.id, 100.0, "x")).is_equal((100.0 - 8.0) * 1.5)
	assert_float(b.hp).is_equal(HUGE_HP - 138.0)


func test_l1_shell_loses_armor_and_ap_shell_ignores_it_on_a_shoggoth() -> void:
	var sim := _sim()
	build(sim, CB)
	var e := put(sim, "shoggoth", 3.0)
	sim.drain_events()
	_one_shot(sim)
	assert_float(e.hp).is_equal(HUGE_HP - 65.0)  # §2.2: 70 - armor 5

	var sim2 := _sim()
	var a: TowerDef.Level = sim2.config.towers[CB].branches["a"]
	assert_float(a.damage).is_equal(140.0)
	_l3(sim2, "a")
	var e2 := put(sim2, "shoggoth", 3.0)
	_one_shot(sim2)
	assert_float(e2.hp).is_equal(HUGE_HP - 140.0)


func test_a_fused_blast_from_an_ignore_armor_level_skips_armor() -> void:
	var sim := _sim()
	var l: TowerDef.Level = sim.config.towers[DYN].levels[0]
	l.effects["ignore_armor"] = 1.0
	build(sim, DYN)
	var e := put(sim, "shoggoth", 8.0)
	sim.drain_events()
	var fuse := SimTime.ticks(float(l.effects["fuse_seconds"]))
	var blasts := of_type(run_to(sim, 1 + fuse), T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_array(blasts[0].data["hits"]).is_equal([e.id])
	assert_float(e.hp).is_equal(HUGE_HP - l.damage)


# --- HE splash --------------------------------------------------------------------------------

func test_he_shell_splashes_an_enemy_standing_inside_the_dead_zone() -> void:
	var sim := _sim()
	var b: TowerDef.Level = sim.config.towers[CB].branches["b"]
	assert_float(float(b.effects["aoe_radius"])).is_equal(1.0)
	var t := _l3(sim, "b")
	var target := put(sim, "cultist", 9.0)  # 2.24 cells: a candidate, "first"
	var near := put(sim, "cultist", 8.5)  # 1.80 cells: inside the dead zone, 0.5 off target
	var far := put(sim, "cultist", 3.0)  # 2+ cells off the target: not splashed
	assert_float(_dist(t, near)).is_less(2.0)
	var shot := _one_shot(sim)
	assert_int(shot.data["target"]).is_equal(target.id)
	assert_array(shot.data["hits"]).contains_exactly_in_any_order([target.id, near.id])
	assert_float(target.hp).is_equal(HUGE_HP - b.damage)
	assert_float(near.hp).is_equal(HUGE_HP - b.damage)
	assert_float(far.hp).is_equal(HUGE_HP)


# --- miss and lit -----------------------------------------------------------------------------

func test_a_fraying_miss_spends_the_three_second_cooldown() -> void:
	var sim := _sim()
	var l := _l1(sim)
	assert_float(l.fire_interval).is_equal(3.0)
	var t := build(sim, CB)
	var e := put(sim, "cultist", 3.0)
	_fray_always_miss(sim)
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_bool(shot.data["miss"]).is_true()
	assert_float(e.hp).is_equal(HUGE_HP)
	assert_int(t.cooldown_ticks).is_equal(90)
	assert_array(of_type(run(sim, 89), T.SHOT)).is_empty()
	assert_int(of_type(run(sim, 1), T.SHOT).size()).is_equal(1)


func test_a_lit_battery_never_misses_and_fires_at_x0_8() -> void:
	var sim := _lit_sim()
	var l := _l1(sim)
	var t := build(sim, CB)
	var e := put(sim, "cultist", 3.0)
	sim.threshold().miss_chance = 1.0
	sim.drain_events()
	var combat0 := sim.rng(SimRng.Stream.COMBAT).state
	var shot := _one_shot(sim)
	assert_bool(t.lit).is_true()
	assert_bool(shot.data["miss"]).is_false()
	assert_float(e.hp).is_equal(HUGE_HP - l.damage)
	assert_int(sim.rng(SimRng.Stream.COMBAT).state).is_equal(combat0)  # no miss roll
	var mult := sim.config.economy.beam.mundane_fire_interval_mult
	assert_float(mult).is_equal(0.8)
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(l.fire_interval * mult))


# --- kills ------------------------------------------------------------------------------------

func test_a_battery_kill_is_a_mundane_kill() -> void:
	var sim := _sim()
	_set_sanity(sim, 80.0)
	build(sim, CB)
	var e := put(sim, "cultist", 3.0, _l1(sim).damage)
	sim.drain_events()
	var ev := run(sim, 1)
	var died := of_type(ev, T.DIED)
	assert_int(died.size()).is_equal(1)
	assert_int(died[0].id).is_equal(e.id)
	assert_str(died[0].data["source"]).is_equal(CB)
	var kill := of_type(ev, T.SANITY_CHANGED).filter(
		func(s: SimEvent) -> bool: return s.data["reason"] == "mundane_kill")
	assert_int(kill.size()).is_equal(1)
	assert_float(kill[0].data["delta"]).is_equal(sim.config.sanity.regen_mundane_kill)
	assert_float(sim.config.sanity.regen_mundane_kill).is_equal(0.5)
