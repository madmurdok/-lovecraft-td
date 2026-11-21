class_name TowerLiftTrait
extends EnemyTrait
## Pending (LT-106 T7): schema only, no hook. Its tower-move rules get their own content task.


func id() -> String:
	return "tower_lift"


func params() -> PackedStringArray:
	return PackedStringArray(["from_wave", "drop_cells", "disable_seconds"])


func pending() -> bool:
	return true
