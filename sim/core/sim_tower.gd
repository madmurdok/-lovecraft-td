class_name SimTower
extends RefCounted
## One placed tower in the simulation (LT-6; design note LT-4 §1.4, §6).
## L1 only for now: upgrades and branches (later content) change `level` and add to `spent`.

var id: int  ## shared entity id counter (SimState.next_id)
var def: TowerDef
var cell: Vector2i
var level := 0  ## index into def.levels (0 = L1)
var spent := 0  ## total gold paid for this tower (build + upgrades); the sell refund base
var build_tick := 0
## Ticks until the tower may fire again; 0 = ready. A new tower is ready at once.
var cooldown_ticks := 0

## Disable/harass timers (tower_harass, tower_lift, ...) added by later tasks.
var status: Dictionary = {}


func stats() -> TowerDef.Level:
	return def.levels[level]


## Cell centre in cell units (same frame as SimRoute.position_at).
func centre() -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)
