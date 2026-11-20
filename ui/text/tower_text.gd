class_name TowerText
extends RefCounted
## Player-facing tower text (LT-24 §3, LT-43; LT-65 §3.6, LT-79): the stats table cells
## (row_values), special, kind and upgrade lines, money and cost text. Pure strings, static
## (no nodes): the table numbers come from TowerStatsModel (built on TowerRules), the rest
## straight from TowerDef / SanityConfig. Refusal reasons are CommandText's.

const CURRENCY := "$"  ## the money sign (LT-27 §2: "gold" internally, "$" on screen)
const DASH := " — "  ## between a name and its cost: "Rifleman — $50"
const COMING_SOON := " (coming soon)"  ## appended to lines whose key is pending (EffectCatalog)
const MINUS := "−"  ## U+2212, for sanity drains
const MADNESS_WARNING := " (drives you mad!)"  ## LT-23 Q3: build/upgrade takes the cap to 0
const REMOVED := "Loses: "  ## LT-28: before the old line of an effect an upgrade removes
const CELL_DASH := "—"  ## LT-43 §1: a table cell with no value (never "0", never hidden)
const LIT_MARK := "*"  ## LT-43 §5 (Q4): after a value the lighthouse beam changes now
const NO_MISSES_LIT := "No misses while lit"  ## LT-43 §5: the Fraying line of a lit tower
const NOW_LIT := "* In the beam now: "  ## LT-43 §5: the status line of a lit tower
const NOW_SHADOW := "* In shadow now: "  ## LT-70 §5: the status line of a shadowed tower
## LT-105 (Q3): the status line of a tower whose modifier channel is changed by something
## other than light / shadow (neither lit nor shadowed).
const NOW_MODIFIED := "* Modified now: "

## Player-facing names of SimTower.TARGET_PRIORITIES (LT-31).
const PRIORITY_NAMES := {
	"first": "Closest to the lighthouse",
	"strongest": "Strongest",
	"fastest": "Fastest",
}


## Up to 2 decimals, trailing zeros dropped: 3.5, 82.5, 0.2, 12.
static func num(v: float) -> String:
	var s := "%.2f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" else s


## "1 cell" / "2.5 cells": `n` is an already formatted number (LT-59).
static func cells_text(n: String) -> String:
	return n + (" cell" if n == "1" else " cells")


## "$40" (sanity is reserved, not paid: LT-23).
static func cost_text(gold: int) -> String:
	return money(gold)


## LT-27 §2: money as shown on screen, "$240"; a negative amount reads "−$5".
static func money(amount: int) -> String:
	return ("%s%s%d" % [MINUS if amount < 0 else "", CURRENCY, absi(amount)])


## One line per effect group present (a key off its neutral value) in `effects`, then
## `key: value` for any key no group reads; pending keys get COMING_SOON unless `suffix`
## is false.
static func effect_lines(effects: Dictionary, suffix := true) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for entry: Dictionary in EffectText.lines():
		var present := false
		var pending := false
		for key: String in entry["keys"]:
			seen[key] = true
			if TowerStatsModel.is_active(effects, key):
				present = true
			if TowerStatsModel.is_pending(key):
				pending = true
		if present:
			out.append(EffectText.line_text(entry, effects)
				+ (COMING_SOON if pending and suffix else ""))
	for key: String in effects:
		if not seen.has(key) and TowerStatsModel.is_active(effects, key):
			out.append("%s: %s" % [key, num(effects[key])]
				+ (COMING_SOON if TowerStatsModel.is_pending(key) and suffix else ""))
	return out


