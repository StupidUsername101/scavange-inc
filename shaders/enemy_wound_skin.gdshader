shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

const int MAX_WOUNDS = 24;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap;
uniform bool has_albedo_texture = false;
uniform float material_roughness : hint_range(0.0, 1.0) = 0.8;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 wound_inner_color : source_color = vec3(0.92, 0.045, 0.025);
uniform vec3 wound_deep_color : source_color = vec3(0.16, 0.002, 0.004);
uniform int wound_count : hint_range(0, 24) = 0;
// xyz = animated entry point, w = radius.
uniform vec4 wound_entries[MAX_WOUNDS];
// xyz = direction into the body, w = shallow presentation-shell aperture depth. The authoritative
// SDF retains the projectile's complete penetration independently.
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
	float wound_rim = 0.0;
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
		// Clip only the tapered mouth in the imported presentation shell. Extending this to the
		// projectile's material penetration would delete the far side of the animated body.
		float depth_weight = clamp(axial / max(axis.w, 0.001), 0.0, 1.0);
		float local_radius = entry.w * mix(1.0, 0.58, depth_weight);
		if (axial >= -0.002 && axial <= axis.w && radial < local_radius) {
			discard;
		}
		// Break up the visually sterile edge left by clipping an imported animated shell. This is only
		// a narrow discoloration around the real SDF aperture, not a second fake wound primitive.
		float mouth_weight = 1.0 - smoothstep(entry.w * 0.45, entry.w * 2.2, max(axial, 0.0));
		float outer_rim = 1.0 - smoothstep(local_radius, local_radius * 1.65, radial);
		float inner_rim = smoothstep(local_radius * 0.94, local_radius * 1.08, radial);
		wound_rim = max(wound_rim, outer_rim * inner_rim * mouth_weight);
	}
	vec4 sampled = albedo_color;
	if (has_albedo_texture) {
		sampled *= texture(albedo_texture, UV);
	}
	if (sampled.a < 0.5) {
		discard;
	}
	if (FRONT_FACING) {
		ALBEDO = mix(sampled.rgb, vec3(0.19, 0.018, 0.012), wound_rim * 0.58);
		ROUGHNESS = material_roughness;
		METALLIC = material_metallic;
	} else {
		// Imported character skins are zero-thickness shells. Their back faces are the only natural
		// occluder behind an aperture; render those as deep tissue so a valid entry hole does not
		// expose the sky through the character when the ballistic SDF channel perforates.
		ALBEDO = mix(wound_inner_color, wound_deep_color, 0.72);
		ROUGHNESS = max(material_roughness, 0.88);
		METALLIC = 0.0;
		NORMAL = -NORMAL;
	}
}
