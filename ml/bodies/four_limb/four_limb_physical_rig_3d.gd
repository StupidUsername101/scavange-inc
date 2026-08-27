class_name FourLimbPhysicalRig3D
extends Node3D

const WORLD_COLLISION_MASK := 1
const PHYSICAL_BODY_LAYER := 4
const MAXIMUM_GROUND_PROBE_DISTANCE := 6.0
const MAX_CONTACTS_REPORTED_PER_BODY := 8
const MINIMUM_SUPPORT_NORMAL_UP_DOT := 0.20

#######################################################
# Compatibility adapter from the fixed four-limb ML contract to the generic modular limb stack.
# The chassis and every limb part are ordinary rigid bodies joined by Generic6DOF constraints.
# No Skeleton3D, PhysicalBone3D, hidden gait controller, or virtual foot force is involved.
#######################################################

var owner_body: Node
var definition: FourLimbBodyDefinition
var core_bone: LimbSegment3D
var attachment_feed: FourLimbAttachmentFeed
var limbs_controller: LimbsController3D
var generic_limbs: Array[GenericLimb3D] = []
var limb_records: Array[Dictionary] = []
var commands := FourLimbMLAction.neutral_commands()
var previous_commands := FourLimbMLAction.neutral_commands()
var applied_torque_values := PackedFloat64Array()
var cached_segments: Array[LimbSegment3D] = []
var cached_body_rids: Array[RID] = []
var cached_body_rid_set: Dictionary[RID, bool] = {}
var built := false
var runtime_active := false
# Kept for compatibility with existing diagnostics. Generic limbs have no deferred skeleton bind.
var rest_bindings_finalized := false


func configure(
	body: Node,
	body_definition: FourLimbBodyDefinition
) -> void:
	owner_body = body
	definition = body_definition
	if definition != null:
		definition.ensure_contract()
	if is_inside_tree():
		_build_rig()


func _ready() -> void:
	_build_rig()


func _physics_process(_delta: float) -> void:
	if not runtime_active or not built:
		return
	if not has_finite_physics_state():
		_stop_unstable_simulation()
		return
	# Diagnostics read the controller's live packed torque array. Copying it here every physics tick
	# only duplicates immutable topology-sized data for every worker.


func set_runtime_active(value: bool) -> void:
	runtime_active = value
	set_physics_process(value)
	if not built:
		return
	if is_instance_valid(core_bone):
		core_bone.freeze = not value
		core_bone.sleeping = false
	for limb: GenericLimb3D in generic_limbs:
		if is_instance_valid(limb):
			limb.set_runtime_active(value)
	if is_instance_valid(limbs_controller):
		limbs_controller.set_active(value)


func submit_commands(new_commands: PackedFloat64Array) -> bool:
	if new_commands.size() != FourLimbMLAction.ACTION_COUNT:
		return false
	for value in new_commands:
		if not is_finite(value):
			return false
	for index in range(FourLimbMLAction.ACTION_COUNT):
		previous_commands[index] = commands[index]
		commands[index] = clampf(new_commands[index], -1.0, 1.0)
	return (
		limbs_controller.submit_commands(commands)
		if is_instance_valid(limbs_controller)
		else false
	)


func neutralize_commands() -> void:
	for index in range(FourLimbMLAction.ACTION_COUNT):
		previous_commands[index] = commands[index]
		commands[index] = 0.0
	if is_instance_valid(limbs_controller):
		limbs_controller.neutralize()


func _stop_unstable_simulation() -> void:
	neutralize_commands()
	set_runtime_active(false)
	if is_instance_valid(owner_body):
		owner_body.set("last_failure_reason", "unstable_physics")


func get_core_transform() -> Transform3D:
	return core_bone.global_transform if is_instance_valid(core_bone) else global_transform


func get_core_linear_velocity() -> Vector3:
	return core_bone.linear_velocity if is_instance_valid(core_bone) else Vector3.ZERO


func get_core_angular_velocity() -> Vector3:
	return core_bone.angular_velocity if is_instance_valid(core_bone) else Vector3.ZERO


func get_core_health_ratio() -> float:
	return core_bone.health_ratio() if is_instance_valid(core_bone) else 0.0


func has_finite_physics_state() -> bool:
	if cached_segments.is_empty():
		return false
	for segment: LimbSegment3D in cached_segments:
		if not is_instance_valid(segment) or not segment.has_finite_state():
			return false
	return true


func refresh_attachment_mass() -> void:
	if not is_instance_valid(core_bone) or definition == null:
		return
	core_bone.mass = definition.core_mass + (
		attachment_feed.total_contributed_mass()
		if is_instance_valid(attachment_feed)
		else 0.0
	)
	_refresh_cached_query_topology()


func apply_core_impulse(world_impulse: Vector3, world_position: Vector3) -> bool:
	if (
		not is_instance_valid(core_bone)
		or not world_impulse.is_finite()
		or not world_position.is_finite()
	):
		return false
	core_bone.apply_impulse(world_impulse, world_position - core_bone.global_position)
	return true


func get_all_body_rids() -> Array[RID]:
	return cached_body_rids.duplicate()


func _refresh_cached_query_topology() -> void:
	cached_segments.clear()
	cached_body_rids.clear()
	cached_body_rid_set.clear()
	if is_instance_valid(core_bone):
		cached_segments.append(core_bone)
		_append_cached_body_rid(core_bone.get_rid())
	for limb: GenericLimb3D in generic_limbs:
		if not is_instance_valid(limb):
			continue
		for segment: LimbSegment3D in limb.segments:
			if not is_instance_valid(segment):
				continue
			cached_segments.append(segment)
			_append_cached_body_rid(segment.get_rid())
	if is_instance_valid(attachment_feed):
		for rid: RID in attachment_feed.collision_rids_for_body_queries():
			_append_cached_body_rid(rid)


func _append_cached_body_rid(rid: RID) -> void:
	if not rid.is_valid() or cached_body_rid_set.has(rid):
		return
	cached_body_rids.append(rid)
	cached_body_rid_set[rid] = true


func set_limb_effectiveness(limb_index: int, value: float) -> bool:
	var record := _record_for_limb(limb_index)
	if record.is_empty():
		return false
	var effectiveness := clampf(value, 0.0, 1.0)
	var chain := record.get("chain") as GenericLimb3D
	if not is_instance_valid(chain):
		return false
	for segment: LimbSegment3D in chain.segments:
		segment.actuator_effectiveness = effectiveness
	return true


func damage_limb(limb_index: int, amount: float) -> bool:
	var record := _record_for_limb(limb_index)
	if record.is_empty():
		return false
	var chain := record.get("chain") as GenericLimb3D
	if not is_instance_valid(chain) or chain.segments.is_empty():
		return false
	var damage_per_segment := maxf(amount, 0.0) / float(chain.segments.size())
	for segment: LimbSegment3D in chain.segments:
		segment.apply_segment_damage(damage_per_segment)
	return true


