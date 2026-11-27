class_name MapRng
extends RefCounted
## LT-130 (LT-18 §9): the map generator's own generator, one per attempt. Not a SimRng stream:
## the map seed must never shift combat rolls. Draws are only randi_range (PCG32 bounded
## integer, platform-independent); no randf, no global RNG, no hash() of Variants.

## Attempt `a` of map seed `s` is seeded `s * ATTEMPT_STRIDE + a` (LT-18 §9).
const ATTEMPT_STRIDE := 1000

var _g: RandomNumberGenerator


func _init(attempt_seed_value: int) -> void:
	_g = RandomNumberGenerator.new()
	_g.seed = attempt_seed_value


## The seed of attempt `attempt` (0-based) of `map_seed`.
static func attempt_seed(map_seed: int, attempt: int) -> int:
	return map_seed * ATTEMPT_STRIDE + attempt


## One draw in [from, to], both inclusive: RandomNumberGenerator.randi_range.
func randi_range(from: int, to: int) -> int:
	return _g.randi_range(from, to)


## An index into `n` candidates: no draw when there is at most one (LT-130 §3: a draw
## happens whenever a choice has 2+ candidates).
func pick(n: int) -> int:
	if n <= 1:
		return 0
	return _g.randi_range(0, n - 1)
