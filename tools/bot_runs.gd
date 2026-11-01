extends SceneTree
## Headless bot harness for the playtest baseline (LT-15). Run:
##   $GODOT --headless --path . -s res://tools/bot_runs.gd -- [--seeds=10] [--out=<file>]
##   [--data=<dir>] (a config directory other than res://data, e.g. a tuning variant)
##   [--upgrades=0] (never upgrade: the pre-LT-24 baseline; RUN lines then carry no
##   "upgrades"/"upgrade_gold" keys. Since LT-27 the economy differs, so no run compares
##   byte for byte with a pre-LT-27 harness; only the key set does)
##   [--branch=<tower>:<a|b>[,<tower>:<a|b>...]] (LT-29: override BRANCH_PICK for these
##   tower def ids in every strategy, e.g. --branch=rifleman:b,harpooner:b; other towers keep
##   the strategy's pick; a branch other than a or b is an error)
##   [--strategies=<name>[,<name>...]] (LT-56: play only these strategies, in STRATEGIES
##   order; an unknown name is an error. tools/balance/ runs one strategy per process)
## For each strategy x seed it plays one full run on data/ with a fresh Simulation +
## WaveDirector and prints one "RUN {json}" line per run, then a "SUMMARY {json}" line.
##
## Strategies (build orders; the bot builds the next item as soon as it can pay for it):
##   mundane  : rifleman, rifleman, harpooner repeated. Never builds occult.
##   occult   : rifleman, then elder_sign / necronomicon_reader alternating. Cap guard
##              (LT-23 §4): an occult build or upgrade only while sanity_cap - its reserve
##              delta >= CAP_FLOOR (30); a blocked occult build is replaced by a rifleman
##              while the run has fewer than OCCULT_MAX_RIFLEMEN (3), otherwise the bot tries
##              an upgrade that passes the guard and else saves its gold. Tries buy_sanity()
##              in madness (refused under the "permanent" exit rule).
##   mixed    : rifleman, rifleman, elder_sign, rifleman, harpooner, necronomicon_reader
##              repeated; the same cap guard with CAP_FLOOR 60, a blocked occult item is
##              skipped (the order moves on to the next item). Tries buy_sanity() too.
##   madness  : necronomicon_reader / elder_sign alternating, no guard, never buys sanity:
##              it keeps building past cap 0 (MADNESS).
##   demolition: rifleman, rifleman, dynamite_crew repeated (LT-47): "mundane" with the
##              Dynamite crew in the harpooner's slot, for a with/without comparison.
##   battery  : rifleman, rifleman, coast_battery repeated (LT-48): the same with the
##              Coast battery in that slot.
##   resonator: rifleman, rifleman, resonator repeated (LT-50): the same with the
##              Tillinghast Resonator in that slot; no cap guard (its reserves lower the
##              cap, and lower sanity is what it feeds on).
## Placement (greedy): the free buildable cell with the most path cells whose centre is
## within the tower's L1 range (and not inside its L1 min_range, LT-48); ties go to the
## lowest row-major cell. No sells.
## Upgrades (LT-24 §5, "wide then deep"): while the board has fewer than BUILD_FIRST towers
## the next purchase is the next build; after that it is the cheapest upgrade (gold; ties
## -> lower tower id) among the towers, L3 branch from BRANCH_PICK. A tower whose picked
## branch is missing or has_pending() (none since LT-29) stays at L2; the cap guard (occult, mixed) skips an
## upgrade whose reserve delta would leave the cap below CAP_FLOOR. With no upgrade left the next purchase is a build. The
## bot buys the next purchase or stops for the round (it saves, never skips to something
## cheaper).
## Day/night (LT-27 §5): in BUILD (day), sell_relics() first, spend what the next purchase
## allows, then call_wave() at once (lighting the lamp at once gives the night its maximum
## luck). During a wave (night) building, upgrades and sales are refused, so the bot only
## tries buy_sanity() (occult, mixed), re-checking every second.
## Lighthouse (LT-30 §3.2/§3.4): by day, after sell_relics(), the bot tops the lamp oil up to
## BOT_OIL_TARGET (buy_oil() until the stock is there or a call is refused), and in the
## purchase loop buys the next lighthouse level when its cost is at most the cheapest tower
## upgrade's (or no tower upgrade is left); a refused level is not retried that day and the
## loop falls through to tower upgrades and builds (LT-30 S10); at night it fires the flare when at least
## FLARE_MIN_LIT live enemies are lit. [--lighthouse=0] never upgrades the lighthouse,
## [--flare=0] never buys oil and never fires. A beam-off arm is a --data=<dir> variant.
## RUN lines add "lighthouse_level", "flares", "oil_bought", "oil_gold" and "lit_shots"
## (shots by a tower inside a beam).
## Loot is random (seeded LOOT stream): compare strategies over the default 10 seeds.
## RUN lines add "relics_sold" ($ from sales), "drops" (real relics credited per kind, config
## order), "star_stones" and "wage" ($ of dawn wages).
## A run is capped at 30 simulated minutes (outcome "timeout").

