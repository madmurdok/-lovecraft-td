extends SceneTree
## Headless bot harness for the playtest baseline (LT-15). Run:
##   $GODOT --headless --path . -s res://tools/bot_runs.gd -- [--seeds=10] [--out=<file>]
##   [--data=<dir>] (a config directory other than res://data, e.g. a tuning variant)
##   [--upgrades=0] (never upgrade: the pre-LT-24 baseline; RUN lines then carry no
##   "upgrades"/"upgrade_gold" keys. Since LT-27 the economy differs, so no run compares
##   byte for byte with a pre-LT-27 harness; only the key set does)
##   [--branch=<tower>:<a|b>[,<tower>:<a|b>...]] (LT-29: override the rows' branches for these
##   tower def ids in every strategy, e.g. --branch=rifleman:b,harpooner:b; other towers keep
##   the strategy's pick; a branch other than a or b is an error)
##   [--strategies=<name>[,<name>...]] (LT-56: play only these strategies, in the table's
##   order; an unknown name is an error. tools/balance/ runs one strategy per process)
##   [--bot-strategies=<path>] (LT-112: play the strategy table in this file instead of
##   tools/bot/strategies.json; validated like the default, a bad file quits 1 before any run.
##   Set by tools/balance/ for a variant with a "bot" key)
## For each strategy x seed it plays one full run on data/ with a fresh Simulation +
## WaveDirector and prints one "RUN {json}" line per run, then a "SUMMARY {json}" line.
##
## Strategies (LT-101): one row each in tools/bot/strategies.json, in play order, with its
## description (`about`); the bot builds the next item of its order (`prefix`, then `cycle`
## repeated) as soon as it can pay for it. Cap guard (LT-23 §4, rows with `cap_floor`): an
## occult build or upgrade only while sanity_cap - its reserve delta >= the row's cap_floor;
## a blocked occult build is skipped (`on_blocked: "skip"`, mixed) or replaced by the row's
## `fallback` tower while the run has fewer than `fallback_max` of them, otherwise the bot
## tries an upgrade that passes the guard and else saves its gold (`"fallback"`, occult).
## Rows with `buy_sanity` try buy_sanity() in madness (refused under the "permanent" exit rule).
## Placement (greedy): the free buildable cell with the most path cells whose centre is
## within the tower's L1 range (and not inside its L1 min_range, LT-48); ties go to the
## lowest row-major cell. No sells.
## Upgrades (LT-24 §5, "wide then deep"): while the board has fewer than build_first towers
## the next purchase is the next build; after that it is the cheapest upgrade (gold; ties
## -> lower tower id) among the towers, L3 branch from the row's branches. A tower whose picked
## branch is missing or has_pending() (none since LT-29) stays at L2; the cap guard skips an
## upgrade whose reserve delta would leave the cap below the row's cap_floor. With no upgrade left the next purchase is a build. The
## bot buys the next purchase or stops for the round (it saves, never skips to something
## cheaper).
## Day/night (LT-27 §5): in BUILD (day), sell_relics() first, spend what the next purchase
## allows, then call_wave() at once (lighting the lamp at once gives the night its maximum
## luck). During a wave (night) building, upgrades and sales are refused, so the bot only
## tries buy_sanity() (rows with buy_sanity), re-checking every second.
## Lighthouse (LT-30 §3.2/§3.4, LT-57 §5): by day, once the board has build_first towers
## (towers first, then the oil reserve; LT-57 S2 decision), the bot tops the lamp oil up to
## one flare's flare.cost_oil (buy_oil() until the stock is there or a call is refused),
## before any upgrade, and in the
## purchase loop buys the next lighthouse level when its cost is at most the cheapest tower
## upgrade's (or no tower upgrade is left); a refused level is not retried that day and the
## loop falls through to tower upgrades and builds (LT-30 S10); at night it fires the flare when at least
## flare_min_live live enemies are on the map (LT-69: the flare lights the whole map).
## [--lighthouse=0] never upgrades the lighthouse,
## [--flare=0] never buys oil and never fires. A beam-off arm is a --data=<dir> variant.
## RUN lines add "lighthouse_level", "flares", "oil_bought", "oil_gold" and "lit_shots"
## (shots by a tower lit by the lighthouse beam or the flare; LT-70: a tower inside a
## Searchlight's radius does not count, `lit_tower_ticks` covers every light source),
## "lit_tower_ticks" / "shadow_tower_ticks" (tower-ticks with the net `lit` / `shadowed` flag)
## and "shadowed_mundane_builds" (mundane towers the bot placed inside a shadow caster's radius).
## LT-70 §6: placement is light/shadow-aware for every strategy (`Placement.cast_term`, CAST_WEIGHT);
## the `light` strategy builds the Searchlight.
## Loot is random (seeded LOOT stream): compare strategies over the default 10 seeds.
## RUN lines add "relics_sold" ($ from sales), "drops" (real relics credited per kind, config
## order), "star_stones" and "wage" ($ of dawn wages).
## Crew (LT-32 §5, data/crew.json): the build price hires a tower's missing crew, so with an
## empty reserve the bot pays what it paid before crew. Two optional tunables in
## tools/bot/strategies.json (patched through a balance variant's "bot" key, no CLI flag):
## `crew_reserve` (default 0): by day, after the purchases, the bot hires the cheapest crew
## kind until the reserve holds that many men; `post_min_live` (default 4): at night, with at
## least that many live enemies on the map, it deploys every post the reserve allows (crew.json
## kind order, the rifleman's best free cell). With crew_reserve 0 no man is hired and no post
## deployed, so every RUN line equals the crew-off run's. RUN lines add "crew_hired" (men),
## "crew_gold" ($ of hires), "posts" (posts deployed) and "post_shots" (shots by a post);
## "towers_final" lists real towers only.
## A run is capped at 6 simulated minutes per wave of the config (LT-101 §7; 30 minutes for
## 5 waves; outcome "timeout").

