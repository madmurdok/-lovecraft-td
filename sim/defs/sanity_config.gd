class_name SanityConfig
extends RefCounted
## sanity.json (GDD §5.3, §5.4): pool, regen, thresholds, hallucinations, madness.
## Tower-specific drains live on the tower (towers.json: sanity_cost,
## upgrade_sanity_cost, sanity_per_cast, sanity_per_second); horror drain per
## second lives on the enemy (enemies.json: horror_drain).

const FIELDS := ["max", "start", "regen", "horror_radius_cells", "thresholds", "madness"]
## Highest first. A state applies while sanity >= its `min` and below the previous state's.
const STATES: PackedStringArray = ["lucid", "whispers", "fraying", "madness"]

var max_sanity: float  ## > 0
var start: float  ## 0..max
var regen_between_waves: float  ## >= 0
var regen_mundane_kill: float  ## per kill by a mundane damage tower, >= 0
var horror_radius_cells: float  ## horror drain applies within this many cells of a tower
var thresholds: Dictionary[String, Threshold] = {}  ## keyed by STATES
var madness: Madness


static func parse(r: ConfigReader, root: Dictionary) -> SanityConfig:
	r.check_keys(root, FIELDS, "")
	var c := SanityConfig.new()
	c.max_sanity = r.req_number(root, "max", "", 0.0, INF, true)
	var top := c.max_sanity if c.max_sanity > 0.0 else INF
	c.start = r.req_number(root, "start", "", 0.0, top)
	var regen: Variant = r.req_object(root, "regen", "")
	if regen != null:
		r.check_keys(regen, ["between_waves", "mundane_kill"], "regen")
		c.regen_between_waves = r.req_number(regen, "between_waves", "regen", 0.0)
		c.regen_mundane_kill = r.req_number(regen, "mundane_kill", "regen", 0.0)
	c.horror_radius_cells = r.req_number(root, "horror_radius_cells", "", 0.0)

	var thresholds: Variant = r.req_object(root, "thresholds", "")
	if thresholds != null:
		r.check_keys(thresholds, Array(STATES), "thresholds")
		for state in STATES:
			var to: Variant = r.req_object(thresholds, state, "thresholds")
			if to != null:
				c.thresholds[state] = Threshold.parse(r, to, ConfigReader.join("thresholds", state), top)
		_check_threshold_order(r, thresholds, c, top)

	var madness: Variant = r.req_object(root, "madness", "")
	if madness != null:
		c.madness = Madness.parse(r, madness, "madness", top)
	return c


## Mins must strictly decrease lucid > whispers > fraying > madness, and madness starts at 0.
## Compares only mins that parsed cleanly; the others already reported an error.
static func _check_threshold_order(r: ConfigReader, raw: Dictionary, c: SanityConfig,
		top: float) -> void:
	var valid: Dictionary[String, float] = {}
	for state in STATES:
		if not c.thresholds.has(state):
			continue
		var v: Variant = raw[state].get("min")
		if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and v >= 0.0 and v <= top:
			valid[state] = float(v)
	for i in range(1, STATES.size()):
		var hi_state := STATES[i - 1]
		var lo_state := STATES[i]
		if valid.has(hi_state) and valid.has(lo_state) and valid[lo_state] >= valid[hi_state]:
			r.error("thresholds.%s.min" % lo_state, "must be < thresholds.%s.min (%s), got %s"
				% [hi_state, ConfigReader.fmt(valid[hi_state]), ConfigReader.fmt(valid[lo_state])])
	if valid.has("madness") and valid["madness"] != 0.0:
		r.error("thresholds.madness.min", "must be 0, got %s" % ConfigReader.fmt(valid["madness"]))


class Threshold:
	extends RefCounted

	const THRESHOLD_FIELDS := ["min", "fake_spawn_interval", "miss_chance"]

	var min_sanity: float  ## JSON "min": lowest sanity in this state
	var fake_spawn_interval: float  ## seconds between fake enemies; 0 = none
	var miss_chance: float  ## tower miss chance, 0..1

	static func parse(r: ConfigReader, obj: Dictionary, path: String, top: float) -> Threshold:
		r.check_keys(obj, THRESHOLD_FIELDS, path)
		var t := Threshold.new()
		t.min_sanity = r.req_number(obj, "min", path, 0.0, top)
		t.fake_spawn_interval = r.opt_number(obj, "fake_spawn_interval", path, 0.0, 0.0)
		t.miss_chance = r.opt_number(obj, "miss_chance", path, 0.0, 0.0, 1.0)
		return t


class Madness:
	extends RefCounted

	const MADNESS_FIELDS := ["damage_multiplier", "shot_split", "exit_rule", "restore_sanity",
		"buyout_cost"]
	const SPLIT_FIELDS := ["real", "fake", "empty"]
	const EXIT_RULES: PackedStringArray = ["permanent", "buyout", "auto_restore"]
	const SPLIT_TOLERANCE := 1e-6

	var damage_multiplier: float  ## occult damage in madness, > 0
	var shot_real: float  ## share of astray shots hitting a random real enemy in range
	var shot_fake: float  ## ... a fake enemy
	var shot_empty: float  ## ... an empty cell; the three sum to 1
	var exit_rule: String  ## "permanent" | "buyout" | "auto_restore"
	var restore_sanity: float  ## sanity after buyout / auto restore, 0..max
	var buyout_cost: int  ## gold, >= 0

	static func parse(r: ConfigReader, obj: Dictionary, path: String, top: float) -> Madness:
		r.check_keys(obj, MADNESS_FIELDS, path)
		var m := Madness.new()
		m.damage_multiplier = r.req_number(obj, "damage_multiplier", path, 0.0, INF, true)
		var split: Variant = r.req_object(obj, "shot_split", path)
		if split != null:
			var sp := ConfigReader.join(path, "shot_split")
			r.check_keys(split, SPLIT_FIELDS, sp)
			var n := r.errors.size()
			m.shot_real = r.req_number(split, "real", sp, 0.0, 1.0)
			m.shot_fake = r.req_number(split, "fake", sp, 0.0, 1.0)
			m.shot_empty = r.req_number(split, "empty", sp, 0.0, 1.0)
			var total := m.shot_real + m.shot_fake + m.shot_empty
			if r.errors.size() == n and absf(total - 1.0) > SPLIT_TOLERANCE:
				r.error(sp, "real + fake + empty must sum to 1, got %s" % ConfigReader.fmt(total))
		m.exit_rule = r.req_string(obj, "exit_rule", path, EXIT_RULES)
		var n_restore := r.errors.size()
		m.restore_sanity = r.req_number(obj, "restore_sanity", path, 0.0, top)
		# Restoring to 0 would leave the player in madness: buyout would only take gold.
		if r.errors.size() == n_restore and m.exit_rule != "permanent" and m.restore_sanity <= 0.0:
			r.error(ConfigReader.join(path, "restore_sanity"),
				"must be > 0 when exit_rule is %s, got %s"
				% [m.exit_rule, ConfigReader.fmt(m.restore_sanity)])
		m.buyout_cost = r.req_int(obj, "buyout_cost", path, 0)
		return m
