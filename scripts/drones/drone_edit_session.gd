extends RefCounted

const SERVER_DRONE_SCENE := preload(
	"res://scenes/server/server_drone.tscn"
)
const PREVIEW_ROTATION_STEP_DEGREES := 15.0

#######################################################
# Implements the drone edit session subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

var station: Node3D
var original_drone: ServerDrone
var preview_drone: ServerDrone
var active := false

var original_state := {}
var pending_output_parts: Array[RigidBody3D] = []
var external_inputs_by_token: Dictionary = {}
var slot_tokens: Dictionary = {}
var output_count := 0


func _init(
	owner_station: Node3D,
	live_drone: ServerDrone
) -> void:
	station = owner_station
	original_drone = live_drone


func begin() -> bool:
	if (
		active
		or not is_instance_valid(station)
		or not is_instance_valid(original_drone)
		or original_drone.is_edit_preview
	):
		return false

	original_state = {
		"transform": original_drone.global_transform,
		"linear_velocity": original_drone.linear_velocity,
		"angular_velocity": original_drone.angular_velocity,
		"freeze": original_drone.freeze,
		"collision_layer": original_drone.collision_layer,
		"collision_mask": original_drone.collision_mask,
		"activated": original_drone.activated,
	}
	_initialize_slot_tokens()

	Server.release_grabs_for_body(original_drone)
	original_drone.set_edit_locked(true)
	original_drone.network_visible = false
	original_drone.freeze = true
	original_drone.collision_layer = 0
	original_drone.collision_mask = 0

	_spawn_preview(
		original_drone.loadout,
		original_drone.remaining_battery_energy_wh,
		original_drone.current_health
	)
	if preview_drone == null:
		_restore_original_runtime(true)
		return false

	active = true
	return true


func begin_from_core(
	player: ServerPlayer,
	loose_core: RigidBody3D
) -> bool:
	if (
		active
		or not is_instance_valid(station)
		or player == null
		or not is_instance_valid(loose_core)
	):
		return false

	var core: DroneCoreDefinition = loose_core.call(
		"get_drone_part_definition"
	) as DroneCoreDefinition
	if core == null:
		return false

	_initialize_slot_tokens()
	var core_token: int = int(loose_core.get("part_token_id"))
	slot_tokens["core"] = core_token
	_remember_external_input(loose_core)

	var core_health: float = float(loose_core.get("core_health"))
	var starter_loadout: DroneLoadout = DroneLoadout.new()
	starter_loadout.install_core(core)

	Server.end_grab(player.grabber)
	Server.despawn_drone_part(loose_core)
	_spawn_preview(starter_loadout, -1.0, core_health)
	if preview_drone == null:
		_restore_external_inputs()
		return false

	active = true
	return true


func _spawn_preview(
	preview_loadout: DroneLoadout,
	battery_energy_wh: float,
	core_health: float
) -> void:
	preview_drone = SERVER_DRONE_SCENE.instantiate() as ServerDrone
	preview_drone.loadout = (
		MLBodyPartContract.deep_duplicate_resource(preview_loadout) as DroneLoadout
		if preview_loadout != null
		else DroneLoadout.new()
	)
	preview_drone.starts_activated = false
	preview_drone.is_edit_preview = true
	preview_drone.edit_session = self
	station.get_parent().add_child(preview_drone)
	preview_drone.global_transform = station.call(
		"get_edit_anchor_transform"
	)
	if preview_drone.loadout.battery != null:
		preview_drone.remaining_battery_energy_wh = clampf(
			battery_energy_wh,
			0.0,
			preview_drone.loadout.battery.energy_capacity_wh
		)
	else:
		preview_drone.remaining_battery_energy_wh = 0.0
	if preview_drone.loadout.core != null:
		preview_drone.current_health = clampf(
			core_health,
			0.0,
			preview_drone.loadout.core.max_health
		)
	else:
		preview_drone.current_health = 0.0
	preview_drone.freeze = true
	preview_drone.collision_layer = 1
	preview_drone.collision_mask = 0
	preview_drone.set_edit_locked(true)


func rotate_preview(axis: Vector3, direction: float) -> void:
	if not active or not is_instance_valid(preview_drone):
		return

	var angle := (
		deg_to_rad(PREVIEW_ROTATION_STEP_DEGREES)
		* signf(direction)
	)
	preview_drone.rotate_object_local(axis.normalized(), angle)
	anchor_preview()


