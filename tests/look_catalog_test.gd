class_name LookCatalogTest
extends GdUnitTestSuite
## LT-104 §2, §4 pins 1, 3, 5, 6, 7: the look catalog without a board. With no override every
## look is the one derived from the attack mode (the built-in rows keep today's colours and
## caps); an override is used only on the levels whose mode its look draws; every enemy
## derives `enemy` (Q2: no built-in boss); validate and check_config name each problem.
## Tests that inject a table restore the shipped file with LookCatalog.use(null).

const FIXTURE := "res://tests/fixtures/looks/variant_looks.json"
const SLOTS := [[0, ""], [1, ""], [2, "a"], [2, "b"]]
const DUP_FILE := "looks_dup.json"

var _config: GameConfig


func before() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config


func after_test() -> void:
	LookCatalog.use(null)
	if FileAccess.file_exists(TestUserDir.path(DUP_FILE)):
		DirAccess.remove_absolute(TestUserDir.path(DUP_FILE))


# --- helpers -----------------------------------------------------------------------------

## A tower of def `id` at `slot` ([level, branch]); the catalog reads only def and stats.
func _tower(id: String, slot: Array) -> SimTower:
	var t := SimTower.new()
	t.def = _config.towers[id]
	t.level = slot[0]
	t.branch = slot[1]
	return t


func _enemy(id: String) -> SimEnemy:
	var e := SimEnemy.new()
	e.def = _config.enemies[id]
	return e


static func _fixture() -> Dictionary:
	var r := TextLoader.read_json(FIXTURE)
	return r["data"]


static func _has(errs: Array, part: String) -> bool:
	for e: String in errs:
		if e.contains(part):
			return true
	return false


func _assert_rejects(table: Variant, part: String) -> void:
	var errs := LookCatalog.validate(table)
	assert_bool(_has(errs, part)).override_failure_message(
		"%s: want an error containing '%s', got %s" % [JSON.stringify(table), part, errs]).is_true()


func _assert_accepts(table: Variant) -> void:
	var errs := LookCatalog.validate(table)
	assert_array(errs).override_failure_message("%s: %s" % [JSON.stringify(table), errs]) \
		.is_empty()


# --- 1, 7: no override = the derived look, today's colours -------------------------------

func test_the_shipped_file_is_valid_and_fits_the_shipped_config() -> void:
	LookCatalog.use(null)
	assert_array(LookCatalog.errors()).is_empty()
	assert_array(LookCatalog.check_config(_config)).is_empty()


func test_with_no_override_every_shipped_tower_slot_gets_its_derived_look() -> void:
	for table: Variant in [null, {}]:
		LookCatalog.use(table)
		var n := 0
		for id: String in _config.towers:
			for slot: Array in SLOTS:
				var t := _tower(id, slot)
				assert_str(Board.shot_kind(t)).override_failure_message("%s %s" % [id, slot]) \
					.is_equal(LookCatalog.derived_tower_look(t.stats()))
				n += 1
		assert_int(n).is_equal(_config.towers.size() * 4)


func test_built_in_rows_keep_todays_colours_effects_areas_and_caps() -> void:
	LookCatalog.use({})
	var want := {
		"tracer": [Board.TRACER_COLOR, "tracer", ""],
		"harpoon": [Board.HARPOON_COLOR, "harpoon", ""],
		"wave": [Board.WAVE_RIM, "wave", ""],
		"shell": [Board.SHELL_COLOR, "shell", ""],
		"beam": [Board.BEAM_COLOR, "beam", ""],
		"dynamite": [Board.DYNAMITE_COLOR, "dynamite", ""],
		"banish": [Board.BANISH_COLOR, "banish", ""],
		"aura": [EntityLayer.WARD_COLOR, "", "ward"],
		"searchlight": [EntityLayer.SEARCHLIGHT_COLOR, "", "searchlight"],
		"summon": [EntityLayer.SUMMON_COLOR, "", "summon_ring"],
	}
	for id: String in want:
		var row := LookCatalog.row(id)
		assert_that(EntityLayer.attack_color(id)).override_failure_message(id) \
			.is_equal(want[id][0])
		assert_str(row["fx"]).override_failure_message(id).is_equal(want[id][1])
		assert_str(row["area"]).override_failure_message(id).is_equal(want[id][2])
		assert_int(row["cap"]).override_failure_message(id).is_equal(FxLayer.MAX_FX_PER_TOWER)
	assert_that(EntityLayer.attack_color("no_such_look")).is_equal(Color.BLACK)
	assert_str(LookCatalog.row("no_such_look")["fx"]).is_empty()


