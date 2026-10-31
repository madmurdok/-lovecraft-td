class_name MadnessTest
extends WaveTestBase
## LT-13 madness mode (GDD §5.4): the latch (sanity <= 0 is exited only by the exit rule),
## astray occult shots (shot_split on the MADNESS stream, x damage_multiplier once), the
## exit rules (permanent / buyout / auto_restore) and determinism. Every number is read
## from config; the exit rule and the split are switched on the loaded config object.

const T := SimEvent.Type
const S := SimState.SanityState
const NECRO := "necronomicon_reader"
const SIGN := "elder_sign"
const REAL_CELLS := 6.0  ## parked real: 1.4 cells from the default tower
const FAR_CELLS := 9.0  ## second parked enemy: 2.2 cells from it and 3 from REAL_CELLS
const CASTS := 2000
const SIGMAS := 4.0


# --- helpers ---------------------------------------------------------------------------

func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _split(sim: Simulation, real: float, fake: float, empty: float) -> void:
	var m := sim.config.sanity.madness
	m.shot_real = real
	m.shot_fake = fake
	m.shot_empty = empty


func _rule(sim: Simulation, rule: String) -> void:
	sim.config.sanity.madness.exit_rule = rule


## Switches off the LT-23 madness enemy buff, so the LT-13 damage numbers stay exact.
func _no_enemy_buff(sim: Simulation) -> void:
	var m := sim.config.sanity.madness
	m.enemy_speed_multiplier = 1.0
	m.enemy_damage_taken_multiplier = 1.0


## tower-test sim with plenty of gold, a Necronomicon at TOWER and sanity 0 (madness),
## without the LT-23 enemy buff.
func _necro_sim(run_seed := SEED) -> Simulation:
	var sim := Simulation.new(tconfig(), run_seed)
	_no_enemy_buff(sim)
	sim.state.gold = 1000000
	build(sim, NECRO)
	_set_sanity(sim, 0.0)
	return sim


## Steps `n` times with every tower's cooldown cleared first (one cast per tick); returns
## the SHOT events.
func _casts(sim: Simulation, n: int) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for i in n:
		for t in sim.state.towers:
			t.cooldown_ticks = 0
		sim.step()
		out.append_array(of_type(sim.drain_events(), T.SHOT))
	return out


## "empty" (no hits), else "fake" if the shot's target is one of `fake_ids`, else "real".
func _kind(shot: SimEvent, fake_ids: Array[int]) -> String:
	if shot.data["hits"].is_empty():
		return "empty"
	return "fake" if fake_ids.has(shot.data["target"]) else "real"


func _madness_state(sim: Simulation) -> int:
	return sim.rng(SimRng.Stream.MADNESS).state


## State of the MADNESS stream of a run seeded `run_seed` after `draws` randf() calls.
func _reference_state(run_seed: int, draws: int) -> int:
	var g := RandomNumberGenerator.new()
	g.seed = run_seed * SimRng.STREAM_SEED_STRIDE + SimRng.Stream.MADNESS
	for i in draws:
		g.randf()
	return g.state


func _assert_within_sigmas(count: int, n: int, p: float) -> void:
	var sigma := sqrt(n * p * (1.0 - p))
	assert_float(float(count)).override_failure_message(
		"count %d of %d outside %.0f sigma of p=%s" % [count, n, SIGMAS, p]) \
		.is_between(n * p - SIGMAS * sigma, n * p + SIGMAS * sigma)


# --- astray split ----------------------------------------------------------------------

func test_shot_split_frequencies_follow_the_configured_split() -> void:
	for run_seed in [3, 17, 101]:
		var sim := _necro_sim(run_seed)
		# Enough HP that neither dies within CASTS casts (a dead real would turn "real"
		# rolls into empty shots).
		var hp := HUGE_HP * 10.0
		var real := put(sim, "cultist", REAL_CELLS, hp)
		var fake := put(sim, "cultist", FAR_CELLS, hp, true)
		var m := sim.config.sanity.madness
		var counts := {"real": 0, "fake": 0, "empty": 0}
		for s in _casts(sim, CASTS):
			counts[_kind(s, [fake.id])] += 1
		assert_int(counts["real"] + counts["fake"] + counts["empty"]).is_equal(CASTS)
		_assert_within_sigmas(counts["real"], CASTS, m.shot_real)
		_assert_within_sigmas(counts["fake"], CASTS, m.shot_fake)
		_assert_within_sigmas(counts["empty"], CASTS, m.shot_empty)
		assert_float(real.hp).is_greater(0.0)
		assert_float(real.hp).is_less(hp)
		assert_float(fake.hp).is_less(hp)


