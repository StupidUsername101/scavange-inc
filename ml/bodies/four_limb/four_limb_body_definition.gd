@tool
class_name FourLimbBodyDefinition
extends Resource

const LIMB_SLOT_COUNT = 4
const ATTACHMENT_SLOT_COUNT = 4
const BODY_PROFILE_ID = "four_limb_physics_v12"
const SAFE_HIP_HORIZONTAL_RESPONSE_DEGREES_PER_SECOND: float = 180.0

#######################################################
# Compatibility resource for the current four-limb trainer/physics rig. Stock anatomy no longer
# lives here; the model creator owns that body as a named preset. Generic future bodies use
# MLBodyBuildDraft/MLBodyCoreDefinition/GenericLimbDefinition directly.
#######################################################

@export_group("Core")
@export var core_size: Vector3 = Vector3.ONE
@export_range(0.1, 500.0, 0.1, "or_greater") var core_mass: float = 1.0
@export_range(0.1, 10000.0, 0.1, "or_greater") var core_maximum_health: float = 100.0
@export_range(0.0, 1.0, 0.01) var friction: float = 0.8
@export_range(0.0, 1.0, 0.01) var bounce: float = 0.0
@export_range(0.0, 20.0, 0.05, "or_greater") var linear_damp: float = 0.5
@export_range(0.0, 20.0, 0.05, "or_greater") var angular_damp: float = 1.0

@export_group("Actuators")
@export_range(0.0, 1000.0, 0.1, "or_greater") var hip_stiffness: float = 100.0
@export_range(0.0, 100.0, 0.05, "or_greater") var hip_damping: float = 10.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var maximum_hip_torque: float = 100.0
# Horizontal coxa sweep has large leverage on a light core. This compatibility field stores the
# authored slew rate for the fixed four-limb trainer; creator presets choose their own value.
@export_range(0.0, 1440.0, 1.0, "or_greater") var hip_horizontal_response_degrees_per_second: float = SAFE_HIP_HORIZONTAL_RESPONSE_DEGREES_PER_SECOND
@export_range(0.0, 1000.0, 0.1, "or_greater") var knee_stiffness: float = 100.0
@export_range(0.0, 100.0, 0.05, "or_greater") var knee_damping: float = 10.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var maximum_knee_torque: float = 100.0
@export_range(0.0, 45.0, 0.25) var joint_limit_soft_zone_degrees: float = 8.0
@export_range(0.0, 5000.0, 0.5, "or_greater") var joint_limit_stiffness: float = 200.0
@export_range(0.0, 500.0, 0.25, "or_greater") var joint_limit_damping: float = 15.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_joint_limit_torque: float = 250.0

@export_group("Passive joint elasticity")
# Permanent spring-damper resistance around every authored joint rest pose. This remains active
# without policy input and is physically separate from the stronger model-command actuator.
@export_range(0.0, 1000.0, 0.1, "or_greater") var passive_joint_stiffness: float = 50.0
@export_range(0.0, 100.0, 0.05, "or_greater") var passive_joint_damping: float = 10.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var maximum_passive_joint_torque: float = 100.0
@export_range(0.0, 0.95, 0.01) var passive_joint_progressive_onset_ratio: float = 0.50
@export_range(0.0, 50.0, 0.1, "or_greater") var passive_joint_progressive_ratio: float = 2.0
@export_range(0.0, 1.0, 0.01) var passive_joint_native_fraction: float = 0.35

@export_group("Topology")
@export var limbs: Array[FourLimbSlotDefinition] = []
@export var attachment_slots: Array[FourLimbAttachmentSlotDefinition] = []


func ensure_contract() -> void:
	# This compatibility profile has four stable legacy slots, but it no longer invents preset
	# anatomy. Missing serialized slots become explicit unequipped placeholders. The Walker body
	# itself is created only through the Four-Limb Walker .tres preset/MLBodyPresetLibrary.
	limbs.resize(LIMB_SLOT_COUNT)
	for limb_index in range(LIMB_SLOT_COUNT):
		if limbs[limb_index] == null:
			var placeholder = FourLimbSlotDefinition.new()
			placeholder.slot_name = "Limb %d" % (limb_index + 1)
			placeholder.installed = false
			limbs[limb_index] = placeholder
		limbs[limb_index].sanitize_joint_limits()
	attachment_slots.resize(ATTACHMENT_SLOT_COUNT)
	for slot_index in range(ATTACHMENT_SLOT_COUNT):
		if attachment_slots[slot_index] == null:
			var placeholder = FourLimbAttachmentSlotDefinition.new()
			placeholder.slot_name = "Attachment %d" % (slot_index + 1)
			attachment_slots[slot_index] = placeholder

