class_name UiPolishTest
extends GdUnitTestSuite
## LT-28: the HUD bar groups fit a 1280x720 window (the 1200x675 base stretched, as
## canvas_items does) with no two bar items overlapping and none squashed; the sanity threshold ticks stay out
## of the label's band; the tower letter sits on a dark plate inside its tile. Draw calls are
## not observable headless, so the last two pin the geometry the drawing uses (text metrics
## from the fallback font) and, for the plate, that _draw_tower draws it under the letter.

const BASE := Vector2i(1200, 675)
const WINDOW := Vector2i(1280, 720)
const BAR_NAMES := ["GoldLabel", "RelicsLabel", "SellRelicsButton", "PhaseLabel", "HpLabel",
	"CallWaveButton", "SpeedButton", "PauseButton", "SanityBar"]
## Mirrors SanityBar._draw: the label's baseline sits at half height + 5, 14 px text.
const LABEL_BASELINE_BELOW_MIDDLE := 5.0
const LABEL_FONT_SIZE := 14
## Mirrors EntityLayer._draw_tower: the letter's origin in the tile, 16 px text, the tile inset.
const LETTER_ORIGIN := EntityLayer.GLYPH_OFFSET  ## from the cell centre (LT-108 F3)
const LETTER_FONT_SIZE := 16
const TILE_INSET := 6.0
const FRAME := 2.0  ## the tile's outline width
const INK_ALPHA := 0.05  ## an atlas pixel above this coverage counts as ink

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := ConfigLoader.load_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = GameFixture.make_viewport(self, WINDOW, BASE)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game() -> void:
	_game = GameFixture.make_game(_vp, _config, 7)
	await get_tree().process_frame


## Visible controls of the bar, gaps left out: `units` are the bar's own children (a
## two-line column is one unit: its lines overlap by design), `leaves` open the columns up.
func _bar_controls(bar: Control, leaves: bool) -> Array[Control]:
	var out: Array[Control] = []
	for c in bar.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible or ctl.name.begins_with("Gap"):
			continue
		if leaves and ctl is BoxContainer:
			for k in ctl.get_children():
				if k is Control and (k as Control).visible:
					out.append(k)
		else:
			out.append(ctl)
	return out


func _assert_bar_fits(names: Array) -> void:
	var hud := _game.hud
	var bar := hud.get_node("Bar") as Control
	var strip := Rect2(0, 0, BASE.x, _game.board.view.world_rect().position.y)
	# The bar spans the width up to the right margin.
	var end := bar.get_global_rect().end.x
	assert_float(end).is_between(BASE.x - Hud.MARGIN - 1.0, float(BASE.x))
	var screen_end := (_vp.get_final_transform() * bar.get_global_transform_with_canvas()) \
		* Vector2(bar.size.x, 0)
	assert_float(screen_end.x).is_less_equal(float(WINDOW.x))
	var ctls := _bar_controls(bar, true)
	var seen: Array[String] = []
	for c in ctls:
		seen.append(String(c.name))
		var r := c.get_global_rect()
		assert_bool(strip.encloses(r)).override_failure_message("%s %s" % [c.name, r]).is_true()
		assert_float(r.size.x).override_failure_message("%s squashed" % c.name) \
			.is_greater_equal(c.get_combined_minimum_size().x - 0.5)
	assert_array(seen).contains(names)
	ctls = _bar_controls(bar, false)
	for i in ctls.size():
		for j in range(i + 1, ctls.size()):
			var a := ctls[i].get_global_rect()
			var b := ctls[j].get_global_rect()
			assert_bool(a.intersects(b)).override_failure_message("%s %s overlaps %s %s" % [
				ctls[i].name, a, ctls[j].name, b]).is_false()


func test_hud_groups_fit_1280x720_by_day_without_overlaps() -> void:
	await _start_game()
	_game.hud.refresh()
	await get_tree().process_frame
	var bar := _game.hud.get_node("Bar") as Control
	for gap: String in ["GapLeft", "GapRight"]:
		var g := bar.get_node(gap) as Control
		assert_int(g.size_flags_horizontal & Control.SIZE_EXPAND).is_not_zero()
		assert_float(g.size.x).is_greater(0.0)
	_assert_bar_fits(BAR_NAMES)


