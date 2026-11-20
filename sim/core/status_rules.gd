class_name StatusRules
extends RefCounted
## LT-106 T8: the enemy statuses kept in SimEnemy.status, one row each; row order is marker
## order (SimEnemy.markers). Ticked in slot 2 by CombatSystem.tick_statuses. A trait with a
## visible timer adds one row (its marker).

## status id -> {keys: the e.status keys it owns, ticks: the key whose value > 0 means
## active, tick: "pulse" (bleed: pulses through apply_damage, every key erased at 0) or
## "countdown" (erased at 0), marker: the presentation marker, "" = none}.
const ROWS := {
	"bleed": {"keys": ["bleed_ticks", "bleed_dps", "bleed_pulse", "bleed_source"],
		"ticks": "bleed_ticks", "tick": "pulse", "marker": "bleed"},  # LT-29
	"banish_immune": {"keys": ["banish_immune_ticks"], "ticks": "banish_immune_ticks",
		"tick": "countdown", "marker": "sealed"},  # LT-51: a gate cannot banish it now
	"pull_immune": {"keys": ["pull_immune_ticks"], "ticks": "pull_immune_ticks",
		"tick": "countdown", "marker": ""},  # LT-29
}

## The countdown keys in tick_statuses order (pre-LT-106 CombatSystem.IMMUNITY_KEYS order).
const COUNTDOWN_KEYS: PackedStringArray = ["pull_immune_ticks", "banish_immune_ticks"]
