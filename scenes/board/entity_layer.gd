class_name EntityLayer
extends BoardLayer
## LT-84 (LT-65 §3.4): the board's entities, drawn each board redraw above the phantom path
## and below the effects: aura discs (Elder Sign ward, Searchlight sweep), towers (plate
## tinted by lit / shadow state and the BUILD preview, OverlayLayer.preview_cast), enemies
## (interpolated by the clock alpha, flicker, markers, HP bars) and summoned allies. LT-32:
## a reserve post (SimTower.post) is not a tower: its men are drawn as small rifleman
## figures (_draw_post), with no plate, letter, border or level pips. Reads
## sim state only. Writes `board.last_pos` (enemy id -> drawn position), which the ward
## pulse, FxLayer's hit positions and astray spots read.

const LIT_MARK_COLOR := Color(1.0, 0.95, 0.6)  ## LT-30: tower inside a beam
## LT-70 §5: the plate fill of a lit (amber) and a shadowed (violet) tower, and the weight
## the BUILD preview mixes them into COLOR_TOWER with (fainter than the night state, still
## clearly tinted). The night CanvasModulate (Lighting.AMBIENT_NIGHT ~0.3) greys a pale
## tint out, so the fills are saturated and each state also gets a border (STATE_BORDER px)
## over 1 that stays bright under the darkness, as COLOR_ASTRAY does.
const LIT_TINT := Color(1.0, 0.6, 0.15)
const SHADOW_TINT := Color(0.5, 0.28, 0.95)
const LIT_BORDER := Color(2.8, 1.7, 0.35)
const SHADOW_BORDER := Color(1.5, 0.7, 3.2)
const PREVIEW_TINT_WEIGHT := 0.55
## LT-117: a disabled tower's plate (t.disabled, e.g. a night-gaunt lift) is darkened by this.
const DISABLED_DIM := 0.6
const STATE_BORDER := 3.0
const PREVIEW_BORDER := 2.0
const SHADOW_MARK_COLOR := Color(0.22, 0.12, 0.4)  ## LT-70 §5: the shadowed corner dot
const SHADOW_MARK_RIM := Color(0.85, 0.8, 1.0)  ## its pale rim (reads on a dark plate)
const WARD_SHADOW_FILL := Color(0.05, 0.02, 0.1, 0.22)  ## LT-70 §5: a sign's shadow area
const COLOR_TOWER := Color(0.75, 0.75, 0.80)
const COLOR_ENEMY := Color(0.55, 0.85, 0.55)
const COLOR_ENEMY_MAD := Color(1.0, 0.25, 0.15)  ## LT-23 Q10: hostile tint in madness
const COLOR_ENEMY_OUTLINE := Color(0.03, 0.0, 0.02)  ## LT-23 Q10: dark outline in madness
const COLOR_HP_BACK := Color(0.2, 0, 0)
const COLOR_HP := Color(0.9, 0.2, 0.2)
const COLOR_DEBUG_FAKE := Color(1, 0, 1)  ## debug outline (--reveal-fakes), LT-12 §1
const COLOR_LETTER_PLATE := Color(0.06, 0.05, 0.08)  ## LT-28: contrast plate under the letter
## LT-108 F3: tower marks are offsets from the cell centre (square: today's positions in the
## 28 px plate, the tile inset by PLATE_INSET). Whether they suit a hex plate is LT-64's.
const PLATE_INSET := 6.0  ## the tower plate inside its tile, px
const LETTER_PLATE := Rect2(-10, -10, 15, 19)  ## from the centre, under the 16 px letter
const GLYPH_OFFSET := Vector2(-6, 6)  ## the tower letter's baseline (and the ghost's)
const STATE_MARK_OFFSET := Vector2(8, -8)  ## the lit / shadowed corner dot
const PIP_OFFSET := Vector2(-11, 8)  ## the first 4x4 level pip; each next one PIP_STEP right
const PIP_STEP := 6.0
const BRANCH_OFFSET := Vector2(5, -3)  ## the L3 branch letter
const WARD_COLOR := Color(0.9, 2.0, 1.6)
const WARD_IDLE_ALPHA := 0.25
const WARD_PULSE_LOW := 0.75  ## active ring pulses between this and WARD_ACTIVE_ALPHA
const WARD_ACTIVE_ALPHA := 1.0
const WARD_PULSE_HZ := 1.5
const WARD_TURN_SECONDS := 12.0
const MARK_SLOW_CELLS := 0.34
const MARK_VULN := Color(1.6, 0.7, 2.2)
const MARK_BLEED := Color(1.7, 0.2, 0.15)  ## LT-29: bleed drops below the body
const BLEED_DROP_SECONDS := 0.5  ## one drip loop (decoration, real time)
## LT-49 Searchlight: a faint lit disc at the aura radius with a beam wedge sweeping round
## once per SEARCH_SWEEP_SECONDS; brighter while a drawn enemy is inside (ward_alpha).
const SEARCHLIGHT_COLOR := Color(2.4, 2.2, 1.5)
const SEARCH_SWEEP_SECONDS := 5.0
const SEARCH_CONE := 0.45  ## half angle of the sweeping wedge, radians
const SEARCH_DISC_ALPHA := 0.07
const REVEALED_ALPHA := 0.45  ## body alpha of a revealed fake
## A revealed fake: a ghost-grey body, a bold amber ring outside the dashed slow mark and
## an amber slash across the body ("exposed, ignore"), unlike any other enemy marker.
const REVEALED_BODY := Color(0.62, 0.62, 0.72)
const REVEALED_MARK := Color(2.6, 1.3, 0.3)
const REVEALED_RING_CELLS := 0.44
const REVEALED_SLASH_CELLS := 0.3  ## half length of the slash
## LT-52 Summoning Circle: the tower's rim and letter, a faint leash ring (summon_leash) and
## its units: a bone body with a violet rim (a Byakhee also gets two wing strokes), a teal
## HP bar under the body (enemy bars are red, above), a claw line to the enemy it holds.
## LT-32 §4: a reserve post's figures. The night CanvasModulate (~0.3) would sink the
## attack colour, so the figures are drawn brighter than 1 (as the state borders are),
## over a dark rim that keeps them apart from the tile.
const POST_GLOW := 2.6  ## multiplier on the attack colour of a post's figures
const POST_RIM := Color(0.02, 0.02, 0.03)
const POST_SPREAD_CELLS := 0.3  ## between two figures' centres
const POST_HEAD_CELLS := 0.07  ## head radius
const POST_BODY_CELLS := 0.2  ## body length, neck to feet
const SUMMON_COLOR := Color(2.2, 0.8, 1.7)
const ALLY_BODY := Color(0.86, 0.8, 0.68)
const ALLY_HP := Color(0.35, 1.6, 1.25)
const ALLY_RADIUS_CELLS := 0.2
const SUMMON_RING_ALPHA := 0.18
const BANISH_LID_CELLS := 0.33


