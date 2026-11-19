class_name UiSnapshot
extends RefCounted
## LT-78 §4 / §8 B2: a generic walk over a panel's Controls. `take` records, per Control,
## the fields a player can see (text, tooltip, visible, disabled, modulate, font colour,
## and the position of the three nodes the HUD places by hand); `diff` names every field
## that differs between two snapshots. Not a test suite (no _test suffix).

## Nodes driven by a Timer or layout, not by sim events (FPS readouts: fps_readout_test,
## frame_stats_test).
const SKIP_NAMES: PackedStringArray = ["FpsLabel", "FrameLabel"]
## Nodes the HUD places by hand: their position is a displayed field (LT-78 §3 row 16).
const POSITIONED: PackedStringArray = ["FlareButton", "OilLabel", "HostileLabel"]


## {path -> {field -> value}} for `root` and every Control below it.
static func take(root: Node) -> Dictionary:
	var out := {}
	_walk(root, root, out)
	return out


## A path that is stable between runs: auto-named nodes ("@Label@12") are named by class
## and sibling index.
static func path_of(node: Node, root: Node) -> String:
	var parts: PackedStringArray = []
	var n := node
	while n != root and n != null:
		var nm := String(n.name)
		if nm.begins_with("@"):
			nm = "%s#%d" % [n.get_class(), n.get_index()]
		parts.append(nm)
		n = n.get_parent()
	parts.reverse()
	return "." if parts.is_empty() else "/".join(parts)


## "path.field: 'a' -> 'b'" for every field that differs; a path in only one snapshot is
## reported as present/absent.
static func diff(a: Dictionary, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for path: String in b:
		if not a.has(path):
			out.append("%s: absent -> present" % path)
			continue
		for field: String in b[path]:
			if a[path].get(field) != b[path][field]:
				out.append("%s.%s: '%s' -> '%s'" % [path, field, str(a[path].get(field)),
					str(b[path][field])])
	for path: String in a:
		if not b.has(path):
			out.append("%s: present -> absent" % path)
	return out


## The paths present in both snapshots with at least one differing field.
static func changed_paths(a: Dictionary, b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for path: String in b:
		if a.has(path) and a[path] != b[path]:
			out.append(path)
	return out


static func _walk(node: Node, root: Node, out: Dictionary) -> void:
	for c in node.get_children():
		_walk(c, root, out)
	var ctl := node as Control
	if ctl == null or SKIP_NAMES.has(String(ctl.name)):
		return
	var d := {"visible": ctl.visible, "tooltip": ctl.tooltip_text, "modulate": ctl.modulate}
	if ctl is Label:
		d["text"] = (ctl as Label).text
		d["font_color"] = ctl.get_theme_color("font_color")
	if ctl is Button:
		d["text"] = (ctl as Button).text
		d["disabled"] = (ctl as Button).disabled
		d["font_color"] = ctl.get_theme_color("font_color")
	if POSITIONED.has(String(ctl.name)):
		d["position"] = ctl.position
	out[path_of(node, root)] = d
