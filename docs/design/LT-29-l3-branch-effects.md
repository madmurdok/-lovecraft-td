# LT-29 — L3 branch effects: crits, gangster bursts, bleed, pull, armor strip (design note)

Status: draft for owner review · branch `feat/LT-29-l3-branch-effects`. Line numbers are
`release-0.3.0` at `594d24b` (LT-46 merge).

Source: LT-24 design found five L3 effects that parse but do nothing (Marksman crits,
Militia second shooter, Barbed bleed, Chain harpoon pull, Corrupted Seal armor strip). Owner,
LT-46 review Q1: "Гангстеры-ветка, Прожектор (Recommended)" — Rifleman branch b becomes
**Gangsters** with `burst_targets` (3-target bursts) instead of Militia's `shooters`. LT-46
Q4 "Лимит HP по уровню (Recommended)" sets the pattern for displacement caps (§2.3).

---

## 0. What exists today and what this task adds

**Today**
- `TowerDef.Level.EFFECTS` (`sim/defs/tower_def.gd:92-96`) accepts `crit_chance`,
  `crit_multiplier`, `shooters`, `bleed_dps`, `bleed_seconds`, `pull_cells`, `strip_armor`;
  all seven are in `Level.PENDING` (101-102). `ui/tower_info.gd` appends " (coming soon)" to
  their lines (`is_pending`, 69-70); bots skip a branch whose `has_pending()` is true
  (`tools/bot_runs.gd` `_next_upgrade`, 281-305), so Marksman, Barbed (mundane/mixed bots) and
  Corrupted Seal (madness bot) are never bought.
- `_fire_towers` (`sim/core/simulation.gd:1001-1062`): one target by `_pick_target`
  (1064-1073, LT-31), line shot (`pierce`) or blast (`aoe_radius`), one `_roll_miss()` per
  shot on COMBAT (mundane, Fraying/Madness), SHOT emitted **before** `apply_damage` (tests
  pin SHOT → DIED: `tests/occult_tower_test.gd:392`, `tests/tower_targeting_test.gd:179`).
- `apply_damage` (157-173) is the one armor rule: `max(0, amount − max(0, armor +
  armor_bonus)) × damage_taken_mult`. `SimEnemy.armor_bonus` exists, is reset every tick
  (`sim_enemy.gd:32-36`) and nothing writes it yet.
- `SimEnemy.status` and `SimTower.status` exist as empty dictionaries; nothing ticks them.
- `_apply_auras` (935-968) builds slow/vuln for every `damage <= 0` tower with those
  effects, `maxf` over overlapping auras; line 960 is the "strip_armor not wired" comment.
- Render: `Board.enemy_markers` (`scenes/board.gd:156-163`) knows `"slow"`, `"vuln"` only.
  **Correction to the task text:** LT-25 does *not* draw bleed or pull yet; its Decision Q1
  ("Нет, их добавит задача L3") reserved the channels and left the markers to this task
  (LT-25 §2 and "Note for the backlog task", §4). LT-29 adds them (§4).
- LT-30 (lighthouse beam) is designed (`feat/LT-30-lighthouse-beam`,
  `docs/design/LT-30-beam-addendum.md` §3.1) but has no code yet: lit mundane towers get
  cooldown `ticks(fire_interval × 0.8)` and skip `_roll_miss()`; lit occult towers get
  `power_mult` 0.7 on damage and on aura slow/vuln.

**This task adds** the five effects in the sim from config, their render markers, the
Militia → Gangsters data change, the removal of every "(coming soon)", and bots that may buy
these branches. It builds LT-46 pieces P5 (push back), P6 (enemy status timers) and P12
(burst at N targets), plus a crit roll that later towers may reuse.

---

## 1. Effects: rules, keys, numbers, tick slot

Tick slots are `Simulation.step()` (80-119): 1 reset, 2 effect systems, 3 move, 4 leak,
5 fire, 6 sanity, 7 spawn, 8 compact, 9 outcome.

