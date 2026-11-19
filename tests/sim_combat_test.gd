class_name SimCombatTest
extends TowerTestBase
## LT-82 (B7 of LT-80, docs/design/LT-80-sim-split.md section 7): CombatSystem owns damage,
## kills, auras, blasts, push-back, bleed and the roll hooks; AllySystem owns the allied
## units. Pins them standalone (a SimContext and their peers, no Simulation), the facade
## forwarders, the roll draw order and the hook wiring. The overall check stays the golden
## digest; this file only reaches the systems directly.
## Map: TowerTestBase ROWS. An enemy `put` at c cells is at (c + 0.5, 0.5), the default
## tower cell (7, 1) has its centre at (7.5, 1.5).

const T := SimEvent.Type
const SC := "summoning_circle"
const DYN := "dynamite_crew"

var _ctx: SimContext
var _eco: EconomySystem
var _sanity: SanitySystem
var _light: LightSystem
var _combat: CombatSystem
var _ally: AllySystem
var _spawn: SpawnSystem


## Counts the calls AllySystem makes to its Combat peer.
class SpyCombat:
	extends CombatSystem
	var damage_calls: Array = []

	func _init(ctx: SimContext, light: LightSystem, sanity: SanitySystem,
			economy: EconomySystem, spawn: SpawnSystem) -> void:
		super(ctx, light, sanity, economy, spawn)

	func apply_damage(enemy_id: int, amount: float, source: String, ignore_armor := false) -> float:
		damage_calls.append([enemy_id, amount, source, ignore_armor])
		return super(enemy_id, amount, source, ignore_armor)


func before_test() -> void:
	_ctx = SimContext.new(tconfig(), SEED)
	_ctx.state.map = _ctx.config.map
	_build(CombatSystem)


## Builds the peers (and the systems of `combat_class`, wired like the facade does).
func _build(combat_class: GDScript) -> void:
	_eco = EconomySystem.new(_ctx)
	_sanity = SanitySystem.new(_ctx, _eco)
	_light = LightSystem.new(_ctx, _eco)
	_spawn = SpawnSystem.new(_ctx)
	_combat = combat_class.new(_ctx, _light, _sanity, _eco, _spawn)
	_ally = AllySystem.new(_ctx, _combat)


func _wire() -> void:
	_combat.set_ally_hooks(_ally.spawn, _ally.allies_of)


func _types(events: Array[SimEvent]) -> Array:
	return events.map(func(e: SimEvent) -> int: return e.type)


func _drain() -> Array[SimEvent]:
	var out := _ctx.events.duplicate()
	_ctx.events.clear()
	return out


## The stream's draw sequence a fresh run with SEED would see (same seeding as SimRng).
func _fresh(stream: SimRng.Stream) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = SEED * SimRng.STREAM_SEED_STRIDE + int(stream)
	return g


## A parked enemy of a throwaway sim (route and def only), put into the standalone state.
func _enemy(def_id := "hybrid", cells := 7.0, hp := HUGE_HP, fake := false) -> SimEnemy:
	var e := put(tsim(), def_id, cells, hp, fake)
	e.id = _ctx.state.next_id
	_ctx.state.next_id += 1
	_ctx.state.enemies.append(e)
	return e


func _tower(def_id: String, cell := TOWER) -> SimTower:
	var t := SimTower.new()
	t.id = _ctx.state.next_id
	_ctx.state.next_id += 1
	t.def = _ctx.config.towers[def_id]
	t.cell = cell
	t.pos = _ctx.state.map.grid.centre(cell)
	_ctx.state.towers.append(t)
	_ctx.state.tower_at[cell] = t.id
	return t


func _pos(e: SimEnemy) -> Vector2:
	return e.route.position_at(e.distance)


## A unit placed by the system itself (no tower), `hp` hit points.
func _unit(at := Vector2(7.5, 1.5), hp := 120.0, dps := 15.0, speed := 1.5, leash := 3.5,
		lifetime := 0, tower := 0) -> SimAlly:
	var id := _ally.spawn(tower, SC, at, hp, dps, speed, false, lifetime, leash)
	assert_int(id).is_greater(0)
	_ctx.events.clear()  # the summon event is not what the callers look at
	return _ally.ally_by_id(id)


# --- CombatSystem standalone: damage and kill ------------------------------------------------

