extends RefCounted
## Bot decision policies (LT-15 .. LT-70; split out of tools/bot_runs.gd by LT-86): what each
## strategy builds, buys and fires, by day and by night. LT-101: the strategies (build orders,
## L3 branch picks, cap floors, flags) and the shared tunables are data in
## tools/bot/strategies.json, loaded by tools/bot/strategy_table.gd; this file interprets
## them and keeps the policies with real control flow (cap guard, blocked-item handling,
## upgrade pick, lighthouse, oil, flare). One instance serves one harness: it owns the
## per-run counters and is configured by the harness through the fields below.

const Placement := preload("res://tools/bot/bot_placement.gd")
const StrategyTable := preload("res://tools/bot/strategy_table.gd")

## The strategy rows and tunables (LT-101); a test may assign a table from parse_text().
var table: StrategyTable = StrategyTable.default()
var cfg: GameConfig
var score_cache := {}  ## shared with the harness: def id -> Array of [score, cell], best first
var upgrades := true  ## false with --upgrades=0
var lighthouse := true  ## false with --lighthouse=0
var flare := true  ## false with --flare=0
var branch_override := {}  ## tower def id -> branch from --branch=, wins over the row's branches
var shadowed_builds := 0  ## LT-70: mundane towers placed inside a shadow radius, this run

## The next build of `strat` at order index `i`: its row's `prefix`, then its `cycle`
## repeated. A "fallback" row (occult) whose cap guard blocks an occult cycle item returns
## its `fallback` tower while the run has fewer than `fallback_max` of them, else "" (save).
## A "skip" row (mixed) returns its item as is; act() skips a blocked one.
func order(strat: String, i: int, sim: Simulation, built: Dictionary) -> String:
	var r := table.row(strat)
	assert(not r.is_empty(), "unknown strategy " + strat)
	var prefix: Array = r.prefix
	if i < prefix.size():
		return prefix[i]
	var cycle: Array = r.cycle
	var id: String = cycle[(i - prefix.size()) % cycle.size()]
	if r.on_blocked == "fallback" and cfg.towers[id].kind == "occult" \
			and not cap_allows(sim, strat, cfg.towers[id].levels[0].sanity_reserve):
		return r.fallback if built.get(r.fallback, 0) < r.fallback_max else ""
	return id


## The cap guard (LT-23 §4): true when `strat` has no `cap_floor`, or reserving `delta` more
## leaves sanity_cap >= its floor (a delta <= 0 always passes).
func cap_allows(sim: Simulation, strat: String, delta: float) -> bool:
	var floor_cap: Variant = table.row(strat).get("cap_floor")  # unknown strategy, null: none
	if floor_cap == null or delta <= 0.0:
		return true
	return sim.state.sanity_cap - delta >= floor_cap


## At night (a wave) only tries buy_sanity() (rows with `buy_sanity`: occult, mixed), fires
## the flare and deploys reserve posts (LT-32). By day sells every relic, buys as many
## purchases (builds, then upgrades per the header) as affordable, tops the crew reserve up
## to the table's crew_reserve (LT-32) and in BUILD then calls the wave. Returns the new
## build-order index.
func act(sim: Simulation, strat: String, idx: int, built: Dictionary) -> int:
	if table.row(strat).buy_sanity:
		sim.buy_sanity()  # refused unless exit_rule is "buyout" and state is MADNESS
	if sim.state.phase == SimState.Phase.WAVE:
		night_flare(sim)
		night_posts(sim)
		return idx  # LT-27 §3: night; builds, upgrades and sales are day only
	sim.sell_relics()  # refused with an empty stash
	var lighthouse_refused := false  # a refused lighthouse buy falls through to the builds
	var build_first := table.build_first
	var topped := not flare  # LT-57: the oil reserve comes after the build_first towers
	while true:
		if not topped and tower_count(sim) >= build_first:
			topped = true
			while sim.state.oil < bot_oil_target(sim) \
					and sim.buy_oil() == SimCommand.CommandResult.OK:
				pass  # refused: no oil block, full, or too poor
		if upgrades and lighthouse and not lighthouse_refused \
				and tower_count(sim) >= build_first and lighthouse_next(sim, strat):
			if sim.upgrade_lighthouse() != SimCommand.CommandResult.OK:
				lighthouse_refused = true
			continue
		if upgrades and tower_count(sim) >= build_first:
			var up := next_upgrade(sim, strat)
			if not up.is_empty():
				if sim.upgrade_tower(up[0], up[1]) != SimCommand.CommandResult.OK:
					break
				continue
		var id := order(strat, idx, sim, built)
		if table.row(strat).on_blocked == "skip" and cfg.towers[id].kind == "occult" \
				and not cap_allows(sim, strat, cfg.towers[id].levels[0].sanity_reserve):
			idx += 1  # blocked occult item: skip to the next one in the order
			continue
		if id == "":
			# A "fallback" row (occult), blocked and out of fallback towers: any upgrade that
			# passes the cap guard if there is one (even below build_first towers), else save.
			var up := next_upgrade(sim, strat) if upgrades else []
			if up.is_empty() or sim.upgrade_tower(up[0], up[1]) != SimCommand.CommandResult.OK:
				break
			continue
		var cell := Placement.best_cell(cfg, sim, id, score_cache)
		var in_sign := cfg.towers[id].kind == "mundane" and Placement.in_shadow_radius(sim, cell)
		if cell.x < 0 or sim.build_tower(id, cell) != SimCommand.CommandResult.OK:
			break
		if in_sign:
			shadowed_builds += 1
		built[id] = built.get(id, 0) + 1
		idx += 1
	hire_reserve(sim)
	if sim.state.phase == SimState.Phase.BUILD:
		sim.call_wave()
	return idx


