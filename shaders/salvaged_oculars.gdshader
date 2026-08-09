shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float visual_acuity = 0.58;
uniform float contrast_sensitivity = 0.52;
uniform float light_sensitivity = 0.82;
uniform float optical_quality = 0.32;
uniform float base_distortion = 0.028;
uniform float motion_smear = 0.65;
uniform float motion_intensity = 0.0;
uniform float external_distortion = 0.0;
uniform float external_glitch = 0.0;
uniform float external_smear = 0.0;
uniform vec2 distortion_center = vec2(0.5);
uniform float pulse_hz = 7.0;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(91.7, 273.3))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - distortion_center;
	float quality_fault = 1.0 - optical_quality;
	float pulse = 0.65 + 0.35 * sin(TIME * pulse_hz + uv.y * 4.0);
	float warp = base_distortion + external_distortion * 0.12 * pulse;
	uv += centered * dot(centered, centered) * warp;

	float block_line = floor(uv.y / max(SCREEN_PIXEL_SIZE.y * 11.0, 0.0001));
	float tick = floor(TIME * mix(8.0, 25.0, quality_fault + external_glitch));
	float fault = step(
		1.0 - clamp(quality_fault * 0.055 + external_glitch * 0.34, 0.0, 0.8),
		hash21(vec2(block_line, tick))
	);
	float horizontal_jump = (hash21(vec2(tick, block_line + 5.0)) - 0.5) * fault;
	uv.x += horizontal_jump * (0.028 + external_glitch * 0.12);
	uv.y += sin(TIME * 1.7) * SCREEN_PIXEL_SIZE.y * quality_fault * 1.5;

	float smear = clamp(
		motion_intensity * motion_smear
		+ external_smear
		+ fault * 0.28,
		0.0,
		1.0
	);
	vec2 smear_offset = vec2(SCREEN_PIXEL_SIZE.x * (8.0 + 42.0 * smear), 0.0);
	vec2 sample_uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec3 base = texture(screen_texture, sample_uv).rgb;
	vec3 trail_a = texture(screen_texture, clamp(sample_uv - smear_offset, vec2(0.0), vec2(1.0))).rgb;
	vec3 trail_b = texture(screen_texture, clamp(sample_uv - smear_offset * 2.2, vec2(0.0), vec2(1.0))).rgb;
	vec3 color = mix(base, base * 0.52 + trail_a * 0.31 + trail_b * 0.17, smear);

	float chroma = quality_fault * 2.2 + external_glitch * 6.0;
	vec2 chroma_offset = vec2(SCREEN_PIXEL_SIZE.x * chroma, 0.0);
	color.r = texture(screen_texture, clamp(sample_uv + chroma_offset, vec2(0.0), vec2(1.0))).r;
	color.b = texture(screen_texture, clamp(sample_uv - chroma_offset, vec2(0.0), vec2(1.0))).b;

	color = (color - 0.5) * mix(0.78, 1.14, contrast_sensitivity) + 0.5;
	color *= mix(0.74, 1.14, light_sensitivity);
	color *= vec3(1.08, 0.84, 0.48);
	float scanline = 1.0 - 0.19 * (0.5 + 0.5 * sin(sample_uv.y / SCREEN_PIXEL_SIZE.y * 3.14159265));
	float noise = (hash21(sample_uv / SCREEN_PIXEL_SIZE + vec2(tick)) - 0.5) * (0.045 + quality_fault * 0.17);
	float vignette = 1.0 - 0.46 * clamp(dot((SCREEN_UV - 0.5) * 1.42, (SCREEN_UV - 0.5) * 1.42), 0.0, 1.0);
	COLOR = vec4(max(color * scanline * vignette + noise, vec3(0.0)), 1.0);
}
