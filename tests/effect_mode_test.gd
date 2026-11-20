class_name EffectModeTest
extends TowerTestBase
## LT-103 §2.2 / §4 pins 1-3: Level.mode is one precedence (EffectCatalog.Mode order) that
## replaces three attack-choice ladders. The ladders as they were before LT-103 (combat
## dispatch/aim/shape, Board.shot_kind, TowerText.attack_text at 6c4d5b7) are frozen below;
## for every shipped and golden level and a synthetic grid of mode-key combos the new
## mappings must equal them. Owner Q1: burst or beam with a shot shape, and beam with burst,
## are rejected at parse, so one precedence holds for every accepted config.

const GOLDEN_DIR := "res://tests/fixtures/golden_data"
const MODE_KEYS := ["burst_targets", "pierce", "fuse_seconds", "aoe_radius", "sanity_scaling",
	"banish_cells", "summon_max"]
## Grid values for each mode key, and the companions parse requires with it.
const GRID_VALUE := {"burst_targets": 2.0, "pierce": 1.0, "fuse_seconds": 1.0,
	"aoe_radius": 1.0, "sanity_scaling": 1.0, "banish_cells": 2.0, "summon_max": 1.0}
const COMPANIONS := {"fuse_seconds": {"aoe_radius": 1.0},
	"banish_cells": {"banish_max_hp": 100.0},
	"summon_max": {"summon_hp": 10.0, "summon_lifetime": 5.0, "summon_speed": 1.0}}
const SLOTS := [[0, ""], [1, ""], [2, "a"], [2, "b"]]


# --- the frozen pre-LT-103 ladders ----------------------------------------------------------

static func _e(l: TowerDef.Level, key: String) -> float:
	return float(l.effects.get(key, 0.0))


static func _old_acts(l: TowerDef.Level) -> bool:
	return l.damage > 0.0 or _e(l, "banish_cells") > 0.0 or _e(l, "summon_max") > 0.0


## CombatSystem.fire_towers before LT-103: dispatch, then aim, then shot shape.
static func old_combat(l: TowerDef.Level) -> String:
	if not _old_acts(l):
		return "skip"
	if _e(l, "banish_cells") > 0.0:
		return "banish"
	if _e(l, "summon_max") > 0.0:
		return "summon"
	var aim := "pick"
	if int(_e(l, "burst_targets")) > 0:
		aim = "burst"
	elif _e(l, "sanity_scaling") > 0.0:
		aim = "beam"
	var shape := "point"
	if _e(l, "fuse_seconds") > 0.0:
		shape = "fuse"
	elif _e(l, "pierce") > 0.0:
		shape = "line"
	elif _e(l, "aoe_radius") > 0.0:
		shape = "blast"
	return aim + "/" + shape


## Board.shot_kind before LT-103.
static func old_board(l: TowerDef.Level) -> String:
	if not _old_acts(l):
		return "searchlight" if _e(l, "reveal_fakes") > 0.0 else "aura"
	if _e(l, "banish_cells") > 0.0:
		return "banish"
	if _e(l, "summon_max") > 0.0:
		return "summon"
	if _e(l, "sanity_scaling") > 0.0:
		return "beam"
	if _e(l, "pierce") > 0.0:
		return "harpoon"
	if _e(l, "fuse_seconds") > 0.0:
		return "dynamite"
	if l.min_range > 0.0:
		return "shell"
	if _e(l, "aoe_radius") > 0.0:
		return "wave"
	return "tracer"


## TowerText.attack_text before LT-103 (is_active: value != neutral, 0 for these keys).
static func old_text(l: TowerDef.Level) -> String:
	if _e(l, "summon_max") > 0.0:
		return "Summon"
	if _e(l, "banish_cells") > 0.0:
		return "Banish"
	if l.damage <= 0.0:
		return "Aura"
	if _e(l, "sanity_scaling") > 0.0:
		return "Beam"
	if _e(l, "burst_targets") != 0.0:
		return "Burst"
	if _e(l, "pierce") != 0.0:
		return "Line"
	if _e(l, "aoe_radius") != 0.0:
		return "Blast"
	return "Single"


## What fire_towers does for `mode` (its dispatch on Level.mode), as old_combat spells it.
static func combat_of_mode(l: TowerDef.Level) -> String:
	var m := l.mode()
	match m:
		EffectCatalog.Mode.AURA:
			return "skip"
		EffectCatalog.Mode.BANISH:
			return "banish"
		EffectCatalog.Mode.SUMMON:
			return "summon"
	var aim := "pick"
	if m == EffectCatalog.Mode.BURST and int(_e(l, "burst_targets")) > 0:
		aim = "burst"
	elif m == EffectCatalog.Mode.BEAM:
		aim = "beam"
	var shape := "point"
	match m:
		EffectCatalog.Mode.FUSE:
			shape = "fuse"
		EffectCatalog.Mode.LINE:
			shape = "line"
		EffectCatalog.Mode.BLAST:
			shape = "blast"
	return aim + "/" + shape