### 1.1 Marksman crits (Rifleman a)

Keys (existing): `crit_chance 0.2`, `crit_multiplier 2`. Numbers unchanged (range 5, dmg 18,
0.7 s).

Rule: a shot that hits (not a miss, `hits` not empty) and whose level has `crit_chance > 0`
rolls once on a **new RNG stream `CRIT`** (appended to `SimRng.Stream`, `sim_rng.gd:8`):
`randf() < crit_chance` → crit. A crit multiplies the shot's per-hit damage by
`crit_multiplier` for every enemy the shot hits; then `apply_damage` applies armor and
`damage_taken_mult` as usual. SHOT gains `"crit": true` (key absent on a normal shot).

- No roll on a miss, so crits never shift the miss sequence; a separate stream keeps COMBAT
  (misses) identical between a run with and without crit towers, which keeps A/B bot runs
  and seeded tests comparable. Slot 5, after the miss roll.
- Numbers: 18 → 36 on a crit; vs Shoggoth armor 5: 13 normal, 31 crit (crit before armor).
  Expected DPS 18 × 1.2 / 0.7 = 30.9 (panel keeps 25.7 "DPS" plus the crit line, §4.2).

### 1.2 Gangsters bursts (Rifleman b, replaces Militia)

Data (`data/towers.json`, LT-46 §2.2): branch b becomes
`{"name": "Gangsters", "role": "Tommy guns, 3 targets", "upgrade_cost": 80, "range": 3,
"damage": 7, "fire_interval": 0.2, "effects": {"burst_targets": 3}}`.
`shooters` leaves `Level.EFFECTS` (no level uses it; an old config with it is then rejected
as an unknown field). New key `burst_targets` (integer ≥ 1 by meaning; schema max INF like
the others; 0 or absent = single target).

Rule (P12): each shot is one ordinary single shot, every `fire_interval` (0.2 s = 6 ticks).
- **Ranked set:** `_ranked_targets(t, candidates, n)` returns up to `n = burst_targets`
  candidates in the order the tower's `target_priority` ranks them (LT-31: "first" = least
  route left, "strongest" = hp, "fastest" = units this tick; every tie → lower id).
  `_pick_target` becomes `_ranked_targets(t, c, 1)[0]`, so one ranking rule serves both.
- **Round robin:** `SimTower.burst_index` (persistent int, starts 0). With `m` = ranked size
  this shot: target = `ranked[burst_index % m]`; then `burst_index = (burst_index % m + 1) % m`.
  Three in range: r0, r1, r2, r0, …; two: r0, r1, r0, r1; one: always r0. When an enemy
  dies or leaves range the ranking simply shrinks next shot; no target is "locked".
- **Misses:** each bullet is a mundane shot and rolls `_roll_miss()` itself (15 % each in
  Fraying). A miss spends that bullet's cooldown and moves the round robin on (the gangster
  swung to the next man anyway); kills give `regen.mundane_kill` each.
- **Beam (LT-30):** lit → cooldown `ticks(0.2 × 0.8) = ticks(0.16) = 5` ticks, i.e. +20 %
  rate, not +25 % (whole ticks, see Q3); no miss roll while lit.
- Madness: mundane, unaffected (no ×2, no astray).
- Numbers: 35 DPS spread; armor 2 → 25, armor 5 → 10. SHOT unchanged (one per bullet), so
  the render draws tracers as today.

### 1.3 Barbed bleed (Harpooner a)

Keys (existing): `bleed_dps 6`, `bleed_seconds 3`. The harpoon line damage (24, pierce)
is unchanged.