func test_apply_damage_applies_armor_and_caps_the_removed_hp_at_the_remaining_hp() -> void:
	var e := _enemy("hybrid", 7.0, 20.0)
	var armor := float(e.def.armor)
	assert_float(armor).is_greater(0.0)
	assert_float(_combat.apply_damage(e.id, 10.0, "test")).is_equal(10.0 - armor)
	assert_float(e.hp).is_equal(20.0 - (10.0 - armor))
	assert_float(_combat.apply_damage(e.id, 1.0, "test")).is_equal(0.0)  # armor eats it whole
	assert_float(e.hp).is_equal(20.0 - (10.0 - armor))
	var before := e.hp
	assert_float(_combat.apply_damage(e.id, 5.0, "test", true)).is_equal(5.0)  # ignore_armor
	assert_float(e.hp).is_equal(before - 5.0)
	assert_array(_drain()).is_empty()  # nothing died: no event
	e.damage_taken_mult = 2.0
	var left := e.hp
	assert_float(_combat.apply_damage(e.id, 1000.0, "test")).is_equal(left)  # overkill not counted
	assert_bool(e.dead).is_true()


func test_apply_damage_ignores_unknown_dead_and_post_outcome_targets() -> void:
	var e := _enemy("hybrid", 7.0, 20.0)
	assert_float(_combat.apply_damage(999, 10.0, "test")).is_equal(0.0)
	_combat.apply_damage(e.id, 1000.0, "test")
	_drain()
	assert_float(_combat.apply_damage(e.id, 10.0, "test")).is_equal(0.0)  # already dead
	var f := _enemy("hybrid", 8.0, 20.0)
	_ctx.state.outcome = SimState.Outcome.LOST
	assert_float(_combat.apply_damage(f.id, 10.0, "test")).is_equal(0.0)
	assert_float(f.hp).is_equal(20.0)
	assert_array(_drain()).is_empty()


func test_a_kill_emits_died_then_the_relic_drop() -> void:
	var e := _enemy("hybrid", 7.0, 20.0)
	_combat.apply_damage(e.id, 1000.0, "test")
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.DIED, T.RELIC_DROPPED])
	assert_int(ev[0].id).is_equal(e.id)
	assert_dict(ev[0].data).is_equal({"source": "test"})
	assert_int(_ctx.state.relic_tokens.size()).is_equal(1)


func test_a_mundane_kill_drops_the_token_before_the_sanity_regen() -> void:
	var e := _enemy("hybrid", 7.0, 20.0)
	_ctx.state.sanity = _ctx.state.sanity_cap * 0.8
	_ctx.state.sanity_state = _sanity.sanity_state_for(_ctx.state.sanity)
	var before := _ctx.state.sanity
	_combat.apply_damage(e.id, 1000.0, "rifleman")
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.DIED, T.RELIC_DROPPED, T.SANITY_CHANGED])
	assert_str(ev[2].data["reason"]).is_equal("mundane_kill")
	assert_int(ev[2].id).is_equal(e.id)
	assert_float(_ctx.state.sanity - before).is_equal_approx(
		_ctx.config.sanity.regen_mundane_kill, 1e-6)


func test_only_a_real_enemy_killed_by_a_mundane_tower_restores_sanity() -> void:
	_ctx.state.sanity = _ctx.state.sanity_cap * 0.8
	_ctx.state.sanity_state = _sanity.sanity_state_for(_ctx.state.sanity)
	var occult := _enemy("hybrid", 7.0, 20.0)
	var fake := _enemy("hybrid", 8.0, 20.0, true)
	var other := _enemy("hybrid", 9.0, 20.0)
	_combat.apply_damage(occult.id, 1000.0, "necronomicon_reader")
	_combat.apply_damage(fake.id, 1000.0, "rifleman")  # a fake: dropped (ghost), never credited
	_combat.apply_damage(other.id, 1000.0, "test")  # not a tower def
	assert_array(_types(_drain())).is_equal([T.DIED, T.RELIC_DROPPED, T.DIED, T.RELIC_DROPPED,
		T.DIED, T.RELIC_DROPPED])


# --- CombatSystem standalone: queries, auras, blasts, push-back ---------------------------------