func test_a_real_or_fake_shot_picks_uniformly_among_those_in_range() -> void:
	# Not the first-along-route one: the enemy at FAR_CELLS is first, REAL_CELLS second.
	for kind in ["real", "fake"]:
		var sim := _necro_sim()
		var is_fake: bool = kind == "fake"
		_split(sim, 0.0 if is_fake else 1.0, 1.0 if is_fake else 0.0, 0.0)
		var a := put(sim, "cultist", REAL_CELLS, HUGE_HP, is_fake)
		var b := put(sim, "cultist", FAR_CELLS, HUGE_HP, is_fake)
		var n := 400
		var on_a := 0
		for s in _casts(sim, n):
			assert_array(s.data["hits"]).has_size(1)
			if s.data["target"] == a.id:
				on_a += 1
			else:
				assert_int(s.data["target"]).is_equal(b.id)
		_assert_within_sigmas(on_a, n, 0.5)


func test_a_real_roll_with_no_real_in_range_is_an_empty_shot() -> void:
	var sim := _necro_sim()
	_split(sim, 1.0, 0.0, 0.0)
	var fake := put(sim, "cultist", REAL_CELLS, HUGE_HP, true)
	for s in _casts(sim, 50):
		assert_array(s.data["hits"]).is_empty()
		assert_bool(s.data["astray"]).is_true()
	assert_float(fake.hp).is_equal(HUGE_HP)
	# One roll per cast and no pick draw for the empty pool.
	assert_int(_madness_state(sim)).is_equal(_reference_state(SEED, 50))


func test_a_fake_roll_with_no_fake_in_range_is_an_empty_shot() -> void:
	var sim := _necro_sim()
	_split(sim, 0.0, 1.0, 0.0)
	var real := put(sim, "cultist", REAL_CELLS)
	for s in _casts(sim, 50):
		assert_array(s.data["hits"]).is_empty()
		assert_bool(s.data["astray"]).is_true()
	assert_float(real.hp).is_equal(HUGE_HP)
	assert_int(_madness_state(sim)).is_equal(_reference_state(SEED, 50))


func test_an_empty_roll_deals_no_damage_to_anyone_and_makes_no_sanity_event() -> void:
	var sim := _necro_sim()
	_split(sim, 0.0, 0.0, 1.0)
	var real := put(sim, "cultist", REAL_CELLS)
	var fake := put(sim, "cultist", FAR_CELLS, HUGE_HP, true)
	for i in 20:
		for t in sim.state.towers:
			t.cooldown_ticks = 0
		sim.step()
		var ev := sim.drain_events()
		var shots := of_type(ev, T.SHOT)
		assert_int(shots.size()).is_equal(1)
		assert_array(shots[0].data["hits"]).is_empty()
		assert_bool(shots[0].data["astray"]).is_true()
		assert_bool(shots[0].data["miss"]).is_false()
		assert_array(of_type(ev, T.SANITY_CHANGED)).is_empty()
		assert_array(of_type(ev, T.DIED)).is_empty()
	assert_float(real.hp).is_equal(HUGE_HP)
	assert_float(fake.hp).is_equal(HUGE_HP)
	assert_float(sim.state.sanity).is_equal(0.0)


func test_astray_shots_never_hurt_the_player_side() -> void:
	var sim := _necro_sim()
	build(sim, NECRO, Vector2i(8, 1))
	_set_sanity(sim, 0.0)
	var real := put(sim, "cultist", REAL_CELLS)
	var fake := put(sim, "cultist", FAR_CELLS, HUGE_HP, true)
	var hp := sim.state.lighthouse_hp
	var towers := sim.state.towers.size()
	var gold := sim.state.gold
	for s in _casts(sim, 300):
		for id: int in s.data["hits"]:
			assert_bool(id == real.id or id == fake.id).is_true()
	assert_int(sim.state.lighthouse_hp).is_equal(hp)
	assert_int(sim.state.towers.size()).is_equal(towers)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)