Rule (P6):
- **Apply (slot 5):** after the shot's damage, every enemy in `hits` that is still live gets
  bleed: `status.bleed_ticks = max(left, ticks(bleed_seconds))` (90), `status.bleed_dps =
  max(old, bleed_dps)`, `status.bleed_source = t.def.id` (of the stronger bleed; tie → the
  newest), and, only if it was not bleeding, `status.bleed_pulse = 30` (ticks to the next
  pulse). Fakes bleed exactly like real enemies (render isolation).
- **Refresh, never stack:** a second Barbed hit (same or another tower) restarts the
  duration and keeps the higher dps; two Barbed towers do not double the bleed. Continuous
  harpoon cadence (1.5 s) keeps a 6 DPS bleed running.
- **Pulse (slot 2, new `_tick_statuses()` after `_apply_madness_buff`):** for each live
  bleeding enemy, id order: `bleed_ticks −= 1`, `bleed_pulse −= 1`; when `bleed_pulse` hits 0
  → `apply_damage(e.id, bleed_dps, bleed_source)` and `bleed_pulse = 30`; when `bleed_ticks`
  hits 0 the bleed keys are erased. One application = 3 pulses = 18 = dps × seconds.
  Slot 2 is after the auras and madness buff, so the pulse gets this tick's
  `damage_taken_mult` (Elder Sign ×1.5, madness ×0.37) and `armor_bonus` (strip, §1.5).
- **Armor:** the pulse goes through `apply_damage`, so armor applies once per pulse
  (Q1 decides; recommended as written). Hybrid (armor 2): 4/s; Shoggoth (5): 1/s.
- **Kill credit:** `bleed_source` is the tower def id, so `_on_enemy_killed` (811-820) pays
  mundane-kill sanity for a bleed kill like for a harpoon kill; DIED `source` is that id.

### 1.4 Chain harpoon pull (Harpooner b)

Keys: existing `pull_cells 1.5`; **new** `pull_max_hp 500`, `pull_immune_seconds 3`
(Q2; both in `Level.EFFECTS`, max INF). The harpoon line damage is unchanged.

Rule (P5 + P6), slot 5, after the shot's damage:
- **Who:** the shot's primary target only (role "Pulls target back"; the chain is one line
  from that enemy to the tower, LT-25 §2), if it is still live, `max_hp ≤ pull_max_hp`
  (`0` or absent = no cap) and has no `status.pull_immune_ticks`. Q4 asks primary vs all.
- **Move:** `_push_back(e, cells)`: `distance = max(0, distance − roundi(cells ×
  UNITS_PER_CELL))`, `prev_distance = distance` (no backwards slide through a tick, LT-25
  §4 note). Along the enemy's own route: path walkers back along the path, flyers back along
  their straight S → L line. Distance only decreases, so `_leak` and `_check_outcome` are
  unaffected.
- **Immunity:** `status.pull_immune_ticks = ticks(pull_immune_seconds)` (90), ticked down in
  `_tick_statuses()` and erased at 0. Any Chain harpoon respects it (no lock by two towers).
- **SHOT:** a level with `pull_cells > 0` adds `"pulled": [ids]` (0 or 1 id). Because SHOT
  is emitted before damage (pinned order SHOT → DIED), the pull is decided after damage and
  written into the same `shot` dictionary already passed to `_emit` (events are drained only
  after `step()`); a comment says so at the write.
- **Fakes:** pulled like real ones (a fake's `max_hp` is its def's).
- Numbers: without immunity one Chain harpoon in Lucid would hold a cultist in place
  (1.0 c/s × 1.5 s = 1.5 cells walked, 1.5 pulled). With 3 s immunity: cultist net 1.5 cells
  per 3 s (50 % speed), Hybrid 44 %, Deep One 69 %; Shoggoth (3600 > 500) never pulled.
- **Silver Key (LT-51) interaction:** banish uses its own `banish_immune_ticks`; the two
  timers are independent, so a pull never wastes a later 4-8-cell banish and a banish never
  blocks a pull. `pull_max_hp` 500 equals banish L1/L2/Pure's `banish_max_hp` (LT-46 Q4: a cap
  per level), so the player learns one "≤ 500 HP" threshold. LT-51 reuses `_push_back` and
  the status ticking.