func test_the_queries_find_live_enemies_by_id_range_and_radius() -> void:
	var near := _enemy("hybrid", 7.0)
	var far := _enemy("hybrid", 12.0)
	var fake := _enemy("hybrid", 8.0, HUGE_HP, true)
	var tower := _tower("rifleman")
	assert_object(_combat.enemy_by_id(near.id)).is_same(near)
	assert_object(_combat.enemy_by_id(777)).is_null()
	assert_object(_combat.tower_by_id(tower.id)).is_same(tower)
	assert_object(_combat.tower_by_id(777)).is_null()
	var in_range := _combat.enemies_in_range(TOWER, 3.0).map(func(e: SimEnemy) -> int: return e.id)
	assert_array(in_range).is_equal([near.id, fake.id])  # id order, fakes too
	var fakes := _combat.live_fakes_in_range(TOWER, 3.0)
	assert_array(fakes.map(func(e: SimEnemy) -> int: return e.id)).is_equal([fake.id])
	var around := _combat.enemies_near(_pos(near), 0.5).map(func(e: SimEnemy) -> int: return e.id)
	assert_array(around).is_equal([near.id])
	far.dead = true
	assert_array(_combat.enemies_in_range(Vector2i(12, 1), 1.0)).is_empty()  # the dead are skipped


func test_an_aura_slows_and_exposes_only_the_enemies_inside() -> void:
	var inside := _enemy("hybrid", 7.0)
	var outside := _enemy("hybrid", 12.0)
	var sign := _tower("elder_sign")
	var s := sign.stats()
	_combat.apply_auras()
	assert_float(inside.speed_mult).is_equal_approx(1.0 - float(s.effects["slow"]), 1e-6)
	assert_float(inside.damage_taken_mult).is_equal_approx(
		float(s.effects["damage_taken_multiplier"]), 1e-6)
	assert_float(outside.speed_mult).is_equal(1.0)
	assert_float(outside.damage_taken_mult).is_equal(1.0)


func test_aura_signs_do_not_stack_the_strongest_wins() -> void:
	var e := _enemy("hybrid", 7.0)
	_tower("elder_sign")
	_tower("elder_sign", Vector2i(6, 1))
	_combat.apply_auras()
	var s: TowerDef.Level = _ctx.config.towers["elder_sign"].levels[0]
	assert_float(e.speed_mult).is_equal_approx(1.0 - float(s.effects["slow"]), 1e-6)
	assert_float(e.damage_taken_mult).is_equal_approx(
		float(s.effects["damage_taken_multiplier"]), 1e-6)


func test_a_blast_is_queued_by_the_shot_and_settled_when_its_fuse_has_burnt() -> void:
	var near := _enemy("hybrid", 7.0)
	var far := _enemy("hybrid", 12.0)
	var t := _tower(DYN)
	var s := t.stats()
	_combat.fire_towers()
	assert_int(_ctx.state.blasts.size()).is_equal(1)
	assert_int(_ctx.state.next_blast_id).is_equal(2)
	var b := _ctx.state.blasts[0]
	assert_int(b.id).is_equal(1)
	assert_int(b.tower).is_equal(t.id)
	assert_str(b.source).is_equal(DYN)
	assert_int(b.detonate_tick).is_equal(_ctx.state.tick + SimTime.ticks(float(s.effects["fuse_seconds"])))
	assert_vector(b.at).is_equal_approx(_pos(near), Vector2(1e-4, 1e-4))
	assert_float(near.hp).is_equal(HUGE_HP)  # nothing before the fuse has burnt
	_drain()
	_combat.settle_blasts()
	assert_int(_ctx.state.blasts.size()).is_equal(1)  # not due yet
	assert_array(_drain()).is_empty()
	_ctx.state.tick = b.detonate_tick
	_combat.settle_blasts()
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.BLAST])
	assert_int(ev[0].id).is_equal(1)
	assert_array(ev[0].data["hits"]).is_equal([near.id])
	assert_float(near.hp).is_equal(HUGE_HP - (s.damage - near.def.armor))
	assert_float(far.hp).is_equal(HUGE_HP)
	assert_array(_ctx.state.blasts).is_empty()


func test_push_back_moves_along_the_route_never_before_its_start() -> void:
	var e := _enemy("hybrid", 8.0)
	e.prev_distance = 0
	_spawn.push_back(e, 2.0)
	assert_int(e.distance).is_equal(6 * SimTime.UNITS_PER_CELL)
	assert_int(e.prev_distance).is_equal(e.distance)  # the render does not slide it back
	_spawn.push_back(e, 100.0)
	assert_int(e.distance).is_equal(0)
	assert_int(e.prev_distance).is_equal(0)


