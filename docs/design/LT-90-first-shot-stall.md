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

## Appendix A: throwaway patch and probe (probe worktree only)

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

## Measured after the fix (LT-90/S5)

Same seed 4242, `probe90.gd` rewritten for this slice (the appendix names it but does not hold the source; occult bot, `commands.*` API, refocus every 1 s, frame timeline, `first_fx_t` = first frame with a board effect). base = c3ad7ed, fix = 6b2b2fd, each from its own detached worktree, `--audio-driver Dummy --frame-stats --mute`, 4 runs per arm and sanity (interleaved), 30 s (sanity 0) / 42 s (sanity 100) probes. `focused` = window focused at `first_fx_t` and for >= 95% of frames. `gated` = 1-min load < 25 before launch (cap 30 min, after the first cap hit 3 min). `worst` = worst frame within +-0.2 s of `first_fx_t`. A first-shot stall of 450-1000 ms would also show in the "other" column (the frame ends after the stall), and none did. The 1-2.5 s frames at t = 1-5 s are window start-up and are outside this task.

Verdict: **fix: no frame over 100 ms at the first shot in 8/8 runs (worst 33-74 ms, 6/8 focused). The control did not reproduce the stall: base also shows 38-113 ms at the first shot (0 frames over 450 ms), so this measure does not tell the arms apart.** Under load 17-126 the 450-1000 ms stall seen in the diagnosis did not appear in base at all; the likely difference is run timing (start-up under load is 1-5 s here). Acceptance "base shows the stall again" is not met; needs the diagnosis-time conditions or a deterministic test control (the unit tests in 6b2b2fd).

| arm | sanity | run | focused | load before | gated | first_fx_t | worst near first shot (ms) | other frames >100 ms after t=1 (t:ms) | real / user / sys (s) |
|---|---|---|---|---|---|---|---|---|---|
| base | 0 | 1 | yes | 46.34 | no | 17.306 | 37.8 | 2.44:1809,23.96:111,24.07:111,24.75:122,25.17:137,25.80:111,25.99:121,28.39:121,29.36:115 | 36.93 / 16.74 / 6.88 |
| fix | 0 | 1 | yes | 31.60 | no | 17.589 | 53.9 | 2.70:1972,22.12:105,23.24:133,26.15:160,26.48:111,29.12:101 | 36.00 / 17.05 / 7.15 |
| base | 100 | 1 | yes | 22.49 | yes | 27.861 | 43.6 | 3.29:2502,3.44:100,30.34:181,32.27:161,39.38:135,39.61:125 | 52.40 / 21.82 / 9.60 |
| fix | 100 | 1 | yes | 21.88 | yes | 26.605 | 37.1 | 1.96:1450,16.38:132,17.01:139 | 46.64 / 20.26 / 9.75 |
| base | 0 | 2 | yes | 24.38 | yes | 16.893 | 43.1 | 1.99:1437,19.33:112,21.37:112,21.73:141,23.83:102,27.37:112,28.90:107,29.39:137 | 35.25 / 16.27 / 7.01 |
| fix | 0 | 2 | yes | 22.41 | yes | 17.156 | 33.3 | 2.30:1509 | 37.70 / 17.40 / 7.18 |
| base | 100 | 2 | yes | 21.83 | yes | 26.874 | 112.6 | 2.05:1539,17.00:105,17.17:117,17.77:150,18.51:201,18.90:123,19.42:104,19.67:107,19.95:117,20.39:114,20.78:104,23.23:121,25.57:120,27.07:102,27.73:107,29.31:138,29.80:102,30.32:135,31.25:108 | 46.06 / 17.53 / 8.25 |
| fix | 100 | 2 | no | 23.19 | yes | 26.774 | 45.2 | 2.20:1679 | 48.57 / 18.64 / 8.35 |
| base | 0 | 3 | yes | 23.16 | yes | 16.980 | 37.9 | 2.09:1561 | 35.41 / 14.96 / 6.28 |
| fix | 0 | 3 | yes | 19.34 | yes | 16.946 | 33.8 | 2.08:1426,22.77:110,22.88:106,24.61:126,25.26:147,25.58:108,27.14:132,27.66:154,29.52:105,29.84:111 | 38.64 / 16.92 / 6.93 |
| base | 100 | 3 | yes | 22.60 | yes | 26.798 | 52.2 | 2.20:1670,2.65:104,23.96:104,25.72:169,27.12:132,30.00:130,30.76:154,31.36:113,33.00:108,33.78:166 | 47.32 / 19.78 / 9.35 |
| fix | 100 | 3 | yes | 88.57 | no | 28.250 | 73.9 | 1.20:1203,1.40:193,4.02:2399,17.51:140,17.99:114,20.23:104,21.12:128,21.75:131,23.52:148,24.02:153,26.40:152,26.64:120,27.02:141,27.75:123,29.74:136,32.41:148,33.17:141,41.93:135 | 51.80 / 20.42 / 9.78 |
| base | 0 | 4 | no | 68.41 | no | 17.182 | 54.1 | 2.28:1548,14.33:112,20.17:136 | 36.39 / 15.98 / 6.40 |
| fix | 0 | 4 | yes | 21.94 | yes | 19.575 | 37.4 | 1.11:1106,4.69:3584,4.94:159,5.13:107,8.42:115,23.71:111,27.07:111,29.72:139,29.95:115 | 38.34 / 15.43 / 6.65 |
| base | 100 | 4 | yes | 126.10 | no | 27.497 | 62.4 | 2.92:2135,3.13:164,14.86:137,22.38:147,23.64:139,26.22:106,35.61:101,37.75:112,40.78:107 | 48.07 / 19.11 / 8.74 |
| fix | 100 | 4 | no | 36.65 | no | 28.485 | 53.0 | 1.06:1061,3.91:2845,4.44:100,19.80:125,35.07:143,36.95:119 | 51.84 / 18.25 / 7.52 |

