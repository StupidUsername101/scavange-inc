class_name ServerPlayer
extends CharacterBody3D

signal inventory_changed(revision: int)

const WALK_SPEED := 5.75
const RUN_SPEED := 13.5
const GROUND_ACCELERATION := 46.0
const GROUND_DECELERATION := 52.0
const AIR_CONTROL_ACCELERATION := 7.0

const GRAVITY := 24.0
const JUMP_VELOCITY := 10.0
const MAX_FALL_SPEED := 48.0
const ARM_CRAWL_MOVEMENT_MULTIPLIER := 0.2
const STANDING_COLLISION_HEIGHT := 1.979
const LEGLESS_COLLISION_HEIGHT := 1.1
const MAX_HEALTH := 100.0
const BASE_MAX_STAMINA := 100.0
const TEMPORARY_STAMINA_MULTIPLIER := 3.0
const MAX_STAMINA := BASE_MAX_STAMINA * TEMPORARY_STAMINA_MULTIPLIER
const RUN_STAMINA_DRAIN_PER_SECOND := 19.0
const STAMINA_RECOVERY_PER_SECOND := 15.0
const STAMINA_RECOVERY_DELAY := 0.7
const COLLISION_SAFE_MARGIN := 0.001
const WEAPON_RANDOM_SEED_BASE := 5381
const PLAYER_RANDOM_SEED_FACTOR := 7919
const MAX_LOOK_PITCH_DEGREES := 85.0
const DEFAULT_DISTORTION_CENTER := Vector2(0.5, 0.5)
const DEFAULT_DISTORTION_PULSE_HZ := 7.0
const MIN_DISTORTION_PULSE_HZ := 0.1
const MAX_DISTORTION_PULSE_HZ := 30.0
const MAX_DISTORTION_DURATION := 12.0
const STAMINA_EMPTY_THRESHOLD := 0.01
const MOVEMENT_INPUT_THRESHOLD_SQUARED := 0.001
const MOTION_THRESHOLD_SQUARED := 0.000001
const FLOOR_CONTACT_NORMAL_Y := 0.6
const FLOOR_STICK_VELOCITY := -0.1
const MAX_STEP_HEIGHT := 0.28
const STEP_DOWN_PROBE_DISTANCE := 0.04
const MIN_STEP_RISE := 0.008
const MIN_STEP_FORWARD_PROGRESS_SQUARED := 0.000004
const MIN_PUSH_BODY_MASS := 0.1
const PUSH_IMPULSE_STRENGTH := 4.0
const RELOAD_DURATION_THRESHOLD := 0.001
const RELOAD_INSERT_SOUND_REMAINING_RATIO := 0.45
const FOOTSTEP_MAX_DISTANCE := 24.0
const FOOTSTEP_PRIORITY := 0.25
const JUMP_SOUND_MAX_DISTANCE := 26.0
const JUMP_SOUND_PRIORITY := 0.35
const LANDING_SOUND_MAX_DISTANCE := 30.0
const LANDING_SOUND_PRIORITY := 0.4
const LANDING_MIN_AIR_TIME := 0.18
const LANDING_MIN_IMPACT_SPEED := 2.0
const TRIP_MIN_AIR_TIME := 0.05
const TRIP_RECOVERY_SECONDS := 1.65
const TRIP_SUPPORT_LATERAL_OFFSET := 0.22
const TRIP_SUPPORT_FORWARD_LEAD_SECONDS := 0.035
const TRIP_SUPPORT_MAX_FORWARD_LEAD := 0.22
const TRIP_SUPPORT_PROBE_UP := 0.30
const TRIP_SUPPORT_PROBE_DOWN := 1.35
const TRIP_RECOVERY_GROUND_PROBE_UP := 0.2
const TRIP_RECOVERY_GROUND_PROBE_DOWN := 3.2
const TRIP_RECOVERY_CLEARANCE := 0.035
const TRIP_RECOVERY_SEARCH_RADIUS := 0.38
const WRIST_SOUND_HOVER_COOLDOWN_MSEC := 80
const WRIST_SOUND_CLICK_COOLDOWN_MSEC := 90
const WRIST_SOUND_FEEDBACK_COOLDOWN_MSEC := 220
const WRIST_SOUND_SOURCE_HEIGHT_OFFSET := -0.12
const WRIST_SOUND_OUTPUT_GAIN_DB := -5.0
# Mouth clicks are an expressive/rhythmic input, so a conventional half-second ability cooldown
# feels artificial. This bucket sustains faster-than-normal musical tapping while still bounding
# malicious RPC spam and the acoustic work it can create for other peers.
const ECHOLOCATION_CLICK_MIN_INTERVAL_MSEC := 45
const ECHOLOCATION_CLICK_REFILL_PER_SECOND := 12.0
const ECHOLOCATION_CLICK_BURST_CAPACITY := 4.0
const DISTORTION_FADE_DURATION_RATIO := 0.3
const MIN_DISTORTION_FADE_DURATION := 0.08
const MAX_DISTORTION_FADE_DURATION := 1.2
const DEFAULT_EYES := preload(
	"res://resources/items/eyes/factory_oculars.tres"
)
const DEFAULT_WRIST_DEVICE := preload(
	"res://resources/items/wrist_devices/corporate_field_terminal.tres"
)
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)
const LOCAL_AUDIO_PREDICTION := preload(
	"res://scripts/audio/local_audio_prediction.gd"
)
const PLAYER_RAGDOLL_ANCHOR := preload(
	"res://scripts/characters/player_ragdoll_anchor_3d.gd"
)

#######################################################
# Simulates an authoritative player, including movement, body capabilities, inventory,
# equipment, stamina, weapons, and vision state.
#######################################################

var air_time := 0.0
var wants_run := false

@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var grabber: GrabberComponent = $Grabber

@export var body_loadout: CharacterLoadout
@export var faction_id := 0

var player_id: int = -1

