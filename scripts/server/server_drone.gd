class_name ServerDrone
extends RigidBody3D

const SLOT_LAYOUT := preload(
	"res://scripts/drones/drone_slot_layout.gd"
)
const AI_GROUND_PROBE_DISTANCE := 12.0
const MAX_PROPELLER_SLOTS := 4
const DEFAULT_CORE_SIZE := Vector3(0.65, 0.24, 0.65)
const DEFAULT_BATTERY_SIZE := Vector3(0.35, 0.12, 0.26)
const DEFAULT_PROPELLER_RADIUS := 0.18
const DEFAULT_PROPELLER_COLLISION_HEIGHT := 0.1
const DEFAULT_AI_CHIP_SIZE := Vector3(0.2, 0.035, 0.15)
const DEFAULT_ATTACHMENT_SIZE := Vector3(0.24, 0.15, 0.3)
const BOX_INERTIA_DIVISOR := 12.0
const DISC_DIAMETER_INERTIA_FACTOR := 0.25
const DISC_AXIS_INERTIA_FACTOR := 0.5
const RANDOM_SEED_BASE := 9187
const DRONE_RANDOM_SEED_FACTOR := 7919
const MIN_POWER_REQUEST := 0.001
const ML_GROUND_EFFECT_RAYS_PER_PHYSICS_TICK := 1

#######################################################
# Simulates an authoritative modular drone, including power, flight, weapons, attachments,
# editing, and replication.
#######################################################

@export var loadout: DroneLoadout
@export var starts_activated := false
@export var is_edit_preview := false
@export var faction_id := 0

var drone_id := -1
var activated := false
var current_health := 0.0
var current_power_output := 0.0
var current_bus_voltage_v := 0.0
var power_spool_ratio := 0.0
var remaining_battery_energy_wh := 0.0
var ml_episode_unlimited_battery := false
var ml_training_performance_mode := false
var ml_training_paused: bool = false
var ml_training_pause_restore_freeze: bool = false
var ml_training_pause_restore_sleeping: bool = false
var ml_training_pause_linear_velocity: Vector3 = Vector3.ZERO
var ml_training_pause_angular_velocity: Vector3 = Vector3.ZERO

var battery_fluctuation_phase := 0.0
var core_fluctuation_phase := 0.0
var battery_spike_time_remaining := 0.0
var battery_spike_multiplier := 1.0
var power_rng := RandomNumberGenerator.new()

var edit_locked := false
var network_visible := true
var edit_session: RefCounted

var air_environment: AirEnvironment
var propeller_slots: Array[DronePropellerSlot] = []
var ai_controller: DroneAIController
var flight_controller: DroneFlightController
var ml_controller: DroneMLController
var obstacle_avoidance: DroneObstacleAvoidance
var ai_motor_thrust_targets: Array[float] = [0.0, 0.0, 0.0, 0.0]
var last_propeller_requested_power_w: Array[float] = []
var last_propeller_applied_power_w: Array[float] = []
var last_propeller_realized_thrust_n: Array[float] = []
var requested_power_workspace: Array[float] = []
var propeller_disk_area_by_slot: Array[float] = []
var propeller_efficiency_by_slot: Array[float] = []
var propeller_max_power_by_slot: Array[float] = []
var propeller_reaction_torque_by_slot: Array[float] = []
var propeller_axial_response_by_slot: Array[float] = []
var propeller_minimum_axial_factor_by_slot: Array[float] = []
var propeller_maximum_axial_factor_by_slot: Array[float] = []
var cached_ground_effect_by_slot: Array[float] = []
var cached_ai_collision_radius := 0.72
var cached_spool_up_response := 1.0
var cached_spool_down_response := 1.0
var cached_drag_area := 0.0
var cached_drag_coefficient := 0.0
var cached_angular_drag_coefficient := 0.0
var deterministic_power_output_cache := false
var deterministic_bus_voltage_v := 0.0
var deterministic_forwarded_power_w := 0.0
var has_installed_attachments_cache := false
var ground_effect_refresh_cursor := 0
var ground_effect_cache_initialized := false
var ml_degraded_propeller_slots: Dictionary[int, bool] = {}
var ai_fire_requested := false
var ai_combat_target_id := -1
var ai_combat_target_kind := &""
var ai_combat_target_position := Vector3.ZERO
var ai_avoidance_neighbor_count := 0
var powered_weapon_slots: Array[int] = []
var weapon_cooldowns_by_slot: Dictionary[int, float] = {}
var weapon_aim_local_by_slot: Dictionary[int, Vector3] = {}
var camera_attachment_nodes_by_slot: Dictionary[int, Camera3D] = {}
var limb_attachment_assemblies_by_slot: Dictionary[int, GenericLimbAssembly3D] = {}
var core_camera_part_definition: DroneCameraAttachmentDefinition
var ml_body_interface_manifest: MLBodyInterfaceManifest


func _ready() -> void:
	if loadout != null:
		loadout = MLBodyPartContract.deep_duplicate_resource(loadout) as DroneLoadout

	ai_controller = DroneAIController.new(self)
	flight_controller = DroneFlightController.new(self)
	ml_controller = DroneMLController.new(self)
	obstacle_avoidance = DroneObstacleAvoidance.new(self)
	_collect_propeller_slots()
	_apply_loadout(true, true)
	activated = starts_activated and not is_edit_preview
	if is_edit_preview:
		edit_locked = true
		freeze = true

	air_environment = get_tree().get_first_node_in_group(
		"air_environment"
	) as AirEnvironment
	if air_environment == null:
		push_error("ServerDrone requires an AirEnvironment in the server world")

	drone_id = Server.register_drone(self)
	power_rng.seed = (
		RANDOM_SEED_BASE
		+ drone_id * DRONE_RANDOM_SEED_FACTOR
	)
	_refresh_part_collisions()
	_refresh_spatial_interest()


func _exit_tree() -> void:
	if drone_id != -1:
		Server.unregister_drone(drone_id)


func _collect_propeller_slots() -> void:
	propeller_slots.clear()
	for child in $PropellerSlots.get_children():
		if child is DronePropellerSlot:
			propeller_slots.append(child as DronePropellerSlot)

	propeller_slots.sort_custom(
		func(a: DronePropellerSlot, b: DronePropellerSlot) -> bool:
			return a.slot_index < b.slot_index
	)

	$CoreCollision.set_meta("edit_slot_kind", &"core")
	$CoreCollision.set_meta("edit_slot_index", -1)
	$BatteryCollision.set_meta("edit_slot_kind", &"battery")
	$BatteryCollision.set_meta("edit_slot_index", -1)
	for slot_index in range(MAX_PROPELLER_SLOTS):
		var collision := get_node_or_null(
			"Propeller%dCollision" % slot_index
		) as CollisionShape3D
		if collision != null:
			collision.set_meta("edit_slot_kind", &"propeller")
			collision.set_meta("edit_slot_index", slot_index)

	for slot_index in range(SLOT_LAYOUT.MAX_AI_CHIP_SLOTS):
		var chip_collision := get_node_or_null(
			"AIChip%dCollision" % slot_index
		) as CollisionShape3D
		if chip_collision != null:
			chip_collision.set_meta("edit_slot_kind", &"ai_chip")
			chip_collision.set_meta("edit_slot_index", slot_index)

	for slot_index in range(SLOT_LAYOUT.MAX_ATTACHMENT_SLOTS):
		var attachment_collision := get_node_or_null(
			"Attachment%dCollision" % slot_index
		) as CollisionShape3D
		if attachment_collision != null:
			attachment_collision.set_meta("edit_slot_kind", &"attachment")
			attachment_collision.set_meta("edit_slot_index", slot_index)


func _apply_loadout(
	reset_health := false,
	reset_battery := false
) -> void:
	if loadout == null or loadout.core == null:
		mass = (
			loadout.get_total_mass()
			if loadout != null
			else 0.1
		)
		inertia = Vector3.ZERO
		current_health = 0.0
		activated = false
		if loadout == null or loadout.battery == null:
			remaining_battery_energy_wh = 0.0
		elif reset_battery:
			remaining_battery_energy_wh = loadout.battery.energy_capacity_wh
		else:
			remaining_battery_energy_wh = minf(
				remaining_battery_energy_wh,
				loadout.battery.energy_capacity_wh
			)
		_refresh_part_collisions()
		_refresh_model_body_interface()
		_refresh_propeller_runtime_cache()
		if ai_controller != null:
			ai_controller.synchronize(loadout)
		_refresh_spatial_interest()
		sleeping = false
		return

	mass = loadout.get_total_mass()
	inertia = _calculate_loadout_inertia()
	if reset_health:
		current_health = loadout.core.max_health
	else:
		current_health = minf(current_health, loadout.core.max_health)

	if loadout.battery == null:
		remaining_battery_energy_wh = 0.0
		activated = false
	elif reset_battery:
		remaining_battery_energy_wh = loadout.battery.energy_capacity_wh
	else:
		remaining_battery_energy_wh = minf(
			remaining_battery_energy_wh,
			loadout.battery.energy_capacity_wh
		)
	_refresh_part_collisions()
	_refresh_model_body_interface()
	_refresh_propeller_runtime_cache()
	if ai_controller != null:
		ai_controller.synchronize(loadout)
	_refresh_spatial_interest()
	sleeping = false


func install_core(core: DroneCoreDefinition) -> void:
	if loadout == null:
		loadout = DroneLoadout.new()

	loadout.install_core(core)
	_apply_loadout(true, false)


func remove_core() -> void:
	if loadout == null:
		return

	loadout.remove_core()
	_apply_loadout(false, false)


