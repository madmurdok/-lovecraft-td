class_name MapGenParams
extends RefCounted
## LT-130: the map generator's knobs and the LT-18 §8 metric thresholds. Code defaults (owner
## Q3: no data/ file in P1); the report tool overrides them with from_dict. All integers but
## tower_range. Defaults = the p1_small preset (owner Q1); p1_large is the 32 x 18 variant.

## Every overridable field, in a fixed order (from_dict / to_dict never iterate a Dictionary).
const KEYS: PackedStringArray = [
	"grid_kind", "width", "height", "entries_min", "entries_max", "sea_min", "sea_max",
	"funnel_steps", "waypoint_jitter", "wide_pct", "loops_min", "loops_max", "pockets_min",
	"pockets_max", "pocket_len_min", "pocket_len_max", "pocket_sea_steps", "island_min",
	"island_max", "island_seed_div", "attempt_cap", "tower_range", "choke_k", "choke_e",
	"c1_m", "c1_s", "c2_g", "floor_cells", "c3_share_pct", "c4_lmin", "c4_lmax",
	"c4_ratio_pct", "c5_d", "c6_extra", "c7_hud_rows", "c7_l_cover",
]

## Knobs that are counts, distances or thresholds: a negative value has no meaning (and a
## negative waypoint_jitter would draw randi_range(j, -j)).
const NON_NEGATIVE: PackedStringArray = [
	"waypoint_jitter", "pocket_sea_steps", "choke_k", "choke_e", "c1_m", "c1_s", "c2_g",
	"floor_cells", "c5_d", "c6_extra", "c7_hud_rows", "c7_l_cover",
]

# --- board --------------------------------------------------------------------------------
var grid_kind := "hex"  ## a GridFactory kind; "square" works too (everything is GridTopology)
var width := 24
var height := 16
var entries_min := 1
var entries_max := 3

# --- generator steps (LT-130 §3) ----------------------------------------------------------
var sea_min := 1  ## sea band depth per text row, drawn in [sea_min, sea_max]
var sea_max := 2
var funnel_steps := 7  ## L -> F trunk length in steps (floor_cells + 1; S24: 9 gave a trunk share near the C3 cap)
var waypoint_jitter := 3  ## rows of jitter around the entry-to-F midpoint
var wide_pct := 30  ## chance (percent) that a carve step is 2 cells wide
var loops_min := 1
var loops_max := 2
var pockets_min := 1
var pockets_max := 3
var pocket_len_min := 2
var pocket_len_max := 6
var pocket_sea_steps := 4  ## a pocket mouth is within this many steps of the sea
var island_min := 4  ## land components smaller than this become ROCK
var island_max := 12  ## land components larger than this are split
var island_seed_div := 8  ## a split uses ceil(size / island_seed_div) seed cells
var attempt_cap := 50

# --- metric (LT-18 §8) --------------------------------------------------------------------
var tower_range := 3.0  ## R: the rifleman L1 range in cells
var choke_k := 3  ## K: buildable cells near a chokepoint ...
var choke_e := 5  ## E: ... each seeing at least this many route cells
var c1_m := 2  ## M: spaced chokepoints per route
var c1_s := 6  ## S: their spacing in route cells
var c2_g := 8  ## G: longest blind stretch
var floor_cells := 6  ## flood floor in route cells from L (LT-18 §6.2, §13)
var c3_share_pct := 50  ## max share of route cells common to every route
var c4_lmin := 20  ## route length bounds, in steps
var c4_lmax := 40
var c4_ratio_pct := 140  ## longest * 100 <= shortest * c4_ratio_pct
var c5_d := 4  ## D: detour around one barricade, in cells
var c6_extra := 3  ## some route cell at cost >= floor_cells + c6_extra cells
var c7_hud_rows := 0  ## P1 proxy for LT-64: no ISLAND in the top text rows ...
var c7_l_cover := 1  ## ... nor within this many steps of L


## Owner Q1 (a): 24 x 16 hex, 1-3 entries (today's board width).
static func p1_small() -> MapGenParams:
	return MapGenParams.new()


