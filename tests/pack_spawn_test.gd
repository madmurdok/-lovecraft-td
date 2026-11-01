class_name PackSpawnTest
extends WaveTestBase
## LT-63: pack members enter one by one, pack.spacing_s apart, instead of stacking in one
## cell. Spacing, pack sizes and tick numbers come from the config and SimTime.

const T := SimEvent.Type


func _spacing(cfg: GameConfig) -> int:
	return SimTime.ticks(cfg.enemies["deep_one"].traits["pack"]["spacing_s"])


## Members of the pack whose first member has id `first`, in id order.
func _members(sim: Simulation, first: int) -> Array[SimEnemy]:
	var out: Array[SimEnemy] = []
	for e in sim.state.enemies:
		if e.pack_of == first:
			out.append(e)
	return out


func _spawn_ticks(members: Array[SimEnemy]) -> Array[int]:
	var out: Array[int] = []
	for e in members:
		out.append(e.spawn_tick)
	return out


## Spawn ticks a pack of `n` entered at `start` must have.
func _expected_ticks(start: int, n: int, spacing: int) -> Array[int]:
	var out: Array[int] = []
	for k in n:
		out.append(start + k * spacing)
	return out


# --- behaviour 1: one by one, no shared tick -------------------------------------------

func test_first_member_enters_at_once_and_member_k_k_spacings_later() -> void:
	var cfg := real_config()
	var pack: Dictionary = cfg.enemies["deep_one"].traits["pack"]
	var spacing := _spacing(cfg)
	assert_int(spacing).is_greater(0)
	for run_seed: int in [1, 2, 3, 42]:
		var sim := Simulation.new(cfg, run_seed)
		var first := sim.spawn_enemy("deep_one")
		var start := sim.state.tick
		# Only the first member is in on the spawn call itself.
		assert_int(_members(sim, first).size()).is_equal(1)
		assert_int(sim.state.next_id).is_equal(first + 1)
		run(sim, pack_span_ticks(cfg, "deep_one") + 1)
		var members := _members(sim, first)
		assert_int(members.size()).is_between(int(pack["min"]), int(pack["max"]))
		var ticks := _spawn_ticks(members)
		assert_array(ticks).is_equal(_expected_ticks(start, members.size(), spacing))
		for i in range(1, ticks.size()):
			assert_int(ticks[i]).is_greater(ticks[i - 1])  # no two members share a tick
		assert_int(members[0].id).is_equal(first)


func test_real_members_enter_before_the_spawners_spawns_of_that_tick() -> void:
	var cfg := real_config()
	var spacing := _spacing(cfg)
	var sim := Simulation.new(cfg, 42)
	sim.set_spawner(ScriptedSpawner.new([[10, "deep_one"], [10 + spacing, "cultist"]]))
	var ev := run(sim, 10 + spacing)
	var spawned := of_type(ev, T.SPAWNED)
	var cultist: SimEnemy = null
	var member: SimEnemy = null
	for s in spawned:
		var e := sim.enemy_by_id(s.id)
		if e.def.id == "cultist":
			cultist = e
		elif e.spawn_tick == 10 + spacing:
			member = e
	assert_object(cultist).is_not_null()
	assert_object(member).is_not_null()
	assert_int(cultist.spawn_tick).is_equal(member.spawn_tick)
	assert_int(member.id).is_less(cultist.id)


# --- behaviour 2: rolled at spawn_enemy on SPAWN, replay identical ----------------------

func test_pack_size_is_rolled_at_the_spawn_call_on_the_spawn_stream() -> void:
	var cfg := real_config()
	var pack: Dictionary = cfg.enemies["deep_one"].traits["pack"]
	var sim := Simulation.new(cfg, 42)
	var ref := Simulation.new(cfg, 42)
	var firsts: Array[int] = []
	var want: Array[int] = []
	for i in 3:
		firsts.append(sim.spawn_enemy("deep_one"))
		want.append(ref.rng(SimRng.Stream.SPAWN).randi_range(int(pack["min"]), int(pack["max"])))
	run(sim, pack_span_ticks(cfg, "deep_one") + 1)
	var got: Array[int] = []
	for f in firsts:
		got.append(_members(sim, f).size())
	assert_array(got).is_equal(want)
	assert_int(sim.state.next_id - 1).is_equal(want[0] + want[1] + want[2])


func _replay_log(run_seed: int) -> Array[String]:
	var sim := Simulation.new(real_config(), run_seed)
	sim.set_spawner(ScriptedSpawner.new([[1, "deep_one"], [7, "cultist"], [12, "deep_one"],
		[40, "deep_one"]]))
	var out: Array[String] = []
	for t in 300:
		if t == 3:
			sim.spawn_enemy("deep_one", true)
		sim.step()
		out.append_array(strings_of(sim.drain_events()))
	out.append("next_id=%d" % sim.state.next_id)
	return out


