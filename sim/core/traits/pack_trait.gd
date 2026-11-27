class_name PackTrait
extends EnemyTrait
## LT-63: a spawn event brings min..max of this enemy (integers >= 1), one by one: member k
## enters k x spacing_s seconds after the first (> 0 and at least one tick). Every member's
## pack_of is the first member's id. The count is rolled on SPAWN, or on SANITY for a fake
## (LT-12 §2), once per spawn event; queued members do not roll again.

const ID := "pack"


func id() -> String:
	return ID


func params() -> PackedStringArray:
	return PackedStringArray(["min", "max", "spacing_s"])


func hooks() -> int:
	return ON_SPAWN


func parse_params(r: ConfigReader, p: Dictionary, path: String) -> Dictionary:
	var out := {}
	var n := r.errors.size()
	var lo := r.req_int(p, "min", path, 1)
	var hi := r.req_int(p, "max", path, 1)
	if r.errors.size() == n and hi < lo:
		r.error(ConfigReader.join(path, "max"), "must be >= min (%d), got %d" % [lo, hi])
	out["min"] = float(lo)
	out["max"] = float(hi)
	n = r.errors.size()
	var spacing := r.req_number(p, "spacing_s", path, 0.0, INF, true)
	if r.errors.size() == n and spacing < SimTime.DT - 1e-9:  # 1e-9: DT written out in JSON (0.0333...) rounds just below DT
		r.error(ConfigReader.join(path, "spacing_s"),
			"must be at least one tick (%s s), got %s" % [SimTime.DT, spacing])
	out["spacing_s"] = spacing
	return out


## LT-106 T6: the one draw comes right after the first member's _enter (which draws
## nothing), so the RNG stream is the one of the pre-LT-106 draw-then-enter order.
func on_spawn(host: TraitHost, e: SimEnemy, p: Dictionary, from_event: bool) -> void:
	if not from_event:
		return
	var count := host.randi_range(e, SimRng.Stream.SPAWN, int(p["min"]), int(p["max"]))
	e.pack_of = e.id
	var spacing := SimTime.ticks(p["spacing_s"])
	var now := host.tick()
	for k in range(1, count):
		host.queue_pack_member(now + k * spacing, e.def, e.is_fake, e.id, e.route_id)
