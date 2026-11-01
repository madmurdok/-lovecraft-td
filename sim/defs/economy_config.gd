class_name EconomyConfig
extends RefCounted
## economy.json (GDD §5.1, §5.2): money ("gold" internally) rules, relics (LT-27 §1.1),
## lighthouse HP, its beam (LT-26 §1.3), lamp oil and the flare (LT-30 §1.3).

const FIELDS := ["starting_gold", "wave_bonus", "sell_refund_ratio", "relics",
	"token_fly_seconds", "ghost_vanish_seconds", "early_night_luck_per_second", "lighthouse"]
const RELIC_FIELDS := ["name", "price"]
const LIGHTHOUSE_FIELDS := ["hp", "beam", "oil", "flare"]
const BEAM_FIELDS := ["pattern", "turn_t", "reach_cells", "half_width_ratio", "sweep_edges",
	"levels", "mundane", "occult", "enemy"]
const BEAM_PATTERNS: PackedStringArray = ["rotate", "sweep"]
## Beam counts the trig-free direction set supports (LT-26 §1.1).
const BEAM_COUNTS: Array[int] = [1, 2, 4, 8]
const OIL_FIELDS := ["price", "start", "cap"]
const FLARE_FIELDS := ["cost_oil", "cooldown_seconds", "seconds", "radius_cells",
	"enemy_speed_mult"]

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
var beam: BeamConfig  ## lighthouse.beam (LT-26 §1.3), required
var oil: OilConfig  ## lighthouse.oil (LT-30 §1.2), null when absent
var flare: FlareConfig  ## lighthouse.flare (LT-30 §1.1), null when absent (needs `oil`)


## One relic kind (LT-27 §1.1): sold by day for a fixed `price` in money.
class RelicKind:
	extends RefCounted

	var id: String
	var name: String  ## non-empty
	var price: int  ## money per relic, >= 0


## The lighthouse beam (LT-26 §1.1, §1.3; LT-30 §2: occult has power_mult only).
class BeamConfig:
	extends RefCounted

	var pattern: String  ## "rotate" | "sweep"
	## Tangent of half the per-tick turn: rotation (c, s) = ((1 - t²), 2t) / (1 + t²).
	var turn_t: float
	var reach_cells: float  ## > 0
	var half_width_ratio: float  ## tan of the cone's half angle, > 0
	## "sweep" only: the land arc, from sweep_edges[0] counter-clockwise (positive turn)
	## to sweep_edges[1]; each [x, y], 64-bit. Empty for "rotate".
	var sweep_edges: Array = []
	var levels: Array[BeamLevel] = []  ## L1 first; beams non-decreasing
	var mundane_fire_interval_mult: float  ## > 0, lit mundane cooldown multiplier
	var mundane_ignore_miss: bool  ## lit mundane shots never miss
	var occult_power_mult: float  ## > 0, lit occult damage / aura strength multiplier
	var cancel_madness_buff: bool  ## lit enemies skip the madness buff (LT-26 D4)


class BeamLevel:
	extends RefCounted

	var beams: int  ## 1, 2, 4 or 8
	var upgrade_cost: int  ## money to reach this level; 0 for L1, >= 1 from L2


## Lamp oil (LT-30 §1.2): a stock bought by day, used only by the flare.
class OilConfig:
	extends RefCounted

	var price: int  ## money per unit, >= 1
	var start: int  ## stock at the start of the run, 0..cap
	var cap: int  ## >= flare.cost_oil (>= 1)


