class_name EconomyConfig
extends RefCounted
## economy.json (GDD §5.1, §5.2): gold rules and lighthouse HP.

const FIELDS := ["starting_gold", "wave_bonus", "sell_refund_ratio",
	"early_call_gold_per_second", "lighthouse"]

var starting_gold: int  ## >= 0
var wave_bonus_base: int  ## wave bonus = base + per_wave * wave number
var wave_bonus_per_wave: int
var sell_refund_ratio: float  ## share of total spent refunded on sell, 0..1
var early_call_gold_per_second: float  ## bonus per second left on the build timer
var lighthouse_hp: int  ## >= 1


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
	c.early_call_gold_per_second = r.req_number(root, "early_call_gold_per_second", "", 0.0)
	var lighthouse: Variant = r.req_object(root, "lighthouse", "")
	if lighthouse != null:
		r.check_keys(lighthouse, ["hp"], "lighthouse")
		c.lighthouse_hp = r.req_int(lighthouse, "hp", "lighthouse", 1)
	return c
