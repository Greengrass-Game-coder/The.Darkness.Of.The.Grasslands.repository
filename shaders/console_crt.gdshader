shader_type canvas_item;
// Subtle old-console / prototype CRT post-process overlay.
//
// Deliberately gentle: a touch of pixelation, faint scanlines, a barely-visible
// barrel curvature + vignette, and optional static noise that is ONLY raised
// while the console is loading. It is meant to feel like an old, slightly
// imperfect prototype console — NOT a glitchy horror screen. Text stays easy to
// read because every effect stays low.

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;

uniform float noise_amount : hint_range(0.0, 1.0) = 0.0;
uniform float pixel_scale : hint_range(1.0, 8.0) = 2.0;
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.10;
uniform float curvature : hint_range(0.0, 0.2) = 0.02;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.20;

void fragment() {
	// Barely-visible barrel bulge toward the screen edges.
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5, 0.5);
	vec2 off = uv - center;
	uv = center + off * (1.0 - curvature * dot(off, off));

	// Slight pixelation: sample the screen in small chunky blocks.
	vec2 px = pixel_scale * SCREEN_PIXEL_SIZE;
	vec2 block = floor(uv / px) * px;
	vec3 col = texture(SCREEN_TEXTURE, block).rgb;

	// Faint scanlines: darken alternating pixel rows just a little.
	float line = fract(uv.y / SCREEN_PIXEL_SIZE.y * 0.5);
	col *= 1.0 - scanline_strength * smoothstep(0.5, 1.0, line);

	// Very subtle vignette (darker corners) for the old-tube look.
	float vig = smoothstep(0.45, 1.05, length(off) * 1.5);
	col *= mix(1.0, 0.88, vignette_strength * vig);

	// Static noise — only appears while loading (noise_amount > 0).
	if (noise_amount > 0.0) {
		vec2 seed = block * SCREEN_PIXEL_SIZE * vec2(197.0, 311.0) + vec2(TIME * 1.3, TIME * 0.9);
		float n = fract(sin(dot(seed, vec2(12.9898, 78.233))) * 43758.5453);
		col += (n - 0.5) * noise_amount;
	}

	COLOR = vec4(col, 1.0);
}
