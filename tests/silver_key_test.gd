class_name SilverKeyTest
extends TowerTestBase
## LT-51 Silver Key Gate in the sim (docs/design/LT-46-tower-roster.md §2.2, §4 P5/P6/P9, §6;
## owner Q4 "HP cap per level"): every fire_interval the gate picks (by target_priority) up
## to banish_targets live enemies in range with max_hp <= banish_max_hp and no banish
## immunity, moves each back banish_cells along its own route (clamped at 0, flyers along
## their straight line, no render slide) and gives it banish_immune_seconds of immunity, a
## status of its own (the Chain pull's immunity neither blocks nor is blocked by it). No
## damage except Corrupted (after the move, armor applies). No candidate: no cast, the gate
## stays ready. Lit: banish_cells x occult_power_mult. MADNESS: Pure draws its picks on the
## seeded MADNESS stream. Elder Sign and Searchlight stay auras without targeting (P9).
## Tower centre (7.5, 1.5); an enemy `put` at c cells is at (c + 0.5, 0.5): inside L1 range 3
## iff c in [4.18, 9.82], inside range 3.5 (L2 and both branches) iff c in [3.65, 10.35].

const T := SimEvent.Type
const SK := "silver_key"
const SIGN := "elder_sign"
const SLT := "searchlight"
const HARP := "harpooner"
const U := SimTime.UNITS_PER_CELL
const IMMUNE_TICKS := 240  ## banish_immune_seconds 8 x 30 ticks
const DAGON_HP := 6000.0  ## GDD Dagon; no enemy def yet, so a cultist with Dagon's HP


# --- helpers ---------------------------------------------------------------------------

func _sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	return sim


func _lit_sim() -> Simulation:
	lit_beam = true
	var sim := tsim()
	lit_beam = false
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	return sim


## Builds the gate at `cell` and sets it to `level` (0 = L1, 1 = L2, 2 = L3 `branch`).
func _gate(sim: Simulation, level := 0, branch := "", cell := TOWER) -> SimTower:
	var t := build(sim, SK, cell)
	t.level = level
	t.branch = branch
	sim.drain_events()
	return t


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


func _madness(sim: Simulation, real := 1.0, fake := 0.0, empty := 0.0) -> void:
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	var m := sim.config.sanity.madness
	m.shot_real = real
	m.shot_fake = fake
	m.shot_empty = empty


func _cells(n: float) -> int:
	return roundi(n * U)


func _shots(ev: Array[SimEvent]) -> Array[SimEvent]:
	return of_type(ev, T.SHOT)


## Target ids of the SHOTs in `ev`, in event order.
func _targets(ev: Array[SimEvent]) -> Array:
	var out: Array = []
	for s in _shots(ev):
		out.append(s.data["target"])
	return out


# --- the rewind -----------------------------------------------------------------------------

func test_l1_moves_its_pick_back_four_cells_with_no_slide_and_no_damage() -> void:
	var sim := _sim()
	var t := _gate(sim)
	var e := put(sim, "cultist", 9.0, 400.0)
	var d0 := e.distance
	var from := e.route.position_at(d0)
	var ev := run(sim, 1)
	var shots := _shots(ev)
	assert_int(shots.size()).is_equal(1)
	assert_int(e.distance).is_equal(d0 - _cells(4.0))
	assert_int(e.prev_distance).is_equal(e.distance)
	assert_float(e.hp).is_equal(400.0)
	var d := shots[0].data
	assert_bool(d["banish"]).is_true()
	assert_int(d["target"]).is_equal(e.id)
	assert_array(d["hits"]).is_equal([e.id])
	assert_that(d["from"]).is_equal(from)
	assert_that(d["to"]).is_equal(e.route.position_at(d0 - _cells(4.0)))
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(6.0))


func test_the_banish_clamps_at_the_path_start() -> void:
	var sim := _sim()
	_gate(sim, 0, "", Vector2i(1, 1))
	var e := put(sim, "cultist", 1.0, 400.0)
	assert_int(_shots(run(sim, 1)).size()).is_equal(1)
	assert_int(e.distance).is_equal(0)
	assert_int(e.prev_distance).is_equal(0)


func test_l2_and_corrupted_move_five_and_eight_cells() -> void:
	for row: Array in [[1, "", 5.0], [2, "a", 5.0], [2, "b", 8.0]]:
		var sim := _sim()
		_gate(sim, row[0], row[1])
		var e := put(sim, "cultist", 10.0, 400.0)
		var d0 := e.distance
		run(sim, 1)
		assert_int(e.distance).override_failure_message("level %s%s" % [row[0], row[1]]) \
			.is_equal(d0 - _cells(row[2]))


