class_name EnemyGaitPlanner
extends RefCounted

const EPSILON := 0.000001
const STOP_SPEED := 0.05
const VELOCITY_SMOOTHING := 12.0
const REACH_MARGIN := 0.01
const REACH_EMERGENCY_RATIO := 0.90
const MIN_HORIZONTAL_REACH_RATIO := 0.50
const MIN_OUTWARD_PROJECTION_RATIO := 0.30
const SCHEDULED_GROUP_TRIGGER_RATIO := 0.75
const MIN_GROUND_NORMAL_DOT := 0.20
const MIN_STEP_DURATION := 0.001
const STEP_ARC_SCALE := 16.0
const EMERGENCY_ERROR_MULTIPLIER := 2.0

#######################################################
# Plans world-space foot placement and two-segment limb poses for arbitrary physical enemy
# anatomies and ordered gait groups.
#######################################################

var anatomy: EnemyPhysicalAnatomyDefinition
var limb_states: Array[Dictionary] = []
var active_gait_group := -1
var next_gait_group := -1
var support_transfer_remaining := 0.0

# Keep this configurable because not every project uses physics layer 1 for terrain.
var ground_collision_mask: int = 1

var gait_group_ids: Array[int] = []
var smoothed_horizontal_velocity := Vector3.ZERO
var previous_body_origin := Vector3.ZERO
var has_previous_body_origin := false


func configure(
	new_anatomy: EnemyPhysicalAnatomyDefinition,
	body_transform: Transform3D,
	space_state: PhysicsDirectSpaceState3D = null,
	exclude: Array[RID] = []
) -> void:
	anatomy = new_anatomy
	reset(body_transform, space_state, exclude)


func reset(
	body_transform: Transform3D,
	space_state: PhysicsDirectSpaceState3D = null,
	exclude: Array[RID] = []
) -> void:
	limb_states.clear()
	active_gait_group = -1
	next_gait_group = -1
	support_transfer_remaining = 0.0
	smoothed_horizontal_velocity = Vector3.ZERO
	previous_body_origin = body_transform.origin
	has_previous_body_origin = true
	_rebuild_gait_group_ids()

	if anatomy == null:
		return

	for limb: EnemyPhysicalLimbDefinition in anatomy.limbs:
		if limb == null:
			limb_states.append({})
			continue

		var desired: Vector3 = body_transform * limb.rest_foot_offset
		var ground_result := _sample_ground_result(
			desired,
			space_state,
			exclude
		)
		var foot := desired
		var grounded := false
		var ground_normal := Vector3.UP
		if bool(ground_result.get("hit", false)):
			foot = _clamp_target_to_reach(
				limb,
				body_transform,
				ground_result.get("position", desired)
			)
			grounded = true
			ground_normal = ground_result.get("normal", Vector3.UP)

		limb_states.append({
			"foot": foot,
			"step_start": foot,
			"step_target": foot,
			"step_progress": 1.0,
			"step_arc_offset": Vector3.ZERO,
			"step_target_grounded": grounded,
			"ground_normal": ground_normal,
			"stepping": false,
			"grounded": grounded,
			"knee_direction_local": _get_local_bend_fallback(limb),
		})


func update(
	delta: float,
	body_transform: Transform3D,
	body_velocity: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	exclude: Array[RID] = []
) -> void:
	if anatomy == null:
		return

	if limb_states.size() != anatomy.limbs.size():
		reset(body_transform, space_state, exclude)
		return

	if _body_was_teleported(body_transform.origin):
		reset(body_transform, space_state, exclude)
		return
	previous_body_origin = body_transform.origin
	has_previous_body_origin = true

	var safe_delta := maxf(delta, 0.0)
	var is_moving := _update_smoothed_velocity(safe_delta, body_velocity)
	var active_group_still_stepping := _advance_active_steps(safe_delta)
	var completed_group := _finish_completed_group(
		active_group_still_stepping,
		is_moving
	)
	if active_gait_group >= 0 or completed_group >= 0:
		# A completed support set remains planted for at least one full tick.
		return

	if not is_moving:
		# Preserve the planted stance instead of snapping to authored rest offsets.
		next_gait_group = -1
		support_transfer_remaining = 0.0

	if _is_support_transfer_active(safe_delta):
		return

	var trigger_distance := maxf(anatomy.step_trigger_distance, 0.001)
	var candidates := _build_step_candidates(
		body_transform,
		space_state,
		exclude,
		trigger_distance
	)
	var selected_group := _select_step_group(
		candidates,
		is_moving,
		trigger_distance
	)
	if selected_group < 0:
		return
	_start_group_steps(selected_group, candidates, body_transform)