func preferred_core_height() -> float:
	ensure_contract()
	var result = core_size.y * 0.5
	for limb: FourLimbSlotDefinition in limbs:
		if limb == null or not limb.installed:
			continue
		# rest_foot_offset is the lower-segment tip. An absent physical terminal uses that exact tip;
		# an authored terminal extends the rest support envelope.
		result = maxf(result, -_rest_support_minimum_y(limb))
	return result


func minimum_spawn_height(clearance: float = 0.03) -> float:
	ensure_contract()
	var result = core_size.y * 0.5 + maxf(clearance, 0.0)
	for limb: FourLimbSlotDefinition in limbs:
		if limb == null or not limb.installed:
			continue
		result = maxf(
			result,
			-_rest_support_minimum_y(limb) + maxf(clearance, 0.0)
		)
	return result


func horizontal_rest_extent() -> float:
	ensure_contract()
	var result = maxf(core_size.x, core_size.z) * 0.5
	for limb: FourLimbSlotDefinition in limbs:
		if limb == null or not limb.installed:
			continue
		result = maxf(result, _rest_support_horizontal_extent(limb))
	return result


func _rest_support_minimum_y(limb: FourLimbSlotDefinition) -> float:
	if limb == null or limb.end_effector == null or not limb.end_effector.is_physically_present():
		return limb.rest_foot_offset.y if limb != null else 0.0
	var lower_basis := _rest_lower_segment_basis(limb)
	var downward_in_lower := lower_basis.inverse() * Vector3.DOWN
	var effector_minimum_y = (
		limb.rest_foot_offset.y
		- limb.end_effector.support_offset_along_parent_direction(downward_in_lower)
	)
	# The lower capsule still reaches its authored tip even when terminal geometry is offset upward.
	return minf(limb.rest_foot_offset.y, effector_minimum_y)


func _rest_support_horizontal_extent(limb: FourLimbSlotDefinition) -> float:
	var base_extent = (
		maxf(absf(limb.rest_foot_offset.x), absf(limb.rest_foot_offset.z))
		+ limb.segment_radius
	)
	if limb.end_effector == null or not limb.end_effector.is_physically_present():
		return base_extent
	var lower_basis := _rest_lower_segment_basis(limb)
	var positive_x := limb.end_effector.support_offset_along_parent_direction(
		lower_basis.inverse() * Vector3.RIGHT
	)
	var negative_x := limb.end_effector.support_offset_along_parent_direction(
		lower_basis.inverse() * Vector3.LEFT
	)
	var positive_z := limb.end_effector.support_offset_along_parent_direction(
		lower_basis.inverse() * Vector3.BACK
	)
	var negative_z := limb.end_effector.support_offset_along_parent_direction(
		lower_basis.inverse() * Vector3.FORWARD
	)
	return maxf(
		base_extent,
		maxf(
			maxf(
				limb.rest_foot_offset.x + positive_x,
				-limb.rest_foot_offset.x + negative_x
			),
			maxf(
				limb.rest_foot_offset.z + positive_z,
				-limb.rest_foot_offset.z + negative_z
			)
		)
	)


func _rest_lower_segment_basis(limb: FourLimbSlotDefinition) -> Basis:
	var points := EnemyGaitPlanner.solve_two_bone(
		limb.hip_offset,
		limb.rest_foot_offset,
		limb.upper_length,
		limb.lower_length,
		limb.bend_hint
	)
	if points.size() != 3:
		return Basis.IDENTITY
	return GenericLimb3D.basis_from_y((points[2] - points[1]).normalized())


