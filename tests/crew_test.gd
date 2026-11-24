class_name CrewTest
extends TowerTestBase
## LT-32 (docs/design/LT-32-crew.md §2, §3, §9 "Behaviours the tests slice pins"): the crew
## reserve, crewed builds, hire by day, reserve posts at night and their removal at dawn,
## sell / upgrade on a post, and the crew-off identity. Boards are TowerTestBase's 15x3 strip;
## "crew on" copies the shipped data/crew.json into the config dir, so every number below
## comes from that file (and towers.json), never from memory.

const R := SimCommand.CommandResult
const RIFLE := "rifleman"
const HARP := "harpooner"
const SIGN := "elder_sign"
const CREW_FILE := "crew.json"
const POST_CELL := Vector2i(7, 1)
const WATER := Vector2i(7, 2)

var _on_cfg: GameConfig


## TowerTestBase's board with the shipped crew.json (crew on), edited by `crew_edit(root)`.
func ccfg(crew_edit := Callable()) -> GameConfig:
	if not crew_edit.is_valid() and _on_cfg != null:
		return _on_cfg
	var r := load_edited(func(dir: String) -> void:
		_apply_edits(dir, ROWS, -1, {})
		write_file(dir, CREW_FILE, FileAccess.get_file_as_string("res://data/" + CREW_FILE))
		if crew_edit.is_valid():
			edit(dir, CREW_FILE, crew_edit))
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	if not crew_edit.is_valid():
		_on_cfg = r.config
	return r.config


func csim(cfg: GameConfig = null) -> Simulation:
	var sim := Simulation.new(cfg if cfg != null else ccfg(), SEED)
	sim.state.gold = 100000
	return sim


func _kind(sim: Simulation, kind: String) -> CrewConfig.CrewKind:
	return sim.config.crew.crews[kind]


func _frame(sim: Simulation, kind: String) -> int:
	var k := _kind(sim, kind)
	return sim.config.towers[kind].cost - k.per_tower * k.hire


func _post_crew(sim: Simulation) -> int:
	return sim.config.crew.post.crew


## A night sim (phase WAVE) with `men` reserve men of `kind`, events drained.
func _night(kind := RIFLE, men := -1) -> Simulation:
	var sim := csim()
	sim.state.crew[kind] = _post_crew(sim) if men < 0 else men
	sim.state.phase = SimState.Phase.WAVE
	sim.drain_events()
	return sim


func _types(events: Array[SimEvent]) -> Array[String]:
	var out: Array[String] = []
	for e in events:
		out.append(SimEvent.Type.keys()[e.type])
	return out


func _rng_states(sim: Simulation) -> Array[int]:
	var out: Array[int] = []
	for s: int in SimRng.Stream.values():
		out.append(sim.rng(s).state)
	return out


# --- §9.1: crew off ----------------------------------------------------------------------------

## No crew.json, or crew.json with enabled false: a build pays def.cost and keeps it as the
## refund base, the tower carries no crew, no CREW_* / POST_* event, hire and deploy answer
## NO_CREW, the reserve is empty.
func test_crew_off_builds_as_before_and_answers_no_crew() -> void:
	var off_cfg := ccfg(func(root: Dictionary) -> void: root["enabled"] = false)
	assert_object(off_cfg.crew).is_not_null()
	assert_bool(off_cfg.crew_on()).is_false()
	assert_bool(tconfig().crew_on()).is_false()
	for cfg: GameConfig in [tconfig(), off_cfg]:
		var sim := csim(cfg)
		var cost: int = cfg.towers[RIFLE].cost
		assert_int(sim.build_price(RIFLE)).is_equal(cost)
		assert_int(sim.crew_need(RIFLE)).is_equal(0)
		var gold := sim.state.gold
		var t := build(sim, RIFLE)
		assert_int(sim.state.gold).is_equal(gold - cost)
		assert_int(t.spent).is_equal(cost)
		assert_int(t.crew).is_equal(0)
		assert_dict(sim.crew_reserve()).is_empty()
		assert_int(sim.can_hire(RIFLE)).is_equal(R.NO_CREW)
		assert_int(sim.hire(RIFLE)).is_equal(R.NO_CREW)
		sim.state.phase = SimState.Phase.WAVE
		assert_int(sim.can_deploy(RIFLE, Vector2i(3, 1))).is_equal(R.NO_CREW)
		assert_object(sim.post_def(RIFLE)).is_null()
		var types := _types(sim.drain_events())
		for name in ["CREW_CHANGED", "POST_DEPLOYED", "POST_REMOVED"]:
			assert_array(types).not_contains([name])