func test_apply_bleed_refreshes_and_never_stacks() -> void:
	var e := _enemy("hybrid", 7.0)
	_combat.apply_bleed(e, 4.0, 2.0, "a")
	assert_int(e.status["bleed_ticks"]).is_equal(SimTime.ticks(2.0))
	assert_float(e.status["bleed_dps"]).is_equal(4.0)
	assert_int(e.status["bleed_pulse"]).is_equal(SimTime.TICK_RATE)
	_combat.apply_bleed(e, 2.0, 1.0, "b")  # weaker and shorter: nothing changes
	assert_float(e.status["bleed_dps"]).is_equal(4.0)
	assert_str(e.status["bleed_source"]).is_equal("a")
	assert_int(e.status["bleed_ticks"]).is_equal(SimTime.ticks(2.0))
	_combat.apply_bleed(e, 6.0, 3.0, "c")  # stronger and longer: both win
	assert_float(e.status["bleed_dps"]).is_equal(6.0)
	assert_str(e.status["bleed_source"]).is_equal("c")
	assert_int(e.status["bleed_ticks"]).is_equal(SimTime.ticks(3.0))


# --- CombatSystem: roll draw order ---------------------------------------------------------------

func _astray_of(r: float) -> String:
	var m := _ctx.config.sanity.madness
	if r < m.shot_real:
		return "real"
	if r < m.shot_real + m.shot_fake:
		return "fake"
	return "empty"


## Miss rolls on COMBAT, crit rolls on CRIT, astray rolls on MADNESS: one draw per roll on
## its own stream, interleaved calls never disturb another stream's sequence.
func test_the_rolls_draw_one_value_each_from_their_own_stream_in_call_order() -> void:
	_sanity.threshold().miss_chance = 0.5
	var combat := _fresh(SimRng.Stream.COMBAT)
	var crit := _fresh(SimRng.Stream.CRIT)
	var madness := _fresh(SimRng.Stream.MADNESS)
	var got: Array = []
	var expected: Array = []
	for i in 40:
		got.append([_combat._roll_miss(), _combat._roll_crit(0.4), _combat._roll_astray()])
		expected.append([combat.randf() < 0.5, crit.randf() < 0.4, _astray_of(madness.randf())])
	assert_array(got).is_equal(expected)
	var flat := []
	for row: Array in got:
		flat.append_array(row)
	assert_array(flat.duplicate()).contains([true, false, "real", "fake", "empty"])  # not constant


func test_a_roll_with_no_chance_draws_nothing() -> void:
	_sanity.threshold().miss_chance = 0.0
	assert_bool(_combat._roll_miss()).is_false()
	assert_bool(_combat._roll_crit(0.0)).is_false()
	assert_float(_ctx.rng(SimRng.Stream.COMBAT).randf()).is_equal(_fresh(SimRng.Stream.COMBAT).randf())
	assert_float(_ctx.rng(SimRng.Stream.CRIT).randf()).is_equal(_fresh(SimRng.Stream.CRIT).randf())


func test_the_shadow_extra_raises_the_miss_chance_capped_at_one() -> void:
	_sanity.threshold().miss_chance = 0.0
	var g := _fresh(SimRng.Stream.COMBAT)
	assert_bool(_combat._roll_miss(1.5)).is_true()  # chance capped at 1: always a miss, one draw
	g.randf()
	assert_float(_ctx.rng(SimRng.Stream.COMBAT).randf()).is_equal(g.randf())


# --- Summon: the hook path ------------------------------------------------------------------------

func test_a_circle_summons_through_the_spawn_hook_and_spends_its_cooldown() -> void:
	var t := _tower(SC)
	var s := t.stats()
	var calls := []
	var asked := []
	_combat.set_ally_hooks(
		func(tower: int, source: String, at: Vector2, hp: float, dps: float, speed: float,
				flying: bool, lifetime: int, leash: float) -> int:
			calls.append([tower, source, at, hp, dps, speed, flying, lifetime, leash])
			return 42,
		func(tower_id: int) -> Array[SimAlly]:
			asked.append(tower_id)
			return [] as Array[SimAlly])
	_combat.fire_towers()
	assert_array(asked).is_equal([t.id])
	assert_array(calls).has_size(1)
	assert_array(calls[0]).is_equal([t.id, SC, t.centre(), float(s.effects["summon_hp"]),
		TowerRules.unit_dps(s, _light.power_mult(t)), float(s.effects["summon_speed"]),
		s.summon_flying(), SimTime.ticks(float(s.effects["summon_lifetime"])), s.range_cells + 1.0])
	assert_int(t.cooldown_ticks).is_equal(TowerRules.cooldown_ticks(s.fire_interval))


