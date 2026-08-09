@tool
class_name RopeDefinition
extends ItemDefinition

#######################################################
# Defines the serialized rope configuration shared by gameplay, inspection, and replication
# systems.
#######################################################

enum VisualEffect {
	NONE,
	CURRENT_PULSE,
	FIBER_PULSE,
}

@export_group("Rope Identity")
@export var rope_color := Color(0.55, 0.46, 0.32, 1.0)
@export var visual_effect: VisualEffect = VisualEffect.NONE
@export var effect_color := Color(1.0, 0.72, 0.24, 1.0)
@export_range(0.0, 20.0, 0.05, "or_greater") var effect_speed := 2.0

@export_group("Deployed Geometry")
@export_range(0.25, 500.0, 0.05, "or_greater") var maximum_length := 8.0
@export_range(0.0, 5.0, 0.01, "or_greater") var placement_slack := 0.3
@export_range(0.005, 0.25, 0.001, "or_greater") var diameter := 0.035
@export_range(0.1, 5.0, 0.05, "or_greater") var target_segment_length := 0.45
@export_range(4, 128, 1) var maximum_simulation_segments := 64

@export_group("Repeated Visual Sections")
@export_range(0.04, 2.0, 0.01, "or_greater") var visual_repeat_length := 0.25
@export_range(0.0, 0.35, 0.01) var visual_section_contrast := 0.08

@export_group("Physical Rope")
@export_range(0.001, 20.0, 0.001, "or_greater") var linear_density_kg_per_m := 0.08
@export_range(1.0, 1000000.0, 1.0, "or_greater") var breaking_force_newtons := 900.0
@export_range(1.0, 1000000.0, 1.0, "or_greater") var stretch_stiffness_newtons_per_m := 1800.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var tension_damping := 55.0
@export_range(0.1, 100.0, 0.1, "or_greater") var force_response := 10.0
@export_range(1.0, 1000000.0, 1.0, "or_greater") var tension_slew_rate_newtons_per_second := 1000.0
@export_range(0.0, 1.0, 0.001) var motion_damping := 0.985
@export_range(0.0, 1.0, 0.001) var surface_friction := 0.35
@export_range(2, 16, 1) var solver_iterations := 6
@export_range(0.01, 1.0, 0.01, "or_greater") var break_grace_seconds := 0.14
@export_flags_3d_physics var collision_mask := 1

@export_group("Electrical Transfer")
@export var transfers_power := false
@export_range(0.0, 1000000.0, 0.1, "or_greater") var maximum_transfer_power_w := 0.0
@export_range(0.0, 1.0, 0.001) var transfer_efficiency := 0.9

@export_group("Data Link")
@export var provides_fiber_link := false
@export_range(0.0, 1000000.0, 0.1, "or_greater") var data_bandwidth_mbps := 0.0
@export_range(0.0, 1.0, 0.0001, "or_greater") var signal_loss_per_meter := 0.001


func get_radius() -> float:
	return maxf(diameter * 0.5, 0.0025)


func get_deployed_mass(deployed_length: float) -> float:
	return maxf(deployed_length, 0.0) * linear_density_kg_per_m


func get_segment_count(deployed_length: float) -> int:
	return clampi(
		ceili(maxf(deployed_length, 0.01) / maxf(target_segment_length, 0.05)),
		2,
		maximum_simulation_segments
	)


func get_effect_name() -> String:
	match visual_effect:
		VisualEffect.CURRENT_PULSE:
			return "Electrical pulse"
		VisualEffect.FIBER_PULSE:
			return "Fiber data pulse"
	return "None"


func instantiate_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "RopeSpoolVisual"
	root.scale = Vector3.ONE * overall_size

	var dark_material := _make_material(
		rope_color.darkened(0.55),
		Color.BLACK
	)
	var rope_material := _make_material(
		rope_color,
		effect_color * 0.18 if visual_effect != VisualEffect.NONE else Color.BLACK
	)

	_add_cylinder(root, "Axle", 0.075, 0.48, dark_material)
	_add_cylinder(root, "WoundLine", 0.205, 0.29, rope_material)
	var left_flange := _add_cylinder(root, "LeftFlange", 0.255, 0.035, dark_material)
	left_flange.position.z = -0.18
	var right_flange := _add_cylinder(root, "RightFlange", 0.255, 0.035, dark_material)
	right_flange.position.z = 0.18

	var label := Label3D.new()
	label.name = "Instructions"
	label.position = Vector3(0.0, 0.36, 0.0)
	label.text = "LMB: attach A / B   F: cancel"
	label.font_size = 28
	label.outline_size = 8
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = effect_color.lightened(0.2)
	label.outline_modulate = Color(0.01, 0.012, 0.016, 1.0)
	root.add_child(label)
	return root


func _add_cylinder(
	parent: Node3D,
	node_name: String,
	radius: float,
	length: float,
	material: Material
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 20
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.rotation.x = PI * 0.5
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


func _make_material(color: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	material.metallic = 0.18
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
	return material