# --- §9.2: build price ---------------------------------------------------------------------------

## Crew on, empty reserve: the build pays def.cost in one GOLD_CHANGED "build", TOWER_BUILT
## cost = def.cost, no CREW_CHANGED; the tower holds per_tower men and its refund base is the
## frame (cost - per_tower x hire).
func test_build_with_an_empty_reserve_pays_the_tower_cost_once() -> void:
	var sim := csim()
	var cost: int = sim.config.towers[RIFLE].cost
	assert_int(sim.build_price(RIFLE)).is_equal(cost)
	sim.drain_events()
	var gold := sim.state.gold
	var t := build(sim, RIFLE)
	var evs := sim.drain_events()
	assert_int(sim.state.gold).is_equal(gold - cost)
	var golds := of_type(evs, SimEvent.Type.GOLD_CHANGED)
	assert_int(golds.size()).is_equal(1)
	assert_int(golds[0].data["delta"]).is_equal(-cost)
	assert_str(golds[0].data["reason"]).is_equal("build")
	assert_int(of_type(evs, SimEvent.Type.TOWER_BUILT)[0].data["cost"]).is_equal(cost)
	assert_array(of_type(evs, SimEvent.Type.CREW_CHANGED)).is_empty()
	assert_int(t.crew).is_equal(_kind(sim, RIFLE).per_tower)
	assert_int(t.spent).is_equal(_frame(sim, RIFLE))
	assert_int(sim.crew_reserve()[RIFLE]).is_equal(0)


## With N men of the kind in the reserve a build pays frame + max(0, need - N) x hire and
## takes min(N, need) men (CREW_CHANGED "build"); the gold check uses that price.
func test_build_with_reserve_pays_the_frame_plus_the_missing_crew() -> void:
	var probe := csim()
	var k := _kind(probe, RIFLE)
	var frame := _frame(probe, RIFLE)
	for n in [1, k.per_tower, k.per_tower + 3]:
		var sim := csim()
		sim.state.crew[RIFLE] = n
		var price := frame + maxi(0, k.per_tower - n) * k.hire
		assert_int(sim.build_price(RIFLE)).override_failure_message("n=%d" % n).is_equal(price)
		sim.state.gold = price - 1
		assert_int(sim.can_build(RIFLE, TOWER)).is_equal(R.NOT_ENOUGH_GOLD)
		sim.state.gold = price
		sim.drain_events()
		var t := build(sim, RIFLE)
		var evs := sim.drain_events()
		assert_int(sim.state.gold).override_failure_message("n=%d" % n).is_equal(0)
		assert_int(of_type(evs, SimEvent.Type.TOWER_BUILT)[0].data["cost"]).is_equal(price)
		var take := mini(n, k.per_tower)
		var crews := of_type(evs, SimEvent.Type.CREW_CHANGED)
		assert_int(crews.size()).is_equal(1)
		assert_dict(crews[0].data).is_equal({"kind": RIFLE, "reserve": n - take, "delta": -take,
			"reason": "build"})
		assert_int(sim.crew_reserve()[RIFLE]).is_equal(n - take)
		assert_int(t.crew).is_equal(k.per_tower)
		assert_int(t.spent).is_equal(frame)


## Another kind's reserve does not lower the price; an uncrewed tower costs def.cost.
func test_only_the_towers_own_kind_lowers_its_price() -> void:
	var sim := csim()
	sim.state.crew[HARP] = 5
	assert_int(sim.build_price(RIFLE)).is_equal(sim.config.towers[RIFLE].cost)
	assert_int(sim.build_price(SIGN)).is_equal(sim.config.towers[SIGN].cost)
	assert_int(sim.crew_need(SIGN)).is_equal(0)
	var t := build(sim, SIGN)
	assert_int(t.crew).is_equal(0)
	assert_int(sim.crew_reserve()[HARP]).is_equal(5)


