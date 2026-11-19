# LT-90: the first-shot stall survives the LT-62 P1 warm-up (diagnosis, slice S1)

Status: diagnosis only. No production code changed. Probe edits ran in a throwaway detached
worktree (`lovecraft-td-wt-LT-90-probe`, removed after the slice); the patch and probe are
summarised in the appendix.

Build: branch `fix/LT-90-first-shot-stall` at c3ad7ed (0.6.0), Godot 4.7.2, GL Compatibility,
boot-fit window 2390x1344 px, `--seed=4242 --sanity=0 --frame-stats --mute --audio-driver Dummy`.

## Verdict

1. **The cause is the one LT-62 named: the first draw of a thick `draw_line` (the rifleman
   tracer's 2-px dash).** Drawing the tracer without that line removes the stall. Drawing only
   that line keeps it.
2. **P1 fails because of *when* it draws, not *what* it draws.** The warm-up runs while
   `_time < 0.5`. `_time` sums the engine's process `delta`, and Godot caps `delta` at about
   0.15 s (measured `first_delta=0.150` in every run). The first frames of a run are 0.7-2.2 s
   long while the window is created, fitted and brought to the front. So "0.5 s of effects time"
   is only 7-13 frames, all of them inside the startup frames, before the window is up. Draws
   in those frames do not pay the first-use cost. The same 0.5 s warm-up started at
   `_time = 3 s` does pay it (a 365-599 ms frame at t = 3.16 s), and then the first shot is clean.
3. The cost is spent inside `RenderingServer` drawing (from `frame_pre_draw` to
   `frame_post_draw`: 436-990 ms in the stall frame), but **not** in the viewport's measured
   render CPU time (22-28 ms). It sits after the canvas submission, in the end-of-frame
   flush/swap, which matches a GL driver that compiles a pipeline lazily on first real use.
   Scripts take 2-5 ms in that frame (`proc`), and the board's own `_draw` takes 2.6 ms.
4. Not audio (no stream plays on SHOT; Dummy driver plus `--mute` in every run), not a scene
   instantiation (SHOT only appends a Dictionary to `board.effects`), not the muzzle
   `draw_circle`, and not sanity (S17 had the same stall at sanity 100).

## How it was measured

- Probe `probe90.gd` (SceneTree script, appendix) is the S17 occult bot trimmed to 20 s
  (the first shot comes at t ~ 15.7 s at sanity 0). It brings the window to the front at
  t = 0.5 s and again every 1 s while unfocused. A `Tail` node with process priority 100000
  marks the end of process. `frame_pre_draw`/`frame_post_draw` timestamps split every
  frame over 100 ms into `proc` (scripts), `draw` (RenderingServer draw incl. swap) and `wait`.
  It also prints `viewport_get_measured_render_time_cpu/gpu`, the board `_draw` time, the
  first frame with a board effect (`first_fx_t`), how many frames ran the warm-up, and the
  first `delta`.
- Arms are throwaway `--ab-*` switches in `scenes/board.gd` (appendix). Each arm ran 3 times,
  round-robin. Before each run the script waited until the 1-min load average was < 40
  (at most 600 s). The machine was shared with sibling agents (load 100-265 when the slice
  started), so a load gate of 25 was not reachable. The stall (450-1000 ms) stands well above
  the background noise (100-220 ms frames at this load).
- Machine state: `uptime` load 1-min 19-56 before the runs and 24-118 after them (per-run
  numbers below). `/usr/bin/time -p` per run: real 28-37 s, user 11.7-16.4 s, sys 4.3-5.7 s,
  so the process was mostly busy rendering, not waiting.

## Evidence: per run (sanity 0, worst frame over 100 ms near the first shot)

`stall` = the frame that draws the first board effect (`first_fx_t` 15.50-15.74 s);
`-` = no frame over 100 ms there. `draw` = pre->post draw ms of that frame.

| arm | what it changes | r1 | r2 | r3 | load before/after (r1, r2, r3) |
|---|---|---|---|---|---|
| base | P1 as shipped (0.5 s warm-up) | 791 (draw 780) | 699 (681) | 455 (436) | 38.8/43.3, 36.7/36.4, 35.7/26.7 |
| nowarm | no warm-up at all | 536 (518) | 1008 (991) | 460 (446) | 33.0/56.4, 36.4/49.6, 34.0/24.0 |
| warmtracer | P1 plus the tracer's exact circle + 2-px line at board coords | 572 (556) | 570 (552) | 537 (517) | 39.3/43.8, 38.6/30.5, 24.0/32.4 |
| notracer | tracer effect not drawn | - | - | - | 36.3/43.7, 36.4/37.1, 26.7/32.7 |
| tracerline | tracer = one 2-px `draw_line` only | 952 (944) | 730 (713) | 500 (484) | 37.9/29.0, 37.1/65.1, 32.7/36.5 |
| tracercircle | tracer = muzzle `draw_circle` only | - | - | - | 29.0/33.0, 37.0/39.9, 36.5/34.0 |
| warm3 | P1 warm-up for 3 s | - | - | - | 39.6/65.4, 30.5/23.5, 32.4/60.3 |
| warmfrom3 | P1 warm-up for 0.5 s from `_time` 3 s | - (stall moved to t=3.15: 599) | - (t=3.16: 365) | - (t=3.16: 503) | 43.2/67.9, 23.5/19.0, 34.1/44.3 |
| warm30 | P1 warm-up for 30 s (whole run) | - | - | - | 39.9/117.5, 19.0/35.7, 35.7/31.4 |

Same-frame detail for the stall (base r1): `ms=791.3 draw=779.5`; the dry run with the
full split: `ms=956.7 proc=4.5 gap=5.2 draw=946.6 wait=0.3 bdraw=2.6 rcpu=22.3 rgpu=0.0`.

Every run has two startup frames before play (game spike log, sim tick 4: 0.66-1.15 s; tick
15-16: 1.2-2.2 s, the frame where the window comes to the front). They are in every arm,
including `nowarm`, so they are not caused by the warm-up. The `warm3`/`warm30` runs show no
separate frame for the thick-line cost. It most likely folds into the tick-15/16 startup frame
(2.0-2.2 s there against 1.6-1.7 s in base/nowarm), but at this load that difference is not
conclusive.

### Control: the arms differ where they should

- `warm_frames` per run: base 8-9, warmtracer 7-9, nowarm 0, warm3 93-189, warm30 615-1010,
  warmfrom3 12-14 frames, ending at `warm_last_t` 0.42-0.50 / 0 / 2.98-3.00 / 19.97-19.98 /
  3.48 s. So `nowarm` really drew nothing, and P1 really drew in 7-9 frames.
- `warmfrom3` gives a 365-599 ms frame at exactly `_time` 3.0 s in 3/3 runs. The warm-up
  draw pays the first-use cost when the window is up, and it does not when it runs in the
  first 0.5 s.
- `notracer` and `tracercircle` give no stall at the first shot, while `tracerline` does, in
  3/3 runs each.

## What was ruled out, and how

- First audio stream: SHOT starts no audio (`relic_tokens.gd`/`whisper_audio.gd` are the
  only players). Every run used `--audio-driver Dummy --mute`, and the stall stays.
- First scene instantiation: `Board.on_event(SHOT)` only appends a Dictionary. `notracer`
  keeps that path (the effect is created and ticked, `first_fx_t` set) and has no stall.
- Script time: `proc` 2-5 ms and board `_draw` 2.6 ms in the stall frame.
- Canvas command submission / shader bind in the viewport pass: measured viewport render CPU
  22-28 ms in the stall frame and the frame after.
- Muzzle `draw_circle`: `tracercircle` has no stall.
- Warm-up primitive shape: `warmtracer` (the tracer's exact primitives at real board
  coordinates) fails exactly like P1. The timing matters, not the shape or the place.
- Sanity: covered by S17 (same stall at sanity 100). This slice ran sanity 0 only, because
  the first shot comes 10 s sooner there.

## Fix proposals

**F1 (recommended): keep the warm-up draws on until a real thick line has been drawn.**
Replace the `_time < WARMUP_SECONDS` gate with a flag `_thick_line_warm` that `_draw_tracer`
(and any other thick-line effect) sets once it has drawn its line. Until then, `_draw_warmup`
runs every frame. Equivalent measured arm: `warm30` (no first-shot stall in 3/3).
- Benefit: does not depend on startup timing, the window state or the `delta` cap. Once the
  window is up, the cost is paid in the first presented frame, during startup or the quiet
  build phase. Stops by itself.
- Risk: three invisible primitives per frame until the first shot (+1 batch, negligible next
  to ~750 draw calls). If the first presented frame comes during play, the cost lands there
  instead, the same as today at worst. A flag tied to the tracer misses other first-use
  primitives (harpoon polyline, wave polygon) if a different tower fires first; set it from
  `_draw_warmup` callers per primitive, or use F2.

**F2: draw the warm-up for a wall-clock window counted from the first focused frame.**
Count real frames or `Time.get_ticks_msec()` from the first frame where
`get_window().has_focus()` (or is visible), and warm for ~1 s / 30 frames after that.
Measured analogue: `warmfrom3` / `warm3` (clean first shot in 3/3).
- Benefit: bounded cost. Covers every primitive `_draw_warmup` lists, whichever tower
  fires first.
- Risk: depends on focus/visibility reporting. A window that never gets focus (started
  behind another app) never starts the countdown unless there is a fallback. More state
  and harder to test than F1.

**F3: always draw the warm-up (drop the gate).**
- Benefit: one-line change, no state, nothing to get wrong. `warm30` is this in practice.
- Risk: a permanent invisible draw each frame (tiny). It reads as dead code to a later
  reader unless the comment says why, and it stays in every frame for the whole run.

## Edit map for the code slice

Line numbers at c3ad7ed.

- `scenes/board.gd`
  - consts `WARMUP_SECONDS` / `WARMUP_ALPHA` and their comment: lines 79-81 (F1/F3: drop or
    rename `WARMUP_SECONDS`; F2: replace with a frame/ms count).
  - `_draw()` lines 541-567: the gate at 544-545.
  - `_draw_warmup()` and its doc comment, lines 570-578: fix the comment's claim ("paid while
    the board is quiet") to state the real condition.
  - `tick_effects()` lines 469-479: holds `_time`, the clock P1 wrongly used (no change for F1).
  - `_draw_tracer()` lines 913-937 (F1: set the flag after the `draw_line` at 925); likewise
    `_draw_harpoon()` 940+, `_draw_astray()` 881-890 if the flag is per primitive.
- `tests/lt62_fps_test.gd`
  - header comment lines 1-5 ("runs in the first WARMUP_SECONDS only").
  - `test_warmup_draw_stops_after_half_second_of_effects_time` lines 106-115 pins the wrong
    behaviour; replace it.
  - `test_warmup_draw_runs_in_the_first_half_second` 98-103 and
    `test_board_without_a_game_draws_no_warmup` 118-122 stay valid (rename the first).

## How a test pins the fix, and the control

Headless tests cannot see a GL driver stall, so the test pins the gate, and the measure
slice pins the effect.

- Unit (F1): a `SpyBoard` that ticks `_time` well past 0.5 s (e.g. `tick_effects(5.0)`) still
  calls `_draw_warmup` on every draw. After a tracer effect has been drawn (append a tracer
  fx with `ttl`, draw one frame), it stops.
  Control revert: restore `if _time < WARMUP_SECONDS:` in `_draw()`. The "still warms after
  5 s of effects time" assertion must fail.
- Unit (F2): after N frames without focus it does not count down; after focus it warms for
  the window and then stops. Control: the same `_time` gate revert.
- Measure slice (the real control): `probe90.gd` from the appendix, `base` (c3ad7ed) vs the
  fix, 3 runs each at sanity 0 and 3 at sanity 100. Pass: no frame over 150 ms within
  ±0.2 s of `first_fx_t` in 6/6 fix runs, while base shows the 450-1000 ms frame in each.
  The `notracer` arm is the cheap observation that tells the arms apart.

## Owner questions

1. Which fix: F1 (warm until the first thick line), F2 (warm for ~1 s after the window is
   focused) or F3 (always draw the invisible warm-up)?
2. The two startup frames (~1 s and ~1.5-2 s, before the first wave, in every run) are
   window creation and the window coming to the front. They are outside this task. Track
   them, or accept them as loading time?

## Appendix: throwaway patch and probe (probe worktree only)

`scenes/board.gd` switches (all read from `OS.get_cmdline_user_args()`):

- `_draw()` was renamed `_draw_real()` and wrapped by a `_draw()` that stores its time in
  `Engine` meta `p90_bdraw_us`.
- Warm-up gate: `_time >= warmfrom and _time < warmfrom + warm`, with `--ab-warm=<s>`
  (default 0.5), `--ab-warmfrom=<s>` (default 0) and `--ab-nowarm`. It counts
  `p90_warm_frames` and `p90_warm_last_t`. `--ab-warmtracer` adds
  `draw_circle(Vector2(40,40), cells_to_px(0.12))` + `draw_line(Vector2(40,40), Vector2(60,50), 2.0)`
  at alpha 0.01.
- `_draw_effects()` "tracer": `--ab-notracer` skips it, `--ab-tracerline` draws one
  `draw_line(from, end, TRACER_COLOR, 2.0)`, `--ab-tracercircle` draws only the muzzle circle.
- `tick_effects()` stores the first `delta` in `p90_first_delta`.

`probe90.gd` = LT-62 appendix B with these changes: no section/event accumulators; the
`commands.*` API (LT-78); refocus every 1 s; `frame_pre_draw`/`frame_post_draw` timestamps
and the `proc/gap/draw/wait/bdraw` split; `FIRST_FX` line; summary
`PROBE frames max_ms max_t n100 first_fx_t warm_frames warm_last_t first_delta focused refocus`.
Run: `godot --path . --audio-driver Dummy -s probe90.gd -- --seed=4242 --sanity=0 --frame-stats --mute --probe-secs=20 [--ab-...]`.
