class_name TraitHooksTest
extends TowerTestBase
## LT-106 (docs/design/LT-106-trait-hooks.md §4): enemy trait hooks, the trait catalog and the
## status registry. Hook calls are observed through ProbeTrait (tests/fixtures/probe_trait.gd),
## injected into TraitCatalog where its catalog line would put it (after the shipped rows),
## then EnemyDef.build_hooks() and only then the Simulation (TraitSystem reads the defs' hook
## bits at construction). Pack's RNG draws are pinned on the stream states.

const CARRIER := "hybrid"  ## an enemy with no traits in data/enemies.json

## Probe ids injected by the current test; after_test takes them out of the catalog again.
var _injected: Array[String] = []
var _calls: Array = []


func before_test() -> void:
	_calls = []
	_injected = []


func after_test() -> void:
	for id in _injected:
		var p: ProbeTrait = TraitCatalog._by_id.get(id)
		if p != null:  # breaks def -> probe -> state -> enemy -> def, a RefCounted cycle
			p.state = null
			p.tower = null
		TraitCatalog._by_id.erase(id)


## Puts `probe` into the catalog after the rows already there, as a line appended to
## TraitCatalog._rows() would.
func _inject(probe: EnemyTrait) -> void:
	TraitCatalog.ids()  # builds the shipped rows first
	TraitCatalog._by_id[probe.id()] = probe
	_injected.append(probe.id())


func _probe(id: String, mask: int) -> ProbeTrait:
	var p := ProbeTrait.new(id, mask, _calls)
	_inject(p)
	return p


## A tsim config whose CARRIER carries `probes` ({"tag": i}), hooks built before the sim.
func _probe_sim(probes: Array) -> Simulation:
	var cfg := tconfig()
	var d: EnemyDef = cfg.enemies[CARRIER]
	for i in probes.size():
		d.traits[(probes[i] as EnemyTrait).id()] = {"tag": float(i)}
	d.build_hooks()
	var sim := Simulation.new(cfg, SEED)
	for p: ProbeTrait in probes:
		p.state = sim.state
	return sim


## [trait id, hook, enemy id] of every recorded call of `hook` ("" = every hook).
func _seen(hook := "") -> Array:
	var out := []
	for c: Array in _calls:
		if hook == "" or c[1] == hook:
			out.append([c[0], c[1], c[2]])
	return out


func _of(hook: String) -> Array:
	var out := []
	for c: Array in _calls:
		if c[1] == hook:
			out.append(c)
	return out


func _rng_states(rng_of: Callable) -> Array[int]:
	var out: Array[int] = []
	for s: int in SimRng.Stream.values():
		out.append((rng_of.call(s) as RandomNumberGenerator).state)
	return out


# --- behaviour 2 (T6): pack's one roll per spawn event ----------------------------------------

## One SPAWN draw per real pack spawn event, one SANITY draw per fake one, nothing else moves.
func test_pack_rolls_once_per_spawn_event_on_spawn_or_sanity() -> void:
	var cfg := real_config()
	var pack: Dictionary = cfg.enemies["deep_one"].traits["pack"]
	assert_int(int(pack["max"])).is_greater(int(pack["min"]))  # a roll that draws
	for fake: bool in [false, true]:
		var sim := Simulation.new(cfg, 42)
		var ref := Simulation.new(cfg, 42)
		var before := _rng_states(sim.rng)
		sim.spawn_enemy("deep_one", fake)
		var stream := SimRng.Stream.SANITY if fake else SimRng.Stream.SPAWN
		ref.rng(stream).randi_range(int(pack["min"]), int(pack["max"]))
		assert_array(_rng_states(sim.rng)).override_failure_message("fake=%s" % fake) \
			.is_equal(_rng_states(ref.rng))
		assert_array(_rng_states(sim.rng)).is_not_equal(before)


func test_non_pack_spawn_draws_nothing() -> void:
	var sim := Simulation.new(real_config(), 42)
	var before := _rng_states(sim.rng)
	sim.spawn_enemy(CARRIER)
	sim.spawn_enemy(CARRIER, true)
	assert_array(_rng_states(sim.rng)).is_equal(before)


