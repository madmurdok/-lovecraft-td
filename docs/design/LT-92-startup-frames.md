# LT-92: the two heavy frames before the first wave (diagnosis, slice S1)

Status: diagnosis only. No production code changed. One throwaway probe (`probe92.gd` in the
worktree root, source in the appendix) was removed at the end of the slice.

Build: branch `fix/LT-92-startup-frames` at 0c6f17b (0.13.0), Godot 4.7.2, GL Compatibility,
"OpenGL API 4.1 INTEL-24.5.8, Intel Iris Plus Graphics" (MacBookPro16,2, 8 threads), Retina
scale 2.0, boot-fit window 2402x1352 px, `--audio-driver Dummy`, `-- --seed=4242 --frame-stats
--mute`. Every window was launched with `--mute`.

## Owner decisions (2026-11-25)

- Frame A: "Кадр «Загрузка…» уже сейчас" — show a loading frame now, not only once a menu exists (A2 brought forward).
- Frame B: "Прогреть свет во время кадра A (Recommended)" — B1.
- Frame C: "Расширить LT-92 на кадр C" — frame C is diagnosed and fixed within LT-92.

## Verdict

LT-90 named the two frames "window creation" and "window coming to the front". Neither is right.
Both frames are **first-use GL shader compilation in the draw step**. The window costs almost
nothing in either one.

| frame | when (LT-62 spike log) | cause | fast runs | slow runs / LT-90 load 20-40 |
|---|---|---|---|---|
| A | first frame, sim tick 4 | the first draw of the game scene: the GL driver compiles the canvas shader variants (and the sea-fog shader) that the board, entities and UI use | 287-339 ms, 96-99% in `draw` | 513-978 ms (LT-90: 0.66-1.15 s) |
| B | the first frame of the first night, sim tick 15-16 in LT-90 | `call_wave` starts the night fade, so the lighthouse glow and beam `PointLight2D`s turn visible for the first time. The driver then compiles the lit variants of every canvas shader that draws under them | 424-473 ms, 96-97% in `draw` | 946-1425 ms (LT-90: 1.2-2.2 s) |

1. **Frame A is load time.** It cannot be removed on this machine, only moved. macOS OpenGL
   offers no program-binary formats. Godot's GL shader cache folder
   (`user://shader_cache/CanvasShaderGLES3/...`) exists but holds 0 files after hundreds of
   runs. So every launch compiles again.
2. **Frame B can be avoided. It is not load time.** In the probe it showed up 0.5 s into the run
   only because the LT-90 bot called the first wave then. In real play it lands on the player's
   first "light the lamp / call wave". That is a 0.4-1.4 s freeze as the first enemy spawns.
   Lighting the lamps for the first frames moved the whole cost into frame A and left the
   wave-call frame clean in 3/3 runs (see `botwarm`).
3. **The window is not the cause of either frame.** The engine creates the window before the
   first frame: `_initialize` runs at 1.45-1.6 s from process start, against 1.09 s headless.
   An empty window's first frame takes 4-11 ms (`nomain`), and a Label-only one 44-73 ms
   (`label`). Calling `window_move_to_foreground` adds no frame (`fg` matches `base`). The
   boot-fit resize changes nothing either (`nofit` matches `base`). The window takes focus
   right after frame A is presented (`focus_in` 2.08-2.43 s in fast runs), which is why LT-90
   linked the two.
4. **A third frame turned up, outside this task:** 138-537 ms, all in `draw`, about 1 s after
   the wave call (night 0.81-0.83, one enemy on the board). It appears in every run that calls
   a wave, including `botwarm`, so the light warm-up does not cover it. Suggested follow-up
   task: "first-night third frame (~150 ms) ~1 s after the first wave call".

## How it was measured

