class_name TowerModifierTest
extends TowerTestBase
## LT-105 (docs/design/LT-105-tower-modifiers.md §5): the tower modifier channel on SimTower.
## add_modifiers composes (power / interval multiply in call order, miss_add sums, the bools
## OR); slot 1 of every step resets it; light writes it every tick; combat (fire_towers,
## apply_auras, _cast_banish, _summon) reads it, not lit / shadowed: the channel is set by hand
## on dark towers (lit = false) and the systems are called directly. ignore_miss wins over
## miss_add with no COMBAT draw; disabled (Q2) keeps the cooldown counting, fires nothing,
## draws nothing, switches its aura off, leaves its light casting and its allies; gate and
## circle cooldowns ignore interval_mult (Q4). Simulation.tower_mults is t.modifiers();
## TowerRules.effective is effective_with(light_effect(..)) bit for bit.

const T := SimEvent.Type
const RIFLE := "rifleman"
const SL := "searchlight"
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"
const SK := "silver_key"
const SC := "summoning_circle"
const NEUTRAL := {"power_mult": 1.0, "interval_mult": 1.0, "miss_add": 0.0,
	"ignore_miss": false, "disabled": false}


# --- helpers ---------------------------------------------------------------------------

func _sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	return sim


func _at(x: int) -> Vector2i:
	return Vector2i(x, 1)


func _combat_state(sim: Simulation) -> int:
	return sim.rng(SimRng.Stream.COMBAT).state


func _madness_state(sim: Simulation) -> int:
	return sim.rng(SimRng.Stream.MADNESS).state


## The light rule's values for `t`'s flags, as the channel holds them (five keys).
func _light(sim: Simulation, t: SimTower) -> Dictionary:
	return TowerRules.light_effect(t.def, sim.config, t.lit, t.shadowed).merged({"disabled": false})


## A dark rifle at TOWER with a cultist parked in range; events drained.
func _rifle(sim: Simulation) -> Array:
	var t := build(sim, RIFLE)
	var e := put(sim, "cultist", 7.0)
	sim.drain_events()
	assert_array([t.lit, t.shadowed]).is_equal([false, false])
	return [t, e]


# --- 1: composition (D4) -----------------------------------------------------------------

func test_add_modifiers_multiplies_in_call_order_sums_miss_and_ors_the_bools() -> void:
	# Values where the grouping shows in the last bit: (a*b)*c != a*(b*c).
	var a := 0.1
	var b := 0.2
	var c := 0.3
	assert_bool((a * b) * c != a * (b * c)).override_failure_message("probe values").is_true()
	var t := SimTower.new()
	t.add_modifiers(a, c, 0.1)
	t.add_modifiers(b, b, 0.2, true, true)
	t.add_modifiers(c, a, 0.3, false, false)
	assert_bool(t.power_mult == (a * b) * c).override_failure_message(
		"power %s, want (a*b)*c %s" % [t.power_mult, (a * b) * c]).is_true()
	assert_bool(t.interval_mult == (c * b) * a).override_failure_message(
		"interval %s, want (c*b)*a %s" % [t.interval_mult, (c * b) * a]).is_true()
	assert_bool(t.miss_add == (0.1 + 0.2) + 0.3).is_true()
	# A later false does not clear an earlier true.
	assert_bool(t.ignore_miss).is_true()
	assert_bool(t.disabled).is_true()
	assert_dict(t.modifiers()).is_equal({"power_mult": t.power_mult,
		"interval_mult": t.interval_mult, "miss_add": t.miss_add, "ignore_miss": true,
		"disabled": true})
	t.reset_modifiers()
	assert_dict(t.modifiers()).is_equal(NEUTRAL)


# --- 2: slot-1 reset (D2) ----------------------------------------------------------------

