class_name FrameStats
extends RefCounted
## LT-38 P1: ring buffer of wall-clock frame intervals (ms) with median and p90, for the
## debug-only `--frame-stats` overlay. No scene or sim access; the math is static so tests
## can call it directly.

## ~2 s at 60 fps: long enough to smooth single hitches, short enough to follow a change
## (e.g. sanity dropping into madness) within a couple of seconds.
const CAPACITY := 120
## LT-62 P2: a frame interval above this is a spike, logged with context by Game.advance.
const SPIKE_MS := 100.0
## LT-62 P2: worst_ms() looks this far back (wall-clock ms, summed newest first).
const WORST_WINDOW_MS := 1000.0

var _buf := PackedFloat64Array()
var _next := 0  ## ring write index once the buffer is full


## Adds one frame interval in ms; the oldest sample is overwritten when full.
func push(ms: float) -> void:
	if _buf.size() < CAPACITY:
		_buf.append(ms)
	else:
		_buf[_next] = ms
		_next = (_next + 1) % CAPACITY


## LT-62 P2: true when one frame interval of `ms` counts as a spike (> SPIKE_MS).
static func is_spike(ms: float) -> bool:
	return ms > SPIKE_MS


## LT-62 P2: the longest interval among the newest samples that together span at most
## WORST_WINDOW_MS (the newest one always counts, even when it alone is longer); 0.0 while
## empty.
func worst_ms() -> float:
	var n := _buf.size()
	var newest := _newest()
	var worst := 0.0
	var span := 0.0
	for k in n:
		var ms: float = _buf[(newest - k + n) % n]
		if k > 0 and span + ms > WORST_WINDOW_MS:
			break
		span += ms
		worst = maxf(worst, ms)
	return worst


## Index of the newest sample in _buf (the buffer must not be empty).
func _newest() -> int:
	return _buf.size() - 1 if _buf.size() < CAPACITY else (_next - 1 + CAPACITY) % CAPACITY


func count() -> int:
	return _buf.size()


func median_ms() -> float:
	return percentile(_buf, 0.5)


func p90_ms() -> float:
	return percentile(_buf, 0.9)


## "frame 16.4 ms median / 21.0 p90 / worst 48.2" (worst over the last second, LT-62 P2),
## or "frame - (no samples)" while empty.
func text() -> String:
	if _buf.is_empty():
		return "frame - (no samples)"
	return "frame %.1f ms median / %.1f p90 / worst %.1f" % [median_ms(), p90_ms(), worst_ms()]


## LT-62 P2: one spike log line, "LT-62 spike 412.3 ms | k1=v1 k2=v2 ...", the context keys
## in the dictionary's insertion order.
static func spike_line(ms: float, context: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: Variant in context:
		parts.append("%s=%s" % [k, context[k]])
	return "LT-62 spike %.1f ms | %s" % [ms, " ".join(parts)]


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
