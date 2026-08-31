class_name ServerPlayer
extends CharacterBody3D

signal inventory_changed(revision: int)
signal jump_request_resolved(
	request_id: int,
	jump_accepted: bool,
	accepted_flip_direction: int
)
signal ragdoll_backpack_released(
	backpack_entry: Dictionary,
	spilled_entries: Array,
	release_position: Vector3,
	release_velocity: Vector3,
	release_direction: Vector3
)
signal died(player: ServerPlayer)

enum KickStyle {
	SINGLE,
	DROP,
}

const WALK_SPEED := 5.4
const RUN_SPEED := 13.5
const SPRINT_SPEED_RAMP_SECONDS := 1.5
const GROUND_ACCELERATION := 46.0
const GROUND_DECELERATION := 52.0
const SPRINT_RELEASE_DECELERATION := 5.5
const SPRINT_RELEASE_DIRECTION_DOT_MIN := 0.45
const AIR_CONTROL_ACCELERATION := 7.0

const GRAVITY := 24.0
const JUMP_VELOCITY := 10.0
const MAX_FALL_SPEED := 48.0
const FLIP_MIN_HORIZONTAL_SPEED := 9.0
const FLIP_DURATION_SECONDS := 0.68
const FRONT_FLIP_TAKEOFF_HORIZONTAL_MULTIPLIER := 1.16
const FRONT_FLIP_TAKEOFF_VERTICAL_MULTIPLIER := 1.02
const BACK_FLIP_TAKEOFF_VERTICAL_MULTIPLIER := 1.10
# Backflip traversal is authored as a range, not an arbitrary launch-speed subtraction. Extra
# vertical speed means extra airtime, so a fixed horizontal multiplier changes meaning whenever
# jump height changes. Solving from 70% of the corresponding ordinary jump keeps it the height
# option and leaves a deliberate safety margin below the frontflip-only course transfer.
const BACK_FLIP_TARGET_RANGE_RATIO := 0.70
const FLIP_AIR_MOMENTUM_DRAG := 0.08
const FLIP_AIR_REDIRECT_ACCELERATION := 18.0
const FLIP_MIN_SAFE_LANDING_PHASE := 0.84
const FLIP_BODY_IMPACT_TRIP_MIN_SPEED := 5.6
const FLIP_POST_IMPACT_VULNERABILITY_SECONDS := 0.35
const KICK_COOLDOWN_SECONDS := 0.75
const KICK_DURATION_SECONDS := 0.44
const KICK_STRIKE_PHASE := 0.48
const KICK_REACH_METERS := 0.96
const KICK_HIT_RADIUS := 0.31
const KICK_LATERAL_OFFSET := 0.13
const KICK_HIP_HEIGHT_OFFSET := -0.17
const KICK_FOOT_HEIGHT_OFFSET := -0.92
const KICK_BASE_IMPULSE := 5.4
const KICK_FORWARD_IMPULSE_SCALE := 0.58
const KICK_MOVEMENT_IMPULSE_SCALE := 0.16
const KICK_FLIP_IMPULSE_BONUS := 1.6
const KICK_MAX_IMPULSE := 13.5
const KICK_ENEMY_DAMAGE := 7.0
const KICK_SOUND_MAX_DISTANCE := 20.0
const KICK_SOUND_PRIORITY := 0.28
const KICK_GUIDANCE_QUERY_RADIUS := 1.15
const KICK_GUIDANCE_QUERY_FORWARD := 0.48
const KICK_GUIDANCE_QUERY_UP := 0.42
const KICK_GUIDANCE_MAX_DISTANCE := 1.48
const KICK_GUIDANCE_MIN_FORWARD_DOT := 0.50
const KICK_GUIDANCE_MIN_DIRECTION_DOT := 0.57
const KICK_GUIDANCE_MIN_WEIGHT := 0.20
const KICK_GUIDANCE_MAX_WEIGHT := 0.38
const KICK_GUIDANCE_MAX_RESULTS := 16
const KICK_GUIDANCE_MAX_SPOTS_PER_TARGET := 20
const RUNNING_KICK_BALANCE_MIN_SPEED := 7.2
const RUNNING_KICK_BALANCE_MAX_PROBABILITY := 0.34
const DROP_KICK_MIN_HORIZONTAL_SPEED := 8.4
const DROP_KICK_POSE_BUILD_SECONDS := 0.28
const DROP_KICK_CONTACT_ARM_PHASE := 0.72
const DROP_KICK_REACH_METERS := 1.02
const DROP_KICK_HIT_RADIUS := 0.38
const DROP_KICK_BODY_TRIP_MIN_SPEED := 4.6
const DROP_KICK_LANDING_TRIP_MIN_SPEED := 3.2
const DROP_KICK_BASE_IMPULSE := 8.0
const DROP_KICK_MOMENTUM_IMPULSE_SCALE := 0.72
const DROP_KICK_MAX_IMPULSE := 18.0
const DROP_KICK_CONTACT_RESTITUTION := 0.26
const DROP_KICK_REACTION_IMPULSE_TO_SPEED := 0.075
const DROP_KICK_TANGENTIAL_VELOCITY_RETENTION := 0.46
const DROP_KICK_MIN_REBOUND_SPEED := 1.1
const DROP_KICK_MAX_REBOUND_SPEED := 4.8
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
const SPRINT_EXHAUSTION_RECOVERY_RATIO := 0.12
const MOVEMENT_INPUT_THRESHOLD_SQUARED := 0.001
const MOTION_THRESHOLD_SQUARED := 0.000001
const FLOOR_CONTACT_NORMAL_Y := 0.6
const FLOOR_STICK_VELOCITY := -0.1
const MAX_STEP_HEIGHT := 0.28
const STEP_DOWN_PROBE_DISTANCE := 0.04
const MIN_STEP_RISE := 0.008
const MIN_STEP_FORWARD_PROGRESS_SQUARED := 0.000004
# Horizontal body response is driven by relative contact velocity, never by the sprint input. The
# squared-speed curve approximates kinetic load without needing a player mass allocation per hit.
const BODY_IMPACT_MIN_SPEED := 2.2
const BODY_IMPACT_FULL_SPEED := RUN_SPEED
const BODY_IMPACT_EVENT_COOLDOWN_SECONDS := 0.14
const LOW_OBSTACLE_TRIP_MIN_SPEED := 8.2
const TRIP_OBSTACLE_LOWER_PROBE_HEIGHT := 0.43
const TRIP_OBSTACLE_CLEARANCE_PROBE_HEIGHT := 0.92
const TRIP_OBSTACLE_PROBE_DISTANCE := 0.86
const MIN_PUSH_BODY_MASS := 0.1
const PUSH_IMPULSE_STRENGTH := 4.0
const RELOAD_DURATION_THRESHOLD := 0.001
const RELOAD_INSERT_SOUND_REMAINING_RATIO := 0.45
const FOOTSTEP_MAX_DISTANCE := 24.0
const FOOTSTEP_PRIORITY := 0.25
const FOOT_CONTACT_MIN_INTERVAL_MSEC := 85
const FOOT_CONTACT_MAX_SEQUENCE_LEAD := 2
const FOOT_CONTACT_PROBE_UP := 0.32
const FOOT_CONTACT_PROBE_DOWN := 1.38
const JUMP_SOUND_MAX_DISTANCE := 26.0
const JUMP_SOUND_PRIORITY := 0.35
const LANDING_SOUND_MAX_DISTANCE := 30.0
const LANDING_SOUND_PRIORITY := 0.4
const LANDING_MIN_AIR_TIME := 0.18
const LANDING_MIN_IMPACT_SPEED := 2.0
const LANDING_RESPONSE_MIN_SPEED := 3.0
const HARD_LANDING_TRIP_SPEED := 20.0
const TRIP_MIN_AIR_TIME := 0.05
const TRIP_RECOVERY_SECONDS := 1.65
const TRIP_SUPPORT_LATERAL_OFFSET := 0.22
const TRIP_SUPPORT_FORWARD_LEAD_SECONDS := 0.035
const TRIP_SUPPORT_MAX_FORWARD_LEAD := 0.22
const TRIP_SUPPORT_PROBE_UP := 0.30
const TRIP_SUPPORT_PROBE_DOWN := 1.35
const TRIP_RECOVERY_GROUND_PROBE_UP := 0.42
const TRIP_RECOVERY_GROUND_PROBE_DOWN := 3.2
const TRIP_RECOVERY_CLEARANCE := 0.035
const TRIP_RECOVERY_MAX_GROUND_RISE := 0.34
const TRIP_RECOVERY_SEARCH_RADIUS := 0.48
const TRIP_RECOVERY_SEARCH_RING_COUNT := 4
const TRIP_RECOVERY_SEARCH_SAMPLES := 12
const TRIP_RECOVERY_ROUTE_HEIGHT := 0.48
const TRIP_RECOVERY_RETRY_INTERVAL := 0.10
const TRIP_RECOVERY_FALLBACK_DELAY := 1.25
const TRIP_RECOVERY_FALLBACK_MAX_DISTANCE := 4.0
# Backpack retention is evaluated as one bounded per-trip failure probability. Contact-induced
# delta-velocity is the main load, while accumulated shocks, tumbling, and travel contribute less.
# Even a maximally violent ragdoll caps at 18%, so losing a pack stays an occasional consequence.
const RAGDOLL_BACKPACK_SHOCK_START := 2.8
const RAGDOLL_BACKPACK_SHOCK_FULL := 10.0
const RAGDOLL_BACKPACK_CUMULATIVE_START := 5.0
const RAGDOLL_BACKPACK_CUMULATIVE_FULL := 22.0
const RAGDOLL_BACKPACK_TUMBLE_START := 3.5
const RAGDOLL_BACKPACK_TUMBLE_FULL := 10.0
const RAGDOLL_BACKPACK_TRAVEL_START := 2.0
const RAGDOLL_BACKPACK_TRAVEL_FULL := 12.0
const RAGDOLL_BACKPACK_MAX_RELEASE_PROBABILITY := 0.18
const RAGDOLL_BACKPACK_PROBABILITY_EXPONENT := 1.65
const RAGDOLL_BACKPACK_SHOCK_NOISE_FLOOR := 0.35
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
var pending_flip_intent := 0
var pending_flip_run_committed := false
var pending_jump_request_id := 0
var flip_sequence := 0
var flip_direction := 0
var flip_active := false
var flip_phase := 0.0
var flip_elapsed := 0.0
var airborne_flip_direction := 0
var flip_impact_vulnerability_remaining := 0.0
var kick_sequence := 0
var kick_side := -1
var kick_style := KickStyle.SINGLE
var kick_active := false
var kick_phase := 1.0
var kick_clock := -1.0
var kick_direction := Vector3.FORWARD
var kick_view_yaw := 0.0
var kick_view_pitch := 0.0
var kick_flip_direction := 0
var dropkick_tilt_input := 0.0
var kick_guidance_direction := Vector3.FORWARD
var kick_guidance_weight := 0.0
var kick_intensity := 1.0
var kick_momentum_speed := 0.0
var kick_forward_momentum_speed := 0.0
var kick_cooldown_remaining := 0.0
var context_action_held := false
var _kick_elapsed := 0.0
var _kick_hit_resolved := false
var landing_sequence := 0
var landing_impact_strength := 0.0
var body_impact_sequence := 0
var body_impact_strength := 0.0
var body_impact_direction := Vector3.ZERO
var body_impact_contact_side := 0.0
var body_impact_clock := -1.0
var trip_sequence := 0
var ragdoll_active := false
var trip_recovery_remaining := 0.0
var trip_recovery_blocked_elapsed := 0.0
var trip_recovery_retry_remaining := 0.0
var trip_direction := Vector3.FORWARD
var last_safe_standing_position := Vector3.INF
var authoritative_ragdoll_anchor
var _ragdoll_backpack_previous_velocity := Vector3.ZERO
var _ragdoll_backpack_peak_shock := 0.0
var _ragdoll_backpack_cumulative_shock := 0.0
var _ragdoll_backpack_peak_angular_speed := 0.0
var _ragdoll_backpack_travel_distance := 0.0
var _ragdoll_backpack_release_sample := 1.0
var _ragdoll_gravity_acceleration := 9.8
var pending_jump_audio_prediction_key := 0
var on_floor := false
var grab_movement_multiplier := 1.0
var body_movement_multiplier := 1.0
var body_jump_multiplier := 1.0
var health := MAX_HEALTH
var death_pending := false
var stamina := MAX_STAMINA
var stamina_recovery_delay_remaining := 0.0
var is_actually_running := false
var sprint_exhausted := false
var sprint_speed_ramp_elapsed := 0.0
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
var last_foot_contact_sequence := -1
var last_foot_contact_msec := -100000
var _foot_contact_query := PhysicsRayQueryParameters3D.new()
var _body_impact_query := PhysicsRayQueryParameters3D.new()
var _kick_shape := SphereShape3D.new()
var _kick_query := PhysicsShapeQueryParameters3D.new()
var _kick_ray_query := PhysicsRayQueryParameters3D.new()
var _kick_guidance_shape := SphereShape3D.new()
var _kick_guidance_query := PhysicsShapeQueryParameters3D.new()
var _kick_guidance_spots: Array[Vector3] = []
var _dropkick_shape := SphereShape3D.new()
var _dropkick_query := PhysicsShapeQueryParameters3D.new()
var _body_impact_cooldown_remaining := 0.0
var _pending_body_impact_strength := 0.0
var _pending_body_impact_direction := Vector3.ZERO
var _pending_body_impact_contact_side := 0.0
var _pending_body_impact_velocity := Vector3.ZERO
var _pending_low_obstacle_trip := false
var _pending_flip_impact_trip := false
var _pending_dropkick_impact_trip := false
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
var plasma_cutter_trigger_held := false
var plasma_cutter_active := false
var plasma_cutter_overheated := false
var plasma_cutter_heat_ratio := 0.0
var plasma_cutter_pulse_remaining := 0.0
var plasma_cutter_pulse_ready := false
var plasma_cutter_has_hit := false
var plasma_cutter_hit_position := Vector3.ZERO
var plasma_cutter_ray_query: PhysicsRayQueryParameters3D
var plasma_cutter_ray_exclusions: Array[RID] = []
var _cached_plasma_cutter_inventory_revision := -1
var _cached_plasma_cutter_definition: Resource
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
	_ragdoll_gravity_acceleration = maxf(
		float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)),
		0.0
	)
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_stop_on_slope = true
	floor_constant_speed = false
	floor_block_on_wall = true

	platform_floor_layers = 0
	platform_wall_layers = 0
	_foot_contact_query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	_foot_contact_query.collide_with_areas = false
	_foot_contact_query.collide_with_bodies = true
	_foot_contact_query.exclude = [get_rid()]
	_body_impact_query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	_body_impact_query.collide_with_areas = false
	_body_impact_query.collide_with_bodies = true
	_body_impact_query.exclude = [get_rid()]
	_kick_shape.radius = KICK_HIT_RADIUS
	_kick_query.shape = _kick_shape
	_kick_query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	_kick_query.collide_with_areas = false
	_kick_query.collide_with_bodies = true
	_kick_ray_query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	_kick_ray_query.collide_with_areas = false
	_kick_ray_query.collide_with_bodies = true
	_kick_guidance_shape.radius = KICK_GUIDANCE_QUERY_RADIUS
	_kick_guidance_query.shape = _kick_guidance_shape
	_kick_guidance_query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	_kick_guidance_query.collide_with_areas = false
	_kick_guidance_query.collide_with_bodies = true
	_dropkick_shape.radius = DROP_KICK_HIT_RADIUS
	_dropkick_query.shape = _dropkick_shape
	_dropkick_query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	_dropkick_query.collide_with_areas = false
	_dropkick_query.collide_with_bodies = true

	safe_margin = COLLISION_SAFE_MARGIN

	if collision_shape_3d.shape != null:
		collision_shape_3d.shape = collision_shape_3d.shape.duplicate(true)

	grabber.make_capability_unique()
	grabber.load_changed.connect(_on_grab_load_changed)
	_install_authoritative_ragdoll_anchor()

	if body_loadout != null:
		body_loadout = body_loadout.duplicate(true) as CharacterLoadout

	_apply_body_loadout()
	_install_default_equipment()

