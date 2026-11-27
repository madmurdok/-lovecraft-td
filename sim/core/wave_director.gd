class_name WaveDirector
extends SimSpawner
## Wave flow from waves.json (GDD §4, §8; LT-5): BUILD (timer) -> WAVE n -> BUILD -> ...
## -> DONE after the last wave is cleared. Writes SimState.phase / wave_index /
## waves_total / build_ticks_left and emits BUILD_STARTED, WAVE_STARTED, WAVE_CLEARED.
##
## Timing, all in ticks: the run starts in BUILD with build_ticks_left = build phase ticks.
## Each BUILD tick decrements it; the tick it reaches 0 starts the wave, and that same tick
## is wave tick 0. A wave called early (Simulation.call_wave, between ticks) makes the next
## tick wave tick 0. Spawn event k of a group fires on wave tick
## ticks(delay) + k * ticks(interval); events due on one tick fire in group order, then
## event order. A pack enemy expands into its pack inside Simulation.spawn_enemy; its
## members after the first enter later, one per pack.spacing_s (LT-63).
##
## Day = BUILD, night = WAVE (LT-27 §3). Dawn (clearing a wave) runs Simulation.on_dawn
## (fakes, relic tokens, wage, sanity; LT-99), then emits WAVE_CLEARED and resets the night luck.
## LT-109: every build phase first calls Simulation.on_build_start(next wave) (route plan of
## the next wave), and start_wave calls Simulation.on_wave_start after advancing wave_index,
## before WAVE_STARTED (that plan becomes the one spawns read). Neither draws nor emits.
## A wave is cleared when every group has fired all its events, no real pack member is still
## queued (LT-63) and no real enemy is alive (fakes do not count). Clearing pays award_wave_bonus(n) (the dawn wage) before the outcome check, so the
## last wave's bonus is paid in the same tick WON is set; the between-waves sanity regen
## (award_wave_sanity) follows the bonus the same way.

var _waves: WavesConfig
var _build_ticks: int
var _done := false
var _wave_tick := 0  ## wave tick the next spawn pass handles
var _fired: Array[int] = []  ## per group of the current wave: spawn events already fired


func _init(waves: WavesConfig) -> void:
	_waves = waves
	_build_ticks = SimTime.ticks(waves.build_phase_seconds)


## Starts the run in the build phase before wave 1 (tick 0).
func attach(sim: Simulation) -> void:
	sim.state.waves_total = _waves.waves.size()
	_begin_build(sim)


func tick(sim: Simulation) -> void:
	var s := sim.state
	if s.phase == SimState.Phase.BUILD:
		s.build_ticks_left -= 1
		if s.build_ticks_left > 0:
			return
		start_wave(sim, false)
	if s.phase == SimState.Phase.WAVE:
		_spawn_due(sim)


func end_tick(sim: Simulation) -> void:
	var s := sim.state
	if s.phase != SimState.Phase.WAVE or s.lighthouse_hp == 0:
		return  # a wave that ends with the lighthouse is not survived: no bonus
	if not _all_fired(s) or sim.has_queued_real_members():
		return
	for e in s.enemies:
		if not e.is_fake:
			return
	_clear_wave(sim)


## LT-12 §2: in a wave whose groups are not all fired, one entry per unfired spawn event
## (`count - fired` copies of the group's enemy id, group order); otherwise empty, so no
## fake spawns in BUILD/DONE or after the wave's last real spawn (owner decision Q2).
func fake_candidates(sim: Simulation) -> Array[String]:
	var out: Array[String] = []
	var s := sim.state
	if s.phase != SimState.Phase.WAVE or _all_fired(s):
		return out
	var groups := _current_wave(s).groups
	for gi in groups.size():
		for _k in groups[gi].count - _fired[gi]:
			out.append(groups[gi].enemy_id)
	return out


## True once the last wave is cleared.
func is_exhausted() -> bool:
	return _done


## Ends the build phase and starts the next wave. `early` = called by the player
## (Simulation.call_wave), which then spawns from the next tick on; otherwise the timer
## ran out and the caller spawns in this same tick. Only valid in BUILD.
func start_wave(sim: Simulation, early: bool) -> void:
	var s := sim.state
	if s.phase != SimState.Phase.BUILD:
		return
	var ticks_left := s.build_ticks_left
	s.phase = SimState.Phase.WAVE
	s.wave_index += 1
	sim.on_wave_start()  # LT-109: the day's route plan is now the one spawns read
	s.build_ticks_left = 0
	_wave_tick = 0
	_fired.clear()
	_fired.resize(_current_wave(s).groups.size())
	_fired.fill(0)
	sim.emit_event(SimEvent.Type.WAVE_STARTED, 0,
		{"wave": s.wave_index, "early": early, "ticks_left": ticks_left})


## LT-67 (debug, Simulation.debug_end_night): marks every spawn event of the current wave
## fired without spawning it, so the dawn check can clear the wave. Only in WAVE.
func debug_fire_all(sim: Simulation) -> void:
	if sim.state.phase != SimState.Phase.WAVE:
		return
	var groups := _current_wave(sim.state).groups
	for gi in groups.size():
		_fired[gi] = groups[gi].count


func _begin_build(sim: Simulation) -> void:
	var s := sim.state
	sim.on_build_start(s.wave_index + 1)  # LT-109: plan the next wave's routes first
	s.phase = SimState.Phase.BUILD
	s.build_ticks_left = _build_ticks
	sim.emit_event(SimEvent.Type.BUILD_STARTED, 0,
		{"next_wave": s.wave_index + 1, "ticks": _build_ticks})


## LT-109: group gi spawns on its route of the frozen plan (state.route_now.group_routes[gi];
## "" = the default route when the plan has no entry for it).
func _spawn_due(sim: Simulation) -> void:
	var groups := _current_wave(sim.state).groups
	var routes := sim.state.route_now.group_routes
	for gi in groups.size():
		var g := groups[gi]
		var delay := SimTime.ticks(g.delay)
		var interval := SimTime.ticks(g.interval)
		while _fired[gi] < g.count and delay + _fired[gi] * interval <= _wave_tick:
			_fired[gi] += 1
			sim.spawn_enemy(g.enemy_id, false, routes[gi] if gi < routes.size() else "")
	_wave_tick += 1


func _all_fired(s: SimState) -> bool:
	var groups := _current_wave(s).groups
	for gi in groups.size():
		if _fired[gi] < groups[gi].count:
			return false
	return true


func _clear_wave(sim: Simulation) -> void:
	var s := sim.state
	var n := s.wave_index
	var bonus := sim.on_dawn(n)  # LT-99: the facade owns the dawn actions and their order
	sim.emit_event(SimEvent.Type.WAVE_CLEARED, 0, {"wave": n, "bonus": bonus})
	s.night_luck = 1.0  # LT-27 §1.2: the dawn resets the luck of an early night
	if n < s.waves_total:
		_begin_build(sim)
	else:
		s.phase = SimState.Phase.DONE
		_done = true


func _current_wave(s: SimState) -> WavesConfig.Wave:
	return _waves.waves[s.wave_index - 1]
