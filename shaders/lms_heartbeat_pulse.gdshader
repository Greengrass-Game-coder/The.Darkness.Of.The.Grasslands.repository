shader_type canvas_item;
// LMS heartbeat circular red fade.
// A red vignette that is transparent in the middle and gets red toward the
// screen edges. The `intensity` uniform (0..1) is driven every frame by
// game_map.gd's _update_lms_heartbeat, so it throbs in sync with the camera
// zoom pulse at the exact same BPM.

uniform vec4 fade_color : source_color = vec4(0.82, 0.03, 0.02, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float aspect : hint_range(0.5, 3.0) = 1.7777;

void fragment() {
	vec2 c = UV - vec2(0.5, 0.5);
	c.x *= aspect; // widen X so the falloff is a true circle on any window shape
	float d = length(c);
	float max_d = length(vec2(0.5 * aspect, 0.5));
	float t = clamp(d / max_d, 0.0, 1.0); // 0 = center, 1 = corner
	// Circular fade: fully clear near the middle, red toward the edges.
	float edge = smoothstep(0.42, 0.97, t) * intensity;
	COLOR = vec4(fade_color.rgb, fade_color.a * edge);
}
