class_name HallucinationTest
extends WaveTestBase
## LT-12 hallucinations (design note §2, §3, §5 and the owner decisions): the fake scheduler
## per sanity threshold, candidates from the current wave's unfired groups, fake packs on
## SANITY, dissolve at the lighthouse and at wave end, no economy or sanity effect, events
## that never tell a fake apart. Intervals, pack sizes and rewards are read from config;
## waves are test fixtures long enough for several fakes (today's waves.json is too short).

const T := SimEvent.Type
const LIGHTHOUSE_HP := 100000  ## fixture: every real of a long wave may leak
const SPACING := 1.0  ## fixture: seconds between the spawns of a long group


## Steps a sim and keeps every event plus the enemies it spawned (fake / real, in order).
class Rec:
	var sim: Simulation
	var events: Array[SimEvent] = []
	var fakes: Array[SimEnemy] = []
	var reals: Array[SimEnemy] = []
	var _counts := {}

	func _init(s: Simulation) -> void:
		sim = s
		_take(sim.drain_events())

	func step(n := 1) -> void:
		for i in n:
			sim.step()
			_take(sim.drain_events())

	## Steps until the `nth` event of `type` (counting from the start); returns it.
	func until(type: SimEvent.Type, nth := 1, limit := 100000) -> SimEvent:
		var guard := 0
		while int(_counts.get(type, 0)) < nth and guard < limit:
			step()
			guard += 1
		var seen := 0
		for e in events:
			if e.type == type:
				seen += 1
				if seen == nth:
					return e
		return null

	func _take(ev: Array[SimEvent]) -> void:
		for e in ev:
			events.append(e)
			_counts[e.type] = int(_counts.get(e.type, 0)) + 1
			if e.type == SimEvent.Type.SPAWNED:
				var en := sim.enemy_by_id(e.id)
				if en.is_fake:
					fakes.append(en)
				else:
					reals.append(en)


## A scheduler that never spawns: the "without the system" arm.
class NoFakes extends HallucinationSystem:
	func tick(_sim: Simulation, _spawner: SimSpawner) -> void:
		pass


# --- fixtures -----------------------------------------------------------------

## A sanity value inside threshold state `key` (madness: its min; others: the middle).
func _sanity_in(sim: Simulation, key: String) -> float:
	var th := sim.config.sanity.thresholds
	var i := SanityConfig.STATES.find(key)
	var v: float = th[key].min_sanity
	if key != "madness":
		var hi: float = sim.config.sanity.max_sanity if i == 0 \
			else th[SanityConfig.STATES[i - 1]].min_sanity
		v = (v + hi) * 0.5
	assert_int(sim.sanity_state_for(v)).is_equal(i)
	return v


func _set_state(sim: Simulation, key: String) -> void:
	sim.state.sanity = _sanity_in(sim, key)
	sim.state.sanity_state = sim.sanity_state_for(sim.state.sanity)


func _interval(sim: Simulation, key: String) -> int:
	return SimTime.ticks(sim.config.sanity.thresholds[key].fake_spawn_interval)


## Spawn events per long group: its last spawn comes after 3.5 of the longest fake interval.
func _long_count() -> int:
	var longest := 0.0
	for k: String in real_config().sanity.thresholds:
		longest = maxf(longest, real_config().sanity.thresholds[k].fake_spawn_interval)
	return ceili(3.5 * longest / SPACING) + 1


## Wave tick of the last spawn of a long group.
func _long_last() -> int:
	return (_long_count() - 1) * SimTime.ticks(SPACING)


func _long_sim(enemy := "cultist", waves := 1, run_seed := SEED) -> Simulation:
	var ws: Array = []
	for i in waves:
		ws.append([group(enemy, _long_count(), SPACING)])
	return wsim(ws, 1, LIGHTHOUSE_HP, run_seed)