func to_dictionary() -> Dictionary:
	ensure_contract()
	var limb_data: Array[Dictionary] = []
	for limb: FourLimbSlotDefinition in limbs:
		limb_data.append(limb.to_dictionary() if limb != null else {})
	var attachment_data: Array[Dictionary] = []
	for slot: FourLimbAttachmentSlotDefinition in attachment_slots:
		attachment_data.append(slot.to_dictionary() if slot != null else {})
	var result = {
		"body_profile_id": BODY_PROFILE_ID,
		"core_size": [core_size.x, core_size.y, core_size.z],
		"core_mass": core_mass,
		"core_maximum_health": core_maximum_health,
		"friction": friction,
		"bounce": bounce,
		"linear_damp": linear_damp,
		"angular_damp": angular_damp,
		"hip_stiffness": hip_stiffness,
		"hip_damping": hip_damping,
		"maximum_hip_torque": maximum_hip_torque,
		"knee_stiffness": knee_stiffness,
		"knee_damping": knee_damping,
		"maximum_knee_torque": maximum_knee_torque,
		"joint_limit_soft_zone_degrees": joint_limit_soft_zone_degrees,
		"joint_limit_stiffness": joint_limit_stiffness,
		"joint_limit_damping": joint_limit_damping,
		"maximum_joint_limit_torque": maximum_joint_limit_torque,
		"passive_joint_stiffness": passive_joint_stiffness,
		"passive_joint_damping": passive_joint_damping,
		"maximum_passive_joint_torque": maximum_passive_joint_torque,
		"passive_joint_progressive_onset_ratio": passive_joint_progressive_onset_ratio,
		"passive_joint_progressive_ratio": passive_joint_progressive_ratio,
		"passive_joint_native_fraction": passive_joint_native_fraction,
		"limbs": limb_data,
		"attachment_slots": attachment_data,
	}
	result["hip_horizontal_response_degrees_per_second"] = (
		hip_horizontal_response_degrees_per_second
	)
	return result


