shader_type canvas_item;
render_mode unshaded;
// LT-14 sanity screen effect: a full-screen rect on a CanvasLayer between the world and
// the HUD. Wavy distortion, chromatic aberration and a vignette, all scaled by
// SanityFx from the sanity level, plus a desaturated red "madness" grade. The HUD is
// drawn above this layer, so it is never distorted. Compatibility / WebGL2 safe.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float distortion = 0.0;  // peak UV offset in pixels
uniform float aberration = 0.0;  // red/blue split at the screen edge, in pixels
uniform float vignette : hint_range(0.0, 1.0) = 0.0;  // edge darkening
uniform float madness : hint_range(0.0, 1.0) = 0.0;  // madness grade
uniform float pulse : hint_range(0.0, 1.0) = 0.0;  // short jolt on a threshold change
uniform vec4 vignette_color : source_color = vec4(0.02, 0.04, 0.03, 1.0);
uniform vec4 madness_tint : source_color = vec4(1.0, 0.42, 0.38, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	float t = TIME;
	float amount = distortion * (1.0 + 2.0 * pulse);
	vec2 wave = vec2(
		sin(uv.y * 23.0 + t * 1.9) + 0.6 * sin(uv.y * 61.0 - t * 3.1),
		cos(uv.x * 17.0 + t * 1.4) + 0.6 * cos(uv.x * 47.0 + t * 2.3));
	uv += wave * 0.5 * amount * px;

	vec2 from_centre = uv - vec2(0.5);
	float edge = length(from_centre * vec2(1.0, 0.75)) * 2.0;  // ~0 centre, ~1 corners
	vec2 split = normalize(from_centre + vec2(1e-5)) * aberration * (0.3 + edge) * px;
	vec3 col;
	col.r = texture(screen_tex, uv + split).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - split).b;

	float vig = smoothstep(0.35, 1.15, edge) * clamp(vignette + 0.3 * pulse, 0.0, 1.0);
	col = mix(col, vignette_color.rgb, vig);

	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 graded = vec3(lum) * madness_tint.rgb * 1.5;
	col = mix(col, graded, madness * 0.6);
	float throb = 0.65 + 0.35 * sin(t * 2.6);
	col += vec3(0.30, 0.0, 0.03) * smoothstep(0.55, 1.2, edge) * madness * throb;

	COLOR = vec4(col, 1.0);
}
