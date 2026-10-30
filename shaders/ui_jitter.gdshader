shader_type canvas_item;
// LT-14 UI jitter (GDD §9: "jitter at Whispers"). Moves only the drawn vertices of a HUD
// control, never the control itself, so its click area stays where it is.

uniform float jitter_px = 0.0;  // peak offset in pixels; 0 = off
uniform float rate = 11.0;  // new offsets per second
uniform float duty : hint_range(0.0, 1.0) = 0.45;  // share of steps that jump at all

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	vec2 seed = MODEL_MATRIX[3].xy;  // differs per control, so they twitch apart
	float s = floor(TIME * rate) + seed.x * 0.0131 + seed.y * 0.0717;
	float jump = step(1.0 - duty, hash(s * 1.37 + 0.5));
	vec2 off = vec2(hash(s), hash(s + 3.17)) * 2.0 - 1.0;
	VERTEX += off * jitter_px * jump;
}
