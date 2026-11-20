class_name MainBootTest
extends GdUnitTestSuite
## LT-103 §2.4: Main._ready refuses to start on a bad effect text table, as on a bad config.
## LT-104 Q1: so does an invalid looks table or one that does not fit the config.
## The real _refuse_to_start quits a headless run with code 1, so the probe below overrides
## it to record the call instead; everything else in _ready runs as shipped.


class RefusingMain extends "res://scenes/main.gd":
	var refused_from := ""
	var refused_errors: Array[String] = []

	func _refuse_to_start(dir: String, errors: Array[String]) -> void:
		refused_from = dir
		refused_errors = errors


func after_test() -> void:
	EffectText.use(null)
	LookCatalog.use(null)


func test_a_bad_effect_text_table_refuses_to_start() -> void:
	var errs := EffectText.use({"modes": {}})
	assert_array(errs).is_not_empty()
	var m: RefusingMain = auto_free(RefusingMain.new())
	add_child(m)
	assert_str(m.refused_from).is_equal(EffectText.PATH)
	assert_array(m.refused_errors).is_equal(errs)
	assert_object(m.config).is_null()
	assert_object(m.game).is_null()
	remove_child(m)


func _assert_refused_with(path: String, errs: Array[String]) -> void:
	var m: RefusingMain = auto_free(RefusingMain.new())
	add_child(m)
	assert_str(m.refused_from).is_equal(path)
	assert_array(m.refused_errors).is_equal(errs)
	assert_object(m.config).is_null()
	assert_object(m.game).is_null()
	remove_child(m)


func test_an_invalid_looks_table_refuses_to_start() -> void:
	var errs := LookCatalog.use({"looks": {"tracer": {"base": "tracer"}}})
	assert_array(errs).is_not_empty()
	_assert_refused_with(LookCatalog.PATH, errs)


func test_a_looks_table_that_does_not_fit_the_config_refuses_to_start() -> void:
	assert_array(LookCatalog.use({"towers": {"ghost_tower": "tracer"}})).is_empty()
	var want: Array[String] = ["towers.ghost_tower: no such tower"]
	_assert_refused_with(LookCatalog.PATH, want)
