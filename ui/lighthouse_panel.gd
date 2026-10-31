class_name LighthousePanel
extends VBoxContainer
## Lighthouse view of the side panel (LT-30 §3.2), opened by a click on the lighthouse cell:
## level, beams, how much of the sea the beams cover, the upgrade button (money, by day) and
## the lamp oil stock with "Buy oil" (by day). Buttons are disabled with the reason whenever
## the sim refuses the command; refresh() re-reads everything each frame.
## `visible` is "the lighthouse view is shown"; SidePanel shows its idle text otherwise.

const REASONS := {
	Simulation.CommandResult.MAX_LEVEL: "Max level",
	Simulation.CommandResult.NOT_BUILD_PHASE: "By day only",
	Simulation.CommandResult.NOT_ENOUGH_GOLD: "Not enough money",
	Simulation.CommandResult.OIL_FULL: "Tank full",
}

var game: Game
var title_label: Label
var stats_label: Label
var upgrade_button: Button
var oil_label: Label
var oil_button: Button


func _ready() -> void:
	visible = false
	title_label = SidePanel.make_label("Title")
	add_child(title_label)
	stats_label = SidePanel.make_label("Stats", SidePanel.COLOR_INFO)
	add_child(stats_label)
	upgrade_button = SidePanel.make_button("UpgradeButton", game.upgrade_lighthouse)
	add_child(upgrade_button)
	oil_label = SidePanel.make_label("OilLabel", SidePanel.COLOR_INFO)
	add_child(oil_label)
	oil_button = SidePanel.make_button("BuyOilButton", game.buy_oil)
	add_child(oil_button)
	add_child(SidePanel.make_button("CancelButton", close, "Cancel"))


func open() -> void:
	visible = true
	game.board.selected_cell = game.sim.state.map.lighthouse
	game.board.selected_range = 0.0
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.queue_redraw()


## Share of the full circle the beams cover, in percent (render-side trig).
static func coverage_percent(beams: int, half_width_ratio: float) -> int:
	return roundi(100.0 * minf(1.0, beams * atan(half_width_ratio) / PI))


func refresh() -> void:
	if not visible:
		return
	var sim := game.sim
	var eco := sim.config.economy
	var level := sim.state.lighthouse_level
	var beams := sim.beam_count()
	title_label.text = "Lighthouse  L%d" % (level + 1)
	stats_label.text = "Beams: %d\nCoverage: %d %%\nThe lamp is lit at night only." % [
		beams, coverage_percent(beams, eco.beam.half_width_ratio)]
	var cost := sim.lighthouse_upgrade_cost()
	var up := sim.can_upgrade_lighthouse()
	if cost == 0:
		upgrade_button.text = "Max level"
	else:
		var next_beams: int = eco.beam.levels[level + 1].beams
		upgrade_button.text = "Upgrade: %d beams (%s)" % [next_beams, TowerInfo.money(cost)]
		if REASONS.has(up):
			upgrade_button.text += "\n" + REASONS[up]
	upgrade_button.disabled = up != Simulation.CommandResult.OK
	var has_oil := eco.oil != null
	oil_label.visible = has_oil
	oil_button.visible = has_oil
	if not has_oil:
		return
	oil_label.text = "Lamp oil: %d / %d" % [sim.state.oil, eco.oil.cap]
	if eco.flare != null:
		oil_label.text += "\nFlare costs %d oil; fired at night." % eco.flare.cost_oil
	var buy := sim.can_buy_oil()
	oil_button.text = "Buy oil (%s)" % TowerInfo.money(eco.oil.price)
	if buy != Simulation.CommandResult.OK and REASONS.has(buy):
		oil_button.text += "\n" + REASONS[buy]
	oil_button.disabled = buy != Simulation.CommandResult.OK