### 1.5 Corrupted Seal armor strip (Elder Sign b)

Key (existing): `strip_armor 1`. Its sanity reserve (30) is LT-23's, already applied.

Rule: an aura modifier, same path and lifetime as slow and vuln. In `_apply_auras`, for an
enemy inside one or more aura towers, `strip = max over those towers of strip_armor`;
`e.armor_bonus −= strip` for this tick (reset in slot 1). Aura-only: it ends the tick the
enemy leaves the ring, no lingering status. Two Seals do not stack (max, like slow/vuln).
- With Elder Sign exposure (both from the same Seal): `max(0, dmg − max(0, armor − strip))
  × 1.5`. Rifleman 10 vs Shoggoth: 5 → 6 × 1.5 = 9. Armor never goes below 0 (existing
  `maxf(0.0, …)` in `apply_damage`): stripping a cultist does nothing.
- Bleed pulses (slot 2, after auras) and every tower shot (slot 5) see the strip.
- Beam (LT-30, when it lands): lit occult aura → `strip × power_mult` (0.7 armor) like slow;
  LT-30's `_apply_auras` edit multiplies all three.
- Detection: `_apply_auras` also treats a `damage <= 0` level with `strip_armor` as an aura
  (today the Seal qualifies through `slow` anyway).

---

## 2. Stacking rules (one table)

| Pair | Rule |
|---|---|
| crit × madness ×2 / lit occult ×0.7 | multiply, all before armor: `damage × power_mult (lit occult) × madness ×2 (madness_affected) × crit`. No shipped tower has both (Marksman is mundane); the order is fixed for later occult crits. |
| crit × beam (mundane) | lit Marksman: cooldown ×0.8 (17 ticks), no misses; crit chance and multiplier unchanged |
| crit × Elder Sign / madness enemy buff | `damage_taken_mult` after armor, as for any hit |
| burst × target priority | the mode ranks; round robin over the top `burst_targets` (§1.2) |
| burst × miss / beam | per bullet; lit 5 ticks, no misses (Q3 on +20 %) |
| bleed × armor | armor per pulse (Q1) |
| bleed × bleed | refresh duration, max dps, no stack |
| bleed × strip / vuln | pulse in slot 2 after auras: both apply |
| pull × pull | 3 s immunity, any tower |
| pull × banish (LT-51) | independent immunities |
| pull × HP | `pull_max_hp` 500 (Q2) |
| pull × flyer | along its straight line |
| strip × strip | max, not sum |
| strip × Elder Sign vuln | armor first, then ×1.5 |
| strip × beam | ×0.7 when the Seal is lit |

---

## 3. Fit with the roster (LT-46)

- §2.1 Rifleman b: Militia → Gangsters per Q1 (done here, data + sim). Harpooner a/b,
  Elder Sign b, Rifleman a wired as above; Necronomicon branches need nothing.
- §4 pieces LT-29 builds first, so LT-47..52 reuse them:
  - **P5** `_push_back(e, cells)` (pull; LT-51 banish).
  - **P6** `_tick_statuses()` in slot 2 over `SimEnemy.status` with integer `*_ticks` keys
    erased at 0 (bleed, `pull_immune_ticks`; LT-47 b reuses bleed through a shared
    `_apply_bleed(e, dps, seconds, source)`; LT-51 adds `banish_immune_ticks`; LT-49 C
    would add `root_ticks`).
  - **P12** `_ranked_targets` + `SimTower.burst_index`. LT-51's `banish_targets` reuses
    `_ranked_targets` for its "up to N by priority".
  - New: crit roll on `Stream.CRIT` (no roster tower uses it yet).