Raw logs and script: `/private/tmp/claude-502/-Users-Valentin-Taiurskii-Projects-ClaudeProjects-lovecraft-td/820d9945-a8f9-4c4b-9388-aabe64243b23/scratchpad/lt90s5/` (summary.tsv, run_all.sh, probe90.gd; not committed).

## Measured from cold caches (LT-90/S6)

Question: did S1's runs warm a persistent Godot shader/pipeline cache that hid the stall from S5? **No. None of the Godot-specific caches holds anything a run could reuse, so a warm cache does not explain why S5 saw no stall.**

Evidence (read-only checks first, then one probe run with the caches cleared):

- `user://shader_cache` (`~/Library/Application Support/Godot/app_userdata/Lovecraft TD/shader_cache`): 14 `*ShaderGLES3/<hash>/` folders, **0 files**, all dated 2026-10-30. A run with the folder moved aside creates the same empty folders and no files, so the GL Compatibility renderer writes no shader binaries here.
- `$(getconf DARWIN_USER_CACHE_DIR)org.godotengine.godot` (the bundle id of `/Applications/Godot.app`): one empty `com.apple.metalfe/` folder, dated 2026-10-30.
- `~/Library/Caches/Godot`: only `editor_doc_cache-4.7.res` (2026-10-29).
- No file under `DARWIN_USER_CACHE_DIR` was written on 2026-11-19, the day S1 and S5 ran, except under `com.apple.SecurityAgent`. The shared `com.apple.metal` folder was last written 2026-11-04 (it was not touched). The driver is native Intel OpenGL (`OpenGL API 4.1 INTEL-24.5.8`), so a driver cache on disk is unlikely.

Cold run: base (c3ad7ed) from a fresh detached worktree, all three caches renamed to `*.lt90-aside`, `--seed=4242 --sanity=0 --frame-stats --mute --audio-driver Dummy --probe-secs=30`, gated on 1-min load < 25. A trap restored each cache (deleting what the run created, then renaming the original back), and a `stat` snapshot (name, ctime, mtime of every entry) before and after matched both times.

