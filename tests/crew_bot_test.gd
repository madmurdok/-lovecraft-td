class_name CrewBotTest
extends SimTestBase
## LT-32 §5: the bots and crew. The two optional tunables (crew_reserve, post_min_live), the
## day hire policy, the night post policy, and the RUN line: crew_reserve 0 plays exactly as
## crew off; with a reserve the bot hires and deploys, and towers_final / the lit and shadow
## tower ticks count real towers only (44e7b65). Runs are capped (_max_ticks) to keep the
## suite short; the cap is the same for both arms of a comparison.

const BOT_PATH := "res://tools/bot_runs.gd"
const Strategies := preload("res://tools/bot/bot_strategies.gd")
const Table := preload("res://tools/bot/strategy_table.gd")
const R := SimCommand.CommandResult
const RIFLE := "rifleman"
const SEEDS := [1000, 1001, 1002]
const STRAT := "mundane"
## One bot wave's worth of ticks (bot_runs.gd TICKS_PER_WAVE = 6 * 60 * 30): a few days and
## nights of a mundane run.
const CAP := 6 * 60 * 30

var _bot_script: GDScript
var _bots: Array[Object] = []


func after_test() -> void:
	for b in _bots:
		if is_instance_valid(b):
			b.free()
	_bots.clear()


func _fresh() -> GameConfig:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	return r.config


## The shipped table with tunables patched by `tunables`.
func _table(tunables := {}) -> Table:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Table.DEFAULT_PATH))
	for k: String in tunables:
		raw["tunables"][k] = tunables[k]
	var t := Table.parse_text(JSON.stringify(raw))
	assert_array(t.errors).is_empty()
	return t


## A bot harness on `cfg` (constructor skipped), capped at CAP ticks, playing `table`
## (null: the shipped default).
func _bot(cfg: GameConfig, table: Table = null) -> Object:
	if _bot_script == null:
		var src := FileAccess.get_file_as_string(BOT_PATH)
		assert_bool(src.contains("func _init() -> void:")).is_true()
		_bot_script = GDScript.new()
		_bot_script.source_code = src.replace("func _init() -> void:", "func _unused_init() -> void:")
		assert_int(_bot_script.reload()).is_equal(OK)
	var b: Object = _bot_script.new()
	_bots.append(b)
	b.set("_cfg", cfg)
	b.set("_max_ticks", CAP)
	if table != null:
		b.set("_table", table)
	return b


func _strat(cfg: GameConfig, table: Table) -> Strategies:
	var st := Strategies.new()
	st.cfg = cfg
	st.table = table
	st.upgrades = true
	st.lighthouse = true
	st.flare = true
	return st


## A crew-on day sim (WaveDirector, first BUILD), with `gold`.
func _day(cfg: GameConfig, gold: int) -> Simulation:
	var sim := Simulation.new(cfg, 1000)
	sim.set_spawner(WaveDirector.new(cfg.waves))
	sim.step()
	assert_int(sim.state.phase).is_equal(SimState.Phase.BUILD)
	sim.state.gold = gold
	sim.drain_events()
	return sim


# --- tunables ------------------------------------------------------------------------------------

## crew_reserve / post_min_live are optional (defaults 0 / 4) and must be whole counts >= 0.
func test_crew_tunables_are_optional_counts() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Table.DEFAULT_PATH))
	raw["tunables"].erase("crew_reserve")
	raw["tunables"].erase("post_min_live")
	var t := Table.parse_text(JSON.stringify(raw))
	assert_array(t.errors).is_empty()
	assert_int(t.crew_reserve).is_equal(0)
	assert_int(t.post_min_live).is_equal(4)
	assert_int(_table({"crew_reserve": 3, "post_min_live": 2}).crew_reserve).is_equal(3)
	for bad: Variant in [-1, 1.5, "2"]:
		raw["tunables"]["crew_reserve"] = bad
		var b := Table.parse_text(JSON.stringify(raw))
		assert_bool(b.errors.any(func(e: String) -> bool: return e.contains("crew_reserve"))) \
			.override_failure_message("%s accepted" % [bad]).is_true()


# --- policy --------------------------------------------------------------------------------------

## By day the bot hires the cheapest crew kind until the whole reserve holds crew_reserve
## men; with crew_reserve 0 it hires nobody.
func test_day_hires_the_cheapest_kind_up_to_crew_reserve() -> void:
	var cfg := _fresh()
	var cheapest := ""
	for kind: String in cfg.crew.crews:
		if cheapest == "" or cfg.crew.crews[kind].hire < cfg.crew.crews[cheapest].hire:
			cheapest = kind
	var sim := _day(cfg, 0)
	sim.state.gold = 100000
	_strat(cfg, _table({"crew_reserve": 3})).hire_reserve(sim)
	assert_int(sim.crew_reserve()[cheapest]).is_equal(3)
	var total := 0
	for kind: String in sim.crew_reserve():
		total += sim.crew_reserve()[kind]
	assert_int(total).is_equal(3)
	var none := _day(cfg, 100000)
	_strat(cfg, _table({"crew_reserve": 0})).hire_reserve(none)
	for kind: String in none.crew_reserve():
		assert_int(none.crew_reserve()[kind]).is_equal(0)


## At night, with fewer than post_min_live live enemies nothing is deployed; at the threshold
## every post the reserve allows is deployed (reserve left below a post's crew).
func test_night_deploys_posts_at_post_min_live() -> void:
	var cfg := _fresh()
	var men := cfg.crew.post.crew
	var table := _table({"crew_reserve": 2 * men, "post_min_live": 4})
	for live in [3, 4]:
		var sim := _day(cfg, 0)
		sim.state.crew[RIFLE] = 2 * men
		assert_int(sim.call_wave()).is_equal(R.OK)
		for e in sim.state.enemies:
			e.dead = true
		for i in live:
			sim.spawn_enemy("cultist", false)
		sim.drain_events()
		_strat(cfg, table).act(sim, STRAT, 0, {})
		var posts := sim.state.towers.filter(func(t: SimTower) -> bool: return t.post)
		assert_int(posts.size()).override_failure_message("live %d" % live) \
			.is_equal(0 if live < 4 else 2)
		assert_int(sim.crew_reserve()[RIFLE]).is_equal(2 * men if live < 4 else 0)


