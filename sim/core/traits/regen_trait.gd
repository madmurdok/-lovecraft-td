class_name RegenTrait
extends EnemyTrait
## Pending (LT-106 T7): schema only, no hook. Wiring it (on_tick, writes e.hp of its own
## enemy) changes the golden runs (shoggoth), so it gets its own task and golden regen.


func id() -> String:
	return "regen"


func params() -> PackedStringArray:
	return PackedStringArray(["hp_percent_per_second"])


func pending() -> bool:
	return true
