class_name EffectCatalog
extends RefCounted
## LT-103 §2.1: one row per tower effect key (schema, not balance; the sim reads no files).
## A new effect key is one row here, one text entry and its behaviour. Absent row fields
## take their default:
##   max       INF    largest value parse accepts (min is 0)
##   flag      false  0 or 1, not an amount (implies max 1)
##   whole     false  a whole number >= 1 when its family is active
##   neutral   0.0    the value that means "no effect" (1 for a multiplier)
##   power     ""     "mult": x the occult power mult on an aura, gate or circle;
##                    "taken": by TowerRules.powered_taken_mult
##   mode      none   the attack Mode this key gives a level (Level.mode)
##   requires  []     keys that must be > 0 when this key is: "needs Y > 0" at this key
##   not_with  []     keys that may not be > 0 with this key: "cannot combine with Y"
##   pending   false  parses but the sim does not apply it yet (UI "(coming soon)")
## Row order is the parse order of each check (TowerDef.Level.parse).

## LT-103 §2.2: a level's one attack mode; the enum order is the precedence (first match).
enum Mode { AURA, BANISH, SUMMON, BEAM, BURST, LINE, FUSE, BLAST, SINGLE }

const _OWNER_SHAPES := ["banish_cells", "summon_max"]

const ROWS := {
	"crit_chance": {"max": 1.0, "not_with": ["summon_max"]},
	"crit_multiplier": {"neutral": 1.0},
	# LT-103 Q1: a burst picks several targets for one point shot; no other shape or beam.
	"burst_targets": {"mode": Mode.BURST, "not_with": ["pierce", "aoe_radius", "fuse_seconds",
		"sanity_scaling", "banish_cells", "summon_max"]},
	"pierce": {"mode": Mode.LINE, "not_with": ["banish_cells", "summon_max"]},
	"bleed_dps": {"not_with": ["summon_max"]},
	"bleed_seconds": {},
	"pull_cells": {"not_with": ["banish_cells", "summon_max"]},
	"pull_max_hp": {},
	"pull_immune_seconds": {},
	"slow": {"max": 1.0, "power": "mult", "not_with": ["banish_cells", "summon_max"]},
	"damage_taken_multiplier": {"neutral": 1.0, "power": "taken",
		"not_with": ["banish_cells", "summon_max"]},
	"strip_armor": {"power": "mult", "not_with": ["banish_cells", "summon_max"]},
	"aoe_radius": {"mode": Mode.BLAST, "not_with": ["banish_cells", "summon_max"]},
	# LT-47: a fused charge is a delayed blast, so it needs a blast radius and is not a line.
	"fuse_seconds": {"mode": Mode.FUSE, "requires": ["aoe_radius"],
		"not_with": ["pierce", "pull_cells", "banish_cells", "summon_max"]},
	"ignore_armor": {"flag": true, "not_with": ["summon_max"]},
	# LT-49/LT-50 (P8): a fused charge hits at the blast, which reveals nothing.
	"reveal_fakes": {"flag": true, "not_with": ["fuse_seconds", "banish_cells", "summon_max"]},
	# LT-103 Q1: a beam holds one target with a point shot.
	"sanity_scaling": {"mode": Mode.BEAM, "not_with": ["pierce", "aoe_radius", "fuse_seconds",
		"banish_cells", "summon_max"]},
	# LT-51: Dagon is never banished, so a gate always has its HP cap.
	"banish_cells": {"mode": Mode.BANISH, "power": "mult", "requires": ["banish_max_hp"],
		"not_with": ["summon_max"]},
	"banish_targets": {"whole": true, "requires": ["banish_cells"]},
	"banish_max_hp": {"requires": ["banish_cells"]},
	"banish_immune_seconds": {"requires": ["banish_cells"]},
	# LT-52: a unit with no HP never appears, one that cannot move never engages, one with
	# no lifetime never makes room.
	"summon_max": {"mode": Mode.SUMMON, "whole": true,
		"requires": ["summon_hp", "summon_lifetime", "summon_speed"]},
	"summon_hp": {"requires": ["summon_max"]},
	"summon_dps": {"power": "mult", "requires": ["summon_max"]},
	"summon_lifetime": {"requires": ["summon_max"]},
	"summon_speed": {"requires": ["summon_max"]},
	"summon_flying": {"flag": true, "requires": ["summon_max"]},
	# LT-103 Q2: a unit's hold distance in cells; absent = AllySystem.ALLY_CONTACT.
	"summon_contact": {"requires": ["summon_max"]},
	# LT-103 Q2: whom a unit engages, cells from its summon spot; absent = range + 1.
	"summon_leash": {"requires": ["summon_max"]},
	# LT-70 §3: support levels only (Level.parse), light or shadow, not both.
	"casts_light": {"flag": true, "not_with": ["banish_cells", "summon_max"]},
	"casts_shadow": {"flag": true, "not_with": ["casts_light", "banish_cells", "summon_max"]},
}

