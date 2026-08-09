class_name EnemyBehaviorController
extends RefCounted

#######################################################
# Coordinates enemy behavior state and translates current inputs into gameplay decisions or
# actuator targets.
#######################################################

var attack_cooldown_remaining := 0.0
var attack_phase := 0.0


func evaluate(
	delta: float,
	definition: EnemyBehaviorDefinition,
	host_position: Vector3,
	roam_center: Vector3,
	candidates: Array[Dictionary]
) -> Dictionary:
	attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	attack_phase = maxf(attack_phase - delta * 3.5, 0.0)
	if (
		definition == null
		or definition.behavior_type
		== EnemyBehaviorDefinition.BehaviorType.STATIONARY
	):
		return {
			"movement_active": false,
			"attack_requested": false,
			"attack_phase": attack_phase,
		}

	var target := _nearest_candidate(host_position, candidates)
	if target.is_empty():
		return {
			"movement_active": false,
			"attack_requested": false,
			"attack_phase": attack_phase,
		}
	var target_position: Vector3 = target.get("position", host_position)
	var to_target := target_position - host_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > definition.notice_range:
		return {
			"movement_active": false,
			"target_id": int(target.get("target_id", -1)),
			"attack_requested": false,
			"attack_phase": attack_phase,
		}

	var desired_direction := (
		to_target / distance if distance > 0.001 else Vector3.ZERO
	)
	var desired_velocity := Vector3.ZERO
	if distance > definition.preferred_distance:
		desired_velocity = desired_direction * definition.maximum_speed
		var proposed_position := host_position + desired_velocity * delta
		var from_roam_center := proposed_position - roam_center
		from_roam_center.y = 0.0
		if from_roam_center.length() > definition.roam_radius:
			var boundary: Vector3 = (
				roam_center
				+ from_roam_center.normalized() * definition.roam_radius
			)
			var toward_boundary: Vector3 = boundary - host_position
			toward_boundary.y = 0.0
			desired_velocity = (
				toward_boundary.normalized() * definition.maximum_speed
				if toward_boundary.length_squared() > 0.0001
				else Vector3.ZERO
			)

	var attack_requested := (
		distance <= definition.attack_range
		and attack_cooldown_remaining <= 0.0
	)
	if attack_requested:
		attack_cooldown_remaining = definition.attack_cooldown
		attack_phase = 1.0
	return {
		"movement_active": desired_velocity.length_squared() > 0.0001,
		"desired_velocity": desired_velocity,
		"desired_forward": desired_direction,
		"target_id": int(target.get("target_id", -1)),
		"target_body": target.get("body"),
		"target_position": target_position,
		"attack_requested": attack_requested,
		"attack_phase": attack_phase,
	}


static func _nearest_candidate(
	origin: Vector3,
	candidates: Array[Dictionary]
) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance_squared := INF
	for candidate: Dictionary in candidates:
		var position: Vector3 = candidate.get("position", origin)
		var distance_squared := origin.distance_squared_to(position)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest = candidate
	return nearest