func test_a_lit_gate_moves_banish_cells_times_the_occult_power_mult() -> void:
	var sim := _lit_sim()
	var pm := sim.config.economy.beam.occult_power_mult
	assert_float(pm).is_equal(0.7)
	var t := _gate(sim)
	var e := put(sim, "cultist", 9.0, 400.0)
	var d0 := e.distance
	run(sim, 1)
	assert_bool(t.lit).is_true()
	assert_int(e.distance).is_equal(d0 - _cells(4.0 * pm))


## An L-shaped path: the flyer's straight S -> L line is not the ground path.
const L_ROWS := [
	"S......",
	"#......",
	"#......",
	"######L",
]


func test_a_flyer_is_banished_back_along_its_straight_line() -> void:
	var sim := Simulation.new(make_config(L_ROWS), SEED)
	sim.state.gold = 1000000
	_gate(sim, 0, "", Vector2i(2, 1))
	var f := put(sim, "night_gaunt", 5.0, 165.0)
	assert_bool(f.def.flying).is_true()
	var d0 := f.distance
	assert_int(_shots(run(sim, 1)).size()).is_equal(1)
	assert_int(f.distance).is_equal(d0 - _cells(4.0))
	var p := f.route.position_at(f.distance)
	var s := Vector2(0.5, 0.5)
	var dir := Vector2(6.5, 3.5) - s
	assert_float(absf((Vector2(p) - s).cross(dir))).is_less(1e-3)
	assert_float(p.x).is_greater(0.6)  # off the ground path's first column


# --- no candidate, cooldown -------------------------------------------------------------------

func test_with_no_banishable_enemy_there_is_no_cast_and_the_gate_stays_ready() -> void:
	var sim := _sim()
	var t := _gate(sim)
	var shog := put(sim, "shoggoth", 6.0, 3600.0)
	var d0 := shog.distance
	assert_array(_shots(run(sim, 1))).is_empty()
	assert_int(t.cooldown_ticks).is_equal(0)
	assert_int(shog.distance).is_equal(d0)
	var e := put(sim, "cultist", 8.0, 400.0)
	var ev := run(sim, 1)
	assert_array(_targets(ev)).is_equal([e.id])
	assert_array(shot_ticks(ev)).is_equal([2])
	assert_int(shog.distance).is_equal(d0)


# --- HP cap per level (Q4) ----------------------------------------------------------------------

## Whether `level`/`branch` banishes an enemy of max_hp `max_hp` (hp `hp`, -1 = max_hp).
func _banishes(level: int, branch: String, def_id: String, max_hp: float, hp := -1.0) -> bool:
	var sim := _sim()
	_gate(sim, level, branch)
	var e := put(sim, def_id, 8.0, max_hp)
	if hp >= 0.0:
		e.hp = hp
	var d0 := e.distance
	var n := _shots(run(sim, 1)).size()
	assert_bool((n == 1) == (e.distance < d0)).is_true()
	return n == 1


func test_l1_l2_and_pure_banish_up_to_500_max_hp_inclusive() -> void:
	for lv: Array in [[0, ""], [1, ""], [2, "a"]]:
		var tag := "level %s%s" % lv
		assert_bool(_banishes(lv[0], lv[1], "cultist", 500.0)).override_failure_message(tag) \
			.is_true()
		assert_bool(_banishes(lv[0], lv[1], "cultist", 501.0)).override_failure_message(tag) \
			.is_false()
		assert_bool(_banishes(lv[0], lv[1], "shoggoth", 3600.0)).override_failure_message(tag) \
			.is_false()


func test_the_cap_reads_max_hp_not_current_hp() -> void:
	# A wounded big enemy (hp 100 of 600) is still too big for L1.
	assert_bool(_banishes(0, "", "cultist", 600.0, 100.0)).is_false()


func test_corrupted_banishes_up_to_4000_max_hp_and_never_dagon() -> void:
	assert_bool(_banishes(2, "b", "shoggoth", 3600.0)).is_true()
	assert_bool(_banishes(2, "b", "cultist", 4000.0)).is_true()
	assert_bool(_banishes(2, "b", "cultist", 4001.0)).is_false()
	assert_bool(_banishes(2, "b", "cultist", DAGON_HP)).is_false()


# --- immunity ---------------------------------------------------------------------------------