# --- damage ----------------------------------------------------------------------------

## HP lost by a hybrid (armor > 0) parked in range after one cast at `sanity`.
func _hybrid_loss(sanity: float, with_sign: bool) -> float:
	var sim := Simulation.new(tconfig(), SEED)
	_no_enemy_buff(sim)
	sim.state.gold = 1000000
	if with_sign:
		build(sim, SIGN, Vector2i(6, 1))
	build(sim, NECRO)
	_split(sim, 1.0, 0.0, 0.0)
	_set_sanity(sim, sanity)
	var e := put(sim, "hybrid", 7.0)
	sim.step()
	return HUGE_HP - e.hp


func test_madness_damage_is_doubled_once_before_armor_and_the_sign_boost() -> void:
	var sim := tsim()
	var dmg := sim.config.towers[NECRO].levels[0].damage
	var mult := sim.config.sanity.madness.damage_multiplier
	var armor := sim.config.enemies["hybrid"].armor
	var boost: float = sim.config.towers[SIGN].levels[0].effects["damage_taken_multiplier"]
	assert_float(armor).is_greater(0.0)
	assert_float(boost).is_greater(1.0)
	var expected := (dmg * mult - armor) * boost
	# The orders that would be wrong differ from the right one.
	assert_float((dmg - armor) * mult * boost).is_not_equal(expected)
	assert_float(dmg * mult * boost - armor).is_not_equal(expected)
	assert_float(_hybrid_loss(0.0, true)).is_equal_approx(expected, 0.0001)
	assert_float(_hybrid_loss(0.0, false)).is_equal_approx(dmg * mult - armor, 0.0001)
	# Outside madness the same cast is not multiplied.
	assert_float(_hybrid_loss(50.0, true)).is_equal_approx((dmg - armor) * boost, 0.0001)
	assert_float(_hybrid_loss(50.0, false)).is_equal_approx(dmg - armor, 0.0001)


func test_every_enemy_in_the_blast_takes_the_doubled_damage() -> void:
	var sim := _necro_sim()
	_split(sim, 1.0, 0.0, 0.0)
	var a := put(sim, "cultist", 6.0)
	var b := put(sim, "cultist", 7.0)
	var dmg := sim.config.towers[NECRO].levels[0].damage
	var mult := sim.config.sanity.madness.damage_multiplier
	sim.step()
	assert_float(a.hp).is_equal_approx(HUGE_HP - dmg * mult, 0.0001)
	assert_float(b.hp).is_equal_approx(HUGE_HP - dmg * mult, 0.0001)


# --- astray flag and who is affected ---------------------------------------------------

func test_shots_carry_astray_true_only_in_madness_and_never_name_the_outcome() -> void:
	var sim := _necro_sim()
	put(sim, "cultist", REAL_CELLS)
	put(sim, "cultist", FAR_CELLS, HUGE_HP, true)
	for s in _casts(sim, 300):
		assert_bool(s.data["astray"] is bool).is_true()
		assert_bool(s.data["astray"]).is_true()
		for v: Variant in s.data.values():
			assert_bool(v is String and v in ["real", "fake", "empty"]).is_false()
		for k: String in s.data:
			assert_bool(k in ["def", "target", "hits", "to", "miss", "astray"]).is_true()
	for v in [100.0, 50.0, 20.0]:
		var out := Simulation.new(tconfig(), SEED)
		out.state.gold = 1000000
		build(out, NECRO)
		_set_sanity(out, v)
		put(out, "cultist", REAL_CELLS)
		for s in _casts(out, 3):
			assert_bool(s.data.has("astray")).override_failure_message("sanity %s" % v).is_false()