func install_battery(battery: DroneBatteryDefinition) -> void:
	if loadout == null:
		loadout = DroneLoadout.new()

	loadout.install_battery(battery)
	battery_spike_time_remaining = 0.0
	battery_spike_multiplier = 1.0
	_apply_loadout(false, true)


func install_battery_with_energy(
	battery: DroneBatteryDefinition,
	energy_wh: float
) -> void:
	install_battery(battery)
	remaining_battery_energy_wh = clampf(
		energy_wh,
		0.0,
		battery.energy_capacity_wh
	)


func remove_battery() -> void:
	if loadout == null:
		return

	loadout.remove_battery()
	current_power_output = 0.0
	power_spool_ratio = 0.0
	_apply_loadout(false, false)


func install_propeller(
	slot_index: int,
	propeller: DronePropellerDefinition
) -> bool:
	if (
		loadout == null
		or slot_index < 0
		or slot_index >= propeller_slots.size()
	):
		return false

	var installed := loadout.install_propeller(slot_index, propeller)
	if installed:
		_apply_loadout()
	return installed


func _propeller_array_index_for_slot(slot_index: int) -> int:
	for array_index: int in range(propeller_slots.size()):
		if propeller_slots[array_index].slot_index == slot_index:
			return array_index
	return -1


func set_ml_propeller_degraded(slot_index: int, degraded: bool) -> bool:
	# Slot ids are part of the body contract; do not assume they are the same thing as the runtime
	# array index. Creator-authored layouts may eventually reorder/sparsify physical slot ids.
	var array_index: int = _propeller_array_index_for_slot(slot_index)
	if slot_index < 0 or array_index < 0:
		return false
	if degraded:
		ml_degraded_propeller_slots[slot_index] = true
		if array_index >= 0 and array_index < ai_motor_thrust_targets.size():
			ai_motor_thrust_targets[array_index] = 0.0
		if array_index >= 0 and array_index < last_propeller_requested_power_w.size():
			last_propeller_requested_power_w[array_index] = 0.0
		if array_index >= 0 and array_index < last_propeller_applied_power_w.size():
			last_propeller_applied_power_w[array_index] = 0.0
		if array_index >= 0 and array_index < last_propeller_realized_thrust_n.size():
			last_propeller_realized_thrust_n[array_index] = 0.0
	else:
		ml_degraded_propeller_slots.erase(slot_index)
	return true


func is_ml_propeller_degraded(slot_index: int) -> bool:
	return bool(ml_degraded_propeller_slots.get(slot_index, false))


func clear_ml_propeller_degradation() -> void:
	ml_degraded_propeller_slots.clear()


func remove_propeller(slot_index: int) -> void:
	if loadout == null:
		return

	loadout.remove_propeller(slot_index)
	_apply_loadout()


func install_ai_chip(
	slot_index: int,
	chip: DroneAIChipDefinition
) -> bool:
	if loadout == null:
		return false
	var installed := loadout.install_ai_chip(slot_index, chip)
	if installed:
		_apply_loadout()
	return installed


func remove_ai_chip(slot_index: int) -> void:
	if loadout == null:
		return
	loadout.remove_ai_chip(slot_index)
	_apply_loadout()


func install_attachment(
	slot_index: int,
	attachment: DroneAttachmentDefinition
) -> bool:
	if loadout == null:
		return false
	var installed := loadout.install_attachment(slot_index, attachment)
	if installed:
		_apply_loadout()
	return installed


func remove_attachment(slot_index: int) -> void:
	if loadout == null:
		return
	loadout.remove_attachment(slot_index)
	_apply_loadout()


func replace_loadout(
	new_loadout: DroneLoadout,
	battery_energy_wh: float,
	core_health: float
) -> void:
	loadout = (
		MLBodyPartContract.deep_duplicate_resource(new_loadout) as DroneLoadout
		if new_loadout != null
		else DroneLoadout.new()
	)
	_apply_loadout(false, false)

	if loadout.battery != null:
		remaining_battery_energy_wh = clampf(
			battery_energy_wh,
			0.0,
			loadout.battery.energy_capacity_wh
		)
	if loadout.core != null:
		current_health = clampf(
			core_health,
			0.0,
			loadout.core.max_health
		)
	_refresh_part_collisions()
	_refresh_model_body_interface()


func _refresh_model_body_interface() -> void:
	ml_body_interface_manifest = DroneMLBodyInterfaceFactory.finalize_loadout(loadout)


func model_body_interface() -> MLBodyInterfaceManifest:
	if ml_body_interface_manifest == null and loadout != null and loadout.core != null:
		_refresh_model_body_interface()
	return ml_body_interface_manifest


func model_body_control_count() -> int:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	return manifest.control_count() if manifest != null else 0


func model_body_observation_features() -> PackedFloat64Array:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	if manifest == null:
		return PackedFloat64Array()
	return manifest.encode_body_observation(
		DroneMLBodyInterfaceFactory.runtime_states(self),
		DroneMLBodyInterfaceFactory.host_state(self)
	)


func model_body_contract_signature() -> String:
	var manifest: MLBodyInterfaceManifest = model_body_interface()
	return manifest.contract_signature if manifest != null else ""


func can_submit_model_core_commands(command_count: int) -> bool:
	if loadout == null or loadout.core == null or command_count < 0:
		return false
	if MLBodyPartContract.control_descriptors(loadout.core).size() != command_count:
		return false
	var runtime_node: Node = get_node_or_null("ModelCoreRuntime")
	if runtime_node == null or not runtime_node.has_method("submit_model_commands"):
		return command_count == 0
	if runtime_node.has_method("model_control_count"):
		return int(runtime_node.call("model_control_count")) == command_count
	return true


func submit_model_core_commands(commands: PackedFloat64Array) -> bool:
	if loadout == null or loadout.core == null:
		return commands.is_empty()
	var runtime_node: Node = get_node_or_null("ModelCoreRuntime")
	if runtime_node != null and runtime_node.has_method("submit_model_commands"):
		return bool(runtime_node.call("submit_model_commands", commands))
	return commands.is_empty()


func can_submit_model_attachment_slot_commands(slot_index: int, command_count: int) -> bool:
	if loadout == null or command_count < 0:
		return false
	var attachment: DroneAttachmentDefinition = loadout.get_attachment(slot_index)
	if attachment == null:
		return command_count == 0
	if MLBodyPartContract.control_descriptors(attachment).size() != command_count:
		return false
	if attachment is DroneLimbAttachmentDefinition:
		var assembly: GenericLimbAssembly3D = limb_attachment_assemblies_by_slot.get(slot_index) as GenericLimbAssembly3D
		return is_instance_valid(assembly) and assembly.can_submit_commands(command_count)
	var runtime_node: Node = get_node_or_null("ModelAttachmentRuntime%d" % slot_index)
	if runtime_node == null or not runtime_node.has_method("submit_model_commands"):
		return command_count == 0
	if runtime_node.has_method("model_control_count"):
		return int(runtime_node.call("model_control_count")) == command_count
	return true


func submit_model_attachment_slot_commands(
	slot_index: int,
	commands: PackedFloat64Array
) -> bool:
	if loadout == null:
		return false
	var attachment: DroneAttachmentDefinition = loadout.get_attachment(slot_index)
	if attachment == null:
		return commands.is_empty()
	if attachment is DroneLimbAttachmentDefinition:
		var assembly: GenericLimbAssembly3D = limb_attachment_assemblies_by_slot.get(slot_index) as GenericLimbAssembly3D
		return is_instance_valid(assembly) and assembly.submit_commands(commands)
	# Future powered tools/guns can declare controls only once their runtime attachment implements
	# this generic command hook. Fail closed instead of silently dropping declared model outputs.
	var runtime_node: Node = get_node_or_null("ModelAttachmentRuntime%d" % slot_index)
	if runtime_node != null and runtime_node.has_method("submit_model_commands"):
		return bool(runtime_node.call("submit_model_commands", commands))
	return commands.is_empty()


func model_attachment_state_for_slot(slot_index: int) -> Dictionary:
	var runtime_node: Node = get_node_or_null("ModelAttachmentRuntime%d" % slot_index)
	if runtime_node != null and runtime_node.has_method("model_state_snapshot"):
		var value: Variant = runtime_node.call("model_state_snapshot")
		return value if value is Dictionary else {}
	return {}


func set_edit_locked(value: bool) -> void:
	edit_locked = value
	if edit_locked:
		set_activated(false)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func get_edit_slot_from_shape_index(shape_index: int) -> Dictionary:
	if shape_index < 0:
		return {}

	var owner_id := shape_find_owner(shape_index)
	var owner := shape_owner_get_owner(owner_id) as Node
	if owner == null or not owner.has_meta("edit_slot_kind"):
		return {}

	return {
		"kind": owner.get_meta("edit_slot_kind"),
		"index": int(owner.get_meta("edit_slot_index", -1)),
		"node": owner,
	}


func get_edit_slot_transform(slot: Dictionary) -> Transform3D:
	var slot_node := slot.get("node") as Node3D
	if slot_node != null:
		return slot_node.global_transform
	return global_transform


func _refresh_part_collisions() -> void:
	if not has_node("CoreCollision"):
		return

	var has_core := loadout != null and loadout.core != null
	var core_size := _refresh_main_part_collisions(has_core)
	_refresh_propeller_collisions()
	_refresh_ai_chip_collisions(core_size, has_core)
	_refresh_attachment_collisions(core_size, has_core)
	_refresh_camera_attachment_nodes()
	_refresh_limb_attachment_nodes()