# --- helpers -----------------------------------------------------------------------------

static func _slot(def: TowerDef, slot: Array) -> TowerDef.Level:
	return def.levels[slot[0]] if slot[0] < TowerDef.LEVEL_COUNT else def.branches[slot[1]]


static func _tower_of(l: TowerDef.Level) -> SimTower:
	var def := TowerDef.new()
	def.id = "probe"
	def.kind = "occult"
	def.levels = [l, l]
	var t := SimTower.new()
	t.def = def
	return t


## Every level and branch of the shipped and golden towers: [label, level].
func _all_levels() -> Array:
	var out := []
	var golden := ConfigLoader.load_dir(GOLDEN_DIR)
	assert_bool(golden.ok).override_failure_message("\n".join(golden.errors)).is_true()
	for src: Array in [["data", real_config()], ["golden", golden.config]]:
		var cfg: GameConfig = src[1]
		for id: String in cfg.towers:
			for slot: Array in SLOTS:
				out.append(["%s %s %s%s" % [src[0], id, slot[0], slot[1]],
					_slot(cfg.towers[id], slot)])
	return out


## A level parsed from `effects` (+ damage, min_range); [level, errors].
static func _parse(effects: Dictionary, damage: float, min_range: float) -> Array:
	var obj := {"range": 3.0, "damage": damage, "fire_interval": 1.0, "effects": effects}
	if min_range > 0.0:
		obj["min_range"] = min_range
	var r := ConfigReader.new("towers.json")
	var l := TowerDef.Level.parse(r, obj, "towers.x.levels[0]", false, "occult", false)
	return [l, r.errors]


func _assert_same(at: String, l: TowerDef.Level) -> void:
	assert_str(Board.shot_kind(_tower_of(l))).override_failure_message("%s board" % at) \
		.is_equal(old_board(l))
	assert_str(TowerText.attack_text(l)).override_failure_message("%s text" % at) \
		.is_equal(old_text(l))
	assert_str(combat_of_mode(l)).override_failure_message("%s combat" % at) \
		.is_equal(old_combat(l))


# --- 1. mode pin -------------------------------------------------------------------------

func test_shipped_and_golden_levels_keep_their_board_kind_text_and_combat() -> void:
	var levels := _all_levels()
	assert_int(levels.size()).is_equal(2 * 10 * 4)
	for pair: Array in levels:
		_assert_same(pair[0], pair[1])


func test_grid_of_mode_keys_is_rejected_or_matches_the_old_ladders() -> void:
	var seen_modes := {}
	var accepted := 0
	for mask in 1 << MODE_KEYS.size():
		var base := {}
		for i in MODE_KEYS.size():
			if mask & (1 << i):
				var key: String = MODE_KEYS[i]
				base[key] = GRID_VALUE[key]
				base.merge(COMPANIONS.get(key, {}))
		for min_range: float in [0.0, 2.0]:
			for damage: float in [0.0, 10.0]:
				for reveal: float in [0.0, 1.0]:
					var effects := base.duplicate()
					if reveal > 0.0:
						effects["reveal_fakes"] = reveal
					var p := _parse(effects, damage, min_range)
					if not (p[1] as Array).is_empty():
						continue
					accepted += 1
					var l: TowerDef.Level = p[0]
					seen_modes[l.mode()] = true
					_assert_same("%s dmg %s min %s" % [effects, damage, min_range], l)
	assert_int(accepted).is_greater(0)
	for m: int in EffectCatalog.Mode.values():
		assert_bool(seen_modes.has(m)) \
			.override_failure_message("no accepted grid level has mode %s"
				% EffectCatalog.Mode.find_key(m)).is_true()


## The shot each shipped and golden level fires in a sim, read from its events, equals the
## old combat ladder (dispatch, aim, shape): CombatSystem.fire_towers agrees with Level.mode.
func test_fire_towers_dispatch_aim_and_shape_match_the_old_ladder() -> void:
	var golden := ConfigLoader.load_dir(GOLDEN_DIR)
	assert_bool(golden.ok).is_true()
	var data_cfg := tconfig()
	var golden_cfg := tconfig()
	for id: String in golden_cfg.towers:
		golden_cfg.towers[id].levels = golden.config.towers[id].levels
		golden_cfg.towers[id].branches = golden.config.towers[id].branches
	var checked := 0
	for src: Array in [["data", data_cfg], ["golden", golden_cfg]]:
		var cfg: GameConfig = src[1]
		for id: String in cfg.towers:
			for slot: Array in SLOTS:
				var at := "%s %s %s%s" % [src[0], id, slot[0], slot[1]]
				var l := _slot(cfg.towers[id], slot)
				var want := old_combat(l)
				var got := _observed_combat(cfg, id, slot, l)
				if _e(l, "pull_cells") > 0.0 and want.contains("/"):
					# A pull moves the target between shots, so the aim is not observable.
					want = want.get_slice("/", 1)
					got = got.get_slice("/", 1)
				assert_str(got).override_failure_message(at).is_equal(want)
				checked += 1
	assert_int(checked).is_equal(2 * 10 * 4)