const STRATEGIES := ["mundane", "occult", "mixed", "madness", "demolition", "battery",
	"resonator"]
const BOT_OIL_TARGET := 4  ## oil the bot keeps by day: two flares (tunable)
const FLARE_MIN_LIT := 3  ## live lit enemies that make the bot fire the flare (tunable)
const MAX_TICKS := 30 * 60 * 30
## Strategy -> lowest sanity_cap an occult build/upgrade may leave (LT-23 §4, tunable).
const CAP_FLOOR := {"occult": 30.0, "mixed": 60.0}
const OCCULT_MAX_RIFLEMEN := 3  ## riflemen the occult bot builds per run, the first included
const MIXED_ORDER := ["rifleman", "rifleman", "elder_sign", "rifleman", "harpooner",
	"necronomicon_reader"]
const BUILD_FIRST := 5  ## towers on the board before the bot starts upgrading (tunable)
## Strategy -> tower def id -> L3 branch the bot buys (tunable); a tower not listed stays
## at L2. Pure branches for the careful bot, corrupted for the mad one.
const BRANCH_PICK := {
	"mundane": {"rifleman": "a", "harpooner": "a"},
	"occult": {"rifleman": "a", "elder_sign": "a", "necronomicon_reader": "a"},
	"mixed": {"rifleman": "a", "harpooner": "a", "elder_sign": "a", "necronomicon_reader": "a"},
	"madness": {"elder_sign": "b", "necronomicon_reader": "b"},
	"demolition": {"rifleman": "a", "dynamite_crew": "a"},
	"battery": {"rifleman": "a", "coast_battery": "a"},
	"resonator": {"rifleman": "a", "resonator": "a"},
}

var _cfg: GameConfig
var _score_cache := {}  ## def id -> Array of [score, cell] sorted best first
var _upgrades := true  ## false with --upgrades=0
var _lighthouse := true  ## false with --lighthouse=0
var _flare := true  ## false with --flare=0
var _branch_override := {}  ## tower def id -> branch from --branch=, wins over BRANCH_PICK
var _strategies: Array = STRATEGIES  ## strategies to play, narrowed by --strategies=


