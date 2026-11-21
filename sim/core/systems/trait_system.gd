class_name TraitSystem
extends RefCounted
## LT-106 T4: the two per-tick enemy trait passes of slot 2 (near_tower, on_tick). Every
## live enemy in id order (state.enemies is append order), its traits in catalog order
## (EnemyDef.hook_traits). A pass returns at once when no enemy def of the config carries
## its hook bit (`_any`), so with today's traits each costs one int test per tick. The
## event hooks (on_spawn, on_leak, on_damaged, on_death) are dispatched by Spawn and Combat.

var _state: SimState
var _host: TraitHost
## OR of def.hooks over config.enemies.
var _any := 0


func _init(ctx: SimContext, host: TraitHost) -> void:
	_state = ctx.state
	_host = host
	for id: String in ctx.config.enemies:
		_any |= (ctx.config.enemies[id] as EnemyDef).hooks


## Slot 2, after the light writer, before apply_auras (LT-105 §3 writer slot).
func near_tower() -> void:
	if (_any & EnemyTrait.NEAR_TOWER) == 0:
		return
	for e in _state.enemies:
		var d := e.def
		if not e.is_live() or (d.hooks & EnemyTrait.NEAR_TOWER) == 0:
			continue
		for i in d.hook_traits.size():
			var t := d.hook_traits[i]
			if t.hooks() & EnemyTrait.NEAR_TOWER:
				t.near_tower(_host, e, d.hook_params[i])


## Slot 2, right after the status timers.
func tick_traits() -> void:
	if (_any & EnemyTrait.ON_TICK) == 0:
		return
	for e in _state.enemies:
		var d := e.def
		if not e.is_live() or (d.hooks & EnemyTrait.ON_TICK) == 0:
			continue
		for i in d.hook_traits.size():
			var t := d.hook_traits[i]
			if t.hooks() & EnemyTrait.ON_TICK:
				t.on_tick(_host, e, d.hook_params[i])
