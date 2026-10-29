shader_type canvas_item;
// LT-8 sea fog: two layers of scrolling value-noise fbm drawn over water cells.
// Procedural (no noise texture) so it behaves the same in Compatibility / WebGL2.
// Uses the default light mode, so the lighthouse beam lights the fog too.

uniform vec4 fog_color : source_color = vec4(0.62, 0.68, 0.74, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.42;  // peak alpha
uniform float scale = 0.006;                            // noise frequency per pixel
uniform vec2 drift = vec2(0.035, 0.012);                // layer-1 speed, noise units per second

varying vec2 board_pos;

void vertex() {
	board_pos = VERTEX;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = board_pos * scale;
	float n1 = fbm(p + drift * TIME);
	float n2 = fbm(p * 1.7 - drift.yx * 1.6 * TIME + vec2(31.0, 7.0));
	float n = smoothstep(0.35, 0.85, 0.6 * n1 + 0.4 * n2);
	COLOR = vec4(fog_color.rgb, n * density);
}
