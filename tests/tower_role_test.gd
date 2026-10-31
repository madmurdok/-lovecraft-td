class_name TowerRoleTest
extends ConfigTestBase
## LT-24 §1: the optional `role` line on towers and branches (Decision 5) and the PENDING
## effect keys behind "(coming soon)" (Decision 1).

const T := "towers.json"


func _real() -> GameConfig:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config


func _tower(d: Dictionary, id := "rifleman") -> Dictionary:
	return d["towers"][id]


# --- 11: role parsing ------------------------------------------------------------------

func test_role_on_tower_and_branch_is_parsed_and_stripped() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		_tower(d)["role"] = "  Steady shots \t"
		_tower(d)["branches"]["b"]["role"] = "\nTwo of them  ")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_str(r.config.towers["rifleman"].role).is_equal("Steady shots")
	assert_str(r.config.towers["rifleman"].branches["b"].role).is_equal("Two of them")


func test_absent_role_is_empty() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		_tower(d).erase("role")
		_tower(d)["branches"]["a"].erase("role"))
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var def: TowerDef = r.config.towers["rifleman"]
	assert_str(def.role).is_equal("")
	assert_str(def.branches["a"].role).is_equal("")
	assert_str(def.branches["b"].role).is_not_empty()
	for l in def.levels:
		assert_str(l.role).is_equal("")


func test_role_of_exactly_the_max_length_is_accepted() -> void:
	var text := "x".repeat(TowerDef.ROLE_MAX_CHARS)
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		_tower(d)["role"] = text
		_tower(d)["branches"]["a"]["role"] = " " + text + " ")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_str(r.config.towers["rifleman"].branches["a"].role).is_equal(text)


func test_bad_roles_are_rejected_with_their_path() -> void:
	var too_long := "x".repeat(TowerDef.ROLE_MAX_CHARS + 1)
	var cases := [
		["towers.rifleman.role", "expected string", func(d: Dictionary) -> void: _tower(d)["role"] = 5],
		["towers.rifleman.role", "must not be empty", func(d: Dictionary) -> void: _tower(d)["role"] = ""],
		["towers.rifleman.role", "must not be empty", func(d: Dictionary) -> void: _tower(d)["role"] = "   "],
		["towers.rifleman.role", "at most %d" % TowerDef.ROLE_MAX_CHARS,
			func(d: Dictionary) -> void: _tower(d)["role"] = too_long],
		["towers.harpooner.branches.a.role", "expected string",
			func(d: Dictionary) -> void: _tower(d, "harpooner")["branches"]["a"]["role"] = ["x"]],
		["towers.harpooner.branches.b.role", "must not be empty",
			func(d: Dictionary) -> void: _tower(d, "harpooner")["branches"]["b"]["role"] = " \t "],
		["towers.elder_sign.branches.b.role", "at most",
			func(d: Dictionary) -> void: _tower(d, "elder_sign")["branches"]["b"]["role"] = too_long],
		["towers.rifleman.levels[0].role", "not allowed on levels",
			func(d: Dictionary) -> void: _tower(d)["levels"][0]["role"] = "L1 text"],
		["towers.rifleman.levels[1].role", "not allowed on levels",
			func(d: Dictionary) -> void: _tower(d)["levels"][1]["role"] = "L2 text"],
	]
	for c: Array in cases:
		assert_rejected(load_json_edit(T, c[2]), T, c[0], c[1])


func test_shipped_config_has_a_role_on_every_tower_and_branch() -> void:
	var cfg := _real()
	for id: String in cfg.towers:
		var def: TowerDef = cfg.towers[id]
		assert_str(def.role).override_failure_message(id).is_not_empty()
		for b: String in TowerDef.BRANCH_IDS:
			assert_str(def.branches[b].role).override_failure_message("%s.%s" % [id, b]) \
				.is_not_empty()


# --- 12: pending effects -------------------------------------------------------------------

func test_has_pending_on_the_shipped_branches_and_levels() -> void:
	var cfg := _real()
	var pending := {
		"rifleman": {"a": true, "b": true},
		"harpooner": {"a": true, "b": true},
		"elder_sign": {"a": false, "b": true},
		"necronomicon_reader": {"a": false, "b": false},
	}
	for id: String in pending:
		var def: TowerDef = cfg.towers[id]
		for l in def.levels:
			assert_bool(l.has_pending()).override_failure_message("%s level" % id).is_false()
		for b: String in pending[id]:
			assert_bool(def.branches[b].has_pending()) \
				.override_failure_message("%s.%s" % [id, b]).is_equal(pending[id][b])


func test_has_pending_reads_effects_and_the_sanity_per_second_stat() -> void:
	var l := TowerDef.Level.new()
	assert_bool(l.has_pending()).is_false()
	l.effects = {"pierce": 1.0, "slow": 0.3, "aoe_radius": 1.5, "damage_taken_multiplier": 1.25}
	assert_bool(l.has_pending()).is_false()
	l.effects["bleed_dps"] = 0.0
	assert_bool(l.has_pending()).is_false()  # a zero value is not an effect
	for key: String in TowerDef.Level.PENDING:
		var k := TowerDef.Level.new()
		if key == "sanity_per_second":
			k.sanity_per_second = 0.2
		else:
			k.effects[key] = 1.0
		assert_bool(k.has_pending()).override_failure_message(key).is_true()