func _refresh_main_part_collisions(has_core: bool) -> Vector3:
	var has_battery := loadout != null and loadout.battery != null
	var core_size = loadout.core.body_size if has_core else DEFAULT_CORE_SIZE
	var core_shape := BoxShape3D.new()
	core_shape.size = core_size
	$CoreCollision.shape = core_shape
	var battery_size = (
		loadout.battery.body_size
		if has_battery
		else DEFAULT_BATTERY_SIZE
	)
	var battery_shape := BoxShape3D.new()
	battery_shape.size = battery_size
	$BatteryCollision.shape = battery_shape
	var battery_position := Vector3(
		0.0,
		core_size.y * 0.5 + battery_size.y * 0.5,
		0.0
	)
	$BatterySocket.position = battery_position
	$BatteryCollision.position = battery_position
	$CoreCollision.disabled = not is_edit_preview and not has_core
	$BatteryCollision.disabled = not is_edit_preview and not has_battery
	$ArmCollisionA.disabled = is_edit_preview
	$ArmCollisionB.disabled = is_edit_preview
	return core_size


func _refresh_propeller_collisions() -> void:
	for slot_index in range(MAX_PROPELLER_SLOTS):
		var collision := get_node_or_null(
			"Propeller%dCollision" % slot_index
		) as CollisionShape3D
		if collision == null:
			continue
		var has_propeller := (
			loadout != null
			and loadout.get_propeller(slot_index) != null
		)
		var propeller: DronePropellerDefinition = (
			loadout.get_propeller(slot_index)
			if loadout != null
			else null
		)
		var propeller_shape := CylinderShape3D.new()
		propeller_shape.radius = (
			propeller.rotor_radius
			if propeller != null
			else DEFAULT_PROPELLER_RADIUS
		)
		propeller_shape.height = DEFAULT_PROPELLER_COLLISION_HEIGHT
		collision.shape = propeller_shape
		collision.disabled = not is_edit_preview and not has_propeller


func _refresh_ai_chip_collisions(
	core_size: Vector3,
	has_core: bool
) -> void:
	for slot_index in range(SLOT_LAYOUT.MAX_AI_CHIP_SLOTS):
		var chip_collision := get_node_or_null(
			"AIChip%dCollision" % slot_index
		) as CollisionShape3D
		if chip_collision == null:
			continue
		chip_collision.position = SLOT_LAYOUT.get_ai_chip_position(
			slot_index,
			core_size
		)
		var chip := (
			loadout.get_ai_chip(slot_index)
			if loadout != null
			else null
		)
		var chip_shape := BoxShape3D.new()
		chip_shape.size = (
			chip.body_size
			if chip != null
			else DEFAULT_AI_CHIP_SIZE
		)
		chip_collision.shape = chip_shape
		var chip_supported := (
			has_core and slot_index < loadout.core.ai_chip_slot_count
		)
		chip_collision.disabled = (
			not chip_supported
			or (not is_edit_preview and chip == null)
		)


func _refresh_attachment_collisions(
	core_size: Vector3,
	has_core: bool
) -> void:
	for slot_index in range(SLOT_LAYOUT.MAX_ATTACHMENT_SLOTS):
		var attachment_collision := get_node_or_null(
			"Attachment%dCollision" % slot_index
		) as CollisionShape3D
		if attachment_collision == null:
			continue
		attachment_collision.position = SLOT_LAYOUT.get_attachment_position(
			slot_index,
			core_size
		)
		var attachment := (
			loadout.get_attachment(slot_index)
			if loadout != null
			else null
		)
		var is_camera_attachment := attachment is DroneCameraAttachmentDefinition
		var attachment_shape := BoxShape3D.new()
		attachment_shape.size = (
			attachment.body_size
			if attachment != null
			else DEFAULT_ATTACHMENT_SIZE
		)
		attachment_collision.shape = attachment_shape
		var attachment_supported := (
			has_core and slot_index < loadout.core.attachment_slot_count
		)
		attachment_collision.disabled = (
			not attachment_supported
			or is_camera_attachment
			or (not is_edit_preview and attachment == null)
		)


func _refresh_limb_attachment_nodes() -> void:
	for node_value: Variant in limb_attachment_assemblies_by_slot.values():
		var old_assembly := node_value as GenericLimbAssembly3D
		if is_instance_valid(old_assembly):
			old_assembly.queue_free()
	limb_attachment_assemblies_by_slot.clear()
	if loadout == null or loadout.core == null:
		return
	for slot_index in range(loadout.core.attachment_slot_count):
		var definition := loadout.get_attachment(slot_index) as DroneLimbAttachmentDefinition
		if definition == null:
			continue
		var slot_offset := SLOT_LAYOUT.get_attachment_position(
			slot_index,
			loadout.core.body_size
		)
		var mounted_definitions := definition.mounted_limb_definitions(slot_offset)
		if mounted_definitions.is_empty():
			continue
		var assembly := GenericLimbAssembly3D.new()
		assembly.name = "DroneLimbAssembly%d" % slot_index
		add_child(assembly)
		assembly.configure(
			self,
			mounted_definitions,
			self,
			definition.limb_collision_layer,
			definition.limb_collision_mask,
			definition.exclude_self_collision
		)
		assembly.set_runtime_active(not is_edit_preview)
		limb_attachment_assemblies_by_slot[slot_index] = assembly
	_configure_limb_attachment_collision_exceptions()


func _configure_limb_attachment_collision_exceptions() -> void:
	# A drone may install more than one limb-host attachment. Treat all opt-in assemblies as one
	# articulated body for collision filtering so limbs on separate slots cannot self-jam.
	var bodies: Array[PhysicsBody3D] = []
	bodies.append(self)
	for value: Variant in limb_attachment_assemblies_by_slot.values():
		var assembly := value as GenericLimbAssembly3D
		if not is_instance_valid(assembly) or not assembly.exclude_self_collision:
			continue
		for limb: GenericLimb3D in assembly.limbs:
			if not is_instance_valid(limb):
				continue
			for segment: LimbSegment3D in limb.segments:
				if is_instance_valid(segment):
					bodies.append(segment)
	for first_index in range(bodies.size()):
		for second_index in range(first_index + 1, bodies.size()):
			bodies[first_index].add_collision_exception_with(bodies[second_index])
			bodies[second_index].add_collision_exception_with(bodies[first_index])


func get_limb_attachment_assembly(slot_index: int) -> GenericLimbAssembly3D:
	return limb_attachment_assemblies_by_slot.get(slot_index) as GenericLimbAssembly3D


func limb_attachment_action_count(slot_index: int) -> int:
	var assembly := get_limb_attachment_assembly(slot_index)
	return assembly.required_action_count() if is_instance_valid(assembly) else 0


func submit_limb_attachment_commands(
	slot_index: int,
	commands: PackedFloat64Array
) -> bool:
	var assembly := get_limb_attachment_assembly(slot_index)
	return is_instance_valid(assembly) and assembly.submit_commands(commands)


func limb_attachment_state(slot_index: int) -> Dictionary:
	var assembly := get_limb_attachment_assembly(slot_index)
	return assembly.state_snapshot() if is_instance_valid(assembly) else {}


func limb_attachment_slots() -> PackedInt32Array:
	var result := PackedInt32Array()
	var slots: Array[int] = []
	for slot_value: Variant in limb_attachment_assemblies_by_slot.keys():
		slots.append(int(slot_value))
	slots.sort()
	for slot_index: int in slots:
		result.append(slot_index)
	return result


func total_limb_attachment_action_count() -> int:
	var result := 0
	for slot_index: int in limb_attachment_slots():
		result += limb_attachment_action_count(slot_index)
	return result


func submit_all_limb_attachment_commands(commands: PackedFloat64Array) -> bool:
	if commands.size() != total_limb_attachment_action_count():
		return false
	var cursor := 0
	for slot_index: int in limb_attachment_slots():
		var local_count := limb_attachment_action_count(slot_index)
		var local_commands := PackedFloat64Array()
		local_commands.resize(local_count)
		for local_index in range(local_count):
			local_commands[local_index] = commands[cursor + local_index]
		if not submit_limb_attachment_commands(slot_index, local_commands):
			return false
		cursor += local_count
	return true


func all_limb_attachment_states() -> Dictionary:
	var result: Dictionary[int, Dictionary] = {}
	for slot_index: int in limb_attachment_slots():
		result[slot_index] = limb_attachment_state(slot_index)
	return result


func set_limb_attachments_runtime_active(
	value: bool,
	release_grip_on_deactivate: bool = true
) -> void:
	for assembly_value: Variant in limb_attachment_assemblies_by_slot.values():
		var assembly = assembly_value as GenericLimbAssembly3D
		if is_instance_valid(assembly):
			assembly.set_runtime_active(value, release_grip_on_deactivate)


func holds_instance_id(instance_id: int) -> bool:
	if instance_id <= 0:
		return false
	for assembly_value: Variant in limb_attachment_assemblies_by_slot.values():
		var assembly: GenericLimbAssembly3D = assembly_value as GenericLimbAssembly3D
		if is_instance_valid(assembly) and assembly.holds_instance_id(instance_id):
			return true
	return false


func release_limb_attachment_grips() -> void:
	for assembly_value: Variant in limb_attachment_assemblies_by_slot.values():
		var assembly = assembly_value as GenericLimbAssembly3D
		if is_instance_valid(assembly):
			assembly.release_grips()


func reset_limb_attachments_to_rest() -> void:
	for assembly_value: Variant in limb_attachment_assemblies_by_slot.values():
		var assembly = assembly_value as GenericLimbAssembly3D
		if is_instance_valid(assembly):
			assembly.reset_to_rest()