func test_mundane_towers_in_madness_keep_the_miss_roll_and_are_not_doubled() -> void:
	var sim := Simulation.new(tconfig(), SEED)
	_no_enemy_buff(sim)
	sim.state.gold = 1000000
	build(sim, "rifleman")
	_set_sanity(sim, 0.0)
	var e := put(sim, "cultist", 7.0)
	var dmg := sim.config.towers["rifleman"].levels[0].damage
	var chance := sim.config.sanity.thresholds["madness"].miss_chance
	assert_float(chance).is_greater(0.0)
	var combat_before: int = sim.rng(SimRng.Stream.COMBAT).state
	var n := 1000
	var misses := 0
	for s in _casts(sim, n):
		assert_bool(s.data.has("astray")).is_false()
		if s.data["miss"]:
			misses += 1
	_assert_within_sigmas(misses, n, chance)
	assert_float(e.hp).is_equal_approx(HUGE_HP - dmg * (n - misses), 0.0001)
	assert_int(sim.rng(SimRng.Stream.COMBAT).state).is_not_equal(combat_before)
	assert_int(_madness_state(sim)).is_equal(_reference_state(SEED, 0))


func test_an_occult_tower_that_is_not_madness_affected_shoots_as_usual() -> void:
	var sim := _necro_sim()
	sim.config.towers[NECRO].levels[0].madness_affected = false
	var near := put(sim, "cultist", REAL_CELLS)
	var first := put(sim, "cultist", FAR_CELLS)
	var dmg := sim.config.towers[NECRO].levels[0].damage
	var n := 20
	for s in _casts(sim, n):
		assert_bool(s.data.has("astray")).is_false()
		assert_int(s.data["target"]).is_equal(first.id)
	assert_float(first.hp).is_equal_approx(HUGE_HP - dmg * n, 0.0001)
	assert_float(near.hp).is_equal(HUGE_HP)
	assert_int(_madness_state(sim)).is_equal(_reference_state(SEED, 0))


func test_elder_sign_is_unaffected_by_madness() -> void:
	var sim := Simulation.new(tconfig(), SEED)
	_no_enemy_buff(sim)
	sim.state.gold = 1000000
	build(sim, SIGN)
	_set_sanity(sim, 0.0)
	var e := put(sim, "cultist", 7.0)
	var boost: float = sim.config.towers[SIGN].levels[0].effects["damage_taken_multiplier"]
	sim.step()
	assert_array(of_type(sim.drain_events(), T.SHOT)).is_empty()
	assert_float(e.damage_taken_mult).is_equal(boost)
	assert_int(_madness_state(sim)).is_equal(_reference_state(SEED, 0))


func test_non_madness_runs_draw_nothing_from_the_madness_stream() -> void:
	var sim := Simulation.new(tconfig(), SEED)
	sim.state.gold = 1000000
	build(sim, NECRO)
	build(sim, "rifleman", Vector2i(8, 1))
	put(sim, "cultist", REAL_CELLS)
	put(sim, "cultist", FAR_CELLS, HUGE_HP, true)
	var shots := _casts(sim, 20)  # casts cost no sanity (LT-23): stays outside madness
	assert_int(sim.state.sanity_state).is_not_equal(S.MADNESS)
	assert_int(shots.size()).is_greater(0)
	assert_int(_madness_state(sim)).is_equal(_reference_state(SEED, 0))


# --- fakes -----------------------------------------------------------------------------

func test_fakes_spawn_at_the_madness_row_interval() -> void:
	var sim := wsim([[group("cultist", 3, 100.0)]])
	var th := sim.config.sanity.thresholds
	th["madness"].fake_spawn_interval = 4.0  # distinct from the fraying row (6)
	_set_sanity(sim, 0.0)
	var started := -1
	var first_fake := -1
	for i in 600:
		sim.step()
		for e in sim.drain_events():
			if e.type == T.WAVE_STARTED:
				started = e.tick
		if first_fake < 0:
			for e in sim.state.enemies:
				if e.is_fake:
					first_fake = sim.state.tick
		if first_fake >= 0:
			break
	assert_int(started).is_greater(0)
	assert_int(first_fake).is_equal(started + SimTime.ticks(4.0))


# --- the latch -------------------------------------------------------------------------

