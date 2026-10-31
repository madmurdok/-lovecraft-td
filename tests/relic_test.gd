class_name RelicTest
extends WaveTestBase
## LT-27 day/night relic economy (design note §1, §3, §6 behaviours 1-14): kills drop relic
## tokens credited on arrival, fakes' tokens vanish, the roll and early-night luck, the LOOT /
## GHOST_LOOT streams, dawn settlement, selling by day, night rules, day length, config
## rejects and replay.

const T := SimEvent.Type
const E := "enemies.json"
const EC := "economy.json"
const KINDS := ["bone", "amber", "idol", "star_stone"]
const SINGLE_BONE := {"cultist": {"drops": {"bone": 1}}}


# --- helpers ---------------------------------------------------------------------------

## Spawns `def_id` (a fake when `fake`), kills it between steps and returns its one
## RELIC_DROPPED event (the other drained events are dropped).
func _kill(sim: Simulation, def_id: String, fake := false) -> SimEvent:
	var id := sim.spawn_enemy(def_id, fake)
	sim.apply_damage(id, 1.0e9, "test")
	var dropped := of_type(sim.drain_events(), T.RELIC_DROPPED)
	assert_int(dropped.size()).is_equal(1)
	return dropped[0]


## Share of each kind over `n` kills of `def_id` (steps now and then so the dead are
## compacted).
func _shares(sim: Simulation, def_id: String, n: int, fake := false) -> Dictionary:
	var counts := {}
	for k: String in sim.config.economy.relic_ids():
		counts[k] = 0
	for i in n:
		var ev := _kill(sim, def_id, fake)
		counts[ev.data["kind"]] += 1
		if i % 100 == 99:
			sim.step()
			sim.drain_events()
	var out := {}
	for k: String in counts:
		out[k] = float(counts[k]) / n
	return out


func _assert_share(shares: Dictionary, kind: String, expected: float, tol: float) -> void:
	assert_float(shares[kind]).override_failure_message("%s share %f, expected %f +- %f"
		% [kind, shares[kind], expected, tol]).is_between(expected - tol, expected + tol)


func _rng_states(sim: Simulation) -> Dictionary:
	var out := {}
	for s: int in SimRng.Stream.values():
		out[s] = sim.rng(s).state
	return out


## The RNG state after one randf() from `state`.
func _one_draw_after(state: int) -> int:
	var r := RandomNumberGenerator.new()
	r.state = state
	r.randf()
	return r.state


## A run in phase WAVE (night): one wave of one parked-for-long cultist plus a second wave,
## so dawn starts a new day. `sanity_edit` edits sanity.json (null keeps it).
func _night_sim(sanity_edit: Variant = null) -> Simulation:
	var r := load_edited(func(dir: String) -> void:
		write_file(dir, "waves.json", JSON.stringify({"build_phase_seconds": 1, "waves": [
			{"groups": [group("cultist", 1)]}, {"groups": [group("cultist", 1)]}]}))
		edit(dir, MAP, func(root: Dictionary) -> void:
			root["width"] = ROWS[0].length()
			root["height"] = ROWS.size()
			root["rows"] = ROWS)
		if sanity_edit != null:
			edit(dir, "sanity.json", sanity_edit))
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var sim := Simulation.new(r.config, SEED)
	director = WaveDirector.new(sim.config.waves)
	sim.set_spawner(director)
	assert_int(sim.call_wave()).is_equal(R.OK)
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	sim.drain_events()
	return sim


func _stash(sim: Simulation) -> Dictionary:
	return sim.state.relics.duplicate()


# --- 1-3: tokens, credit on arrival, ghosts ----------------------------------------------