func test_a_step_resets_a_dark_tower_channel_to_neutral() -> void:
	var sim := _sim()
	var t: SimTower = _rifle(sim)[0]
	t.add_modifiers(2.0, 3.0, 0.5, true, true)
	assert_dict(t.modifiers()).is_not_equal(NEUTRAL)
	sim.step()
	assert_array([t.lit, t.shadowed]).is_equal([false, false])
	assert_dict(t.modifiers()).is_equal(NEUTRAL)
	# A writer that stopped writing leaves nothing behind on the next tick either.
	sim.step()
	assert_dict(t.modifiers()).is_equal(NEUTRAL)


# --- 3: light is the first writer, every tick (D3) ---------------------------------------

func test_light_writes_lit_and_shadowed_values_into_the_channel_every_tick() -> void:
	var sim := _sim()
	build(sim, SL, _at(3))
	var lit_rifle := build(sim, RIFLE, _at(6))  # range 3 from the Searchlight
	var lit_necro := build(sim, NECRO, _at(1))  # range 2
	build(sim, SIGN, _at(12))
	var dark_rifle := build(sim, RIFLE, _at(10))  # range 2 from the sign
	put(sim, "cultist", 0.5)
	for tick in 3:
		sim.step()
		assert_array([lit_rifle.lit, lit_necro.lit, dark_rifle.shadowed]) \
			.is_equal([true, true, true])
		for t: SimTower in [lit_rifle, lit_necro, dark_rifle]:
			var what := "tick %d %s lit=%s" % [tick + 1, t.def.id, t.lit]
			assert_dict(t.modifiers()).override_failure_message(what).is_equal(_light(sim, t))
			assert_dict(t.modifiers()).override_failure_message(what).is_not_equal(NEUTRAL)
	# The three rows really differ (beam mundane, beam occult, shadow mundane).
	assert_bool(lit_rifle.modifiers() != dark_rifle.modifiers()).is_true()
	assert_bool(lit_rifle.modifiers() != lit_necro.modifiers()).is_true()


# --- 4: combat reads the channel, not the flags (D5) -------------------------------------

func test_fire_towers_damage_and_cooldown_come_from_the_channel_of_a_dark_tower() -> void:
	var sim := _sim()
	var r := _rifle(sim)
	var t: SimTower = r[0]
	var e: SimEnemy = r[1]
	var s := t.stats()
	t.add_modifiers(2.0, 3.0, 0.0)
	sim._combat.fire_towers()
	assert_int(of_type(sim.drain_events(), T.SHOT).size()).is_equal(1)
	assert_float(HUGE_HP - e.hp).is_equal_approx(TowerRules.shot_damage(s, 1.0, 2.0), 1e-9)
	var want := TowerRules.cooldown_ticks(TowerRules.fire_interval(s, 3.0))
	assert_int(want).is_not_equal(TowerRules.cooldown_ticks(s.fire_interval))
	assert_int(t.cooldown_ticks).is_equal(want)


func test_an_aura_works_at_the_channel_power_of_a_dark_tower() -> void:
	var sim := _sim()
	var sign := build(sim, SIGN)
	var e := put(sim, "cultist", 7.0)
	var s := sign.stats()
	assert_bool(sign.lit or sign.shadowed).is_false()
	sign.add_modifiers(0.5, 1.0, 0.0)
	sim._combat.apply_auras()
	var slow: float = s.effects["slow"]
	var taken: float = s.effects["damage_taken_multiplier"]
	assert_float(e.speed_mult).is_equal_approx(1.0 - slow * 0.5, 1e-9)
	assert_float(e.damage_taken_mult).is_equal_approx(
		TowerRules.powered_taken_mult(taken, 0.5), 1e-9)
	assert_bool(absf(e.speed_mult - (1.0 - slow)) > 1e-6).is_true()  # not the plain aura


## Q4 too: interval_mult 3 on the gate leaves its cooldown at fire_interval.
func test_a_gate_banishes_at_the_channel_power_and_ignores_interval_mult() -> void:
	var sim := _sim()
	var k := build(sim, SK)
	var e := put(sim, "cultist", 9.0, 400.0)
	var s := k.stats()
	var d0 := e.distance
	k.add_modifiers(0.5, 3.0, 0.0)
	sim._combat.fire_towers()
	var cells: float = s.effects["banish_cells"]
	assert_int(d0 - e.distance).is_equal(roundi(cells * 0.5 * SimTime.UNITS_PER_CELL))
	assert_int(d0 - e.distance).is_not_equal(roundi(cells * SimTime.UNITS_PER_CELL))
	assert_int(k.cooldown_ticks).is_equal(TowerRules.cooldown_ticks(s.fire_interval))