# --- 3: Q2, every enemy derives `enemy` ----------------------------------------------------

func test_every_enemy_derives_the_enemy_look_a_boss_too() -> void:
	LookCatalog.use({})
	for id: String in _config.enemies:
		assert_str(LookCatalog.enemy_look(_enemy(id))).override_failure_message(id) \
			.is_equal("enemy")
	var boss := EnemyDef.new()
	boss.id = "probe_boss"
	boss.traits = {"boss": {}}
	assert_str(LookCatalog.derived_enemy_look(boss)).is_equal("enemy")
	var row := LookCatalog.enemy_row("enemy")
	assert_that(row["color"]).is_equal(EntityLayer.COLOR_ENEMY)
	assert_float(row["radius"]).is_equal(LookCatalog.ENEMY_RADIUS)
	assert_float(LookCatalog.ENEMY_RADIUS).is_equal(0.25)
	assert_bool(row["ring"]).is_false()
	assert_bool(LookCatalog.builtin().has("boss")).is_false()
	# A tower look id is no enemy look: the body falls back to `enemy`.
	assert_that(LookCatalog.enemy_row("tracer")["color"]).is_equal(EntityLayer.COLOR_ENEMY)


func test_an_enemy_override_applies_to_its_def_only() -> void:
	assert_array(LookCatalog.use(_fixture())).is_empty()
	assert_str(LookCatalog.enemy_look(_enemy("shoggoth"))).is_equal("big_body")
	assert_str(LookCatalog.enemy_look(_enemy("deep_one"))).is_equal("enemy")
	assert_str(LookCatalog.enemy_look(_enemy("cultist"))).is_equal("enemy")
	var row := LookCatalog.enemy_row("big_body")
	assert_that(row["color"]).is_equal(Color(0.4, 0.7, 0.9))
	assert_float(row["radius"]).is_equal_approx(0.4, 0.0001)
	assert_bool(row["ring"]).is_true()


# --- 1, 2: an override only where its look draws the level's mode (Q3) ---------------------

func test_an_override_is_used_on_the_levels_whose_mode_its_look_draws() -> void:
	assert_array(LookCatalog.use(_fixture())).is_empty()
	# Coast battery: L1, L2 and branch a fire single shots (tracer draws SINGLE); branch b
	# is a BLAST, which tracer cannot draw: the derived shell there.
	for slot: Array in [[0, ""], [1, ""], [2, "a"]]:
		assert_str(Board.shot_kind(_tower("coast_battery", slot))) \
			.override_failure_message(str(slot)).is_equal("tracer")
	assert_str(Board.shot_kind(_tower("coast_battery", [2, "b"]))).is_equal("shell")
	# Rifleman: its variant on every slot, the BURST branch included.
	for slot: Array in SLOTS:
		assert_str(Board.shot_kind(_tower("rifleman", slot))) \
			.override_failure_message(str(slot)).is_equal("pale_tracer")
	# A tower with no override keeps its derived look.
	assert_str(Board.shot_kind(_tower("harpooner", [0, ""]))).is_equal("harpoon")


func test_a_variant_copies_its_base_and_overrides_colour_and_cap_only() -> void:
	assert_array(LookCatalog.use(_fixture())).is_empty()
	var v := LookCatalog.row("pale_tracer")
	var b := LookCatalog.row("tracer")
	assert_that(v["color"]).is_equal(Color(1.2, 2.0, 2.4))
	assert_that(EntityLayer.attack_color("pale_tracer")).is_equal(Color(1.2, 2.0, 2.4))
	assert_int(v["cap"]).is_equal(3)
	for k: String in ["fx", "area", "modes", "marker", "kind"]:
		assert_that(v[k]).override_failure_message(k).is_equal(b[k])
	# The base row is not recoloured (Q4).
	assert_that(b["color"]).is_equal(Board.TRACER_COLOR)
	assert_int(b["cap"]).is_equal(FxLayer.MAX_FX_PER_TOWER)
	assert_int(LookCatalog.row("wide_gate")["cap"]).is_equal(5)
	assert_that(LookCatalog.row("wide_gate")["color"]).is_equal(Board.BANISH_COLOR)
	assert_that(LookCatalog.row("violet_pack")["color"]).is_equal(Color(1.5, 0.4, 2.0, 0.9))


