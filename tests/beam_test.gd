class_name BeamTest
extends WaveTestBase
## LT-30 (LT-26 §1.1, addendum §1-§3): the lighthouse beam in the sim. Trig-free lit test on
## both sides of a cone edge for 1/2/4/8 beams, the rational rotation and the "sweep" arc,
## night-only lighting, upgrade_lighthouse, every config-driven modifier (lit mundane rate and
## no misses, lit occult power for the Necronomicon and the Elder Sign, madness-buff cancel),
## lamp oil (buy_oil) and the flare (fire_flare). Map: TowerTestBase ROWS, lighthouse cell
## (14, 0), centre (14.5, 0.5); the path row lies on the axis of the starting beam (-1, 0).

const T := SimEvent.Type
const S := SimState.SanityState
const P := SimState.Phase
const RIFLE := "rifleman"
const SIGN := "elder_sign"
const NECRO := "necronomicon_reader"
const EPS := 1.0e-3  ## relative step across a cone edge
const TRIG := "\\b(sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh)\\s*\\(|\\.(angle|angle_to|angle_to_point|rotated|from_angle)\\s*\\("


func before() -> void:
	lit_beam = true  # the default fixture darkens the beam (SimTestBase)


# --- helpers ---------------------------------------------------------------------------

## Config over ROWS with economy.json `lighthouse` edited by `fn(lighthouse)`.
func _econ(fn: Callable) -> GameConfig:
	var r := load_edited(func(dir: String) -> void:
		edit(dir, MAP, func(root: Dictionary) -> void:
			root["width"] = ROWS[0].length()
			root["height"] = ROWS.size()
			root["rows"] = ROWS)
		edit(dir, ECON, func(root: Dictionary) -> void: fn.call(root["lighthouse"])))
	assert_bool(r.ok).override_failure_message("config rejected:\n%s" % "\n".join(r.errors)) \
		.is_true()
	return r.config


## Points the base beam at (x, y) (unit) for this and the previous tick.
func _aim(sim: Simulation, x: float, y: float) -> void:
	sim.state.beam_dx = x
	sim.state.beam_dy = y
	sim.state.prev_beam_dx = x
	sim.state.prev_beam_dy = y


## tsim (phase NONE: the beam shines) with a still beam: lit along the path row, or aimed
## away from the map (+x) when not `lit`.
func _still(lit := true) -> Simulation:
	var sim := tsim()
	sim.state.gold = 1000000
	sim.config.economy.beam.turn_t = 0.0
	if not lit:
		_aim(sim, 1.0, 0.0)
	return sim


## Whether the point lighthouse centre + (vx, vy) is lit now.
func _lit(sim: Simulation, vx: float, vy: float) -> bool:
	var lh := sim.config.map.lighthouse
	return sim._is_lit(lh.x + 0.5 + vx, lh.y + 0.5 + vy)


## Beam directions of `count` beams from (x, y): negation, perpendiculars, 45° by sqrt(0.5).
func _expected_dirs(x: float, y: float, count: int) -> Array:
	var r := sqrt(0.5)
	var all := [[x, y], [(x - y) * r, (x + y) * r], [-y, x], [-(x + y) * r, (x - y) * r],
		[-x, -y], [-(x - y) * r, -(x + y) * r], [y, -x], [(x + y) * r, -(x - y) * r]]
	var step := 8 / count
	var out := []
	for i in count:
		out.append(all[i * step])
	return out


## A wave sim stepped into its first day (BUILD); waves of one deep_one each.
func _day_sim(waves := 2) -> Simulation:
	var w: Array = []
	for i in waves:
		w.append([group("deep_one", 1)])
	var sim := wsim(w, 5)
	sim.step()
	assert_int(sim.state.phase).is_equal(P.BUILD)
	sim.state.gold = 100000
	sim.drain_events()
	return sim


## Steps (killing every real enemy first) until the phase is `phase`; returns the events.
func _until(sim: Simulation, phase: P) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	var guard := 0
	while sim.state.phase != phase and guard < 20000:
		kill_real(sim)
		sim.step()
		out.append_array(sim.drain_events())
		guard += 1
	assert_int(sim.state.phase).is_equal(phase)
	return out


func _lit_events(events: Array[SimEvent], tower_id: int) -> Array:
	var out := []
	for e in of_type(events, T.TOWER_LIT):
		if e.id == tower_id:
			out.append([e.tick, e.data["lit"]])
	return out


