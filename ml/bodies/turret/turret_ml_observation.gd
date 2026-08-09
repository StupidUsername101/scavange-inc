class_name TurretMLObservation
extends RefCounted

const SCHEMA_VERSION = 5


static func capture(
	turret: TurretPhysicalBody3D,
	target_probe: Dictionary,
	episode_progress: float,
	previous_commands: PackedFloat64Array,
	combat_events: Dictionary = {}
) -> Dictionary:
	if not is_instance_valid(turret) or turret.loadout == null:
		return {}
	var safe_target = target_probe
	if safe_target.is_empty():
		safe_target = TurretTrainingTargetSensor.empty_probe(turret.global_position + Vector3.FORWARD)
	var base_basis = turret.global_basis.orthonormalized()
	var inverse_base_basis = base_basis.inverse()
	var target_position: Vector3 = safe_target.get("position_world", turret.global_position)
	var target_velocity: Vector3 = safe_target.get("velocity_world", Vector3.ZERO)
	var intercept_direction_world: Vector3 = safe_target.get(
		"intercept_direction_world",
		Vector3.FORWARD
	)
	var direct_direction_world: Vector3 = safe_target.get(
		"direct_direction_world",
		Vector3.FORWARD
	)
	var aim_direction_world = turret.aim_direction_world()
	var muzzle_position = turret.muzzle_position_world()
	var target_offset_world = target_position - muzzle_position
	var target_offset_local = inverse_base_basis * target_offset_world
	var target_velocity_local = inverse_base_basis * target_velocity
	var aim_direction_local = inverse_base_basis * aim_direction_world
	var direct_direction_local = inverse_base_basis * direct_direction_world
	var intercept_direction_local = inverse_base_basis * intercept_direction_world
	var target_present: bool = bool(safe_target.get("present", false))
	var aim_alignment: float = TurretTrainingTargetSensor.aim_alignment(turret, safe_target)
	var yaw_error_radians: float = 0.0
	var pitch_error_radians: float = 0.0
	if target_present:
		var desired_yaw_radians: float = atan2(
			-intercept_direction_local.x,
			-intercept_direction_local.z
		)
		var horizontal_length: float = Vector2(
			intercept_direction_local.x,
			intercept_direction_local.z
		).length()
		var desired_pitch_radians: float = atan2(
			intercept_direction_local.y,
			horizontal_length
		)
		yaw_error_radians = wrapf(
			desired_yaw_radians - turret.yaw_angle_radians,
			-PI,
			PI
		)
		pitch_error_radians = desired_pitch_radians - turret.pitch_angle_radians
	return {
		"schema_version": SCHEMA_VERSION,
		"body_profile_id": TurretPhysicalBody3D.BODY_PROFILE_ID,
		"hardware_signature": turret.hardware_signature(),
		"body": {
			"position_world": turret.global_position,
			"basis_world": base_basis,
			"yaw_angle_radians": turret.yaw_angle_radians,
			"pitch_angle_radians": turret.pitch_angle_radians,
			"yaw_velocity_radians_per_second": turret.yaw_velocity_radians_per_second,
			"pitch_velocity_radians_per_second": turret.pitch_velocity_radians_per_second,
			"aim_direction_world": aim_direction_world,
			"aim_direction_local": aim_direction_local,
			"health_ratio": turret.current_health / maxf(turret.loadout.maximum_health(), 1.0),
		},
		"weapon": {
			"cooldown_ready_ratio": turret.cooldown_ready_ratio(),
			"projectile_speed_mps": turret.loadout.gun.projectile_speed_mps,
			"maximum_range_m": turret.loadout.gun.maximum_range_m,
			"seconds_between_shots": turret.loadout.gun.seconds_between_shots,
			"trigger_command": turret.trigger_command,
		},
		"target": {
			"present": target_present,
			"is_combat_target": bool(safe_target.get(
				"is_combat_target", int(safe_target.get("entity_id", 0)) > 0
			)),
			"is_shootable_target": bool(safe_target.get(
				"is_shootable_target", false
			)),
			"stable_id": str(safe_target.get("stable_id", "")),
			"target_kind": str(safe_target.get("target_kind", "fallback")),
			"entity_id": int(safe_target.get("entity_id", 0)),
			"entity_kind": str(safe_target.get("entity_kind", "training_target")),
			"position_world": target_position,
			"velocity_world": target_velocity,
			"offset_local": target_offset_local,
			"velocity_local": target_velocity_local,
			"direct_direction_local": direct_direction_local,
			"intercept_direction_local": intercept_direction_local,
			"distance_m": float(safe_target.get("distance_m", target_offset_world.length())),
			"radius_m": maxf(float(safe_target.get("radius_m", 0.35)), 0.01),
			"line_of_sight": bool(safe_target.get("line_of_sight", false)),
			"within_range": bool(safe_target.get("within_range", false)),
			"within_pitch_arc": bool(safe_target.get("within_pitch_arc", false)),
			"aim_alignment": aim_alignment,
			"yaw_error_radians": yaw_error_radians,
			"pitch_error_radians": pitch_error_radians,
		},
		"combat": {
			"damage_taken": maxf(float(combat_events.get("damage_taken", 0.0)), 0.0),
			"hit_count": maxi(int(combat_events.get("hit_count", 0)), 0),
		},
		"episode_progress": clampf(episode_progress, 0.0, 1.0),
		"previous_commands": previous_commands,
	}