func _update_smoothed_velocity(delta: float, body_velocity: Vector3) -> bool:
	var horizontal_velocity := Vector3(body_velocity.x, 0.0, body_velocity.z)
	var velocity_blend := 1.0 - exp(-delta * VELOCITY_SMOOTHING)
	smoothed_horizontal_velocity = smoothed_horizontal_velocity.lerp(
		horizontal_velocity,
		velocity_blend
	)
	if (
		horizontal_velocity.length() < STOP_SPEED
		and smoothed_horizontal_velocity.length() < STOP_SPEED
	):
		smoothed_horizontal_velocity = Vector3.ZERO
	return horizontal_velocity.length() >= STOP_SPEED


func _advance_active_steps(delta: float) -> bool:
	var active_group_still_stepping := false
	for index: int in range(limb_states.size()):
		var state: Dictionary = limb_states[index]
		if state.is_empty() or not bool(state.get("stepping", false)):
			continue

		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[index]
		if (
			limb == null
			or not state.has("step_start")
			or not state.has("step_target")
		):
			state["stepping"] = false
			state["grounded"] = false
			continue

		var progress := minf(
			float(state.get("step_progress", 0.0))
			+ delta / maxf(anatomy.step_duration, MIN_STEP_DURATION),
			1.0
		)
		_apply_step_pose(state, progress)
		if progress < 1.0 and limb.gait_group == active_gait_group:
			active_group_still_stepping = true
	return active_group_still_stepping


func _apply_step_pose(state: Dictionary, progress: float) -> void:
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var one_minus_progress := 1.0 - progress
	# This quartic bump has zero lift velocity at takeoff and landing.
	var arc_amount := (
		STEP_ARC_SCALE
		* progress * progress
		* one_minus_progress * one_minus_progress
	)
	var start: Vector3 = state["step_start"]
	var target: Vector3 = state["step_target"]
	var step_arc_offset: Vector3 = state.get(
		"step_arc_offset",
		Vector3.ZERO
	)
	var foot: Vector3 = start.lerp(target, eased)
	foot += step_arc_offset * arc_amount
	foot.y += maxf(anatomy.step_height, 0.0) * arc_amount

	state["foot"] = target if progress >= 1.0 else foot
	state["step_progress"] = progress
	state["stepping"] = progress < 1.0
	state["grounded"] = (
		bool(state.get("step_target_grounded", false))
		if progress >= 1.0
		else false
	)


func _finish_completed_group(
	active_group_still_stepping: bool,
	is_moving: bool
) -> int:
	if active_gait_group < 0 or active_group_still_stepping:
		return -1

	var completed_group := active_gait_group
	active_gait_group = -1
	if is_moving:
		next_gait_group = _get_following_gait_group(completed_group)
		support_transfer_remaining = maxf(
			anatomy.support_transfer_duration,
			0.0
		)
	else:
		next_gait_group = -1
		support_transfer_remaining = 0.0
	return completed_group


func _is_support_transfer_active(delta: float) -> bool:
	if support_transfer_remaining <= 0.0:
		return false
	support_transfer_remaining = maxf(
		support_transfer_remaining - delta,
		0.0
	)
	return support_transfer_remaining > 0.0


