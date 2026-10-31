# LT-38: frame rate as sanity falls (diagnosis, slice S1)

Status: diagnosis only. No production code changed. The throwaway instrumentation was
reverted with `git checkout`, so the worktree is clean apart from this note.

## Verdict in one paragraph

With the scene, wave, seed, towers and window held fixed (windowed, 1280x720 points =
2560x1440 px on Retina, GL Compatibility), **sanity does not change the frame rate by more
than about 10 %, and no single sanity effect, when disabled, moves the frame rate beyond
the run-to-run noise.** The large swings seen in the orchestrator probe (31 -> 19 fps,
"62 -> 109 ms process") and in this slice (45 fps vs 145 fps for the same arm) come from
two places other than sanity:
1. **The metric.** `Performance.TIME_PROCESS` is the *maximum* frame process time over the
   last second, and in Godot 4 it includes the render/draw step. It is not "CPU script
   time per frame". The measured GDScript work (all `_process`, all `_draw`) is 3-5 ms per
   frame, against a TIME_PROCESS median of 20-80 ms in the same runs.
2. **The machine/window state.** The same arm ran at ~20 ms/frame in one period and
   ~7 ms/frame in another (round 1, rows 13-18 below), with the 1-min load *higher* in the
   fast period. The difference lies entirely in render + present (`flush_render_swap`),
   not in scripts. Vsync on vs off made no difference (round 2), so it is not vsync
   pacing. Its cause is outside the game (GPU/compositor contention or window
   occlusion/focus; round 2 windows were unfocused). It explains the contradictory "95 fps
   at sanity 0" run.

## How it was measured

- Probe: `/private/tmp/claude-502/-Users-Valentin-Taiurskii-Projects-ClaudeProjects/38a0365f-d40b-48d3-891c-d7ac9facb436/scratchpad/perf/probe.gd`
  (based on the old fps.gd). It starts `main.tscn` with `--seed=1`, builds 2 towers next to
  the path, calls waves as soon as allowed, and every 0.5 s pins gold, lighthouse HP
  (100000, so the run never ends) and sanity (`debug_set_sanity`). It samples from 6 s to
  26 s (~600-2900 frames).
- Per frame it records: the wall-clock frame interval (`frame_ms`), TIME_PROCESS,
  RenderingServer render CPU time (`rcpu`; GPU time is unsupported in Compatibility and
  reads 0), draw calls, live enemies, and two segments: node `_process` (frame start ->
  a tail node with `process_priority = 100000`) and the remainder (message-queue flush with
  every `_draw`, render, present).
- Throwaway timing patch (`patch.py` in the same folder, reverted): accumulators around
  `Game.advance` sections, `Board._draw` / `_draw_enemies` / `_draw_effects`,
  `SanityBar._draw`, `SanityFx._process`, `Lighting._process`. A/B switches:
  `--ab-noscreen` (screen distortion rect hidden), `--ab-nojitter` (HUD jitter material
  not assigned), `--ab-notorn` (plain sanity fill), `--ab-noenemyfx` (enemy flicker and
  madness tint/outline off), `--ab-nophantom`, `--ab-nofakes` (hallucination spawning off,
  sim-side), `all` (every switch), `--ab-nolights` (Lighting node hidden).
- Runners: `run.sh` (round 1) and `run2.sh` (round 2, waits until the 1-min load is < 20,
  adds `--disable-vsync`). Raw lines: `summary.txt`, `summary2.txt` in the same folder.

## Measurements

`fps` = median of TIME_FPS; `frame` = median wall-clock frame interval; `proc max/s` =
median of TIME_PROCESS; `scripts` = node `_process` + `Board._draw` + `SanityBar._draw`
(ms per frame); `r+swap` = flush + render + present (ms/frame, mean); `rcpu` = render CPU.
Load = 1-min load average before / after the arm. `time -p` = user / sys / real (s).

### Round 1 (vsync on, window focus not recorded)

