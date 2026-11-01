# LT-62: frame rate at low sanity in real play (diagnosis, slice S1)

Status: diagnosis only. No production code changed. All measurement code (probe, timing
accumulators, A/B switches) ran in a throwaway detached worktree
(`lovecraft-td-wt-lt62-probe`, removed after the slice); the patch is in the appendix.

Build: `release-0.4.0` HEAD 6575e4d, Godot 4.7.2, GL Compatibility, Intel Iris Plus
(OpenGL 4.1 INTEL-24.5.8), 2560x1600 Retina, vsync on.

## Verdict

1. **Steady frame rate: the sanity gap is not reproduced.** With a visible, focused,
   boot-fit window (2390x1344 px, as the owner runs it), a real bot run on one seed, and
   load gated below 25, madness (sanity 0) runs at **37.5-39.3 fps median** and sanity 100
   at **39.5-40.5 fps** (repeats at the start and end of the round). The gap is 1-3 fps
   (3-7 %), not 36 % and not "steadily 10-15 fps".
2. **All sanity presentation effects together cost ~4 fps (~10 %) in madness**:
   `allfx` 43.7 fps vs 37.5-39.3. Most of it is the full-screen SanityFx pass
   (`noscreen` 41.0 fps, +2-3). Every other single effect is inside the noise
   (37.7-39.4 fps). The sim-side madness mechanics (fakes, x2/astray shots, enemy buff)
   do not move the frame rate.
3. **Dips: one reproducible hitch, and it is not sanity-specific.** Every run, at both
   sanity levels, has **one 350-670 ms render stall in the frame that first draws a tower
   shot** (the rifleman tracer). A control confirms the cause: drawing one 2-px
   `draw_line` (alpha 0.01) during the first 3 s removes it (400 ms stall -> no frame over
   150 ms). It looks like a first-use GL shader/pipeline compile for thick lines. It
   comes ~10 s earlier at sanity 0 (enemies are 1.7x faster), so on a quick look it can
   read as "sanity 0 stutters". The FPS label averages over 1 s, so a 0.5 s stall shows
   as a dip in the label.
4. **Repeated dips to 5-6 fps are not reproduced on a quiet machine.** Frames over 100 ms
   numbered 2-15 per 180 s run when the load stayed below ~25, at both sanity levels.
   They rose to 30-57 per run exactly in the runs where sibling agents pushed the 1-min
   load to 58-118 (table below). 97 % of them (194 of 200 in the final round) are in render/present, not in scripts. No
   sim or presentation event lines up with them beyond the first-shot stall above.
5. **Nothing accumulates.** Over 5-minute madness runs, the node count stays at 266-276,
   orphan nodes at 0 and objects flat. Draw calls follow live enemies (720-835) and fall
   back between waves. The FPS medians follow live enemies and towers within a wave
   (43 -> 37 fps from wave 1 to wave 4, at both sanity levels). They do not trend down
   over time at sanity 0.
6. **Window state matters more than anything in the game.** When the window loses focus
   (another app comes to the front), the same run jumps to ~145 fps with the draw-call
   count frozen (739 for minutes). macOS stops presenting the occluded window. This is
   the "fast mode" of LT-38. LT-38's round-2 numbers were taken unfocused, so they did not
   measure real rendering. Every number in this note's final round is from frames with
   the window focused (focused share 1.00, no re-focus needed).

What this means for the owner's reports (36 % gap; then "steady 10-15 fps in madness";
then "about 40 with dips to 5-6"): on this machine, under the owner's conditions as
far as they can be reproduced, the only madness cost is ~4 fps from the effects (most of
it the screen pass), plus one first-shot hitch that is not caused by sanity. A steady
10-15 fps and repeated 5-6 fps dips need something this setup did not have: a much
larger board (towers/enemies), x2 speed, mouse hovering over UI, thermal throttling, or
a machine running something else. P2 below captures that context on the owner's machine.

## How it was measured

- Probe (SceneTree script, appendix B): starts `main.tscn` without `--resolution` (the
  LT-22 boot fit gives a 2390x1344 px window, stretch 2.07), with
  `-- --seed=4242 --sanity=<0|100> --frame-stats`, i.e. the owner's flags: sanity is set
  once by the game, not re-pinned. A bot plays the real waves. It builds
  rifleman, necronomicon_reader, rifleman, resonator, harpooner, elder_sign on the
  best-covering cells as gold allows. It builds occult towers only while the cap stays at
  >= 70, so the build decisions do not depend on the sanity arm. It sells relics and
  lights the lamp at once. Only lighthouse HP is pinned, so a madness run is not lost. It
  calls `window_move_to_foreground()` at start and again every 5 s while unfocused (it
  never had to).
- Per frame: the wall-clock interval, focus, madness state, screen-pass visibility,
  sanity-effect state, live enemies and fakes, effects, node, orphan and object counts,
  and draw calls. Any frame over 50 ms prints a `SPIKE` line with the time spent in each
  instrumented function during that interval, the sim events consumed in it (by type;
  astray shots and fake spawns separately) and the state deltas. A `TS` line every 30 s.
- Sampling: 180 s (t = 10-190 s, waves 1-4) per arm. One background script, arms in
  sequence. Before each arm it waits until the 1-min load is < 25 (at most 20 min).
  `uptime` before/after and `/usr/bin/time -p` per arm.
