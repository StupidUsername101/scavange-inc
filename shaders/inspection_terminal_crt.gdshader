shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D terminal_texture : source_color, filter_linear;
uniform vec4 phosphor_tint : source_color = vec4(0.72, 1.0, 0.78, 1.0);
uniform vec4 terminal_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float curvature = 0.018;
uniform float scanline_strength = 0.14;
uniform float phosphor_mask_strength = 0.045;
uniform float vignette_strength = 0.34;
uniform float flicker_strength = 0.018;
uniform float glitch_strength = 0.0;
uniform float glitch_tick_rate = 6.0;
uniform float glitch_event_chance = 0.0;
uniform float glitch_band_chance = 0.0;
uniform float glitch_chroma_strength = 0.0;
uniform float glitch_luma_flutter = 0.0;
uniform float acoustic_glitch_drive = 0.0;
uniform float acoustic_glitch_event_lift = 0.0;
uniform float refresh_line_min_speed = 0.1;
uniform float refresh_line_max_speed = 0.1;
uniform float refresh_line_width = 0.0;
uniform float refresh_line_opacity = 0.0;
uniform float refresh_line_distortion_min = 0.0;
uniform float refresh_line_distortion_max = 0.0;
uniform float refresh_line_point_count = 1.0;
uniform float refresh_line_point_min_strength = 1.0;
uniform float refresh_line_point_max_strength = 1.0;
uniform float refresh_start_time = 0.0;
uniform float phosphor_decay_per_second = 0.0;
uniform float phosphor_brightness_floor = 1.0;
uniform float grit_strength = 0.0;
uniform float grit_tick_rate = 10.0;
uniform vec2 grit_grid = vec2(360.0, 260.0);
uniform float grit_speck_chance = 0.0;
uniform float grit_age_influence = 0.0;
uniform vec2 terminal_texel_size = vec2(0.001388889, 0.001923077);
uniform float neon_glow_radius_pixels = 1.0;
uniform float neon_glow_strength = 0.0;
uniform float color_bleed_strength = 0.0;