func capture_ml_state(contact_snapshot: Dictionary = {}) -> Dictionary:
	var contacts := (
		contact_snapshot
		if not contact_snapshot.is_empty()
		else world_contact_snapshot()
	)
	return {
		"body": body_snapshot(contacts),
		"limbs": all_limb_snapshots(contacts),
		"contacts": contacts,
	}


func limb_snapshot(
	limb_index: int,
	contact_snapshot: Dictionary = {}
) -> Dictionary:
	if (
		definition == null
		or limb_index < 0
		or limb_index >= FourLimbBodyDefinition.LIMB_SLOT_COUNT
	):
		return {}
	var slot := definition.limbs[limb_index]
	if slot == null:
		return _missing_limb_snapshot(limb_index, "Limb %d" % limb_index)
	var record := _record_for_limb(limb_index)
	if record.is_empty():
		return _missing_limb_snapshot(limb_index, slot.slot_name)
	var chain := record.get("chain") as GenericLimb3D
	var upper := record.get("upper") as LimbSegment3D
	var lower := record.get("lower") as LimbSegment3D
	var hip_record: Dictionary = record.get("hip_joint", {})
	var knee_record: Dictionary = record.get("knee_joint", {})
	if (
		not is_instance_valid(chain)
		or not is_instance_valid(upper)
		or not is_instance_valid(lower)
		or hip_record.is_empty()
		or knee_record.is_empty()
	):
		return _missing_limb_snapshot(limb_index, slot.slot_name)

	var core_transform := get_core_transform()
	var to_core := core_transform.affine_inverse()
	var core_basis_inverse: Basis = to_core.basis
	var foot_position := chain.foot_world_position()
	var foot_velocity := chain.foot_world_velocity()
	var foot_up_world: Vector3 = Vector3.UP
	if is_instance_valid(chain.end_effector) and not chain.end_effector.disabled:
		var terminal_up: Vector3 = chain.end_effector.global_basis.y
		if terminal_up.is_finite() and terminal_up.length_squared() > 0.000001:
			foot_up_world = terminal_up.normalized()
	var support_contact_count: int = _contact_array_integer(
		contact_snapshot,
		"limb_distal_support_contact_counts",
		limb_index
	)
	var has_authoritative_foot_contacts: bool = contact_snapshot.has(
		"limb_distal_support_contact_counts"
	)
	var support_normal_world: Vector3 = _contact_array_vector3(
		contact_snapshot,
		"limb_support_normals_world",
		limb_index
	)
	var authoritative_support: bool = (
		has_authoritative_foot_contacts
		and support_contact_count > 0
		and support_normal_world.is_finite()
		and support_normal_world.length_squared() > 0.000001
	)
	var ground: Dictionary = (
		{
			"hit": true,
			"distance": 0.08,
			"normal": support_normal_world.normalized(),
		}
		if authoritative_support
		else _ground_probe(foot_position + Vector3.UP * 0.08, 2.5)
	)
	var ray_contact := (
		bool(ground.get("hit", false))
		and float(ground.get("distance", 99.0)) <= slot.segment_radius + 0.12
	)
	var ground_normal_world: Vector3 = ground.get("normal", Vector3.UP)
	var hip_angles: Vector3 = hip_record.get("current_angles", Vector3.ZERO)
	var knee_angles: Vector3 = knee_record.get("current_angles", Vector3.ZERO)
	var hip_targets: Vector3 = hip_record.get("target_angles", Vector3.ZERO)
	var knee_targets: Vector3 = knee_record.get("target_angles", Vector3.ZERO)
	# External joint order is [hip elevation, hip horizontal sweep, knee]. The profile-v9 hip frame
	# uses Z for radial elevation and X (core-local up at rest) for horizontal coxa sweep.
	var current_angles := Vector3(hip_angles.z, hip_angles.x, knee_angles.z)
	var target_angles := Vector3(hip_targets.z, hip_targets.x, knee_targets.z)
	var hip_target_errors: Vector3 = hip_record.get(
		"target_error_angles",
		Vector3(
			_wrap_angle(hip_targets.x - hip_angles.x),
			_wrap_angle(hip_targets.y - hip_angles.y),
			_wrap_angle(hip_targets.z - hip_angles.z)
		)
	)
	var knee_target_errors: Vector3 = knee_record.get(
		"target_error_angles",
		Vector3(
			_wrap_angle(knee_targets.x - knee_angles.x),
			_wrap_angle(knee_targets.y - knee_angles.y),
			_wrap_angle(knee_targets.z - knee_angles.z)
		)
	)
	# Profile v9 keeps coordinate error as wrapped target-minus-measured values in the current
	# [elevation, horizontal sweep, knee] order. The exact quaternion-space actuator error remains
	# available separately for diagnostics below.
	var target_errors := Vector3(
		_wrap_angle(target_angles.x - current_angles.x),
		_wrap_angle(target_angles.y - current_angles.y),
		_wrap_angle(target_angles.z - current_angles.z)
	)
	var controller_target_errors := Vector3(
		hip_target_errors.z,
		hip_target_errors.x,
		knee_target_errors.z
	)
	var hip_rest_errors: Vector3 = hip_record.get("rest_error_angles", Vector3.ZERO)
	var knee_rest_errors: Vector3 = knee_record.get("rest_error_angles", Vector3.ZERO)
	var rest_pose_errors := Vector3(
		hip_rest_errors.z,
		hip_rest_errors.x,
		knee_rest_errors.z
	)
	var hip_speeds := _joint_angular_speeds(hip_record)
	var knee_speeds := _joint_angular_speeds(knee_record)
	var action_offset := FourLimbMLAction.action_offset(limb_index, 0)
	var upper_health := upper.health_ratio()
	var lower_health := lower.health_ratio()
	var functional := minf(upper.functional_ratio(), lower.functional_ratio())
	var live_torques := (
		limbs_controller.applied_torques
		if is_instance_valid(limbs_controller)
		else applied_torque_values
	)
	var world_contact_count := _contact_array_integer(
		contact_snapshot,
		"limb_world_contact_counts",
		limb_index
	)
	var wall_contact_count := _contact_array_integer(
		contact_snapshot,
		"limb_wall_contact_counts",
		limb_index
	)
	var wall_contact_impulse := _contact_array_float(
		contact_snapshot,
		"limb_maximum_wall_impulses",
		limb_index
	)
	var distal_contact_count := _contact_array_integer(
		contact_snapshot,
		"limb_distal_contact_counts",
		limb_index
	)
	var contact := support_contact_count > 0 if has_authoritative_foot_contacts else ray_contact
	var support_relative_speed := _contact_array_float(
		contact_snapshot,
		"limb_maximum_support_relative_speeds",
		limb_index
	)
	if (
		has_authoritative_foot_contacts
		and contact
		and support_normal_world.is_finite()
		and support_normal_world.length_squared() > 0.000001
	):
		ground_normal_world = support_normal_world.normalized()
	var effector_snapshot := chain.end_effector_snapshot()
	var grip_attached := bool(effector_snapshot.get("attached", false))
	var grip_candidate_present: bool = bool(effector_snapshot.get("candidate_present", false))
	var grip_target_available: bool = grip_attached or grip_candidate_present
	var grip_origin_world: Vector3 = _dictionary_vector3(
		effector_snapshot,
		"position_world",
		foot_position
	)
	if grip_attached:
		grip_origin_world = _dictionary_vector3(
			effector_snapshot,
			"attached_owner_point_world",
			grip_origin_world
		)
	elif grip_candidate_present:
		grip_origin_world = _dictionary_vector3(
			effector_snapshot,
			"candidate_owner_point_world",
			grip_origin_world
		)
	var grip_target_point_world: Vector3 = (
		_dictionary_vector3(
			effector_snapshot,
			"attached_point_world" if grip_attached else "candidate_point_world",
			grip_origin_world
		)
		if grip_target_available
		else grip_origin_world
	)
	var grip_target_normal_world: Vector3 = (
		_dictionary_vector3(
			effector_snapshot,
			"attached_normal_world" if grip_attached else "candidate_normal_world",
			Vector3.UP
		)
		if grip_target_available
		else Vector3.UP
	)
	var grip_candidate_tags: Variant = effector_snapshot.get(
		"candidate_surface_tags",
		PackedStringArray()
	)
	var grip_attached_tags: Variant = effector_snapshot.get(
		"attached_surface_tags",
		PackedStringArray()
	)
	return {
		"slot_index": limb_index,
		"slot_name": slot.slot_name,
		"installed": true,
		"functional": functional > 0.001,
		"health_ratio": minf(upper_health, lower_health),
		"actuator_effectiveness": functional,
		"hip_offset_local": slot.hip_offset,
		"upper_length": slot.upper_length,
		"lower_length": slot.lower_length,
		"joint_angles": current_angles,
		# Diagnostic-only physical limits. The feature encoder intentionally ignores these,
		# so reward logic can protect real anatomy without changing the model tensor schema.
		"joint_limit_lower": record.get("joint_limit_lower", Vector3.ZERO),
		"joint_limit_upper": record.get("joint_limit_upper", Vector3.ZERO),
		"joint_target_angles": target_angles,
		"joint_target_errors": target_errors,
		"controller_target_errors": controller_target_errors,
		"rest_pose_errors": rest_pose_errors,
		"joint_angular_velocities": Vector3(hip_speeds.z, hip_speeds.x, knee_speeds.z),
		"previous_commands": Vector3(
			previous_commands[action_offset],
			previous_commands[action_offset + 1],
			previous_commands[action_offset + 2]
		),
		"commands": Vector3(
			commands[action_offset],
			commands[action_offset + 1],
			commands[action_offset + 2]
		),
		"applied_torque": Vector3(
			_safe_packed_value(live_torques, action_offset),
			_safe_packed_value(live_torques, action_offset + 1),
			_safe_packed_value(live_torques, action_offset + 2)
		),
		"saturation": Vector3(
			1.0 if absf(commands[action_offset]) >= 0.98 else 0.0,
			1.0 if absf(commands[action_offset + 1]) >= 0.98 else 0.0,
			1.0 if absf(commands[action_offset + 2]) >= 0.98 else 0.0
		),
		"foot_position_local": to_core * foot_position,
		"foot_velocity_local": core_basis_inverse * foot_velocity,
		"foot_up_local": core_basis_inverse * foot_up_world,
		"foot_contact": contact,
		"ground_normal_local": core_basis_inverse * ground_normal_world,
		"foot_clearance": (
			0.0
			if has_authoritative_foot_contacts and contact
			else maxf(float(ground.get("distance", 2.5)) - 0.08, 0.0)
		),
		"foot_slip_speed": (
			support_relative_speed
			if has_authoritative_foot_contacts and contact
			else (
				Vector3(foot_velocity.x, 0.0, foot_velocity.z).length()
				if contact
				else 0.0
			)
		),
		"distal_contact_count": distal_contact_count,
		"support_contact_count": support_contact_count,
		"world_contact_count": world_contact_count,
		"wall_contact": wall_contact_count > 0,
		"wall_contact_count": wall_contact_count,
		"maximum_wall_contact_impulse": wall_contact_impulse,
		"grip_present": (
			bool(effector_snapshot.get("present", false))
			and int(effector_snapshot.get(
				"grip_mode",
				LimbEndEffectorDefinition.GripMode.NONE
			)) != LimbEndEffectorDefinition.GripMode.NONE
		),
		"grip_command": _safe_packed_value(
			commands,
			FourLimbMLAction.grip_action_offset(limb_index)
		),
		"grip_activation": float(effector_snapshot.get("activation", 0.0)),
		"grip_requires_rearm": bool(effector_snapshot.get("requires_rearm", false)),
		"grip_candidate_present": grip_candidate_present,
		# Candidate state remains available for pre-latch reach shaping. The policy-facing grip target is
		# unified instead: before attachment it is the best compatible candidate, after attachment it is
		# the actual anchor. This avoids the old contradictory state where the offset pointed at the
		# attachment anchor while candidate_present was false and candidate distance encoded as far.
		"grip_candidate_distance": float(effector_snapshot.get("candidate_distance", 0.0)),
		"grip_target_present": grip_target_available,
		"grip_target_offset_local": core_basis_inverse * (grip_target_point_world - grip_origin_world),
		"grip_target_normal_local": core_basis_inverse * grip_target_normal_world,
		"grip_target_distance": (
			grip_origin_world.distance_to(grip_target_point_world)
			if grip_target_available
			else float(effector_snapshot.get("grip_detection_radius", 0.0))
		),
		"grip_candidate_dynamic": bool(effector_snapshot.get("candidate_dynamic", false)),
		"grip_candidate_target_mass": float(effector_snapshot.get("candidate_target_mass", 0.0)),
		"grip_candidate_climbable": GenericGrip3D.surface_tags_have(grip_candidate_tags, "climbable"),
		"grip_candidate_carryable": GenericGrip3D.surface_tags_have(grip_candidate_tags, "carryable"),
		"grip_attached": grip_attached,
		"grip_attached_dynamic": bool(effector_snapshot.get("attached_dynamic", false)),
		"grip_attached_target_id": int(effector_snapshot.get("attached_target_id", 0)),
		"grip_attached_target_mass": float(effector_snapshot.get("attached_target_mass", 0.0)),
		"grip_attached_surface_tags": grip_attached_tags,
		"grip_attached_climbable": GenericGrip3D.surface_tags_have(grip_attached_tags, "climbable"),
		"grip_attached_carryable": GenericGrip3D.surface_tags_have(grip_attached_tags, "carryable"),
		"grip_load_ratio": float(effector_snapshot.get("load_ratio", 0.0)),
		"grip_pickup_sequence": int(effector_snapshot.get("pickup_sequence", 0)),
		"end_effector": effector_snapshot,
	}


