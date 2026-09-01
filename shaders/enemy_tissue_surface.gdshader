shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform float material_roughness : hint_range(0.0, 1.0) = 0.88;
uniform float material_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float dark_visibility : hint_range(0.0, 0.25) = 0.055;


void fragment() {
	// Vertex color is authored from actual SDF depth: fresh tissue starts bright red and darkens
	// inward. A tiny unshaded contribution keeps a cavity identifiable in this deliberately dark
	// game without turning flesh into an emissive prop.
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * dark_visibility;
	ROUGHNESS = material_roughness;
	METALLIC = material_metallic;
}
