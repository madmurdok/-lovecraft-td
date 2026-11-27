class_name SimRng
extends RefCounted
## One RandomNumberGenerator per stream, all seeded from the run seed (design note LT-4 §4).
## Streams keep features independent: a new roll on COMBAT does not reshuffle SPAWN.
## Sim code draws only through randf / randi_range (LT-102); the numeric contract a port
## must reproduce (PCG32 per stream, binary32 randf) is in the sim/core/sim_time.gd header.

## New streams are appended so existing ones keep their seeds. LOOT rolls real relic drops,
## GHOST_LOOT the tokens of fakes (LT-27 §1.2), so hallucinations never shift real loot.
## CRIT rolls tower crits (LT-29 §1.1), so crit towers never shift the COMBAT miss sequence.
## LIFT rolls the night-gaunt's drop cell (LT-117), so a lift never reshuffles SPAWN.
## ROUTE resolves a group's "any" route at the build start (LT-109), so a route draw never
## reshuffles SPAWN.
enum Stream {SPAWN, COMBAT, SANITY, MADNESS, LOOT, GHOST_LOOT, CRIT, LIFT, ROUTE}

const STREAM_SEED_STRIDE := 16

var _streams: Array[RandomNumberGenerator] = []


func _init(run_seed: int) -> void:
	for i in Stream.size():
		var g := RandomNumberGenerator.new()
		g.seed = run_seed * STREAM_SEED_STRIDE + i
		_streams.append(g)


## Inspection only (seed, state); draws go through randf / randi_range.
func stream(s: Stream) -> RandomNumberGenerator:
	return _streams[s]


## One draw on stream `s`: RandomNumberGenerator.randf().
func randf(s: Stream) -> float:
	return _streams[s].randf()


## RandomNumberGenerator.randi_range(from, to) on stream `s`; from == to draws nothing.
func randi_range(s: Stream, from: int, to: int) -> int:
	return _streams[s].randi_range(from, to)
