shader_type canvas_item;
// Diagonal glass shine for CRT screen thumbnails (arcade console).
// Renders a translucent white band sweeping top-left -> bottom-right so the
// thumbnail looks like a glossy screen.

uniform vec4 gloss_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

void fragment() {
	// Diagonal axis (top-left low, bottom-right high).
	float d = UV.x + UV.y;
	// Bright band around the middle of the diagonal, soft falloff on both sides.
	float band = smoothstep(0.55, 0.85, d) - smoothstep(1.05, 1.35, d);
	// Fade toward the edges so the shine doesn't hard-clip at corners.
	float edge = smoothstep(0.0, 0.15, UV.x) * smoothstep(0.0, 0.15, UV.y);
	COLOR = vec4(1.0, 1.0, 1.0, band * edge * 0.35);
}
