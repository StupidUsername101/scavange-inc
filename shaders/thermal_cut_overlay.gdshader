shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

const int MAX_THERMAL_CUTS = 24;

// xyz = entry in the owning mesh's local space, w = removed channel radius.
uniform vec4 cut_entries[MAX_THERMAL_CUTS];
// xyz = direction into the material, w = channel depth.
uniform vec4 cut_axes[MAX_THERMAL_CUTS];
// x = start clock, y = cooling duration, z = heat intensity.
uniform vec4 cut_lifetimes[MAX_THERMAL_CUTS];
uniform int cut_count : hint_range(0, 24) = 0;
uniform float thermal_clock_seconds = 0.0;
uniform vec3 molten_hot_color : source_color = vec3(1.0, 0.82, 0.28);
uniform vec3 molten_cool_color : source_color = vec3(1.0, 0.055, 0.008);

varying vec3 cut_local_position;


void vertex() {
	cut_local_position = VERTEX;
}


void fragment() {
	float strongest_heat = 0.0;
	float hottest_core = 0.0;
	for (int cut_index = 0; cut_index < MAX_THERMAL_CUTS; cut_index++) {
		if (cut_index >= cut_count) {
			break;
		}
		vec4 lifetime = cut_lifetimes[cut_index];
		float age = thermal_clock_seconds - lifetime.x;
		if (age < 0.0 || age >= lifetime.y || lifetime.z <= 0.0) {
			continue;
		}
		vec4 entry = cut_entries[cut_index];
		vec4 axis = cut_axes[cut_index];
		vec3 direction = normalize(axis.xyz);
		float axial = clamp(
			dot(cut_local_position - entry.xyz, direction),
			-entry.w * 0.38,
			max(axis.w, entry.w) + entry.w * 0.38
		);
		vec3 centerline = entry.xyz + direction * axial;
		float radial = distance(cut_local_position, centerline);
		// The removed SDF surface lies near the channel radius. Heating that narrow band produces
		// molten cut walls and a hot lip without painting a luminous cylinder across intact material.
		float rim_distance = abs(radial - entry.w * 0.88);
		float band_width = max(entry.w * 0.92, 0.006);
		float spatial_heat = 1.0 - smoothstep(0.0, band_width, rim_distance);
		float end_softness = entry.w * 1.25;
		float end_heat = smoothstep(
			-entry.w * 0.38 - end_softness,
			-entry.w * 0.38,
			axial
		) * (1.0 - smoothstep(
			max(axis.w, entry.w) + entry.w * 0.38,
			max(axis.w, entry.w) + entry.w * 0.38 + end_softness,
			axial
		));
		float cooling = clamp(1.0 - age / max(lifetime.y, 0.001), 0.0, 1.0);
		// Cooling is intentionally nonlinear: a white-hot center collapses quickly into a longer,
		// dim red afterglow instead of linearly looking like its opacity slider is being reduced.
		float thermal_energy = spatial_heat * end_heat * lifetime.z * cooling * cooling;
		strongest_heat = max(strongest_heat, thermal_energy);
		hottest_core = max(hottest_core, thermal_energy * thermal_energy);
	}
	if (strongest_heat <= 0.001) {
		discard;
	}
	vec3 temperature_color = mix(
		molten_cool_color,
		molten_hot_color,
		clamp(hottest_core * 1.35, 0.0, 1.0)
	);
	ALBEDO = temperature_color * 0.18;
	EMISSION = temperature_color * (1.7 + strongest_heat * 7.5);
	ALPHA = clamp(strongest_heat, 0.0, 1.0);
}