func test_a_circle_at_its_maximum_asks_but_does_not_spawn_and_stays_ready() -> void:
	var t := _tower(SC)
	var s := t.stats()
	var spawned := []
	var live: Array[SimAlly] = []
	for i in s.summon_max():
		live.append(SimAlly.new())
	_combat.set_ally_hooks(
		func(...args: Array) -> int:
			spawned.append(args)
			return 1,
		func(_tower_id: int) -> Array[SimAlly]: return live)
	_combat.fire_towers()
	assert_array(spawned).is_empty()
	assert_int(t.cooldown_ticks).is_equal(0)


func test_a_refused_spawn_does_not_spend_the_cooldown() -> void:
	var t := _tower(SC)
	_combat.set_ally_hooks(
		func(...args: Array) -> int: return 0,
		func(_tower_id: int) -> Array[SimAlly]: return [] as Array[SimAlly])
	_combat.fire_towers()
	assert_int(t.cooldown_ticks).is_equal(0)


func test_a_circle_wired_to_the_ally_system_summons_one_unit_and_then_waits_for_a_free_slot() -> void:
	_wire()
	var t := _tower(SC)
	var s := t.stats()
	_combat.fire_towers()
	assert_int(_ctx.state.allies.size()).is_equal(1)
	var a := _ctx.state.allies[0]
	assert_int(a.tower).is_equal(t.id)
	assert_str(a.source).is_equal(SC)
	assert_vector(a.pos).is_equal(t.centre())
	assert_float(a.hp).is_equal(float(s.effects["summon_hp"]))
	assert_array(_types(_drain())).is_equal([T.ALLY_SUMMONED])
	assert_int(t.cooldown_ticks).is_equal(TowerRules.cooldown_ticks(s.fire_interval))
	t.cooldown_ticks = 0
	_combat.fire_towers()  # summon_max 1 at L1: no second unit, the circle stays ready
	assert_int(_ctx.state.allies.size()).is_equal(1)
	assert_int(t.cooldown_ticks).is_equal(0)
	a.gone = true  # a unit gone frees the slot at once
	_combat.fire_towers()
	assert_int(_ctx.state.allies.size()).is_equal(2)


## F3 (LT-82 review): the hooks are optional for every tower that does not summon.
func test_a_combat_system_without_hooks_fires_a_tower_that_does_not_summon() -> void:
	assert_bool(_combat._spawn_ally.is_null()).is_true()
	assert_bool(_combat._allies_of.is_null()).is_true()
	var e := _enemy("hybrid", 7.0, 100.0)
	_tower("rifleman")
	_combat.fire_towers()
	assert_float(e.hp).is_less(100.0)
	_combat.set_ally_hooks(_ally.spawn, _ally.allies_of)
	assert_bool(_combat._spawn_ally.is_null()).is_false()
	assert_bool(_combat._allies_of.is_null()).is_false()


# --- AllySystem standalone ---------------------------------------------------------------------------

func test_spawn_places_a_unit_with_the_next_id_and_emits_the_event() -> void:
	var next := _ctx.state.next_id
	_ctx.state.tick = 5
	var id := _ally.spawn(3, SC, Vector2(2.5, 1.5), 50.0, -1.0, -2.0, true, 40, -1.0)
	assert_int(id).is_equal(next)
	assert_int(_ctx.state.next_id).is_equal(next + 1)
	var a := _ally.ally_by_id(id)
	assert_object(a).is_not_null()
	assert_int(a.tower).is_equal(3)
	assert_float(a.dps).is_equal(0.0)  # clamped at 0
	assert_float(a.speed).is_equal(0.0)
	assert_float(a.leash).is_equal(0.0)
	assert_int(a.summon_tick).is_equal(5)
	assert_int(a.expires_tick).is_equal(45)
	assert_vector(a.prev_pos).is_equal(a.pos)
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.ALLY_SUMMONED])
	assert_int(ev[0].id).is_equal(id)
	assert_int(ev[0].data["expires_tick"]).is_equal(45)
	assert_bool(ev[0].data["flying"]).is_true()
	assert_int(_unit().expires_tick).is_equal(0)  # lifetime 0 = none


