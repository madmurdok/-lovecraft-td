# LT-40: smoother low-sanity effects (design, slice S1)

Status: design only. No production code changed; the capture tweak was runtime-only (probe
script setting `@export`s and a shader uniform), so there is nothing to revert. Base:
`release-0.12.0` 8042850. Source: LT-38 P3 (`docs/design/LT-38-fps-diagnosis.md`).

## 1. Go / no-go

**Go, as a look change, not a performance fix.** LT-62 settled the frame rate: after its
fixes (LT-62/S17, focused boot-fit window, load 4.6-7.9) madness runs at 41-44 fps median
and sanity 100 at 44-46 fps; the madness gap is 2-3 fps, all sanity effects together cost
~4 fps (most of it the screen pass), and HUD jitter, flicker and the torn bar are each
inside the noise. So smoothing will not raise fps. It is still worth doing because the
"sluggish" read comes from what is drawn, not from fps:

- At ~40 fps a 13/s step holds for 3, 3, then 4 frames (irregular), and at the 18-33 fps
  the owner saw it holds 1-3 frames: the stepped effects beat against the frame rate.
- At sanity 0 an enemy's alpha jumps by more than 0.3 in one frame on 8.5 % of frames at
  60 fps and 12.7 % at 40 fps, up to 0.85 (table in section 3). With many enemies on screen
  something on the board jumps almost every frame, which reads as stutter.
- The screen wobble bends the whole board grid by up to 4 px (12 px in a pulse), so the
  path and towers swim; that reads as an unsteady frame, not as madness.

Cost of the proposed changes: one extra hash per enemy per frame (GDScript) and per vertex
(jitter shader). No new draw calls. This changes the agreed madness look (GDD §5.3 table,
§9 "jitter at Whispers", "flicker on all enemies", "distorted sanity bar"); **the owner
judges it by eye** before the code slice ships the values.

## 2. Per effect: now, where set, proposal

Rates and amplitudes are not in `data/` (no sanity look values in `data/sanity.json`):
they are `@export`s on the presentation scripts and one shader uniform default.

### Enemy flicker (and the phantom path)

- Now: `Board.flicker_rate = 13.0` (`scenes/board.gd:72`), step function
  `Board.flicker_dip` (173-178): per enemy id and step a hash; 28 % of steps dip fully
  (`1.0`), the rest dip `h * 0.35`. Strength `SanityFx.max_flicker = 0.85`
  (`scenes/sanity_fx.gd:32`), applied in `SanityFx._apply` (155-157: 0.55-1.0 of max over
  Fraying, max in Madness). Used by `EntityLayer._draw_enemies`
  (`scenes/board/entity_layer.gd:285, 301-306`: alpha `*= 1 - dip`; a ghost double when
  `dip > 0.5`) and `PhantomLayer._draw` (`scenes/board/phantom_layer.gd:24-25`, key -1).
- Proposal **F1 (recommended): ease between steps.** `flicker_dip` returns
  `lerp(dip(step), dip(step + 1), smoothstep(frac))` with the same hash, rate 13, same
  `max_flicker` 0.85. Same average dip and ghost share, no one-frame jumps.
- Alternative F2: eased at 20/s with `max_flicker` 0.65 (busier, softer).
- **Not recommended: higher rate + lower amplitude with steps** (e.g. 30/s, 0.5): at 30/s
  the step is shorter than a frame at <= 30 fps, so every frame jumps (19.9 % of frames
  jump > 0.3 at 60 fps, 29.9 % at 40 fps, worse than now), and a dip of 0.5 never passes
  the `> 0.5` ghost threshold, so the "torn frame" double silently disappears.

### HUD jitter (Whispers and below)

- Now: shader `shaders/ui_jitter.gdshader`: `rate = 11.0` (line 6, uniform default, not set
  from GDScript), `duty = 0.45` (7), `vertex()` (13-19): a new random offset of up to
  `jitter_px` per axis each step on 45 % of steps, else 0. Amplitude
  `SanityFx.max_ui_jitter_px = 2.5` (`sanity_fx.gd:31`), applied in `_apply` (158-159):
  `2.5 * (0.6 + 0.4 * level)` = 1.5-2.5 px (base px, x stretch on screen). One material
  shared by 11 HUD controls (`ui/hud.gd:205-210`). A control can jump up to ~7 px in one
  frame (corner to corner).
