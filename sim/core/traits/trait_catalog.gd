class_name TraitCatalog
extends RefCounted
## LT-106 T1: the enemy trait registry. A new trait = its file + one line in _rows().

## id -> the one shared instance (traits hold no state), catalog order, built on first use.
static var _by_id: Dictionary = {}


## THE CATALOG: one line per trait, and this order is the catalog order (hook dispatch order
## within one enemy, EnemyDef.hook_traits; the order of ids()). Pack is row 0, so no other
## on_spawn can draw RNG before its count roll. A list built here, not a const: a global
## class name is not a constant expression, and sim/ uses no preload (sim boundary).
static func _rows() -> Array[EnemyTrait]:
	return [
		PackTrait.new(),
		TowerHarassTrait.new(),
		TowerLiftTrait.new(),
		RegenTrait.new(),
		BossTrait.new(),
	]


static func _all() -> Dictionary:
	if _by_id.is_empty():
		for t in _rows():
			_by_id[t.id()] = t
	return _by_id


static func has(id: String) -> bool:
	return _all().has(id)


## The trait with this id, or null.
static func get_trait(id: String) -> EnemyTrait:
	return _all().get(id)


## Every trait id, catalog order.
static func ids() -> Array:
	return _all().keys()


## Every trait instance, catalog order.
static func all() -> Array:
	return _all().values()


## Ids of the traits the sim does not apply yet (LT-97), catalog order.
static func pending_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _all():
		if (_by_id[id] as EnemyTrait).pending():
			out.append(id)
	return out