func test_regen_and_drain_change_nothing_in_madness() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	_set_sanity(sim, 0.0)
	sim.apply_damage(e.id, 1.0e9, "rifleman")
	var ev := sim.drain_events()
	assert_array(of_type(ev, T.SANITY_CHANGED)).is_empty()
	assert_array(of_type(ev, T.SANITY_STATE_CHANGED)).is_empty()
	assert_float(sim.state.sanity).is_equal(0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_float(sim.award_wave_sanity()).is_equal(0.0)
	assert_float(sim.state.sanity).is_equal(0.0)


func test_permanent_and_buyout_madness_survive_every_wave_clear() -> void:
	for rule in ["permanent", "buyout"]:
		var sim := wsim([[group("cultist", 1)], [group("cultist", 1)], [group("cultist", 1)]])
		_rule(sim, rule)
		_set_sanity(sim, 0.0)
		var events := _until_cleared(sim, 3)
		assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
		assert_array(of_type(events, T.SANITY_CHANGED)).override_failure_message(rule).is_empty()
		assert_array(of_type(events, T.SANITY_STATE_CHANGED)).is_empty()
		assert_float(sim.state.sanity).is_equal(0.0)
		assert_int(sim.state.sanity_state).is_equal(S.MADNESS)


# --- buyout ----------------------------------------------------------------------------

func _buyout_sim() -> Simulation:
	var sim := wsim([[group("cultist", 1)]])
	_rule(sim, "buyout")
	sim.state.gold = 1000
	_set_sanity(sim, 0.0)
	return sim


func test_buyout_pays_the_cost_sets_sanity_logs_and_emits_in_order() -> void:
	var sim := _buyout_sim()
	var m := sim.config.sanity.madness
	var gold := sim.state.gold
	assert_int(sim.can_buy_sanity()).is_equal(Simulation.CommandResult.OK)
	assert_int(sim.buy_sanity()).is_equal(Simulation.CommandResult.OK)
	assert_int(sim.state.gold).is_equal(gold - m.buyout_cost)
	assert_float(sim.state.sanity).is_equal(m.restore_sanity)
	var new_state := sim.sanity_state_for(m.restore_sanity)
	assert_int(sim.state.sanity_state).is_equal(new_state)
	assert_array(sim.state.command_log).is_equal([[0, "buy_sanity"]])
	var ev := sim.drain_events()
	assert_array(ev).has_size(3)
	assert_int(ev[0].type).is_equal(T.GOLD_CHANGED)
	assert_dict(ev[0].data).is_equal(
		{"delta": -m.buyout_cost, "gold": gold - m.buyout_cost, "reason": "buyout"})
	assert_int(ev[1].type).is_equal(T.SANITY_CHANGED)
	assert_dict(ev[1].data).is_equal(
		{"delta": m.restore_sanity, "sanity": m.restore_sanity, "reason": "buyout"})
	assert_int(ev[2].type).is_equal(T.SANITY_STATE_CHANGED)
	assert_dict(ev[2].data).is_equal({"old": S.MADNESS, "new": new_state})
	# Out of madness: a second purchase is refused, and regen works again.
	assert_int(sim.can_buy_sanity()).is_equal(Simulation.CommandResult.NOT_IN_MADNESS)
	assert_int(sim.buy_sanity()).is_equal(Simulation.CommandResult.NOT_IN_MADNESS)
	assert_float(sim.award_wave_sanity()).is_greater(0.0)


func test_buyout_works_with_exactly_the_cost_and_during_a_wave() -> void:
	var sim := _buyout_sim()
	sim.call_wave()
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	sim.state.gold = sim.config.sanity.madness.buyout_cost
	sim.drain_events()
	assert_int(sim.buy_sanity()).is_equal(Simulation.CommandResult.OK)
	assert_int(sim.state.gold).is_equal(0)
	assert_float(sim.state.sanity).is_equal(sim.config.sanity.madness.restore_sanity)
	assert_array(sim.state.command_log).contains([[1, "buy_sanity"]])


func test_refused_buyouts_change_nothing_and_report_the_first_failing_reason() -> void:
	var R := Simulation.CommandResult
	var cases := {}  # name -> [sim, expected]
	var permanent := _buyout_sim()
	_rule(permanent, "permanent")
	cases["permanent"] = [permanent, R.NO_BUYOUT]
	var auto := _buyout_sim()
	_rule(auto, "auto_restore")
	cases["auto_restore"] = [auto, R.NO_BUYOUT]
	var sane := _buyout_sim()
	_set_sanity(sane, 50.0)
	cases["not in madness"] = [sane, R.NOT_IN_MADNESS]
	var poor := _buyout_sim()
	poor.state.gold = poor.config.sanity.madness.buyout_cost - 1
	cases["poor"] = [poor, R.NOT_ENOUGH_GOLD]
	var over := _buyout_sim()
	over.state.outcome = SimState.Outcome.LOST
	cases["outcome"] = [over, R.OUTCOME_REACHED]
	var order := _buyout_sim()  # outcome > rule > madness > gold
	_rule(order, "permanent")
	_set_sanity(order, 50.0)
	order.state.gold = 0
	cases["rule before madness and gold"] = [order, R.NO_BUYOUT]
	var order2 := _buyout_sim()
	_set_sanity(order2, 50.0)
	order2.state.gold = 0
	cases["madness before gold"] = [order2, R.NOT_IN_MADNESS]
	for name: String in cases:
		var sim: Simulation = cases[name][0]
		var gold := sim.state.gold
		var sanity := sim.state.sanity
		var expected: int = cases[name][1]
		assert_int(sim.can_buy_sanity()).override_failure_message(name).is_equal(expected)
		assert_int(sim.buy_sanity()).override_failure_message(name).is_equal(expected)
		assert_int(sim.state.gold).override_failure_message(name).is_equal(gold)
		assert_float(sim.state.sanity).override_failure_message(name).is_equal(sanity)
		assert_array(sim.state.command_log).override_failure_message(name).is_empty()
		assert_array(sim.drain_events()).override_failure_message(name).is_empty()


func test_the_other_exit_rules_ignore_the_buyout_cost_and_stay_in_madness() -> void:
	var sim := _buyout_sim()
	_rule(sim, "permanent")
	sim.buy_sanity()
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	assert_float(sim.auto_restore_sanity()).is_equal(0.0)
	assert_float(sim.state.sanity).is_equal(0.0)


# --- auto_restore ----------------------------------------------------------------------

## Steps (killing the real enemies between steps) until `n` WAVE_CLEARED events were seen.
func _until_cleared(sim: Simulation, n: int) -> Array[SimEvent]:
	var all: Array[SimEvent] = []
	var seen := 0
	for i in 4000:
		sim.step()
		var ev := sim.drain_events()
		all.append_array(ev)
		seen += of_type(ev, T.WAVE_CLEARED).size()
		if seen >= n or sim.state.outcome != SimState.Outcome.NONE:
			break
		kill_real(sim)
	return all


func _index_of(events: Array[SimEvent], type: T, reason := "") -> int:
	for i in events.size():
		if events[i].type == type and (reason.is_empty() or events[i].data.get("reason") == reason):
			return i
	return -1


func test_auto_restore_sets_sanity_to_exactly_restore_after_the_bonus_before_the_clear() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	_rule(sim, "auto_restore")
	_set_sanity(sim, 0.0)
	var m := sim.config.sanity.madness
	assert_float(sim.config.sanity.regen_between_waves).is_greater(0.0)
	var events := _until_cleared(sim, 1)
	assert_float(sim.state.sanity).is_equal(m.restore_sanity)  # no between_waves on top
	var changes := of_type(events, T.SANITY_CHANGED)
	assert_int(changes.size()).is_equal(1)
	assert_dict(changes[0].data).is_equal(
		{"delta": m.restore_sanity, "sanity": m.restore_sanity, "reason": "auto_restore"})
	var bonus_i := -1
	for i in events.size():
		if events[i].type == T.GOLD_CHANGED and events[i].data["reason"] == "wave_bonus":
			bonus_i = i
	var restore_i := _index_of(events, T.SANITY_CHANGED)
	var state_i := _index_of(events, T.SANITY_STATE_CHANGED)
	assert_int(bonus_i).is_greater_equal(0)
	assert_int(restore_i).is_greater(bonus_i)
	assert_int(state_i).is_equal(restore_i + 1)
	assert_dict(events[state_i].data).is_equal(
		{"old": S.MADNESS, "new": sim.sanity_state_for(m.restore_sanity)})
	assert_int(_index_of(events, T.WAVE_CLEARED)).is_greater(state_i)
	assert_int(sim.state.sanity_state).is_equal(sim.sanity_state_for(m.restore_sanity))


func test_auto_restore_also_fires_on_the_last_wave_in_the_tick_it_is_won() -> void:
	var sim := wsim([[group("cultist", 1)]])
	_rule(sim, "auto_restore")
	_set_sanity(sim, 0.0)
	var events := _until_cleared(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	var changes := of_type(events, T.SANITY_CHANGED)
	assert_int(changes.size()).is_equal(1)
	assert_str(changes[0].data["reason"]).is_equal("auto_restore")
	assert_int(changes[0].tick).is_equal(of_type(events, T.OUTCOME)[0].tick)
	assert_float(sim.state.sanity).is_equal(sim.config.sanity.madness.restore_sanity)


func test_auto_restore_does_nothing_outside_madness_or_under_other_rules() -> void:
	var regen := 0.0
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]])
	_rule(sim, "auto_restore")
	_set_sanity(sim, 50.0)
	regen = sim.config.sanity.regen_between_waves
	var events := _until_cleared(sim, 1)
	var changes := of_type(events, T.SANITY_CHANGED)
	assert_int(changes.size()).is_equal(1)
	assert_str(changes[0].data["reason"]).is_equal("between_waves")
	assert_float(sim.state.sanity).is_equal_approx(50.0 + regen, 0.0001)
	for rule in ["permanent", "buyout"]:
		var other := wsim([[group("cultist", 1)], [group("cultist", 1)]])
		_rule(other, rule)
		_set_sanity(other, 0.0)
		assert_int(_index_of(_until_cleared(other, 1), T.SANITY_CHANGED)).is_equal(-1)
		assert_float(other.state.sanity).is_equal(0.0)


