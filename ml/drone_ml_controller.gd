class_name DroneMLController
extends RefCounted

#######################################################
# Connects snapshots to either a synchronous model adapter or externally submitted actions,
# while keeping malformed and stale actions away from the physics simulation.
#######################################################

var host
var model: DroneMLModel
var enabled = false
var step_index = 0
var latest_observation: Dictionary = {}
var latest_action_error = ""
var current_normalized_commands: Array[float] = []
var current_thrust_targets: Array[float] = []
var current_limb_commands = PackedFloat64Array()
var maximum_static_thrusts: Array[float] = []
var has_cached_action = false
var objective: Dictionary = {}
var model_control_elapsed = 0.0
var cached_air_density = NAN
var static_thrust_cache_valid = false


func _init(owner_drone) -> void:
	host = owner_drone


func enable(value: DroneMLModel = null) -> void:
	model = value
	enabled = true
	step_index = 0
	latest_action_error = ""
	current_normalized_commands.clear()
	current_thrust_targets.clear()
	current_limb_commands = PackedFloat64Array()
	maximum_static_thrusts.clear()
	objective = {}
	model_control_elapsed = 0.0
	cached_air_density = NAN
	static_thrust_cache_valid = false
	if host != null and host.has_method("set_limb_attachments_runtime_active"):
		host.set_limb_attachments_runtime_active(true, false)
	_refresh_maximum_static_thrusts()
	_reset_cached_commands()


func disable() -> void:
	_reset_cached_commands()
	if host != null and host.has_method("set_limb_attachments_runtime_active"):
		host.set_limb_attachments_runtime_active(false, true)
	enabled = false
	model = null
	current_normalized_commands.clear()
	current_thrust_targets.clear()
	maximum_static_thrusts.clear()
	has_cached_action = false
	objective = {}
	latest_action_error = ""
	model_control_elapsed = 0.0
	cached_air_density = NAN
	static_thrust_cache_valid = false


func submit_external_action(action: Dictionary) -> bool:
	# PPO actions are intentionally held until the next decision. Keeping the validated
	# command removes a full snapshot, deep copy, and validation pass on every physics tick.
	# Propagate validation to the caller so trainer telemetry cannot graph a command that never
	# reached the physical actuator cache.
	return _validate_and_cache_action(action)


func step(delta: float) -> Array[float]:
	if model == null:
		return current_thrust_targets

	model_control_elapsed += maxf(delta, 0.0)
	var control_interval = maxf(model.get_control_interval_seconds(), 0.0)
	if (
		not has_cached_action
		or control_interval <= 0.0
		or model_control_elapsed >= control_interval
	):
		var observation_delta = model_control_elapsed
		latest_observation = (
			DroneMLObservation.capture_ppo(host, observation_delta, step_index)
			if model.uses_compact_ppo_observation()
			else DroneMLObservation.capture(host, observation_delta, step_index)
		)
		step_index += 1
		_validate_and_cache_action(model.predict_action(latest_observation))
		model_control_elapsed = (
			fmod(model_control_elapsed, control_interval)
			if control_interval > 0.0
			else 0.0
		)
	return current_thrust_targets


func snapshot_now() -> Dictionary:
	latest_observation = DroneMLObservation.capture(host, 0.0, step_index)
	return latest_observation


func ppo_snapshot_now() -> Dictionary:
	latest_observation = DroneMLObservation.capture_ppo(host, 0.0, step_index)
	return latest_observation


func normalized_commands() -> Array[float]:
	return current_normalized_commands


func static_thrust_limits() -> Array[float]:
	_refresh_maximum_static_thrusts()
	return maximum_static_thrusts


func _validate_and_cache_action(action: Dictionary) -> bool:
	if action.has("body_commands") or action.has("body_interface_signature"):
		return _validate_and_cache_body_action(action)
	return _validate_and_cache_legacy_action(action)


