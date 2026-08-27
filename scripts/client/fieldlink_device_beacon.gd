class_name FieldlinkDeviceBeacon
extends Node3D

const GROUP := &"fieldlink_device_beacons"

@export var contact_id: StringName = &"technical_device"
@export var display_name := "TECHNICAL DEVICE"
@export var device_class: StringName = &"TERMINAL"
@export var control_type: StringName = &""
@export var status_text := "ONLINE"
@export_range(0.0, 4.0, 0.05) var signal_strength := 1.0

#######################################################
# Marks fixed client-world technology for the Fieldlink scanner. Its transform is
# already paired with authoritative scene geometry, so scanning needs no second
# position registry or per-frame physics query.
#######################################################


func _ready() -> void:
	add_to_group(GROUP)
	var client := get_node_or_null("/root/Client")
	if client != null and client.has_method("register_fieldlink_device_beacon"):
		client.call("register_fieldlink_device_beacon", self)


func _exit_tree() -> void:
	var client := get_node_or_null("/root/Client")
	if client != null and client.has_method("unregister_fieldlink_device_beacon"):
		client.call("unregister_fieldlink_device_beacon", self)


func build_fieldlink_contact(
	origin: Vector3,
	maximum_distance: float
) -> Dictionary:
	var offset := global_position - origin
	var distance_squared := offset.length_squared()
	var bounded_range := maxf(maximum_distance, 0.0)
	if distance_squared > bounded_range * bounded_range:
		return {}
	return {
		"contact_id": contact_id,
		"display_name": display_name,
		"device_class": device_class,
		"control_type": control_type,
		"status_text": status_text,
		"world_position": global_position,
		"distance_meters": sqrt(distance_squared),
		"signal_strength": signal_strength,
	}
