class_name TowerInfo
extends RefCounted
## Player-facing tower text built from config (LT-24 §3, LT-43): the stats table cells
## (row_values), special, kind and upgrade lines, cost text and refusal reasons. Pure and
## static (no nodes); every number comes from TowerDef / SanityConfig / EconomyConfig.

const CURRENCY := "$"  ## the money sign (LT-27 §2: "gold" internally, "$" on screen)
const DASH := " — "  ## between a name and its cost: "Rifleman — $50"
const COMING_SOON := " (coming soon)"  ## appended to lines whose key is in Level.PENDING
const MINUS := "−"  ## U+2212, for sanity drains
const MADNESS_WARNING := " (drives you mad!)"  ## LT-23 Q3: build/upgrade takes the cap to 0
const REMOVED := "Loses: "  ## LT-28: before the old line of an effect an upgrade removes
const CELL_DASH := "—"  ## LT-43 §1: a table cell with no value (never "0", never hidden)
const LIT_MARK := "*"  ## LT-43 §5 (Q4): after a value the lighthouse beam changes now
const NO_MISSES_LIT := "No misses while lit"  ## LT-43 §5: the Fraying line of a lit tower
const NOW_LIT := "* In the beam now: "  ## LT-43 §5: the status line of a lit tower
const NOW_SHADOW := "* In shadow now: "  ## LT-70 §5: the status line of a shadowed tower

## Player-facing names of SimTower.TARGET_PRIORITIES (LT-31).
const PRIORITY_NAMES := {
	"first": "Closest to the lighthouse",
	"strongest": "Strongest",
	"fastest": "Fastest",
}

## Effect lines in display order: the keys one line reads (a pair shares a line).
const EFFECT_GROUPS := [
	["pierce"], ["aoe_radius"], ["fuse_seconds"], ["ignore_armor"], ["sanity_scaling"],
	["reveal_fakes"], ["slow"], ["damage_taken_multiplier"], ["casts_light"], ["casts_shadow"],
	["crit_chance", "crit_multiplier"], ["burst_targets"], ["bleed_dps", "bleed_seconds"],
	["pull_cells", "pull_max_hp", "pull_immune_seconds"], ["strip_armor"],
	["banish_cells", "banish_targets"], ["banish_max_hp", "banish_immune_seconds"],
	["summon_max", "summon_lifetime"], ["summon_hp", "summon_dps"], ["summon_speed"],
	["summon_flying"],
]


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


## The reason text for a refused command (the table lives in CommandText).
static func reason(r: Simulation.CommandResult) -> String:
	return CommandText.reason(r)


static func is_pending(key: String) -> bool:
	return TowerDef.Level.PENDING.has(key)


## The value of an effect key that means "no effect": 1 for a multiplier, 0 otherwise.
static func neutral(key: String) -> float:
	return 1.0 if key.ends_with("_multiplier") else 0.0


## LT-28: an effect key with a value other than its neutral one (a x1 multiplier does nothing).
static func is_active(effects: Dictionary, key: String) -> bool:
	return effects.has(key) and effects[key] != neutral(key)


## One line per effect group present (a key off its neutral value) in `effects`, then
## `key: value` for any key no group reads; pending keys get COMING_SOON unless `suffix`
## is false.
static func effect_lines(effects: Dictionary, suffix := true) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for group: Array in EFFECT_GROUPS:
		var present := false
		var pending := false
		for key: String in group:
			seen[key] = true
			if is_active(effects, key):
				present = true
			if is_pending(key):
				pending = true
		if present:
			out.append(_effect_text(group[0], effects) + (COMING_SOON if pending and suffix else ""))
	for key: String in effects:
		if not seen.has(key) and is_active(effects, key):
			out.append("%s: %s" % [key, num(effects[key])]
				+ (COMING_SOON if is_pending(key) and suffix else ""))
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
		if to.effects.get(key, neutral(key)) != from.effects.get(key, neutral(key)):
			changed[key] = true
	# Whole groups: a pair line needs both values even if only one of them changed. A group
	# still active in `to` shows its new line; one active only in `from` was removed.
	var shown := {}
	var removed := {}
	var grouped := {}
	for group: Array in EFFECT_GROUPS:
		grouped.merge(_keys_dict(group))
		if not group.any(func(k: String) -> bool: return changed.has(k)):
			continue
		if group.any(func(k: String) -> bool: return is_active(to.effects, k)):
			for key: String in group:
				if to.effects.has(key):
					shown[key] = to.effects[key]
		elif group.any(func(k: String) -> bool: return is_active(from.effects, k)):
			for key: String in group:
				if from.effects.has(key):
					removed[key] = from.effects[key]
	for key: String in changed:
		if grouped.has(key):
			continue
		if is_active(to.effects, key):
			shown[key] = to.effects[key]
		elif is_active(from.effects, key):
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
## Effect keys a table row says already (Attack "Line", Hits "All"): no special line.
const ROW_EFFECT_KEYS: PackedStringArray = ["pierce", "summon_flying"]