## k * interval for k >= 1 while below `last` (fakes stop once the groups are exhausted).
func _multiples(interval: int, last: int) -> Array[int]:
	var out: Array[int] = []
	var t := interval
	while t < last:
		out.append(t)
		t += interval
	return out


## Distinct spawn ticks of fakes, relative to `start`, from `start` on.
func _fake_ticks(rec: Rec, start: int) -> Array[int]:
	var out: Array[int] = []
	for f in rec.fakes:
		var t := f.spawn_tick - start
		if t >= 0 and (out.is_empty() or out[-1] != t):
			out.append(t)
	return out


func _defs(enemies: Array[SimEnemy]) -> Dictionary:
	var out := {}
	for e in enemies:
		out[e.def.id] = int(out.get(e.def.id, 0)) + 1
	return out


## [spawn_tick, def, pack size] per spawn call (a pack's members share pack_of, LT-63).
func _spawn_calls(enemies: Array[SimEnemy]) -> Array:
	var out: Array = []
	var at := {}  # pack_of -> index in out
	for e in enemies:
		if e.pack_of != 0 and at.has(e.pack_of):
			out[at[e.pack_of]][2] += 1
			continue
		if e.pack_of != 0:
			at[e.pack_of] = out.size()
		out.append([e.spawn_tick, e.def.id, 1])
	return out


# --- schedule (behaviours 1-4) ------------------------------------------------

func test_lucid_never_spawns_a_fake_in_a_full_wave() -> void:
	var sim := _long_sim()
	_set_state(sim, "lucid")
	var rec := Rec.new(sim)
	assert_object(rec.until(T.WAVE_CLEARED)).is_not_null()
	assert_int(rec.reals.size()).is_equal(_long_count())
	assert_array(rec.fakes).is_empty()


func _assert_schedule(key: String) -> void:
	var sim := _long_sim()
	_set_state(sim, key)
	var rec := Rec.new(sim)
	var start := rec.until(T.WAVE_STARTED).tick
	assert_object(rec.until(T.WAVE_CLEARED)).is_not_null()
	var expected := _multiples(_interval(sim, key), _long_last())
	assert_int(expected.size()).is_greater_equal(3)
	assert_array(_fake_ticks(rec, start)).is_equal(expected)


func test_whispers_spawns_the_first_fake_one_interval_into_the_wave_then_every_interval() -> void:
	_assert_schedule("whispers")


func test_fraying_spawns_on_its_own_interval() -> void:
	_assert_schedule("fraying")


func test_madness_spawns_on_its_own_interval() -> void:
	_assert_schedule("madness")


func test_no_fake_in_the_build_phase_and_no_candidates_outside_a_wave() -> void:
	var build_s := ceili(3.0 * real_config().sanity.thresholds["fraying"].fake_spawn_interval)
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], build_s, LIGHTHOUSE_HP)
	_set_state(sim, "fraying")
	assert_array(director.fake_candidates(sim)).is_empty()  # BUILD before wave 1
	var rec := Rec.new(sim)
	rec.until(T.WAVE_STARTED)
	assert_int(rec.events[-1].tick).is_greater(_interval(sim, "fraying"))
	rec.until(T.WAVE_CLEARED)
	_set_state(sim, "fraying")
	assert_array(director.fake_candidates(sim)).is_empty()  # BUILD between waves
	rec.until(T.WAVE_STARTED, 2)
	assert_array(rec.fakes).is_empty()
	rec.until(T.WAVE_CLEARED, 2)
	assert_int(sim.state.phase).is_equal(SimState.Phase.DONE)
	assert_array(director.fake_candidates(sim)).is_empty()  # DONE