func _draw() -> void:
	if not has_sim():
		return
	var s := game.sim.state
	_draw_auras(s)
	for t in s.towers:
		_draw_tower(t)
	_draw_enemies(s)
	_draw_allies(s)


## LT-25 §1.3: the ward ring's alpha: idle while no drawn enemy (`board.last_pos`, real or fake
## alike) is inside its radius, pulsing between WARD_PULSE_LOW and WARD_ACTIVE_ALPHA while
## one is.
func ward_alpha(t: SimTower) -> float:
	var c := t.centre()
	var r := t.stats().range_cells
	for p: Vector2 in board.last_pos.values():
		if p.distance_to(c) <= r:
			var k := 0.5 + 0.5 * sin(board.time * TAU * WARD_PULSE_HZ)
			return lerpf(WARD_PULSE_LOW, WARD_ACTIVE_ALPHA, k)
	return WARD_IDLE_ALPHA


## The colour that links a tower to its attack look (LT-25 §1): LookCatalog.color
## (Color.BLACK for an unknown id).
static func attack_color(kind: String) -> Color:
	return LookCatalog.color(kind)


## LT-70 §5: the tower plate colour from the net sim flags: amber when lit, violet when
## shadowed (never both: cancelled is neither), else COLOR_TOWER; with neither flag, a
## `preview` "light" / "shadow" (preview_cast) mixes the same tint in at PREVIEW_TINT_WEIGHT.
## LT-117: a disabled tower (the channel's last-tick value) gets that colour DISABLED_DIM darker.
static func plate_color(t: SimTower, preview := "") -> Color:
	var c := _plate_tint(t, preview)
	return c.darkened(DISABLED_DIM) if t.disabled else c