func setup(_player_id: int, spawn_pos: Vector3) -> void:
	player_id = _player_id
	gait.set_expression_identity(player_id)
	global_position = spawn_pos
	last_safe_standing_position = spawn_pos
	velocity = Vector3.ZERO
	weapon_rng.seed = (
		WEAPON_RANDOM_SEED_BASE
		+ player_id * PLAYER_RANDOM_SEED_FACTOR
	)


func _install_authoritative_ragdoll_anchor() -> void:
	authoritative_ragdoll_anchor = PLAYER_RAGDOLL_ANCHOR.new()
	authoritative_ragdoll_anchor.name = "AuthoritativeRagdollAnchor"
	add_child(authoritative_ragdoll_anchor)
	authoritative_ragdoll_anchor.add_collision_exception_with(self)
	_refresh_self_collision_exclusions()


func _refresh_self_collision_exclusions() -> void:
	var exclusions: Array[RID] = [get_rid()]
	if authoritative_ragdoll_anchor != null:
		exclusions.append(authoritative_ragdoll_anchor.get_collision_rid())
	_kick_query.exclude = exclusions
	_kick_ray_query.exclude = exclusions
	_kick_guidance_query.exclude = exclusions
	_dropkick_query.exclude = exclusions


func detach_ragdoll_anchor_for_corpse(corpse_parent: Node) -> Node:
	if corpse_parent == null or authoritative_ragdoll_anchor == null:
		return null
	var corpse_anchor: Node = authoritative_ragdoll_anchor
	corpse_anchor.remove_collision_exception_with(self)
	corpse_anchor.reparent(corpse_parent, true)
	authoritative_ragdoll_anchor = null
	_install_authoritative_ragdoll_anchor()
	return corpse_anchor


func respawn_at(spawn_position: Vector3) -> void:
	var resumed_gait_sequence := (
		maxi(gait.step_sequence, last_foot_contact_sequence) + 1
	)
	if authoritative_ragdoll_anchor != null:
		authoritative_ragdoll_anchor.deactivate()
	death_pending = false
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	stamina_recovery_delay_remaining = 0.0
	sprint_exhausted = false
	sprint_speed_ramp_elapsed = 0.0
	is_actually_running = false
	global_position = spawn_position
	rotation = Vector3(0.0, look_yaw, 0.0)
	last_safe_standing_position = spawn_position
	velocity = Vector3.ZERO
	on_floor = false
	air_time = 0.0
	move_input = Vector2.ZERO
	wants_run = false
	wants_jump = false
	pending_flip_intent = 0
	pending_flip_run_committed = false
	pending_jump_request_id = 0
	pending_jump_audio_prediction_key = 0
	flip_direction = 0
	flip_active = false
	flip_phase = 0.0
	flip_elapsed = 0.0
	airborne_flip_direction = 0
	flip_impact_vulnerability_remaining = 0.0
	kick_active = false
	kick_phase = 1.0
	_kick_elapsed = 0.0
	_kick_hit_resolved = false
	kick_cooldown_remaining = 0.0
	ragdoll_active = false
	trip_recovery_remaining = 0.0
	trip_recovery_blocked_elapsed = 0.0
	trip_recovery_retry_remaining = 0.0
	primary_action_held = false
	context_action_held = false
	weapon_reload_remaining = 0.0
	weapon_reload_duration = 0.0
	weapon_reload_slot = -1
	weapon_reload_insert_emitted = false
	wrist_interface_open = false
	_reset_plasma_cutter_runtime(true)
	edit_aim_active = false
	_reset_pending_body_impact()
	gait = PlayerGait.new()
	gait.set_expression_identity(player_id)
	gait.reset_after_full_body_interruption(resumed_gait_sequence)
	last_foot_contact_msec = -100000
	collision_shape_3d.set_deferred("disabled", false)
	
func request_jump(
	local_prediction_key := 0,
	requested_flip_direction := 0,
	request_id := 0,
	flip_run_committed := false
) -> void:
	wants_jump = true
	pending_flip_intent = (
		0
		if wrist_interface_open
		else clampi(requested_flip_direction, -1, 1)
	)
	pending_flip_run_committed = (
		pending_flip_intent != 0
		and bool(flip_run_committed)
	)
	pending_jump_request_id = maxi(request_id, 0)
	pending_jump_audio_prediction_key = LOCAL_AUDIO_PREDICTION.sanitize_key(
		local_prediction_key
	)


func request_kick(
	preferred_side := -1,
	requested_dropkick_tilt_input: float = 0.0
) -> bool:
	# Kick is deliberately the lowest-priority action. It never interrupts a live technical
	# interface, weapon action, reload, ragdoll, or a higher-priority context interaction resolved by
	# Server before this method is called. A flip is not a rejection condition: airborne kicks are a
	# supported movement expression rather than a separate ability.
	if (
		ragdoll_active
		or wrist_interface_open
		or primary_action_held
		or weapon_reload_remaining > RELOAD_DURATION_THRESHOLD
		or kick_cooldown_remaining > 0.0
		or body_loadout == null
		or not body_loadout.has_any_leg()
	):
		return false
	kick_side = select_kick_side(
		preferred_side,
		body_loadout.left_leg != null,
		body_loadout.right_leg != null,
		gait.step_sequence
	)
	if kick_side < 0:
		return false
	kick_style = (
		KickStyle.DROP
		if _can_start_dropkick()
		else KickStyle.SINGLE
	)
	kick_sequence += 1
	kick_active = true
	kick_phase = 0.0
	kick_clock = expression_clock
	_kick_elapsed = 0.0
	_kick_hit_resolved = false
	kick_cooldown_remaining = KICK_COOLDOWN_SECONDS
	kick_view_yaw = look_yaw
	# A dropkick is aimed with the body, not welded to an extreme camera pitch. The player can still
	# look around freely after commitment; this only keeps the feet-forward launch anatomically sane.
	kick_view_pitch = (
		clampf(look_pitch, deg_to_rad(-18.0), deg_to_rad(12.0))
		if kick_style == KickStyle.DROP
		else look_pitch
	)
	kick_flip_direction = (
		0
		if kick_style == KickStyle.DROP
		else (
			airborne_flip_direction
			if airborne_flip_direction != 0
			else flip_direction if flip_active else 0
		)
	)
	dropkick_tilt_input = (
		clampf(requested_dropkick_tilt_input, -1.0, 1.0)
		if kick_style == KickStyle.DROP
		else 0.0
	)
	kick_direction = kick_direction_from_view(
		kick_view_yaw,
		kick_view_pitch,
		kick_flip_direction,
		flip_phase if kick_flip_direction != 0 else 0.0
	)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var horizontal_kick_direction := Vector3(
		kick_direction.x,
		0.0,
		kick_direction.z
	)
	if horizontal_kick_direction.length_squared() <= MOTION_THRESHOLD_SQUARED:
		horizontal_kick_direction = -global_basis.z
	horizontal_kick_direction = horizontal_kick_direction.normalized()
	kick_momentum_speed = horizontal_velocity.length()
	kick_forward_momentum_speed = maxf(
		horizontal_velocity.dot(horizontal_kick_direction),
		0.0
	)
	kick_intensity = kick_intensity_from_momentum(
		kick_forward_momentum_speed,
		kick_momentum_speed,
		kick_flip_direction != 0 or kick_style == KickStyle.DROP
	)
	kick_guidance_direction = kick_direction
	kick_guidance_weight = 0.0
	_select_kick_guidance()
	kick_direction = apply_kick_guidance(
		kick_direction,
		kick_guidance_direction,
		kick_guidance_weight
	)
	return true


func set_context_action_held(value: bool) -> void:
	context_action_held = value


func _can_start_dropkick() -> bool:
	return (
		context_action_held
		and not on_floor
		and (
			air_time > 0.0
			or absf(velocity.y) > LANDING_MIN_IMPACT_SPEED
		)
		and wants_run
		and Vector2(velocity.x, velocity.z).length()
		>= DROP_KICK_MIN_HORIZONTAL_SPEED
		and not flip_active
		and airborne_flip_direction == 0
		and body_loadout != null
		and body_loadout.left_leg != null
		and body_loadout.right_leg != null
	)


static func select_kick_side(
	preferred_side: int,
	has_left_leg: bool,
	has_right_leg: bool,
	gait_sequence: int
) -> int:
	if not has_left_leg and not has_right_leg:
		return -1
	if has_left_leg and not has_right_leg:
		return PlayerGait.FootSide.LEFT
	if has_right_leg and not has_left_leg:
		return PlayerGait.FootSide.RIGHT
	if (
		preferred_side == PlayerGait.FootSide.LEFT
		or preferred_side == PlayerGait.FootSide.RIGHT
	):
		return preferred_side
	# A missing/old client cannot choose from the presentation rig. Alternate deterministically from
	# the shared gait sequence so observers still agree and repeated stationary kicks use both legs.
	return (
		PlayerGait.FootSide.LEFT
		if posmod(gait_sequence, 2) == 0
		else PlayerGait.FootSide.RIGHT
	)