## One string per ROWS key for `s` (a level or branch of `def`). `sanity_now` < 0 (the
## picker): a sanity-scaled DPS reads its range "15–45" (sanity max -> 0); >= 0 (the panel):
## the value at that sanity (LT-43 Q3). `cfg` null: the config rows read CELL_DASH.
static func row_values(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		sanity_now := -1.0) -> Dictionary:
	return {
		"attack": attack_text(s),
		"damage": damage_cell(s),
		"every": num(s.fire_interval) if s.acts() else CELL_DASH,
		"dps": dps_text(s, cfg, sanity_now),
		"range": range_text(s),
		"hits": hits_text(def, s),
		"kill": kill_text(def, s, cfg),
		"reserve": num(s.sanity_reserve) if s.sanity_reserve > 0.0 else CELL_DASH,
		"beam": beam_text(def, s, cfg),
		"shadow": beam_text(def, s, cfg, true),
		"special": special_short(s),
	}


## LT-43 §1 (Q2 "attack shape"), first match: Summon, Banish, Aura (no damage), Beam
## (sanity-scaled), Burst, Line (pierce), Blast (aoe), else Single.
static func attack_text(s: TowerDef.Level) -> String:
	if s.is_summon():
		return "Summon"
	if s.is_banish():
		return "Banish"
	if s.damage <= 0.0:
		return "Aura"
	if s.is_beam():
		return "Beam"
	if is_active(s.effects, "burst_targets"):
		return "Burst"
	if is_active(s.effects, "pierce"):
		return "Line"
	if is_active(s.effects, "aoe_radius"):
		return "Blast"
	return "Single"


## Damage per hit; a circle's unit DPS "15/s"; CELL_DASH without damage (aura, plain banish).
static func damage_cell(s: TowerDef.Level) -> String:
	if s.is_summon():
		return "%s/s" % num(s.effects.get("summon_dps", 0.0))
	return num(s.damage) if s.damage > 0.0 else CELL_DASH


## Damage per second at full sanity, base stats (no beam, no madness, no crits or bleed):
## TowerRules.effective's dps, neutral light, no sanity scaling.
static func dps_value(s: TowerDef.Level) -> float:
	return TowerRules.effective(null, s, null)["dps"]


## A table number with one decimal at most: 12.5, 11.3, 18.
static func one_decimal(v: float) -> String:
	return num(roundf(v * 10.0) / 10.0)


## The DPS cell: CELL_DASH for none; a sanity-scaled level reads "lo–hi" (sanity max -> 0)
## when `sanity_now` < 0, else its value at that sanity (LT-43 Q3).
static func dps_text(s: TowerDef.Level, cfg: GameConfig, sanity_now := -1.0) -> String:
	var v := dps_value(s)
	if v <= 0.0:
		return CELL_DASH
	if not s.is_beam() or cfg == null:
		return one_decimal(v)
	if sanity_now < 0.0:
		return "%s–%s" % [one_decimal(v),
			one_decimal(TowerRules.effective(null, s, cfg, false, false, 0.0)["dps"])]
	return one_decimal(TowerRules.effective(null, s, cfg, false, false, sanity_now)["dps"])


## Range in cells; "2–7" with a dead zone (LT-48 min_range).
static func range_text(s: TowerDef.Level) -> String:
	if s.min_range > 0.0:
		return "%s–%s" % [num(s.min_range), num(s.range_cells)]
	return num(s.range_cells)


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


