class_name CrewPanel
extends VBoxContainer
## LT-32 §4: crew view of the side panel (the LighthousePanel pattern), opened by the HUD's
## crew button while crew is on. One row per crew kind (crew.json order): "Harpooners: 4 in
## reserve, 2 on duty" over a "Hire (+1, $25)" button, disabled with the reason whenever
## Simulation.can_hire refuses (by day only). A short note says how the reserve is used:
## a crewed tower takes men from it first and hires the rest at build (LT-118), and at
## night a free cell takes a reserve post.
## LT-78: one field group, rebuilt only when a sim event marks it (REFRESH_ON, flush);
## open() syncs it. `visible` is "the crew view is shown"; SidePanel shows its idle text
## otherwise.

const G_ROWS := 1  ## the one field group: reserve, on-duty counts and hire buttons
## Sim event -> the groups it may change (reserve, on duty, money, phase, outcome).
const REFRESH_ON: Dictionary[SimEvent.Type, int] = {
	SimEvent.Type.CREW_CHANGED: G_ROWS,
	SimEvent.Type.POST_DEPLOYED: G_ROWS,
	SimEvent.Type.POST_REMOVED: G_ROWS,
	SimEvent.Type.TOWER_BUILT: G_ROWS,
	SimEvent.Type.TOWER_SOLD: G_ROWS,
	SimEvent.Type.GOLD_CHANGED: G_ROWS,
	SimEvent.Type.BUILD_STARTED: G_ROWS,
	SimEvent.Type.WAVE_STARTED: G_ROWS,
	SimEvent.Type.WAVE_CLEARED: G_ROWS,
	SimEvent.Type.OUTCOME: G_ROWS,
}
const TITLE_TEXT := "Crew reserve"

var game: Game
var title_label: Label
var note_label: Label
var counts: Dictionary[String, Label] = {}  ## crew kind -> its "in reserve, on duty" line
var hire_buttons: Dictionary[String, Button] = {}  ## crew kind -> its Hire button
var refresh_count := 0  ## LT-78 §8 B1: field group rebuilds so far (refresh and flush)
var _dirty := 0  ## groups marked by on_event since the last flush


func _ready() -> void:
	visible = false
	title_label = SidePanel.make_label("Title")
	title_label.text = TITLE_TEXT
	add_child(title_label)
	if game.sim.config.crew_on():
		for kind: String in game.sim.config.crew.crews:
			var line := SidePanel.make_label("Count_" + kind, SidePanel.COLOR_ROLE)
			add_child(line)
			counts[kind] = line
			var b := SidePanel.make_button("Hire_" + kind, _on_hire_pressed.bind(kind))
			add_child(b)
			hire_buttons[kind] = b
	note_label = SidePanel.make_label("Note", SidePanel.COLOR_INFO)
	note_label.add_theme_font_size_override("font_size", StatsTable.FONT_SIZE)
	add_child(note_label)
	add_child(SidePanel.make_button("CancelButton", close, "Cancel"))


func open() -> void:
	visible = true
	refresh()


func close() -> void:
	visible = false


## LT-78 §1: full sync (open, tests).
func refresh() -> void:
	_dirty = 0
	_rebuild(G_ROWS)


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


## Men of crew `kind` on the board now: on its towers and on posts of that kind.
static func on_duty(sim: Simulation, kind: String) -> int:
	var n := 0
	for t in sim.state.towers:
		if (t.crew_kind if t.post else t.def.id) == kind:
			n += t.crew
	return n


## "Harpooners: 4 in reserve, 2 on duty".
static func count_text(sim: Simulation, kind: String) -> String:
	return "%s: %d in reserve, %d on duty" % [sim.config.crew.crews[kind].name,
		sim.crew_reserve().get(kind, 0), on_duty(sim, kind)]


func _rebuild(mask: int) -> void:
	if not visible or not (mask & G_ROWS):
		return
	refresh_count += 1
	var sim := game.sim
	for kind: String in hire_buttons:
		counts[kind].text = count_text(sim, kind)
		var b := hire_buttons[kind]
		var r := sim.can_hire(kind)
		b.disabled = r != SimCommand.CommandResult.OK
		b.text = "Hire 1 (%s)" % TowerText.money(sim.config.crew.crews[kind].hire)
		if b.disabled:
			b.text += " (%s)" % CommandText.reason(r, "hire")
	var post := sim.config.crew.post if sim.config.crew_on() else null
	note_label.text = "" if post == null else (
		"A crewed tower takes men from the reserve first; any it lacks are hired at build.\n"
		+ "At night, click a free cell to deploy a reserve post: %d men of one kind,"
		+ " fighting as riflemen. Posts return to the reserve at dawn.") % post.crew


func _on_hire_pressed(kind: String) -> void:
	game.commands.hire(kind)
