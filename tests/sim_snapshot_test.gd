class_name SimSnapshotTest
extends WaveTestBase
## LT-85 (docs/design/LT-85-view-snapshot.md §3, §5, §9): the view records and
## Simulation.snapshot(). Shape allowlists with no fake and no live sim object, a real and a
## fake of one kind giving equal records every tick, the position/speed/armor formulas,
## madness_buffed on the ticks MADNESS starts and ends, purity, live-only id-ordered
## entities, scalars equal to SimState every tick, copies not references, the lookups and the
## id queries. Written from the spec; the controls are listed in LT-85-controls.md.

const T := SimEvent.Type
const S := SimState.SanityState
const RIFLE := "rifleman"
const SIGN := "elder_sign"
const FAR := 1.0
const NEAR := 7.0

const ENEMY_PROPS: Array[String] = ["id", "def", "hp", "max_hp", "speed", "base_speed", "armor",
	"markers", "madness_buffed", "lit", "revealed", "prev_distance", "distance", "pos", "_route"]
const TOWER_PROPS: Array[String] = ["id", "def", "cell", "centre", "level", "branch", "stats",
	"post", "crew", "crew_kind", "lit", "shadowed", "disabled", "target_priority"]
const ALLY_PROPS: Array[String] = ["id", "tower", "source", "prev_pos", "pos", "hp", "max_hp",
	"flying", "held_id"]
const SNAP_PROPS: Array[String] = ["enemies", "towers", "allies", "tick", "outcome", "phase",
	"wave_index", "waves_total", "build_ticks_left", "gold", "relics", "sanity", "sanity_cap",
	"sanity_state", "lighthouse_hp", "lighthouse_level", "night_luck", "oil",
	"flare_ticks_left", "flare_cooldown_ticks", "map", "_enemy_by_id", "_tower_by_id",
	"_tower_at"]
const SCALARS: Array[String] = ["tick", "outcome", "phase", "wave_index", "waves_total",
	"build_ticks_left", "gold", "sanity", "sanity_cap", "sanity_state", "lighthouse_hp",
	"lighthouse_level", "night_luck", "oil", "flare_ticks_left", "flare_cooldown_ticks", "map"]

## Corner map: S(0,0) -> (2,0) -> (2,2) -> L(0,2); the route turns at cells 2 and 4.
const CORNER_ROWS := ["S##", "..#", "L##"]


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


func _script_props(o: Object) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in o.get_script().get_script_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			out.append(String(p["name"]))
	out.sort()
	return out


func _sorted(a: Array[String]) -> Array[String]:
	var b := a.duplicate()
	b.sort()
	return b


## Names of live-sim classes found anywhere in `v` (objects, arrays, dictionaries).
func _live_objects(v: Variant, path: String, out: Array[String]) -> void:
	if v is Object:
		for cls: Variant in [SimEnemy, SimTower, SimAlly, SimState, Simulation, SimBlast]:
			if is_instance_of(v, cls):
				out.append(path)
	elif v is Array:
		for x: Variant in v:
			_live_objects(x, path + "[]", out)
	elif v is Dictionary:
		for k: Variant in v:
			_live_objects(k, path + "{k}", out)
			_live_objects(v[k], path + "{v}", out)


## One of each: an enemy (real), a fake, a tower, an ally.
func _full_sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 100000
	var t := build(sim, RIFLE)
	put(sim, "cultist", 3.0)
	put(sim, "cultist", 4.0, HUGE_HP, true)
	assert_int(sim.spawn_ally(t.id, "test", Vector2(3.5, 0.5), 10.0, 1.0, 1.0, false, 100, 5.0)) \
		.is_greater(0)
	return sim


# --- 1: shape --------------------------------------------------------------------------------

func test_record_and_snapshot_property_sets_equal_the_pinned_allowlists() -> void:
	var sim := _full_sim()
	var snap := sim.snapshot()
	assert_array(_script_props(snap.enemies[0])).is_equal(_sorted(ENEMY_PROPS))
	assert_array(_script_props(snap.towers[0])).is_equal(_sorted(TOWER_PROPS))
	assert_array(_script_props(snap.allies[0])).is_equal(_sorted(ALLY_PROPS))
	assert_array(_script_props(snap)).is_equal(_sorted(SNAP_PROPS))