func _init() -> void:
	var seeds := 10
	var out := ""
	var data_dir := ""
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
				if name not in STRATEGIES:
					printerr("unknown strategy in --strategies: ", name, " (known: ", STRATEGIES, ")")
					quit(1)
					return
			_strategies = STRATEGIES.filter(func(x): return x in picked)
			if _strategies.is_empty():
				printerr("--strategies names no strategy")
				quit(1)
				return
	var res := GameConfig.load_from_dir(data_dir) if data_dir != "" else GameConfig.load_from_dir()
	if not res.ok:
		printerr("config errors: ", res.errors)
		quit(1)
		return
	_cfg = res.config
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
	for kind in _cfg.economy.relic_ids():
		drops[kind] = 0
	while st.outcome == SimState.Outcome.NONE and st.tick < MAX_TICKS:
		if st.tick % 30 == 0:
			idx = _act(sim, strat, idx, built)
		sim.step()
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
		for ev in sim.drain_events():
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
				var shooter := sim.tower_by_id(ev.id)
				if shooter != null and shooter.lit:
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
	}
	if _upgrades:
		run["upgrades"] = upgrades
		run["upgrade_gold"] = upgrade_gold
	return run


## The next build of `strat` at order index `i`, or "" when the occult bot must save (its
## cap guard blocks the occult item and its riflemen are used up). Mixed returns its item
## as is; _act skips a blocked one.
func _order(strat: String, i: int, sim: Simulation, built: Dictionary) -> String:
	match strat:
		"mundane":
			return "harpooner" if i % 3 == 2 else "rifleman"
		"demolition":
			return "dynamite_crew" if i % 3 == 2 else "rifleman"
		"battery":
			return "coast_battery" if i % 3 == 2 else "rifleman"
		"resonator":
			return "resonator" if i % 3 == 2 else "rifleman"
		"occult":
			if i == 0:
				return "rifleman"
			var d := "elder_sign" if i % 2 == 1 else "necronomicon_reader"
			if not _cap_allows(sim, strat, _cfg.towers[d].levels[0].sanity_reserve):
				return "rifleman" if built.get("rifleman", 0) < OCCULT_MAX_RIFLEMEN else ""
			return d
		"mixed":
			return MIXED_ORDER[i % MIXED_ORDER.size()]
		_:
			return "necronomicon_reader" if i % 2 == 0 else "elder_sign"


## The cap guard (LT-23 §4): true when `strat` has no CAP_FLOOR, or reserving `delta` more
## leaves sanity_cap >= its floor (a delta <= 0 always passes).
func _cap_allows(sim: Simulation, strat: String, delta: float) -> bool:
	if not CAP_FLOOR.has(strat) or delta <= 0.0:
		return true
	return sim.state.sanity_cap - delta >= CAP_FLOOR[strat]


## At night (a wave) only tries buy_sanity() (occult, mixed). By day sells every relic,
## buys as many purchases (builds, then upgrades per the header) as affordable, and in BUILD
## then calls the wave. Returns the new build-order index.
func _act(sim: Simulation, strat: String, idx: int, built: Dictionary) -> int:
	if strat == "occult" or strat == "mixed":
		sim.buy_sanity()  # refused unless exit_rule is "buyout" and state is MADNESS
	if sim.state.phase == SimState.Phase.WAVE:
		_night_flare(sim)
		return idx  # LT-27 §3: night; builds, upgrades and sales are day only
	sim.sell_relics()  # refused with an empty stash
	if _flare:
		while sim.state.oil < BOT_OIL_TARGET and sim.buy_oil() == Simulation.CommandResult.OK:
			pass  # refused: no oil block, full, or too poor
	var lighthouse_refused := false  # a refused lighthouse buy falls through to the builds
	while true:
		if _upgrades and _lighthouse and not lighthouse_refused \
				and sim.state.towers.size() >= BUILD_FIRST and _lighthouse_next(sim, strat):
			if sim.upgrade_lighthouse() != Simulation.CommandResult.OK:
				lighthouse_refused = true
			continue
		if _upgrades and sim.state.towers.size() >= BUILD_FIRST:
			var up := _next_upgrade(sim, strat)
			if not up.is_empty():
				if sim.upgrade_tower(up[0], up[1]) != Simulation.CommandResult.OK:
					break
				continue
		var id := _order(strat, idx, sim, built)
		if strat == "mixed" and _cfg.towers[id].kind == "occult" \
				and not _cap_allows(sim, strat, _cfg.towers[id].levels[0].sanity_reserve):
			idx += 1  # blocked occult item: skip to the next one in the order
			continue
		if id == "":
			# Occult bot, blocked and out of riflemen: any upgrade that passes the cap
			# guard if there is one (even below BUILD_FIRST towers), else save.
			var up := _next_upgrade(sim, strat) if _upgrades else []
			if up.is_empty() or sim.upgrade_tower(up[0], up[1]) != Simulation.CommandResult.OK:
				break
			continue
		var cell := _best_cell(sim, id)
		if cell.x < 0 or sim.build_tower(id, cell) != Simulation.CommandResult.OK:
			break
		built[id] = built.get(id, 0) + 1
		idx += 1
	if sim.state.phase == SimState.Phase.BUILD:
		sim.call_wave()
	return idx