static func _plate_tint(t: SimTower, preview: String) -> Color:
	if t.lit:
		return LIT_TINT
	if t.shadowed:
		return SHADOW_TINT
	match preview:
		"light":
			return COLOR_TOWER.lerp(LIT_TINT, PREVIEW_TINT_WEIGHT)
		"shadow":
			return COLOR_TOWER.lerp(SHADOW_TINT, PREVIEW_TINT_WEIGHT)
	return COLOR_TOWER


## LT-70 §5: the state border around the tile: LIT_BORDER / SHADOW_BORDER (over 1) for the
## net flags, the plain tint for a preview, transparent for none.
static func state_border(t: SimTower, preview := "") -> Color:
	if t.lit:
		return LIT_BORDER
	if t.shadowed:
		return SHADOW_BORDER
	match preview:
		"light":
			return LIT_TINT
		"shadow":
			return SHADOW_TINT
	return Color.TRANSPARENT


## LT-108 F3: where a tower's text and marks sit, from its cell centre in world pixels:
## "plate" (the letter plate rect), "glyph", "mark" (lit / shadow dot), "pip" (the first
## level pip's top-left; pip i is PIP_STEP * i to the right) and "branch".
static func tower_anchors(centre: Vector2) -> Dictionary:
	return {"plate": Rect2(centre + LETTER_PLATE.position, LETTER_PLATE.size),
		"glyph": centre + GLYPH_OFFSET, "mark": centre + STATE_MARK_OFFSET,
		"pip": centre + PIP_OFFSET, "branch": centre + BRANCH_OFFSET}


func _draw_tower(t: SimTower) -> void:
	if t.post:
		_draw_post(t)
		return
	var at := tower_anchors(view.cell_centre(t.cell))
	var c := attack_color(Board.shot_kind(t))
	var preview := board.overlay_layer.preview_cast(t)
	view.fill_cell(self, t.cell, plate_color(t, preview), PLATE_INSET)
	var border := state_border(t, preview)
	if border.a > 0.0:  # LT-70 §5: outside the attack-colour frame, inside the cell
		var w := STATE_BORDER if preview.is_empty() else PREVIEW_BORDER
		view.outline_cell(self, t.cell, border, w, PLATE_INSET - (w * 0.5 + 1.0))
	view.outline_cell(self, t.cell, c, 2.0, PLATE_INSET)
	# LT-28: a dark plate under the letter keeps it readable where the beam washes the
	# light tile out (the plate stays dark under the light; the letter's colour is over 1).
	draw_rect(at["plate"], COLOR_LETTER_PLATE)
	draw_string(ThemeDB.fallback_font, at["glyph"], t.def.glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, c)
	# LT-30: a lit tower (a beam sweeps its centre) gets a small bright corner mark.
	if t.lit:
		draw_circle(at["mark"], 3.5, LIT_MARK_COLOR)
	elif t.shadowed:  # LT-70 §5: the same corner, a dark violet dot with a pale rim
		draw_circle(at["mark"], 3.5, SHADOW_MARK_COLOR)
		draw_arc(at["mark"], 3.5, 0, TAU, 12, SHADOW_MARK_RIM, 1.0)
	# LT-24 level mark: one pip per level along the bottom, the branch letter at L3.
	for i in t.level + 1:
		draw_rect(Rect2(at["pip"] + Vector2(PIP_STEP * i, 0), Vector2(4, 4)), Color.BLACK)
	if not t.branch.is_empty():
		draw_string(ThemeDB.fallback_font, at["branch"], t.branch,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)