func test_no_fake_once_the_waves_groups_are_exhausted() -> void:
	var sim := wsim([[group("hybrid", 1)]], 1, LIGHTHOUSE_HP)
	_set_state(sim, "fraying")
	var rec := Rec.new(sim)
	var start := rec.until(T.WAVE_STARTED).tick
	rec.step(2 * _interval(sim, "fraying"))
	# The real hybrid is still walking, so the wave is open: only exhaustion stops fakes.
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	assert_int(sim.state.enemies.size()).is_equal(1)
	assert_int(sim.state.tick - start).is_equal(2 * _interval(sim, "fraying"))
	assert_array(rec.fakes).is_empty()


func test_no_fake_with_a_scripted_spawner() -> void:
	var sim := Simulation.new(tconfig(), SEED)
	var script: Array = []
	for i in 10:
		script.append([1 + i * SimTime.ticks(SPACING), "cultist"])
	sim.set_spawner(ScriptedSpawner.new(script))
	_set_state(sim, "fraying")
	var rec := Rec.new(sim)
	rec.step(10 * _interval(sim, "fraying"))
	assert_int(rec.reals.size()).is_equal(10)
	assert_array(rec.fakes).is_empty()


func test_drop_to_fraying_mid_wave_keeps_the_counter_and_spawns_on_the_next_tick() -> void:
	var sim := _long_sim()
	_set_state(sim, "whispers")
	var iw := _interval(sim, "whispers")
	var ifr := _interval(sim, "fraying")
	var x := (iw + ifr) / 2
	assert_int(x).is_greater(ifr)
	assert_int(x).is_less(iw)
	var rec := Rec.new(sim)
	var start := rec.until(T.WAVE_STARTED).tick
	rec.step(x)
	assert_array(rec.fakes).is_empty()
	_set_state(sim, "fraying")
	rec.step(1 + ifr)
	assert_array(_fake_ticks(rec, start)).is_equal([x + 1, x + 1 + ifr])


func test_rising_to_lucid_pauses_the_counter_without_resetting_it() -> void:
	var sim := _long_sim()
	_set_state(sim, "fraying")
	var f := _interval(sim, "fraying")
	var a := f / 2
	var b := 2 * f
	var rec := Rec.new(sim)
	var start := rec.until(T.WAVE_STARTED).tick
	rec.step(a)
	_set_state(sim, "lucid")
	rec.step(b)
	assert_array(rec.fakes).is_empty()
	_set_state(sim, "fraying")
	rec.step(f)
	# a ticks counted before the pause, f - a after it.
	assert_array(_fake_ticks(rec, start)).is_equal([b + f])


func test_a_new_wave_restarts_the_counter() -> void:
	var sim := _long_sim("cultist", 2)
	_set_state(sim, "fraying")
	var f := _interval(sim, "fraying")
	var rec := Rec.new(sim)
	rec.until(T.WAVE_CLEARED)
	_set_state(sim, "fraying")  # between-waves regen may have moved it
	var start2 := rec.until(T.WAVE_STARTED, 2).tick
	rec.until(T.WAVE_CLEARED, 2)
	assert_array(_fake_ticks(rec, start2)).is_equal(_multiples(f, _long_last()))


# --- type (behaviour 5, owner Q6) ---------------------------------------------

func test_fakes_mimic_the_current_wave() -> void:
	var n := _long_count()
	var sim := wsim([[group("cultist", n, SPACING)], [group("hybrid", n, SPACING)]], 1,
		LIGHTHOUSE_HP)
	_set_state(sim, "fraying")
	var rec := Rec.new(sim)
	rec.until(T.WAVE_CLEARED)
	_set_state(sim, "fraying")
	var start2 := rec.until(T.WAVE_STARTED, 2).tick
	rec.until(T.WAVE_CLEARED, 2)
	var w1: Array[SimEnemy] = []
	var w2: Array[SimEnemy] = []
	for f in rec.fakes:
		if f.spawn_tick < start2:
			w1.append(f)
		else:
			w2.append(f)
	assert_dict(_defs(w1)).is_equal({"cultist": _multiples(_interval(sim, "fraying"),
		_long_last()).size()})
	assert_dict(_defs(w2)).is_equal({"hybrid": _multiples(_interval(sim, "fraying"),
		_long_last()).size()})


