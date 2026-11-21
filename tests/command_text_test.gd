class_name CommandTextTest
extends GdUnitTestSuite
## LT-75 (LT-65 B3, guard G9): one table of refusal texts, CommandText.TEXT, and the lighthouse
## panel's capitalised subset. Pure static calls; no nodes.

const R := SimCommand.CommandResult
## A refusal-text map keyed by a CommandResult name with a string value, or a table named REASONS.
const MAP_ENTRY := "(CommandResult|\\bR)\\.[A-Z_]+\\s*:\\s*\""
const REASONS_DECL := "(const|var)\\s+REASONS\\b"


func test_every_command_result_has_a_text() -> void:
	assert_int(R.size()).is_greater(10)
	for name: String in R.keys():
		var text: Variant = CommandText.TEXT.get(R[name])
		assert_bool(text is String and not (text as String).is_empty()) \
			.override_failure_message("CommandText.TEXT has no text for %s" % name).is_true()


func test_text_has_no_key_outside_the_enum() -> void:
	for k: Variant in CommandText.TEXT.keys():
		assert_bool(R.values().has(k)).override_failure_message(
			"TEXT key %s is not a CommandResult" % str(k)).is_true()


func test_reason_returns_the_table_text() -> void:
	for k: Variant in CommandText.TEXT.keys():
		assert_str(CommandText.reason(k)).is_equal(CommandText.TEXT[k])


func test_reason_of_an_unmapped_result_is_generic() -> void:
	# 9999 is outside the enum, so it is unmapped whatever the table holds.
	assert_str(CommandText.reason(9999 as R)).is_equal(CommandText.GENERIC)


func test_the_four_panel_results_read_lowercase_in_the_table() -> void:
	assert_str(CommandText.reason(R.MAX_LEVEL)).is_equal("max level")
	assert_str(CommandText.reason(R.NOT_BUILD_PHASE)).is_equal("only by day")
	assert_str(CommandText.reason(R.NOT_ENOUGH_GOLD)).is_equal("not enough money")
	assert_str(CommandText.reason(R.OIL_FULL)).is_equal("tank full")


func test_panel_results_are_exactly_the_four_named() -> void:
	var got: Array = CommandText.PANEL_RESULTS.duplicate()
	got.sort()
	var want: Array = [R.MAX_LEVEL, R.NOT_BUILD_PHASE, R.NOT_ENOUGH_GOLD, R.OIL_FULL]
	want.sort()
	assert_array(got).is_equal(want)


func test_panel_reason_capitalises_the_four() -> void:
	assert_str(CommandText.panel_reason(R.MAX_LEVEL)).is_equal("Max level")
	assert_str(CommandText.panel_reason(R.NOT_BUILD_PHASE)).is_equal("Only by day")
	assert_str(CommandText.panel_reason(R.NOT_ENOUGH_GOLD)).is_equal("Not enough money")
	assert_str(CommandText.panel_reason(R.OIL_FULL)).is_equal("Tank full")


func test_panel_reason_is_empty_outside_panel_results() -> void:
	for name: String in R.keys():
		if CommandText.PANEL_RESULTS.has(R[name]):
			continue
		assert_str(CommandText.panel_reason(R[name])).override_failure_message(
			"%s should show no panel reason" % name).is_empty()


# --- G9: one reasons table -------------------------------------------------------------------

func test_g9_no_other_refusal_text_table() -> void:
	var map_re := RegEx.create_from_string(MAP_ENTRY)
	var decl_re := RegEx.create_from_string(REASONS_DECL)
	var files := _gd_files("res://ui")
	files.append_array(_gd_files("res://scenes"))
	files.append_array(_gd_files("res://sim"))
	assert_bool(files.has("res://ui/text/command_text.gd")).is_true()
	assert_bool(files.has("res://ui/lighthouse_panel.gd")).is_true()
	assert_bool(files.has("res://ui/text/tower_text.gd")).is_true()
	for f: String in files:
		if f == "res://ui/text/command_text.gd":
			continue
		var src := FileAccess.get_file_as_string(f)
		assert_object(decl_re.search(src)).override_failure_message(
			"%s declares REASONS; the table lives in ui/text/command_text.gd" % f).is_null()
		var m := map_re.search(src)
		assert_object(m).override_failure_message(
			"%s maps a CommandResult to text (%s); use CommandText" % [
				f, m.get_string() if m != null else ""]).is_null()


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


# --- LT-107: per-command overrides (BY_COMMAND) ----------------------------------------------

func test_reason_with_any_existing_command_equals_the_shared_text() -> void:
	assert_int(Simulation.COMMANDS.size()).is_equal(12)
	for cmd: String in Simulation.COMMANDS:
		for name: String in R.keys():
			assert_str(CommandText.reason(R[name], cmd)).override_failure_message(
				"%s %s" % [cmd, name]).is_equal(CommandText.reason(R[name]))
	# An unknown command name falls back too.
	assert_str(CommandText.reason(R.NOT_NIGHT, "no_such_command")).is_equal(
		CommandText.reason(R.NOT_NIGHT))


## A planted override table (the const BY_COMMAND is empty): the override wins for its own
## key and mapped result only; other keys, unmapped results and the empty key read TEXT.
func test_a_planted_override_wins_only_for_its_command_and_result() -> void:
	var planted := {"deploy": {R.NOT_NIGHT: "only at night"},
		"": {R.NOT_NIGHT: "empty key must not apply"}}
	assert_str(CommandText._reason_in(R.NOT_NIGHT, "deploy", planted)).is_equal("only at night")
	assert_str(CommandText.TEXT[R.NOT_NIGHT]).is_not_equal("only at night")
	assert_str(CommandText._reason_in(R.NOT_NIGHT, "", planted)).is_equal(
		CommandText.TEXT[R.NOT_NIGHT])
	assert_str(CommandText._reason_in(R.NOT_NIGHT, "hire", planted)).is_equal(
		CommandText.TEXT[R.NOT_NIGHT])
	assert_str(CommandText._reason_in(R.OIL_FULL, "deploy", planted)).is_equal(
		CommandText.TEXT[R.OIL_FULL])
	assert_str(CommandText._reason_in(9999 as R, "deploy", planted)).is_equal(
		CommandText.GENERIC)
	for name: String in R.keys():
		assert_str(CommandText._reason_in(R[name], "", CommandText.BY_COMMAND)).is_equal(
			CommandText.reason(R[name]))
