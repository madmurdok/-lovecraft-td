class_name SimTower
extends RefCounted
## One placed tower in the simulation (LT-6; design note LT-4 §1.4, §6).
## Upgrades (LT-24, Simulation.upgrade_tower) raise `level`, set `branch` at L3 and add to
## `spent`. Simulation.set_target_priority (LT-31) sets `target_priority`.

## Target priority modes (LT-31), in panel order: "first" = closest to the lighthouse
## (least route left), "strongest" = highest current hp, "fastest" = highest current speed.
const TARGET_PRIORITIES: PackedStringArray = ["first", "strongest", "fastest"]
const DEFAULT_TARGET_PRIORITY := "first"

var id: int  ## shared entity id counter (SimState.next_id)
var def: TowerDef
var cell: Vector2i
var level := 0  ## 0 = L1, 1 = L2 (indices into def.levels), 2 = L3 (def.branches[branch])
var branch := ""  ## "" below L3; "a" or "b" at L3
var spent := 0  ## total gold paid for this tower (build + upgrades); the sell refund base
var build_tick := 0
## Ticks until the tower may fire again; 0 = ready. A new tower is ready at once.
var cooldown_ticks := 0
## One of TARGET_PRIORITIES; whom _fire_towers picks among the live enemies in range.
var target_priority := DEFAULT_TARGET_PRIORITY
## LT-29 §1.2 (Gangsters): round-robin position over the ranked `burst_targets`; persists
## between shots, wraps to the ranked set's size at each shot.
var burst_index := 0
## LT-30: inside a lighthouse beam (centre test, slot 2); persists between ticks, a flip
## emits TOWER_LIT {lit}.
var lit := false

## Disable/harass timers (tower_harass, tower_lift, ...) added by later tasks.
var status: Dictionary = {}


func stats() -> TowerDef.Level:
	if level >= TowerDef.LEVEL_COUNT:
		return def.branches[branch]
	return def.levels[level]


## Cell centre in cell units (same frame as SimRoute.position_at).
func centre() -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5)