# --- §9.3: hire ----------------------------------------------------------------------------------

## By day: reserve +1, hire money off, [tick, "hire", kind] logged, CREW_CHANGED then
## GOLD_CHANGED "hire"; no RNG draw.
func test_hire_by_day_adds_one_man_for_his_price() -> void:
	var sim := csim()
	var k := _kind(sim, HARP)
	var gold := sim.state.gold
	var states := _rng_states(sim)
	sim.drain_events()
	assert_int(sim.hire(HARP)).is_equal(R.OK)
	var evs := sim.drain_events()
	assert_int(sim.crew_reserve()[HARP]).is_equal(1)
	assert_int(sim.state.gold).is_equal(gold - k.hire)
	assert_array(sim.state.command_log.back()).is_equal([sim.state.tick, "hire", HARP])
	assert_array(_types(evs)).is_equal(["CREW_CHANGED", "GOLD_CHANGED"])
	assert_dict(evs[0].data).is_equal({"kind": HARP, "reserve": 1, "delta": 1, "reason": "hire"})
	assert_int(evs[1].data["delta"]).is_equal(-k.hire)
	assert_str(evs[1].data["reason"]).is_equal("hire")
	assert_array(_rng_states(sim)).is_equal(states)


## Refusals in order: OUTCOME_REACHED, NO_CREW, NOT_ENOUGH_GOLD, NOT_BUILD_PHASE (night,
## last); a refused hire changes nothing.
func test_hire_is_refused_at_night_poor_and_for_no_crew_kind() -> void:
	var sim := csim()
	sim.state.phase = SimState.Phase.WAVE
	sim.drain_events()
	var log_size := sim.state.command_log.size()
	var gold := sim.state.gold
	assert_int(sim.can_hire(RIFLE)).is_equal(R.NOT_BUILD_PHASE)
	assert_int(sim.hire(RIFLE)).is_equal(R.NOT_BUILD_PHASE)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.crew_reserve()[RIFLE]).is_equal(0)
	assert_int(sim.state.command_log.size()).is_equal(log_size)
	assert_array(sim.drain_events()).is_empty()
	sim.state.gold = _kind(sim, RIFLE).hire - 1
	assert_int(sim.can_hire(RIFLE)).is_equal(R.NOT_ENOUGH_GOLD)  # before the phase
	assert_int(sim.can_hire(SIGN)).is_equal(R.NO_CREW)
	assert_int(sim.can_hire("no_such_kind")).is_equal(R.NO_CREW)
	sim.state.outcome = SimState.Outcome.LOST
	assert_int(sim.can_hire(RIFLE)).is_equal(R.OUTCOME_REACHED)


## A logged hire replays to the same reserve and gold.
func test_hire_replays_from_the_command_log() -> void:
	var a := csim()
	assert_int(a.hire(RIFLE)).is_equal(R.OK)
	assert_int(a.hire(HARP)).is_equal(R.OK)
	var b := csim()
	for entry: Array in a.state.command_log:
		assert_int(b.replay_command(entry)).is_equal(R.OK)
	assert_dict(b.crew_reserve()).is_equal(a.crew_reserve())
	assert_int(b.state.gold).is_equal(a.state.gold)


# --- §9.4: deploy --------------------------------------------------------------------------------