func test_no_record_property_is_named_fake_or_holds_a_live_sim_object() -> void:
	var sim := _full_sim()
	var snap := sim.snapshot()
	var live: Array[String] = []
	for o: Object in [snap, snap.enemies[0], snap.enemies[1], snap.towers[0], snap.allies[0]]:
		for p in _script_props(o):
			assert_bool(p.to_lower().contains("fake")).override_failure_message(
				"%s has a property named %s" % [o.get_script().get_global_name(), p]).is_false()
			_live_objects(o.get(p), "%s.%s" % [o.get_script().get_global_name(), p], live)
	assert_array(live).is_empty()


# --- 2: a fake cannot be told from a real one ------------------------------------------------

func _diffs(a: EnemyRecord, b: EnemyRecord) -> Array[String]:
	var out: Array[String] = []
	for p in ENEMY_PROPS:
		if p != "id" and a.get(p) != b.get(p):
			out.append(p)
	for alpha: float in [0.0, 0.5, 1.0]:
		if a.position(alpha) != b.position(alpha):
			out.append("position(%s)" % alpha)
	return out


func test_a_real_and_a_fake_of_one_kind_have_equal_records_every_tick() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	sim.state.oil = 50
	build(sim, SIGN)  # slows what passes cell 7
	var real_id := sim.spawn_enemy("cultist")
	var fake_id := sim.spawn_enemy("cultist", true)
	for id in [real_id, fake_id]:  # both start 5 cells in, so the aura is reached early
		var e := sim.enemy_by_id(id)
		e.distance = 5 * SimTime.UNITS_PER_CELL
		e.prev_distance = e.distance
	var seen := {"slow": false, "madness": false, "lit": false}
	for t in 140:
		if t == 80:
			_set_sanity(sim, 0.0)
		if t == 100:
			assert_int(sim.fire_flare()).is_equal(SimCommand.CommandResult.OK)
		sim.step()
		var snap := sim.snapshot()
		var a := snap.enemy(real_id)
		var b := snap.enemy(fake_id)
		assert_bool(a == null).override_failure_message("tick %d: presence" % t).is_equal(b == null)
		if a == null:
			break
		assert_array(_diffs(a, b)).override_failure_message("tick %d" % t).is_empty()
		seen["slow"] = seen["slow"] or (t < 80 and a.speed < a.base_speed)
		seen["madness"] = seen["madness"] or a.madness_buffed
		seen["lit"] = seen["lit"] or a.lit
	assert_dict(seen).is_equal({"slow": true, "madness": true, "lit": true})


# --- 3: position ------------------------------------------------------------------------------

func test_position_follows_the_route_across_a_corner_and_pos_is_alpha_one() -> void:
	var sim := Simulation.new(make_config(CORNER_ROWS), SEED)
	var e := sim.enemy_by_id(sim.spawn_enemy("cultist"))
	e.prev_distance = roundi(1.5 * SimTime.UNITS_PER_CELL)
	e.distance = roundi(2.5 * SimTime.UNITS_PER_CELL)  # (1.5, .5) -> round the corner -> (2.5, 1.5)
	var r := sim.snapshot().enemy(e.id)
	for alpha: float in [0.0, 0.5, 1.0]:
		assert_vector(r.position(alpha)).override_failure_message("alpha %s" % alpha) \
			.is_equal(sim.enemy_position(e, alpha))
	assert_vector(r.pos).is_equal(r.position(1.0))
	var straight := r.position(0.0).lerp(r.position(1.0), 0.5)
	assert_bool(r.position(0.5).is_equal_approx(straight)).override_failure_message(
		"the corner fixture must bend the route").is_false()


# --- 4: speed, base_speed, armor, markers -----------------------------------------------------

