class_name TowerDef
extends RefCounted
## One tower from towers.json (GDD §6): L1 and L2 in `levels`, L3 as branch "a" or "b".

const FIELDS := ["name", "short", "role", "kind", "glyph", "targets", "cost", "levels",
	"branches"]
const KINDS: PackedStringArray = ["mundane", "occult"]
## LT-47 (LT-46 §2.3): "all" (default) or "ground": flyers are never candidates of a
## ground tower and never hit by its shots or blasts.
const TARGETS: PackedStringArray = ["all", "ground"]
const LEVEL_COUNT := 2  ## L1, L2; L3 is a branch
const BRANCH_IDS: PackedStringArray = ["a", "b"]
## Max length of a `role` line (tower or branch), after strip_edges (LT-24 §1).
const ROLE_MAX_CHARS := 24

var id: String
var name: String
## LT-61 §4: the name in the side-panel build list; defaults to `name`.
var short_name: String
## One-line player-facing role (no numbers); "" when absent (LT-24 §1).
var role: String
var kind: String  ## "mundane" | "occult"
## LT-47 (P11): the board letter, one character; defaults to the name's first letter.
## Glyphs are unique across towers (GameConfig).
var glyph: String
var targets := "all"  ## one of TARGETS
var cost: int  ## gold to build (L1), >= 0
var levels: Array[Level] = []
var branches: Dictionary[String, Level] = {}


static func parse(r: ConfigReader, id: String, obj: Dictionary, path: String) -> TowerDef:
	r.check_keys(obj, FIELDS, path)
	var t := TowerDef.new()
	t.id = id
	t.name = r.req_string(obj, "name", path)
	t.short_name = parse_short(r, obj, path, t.name)
	t.role = parse_role(r, obj, path)
	t.kind = r.req_string(obj, "kind", path, KINDS)
	t.glyph = t.name.left(1)
	var g := r.opt_string(obj, "glyph", path)
	# Codepoints <= 32 and U+00A0 draw nothing on the board.
	if g.length() == 1 and g.unicode_at(0) > 32 and g.unicode_at(0) != 0xA0:
		t.glyph = g
	elif obj.has("glyph"):
		r.error(ConfigReader.join(path, "glyph"),
			"must be exactly 1 visible character, got \"%s\"" % g)
	if obj.has("targets"):
		t.targets = r.as_string(obj["targets"], ConfigReader.join(path, "targets"), TARGETS)
		if t.targets.is_empty():
			t.targets = "all"
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


## LT-47: flyers are not candidates of this tower and not hit by its shots or blasts.
func ground_only() -> bool:
	return targets == "ground"