var move_input: Vector2 = Vector2.ZERO
var look_yaw: float = 0.0
var look_pitch: float = 0.0
var wants_jump: bool = false
var jump_sequence := 0
var trip_sequence := 0
var ragdoll_active := false
var trip_recovery_remaining := 0.0
var trip_direction := Vector3.FORWARD
var authoritative_ragdoll_anchor
var pending_jump_audio_prediction_key := 0
var on_floor := false
var grab_movement_multiplier := 1.0
var body_movement_multiplier := 1.0
var body_jump_multiplier := 1.0
var health := MAX_HEALTH
var stamina := MAX_STAMINA
var stamina_recovery_delay_remaining := 0.0
var is_actually_running := false
var inventory_entries: Array[Dictionary] = []
var equipment_entries: Dictionary = {}
var selected_inventory_slot := 0
var inventory_revision := 0
var _cached_public_inventory_revision := -1
var _cached_public_inventory: Dictionary = {}
var weapon_fire_cooldown_remaining := 0.0
var weapon_reload_remaining := 0.0
var weapon_reload_duration := 0.0
var weapon_reload_slot := -1
var weapon_reload_insert_emitted := false
var weapon_reload_insert_sound_id: StringName = &""
var primary_action_held := false
var primary_audio_prediction_session := 0
var primary_audio_prediction_shot_index := 1
var weapon_rng := RandomNumberGenerator.new()
var gait := PlayerGait.new()
var expression_clock := 0.0
var footstep_surface: StringName = &"concrete"
var interaction_hint := ""
var vision_distortion_remaining := 0.0
var vision_distortion_duration := 0.0
var vision_distortion_warp := 0.0
var vision_distortion_glitch := 0.0
var vision_distortion_smear := 0.0
var vision_distortion_center := DEFAULT_DISTORTION_CENTER
var vision_distortion_pulse_hz := DEFAULT_DISTORTION_PULSE_HZ
var edit_aim_active := false
var edit_aim_origin := Vector3.ZERO
var edit_aim_hit := Vector3.ZERO
var edit_aim_color := Color(0.2, 0.8, 1.0, 1.0)
var wrist_interface_open := false
var wrist_display_page: StringName = FIELDLINK_DISPLAY_STATE.PAGE_HOME
var last_requested_wrist_sound_msec := PackedInt64Array([
	-100000,
	-100000,
	-100000,
	-100000,
])
var last_echolocation_click_msec := -100000
var echolocation_click_refill_msec := -1
var echolocation_click_tokens := ECHOLOCATION_CLICK_BURST_CAPACITY


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_stop_on_slope = true
	floor_constant_speed = false
	floor_block_on_wall = true

	platform_floor_layers = 0
	platform_wall_layers = 0

	safe_margin = COLLISION_SAFE_MARGIN

	if collision_shape_3d.shape != null:
		collision_shape_3d.shape = collision_shape_3d.shape.duplicate(true)

	grabber.make_capability_unique()
	grabber.load_changed.connect(_on_grab_load_changed)
	authoritative_ragdoll_anchor = PLAYER_RAGDOLL_ANCHOR.new()
	authoritative_ragdoll_anchor.name = "AuthoritativeRagdollAnchor"
	add_child(authoritative_ragdoll_anchor)
	authoritative_ragdoll_anchor.add_collision_exception_with(self)

	if body_loadout != null:
		body_loadout = body_loadout.duplicate(true) as CharacterLoadout

	_apply_body_loadout()
	_install_default_equipment()

func setup(_player_id: int, spawn_pos: Vector3) -> void:
	player_id = _player_id
	global_position = spawn_pos
	velocity = Vector3.ZERO
	weapon_rng.seed = (
		WEAPON_RANDOM_SEED_BASE
		+ player_id * PLAYER_RANDOM_SEED_FACTOR
	)
	
func request_jump(local_prediction_key := 0) -> void:
	wants_jump = true
	pending_jump_audio_prediction_key = LOCAL_AUDIO_PREDICTION.sanitize_key(
		local_prediction_key
	)

func set_input(
	input: Vector2,
	yaw: float,
	pitch: float,
	running: bool
) -> void:
	move_input = input.limit_length(1.0)
	look_yaw = yaw
	look_pitch = clampf(
		pitch,
		deg_to_rad(-MAX_LOOK_PITCH_DEGREES),
		deg_to_rad(MAX_LOOK_PITCH_DEGREES)
	)
	wants_run = running
	grabber.rotation.x = look_pitch


func set_look_direction(yaw: float, pitch: float) -> void:
	look_yaw = yaw
	look_pitch = clampf(
		pitch,
		deg_to_rad(-MAX_LOOK_PITCH_DEGREES),
		deg_to_rad(MAX_LOOK_PITCH_DEGREES)
	)
	rotation.y = look_yaw
	grabber.rotation.x = look_pitch


func set_primary_action_held(value: bool, prediction_session := 0) -> void:
	primary_action_held = value and not wrist_interface_open
	if not primary_action_held:
		primary_audio_prediction_session = 0
		primary_audio_prediction_shot_index = 1
		return
	primary_audio_prediction_session = clampi(
		prediction_session,
		0,
		LOCAL_AUDIO_PREDICTION.WEAPON_MAX_SESSION
	)
	primary_audio_prediction_shot_index = 1


func current_automatic_audio_prediction_key() -> int:
	if primary_audio_prediction_session <= 0:
		return 0
	return LOCAL_AUDIO_PREDICTION.weapon_shot_key(
		primary_audio_prediction_session,
		primary_audio_prediction_shot_index
	)


func advance_automatic_audio_prediction() -> void:
	primary_audio_prediction_shot_index = mini(
		primary_audio_prediction_shot_index + 1,
		LOCAL_AUDIO_PREDICTION.WEAPON_MAX_SHOT
	)


func set_wrist_interface_open(value: bool, local_prediction_key := 0) -> bool:
	var next_open := value and has_equipped_wrist_device() and not ragdoll_active
	if next_open == wrist_interface_open:
		return false
	wrist_interface_open = next_open
	_emit_wrist_device_sound(
		&"fieldlink_open" if wrist_interface_open else &"fieldlink_close",
		local_prediction_key
	)
	if not wrist_interface_open:
		return true
	set_primary_action_held(false)
	return true


func set_wrist_display_page(page_value: Variant) -> bool:
	if not wrist_interface_open or not has_equipped_wrist_device():
		return false
	var next_page := FIELDLINK_DISPLAY_STATE.sanitize_page(page_value)
	if next_page == wrist_display_page:
		return false
	wrist_display_page = next_page
	return true


func request_wrist_device_sound(
	sound_id: StringName,
	local_prediction_key := 0
) -> bool:
	if not wrist_interface_open or not has_equipped_wrist_device():
		return false
	var cue_index := _requested_wrist_sound_index(sound_id)
	if cue_index < 0:
		return false
	var now_msec := Time.get_ticks_msec()
	var cooldown_msec := _requested_wrist_sound_cooldown_msec(cue_index)
	if (
		now_msec - last_requested_wrist_sound_msec[cue_index]
		< cooldown_msec
	):
		return false
	last_requested_wrist_sound_msec[cue_index] = now_msec
	_emit_wrist_device_sound(sound_id, local_prediction_key)
	return true


func request_echolocation_click(local_prediction_key := 0) -> bool:
	var now_msec := Time.get_ticks_msec()
	if echolocation_click_refill_msec < 0:
		echolocation_click_refill_msec = now_msec
	else:
		var elapsed_msec := maxi(now_msec - echolocation_click_refill_msec, 0)
		echolocation_click_tokens = minf(
			ECHOLOCATION_CLICK_BURST_CAPACITY,
			echolocation_click_tokens
			+ float(elapsed_msec)
			* ECHOLOCATION_CLICK_REFILL_PER_SECOND
			/ 1000.0
		)
		echolocation_click_refill_msec = now_msec
	if (
		now_msec - last_echolocation_click_msec
		< ECHOLOCATION_CLICK_MIN_INTERVAL_MSEC
		or echolocation_click_tokens < 1.0
	):
		return false
	echolocation_click_tokens -= 1.0
	last_echolocation_click_msec = now_msec
	_emit_echolocation_click(local_prediction_key)
	return true


static func _requested_wrist_sound_index(sound_id: StringName) -> int:
	match sound_id:
		&"fieldlink_hover":
			return 0
		&"fieldlink_click":
			return 1
		&"fieldlink_confirm":
			return 2
		&"fieldlink_warning":
			return 3
		_:
			return -1