func test_real_kill_drops_a_token_credited_only_at_its_arrive_tick() -> void:
	var sim := tsim()
	assert_dict(sim.state.relics).is_equal({"bone": 0, "amber": 0, "idol": 0, "star_stone": 0})
	var gold := sim.state.gold
	var next_id := sim.state.next_id
	var e := put(sim, "hybrid", 8.0, 1.0)
	sim.drain_events()
	sim.apply_damage(e.id, 10.0, "test")
	var ev := sim.drain_events()
	assert_array(ev.map(func(x: SimEvent) -> int: return x.type)).is_equal([T.DIED, T.RELIC_DROPPED])
	assert_dict(ev[0].data).is_equal({"source": "test"})
	var drop := ev[1]
	var fly := SimTime.ticks(sim.config.economy.token_fly_seconds)
	assert_int(fly).is_equal(60)
	var kind: String = drop.data["kind"]
	assert_array(KINDS).contains([kind])
	assert_array(drop.data.keys()).contains_exactly_in_any_order(["token", "kind", "at",
		"arrive_tick"])
	assert_int(drop.id).is_equal(int(drop.data["token"]))
	assert_int(drop.data["arrive_tick"]).is_equal(drop.tick + fly)
	assert_vector(drop.data["at"]).is_equal(e.route.position_at(e.distance))
	assert_int(sim.state.next_id).is_equal(next_id + 1)  # the token id is not an entity id
	assert_int(sim.state.relic_tokens.size()).is_equal(1)
	var before := _stash(sim)
	# In flight: nothing credited up to the tick before arrival.
	var flight := run_to(sim, drop.tick + fly - 1)
	assert_array(of_type(flight, T.RELICS_CHANGED)).is_empty()
	assert_dict(sim.state.relics).is_equal(before)
	var landed := run(sim, 1)
	var ch := of_type(landed, T.RELICS_CHANGED)
	assert_int(ch.size()).is_equal(1)
	assert_int(ch[0].tick).is_equal(drop.tick + fly)
	assert_dict(ch[0].data).is_equal({"kind": kind, "delta": 1, "count": 1, "reason": "kill",
		"token": drop.id})
	assert_int(sim.state.relics[kind]).is_equal(1)
	assert_array(sim.state.relic_tokens).is_empty()
	# Money never changes on a kill.
	assert_int(sim.state.gold).is_equal(gold)
	assert_array(of_type(flight, T.GOLD_CHANGED)).is_empty()
	assert_array(of_type(landed, T.GOLD_CHANGED)).is_empty()


func test_fake_kill_drops_a_ghost_token_that_vanishes_and_credits_nothing() -> void:
	var sim := tsim()
	var gold := sim.state.gold
	var drop := _kill(sim, "hybrid", true)
	var fly := SimTime.ticks(sim.config.economy.token_fly_seconds)
	var vanish := SimTime.ticks(sim.config.economy.ghost_vanish_seconds)
	assert_int(vanish).is_equal(30)
	assert_int(drop.data["arrive_tick"]).is_equal(drop.tick + fly)
	assert_int(sim.state.relic_tokens.size()).is_equal(1)
	assert_array(of_type(run_to(sim, drop.tick + vanish - 1), T.RELIC_VANISHED)).is_empty()
	var at_vanish := run(sim, 1)
	var gone := of_type(at_vanish, T.RELIC_VANISHED)
	assert_int(gone.size()).is_equal(1)
	assert_int(gone[0].id).is_equal(drop.id)
	assert_dict(gone[0].data).is_equal({"token": drop.id})
	assert_array(sim.state.relic_tokens).is_empty()
	var later := run(sim, fly * 2)
	assert_array(of_type(at_vanish, T.RELICS_CHANGED)).is_empty()
	assert_array(of_type(later, T.RELICS_CHANGED)).is_empty()
	assert_dict(sim.state.relics).is_equal({"bone": 0, "amber": 0, "idol": 0, "star_stone": 0})
	assert_int(sim.state.gold).is_equal(gold)


