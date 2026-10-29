class_name SimClock
extends RefCounted
## Turns real frame time into a number of sim steps (design note LT-4 §1.2).
## Pure: the Node that calls advance() and Simulation.step() comes with LT-7.

const MAX_STEPS_PER_FRAME := 8  ## catch-up cap; excess time is dropped
## Absorbs float error in the accumulator (1/60 s * 30 is not exactly 0.5 tick).
const EPSILON := 1e-6
const MAX_SPEED := 2

## 0 = pause, 1 = normal, 2 = fast; any other value is clamped into 0..2.
var speed := 1:
	set(value):
		speed = clampi(value, 0, MAX_SPEED)
var _accumulator := 0.0  ## in ticks, kept in [0, 1) between frames


## Adds one frame of real time and returns how many steps to run now (0..8).
## A negative delta counts as 0.
func advance(real_delta: float) -> int:
	if speed == 0 or real_delta <= 0.0:
		return 0
	_accumulator += real_delta * speed * SimTime.TICK_RATE
	var steps := floori(_accumulator + EPSILON)
	_accumulator = maxf(0.0, _accumulator - steps)
	if steps > MAX_STEPS_PER_FRAME:
		steps = MAX_STEPS_PER_FRAME
	return steps


## Fraction of the next tick already elapsed, in [0, 1), for render interpolation.
func alpha() -> float:
	return clampf(_accumulator, 0.0, 1.0 - EPSILON)