## "+0.5": sanity a kill restores, for a mundane tower that deals damage.
static func kill_text(def: TowerDef, s: TowerDef.Level, cfg: GameConfig) -> String:
	if cfg == null or def.kind != "mundane" or s.damage <= 0.0 \
			or cfg.sanity.regen_mundane_kill <= 0.0:
		return CELL_DASH
	return "+" + num(cfg.sanity.regen_mundane_kill)


## LT-70 §5: TowerRules.light_effect of a `def` tower lit or, with `shadow`, shadowed;
## {} when that block (beam / shadow) is absent.
static func state_effect(def: TowerDef, cfg: GameConfig, shadow := false) -> Dictionary:
	if cfg == null or cfg.economy == null:
		return {}
	if (cfg.economy.shadow if shadow else cfg.economy.beam) == null:
		return {}
	return TowerRules.light_effect(def, cfg, not shadow, shadow)


## LT-30 beam effect as a percent: mundane fire rate "+25%" (1 / fire_interval_mult - 1),
## occult power "−30%" (power_mult - 1); CELL_DASH for a mundane support tower (it never
## fires) or a neutral multiplier. LT-70: `shadow` reads the shadow block ("−20%", "+15%").
static func beam_text(def: TowerDef, s: TowerDef.Level, cfg: GameConfig, shadow := false) -> String:
	var pct := beam_percent(def, s, cfg, shadow)
	if pct == 0.0:
		return CELL_DASH
	return ("+" if pct > 0.0 else MINUS) + num(roundf(absf(pct))) + "%"


## The light (or, with `shadow`, the shadow) percent beam_text shows (0 when none applies).
static func beam_percent(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		shadow := false) -> float:
	var fx := state_effect(def, cfg, shadow)
	if fx.is_empty():
		return 0.0
	if def.kind == "mundane":
		var m: float = fx["interval_mult"]
		if s.damage <= 0.0 or m <= 0.0:
			return 0.0
		return (1.0 / m - 1.0) * 100.0
	return (fx["power_mult"] - 1.0) * 100.0


## LT-43 §5 (Q4): the cells the beam changes on a lit tower, value + LIT_MARK, keyed like
## row_values: mundane Every x fire_interval_mult and DPS / it; occult Damage and DPS x
## power_mult (a circle: its unit DPS and DPS, as Simulation._summon gives the units
## it summons while lit). Empty when nothing changes. LT-70: `shadow` takes the shadow
## multipliers (a shadowed tower), with the same mark.
static func lit_values(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		sanity_now := -1.0, shadow := false) -> Dictionary:
	var out := {}
	var fx := state_effect(def, cfg, shadow)
	if fx.is_empty():
		return out
	# TowerRules.effective in the sim's own order (damage x factor x power, / interval).
	var sanity := sanity_now if s.is_beam() else -1.0
	var now := TowerRules.effective(def, s, cfg, not shadow, shadow, sanity)
	if def.kind == "mundane":
		var m: float = fx["interval_mult"]
		if s.damage > 0.0 and m > 0.0 and m != 1.0:
			out["every"] = num(now["interval"]) + LIT_MARK
			out["dps"] = one_decimal(now["dps"]) + LIT_MARK
	elif fx["power_mult"] != 1.0 and (s.damage > 0.0 or s.is_summon() and dps_value(s) > 0.0):
		var pm: float = fx["power_mult"]
		if s.is_summon():
			# "12.6*", no "/s": "12.6/s*" is cut in a 3-column panel
			out["damage"] = one_decimal(now["unit_dps"]) + LIT_MARK
		else:
			out["damage"] = num(TowerRules.shot_damage(s, 1.0, pm)) + LIT_MARK
		out["dps"] = one_decimal(now["dps"]) + LIT_MARK
	return out