static func _requested_wrist_sound_cooldown_msec(cue_index: int) -> int:
	match cue_index:
		0:
			return WRIST_SOUND_HOVER_COOLDOWN_MSEC
		1:
			return WRIST_SOUND_CLICK_COOLDOWN_MSEC
		_:
			return WRIST_SOUND_FEEDBACK_COOLDOWN_MSEC


func wants_automatic_fire() -> bool:
	if (
		not primary_action_held
		or wrist_interface_open
		or weapon_fire_cooldown_remaining > 0.0
		or weapon_reload_remaining > 0.0
		or body_loadout == null
		or not body_loadout.has_any_arm()
	):
		return false
	var entry := get_selected_inventory_entry()
	var definition := PlayerInventoryRules.get_definition(
		entry
	) as GunItemDefinition
	return (
		definition != null
		and definition.is_automatic(entry.get("instance_state", {}))
	)


func set_grab_capability(value: GrabCapability) -> void:
	grabber.set_capability(value, true)


func get_grab_capability() -> GrabCapability:
	return grabber.capability


func get_audio_listener_position() -> Vector3:
	# Aim/grab origin sits forward of the body and rotates around it. Using it as the listener made
	# turning in place move the authoritative ears through an 84 cm circle, crossing acoustic
	# boundaries without any player movement. Keep only the authored head height here.
	var listener_height := grabber.position.y if is_instance_valid(grabber) else 0.56
	return global_position + Vector3.UP * listener_height


func set_body_loadout(value: CharacterLoadout) -> void:
	body_loadout = (
		value.duplicate(true) as CharacterLoadout
		if value != null
		else CharacterLoadout.new()
	)
	_apply_body_loadout()


func install_limb(limb: LimbDefinition) -> void:
	body_loadout.install_limb(limb)
	_apply_body_loadout()


func remove_limb(slot: LimbDefinition.Slot) -> void:
	body_loadout.remove_limb(slot)
	_apply_body_loadout()


func set_edit_aim(
	active: bool,
	origin: Vector3,
	hit_position: Vector3,
	color: Color
) -> void:
	edit_aim_active = active
	edit_aim_origin = origin
	edit_aim_hit = hit_position
	edit_aim_color = color


func _apply_body_loadout() -> void:
	if body_loadout == null:
		body_loadout = CharacterLoadout.new()

	var arm_strength := body_loadout.get_grab_strength_multiplier()
	grabber.strength_multiplier = arm_strength
	grabber.enabled = arm_strength > 0.0

	body_movement_multiplier = body_loadout.get_movement_multiplier()
	body_jump_multiplier = body_loadout.get_jump_multiplier()

	if body_movement_multiplier <= 0.0 and arm_strength > 0.0:
		body_movement_multiplier = ARM_CRAWL_MOVEMENT_MULTIPLIER

	var box_shape := collision_shape_3d.shape as BoxShape3D
	if box_shape != null:
		box_shape.size.y = (
			LEGLESS_COLLISION_HEIGHT
			if not body_loadout.has_any_leg()
			else STANDING_COLLISION_HEIGHT
		)


func _on_grab_load_changed(
	mobility_multiplier: float,
	_shared_mass: float,
	_is_immovable: bool
) -> void:
	grab_movement_multiplier = mobility_multiplier


func _install_default_equipment() -> void:
	var changed := false
	if not equipment_entries.has(PlayerInventoryRules.EYES_SLOT):
		var eye_entry := PlayerInventoryRules.make_entry(DEFAULT_EYES)
		if not eye_entry.is_empty():
			equipment_entries[PlayerInventoryRules.EYES_SLOT] = eye_entry
			changed = true
	if not equipment_entries.has(PlayerInventoryRules.WRIST_DEVICE_SLOT):
		var wrist_entry := PlayerInventoryRules.make_entry(
			DEFAULT_WRIST_DEVICE
		)
		if not wrist_entry.is_empty():
			equipment_entries[PlayerInventoryRules.WRIST_DEVICE_SLOT] = wrist_entry
			changed = true
	if changed:
		_mark_inventory_changed()


func _mark_inventory_changed() -> void:
	inventory_revision += 1
	_cached_public_inventory_revision = -1
	inventory_changed.emit(inventory_revision)


func get_inventory_capacity() -> int:
	return PlayerInventoryRules.get_capacity(equipment_entries)


func get_selected_inventory_entry() -> Dictionary:
	if (
		selected_inventory_slot < 0
		or selected_inventory_slot >= inventory_entries.size()
	):
		return {}
	return inventory_entries[selected_inventory_slot]


func select_inventory_slot(slot_index: int) -> void:
	var next_slot := clampi(
		slot_index,
		0,
		maxi(get_inventory_capacity() - 1, 0)
	)
	if next_slot != selected_inventory_slot:
		_cancel_weapon_reload()
		selected_inventory_slot = next_slot
		_mark_inventory_changed()


func try_store_inventory_entry(entry: Dictionary) -> bool:
	if entry.is_empty() or inventory_entries.size() >= get_inventory_capacity():
		return false
	if PlayerInventoryRules.get_definition(entry) == null:
		return false
	inventory_entries.append(entry.duplicate(true))
	selected_inventory_slot = clampi(
		selected_inventory_slot,
		0,
		maxi(get_inventory_capacity() - 1, 0)
	)
	_mark_inventory_changed()
	return true


func try_equip_world_entry(entry: Dictionary) -> Dictionary:
	var definition := PlayerInventoryRules.get_equippable_definition(entry)
	if definition == null or not definition.can_equip():
		return {"success": false}

	var slot := str(definition.equipment_slot)
	var next_equipment := equipment_entries.duplicate(true)
	next_equipment[slot] = entry.duplicate(true)
	if not PlayerInventoryRules.can_fit(
		inventory_entries.size(),
		next_equipment
	):
		return {"success": false}

	var displaced: Dictionary = equipment_entries.get(slot, {}).duplicate(true)
	equipment_entries[slot] = entry.duplicate(true)
	if slot == PlayerInventoryRules.WRIST_DEVICE_SLOT:
		set_wrist_interface_open(false)
	_mark_inventory_changed()
	return {
		"success": true,
		"slot": slot,
		"displaced": displaced,
	}


