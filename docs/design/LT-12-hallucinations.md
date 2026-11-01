# LT-12 — Hallucinations: fake enemies and misses (design note)

Status: approved · 2026-10-30 · branch `docs/LT-12-hallucinations-design`

## 0. What exists today and what this task adds

**Today** (`release-0.1.0`): `Simulation.spawn_enemy(def_id, is_fake)` can already create a
fake; `SimEnemy.is_fake` and `SimEnemy.revealed` exist. Fakes are targeted like real ones
(`enemies_in_range`, `_line_hits` include them), take damage, emit `DIED` but pay no gold
and no regen (`_on_enemy_killed`), never drain sanity (`_horror_drain`, LT-10), deal 0 leak
damage, and do not hold a wave or the win open (`WaveDirector.end_tick`, `_check_outcome`).
Two gaps: `LEAKED` carries `"fake": true|false` (the render layer can read the flag), and
nothing spawns fakes, nothing dissolves them, no tower ever misses.

**This task** adds: a fake scheduler driven by the sanity threshold, dissolve on wave end
and at the lighthouse, the Fraying miss roll, the rule that keeps the flag out of the
render layer, and a debug reveal.

```
slot 5 _fire_towers ── miss roll (COMBAT) when thresholds[state].miss_chance > 0
slot 7 spawner.tick ── HallucinationSystem.tick ── spawn_enemy(def, true)  (pick + pack on SANITY)
slot 8 _compact ── spawner.end_tick ── _clear_wave ── dissolve_fakes("wave_end") → bonus → WAVE_CLEARED
```

---

## 1. Where the flag lives; what the render layer may see

GDScript has no private members: whatever the sim holds, a scene *can* read. So every
option is a convention; the difference is how cheap it is to keep and to check.

| Option | How | For | Against |
|---|---|---|---|
| **A. Field stays, scanned** (chosen) | `SimEnemy.is_fake` stays; a source-scan test fails if any script outside `sim/` and `tests/` names `is_fake`; scenes get one gated accessor `sim.debug_is_fake(e)` | zero churn in 6 sim call sites and ~10 tests; the check is a test, not a hope | relies on the scan; a scene could still use `get("is_fake")` (the scan also catches the string `"is_fake"`) |
| B. Registry | `Simulation._fake_ids: Dictionary`; flag removed from `SimEnemy`; sim asks `_is_fake(id)` | the object the renderer holds carries nothing | `_` is not private either, so still needs the scan; rewrites every call site and test; a lookup per enemy per tick |
| C. View objects | scenes get `EnemyView {id, def, pos, hp, revealed}` snapshots | isolation by construction | per-frame allocation that LT-4 §2 rejected; LT-7 is already built on `sim.state` |

**Rules (A):**
- Scenes may read `sim.state` (enemy `id`, `def`, `hp`, `max_hp`, position via
  `enemy_position`, `revealed`), and events. Never `is_fake`.
- **No event carries the flag or a value only one kind can have.** `SPAWNED {def}`, `SHOT`,
  `DIED {source, reward}` are identical for both (`reward` stays `def.reward`, the def
  value, as today; gold comes from `GOLD_CHANGED`). `LEAKED` loses its `"fake"` key; fakes
  no longer emit `LEAKED` at all (§3).
- **Post-hoc tells are accepted:** once a fake is gone the player may learn it was fake
  (no gold on its kill, no HP lost at the lighthouse, the dissolve VFX). While it is alive
  nothing distinguishes it. The one live tell is LT-10's "fakes never drain" (Q5).
- **Debug flag:** `Simulation.debug_reveal_fakes := false`, set only by `scenes/main.gd`
  when `OS.is_debug_build()` and the user arg `--reveal-fakes` is present (same parsing as
  `_config_dir`). `debug_is_fake(e) -> bool` returns `debug_reveal_fakes and e.is_fake`.
  The renderer (LT-7) tints such enemies (e.g. a magenta outline). The sim never reads the
  flag, so it cannot change outcomes or determinism.

---

## 2. Fake spawn scheduler

New `sim/core/hallucination_system.gd` (`class_name HallucinationSystem`, plain
`RefCounted`), owned by `Simulation`, ticked in slot 7 right after `_spawner.tick`.

- **Candidates come from the spawner.** New `SimSpawner.fake_candidates() -> Array[String]`
  (base: `[]`). `WaveDirector` returns, in phase WAVE and while `not _all_fired`, one entry
  per *unfired spawn event* of the current wave (`count - _fired[gi]` copies of
  `g.enemy_id`, group order). Empty list = no fakes now. So: none in BUILD/DONE, none after
  the wave's groups are exhausted (Q2), none with `ScriptedSpawner` (existing tests keep
  their exact event lists). Weighting by remaining events means a fake mirrors what is
  still to come: a wave of 10 cultists + 1 shoggoth yields mostly fake cultists.
