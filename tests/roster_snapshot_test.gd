class_name RosterSnapshotTest
extends GdUnitTestSuite
## LT-98 (LT-94 A-X1, LT-96 D3): the one test that pins the shipped roster of res://data.
## A content task that adds, removes or renames a tower, an enemy or a wave updates this
## snapshot on purpose; every other config test checks invariants over every def instead
## (config_valid_test.gd), so it stays green when content changes.

const TOWER_IDS := ["rifleman", "harpooner", "elder_sign", "necronomicon_reader",
	"dynamite_crew", "coast_battery", "searchlight", "resonator", "silver_key",
	"summoning_circle"]
const ENEMY_IDS := ["cultist", "hybrid", "deep_one", "night_gaunt", "shoggoth"]
const WAVE_COUNT := 10
const TOUGHEST_ENEMY := "shoggoth"  ## LT-23 S15: the boss has the most hp of all enemies


func test_shipped_roster_matches_the_snapshot() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_array(r.config.towers.keys()).contains_exactly_in_any_order(TOWER_IDS)
	assert_array(r.config.enemies.keys()).contains_exactly_in_any_order(ENEMY_IDS)
	assert_int(r.config.waves.waves.size()).is_equal(WAVE_COUNT)
	for id: String in r.config.enemies:
		if id != TOUGHEST_ENEMY:
			assert_float(r.config.enemies[TOUGHEST_ENEMY].hp).override_failure_message(
				"%s must out-hp %s" % [TOUGHEST_ENEMY, id]).is_greater(r.config.enemies[id].hp)