func try_equip_inventory_entry(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= inventory_entries.size():
		return {"success": false}

	var entry: Dictionary = inventory_entries[slot_index]
	var definition := PlayerInventoryRules.get_equippable_definition(entry)
	if definition == null or not definition.can_equip():
		return {"success": false}

	var equipment_slot := str(definition.equipment_slot)
	var displaced: Dictionary = equipment_entries.get(
		equipment_slot,
		{}
	).duplicate(true)
	var next_inventory := inventory_entries.duplicate(true)
	next_inventory.remove_at(slot_index)
	if not displaced.is_empty():
		next_inventory.append(displaced)

	var next_equipment := equipment_entries.duplicate(true)
	next_equipment[equipment_slot] = entry.duplicate(true)
	if not PlayerInventoryRules.can_fit(
		next_inventory.size(),
		next_equipment
	):
		return {"success": false}

	inventory_entries = next_inventory
	equipment_entries = next_equipment
	if equipment_slot == PlayerInventoryRules.WRIST_DEVICE_SLOT:
		set_wrist_interface_open(false)
	selected_inventory_slot = clampi(
		slot_index,
		0,
		maxi(get_inventory_capacity() - 1, 0)
	)
	_mark_inventory_changed()
	return {
		"success": true,
		"slot": equipment_slot,
		"displaced": {},
	}


func try_unequip_to_world(equipment_slot: String) -> Dictionary:
	var entry: Dictionary = equipment_entries.get(
		equipment_slot,
		{}
	).duplicate(true)
	if entry.is_empty():
		return {}

	var next_equipment := equipment_entries.duplicate(true)
	next_equipment.erase(equipment_slot)
	if not PlayerInventoryRules.can_fit(
		inventory_entries.size(),
		next_equipment
	):
		return {}

	equipment_entries = next_equipment
	if equipment_slot == PlayerInventoryRules.WRIST_DEVICE_SLOT:
		set_wrist_interface_open(false)
	selected_inventory_slot = clampi(
		selected_inventory_slot,
		0,
		maxi(get_inventory_capacity() - 1, 0)
	)
	_mark_inventory_changed()
	return entry


func take_selected_inventory_entry() -> Dictionary:
	if (
		selected_inventory_slot < 0
		or selected_inventory_slot >= inventory_entries.size()
	):
		return {}
	var entry: Dictionary = inventory_entries[selected_inventory_slot]
	_cancel_weapon_reload()
	inventory_entries.remove_at(selected_inventory_slot)
	selected_inventory_slot = clampi(
		selected_inventory_slot,
		0,
		maxi(get_inventory_capacity() - 1, 0)
	)
	_mark_inventory_changed()
	return entry


func try_fire_selected_gun() -> Dictionary:
	var entry := get_selected_inventory_entry()
	var definition := PlayerInventoryRules.get_definition(
		entry
	) as GunItemDefinition
	if definition == null:
		return {"handled": false, "fired": false}
	if (
		body_loadout == null
		or not body_loadout.has_any_arm()
		or weapon_fire_cooldown_remaining > 0.0
		or weapon_reload_remaining > 0.0
	):
		return {"handled": true, "fired": false}

	var state: Dictionary = entry.get("instance_state", {})
	state = definition.normalize_instance_state(state)
	var build := definition.get_build(state)
	var profiles := build.get_ballistic_profiles()
	if profiles.is_empty():
		return {"handled": true, "fired": false}
	var available_rounds := int(state.get("rounds", 0))
	if available_rounds <= 0:
		begin_reload_selected_gun()
		return {"handled": true, "fired": false}
	var fired_barrel_count := mini(profiles.size(), available_rounds)
	var fired_profiles: Array[Dictionary] = []
	for profile_index: int in range(fired_barrel_count):
		fired_profiles.append(profiles[profile_index])
	var profile: Dictionary = fired_profiles[0]

	entry["instance_state"] = definition.consume_rounds(
		state,
		fired_barrel_count
	)
	inventory_entries[selected_inventory_slot] = entry
	_mark_inventory_changed()
	weapon_fire_cooldown_remaining = (
		1.0 / maxf(float(profile.get("rounds_per_second", 1.0)), 0.1)
	)
	return {
		"handled": true,
		"fired": true,
		"profile": profile,
		"profiles": fired_profiles,
		"fired_barrel_count": fired_barrel_count,
		"installed_barrel_count": profiles.size(),
		"spread_degrees": float(profile.get("spread_degrees", 0.0)),
		"fire_sound": build.get_fire_sound_profile(),
	}


func begin_reload_selected_gun() -> bool:
	if weapon_reload_remaining > 0.0:
		return false
	var entry := get_selected_inventory_entry()
	var definition := PlayerInventoryRules.get_definition(
		entry
	) as GunItemDefinition
	if definition == null:
		return false
	var state := definition.normalize_instance_state(
		entry.get("instance_state", {})
	)
	var build := definition.get_build(state)
	var capacity := build.get_magazine_capacity()
	if (
		not build.is_compatible()
		or capacity <= 0
		or int(state.get("rounds", 0)) >= capacity
	):
		return false
	weapon_reload_duration = build.get_reload_seconds()
	weapon_reload_remaining = weapon_reload_duration
	weapon_reload_slot = selected_inventory_slot
	weapon_reload_insert_emitted = false
	weapon_reload_insert_sound_id = build.get_reload_sound_id(true)
	var reload_out_sound_id := build.get_reload_sound_id(false)
	if not reload_out_sound_id.is_empty():
		_emit_gameplay_sound(reload_out_sound_id, 28.0, 0.55)
	return true


func apply_weapon_spread(
	direction: Vector3,
	spread_degrees: float
) -> Vector3:
	if spread_degrees <= 0.0001:
		return direction.normalized()
	var forward := direction.normalized()
	var right := forward.cross(Vector3.UP)
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var up := right.cross(forward).normalized()
	var radius := tan(deg_to_rad(spread_degrees))
	var angle := weapon_rng.randf_range(0.0, TAU)
	var distance := sqrt(weapon_rng.randf()) * radius
	return (
		forward
		+ right * cos(angle) * distance
		+ up * sin(angle) * distance
	).normalized()


func _update_weapon_state(delta: float) -> void:
	weapon_fire_cooldown_remaining = maxf(
		weapon_fire_cooldown_remaining - delta,
		0.0
	)
	if weapon_reload_remaining <= 0.0:
		return
	weapon_reload_remaining = maxf(weapon_reload_remaining - delta, 0.0)
	if (
		not weapon_reload_insert_emitted
		and weapon_reload_remaining
		<= weapon_reload_duration * RELOAD_INSERT_SOUND_REMAINING_RATIO
	):
		weapon_reload_insert_emitted = true
		if not weapon_reload_insert_sound_id.is_empty():
			_emit_gameplay_sound(
				weapon_reload_insert_sound_id,
				28.0,
				0.55
			)
	if weapon_reload_remaining > 0.0:
		return
	if (
		weapon_reload_slot < 0
		or weapon_reload_slot >= inventory_entries.size()
		or weapon_reload_slot != selected_inventory_slot
	):
		_cancel_weapon_reload()
		return
	var entry: Dictionary = inventory_entries[weapon_reload_slot]
	var definition := PlayerInventoryRules.get_definition(
		entry
	) as GunItemDefinition
	if definition != null:
		entry["instance_state"] = definition.refill_magazine(
			entry.get("instance_state", {})
		)
		inventory_entries[weapon_reload_slot] = entry
		_mark_inventory_changed()
	_cancel_weapon_reload()


func _cancel_weapon_reload() -> void:
	weapon_reload_remaining = 0.0
	weapon_reload_duration = 0.0
	weapon_reload_slot = -1
	weapon_reload_insert_emitted = false
	weapon_reload_insert_sound_id = &""


func spill_all_item_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in inventory_entries:
		result.append(entry.duplicate(true))
	for entry_value: Variant in equipment_entries.values():
		var entry: Dictionary = entry_value
		if not entry.is_empty():
			result.append(entry.duplicate(true))
	var had_entries := not inventory_entries.is_empty() or not equipment_entries.is_empty()
	inventory_entries.clear()
	equipment_entries.clear()
	if had_entries:
		_mark_inventory_changed()
	set_wrist_interface_open(false)
	return result


func has_equipped_eyes() -> bool:
	var eye_entry: Dictionary = equipment_entries.get(
		PlayerInventoryRules.EYES_SLOT,
		{}
	)
	return PlayerInventoryRules.get_definition(eye_entry) is EyeDefinition


func has_equipped_wrist_device() -> bool:
	var wrist_entry: Dictionary = equipment_entries.get(
		PlayerInventoryRules.WRIST_DEVICE_SLOT,
		{}
	)
	var definition := PlayerInventoryRules.get_equippable_definition(
		wrist_entry
	)
	return (
		definition != null
		and definition.equipment_slot == &"wrist_device"
	)


func has_special_sight(effect_id: StringName) -> bool:
	var eye_entry: Dictionary = equipment_entries.get(
		PlayerInventoryRules.EYES_SLOT,
		{}
	)
	var eyes := PlayerInventoryRules.get_definition(
		eye_entry
	) as EyeDefinition
	return eyes != null and eyes.has_special_sight(effect_id)


func set_interaction_hint(value: String) -> void:
	interaction_hint = value


func apply_damage(amount: float) -> float:
	var applied := clampf(amount, 0.0, health)
	health -= applied
	return applied


func heal(amount: float) -> float:
	var previous := health
	health = clampf(health + maxf(amount, 0.0), 0.0, MAX_HEALTH)
	return health - previous


func apply_vision_distortion(
	warp: float,
	glitch: float,
	smear: float,
	duration: float,
	center: Vector2 = DEFAULT_DISTORTION_CENTER,
	pulse_hz: float = DEFAULT_DISTORTION_PULSE_HZ
) -> void:
	var bounded_duration := clampf(
		duration,
		0.0,
		MAX_DISTORTION_DURATION
	)
	if bounded_duration <= 0.0:
		return
	vision_distortion_warp = maxf(
		vision_distortion_warp,
		clampf(warp, 0.0, 1.0)
	)
	vision_distortion_glitch = maxf(
		vision_distortion_glitch,
		clampf(glitch, 0.0, 1.0)
	)
	vision_distortion_smear = maxf(
		vision_distortion_smear,
		clampf(smear, 0.0, 1.0)
	)
	vision_distortion_remaining = maxf(
		vision_distortion_remaining,
		bounded_duration
	)
	vision_distortion_duration = maxf(
		vision_distortion_duration,
		bounded_duration
	)
	vision_distortion_center = Vector2(
		clampf(center.x, 0.0, 1.0),
		clampf(center.y, 0.0, 1.0)
	)
	vision_distortion_pulse_hz = clampf(
		pulse_hz,
		MIN_DISTORTION_PULSE_HZ,
		MAX_DISTORTION_PULSE_HZ
	)


func _update_vitals(
	delta: float,
	has_move_input: bool,
	was_on_floor: bool
) -> void:
	is_actually_running = (
		wants_run
		and has_move_input
		and was_on_floor
		and stamina > STAMINA_EMPTY_THRESHOLD
	)
	if is_actually_running:
		stamina = maxf(
			stamina - RUN_STAMINA_DRAIN_PER_SECOND * delta,
			0.0
		)
		stamina_recovery_delay_remaining = STAMINA_RECOVERY_DELAY
		if stamina <= STAMINA_EMPTY_THRESHOLD:
			is_actually_running = false
		return

	stamina_recovery_delay_remaining = maxf(
		stamina_recovery_delay_remaining - delta,
		0.0
	)
	if stamina_recovery_delay_remaining <= 0.0:
		stamina = minf(
			stamina + STAMINA_RECOVERY_PER_SECOND * delta,
			MAX_STAMINA
		)


func _update_vision_distortion(delta: float) -> void:
	vision_distortion_remaining = maxf(
		vision_distortion_remaining - delta,
		0.0
	)
	if vision_distortion_remaining > 0.0:
		return
	vision_distortion_duration = 0.0
	vision_distortion_warp = 0.0
	vision_distortion_glitch = 0.0
	vision_distortion_smear = 0.0


func _get_vision_distortion_state() -> Dictionary:
	if vision_distortion_remaining <= 0.0:
		return {
			"warp": 0.0,
			"glitch": 0.0,
			"smear": 0.0,
			"center": vision_distortion_center,
			"pulse_hz": vision_distortion_pulse_hz,
		}

	var fade_duration := minf(
		maxf(
			vision_distortion_duration * DISTORTION_FADE_DURATION_RATIO,
			MIN_DISTORTION_FADE_DURATION
		),
		MAX_DISTORTION_FADE_DURATION
	)
	var fade := clampf(
		vision_distortion_remaining / fade_duration,
		0.0,
		1.0
	)
	return {
		"warp": vision_distortion_warp * fade,
		"glitch": vision_distortion_glitch * fade,
		"smear": vision_distortion_smear * fade,
		"center": vision_distortion_center,
		"pulse_hz": vision_distortion_pulse_hz,
	}


func _get_public_inventory_state() -> Dictionary:
	if _cached_public_inventory_revision == inventory_revision:
		return _cached_public_inventory
	var public_inventory: Array[Dictionary] = []
	for entry: Dictionary in inventory_entries:
		public_inventory.append(PlayerInventoryRules.to_public_entry(entry))

	var public_equipment: Dictionary = {}
	for slot_value: Variant in equipment_entries.keys():
		var slot := str(slot_value)
		var entry: Dictionary = equipment_entries[slot_value]
		public_equipment[slot] = PlayerInventoryRules.to_public_entry(entry)

	_cached_public_inventory = {
		"capacity": get_inventory_capacity(),
		"selected_slot": selected_inventory_slot,
		"entries": public_inventory,
		"equipment": public_equipment,
	}
	_cached_public_inventory_revision = inventory_revision
	return _cached_public_inventory

func server_physics_tick(delta: float) -> void:
	# A server-owned presentation clock gives every peer the same slow breathing/weight-shift phase
	# without replicating bones. It advances through ragdoll and stationary states so late joins do
	# not restart a character's expression loop.
	expression_clock += maxf(delta, 0.0)
	rotation.y = look_yaw
	var was_ragdoll_active := ragdoll_active
	_update_trip_state(delta)
	if ragdoll_active:
		_update_authoritative_ragdoll(delta)
		return
	if was_ragdoll_active:
		# Recovery placed and re-enabled the character capsule this tick. Resume ordinary movement on
		# the following physics frame instead of moving a collider while its deferred state is changing.
		return
	
	var was_on_floor := on_floor
	on_floor = false

	var has_move_input := (
		move_input.length_squared()
		> MOVEMENT_INPUT_THRESHOLD_SQUARED
	)
	_update_vitals(delta, has_move_input, was_on_floor)
	_update_vision_distortion(delta)
	_update_weapon_state(delta)

	var jump_velocity := (
		JUMP_VELOCITY
		* grab_movement_multiplier
		* body_jump_multiplier
	)
	var is_launching := (
		was_on_floor
		and wants_jump
		and jump_velocity > 0.0
	)
	var can_air_run := (
		not was_on_floor
		and wants_run
		and stamina > STAMINA_EMPTY_THRESHOLD
	)
	var movement_speed := (
		RUN_SPEED
		if is_actually_running or can_air_run
		else WALK_SPEED
	)
	movement_speed *= grab_movement_multiplier
	movement_speed *= body_movement_multiplier

	var direction := _movement_direction(move_input, look_yaw)
	var horizontal_velocity := calculate_horizontal_velocity(
		velocity,
		direction,
		movement_speed,
		was_on_floor and not is_launching,
		delta
	)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	var constrained_velocity := grabber.constrain_horizontal_velocity(
		Vector3(velocity.x, 0.0, velocity.z)
	)
	velocity.x = constrained_velocity.x
	velocity.z = constrained_velocity.z

	if was_on_floor:
		air_time = 0.0

		if is_launching:
			jump_sequence += 1
			velocity.y = jump_velocity
			if jump_velocity > LANDING_MIN_IMPACT_SPEED:
				_emit_gameplay_sound(
					_jump_sound_id(footstep_surface),
					JUMP_SOUND_MAX_DISTANCE,
					JUMP_SOUND_PRIORITY,
					pending_jump_audio_prediction_key
				)
		else:
			velocity.y = FLOOR_STICK_VELOCITY
	else:
		air_time += delta
		velocity.y = maxf(
			velocity.y - GRAVITY * delta,
			-MAX_FALL_SPEED
		)

	wants_jump = false
	pending_jump_audio_prediction_key = 0

	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	_move_and_collide_with_slide(
		horizontal_motion,
		was_on_floor and not is_launching
	)

	var landing_impact_speed := maxf(-velocity.y, 0.0)
	var vertical_motion := Vector3(0.0, velocity.y, 0.0) * delta
	var vertical_col := move_and_collide(vertical_motion)

	if vertical_col:
		var normal := vertical_col.get_normal()

		if normal.y > FLOOR_CONTACT_NORMAL_Y:
			on_floor = true
			footstep_surface = _get_footstep_surface(vertical_col.get_collider())
			var contacted_from_air := not was_on_floor
			var accepted_landing := (
				contacted_from_air
				and air_time >= LANDING_MIN_AIR_TIME
				and landing_impact_speed >= LANDING_MIN_IMPACT_SPEED
			)
			if accepted_landing:
				_emit_gameplay_sound(
					_landing_sound_id(footstep_surface),
					LANDING_SOUND_MAX_DISTANCE,
					LANDING_SOUND_PRIORITY
				)
			if (
				contacted_from_air
				and air_time >= TRIP_MIN_AIR_TIME
				and _landing_lacks_required_support()
			):
				_begin_trip()
			if velocity.y < 0.0:
				velocity.y = 0.0

		_try_push_body(vertical_col)
	_update_footsteps(delta)


func _update_trip_state(delta: float) -> void:
	if not ragdoll_active:
		return
	trip_recovery_remaining = maxf(
		trip_recovery_remaining - maxf(delta, 0.0),
		0.0
	)
	if trip_recovery_remaining > 0.0:
		return
	_recover_from_trip()


func _begin_trip() -> void:
	if ragdoll_active:
		return
	ragdoll_active = true
	trip_sequence += 1
	trip_recovery_remaining = TRIP_RECOVERY_SECONDS
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	trip_direction = (
		horizontal_velocity.normalized()
		if horizontal_velocity.length_squared() > MOVEMENT_INPUT_THRESHOLD_SQUARED
		else -global_basis.z
	)
	# Deterministic lateral imbalance stops repeated straight-down mannequin falls while keeping all
	# peers on the same expressive trip direction.
	var lateral_sign := -1.0 if posmod(trip_sequence + player_id, 2) == 0 else 1.0
	trip_direction = (
		trip_direction + global_basis.x * lateral_sign * 0.28
	).normalized()
	wrist_interface_open = false
	set_primary_action_held(false)
	move_input = Vector2.ZERO
	wants_run = false
	wants_jump = false
	collision_shape_3d.set_deferred("disabled", true)
	if authoritative_ragdoll_anchor != null:
		authoritative_ragdoll_anchor.activate(
			global_transform,
			velocity,
			trip_direction,
			trip_sequence
		)


func _update_authoritative_ragdoll(delta: float) -> void:
	move_input = Vector2.ZERO
	wants_run = false
	wants_jump = false
	primary_action_held = false
	on_floor = false
	_update_vitals(delta, false, false)
	_update_vision_distortion(delta)
	_update_weapon_state(delta)
	if (
		authoritative_ragdoll_anchor == null
		or not authoritative_ragdoll_anchor.is_active()
	):
		return
	global_position = authoritative_ragdoll_anchor.get_player_reference_position()
	velocity = authoritative_ragdoll_anchor.linear_velocity


func _recover_from_trip() -> void:
	var anchor_velocity := velocity
	var anchor_position := global_position
	if (
		authoritative_ragdoll_anchor != null
		and authoritative_ragdoll_anchor.is_active()
	):
		anchor_velocity = authoritative_ragdoll_anchor.linear_velocity
		anchor_position = authoritative_ragdoll_anchor.get_player_reference_position()
	var recovery := _find_ragdoll_recovery(anchor_position)
	if not bool(recovery.get("valid", false)):
		# A low ceiling or occupied capsule volume is not a valid place to stand. Keep simulating the
		# physical body and retry next tick instead of enabling a CharacterBody inside geometry.
		return
	global_position = recovery.get("position", anchor_position) as Vector3
	on_floor = bool(recovery.get("on_floor", false))
	velocity = anchor_velocity if anchor_velocity.is_finite() else Vector3.ZERO
	if on_floor:
		velocity.y = 0.0
		air_time = 0.0
	if authoritative_ragdoll_anchor != null:
		authoritative_ragdoll_anchor.deactivate()
	collision_shape_3d.set_deferred("disabled", false)
	trip_recovery_remaining = 0.0
	ragdoll_active = false


func _find_ragdoll_recovery(anchor_position: Vector3) -> Dictionary:
	if not anchor_position.is_finite() or not is_inside_tree() or get_world_3d() == null:
		return {"valid": false}
	var facing := -Basis(Vector3.UP, look_yaw).z
	var right := Basis(Vector3.UP, look_yaw).x
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		facing * TRIP_RECOVERY_SEARCH_RADIUS,
		-facing * TRIP_RECOVERY_SEARCH_RADIUS,
		right * TRIP_RECOVERY_SEARCH_RADIUS,
		-right * TRIP_RECOVERY_SEARCH_RADIUS,
	]
	var found_ground := false
	for offset: Vector3 in offsets:
		var candidate := _grounded_recovery_position(anchor_position + offset)
		if not candidate.is_finite():
			continue
		found_ground = true
		if _is_recovery_space_clear(candidate):
			return {"valid": true, "position": candidate, "on_floor": true}
	if found_ground:
		return {"valid": false}
	# Falling off an edge remains a real fall. Continue from the physical torso rather than teleporting
	# to the last grounded position; normal CharacterBody gravity takes over on the next frame.
	return {"valid": true, "position": anchor_position, "on_floor": false}