## Two runs with the same seed: one kills a real cultist, the other a fake at the same spot
## and tick. Until the ghost's vanish tick the event streams, token lists and stashes agree.
func test_real_and_ghost_tokens_are_indistinguishable_before_the_vanish_tick() -> void:
	var runs := []
	for fake: bool in [false, true]:
		var sim := tsim(SINGLE_BONE)
		var e := put(sim, "cultist", 6.0, 1.0, fake)
		sim.drain_events()
		sim.apply_damage(e.id, 10.0, "test")
		var events := strings_of(sim.drain_events())
		var vanish := SimTime.ticks(sim.config.economy.ghost_vanish_seconds)
		var tokens := []
		var stashes := []
		for i in vanish - 1:
			sim.step()
			events.append_array(strings_of(sim.drain_events()))
			tokens.append(sim.state.relic_tokens.map(func(t: RelicToken) -> Array:
				return [t.id, t.kind, t.at, t.drop_tick, t.arrive_tick]))
			stashes.append(_stash(sim))
		runs.append([events, tokens, stashes])
	assert_array(runs[1][0]).is_equal(runs[0][0])
	assert_array(runs[1][1]).is_equal(runs[0][1])
	assert_array(runs[1][2]).is_equal(runs[0][2])
	assert_int(runs[0][1][0].size()).is_equal(1)  # the token is still in flight


# --- 4: leaks, dissolved fakes, one token per enemy --------------------------------------

func test_leaks_and_dissolved_fakes_drop_nothing() -> void:
	var sim := tsim()
	for fake: bool in [false, true]:
		var e := put(sim, "cultist", 13.5, HUGE_HP, fake)
		e.base_units_per_tick = SimTime.UNITS_PER_CELL
	var parked_fake := put(sim, "cultist", 3.0, HUGE_HP, true)
	sim.drain_events()
	var events := run(sim, 2)
	assert_array(of_type(events, T.LEAKED)).has_size(1)
	assert_array(of_type(events, T.FAKE_DISSOLVED)).has_size(1)
	sim.dissolve_fakes("wave_end")
	events = sim.drain_events()
	assert_array(ids_of(of_type(events, T.FAKE_DISSOLVED))).is_equal([parked_fake.id])
	assert_array(of_type(events, T.RELIC_DROPPED)).is_empty()
	assert_array(sim.state.relic_tokens).is_empty()
	assert_int(sim.state.next_token_id).is_equal(1)


func test_a_multi_kill_drops_one_token_per_enemy_with_fresh_token_ids() -> void:
	var sim := tsim()
	var ids: Array[int] = []
	for i in 5:
		ids.append(put(sim, "deep_one", 8.0, 1.0).id)
	sim.drain_events()
	for id in ids:
		sim.apply_damage(id, 10.0, "test")
	sim.apply_damage(ids[0], 10.0, "test")  # already dead: no second drop
	var events := sim.drain_events()
	assert_array(of_type(events, T.DIED)).has_size(5)
	var drops := of_type(events, T.RELIC_DROPPED)
	assert_array(ids_of(drops)).is_equal([1, 2, 3, 4, 5])
	assert_int(sim.state.relic_tokens.size()).is_equal(5)
	assert_int(sim.state.next_token_id).is_equal(6)


# --- 5-6: the roll and early-night luck ---------------------------------------------------

func test_drop_shares_follow_the_table_weights_and_weight_zero_never_drops() -> void:
	var sim := tsim()
	var w: Dictionary = sim.config.enemies["hybrid"].drops
	var total := 0
	for k: String in w:
		total += w[k]
	var shares := _shares(sim, "hybrid", 10000)
	for k: String in w:
		_assert_share(shares, k, float(w[k]) / total, 0.02)
	var cultist := _shares(sim, "cultist", 3000)
	assert_float(cultist["amber"]).is_equal(0.0)
	assert_float(cultist["idol"]).is_equal(0.0)
	assert_float(cultist["bone"]).is_greater(0.98)


## Luck 1.8 (a lamp lit at once): every kind but the cheapest gains (hybrid: bone stays 699,
## amber 450, idol 90, star-stone 1.8 of 1240.8).
func test_luck_scales_every_kind_but_the_cheapest() -> void:
	var sim := tsim()
	sim.state.night_luck = 1.8
	var shares := _shares(sim, "hybrid", 6000)
	var total := 699.0 + 1.8 * (250 + 50 + 1)
	_assert_share(shares, "bone", 699.0 / total, 0.02)
	_assert_share(shares, "amber", 450.0 / total, 0.02)
	_assert_share(shares, "idol", 90.0 / total, 0.015)


