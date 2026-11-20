class_name GameFixtureTest
extends GdUnitTestSuite
## LT-74 (LT-65 B1): GameFixture hands the suite's seed to the Game's simulation. No migrated
## suite reads the run seed, so without this a fixture that dropped the seed would go unseen.


func test_make_game_passes_the_seed_to_the_simulation() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).is_true()
	for seed in [7, 42]:
		var game := GameFixture.make_game(null, r.config, seed)
		var expected := SimRng.new(seed)
		for stream in [SimRng.Stream.SPAWN, SimRng.Stream.COMBAT, SimRng.Stream.LOOT]:
			assert_int(game.sim.rng(stream).seed).is_equal(expected.stream(stream).seed)
		game.free()
