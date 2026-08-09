class_name ServerPlayer
extends CharacterBody3D

const WALK_SPEED := 8.5
const RUN_SPEED := 13.5

const GRAVITY := 24.0
const JUMP_VELOCITY := 10.0
const FALL_GRAVITY_RAMP := 2.0
const MAX_GRAVITY_MULT := 3.0
const ARM_CRAWL_MOVEMENT_MULTIPLIER := 0.2
const STANDING_COLLISION_HEIGHT := 1.979
const LEGLESS_COLLISION_HEIGHT := 1.1
const MAX_HEALTH := 100.0
const MAX_STAMINA := 100.0
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
const MIN_PUSH_BODY_MASS := 0.1
const PUSH_IMPULSE_STRENGTH := 4.0
const RELOAD_DURATION_THRESHOLD := 0.001
const DISTORTION_FADE_DURATION_RATIO := 0.3
const MIN_DISTORTION_FADE_DURATION := 0.08
const MAX_DISTORTION_FADE_DURATION := 1.2
const DEFAULT_EYES := preload(
	"res://resources/items/eyes/factory_oculars.tres"
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
var weapon_fire_cooldown_remaining := 0.0
var weapon_reload_remaining := 0.0
var weapon_reload_duration := 0.0
var weapon_reload_slot := -1
var weapon_rng := RandomNumberGenerator.new()
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

	if body_loadout != null:
		body_loadout = body_loadout.duplicate(true) as CharacterLoadout

	_apply_body_loadout()
	_install_default_eyes()

func setup(_player_id: int, spawn_pos: Vector3) -> void:
	player_id = _player_id
	global_position = spawn_pos
	velocity = Vector3.ZERO
	weapon_rng.seed = (
		WEAPON_RANDOM_SEED_BASE
		+ player_id * PLAYER_RANDOM_SEED_FACTOR
	)
	
func request_jump() -> void:
	wants_jump = true

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


func set_grab_capability(value: GrabCapability) -> void:
	grabber.set_capability(value, true)


func get_grab_capability() -> GrabCapability:
	return grabber.capability


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


func _install_default_eyes() -> void:
	if equipment_entries.has(PlayerInventoryRules.EYES_SLOT):
		return
	var entry := PlayerInventoryRules.make_entry(DEFAULT_EYES)
	if not entry.is_empty():
		equipment_entries[PlayerInventoryRules.EYES_SLOT] = entry


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
	selected_inventory_slot = clampi(
		slot_index,
		0,
		maxi(get_inventory_capacity() - 1, 0)
	)
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
	selected_inventory_slot = clampi(
		selected_inventory_slot,
		0,
		maxi(get_inventory_capacity() - 1, 0)
	)
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
	var profile := build.get_ballistic_profile()
	if profile.is_empty():
		return {"handled": true, "fired": false}
	if int(state.get("rounds", 0)) <= 0:
		begin_reload_selected_gun()
		return {"handled": true, "fired": false}

	entry["instance_state"] = definition.consume_round(state)
	inventory_entries[selected_inventory_slot] = entry
	weapon_fire_cooldown_remaining = (
		1.0 / maxf(float(profile.get("rounds_per_second", 1.0)), 0.1)
	)
	return {
		"handled": true,
		"fired": true,
		"profile": profile,
		"spread_degrees": float(profile.get("spread_degrees", 0.0)),
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
	_cancel_weapon_reload()


func _cancel_weapon_reload() -> void:
	weapon_reload_remaining = 0.0
	weapon_reload_duration = 0.0
	weapon_reload_slot = -1


func spill_all_item_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in inventory_entries:
		result.append(entry.duplicate(true))
	for entry_value: Variant in equipment_entries.values():
		var entry: Dictionary = entry_value
		if not entry.is_empty():
			result.append(entry.duplicate(true))
	inventory_entries.clear()
	equipment_entries.clear()
	return result


func has_equipped_eyes() -> bool:
	var eye_entry: Dictionary = equipment_entries.get(
		PlayerInventoryRules.EYES_SLOT,
		{}
	)
	return PlayerInventoryRules.get_definition(eye_entry) is EyeDefinition


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
	var public_inventory: Array[Dictionary] = []
	for entry: Dictionary in inventory_entries:
		public_inventory.append(PlayerInventoryRules.to_public_entry(entry))

	var public_equipment: Dictionary = {}
	for slot_value: Variant in equipment_entries.keys():
		var slot := str(slot_value)
		var entry: Dictionary = equipment_entries[slot_value]
		public_equipment[slot] = PlayerInventoryRules.to_public_entry(entry)

	return {
		"capacity": get_inventory_capacity(),
		"selected_slot": selected_inventory_slot,
		"entries": public_inventory,
		"equipment": public_equipment,
	}

func server_physics_tick(delta: float) -> void:
	rotation.y = look_yaw
	
	var was_on_floor := on_floor
	on_floor = false

	var has_move_input := (
		move_input.length_squared()
		> MOVEMENT_INPUT_THRESHOLD_SQUARED
	)
	_update_vitals(delta, has_move_input, was_on_floor)
	_update_vision_distortion(delta)
	_update_weapon_state(delta)

	if has_move_input:
		var basis := Basis(Vector3.UP, look_yaw)
		var direction := (
			basis.x * move_input.x +
			basis.z * move_input.y
		).normalized()

		var speed := RUN_SPEED if is_actually_running else WALK_SPEED
		speed *= grab_movement_multiplier
		speed *= body_movement_multiplier

		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	var constrained_velocity := grabber.constrain_horizontal_velocity(
		Vector3(velocity.x, 0.0, velocity.z)
	)
	velocity.x = constrained_velocity.x
	velocity.z = constrained_velocity.z

	if was_on_floor:
		air_time = 0.0

		if wants_jump:
			velocity.y = (
				JUMP_VELOCITY
				* grab_movement_multiplier
				* body_jump_multiplier
			)
		else:
			velocity.y = FLOOR_STICK_VELOCITY
	else:
		air_time += delta

		var gravity_mult := 1.0 + air_time * FALL_GRAVITY_RAMP
		gravity_mult = min(gravity_mult, MAX_GRAVITY_MULT)

		velocity.y -= GRAVITY * gravity_mult * delta

	wants_jump = false

	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	_move_and_collide_with_slide(horizontal_motion)

	var vertical_motion := Vector3(0.0, velocity.y, 0.0) * delta
	var vertical_col := move_and_collide(vertical_motion)

	if vertical_col:
		var normal := vertical_col.get_normal()

		if normal.y > FLOOR_CONTACT_NORMAL_Y:
			on_floor = true
			if velocity.y < 0.0:
				velocity.y = 0.0

		_try_push_body(vertical_col)

func _try_push_body(col: KinematicCollision3D) -> void:
	var body := col.get_collider()

	if body is RigidBody3D:
		var push_dir := Vector3(velocity.x, 0.0, velocity.z)

		if push_dir.length_squared() > MOVEMENT_INPUT_THRESHOLD_SQUARED:
			var mass_factor := sqrt(max(body.mass, MIN_PUSH_BODY_MASS))
			var impulse_strength := PUSH_IMPULSE_STRENGTH / mass_factor

			body.apply_central_impulse(push_dir.normalized() * impulse_strength)

func _move_and_collide_with_slide(motion: Vector3) -> void:
	if motion.length_squared() < MOTION_THRESHOLD_SQUARED:
		return

	var col := move_and_collide(motion)

	if col == null:
		return

	_try_push_body(col)

	var remainder := col.get_remainder()
	var slide_motion := remainder.slide(col.get_normal())

	if slide_motion.length_squared() > MOTION_THRESHOLD_SQUARED:
		var col2 := move_and_collide(slide_motion)
		if col2:
			_try_push_body(col2)

func to_state_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"pos": global_position,
		"rot": global_rotation,
		"vel": velocity,
		"on_floor": on_floor,
		"health_ratio": health / MAX_HEALTH,
		"stamina_ratio": stamina / MAX_STAMINA,
		"inventory": _get_public_inventory_state(),
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
	}