static var _mode_order: Array[String] = []


static func has(key: String) -> bool:
	return ROWS.has(key)


static func keys() -> Array:
	return ROWS.keys()


## The row of `key` ({} for an unknown key).
static func row(key: String) -> Dictionary:
	return ROWS.get(key, {})


static func max_of(key: String) -> float:
	var r := row(key)
	return 1.0 if r.get("flag", false) else float(r.get("max", INF))


## The value of `key` that means "no effect". An unknown key keeps the old suffix rule:
## 1 for a `_multiplier`, 0 otherwise.
static func neutral(key: String) -> float:
	if ROWS.has(key):
		return float(ROWS[key].get("neutral", 0.0))
	return 1.0 if key.ends_with("_multiplier") else 0.0


static func is_flag(key: String) -> bool:
	return row(key).get("flag", false)


static func is_whole(key: String) -> bool:
	return row(key).get("whole", false)


static func is_pending(key: String) -> bool:
	return row(key).get("pending", false)


static func pending_keys() -> Array[String]:
	return _keys_where("pending", true)


static func flag_keys() -> Array[String]:
	return _keys_where("flag", true)


## "" (not scaled), "mult" or "taken".
static func power_of(key: String) -> String:
	return row(key).get("power", "")


static func power_keys(power: String) -> Array[String]:
	return _keys_where("power", power)


static func requires_of(key: String) -> Array:
	return row(key).get("requires", [])


static func not_with_of(key: String) -> Array:
	return row(key).get("not_with", [])


## Keys whose row requires `owner`, in row order.
static func keys_requiring(owner: String) -> Array[String]:
	var out: Array[String] = []
	for k: String in ROWS:
		if (ROWS[k].get("requires", []) as Array).has(owner):
			out.append(k)
	return out


## Keys whose row may not combine with `other`, in row order.
static func keys_not_with(other: String) -> Array[String]:
	var out: Array[String] = []
	for k: String in ROWS:
		if (ROWS[k].get("not_with", []) as Array).has(other):
			out.append(k)
	return out


## A key whose mode is a whole attack of its own (banish, summon): its family and
## exclusions are checked in its own parse phase (Level._check_banish / _check_summon).
static func is_owner(key: String) -> bool:
	return _OWNER_SHAPES.has(key)


## The keys that carry a mode, sorted by their Mode (the precedence).
static func mode_order() -> Array[String]:
	if _mode_order.is_empty():
		var by_mode := {}
		for k: String in ROWS:
			if ROWS[k].has("mode"):
				by_mode[ROWS[k]["mode"]] = k
		var modes := by_mode.keys()
		modes.sort()
		for m: int in modes:
			_mode_order.append(by_mode[m])
	return _mode_order


## The Mode a mode key gives (-1 for a key without one).
static func mode_of(key: String) -> int:
	return row(key).get("mode", -1)


static func _keys_where(field: String, value: Variant) -> Array[String]:
	var out: Array[String] = []
	for k: String in ROWS:
		if ROWS[k].get(field, null) == value:
			out.append(k)
	return out
