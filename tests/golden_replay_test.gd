class_name GoldenReplayTest
extends GdUnitTestSuite
## LT-73 (B0 of docs/design/LT-65-architecture-review.md, guard G5 "behaviour unchanged"):
## replays the golden runs (tests/golden_runs.gd: every bot strategy x seed, SimNoTreeLoop and
## the LT-34 frame-driven run) on the frozen config in tests/fixtures/golden_data/ and compares
## each run's event-stream and final-state digests with tests/fixtures/golden_digests.json,
## and (LT-102) each run's engine-neutral trace with tests/fixtures/golden_trace/ (line count
## and sha256 of every run, the full text of GoldenRuns.TRACE_FULL_RUNS).
##
## A failure means the sim's behaviour changed. During a refactor that is a bug: fix the code.
## Only an approved behaviour change may regenerate the pinned file, with scripts/golden-regen.sh
## (never by hand), committed together with the change; see tests/fixtures/README.md.

const REGEN_HINT := "\nIf this behaviour change is approved, regenerate with scripts/golden-regen.sh" \
	+ " and commit tests/fixtures/golden_digests.json and tests/fixtures/golden_trace/ with it" \
	+ " (tests/fixtures/README.md);" \
	+ " never edit the file by hand. In a refactor, fix the code instead."


func test_golden_runs_match_the_pinned_digests() -> void:
	var text := FileAccess.get_file_as_string(GoldenRuns.PINNED)
	assert_str(text).override_failure_message("no pinned digests at %s.%s" % [GoldenRuns.PINNED,
		REGEN_HINT]).is_not_empty()
	var pinned: Variant = JSON.parse_string(text)
	assert_bool(pinned is Dictionary).override_failure_message("unreadable %s.%s" % [
		GoldenRuns.PINNED, REGEN_HINT]).is_true()
	assert_int(int(pinned.get("bucket_ticks", 0))).is_equal(GoldenRuns.BUCKET_TICKS)
	var got: Dictionary = await GoldenRuns.compute_all(self)
	var traces := {}
	for n: String in got:
		traces[n] = got[n]["trace"]
		got[n].erase("trace")
	# JSON reads every number as a float: compare through the same JSON round trip.
	var got_json: Dictionary = JSON.parse_string(JSON.stringify(got))
	var diff := GoldenRuns.diff(pinned["runs"], got_json)
	assert_str(diff).override_failure_message("golden replay differs from %s:\n%s%s" % [
		GoldenRuns.PINNED, diff, REGEN_HINT]).is_empty()
	var trace_diff := _trace_diff(traces)
	assert_str(trace_diff).override_failure_message("golden trace differs from %s:\n%s%s" % [
		GoldenRuns.TRACE_DIR, trace_diff, REGEN_HINT]).is_empty()


## "" when every computed trace matches the manifest (lines, sha256) and every full-text run
## its .jsonl file; else one line per difference, a text difference naming its first line.
func _trace_diff(traces: Dictionary) -> String:
	var path := GoldenRuns.TRACE_DIR.path_join(GoldenRuns.TRACE_MANIFEST)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Dictionary or not manifest.get("runs") is Dictionary:
		return "no readable trace manifest at %s" % path
	if manifest.get("format") != GoldenRuns.TRACE_FORMAT \
			or int(manifest.get("version", 0)) != GoldenRuns.TRACE_VERSION:
		return "manifest format %s v%s, expected %s v%d" % [manifest.get("format"),
			manifest.get("version"), GoldenRuns.TRACE_FORMAT, GoldenRuns.TRACE_VERSION]
	var runs: Dictionary = manifest["runs"]
	var lines: Array[String] = []
	for n: String in runs:
		if not traces.has(n):
			lines.append("%s: not computed any more" % n)
	for n: String in traces:
		if not runs.has(n):
			lines.append("%s: not in the manifest" % n)
			continue
		var w: Dictionary = runs[n]
		var g: Dictionary = traces[n]
		if int(w.get("lines", -1)) != int(g["lines"]) or w.get("sha256") != g["sha256"]:
			lines.append("%s: %s lines sha256 %s -> %d lines sha256 %s" % [n, w.get("lines"),
				w.get("sha256"), g["lines"], g["sha256"]])
		var full: bool = n in GoldenRuns.TRACE_FULL_RUNS
		if full != (w.get("file") != null):
			lines.append("%s: manifest file %s, full text expected: %s" % [n, w.get("file"), full])
		if full:
			var file := GoldenRuns.TRACE_DIR.path_join(GoldenRuns.trace_file_name(n))
			var text := _first_text_difference(FileAccess.get_file_as_string(file), g["text"])
			if text != "":
				lines.append("%s: %s %s" % [n, file, text])
	return "\n".join(lines)


## "" when equal, else "line N: <want> -> <got>" for the first differing line (1-based).
static func _first_text_difference(want: String, got: String) -> String:
	if want == got:
		return ""
	var w := want.split("\n")
	var g := got.split("\n")
	for i in maxi(w.size(), g.size()):
		var wl := w[i] if i < w.size() else "<end of file>"
		var gl := g[i] if i < g.size() else "<end of trace>"
		if wl != gl:
			return "line %d:\n  pinned:   %s\n  computed: %s" % [i + 1, wl, gl]
	return "differs (line ends)"


func test_the_golden_config_is_the_frozen_copy_not_data() -> void:
	assert_str(GoldenRuns.GOLDEN_DATA).is_not_equal("res://data")
	assert_object(GoldenRuns.golden_config()).is_not_null()