| # | sanity / arm | load before / after | user / sys / real | fps | frame ms | proc max/s | scripts | r+swap | rcpu | draws | enemies |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 100 | 5.98 / 5.73 | 14.40 / 4.89 / 28.95 | 45 | 22.0 | 29.7 | 4.2 | 21.5 | 6.9 | 715 | 5.8 |
| 2 | 30 | 5.73 / 5.66 | 10.89 / 3.59 / 29.14 | 47 | 21.7 | 28.1 | 3.0 | 20.1 | 4.5 | 723 | 8.7 |
| 3 | 0 | 5.66 / 5.19 | 14.33 / 4.66 / 30.72 | 58 | 15.8 | 29.3 | 3.3 | 17.0 | 4.8 | 743 | 11.5 |
| 4 | 0 noscreen | 5.19 / 5.11 | 14.92 / 5.03 / 29.78 | 51 | 16.6 | 29.6 | 4.0 | 19.0 | 5.9 | 741 | 11.2 |
| 5 | 0 nojitter | 5.11 / 10.47 | 15.88 / 5.37 / 30.25 | 47 | 19.0 | 29.6 | 4.5 | 19.2 | 6.8 | 742 | 11.0 |
| 6 | 0 notorn | 10.47 / 10.23 | 17.18 / 5.50 / 32.72 | 50 | 17.6 | 29.6 | 4.3 | 19.3 | 6.9 | 742 | 11.2 |
| 7 | 0 noenemyfx | 10.23 / 8.60 | 16.68 / 5.26 / 31.67 | 48 | 19.7 | 31.1 | 4.4 | 20.4 | 6.5 | 728 | 11.4 |
| 8 | 0 nophantom | 8.60 / 7.49 | 14.87 / 4.89 / 30.54 | 50 | 17.4 | 29.6 | 4.0 | 19.5 | 5.7 | 743 | 11.3 |
| 9 | 0 nofakes | 7.49 / 11.50 | 14.82 / 4.75 / 30.84 | 49 | 17.0 | 29.7 | 3.8 | 19.1 | 5.5 | 736 | 9.4 |
| 10 | 0 all | 11.50 / 8.53 | 11.92 / 3.71 / 30.29 | 49 | 21.5 | 27.4 | 2.9 | 20.0 | 4.2 | 723 | 9.4 |
| 11 | 100 | 8.53 / 17.31 | 13.58 / 4.46 / 29.45 | 48 | 21.6 | 29.4 | 3.6 | 20.0 | 5.5 | 715 | 5.8 |
| 12 | 30 | 17.31 / 18.07 | 14.06 / 4.73 / 29.77 | 48 | 20.6 | 29.3 | 3.8 | 20.2 | 6.0 | 723 | 8.5 |
| 13 | 0 | 18.07 / 14.97 | 13.64 / 4.42 / 30.78 | 52 | 21.2 | 29.2 | 3.4 | 18.6 | 4.8 | 743 | 11.4 |
| 14 | 100 noscreen | 14.97 / 11.82 | 17.30 / 1.99 / 31.19 | **145** | **6.9** | 5.7 | 3.1 | **6.6** | 8.1 | 712 | 5.8 |
| 15 | 0 noscreen | 11.82 / **33.83** | 18.68 / 1.38 / 29.87 | 111 | 7.4 | 45.4 | 8.5 | 9.6 | 5.3 | 707 | 10.8 |
| 16 | 100 nolights | **33.83 / 61.59** | 16.79 / 5.08 / 32.51 | 44 | 20.2 | 48.3 | 5.7 | 21.6 | 8.7 | 714 | 5.8 |
| 17 | 0 nolights | **61.59 / 94.21** | 17.52 / 3.09 / 34.62 | 84 | 8.2 | 72.9 | 8.6 | 12.1 | 15.4 | 734 | 12.1 |
| 18 | 0 all | **94.21 / 136.14** | 18.13 / 1.43 / 34.39 | 99 | 7.0 | 63.0 | 8.5 | 9.7 | 16.8 | 705 | 9.4 |

Rows 15-18 ran with the load above 20 and are not trusted for A/B (re-run in round 2).
Row 14 vs row 4 (same switch, quiet load) shows the external mode change: 6.6 vs 19.0 ms of
render + present for the same work. Note that `sys` fell from ~5 s to ~1.4-2 s in the fast
period (rows 14, 15, 18), which is consistent with less time spent in the GL driver/present
path. The fast/slow mode does not follow sanity, the A/B switch, or the load.

### Round 2 (load-gated < 20 at start, window unfocused at start and end)

