class_name FlareRadialTest
extends WaveTestBase
## LT-57 §7 (radial flare), LT-69 (whole map): while the flare burns every tower and enemy
## is lit, in every direction and at any distance, only while it burns; lit-by-flare
## effects are the beam's (Q2): enemies x enemy_speed_mult and no Madness buff, mundane x
## fire_interval_mult, occult x power_mult; fakes are slowed and shot but never revealed (Q3).
## Map: TowerTestBase ROWS, lighthouse cell (14, 0), centre (14.5, 0.5).

const RIFLE := "rifleman"
const NECRO := "necronomicon_reader"
const IN_CELL := Vector2i(11, 1)  ## centre (11.5, 1.5): v = (-3, 1)


func before() -> void:
	lit_beam = true  # the default fixture darkens the beam


# --- helpers ---------------------------------------------------------------------------------

## tsim (phase NONE: the beam shines) whose beam lights nothing (reach ~0) and stands still.
func _dark() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	sim.config.economy.beam.reach_cells = 0.0001
	return sim


## tsim with one still beam aimed away from the map (+x): every path cell is behind it.
func _away() -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	sim.state.beam_dx = 1.0
	sim.state.beam_dy = 0.0
	sim.state.prev_beam_dx = 1.0
	sim.state.prev_beam_dy = 0.0
	return sim


## Fires a flare now (oil and cooldown set up for it).
func _fire(sim: Simulation) -> void:
	sim.state.flare_cooldown_ticks = 0
	sim.state.oil = sim.config.economy.flare.cost_oil
	assert_int(sim.fire_flare()).is_equal(R.OK)


## Whether lighthouse centre + v is lit now.
func _lit(sim: Simulation, v: Vector2) -> bool:
	var lh := sim.config.map.lighthouse
	return sim._is_lit(lh.x + 0.5 + v.x, lh.y + 0.5 + v.y)


func _mods(e: SimEnemy) -> Array:
	return [snappedf(e.speed_mult, 0.0001), snappedf(e.damage_taken_mult, 0.0001)]


func _madness(sim: Simulation) -> void:
	sim.state.sanity = 0.0
	sim.state.sanity_state = sim.sanity_state_for(0.0)
	assert_int(sim.state.sanity_state).is_equal(SimState.SanityState.MADNESS)
	sim.drain_events()


# --- geometry --------------------------------------------------------------------------------

## b1/b2 (LT-69): all eight directions (behind the lighthouse, off the map too), near and
## far, are lit while the flare burns and not before; dark again once it runs out.
func test_the_flare_lights_every_direction_at_any_distance() -> void:
	var sim := _dark()
	var d := sqrt(0.5)
	var dirs: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
		Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d)]
	for flaring: bool in [false, true]:
		if flaring:
			_fire(sim)
		for u in dirs:
			var msg := "flaring=%s dir=%s" % [flaring, u]
			assert_bool(_lit(sim, u * 0.5)).override_failure_message(msg + " near").is_equal(flaring)
			assert_bool(_lit(sim, u * 30.0)).override_failure_message(msg + " far").is_equal(flaring)
	# The flare runs out: everything is dark again.
	run(sim, SimTime.ticks(sim.flare_seconds()))
	assert_int(sim.state.flare_ticks_left).is_equal(0)
	assert_bool(_lit(sim, Vector2(-1, 0))).is_false()


## b2: a point the beam lights stays lit with or without a flare.
func test_beam_lit_points_stay_lit_either_way() -> void:
	var sim := tsim()  # the starting beam points along the path (-x), reach 16
	sim.config.economy.beam.turn_t = 0.0
	var far := Vector2(-9.0, 0.0)
	assert_bool(_lit(sim, far)).is_true()
	_fire(sim)
	assert_bool(_lit(sim, far)).is_true()


# --- lit-by-flare effects (Q2, Q3) ----------------------------------------------------------