| try | focused | load before / after | gated | first_fx_t | worst near first shot (ms) | other frames >100 ms after t=1 (t:ms) | real / user / sys (s) |
|---|---|---|---|---|---|---|---|
| 1 | no (0.000, 27 refocus) | 23.49 / 20.83 | yes (waited 270 s) | 17.111 | 53.7 | 2.21:1603,25.89:185,29.92:111 | 36.10 / 15.08 / 6.08 |
| 2 | no (0.041, 24 refocus) | 20.20 / 45.01 | yes | 17.156 | 62.7 | 2.24:1665, 17.74-29.49: 26 frames of 102-236 ms, 23.94:1233 | 34.84 / 13.63 / 4.96 |

Neither run got focus (`window_move_to_foreground` failed; the desktop was probably in use), so by the acceptance rule they do not count as a measure of the stall. The cache question does not depend on focus: there is no cache to clear. The 16-run step 3 (cold caches per run) was not run, because clearing empty caches cannot make the base and fix arms differ. A control for F1 still needs either the S1 conditions (what differed there is still unknown: S1 ran on a probe worktree with `--ab-*` switches, and first shot came at t ~ 15.7 s rather than 17 s) or the deterministic unit-test control in 6b2b2fd.

Logs: `/private/tmp/claude-502/-Users-Valentin-Taiurskii-Projects-ClaudeProjects-lovecraft-td/820d9945-a8f9-4c4b-9388-aabe64243b23/scratchpad/lt90s6/` (cold1.sh, cold1_try1.summary, cold1.summary, before.snap/after.snap; not committed).

## Appendix B: probe90.gd source (S5/S6 reconstruction)

This is not the S1 probe, and with it the base stall did not show (S5/S6). The S1/S7 probe that reproduces the stall is in Appendix C.


Run from the project root: `godot --path . --audio-driver Dummy -s <path>/probe90.gd -- --seed=4242 --sanity=0 --frame-stats --mute --probe-secs=30`. `focused` in the tables = `fx_focused=true` and `focused_frac >= 0.95`.

```gdscript
extends SceneTree
## Throwaway LT-90/S5 probe (never committed). Occult bot, frame timeline, first board effect.
var main: Node
var t := 0.0
var started := false
var last_us := 0
var t0_us := 0
var frames := 0
var ts: Array[float] = []
var ms: Array[float] = []
var foc: Array[bool] = []
var first_fx_t := -1.0
var refocus_n := 0
var refocus_t := 0.0
var pin_t := 0.0
var idx := 0
var score_cache := {}
var T_END := 24.0
const ORDER := ["rifleman", "necronomicon_reader", "rifleman", "resonator", "harpooner", "elder_sign"]
const CAP_FLOOR := 70.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-secs="):
			T_END = float(a.split("=")[1])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


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
	g.commands.sell_relics()
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
		if cell.x < 0 or g.commands.build(id, cell) != Simulation.CommandResult.OK:
			break
		idx += 1
	g.commands.call_wave()


func _process(delta: float) -> bool:
	var g: Game = main.game
	if g == null:
		return false
	var now := Time.get_ticks_usec()
	if t0_us == 0:
		t0_us = now
	t = (now - t0_us) / 1e6
	if not started and t > 0.5:
		DisplayServer.window_move_to_foreground()
		started = true
		print("PROBE_START seed=%d win_px=%s focused=%s sanity=%.1f" % [g.run_seed,
			DisplayServer.window_get_size(), DisplayServer.window_is_focused(), g.sim.state.sanity])
	if started:
		_bot(g)
		refocus_t += delta
		if refocus_t > 1.0:
			refocus_t = 0.0
			if not DisplayServer.window_is_focused():
				DisplayServer.window_move_to_foreground()
				refocus_n += 1
		pin_t += delta
		if pin_t > 0.5:
			pin_t = 0.0
			g.sim.state.lighthouse_hp = 100000
		if first_fx_t < 0.0 and g.board.effects.size() > 0:
			first_fx_t = t
			print("FIRST_FX t=%.3f focused=%s" % [t, DisplayServer.window_is_focused()])
		if last_us > 0:
			frames += 1
			ts.append(t)
			ms.append((now - last_us) / 1000.0)
			foc.append(DisplayServer.window_is_focused())
	last_us = now
	if t > T_END:
		var fcount := 0
		var worst := 0.0
		var worst_t := -1.0
		var others := []
		var maxall := 0.0
		for i in ts.size():
			if foc[i]:
				fcount += 1
			if ts[i] < 1.0:
				continue
			if ms[i] > 100.0:
				var near: bool = first_fx_t >= 0.0 and absf(ts[i] - first_fx_t) <= 0.2
				if near:
					pass
				else:
					others.append("%.2f:%.0f" % [ts[i], ms[i]])
			if first_fx_t >= 0.0 and absf(ts[i] - first_fx_t) <= 0.2 and ms[i] > worst:
				worst = ms[i]
				worst_t = ts[i]
		var fx_focused := false
		for i in ts.size():
			if first_fx_t >= 0.0 and absf(ts[i] - first_fx_t) < 0.001:
				fx_focused = foc[i]
		print("PROBE frames=%d first_fx_t=%.3f worst_near_ms=%.1f worst_near_t=%.3f focused_frac=%.3f fx_focused=%s refocus=%d others=%s" % [
			frames, first_fx_t, worst, worst_t, fcount / maxf(1.0, float(frames)), fx_focused, refocus_n,
			",".join(others) if others.size() > 0 else "none"])
		return true
	return false
```