## Kind lines, one line under the stats table (LT-43 §1): mundane Fraying misses ("No
## misses while lit" when `no_misses`: lit, with beam.mundane_ignore_miss; LT-70 §5: then
## "+10% misses in shadow" when `shadow_miss` > 0: shadowed, shadow.mundane_miss_chance_add),
## occult madness behaviour. The kill regen is the table's Sanity/kill row, not a line here.
static func kind_lines(def: TowerDef, s: TowerDef.Level, sanity: SanityConfig,
		no_misses := false, shadow_miss := 0.0) -> PackedStringArray:
	var out := PackedStringArray()
	if def.kind == "mundane":
		if sanity == null:
			return out
		var fraying: SanityConfig.Threshold = sanity.thresholds.get("fraying")
		# LT-49: a mundane support tower (Searchlight) never shoots, so it never misses.
		if s.damage > 0.0 and fraying != null and fraying.miss_chance > 0.0:
			out.append(NO_MISSES_LIT if no_misses
				else "May miss while Fraying (%s%%)" % num(fraying.miss_chance * 100.0))
		if s.damage > 0.0 and shadow_miss > 0.0:
			out.append("+%s%% misses in shadow" % num(shadow_miss * 100.0))
	elif s.acts():
		# Madness changes shots only (x damage, astray); an aura has none. LT-51: a gate
		# without damage only goes astray. LT-52: a circle's units deal x damage, never
		# astray (a unit bites what it holds).
		if s.madness_affected and s.is_summon():
			var um := sanity.madness.damage_multiplier if sanity != null else 0.0
			out.append("Madness: units x%s" % num(um))
		elif s.madness_affected and s.damage <= 0.0:
			out.append("Madness: astray")
		elif s.madness_affected:
			var mult := sanity.madness.damage_multiplier if sanity != null else 0.0
			out.append("Madness: x%s, astray" % num(mult))
		else:
			out.append("Unaffected by madness")
	return out


## LT-43 §2: what an upgrade changes beyond the table rows: the effect lines that are new
## or changed, then REMOVED + the old line for each effect `to` no longer has (LT-28), then
## a madness line if that flag flips. Stats and the reserve are table cells, not lines.
static func special_delta_lines(from: TowerDef.Level, to: TowerDef.Level) -> PackedStringArray:
	var out := PackedStringArray()
	var changed := {}
	for key: String in to.effects.keys() + from.effects.keys():
		var none := TowerStatsModel.neutral(key)
		if to.effects.get(key, none) != from.effects.get(key, none):
			changed[key] = true
	# Whole groups: a pair line needs both values even if only one of them changed. A group
	# still active in `to` shows its new line; one active only in `from` was removed.
	var shown := {}
	var removed := {}
	var grouped := {}
	for entry: Dictionary in EffectText.lines():
		var group: Array = entry["keys"]
		for key: String in group:
			grouped[key] = true
		if not group.any(func(k: String) -> bool: return changed.has(k)):
			continue
		if group.any(func(k: String) -> bool: return TowerStatsModel.is_active(to.effects, k)):
			for key: String in group:
				if to.effects.has(key):
					shown[key] = to.effects[key]
		elif group.any(func(k: String) -> bool: return TowerStatsModel.is_active(from.effects, k)):
			for key: String in group:
				if from.effects.has(key):
					removed[key] = from.effects[key]
	for key: String in changed:
		if grouped.has(key):
			continue
		if TowerStatsModel.is_active(to.effects, key):
			shown[key] = to.effects[key]
		elif TowerStatsModel.is_active(from.effects, key):
			removed[key] = from.effects[key]
	out.append_array(effect_lines(shown))
	for line in effect_lines(removed, false):
		out.append(REMOVED + line)
	if from.madness_affected != to.madness_affected and to.acts():
		out.append("Affected by madness" if to.madness_affected else "Unaffected by madness")
	return out


# --- LT-43: the shared stats table ------------------------------------------------------

## The table rows in display order (LT-43 §1): [key, label]. Every tower shows all of them;
## a row with no value reads CELL_DASH. "special" is the picker's last row; the side panel
## prints the special lines under its table instead.
const ROWS := [
	["attack", "Attack"], ["damage", "Damage"], ["every", "Every, s"], ["dps", "DPS"],
	["range", "Range"], ["hits", "Hits"], ["kill", "Sanity/kill"], ["reserve", "Reserve"],
	["beam", "In light"], ["shadow", "In shadow"], ["special", "Special"],
]