func apply_dictionary(data: Dictionary) -> void:
	core_size = SafeVariant.vector3_or(data.get("core_size", []), core_size)
	core_size = Vector3(
		maxf(core_size.x, 0.1),
		maxf(core_size.y, 0.1),
		maxf(core_size.z, 0.1)
	)
	core_mass = maxf(SafeVariant.finite_float_or(data.get("core_mass"), core_mass), 0.1)
	core_maximum_health = maxf(
		SafeVariant.finite_float_or(data.get("core_maximum_health"), core_maximum_health),
		0.1
	)
	friction = clampf(SafeVariant.finite_float_or(data.get("friction"), friction), 0.0, 1.0)
	bounce = clampf(SafeVariant.finite_float_or(data.get("bounce"), bounce), 0.0, 1.0)
	linear_damp = maxf(SafeVariant.finite_float_or(data.get("linear_damp"), linear_damp), 0.0)
	angular_damp = maxf(SafeVariant.finite_float_or(data.get("angular_damp"), angular_damp), 0.0)
	hip_stiffness = maxf(SafeVariant.finite_float_or(data.get("hip_stiffness"), hip_stiffness), 0.0)
	hip_damping = maxf(SafeVariant.finite_float_or(data.get("hip_damping"), hip_damping), 0.0)
	maximum_hip_torque = maxf(
		SafeVariant.finite_float_or(data.get("maximum_hip_torque"), maximum_hip_torque),
		0.0
	)
	hip_horizontal_response_degrees_per_second = maxf(
		SafeVariant.finite_float_or(
			data.get("hip_horizontal_response_degrees_per_second"),
			SAFE_HIP_HORIZONTAL_RESPONSE_DEGREES_PER_SECOND
		),
		0.0
	)
	knee_stiffness = maxf(SafeVariant.finite_float_or(data.get("knee_stiffness"), knee_stiffness), 0.0)
	knee_damping = maxf(SafeVariant.finite_float_or(data.get("knee_damping"), knee_damping), 0.0)
	maximum_knee_torque = maxf(
		SafeVariant.finite_float_or(data.get("maximum_knee_torque"), maximum_knee_torque),
		0.0
	)
	joint_limit_soft_zone_degrees = clampf(
		SafeVariant.finite_float_or(data.get("joint_limit_soft_zone_degrees"), joint_limit_soft_zone_degrees),
		0.0,
		45.0
	)
	joint_limit_stiffness = maxf(
		SafeVariant.finite_float_or(data.get("joint_limit_stiffness"), joint_limit_stiffness),
		0.0
	)
	joint_limit_damping = maxf(
		SafeVariant.finite_float_or(data.get("joint_limit_damping"), joint_limit_damping),
		0.0
	)
	maximum_joint_limit_torque = maxf(
		SafeVariant.finite_float_or(data.get("maximum_joint_limit_torque"), maximum_joint_limit_torque),
		0.0
	)
	passive_joint_stiffness = maxf(
		SafeVariant.finite_float_or(data.get("passive_joint_stiffness"), passive_joint_stiffness),
		0.0
	)
	passive_joint_damping = maxf(
		SafeVariant.finite_float_or(data.get("passive_joint_damping"), passive_joint_damping),
		0.0
	)
	maximum_passive_joint_torque = maxf(
		SafeVariant.finite_float_or(data.get("maximum_passive_joint_torque"), maximum_passive_joint_torque),
		0.0
	)
	passive_joint_progressive_onset_ratio = clampf(
		SafeVariant.finite_float_or(
			data.get("passive_joint_progressive_onset_ratio"),
			passive_joint_progressive_onset_ratio
		),
		0.0,
		0.95
	)
	passive_joint_progressive_ratio = maxf(
		SafeVariant.finite_float_or(
			data.get("passive_joint_progressive_ratio"),
			passive_joint_progressive_ratio
		),
		0.0
	)
	passive_joint_native_fraction = clampf(
		SafeVariant.finite_float_or(
			data.get("passive_joint_native_fraction"),
			passive_joint_native_fraction
		),
		0.0,
		1.0
	)
	var loaded_limbs: Variant = data.get("limbs", [])
	if loaded_limbs is Array:
		var loaded_limb_array = loaded_limbs as Array
		if loaded_limb_array.size() == LIMB_SLOT_COUNT:
			var typed_limbs: Array[FourLimbSlotDefinition] = []
			for limb_index in range(LIMB_SLOT_COUNT):
				var value: Variant = loaded_limb_array[limb_index]
				if value is Dictionary:
					typed_limbs.append(FourLimbSlotDefinition.from_dictionary(value as Dictionary))
				else:
					var placeholder = FourLimbSlotDefinition.new()
					placeholder.slot_name = "Limb %d" % (limb_index + 1)
					placeholder.installed = false
					typed_limbs.append(placeholder)
			limbs = typed_limbs
	var loaded_attachments: Variant = data.get("attachment_slots", [])
	if loaded_attachments is Array:
		var loaded_attachment_array = loaded_attachments as Array
		if loaded_attachment_array.size() == ATTACHMENT_SLOT_COUNT:
			var typed_attachments: Array[FourLimbAttachmentSlotDefinition] = []
			for value: Variant in loaded_attachment_array:
				if value is Dictionary:
					typed_attachments.append(
						FourLimbAttachmentSlotDefinition.from_dictionary(
							value as Dictionary
						)
					)
				else:
					typed_attachments.append(
						FourLimbAttachmentSlotDefinition.new()
					)
			attachment_slots = typed_attachments
	ensure_contract()


static func from_dictionary(data: Dictionary) -> FourLimbBodyDefinition:
	# Compatibility records are complete accepted bodies, not invitations to reconstruct a historical
	# Walker from class defaults. Missing profile fields/topology fail closed; new groups select the
	# explicit Four-Limb Walker creator preset instead.
	if not _is_complete_serialized_body(data):
		return null
	var result = FourLimbBodyDefinition.new()
	result.apply_dictionary(data)
	return result