## LT-61 §4: optional `short` of `obj`, a non-blank string (stripped); `name` when absent
## or rejected.
static func parse_short(r: ConfigReader, obj: Dictionary, path: String,
		fallback: String) -> String:
	if not obj.has("short"):
		return fallback
	var sp := ConfigReader.join(path, "short")
	if typeof(obj["short"]) != TYPE_STRING:
		r.error(sp, "expected string, got %s" % ConfigReader.type_name(obj["short"]))
		return fallback
	var s: String = (obj["short"] as String).strip_edges()
	if s.is_empty():
		r.error(sp, "must not be empty")
		return fallback
	return s


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

	const LEVEL_FIELDS := ["name", "role", "upgrade_cost", "range", "min_range", "damage",
		"fire_interval", "sanity_reserve", "madness_affected", "effects"]

	var name: String
	var role: String  ## branches only (L3); "" on levels and when absent (LT-24 §1)
	var upgrade_cost: int  ## gold to upgrade into this level; 0 on L1 (use TowerDef.cost)
	var range_cells: float  ## JSON "range"; cells, > 0 (attack range or aura radius)
	## LT-48 (P4): dead zone, cells; enemies whose cell-centre distance is strictly less
	## are not candidates. Default 0; >= 0 and < range; only on towers with damage.
	var min_range: float
	var damage: float  ## per hit, >= 0 (0 and no banish = support tower, see acts())
	var fire_interval: float  ## seconds between shots; required > 0 when damage > 0
	## Total sanity cap this tower holds while it stands at this level (LT-23 §1), not added
	## to lower levels; >= 0, default 0, > 0 only on occult towers.
	var sanity_reserve: float
	## x2 damage and astray shots in madness (GDD §5.4). Defaults to kind == "occult";
	## only occult towers may set it true (Pure Rite sets false).
	var madness_affected: bool
	## Known effect parameters (schema, not balance): key -> max value (min is 0).
	const EFFECTS := {
		"crit_chance": 1.0, "crit_multiplier": INF, "burst_targets": INF, "pierce": INF,
		"bleed_dps": INF, "bleed_seconds": INF, "pull_cells": INF, "pull_max_hp": INF,
		"pull_immune_seconds": INF, "slow": 1.0, "damage_taken_multiplier": INF,
		"strip_armor": INF, "aoe_radius": INF, "fuse_seconds": INF,
		"ignore_armor": 1.0, "reveal_fakes": 1.0, "sanity_scaling": INF,
		"banish_cells": INF, "banish_targets": INF, "banish_max_hp": INF,
		"banish_immune_seconds": INF,
		"summon_max": INF, "summon_hp": INF, "summon_dps": INF, "summon_lifetime": INF,
		"summon_speed": INF, "summon_flying": 1.0,
	}
	## LT-51: the keys that only mean something on a banishing level (banish_cells > 0).
	const BANISH_KEYS: PackedStringArray = ["banish_targets", "banish_max_hp",
		"banish_immune_seconds"]
	## LT-51: shot shapes a banish cast does not have (it moves its picks, nothing else).
	const NOT_WITH_BANISH: PackedStringArray = ["pierce", "aoe_radius", "fuse_seconds",
		"burst_targets", "pull_cells", "sanity_scaling", "slow", "damage_taken_multiplier",
		"strip_armor", "reveal_fakes"]
	## LT-52: the keys that only mean something on a summoning level (summon_max > 0).
	const SUMMON_KEYS: PackedStringArray = ["summon_hp", "summon_dps", "summon_lifetime",
		"summon_speed", "summon_flying"]
	## LT-52: a summoning level's units must have these (> 0): a unit with no HP never
	## appears, one that cannot move never engages, one with no lifetime never makes room.
	const SUMMON_REQUIRED: PackedStringArray = ["summon_hp", "summon_lifetime", "summon_speed"]
	## LT-52: a circle only summons; its units do the damage (no shot shape, no banish).
	const NOT_WITH_SUMMON: PackedStringArray = ["pierce", "aoe_radius", "fuse_seconds",
		"burst_targets", "pull_cells", "sanity_scaling", "slow", "damage_taken_multiplier",
		"strip_armor", "reveal_fakes", "crit_chance", "bleed_dps", "ignore_armor",
		"banish_cells"]
	## LT-48/LT-49: flag effects, 0 or 1 (not amounts). LT-52: summon_flying.
	const FLAG_EFFECTS: PackedStringArray = ["ignore_armor", "reveal_fakes", "summon_flying"]

	## Config keys (EFFECTS or stats) that parse but the sim does not apply yet (LT-24
	## Decision 1). The UI marks them "(coming soon)" and bots skip branches using them;
	## the task that wires a key removes it from here. Empty since LT-29 wired the L3
	## branch effects; a later task that adds a key ahead of its sim code lists it here.
	const PENDING: PackedStringArray = []

	## Branch/level-specific numeric parameters (String -> float), keys from EFFECTS.
	var effects: Dictionary = {}

	## LT-50 (LT-46 P13/P14): a sanity-scaled level is a beam: it keeps its target while
	## that one stays a live candidate (SimTower.locked_id).
	func is_beam() -> bool:
		return effects.get("sanity_scaling", 0.0) > 0.0

	## LT-51 (LT-46 P9): a level that acts on enemies every fire_interval: it has damage,
	## it banishes or (LT-52) it summons. "Support" (an aura, no targeting) is `not acts()`.
	func acts() -> bool:
		return damage > 0.0 or is_banish() or is_summon()

	## LT-52: a Summoning Circle level, keeping up to summon_max allied units on the board.
	func is_summon() -> bool:
		return effects.get("summon_max", 0.0) > 0.0

	## LT-52: how many of its units a circle keeps live at once (summon_max, whole).
	func summon_max() -> int:
		return int(effects.get("summon_max", 0.0))

	## LT-52: true when this level's units fly (engage flyers too).
	func summon_flying() -> bool:
		return effects.get("summon_flying", 0.0) > 0.0

	## LT-51: a Silver Key level, moving its picks back `banish_cells` along their route.
	func is_banish() -> bool:
		return effects.get("banish_cells", 0.0) > 0.0

	## LT-51: how many enemies one cast moves (banish_targets, default 1).
	func banish_targets() -> int:
		return maxi(1, int(effects.get("banish_targets", 1.0)))

	## LT-50 (§7 Q2, current sanity on the full bar): the damage factor at `sanity` of
	## `max_sanity`, 1 + sanity_scaling x (1 - sanity / max), sanity clamped to 0..max;
	## 1 for a level without sanity_scaling.
	func sanity_factor(sanity: float, max_sanity: float) -> float:
		var k: float = effects.get("sanity_scaling", 0.0)
		if k <= 0.0 or max_sanity <= 0.0:
			return 1.0
		return 1.0 + k * (1.0 - clampf(sanity, 0.0, max_sanity) / max_sanity)

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
		# LT-48: a dead zone needs an attack and must leave a ring to fire into.
		l.min_range = r.opt_number(obj, "min_range", path, 0.0, 0.0)
		if l.min_range > 0.0:
			if l.damage <= 0.0:
				r.error(ConfigReader.join(path, "min_range"),
					"only towers with damage have a dead zone")
				l.min_range = 0.0
			elif l.range_cells > 0.0 and l.min_range >= l.range_cells:
				r.error(ConfigReader.join(path, "min_range"),
					"must be less than range (%s), got %s" % [l.range_cells, l.min_range])
				l.min_range = 0.0
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
			# LT-47: a fused charge is a delayed blast, so it needs a blast radius and is
			# not a line shot.
			if l.effects.get("fuse_seconds", 0.0) > 0.0:
				if l.effects.get("aoe_radius", 0.0) <= 0.0:
					r.error(ConfigReader.join(ep, "fuse_seconds"), "needs aoe_radius > 0")
				if l.effects.get("pierce", 0.0) > 0.0:
					r.error(ConfigReader.join(ep, "fuse_seconds"), "cannot combine with pierce")
				if l.effects.get("pull_cells", 0.0) > 0.0:
					r.error(ConfigReader.join(ep, "fuse_seconds"), "cannot combine with pull_cells")
			# LT-48/LT-49: flags, not amounts.
			for key in FLAG_EFFECTS:
				var f: float = l.effects.get(key, 0.0)
				if f != 0.0 and f != 1.0:
					r.error(ConfigReader.join(ep, key), "must be 0 or 1, got %s" % f)
					l.effects[key] = 0.0
			# LT-49/LT-50 (P8): a support level reveals the fakes in its aura, a level with
			# damage the fakes its shot hits (_on_hit_effects). A fused charge hits at the
			# blast, which reveals nothing, so it may not carry the flag.
			if l.effects.get("reveal_fakes", 0.0) > 0.0 \
					and l.effects.get("fuse_seconds", 0.0) > 0.0:
				r.error(ConfigReader.join(ep, "reveal_fakes"), "cannot combine with fuse_seconds")
				l.effects["reveal_fakes"] = 0.0
			# LT-50 (P13): the sanity factor scales shot damage, so it needs an attack.
			if l.effects.get("sanity_scaling", 0.0) > 0.0 and l.damage <= 0.0:
				r.error(ConfigReader.join(ep, "sanity_scaling"), "needs damage > 0")
				l.effects["sanity_scaling"] = 0.0
			_check_banish(r, l, ep)
			_check_summon(r, l, ep, path)
		if l.is_banish() and l.fire_interval <= 0.0:
			# LT-51: a gate with no damage still casts every fire_interval.
			r.error(ConfigReader.join(path, "fire_interval"), "required > 0 with banish_cells")
		if l.is_summon() and l.fire_interval <= 0.0:
			# LT-52: a circle summons every fire_interval.
			r.error(ConfigReader.join(path, "fire_interval"), "required > 0 with summon_max")
		return l

	## LT-52 (§2.2): a summoning level needs a whole summon_max >= 1, summon_hp,
	## summon_lifetime and summon_speed > 0, no damage of its own and no other attack
	## shape; the other summon keys need summon_max.
	static func _check_summon(r: ConfigReader, l: Level, ep: String, path: String) -> void:
		if not l.is_summon():
			for key in SUMMON_KEYS:
				if l.effects.get(key, 0.0) > 0.0:
					r.error(ConfigReader.join(ep, key), "needs summon_max > 0")
			return
		var n: float = l.effects["summon_max"]
		if n != floorf(n):
			r.error(ConfigReader.join(ep, "summon_max"), "must be a whole number >= 1, got %s" % n)
			l.effects["summon_max"] = maxf(1.0, floorf(n))
		for key in SUMMON_REQUIRED:
			if l.effects.get(key, 0.0) <= 0.0:
				r.error(ConfigReader.join(ep, "summon_max"), "needs %s > 0" % key)
		if l.damage > 0.0:
			r.error(ConfigReader.join(path, "damage"), "cannot combine with summon_max")
		for key in NOT_WITH_SUMMON:
			if l.effects.get(key, 0.0) > 0.0:
				r.error(ConfigReader.join(ep, key), "cannot combine with summon_max")

	## LT-51 (§2.2, Q4 "HP cap per level"): a banishing level needs its HP cap
	## (banish_max_hp > 0: Dagon is never banished, so "no cap" is not offered), a whole
	## banish_targets >= 1, and no other shot shape; the other banish keys need banish_cells.
	static func _check_banish(r: ConfigReader, l: Level, ep: String) -> void:
		if not l.is_banish():
			for key in BANISH_KEYS:
				if l.effects.get(key, 0.0) > 0.0:
					r.error(ConfigReader.join(ep, key), "needs banish_cells > 0")
			return
		if l.effects.get("banish_max_hp", 0.0) <= 0.0:
			r.error(ConfigReader.join(ep, "banish_cells"), "needs banish_max_hp > 0")
		if l.effects.has("banish_targets"):
			var n: float = l.effects["banish_targets"]
			if n < 1.0 or n != floorf(n):
				r.error(ConfigReader.join(ep, "banish_targets"),
					"must be a whole number >= 1, got %s" % n)
				l.effects["banish_targets"] = 1.0
		for key in NOT_WITH_BANISH:
			if l.effects.get(key, 0.0) > 0.0:
				r.error(ConfigReader.join(ep, key), "cannot combine with banish_cells")