- **P1 (the `_fire_towers` split) stays LT-47's.** LT-29 goes first in `_fire_towers` (§5
  sequencing) and keeps the function in its current shape, adding only: the ranked pick, the
  crit roll, and one call `_on_hit_effects(t, s, target, hits, shot)` after the damage loop
  (bleed + pull). That call is the seam P1 later moves into `_shot_hits`/per-hit code.
- **LT-30 overlap:** LT-30 edits `_fire_towers` (lit miss skip, cooldown mult, power mult)
  and `_apply_auras`. Whichever lands second rebases: the lit miss skip wraps the same
  per-bullet `_roll_miss()`; `power_mult` applies to `strip_armor` too. `SimRng.Stream`
  append order: if LT-30 appends a stream first, `CRIT` goes after it.

---

## 4. Render and UI

### 4.1 What LT-25's markers need from the sim (boundary: LT-33)

All read-only, through public state and drained events; nothing reads `is_fake`; all
effects apply to fakes identically, so `tests/render_isolation_test.gd` is unaffected.

| Marker | Sim source | Render (`scenes/board.gd`) |
|---|---|---|
| bleed | `SimEnemy.status.get("bleed_ticks", 0) > 0` (state, per tick) | `enemy_markers` (156-163) adds `"bleed"`; `_draw_markers` draws LT-25 §2's reserved look: 2 red drops below the body, 0.5 s loop, enemy alpha |
| pull | SHOT `pulled: [ids]` | `_shot_fx` (180-217) for a harpoon with `pulled`: adds `chain_ids`; `_draw_harpoon` (562-590) draws the one-shot dashed steel chain from each pulled enemy's drawn position to the tower, 0.3 s |
| crit | SHOT `crit: true` | `_shot_fx`: `fx.crit`; `_draw_tracer` (539-561) draws the hit spark at 2× ray length (no new colour) |
| strip | `armor_bonus < 0` (state) | **no marker**: the Seal's ring and the vuln outline already mark the zone; adding a third body marker for −1 armor is noise. Data is there if wanted later. |
| burst | ordinary SHOTs | unchanged tracers; `MAX_FX_PER_TOWER 2` (46) holds at x2 (0.1 s real per bullet, 0.18 s tracer) |

The bleed drop loop is decoration (it shows no rule timing), so real delta is fine under
LT-33's rule; the pulse cadence is not drawn.

### 4.2 Panel (`ui/tower_info.gd`)

- `Level.PENDING` becomes empty (`PackedStringArray()`, kept with `has_pending()` for future
  keys, LT-24 Decision 1); every "(coming soon)" disappears by data.
- `EFFECT_GROUPS` (40-44): `["shooters"]` → `["burst_targets"]`; `["pull_cells"]` group
  reads `pull_cells`, `pull_max_hp`, `pull_immune_seconds` on one line.
- `_effect_text` (219-241): `burst_targets` → "Spreads fire over 3 foes"; `pull_cells` →
  "Pulls back 1.5 cells (≤ 500 HP, every 3 s)"; crit/bleed/strip texts unchanged.
- `_dps` (208-211): comment no longer mentions pending shooters; formula unchanged.
- `neutral()` (90) / `is_active()` (95): new keys are neutral at 0 (only `*_multiplier` keys are neutral at 1, so `crit_multiplier` alone is inactive at 1).

### 4.3 Bots (`tools/bot_runs.gd`)

With PENDING empty, today's `BRANCH_PICK` (52-57) starts buying Marksman and Barbed
(mundane, mixed) and Corrupted Seal (madness); occult keeps Pure branches. Bot results
change by design. To measure the b branches, add a flag `--branch=<tower>:<a|b>[,…]` parsed
in `_init` (64-97, beside `--upgrades=`) that overrides `BRANCH_PICK` for every strategy;
header comment (1-41) documents it. RUN lines unchanged. A measure slice (if planned)
compares mundane with `rifleman:a,harpooner:a` vs `rifleman:b,harpooner:b` over the
default 10 seeds.

