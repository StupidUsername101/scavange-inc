shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float visual_acuity = 0.8;
uniform float contrast_sensitivity = 0.75;
uniform float light_sensitivity = 0.7;
uniform float optical_quality = 0.75;
uniform float base_distortion = 0.01;
uniform float motion_smear = 0.2;
uniform float motion_intensity = 0.0;
uniform float external_distortion = 0.0;
uniform float external_glitch = 0.0;
uniform float external_smear = 0.0;
uniform vec2 distortion_center = vec2(0.5);
uniform float pulse_hz = 7.0;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 sample_smeared(vec2 uv, float amount, vec2 screen_pixel_size) {
	vec2 offset = vec2(screen_pixel_size.x * amount * 18.0, 0.0);
	vec3 center = texture(screen_texture, uv).rgb;
	vec3 left = texture(screen_texture, clamp(uv - offset, vec2(0.0), vec2(1.0))).rgb;
	vec3 right = texture(screen_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb;
	return mix(center, (left + center * 2.0 + right) * 0.25, clamp(amount, 0.0, 1.0));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - distortion_center;
	float pulse = 0.82 + 0.18 * sin(TIME * pulse_hz);
	float warp = base_distortion + external_distortion * 0.08 * pulse;
	uv += centered * dot(centered, centered) * warp;

	float line = floor(uv.y / max(SCREEN_PIXEL_SIZE.y * 5.0, 0.0001));
	float glitch_gate = step(1.0 - external_glitch * 0.18, hash21(vec2(line, floor(TIME * 18.0))));
	uv.x += (hash21(vec2(line, floor(TIME * 31.0))) - 0.5) * glitch_gate * external_glitch * 0.055;

	float smear = clamp(motion_intensity * motion_smear + external_smear, 0.0, 1.0);
	vec3 color = sample_smeared(
		clamp(uv, vec2(0.0), vec2(1.0)),
		smear,
		SCREEN_PIXEL_SIZE
	);

	float blur = (1.0 - visual_acuity) * 1.8;
	vec2 blur_offset = SCREEN_PIXEL_SIZE * blur;
	color = mix(
		color,
		(
			texture(screen_texture, clamp(uv + blur_offset, vec2(0.0), vec2(1.0))).rgb
			+ texture(screen_texture, clamp(uv - blur_offset, vec2(0.0), vec2(1.0))).rgb
		) * 0.5,
		1.0 - visual_acuity
	);

	color = (color - 0.5) * mix(0.82, 1.18, contrast_sensitivity) + 0.5;
	color *= mix(0.78, 1.08, light_sensitivity);
	color *= vec3(0.91, 1.035, 0.95);

	float scanline = 1.0 - 0.075 * (0.5 + 0.5 * sin(uv.y / SCREEN_PIXEL_SIZE.y * 3.14159265));
	float noise = (hash21(uv / SCREEN_PIXEL_SIZE + vec2(TIME * 47.0)) - 0.5) * (1.0 - optical_quality) * 0.075;
	float vignette = 1.0 - 0.22 * clamp(dot((SCREEN_UV - 0.5) * 1.5, (SCREEN_UV - 0.5) * 1.5), 0.0, 1.0);
	COLOR = vec4(max(color * scanline * vignette + noise, vec3(0.0)), 1.0);
}