func _mods(e: SimEnemy) -> Array:
	return [snappedf(e.speed_mult, 0.0001), snappedf(e.damage_taken_mult, 0.0001)]


func _set_sanity(sim: Simulation, v: float) -> void:
	sim.state.sanity = v
	sim.state.sanity_state = sim.sanity_state_for(v)
	sim.drain_events()


# --- the lit test (LT-26 §1.1), trig-free ------------------------------------------------

func test_cone_edges_for_1_2_4_and_8_beams() -> void:
	for count: int in [1, 2, 4, 8]:
		var sim := _still()
		sim.config.economy.beam.levels[2].beams = count if count == 8 else 4
		sim.state.lighthouse_level = {1: 0, 2: 1, 4: 2, 8: 2}[count]
		assert_int(sim.beam_count()).is_equal(count)
		_aim(sim, 0.6, -0.8)  # off-axis, so no beam is axis-aligned
		var k := sim.config.economy.beam.half_width_ratio
		var dist := 5.0
		var lit_dirs := _expected_dirs(0.6, -0.8, count)
		for d: Array in _expected_dirs(0.6, -0.8, 8):
			var dx: float = d[0]
			var dy: float = d[1]
			var on := lit_dirs.has(d)
			var msg := "%d beams, dir %s" % [count, d]
			assert_bool(_lit(sim, dx * dist, dy * dist)).override_failure_message(msg) \
				.is_equal(on)
			if not on:
				continue
			for side: float in [1.0, -1.0]:
				var px := -dy * side
				var py := dx * side
				var w_in := k * dist * (1.0 - EPS)
				var w_out := k * dist * (1.0 + EPS)
				assert_bool(_lit(sim, dx * dist + px * w_in, dy * dist + py * w_in)) \
					.override_failure_message(msg + " inside edge").is_true()
				assert_bool(_lit(sim, dx * dist + px * w_out, dy * dist + py * w_out)) \
					.override_failure_message(msg + " outside edge").is_false()


func test_reach_and_the_lighthouse_side_bound_the_cone() -> void:
	var sim := _still()
	var reach := sim.config.economy.beam.reach_cells
	assert_bool(_lit(sim, -(reach - 0.01), 0.0)).is_true()
	assert_bool(_lit(sim, -(reach + 0.01), 0.0)).is_false()
	assert_bool(_lit(sim, 0.0, 0.0)).is_false()  # v·d = 0
	assert_bool(_lit(sim, 1.0, 0.0)).is_false()  # behind a single beam


func test_the_sim_has_no_trig() -> void:
	var re := RegEx.create_from_string(TRIG)
	var files := _gd_files("res://sim")
	assert_int(files.size()).is_greater(5)
	assert_bool(files.has("res://sim/core/simulation.gd")).is_true()
	for f: String in files:
		var src := FileAccess.get_file_as_string(f)
		var m := re.search(src)
		assert_object(m).override_failure_message(
			"%s: %s" % [f, m.get_string() if m != null else ""]).is_null()


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


# --- rotation, sweep, determinism ------------------------------------------------------------

func test_one_tick_turns_by_the_rational_rotation_of_turn_t() -> void:
	var sim := tsim()
	var t := sim.config.economy.beam.turn_t
	assert_float(t).is_not_equal(0.0)
	assert_float(sim.state.beam_dx).is_equal(-1.0)
	assert_float(sim.state.beam_dy).is_equal(0.0)
	sim.step()
	var q := 1.0 + t * t
	assert_float(sim.state.beam_dx).is_equal_approx(-(1.0 - t * t) / q, 1e-12)
	assert_float(sim.state.beam_dy).is_equal_approx(-2.0 * t / q, 1e-12)
	assert_float(sim.state.prev_beam_dx).is_equal(-1.0)
	assert_float(sim.state.prev_beam_dy).is_equal(0.0)
	for i in 5000:
		sim.step()
	var n := sim.state.beam_dx * sim.state.beam_dx + sim.state.beam_dy * sim.state.beam_dy
	assert_float(n).is_equal_approx(1.0, 1e-12)