## The cheapest kind is the lowest price among kinds with weight > 0: with bone at weight 0,
## amber is exempt and idol gains (500 vs 900).
func test_the_luck_exempt_kind_is_the_cheapest_that_can_drop() -> void:
	var sim := tsim({"hybrid": {"drops": {"bone": 0, "amber": 500, "idol": 500,
		"star_stone": 0}}})
	sim.state.night_luck = 1.8
	var shares := _shares(sim, "hybrid", 4000)
	_assert_share(shares, "amber", 500.0 / 1400.0, 0.03)
	_assert_share(shares, "idol", 900.0 / 1400.0, 0.03)
	assert_float(shares["bone"]).is_equal(0.0)


func test_lamp_lit_at_once_on_the_real_day_gives_the_maximum_luck() -> void:
	var cfg := real_config()
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	var top := 1.0 + cfg.economy.early_night_luck_per_second * cfg.waves.build_phase_seconds
	assert_float(top).is_equal_approx(1.8, 1e-9)
	assert_float(sim.early_night_luck()).is_equal_approx(top, 1e-9)
	run(sim, 1)
	assert_float(sim.early_night_luck()).is_less(top)  # 39 whole seconds left
	var later := Simulation.new(cfg, SEED)
	later.set_spawner(WaveDirector.new(cfg.waves))
	assert_int(later.call_wave()).is_equal(R.OK)
	assert_float(later.state.night_luck).is_equal_approx(top, 1e-9)


func test_dawn_resets_the_luck_of_an_early_night() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 10)
	assert_int(sim.call_wave()).is_equal(R.OK)
	assert_float(sim.state.night_luck).is_greater(1.0)
	run(sim, 1)
	kill_real(sim)
	var events := run(sim, 1)
	assert_array(of_type(events, T.BUILD_STARTED)).has_size(1)
	assert_float(sim.state.night_luck).is_equal(1.0)


# --- 7: streams ----------------------------------------------------------------------------

func test_a_real_drop_draws_once_on_loot_and_a_fake_once_on_ghost_loot_only() -> void:
	for fake: bool in [false, true]:
		var sim := tsim()
		var e := put(sim, "hybrid", 8.0, 1.0, fake)
		var before := _rng_states(sim)
		sim.apply_damage(e.id, 10.0, "test")
		var after := _rng_states(sim)
		var moved := SimRng.Stream.GHOST_LOOT if fake else SimRng.Stream.LOOT
		for s: int in before:
			if s == moved:
				assert_int(after[s]).override_failure_message("stream %d" % s) \
					.is_equal(_one_draw_after(before[s]))
			else:
				assert_int(after[s]).override_failure_message("stream %d" % s) \
					.is_equal(before[s])


func test_fakes_never_shift_the_real_drops() -> void:
	var kinds := []
	for with_fakes: bool in [false, true]:
		var sim := tsim()
		var real: Array[String] = []
		for i in 60:
			if with_fakes:
				_kill(sim, "night_gaunt", true)
			real.append(_kill(sim, "night_gaunt").data["kind"])
			if with_fakes:
				_kill(sim, "hybrid", true)
		kinds.append(real)
	assert_array(kinds[1]).is_equal(kinds[0])
	assert_bool(kinds[0].has("bone") and kinds[0].has("amber")).is_true()  # not one kind


# --- 8: dawn -------------------------------------------------------------------------------

