class_name SimEvent
extends RefCounted
## A one-shot fact the sim reports to scenes and tests (design note LT-4 §2).

## New types are appended so existing values never change.
enum Type {SPAWNED, LEAKED, DIED, OUTCOME, TOWER_BUILT, TOWER_SOLD, GOLD_CHANGED, SHOT,
		BUILD_STARTED, WAVE_STARTED, WAVE_CLEARED, SANITY_CHANGED, SANITY_STATE_CHANGED,
		FAKE_DISSOLVED, TOWER_UPGRADED, TARGET_PRIORITY_SET,
		## LT-23 {delta, cap, reason: "build" | "upgrade" | "sell"}; id = the tower
		SANITY_CAP_CHANGED,
		## LT-27 §1.3, id = the token: {token, kind, at, arrive_tick} (same for real and fake);
		## {token} (a ghost token dissolved); {kind, delta, count, reason: "kill" | "sell",
		## token (kill only)}
		RELIC_DROPPED, RELIC_VANISHED, RELICS_CHANGED,
		## LT-30, id 0: {level, beams, cost}; id = the tower: {lit}; id 0: {ticks, cooldown};
		## id 0: {delta, oil, reason: "buy" | "flare"}
		LIGHTHOUSE_UPGRADED, TOWER_LIT, FLARE_FIRED, OIL_CHANGED,
		## LT-47, id = the blast (SimState.next_blast_id): {tower, def, at, radius, hits}
		## when a fused charge (SHOT {fuse: true, blast}) explodes; hits in id order
		BLAST}

var type: Type
var tick: int
var id: int  ## entity id; 0 when the event is not about an entity (OUTCOME)
var data: Dictionary


func _init(p_type: Type, p_tick: int, p_id: int, p_data: Dictionary = {}) -> void:
	type = p_type
	tick = p_tick
	id = p_id
	data = p_data


func _to_string() -> String:
	return "%s@%d#%d%s" % [Type.keys()[type], tick, id, data]