func test_same_seed_same_beam_and_events() -> void:
	var runs := []
	for i in 2:
		var sim := _day_sim(1)
		for c: Vector2i in [Vector2i(3, 1), Vector2i(7, 1), Vector2i(12, 1)]:
			build(sim, RIFLE, c)
		sim.call_wave()
		var ev := run(sim, 600)
		runs.append([sim.state.beam_dx, sim.state.beam_dy, strings_of(ev), of_type(ev,
			T.TOWER_LIT).size()])
	assert_float(runs[0][0]).is_equal(runs[1][0])
	assert_float(runs[0][1]).is_equal(runs[1][1])
	assert_array(runs[0][2]).is_equal(runs[1][2])
	assert_int(runs[0][3]).is_greater(0)  # the turning beam did flip towers


func test_sweep_starts_at_its_first_edge_and_stays_in_its_arc() -> void:
	var cfg := _econ(func(lh: Dictionary) -> void:
		lh["beam"]["pattern"] = "sweep"
		lh["beam"]["sweep_edges"] = [[0, -2], [3, 0]])
	var sim := Simulation.new(cfg, SEED)
	assert_float(sim.state.beam_dx).is_equal(0.0)
	assert_float(sim.state.beam_dy).is_equal(-1.0)
	assert_float(sim.state.prev_beam_dy).is_equal(-1.0)
	var t := cfg.economy.beam.turn_t
	var tol := 2.0 * absf(t) / (1.0 + t * t) + 1e-9  # one tick of overshoot past an edge
	var flips := 0
	var cur_sign := sim.state.beam_sign
	var near0 := 0
	var near1 := 0
	for i in 3000:
		sim.step()
		var x := sim.state.beam_dx
		var y := sim.state.beam_dy
		# Inside the arc from (0, -1) counter-clockwise to (1, 0): x >= 0 and y <= 0.
		assert_bool(x >= -tol and y <= tol).override_failure_message(
			"tick %d: (%f, %f) outside the arc" % [sim.state.tick, x, y]).is_true()
		if sim.state.beam_sign != cur_sign:
			flips += 1
			cur_sign = sim.state.beam_sign
		if x <= tol:
			near0 += 1
		if y >= -tol:
			near1 += 1
	assert_int(flips).is_greater_equal(4)
	assert_int(near0).is_greater(0)
	assert_int(near1).is_greater(0)


# --- night only ------------------------------------------------------------------------------

func test_dark_by_day_lit_at_night_and_dark_again_at_dawn() -> void:
	var sim := _day_sim(2)
	sim.config.economy.beam.turn_t = 0.0
	var tw := build(sim, RIFLE, TOWER)  # (7, 1): inside the starting beam
	var ev := run(sim, 10)
	assert_bool(tw.lit).is_false()
	assert_array(_lit_events(ev, tw.id)).is_empty()
	assert_array(sim.beam_directions(0.5)).is_empty()
	assert_float(sim.state.beam_dx).is_equal(-1.0)
	sim.call_wave()
	sim.drain_events()
	ev = run(sim, 1)
	assert_int(sim.state.phase).is_equal(P.WAVE)
	assert_bool(tw.lit).is_true()
	assert_array(_lit_events(ev, tw.id)).is_equal([[sim.state.tick, true]])
	ev = run(sim, 3)
	assert_array(_lit_events(ev, tw.id)).is_empty()  # only flips emit
	ev = _until(sim, P.BUILD)
	ev.append_array(run(sim, 1))
	assert_bool(tw.lit).is_false()
	var flips := _lit_events(ev, tw.id)
	assert_int(flips.size()).is_equal(1)
	assert_bool(flips[0][1]).is_false()
	for e in sim.state.enemies:
		assert_bool(e.lit).is_false()


func test_the_beam_holds_by_day_and_turns_at_night() -> void:
	var sim := _day_sim(1)
	var dx := sim.state.beam_dx
	var dy := sim.state.beam_dy
	run(sim, 20)
	assert_float(sim.state.beam_dx).is_equal(dx)
	assert_float(sim.state.beam_dy).is_equal(dy)
	assert_float(sim.state.prev_beam_dx).is_equal(dx)
	sim.call_wave()
	run(sim, 1)
	assert_bool(sim.state.beam_dx != dx or sim.state.beam_dy != dy).is_true()


