class_name EffectTextTest
extends GdUnitTestSuite
## LT-103 §2.4 / §2.5 item 1: data/effect_text.json and EffectText. The guard over the real
## file (every catalog key in exactly one line, every mode labelled), EffectText.validate on
## broken tables, the template ops, the line/short variants, in_row keys and the unknown-key
## fallback. Tests that inject a table restore the file with EffectText.use(null).


func after_test() -> void:
	EffectText.use(null)


## A deep copy of the real file's table.
func _real() -> Dictionary:
	EffectText.use(null)
	return (EffectText.table() as Dictionary).duplicate(true)


static func _line_of(t: Dictionary, key: String) -> Dictionary:
	for entry: Dictionary in t["lines"]:
		if key in entry["keys"]:
			return entry
	return {}


static func _has_error(errs: Array, part: String) -> bool:
	return errs.any(func(e: String) -> bool: return e.contains(part))


# --- 10. guard over the real data ------------------------------------------------------------

func test_the_real_text_file_is_valid() -> void:
	EffectText.use(null)
	assert_array(EffectText.errors()).is_empty()
	assert_array(EffectText.validate(_real())).is_empty()


func test_every_catalog_key_has_exactly_one_line_in_the_real_file() -> void:
	var t := _real()
	assert_bool(t.is_empty()).override_failure_message("effect_text.json did not load") \
		.is_false()
	for key: String in EffectCatalog.keys():
		var n := 0
		for entry: Dictionary in t.get("lines", []):
			if key in entry["keys"]:
				n += 1
		assert_int(n).override_failure_message("\"%s\" is in %d lines" % [key, n]).is_equal(1)
	for name: String in EffectCatalog.Mode.keys():
		assert_bool(t.get("modes", {}).get(name) is String).override_failure_message(name) \
			.is_true()


# --- 7. validate ---------------------------------------------------------------------------

func test_validate_rejects_a_key_in_no_line_and_in_two_lines() -> void:
	var t := _real()
	t["lines"].erase(_line_of(t, "strip_armor"))
	assert_bool(_has_error(EffectText.validate(t),
		"effect key \"strip_armor\" is in 0 lines")).is_true()
	var t2 := _real()
	t2["lines"].append({"keys": ["slow"], "text": "again {slow}"})
	assert_bool(_has_error(EffectText.validate(t2), "effect key \"slow\" is in 2 lines")) \
		.is_true()


func test_validate_rejects_a_bad_op_an_unknown_key_and_a_missing_mode_label() -> void:
	var t := _real()
	_line_of(t, "slow")["text"] = "Slows {slow|pcnt}%"
	assert_bool(_has_error(EffectText.validate(t), "unknown op \"pcnt\"")).is_true()
	var t2 := _real()
	_line_of(t2, "slow")["text"] = "Slows {frost}%"
	assert_bool(_has_error(EffectText.validate(t2), "\"frost\" is not an effect key")).is_true()
	var t3 := _real()
	t3["lines"][0]["keys"].append("frost_aura")
	assert_bool(_has_error(EffectText.validate(t3), "\"frost_aura\" is not an effect key")) \
		.is_true()
	var t4 := _real()
	t4["modes"].erase("FUSE")
	assert_bool(_has_error(EffectText.validate(t4), "modes.FUSE: missing label")).is_true()
	var t5 := _real()
	_line_of(t5, "summon_max")["text"] = "{summon_max|plural:unit}"
	assert_bool(_has_error(EffectText.validate(t5), "\"plural\" takes two words")).is_true()
	assert_array(EffectText.validate([])).is_equal(["root must be an object"])


func test_an_invalid_injected_table_is_used_as_empty_and_null_reloads_the_file() -> void:
	var errs := EffectText.use({"modes": {}})
	assert_array(errs).is_not_empty()
	assert_array(EffectText.errors()).is_equal(errs)
	assert_array(EffectText.lines()).is_empty()
	assert_str(EffectText.mode_label(EffectCatalog.Mode.FUSE)).is_equal("Fuse")
	assert_array(EffectText.use(null)).is_empty()
	assert_array(EffectText.errors()).is_empty()
	assert_array(EffectText.lines()).is_not_empty()
	assert_str(EffectText.mode_label(EffectCatalog.Mode.FUSE)).is_equal("Blast")


