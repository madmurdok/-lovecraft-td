class_name DynamiteTest
extends TowerTestBase
## LT-47 Dynamite crew in the sim (docs/design/LT-46-tower-roster.md §2.2, §4 P2/P3, §6):
## the charge is thrown where the target will be after the fuse (Q5 "lead") and explodes
## there after fuse_seconds, hitting every live ground enemy within aoe_radius at that tick;
## an enemy pushed back or stopped meanwhile is outside; flyers are never targeted nor hit;
## a Fraying miss is a dud (no blast, cooldown spent); a lit crew never duds; branch b's
## blast makes foes bleed; blast kills are mundane kills, also after the tower is sold.
## Enemies are parked with `put` (speed 0) unless a test gives them a speed.

const T := SimEvent.Type
const DYN := "dynamite_crew"
const FAST_UPT := 1500  ## units per tick: 1.5 cells over a 1 s fuse, more than radius 1.0


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
	return sim.config.towers[DYN].levels[0]


## Builds the crew on `cell` and sets it to L3 `branch` (no gold, reserve or event).
func _l3(sim: Simulation, branch: String) -> SimTower:
	var t := build(sim, DYN)
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


func _fuse_ticks(l: TowerDef.Level) -> int:
	return SimTime.ticks(float(l.effects["fuse_seconds"]))


func _pos(e: SimEnemy) -> Vector2:
	return e.route.position_at(e.distance)


# --- lead point and fuse timing ---------------------------------------------------------

