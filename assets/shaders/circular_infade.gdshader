shader_type canvas_item;

uniform float circle_radius : hint_range(0.0, 2.0) = 0.0;
uniform vec2 center_point = vec2(0.5, 0.5);
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV - center_point;
	float dist = length(uv);
	
	// Circle of visibility: inside the circle = transparent (see game), outside = dark
	float circle = step(dist, circle_radius * 1.25);
	
	// Smooth edge for a less harsh transition
	float alpha = 1.0 - circle;
	
	COLOR = vec4(edge_color.rgb, edge_color.a * alpha);
}