func test_spawn_refuses_without_hp_or_after_the_outcome_and_changes_nothing() -> void:
	var next := _ctx.state.next_id
	assert_int(_ally.spawn(0, SC, Vector2.ZERO, 0.0, 1.0, 1.0, false, 0, 1.0)).is_equal(0)
	_ctx.state.outcome = SimState.Outcome.WON
	assert_int(_ally.spawn(0, SC, Vector2.ZERO, 10.0, 1.0, 1.0, false, 0, 1.0)).is_equal(0)
	assert_int(_ctx.state.next_id).is_equal(next)
	assert_array(_ctx.state.allies).is_empty()
	assert_array(_ctx.events).is_empty()


func test_allies_of_lists_the_live_units_of_one_tower_in_id_order() -> void:
	var a := _unit(Vector2(1.5, 1.5), 10.0, 1.0, 1.0, 1.0, 0, 7)
	var other := _unit(Vector2(2.5, 1.5), 10.0, 1.0, 1.0, 1.0, 0, 8)
	var c := _unit(Vector2(3.5, 1.5), 10.0, 1.0, 1.0, 1.0, 0, 7)
	var d := _unit(Vector2(4.5, 1.5), 10.0, 1.0, 1.0, 1.0, 0, 7)
	d.gone = true
	assert_array(_ally.allies_of(7)).is_equal([a, c])
	assert_array(_ally.allies_of(8)).is_equal([other])
	assert_array(_ally.allies_of(99)).is_empty()
	assert_object(_ally.ally_by_id(c.id)).is_same(c)
	assert_object(_ally.ally_by_id(999)).is_null()


func test_ally_position_interpolates_between_the_last_two_ticks() -> void:
	var a := _unit()
	a.prev_pos = Vector2(0.0, 0.0)
	a.pos = Vector2(4.0, 2.0)
	assert_vector(_ally.ally_position(a, 0.0)).is_equal(Vector2(0.0, 0.0))
	assert_vector(_ally.ally_position(a, 0.25)).is_equal(Vector2(1.0, 0.5))
	assert_vector(_ally.ally_position(a, 1.0)).is_equal(Vector2(4.0, 2.0))


func test_a_unit_past_its_lifetime_is_gone_expired_and_a_held_enemy_is_frozen() -> void:
	var e := _enemy("hybrid", 8.0)
	var a := _unit(Vector2(8.5, 0.8), 50.0, 1.0, 1.0, 3.5, 10)
	a.held_id = e.id
	e.speed_mult = 1.0
	_ctx.state.tick = 9
	_ally.tick_allies()
	assert_float(e.speed_mult).is_equal(0.0)  # in contact: held
	assert_bool(a.gone).is_false()
	_drain()
	_ctx.state.tick = 10
	_ally.tick_allies()
	assert_bool(a.gone).is_true()
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.ALLY_GONE])
	assert_dict(ev[0].data).is_equal({"tower": 0, "reason": "expired"})
	assert_int(a.held_id).is_equal(-1)


func test_a_hold_that_left_contact_is_dropped_and_the_enemy_is_not_frozen() -> void:
	var e := _enemy("hybrid", 8.0)
	var a := _unit(Vector2(8.5, 1.4), 50.0, 1.0, 1.0, 3.5)  # 0.9 cells away
	a.held_id = e.id
	e.speed_mult = 1.0
	_ally.tick_allies()
	assert_int(a.held_id).is_equal(-1)
	assert_float(e.speed_mult).is_equal(1.0)


func test_a_unit_chases_the_nearest_enemy_inside_its_leash_and_holds_it_on_contact() -> void:
	var near := _enemy("hybrid", 8.0)  # (8.5, 0.5)
	var beyond := _enemy("hybrid", 13.0)  # outside the leash of 3.5 around home
	var a := _unit(Vector2(7.5, 1.5), 50.0, 1.0, 1.0, 3.5)
	_ally.move_allies()
	assert_int(a.target_id).is_equal(near.id)
	assert_int(a.held_id).is_equal(-1)  # one step of 1 cell/s is too short to arrive
	assert_vector(a.prev_pos).is_equal(Vector2(7.5, 1.5))
	var moved := a.pos.distance_to(Vector2(7.5, 1.5))
	assert_float(moved).is_equal_approx(1.0 * SimTime.DT, 1e-6)
	a.speed = 1000.0  # now it arrives in one step
	_ally.move_allies()
	assert_int(a.held_id).is_equal(near.id)
	assert_vector(a.pos).is_equal_approx(_pos(near), Vector2(1e-4, 1e-4))
	assert_int(beyond.id).is_not_equal(a.target_id)