func test_same_seed_replays_pack_events_identically() -> void:
	for run_seed: int in [5, 42]:
		var a := _replay_log(run_seed)
		var b := _replay_log(run_seed)
		assert_array(a).is_equal(b)
		assert_int(a.size()).is_greater(15)


# --- behaviour 3: fake packs staggered, dropped at dawn ---------------------------------

func test_fake_pack_is_staggered_too() -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 1)
	var spacing := _spacing(sim.config)
	run(sim, SimTime.ticks(1))
	var start := sim.state.tick
	var fid := sim.spawn_enemy("deep_one", true)
	assert_int(_members(sim, fid).size()).is_equal(1)
	run(sim, pack_span_ticks(sim.config, "deep_one") + 1)
	var members := _members(sim, fid)
	assert_int(members.size()).is_greater_equal(
		int(sim.config.enemies["deep_one"].traits["pack"]["min"]))
	assert_array(_spawn_ticks(members)).is_equal(_expected_ticks(start, members.size(), spacing))
	for m in members:
		assert_bool(m.is_fake).is_true()


## A fake pack queued when the wave clears: its members due on the dawn tick or later are
## dropped without a SPAWNED, a FAKE_DISSOLVED or a one-frame flash.
func _dawn_with_queued_fakes(spacing_s: float) -> void:
	var sim := wsim([[group("cultist", 1)], [group("cultist", 1)]], 10)
	sim.config.enemies["deep_one"].traits["pack"]["spacing_s"] = spacing_s
	run(sim, SimTime.ticks(10) + 1)  # wave starts on tick ticks(build), its cultist enters next
	assert_int(sim.state.enemies.size()).is_equal(1)
	kill_real(sim)
	var fid := sim.spawn_enemy("deep_one", true)
	sim.drain_events()
	var next_before := sim.state.next_id
	assert_int(next_before).is_equal(fid + 1)
	var dawn := run(sim, 1)  # the wave clears on this tick
	assert_int(of_type(dawn, T.WAVE_CLEARED).size()).is_equal(1)
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_array(of_type(dawn, T.SPAWNED)).is_empty()
	assert_array(ids_of(of_type(dawn, T.FAKE_DISSOLVED))).is_equal([fid])
	assert_int(sim.state.next_id).is_equal(next_before)
	var after := run(sim, pack_span_ticks(sim.config, "deep_one") + 3)
	assert_array(of_type(after, T.SPAWNED)).is_empty()
	assert_array(of_type(after, T.FAKE_DISSOLVED)).is_empty()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	assert_int(sim.state.enemies.size()).is_equal(0)
	assert_int(sim.state.next_id).is_equal(next_before)


func test_fake_member_due_on_the_dawn_tick_is_dropped_not_spawned_and_dissolved() -> void:
	# One tick of spacing: member 1 is due exactly on the dawn tick.
	_dawn_with_queued_fakes(SimTime.DT)


func test_fake_members_due_after_dawn_never_enter_the_build_phase() -> void:
	_dawn_with_queued_fakes(real_config().enemies["deep_one"].traits["pack"]["spacing_s"])


# --- behaviours 4 and 5: queued real members hold the wave and the win -------------------

func test_wave_is_not_cleared_while_a_real_member_is_queued() -> void:
	var sim := wsim([[group("deep_one", 1)], [group("deep_one", 1)]], 1)
	run(sim, SimTime.ticks(1))
	assert_bool(sim.has_queued_real_members()).is_true()
	var steps := 0
	while sim.has_queued_real_members() and steps < 100:
		kill_real(sim)  # everything entered so far is dead
		var ev := run(sim, 1)
		steps += 1
		assert_array(of_type(ev, T.WAVE_CLEARED)).is_empty()
		assert_int(sim.state.phase).is_equal(SimState.Phase.WAVE)
	assert_int(steps).is_greater_equal(
		int(sim.config.enemies["deep_one"].traits["pack"]["min"]) - 1)
	kill_real(sim)  # the last member
	assert_int(of_type(run(sim, 1), T.WAVE_CLEARED).size()).is_equal(1)


func test_run_is_not_won_while_a_real_member_is_queued() -> void:
	var cfg := real_config()
	var sim := Simulation.new(cfg, 42)
	sim.set_spawner(ScriptedSpawner.new([[1, "deep_one"]]))
	var steps := 0
	while sim.state.outcome == SimState.Outcome.NONE and steps < 200:
		kill_real(sim)
		sim.step()
		steps += 1
		if sim.has_queued_real_members():
			assert_int(sim.state.outcome).is_equal(SimState.Outcome.NONE)
	assert_int(sim.state.outcome).is_equal(SimState.Outcome.WON)
	assert_bool(sim.has_queued_real_members()).is_false()
	var pack: Dictionary = cfg.enemies["deep_one"].traits["pack"]
	assert_int(sim.state.next_id - 1).is_between(int(pack["min"]), int(pack["max"]))
