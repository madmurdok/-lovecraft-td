# Test fixtures

## Golden replay (LT-73, B0 / guard G5 of docs/design/LT-65-architecture-review.md)

- `golden_data/`: a frozen copy of `data/` (every JSON file `GameConfig` loads), taken at
  0.5.0. Balance tuning edits `data/` and never touches the golden test. Do not edit
  `golden_data/` to follow `data/`.
- `golden_digests.json`: per-run digests of the golden runs (`tests/golden_runs.gd`): every
  drained event (type, tick, id, data with sorted keys, floats as their exact bits) hashed as a
  whole and per 900-tick bucket, the event count, and a hash of the final state. Runs: every
  `tools/bot_runs.gd` strategy x the seeds in `GoldenRuns.SEEDS`, the `SimNoTreeLoop` game and
  the LT-34 frame-driven `Game` run (its command log replayed on a bare sim).
- `tests/golden_replay_test.gd` recomputes the digests and compares; a failure names the run,
  the first differing tick window and the final-state summary.

### Regenerating `golden_digests.json`

```
scripts/golden-regen.sh
```

Only when the sim's behaviour changes on purpose and the owner approved that change (a new
mechanic, a rule change, a new event field), or when `golden_data/` itself is deliberately
replaced. Commit the regenerated file in the same commit as the change and say why in the
message. Never during a refactor (the refactor plan's steps must keep the golden test green
without regenerating), and never edit the file by hand.
