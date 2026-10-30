class_name WhisperAudio
extends Node
## LT-14 placeholder whispers (GDD §5.3: "audio whispers" from Whispers on). One looping
## sound generated in code at first use (band-passed noise in syllable-like bursts over a
## low detuned drone), no asset file. Its volume and pitch follow the sanity state.
## Web audio needs a user gesture: on the web build nothing plays before the first
## click or key press. Headless runs (tests, export) skip audio entirely.

const MIX_RATE := 22050
const LOOP_SECONDS := 3  ## whole seconds, so the drone's integer frequencies loop cleanly
const SILENT_DB := -60.0

## Per SimState.SanityState (Lucid, Whispers, Fraying, Madness). Visual-style tunables.
@export var state_volume_db: PackedFloat32Array = [-80.0, -20.0, -11.0, -5.0]
@export var state_pitch: PackedFloat32Array = [1.0, 1.0, 0.9, 0.75]
@export var fade_db_per_second := 30.0

static var _stream: AudioStreamWAV

var player: AudioStreamPlayer
var enabled := false  ## false in headless runs
var unlocked := false  ## true once audio may start (web: after the first input)
var _state := SimState.SanityState.LUCID


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		set_process(false)
		set_process_input(false)
		return
	unlocked = not OS.has_feature("web")
	player = AudioStreamPlayer.new()
	player.name = "Player"
	player.stream = loop_stream()
	player.volume_db = state_volume_db[0]
	add_child(player)


func _input(event: InputEvent) -> void:
	if unlocked:
		set_process_input(false)
		return
	if (event is InputEventMouseButton or event is InputEventKey
			or event is InputEventScreenTouch) and event.is_pressed():
		unlocked = true
		set_process_input(false)


func set_state(s: SimState.SanityState) -> void:
	_state = s


func _process(delta: float) -> void:
	var target := state_volume_db[_state]
	player.volume_db = move_toward(player.volume_db, target, fade_db_per_second * delta)
	player.pitch_scale = state_pitch[_state]
	var audible := unlocked and player.volume_db > SILENT_DB
	if audible and not player.playing:
		player.play()
	elif not audible and player.playing:
		player.stop()


## The whisper loop, built once per process.
static func loop_stream() -> AudioStreamWAV:
	if _stream != null:
		return _stream
	var n := MIX_RATE * LOOP_SECONDS
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1031  # presentation-only RNG, never the sim's
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var ph := t / LOOP_SECONDS  # 0..1 over the loop; integer cycles keep it seamless
		# Band-passed noise: a "breathy" hiss around 1-3 kHz.
		var white := rng.randf() * 2.0 - 1.0
		lp += 0.35 * (white - lp)
		lp2 += 0.08 * (lp - lp2)
		var hiss := lp - lp2
		# Syllable bursts: a few periodic envelopes at different integer rates.
		var env := pow(absf(sin(PI * ph * 7.0)), 6.0) * 0.7 \
			+ pow(absf(sin(PI * ph * 11.0 + 0.7)), 8.0) * 0.5 \
			+ pow(absf(sin(PI * ph * 5.0 + 1.9)), 10.0) * 0.6
		var drone := 0.18 * sin(TAU * 55.0 * t) + 0.12 * sin(TAU * 82.0 * t) \
			+ 0.06 * sin(TAU * 110.0 * t + 0.5 * sin(TAU * ph * 2.0))
		var v := clampf(hiss * env * 2.6 + drone * 0.5, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	_stream = AudioStreamWAV.new()
	_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_stream.mix_rate = MIX_RATE
	_stream.stereo = false
	_stream.data = data
	_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_stream.loop_begin = 0
	_stream.loop_end = n
	return _stream