---

## 5. Edit map

### S2 — sim + data (one slice; `_fire_towers` is one function)

| File | Lines | Change |
|---|---|---|
| `data/towers.json` | rifleman b; harpooner b | Gangsters (§1.2); add `pull_max_hp 500`, `pull_immune_seconds 3` |
| `sim/defs/tower_def.gd` | 92-96 `EFFECTS` | − `shooters`; + `burst_targets`, `pull_max_hp`, `pull_immune_seconds` |
| `sim/defs/tower_def.gd` | 97-102 `PENDING` | empty; doc comment updated |
| `sim/core/sim_rng.gd` | 8 | append `CRIT` |
| `sim/core/sim_tower.gd` | after 22 | `var burst_index := 0` |
| `sim/core/sim_enemy.gd` | 28-29 | doc: status keys `bleed_ticks`, `bleed_dps`, `bleed_pulse`, `bleed_source`, `pull_immune_ticks` |
| `sim/core/simulation.gd` | `step` 88-91 | slot 2: `_tick_statuses()` after `_apply_madness_buff()`; comment lists bleed/pull |
| `sim/core/simulation.gd` | `_apply_auras` 935-968 | detect `strip_armor`; `strip = maxf`; `e.armor_bonus -= strip`; drop the 960 comment |
| `sim/core/simulation.gd` | `_fire_towers` 1001-1062 | ranked pick + round robin when `burst_targets > 0`; crit roll after the miss roll; `damage × crit` per hit; after the damage loop `_on_hit_effects` (bleed on live hits; pull primary; fill `shot.pulled`); doc comment |
| `sim/core/simulation.gd` | `_pick_target` 1064-1073, `_best_by` 1075-1084, `_first_along_route` 1087-1097 | new `_ranked_targets(t, c, n)` (stable rank by mode key, ties lower id); `_pick_target` delegates |
| `sim/core/simulation.gd` | new near 1136 | `_push_back(e, cells)`, `_tick_statuses()`, `_apply_bleed(e, dps, seconds, source)`, `_roll_crit(chance)` (beside `_roll_miss` 1194) |

Read for context: `apply_damage` 157-173 (unchanged), `_on_enemy_killed` 811-820 (bleed
source), `_move` 1136-1144 and `_leak` 1147-1161 (pull keeps distance ≥ 0, only
decreases), `SimRoute.position_at` (`sim_route.gd:33`), `SimTime.ticks` (`sim_time.gd:10`).

### S3 — render, UI, bots

| File | Lines | Change |
|---|---|---|
| `scenes/board.gd` | 156-163 `enemy_markers`; `_draw_enemies` 443-481 marker draw | `"bleed"` |
| `scenes/board.gd` | 180-217 `_shot_fx`; 539-561 `_draw_tracer`; 562-590 `_draw_harpoon` | crit spark; pull chain |
| `ui/tower_info.gd` | 40-44, 208-211, 219-241 | §4.2 |
| `tools/bot_runs.gd` | 1-41, 64-97, 52-57 | `--branch=` flag (§4.3) |

### Callers / references this map relies on (grep; GDScript is not in g-mesh)

- `PENDING|has_pending|COMING_SOON|is_pending`: `tower_def.gd:101-109`,
  `ui/tower_info.gd:10,69-70`, `tools/bot_runs.gd:29,279,295`, tests
  `tower_role_test.gd:114-155`, `tower_info_test.gd` (8, 51-63, 83-89, 105-114, 143,
  149-161, 203-213, 312-330, 417-423), `bot_upgrade_test.gd:125,134`.
- `shooters`: `tower_def.gd:93`, `tower_info.gd:42,233-234`, `config_valid_test.gd:189`,
  `config_reject_test.gd:372-373`, `tower_info_test.gd:111`.
- `bleed|pull|crit|strip_armor` in code: only the above plus `simulation.gd:960`; none in
  `scenes/`.