## LT-32 §4: a reserve post: `t.crew` small figures side by side (head, body, legs and a
## musket held up at a slant) in its attack colour, no plate, letter, border or pips; the
## lit / shadowed corner dot as on a tower, so the beam's effect still reads.
func _draw_post(t: SimTower) -> void:
	var centre := view.cell_centre(t.cell)
	var c := attack_color(Board.shot_kind(t))
	var glow := Color(c.r * POST_GLOW, c.g * POST_GLOW, c.b * POST_GLOW, 1.0)
	var n := maxi(1, t.crew)
	var step := view.cells_to_px(POST_SPREAD_CELLS)
	var head := view.cells_to_px(POST_HEAD_CELLS)
	var body := view.cells_to_px(POST_BODY_CELLS)
	for i in n:
		var x := (i - (n - 1) * 0.5) * step
		var neck := centre + Vector2(x, -body * 0.35)
		var hip := neck + Vector2(0, body * 0.55)
		var lines: Array[PackedVector2Array] = [
			PackedVector2Array([neck, hip]),  # body
			PackedVector2Array([hip, hip + Vector2(-head, body * 0.45)]),  # legs
			PackedVector2Array([hip, hip + Vector2(head, body * 0.45)]),
			PackedVector2Array([neck + Vector2(-head * 0.8, body * 0.3),  # musket
				neck + Vector2(head * 1.6, -body * 0.55)]),
		]
		for l in lines:
			draw_line(l[0], l[1], POST_RIM, 4.0)
		for l in lines:
			draw_line(l[0], l[1], glow, 2.0)
		var h := neck + Vector2(0, -head)
		draw_circle(h, head + 1.0, POST_RIM)
		draw_circle(h, head, glow)
	var mark: Vector2 = tower_anchors(centre)["mark"]
	if t.lit:
		draw_circle(mark, 3.5, LIT_MARK_COLOR)
	elif t.shadowed:
		draw_circle(mark, 3.5, SHADOW_MARK_COLOR)
		draw_arc(mark, 3.5, 0, TAU, 12, SHADOW_MARK_RIM, 1.0)


## Elder Sign wards (LT-25 §1.3): a faint ring at the aura radius with 5 slowly turning
## dashes; brighter and pulsing while a drawn enemy is inside. LT-70 §5: a sign that casts
## shadow gets a faint dark fill, the opposite of the Searchlight's lit disc.
## LT-104: dispatched on the look row's `area`; the colour is the row's.
func _draw_auras(s: SimState) -> void:
	for t in s.towers:
		var look := LookCatalog.row(Board.shot_kind(t))
		var area: String = look["area"]
		if area == "searchlight":
			_draw_searchlight(t, look["color"])
			continue
		if area != "ward":
			continue
		var wc: Color = look["color"]
		var c := view.cell_to_world(t.centre())
		var r := view.cells_to_px(t.stats().range_cells)
		var a := ward_alpha(t)
		var bright := a > WARD_IDLE_ALPHA
		if t.stats().casts_shadow():
			draw_circle(c, r, WARD_SHADOW_FILL)
		draw_arc(c, r, 0, TAU, 64, Color(wc, a), 4.0 if bright else 2.0)
		var rot := board.time * TAU / WARD_TURN_SECONDS
		for i in 5:
			var st := rot + i * TAU / 5.0
			draw_arc(c, r, st, st + 0.22, 6, Color(wc, minf(1.0, a + 0.15)), 4.0)


