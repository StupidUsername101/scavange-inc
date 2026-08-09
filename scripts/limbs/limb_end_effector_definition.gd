@tool
class_name LimbEndEffectorDefinition
extends Resource

#######################################################
# Optional distal hardware for a generic limb. The definition is deliberately separate from
# LimbSegmentDefinition so one creature can mix ordinary feet, pads, claws, magnets, tools, or
# other terminal parts without changing the serial joint-chain implementation.
#
# Geometry and grip behavior remain independent: a non-geometric gripper can live at a distal
# limb tip without changing the known-good foot collision, and the same definition can be hosted
# by a creature limb, drone appendage, or future model-forge body.
#######################################################

enum GeometryType {
	NONE,
	SPHERE,
	BOX,
	CAPSULE,
}

enum GripMode {
	NONE,
	PASSIVE,
	CONTROLLED,
}

@export_group("Identity")
@export var effector_name := "End Effector"
@export var enabled := false
@export var effector_type_id: StringName = &"plain_foot"

@export_group("Geometry")
@export_enum("None", "Sphere", "Box", "Capsule") var geometry_type: int = GeometryType.NONE
# Local to the distal segment's authored tip. The segment's local +Y axis points distally.
@export var local_offset := Vector3.ZERO
@export var local_rotation_degrees := Vector3.ZERO
@export_range(0.005, 2.0, 0.005, "or_greater") var sphere_radius := 0.09
@export var box_size := Vector3(0.18, 0.08, 0.18)
@export_range(0.005, 2.0, 0.005, "or_greater") var capsule_radius := 0.06
@export_range(0.01, 4.0, 0.01, "or_greater") var capsule_height := 0.18
@export_range(0.0, 100.0, 0.01, "or_greater") var added_mass := 0.0
@export_range(0.1, 1000000.0, 0.1, "or_greater") var maximum_health := 100.0

@export_group("Surface")
@export_range(0.0, 1.0, 0.01) var friction := 0.95
@export_range(0.0, 1.0, 0.01) var bounce := 0.01
@export var rough := false
@export var absorbent := false

@export_group("Passive compliance")
# Stored as hardware capabilities for later compliant pads/claws. The present runtime does not
# synthesize a hidden linear spring; contacts remain ordinary solver contacts.
@export_range(0.0, 100000.0, 0.1, "or_greater") var normal_stiffness := 0.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var normal_damping := 0.0
@export_range(0.0, 0.5, 0.001) var maximum_compression := 0.0

@export_group("Grip capability")
@export_enum("None", "Passive", "Controlled") var grip_mode: int = GripMode.NONE
# One global normalized policy output, or -1 for no direct actuator index. Controlled grips map
# [-1, +1] onto [0, 1] activation with threshold hysteresis, so zero is a neutral hold state.
# The fixed four-limb profile assigns one independent controlled grip index per limb.
@export var grip_action_index := -1
@export_range(0.0, 1.0, 0.01) var grip_activation_threshold := 0.55
@export_range(0.0, 50.0, 0.01, "or_greater") var activation_response_per_second := 8.0
@export_range(0.01, 2.0, 0.01, "or_greater") var grip_acquisition_radius := 0.24
# Perception radius is intentionally wider than the physical latch radius. The policy can therefore
# see and reach toward a compatible surface before the distal tip is already close enough to grab.
@export_range(0.01, 4.0, 0.01, "or_greater") var grip_detection_radius = 1.10
@export_range(0.0, 1.0, 0.005, "or_greater") var candidate_refresh_seconds := 0.05
@export_flags_3d_physics var grip_collision_mask := 1
@export var allow_static_grip := true
@export var allow_dynamic_grip := true
@export_range(0.0, 10000.0, 0.1, "or_greater") var maximum_held_mass := 25.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var grip_stiffness := 1400.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var grip_damping := 90.0
@export_range(0.0, 1.0, 0.01) var grip_release_threshold := 0.30
@export_range(0.0, 100000.0, 0.1, "or_greater") var maximum_normal_holding_force := 420.0
@export_range(0.0, 100000.0, 0.1, "or_greater") var maximum_shear_holding_force := 360.0
@export_range(0.0, 10.0, 0.01, "or_greater") var breakaway_load_ratio := 1.0
# Require overload to persist briefly before releasing. A single solver/acquisition spike should not
# convert a valid grip into a failed latch, while sustained overload still breaks physically.
@export_range(0.0, 1.0, 0.005, "or_greater") var breakaway_confirmation_seconds: float = 0.08
@export_range(0.0, 100000.0, 0.1, "or_greater") var energy_cost_per_second := 0.0
@export var compatible_surface_tags: PackedStringArray = PackedStringArray()