# --- 5: blast and ally colours from the tower def id ---------------------------------------

func test_blast_and_ally_colours_follow_the_tower_def_look() -> void:
	LookCatalog.use({})
	assert_that(LookCatalog.blast_color("dynamite_crew")).is_equal(Board.DYNAMITE_COLOR)
	assert_that(LookCatalog.blast_color("")).is_equal(Board.DYNAMITE_COLOR)
	assert_that(LookCatalog.ally_color("summoning_circle")).is_equal(EntityLayer.SUMMON_COLOR)
	assert_array(LookCatalog.use(_fixture())).is_empty()
	assert_that(LookCatalog.blast_color("dynamite_crew")).is_equal(Color(0.5, 2.0, 0.5))
	assert_that(LookCatalog.ally_color("summoning_circle")).is_equal(Color(1.5, 0.4, 2.0, 0.9))
	# An override that draws no FUSE / SUMMON leaves the built-in colour.
	assert_that(LookCatalog.blast_color("rifleman")).is_equal(Board.DYNAMITE_COLOR)
	assert_that(LookCatalog.ally_color("rifleman")).is_equal(EntityLayer.SUMMON_COLOR)
	assert_that(LookCatalog.blast_color("no_such_tower")).is_equal(Board.DYNAMITE_COLOR)


# --- 6: validate --------------------------------------------------------------------------

func test_validate_accepts_the_fixture_empty_sections_and_edge_values() -> void:
	_assert_accepts(_fixture())
	_assert_accepts({})
	_assert_accepts({"looks": {}, "towers": {}, "enemies": {}})
	_assert_accepts({"looks": {"a": {"base": "tracer", "cap": 1, "color": [0, 0, 0]},
		"b": {"base": "beam", "cap": 8, "color": [4, 4, 4, 4]},
		"c": {"base": "enemy", "radius": 0.15, "ring": false},
		"d": {"base": "enemy", "radius": 0.5}}})
	_assert_accepts({"towers": {"rifleman": "harpoon"}, "enemies": {"cultist": "enemy"}})


func test_validate_rejects_bad_roots_sections_and_bases() -> void:
	_assert_rejects([], "root must be an object")
	_assert_rejects({"look": {}}, "look: unknown section")
	_assert_rejects({"looks": []}, "looks: must be an object")
	_assert_rejects({"towers": "x"}, "towers: must be an object")
	_assert_rejects({"enemies": []}, "enemies: must be an object")
	_assert_rejects({"looks": {"tracer": {"base": "tracer"}}}, "looks.tracer: shadows a built-in")
	_assert_rejects({"looks": {"x": 3}}, "looks.x: must be an object")
	_assert_rejects({"looks": {"x": {}}}, "looks.x.base: must be a built-in look id")
	_assert_rejects({"looks": {"x": {"base": "laser"}}}, "looks.x.base: must be a built-in")
	_assert_rejects({"looks": {"a": {"base": "tracer"}, "b": {"base": "a"}}},
		"looks.b.base: must be a built-in")


func test_validate_rejects_fields_that_do_not_fit_the_kind() -> void:
	_assert_rejects({"looks": {"x": {"base": "tracer", "radius": 0.3}}},
		"looks.x.radius: unknown field for a tower look")
	_assert_rejects({"looks": {"x": {"base": "enemy", "cap": 3}}},
		"looks.x.cap: unknown field for an enemy look")
	_assert_rejects({"looks": {"x": {"base": "tracer", "fx": "beam"}}},
		"looks.x.fx: unknown field for a tower look")