## A queued member's entry runs on_spawn with from_event false: pack does not roll again.
func test_queued_pack_member_entry_draws_nothing() -> void:
	for fake: bool in [false, true]:
		var ctx := SimContext.new(real_config(), 42)
		ctx.state.map = ctx.config.map
		ctx.state.lighthouse_hp = ctx.config.economy.lighthouse_hp
		var spawn := SpawnSystem.new(ctx)
		spawn.set_trait_host(TraitHost.new(ctx, spawn.queue_pack_member))
		spawn.spawn_enemy("deep_one", fake)
		assert_int(ctx.state.enemies.size()).is_equal(1)
		var before := _rng_states(ctx.rng)
		ctx.state.tick += 10000
		spawn.release_pack_members(fake)
		assert_int(ctx.state.enemies.size()).override_failure_message("fake=%s" % fake) \
			.is_greater_equal(int(ctx.config.enemies["deep_one"].traits["pack"]["min"]))
		assert_array(_rng_states(ctx.rng)).override_failure_message("fake=%s" % fake) \
			.is_equal(before)


# --- behaviour 4 (T3): catalog order, shared params -------------------------------------------

func test_hook_traits_follow_catalog_order_not_json_order() -> void:
	_probe("probe_z", EnemyTrait.ON_SPAWN | EnemyTrait.ON_TICK)
	_probe("probe_a", EnemyTrait.ON_DEATH)
	var d := EnemyDef.new()
	d.traits = {"probe_a": {"tag": 1.0}, "regen": {"hp_percent_per_second": 1.0},
		"boss": {}, "probe_z": {"tag": 2.0}, "pack": {"min": 2.0, "max": 3.0, "spacing_s": 0.5}}
	d.build_hooks()
	var ids: Array[String] = []
	for t in d.hook_traits:
		ids.append(t.id())
	# Catalog order: the shipped rows (pack first), then the probes in injection order;
	# pending (regen) and hook-less (boss) traits are left out.
	assert_array(ids).is_equal(["pack", "probe_z", "probe_a"])
	assert_array(d.traits.keys()).is_not_equal(["pack", "probe_z", "probe_a"])
	assert_int(d.hook_params.size()).is_equal(3)
	for i in ids.size():
		assert_bool(is_same(d.hook_params[i], d.traits[ids[i]])) \
			.override_failure_message("hook_params[%d] is not traits[%s]" % [i, ids[i]]).is_true()
	assert_int(d.hooks).is_equal(EnemyTrait.ON_SPAWN | EnemyTrait.ON_TICK | EnemyTrait.ON_DEATH)


# --- behaviour 5 (T4): call points and gating ---------------------------------------------------

## A hit the enemy survives runs on_damaged (taken, source); the killing hit runs on_death once,
## after the kill hook's token drop, and no on_damaged.
func test_on_damaged_for_a_survivor_on_death_once_after_the_token_drop() -> void:
	var probe := _probe("probe", EnemyTrait.ON_DAMAGED | EnemyTrait.ON_DEATH)
	var sim := _probe_sim([probe])
	var e := put(sim, CARRIER, 3.0, 100.0)
	assert_array(_calls).is_empty()
	var removed := sim.apply_damage(e.id, 30.0, "hit")
	assert_float(removed).is_greater(0.0)
	assert_bool(e.dead).is_false()
	assert_array(_seen()).is_equal([["probe", "on_damaged", e.id]])
	var c: Array = _calls[0]
	assert_bool(is_same(c[3], e.def.traits["probe"])).is_true()
	assert_float(c[4]).is_equal(removed)
	assert_str(c[5]).is_equal("hit")
	assert_int(sim.state.relic_tokens.size()).is_equal(0)
	sim.apply_damage(e.id, 1e9, "kill")
	assert_bool(e.dead).is_true()
	sim.apply_damage(e.id, 1e9, "again")  # a dead enemy takes no hit: no hook
	assert_array(_seen()).is_equal([["probe", "on_damaged", e.id], ["probe", "on_death", e.id]])
	assert_str(_calls[1][4]).is_equal("kill")
	assert_int(_calls[1][5]).override_failure_message("on_death ran before the token drop") \
		.is_equal(1)


## Real leaks run on_leak after LEAKED; a fake dissolves at the lighthouse without it.
func test_on_leak_for_a_real_leak_only() -> void:
	var probe := _probe("probe", EnemyTrait.ON_LEAK)
	var sim := _probe_sim([probe])
	var real := put(sim, CARRIER, 0.0)
	var fake := put(sim, CARRIER, 0.0, HUGE_HP, true)
	for e: SimEnemy in [real, fake]:
		e.distance = e.route.length
		e.prev_distance = e.distance
	sim.step()
	assert_bool(real.leaked).is_true()
	assert_bool(fake.dissolved).is_true()
	assert_array(_seen()).is_equal([["probe", "on_leak", real.id]])