func reset_preview_rotation() -> void:
	if not active or not is_instance_valid(preview_drone):
		return
	var anchor_transform: Transform3D = station.call(
		"get_edit_anchor_transform"
	)
	preview_drone.global_transform = anchor_transform


func anchor_preview() -> void:
	if not active or not is_instance_valid(preview_drone):
		return
	var anchor_transform: Transform3D = station.call(
		"get_edit_anchor_transform"
	)
	preview_drone.global_position = anchor_transform.origin


func try_remove_part(
	_player: ServerPlayer,
	hit: Dictionary
) -> void:
	if not active or not is_instance_valid(preview_drone):
		return

	var slot := preview_drone.get_edit_slot_from_shape_index(
		int(hit.get("shape", -1))
	)
	if slot.is_empty():
		return

	var definition := _get_slot_definition(slot)
	if definition == null:
		return
	if not _can_remove_slot(slot):
		return

	var battery_energy := -1.0
	var core_health := -1.0
	var kind: StringName = slot.get("kind", &"")
	if kind == &"battery":
		battery_energy = preview_drone.remaining_battery_energy_wh
	elif kind == &"core":
		core_health = preview_drone.current_health

	var token := int(slot_tokens.get(_slot_key(slot), -1))
	_remove_slot(slot)
	var output := _spawn_pending_output(
		definition,
		battery_energy,
		core_health,
		token
	)
	if output != null:
		pending_output_parts.append(output)


func try_install_part(
	player: ServerPlayer,
	held_part: RigidBody3D,
	hit: Dictionary
) -> void:
	if (
		not active
		or not is_instance_valid(preview_drone)
		or not is_instance_valid(held_part)
	):
		return

	var slot := preview_drone.get_edit_slot_from_shape_index(
		int(hit.get("shape", -1))
	)
	if slot.is_empty():
		return

	var definition := held_part.call(
		"get_drone_part_definition"
	) as DronePartDefinition
	if (
		held_part.has_method("is_operational")
		and not bool(held_part.call("is_operational"))
	):
		return
	if not _definition_fits_slot(definition, slot):
		return
	if not _core_supports_current_loadout(definition, slot):
		return

	var old_definition := _get_slot_definition(slot)
	var old_battery_energy := -1.0
	var old_core_health := -1.0
	var kind: StringName = slot.get("kind", &"")
	if kind == &"battery" and old_definition != null:
		old_battery_energy = preview_drone.remaining_battery_energy_wh
	elif kind == &"core" and old_definition != null:
		old_core_health = preview_drone.current_health

	var old_token := int(slot_tokens.get(_slot_key(slot), -1))
	var new_token := int(held_part.get("part_token_id"))
	_remember_external_input(held_part)

	Server.end_grab(player.grabber)
	pending_output_parts.erase(held_part)
	var new_battery_energy := float(held_part.get("battery_energy_wh"))
	var new_core_health := float(held_part.get("core_health"))
	Server.despawn_drone_part(held_part)

	var replacement: RigidBody3D
	if old_definition != null:
		replacement = _spawn_pending_output(
			old_definition,
			old_battery_energy,
			old_core_health,
			old_token
		)
		if replacement != null:
			pending_output_parts.append(replacement)

	_install_slot(
		slot,
		definition,
		new_battery_energy,
		new_core_health
	)
	slot_tokens[_slot_key(slot)] = new_token

	if replacement != null:
		replacement.global_position = player.grabber.get_grab_target(
			1.6,
			0.0
		)
		replacement.linear_velocity = Vector3.ZERO
		replacement.angular_velocity = Vector3.ZERO
		Server.grab_body_directly(player.grabber, replacement)


func accept() -> void:
	if not active:
		return

	if (
		is_instance_valid(original_drone)
		and is_instance_valid(preview_drone)
	):
		original_drone.replace_loadout(
			preview_drone.loadout,
			preview_drone.remaining_battery_energy_wh,
			preview_drone.current_health
		)
		original_drone.global_transform = preview_drone.global_transform
		_restore_original_runtime(false)
	elif is_instance_valid(preview_drone):
		var assembled: ServerDrone = _create_assembled_drone()
		if assembled == null:
			return
		original_drone = assembled

	_finish()