# --- 8. format ops and variants ----------------------------------------------------------------

func test_format_ops() -> void:
	assert_str(EffectText.format("{v}", {"v": 2.5})).is_equal("2.5")
	assert_str(EffectText.format("{v|num}", {"v": 3.0})).is_equal("3")
	assert_str(EffectText.format("{v|pct}%", {"v": 0.175})).is_equal("17.5%")
	assert_str(EffectText.format("+{v|pct_over1}%", {"v": 1.5})).is_equal("+50%")
	assert_str(EffectText.format("x{v|plus1}", {"v": 2.0})).is_equal("x3")
	assert_str(EffectText.format("{v|cells}", {"v": 1.0})).is_equal("1 cell")
	assert_str(EffectText.format("{v|cells}", {"v": 1.5})).is_equal("1.5 cells")
	assert_str(EffectText.format("{v} {v|plural:unit:units}", {"v": 1.0})).is_equal("1 unit")
	assert_str(EffectText.format("{v} {v|plural:unit:units}", {"v": 2.0})).is_equal("2 units")
	assert_str(EffectText.format("{v}/{w}", {"v": 1.0}, {"w": 4.0})).is_equal("1/4")
	assert_str(EffectText.format("{w}", {})).is_equal("0")
	assert_str(EffectText.format("no placeholders", {})).is_equal("no placeholders")


func test_crit_reads_x0_in_the_long_line_and_x1_in_the_short_cell() -> void:
	var e := {"crit_chance": 0.2}
	assert_str(EffectText.line_text(_line_of(_real(), "crit_chance"), e)) \
		.is_equal("20% crit, x0 damage")
	assert_str(EffectText.short_text(e)).is_equal("20% crit ×1")


func test_banish_line_variant_follows_banish_targets() -> void:
	var entry := _line_of(_real(), "banish_cells")
	assert_str(EffectText.line_text(entry, {"banish_cells": 4.0})) \
		.is_equal("Banish 4 cells back")
	assert_str(EffectText.line_text(entry, {"banish_cells": 4.0, "banish_targets": 1.0})) \
		.is_equal("Banish 4 cells back")
	assert_str(EffectText.line_text(entry, {"banish_cells": 5.0, "banish_targets": 2.0})) \
		.is_equal("Banish 2 foes 5 cells")
	assert_str(EffectText.short_text({"banish_cells": 4.0, "banish_targets": 1.0})) \
		.is_equal("Back 4 cells")
	assert_str(EffectText.short_text({"banish_cells": 4.0, "banish_targets": 2.0})) \
		.is_equal("Back 4 cells, 2 foes")


func test_short_cell_capitalises_unless_the_first_part_keeps_case() -> void:
	assert_str(EffectText.short_text({"fuse_seconds": 1.0})).is_equal("Fuse 1 s")
	assert_str(EffectText.short_text({"aoe_radius": 1.5})).is_equal("r 1.5")
	assert_str(EffectText.short_text({"aoe_radius": 1.5, "fuse_seconds": 1.0})) \
		.is_equal("r 1.5, fuse 1 s")
	assert_str(EffectText.short_text({})).is_equal("")


func test_in_row_keys_are_left_out_of_special_lines_but_not_effect_lines() -> void:
	assert_array(EffectText.in_row_keys()).is_equal(["pierce", "summon_flying"])
	var l := TowerDef.Level.new()
	l.damage = 10.0
	l.effects = {"pierce": 1.0, "bleed_dps": 6.0, "bleed_seconds": 3.0}
	assert_array(Array(TowerText.effect_lines(l.effects))) \
		.is_equal(["Pierce: 1-cell-wide line", "Bleed 6/s for 3 s"])
	assert_array(Array(TowerText.special_lines(l))).is_equal(["Bleed 6/s for 3 s"])