static func is_valid(observation: Dictionary) -> bool:
	if (
		int(observation.get("schema_version", 0)) != SCHEMA_VERSION
		or str(observation.get("body_profile_id", "")) != TurretPhysicalBody3D.BODY_PROFILE_ID
		or not (observation.get("hardware_signature", "") is String)
	):
		return false
	for section_name in ["body", "weapon", "target", "combat"]:
		if not (observation.get(section_name, {}) is Dictionary):
			return false
	var body: Dictionary = observation["body"]
	var weapon: Dictionary = observation["weapon"]
	var target: Dictionary = observation["target"]
	var combat: Dictionary = observation["combat"]
	for key in ["position_world", "aim_direction_world", "aim_direction_local"]:
		if not _finite_vector(body.get(key)):
			return false
	var basis_value: Variant = body.get("basis_world")
	if not (basis_value is Basis) or not (basis_value as Basis).is_finite():
		return false
	for key in [
		"yaw_angle_radians", "pitch_angle_radians",
		"yaw_velocity_radians_per_second", "pitch_velocity_radians_per_second",
		"health_ratio",
	]:
		if not _finite_number(body.get(key)):
			return false
	if float(body["health_ratio"]) < 0.0 or float(body["health_ratio"]) > 1.000001:
		return false
	for key in [
		"cooldown_ready_ratio", "projectile_speed_mps", "maximum_range_m",
		"seconds_between_shots", "trigger_command",
	]:
		if not _finite_number(weapon.get(key)):
			return false
	if (
		float(weapon["cooldown_ready_ratio"]) < 0.0
		or float(weapon["cooldown_ready_ratio"]) > 1.000001
		or float(weapon["projectile_speed_mps"]) <= 0.0
		or float(weapon["maximum_range_m"]) <= 0.0
		or float(weapon["seconds_between_shots"]) <= 0.0
		or float(weapon["trigger_command"]) < 0.0
		or float(weapon["trigger_command"]) > 1.000001
	):
		return false
	if (
		not (target.get("present") is bool)
		or not (target.get("is_combat_target") is bool)
		or not (target.get("is_shootable_target") is bool)
		or not (target.get("stable_id", "") is String)
		or not (target.get("target_kind", "") is String)
		or not (target.get("line_of_sight") is bool)
		or not (target.get("within_range") is bool)
		or not (target.get("within_pitch_arc") is bool)
	):
		return false
	if not (target.get("entity_id") is int) or int(target["entity_id"]) < 0:
		return false
	if not (target.get("entity_kind", "") is String):
		return false
	var target_present: bool = bool(target.get("present", false))
	var target_is_combat: bool = bool(target.get("is_combat_target", false))
	var target_is_shootable: bool = bool(target.get("is_shootable_target", false))
	if target_present and str(target.get("stable_id", "")).is_empty():
		return false
	if target_is_combat and (not target_present or int(target.get("entity_id", 0)) <= 0):
		return false
	if target_is_shootable and not target_present:
		return false
	for key in [
		"position_world", "velocity_world", "offset_local", "velocity_local",
		"direct_direction_local", "intercept_direction_local",
	]:
		if not _finite_vector(target.get(key)):
			return false
	for key in [
		"distance_m", "radius_m", "aim_alignment",
		"yaw_error_radians", "pitch_error_radians",
	]:
		if not _finite_number(target.get(key)):
			return false
	if (
		float(target["distance_m"]) < 0.0
		or float(target["radius_m"]) <= 0.0
		or float(target["aim_alignment"]) < -1.000001
		or float(target["aim_alignment"]) > 1.000001
	):
		return false
	if (
		not _finite_number(combat.get("damage_taken"))
		or float(combat["damage_taken"]) < 0.0
		or not (combat.get("hit_count") is int)
		or int(combat["hit_count"]) < 0
	):
		return false
	if not _finite_number(observation.get("episode_progress")):
		return false
	var progress = float(observation["episode_progress"])
	if progress < 0.0 or progress > 1.000001:
		return false
	var commands: Variant = observation.get("previous_commands", PackedFloat64Array())
	if not (commands is PackedFloat64Array) or (commands as PackedFloat64Array).size() != TurretMLAction.ACTION_COUNT:
		return false
	for command in commands:
		if not is_finite(command) or command < -1.000001 or command > 1.000001:
			return false
	return true


static func _finite_vector(value: Variant) -> bool:
	return value is Vector3 and (value as Vector3).is_finite()


static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
