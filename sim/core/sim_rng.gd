class_name SimRng
extends RefCounted
## One RandomNumberGenerator per stream, all seeded from the run seed (design note LT-4 §4).
## Streams keep features independent: a new roll on COMBAT does not reshuffle SPAWN.

## New streams are appended so existing ones keep their seeds. LOOT rolls real relic drops,
## GHOST_LOOT the tokens of fakes (LT-27 §1.2), so hallucinations never shift real loot.
## CRIT rolls tower crits (LT-29 §1.1), so crit towers never shift the COMBAT miss sequence.
enum Stream {SPAWN, COMBAT, SANITY, MADNESS, LOOT, GHOST_LOOT, CRIT}

const STREAM_SEED_STRIDE := 16

var _streams: Array[RandomNumberGenerator] = []


func _init(run_seed: int) -> void:
	for i in Stream.size():
		var g := RandomNumberGenerator.new()
		g.seed = run_seed * STREAM_SEED_STRIDE + i
		_streams.append(g)


func stream(s: Stream) -> RandomNumberGenerator:
	return _streams[s]
