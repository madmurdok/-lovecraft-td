class_name EconomyConfig
extends RefCounted
## economy.json (GDD §5.1, §5.2): money ("gold" internally) rules, relics (LT-27 §1.1) and
## lighthouse HP.

const FIELDS := ["starting_gold", "wave_bonus", "sell_refund_ratio", "relics",
	"token_fly_seconds", "ghost_vanish_seconds", "early_night_luck_per_second", "lighthouse"]
const RELIC_FIELDS := ["name", "price"]

var starting_gold: int  ## money at the start, >= 0
var wave_bonus_base: int  ## dawn wage = base + per_wave * wave number
var wave_bonus_per_wave: int
var sell_refund_ratio: float  ## share of total spent refunded on sell, 0..1
## LT-27 §1.1: relic kinds in config order (the order of sale events and HUD rows).
var relics: Array[RelicKind] = []
var token_fly_seconds: float  ## kill -> stash credit of a real token, > 0
var ghost_vanish_seconds: float  ## kill -> a ghost token dissolves; 0 < it < token_fly_seconds
var early_night_luck_per_second: float  ## night luck per whole second left on the day timer
var lighthouse_hp: int  ## >= 1


## One relic kind (LT-27 §1.1): sold by day for a fixed `price` in money.
class RelicKind:
	extends RefCounted

	var id: String
	var name: String  ## non-empty
	var price: int  ## money per relic, >= 0


static func parse(r: ConfigReader, root: Dictionary) -> EconomyConfig:
	r.check_keys(root, FIELDS, "")
	var c := EconomyConfig.new()
	c.starting_gold = r.req_int(root, "starting_gold", "", 0)
	var bonus: Variant = r.req_object(root, "wave_bonus", "")
	if bonus != null:
		r.check_keys(bonus, ["base", "per_wave"], "wave_bonus")
		c.wave_bonus_base = r.req_int(bonus, "base", "wave_bonus", 0)
		c.wave_bonus_per_wave = r.req_int(bonus, "per_wave", "wave_bonus", 0)
	c.sell_refund_ratio = r.req_number(root, "sell_refund_ratio", "", 0.0, 1.0)
	var relics: Variant = r.req_object(root, "relics", "")
	if relics != null:
		if relics.is_empty():
			r.error("relics", "must not be empty")
		for id: Variant in relics:
			var rp := ConfigReader.join("relics", str(id))
			if not r.check_id(str(id), rp):
				continue
			var ro: Variant = r.as_object(relics[id], rp)
			if ro == null:
				continue
			r.check_keys(ro, RELIC_FIELDS, rp)
			var k := RelicKind.new()
			k.id = str(id)
			k.name = r.req_string(ro, "name", rp)
			k.price = r.req_int(ro, "price", rp, 0)
			c.relics.append(k)
	c.token_fly_seconds = r.req_number(root, "token_fly_seconds", "", 0.0, INF, true)
	var n := r.errors.size()
	c.ghost_vanish_seconds = r.req_number(root, "ghost_vanish_seconds", "", 0.0, INF, true)
	if r.errors.size() == n and c.ghost_vanish_seconds >= c.token_fly_seconds:
		r.error("ghost_vanish_seconds", "must be < token_fly_seconds (%s), got %s"
			% [ConfigReader.fmt(c.token_fly_seconds), ConfigReader.fmt(c.ghost_vanish_seconds)])
	c.early_night_luck_per_second = r.req_number(root, "early_night_luck_per_second", "", 0.0)
	var lighthouse: Variant = r.req_object(root, "lighthouse", "")
	if lighthouse != null:
		r.check_keys(lighthouse, ["hp"], "lighthouse")
		c.lighthouse_hp = r.req_int(lighthouse, "hp", "lighthouse", 1)
	return c


## The relic kind `id`, or null when unknown.
func relic(id: String) -> RelicKind:
	for k in relics:
		if k.id == id:
			return k
	return null


## Relic kind ids in config order.
func relic_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in relics:
		out.append(k.id)
	return out
