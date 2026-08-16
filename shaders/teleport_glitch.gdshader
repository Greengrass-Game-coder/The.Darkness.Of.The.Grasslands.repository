shader_type canvas_item;

// Teleport glitch overlay for Violentgrass: a red, glitchy full-screen flicker
// that plays while the killer is teleporting. Samples the live SCREEN texture
// underneath and pushes it hard toward red with slice-tear + flicker, so the
// whole viewport looks red and glitchy. Driven by TIME and INTENSITY uniforms.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float time : hint_range(0.0, 60.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.6;
uniform vec4 tint : source_color = vec4(1.0, 0.02, 0.02, 1.0);

float rand_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 base = texture(SCREEN_TEXTURE, uv);

	// Horizontal "slice" displacement — classic screen-tear glitch.
	float slices = 12.0 + 12.0 * intensity;
	float slice_id = floor(uv.y * slices);
	float slice_rand = rand_hash(vec2(slice_id, floor(time * 36.0)));
	float offset = (slice_rand - 0.5) * 0.22 * intensity;
	vec2 tear_uv = uv;
	tear_uv.x = fract(tear_uv.x + offset);
	vec3 col = texture(SCREEN_TEXTURE, tear_uv).rgb;

	// Red dominance: push color toward tint (red) hard.
	col = mix(col, tint.rgb, 0.85 * intensity);

	// Flicker: random dark bands sweep up/down.
	float flick = rand_hash(vec2(floor(time * 28.0), floor(uv.y * 9.0)));
	col *= 0.7 + 0.6 * flick;

	// Scanlines (subtle).
	float scan = sin(uv.y * 900.0 + time * 22.0) * 0.5 + 0.5;
	col *= 0.8 + 0.2 * scan;

	// Global alpha = intensity so the overlay fades in/out with it.
	float a = clamp(intensity, 0.0, 1.0);
	COLOR = vec4(col, a);
}