func test_validate_rejects_bad_colours_caps_radii_and_rings() -> void:
	var colour := "looks.x.color: must be [r, g, b] or [r, g, b, a]"
	var channel := "looks.x.color: each channel must be a number 0..4"
	for c: Variant in [[1, 2], [1, 2, 3, 4, 5], "red", {"r": 1}]:
		_assert_rejects({"looks": {"x": {"base": "tracer", "color": c}}}, colour)
	for c: Variant in [[1, 4.5, 1], [-0.1, 1, 1], ["a", 1, 1], [1, 1, 1, null]]:
		_assert_rejects({"looks": {"x": {"base": "tracer", "color": c}}}, channel)
	for cap: Variant in [0, 9, 2.5, "3", true]:
		_assert_rejects({"looks": {"x": {"base": "tracer", "cap": cap}}},
			"looks.x.cap: must be a whole number 1..8")
	for r: Variant in [0.1, 0.6, "0.3"]:
		_assert_rejects({"looks": {"x": {"base": "enemy", "radius": r}}}, "looks.x.radius: must be")
	_assert_rejects({"looks": {"x": {"base": "enemy", "ring": "yes"}}},
		"looks.x.ring: must be true or false")


func test_validate_rejects_assignments_to_unknown_or_wrong_kind_looks() -> void:
	_assert_rejects({"towers": {"rifleman": "laser"}}, "towers.rifleman: \"laser\" is not a look")
	_assert_rejects({"towers": {"rifleman": 3}}, "towers.rifleman: \"3\" is not a look")
	_assert_rejects({"towers": {"rifleman": "enemy"}}, "towers.rifleman: \"enemy\" is not a tower look")
	_assert_rejects({"enemies": {"cultist": "tracer"}},
		"enemies.cultist: \"tracer\" is not an enemy look")
	_assert_rejects({"looks": {"v": {"base": "enemy"}}, "towers": {"rifleman": "v"}},
		"towers.rifleman: \"v\" is not a tower look")
	# A variant with a bad base names no look.
	_assert_rejects({"looks": {"v": {"base": "laser"}}, "towers": {"rifleman": "v"}},
		"towers.rifleman: \"v\" is not a look")


func test_a_duplicate_key_in_a_looks_file_is_an_error() -> void:
	DirAccess.make_dir_recursive_absolute(TestUserDir.root())
	var path := TestUserDir.path(DUP_FILE)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"towers": {"rifleman": "tracer", "rifleman": "harpoon"}}')
	f.close()
	var r := TextLoader.read_json(path)
	assert_bool(_has(r["errors"], "towers.rifleman: duplicate key")) \
		.override_failure_message(str(r["errors"])).is_true()


func test_an_invalid_injected_table_is_used_as_empty_and_null_reloads_the_file() -> void:
	var errs := LookCatalog.use({"towers": {"rifleman": "pale_tracer"}})
	assert_array(errs).is_not_empty()
	assert_array(LookCatalog.errors()).is_equal(errs)
	assert_str(Board.shot_kind(_tower("rifleman", [0, ""]))).is_equal("tracer")
	assert_array(LookCatalog.use(null)).is_empty()
	assert_array(LookCatalog.errors()).is_empty()


# --- 7: check_config ------------------------------------------------------------------------

func test_check_config_flags_unknown_ids_and_a_dead_override() -> void:
	assert_array(LookCatalog.use({"towers": {"ghost_tower": "tracer", "rifleman": "harpoon",
		"coast_battery": "wave", "harpooner": "harpoon"},
		"enemies": {"ghost": "enemy", "cultist": "enemy"}})).is_empty()
	var errs := LookCatalog.check_config(_config)
	assert_bool(_has(errs, "towers.ghost_tower: no such tower")).is_true()
	assert_bool(_has(errs, "towers.rifleman: look \"harpoon\" draws none of this tower's modes")) \
		.is_true()
	assert_bool(_has(errs, "enemies.ghost: no such enemy")).is_true()
	# Coast battery's branch b is a BLAST, which wave draws: a live override.
	assert_bool(_has(errs, "coast_battery")).override_failure_message(str(errs)).is_false()
	assert_bool(_has(errs, "harpooner")).is_false()
	assert_bool(_has(errs, "cultist")).is_false()
	assert_int(errs.size()).override_failure_message(str(errs)).is_equal(3)


func test_check_config_passes_the_fixture() -> void:
	assert_array(LookCatalog.use(_fixture())).is_empty()
	assert_array(LookCatalog.check_config(_config)).is_empty()