func test_a_unit_with_no_target_walks_back_toward_its_home() -> void:
	var a := _unit(Vector2(7.5, 1.5), 50.0, 1.0, 1000.0, 3.5)
	a.pos = Vector2(9.5, 1.5)
	_ally.move_allies()
	assert_int(a.target_id).is_equal(-1)
	assert_vector(a.pos).is_equal(Vector2(7.5, 1.5))


func test_ally_combat_deals_its_dps_through_combat_apply_damage_and_takes_the_contact_damage() -> void:
	_build(SpyCombat)
	var e := _enemy("hybrid", 8.0)
	var a := _unit(Vector2(8.5, 0.8), 50.0, 15.0, 1.0, 3.5)
	a.held_id = e.id
	_ally.ally_combat()
	var armor := float(e.def.armor)
	var amount := maxf(0.0, 15.0 - armor) * SimTime.DT
	var spy := _combat as SpyCombat
	assert_array(spy.damage_calls).is_equal([[e.id, amount, SC, true]])
	assert_float(e.hp).is_equal(HUGE_HP - amount)  # the hit skips armor a second time
	assert_float(a.hp).is_equal(50.0 - e.def.contact_dps * SimTime.DT)
	assert_int(a.held_id).is_equal(e.id)
	assert_array(_ctx.events).is_empty()


func test_an_ally_kill_goes_through_the_combat_kill_path_and_frees_the_unit() -> void:
	var e := _enemy("hybrid", 8.0, 0.001)
	var a := _unit(Vector2(8.5, 0.8), 50.0, 15.0, 1.0, 3.5)
	a.held_id = e.id
	_ally.ally_combat()
	assert_bool(e.dead).is_true()
	assert_array(_types(_drain())).is_equal([T.DIED, T.RELIC_DROPPED])  # occult source: no regen
	assert_int(a.held_id).is_equal(-1)
	assert_float(a.hp).is_equal(50.0)  # a dead enemy deals no contact damage


func test_a_unit_at_zero_hp_is_gone_killed_by_the_enemy() -> void:
	var e := _enemy("hybrid", 8.0)
	var a := _unit(Vector2(8.5, 0.8), 0.0001, 1.0, 1.0, 3.5)
	a.held_id = e.id
	_ally.ally_combat()
	assert_bool(a.gone).is_true()
	assert_float(a.hp).is_equal(0.0)
	var ev := _drain()
	assert_array(_types(ev)).is_equal([T.ALLY_GONE])
	assert_dict(ev[0].data).is_equal({"tower": 0, "reason": "killed", "by": e.id})


func test_dismiss_marks_a_towers_units_gone_in_id_order_and_compact_drops_them() -> void:
	var a := _unit(Vector2(1.5, 1.5), 10.0, 1.0, 1.0, 1.0, 0, 7)
	var other := _unit(Vector2(2.5, 1.5), 10.0, 1.0, 1.0, 1.0, 0, 8)
	var c := _unit(Vector2(3.5, 1.5), 10.0, 1.0, 1.0, 1.0, 0, 7)
	_drain()
	_ally.dismiss_allies(7)
	var ev := _drain()
	assert_array(ev.map(func(e: SimEvent) -> int: return e.id)).is_equal([a.id, c.id])
	assert_array(ev.map(func(e: SimEvent) -> String: return e.data["reason"])) \
		.is_equal(["dismissed", "dismissed"])
	assert_array(_ctx.state.allies).has_size(3)  # removed only in slot 8
	_ally.compact()
	assert_array(_ctx.state.allies).is_equal([other])
	_ally.compact()
	_ctx.state.allies.clear()
	_ally.compact()  # an empty list is fine
	assert_array(_ctx.state.allies).is_empty()


# --- Facade forwarders ----------------------------------------------------------------------------------

func _twin_sims() -> Array[Simulation]:
	var out: Array[Simulation] = []
	for i in 2:
		var sim := tsim()
		sim.state.gold = 1000000
		out.append(sim)
	return out


