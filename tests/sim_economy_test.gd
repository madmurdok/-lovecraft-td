class_name SimEconomyTest
extends WaveTestBase
## LT-81 (B6 of LT-80, docs/design/LT-80-sim-split.md section 7): EconomySystem owns the relic
## stash, the tokens, the sell commands, the dawn wage and the night luck. Pins them standalone
## (a SimContext, no Simulation), the facade forwarders, and the `_roll_drop` RNG order.
## The overall check stays the golden digest; this file only reaches the system directly.

const T := SimEvent.Type
const KINDS := ["amber", "bone", "idol", "star_stone"]  ## config order

var _ctx: SimContext
var _eco: EconomySystem


func before_test() -> void:
	_ctx = SimContext.new(tconfig(), SEED)
	_eco = EconomySystem.new(_ctx)


func _types(events: Array[SimEvent]) -> Array:
	return events.map(func(e: SimEvent) -> int: return e.type)


## The stream's draw sequence a fresh run with SEED would see (same seeding as SimRng).
func _fresh(stream: SimRng.Stream) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = SEED * SimRng.STREAM_SEED_STRIDE + int(stream)
	return g


## The kind `_roll_drop` must pick for one draw `r01` (0..1) of `def`'s table at `luck`.
func _expected_kind(def: EnemyDef, luck: float, r01: float) -> String:
	var cheapest := ""
	for kind: String in def.drops:
		if def.drops[kind] > 0 and (cheapest == "" or _eco.relic_price(kind) < _eco.relic_price(cheapest)):
			cheapest = kind
	var weights := {}
	var total := 0.0
	for kind: String in def.drops:
		var w := float(def.drops[kind]) * (1.0 if kind == cheapest else luck)
		weights[kind] = w
		total += w
	var r := r01 * total
	for kind: String in def.drops:
		if weights[kind] <= 0.0:
			continue
		if r < weights[kind]:
			return kind
		r -= weights[kind]
	return cheapest


## A parked enemy of a throwaway sim, to drop tokens for (the system never sees that sim).
func _enemy(fake := false) -> SimEnemy:
	return put(tsim(), "hybrid", 8.0, HUGE_HP, fake)


# --- standalone: stash, prices, sell -------------------------------------------------------

func test_a_standalone_system_starts_with_the_starting_gold_and_an_empty_stash() -> void:
	assert_int(_ctx.state.gold).is_equal(_ctx.config.economy.starting_gold)
	assert_array(_ctx.state.relics.keys()).is_equal(KINDS)
	assert_dict(_ctx.state.relics).is_equal({"bone": 0, "amber": 0, "idol": 0, "star_stone": 0})
	assert_int(_ctx.state.next_token_id).is_equal(1)


func test_relic_price_and_relics_value_read_the_config_prices() -> void:
	for kind in KINDS:
		assert_int(_eco.relic_price(kind)).is_equal(_ctx.config.economy.relic(kind).price)
	assert_int(_eco.relic_price("gold")).is_equal(0)  # unknown kind
	assert_int(_eco.relics_value()).is_equal(0)
	_eco.add_relics("bone", 3, "kill", 1)
	_eco.add_relics("idol", 2, "kill", 2)
	assert_int(_eco.relics_value()).is_equal(3 * _eco.relic_price("bone") + 2 * _eco.relic_price("idol"))
	assert_int(_eco.relic_price("idol")).is_greater(0)


func test_can_sell_relics_reports_the_first_failing_reason_in_order() -> void:
	var s := _ctx.state
	s.phase = SimState.Phase.WAVE
	s.outcome = SimState.Outcome.LOST
	# every reason holds: the outcome comes first, then the night, then the empty stash
	assert_int(_eco.can_sell_relics()).is_equal(R.OUTCOME_REACHED)
	s.outcome = SimState.Outcome.NONE
	assert_int(_eco.can_sell_relics()).is_equal(R.NOT_BUILD_PHASE)
	s.phase = SimState.Phase.BUILD
	assert_int(_eco.can_sell_relics()).is_equal(R.NO_RELICS)
	assert_int(_eco.can_sell_relics("bone")).is_equal(R.NO_RELICS)
	_eco.add_relics("amber", 1, "kill", 1)
	assert_int(_eco.can_sell_relics()).is_equal(R.OK)
	assert_int(_eco.can_sell_relics("amber")).is_equal(R.OK)
	assert_int(_eco.can_sell_relics("bone")).is_equal(R.NO_RELICS)  # other kind is empty
	assert_int(_eco.can_sell_relics("nope")).is_equal(R.NO_RELICS)  # unknown kind
	assert_int(_ctx.state.command_log.size()).is_equal(0)  # a query changes nothing