- Sanity A/B switches at sanity 0 (throwaway, appendix A): `noscreen` (SanityFx
  distortion rect hidden), `nowobble` (distortion and aberration set to 0, pass still on),
  `nojitter` (HUD jitter material not assigned), `noflicker` (enemy flicker and torn
  doubles), `nomadtint` (madness tint and outline on enemies), `notorn` (plain sanity
  fill), `nophantom`, `nofakes` (no hallucination spawns), `nomadshots` (no x2 / astray
  for madness-affected towers), `nomadbuff` (no enemy speed/armour buff). `allfx` = every
  presentation switch, `allsim` = the three sim switches.
- Lighting has no sanity input (`scenes/lighting.gd` reads only phase, beams, flare and
  towers), so there is no "lighting changes" arm. Whisper audio was ruled out in LT-38.

## Control: the arms differ where they should

The same run gives the madness arms state 3 on 100 % of frames, the screen pass visible
on 100 % (`allfx`/`noscreen`: 0 %), HUD jitter 2.5 px, flicker 0.85 and the torn bar on
100 % of frames. Sanity 100: state 0 on 100 %, screen pass 0 %. `nomadshots` and `allsim`:
0 astray shots against 171-268 in the other madness arms. `nofakes`: 0 fake spawns.
`allfx`/`noscreen`: screen-pass visibility 0.00. So a null result for an effect means that
effect was really off, not that the switch failed.

## Final round (occult bot, load-gated, focused)

fps = 1000 / median frame interval. p10 / p1 = the 10th / 1st percentile frame rate.
`>100` = frames over 100 ms (count / total ms). Load = 1-min average before / after.

| # | arm | load before / after | user / sys / real (s) | fps med | p10 | p1 | >50 ms | >100 ms (ms) | astray | towers |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 100 | 24.9 / 15.3 | 82.2 / 41.3 / 197.2 | 39.5 | 31.4 | 19.3 | 79 | 11 (1673) | 0 | 15 |
| 2 | 0 | 22.3 / **71.4** | 81.2 / 40.6 / 199.2 | 37.5 | 28.0 | 12.3 | 268 | 30 (4175) | 184 | 5 |
| 3 | 0 noscreen | 22.3 / 21.3 | 85.0 / 43.2 / 196.1 | 41.0 | 35.0 | 18.6 | 85 | 11 (1848) | 185 | 5 |
| 4 | 0 nowobble | 21.3 / 21.9 | 85.0 / 42.4 / 200.2 | 38.2 | 32.4 | 16.3 | 124 | 15 (2403) | 185 | 5 |
| 5 | 0 nojitter | 21.9 / **118.2** | 78.6 / 39.4 / 199.9 | 38.4 | 29.1 | 10.3 | 328 | 57 (7830) | 185 | 5 |
| 6 | 0 noflicker | 23.7 / 22.3 | 80.4 / 39.7 / 195.8 | 39.4 | 34.1 | 17.0 | 101 | 14 (2081) | 185 | 5 |
| 7 | 0 nomadtint | 22.3 / 18.6 | 82.8 / 42.3 / 198.6 | 39.3 | 34.9 | 25.2 | 31 | 4 (863) | 185 | 5 |
| 8 | 0 notorn | 18.6 / 23.4 | 85.3 / 43.0 / 198.8 | 39.2 | 33.8 | 24.9 | 28 | 2 (587) | 185 | 5 |
| 9 | 0 nophantom | 23.4 / 35.1 | 82.3 / 41.1 / 200.1 | 38.6 | 31.2 | 14.4 | 163 | 24 (3615) | 185 | 5 |
| 10 | 0 nofakes | 22.8 / **58.5** | 79.1 / 39.6 / 197.5 | 38.8 | 30.7 | 12.3 | 230 | 25 (3304) | 171 | 5 |
| 11 | 0 nomadshots | 24.0 / 28.3 | 83.8 / 42.0 / 199.7 | 38.7 | 33.0 | 18.0 | 88 | 6 (1263) | 0 | 4 |
| 12 | 0 nomadbuff | 21.7 / 23.0 | 82.3 / 41.5 / 198.4 | 37.7 | 30.0 | 21.7 | 57 | 5 (918) | 268 | 15 |
| 13 | 0 allfx | 23.0 / 11.2 | 84.3 / 42.6 / 197.1 | **43.7** | 38.1 | 29.5 | 5 | 1 (354) | 185 | 5 |
| 14 | 0 allfx + allsim | 11.2 / 17.7 | 79.5 / 39.4 / 196.3 | 41.1 | 34.8 | 28.3 | 12 | 2 (742) | 0 | 14 |
| 15 | 100 | 17.7 / 14.0 | 82.3 / 41.0 / 196.6 | 40.5 | 35.0 | 29.5 | 8 | 2 (508) | 0 | 15 |
| 16 | 0 | 14.0 / 12.9 | 86.0 / 42.8 / 197.8 | 39.3 | 34.3 | 26.4 | 23 | 2 (566) | 185 | 5 |

Reading it:
- `user`+`sys` is ~123 s of 197 s real in every arm (the process is busy, not waiting).
  The arms do not differ in CPU, so the work per frame is the same order everywhere.