## Reproduction (LT-90/S7)

Question: why did S5/S6 not see the base stall, and does F1 remove it when it does show?
**The stall reproduces with the S1 probe (Appendix C) in 3/3 S1-setup runs, 2/2 focused unpatched
runs and 7/7 focused base runs in the A/B. The fix has no first-shot stall in 8/8 focused runs.
Strict acceptance (no frame over 100 ms within ±0.2 s) holds at sanity 0 (4/4), but not at
sanity 100 (2/4: 123 and 145 ms).** What hides the stall in the S5 probe is not settled; see
"What differs".

### What differs between S1 and S5

| | S1 / S7 | S5 / S6 |
|---|---|---|
| probe | Appendix C, copied into the worktree root (`-s probe90.gd`) | Appendix B, run from the scratchpad path |
| probe `t` | sum of process `delta` (capped ~0.15 s per frame) | wall clock from the first `_process` |
| bot start / first foreground | at `t > 0.5` of summed delta, after the long startup frames; the bot runs after the refocus check | at 0.5 s wall clock, so during startup; towers built and wave called at sim tick 4 (S5 log) |
| render instrumentation | `viewport_set_measure_render_time(root, true)` (GL timer queries every frame), `frame_pre_draw`/`frame_post_draw` handlers, a `Tail` node with process priority 100000 | none |
| board.gd | S1: the `--ab-*` patch (Appendix A); S7 also ran an unpatched twin | unpatched |
| launch | `/Applications/Godot.app/.../Godot --path . --audio-driver Dummy -s probe90.gd -- --seed=4242 --sanity=0 --frame-stats --mute --probe-secs=20` | same flags through `godot` (a symlink to the same binary), `--probe-secs=30/42` |
| worktree | detached, `.godot` cloned (`cp -c -R`) then `--headless --import` | detached (own worktrees) |
| `first_fx_t` | 15.6-15.8 s (s0), 25.3-25.5 s (s100), in summed-delta time | 16.9-19.6 / 26.6-28.5 s, in wall-clock time |

Ruled out in S7: the board patch (the unpatched twin stalls: 472, 610 ms focused; 618, 1349,
418 ms in 3 unfocused tries), the launch flags and the binary (same). That leaves the probe:
the render-time measurement and draw signals, or the startup timing of the bot and the
foreground call. S7 did not bisect these (the brief said to stop at the A/B).

### Runs

One background script (`scratchpad/lt90s7/run.sh`, `summary.txt`, per-run logs). Each run
was gated on 1-min load < 25 (30 min cap; every run was gated, waits of 0-1365 s). An
unfocused run (focused share < 0.95) was rerun up to 2 times. `near` = worst frame within
±0.2 s of `first_fx_t` (`<100` = none over 100 ms). Load is the 1-min load before/after the run.
`real/user/sys` from `/usr/bin/time -p`.

Phase 1, S1 setup (sanity 0, c3ad7ed):

