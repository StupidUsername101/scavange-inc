class_name FourLimbPhysicalBody3D
extends Node3D

signal died(body: FourLimbPhysicalBody3D)
signal limb_state_changed(limb_index: int)

#######################################################
# Gameplay-ready wrapper around the simulated core/limbs. The same body is used by training
# and runtime inference; training never moves it through a hidden CharacterBody controller.
#######################################################

@export var definition: FourLimbBodyDefinition
@export var auto_start_simulation = true

var physical_rig: FourLimbPhysicalRig3D
var current_core_health = 0.0
var alive = true
var last_action_time_seconds = 0.0
var simulation_age_seconds = 0.0
var last_failure_reason = ""
# Training rooms can make the shared physical body damage-immune without changing gameplay
# bodies or bypassing rigid-body physics. Explicit kill() still works for deliberate teardown.
var training_invulnerable = false
var installed_attachments: Dictionary[int, FourLimbAttachmentStateProvider] = {}


func _ready() -> void:
	if definition == null:
		push_error("FourLimbPhysicalBody3D requires an explicit accepted/preset body definition.")
		alive = false
		return
	definition.ensure_contract()
	current_core_health = definition.core_maximum_health
	_build_runtime_body()


func _physics_process(delta: float) -> void:
	if not alive or not is_instance_valid(physical_rig) or not physical_rig.runtime_active:
		return
	simulation_age_seconds += maxf(delta, 0.0)
	current_core_health = (
		physical_rig.core_bone.current_health
		if is_instance_valid(physical_rig.core_bone)
		else current_core_health
	)
	if current_core_health <= 0.0:
		if training_invulnerable and definition != null and is_instance_valid(physical_rig.core_bone):
			physical_rig.core_bone.current_health = definition.core_maximum_health
			current_core_health = definition.core_maximum_health
			return
		kill("destroyed")


func configure(body_definition: FourLimbBodyDefinition) -> void:
	definition = body_definition
	if definition == null:
		alive = false
		return
	definition.ensure_contract()
	alive = true
	if is_inside_tree():
		_rebuild_runtime_body()


func submit_ml_action(action: Dictionary) -> bool:
	if not alive or not is_instance_valid(physical_rig):
		return false
	var packed = FourLimbMLAction.packed_commands(action)
	if packed.size() != FourLimbMLAction.ACTION_COUNT:
		return false
	last_action_time_seconds = simulation_age_seconds
	return physical_rig.submit_commands(packed)


func submit_raw_commands(commands: PackedFloat64Array) -> bool:
	if not alive or not is_instance_valid(physical_rig):
		return false
	if commands.size() != FourLimbMLAction.ACTION_COUNT:
		return false
	last_action_time_seconds = simulation_age_seconds
	return physical_rig.submit_commands(commands)


func holds_instance_id(instance_id: int) -> bool:
	return (
		is_instance_valid(physical_rig)
		and physical_rig.holds_instance_id(instance_id)
	)