func test_dawn_settles_tokens_in_flight_before_the_day_starts() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1)
	assert_int(sim.call_wave()).is_equal(R.OK)
	run(sim, 1)
	var fake := put(sim, "hybrid", 3.0, 1.0, true)
	sim.apply_damage(fake.id, 10.0, "test")
	kill_real(sim)
	var drops := of_type(sim.drain_events(), T.RELIC_DROPPED)
	assert_int(drops.size()).is_equal(2)
	var ghost := drops[0]
	var real := drops[1]
	var stash := _stash(sim)
	var events := run(sim, 1)  # the wave is cleared on this tick: dawn
	var i_build := events.find(of_type(events, T.BUILD_STARTED)[0])
	var i_cleared := events.find(of_type(events, T.WAVE_CLEARED)[0])
	var wage := of_type(events, T.GOLD_CHANGED)
	assert_int(wage.size()).is_equal(1)
	assert_str(wage[0].data["reason"]).is_equal("wave_bonus")
	var credit := of_type(events, T.RELICS_CHANGED)
	assert_int(credit.size()).is_equal(1)
	assert_dict(credit[0].data).is_equal({"kind": real.data["kind"], "delta": 1,
		"count": stash[real.data["kind"]] + 1, "reason": "kill", "token": real.id})
	var gone := of_type(events, T.RELIC_VANISHED)
	assert_array(ids_of(gone)).is_equal([ghost.id])
	assert_int(credit[0].tick).is_less(real.data["arrive_tick"])
	assert_int(events.find(credit[0])).is_less(events.find(wage[0]))
	assert_int(events.find(gone[0])).is_less(events.find(wage[0]))
	assert_int(events.find(wage[0])).is_less(i_cleared)
	assert_int(i_cleared).is_less(i_build)
	assert_array(sim.state.relic_tokens).is_empty()
	assert_int(sim.state.relics[real.data["kind"]]).is_equal(stash[real.data["kind"]] + 1)
	# Nothing is credited later either.
	assert_array(of_type(run(sim, 90), T.RELICS_CHANGED)).is_empty()


# --- 9-10: selling --------------------------------------------------------------------------

func test_sell_relics_by_day_sells_every_stack_at_the_fixed_price_in_config_order() -> void:
	var sim := wsim([[group("cultist", 1)]], 10)
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	run(sim, 5)
	_set_stash(sim, {"bone": 3, "amber": 0, "idol": 2, "star_stone": 1})
	var gold := sim.state.gold
	var price := {}
	for k in sim.config.economy.relics:
		price[k.id] = k.price
	assert_dict(price).is_equal({"bone": 5, "amber": 15, "idol": 50, "star_stone": 200})
	var value: int = 3 * price["bone"] + 2 * price["idol"] + price["star_stone"]
	assert_int(sim.relics_value()).is_equal(value)
	assert_int(sim.can_sell_relics()).is_equal(R.OK)
	assert_int(sim.sell_relics()).is_equal(R.OK)
	var ev := sim.drain_events()
	assert_array(ev.map(func(x: SimEvent) -> int: return x.type)).is_equal(
		[T.RELICS_CHANGED, T.RELICS_CHANGED, T.RELICS_CHANGED, T.GOLD_CHANGED])
	assert_dict(ev[0].data).is_equal({"kind": "bone", "delta": -3, "count": 0, "reason": "sell"})
	assert_dict(ev[1].data).is_equal({"kind": "idol", "delta": -2, "count": 0, "reason": "sell"})
	assert_dict(ev[2].data).is_equal({"kind": "star_stone", "delta": -1, "count": 0,
		"reason": "sell"})
	assert_dict(ev[3].data).is_equal({"delta": value, "gold": gold + value,
		"reason": "relic_sale"})
	assert_int(sim.state.gold).is_equal(gold + value)
	assert_dict(sim.state.relics).is_equal({"bone": 0, "amber": 0, "idol": 0, "star_stone": 0})
	assert_array(sim.state.command_log.back()).is_equal([5, "sell_relics", ""])
	# The price is fixed: a later sale of the same stash pays the same.
	run(sim, 100)
	_set_stash(sim, {"bone": 3, "amber": 0, "idol": 2, "star_stone": 1})
	var gold2 := sim.state.gold
	assert_int(sim.sell_relics()).is_equal(R.OK)
	assert_int(sim.state.gold).is_equal(gold2 + value)


