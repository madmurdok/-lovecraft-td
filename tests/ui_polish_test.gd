class_name UiPolishTest
extends GdUnitTestSuite
## LT-28: the HUD bar groups fit a 1280x720 window (the 1152x648 base stretched, as
## canvas_items does) with no two bar items overlapping and none squashed; the sanity threshold ticks stay out
## of the label's band; the tower letter sits on a dark plate inside its tile. Draw calls are
## not observable headless, so the last two pin the geometry the drawing uses (text metrics
## from the fallback font) and, for the plate, that _draw_tower draws it under the letter.

const BASE := Vector2i(1152, 648)
const WINDOW := Vector2i(1280, 720)
const BAR_NAMES := ["GoldLabel", "RelicsLabel", "SellRelicsButton", "PhaseLabel", "HpLabel",
	"CallWaveButton", "SpeedButton", "PauseButton", "SanityBar"]
## Mirrors SanityBar._draw: the label's baseline sits at half height + 5, 14 px text.
const LABEL_BASELINE_BELOW_MIDDLE := 5.0
const LABEL_FONT_SIZE := 14
## Mirrors Board._draw_tower: the letter's origin in the tile, 16 px text, the tile inset.
const LETTER_ORIGIN := Vector2(8, 20)
const LETTER_FONT_SIZE := 16
const TILE_INSET := 6.0
const FRAME := 2.0  ## the tile's outline width
const INK_ALPHA := 0.05  ## an atlas pixel above this coverage counts as ink

var _vp: SubViewport
var _game: Game
var _config: GameConfig


func before_test() -> void:
	var r := GameConfig.load_from_dir("res://data")
	assert_bool(r.ok).override_failure_message("\n".join(r.errors)).is_true()
	_config = r.config
	_vp = SubViewport.new()
	_vp.size = WINDOW
	_vp.size_2d_override = BASE
	_vp.size_2d_override_stretch = true
	add_child(_vp)


func after_test() -> void:
	if is_instance_valid(_vp):
		_vp.queue_free()
	_vp = null
	_game = null


func _start_game() -> void:
	_game = Game.new()
	_game.setup(_config, 7)
	_vp.add_child(_game)
	_game.set_process(false)
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
	var strip := Rect2(0, 0, BASE.x, Game.BOARD_ORIGIN.y)
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
	var tile := Board.CELL - 2.0 * TILE_INSET
	var inside := Rect2(Vector2(FRAME, FRAME), Vector2(tile, tile) - Vector2(2, 2) * FRAME)
	assert_bool(inside.encloses(Board.LETTER_PLATE)) \
		.override_failure_message("plate %s, tile inside %s" % [Board.LETTER_PLATE, inside]) \
		.is_true()
	for id: String in _config.towers:
		var letter: String = (_config.towers[id] as TowerDef).name.left(1)
		var ink := _ink(letter, LETTER_FONT_SIZE)
		ink.position += LETTER_ORIGIN
		assert_bool(Board.LETTER_PLATE.encloses(ink)).override_failure_message(
			"%s ink %s, plate %s" % [letter, ink, Board.LETTER_PLATE]).is_true()
	assert_float(Board.COLOR_LETTER_PLATE.get_luminance()).is_less(0.2)
	assert_float(Board.COLOR_LETTER_PLATE.get_luminance()) \
		.is_less(Board.COLOR_TOWER.get_luminance() - 0.4)
	assert_float(Board.COLOR_LETTER_PLATE.a).is_equal(1.0)
	# _draw_tower draws the plate after the tile and before the letter.
	var src := FileAccess.get_file_as_string("res://scenes/board.gd")
	var start := src.find("func _draw_tower(")
	assert_int(start).is_greater(-1)
	var body := src.substr(start, src.find("\nfunc ", start + 1) - start)
	var tile_at := body.find("draw_rect(r, COLOR_TOWER)")
	var plate_at := RegEx.create_from_string(
		"(?m)^\\s*draw_rect\\([^\\n]*LETTER_PLATE[^\\n]*COLOR_LETTER_PLATE\\)").search(body)
	var letter_at := body.find("draw_string(")
	assert_int(tile_at).is_greater(-1)
	assert_object(plate_at).override_failure_message("no plate draw_rect in _draw_tower") \
		.is_not_null()
	if plate_at != null:
		assert_int(plate_at.get_start()).is_between(tile_at, letter_at)
