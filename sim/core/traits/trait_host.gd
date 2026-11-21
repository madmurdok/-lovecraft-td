class_name TraitHost
extends RefCounted
## LT-106 T5: the only API an enemy trait sees. Built once by the sim facade after the
## systems; holds the shared context and method Callables (object id, no RefCounted cycle).
## A later trait adds the one method it needs here.
## LT-105 G12: modify_tower is the traits' one write into the tower modifier channel.

var _ctx: SimContext
var _queue_pack_member: Callable


func _init(ctx: SimContext, queue_pack_member: Callable) -> void:
	_ctx = ctx
	_queue_pack_member = queue_pack_member


func tick() -> int:
	return _ctx.state.tick


## A draw on `real_stream` for a real enemy, on SANITY for a fake (LT-12 §2): hallucinations
## never move a real stream.
func randi_range(e: SimEnemy, real_stream: SimRng.Stream, from: int, to: int) -> int:
	return _ctx.randi_range(SimRng.Stream.SANITY if e.is_fake else real_stream, from, to)


func randf(e: SimEnemy, real_stream: SimRng.Stream) -> float:
	return _ctx.randf(SimRng.Stream.SANITY if e.is_fake else real_stream)


## LT-63: one pack member enters at `due_tick` (SpawnSystem.queue_pack_member).
func queue_pack_member(due_tick: int, def: EnemyDef, is_fake: bool, pack_of: int) -> void:
	_queue_pack_member.call(due_tick, def, is_fake, pack_of)


## LT-105: composes into `t`'s modifier channel this tick (slot 2, near_tower only).
func modify_tower(t: SimTower, power: float, interval: float, miss: float, no_miss := false,
		off := false) -> void:
	t.add_modifiers(power, interval, miss, no_miss, off)