## The widest bar: madness with the buyout button and a night luck label shown.
func test_hud_groups_fit_1280x720_with_buyout_and_luck_shown() -> void:
	_config.sanity.madness.exit_rule = "buyout"
	await _start_game()
	_game.sim.state.gold = 1000
	_game.sim._add_sanity(-_game.sim.state.sanity, "test", 0)
	_game.hud.refresh()
	_game.hud.luck_label.visible = true
	_game.hud.luck_label.text = "Luck " + Hud.luck_text(2.25)
	await get_tree().process_frame
	assert_bool(_game.hud.buyout_button.visible).is_true()
	_assert_bar_fits(BAR_NAMES + ["BuyoutButton", "LuckLabel"])


## The ink of `text` at `font_size` relative to its drawing origin: the covered pixels of
## each shaped glyph in the font's atlas (CPU-side, so it works headless).
func _ink(text: String, font_size: int) -> Rect2:
	var ts := TextServerManager.get_primary_interface()
	var line := TextLine.new()
	line.add_string(text, ThemeDB.fallback_font, font_size)
	var out := Rect2()
	var first := true
	var x := 0.0
	for g: Dictionary in ts.shaped_text_get_glyphs(line.get_rid()):
		var rid: RID = g["font_rid"]
		var key := Vector2i(g["font_size"], 0)
		var idx: int = g["index"]
		var size: Vector2 = ts.font_get_glyph_size(rid, key, idx)
		if size.x > 0.0 and size.y > 0.0:
			var off: Vector2 = ts.font_get_glyph_offset(rid, key, idx)
			var uv: Rect2 = ts.font_get_glyph_uv_rect(rid, key, idx)
			var img: Image = ts.font_get_texture_image(rid, key, ts.font_get_glyph_texture_idx(rid, key, idx))
			var lo := Vector2i(1 << 20, 1 << 20)
			var hi := Vector2i(-1, -1)
			for py in int(uv.size.y):
				for px in int(uv.size.x):
					if img.get_pixel(int(uv.position.x) + px, int(uv.position.y) + py).a > INK_ALPHA:
						lo = lo.min(Vector2i(px, py))
						hi = hi.max(Vector2i(px + 1, py + 1))
			if hi.x >= 0:
				var origin := Vector2(x, 0) + (g["offset"] as Vector2) + off
				var r := Rect2(origin + Vector2(lo), Vector2(hi - lo))
				out = r if first else out.merge(r)
				first = false
		x += g["advance"]
	return out


## The ticks end before the label's ink starts and start where it ends (descenders and
## the "n / cap" form included).
func test_sanity_ticks_stay_out_of_the_label_band() -> void:
	await _start_game()
	var bar := _game.hud.sanity_bar
	assert_float(bar.size.y).is_equal(SanityBar.SIZE.y)
	assert_int(bar.mark_ratios().size()).is_greater(0)
	assert_float(SanityBar.MARK_TICK).is_greater(0.0)
	var baseline := SanityBar.SIZE.y * 0.5 + LABEL_BASELINE_BELOW_MIDDLE
	var max_s := _config.sanity.max_sanity
	for v in [max_s, 55.0, 20.0, 0.0, -1.0]:
		if v < 0.0:
			_game.sim.state.sanity_cap = max_s * 0.7  # the "Sanity n / cap" form
		else:
			_game.sim._add_sanity(v - _game.sim.state.sanity, "test", 0)
		var text := bar.label_text()
		var ink := _ink(text, LABEL_FONT_SIZE)
		ink.position.y += baseline
		assert_float(SanityBar.MARK_TICK).override_failure_message(
			"%s: top tick to %s, ink from %s" % [text, SanityBar.MARK_TICK, ink.position.y]) \
			.is_less_equal(ink.position.y)
		assert_float(SanityBar.SIZE.y - SanityBar.MARK_TICK).override_failure_message(
			"%s: bottom tick from %s, ink to %s" % [text, SanityBar.SIZE.y - SanityBar.MARK_TICK,
			ink.end.y]).is_greater_equal(ink.end.y)
	assert_str(bar.label_text()).contains(" / ")