static func kick_direction_from_view(
	yaw: float,
	pitch: float,
	active_flip_direction: int,
	active_flip_phase: float
) -> Vector3:
	var safe_yaw := yaw if is_finite(yaw) else 0.0
	var safe_pitch := pitch if is_finite(pitch) else 0.0
	var flip_angle := (
		float(clampi(active_flip_direction, -1, 1))
		* clampf(active_flip_phase, 0.0, 1.0)
		* TAU
	)
	var direction := (
		Basis(Vector3.UP, safe_yaw)
		* Basis(Vector3.RIGHT, safe_pitch + flip_angle)
		* Vector3.FORWARD
	)
	return direction.normalized() if direction.is_finite() else Vector3.FORWARD


static func apply_kick_guidance(
	free_direction: Vector3,
	guide_direction: Vector3,
	guide_weight: float
) -> Vector3:
	var free := free_direction
	if not free.is_finite() or free.length_squared() <= MOTION_THRESHOLD_SQUARED:
		free = Vector3.FORWARD
	free = free.normalized()
	var guide := guide_direction
	var weight := clampf(guide_weight, 0.0, KICK_GUIDANCE_MAX_WEIGHT)
	if (
		weight <= 0.0
		or not guide.is_finite()
		or guide.length_squared() <= MOTION_THRESHOLD_SQUARED
	):
		return free
	# Guidance bends the committed free strike; it never replaces it. This preserves misses and avoids
	# a magnetic foot even when the target moves after the E press.
	return free.slerp(guide.normalized(), weight).normalized()


static func kick_intensity_from_momentum(
	forward_speed: float,
	total_speed: float,
	during_flip: bool
) -> float:
	var momentum_ratio := clampf(
		(
			maxf(forward_speed, 0.0) * 0.75
			+ maxf(total_speed, 0.0) * 0.25
		) / maxf(RUN_SPEED, 0.001),
		0.0,
		1.25
	)
	return clampf(
		1.0
		+ pow(momentum_ratio, 0.82) * 0.52
		+ (0.16 if during_flip else 0.0),
		1.0,
		1.72
	)


static func kick_impulse_from_momentum(
	forward_speed: float,
	total_speed: float,
	during_flip: bool
) -> float:
	return minf(
		KICK_BASE_IMPULSE
		+ pow(maxf(forward_speed, 0.0), 1.08) * KICK_FORWARD_IMPULSE_SCALE
		+ maxf(total_speed, 0.0) * KICK_MOVEMENT_IMPULSE_SCALE
		+ (KICK_FLIP_IMPULSE_BONUS if during_flip else 0.0),
		KICK_MAX_IMPULSE
	)


static func running_kick_balance_failure_probability(
	forward_speed: float,
	total_speed: float,
	contacted_target: bool
) -> float:
	var speed := maxf(total_speed, 0.0)
	if speed < RUNNING_KICK_BALANCE_MIN_SPEED:
		return 0.0
	var speed_ratio := clampf(
		inverse_lerp(
			RUNNING_KICK_BALANCE_MIN_SPEED,
			RUN_SPEED,
			speed
		),
		0.0,
		1.0
	)
	var forward_ratio := clampf(
		maxf(forward_speed, 0.0) / maxf(speed, 0.001),
		0.0,
		1.0
	)
	var contact_multiplier := 1.25 if contacted_target else 1.0
	return clampf(
		pow(speed_ratio, 1.55)
		* lerpf(0.68, 1.0, forward_ratio)
		* RUNNING_KICK_BALANCE_MAX_PROBABILITY
		* contact_multiplier,
		0.0,
		RUNNING_KICK_BALANCE_MAX_PROBABILITY
	)


static func dropkick_recoil_velocity(
	incoming_velocity: Vector3,
	contact_normal: Vector3,
	contact_velocity: Vector3,
	strike_direction: Vector3,
	strike_impulse: float
) -> Vector3:
	var safe_incoming := (
		incoming_velocity if incoming_velocity.is_finite() else Vector3.ZERO
	)
	var safe_contact_velocity := (
		contact_velocity if contact_velocity.is_finite() else Vector3.ZERO
	)
	var safe_direction := (
		strike_direction if strike_direction.is_finite() else Vector3.FORWARD
	)
	if safe_direction.length_squared() <= MOTION_THRESHOLD_SQUARED:
		safe_direction = Vector3.FORWARD
	safe_direction = safe_direction.normalized()
	var normal := contact_normal if contact_normal.is_finite() else -safe_direction
	if normal.length_squared() <= MOTION_THRESHOLD_SQUARED:
		normal = -safe_direction
	normal = normal.normalized()
	# Queries should return a normal facing the kicker. Correct malformed/fallback normals so the
	# reaction can never accelerate the player farther through the contacted surface.
	if normal.dot(safe_direction) > 0.0:
		normal = -normal
	var relative_velocity := safe_incoming - safe_contact_velocity
	var closing_speed := maxf(-relative_velocity.dot(normal), 0.0)
	var tangential_velocity := relative_velocity.slide(normal)
	var rebound_speed := clampf(
		closing_speed * DROP_KICK_CONTACT_RESTITUTION
		+ maxf(strike_impulse, 0.0) * DROP_KICK_REACTION_IMPULSE_TO_SPEED,
		DROP_KICK_MIN_REBOUND_SPEED,
		DROP_KICK_MAX_REBOUND_SPEED
	)
	var reaction := (
		safe_contact_velocity
		+ tangential_velocity * DROP_KICK_TANGENTIAL_VELOCITY_RETENTION
		+ normal * rebound_speed
	)
	# A braced two-foot strike lifts the collapsing body slightly, keeping the initial ragdoll from
	# being numerically pinned between the floor and the obstacle without inventing a second jump.
	if absf(normal.y) < 0.55:
		reaction.y += lerpf(
			0.20,
			0.55,
			clampf(
				closing_speed / maxf(DROP_KICK_MIN_HORIZONTAL_SPEED, 0.001),
				0.0,
				1.0
			)
		)
	return reaction


func append_kick_guidance_spots(output: Array[Vector3]) -> void:
	# Other players can use the same generic anatomy contract as enemies. These are hints rather than
	# hitboxes: contact is still resolved by the physics sweep at the strike frame.
	output.append(global_position + Vector3.UP * -0.68)
	output.append(global_position + Vector3.UP * -0.18)
	output.append(global_position + Vector3.UP * 0.34)


func _select_kick_guidance() -> void:
	if not is_inside_tree() or get_world_3d() == null:
		return
	var source_position := _kick_source_position()
	var foot_origin := _kick_foot_origin_position()
	var flat_forward := Vector3(kick_direction.x, 0.0, kick_direction.z)
	if flat_forward.length_squared() <= MOTION_THRESHOLD_SQUARED:
		flat_forward = -global_basis.z
	flat_forward = flat_forward.normalized()
	_kick_guidance_query.transform = Transform3D(
		Basis.IDENTITY,
		foot_origin
		+ flat_forward * KICK_GUIDANCE_QUERY_FORWARD
		+ Vector3.UP * KICK_GUIDANCE_QUERY_UP
	)
	var best_direction := kick_direction
	var best_score := INF
	var best_alignment := 0.0
	var best_distance := KICK_GUIDANCE_MAX_DISTANCE
	var space_state := get_world_3d().direct_space_state
	for result: Dictionary in space_state.intersect_shape(
		_kick_guidance_query,
		KICK_GUIDANCE_MAX_RESULTS
	):
		var candidate := result.get("collider") as Node3D
		if not _is_kick_guidance_candidate(candidate):
			continue
		_kick_guidance_spots.clear()
		if candidate.has_method("append_kick_guidance_spots"):
			candidate.call("append_kick_guidance_spots", _kick_guidance_spots)
		if _kick_guidance_spots.is_empty():
			_kick_guidance_spots.append(candidate.global_position)
		var candidate_spot_count := mini(
			_kick_guidance_spots.size(),
			KICK_GUIDANCE_MAX_SPOTS_PER_TARGET
		)
		for spot_index: int in range(candidate_spot_count):
			var spot := _kick_guidance_spots[spot_index]
			if not spot.is_finite():
				continue
			var offset := spot - source_position
			var distance := offset.length()
			if distance <= 0.08 or distance > KICK_GUIDANCE_MAX_DISTANCE:
				continue
			var spot_direction := offset / distance
			var flat_offset := Vector3(offset.x, 0.0, offset.z)
			if flat_offset.length_squared() <= MOTION_THRESHOLD_SQUARED:
				continue
			var forward_dot := flat_forward.dot(flat_offset.normalized())
			var direction_dot := kick_direction.dot(spot_direction)
			if (
				forward_dot < KICK_GUIDANCE_MIN_FORWARD_DOT
				or direction_dot < KICK_GUIDANCE_MIN_DIRECTION_DOT
			):
				continue
			_kick_ray_query.from = foot_origin
			_kick_ray_query.to = spot
			var sight_hit := space_state.intersect_ray(_kick_ray_query)
			if (
				not sight_hit.is_empty()
				and not _kick_hit_matches_candidate(
					sight_hit.get("collider") as Node,
					candidate
				)
			):
				continue
			# Spot choice is measured from the selected live-foot approximation, while its steering
			# direction is solved from the hip where the leg chain actually begins.
			var foot_distance := foot_origin.distance_to(spot)
			var score := foot_distance + (1.0 - direction_dot) * 0.32
			if score >= best_score:
				continue
			best_score = score
			best_direction = spot_direction
			best_alignment = direction_dot
			best_distance = foot_distance
	if not is_finite(best_score):
		return
	var proximity := 1.0 - clampf(
		(best_distance - 0.25) / (KICK_GUIDANCE_MAX_DISTANCE - 0.25),
		0.0,
		1.0
	)
	kick_guidance_direction = best_direction
	kick_guidance_weight = lerpf(
		KICK_GUIDANCE_MIN_WEIGHT,
		KICK_GUIDANCE_MAX_WEIGHT,
		clampf(proximity * 0.65 + best_alignment * 0.35, 0.0, 1.0)
	)


func _kick_source_position() -> Vector3:
	var side_sign := -1.0 if kick_side == PlayerGait.FootSide.LEFT else 1.0
	return (
		global_position
		+ Vector3.UP * KICK_HIP_HEIGHT_OFFSET
		+ global_basis.x * side_sign * KICK_LATERAL_OFFSET
	)


func _kick_foot_origin_position() -> Vector3:
	var side_sign := -1.0 if kick_side == PlayerGait.FootSide.LEFT else 1.0
	return (
		global_position
		+ Vector3.UP * KICK_FOOT_HEIGHT_OFFSET
		+ global_basis.x * side_sign * PlayerGait.FOOT_STANCE_HALF_WIDTH
	)


func _is_kick_guidance_candidate(candidate: Node3D) -> bool:
	if candidate == null or candidate == self:
		return false
	return (
		candidate is RigidBody3D
		or candidate is ServerPlayer
		or candidate.has_method("apply_damage")
		or candidate.is_in_group("kickable")
	)


