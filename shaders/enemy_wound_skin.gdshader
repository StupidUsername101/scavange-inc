shader_type spatial;
render_mode cull_back, depth_draw_opaque;

const int MAX_WOUNDS = 24;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform bool has_albedo_texture = false;
uniform float material_roughness : hint_range(0.0, 1.0) = 0.8;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform int wound_count : hint_range(0, 24) = 0;
// xyz = animated entry point, w = radius.
uniform vec4 wound_entries[MAX_WOUNDS];
// xyz = direction into the body, w = penetration depth.
uniform vec4 wound_axes[MAX_WOUNDS];


float wound_axis_distance(
	vec3 position,
	vec3 entry,
	vec3 direction,
	float depth,
	out float axis_distance
) {
	vec3 safe_direction = normalize(direction);
	axis_distance = clamp(dot(position - entry, safe_direction), -0.002, depth);
	vec3 axis_position = entry + safe_direction * axis_distance;
	return distance(position, axis_position);
}


void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	for (int wound_index = 0; wound_index < MAX_WOUNDS; wound_index++) {
		if (wound_index >= wound_count) {
			break;
		}
		vec4 entry = wound_entries[wound_index];
		vec4 axis = wound_axes[wound_index];
		float axial = 0.0;
		float radial = wound_axis_distance(
			world_position,
			entry.xyz,
			axis.xyz,
			max(axis.w, entry.w),
			axial
		);
		// Pull only a narrow ring of existing vertices inward. This keeps the untouched imported
		// surface intact while giving the fragment-cut opening a physically dented rim.
		float rim = smoothstep(entry.w * 1.65, entry.w * 0.92, radial);
		rim *= smoothstep(entry.w * 0.55, entry.w * 0.92, radial);
		float mouth = 1.0 - smoothstep(entry.w * 0.85, entry.w * 2.4, max(axial, 0.0));
		vec3 inward = normalize(axis.xyz);
		world_position += inward * entry.w * 0.22 * rim * mouth;
	}
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_position, 1.0)).xyz;
}


void fragment() {
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	for (int wound_index = 0; wound_index < MAX_WOUNDS; wound_index++) {
		if (wound_index >= wound_count) {
			break;
		}
		vec4 entry = wound_entries[wound_index];
		vec4 axis = wound_axes[wound_index];
		float axial = 0.0;
		float radial = wound_axis_distance(
			world_position,
			entry.xyz,
			axis.xyz,
			max(axis.w, entry.w),
			axial
		);
		// A tapered tunnel is the actual removed material. The old implementation discarded a
		// sphere and then placed another red sphere on top, which could never look like deformation.
		float depth_weight = clamp(axial / max(axis.w, 0.001), 0.0, 1.0);
		float local_radius = entry.w * mix(1.0, 0.58, depth_weight);
		if (axial >= -0.002 && axial <= axis.w && radial < local_radius) {
			discard;
		}
	}
	vec4 sampled = albedo_color;
	if (has_albedo_texture) {
		sampled *= texture(albedo_texture, UV);
	}
	if (sampled.a < 0.5) {
		discard;
	}
	ALBEDO = sampled.rgb;
	ROUGHNESS = material_roughness;
	METALLIC = material_metallic;
}