func test_the_tower_letter_sits_on_a_dark_plate_inside_its_tile() -> void:
	var tile := BoardView.new().cells_to_px(1.0) - 2.0 * TILE_INSET
	# the plate's inside, from the cell centre (LT-108 F3: marks anchor to the centre)
	var inside := Rect2(Vector2(-tile, -tile) * 0.5 + Vector2(FRAME, FRAME),
		Vector2(tile, tile) - Vector2(2, 2) * FRAME)
	assert_bool(inside.encloses(EntityLayer.LETTER_PLATE)) \
		.override_failure_message("plate %s, tile inside %s" % [EntityLayer.LETTER_PLATE, inside]) \
		.is_true()
	for id: String in _config.towers:
		var letter: String = (_config.towers[id] as TowerDef).name.left(1)
		var ink := _ink(letter, LETTER_FONT_SIZE)
		ink.position += LETTER_ORIGIN
		assert_bool(EntityLayer.LETTER_PLATE.encloses(ink)).override_failure_message(
			"%s ink %s, plate %s" % [letter, ink, EntityLayer.LETTER_PLATE]).is_true()
	assert_float(EntityLayer.COLOR_LETTER_PLATE.get_luminance()).is_less(0.2)
	assert_float(EntityLayer.COLOR_LETTER_PLATE.get_luminance()) \
		.is_less(EntityLayer.COLOR_TOWER.get_luminance() - 0.4)
	assert_float(EntityLayer.COLOR_LETTER_PLATE.a).is_equal(1.0)
	# _draw_tower draws the plate after the tile and before the letter.
	var src := FileAccess.get_file_as_string("res://scenes/board/entity_layer.gd")
	var start := src.find("func _draw_tower(")
	assert_int(start).is_greater(-1)
	var body := src.substr(start, src.find("\nfunc ", start + 1) - start)
	var tile_at := body.find("fill_cell(self, t.cell, plate_color(")  # LT-70 §5: the tinted plate
	# the plate rect is the "plate" anchor and the letter sits at "glyph" (both pinned by
	# test_tower_anchors_are_the_pre_lt108_square_offsets_from_the_cell_centre)
	var plate_at := RegEx.create_from_string(
		"(?m)^\\s*draw_rect\\(\\s*at\\[\"plate\"\\]\\s*,\\s*COLOR_LETTER_PLATE\\s*\\)") \
		.search(body)
	var letter_at := body.find("draw_string(ThemeDB.fallback_font, at[\"glyph\"], t.def.glyph,")
	assert_int(tile_at).is_greater(-1)
	assert_int(letter_at).override_failure_message("no letter draw_string at at[\"glyph\"]") \
		.is_greater(-1)
	assert_object(plate_at).override_failure_message(
		"no draw_rect(at[\"plate\"], COLOR_LETTER_PLATE) in _draw_tower").is_not_null()
	if plate_at != null:
		assert_int(plate_at.get_start()).is_between(tile_at, letter_at)


## LT-108 §6 item 7: tower_anchors(centre) puts each mark where _draw_tower put it before
## LT-108, from the square tile inset by 6 (r = cell_rect(c).grow(-6), a 28 px plate).
func test_tower_anchors_are_the_pre_lt108_square_offsets_from_the_cell_centre() -> void:
	var view := BoardView.new()
	view.grid = SquareGrid.new(7, 5)
	for c: Vector2i in [Vector2i(0, 0), Vector2i(3, 2), Vector2i(6, 4)]:
		var tile := BoardView.CELL
		var r := Rect2(Vector2(c) * tile, Vector2(tile, tile)).grow(-TILE_INSET)
		var at := EntityLayer.tower_anchors(view.cell_centre(c))
		assert_array(at.keys()).contains_exactly_in_any_order(
			["plate", "glyph", "mark", "pip", "branch"])
		assert_object(at["plate"]).override_failure_message(str(c)) \
			.is_equal(Rect2(r.position + Vector2(4, 4), Vector2(15, 19)))
		assert_object(at["glyph"]).override_failure_message(str(c)) \
			.is_equal(r.position + Vector2(8, 20))
		assert_object(at["mark"]).override_failure_message(str(c)) \
			.is_equal(r.position + Vector2(r.size.x - 6, 6))
		assert_object(at["pip"]).override_failure_message(str(c)) \
			.is_equal(r.position + Vector2(3, r.size.y - 6))
		assert_object(at["branch"]).override_failure_message(str(c)) \
			.is_equal(r.position + Vector2(r.size.x - 9, 11))
	assert_float(EntityLayer.PIP_STEP).is_equal(6.0)  # pip i at 3 + 6 * i
	assert_float(EntityLayer.PLATE_INSET).is_equal(TILE_INSET)
