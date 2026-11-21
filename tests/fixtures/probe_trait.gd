class_name ProbeTrait
extends EnemyTrait
## LT-106 test-only enemy trait (tests/trait_hooks_test.gd): the "one file" of a new trait.
## The test injects it into TraitCatalog where a line in TraitCatalog._rows() would put it
## (after the shipped rows) and removes it afterwards. It records every hook call in `calls`
## (an Array the test owns); unlike a shipped trait it keeps state, one instance per test.

var _id: String
var _mask: int
var calls: Array
## near_tower: the tower whose channel it reads, then composes `write_power` into through
## host.modify_tower (1.0 = no write).
var tower: SimTower = null
var write_power := 1.0
## on_death: the state whose relic tokens it counts (the token drop comes first).
var state: SimState = null


func _init(p_id: String, mask: int, p_calls: Array) -> void:
	_id = p_id
	_mask = mask
	calls = p_calls


func id() -> String:
	return _id


func params() -> PackedStringArray:
	return PackedStringArray(["tag"])


func hooks() -> int:
	return _mask


func on_spawn(_host: TraitHost, e: SimEnemy, p: Dictionary, from_event: bool) -> void:
	calls.append([_id, "on_spawn", e.id, p, from_event])


func on_tick(_host: TraitHost, e: SimEnemy, p: Dictionary) -> void:
	calls.append([_id, "on_tick", e.id, p, int(e.status.get("pull_immune_ticks", -1))])


func on_damaged(_host: TraitHost, e: SimEnemy, p: Dictionary, taken: float,
		source: String) -> void:
	calls.append([_id, "on_damaged", e.id, p, taken, source])


func on_death(_host: TraitHost, e: SimEnemy, p: Dictionary, source: String) -> void:
	calls.append([_id, "on_death", e.id, p, source,
		state.relic_tokens.size() if state != null else -1])


func on_leak(_host: TraitHost, e: SimEnemy, p: Dictionary) -> void:
	calls.append([_id, "on_leak", e.id, p])


func near_tower(host: TraitHost, e: SimEnemy, p: Dictionary) -> void:
	calls.append([_id, "near_tower", e.id, p, e.damage_taken_mult,
		tower.power_mult if tower != null else -1.0])
	if tower != null and write_power != 1.0:
		host.modify_tower(tower, write_power, 1.0, 0.0)
