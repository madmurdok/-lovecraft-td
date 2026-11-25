class_name BoardCamera
extends RefCounted
## LT-66 §6.2-§6.3: turns input into the board's pan (BoardView.pan). Owned by Board, which
## forwards non-left mouse events, pan gestures and keys, and calls tick() once per frame.
## Every pan goes through BoardView.clamp_pan for the visible rect V (play_rect minus the
## overlay while it shows, set by SidePanel.sync_visible). No zoom (§6.4).
## Inputs: arrows / WASD held (KEY_SPEED), right or middle drag (1:1), wheel (vertical) and
## Shift+wheel or wheel left/right (horizontal) one cell per notch, trackpad pan gesture, and
## edge pan: 16 px strips along the inside edges of V, after a dwell. A left click never pans.
## Ease (§6.3): when V changes the clamped target is reached over EASE_SECONDS, driven only by
## tick's delta (no Tween, no wall clock); any user pan cancels it.

const KEY_SPEED := 640.0  ## px/s while an arrow or WASD key is held
const EDGE_SPEED := 480.0  ## px/s while the cursor dwells in an edge strip
const EDGE_PX := 16.0  ## edge strip width inside V
const EDGE_DWELL := 0.3  ## seconds in a strip before it pans (crossing it does not)
const EASE_SECONDS := 0.25  ## owner Q5
const WHEEL_CELLS := 1.0  ## one wheel notch pans one cell
const REVEAL_CELLS := 0.5  ## auto-reveal brings this far around the point into V

## Held key -> the direction the view looks (Right = see more to the right).
const KEY_DIRS := {
	KEY_LEFT: Vector2.LEFT, KEY_A: Vector2.LEFT,
	KEY_RIGHT: Vector2.RIGHT, KEY_D: Vector2.RIGHT,
	KEY_UP: Vector2.UP, KEY_W: Vector2.UP,
	KEY_DOWN: Vector2.DOWN, KEY_S: Vector2.DOWN,
}

var view: BoardView
var visible_rect: Rect2  ## V: where the map is seen (screen, base units)
var _held: Dictionary[int, bool] = {}  ## keycodes of held pan keys
var _edge_dir := Vector2.ZERO  ## the strip the cursor is in (look direction), ZERO if none
var _edge_t := 0.0  ## seconds the cursor has been in that strip
var _easing := false
var _ease_from := Vector2.ZERO
var _ease_to := Vector2.ZERO
var _ease_t := 0.0  ## 0..1 progress of the ease


func _init(p_view: BoardView) -> void:
	view = p_view
	visible_rect = BoardView.play_rect()


## True while an ease (§6.3) is running.
func easing() -> bool:
	return _easing


## Sets V. When the clamped pan for the new V differs from the pan, eases to it.
func set_visible_rect(v: Rect2) -> void:
	if v == visible_rect:
		return
	visible_rect = v
	var from := view.pan
	var target := view.clamp_pan(from, v)
	if target == from:
		_easing = false
		return
	_easing = true
	_ease_from = from
	_ease_to = target
	_ease_t = 0.0


## A user pan by `d` (screen px): cancels any ease and applies the clamp at once.
func pan_by(d: Vector2) -> void:
	_easing = false
	view.set_pan(view.clamp_pan(view.pan + d, visible_rect))