## The flare (LT-30 §1.1, LT-57): a night-only command paid with oil; while it burns,
## everything within radius_cells of the lighthouse is lit, in every direction.
class FlareConfig:
	extends RefCounted

	var cost_oil: int  ## >= 1
	var cooldown_seconds: float  ## > seconds, from the activation
	var seconds: float  ## > 0
	## LT-57: the lit circle's radius in cells by lighthouse level (L1 first), one entry per
	## beam.levels, each in [0, beam.reach_cells] (0: the flare lights nothing).
	var radius_cells: Array[float] = []
	var enemy_speed_mult: float  ## (0, 1], lit enemies while the flare burns


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
		r.check_keys(lighthouse, LIGHTHOUSE_FIELDS, "lighthouse")
		c.lighthouse_hp = r.req_int(lighthouse, "hp", "lighthouse", 1)
		var bo: Variant = r.req_object(lighthouse, "beam", "lighthouse")
		if bo != null:
			c.beam = _parse_beam(r, bo, "lighthouse.beam")
		if lighthouse.has("flare"):
			var fo: Variant = r.as_object(lighthouse["flare"], "lighthouse.flare")
			if fo != null:
				c.flare = _parse_flare(r, fo, "lighthouse.flare", c.beam)
		if lighthouse.has("oil"):
			var oo: Variant = r.as_object(lighthouse["oil"], "lighthouse.oil")
			if oo != null:
				c.oil = _parse_oil(r, oo, "lighthouse.oil", c.flare)
		elif lighthouse.has("flare"):
			r.error("lighthouse.flare", "requires lighthouse.oil")
	return c


static func _parse_beam(r: ConfigReader, o: Dictionary, path: String) -> BeamConfig:
	r.check_keys(o, BEAM_FIELDS, path)
	var b := BeamConfig.new()
	b.pattern = r.req_string(o, "pattern", path, BEAM_PATTERNS)
	b.turn_t = r.req_number(o, "turn_t", path, -1.0, 1.0)
	b.reach_cells = r.req_number(o, "reach_cells", path, 0.0, INF, true)
	b.half_width_ratio = r.req_number(o, "half_width_ratio", path, 0.0, INF, true)
	if b.pattern == "sweep" or o.has("sweep_edges"):
		b.sweep_edges = _parse_edges(r, o, path)
	var levels: Variant = r.req_array(o, "levels", path)
	if levels != null:
		if levels.is_empty():
			r.error(ConfigReader.join(path, "levels"), "must not be empty")
		var prev := 0
		for i in levels.size():
			var lp := ConfigReader.index(ConfigReader.join(path, "levels"), i)
			var lo: Variant = r.as_object(levels[i], lp)
			if lo == null:
				continue
			r.check_keys(lo, ["beams"] if i == 0 else ["beams", "upgrade_cost"], lp)
			var lv := BeamLevel.new()
			lv.beams = r.req_int(lo, "beams", lp, 1, 8)
			if lv.beams not in BEAM_COUNTS:
				r.error(ConfigReader.join(lp, "beams"), "must be one of [1, 2, 4, 8], got %d"
					% lv.beams)
			elif lv.beams < prev:
				r.error(ConfigReader.join(lp, "beams"), "must not decrease (previous level %d)"
					% prev)
			prev = maxi(prev, lv.beams)
			if i > 0:
				lv.upgrade_cost = r.req_int(lo, "upgrade_cost", lp, 1)
			b.levels.append(lv)
	var mp := ConfigReader.join(path, "mundane")
	var mo: Variant = r.req_object(o, "mundane", path)
	if mo != null:
		r.check_keys(mo, ["fire_interval_mult", "ignore_miss"], mp)
		b.mundane_fire_interval_mult = r.req_number(mo, "fire_interval_mult", mp, 0.0, INF, true)
		b.mundane_ignore_miss = r.req_bool(mo, "ignore_miss", mp)
	var op := ConfigReader.join(path, "occult")
	var oo: Variant = r.req_object(o, "occult", path)
	if oo != null:
		r.check_keys(oo, ["power_mult"], op)
		b.occult_power_mult = r.req_number(oo, "power_mult", op, 0.0, INF, true)
	var ep := ConfigReader.join(path, "enemy")
	var eo: Variant = r.req_object(o, "enemy", path)
	if eo != null:
		r.check_keys(eo, ["cancel_madness_buff"], ep)
		b.cancel_madness_buff = r.req_bool(eo, "cancel_madness_buff", ep)
	return b