func sanitize() -> void:
	effector_name = effector_name.strip_edges()
	if effector_name.is_empty():
		effector_name = "End Effector"
	if str(effector_type_id).strip_edges().is_empty():
		effector_type_id = &"plain_foot"
	geometry_type = clampi(geometry_type, GeometryType.NONE, GeometryType.CAPSULE)
	grip_mode = clampi(grip_mode, GripMode.NONE, GripMode.CONTROLLED)
	if not local_offset.is_finite():
		local_offset = Vector3.ZERO
	if not local_rotation_degrees.is_finite():
		local_rotation_degrees = Vector3.ZERO
	local_rotation_degrees = Vector3(
		wrapf(local_rotation_degrees.x, -180.0, 180.0),
		wrapf(local_rotation_degrees.y, -180.0, 180.0),
		wrapf(local_rotation_degrees.z, -180.0, 180.0)
	)
	sphere_radius = maxf(sphere_radius, 0.005)
	box_size = Vector3(
		maxf(absf(box_size.x), 0.005),
		maxf(absf(box_size.y), 0.005),
		maxf(absf(box_size.z), 0.005)
	)
	capsule_radius = maxf(capsule_radius, 0.005)
	capsule_height = maxf(capsule_height, capsule_radius * 2.0)
	added_mass = maxf(added_mass, 0.0)
	maximum_health = maxf(maximum_health, 0.1)
	friction = clampf(friction, 0.0, 1.0)
	bounce = clampf(bounce, 0.0, 1.0)
	normal_stiffness = maxf(normal_stiffness, 0.0)
	normal_damping = maxf(normal_damping, 0.0)
	maximum_compression = clampf(maximum_compression, 0.0, 0.5)
	grip_action_index = maxi(grip_action_index, -1)
	grip_activation_threshold = clampf(grip_activation_threshold, 0.0, 1.0)
	activation_response_per_second = maxf(activation_response_per_second, 0.0)
	grip_acquisition_radius = maxf(grip_acquisition_radius, 0.01)
	grip_detection_radius = maxf(grip_detection_radius, grip_acquisition_radius)
	candidate_refresh_seconds = maxf(candidate_refresh_seconds, 0.0)
	grip_collision_mask = maxi(grip_collision_mask, 0)
	maximum_held_mass = maxf(maximum_held_mass, 0.0)
	grip_stiffness = maxf(grip_stiffness, 0.0)
	grip_damping = maxf(grip_damping, 0.0)
	grip_release_threshold = clampf(grip_release_threshold, 0.0, grip_activation_threshold)
	maximum_normal_holding_force = maxf(maximum_normal_holding_force, 0.0)
	maximum_shear_holding_force = maxf(maximum_shear_holding_force, 0.0)
	breakaway_load_ratio = clampf(breakaway_load_ratio, 0.0, 10.0)
	breakaway_confirmation_seconds = maxf(breakaway_confirmation_seconds, 0.0)
	energy_cost_per_second = maxf(energy_cost_per_second, 0.0)
	if grip_mode != GripMode.CONTROLLED:
		grip_action_index = -1
	var sanitized_tags := PackedStringArray()
	for tag: String in compatible_surface_tags:
		var clean_tag := tag.strip_edges()
		if not clean_tag.is_empty() and not sanitized_tags.has(clean_tag):
			sanitized_tags.append(clean_tag)
	compatible_surface_tags = sanitized_tags


func is_physically_present() -> bool:
	return enabled and geometry_type != GeometryType.NONE


func has_mapped_grip_action() -> bool:
	# A fixed model profile may reserve a grip output for a missing/disabled terminal so topology
	# changes do not invalidate the complete dense action map. Physical command dispatch still uses
	# is_controlled(), which additionally requires the hardware to be enabled.
	return grip_mode == GripMode.CONTROLLED and grip_action_index >= 0


func is_controlled() -> bool:
	return enabled and has_mapped_grip_action()


func required_action_count() -> int:
	return grip_action_index + 1 if has_mapped_grip_action() else 0


func distal_extent() -> float:
	# Nominal reach along the effector's own local +Y axis. This is useful for authored distal
	# points; directional support extents below are used for floor-safe spawn bounds.
	if not is_physically_present():
		return 0.0
	match geometry_type:
		GeometryType.SPHERE:
			return sphere_radius
		GeometryType.BOX:
			return box_size.y * 0.5
		GeometryType.CAPSULE:
			return capsule_height * 0.5
	return 0.0