## LT-43 §5: the effects of an occult aura, gate or circle while lit (slow, the taken bonus,
## the armor strip, the banish distance and a new unit's summon_dps x power_mult, as
## Simulation applies them); {} when the beam does not change them. LT-70: `shadow` takes
## shadow.occult_power_mult (a shadowed tower).
static func lit_effects(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		shadow := false) -> Dictionary:
	var fx := state_effect(def, cfg, shadow)
	if def.kind != "occult" or fx.is_empty():
		return {}
	var pm: float = fx["power_mult"]
	if pm == 1.0 or (s.acts() and not s.is_banish() and not s.is_summon()):
		return {}  # an aura, a gate or a circle only
	var e := s.effects.duplicate()
	for key: String in ["slow", "strip_armor", "banish_cells", "summon_dps"]:
		if e.has(key):
			e[key] = e[key] * pm
	if e.has("damage_taken_multiplier"):
		e["damage_taken_multiplier"] = TowerRules.powered_taken_mult(
			e["damage_taken_multiplier"], pm)
	return e if e != s.effects else {}


## LT-43 §5: the status line under the role of a lit tower; "" when the beam changes nothing.
## LT-70 §5: with `shadow`, a shadowed tower's line: NOW_SHADOW + "fire −20%, +10% misses"
## (mundane shooter) or "+15% power" (occult).
static func lit_line(def: TowerDef, s: TowerDef.Level, cfg: GameConfig, shadow := false) -> String:
	var pct := beam_percent(def, s, cfg, shadow)
	if pct == 0.0:
		return ""
	var head := NOW_SHADOW if shadow else NOW_LIT
	var signed := "%s%s%%" % [MINUS if pct < 0.0 else "+", num(roundf(absf(pct)))]
	if def.kind == "mundane":
		var t := head + "fire " + signed
		var fx := TowerRules.light_effect(def, cfg, not shadow, shadow)
		if shadow:
			var add: float = fx["miss_add"]
			return t + (", +%s%% misses" % num(add * 100.0) if add > 0.0 else "")
		return t + (", no misses" if fx["ignore_miss"] else "")
	return head + signed + " power"


## LT-43 Q3: the panel line under a sanity-scaled tower's table.
static func live_dps_text(sanity_now: float) -> String:
	return "DPS at sanity %s; grows as it falls" % num(floorf(sanity_now))


## The picker's Special cell (LT-43 §1): what no row says, short ("r 1, fuse 1 s",
## "Slow 35%, +50% taken"); CELL_DASH when nothing is left. `effects` defaults to the level's.
static func special_short(s: TowerDef.Level, effects: Variant = null) -> String:
	var e: Dictionary = s.effects if effects == null else effects
	var parts := PackedStringArray()
	if is_active(e, "aoe_radius"):
		parts.append("r %s" % num(e["aoe_radius"]))
	if is_active(e, "fuse_seconds"):
		parts.append("fuse %s s" % num(e["fuse_seconds"]))
	if is_active(e, "ignore_armor"):
		parts.append("no armor")
	if is_active(e, "sanity_scaling"):
		parts.append("×%s at 0 sanity" % num(1.0 + e["sanity_scaling"]))
	if is_active(e, "slow"):
		parts.append("slow %s%%" % num(e["slow"] * 100.0))
	if is_active(e, "damage_taken_multiplier"):
		parts.append("+%s%% taken" % num((e["damage_taken_multiplier"] - 1.0) * 100.0))
	if is_active(e, "reveal_fakes"):
		parts.append("shows fakes")
	if is_active(e, "crit_chance"):
		parts.append("%s%% crit ×%s" % [num(e["crit_chance"] * 100.0),
			num(e.get("crit_multiplier", 1.0))])
	if is_active(e, "burst_targets"):
		parts.append("%s targets in turn" % num(e["burst_targets"]))
	if is_active(e, "bleed_dps"):
		parts.append("bleed %s/s" % num(e["bleed_dps"]))
	if is_active(e, "pull_cells"):
		parts.append("pull %s" % num(e["pull_cells"]))
	if is_active(e, "strip_armor"):
		parts.append("%s%s armor" % [MINUS, num(e["strip_armor"])])
	if is_active(e, "banish_cells"):
		parts.append("back " + cells_text(num(e["banish_cells"])))
	if e.get("banish_targets", 1.0) > 1.0:
		parts.append("%s foes" % num(e["banish_targets"]))
	if is_active(e, "banish_max_hp"):
		parts.append("≤%s HP" % num(e["banish_max_hp"]))
	if is_active(e, "summon_max"):
		var n: float = e["summon_max"]
		parts.append("%s unit%s, %s HP" % [num(n), "" if n == 1.0 else "s",
			num(e.get("summon_hp", 0.0))])
	if is_active(e, "casts_light"):  # LT-70
		parts.append("lights")
	if is_active(e, "casts_shadow"):
		parts.append("shadows")
	if parts.is_empty():
		return CELL_DASH
	var t := ", ".join(parts)
	if t.begins_with("r "):  # the blast radius reads "r 1.5" (LT-43 §1)
		return t
	return t.substr(0, 1).to_upper() + t.substr(1)