| # | sanity / arm | load before / after | user / sys / real | fps | frame ms | proc max/s | scripts | r+swap | rcpu | draws | enemies |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 100 (gate timed out) | **321.69 / 276.34** | 15.77 / 5.42 / 36.41 | 33 | 27.7 | 79.0 | 6.6 | 31.4 | 11.6 | 714 | 5.7 |
| 2 | 0 | 17.75 / **32.89** | 19.25 / 7.01 / 33.06 | 50 | 18.8 | 28.8 | 5.7 | 19.5 | 9.1 | 742 | 11.2 |
| 3 | 100 noscreen | 18.22 / 14.31 | 18.61 / 6.09 / 30.64 | 61 | 16.1 | 19.9 | 4.2 | 16.2 | 7.5 | 715 | 5.8 |
| 4 | 0 noscreen | 14.31 / 12.09 | 19.38 / 6.53 / 30.24 | 62 | 16.5 | 20.1 | 4.6 | 16.3 | 7.5 | 741 | 11.3 |
| 5 | 100 novsync | 12.09 / 11.15 | 19.63 / 6.34 / 31.21 | 63 | 16.0 | 19.7 | 4.0 | 15.5 | 7.2 | 715 | 5.8 |
| 6 | 30 novsync | 18.99 / 15.47 | 18.76 / 6.35 / 31.08 | 61 | 16.5 | 20.6 | 4.3 | 16.7 | 7.0 | 723 | 8.7 |
| 7 | 0 novsync | 11.15 / 14.08 | 19.36 / 6.56 / 30.95 | 56 | 17.7 | 25.4 | 5.0 | 17.6 | 8.2 | 743 | 11.3 |
| 8 | 0 novsync + noscreen | 14.08 / **21.30** | 19.85 / 6.63 / 32.18 | 56 | 17.5 | 30.2 | 5.2 | 18.0 | 8.4 | 741 | 11.0 |
| 9 | 0 novsync + all | 18.36 / **26.08** | 18.89 / 6.31 / 30.25 | 54 | 17.9 | 26.8 | 5.4 | 18.7 | 9.1 | 723 | 9.4 |
| 10 | 0 novsync + nojitter | 15.47 / 13.24 | 18.29 / 6.28 / 29.93 | 59 | 16.6 | 20.8 | 4.5 | 16.2 | 7.3 | 743 | 11.3 |

The 15-min load average stayed at 68-155 throughout round 2 (another workload had pushed
the 1-min load to ~320 just before), so round 2 is quieter than round 1's slow period but
not idle. Row 1 is invalid.

### Per-function cost at sanity 0 vs 100 (round 2, rows 7 vs 5, ms per frame)

| function | sanity 100 | sanity 0 | note |
|---|---|---|---|
| `Board._draw` (whole) | 3.50 | 4.32 | map + towers + enemies + effects; redrawn every frame |
| of which `_draw_enemies` | ~0.2 | ~0.45 | scales with live enemies (5.8 -> 11.3) |
| `SanityBar._draw` | 0.08-0.10 | 0.09-0.12 | torn fill is not measurable |
| `SanityFx._process` | 0.02-0.03 | 0.02-0.03 | shader params only |
| `Game.advance`: sim steps | 0.03-0.14 | 0.12-0.18 | incl. hallucination fakes |
| `Hud.refresh` | 0.17-0.23 | 0.18-0.25 | |
| `Lighting._process` | 0.04-0.06 | 0.04-0.06 | |
| node `_process` total | 0.50 | 0.67 | |

## Cause, with evidence

1. **No sanity effect is a frame-rate cost on this machine.** Every A/B at sanity 0 lands
   within the noise of its own baseline: round 1 rows 4-10 give 47-51 fps against 52-58 for
   the baseline (rows 3, 13), and round 2 rows 8-10 give 54-59 fps against 56 (row 7).
   The arms do differ where they should, which shows the switches work: `nofakes` and
   `all` drop live enemies from 11.3 to 9.4, `noenemyfx` and `all` drop draw calls by
   15-20, and `all` cuts `Board._draw` from 3.3 to 2.2 ms in round 1. They cut *work*, but
   not *frame time*, because that work is a small share of the frame. The screen
   distortion pass (`noscreen`) changes neither fps nor render CPU at the same
   load/mode (round 1 rows 3 vs 4; round 2 rows 7 vs 8). Its GPU cost cannot be read in
   Compatibility (`rgpu` = 0), and with vsync off the frame does not shorten, so the GPU is
   not the limit here either.
2. **What remains of a sanity effect is about 1-2 ms/frame, and it comes from game
   state, not the effects.** At sanity 0 (madness) there are twice as many live enemies
   (fakes, +20 % speed, astray shots), so `Board._draw` and `_draw_enemies` cost ~0.8 ms
   more and render CPU ~1 ms more (round 2: 63 -> 56 fps, 16.0 -> 17.7 ms).
3. **The frame is dominated by render + present, ~15-20 ms in the "slow mode" and ~7 ms in
   the "fast mode",** for 2560x1440 px and ~715-743 draw calls a frame. Script work is
   3-5 ms. The slow/fast mode is external to the game (see the verdict) and is the most
   likely explanation of the orchestrator's falling numbers. Its probe ran at load ~300,
   which means a contended machine whose state changed between arms, plus the misread
   TIME_PROCESS metric.
4. **The playtest feel is not explained by measured frame time.** Unmeasured hypothesis
   (for the owner): at low sanity the stepped effects update at 9-13 Hz (enemy flicker
   `flicker_rate` 13/s, HUD jitter `rate` 11/s, torn bar `glitch_rate` 9/s), and the
   screen wobble moves the whole board. A board where many things jump about 10 times a
   second can read as "10-20 fps" even when the game renders at 50-60 fps.