func _refresh_camera_attachment_nodes() -> void:
	for node_value: Variant in camera_attachment_nodes_by_slot.values():
		var old_camera := node_value as Camera3D
		if is_instance_valid(old_camera):
			if old_camera.get_parent() == self:
				remove_child(old_camera)
			old_camera.queue_free()
	camera_attachment_nodes_by_slot.clear()
	if loadout == null or loadout.core == null:
		return
	for slot_index in range(loadout.core.attachment_slot_count):
		var definition := loadout.get_attachment(slot_index) as DroneCameraAttachmentDefinition
		if definition != null:
			_create_camera_attachment_node(slot_index, definition)
	if core_camera_part_definition != null:
		_create_camera_attachment_node(-1, core_camera_part_definition)


func _create_camera_attachment_node(
	slot_index: int,
	definition: DroneCameraAttachmentDefinition
) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = (
		"CoreMountedCameraPart"
		if slot_index < 0
		else "DroneCameraAttachment%d" % slot_index
	)
	definition.configure_camera(camera)
	camera.current = false
	add_child(camera)
	camera_attachment_nodes_by_slot[slot_index] = camera
	return camera


func mount_core_camera_part(
	definition: DroneCameraAttachmentDefinition
) -> Camera3D:
	if definition == null:
		return null
	core_camera_part_definition = definition
	_refresh_camera_attachment_nodes()
	return camera_attachment_nodes_by_slot.get(-1) as Camera3D


func unmount_core_camera_part() -> void:
	if core_camera_part_definition == null:
		return
	core_camera_part_definition = null
	_refresh_camera_attachment_nodes()


func get_camera_attachment(slot_index := -1) -> Camera3D:
	if slot_index >= 0:
		return camera_attachment_nodes_by_slot.get(slot_index) as Camera3D
	var slot_indices := camera_attachment_nodes_by_slot.keys()
	slot_indices.sort()
	for slot_value: Variant in slot_indices:
		var camera := camera_attachment_nodes_by_slot.get(int(slot_value)) as Camera3D
		if is_instance_valid(camera):
			return camera
	return null


func has_camera_attachment() -> bool:
	return get_camera_attachment() != null


func set_ml_episode_unlimited_battery(value: bool) -> void:
	ml_episode_unlimited_battery = value
	if (
		value
		and loadout != null
		and loadout.battery != null
	):
		remaining_battery_energy_wh = loadout.battery.energy_capacity_wh


func set_ml_training_performance_mode(value: bool) -> void:
	ml_training_performance_mode = value
	ground_effect_cache_initialized = false
	ground_effect_refresh_cursor = 0
	_refresh_spatial_interest()


func set_ml_training_paused(value: bool) -> void:
	if ml_training_paused == value:
		return
	if value:
		ml_training_pause_restore_freeze = freeze
		ml_training_pause_restore_sleeping = sleeping
		ml_training_pause_linear_velocity = linear_velocity
		ml_training_pause_angular_velocity = angular_velocity
		ml_training_paused = true
		freeze = true
		for assembly_value: Variant in limb_attachment_assemblies_by_slot.values():
			var assembly = assembly_value as GenericLimbAssembly3D
			if is_instance_valid(assembly):
				# A training pause is not a detach/reset boundary. Match four-limb workers by
				# freezing attached limbs while preserving any established grip for resume.
				assembly.set_runtime_active(false, false)
		return
	ml_training_paused = false
	freeze = ml_training_pause_restore_freeze
	ml_training_pause_restore_freeze = false
	linear_velocity = ml_training_pause_linear_velocity
	angular_velocity = ml_training_pause_angular_velocity
	if not freeze:
		sleeping = ml_training_pause_restore_sleeping
	ml_training_pause_restore_sleeping = false
	for assembly_value: Variant in limb_attachment_assemblies_by_slot.values():
		var assembly = assembly_value as GenericLimbAssembly3D
		if is_instance_valid(assembly):
			assembly.set_runtime_active(not freeze and not is_edit_preview)


func set_activated(value: bool) -> void:
	var was_activated := activated
	activated = (
		value
		and not edit_locked
		and not is_edit_preview
		and loadout != null
		and loadout.core != null
		and loadout.battery != null
		and remaining_battery_energy_wh > 0.0
		and current_health > 0.0
	)
	if activated:
		sleeping = false
		if not was_activated and flight_controller != null:
			flight_controller.reset_hold(global_position)
	elif was_activated and flight_controller != null:
		flight_controller.clear()
	if not activated and obstacle_avoidance != null:
		obstacle_avoidance.clear()
	_refresh_spatial_interest()


func toggle_activated() -> void:
	set_activated(not activated)


func apply_damage(amount: float) -> void:
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if current_health <= 0.0:
		set_activated(false)


func server_physics_tick(delta: float) -> void:
	if ml_training_paused:
		return
	if edit_locked or is_edit_preview:
		current_power_output = 0.0
		current_bus_voltage_v = 0.0
		power_spool_ratio = 0.0
		if activated:
			set_activated(false)
		return
	if freeze and not activated:
		# Completed training trials remain in the scene until every worker finishes. They are
		# intentionally frozen, so continuing the power bus, attachment, controller and rotor
		# simulation only burns CPU while producing no physical result.
		current_power_output = 0.0
		current_bus_voltage_v = 0.0
		power_spool_ratio = 0.0
		return
	if loadout == null or loadout.core == null:
		return

	if (
		loadout.battery == null
		or remaining_battery_energy_wh <= 0.0
	):
		set_activated(false)

	var target_spool := 1.0 if activated else 0.0
	var response = (
		cached_spool_up_response
		if target_spool > power_spool_ratio
		else cached_spool_down_response
	)
	var blend := 1.0 - exp(-maxf(response, 0.01) * delta)
	power_spool_ratio = lerpf(
		power_spool_ratio,
		target_spool,
		blend
	)
	current_power_output = (
		_calculate_forwarded_battery_power(delta)
		* power_spool_ratio
	)

	var remaining_power := current_power_output
	if has_installed_attachments_cache:
		_tick_weapon_cooldowns(delta)
	var ai_consumed_power := 0.0
	if activated and ai_controller != null and not is_ml_control_enabled():
		ai_consumed_power = ai_controller.process(delta, remaining_power)
		remaining_power = maxf(remaining_power - ai_consumed_power, 0.0)
	elif ai_controller != null and not ai_controller.combined_intent.is_empty():
		ai_controller.combined_intent.clear()
	_update_ai_command_outputs(delta)

	var attachment_consumed_power := 0.0
	if has_installed_attachments_cache:
		attachment_consumed_power = _apply_attachment_power(remaining_power)
		_process_powered_weapon_fire()
		remaining_power = maxf(
			remaining_power - attachment_consumed_power,
			0.0
		)
	var propeller_consumed_power := 0.0
	if air_environment != null:
		propeller_consumed_power = _apply_propeller_forces(remaining_power)
		_apply_air_drag()

	_drain_battery(
		ai_consumed_power
		+ attachment_consumed_power
		+ propeller_consumed_power,
		delta
	)


func _update_ai_command_outputs(delta: float) -> void:
	ai_fire_requested = false
	ai_combat_target_id = -1
	ai_combat_target_kind = &""
	ai_combat_target_position = Vector3.ZERO
	ai_avoidance_neighbor_count = 0
	if ai_controller == null or loadout == null or loadout.core == null:
		_clear_propeller_targets()
		return
	if is_ml_control_enabled():
		if not activated or flight_controller == null or air_environment == null:
			_clear_propeller_targets()
			return
		var ml_targets: Array[float] = ml_controller.step(delta)
		if ai_motor_thrust_targets.size() != ml_targets.size():
			ai_motor_thrust_targets.resize(ml_targets.size())
		for index in range(ml_targets.size()):
			ai_motor_thrust_targets[index] = ml_targets[index]
		return

	var intent := ai_controller.combined_intent
	ai_fire_requested = bool(intent.get("fire_requested", false))
	ai_combat_target_id = int(intent.get("combat_target_id", -1))
	ai_combat_target_kind = intent.get("combat_target_kind", &"")
	ai_combat_target_position = intent.get(
		"combat_target_position",
		Vector3.ZERO
	)
	ai_avoidance_neighbor_count = int(intent.get(
		"avoidance_neighbor_count",
		0
	))
	if not activated or flight_controller == null or air_environment == null:
		_clear_propeller_targets()
		return
	var ground_probe: Dictionary = _get_ai_ground_probe()
	ai_motor_thrust_targets = (
		flight_controller.calculate_rotor_thrust_targets(
			loadout.core,
			loadout,
			propeller_slots,
			intent,
			ground_probe,
			air_environment,
			delta
		)
	)


func _get_ai_ground_probe() -> Dictionary:
	if not is_inside_tree():
		return {}
	var origin: Vector3 = global_position + Vector3.UP * 0.15
	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(
			origin,
			origin + Vector3.DOWN * AI_GROUND_PROBE_DISTANCE
		)
	)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	if air_environment != null:
		query.collision_mask = air_environment.ground_collision_mask
	var hit: Dictionary = (
		get_world_3d().direct_space_state.intersect_ray(query)
	)
	if hit.is_empty():
		return {}
	var hit_position: Vector3 = hit.get("position", origin)
	return {
		"ground_height": hit_position.y,
		"position": hit_position,
	}


func _create_zero_propeller_targets() -> Array[float]:
	var result: Array[float] = []
	result.resize(propeller_slots.size())
	result.fill(0.0)
	return result


func _clear_propeller_targets() -> void:
	if ai_motor_thrust_targets.size() != propeller_slots.size():
		ai_motor_thrust_targets.resize(propeller_slots.size())
	ai_motor_thrust_targets.fill(0.0)


func get_ml_ground_probe() -> Dictionary:
	return _get_ai_ground_probe()