## Q4 too: interval_mult 3 on the circle leaves its cooldown at fire_interval.
func test_a_circle_summons_at_the_channel_power_and_ignores_interval_mult() -> void:
	var sim := _sim()
	var c := build(sim, SC)
	var s := c.stats()
	c.add_modifiers(0.5, 3.0, 0.0)
	sim._combat.fire_towers()
	var allies := sim.allies_of(c.id)
	assert_int(allies.size()).is_equal(1)
	assert_float(allies[0].dps).is_equal(TowerRules.unit_dps(s, 0.5))
	assert_float(allies[0].dps).is_not_equal(TowerRules.unit_dps(s, 1.0))
	assert_int(c.cooldown_ticks).is_equal(TowerRules.cooldown_ticks(s.fire_interval))


# --- 5: ignore_miss wins over miss_add (no COMBAT draw) ----------------------------------

func test_ignore_miss_wins_over_miss_add_and_draws_nothing_from_combat() -> void:
	for no_miss: bool in [true, false]:
		var sim := _sim()
		var t: SimTower = _rifle(sim)[0]
		t.add_modifiers(1.0, 1.0, 1.0, no_miss)  # chance 1.0 without ignore_miss
		var before := _combat_state(sim)
		sim._combat.fire_towers()
		var shots := of_type(sim.drain_events(), T.SHOT)
		assert_int(shots.size()).is_equal(1)
		var what := "ignore_miss=%s" % no_miss
		assert_bool(shots[0].data["miss"]).override_failure_message(what).is_equal(not no_miss)
		if no_miss:
			assert_int(_combat_state(sim)).override_failure_message(what).is_equal(before)
		else:  # the observation can see a draw
			assert_int(_combat_state(sim)).override_failure_message(what).is_not_equal(before)


# --- 6: disabled (D6, Q2) ----------------------------------------------------------------