func test_sell_relics_logs_the_command_and_emits_per_kind_then_one_gold_change() -> void:
	_eco.add_relics("idol", 1, "kill", 1)  # stocked out of config order on purpose
	_eco.add_relics("bone", 2, "kill", 2)
	_ctx.events.clear()
	_ctx.state.tick = 5
	var gold := _ctx.state.gold
	var value := _eco.relics_value()
	assert_int(_eco.sell_relics()).is_equal(R.OK)
	assert_array(_ctx.state.command_log).is_equal([[5, "sell_relics", ""]])
	assert_array(_types(_ctx.events)).is_equal([T.RELICS_CHANGED, T.RELICS_CHANGED, T.GOLD_CHANGED])
	assert_dict(_ctx.events[0].data).is_equal({"kind": "bone", "delta": -2, "count": 0, "reason": "sell"})
	assert_dict(_ctx.events[1].data).is_equal({"kind": "idol", "delta": -1, "count": 0, "reason": "sell"})
	assert_dict(_ctx.events[2].data).is_equal({"delta": value, "gold": gold + value, "reason": "relic_sale"})
	assert_int(_ctx.state.gold).is_equal(gold + value)
	assert_int(_eco.relics_value()).is_equal(0)


func test_sell_relics_of_one_kind_leaves_the_rest_and_a_refusal_logs_nothing() -> void:
	_eco.add_relics("bone", 2, "kill", 1)
	_eco.add_relics("amber", 1, "kill", 2)
	_ctx.events.clear()
	assert_int(_eco.sell_relics("bone")).is_equal(R.OK)
	assert_array(_ctx.state.command_log).is_equal([[0, "sell_relics", "bone"]])
	assert_int(_ctx.state.relics["bone"]).is_equal(0)
	assert_int(_ctx.state.relics["amber"]).is_equal(1)
	assert_int(_ctx.events.size()).is_equal(2)
	_ctx.events.clear()
	var gold := _ctx.state.gold
	assert_int(_eco.sell_relics("bone")).is_equal(R.NO_RELICS)
	_ctx.state.phase = SimState.Phase.WAVE
	assert_int(_eco.sell_relics()).is_equal(R.NOT_BUILD_PHASE)
	assert_int(_ctx.state.command_log.size()).is_equal(1)
	assert_int(_ctx.state.gold).is_equal(gold)
	assert_array(_ctx.events).is_empty()


func test_sell_refund_is_the_ratio_of_what_was_spent_rounded_once() -> void:
	var t := SimTower.new()
	var ratio := _ctx.config.economy.sell_refund_ratio
	for spent in [0, 1, 7, 100, 333]:
		t.spent = spent
		assert_int(_eco.sell_refund(t)).is_equal(roundi(spent * ratio))
	t.spent = 100
	assert_int(_eco.sell_refund(t)).is_greater(0)


# --- standalone: dawn wage and night luck ---------------------------------------------------

func test_award_wave_bonus_pays_base_plus_per_wave_and_is_zero_after_the_outcome() -> void:
	var econ := _ctx.config.economy
	var gold := _ctx.state.gold
	assert_int(_eco.award_wave_bonus(3)).is_equal(econ.wave_bonus_base + econ.wave_bonus_per_wave * 3)
	assert_int(_ctx.state.gold).is_equal(gold + econ.wave_bonus_base + econ.wave_bonus_per_wave * 3)
	assert_int(_ctx.events.size()).is_equal(1)
	assert_dict(_ctx.events[0].data).is_equal({"delta": _ctx.state.gold - gold, "gold": _ctx.state.gold,
		"reason": "wave_bonus"})
	assert_int(_ctx.events[0].id).is_equal(0)
	assert_array(_ctx.state.command_log).is_empty()  # not a player command
	_ctx.state.outcome = SimState.Outcome.WON
	_ctx.events.clear()
	gold = _ctx.state.gold
	assert_int(_eco.award_wave_bonus(3)).is_equal(0)
	assert_int(_ctx.state.gold).is_equal(gold)
	assert_array(_ctx.events).is_empty()


