class_name DebugArgs
extends RefCounted
## LT-78: the launch user args (after a bare `--`) that Game reads, parsed once. Debug flags
## are honoured in debug builds only, except `--mute` (any build).

const REVEAL_FAKES_ARG := "--reveal-fakes"  ## `-- --reveal-fakes` (debug builds only)
## `-- --sanity=<v>` or `-- --sanity <v>` (debug builds only, LT-14, LT-21): sets sanity at
## the start of the run through the sim's own sanity path, so SANITY_CHANGED /
## SANITY_STATE_CHANGED fire as usual. User args must follow a bare `--`.
const SANITY_ARG := "--sanity"
## `-- --frame-stats` (debug builds only, LT-38 P1): shows the wall-clock frame time
## (median / p90 over the last FrameStats.CAPACITY frames) in the HUD.
const FRAME_STATS_ARG := "--frame-stats"
## `-- --sandbox` (debug builds only, LT-67): a playtest run for late-game features. The run
## starts with SANDBOX_GOLD money and a full oil stock (oil.start = oil.cap; the cap stays),
## set in a copy of the config before the sim is built (GameConfig.sandboxed), so the sim stays
## deterministic. Game.SKIP_KEY skips ahead: by day it lights the lamp (sim call_wave), at night
## it ends the night (sim debug_end_night, logged). The HUD shows a "SANDBOX" marker.
const SANDBOX_ARG := "--sandbox"
## `-- --mute` (any build, LT-87): mutes the Master bus for the run, so game windows that
## agents open for screenshots and frame-time measures stay silent. Without it the run
## leaves the bus as it is (unmuted by default).
const MUTE_ARG := "--mute"
const SANDBOX_GOLD := 100000  ## enough to build and fully upgrade every tower and the lighthouse

var sandbox := false
var reveal_fakes := false
var frame_stats := false
var mute := false
var sanity := -1.0  ## forced start sanity, -1 when absent


static func parse(args: PackedStringArray, debug_build := OS.is_debug_build()) -> DebugArgs:
	var d := DebugArgs.new()
	d.sandbox = debug_build and args.has(SANDBOX_ARG)
	d.reveal_fakes = debug_build and args.has(REVEAL_FAKES_ARG)
	d.frame_stats = debug_build and args.has(FRAME_STATS_ARG)
	d.mute = args.has(MUTE_ARG)
	d.sanity = sanity_value(args) if debug_build else -1.0
	return d


## Mutes the Master bus when `args` has MUTE_ARG; returns whether it did. Never unmutes.
static func apply_mute(args: PackedStringArray) -> bool:
	if not args.has(MUTE_ARG):
		return false
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	return true


## The `--sanity=<v>` / `--sanity <v>` value clamped to >= 0, or -1 when absent or not a
## number.
static func sanity_value(args: PackedStringArray) -> float:
	for i in args.size():
		var v := ""
		if args[i].begins_with(SANITY_ARG + "="):
			v = args[i].trim_prefix(SANITY_ARG + "=")
		elif args[i] == SANITY_ARG and i + 1 < args.size():
			v = args[i + 1]
		else:
			continue
		return maxf(v.to_float(), 0.0) if v.is_valid_float() else -1.0
	return -1.0
