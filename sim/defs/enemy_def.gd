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
## kinds are known economy relics, ordered as economy.relics (GameConfig.from_dicts).
var drops: Dictionary[String, int] = {}
var flying: bool  ## ignores the path, flies straight to the lighthouse
var horror_drain: float  ## sanity per second near towers, >= 0 (GDD §5.3)
## LT-52 (LT-46 §7 Q3): damage per second it deals to an allied unit holding it, >= 0;
## optional in enemies.json, default leak_damage x 10.
var contact_dps: float
## Trait id (TraitCatalog) -> parameters (String -> float), e.g.
## "pack": {"min": 4, "max": 6, "spacing_s": 0.5}. JSON key order.
var traits: Dictionary = {}
## LT-106 T3: hook dispatch data, built once at parse from `traits` in TraitCatalog
## order (never the JSON order); pending and hook-less traits are left out. `hooks` is the OR
## of hook_traits' masks; hook_params[i] is the same Dictionary as traits[hook_traits[i].id()].
var hooks := 0
var hook_traits: Array[EnemyTrait] = []
var hook_params: Array[Dictionary] = []


## True when this enemy carries a pending trait (LT-97: data the sim does not apply yet).
func has_pending_traits() -> bool:
	for trait_id: String in traits:
		if TraitCatalog.get_trait(trait_id).pending():
			return true
	return false


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
		r.check_keys(traits, TraitCatalog.ids(), tp)
		for trait_id: String in traits:
			if not TraitCatalog.has(trait_id):
				continue
			var params: Variant = r.as_object(traits[trait_id], ConfigReader.join(tp, trait_id))
			if params != null:
				e.traits[trait_id] = _parse_trait(r, trait_id, params, ConfigReader.join(tp, trait_id))
	e.build_hooks()
	return e


static func _parse_trait(r: ConfigReader, trait_id: String, params: Dictionary,
		path: String) -> Dictionary:
	var tr := TraitCatalog.get_trait(trait_id)
	r.check_keys(params, Array(tr.params()), path)
	return tr.parse_params(r, params, path)


## LT-106 T3: (re)builds hook_traits / hook_params / hooks from `traits`, catalog order
## (parse calls it; a test that edits `traits` by hand calls it again).
func build_hooks() -> void:
	hooks = 0
	hook_traits.clear()
	hook_params.clear()
	for tr: EnemyTrait in TraitCatalog.all():
		if tr.pending() or tr.hooks() == 0 or not traits.has(tr.id()):
			continue
		hooks |= tr.hooks()
		hook_traits.append(tr)
		hook_params.append(traits[tr.id()])
