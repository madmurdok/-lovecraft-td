class_name GameFixture
extends RefCounted
## LT-74 (LT-65 B1, guard G8): the one place tests build a Game and its SubViewport. The
## headless root is 64x64 and drops GUI clicks, so scene/UI suites run the Game inside an
## owned SubViewport. Suites keep their own seed, config dir, viewport size and teardown.

const DEFAULT_SEED := 7
const DEFAULT_SIZE := Vector2i(1200, 675)


## A SubViewport of `size` added under `parent`. `override_2d` (non-zero) also sets
## size_2d_override with stretch, the way the window-scale suites run.
static func make_viewport(
	parent: Node, size: Vector2i = DEFAULT_SIZE, override_2d: Vector2i = Vector2i.ZERO
) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	if override_2d != Vector2i.ZERO:
		vp.size_2d_override = override_2d
		vp.size_2d_override_stretch = true
	parent.add_child(vp)
	return vp


## Game.new().setup(config, seed). With a viewport the Game is added to it with its own
## _process switched off (tests drive it through advance()); with null it is returned
## unparented, for the caller to configure and add. The caller awaits a frame.
static func make_game(vp: SubViewport, config: GameConfig, seed: int = DEFAULT_SEED) -> Game:
	var game := Game.new()
	game.setup(config, seed)
	if vp != null:
		vp.add_child(game)
		game.set_process(false)
	return game


## Config load + viewport + Game in one call, for suites with no inline config handling.
## Returns the Game; its viewport is `game.get_parent()`. Null when the config does not load.
static func make(
	parent: Node,
	seed: int = DEFAULT_SEED,
	data: String = "res://data",
	size: Vector2i = DEFAULT_SIZE
) -> Game:
	var r := GameConfig.load_from_dir(data)
	if not r.ok:
		push_error("GameFixture: config load failed: " + "\n".join(r.errors))
		return null
	return make_game(make_viewport(parent, size), r.config, seed)
