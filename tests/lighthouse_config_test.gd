class_name LighthouseConfigTest
extends ConfigTestBase
## LT-30 §1.3 / LT-26 §1.3: economy.json `lighthouse.beam` (required), `lighthouse.oil` and
## `lighthouse.flare` (optional; flare needs oil). One rejected row per rule, plus the
## accepted edge values and the optional blocks.

const EC := "economy.json"


func _rejects(cases: Array) -> void:
	for c: Array in cases:
		assert_rejected(load_json_edit(EC, func(d: Dictionary) -> void: c[1].call(d["lighthouse"])),
			EC, c[0], c[2])


func _accepts(fn: Callable) -> GameConfig:
	var r := load_json_edit(EC, func(d: Dictionary) -> void: fn.call(d["lighthouse"]))
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config


func test_beam_is_required_and_its_fields_too() -> void:
	_rejects([
		["lighthouse.beam", func(l: Dictionary) -> void: l.erase("beam"), "missing required field"],
		["lighthouse.beam.pattern", func(l: Dictionary) -> void: l["beam"].erase("pattern"),
			"missing required field"],
		["lighthouse.beam.levels", func(l: Dictionary) -> void: l["beam"].erase("levels"),
			"missing required field"],
		["lighthouse.beam.mundane.ignore_miss",
			func(l: Dictionary) -> void: l["beam"]["mundane"].erase("ignore_miss"),
			"missing required field"],
		["lighthouse.beam.occult.power_mult",
			func(l: Dictionary) -> void: l["beam"]["occult"].erase("power_mult"),
			"missing required field"],
		["lighthouse.beam.enemy.cancel_madness_buff",
			func(l: Dictionary) -> void: l["beam"]["enemy"].erase("cancel_madness_buff"),
			"missing required field"],
	])


func test_beam_values() -> void:
	_rejects([
		["lighthouse.beam.pattern", func(l: Dictionary) -> void: l["beam"]["pattern"] = "spin", ""],
		["lighthouse.beam.turn_t", func(l: Dictionary) -> void: l["beam"]["turn_t"] = 1.5, "must be"],
		["lighthouse.beam.reach_cells", func(l: Dictionary) -> void: l["beam"]["reach_cells"] = 0,
			"must be"],
		["lighthouse.beam.half_width_ratio",
			func(l: Dictionary) -> void: l["beam"]["half_width_ratio"] = 0, "must be"],
		["lighthouse.beam.mundane.fire_interval_mult",
			func(l: Dictionary) -> void: l["beam"]["mundane"]["fire_interval_mult"] = 0, "must be"],
		["lighthouse.beam.mundane.ignore_miss",
			func(l: Dictionary) -> void: l["beam"]["mundane"]["ignore_miss"] = 1, "expected boolean"],
		["lighthouse.beam.occult.power_mult",
			func(l: Dictionary) -> void: l["beam"]["occult"]["power_mult"] = 0, "must be"],
		["lighthouse.beam.enemy.cancel_madness_buff",
			func(l: Dictionary) -> void: l["beam"]["enemy"]["cancel_madness_buff"] = "yes",
			"expected boolean"],
	])