func enable_ml_control(model: DroneMLModel = null) -> void:
	if ml_controller != null:
		ml_controller.enable(model)
	_refresh_spatial_interest()


func disable_ml_control() -> void:
	ml_episode_unlimited_battery = false
	if ml_controller != null:
		ml_controller.disable()
	_refresh_spatial_interest()


func is_ml_control_enabled() -> bool:
	return ml_controller != null and ml_controller.enabled


func get_ml_snapshot() -> Dictionary:
	return ml_controller.snapshot_now() if ml_controller != null else {}


func get_ppo_snapshot() -> Dictionary:
	return ml_controller.ppo_snapshot_now() if ml_controller != null else {}


func get_ml_normalized_commands() -> Array[float]:
	return ml_controller.normalized_commands() if ml_controller != null else []


func get_ml_static_thrust_limits() -> Array[float]:
	return ml_controller.static_thrust_limits() if ml_controller != null else []


func set_ml_objective(objective: Dictionary) -> bool:
	if not is_ml_control_enabled():
		return false
	# The controller replaces this immutable top-level snapshot at each decision. The
	# obstacle probe inside it is deliberately refreshed in place between ray samples.
	ml_controller.objective = objective
	return true


func submit_ml_action(action: Dictionary) -> bool:
	if not is_ml_control_enabled():
		return false
	ml_controller.submit_external_action(action)
	return true


func reset_ml_episode(
	spawn_transform: Transform3D,
	random_seed: int,
	model: DroneMLModel
) -> bool:
	if (
		not is_inside_tree()
		or loadout == null
		or loadout.core == null
		or loadout.battery == null
	):
		return false

	if ml_training_paused:
		set_ml_training_paused(false)
	set_activated(false)
	freeze = true
	global_transform = spawn_transform
	reset_limb_attachments_to_rest()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	constant_force = Vector3.ZERO
	constant_torque = Vector3.ZERO
	sleeping = false
	current_health = loadout.core.max_health
	remaining_battery_energy_wh = loadout.battery.energy_capacity_wh
	current_power_output = 0.0
	current_bus_voltage_v = 0.0
	power_spool_ratio = 0.0
	battery_fluctuation_phase = 0.0
	core_fluctuation_phase = 0.0
	battery_spike_time_remaining = 0.0
	battery_spike_multiplier = 1.0
	power_rng.seed = random_seed
	clear_ml_propeller_degradation()
	ai_motor_thrust_targets = _create_zero_propeller_targets()
	last_propeller_requested_power_w = _create_zero_propeller_targets()
	last_propeller_applied_power_w = _create_zero_propeller_targets()
	last_propeller_realized_thrust_n = _create_zero_propeller_targets()
	ai_fire_requested = false
	ai_combat_target_id = -1
	ai_combat_target_kind = &""
	ai_combat_target_position = Vector3.ZERO
	ai_avoidance_neighbor_count = 0
	powered_weapon_slots.clear()
	weapon_cooldowns_by_slot.clear()
	weapon_aim_local_by_slot.clear()
	if ai_controller != null:
		ai_controller.combined_intent = {}
	if flight_controller != null:
		flight_controller.clear()
	if obstacle_avoidance != null:
		obstacle_avoidance.clear()
	if ml_controller != null:
		if model != null:
			model.reset_episode_state(random_seed)
		ml_controller.enable(model)
	ground_effect_cache_initialized = false
	ground_effect_refresh_cursor = 0
	set_limb_attachments_runtime_active(true, false)
	freeze = false
	reset_physics_interpolation()
	set_activated(true)
	return activated and is_ml_control_enabled()


func _apply_attachment_power(available_power: float) -> float:
	powered_weapon_slots.clear()
	if loadout == null or loadout.core == null or available_power <= 0.0:
		ai_fire_requested = false
		return 0.0

	var consumed := 0.0
	var remaining := available_power
	for slot_index in range(loadout.core.attachment_slot_count):
		var attachment := loadout.get_attachment(slot_index)
		if attachment == null:
			continue
		var is_requested_weapon := (
			ai_fire_requested
			and attachment.provides_capability(&"weapon")
		)
		var requested = (
			attachment.idle_power_draw
			+ (attachment.active_power_draw if is_requested_weapon else 0.0)
		)
		var allocated := minf(maxf(requested, 0.0), remaining)
		remaining -= allocated
		consumed += allocated
		var power_ratio = (
			allocated / requested
			if requested > MIN_POWER_REQUEST
			else 1.0
		)
		if is_requested_weapon and power_ratio >= 0.65:
			powered_weapon_slots.append(slot_index)

	if ai_fire_requested and powered_weapon_slots.is_empty():
		ai_fire_requested = false
	return consumed


func _tick_weapon_cooldowns(delta: float) -> void:
	var slots := weapon_cooldowns_by_slot.keys()
	for slot_value: Variant in slots:
		var slot_index := int(slot_value)
		var remaining := maxf(
			float(weapon_cooldowns_by_slot.get(slot_index, 0.0)) - delta,
			0.0
		)
		if remaining <= 0.0:
			weapon_cooldowns_by_slot.erase(slot_index)
		else:
			weapon_cooldowns_by_slot[slot_index] = remaining


func _process_powered_weapon_fire() -> void:
	if (
		not ai_fire_requested
		or ai_combat_target_id < 0
		or ai_combat_target_kind.is_empty()
		or loadout == null
		or loadout.core == null
	):
		weapon_aim_local_by_slot.clear()
		return
	var intended_target := Server.get_combat_target_body(
		ai_combat_target_kind,
		ai_combat_target_id
	)
	if not is_instance_valid(intended_target):
		weapon_aim_local_by_slot.clear()
		return
	if (
		intended_target is ServerEnemy
		and not (intended_target as ServerEnemy).is_ai_targetable()
	):
		return

	for slot_index: int in powered_weapon_slots:
		var weapon := loadout.get_attachment(slot_index) as DroneWeaponDefinition
		if weapon == null:
			continue
		var local_mount := SLOT_LAYOUT.get_attachment_position(
			slot_index,
			loadout.core.body_size
		)
		var mount_origin := to_global(local_mount)
		var profile := weapon.get_ballistic_profile()
		var target_velocity := _get_combat_target_velocity(
			intended_target
		)
		var aim_direction := BallisticAim.calculate_launch_direction(
			mount_origin,
			ai_combat_target_position,
			target_velocity,
			linear_velocity,
			float(profile.get("muzzle_velocity", weapon.projectile_speed)),
			float(profile.get("gravity_scale", 0.0))
		)
		var distance := mount_origin.distance_to(
			ai_combat_target_position
		)
		if distance <= 0.01 or distance > weapon.effective_range:
			continue
		weapon_aim_local_by_slot[slot_index] = (
			global_basis.inverse() * aim_direction
		)
		if float(weapon_cooldowns_by_slot.get(slot_index, 0.0)) > 0.0:
			continue

		var origin := (
			mount_origin
			+ aim_direction * minf(
				weapon.get_muzzle_distance(),
				maxf(distance - 0.08, 0.02)
			)
		)
		weapon_cooldowns_by_slot[slot_index] = (
			1.0 / maxf(weapon.rounds_per_second, 0.01)
		)
		Server.spawn_ballistic_projectile(
			profile,
			origin,
			aim_direction,
			linear_velocity,
			[get_rid()],
			&"drone",
			drone_id,
			self,
			slot_index
		)


func _get_combat_target_velocity(target: Node3D) -> Vector3:
	if target is CharacterBody3D:
		return (target as CharacterBody3D).velocity
	if target is RigidBody3D:
		return (target as RigidBody3D).linear_velocity
	return Vector3.ZERO


func _calculate_forwarded_battery_power(delta: float) -> float:
	var battery := loadout.battery
	var core := loadout.core
	if battery == null or remaining_battery_energy_wh <= 0.0:
		current_bus_voltage_v = 0.0
		return 0.0
	if (
		deterministic_power_output_cache
		and battery_spike_time_remaining <= 0.0
		and is_equal_approx(battery_spike_multiplier, 1.0)
	):
		# The calibrated training parts have perfectly consistent output and no spike chance.
		# Avoid four sine calls and one RNG sample on every physics tick when the exact result
		# is a constant. Variable gameplay batteries continue through the original path.
		current_bus_voltage_v = deterministic_bus_voltage_v
		return deterministic_forwarded_power_w

	battery_fluctuation_phase += TAU * battery.fluctuation_rate * delta
	core_fluctuation_phase += TAU * core.fluctuation_rate * delta

	if battery_spike_time_remaining > 0.0:
		battery_spike_time_remaining = maxf(
			battery_spike_time_remaining - delta,
			0.0
		)
		if battery_spike_time_remaining <= 0.0:
			battery_spike_multiplier = 1.0
	elif (
		activated
		and power_rng.randf()
		< 1.0 - exp(-battery.spike_chance_per_second * delta)
	):
		battery_spike_time_remaining = power_rng.randf_range(
			minf(battery.minimum_spike_duration, battery.maximum_spike_duration),
			maxf(battery.minimum_spike_duration, battery.maximum_spike_duration)
		)
		if power_rng.randf() < 0.5:
			battery_spike_multiplier = power_rng.randf_range(
				minf(battery.minimum_drop_multiplier, battery.maximum_drop_multiplier),
				maxf(battery.minimum_drop_multiplier, battery.maximum_drop_multiplier)
			)
		else:
			battery_spike_multiplier = power_rng.randf_range(
				minf(battery.minimum_boost_multiplier, battery.maximum_boost_multiplier),
				maxf(battery.minimum_boost_multiplier, battery.maximum_boost_multiplier)
			)
			_handle_power_spike_started(battery_spike_multiplier)

	var battery_wave := (
		sin(battery_fluctuation_phase)
		+ 0.35 * sin(battery_fluctuation_phase * 2.17 + 1.3)
	) / 1.35
	var core_wave := (
		sin(core_fluctuation_phase + 0.7)
		+ 0.25 * sin(core_fluctuation_phase * 1.73)
	) / 1.25
	var battery_multiplier = (
		1.0
		+ (1.0 - battery.power_output_consistency) * battery_wave
	)
	var core_multiplier = (
		1.0
		+ (1.0 - core.power_output_consistency) * core_wave
	)
	current_bus_voltage_v = maxf(
		battery.nominal_voltage_v
		* battery_multiplier
		* core_multiplier
		* battery_spike_multiplier,
		0.0
	)
	var battery_power = (
		battery.nominal_power_output
		* battery_multiplier
		* core_multiplier
		* battery_spike_multiplier
	)
	battery_power = clampf(
		battery_power,
		0.0,
		battery.maximum_power_output
	)

	# The core is only a forwarding bottleneck. It creates no power itself.
	return minf(battery_power, core.max_power_throughput)