func _kick_hit_matches_candidate(hit: Node, candidate: Node) -> bool:
	if hit == candidate:
		return true
	return (
		is_instance_valid(hit)
		and is_instance_valid(candidate)
		and (
			candidate.is_ancestor_of(hit)
			or hit.is_ancestor_of(candidate)
		)
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


func suspend_network_input() -> void:
	# The body remains authoritative during a reconnect lease, but no stale held action may continue
	# moving, firing, jumping, or manipulating an item after its transport route disappears.
	move_input = Vector2.ZERO
	wants_run = false
	wants_jump = false
	pending_flip_intent = 0
	pending_flip_run_committed = false
	pending_jump_request_id = 0
	pending_jump_audio_prediction_key = 0
	context_action_held = false
	set_primary_action_held(false)
	set_plasma_cutter_triggered(false)


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
		set_plasma_cutter_triggered(false)
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
	var next_open := (
		value
		and has_equipped_wrist_device()
		and not ragdoll_active
		and not flip_active
	)
	if next_open == wrist_interface_open:
		return false
	wrist_interface_open = next_open
	_emit_wrist_device_sound(
		&"fieldlink_open" if wrist_interface_open else &"fieldlink_close",
		local_prediction_key
	)
	if not wrist_interface_open:
		return true
	set_plasma_cutter_triggered(false)
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


func set_plasma_cutter_triggered(value: bool) -> bool:
	if not value:
		var changed := plasma_cutter_trigger_held or plasma_cutter_active
		plasma_cutter_trigger_held = false
		plasma_cutter_active = false
		plasma_cutter_pulse_ready = false
		plasma_cutter_has_hit = false
		return changed
	if (
		wrist_interface_open
		or ragdoll_active
		or death_pending
		or plasma_cutter_overheated
		or get_plasma_cutter_definition() == null
		or body_loadout == null
		or not body_loadout.has_any_arm()
	):
		return false
	if plasma_cutter_trigger_held:
		return false
	plasma_cutter_trigger_held = true
	plasma_cutter_active = true
	var cutter := get_plasma_cutter_definition()
	plasma_cutter_pulse_remaining = maxf(
		float(cutter.get("pulse_interval")) if cutter != null else 0.085,
		0.04
	)
	plasma_cutter_pulse_ready = true
	return true


func consume_plasma_cutter_pulse() -> bool:
	if not plasma_cutter_active or not plasma_cutter_pulse_ready:
		return false
	plasma_cutter_pulse_ready = false
	return true


func set_plasma_cutter_aim_result(
	endpoint: Vector3,
	has_hit: bool
) -> void:
	plasma_cutter_hit_position = endpoint if endpoint.is_finite() else global_position
	plasma_cutter_has_hit = has_hit and endpoint.is_finite()


func _update_plasma_cutter_thermal(delta: float) -> void:
	var cutter := get_plasma_cutter_definition()
	var usable := (
		cutter != null
		and not wrist_interface_open
		and not ragdoll_active
		and not death_pending
		and body_loadout != null
		and body_loadout.has_any_arm()
	)
	if not usable:
		plasma_cutter_trigger_held = false
		plasma_cutter_active = false
		plasma_cutter_pulse_ready = false
		plasma_cutter_has_hit = false
	else:
		plasma_cutter_active = (
			plasma_cutter_trigger_held and not plasma_cutter_overheated
		)
	var safe_delta := clampf(delta if is_finite(delta) else 0.0, 0.0, 0.1)
	if plasma_cutter_active:
		plasma_cutter_heat_ratio = minf(
			plasma_cutter_heat_ratio
			+ float(cutter.get("heat_per_second")) * safe_delta,
			1.0
		)
		if not plasma_cutter_pulse_ready:
			plasma_cutter_pulse_remaining -= safe_delta
		if not plasma_cutter_pulse_ready and plasma_cutter_pulse_remaining <= 0.0:
			plasma_cutter_pulse_ready = true
			plasma_cutter_pulse_remaining = maxf(
				float(cutter.get("pulse_interval")),
				0.04
			)
		if plasma_cutter_heat_ratio >= 1.0:
			plasma_cutter_overheated = true
			plasma_cutter_trigger_held = false
			plasma_cutter_active = false
			plasma_cutter_pulse_ready = false
			plasma_cutter_has_hit = false
	else:
		plasma_cutter_heat_ratio = maxf(
			plasma_cutter_heat_ratio
			- (
				float(cutter.get("cooling_per_second"))
				if cutter != null
				else 0.26
			) * safe_delta,
			0.0
		)
		plasma_cutter_pulse_remaining = 0.0
		plasma_cutter_pulse_ready = false
		plasma_cutter_has_hit = false
	if (
		plasma_cutter_overheated
		and cutter != null
		and plasma_cutter_heat_ratio
		<= float(cutter.get("overheat_recovery_ratio"))
	):
		plasma_cutter_overheated = false


func _reset_plasma_cutter_runtime(reset_heat: bool) -> void:
	plasma_cutter_trigger_held = false
	plasma_cutter_active = false
	plasma_cutter_overheated = false
	plasma_cutter_pulse_remaining = 0.0
	plasma_cutter_pulse_ready = false
	plasma_cutter_has_hit = false
	plasma_cutter_hit_position = global_position
	if reset_heat:
		plasma_cutter_heat_ratio = 0.0


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
		set_plasma_cutter_triggered(false)
		_cancel_weapon_reload()
		selected_inventory_slot = next_slot
		_mark_inventory_changed()


func cycle_inventory_slot(direction: int) -> bool:
	var backpack_entry: Dictionary = SafeVariant.dictionary_copy(
		equipment_entries.get(PlayerInventoryRules.BACKPACK_SLOT, {}),
		false
	)
	var backpack := (
		PlayerInventoryRules.get_definition(backpack_entry)
		as BackpackDefinition
	)
	if backpack == null:
		return false
	var step := signi(direction)
	if step == 0:
		return false
	var capacity := get_inventory_capacity()
	if capacity <= PlayerInventoryRules.BASE_CAPACITY:
		return false
	var next_slot := posmod(selected_inventory_slot + step, capacity)
	select_inventory_slot(next_slot)
	return next_slot == selected_inventory_slot


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


func release_backpack_for_ragdoll() -> Dictionary:
	var backpack_entry: Dictionary = SafeVariant.dictionary_copy(
		equipment_entries.get(PlayerInventoryRules.BACKPACK_SLOT, {}),
		true
	)
	var backpack := (
		PlayerInventoryRules.get_definition(backpack_entry)
		as BackpackDefinition
	)
	if backpack == null:
		return {}

	# The baseline pocket keeps one item. Everything that only fitted because of the backpack becomes
	# a physical world item; retaining the selected entry when possible keeps the outcome legible.
	var retained_index := (
		selected_inventory_slot
		if (
			selected_inventory_slot >= 0
			and selected_inventory_slot < inventory_entries.size()
		)
		else (0 if not inventory_entries.is_empty() else -1)
	)
	var retained_entries: Array[Dictionary] = []
	var spilled_entries: Array[Dictionary] = []
	for index: int in range(inventory_entries.size()):
		var entry := inventory_entries[index].duplicate(true)
		if index == retained_index:
			retained_entries.append(entry)
		else:
			spilled_entries.append(entry)
	_cancel_weapon_reload()
	inventory_entries = retained_entries
	equipment_entries.erase(PlayerInventoryRules.BACKPACK_SLOT)
	selected_inventory_slot = 0
	_mark_inventory_changed()
	return {
		"backpack": backpack_entry,
		"spilled": spilled_entries,
	}


static func ragdoll_backpack_release_probability(
	peak_specific_impulse: float,
	cumulative_specific_impulse: float,
	peak_angular_speed: float,
	travel_distance: float
) -> float:
	var peak_load := smoothstep(
		0.0,
		1.0,
		clampf(
			inverse_lerp(
				RAGDOLL_BACKPACK_SHOCK_START,
				RAGDOLL_BACKPACK_SHOCK_FULL,
				maxf(peak_specific_impulse, 0.0)
			),
			0.0,
			1.0
		)
	)
	var cumulative_load := smoothstep(
		0.0,
		1.0,
		clampf(
			inverse_lerp(
				RAGDOLL_BACKPACK_CUMULATIVE_START,
				RAGDOLL_BACKPACK_CUMULATIVE_FULL,
				maxf(cumulative_specific_impulse, 0.0)
			),
			0.0,
			1.0
		)
	)
	var tumble_load := smoothstep(
		0.0,
		1.0,
		clampf(
			inverse_lerp(
				RAGDOLL_BACKPACK_TUMBLE_START,
				RAGDOLL_BACKPACK_TUMBLE_FULL,
				maxf(peak_angular_speed, 0.0)
			),
			0.0,
			1.0
		)
	)
	var travel_load := smoothstep(
		0.0,
		1.0,
		clampf(
			inverse_lerp(
				RAGDOLL_BACKPACK_TRAVEL_START,
				RAGDOLL_BACKPACK_TRAVEL_FULL,
				maxf(travel_distance, 0.0)
			),
			0.0,
			1.0
		)
	)
	var combined_load := clampf(
		peak_load * 0.62
		+ cumulative_load * 0.18
		+ tumble_load * 0.14
		+ travel_load * 0.06,
		0.0,
		1.0
	)
	return (
		RAGDOLL_BACKPACK_MAX_RELEASE_PROBABILITY
		* pow(combined_load, RAGDOLL_BACKPACK_PROBABILITY_EXPONENT)
	)


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


func get_plasma_cutter_definition() -> Resource:
	if _cached_plasma_cutter_inventory_revision == inventory_revision:
		return _cached_plasma_cutter_definition
	var definition := PlayerInventoryRules.get_definition(
		get_selected_inventory_entry()
	)
	_cached_plasma_cutter_inventory_revision = inventory_revision
	if not definition is PlasmaCutterDefinition:
		_cached_plasma_cutter_definition = null
		return null
	_cached_plasma_cutter_definition = definition as PlasmaCutterDefinition
	(_cached_plasma_cutter_definition as PlasmaCutterDefinition).sanitize()
	return _cached_plasma_cutter_definition


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
	if health <= 0.0 and not death_pending:
		death_pending = true
		if not ragdoll_active:
			_begin_trip(velocity)
		died.emit(self)
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
	if (
		sprint_exhausted
		and stamina >= MAX_STAMINA * SPRINT_EXHAUSTION_RECOVERY_RATIO
	):
		sprint_exhausted = false
	var sprint_available := (
		not sprint_exhausted
		and stamina > STAMINA_EMPTY_THRESHOLD
	)
	is_actually_running = (
		wants_run
		and has_move_input
		and was_on_floor
		and sprint_available
	)
	sprint_speed_ramp_elapsed = advance_sprint_speed_ramp(
		sprint_speed_ramp_elapsed,
		wants_run and has_move_input and sprint_available,
		was_on_floor,
		delta
	)
	if is_actually_running:
		stamina = maxf(
			stamina - RUN_STAMINA_DRAIN_PER_SECOND * delta,
			0.0
		)
		stamina_recovery_delay_remaining = STAMINA_RECOVERY_DELAY
		if stamina <= STAMINA_EMPTY_THRESHOLD:
			sprint_exhausted = true
			is_actually_running = false
			sprint_speed_ramp_elapsed = 0.0
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
	_update_plasma_cutter_thermal(delta)
	_body_impact_cooldown_remaining = maxf(
		_body_impact_cooldown_remaining - maxf(delta, 0.0),
		0.0
	)
	flip_impact_vulnerability_remaining = maxf(
		flip_impact_vulnerability_remaining - maxf(delta, 0.0),
		0.0
	)
	kick_cooldown_remaining = maxf(
		kick_cooldown_remaining - maxf(delta, 0.0),
		0.0
	)
	_reset_pending_body_impact()
	rotation.y = look_yaw
	var was_ragdoll_active := ragdoll_active
	_update_trip_state(delta)
	if ragdoll_active:
		_reject_pending_jump_request()
		_update_authoritative_ragdoll(delta)
		return
	if was_ragdoll_active:
		# Recovery placed and re-enabled the character capsule this tick. Resume ordinary movement on
		# the following physics frame instead of moving a collider while its deferred state is changing.
		_reject_pending_jump_request()
		return
	_advance_flip_state(delta)
	_advance_kick_state(delta)
	
	var was_on_floor := on_floor
	on_floor = false

	var has_move_input := (
		move_input.length_squared()
		> MOVEMENT_INPUT_THRESHOLD_SQUARED
	)
	_update_vitals(delta, has_move_input, was_on_floor)
	var current_horizontal_speed := Vector2(velocity.x, velocity.z).length()
	gait.update_momentum_recovery(
		current_horizontal_speed,
		was_on_floor,
		is_actually_running,
		delta
	)
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
	var accepted_flip_direction := 0
	var can_air_run := (
		not was_on_floor
		and wants_run
		and stamina > STAMINA_EMPTY_THRESHOLD
	)
	var movement_speed := WALK_SPEED
	if is_actually_running or can_air_run:
		movement_speed = sprint_speed_at_elapsed(
			sprint_speed_ramp_elapsed
		)
	movement_speed *= grab_movement_multiplier
	movement_speed *= body_movement_multiplier

	var direction := _movement_direction(move_input, look_yaw)
	var horizontal_wish_speed := movement_speed
	if not was_on_floor and airborne_flip_direction > 0:
		# A committed backflip has already converted forward momentum into lift. Preserve steering,
		# but do not let ordinary airborne acceleration rebuild the discarded sprint speed.
		horizontal_wish_speed = minf(
			horizontal_wish_speed,
			Vector2(velocity.x, velocity.z).length()
		)
	var horizontal_velocity := calculate_horizontal_velocity(
		velocity,
		direction,
		horizontal_wish_speed,
		was_on_floor and not is_launching,
		delta,
		gait.get_momentum_recovery_weight()
	)
	if flip_active and not was_on_floor:
		horizontal_velocity = calculate_flip_horizontal_velocity(
			horizontal_velocity,
			direction,
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
			accepted_flip_direction = validated_flip_direction(
				pending_flip_intent,
				Vector2(velocity.x, velocity.z).length(),
				wrist_interface_open,
				pending_flip_run_committed
			)
			if accepted_flip_direction != 0:
				_begin_flip(accepted_flip_direction)
				velocity = calculate_flip_takeoff_velocity(
					velocity,
					jump_velocity,
					accepted_flip_direction
				)
				airborne_flip_direction = accepted_flip_direction
			else:
				airborne_flip_direction = 0
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

	if wants_jump:
		_resolve_pending_jump_request(
			is_launching,
			accepted_flip_direction
		)
	wants_jump = false
	pending_flip_intent = 0
	pending_flip_run_committed = false
	pending_jump_request_id = 0
	pending_jump_audio_prediction_key = 0

	var horizontal_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	_move_and_collide_with_slide(
		horizontal_motion,
		was_on_floor and not is_launching
	)
	if _commit_pending_body_impact():
		return

	var landing_impact_speed := maxf(-velocity.y, 0.0)
	var vertical_motion := Vector3(0.0, velocity.y, 0.0) * delta
	var vertical_col := move_and_collide(vertical_motion)

	if vertical_col:
		var normal := vertical_col.get_normal()

		if normal.y > FLOOR_CONTACT_NORMAL_Y:
			on_floor = true
			airborne_flip_direction = 0
			footstep_surface = _get_footstep_surface(vertical_col.get_collider())
			var contacted_from_air := not was_on_floor
			if contacted_from_air and air_time >= TRIP_MIN_AIR_TIME:
				landing_sequence += 1
				landing_impact_strength = landing_response_strength(
					landing_impact_speed
				)
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
			var hard_impact := (
				contacted_from_air
				and air_time >= TRIP_MIN_AIR_TIME
				and should_trip_from_landing_impact(landing_impact_speed)
			)
			var incomplete_flip_landing := (
				contacted_from_air
				and flip_direction != 0
				and flip_phase < FLIP_MIN_SAFE_LANDING_PHASE
			)
			var dropkick_landing := (
				contacted_from_air
				and should_trip_from_dropkick_landing(
					kick_style == KickStyle.DROP
					and kick_active
					and kick_phase >= DROP_KICK_CONTACT_ARM_PHASE,
					landing_impact_speed
				)
			)
			if hard_impact or incomplete_flip_landing or dropkick_landing:
				_begin_trip()
			elif (
				contacted_from_air
				and air_time >= TRIP_MIN_AIR_TIME
				and _landing_lacks_required_support()
			):
				_begin_trip()
			if flip_direction != 0 and not ragdoll_active:
				flip_active = false
				flip_elapsed = FLIP_DURATION_SECONDS
				flip_phase = 1.0
			if velocity.y < 0.0:
				velocity.y = 0.0

		_try_push_body(vertical_col)
	_update_footsteps(delta)
	if on_floor:
		last_safe_standing_position = global_position


static func landing_response_strength(impact_speed: float) -> float:
	var bounded_speed := maxf(impact_speed, 0.0)
	var normalized_energy := clampf(
		inverse_lerp(
			LANDING_RESPONSE_MIN_SPEED * LANDING_RESPONSE_MIN_SPEED,
			HARD_LANDING_TRIP_SPEED * HARD_LANDING_TRIP_SPEED,
			bounded_speed * bounded_speed
		),
		0.0,
		1.0
	)
	# Kinetic energy and ballistic drop height are both proportional to speed squared. The rig adds
	# its expressive curve after this authority-owned physical load has been normalized.
	return normalized_energy


static func should_trip_from_landing_impact(impact_speed: float) -> bool:
	return maxf(impact_speed, 0.0) >= HARD_LANDING_TRIP_SPEED


static func should_trip_from_dropkick_landing(
	dropkick_is_active: bool,
	impact_speed: float
) -> bool:
	return (
		dropkick_is_active
		and maxf(impact_speed, 0.0) >= DROP_KICK_LANDING_TRIP_MIN_SPEED
	)


static func validated_flip_direction(
	requested_direction: int,
	horizontal_speed: float,
	wrist_interface_active := false,
	sprint_committed := false
) -> int:
	var direction := clampi(requested_direction, -1, 1)
	if (
		direction == 0
		or wrist_interface_active
		or not sprint_committed
		or maxf(horizontal_speed, 0.0) < FLIP_MIN_HORIZONTAL_SPEED
	):
		return 0
	return direction


func _resolve_pending_jump_request(
	jump_accepted: bool,
	accepted_flip_direction: int
) -> void:
	if pending_jump_request_id <= 0:
		return
	jump_request_resolved.emit(
		pending_jump_request_id,
		jump_accepted,
		clampi(accepted_flip_direction, -1, 1)
	)


func _reject_pending_jump_request() -> void:
	if not wants_jump:
		return
	_resolve_pending_jump_request(false, 0)
	wants_jump = false
	pending_flip_intent = 0
	pending_flip_run_committed = false
	pending_jump_request_id = 0
	pending_jump_audio_prediction_key = 0


static func calculate_flip_horizontal_velocity(
	current_velocity: Vector3,
	input_direction: Vector3,
	delta: float
) -> Vector3:
	var safe_delta := maxf(delta, 0.0)
	var horizontal := Vector3(current_velocity.x, 0.0, current_velocity.z)
	if not horizontal.is_finite():
		return Vector3.ZERO
	# The committed tuck preserves most of its small traversal bonus while keeping decay frame-rate
	# stable. Deliberate opposing input can still carve through old momentum instead of being
	# completely cancelled by it.
	horizontal *= exp(-FLIP_AIR_MOMENTUM_DRAG * safe_delta)
	var desired_direction := Vector3(
		input_direction.x,
		0.0,
		input_direction.z
	)
	if desired_direction.length_squared() <= MOVEMENT_INPUT_THRESHOLD_SQUARED:
		return horizontal
	desired_direction = desired_direction.normalized()
	var speed := horizontal.length()
	if speed <= 0.001:
		return desired_direction * minf(
			FLIP_AIR_REDIRECT_ACCELERATION * safe_delta,
			WALK_SPEED
		)
	var alignment := clampf(
		horizontal.normalized().dot(desired_direction),
		-1.0,
		1.0
	)
	var opposition := (1.0 - alignment) * 0.5
	var redirect_acceleration := (
		FLIP_AIR_REDIRECT_ACCELERATION
		* lerpf(0.65, 1.45, opposition)
	)
	return horizontal.move_toward(
		desired_direction * maxf(speed, WALK_SPEED * 0.8),
		redirect_acceleration * safe_delta
	)


static func calculate_flip_takeoff_velocity(
	current_velocity: Vector3,
	base_jump_velocity: float,
	flip_direction := 0
) -> Vector3:
	var safe_velocity := (
		current_velocity
		if current_velocity.is_finite()
		else Vector3.ZERO
	)
	var direction := clampi(flip_direction, -1, 1)
	var horizontal_multiplier := 1.0
	var vertical_multiplier := 1.0
	if direction < 0:
		# Looking down commits a frontflip: carry farther through the line of travel, with only a
		# slight lift increase so it remains the horizontal traversal choice.
		horizontal_multiplier = FRONT_FLIP_TAKEOFF_HORIZONTAL_MULTIPLIER
		vertical_multiplier = FRONT_FLIP_TAKEOFF_VERTICAL_MULTIPLIER
	elif direction > 0:
		# Looking up commits a backflip: solve horizontal speed from an explicit range budget so its
		# extra airtime cannot accidentally turn it into a second long-jump option.
		horizontal_multiplier = backflip_horizontal_takeoff_multiplier(
			base_jump_velocity
		)
		vertical_multiplier = BACK_FLIP_TAKEOFF_VERTICAL_MULTIPLIER
	return Vector3(
		safe_velocity.x * horizontal_multiplier,
		maxf(base_jump_velocity, 0.0) * vertical_multiplier,
		safe_velocity.z * horizontal_multiplier
	)


static func backflip_horizontal_takeoff_multiplier(
	base_jump_velocity: float
) -> float:
	var ordinary_flight_seconds := (
		2.0 * maxf(base_jump_velocity, 0.0) / GRAVITY
	)
	var backflip_travel_seconds := flip_horizontal_travel_seconds(
		maxf(base_jump_velocity, 0.0)
		* BACK_FLIP_TAKEOFF_VERTICAL_MULTIPLIER
	)
	if backflip_travel_seconds <= 0.00001:
		return 0.0
	return (
		BACK_FLIP_TARGET_RANGE_RATIO
		* ordinary_flight_seconds
		/ backflip_travel_seconds
	)


static func flip_horizontal_travel_seconds(vertical_launch_speed: float) -> float:
	var flight_seconds := (
		2.0 * maxf(vertical_launch_speed, 0.0) / GRAVITY
	)
	var drag_seconds := minf(flight_seconds, FLIP_DURATION_SECONDS)
	if FLIP_AIR_MOMENTUM_DRAG <= 0.00001:
		return flight_seconds
	var decay := exp(-FLIP_AIR_MOMENTUM_DRAG * drag_seconds)
	return (
		(1.0 - decay) / FLIP_AIR_MOMENTUM_DRAG
		+ decay * maxf(flight_seconds - drag_seconds, 0.0)
	)


func _begin_flip(direction: int) -> void:
	flip_sequence += 1
	flip_direction = clampi(direction, -1, 1)
	flip_active = flip_direction != 0
	flip_elapsed = 0.0
	flip_phase = 0.0
	flip_impact_vulnerability_remaining = (
		FLIP_DURATION_SECONDS + FLIP_POST_IMPACT_VULNERABILITY_SECONDS
	)


func _advance_flip_state(delta: float) -> void:
	if not flip_active:
		return
	flip_elapsed = minf(
		flip_elapsed + maxf(delta, 0.0),
		FLIP_DURATION_SECONDS
	)
	flip_phase = clampf(
		flip_elapsed / maxf(FLIP_DURATION_SECONDS, 0.001),
		0.0,
		1.0
	)
	if flip_phase >= 1.0:
		flip_active = false


func _advance_kick_state(delta: float) -> void:
	if not kick_active:
		return
	if kick_style == KickStyle.DROP:
		_advance_dropkick_state(delta)
		return
	kick_direction = apply_kick_guidance(
		kick_direction_from_view(
			kick_view_yaw,
			kick_view_pitch,
			kick_flip_direction,
			flip_phase if kick_flip_direction != 0 else 0.0
		),
		kick_guidance_direction,
		kick_guidance_weight
	)
	var previous_phase := kick_phase
	_kick_elapsed = minf(
		_kick_elapsed + maxf(delta, 0.0),
		KICK_DURATION_SECONDS
	)
	kick_phase = clampf(
		_kick_elapsed / maxf(KICK_DURATION_SECONDS, 0.001),
		0.0,
		1.0
	)
	if (
		not _kick_hit_resolved
		and previous_phase < KICK_STRIKE_PHASE
		and kick_phase >= KICK_STRIKE_PHASE
	):
		_kick_hit_resolved = true
		_resolve_kick_contact()
	if kick_phase >= 1.0:
		kick_active = false


func _advance_dropkick_state(delta: float) -> void:
	if not context_action_held:
		kick_active = false
		kick_phase = 1.0
		return
	kick_direction = apply_kick_guidance(
		kick_direction_from_view(
			kick_view_yaw,
			kick_view_pitch,
			0,
			0.0
		),
		kick_guidance_direction,
		kick_guidance_weight
	)
	_kick_elapsed = minf(
		_kick_elapsed + maxf(delta, 0.0),
		DROP_KICK_POSE_BUILD_SECONDS
	)
	kick_phase = clampf(
		_kick_elapsed / maxf(DROP_KICK_POSE_BUILD_SECONDS, 0.001),
		0.0,
		1.0
	)
	if kick_phase < DROP_KICK_CONTACT_ARM_PHASE:
		return
	_resolve_dropkick_contact()


func _resolve_kick_contact() -> void:
	if not is_inside_tree() or get_world_3d() == null:
		return
	var source_position := _kick_source_position()
	var strike_center := source_position + kick_direction * KICK_REACH_METERS
	var closest: Node3D
	var closest_distance_squared := INF
	var space_state := get_world_3d().direct_space_state
	_kick_ray_query.from = source_position
	_kick_ray_query.to = strike_center
	var blocking_hit := space_state.intersect_ray(_kick_ray_query)
	if not blocking_hit.is_empty():
		closest = blocking_hit.get("collider") as Node3D
		strike_center = blocking_hit.get("position", strike_center)
	else:
		_kick_query.transform = Transform3D(Basis.IDENTITY, strike_center)
		for result: Dictionary in space_state.intersect_shape(_kick_query, 8):
			var candidate := result.get("collider") as Node3D
			if candidate == null or candidate == self:
				continue
			var distance_squared := source_position.distance_squared_to(
				candidate.global_position
			)
			if distance_squared >= closest_distance_squared:
				continue
			closest = candidate
			closest_distance_squared = distance_squared
	if closest == null:
		_maybe_lose_running_kick_balance(false)
		return
	var impact_strength := clampf(
		0.44 + (kick_intensity - 1.0) * 0.72,
		0.35,
		1.0
	)
	var impulse_strength := kick_impulse_from_momentum(
		kick_forward_momentum_speed,
		kick_momentum_speed,
		kick_flip_direction != 0
	)
	_apply_kick_contact(
		closest,
		strike_center,
		impact_strength,
		impulse_strength,
		KICK_ENEMY_DAMAGE * impact_strength * kick_intensity
	)
	_maybe_lose_running_kick_balance(true)


func _resolve_dropkick_contact() -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var source_position := global_position + Vector3.UP * KICK_HIP_HEIGHT_OFFSET
	var extension_weight := smoothstep(
		0.0,
		1.0,
		inverse_lerp(0.43, 1.0, kick_phase)
	)
	var visible_reach := lerpf(
		DROP_KICK_REACH_METERS * 0.46,
		DROP_KICK_REACH_METERS,
		extension_weight
	)
	var strike_center := source_position + kick_direction * visible_reach
	var closest: Node3D
	var contact_normal := -kick_direction
	var closest_distance_squared := INF
	var space_state := get_world_3d().direct_space_state
	_kick_ray_query.from = source_position
	_kick_ray_query.to = strike_center
	var blocking_hit := space_state.intersect_ray(_kick_ray_query)
	if not blocking_hit.is_empty():
		closest = blocking_hit.get("collider") as Node3D
		strike_center = blocking_hit.get("position", strike_center)
		contact_normal = blocking_hit.get("normal", contact_normal)
	else:
		_dropkick_query.transform = Transform3D(Basis.IDENTITY, strike_center)
		var rest_info := space_state.get_rest_info(_dropkick_query)
		if not rest_info.is_empty():
			closest = rest_info.get("collider") as Node3D
			strike_center = rest_info.get("point", strike_center)
			contact_normal = rest_info.get("normal", contact_normal)
		else:
			for result: Dictionary in space_state.intersect_shape(_dropkick_query, 8):
				var candidate := result.get("collider") as Node3D
				if candidate == null or candidate == self:
					continue
				var distance_squared := source_position.distance_squared_to(
					candidate.global_position
				)
				if distance_squared >= closest_distance_squared:
					continue
				closest = candidate
				closest_distance_squared = distance_squared
	if closest == null:
		return false
	var impulse_strength := minf(
		DROP_KICK_BASE_IMPULSE
		+ kick_forward_momentum_speed * DROP_KICK_MOMENTUM_IMPULSE_SCALE,
		DROP_KICK_MAX_IMPULSE
	)
	var contact_velocity := _contact_velocity_for_collider(closest)
	_apply_kick_contact(
		closest,
		strike_center,
		1.0,
		impulse_strength,
		KICK_ENEMY_DAMAGE * kick_intensity * 1.45
	)
	# The collision is resolved before the pose changes state. The ragdoll therefore begins from a
	# visibly extended, physically contacted dropkick rather than from an input-driven timer. Its
	# initial velocity is the equal-and-opposite contact response, not merely a small forward-speed
	# subtraction that leaves the body travelling through the obstacle.
	var recoil_velocity := dropkick_recoil_velocity(
		velocity,
		contact_normal,
		contact_velocity,
		kick_direction,
		impulse_strength
	)
	_begin_trip(recoil_velocity)
	return true


func _contact_velocity_for_collider(collider: Node3D) -> Vector3:
	var rigid_body := collider as RigidBody3D
	if rigid_body != null:
		return rigid_body.linear_velocity
	var character_body := collider as CharacterBody3D
	if character_body != null:
		return character_body.velocity
	return Vector3.ZERO


func _apply_kick_contact(
	closest: Node3D,
	strike_center: Vector3,
	impact_strength: float,
	impulse_strength: float,
	damage: float
) -> void:
	var impulse_direction := (
		kick_direction + Vector3.UP * 0.08
	).normalized()
	var kicked_player := closest as ServerPlayer
	if kicked_player != null:
		kicked_player.receive_kick_impact(
			impulse_direction,
			impact_strength,
			impulse_strength
		)
	else:
		var rigid_body := closest as RigidBody3D
		if rigid_body != null and not rigid_body.freeze:
			rigid_body.apply_impulse(
				impulse_direction * impulse_strength,
				strike_center - rigid_body.global_position
			)
		elif closest.has_method("apply_damage"):
			closest.call("apply_damage", maxf(damage, 0.0))
	var surface := _get_footstep_surface(closest)
	_emit_gameplay_sound(
		_landing_sound_id(surface),
		KICK_SOUND_MAX_DISTANCE,
		KICK_SOUND_PRIORITY,
		0,
		strike_center,
		-3.0 if kick_style == KickStyle.DROP else -4.0
	)


func _maybe_lose_running_kick_balance(contacted_target: bool) -> void:
	if kick_style != KickStyle.SINGLE or not on_floor or ragdoll_active:
		return
	var probability := running_kick_balance_failure_probability(
		kick_forward_momentum_speed,
		kick_momentum_speed,
		contacted_target
	)
	if probability <= 0.0:
		return
	var sample := ExpressionDeterminism.ratio(
		(player_id + 2) * 1103515245 + kick_sequence * 214013
	)
	if sample < probability:
		_begin_trip(velocity)


func receive_kick_impact(
	direction: Vector3,
	strength: float,
	impulse_strength: float
) -> void:
	if ragdoll_active:
		return
	var safe_direction := direction if direction.is_finite() else Vector3.FORWARD
	if safe_direction.length_squared() <= MOTION_THRESHOLD_SQUARED:
		return
	safe_direction = safe_direction.normalized()
	var safe_strength := clampf(strength, 0.0, 1.0)
	velocity += safe_direction * maxf(impulse_strength, 0.0) * 0.42
	body_impact_sequence += 1
	body_impact_strength = safe_strength
	body_impact_direction = -safe_direction
	body_impact_contact_side = 0.0
	body_impact_clock = expression_clock
	# A flying kick carries enough rotational load to destabilize another already-airborne body. A
	# normal grounded kick remains a shove/flinch and does not turn every playful interaction into a
	# ragdoll interruption.
	if not on_floor and safe_strength >= 0.88:
		_begin_trip(velocity)


func receive_enemy_tackle(
	direction: Vector3,
	strength: float,
	impulse_strength: float
) -> void:
	if ragdoll_active:
		return
	var safe_direction := direction if direction.is_finite() else Vector3.FORWARD
	if safe_direction.length_squared() <= MOTION_THRESHOLD_SQUARED:
		return
	safe_direction = safe_direction.normalized()
	var safe_strength := clampf(strength, 0.0, 1.0)
	velocity += safe_direction * maxf(impulse_strength, 0.0)
	body_impact_sequence += 1
	body_impact_strength = safe_strength
	body_impact_direction = -safe_direction
	body_impact_contact_side = 0.0
	body_impact_clock = expression_clock
	# The tackle was already validated from a real slide collision, relative speed, and facing on the
	# authority. Entering ragdoll here therefore expresses the physical impact rather than a radius hit.
	_begin_trip(velocity)


func _update_trip_state(delta: float) -> void:
	if not ragdoll_active:
		return
	# A lethal ragdoll is not a temporary stumble. It remains physical until the server detaches it as
	# a persistent corpse and respawns the player with a new authority anchor.
	if death_pending:
		return
	trip_recovery_remaining = maxf(
		trip_recovery_remaining - maxf(delta, 0.0),
		0.0
	)
	if trip_recovery_remaining > 0.0:
		return
	trip_recovery_blocked_elapsed += maxf(delta, 0.0)
	trip_recovery_retry_remaining = maxf(
		trip_recovery_retry_remaining - maxf(delta, 0.0),
		0.0
	)
	if trip_recovery_retry_remaining > 0.0:
		return
	trip_recovery_retry_remaining = TRIP_RECOVERY_RETRY_INTERVAL
	if _recover_from_trip(
		trip_recovery_blocked_elapsed >= TRIP_RECOVERY_FALLBACK_DELAY
	):
		return


func _begin_trip(initial_velocity := Vector3.INF) -> void:
	if ragdoll_active:
		return
	_reject_pending_jump_request()
	var resolved_initial_velocity := (
		initial_velocity
		if initial_velocity.is_finite()
		else velocity
	)
	velocity = resolved_initial_velocity
	flip_active = false
	kick_active = false
	kick_phase = 1.0
	gait.reset_after_full_body_interruption(
		maxi(gait.step_sequence, last_foot_contact_sequence) + 1
	)
	airborne_flip_direction = 0
	flip_impact_vulnerability_remaining = 0.0
	ragdoll_active = true
	trip_sequence += 1
	trip_recovery_remaining = TRIP_RECOVERY_SECONDS
	trip_recovery_blocked_elapsed = 0.0
	trip_recovery_retry_remaining = 0.0
	if on_floor:
		last_safe_standing_position = global_position
	var horizontal_velocity := Vector3(
		resolved_initial_velocity.x,
		0.0,
		resolved_initial_velocity.z
	)
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
	_ragdoll_backpack_previous_velocity = resolved_initial_velocity
	_ragdoll_backpack_peak_shock = 0.0
	_ragdoll_backpack_cumulative_shock = 0.0
	_ragdoll_backpack_peak_angular_speed = 0.0
	_ragdoll_backpack_travel_distance = 0.0
	_ragdoll_backpack_release_sample = ExpressionDeterminism.ratio(
		(player_id + 7) * 1103515245 + trip_sequence * 214013
	)
	wrist_interface_open = false
	set_plasma_cutter_triggered(false)
	context_action_held = false
	set_primary_action_held(false)
	move_input = Vector2.ZERO
	wants_run = false
	wants_jump = false
	pending_flip_intent = 0
	collision_shape_3d.set_deferred("disabled", true)
	if authoritative_ragdoll_anchor != null:
		authoritative_ragdoll_anchor.activate(
			global_transform,
			resolved_initial_velocity,
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
	_update_ragdoll_backpack_retention(delta)
	global_position = authoritative_ragdoll_anchor.get_player_reference_position()
	velocity = authoritative_ragdoll_anchor.linear_velocity


func _update_ragdoll_backpack_retention(delta: float) -> void:
	if authoritative_ragdoll_anchor == null:
		return
	# Most trips cannot cross the hard 18% cap. Reject their deterministic sample before doing any
	# per-tick motion work; a backpack-free or already-released player is equally cheap.
	if (
		_ragdoll_backpack_release_sample
		>= RAGDOLL_BACKPACK_MAX_RELEASE_PROBABILITY
	):
		return
	var backpack_entry: Dictionary = SafeVariant.dictionary_copy(
		equipment_entries.get(PlayerInventoryRules.BACKPACK_SLOT, {}),
		false
	)
	if backpack_entry.is_empty():
		return
	var safe_delta := clampf(delta, 0.0, 0.1)
	var current_velocity: Vector3 = authoritative_ragdoll_anchor.linear_velocity
	if not current_velocity.is_finite():
		return
	# Subtract free-fall acceleration before interpreting delta-v as strap load. Merely spending time
	# in the air is harmless; an impact, abrupt slide stop, or violent change of direction is not.
	var gravity_delta := (
		Vector3.DOWN * _ragdoll_gravity_acceleration * safe_delta
	)
	var specific_impulse := (
		current_velocity
		- _ragdoll_backpack_previous_velocity
		- gravity_delta
	).length()
	_ragdoll_backpack_previous_velocity = current_velocity
	_ragdoll_backpack_peak_shock = maxf(
		_ragdoll_backpack_peak_shock,
		specific_impulse
	)
	_ragdoll_backpack_cumulative_shock += maxf(
		specific_impulse - RAGDOLL_BACKPACK_SHOCK_NOISE_FLOOR,
		0.0
	)
	var angular_velocity: Vector3 = authoritative_ragdoll_anchor.angular_velocity
	var angular_speed := angular_velocity.length() if angular_velocity.is_finite() else 0.0
	_ragdoll_backpack_peak_angular_speed = maxf(
		_ragdoll_backpack_peak_angular_speed,
		angular_speed
	)
	_ragdoll_backpack_travel_distance += current_velocity.length() * safe_delta
	var probability := ragdoll_backpack_release_probability(
		_ragdoll_backpack_peak_shock,
		_ragdoll_backpack_cumulative_shock,
		_ragdoll_backpack_peak_angular_speed,
		_ragdoll_backpack_travel_distance
	)
	if _ragdoll_backpack_release_sample >= probability:
		return
	var release := release_backpack_for_ragdoll()
	if release.is_empty():
		return
	var release_direction: Vector3 = authoritative_ragdoll_anchor.global_basis.z
	if not release_direction.is_finite() or release_direction.length_squared() <= MOTION_THRESHOLD_SQUARED:
		release_direction = trip_direction
	else:
		release_direction = release_direction.normalized()
	ragdoll_backpack_released.emit(
		release.get("backpack", {}) as Dictionary,
		release.get("spilled", []) as Array,
		authoritative_ragdoll_anchor.global_position,
		current_velocity,
		release_direction
	)


func _recover_from_trip(allow_last_safe_fallback := false) -> bool:
	var anchor_velocity := velocity
	var anchor_position := global_position
	if (
		authoritative_ragdoll_anchor != null
		and authoritative_ragdoll_anchor.is_active()
	):
		anchor_velocity = authoritative_ragdoll_anchor.linear_velocity
		anchor_position = authoritative_ragdoll_anchor.get_player_reference_position()
	var recovery := _find_ragdoll_recovery(anchor_position)
	if (
		not bool(recovery.get("valid", false))
		and allow_last_safe_fallback
		and last_safe_standing_position.is_finite()
		and anchor_position.distance_squared_to(last_safe_standing_position)
		<= TRIP_RECOVERY_FALLBACK_MAX_DISTANCE * TRIP_RECOVERY_FALLBACK_MAX_DISTANCE
	):
		recovery = _find_ragdoll_recovery(last_safe_standing_position)
		if bool(recovery.get("valid", false)):
			# The fallback is an escape from unresolved penetration, not continued ragdoll momentum.
			anchor_velocity = Vector3.ZERO
	if not bool(recovery.get("valid", false)):
		# A low ceiling or occupied capsule volume is not a valid place to stand. Keep simulating the
		# physical body and retry on the bounded search cadence instead of enabling a CharacterBody
		# inside geometry.
		return false
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
	trip_recovery_blocked_elapsed = 0.0
	trip_recovery_retry_remaining = 0.0
	ragdoll_active = false
	flip_direction = 0
	flip_active = false
	flip_phase = 0.0
	flip_elapsed = 0.0
	if on_floor:
		last_safe_standing_position = global_position
	return true


func _find_ragdoll_recovery(anchor_position: Vector3) -> Dictionary:
	if not anchor_position.is_finite() or not is_inside_tree() or get_world_3d() == null:
		return {"valid": false}
	var facing := -Basis(Vector3.UP, look_yaw).z
	var right := Basis(Vector3.UP, look_yaw).x
	var found_ground := false
	var center_candidate := _grounded_recovery_position(anchor_position)
	if center_candidate.is_finite():
		found_ground = true
		if _is_recovery_space_clear(center_candidate):
			return {
				"valid": true,
				"position": center_candidate,
				"on_floor": true,
			}
	# Search complete rings rather than four axis points. This resolves stair risers, modular seams,
	# and inside corners without preferring the player's facing direction or crossing solid walls.
	for ring_index: int in range(1, TRIP_RECOVERY_SEARCH_RING_COUNT + 1):
		var radius := TRIP_RECOVERY_SEARCH_RADIUS * float(ring_index)
		for sample_index: int in range(TRIP_RECOVERY_SEARCH_SAMPLES):
			var angle := TAU * float(sample_index) / float(TRIP_RECOVERY_SEARCH_SAMPLES)
			var offset := (
				right * cos(angle) + facing * sin(angle)
			) * radius
			var candidate := _grounded_recovery_position(anchor_position + offset)
			if not candidate.is_finite():
				continue
			found_ground = true
			if (
				_is_recovery_route_clear(anchor_position, candidate)
				and _is_recovery_space_clear(candidate)
			):
				return {
					"valid": true,
					"position": candidate,
					"on_floor": true,
				}
	if found_ground:
		return {"valid": false}
	# Falling off an edge remains a real fall. Continue from the physical torso rather than teleporting
	# to the last grounded position; normal CharacterBody gravity takes over only if its standing
	# volume is genuinely free. An embedded anchor must remain physical until the search frees it.
	if _is_recovery_space_clear(anchor_position):
		return {"valid": true, "position": anchor_position, "on_floor": false}
	return {"valid": false}


func _grounded_recovery_position(horizontal_position: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.new()
	query.from = horizontal_position + Vector3.UP * TRIP_RECOVERY_GROUND_PROBE_UP
	query.to = horizontal_position - Vector3.UP * TRIP_RECOVERY_GROUND_PROBE_DOWN
	query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	query.collide_with_areas = false
	query.hit_from_inside = true
	query.exclude = _ragdoll_recovery_exclusions()
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var normal := hit.get("normal", Vector3.ZERO) as Vector3
	if normal.y < FLOOR_CONTACT_NORMAL_Y:
		return Vector3.INF
	var ground_position := hit.get("position", horizontal_position) as Vector3
	if (
		ground_position.y - horizontal_position.y
		> TRIP_RECOVERY_MAX_GROUND_RISE
	):
		return Vector3.INF
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


func _is_recovery_route_clear(from_position: Vector3, to_position: Vector3) -> bool:
	var horizontal_delta := Vector3(
		to_position.x - from_position.x,
		0.0,
		to_position.z - from_position.z
	)
	if horizontal_delta.length_squared() <= MOTION_THRESHOLD_SQUARED:
		return true
	var query := PhysicsRayQueryParameters3D.new()
	var route_y := maxf(from_position.y, to_position.y) + TRIP_RECOVERY_ROUTE_HEIGHT
	query.from = Vector3(from_position.x, route_y, from_position.z)
	query.to = Vector3(to_position.x, route_y, to_position.z)
	query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
	query.collide_with_areas = false
	query.hit_from_inside = true
	query.exclude = _ragdoll_recovery_exclusions()
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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


static func advance_sprint_speed_ramp(
	elapsed: float,
	sprint_requested: bool,
	grounded: bool,
	delta: float
) -> float:
	if not sprint_requested:
		return 0.0
	var safe_elapsed := clampf(
		elapsed if is_finite(elapsed) else 0.0,
		0.0,
		SPRINT_SPEED_RAMP_SECONDS
	)
	# Airborne movement keeps the speed earned at takeoff. It cannot silently finish the sprint
	# buildup while no foot is producing forward force.
	if not grounded:
		return safe_elapsed
	return minf(
		safe_elapsed + maxf(delta, 0.0),
		SPRINT_SPEED_RAMP_SECONDS
	)


static func sprint_speed_at_elapsed(elapsed: float) -> float:
	var linear_ratio := clampf(
		(elapsed if is_finite(elapsed) else 0.0)
		/ SPRINT_SPEED_RAMP_SECONDS,
		0.0,
		1.0
	)
	# Allocation-free cubic smoothstep: the runner leaves walking pace cleanly, accelerates most
	# strongly in the middle, and approaches full speed without a hard derivative at 1.5 seconds.
	var curved_ratio := (
		linear_ratio
		* linear_ratio
		* (3.0 - 2.0 * linear_ratio)
	)
	return lerpf(WALK_SPEED, RUN_SPEED, curved_ratio)


static func calculate_horizontal_velocity(
	current_velocity: Vector3,
	wish_direction: Vector3,
	wish_speed: float,
	grounded: bool,
	delta: float,
	momentum_recovery_weight: float = 0.0
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
		var recovery := clampf(momentum_recovery_weight, 0.0, 1.0)
		var current_speed := horizontal.length()
		var direction_alignment := (
			direction.dot(horizontal / current_speed)
			if current_speed > 0.001 and direction != Vector3.ZERO
			else 1.0 if direction == Vector3.ZERO else 0.0
		)
		var shedding_forward_momentum := (
			recovery > 0.001
			and current_speed > bounded_speed + 0.001
			and direction_alignment >= SPRINT_RELEASE_DIRECTION_DOT_MIN
		)
		if direction == Vector3.ZERO and recovery > 0.001:
			shedding_forward_momentum = true
		if shedding_forward_momentum:
			# A full-speed body cannot discard its momentum on the same frame as the sprint button.
			# The nonlinear blend keeps early braking soft, then lets the last catch contacts bite.
			acceleration = lerpf(
				GROUND_DECELERATION,
				SPRINT_RELEASE_DECELERATION,
				sqrt(recovery)
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
		delta,
		true
	)
	if completed_steps <= 0:
		return
	# Support remains authority-owned. Audible impact is accepted separately from the actual client
	# presentation contact, avoiding the former lift-off sound while keeping trip rules untrusted.
	if _landing_lacks_required_support():
		_begin_trip()


func accept_presented_foot_contact(
	contact_sequence: int,
	side: int,
	local_prediction_key: int
) -> bool:
	var expected_key := LOCAL_AUDIO_PREDICTION.gait_step_key(contact_sequence)
	var now_msec := Time.get_ticks_msec()
	if (
		ragdoll_active
		or not on_floor
		or not gait.active
		or contact_sequence <= last_foot_contact_sequence
		or contact_sequence < gait.step_sequence - FOOT_CONTACT_MAX_SEQUENCE_LEAD
		or contact_sequence > gait.step_sequence + FOOT_CONTACT_MAX_SEQUENCE_LEAD
		or local_prediction_key != expected_key
		or now_msec - last_foot_contact_msec < FOOT_CONTACT_MIN_INTERVAL_MSEC
		or not _has_leg_for_side(side)
	):
		return false
	var contact := _resolve_foot_contact(side, contact_sequence)
	if contact.is_empty():
		return false
	last_foot_contact_sequence = contact_sequence
	last_foot_contact_msec = now_msec
	footstep_surface = _get_footstep_surface(contact.get("collider"))
	var source_position: Vector3 = contact["position"]
	_emit_gameplay_sound(
		_footstep_sound_id(footstep_surface),
		FOOTSTEP_MAX_DISTANCE,
		FOOTSTEP_PRIORITY,
		local_prediction_key,
		source_position,
		PlayerGait.get_footstep_volume_db_for_motion(
			Vector2(velocity.x, velocity.z).length(),
			player_id,
			contact_sequence
		)
	)
	return true


func _has_leg_for_side(side: int) -> bool:
	if body_loadout == null:
		return false
	if side == PlayerGait.FootSide.LEFT:
		return body_loadout.left_leg != null
	if side == PlayerGait.FootSide.RIGHT:
		return body_loadout.right_leg != null
	return false


func _resolve_foot_contact(side: int, contact_sequence: int) -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {}
	var lateral_sign := (
		-1.0 if side == PlayerGait.FootSide.LEFT else 1.0
	)
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal_velocity.length()
	var forward := -global_basis.z
	if speed > 0.001:
		forward = horizontal_velocity / speed
	var horizontal_offset := (
		global_basis.x
		* lateral_sign
		* PlayerGait.FOOT_STANCE_HALF_WIDTH
		* PlayerGait.get_step_stance_scale_for_motion(
			speed,
			player_id,
			contact_sequence
		)
	)
	horizontal_offset += global_basis.x * PlayerGait.get_step_lateral_variation(
		player_id,
		contact_sequence
	)
	horizontal_offset += forward * (
		minf(
			speed * PlayerGait.get_step_lead_seconds(
				player_id,
				contact_sequence
			),
			PlayerGait.get_step_max_lead_distance_for_motion(
				speed,
				player_id,
				contact_sequence
			)
		)
		+ PlayerGait.get_step_forward_variation(
			player_id,
			contact_sequence
		)
	)
	_foot_contact_query.from = (
		global_position
		+ horizontal_offset
		+ Vector3.UP * FOOT_CONTACT_PROBE_UP
	)
	_foot_contact_query.to = (
		global_position
		+ horizontal_offset
		- Vector3.UP * FOOT_CONTACT_PROBE_DOWN
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(
		_foot_contact_query
	)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	return hit if normal.y > FLOOR_CONTACT_NORMAL_Y else {}


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
	local_prediction_key := 0,
	source_position := Vector3(INF, INF, INF),
	base_volume_db := 0.0
) -> void:
	if not multiplayer.is_server():
		return
	var server := get_node_or_null("/root/Server")
	if server == null or not server.has_method("emit_spatial_sound"):
		return
	server.call(
		"emit_spatial_sound",
		sound_id,
		source_position if source_position.is_finite() else global_position + Vector3.UP * 0.35,
		max_distance,
		base_volume_db,
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


static func body_impact_response_strength(impact_speed: float) -> float:
	var speed_squared := maxf(impact_speed, 0.0)
	speed_squared *= speed_squared
	var normalized_load := clampf(
		inverse_lerp(
			BODY_IMPACT_MIN_SPEED * BODY_IMPACT_MIN_SPEED,
			BODY_IMPACT_FULL_SPEED * BODY_IMPACT_FULL_SPEED,
			speed_squared
		),
		0.0,
		1.0
	)
	return smoothstep(0.0, 1.0, normalized_load)


static func flip_body_impact_trip_speed_threshold(
	flip_is_active: bool,
	vulnerability_remaining: float
) -> float:
	if flip_is_active:
		return FLIP_BODY_IMPACT_TRIP_MIN_SPEED
	var recovery_ratio := clampf(
		maxf(vulnerability_remaining, 0.0)
		/ FLIP_POST_IMPACT_VULNERABILITY_SECONDS,
		0.0,
		1.0
	)
	if recovery_ratio <= 0.0:
		return INF
	# Stability returns continuously after the rotation. A collision immediately after completion is
	# almost as dangerous as one during the tuck, while the final edge of the window needs nearly a
	# full-speed direct slam to topple the player.
	var instability := smoothstep(0.0, 1.0, recovery_ratio)
	return lerpf(
		BODY_IMPACT_FULL_SPEED,
		FLIP_BODY_IMPACT_TRIP_MIN_SPEED,
		instability
	)


func _reset_pending_body_impact() -> void:
	_pending_body_impact_strength = 0.0
	_pending_body_impact_direction = Vector3.ZERO
	_pending_body_impact_contact_side = 0.0
	_pending_body_impact_velocity = Vector3.ZERO
	_pending_low_obstacle_trip = false
	_pending_flip_impact_trip = false
	_pending_dropkick_impact_trip = false


func _record_body_impact(
	col: KinematicCollision3D,
	incoming_velocity: Vector3,
	allow_low_obstacle_trip: bool
) -> void:
	if col == null or not incoming_velocity.is_finite():
		return
	var collision_normal := col.get_normal()
	var horizontal_normal := Vector3(
		collision_normal.x,
		0.0,
		collision_normal.z
	)
	if horizontal_normal.length_squared() <= MOTION_THRESHOLD_SQUARED:
		return
	horizontal_normal = horizontal_normal.normalized()
	var collider_velocity := col.get_collider_velocity()
	if not collider_velocity.is_finite():
		collider_velocity = Vector3.ZERO
	var relative_velocity := incoming_velocity - collider_velocity
	var impact_speed := maxf(-relative_velocity.dot(horizontal_normal), 0.0)
	if impact_speed < BODY_IMPACT_MIN_SPEED:
		return
	var impact_strength := body_impact_response_strength(impact_speed)
	if impact_strength > _pending_body_impact_strength:
		var contact_offset := col.get_position() - global_position
		var local_contact := global_basis.inverse() * contact_offset
		_pending_body_impact_strength = impact_strength
		_pending_body_impact_direction = horizontal_normal
		_pending_body_impact_contact_side = clampf(
			local_contact.x / 0.5,
			-1.0,
			1.0
		)
		_pending_body_impact_velocity = incoming_velocity
	var flip_trip_threshold := flip_body_impact_trip_speed_threshold(
		flip_active,
		flip_impact_vulnerability_remaining
	)
	if impact_speed >= flip_trip_threshold:
		_pending_flip_impact_trip = true
		_pending_body_impact_velocity = incoming_velocity
	if (
		kick_style == KickStyle.DROP
		and kick_active
		and kick_phase >= DROP_KICK_CONTACT_ARM_PHASE
		and impact_speed >= DROP_KICK_BODY_TRIP_MIN_SPEED
	):
		_pending_dropkick_impact_trip = true
		var dropkick_impulse := minf(
			DROP_KICK_BASE_IMPULSE
			+ kick_forward_momentum_speed * DROP_KICK_MOMENTUM_IMPULSE_SCALE,
			DROP_KICK_MAX_IMPULSE
		)
		_pending_body_impact_velocity = dropkick_recoil_velocity(
			incoming_velocity,
			collision_normal,
			collider_velocity,
			kick_direction,
			dropkick_impulse
		)
	if (
		allow_low_obstacle_trip
		and impact_speed >= LOW_OBSTACLE_TRIP_MIN_SPEED
		and body_loadout != null
		and body_loadout.has_any_leg()
		and _collision_has_upper_body_clearance(col, incoming_velocity)
	):
		_pending_low_obstacle_trip = true
		if not _pending_dropkick_impact_trip:
			_pending_body_impact_velocity = incoming_velocity


func _collision_has_upper_body_clearance(
	col: KinematicCollision3D,
	incoming_velocity: Vector3
) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var collider := col.get_collider()
	if collider == null:
		return false
	var horizontal_motion := Vector3(
		incoming_velocity.x,
		0.0,
		incoming_velocity.z
	)
	if horizontal_motion.length_squared() <= MOTION_THRESHOLD_SQUARED:
		return false
	var probe_direction := horizontal_motion.normalized()
	var foot_height := global_position.y - _standing_collision_half_height()
	var lower_origin := Vector3(
		global_position.x,
		foot_height + TRIP_OBSTACLE_LOWER_PROBE_HEIGHT,
		global_position.z
	)
	_body_impact_query.from = lower_origin
	_body_impact_query.to = (
		lower_origin + probe_direction * TRIP_OBSTACLE_PROBE_DISTANCE
	)
	var lower_hit := get_world_3d().direct_space_state.intersect_ray(
		_body_impact_query
	)
	if lower_hit.is_empty() or lower_hit.get("collider") != collider:
		return false
	var upper_origin := Vector3(
		global_position.x,
		foot_height + TRIP_OBSTACLE_CLEARANCE_PROBE_HEIGHT,
		global_position.z
	)
	_body_impact_query.from = upper_origin
	_body_impact_query.to = (
		upper_origin + probe_direction * TRIP_OBSTACLE_PROBE_DISTANCE
	)
	var upper_hit := get_world_3d().direct_space_state.intersect_ray(
		_body_impact_query
	)
	return upper_hit.is_empty() or upper_hit.get("collider") != collider


func _commit_pending_body_impact() -> bool:
	if (
		_pending_body_impact_strength > 0.0
		and _body_impact_cooldown_remaining <= 0.0
	):
		body_impact_sequence += 1
		body_impact_strength = _pending_body_impact_strength
		body_impact_direction = _pending_body_impact_direction
		body_impact_contact_side = _pending_body_impact_contact_side
		body_impact_clock = expression_clock
		_body_impact_cooldown_remaining = BODY_IMPACT_EVENT_COOLDOWN_SECONDS
	if (
		not _pending_low_obstacle_trip
		and not _pending_flip_impact_trip
		and not _pending_dropkick_impact_trip
	):
		return false
	_begin_trip(_pending_body_impact_velocity)
	return true

func _move_and_collide_with_slide(
	motion: Vector3,
	allow_step_up := false
) -> void:
	if motion.length_squared() < MOTION_THRESHOLD_SQUARED:
		return

	var incoming_velocity := velocity
	var col := move_and_collide(motion)

	if col == null:
		return
	if allow_step_up and _try_step_up(col):
		return

	_record_body_impact(col, incoming_velocity, allow_step_up)
	_try_push_body(col)
	velocity = horizontal_velocity_after_wall_collision(
		velocity,
		col.get_normal()
	)

	var remainder := col.get_remainder()
	var slide_motion := remainder.slide(col.get_normal())

	if slide_motion.length_squared() > MOTION_THRESHOLD_SQUARED:
		var slide_incoming_velocity := velocity
		var col2 := move_and_collide(slide_motion)
		if col2:
			_record_body_impact(
				col2,
				slide_incoming_velocity,
				allow_step_up
			)
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
		_record_body_impact(forward_collision, velocity, false)
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
	var cutter := get_plasma_cutter_definition()
	var cutter_range := 0.0
	var cutter_kerf_mm := 0.0
	var cutter_depth_mm := 0.0
	var cutter_duty_seconds := 0.0
	var cutter_cool_seconds := 0.0
	if cutter != null:
		cutter_range = float(cutter.get("range_meters"))
		cutter_kerf_mm = float(cutter.get("cut_radius")) * 2000.0
		cutter_depth_mm = float(cutter.get("cut_depth")) * 1000.0
		cutter_duty_seconds = 1.0 / maxf(
			float(cutter.get("heat_per_second")),
			0.01
		)
		cutter_cool_seconds = 1.0 / maxf(
			float(cutter.get("cooling_per_second")),
			0.01
		)
	var state := {
		"player_id": player_id,
		"pos": global_position,
		"rot": global_rotation,
		"look_pitch": look_pitch,
		"vel": velocity,
		"on_floor": on_floor,
		"jump_sequence": jump_sequence,
		"flip_sequence": flip_sequence,
		"flip_direction": flip_direction,
		"flip_active": flip_active,
		"flip_phase": flip_phase,
		"kick_sequence": kick_sequence,
		"kick_side": kick_side,
		"kick_style": kick_style,
		"kick_active": kick_active,
		"kick_phase": kick_phase,
		"kick_clock": kick_clock,
		"kick_direction": kick_direction,
		"kick_view_yaw": kick_view_yaw,
		"kick_view_pitch": kick_view_pitch,
		"kick_flip_direction": kick_flip_direction,
		"dropkick_tilt_input": dropkick_tilt_input,
		"kick_guidance_direction": kick_guidance_direction,
		"kick_guidance_weight": kick_guidance_weight,
		"kick_intensity": kick_intensity,
		"ragdoll_active": ragdoll_active,
		"trip_sequence": trip_sequence,
		"trip_direction": trip_direction,
		"gait_cycle": gait.get_cycle(),
		"gait_stride_distance": gait.stride_distance,
		"gait_active": gait.active,
		"gait_momentum_recovery": gait.get_momentum_recovery_weight(),
		"landing_sequence": landing_sequence,
		"landing_impact_strength": landing_impact_strength,
		"body_impact_sequence": body_impact_sequence,
		"body_impact_strength": body_impact_strength,
		"body_impact_direction": body_impact_direction,
		"body_impact_contact_side": body_impact_contact_side,
		"body_impact_clock": body_impact_clock,
		"expression_clock": expression_clock,
		"footstep_surface": footstep_surface,
		"health_ratio": health / MAX_HEALTH,
		"stamina_ratio": stamina / MAX_STAMINA,
		"sprint_exhausted": sprint_exhausted,
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
		"plasma_cutter_available": cutter != null,
		"plasma_cutter_heat_ratio": plasma_cutter_heat_ratio,
		"plasma_cutter_overheated": plasma_cutter_overheated,
		"plasma_cutter_active": plasma_cutter_active,
		"plasma_cutter_has_hit": plasma_cutter_has_hit,
		"plasma_cutter_hit_position": plasma_cutter_hit_position,
		"plasma_cutter_range_meters": cutter_range,
		"plasma_cutter_kerf_millimeters": cutter_kerf_mm,
		"plasma_cutter_cut_depth_millimeters": cutter_depth_mm,
		"plasma_cutter_continuous_duty_seconds": cutter_duty_seconds,
		"plasma_cutter_full_cool_seconds": cutter_cool_seconds,
	}
	if include_inventory:
		state["inventory"] = _get_public_inventory_state()
	return state
