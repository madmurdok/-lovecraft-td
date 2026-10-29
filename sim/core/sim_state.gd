class_name SimState
extends RefCounted
## Everything the simulation knows; scenes read it directly, read-only (design note LT-4 §1.4).

enum Outcome {NONE, WON, LOST}
## Wave flow (LT-5). NONE = no WaveDirector attached (tests with ScriptedSpawner);
## DONE = the last wave was cleared (the win follows in the same tick).
enum Phase {NONE, BUILD, WAVE, DONE}

var tick := 0  ## completed steps; the first step() runs tick 1
var outcome := Outcome.NONE  ## once not NONE, step() is a no-op
var lighthouse_hp := 0
var map: MapDef
var enemies: Array[SimEnemy] = []  ## id order
var next_id := 1  ## shared by every entity; never reused
var command_log: Array = []  ## [tick, command...] entries (LT-5/LT-6 add commands)
var gold := 0  ## from economy.starting_gold; never negative
var towers: Array[SimTower] = []  ## id order
var tower_at: Dictionary[Vector2i, int] = {}  ## occupied cell -> tower id
var phase := Phase.NONE
var wave_index := 0  ## 1-based number of the current or last started wave; 0 before wave 1
var waves_total := 0  ## number of waves in waves.json (0 without a WaveDirector)
var build_ticks_left := 0  ## ticks until the next wave starts by itself; 0 outside BUILD