func _apply_propeller_forces(available_power_input: float) -> float:
	_reset_propeller_telemetry()
	if requested_power_workspace.size() != propeller_slots.size():
		_refresh_propeller_runtime_cache()
	requested_power_workspace.fill(0.0)
	var total_demand := 0.0
	for array_index: int in range(propeller_slots.size()):
		var disk_area := propeller_disk_area_by_slot[array_index]
		if disk_area <= 0.0:
			continue
		var demand_slot: DronePropellerSlot = propeller_slots[array_index]
		if is_ml_propeller_degraded(demand_slot.slot_index):
			continue
		var target_thrust := (
			ai_motor_thrust_targets[array_index]
			if array_index < ai_motor_thrust_targets.size()
			else 0.0
		)
		var requested_power := minf(
			air_environment.calculate_rotor_power(
				target_thrust,
				disk_area,
				propeller_efficiency_by_slot[array_index]
			),
			propeller_max_power_by_slot[array_index]
		)
		requested_power_workspace[array_index] = requested_power
		last_propeller_requested_power_w[array_index] = requested_power
		total_demand += requested_power
	if total_demand <= 0.0 or available_power_input <= 0.0:
		return 0.0

	# A constrained power bus scales every rotor equally. Battery drops can
	# reduce lift, but they no longer inject an artificial roll impulse by
	# starving whichever motor happened to be processed last.
	var power_scale := minf(available_power_input / total_demand, 1.0)
	var consumed_power := total_demand * power_scale
	var space_state := get_world_3d().direct_space_state
	_refresh_ground_effect_cache(space_state)

	for array_index: int in range(propeller_slots.size()):
		var disk_area := propeller_disk_area_by_slot[array_index]
		if disk_area <= 0.0:
			continue
		var slot: DronePropellerSlot = propeller_slots[array_index]
		if is_ml_propeller_degraded(slot.slot_index):
			continue
		var power_share := requested_power_workspace[array_index] * power_scale
		last_propeller_applied_power_w[array_index] = power_share

		var thrust := air_environment.calculate_rotor_thrust(
			power_share,
			disk_area,
			propeller_efficiency_by_slot[array_index]
		)
		var lift_axis := slot.global_basis.y.normalized()
		var body_offset := slot.global_position - global_position
		var point_velocity = (
			linear_velocity
			+ angular_velocity.cross(body_offset)
			- air_environment.wind_velocity
		)
		var induced_velocity := air_environment.calculate_induced_velocity(
			thrust,
			disk_area
		)
		var axial_flow_factor := clampf(
			1.0
			- propeller_axial_response_by_slot[array_index]
			* point_velocity.dot(lift_axis)
			/ maxf(induced_velocity, 0.1),
			propeller_minimum_axial_factor_by_slot[array_index],
			propeller_maximum_axial_factor_by_slot[array_index]
		)
		thrust *= axial_flow_factor
		thrust *= cached_ground_effect_by_slot[array_index]
		last_propeller_realized_thrust_n[array_index] = thrust

		var lift_force := lift_axis * thrust
		apply_force(lift_force, body_offset)

		# Counter-rotating propeller slots cancel this in a balanced build.
		apply_torque(
			lift_axis
			* float(slot.spin_direction)
			* thrust
			* propeller_reaction_torque_by_slot[array_index]
		)

	if flight_controller != null and power_scale > 0.15:
		apply_torque(
			flight_controller.emergency_torque_world * power_scale
		)

	return consumed_power


func _refresh_ground_effect_cache(
	space_state: PhysicsDirectSpaceState3D
) -> void:
	if air_environment == null or space_state == null:
		cached_ground_effect_by_slot.fill(1.0)
		return
	var slot_count := propeller_slots.size()
	if slot_count <= 0:
		return
	if not ml_training_performance_mode or not ground_effect_cache_initialized:
		for array_index in range(slot_count):
			cached_ground_effect_by_slot[array_index] = (
				air_environment.calculate_ground_effect(
					space_state,
					propeller_slots[array_index].global_position,
					get_rid()
				)
				if propeller_disk_area_by_slot[array_index] > 0.0
				else 1.0
			)
		ground_effect_cache_initialized = true
		ground_effect_refresh_cursor = 0
		return
	var refresh_count := mini(
		ML_GROUND_EFFECT_RAYS_PER_PHYSICS_TICK,
		slot_count
	)
	for _refresh_index in range(refresh_count):
		var array_index := ground_effect_refresh_cursor % slot_count
		ground_effect_refresh_cursor = (array_index + 1) % slot_count
		if propeller_disk_area_by_slot[array_index] <= 0.0:
			cached_ground_effect_by_slot[array_index] = 1.0
			continue
		cached_ground_effect_by_slot[array_index] = (
			air_environment.calculate_ground_effect(
				space_state,
				propeller_slots[array_index].global_position,
				get_rid()
			)
		)


func _reset_propeller_telemetry() -> void:
	var slot_count := propeller_slots.size()
	if last_propeller_requested_power_w.size() != slot_count:
		last_propeller_requested_power_w.resize(slot_count)
	if last_propeller_applied_power_w.size() != slot_count:
		last_propeller_applied_power_w.resize(slot_count)
	if last_propeller_realized_thrust_n.size() != slot_count:
		last_propeller_realized_thrust_n.resize(slot_count)
	last_propeller_requested_power_w.fill(0.0)
	last_propeller_applied_power_w.fill(0.0)
	last_propeller_realized_thrust_n.fill(0.0)


func _refresh_propeller_runtime_cache() -> void:
	if ml_controller != null:
		ml_controller.invalidate_static_thrust_cache()
	var slot_count := propeller_slots.size()
	requested_power_workspace.resize(slot_count)
	requested_power_workspace.fill(0.0)
	propeller_disk_area_by_slot.resize(slot_count)
	propeller_efficiency_by_slot.resize(slot_count)
	propeller_max_power_by_slot.resize(slot_count)
	propeller_reaction_torque_by_slot.resize(slot_count)
	propeller_axial_response_by_slot.resize(slot_count)
	propeller_minimum_axial_factor_by_slot.resize(slot_count)
	propeller_maximum_axial_factor_by_slot.resize(slot_count)
	cached_ground_effect_by_slot.resize(slot_count)
	cached_ground_effect_by_slot.fill(1.0)
	ground_effect_refresh_cursor = 0
	ground_effect_cache_initialized = false
	for array_index in range(slot_count):
		var slot := propeller_slots[array_index]
		var propeller: DronePropellerDefinition = (
			loadout.get_propeller(slot.slot_index)
			if loadout != null
			else null
		)
		if propeller == null:
			propeller_disk_area_by_slot[array_index] = 0.0
			propeller_efficiency_by_slot[array_index] = 0.0
			propeller_max_power_by_slot[array_index] = 0.0
			propeller_reaction_torque_by_slot[array_index] = 0.0
			propeller_axial_response_by_slot[array_index] = 0.0
			propeller_minimum_axial_factor_by_slot[array_index] = 0.0
			propeller_maximum_axial_factor_by_slot[array_index] = 0.0
			continue
		propeller_disk_area_by_slot[array_index] = propeller.get_disk_area()
		propeller_efficiency_by_slot[array_index] = propeller.aerodynamic_efficiency
		propeller_max_power_by_slot[array_index] = propeller.max_power_draw
		propeller_reaction_torque_by_slot[array_index] = (
			propeller.reaction_torque_per_newton
		)
		propeller_axial_response_by_slot[array_index] = propeller.axial_flow_response
		propeller_minimum_axial_factor_by_slot[array_index] = (
			propeller.minimum_axial_flow_factor
		)
		propeller_maximum_axial_factor_by_slot[array_index] = (
			propeller.maximum_axial_flow_factor
		)
	cached_spool_up_response = 1.0
	cached_spool_down_response = 1.0
	cached_drag_area = 0.0
	cached_drag_coefficient = 0.0
	cached_angular_drag_coefficient = 0.0
	deterministic_power_output_cache = false
	deterministic_bus_voltage_v = 0.0
	deterministic_forwarded_power_w = 0.0
	if loadout != null and loadout.core != null:
		var core := loadout.core
		cached_spool_up_response = core.spool_up_response
		cached_spool_down_response = core.spool_down_response
		cached_drag_area = core.drag_area
		cached_drag_coefficient = core.drag_coefficient
		cached_angular_drag_coefficient = core.angular_drag_coefficient
		var battery := loadout.battery
		if battery != null:
			deterministic_power_output_cache = (
				is_equal_approx(battery.power_output_consistency, 1.0)
				and is_equal_approx(core.power_output_consistency, 1.0)
				and battery.spike_chance_per_second <= 0.0
			)
			deterministic_bus_voltage_v = maxf(battery.nominal_voltage_v, 0.0)
			deterministic_forwarded_power_w = minf(
				clampf(
					battery.nominal_power_output,
					0.0,
					maxf(battery.maximum_power_output, 0.0)
				),
				maxf(core.max_power_throughput, 0.0)
			)
	has_installed_attachments_cache = false
	if loadout != null and loadout.core != null:
		for attachment_slot_index in range(loadout.core.attachment_slot_count):
			var attachment := loadout.get_attachment(attachment_slot_index)
			# Passive camera parts are represented in the real loadout but require no power,
			# cooldown, targeting, or weapon tick. Do not make every observed training drone
			# pay the general attachment-processing cost each physics frame.
			if attachment != null and not attachment is DroneCameraAttachmentDefinition:
				has_installed_attachments_cache = true
				break
	if not has_installed_attachments_cache:
		powered_weapon_slots.clear()
		weapon_cooldowns_by_slot.clear()
		weapon_aim_local_by_slot.clear()
	cached_ai_collision_radius = _calculate_ai_collision_radius()
	_reset_propeller_telemetry()