func abort() -> void:
	if not active:
		return

	for part in pending_output_parts.duplicate():
		if is_instance_valid(part):
			Server.despawn_drone_part(part)
	pending_output_parts.clear()

	_restore_external_inputs()

	if is_instance_valid(original_drone):
		original_drone.global_transform = original_state.get(
			"transform",
			original_drone.global_transform
		)
		_restore_original_runtime(true)

	_finish()


func _create_assembled_drone() -> ServerDrone:
	if not is_instance_valid(preview_drone):
		return null

	var assembled: ServerDrone = (
		SERVER_DRONE_SCENE.instantiate() as ServerDrone
	)
	if assembled == null:
		return null
	assembled.loadout = MLBodyPartContract.deep_duplicate_resource(preview_drone.loadout) as DroneLoadout
	assembled.starts_activated = false
	assembled.freeze = true
	station.get_parent().add_child(assembled)
	assembled.global_transform = preview_drone.global_transform
	assembled.replace_loadout(
		preview_drone.loadout,
		preview_drone.remaining_battery_energy_wh,
		preview_drone.current_health
	)
	assembled.linear_velocity = Vector3.ZERO
	assembled.angular_velocity = Vector3.ZERO
	assembled.freeze = false
	assembled.set_activated(false)
	return assembled


func _restore_external_inputs() -> void:
	for record: Dictionary in external_inputs_by_token.values():
		var restored: RigidBody3D = Server.spawn_drone_part(
			record.get("definition") as DronePartDefinition,
			record.get("transform", Transform3D.IDENTITY),
			float(record.get("battery_energy_wh", -1.0)),
			float(record.get("core_health", -1.0)),
			int(record.get("part_token_id", -1))
		)
		if restored != null:
			restored.linear_velocity = record.get(
				"linear_velocity",
				Vector3.ZERO
			)
			restored.angular_velocity = record.get(
				"angular_velocity",
				Vector3.ZERO
			)
	external_inputs_by_token.clear()


func _restore_original_runtime(restore_motion: bool) -> void:
	original_drone.network_visible = true
	original_drone.collision_layer = int(
		original_state.get("collision_layer", 1)
	)
	original_drone.collision_mask = int(
		original_state.get("collision_mask", 1)
	)
	original_drone.freeze = bool(original_state.get("freeze", false))
	original_drone.set_edit_locked(false)

	if restore_motion:
		original_drone.linear_velocity = original_state.get(
			"linear_velocity",
			Vector3.ZERO
		)
		original_drone.angular_velocity = original_state.get(
			"angular_velocity",
			Vector3.ZERO
		)
		original_drone.set_activated(
			bool(original_state.get("activated", false))
		)
	else:
		original_drone.linear_velocity = Vector3.ZERO
		original_drone.angular_velocity = Vector3.ZERO
		original_drone.set_activated(false)


func _finish() -> void:
	active = false
	if is_instance_valid(preview_drone):
		preview_drone.edit_session = null
		preview_drone.queue_free()
	preview_drone = null

	if is_instance_valid(station):
		station.call("finish_edit_session", original_drone)


func _get_slot_definition(slot: Dictionary) -> DronePartDefinition:
	if preview_drone.loadout == null:
		return null

	var kind: StringName = slot.get("kind", &"")
	match kind:
		&"core":
			return preview_drone.loadout.core
		&"battery":
			return preview_drone.loadout.battery
		&"propeller":
			return preview_drone.loadout.get_propeller(
				int(slot.get("index", -1))
			)
		&"ai_chip":
			return preview_drone.loadout.get_ai_chip(
				int(slot.get("index", -1))
			)
		&"attachment":
			return preview_drone.loadout.get_attachment(
				int(slot.get("index", -1))
			)
	return null


func _remove_slot(slot: Dictionary) -> void:
	match slot.get("kind", &""):
		&"core":
			preview_drone.remove_core()
		&"battery":
			preview_drone.remove_battery()
		&"propeller":
			preview_drone.remove_propeller(
				int(slot.get("index", -1))
			)
		&"ai_chip":
			preview_drone.remove_ai_chip(
				int(slot.get("index", -1))
			)
		&"attachment":
			preview_drone.remove_attachment(
				int(slot.get("index", -1))
			)
	slot_tokens[_slot_key(slot)] = -1