- The p10/p1 and spike columns follow the **load after** column, not the arm: rows 2, 5,
  9 and 10 are the arms during which other agents' test runs pushed the load to 35-118.
  Rows 2 and 16 are the same arm (19 vs 2 spikes > 100 ms and p1 12.3 vs 26.4). Treat the
  spike counts of rows 2, 5, 9 and 10 as disturbed. The medians barely move with load
  (37.5 vs 39.3).
- The madness board has 5 towers against 15 at sanity 100. Fewer kills mean less gold, so
  the sanity 0 board is *lighter*, and its fps is still 1-3 lower. `nomadbuff` (15
  towers, like sanity 100) gives 37.7 fps, inside the same band. A madness run on a full
  board, as a strong player would have, was not measured. Its cost would come from board
  size, which drives `Board._draw` and draw calls the same way at every sanity.
- Per-frame script time (averages from the round-1 probe, same instrumentation, mundane
  board): sanity 0 `Board._draw` 2.4 ms (enemies 1.7), `sim.step` 0.9, `Hud.refresh` 0.5,
  every other section < 0.25, node `_process` total ~2 ms; sanity 100 `Board._draw` 1.0,
  `sim.step` 0.5, `Hud.refresh` 0.35. That is 3-5 ms of a ~25 ms frame. The rest is render
  + present (render CPU 11-16 ms per frame).

### Per-wave time series, quiet arms (fps median / p10, live enemies, nodes, draws)

| t (s) | 100 (row 15) | 0 (row 16) | 0 allfx (row 13) |
|---|---|---|---|
| 31 | 42.3 / 37.9, 8 en, 266 n, 729 d | 39.1 / 33.2, 6 en, 266 n, 729 d | 43.1 / 37.5, 6 en, 266 n, 720 d |
| 61 | 43.1 / 39.8, 11 en, 267 n | 41.9 / 35.6, 21 en, 267 n, 787 d | 46.1 / 40.4, 21 en, 759 d |
| 91 | 43.1 / 38.6, 9 en | 40.1 / 34.4, 9 en | 42.4 / 38.0, 9 en |
| 121 | 39.5 / 35.9, 16 en, 762 d | 38.2 / 33.0, 30 en, 809 d | 44.2 / 39.1, 25 en, 768 d |
| 151 | 39.6 / 36.7, 12 en | 40.3 / 36.8, 2 en, 269 n | 44.5 / 39.7, 2 en |
| 181 | 36.8 / 32.2, 9 en, 276 n, 790 d | 37.0 / 34.2, 22 en, 269 n, 798 d | 40.9 / 36.5, 22 en, 768 d |

Orphan nodes are 0 in every bucket of every run. Earlier 300-s runs with a mundane bot
(round 3) show the same thing up to wave 5: node count 267 -> 273, orphans 0.

### Spikes > 200 ms, every arm of the final round

Exactly one per run (two in `nojitter`, which ran at load 118), always at the first tower
shot: t = 15.7 s at sanity 0 and t = 25.4 s at sanity 100, 354-674 ms, all in render
(`rest`), scripts 1.8-2.8 ms, events `SHOT:1`, `d_fx=+1`. Present in `allfx`, `noscreen`,
`nomadshots`, `nofakes` and at sanity 100, so no sanity effect causes it.

Control (two 30 s runs, sanity 100, load 13-20): baseline 401 ms stall at t = 25.43 s
(first SHOT); with `--ab-warmtracer` (one `draw_line(..., 2.0)` at alpha 0.01 on the board
during the first 3 s) no frame over 150 ms in the whole run. The first draw of a
thick line costs ~0.4-0.7 s once per process. Enemy madness outlines (`draw_arc` width 3)
are drawn from the first frame at sanity 0, and the stall still comes at the first
tracer. So the expensive first use is `draw_line` with a width, not `draw_arc`.

### Earlier rounds (kept for the record, not used for the verdict)

- Round 1 (mundane bot, 90 s): stopped after one arm on a changed brief; it ran at load
  86-205.
- Round 3 (mundane bot, 300 s, no load gate): sanity 100 and 0 ran **unfocused**
  (focused 0.05 / 0.01) at ~145 fps with draw calls frozen at 739. `0 noscreen` and
  `0 allfx` ran focused at 36 fps median, with 83 / 121 spikes over 100 ms at load 70-198.
  This round shows the focus effect and the load effect described in the verdict.

## Fix proposals

**P1 (recommended): warm up the thick-line draw at game start.** In the board's first
frames, issue one invisible `draw_line` with a width (and, to be safe, one of each other
primitive the effects use that the first frames do not: `draw_polyline` for the astray
waver and wave, `draw_colored_polygon`), for example during the first 0.5 s of
`Board._draw`.
- Benefit: removes the 0.35-0.67 s stall at the first shot of every run, at every sanity
  level (measured by the control above). That stall is the one dip reproduced here.
- Risk: it treats a driver/engine symptom, and other first-use variants may exist that
  this run did not hit (other tower kinds, flare, blast). The verify slice should
  re-run the spike log with every tower kind on the board. A dot at alpha 0.01 in the
  board corner is invisible, but it is still a draw.