## The full special lines under a table (LT-43 §1, §4): effect_lines without the keys a row
## already says (ROW_EFFECT_KEYS). `effects` defaults to the level's (lit_effects passes
## the lit ones).
static func special_lines(s: TowerDef.Level, effects: Variant = null) -> PackedStringArray:
	var e: Dictionary = (s.effects if effects == null else effects).duplicate()
	for key in ROW_EFFECT_KEYS:
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


static func _keys_dict(keys: Array) -> Dictionary:
	var d := {}
	for k: String in keys:
		d[k] = true
	return d


static func _effect_text(first_key: String, e: Dictionary) -> String:
	match first_key:
		"pierce":
			return "Pierce: %s-cell-wide line" % num(e.get("pierce", 0.0))
		"aoe_radius":
			return "Blast radius " + cells_text(num(e.get("aoe_radius", 0.0)))
		"fuse_seconds":
			return "Fuse %s s, thrown ahead" % num(e.get("fuse_seconds", 0.0))
		"ignore_armor":
			return "Ignores armor"
		"sanity_scaling":
			return "Up to x%s at low sanity" % num(1.0 + e.get("sanity_scaling", 0.0))
		"reveal_fakes":
			return "Reveals fakes"
		"slow":
			return "Slows enemies %s%%" % num(e.get("slow", 0.0) * 100.0)
		"damage_taken_multiplier":
			return "Foes take +%s%% damage" \
				% num((e.get("damage_taken_multiplier", 1.0) - 1.0) * 100.0)
		"crit_chance":
			return "%s%% crit, x%s damage" \
				% [num(e.get("crit_chance", 0.0) * 100.0), num(e.get("crit_multiplier", 0.0))]
		"burst_targets":
			return "Spreads fire over %s foes" % num(e.get("burst_targets", 0.0))
		"bleed_dps":
			return "Bleed %s/s for %s s" \
				% [num(e.get("bleed_dps", 0.0)), num(e.get("bleed_seconds", 0.0))]
		"pull_cells":
			return "Pull %sc, ≤%s HP, %ss" % [num(e.get("pull_cells", 0.0)),
				num(e.get("pull_max_hp", 0.0)), num(e.get("pull_immune_seconds", 0.0))]
		"strip_armor":
			return "Foes lose %s armor" % num(e.get("strip_armor", 0.0))
		"banish_cells":  # LT-51
			var n: float = e.get("banish_targets", 1.0)
			if n > 1.0:
				return "Banish %s foes %s" % [num(n), cells_text(num(e.get("banish_cells", 0.0)))]
			return "Banish %s back" % cells_text(num(e.get("banish_cells", 0.0)))
		"summon_max":  # LT-52
			var n: float = e.get("summon_max", 0.0)
			return "Up to %s unit%s, %s s each" % [num(n), "" if n == 1.0 else "s",
				num(e.get("summon_lifetime", 0.0))]
		"summon_hp":  # LT-52
			return "Unit %s HP, %s DPS" % [num(e.get("summon_hp", 0.0)),
				num(e.get("summon_dps", 0.0))]
		"summon_speed":  # LT-52
			return "Unit speed %s cells/s" % num(e.get("summon_speed", 0.0))
		"summon_flying":  # LT-52 (Byakhee)
			return "Units fly, hold flyers"
		"casts_light":  # LT-70 §5: at night only
			return "Lights towers and foes"
		"casts_shadow":  # LT-70 §5: at night only
			return "Shadows nearby towers"
		"banish_max_hp":  # LT-51 (Q4): the cap is shown
			return "Max %s HP; immune %s s" % [num(e.get("banish_max_hp", 0.0)),
				num(e.get("banish_immune_seconds", 0.0))]
	return "%s: %s" % [first_key, num(e.get(first_key, 0.0))]
