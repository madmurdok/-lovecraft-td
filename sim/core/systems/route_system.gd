class_name RouteSystem
extends RefCounted
## LT-109 §2.5-2.6: the one writer of state.route_now / state.route_next. Plans the next
## wave's routes at the build start (Simulation.on_build_start) and freezes that plan when the
## wave starts (Simulation.on_wave_start); SpawnSystem reads route_now. Cells come from the
## map's RouteProvider. No LT-109 path draws: an "any" route (LT-18) will be one draw per
## group on the ROUTE stream through _ctx.randi_range, in group order. Emits nothing.

var _ctx: SimContext
var _state: SimState
var _config: GameConfig
var _provider: RouteProvider


## Both plans start as the default plan (wave 0). Draws nothing, emits nothing (LT-80 §3).
func _init(ctx: SimContext) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_provider = _config.map.route_provider()
	var plan := _plan(0, PackedStringArray())
	_state.route_now = plan
	_state.route_next = plan


## Builds route_next for wave `wave` (1-based): per spawn group its "route", or the default
## route id when absent. A wave outside waves.json gets no group routes.
func plan_next(wave: int) -> void:
	var ids := _provider.ids()
	var groups := PackedStringArray()
	var waves := _config.waves
	if waves != null and wave >= 1 and wave <= waves.waves.size():
		for g in waves.waves[wave - 1].groups:
			groups.append(g.route if not g.route.is_empty() else ids[0])
	_state.route_next = _plan(wave, groups)


## The wave starts: its plan made by day becomes the one spawns read.
func freeze() -> void:
	_state.route_now = _state.route_next


func _plan(wave: int, group_routes: PackedStringArray) -> RoutePlan:
	var plan := RoutePlan.new()
	plan.wave = wave
	plan.group_routes = group_routes
	var no_cost := PackedInt64Array()
	for id in _provider.ids():
		plan.cells[id] = _provider.cells(id, no_cost)
	return plan
