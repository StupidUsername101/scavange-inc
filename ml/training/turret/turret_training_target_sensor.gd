class_name TurretTrainingTargetSensor
extends RefCounted

const AUTOMATIC_TARGET_KINDS: Array[StringName] = [&"drone", &"four_limb"]
const EXPLICIT_TARGET_KINDS: Array[StringName] = [&"drone", &"four_limb", &"turret"]
const MINIMUM_DIRECTION_LENGTH_SQUARED = 0.000001


static func acquire(
	turret: TurretPhysicalBody3D,
	self_adapter: TurretTrainingCombatantAdapter,
	entity_spatial_hash: ServerSpatialHash3D,
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	fallback_target_position: Vector3,
	maximum_range_m: float,
	preferred_group_id: int = -1,
	preferred_entity_id: int = -1,
	fallback_target: Dictionary = {}
) -> Dictionary:
	if not is_instance_valid(turret):
		return empty_probe(fallback_target_position)
	var origin: Vector3 = turret.muzzle_position_world()
	var fallback_position_value: Variant = fallback_target.get(
		"position_world", fallback_target_position
	)
	var safe_fallback_target_position: Vector3 = fallback_target_position
	if fallback_position_value is Vector3 and (fallback_position_value as Vector3).is_finite():
		safe_fallback_target_position = fallback_position_value as Vector3
	elif not safe_fallback_target_position.is_finite():
		safe_fallback_target_position = origin + turret.aim_direction_world() * 10.0
	var fallback_velocity_value: Variant = fallback_target.get("velocity_world", Vector3.ZERO)
	var safe_fallback_velocity: Vector3 = Vector3.ZERO
	if fallback_velocity_value is Vector3 and (fallback_velocity_value as Vector3).is_finite():
		safe_fallback_velocity = fallback_velocity_value as Vector3
	var safe_fallback_radius: float = maxf(
		RLTrainingMath.finite_float_or(fallback_target.get("radius_m", 0.75), 0.75),
		0.01
	)
	# A routed navigation/task objective is a real aiming objective even when it is not a
	# damageable combatant in the entity hash. Historically that objective supplied direction
	# features while `present` stayed false, which made the dense aim reward exactly zero.
	# Only a non-empty resolved target dictionary opts into this generic-objective behavior;
	# direct sensor callers that pass no fallback dictionary retain the old "no target" meaning.
	var fallback_objective_present: bool = (
		not fallback_target.is_empty()
		and bool(fallback_target.get("available", true))
		and safe_fallback_target_position.is_finite()
	)
	# Path/manual targets are the turret forge's synthetic range targets. They have no combat
	# body in the shared entity hash, but shots must still be able to hit the visible target
	# marker. A target system can explicitly opt out with `shootable = false` if a future
	# objective is meant to be aim-only.
	var fallback_objective_shootable: bool = (
		fallback_objective_present
		and bool(fallback_target.get("shootable", false))
	)
	var fallback_matches_explicit_group: bool = false
	if preferred_group_id >= 0 and fallback_objective_present:
		var fallback_metadata_value: Variant = fallback_target.get("metadata", {})
		if fallback_metadata_value is Dictionary:
			var fallback_metadata: Dictionary = fallback_metadata_value as Dictionary
			fallback_matches_explicit_group = (
				RLTrainingMath.finite_int_or(
					fallback_metadata.get("target_worker_group_id", -1),
					-1
				) == preferred_group_id
			)
	# The room target handler is authoritative whenever it supplied a routed objective. In
	# particular, "Path training target" must not silently turn into the nearest ambient drone.
	# Automatic combat acquisition remains available to evaluator/direct callers that provide no
	# routed objective. An explicit worker-group selection may only use routed fallback metadata
	# that belongs to that selected group; a navigation path is not a substitute for a missing
	# or paused combat target.
	var allow_fallback_objective: bool = (
		fallback_objective_present
		and (preferred_group_id < 0 or fallback_matches_explicit_group)
	)
	var routed_objective_is_authoritative: bool = (
		allow_fallback_objective and preferred_group_id < 0
	)
	var safe_maximum_range_m: float = maxf(
		RLTrainingMath.finite_float_or(maximum_range_m, 0.0),
		0.0
	)
	var target_kinds: Array[StringName] = (
		EXPLICIT_TARGET_KINDS if preferred_group_id >= 0 else AUTOMATIC_TARGET_KINDS
	)
	var preferred_adapter: TrainingCombatantAdapter = null
	var preferred_line_of_sight: bool = false
	var nearest_visible_adapter: TrainingCombatantAdapter = null
	var nearest_visible_distance: float = INF
	var nearest_adapter: TrainingCombatantAdapter = null
	var nearest_distance: float = INF
	if entity_spatial_hash != null and not routed_objective_is_authoritative:
		for target_kind: StringName in target_kinds:
			for entity_key: StringName in entity_spatial_hash.readonly_keys_for_kind(target_kind):
				var record: Dictionary = entity_spatial_hash.get_record(entity_key)
				var metadata_value: Variant = record.get("metadata", {})
				if not (metadata_value is Dictionary):
					continue
				var metadata: Dictionary = metadata_value as Dictionary
				var candidate: TrainingCombatantAdapter = metadata.get("adapter") as TrainingCombatantAdapter
				if candidate == null or not candidate.is_alive():
					continue
				if preferred_group_id >= 0:
					if candidate.group_id != preferred_group_id:
						continue
				elif self_adapter != null and candidate.team_id == self_adapter.team_id:
					continue
				var candidate_position: Vector3 = candidate.aim_point_world()
				if not candidate_position.is_finite():
					continue
				var distance: float = origin.distance_to(candidate_position)
				if not is_finite(distance):
					continue
				var candidate_radius: float = maxf(
					RLTrainingMath.finite_float_or(candidate.collision_radius_m(), 0.35),
					0.01
				)
				# Explicit worker-group targeting is an objective contract, not a weapon-reach
				# query. Keep the selected live body observable even while it is temporarily
				# outside range/pitch so the policy keeps tracking it instead of falling back
				# to an unrelated path target and spinning. Automatic acquisition remains
				# restricted to bodies the weapon can currently reach.
				if preferred_group_id < 0:
					if distance > safe_maximum_range_m:
						continue
					if not target_within_pitch_limits(turret, candidate_position, candidate_radius):
						continue
				var line_of_sight: bool = not _wall_blocks(
					wall_spatial_hash,
					origin,
					candidate_position,
					candidate_radius
				)
				if preferred_entity_id >= 0 and candidate.entity_id == preferred_entity_id:
					preferred_adapter = candidate
					preferred_line_of_sight = line_of_sight
				if line_of_sight and distance < nearest_visible_distance:
					nearest_visible_distance = distance
					nearest_visible_adapter = candidate
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_adapter = candidate

	# A worker-group target handler may have already chosen the exact member represented by the
	# room target marker. Honor that decision rather than making a second nearest-body choice here;
	# otherwise the visual target and the gun can disagree and rapidly switch around equal distances.
	var best_adapter: TrainingCombatantAdapter = preferred_adapter
	var best_line_of_sight: bool = preferred_line_of_sight
	if best_adapter == null:
		best_adapter = nearest_visible_adapter if nearest_visible_adapter != null else nearest_adapter
		if best_adapter != null:
			best_line_of_sight = nearest_visible_adapter != null

	var combat_target_present: bool = best_adapter != null
	var target_present: bool = combat_target_present or allow_fallback_objective
	var target_shootable: bool = (
		combat_target_present
		or (allow_fallback_objective and fallback_objective_shootable)
	)
	var target_position: Vector3 = (
		best_adapter.aim_point_world()
		if combat_target_present
		else safe_fallback_target_position
	)
	var target_velocity: Vector3 = (
		best_adapter.linear_velocity_world()
		if combat_target_present
		else safe_fallback_velocity
	)
	if not target_velocity.is_finite():
		target_velocity = Vector3.ZERO
	var target_radius: float = (
		maxf(
			RLTrainingMath.finite_float_or(best_adapter.collision_radius_m(), 0.35),
			0.01
		)
		if combat_target_present
		else safe_fallback_radius
	)
	var offset: Vector3 = target_position - origin
	var distance: float = offset.length()
	var direct_direction: Vector3 = (
		offset / distance
		if distance > 0.000001
		else turret.aim_direction_world()
	)
	var intercept_point: Vector3 = BallisticAim.calculate_intercept_point(
		origin,
		target_position,
		target_velocity,
		Vector3.ZERO,
		turret.loadout.gun.projectile_speed_mps,
		3.0
	)
	var intercept_offset: Vector3 = intercept_point - origin
	var intercept_direction: Vector3 = (
		intercept_offset.normalized()
		if intercept_offset.length_squared() > MINIMUM_DIRECTION_LENGTH_SQUARED
		else direct_direction
	)
	var line_of_sight: bool = (
		best_line_of_sight
		if combat_target_present
		else (
			not _wall_blocks(
				wall_spatial_hash,
				origin,
				target_position,
				target_radius
			)
			if target_present
			else false
		)
	)
	var within_range: bool = target_present and distance <= safe_maximum_range_m
	var within_pitch_arc: bool = (
		target_present
		and target_within_pitch_limits(turret, target_position, target_radius)
	)
	var target_stable_id: String = (
		"entity:%s:%d" % [String(best_adapter.entity_kind), best_adapter.entity_id]
		if combat_target_present
		else str(fallback_target.get("stable_id", "routed-objective"))
	)
	if target_present and target_stable_id.is_empty():
		target_stable_id = "routed-objective"
	var target_kind: String = (
		String(best_adapter.entity_kind)
		if combat_target_present
		else str(fallback_target.get("target_kind", "navigation"))
	)
	if target_kind.is_empty():
		target_kind = "navigation" if target_present else "fallback"
	return {
		"present": target_present,
		"is_combat_target": combat_target_present,
		"is_shootable_target": target_shootable,
		"stable_id": target_stable_id,
		"target_kind": target_kind,
		"entity_id": best_adapter.entity_id if combat_target_present else 0,
		"entity_kind": String(best_adapter.entity_kind) if combat_target_present else "training_target",
		"position_world": target_position,
		"velocity_world": target_velocity,
		"radius_m": target_radius,
		"distance_m": distance,
		"direct_direction_world": direct_direction,
		"intercept_point_world": intercept_point,
		"intercept_direction_world": intercept_direction,
		"line_of_sight": line_of_sight,
		"within_range": within_range,
		"within_pitch_arc": within_pitch_arc,
		"maximum_range_m": safe_maximum_range_m,
	}


