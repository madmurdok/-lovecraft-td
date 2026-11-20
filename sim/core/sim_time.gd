class_name SimTime
extends RefCounted
## Fixed-tick time base of the simulation (design note LT-4 §1.1, §3.2).
## These are engine resolutions, not balance values: changing them does not change balance.
##
## Numeric contract (LT-102; what a port must reproduce bit for bit):
##  - `float` is IEEE 754 binary64; every scalar computation in sim/ is binary64.
##  - `int` is int64. Path progress is integer distance units (UNITS_PER_CELL per cell), so
##    movement is exact; floats meet it only through roundi.
##  - Vector2 / PackedVector2Array components are binary32 (no double-precision build).
##    Storing rounds to nearest-even binary32; reading widens exactly. Positions (towers,
##    enemies via SimRoute, allies, blasts, tokens) are binary32 storage.
##  - Vector2 methods compute in binary32: SimRoute.position_at and AllySystem.ally_position
##    use Vector2.lerp (weight rounded to binary32). Rule and distance checks widen the
##    components first (`float(p.x) - c.x`) and compute in binary64 (LightRules,
##    GridTopology.distance, AllySystem._dist2, CombatSystem._line_*). The beam direction is
##    two binary64 scalars on purpose (SimState.beam_dx/dy).
##  - sqrt is the only non-trivial math (correctly rounded); no trig (guard G11).
##  - roundi rounds halves away from zero (2.5 -> 3, -2.5 -> -3); floori / floorf as usual.
##  - RNG (SimRng): one Godot PCG32 RandomNumberGenerator per stream, seed
##    run_seed * 16 + stream. RandomNumberGenerator.randf() is a binary32 value widened
##    to binary64; randi_range(a, a) returns a and draws nothing.
##  - Config numbers arrive as JSON binary64; int fields are exact up to 2^53 (ConfigReader).

const TICK_RATE := 30  ## ticks per second
const DT := 1.0 / TICK_RATE  ## seconds per tick
const UNITS_PER_CELL := 30000  ## sub-cell distance units; 1 cell/s = 1000 units/tick


## Duration in seconds -> whole ticks (1.2 s -> 36).
static func ticks(seconds: float) -> int:
	return roundi(seconds * TICK_RATE)


## Speed in cells per second -> distance units per tick (1.6 -> 1600).
static func units_per_tick(speed_cells_per_s: float) -> int:
	return roundi(speed_cells_per_s * UNITS_PER_CELL / TICK_RATE)


## Whole seconds in `n_ticks`, rounded down (749 ticks -> 24).
static func whole_seconds(n_ticks: int) -> int:
	@warning_ignore("integer_division")
	return n_ticks / TICK_RATE
