class_name SimSpawner
extends RefCounted
## Spawning slot of Simulation.step() (step 7). LT-4 ships ScriptedSpawner;
## LT-5 replaces it with the wave director.


## Called once by Simulation.set_spawner(); may initialise wave state and emit events.
func attach(_sim: Simulation) -> void:
	pass


## Called once per tick, after movement and leaks; spawns through sim.spawn_enemy().
func tick(_sim: Simulation) -> void:
	pass


## Called once per tick after dead/leaked enemies are removed (step 8) and before the
## outcome check (step 9), so a wave's completion is settled before the win is decided.
func end_tick(_sim: Simulation) -> void:
	pass


## True when nothing more will ever spawn (part of the win rule, §5).
func is_exhausted() -> bool:
	return true