## LT-86: the harness (this file: CLI args, seed loop, RUN lines) plays the strategies of
## tools/bot/bot_strategies.gd, which place towers with tools/bot/bot_placement.gd. LT-101:
## the strategy rows and tunables (build_first, flare_min_live) live in
## tools/bot/strategies.json (tools/bot/strategy_table.gd).
const Strategies := preload("res://tools/bot/bot_strategies.gd")
const Placement := preload("res://tools/bot/bot_placement.gd")
const StrategyTable := preload("res://tools/bot/strategy_table.gd")

const TICKS_PER_WAVE := 6 * 60 * 30

var _cfg: GameConfig
var _score_cache := {}  ## def id -> Array of [score, cell] sorted best first
var _upgrades := true  ## false with --upgrades=0
var _lighthouse := true  ## false with --lighthouse=0
var _flare := true  ## false with --flare=0
var _branch_override := {}  ## tower def id -> branch from --branch=, wins over the row's branches
var _strategies: Array = []  ## strategies to play (the table's names), narrowed by --strategies=
var _max_ticks := 0  ## run cap in ticks; 0: TICKS_PER_WAVE x the config's wave count
## LT-73 golden replay (tests/golden_runs.gd): when valid, _play calls it with (sim, events)
## after every drain; it only reads them, so the runs and RUN lines do not change.
var _event_sink := Callable()
var _strategy: Strategies  ## created on first use by _policy()
var _table: StrategyTable = null  ## --bot-strategies= table; null: the policy's default table


func _init() -> void:
	var seeds := 10
	var out := ""
	var data_dir := ""
	var table_path := StrategyTable.DEFAULT_PATH
	var own_table := false  # --bot-strategies= given (an empty path is an error, not the default)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bot-strategies="):
			table_path = a.substr(17)
			own_table = true
	var table := StrategyTable.load_file(table_path) if own_table else StrategyTable.default()
	if not table.errors.is_empty():
		printerr("strategies.json errors: ", table.errors, " (file %s)" % table_path)
		quit(1)
		return
	if own_table:
		_table = table
	_strategies = table.names.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--data="):
			data_dir = a.substr(7)
		elif a.begins_with("--upgrades="):
			_upgrades = a.substr(11) != "0"
		elif a.begins_with("--lighthouse="):
			_lighthouse = a.substr(13) != "0"
		elif a.begins_with("--flare="):
			_flare = a.substr(8) != "0"
		elif a.begins_with("--branch="):
			for pair in a.substr(9).split(",", false):
				var kv := pair.split(":")
				if kv.size() != 2 or kv[1] not in ["a", "b"]:
					printerr("bad --branch pair: ", pair)
					quit(1)
					return
				_branch_override[kv[0]] = kv[1]
		elif a.begins_with("--strategies="):
			var picked := a.substr(13).split(",", false)
			for name in picked:
				if name not in table.names:
					printerr("unknown strategy in --strategies: ", name, " (known: ", table.names, ")")
					quit(1)
					return
			_strategies = table.names.filter(func(x): return x in picked)
			if _strategies.is_empty():
				printerr("--strategies names no strategy")
				quit(1)
				return
	var res := ConfigLoader.load_dir(data_dir) if data_dir != "" else ConfigLoader.load_dir()
	if not res.ok:
		printerr("config errors: ", res.errors)
		quit(1)
		return
	_cfg = res.config
	var tower_errors := table.check_towers(_cfg)
	if not tower_errors.is_empty():
		printerr("strategies.json errors: ", tower_errors)
		quit(1)
		return
	var runs: Array = []
	for strat in _strategies:
		for s in seeds:
			var r := _play(strat, 1000 + s)
			runs.append(r)
			print("RUN ", JSON.stringify(r))
	var summary := JSON.stringify(runs)
	print("SUMMARY ", summary)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(summary)
		f.close()
	quit(0)


