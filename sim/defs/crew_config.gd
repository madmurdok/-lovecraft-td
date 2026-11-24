class_name CrewConfig
extends RefCounted
## LT-32 §2.1: data/crew.json, the optional crew block. Crew is hired by day into a reserve
## per crew kind; a crewed tower (keyed by its tower id) needs `per_tower` men of its own
## kind, and at night `post.crew` reserve men of any kind can be deployed as a reserve post:
## not a tower, plain riflemen with the `post` stats. Absent file -> GameConfig.crew is null
## (crew off); `enabled: false` -> parsed and validated, but GameConfig.crew_on() is false.

const FIELDS := ["enabled", "post", "crews"]
const POST_FIELDS := ["name", "crew", "range", "damage", "fire_interval"]
const CREW_FIELDS := ["name", "per_tower", "hire", "post"]
## Q3 (a): the synthetic TowerDef id of every reserve post. Never a key of config.towers.
const POST_ID := "post"

var enabled := true
var post: Post
## Crew kind (= the crewed tower id) -> its row, in file order.
var crews: Dictionary[String, CrewKind] = {}


## The men and stats of a reserve post: the shared `post` block or a kind's override.
class Post:
	extends RefCounted

	var crew: int  ## men a deploy takes from the reserve, >= 1
	## Synthetic: id POST_ID, kind mundane, cost 0, one level (L1), no branches.
	var def: TowerDef


## One crew kind (crew.json `crews.<tower id>`).
class CrewKind:
	extends RefCounted

	var id: String  ## the crewed tower id
	var name: String  ## player-facing plural ("Harpooners")
	var per_tower: int  ## men a tower of this kind needs, >= 1
	var hire: int  ## money per man, >= 0
	## Optional per-kind post (parsed, not shipped); null = the shared `post`.
	var post: Post


static func parse(r: ConfigReader, root: Dictionary) -> CrewConfig:
	r.check_keys(root, FIELDS, "")
	var c := CrewConfig.new()
	c.enabled = r.req_bool(root, "enabled", "")
	var po: Variant = r.req_object(root, "post", "")
	if po != null:
		c.post = _parse_post(r, po, "post")
	var crews: Variant = r.req_object(root, "crews", "")
	if crews != null:
		for id: Variant in crews:
			var path := ConfigReader.join("crews", str(id))
			if not r.check_id(str(id), path):
				continue
			var co: Variant = r.as_object(crews[id], path)
			if co != null:
				c.crews[str(id)] = _parse_kind(r, str(id), co, path)
	return c


static func _parse_kind(r: ConfigReader, id: String, o: Dictionary, path: String) -> CrewKind:
	r.check_keys(o, CREW_FIELDS, path)
	var k := CrewKind.new()
	k.id = id
	k.name = r.req_string(o, "name", path)
	k.per_tower = r.req_int(o, "per_tower", path, 1)
	k.hire = r.req_int(o, "hire", path, 0)
	if o.has("post"):
		var pp := ConfigReader.join(path, "post")
		var po: Variant = r.as_object(o["post"], pp)
		if po != null:
			k.post = _parse_post(r, po, pp)
	return k


## `post` / `crews.<id>.post`: crew >= 1 plus one L1 level parsed by TowerDef.Level.parse
## (its own range / damage / fire_interval checks apply), kind mundane.
static func _parse_post(r: ConfigReader, o: Dictionary, path: String) -> Post:
	r.check_keys(o, POST_FIELDS, path)
	var p := Post.new()
	p.crew = r.req_int(o, "crew", path, 1)
	var lv := {}
	for key in ["range", "damage", "fire_interval"]:
		if o.has(key):
			lv[key] = o[key]
	var d := TowerDef.new()
	d.id = POST_ID
	d.name = r.opt_string(o, "name", path, "Reserve post")
	d.short_name = d.name
	d.kind = "mundane"
	d.glyph = d.name.left(1)
	d.cost = 0
	var l := TowerDef.Level.parse(r, lv, path, false, d.kind, false)
	if o.has("damage") and l.damage <= 0.0:
		r.error(ConfigReader.join(path, "damage"), "must be > 0 (a post is a shooter)")
	elif not o.has("damage"):
		r.error(ConfigReader.join(path, "damage"), "missing required field")
	d.levels.append(l)
	p.def = d
	return p


## The post a deploy of crew kind `kind` makes: the kind's override, else the shared one.
func post_of(kind: String) -> Post:
	var k: CrewKind = crews.get(kind)
	if k != null and k.post != null:
		return k.post
	return post