func test_an_unknown_key_falls_back_to_key_colon_value() -> void:
	assert_array(Array(TowerText.effect_lines({"slow": 0.2, "frost_aura": 2.5}))) \
		.is_equal(["Slows enemies 20%", "frost_aura: 2.5"])
	# A x1 multiplier the catalog does not know is neutral by its suffix: no line.
	assert_array(Array(TowerText.effect_lines({"frost_multiplier": 1.0}))).is_empty()
	assert_array(Array(TowerText.effect_lines({"frost_multiplier": 1.5}))) \
		.is_equal(["frost_multiplier: 1.5"])


# --- LT-122: tips (the hover explanation of a line) -----------------------------------------

const _TIP_VALUES := {"shadow_occult_power_mult": 1.4, "shadow_mundane_fire_interval_mult": 1.6,
	"shadow_mundane_miss_chance_add": 0.3}


func test_the_real_file_has_a_casts_shadow_line_and_tip() -> void:
	var t := _real()
	assert_str(EffectText.line_text(_line_of(t, "casts_shadow"), {"casts_shadow": 1.0})) \
		.is_equal("Shadows towers at night")
	var keys := []
	for entry: Dictionary in t["tips"]:
		keys.append(entry["key"])
	assert_array(keys).contains(["casts_shadow"])


## A tip applies only while its key is active: not for other keys, nor for the neutral value.
func test_tip_text_is_empty_unless_its_key_is_active() -> void:
	EffectText.use(null)
	assert_str(EffectText.tip_text({"casts_shadow": 1.0}, _TIP_VALUES)).is_not_empty()
	assert_str(EffectText.tip_text({"slow": 0.2, "casts_light": 1.0}, _TIP_VALUES)).is_empty()
	assert_str(EffectText.tip_text({}, _TIP_VALUES)).is_empty()
	assert_str(EffectText.tip_text({"casts_shadow": 0.0}, _TIP_VALUES)).is_empty()


## The numbers are the ones passed in, not a literal in the template.
func test_tip_text_formats_the_values_it_is_given() -> void:
	EffectText.use(null)
	var s := EffectText.tip_text({"casts_shadow": 1.0}, _TIP_VALUES)
	assert_str(s).contains("×1.4").contains("+60% fire interval").contains("+30% misses")
	assert_str(s).not_contains("1.15")


## A tip naming a value that `values` lacks is left out whole (no "0" stand-ins).
func test_tip_text_is_empty_when_a_value_is_missing() -> void:
	EffectText.use(null)
	var partial := _TIP_VALUES.duplicate()
	partial.erase("shadow_mundane_miss_chance_add")
	assert_str(EffectText.tip_text({"casts_shadow": 1.0}, partial)).is_empty()
	assert_str(EffectText.tip_text({"casts_shadow": 1.0}, {})).is_empty()


func test_validate_rejects_a_tip_placeholder_that_is_not_a_tip_value() -> void:
	var t := _real()
	t["tips"][0]["text"] = "Shadow x{shadow_power}, slow {slow|pct}%"
	var errs := EffectText.validate(t)
	assert_bool(_has_error(errs, "\"shadow_power\" is not a tip value")).is_true()
	assert_bool(_has_error(errs, "\"slow\" is not a tip value")).is_true()


func test_validate_rejects_two_tips_for_one_key_and_an_unknown_tip_key() -> void:
	var t := _real()
	t["tips"].append({"key": "casts_shadow", "text": "again"})
	assert_bool(_has_error(EffectText.validate(t), "\"casts_shadow\" has another tip")).is_true()
	var t2 := _real()
	t2["tips"][0]["key"] = "frost"
	assert_bool(_has_error(EffectText.validate(t2), "\"frost\" is not an effect key")).is_true()
	var t3 := _real()
	t3["tips"] = "no"
	assert_bool(_has_error(EffectText.validate(t3), "tips: must be an array")).is_true()