float fieldlink_hash(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 display_uv = (
		UV - terminal_uv_rect.xy
	) / max(terminal_uv_rect.zw, vec2(0.000001));
	vec2 centered = display_uv * 2.0 - 1.0;
	vec2 curved_uv = display_uv + centered * dot(centered, centered) * curvature;
	float effective_glitch_event_chance = clamp(
		glitch_event_chance
		+ acoustic_glitch_event_lift * clamp(acoustic_glitch_drive, 0.0, 1.0),
		0.0,
		0.45
	);
	float glitch_tick = floor(TIME * max(glitch_tick_rate, 0.001));
	float glitch_active = step(
		1.0 - effective_glitch_event_chance,
		fieldlink_hash(vec2(glitch_tick, 19.73))
	);
	float glitch_band = floor(display_uv.y * 52.0);
	float band_active = glitch_active * step(
		1.0 - glitch_band_chance,
		fieldlink_hash(vec2(glitch_band, glitch_tick + 3.17))
	);
	float band_direction = (
		fieldlink_hash(vec2(glitch_tick + 8.31, glitch_band)) * 2.0 - 1.0
	);
	curved_uv.x += band_active * band_direction * glitch_strength;
	float refresh_line_mask = 0.0;
	float phosphor_persistence = 1.0;
	float phosphor_age = 0.0;
	float refresh_horizontal_offset = 0.0;
	if (
		refresh_line_opacity > 0.0
		|| phosphor_decay_per_second > 0.0
		|| refresh_line_distortion_max > 0.0
	) {
		float minimum_refresh_speed = max(refresh_line_min_speed, 0.001);
		float maximum_refresh_speed = max(
			refresh_line_max_speed,
			minimum_refresh_speed
		);
		float refresh_elapsed = mod(
			TIME - refresh_start_time + 3600.0,
			3600.0
		);
		float minimum_distortion = max(
			min(refresh_line_distortion_min, refresh_line_distortion_max),
			0.0
		);
		float maximum_distortion = max(
			max(refresh_line_distortion_min, refresh_line_distortion_max),
			minimum_distortion
		);
		float time_since_refresh = 1000000.0;
		for (int line_index = 0; line_index < 3; line_index++) {
			float line_seed = float(line_index) + 41.0;
			float line_speed = mix(
				minimum_refresh_speed,
				maximum_refresh_speed,
				fieldlink_hash(vec2(line_seed, 7.31))
			);
			float line_travel = refresh_elapsed * line_speed;
			float line_position = fract(line_travel);
			float distance_to_line = abs(display_uv.y - line_position);
			float current_line_mask = 1.0 - smoothstep(
				0.0,
				max(refresh_line_width, 0.000001),
				distance_to_line
			);
			float line_cycle = floor(line_travel);
			float point_position = (
				display_uv.x * max(refresh_line_point_count, 1.0)
			);
			float point_index = floor(point_position);
			float point_blend = smoothstep(
				0.0,
				1.0,
				fract(point_position)
			);
			float point_seed = line_seed * 31.7 + line_cycle * 17.3;
			float point_noise = mix(
				fieldlink_hash(vec2(point_index, point_seed)),
				fieldlink_hash(vec2(point_index + 1.0, point_seed)),
				point_blend
			);
			float point_strength = mix(
				refresh_line_point_min_strength,
				refresh_line_point_max_strength,
				point_noise
			);
			float shaped_line_mask = current_line_mask * point_strength;
			refresh_line_mask = max(refresh_line_mask, shaped_line_mask);
			float distortion_direction = mix(
				-1.0,
				1.0,
				step(
					0.5,
					fieldlink_hash(vec2(line_seed * 5.13, line_cycle + 67.1))
				)
			);
			float distortion_magnitude = mix(
				minimum_distortion,
				maximum_distortion,
				fieldlink_hash(vec2(line_seed * 9.47, line_cycle + 113.9))
			);
			refresh_horizontal_offset += (
				shaped_line_mask
				* distortion_direction
				* distortion_magnitude
			);
			float phase_since_pass = mod(
				line_position - display_uv.y + 1.0,
				1.0
			);
			time_since_refresh = min(
				time_since_refresh,
				phase_since_pass / line_speed
			);
		}
		phosphor_persistence = max(
			clamp(phosphor_brightness_floor, 0.0, 1.0),
			exp(
				-max(phosphor_decay_per_second, 0.0)
				* time_since_refresh
			)
		);
		phosphor_age = clamp(
			(1.0 - phosphor_persistence)
			/ max(1.0 - phosphor_brightness_floor, 0.000001),
			0.0,
			1.0
		);
	}
	refresh_horizontal_offset = clamp(
		refresh_horizontal_offset,
		-refresh_line_distortion_max,
		refresh_line_distortion_max
	);
	curved_uv.x += refresh_horizontal_offset;
	float in_bounds = (
		step(0.0, curved_uv.x)
		* step(curved_uv.x, 1.0)
		* step(0.0, curved_uv.y)
		* step(curved_uv.y, 1.0)
	);

	vec2 safe_curved_uv = clamp(curved_uv, vec2(0.0), vec2(1.0));
	vec3 source = texture(terminal_texture, safe_curved_uv).rgb;
	if (band_active > 0.0 && glitch_chroma_strength > 0.0) {
		vec2 chroma_offset = vec2(
			band_direction * glitch_chroma_strength,
			0.0
		);
		float shifted_red = texture(
			terminal_texture,
			clamp(safe_curved_uv + chroma_offset, vec2(0.0), vec2(1.0))
		).r;
		float shifted_blue = texture(
			terminal_texture,
			clamp(safe_curved_uv - chroma_offset, vec2(0.0), vec2(1.0))
		).b;
		source = vec3(shifted_red, source.g, shifted_blue);
		float band_flutter = fieldlink_hash(vec2(glitch_band + 71.3, glitch_tick));
		source *= 1.0 + (
			band_flutter * 2.0 - 1.0
		) * glitch_luma_flutter;
	}
	vec3 neon_glow = vec3(0.0);
	if (neon_glow_strength > 0.0 || color_bleed_strength > 0.0) {
		vec2 glow_step = (
			terminal_texel_size * max(neon_glow_radius_pixels, 0.0)
		);
		vec3 left_sample = texture(
			terminal_texture,
			clamp(curved_uv - vec2(glow_step.x, 0.0), vec2(0.0), vec2(1.0))
		).rgb;
		vec3 right_sample = texture(
			terminal_texture,
			clamp(curved_uv + vec2(glow_step.x, 0.0), vec2(0.0), vec2(1.0))
		).rgb;
		vec3 upper_sample = texture(
			terminal_texture,
			clamp(curved_uv - vec2(0.0, glow_step.y), vec2(0.0), vec2(1.0))
		).rgb;
		vec3 lower_sample = texture(
			terminal_texture,
			clamp(curved_uv + vec2(0.0, glow_step.y), vec2(0.0), vec2(1.0))
		).rgb;
		neon_glow = (
			left_sample + right_sample + upper_sample + lower_sample
		) * 0.25;
		vec3 chromatic_bleed = vec3(
			left_sample.r,
			(upper_sample.g + lower_sample.g) * 0.5,
			right_sample.b
		);
		source = mix(source, chromatic_bleed, color_bleed_strength);
	}
	float scanline = 1.0 - scanline_strength * (0.5 + 0.5 * sin(curved_uv.y * 510.0 * 3.14159265));
	float mask = 1.0 - phosphor_mask_strength * (0.5 + 0.5 * sin(curved_uv.x * 1340.0 * 2.0943951));
	float vignette = 1.0 - vignette_strength * clamp(dot(centered, centered) * 0.42, 0.0, 1.0);
	float flicker = 1.0 - flicker_strength * (0.5 + 0.5 * sin(TIME * 47.0));
	vec3 color = source * phosphor_persistence * phosphor_tint.rgb * scanline * mask * vignette * flicker * in_bounds;
	float source_luminance = dot(source, vec3(0.2126, 0.7152, 0.0722));
	color += (
		phosphor_tint.rgb
		* refresh_line_mask
		* refresh_line_opacity
		* (0.018 + source_luminance * 0.24)
		* vignette
		* in_bounds
	);
	color += (
		neon_glow
		* neon_glow_strength
		* phosphor_persistence
		* vignette
		* in_bounds
	);
	if (grit_strength > 0.0) {
		float aged_grit_strength = grit_strength * mix(
			0.55,
			1.0 + grit_age_influence,
			phosphor_age
		);
		float aged_speck_chance = grit_speck_chance * mix(
			0.35,
			1.0,
			phosphor_age
		);
		float grit_tick = floor(TIME * max(grit_tick_rate, 0.001));
		vec2 grit_cell = floor(
			display_uv * max(grit_grid, vec2(1.0))
		);
		float grit_noise = fieldlink_hash(
			grit_cell + vec2(grit_tick * 5.0, grit_tick * 13.0)
		);
		float grit_variation = (
			(grit_noise * 2.0 - 1.0) * aged_grit_strength
		);
		float grit_speck = step(
			1.0 - aged_speck_chance,
			fieldlink_hash(grit_cell + vec2(grit_tick * 17.0, 91.3))
		);
		color *= max(
			1.0 + grit_variation - grit_speck * aged_grit_strength * 1.8,
			0.0
		);
		color += (
			phosphor_tint.rgb
			* max(grit_variation, 0.0)
			* 0.012
			* in_bounds
		);
	}

	ALBEDO = color;
	EMISSION = color * 1.18;
}