func _drain_battery(consumed_power: float, delta: float) -> void:
	if loadout.battery == null:
		return
	if ml_episode_unlimited_battery:
		# Training episodes can be much longer than the default Minute Cell. Keep the
		# stored charge full without changing battery mass, voltage, output, or spikes.
		remaining_battery_energy_wh = loadout.battery.energy_capacity_wh
		return
	if consumed_power <= 0.0:
		return

	remaining_battery_energy_wh = maxf(
		remaining_battery_energy_wh
		- consumed_power * delta / 3600.0,
		0.0
	)
	if remaining_battery_energy_wh <= 0.0:
		set_activated(false)


func _apply_air_drag() -> void:
	var relative_air_velocity = linear_velocity - air_environment.wind_velocity
	apply_central_force(
		air_environment.calculate_linear_drag(
			relative_air_velocity,
			cached_drag_area,
			cached_drag_coefficient
		)
	)

	# Distributed rotor/arm drag resists tumbling without forcing the body
	# upright. Its orientation remains a consequence of rigid-body physics.
	apply_torque(
		-angular_velocity
		* air_environment.air_density
		* cached_angular_drag_coefficient
	)


func _calculate_loadout_inertia() -> Vector3:
	if loadout == null or loadout.core == null:
		return Vector3.ZERO

	var core := loadout.core
	var size = core.body_size
	var result := _calculate_box_inertia(
		core.get_mass(),
		size,
		Vector3.ZERO
	)
	if loadout.battery != null:
		result += _calculate_box_inertia(
			loadout.battery.get_mass(),
			loadout.battery.body_size,
			$BatterySocket.position
		)

	for slot in propeller_slots:
		var propeller := loadout.get_propeller(slot.slot_index)
		if propeller == null:
			continue
		result += _calculate_propeller_inertia(
			propeller.get_mass(),
			propeller.rotor_radius,
			slot.position
		)

	for slot_index in range(core.ai_chip_slot_count):
		var chip := loadout.get_ai_chip(slot_index)
		if chip == null:
			continue
		var chip_offset := SLOT_LAYOUT.get_ai_chip_position(slot_index, size)
		result += _calculate_point_mass_inertia(chip.get_mass(), chip_offset)

	for slot_index in range(core.attachment_slot_count):
		var attachment := loadout.get_attachment(slot_index)
		if attachment == null:
			continue
		var attachment_offset := SLOT_LAYOUT.get_attachment_position(
			slot_index,
			size
		)
		result += _calculate_box_inertia(
			attachment.get_mass(),
			attachment.body_size,
			attachment_offset
		)

	return result


func _calculate_box_inertia(
	part_mass: float,
	part_size: Vector3,
	offset: Vector3
) -> Vector3:
	return Vector3(
		part_mass * (
			part_size.y * part_size.y + part_size.z * part_size.z
		) / BOX_INERTIA_DIVISOR,
		part_mass * (
			part_size.x * part_size.x + part_size.z * part_size.z
		) / BOX_INERTIA_DIVISOR,
		part_mass * (
			part_size.x * part_size.x + part_size.y * part_size.y
		) / BOX_INERTIA_DIVISOR
	) + _calculate_point_mass_inertia(part_mass, offset)


func _calculate_propeller_inertia(
	part_mass: float,
	radius: float,
	offset: Vector3
) -> Vector3:
	var radius_squared := radius * radius
	return _calculate_point_mass_inertia(part_mass, offset) + Vector3(
		DISC_DIAMETER_INERTIA_FACTOR * part_mass * radius_squared,
		DISC_AXIS_INERTIA_FACTOR * part_mass * radius_squared,
		DISC_DIAMETER_INERTIA_FACTOR * part_mass * radius_squared
	)


func _calculate_point_mass_inertia(
	part_mass: float,
	offset: Vector3
) -> Vector3:
	return Vector3(
		part_mass * (offset.y * offset.y + offset.z * offset.z),
		part_mass * (offset.x * offset.x + offset.z * offset.z),
		part_mass * (offset.x * offset.x + offset.y * offset.y)
	)


func get_power_ratio() -> float:
	if loadout == null or loadout.battery == null:
		return 0.0

	return clampf(
		current_power_output
		/ maxf(loadout.battery.nominal_power_output, 0.001),
		0.0,
		2.0
	)


func get_battery_charge_ratio() -> float:
	if loadout == null or loadout.battery == null:
		return 0.0

	return clampf(
		remaining_battery_energy_wh
		/ maxf(loadout.battery.energy_capacity_wh, 0.001),
		0.0,
		1.0
	)


func get_rope_power_state() -> Dictionary:
	if loadout == null or loadout.battery == null:
		return {}
	return {
		"capacity_wh": loadout.battery.energy_capacity_wh,
		"energy_wh": clampf(
			remaining_battery_energy_wh,
			0.0,
			loadout.battery.energy_capacity_wh
		),
		"maximum_output_w": loadout.battery.maximum_power_output,
		"maximum_input_w": loadout.battery.maximum_power_output,
	}


func extract_rope_energy(requested_wh: float) -> float:
	if loadout == null or loadout.battery == null:
		return 0.0
	var extracted := minf(
		maxf(requested_wh, 0.0),
		remaining_battery_energy_wh
	)
	remaining_battery_energy_wh -= extracted
	if remaining_battery_energy_wh <= 0.0:
		set_activated(false)
	return extracted


func receive_rope_energy(offered_wh: float) -> float:
	if loadout == null or loadout.battery == null:
		return 0.0
	var accepted := minf(
		maxf(offered_wh, 0.0),
		maxf(
			loadout.battery.energy_capacity_wh
			- remaining_battery_energy_wh,
			0.0
		)
	)
	remaining_battery_energy_wh += accepted
	return accepted


func build_ai_context() -> Dictionary:
	var weapon_slots: Array[int] = []
	var weapon_snapshots: Array[Dictionary] = []
	if loadout != null and loadout.core != null:
		weapon_slots = loadout.find_attachment_slots_with_capability(&"weapon")
		for slot_index in weapon_slots:
			var weapon := loadout.get_attachment(slot_index) as DroneWeaponDefinition
			if weapon == null:
				continue
			weapon_snapshots.append({
				"slot_index": slot_index,
				"definition": weapon,
				"effective_range": weapon.effective_range,
				"damage_per_shot": weapon.damage_per_shot,
				"rounds_per_second": weapon.rounds_per_second,
				"projectile_speed": weapon.projectile_speed,
			})
	var fiber_links: Array[Dictionary] = (
		Server.get_fiber_link_states_for_body(self)
	)
	return {
		"position": global_position,
		"velocity": linear_velocity,
		"basis": global_basis,
		"faction_id": faction_id,
		"weapon_slots": weapon_slots,
		"weapons": weapon_snapshots,
		"manipulator_slots": (
			loadout.find_attachment_slots_with_capability(&"manipulator")
			if loadout != null
			else []
		),
		"fiber_link_active": not fiber_links.is_empty(),
		"fiber_links": fiber_links,
		# Target discovery is intentionally lazy. Combat behaviors call this
		# only after confirming they have an order and an installed weapon.
		"combat_candidate_provider": Callable(
			self,
			"get_ai_combat_candidates"
		),
	}


func get_ai_combat_candidates(
	center: Vector3,
	maximum_range: float
) -> Array[Dictionary]:
	return Server.get_drone_ai_candidates(self, center, maximum_range)


