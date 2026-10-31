# LT-31 — Tower target priority

Owner request (LT-27 review, night agency): per tower, the player switches whom it shoots.
It costs nothing, is allowed in any phase and is a logged, deterministic sim command.

## Decisions

1. **Modes** (`SimTower.TARGET_PRIORITIES`, panel order): `"first"` (default, today's rule:
   least route distance left to the lighthouse), `"strongest"` (highest current `hp`),
   `"fastest"` (highest current speed). Stored on `SimTower.target_priority`.
2. **Tie-break**: every mode ties to the lower enemy id, as today. Candidates come from
   `enemies_in_range` in id order and a strictly better key is needed to replace the
   current pick. No secondary key (a full-HP pack of one type ties to its lowest id, which
   is the earliest spawned).
3. **"Fastest"** = the units the enemy moves this tick, `roundi(base_units_per_tick x
   speed_mult)`, exactly what `_move` uses. `speed_mult` is reset in slot 1 and set by
   auras in slot 2, so Elder Sign slow counts; any later speed modifier written into
   `speed_mult` (e.g. a madness buff, none today) counts automatically. Integer, so no
   float ties drift.
4. **"Strongest"** = current `hp` (not `max_hp`, not armor-adjusted).
5. **Fakes stay targetable** in every mode: hallucinations draw real shots (LT-12). A fake's
   hp and speed are its def's, so it competes like a real enemy; nothing here tells them
   apart.
6. **Harpooner** (pierce): the mode picks the primary target; the line is drawn from the
   tower through it as before (`_line_end`, `_line_hits`), the primary is always hit.
7. **Necronomicon Reader** (aoe): the blast centres on the target the mode picks.
8. **Madness astray** (LT-13) overrides the mode as before: an astray shot re-picks at
   random from the pool; the mode-picked target is only the aim point of an empty shot.
9. **Elder Sign** (aura, damage 0): no target, so `Simulation.has_targeting` is false, the
   command is refused with `NO_TARGETING` and the panel shows no switch. Decided per
   current level (`stats().damage > 0`).