func get_ml_snapshot(
	objective: Dictionary = {},
	contact_snapshot: Dictionary = {}
) -> Dictionary:
	if not is_instance_valid(physical_rig):
		return {}
	var safe_objective = objective.duplicate(false)
	var core_origin = physical_rig.get_core_transform().origin
	if not safe_objective.has("pickup_item_present"):
		safe_objective["pickup_item_present"] = false
	if not safe_objective.has("pickup_item_position_world"):
		safe_objective["pickup_item_position_world"] = core_origin
	if not safe_objective.has("pickup_item_velocity_world"):
		safe_objective["pickup_item_velocity_world"] = Vector3.ZERO
	if not safe_objective.has("pickup_item_mass"):
		safe_objective["pickup_item_mass"] = 0.0
	if not safe_objective.has("pickup_item_reward_value"):
		safe_objective["pickup_item_reward_value"] = 0.0
	if not safe_objective.has("pickup_item_id"):
		safe_objective["pickup_item_id"] = 0
	if not safe_objective.has("pickup_item_held"):
		safe_objective["pickup_item_held"] = false
	var obstacle_probe_value: Variant = safe_objective.get("obstacle_probe", {})
	if not (obstacle_probe_value is Dictionary) or (obstacle_probe_value as Dictionary).is_empty():
		safe_objective["obstacle_probe"] = FourLimbMLObservation.empty_obstacle_probe()
	var turret_probe_value: Variant = safe_objective.get("turret_threat_probe", {})
	if not (turret_probe_value is Dictionary) or (turret_probe_value as Dictionary).is_empty():
		safe_objective["turret_threat_probe"] = TrainingTurretThreatSensor.empty_probe()
	var physical_state = physical_rig.capture_ml_state(contact_snapshot)
	var context = {
		"body": self,
		"objective": safe_objective,
		"core_transform": physical_rig.get_core_transform(),
	}
	var attachment_capture = (
		physical_rig.attachment_feed.capture_model_feed(context)
		if is_instance_valid(physical_rig.attachment_feed)
		else {"states": [], "features": PackedFloat64Array()}
	)
	return {
		"schema_version": FourLimbMLObservation.SCHEMA_VERSION,
		"body_profile_id": FourLimbBodyDefinition.BODY_PROFILE_ID,
		"hardware_signature": hardware_signature(),
		"body": physical_state.get("body", {}),
		"limbs": physical_state.get("limbs", []),
		"contacts": physical_state.get("contacts", {}),
		"attachments": attachment_capture.get("states", []),
		"attachment_features": attachment_capture.get(
			"features",
			PackedFloat64Array()
		),
		"objective": safe_objective,
		"previous_action_age": maxf(simulation_age_seconds - last_action_time_seconds, 0.0),
	}


func apply_damage(amount: float) -> void:
	if training_invulnerable:
		return
	if not alive or not is_instance_valid(physical_rig.core_bone):
		return
	physical_rig.core_bone.apply_segment_damage(amount)
	current_core_health = physical_rig.core_bone.current_health
	if current_core_health <= 0.0:
		kill("destroyed")


func damage_limb(limb_index: int, amount: float) -> bool:
	if training_invulnerable:
		return true
	return is_instance_valid(physical_rig) and physical_rig.damage_limb(limb_index, amount)


func set_limb_effectiveness(limb_index: int, effectiveness: float) -> bool:
	return is_instance_valid(physical_rig) and physical_rig.set_limb_effectiveness(
		limb_index,
		effectiveness
	)


func apply_attachment_impulse(world_impulse: Vector3, world_position: Vector3) -> bool:
	# Future weapons and tools can use this for recoil or other physical reactions without
	# bypassing the simulated body. No weapon behavior is implemented by the body itself.
	return is_instance_valid(physical_rig) and physical_rig.apply_core_impulse(
		world_impulse,
		world_position
	)


func install_attachment(
	slot_index: int,
	provider: FourLimbAttachmentStateProvider
) -> bool:
	if (
		not is_instance_valid(physical_rig)
		or not is_instance_valid(physical_rig.attachment_feed)
	):
		return false
	var feed = physical_rig.attachment_feed
	# Validate first so a rejected weapon/tag destination never removes an attachment from its
	# current body. This also makes transferring one physical attachment between bodies safe.
	if not feed.can_install_provider(slot_index, provider):
		return false
	var previous = feed.provider_for_slot(slot_index)
	var provider_previous_slot = -1
	for existing_slot_value: Variant in installed_attachments.keys():
		var existing_slot = int(existing_slot_value)
		if installed_attachments.get(existing_slot) == provider:
			provider_previous_slot = existing_slot
			break
	var previous_body = provider.mounted_body
	var previous_body_slot = provider.mounted_slot_index
	if is_instance_valid(previous_body) and previous_body != self:
		previous_body.uninstall_attachment(previous_body_slot)
	if not feed.install_provider(slot_index, provider):
		# This should be unreachable after validation, but restore a cross-body transfer rather
		# than leaving gameplay equipment detached if the destination changed unexpectedly.
		if is_instance_valid(previous_body) and previous_body != self:
			previous_body.install_attachment(previous_body_slot, provider)
		return false
	if provider_previous_slot >= 0 and provider_previous_slot != slot_index:
		installed_attachments.erase(provider_previous_slot)
		provider.on_unmounted_from_body(self, provider_previous_slot)
	if is_instance_valid(previous) and previous != provider:
		installed_attachments.erase(slot_index)
		previous.on_unmounted_from_body(self, slot_index)
		if previous.get_parent() != self:
			previous.reparent(self, true)
	installed_attachments[slot_index] = provider
	provider.on_mounted_to_body(self, slot_index)
	physical_rig.refresh_attachment_mass()
	return true