func _validate_and_cache_body_action(action: Dictionary) -> bool:
	var manifest: MLBodyInterfaceManifest = (
		host.model_body_interface()
		if host != null and host.has_method("model_body_interface")
		else null
	)
	var validation: Dictionary = DroneMLAction.validate_body_commands(action, manifest)
	if not bool(validation.get("valid", false)):
		return _reject_action(str(validation.get("error", "Invalid body action")))
	var routed: Dictionary = validation.get("routed", {})
	var normalized_propellers: Array[float] = []
	normalized_propellers.resize(host.propeller_slots.size())
	normalized_propellers.fill(0.0)
	var prepared_slots: Array[Dictionary] = []
	var core_control_count: int = int(manifest.core_record.get("control_count", 0))
	if core_control_count > 0:
		var core_value: Variant = routed.get("core", PackedFloat64Array())
		if not (core_value is PackedFloat64Array):
			return _reject_action("The body action router produced malformed Core commands.")
		var core_commands: PackedFloat64Array = core_value
		if core_commands.size() != core_control_count:
			return _reject_action("The body action router produced the wrong Core command count.")
		if not host.has_method("can_submit_model_core_commands") or not bool(
			host.call("can_submit_model_core_commands", core_commands.size())
		):
			return _reject_action("The runtime Core cannot accept its finalized model controls.")
		prepared_slots.append({
			"kind": "core",
			"commands": core_commands,
		})
	for record: Dictionary in manifest.slot_records:
		var count: int = int(record.get("control_count", 0))
		if count <= 0:
			continue
		var slot_id: String = str(record.get("slot_id", ""))
		var local_value: Variant = routed.get(slot_id, PackedFloat64Array())
		if not (local_value is PackedFloat64Array):
			return _reject_action("The body action router produced malformed commands for %s." % slot_id)
		var local: PackedFloat64Array = local_value
		if local.size() != count:
			return _reject_action("The body action router produced the wrong command count for %s." % slot_id)
		if slot_id.begins_with("propeller_"):
			var propeller_slot_index: int = int(slot_id.trim_prefix("propeller_"))
			var runtime_index: int = _propeller_runtime_index(propeller_slot_index)
			if runtime_index < 0 or local.size() != 1:
				return _reject_action("The finalized propeller slot is missing from the runtime drone.")
			prepared_slots.append({
				"kind": "propeller",
				"runtime_index": runtime_index,
				"commands": local,
			})
		elif slot_id.begins_with("attachment_"):
			var attachment_slot_index: int = int(slot_id.trim_prefix("attachment_"))
			if (
				not host.has_method("can_submit_model_attachment_slot_commands")
				or not host.can_submit_model_attachment_slot_commands(attachment_slot_index, local.size())
			):
				return _reject_action("Attachment %d cannot accept its finalized model controls." % attachment_slot_index)
			prepared_slots.append({
				"kind": "attachment",
				"slot_index": attachment_slot_index,
				"commands": local,
			})
		else:
			# Future host-specific Core slots must provide a preflight hook. This prevents one
			# earlier attachment from receiving a command before a later unsupported slot fails.
			if not host.has_method("can_submit_model_slot_commands") or not bool(
				host.call("can_submit_model_slot_commands", slot_id, local.size())
			):
				return _reject_action("Runtime body does not implement controlled slot %s." % slot_id)
			prepared_slots.append({
				"kind": "generic",
				"slot_id": slot_id,
				"commands": local,
			})

	# Apply only after every controlled slot has passed preflight. A malformed future gun/tool
	# cannot leave earlier limbs with a partially-applied action.
	var attachment_commands = PackedFloat64Array()
	for prepared: Dictionary in prepared_slots:
		var local: PackedFloat64Array = prepared.get("commands", PackedFloat64Array())
		match str(prepared.get("kind", "")):
			"core":
				if not bool(host.call("submit_model_core_commands", local)):
					return _reject_action("The runtime Core rejected its preflighted model controls.")
			"propeller":
				var runtime_index: int = int(prepared.get("runtime_index", -1))
				normalized_propellers[runtime_index] = clampf(local[0], 0.0, 1.0)
			"attachment":
				var attachment_slot_index: int = int(prepared.get("slot_index", -1))
				if not host.submit_model_attachment_slot_commands(attachment_slot_index, local):
					return _reject_action("Attachment %d rejected its preflighted model commands." % attachment_slot_index)
				attachment_commands.append_array(local)
			"generic":
				if not bool(host.call("submit_model_slot_commands", str(prepared.get("slot_id", "")), local)):
					return _reject_action("Runtime body rejected controlled slot %s." % str(prepared.get("slot_id", "")))
	latest_action_error = ""
	current_normalized_commands = normalized_propellers
	current_limb_commands = attachment_commands
	_refresh_maximum_static_thrusts()
	current_thrust_targets.resize(current_normalized_commands.size())
	for index in range(current_normalized_commands.size()):
		current_thrust_targets[index] = current_normalized_commands[index] * maximum_static_thrusts[index]
	has_cached_action = true
	return true


func _validate_and_cache_legacy_action(action: Dictionary) -> bool:
	var validation = DroneMLAction.validate(action, host.propeller_slots)
	if not bool(validation.get("valid", false)):
		return _reject_action(str(validation.get("error", "Invalid ML action")))
	var limb_validation = DroneMLAction.validate_limb_commands(
		action,
		host.total_limb_attachment_action_count() if host.has_method("total_limb_attachment_action_count") else 0
	)
	if not bool(limb_validation.get("valid", false)):
		return _reject_action(str(limb_validation.get("error", "Invalid limb action")))
	latest_action_error = ""
	current_normalized_commands = validation["commands"]
	current_limb_commands = limb_validation.get("commands", PackedFloat64Array())
	if host.has_method("submit_all_limb_attachment_commands") and not host.submit_all_limb_attachment_commands(current_limb_commands):
		return _reject_action("The drone rejected its legacy manipulator command topology.")
	_refresh_maximum_static_thrusts()
	current_thrust_targets.resize(current_normalized_commands.size())
	for index in range(current_normalized_commands.size()):
		current_thrust_targets[index] = current_normalized_commands[index] * maximum_static_thrusts[index]
	has_cached_action = true
	return true