| run | focused | near ms | load | real / user / sys |
|---|---|---|---|---|
| exact r1 (try 1; try 0 unfocused 0.72: 767) | 1.00 | 500 | 21.7 / 22.6 | 32.1 / 14.1 / 5.3 |
| raw r1 | 1.00 | 472 | 22.6 / 27.4 | 30.9 / 15.0 / 5.4 |
| exact r2 (try 1; try 0 unfocused 0.90: 1839) | 1.00 | 813 | 23.5 / 27.5 | 30.3 / 14.2 / 5.2 |
| raw r2 | 0.95 | 610 | 23.5 / 28.8 | 28.7 / 13.3 / 5.0 |
| exact r3 | 1.00 | 842 | 24.0 / 24.3 | 26.5 / 11.7 / 4.7 |
| raw r3 (3 tries, never focused) | 0.00 | 618 / 1349 / 418 | 21.2-22.7 / 16.6-26.8 | 27.0-30.9 / 11.9-13.6 / 4.6-4.9 |

Phase 2, base (exact S1 worktree, c3ad7ed + Appendix A patch) vs fix (6b2b2fd plus only inert
timing: the `_draw` wrapper and the `first_delta` meta), interleaved, focused runs shown:

| sanity | run | base near ms | fix near ms (frame split) | load base / fix (before) |
|---|---|---|---|---|
| 0 | 1 | 647 (try 1) | <100 (max 148 at +4.2 s) | 21.8 / 22.1 |
| 0 | 2 | 347 | <100 | 20.1 / 22.1 |
| 0 | 3 | 648 (try 1) | <100 | 22.5 / 18.2 |
| 0 | 4 | 695 | <100 (try 1) | 18.2 / 15.5 |
| 100 | 1 | 438 | <100 | 18.6 / 15.1 |
| 100 | 2 | never focused in 3 tries: 367 / 926 / 1333 | 145 at -0.09 s (draw 87, gap 55; try 1, load 81.8 after, 12 other frames of 103-211 ms in the run) | 21.3-21.8 / 21.8 |
| 100 | 3 | 581 | 123 at the first-effect frame (draw 47, gap 72) | 15.4 / 16.9 |
| 100 | 4 | 272 | <100 | 13.3 / 11.9 |

Base: a stall at the first shot in 7/7 focused runs (272-695 ms), all in `draw` like S1. Fix:
no frame over 150 ms near the first shot in 8/8 focused runs. The two 123/145 ms frames at
sanity 100 are not render stalls: their `draw` is 47-87 ms and most of the time is in `gap`
(the time between the end of process and `frame_pre_draw`). Both runs also have 103-211 ms
frames elsewhere (load 17-82). Real/user/sys per run: 25.6-44.8 / 11.4-20.0 / 4.3-8.6 s.
Startup frames (0.5-2.2 s) are in every run of both arms.

Verdict: F1 removes the first-shot stall wherever the stall reproduces. The acceptance as
written (no frame over 100 ms within ±0.2 s) is met at sanity 0 and missed by background
frames at sanity 100. Raise it to 200 ms, or require a 4/4 rerun at load < 15.

## Appendix C: probe90.gd source (S1/S7 version, reproduces the stall)

Copy it into the worktree root. Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --audio-driver Dummy -s probe90.gd -- --seed=4242 --sanity=<0|100> --frame-stats --mute --probe-secs=<20|34>`. It reads `p90_*` Engine meta from the Appendix A patch when present (defaults otherwise).

```gdscript
extends SceneTree
## Throwaway LT-90 first-shot probe (trimmed LT-62 appendix B occult bot).
var main: Node
var t := 0.0
var started := false
var pin_t := 0.0
var last_us := 0
var idx := 0
var score_cache := {}
var frames := 0
var n100 := 0
var max_ms := 0.0
var max_t := 0.0
var first_fx_t := -1.0
var focused := 0
var after_spike := 0
var pre_us := 0
var post_us := 0
var refocus_t := 0.0
var refocus_n := 0
const ORDER := ["rifleman", "necronomicon_reader", "rifleman", "resonator", "harpooner", "elder_sign"]
const CAP_FLOOR := 70.0
var T_END := 35.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-secs="):
			T_END = float(a.split("=")[1])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	RenderingServer.frame_pre_draw.connect(func() -> void: pre_us = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: post_us = Time.get_ticks_usec())
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
	g.commands.sell_relics()
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
		if cell.x < 0 or g.commands.build(id, cell) != Simulation.CommandResult.OK:
			break
		idx += 1
	g.commands.call_wave()