## Fix proposals

**P1 (recommended first): fix the measurement before fixing code.** Add a frame-time
overlay or debug print based on the wall-clock frame interval (median and p90), not
TIME_PROCESS. Then the owner reruns sanity 100 / 0 on a quiet machine with the window
focused, and compares by eye with `--ab-*`-style switches.
- Benefit: tells "the game drops frames" apart from "the effects look choppy" on the
  owner's own hardware. That is exactly the question this slice could not settle,
  because of the external mode change.
- Risk: it needs a playtest round with the owner. A debug-only overlay adds code that must
  stay out of release builds (gate it like `--sanity`).

**P2: cache the static map layer** (a separate child CanvasItem that draws the map once
and redraws only on map change or build/sell). Every frame now re-issues the map draw
commands (two `draw_rect` per cell plus a string).
- Benefit: removes most of the ~3 ms `Board._draw` GDScript cost and many draw primitives
  per frame at every sanity level. The largest script-side saving available.
- Risk: it is not sanity-specific, so it does not answer the playtest complaint by
  itself. Draw order must be kept (the phantom, auras, towers and enemies stay above the
  map; lights and fog must still affect the new node: same parent, so the same
  CanvasModulate/light mask). It needs a render check (screenshot before/after).

**P3 (owner decision, design): make the low-sanity effects read as smooth.** Raise or
interpolate the step rates (for example, flicker that eases between steps instead of
jumping, a jitter rate of 20-30/s with a smaller amplitude, or a lower screen wobble
amplitude), if P1 shows that frames are fine and the feel comes from the effects.
- Benefit: targets the likely cause of "sluggish" at no performance cost.
- Risk: it changes the agreed look of the madness effects (GDD §5.3/§9). It is a design
  change, so the owner decides it. It is unmeasured until P1 runs.

**Not recommended:** removing or simplifying the screen shader, the HUD jitter material,
the torn bar or the fakes for performance. None of them moved the frame time in any A/B.

## Edit map for the code slice

Line numbers are from `release-0.2.1` (the worktree HEAD, 78fb66a).

| proposal | file | function / item | lines | change |
|---|---|---|---|---|
| P1 | `scenes/game.gd` | `setup` (debug-arg block) | 35-45 | read a debug flag (e.g. `--frame-stats`), debug builds only |
| P1 | `scenes/game.gd` | `advance` | 112-125 | feed the frame interval into a small ring buffer (median/p90) |
| P1 | `ui/hud.gd` | `_ready` / `refresh` | 33-110 / 112-142 | optional debug label with frame median/p90 ms |
| P2 | `scenes/board.gd` | `_draw` | 344-360 | drop the `_draw_map(s.map)` call |
| P2 | `scenes/board.gd` | `_draw_map` | 362-379 | move into a child `MapLayer` node (first child, so it draws below); redraw on build/sell/map change |
| P2 | `scenes/board.gd` | `_ready`, `on_event` | 96-99, 122-143 | create the layer; `queue_redraw` it on build/sell events |
| P2 | `scenes/game.gd` | `_after_command` | 188-195 | also redraw the map layer (tower cells) |
| P3 | `scenes/board.gd` | `flicker_rate`, `_flicker_dip` | 77, 337-342 | rate / easing between steps |
| P3 | `shaders/ui_jitter.gdshader` | `rate`, `vertex` | 6, 13-19 | rate/amplitude, or smooth between steps |
| P3 | `ui/sanity_bar.gd` | `glitch_rate`, `_draw_torn_fill` | 29, 130-150 | rate |
| P3 | `scenes/sanity_fx.gd` | `max_distortion_px` | 24 | wobble amplitude |

## What was ruled out, and how

- Whisper audio: ruled out before this slice (the stream is built once).
- `SanityFx` shader parameter pushes: 0.02-0.03 ms/frame (timed).
- The torn sanity bar: `SanityBar._draw` is 0.1 ms; `notorn` gives no fps change.
- HUD jitter material: `nojitter` gives no fps change (round 1: 47 vs 52-58; round 2: 59 vs 56).
- Enemy flicker / madness outline: `noenemyfx` cuts draw calls by 15 and `_draw_enemies` by
  0.1-0.2 ms, with no fps change.
- Hallucination fakes: `nofakes` cuts live enemies from 11.3 to 9.4, with no fps change.
- Screen distortion pass: `noscreen` gives no fps or render CPU change at the same load and
  mode. Its GPU cost is not readable in Compatibility, and vsync-off frames do not shorten
  without it.
- Vsync pacing: `--disable-vsync` gives the same frame times (round 2, rows 3-5).
- Not settled: what causes the external slow/fast render mode (focus/occlusion vs GPU
  contention). Round 2 recorded `window_is_focused() = false`; round 1 did not record it.
