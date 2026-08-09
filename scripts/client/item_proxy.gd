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
	warehouse_label.no_depth_test = false
	add_child(warehouse_label)


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
	_apply_warehouse_label(str(state.get("warehouse_display_name", "")))

	time_since_last_state = 0.0


func _process(delta: float) -> void:
	# A listen server already owns the authoritative physics body locally.
	# Following it directly keeps the rendered model exactly on its collider.
	# Joining clients do not have that body and use network smoothing below.
	if multiplayer.is_server():
		var server_item := Server.get_server_item(item_id)

		if is_instance_valid(server_item):
			global_transform = server_item.global_transform
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

	var interpolation_weight := clampf(
		INTERP_SPEED * delta,
		0.0,
		1.0
	)

	# Advance with the server-reported motion first. Without this, lerping
	# toward an equally fast moving target creates a permanent trailing gap.
	global_position += target_linear_velocity * delta

	global_position = global_position.lerp(
		predicted_position,
		interpolation_weight
	)

	var current_rotation := global_basis.get_rotation_quaternion()
	global_basis = Basis(current_rotation.slerp(
		predicted_rotation,
		interpolation_weight
	))
	_update_warehouse_label_position()


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


func _apply_warehouse_label(display_name: String) -> void:
	if warehouse_label == null:
		return
	warehouse_label.text = display_name
	warehouse_label.visible = not display_name.is_empty()
	_update_warehouse_label_position()


func _update_warehouse_label_position() -> void:
	if warehouse_label == null or not warehouse_label.visible:
		return
	warehouse_label.global_position = global_position + Vector3.UP * 0.52