func release_all_grips() -> void:
	# Pausing deliberately preserves grip state so a held object does not detach just because the
	# user paused training. Episode termination is different: a finished worker must surrender any
	# shared cargo immediately so sibling workers are not left competing with a frozen owner.
	for limb: GenericLimb3D in generic_limbs:
		if is_instance_valid(limb) and is_instance_valid(limb.end_effector):
			limb.end_effector.release_grip()


func holds_instance_id(instance_id: int) -> bool:
	if instance_id <= 0:
		return false
	for limb: GenericLimb3D in generic_limbs:
		if is_instance_valid(limb) and is_instance_valid(limb.end_effector):
			if limb.end_effector.holds_instance_id(instance_id):
				return true
	return false


func body_snapshot(contact_snapshot: Dictionary = {}) -> Dictionary:
	var transform_value := get_core_transform()
	var ground := _ground_probe(transform_value.origin, MAXIMUM_GROUND_PROBE_DISTANCE)
	var half_height = definition.core_size.y * 0.5 if definition != null else 0.0
	var clearance := maxf(
		float(ground.get("distance", MAXIMUM_GROUND_PROBE_DISTANCE)) - half_height,
		0.0
	)
	var preferred_core_height = (
		definition.preferred_core_height()
		if definition != null
		else half_height
	)
	var preferred_ground_clearance := maxf(preferred_core_height - half_height, 0.0)
	var contacts := (
		contact_snapshot
		if not contact_snapshot.is_empty()
		else world_contact_snapshot()
	)
	var core_contact := bool(contacts.get("core_contact", false)) or clearance <= 0.08
	# Keep support authoritative: proximity alone is not enough to say that the chassis carries
	# load. This distinction is used by the policy and reward to identify real chassis crawling.
	var core_support_contact := bool(contacts.get("core_support_contact", false))
	return {
		"transform_world": transform_value,
		"position_world": transform_value.origin,
		"basis_world": transform_value.basis,
		"linear_velocity_world": get_core_linear_velocity(),
		"angular_velocity_world": get_core_angular_velocity(),
		"uprightness": clampf(
			transform_value.basis.y.normalized().dot(Vector3.UP),
			-1.0,
			1.0
		),
		"ground_clearance": clearance,
		"preferred_core_height": preferred_core_height,
		"preferred_ground_clearance": preferred_ground_clearance,
		"ground_clearance_error": clearance - preferred_ground_clearance,
		"core_contact": core_contact,
		"core_support_contact": core_support_contact,
		"core_wall_contact": bool(contacts.get("core_wall_contact", false)),
		"world_contact_count": int(contacts.get("contact_count", 0)),
		"wall_contact_count": int(contacts.get("wall_contact_count", 0)),
		"maximum_contact_impulse": float(contacts.get("maximum_contact_impulse", 0.0)),
		"ground_normal_world": ground.get("normal", Vector3.UP),
		"health_ratio": get_core_health_ratio(),
		"mass": total_mass(),
	}


