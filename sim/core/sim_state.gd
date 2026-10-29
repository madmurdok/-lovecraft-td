class_name SimState
extends RefCounted
## Everything the simulation knows; scenes read it directly, read-only (design note LT-4 §1.4).

enum Outcome {NONE, WON, LOST}

var tick := 0  ## completed steps; the first step() runs tick 1
var outcome := Outcome.NONE  ## once not NONE, step() is a no-op
var lighthouse_hp := 0
var map: MapDef
var enemies: Array[SimEnemy] = []  ## id order
var next_id := 1  ## shared by every entity; never reused
var command_log: Array = []  ## [tick, command...] entries (LT-5/LT-6 add commands)