## LT-49: the Searchlight's aura: a faint disc and rim at the radius, and a beam wedge
## from the tower to the rim turning once per SEARCH_SWEEP_SECONDS (decoration: what is
## revealed is the whole disc, sim state). `sc`: the look's colour (LT-104).
func _draw_searchlight(t: SimTower, sc: Color) -> void:
	var c := view.cell_to_world(t.centre())
	var r := view.cells_to_px(t.stats().range_cells)
	var a := ward_alpha(t)
	draw_circle(c, r, Color(sc, SEARCH_DISC_ALPHA * (1.0 + a)))
	draw_arc(c, r, 0, TAU, 64, Color(sc, a * 0.8), 2.0)
	var dir := board.time * TAU / SEARCH_SWEEP_SECONDS
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([Color(sc, 0.35 + 0.25 * a)])
	var steps := 8
	for i in steps + 1:
		var ang := dir - SEARCH_CONE + 2.0 * SEARCH_CONE * i / steps
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		cols.append(Color(sc, 0.04))
	draw_polygon(pts, cols)


## LT-104: body colour, radius and rim from the enemy's look row (LookCatalog.enemy_look);
## every marker radius and the HP bar move out by the radius above the built-in 0.25 cell.
func _draw_enemies(s: SimState) -> void:
	board.last_pos.clear()
	var fl := board.flicker_strength()
	# LT-23 Q10: the smoothed madness grade tints and outlines every enemy alike.
	var mad := game.sanity_fx.madness if game.sanity_fx != null else 0.0
	for e in s.enemies:
		if not e.is_live():
			continue
		var p := game.sim.enemy_position(e, alpha)
		board.last_pos[e.id] = p
		var px := view.cell_to_world(p)
		var look := LookCatalog.enemy_row(LookCatalog.enemy_look(e))
		var body: float = look["radius"]
		var dr := body - LookCatalog.ENEMY_RADIUS  # 0 for the built-in look
		var base_color: Color = look["color"]
		var color := base_color.lerp(COLOR_ENEMY_MAD, mad)
		if e.revealed:
			color = Color(REVEALED_BODY, REVEALED_ALPHA)
		var dip := fl * board.flicker_dip(e.id) if fl > 0.0 else 0.0
		color.a *= 1.0 - dip
		if dip > 0.5:  # a torn frame: a faint double a few pixels off
			var ghost := color
			# LT-40: fade the double in over dip 0.5..0.7 instead of popping in at full alpha.
			ghost.a = 0.35 * clampf((dip - 0.5) / 0.2, 0.0, 1.0)
			draw_circle(px + Vector2(view.cells_to_px(0.15), 0), view.cells_to_px(body), ghost)
		var marks := e.markers()
		if marks.has("slow"):  # ground ring under the body
			var sc := Color(WARD_COLOR, color.a)
			for i in 6:
				var st := i * TAU / 6.0
				draw_arc(px, view.cells_to_px(MARK_SLOW_CELLS + dr), st, st + TAU / 12.0, 4, sc, 2.0)
		draw_circle(px, view.cells_to_px(body), color)
		if look["ring"]:  # LT-104: a dark rim (an enemy look's `ring`)
			draw_arc(px, view.cells_to_px(body), 0, TAU, 24, Color(COLOR_ENEMY_OUTLINE, color.a), 2.0)
		if marks.has("bleed"):  # two red drops dripping below the body
			for i in 2:
				var ph := fposmod(board.time / BLEED_DROP_SECONDS + i * 0.5, 1.0)
				var dc := Color(MARK_BLEED, color.a * (1.0 - ph * 0.7))
				draw_circle(px + Vector2(view.cells_to_px(i - 0.5) * 0.22, view.cells_to_px(0.3 + dr + 0.2 * ph)),
					view.cells_to_px(0.09), dc)
		if mad > 0.0:
			draw_arc(px, view.cells_to_px(body), 0, TAU, 24, Color(COLOR_ENEMY_OUTLINE, color.a * mad), 3.0)
		if marks.has("sealed"):  # LT-51: a silver lid over the body while banish-immune
			draw_arc(px, view.cells_to_px(BANISH_LID_CELLS + dr), PI * 1.15, PI * 1.85, 10,
				Color(Board.BANISH_COLOR, 0.85 * color.a), 2.0)
		if marks.has("vuln"):  # body outline
			draw_arc(px, view.cells_to_px(body), 0, TAU, 24, Color(MARK_VULN, color.a), 2.0)
		if e.revealed:  # LT-49: amber ring outside the dashed slow mark, slash across the body
			var mc := Color(REVEALED_MARK, 1.0 - dip)
			draw_arc(px, view.cells_to_px(REVEALED_RING_CELLS + dr), 0, TAU, 24, mc, 3.0)
			var d := view.cell_to_world(Vector2(1, -1).normalized()) * REVEALED_SLASH_CELLS
			draw_line(px - d, px + d, mc, 3.0)
		if game.sim.debug_is_fake(e):
			draw_arc(px, view.cells_to_px(0.3 + dr), 0, TAU, 24, COLOR_DEBUG_FAKE, 2.0)
		var w := view.cells_to_px(0.6)
		var bar := Rect2(px + Vector2(-w * 0.5, -view.cells_to_px(0.4 + dr)), Vector2(w, 4))
		draw_rect(bar, Color(COLOR_HP_BACK, 1.0 - dip))
		bar.size.x = w * clampf(e.hp / e.max_hp, 0.0, 1.0)
		draw_rect(bar, Color(COLOR_HP, 1.0 - dip))