## At night a deploy takes post.crew men of the kind, costs nothing, and places a post: a
## SimTower with post = true, the "post" def, crew_kind, crew = post.crew, spent 0, the next
## id; POST_DEPLOYED then CREW_CHANGED "deploy"; no TOWER_BUILT, no GOLD_CHANGED; logged.
func test_deploy_at_night_places_a_post_from_the_reserve_for_free() -> void:
	var sim := _night(HARP, ccfg().crew.post.crew + 1)
	var men := _post_crew(sim)
	var gold := sim.state.gold
	var next_id := sim.state.next_id
	var states := _rng_states(sim)
	assert_int(sim.deploy(HARP, POST_CELL)).is_equal(R.OK)
	var evs := sim.drain_events()
	var t := sim.tower_by_id(sim.state.tower_at[POST_CELL])
	assert_int(t.id).is_equal(next_id)
	assert_bool(t.post).is_true()
	assert_str(t.def.id).is_equal(CrewConfig.POST_ID)
	assert_str(t.crew_kind).is_equal(HARP)
	assert_int(t.crew).is_equal(men)
	assert_int(t.spent).is_equal(0)
	assert_int(t.level).is_equal(0)
	assert_object(t.cell).is_equal(POST_CELL)
	assert_int(sim.state.gold).is_equal(gold)
	assert_int(sim.crew_reserve()[HARP]).is_equal(1)
	assert_array(_types(evs)).is_equal(["POST_DEPLOYED", "CREW_CHANGED"])
	assert_int(evs[0].id).is_equal(t.id)
	assert_dict(evs[0].data).is_equal({"kind": HARP, "cell": POST_CELL, "crew": men})
	assert_dict(evs[1].data).is_equal({"kind": HARP, "reserve": 1, "delta": -men,
		"reason": "deploy"})
	assert_array(sim.state.command_log.back()).is_equal([sim.state.tick, "deploy", HARP, POST_CELL])
	assert_array(_rng_states(sim)).is_equal(states)


## Refusals in order: NO_CREW, NOT_BUILDABLE, OCCUPIED, RESERVE_SHORT, NOT_NIGHT (by day,
## last); a refused deploy changes nothing.
func test_deploy_is_refused_by_day_short_occupied_and_off_the_buildable_cells() -> void:
	var sim := _night()
	sim.state.phase = SimState.Phase.BUILD
	var log_size := sim.state.command_log.size()
	assert_int(sim.can_deploy(RIFLE, POST_CELL)).is_equal(R.NOT_NIGHT)
	assert_int(sim.deploy(RIFLE, POST_CELL)).is_equal(R.NOT_NIGHT)
	assert_bool(sim.state.tower_at.has(POST_CELL)).is_false()
	assert_int(sim.crew_reserve()[RIFLE]).is_equal(_post_crew(sim))
	assert_int(sim.state.command_log.size()).is_equal(log_size)
	assert_array(sim.drain_events()).is_empty()
	sim.state.phase = SimState.Phase.WAVE
	assert_int(sim.can_deploy(SIGN, POST_CELL)).is_equal(R.NO_CREW)
	assert_int(sim.can_deploy(RIFLE, WATER)).is_equal(R.NOT_BUILDABLE)
	assert_int(sim.can_deploy(HARP, POST_CELL)).is_equal(R.RESERVE_SHORT)
	sim.state.crew[RIFLE] = _post_crew(sim) - 1
	assert_int(sim.can_deploy(RIFLE, POST_CELL)).is_equal(R.RESERVE_SHORT)
	sim.state.crew[RIFLE] = _post_crew(sim)
	assert_int(sim.deploy(RIFLE, POST_CELL)).is_equal(R.OK)
	sim.state.crew[RIFLE] = _post_crew(sim)
	assert_int(sim.can_deploy(RIFLE, POST_CELL)).is_equal(R.OCCUPIED)


# --- §9.5: a post is plain riflemen ---------------------------------------------------------------

## A harpooner post fires with the shared post stats (damage, one target, no pierce), not the
## harpooner's; the "post" def is not a tower of the config.
func test_a_post_fires_with_post_stats_whatever_the_crew_kind() -> void:
	var sim := _night(HARP)
	var post := sim.config.crew.post.def
	assert_bool(sim.config.towers.has(CrewConfig.POST_ID)).is_false()
	assert_float(sim.config.towers[HARP].levels[0].damage).is_not_equal(post.levels[0].damage)
	var a := put(sim, "cultist", 7.0)
	var b := put(sim, "cultist", 7.0)
	assert_int(sim.deploy(HARP, POST_CELL)).is_equal(R.OK)
	var t := sim.tower_by_id(sim.state.tower_at[POST_CELL])
	assert_object(t.def).is_same(post)
	var shots := of_type(run(sim, 1), SimEvent.Type.SHOT)
	assert_int(shots.size()).is_equal(1)
	assert_str(shots[0].data["def"]).is_equal(CrewConfig.POST_ID)
	assert_int((shots[0].data["hits"] as Array).size()).is_equal(1)
	var lost := (HUGE_HP - a.hp) + (HUGE_HP - b.hp)
	assert_float(lost).is_equal_approx(post.levels[0].damage, 0.001)