func test_fakes_mimic_only_groups_with_unfired_spawns() -> void:
	var sim := wsim([[group("hybrid", 3), group("cultist", _long_count(), SPACING)]], 1,
		LIGHTHOUSE_HP)
	_set_state(sim, "fraying")
	var rec := Rec.new(sim)
	rec.until(T.WAVE_CLEARED)
	assert_int(rec.fakes.size()).is_greater(0)
	assert_array(_defs(rec.fakes).keys()).is_equal(["cultist"])


func test_fake_type_is_weighted_by_unfired_spawn_events() -> void:
	# One cultist held back to the last hybrid's tick vs a long hybrid group: weighted by
	# unfired events a fake cultist is rare; one pick per group would give about half.
	var picks := {}
	for run_seed in [1, 2, 3, 4, 5]:
		var sim := wsim([[group("cultist", 1, 0.0, (_long_count() - 1) * SPACING),
			group("hybrid", _long_count(), SPACING)]], 1, LIGHTHOUSE_HP, run_seed)
		_set_state(sim, "fraying")
		var rec := Rec.new(sim)
		rec.until(T.WAVE_CLEARED)
		for k: String in _defs(rec.fakes):
			picks[k] = int(picks.get(k, 0)) + _defs(rec.fakes)[k]
	var total := int(picks.get("cultist", 0)) + int(picks.get("hybrid", 0))
	assert_int(total).is_greater(20)
	assert_int(int(picks.get("cultist", 0)) * 4).is_less(total)


func test_same_seed_gives_the_same_fake_picks() -> void:
	var lists: Array = []
	for i in 2:
		var n := _long_count()
		var sim := wsim([[group("cultist", n, SPACING), group("hybrid", n, SPACING)]], 1,
			LIGHTHOUSE_HP)
		_set_state(sim, "fraying")
		var rec := Rec.new(sim)
		rec.until(T.WAVE_CLEARED)
		var l: Array = []
		for f in rec.fakes:
			l.append([f.spawn_tick, f.def.id])
		lists.append(l)
	assert_int((lists[0] as Array).size()).is_greater(2)
	assert_array(lists[0]).is_equal(lists[1])


func test_a_boss_is_never_mimicked() -> void:
	var n := _long_count()
	var sim := wsim([[group("hybrid", n, SPACING)],
		[group("hybrid", n, SPACING), group("cultist", n, SPACING)]], 1, LIGHTHOUSE_HP)
	# config rejects the trait today (the Dagon content task adds it): set it in memory.
	sim.config.enemies["hybrid"].traits[HallucinationSystem.BOSS_TRAIT] = {}
	_set_state(sim, "fraying")
	var rec := Rec.new(sim)
	rec.until(T.WAVE_CLEARED)
	assert_array(rec.fakes).is_empty()  # only a boss to mimic: no fake at all
	_set_state(sim, "fraying")
	rec.until(T.WAVE_CLEARED, 2)
	assert_int(rec.fakes.size()).is_greater(0)
	assert_array(_defs(rec.fakes).keys()).is_equal(["cultist"])


# --- packs and stream independence (behaviour 6) -------------------------------

func test_a_fake_deep_one_spawns_as_a_full_pack() -> void:
	var sim := _long_sim("deep_one")
	_set_state(sim, "fraying")
	var pack: Dictionary = sim.config.enemies["deep_one"].traits["pack"]
	var rec := Rec.new(sim)
	rec.until(T.WAVE_CLEARED)
	var calls := _spawn_calls(rec.fakes)
	assert_int(calls.size()).is_greater_equal(3)
	for c: Array in calls:
		assert_int(c[2]).is_between(int(pack["min"]), int(pack["max"]))


