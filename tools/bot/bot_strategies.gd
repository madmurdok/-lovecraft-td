extends RefCounted
## Bot decision policies (LT-15 .. LT-70; split out of tools/bot_runs.gd by LT-86): what each
## strategy builds, buys and fires, by day and by night. The strategy list and the strategy
## descriptions stay in tools/bot_runs.gd. One instance serves one harness: it owns the
## per-run counters and is configured by the harness through the fields below.

const Placement := preload("res://tools/bot/bot_placement.gd")

## LT-57 §5, LT-69: live enemies (reals and fakes) anywhere on the map that make the bot
## fire the flare (tunable).
const FLARE_MIN_LIVE := 4
## Strategy -> lowest sanity_cap an occult build/upgrade may leave (LT-23 §4, tunable).
const CAP_FLOOR := {"occult": 30.0, "mixed": 60.0}
const OCCULT_MAX_RIFLEMEN := 3  ## riflemen the occult bot builds per run, the first included
const MIXED_ORDER := ["rifleman", "rifleman", "elder_sign", "rifleman", "harpooner",
	"necronomicon_reader"]
## LT-70 §6: the `light` strategy's build order, repeated.
const LIGHT_ORDER := ["rifleman", "rifleman", "searchlight", "harpooner", "rifleman"]
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
	"gate": {"rifleman": "a", "silver_key": "a"},
	"circle": {"rifleman": "a", "summoning_circle": "a"},
	"light": {"rifleman": "a", "harpooner": "a", "searchlight": "b"},
}

var cfg: GameConfig
var score_cache := {}  ## shared with the harness: def id -> Array of [score, cell], best first
var upgrades := true  ## false with --upgrades=0
var lighthouse := true  ## false with --lighthouse=0
var flare := true  ## false with --flare=0
var branch_override := {}  ## tower def id -> branch from --branch=, wins over BRANCH_PICK
var shadowed_builds := 0  ## LT-70: mundane towers placed inside a shadow radius, this run

## The next build of `strat` at order index `i`, or "" when the occult bot must save (its
## cap guard blocks the occult item and its riflemen are used up). Mixed returns its item
## as is; _act skips a blocked one.
func order(strat: String, i: int, sim: Simulation, built: Dictionary) -> String:
	match strat:
		"mundane":
			return "harpooner" if i % 3 == 2 else "rifleman"
		"demolition":
			return "dynamite_crew" if i % 3 == 2 else "rifleman"
		"battery":
			return "coast_battery" if i % 3 == 2 else "rifleman"
		"resonator":
			return "resonator" if i % 3 == 2 else "rifleman"
		"gate":
			return "silver_key" if i % 3 == 2 else "rifleman"
		"circle":
			return "summoning_circle" if i % 3 == 2 else "rifleman"
		"occult":
			if i == 0:
				return "rifleman"
			var d := "elder_sign" if i % 2 == 1 else "necronomicon_reader"
			if not cap_allows(sim, strat, cfg.towers[d].levels[0].sanity_reserve):
				return "rifleman" if built.get("rifleman", 0) < OCCULT_MAX_RIFLEMEN else ""
			return d
		"mixed":
			return MIXED_ORDER[i % MIXED_ORDER.size()]
		"light":
			return LIGHT_ORDER[i % LIGHT_ORDER.size()]
		_:
			return "necronomicon_reader" if i % 2 == 0 else "elder_sign"


## The cap guard (LT-23 §4): true when `strat` has no CAP_FLOOR, or reserving `delta` more
## leaves sanity_cap >= its floor (a delta <= 0 always passes).
func cap_allows(sim: Simulation, strat: String, delta: float) -> bool:
	if not CAP_FLOOR.has(strat) or delta <= 0.0:
		return true
	return sim.state.sanity_cap - delta >= CAP_FLOOR[strat]