## A real run reaches DONE together with the WON outcome, which freezes step(); the phase
## rule itself is pinned on a director-less sim put in DONE.
func test_done_is_dark() -> void:
	var sim := _still()
	var tw := build(sim, RIFLE, TOWER)
	run(sim, 1)
	assert_bool(tw.lit).is_true()
	sim.state.phase = P.DONE
	var ev := run(sim, 1)
	assert_bool(tw.lit).is_false()
	assert_array(_lit_events(ev, tw.id)).is_equal([[sim.state.tick, false]])
	assert_array(sim.beam_directions(1.0)).is_empty()
	var won := _day_sim(1)
	won.call_wave()
	_until(won, P.DONE)
	assert_array(won.beam_directions(1.0)).is_empty()


func test_phase_none_lights_without_a_wave_director() -> void:
	var sim := _still()
	var tw := build(sim, RIFLE, TOWER)
	var e := put(sim, "cultist", 3.0)
	assert_int(sim.state.phase).is_equal(P.NONE)
	var ev := run(sim, 1)
	assert_bool(tw.lit).is_true()
	assert_bool(e.lit).is_true()
	assert_array(_lit_events(ev, tw.id)).is_equal([[sim.state.tick, true]])
	var away := _still(false)
	var tw2 := build(away, RIFLE, TOWER)
	var e2 := put(away, "cultist", 3.0)
	run(away, 1)
	assert_bool(tw2.lit).is_false()
	assert_bool(e2.lit).is_false()


func test_beam_directions_interpolate_prev_to_current_one_per_beam() -> void:
	var sim := tsim()
	sim.state.lighthouse_level = 1
	run(sim, 7)
	var d0 := sim.beam_directions(0.0)
	var d1 := sim.beam_directions(1.0)
	assert_int(d0.size()).is_equal(2)
	assert_float(d0[0].x).is_equal_approx(sim.state.prev_beam_dx, 1e-6)
	assert_float(d0[0].y).is_equal_approx(sim.state.prev_beam_dy, 1e-6)
	assert_float(d1[0].x).is_equal_approx(sim.state.beam_dx, 1e-6)
	assert_float(d1[0].y).is_equal_approx(sim.state.beam_dy, 1e-6)
	assert_float(d1[1].x).is_equal_approx(-sim.state.beam_dx, 1e-6)


# --- upgrade_lighthouse ----------------------------------------------------------------------

func test_upgrade_pays_money_logs_and_adds_beams_1_2_4() -> void:
	var sim := _day_sim()
	var levels := sim.config.economy.beam.levels
	assert_int(sim.beam_count()).is_equal(1)
	for want: Array in [[1, 2], [2, 4]]:
		var cost: int = levels[want[0]].upgrade_cost
		assert_int(sim.lighthouse_upgrade_cost()).is_equal(cost)
		var gold := sim.state.gold
		assert_int(sim.upgrade_lighthouse()).is_equal(R.OK)
		assert_int(sim.state.lighthouse_level).is_equal(want[0])
		assert_int(sim.beam_count()).is_equal(want[1])
		assert_int(sim.state.gold).is_equal(gold - cost)
		var ev := sim.drain_events()
		assert_array(ev.map(func(e: SimEvent) -> int: return e.type)).is_equal(
			[T.LIGHTHOUSE_UPGRADED, T.GOLD_CHANGED])
		assert_dict(ev[0].data).is_equal({"level": want[0], "beams": want[1], "cost": cost})
		assert_int(ev[0].id).is_equal(0)
		assert_str(ev[1].data["reason"]).is_equal("lighthouse")
		assert_int(ev[1].data["delta"]).is_equal(-cost)
		assert_array(sim.state.command_log.back()).is_equal([sim.state.tick, "upgrade_lighthouse"])
	assert_int(sim.lighthouse_upgrade_cost()).is_equal(0)
	_refused(sim, sim.upgrade_lighthouse, R.MAX_LEVEL)


## `cmd` returns `want` and changes nothing (gold, oil, level, log, events).
func _refused(sim: Simulation, cmd: Callable, want: int) -> void:
	sim.drain_events()
	var s := sim.state
	var before := [s.gold, s.oil, s.lighthouse_level, s.flare_ticks_left,
		s.flare_cooldown_ticks, s.command_log.size()]
	assert_int(cmd.call()).is_equal(want)
	assert_array([s.gold, s.oil, s.lighthouse_level, s.flare_ticks_left,
		s.flare_cooldown_ticks, s.command_log.size()]).is_equal(before)
	assert_array(sim.drain_events()).is_empty()