10. **Command** `Simulation.set_target_priority(tower_id, mode)`, checked by
    `can_set_target_priority`; rejection order `OUTCOME_REACHED`, `NO_SUCH_TOWER`,
    `NO_TARGETING`, `BAD_PRIORITY` (new values appended to `CommandResult`). No phase or
    gold check. Re-setting the current mode is applied (logged, event): harmless, replays
    identically; the panel never sends it (current mode's button is disabled).
    OK: `target_priority` set, `command_log` gets `[tick, "set_target_priority", id, mode]`,
    `TARGET_PRIORITY_SET {def, cell, mode}` emitted (new `SimEvent.Type`, appended); no gold
    or sanity event; cooldown untouched; the next shot uses the new mode.
11. **Upgrade/sell**: an upgrade keeps the mode (same tower object); a sold tower is gone.
12. **Bots** (`tools/bot_runs.gd`) never call the command, so they keep `"first"`; their
    runs are unchanged.
13. **UI**: the tower view of the side panel shows `── Target ──` and one button per mode
    (`Closest to the lighthouse`, `Strongest`, `Fastest`; names in
    `TowerInfo.PRIORITY_NAMES`) between the stats and the upgrade section. The current mode
    is prefixed `▸ `, disabled and drawn in the role colour; others are enabled, or disabled
    with ` (<reason>)` when the sim refuses (run over). Clicking calls
    `Game.set_target_priority`. Hidden for Elder Sign.

## Behaviours to pin (tests slice)

Each line: behaviour — implementing function.

1. A new tower has `target_priority == "first"` and shoots as before (existing targeting tests unchanged) — `SimTower`, `Simulation._pick_target` -> `_first_along_route`.
2. "strongest": of enemies in range the highest current `hp` is shot, also when it is behind another along the route; a damaged front enemy loses to a full-HP one behind — `_pick_target`, `_best_by`.
3. "fastest": the enemy with the highest `roundi(base_units_per_tick x speed_mult)` is shot; an enemy slowed by an Elder Sign aura this tick loses to an unslowed slower-def one when its slowed speed is lower — `_pick_target`, `_best_by`, `_apply_auras`.
4. Ties in "strongest" and "fastest" (equal key) go to the lower id — `_best_by` (strict `>`).
5. Fakes are picked by every mode like real enemies (a fake with higher hp is the "strongest" target) — `_pick_target` over `enemies_in_range`.
6. Harpooner with "strongest": the line goes through the strongest enemy, which is in `hits` — `_fire_towers` (pierce branch) with `_pick_target`.
7. Necronomicon with "strongest"/"fastest": SHOT `to` is that enemy's position; the blast hits around it — `_fire_towers` (aoe branch).
8. In MADNESS an astray madness_affected shot still picks from the random pool, not by mode — `_fire_towers`.
9. Rejections in order OUTCOME_REACHED, NO_SUCH_TOWER (unknown / sold id), NO_TARGETING (Elder Sign at L1/L2/L3), BAD_PRIORITY (`"weakest"`, `""`); each changes nothing (no log, no event, mode unchanged) — `Simulation.can_set_target_priority`.
10. Allowed in BUILD, WAVE and NONE phases and in MADNESS; no gold/sanity change — `set_target_priority`.
11. OK: `command_log` gets `[tick, "set_target_priority", id, mode]`, one TARGET_PRIORITY_SET {def, cell, mode} event, cooldown unchanged; re-setting the same mode is OK and logged — `set_target_priority`.
12. Replaying a command log with set_target_priority (mid-wave) and the same seed gives the same events and state (the replay helper needs a `"set_target_priority"` case) — `set_target_priority`, `_pick_target`.
13. Upgrade keeps the chosen mode — `upgrade_tower` does not touch `target_priority`.
14. Bot runs never log `set_target_priority`; RUN lines unchanged — `tools/bot_runs.gd` (no call).
15. Side panel: a Rifleman/Harpooner/Necronomicon tower view shows `PriorityTitle` and `Priority_first/strongest/fastest` visible, the current one's text starts with `▸ ` and is disabled; Elder Sign hides all four — `TowerPanel._refresh_priority`, `Simulation.has_targeting`.
16. Clicking `Priority_fastest` calls `Game.set_target_priority`, the tower's mode becomes `"fastest"`, the button becomes the marked/disabled one, the panel stays on the tower — `TowerPanel._on_priority_pressed`, `Game.set_target_priority`.
17. After OUTCOME the non-current buttons are disabled with ` (run over)` (panel is hidden anyway) — `_refresh_priority`, `TowerInfo.reason`.
18. `TowerInfo.REASONS` maps NO_TARGETING and BAD_PRIORITY — `TowerInfo`.

Screenshot of the switch (S1): scratchpad `lt31/side_panel_priority.png`.

## Controls (S3)

Each control is a production-code revert (tests untouched) that must make the named test
fail. Tests: `tests/target_priority_test.gd` (TP), `tests/madness_test.gd` (MAD),
`tests/upgrade_test.gd` (UP), `tests/side_panel_test.gd` (SP).

| # | Behaviour | Revert (production code) | Must fail |
|---|-----------|--------------------------|-----------|
| C1 | 2 strongest = current hp | `Simulation._pick_target` "strongest": key `e.hp` -> `e.max_hp` | TP `test_strongest_uses_current_hp_so_a_damaged_front_enemy_loses_to_a_full_one` |
| C2 | 3 fastest counts the slow | `_pick_target` "fastest": key `roundi(e.base_units_per_tick * e.speed_mult)` -> `e.base_units_per_tick` | TP `test_fastest_counts_the_elder_sign_slow_of_this_tick` |
| C3 | 4 tie -> lower id | `Simulation._best_by`: `k > best_key` -> `k >= best_key` | TP `test_a_strongest_tie_goes_to_the_lower_id_not_the_one_further_along`, `test_a_fastest_tie_goes_to_the_lower_id_not_the_one_further_along` |
| C4 | 6, 7, 12 mode drives the shot and the replay | `Simulation._fire_towers`: `_pick_target(t, in_range)` -> `_first_along_route(in_range)` | TP `test_reader_blast_centres_on_the_strongest_target`, `test_harpoon_line_goes_through_the_strongest_enemy`; UP `test_replaying_a_log_with_target_priority_switches_gives_the_same_run` (its "without differs" control) |
| C5 | 8 astray ignores the mode | `_fire_towers` astray branch: `target = pool[rng(...).randi_range(...)]` -> `target = _pick_target(t, pool)` (keep the MADNESS draw) | MAD `test_an_astray_shot_ignores_the_target_priority` |
| C6 | 9 rejection order | `Simulation.can_set_target_priority`: move the `BAD_PRIORITY` check above `NO_TARGETING` | TP `test_elder_sign_is_no_targeting_at_every_level_and_beats_bad_priority` |
| C7 | 11 cooldown untouched | `Simulation.set_target_priority`: add `t.cooldown_ticks = 0` after setting the mode | TP `test_the_running_cooldown_is_kept_and_the_next_shot_uses_the_new_mode` |
| C8 | 15 hidden for Elder Sign | `TowerPanel._refresh_priority`: `var shown := game.sim.has_targeting(t)` -> `var shown := true` | SP `test_elder_sign_hides_the_switch_at_every_level` |
