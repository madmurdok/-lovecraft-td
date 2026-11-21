class_name EnemyTrait
extends RefCounted
## LT-106 T1: one enemy trait (schema and behaviour) in one file, listed once in
## TraitCatalog._rows(). Virtual methods, not consts (a subclass cannot redeclare a parent
## const). An instance holds no state: one shared instance serves every sim; per-enemy trait
## state lives in `e.status` under keys prefixed with the trait id.
##
## Hooks (T4) run at fixed call points, enemies in id order, then catalog order within one
## enemy, for real and fake enemies alike except on_leak (a fake never leaks). A hook sees
## the sim only through `host` (TraitHost); any RNG goes through host.randi_range / randf,
## which draw on SANITY for a fake. on_damaged / on_death must not damage their own enemy.

const ON_SPAWN := 1
const ON_TICK := 2
const ON_DAMAGED := 4
const ON_DEATH := 8
const ON_LEAK := 16
const NEAR_TOWER := 32


## The id used in enemies.json `traits`.
func id() -> String:
	return ""


## Parameter names (schema, not balance); empty for a flag trait.
func params() -> PackedStringArray:
	return PackedStringArray()


## OR of the hook bits this trait implements; 0 = no hook.
func hooks() -> int:
	return 0


## True while the sim does not apply this trait yet (LT-97: data parses, nothing happens).
func pending() -> bool:
	return false


## Parses `p` (keys already checked against params()); default: every name is a required
## number >= 0. Returns parameter name -> value.
func parse_params(r: ConfigReader, p: Dictionary, path: String) -> Dictionary:
	var out := {}
	for key: String in params():
		out[key] = r.req_number(p, key, path, 0.0)
	return out


## End of SpawnSystem._enter, after SPAWNED. `from_event` is false for a queued pack member.
func on_spawn(_host: TraitHost, _e: SimEnemy, _p: Dictionary, _from_event: bool) -> void:
	pass


## Slot 2, right after the status timers, live enemies only.
func on_tick(_host: TraitHost, _e: SimEnemy, _p: Dictionary) -> void:
	pass


## A hit the enemy survived (CombatSystem.apply_damage).
func on_damaged(_host: TraitHost, _e: SimEnemy, _p: Dictionary, _taken: float,
		_source: String) -> void:
	pass


## The killing hit, after the kill hook (token drop).
func on_death(_host: TraitHost, _e: SimEnemy, _p: Dictionary, _source: String) -> void:
	pass


## A real enemy leaked, after LEAKED.
func on_leak(_host: TraitHost, _e: SimEnemy, _p: Dictionary) -> void:
	pass


## Slot 2, after the light writer and before apply_auras; writes towers only through
## host.modify_tower.
func near_tower(_host: TraitHost, _e: SimEnemy, _p: Dictionary) -> void:
	pass