func test_upgrade_refusals_in_order() -> void:
	var sim := _day_sim()
	var cost := sim.lighthouse_upgrade_cost()
	sim.state.gold = cost - 1
	assert_int(sim.can_upgrade_lighthouse()).is_equal(R.NOT_ENOUGH_GOLD)
	_refused(sim, sim.upgrade_lighthouse, R.NOT_ENOUGH_GOLD)
	sim.call_wave()
	assert_int(sim.state.phase).is_equal(P.WAVE)
	sim.state.gold = 100000
	_refused(sim, sim.upgrade_lighthouse, R.NOT_BUILD_PHASE)
	sim.state.outcome = SimState.Outcome.LOST
	_refused(sim, sim.upgrade_lighthouse, R.OUTCOME_REACHED)


func test_new_beams_light_from_the_next_night_tick() -> void:
	var sim := _day_sim()
	sim.config.economy.beam.turn_t = 0.0
	var behind := build(sim, RIFLE, Vector2i(13, 1))  # v = (-1, 1): in no beam of 1, 2 or 4
	var up := build(sim, RIFLE, Vector2i(14, 1))  # v = (0, 1): the 4-beam set's (0, 1)
	assert_int(sim.upgrade_lighthouse()).is_equal(R.OK)
	assert_int(sim.upgrade_lighthouse()).is_equal(R.OK)
	run(sim, 1)
	assert_bool(up.lit).is_false()  # by day
	sim.call_wave()
	run(sim, 1)
	assert_bool(up.lit).is_true()
	assert_bool(behind.lit).is_false()


# --- modifiers (config-driven) ---------------------------------------------------------------

## Ticks between the first two SHOTs of a rifle at TOWER with a cultist parked at path 7.
func _rifle_gap(sim: Simulation) -> int:
	build(sim, RIFLE)
	put(sim, "cultist", 7.0)
	sim.drain_events()
	var ticks := shot_ticks(run(sim, 200))
	assert_int(ticks.size()).is_greater_equal(2)
	return ticks[1] - ticks[0]


func test_lit_mundane_cooldown_uses_fire_interval_mult() -> void:
	var fi: float = tconfig().towers[RIFLE].levels[0].fire_interval
	var unlit := _rifle_gap(_still(false))
	assert_int(unlit).is_equal(maxi(1, SimTime.ticks(fi)))
	for mult: float in [-1.0, 0.5]:
		var sim := _still()
		if mult > 0.0:
			sim.config.economy.beam.mundane_fire_interval_mult = mult
		var m := sim.config.economy.beam.mundane_fire_interval_mult
		var gap := _rifle_gap(sim)
		assert_int(gap).override_failure_message("mult %f" % m).is_equal(
			maxi(1, SimTime.ticks(fi * m)))
		assert_int(gap).is_less(unlit)


## Rifle shots at Fraying until `n`; returns [misses, combat rng moved].
func _fraying_shots(sim: Simulation, n: int) -> Array:
	var th := sim.config.sanity.thresholds
	var v := (float(th["fraying"].min_sanity) + float(th["whispers"].min_sanity)) * 0.5
	_set_sanity(sim, v)
	assert_int(sim.state.sanity_state).is_equal(S.FRAYING)
	assert_float(sim.threshold().miss_chance).is_greater(0.0)
	build(sim, RIFLE)
	put(sim, "cultist", 7.0)
	sim.drain_events()
	var before := sim.rng(SimRng.Stream.COMBAT).state
	var shots: Array[SimEvent] = []
	var guard := 0
	while shots.size() < n and guard < 100000:
		_set_sanity(sim, v)
		sim.step()
		shots.append_array(of_type(sim.drain_events(), T.SHOT))
		guard += 1
	var misses := shots.filter(func(s: SimEvent) -> bool: return s.data["miss"]).size()
	return [misses, sim.rng(SimRng.Stream.COMBAT).state != before]


func test_lit_mundane_with_ignore_miss_never_misses_and_draws_nothing() -> void:
	assert_bool(_still().config.economy.beam.mundane_ignore_miss).is_true()
	assert_array(_fraying_shots(_still(), 100)).is_equal([0, false])
	var unlit := _fraying_shots(_still(false), 100)
	assert_int(unlit[0]).is_greater(0)
	assert_bool(unlit[1]).is_true()
	var off := _still()
	off.config.economy.beam.mundane_ignore_miss = false
	var r := _fraying_shots(off, 100)
	assert_int(r[0]).is_greater(0)  # lit but the key is off: the miss roll is back


