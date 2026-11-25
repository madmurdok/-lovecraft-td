class_name MainLoadingTest
extends GdUnitTestSuite
## LT-92 frame A: Main shows a plain "Loading..." frame, then starts the game two frames
## later (docs/design/LT-92-startup-frames.md, edit map 1). A refusal never shows it, and a
## restart skips it.


class RefusingMain extends "res://scenes/main.gd":
	var refused_from := ""

	func _refuse_to_start(dir: String, _errors: Array[String]) -> void:
		refused_from = dir


var _vp: SubViewport


func before_test() -> void:
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	EffectText.use(null)
	LookCatalog.use(null)


func _loading_nodes(m: Node) -> Array[Node]:
	return m.find_children("Loading", "", true, false)


func _boot() -> Node:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	_vp.add_child(m)  # _ready runs here; its two awaited frames start now
	return m


func test_loading_layer_is_shown_before_the_game_exists() -> void:
	var m := _boot()
	assert_object(m.game).is_null()
	assert_object(m.loading).is_not_null()
	assert_array(_loading_nodes(m)).has_size(1)
	assert_bool(m.loading.is_inside_tree()).is_true()
	assert_object(m.find_child("Game", true, false)).is_null()  # no game scene yet
	assert_int(m.loading.layer).is_equal(Game.UI_LAYER + 1)
	var labels: Array[Node] = m.loading.find_children("*", "Label", true, false)
	assert_array(labels).has_size(1)
	assert_str((labels[0] as Label).text).is_equal(m.LOADING_TEXT)


func test_the_game_starts_after_two_frames_and_the_loading_layer_is_removed() -> void:
	var m := _boot()
	var loading: CanvasLayer = m.loading
	await get_tree().process_frame
	# One frame in (the Loading frame's draw is still to come): no game, no game logic.
	assert_object(m.game).is_null()
	assert_object(m.find_child("Game", true, false)).is_null()
	assert_bool(loading.is_inside_tree()).is_true()
	await get_tree().process_frame
	assert_object(m.game).is_not_null()
	assert_bool(m.game.is_inside_tree()).is_true()
	assert_object(m.loading).is_null()
	assert_array(_loading_nodes(m)).is_empty()
	assert_bool(is_instance_valid(loading) and loading.is_inside_tree()).is_false()
	await get_tree().process_frame
	assert_array(_loading_nodes(m)).is_empty()  # and it stays gone


func test_the_game_does_not_start_when_main_leaves_the_tree_during_loading() -> void:
	var m := _boot()
	_vp.remove_child(m)
	for i in 3:
		await get_tree().process_frame
	assert_object(m.game).is_null()
	m.free()


func test_a_refusal_never_shows_the_loading_layer() -> void:
	var errs := EffectText.use({"modes": {}})
	assert_array(errs).is_not_empty()
	var m: RefusingMain = auto_free(RefusingMain.new())
	_vp.add_child(m)
	assert_str(m.refused_from).is_equal(EffectText.PATH)
	assert_object(m.loading).is_null()
	assert_array(_loading_nodes(m)).is_empty()
	for i in 3:
		await get_tree().process_frame
	assert_object(m.loading).is_null()
	assert_array(_loading_nodes(m)).is_empty()
	assert_object(m.game).is_null()
	_vp.remove_child(m)


func test_a_restart_creates_the_fresh_game_without_a_loading_layer() -> void:
	var m := _boot()
	for i in 2:
		await get_tree().process_frame
	var old: Game = m.game
	assert_object(old).is_not_null()
	old.restart_requested.emit()  # what the end screen's restart button does
	await get_tree().process_frame  # the deferred start_game
	await get_tree().process_frame
	var fresh: Game = m.game
	assert_bool(fresh != old).is_true()
	assert_bool(fresh.is_inside_tree()).is_true()
	assert_object(m.loading).is_null()
	assert_array(_loading_nodes(m)).is_empty()