## One string per ROWS key for `s` (a level or branch of `def`): TowerStatsModel.row_numbers
## formatted, plus the attack shape, the hits and the special cell. `sanity_now` < 0 (the
## picker): a sanity-scaled DPS reads its range "15–45" (sanity max -> 0); >= 0 (the panel):
## the value at that sanity (LT-43 Q3). `cfg` null: the config rows read CELL_DASH.
static func row_values(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		sanity_now := -1.0) -> Dictionary:
	var n := TowerStatsModel.row_numbers(def, s, cfg, sanity_now)
	return {
		"attack": attack_text(s),
		"damage": _damage_cell(s, n),
		"every": num(n["every"]) if n.has("every") else CELL_DASH,
		"dps": _dps_cell(n),
		"range": _range_cell(n),
		"hits": hits_text(def, s),
		"kill": "+" + num(n["kill"]) if n.has("kill") else CELL_DASH,
		"reserve": num(n["reserve"]) if n.has("reserve") else CELL_DASH,
		"beam": _percent_cell(n["beam"]),
		"shadow": _percent_cell(n["shadow"]),
		"special": special_short(s),
	}


## LT-43 §1 (Q2 "attack shape") / LT-103 §2.2: the label of Level.mode from
## data/effect_text.json (a fused charge reads "Blast").
static func attack_text(s: TowerDef.Level) -> String:
	return EffectText.mode_label(s.mode())


## A table number with one decimal at most: 12.5, 11.3, 18.
static func one_decimal(v: float) -> String:
	return num(roundf(v * 10.0) / 10.0)


## The DPS cell: CELL_DASH for none; a sanity-scaled level reads "lo–hi" (sanity max -> 0)
## when `sanity_now` < 0, else its value at that sanity (LT-43 Q3).
static func dps_text(s: TowerDef.Level, cfg: GameConfig, sanity_now := -1.0) -> String:
	return _dps_cell(TowerStatsModel.dps_numbers(s, cfg, sanity_now))


## Range in cells; "2–7" with a dead zone (LT-48 min_range).
static func range_text(s: TowerDef.Level) -> String:
	return _range_cell(TowerStatsModel.range_numbers(s))


## LT-61 §2: the build list's Trait cell, the one property to know before building, first
## match: "Res N" (an occult sanity reserve), "Ground" (never hits flyers), "Blind N" (no
## fire within N cells), "Line" (pierce), "Reveal" (shows fakes), "Blast" (area), else
## CELL_DASH. The madness "!" is the picker's (it depends on the live sanity cap).
static func trait_text(def: TowerDef, s: TowerDef.Level) -> String:
	if def.kind == "occult" and s.sanity_reserve > 0.0:
		return "Res " + num(s.sanity_reserve)
	if def.ground_only():
		return "Ground"
	if s.min_range > 0.0:
		return "Blind " + num(s.min_range)
	if s.effects.get("pierce", 0.0) > 0.0:
		return "Line"
	if s.effects.get("reveal_fakes", 0.0) > 0.0:
		return "Reveal"
	if s.effects.get("aoe_radius", 0.0) > 0.0:
		return "Blast"
	return CELL_DASH


## "All" or "Ground" (TowerDef.targets; a circle: whether its units fly).
static func hits_text(def: TowerDef, s: TowerDef.Level) -> String:
	if s.is_summon():
		return "All" if s.summon_flying() else "Ground"
	return "Ground" if def.ground_only() else "All"


## LT-43 §5 (Q4): the cells the beam changes on a lit tower (TowerStatsModel.lit_numbers),
## value + LIT_MARK, keyed like row_values: mundane Every and DPS; occult Damage and DPS (a
## circle: its unit DPS and DPS). Empty when nothing changes. LT-70: `shadow` takes the
## shadow multipliers (a shadowed tower), with the same mark. LT-105 D7: `fx`, when given,
## is the tower's modifier channel (TowerStatsModel.lit_numbers).
static func lit_values(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		sanity_now := -1.0, shadow := false, fx := {}) -> Dictionary:
	var out := {}
	var n := TowerStatsModel.lit_numbers(def, s, cfg, sanity_now, shadow, fx)
	for key: String in n:
		var v: float = n[key]
		# a circle's unit DPS reads "12.6*", no "/s": "12.6/s*" is cut in a 3-column panel
		var one := key == "dps" or key == "damage" and s.is_summon()
		out[key] = (one_decimal(v) if one else num(v)) + LIT_MARK
	return out