func test_beam_levels() -> void:
	_rejects([
		["lighthouse.beam.levels", func(l: Dictionary) -> void: l["beam"]["levels"] = [],
			"must not be empty"],
		["lighthouse.beam.levels[1].beams",
			func(l: Dictionary) -> void: l["beam"]["levels"][1]["beams"] = 3, "must be one of"],
		["lighthouse.beam.levels[2].beams",
			func(l: Dictionary) -> void: l["beam"]["levels"][2]["beams"] = 1, "must not decrease"],
		["lighthouse.beam.levels[0].upgrade_cost",
			func(l: Dictionary) -> void: l["beam"]["levels"][0]["upgrade_cost"] = 10, "unknown field"],
		["lighthouse.beam.levels[1].upgrade_cost",
			func(l: Dictionary) -> void: l["beam"]["levels"][1]["upgrade_cost"] = 0, "must be"],
		["lighthouse.beam.levels[1].upgrade_cost",
			func(l: Dictionary) -> void: l["beam"]["levels"][1].erase("upgrade_cost"),
			"missing required field"],
	])
	var c := _accepts(func(l: Dictionary) -> void:
		l["beam"]["levels"].append({"beams": 8, "upgrade_cost": 1})
		l["flare"]["radius_cells"].append(10)  # LT-57: one radius per level
		l["beam"]["levels"][1]["beams"] = 1)  # equal is not a decrease
	assert_array(c.economy.beam.levels.map(func(v: EconomyConfig.BeamLevel) -> int:
		return v.beams)).is_equal([1, 1, 4, 8])
	assert_int(c.economy.beam.levels[0].upgrade_cost).is_equal(0)


func test_sweep_edges() -> void:
	_rejects([
		["lighthouse.beam.sweep_edges", func(l: Dictionary) -> void:
			l["beam"]["pattern"] = "sweep"
			l["beam"].erase("sweep_edges"), "missing required field"],
		["lighthouse.beam.sweep_edges",
			func(l: Dictionary) -> void: l["beam"]["sweep_edges"] = [[-1, 0]], "expected 2"],
		["lighthouse.beam.sweep_edges[0]",
			func(l: Dictionary) -> void: l["beam"]["sweep_edges"] = [[0, 0], [0, -1]], "zero vector"],
		["lighthouse.beam.sweep_edges[1]",
			func(l: Dictionary) -> void: l["beam"]["sweep_edges"] = [[-1, 0], [0, -1, 2]],
			"expected [x, y]"],
		["lighthouse.beam.sweep_edges[1][0]",
			func(l: Dictionary) -> void: l["beam"]["sweep_edges"] = [[-1, 0], ["a", -1]],
			"expected number"],
		["lighthouse.beam.sweep_edges",
			func(l: Dictionary) -> void: l["beam"]["sweep_edges"] = [[0, -1], [-1, 0]],
			"counter-clockwise"],
		["lighthouse.beam.sweep_edges",
			func(l: Dictionary) -> void: l["beam"]["sweep_edges"] = [[1, 0], [-1, 0]],
			"counter-clockwise"],  # 180°: cross 0
	])
	var rotate := _accepts(func(l: Dictionary) -> void: l["beam"].erase("sweep_edges"))
	assert_array(rotate.economy.beam.sweep_edges).is_empty()
	var sweep := _accepts(func(l: Dictionary) -> void:
		l["beam"]["pattern"] = "sweep"
		l["beam"]["sweep_edges"] = [[0, -2], [3, 0]])
	assert_array(sweep.economy.beam.sweep_edges).is_equal([[0.0, -2.0], [3.0, 0.0]])


func test_oil_and_flare_are_optional_and_flare_needs_oil() -> void:
	var none := _accepts(func(l: Dictionary) -> void:
		l.erase("oil")
		l.erase("flare"))
	assert_object(none.economy.oil).is_null()
	assert_object(none.economy.flare).is_null()
	var oil_only := _accepts(func(l: Dictionary) -> void: l.erase("flare"))
	assert_object(oil_only.economy.oil).is_not_null()
	assert_object(oil_only.economy.flare).is_null()
	_rejects([["lighthouse.flare", func(l: Dictionary) -> void: l.erase("oil"),
		"requires lighthouse.oil"]])


