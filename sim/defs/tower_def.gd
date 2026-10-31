class_name TowerDef
extends RefCounted
## One tower from towers.json (GDD §6): L1 and L2 in `levels`, L3 as branch "a" or "b".

const FIELDS := ["name", "role", "kind", "cost", "levels", "branches"]
const KINDS: PackedStringArray = ["mundane", "occult"]
const LEVEL_COUNT := 2  ## L1, L2; L3 is a branch
const BRANCH_IDS: PackedStringArray = ["a", "b"]
## Max length of a `role` line (tower or branch), after strip_edges (LT-24 §1).
const ROLE_MAX_CHARS := 24

var id: String
var name: String
## One-line player-facing role (no numbers); "" when absent (LT-24 §1).
var role: String
var kind: String  ## "mundane" | "occult"
var cost: int  ## gold to build (L1), >= 0
var levels: Array[Level] = []
var branches: Dictionary[String, Level] = {}


static func parse(r: ConfigReader, id: String, obj: Dictionary, path: String) -> TowerDef:
	r.check_keys(obj, FIELDS, path)
	var t := TowerDef.new()
	t.id = id
	t.name = r.req_string(obj, "name", path)
	t.role = parse_role(r, obj, path)
	t.kind = r.req_string(obj, "kind", path, KINDS)
	t.cost = r.req_int(obj, "cost", path, 0)

	var levels: Variant = r.req_array(obj, "levels", path)
	if levels != null:
		var lp := ConfigReader.join(path, "levels")
		if levels.size() != LEVEL_COUNT:
			r.error(lp, "expected %d levels (L1, L2), got %d" % [LEVEL_COUNT, levels.size()])
		for i in levels.size():
			var ip := ConfigReader.index(lp, i)
			var lv: Variant = r.as_object(levels[i], ip)
			if lv != null:
				t.levels.append(Level.parse(r, lv, ip, i > 0, t.kind, false))

	var branches: Variant = r.req_object(obj, "branches", path)
	if branches != null:
		var bp := ConfigReader.join(path, "branches")
		r.check_keys(branches, Array(BRANCH_IDS), bp)
		for b in BRANCH_IDS:
			var bo: Variant = r.req_object(branches, b, bp)
			if bo != null:
				t.branches[b] = Level.parse(r, bo, ConfigReader.join(bp, b), true, t.kind, true)
	return t


## Optional `role` of `obj`: a non-blank string of at most ROLE_MAX_CHARS characters
## (stripped); "" when absent or rejected.
static func parse_role(r: ConfigReader, obj: Dictionary, path: String) -> String:
	if not obj.has("role"):
		return ""
	var rp := ConfigReader.join(path, "role")
	if typeof(obj["role"]) != TYPE_STRING:
		r.error(rp, "expected string, got %s" % ConfigReader.type_name(obj["role"]))
		return ""
	var s: String = (obj["role"] as String).strip_edges()
	if s.is_empty():
		r.error(rp, "must not be empty")
		return ""
	if s.length() > ROLE_MAX_CHARS:
		r.error(rp, "must be at most %d characters, got %d" % [ROLE_MAX_CHARS, s.length()])
		return ""
	return s


## Stats of one tower level or L3 branch.
class Level:
	extends RefCounted

	const LEVEL_FIELDS := ["name", "role", "upgrade_cost", "range", "damage",
		"fire_interval", "sanity_reserve", "madness_affected", "effects"]

	var name: String
	var role: String  ## branches only (L3); "" on levels and when absent (LT-24 §1)
	var upgrade_cost: int  ## gold to upgrade into this level; 0 on L1 (use TowerDef.cost)
	var range_cells: float  ## JSON "range"; cells, > 0 (attack range or aura radius)
	var damage: float  ## per hit, >= 0 (0 = support tower)
	var fire_interval: float  ## seconds between shots; required > 0 when damage > 0
	## Total sanity cap this tower holds while it stands at this level (LT-23 §1), not added
	## to lower levels; >= 0, default 0, > 0 only on occult towers.
	var sanity_reserve: float
	## x2 damage and astray shots in madness (GDD §5.4). Defaults to kind == "occult";
	## only occult towers may set it true (Pure Rite sets false).
	var madness_affected: bool
	## Known effect parameters (schema, not balance): key -> max value (min is 0).
	const EFFECTS := {
		"crit_chance": 1.0, "crit_multiplier": INF, "shooters": INF, "pierce": INF,
		"bleed_dps": INF, "bleed_seconds": INF, "pull_cells": INF, "slow": 1.0,
		"damage_taken_multiplier": INF, "strip_armor": INF, "aoe_radius": INF,
	}

	## Config keys (EFFECTS or stats) that parse but the sim does not apply yet (LT-24
	## Decision 1). The UI marks them "(coming soon)" and bots skip branches using them;
	## the task that wires a key removes it from here.
	const PENDING: PackedStringArray = ["crit_chance", "crit_multiplier", "shooters",
		"bleed_dps", "bleed_seconds", "pull_cells", "strip_armor"]

	## Branch/level-specific numeric parameters (String -> float), keys from EFFECTS.
	var effects: Dictionary = {}

	## True when any PENDING effect key is non-zero on this level.
	func has_pending() -> bool:
		for key in PENDING:
			if effects.get(key, 0.0) != 0.0:
				return true
		return false

	## `is_branch`: an L3 branch, the only place `role` is allowed.
	static func parse(r: ConfigReader, obj: Dictionary, path: String, is_upgrade: bool,
			kind: String, is_branch: bool) -> Level:
		r.check_keys(obj, LEVEL_FIELDS, path)
		var l := Level.new()
		l.name = r.opt_string(obj, "name", path)
		if is_branch:
			l.role = TowerDef.parse_role(r, obj, path)
		elif obj.has("role"):
			r.error(ConfigReader.join(path, "role"),
				"not allowed on levels (only on the tower and its branches)")
		if is_upgrade:
			l.upgrade_cost = r.req_int(obj, "upgrade_cost", path, 0)
		elif obj.has("upgrade_cost"):
			r.error(ConfigReader.join(path, "upgrade_cost"),
				"not allowed on L1 (the tower's cost is the build price)")
		l.range_cells = r.req_number(obj, "range", path, 0.0, INF, true)
		l.damage = r.opt_number(obj, "damage", path, 0.0, 0.0)
		if l.damage > 0.0:
			l.fire_interval = r.req_number(obj, "fire_interval", path, 0.0, INF, true)
		else:
			l.fire_interval = r.opt_number(obj, "fire_interval", path, 0.0, 0.0, INF, true)
		var occult := kind == "occult"
		l.sanity_reserve = r.opt_number(obj, "sanity_reserve", path, 0.0, 0.0)
		if l.sanity_reserve > 0.0 and not occult:
			r.error(ConfigReader.join(path, "sanity_reserve"),
				"only occult towers reserve sanity")
			l.sanity_reserve = 0.0
		l.madness_affected = r.opt_bool(obj, "madness_affected", path, occult)
		if l.madness_affected and not occult and obj.has("madness_affected"):
			r.error(ConfigReader.join(path, "madness_affected"),
				"only occult towers can be affected by madness")
			l.madness_affected = false
		var effects: Variant = r.opt_object(obj, "effects", path)
		if effects != null:
			var ep := ConfigReader.join(path, "effects")
			r.check_keys(effects, EFFECTS.keys(), ep)
			for key: String in effects:
				if EFFECTS.has(key):
					l.effects[key] = r.as_number(effects[key], ConfigReader.join(ep, key),
						0.0, EFFECTS[key])
		return l