func _install_slot(
	slot: Dictionary,
	definition: DronePartDefinition,
	battery_energy_wh: float,
	core_health: float
) -> void:
	match slot.get("kind", &""):
		&"core":
			preview_drone.install_core(definition as DroneCoreDefinition)
			preview_drone.current_health = clampf(
				core_health,
				0.0,
				(definition as DroneCoreDefinition).max_health
			)
		&"battery":
			preview_drone.install_battery_with_energy(
				definition as DroneBatteryDefinition,
				battery_energy_wh
			)
		&"propeller":
			preview_drone.install_propeller(
				int(slot.get("index", -1)),
				definition as DronePropellerDefinition
			)
		&"ai_chip":
			preview_drone.install_ai_chip(
				int(slot.get("index", -1)),
				definition as DroneAIChipDefinition
			)
		&"attachment":
			preview_drone.install_attachment(
				int(slot.get("index", -1)),
				definition as DroneAttachmentDefinition
			)


func _definition_fits_slot(
	definition: DronePartDefinition,
	slot: Dictionary
) -> bool:
	if definition == null:
		return false

	match slot.get("kind", &""):
		&"core":
			return definition is DroneCoreDefinition
		&"battery":
			return definition is DroneBatteryDefinition
		&"propeller":
			return definition is DronePropellerDefinition
		&"ai_chip":
			return definition is DroneAIChipDefinition
		&"attachment":
			return definition is DroneAttachmentDefinition
	return false


func _core_supports_current_loadout(
	definition: DronePartDefinition,
	slot: Dictionary
) -> bool:
	if slot.get("kind", &"") != &"core":
		return true

	var core := definition as DroneCoreDefinition
	if core == null or preview_drone.loadout == null:
		return false
	for slot_index in range(
		core.propeller_slot_count,
		preview_drone.loadout.propellers.size()
	):
		if preview_drone.loadout.propellers[slot_index] != null:
			return false
	for slot_index in range(
		core.ai_chip_slot_count,
		preview_drone.loadout.ai_chips.size()
	):
		if preview_drone.loadout.ai_chips[slot_index] != null:
			return false
	for slot_index in range(
		core.attachment_slot_count,
		preview_drone.loadout.attachments.size()
	):
		if preview_drone.loadout.attachments[slot_index] != null:
			return false
	return true


func _can_remove_slot(slot: Dictionary) -> bool:
	if slot.get("kind", &"") != &"core":
		return true
	if preview_drone.loadout == null:
		return true
	for chip in preview_drone.loadout.ai_chips:
		if chip != null:
			return false
	for attachment in preview_drone.loadout.attachments:
		if attachment != null:
			return false
	return true


func _spawn_pending_output(
	definition: DronePartDefinition,
	battery_energy_wh: float,
	core_health: float,
	part_token_id: int
) -> RigidBody3D:
	var output_transform: Transform3D = station.call(
		"get_part_output_transform",
		output_count
	)
	output_count += 1
	return Server.spawn_drone_part(
		definition,
		output_transform,
		battery_energy_wh,
		core_health,
		part_token_id
	)


func _remember_external_input(part: RigidBody3D) -> void:
	if pending_output_parts.has(part):
		return

	var token := int(part.get("part_token_id"))
	if external_inputs_by_token.has(token):
		return

	external_inputs_by_token[token] = {
		"definition": part.call("get_drone_part_definition"),
		"transform": part.global_transform,
		"linear_velocity": part.linear_velocity,
		"angular_velocity": part.angular_velocity,
		"battery_energy_wh": float(part.get("battery_energy_wh")),
		"core_health": float(part.get("core_health")),
		"part_token_id": token,
	}


func _initialize_slot_tokens() -> void:
	slot_tokens = {
		"core": -1,
		"battery": -1,
		"propeller:0": -1,
		"propeller:1": -1,
		"propeller:2": -1,
		"propeller:3": -1,
	}
	for slot_index in range(8):
		slot_tokens["ai_chip:%d" % slot_index] = -1
	for slot_index in range(4):
		slot_tokens["attachment:%d" % slot_index] = -1


func _slot_key(slot: Dictionary) -> String:
	var kind: StringName = slot.get("kind", &"")
	if kind in [&"propeller", &"ai_chip", &"attachment"]:
		return "%s:%d" % [String(kind), int(slot.get("index", -1))]
	return String(kind)
