class_name GameSnapshotTest
extends GdUnitTestSuite
## LT-85 §4, §9 behaviour 6 and S7 behaviours 16-19: Game.snapshot exists once setup returns,
## a command through Game rebuilds it at once (before the panels flush), advance rebuilds
## only when it stepped, and a direct sim poke reaches presentation only through
## GameFixture.sync.

var _vp: SubViewport
var _game: Game


func before_test() -> void:
	_vp = GameFixture.make_viewport(self)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start() -> void:
	_game = GameFixture.make_game(_vp, GoldenRuns.golden_config(), 7)
	await get_tree().process_frame
	_game.advance(0.0)


func _buildable() -> Vector2i:
	var m := _game.sim.state.map
	for y in m.height:
		for x in m.width:
			if m.is_buildable(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_the_snapshot_exists_as_soon_as_setup_returns() -> void:
	var game := GameFixture.make_game(null, GoldenRuns.golden_config(), 7)  # no _ready yet
	assert_object(game.snapshot).is_not_null()
	assert_int(game.snapshot.gold).is_equal(game.sim.state.gold)
	assert_object(game.snapshot.map).is_same(game.sim.state.map)
	game.free()


func test_a_command_through_game_rebuilds_the_snapshot_without_a_step() -> void:
	await _start()
	var cell := _buildable()
	var before := _game.snapshot
	var tick := _game.sim.state.tick
	assert_int(_game.commands.build("rifleman", cell)).is_equal(SimCommand.CommandResult.OK)
	assert_int(_game.sim.state.tick).is_equal(tick)
	assert_object(_game.snapshot).is_not_same(before)
	assert_int(_game.snapshot.gold).is_less(before.gold)
	assert_int(_game.snapshot.gold).is_equal(_game.sim.state.gold)
	assert_object(_game.snapshot.tower_at(cell)).is_not_null()
	assert_object(before.tower_at(cell)).is_null()
	# the panels flushed on the new snapshot: the money label shows the post-command gold
	assert_str(_game.hud.gold_label.text).is_equal("Money: " + TowerText.money(_game.snapshot.gold))


func test_advance_rebuilds_only_when_it_stepped() -> void:
	await _start()
	var snap := _game.snapshot
	_game.advance(0.0)
	assert_object(_game.snapshot).is_same(snap)
	_game.advance(0.5)  # a half second is many ticks at 1x
	assert_object(_game.snapshot).is_not_same(snap)
	assert_int(_game.snapshot.tick).is_equal(_game.sim.state.tick)
	assert_int(_game.snapshot.tick).is_greater(snap.tick)


func test_a_direct_sim_poke_is_not_seen_until_sync() -> void:
	await _start()
	var gold := _game.snapshot.gold
	_game.sim.state.gold += 77
	assert_int(_game.snapshot.gold).is_equal(gold)
	GameFixture.sync(_game)
	assert_int(_game.snapshot.gold).is_equal(gold + 77)