static func _is_complete_serialized_body(data: Dictionary) -> bool:
	if str(data.get("body_profile_id", "")) != BODY_PROFILE_ID:
		return false
	for required_key: String in [
		"core_size",
		"core_mass",
		"core_maximum_health",
		"friction",
		"bounce",
		"linear_damp",
		"angular_damp",
		"hip_stiffness",
		"hip_damping",
		"maximum_hip_torque",
		"hip_horizontal_response_degrees_per_second",
		"knee_stiffness",
		"knee_damping",
		"maximum_knee_torque",
		"joint_limit_soft_zone_degrees",
		"joint_limit_stiffness",
		"joint_limit_damping",
		"maximum_joint_limit_torque",
		"passive_joint_stiffness",
		"passive_joint_damping",
		"maximum_passive_joint_torque",
		"passive_joint_progressive_onset_ratio",
		"passive_joint_progressive_ratio",
		"passive_joint_native_fraction",
		"limbs",
		"attachment_slots",
	]:
		if not data.has(required_key):
			return false
	var limbs_value: Variant = data.get("limbs", null)
	var attachments_value: Variant = data.get("attachment_slots", null)
	if not (limbs_value is Array) or (limbs_value as Array).size() != LIMB_SLOT_COUNT:
		return false
	if not (attachments_value is Array) or (attachments_value as Array).size() != ATTACHMENT_SLOT_COUNT:
		return false
	var required_limb_keys: Array[String] = [
		"slot_name", "installed", "hip_offset", "rest_foot_offset", "bend_hint",
		"upper_length", "lower_length", "segment_radius", "segment_mass", "maximum_health",
		"end_effector", "hip_swing_span_degrees", "hip_elevation_upper_extension_degrees",
		"hip_twist_span_degrees", "knee_limit_lower_degrees", "knee_limit_upper_degrees",
	]
	for limb_value: Variant in (limbs_value as Array):
		if not (limb_value is Dictionary):
			return false
		if not _dictionary_has_keys(limb_value as Dictionary, required_limb_keys):
			return false
	var required_attachment_keys: Array[String] = ["slot_name", "core_offset", "allowed_tags"]
	for attachment_value: Variant in (attachments_value as Array):
		if not (attachment_value is Dictionary):
			return false
		if not _dictionary_has_keys(attachment_value as Dictionary, required_attachment_keys):
			return false
	return true


static func _dictionary_has_keys(data: Dictionary, required_keys: Array[String]) -> bool:
	for required_key: String in required_keys:
		if not data.has(required_key):
			return false
	return true


func hardware_signature() -> String:
	ensure_contract()
	var data = {
		"body_profile_id": BODY_PROFILE_ID,
		"core_size": [core_size.x, core_size.y, core_size.z],
		"core_mass": core_mass,
		"core_maximum_health": core_maximum_health,
		"friction": friction,
		"bounce": bounce,
		"linear_damp": linear_damp,
		"angular_damp": angular_damp,
		"hip_stiffness": hip_stiffness,
		"hip_damping": hip_damping,
		"maximum_hip_torque": maximum_hip_torque,
		"knee_stiffness": knee_stiffness,
		"knee_damping": knee_damping,
		"maximum_knee_torque": maximum_knee_torque,
		"joint_limit_soft_zone_degrees": joint_limit_soft_zone_degrees,
		"joint_limit_stiffness": joint_limit_stiffness,
		"joint_limit_damping": joint_limit_damping,
		"maximum_joint_limit_torque": maximum_joint_limit_torque,
		"passive_joint_stiffness": passive_joint_stiffness,
		"passive_joint_damping": passive_joint_damping,
		"maximum_passive_joint_torque": maximum_passive_joint_torque,
		"passive_joint_progressive_onset_ratio": passive_joint_progressive_onset_ratio,
		"passive_joint_progressive_ratio": passive_joint_progressive_ratio,
		"passive_joint_native_fraction": passive_joint_native_fraction,
		"limbs": [],
		"attachments": [],
	}
	data["hip_horizontal_response_degrees_per_second"] = (
		hip_horizontal_response_degrees_per_second
	)
	for limb: FourLimbSlotDefinition in limbs:
		var limb_contract = limb.contract_dictionary() if limb != null else {}
		# Installed/missing is a runtime condition exposed through observation masks. It must
		# not make an otherwise compatible damaged body reject the same locomotion model.
		limb_contract.erase("installed")
		(data["limbs"] as Array).append(limb_contract)
	for slot: FourLimbAttachmentSlotDefinition in attachment_slots:
		(data["attachments"] as Array).append(
			slot.contract_dictionary() if slot != null else {}
		)
	# Store the complete canonical contract rather than a short hash. This avoids silently
	# accepting a different anatomy because two 32-bit hashes happened to collide.
	return "%s:%s" % [BODY_PROFILE_ID, JSON.stringify(data)]