func test_lit_necronomicon_deals_power_mult_damage() -> void:
	for arm: Array in [[false, -1.0], [true, -1.0], [true, 0.5]]:
		var sim := _still(arm[0])
		if arm[1] > 0.0:
			sim.config.economy.beam.occult_power_mult = arm[1]
		var pm := sim.config.economy.beam.occult_power_mult if arm[0] else 1.0
		var dmg: float = sim.config.towers[NECRO].levels[0].damage
		build(sim, NECRO)
		var e := put(sim, "cultist", 8.0)
		sim.step()
		assert_float(e.hp).override_failure_message("%s" % [arm]).is_equal_approx(
			HUGE_HP - dmg * pm, 0.0001)


func test_a_lit_rifle_keeps_its_damage() -> void:
	var sim := _still()
	var dmg: float = sim.config.towers[RIFLE].levels[0].damage
	build(sim, RIFLE)
	var e := put(sim, "cultist", 7.0)
	sim.step()
	assert_float(e.hp).is_equal_approx(HUGE_HP - dmg, 0.0001)


func test_lit_elder_sign_aura_at_power_mult_strength() -> void:
	for arm: Array in [[false, -1.0], [true, -1.0], [true, 0.5]]:
		var sim := _still(arm[0])
		if arm[1] > 0.0:
			sim.config.economy.beam.occult_power_mult = arm[1]
		var pm := sim.config.economy.beam.occult_power_mult if arm[0] else 1.0
		var fx: Dictionary = sim.config.towers[SIGN].levels[0].effects
		var slow: float = fx["slow"]
		var m: float = fx["damage_taken_multiplier"]
		build(sim, SIGN)
		var e := put(sim, "cultist", 7.0)
		sim.step()
		assert_array(_mods(e)).override_failure_message("%s" % [arm]).is_equal(
			[snappedf(1.0 - slow * pm, 0.0001), snappedf(1.0 + (m - 1.0) * pm, 0.0001)])


func test_lit_enemies_real_and_fake_skip_the_madness_buff() -> void:
	for arm: Array in [[true, true], [false, true], [true, false]]:  # [lit, cancel key]
		var sim := _still(arm[0])
		sim.config.economy.beam.cancel_madness_buff = arm[1]
		_set_sanity(sim, 0.0)
		assert_int(sim.state.sanity_state).is_equal(S.MADNESS)
		var mad := sim.config.sanity.madness
		var real := put(sim, "cultist", 1.0)
		var fake := put(sim, "cultist", 1.0, HUGE_HP, true)
		sim.step()
		var blocked: bool = arm[0] and arm[1]
		var want := [1.0, 1.0] if blocked else [snappedf(mad.enemy_speed_multiplier, 0.0001),
			snappedf(mad.enemy_damage_taken_multiplier, 0.0001)]
		for e: SimEnemy in [real, fake]:
			assert_bool(e.lit).is_equal(arm[0])
			assert_array(_mods(e)).override_failure_message("%s fake=%s" % [arm, e.is_fake]) \
				.is_equal(want)


# --- lamp oil --------------------------------------------------------------------------------

func test_oil_starts_at_oil_start_and_is_zero_without_the_block() -> void:
	var sim := tsim()
	assert_int(sim.state.oil).is_equal(sim.config.economy.oil.start)
	var cfg := _econ(func(lh: Dictionary) -> void:
		lh["oil"]["start"] = 5)
	assert_int(Simulation.new(cfg, SEED).state.oil).is_equal(5)
	var none := Simulation.new(_econ(func(lh: Dictionary) -> void:
		lh.erase("oil")
		lh.erase("flare")), SEED)
	assert_int(none.state.oil).is_equal(0)
	assert_int(none.can_buy_oil()).is_equal(R.NO_FLARE)
	assert_int(none.can_fire_flare()).is_equal(R.NO_FLARE)


func test_buy_oil_pays_the_price_one_unit_per_call() -> void:
	var sim := _day_sim()
	var oil := sim.config.economy.oil
	var gold := sim.state.gold
	var start := sim.state.oil
	assert_int(sim.buy_oil()).is_equal(R.OK)
	assert_int(sim.state.oil).is_equal(start + 1)
	assert_int(sim.state.gold).is_equal(gold - oil.price)
	var ev := sim.drain_events()
	assert_array(ev.map(func(e: SimEvent) -> int: return e.type)).is_equal(
		[T.OIL_CHANGED, T.GOLD_CHANGED])
	assert_dict(ev[0].data).is_equal({"delta": 1, "oil": start + 1, "reason": "buy"})
	assert_dict(ev[1].data).is_equal({"delta": -oil.price, "gold": gold - oil.price,
		"reason": "oil"})
	assert_array(sim.state.command_log.back()).is_equal([sim.state.tick, "buy_oil"])


