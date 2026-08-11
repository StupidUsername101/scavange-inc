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
	warehouse_label = WarehouseNameLabel.create(self)


func apply_server_state(state: Dictionary) -> void:
	drone_part_id = SafeVariant.integral_int_or(state.get("drone_part_id", -1), -1)
	var was_broken: bool = broken
	broken = SafeVariant.strict_bool_or(state.get("broken", false), false)
	_apply_definition(
		str(state.get("definition_path", "")),
		was_broken and not broken
	)
	_apply_broken_visual()
	WarehouseNameLabel.set_display_name(
		warehouse_label,
		str(state.get("warehouse_display_name", "")),
		global_position,
		warehouse_label_height
	)
	var rigid_state: Dictionary = ClientProxyMotion.decode_rigid_state(
		state,
		global_position,
		global_rotation
	)
	target_position = rigid_state["position"]
	target_rotation = rigid_state["rotation"]
	target_linear_velocity = rigid_state["linear_velocity"]
	target_angular_velocity = rigid_state["angular_velocity"]
	time_since_last_state = 0.0


func _apply_definition(new_path: String, force_rebuild: bool = false) -> void:
	if new_path.is_empty() or (new_path == definition_path and not force_rebuild):
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
			WarehouseNameLabel.update_position(
				warehouse_label, global_position, warehouse_label_height
			)
			return

	time_since_last_state += delta
	ClientProxyMotion.apply_smoothed_motion(
		self,
		delta,
		time_since_last_state,
		target_position,
		target_rotation,
		target_linear_velocity,
		target_angular_velocity,
		MAX_EXTRAPOLATION_TIME,
		INTERP_SPEED
	)
	WarehouseNameLabel.update_position(
		warehouse_label, global_position, warehouse_label_height
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
