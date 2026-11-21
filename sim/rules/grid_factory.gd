class_name GridFactory
extends RefCounted
## LT-108 F1: the one place that builds a GridTopology from map data's "grid" kind (guard G15).
## Registering a topology is one MAKERS line; the config error text and G10 follow the table.
## HexGrid ships but is not registered yet (owner, LT-108 Q6): "grid": "hex" stays an error.

## kind -> topology class. A static var, not a const: a global class name is not a constant
## expression, and sim/ may not preload (sim_boundary_test). Never written after load.
static var MAKERS := {"square": SquareGrid}


## The registered kinds, sorted (config error text).
static func kinds() -> PackedStringArray:
	var out := PackedStringArray(MAKERS.keys())
	out.sort()
	return out


## A `width` x `height` topology of `kind`, or null for an unregistered kind.
static func make(kind: String, width: int, height: int) -> GridTopology:
	if not MAKERS.has(kind):
		return null
	return MAKERS[kind].new(width, height)