func test_real_pack_sizes_are_unchanged_by_fakes() -> void:
	var real_calls: Array = []
	var fake_count: Array[int] = []
	for system: bool in [true, false]:
		var sim := _long_sim("deep_one")
		if not system:
			sim._hallucinations = NoFakes.new()
		_set_state(sim, "fraying")
		var rec := Rec.new(sim)
		rec.until(T.WAVE_CLEARED)
		real_calls.append(_spawn_calls(rec.reals))
		fake_count.append(rec.fakes.size())
	assert_int(fake_count[0]).is_greater(0)
	assert_int(fake_count[1]).is_equal(0)
	assert_int((real_calls[0] as Array).size()).is_equal(_long_count())
	assert_array(real_calls[0]).is_equal(real_calls[1])


func test_a_lucid_run_is_event_identical_to_one_without_the_system() -> void:
	var runs: Array = []
	for system: bool in [true, false]:
		var n := _long_count()
		var sim := wsim([[group("cultist", n, SPACING), group("deep_one", n / 4, SPACING * 4)]],
			1, LIGHTHOUSE_HP)
		if not system:
			sim._hallucinations = NoFakes.new()
		sim.state.gold = 100000
		build(sim, "rifleman", Vector2i(3, 1))
		build(sim, "harpooner", Vector2i(9, 1))
		_set_state(sim, "lucid")
		var rec := Rec.new(sim)
		rec.until(T.WAVE_CLEARED)
		assert_int(of_type(rec.events, T.SANITY_STATE_CHANGED).size()).is_equal(0)
		assert_int(of_type(rec.events, T.SHOT).size()).is_greater(10)
		runs.append(strings_of(rec.events))
	assert_array(runs[0]).is_equal(runs[1])


# --- lighthouse, kills, wave end (behaviours 7-9) ------------------------------

func test_fake_and_real_reaching_the_lighthouse_together() -> void:
	var hp := 20
	var sim := Simulation.new(make_config(line_map(2), hp), SEED)
	var real := sim.spawn_enemy("cultist")
	var fake := sim.spawn_enemy("cultist", true)
	var def: EnemyDef = sim.config.enemies["cultist"]
	var at := expected_leak_tick(0, ground_length(3), SimTime.units_per_tick(def.speed))
	sim.drain_events()
	var events := run(sim, at - 1)
	assert_int(sim.state.enemies.size()).is_equal(2)
	events = run(sim, 1)
	var leaks := of_type(events, T.LEAKED)
	assert_array(ids_of(leaks)).is_equal([real])
	assert_dict(leaks[0].data).is_equal(
		{"damage": def.leak_damage, "hp_after": hp - def.leak_damage})
	var gone := of_type(events, T.FAKE_DISSOLVED)
	assert_array(ids_of(gone)).is_equal([fake])
	assert_dict(gone[0].data).is_equal({"reason": "lighthouse"})
	assert_int(gone[0].tick).is_equal(at)
	assert_int(sim.state.lighthouse_hp).is_equal(hp - def.leak_damage)
	assert_object(sim.enemy_by_id(fake)).is_null()
	assert_array(sim.state.enemies).is_empty()


func test_a_killed_fake_dies_like_a_real_but_pays_no_gold_and_no_sanity() -> void:
	var sim := tsim()
	_set_state(sim, "whispers")  # below the cap, so a mundane kill would restore sanity
	var real := put(sim, "cultist", 3.0, 1.0)
	var fake := put(sim, "cultist", 4.0, 1.0, true)
	sim.drain_events()
	var gold := sim.state.gold
	var sanity := sim.state.sanity
	sim.apply_damage(fake.id, 10.0, "rifleman")
	var fev := sim.drain_events()
	# LT-27: a fake drops a (ghost) token like a real kill; neither pays money.
	assert_array(fev.map(func(e: SimEvent) -> int: return e.type)).is_equal(
		[T.DIED, T.RELIC_DROPPED])
	assert_int(sim.state.gold).is_equal(gold)
	assert_float(sim.state.sanity).is_equal(sanity)
	sim.apply_damage(real.id, 10.0, "rifleman")
	var rev := sim.drain_events()
	assert_int(of_type(rev, T.GOLD_CHANGED).size()).is_equal(0)
	assert_int(of_type(rev, T.SANITY_CHANGED).size()).is_equal(1)
	assert_dict(fev[0].data).is_equal(of_type(rev, T.DIED)[0].data)