func _build_step_candidates(
	body_transform: Transform3D,
	space_state: PhysicsDirectSpaceState3D,
	exclude: Array[RID],
	trigger_distance: float
) -> Dictionary:
	var desired_feet: Array[Vector3] = []
	var desired_valid: Array[bool] = []
	var desired_grounded: Array[bool] = []
	var candidates := {
		"desired_feet": desired_feet,
		"desired_valid": desired_valid,
		"desired_grounded": desired_grounded,
		"error_by_group": {},
		"group_has_valid_target": {},
		"best_group": -1,
		"best_error": 0.0,
		"emergency_group": -1,
		"emergency_score": 0.0,
	}
	for index: int in range(anatomy.limbs.size()):
		_append_limb_candidate(
			candidates,
			index,
			body_transform,
			space_state,
			exclude,
			trigger_distance
		)
	return candidates


func _append_limb_candidate(
	candidates: Dictionary,
	index: int,
	body_transform: Transform3D,
	space_state: PhysicsDirectSpaceState3D,
	exclude: Array[RID],
	trigger_distance: float
) -> void:
	var desired_feet: Array[Vector3] = candidates["desired_feet"]
	var desired_valid: Array[bool] = candidates["desired_valid"]
	var desired_grounded: Array[bool] = candidates["desired_grounded"]
	var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[index]
	var state: Dictionary = limb_states[index]
	if limb == null or state.is_empty() or not state.has("foot"):
		desired_feet.append(Vector3.ZERO)
		desired_valid.append(false)
		desired_grounded.append(false)
		return

	var current: Vector3 = state["foot"]
	var raw_desired: Vector3 = (
		body_transform * limb.rest_foot_offset
		+ smoothed_horizontal_velocity * anatomy.velocity_look_ahead
	)
	var target_result := _calculate_limb_target(
		limb,
		body_transform,
		raw_desired,
		space_state,
		exclude
	)
	if not bool(target_result.get("valid", false)):
		desired_feet.append(current)
		desired_valid.append(false)
		desired_grounded.append(false)
		return

	var desired: Vector3 = target_result.get("position", current)
	desired_feet.append(desired)
	desired_valid.append(true)
	desired_grounded.append(bool(target_result.get("grounded", false)))
	_record_group_error(
		candidates,
		limb,
		state,
		body_transform,
		current,
		desired,
		trigger_distance
	)


func _record_group_error(
	candidates: Dictionary,
	limb: EnemyPhysicalLimbDefinition,
	state: Dictionary,
	body_transform: Transform3D,
	current: Vector3,
	desired: Vector3,
	trigger_distance: float
) -> void:
	var horizontal_error := Vector2(
		desired.x - current.x,
		desired.z - current.z
	).length()
	var error := maxf(horizontal_error, absf(desired.y - current.y))
	var group_id = limb.gait_group
	var error_by_group: Dictionary = candidates["error_by_group"]
	var group_has_valid_target: Dictionary = candidates["group_has_valid_target"]
	error_by_group[group_id] = maxf(
		float(error_by_group.get(group_id, 0.0)),
		error
	)
	group_has_valid_target[group_id] = true

	if error > float(candidates["best_error"]):
		candidates["best_error"] = error
		candidates["best_group"] = group_id

	if _is_limb_unsafe(
		limb,
		state,
		body_transform,
		desired,
		trigger_distance
	):
		var score := maxf(
			error,
			trigger_distance * EMERGENCY_ERROR_MULTIPLIER
		)
		if score > float(candidates["emergency_score"]):
			candidates["emergency_score"] = score
			candidates["emergency_group"] = group_id


func _select_step_group(
	candidates: Dictionary,
	is_moving: bool,
	trigger_distance: float
) -> int:
	var emergency_group := int(candidates["emergency_group"])
	if emergency_group >= 0:
		return emergency_group
	if not is_moving:
		return -1

	var group_has_valid_target: Dictionary = candidates["group_has_valid_target"]
	var error_by_group: Dictionary = candidates["error_by_group"]
	var scheduled_error := float(error_by_group.get(next_gait_group, 0.0))
	if (
		next_gait_group >= 0
		and bool(group_has_valid_target.get(next_gait_group, false))
		and scheduled_error >= (
			trigger_distance * SCHEDULED_GROUP_TRIGGER_RATIO
		)
	):
		return next_gait_group

	# Prefer the schedule, but release an overstretched support set to avoid deadlock.
	var best_group := int(candidates["best_group"])
	if best_group >= 0 and float(candidates["best_error"]) >= trigger_distance:
		return best_group
	return -1


