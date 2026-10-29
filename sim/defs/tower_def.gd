class_name TowerDef
extends RefCounted
## One tower from towers.json (GDD §6): L1 and L2 in `levels`, L3 as branch "a" or "b".

const FIELDS := ["name", "kind", "cost", "sanity_cost", "levels", "branches"]
const KINDS: PackedStringArray = ["mundane", "occult"]
const LEVEL_COUNT := 2  ## L1, L2; L3 is a branch
const BRANCH_IDS: PackedStringArray = ["a", "b"]

var id: String
var name: String
var kind: String  ## "mundane" | "occult"
var cost: int  ## gold to build (L1), >= 0
var sanity_cost: float  ## sanity to build (L1), >= 0
var levels: Array[Level] = []
var branches: Dictionary[String, Level] = {}


static func parse(r: ConfigReader, id: String, obj: Dictionary, path: String) -> TowerDef:
	r.check_keys(obj, FIELDS, path)
	var t := TowerDef.new()
	t.id = id
	t.name = r.req_string(obj, "name", path)
	t.kind = r.req_string(obj, "kind", path, KINDS)
	t.cost = r.req_int(obj, "cost", path, 0)
	t.sanity_cost = r.opt_number(obj, "sanity_cost", path, 0.0, 0.0)

	var levels: Variant = r.req_array(obj, "levels", path)
	if levels != null:
		var lp := ConfigReader.join(path, "levels")
		if levels.size() != LEVEL_COUNT:
			r.error(lp, "expected %d levels (L1, L2), got %d" % [LEVEL_COUNT, levels.size()])
		for i in levels.size():
			var ip := ConfigReader.index(lp, i)
			var lv: Variant = r.as_object(levels[i], ip)
			if lv != null:
				t.levels.append(Level.parse(r, lv, ip, i > 0))

	var branches: Variant = r.req_object(obj, "branches", path)
	if branches != null:
		var bp := ConfigReader.join(path, "branches")
		r.check_keys(branches, Array(BRANCH_IDS), bp)
		for b in BRANCH_IDS:
			var bo: Variant = r.req_object(branches, b, bp)
			if bo != null:
				t.branches[b] = Level.parse(r, bo, ConfigReader.join(bp, b), true)
	return t


## Stats of one tower level or L3 branch.
class Level:
	extends RefCounted

	const LEVEL_FIELDS := ["name", "upgrade_cost", "upgrade_sanity_cost", "range", "damage",
		"fire_interval", "sanity_per_cast", "sanity_per_second", "madness_affected",
		"effects"]

	var name: String
	var upgrade_cost: int  ## gold to upgrade into this level; 0 on L1 (use TowerDef.cost)
	var upgrade_sanity_cost: float  ## sanity to upgrade into this level
	var range_cells: float  ## JSON "range"; cells, > 0 (attack range or aura radius)
	var damage: float  ## per hit, >= 0 (0 = support tower)
	var fire_interval: float  ## seconds between shots; required > 0 when damage > 0
	var sanity_per_cast: float  ## sanity drained per shot/cast
	var sanity_per_second: float  ## sanity drained per second while active
	var madness_affected: bool  ## occult: x2 damage and astray shots in madness (GDD §5.4)
	## Branch/level-specific numeric parameters (String -> float), e.g. "slow", "crit_chance".
	var effects: Dictionary = {}

	static func parse(r: ConfigReader, obj: Dictionary, path: String, is_upgrade: bool) -> Level:
		r.check_keys(obj, LEVEL_FIELDS, path)
		var l := Level.new()
		l.name = r.opt_string(obj, "name", path)
		if is_upgrade:
			l.upgrade_cost = r.req_int(obj, "upgrade_cost", path, 0)
			l.upgrade_sanity_cost = r.opt_number(obj, "upgrade_sanity_cost", path, 0.0, 0.0)
		else:
			for key in ["upgrade_cost", "upgrade_sanity_cost"]:
				if obj.has(key):
					r.error(ConfigReader.join(path, key),
						"not allowed on L1 (the tower's cost/sanity_cost is the build price)")
		l.range_cells = r.req_number(obj, "range", path, 0.0, INF, true)
		l.damage = r.opt_number(obj, "damage", path, 0.0, 0.0)
		if l.damage > 0.0:
			l.fire_interval = r.req_number(obj, "fire_interval", path, 0.0, INF, true)
		else:
			l.fire_interval = r.opt_number(obj, "fire_interval", path, 0.0, 0.0, INF, true)
		l.sanity_per_cast = r.opt_number(obj, "sanity_per_cast", path, 0.0, 0.0)
		l.sanity_per_second = r.opt_number(obj, "sanity_per_second", path, 0.0, 0.0)
		l.madness_affected = r.opt_bool(obj, "madness_affected", path, true)
		var effects: Variant = r.opt_object(obj, "effects", path)
		if effects != null:
			var ep := ConfigReader.join(path, "effects")
			for key: String in effects:
				l.effects[key] = r.as_number(effects[key], ConfigReader.join(ep, key), 0.0)
		return l