## Wave of 3 cultists 1.5 fake intervals apart: fakes at 1 and 2 intervals; the reals are
## killed right after the last spawn, while both fakes are still walking.
func _wave_end_sim(waves: int, hp := LIGHTHOUSE_HP) -> Simulation:
	var fs: float = real_config().sanity.thresholds["fraying"].fake_spawn_interval
	var ws: Array = []
	for i in waves:
		ws.append([group("cultist", 3, 1.5 * fs)])
	var sim := wsim(ws, 1, hp)
	_set_state(sim, "fraying")
	var def: EnemyDef = sim.config.enemies["cultist"]
	var walk := ceili(float(sim.state.map.path.size() - 1) * SimTime.UNITS_PER_CELL
		/ SimTime.units_per_tick(def.speed))
	assert_int(walk).override_failure_message("fixture: a fake must outlive the wave") \
		.is_greater(2 * _interval(sim, "fraying") + 1)
	return sim


func _clear_with_live_fakes(sim: Simulation) -> Array[SimEvent]:
	var rec := Rec.new(sim)
	var start := rec.until(T.WAVE_STARTED).tick
	rec.step(3 * _interval(sim, "fraying") - (sim.state.tick - start))
	assert_int(rec.fakes.size()).is_equal(2)
	for f in rec.fakes:
		assert_bool(f.is_live()).is_true()
	kill_real(sim)
	var before := rec.events.size()
	rec.step()
	var out: Array[SimEvent] = []
	for e in rec.events.slice(before):
		var bonus_gold: bool = e.type == T.GOLD_CHANGED and e.data["reason"] == "wave_bonus"
		if bonus_gold or e.type in [T.FAKE_DISSOLVED, T.WAVE_CLEARED, T.BUILD_STARTED,
				T.OUTCOME, T.LEAKED]:
			out.append(e)
	assert_array(ids_of(of_type(out, T.FAKE_DISSOLVED))).is_equal(
		[rec.fakes[0].id, rec.fakes[1].id])
	assert_bool(rec.fakes[0].id < rec.fakes[1].id).is_true()
	for e in of_type(out, T.FAKE_DISSOLVED):
		assert_dict(e.data).is_equal({"reason": "wave_end"})
	return out


func test_wave_end_dissolves_live_fakes_before_the_bonus_and_the_clear() -> void:
	var sim := _wave_end_sim(2)
	var out := _clear_with_live_fakes(sim)
	assert_array(out.map(func(e: SimEvent) -> int: return e.type)).is_equal(
		[T.FAKE_DISSOLVED, T.FAKE_DISSOLVED, T.GOLD_CHANGED, T.WAVE_CLEARED, T.BUILD_STARTED])
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_array(sim.state.enemies).is_empty()


func test_last_wave_with_live_fakes_dissolves_them_and_wins() -> void:
	var sim := _wave_end_sim(1)
	var out := _clear_with_live_fakes(sim)
	assert_array(out.map(func(e: SimEvent) -> int: return e.type)).is_equal(
		[T.FAKE_DISSOLVED, T.FAKE_DISSOLVED, T.GOLD_CHANGED, T.WAVE_CLEARED, T.OUTCOME])
	assert_dict(out[-1].data).is_equal({"result": "won"})
	assert_array(sim.state.enemies).is_empty()


