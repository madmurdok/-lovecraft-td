class_name EnemyDef
extends RefCounted
## One enemy type from enemies.json (GDD §7).

const FIELDS := ["name", "hp", "speed", "armor", "leak_damage", "reward", "flying",
	"horror_drain", "traits"]

var id: String
var name: String
var hp: float  ## > 0
var speed: float  ## cells per second, > 0
var armor: float  ## flat damage reduction per hit, >= 0
var leak_damage: int  ## lighthouse HP lost when it leaks, >= 0
var reward: int  ## gold per kill, >= 0
var flying: bool  ## ignores the path, flies straight to the lighthouse
var horror_drain: float  ## sanity per second near towers, >= 0 (GDD §5.3)
## Trait id -> parameters (String -> float), e.g. "pack": {"min": 4, "max": 6}.
## Behaviour is defined by the sim; the loader only checks the shape.
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
	e.reward = r.req_int(obj, "reward", path, 0)
	e.flying = r.opt_bool(obj, "flying", path, false)
	e.horror_drain = r.opt_number(obj, "horror_drain", path, 0.0, 0.0)
	var traits: Variant = r.opt_object(obj, "traits", path)
	if traits != null:
		var tp := ConfigReader.join(path, "traits")
		for trait_id: String in traits:
			var params: Variant = r.as_object(traits[trait_id], ConfigReader.join(tp, trait_id))
			if params != null:
				e.traits[trait_id] = _parse_trait(r, trait_id, params, ConfigReader.join(tp, trait_id))
	return e


static func _parse_trait(r: ConfigReader, trait_id: String, params: Dictionary,
		path: String) -> Dictionary:
	var out := {}
	var is_pack := trait_id == "pack"
	for key: String in params:
		if is_pack and (key == "min" or key == "max"):
			continue
		out[key] = r.as_number(params[key], ConfigReader.join(path, key), 0.0)
	if is_pack:
		var n := r.errors.size()
		var lo := r.req_int(params, "min", path, 1)
		var hi := r.req_int(params, "max", path, 1)
		if r.errors.size() == n and hi < lo:
			r.error(ConfigReader.join(path, "max"), "must be >= min (%d), got %d" % [lo, hi])
		out["min"] = float(lo)
		out["max"] = float(hi)
	return out
