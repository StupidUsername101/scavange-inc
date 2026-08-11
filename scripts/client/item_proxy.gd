extends Node3D
class_name ItemProxy

const INTERP_SPEED := 12.0
const MAX_EXTRAPOLATION_TIME := 0.25

#######################################################
# Mirrors authoritative item state on clients and updates its local visual presentation.
#######################################################

var item_id: int = -1
var target_position: Vector3
var target_rotation := Quaternion.IDENTITY
var target_linear_velocity := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO
var time_since_last_state := 0.0

var definition_path := ""
var visual_state_signature := ""
var visual: Node3D
var warehouse_label: Label3D


func _ready() -> void:
	warehouse_label = WarehouseNameLabel.create(self)


func from_server_state(state: Dictionary) -> void:
	item_id = state.get("item_id", -1)

	_apply_definition(
		state.get("definition_path", ""),
		state.get("instance_state", {})
	)

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
	WarehouseNameLabel.set_display_name(
		warehouse_label,
		str(state.get("warehouse_display_name", "")),
		global_position,
		0.52
	)

	time_since_last_state = 0.0


func _process(delta: float) -> void:
	# A listen server already owns the authoritative physics body locally.
	# Following it directly keeps the rendered model exactly on its collider.
	# Joining clients do not have that body and use network smoothing below.
	if multiplayer.is_server():
		var server_item := Server.get_server_item(item_id)

		if is_instance_valid(server_item):
			global_transform = server_item.global_transform
			WarehouseNameLabel.update_position(warehouse_label, global_position, 0.52)
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
	WarehouseNameLabel.update_position(warehouse_label, global_position, 0.52)


func _apply_definition(
	new_definition_path: String,
	instance_state: Dictionary
) -> void:
	var next_signature := JSON.stringify(instance_state)
	if (
		new_definition_path.is_empty()
		or (
			new_definition_path == definition_path
			and next_signature == visual_state_signature
		)
	):
		return

	var resource := load(new_definition_path)

	if not resource is ItemDefinition:
		push_error(
			"Invalid item definition: %s"
			% new_definition_path
		)
		return

	definition_path = new_definition_path
	visual_state_signature = next_signature

	if visual != null:
		visual.queue_free()

	visual = (
		resource as ItemDefinition
	).instantiate_visual_from_state(instance_state)
	add_child(visual)