func maximum_extent_from_distal_tip() -> float:
	if not is_physically_present():
		return 0.0
	var shape_radius := 0.0
	match geometry_type:
		GeometryType.SPHERE:
			shape_radius = sphere_radius
		GeometryType.BOX:
			shape_radius = box_size.length() * 0.5
		GeometryType.CAPSULE:
			shape_radius = capsule_height * 0.5
	return local_offset.length() + shape_radius


func support_radius_along_parent_direction(direction_parent_local: Vector3) -> float:
	if not is_physically_present() or direction_parent_local.length_squared() <= 0.000001:
		return 0.0
	var direction_local := (
		local_basis().inverse() * direction_parent_local.normalized()
	).normalized()
	match geometry_type:
		GeometryType.SPHERE:
			return sphere_radius
		GeometryType.BOX:
			var half_size := box_size * 0.5
			return (
			absf(direction_local.x) * half_size.x
			+ absf(direction_local.y) * half_size.y
			+ absf(direction_local.z) * half_size.z
			)
		GeometryType.CAPSULE:
			var cylinder_half_length := maxf(capsule_height * 0.5 - capsule_radius, 0.0)
			return capsule_radius + absf(direction_local.y) * cylinder_half_length
	return 0.0


func support_offset_along_parent_direction(direction_parent_local: Vector3) -> float:
	if not is_physically_present() or direction_parent_local.length_squared() <= 0.000001:
		return 0.0
	var direction := direction_parent_local.normalized()
	return local_offset.dot(direction) + support_radius_along_parent_direction(direction)


func nominal_contact_offset_parent_local() -> Vector3:
	if not is_physically_present():
		return Vector3.ZERO
	return local_offset + local_basis() * (Vector3.UP * distal_extent())


func local_basis() -> Basis:
	return Basis.from_euler(Vector3(
		deg_to_rad(local_rotation_degrees.x),
		deg_to_rad(local_rotation_degrees.y),
		deg_to_rad(local_rotation_degrees.z)
	)).orthonormalized()


func contract_dictionary() -> Dictionary:
	sanitize()
	return {
		"effector_name": effector_name,
		"enabled": enabled,
		"effector_type_id": str(effector_type_id),
		"geometry_type": geometry_type,
		"local_offset": [local_offset.x, local_offset.y, local_offset.z],
		"local_rotation_degrees": [
			local_rotation_degrees.x,
			local_rotation_degrees.y,
			local_rotation_degrees.z,
		],
		"sphere_radius": sphere_radius,
		"box_size": [box_size.x, box_size.y, box_size.z],
		"capsule_radius": capsule_radius,
		"capsule_height": capsule_height,
		"added_mass": added_mass,
		"maximum_health": maximum_health,
		"friction": friction,
		"bounce": bounce,
		"rough": rough,
		"absorbent": absorbent,
		"normal_stiffness": normal_stiffness,
		"normal_damping": normal_damping,
		"maximum_compression": maximum_compression,
		"grip_mode": grip_mode,
		"grip_action_index": grip_action_index,
		"grip_activation_threshold": grip_activation_threshold,
		"activation_response_per_second": activation_response_per_second,
		"grip_acquisition_radius": grip_acquisition_radius,
		"grip_detection_radius": grip_detection_radius,
		"candidate_refresh_seconds": candidate_refresh_seconds,
		"grip_collision_mask": grip_collision_mask,
		"allow_static_grip": allow_static_grip,
		"allow_dynamic_grip": allow_dynamic_grip,
		"maximum_held_mass": maximum_held_mass,
		"grip_stiffness": grip_stiffness,
		"grip_damping": grip_damping,
		"grip_release_threshold": grip_release_threshold,
		"maximum_normal_holding_force": maximum_normal_holding_force,
		"maximum_shear_holding_force": maximum_shear_holding_force,
		"breakaway_load_ratio": breakaway_load_ratio,
		"breakaway_confirmation_seconds": breakaway_confirmation_seconds,
		"energy_cost_per_second": energy_cost_per_second,
		"compatible_surface_tags": _surface_tags_as_array(),
	}


func to_dictionary() -> Dictionary:
	return contract_dictionary()


