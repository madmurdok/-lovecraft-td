class_name MissTest
extends TowerTestBase
## LT-12 §4 and owner decision Q3: from Fraying on, a mundane tower's shot misses with the
## threshold's miss_chance (one COMBAT roll per shot, none when the chance is 0); a miss
## spends the cooldown, deals nothing and reports SHOT {miss: true, hits: []} with `to` at
## the aim point. Occult towers never miss. Chances and stats are read from config.

const T := SimEvent.Type
const TARGET_CELLS := 7.0  ## parked target: route cell 7, next to the default tower
const SHOTS := 1000


## TowerTestBase map; `miss` overrides thresholds[state].miss_chance ({state: chance}).
func _sim(run_seed := SEED, miss := {}) -> Simulation:
	var r := load_edited(func(dir: String) -> void:
		edit(dir, MAP, func(root: Dictionary) -> void:
			root["width"] = ROWS[0].length()
			root["height"] = ROWS.size()
			root["rows"] = ROWS)
		for k: String in miss:
			edit(dir, "sanity.json", func(root: Dictionary) -> void:
				root["thresholds"][k]["miss_chance"] = miss[k]))
	assert_bool(r.ok).override_failure_message("config rejected:\n%s" % "\n".join(r.errors)) \
		.is_true()
	var sim := Simulation.new(r.config, run_seed)
	sim.state.gold = 1000000
	return sim


## A sanity value inside threshold state `key` (madness: its min; others: the middle).
func _set_state(sim: Simulation, key: String) -> void:
	var th := sim.config.sanity.thresholds
	var i := SanityConfig.STATES.find(key)
	var v: float = th[key].min_sanity
	if key != "madness":
		var hi: float = sim.config.sanity.max_sanity if i == 0 \
			else th[SanityConfig.STATES[i - 1]].min_sanity
		v = (v + hi) * 0.5
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	assert_int(sim.state.sanity_state).is_equal(i)


## Builds `def_id` on every buildable cell whose range covers `target`.
func _ring(sim: Simulation, def_id: String, target: SimEnemy) -> Array[SimTower]:
	var out: Array[SimTower] = []
	var rng: float = sim.config.towers[def_id].levels[0].range_cells
	for x in ROWS[0].length():
		var cell := Vector2i(x, 1)
		if sim.enemies_in_range(cell, rng).has(target):
			out.append(build(sim, def_id, cell))
	assert_int(out.size()).is_greater(0)
	return out


## Steps (re-setting the sanity state each tick, casts drain it) until `n` SHOTs.
func _shots(sim: Simulation, n: int, key: String) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	var guard := 0
	while out.size() < n and guard < 200000:
		_set_state(sim, key)
		sim.step()
		out.append_array(of_type(sim.drain_events(), T.SHOT))
		guard += 1
	return out


func _misses(shots: Array[SimEvent]) -> int:
	var n := 0
	for s in shots:
		if s.data["miss"]:
			n += 1
	return n


func _combat_state(sim: Simulation) -> int:
	return sim.rng(SimRng.Stream.COMBAT).state


# --- mundane at Fraying (behaviour 11) ------------------------------------------

func test_fraying_rifle_shots_miss_at_the_configured_rate() -> void:
	for run_seed in [1, 2, 3]:
		var sim := _sim(run_seed)
		_set_state(sim, "fraying")
		var p: float = sim.threshold().miss_chance
		assert_float(p).is_greater(0.0)
		var target := put(sim, "cultist", TARGET_CELLS)
		_ring(sim, "rifleman", target)
		sim.drain_events()
		var shots := _shots(sim, SHOTS, "fraying")
		var n := shots.size()
		var m := _misses(shots)
		var sd := sqrt(n * p * (1.0 - p))
		assert_float(absf(m - n * p)).override_failure_message(
			"seed %d: %d misses of %d shots, p %.3f" % [run_seed, m, n, p]) \
			.is_less_equal(4.0 * sd)


func test_a_miss_deals_nothing_and_aims_at_the_target() -> void:
	var sim := _sim()
	_set_state(sim, "fraying")
	var target := put(sim, "cultist", TARGET_CELLS)
	_ring(sim, "rifleman", target)
	sim.drain_events()
	var shots := _shots(sim, 200, "fraying")
	var dmg: float = sim.config.towers["rifleman"].levels[0].damage - target.def.armor
	var aim := target.route.position_at(target.distance)
	var hits := 0
	for s in shots:
		assert_int(s.data["target"]).is_equal(target.id)
		assert_that(s.data["to"]).is_equal(aim)
		if s.data["miss"]:
			assert_array(s.data["hits"]).is_empty()
		else:
			assert_array(s.data["hits"]).is_equal([target.id])
			hits += 1
	assert_int(_misses(shots)).is_greater(0)
	assert_float(target.hp).is_equal_approx(HUGE_HP - hits * dmg, 1e-3)


func test_a_miss_spends_the_cooldown() -> void:
	var sim := _sim()
	_set_state(sim, "fraying")
	var target := put(sim, "cultist", TARGET_CELLS)
	build(sim, "rifleman")
	sim.drain_events()
	var shots := _shots(sim, 100, "fraying")
	assert_int(_misses(shots)).is_greater(0)
	var gap := fire_ticks("rifleman")
	for i in range(1, shots.size()):
		assert_int(shots[i].tick - shots[i - 1].tick).is_equal(gap)
	assert_object(target).is_not_null()


