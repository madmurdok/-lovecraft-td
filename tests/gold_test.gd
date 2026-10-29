class_name GoldTest
extends TowerTestBase
## LT-6 gold economy: kill rewards, wave bonus, sell refund (behaviours 10-15).

const R := Simulation.CommandResult


# --- kill rewards ------------------------------------------------------------

func test_tower_kill_pays_the_enemy_reward_right_after_died() -> void:
	for enemy_id: String in ["cultist", "hybrid"]:
		var sim := tsim()
		build(sim, "rifleman")
		var reward: int = sim.config.enemies[enemy_id].reward
		var e := put(sim, enemy_id, 8.0, 1.0)
		var gold := sim.state.gold
		sim.drain_events()
		var events := run(sim, 1)
		var died := of_type(events, SimEvent.Type.DIED)
		var paid := of_type(events, SimEvent.Type.GOLD_CHANGED)
		assert_int(died.size()).is_equal(1)
		assert_int(paid.size()).is_equal(1)
		assert_int(events.find(paid[0])).is_equal(events.find(died[0]) + 1)
		assert_int(paid[0].id).is_equal(e.id)
		assert_dict(paid[0].data).is_equal({"delta": reward, "gold": gold + reward,
			"reason": "kill"})
		assert_int(sim.state.gold).is_equal(gold + reward)


func test_two_towers_killing_one_enemy_in_a_tick_pay_one_reward() -> void:
	var sim := tsim()
	build(sim, "rifleman", TOWER)
	build(sim, "harpooner", TOWER + Vector2i.RIGHT)
	var reward: int = sim.config.enemies["cultist"].reward
	put(sim, "cultist", 8.0, 1.0)
	var gold := sim.state.gold
	sim.drain_events()
	var events := run(sim, 1)
	assert_array(of_type(events, SimEvent.Type.DIED)).has_size(1)
	var paid := of_type(events, SimEvent.Type.GOLD_CHANGED)
	assert_int(paid.size()).is_equal(1)
	assert_int(sim.state.gold).is_equal(gold + reward)


func test_a_second_damage_source_in_the_same_tick_cannot_kill_again() -> void:
	var sim := tsim()
	var reward: int = sim.config.enemies["cultist"].reward
	var e := put(sim, "cultist", 8.0, 1.0)
	var gold := sim.state.gold
	sim.drain_events()
	assert_float(sim.apply_damage(e.id, 100.0, "test")).is_greater(0.0)
	assert_float(sim.apply_damage(e.id, 100.0, "test")).is_equal(0.0)
	var events := sim.drain_events()
	assert_array(of_type(events, SimEvent.Type.DIED)).has_size(1)
	assert_array(of_type(events, SimEvent.Type.GOLD_CHANGED)).has_size(1)
	assert_int(sim.state.gold).is_equal(gold + reward)


func test_fake_kill_pays_nothing_but_still_emits_died() -> void:
	var sim := tsim()
	build(sim, "rifleman")
	put(sim, "cultist", 8.0, 1.0, true)
	var gold := sim.state.gold
	sim.drain_events()
	var events := run(sim, 1)
	assert_array(of_type(events, SimEvent.Type.SHOT)).has_size(1)
	assert_array(of_type(events, SimEvent.Type.DIED)).has_size(1)
	assert_array(of_type(events, SimEvent.Type.GOLD_CHANGED)).is_empty()
	assert_int(sim.state.gold).is_equal(gold)


# --- wave bonus --------------------------------------------------------------

func test_wave_bonus_matches_the_gdd_formula_and_config() -> void:
	var econ := tconfig().economy
	assert_int(econ.wave_bonus_base).is_equal(50)  # GDD §6: 50 + 10 * n
	assert_int(econ.wave_bonus_per_wave).is_equal(10)


func test_award_wave_bonus_adds_base_plus_step_times_wave() -> void:
	for n in [1, 2, 3, 7, 20]:
		var sim := tsim()
		var econ := sim.config.economy
		var want: int = econ.wave_bonus_base + econ.wave_bonus_per_wave * n
		var gold := sim.state.gold
		assert_int(sim.award_wave_bonus(n)).is_equal(want)
		assert_int(sim.state.gold).is_equal(gold + want)
		var ev := sim.drain_events()
		assert_int(ev.size()).is_equal(1)
		assert_int(ev[0].type).is_equal(SimEvent.Type.GOLD_CHANGED)
		assert_int(ev[0].id).is_equal(0)
		assert_dict(ev[0].data).is_equal({"delta": want, "gold": gold + want,
			"reason": "wave_bonus"})


func test_wave_bonus_is_not_a_logged_command() -> void:
	var sim := tsim()
	sim.award_wave_bonus(1)
	assert_array(sim.state.command_log).is_empty()


