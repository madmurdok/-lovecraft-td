class_name LighthousePanel
extends VBoxContainer
## Lighthouse view of the side panel (LT-30 §3.2), opened by a click on the lighthouse cell:
## level, beams, how much of the sea the beams cover, the upgrade button (money, by day) and
## the lamp oil stock with "Buy oil for a flare" (by day; LT-57: one flare's oil per click). Buttons are disabled with the reason whenever
## the sim refuses the command. LT-78: a field group is rebuilt only when a sim event marks
## it (REFRESH_ON, flush); refresh() syncs every group on open.
## `visible` is "the lighthouse view is shown"; SidePanel shows its idle text otherwise.

## LT-78 §1: field groups (bits of _dirty).
const G_HEAD := 1  ## title, beams and coverage
const G_UPGRADE := 2  ## the upgrade button
const G_OIL := 4  ## oil stock and flare line, "Buy oil"
const G_ALL := 7
const _PH := G_UPGRADE | G_OIL  ## phase events: day-only commands
## LT-78 §3 (rows 48-52): sim event -> the groups it may change.
const REFRESH_ON: Dictionary[SimEvent.Type, int] = {
	SimEvent.Type.LIGHTHOUSE_UPGRADED: G_ALL,
	SimEvent.Type.GOLD_CHANGED: G_UPGRADE | G_OIL,
	SimEvent.Type.OIL_CHANGED: G_OIL,
	SimEvent.Type.BUILD_STARTED: _PH,
	SimEvent.Type.WAVE_STARTED: _PH,
	SimEvent.Type.WAVE_CLEARED: _PH,
	SimEvent.Type.OUTCOME: _PH,
}

var game: Game
var title_label: Label
var stats_label: Label
var upgrade_button: Button
var oil_label: Label
var oil_button: Button
var refresh_count := 0  ## LT-78 §8 B1: field groups rebuilt so far (refresh and flush)
var _dirty := 0  ## groups marked by on_event since the last flush


func _ready() -> void:
	visible = false
	title_label = SidePanel.make_label("Title")
	add_child(title_label)
	stats_label = SidePanel.make_label("Stats", SidePanel.COLOR_INFO)
	add_child(stats_label)
	upgrade_button = SidePanel.make_button("UpgradeButton", game.commands.upgrade_lighthouse)
	add_child(upgrade_button)
	oil_label = SidePanel.make_label("OilLabel", SidePanel.COLOR_INFO)
	add_child(oil_label)
	oil_button = SidePanel.make_button("BuyOilButton", game.commands.buy_flare_oil)
	add_child(oil_button)
	add_child(SidePanel.make_button("CancelButton", close, "Cancel"))


func open() -> void:
	visible = true
	game.board.selected_cell = game.sim.state.map.lighthouse
	game.board.selected_range = 0.0
	game.board.selected_cast = ""
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.queue_redraw()


## Share (0..1) of the full circle that `beams` beams of half-width ratio
## `half_width_ratio` cover: each beam is the cone cross² <= k² dot² of Simulation._lit_by,
## 2 atan(k) wide; overlaps are not counted twice, so it caps at 1. Display only: it lives
## here, not in sim/rules, because the sim never needs it and sim/ is trig-free
## (beam_test.test_the_sim_has_no_trig, LT-76 verify).
static func beam_coverage(beams: int, half_width_ratio: float) -> float:
	return minf(1.0, beams * atan(half_width_ratio) / PI)


## Share of the full circle the beams cover (beam_coverage), in percent.
static func coverage_percent(beams: int, half_width_ratio: float) -> int:
	return roundi(100.0 * beam_coverage(beams, half_width_ratio))


## LT-78 §1: full sync of every group (open, tests).
func refresh() -> void:
	_dirty = 0
	_rebuild(G_ALL)


## LT-78 §1: marks the groups `ev` may change; flush() rebuilds them once per drain.
func on_event(ev: SimEvent) -> void:
	_dirty |= REFRESH_ON.get(ev.type, 0)


## LT-78 §1: rebuilds the marked groups; a hidden view drops the marks (open syncs it).
func flush() -> void:
	if _dirty == 0:
		return
	var mask := _dirty
	_dirty = 0
	_rebuild(mask)


func _rebuild(mask: int) -> void:
	if not visible:
		return
	if mask & G_HEAD:
		refresh_count += 1
		_refresh_head()
	if mask & G_UPGRADE:
		refresh_count += 1
		_refresh_upgrade()
	if mask & G_OIL:
		refresh_count += 1
		_refresh_oil()


func _refresh_head() -> void:
	var sim := game.sim
	var beams := sim.beam_count()
	title_label.text = "Lighthouse  L%d" % (sim.state.lighthouse_level + 1)
	stats_label.text = "Beams: %d\nCoverage: %d %%\nThe lamp is lit at night only." % [
		beams, coverage_percent(beams, sim.config.economy.beam.half_width_ratio)]


func _refresh_upgrade() -> void:
	var sim := game.sim
	var eco := sim.config.economy
	var level := sim.state.lighthouse_level
	var cost := sim.lighthouse_upgrade_cost()
	var up := sim.can_upgrade_lighthouse()
	if cost == 0:
		upgrade_button.text = "Max level"
	else:
		var next_beams: int = eco.beam.levels[level + 1].beams
		var next_flare := ""
		if eco.flare != null and level + 1 < eco.flare.seconds.size():
			next_flare = ", flare %s s" % ConfigReader.fmt(eco.flare.seconds[level + 1])
		upgrade_button.text = "Upgrade: %d beams%s (%s)" % [next_beams, next_flare,
			TowerText.money(cost)]
		if CommandText.panel_reason(up) != "":
			upgrade_button.text += "\n" + CommandText.panel_reason(up)
	upgrade_button.disabled = up != SimCommand.CommandResult.OK


func _refresh_oil() -> void:
	var sim := game.sim
	var eco := sim.config.economy
	var has_oil := eco.oil != null
	oil_label.visible = has_oil
	oil_button.visible = has_oil
	if not has_oil:
		return
	oil_label.text = "Lamp oil: %d / %d" % [sim.state.oil, sim.oil_cap()]
	if eco.flare != null:
		oil_label.text += "\nFlare: %d oil, whole map, %s s; fired at night." % [
			sim.flare_cost_oil(), ConfigReader.fmt(sim.flare_seconds())]
	var buy := sim.can_buy_oil()
	if eco.flare != null:
		var units := sim.oil_for_flare()
		if units == 0:
			units = sim.flare_cost_oil()
		oil_button.text = "Buy oil for a flare (%s)" % TowerText.money(units * eco.oil.price)
	else:
		oil_button.text = "Buy oil (%s)" % TowerText.money(eco.oil.price)
	if buy != SimCommand.CommandResult.OK and CommandText.panel_reason(buy) != "":
		oil_button.text += "\n" + CommandText.panel_reason(buy)
	oil_button.disabled = buy != SimCommand.CommandResult.OK
