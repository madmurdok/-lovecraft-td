class_name GoldenTraceTest
extends GdUnitTestSuite
## LT-102 (docs/design/LT-102-portability-core.md §5, §7 B10): the golden trace is
## engine-neutral JSON, and a value it cannot carry exactly fails the run instead of being
## written. The trace is compared with its pinned files by golden_replay_test (B9); this suite
## plays only the short SimNoTreeLoop run.

## Godot's text form of a vector, which a port could not read back as numbers.
const VECTOR_TEXT := "^\\(.*, .*\\)$"


## Every String inside `v` that looks like Godot vector text or a "!" marker, with its path.
func _godot_text(v: Variant, path: String, out: Array[String]) -> void:
	match typeof(v):
		TYPE_STRING:
			if RegEx.create_from_string(VECTOR_TEXT).search(v) != null or v.begins_with("!"):
				out.append("%s = %s" % [path, v])
		TYPE_DICTIONARY:
			for k: Variant in v:
				_godot_text(v[k], "%s.%s" % [path, k], out)
		TYPE_ARRAY:
			for i in v.size():
				_godot_text(v[i], "%s[%d]" % [path, i], out)


## The binary64 bit pattern of `f` as an int64 (adjacent doubles of one sign differ by 1).
static func _bits(f: float) -> int:
	var b := PackedFloat64Array([f]).to_byte_array()
	return b.decode_s64(0)


## True when the parsed JSON `got` holds `want` (a neutral value): numbers compared as binary64
## (JSON reads every number as a float) to within one ulp, the rest by type and value.
## One ulp, not exact: Godot's own JSON reader is not correctly rounded (LT-102/S8 probe: it
## reads "7.8466668128967285", the shortest round-trip text of that binary64, one ulp off).
## The exact text is pinned by golden_replay_test (B9, sha256 and full-text files).
func _same(want: Variant, got: Variant) -> bool:
	var tw := typeof(want)
	if tw == TYPE_INT or tw == TYPE_FLOAT:
		return typeof(got) == TYPE_FLOAT and absi(_bits(float(want)) - _bits(got)) <= 1
	if tw != typeof(got):
		return false
	if tw == TYPE_DICTIONARY:
		if want.size() != got.size():
			return false
		for k: Variant in want:
			if not got.has(k) or not _same(want[k], got[k]):
				return false
		return true
	if tw == TYPE_ARRAY:
		if want.size() != got.size():
			return false
		for i in want.size():
			if not _same(want[i], got[i]):
				return false
		return true
	return want == got


## Floats inside `v`.
func _floats(v: Variant, out: Array[float]) -> void:
	match typeof(v):
		TYPE_FLOAT:
			out.append(v)
		TYPE_DICTIONARY:
			for k: Variant in v:
				_floats(v[k], out)
		TYPE_ARRAY:
			for x: Variant in v:
				_floats(x, out)


# --- B10 ------------------------------------------------------------------------------------

func test_trace_lines_are_engine_neutral() -> void:
	var run_name := "no_tree_loop/%d" % GoldenRuns.NO_TREE_SEED
	assert_bool(run_name in GoldenRuns.TRACE_FULL_RUNS).is_true()
	var rec := GoldenRuns.Recorder.new(run_name)
	var events: Array = []  # the neutral value of every event line, in drain order
	var sink := func(s: Simulation, evs: Array[SimEvent]) -> void:
		for ev in evs:
			var errs: Array[String] = []
			events.append(GoldenRuns.neutral({"data": ev.data, "id": ev.id, "tick": ev.tick,
				"type": SimEvent.Type.keys()[ev.type]}, errs))
		rec.sink(s, evs)
	var sim := SimNoTreeLoop.play(GoldenRuns.golden_config(), GoldenRuns.NO_TREE_SEED, sink)
	var trace: Dictionary = rec.result()["trace"]
	assert_array(trace["errors"]).is_empty()
	var lines := (trace["text"] as String).split("\n", false)
	assert_int(lines.size()).is_equal(int(trace["lines"]))
	assert_int(lines.size()).is_equal(events.size() + 2)
	assert_int(events.size()).is_greater(100)

	var parsed: Array = []
	for i in lines.size():
		var v: Variant = JSON.parse_string(lines[i])
		assert_bool(v is Dictionary).override_failure_message(
			"line %d is not a JSON object: %s" % [i + 1, lines[i]]).is_true()
		parsed.append(v)
	var godot_text: Array[String] = []
	for i in parsed.size():
		_godot_text(parsed[i], "line %d" % (i + 1), godot_text)
	assert_array(godot_text).override_failure_message(
		"Godot text in the trace:\n" + "\n".join(godot_text)).is_empty()

	var header: Dictionary = parsed[0]
	assert_str(header.get("format")).is_equal(GoldenRuns.TRACE_FORMAT)
	assert_str(header.get("run")).is_equal(run_name)
	assert_float(header.get("version")).is_equal(float(GoldenRuns.TRACE_VERSION))

	# Every event line parses back to exactly its values: floats at full binary64 precision.
	var bad: Array[String] = []
	var lossy := 0  # floats a default-precision writer would write with fewer digits
	for i in events.size():
		if not _same(events[i], parsed[i + 1]):
			bad.append("line %d: %s" % [i + 2, lines[i + 1]])
		var fs: Array[float] = []
		_floats(events[i], fs)
		for f in fs:
			if JSON.stringify(f) != JSON.stringify(f, "", false, true):
				lossy += 1
	assert_array(bad).override_failure_message(
		"trace lines that do not parse back to their values:\n" + "\n".join(bad)).is_empty()
	assert_int(lossy).override_failure_message(
		"no float needs full precision: the round-trip check would see nothing").is_greater(0)

	var final: Variant = parsed[-1].get("final")
	assert_bool(final is Dictionary).is_true()
	var rng: Variant = final.get("rng")
	assert_bool(rng is Array).is_true()
	assert_int(rng.size()).is_equal(SimRng.Stream.size())
	for s: SimRng.Stream in SimRng.Stream.values():
		assert_int(typeof(rng[s])).is_equal(TYPE_STRING)
		assert_str(rng[s]).is_equal(str(sim.rng(s).state))
	assert_float(final.get("tick")).is_equal(float(sim.state.tick))