func test_early_night_luck_takes_both_branches_of_has_director() -> void:
	var rate := _ctx.config.economy.early_night_luck_per_second
	assert_float(rate).is_greater(0.0)
	var s := _ctx.state
	s.phase = SimState.Phase.BUILD
	s.build_ticks_left = SimTime.ticks(10.0) + 5  # 10 whole seconds and a bit
	assert_float(_eco.early_night_luck(true)).is_equal_approx(1.0 + rate * 10, 1e-9)
	assert_float(_eco.early_night_luck(false)).is_equal(1.0)  # no director: call_wave is refused
	s.phase = SimState.Phase.WAVE
	assert_float(_eco.early_night_luck(true)).is_equal(1.0)
	s.phase = SimState.Phase.BUILD
	s.outcome = SimState.Outcome.LOST
	assert_float(_eco.early_night_luck(true)).is_equal(1.0)


# --- standalone: tokens ---------------------------------------------------------------------

func test_drop_token_takes_ids_in_order_and_emits_the_drop_event() -> void:
	var e := _enemy()
	_ctx.state.tick = 9
	_eco.drop_token(e)
	_eco.drop_token(e)
	assert_int(_ctx.state.next_token_id).is_equal(3)
	assert_array(_ctx.state.relic_tokens.map(func(t: RelicToken) -> int: return t.id)).is_equal([1, 2])
	assert_array(_types(_ctx.events)).is_equal([T.RELIC_DROPPED, T.RELIC_DROPPED])
	var fly := SimTime.ticks(_ctx.config.economy.token_fly_seconds)
	var d := _ctx.events[0]
	assert_int(d.id).is_equal(1)
	assert_int(d.tick).is_equal(9)
	assert_array(d.data.keys()).contains_exactly_in_any_order(["token", "kind", "at", "arrive_tick"])
	assert_int(d.data["arrive_tick"]).is_equal(9 + fly)
	assert_vector(d.data["at"]).is_equal(e.route.position_at(e.distance))
	assert_array(KINDS).contains([d.data["kind"]])
	assert_int(_ctx.state.next_id).is_equal(1)  # a token id is not an entity id


func test_a_real_token_is_credited_at_its_arrive_tick_not_before_in_id_order() -> void:
	var e := _enemy()
	_eco.drop_token(e)
	_eco.drop_token(e)
	var fly := SimTime.ticks(_ctx.config.economy.token_fly_seconds)
	var kinds: Array = _ctx.state.relic_tokens.map(func(t: RelicToken) -> String: return t.kind)
	_ctx.events.clear()
	_ctx.state.tick = fly - 1
	_eco.settle_tokens()
	assert_array(_ctx.events).is_empty()
	assert_int(_ctx.state.relic_tokens.size()).is_equal(2)
	_ctx.state.tick = fly
	_eco.settle_tokens()
	assert_array(_types(_ctx.events)).is_equal([T.RELICS_CHANGED, T.RELICS_CHANGED])
	assert_array(_ctx.events.map(func(x: SimEvent) -> int: return x.id)).is_equal([1, 2])
	assert_dict(_ctx.events[0].data).is_equal({"kind": kinds[0], "delta": 1,
		"count": 1, "reason": "kill", "token": 1})
	assert_array(_ctx.state.relic_tokens).is_empty()


func test_a_ghost_token_vanishes_at_drop_tick_plus_vanish_and_credits_nothing() -> void:
	var e := _enemy(true)
	_ctx.state.tick = 4
	_eco.drop_token(e)
	var vanish := SimTime.ticks(_ctx.config.economy.ghost_vanish_seconds)
	var fly := SimTime.ticks(_ctx.config.economy.token_fly_seconds)
	assert_int(vanish).is_less(fly)  # the ghost goes before a real token would land
	_ctx.events.clear()
	_ctx.state.tick = 4 + vanish - 1
	_eco.settle_tokens()
	assert_array(_ctx.events).is_empty()
	_ctx.state.tick = 4 + vanish
	_eco.settle_tokens()
	assert_array(_types(_ctx.events)).is_equal([T.RELIC_VANISHED])
	assert_dict(_ctx.events[0].data).is_equal({"token": 1})
	assert_array(_ctx.state.relic_tokens).is_empty()
	assert_dict(_ctx.state.relics).is_equal({"bone": 0, "amber": 0, "idol": 0, "star_stone": 0})
	assert_bool(_eco._ghost_tokens.has(1)).is_false()  # forgotten once vanished