## Builds `id` at `slot` in a fresh sim on `cfg` with two ground enemies in range, then reads
## what fire_towers did: "skip", "summon", "banish" or "<aim>/<shape>".
func _observed_combat(cfg: GameConfig, id: String, slot: Array, l: TowerDef.Level) -> String:
	var sim := Simulation.new(cfg, SEED)
	sim.state.gold = 1000000
	var t := build(sim, id)
	t.level = slot[0]
	t.branch = slot[1]
	sim.drain_events()
	# Two enemies 0.3 cells apart, both outside the dead zone and inside the range.
	var near := maxf(l.min_range + 0.5, 1.0)
	var c1 := 7.0 + sqrt(near * near - 1.0)
	var hp := 100.0 if _e(l, "banish_cells") > 0.0 else HUGE_HP
	var e1 := put(sim, "cultist", c1, hp)
	var e2 := put(sim, "cultist", c1 + 0.3, hp)
	var start := {e1.id: e1.route.position_at(e1.distance),
		e2.id: e2.route.position_at(e2.distance)}
	var shots: Array[SimEvent] = []
	for i in 400:
		var ev := run(sim, 1)
		if not of_type(ev, SimEvent.Type.ALLY_SUMMONED).is_empty():
			return "summon"
		shots.append_array(of_type(ev, SimEvent.Type.SHOT))
		if shots.size() >= 2:
			break
	if shots.is_empty():
		return "skip"
	var first: Dictionary = shots[0].data
	if first.get("banish", false):
		return "banish"
	var aim := "pick"
	if first.get("beam", false):
		aim = "beam"
	elif shots.size() >= 2 and int(shots[1].data["target"]) != int(first["target"]):
		aim = "burst"
	var shape := "point"
	if first.get("fuse", false):
		shape = "fuse"
	elif (first["to"] as Vector2).distance_to(start[int(first["target"])]) > 0.01:
		shape = "line"
	elif (first["hits"] as Array).size() > 1:
		shape = "blast"
	return aim + "/" + shape


# --- 2. Q1 exclusions ----------------------------------------------------------------------

func test_burst_or_beam_with_a_shot_shape_is_rejected() -> void:
	var cases := [["burst_targets", "pierce"], ["burst_targets", "aoe_radius"],
		["burst_targets", "fuse_seconds"], ["burst_targets", "sanity_scaling"],
		["sanity_scaling", "pierce"], ["sanity_scaling", "aoe_radius"],
		["sanity_scaling", "fuse_seconds"]]
	for c: Array in cases:
		var effects := {c[0]: GRID_VALUE[c[0]], c[1]: GRID_VALUE[c[1]]}
		effects.merge(COMPANIONS.get(c[1], {}))
		var errs: Array = _parse(effects, 10.0, 0.0)[1]
		var want := "towers.json: towers.x.levels[0].effects.%s: cannot combine with %s" \
			% [c[0], c[1]]
		assert_bool(errs.any(func(e: String) -> bool: return e.contains(want))) \
			.override_failure_message("%s + %s: want \"%s\" in %s" % [c[0], c[1], want, errs]) \
			.is_true()
	# Each alone (with its companions) still parses.
	for key: String in ["burst_targets", "sanity_scaling", "pierce", "aoe_radius",
			"fuse_seconds"]:
		var effects := {key: GRID_VALUE[key]}
		effects.merge(COMPANIONS.get(key, {}))
		assert_array(_parse(effects, 10.0, 0.0)[1]).override_failure_message(key).is_empty()


# --- 3. mode is read live ----------------------------------------------------------------

func test_mode_follows_effects_changed_after_parse() -> void:
	var p := _parse({"pierce": 1.0}, 10.0, 0.0)
	assert_array(p[1]).is_empty()
	var l: TowerDef.Level = p[0]
	assert_int(l.mode()).is_equal(EffectCatalog.Mode.LINE)
	l.effects.erase("pierce")
	assert_int(l.mode()).is_equal(EffectCatalog.Mode.SINGLE)
	l.effects["aoe_radius"] = 1.5
	assert_int(l.mode()).is_equal(EffectCatalog.Mode.BLAST)
	l.effects["fuse_seconds"] = 1.0
	assert_int(l.mode()).is_equal(EffectCatalog.Mode.FUSE)
	l.damage = 0.0
	assert_int(l.mode()).is_equal(EffectCatalog.Mode.AURA)
	l.effects["summon_max"] = 1.0
	assert_int(l.mode()).is_equal(EffectCatalog.Mode.SUMMON)
