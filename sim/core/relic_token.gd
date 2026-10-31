class_name RelicToken
extends RefCounted
## LT-27 §1.3: a relic dropped at a kill, flying to the HUD stash. Real and ghost tokens
## (from fakes) look the same here; only Simulation knows which is which.

var id: int  ## from SimState.next_token_id
var kind: String  ## relic kind id
var at: Vector2  ## where the enemy died, in cell units (like enemy_position)
var drop_tick: int
var arrive_tick: int  ## drop_tick + ticks(token_fly_seconds); a real token is credited then