static func empty_probe(fallback_target_position: Vector3) -> Dictionary:
	var safe_fallback_position: Vector3 = (
		fallback_target_position if fallback_target_position.is_finite() else Vector3.ZERO
	)
	return {
		"present": false,
		"is_combat_target": false,
		"is_shootable_target": false,
		"stable_id": "",
		"target_kind": "fallback",
		"entity_id": 0,
		"entity_kind": "training_target",
		"position_world": safe_fallback_position,
		"velocity_world": Vector3.ZERO,
		"radius_m": 0.35,
		"distance_m": 0.0,
		"direct_direction_world": Vector3.FORWARD,
		"intercept_point_world": safe_fallback_position,
		"intercept_direction_world": Vector3.FORWARD,
		"line_of_sight": false,
		"within_range": false,
		"within_pitch_arc": false,
		"maximum_range_m": 1.0,
	}


static func aim_alignment(turret: TurretPhysicalBody3D, target_probe: Dictionary) -> float:
	if not is_instance_valid(turret) or not bool(target_probe.get("present", false)):
		return -1.0
	var direction_value: Variant = target_probe.get("intercept_direction_world", Vector3.ZERO)
	if not (direction_value is Vector3):
		return -1.0
	var intercept_direction: Vector3 = direction_value
	if (
		not intercept_direction.is_finite()
		or intercept_direction.length_squared() <= MINIMUM_DIRECTION_LENGTH_SQUARED
	):
		return -1.0
	return clampf(
		turret.aim_direction_world().dot(intercept_direction.normalized()),
		-1.0,
		1.0
	)


