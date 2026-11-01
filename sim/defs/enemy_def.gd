class_name EnemyDef
extends RefCounted
## One enemy type from enemies.json (GDD §7).

const FIELDS := ["name", "hp", "speed", "armor", "leak_damage", "drops", "flying",
	"horror_drain", "traits", "contact_dps"]

var id: String
var name: String
var hp: float  ## > 0
var speed: float  ## cells per second, > 0
var armor: float  ## flat damage reduction per hit, >= 0
var leak_damage: int  ## lighthouse HP lost when it leaks, >= 0
## LT-27 §1.1: relic kind -> integer weight (>= 0, sum > 0) of the one drop rolled per kill;
## kinds are known economy relics, ordered as economy.relics (GameConfig.load_from_dir).
var drops: Dictionary[String, int] = {}
var flying: bool  ## ignores the path, flies straight to the lighthouse
var horror_drain: float  ## sanity per second near towers, >= 0 (GDD §5.3)
## LT-52 (LT-46 §7 Q3): damage per second it deals to an allied unit holding it, >= 0;
## optional in enemies.json, default leak_damage x 10.
var contact_dps: float
## Known traits and their required parameters (schema, not balance).
const TRAITS := {
	# spawns min..max per spawn event (integers >= 1), one by one: member k enters
	# k x spacing_s seconds after the first (LT-63; > 0 and at least one tick)
	"pack": ["min", "max", "spacing_s"],
	"tower_harass": ["stop_seconds", "fire_rate_multiplier", "debuff_seconds"],
	"tower_lift": ["from_wave", "drop_cells", "disable_seconds"],
	"regen": ["hp_percent_per_second"],
}

## Trait id (from TRAITS) -> parameters (String -> float), e.g.
## "pack": {"min": 4, "max": 6, "spacing_s": 0.5}.
var traits: Dictionary = {}


static func parse(r: ConfigReader, id: String, obj: Dictionary, path: String) -> EnemyDef:
	r.check_keys(obj, FIELDS, path)
	var e := EnemyDef.new()
	e.id = id
	e.name = r.req_string(obj, "name", path)
	e.hp = r.req_number(obj, "hp", path, 0.0, INF, true)
	e.speed = r.req_number(obj, "speed", path, 0.0, INF, true)
	e.armor = r.req_number(obj, "armor", path, 0.0)
	e.leak_damage = r.req_int(obj, "leak_damage", path, 0)
	var drops: Variant = r.req_object(obj, "drops", path)
	if drops != null:
		var dp := ConfigReader.join(path, "drops")
		if drops.is_empty():
			r.error(dp, "must not be empty")
		var n := r.errors.size()
		var total := 0
		for kind: Variant in drops:
			var w := r.as_int(drops[kind], ConfigReader.join(dp, str(kind)), 0)
			e.drops[str(kind)] = w
			total += w
		if not drops.is_empty() and r.errors.size() == n and total <= 0:
			r.error(dp, "weights must sum to > 0")
	e.flying = r.opt_bool(obj, "flying", path, false)
	e.horror_drain = r.opt_number(obj, "horror_drain", path, 0.0, 0.0)
	e.contact_dps = r.opt_number(obj, "contact_dps", path, e.leak_damage * 10.0, 0.0)
	var traits: Variant = r.opt_object(obj, "traits", path)
	if traits != null:
		var tp := ConfigReader.join(path, "traits")
		r.check_keys(traits, TRAITS.keys(), tp)
		for trait_id: String in traits:
			if not TRAITS.has(trait_id):
				continue
			var params: Variant = r.as_object(traits[trait_id], ConfigReader.join(tp, trait_id))
			if params != null:
				e.traits[trait_id] = _parse_trait(r, trait_id, params, ConfigReader.join(tp, trait_id))
	return e


static func _parse_trait(r: ConfigReader, trait_id: String, params: Dictionary,
		path: String) -> Dictionary:
	var names: Array = TRAITS[trait_id]
	r.check_keys(params, names, path)
	var out := {}
	if trait_id == "pack":
		var n := r.errors.size()
		var lo := r.req_int(params, "min", path, 1)
		var hi := r.req_int(params, "max", path, 1)
		if r.errors.size() == n and hi < lo:
			r.error(ConfigReader.join(path, "max"), "must be >= min (%d), got %d" % [lo, hi])
		out["min"] = float(lo)
		out["max"] = float(hi)
		n = r.errors.size()
		var spacing := r.req_number(params, "spacing_s", path, 0.0, INF, true)
		if r.errors.size() == n and spacing < SimTime.DT - 1e-9:  # 1e-9: DT written out in JSON (0.0333...) rounds just below DT
			r.error(ConfigReader.join(path, "spacing_s"),
				"must be at least one tick (%s s), got %s" % [SimTime.DT, spacing])
		out["spacing_s"] = spacing
		return out
	for key: String in names:
		out[key] = r.req_number(params, key, path, 0.0)
	return out