## The light writer reaches a post: under the flare it is lit and fires with the lit
## mundane channel (no miss roll).
func test_the_light_writer_applies_to_a_post() -> void:
	var sim := _night()
	assert_int(sim.deploy(RIFLE, POST_CELL)).is_equal(R.OK)
	var t := sim.tower_by_id(sim.state.tower_at[POST_CELL])
	run(sim, 1)
	assert_bool(t.lit).is_false()
	sim.state.flare_ticks_left = 30
	run(sim, 1)
	assert_bool(t.lit).is_true()
	assert_bool(t.ignore_miss).is_true()


## A post kill is a mundane kill: sanity regains regen.mundane_kill.
func test_a_post_kill_regains_mundane_kill_sanity() -> void:
	var sim := _night()
	sim.state.sanity = 90.0
	var e := put(sim, "cultist", 7.0, 1.0)
	assert_int(sim.deploy(RIFLE, POST_CELL)).is_equal(R.OK)
	var evs := run(sim, 1)
	assert_bool(e.dead).is_true()
	var regen := of_type(evs, SimEvent.Type.SANITY_CHANGED).filter(
		func(x: SimEvent) -> bool: return x.data["reason"] == "mundane_kill")
	assert_int(regen.size()).is_equal(1)
	assert_float(regen[0].data["delta"]).is_equal_approx(sim.config.sanity.regen_mundane_kill, 0.0001)


## A post near a horror enemy drains sanity like a tower (owner decision: posts affect sanity
## like a normal tower); with no post nothing drains.
func test_a_post_near_a_horror_enemy_drains_sanity() -> void:
	for with_post in [false, true]:
		var sim := _night()
		sim.state.sanity = 90.0
		put(sim, "shoggoth", 6.0)
		if with_post:
			assert_int(sim.deploy(RIFLE, POST_CELL)).is_equal(R.OK)
		var drains := of_type(run(sim, 1), SimEvent.Type.SANITY_CHANGED).filter(
			func(x: SimEvent) -> bool: return x.data["reason"] == "horror")
		assert_int(drains.size()).override_failure_message("post %s" % with_post) \
			.is_equal(1 if with_post else 0)


# --- §9.6: dawn, sell and upgrade on a post -------------------------------------------------------

## Dawn removes every post (id order) with POST_REMOVED {kind, cell, reason "dawn"} and
## returns its men (CREW_CHANGED "dawn"), all before WAVE_CLEARED; the cells are free again.
func test_dawn_removes_every_post_and_returns_its_men_before_wave_cleared() -> void:
	var cfg := ccfg()
	var sim := Simulation.new(cfg, SEED)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	sim.state.gold = 100000
	var men := _post_crew(sim)
	for i in men:
		assert_int(sim.hire(HARP)).is_equal(R.OK)
		assert_int(sim.hire(RIFLE)).is_equal(R.OK)
	assert_int(sim.call_wave()).is_equal(R.OK)
	run(sim, 1)
	assert_int(sim.deploy(HARP, Vector2i(3, 1))).is_equal(R.OK)
	assert_int(sim.deploy(RIFLE, Vector2i(9, 1))).is_equal(R.OK)
	var harp_id: int = sim.state.tower_at[Vector2i(3, 1)]
	var rifle_id: int = sim.state.tower_at[Vector2i(9, 1)]
	sim.drain_events()
	assert_int(sim.debug_end_night()).is_equal(R.OK)
	var evs: Array[SimEvent] = []
	for i in 300:
		evs.append_array(run(sim, 1))
		if not of_type(evs, SimEvent.Type.WAVE_CLEARED).is_empty():
			break
	var types := _types(evs)
	var cleared := types.find("WAVE_CLEARED")
	assert_int(cleared).is_greater(-1)
	var removed := of_type(evs, SimEvent.Type.POST_REMOVED)
	assert_array(ids_of(removed)).is_equal([harp_id, rifle_id])
	assert_dict(removed[0].data).is_equal({"kind": HARP, "cell": Vector2i(3, 1), "reason": "dawn"})
	assert_dict(removed[1].data).is_equal({"kind": RIFLE, "cell": Vector2i(9, 1), "reason": "dawn"})
	var back := of_type(evs, SimEvent.Type.CREW_CHANGED).filter(
		func(x: SimEvent) -> bool: return x.data["reason"] == "dawn")
	assert_int(back.size()).is_equal(2)
	for ev in removed + back:
		assert_int(evs.find(ev)).is_less(cleared)
	assert_array(sim.state.towers).is_empty()
	assert_dict(sim.state.tower_at).is_empty()
	assert_int(sim.crew_reserve()[HARP]).is_equal(men)
	assert_int(sim.crew_reserve()[RIFLE]).is_equal(men)


