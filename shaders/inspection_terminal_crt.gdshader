shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D terminal_texture : source_color, filter_linear;
uniform vec4 phosphor_tint : source_color = vec4(0.72, 1.0, 0.78, 1.0);
uniform float curvature = 0.018;
uniform float scanline_strength = 0.14;
uniform float phosphor_mask_strength = 0.045;
uniform float vignette_strength = 0.34;
uniform float flicker_strength = 0.018;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	vec2 curved_uv = UV + centered * dot(centered, centered) * curvature;
	float in_bounds = (
		step(0.0, curved_uv.x)
		* step(curved_uv.x, 1.0)
		* step(0.0, curved_uv.y)
		* step(curved_uv.y, 1.0)
	);

	vec3 source = texture(terminal_texture, clamp(curved_uv, vec2(0.0), vec2(1.0))).rgb;
	float scanline = 1.0 - scanline_strength * (0.5 + 0.5 * sin(curved_uv.y * 510.0 * 3.14159265));
	float mask = 1.0 - phosphor_mask_strength * (0.5 + 0.5 * sin(curved_uv.x * 1340.0 * 2.0943951));
	float vignette = 1.0 - vignette_strength * clamp(dot(centered, centered) * 0.42, 0.0, 1.0);
	float flicker = 1.0 - flicker_strength * (0.5 + 0.5 * sin(TIME * 47.0));
	vec3 color = source * phosphor_tint.rgb * scanline * mask * vignette * flicker * in_bounds;

	ALBEDO = color;
	EMISSION = color * 1.18;
}