func test_speed_base_speed_armor_and_markers_follow_the_combat_formulas() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	build(sim, SIGN)
	var e := sim.enemy_by_id(sim.spawn_enemy("cultist"))
	for i in 12:  # walks to the elder sign's aura (cell 7 is 1 cell away; slow in force)
		sim.step()
	e.armor_bonus = 2.0
	var rate := float(SimTime.TICK_RATE) / SimTime.UNITS_PER_CELL
	var r := sim.snapshot().enemy(e.id)
	assert_float(r.base_speed).is_equal_approx(e.base_units_per_tick * rate, 1.0e-6)
	assert_float(r.speed).is_equal_approx(roundi(e.base_units_per_tick * e.speed_mult) * rate, 1.0e-6)
	assert_float(r.armor).is_equal(maxf(0.0, e.def.armor + 2.0))
	assert_array(r.markers).is_equal(e.markers())
	e.armor_bonus = -1000.0
	assert_float(sim.snapshot().enemy(e.id).armor).is_equal(0.0)
	e.speed_mult = 0.5
	assert_float(sim.snapshot().enemy(e.id).speed).is_equal_approx(
		roundi(e.base_units_per_tick * 0.5) * rate, 1.0e-6)
	assert_float(sim.snapshot().enemy(e.id).speed).is_less(sim.snapshot().enemy(e.id).base_speed)


# --- 5: madness_buffed ------------------------------------------------------------------------

func _mad_sim() -> Simulation:
	var sim := tsim()
	sim.state.gold = 100000
	_set_sanity(sim, 0.0)
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	return sim


func test_madness_buffed_is_true_in_madness_for_real_and_fake_and_agrees_with_speed() -> void:
	var sim := _mad_sim()
	var real := sim.enemy_by_id(sim.spawn_enemy("cultist"))
	var fake := sim.enemy_by_id(sim.spawn_enemy("cultist", true))
	sim.step()
	var snap := sim.snapshot()
	var rate := float(SimTime.TICK_RATE) / SimTime.UNITS_PER_CELL
	for e: SimEnemy in [real, fake]:
		var r := snap.enemy(e.id)
		assert_bool(r.madness_buffed).is_true()
		assert_float(r.speed).is_equal_approx(roundi(e.base_units_per_tick * e.speed_mult) * rate, 1.0e-6)
		assert_float(r.speed).is_greater(r.base_speed)


func test_madness_buffed_is_false_outside_madness_with_a_unit_multiplier_and_when_lit() -> void:
	# outside MADNESS
	var sim := tsim()
	_set_sanity(sim, sim.config.sanity.max_sanity)
	var e := put(sim, "cultist", FAR)
	sim.step()
	assert_bool(sim.snapshot().enemy(e.id).madness_buffed).is_false()
	# both multipliers 1.0: no buff
	sim = _mad_sim()
	sim.config.sanity.madness.enemy_speed_multiplier = 1.0
	sim.config.sanity.madness.enemy_damage_taken_multiplier = 1.0
	e = put(sim, "cultist", FAR)
	sim.step()
	assert_bool(sim.snapshot().enemy(e.id).madness_buffed).is_false()
	# lit by the flare, cancel_madness_buff on: lit enemies, real and fake, skip the buff
	for cancel: bool in [true, false]:
		sim = _mad_sim()
		sim.config.economy.beam.cancel_madness_buff = cancel
		sim.state.oil = 50
		var real := put(sim, "cultist", FAR)
		var fake := put(sim, "cultist", 2.0, HUGE_HP, true)
		assert_int(sim.fire_flare()).is_equal(SimCommand.CommandResult.OK)
		sim.step()
		var snap := sim.snapshot()
		for x: SimEnemy in [real, fake]:
			assert_bool(snap.enemy(x.id).lit).is_true()
			assert_bool(snap.enemy(x.id).madness_buffed).override_failure_message(
				"cancel=%s fake=%s" % [cancel, x.is_fake]).is_equal(not cancel)


## S12 SF1: on the tick horror drain takes sanity into MADNESS the record is unbuffed, like
## its speed; the next tick both are buffed.
func test_madness_buffed_agrees_with_the_applied_speed_on_the_tick_madness_starts() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	build(sim, RIFLE)
	var e := put(sim, "shoggoth", NEAR)
	var drain: float = sim.config.enemies["shoggoth"].horror_drain * SimTime.DT
	_set_sanity(sim, drain / 2.0)
	sim.step()
	assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
	var r := sim.snapshot().enemy(e.id)
	assert_bool(r.madness_buffed).is_false()
	assert_float(e.speed_mult).is_equal(1.0)
	sim.step()
	assert_bool(sim.snapshot().enemy(e.id).madness_buffed).is_true()
	assert_float(e.speed_mult).is_not_equal(1.0)