## Spawn events run on_spawn with from_event true, for fakes too.
func test_on_spawn_for_real_and_fake_spawn_events() -> void:
	var probe := _probe("probe", EnemyTrait.ON_SPAWN)
	var sim := _probe_sim([probe])
	var a := sim.spawn_enemy(CARRIER)
	var b := sim.spawn_enemy(CARRIER, true)
	assert_array(_seen()).is_equal([["probe", "on_spawn", a], ["probe", "on_spawn", b]])
	assert_bool(_calls[0][4]).is_true()
	assert_bool(_calls[1][4]).is_true()


## near_tower runs after the light writer (sees its channel value) and before apply_auras
## (sees no aura on the enemy yet, and the aura sees the trait's modify_tower write);
## on_tick runs after the status timers.
func test_near_tower_between_light_and_auras_on_tick_after_statuses() -> void:
	var probe := _probe("probe", EnemyTrait.NEAR_TOWER | EnemyTrait.ON_TICK)
	var sim := _probe_sim([probe])
	var twin := Simulation.new(sim.config, SEED)  # same defs, its probe writes nothing
	var signs: Array[SimTower] = []
	var enemies: Array[SimEnemy] = []
	for s: Simulation in [sim, twin]:
		signs.append(build(s, "elder_sign", TOWER))
		build(s, "elder_sign", TOWER + Vector2i(1, 0))  # shadows the first: light writes it
		var e := put(s, CARRIER, 7.0)
		e.status["pull_immune_ticks"] = 5
		enemies.append(e)
	probe.tower = signs[1]
	probe.state = twin.state
	twin.step()
	var light_pm := signs[1].power_mult
	var twin_mult := enemies[1].damage_taken_mult
	assert_float(light_pm).override_failure_message("light wrote nothing: no order to see") \
		.is_not_equal(1.0)
	assert_float(twin_mult).is_greater(1.0)
	_calls.clear()
	probe.tower = signs[0]
	probe.state = sim.state
	probe.write_power = 2.0
	sim.step()
	var near := _of("near_tower")
	assert_int(near.size()).is_equal(1)
	assert_float(near[0][4]).override_failure_message("near_tower saw the aura: ran after it") \
		.is_equal(1.0)
	assert_float(near[0][5]).override_failure_message("near_tower ran before the light") \
		.is_equal(light_pm)
	assert_float(signs[0].power_mult).is_equal_approx(light_pm * 2.0, 1e-9)
	assert_float(enemies[0].damage_taken_mult).override_failure_message(
		"apply_auras did not see the trait's channel write").is_equal_approx(
		TowerRules.powered_taken_mult(1.5, light_pm * 2.0), 1e-9)
	assert_float(enemies[0].damage_taken_mult).is_greater(twin_mult)
	var ticks := _of("on_tick")
	assert_int(ticks.size()).is_equal(1)
	assert_int(ticks[0][4]).override_failure_message("on_tick ran before tick_statuses") \
		.is_equal(4)


## At one call point: enemies in id order, then catalog order within one enemy.
func test_hook_order_is_enemy_id_then_catalog_order() -> void:
	var z := _probe("probe_z", EnemyTrait.ON_TICK | EnemyTrait.NEAR_TOWER)
	var a := _probe("probe_a", EnemyTrait.ON_TICK | EnemyTrait.NEAR_TOWER)
	var sim := _probe_sim([a, z])  # carrier lists probe_a first
	var e1 := put(sim, CARRIER, 2.0)
	var e2 := put(sim, CARRIER, 4.0)
	assert_int(e2.id).is_greater(e1.id)
	sim.step()
	for hook: String in ["near_tower", "on_tick"]:
		assert_array(_seen(hook)).override_failure_message(hook).is_equal([
			["probe_z", hook, e1.id], ["probe_a", hook, e1.id],
			["probe_z", hook, e2.id], ["probe_a", hook, e2.id]])


## TraitSystem reads the defs' hook bits once, at construction: a pass whose bit no def had
## then is skipped whole (the event hooks, dispatched per enemy, still run).
func test_trait_passes_skip_when_no_def_had_their_hook_at_construction() -> void:
	var probe := _probe("probe", EnemyTrait.ON_TICK | EnemyTrait.NEAR_TOWER | EnemyTrait.ON_DAMAGED)
	var sim := tsim()
	var d: EnemyDef = sim.config.enemies[CARRIER]
	d.traits["probe"] = {"tag": 0.0}
	d.build_hooks()
	assert_int(d.hooks & EnemyTrait.ON_TICK).is_not_zero()
	var e := put(sim, CARRIER, 3.0)
	run(sim, 3)
	sim.apply_damage(e.id, 1.0, "hit")
	assert_array(_seen()).is_equal([["probe", "on_damaged", e.id]])


# --- behaviour 7: the catalog ------------------------------------------------------------------

