class_name MonsterCard
extends VBoxContainer
## LT-66 §5: the side panel's monster view for an enemy clicked at night (Board.enemy_clicked):
## name, ground/flying and pack size, HP, speed and armour against their base, leak, drain,
## traits, its markers now and the madness buff. Reads only `game.snapshot.enemy(id)`
## (EnemyRecord) and its def, so a fake and a real enemy of one kind read the same (LT-12);
## a revealed fake gets the board's own tell, " (hallucination)" after the name (LT-49).
## Refreshed by on_stepped (after the snapshot rebuild) only when the shown key changed; no
## _process (G6c). Closes when its enemy dies, leaks or dissolves, or leaves the snapshot.
## `visible` is "the monster view is shown"; SidePanel shows its idle text otherwise.

const HALLUCINATION_SUFFIX := " (hallucination)"
## Marker -> the word on the "Now" line; an unknown marker shows as itself.
const MARKER_WORDS := {"slow": "slowed", "vuln": "vulnerable", "bleed": "bleeding",
	"sealed": "sealed"}
const MADNESS_TEXT := "faster, takes more damage"
## Row names, top to bottom: each is a key label and a value label in `grid`.
const ROWS := ["HP", "Speed", "Armour", "Leak", "Drain", "Traits", "Now", "Madness"]

var game: Game
var enemy_id := 0  ## the shown enemy; 0 while hidden
var title_label: Label
var kind_label: Label  ## "Ground · comes in packs of 4–6"
var grid: GridContainer
var values: Dictionary[String, Label] = {}  ## row name -> its value label
var keys: Dictionary[String, Label] = {}  ## row name -> its key label
var rebuild_count := 0  ## rebuilds so far (open_for and on_stepped)
var _shown_key: Array = []


func _ready() -> void:
	visible = false
	add_theme_constant_override("separation", 2)
	title_label = SidePanel.make_label("Title")
	add_child(title_label)
	kind_label = SidePanel.make_label("Kind", SidePanel.COLOR_ROLE)
	add_child(kind_label)
	grid = GridContainer.new()
	grid.name = "Rows"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	add_child(grid)
	for row: String in ROWS:
		var k := Label.new()
		k.name = "Key_" + row
		k.text = row
		k.add_theme_color_override("font_color", StatsTable.COLOR_LABEL)
		grid.add_child(k)
		keys[row] = k
		var v := SidePanel.make_label("Value_" + row, StatsTable.COLOR_VALUE)
		grid.add_child(v)
		values[row] = v


func open_for(id: int) -> void:
	if game.snapshot.enemy(id) == null:
		return
	enemy_id = id
	_shown_key = []
	visible = true
	game.selection.show_enemy(id)
	_rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	enemy_id = 0
	_shown_key = []
	game.selection.show_enemy(0)


## Closes on its enemy's DIED, LEAKED or FAKE_DISSOLVED.
func on_event(ev: SimEvent) -> void:
	if not visible or ev.id != enemy_id:
		return
	match ev.type:
		SimEvent.Type.DIED, SimEvent.Type.LEAKED, SimEvent.Type.FAKE_DISSOLVED:
			close()


## Game.advance, on frames with sim steps, after the snapshot rebuild: rebuilds when the
## shown key changed; closes when the enemy left the snapshot.
func on_stepped() -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	var r := game.snapshot.enemy(enemy_id)
	if r == null:
		close()
		return
	var key := shown_key(r)
	if key == _shown_key:
		return
	_shown_key = key
	rebuild_count += 1
	var t := card_text(r)
	title_label.text = t["title"]
	kind_label.text = t["kind"]
	for row: String in ROWS:
		var shown: bool = t.has(row)
		keys[row].visible = shown
		values[row].visible = shown
		values[row].text = t.get(row, "")


## What the card shows changes only with these (rounded HP, speed, armour, markers, lit,
## madness, revealed); the def is fixed per id.
static func shown_key(r: EnemyRecord) -> Array:
	return [r.id, roundi(r.hp), roundi(r.max_hp), snappedf(r.speed, 0.01),
		snappedf(r.armor, 0.01), r.markers, r.lit, r.madness_buffed, r.revealed]


## The card's text by line ("title", "kind", then ROWS names; Madness only while buffed),
## from the record and its def only.
static func card_text(r: EnemyRecord) -> Dictionary:
	var d := r.def
	var out := {}
	out["title"] = d.name + (HALLUCINATION_SUFFIX if r.revealed else "")
	var kind := "Flying" if d.flying else "Ground"
	if d.traits.has("pack"):
		kind += " · comes in packs of " + _pack_size(d.traits["pack"])
	out["kind"] = kind
	out["HP"] = "%d / %d" % [ceili(r.hp), ceili(r.max_hp)]
	out["Speed"] = "%s cells/s  (base %s)" % [TowerText.num(snappedf(r.speed, 0.01)),
		TowerText.num(snappedf(r.base_speed, 0.01))]
	out["Armour"] = "%s  (base %s)" % [TowerText.num(r.armor), TowerText.num(d.armor)]
	out["Leak"] = "%d lighthouse HP" % d.leak_damage
	out["Drain"] = "%s sanity/s near towers" % TowerText.num(d.horror_drain) \
		if d.horror_drain > 0.0 else TowerText.CELL_DASH
	out["Traits"] = traits_text(d)
	var now := PackedStringArray()
	for m: String in r.markers:
		now.append(MARKER_WORDS.get(m, m))
	if r.lit:
		now.append("lit")
	out["Now"] = " · ".join(now) if not now.is_empty() else TowerText.CELL_DASH
	if r.madness_buffed:
		out["Madness"] = MADNESS_TEXT
	return out


## The def's traits, one short phrase each, in the def's key order; a dash for none.
static func traits_text(d: EnemyDef) -> String:
	var out := PackedStringArray()
	for id: String in d.traits:
		var p: Dictionary = d.traits[id] if d.traits[id] is Dictionary else {}
		match id:
			"pack":
				out.append("Pack " + _pack_size(p))
			"regen":
				out.append("Regenerates %s%%/s" % TowerText.num(p.get("hp_percent_per_second",
					0.0)))
			"tower_harass":
				out.append("Harasses towers")
			"tower_lift":
				out.append("Lifts towers" + (" from wave %d" % int(p["from_wave"])
					if p.has("from_wave") else ""))
			_:
				out.append(id.replace("_", " ").capitalize())
	return ", ".join(out) if not out.is_empty() else TowerText.CELL_DASH


static func _pack_size(p: Variant) -> String:
	if not p is Dictionary:
		return "?"
	var lo := int(p.get("min", 0))
	var hi := int(p.get("max", lo))
	return str(lo) if lo == hi else "%d–%d" % [lo, hi]
