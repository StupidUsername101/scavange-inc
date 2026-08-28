extends Node3D
class_name ItemProxy

const INTERP_SPEED := 20.0
const GRABBED_INTERP_SPEED := 30.0
const MAX_EXTRAPOLATION_TIME := 0.20
const NETWORK_LEAD_SECONDS := 0.035
const GRABBED_NETWORK_LEAD_SECONDS := 0.055

#######################################################
# Mirrors authoritative item state on clients and updates its local visual presentation.
#######################################################

var item_id: int = -1
var target_position: Vector3
var target_rotation := Quaternion.IDENTITY
var target_linear_velocity := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO
var time_since_last_state := 0.0
var last_motion_sequence := -1
var grabbed_by_player_id := -1

var definition_path := ""
var item_definition: ItemDefinition
var visual_state_signature := ""
var visual: Node3D
var warehouse_label: Label3D
var fieldlink_status_text := "ONLINE"


func _ready() -> void:
	warehouse_label = WarehouseNameLabel.create(self)


func from_server_state(state: Dictionary) -> void:
	item_id = SafeVariant.integral_int_or(state.get("item_id", -1), -1)

	_apply_definition(
		str(state.get("definition_path", "")),
		SafeVariant.dictionary_copy(state.get("instance_state", {}))
	)
	fieldlink_status_text = "ONLINE"
	if item_definition is RadioItemDefinition:
		var radio_powered := SafeVariant.strict_bool_or(
			state.get("radio_powered", false),
			false
		)
		var radio_paused := SafeVariant.strict_bool_or(
			state.get("radio_paused", false),
			false
		)
		fieldlink_status_text = (
			"PAUSED"
			if radio_powered and radio_paused
			else ("TRANSMITTING" if radio_powered else "STANDBY")
		)

	_apply_motion_state(state)
	WarehouseNameLabel.set_display_name(
		warehouse_label,
		str(state.get("warehouse_display_name", "")),
		global_position,
		0.52
	)
	if visual != null:
		visual.propagate_call(
			"apply_server_item_state",
			[state],
			false
		)



func from_server_motion_state(state: Dictionary) -> void:
	var state_item_id := SafeVariant.integral_int_or(
		state.get("item_id", -1),
		-1
	)
	if state_item_id != item_id:
		return
	_apply_motion_state(state)


func _apply_motion_state(state: Dictionary) -> bool:
	var motion_sequence := SafeVariant.integral_int_or(
		state.get("item_motion_sequence", -1),
		-1
	)
	if not ClientProxyMotion.is_newer_motion_sequence(
		motion_sequence,
		last_motion_sequence
	):
		return false
	if motion_sequence >= 0:
		last_motion_sequence = motion_sequence
	grabbed_by_player_id = SafeVariant.integral_int_or(
		state.get("grabber_player_id", grabbed_by_player_id),
		grabbed_by_player_id
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
	return true


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
	var is_grabbed := grabbed_by_player_id >= 0
	ClientProxyMotion.apply_smoothed_motion(
		self,
		delta,
		time_since_last_state + (
			GRABBED_NETWORK_LEAD_SECONDS
			if is_grabbed
			else NETWORK_LEAD_SECONDS
		),
		target_position,
		target_rotation,
		target_linear_velocity,
		target_angular_velocity,
		MAX_EXTRAPOLATION_TIME,
		GRABBED_INTERP_SPEED if is_grabbed else INTERP_SPEED
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
	item_definition = resource as ItemDefinition
	visual_state_signature = next_signature

	if visual != null:
		visual.queue_free()

	visual = item_definition.instantiate_visual_from_state(instance_state)
	add_child(visual)


func build_fieldlink_contact(
	origin: Vector3,
	maximum_distance: float
) -> Dictionary:
	if item_definition == null or not item_definition.fieldlink_detectable:
		return {}
	var offset := global_position - origin
	var distance_squared := offset.length_squared()
	var bounded_range := maxf(maximum_distance, 0.0)
	if distance_squared > bounded_range * bounded_range:
		return {}
	return {
		"contact_id": StringName("item:%d" % item_id),
		"display_name": item_definition.display_name,
		"device_class": item_definition.fieldlink_device_class,
		"control_type": item_definition.fieldlink_control_type,
		"status_text": fieldlink_status_text,
		"world_position": global_position,
		"distance_meters": sqrt(distance_squared),
		"signal_strength": item_definition.fieldlink_signal_strength,
	}