- Probe `probe92.gd` is a SceneTree script (appendix). It loads `main.tscn` as LT-90's probe
  did. For every frame it prints one `F` line with the interval and a split, using the LT-90
  method: `proc` (probe `_process` -> a tail node with priority 100000), `gap` (tail ->
  `frame_pre_draw`, mainly `_draw` callbacks), `draw` (`frame_pre_draw` -> `frame_post_draw`,
  including swap), `wait` (post draw -> next physics/process, i.e. OS events and pacing). The
  line also carries draw calls, focus, window size, `lighting.night`, enemies, towers and the
  sim events consumed. The game's own `--frame-stats` spike log (`scenes/frame_stats.gd`,
  `Game.advance`) runs as well.
- Arms (user args after `--`, nothing in the game changed):

| arm | what differs | cheap observation that tells it apart (control) |
|---|---|---|
| plain | no probe, `--quit-after 360`, game spike log only | no `F` lines, spike log only |
| base | probe, no input | - |
| fg | `window_move_to_foreground()` at 0.5 s | `fg_call@` event in the log |
| bot | LT-90 bot: at 0.5 s of summed delta, build 3 towers, call wave | `bot3` event, `tw=3`, `night>0` afterwards |
| fgbot | bot + fg (the LT-90 conditions) | both events |
| build | bot builds, no wave | `tw=3`, `night` stays 0.000 |
| wave | wave called, nothing built | `tw=0`, `night>0` |
| botwarm | bot + `lighting.night = 0.01` for the first 3 frames (lights drawn at ~0 energy) | `warm` events, F1 `night=0.010` |
| nomain | no main scene, empty window | `draws=0` |
| label | `--config-dir=/nonexistent_lt92`: main refuses, draws only its error Label | `draws=1`, config error in log |
| menu | a Label "menu" for 1.5 s, then `main.tscn` (a stand-in for a future menu) | `menu_to_game` event, F1 `draws=1` |
| noui | UI CanvasLayer hidden | (frame A unchanged, see results) |
| nofx | Lighting and SanityFx hidden | (frame A unchanged) |
| nofit | engine `--resolution 1600x900` turns the boot fit off | `win=1600x900` instead of 2402x1352 |
| headless | `--headless` + bot | `ds=headless`, no draw |
| bot_L | bot with 16 `yes` CPU burners running | load rises 7-10 -> 12-13 |

- One background script ran 3 rounds, round robin over all 16 arms (48 runs, 6 s each). Each
  run waited for a 1-min load < 10 (180 s cap). Scratchpad: `lt92/run.sh`, `summarize.py`,
  `summary.txt`, and one log per run.
- Machine state: `uptime` load 3.4-7.1 before the batch. Per-run 1-min load before/after was
  4.1-10.0 / 4.1-18.2 (39.7 after one headless run). `/usr/bin/time -p` real/user/sys
  8.0-19.2 / 1.9-8.5 / 0.4-2.6 s. user + sys is about 0.7 of real in the game runs, so the
  process was busy, not waiting. The runs fall into two speed classes. In "fast" runs
  `_initialize` comes at 1.45-1.66 s after process start. In "slow" runs it comes at
  2.5-12.2 s, and every frame in them is about 2x longer, so contention came from outside
  (other agents, thermal). Compare frames within a class.

## Evidence

### Frame A: first draw of the game scene (fast runs, `F1` = the first frame interval)

| arm | F1 ms (draw / proc / wait) | draw calls |
|---|---|---|
| plain (game spike log, tick 4) | 320, 304 (406 in a slower run) | - |
| base | 312 (288/0.4/23), 328 (319/0.5/8) | 1881 |
| fg | 308 (282/0.4/25), 307 (299/0.6/6) | 1881 |
| build | 313 (287), 328 (320) | 1881 |
| bot / fgbot | 322 (297), 326 (299), 311 (284) | 1881 |
| noui | 313 (289), 303 (277), 316 (273) | 1881 |
| nofx | 302 (277), 339 (331), 287 (286) | 1881 |
| nofit (1600x900 window) | 311 (307) | 1881 |
| label (error Label only) | 73 (30), 63 (38), 44 (44) | 1 |
| nomain (empty window) | 11 (11), 6 (5), 8 (7) | 0 |
| menu: first frame of the "menu" | 32 (31), 39 (38), 38 (37) | 1 |
| menu: the menu -> game frame | 467 (draw 238, proc 223), 488 (246/237), 491 (258/228) | 1905 |
| headless + bot | 0.7-2.7 (no draw) | 0 |