func test_the_charge_lands_where_the_target_walks_to_and_blasts_it_after_the_fuse() -> void:
	var sim := _sim()
	var l := _l1(sim)
	var fuse := _fuse_ticks(l)
	assert_int(fuse).is_equal(30)  # §2.2: fuse_seconds 1.0 at 30 ticks/s
	build(sim, DYN)
	var e := put(sim, "cultist", 6.0)
	e.base_units_per_tick = FAST_UPT
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_int(shot.tick).is_equal(1)
	assert_int(shot.data["target"]).is_equal(e.id)
	assert_bool(shot.data["fuse"]).is_true()
	assert_bool(shot.data["miss"]).is_false()
	assert_array(shot.data["hits"]).is_empty()
	assert_int(shot.data["detonate_tick"]).is_equal(1 + fuse)
	assert_float(shot.data["radius"]).is_equal(float(l.effects["aoe_radius"]))
	assert_int(shot.data["blast"]).is_greater(0)
	# Lead: thrown at distance + speed x fuse, not at where the target stands now.
	var lead: Vector2 = e.route.position_at(e.distance + FAST_UPT * fuse)
	assert_vector(shot.data["to"]).is_equal(lead)
	assert_float((shot.data["to"] as Vector2).distance_to(_pos(e))) \
		.is_greater(float(l.effects["aoe_radius"]))
	# Nothing explodes before detonate_tick.
	assert_array(of_type(run_to(sim, fuse), T.BLAST)).is_empty()
	assert_float(e.hp).is_equal(HUGE_HP)
	var ev := run(sim, 1)
	var blasts := of_type(ev, T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	var b := blasts[0]
	assert_int(b.tick).is_equal(1 + fuse)
	assert_int(b.id).is_equal(shot.data["blast"])
	assert_vector(b.data["at"]).is_equal(lead)
	assert_vector(_pos(e)).is_equal(lead)  # the target is at the centre
	assert_array(b.data["hits"]).is_equal([e.id])
	assert_str(b.data["def"]).is_equal(DYN)
	assert_float(e.hp).is_equal(HUGE_HP - l.damage)
	assert_array(sim.state.blasts).is_empty()


func test_a_parked_target_is_blasted_where_it_stands() -> void:
	var sim := _sim()
	build(sim, DYN)
	var e := put(sim, "cultist", 8.0)
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_vector(shot.data["to"]).is_equal(_pos(e))


func test_a_charge_with_a_sub_tick_fuse_still_waits_one_tick() -> void:
	var sim := _sim()
	_l1(sim).effects["fuse_seconds"] = 0.001
	build(sim, DYN)
	var e := put(sim, "cultist", 8.0)
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_int(shot.data["detonate_tick"]).is_equal(2)
	assert_float(e.hp).is_equal(HUGE_HP)
	var blasts := of_type(run(sim, 1), T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_int(blasts[0].tick).is_equal(2)


# --- who is hit is decided at the blast ---------------------------------------------------

func test_an_enemy_pushed_back_after_the_throw_is_outside_and_not_hit() -> void:
	var sim := _sim()
	var l := _l1(sim)
	build(sim, DYN)
	var a := put(sim, "cultist", 8.0)
	var b := put(sim, "cultist", 8.0)
	sim.drain_events()
	var shot := _one_shot(sim)
	var target := sim.enemy_by_id(shot.data["target"])
	var other := b if target == a else a
	sim._push_back(target, 2.0)
	assert_float(_pos(target).distance_to(shot.data["to"])) \
		.is_greater(float(l.effects["aoe_radius"]))
	var blasts := of_type(run_to(sim, 1 + _fuse_ticks(l)), T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_array(blasts[0].data["hits"]).is_equal([other.id])
	assert_float(target.hp).is_equal(HUGE_HP)
	assert_float(other.hp).is_equal(HUGE_HP - l.damage)


func test_an_enemy_that_stops_after_the_throw_falls_short_and_is_not_hit() -> void:
	var sim := _sim()
	var l := _l1(sim)
	build(sim, DYN)
	var e := put(sim, "cultist", 6.0)
	e.base_units_per_tick = FAST_UPT
	sim.drain_events()
	var shot := _one_shot(sim)
	e.base_units_per_tick = 0  # slowed to a halt after the throw
	var blasts := of_type(run_to(sim, 1 + _fuse_ticks(l)), T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_vector(blasts[0].data["at"]).is_equal(shot.data["to"])
	assert_array(blasts[0].data["hits"]).is_empty()
	assert_float(e.hp).is_equal(HUGE_HP)


func test_the_blast_hits_every_live_enemy_within_the_radius_boundary_included() -> void:
	var sim := _sim()
	var l := _l1(sim)
	assert_float(float(l.effects["aoe_radius"])).is_equal(1.0)  # §2.2 L1
	build(sim, DYN)
	var outside := put(sim, "cultist", 8.0)  # 2 cells from the blast
	var edge := put(sim, "cultist", 9.0)  # exactly 1.0 cell away
	var target := put(sim, "cultist", 10.0)  # "first": the one farthest along
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_int(shot.data["target"]).is_equal(target.id)
	var blasts := of_type(run_to(sim, 1 + _fuse_ticks(l)), T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_vector(blasts[0].data["at"]).is_equal(_pos(target))
	assert_array(blasts[0].data["hits"]).is_equal([edge.id, target.id])
	assert_float(outside.hp).is_equal(HUGE_HP)
	assert_float(edge.hp).is_equal(HUGE_HP - l.damage)


func test_a_fake_in_the_radius_is_hit() -> void:
	var sim := _sim()
	var l := _l1(sim)
	build(sim, DYN)
	var e := put(sim, "cultist", 8.0)
	var fake := put(sim, "cultist", 8.5, HUGE_HP, true)
	sim.drain_events()
	_one_shot(sim)
	var blasts := of_type(run_to(sim, 1 + _fuse_ticks(l)), T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_array(blasts[0].data["hits"]).contains_exactly_in_any_order([e.id, fake.id])


# --- ground only ----------------------------------------------------------------------------

func test_a_flyer_alone_in_range_is_never_targeted() -> void:
	var sim := _sim()
	var t := build(sim, DYN)
	assert_bool(t.def.ground_only()).is_true()
	var flyer := put(sim, "night_gaunt", 8.0)
	assert_bool(flyer.def.flying).is_true()
	sim.drain_events()
	var ev := run(sim, 100)
	assert_array(of_type(ev, T.SHOT)).is_empty()
	assert_array(of_type(ev, T.BLAST)).is_empty()
	assert_array(sim.state.blasts).is_empty()
	assert_float(flyer.hp).is_equal(HUGE_HP)


func test_a_flyer_on_the_blast_point_is_not_hit_and_not_the_target() -> void:
	var sim := _sim()
	var l := _l1(sim)
	build(sim, DYN)
	var flyer := put(sim, "night_gaunt", 8.0)  # lower id: wins a "first" tie if a candidate
	var walker := put(sim, "cultist", 8.0)
	assert_vector(_pos(flyer)).is_equal(_pos(walker))
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_int(shot.data["target"]).is_equal(walker.id)
	var blasts := of_type(run_to(sim, 1 + _fuse_ticks(l)), T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_array(blasts[0].data["hits"]).is_equal([walker.id])
	assert_float(flyer.hp).is_equal(HUGE_HP)
	assert_float(walker.hp).is_equal(HUGE_HP - l.damage)


# --- dud and lit ------------------------------------------------------------------------------

func test_a_fraying_miss_is_a_dud_no_blast_and_the_cooldown_is_spent() -> void:
	var sim := _sim()
	var l := _l1(sim)
	var t := build(sim, DYN)
	var e := put(sim, "cultist", 8.0)
	_fray_always_miss(sim)
	sim.drain_events()
	var shot := _one_shot(sim)
	assert_bool(shot.data["fuse"]).is_true()
	assert_bool(shot.data["miss"]).is_true()
	assert_int(shot.data["blast"]).is_equal(0)
	assert_array(shot.data["hits"]).is_empty()
	assert_array(sim.state.blasts).is_empty()
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(l.fire_interval))
	var ev := run_to(sim, 1 + _fuse_ticks(l) + 5)
	assert_array(of_type(ev, T.BLAST)).is_empty()
	assert_array(of_type(ev, T.SHOT)).is_empty()
	assert_float(e.hp).is_equal(HUGE_HP)


func test_a_lit_crew_never_duds_throws_faster_and_keeps_its_fuse() -> void:
	var sim := _lit_sim()
	var l := _l1(sim)
	var t := build(sim, DYN)
	put(sim, "cultist", 8.0)
	sim.threshold().miss_chance = 1.0
	sim.drain_events()
	var combat0 := sim.rng(SimRng.Stream.COMBAT).state
	var shot := _one_shot(sim)
	assert_bool(t.lit).is_true()
	assert_bool(shot.data["miss"]).is_false()
	assert_int(shot.data["blast"]).is_greater(0)
	assert_int(sim.rng(SimRng.Stream.COMBAT).state).is_equal(combat0)  # no miss roll
	var mult := sim.config.economy.beam.mundane_fire_interval_mult
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(l.fire_interval * mult))
	assert_int(shot.data["detonate_tick"]).is_equal(1 + _fuse_ticks(l))
	assert_int(of_type(run_to(sim, 1 + _fuse_ticks(l)), T.BLAST).size()).is_equal(1)


# --- branch b bleed ---------------------------------------------------------------------------

func test_shrapnel_blast_makes_its_hits_bleed_and_demolition_does_not() -> void:
	var sim := _sim()
	var b := sim.config.towers[DYN].branches["b"]
	assert_float(b.effects["bleed_dps"]).is_equal(8.0)  # §2.2
	assert_float(b.effects["bleed_seconds"]).is_equal(3.0)
	_l3(sim, "b")
	var e := put(sim, "cultist", 8.0)
	run_to(sim, 1 + _fuse_ticks(b) - 1)
	assert_bool(e.status.has("bleed_ticks")).is_false()  # bleed comes with the blast
	run(sim, 1)
	assert_float(e.hp).is_equal(HUGE_HP - b.damage)
	assert_int(e.status["bleed_ticks"]).is_equal(SimTime.ticks(3.0))
	assert_float(e.status["bleed_dps"]).is_equal(8.0)
	assert_str(e.status["bleed_source"]).is_equal(DYN)

	var sim2 := _sim()
	var a := sim2.config.towers[DYN].branches["a"]
	assert_bool(a.effects.has("bleed_dps")).is_false()
	_l3(sim2, "a")
	var e2 := put(sim2, "cultist", 8.0)
	run_to(sim2, 1 + _fuse_ticks(a))
	assert_float(e2.hp).is_equal(HUGE_HP - a.damage)
	assert_dict(e2.status).is_empty()


# --- kills ------------------------------------------------------------------------------------

func _assert_one_mundane_kill(sim: Simulation, ev: Array[SimEvent], e: SimEnemy, tick: int) -> void:
	var died := of_type(ev, T.DIED)
	assert_int(died.size()).is_equal(1)
	assert_int(died[0].id).is_equal(e.id)
	assert_int(died[0].tick).is_equal(tick)
	assert_str(died[0].data["source"]).is_equal(DYN)
	var kill := of_type(ev, T.SANITY_CHANGED).filter(
		func(s: SimEvent) -> bool: return s.data["reason"] == "mundane_kill")
	assert_int(kill.size()).is_equal(1)
	assert_float(kill[0].data["delta"]).is_equal(sim.config.sanity.regen_mundane_kill)


func test_a_blast_kill_is_a_mundane_kill_credited_to_the_crew() -> void:
	var sim := _sim()
	_set_sanity(sim, 80.0)
	var l := _l1(sim)
	build(sim, DYN)
	var e := put(sim, "cultist", 8.0, l.damage)
	sim.drain_events()
	var ev := run_to(sim, 1 + _fuse_ticks(l))
	_assert_one_mundane_kill(sim, ev, e, 1 + _fuse_ticks(l))


func test_a_charge_still_explodes_and_kills_after_its_tower_is_sold() -> void:
	var sim := _sim()
	_set_sanity(sim, 80.0)
	var l := _l1(sim)
	var t := build(sim, DYN)
	var e := put(sim, "cultist", 8.0, l.damage)
	sim.drain_events()
	_one_shot(sim)
	assert_int(sim.sell_tower(t.id)).is_equal(Simulation.CommandResult.OK)
	assert_object(sim.tower_by_id(t.id)).is_null()
	var ev := run_to(sim, 1 + _fuse_ticks(l))
	var blasts := of_type(ev, T.BLAST)
	assert_int(blasts.size()).is_equal(1)
	assert_int(blasts[0].data["tower"]).is_equal(t.id)
	assert_array(blasts[0].data["hits"]).is_equal([e.id])
	_assert_one_mundane_kill(sim, ev, e, 1 + _fuse_ticks(l))