- **Pick:** `candidates[rng(SANITY).randi_range(0, size-1)]`. **Stream SANITY**, not
  MADNESS: fakes are a threshold effect from Whispers on; MADNESS stays for LT-13's
  shot_split so the two do not reshuffle each other.
- **Timer, in ticks.** `interval = SimTime.ticks(thresholds[key].fake_spawn_interval)` for
  the current `sanity_state` (key map LUCID→"lucid" ... MADNESS→"madness"); 15 s = 450,
  6 s = 180. A counter `_elapsed` is set to 0 when a new `wave_index` is seen, advances by
  1 each WAVE tick in which `interval > 0`, and when `_elapsed >= interval` one fake spawns
  and `_elapsed = 0`. First fake of a wave at wave tick 450 (Whispers) / 180 (Fraying).
- **Threshold change mid-wave: keep the counter, compare with the new interval.** Example:
  Whispers, 10 s elapsed, sanity drops to Fraying → 300 ≥ 180, a fake spawns next tick,
  then every 6 s. Rising back to Lucid pauses the counter (no reset). *Reset* was rejected:
  sanity that hovers at a boundary (kill regen +0.5 vs horror drain each tick) would reset
  it forever and Fraying would never spawn a fake. *Prorate* behaves almost the same as
  keep for more code.
- **Spawn point and route:** `spawn_enemy(def, true)` as for a real one: route start `S`,
  flyers on the straight route (fake night-gaunts allowed). Same tick slot as real spawns.
- **Packs:** a fake Deep One comes as a full pack (a lone Deep One would be a live tell).
  The pack size of a fake rolls on **SANITY**, not SPAWN: `spawn_enemy` picks the stream by
  `is_fake`, so hallucinations never change the size of later real packs.
  Since LT-63 a fake pack's members enter one by one like a real pack's; fake members still
  queued at dawn are dropped with the other fakes (no event: they never entered).
- **Cap:** none. At 6 s and with dissolve at wave end the count is bounded by wave length
  (~10 per minute of wave). No new config field.

---

## 3. Towers vs. fakes; lighthouse

- Targeting, damage, armor, `damage_taken_mult`, HP bar: unchanged and identical (already
  so). Kill: `DIED` identical; `_on_enemy_killed` pays nothing (already so).
- **At the lighthouse a fake dissolves instead of leaking** (GDD §11 "fakes never leak").
  `_leak` marks it gone and emits `FAKE_DISSOLVED {reason: "lighthouse"}`; no `LEAKED`, no
  HP change. The renderer plays the dissolve VFX (GDD §9a lists "fake dissolve"). The
  alternative, a `LEAKED {damage: 0}` splash with an HP counter that does not move, reads as
  a bug (Q1).
- New `SimEnemy.dissolved := false`; `is_live()` becomes `not dead and not leaked and not
  dissolved`, so `_compact` removes it with no further change.

## 4. Miss chance (Fraying, Madness)

- `miss = thresholds[key].miss_chance` for the current state (0, 0, 0.15, 0.15).
- **Which towers:** mundane towers only (rifleman, harpooner; owner decision Q3). Occult
  towers never roll a miss: their price is sanity, and in Madness those with
  `madness_affected` use LT-13's shot_split instead. Elder Sign and searchlight have no
  shot. Rule in code: roll only when `tower.def.kind == "mundane"` and damage > 0.
- **Resolution:** after the target is chosen, before damage: if `miss > 0`, one roll
  `rng(COMBAT).randf() < miss`. No roll when `miss == 0`, so Lucid/Whispers runs consume
  COMBAT exactly as today. One roll per shot: a harpoon line misses as a whole; Militia's
  two shooters (when built) roll once each; a crit roll (later) happens only on a hit.
- **On a miss:** cooldown is spent, no damage, no sanity cost change (a Necronomicon cast
  that misses still costs its sanity: the cast happened). Event: the same `SHOT` with
  `"miss": true` and `"hits": []`; `"to"` stays the aim point; hits carry `"miss": false`.
  One event type with a field instead of a new `SHOT_MISSED`: every consumer of SHOT
  already exists and a miss still is a shot (sound, muzzle flash, cooldown).

## 5. Dissolve at wave end

