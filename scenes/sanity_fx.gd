class_name SanityFx
extends Node
## LT-14 sanity feedback (GDD §5.3 table, §9, §9a), presentation only: reads
## `game.sim.state.sanity` / `sanity_state` and the sanity.json thresholds, never changes
## the sim. Owns the full-screen distortion layer (between the world and the HUD), the
## shared UI jitter material and the whisper audio. Board and HUD read `state`, `level`,
## `flicker` and `ui_jitter_material` from here.
##
## What each threshold shows / plays:
## - Lucid: nothing (the screen layer is hidden).
## - Whispers: whisper loop, HUD jitter, light distortion / aberration / vignette.
## - Fraying: louder whispers, stronger screen effects, flicker on every enemy, phantom
##   path flicker, distorted sanity bar.
## - Madness: every effect at its maximum plus the red madness grade.
## All strengths below are visual tunables, not balance numbers.

const SCREEN_SHADER := preload("res://shaders/sanity_screen.gdshader")
const JITTER_SHADER := preload("res://shaders/ui_jitter.gdshader")
const SCREEN_LAYER := 1  ## the HUD CanvasLayer sits above it (Game.UI_LAYER)

## Effect level per threshold state (0..1); within Whispers / Fraying the level slides
## from its own value towards the next state's as sanity falls.
@export var state_levels: PackedFloat32Array = [0.0, 0.3, 0.62, 1.0]
@export var max_distortion_px := 5.0
@export var max_aberration_px := 6.0
@export var max_vignette := 0.7
@export var max_ui_jitter_px := 2.5
@export var max_flicker := 0.85  ## enemy alpha dip at full strength (Fraying low end, Madness)
@export var level_speed := 1.5  ## displayed level change per second (smooths jumps)
@export var pulse_seconds := 0.8  ## jolt after a threshold change

var game: Game
var state := SimState.SanityState.LUCID
var level := 0.0  ## smoothed 0..1
var pulse := 0.0  ## 1 right after a threshold change, decays to 0
var madness := 0.0  ## smoothed 0..1 madness grade
var flicker := 0.0  ## enemy flicker strength (0 below Fraying); same for every enemy
var ui_jitter_material: ShaderMaterial
var screen_layer: CanvasLayer
var screen_rect: ColorRect
var screen_material: ShaderMaterial
var audio: WhisperAudio


func _ready() -> void:
	ui_jitter_material = ShaderMaterial.new()
	ui_jitter_material.shader = JITTER_SHADER
	screen_layer = CanvasLayer.new()
	screen_layer.name = "SanityScreen"
	screen_layer.layer = SCREEN_LAYER
	add_child(screen_layer)
	screen_rect = ColorRect.new()
	screen_rect.name = "Distortion"
	screen_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eats a board click
	screen_material = ShaderMaterial.new()
	screen_material.shader = SCREEN_SHADER
	screen_rect.material = screen_material
	screen_layer.add_child(screen_rect)
	audio = WhisperAudio.new()
	audio.name = "WhisperAudio"
	add_child(audio)
	_snap()


## Called by Game for every sim event; only the threshold change matters here.
func on_event(ev: SimEvent) -> void:
	if ev.type == SimEvent.Type.SANITY_STATE_CHANGED:
		pulse = 1.0


func _process(delta: float) -> void:
	tick(delta)


## One frame of smoothing, then pushes the values to the shaders and the audio.
func tick(delta: float) -> void:
	var s := game.sim.state
	state = s.sanity_state
	level = move_toward(level, target_level(), level_speed * delta)
	var mad_target := 1.0 if state == SimState.SanityState.MADNESS else 0.0
	madness = move_toward(madness, mad_target, level_speed * delta)
	pulse = maxf(0.0, pulse - delta / pulse_seconds)
	_apply()


## Jumps straight to the current target (start of a run, tests, screenshots).
func _snap() -> void:
	state = game.sim.state.sanity_state
	level = target_level()
	madness = 1.0 if state == SimState.SanityState.MADNESS else 0.0
	_apply()


## The level the current sanity asks for (GDD §5.3 table, thresholds from sanity.json).
func target_level() -> float:
	var s := game.sim.state
	var i := int(s.sanity_state)
	if i <= SimState.SanityState.LUCID:
		return state_levels[0]
	if i >= SimState.SanityState.MADNESS:
		return state_levels[3]
	var th := game.sim.config.sanity.thresholds
	var top := th[SanityConfig.STATES[i - 1]].min_sanity
	var bottom := th[SanityConfig.STATES[i]].min_sanity
	var p := clampf((top - s.sanity) / maxf(top - bottom, 0.001), 0.0, 1.0)
	return lerpf(state_levels[i], state_levels[i + 1], p)


func _apply() -> void:
	var fraying := state >= SimState.SanityState.FRAYING
	var whispers := state >= SimState.SanityState.WHISPERS
	# Fraying flicker grows with the level and stays at its maximum in Madness (§5.4).
	var f_lo := state_levels[SimState.SanityState.FRAYING]
	flicker = max_flicker * clampf(0.55 + 0.45 * (level - f_lo) / maxf(1.0 - f_lo, 0.001),
		0.0, 1.0) if fraying else 0.0
	ui_jitter_material.set_shader_parameter("jitter_px",
		max_ui_jitter_px * (0.6 + 0.4 * level) if whispers else 0.0)
	screen_material.set_shader_parameter("distortion", max_distortion_px * level)
	screen_material.set_shader_parameter("aberration", max_aberration_px * level)
	screen_material.set_shader_parameter("vignette", max_vignette * level)
	screen_material.set_shader_parameter("madness", madness)
	screen_material.set_shader_parameter("pulse", pulse)
	# Lucid costs nothing: the screen copy only runs while something is shown.
	screen_rect.visible = level > 0.001 or pulse > 0.0 or madness > 0.0
	audio.set_state(state)
