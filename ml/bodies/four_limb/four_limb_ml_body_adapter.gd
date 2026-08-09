class_name FourLimbMLBodyAdapter
extends MLControllableBodyAdapter

#######################################################
# Learning/runtime adapter for the raw 16-actuator four-limb body.
#######################################################

var body: FourLimbPhysicalBody3D
var objective: Dictionary = {}
var accepted_body_manifest: MLBodyInterfaceManifest


func _init(owner_body: FourLimbPhysicalBody3D = null) -> void:
	body = owner_body


func body_profile_id() -> String:
	return FourLimbBodyDefinition.BODY_PROFILE_ID


func observation_schema_version() -> int:
	return FourLimbMLObservation.SCHEMA_VERSION


func action_schema_version() -> int:
	return FourLimbMLAction.SCHEMA_VERSION


func action_count() -> int:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	return manifest.control_count() if manifest != null else FourLimbMLAction.ACTION_COUNT


func model_body_interface() -> MLBodyInterfaceManifest:
	if accepted_body_manifest == null:
		accepted_body_manifest = FourLimbMLBodyInterfaceFactory.finalize_runtime_body(body)
	return accepted_body_manifest


func refresh_model_body_interface() -> MLBodyInterfaceManifest:
	accepted_body_manifest = FourLimbMLBodyInterfaceFactory.finalize_runtime_body(body)
	return accepted_body_manifest


func model_body_observation_features() -> PackedFloat64Array:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	if manifest == null:
		return PackedFloat64Array()
	return manifest.encode_body_observation(
		FourLimbMLBodyInterfaceFactory.runtime_states(body),
		FourLimbMLBodyInterfaceFactory.host_state(body)
	)


func capture_observation(new_objective: Dictionary = {}) -> Dictionary:
	if not new_objective.is_empty():
		objective = _objective_with_defaults(new_objective)
	if not is_instance_valid(body):
		return {}
	return _validated_snapshot(body.get_ml_snapshot(objective))


func capture_observation_with_contacts(
	new_objective: Dictionary,
	contact_snapshot: Dictionary
) -> Dictionary:
	if not new_objective.is_empty():
		objective = _objective_with_defaults(new_objective)
	if not is_instance_valid(body):
		return {}
	return _validated_snapshot(body.get_ml_snapshot(objective, contact_snapshot))


func _objective_with_defaults(source: Dictionary) -> Dictionary:
	var result = source.duplicate(false)
	if not (result.get("turret_threat_probe", {}) is Dictionary):
		result["turret_threat_probe"] = TrainingTurretThreatSensor.empty_probe()
	elif (result.get("turret_threat_probe", {}) as Dictionary).is_empty():
		result["turret_threat_probe"] = TrainingTurretThreatSensor.empty_probe()
	return result


func _validated_snapshot(snapshot: Dictionary) -> Dictionary:
	# Reward calculation and policy inference share this adapter output. Reject bad sensor data here
	# so neither path can silently treat NaN, missing contact slots, or malformed attachment input as
	# a legitimate zero-valued physical state.
	return snapshot if FourLimbMLObservation.is_valid(snapshot) else {}


func apply_action(action: Dictionary) -> bool:
	return is_instance_valid(body) and body.submit_ml_action(action)


func apply_commands(commands: PackedFloat64Array) -> bool:
	return is_instance_valid(body) and body.submit_raw_commands(commands)


func apply_model_body_commands(commands: PackedFloat64Array, _routed: Dictionary) -> bool:
	# The established four-limb rig already exposes one flat physical controller. The generic limb
	# descriptor builder preserves its authored action mapping, so the accepted manifest order is
	# exactly the rig's raw command order for this legacy fixed profile.
	return (
		is_instance_valid(body)
		and commands.size() == FourLimbMLAction.ACTION_COUNT
		and body.submit_raw_commands(commands)
	)


func reset_body(spawn_transform: Transform3D, _random_seed: int = 0) -> bool:
	if not is_instance_valid(body):
		return false
	body.global_transform = spawn_transform
	body.configure(body.definition)
	return refresh_model_body_interface() != null


func is_alive() -> bool:
	return is_instance_valid(body) and body.is_body_alive()


func failure_reason() -> String:
	return body.last_failure_reason if is_instance_valid(body) else "missing_body"


func camera_anchor_transform() -> Transform3D:
	return body.camera_anchor_transform() if is_instance_valid(body) else Transform3D.IDENTITY


func hardware_signature() -> String:
	return body.hardware_signature() if is_instance_valid(body) else ""
