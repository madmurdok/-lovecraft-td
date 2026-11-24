class_name BoardLayer
extends Node2D
## LT-84 (LT-65 §3.4): base of the board's drawing layers (PhantomLayer, EntityLayer,
## FxLayer, OverlayLayer). Each is a child Node2D of the Board with its own _draw, under the
## same CanvasModulate and light mask as the board. Board adds them in draw order and
## queues all of them on every board redraw. Shared render state stays on the Board:
## `game`, `alpha` (clock interpolation), `time` (effects seconds), `last_pos` (enemy
## positions EntityLayer drew) and the flicker helpers.

var board: Board
var view: BoardView  ## the board's view, set by Board when it adds the layer
var game: Game:
	get:
		return board.game if board != null else null
var alpha: float:  ## render interpolation between the last two ticks
	get:
		return board.alpha


## True when there is a sim to draw (the board's own _draw has the same guard). LT-85: the
## layers read its snapshot, built in Game.setup.
func has_sim() -> bool:
	return game != null and game.sim != null and game.snapshot != null