func apply_dictionary(data: Dictionary) -> void:
	effector_name = str(data.get("effector_name", effector_name))
	enabled = _bool_or(data.get("enabled"), enabled)
	effector_type_id = StringName(str(data.get("effector_type_id", effector_type_id)))
	geometry_type = _finite_int_or(data.get("geometry_type"), geometry_type)
	local_offset = _vector3_from_value(data.get("local_offset", []), local_offset)
	local_rotation_degrees = _vector3_from_value(
		data.get("local_rotation_degrees", []),
		local_rotation_degrees
	)
	sphere_radius = _finite_float_or(data.get("sphere_radius"), sphere_radius)
	box_size = _vector3_from_value(data.get("box_size", []), box_size)
	capsule_radius = _finite_float_or(data.get("capsule_radius"), capsule_radius)
	capsule_height = _finite_float_or(data.get("capsule_height"), capsule_height)
	added_mass = _finite_float_or(data.get("added_mass"), added_mass)
	maximum_health = _finite_float_or(data.get("maximum_health"), maximum_health)
	friction = _finite_float_or(data.get("friction"), friction)
	bounce = _finite_float_or(data.get("bounce"), bounce)
	rough = _bool_or(data.get("rough"), rough)
	absorbent = _bool_or(data.get("absorbent"), absorbent)
	normal_stiffness = _finite_float_or(data.get("normal_stiffness"), normal_stiffness)
	normal_damping = _finite_float_or(data.get("normal_damping"), normal_damping)
	maximum_compression = _finite_float_or(data.get("maximum_compression"), maximum_compression)
	grip_mode = _finite_int_or(data.get("grip_mode"), grip_mode)
	grip_action_index = _finite_int_or(data.get("grip_action_index"), grip_action_index)
	grip_activation_threshold = _finite_float_or(
		data.get("grip_activation_threshold"),
		grip_activation_threshold
	)
	activation_response_per_second = _finite_float_or(
		data.get("activation_response_per_second"),
		activation_response_per_second
	)
	grip_acquisition_radius = _finite_float_or(data.get("grip_acquisition_radius"), grip_acquisition_radius)
	grip_detection_radius = _finite_float_or(data.get("grip_detection_radius"), grip_detection_radius)
	candidate_refresh_seconds = _finite_float_or(
		data.get("candidate_refresh_seconds"),
		candidate_refresh_seconds
	)
	grip_collision_mask = _finite_int_or(data.get("grip_collision_mask"), grip_collision_mask)
	allow_static_grip = _bool_or(data.get("allow_static_grip"), allow_static_grip)
	allow_dynamic_grip = _bool_or(data.get("allow_dynamic_grip"), allow_dynamic_grip)
	maximum_held_mass = _finite_float_or(data.get("maximum_held_mass"), maximum_held_mass)
	grip_stiffness = _finite_float_or(data.get("grip_stiffness"), grip_stiffness)
	grip_damping = _finite_float_or(data.get("grip_damping"), grip_damping)
	grip_release_threshold = _finite_float_or(data.get("grip_release_threshold"), grip_release_threshold)
	maximum_normal_holding_force = _finite_float_or(
		data.get("maximum_normal_holding_force"),
		maximum_normal_holding_force
	)
	maximum_shear_holding_force = _finite_float_or(
		data.get("maximum_shear_holding_force"),
		maximum_shear_holding_force
	)
	breakaway_load_ratio = _finite_float_or(data.get("breakaway_load_ratio"), breakaway_load_ratio)
	breakaway_confirmation_seconds = _finite_float_or(
		data.get("breakaway_confirmation_seconds"),
		breakaway_confirmation_seconds
	)
	energy_cost_per_second = _finite_float_or(data.get("energy_cost_per_second"), energy_cost_per_second)
	var tags_value: Variant = data.get("compatible_surface_tags", [])
	compatible_surface_tags = PackedStringArray()
	if tags_value is PackedStringArray:
		compatible_surface_tags = (tags_value as PackedStringArray).duplicate()
	elif tags_value is Array:
		for tag_value: Variant in (tags_value as Array):
			compatible_surface_tags.append(str(tag_value))
	sanitize()


func _surface_tags_as_array() -> Array[String]:
	var result: Array[String] = []
	for tag: String in compatible_surface_tags:
		result.append(tag)
	return result


static func from_dictionary(data: Dictionary) -> LimbEndEffectorDefinition:
	var result := LimbEndEffectorDefinition.new()
	result.apply_dictionary(data)
	return result


static func _vector3_from_value(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value if (value as Vector3).is_finite() else fallback
	if value is Array and value.size() >= 3:
		var result = Vector3(
			_finite_float_or(value[0], fallback.x),
			_finite_float_or(value[1], fallback.y),
			_finite_float_or(value[2], fallback.z)
		)
		return result if result.is_finite() else fallback
	return fallback


static func _bool_or(value: Variant, fallback: bool) -> bool:
	return value if value is bool else fallback


static func _finite_float_or(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var numeric_value: float = float(value)
		if is_finite(numeric_value):
			return numeric_value
	return fallback


static func _finite_int_or(value: Variant, fallback: int) -> int:
	if value is float or value is int:
		var numeric_value: float = float(value)
		if is_finite(numeric_value):
			return int(numeric_value)
	return fallback
