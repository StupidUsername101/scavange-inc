@tool
class_name FourLimbSlotDefinition
extends Resource

#######################################################
# One stable limb slot. Missing limbs keep their slot and action channels so a policy can
# identify damage instead of receiving a differently sized tensor.
#######################################################

@export_group("Identity")
@export var slot_name = "Limb"
@export var installed = true

@export_group("Placement")
@export var hip_offset = Vector3.ZERO
@export var rest_foot_offset = Vector3(0.0, -1.65, 0.65)
@export var bend_hint = Vector3.UP

@export_group("Segments")
@export_range(0.1, 4.0, 0.01, "or_greater") var upper_length = 1.05
@export_range(0.1, 4.0, 0.01, "or_greater") var lower_length = 1.10
@export_range(0.02, 0.5, 0.005, "or_greater") var segment_radius = 0.075
@export_range(0.01, 100.0, 0.01, "or_greater") var segment_mass = 0.38
@export_range(0.1, 1000.0, 0.1, "or_greater") var maximum_health = 100.0
@export var end_effector: LimbEndEffectorDefinition

@export_group("Joint limits")
# Elevation/depression in the leg's radial vertical plane.
@export_range(1.0, 90.0, 0.5) var hip_swing_span_degrees = 68.0
# Extra positive elevation above the symmetric walking range. Profile v10 treats this recovery and
# climbing workspace as part of the normal four-limb anatomy rather than a legacy opt-in.
@export_range(0.0, 60.0, 0.5) var hip_elevation_upper_extension_degrees = 40.0
# Legacy serialized name retained for old body files. In profile v9 this is the horizontal
# coxa sweep around core-local up, not axial twisting of the upper capsule.
@export_range(1.0, 90.0, 0.5) var hip_twist_span_degrees = 72.0
@export_range(-20.0, -1.0, 0.5) var knee_limit_lower_degrees = -8.0
@export_range(15.0, 120.0, 0.5) var knee_limit_upper_degrees = 72.0


func maximum_reach() -> float:
	var result = upper_length + lower_length
	if end_effector != null:
		result += end_effector.maximum_extent_from_distal_tip()
	return result


func sanitize_joint_limits() -> void:
	# End-effectors are optional saved attachments. Never synthesize one while sanitizing the
	# compatibility slot; the Walker preset explicitly equips its grip .tres resources.
	if end_effector != null:
		end_effector.sanitize()
	hip_swing_span_degrees = clampf(hip_swing_span_degrees, 1.0, 90.0)
	hip_elevation_upper_extension_degrees = clampf(
		hip_elevation_upper_extension_degrees,
		0.0,
		60.0
	)
	hip_twist_span_degrees = clampf(hip_twist_span_degrees, 1.0, 90.0)
	# A small negative range permits natural straightening without allowing the lower segment to
	# flip through the upper segment. This is a physical anatomy invariant, not a policy setting.
	knee_limit_lower_degrees = clampf(knee_limit_lower_degrees, -20.0, -1.0)
	knee_limit_upper_degrees = clampf(knee_limit_upper_degrees, 15.0, 120.0)


func contract_dictionary() -> Dictionary:
	var result = {
		"slot_name": slot_name,
		"installed": installed,
		"hip_offset": [hip_offset.x, hip_offset.y, hip_offset.z],
		"rest_foot_offset": [rest_foot_offset.x, rest_foot_offset.y, rest_foot_offset.z],
		"bend_hint": [bend_hint.x, bend_hint.y, bend_hint.z],
		"upper_length": upper_length,
		"lower_length": lower_length,
		"segment_radius": segment_radius,
		"segment_mass": segment_mass,
		"maximum_health": maximum_health,
		"end_effector": end_effector.contract_dictionary() if end_effector != null else {},
		"hip_swing_span_degrees": hip_swing_span_degrees,
		"hip_twist_span_degrees": hip_twist_span_degrees,
		"knee_limit_lower_degrees": knee_limit_lower_degrees,
		"knee_limit_upper_degrees": knee_limit_upper_degrees,
	}
	result["hip_elevation_upper_extension_degrees"] = (
		hip_elevation_upper_extension_degrees
	)
	return result


func to_dictionary() -> Dictionary:
	return contract_dictionary()


func apply_dictionary(data: Dictionary) -> void:
	slot_name = str(data.get("slot_name", slot_name))
	installed = RLTrainingMath.bool_or(data.get("installed", installed), installed)
	hip_offset = _vector3_from_value(data.get("hip_offset", []), hip_offset)
	rest_foot_offset = _vector3_from_value(
		data.get("rest_foot_offset", []),
		rest_foot_offset
	)
	bend_hint = _vector3_from_value(data.get("bend_hint", []), bend_hint)
	if bend_hint.length_squared() > 0.000001:
		bend_hint = bend_hint.normalized()
	upper_length = maxf(_finite_float_or(data.get("upper_length"), upper_length), 0.1)
	lower_length = maxf(_finite_float_or(data.get("lower_length"), lower_length), 0.1)
	segment_radius = maxf(_finite_float_or(data.get("segment_radius"), segment_radius), 0.02)
	segment_mass = maxf(_finite_float_or(data.get("segment_mass"), segment_mass), 0.01)
	maximum_health = maxf(_finite_float_or(data.get("maximum_health"), maximum_health), 0.1)
	var effector_value: Variant = data.get("end_effector", {})
	if effector_value is Dictionary and not (effector_value as Dictionary).is_empty():
		end_effector = LimbEndEffectorDefinition.from_dictionary(effector_value as Dictionary)
	elif effector_value is Dictionary:
		end_effector = null
	hip_swing_span_degrees = clampf(
		_finite_float_or(data.get("hip_swing_span_degrees"), hip_swing_span_degrees),
		1.0,
		90.0
	)
	hip_elevation_upper_extension_degrees = clampf(
		_finite_float_or(
			data.get("hip_elevation_upper_extension_degrees"),
			hip_elevation_upper_extension_degrees
		),
		0.0,
		60.0
	)
	hip_twist_span_degrees = clampf(
		_finite_float_or(data.get("hip_twist_span_degrees"), hip_twist_span_degrees),
		1.0,
		90.0
	)
	knee_limit_lower_degrees = clampf(
		_finite_float_or(data.get("knee_limit_lower_degrees"), knee_limit_lower_degrees),
		-20.0,
		-1.0
	)
	knee_limit_upper_degrees = clampf(
		_finite_float_or(data.get("knee_limit_upper_degrees"), knee_limit_upper_degrees),
		15.0,
		120.0
	)
	sanitize_joint_limits()


static func from_dictionary(data: Dictionary) -> FourLimbSlotDefinition:
	var result = FourLimbSlotDefinition.new()
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


static func _finite_float_or(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var numeric_value: float = float(value)
		if is_finite(numeric_value):
			return numeric_value
	return fallback