func all_limb_snapshots(contact_snapshot: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		result.append(limb_snapshot(limb_index, contact_snapshot))
	return result


func limb_hip_world_position(limb_index: int) -> Vector3:
	var record := _record_for_limb(limb_index)
	if record.is_empty():
		return Vector3(INF, INF, INF)
	var upper := record.get("upper") as LimbSegment3D
	var slot: FourLimbSlotDefinition
	if definition != null and limb_index >= 0 and limb_index < definition.limbs.size():
		slot = definition.limbs[limb_index]
	if not is_instance_valid(upper) or slot == null:
		return Vector3(INF, INF, INF)
	return upper.global_position - upper.global_basis.y.normalized() * slot.upper_length * 0.5


func authored_limb_hip_world_position(limb_index: int) -> Vector3:
	if (
		definition == null
		or limb_index < 0
		or limb_index >= definition.limbs.size()
		or definition.limbs[limb_index] == null
	):
		return Vector3(INF, INF, INF)
	return get_core_transform() * definition.limbs[limb_index].hip_offset


func maximum_limb_mount_error() -> float:
	var result := 0.0
	for limb_index in range(limb_records.size()):
		if limb_records[limb_index].is_empty():
			continue
		var physical_hip := limb_hip_world_position(limb_index)
		var authored_hip := authored_limb_hip_world_position(limb_index)
		if not physical_hip.is_finite() or not authored_hip.is_finite():
			return INF
		result = maxf(result, physical_hip.distance_to(authored_hip))
	return result


func minimum_limb_mount_separation() -> float:
	var positions: Array[Vector3] = []
	for limb_index in range(limb_records.size()):
		if limb_records[limb_index].is_empty():
			continue
		var position := authored_limb_hip_world_position(limb_index)
		if not position.is_finite():
			return 0.0
		positions.append(position)
	if positions.size() < 2:
		return 0.0
	var result := INF
	for left_index in range(positions.size()):
		for right_index in range(left_index + 1, positions.size()):
			result = minf(result, positions[left_index].distance_to(positions[right_index]))
	return result if is_finite(result) else 0.0


func world_contact_snapshot() -> Dictionary:
	var limb_world_contact_counts := PackedInt32Array()
	limb_world_contact_counts.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_world_contact_counts.fill(0)
	var limb_wall_contact_counts := PackedInt32Array()
	limb_wall_contact_counts.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_wall_contact_counts.fill(0)
	var limb_maximum_wall_impulses := PackedFloat64Array()
	limb_maximum_wall_impulses.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_maximum_wall_impulses.fill(0.0)
	var limb_distal_contact_counts := PackedInt32Array()
	limb_distal_contact_counts.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_distal_contact_counts.fill(0)
	var limb_distal_support_contact_counts := PackedInt32Array()
	limb_distal_support_contact_counts.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_distal_support_contact_counts.fill(0)
	var limb_maximum_support_relative_speeds := PackedFloat64Array()
	limb_maximum_support_relative_speeds.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_maximum_support_relative_speeds.fill(0.0)
	var limb_support_normals_world := PackedVector3Array()
	limb_support_normals_world.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_support_normals_world.fill(Vector3.ZERO)
	var limb_maximum_support_impulses := PackedFloat64Array()
	limb_maximum_support_impulses.resize(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	limb_maximum_support_impulses.fill(0.0)
	var result := {
		"contact_count": 0,
		"wall_contact_count": 0,
		"core_contact": false,
		"core_support_contact": false,
		"core_wall_contact": false,
		"maximum_contact_impulse": 0.0,
		"wall_contacts": [],
		"limb_world_contact_counts": limb_world_contact_counts,
		"limb_wall_contact_counts": limb_wall_contact_counts,
		"limb_maximum_wall_impulses": limb_maximum_wall_impulses,
		"limb_distal_contact_counts": limb_distal_contact_counts,
		"limb_distal_support_contact_counts": limb_distal_support_contact_counts,
		"limb_maximum_support_relative_speeds": limb_maximum_support_relative_speeds,
		"limb_support_normals_world": limb_support_normals_world,
		"limb_maximum_support_impulses": limb_maximum_support_impulses,
	}
	if not built or not runtime_active:
		return result
	for body: LimbSegment3D in cached_segments:
		var rid := body.get_rid()
		if not rid.is_valid():
			continue
		var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(rid)
		if state == null:
			continue
		var count := state.get_contact_count()
		result["contact_count"] = int(result["contact_count"]) + count
		if body.limb_slot_index >= 0 and body.limb_slot_index < FourLimbBodyDefinition.LIMB_SLOT_COUNT:
			limb_world_contact_counts[body.limb_slot_index] += count
		if body == core_bone and count > 0:
			result["core_contact"] = true
		var is_distal_segment := _is_distal_limb_segment(body)
		for contact_index in range(count):
			var impulse := state.get_contact_impulse(contact_index).length()
			result["maximum_contact_impulse"] = maxf(
				float(result["maximum_contact_impulse"]),
				impulse
			)
			var collider_rid := state.get_contact_collider(contact_index)
			var own_rig_contact: bool = cached_body_rid_set.has(collider_rid)
			# Despite the legacy "local" name, Godot returns this contact normal in global space.
			var contact_normal := state.get_contact_local_normal(contact_index)
			var finite_contact_normal := (
				contact_normal.is_finite()
				and contact_normal.length_squared() > 0.000001
			)
			if finite_contact_normal:
				contact_normal = contact_normal.normalized()
			var support_contact := (
				not own_rig_contact
				and finite_contact_normal
				and contact_normal.dot(Vector3.UP) >= MINIMUM_SUPPORT_NORMAL_UP_DOT
			)
			if body == core_bone and support_contact:
				result["core_support_contact"] = true
			var wall := _training_wall_node(state.get_contact_collider_object(contact_index))
			if is_distal_segment and not own_rig_contact:
				var limb_index: int = body.limb_slot_index
				limb_distal_contact_counts[limb_index] += 1
				# With an authored physical foot, only support delivered through that terminal shape is
				# a planted-foot contact. The lower capsule may still collide with the floor/wall, but
				# treating a shin scrape as foot support teaches the reward/observation the wrong posture.
				var planted_foot_contact: bool = _contact_is_load_bearing_foot_shape(
					body,
					state,
					contact_index
				)
				if support_contact and planted_foot_contact:
					limb_distal_support_contact_counts[limb_index] += 1
					if impulse >= limb_maximum_support_impulses[limb_index]:
						limb_maximum_support_impulses[limb_index] = impulse
						limb_support_normals_world[limb_index] = contact_normal
					var relative_velocity: Vector3 = (
						state.get_contact_local_velocity_at_position(contact_index)
						- state.get_contact_collider_velocity_at_position(contact_index)
					)
					if relative_velocity.is_finite():
						var slip_velocity: Vector3 = relative_velocity
						slip_velocity -= contact_normal * slip_velocity.dot(contact_normal)
						limb_maximum_support_relative_speeds[limb_index] = maxf(
							limb_maximum_support_relative_speeds[limb_index],
							slip_velocity.length()
						)
			if wall == null:
				continue
			result["wall_contact_count"] = int(result["wall_contact_count"]) + 1
			if body == core_bone:
				result["core_wall_contact"] = true
			elif body.limb_slot_index >= 0 and body.limb_slot_index < FourLimbBodyDefinition.LIMB_SLOT_COUNT:
				limb_wall_contact_counts[body.limb_slot_index] += 1
				limb_maximum_wall_impulses[body.limb_slot_index] = maxf(
					limb_maximum_wall_impulses[body.limb_slot_index],
					impulse
				)
			var contacts: Array = result["wall_contacts"]
			contacts.append({
				"wall": wall,
				"position_world": state.get_contact_collider_position(contact_index),
				"impulse": impulse,
				"limb_index": body.limb_slot_index,
				"segment_index": body.segment_index,
			})
	return result


func total_mass() -> float:
	var result := core_bone.mass if is_instance_valid(core_bone) else 0.0
	for limb: GenericLimb3D in generic_limbs:
		if is_instance_valid(limb):
			result += limb.total_mass()
	return result


func installed_limb_chain_count() -> int:
	var result := 0
	for limb: GenericLimb3D in generic_limbs:
		if is_instance_valid(limb) and limb.has_valid_topology():
			result += 1
	return result


func physical_limb_segment_count() -> int:
	var result := 0
	for limb: GenericLimb3D in generic_limbs:
		if is_instance_valid(limb):
			result += limb.segments.size()
	return result


func has_exact_four_limb_topology() -> bool:
	if definition == null or limb_records.size() != FourLimbBodyDefinition.LIMB_SLOT_COUNT:
		return false
	var expected_chains := 0
	var expected_segments := 0
	for slot: FourLimbSlotDefinition in definition.limbs:
		if slot != null and slot.installed:
			expected_chains += 1
			expected_segments += 2
	return (
		installed_limb_chain_count() == expected_chains
		and physical_limb_segment_count() == expected_segments
	)


func has_safe_joint_constraints() -> bool:
	if definition == null or limb_records.size() != FourLimbBodyDefinition.LIMB_SLOT_COUNT:
		return false
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var slot := definition.limbs[limb_index]
		var record := limb_records[limb_index]
		if slot == null or not slot.installed:
			if not record.is_empty():
				return false
			continue
		var chain := record.get("chain") as GenericLimb3D
		if not is_instance_valid(chain) or chain.joints.size() != 2:
			return false
		var hip := chain.joints[0]
		var knee := chain.joints[1]
		if not _joint_has_locked_translation(hip) or not _joint_has_locked_translation(knee):
			return false
		var hip_definition := chain.joint_records[0].get("definition") as LimbJointDefinition
		var upper_definition: LimbSegmentDefinition = chain.definition.segments[0]
		if hip_definition == null or upper_definition == null:
			return false
		var expected_hip_basis := hip_joint_basis_for_slot(
			slot,
			upper_definition.rest_direction_local
		)
		if (
			absf(
				hip_definition.joint_basis_local.x.normalized().dot(Vector3.UP)
			) < 0.999
			or absf(
				hip_definition.joint_basis_local.z.normalized().dot(
					expected_hip_basis.z.normalized()
				)
			) < 0.999
			or not _joint_axis_matches(hip, Vector3.AXIS_X, -slot.hip_twist_span_degrees, slot.hip_twist_span_degrees)
			or not _joint_axis_matches(hip, Vector3.AXIS_Y, 0.0, 0.0)
			or not _joint_axis_matches(
				hip,
				Vector3.AXIS_Z,
				-slot.hip_swing_span_degrees,
				slot.hip_swing_span_degrees + slot.hip_elevation_upper_extension_degrees
			)
			or not _joint_axis_matches(knee, Vector3.AXIS_X, 0.0, 0.0)
			or not _joint_axis_matches(knee, Vector3.AXIS_Y, 0.0, 0.0)
			or not _joint_axis_matches(knee, Vector3.AXIS_Z, slot.knee_limit_lower_degrees, slot.knee_limit_upper_degrees)
		):
			return false
	return true


func has_passive_rest_elasticity() -> bool:
	if not is_instance_valid(limbs_controller):
		return false
	for limb: GenericLimb3D in generic_limbs:
		if not is_instance_valid(limb) or not limb.has_configured_native_springs():
			return false
		for record: Dictionary in limb.joint_records:
			var joint_definition := record.get("definition") as LimbJointDefinition
			if joint_definition == null:
				return false
			for axis in range(3):
				if not joint_definition.axis_is_free(axis):
					continue
				if (
					joint_definition.passive_stiffness[axis] <= 0.0
					or joint_definition.passive_damping[axis] <= 0.0
					or joint_definition.maximum_passive_torque[axis] <= 0.0
					or joint_definition.passive_progressive_ratio[axis] <= 0.0
					or joint_definition.passive_progressive_onset_ratio >= 0.95
					or (
						joint_definition.use_native_passive_spring
						and joint_definition.native_passive_fraction <= 0.0
					)
				):
					return false
	return true


func has_valid_physical_bindings(require_simulating: bool = false) -> bool:
	if (
		not built
		or not rest_bindings_finalized
		or not is_instance_valid(core_bone)
		or not core_bone.get_rid().is_valid()
		or not has_exact_four_limb_topology()
		or not has_safe_joint_constraints()
		or not is_instance_valid(limbs_controller)
	):
		return false
	if require_simulating and (not runtime_active or core_bone.freeze):
		return false
	for limb: GenericLimb3D in generic_limbs:
		if not is_instance_valid(limb) or not limb.has_valid_topology():
			return false
		for segment: LimbSegment3D in limb.segments:
			if not segment.get_rid().is_valid() or (require_simulating and segment.freeze):
				return false
		for joint: Generic6DOFJoint3D in limb.joints:
			if joint.node_a == NodePath() or joint.node_b == NodePath():
				return false
	return true


func _build_rig() -> void:
	if built or definition == null or not is_instance_valid(owner_body):
		return
	built = true
	name = "FourLimbPhysicalRig"
	limb_records.clear()
	generic_limbs.clear()
	applied_torque_values.resize(FourLimbMLAction.ACTION_COUNT)
	applied_torque_values.fill(0.0)
	_create_core_body()
	_add_limb_mount_visuals()
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		_build_four_limb_slot(limb_index)
	_configure_self_collision_exceptions()
	attachment_feed = FourLimbAttachmentFeed.new()
	attachment_feed.name = "AttachmentFeed"
	core_bone.add_child(attachment_feed)
	attachment_feed.configure(definition.attachment_slots)
	refresh_attachment_mass()
	limbs_controller = LimbsController3D.new()
	limbs_controller.name = "LimbsController"
	limbs_controller.process_physics_priority = -20
	add_child(limbs_controller)
	limbs_controller.configure(
		core_bone,
		generic_limbs,
		FourLimbMLAction.ACTION_COUNT,
		_reserved_noop_action_indices()
	)
	# Packed arrays use shared storage. Keep the legacy diagnostic field as a live alias instead of
	# copying all actuator torques after every physics step.
	applied_torque_values = limbs_controller.applied_torques
	_refresh_cached_query_topology()
	rest_bindings_finalized = true


func _create_core_body() -> void:
	core_bone = LimbSegment3D.new()
	core_bone.name = "Core"
	core_bone.configure(owner_body, -1, -1, &"body_root", definition.core_maximum_health)
	core_bone.mass = definition.core_mass
	core_bone.configure_surface_material(definition.friction, definition.bounce)
	core_bone.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	core_bone.linear_damp = definition.linear_damp
	core_bone.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	core_bone.angular_damp = definition.angular_damp
	core_bone.continuous_cd = true
	core_bone.can_sleep = false
	core_bone.freeze = true
	core_bone.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	core_bone.collision_layer = PHYSICAL_BODY_LAYER
	core_bone.collision_mask = WORLD_COLLISION_MASK
	core_bone.max_contacts_reported = MAX_CONTACTS_REPORTED_PER_BODY
	core_bone.contact_monitor = true
	core_bone.rest_transform_local = Transform3D.IDENTITY
	add_child(core_bone)
	core_bone.transform = Transform3D.IDENTITY
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = definition.core_size
	collision.shape = shape
	core_bone.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = definition.core_size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.28, 0.46, 0.56, 1.0)
	material.roughness = 0.72
	visual.material_override = material
	core_bone.add_child(visual)


func _add_limb_mount_visuals() -> void:
	for limb_index in range(definition.limbs.size()):
		var slot := definition.limbs[limb_index]
		if slot == null or not slot.installed:
			continue
		var mount := MeshInstance3D.new()
		mount.name = "LimbMount%02d" % limb_index
		mount.position = slot.hip_offset
		var sphere := SphereMesh.new()
		sphere.radius = maxf(slot.segment_radius * 1.35, 0.07)
		sphere.height = sphere.radius * 2.0
		mount.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = _limb_color(limb_index, false).lightened(0.12)
		material.roughness = 0.55
		mount.material_override = material
		core_bone.add_child(mount)


func _build_four_limb_slot(limb_index: int) -> void:
	var slot := definition.limbs[limb_index]
	if slot == null or not slot.installed:
		limb_records.append({})
		return
	var points := LimbKinematics.solve_two_bone(
		slot.hip_offset,
		slot.rest_foot_offset,
		slot.upper_length,
		slot.lower_length,
		slot.bend_hint
	)
	if points.size() != 3:
		limb_records.append({})
		return
	var limb_definition := _generic_definition_from_slot(slot, limb_index, points)
	var chain := GenericLimb3D.new()
	chain.name = "Limb%02d" % limb_index
	add_child(chain)
	chain.configure(
		owner_body,
		core_bone,
		limb_definition,
		limb_index,
		_limb_color(limb_index, false),
		PHYSICAL_BODY_LAYER,
		WORLD_COLLISION_MASK,
		true,
		false
	)
	if not chain.has_valid_topology() or chain.segments.size() != 2:
		chain.queue_free()
		limb_records.append({})
		return
	generic_limbs.append(chain)
	limb_records.append({
		"slot_index": limb_index,
		"chain": chain,
		"upper": chain.segments[0],
		"lower": chain.segments[1],
		"hip_joint": chain.joint_records[0],
		"knee_joint": chain.joint_records[1],
		"points": points,
		"joint_limit_lower": Vector3(
			deg_to_rad(-slot.hip_swing_span_degrees),
			deg_to_rad(-slot.hip_twist_span_degrees),
			deg_to_rad(slot.knee_limit_lower_degrees)
		),
		"joint_limit_upper": Vector3(
			deg_to_rad(
				slot.hip_swing_span_degrees + slot.hip_elevation_upper_extension_degrees
			),
			deg_to_rad(slot.hip_twist_span_degrees),
			deg_to_rad(slot.knee_limit_upper_degrees)
		),
	})


static func hip_joint_basis_for_slot(
	slot: FourLimbSlotDefinition,
	upper_direction: Vector3
) -> Basis:
	return FourLimbGenericDefinitionFactory.hip_joint_basis_for_slot(slot, upper_direction)

func _generic_definition_from_slot(
	slot: FourLimbSlotDefinition,
	limb_index: int,
	points: PackedVector3Array
) -> GenericLimbDefinition:
	return FourLimbGenericDefinitionFactory.create_limb_definition_from_points(
		definition,
		slot,
		limb_index,
		points,
		FourLimbMLAction.action_offset(limb_index, 0)
	)

func _reserved_noop_action_indices() -> PackedInt32Array:
	# Fixed model profiles keep stable slots across missing limbs and mixed terminal hardware. A
	# reserved output is accepted and observed as a harmless zero-response actuator rather than
	# making the complete controller mapping invalid.
	var result := PackedInt32Array()
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var record: Dictionary = limb_records[limb_index] if limb_index < limb_records.size() else {}
		if record.is_empty():
			for actuator_index in range(FourLimbMLAction.ACTIONS_PER_LIMB):
				result.append(FourLimbMLAction.action_offset(limb_index, actuator_index))
			continue
		var chain := record.get("chain") as GenericLimb3D
		var effector: LimbEndEffectorDefinition = null
		if is_instance_valid(chain) and chain.definition != null:
			effector = chain.definition.end_effector
		if effector == null or not effector.has_mapped_grip_action():
			result.append(FourLimbMLAction.grip_action_offset(limb_index))
	return result


func _configure_self_collision_exceptions() -> void:
	var bodies: Array[LimbSegment3D] = []
	if is_instance_valid(core_bone):
		bodies.append(core_bone)
	for limb: GenericLimb3D in generic_limbs:
		if not is_instance_valid(limb):
			continue
		for segment: LimbSegment3D in limb.segments:
			if is_instance_valid(segment):
				bodies.append(segment)
	for left_index in range(bodies.size()):
		for right_index in range(left_index + 1, bodies.size()):
			bodies[left_index].add_collision_exception_with(bodies[right_index])
			bodies[right_index].add_collision_exception_with(bodies[left_index])


func _record_for_limb(limb_index: int) -> Dictionary:
	if limb_index < 0 or limb_index >= limb_records.size():
		return {}
	return limb_records[limb_index]


func _joint_angular_speeds(record: Dictionary) -> Vector3:
	var parent := record.get("parent") as LimbSegment3D
	var child := record.get("child") as LimbSegment3D
	var joint_basis_parent: Basis = record.get("joint_basis_parent", Basis.IDENTITY)
	if not is_instance_valid(parent) or not is_instance_valid(child):
		return Vector3.ZERO
	var relative_parent := parent.global_basis.inverse() * (
		child.angular_velocity - parent.angular_velocity
	)
	return Vector3(
		relative_parent.dot(joint_basis_parent.x.normalized()),
		relative_parent.dot(joint_basis_parent.y.normalized()),
		relative_parent.dot(joint_basis_parent.z.normalized())
	)


func _ground_probe(origin: Vector3, maximum_distance: float) -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {"hit": false, "distance": maximum_distance, "normal": Vector3.UP}
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + Vector3.DOWN * maximum_distance,
		WORLD_COLLISION_MASK,
		cached_body_rids
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "distance": maximum_distance, "normal": Vector3.UP}
	var position: Vector3 = hit.get(
		"position",
		origin + Vector3.DOWN * maximum_distance
	)
	return {
		"hit": true,
		"distance": origin.distance_to(position),
		"position": position,
		"normal": hit.get("normal", Vector3.UP),
		"collider": hit.get("collider"),
	}