func _start_group_steps(
	selected_group: int,
	candidates: Dictionary,
	body_transform: Transform3D
) -> void:
	var desired_feet: Array[Vector3] = candidates["desired_feet"]
	var desired_valid: Array[bool] = candidates["desired_valid"]
	var desired_grounded: Array[bool] = candidates["desired_grounded"]
	var started_any_step := false
	for index: int in range(anatomy.limbs.size()):
		var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[index]
		if (
			limb == null
			or limb.gait_group != selected_group
			or limb_states[index].is_empty()
			or not desired_valid[index]
		):
			continue

		var state: Dictionary = limb_states[index]
		var current_foot: Vector3 = state["foot"]
		state["step_start"] = current_foot
		state["step_target"] = desired_feet[index]
		state["step_target_grounded"] = desired_grounded[index]
		state["step_arc_offset"] = (
			_get_outward_swing_direction(
				limb,
				body_transform,
				current_foot
			)
			* maxf(anatomy.swing_retraction_distance, 0.0)
		)
		state["step_progress"] = 0.0
		state["stepping"] = true
		state["grounded"] = false
		started_any_step = true

	active_gait_group = selected_group if started_any_step else -1
	if not started_any_step:
		next_gait_group = -1


func get_desired_limb_points(
	limb_index: int,
	body_transform: Transform3D
) -> PackedVector3Array:
	if (
		anatomy == null
		or limb_index < 0
		or limb_index >= anatomy.limbs.size()
		or limb_index >= limb_states.size()
	):
		return PackedVector3Array()

	var limb: EnemyPhysicalLimbDefinition = anatomy.limbs[limb_index]
	var state: Dictionary = limb_states[limb_index]
	if limb == null or state.is_empty() or not state.has("foot"):
		return PackedVector3Array()

	var hip: Vector3 = body_transform * limb.hip_offset
	var foot: Vector3 = state["foot"]
	var world_bend_hint: Vector3 = body_transform.basis * limb.bend_hint
	var previous_local_bend: Vector3 = state.get(
		"knee_direction_local",
		_get_local_bend_fallback(limb)
	)
	var previous_world_bend := body_transform.basis * previous_local_bend
	var fallback_direction = body_transform.basis * (
		limb.rest_foot_offset - limb.hip_offset
	)
	var solution := _solve_two_bone_internal(
		hip,
		foot,
		limb.upper_length,
		limb.lower_length,
		world_bend_hint,
		previous_world_bend,
		fallback_direction
	)
	var world_knee_direction: Vector3 = solution.get(
		"bend_direction",
		world_bend_hint.normalized()
	)
	var local_knee_direction := (
		body_transform.basis.inverse() * world_knee_direction
	)
	if local_knee_direction.length_squared() > EPSILON:
		state["knee_direction_local"] = local_knee_direction.normalized()
	return solution.get("points", PackedVector3Array())


func is_limb_stepping(limb_index: int) -> bool:
	return (
		limb_index >= 0
		and limb_index < limb_states.size()
		and bool(limb_states[limb_index].get("stepping", false))
	)


func get_active_gait_group() -> int:
	return active_gait_group


func is_in_support_transfer() -> bool:
	return active_gait_group < 0 and support_transfer_remaining > 0.0


static func solve_two_bone(
	hip: Vector3,
	requested_foot: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3
) -> PackedVector3Array:
	var solution := _solve_two_bone_internal(
		hip,
		requested_foot,
		upper_length,
		lower_length,
		bend_hint,
		Vector3.ZERO,
		requested_foot - hip
	)
	return solution.get("points", PackedVector3Array())


