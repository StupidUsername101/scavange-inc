extends Node3D

const PART_GEOMETRY := preload(
	"res://scripts/drones/drone_part_geometry.gd"
)
const INTERP_SPEED := 12.0
const MAX_EXTRAPOLATION_TIME := 0.25

#######################################################
# Mirrors authoritative drone part state on clients and updates its local visual presentation.
#######################################################

var drone_part_id := -1
var definition_path := ""
var visual: Node3D
var broken := false
var warehouse_label: Label3D
var warehouse_label_height := 0.42

var target_position := Vector3.ZERO
var target_rotation := Quaternion.IDENTITY
var target_linear_velocity := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO
var time_since_last_state := 0.0


func _ready() -> void:
	warehouse_label = Label3D.new()
	warehouse_label.name = "WarehouseItemName"
	warehouse_label.top_level = true
	warehouse_label.visible = false
	warehouse_label.font_size = 38
	warehouse_label.outline_size = 10
	warehouse_label.modulate = Color(0.96, 0.98, 1.0, 1.0)
	warehouse_label.outline_modulate = Color(0.005, 0.008, 0.012, 1.0)
	warehouse_label.pixel_size = 0.002
	warehouse_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Warehouse names should be readable, but they must still respect walls,
	# shelves, parts, and every other piece of scene geometry.
	warehouse_label.no_depth_test = false
	add_child(warehouse_label)


func apply_server_state(state: Dictionary) -> void:
	drone_part_id = state.get("drone_part_id", -1)
	_apply_definition(state.get("definition_path", ""))
	broken = state.get("broken", false)
	_apply_broken_visual()
	_apply_warehouse_label(str(state.get("warehouse_display_name", "")))
	target_position = state.get("pos", global_position)
	target_rotation = Quaternion.from_euler(
		state.get("rot", global_rotation)
	)
	target_linear_velocity = state.get(
		"linear_velocity",
		Vector3.ZERO
	)
	target_angular_velocity = state.get(
		"angular_velocity",
		Vector3.ZERO
	)
	time_since_last_state = 0.0


func _apply_definition(new_path: String) -> void:
	if new_path.is_empty() or new_path == definition_path:
		return

	var resource := load(new_path) as DronePartDefinition
	if resource == null:
		push_error("Invalid drone part definition: %s" % new_path)
		return

	definition_path = new_path
	if visual != null:
		visual.queue_free()
	visual = PART_GEOMETRY.create_visual(resource)
	add_child(visual)
	warehouse_label_height = _get_mounted_label_height(resource)
	_apply_broken_visual()


func _apply_broken_visual() -> void:
	if visual == null or not broken:
		return
	var broken_material := StandardMaterial3D.new()
	broken_material.albedo_color = Color(0.055, 0.045, 0.04, 1.0)
	broken_material.roughness = 0.95
	broken_material.emission_enabled = true
	broken_material.emission = Color(0.12, 0.025, 0.005, 1.0)
	_apply_material_recursively(visual, broken_material)


func _apply_material_recursively(
	node: Node,
	material: StandardMaterial3D
) -> void:
	var mesh_visual := node as MeshInstance3D
	if mesh_visual != null:
		mesh_visual.material_override = material
	for child in node.get_children():
		_apply_material_recursively(child, material)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		var server_part := Server.get_server_drone_part(drone_part_id)
		if is_instance_valid(server_part):
			global_transform = server_part.global_transform
			_update_warehouse_label_position()
			return

	time_since_last_state += delta
	var extrapolation_time := minf(
		time_since_last_state,
		MAX_EXTRAPOLATION_TIME
	)
	var predicted_position := (
		target_position
		+ target_linear_velocity * extrapolation_time
	)
	var predicted_rotation := target_rotation
	var angular_speed := target_angular_velocity.length()
	if angular_speed > 0.0001:
		predicted_rotation = (
			Quaternion(
				target_angular_velocity / angular_speed,
				angular_speed * extrapolation_time
			)
			* target_rotation
		)

	var weight := clampf(INTERP_SPEED * delta, 0.0, 1.0)
	global_position += target_linear_velocity * delta
	global_position = global_position.lerp(
		predicted_position,
		weight
	)
	var current_rotation := global_basis.get_rotation_quaternion()
	global_basis = Basis(
		current_rotation.slerp(predicted_rotation, weight)
	)
	_update_warehouse_label_position()


func _apply_warehouse_label(display_name: String) -> void:
	if warehouse_label == null:
		return
	warehouse_label.text = display_name
	warehouse_label.visible = not display_name.is_empty()
	_update_warehouse_label_position()


func _update_warehouse_label_position() -> void:
	if warehouse_label == null or not warehouse_label.visible:
		return
	warehouse_label.global_position = (
		global_position + Vector3.UP * warehouse_label_height
	)


func _get_mounted_label_height(definition: DronePartDefinition) -> float:
	if definition is DroneCoreDefinition:
		return (definition as DroneCoreDefinition).body_size.z * 0.5 + 0.2
	if definition is DroneBatteryDefinition:
		return (definition as DroneBatteryDefinition).body_size.z * 0.5 + 0.2
	if definition is DroneAIChipDefinition:
		return (definition as DroneAIChipDefinition).body_size.z * 0.5 + 0.2
	if definition is DroneAttachmentDefinition:
		return (definition as DroneAttachmentDefinition).body_size.z * 0.5 + 0.2
	if definition is DronePropellerDefinition:
		return (definition as DronePropellerDefinition).rotor_radius + 0.2
	return 0.42