## S12 SF1: after a buyout the snapshot built before the next step still carries the buff
## the step just applied; one step later it is gone (reset_modifiers clears the flag).
func test_madness_buffed_agrees_with_the_applied_speed_on_the_tick_madness_ends() -> void:
	var sim := _mad_sim()
	sim.config.sanity.madness.exit_rule = "buyout"
	var e := put(sim, "cultist", FAR)
	sim.step()
	assert_bool(sim.snapshot().enemy(e.id).madness_buffed).is_true()
	assert_int(sim.buy_sanity()).is_equal(SimCommand.CommandResult.OK)
	assert_int(sim.state.sanity_state).is_not_equal(S.MADNESS)
	assert_bool(sim.snapshot().enemy(e.id).madness_buffed).is_true()
	assert_float(e.speed_mult).is_not_equal(1.0)
	sim.step()
	assert_bool(sim.snapshot().enemy(e.id).madness_buffed).is_false()
	assert_float(e.speed_mult).is_equal(1.0)


# --- 6: purity ---------------------------------------------------------------------------------

## A seeded wave run through MADNESS; `take` calls snapshot() every tick (after the step,
## before the events are drained and before a between-ticks hit). Returns what the sim shows.
func _pure_run(take: bool) -> Dictionary:
	var sim := wsim([[group("cultist", 4, 0.5)]], 1, 100000)
	sim.state.gold = 100000
	var events: Array[String] = []
	var buffed_seen := 0
	for t in 220:
		if t == 3:
			build(sim, RIFLE)
		if t == 60:
			_set_sanity(sim, 0.0)
		sim.step()
		if take:
			for r in sim.snapshot().enemies:
				buffed_seen += int(r.madness_buffed)
		events.append_array(strings_of(sim.drain_events()))
		for e in sim.state.enemies:  # a between-ticks hit sees the modifiers a snapshot may touch
			if e.is_live():
				sim.apply_damage(e.id, 3.0, "test")
				break
	var ents: Array = []
	for e in sim.state.enemies:
		ents.append([e.id, e.distance, e.hp, e.speed_mult, e.damage_taken_mult, e.is_fake])
	return {"digest": SimNoTreeLoop.digest(sim), "log": str(sim.state.command_log),
		"events": events, "enemies": ents, "next_id": sim.state.next_id, "buffed": buffed_seen}


func test_snapshot_is_pure_a_run_calling_it_every_tick_equals_one_that_never_does() -> void:
	var a := _pure_run(true)
	var b := _pure_run(false)
	assert_int(a["buffed"]).override_failure_message("the run must reach a buffed enemy") \
		.is_greater(0)
	assert_array(a["events"]).is_not_empty()
	for k: String in ["digest", "log", "enemies", "next_id"]:
		assert_str(str(a[k])).override_failure_message(k).is_equal(str(b[k]))
	assert_array(a["events"]).is_equal(b["events"])


# --- 7: live only, id order --------------------------------------------------------------------

func test_only_live_enemies_and_allies_and_all_towers_each_in_id_order() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var t1 := build(sim, RIFLE)
	var e1 := put(sim, "cultist", 3.0)
	var e2 := put(sim, "cultist", 4.0)
	var e3 := put(sim, "cultist", 5.0, HUGE_HP, true)
	var t2 := build(sim, RIFLE, Vector2i(9, 1))
	var a1 := sim.spawn_ally(t1.id, "test", Vector2(3.5, 0.5), 10.0, 1.0, 1.0, false, 100, 5.0)
	var a2 := sim.spawn_ally(t1.id, "test", Vector2(4.5, 0.5), 10.0, 1.0, 1.0, false, 100, 5.0)
	var a3 := sim.spawn_ally(t1.id, "test", Vector2(5.5, 0.5), 10.0, 1.0, 1.0, false, 100, 5.0)
	sim.apply_damage(e2.id, HUGE_HP * 2.0, "test")
	assert_bool(e2.is_live()).is_false()
	sim.ally_by_id(a2).gone = true
	var snap := sim.snapshot()
	assert_array(snap.enemies.map(func(r: EnemyRecord) -> int: return r.id)).is_equal([e1.id, e3.id])
	assert_array(snap.towers.map(func(r: TowerRecord) -> int: return r.id)).is_equal([t1.id, t2.id])
	assert_array(snap.allies.map(func(r: AllyRecord) -> int: return r.id)).is_equal([a1, a3])
	assert_object(snap.enemy(e2.id)).is_null()