func test_the_drop_event_of_a_ghost_looks_like_a_real_one() -> void:
	var real := _enemy()
	var fake := _enemy(true)
	_eco.drop_token(real)
	_eco.drop_token(fake)
	assert_array(_ctx.events[0].data.keys()).is_equal(_ctx.events[1].data.keys())
	assert_int(_ctx.events[1].data["arrive_tick"]).is_equal(_ctx.events[0].data["arrive_tick"])
	assert_bool(_eco._ghost_tokens.has(2)).is_true()
	assert_bool(_eco._ghost_tokens.has(1)).is_false()


func test_settle_all_tokens_settles_everything_in_id_order_and_empties_the_list() -> void:
	_eco.drop_token(_enemy())
	_eco.drop_token(_enemy(true))
	_eco.drop_token(_enemy())
	_ctx.events.clear()
	_ctx.state.tick = 1  # nothing is due yet; dawn settles anyway
	_eco.settle_all_tokens()
	assert_array(_types(_ctx.events)).is_equal([T.RELICS_CHANGED, T.RELIC_VANISHED, T.RELICS_CHANGED])
	assert_array(_ctx.events.map(func(x: SimEvent) -> int: return x.id)).is_equal([1, 2, 3])
	assert_array(_ctx.state.relic_tokens).is_empty()
	var total := 0
	for k: String in _ctx.state.relics:
		total += _ctx.state.relics[k]
	assert_int(total).is_equal(2)  # the two real tokens only
	_ctx.events.clear()
	_eco.settle_all_tokens()
	assert_array(_ctx.events).is_empty()


# --- standalone: _roll_drop RNG order -------------------------------------------------------

func test_roll_drop_draws_once_per_call_on_the_stream_it_is_given() -> void:
	var def: EnemyDef = _ctx.config.enemies["hybrid"]
	var want := _fresh(SimRng.Stream.LOOT)
	var got: Array[String] = []
	var expected: Array[String] = []
	for i in 40:
		got.append(_eco._roll_drop(def, SimRng.Stream.LOOT))
		expected.append(_expected_kind(def, 1.0, want.randf()))
	assert_array(got).is_equal(expected)
	assert_array(got.duplicate()).contains(["bone"])
	# the other streams were never touched: their next draw is still their first
	for s: SimRng.Stream in [SimRng.Stream.GHOST_LOOT, SimRng.Stream.SPAWN, SimRng.Stream.COMBAT]:
		assert_float(_ctx.rng(s).randf()).is_equal(_fresh(s).randf())


func test_roll_drop_multiplies_every_weight_but_the_cheapest_by_the_night_luck() -> void:
	var def: EnemyDef = _ctx.config.enemies["hybrid"]
	_ctx.state.night_luck = 8.0
	var want := _fresh(SimRng.Stream.GHOST_LOOT)
	var got: Array[String] = []
	var expected: Array[String] = []
	for i in 60:
		got.append(_eco._roll_drop(def, SimRng.Stream.GHOST_LOOT))
		expected.append(_expected_kind(def, 8.0, want.randf()))
	assert_array(got).is_equal(expected)
	var plain: Array[String] = []
	var g := _fresh(SimRng.Stream.GHOST_LOOT)
	for i in 60:
		plain.append(_expected_kind(def, 1.0, g.randf()))
	assert_array(got).is_not_equal(plain)  # the luck changed the picks


