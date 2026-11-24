class_name TowerLiftTrait
extends EnemyTrait
## LT-117 (design note docs/design/LT-117-tower-lift.md §1): from wave `from_wave` on, a real
## night-gaunt lifts once the first tower it flies over (the tower on the cell under its
## position) whose lift timer is not running, and drops it on a free buildable cell exactly
## `drop_cells` topology steps away, drawn uniformly on the LIFT stream; no free cell there:
## the next smaller ring, down to 1; none at all: the tower stays (to == from). The tower is
## disabled for `disable_seconds` from the lift tick (its own timer, TraitSystem.near_tower),
## whatever happens to the gaunt. A fake never lifts (it moves no real tower or stream).

const ID := "tower_lift"
## e.status key: this gaunt has used its one lift.
const DONE := "tower_lift_done"


func id() -> String:
	return ID


func params() -> PackedStringArray:
	return PackedStringArray(["from_wave", "drop_cells", "disable_seconds"])


func hooks() -> int:
	return NEAR_TOWER


func parse_params(r: ConfigReader, p: Dictionary, path: String) -> Dictionary:
	var out := {}
	out["from_wave"] = float(r.req_int(p, "from_wave", path, 1))
	out["drop_cells"] = float(r.req_int(p, "drop_cells", path, 1))
	var n := r.errors.size()
	var secs := r.req_number(p, "disable_seconds", path, 0.0, INF, true)
	if r.errors.size() == n and secs < SimTime.DT - 1e-9:  # 1e-9: DT written out in JSON rounds just below DT
		r.error(ConfigReader.join(path, "disable_seconds"),
			"must be at least one tick (%s s), got %s" % [SimTime.DT, secs])
	out["disable_seconds"] = secs
	return out


## Gates first (fake, used, wave), so below from_wave nothing is read, drawn or emitted.
## One LIFT draw per lift whose ring has candidates (SimRng.randi_range(0, 0) draws nothing,
## so a one-cell ring consumes no state). LT-32 Q3b: a night post is never a target (the
## gaunt keeps its one lift for a tower).
func near_tower(host: TraitHost, e: SimEnemy, p: Dictionary) -> void:
	if e.is_fake or e.status.has(DONE) or host.wave() < int(p["from_wave"]):
		return
	var t := host.tower_under(e)
	if t == null or t.post or t.lift_ticks_left > 0:
		return
	e.status[DONE] = true
	var to := t.cell
	for ring in range(int(p["drop_cells"]), 0, -1):
		var cands := host.drop_candidates(t, ring)
		if not cands.is_empty():
			to = cands[host.randi_range(e, SimRng.Stream.LIFT, 0, cands.size() - 1)]
			break
	host.lift_tower(t, to, SimTime.ticks(p["disable_seconds"]), e.id)