func test_the_facade_query_forwarders_return_what_the_systems_return() -> void:
	var sim := tsim()
	sim.state.gold = 1000000
	var near := put(sim, "hybrid", 7.0)
	var fake := put(sim, "hybrid", 8.0, HUGE_HP, true)
	var t := build(sim, "rifleman")
	assert_object(sim.enemy_by_id(near.id)).is_same(sim._combat.enemy_by_id(near.id))
	assert_object(sim.enemy_by_id(near.id)).is_same(near)
	assert_object(sim.tower_by_id(t.id)).is_same(t)
	assert_object(sim.tower_by_id(999)).is_null()
	assert_array(sim.enemies_in_range(TOWER, 3.0)).is_equal(sim._combat.enemies_in_range(TOWER, 3.0))
	assert_array(sim.enemies_in_range(TOWER, 3.0)).is_equal([near, fake])
	assert_array(sim.enemies_near(Vector2(7.5, 0.5), 0.6)).is_equal([near])
	assert_array(sim.live_fakes_in_range(TOWER, 3.0)).is_equal([fake])
	assert_object(sim.ally_by_id(1)).is_null()


func test_the_facade_ally_forwarders_reach_the_ally_system() -> void:
	var sim := tsim()
	var id := sim.spawn_ally(5, SC, Vector2(3.5, 1.5), 40.0, 3.0, 1.0, false, 0, 2.0)
	assert_int(id).is_greater(0)
	var a := sim.ally_by_id(id)
	assert_object(a).is_same(sim._ally.ally_by_id(id))
	assert_array(sim.allies_of(5)).is_equal([a])
	assert_array(sim.allies_of(6)).is_empty()
	a.prev_pos = Vector2(0.0, 0.0)
	a.pos = Vector2(4.0, 2.0)
	assert_vector(sim.ally_position(a, 0.25)).is_equal(Vector2(1.0, 0.5))
	assert_int(sim.spawn_ally(5, SC, Vector2.ZERO, 0.0, 1.0, 1.0, false, 0, 1.0)).is_equal(0)


func test_the_facade_damage_and_test_only_forwarders_match_the_systems_on_a_twin_run() -> void:
	var twins := _twin_sims()
	var via_facade := twins[0]
	var via_system := twins[1]
	var a := put(via_facade, "hybrid", 7.0, 50.0)
	var b := put(via_system, "hybrid", 7.0, 50.0)
	assert_float(via_facade.apply_damage(a.id, 12.0, "rifleman")).is_equal(
		via_system._combat.apply_damage(b.id, 12.0, "rifleman"))
	assert_float(via_facade.apply_damage(a.id, 1000.0, "rifleman", true)).is_equal(
		via_system._combat.apply_damage(b.id, 1000.0, "rifleman", true))
	assert_float(a.hp).is_equal(b.hp)
	var flat := func(sim: Simulation) -> Array:
		return sim.drain_events().map(func(e: SimEvent) -> Array: return [e.type, e.tick, e.id, e.data])
	assert_array(flat.call(via_facade)).is_equal(flat.call(via_system))
	var c := put(via_facade, "hybrid", 8.0)
	var d := put(via_system, "hybrid", 8.0)
	via_facade._push_back(c, 1.5)
	via_system._spawn.push_back(d, 1.5)
	assert_int(c.distance).is_equal(d.distance)
	assert_int(c.distance).is_equal(roundi(6.5 * SimTime.UNITS_PER_CELL))
	via_facade._apply_bleed(c, 3.0, 2.0, "x")
	via_system._combat.apply_bleed(d, 3.0, 2.0, "x")
	assert_dict(c.status).is_equal(d.status)
	assert_dict(c.status).is_not_empty()


func test_the_facade_keeps_the_moved_constants_as_aliases() -> void:
	assert_array(Array(Simulation.IMMUNITY_KEYS)).is_equal(Array(CombatSystem.IMMUNITY_KEYS))
	assert_float(Simulation.ALLY_CONTACT).is_equal(AllySystem.ALLY_CONTACT)
	assert_float(AllySystem.ALLY_CONTACT).is_equal(0.4)


# --- F1: where the facade points the hooks ---------------------------------------------------------

## G4a cannot see a Callable (it is opaque), so the wiring is pinned here: both hooks must
## point at AllySystem, not at a facade method or at a peer's private method.
func test_the_facade_wires_both_hooks_to_the_ally_system_methods() -> void:
	var sim := tsim()
	assert_bool(sim._combat._spawn_ally.get_object() is AllySystem).is_true()
	assert_bool(sim._combat._allies_of.get_object() is AllySystem).is_true()
	assert_object(sim._combat._spawn_ally.get_object()).is_same(sim._ally)
	assert_object(sim._combat._allies_of.get_object()).is_same(sim._ally)
	assert_str(String(sim._combat._spawn_ally.get_method())).is_equal("spawn")
	assert_str(String(sim._combat._allies_of.get_method())).is_equal("allies_of")