func test_buy_oil_stops_at_the_cap() -> void:
	var sim := _day_sim()
	var cap := sim.config.economy.oil.cap
	while sim.state.oil < cap:
		assert_int(sim.buy_oil()).is_equal(R.OK)
	assert_int(sim.state.oil).is_equal(cap)
	_refused(sim, sim.buy_oil, R.OIL_FULL)
	sim.state.gold = 0  # the cap comes before the money
	assert_int(sim.can_buy_oil()).is_equal(R.OIL_FULL)


func test_buy_oil_refusals_in_order() -> void:
	var sim := _day_sim()
	sim.state.gold = sim.config.economy.oil.price - 1
	_refused(sim, sim.buy_oil, R.NOT_ENOUGH_GOLD)
	sim.state.gold = 100000
	sim.call_wave()
	_refused(sim, sim.buy_oil, R.NOT_BUILD_PHASE)
	sim.state.outcome = SimState.Outcome.LOST
	_refused(sim, sim.buy_oil, R.OUTCOME_REACHED)


func test_oil_carries_over_the_night_and_the_dawn() -> void:
	var sim := _day_sim(3)
	var cap := sim.config.economy.oil.cap
	while sim.buy_oil() == R.OK:
		pass
	assert_int(sim.state.oil).is_equal(cap)
	sim.call_wave()
	_until(sim, P.BUILD)
	run(sim, 3)
	assert_int(sim.state.oil).is_equal(cap)  # unused: nothing burns at dawn
	sim.call_wave()
	run(sim, 1)
	assert_int(sim.fire_flare()).is_equal(R.OK)
	_until(sim, P.BUILD)
	assert_int(sim.state.oil).is_equal(cap - sim.config.economy.flare.cost_oil)


# --- the flare -------------------------------------------------------------------------------

func test_fire_flare_pays_oil_and_emits_in_order() -> void:
	var sim := _still()
	var f := sim.config.economy.flare
	var start := f.cost_oil + 3
	sim.state.oil = start
	assert_int(sim.fire_flare()).is_equal(R.OK)
	assert_int(sim.state.oil).is_equal(start - f.cost_oil)
	assert_int(sim.state.flare_ticks_left).is_equal(SimTime.ticks(f.seconds))
	assert_int(sim.state.flare_cooldown_ticks).is_equal(SimTime.ticks(f.cooldown_seconds))
	var ev := sim.drain_events()
	assert_array(ev.map(func(e: SimEvent) -> int: return e.type)).is_equal(
		[T.FLARE_FIRED, T.OIL_CHANGED])
	assert_dict(ev[0].data).is_equal({"ticks": SimTime.ticks(f.seconds),
		"cooldown": SimTime.ticks(f.cooldown_seconds)})
	assert_dict(ev[1].data).is_equal({"delta": -f.cost_oil, "oil": start - f.cost_oil,
		"reason": "flare"})
	assert_array(sim.state.command_log.back()).is_equal([sim.state.tick, "fire_flare"])


func test_fire_flare_refusals_in_order() -> void:
	var sim := _day_sim()
	var f := sim.config.economy.flare
	sim.state.oil = f.cost_oil
	_refused(sim, sim.fire_flare, R.NOT_NIGHT)  # BUILD
	sim.call_wave()
	assert_int(sim.can_fire_flare()).is_equal(R.OK)  # WAVE
	sim.state.oil = f.cost_oil - 1
	_refused(sim, sim.fire_flare, R.NO_OIL)
	sim.state.oil = f.cost_oil
	sim.state.flare_cooldown_ticks = 1
	_refused(sim, sim.fire_flare, R.ON_COOLDOWN)
	sim.state.phase = P.DONE
	_refused(sim, sim.fire_flare, R.NOT_NIGHT)
	sim.state.phase = P.WAVE
	sim.state.outcome = SimState.Outcome.LOST
	_refused(sim, sim.fire_flare, R.OUTCOME_REACHED)