- The time is spent in `draw`: 288-331 ms of a 302-339 ms frame. Scripts take < 1 ms. Main
  scene setup (config load, `Game._ready`, UI build) runs before the first frame: `first_proc`
  is 254-325 ms after `_initialize` in fast runs, against 27-48 ms for `nomain`. That time does
  not count as a frame interval in the spike log.
- Hiding the UI layer or Lighting/SanityFx (fog shader, lights) leaves frame A where it is. The
  cost belongs to the board and entity canvas items as a group, not to one node. No single node
  can be cut to remove it.
- A window that draws (almost) nothing has a 4-73 ms first frame. So the window and its first
  present are not frame A.
- In `menu`, the menu's own first frame costs 32-39 ms. The cost moves to the menu -> game frame
  (467-491 ms): 223-237 ms of scene load (`proc`, the `main.tscn` instance plus `_ready`, done
  in the probe's `_process`) plus 238-258 ms of first draw. That frame also runs the boot fit,
  since main does it.

### Frame B: the first night (the frame right after the trigger)

| arm | frame after trigger, ms (draw) | night in that frame | verdict |
|---|---|---|---|
| bot (fast) | 473 (453) | 0.034 | frame B |
| fgbot (fast) | 447 (436), 424 (414) | 0.036 | frame B |
| bot / fgbot / wave (slow) | 1109, 1113, 1294, 946, 1425, 1395 (all 93-99% draw) | 0.04-0.16 | frame B |
| bot_L (16 burners) | 1008, 1306, 967 | 0.04-0.08 | frame B, scales with load |
| build (3 towers, no wave) | 23 (13), 57 (33), 25 (14) | 0.000 | **no frame**: building is not the cause |
| wave (no towers) | 946, 1425, 1395 (slow class) | 0.05-0.16 | frame B: towers are not needed |
| fg (foreground call, no bot) | no frame > 100 ms after F1 | 0.000 | **no frame**: the window is not the cause |
| botwarm (lights on at ~0 energy in frames 1-3) | 151 (draw 48, proc 56), 55 (29), 63 (33) | 0.07-0.21 | **frame B gone** |

- Control for `botwarm`: its F1 grows to 1786-3246 ms (slow class, with `night=0.010` in F1).
  In the slow class, `bot` F1 + frame B = 686 + 1109 = 1795 ms, and `botwarm` r2 F1 = 1786 ms.
  The cost moved; it did not go away. The `warm` events and the `night` column show that the
  lights really drew in frames 1-3, and that `night` is still 0.000 in base F1.
- The one `botwarm` wave-call frame over 100 ms (r1, 151 ms) is not a render stall. Its `draw`
  is 48 ms and the rest is script (`proc` 56 ms). That run was the slowest of the batch
  (`_initialize` at 5.9 s).
- Why lights: Godot's GL Compatibility canvas renderer draws a lit item with a different shader
  variant from an unlit one. By day `Lighting._apply_night()` sets every light
  `visible = night > 0.0` (`scenes/lighting.gd` 124-134), so no lit variant is compiled until
  the first night. All lights are `PointLight2D`s with a texture, `BLEND_MODE_ADD` and no
  shadows (`_light`, 224-235).

### Frame C (outside this task)

At night 0.81-0.83 (about 1 s after the wave call; enemy count 1): 138-162 ms in fast runs and
307-537 ms in slow runs, 95-99% in `draw`. It shows in every arm that calls a wave, including
`botwarm` (335-438 ms), so it is a different first use (probably the first enemy reaching a lit
or newly drawn area). Not diagnosed here.

## Effect on a future menu or intro

- **Frame A follows the first scene that draws the board.** A menu that draws only text and
  simple controls would get a 30-75 ms first frame (`label`, `menu`). The board's ~300 ms
  (0.5-1 s under load), plus ~230 ms of scene setup, would then land on the "New game"
  transition. As a single frame that looks like the game freezing on the click, unless the menu
  first shows a loading frame. A menu does not hide frame A; it only moves it to a moment the
  player sees as loading.
- **Frame B does not move with a menu.** It belongs to the first night of the run, so a menu
  does not change it. A menu that uses `Light2D` itself would compile part of the lit set early.
- On other platforms the picture may differ (not measured). Desktop GL drivers with program
  binaries would fill Godot's shader cache and pay A and B only on the first launch. WebGL has
  no such cache.

## Options for the owner

**Frame A**

- **A1: accept as load time (recommended).** Benefit: nothing to build, and it already falls in
  the startup window, before any input. Risk: nothing today. Revisit once a menu exists (see
  A2).
- **A2: when a menu or intro is added, draw one "Loading..." frame before the game scene is
  instanced and added.** Benefit: the 0.5-1 s on "New game" reads as loading, not as a freeze.
  Risk: almost none. It belongs to the menu task, not here.
- Not offered: a shader cache (macOS GL has no binaries to store), cutting draw calls to lower
  the compile cost (the cost is per variant, not per call: hiding the UI or Lighting does not
  move it).

**Frame B**

- **B1: warm the lit variants during frame A (recommended).** For the first 2-3 frames of a run,
  draw a light while the scene is still loading, at ~0 energy so nothing shows. Benefit: removes
  a 0.4-1.4 s freeze at the player's first wave call. That happens during play, when the first
  enemy spawns, so it is the one of the two that a player notices. Risk: frame A grows by about
  the same amount (fast class ~300 -> ~700 ms), so total startup is unchanged. A one- or
  two-frame tint is possible if the warm uses `night` (0.01 is invisible). The warm must cover
  the variants the night really uses. The probe warmed the glow and the beam; tower lights are
  the same light type. It does not fix frame C.
- **B2: accept.** Benefit: no code. Risk: a visible stall on every run's first wave call, on
  this hardware.

## Edit map for B1 (code slice)

- `scenes/lighting.gd`:
  - A new `const WARM_FRAMES := 3` next to the other constants (around line 44) and
    `var _warm_left := WARM_FRAMES`.
  - `_ready()` (83-104): create one dedicated `WarmLight` with `_light("WarmLight",
    _glow_texture(), BEAM_COLOR, WARM_ENERGY, <glow scale>)` at the lighthouse centre,
    visible. `WARM_ENERGY` is about 0.01 (the code slice checks whether 0.0 still selects the
    lit variant; if it does, use 0.0).
  - `_process()` (107-112): count `_warm_left` down and `queue_free()` the warm light at 0.
  - Do **not** reuse the beam/glow visibility for this. `tests/lighting_test.gd:93` asserts
    `beam.visible == false` by day after one awaited frame, and a dedicated node keeps every
    current day/night rule unchanged.
- Test (new, in `tests/lighting_test.gd`): after setup a `WarmLight` child exists, is visible,
  and is gone after `WARM_FRAMES` processed frames; beam and glow stay invisible by day
  throughout. Control: `WARM_FRAMES := 0` (or skip the node) makes it fail.
- Before/after measure: this slice's probe (appendix) with `--bot`, against the base commit
  and the fix commit, each from its own worktree, 4 runs per arm, interleaved, load gate as
  here. Pass: no frame over 150 ms in the frame after the wave call, in 4/4 fix runs (a draw
  step under 100 ms). Expected: base shows frame B in 4/4, and the fix's F1 grows by about
  frame B's size (that growth is the control that the warm drew).

## Appendix: probe92.gd (throwaway, removed)

Copy it into the worktree root. Run:
`/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s probe92.gd --
--seed=4242 --frame-stats --mute --probe-secs=6 [--bot|--build|--wave] [--fg=0.5] [--warm=3]
[--nomain|--menu=1.5] [--noui] [--nofx]`

```gdscript
extends SceneTree
## Throwaway LT-92 startup-frame probe (never committed). Logs every frame of the first
## seconds with a split: phys (post_draw -> first physics tick or head), proc (head -> tail
## node), gap (tail -> frame_pre_draw), draw (pre -> post draw, incl. swap) and wait (time
## after post_draw not spent in physics, i.e. OS event processing and frame pacing).
## Args (after `--`): --probe-secs=<s> --fg=<s> (window_move_to_foreground at wall s)
## --nofx (hide lighting + sanity_fx) --noui (hide the UI CanvasLayer) --nomain (no main scene)
var main: Node
var t0 := 0
var init_us := 0
var head_us := 0
var tail_prev := 0
var pre_us := 0
var post_us := 0
var phys_us := 0
var last_head := 0
var frame := 0
var secs := 6.0
var fg := -1.0
var fg_done := false
var events: PackedStringArray = []
var max_ms := 0.0
var bot := false
var bot_done := false
var sum_t := 0.0
var menu_s := -1.0
var menu_node: Node
var do_build := false
var do_wave := false
var warm := 0  ## frames during which lighting.night is set to 0.01 (lights drawn, ~invisible)
const ORDER := ["rifleman", "necronomicon_reader", "rifleman", "resonator", "harpooner", "elder_sign"]


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a == name:
			return "1"
		if a.begins_with(name + "="):
			return a.split("=")[1]
	return def


func _ms(us: int) -> float:
	return us / 1000.0


func _initialize() -> void:
	init_us = Time.get_ticks_usec()
	secs = float(_arg("--probe-secs", "6"))
	fg = float(_arg("--fg", "-1"))
	bot = _arg("--bot", "") != "" or _arg("--build", "") != "" or _arg("--wave", "") != ""
	do_build = _arg("--bot", "") != "" or _arg("--build", "") != ""
	do_wave = _arg("--bot", "") != "" or _arg("--wave", "") != ""
	warm = int(_arg("--warm", "0"))
	print("P92_INIT t=%.3f ds=%s win=%s pos=%s focus=%s screen_scale=%.1f" % [
		init_us / 1e6, DisplayServer.get_name(), DisplayServer.window_get_size(),
		DisplayServer.window_get_position(), DisplayServer.window_is_focused(),
		DisplayServer.screen_get_scale()])
	RenderingServer.frame_pre_draw.connect(func() -> void: pre_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: post_us = Time.get_ticks_usec())
	root.focus_entered.connect(func() -> void: events.append("focus_in@%.3f" % (Time.get_ticks_usec() / 1e6)))
	root.focus_exited.connect(func() -> void: events.append("focus_out@%.3f" % (Time.get_ticks_usec() / 1e6)))
	root.size_changed.connect(func() -> void: events.append("size%s@%.3f" % [root.size, Time.get_ticks_usec() / 1e6]))
	var a := Time.get_ticks_usec()
	menu_s = float(_arg("--menu", "-1"))
	if menu_s >= 0.0:
		var m := Label.new()
		m.text = "LOVECRAFT TD\n\nNew game\nOptions\nQuit"
		m.position = Vector2(400, 200)
		m.add_theme_font_size_override("font_size", 32)
		root.add_child(m)
		menu_node = m
	elif _arg("--nomain", "") == "":
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		var g: Game = main.game
		if g != null:
			if _arg("--nofx", "") != "":
				g.lighting.visible = false
				g.sanity_fx.visible = false
				for c in g.sanity_fx.get_children():
					if c is CanvasLayer:
						c.visible = false
			if _arg("--noui", "") != "":
				(g.get_node("UI") as CanvasLayer).visible = false
	var b := Time.get_ticks_usec()
	print("P92_MAIN ready_ms=%.1f game=%s win=%s pos=%s" % [_ms(b - a),
		main != null and main.get("game") != null, DisplayServer.window_get_size(),
		DisplayServer.window_get_position()])
	var tail := Tail.new()
	tail.process_priority = 100000
	root.add_child.call_deferred(tail)


class Tail extends Node:
	func _process(_d: float) -> void:
		Engine.set_meta("tail_us", Time.get_ticks_usec())


func _physics_process(_d: float) -> bool:
	if phys_us <= post_us:
		phys_us = Time.get_ticks_usec()
	return false


func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if fg >= 0.0 and not fg_done and now - init_us > int(fg * 1e6):
		DisplayServer.window_move_to_foreground()
		fg_done = true
		events.append("fg_call@%.3f" % (now / 1e6))
	sum_t += delta
	if menu_node != null and now - init_us > int(menu_s * 1e6):
		menu_node.queue_free()
		menu_node = null
		var a := Time.get_ticks_usec()
		main = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		events.append("menu_to_game_ms%.1f@%.3f" % [_ms(Time.get_ticks_usec() - a), now / 1e6])
	var g0: Game = main.get("game") if main != null else null
	if warm > 0 and g0 != null:
		warm -= 1
		g0.lighting.night = 0.01
		events.append("warm")
	if bot and not bot_done and sum_t > 0.5 and main != null and main.get("game") != null:
		bot_done = true
		var b0 := Time.get_ticks_usec()
		var n := _bot(main.game)
		events.append("bot%d_ms%.1f@%.3f" % [n, _ms(Time.get_ticks_usec() - b0), now / 1e6])
	if last_head > 0:
		var ms := _ms(now - last_head)
		var tl := int(Engine.get_meta("tail_us", last_head))
		var after := now - post_us
		var phys := 0
		if phys_us > post_us:
			phys = now - phys_us
		max_ms = maxf(max_ms, ms)
		print("F %d t=%.3f ms=%.1f proc=%.1f gap=%.1f draw=%.1f wait=%.1f phys=%.1f d=%.3f draws=%d foc=%s win=%s night=%.3f en=%d tw=%d sim=%s ev=%s" % [
			frame, last_head / 1e6, ms, _ms(tl - last_head), _ms(pre_us - tl), _ms(post_us - pre_us),
			_ms(after - phys), _ms(phys), delta,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			DisplayServer.window_is_focused(), DisplayServer.window_get_size(),
			g0.lighting.night if g0 != null else -1.0, g0.sim.state.enemies.size() if g0 != null else -1,
			g0.sim.state.towers.size() if g0 != null else -1,
			str(g0._frame_events).replace(" ", "") if g0 != null else "", ",".join(events)])
	else:
		print("P92_FIRST_PROC t=%.3f since_init_ms=%.1f ev=%s" % [now / 1e6, _ms(now - init_us), ",".join(events)])
	events.clear()
	frame += 1
	last_head = now
	if now - init_us > int(secs * 1e6):
		print("P92_END frames=%d max_ms=%.1f t=%.3f focus=%s" % [frame, max_ms, now / 1e6,
			DisplayServer.window_is_focused()])
		return true
	return false


## LT-90 occult bot, one shot: builds what it can on the best cells, then calls the wave.
func _bot(g: Game) -> int:
	var built := 0
	for id: String in (ORDER if do_build else []):
		var cfg := g.sim.config
		var rng_cells: float = cfg.towers[id].levels[0].range_cells
		var min_cells: float = cfg.towers[id].levels[0].min_range
		var m: MapDef = g.sim.state.map
		var best := Vector2i(-1, -1)
		var best_s := 0
		for y in m.height:
			for x in m.width:
				var c := Vector2i(x, y)
				if not m.is_buildable(c) or g.sim.state.tower_at.has(c):
					continue
				var score := 0
				for p in m.path:
					var d := Vector2(c - p).length()
					if d <= rng_cells and d >= min_cells:
						score += 1
				if score > best_s:
					best_s = score
					best = c
		if best.x < 0 or g.commands.build(id, best) != SimCommand.CommandResult.OK:
			break
		built += 1
	if do_wave:
		g.commands.call_wave()
	return built
```