func test_drop_token_rolls_real_kills_on_loot_and_fakes_on_ghost_loot() -> void:
	var def: EnemyDef = _ctx.config.enemies["hybrid"]
	var loot := _fresh(SimRng.Stream.LOOT)
	var ghost := _fresh(SimRng.Stream.GHOST_LOOT)
	var want_real: Array[String] = []
	var want_fake: Array[String] = []
	var real := _enemy()
	var fake := _enemy(true)
	for i in 12:
		want_real.append(_expected_kind(def, 1.0, loot.randf()))
		want_fake.append(_expected_kind(def, 1.0, ghost.randf()))
		_eco.drop_token(real)
		_eco.drop_token(fake)
	var got_real: Array[String] = []
	var got_fake: Array[String] = []
	for tok in _ctx.state.relic_tokens:
		(got_fake if _eco._ghost_tokens.has(tok.id) else got_real).append(tok.kind)
	assert_array(got_real).is_equal(want_real)
	assert_array(got_fake).is_equal(want_fake)


# --- facade forwarders ----------------------------------------------------------------------

func _stocked_sim() -> Simulation:
	var sim := tsim()
	sim._add_relics("bone", 4, "kill", 1)
	sim._add_relics("star_stone", 1, "kill", 2)
	sim.drain_events()
	return sim


func test_the_facade_forwarders_return_what_the_system_returns() -> void:
	var sim := _stocked_sim()
	var eco: EconomySystem = sim._economy
	for kind in KINDS + ["nope"]:
		assert_int(sim.relic_price(kind)).is_equal(eco.relic_price(kind))
	assert_int(sim.relics_value()).is_equal(eco.relics_value())
	assert_int(sim.relics_value()).is_greater(0)
	for kind in ["", "bone", "amber", "nope"]:
		assert_int(sim.can_sell_relics(kind)).is_equal(eco.can_sell_relics(kind))
	var t := SimTower.new()
	t.spent = 77
	assert_int(sim.sell_refund(t)).is_equal(eco.sell_refund(t))
	assert_int(sim.sell_refund(t)).is_greater(0)
	var gold := sim.state.gold
	assert_int(sim.award_wave_bonus(2)).is_equal(sim.config.economy.wave_bonus_base
		+ sim.config.economy.wave_bonus_per_wave * 2)
	assert_int(sim.state.gold).is_greater(gold)


func test_the_facade_sell_relics_is_the_systems_sell_relics() -> void:
	var a := _stocked_sim()
	var b := _stocked_sim()
	assert_int(a.sell_relics("bone")).is_equal(R.OK)
	assert_int(b._economy.sell_relics("bone")).is_equal(R.OK)
	var flat := func(sim: Simulation) -> Array:
		return sim.drain_events().map(func(e: SimEvent) -> Array: return [e.type, e.tick, e.id, e.data])
	assert_array(flat.call(a)).is_equal(flat.call(b))
	assert_array(a.state.command_log).is_equal(b.state.command_log)
	assert_dict(a.state.relics).is_equal(b.state.relics)
	assert_int(a.state.gold).is_equal(b.state.gold)
	assert_int(a.sell_relics("bone")).is_equal(b._economy.sell_relics("bone"))  # both NO_RELICS


func test_the_facade_settle_all_tokens_forwards() -> void:
	var sim := tsim()
	sim._economy.drop_token(put(sim, "hybrid", 8.0))
	assert_int(sim.state.relic_tokens.size()).is_equal(1)
	sim.drain_events()
	sim.settle_all_tokens()
	assert_array(sim.state.relic_tokens).is_empty()
	assert_array(_types(sim.drain_events())).is_equal([T.RELICS_CHANGED])


func test_the_facade_early_night_luck_passes_whether_it_has_a_wave_director() -> void:
	var plain := tsim()
	plain.state.phase = SimState.Phase.BUILD
	plain.state.build_ticks_left = SimTime.ticks(10.0)
	assert_float(plain.early_night_luck()).is_equal(1.0)  # no director
	var sim := wsim([[group("cultist", 1)]], 25)
	run(sim, 1)  # 749 ticks left = 24 whole seconds
	var rate := sim.config.economy.early_night_luck_per_second
	assert_float(sim.early_night_luck()).is_equal_approx(1.0 + rate * 24, 1e-9)
	assert_float(sim.early_night_luck()).is_equal(sim._economy.early_night_luck(true))
	assert_float(sim._economy.early_night_luck(false)).is_equal(1.0)