func test_banish_immunity_holds_240_ticks_then_the_gate_banishes_again() -> void:
	var sim := _sim()
	var t := _gate(sim)
	var e := put(sim, "cultist", 9.0, 400.0)
	var d0 := e.distance
	var first := run(sim, 1)
	assert_int(_shots(first).size()).is_equal(1)
	assert_int(e.status["banish_immune_ticks"]).is_equal(IMMUNE_TICKS)
	assert_bool(e.status.has("pull_immune_ticks")).is_false()
	# Ready again at tick 181, enemy in range (5 cells), but immune until tick 241.
	var ev := run_to(sim, IMMUNE_TICKS + 1)
	assert_array(shot_ticks(ev)).is_equal([IMMUNE_TICKS + 1])
	assert_int(e.distance).is_equal(d0 - 2 * _cells(4.0))
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(6.0))


func test_banish_immunity_counts_down_and_is_erased() -> void:
	var sim := _sim()
	var t := _gate(sim)
	var e := put(sim, "cultist", 9.0, 400.0)
	run(sim, 1)
	t.cooldown_ticks = 1000000
	run_to(sim, 31)
	assert_int(e.status["banish_immune_ticks"]).is_equal(IMMUNE_TICKS - 30)
	run_to(sim, IMMUNE_TICKS + 1)
	assert_bool(e.status.has("banish_immune_ticks")).is_false()


func test_two_gates_in_one_tick_banish_an_enemy_once() -> void:
	var sim := _sim()
	_gate(sim)
	var t2 := _gate(sim, 0, "", Vector2i(8, 1))
	var e := put(sim, "cultist", 9.0, 400.0)
	var d0 := e.distance
	var ev := run(sim, 1)
	assert_int(_shots(ev).size()).is_equal(1)
	assert_int(e.distance).is_equal(d0 - _cells(4.0))
	assert_int(t2.cooldown_ticks).is_equal(0)  # no candidate: stays ready


func test_pull_immunity_does_not_block_a_banish() -> void:
	var sim := _sim()
	_gate(sim)
	var e := put(sim, "cultist", 9.0, 400.0)
	e.status["pull_immune_ticks"] = 1000
	var d0 := e.distance
	assert_array(_targets(run(sim, 1))).is_equal([e.id])
	assert_int(e.distance).is_equal(d0 - _cells(4.0))


func test_banish_immunity_does_not_block_a_chain_pull() -> void:
	var sim := _sim()
	_l3(sim, HARP, "b")
	var e := put(sim, "cultist", 10.0, 400.0)
	e.status["banish_immune_ticks"] = 1000
	var shots := _shots(run(sim, 1))
	assert_int(shots.size()).is_equal(1)
	assert_array(shots[0].data["pulled"]).is_equal([e.id])


# --- damage ------------------------------------------------------------------------------------

func test_only_corrupted_deals_damage_after_the_move_through_armor() -> void:
	for lv: Array in [[0, ""], [1, ""], [2, "a"]]:
		var sim := _sim()
		_gate(sim, lv[0], lv[1])
		var e := put(sim, "cultist", 8.0, 400.0)
		run(sim, 1)
		assert_float(e.hp).override_failure_message("level %s%s" % lv).is_equal(400.0)
	var c := _sim()
	_gate(c, 2, "b")
	var shog := put(c, "shoggoth", 9.0, 3600.0)
	assert_float(shog.def.armor).is_equal(5.0)
	run(c, 1)
	assert_float(shog.hp).is_equal_approx(3600.0 - (60.0 - 5.0), 1e-6)


func test_a_corrupted_kill_moves_first_shot_before_died() -> void:
	var sim := _sim()
	_gate(sim, 2, "b")
	var e := put(sim, "cultist", 9.0, 50.0)
	var d0 := e.distance
	var ev := run(sim, 1)
	var kinds: Array = []
	for x in ev:
		if x.type == T.SHOT or x.type == T.DIED:
			kinds.append(x.type)
	assert_array(kinds).is_equal([T.SHOT, T.DIED])
	assert_bool(e.is_live()).is_false()
	var shot := _shots(ev)[0]
	assert_that(shot.data["to"]).is_equal(e.route.position_at(d0 - _cells(8.0)))


# --- Pure: three at once -------------------------------------------------------------------------

func test_pure_banishes_the_top_three_by_priority_in_one_cast() -> void:
	var sim := _sim()
	_gate(sim, 2, "a")
	var es: Array[SimEnemy] = []
	for c: float in [5.0, 6.0, 7.0, 8.0]:
		es.append(put(sim, "cultist", c, 400.0))
	var d0: Array[int] = []
	for e in es:
		d0.append(e.distance)
	var ev := run(sim, 1)
	assert_array(_targets(ev)).contains_exactly_in_any_order([es[1].id, es[2].id, es[3].id])
	assert_int(es[0].distance).is_equal(d0[0])
	for i in [1, 2, 3]:
		assert_int(es[i].distance).is_equal(d0[i] - _cells(5.0))


