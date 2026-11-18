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
## `args` are the launch user args Game.setup reads (LT-87); suites pass their own flags.
static func make_game(
	vp: SubViewport,
	config: GameConfig,
	seed: int = DEFAULT_SEED,
	args: PackedStringArray = OS.get_cmdline_user_args()
) -> Game:
	var game := Game.new()
	game.setup(config, seed, args)
	if vp != null:
		vp.add_child(game)
		game.set_process(false)
	return game