## Sell and upgrade on a post answer NOT_A_TOWER (right after NO_SUCH_TOWER), at night and by
## day alike; upgrade_branches is empty; the post stays.
func test_sell_and_upgrade_on_a_post_answer_not_a_tower() -> void:
	var sim := _night()
	assert_int(sim.deploy(RIFLE, POST_CELL)).is_equal(R.OK)
	var t := sim.tower_by_id(sim.state.tower_at[POST_CELL])
	for phase in [SimState.Phase.WAVE, SimState.Phase.BUILD]:
		sim.state.phase = phase
		assert_int(sim.can_sell_tower(t.id)).is_equal(R.NOT_A_TOWER)
		assert_int(sim.sell_tower(t.id)).is_equal(R.NOT_A_TOWER)
		assert_int(sim.can_upgrade(t.id)).is_equal(R.NOT_A_TOWER)
		assert_int(sim.can_upgrade(t.id, "a")).is_equal(R.NOT_A_TOWER)
		assert_int(sim.upgrade_tower(t.id)).is_equal(R.NOT_A_TOWER)
	assert_array(Array(sim.upgrade_branches(t))).is_empty()
	assert_object(sim.tower_by_id(t.id)).is_same(t)
	assert_int(t.level).is_equal(0)
	assert_int(sim.can_sell_tower(9999)).is_equal(R.NO_SUCH_TOWER)
	# set_target_priority on a post is allowed (a plain shooter picks targets).
	assert_int(sim.set_target_priority(t.id, "strongest")).is_equal(R.OK)


# --- §9.7: sell a crewed tower ---------------------------------------------------------------------

## Selling refunds the sell ratio of frame + upgrades (no crew money) and returns the tower's
## men to the reserve (CREW_CHANGED "sell", after TOWER_SOLD and the gold).
func test_sell_refunds_a_share_of_the_frame_and_returns_the_crew() -> void:
	var sim := csim()
	var k := _kind(sim, RIFLE)
	var t := build(sim, RIFLE)
	assert_int(sim.upgrade_tower(t.id)).is_equal(R.OK)
	var up: int = sim.config.towers[RIFLE].levels[1].upgrade_cost
	var want := roundi((_frame(sim, RIFLE) + up) * sim.config.economy.sell_refund_ratio)
	assert_int(sim.sell_refund(t)).is_equal(want)
	sim.drain_events()
	var gold := sim.state.gold
	assert_int(sim.sell_tower(t.id)).is_equal(R.OK)
	var evs := sim.drain_events()
	assert_int(sim.state.gold).is_equal(gold + want)
	var crews := of_type(evs, SimEvent.Type.CREW_CHANGED)
	assert_int(crews.size()).is_equal(1)
	assert_dict(crews[0].data).is_equal({"kind": RIFLE, "reserve": k.per_tower,
		"delta": k.per_tower, "reason": "sell"})
	assert_int(evs.find(crews[0])).is_greater(evs.find(of_type(evs, SimEvent.Type.TOWER_SOLD)[0]))
	assert_int(sim.crew_reserve()[RIFLE]).is_equal(k.per_tower)
	# The men come back for the next build: it pays only the frame.
	assert_int(sim.build_price(RIFLE)).is_equal(_frame(sim, RIFLE))
