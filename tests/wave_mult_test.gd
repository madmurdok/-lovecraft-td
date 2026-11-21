class_name WaveMultTest
extends WaveTestBase
## LT-111 (docs/design/LT-111-wave-multipliers.md): a wave's optional hp_mult / speed_mult
## scale every enemy that enters while it is the current wave (real, fake, queued pack
## member): hp = max_hp = def.hp x hp_mult, base_max_hp = def.hp (owner Q1), base speed
## = units_per_tick(def.speed x speed_mult), one rounding, floored at 1 unit/tick for a
## moving def. Per wave, no carry-over; 1.0 before wave 1, past the last wave and without a
## waves config. Standalone SpawnSystem as in sim_spawn_test, plus one run through the
## WaveDirector from waves.json. The HP caps: silver_key_test, branch_effects_test.

var _ctx: SimContext
var _spawn: SpawnSystem


func before_test() -> void:
	_ctx = SimContext.new(tconfig(), SEED)
	_ctx.state.map = _ctx.config.map
	_ctx.state.lighthouse_hp = _ctx.config.economy.lighthouse_hp
	_spawn = SpawnSystem.new(_ctx)
	_spawn.set_trait_host(TraitHost.new(_ctx, _spawn.queue_pack_member))  # LT-106, like the facade


## Sets every wave of the context's config to `hp` / `speed` (the real data has 5 waves).
func _scale_all(hp: float, speed: float) -> void:
	for w: WavesConfig.Wave in _ctx.config.waves.waves:
		w.hp_mult = hp
		w.speed_mult = speed


func _set_wave(n: int, hp: float, speed: float) -> void:
	var w: WavesConfig.Wave = _ctx.config.waves.waves[n - 1]
	w.hp_mult = hp
	w.speed_mult = speed


func _enter_in(wave_index: int, def_id: String, fake := false) -> SimEnemy:
	_ctx.state.wave_index = wave_index
	return _enemy(_spawn.spawn_enemy(def_id, fake))


func _enemy(id: int) -> SimEnemy:
	for e in _ctx.state.enemies:
		if e.id == id:
			return e
	return null


## Asserts `e` has `def_id`'s stats scaled by `hp` / `speed`.
func _assert_scaled(e: SimEnemy, def_id: String, hp: float, speed: float, tag := "") -> void:
	var def: EnemyDef = _ctx.config.enemies[def_id]
	assert_object(e).override_failure_message(tag).is_not_null()
	assert_float(e.hp).override_failure_message("%s hp" % tag).is_equal(def.hp * hp)
	assert_float(e.max_hp).override_failure_message("%s max_hp" % tag).is_equal(def.hp * hp)
	assert_float(e.base_max_hp).override_failure_message("%s base_max_hp" % tag) \
		.is_equal(float(def.hp))
	assert_int(e.base_units_per_tick).override_failure_message("%s speed" % tag) \
		.is_equal(SimTime.units_per_tick(def.speed * speed))


# --- scaling ---------------------------------------------------------------------------------

func test_a_waves_multipliers_scale_hp_and_base_speed() -> void:
	_set_wave(2, 2.0, 1.5)
	var e := _enter_in(2, "cultist")
	_assert_scaled(e, "cultist", 2.0, 1.5)
	assert_float(e.hp).is_equal(120.0)
	assert_int(e.base_units_per_tick).is_equal(1500)  # 1.0 x 1.5 cells/s
	_set_wave(3, 0.5, 0.75)
	_assert_scaled(_enter_in(3, "hybrid"), "hybrid", 0.5, 0.75, "hybrid in wave 3")


func test_hp_is_not_rounded() -> void:
	_set_wave(1, 1.111, 1.0)  # owner Q3: no rounding of HP
	var e := _enter_in(1, "cultist")
	assert_float(e.hp).is_equal(60.0 * 1.111)
	assert_bool(e.hp == roundf(e.hp)).is_false()


func test_multipliers_are_per_wave_with_no_carry_over() -> void:
	_scale_all(3.0, 2.0)
	_set_wave(3, 1.0, 1.0)
	_assert_scaled(_enter_in(2, "cultist"), "cultist", 3.0, 2.0, "wave 2")
	_assert_scaled(_enter_in(3, "cultist"), "cultist", 1.0, 1.0, "wave 3 after a scaled wave")
	_assert_scaled(_enter_in(4, "cultist"), "cultist", 3.0, 2.0, "wave 4")


func test_before_wave_one_and_past_the_last_wave_the_multipliers_are_one() -> void:
	_scale_all(3.0, 2.0)
	var n := _ctx.config.waves.waves.size()
	_assert_scaled(_enter_in(0, "cultist"), "cultist", 1.0, 1.0, "wave_index 0")
	_assert_scaled(_enter_in(n, "cultist"), "cultist", 3.0, 2.0, "the last wave")
	_assert_scaled(_enter_in(n + 1, "cultist"), "cultist", 1.0, 1.0, "past the last wave")