# --- 8: scalars ---------------------------------------------------------------------------------

func test_every_scalar_equals_its_sim_state_field_after_every_tick() -> void:
	var sim := wsim([[group("cultist", 3, 0.5)]], 1, 100000)
	sim.state.gold = 100000
	sim.state.relics["probe"] = 2
	sim.state.oil = 50
	var seen := {"build": false, "wave": false, "madness": false, "flare": false, "lh": false}
	for t in 160:
		if t == 2:
			build(sim, RIFLE)
		if t == 5:
			seen["lh"] = sim.upgrade_lighthouse() == SimCommand.CommandResult.OK
		if t == 70:
			_set_sanity(sim, 0.0)
		if t >= 80 and not seen["flare"] and sim.fire_flare() == SimCommand.CommandResult.OK:
			seen["flare"] = true
		sim.step()
		var snap := sim.snapshot()
		for p in SCALARS:
			assert_that(snap.get(p)).override_failure_message("tick %d %s" % [t, p]) \
				.is_equal(sim.state.get(p))
		assert_dict(snap.relics).is_equal(sim.state.relics)
		seen["build"] = seen["build"] or snap.phase == SimState.Phase.BUILD
		seen["wave"] = seen["wave"] or snap.phase == SimState.Phase.WAVE
		seen["madness"] = seen["madness"] or snap.sanity_state == S.MADNESS
	assert_dict(seen).is_equal({"build": true, "wave": true, "madness": true, "flare": true,
		"lh": true})
	assert_float(sim.snapshot().sanity_cap).is_not_equal(sim.snapshot().sanity)


# --- 9: relics are a copy ----------------------------------------------------------------------

func test_relics_is_a_copy_writing_it_does_not_change_the_sim() -> void:
	var sim := tsim()
	sim.state.relics["probe"] = 2
	var want := sim.state.relics.duplicate()
	var snap := sim.snapshot()
	snap.relics["probe"] = 99
	snap.relics["other"] = 1
	assert_dict(sim.state.relics).is_equal(want)
	assert_int(sim.state.relics["probe"]).is_equal(2)


# --- 10, 11: tower and ally records ------------------------------------------------------------

func test_a_tower_record_equals_its_sim_tower() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var t := build(sim, RIFLE)
	assert_int(sim.upgrade_tower(t.id)).is_equal(SimCommand.CommandResult.OK)
	t.lit = true
	t.shadowed = true
	t.disabled = true
	t.crew = 2
	t.crew_kind = "probe_kind"
	t.target_priority = TowerRecord.TARGET_PRIORITIES[TowerRecord.TARGET_PRIORITIES.size() - 1]
	var r := sim.snapshot().tower(t.id)
	assert_object(r.def).is_same(t.def)
	assert_vector(r.cell).is_equal(t.cell)
	assert_vector(r.centre).is_equal(t.centre())
	assert_int(r.level).is_equal(t.level)
	assert_str(r.branch).is_equal(t.branch)
	assert_object(r.stats).is_same(t.stats())
	assert_bool(r.post).is_equal(t.post)
	assert_int(r.crew).is_equal(2)
	assert_str(r.crew_kind).is_equal("probe_kind")
	assert_bool(r.lit and r.shadowed and r.disabled).is_true()
	assert_str(r.target_priority).is_equal(t.target_priority)
	assert_array(TowerRecord.TARGET_PRIORITIES).is_equal(SimTower.TARGET_PRIORITIES)