**P2 (recommended, cheap): make `--frame-stats` log spikes with context.** Extend the
existing debug overlay (`FrameStats`) so that it prints every frame over 100 ms with a
timestamp, the sanity state, live enemies, towers, effects, the sim events of that frame
and the window focus, plus the worst frame in the last second next to the median. Then
the owner's next run shows what his 5-6 fps dips coincide with.
- Benefit: the owner's repeated dips and steady 10-15 fps are not reproduced here. This
  is the cheapest way to see them on his machine, with his board, speed and mouse
  activity.
- Risk: debug-only code that must stay behind the flag (as now). It needs one more owner
  run.

**P3 (owner decision, optional): make the SanityFx screen pass cheaper.** It is the only
measurable steady madness cost here, ~2-3 fps of the ~4 fps total (`noscreen` 41.0,
`allfx` 43.7 vs 37.5-39.3). Options: one texture fetch instead of three when aberration
is ~0 (it is 6 px x stretch at madness, so not ~0); compute the wave only on the board
area; or a lower-resolution pass.
- Benefit: up to ~5-7 % in madness, Whispers and Fraying.
- Risk: it changes the agreed look (GDD §5.3/§9), and the gain is small and near the
  noise. Not worth doing before P2 shows what the owner's machine actually spends.

**Not recommended:** removing or simplifying HUD jitter, flicker, madness tint, torn bar,
phantom, fakes or madness shots for performance. None of them moved the steady frame rate
beyond the noise, and the spike counts follow the machine load, not these switches.

## Edit map for the code slice

Line numbers are from `release-0.4.0` (6575e4d).

| proposal | file | function / item | lines | change |
|---|---|---|---|---|
| P1 | `scenes/board.gd` | `_draw` | 519-540 | first ~0.5 s (`_time`): one alpha-0.01 `draw_line(..., 2.0)`, `draw_polyline`, `draw_colored_polygon` in a corner |
| P1 | `scenes/board.gd` | `tick_effects` (`_time`) | 451-460 | read only: `_time` is the warm-up clock |
| P1 | `tests/` (new or `tower_attack_visuals_test.gd`) | | | warm-up draws happen only while `_time` < the window; no visible change after |
| P2 | `scenes/frame_stats.gd` | `push`, `text` | 16-22, 37-41 | keep the max of the last second; expose "spike" when a push is > 100 ms |
| P2 | `scenes/game.gd` | `advance` | 126-131 | on a spike, print one line: t, ms, sanity state, enemies, towers, `board.effects.size()`, focus, the event types consumed by `_consume_events` this frame |
| P2 | `scenes/game.gd` | `_consume_events` | 265-279 | count event types per frame (only when `frame_stats != null`) |
| P2 | `ui/hud.gd` | `refresh` (frame label) | 174-179 | show "worst x ms" next to median/p90 |
| P2 | `tests/frame_stats_test.gd` | | | max-of-last-second and spike threshold |
| P3 | `shaders/sanity_screen.gdshader` | `fragment` | 17-end | cheaper aberration / board-only wave |
| P3 | `scenes/sanity_fx.gd` | `_apply` | 115-134 | matching params |

Read for context: `Board._draw_tracer` (808-829, the first thick `draw_line`),
`Board._draw_effects` (742-771, the effect kinds), `Board._draw_enemies` (660-715),
`Game._consume_events` (265-279), `Hud._refresh_fps` (214-222, the 1-s FPS label).

## What was ruled out, and how

- Node / orphan / object accumulation: flat over 5-minute madness runs (266-276 nodes, 0
  orphans).
- Each sanity presentation effect alone: within 37.7-39.4 fps against 37.5-39.3 base.
- Hallucination fakes, madness x2/astray shots, madness enemy buff: same band
  (38.8 / 38.7 / 37.7). The control shows they were off (0 fakes / 0 astray).
- Script time as the cause of dips: 97 % of frames over 100 ms are in render/present;
  scripts are 2-3 ms in those frames.
- Sanity as the cause of the first-shot hitch: same stall at sanity 100 and with every
  switch; removed by a thick-line warm-up.
- Not settled: the owner's steady 10-15 fps and repeated 5-6 fps dips. Not reproduced
  with a focused window at load < 25. Candidates not covered: a full board (15+ towers in
  madness), x2 speed, hovering the picker/tooltips, thermal state of the owner's machine.
  P2 is the way to find out.

## Appendix A: throwaway patch (applied only in the probe worktree)

Timing accumulators (`Game._pp`), A/B switches (`Game._ab`, `--ab-<name>`), per-frame event
counts (`Game._evc`), and the `warmtracer` control. `git diff` of the probe worktree
against 6575e4d:

```diff
diff --git a/scenes/board.gd b/scenes/board.gd
index e2e006f..4f4eec0 100644
--- a/scenes/board.gd
+++ b/scenes/board.gd
@@ -467,7 +467,7 @@ func _flicker_strength() -> float:
 ## While Fraying / in Madness a phantom stretch of path appears off the real one, flickers
 ## and moves elsewhere every second or two (GDD §5.3 "phantom path flickers on screen").
 func _tick_phantom(delta: float) -> void:
-	if _flicker_strength() <= 0.0:
+	if _flicker_strength() <= 0.0 or Game._ab("nophantom"):
 		phantom.clear()
 		return
 	_phantom_ttl -= delta
@@ -517,17 +517,28 @@ func _flicker_dip(key: int) -> float:
 
 
 func _draw() -> void:
+	var __t := Time.get_ticks_usec()
+	_draw_real()
+	Game._pp("board_draw", __t)
+
+
+func _draw_real() -> void:
 	if game == null or game.sim == null:
 		return
+	if Game._ab("warmtracer") and _time < 3.0:
+		draw_line(Vector2(2, 2), Vector2(6, 2), Color(TRACER_COLOR, 0.01), 2.0)
 	var s := game.sim.state
 	sync_map()  # O(1) unless the map changed; the map itself is drawn by map_layer
 	_draw_phantom()
 	_draw_auras(s)
 	for t in s.towers:
 		_draw_tower(t)
+	var __e := Time.get_ticks_usec()
 	_draw_enemies(s)
+	__e = Game._pp("board_enemies", __e)
 	_draw_allies(s)
 	_draw_effects()
+	Game._pp("board_effects", __e)
 	if game.sim.state.map.in_bounds(selected_cell):
 		draw_rect(Rect2(cell_origin(selected_cell), Vector2(CELL, CELL)), COLOR_SELECT, false, 2.0)
 		if selected_range > 0.0:
@@ -662,6 +673,10 @@ func _draw_enemies(s: SimState) -> void:
 	var fl := _flicker_strength()
 	# LT-23 Q10: the smoothed madness grade tints and outlines every enemy alike.
 	var mad := game.sanity_fx.madness if game.sanity_fx != null else 0.0
+	if Game._ab("noflicker"):
+		fl = 0.0
+	if Game._ab("nomadtint"):
+		mad = 0.0
 	for e in s.enemies:
 		if not e.is_live():
 			continue
diff --git a/scenes/game.gd b/scenes/game.gd
index 72b9215..4188f7e 100644
--- a/scenes/game.gd
+++ b/scenes/game.gd
@@ -24,6 +24,7 @@ var paused := false
 var run_seed := 0
 var frame_stats: FrameStats  ## LT-38 P1: null unless `--frame-stats` in a debug build
 var _last_frame_usec := 0
+var _evc := {}
 
 var board: Board
 var lighting: Lighting  ## LT-8: darkness, beam, tower lights, sea fog (visual only)
@@ -118,6 +119,19 @@ func _ready() -> void:
 	hud.refresh()
 
 
+static var _ab_args: PackedStringArray = []
+static var _ab_init := false
+static func _ab(n: String) -> bool:
+	if not _ab_init:
+		_ab_init = true
+		_ab_args = OS.get_cmdline_user_args()
+	return _ab_args.has("--ab-" + n)
+static func _pp(k: String, t: int) -> int:
+	var now := Time.get_ticks_usec()
+	Engine.set_meta("p_" + k, int(Engine.get_meta("p_" + k, 0)) + now - t)
+	return now
+
+
 func _process(delta: float) -> void:
 	advance(delta)
 
@@ -129,18 +143,24 @@ func advance(delta: float) -> void:
 		if _last_frame_usec > 0:
 			frame_stats.push((now - _last_frame_usec) / 1000.0)
 		_last_frame_usec = now
+	var __t := Time.get_ticks_usec()
 	var steps := clock.advance(delta)
 	for i in steps:
 		sim.step()
+	__t = _pp("sim_step", __t)
 	_consume_events()
+	__t = _pp("events", __t)
 	board.alpha = clock.alpha()
 	board.tick_effects(delta)
 	relic_tokens.tick(delta)
 	board.queue_redraw()
+	__t = _pp("board_tick", __t)
 	hud.refresh()
+	__t = _pp("hud_refresh", __t)
 	picker.refresh()
 	tower_panel.refresh()
 	lighthouse_panel.refresh()
+	__t = _pp("panels", __t)
 
 
 # --- Player commands (forwarded to the sim) -------------------------------------------
@@ -264,6 +284,12 @@ func _after_command() -> void:
 
 func _consume_events() -> void:
 	for ev in sim.drain_events():
+		var __k: String = SimEvent.Type.keys()[ev.type]
+		if ev.type == SimEvent.Type.SHOT and ev.data.get("astray", false):
+			__k = "SHOT_ASTRAY"
+		if ev.type == SimEvent.Type.SPAWNED and sim.enemy_by_id(ev.id) != null and sim.enemy_by_id(ev.id).is_fake:
+			__k = "SPAWNED_FAKE"
+		_evc[__k] = _evc.get(__k, 0) + 1
 		board.on_event(ev)
 		sanity_fx.on_event(ev)
 		relic_tokens.on_event(ev)
diff --git a/scenes/lighting.gd b/scenes/lighting.gd
index 5df8350..f927a43 100644
--- a/scenes/lighting.gd
+++ b/scenes/lighting.gd
@@ -92,6 +92,12 @@ func _ready() -> void:
 
 
 func _process(delta: float) -> void:
+	var __t := Time.get_ticks_usec()
+	_process_real(delta)
+	Game._pp("lighting", __t)
+
+
+func _process_real(delta: float) -> void:
 	_sync_beams()
 	_sync_tower_lights()
 	ease_night(delta)
diff --git a/scenes/sanity_fx.gd b/scenes/sanity_fx.gd
index 5ceba56..ff9c81b 100644
--- a/scenes/sanity_fx.gd
+++ b/scenes/sanity_fx.gd
@@ -70,7 +70,9 @@ func on_event(ev: SimEvent) -> void:
 
 
 func _process(delta: float) -> void:
+	var __t := Time.get_ticks_usec()
 	tick(delta)
+	Game._pp("fx_tick", __t)
 
 
 ## One frame of smoothing, then pushes the values to the shaders and the audio.
@@ -127,8 +129,11 @@ func _apply() -> void:
 	screen_material.set_shader_parameter("distortion", max_distortion_px * level * px)
 	screen_material.set_shader_parameter("aberration", max_aberration_px * level * px)
 	screen_material.set_shader_parameter("vignette", max_vignette * level)
+	if Game._ab("nowobble"):
+		screen_material.set_shader_parameter("distortion", 0.0)
+		screen_material.set_shader_parameter("aberration", 0.0)
 	screen_material.set_shader_parameter("madness", madness)
 	screen_material.set_shader_parameter("pulse", pulse)
 	# Lucid costs nothing: the screen copy only runs while something is shown.
-	screen_rect.visible = level > 0.001 or pulse > 0.0 or madness > 0.0
+	screen_rect.visible = (level > 0.001 or pulse > 0.0 or madness > 0.0) and not Game._ab("noscreen")
 	audio.set_state(state)
diff --git a/sim/core/simulation.gd b/sim/core/simulation.gd
index 0c7b7cc..d9f6bb9 100644
--- a/sim/core/simulation.gd
+++ b/sim/core/simulation.gd
@@ -103,7 +103,8 @@ func step() -> void:
 	# here. The flare timers count down last.
 	_update_beam()
 	_apply_auras()
-	_apply_madness_buff()
+	if not OS.get_cmdline_user_args().has("--ab-nomadbuff"):
+		_apply_madness_buff()
 	_apply_flare_slow()
 	_tick_statuses()
 	# LT-52 (P10): allies past their lifetime are gone; the rest hold their enemy
@@ -132,7 +133,8 @@ func step() -> void:
 	# 7. Spawning, then fakes (LT-12) from the spawner's candidates.
 	if _spawner != null:
 		_spawner.tick(self)
-		_hallucinations.tick(self, _spawner)
+		if not OS.get_cmdline_user_args().has("--ab-nofakes"):
+			_hallucinations.tick(self, _spawner)
 	# 8. Remove dead and leaked enemies and gone allies (LT-52); then the wave system settles
 	# a cleared wave (its bonus is paid before the outcome check, so the last wave's bonus
 	# lands too).
@@ -1483,7 +1485,7 @@ func _fire_towers() -> void:
 		if t.lit and t.def.kind == "occult":
 			damage *= beam.occult_power_mult  # LT-30 §2, before the madness x2
 		var astray := ""
-		if s.madness_affected and state.sanity_state == SimState.SanityState.MADNESS:
+		if s.madness_affected and state.sanity_state == SimState.SanityState.MADNESS and not OS.get_cmdline_user_args().has("--ab-nomadshots"):
 			damage *= config.sanity.madness.damage_multiplier
 			astray = _roll_astray()
 			var pool: Array[SimEnemy] = []
@@ -1581,7 +1583,7 @@ func _cast_banish(t: SimTower, s: TowerDef.Level) -> void:
 	var power := beam.occult_power_mult if t.lit and t.def.kind == "occult" else 1.0
 	var damage := s.damage * power
 	var astray := ""
-	if s.madness_affected and state.sanity_state == SimState.SanityState.MADNESS:
+	if s.madness_affected and state.sanity_state == SimState.SanityState.MADNESS and not OS.get_cmdline_user_args().has("--ab-nomadshots"):
 		damage *= config.sanity.madness.damage_multiplier
 		astray = _roll_astray()
 		var pool: Array[SimEnemy] = []
diff --git a/ui/hud.gd b/ui/hud.gd
index f35125a..44de609 100644
--- a/ui/hud.gd
+++ b/ui/hud.gd
@@ -132,7 +132,7 @@ func _ready() -> void:
 		frame_label.position = Vector2(RELIC_SLOT, Game.BOARD_ORIGIN.y + 2)
 		add_child(frame_label)
 	# LT-14 Whispers jitter: the shader moves only the drawing, so click areas stay put.
-	if game.sanity_fx != null:
+	if game.sanity_fx != null and not Game._ab("nojitter"):
 		for c: CanvasItem in [gold_label, relics_label, hp_label, phase_label,
 				luck_label, call_wave_button, sell_relics_button, speed_button, pause_button,
 				sanity_bar, buyout_button]:
diff --git a/ui/sanity_bar.gd b/ui/sanity_bar.gd
index a0880b3..1a7adb4 100644
--- a/ui/sanity_bar.gd
+++ b/ui/sanity_bar.gd
@@ -75,6 +75,12 @@ func mark_ratios() -> PackedFloat32Array:
 
 
 func _draw() -> void:
+	var __t := Time.get_ticks_usec()
+	_draw_real()
+	Game._pp("bar_draw", __t)
+
+
+func _draw_real() -> void:
 	if game == null or game.sim == null:
 		return
 	var s := game.sim.state
@@ -83,7 +89,7 @@ func _draw() -> void:
 	draw_rect(r, COLOR_BACK)
 	var fill := r.size.x * fill_ratio()
 	var color := STATE_COLORS[st]
-	var torn := st >= SimState.SanityState.FRAYING
+	var torn := st >= SimState.SanityState.FRAYING and not Game._ab("notorn")
 	if torn:
 		_draw_torn_fill(r, fill, color, st == SimState.SanityState.MADNESS)
 	else:
```

