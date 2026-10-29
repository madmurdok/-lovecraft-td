class_name SimTime
extends RefCounted
## Fixed-tick time base of the simulation (design note LT-4 §1.1, §3.2).
## These are engine resolutions, not balance values: changing them does not change balance.

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