func test_an_ally_record_equals_its_sim_ally_and_positions_like_the_sim() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var t := build(sim, RIFLE)
	var id := sim.spawn_ally(t.id, "probe_src", Vector2(3.5, 0.5), 10.0, 1.0, 1.0, true, 100, 5.0)
	var a := sim.ally_by_id(id)
	a.prev_pos = Vector2(1.0, 1.0)
	a.pos = Vector2(2.0, 3.0)
	a.hp = 7.0
	a.held_id = 5
	var r := sim.snapshot().allies[0]
	assert_int(r.id).is_equal(a.id)
	assert_int(r.tower).is_equal(t.id)
	assert_str(r.source).is_equal("probe_src")
	assert_vector(r.prev_pos).is_equal(a.prev_pos)
	assert_vector(r.pos).is_equal(a.pos)
	assert_float(r.hp).is_equal(7.0)
	assert_float(r.max_hp).is_equal(a.max_hp)
	assert_bool(r.flying).is_equal(a.flying)
	assert_int(r.held_id).is_equal(5)
	for alpha: float in [0.0, 0.5, 1.0]:
		assert_vector(r.position(alpha)).override_failure_message("alpha %s" % alpha) \
			.is_equal(sim.ally_position(a, alpha))
	assert_vector(r.position(0.5)).is_not_equal(r.position(0.0))


# --- 12: lookups ---------------------------------------------------------------------------------

func test_lookups_return_the_record_or_null_and_tower_at_follows_a_lifted_tower() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var t := build(sim, RIFLE)
	var e := put(sim, "cultist", 3.0)
	var snap := sim.snapshot()
	assert_object(snap.enemy(e.id)).is_same(snap.enemies[0])
	assert_object(snap.tower(t.id)).is_same(snap.towers[0])
	assert_object(snap.tower_at(TOWER)).is_same(snap.towers[0])
	assert_object(snap.enemy(9999)).is_null()
	assert_object(snap.tower(9999)).is_null()
	assert_object(snap.tower_at(Vector2i(3, 1))).is_null()
	var to := Vector2i(10, 1)
	sim._lift_tower(t, to, 5, -1)
	snap = sim.snapshot()
	assert_object(snap.tower_at(to)).is_same(snap.tower(t.id))
	assert_object(snap.tower_at(TOWER)).is_null()
	assert_vector(snap.tower(t.id).cell).is_equal(to)
	sim.sell_tower(t.id)
	snap = sim.snapshot()
	assert_object(snap.tower(t.id)).is_null()
	assert_object(snap.tower_at(to)).is_null()


# --- 13: a snapshot is a copy ----------------------------------------------------------------------

func test_stepping_the_sim_does_not_change_an_older_snapshot() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var t := build(sim, RIFLE)
	var e := sim.enemy_by_id(sim.spawn_enemy("cultist"))
	sim.step()
	var snap := sim.snapshot()
	var r := snap.enemy(e.id)
	var before := [snap.tick, snap.gold, r.distance, r.hp, r.pos, snap.towers.size(),
		snap.enemies.size(), snap.tower(t.id).level]
	for i in 10:
		sim.step()
	e.hp -= 1.0
	sim.upgrade_tower(t.id)
	build(sim, RIFLE, Vector2i(9, 1))
	assert_array([snap.tick, snap.gold, r.distance, r.hp, r.pos, snap.towers.size(),
		snap.enemies.size(), snap.tower(t.id).level]).is_equal(before)
	assert_int(sim.state.tick).is_not_equal(snap.tick)
	assert_int(e.distance).is_not_equal(r.distance)


# --- 14: id queries -----------------------------------------------------------------------------------

func test_id_queries_equal_their_tower_forms_and_are_safe_on_a_missing_id() -> void:
	var sim := tsim()
	sim.state.gold = 100000
	var t := build(sim, RIFLE)
	for level in 2:
		var branches := sim.upgrade_branches(t)
		assert_array(branches).is_not_empty()
		assert_array(sim.upgrade_branches_of(t.id)).is_equal(sim.upgrade_branches(t))
		for b: String in sim.upgrade_branches(t):
			assert_object(sim.upgrade_target_of(t.id, b)).is_same(sim.upgrade_target(t, b))
		assert_bool(sim.has_targeting_of(t.id)).is_equal(sim.has_targeting(t))
		assert_int(sim.sell_refund_of(t.id)).is_equal(sim.sell_refund(t))
		assert_int(sim.sell_refund_of(t.id)).is_greater(0)
		assert_int(sim.upgrade_tower(t.id, branches[0])).is_equal(SimCommand.CommandResult.OK)
	assert_array(sim.upgrade_branches_of(9999)).is_empty()
	assert_object(sim.upgrade_target_of(9999, "")).is_null()
	assert_bool(sim.has_targeting_of(9999)).is_false()
	assert_int(sim.sell_refund_of(9999)).is_equal(0)