func _reject_action(message: String) -> bool:
	latest_action_error = message
	_reset_cached_commands()
	_release_manipulator_grips()
	return false


func _propeller_runtime_index(slot_index: int) -> int:
	for index in range(host.propeller_slots.size()):
		if int(host.propeller_slots[index].slot_index) == slot_index:
			return index
	return -1


func invalidate_static_thrust_cache() -> void:
	static_thrust_cache_valid = false
	cached_air_density = NAN


func _refresh_maximum_static_thrusts() -> void:
	var air_density = (
		host.air_environment.air_density
		if host.air_environment != null
		else 0.0
	)
	if (
		static_thrust_cache_valid
		and maximum_static_thrusts.size() == host.propeller_slots.size()
		and is_equal_approx(cached_air_density, air_density)
	):
		return
	cached_air_density = air_density
	static_thrust_cache_valid = true
	maximum_static_thrusts.resize(host.propeller_slots.size())
	maximum_static_thrusts.fill(0.0)
	if host.loadout == null or host.air_environment == null:
		return
	for index in range(host.propeller_slots.size()):
		var slot = host.propeller_slots[index]
		var propeller = host.loadout.get_propeller(int(slot.slot_index))
		if propeller == null:
			continue
		maximum_static_thrusts[index] = host.air_environment.calculate_rotor_thrust(
			propeller.max_power_draw,
			propeller.get_disk_area(),
			propeller.aerodynamic_efficiency
		)


func _release_manipulator_grips() -> void:
	if host != null and host.has_method("release_limb_attachment_grips"):
		host.release_limb_attachment_grips()


func _reset_cached_commands() -> void:
	has_cached_action = false
	current_normalized_commands.resize(host.propeller_slots.size())
	current_normalized_commands.fill(0.0)
	current_thrust_targets.resize(host.propeller_slots.size())
	current_thrust_targets.fill(0.0)
	current_limb_commands = PackedFloat64Array()
	var manifest: MLBodyInterfaceManifest = (
		host.model_body_interface()
		if host != null and host.has_method("model_body_interface")
		else null
	)
	if manifest == null or not manifest.finalized:
		var limb_count: int = (
			host.total_limb_attachment_action_count()
			if host != null and host.has_method("total_limb_attachment_action_count")
			else 0
		)
		current_limb_commands.resize(limb_count)
		current_limb_commands.fill(0.0)
		if host != null and host.has_method("submit_all_limb_attachment_commands"):
			host.submit_all_limb_attachment_commands(current_limb_commands)
		return
	var neutral = PackedFloat64Array()
	neutral.resize(manifest.control_count())
	for index in range(manifest.control_count()):
		var descriptor: Dictionary = manifest.control_descriptors[index]
		neutral[index] = RLTrainingMath.finite_float_or(descriptor.get("neutral", 0.0), 0.0)
	var routed: Dictionary = manifest.route_controls(neutral)
	var core_control_count: int = int(manifest.core_record.get("control_count", 0))
	if core_control_count > 0:
		var core_value: Variant = routed.get("core", PackedFloat64Array())
		if core_value is PackedFloat64Array:
			var core_commands: PackedFloat64Array = core_value
			if (
				core_commands.size() == core_control_count
				and host.has_method("can_submit_model_core_commands")
				and bool(host.call("can_submit_model_core_commands", core_commands.size()))
			):
				host.call("submit_model_core_commands", core_commands)
	for record: Dictionary in manifest.slot_records:
		var slot_id: String = str(record.get("slot_id", ""))
		if int(record.get("control_count", 0)) <= 0:
			continue
		var local_value: Variant = routed.get(slot_id, PackedFloat64Array())
		if not (local_value is PackedFloat64Array):
			continue
		var local: PackedFloat64Array = local_value
		if slot_id.begins_with("attachment_"):
			var slot_index: int = int(slot_id.trim_prefix("attachment_"))
			if host.has_method("can_submit_model_attachment_slot_commands") and host.can_submit_model_attachment_slot_commands(slot_index, local.size()):
				host.submit_model_attachment_slot_commands(slot_index, local)
				current_limb_commands.append_array(local)
		elif not slot_id.begins_with("propeller_") and host.has_method("can_submit_model_slot_commands") and bool(
			host.call("can_submit_model_slot_commands", slot_id, local.size())
		):
			host.call("submit_model_slot_commands", slot_id, local)