func test_neutral_writes_vectors_and_names_as_plain_json() -> void:
	var errs: Array[String] = []
	var v := Vector2(0.1, 2.0)
	assert_array(GoldenRuns.neutral(v, errs)).is_equal([float(v.x), 2.0])
	assert_array(GoldenRuns.neutral(Vector2i(3, -4), errs)).is_equal([3, -4])
	assert_array(GoldenRuns.neutral(PackedVector2Array([Vector2(1, 2)]), errs)) \
		.is_equal([[1.0, 2.0]])
	var name: Variant = GoldenRuns.neutral(&"rifleman", errs)
	assert_int(typeof(name)).is_equal(TYPE_STRING)
	assert_str(GoldenRuns.trace_json({"to": v}, errs)).is_equal(
		"{\"to\":[0.10000000149011612,2.0]}")
	assert_array(errs).is_empty()


# --- F2: an untraceable value fails the run ------------------------------------------------

func test_neutral_reports_what_json_cannot_carry_and_writes_no_marker() -> void:
	var errs: Array[String] = []
	var out: Variant = GoldenRuns.neutral({&"k": 1, "a": 2.5, "b": [1, NAN]}, errs)
	# Only the bad key is left out; the rest of the dictionary stays in the trace.
	assert_dict(out).is_equal({"a": 2.5, "b": [1, null]})
	assert_int(errs.size()).override_failure_message("\n".join(errs)).is_equal(2)
	assert_bool(errs[0].contains("non-String key")).is_true()
	assert_bool(errs[1].begins_with(".b[1]: non-finite float")).is_true()
	for bad: Variant in [INF, -INF, GoldenRuns.MAX_EXACT_INT + 1, -GoldenRuns.MAX_EXACT_INT - 1,
			Color(1, 0, 0)]:
		var e: Array[String] = []
		assert_object(GoldenRuns.neutral(bad, e)).is_null()
		assert_int(e.size()).override_failure_message("accepted %s" % [bad]).is_equal(1)
	var ok: Array[String] = []
	assert_int(GoldenRuns.neutral(GoldenRuns.MAX_EXACT_INT, ok)).is_equal(GoldenRuns.MAX_EXACT_INT)
	assert_array(ok).is_empty()
	var line := GoldenRuns.trace_json({&"k": 1}, errs)
	assert_bool(line.contains("!")).override_failure_message(line).is_false()


func test_the_recorder_names_the_line_of_an_untraceable_value() -> void:
	var sim := Simulation.new(GoldenRuns.golden_config(), 1)
	var rec := GoldenRuns.Recorder.new("probe/1")
	var ev := SimEvent.new(SimEvent.Type.SPAWNED, 0, 1, {&"def": "cultist"})
	var evs: Array[SimEvent] = [ev]
	rec.sink(sim, evs)
	var errors: Array = rec.result()["trace"]["errors"]
	assert_int(errors.size()).is_equal(1)
	assert_bool(String(errors[0]).begins_with("probe/1 event 1.data: non-String key")) \
		.override_failure_message(str(errors)).is_true()


func test_the_replay_fails_on_an_untraceable_value() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		GoldenRuns.TRACE_DIR.path_join(GoldenRuns.TRACE_MANIFEST)))
	var traces := {}
	for n: String in manifest["runs"]:
		var w: Dictionary = manifest["runs"][n]
		var text: Variant = null
		if w["file"] != null:
			text = FileAccess.get_file_as_string(GoldenRuns.TRACE_DIR.path_join(w["file"]))
		traces[n] = {"lines": int(w["lines"]), "sha256": w["sha256"], "text": text,
			"errors": []}
	var replay: GoldenReplayTest = auto_free(GoldenReplayTest.new())
	# The pinned trace itself is clean: the probe below fails only on its error.
	assert_str(replay._trace_diff(traces)).is_empty()
	var run: String = GoldenRuns.TRACE_FULL_RUNS[0]
	traces[run]["errors"] = ["%s event 3.data: non-String key &\"k\" (StringName)" % run]
	assert_str(replay._trace_diff(traces)).is_equal(
		"untraceable value: %s event 3.data: non-String key &\"k\" (StringName)" % run)