func test_cooldown_runs_from_the_activation_also_by_day() -> void:
	var sim := _still()
	var cd := SimTime.ticks(sim.config.economy.flare.cooldown_seconds)
	sim.state.oil = 2 * sim.config.economy.flare.cost_oil  # two flares
	assert_int(sim.fire_flare()).is_equal(R.OK)
	run(sim, cd - 1)
	assert_int(sim.can_fire_flare()).is_equal(R.ON_COOLDOWN)
	run(sim, 1)
	assert_int(sim.can_fire_flare()).is_equal(R.OK)
	# By day: the cooldown still counts down.
	assert_int(sim.fire_flare()).is_equal(R.OK)
	sim.state.phase = P.BUILD
	run(sim, 10)
	assert_int(sim.state.flare_cooldown_ticks).is_equal(cd - 10)


## LT-57: the flare burns for exactly its seconds and no longer holds the beams.
func test_flare_burns_for_exactly_its_seconds_and_beams_keep_turning() -> void:
	var sim := tsim()
	sim.state.oil = sim.config.economy.flare.cost_oil
	var n := SimTime.ticks(sim.config.economy.flare.seconds)
	run(sim, 3)
	assert_int(sim.fire_flare()).is_equal(R.OK)
	for i in n:
		var dx := sim.state.beam_dx
		var dy := sim.state.beam_dy
		assert_int(sim.state.flare_ticks_left).is_equal(n - i)
		sim.step()
		assert_bool(sim.state.beam_dx != dx or sim.state.beam_dy != dy) \
			.override_failure_message("tick %d: beam held" % i).is_true()
	assert_int(sim.state.flare_ticks_left).is_equal(0)


## LT-57: while the flare burns everything within flare_radius() of the lighthouse is lit
## (the beam aimed away from the map lights nothing here).
func test_flare_lights_the_circle_while_it_burns() -> void:
	var sim := _still(false)
	var n := SimTime.ticks(sim.config.economy.flare.seconds)
	var r := sim.flare_radius()
	assert_float(r).is_equal(6.0)
	# (11, 1): v = (-3, 1), inside the circle; (7, 1): v = (-7, 1), outside.
	var near := build(sim, RIFLE, Vector2i(11, 1))
	var far := build(sim, RIFLE, Vector2i(7, 1))
	run(sim, 2)
	assert_bool(near.lit).is_false()
	sim.state.oil = 2 * sim.config.economy.flare.cost_oil
	assert_int(sim.fire_flare()).is_equal(R.OK)
	var t0 := sim.state.tick
	var ev := run(sim, n + 2)
	assert_array(_lit_events(ev, near.id)).is_equal([[t0 + 1, true], [t0 + n + 1, false]])
	assert_array(_lit_events(ev, far.id)).is_empty()
	# Direct geometry: the edge at r, inclusive.
	sim.state.flare_cooldown_ticks = 0
	assert_bool(_lit(sim, -r, 0.0)).is_false()
	sim.fire_flare()
	assert_bool(_lit(sim, -r, 0.0)).is_true()
	assert_bool(_lit(sim, -r * (1.0 + EPS), 0.0)).is_false()


func test_flare_slows_lit_enemies_only_while_it_burns() -> void:
	var sim := _still()
	var f := sim.config.economy.flare
	var n := SimTime.ticks(f.seconds)
	var real := put(sim, "cultist", 3.0)
	var fake := put(sim, "cultist", 3.0, HUGE_HP, true)
	run(sim, 2)
	assert_bool(real.lit).is_true()
	assert_float(real.speed_mult).is_equal(1.0)  # the passive beam never slows
	sim.state.oil = f.cost_oil
	sim.fire_flare()
	var slowed := {"real": 0, "fake": 0}
	for i in n + 10:
		sim.step()
		for p: Array in [["real", real], ["fake", fake]]:
			var e: SimEnemy = p[1]
			if is_equal_approx(e.speed_mult, f.enemy_speed_mult):
				slowed[p[0]] += 1
			else:
				assert_float(e.speed_mult).is_equal(1.0)
	assert_dict(slowed).is_equal({"real": n, "fake": n})
	# Unlit enemies are not slowed by a flare.
	var away := _still(false)
	var e3 := put(away, "cultist", 3.0)
	away.state.oil = f.cost_oil
	away.fire_flare()
	run(away, 1)
	assert_bool(e3.lit).is_false()
	assert_float(e3.speed_mult).is_equal(1.0)