func _missing_limb_snapshot(limb_index: int, name_value: String) -> Dictionary:
	return {
		"slot_index": limb_index,
		"slot_name": name_value,
		"installed": false,
		"functional": false,
		"health_ratio": 0.0,
		"actuator_effectiveness": 0.0,
		"hip_offset_local": Vector3.ZERO,
		"upper_length": 0.0,
		"lower_length": 0.0,
		"joint_angles": Vector3.ZERO,
		"joint_limit_lower": Vector3.ZERO,
		"joint_limit_upper": Vector3.ZERO,
		"joint_target_angles": Vector3.ZERO,
		"joint_target_errors": Vector3.ZERO,
		"controller_target_errors": Vector3.ZERO,
		"rest_pose_errors": Vector3.ZERO,
		"joint_angular_velocities": Vector3.ZERO,
		"previous_commands": Vector3.ZERO,
		"commands": Vector3.ZERO,
		"applied_torque": Vector3.ZERO,
		"saturation": Vector3.ZERO,
		"foot_position_local": Vector3.ZERO,
		"foot_velocity_local": Vector3.ZERO,
		"foot_up_local": Vector3.UP,
		"foot_contact": false,
		"ground_normal_local": Vector3.UP,
		"foot_clearance": 0.0,
		"foot_slip_speed": 0.0,
		"distal_contact_count": 0,
		"support_contact_count": 0,
		"world_contact_count": 0,
		"wall_contact": false,
		"wall_contact_count": 0,
		"maximum_wall_contact_impulse": 0.0,
		"grip_present": false,
		"grip_command": 0.0,
		"grip_activation": 0.0,
		"grip_requires_rearm": false,
		"grip_candidate_present": false,
		"grip_candidate_distance": 0.0,
		"grip_target_present": false,
		"grip_target_offset_local": Vector3.ZERO,
		"grip_target_normal_local": Vector3.UP,
		"grip_target_distance": 0.0,
		"grip_candidate_dynamic": false,
		"grip_candidate_target_mass": 0.0,
		"grip_candidate_climbable": false,
		"grip_candidate_carryable": false,
		"grip_attached": false,
		"grip_attached_dynamic": false,
		"grip_attached_target_id": 0,
		"grip_attached_target_mass": 0.0,
		"grip_attached_surface_tags": PackedStringArray(),
		"grip_attached_climbable": false,
		"grip_attached_carryable": false,
		"grip_load_ratio": 0.0,
		"grip_pickup_sequence": 0,
		"end_effector": LimbEndEffector3D.empty_snapshot(),
	}


