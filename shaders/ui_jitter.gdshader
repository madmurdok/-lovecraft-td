shader_type canvas_item;
// LT-14 UI jitter (GDD §9: "jitter at Whispers"). Moves only the drawn vertices of a HUD
// control, never the control itself, so its click area stays where it is.

uniform float jitter_px = 0.0;  // peak offset in pixels; 0 = off
uniform float rate = 11.0;  // new offsets per second (set by SanityFx.ui_jitter_rate)
uniform float duty : hint_range(0.0, 1.0) = 0.45;  // share of steps that jump at all

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

// Offset of one step: a random point in [-1, 1]^2 on `duty` of the steps, else 0.
vec2 step_offset(float s) {
	float jump = step(1.0 - duty, hash(s * 1.37 + 0.5));
	return (vec2(hash(s), hash(s + 3.17)) * 2.0 - 1.0) * jump;
}

void vertex() {
	vec2 seed = MODEL_MATRIX[3].xy;  // differs per control, so they sway apart
	float t = TIME * rate;
	float s = floor(t) + seed.x * 0.0131 + seed.y * 0.0717;
	// LT-40 J1: ease from this step's offset to the next one, a sway rather than a twitch.
	vec2 off = mix(step_offset(s), step_offset(s + 1.0), smoothstep(0.0, 1.0, fract(t)));
	VERTEX += off * jitter_px;
}