## Whether the lighthouse level is the next purchase: one is left and its cost is at most
## the cheapest tower upgrade's (or no tower upgrade is left).
func _lighthouse_next(sim: Simulation, strat: String) -> bool:
	var cost := sim.lighthouse_upgrade_cost()
	if cost == 0:
		return false
	var up := _next_upgrade(sim, strat)
	return up.is_empty() or cost <= sim.upgrade_target(sim.tower_by_id(up[0]), up[1]).upgrade_cost


## Night: fires the flare when at least FLARE_MIN_LIT live enemies are lit (refused on
## cooldown or without oil).
func _night_flare(sim: Simulation) -> void:
	if not _flare:
		return
	var lit := 0
	for e in sim.state.enemies:
		if e.lit:
			lit += 1
	if lit >= FLARE_MIN_LIT:
		sim.fire_flare()


## The bot's next upgrade as [tower_id, branch], or [] when no tower can go further for it:
## the cheapest target (gold) over the towers in id order, ties -> lower id. Skips a tower
## whose L3 pick is missing from BRANCH_PICK or has_pending(), and (occult, mixed) an
## upgrade whose reserve delta fails the cap guard (_cap_allows).
func _next_upgrade(sim: Simulation, strat: String) -> Array:
	var picks: Dictionary = BRANCH_PICK.get(strat, {}).duplicate()
	picks.merge(_branch_override, true)
	var best: Array = []
	var best_cost := 0
	for t in sim.state.towers:
		var branches := sim.upgrade_branches(t)
		if branches.is_empty():
			continue
		var branch := ""
		if branches[0] != "":
			branch = picks.get(t.def.id, "")
			if branch == "":
				continue
		var target := sim.upgrade_target(t, branch)
		if target == null or target.has_pending():
			continue
		if not _cap_allows(sim, strat, sim.reserve_delta(t.def.id, t.stats(), target)):
			continue
		if best.is_empty() or target.upgrade_cost < best_cost \
				or (target.upgrade_cost == best_cost and t.id < best[0]):
			best = [t.id, branch]
			best_cost = target.upgrade_cost
	return best


func _best_cell(sim: Simulation, id: String) -> Vector2i:
	if not _score_cache.has(id):
		var rng_cells: float = _cfg.towers[id].levels[0].range_cells
		var min_cells: float = _cfg.towers[id].levels[0].min_range
		var m := _cfg.map
		var list: Array = []
		for y in m.height:
			for x in m.width:
				var c := Vector2i(x, y)
				if not m.is_buildable(c):
					continue
				var score := 0
				for p in m.path:
					var d := Vector2(c - p).length()
					if d <= rng_cells and d >= min_cells:
						score += 1
				if score > 0:
					list.append([score, c])
		list.sort_custom(func(a, b): return a[0] > b[0])  # stable enough: row-major kept
		_score_cache[id] = list
	for e in _score_cache[id]:
		if not sim.state.tower_at.has(e[1]):
			return e[1]
	return Vector2i(-1, -1)
