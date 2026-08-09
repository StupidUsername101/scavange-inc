class_name DroneTrainingPolicy
extends DroneMLModel

const QUAD_PROPELLER_COUNT = 4
const DEFAULT_WEIGHTS = {
	"hover_bias": 0.74,
	"height_gain": 0.12,
	"vertical_damping": 0.08,
	"target_gain": 0.08,
	"horizontal_damping": 0.05,
	"attitude_gain": 0.18,
	"angular_damping": 0.06,
}

#######################################################
# Provides an intentionally simple, editable quadrotor policy for validating the training
# room. It is a baseline controller, not the future learning algorithm.
#######################################################

var weights: Dictionary


func _init(candidate_weights: Dictionary = {}) -> void:
	weights = DEFAULT_WEIGHTS.duplicate(true)
	for key in candidate_weights:
		if weights.has(key):
			weights[key] = float(candidate_weights[key])


func predict_action(observation: Dictionary) -> Dictionary:
	var propellers: Array = observation.get("propellers", [])
	if propellers.size() != QUAD_PROPELLER_COUNT:
		return {}

	var body: Dictionary = observation.get("body", {})
	var objective: Dictionary = observation.get("objective", {})
	var position: Vector3 = body.get("position_world", Vector3.ZERO)
	var basis: Basis = body.get("basis_world", Basis.IDENTITY)
	var velocity: Vector3 = body.get("linear_velocity_world", Vector3.ZERO)
	var angular_local: Vector3 = body.get("angular_velocity_local", Vector3.ZERO)
	var target: Vector3 = objective.get("target_position_world", position)
	var target_radius = float(objective.get("target_hover_radius_m", 0.5))
	var error_world = target - position
	var horizontal_error = Vector3(error_world.x, 0.0, error_world.z)
	if horizontal_error.length() <= target_radius:
		horizontal_error = Vector3.ZERO
	var error_local = basis.inverse() * horizontal_error
	var velocity_local = basis.inverse() * velocity

	var collective = (
		_weight("hover_bias")
		+ error_world.y * _weight("height_gain")
		- velocity.y * _weight("vertical_damping")
	)
	var roll_mix = (
		-error_local.x * _weight("target_gain")
		+ velocity_local.x * _weight("horizontal_damping")
		+ basis.y.x * _weight("attitude_gain")
		+ angular_local.z * _weight("angular_damping")
	)
	var pitch_mix = (
		error_local.z * _weight("target_gain")
		- velocity_local.z * _weight("horizontal_damping")
		- basis.y.z * _weight("attitude_gain")
		- angular_local.x * _weight("angular_damping")
	)
	var yaw_mix = angular_local.y * _weight("angular_damping")
	var mixed = [
		collective + roll_mix + pitch_mix - yaw_mix,
		collective - roll_mix + pitch_mix + yaw_mix,
		collective + roll_mix - pitch_mix + yaw_mix,
		collective - roll_mix - pitch_mix - yaw_mix,
	]
	var commands: Array[Dictionary] = []
	for index in range(QUAD_PROPELLER_COUNT):
		commands.append({
			"slot_index": int(propellers[index].get("slot_index", index)),
			"command": clampf(float(mixed[index]), 0.0, 1.0),
		})
	return {"propeller_commands": commands}


func get_control_interval_seconds() -> float:
	# The diagnostic baseline does not gain anything from recomputing identical control
	# logic at the physics rate. Match the trained policies' default 20 Hz cadence.
	return 0.05


func uses_compact_ppo_observation() -> bool:
	# The compact control snapshot contains every body/objective field used above. The
	# rich diagnostic snapshot remains available through get_ml_snapshot() on demand.
	return true


func _weight(key: String) -> float:
	return float(weights.get(key, 0.0))
