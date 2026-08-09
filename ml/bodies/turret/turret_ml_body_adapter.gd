class_name TurretMLBodyAdapter
extends MLControllableBodyAdapter

var turret: TurretPhysicalBody3D
var target_probe: Dictionary = {}
var episode_progress = 0.0
var previous_commands = TurretMLAction.neutral_commands()
var combat_events: Dictionary = {}
var accepted_body_manifest: MLBodyInterfaceManifest


func _init(owner_turret: TurretPhysicalBody3D = null) -> void:
	turret = owner_turret


func body_profile_id() -> String:
	return TurretPhysicalBody3D.BODY_PROFILE_ID


func observation_schema_version() -> int:
	return TurretMLObservation.SCHEMA_VERSION


func action_schema_version() -> int:
	return TurretMLAction.SCHEMA_VERSION


func action_count() -> int:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	return manifest.control_count() if manifest != null else TurretMLAction.ACTION_COUNT


func model_body_interface() -> MLBodyInterfaceManifest:
	if accepted_body_manifest == null and is_instance_valid(turret) and turret.loadout != null:
		accepted_body_manifest = TurretMLBodyInterfaceFactory.finalize_loadout(turret.loadout)
	return accepted_body_manifest


func refresh_model_body_interface() -> MLBodyInterfaceManifest:
	accepted_body_manifest = (
		TurretMLBodyInterfaceFactory.finalize_loadout(turret.loadout)
		if is_instance_valid(turret) and turret.loadout != null
		else null
	)
	return accepted_body_manifest


func model_body_observation_features() -> PackedFloat64Array:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	if manifest == null:
		return PackedFloat64Array()
	return manifest.encode_body_observation(
		TurretMLBodyInterfaceFactory.runtime_states(turret),
		{}
	)


func set_context(
	new_target_probe: Dictionary,
	new_episode_progress: float,
	new_previous_commands: PackedFloat64Array,
	new_combat_events: Dictionary = {}
) -> void:
	# The coordinator creates fresh probe/event dictionaries and replaces command arrays rather than
	# mutating them. Retain those immutable snapshots by reference until capture_observation().
	target_probe = new_target_probe
	episode_progress = clampf(new_episode_progress, 0.0, 1.0)
	previous_commands = new_previous_commands
	combat_events = new_combat_events


func capture_observation(_objective: Dictionary = {}) -> Dictionary:
	var observation: Dictionary = TurretMLObservation.capture(
		turret,
		target_probe,
		episode_progress,
		previous_commands,
		combat_events
	)
	# Reward calculation and policy inference share this adapter output. Do not let a malformed or
	# non-finite physics snapshot reach either path: once a NaN enters a reward total or feature
	# tensor it can contaminate an entire rollout before the model itself gets a chance to reject it.
	return observation if TurretMLObservation.is_valid(observation) else {}


func apply_action(action: Dictionary) -> bool:
	return is_instance_valid(turret) and turret.submit_ml_action(action)


func apply_commands(commands: PackedFloat64Array) -> bool:
	return is_instance_valid(turret) and turret.submit_raw_commands(commands)


func apply_model_body_commands(_commands: PackedFloat64Array, routed: Dictionary) -> bool:
	if not is_instance_valid(turret):
		return false
	var core_value: Variant = routed.get("core", PackedFloat64Array())
	var gun_value: Variant = routed.get("gun", PackedFloat64Array())
	if not (core_value is PackedFloat64Array) or not (gun_value is PackedFloat64Array):
		return false
	var core_commands: PackedFloat64Array = core_value
	var gun_commands: PackedFloat64Array = gun_value
	if core_commands.size() != 1 or gun_commands.size() != 2:
		return false
	# The generic gun part owns a physical 0..1 trigger channel. The legacy turret raw controller
	# stores that same channel as -1..1, so this adapter is the only compatibility translation.
	var legacy_commands = PackedFloat64Array([
		core_commands[0],
		gun_commands[0],
		clampf(gun_commands[1], 0.0, 1.0) * 2.0 - 1.0,
	])
	return turret.submit_raw_commands(legacy_commands)


func reset_body(spawn_transform: Transform3D, random_seed: int = 0) -> bool:
	if not is_instance_valid(turret):
		return false
	if not turret.reset_body(spawn_transform, random_seed):
		return false
	previous_commands = TurretMLAction.neutral_commands()
	return true


func is_alive() -> bool:
	return is_instance_valid(turret) and turret.is_body_alive()


func failure_reason() -> String:
	return "" if is_alive() else "destroyed"


func camera_anchor_transform() -> Transform3D:
	return turret.camera_anchor_transform() if is_instance_valid(turret) else Transform3D.IDENTITY


func hardware_signature() -> String:
	return turret.hardware_signature() if is_instance_valid(turret) else ""
