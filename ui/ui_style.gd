class_name UiStyle
extends RefCounted
## LT-28: the shared look of HUD and side panel buttons. Every state has an opaque,
## framed box, and a disabled button keeps an opaque (dimmed, not see-through) text, so
## buttons read as buttons on the dark bars and a disabled picker entry stays legible.
## Presentation only.

const COLOR_BG := Color(0.08, 0.08, 0.1)  ## HUD bar, footer and side panel background
const COLOR_BUTTON := Color(0.16, 0.16, 0.2)
const COLOR_BUTTON_HOVER := Color(0.23, 0.23, 0.29)
const COLOR_BUTTON_PRESSED := Color(0.11, 0.11, 0.14)
const COLOR_BUTTON_DISABLED := Color(0.12, 0.12, 0.14)
const COLOR_BORDER := Color(0.38, 0.38, 0.46)
const COLOR_BORDER_DISABLED := Color(0.24, 0.24, 0.28)
const COLOR_TEXT := Color(0.93, 0.93, 0.95)
const COLOR_TEXT_DISABLED := Color(0.6, 0.6, 0.64)  ## opaque: the default is 50 % alpha
const PAD_X := 6
const PAD_Y := 3


## A theme with `font_size` and the button boxes and colours above.
static func theme(font_size: int) -> Theme:
	var t := Theme.new()
	t.default_font_size = font_size
	t.set_stylebox("normal", "Button", _box(COLOR_BUTTON, COLOR_BORDER))
	t.set_stylebox("hover", "Button", _box(COLOR_BUTTON_HOVER, COLOR_BORDER))
	t.set_stylebox("pressed", "Button", _box(COLOR_BUTTON_PRESSED, COLOR_BORDER))
	t.set_stylebox("hover_pressed", "Button", _box(COLOR_BUTTON_PRESSED, COLOR_BORDER))
	t.set_stylebox("disabled", "Button", _box(COLOR_BUTTON_DISABLED, COLOR_BORDER_DISABLED))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c: String in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", COLOR_TEXT)
	t.set_color("font_disabled_color", "Button", COLOR_TEXT_DISABLED)
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(1)
	b.set_corner_radius_all(3)
	b.content_margin_left = PAD_X
	b.content_margin_right = PAD_X
	b.content_margin_top = PAD_Y
	b.content_margin_bottom = PAD_Y
	return b