func _contact_is_load_bearing_foot_shape(
	body: LimbSegment3D,
	state: PhysicsDirectBodyState3D,
	contact_index: int
) -> bool:
	if not _is_distal_limb_segment(body) or state == null:
		return false
	var limb_index: int = body.limb_slot_index
	if limb_index < 0 or limb_index >= limb_records.size():
		return false
	var record: Dictionary = limb_records[limb_index]
	var chain: GenericLimb3D = record.get("chain") as GenericLimb3D
	if not is_instance_valid(chain):
		return false
	# Custom limbs without physical terminal geometry still use the distal capsule tip as their
	# load-bearing foot. Once a physical terminal exists, require the actual end-effector shape.
	if (
		not is_instance_valid(chain.end_effector)
		or chain.end_effector.disabled
		or chain.end_effector.definition == null
		or not chain.end_effector.definition.is_physically_present()
	):
		return true
	var local_shape_index: int = state.get_contact_local_shape(contact_index)
	if local_shape_index < 0:
		return false
	var owner_id: int = body.shape_find_owner(local_shape_index)
	if owner_id < 0:
		return false
	return body.shape_owner_get_owner(owner_id) == chain.end_effector


func _is_distal_limb_segment(body: LimbSegment3D) -> bool:
	if (
		not is_instance_valid(body)
		or body.limb_slot_index < 0
		or body.limb_slot_index >= limb_records.size()
	):
		return false
	var record: Dictionary = limb_records[body.limb_slot_index]
	var chain := record.get("chain") as GenericLimb3D
	return (
		is_instance_valid(chain)
		and not chain.segments.is_empty()
		and chain.segments[chain.segments.size() - 1] == body
	)


