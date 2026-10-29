class_name WavesConfig
extends RefCounted
## waves.json (GDD §8): build phase timer and the ordered wave list.

const FIELDS := ["build_phase_seconds", "waves"]

var build_phase_seconds: float  ## > 0
var waves: Array[Wave] = []


## `enemy_ids` is the set of ids in enemies.json for the cross-reference check,
## or null when enemies.json could not be read (the check is then skipped).
static func parse(r: ConfigReader, root: Dictionary, enemy_ids: Variant) -> WavesConfig:
	r.check_keys(root, FIELDS, "")
	var c := WavesConfig.new()
	c.build_phase_seconds = r.req_number(root, "build_phase_seconds", "", 0.0, INF, true)
	var waves: Variant = r.req_array(root, "waves", "")
	if waves != null:
		if waves.is_empty():
			r.error("waves", "must not be empty")
		for i in waves.size():
			var wp := ConfigReader.index("waves", i)
			var wo: Variant = r.as_object(waves[i], wp)
			if wo != null:
				c.waves.append(Wave.parse(r, wo, wp, enemy_ids))
	return c


class Wave:
	extends RefCounted

	const WAVE_FIELDS := ["groups"]

	var groups: Array[SpawnGroup] = []

	static func parse(r: ConfigReader, obj: Dictionary, path: String, enemy_ids: Variant) -> Wave:
		r.check_keys(obj, WAVE_FIELDS, path)
		var w := Wave.new()
		var groups: Variant = r.req_array(obj, "groups", path)
		if groups != null:
			var gp := ConfigReader.join(path, "groups")
			if groups.is_empty():
				r.error(gp, "must not be empty")
			for i in groups.size():
				var ip := ConfigReader.index(gp, i)
				var go: Variant = r.as_object(groups[i], ip)
				if go != null:
					w.groups.append(SpawnGroup.parse(r, go, ip, enemy_ids))
		return w


## `count` spawn events of `enemy_id`, `interval` s apart, starting `delay` s
## after the wave starts. An enemy with a "pack" trait spawns a pack per event.
class SpawnGroup:
	extends RefCounted

	const GROUP_FIELDS := ["type", "count", "interval", "delay"]

	var enemy_id: String
	var count: int  ## >= 1
	var interval: float  ## >= 0
	var delay: float  ## >= 0

	static func parse(r: ConfigReader, obj: Dictionary, path: String,
			enemy_ids: Variant) -> SpawnGroup:
		r.check_keys(obj, GROUP_FIELDS, path)
		var g := SpawnGroup.new()
		g.enemy_id = r.req_string(obj, "type", path)
		if enemy_ids != null and not g.enemy_id.is_empty() and not enemy_ids.has(g.enemy_id):
			r.error(ConfigReader.join(path, "type"), "unknown enemy \"%s\"" % g.enemy_id)
		g.count = r.req_int(obj, "count", path, 1)
		g.interval = r.req_number(obj, "interval", path, 0.0)
		g.delay = r.opt_number(obj, "delay", path, 0.0, 0.0)
		return g