- Proposal **J1 (recommended): ease between steps in the shader.** Offset
  `mix(off(s), off(s + 1), smoothstep(fract(TIME * rate)))`, with `jump` eased the same
  way; rate 11, `max_ui_jitter_px` 2.5. Peak motion drops to ~1.4 px per frame at 60 fps
  (smoothstep slope 1.5 x 11/60 x 5 px). Reads as a sway, not a twitch.
- Alternative J2: keep the steps, halve the amplitude (`max_ui_jitter_px` 1.25, rate 11):
  still a twitch, half as far. Cheapest (one number).
- Make `rate` a `SanityFx` `@export` (`ui_jitter_rate := 11.0`) set in `_apply`, so the
  value is tunable and testable like the others.

### Torn sanity bar (Fraying, Madness)

- Now: `SanityBar.glitch_rate = 9.0`, `edge_wobble_px = 9.0`, `tear_px = 3.0`
  (`ui/sanity_bar.gd:27-29`); `_draw_torn_fill` (144-164) reseeds the RNG per step, so
  slices, edge, highlights and stripes all change at once 9 times a second (x1.6 in
  Madness: edge up to 14 px, tears 5 px). Runs only while torn (`set_distorted`).
- Proposal **T1 (recommended): keep it stepped (it is a glitch, in a 190x26 widget off the
  board), halve the size:** `edge_wobble_px` 4.5, `tear_px` 1.5, rate 9. The bar stays
  "distorted" (GDD §9) but stops flashing at the edge of vision.
- Alternative T2: ease the edge position only (lerp between two seeded edges), keep
  slices/stripes stepped. More code, keeps the full size.

### Screen wobble (Whispers and below)

- Now: not stepped. `shaders/sanity_screen.gdshader` `fragment()` (20-28): a continuous
  sine wave, 0.2-0.5 Hz, low spatial frequency (sin(uv.y * 23) is ~3.7 periods over the
  screen) plus a 0.6 x high-frequency term; peak offset `0.5 * 1.6 * distortion` =
  4 base px at Madness (`max_distortion_px = 5.0`, `sanity_fx.gd:28`, `_apply` 163), x3 for
  0.8 s after a threshold change (`pulse`). The low-frequency term moves whole board
  regions together: the grid bends and towers/path swim.
- Proposal **W1 (recommended): keep the board centre still.** Multiply the wave by an
  edge mask, `amount *= smoothstep(0.25, 0.9, edge)` (the `edge` the vignette already
  computes; move its computation above the wave): the board middle, where play happens,
  stays put; the rim wobbles under the vignette. Same `max_distortion_px`.
- Alternative W2: halve `max_distortion_px` to 2.5 (one number; whole board still moves,
  half as far).
- Alternative W3: drop the low-frequency terms (23 / 17), keep the high-frequency ripple
  (61 / 47) as a heat-haze shimmer at the same amplitude.
- `COPY_MARGIN` (`sanity_fx.gd:20-23`) is derived from the peak offset; W1/W2/W3 only
  lower it, so 32 px stays safe. Its comment must be updated if the formula changes.

## 3. Captures and numbers

**Frame sequences were not feasible.** The probe (`-s` script, `--fixed-fps 60`,
`--resolution 1200x675`, `-- --mute --sanity=0 --seed=4242`) ran while the machine was at
load 33-67 and the agent's window was not on top: macOS presented only 54 of 1526
iterations (`Engine.get_frames_drawn()`; the HUD label shows "FPS 201", LT-62's occluded
"fast mode"). Consecutive grabs were ~0.28 s of game time apart, so they cannot show
stepping. Single frames are valid:

- current: `.../scratchpad/lt40/A-full-f0.png`
- runtime tweak (rates 30/24/30, `max_flicker` 0.5, jitter 1.25 px, bar wobble/tear
  halved, `max_distortion_px` 2.5): `.../scratchpad/lt40/B-full-f0.png` (the board grid is
  visibly less bent)

(scratchpad = `/private/tmp/claude-502/-Users-Valentin-Taiurskii-Projects-ClaudeProjects-lovecraft-td/814c3663-e64c-4d70-99e4-5838e69d71ce/scratchpad`;
probe `lt40/probe.gd`, logs `lt40/run3.log`.) The owner's eye check is best done live after
the code slice, with the values as `@export`s so they can be flipped in the inspector.

Exact per-frame numbers instead, from the shipped `flicker_dip` formula (Python mirror,
`lt40/curves.py`, 40 enemy ids x 20 s), one enemy's alpha change between frames:

| variant | fps | mean abs | p95 | max | frames > 0.3 | ghost frames |
|---|---|---|---|---|---|---|
| now: 13/s stepped, 0.85 | 60 | 0.071 | 0.725 | 0.850 | 8.5 % | 26.9 % |
| F1: 13/s eased, 0.85 | 60 | 0.071 | 0.236 | 0.272 | 0.0 % | 26.3 % |
| F2: 20/s eased, 0.65 | 60 | 0.084 | 0.282 | 0.313 | 2.1 % | 21.6 % |
| 30/s stepped, 0.50 | 60 | 0.098 | 0.468 | 0.500 | 19.9 % | 0.0 % |
| now | 40 | 0.107 | 0.766 | 0.850 | 12.7 % | 26.9 % |
| F1 | 40 | 0.105 | 0.347 | 0.399 | 13.6 % | 26.2 % |
| F2 | 40 | 0.126 | 0.315 | 0.325 | 11.7 % | 17.3 % |
| 30/s stepped, 0.50 | 40 | 0.147 | 0.479 | 0.500 | 29.9 % | 0.0 % |

F1 keeps the look's average (mean change and ghost share unchanged) and cuts the worst
one-frame jump from 0.85 to 0.27-0.40.

## 4. Edit map for the code slice

| item | file | function / line range | change |
|---|---|---|---|
| F1 | `scenes/board.gd` | `flicker_dip` 171-178 | split the hash into `_flicker_step_dip(step, key)`; return the smoothstep lerp of step and step + 1; keep key = id only |
| F | `scenes/board.gd` | `flicker_rate` 72 | value per owner choice |
| F | `scenes/sanity_fx.gd` | `max_flicker` 32 | value per owner choice (F2: 0.65) |
| F | `scenes/board/entity_layer.gd` | `_draw_enemies` 301-306 | read only: ghost at `dip > 0.5` stays; check it still fires |
| J1 | `shaders/ui_jitter.gdshader` | `vertex` 13-19 | eased offset and jump between `s` and `s + 1` |
| J | `scenes/sanity_fx.gd` | exports 27-34, `_apply` 151-159 | new `@export var ui_jitter_rate := 11.0`, set `"rate"` in `_apply`; `max_ui_jitter_px` per choice |
| T1 | `ui/sanity_bar.gd` | exports 27-29 | `edge_wobble_px` 4.5, `tear_px` 1.5 (or T2 in `_draw_torn_fill` 144-164) |
| W1 | `shaders/sanity_screen.gdshader` | `fragment` 20-31 | compute `edge` before the wave, `amount *= smoothstep(0.25, 0.9, edge)` (W2: `max_distortion_px` 2.5 in `sanity_fx.gd:28`) |
| W | `scenes/sanity_fx.gd` | `COPY_MARGIN` comment 20-23 | update the peak-offset formula if the wave changes |

Tests to pin (`scripts/test.sh tests/<file>_test.gd`):

- `tests/sanity_feedback_test.gd` (or a new `tests/sanity_fx_smooth_test.gd`):
  - the jitter material's `rate` equals `SanityFx.ui_jitter_rate` after `_apply`, and
    follows a changed export (params read from the exports, not shader defaults);
  - `flicker_dip` is continuous: over 1 s sampled at 1/240 s, no two neighbours differ by
    more than a bound (e.g. 0.1) for any key; at step boundaries (`k / flicker_rate`) it
    equals the step value (so the hashed look is kept). Control: the stepped version fails
    the continuity assertion;
  - `flicker_dip` changes with `flicker_rate` (read from the export).
- Render isolation (`tests/render_isolation_test.gd`, LT-12 §7 b13): the source scan
  already forbids fake checks in `scenes/`; add one behaviour test that a real and a fake
  enemy with the same id-equivalent key get the same `flicker_dip` series, i.e. the dip
  depends only on `(time, key)`. Keep `flicker_dip`'s signature `(key: int)`.
- `tests/sanity_fx_screen_test.gd`: W1 adds an assertion on the shader source (like
  `test_shader_does_not_blend_and_gates_the_madness_grade`, 130) that the wave is scaled
  by the edge mask; W2 is covered by `tests/window_scale_test.gd:125` (distortion =
  `max_distortion_px * level * scale`).
- `SanityBar`: exports read back in `_draw_torn_fill` (edge offset bounded by
  `edge_wobble_px * 1.6`) if T2 is chosen; T1 is a value change only.

Controls (6-8): revert F1 (continuity test fails), drop the `rate` set in `_apply`
(rate test fails), revert W1 in the shader (source test fails).