static func _dictionary_vector3(
	data: Dictionary,
	key: String,
	fallback: Vector3
) -> Vector3:
	var value: Variant = data.get(key, fallback)
	return value if value is Vector3 and (value as Vector3).is_finite() else fallback


func _contact_array_vector3(contact_snapshot: Dictionary, key: String, index: int) -> Vector3:
	var value: Variant = contact_snapshot.get(key, PackedVector3Array())
	if value is PackedVector3Array and index >= 0 and index < (value as PackedVector3Array).size():
		return (value as PackedVector3Array)[index]
	if value is Array and index >= 0 and index < (value as Array).size():
		var item: Variant = (value as Array)[index]
		return item if item is Vector3 else Vector3.ZERO
	return Vector3.ZERO


func _contact_array_integer(contact_snapshot: Dictionary, key: String, index: int) -> int:
	var value: Variant = contact_snapshot.get(key, PackedInt32Array())
	if value is PackedInt32Array and index >= 0 and index < (value as PackedInt32Array).size():
		return (value as PackedInt32Array)[index]
	if value is Array and index >= 0 and index < (value as Array).size():
		return int((value as Array)[index])
	return 0


func _contact_array_float(contact_snapshot: Dictionary, key: String, index: int) -> float:
	var value: Variant = contact_snapshot.get(key, PackedFloat64Array())
	if value is PackedFloat64Array and index >= 0 and index < (value as PackedFloat64Array).size():
		return (value as PackedFloat64Array)[index]
	if value is Array and index >= 0 and index < (value as Array).size():
		return float((value as Array)[index])
	return 0.0


