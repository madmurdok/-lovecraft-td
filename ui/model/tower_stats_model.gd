class_name TowerStatsModel
extends RefCounted
## LT-65 §3.6 (LT-79): the numbers behind the shared stats table (LT-43) and the lit / shadow
## cells (LT-43 §5, LT-70 §5), as data. Every rule value comes from TowerRules (sim/rules,
## LT-76); this file has no rule formula of its own and makes no text (TowerText formats).
## Pure and static (no nodes).


## The value of an effect key that means "no effect" (EffectCatalog.neutral): 1 for a
## multiplier, 0 otherwise.
static func neutral(key: String) -> float:
	return EffectCatalog.neutral(key)


## LT-28: an effect key with a value other than its neutral one (a x1 multiplier does nothing).
static func is_active(effects: Dictionary, key: String) -> bool:
	return effects.has(key) and effects[key] != neutral(key)


## An effect key the sim does not apply yet (EffectCatalog.is_pending).
static func is_pending(key: String) -> bool:
	return EffectCatalog.is_pending(key)


## The numbers of the table rows for `s` (a level or branch of `def`), keyed like
## TowerText.ROWS; a row with no value is absent (beam / shadow: 0). Keys: "damage" (per hit;
## a circle: its unit DPS), "every", the keys of dps_numbers and range_numbers, "kill",
## "reserve", "beam", "shadow" (percents, beam_percent).
## `sanity_now` and `cfg` as in dps_numbers.
static func row_numbers(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		sanity_now := -1.0) -> Dictionary:
	var out := {}
	if s.is_summon():
		out["damage"] = s.effects.get("summon_dps", 0.0)
	elif s.damage > 0.0:
		out["damage"] = s.damage
	if s.acts():
		out["every"] = TowerRules.shot_period(s, 1.0)  # LT-89: whole ticks, as the sim fires
	out.merge(dps_numbers(s, cfg, sanity_now))
	out.merge(range_numbers(s))
	var kill := kill_regen(def, s, cfg)
	if kill > 0.0:
		out["kill"] = kill
	if s.sanity_reserve > 0.0:
		out["reserve"] = s.sanity_reserve
	out["beam"] = beam_percent(def, s, cfg)
	out["shadow"] = beam_percent(def, s, cfg, true)
	return out


## The Range row's numbers in cells: "range", and "min_range" with a dead zone (LT-48).
static func range_numbers(s: TowerDef.Level) -> Dictionary:
	if s.min_range > 0.0:
		return {"range": s.range_cells, "min_range": s.min_range}
	return {"range": s.range_cells}


## Damage per second at full sanity, base stats (no beam, no madness, no crits or bleed):
## TowerRules.effective's dps, neutral light, no sanity scaling.
static func dps_value(s: TowerDef.Level) -> float:
	return TowerRules.effective(null, s, null)["dps"]


## The DPS cell's numbers: {} for none; {"dps"} otherwise. A sanity-scaled level with `cfg`:
## `sanity_now` < 0 (the picker) gives its range, "dps" at sanity max and "dps_to" at 0;
## >= 0 (the panel) gives "dps" at that sanity (LT-43 Q3).
static func dps_numbers(s: TowerDef.Level, cfg: GameConfig, sanity_now := -1.0) -> Dictionary:
	var v := dps_value(s)
	if v <= 0.0:
		return {}
	if not s.is_beam() or cfg == null:
		return {"dps": v}
	if sanity_now < 0.0:
		return {"dps": v, "dps_to": TowerRules.effective(null, s, cfg, false, false, 0.0)["dps"]}
	return {"dps": TowerRules.effective(null, s, cfg, false, false, sanity_now)["dps"]}


## Sanity a kill restores, for a mundane tower that deals damage; 0 for none (or no `cfg`).
static func kill_regen(def: TowerDef, s: TowerDef.Level, cfg: GameConfig) -> float:
	if cfg == null or def.kind != "mundane" or s.damage <= 0.0 \
			or cfg.sanity.regen_mundane_kill <= 0.0:
		return 0.0
	return cfg.sanity.regen_mundane_kill


## LT-70 §5: TowerRules.light_effect of a `def` tower lit or, with `shadow`, shadowed;
## {} when that block (beam / shadow) is absent.
static func state_effect(def: TowerDef, cfg: GameConfig, shadow := false) -> Dictionary:
	if cfg == null or cfg.economy == null:
		return {}
	if (cfg.economy.shadow if shadow else cfg.economy.beam) == null:
		return {}
	return TowerRules.light_effect(def, cfg, not shadow, shadow)


## LT-122: what a shadow does to the towers it covers, as TowerRules applies it: occult
## power_mult, mundane interval_mult and miss_add of a shadowed tower; {} when the economy has
## no shadow block.
static func shadow_numbers(cfg: GameConfig) -> Dictionary:
	if cfg == null or cfg.economy == null or cfg.economy.shadow == null:
		return {}
	return {
		"occult_power_mult": TowerRules.power_mult("occult", cfg, false, true),
		"mundane_interval_mult": TowerRules.interval_mult("mundane", cfg, false, true),
		"mundane_miss_add": TowerRules.miss_add("mundane", cfg, true),
	}