## LT-43 §5: the status line under the role of a lit tower; "" when the beam changes nothing.
## LT-70 §5: with `shadow`, a shadowed tower's line: NOW_SHADOW + "fire −20%, +10% misses"
## (mundane shooter) or "+15% power" (occult). LT-105 D7: `fx`, when given, is the tower's
## modifier channel; `head`, when given, replaces the NOW_LIT / NOW_SHADOW head (the panel
## passes NOW_MODIFIED for a tower changed by neither light nor shadow, Q3). A mundane line
## ends ", no misses" with ignore_miss, else ", +N% misses" with miss_add > 0.
static func lit_line(def: TowerDef, s: TowerDef.Level, cfg: GameConfig, shadow := false,
		fx := {}, head := "") -> String:
	fx = TowerStatsModel.effect_of(def, cfg, shadow, fx)
	var pct := TowerStatsModel.beam_percent(def, s, cfg, shadow, fx)
	if pct == 0.0:
		return ""
	if head.is_empty():
		head = NOW_SHADOW if shadow else NOW_LIT
	var signed := "%s%s%%" % [MINUS if pct < 0.0 else "+", num(roundf(absf(pct)))]
	if def.kind == "mundane":
		var t := head + "fire " + signed
		if fx["ignore_miss"]:
			return t + ", no misses"
		var add: float = fx["miss_add"]
		return t + (", +%s%% misses" % num(add * 100.0) if add > 0.0 else "")
	return head + signed + " power"


## LT-43 Q3: the panel line under a sanity-scaled tower's table.
static func live_dps_text(sanity_now: float) -> String:
	return "DPS at sanity %s; grows as it falls" % num(floorf(sanity_now))


## The picker's Special cell (LT-43 §1): what no row says, short ("r 1, fuse 1 s",
## "Slow 35%, +50% taken"); CELL_DASH when nothing is left. `effects` defaults to the level's.
static func special_short(s: TowerDef.Level, effects: Variant = null) -> String:
	var e: Dictionary = s.effects if effects == null else effects
	var t := EffectText.short_text(e)
	return CELL_DASH if t.is_empty() else t


## The full special lines under a table (LT-43 §1, §4): effect_lines without the keys a row
## already says (EffectText.in_row_keys). `effects` defaults to the level's (lit_effects passes
## the lit ones).
static func special_lines(s: TowerDef.Level, effects: Variant = null) -> PackedStringArray:
	var e: Dictionary = (s.effects if effects == null else effects).duplicate()
	for key in EffectText.in_row_keys():
		e.erase(key)
	return effect_lines(e)


## LT-43 §3: a tower's upgrade path for the picker card, "L2 $70 · then A Demolition man or
## B Shrapnel charges".
static func upgrade_path_text(def: TowerDef) -> String:
	if def.levels.size() < 2:
		return ""
	var t := "L2 %s" % cost_text(def.levels[1].upgrade_cost)
	var names := PackedStringArray()
	for b: String in TowerDef.BRANCH_IDS:
		if def.branches.has(b):
			names.append("%s %s" % [b.to_upper(), def.branches[b].name])
	if not names.is_empty():
		t += " · then " + " or ".join(names)
	return t


## Damage per hit; a circle's unit DPS "15/s"; CELL_DASH without damage (aura, plain banish).
static func _damage_cell(s: TowerDef.Level, n: Dictionary) -> String:
	if not n.has("damage"):
		return CELL_DASH
	return ("%s/s" if s.is_summon() else "%s") % num(n["damage"])


static func _dps_cell(n: Dictionary) -> String:
	if not n.has("dps"):
		return CELL_DASH
	if n.has("dps_to"):
		return "%s–%s" % [one_decimal(n["dps"]), one_decimal(n["dps_to"])]
	return one_decimal(n["dps"])


static func _range_cell(n: Dictionary) -> String:
	if n.has("min_range"):
		return "%s–%s" % [num(n["min_range"]), num(n["range"])]
	return num(n["range"])


## A light / shadow percent "+25%" / "−30%"; CELL_DASH for 0 (TowerStatsModel.beam_percent).
static func _percent_cell(pct: float) -> String:
	if pct == 0.0:
		return CELL_DASH
	return ("+" if pct > 0.0 else MINUS) + num(roundf(absf(pct))) + "%"
