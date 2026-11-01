class_name TowerPanel
extends VBoxContainer
## Tower view of the side panel for a clicked tower (LT-7, LT-24 §4): name and level, role
## (the branch role at L3), current stats (TowerInfo), the upgrade button (L1) or the two
## branch buttons (L2) with their deltas, the target priority switch (LT-31; hidden for an
## aura tower), "Max level" at L3, and Sell with the refund
## Simulation.sell_refund reports now. Buttons are disabled with the reason whenever
## Simulation.can_upgrade refuses them; refresh() re-reads everything each frame.
## `visible` is "the tower view is shown"; SidePanel shows its idle text otherwise.

const MADNESS_WARNING := TowerInfo.MADNESS_WARNING
const PRIORITY_MARK := "▸ "  ## prefixes the current target priority (LT-31)

var game: Game
var tower_id := 0
var title_label: Label
var role_label: Label
var stats_label: Label
var upgrade_title: Label
var max_label: Label
## Upgrade branch ("" = L1 -> L2, "a"/"b" = L2 -> L3) -> its button / its role + delta text.
## All three exist; refresh() shows those Simulation.upgrade_branches accepts now.
var upgrade_buttons: Dictionary[String, Button] = {}
var upgrade_infos: Dictionary[String, Label] = {}
var sell_button: Button
var priority_title: Label
## SimTower.TARGET_PRIORITIES mode -> its button; the current mode is marked and disabled.
var priority_buttons: Dictionary[String, Button] = {}


func _ready() -> void:
	visible = false
	title_label = SidePanel.make_label("Title")
	add_child(title_label)
	role_label = SidePanel.make_label("Role", SidePanel.COLOR_ROLE)
	add_child(role_label)
	stats_label = SidePanel.make_label("Stats", SidePanel.COLOR_INFO)
	add_child(stats_label)
	priority_title = SidePanel.make_label("PriorityTitle")
	priority_title.text = "── Target ──"
	priority_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(priority_title)
	for mode: String in SimTower.TARGET_PRIORITIES:
		var pb := SidePanel.make_button("Priority_" + mode, _on_priority_pressed.bind(mode))
		add_child(pb)
		priority_buttons[mode] = pb
	upgrade_title = SidePanel.make_label("UpgradeTitle")
	upgrade_title.text = "── Upgrade ──"
	upgrade_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(upgrade_title)
	for branch: String in [""] + Array(TowerDef.BRANCH_IDS):
		var key := "L2" if branch.is_empty() else branch.to_upper()
		var b := SidePanel.make_button("Upgrade_" + key, _on_upgrade_pressed.bind(branch))
		add_child(b)
		upgrade_buttons[branch] = b
		var info := SidePanel.make_label("UpgradeInfo_" + key, SidePanel.COLOR_INFO)
		add_child(info)
		upgrade_infos[branch] = info
	max_label = SidePanel.make_label("MaxLevel")
	max_label.text = "Max level"
	add_child(max_label)
	sell_button = SidePanel.make_button("SellButton", _on_sell_pressed)
	add_child(sell_button)
	add_child(SidePanel.make_button("CancelButton", close, "Cancel"))


func open_for(p_tower_id: int) -> void:
	var t := game.sim.tower_by_id(p_tower_id)
	if t == null:
		return
	tower_id = p_tower_id
	visible = true
	game.board.selected_cell = t.cell
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	game.board.selected_cell = Vector2i(-1, -1)
	game.board.selected_range = 0.0
	game.board.queue_redraw()


## Closes itself once the tower is gone; otherwise re-reads level, stats, the upgrade
## buttons (cost, can_upgrade, sanity warning), the refund and the range ring.
func refresh() -> void:
	if not visible:
		return
	var t := game.sim.tower_by_id(tower_id)
	if t == null:
		close()
		return
	var s := t.stats()
	var at_max := t.level >= TowerDef.LEVEL_COUNT
	title_label.text = "%s  L%d" % [t.def.name, t.level + 1]
	if at_max:
		title_label.text += " · " + s.name
	role_label.text = s.role if at_max else t.def.role
	role_label.visible = not role_label.text.is_empty()
	stats_label.text = "\n".join(TowerInfo.lines(t.def, s, game.sim.config.sanity,
		game.sim.state.sanity))
	_refresh_priority(t)
	var branches := game.sim.upgrade_branches(t)
	upgrade_title.visible = not branches.is_empty()
	max_label.visible = branches.is_empty()
	for branch: String in upgrade_buttons:
		var b := upgrade_buttons[branch]
		var info := upgrade_infos[branch]
		var target: TowerDef.Level = game.sim.upgrade_target(t, branch) if branches.has(branch) else null
		b.visible = target != null
		info.visible = target != null
		if target == null:
			continue
		_refresh_upgrade(b, info, t, s, branch, target)
	# LT-27 §3: towers are sold by day only.
	var sell := game.sim.can_sell_tower(t.id)
	sell_button.disabled = sell != Simulation.CommandResult.OK
	sell_button.text = "Sell (+%s)" % TowerInfo.money(game.sim.sell_refund(t))
	if sell_button.disabled:
		sell_button.text += " (%s)" % TowerInfo.reason(sell)
	if game.board.selected_range != s.range_cells:
		game.board.selected_range = s.range_cells
		game.board.queue_redraw()


func _refresh_upgrade(b: Button, info: Label, t: SimTower, s: TowerDef.Level, branch: String,
		target: TowerDef.Level) -> void:
	var r := game.sim.can_upgrade(t.id, branch)
	b.disabled = r != Simulation.CommandResult.OK
	var label := "Upgrade to L%d" % (t.level + 2) if branch.is_empty() else target.name
	var text := label + TowerInfo.DASH + TowerInfo.cost_text(target.upgrade_cost)
	if b.disabled:
		text += " (%s)" % TowerInfo.reason(r)
	elif game.sim.would_drive_mad_upgrade(t.id, branch):
		text += MADNESS_WARNING
	b.text = text
	var lines := PackedStringArray()
	if not target.role.is_empty():
		lines.append(target.role)
	lines.append_array(TowerInfo.delta_lines(s, target))
	info.text = "\n".join(lines)


## LT-31: shown only when the tower picks targets (Simulation.has_targeting). The current
## mode is marked and disabled; the others are disabled with the reason when
## can_set_target_priority refuses (run over).
func _refresh_priority(t: SimTower) -> void:
	var shown := game.sim.has_targeting(t)
	priority_title.visible = shown
	for mode: String in priority_buttons:
		var b := priority_buttons[mode]
		b.visible = shown
		if not shown:
			continue
		var current := mode == t.target_priority
		var r := game.sim.can_set_target_priority(t.id, mode)
		var text: String = TowerInfo.PRIORITY_NAMES.get(mode, mode)
		if current:
			text = PRIORITY_MARK + text
		elif r != Simulation.CommandResult.OK:
			text += " (%s)" % TowerInfo.reason(r)
		b.text = text
		b.disabled = current or r != Simulation.CommandResult.OK
		# The current mode is disabled but must read as selected, not as unavailable.
		if current:
			b.add_theme_color_override("font_disabled_color", SidePanel.COLOR_ROLE)
		else:
			b.remove_theme_color_override("font_disabled_color")


func _on_upgrade_pressed(branch: String) -> void:
	game.upgrade(tower_id, branch)


func _on_priority_pressed(mode: String) -> void:
	game.set_target_priority(tower_id, mode)


func _on_sell_pressed() -> void:
	game.sell(tower_id)
	close()