static func is_precision_tracking_state(
	target_state: Dictionary,
	minimum_alignment: float
) -> bool:
	return (
		bool(target_state.get("present", false))
		and bool(target_state.get("line_of_sight", false))
		and bool(target_state.get("within_range", false))
		and bool(target_state.get("within_pitch_arc", false))
		and RLTrainingMath.finite_float_or(
			target_state.get("aim_alignment", -1.0),
			-1.0
		) >= clampf(minimum_alignment, -1.0, 1.0)
	)


static func is_viable_shot(
	turret: TurretPhysicalBody3D,
	target_probe: Dictionary,
	minimum_alignment: float
) -> bool:
	return (
		bool(target_probe.get("present", false))
		and bool(target_probe.get("is_shootable_target", false))
		and bool(target_probe.get("line_of_sight", false))
		and bool(target_probe.get("within_range", false))
		and bool(target_probe.get("within_pitch_arc", false))
		and aim_alignment(turret, target_probe) >= clampf(minimum_alignment, -1.0, 1.0)
	)


static func has_wall_line_of_sight(
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	origin: Vector3,
	target_position: Vector3,
	target_radius: float
) -> bool:
	if not origin.is_finite() or not target_position.is_finite():
		return false
	return not _wall_blocks(
		wall_spatial_hash,
		origin,
		target_position,
		maxf(RLTrainingMath.finite_float_or(target_radius, 0.35), 0.01)
	)


