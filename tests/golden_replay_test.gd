class_name GoldenReplayTest
extends GdUnitTestSuite
## LT-73 (B0 of docs/design/LT-65-architecture-review.md, guard G5 "behaviour unchanged"):
## replays the golden runs (tests/golden_runs.gd: every bot strategy x seed, SimNoTreeLoop and
## the LT-34 frame-driven run) on the frozen config in tests/fixtures/golden_data/ and compares
## each run's event-stream and final-state digests with tests/fixtures/golden_digests.json.
##
## A failure means the sim's behaviour changed. During a refactor that is a bug: fix the code.
## Only an approved behaviour change may regenerate the pinned file, with scripts/golden-regen.sh
## (never by hand), committed together with the change; see tests/fixtures/README.md.

const REGEN_HINT := "\nIf this behaviour change is approved, regenerate with scripts/golden-regen.sh" \
	+ " and commit tests/fixtures/golden_digests.json with it (tests/fixtures/README.md);" \
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
	# JSON reads every number as a float: compare through the same JSON round trip.
	var got_json: Dictionary = JSON.parse_string(JSON.stringify(got))
	var diff := GoldenRuns.diff(pinned["runs"], got_json)
	assert_str(diff).override_failure_message("golden replay differs from %s:\n%s%s" % [
		GoldenRuns.PINNED, diff, REGEN_HINT]).is_empty()


func test_the_golden_config_is_the_frozen_copy_not_data() -> void:
	assert_str(GoldenRuns.GOLDEN_DATA).is_not_equal("res://data")
	assert_object(GoldenRuns.golden_config()).is_not_null()
