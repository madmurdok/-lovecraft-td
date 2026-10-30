class_name HallucinationSystem
extends RefCounted
## Fake enemy scheduler (design note LT-12 §2), owned by Simulation and ticked in slot 7
## right after the spawner. Holds no reference to the sim (no reference cycle).
##
## Timer, in ticks: interval = ticks(thresholds[state].fake_spawn_interval) for the current
## sanity state (0 = none). `_elapsed` restarts at 0 on the first tick of each wave (wave
## tick 0) and advances by 1 on every later WAVE tick whose interval is > 0; when it
## reaches the interval one fake spawns and it restarts at 0. A threshold change mid-wave
## keeps the counter and compares it with the new interval; Lucid (interval 0) pauses it.
## So the first fake of a wave comes on wave tick `interval`, then every `interval`.
##
## The fake mimics one of the spawner's candidates (the current wave's unfired spawn
## events), picked on rng(SANITY); a pack enemy expands into a full pack, also on SANITY
## (Simulation.spawn_enemy). Enemies with a `boss` trait are never mimicked (owner
## decision Q6; no such trait exists yet, the check is the hook for the boss content task).

const BOSS_TRAIT := "boss"

var _elapsed := 0
var _wave_seen := 0  ## wave_index the counter belongs to


func tick(sim: Simulation, spawner: SimSpawner) -> void:
	var s := sim.state
	if s.phase != SimState.Phase.WAVE:
		return
	if s.wave_index != _wave_seen:
		_wave_seen = s.wave_index
		_elapsed = 0
		return
	var interval := SimTime.ticks(sim.threshold().fake_spawn_interval)
	if interval <= 0:
		return
	_elapsed += 1
	if _elapsed < interval:
		return
	var candidates := _mimicable(sim, spawner.fake_candidates(sim))
	if candidates.is_empty():
		return
	_elapsed = 0
	var pick := candidates[sim.rng(SimRng.Stream.SANITY).randi_range(0, candidates.size() - 1)]
	spawn_fake(sim, pick)


## Spawns a fake `def_id` (a full pack for a pack enemy) like a real spawn; returns the
## first new id, 0 if nothing spawned. Public for LT-13's madness effects.
func spawn_fake(sim: Simulation, def_id: String) -> int:
	return sim.spawn_enemy(def_id, true)


func _mimicable(sim: Simulation, candidates: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id in candidates:
		var def: EnemyDef = sim.config.enemies.get(id)
		if def != null and not def.traits.has(BOSS_TRAIT):
			out.append(id)
	return out