## Owner Q1 (c): 32 x 18 hex, 1-4 entries (the full LT-18 §2 range).
static func p1_large() -> MapGenParams:
	var p := MapGenParams.new()
	p.width = 32
	p.height = 18
	p.entries_max = 4
	return p


## A copy of `base` (p1_small when null) with the keys of `d` applied; unknown keys and wrong
## types are errors. Returns {"params": MapGenParams or null, "errors": PackedStringArray}.
static func from_dict(d: Dictionary, base: MapGenParams = null) -> Dictionary:
	var p := MapGenParams.new()
	if base != null:
		for key in KEYS:
			p.set(key, base.get(key))
	var errors := PackedStringArray()
	var unknown := PackedStringArray()
	for key: Variant in d.keys():
		if not (key is String) or not KEYS.has(key):
			unknown.append(str(key))
	unknown.sort()
	for key in unknown:
		errors.append("unknown key \"%s\"" % key)
	for key in KEYS:
		if not d.has(key):
			continue
		var v: Variant = d[key]
		var want: Variant = p.get(key)
		if want is String:
			if v is String:
				p.set(key, v)
			else:
				errors.append("%s: expected a string" % key)
		elif want is float:
			if v is float or v is int:
				p.set(key, float(v))
			else:
				errors.append("%s: expected a number" % key)
		elif v is int:
			p.set(key, v)
		elif v is float and float(v) == floorf(v) and absf(v) < 1e15:
			p.set(key, int(v))
		else:
			errors.append("%s: expected an integer" % key)
	if errors.is_empty():
		errors.append_array(p.check())
	return {"params": p if errors.is_empty() else null, "errors": errors}


## Every knob by name, in KEYS order (the tool prints / saves it).
func to_dict() -> Dictionary:
	var out := {}
	for key in KEYS:
		out[key] = get(key)
	return out


## Range errors that would crash the generator or make it meaningless (empty when fine);
## MapGenerator.generate refuses params with any.
func check() -> PackedStringArray:
	var out := PackedStringArray()
	if GridFactory.make(grid_kind, 1, 1) == null:
		out.append("grid_kind: unknown grid \"%s\"" % grid_kind)
	if width < 8 or height < 4:
		out.append("width x height: at least 8 x 4")
	_check_range(out, "entries", entries_min, entries_max, 1)
	_check_range(out, "sea", sea_min, sea_max, 1)
	_check_range(out, "loops", loops_min, loops_max, 0)
	_check_range(out, "pockets", pockets_min, pockets_max, 0)
	_check_range(out, "pocket_len", pocket_len_min, pocket_len_max, 1)
	_check_range(out, "island", island_min, island_max, 1)
	if entries_max > height:
		out.append("entries_max: at most height (one band per entry)")
	if sea_max > width - 6:
		out.append("sea_max: at most width - 6 (entries and the funnel east of L)")
	if funnel_steps < 1 or island_seed_div < 1 or attempt_cap < 1:
		out.append("funnel_steps, island_seed_div, attempt_cap: at least 1")
	if attempt_cap > MapRng.ATTEMPT_STRIDE:
		out.append("attempt_cap: at most %d (attempt seeds of two map seeds would collide)"
			% MapRng.ATTEMPT_STRIDE)
	if c4_lmin < 0 or c4_lmax < c4_lmin:
		out.append("c4_lmin / c4_lmax: need 0 <= c4_lmin <= c4_lmax")
	if c7_hud_rows >= height:
		out.append("c7_hud_rows: below height")
	for key in NON_NEGATIVE:
		if int(get(key)) < 0:
			out.append("%s: at least 0" % key)
	if wide_pct < 0 or wide_pct > 100 or c3_share_pct < 0 or c4_ratio_pct < 100:
		out.append("wide_pct, c3_share_pct in 0..100; c4_ratio_pct at least 100")
	if tower_range <= 0.0:
		out.append("tower_range: positive")
	return out


static func _check_range(out: PackedStringArray, name: String, lo: int, hi: int, least: int) -> void:
	if lo < least or hi < lo:
		out.append("%s_min / %s_max: need %d <= min <= max" % [name, name, least])
