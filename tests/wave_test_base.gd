class_name WaveTestBase
extends TowerTestBase
## Shared fixtures for the LT-5 suites: the TowerTestBase map with waves.json replaced by
## the groups a test needs and a WaveDirector attached.

const R := Simulation.CommandResult
const NO_EDITS := {}

var director: WaveDirector


## Config with waves.json replaced: `waves` = Array of Array of group dicts
## ({"type", "count", "interval", "delay"}).
func wconfig(waves: Array, build_seconds := 1, hp := -1) -> GameConfig:
	var r := load_edited(func(dir: String) -> void:
		var packed: Array = []
		for groups: Array in waves:
			packed.append({"groups": groups})
		write_file(dir, "waves.json", JSON.stringify(
			{"build_phase_seconds": build_seconds, "waves": packed}))
		edit(dir, MAP, func(root: Dictionary) -> void:
			root["width"] = ROWS[0].length()
			root["height"] = ROWS.size()
			root["rows"] = ROWS)
		if hp >= 0:
			edit(dir, ECON, func(root: Dictionary) -> void: root["lighthouse"]["hp"] = hp))
	assert_bool(r.ok).override_failure_message("config rejected:\n%s" % "\n".join(r.errors)) \
		.is_true()
	return r.config


## Simulation with a WaveDirector over `waves` (also kept in `director`).
func wsim(waves: Array, build_seconds := 1, hp := -1, run_seed := SEED) -> Simulation:
	var sim := Simulation.new(wconfig(waves, build_seconds, hp), run_seed)
	director = WaveDirector.new(sim.config.waves)
	sim.set_spawner(director)
	return sim


func group(enemy: String, count: int, interval := 0.0, delay := 0.0) -> Dictionary:
	return {"type": enemy, "count": count, "interval": interval, "delay": delay}


## Kills every live real enemy (between steps); the next step removes them.
func kill_real(sim: Simulation) -> void:
	for e in sim.state.enemies:
		if not e.is_fake:
			sim.apply_damage(e.id, 1.0e9, "test")


func ticks_of(events: Array[SimEvent]) -> Array[int]:
	var out: Array[int] = []
	for e in events:
		out.append(e.tick)
	return out


func bonus_for(sim: Simulation, wave: int) -> int:
	return sim.config.economy.wave_bonus_base + sim.config.economy.wave_bonus_per_wave * wave