func test_a_harpoon_miss_hits_nobody_on_its_line() -> void:
	var sim := _sim()
	_set_state(sim, "fraying")
	build(sim, "harpooner")
	# Geometry from harpoon_test: cells 9 and 10 lie on the line from the tower to cell 10.
	var on := put(sim, "cultist", 9.0)
	var primary := put(sim, "cultist", 10.0)
	sim.drain_events()
	var misses := 0
	var line_hits := 0
	for i in 400:
		var before := [on.hp, primary.hp]
		_set_state(sim, "fraying")
		sim.step()
		for s in of_type(sim.drain_events(), T.SHOT):
			assert_int(s.data["target"]).is_equal(primary.id)
			if s.data["miss"]:
				misses += 1
				assert_array(s.data["hits"]).is_empty()
				assert_array([on.hp, primary.hp]).is_equal(before)
			else:
				line_hits += 1
				assert_array(s.data["hits"]).contains_exactly_in_any_order([on.id, primary.id])
	assert_int(misses).is_greater(0)
	assert_int(line_hits).is_greater(0)


# --- no roll when the chance is 0 -----------------------------------------------

func _assert_no_miss_and_no_combat_draw(key: String, miss := {}) -> void:
	var sim := _sim(SEED, miss)
	_set_state(sim, key)
	assert_float(sim.threshold().miss_chance).is_equal(0.0)
	var target := put(sim, "cultist", TARGET_CELLS)
	_ring(sim, "rifleman", target)
	build(sim, "harpooner", Vector2i(12, 1))
	put(sim, "cultist", 12.0)
	sim.drain_events()
	var before := _combat_state(sim)
	var shots := _shots(sim, 300, key)
	assert_int(shots.size()).is_greater_equal(300)
	assert_int(_misses(shots)).is_equal(0)
	assert_int(_combat_state(sim)).is_equal(before)


func test_lucid_shots_never_miss_and_draw_nothing_from_combat() -> void:
	_assert_no_miss_and_no_combat_draw("lucid")


func test_whispers_shots_never_miss_and_draw_nothing_from_combat() -> void:
	_assert_no_miss_and_no_combat_draw("whispers")


func test_a_zero_miss_chance_at_fraying_draws_nothing() -> void:
	_assert_no_miss_and_no_combat_draw("fraying", {"fraying": 0.0})


func test_fraying_shots_do_draw_from_combat() -> void:
	# The observation above can see a draw: with the configured chance the state moves.
	var sim := _sim()
	_set_state(sim, "fraying")
	var target := put(sim, "cultist", TARGET_CELLS)
	build(sim, "rifleman")
	sim.drain_events()
	var before := _combat_state(sim)
	_shots(sim, 1, "fraying")
	assert_int(_combat_state(sim)).is_not_equal(before)
	assert_object(target).is_not_null()


# --- occult towers never miss (owner Q3) -----------------------------------------

## `real_only` (madness): every astray shot is a "real" one, so each cast has a hit to check.
func _assert_occult_never_misses(key: String, real_only := false) -> void:
	var sim := _sim()
	if real_only:
		var m := sim.config.sanity.madness
		m.shot_real = 1.0
		m.shot_fake = 0.0
		m.shot_empty = 0.0
	_set_state(sim, key)
	assert_float(sim.threshold().miss_chance).is_greater(0.0)
	var target := put(sim, "cultist", TARGET_CELLS)
	_ring(sim, "necronomicon_reader", target)
	sim.drain_events()
	var before := _combat_state(sim)
	var casts := _shots(sim, 60, key)
	assert_int(casts.size()).is_greater_equal(60)
	assert_int(_misses(casts)).is_equal(0)
	for c in casts:
		assert_array(c.data["hits"]).contains([target.id])
	assert_int(_combat_state(sim)).is_equal(before)


func test_necronomicon_never_misses_at_fraying() -> void:
	_assert_occult_never_misses("fraying")


func test_necronomicon_never_uses_the_miss_roll_in_madness() -> void:
	# LT-13: its shots go astray (shot_split) instead; the madness row's miss_chance is unused.
	_assert_occult_never_misses("madness", true)


func test_an_empty_astray_shot_is_not_a_miss_and_draws_no_combat_roll() -> void:
	var sim := _sim()
	var m := sim.config.sanity.madness
	m.shot_real = 0.0
	m.shot_fake = 0.0
	m.shot_empty = 1.0
	_set_state(sim, "madness")
	assert_float(sim.threshold().miss_chance).is_greater(0.0)
	var target := put(sim, "cultist", TARGET_CELLS)
	_ring(sim, "necronomicon_reader", target)
	sim.drain_events()
	var before := _combat_state(sim)
	var casts := _shots(sim, 20, "madness")
	assert_int(casts.size()).is_greater_equal(20)
	for c in casts:
		assert_bool(c.data["miss"]).is_false()
		assert_bool(c.data["astray"]).is_true()
		assert_array(c.data["hits"]).is_empty()
	assert_int(_misses(casts)).is_equal(0)
	assert_int(_combat_state(sim)).is_equal(before)
	assert_float(target.hp).is_equal(HUGE_HP)