## b5: enemies behind the beam, near and far, are lit while the flare burns: x0.5 and no
## Madness buff; both are back to the buff after the flare.
func test_an_enemy_behind_the_beam_is_lit_slowed_and_loses_the_madness_buff() -> void:
	var sim := _away()
	var f := sim.config.economy.flare
	var mad := sim.config.sanity.madness
	_madness(sim)
	var buffed := [snappedf(mad.enemy_speed_multiplier, 0.0001),
		snappedf(mad.enemy_damage_taken_multiplier, 0.0001)]
	assert_array(buffed).is_not_equal([1.0, 1.0])
	var inside := put(sim, "cultist", 11.0)  # (11.5, 0.5): 3 cells behind the lighthouse
	var outside := put(sim, "cultist", 3.0)  # 11 cells away, lit too (LT-69)
	sim.step()
	assert_bool(inside.lit).is_false()
	assert_array(_mods(inside)).is_equal(buffed)
	_fire(sim)
	var n := SimTime.ticks(sim.flare_seconds())
	for i in n:
		_madness(sim)  # hold MADNESS: sanity may drift tick to tick
		sim.step()
		assert_bool(inside.lit).override_failure_message("tick %d" % i).is_true()
		assert_array(_mods(inside)).override_failure_message("tick %d" % i) \
			.is_equal([snappedf(f.enemy_speed_mult, 0.0001), 1.0])
		assert_bool(outside.lit).override_failure_message("tick %d" % i).is_true()
		assert_array(_mods(outside)).override_failure_message("tick %d" % i) \
			.is_equal([snappedf(f.enemy_speed_mult, 0.0001), 1.0])
	_madness(sim)
	sim.step()
	assert_bool(inside.lit).is_false()
	assert_array(_mods(inside)).is_equal(buffed)


## b5 (Q3): a fake is lit and slowed like a real one, still shot at, and never
## revealed.
func test_a_fake_is_slowed_shot_and_not_revealed() -> void:
	var sim := _away()
	var f := sim.config.economy.flare
	var rifle := build(sim, RIFLE, IN_CELL)
	var fake := put(sim, "cultist", 11.0, HUGE_HP, true)
	_fire(sim)
	var shots := 0
	for i in SimTime.ticks(sim.flare_seconds()):
		sim.step()
		for ev in of_type(sim.drain_events(), SimEvent.Type.SHOT):
			if ev.id == rifle.id and ev.data["target"] == fake.id:
				shots += 1
		assert_bool(fake.lit).override_failure_message("tick %d" % i).is_true()
		assert_float(fake.speed_mult).is_equal_approx(f.enemy_speed_mult, 1e-9)
		assert_bool(fake.revealed).override_failure_message("tick %d" % i).is_false()
	assert_int(shots).is_greater(0)
	assert_bool(fake.is_live()).is_true()


## b5: an occult tower works at power_mult while the flare burns (and at full
## power without it); the beam lights neither.
func test_an_occult_tower_is_lit_at_power_mult() -> void:
	var pm := tconfig().economy.beam.occult_power_mult
	assert_float(pm).is_equal(0.7)
	for flaring: bool in [false, true]:
		var sim := _away()
		var dmg: float = sim.config.towers[NECRO].levels[0].damage
		var necro := build(sim, NECRO, IN_CELL)
		var e := put(sim, "cultist", 11.0)
		if flaring:
			_fire(sim)
		sim.step()
		assert_bool(necro.lit).override_failure_message("flaring=%s" % flaring).is_equal(flaring)
		assert_float(e.hp).override_failure_message("flaring=%s" % flaring).is_equal_approx(
			HUGE_HP - dmg * (pm if flaring else 1.0), 0.0001)


## b5: a mundane tower fires at fire_interval x fire_interval_mult while the
## flare burns.
func test_a_mundane_tower_fires_faster_while_the_flare_burns() -> void:
	var fi: float = tconfig().towers[RIFLE].levels[0].fire_interval
	var m := tconfig().economy.beam.mundane_fire_interval_mult
	var gaps := []
	for flaring: bool in [false, true]:
		var sim := _away()
		build(sim, RIFLE, IN_CELL)
		put(sim, "cultist", 11.0)
		if flaring:
			_fire(sim)
		sim.drain_events()
		var ticks := shot_ticks(run(sim, SimTime.ticks(fi) + 5))
		assert_int(ticks.size()).is_greater_equal(2)
		gaps.append(ticks[1] - ticks[0])
	assert_array(gaps).is_equal([maxi(1, SimTime.ticks(fi)), maxi(1, SimTime.ticks(fi * m))])