## Mouse and gesture input (in the board's screen frame, base units). Returns true when it
## panned or took the event (right/middle press and release, drag, wheel, gesture).
func input(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				return true  # drag is read from the motion's button mask
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, \
					MOUSE_BUTTON_WHEEL_RIGHT:
				if mb.pressed:
					pan_by(_wheel_look(mb) * -view.cells_to_px(WHEEL_CELLS) * _notches(mb))
				return true
		return false
	var mm := event as InputEventMouseMotion
	if mm != null:
		if mm.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			pan_by(mm.relative)  # 1:1 with the mouse
			return true
		return false
	var pg := event as InputEventPanGesture
	if pg != null:
		pan_by(-pg.delta * view.cells_to_px(WHEEL_CELLS))
		return true
	return false


## The look direction of a wheel notch: vertical wheel, Shift turns it horizontal.
static func _wheel_look(mb: InputEventMouseButton) -> Vector2:
	var d := Vector2.ZERO
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			d = Vector2.UP
		MOUSE_BUTTON_WHEEL_DOWN:
			d = Vector2.DOWN
		MOUSE_BUTTON_WHEEL_LEFT:
			d = Vector2.LEFT
		MOUSE_BUTTON_WHEEL_RIGHT:
			d = Vector2.RIGHT
	if mb.shift_pressed and d.x == 0.0:
		d = Vector2(d.y, 0.0)  # up -> left, down -> right
	return d


## Notches in one wheel event (a smooth wheel or trackpad reports fractions; 0 means one).
static func _notches(mb: InputEventMouseButton) -> float:
	return mb.factor if mb.factor > 0.0 else 1.0


## Arrow / WASD press and release. Returns true when the key is a pan key.
func key_input(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not KEY_DIRS.has(k.keycode):
		return false
	if k.pressed:
		_held[k.keycode] = true
	else:
		_held.erase(k.keycode)
	return true


## Forgets held keys and the edge dwell (the window lost focus or the mouse left it).
func release_all() -> void:
	_held.clear()
	_edge_dir = Vector2.ZERO
	_edge_t = 0.0


## One frame: held keys and edge pan, then the ease. `mouse_pos` is the cursor in base
## units; `edge_ok` is false while the cursor is over a Control, outside the window, the
## window is unfocused or a mouse button is held (Board decides).
func tick(delta: float, mouse_pos: Vector2, edge_ok := true) -> void:
	var look := Vector2.ZERO
	for code: int in _held:
		look += KEY_DIRS[code]
	var d := -look * KEY_SPEED * delta
	var edge := edge_look(mouse_pos) if edge_ok else Vector2.ZERO
	if edge != _edge_dir:
		_edge_dir = edge
		_edge_t = 0.0
	if edge != Vector2.ZERO:
		var before := _edge_t
		_edge_t += delta
		var moving := _edge_t - maxf(before, EDGE_DWELL)  # only the time past the dwell
		if moving > 0.0:
			d -= edge * EDGE_SPEED * moving
	if d != Vector2.ZERO:
		var target := view.clamp_pan(view.pan + d, visible_rect)
		if target != view.pan or not _easing:
			pan_by(d)  # a pan that moves (or no ease to keep) cancels the ease
	if _easing:
		_ease_t = minf(_ease_t + delta / EASE_SECONDS, 1.0)
		if _ease_t >= 1.0:
			_easing = false
			view.set_pan(_ease_to)
		else:
			view.set_pan(_ease_from.lerp(_ease_to, smoothstep(0.0, 1.0, _ease_t)))


## The look direction of the edge strip under `p` (16 px inside V's edges), ZERO when the
## cursor is outside V or in no strip. Corners give both axes.
func edge_look(p: Vector2) -> Vector2:
	var v := visible_rect
	if not v.has_point(p):
		return Vector2.ZERO
	var d := Vector2.ZERO
	if p.x < v.position.x + EDGE_PX:
		d.x = -1.0
	elif p.x >= v.end.x - EDGE_PX:
		d.x = 1.0
	if p.y < v.position.y + EDGE_PX:
		d.y = -1.0
	elif p.y >= v.end.y - EDGE_PX:
		d.y = 1.0
	return d


## LT-66 §6.1 auto-reveal: pans by the least amount that brings the point `p_cells` (with
## REVEAL_CELLS around it) inside V, at once. Does nothing when it is already inside.
func reveal(p_cells: Vector2) -> void:
	var c := view.cell_to_screen(p_cells)
	var r := view.cells_to_px(REVEAL_CELLS)
	var v := visible_rect
	var d := Vector2.ZERO
	for axis in 2:
		var lo := c[axis] - r
		var hi := c[axis] + r
		if lo < v.position[axis]:
			d[axis] = v.position[axis] - lo
		elif hi > v.end[axis]:
			d[axis] = v.end[axis] - hi
	if d != Vector2.ZERO:
		pan_by(d)