func test_without_a_waves_config_the_multipliers_are_one() -> void:
	_scale_all(3.0, 2.0)
	_ctx.state.wave_index = 1
	_ctx.config.waves = null
	_assert_scaled(_enemy(_spawn.spawn_enemy("cultist")), "cultist", 1.0, 1.0)


func test_a_fake_gets_its_waves_multipliers() -> void:
	_set_wave(2, 2.0, 1.5)
	var real := _enter_in(2, "night_gaunt")
	var fake := _enter_in(2, "night_gaunt", true)
	assert_bool(fake.is_fake).is_true()
	_assert_scaled(fake, "night_gaunt", 2.0, 1.5, "fake")
	assert_float(fake.hp).is_equal(real.hp)
	assert_int(fake.base_units_per_tick).is_equal(real.base_units_per_tick)


func test_queued_pack_members_get_their_waves_multipliers() -> void:
	_set_wave(2, 2.0, 1.5)
	var first := _enter_in(2, "deep_one").id
	var fake_first := _enter_in(2, "deep_one", true).id
	var queued := _spawn._pack_queue.size()
	assert_int(queued).is_greater(1)
	_ctx.state.tick = 1000  # every member is due
	_spawn.release_pack_members(false)
	_spawn.release_pack_members(true)
	assert_int(_spawn._pack_queue.size()).is_equal(0)
	var members := 0
	for e in _ctx.state.enemies:
		if e.id != first and e.id != fake_first:
			assert_int(e.pack_of).is_in([first, fake_first])
			_assert_scaled(e, "deep_one", 2.0, 1.5, "member %d" % e.id)
			members += 1
	assert_int(members).is_equal(queued)


# --- speed rounding ----------------------------------------------------------------------------

func test_unscaled_speed_is_the_defs_units_per_tick() -> void:
	for id: String in _ctx.config.enemies:
		var e := _enter_in(1, id)
		assert_int(e.base_units_per_tick).override_failure_message(id) \
			.is_equal(SimTime.units_per_tick(_ctx.config.enemies[id].speed))


func test_a_speed_mult_that_rounds_to_zero_still_moves_one_unit_per_tick() -> void:
	_set_wave(1, 1.0, 0.0001)  # cultist 1.0 x 0.0001 cells/s = 0.1 units/tick -> 0
	assert_int(SimTime.units_per_tick(1.0 * 0.0001)).is_equal(0)
	assert_int(_enter_in(1, "cultist").base_units_per_tick).is_equal(1)


# --- through waves.json and the WaveDirector ----------------------------------------------------

## Config whose waves.json holds `waves` as given (wave dicts, so hp_mult/speed_mult fit).
func _mconfig(waves: Array) -> GameConfig:
	var r := load_edited(func(dir: String) -> void:
		write_file(dir, "waves.json", JSON.stringify({"build_phase_seconds": 1, "waves": waves}))
		edit(dir, MAP, func(root: Dictionary) -> void:
			root["width"] = ROWS[0].length()
			root["height"] = ROWS.size()
			root["rows"] = ROWS))
	assert_bool(r.ok).override_failure_message("config rejected:\n%s" % "\n".join(r.errors)) \
		.is_true()
	return r.config


## Steps until a real enemy of the current wave has entered; returns it.
func _next_spawn(sim: Simulation) -> SimEnemy:
	for i in 200:
		sim.step()
		for e in sim.state.enemies:
			if not e.is_fake and e.is_live():
				sim.drain_events()
				return e
	assert_bool(false).override_failure_message("no spawn in 200 ticks").is_true()
	return null


func test_waves_json_multipliers_reach_the_enemies_of_their_wave_only() -> void:
	var one := {"groups": [group("cultist", 1)]}
	var scaled := {"hp_mult": 2, "speed_mult": 1.5, "groups": [group("cultist", 1)]}
	var sim := Simulation.new(_mconfig([one, scaled, one]), SEED)
	director = WaveDirector.new(sim.config.waves)
	sim.set_spawner(director)
	var cultist: EnemyDef = sim.config.enemies["cultist"]
	for c: Array in [[1, 1.0, 1.0], [2, 2.0, 1.5], [3, 1.0, 1.0]]:
		var e := _next_spawn(sim)
		var tag := "wave %d" % c[0]
		assert_int(sim.state.wave_index).override_failure_message(tag).is_equal(c[0])
		assert_float(e.max_hp).override_failure_message(tag).is_equal(cultist.hp * c[1])
		assert_float(e.base_max_hp).override_failure_message(tag).is_equal(float(cultist.hp))
		assert_int(e.base_units_per_tick).override_failure_message(tag) \
			.is_equal(SimTime.units_per_tick(cultist.speed * c[2]))
		kill_real(sim)
		sim.step()  # removes the dead, clears the wave
