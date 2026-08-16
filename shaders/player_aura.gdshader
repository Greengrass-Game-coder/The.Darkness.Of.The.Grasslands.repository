shader_type canvas_item;

// LMS character aura: draws a pulsing colored rim-glow around the sprite's
// silhouette (red/black for Violentgrass, green/black for Greengrass) while
// keeping the original sprite visible in the center. The glow self-pulses
// using TIME so no infinite animation loop / tween is needed.

uniform vec4 aura_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float aura_strength : hint_range(0.0, 1.0) = 1.0; // overall intensity
uniform float glow_size : hint_range(0.0, 0.15) = 0.045;    // rim thickness (uv units)
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.4;     // pulse frequency
uniform bool enabled = true;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 col = base;

	if (enabled) {
		// Smooth breathing pulse (0.75..1.0) so the aura shimmers.
		float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
		float strength = aura_strength * pulse;

		// Sample the surrounding alpha in a small ring to detect silhouette edges.
		float rim = 0.0;
		float step = glow_size;
		int samples = 8;
		for (int i = 0; i < samples; i++) {
			float ang = float(i) / float(samples) * 6.2831853;
			vec2 off = vec2(cos(ang), sin(ang)) * step;
			float a = texture(TEXTURE, UV + off).a;
			rim = max(rim, a);
		}

		// Where the rim is bright but the center pixel is transparent, paint aura.
		if (base.a < 0.5 && rim > 0.5) {
			// Colored glow on the rim.
			col.rgb = mix(base.rgb, aura_color.rgb, 0.85);
			col.a = max(base.a, rim * strength * 0.9);
		}
		// Slight red/green tint halo in the semi-transparent fringe.
		else if (base.a < 0.85) {
			col.rgb = mix(base.rgb, aura_color.rgb, 0.25 * strength);
		}
	}

	COLOR = col;
}