func test_wave_bonus_after_outcome_is_zero_and_changes_nothing() -> void:
	var sim := tsim({}, 1)
	var leaker := put(sim, "cultist", 14.0)
	leaker.distance = leaker.route.length
	run(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)
	var gold := sim.state.gold
	assert_int(sim.award_wave_bonus(3)).is_equal(0)
	assert_int(sim.state.gold).is_equal(gold)
	assert_array(sim.drain_events()).is_empty()


# --- sell --------------------------------------------------------------------

func test_sell_refund_ratio_is_seventy_percent_per_the_gdd() -> void:
	assert_float(tconfig().economy.sell_refund_ratio).is_equal(0.7)


func test_sell_refunds_the_rounded_ratio_of_the_cost_and_frees_the_cell() -> void:
	for def_id: String in ["rifleman", "harpooner"]:
		var sim := tsim()
		var cost: int = sim.config.towers[def_id].cost
		var refund := roundi(cost * sim.config.economy.sell_refund_ratio)
		var t := build(sim, def_id)
		var gold := sim.state.gold
		sim.drain_events()
		assert_int(sim.sell_tower(t.id)).is_equal(R.OK)
		assert_int(sim.state.gold).is_equal(gold + refund)
		assert_int(refund).is_less(cost)
		assert_object(sim.tower_by_id(t.id)).is_null()
		assert_bool(sim.state.tower_at.has(TOWER)).is_false()
		assert_array(sim.state.towers).is_empty()
		assert_array(sim.state.command_log.back()).is_equal([0, "sell", t.id])
		var ev := sim.drain_events()
		assert_int(ev.size()).is_equal(2)
		assert_int(ev[0].type).is_equal(SimEvent.Type.TOWER_SOLD)
		assert_int(ev[0].id).is_equal(t.id)
		assert_dict(ev[0].data).is_equal({"def": def_id, "cell": TOWER, "refund": refund})
		assert_int(ev[1].type).is_equal(SimEvent.Type.GOLD_CHANGED)
		assert_dict(ev[1].data).is_equal({"delta": refund, "gold": gold + refund,
			"reason": "sell"})
		# The cell is free again.
		assert_int(sim.build_tower(def_id, TOWER)).is_equal(R.OK)


func test_sell_refund_rounds_to_nearest_not_down() -> void:
	# 57 * 0.7 = 39.9: floor gives 39, nearest gives 40. Seed costs (50, 70) round exactly.
	var sim := tsim()
	var t := build(sim, "rifleman")
	t.spent = 57
	var gold := sim.state.gold
	assert_int(sim.sell_refund(t)).is_equal(40)
	assert_int(sim.sell_tower(t.id)).is_equal(R.OK)
	assert_int(sim.state.gold).is_equal(gold + 40)


func test_sell_applies_between_ticks_and_logs_the_current_tick() -> void:
	var sim := tsim()
	var t := build(sim, "rifleman")
	run(sim, 5)
	assert_int(sim.sell_tower(t.id)).is_equal(R.OK)
	assert_array(sim.state.command_log.back()).is_equal([5, "sell", t.id])


func test_sold_tower_stops_firing() -> void:
	var sim := tsim()
	var t := build(sim, "rifleman")
	var e := put(sim, "cultist", 8.0)
	run(sim, 1)
	var hp := e.hp
	sim.sell_tower(t.id)
	sim.drain_events()
	assert_array(of_type(run(sim, 2 * fire_ticks("rifleman")), SimEvent.Type.SHOT)).is_empty()
	assert_float(e.hp).is_equal(hp)


func test_selling_an_unknown_or_already_sold_tower_is_rejected_unchanged() -> void:
	var sim := tsim()
	var t := build(sim, "rifleman")
	sim.sell_tower(t.id)
	sim.drain_events()
	var gold := sim.state.gold
	var log_size := sim.state.command_log.size()
	for id in [t.id, 9999, 0, -1]:
		assert_int(sim.sell_tower(id)).is_equal(R.NO_SUCH_TOWER)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.state.command_log.size()).is_equal(log_size)
	assert_array(sim.drain_events()).is_empty()


func test_sell_after_outcome_is_refused_and_keeps_the_tower() -> void:
	var sim := tsim({}, 1)
	var t := build(sim, "rifleman")
	var leaker := put(sim, "cultist", 14.0)
	leaker.distance = leaker.route.length
	run(sim, 1)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.LOST)
	var gold := sim.state.gold
	sim.drain_events()
	assert_int(sim.sell_tower(t.id)).is_equal(R.OUTCOME_REACHED)
	assert_int(sim.state.gold).is_equal(gold)
	assert_object(sim.tower_by_id(t.id)).is_not_null()
	assert_array(sim.drain_events()).is_empty()