`WaveDirector._clear_wave`, at the existing LT-12 hook, calls
`sim.dissolve_fakes("wave_end")` before the bonus. It emits `FAKE_DISSOLVED {reason:
"wave_end"}` per live fake in id order, marks them `dissolved`, then compacts
`state.enemies` again (slot 8's `_compact` already ran this tick), so the build phase
starts with no enemy in `state`. Order in that tick: `FAKE_DISSOLVED`… → `GOLD_CHANGED`
(bonus) → `SANITY_CHANGED` (between waves) → `WAVE_CLEARED` → `BUILD_STARTED` (or `WON` in
slot 9 after the last wave). Bonus and outcome ignore fakes, as today. On a loss
(`lighthouse_hp == 0`) nothing dissolves; the run is frozen anyway.
`SimEvent.Type` gains `FAKE_DISSOLVED` appended at the end.

## 6. Interfaces left for LT-11 and LT-13

- **LT-11 Necronomicon:** AoE uses `enemies_in_range` (fakes included) and `apply_damage`;
  a fake can trigger a cast (that is the pressure). It must call the miss hook (below).
- **LT-11 Elder Sign:** aura applies to fakes too (slow, damage taken, strip armor); a fake
  walking faster through the aura would be a live tell. Corrupted Seal "active" counts
  fakes inside the aura.
- **Miss hook:** `Simulation._roll_miss() -> bool` (COMBAT, state-driven); LT-11's cast code
  and `_fire_towers` both call it. LT-11 is editing `_fire_towers` in parallel: the code
  slice rebases on it and adds one call per shot path.
- **LT-13 madness:** `Simulation.live_fakes_in_range(cell, r) -> Array[SimEnemy]` (sim
  only) for the "25% hit a fake" branch; `HallucinationSystem.spawn_fake(def_id)` is public
  if LT-13 wants a fake on demand. shot_split rolls on MADNESS. Madness thresholds already
  carry the Fraying values (6 s, 0.15), so the scheduler needs no madness case.
- **Revealing searchlight** (later): sets `SimEnemy.revealed`; the renderer reads that.

---

## 7. Must confirm, edit map, behaviours

### Must confirm (code slice)
1. LT-11's `_fire_towers` shape after its merge; place the miss roll in every shot path.
2. `wave_test_base.gd:47` and `sim_outcome_test.gd:166-192` read `is_fake` / the `LEAKED`
   `"fake"` key: update them to the new lighthouse rule (tests may read `is_fake`).
3. No existing test asserts `LEAKED.data` for a fake beyond `sim_outcome_test.gd:174`.
4. `rng(SANITY)` is unused today (grep): the new rolls shift nothing existing.
5. Whether LT-7's renderer already reads `LEAKED` / `DIED`; add a `FAKE_DISSOLVED` case.

### Edit map
| Path | Lines | Change |
|---|---|---|
| `sim/core/sim_enemy.gd` | 13-18, 36-37 | add `dissolved`; `is_live()` checks it |
| `sim/core/sim_event.gd` | 6-7 | append `FAKE_DISSOLVED` |
| `sim/core/sim_spawner.gd` | after 25 | `fake_candidates() -> Array[String]` returning `[]` |
| `sim/core/wave_director.gd` | new func; 112-123 | `fake_candidates()` per §2; `_clear_wave` calls `sim.dissolve_fakes("wave_end")` at the hook |
| `sim/core/simulation.gd` | 21-42 | `var _hallucinations`, `var debug_reveal_fakes`; create the system in `_init` |
| | 54-84 | slot 7: `_hallucinations.tick(self)` after `_spawner.tick` |
| | 87-118 | pack roll on SANITY when `is_fake` |
| | 386-412 | miss roll per shot via `_roll_miss()`; `SHOT` gains `miss` |
| | 474-482 | fake: `dissolved`, `FAKE_DISSOLVED {reason: "lighthouse"}`; real `LEAKED` drops `"fake"` |
| | new | `dissolve_fakes(reason)`, `debug_is_fake(e)`, `live_fakes_in_range`, `_roll_miss`, `_threshold()` |
| `sim/core/hallucination_system.gd` | new | timer, pick, `tick(sim)`, `spawn_fake(def_id)` |
| `scenes/main.gd` | 12-28 | `--reveal-fakes` in debug builds → `sim.debug_reveal_fakes` (when LT-7's sim exists there) |
| `tests/hallucination_test.gd`, `tests/miss_test.gd`, `tests/render_isolation_test.gd` | new | behaviours below |

### Behaviours the tests slice pins
1. Lucid: no fake ever spawns in a full wave.
2. Whispers: first fake at wave tick 450, then every 450; Fraying/Madness: 180.
3. No fake in BUILD (whole build phase at Fraying), none after the wave's groups are all
   fired, none with `ScriptedSpawner`.
4. Threshold drop mid-wave keeps the counter (300 elapsed → spawn on the next tick); rise
   to Lucid pauses it; a new wave resets it.
5. Fake type is one of the current wave's unfired groups; same seed → same picks.
6. Fake Deep One spawns as a pack in [min, max]; real pack sizes in a run with fakes equal
   those of the same seed without fakes (SANITY vs SPAWN independence).
7. A fake reaching the lighthouse: no HP change, no `LEAKED`, one `FAKE_DISSOLVED
   {reason: "lighthouse"}`, removed.
8. A killed fake: `DIED` identical in keys and values to a real of the same def; no
   `GOLD_CHANGED`, no `SANITY_CHANGED`.
9. Wave ends with fakes alive: `FAKE_DISSOLVED` per fake (id order) before the bonus's
   `GOLD_CHANGED` and `WAVE_CLEARED`; `state.enemies` empty in BUILD; last wave → `WON`.
10. `SPAWNED`/`SHOT`/`DIED` data of fake and real are indistinguishable (same keys, no
    `fake` key anywhere); no event type but `FAKE_DISSOLVED` differs.
11. Miss: at Fraying, 1000 shots on one seed miss within [10 %, 20 %]; at Lucid/Whispers
    none, and COMBAT is untouched (a seeded sequence check); a miss spends cooldown, deals
    nothing, emits `SHOT {miss: true, hits: []}`; a harpoon miss hits nobody on the line.
12. `debug_is_fake` is false for every enemy unless `debug_reveal_fakes`; then it equals
    `is_fake`.
13. Source scan: no `.gd` outside `sim/` and `tests/` contains `is_fake` (word or string).

Controls (revert → test must fail): drop the SANITY pack stream (6); emit `LEAKED` for
fakes (7); move dissolve after `WAVE_CLEARED` (9); roll miss when chance is 0 (11);
remove the phase check in `fake_candidates` (3).

---

## 8. Open questions for the owner

1. **What a fake does at the lighthouse.** *Today* it "leaks" with 0 damage and a `LEAKED`
   event, so the renderer would play the leak splash while the HP counter stays.
   *Change:* it dissolves there (`FAKE_DISSOLVED`, dissolve VFX, no splash). *Example:* a
   fake cultist walks into the lighthouse and melts into fog. *Consequence:* honest and
   matches GDD §11 "never leak"; the player learns, after the fact, it was fake.
   Alternative: it vanishes with the real leak splash and no HP loss (more doubt, looks
   like a bug). **Recommended: dissolve.**
2. **Fakes after the last real spawn.** *Today* nothing spawns fakes. *Change:* fakes stop
   once the wave's spawn groups are exhausted, while real stragglers are still walking.
   *Example:* wave 3 spawns its last hybrid at 40 s; the last real dies at 70 s; no fake
   appears in 40-70 s. *Consequence:* no "enemy that appeared after the wave finished" tell
   for players who know the wave; the tail of a wave is calmer. Alternative: keep
   spawning until the wave clears (more pressure, that tell exists). **Recommended: stop.**
3. **Do occult towers miss?** *Today* nobody misses. *Change:* every tower that fires a
   shot rolls 15 % at Fraying, Necronomicon included (a missed cast still costs 2 sanity).
   *Example:* a Fraying Necronomicon blast lands on empty water 1 time in 7. *Consequence:*
   simple and as GDD says "towers miss"; it makes occult towers weaker exactly when sanity
   is low (a spiral). Alternative: only mundane towers miss. **Recommended: all.**
4. **GDD §9a "flicker on fake enemies".** *Today* the art pipeline lists a shader flicker
   on fakes, which would reveal them and contradicts §5.3. *Change:* the flicker becomes
   a Fraying effect on *all* enemies (or is dropped). *Example:* at sanity 30 every enemy
   shimmers. *Consequence:* keeps fakes indistinguishable; GDD §9a gets one line edited.
   **Recommended: all enemies.**
5. **Fakes never drain sanity (LT-10).** *Today* a fake shoggoth near a tower does not
   lower sanity, while a real one drains 0.5/s; an attentive player can tell them apart
   while both live. *Change (optional):* fakes drain like real ones. *Consequence:*
   removes the only live tell but makes hallucinations feed the spiral (more fakes →
   lower sanity → more fakes). **Recommended: keep LT-10's decision, note it in GDD §11.**
6. **Fake bosses.** Dagon is not in `enemies.json` yet. *Change:* when it lands, a boss is
   never picked as a fake. *Example:* the boss wave's fakes are only its Deep Ones.
   *Consequence:* a fake Dagon (6000 HP soaking all fire) would decide runs by luck.
   **Recommended: exclude bosses** (a trait in Dagon's content task).

**Owner decisions (2026-10-30):** Q1 "Растворяется (Recommended)"; Q2 "Нет, перестают
(Recommended)"; Q3 "Только обычные башни" (changes §4: occult towers never miss);
Q4 "Мерцают все враги при Fraying (Recommended)" (GDD §9a edited); Q5 "Оставить, записать
в GDD (Recommended)" (GDD §11 edited); Q6 "Нет, боссы исключены (Recommended)" (for the
Dagon content task). Also decided (orchestrator, with LT-11): fakes are slowed by Elder
Sign auras and hit by Necronomicon blasts like real enemies, so behaviour gives no tell.
