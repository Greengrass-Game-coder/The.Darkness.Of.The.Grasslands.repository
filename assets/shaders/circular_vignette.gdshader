shader_type canvas_item;

// Circular vignette overlay: a filled circle that is faded in the middle so
// the player can always see the map / camera clearly at screen center.
uniform float intensity : hint_range(0.0, 1.0) = 0.55;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.55;
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);

void fragment() {
	vec2 uv = UV;
	vec2 c = vec2(0.5, 0.5);
	float d = distance(uv, c);
	// Fade from fully transparent at center to edge_color at the rim.
	float v = smoothstep(inner_radius, 1.0, d);
	COLOR = vec4(edge_color.rgb, edge_color.a * v * intensity);
}