func test_sell_relics_of_one_kind_sells_only_that_stack() -> void:
	var sim := tsim()  # phase NONE (no WaveDirector) counts as day
	_set_stash(sim, {"bone": 4, "amber": 3, "idol": 0, "star_stone": 0})
	var gold := sim.state.gold
	assert_int(sim.sell_relics("amber")).is_equal(R.OK)
	var ev := sim.drain_events()
	assert_int(ev.size()).is_equal(2)
	assert_dict(ev[0].data).is_equal({"kind": "amber", "delta": -3, "count": 0, "reason": "sell"})
	assert_int(sim.state.gold).is_equal(gold + 3 * sim.relic_price("amber"))
	assert_dict(sim.state.relics).is_equal({"bone": 4, "amber": 0, "idol": 0, "star_stone": 0})
	assert_array(sim.state.command_log).is_equal([[0, "sell_relics", "amber"]])


func test_sell_relics_refusals_change_nothing() -> void:
	# Night: refused even with a stash.
	var night := _night_sim()
	_set_stash(night, {"bone": 2, "amber": 1, "idol": 0, "star_stone": 0})
	_assert_sell_refused(night, "", R.NOT_BUILD_PHASE)
	_assert_sell_refused(night, "bone", R.NOT_BUILD_PHASE)
	# Day: nothing to sell, an empty stack, an unknown kind.
	var day := tsim()
	_assert_sell_refused(day, "", R.NO_RELICS)
	_set_stash(day, {"bone": 2, "amber": 0, "idol": 0, "star_stone": 0})
	_assert_sell_refused(day, "amber", R.NO_RELICS)
	_assert_sell_refused(day, "gold", R.NO_RELICS)
	assert_int(day.relic_price("gold")).is_equal(0)
	# Outcome first.
	day.state.outcome = SimState.Outcome.LOST
	_assert_sell_refused(day, "", R.OUTCOME_REACHED)


func _set_stash(sim: Simulation, stash: Dictionary) -> void:
	for k: String in stash:
		sim.state.relics[k] = stash[k]


func _assert_sell_refused(sim: Simulation, kind: String, why: int) -> void:
	sim.drain_events()
	var stash := _stash(sim)
	var gold := sim.state.gold
	var log_size := sim.state.command_log.size()
	assert_int(sim.can_sell_relics(kind)).is_equal(why)
	assert_int(sim.sell_relics(kind)).is_equal(why)
	assert_array(sim.drain_events()).is_empty()
	assert_dict(sim.state.relics).is_equal(stash)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.state.command_log.size()).is_equal(log_size)


# --- 11: night rules ------------------------------------------------------------------------

func test_at_night_money_is_checked_before_the_phase_and_the_buyout_still_works() -> void:
	var sim := _night_sim(func(root: Dictionary) -> void:
		root["madness"]["exit_rule"] = "buyout")
	sim.state.gold = 0
	assert_int(sim.can_build("rifleman", TOWER)).is_equal(R.NOT_ENOUGH_GOLD)
	sim.state.gold = 100000
	assert_int(sim.can_build("rifleman", TOWER)).is_equal(R.NOT_BUILD_PHASE)
	assert_int(sim.sell_tower(999)).is_equal(R.NO_SUCH_TOWER)
	sim.state.sanity = 0.0
	sim.state.sanity_state = sim.sanity_state_for(0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	assert_int(sim.buy_sanity()).is_equal(R.OK)
	assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)


# --- 12: day length ------------------------------------------------------------------------

func test_the_real_day_lasts_forty_seconds() -> void:
	var cfg := real_config()
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	var day := SimTime.ticks(40.0)
	assert_int(sim.state.build_ticks_left).is_equal(day)
	sim.drain_events()
	var events := run(sim, day)
	var started := of_type(events, T.WAVE_STARTED)
	assert_int(started.size()).is_equal(1)
	assert_int(started[0].tick).is_equal(day)
	assert_bool(started[0].data["early"]).is_false()


# --- 13: config ----------------------------------------------------------------------------

