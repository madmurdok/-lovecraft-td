class_name RouteProvider
extends RefCounted
## LT-109 §2.2: the route source of a map. A pure rule: no RNG, no state, the same input
## gives the same cells. MapDef.route_provider() picks the implementation (FixedRouteProvider
## on a v1 map; LT-18 adds a field-based one). Resolving an "any" route is a RouteSystem draw,
## never a provider's, so a provider swap never moves an RNG sequence.


## Route ids in pinned order; ids()[0] is the default route.
func ids() -> PackedStringArray:
	return PackedStringArray()


## start ... L of route `id` under the given extra entry cost per grid.index (sim units;
## empty = none; LT-18 passes barricade breach weights here). Empty for an unknown id or an
## unreachable start. Pure: no RNG, no state, same input -> same cells.
func cells(_id: String, _extra_cost: PackedInt64Array) -> Array[Vector2i]:
	return []
