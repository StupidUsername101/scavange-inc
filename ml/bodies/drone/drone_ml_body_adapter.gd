class_name DroneMLBodyAdapter
extends MLControllableBodyAdapter

const BODY_PROFILE_ID = "quadrotor_raw_propellers_v1"

#######################################################
# Wraps the existing ServerDrone API without changing its observation or raw-propeller
# behavior. The four-limb implementation uses the same outer boundary beside this adapter.
#######################################################

var drone: ServerDrone
var runtime_model: DroneMLModel


func _init(owner_drone: ServerDrone = null, model: DroneMLModel = null) -> void:
	drone = owner_drone
	runtime_model = model


func body_profile_id() -> String:
	return BODY_PROFILE_ID


func observation_schema_version() -> int:
	return DronePPOObservationEncoder.SCHEMA_VERSION


func action_schema_version() -> int:
	return DroneMLAction.SCHEMA_VERSION


func action_count() -> int:
	return drone.model_body_control_count() if is_instance_valid(drone) else 0


func model_body_interface() -> MLBodyInterfaceManifest:
	return drone.model_body_interface() if is_instance_valid(drone) else null


func model_body_observation_features() -> PackedFloat64Array:
	return (
		drone.model_body_observation_features()
		if is_instance_valid(drone)
		else PackedFloat64Array()
	)


func capture_observation(_objective: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(drone):
		return {}
	return drone.get_ppo_snapshot()


func apply_action(action: Dictionary) -> bool:
	return is_instance_valid(drone) and drone.submit_ml_action(action)


func apply_model_body_action(action: Dictionary) -> bool:
	# ServerDrone's ML controller consumes the same body_commands/signature dictionary directly and
	# performs an all-owner preflight before applying Core/propeller/attachment commands.
	return is_instance_valid(drone) and drone.submit_ml_action(action)


func reset_body(spawn_transform: Transform3D, random_seed: int = 0) -> bool:
	if not is_instance_valid(drone) or runtime_model == null:
		return false
	return drone.reset_ml_episode(spawn_transform, random_seed, runtime_model)


func is_alive() -> bool:
	return is_instance_valid(drone) and drone.current_health > 0.0


func failure_reason() -> String:
	if not is_instance_valid(drone):
		return "missing_body"
	return "" if drone.current_health > 0.0 else "destroyed"


func camera_anchor_transform() -> Transform3D:
	return drone.global_transform if is_instance_valid(drone) else Transform3D.IDENTITY


func hardware_signature() -> String:
	if not is_instance_valid(drone):
		return ""
	var limits = drone.get_ml_static_thrust_limits()
	return "%s:%s" % [BODY_PROFILE_ID, JSON.stringify(limits)]