func _process(delta: float) -> bool:
	t += delta
	var g: Game = main.game
	if g == null:
		return false
	var now := Time.get_ticks_usec()
	var vp := root.get_viewport_rid()
	if not started and t > 0.5:
		DisplayServer.window_move_to_foreground()
		started = true
		print("PROBE_START win_px=%s focused=%s sanity=%.1f first_delta=%.3f" % [
			DisplayServer.window_get_size(), DisplayServer.window_is_focused(),
			g.sim.state.sanity, float(Engine.get_meta("p90_first_delta", -1.0))])
	if started:
		refocus_t += delta
		if refocus_t > 1.0:
			refocus_t = 0.0
			if not DisplayServer.window_is_focused():
				DisplayServer.window_move_to_foreground()
				refocus_n += 1
		_bot(g)
		pin_t += delta
		if pin_t > 0.5:
			pin_t = 0.0
			g.sim.state.lighthouse_hp = 100000
	var fx: int = g.board.effects.size()
	if fx > 0 and first_fx_t < 0.0:
		first_fx_t = t
		print("FIRST_FX t=%.2f fx=%d" % [t, fx])
	if after_spike > 0:
		after_spike -= 1
		print("  next t=%.2f ms=%.1f %s rcpu=%.1f rgpu=%.1f" % [t, (now - last_us) / 1000.0, _split(now),
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp)])
	if started and t > 1.0 and last_us > 0:
		var ms := (now - last_us) / 1000.0
		frames += 1
		if DisplayServer.window_is_focused():
			focused += 1
		if ms > max_ms:
			max_ms = ms
			max_t = t
		if ms > 100.0:
			n100 += 1
			after_spike = 2
			print("SPIKE t=%.2f ms=%.1f %s rcpu=%.1f rgpu=%.1f fx=%d draws=%d enemies=%d towers=%d" % [
				t, ms, _split(now), RenderingServer.viewport_get_measured_render_time_cpu(vp),
				RenderingServer.viewport_get_measured_render_time_gpu(vp), fx,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				g.sim.state.enemies.size(), g.sim.state.towers.size()])
	last_us = now
	if t > T_END:
		print("PROBE frames=%d max_ms=%.1f max_t=%.2f n100=%d first_fx_t=%.2f warm_frames=%d warm_last_t=%.3f first_delta=%.3f focused=%.2f refocus=%d" % [
			frames, max_ms, max_t, n100, first_fx_t, int(Engine.get_meta("p90_warm_frames", 0)),
			float(Engine.get_meta("p90_warm_last_t", -1.0)), float(Engine.get_meta("p90_first_delta", -1.0)),
			focused / maxf(1.0, float(frames)), refocus_n])
		return true
	return false


## The previous frame split: process (probe start -> tail node), pre-draw gap, render
## (frame_pre_draw -> frame_post_draw, incl. swap), and wait until this frame.
func _split(now: int) -> String:
	var tl := int(Engine.get_meta("tail_us", 0))
	return "proc=%.1f gap=%.1f draw=%.1f wait=%.1f bdraw=%.1f" % [(tl - last_us) / 1000.0,
		(pre_us - tl) / 1000.0, (post_us - pre_us) / 1000.0, (now - post_us) / 1000.0,
		float(Engine.get_meta("p90_bdraw_us", 0)) / 1000.0]
```

## Owner decision (LT-90/S7)

- Acceptance: "Принять: критерий — рывок отрисовки (Recommended)". The fix is accepted on the render-stall criterion: no frame over 150 ms at the first shot (fix 8/8, base 7/7 stalled at 272-695 ms). The 123/145 ms frames at sanity 100 have a draw step of 47-87 ms and are not render stalls.
- S5 discrepancy: "Не выяснять, записать в доке (Recommended)". The three probe differences listed above are recorded and not bisected.
