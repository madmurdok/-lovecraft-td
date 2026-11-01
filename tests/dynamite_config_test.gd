class_name DynamiteConfigTest
extends ConfigTestBase
## LT-47 config fields (docs/design/LT-46-tower-roster.md §2.3): `glyph` (optional, one
## visible character, default name.left(1), unique across towers), `targets` ("all" default
## or "ground"), `fuse_seconds` (needs aoe_radius > 0; never with pierce or pull_cells).

const T := "towers.json"
const DYN := "towers.dynamite_crew"


func _dyn(fn: Callable) -> ConfigLoadResult:
	return load_json_edit(T, func(d: Dictionary) -> void: fn.call(d["towers"]["dynamite_crew"]))


func test_shipped_crew_is_ground_only_with_glyph_d_and_others_default() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	var dyn: TowerDef = r.config.towers["dynamite_crew"]
	assert_str(dyn.glyph).is_equal("D")
	assert_str(dyn.targets).is_equal("ground")
	assert_bool(dyn.ground_only()).is_true()
	for id: String in r.config.towers:
		if id == "dynamite_crew":
			continue
		var t: TowerDef = r.config.towers[id]
		if id != "coast_battery":  # LT-48 sets glyph "B" on purpose
			assert_str(t.glyph).override_failure_message(id).is_equal(t.name.left(1))
		assert_str(t.targets).override_failure_message(id).is_equal("all")
		assert_bool(t.ground_only()).override_failure_message(id).is_false()


func test_a_visible_non_ascii_glyph_is_accepted() -> void:
	var r := _dyn(func(t: Dictionary) -> void: t["glyph"] = "Ж")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_str(r.config.towers["dynamite_crew"].glyph).is_equal("Ж")


func test_glyph_must_be_exactly_one_visible_character() -> void:
	for g: String in ["", " ", "\t", "\n", String.chr(0x1F), String.chr(0xA0), "DD"]:
		var r := _dyn(func(t: Dictionary) -> void: t["glyph"] = g)
		assert_rejected(r, T, DYN + ".glyph")
		assert_bool(has_error(r, T, DYN + ".glyph", "1 visible character")) \
			.override_failure_message("glyph U+%04X..." % (g.unicode_at(0) if g != "" else 0)) \
			.is_true()


func test_glyph_must_be_a_string() -> void:
	assert_rejected(_dyn(func(t: Dictionary) -> void: t["glyph"] = 5), T, DYN + ".glyph")


func test_a_duplicate_glyph_is_rejected() -> void:
	var r := load_json_edit(T, func(d: Dictionary) -> void: d["towers"]["rifleman"]["glyph"] = "D")
	assert_bool(r.ok).is_false()
	assert_bool(has_error(r, T, DYN, "already used") or has_error(r, T, "towers.rifleman",
		"already used")).override_failure_message("\n".join(r.errors)).is_true()


func test_a_default_glyph_counts_for_uniqueness() -> void:
	# No "glyph" key: "Demolition" defaults to "D", the crew's explicit glyph.
	var r := load_json_edit(T, func(d: Dictionary) -> void:
		d["towers"]["rifleman"]["name"] = "Demolition")
	assert_bool(r.ok).is_false()
	assert_bool(has_error(r, T, DYN, "already used") or has_error(r, T, "towers.rifleman",
		"already used")).override_failure_message("\n".join(r.errors)).is_true()


func test_targets_is_all_or_ground() -> void:
	assert_rejected(_dyn(func(t: Dictionary) -> void: t["targets"] = "air"), T, DYN + ".targets",
		"air")
	assert_rejected(_dyn(func(t: Dictionary) -> void: t["targets"] = 1), T, DYN + ".targets")
	var r := _dyn(func(t: Dictionary) -> void: t["targets"] = "all")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	assert_bool(r.config.towers["dynamite_crew"].ground_only()).is_false()


func test_fuse_needs_an_aoe_radius() -> void:
	var r := _dyn(func(t: Dictionary) -> void: t["levels"][0]["effects"].erase("aoe_radius"))
	assert_rejected(r, T, DYN + ".levels[0].effects.fuse_seconds", "needs aoe_radius")


func test_fuse_cannot_combine_with_pierce() -> void:
	var r := _dyn(func(t: Dictionary) -> void: t["levels"][1]["effects"]["pierce"] = 0.5)
	assert_rejected(r, T, DYN + ".levels[1].effects.fuse_seconds", "cannot combine with pierce")


func test_fuse_cannot_combine_with_pull_cells() -> void:
	var r := _dyn(func(t: Dictionary) -> void: t["branches"]["a"]["effects"]["pull_cells"] = 1)
	assert_rejected(r, T, DYN + ".branches.a.effects.fuse_seconds",
		"cannot combine with pull_cells")