func _play(strat: String, run_seed: int) -> Dictionary:
	var sim := Simulation.new(_cfg, run_seed)
	sim.set_spawner(WaveDirector.new(_cfg.waves))
	# Fakes are counted via the debug accessor: the render isolation test bans the raw flag.
	sim.debug_reveal_fakes = OS.is_debug_build()
	if not sim.debug_reveal_fakes:
		push_warning("release build: fakes are not counted")
	var st := sim.state
	var idx := 0
	var ticks_in_state := [0, 0, 0, 0]
	var wave_end_sanity: Array = []
	var fakes := 0
	var last_fake_id := 0
	var astray := 0
	var missed := 0
	var shots := 0
	var built := {}
	var upgrades := {}  ## "<def>_L2" or "<def>_<branch>" -> count
	var upgrade_gold := 0
	# LT-23 §4 metrics.
	var min_sanity := st.sanity
	var cap_per_wave: Array = []
	var madness_tick := -1
	var reserve_peak := 0.0
	var free_reserve := 0.0  ## reserve taken from the cap but not from current sanity
	var hp_lost_per_wave: Array = []
	var hp_before := st.lighthouse_hp
	# LT-27 §5 metrics.
	var relics_sold := 0
	var wage := 0
	var drops := {}
	var flares := 0
	var oil_bought := 0
	var oil_gold := 0
	var lit_shots := 0
	var lit_tower_ticks := 0
	var shadow_tower_ticks := 0
	# LT-32 §5 metrics.
	var crew_hired := 0
	var crew_gold := 0
	var posts := 0
	var post_shots := 0
	var post_ids := {}  ## ids of deployed posts (a post may be gone at dawn by the drain)
	_policy().shadowed_builds = 0
	for kind in _cfg.economy.relic_ids():
		drops[kind] = 0
	var tick_cap := _tick_cap()
	while st.outcome == SimState.Outcome.NONE and st.tick < tick_cap:
		if st.tick % 30 == 0:
			idx = _policy().act(sim, strat, idx, built)
		sim.step()
		for t in st.towers:
			if t.lit:
				lit_tower_ticks += 1
			if t.shadowed:
				shadow_tower_ticks += 1
		ticks_in_state[st.sanity_state] += 1
		min_sanity = minf(min_sanity, st.sanity)
		if madness_tick < 0 and st.sanity_state == SimState.SanityState.MADNESS:
			madness_tick = st.tick
		var reserved := 0.0
		for t in st.towers:
			reserved += sim.reserve_of(t)
		reserve_peak = maxf(reserve_peak, reserved)
		for e in st.enemies:
			if sim.debug_is_fake(e) and e.id > last_fake_id:
				last_fake_id = e.id
				fakes += 1
		var evs := sim.drain_events()
		if _event_sink.is_valid():
			_event_sink.call(sim, evs)
		for ev in evs:
			if ev.type == SimEvent.Type.WAVE_CLEARED:
				wave_end_sanity.append(snappedf(st.sanity, 0.1))
				cap_per_wave.append(snappedf(st.sanity_cap, 0.1))
				hp_lost_per_wave.append(hp_before - st.lighthouse_hp)
				hp_before = st.lighthouse_hp
			elif ev.type == SimEvent.Type.SANITY_CAP_CHANGED:
				if ev.data["delta"] < 0.0:
					free_reserve -= ev.data["delta"]
			elif ev.type == SimEvent.Type.SANITY_CHANGED and ev.data["reason"] == "reserve":
				free_reserve += ev.data["delta"]  # negative: the part paid from sanity
			elif ev.type == SimEvent.Type.SHOT:
				shots += 1
				if post_ids.has(ev.id):
					post_shots += 1
				var shooter := sim.tower_by_id(ev.id)
				if shooter != null and shooter.lit and _beam_lit(sim, shooter):
					lit_shots += 1
				if ev.data.get("miss", false):
					missed += 1
				if ev.data.get("astray", false):
					astray += 1
			elif ev.type == SimEvent.Type.GOLD_CHANGED:
				if ev.data["reason"] == "relic_sale":
					relics_sold += ev.data["delta"]
				elif ev.data["reason"] == "wave_bonus":
					wage += ev.data["delta"]
				elif ev.data["reason"] == "oil":
					oil_gold -= ev.data["delta"]
				elif ev.data["reason"] == "hire":
					crew_gold -= ev.data["delta"]
			elif ev.type == SimEvent.Type.CREW_CHANGED and ev.data["reason"] == "hire":
				crew_hired += ev.data["delta"]
			elif ev.type == SimEvent.Type.POST_DEPLOYED:
				posts += 1
				post_ids[ev.id] = true
			elif ev.type == SimEvent.Type.FLARE_FIRED:
				flares += 1
			elif ev.type == SimEvent.Type.OIL_CHANGED and ev.data["reason"] == "buy":
				oil_bought += ev.data["delta"]
			elif ev.type == SimEvent.Type.RELICS_CHANGED and ev.data["reason"] == "kill":
				drops[ev.data["kind"]] += ev.data["delta"]
			elif ev.type == SimEvent.Type.TOWER_UPGRADED:
				var b: String = ev.data["branch"]
				var key := "%s_%s" % [ev.data["def"], b if b != "" else "L%d" % (ev.data["level"] + 1)]
				upgrades[key] = upgrades.get(key, 0) + 1
				upgrade_gold += ev.data["cost"]
	var outcome := "timeout"
	if st.outcome == SimState.Outcome.WON:
		outcome = "won"
	elif st.outcome == SimState.Outcome.LOST:
		outcome = "lost"
	var waves_survived := wave_end_sanity.size()
	if st.outcome != SimState.Outcome.WON:
		hp_lost_per_wave.append(hp_before - st.lighthouse_hp)  # the wave it ended in
	var towers_final := {}  ## "<def>_L1" / "<def>_L2" / "<def>_<branch>" -> standing count
	for t in st.towers:
		if t.post:
			continue  # LT-32: a run lost at night would list its reserve posts
		var key := "%s_%s" % [t.def.id, t.branch if t.level >= TowerDef.LEVEL_COUNT \
			else "L%d" % (t.level + 1)]
		towers_final[key] = towers_final.get(key, 0) + 1
	var run := {
		"strategy": strat, "seed": run_seed, "outcome": outcome,
		"waves_survived": waves_survived, "gold": st.gold,
		"final_sanity": snappedf(st.sanity, 0.1), "wave_end_sanity": wave_end_sanity,
		"seconds": {
			"lucid": ticks_in_state[0] / 30.0, "whispers": ticks_in_state[1] / 30.0,
			"fraying": ticks_in_state[2] / 30.0, "madness": ticks_in_state[3] / 30.0},
		"fakes": fakes, "astray": astray, "missed": missed, "shots": shots,
		"towers": built, "lighthouse_hp": st.lighthouse_hp, "ticks": st.tick,
		"min_sanity": snappedf(min_sanity, 0.1), "final_cap": snappedf(st.sanity_cap, 0.1),
		"cap_per_wave": cap_per_wave, "madness_tick": madness_tick,
		"reserve_peak": snappedf(reserve_peak, 0.1), "free_reserve": snappedf(free_reserve, 0.1),
		"hp_lost_per_wave": hp_lost_per_wave, "towers_final": towers_final,
		"relics_sold": relics_sold, "drops": drops, "star_stones": drops.get("star_stone", 0),
		"wage": wage, "lighthouse_level": st.lighthouse_level, "flares": flares,
		"oil_bought": oil_bought, "oil_gold": oil_gold, "lit_shots": lit_shots,
		"lit_tower_ticks": lit_tower_ticks, "shadow_tower_ticks": shadow_tower_ticks,
		"shadowed_mundane_builds": _policy().shadowed_builds,
		"crew_hired": crew_hired, "crew_gold": crew_gold, "posts": posts,
		"post_shots": post_shots,
	}
	if _upgrades:
		run["upgrades"] = upgrades
		run["upgrade_gold"] = upgrade_gold
	return run


## The run cap in ticks: `_max_ticks` when set (golden cuts), else TICKS_PER_WAVE per wave.
func _tick_cap() -> int:
	return _max_ticks if _max_ticks > 0 else TICKS_PER_WAVE * _cfg.waves.waves.size()


## The strategies object, its fields synced from the harness's (a test sets those after
## construction, so they are copied on every call).
func _policy() -> Strategies:
	if _strategy == null:
		_strategy = Strategies.new()
	_strategy.cfg = _cfg
	_strategy.score_cache = _score_cache
	_strategy.upgrades = _upgrades
	_strategy.lighthouse = _lighthouse
	_strategy.flare = _flare
	_strategy.branch_override = _branch_override
	if _table != null:
		_strategy.table = _table
	return _strategy


## LT-70 §6: `lit_shots` keeps its meaning (lighthouse beam / flare value): a lit shooter that
## no other casts_light tower covers (Simulation.light_at's light_casters). A tower under both
## the beam and a Searchlight is not counted (an undercount, kept so the RUN lines stay
## identical; light_at's `beam` would count it); `lit_tower_ticks` counts every light source.
func _beam_lit(sim: Simulation, t: SimTower) -> bool:
	return int(sim.light_at(t.centre(), t.id)["light_casters"]) == 0
