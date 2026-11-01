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


func test_role_budget_is_24_chars_and_every_shipped_role_fits_it() -> void:
	# LT-37: one short panel line (168 px at 1280x720).
	assert_int(TowerDef.ROLE_MAX_CHARS).is_equal(24)
	var cfg := _real()
	var checked := 0
	for id: String in cfg.towers:
		var def: TowerDef = cfg.towers[id]
		assert_int(def.role.length()).override_failure_message("%s: '%s'" % [id, def.role]) \
			.is_less_equal(TowerDef.ROLE_MAX_CHARS)
		checked += 1
		for b: String in TowerDef.BRANCH_IDS:
			var role: String = def.branches[b].role
			assert_int(role.length()).override_failure_message("%s.%s: '%s'" % [id, b, role]) \
				.is_less_equal(TowerDef.ROLE_MAX_CHARS)
			checked += 1
	assert_int(checked).is_greater(0)


func test_a_25_char_role_is_rejected_naming_the_path() -> void:
	var text := "x".repeat(25)
	assert_rejected(load_json_edit(T, func(d: Dictionary) -> void: _tower(d)["role"] = text),
		T, "towers.rifleman.role", "at most 24")
	assert_rejected(load_json_edit(T, func(d: Dictionary) -> void:
		_tower(d, "harpooner")["branches"]["b"]["role"] = text),
		T, "towers.harpooner.branches.b.role", "at most 24")


# --- 12: pending effects -------------------------------------------------------------------

## LT-29 wired every L3 effect: PENDING is empty and no shipped level or branch is pending.
func test_nothing_shipped_is_pending() -> void:
	assert_array(Array(TowerDef.Level.PENDING)).is_empty()
	var cfg := _real()
	assert_int(cfg.towers.size()).is_greater(0)
	for id: String in cfg.towers:
		var def: TowerDef = cfg.towers[id]
		for l in def.levels:
			assert_bool(l.has_pending()).override_failure_message("%s level" % id).is_false()
		for b: String in TowerDef.BRANCH_IDS:
			assert_bool(def.branches[b].has_pending()) \
				.override_failure_message("%s.%s" % [id, b]).is_false()


func test_has_pending_reads_only_effect_keys() -> void:
	var l := TowerDef.Level.new()
	assert_bool(l.has_pending()).is_false()
	l.effects = {"pierce": 1.0, "slow": 0.3, "aoe_radius": 1.5, "damage_taken_multiplier": 1.25}
	assert_bool(l.has_pending()).is_false()
	l.effects["bleed_dps"] = 0.0
	assert_bool(l.has_pending()).is_false()  # a zero value is not an effect
	# LT-29: the formerly pending keys are wired, so a non-zero value is not pending either.
	for key: String in ["crit_chance", "crit_multiplier", "burst_targets", "bleed_dps",
			"bleed_seconds", "pull_cells", "pull_max_hp", "pull_immune_seconds", "strip_armor"]:
		var w := TowerDef.Level.new()
		w.effects[key] = 1.0
		assert_bool(w.has_pending()).override_failure_message(key).is_false()
	for key: String in TowerDef.Level.PENDING:
		var k := TowerDef.Level.new()
		k.effects[key] = 1.0
		assert_bool(k.has_pending()).override_failure_message(key).is_true()


## LT-23 pin 18: the drain stat left the schema and PENDING; a reserve is not pending.
## LT-29: the Corrupted Seal's strip_armor is wired, so the Seal is not pending with or
## without it.
func test_sanity_per_second_left_pending_and_the_seal_is_not_pending() -> void:
	assert_bool(TowerDef.Level.PENDING.has("sanity_per_second")).is_false()
	var k := TowerDef.Level.new()
	k.sanity_reserve = 15.0
	assert_bool(k.has_pending()).is_false()
	var seal: TowerDef.Level = _real().towers["elder_sign"].branches["b"]
	assert_float(seal.sanity_reserve).is_greater(0.0)
	assert_float(seal.effects.get("strip_armor", 0.0)).is_greater(0.0)
	assert_bool(seal.has_pending()).is_false()
	seal.effects.erase("strip_armor")
	assert_bool(seal.has_pending()).is_false()