## At night (a wave) only tries buy_sanity() (occult, mixed). By day sells every relic,
## buys as many purchases (builds, then upgrades per the header) as affordable, and in BUILD
## then calls the wave. Returns the new build-order index.
func act(sim: Simulation, strat: String, idx: int, built: Dictionary) -> int:
	if strat == "occult" or strat == "mixed":
		sim.buy_sanity()  # refused unless exit_rule is "buyout" and state is MADNESS
	if sim.state.phase == SimState.Phase.WAVE:
		night_flare(sim)
		return idx  # LT-27 §3: night; builds, upgrades and sales are day only
	sim.sell_relics()  # refused with an empty stash
	var lighthouse_refused := false  # a refused lighthouse buy falls through to the builds
	var topped := not flare  # LT-57: the oil reserve comes after the BUILD_FIRST towers
	while true:
		if not topped and sim.state.towers.size() >= BUILD_FIRST:
			topped = true
			while sim.state.oil < bot_oil_target(sim) \
					and sim.buy_oil() == Simulation.CommandResult.OK:
				pass  # refused: no oil block, full, or too poor
		if upgrades and lighthouse and not lighthouse_refused \
				and sim.state.towers.size() >= BUILD_FIRST and lighthouse_next(sim, strat):
			if sim.upgrade_lighthouse() != Simulation.CommandResult.OK:
				lighthouse_refused = true
			continue
		if upgrades and sim.state.towers.size() >= BUILD_FIRST:
			var up := next_upgrade(sim, strat)
			if not up.is_empty():
				if sim.upgrade_tower(up[0], up[1]) != Simulation.CommandResult.OK:
					break
				continue
		var id := order(strat, idx, sim, built)
		if strat == "mixed" and cfg.towers[id].kind == "occult" \
				and not cap_allows(sim, strat, cfg.towers[id].levels[0].sanity_reserve):
			idx += 1  # blocked occult item: skip to the next one in the order
			continue
		if id == "":
			# Occult bot, blocked and out of riflemen: any upgrade that passes the cap
			# guard if there is one (even below BUILD_FIRST towers), else save.
			var up := next_upgrade(sim, strat) if upgrades else []
			if up.is_empty() or sim.upgrade_tower(up[0], up[1]) != Simulation.CommandResult.OK:
				break
			continue
		var cell := Placement.best_cell(cfg, sim, id, score_cache)
		var in_sign := cfg.towers[id].kind == "mundane" and Placement.in_shadow_radius(sim, cell)
		if cell.x < 0 or sim.build_tower(id, cell) != Simulation.CommandResult.OK:
			break
		if in_sign:
			shadowed_builds += 1
		built[id] = built.get(id, 0) + 1
		idx += 1
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


## Night: fires the flare when at least FLARE_MIN_LIVE live enemies (reals and fakes, as a
## player sees them) are on the map (LT-69: the flare lights the whole map; e.lit is not the
## count, it is set by the beams before firing). Refused on cooldown or without oil.
func night_flare(sim: Simulation) -> void:
	if not flare:
		return
	var live := 0
	for e in sim.state.enemies:
		if e.is_live():
			live += 1
	if live >= FLARE_MIN_LIVE:
		sim.fire_flare()


## The bot's next upgrade as [tower_id, branch], or [] when no tower can go further for it:
## the cheapest target (gold) over the towers in id order, ties -> lower id. Skips a tower
## whose L3 pick is missing from BRANCH_PICK or has_pending(), and (occult, mixed) an
## upgrade whose reserve delta fails the cap guard (_cap_allows).
func next_upgrade(sim: Simulation, strat: String) -> Array:
	var picks: Dictionary = BRANCH_PICK.get(strat, {}).duplicate()
	picks.merge(branch_override, true)
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
		if not cap_allows(sim, strat, sim.reserve_delta(t.def.id, t.stats(), target)):
			continue
		if best.is_empty() or target.upgrade_cost < best_cost \
				or (target.upgrade_cost == best_cost and t.id < best[0]):
			best = [t.id, branch]
			best_cost = target.upgrade_cost
	return best