static func _solve_two_bone_internal(
	hip: Vector3,
	requested_foot: Vector3,
	upper_length: float,
	lower_length: float,
	bend_hint: Vector3,
	previous_bend: Vector3,
	fallback_direction: Vector3
) -> Dictionary:
	var upper := maxf(upper_length, 0.001)
	var lower := maxf(lower_length, 0.001)
	var offset := requested_foot - hip
	var raw_distance := offset.length()
	var direction := offset.normalized() if raw_distance > 0.0001 else Vector3.ZERO
	if direction.length_squared() <= EPSILON:
		direction = fallback_direction.normalized()
	if direction.length_squared() <= EPSILON:
		direction = Vector3.DOWN

	var maximum_reach := maxf(upper + lower - REACH_MARGIN, 0.001)
	var minimum_reach := minf(
		absf(upper - lower) + REACH_MARGIN,
		maximum_reach
	)
	var distance := clampf(raw_distance, minimum_reach, maximum_reach)
	var foot := hip + direction * distance
	var along := (
		upper * upper - lower * lower + distance * distance
	) / maxf(2.0 * distance, 0.001)
	var perpendicular_height := sqrt(
		maxf(upper * upper - along * along, 0.0)
	)

	var authored_perpendicular := _project_perpendicular(
		bend_hint,
		direction
	)
	var previous_perpendicular := _project_perpendicular(
		previous_bend,
		direction
	)
	var perpendicular := Vector3.ZERO

	if previous_perpendicular.length_squared() > EPSILON:
		previous_perpendicular = previous_perpendicular.normalized()
		if authored_perpendicular.length_squared() > EPSILON:
			authored_perpendicular = authored_perpendicular.normalized()
			if authored_perpendicular.dot(previous_perpendicular) < 0.0:
				authored_perpendicular = -authored_perpendicular
			perpendicular = (
				previous_perpendicular * 0.85
				+ authored_perpendicular * 0.15
			).normalized()
		else:
			perpendicular = previous_perpendicular
	elif authored_perpendicular.length_squared() > EPSILON:
		perpendicular = authored_perpendicular.normalized()
	else:
		perpendicular = _project_perpendicular(
			fallback_direction,
			direction
		)
		if perpendicular.length_squared() <= EPSILON:
			perpendicular = _get_least_parallel_axis(direction)
		perpendicular = _project_perpendicular(
			perpendicular,
			direction
		).normalized()

	var knee := (
		hip
		+ direction * along
		+ perpendicular * perpendicular_height
	)
	return {
		"points": PackedVector3Array([hip, knee, foot]),
		"bend_direction": perpendicular,
	}


func _calculate_limb_target(
	limb: EnemyPhysicalLimbDefinition,
	body_transform: Transform3D,
	raw_desired: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	exclude: Array[RID]
) -> Dictionary:
	var constrained := _constrain_target_to_leg_workspace(
		limb,
		body_transform,
		raw_desired
	)
	var ground_result := _sample_ground_result(
		constrained,
		space_state,
		exclude
	)
	if not bool(ground_result.get("hit", false)):
		return {
			"valid": false,
			"position": constrained,
			"grounded": false,
		}

	var ground_position: Vector3 = ground_result.get(
		"position",
		constrained
	)
	var reachable := _clamp_target_to_reach(
		limb,
		body_transform,
		ground_position
	)

	# Reach clamping can move X/Z slightly. Re-probe there so the authoritative
	# planner position remains both reachable and attached to the terrain.
	if Vector2(
		reachable.x - ground_position.x,
		reachable.z - ground_position.z
	).length_squared() > 0.000001:
		var reprobe_source := Vector3(
			reachable.x,
			constrained.y,
			reachable.z
		)
		var reprobe := _sample_ground_result(
			reprobe_source,
			space_state,
			exclude
		)
		if bool(reprobe.get("hit", false)):
			ground_position = reprobe.get("position", reachable)
			reachable = _clamp_target_to_reach(
				limb,
				body_transform,
				ground_position
			)

	return {
		"valid": true,
		"position": reachable,
		"grounded": true,
		"normal": ground_result.get("normal", Vector3.UP),
	}