func test_oil_values() -> void:
	_rejects([
		["lighthouse.oil.price", func(l: Dictionary) -> void: l["oil"]["price"] = 0, "must be"],
		["lighthouse.oil.cap", func(l: Dictionary) -> void: l["oil"]["cap"] = 1, "must be"],
		["lighthouse.oil.start", func(l: Dictionary) -> void: l["oil"]["start"] = 17, "must be"],
		["lighthouse.oil.start", func(l: Dictionary) -> void: l["oil"]["start"] = -1, "must be"],
		["lighthouse.oil.cap", func(l: Dictionary) -> void: l["oil"].erase("cap"),
			"missing required field"],
	])
	# cap may equal cost_oil and start may equal cap; without a flare cap >= 1 suffices.
	var c := _accepts(func(l: Dictionary) -> void:
		l["oil"]["cap"] = 8
		l["oil"]["start"] = 8)
	assert_int(c.economy.oil.cap).is_equal(8)
	var lone := _accepts(func(l: Dictionary) -> void:
		l.erase("flare")
		l["oil"]["cap"] = 1
		l["oil"]["start"] = 0)
	assert_int(lone.economy.oil.cap).is_equal(1)


func test_flare_values() -> void:
	_rejects([
		["lighthouse.flare.cost_oil", func(l: Dictionary) -> void: l["flare"]["cost_oil"] = 0,
			"must be"],
		["lighthouse.flare.seconds", func(l: Dictionary) -> void: l["flare"]["seconds"] = 0,
			"must be"],
		["lighthouse.flare.cooldown_seconds",
			func(l: Dictionary) -> void: l["flare"]["cooldown_seconds"] = 5, "must be > seconds"],
		["lighthouse.flare.radius_cells[0]",
			func(l: Dictionary) -> void: l["flare"]["radius_cells"][0] = -1, "must be"],
		["lighthouse.flare.enemy_speed_mult",
			func(l: Dictionary) -> void: l["flare"]["enemy_speed_mult"] = 0, "must be"],
		["lighthouse.flare.enemy_speed_mult",
			func(l: Dictionary) -> void: l["flare"]["enemy_speed_mult"] = 1.5, "must be"],
		["lighthouse.flare.width_mult", func(l: Dictionary) -> void: l["flare"]["width_mult"] = 2,
			"unknown field"],  # LT-57: the cone no longer widens
	])
	var c := _accepts(func(l: Dictionary) -> void:
		l["flare"]["radius_cells"] = [0, 0, 0]
		l["flare"]["enemy_speed_mult"] = 1
		l["flare"]["cooldown_seconds"] = 5.01)
	assert_array(c.economy.flare.radius_cells).is_equal([0.0, 0.0, 0.0])
	assert_float(c.economy.flare.enemy_speed_mult).is_equal(1.0)


func test_unknown_fields() -> void:
	_rejects([
		["lighthouse.beam.color", func(l: Dictionary) -> void: l["beam"]["color"] = 1, "unknown field"],
		["lighthouse.beam.occult.drain_mult",  # LT-30 §2: R1, no drain_mult
			func(l: Dictionary) -> void: l["beam"]["occult"]["drain_mult"] = 0.5, "unknown field"],
		["lighthouse.oil.refund", func(l: Dictionary) -> void: l["oil"]["refund"] = 1, "unknown field"],
		["lighthouse.flare.sound", func(l: Dictionary) -> void: l["flare"]["sound"] = 1,
			"unknown field"],
		["lighthouse.lamp", func(l: Dictionary) -> void: l["lamp"] = 1, "unknown field"],
	])


func test_shipped_values_are_the_addendum_numbers() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).is_true()
	var e := r.config.economy
	assert_array(e.beam.levels.map(func(v: EconomyConfig.BeamLevel) -> int: return v.beams)) \
		.is_equal([1, 2, 4])
	assert_float(e.beam.occult_power_mult).is_equal(0.7)
	# LT-57 (owner Q1 "$80 (8 масла)", Q4 "Растёт: 6/8/10"): the radial flare.
	assert_array([e.oil.price, e.oil.start, e.oil.cap]).is_equal([10, 0, 16])
	assert_array([e.flare.cost_oil, e.flare.seconds, e.flare.cooldown_seconds,
		e.flare.enemy_speed_mult]).is_equal([8, 5.0, 30.0, 0.5])
	assert_array(e.flare.radius_cells).is_equal([6.0, 8.0, 10.0])
