class_name FrameStats
extends RefCounted
## LT-38 P1: ring buffer of wall-clock frame intervals (ms) with median and p90, for the
## debug-only `--frame-stats` overlay. No scene or sim access; the math is static so tests
## can call it directly.

## ~2 s at 60 fps: long enough to smooth single hitches, short enough to follow a change
## (e.g. sanity dropping into madness) within a couple of seconds.
const CAPACITY := 120

var _buf := PackedFloat64Array()
var _next := 0  ## ring write index once the buffer is full


## Adds one frame interval in ms; the oldest sample is overwritten when full.
func push(ms: float) -> void:
	if _buf.size() < CAPACITY:
		_buf.append(ms)
	else:
		_buf[_next] = ms
		_next = (_next + 1) % CAPACITY


func count() -> int:
	return _buf.size()


func median_ms() -> float:
	return percentile(_buf, 0.5)


func p90_ms() -> float:
	return percentile(_buf, 0.9)


## "frame 16.4 ms median / 21.0 p90", or "frame - (no samples)" while empty.
func text() -> String:
	if _buf.is_empty():
		return "frame - (no samples)"
	return "frame %.1f ms median / %.1f p90" % [median_ms(), p90_ms()]


## Nearest-rank percentile (q in 0..1) of `values`; 0.0 when empty. The median of an even
## count is the mean of the two middle values.
static func percentile(values: PackedFloat64Array, q: float) -> float:
	var n := values.size()
	if n == 0:
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	if is_equal_approx(q, 0.5):
		return sorted[n / 2] if n % 2 == 1 else (sorted[n / 2 - 1] + sorted[n / 2]) * 0.5
	return sorted[clampi(ceili(q * n) - 1, 0, n - 1)]