## Appendix B: probe (`-s probe3.gd`)

Run: `godot --path . -s probe3.gd -- --seed=4242 --sanity=<v> --frame-stats --probe-secs=180 [--ab-...]`
(needs the appendix A patch for the section times, the event counts and the switches).

```gdscript
extends SceneTree
## Throwaway LT-62 spike probe. Starts main.tscn like the owner (boot-fit window,
## --sanity=<v> set once, --frame-stats), plays with a mundane bot (rifleman, rifleman,
## harpooner on the best cells, call the wave at once), pins only lighthouse HP.
## Every frame from t=1 s: if the wall-clock interval > SPIKE_MS it prints a SPIKE line with
## the per-section ms of that interval (patch.py accumulators), the sim events consumed in
## it (patch_ev.py) and the state deltas. Every BUCKET s a TS line. At the end a PROBE line.
var main: Node
var t := 0.0
var started := false
var pin_t := 0.0
var last_us := 0
var frame_ms: Array[float] = []
var b_frames: Array[float] = []
var b_t := 0.0
var b_spk50 := 0
var b_spk100 := 0
var spk50 := 0
var spk100 := 0
var spk100_ms := 0.0
var idx := 0
var waves_called := 0
var score_cache := {}
var prev_meta := {}
var prev := {}
var focused_frames := 0
var mad_frames := 0
var screen_vis_frames := 0
var frames := 0
var astray_total := 0
const ORDER := ["rifleman", "necronomicon_reader", "rifleman", "resonator", "harpooner", "elder_sign"]
const CAP_FLOOR := 70.0  ## occult builds only while the cap stays Lucid (same decisions in every arm)
var refocus_t := 0.0
var refocus_n := 0
const SPIKE_MS := 50.0
const BUCKET := 30.0
var T_END := 370.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-secs="):
			T_END = 10.0 + float(a.split("=")[1])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var tail := Tail.new()
	tail.process_priority = 100000
	root.add_child.call_deferred(tail)


class Tail extends Node:
	func _process(_d: float) -> void:
		Engine.set_meta("tail_us", Time.get_ticks_usec())


func _best_cell(g: Game, id: String) -> Vector2i:
	var cfg := g.sim.config
	if not score_cache.has(id):
		var rng_cells: float = cfg.towers[id].levels[0].range_cells
		var min_cells: float = cfg.towers[id].levels[0].min_range
		var m: MapDef = g.sim.state.map
		var list: Array = []
		for y in m.height:
			for x in m.width:
				var c := Vector2i(x, y)
				if not m.is_buildable(c):
					continue
				var score := 0
				for p in m.path:
					var d := Vector2(c - p).length()
					if d <= rng_cells and d >= min_cells:
						score += 1
				if score > 0:
					list.append([score, c])
		list.sort_custom(func(a, b): return a[0] > b[0])
		score_cache[id] = list
	for e in score_cache[id]:
		if not g.sim.state.tower_at.has(e[1]):
			return e[1]
	return Vector2i(-1, -1)


func _bot(g: Game) -> void:
	if g.sim.state.phase != SimState.Phase.BUILD:
		return
	g.sell_relics()
	var skips := 0
	while skips < ORDER.size():
		var id: String = ORDER[idx % ORDER.size()]
		var def = g.sim.config.towers[id]
		if def.kind == "occult" and g.sim.state.sanity_cap - def.levels[0].sanity_reserve < CAP_FLOOR:
			idx += 1
			skips += 1
			continue
		skips = 0
		var cell := _best_cell(g, id)
		if cell.x < 0 or g.build(id, cell) != Simulation.CommandResult.OK:
			break
		idx += 1
	if g.call_wave() == Simulation.CommandResult.OK:
		waves_called += 1


func _snap(g: Game) -> Dictionary:
	var live := 0
	var fakes := 0
	for e in g.sim.state.enemies:
		if e.is_live():
			live += 1
			if e.is_fake:
				fakes += 1
	return {"enemies": live, "fakes": fakes, "fx": g.board.effects.size(),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"towers": g.sim.state.towers.size(), "wave": g.sim.state.wave_index,
		"phase": int(g.sim.state.phase), "state": int(g.sim.state.sanity_state),
		"screen": g.sanity_fx.screen_rect.visible, "phantom": g.board.phantom.size(),
		"tick": g.sim.state.tick}


func _process(delta: float) -> bool:
	t += delta
	var g: Game = main.game
	if g == null:
		return false
	var now := Time.get_ticks_usec()
	if not started and t > 0.5:
		DisplayServer.window_move_to_foreground()
		started = true
		print("PROBE_START seed=%d win_px=%s stretch=%.2f vsync=%d focused=%s sanity=%.1f state=%d" % [
			g.run_seed, DisplayServer.window_get_size(), g.sanity_fx.screen_scale(),
			DisplayServer.window_get_vsync_mode(), DisplayServer.window_is_focused(),
			g.sim.state.sanity, int(g.sim.state.sanity_state)])
	if started:
		_bot(g)
		refocus_t += delta
		if refocus_t > 5.0:
			refocus_t = 0.0
			if not DisplayServer.window_is_focused():
				DisplayServer.window_move_to_foreground()
				refocus_n += 1
		pin_t += delta
		if pin_t > 0.5:
			pin_t = 0.0
			g.sim.state.lighthouse_hp = 100000
	# Section deltas over the interval that just ended.
	var meta := {}
	for k in Engine.get_meta_list():
		if String(k).begins_with("p_"):
			meta[String(k).substr(2)] = int(Engine.get_meta(k))
	var cur := _snap(g)
	var evc: Dictionary = g._evc.duplicate()
	astray_total += int(evc.get("SHOT_ASTRAY", 0))
	g._evc.clear()
	if started and t > 1.0 and t <= T_END and last_us > 0:
		var ms := (now - last_us) / 1000.0
		frames += 1
		frame_ms.append(ms)
		b_frames.append(ms)
		if DisplayServer.window_is_focused():
			focused_frames += 1
		if cur["state"] == SimState.SanityState.MADNESS:
			mad_frames += 1
		if cur["screen"]:
			screen_vis_frames += 1
		if ms > SPIKE_MS:
			spk50 += 1
			b_spk50 += 1
			if ms > 100.0:
				spk100 += 1
				b_spk100 += 1
				spk100_ms += ms
			var secs := []
			for k in meta:
				var d: float = (int(meta[k]) - int(prev_meta.get(k, 0))) / 1000.0
				if d >= 0.5:
					secs.append("%s=%.1f" % [k, d])
			var tl := int(Engine.get_meta("tail_us", 0))
			var deltas := []
			for k in ["enemies", "fakes", "fx", "nodes", "orphans", "objects", "towers"]:
				var dd: int = cur[k] - int(prev.get(k, 0))
				if dd != 0:
					deltas.append("d_%s=%+d" % [k, dd])
			var ev := []
			for k in evc:
				ev.append("%s:%d" % [k, evc[k]])
			print("SPIKE t=%.2f ms=%.1f nodes_proc=%.1f rest=%.1f rcpu=%.1f | %s | ev %s | %s | enemies=%d fakes=%d fx=%d nodes=%d draws=%d wave=%d phase=%d state=%d screen=%s focused=%s ticks+%d" % [
				t, ms, (tl - last_us) / 1000.0 if tl > last_us else -1.0, (now - tl) / 1000.0 if tl > last_us else -1.0,
				RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
				" ".join(secs), " ".join(ev), " ".join(deltas), cur["enemies"], cur["fakes"], cur["fx"],
				cur["nodes"], cur["draws"], cur["wave"], cur["phase"], cur["state"], cur["screen"],
				DisplayServer.window_is_focused(), cur["tick"] - int(prev.get("tick", 0))])
		b_t += delta
		if b_t >= BUCKET:
			print("TS t=%.0f fps_med=%.1f fps_p10=%.1f fps_min=%.1f spikes50=%d spikes100=%d enemies=%d fakes=%d fx=%d nodes=%d orphans=%d objects=%d draws=%d wave=%d towers=%d state=%d focused=%s" % [
				t, 1000.0 / _pct(b_frames, 0.5), 1000.0 / _pct(b_frames, 0.9), 1000.0 / _pct(b_frames, 1.0),
				b_spk50, b_spk100, cur["enemies"], cur["fakes"], cur["fx"], cur["nodes"], cur["orphans"],
				cur["objects"], cur["draws"], cur["wave"], cur["towers"], cur["state"],
				DisplayServer.window_is_focused()])
			b_t = 0.0
			b_frames.clear()
			b_spk50 = 0
			b_spk100 = 0
	prev_meta = meta
	prev = cur
	last_us = now
	if t > T_END:
		var n := float(frames)
		print("PROBE frames=%d fps_med=%.1f fps_p10=%.1f fps_p1=%.1f spikes50=%d spikes100=%d spike100_total_ms=%.0f focused=%.2f refocus=%d astray=%d occult=%d mad=%.2f screen_vis=%.2f waves=%d towers=%d" % [
			frames, 1000.0 / _pct(frame_ms, 0.5), 1000.0 / _pct(frame_ms, 0.9),
			1000.0 / _pct(frame_ms, 0.99), spk50, spk100, spk100_ms, focused_frames / n,
			refocus_n, astray_total, _occult(g), mad_frames / n, screen_vis_frames / n, waves_called, g.sim.state.towers.size()])
		return true
	return false


func _pct(a: Array[float], p: float) -> float:
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(b.size() * p), 0, b.size() - 1)] if b.size() > 0 else -1.0


func _occult(g: Game) -> int:
	var n := 0
	for tw in g.sim.state.towers:
		if tw.def.kind == "occult":
			n += 1
	return n
```