func _constrain_target_to_leg_workspace(
	limb: EnemyPhysicalLimbDefinition,
	body_transform: Transform3D,
	requested: Vector3
) -> Vector3:
	var local_target: Vector3 = body_transform.affine_inverse() * requested
	var rest_relative = limb.rest_foot_offset - limb.hip_offset
	var requested_relative = local_target - limb.hip_offset
	var rest_horizontal := Vector2(rest_relative.x, rest_relative.z)
	var requested_horizontal := Vector2(
		requested_relative.x,
		requested_relative.z
	)
	var rest_radius := rest_horizontal.length()
	if rest_radius <= 0.0001:
		return requested

	var outward := rest_horizontal / rest_radius
	var outward_amount := requested_horizontal.dot(outward)
	var tangential := requested_horizontal - outward * outward_amount
	outward_amount = maxf(
		outward_amount,
		rest_radius * MIN_OUTWARD_PROJECTION_RATIO
	)
	requested_horizontal = outward * outward_amount + tangential

	var minimum_radius := rest_radius * MIN_HORIZONTAL_REACH_RATIO
	if requested_horizontal.length() < minimum_radius:
		if requested_horizontal.length_squared() > EPSILON:
			requested_horizontal = (
				requested_horizontal.normalized() * minimum_radius
			)
		else:
			requested_horizontal = outward * minimum_radius

	local_target.x = limb.hip_offset.x + requested_horizontal.x
	local_target.z = limb.hip_offset.z + requested_horizontal.y
	return body_transform * local_target


func _clamp_target_to_reach(
	limb: EnemyPhysicalLimbDefinition,
	body_transform: Transform3D,
	requested: Vector3
) -> Vector3:
	var upper := maxf(limb.upper_length, 0.001)
	var lower := maxf(limb.lower_length, 0.001)
	var hip: Vector3 = body_transform * limb.hip_offset
	var offset := requested - hip
	var raw_distance := offset.length()
	var direction := offset.normalized() if raw_distance > 0.0001 else Vector3.ZERO
	if direction.length_squared() <= EPSILON:
		direction = body_transform.basis * (
			limb.rest_foot_offset - limb.hip_offset
		)
		direction = direction.normalized()
	if direction.length_squared() <= EPSILON:
		direction = Vector3.DOWN

	var maximum_reach := maxf(upper + lower - REACH_MARGIN, 0.001)
	var minimum_reach := minf(
		absf(upper - lower) + REACH_MARGIN,
		maximum_reach
	)
	var distance := clampf(raw_distance, minimum_reach, maximum_reach)
	return hip + direction * distance


func _is_limb_unsafe(
	limb: EnemyPhysicalLimbDefinition,
	state: Dictionary,
	body_transform: Transform3D,
	desired: Vector3,
	trigger_distance: float
) -> bool:
	if not bool(state.get("grounded", false)):
		return true

	var current: Vector3 = state["foot"]
	var hip: Vector3 = body_transform * limb.hip_offset
	var maximum_reach := maxf(
		maxf(limb.upper_length, 0.001)
		+ maxf(limb.lower_length, 0.001)
		- REACH_MARGIN,
		0.001
	)
	if hip.distance_to(current) >= maximum_reach * REACH_EMERGENCY_RATIO:
		return true

	var inverse_transform := body_transform.affine_inverse()
	var current_local: Vector3 = inverse_transform * current
	var current_relative = current_local - limb.hip_offset
	var rest_relative = limb.rest_foot_offset - limb.hip_offset
	var current_horizontal := Vector2(
		current_relative.x,
		current_relative.z
	)
	var rest_horizontal := Vector2(
		rest_relative.x,
		rest_relative.z
	)
	var rest_radius := rest_horizontal.length()
	if rest_radius > 0.0001:
		var outward := rest_horizontal / rest_radius
		if (
			current_horizontal.length()
			< rest_radius * MIN_HORIZONTAL_REACH_RATIO
		):
			return true
		if (
			current_horizontal.dot(outward)
			< rest_radius * MIN_OUTWARD_PROJECTION_RATIO
		):
			return true

	if absf(desired.y - current.y) >= maxf(trigger_distance, 0.05):
		return true
	return false