static func target_within_pitch_limits(
	turret: TurretPhysicalBody3D,
	target_position: Vector3,
	target_radius: float
) -> bool:
	if not is_instance_valid(turret) or turret.loadout == null or not target_position.is_finite():
		return false
	var offset: Vector3 = target_position - turret.muzzle_position_world()
	var horizontal_distance: float = Vector2(offset.x, offset.z).length()
	var distance: float = offset.length()
	if distance <= 0.000001:
		return true
	var center_pitch: float = atan2(offset.y, horizontal_distance)
	var safe_radius: float = maxf(
		RLTrainingMath.finite_float_or(target_radius, 0.35),
		0.01
	)
	var angular_radius: float = asin(clampf(safe_radius / distance, 0.0, 1.0))
	var minimum_pitch: float = deg_to_rad(turret.loadout.gun.minimum_pitch_degrees)
	var maximum_pitch: float = deg_to_rad(turret.loadout.gun.maximum_pitch_degrees)
	return (
		center_pitch + angular_radius >= minimum_pitch
		and center_pitch - angular_radius <= maximum_pitch
	)


static func _wall_blocks(
	wall_spatial_hash: DroneTrainingWallSpatialHash,
	origin: Vector3,
	target_position: Vector3,
	target_radius: float
) -> bool:
	if wall_spatial_hash == null:
		return false
	var offset: Vector3 = target_position - origin
	var distance: float = offset.length()
	if distance <= 0.000001:
		return false
	var records: Array = wall_spatial_hash.query_segment(origin, target_position, target_radius)
	var hit: Dictionary = wall_spatial_hash.raycast_records(
		records,
		origin,
		offset / distance,
		distance,
		Vector3.ONE * maxf(target_radius * 0.15, 0.02)
	)
	return not hit.is_empty() and float(hit.get("distance_m", distance + 1.0)) < distance - target_radius
