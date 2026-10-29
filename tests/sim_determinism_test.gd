class_name SimDeterminismTest
extends SimTestBase
## LT-4 §4: same config + seed -> same events and state; RNG streams; pack sizes
## (behaviours 9, 16).

const TICKS := 1300
const PACKS := 6
const SCRIPT := [
	[1, "cultist"], [5, "deep_one"], [20, "night_gaunt"], [40, "deep_one"], [60, "hybrid"],
	[90, "deep_one"], [120, "cultist"], [150, "deep_one"], [200, "shoggoth"], [240, "deep_one"],
	[300, "deep_one"],
]


## Runs the scripted mixed wave with periodic damage to the lowest-id live enemy and
## returns every event plus a snapshot of the final state, as strings.
func _scenario(run_seed: int) -> Array[String]:
	var sim := Simulation.new(real_config(), run_seed)
	sim.set_spawner(ScriptedSpawner.new(SCRIPT))
	var out: Array[String] = []
	for t in TICKS:
		sim.step()
		if t % 29 == 0 and not sim.state.enemies.is_empty():
			sim.apply_damage(sim.state.enemies[0].id, 25.0, "test")
		out.append_array(strings_of(sim.drain_events()))
	var s := sim.state
	out.append("tick=%d hp=%d outcome=%d next_id=%d" % [s.tick, s.lighthouse_hp, s.outcome,
		s.next_id])
	for e in s.enemies:
		out.append("enemy %d %s hp=%s d=%d pd=%d" % [e.id, e.def.id, e.hp, e.distance,
			e.prev_distance])
	return out


## Sizes of PACKS deep_one packs spawned back to back on a fresh sim.
func _pack_sizes(run_seed: int) -> Array[int]:
	var sim := Simulation.new(real_config(), run_seed)
	var sizes: Array[int] = []
	for i in PACKS:
		var before := sim.state.next_id
		sim.spawn_enemy("deep_one")
		sizes.append(sim.state.next_id - before)
	return sizes


func test_same_seed_gives_identical_events_and_state() -> void:
	for run_seed: int in [1, 42, 7777]:
		var a := _scenario(run_seed)
		var b := _scenario(run_seed)
		assert_int(a.size()).is_greater(20)
		assert_bool(a == b).override_failure_message(
			"seed %d diverged:\n%s\n---\n%s" % [run_seed, "\n".join(a), "\n".join(b)]).is_true()


func test_scenario_rolls_packs_and_leaks() -> void:
	# Sanity check that the scenario exercises the RNG (packs) and leaks.
	var a := _scenario(42)
	var spawned := a.filter(func(s: String) -> bool: return s.begins_with("SPAWNED"))
	assert_int(spawned.size()).is_greater(SCRIPT.size())
	assert_bool(a.any(func(s: String) -> bool: return s.begins_with("LEAKED"))).is_true()


func test_pack_size_always_within_min_max() -> void:
	var pack: Dictionary = real_config().enemies["deep_one"].traits["pack"]
	var lo := int(pack["min"])
	var hi := int(pack["max"])
	for run_seed in 40:
		for size in _pack_sizes(run_seed):
			assert_int(size).is_between(lo, hi)


func test_different_seeds_give_different_pack_sizes() -> void:
	var distinct := {}
	var values := {}
	for run_seed in 20:
		var sizes := _pack_sizes(run_seed)
		distinct[str(sizes)] = true
		for v in sizes:
			values[v] = true
	assert_int(distinct.size()).override_failure_message(
		"20 seeds gave only %d distinct pack sequences" % distinct.size()).is_greater(1)
	assert_int(values.size()).is_greater(1)


func test_same_seed_gives_same_pack_sizes() -> void:
	for run_seed in 10:
		assert_bool(_pack_sizes(run_seed) == _pack_sizes(run_seed)).is_true()


## §4: streams are independent, so rolls on COMBAT do not reshuffle SPAWN.
func test_rolls_on_another_stream_do_not_change_pack_sizes() -> void:
	for run_seed: int in [0, 5, 42]:
		var plain := _pack_sizes(run_seed)
		var sim := Simulation.new(real_config(), run_seed)
		for i in 50:
			sim.rng(SimRng.Stream.COMBAT).randi()
			sim.rng(SimRng.Stream.MADNESS).randf()
		var sizes: Array[int] = []
		for i in PACKS:
			var before := sim.state.next_id
			sim.spawn_enemy("deep_one")
			sizes.append(sim.state.next_id - before)
		assert_bool(sizes == plain).override_failure_message(
			"seed %d: %s vs %s" % [run_seed, sizes, plain]).is_true()


# --- purity (behaviour 16) --------------------------------------------------

var FORBIDDEN := RegEx.create_from_string("(^|[^.\\w])(Time\\.|OS\\.|randomize\\(|randi\\(|randf\\()")


func test_no_sim_script_extends_node_or_uses_scene_tree() -> void:
	var files := _scripts("res://sim")
	assert_int(files.size()).is_greater(10)
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		assert_bool(text.contains("extends Node")).override_failure_message(
			"%s extends Node" % f).is_false()
		assert_bool(text.contains("SceneTree") or text.contains("get_tree(")) \
			.override_failure_message("%s references the scene tree" % f).is_false()
		# Global clocks, OS and unseeded RNG break determinism; seeded rng.randi() is fine
		# (the dot before it), as is SimTime. (a word character before it).
		var m := FORBIDDEN.search(text)
		assert_object(m).override_failure_message(
			"%s uses %s" % [f, m.get_string(2) if m else ""]).is_null()


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(_scripts(dir.path_join(sub)))
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	return out
