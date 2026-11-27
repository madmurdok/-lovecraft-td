class_name RoutePlan
extends RefCounted
## LT-109 §2.5: the routes of one wave, a value type like SimRoute: RouteSystem builds it and
## never changes it afterwards (state.route_now / route_next hold whole plans, replaced, never
## edited).

var wave := 0  ## the 1-based wave this plan is for; 0 = the default plan (no wave)
## Resolved route id per spawn group of that wave, group order (empty in the default plan).
var group_routes: PackedStringArray = []
## Route id -> cells (Array[Vector2i], start ... L) for every id of the map's route_ids.
## Lookup only, never iterated.
var cells: Dictionary[String, Array] = {}
