class_name TowerHarassTrait
extends EnemyTrait
## Pending (LT-106 T7): schema only, no hook. Its semantics (does it stop, near which tower,
## radius) get their own content task, which wires near_tower + host.modify_tower.


func id() -> String:
	return "tower_harass"


func params() -> PackedStringArray:
	return PackedStringArray(["stop_seconds", "fire_rate_multiplier", "debuff_seconds"])


func pending() -> bool:
	return true