func test_on_a_loss_no_fake_dissolves_and_none_spawns_afterwards() -> void:
	var def: EnemyDef = real_config().enemies["cultist"]
	var sim := _wave_end_sim(1, def.leak_damage)
	var rec := Rec.new(sim)
	assert_object(rec.until(T.OUTCOME, 1, 5000)).is_not_null()
	assert_dict(rec.events[-1].data).is_equal({"result": "lost"})
	assert_int(rec.fakes.size()).is_equal(2)
	assert_int(of_type(rec.events, T.FAKE_DISSOLVED).size()).is_equal(0)
	for f in rec.fakes:
		assert_bool(f.is_live()).is_true()
	var n := sim.state.enemies.size()
	rec.step(3 * _interval(sim, "fraying"))
	assert_int(sim.state.enemies.size()).is_equal(n)
	assert_int(rec.fakes.size()).is_equal(2)


# --- events never tell (behaviour 10) -------------------------------------------

func test_events_of_fakes_and_reals_are_indistinguishable() -> void:
	var n := _long_count()
	var sim := wsim([[group("cultist", n, SPACING), group("hybrid", n / 3, SPACING * 3)]], 1,
		LIGHTHOUSE_HP)
	sim.state.gold = 100000
	for x in range(1, 12):  # enough fire that fakes get killed too, not only the leaders
		build(sim, "rifleman", Vector2i(x, 1))
	build(sim, "harpooner", Vector2i(12, 1))
	_set_state(sim, "fraying")
	var rec := Rec.new(sim)
	rec.until(T.WAVE_CLEARED)
	var fake_ids := {}
	for f in rec.fakes:
		fake_ids[f.id] = f
	assert_int(fake_ids.size()).is_greater(2)
	var by_type := {}  # [type, fake?] -> keys seen
	var fake_died := 0
	for e in rec.events:
		assert_bool(e.data.has("fake")).override_failure_message(str(e)).is_false()
		if e.type == T.LEAKED:
			assert_array(e.data.keys()).contains_exactly_in_any_order(["damage", "hp_after"])
		# Relic events carry a token id (LT-27 §1.3), not an entity id.
		var is_f := fake_ids.has(e.id) and not e.type in [T.RELIC_DROPPED, T.RELIC_VANISHED,
			T.RELICS_CHANGED]
		if e.type == T.SHOT:
			is_f = fake_ids.has(int(e.data["target"]))
		elif is_f:
			assert_int(e.type).override_failure_message(str(e)).is_in(
				[T.SPAWNED, T.DIED, T.FAKE_DISSOLVED])
		if e.type == T.DIED and is_f:
			fake_died += 1
		var key := [e.type, is_f]
		var keys := e.data.keys()
		keys.sort()
		if by_type.has(key):
			assert_array(keys).is_equal(by_type[key])
		by_type[key] = keys
	assert_int(fake_died).is_greater(0)
	for t in [T.SPAWNED, T.DIED, T.SHOT]:
		assert_bool(by_type.has([t, true]) and by_type.has([t, false])).is_true()
		assert_array(by_type[[t, true]]).is_equal(by_type[[t, false]])
	# SPAWNED and DIED values match too (same def, same source kind).
	for f in rec.fakes:
		for e in of_type(rec.events, T.SPAWNED):
			if e.id == f.id:
				assert_dict(e.data).is_equal({"def": f.def.id})


func test_debug_is_fake_only_with_the_reveal_flag() -> void:
	var sim := tsim()
	var real := put(sim, "cultist", 3.0)
	var fake := put(sim, "cultist", 4.0, HUGE_HP, true)
	assert_bool(sim.debug_reveal_fakes).is_false()
	assert_bool(sim.debug_is_fake(real)).is_false()
	assert_bool(sim.debug_is_fake(fake)).is_false()
	sim.debug_reveal_fakes = true
	assert_bool(sim.debug_is_fake(real)).is_false()
	assert_bool(sim.debug_is_fake(fake)).is_true()