## Whether the lighthouse level is the next purchase: one is left and its cost is at most
## the cheapest tower upgrade's (or no tower upgrade is left).
func lighthouse_next(sim: Simulation, strat: String) -> bool:
	var cost := sim.lighthouse_upgrade_cost()
	if cost == 0:
		return false
	var up := next_upgrade(sim, strat)
	return up.is_empty() or cost <= sim.upgrade_target(sim.tower_by_id(up[0]), up[1]).upgrade_cost


## LT-57 §5: oil the bot keeps by day: one flare (Simulation.flare_cost_oil), 0 without a
## flare block. Not Simulation.oil_for_flare: that is a click's batch (up to the cap), the
## bot stops at one flare's worth.
static func bot_oil_target(sim: Simulation) -> int:
	return sim.flare_cost_oil()


## Night: fires the flare when at least the table's `flare_min_live` live enemies (reals and
## fakes, as a player sees them) are on the map (LT-69: the flare lights the whole map; e.lit
## is not the count, it is set by the beams before firing). Refused on cooldown or without oil.
func night_flare(sim: Simulation) -> void:
	if not flare:
		return
	if live_count(sim) >= table.flare_min_live:
		sim.fire_flare()


## LT-32 §5: real towers on the board (reserve posts are not towers; by day none stand).
static func tower_count(sim: Simulation) -> int:
	var n := 0
	for t in sim.state.towers:
		if not t.post:
			n += 1
	return n


## Live enemies (reals and fakes, as a player sees them) on the map.
static func live_count(sim: Simulation) -> int:
	var live := 0
	for e in sim.state.enemies:
		if e.is_live():
			live += 1
	return live


## LT-32 §5, night: when at least the table's `post_min_live` live enemies are on the map,
## deploys the reserve as posts: crew kinds in crew.json order, each while its reserve holds
## a post's crew, at the rifleman's best free cell (a post fights as a rifleman), until a
## deploy is refused. No-op with crew off or an empty reserve (crew_reserve 0).
func night_posts(sim: Simulation) -> void:
	if not cfg.crew_on() or sim.crew_reserve().is_empty():
		return
	if live_count(sim) < table.post_min_live:
		return
	for kind: String in cfg.crew.crews:
		while sim.crew_reserve().get(kind, 0) >= cfg.crew.post_of(kind).crew:
			var cell := Placement.best_cell(cfg, sim, "rifleman", score_cache)
			if cell.x < 0 or sim.deploy(kind, cell) != SimCommand.CommandResult.OK:
				return


## LT-32 §5, day (after the purchases): hires the cheapest crew kind (ties: crew.json order;
## a post is the same whoever stands there) while the whole reserve is below the table's
## `crew_reserve` and the hire is accepted. No-op with crew off or crew_reserve 0.
func hire_reserve(sim: Simulation) -> void:
	if table.crew_reserve <= 0 or not cfg.crew_on():
		return
	var cheapest := ""
	for kind: String in cfg.crew.crews:
		if cheapest == "" or cfg.crew.crews[kind].hire < cfg.crew.crews[cheapest].hire:
			cheapest = kind
	if cheapest == "":
		return
	while _reserve_total(sim) < table.crew_reserve \
			and sim.hire(cheapest) == SimCommand.CommandResult.OK:
		pass


static func _reserve_total(sim: Simulation) -> int:
	var n := 0
	for kind: String in sim.crew_reserve():
		n += int(sim.crew_reserve()[kind])
	return n


## The bot's next upgrade as [tower_id, branch], or [] when no tower can go further for it:
## the cheapest target (gold) over the towers in id order, ties -> lower id. Skips a tower
## whose L3 pick is missing from the row's `branches` (and `branch_override`) or has_pending(),
## and (rows with a `cap_floor`) an upgrade whose reserve delta fails the cap guard.
func next_upgrade(sim: Simulation, strat: String) -> Array:
	var picks: Dictionary = table.row(strat).get("branches", {}).duplicate()
	picks.merge(branch_override, true)
	var best: Array = []
	var best_cost := 0
	for t in sim.state.towers:
		if t.post:
			continue  # LT-32: a reserve post is not a tower (none stand by day)
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
		if not cap_allows(sim, strat, sim.reserve_delta(t.def.id, t.stats(), target)):
			continue
		if best.is_empty() or target.upgrade_cost < best_cost \
				or (target.upgrade_cost == best_cost and t.id < best[0]):
			best = [t.id, branch]
			best_cost = target.upgrade_cost
	return best