## LT-105 D7: the modifiers a lit / shadow function reads: `fx` when given (a placed
## tower's channel, Simulation.tower_mults), else state_effect(def, cfg, shadow).
static func effect_of(def: TowerDef, cfg: GameConfig, shadow: bool, fx: Dictionary) -> Dictionary:
	return fx if not fx.is_empty() else state_effect(def, cfg, shadow)


## LT-105 (Q3): a tower's modifiers `fx` (SimTower.modifiers keys) change anything: the panel
## marks it then.
static func is_modified(fx: Dictionary) -> bool:
	return fx.get("power_mult", 1.0) != 1.0 or fx.get("interval_mult", 1.0) != 1.0 \
		or fx.get("miss_add", 0.0) != 0.0 or fx.get("ignore_miss", false) \
		or fx.get("disabled", false)


## LT-105 (Q3): the tower's channel `fx` is exactly what light alone writes for the net state
## `lit` / `shadowed` (TowerRules.light_effect, never disabled): the panel keeps the lit /
## shadowed wording then, else (another writer contributed, alone or with light) it shows
## the generic NOW_MODIFIED wording.
static func light_only(def: TowerDef, cfg: GameConfig, lit: bool, shadowed: bool,
		fx: Dictionary) -> bool:
	var light := TowerRules.light_effect(def, cfg, lit, shadowed)
	return fx.get("power_mult", 1.0) == light["power_mult"] \
		and fx.get("interval_mult", 1.0) == light["interval_mult"] \
		and fx.get("miss_add", 0.0) == light["miss_add"] \
		and fx.get("ignore_miss", false) == light["ignore_miss"] \
		and not fx.get("disabled", false)


## LT-30 beam effect as a percent: mundane fire rate (LT-89: base cooldown ticks / the
## ticks at fire_interval_mult - 1, TowerRules.shot_ticks, as the sim fires), occult
## power (power_mult - 1); 0 for a mundane support tower (it never fires), a neutral
## multiplier or an absent block. LT-70: `shadow` reads the shadow block. LT-105: `fx`, when
## given, replaces the light block (a placed tower's channel).
static func beam_percent(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		shadow := false, fx := {}) -> float:
	fx = effect_of(def, cfg, shadow, fx)
	if fx.is_empty():
		return 0.0
	if def.kind == "mundane":
		var m: float = fx["interval_mult"]
		if s.damage <= 0.0 or m <= 0.0:
			return 0.0
		return (float(TowerRules.shot_ticks(s, 1.0)) / TowerRules.shot_ticks(s, m) - 1.0) * 100.0
	return (fx["power_mult"] - 1.0) * 100.0


## LT-43 §5 (Q4): the numbers of the cells the beam changes on a lit tower, keyed like
## row_numbers: mundane "every" (x fire_interval_mult) and "dps"; occult "damage" (per hit;
## a circle: a new unit's DPS, as Simulation._summon gives the units it summons while lit)
## and "dps" (x power_mult). Empty when nothing changes. LT-70: `shadow` takes the shadow
## multipliers (a shadowed tower). LT-105 D7: `fx`, when given, is the tower's modifier
## channel (the numbers the sim fires with); then any kind shows an interval change (a
## shooter's) and a power change, as the sim applies them (light alone changes only the
## interval of a mundane tower and the power of an occult one, as before).
static func lit_numbers(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		sanity_now := -1.0, shadow := false, fx := {}) -> Dictionary:
	var out := {}
	fx = effect_of(def, cfg, shadow, fx)
	if fx.is_empty():
		return out
	# TowerRules.effective in the sim's own order (damage x factor x power, / interval).
	var sanity := sanity_now if s.is_beam() else -1.0
	var now := TowerRules.effective_with(s, cfg, fx, sanity)
	var m: float = fx["interval_mult"]
	# A gate's / circle's cooldown ignores interval_mult (LT-105 Q4).
	if s.damage > 0.0 and m > 0.0 and m != 1.0 and not s.is_banish() and not s.is_summon():
		out["every"] = now["interval"]
		out["dps"] = now["dps"]
	if fx["power_mult"] != 1.0 and (s.damage > 0.0 or s.is_summon() and dps_value(s) > 0.0):
		var pm: float = fx["power_mult"]
		if s.is_summon():
			out["damage"] = now["unit_dps"]
		else:
			out["damage"] = TowerRules.shot_damage(s, 1.0, pm)
		out["dps"] = now["dps"]
	return out


## LT-43 §5: the effects of an occult aura, gate or circle while lit (slow, the taken bonus,
## the armor strip, the banish distance and a new unit's summon_dps x power_mult, as
## Simulation applies them); {} when the beam does not change them. LT-70: `shadow` takes
## shadow.occult_power_mult (a shadowed tower). LT-105 D7: `fx`, when given, is the tower's
## modifier channel; then any aura, gate or circle at power_mult != 1 (the sim's apply_auras
## scales any kind; light gives a mundane one 1.0).
static func lit_effects(def: TowerDef, s: TowerDef.Level, cfg: GameConfig,
		shadow := false, fx := {}) -> Dictionary:
	if fx.is_empty() and def.kind != "occult":
		return {}
	fx = effect_of(def, cfg, shadow, fx)
	if fx.is_empty():
		return {}
	var pm: float = fx["power_mult"]
	if pm == 1.0:
		return {}
	var e := TowerRules.powered_effects(s, pm)  # an aura, a gate or a circle only
	return e if e != s.effects else {}