func uninstall_attachment(slot_index: int) -> FourLimbAttachmentStateProvider:
	var recorded = installed_attachments.get(slot_index) as FourLimbAttachmentStateProvider
	installed_attachments.erase(slot_index)
	var provider = recorded
	if is_instance_valid(physical_rig) and is_instance_valid(physical_rig.attachment_feed):
		var mounted = physical_rig.attachment_feed.uninstall_provider(slot_index)
		if is_instance_valid(mounted):
			provider = mounted
	if is_instance_valid(provider):
		provider.on_unmounted_from_body(self, slot_index)
		if provider.get_parent() != self:
			provider.reparent(self, true)
	if is_instance_valid(physical_rig):
		physical_rig.refresh_attachment_mass()
	return provider


func kill(reason: String) -> void:
	if not alive:
		return
	alive = false
	last_failure_reason = reason
	if is_instance_valid(physical_rig):
		physical_rig.neutralize_commands()
	died.emit(self)


func is_body_alive() -> bool:
	if not alive or not is_instance_valid(physical_rig):
		return false
	if training_invulnerable:
		# The room coordinator can tick before this child node's _physics_process(). Restore
		# direct physical-bone damage here as well so a zero-health frame never looks like death.
		if definition != null and is_instance_valid(physical_rig.core_bone):
			if physical_rig.core_bone.current_health <= 0.0:
				physical_rig.core_bone.current_health = definition.core_maximum_health
			current_core_health = physical_rig.core_bone.current_health
		return true
	return physical_rig.get_core_health_ratio() > 0.0


func has_finite_physics_state() -> bool:
	return is_instance_valid(physical_rig) and physical_rig.has_finite_physics_state()


func stop_simulation() -> void:
	if not is_instance_valid(physical_rig):
		return
	physical_rig.neutralize_commands()
	physical_rig.set_runtime_active(false)


func core_transform() -> Transform3D:
	return physical_rig.get_core_transform() if is_instance_valid(physical_rig) else global_transform


func camera_anchor_transform() -> Transform3D:
	var transform_value = core_transform()
	return transform_value * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0))


func hardware_signature() -> String:
	return definition.hardware_signature() if definition != null else ""


func notify_limb_damage(limb_index: int) -> void:
	limb_state_changed.emit(limb_index)


func _exit_tree() -> void:
	stop_simulation()


func _build_runtime_body() -> void:
	physical_rig = FourLimbPhysicalRig3D.new()
	add_child(physical_rig)
	physical_rig.configure(self, definition)
	if is_instance_valid(physical_rig.attachment_feed):
		for slot_index: int in installed_attachments.keys():
			var provider = installed_attachments.get(slot_index) as FourLimbAttachmentStateProvider
			if is_instance_valid(provider):
				physical_rig.attachment_feed.install_provider(slot_index, provider)
	physical_rig.refresh_attachment_mass()
	physical_rig.set_runtime_active(auto_start_simulation)


func _rebuild_runtime_body() -> void:
	_detach_attachments_for_rebuild()
	if is_instance_valid(physical_rig):
		physical_rig.set_runtime_active(false)
		if physical_rig.get_parent() == self:
			remove_child(physical_rig)
		physical_rig.queue_free()
	physical_rig = null
	alive = true
	last_failure_reason = ""
	simulation_age_seconds = 0.0
	last_action_time_seconds = 0.0
	current_core_health = definition.core_maximum_health
	_build_runtime_body()


func _detach_attachments_for_rebuild() -> void:
	for slot_index: int in installed_attachments.keys():
		var provider = installed_attachments.get(slot_index) as FourLimbAttachmentStateProvider
		if is_instance_valid(provider) and provider.get_parent() != self:
			provider.reparent(self, true)