func test_config_rejects_bad_drop_tables_with_the_path() -> void:
	var cases := [
		["enemies.cultist.drops.gold", "unknown relic kind",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["drops"]["gold"] = 1],
		["enemies.cultist.drops.bone", "must be >= 0",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["drops"]["bone"] = -1],
		["enemies.cultist.drops", "weights must sum to > 0",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["drops"] = {"bone": 0,
				"star_stone": 0}],
		["enemies.cultist.drops", "must not be empty",
			func(d: Dictionary) -> void: d["enemies"]["cultist"]["drops"] = {}],
	]
	for c: Array in cases:
		var r := load_json_edit(E, c[2])
		assert_rejected(r, E, c[0], c[1])


func test_config_rejects_a_ghost_vanish_not_shorter_than_the_flight() -> void:
	for v: float in [2.0, 3.0]:
		var r := load_json_edit(EC, func(d: Dictionary) -> void: d["ghost_vanish_seconds"] = v)
		assert_rejected(r, EC, "ghost_vanish_seconds", "must be < token_fly_seconds")


func test_config_rejects_an_empty_relic_list() -> void:
	var r := load_json_edit(EC, func(d: Dictionary) -> void: d["relics"] = {})
	assert_rejected(r, EC, "relics", "must not be empty")


# --- 14: replay ----------------------------------------------------------------------------

const REPLAY_TICKS := 900
const REPLAY_TOWERS := [Vector2i(3, 1), Vector2i(5, 1), Vector2i(7, 1)]


## One run with three riflemen built on tick 0, the lamp lit on tick 5 (luck) and, on the first
## tick of the second day with a stash, sell_relics(). Returns [event strings + final state
## line, command_log].
func _record() -> Array:
	var sim := _replay_sim()
	var out: Array[String] = []
	var sold := false
	for t in REPLAY_TICKS:
		if t == 0:
			for cell: Vector2i in REPLAY_TOWERS:
				assert_int(sim.build_tower("rifleman", cell)).is_equal(R.OK)
		if t == 5:
			sim.call_wave()
		if not sold and sim.state.wave_index == 1 and sim.can_sell_relics() == R.OK:
			sim.sell_relics()
			sold = true
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	assert_bool(sold).override_failure_message("no relics to sell by day 2").is_true()
	out.append(_state_line(sim))
	return [out, sim.state.command_log.duplicate(true)]


func _replay(commands: Array) -> Array[String]:
	var sim := _replay_sim()
	var out: Array[String] = []
	for t in REPLAY_TICKS:
		for c: Array in commands:
			if int(c[0]) == sim.state.tick:
				match c[1]:
					"build": sim.build_tower(c[2], c[3])
					"call_wave": sim.call_wave()
					"sell_relics": sim.sell_relics(c[2])
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append(_state_line(sim))
	return out


func _replay_sim() -> Simulation:
	return wsim([[group("cultist", 4, 1.0)], [group("cultist", 1)]], 5)


func _state_line(sim: Simulation) -> String:
	var s := sim.state
	return "tick=%d gold=%d relics=%s tokens=%d next_token=%d luck=%f phase=%d wave=%d" % [
		s.tick, s.gold, s.relics, s.relic_tokens.size(), s.next_token_id, s.night_luck,
		s.phase, s.wave_index]


func test_replaying_sell_relics_and_an_early_night_gives_the_same_run() -> void:
	var first := _record()
	var commands: Array = first[1]
	var names: Array = commands.map(func(c: Array) -> String: return c[1])
	assert_array(names).is_equal(["build", "build", "build", "call_wave", "sell_relics"])
	assert_array(commands[3]).is_equal([5, "call_wave"])
	var events: Array[String] = first[0]
	assert_bool(events.any(func(s: String) -> bool: return s.contains("relic_sale"))).is_true()
	assert_array(_replay(commands)).is_equal(events)
	# Controls: without the sale, or without the early night, the run differs.
	assert_bool(_replay(commands.slice(0, 4)) == events).is_false()
	assert_bool(_replay(commands.filter(func(c: Array) -> bool: return c[1] != "call_wave"))
		== events).is_false()