func _get_outward_swing_direction(
	limb: EnemyPhysicalLimbDefinition,
	body_transform: Transform3D,
	current_foot: Vector3
) -> Vector3:
	var local_outward = limb.rest_foot_offset - limb.hip_offset
	local_outward.y = 0.0
	var world_outward = body_transform.basis * local_outward
	world_outward.y = 0.0
	if world_outward.length_squared() <= EPSILON:
		var hip: Vector3 = body_transform * limb.hip_offset
		world_outward = current_foot - hip
		world_outward.y = 0.0
	return (
		world_outward.normalized()
		if world_outward.length_squared() > EPSILON
		else Vector3.ZERO
	)


func _rebuild_gait_group_ids() -> void:
	gait_group_ids.clear()
	if anatomy == null:
		return
	for limb: EnemyPhysicalLimbDefinition in anatomy.limbs:
		if limb == null or limb.gait_group < 0:
			continue
		if not gait_group_ids.has(limb.gait_group):
			gait_group_ids.append(limb.gait_group)
	gait_group_ids.sort()


func _get_following_gait_group(group_id: int) -> int:
	if gait_group_ids.is_empty():
		return -1
	var index := gait_group_ids.find(group_id)
	if index < 0:
		return gait_group_ids[0]
	return gait_group_ids[(index + 1) % gait_group_ids.size()]


func _body_was_teleported(current_origin: Vector3) -> bool:
	if not has_previous_body_origin or anatomy == null:
		return false
	var maximum_reach := 0.0
	for limb: EnemyPhysicalLimbDefinition in anatomy.limbs:
		if limb == null:
			continue
		maximum_reach = maxf(
			maximum_reach,
			maxf(limb.upper_length, 0.001)
			+ maxf(limb.lower_length, 0.001)
		)
	var teleport_distance := maxf(
		maximum_reach * 1.5,
		maxf(anatomy.step_trigger_distance, 0.001) * 4.0
	)
	return previous_body_origin.distance_to(current_origin) > teleport_distance


func _get_local_bend_fallback(
	limb: EnemyPhysicalLimbDefinition
) -> Vector3:
	var bend = limb.bend_hint
	if bend.length_squared() <= EPSILON:
		bend = limb.rest_foot_offset - limb.hip_offset
	if bend.length_squared() <= EPSILON:
		bend = Vector3.UP
	return bend.normalized()


func _sample_ground_result(
	desired: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	exclude: Array[RID]
) -> Dictionary:
	if space_state == null or anatomy == null:
		return {
			"hit": false,
			"position": desired,
			"normal": Vector3.UP,
		}

	var origin: Vector3 = desired + Vector3.UP * maxf(
		anatomy.probe_height,
		0.0
	)
	var end: Vector3 = desired - Vector3.UP * maxf(
		anatomy.probe_depth,
		0.0
	)
	if origin.is_equal_approx(end):
		return {
			"hit": false,
			"position": desired,
			"normal": Vector3.UP,
		}

	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = exclude
	query.collision_mask = ground_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return {
			"hit": false,
			"position": desired,
			"normal": Vector3.UP,
		}

	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if normal.length_squared() <= EPSILON:
		return {
			"hit": false,
			"position": desired,
			"normal": Vector3.UP,
		}
	normal = normal.normalized()
	if normal.dot(Vector3.UP) < MIN_GROUND_NORMAL_DOT:
		return {
			"hit": false,
			"position": desired,
			"normal": normal,
		}

	return {
		"hit": true,
		"position": hit.get("position", desired),
		"normal": normal,
	}


static func _project_perpendicular(
	vector: Vector3,
	direction: Vector3
) -> Vector3:
	return vector - direction * vector.dot(direction)


static func _get_least_parallel_axis(direction: Vector3) -> Vector3:
	var x_alignment := absf(direction.dot(Vector3.RIGHT))
	var y_alignment := absf(direction.dot(Vector3.UP))
	var z_alignment := absf(direction.dot(Vector3.FORWARD))
	if x_alignment <= y_alignment and x_alignment <= z_alignment:
		return Vector3.RIGHT
	if y_alignment <= z_alignment:
		return Vector3.UP
	return Vector3.FORWARD