## A rifle (miss_add 1: a shot draws a COMBAT miss roll) and a Necronomicon (MADNESS: a cast
## draws the astray roll), both disabled with 2 cooldown ticks left.
func test_a_disabled_tower_counts_its_cooldown_fires_nothing_and_draws_nothing() -> void:
	var sim := _sim()
	var rifle := build(sim, RIFLE)
	var necro := build(sim, NECRO, _at(9))
	put(sim, "cultist", 7.0)
	sim.drain_events()
	sim.state.sanity = 0.0
	sim.state.sanity_state = sim.sanity_state_for(0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	assert_bool(necro.stats().madness_affected).is_true()
	var towers: Array[SimTower] = [rifle, necro]
	for t in towers:
		t.cooldown_ticks = 2
	var combat := _combat_state(sim)
	var madness := _madness_state(sim)
	for want_cd in [1, 0, 0]:  # counts down while disabled, then holds at ready
		for t in towers:
			t.reset_modifiers()
			t.add_modifiers(1.0, 1.0, 1.0, false, true)
		sim._combat.fire_towers()
		for t in towers:
			assert_int(t.cooldown_ticks).override_failure_message(t.def.id).is_equal(want_cd)
		assert_int(of_type(sim.drain_events(), T.SHOT).size()).is_equal(0)
	assert_int(_combat_state(sim)).is_equal(combat)
	assert_int(_madness_state(sim)).is_equal(madness)
	# The first enabled tick fires (no wait for a new cooldown) and draws from both.
	for t in towers:
		t.reset_modifiers()
		t.add_modifiers(1.0, 1.0, 1.0)
	sim._combat.fire_towers()
	assert_int(of_type(sim.drain_events(), T.SHOT).size()).is_greater_equal(2)
	assert_int(_combat_state(sim)).is_not_equal(combat)
	assert_int(_madness_state(sim)).is_not_equal(madness)


func test_a_disabled_aura_applies_nothing() -> void:
	for off: bool in [true, false]:
		var sim := _sim()
		var sign := build(sim, SIGN)
		var e := put(sim, "cultist", 7.0)
		sign.add_modifiers(1.0, 1.0, 0.0, false, off)
		sim._combat.apply_auras()
		var plain := [e.speed_mult, e.damage_taken_mult] == [1.0, 1.0]
		assert_bool(plain).override_failure_message("disabled=%s" % off).is_equal(off)


func test_a_disabled_tower_still_casts_light_and_shadow() -> void:
	var sim := _sim()
	var sl := build(sim, SL, _at(3))
	var lit := build(sim, RIFLE, _at(5))
	var sign := build(sim, SIGN, _at(12))
	var dark := build(sim, RIFLE, _at(10))
	sim.step()
	assert_array([lit.lit, dark.shadowed]).is_equal([true, true])
	sl.add_modifiers(1.0, 1.0, 0.0, false, true)
	sign.add_modifiers(1.0, 1.0, 0.0, false, true)
	sim._light.update_beam()  # the slot-2 light pass, the casters still disabled
	assert_array([lit.lit, dark.shadowed]).is_equal([true, true])


func test_a_disabled_circle_keeps_its_live_ally_and_summons_no_new_one() -> void:
	var sim := _sim()
	var c := build(sim, SC)
	assert_int(sim.upgrade_tower(c.id)).is_equal(SimCommand.CommandResult.OK)  # L2: 2 units
	sim._combat.fire_towers()
	assert_int(sim.allies_of(c.id).size()).is_equal(1)
	var first: SimAlly = sim.allies_of(c.id)[0]
	assert_int(c.stats().summon_max()).is_greater(1)
	c.cooldown_ticks = 0  # ready, room for one more
	c.add_modifiers(1.0, 1.0, 0.0, false, true)
	sim._combat.fire_towers()
	sim._ally.tick_allies()
	assert_int(sim.allies_of(c.id).size()).is_equal(1)
	assert_bool(first.gone).is_false()


# --- 7: tower_mults is the channel (D7) --------------------------------------------------

func test_tower_mults_is_the_tower_channel_set_by_hand() -> void:
	var sim := _sim()
	var t: SimTower = _rifle(sim)[0]
	t.add_modifiers(1.5, 0.75, 0.2, false, true)
	var want := {"power_mult": 1.5, "interval_mult": 0.75, "miss_add": 0.2,
		"ignore_miss": false, "disabled": true}
	assert_dict(t.modifiers()).is_equal(want)
	assert_dict(sim.tower_mults(t.id)).is_equal(want)
	assert_dict(sim.tower_mults(t.id)).is_not_equal(_light(sim, t))
	assert_dict(sim.tower_mults(-5)).is_empty()


# --- 8: effective == effective_with(light_effect) bit for bit (D7) -----------------------

func test_effective_is_effective_with_the_light_effect_bit_for_bit() -> void:
	var cfg := real_config()
	var n := 0
	for id: String in cfg.towers:
		var def: TowerDef = cfg.towers[id]
		var levels: Array = def.levels.duplicate()
		levels.append_array(def.branches.values())
		for s: TowerDef.Level in levels:
			for state: Array in [[false, false], [true, false], [false, true]]:
				for sanity: float in [-1.0, 30.0, 100.0]:
					var a := TowerRules.effective(def, s, cfg, state[0], state[1], sanity)
					var b := TowerRules.effective_with(s, cfg,
						TowerRules.light_effect(def, cfg, state[0], state[1]), sanity)
					assert_bool(var_to_bytes(a) == var_to_bytes(b)).override_failure_message(
						"%s %s lit/shadow %s sanity %s: %s != %s"
						% [id, s.name, state, sanity, a, b]).is_true()
					n += 1
	assert_int(n).is_greater(100)