## A post is never upgraded nor counted as a tower by the policy.
func test_posts_are_not_towers_for_the_policy() -> void:
	var cfg := _fresh()
	var sim := _day(cfg, 0)
	sim.state.crew[RIFLE] = cfg.crew.post.crew
	assert_int(sim.call_wave()).is_equal(R.OK)
	assert_int(sim.deploy(RIFLE, _free_cell(sim))).is_equal(R.OK)
	assert_int(Strategies.tower_count(sim)).is_equal(0)
	assert_array(_strat(cfg, _table()).next_upgrade(sim, STRAT)).is_empty()


func _free_cell(sim: Simulation) -> Vector2i:
	var m := sim.state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m.is_buildable(c) and not sim.state.tower_at.has(c):
				return c
	return Vector2i(-1, -1)


# --- RUN lines -----------------------------------------------------------------------------------

## §9.8: with the shipped table (crew_reserve 0) every RUN line equals the crew-off run's
## (crew.json enabled false), on 3 seeds.
func test_crew_reserve_zero_run_lines_equal_crew_off() -> void:
	var on_cfg := _fresh()
	var off_cfg := _fresh()
	off_cfg.crew.enabled = false
	assert_bool(on_cfg.crew_on()).is_true()
	assert_bool(off_cfg.crew_on()).is_false()
	for s: int in SEEDS:
		var on: Dictionary = _bot(on_cfg).call("_play", STRAT, s)
		var off: Dictionary = _bot(off_cfg).call("_play", STRAT, s)
		assert_dict(on).override_failure_message("seed %d:\non  %s\noff %s" % [s, on, off]) \
			.is_equal(off)
		assert_int(on["crew_hired"]).is_equal(0)
		assert_int(on["posts"]).is_equal(0)


## With a reserve the bot hires and deploys; the crew keys add up; towers_final and the lit /
## shadow tower ticks count real towers only (posts excluded, 44e7b65).
func test_a_crew_reserve_hires_deploys_and_posts_stay_out_of_tower_metrics() -> void:
	var cfg := _fresh()
	var b := _bot(cfg, _table({"crew_reserve": 2 * cfg.crew.post.crew}))
	var seen := {"real_lit": 0, "real_shadow": 0, "post_lit": 0, "post_shadow": 0,
		"post_ticks": 0, "post_shots": 0}
	var last := {}
	b.set("_event_sink", func(sim: Simulation, evs: Array[SimEvent]) -> void:
		for ev in evs:
			if ev.type == SimEvent.Type.SHOT and sim.tower_by_id(ev.id) != null \
					and sim.tower_by_id(ev.id).post:
				seen["post_shots"] += 1
		var any_post := false
		for t in sim.state.towers:
			var pre := "post_" if t.post else "real_"
			any_post = any_post or t.post
			if t.lit:
				seen[pre + "lit"] += 1
			if t.shadowed:
				seen[pre + "shadow"] += 1
		if any_post:
			seen["post_ticks"] += 1
		var standing := {}
		for t in sim.state.towers:
			if not t.post:
				var key := "%s_%s" % [t.def.id, t.branch if t.level >= TowerDef.LEVEL_COUNT \
					else "L%d" % (t.level + 1)]
				standing[key] = standing.get(key, 0) + 1
		last["standing"] = standing
		last["posts"] = sim.state.towers.filter(func(t: SimTower) -> bool: return t.post).size()
		# End the run at night with posts standing, once a post was lit or shadowed, so
		# towers_final and the tower ticks meet posts (the harness reads outcome != NONE).
		if last["posts"] > 0 and seen["post_lit"] + seen["post_shadow"] > 0 \
				and seen["post_shots"] > 0:
			sim.state.outcome = SimState.Outcome.LOST)
	var run_line: Dictionary = b.call("_play", STRAT, 1000)
	assert_int(run_line["crew_hired"]).is_greater(0)
	var cheapest := -1
	for kind: String in cfg.crew.crews:
		var h: int = cfg.crew.crews[kind].hire
		cheapest = h if cheapest < 0 else mini(cheapest, h)
	assert_int(run_line["crew_gold"]).is_equal(run_line["crew_hired"] * cheapest)
	assert_int(run_line["posts"]).is_greater(0)
	assert_int(run_line["post_shots"]).is_greater_equal(seen["post_shots"])
	assert_int(seen["post_shots"]).is_greater(0)
	assert_int(seen["post_ticks"]).is_greater(0)
	assert_int(run_line["lit_tower_ticks"]).is_equal(seen["real_lit"])
	assert_int(run_line["shadow_tower_ticks"]).is_equal(seen["real_shadow"])
	assert_dict(run_line["towers_final"]).is_equal(last["standing"])
	for key: String in run_line["towers_final"]:
		assert_bool(key.begins_with(CrewConfig.POST_ID + "_")).override_failure_message(key) \
			.is_false()
	assert_int(last["posts"]).override_failure_message("the run must end at night with "
		+ "posts standing, or towers_final never meets one").is_greater(0)
	# Non-vacuous: some post stood lit or shadowed, so counting posts would change a metric.
	assert_int(seen["post_lit"] + seen["post_shadow"]).override_failure_message(
		"no post was ever lit or shadowed: %s" % seen).is_greater(0)