- `_pick_target`: only `_fire_towers` (1011). `armor_bonus`: `sim_enemy.gd:26,35`,
  `apply_damage` 163. `status` dicts: declared only (`sim_enemy.gd:29`, `sim_tower.gd:25`).
- SHOT → DIED order pinned: `occult_tower_test.gd:392`, `tower_targeting_test.gd:179`.

### Must confirm (S2)

- No test pins the COMBAT sequence with a Marksman present (none existed: the branch was
  pending) — appending `CRIT` must leave every existing seeded test green.
- Writing `shot["pulled"]` after `_emit` is visible in the drained event (Dictionary by
  reference); if a guard copies event data, emit order must be rethought, not tests changed.
- `sim_boundary_test` / `render_isolation_test` accept the new status keys and SHOT fields.

### S4 — tests: behaviours to pin (new `tests/branch_effects_test.gd`, plus edits)

1. Crit: with `crit_chance 1` a Marksman hit deals `36 − armor`; `0` → `18 − armor`; SHOT
   `crit` only on crits.
2. Crit before armor: vs armor 5, crit hit removes 31 (not 26).
3. Crit uses `CRIT`: the COMBAT miss sequence in Fraying is identical with crit_chance 0 and 1.
4. Gangsters round robin: 3 in range → r0, r1, r2, r0; 2 → alternate; 1 → same target;
   `strongest` mode changes r0.
5. Gangsters: each bullet rolls its own miss (Fraying: COMBAT draws = bullets fired).
6. Bleed: 3 pulses of 6 at +30/+60/+90 ticks, armor per pulse; second hit refreshes
   (duration reset, no double dps); fakes bleed; a bleed kill pays mundane-kill sanity.
7. Pull: primary distance −45000 units, `prev_distance == distance`, clamped at 0; a second
   pull within 90 ticks is refused; `max_hp > 500` never pulled; killed primary not pulled,
   `pulled` empty; flyer pulled along its line; SHOT `pulled` lists the id.
8. Strip: inside a Seal hit = `(dmg − (armor − 1)) × 1.5`; outside unchanged; two Seals still
   −1; armor 0 enemy unchanged.
9. PENDING empty; no "(coming soon)" on any shipped level; `shooters` rejected as unknown;
   `burst_targets` parses; Gangsters role ≤ 24 chars.
10. Bots: `_next_upgrade` buys rifleman a / harpooner a; `--branch=rifleman:b` picks b.
11. Render: `enemy_markers` has `"bleed"` iff `bleed_ticks > 0`; a SHOT with `pulled` makes
    a chain fx; a crit SHOT a big spark.

Rewrites: `tower_role_test.gd:114-155` (PENDING now empty: assert empty and every shipped
level `has_pending() == false`), `tower_info_test.gd` pending cases (lines above),
`bot_upgrade_test.gd:125,134` (now false), `config_valid_test.gd:189` and
`config_reject_test.gd:372-373` (`burst_targets`).

### Suggested controls (revert the code, the test must fail) — 8

| # | Revert | Fails |
|---|---|---|
| C1 | drop the `× crit_multiplier` | 1 |
| C2 | apply crit after armor (`(dmg − armor) × mult` via a second call) | 2 |
| C3 | crit roll on COMBAT instead of CRIT | 3 |
| C4 | burst always `ranked[0]` | 4 |
| C5 | bleed `bleed_dps += new` (stack) | 6 (refresh) |
| C6 | skip the `pull_immune_ticks` check | 7 (immunity) |
| C7 | ignore `pull_max_hp` | 7 (cap) |
| C8 | `_apply_auras` without `armor_bonus -= strip` | 8 |

C1-C4, C8 hit `simulation.gd` only; one build per worktree, `--test branch_effects_test`.

---

## 6. Open questions for the owner

### Q1. Does armor reduce bleed?