func test_madness_entered_in_build_lasts_the_next_wave_and_ends_at_its_clear() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)], [group("cultist", 1)]])
	_rule(sim, "auto_restore")
	var m := sim.config.sanity.madness
	var regen := sim.config.sanity.regen_between_waves
	_set_sanity(sim, 50.0)
	_until_cleared(sim, 1)  # leaves us at the start of BUILD
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	_set_sanity(sim, 0.0)  # madness entered in BUILD
	for i in 5:
		sim.step()
	assert_float(sim.state.sanity).is_equal(0.0)
	var events := _until_cleared(sim, 1)
	assert_int(sim.state.wave_index).is_equal(2)
	assert_float(sim.state.sanity).is_equal(m.restore_sanity)
	assert_int(_index_of(events, T.SANITY_CHANGED, "auto_restore")).is_greater_equal(0)
	# Madness is over: wave 3 pays the normal between-waves regen on top.
	_until_cleared(sim, 1)
	assert_float(sim.state.sanity).is_equal_approx(m.restore_sanity + regen, 0.0001)


# --- determinism -----------------------------------------------------------------------

func _play(run_seed: int, commands: Array, ticks: int) -> Array:
	var sim := wsim([[group("cultist", 6, 1.0)], [group("cultist", 2, 1.0)]], 2, -1, run_seed)
	_rule(sim, "buyout")
	sim.state.gold = 2000
	_set_sanity(sim, 0.0)
	var out: Array[String] = []
	for t in ticks:
		for c: Array in commands:
			if int(c[0]) == sim.state.tick:
				match c[1]:
					"build": sim.build_tower(c[2], c[3])
					"call_wave": sim.call_wave()
					"buy_sanity": sim.buy_sanity()
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("tick=%d gold=%d sanity=%s madness=%d" % [sim.state.tick, sim.state.gold,
		sim.state.sanity, _madness_state(sim)])
	return [out, sim.state.command_log]


func test_same_seed_and_command_log_replay_the_same_madness_run() -> void:
	var commands := [[2, "build", NECRO, TOWER], [3, "build", NECRO, Vector2i(8, 1)],
		[5, "call_wave"], [150, "buy_sanity"]]
	var first := _play(SEED, commands, 500)
	var shots := 0
	for line: String in first[0]:
		if line.begins_with("SHOT") and line.contains("astray"):
			shots += 1
	assert_int(shots).is_greater(0)
	assert_array(first[1]).contains([[150, "buy_sanity"]])
	var replay := _play(SEED, first[1], 500)
	assert_array(replay[0]).is_equal(first[0])
	assert_array(replay[1]).is_equal(first[1])
	# Controls: the buyout and the seed each change the run.
	var without := _play(SEED, commands.slice(0, 3), 500)
	assert_bool(without[0] == first[0]).is_false()
	var other := _play(SEED + 1, commands, 500)
	assert_bool(other[0] == first[0]).is_false()