## LT-52 (P10): each circle's leash ring (faint), then every live ally at its interpolated
## position over the enemies: a claw line to its held enemy, the body (wing strokes when it
## flies) and its HP bar below the body.
## LT-104: the ring where the tower's look row has area "summon_ring", in that row's colour;
## a unit's colour is its tower def's SUMMON look (LookCatalog.ally_color, survives a sale).
func _draw_allies(s: SimState) -> void:
	for t in s.towers:
		var look := LookCatalog.row(Board.shot_kind(t))
		if look["area"] == "summon_ring":
			var rc: Color = look["color"]
			draw_arc(view.cell_to_world(t.centre()), view.cells_to_px(t.stats().summon_leash()), 0,
				TAU, 64, Color(rc, SUMMON_RING_ALPHA), 1.0)
	for a in s.allies:
		if not a.is_live():
			continue
		var px := view.cell_to_world(game.sim.ally_position(a, alpha))
		var ac := LookCatalog.ally_color(a.source)
		if a.held_id >= 0 and board.last_pos.has(a.held_id):
			draw_line(px, view.cell_to_world(board.last_pos[a.held_id]), Color(ac, 0.9), 2.0)
		var r := view.cells_to_px(ALLY_RADIUS_CELLS)
		if a.flying:
			for side: float in [-1.0, 1.0]:
				draw_line(px + Vector2(side * r * 0.6, 0), px + Vector2(side * r * 1.9, -r * 0.9),
					ac, 2.0)
		draw_circle(px, r, ALLY_BODY)
		draw_arc(px, r, 0, TAU, 20, ac, 2.0)
		var w := view.cells_to_px(0.5)
		var bar := Rect2(px + Vector2(-w * 0.5, r + 3.0), Vector2(w, 3))
		draw_rect(bar, COLOR_HP_BACK)
		bar.size.x = w * clampf(a.hp / a.max_hp, 0.0, 1.0) if a.max_hp > 0.0 else 0.0
		draw_rect(bar, ALLY_HP)