## sweep_edges: two non-zero [x, y] vectors with edges[0] x edges[1] > 0 (an arc under 180°
## from edges[0] counter-clockwise to edges[1]).
static func _parse_edges(r: ConfigReader, o: Dictionary, path: String) -> Array:
	var sp := ConfigReader.join(path, "sweep_edges")
	var arr: Variant = r.req_array(o, "sweep_edges", path)
	if arr == null:
		return []
	if arr.size() != 2:
		r.error(sp, "expected 2 edge vectors, got %d" % arr.size())
		return []
	var out := []
	for i in 2:
		var ip := ConfigReader.index(sp, i)
		var v: Variant = r.as_array(arr[i], ip)
		if v == null:
			return []
		if v.size() != 2:
			r.error(ip, "expected [x, y], got %d values" % v.size())
			return []
		var n := r.errors.size()
		var x := r.as_number(v[0], ConfigReader.index(ip, 0))
		var y := r.as_number(v[1], ConfigReader.index(ip, 1))
		if r.errors.size() > n:
			return []
		if x == 0.0 and y == 0.0:
			r.error(ip, "must not be the zero vector")
			return []
		out.append([x, y])
	if out[0][0] * out[1][1] - out[0][1] * out[1][0] <= 0.0:
		r.error(sp, "edges[1] must lie counter-clockwise of edges[0], under 180°")
		return []
	return out


static func _parse_flare(r: ConfigReader, o: Dictionary, path: String,
		beam: BeamConfig) -> FlareConfig:
	r.check_keys(o, FLARE_FIELDS, path)
	var f := FlareConfig.new()
	f.cost_oil = r.req_int(o, "cost_oil", path, 1)
	f.seconds = r.req_number(o, "seconds", path, 0.0, INF, true)
	var n := r.errors.size()
	f.cooldown_seconds = r.req_number(o, "cooldown_seconds", path, 0.0, INF, true)
	if r.errors.size() == n and f.cooldown_seconds <= f.seconds:
		r.error(ConfigReader.join(path, "cooldown_seconds"), "must be > seconds (%s), got %s"
			% [ConfigReader.fmt(f.seconds), ConfigReader.fmt(f.cooldown_seconds)])
	f.radius_cells = _parse_radius_cells(r, o, path, beam)
	f.enemy_speed_mult = r.req_number(o, "enemy_speed_mult", path, 0.0, 1.0, true)
	return f


## LT-57: flare.radius_cells, one number per beam level in [0, reach_cells]. Without a
## parsed beam only the range check against 0 runs (the beam's own errors are reported).
static func _parse_radius_cells(r: ConfigReader, o: Dictionary, path: String,
		beam: BeamConfig) -> Array[float]:
	var out: Array[float] = []
	var rp := ConfigReader.join(path, "radius_cells")
	var arr: Variant = r.req_array(o, "radius_cells", path)
	if arr == null:
		return out
	var reach := beam.reach_cells if beam != null and beam.reach_cells > 0.0 else INF
	if beam != null and beam.levels.size() > 0 and arr.size() != beam.levels.size():
		r.error(rp, "must have one entry per beam level (%d), got %d"
			% [beam.levels.size(), arr.size()])
		return out
	for i in arr.size():
		out.append(r.as_number(arr[i], ConfigReader.index(rp, i), 0.0, reach))
	return out


static func _parse_oil(r: ConfigReader, o: Dictionary, path: String,
		flare: FlareConfig) -> OilConfig:
	r.check_keys(o, OIL_FIELDS, path)
	var c := OilConfig.new()
	c.price = r.req_int(o, "price", path, 1)
	var min_cap := flare.cost_oil if flare != null and flare.cost_oil >= 1 else 1
	c.cap = r.req_int(o, "cap", path, min_cap)
	c.start = r.req_int(o, "start", path, 0, maxi(c.cap, 0))
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