func _training_wall_node(value: Variant) -> Node3D:
	var node := value as Node
	while node != null:
		if node is Node3D and node.has_meta("training_wall") and bool(node.get_meta("training_wall")):
			return node as Node3D
		node = node.get_parent()
	return null


static func _joint_has_locked_translation(joint: Generic6DOFJoint3D) -> bool:
	return (
		_joint_linear_axis_locked(joint, Vector3.AXIS_X)
		and _joint_linear_axis_locked(joint, Vector3.AXIS_Y)
		and _joint_linear_axis_locked(joint, Vector3.AXIS_Z)
	)


static func _joint_linear_axis_locked(joint: Generic6DOFJoint3D, axis: int) -> bool:
	var enabled := false
	var lower := 0.0
	var upper := 0.0
	match axis:
		Vector3.AXIS_X:
			enabled = joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)
			lower = joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
			upper = joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
		Vector3.AXIS_Y:
			enabled = joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)
			lower = joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
			upper = joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
		Vector3.AXIS_Z:
			enabled = joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)
			lower = joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
			upper = joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
	return enabled and absf(lower) <= 0.0001 and absf(upper) <= 0.0001


static func _joint_axis_matches(
	joint: Generic6DOFJoint3D,
	axis: int,
	lower_degrees: float,
	upper_degrees: float
) -> bool:
	var enabled := false
	var lower := 0.0
	var upper := 0.0
	match axis:
		Vector3.AXIS_X:
			enabled = joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)
			lower = joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
			upper = joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
		Vector3.AXIS_Y:
			enabled = joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)
			lower = joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
			upper = joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
		Vector3.AXIS_Z:
			enabled = joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)
			lower = joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
			upper = joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
	return (
		enabled
		and absf(lower - deg_to_rad(lower_degrees)) <= 0.001
		and absf(upper - deg_to_rad(upper_degrees)) <= 0.001
	)


static func _safe_packed_value(values: PackedFloat64Array, index: int) -> float:
	return values[index] if index >= 0 and index < values.size() else 0.0


static func _wrap_angle(value: float) -> float:
	return wrapf(value, -PI, PI)


static func _limb_color(index: int, lower: bool) -> Color:
	var colors := [
		Color(0.92, 0.45, 0.24, 1.0),
		Color(0.26, 0.67, 0.91, 1.0),
		Color(0.63, 0.83, 0.31, 1.0),
		Color(0.76, 0.43, 0.88, 1.0),
	]
	var color: Color = colors[index % colors.size()]
	return color.darkened(0.18) if lower else color