func calculate_ai_avoidance(
	definition: DroneAIChipDefinition,
	intent: Dictionary,
	delta: float
) -> Dictionary:
	if (
		definition == null
		or not definition.is_collision_avoidance_chip()
		or not activated
		or loadout == null
		or loadout.core == null
		or flight_controller == null
	):
		return {}

	var preferred_world := (
		flight_controller.calculate_preferred_horizontal_velocity(
			loadout.core,
			intent
		)
	)
	var preferred := Vector2(preferred_world.x, preferred_world.z)
	var current_velocity := Vector2(linear_velocity.x, linear_velocity.z)
	var position := Vector2(global_position.x, global_position.z)
	var physical_radius := get_ai_collision_radius()
	var own_radius := (
		physical_radius + definition.get_avoidance_radius_padding()
	)
	var raw_neighbors: Array[Dictionary] = (
		Server.get_drone_avoidance_neighbors(
			self,
			definition.get_avoidance_neighbor_distance(),
			definition.get_avoidance_vertical_tolerance()
		)
	)
	if raw_neighbors.is_empty():
		return {}

	var relevant_neighbors: Array[Dictionary] = []
	for neighbor: Dictionary in raw_neighbors:
		if OrcaVelocitySolver.is_relevant_neighbor(
			position,
			current_velocity,
			preferred,
			own_radius,
			definition.get_avoidance_time_horizon(),
			neighbor
		):
			relevant_neighbors.append(neighbor)
		if relevant_neighbors.size() >= definition.get_avoidance_max_neighbors():
			break
	if relevant_neighbors.is_empty():
		return {}

	var solution := OrcaVelocitySolver.solve(
		position,
		current_velocity,
		preferred,
		flight_controller.get_navigation_speed_limit(loadout.core, intent),
		own_radius,
		definition.get_avoidance_time_horizon(),
		clampf(delta, 0.008, 0.1),
		drone_id,
		relevant_neighbors
	)
	var solved_velocity: Vector2 = solution.get("velocity", preferred)
	return {
		"velocity": Vector3(
			solved_velocity.x,
			0.0,
			solved_velocity.y
		),
		"neighbor_count": relevant_neighbors.size(),
		"constraint_count": int(solution.get("constraint_count", 0)),
	}


func calculate_ai_static_obstacle_avoidance(
	intent: Dictionary,
	delta: float
) -> Dictionary:
	if (
		not activated
		or obstacle_avoidance == null
		or flight_controller == null
		or loadout == null
		or loadout.core == null
		or not bool(intent.get("movement_active", false))
	):
		return {}
	var preferred_velocity := (
		flight_controller.calculate_unmodified_preferred_horizontal_velocity(
			loadout.core,
			intent
		)
	)
	return obstacle_avoidance.calculate(
		preferred_velocity,
		flight_controller.get_navigation_acceleration_limit(
			loadout.core,
			intent
		),
		get_ai_collision_radius(),
		delta
	)


func get_ai_collision_radius() -> float:
	return cached_ai_collision_radius


func _calculate_ai_collision_radius() -> float:
	var result := 0.72
	if loadout == null or loadout.core == null:
		return result
	var core_size = loadout.core.body_size
	result = maxf(
		result,
		Vector2(core_size.x, core_size.z).length() * 0.5
	)
	for slot: DronePropellerSlot in propeller_slots:
		var propeller := loadout.get_propeller(slot.slot_index)
		if propeller == null:
			continue
		var rotor_center := Vector2(slot.position.x, slot.position.z)
		result = maxf(
			result,
			rotor_center.length() + propeller.rotor_radius
		)
	return result


func has_collision_avoidance_chip() -> bool:
	return _has_ai_behavior(&"orca_collision_avoidance")


func is_collision_avoidance_operational() -> bool:
	return (
		activated
		and ai_controller != null
		and ai_controller.has_operational_behavior(
			&"orca_collision_avoidance"
		)
	)


func _has_ai_behavior(behavior_id: StringName) -> bool:
	if loadout == null or loadout.core == null:
		return false
	for slot_index: int in range(loadout.core.ai_chip_slot_count):
		var chip := loadout.get_ai_chip(slot_index)
		if chip != null and chip.behavior_id == behavior_id:
			return true
	return false


func _has_active_combat_candidate_behavior() -> bool:
	if _has_ai_behavior(&"combat_targeting"):
		return true
	if ai_controller == null:
		return false
	return (
		(_has_ai_behavior(&"guard_sphere") and ai_controller.guard_enabled)
		or (
			_has_ai_behavior(&"waypoint_guard")
			and not ai_controller.waypoints.is_empty()
		)
	)


func _has_weapon_attachment() -> bool:
	return (
		loadout != null
		and not loadout.find_attachment_slots_with_capability(
			&"weapon"
		).is_empty()
	)


func _refresh_spatial_interest() -> void:
	if drone_id < 0:
		return
	var general_ai_enabled := activated and not is_ml_control_enabled()
	Server.set_drone_spatial_interest(
		drone_id,
		general_ai_enabled
		and _has_weapon_attachment()
		and _has_active_combat_candidate_behavior(),
		general_ai_enabled and has_collision_avoidance_chip()
	)


func get_ai_follow_target_snapshot(player_id: int) -> Dictionary:
	var player := Server.get_server_player(player_id)
	if player == null:
		return {}
	# Orientation is deliberately not part of the follow contract. Chips may
	# react to where the player goes, but never to where the player looks.
	return {
		"position": player.global_position,
		"velocity": player.velocity,
		"faction_id": player.faction_id,
	}


func set_ai_waypoint_plan(points: Array[Vector3], loop: bool) -> void:
	if ai_controller != null:
		ai_controller.set_waypoint_plan(points, loop)
		_refresh_spatial_interest()


func set_ai_guard_sphere(center: Vector3, radius: float) -> void:
	if ai_controller != null:
		ai_controller.set_guard_sphere(center, radius)
		_refresh_spatial_interest()


func set_ai_follow_player(player_id: int) -> void:
	if ai_controller != null:
		ai_controller.set_follow_player(player_id)


func clear_ai_orders() -> void:
	if ai_controller != null:
		ai_controller.clear_orders()
		_refresh_spatial_interest()


func _handle_power_spike_started(spike_multiplier: float) -> void:
	if (
		loadout == null
		or loadout.core == null
		or loadout.battery == null
		or spike_multiplier <= 1.0
	):
		return

	var broken_slots: Array[int] = []
	var battery := loadout.battery
	for slot_index in range(loadout.core.ai_chip_slot_count):
		var chip := loadout.get_ai_chip(slot_index)
		if (
			chip == null
			or chip.surge_immune
			or spike_multiplier <= chip.damaging_spike_threshold
		):
			continue
		var overvoltage = spike_multiplier - chip.damaging_spike_threshold
		var break_chance := clampf(
			overvoltage
			* chip.surge_fragility
			* (1.0 - battery.surge_protection)
			* battery.extreme_spike_damage_coupling,
			0.0,
			0.35
		)
		if power_rng.randf() < break_chance:
			broken_slots.append(slot_index)

	for slot_index in broken_slots:
		_eject_broken_ai_chip(slot_index)


func _eject_broken_ai_chip(slot_index: int) -> void:
	var chip := loadout.get_ai_chip(slot_index)
	if chip == null:
		return
	var slot_node := get_node_or_null(
		"AIChip%dCollision" % slot_index
	) as Node3D
	var ejection_transform := (
		slot_node.global_transform
		if slot_node != null
		else global_transform
	)
	loadout.remove_ai_chip(slot_index)
	_apply_loadout()
	var ejected := Server.spawn_drone_part(
		chip,
		ejection_transform,
		-1.0,
		-1.0,
		-1,
		true
	)
	if ejected == null:
		return
	var side_impulse := (
		global_basis.x * power_rng.randf_range(-0.05, 0.05)
		+ global_basis.z * power_rng.randf_range(-0.05, 0.05)
	)
	ejected.apply_central_impulse(
		global_basis.y.normalized() * power_rng.randf_range(0.14, 0.22)
		+ side_impulse
	)
	ejected.angular_velocity = Vector3(
		power_rng.randf_range(-8.0, 8.0),
		power_rng.randf_range(-8.0, 8.0),
		power_rng.randf_range(-8.0, 8.0)
	)


func to_state_dict() -> Dictionary:
	var weapon_aim_directions: Array[Vector3] = []
	var attachment_slot_count = (
		loadout.core.attachment_slot_count
		if loadout != null and loadout.core != null
		else 0
	)
	for slot_index: int in range(attachment_slot_count):
		weapon_aim_directions.append(
			weapon_aim_local_by_slot.get(
				slot_index,
				Vector3.FORWARD
			)
		)
	return {
		"drone_id": drone_id,
		"pos": global_position,
		"rot": global_rotation,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"activated": activated,
		"visible": network_visible,
		"edit_preview": is_edit_preview,
		"power_ratio": get_power_ratio(),
		"health": current_health,
		"core_present": (
			loadout != null and loadout.core != null
		),
		"core_definition_path": (
			DroneLoadout.definition_path(loadout.core)
			if loadout != null and loadout.core != null
			else ""
		),
		"battery_present": (
			loadout != null and loadout.battery != null
		),
		"battery_definition_path": (
			DroneLoadout.definition_path(loadout.battery)
			if loadout != null and loadout.battery != null
			else ""
		),
		"battery_charge_ratio": get_battery_charge_ratio(),
		"propellers": (
			loadout.get_propeller_presence()
			if loadout != null
			else []
		),
		"propeller_definition_paths": (
			loadout.get_propeller_definition_paths()
			if loadout != null
			else []
		),
		"ai_chip_slot_count": (
			loadout.core.ai_chip_slot_count
			if loadout != null and loadout.core != null
			else 0
		),
		"ai_chip_definition_paths": (
			loadout.get_ai_chip_definition_paths()
			if loadout != null
			else []
		),
		"attachment_slot_count": attachment_slot_count,
		"attachment_definition_paths": (
			loadout.get_attachment_definition_paths()
			if loadout != null
			else []
		),
		"weapon_aim_directions": weapon_aim_directions,
		"ai_active_chip_count": (
			ai_controller.get_active_chip_count()
			if ai_controller != null
			else 0
		),
		"ai_fire_requested": ai_fire_requested,
		"ai_combat_target_id": ai_combat_target_id,
		"ai_combat_target_kind": ai_combat_target_kind,
		"ai_combat_target_position": ai_combat_target_position,
		"ai_avoidance_neighbor_count": ai_avoidance_neighbor_count,
		"faction_id": faction_id,
	}