**Today:** every damage goes through one armor rule: `damage − armor` per hit, never below 0.
**Change:** bleed deals `bleed_dps` (6) per second for 3 s after a Barbed harpoon hit.
**Example:** Barbed on a Shoggoth (armor 5) and on a Hybrid (armor 2).
- **Armor once per pulse: one 6-damage pulse each second through the normal armor rule
  (Recommended).** Shoggoth takes 1/s, Hybrid 4/s, cultists and Deep Ones 6/s. + One armor
  rule for all damage; Barbed stays a pack/soft-target branch; Corrupted Seal's strip helps
  it. − Bleed is near-useless on the Shoggoth.
- **Bleed ignores armor.** Shoggoth takes 6/s, 18 per hit on top of 19 harpoon damage.
  + Barbed becomes a mundane anti-armor answer at $100. − Overlaps Coast battery AP
  (LT-48) and needs `ignore_armor` (P7) built now instead of in LT-48.
- **Armor per tick (0.2 damage per tick − armor).** + Literal "one rule per hit". − Any
  armor ≥ 0.2 zeroes it: bleed does nothing against Hybrids or Shoggoths.

### Q2. Limits on the Chain harpoon pull

**Today:** nothing moves an enemy backwards.
**Change:** a Chain harpoon hit pulls its target 1.5 cells back along its route every 1.5 s.
**Example:** a cultist walks 1.5 cells in 1.5 s; one Chain harpoon in Lucid pulls it 1.5
cells back each shot — it never advances. Two towers do the same to a Shoggoth.
- **HP cap 500 + 3 s immunity after a pull (Recommended).** Cultist at 50 % speed, Hybrid
  44 %, Deep One 69 %; Shoggoth and Dagon never pulled (harpoon still damages them). + Same
  "≤ 500 HP" line as the Silver Key's L1-L2 (LT-46 Q4); no locks by stacking towers. − Two
  new numbers on the panel line.
- **HP cap only.** + Simple. − One tower locks a cultist; two lock a Hybrid: a hard counter
  to every walker under 500 HP.
- **Immunity only (no cap).** + Works on everything. − A 3600-HP Shoggoth pulled 1.5 cells
  every 3 s (0.5 c/s × 3 s = 1.5): the slowest enemy is held in place by one tower.

### Q3. Gangsters under the lighthouse beam: +20 % or +25 %?

**Today:** cooldowns are whole ticks (`ticks(s) = round(s × 30)`). LT-30 will make a lit
mundane tower fire with `fire_interval × 0.8` (meant as +25 % rate).
**Change:** Gangsters fire every 0.2 s = 6 ticks; lit, 0.16 s = 4.8 → 5 ticks.
**Example:** lit Gangsters fire 6 shots/s instead of 7.5 (+20 %); Marksman 0.7 s → 17 ticks
(+23.5 %); Coast battery 3 s → 72 ticks (+25 %).
- **Accept whole-tick rounding (Recommended).** + No sim change; every tower is exact to a
  tick and replays stay trivial. − The fastest towers gain a bit less than 25 %.
- **Carry the fraction (a sub-tick cooldown remainder per tower).** + Exactly +25 % for
  all. − Touches every tower's cooldown (all seeded timing tests move); belongs to LT-30.

### Q4. Whom the chain pulls

**Today:** the harpoon pierces: one line hits the target and every enemy within 0.5 cell
of the line.
**Change:** pull 1.5 cells back.
**Example:** a Deep One pack of 5 walking in a line toward the harpooner.
- **The primary target only (Recommended).** + Matches "Pulls target back" and LT-25's one
  chain from the enemy to the tower; with Q2's immunity a modest slow. − Weak against packs
  (that is Barbed's job).
- **Every enemy the harpoon hits.** + Strong anti-pack control. − With 3 s immunity a whole
  pack loses ~30 % speed from one $225 tower, outclassing Elder Sign's slow; the render
  needs several chains per shot.