func _grounded_recovery_position(horizontal_position: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = horizontal_position + Vector3.UP * TRIP_RECOVERY_GROUND_PROBE_UP
	query.to = horizontal_position - Vector3.UP * TRIP_RECOVERY_GROUND_PROBE_DOWN
	query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	query.collide_with_areas = false
	query.exclude = _ragdoll_recovery_exclusions()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var normal := hit.get("normal", Vector3.ZERO) as Vector3
	if normal.y < FLOOR_CONTACT_NORMAL_Y:
		return Vector3.INF
	var ground_position := hit.get("position", horizontal_position) as Vector3
	return Vector3(
		horizontal_position.x,
		ground_position.y + _standing_collision_half_height() + TRIP_RECOVERY_CLEARANCE,
		horizontal_position.z
	)


func _is_recovery_space_clear(position_value: Vector3) -> bool:
	if collision_shape_3d == null or collision_shape_3d.shape == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision_shape_3d.shape
	query.transform = Transform3D(
		Basis(Vector3.UP, look_yaw),
		position_value
	) * collision_shape_3d.transform
	query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	query.collide_with_areas = false
	query.margin = COLLISION_SAFE_MARGIN
	query.exclude = _ragdoll_recovery_exclusions()
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _ragdoll_recovery_exclusions() -> Array[RID]:
	var result: Array[RID] = [get_rid()]
	if authoritative_ragdoll_anchor != null:
		result.append(authoritative_ragdoll_anchor.get_collision_rid())
	return result


func _standing_collision_half_height() -> float:
	var box := collision_shape_3d.shape as BoxShape3D
	if box != null:
		return box.size.y * 0.5 - collision_shape_3d.position.y
	return STANDING_COLLISION_HEIGHT * 0.5


func _landing_lacks_required_support() -> bool:
	# A one-legged loadout has no phantom second foot to fail. Its locomotion can use the same
	# independent contact contract, while a genuine biped must find support under both landing feet.
	if (
		body_loadout == null
		or body_loadout.left_leg == null
		or body_loadout.right_leg == null
	):
		return false
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var forward_lead := horizontal_velocity * TRIP_SUPPORT_FORWARD_LEAD_SECONDS
	forward_lead = forward_lead.limit_length(TRIP_SUPPORT_MAX_FORWARD_LEAD)
	var left_supported := _has_landing_support(
		-global_basis.x * TRIP_SUPPORT_LATERAL_OFFSET + forward_lead
	)
	var right_supported := _has_landing_support(
		global_basis.x * TRIP_SUPPORT_LATERAL_OFFSET + forward_lead
	)
	return not left_supported or not right_supported


func _has_landing_support(horizontal_offset: Vector3) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.new()
	query.from = global_position + horizontal_offset + Vector3.UP * TRIP_SUPPORT_PROBE_UP
	query.to = global_position + horizontal_offset - Vector3.UP * TRIP_SUPPORT_PROBE_DOWN
	query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	return normal.y > FLOOR_CONTACT_NORMAL_Y


static func _movement_direction(input: Vector2, yaw: float) -> Vector3:
	if input.length_squared() <= MOVEMENT_INPUT_THRESHOLD_SQUARED:
		return Vector3.ZERO
	var basis := Basis(Vector3.UP, yaw)
	return (
		basis.x * input.x
		+ basis.z * input.y
	).normalized()


static func calculate_horizontal_velocity(
	current_velocity: Vector3,
	wish_direction: Vector3,
	wish_speed: float,
	grounded: bool,
	delta: float
) -> Vector3:
	var horizontal := Vector3(
		current_velocity.x,
		0.0,
		current_velocity.z
	)
	var direction := Vector3(wish_direction.x, 0.0, wish_direction.z)
	if direction.length_squared() > MOVEMENT_INPUT_THRESHOLD_SQUARED:
		direction = direction.normalized()
	else:
		direction = Vector3.ZERO

	var bounded_delta := maxf(delta, 0.0)
	var bounded_speed := maxf(wish_speed, 0.0)
	if grounded:
		var target_velocity := direction * bounded_speed
		var acceleration := (
			GROUND_DECELERATION
			if direction == Vector3.ZERO
			else GROUND_ACCELERATION
		)
		return horizontal.move_toward(
			target_velocity,
			acceleration * bounded_delta
		)

	# Air input can redirect momentum or build only as far as ordinary movement
	# speed. Faster takeoff momentum cannot be increased further, and releasing the
	# controls preserves horizontal velocity exactly.
	if direction == Vector3.ZERO or bounded_speed <= 0.0:
		return horizontal
	var original_speed := horizontal.length()
	var projected_speed := horizontal.dot(direction)
	var available_speed := bounded_speed - projected_speed
	if available_speed <= 0.0:
		return horizontal
	var control_delta := minf(
		available_speed,
		AIR_CONTROL_ACCELERATION * bounded_delta
	)
	var controlled := horizontal + direction * control_delta
	var maximum_speed := maxf(original_speed, bounded_speed)
	if controlled.length_squared() > maximum_speed * maximum_speed:
		controlled = controlled.normalized() * maximum_speed
	return controlled


func _update_footsteps(delta: float) -> void:
	if ragdoll_active:
		gait.advance(0.0, false, false, delta)
		return
	var horizontal_speed_squared := velocity.x * velocity.x + velocity.z * velocity.z
	var completed_steps := gait.advance(
		sqrt(horizontal_speed_squared),
		on_floor,
		is_actually_running,
		delta
	)
	if completed_steps <= 0:
		return
	_emit_gameplay_sound(
		_footstep_sound_id(footstep_surface),
		FOOTSTEP_MAX_DISTANCE,
		FOOTSTEP_PRIORITY,
		LOCAL_AUDIO_PREDICTION.gait_step_key(gait.step_sequence)
	)
	# Foot support is event-driven like the gait itself: two bounded rays at a real footfall, never a
	# polling cost on every physics frame. If the new foot has nowhere to land, authority trips once.
	if _landing_lacks_required_support():
		_begin_trip()


static func _get_footstep_surface(collider: Object) -> StringName:
	return PHYSICAL_SURFACE.from_collider(collider)


static func _footstep_sound_id(surface: StringName) -> StringName:
	return PHYSICAL_SURFACE.footstep_sound_id(surface)


static func _jump_sound_id(surface: StringName) -> StringName:
	return PHYSICAL_SURFACE.jump_sound_id(surface)


static func _landing_sound_id(surface: StringName) -> StringName:
	return PHYSICAL_SURFACE.landing_sound_id(surface)


func _emit_gameplay_sound(
	sound_id: StringName,
	max_distance: float,
	priority: float,
	local_prediction_key := 0
) -> void:
	if not multiplayer.is_server():
		return
	var server := get_node_or_null("/root/Server")
	if server == null or not server.has_method("emit_spatial_sound"):
		return
	server.call(
		"emit_spatial_sound",
		sound_id,
		global_position + Vector3.UP * 0.35,
		max_distance,
		0.0,
		null,
		priority,
		-1.0,
		player_id,
		local_prediction_key
	)


func _emit_wrist_device_sound(
	sound_id: StringName,
	local_prediction_key := 0
) -> void:
	if not multiplayer.is_server():
		return
	var server := get_node_or_null("/root/Server")
	if server == null or not server.has_method("emit_spatial_sound"):
		return
	var profile := LOCAL_AUDIO_PREDICTION.player_cue_profile(sound_id)
	if profile.is_empty():
		return
	server.call(
		"emit_spatial_sound",
		sound_id,
		get_audio_listener_position()
		+ Vector3.UP * WRIST_SOUND_SOURCE_HEIGHT_OFFSET,
		float(profile["max_distance"]),
		float(profile["volume_db"]),
		null,
		float(profile["priority"]),
		float(profile["pressure_strength"]),
		player_id,
		local_prediction_key
	)


func _emit_echolocation_click(local_prediction_key := 0) -> void:
	if not multiplayer.is_server():
		return
	var server := get_node_or_null("/root/Server")
	if server == null or not server.has_method("emit_spatial_sound"):
		return
	var profile := LOCAL_AUDIO_PREDICTION.player_cue_profile(&"mouth_click")
	if profile.is_empty():
		return
	server.call(
		"emit_spatial_sound",
		&"mouth_click",
		get_audio_listener_position(),
		float(profile["max_distance"]),
		float(profile["volume_db"]),
		null,
		float(profile["priority"]),
		float(profile["pressure_strength"]),
		player_id,
		local_prediction_key
	)

func _try_push_body(col: KinematicCollision3D) -> void:
	var body := col.get_collider()

	if body is RigidBody3D:
		var push_dir := Vector3(velocity.x, 0.0, velocity.z)

		if push_dir.length_squared() > MOVEMENT_INPUT_THRESHOLD_SQUARED:
			var mass_factor := sqrt(max(body.mass, MIN_PUSH_BODY_MASS))
			var impulse_strength := PUSH_IMPULSE_STRENGTH / mass_factor

			body.apply_central_impulse(push_dir.normalized() * impulse_strength)

func _move_and_collide_with_slide(
	motion: Vector3,
	allow_step_up := false
) -> void:
	if motion.length_squared() < MOTION_THRESHOLD_SQUARED:
		return

	var col := move_and_collide(motion)

	if col == null:
		return
	if allow_step_up and _try_step_up(col):
		return

	_try_push_body(col)
	velocity = horizontal_velocity_after_wall_collision(
		velocity,
		col.get_normal()
	)

	var remainder := col.get_remainder()
	var slide_motion := remainder.slide(col.get_normal())

	if slide_motion.length_squared() > MOTION_THRESHOLD_SQUARED:
		var col2 := move_and_collide(slide_motion)
		if col2:
			_try_push_body(col2)
			velocity = horizontal_velocity_after_wall_collision(
				velocity,
				col2.get_normal()
			)


func _try_step_up(blocking_collision: KinematicCollision3D) -> bool:
	if (
		blocking_collision == null
		or blocking_collision.get_normal().y > FLOOR_CONTACT_NORMAL_Y
	):
		return false
	var blocking_collider := blocking_collision.get_collider()
	if blocking_collider is RigidBody3D or blocking_collider is CharacterBody3D:
		return false
	var remainder := blocking_collision.get_remainder()
	remainder.y = 0.0
	if remainder.length_squared() < MOTION_THRESHOLD_SQUARED:
		return false

	# The original horizontal move has already advanced to the obstruction. Try
	# the remaining motion from one bounded step higher, then probe back down for
	# a real walkable top. Any failed branch restores the exact blocked pose.
	var blocked_transform := global_transform
	var blocked_height := global_position.y
	var up_collision := move_and_collide(Vector3.UP * MAX_STEP_HEIGHT)
	if up_collision != null:
		global_transform = blocked_transform
		return false

	var raised_position := global_position
	var forward_collision := move_and_collide(remainder)
	var forward_delta := global_position - raised_position
	forward_delta.y = 0.0
	if forward_delta.length_squared() < MIN_STEP_FORWARD_PROGRESS_SQUARED:
		global_transform = blocked_transform
		return false

	var down_collision := move_and_collide(
		Vector3.DOWN * (MAX_STEP_HEIGHT + STEP_DOWN_PROBE_DISTANCE)
	)
	if (
		down_collision == null
		or down_collision.get_normal().y <= FLOOR_CONTACT_NORMAL_Y
		or down_collision.get_collider() is RigidBody3D
		or down_collision.get_collider() is CharacterBody3D
		or global_position.y - blocked_height < MIN_STEP_RISE
	):
		global_transform = blocked_transform
		return false

	on_floor = true
	footstep_surface = _get_footstep_surface(down_collision.get_collider())
	if forward_collision != null:
		_try_push_body(forward_collision)
		velocity = horizontal_velocity_after_wall_collision(
			velocity,
			forward_collision.get_normal()
		)
	return true


static func horizontal_velocity_after_wall_collision(
	current_velocity: Vector3,
	collision_normal: Vector3
) -> Vector3:
	if absf(collision_normal.y) >= FLOOR_CONTACT_NORMAL_Y:
		return current_velocity
	var wall_normal := Vector3(
		collision_normal.x,
		0.0,
		collision_normal.z
	)
	if wall_normal.length_squared() <= MOTION_THRESHOLD_SQUARED:
		return current_velocity
	wall_normal = wall_normal.normalized()
	var inward_speed := current_velocity.dot(wall_normal)
	if inward_speed >= 0.0:
		return current_velocity
	return current_velocity - wall_normal * inward_speed


func to_state_dict(include_inventory := true) -> Dictionary:
	var state := {
		"player_id": player_id,
		"pos": global_position,
		"rot": global_rotation,
		"vel": velocity,
		"on_floor": on_floor,
		"jump_sequence": jump_sequence,
		"ragdoll_active": ragdoll_active,
		"trip_sequence": trip_sequence,
		"trip_direction": trip_direction,
		"gait_cycle": gait.get_cycle(),
		"gait_stride_distance": gait.stride_distance,
		"gait_active": gait.active,
		"expression_clock": expression_clock,
		"footstep_surface": footstep_surface,
		"health_ratio": health / MAX_HEALTH,
		"stamina_ratio": stamina / MAX_STAMINA,
		"inventory_revision": inventory_revision,
		"interaction_hint": interaction_hint,
		"vision_distortion": _get_vision_distortion_state(),
		"weapon_reload_ratio": (
			weapon_reload_remaining / weapon_reload_duration
			if weapon_reload_duration > RELOAD_DURATION_THRESHOLD
			else 0.0
		),
		"limbs": body_loadout.to_state_dict(),
		"edit_aim_active": edit_aim_active,
		"edit_aim_origin": edit_aim_origin,
		"edit_aim_hit": edit_aim_hit,
		"edit_aim_color": edit_aim_color,
		"faction_id": faction_id,
		"wrist_interface_open": wrist_interface_open,
		"wrist_display_page": wrist_display_page,
	}
	if include_inventory:
		state["inventory"] = _get_public_inventory_state()
	return state