func test_pure_with_two_candidates_banishes_two() -> void:
	var sim := _sim()
	_gate(sim, 2, "a")
	var a := put(sim, "cultist", 6.0, 400.0)
	var b := put(sim, "cultist", 8.0, 400.0)
	put(sim, "shoggoth", 7.0, 3600.0)  # in range, over the cap
	assert_array(_targets(run(sim, 1))).contains_exactly_in_any_order([a.id, b.id])


# --- madness -------------------------------------------------------------------------------------

## Pure in MADNESS (every cast "real") with six cultists in range: the target lists of three
## casts, each cast with the board reset (distances and immunity).
func _pure_madness_casts(run_seed: int) -> Array:
	var sim := Simulation.new(tconfig(), run_seed)
	sim.state.gold = 1000000
	var t := _gate(sim, 2, "a")
	var es: Array[SimEnemy] = []
	for c: float in [4.5, 5.5, 6.5, 7.5, 8.5, 9.5]:
		es.append(put(sim, "cultist", c, 400.0))
	var d0: Array[int] = []
	for e in es:
		d0.append(e.distance)
	_madness(sim)
	var casts: Array = []
	for i in 3:
		var ev := run(sim, maxi(1, t.cooldown_ticks))
		var shots := _shots(ev)
		casts.append(_targets(ev))
		for s in shots:
			assert_bool(s.data.get("astray", false)).is_true()
		for j in es.size():
			es[j].distance = d0[j]
			es[j].prev_distance = d0[j]
			es[j].status.erase("banish_immune_ticks")
	var ids: Array = []
	for e in es:
		ids.append(e.id)
	casts.append(ids)
	return casts


func test_pure_in_madness_picks_three_distinct_in_range_and_repeats_for_a_seed() -> void:
	var a := _pure_madness_casts(SEED)
	var b := _pure_madness_casts(SEED)
	var ids: Array = a[3]
	for i in 3:
		var picks: Array = a[i]
		assert_int(picks.size()).is_equal(3)
		var seen := {}
		for id in picks:
			assert_bool(ids.has(id)).is_true()
			seen[id] = true
		assert_int(seen.size()).is_equal(3)
	assert_array(b.slice(0, 3)).is_equal(a.slice(0, 3))


func test_an_empty_madness_roll_moves_nothing_and_spends_the_cooldown() -> void:
	var sim := _sim()
	var t := _gate(sim)
	var e := put(sim, "cultist", 8.0, 400.0)
	var d0 := e.distance
	_madness(sim, 0.0, 0.0, 1.0)
	assert_array(_shots(run(sim, 1))).is_empty()
	assert_int(e.distance).is_equal(d0)
	assert_int(t.cooldown_ticks).is_equal(SimTime.ticks(6.0))


# --- P9: support towers stay auras --------------------------------------------------------------

func test_the_gate_has_targeting_and_elder_sign_and_searchlight_do_not() -> void:
	var sim := _sim()
	var g := _gate(sim)
	assert_bool(sim.has_targeting(g)).is_true()
	for br: String in ["a", "b"]:
		g.level = TowerDef.LEVEL_COUNT
		g.branch = br
		assert_bool(sim.has_targeting(g)).is_true()
	var sign := build(sim, SIGN, Vector2i(5, 1))
	var sl := build(sim, SLT, Vector2i(3, 1))
	for t: SimTower in [sign, sl]:
		for lv: Array in [[0, ""], [1, ""], [2, "a"], [2, "b"]]:
			t.level = lv[0]
			t.branch = lv[1]
			assert_bool(sim.has_targeting(t)) \
				.override_failure_message("%s %s%s" % [t.def.id, lv[0], lv[1]]).is_false()


func test_elder_sign_and_searchlight_still_apply_their_auras_beside_a_gate() -> void:
	var sim := _sim()
	_gate(sim)
	build(sim, SLT, Vector2i(3, 1))  # centre (3.5, 1.5), radius 3
	build(sim, SIGN, Vector2i(11, 1))  # centre (11.5, 1.5)
	var fake := put(sim, "cultist", 2.0, HUGE_HP, true)
	var near_sign := put(sim, "shoggoth", 11.0, 3600.0)  # out of the gate's reach and cap
	sim.drain_events()
	run(sim, 1)
	assert_bool(fake.revealed).is_true()
	assert_float(fake.speed_mult).is_less(1.0)
	var es: TowerDef.Level = sim.config.towers[SIGN].levels[0]
	assert_float(near_sign.speed_mult).is_equal_approx(1.0 - float(es.effects["slow"]), 1e-9)
