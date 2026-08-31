@tool
class_name EnemyDefinition
extends Resource

#######################################################
# Defines the serialized enemy configuration shared by gameplay, inspection, and replication
# systems.
#######################################################

enum PhysicalVisualStyle {
	SPIDER,
	BLOCK_CREATURE,
}

enum PresentationType {
	LEGACY,
	HUMANOID,
}

@export_group("Identity")
@export var display_name := "Enemy"
@export var visual_color := Color(0.72, 0.16, 0.12, 1.0)
@export var faction_id := 2
@export var physical_visual_style := PhysicalVisualStyle.SPIDER
@export var presentation_type := PresentationType.LEGACY
@export var show_status_label := true

@export_group("Body")
@export var body_size := Vector3(1.0, 1.8, 1.0)
@export var collision_size := Vector3.ZERO
@export_range(-1.0, 30.0, 0.05, "or_greater") var body_center_height := -1.0
@export_range(1.0, 1000000.0, 1.0, "or_greater") var max_health := 100.0
@export_range(0.0, 30.0, 0.05, "or_greater") var target_height := 1.0

@export_group("Enemy Systems")
@export var behavior: EnemyBehaviorDefinition
@export var physical_anatomy: EnemyPhysicalAnatomyDefinition
@export var destructible_anatomy: EnemyDestructibleAnatomyDefinition
@export var flute_runner: FluteRunnerDefinition
@export_range(0.0, 30.0, 0.05, "or_greater") var death_linger_seconds := 0.0

@export_group("Runtime")
@export var starts_active := false
@export var automatically_target_players := false

@export_group("Dev Zoo")
@export_range(0.0, 120.0, 0.1, "or_greater") var respawn_delay_seconds := 2.0


func create_collision_shape() -> Shape3D:
	var shape := BoxShape3D.new()
	shape.size = get_collision_size()
	return shape


func instantiate_visual() -> Node3D:
	# Humanoids are assembled by EnemyHumanoidPresentation3D because their visuals depend on compact
	# replicated gait/awareness state. Keep this fallback empty rather than briefly flashing a box.
	if presentation_type == PresentationType.HUMANOID:
		var humanoid_root := Node3D.new()
		humanoid_root.name = "HumanoidPresentationRoot"
		return humanoid_root
	if physical_anatomy != null:
		var physical_visual := EnemyPhysicalLimbVisual3D.new()
		physical_visual.configure(self)
		return physical_visual

	var root := Node3D.new()
	root.name = "EnemyVisual"

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = visual_color
	body_material.roughness = 0.74
	body_material.metallic = 0.08

	var body_mesh := BoxMesh.new()
	body_mesh.size = body_size
	body_mesh.material = body_material
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.position.y = get_body_center_height()
	body.mesh = body_mesh
	root.add_child(body)

	var target_material := StandardMaterial3D.new()
	target_material.albedo_color = Color(0.92, 0.88, 0.72, 1.0)
	target_material.emission_enabled = true
	target_material.emission = visual_color * 0.28
	target_material.roughness = 0.6
	var target_mesh := CylinderMesh.new()
	target_mesh.top_radius = minf(body_size.x, body_size.y) * 0.22
	target_mesh.bottom_radius = target_mesh.top_radius
	target_mesh.height = 0.025
	target_mesh.radial_segments = 24
	target_mesh.material = target_material
	var target := MeshInstance3D.new()
	target.name = "TargetPlate"
	target.position = Vector3(0.0, target_height, -body_size.z * 0.51)
	target.rotation.x = PI * 0.5
	target.mesh = target_mesh
	root.add_child(target)
	return root


func get_collision_size() -> Vector3:
	if collision_size.x > 0.0 and collision_size.y > 0.0 and collision_size.z > 0.0:
		return collision_size
	return body_size


func get_body_center_height() -> float:
	if body_center_height >= 0.0:
		return body_center_height
	return body_size.y * 0.5


func get_visual_height() -> float:
	var body_top := get_body_center_height() + body_size.y * 0.5
	if physical_anatomy == null:
		return body_top
	var limb_top := body_top
	for limb: EnemyPhysicalLimbDefinition in physical_anatomy.limbs:
		if limb != null:
			limb_top = maxf(limb_top, limb.hip_offset.y + limb.upper_length)
	return limb_top
