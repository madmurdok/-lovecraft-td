class_name EconomySystem
extends RefCounted
## LT-80 (B5 seed of LT-65 §3.1 Economy): owns gold. Until B6 it holds only add_gold, the
## one writer of state.gold, so Light and Sanity reach gold without the sim facade.

var _ctx: SimContext
var _state: SimState
var _config: GameConfig


func _init(ctx: SimContext) -> void:
	_ctx = ctx
	_state = ctx.state
	_config = ctx.config
	_state.gold = _config.economy.starting_gold


## Every money change ("gold" internally, LT-27 §2) goes through here: GOLD_CHANGED {delta,
## gold, reason}; `id` is the tower (build/sell/upgrade) it is about, 0 for the dawn wage
## ("wave_bonus"), a relic sale ("relic_sale") or the buyout. Kills pay no money since LT-27.
func add_gold(delta: int, reason: String, id: int) -> void:
	if delta == 0:
		return
	_state.gold += delta
	_ctx.emit(SimEvent.Type.GOLD_CHANGED, id, {"delta": delta, "gold": _state.gold, "reason": reason})
