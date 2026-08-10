class_name MLControllableBodyAdapter
extends RefCounted

#######################################################
# Stable boundary between a physical gameplay body and a learning policy. Worker-specific
# task/reward observations can remain specialized, while every physical topology is exposed through
# the same accepted Core/slot/part manifest and action-routing contract.
#######################################################


func body_profile_id() -> String:
	return ""


func observation_schema_version() -> int:
	return 0


func action_schema_version() -> int:
	return 0


func action_count() -> int:
	return 0


func capture_observation(_objective: Dictionary = {}) -> Dictionary:
	return {}


func apply_action(_action: Dictionary) -> bool:
	return false


func reset_body(_spawn_transform: Transform3D, _random_seed: int = 0) -> bool:
	return false


func is_alive() -> bool:
	return false


func failure_reason() -> String:
	return ""


func camera_anchor_transform() -> Transform3D:
	return Transform3D.IDENTITY


func hardware_signature() -> String:
	return ""


func model_body_interface() -> MLBodyInterfaceManifest:
	return null


func model_body_observation_features() -> PackedFloat64Array:
	return PackedFloat64Array()


func model_body_interface_signature() -> String:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	return manifest.contract_signature if manifest != null and manifest.finalized else ""


func model_body_runtime_contract() -> Dictionary:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	if manifest == null or not manifest.finalized:
		return {}
	return {
		"action_count": manifest.control_count(),
		"body_feature_count": manifest.observation_count(),
		"body_interface_signature": manifest.contract_signature,
		"body_interface": manifest.to_dictionary(),
	}


func validate_model_body_action(action: Dictionary) -> Dictionary:
	return MLBodyActionContract.validate(action, model_body_interface())


func apply_model_body_action(action: Dictionary) -> bool:
	# Common action entry point paired with build_model_input_vector(). Body adapters translate the
	# generic Core/slot routes into their physical runtime without changing neural channel ownership.
	var validation: Dictionary = validate_model_body_action(action)
	if not bool(validation.get("valid", false)):
		return false
	var commands_value: Variant = validation.get("commands", PackedFloat64Array())
	var routed_value: Variant = validation.get("routed", {})
	if not (commands_value is PackedFloat64Array) or not (routed_value is Dictionary):
		return false
	var commands: PackedFloat64Array = commands_value
	var routed: Dictionary = routed_value
	return apply_model_body_commands(commands, routed)


func apply_model_body_commands(_commands: PackedFloat64Array, _routed: Dictionary) -> bool:
	return false


func build_model_input_vector(task_and_environment_features: PackedFloat64Array) -> PackedFloat64Array:
	# One common final assembly boundary for every worker adapter. Legacy trainers may still build
	# their established fixed profile internally, while the body-creator path can call this after
	# Accept without knowing whether the body is a drone, creature, turret, or future Core type.
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	# model_body_observation_features() was produced by the finalized manifest, which already
	# checked every body channel against its descriptor. Avoid scanning the large articulated body
	# block a second time before every policy forward pass.
	return MLModelInputVectorBuilder.combine_finalized(
		manifest,
		model_body_observation_features(),
		task_and_environment_features,
		true
	)