func test_catalog_ids_and_pending_ids() -> void:
	assert_array(TraitCatalog.ids()).is_equal(
		["pack", "tower_harass", "tower_lift", "regen", "boss"])
	assert_array(Array(TraitCatalog.pending_ids())).is_equal(
		["tower_harass", "tower_lift", "regen"])


# --- behaviour 8 (T8): markers ----------------------------------------------------------------

## EntityLayer.enemy_markers as it was before LT-106 (eb6444d), frozen.
static func _old_markers(e: SimEnemy) -> PackedStringArray:
	var out := PackedStringArray()
	if e.speed_mult < 0.999:
		out.append("slow")
	if e.damage_taken_mult > 1.001:
		out.append("vuln")
	if e.status.get("bleed_ticks", 0) > 0:
		out.append("bleed")
	if e.status.get("banish_immune_ticks", 0) > 0:
		out.append("sealed")
	return out


func test_markers_equal_the_pre_lt106_mapping_for_every_status() -> void:
	var values := [null, 0, 3]
	var checked := 0
	for slow: float in [1.0, 0.7]:
		for taken: float in [1.0, 1.25]:
			for bleed: Variant in values:
				for banish: Variant in values:
					for pull: Variant in values:
						var e := SimEnemy.new()
						e.speed_mult = slow
						e.damage_taken_mult = taken
						# Insertion order the reverse of the marker order: markers() must not
						# follow the dictionary's order.
						for kv: Array in [["pull_immune_ticks", pull],
								["banish_immune_ticks", banish], ["bleed_ticks", bleed]]:
							if kv[1] != null:
								e.status[kv[0]] = kv[1]
						if bleed != null:
							e.status["bleed_dps"] = 2.0
						assert_array(Array(e.markers())).override_failure_message(
							"status %s slow %s taken %s" % [e.status, slow, taken]).is_equal(
							Array(_old_markers(e)))
						checked += 1
	assert_int(checked).is_equal(108)
	var all := SimEnemy.new()
	all.speed_mult = 0.5
	all.damage_taken_mult = 2.0
	all.status = {"pull_immune_ticks": 1, "banish_immune_ticks": 1, "bleed_ticks": 1}
	assert_array(Array(all.markers())).is_equal(["slow", "vuln", "bleed", "sealed"])


func test_countdown_keys_keep_the_pre_lt106_order() -> void:
	assert_array(Array(CombatSystem.IMMUNITY_KEYS)).is_equal(
		["pull_immune_ticks", "banish_immune_ticks"])
	assert_array(Array(StatusRules.COUNTDOWN_KEYS)).is_equal(Array(CombatSystem.IMMUNITY_KEYS))


# --- behaviour 11 (Q2): a new enemy-only trait = one file + one catalog line --------------------

func _carrier_with(traits: Dictionary) -> ConfigLoadResult:
	return load_edited(func(dir: String) -> void:
		_apply_edits(dir, ROWS, -1, {CARRIER: {"traits": traits}}))


func test_a_probe_trait_is_one_file_and_one_catalog_line_end_to_end() -> void:
	var probe := ProbeTrait.new("probe_e2e", EnemyTrait.ON_SPAWN | EnemyTrait.ON_DAMAGED | EnemyTrait.ON_DEATH, _calls)
	var path := "enemies.%s.traits" % CARRIER
	# Without its catalog line the id is unknown to the config.
	assert_rejected(_carrier_with({"probe_e2e": {"tag": 3}}), ENEMIES, path + ".probe_e2e",
		"unknown field")
	_inject(probe)
	# With it, its params() are the schema ...
	assert_rejected(_carrier_with({"probe_e2e": {}}), ENEMIES, path + ".probe_e2e.tag",
		"missing required field")
	var r := _carrier_with({"probe_e2e": {"tag": 3}})
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var d: EnemyDef = r.config.enemies[CARRIER]
	assert_dict(d.traits).is_equal({"probe_e2e": {"tag": 3.0}})
	assert_array(d.hook_traits).is_equal([probe])
	# ... and the sim calls its hooks: no other file changed.
	var sim := Simulation.new(r.config, SEED)
	probe.state = sim.state
	var e := sim.enemy_by_id(sim.spawn_enemy(CARRIER))
	sim.apply_damage(e.id, 1.0, "hit")
	sim.apply_damage(e.id, 1e9, "kill")
	assert_array(_seen()).is_equal([["probe_e2e", "on_spawn", e.id],
		["probe_e2e", "on_damaged", e.id], ["probe_e2e", "on_death", e.id]])
	assert_dict(_calls[0][3]).is_equal({"tag": 3.0})
