shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float visual_acuity = 0.96;
uniform float contrast_sensitivity = 0.94;
uniform float light_sensitivity = 0.76;
uniform float optical_quality = 0.94;
uniform float base_distortion = 0.004;
uniform float motion_smear = 0.08;
uniform float motion_intensity = 0.0;
uniform float external_distortion = 0.0;
uniform float external_glitch = 0.0;
uniform float external_smear = 0.0;
uniform vec2 distortion_center = vec2(0.5);
uniform float pulse_hz = 7.0;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(147.3, 229.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - distortion_center;
	float pulse = 0.9 + 0.1 * sin(TIME * pulse_hz);
	uv += centered * dot(centered, centered) * (
		base_distortion + external_distortion * 0.065 * pulse
	);

	float row = floor(uv.y / max(SCREEN_PIXEL_SIZE.y * 4.0, 0.0001));
	float glitch_gate = step(
		1.0 - external_glitch * 0.2,
		hash21(vec2(row, floor(TIME * 30.0)))
	);
	uv.x += (hash21(vec2(row + 7.0, floor(TIME * 30.0))) - 0.5) * glitch_gate * external_glitch * 0.07;

	vec2 sample_uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec3 center_color = texture(screen_texture, sample_uv).rgb;
	vec2 pixel = SCREEN_PIXEL_SIZE * mix(1.6, 0.45, visual_acuity);
	vec3 neighbors = (
		texture(screen_texture, clamp(sample_uv + vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0))).rgb
		+ texture(screen_texture, clamp(sample_uv - vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0))).rgb
		+ texture(screen_texture, clamp(sample_uv + vec2(0.0, pixel.y), vec2(0.0), vec2(1.0))).rgb
		+ texture(screen_texture, clamp(sample_uv - vec2(0.0, pixel.y), vec2(0.0), vec2(1.0))).rgb
	) * 0.25;
	vec3 color = center_color + (center_color - neighbors) * visual_acuity * 0.32;

	float smear = clamp(motion_intensity * motion_smear + external_smear, 0.0, 1.0);
	vec2 smear_offset = vec2(SCREEN_PIXEL_SIZE.x * smear * 24.0, 0.0);
	vec3 trail = texture(screen_texture, clamp(sample_uv - smear_offset, vec2(0.0), vec2(1.0))).rgb;
	color = mix(color, color * 0.78 + trail * 0.22, smear);

	color = (color - 0.5) * mix(0.9, 1.24, contrast_sensitivity) + 0.5;
	color *= mix(0.82, 1.08, light_sensitivity);
	color *= vec3(0.82, 1.02, 1.08);
	float scanline = 1.0 - 0.04 * (0.5 + 0.5 * sin(sample_uv.y / SCREEN_PIXEL_SIZE.y * 3.14159265));
	float noise = (hash21(sample_uv / SCREEN_PIXEL_SIZE + vec2(TIME * 61.0)) - 0.5) * (1.0 - optical_quality) * 0.04;
	float frame = smoothstep(0.0, 0.018, min(min(SCREEN_UV.x, 1.0 - SCREEN_UV.x), min(SCREEN_UV.y, 1.0 - SCREEN_UV.y)));
	COLOR = vec4(max(color * scanline * mix(0.82, 1.0, frame) + noise, vec3(0.0)), 1.0);
}
