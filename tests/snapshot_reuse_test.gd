class_name SnapshotReuseTest
extends TowerTestBase
## LT-85/S15 (controls: LT-85-controls.md, S18): snapshot(prev) equals snapshot() on every
## TowerRecord field (found by reflection, so a new field missing from the reuse path fails
## here), a snapshot held from an earlier tick never changes after later builds that reuse
## records, and SimSnapshot.enemy(id) finds every live id and nothing else.

const RIFLE := "rifleman"
const SIGN := "elder_sign"


## name -> value of every script variable of `o`.
func _fields(o: Object) -> Dictionary:
	var out := {}
	for p: Dictionary in o.get_script().get_script_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			out[String(p["name"])] = o.get(String(p["name"]))
	return out


func _diffs(a: TowerRecord, b: TowerRecord) -> Array[String]:
	var out: Array[String] = []
	var fa := _fields(a)
	var fb := _fields(b)
	if fa.keys() != fb.keys():
		out.append("field sets differ")
	for k: String in fa:
		if not is_same(fa[k], fb.get(k)) and fa[k] != fb.get(k):
			out.append("%s: %s vs %s" % [k, fa[k], fb.get(k)])
	return out


## Pokes the tower state on a schedule of ticks: every record field changes at least once.
func _poke(sim: Simulation, k: int, ids: Array[int]) -> void:
	var a := sim.tower_by_id(ids[0])
	var b := sim.tower_by_id(ids[1]) if sim.tower_by_id(ids[1]) != null else null
	var prios := TowerRecord.TARGET_PRIORITIES
	match k:
		4: sim.upgrade_tower(ids[0])
		8: a.target_priority = prios[1 % prios.size()]
		12: a.lit = true
		16: a.lit = false
		20: a.shadowed = true
		24: a.disabled = true
		28: a.disabled = false
		32: a.crew = 2
		36: a.crew_kind = "probe_kind"
		40: a.post = true
		44: a.target_priority = prios[prios.size() - 1]
		48: sim.sell_tower(ids[1])
		52: ids.append(build(sim, RIFLE, Vector2i(11, 1)).id)
		56: sim.upgrade_tower(ids[0])
		58: a.shadowed = false
		60: a.branch = "probe_branch"
		_: pass


func _sim_with_towers() -> Array:
	var sim := tsim()
	sim.state.gold = 100000
	var ids: Array[int] = [build(sim, RIFLE, Vector2i(3, 1)).id,
		build(sim, RIFLE, Vector2i(7, 1)).id]
	return [sim, ids]


func test_snapshot_with_prev_equals_snapshot_on_every_record_field_every_tick() -> void:
	var made := _sim_with_towers()
	var sim: Simulation = made[0]
	var ids: Array[int] = made[1]
	var prev := sim.snapshot()
	var shared := 0
	var rebuilt := 0
	var seen := {}
	for k in 62:
		_poke(sim, k, ids)
		var fresh := sim.snapshot()
		var reused := sim.snapshot(prev)
		assert_int(reused.towers.size()).is_equal(fresh.towers.size())
		for i in fresh.towers.size():
			var diffs := _diffs(reused.towers[i], fresh.towers[i])
			assert_array(diffs).override_failure_message("tick %d tower %d: %s" % [
				k, fresh.towers[i].id, diffs]).is_empty()
			if reused.towers[i] == prev.tower(fresh.towers[i].id):
				shared += 1
			else:
				rebuilt += 1
			for f: String in _fields(fresh.towers[i]):
				seen["%s=%s" % [f, fresh.towers[i].get(f)]] = true
		sim.step()
		prev = reused
	# The run must exercise both paths and change every field, or it proves nothing.
	assert_int(shared).is_greater(0)
	assert_int(rebuilt).is_greater(0)
	for f: String in _fields(prev.towers[0]):
		var values := 0
		for key: String in seen:
			if key.begins_with(f + "="):
				values += 1
		if f != "id" and f != "def" and f != "cell" and f != "centre":
			assert_int(values).override_failure_message("field %s never changed" % f) \
				.is_greater(1)


func test_a_held_snapshot_never_changes_after_later_builds_that_reuse_records() -> void:
	var made := _sim_with_towers()
	var sim: Simulation = made[0]
	var ids: Array[int] = made[1]
	var held: Array = []  # [snapshot, per-tower field dicts at build time]
	var prev: SimSnapshot = null
	for k in 62:
		_poke(sim, k, ids)
		var snap := sim.snapshot(prev)
		var rows: Array = []
		for r in snap.towers:
			rows.append(_fields(r))
		held.append([snap, rows, snap.towers.duplicate()])
		sim.step()
		prev = snap
	for h: Array in held:
		var snap: SimSnapshot = h[0]
		assert_int(snap.towers.size()).is_equal(h[1].size())
		for i in snap.towers.size():
			assert_bool(snap.towers[i] == h[2][i]).is_true()
			var now := _fields(snap.towers[i])
			for key: String in now:
				assert_bool(is_same(now[key], h[1][i][key]) or now[key] == h[1][i][key]) \
					.override_failure_message("tick %d tower %d field %s changed" % [
						snap.tick, snap.towers[i].id, key]).is_true()


func test_enemy_lookup_finds_every_live_id_and_null_for_dead_and_unknown_ids() -> void:
	var sim := tsim()
	var ever: Array[int] = []
	var live: Array[int] = []
	for k in 30:
		if k % 3 == 0:
			for j in 1 + k % 2:
				var e := put(sim, "cultist", 1.0 + j)
				ever.append(e.id)
				live.append(e.id)
		if k % 5 == 4 and not live.is_empty():
			sim.apply_damage(live[(k * 7) % live.size()], 1.0e9, "test")
		var snap := sim.snapshot()
		var now: Array[int] = []
		for r in snap.enemies:
			now.append(r.id)
		for id in ever:
			var found := snap.enemy(id)
			if id in now:
				assert_object(found).override_failure_message("tick %d id %d" % [k, id]).is_not_null()
				assert_int(found.id).is_equal(id)
				assert_object(found).is_same(snap.enemies[now.find(id)])
			else:
				assert_object(found).override_failure_message("tick %d dead id %d" % [k, id]).is_null()
		for id in [-5, -1, 0, 987654, ever.max() + 1]:
			if not id in now:
				assert_object(snap.enemy(id)).is_null()
		sim.step()
		live = []
		for e in sim.state.enemies:
			if e.is_live():
				live.append(e.id)
	assert_int(ever.size()).is_greater(8)
	assert_int(live.size()).is_less(ever.size())
