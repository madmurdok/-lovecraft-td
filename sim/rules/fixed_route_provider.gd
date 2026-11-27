class_name FixedRouteProvider
extends RouteProvider
## LT-109 §2.2: routes as authored in the map (a v1 map: the one S ... L walk). Holds any
## number of ids; ignores extra_cost (an authored route never detours).

var _routes: Dictionary[String, Array]
var _ids: PackedStringArray


## `routes`: id -> cells (start ... L); `route_ids`: pinned order, [0] the default.
func _init(routes: Dictionary[String, Array], route_ids: PackedStringArray) -> void:
	_routes = routes
	_ids = route_ids


func ids() -> PackedStringArray:
	return _ids


## A copy of the authored cells of `id`; empty for an unknown id.
func cells(id: String, _extra_cost: PackedInt64Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _routes.has(id):
		out.assign(_routes[id])
	return out
