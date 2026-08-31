class_name PlayerProceduralLegRig
extends Node3D

## Presentation-only biped contact rig. ServerPlayer remains the movement authority; this node
## selects detailed ground contacts, preserves planted feet, and solves the visible leg chains.
## It deliberately supports zero, one, or two installed legs without inventing phantom support.

enum Side {
	LEFT,
	RIGHT,
}

const HIP_LATERAL_OFFSET := PlayerGait.FOOT_STANCE_HALF_WIDTH
const HIP_LOCAL_HEIGHT := -0.17
const REST_FOOT_LOCAL_HEIGHT := -0.985
const UPPER_LEG_LENGTH := 0.51
const LOWER_LEG_LENGTH := 0.49
const FOOT_HALF_HEIGHT := 0.065
const FOOT_HALF_LENGTH := 0.21
const FOOT_CENTER_FORWARD_OFFSET := 0.035
const CONTACT_PROBE_UP := 0.48
const CONTACT_PROBE_DOWN := 0.62
const MIN_WALKABLE_NORMAL_Y := 0.58
const MAX_SOLE_SAMPLE_HEIGHT_DELTA := 0.075
const STEP_TRIGGER_DISTANCE := 0.47
const TURN_STEP_TRIGGER_DISTANCE := 0.085
const EMERGENCY_REACH_DISTANCE := 0.61
const BALANCE_REPLANT_DISTANCE_RANGE := Vector2(0.13, 0.19)
const BALANCE_DIRECTION_COMMIT_SECONDS_RANGE := Vector2(0.10, 0.18)
const BALANCE_FAST_REPLANT_DISTANCE_SCALE := 0.58
const BALANCE_DIRECTION_REVERSAL_DOT := 0.25
const MOMENTUM_RECOVERY_FOOT_LEAD := 0.16
const MOMENTUM_RECOVERY_ARC_LIFT := 0.42
const MOMENTUM_RECOVERY_DURATION_SCALE := 0.82
const MIN_STEP_DURATION := 0.105
const MAX_STEP_DURATION := 0.235
const TURN_STEP_DURATION := 0.14
const STEP_DURATION_SPEED_SCALE := 0.018
const STEP_ARC_HEIGHT := 0.19
const AIR_POSE_RECOVERY_SECONDS := 0.36
const AIR_LANDING_TUCK_HEIGHT := 0.12
const AIR_LANDING_LEAD_SECONDS := 0.02
const AIR_LANDING_MAX_LEAD_DISTANCE := 0.12
const AIR_LANDING_EXTENSION_DISTANCE := 0.10
const LANDING_QUERY_UP := 0.16
const LANDING_QUERY_DISTANCE := 8.5
const LANDING_FULL_CLEARANCE := 0.08
const LANDING_PREPARE_BASE_CLEARANCE := 0.85
const LANDING_PREPARE_LOOKAHEAD_SECONDS := 0.20
const LANDING_PREPARE_MAX_CLEARANCE := 7.0
const LANDING_DESCENT_FULL_SPEED := 1.5
const AIR_MOTION_FREQUENCY_HZ := 1.05
const AIR_MOTION_FORWARD_DISTANCE := 0.065
const AIR_MOTION_VERTICAL_DISTANCE := 0.038
const AIR_MOTION_LATERAL_DISTANCE := 0.014
const AIR_MOTION_SECONDARY_DISTANCE := 0.012
const AIR_MOTION_LANDING_SCALE := 0.28
const AIR_POSE_ASCENT_SMOOTH_TIME := 0.28
const AIR_POSE_LANDING_SMOOTH_TIME := 0.12
const AIR_POSE_MAX_LOCAL_SPEED := 2.4
const AIR_LANDING_STAGGER_MIN_SECONDS := 0.085
const AIR_LANDING_STAGGER_RANGE_SECONDS := 0.10
const BODY_YIELD_HEIGHT_SCALE := 0.15
const BODY_YIELD_MAX_ROLL := deg_to_rad(10.0)
const BODY_YIELD_MAX_DROP := 0.055
const BODY_YIELD_MAX_LATERAL_SHIFT := 0.028
const BODY_YIELD_RESPONSE := 11.0
const BODY_BALANCE_FULL_OFFSET := 0.24
const BODY_BALANCE_MAX_PITCH := deg_to_rad(6.0)
const BODY_BALANCE_MAX_ROLL := deg_to_rad(7.5)
const BODY_BALANCE_MAX_SHIFT := 0.022
const LANDING_COMPRESSION_DROP_RANGE := Vector2(0.018, 0.145)
const LANDING_COMPRESSION_PEAK_SECONDS_RANGE := Vector2(0.13, 0.23)
const LANDING_COMPRESSION_RECOVERY_SECONDS_RANGE := Vector2(0.22, 0.48)
const KICK_CHAMBER_END_PHASE := 0.20
const KICK_EXTENSION_END_PHASE := 0.47
const KICK_EXTENSION_HOLD_END_PHASE := 0.60
const KICK_CHAMBER_BACK_DISTANCE := 0.22
const KICK_CHAMBER_LIFT := 0.26
const KICK_EXTENSION_DISTANCE := 0.92
const KICK_EXTENSION_DROP := 0.015
const AIRBORNE_KICK_EXTENSION_LIFT := 0.13
const KICK_SIDE_CLEARANCE := 0.045
const KICK_FOOT_STRIKE_TILT := 0.58
const AIRBORNE_KICK_COUNTER_TUCK_DISTANCE := 0.50
const AIRBORNE_KICK_COUNTER_BACK_DISTANCE := 0.08
const AIRBORNE_KICK_COUNTER_SIDE_CLEARANCE := 0.035
const AIRBORNE_KICK_COUNTER_RELEASE_PHASE := 0.72
const AIRBORNE_KICK_COUNTER_MAX_WEIGHT := 0.86
const DROP_KICK_TUCK_END_PHASE := 0.43
const DROP_KICK_TUCK_FORWARD := 0.10
const DROP_KICK_TUCK_LIFT := 0.20
const DROP_KICK_EXTENSION_DISTANCE := 0.94
const DROP_KICK_EXTENSION_STAGGER := 0.055
const DROP_KICK_SPREAD_VARIATION := 0.045
const DROP_KICK_HEIGHT_VARIATION := 0.035
const TELEPORT_RESET_DISTANCE_SQUARED := 4.0
const STOP_SPEED_SQUARED := 0.01
const EPSILON := 0.000001

@export_flags_3d_physics var contact_collision_mask := (
	CharacterContactLayers.FOOT_CONTACT_QUERY
)

@onready var left_leg_root: Node3D = $LeftLeg
@onready var right_leg_root: Node3D = $RightLeg


class GroundSample:
	var hit := false
	var position := Vector3.ZERO
	var normal := Vector3.UP
	var surface: StringName = PhysicalSurface.CONCRETE


class LegState:
	var side: int
	var lateral_sign: float
	var available := true
	var root: Node3D
	var upper_visual: MeshInstance3D
	var lower_visual: MeshInstance3D
	var foot_visual: MeshInstance3D
	var planted := false
	var swinging := false
	var current_foot_world := Vector3.ZERO
	var planted_foot_world := Vector3.ZERO
	var swing_start_world := Vector3.ZERO
	var swing_target_world := Vector3.ZERO
	var swing_progress := 1.0
	var swing_duration := MAX_STEP_DURATION
	var gait_driven_swing := false
	var swing_start_cycle := 0.0
	var swing_impact_cycle := 0.0
	var impact_sequence := -1
	var profile_sequence := 0
	var step_lead_seconds := 0.062
	var step_max_lead_distance := 0.38
	var step_forward_variation := 0.0
	var step_stance_scale := 1.0
	var step_lateral_variation := 0.0
	var step_arc_height := STEP_ARC_HEIGHT
	var step_duration_scale := 1.0
	var step_trigger_distance := STEP_TRIGGER_DISTANCE
	var landing_swing := false
	var landing_target_valid := false
	var current_normal := Vector3.UP
	var swing_start_normal := Vector3.UP
	var swing_target_normal := Vector3.UP
	var previous_bend_world := Vector3.ZERO
	var has_grounded_pose := false
	var last_grounded_foot_local := Vector3.ZERO
	var last_grounded_normal_local := Vector3.UP
	var air_takeoff_foot_local := Vector3.ZERO
	var air_takeoff_normal_local := Vector3.UP
	var air_current_foot_local := Vector3.ZERO
	var air_velocity_local := Vector3.ZERO
	var query := PhysicsRayQueryParameters3D.new()
	var center_sample := GroundSample.new()
	var toe_sample := GroundSample.new()
	var heel_sample := GroundSample.new()
	var solution := LimbKinematics.TwoBoneSolution.new()

	func _init(new_side: int, new_root: Node3D) -> void:
		side = new_side
		lateral_sign = -1.0 if side == Side.LEFT else 1.0
		root = new_root
		upper_visual = root.get_node("Upper") as MeshInstance3D
		lower_visual = root.get_node("Lower") as MeshInstance3D
		foot_visual = root.get_node("Foot") as MeshInstance3D
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = false
		query.hit_back_faces = false


var _left_state: LegState
var _right_state: LegState
var _requested_left_available := true
var _requested_right_available := true
var _initialized := false
var _pose_initialized := false
var _was_grounded := false
var _last_root_origin := Vector3.ZERO
var _last_gait_sequence := -1
var _last_scheduled_impact_sequence := -1
var _next_preferred_side := Side.LEFT
var _active_swing_side := -1
var _recovery_step_sequence := 0
var _foot_contact_event_side := -1
var _foot_contact_event_sequence := -1
var _foot_contact_event_position := Vector3.ZERO
var _foot_contact_event_surface: StringName = PhysicalSurface.CONCRETE
var _query_exclusions: Array[RID] = []
var _landing_query := PhysicsRayQueryParameters3D.new()
var _probe_cast_count := 0
var _air_pose_progress := 1.0
var _air_pose_elapsed := 0.0
var _air_takeoff_up_speed := 0.0
var _air_motion_phase := 0.0
var _air_motion_frequency_scale := 1.0
var _air_motion_amplitude_scale := 1.0
var _air_stance_scale := 1.0
var _air_tuck_variation := 0.0
var _air_left_pose_bias := Vector3.ZERO
var _air_right_pose_bias := Vector3.ZERO
var _air_preferred_landing_side := Side.LEFT
var _air_landing_stagger_duration := AIR_LANDING_STAGGER_MIN_SECONDS
var _landing_pose_weight := 0.0
var _landing_ground_clearance := INF
var _expression_identity := 0
var _fallback_jump_sequence := 0
var _expression_rng := RandomNumberGenerator.new()
var _body_yield_roll := 0.0
var _body_yield_drop := 0.0
var _body_yield_lateral_shift := 0.0
var _body_balance_pitch := 0.0
var _body_balance_roll := 0.0
var _body_balance_shift := Vector3.ZERO
var _balance_replant_distance := BALANCE_REPLANT_DISTANCE_RANGE.x
var _balance_direction_commit_seconds := BALANCE_DIRECTION_COMMIT_SECONDS_RANGE.x
var _movement_direction_commit_elapsed := 0.0
var _previous_movement_direction := Vector3.ZERO
var _momentum_recovery_weight := 0.0
var _momentum_recovery_direction := Vector3.FORWARD
var _support_failure := false
var _last_landing_sequence := -1
var _landing_compression_elapsed := 0.0
var _landing_compression_peak_seconds := 0.0
var _landing_compression_recovery_seconds := 0.0
var _landing_compression_depth := 0.0
var _landing_compression := 0.0
var _landing_compression_active := false
var _presented_kick_sequence := -1
var _kick_side := -1
var _kick_active := false
var _kick_start_foot_local := Vector3.ZERO
var _kick_return_foot_local := Vector3.ZERO
var _kick_style := ServerPlayer.KickStyle.SINGLE
var _dropkick_start_left_local := Vector3.ZERO
var _dropkick_start_right_local := Vector3.ZERO
var _dropkick_left_lead := 0.0
var _dropkick_right_lead := 0.0
var _dropkick_spread := 0.0
var _dropkick_height_bias := 0.0
var _dropkick_tuck_asymmetry := 0.0


func _ready() -> void:
	_left_state = LegState.new(Side.LEFT, left_leg_root)
	_right_state = LegState.new(Side.RIGHT, right_leg_root)
	_landing_query.collide_with_areas = false
	_landing_query.collide_with_bodies = true
	_landing_query.hit_from_inside = false
	_landing_query.hit_back_faces = false
	_apply_requested_presence()


func set_limb_presence(left_available: bool, right_available: bool) -> void:
	_requested_left_available = left_available
	_requested_right_available = right_available
	if not is_node_ready():
		return
	var changed := (
		_left_state.available != left_available
		or _right_state.available != right_available
	)
	_apply_requested_presence()
	if changed:
		reset_contacts()


func set_expression_identity(identity: int) -> void:
	_expression_identity = maxi(identity, 0)
	var key := _expression_identity + 1
	_balance_replant_distance = lerpf(
		BALANCE_REPLANT_DISTANCE_RANGE.x,
		BALANCE_REPLANT_DISTANCE_RANGE.y,
		ExpressionDeterminism.ratio(key * 214013 + 2531011)
	)
	_balance_direction_commit_seconds = lerpf(
		BALANCE_DIRECTION_COMMIT_SECONDS_RANGE.x,
		BALANCE_DIRECTION_COMMIT_SECONDS_RANGE.y,
		ExpressionDeterminism.ratio(key * 1103515245 + 12345)
	)


func set_query_exclusion_rid(body_rid: RID) -> void:
	if _query_exclusions.size() == 1 and _query_exclusions[0] == body_rid:
		return
	_query_exclusions.clear()
	if body_rid.is_valid():
		_query_exclusions.append(body_rid)
	if is_node_ready():
		_left_state.query.exclude = _query_exclusions
		_right_state.query.exclude = _query_exclusions
		_landing_query.exclude = _query_exclusions


func reset_contacts() -> void:
	_initialized = false
	_pose_initialized = false
	_active_swing_side = -1
	_last_gait_sequence = -1
	_last_scheduled_impact_sequence = -1
	_foot_contact_event_side = -1
	_foot_contact_event_sequence = -1
	_landing_pose_weight = 0.0
	_landing_ground_clearance = INF
	_movement_direction_commit_elapsed = 0.0
	_previous_movement_direction = Vector3.ZERO
	_kick_active = false
	_kick_side = -1
	_kick_style = ServerPlayer.KickStyle.SINGLE
	if is_node_ready():
		_clear_leg_contact(_left_state)
		_clear_leg_contact(_right_state)


func update_pose(
	delta: float,
	world_velocity: Vector3,
	grounded: bool,
	gait_cycle: float,
	gait_active: bool,
	jump_sequence: int = -1,
	landing_sequence: int = 0,
	landing_impact_strength: float = 0.0,
	momentum_recovery_weight: float = 0.0,
	kick_sequence: int = 0,
	kick_side: int = -1,
	kick_phase: float = 1.0,
	kick_direction: Vector3 = Vector3.FORWARD,
	kick_intensity: float = 1.0,
	kick_authority_active: bool = false,
	kick_style: int = ServerPlayer.KickStyle.SINGLE
) -> void:
	if not is_node_ready():
		return
	# Contact events live for exactly one presentation update and need no queue allocation because
	# the biped scheduler permits only one active swing.
	_foot_contact_event_side = -1
	_foot_contact_event_sequence = -1
	var safe_delta := maxf(delta, 0.0)
	var kick_blocks_gait := _kick_active or kick_authority_active or (
		kick_phase < 1.0
		and kick_sequence > 0
		and is_leg_available(kick_side)
	)
	_update_momentum_recovery(
		world_velocity,
		momentum_recovery_weight
	)
	_update_landing_compression(
		safe_delta,
		grounded,
		landing_sequence,
		landing_impact_strength
	)
	var root_origin := global_position
	if (
		_initialized
		and root_origin.distance_squared_to(_last_root_origin)
		> TELEPORT_RESET_DISTANCE_SQUARED
	):
		reset_contacts()
	_last_root_origin = root_origin

	if not grounded:
		_update_movement_commitment(safe_delta, world_velocity, false)
		if _was_grounded:
			_begin_air_pose(world_velocity, gait_cycle, jump_sequence)
		elif not _pose_initialized:
			_snap_air_pose(world_velocity, gait_cycle, jump_sequence)
		else:
			_update_air_pose(safe_delta, world_velocity)
		_was_grounded = false
		_update_body_yield(safe_delta, false)
		_apply_kick_override(
			kick_sequence,
			kick_side,
			kick_phase,
			kick_direction,
			kick_intensity,
			kick_authority_active,
			kick_style,
			false
		)
		_solve_available_legs()
		return

	if not _initialized or not _was_grounded:
		if _pose_initialized and not _was_grounded:
			_begin_grounded_landing(gait_cycle)
		else:
			_initialize_ground_contacts(gait_cycle)
	_was_grounded = true
	_update_movement_commitment(safe_delta, world_velocity, true)
	if not gait_active:
		_release_active_swing_from_gait()

	_advance_active_swing(safe_delta, world_velocity, gait_cycle)
	var gait_sequence := floori(gait_cycle) if is_finite(gait_cycle) else 0
	var gait_crossed := gait_sequence > _last_gait_sequence
	if gait_sequence < _last_gait_sequence:
		_initialize_ground_contacts(gait_cycle)
		gait_crossed = false
	_last_gait_sequence = gait_sequence

	if _active_swing_side < 0 and not kick_blocks_gait:
		var requested_side := -1
		var impact_sequence := gait_sequence + 1
		var speed := Vector2(world_velocity.x, world_velocity.z).length()
		var swing_start_phase := PlayerGait.get_swing_start_phase_for_motion(
			speed,
			_expression_identity,
			impact_sequence
		)
		var gait_phase := gait_cycle - floorf(gait_cycle)
		var missed_gait_impact := (
			gait_active
			and gait_crossed
			and gait_sequence > _last_scheduled_impact_sequence
		)
		var gait_step_due := (
			gait_active
			and impact_sequence > _last_scheduled_impact_sequence
			and gait_phase >= swing_start_phase
		)
		var balance_requires_replant := (
			_momentum_recovery_weight > 0.001
			or _balance_requires_replant(world_velocity)
		)
		if missed_gait_impact and balance_requires_replant:
			requested_side = _available_side_for_preference(
				_next_preferred_side
			)
			_start_step(
				requested_side,
				world_velocity,
				gait_sequence,
				gait_cycle,
				false
			)
			_last_scheduled_impact_sequence = gait_sequence
		elif gait_step_due and balance_requires_replant:
			requested_side = _available_side_for_preference(
				_next_preferred_side
			)
			_start_step(
				requested_side,
				world_velocity,
				impact_sequence,
				gait_cycle,
				true
			)
			_last_scheduled_impact_sequence = impact_sequence
		else:
			# Translation is owned by the shared gait. Only turning/stopping recovery may schedule an
			# extra visual step; this removes the former rapid emergency-step loop at normal speed.
			requested_side = _select_step_side(
				world_velocity,
				false,
				not gait_active
			)
		if requested_side >= 0:
			if not gait_step_due and not missed_gait_impact:
				_recovery_step_sequence += 1
				_start_step(
					requested_side,
					world_velocity,
					-(
						_expression_identity * 4096
						+ _recovery_step_sequence
					),
					gait_cycle,
					false
				)

	_apply_kick_override(
		kick_sequence,
		kick_side,
		kick_phase,
		kick_direction,
		kick_intensity,
		kick_authority_active,
		kick_style,
		true
	)
	_update_body_yield(safe_delta, true)
	_solve_available_legs()
	_store_grounded_pose()


func get_present_leg_count() -> int:
	if not is_node_ready():
		return int(_requested_left_available) + int(_requested_right_available)
	return int(_left_state.available) + int(_right_state.available)


func is_leg_available(side: int) -> bool:
	var state := _state_for_side(side)
	return state != null and state.available


func is_foot_planted(side: int) -> bool:
	var state := _state_for_side(side)
	return state != null and state.available and state.planted


func is_foot_swinging(side: int) -> bool:
	var state := _state_for_side(side)
	return state != null and state.available and state.swinging


func get_foot_world_position(side: int) -> Vector3:
	var state := _state_for_side(side)
	return state.current_foot_world if state != null else global_position


func get_leg_points(side: int) -> PackedVector3Array:
	var state := _state_for_side(side)
	if state == null or not state.available:
		return PackedVector3Array()
	return PackedVector3Array([
		state.solution.hip,
		state.solution.knee,
		state.solution.tip,
	])


func get_hip_world_position(side: int) -> Vector3:
	var state := _state_for_side(side)
	return _hip_world(state) if state != null else global_position


func get_knee_world_position(side: int) -> Vector3:
	var state := _state_for_side(side)
	return state.solution.knee if state != null else global_position


func get_ankle_world_position(side: int) -> Vector3:
	var state := _state_for_side(side)
	return state.solution.tip if state != null else global_position


func get_foot_world_basis(side: int) -> Basis:
	var state := _state_for_side(side)
	if state == null or state.foot_visual == null:
		return global_basis.orthonormalized()
	return state.foot_visual.global_basis.orthonormalized()


func get_active_swing_side() -> int:
	return _active_swing_side


func get_swing_progress(side: int) -> float:
	var state := _state_for_side(side)
	if state == null or not state.available:
		return 1.0
	return clampf(state.swing_progress, 0.0, 1.0)


func get_swing_target_world_position(side: int) -> Vector3:
	var state := _state_for_side(side)
	if state == null or not state.available:
		return global_position
	return state.swing_target_world


func suggest_kick_side(world_forward: Vector3, gait_cycle := 0.0) -> int:
	var left_available := is_leg_available(Side.LEFT)
	var right_available := is_leg_available(Side.RIGHT)
	if not left_available and not right_available:
		return -1
	if left_available and not right_available:
		return Side.LEFT
	if right_available and not left_available:
		return Side.RIGHT
	# A foot already in flight is carrying less support load and can turn its current motion into the
	# kick without first teleporting out of a planted stance.
	if _active_swing_side >= 0 and is_leg_available(_active_swing_side):
		return _active_swing_side
	if _left_state.swinging != _right_state.swinging:
		return Side.LEFT if _left_state.swinging else Side.RIGHT
	if _left_state.planted != _right_state.planted:
		return Side.RIGHT if _left_state.planted else Side.LEFT
	var forward := Vector3(world_forward.x, 0.0, world_forward.z)
	if not forward.is_finite() or forward.length_squared() <= EPSILON:
		forward = -global_basis.z
	forward = forward.normalized()
	var left_lead := (
		_left_state.current_foot_world - _hip_world(_left_state)
	).dot(forward)
	var right_lead := (
		_right_state.current_foot_world - _hip_world(_right_state)
	).dot(forward)
	if absf(left_lead - right_lead) > 0.018:
		return Side.LEFT if left_lead > right_lead else Side.RIGHT
	# Exact stance ties are resolved by the same shared gait parity on every peer.
	return Side.LEFT if posmod(floori(gait_cycle), 2) == 0 else Side.RIGHT


func is_kick_active() -> bool:
	return _kick_active


func get_kick_side() -> int:
	return _kick_side


func has_foot_contact_event() -> bool:
	return _foot_contact_event_side >= 0


func get_foot_contact_event_side() -> int:
	return _foot_contact_event_side


func get_foot_contact_event_sequence() -> int:
	return _foot_contact_event_sequence


func get_foot_contact_event_position() -> Vector3:
	return _foot_contact_event_position


func get_foot_contact_event_surface() -> StringName:
	return _foot_contact_event_surface


func get_probe_cast_count() -> int:
	return _probe_cast_count


func get_landing_pose_weight() -> float:
	return _landing_pose_weight


func get_landing_ground_clearance() -> float:
	return _landing_ground_clearance


func get_body_yield_rotation() -> Vector3:
	return Vector3(
		_body_balance_pitch,
		0.0,
		clampf(
			_body_yield_roll + _body_balance_roll,
			-BODY_YIELD_MAX_ROLL - BODY_BALANCE_MAX_ROLL,
			BODY_YIELD_MAX_ROLL + BODY_BALANCE_MAX_ROLL
		)
	)


func get_body_yield_offset() -> Vector3:
	return Vector3(
		_body_yield_lateral_shift + _body_balance_shift.x,
		_body_yield_drop - _landing_compression,
		_body_balance_shift.z
	)


func get_horizontal_support_error() -> float:
	return _maximum_rest_contact_error()


func get_landing_compression() -> float:
	return _landing_compression


func has_support_failure() -> bool:
	return _support_failure


func _apply_requested_presence() -> void:
	_left_state.available = _requested_left_available
	_right_state.available = _requested_right_available
	left_leg_root.visible = _requested_left_available
	right_leg_root.visible = _requested_right_available
	if not _requested_left_available:
		_clear_leg_contact(_left_state)
	if not _requested_right_available:
		_clear_leg_contact(_right_state)


func _clear_leg_contact(state: LegState) -> void:
	state.planted = false
	state.swinging = false
	state.landing_swing = false
	state.gait_driven_swing = false
	state.impact_sequence = -1
	state.landing_target_valid = false
	state.swing_progress = 1.0
	state.previous_bend_world = Vector3.ZERO
	state.has_grounded_pose = false


func _initialize_ground_contacts(gait_cycle: float) -> void:
	_active_swing_side = -1
	_support_failure = false
	var gait_sequence := floori(gait_cycle) if is_finite(gait_cycle) else 0
	_configure_step_profile(_left_state, gait_sequence * 2, 0.0)
	_configure_step_profile(_right_state, gait_sequence * 2 + 1, 0.0)
	_initialize_leg_contact(_left_state)
	_initialize_leg_contact(_right_state)
	_last_gait_sequence = gait_sequence
	_last_scheduled_impact_sequence = gait_sequence
	_next_preferred_side = _available_side_for_preference(
		Side.RIGHT if posmod(gait_sequence, 2) == 0 else Side.LEFT
	)
	_initialized = true
	_pose_initialized = true
	_landing_pose_weight = 1.0
	_landing_ground_clearance = 0.0


func _initialize_leg_contact(state: LegState) -> void:
	if not state.available:
		_clear_leg_contact(state)
		return
	var desired := _rest_foot_world(state)
	var sampled := _sample_contact(state, desired)
	state.current_foot_world = (
		state.center_sample.position if sampled else desired
	)
	state.planted_foot_world = state.current_foot_world
	state.current_normal = (
		state.center_sample.normal if sampled else Vector3.UP
	)
	state.swing_start_normal = state.current_normal
	state.swing_target_normal = state.current_normal
	state.planted = sampled
	state.swinging = false
	state.landing_swing = false
	state.gait_driven_swing = false
	state.impact_sequence = -1
	state.swing_progress = 1.0
	state.landing_target_valid = sampled


func _begin_grounded_landing(gait_cycle: float) -> void:
	_active_swing_side = -1
	_support_failure = false
	var gait_sequence := floori(gait_cycle) if is_finite(gait_cycle) else 0
	_last_gait_sequence = gait_sequence
	_last_scheduled_impact_sequence = gait_sequence
	_next_preferred_side = _available_side_for_preference(
		Side.RIGHT if posmod(gait_sequence, 2) == 0 else Side.LEFT
	)
	_prepare_landing_contact(_left_state)
	_prepare_landing_contact(_right_state)
	var present_count := get_present_leg_count()
	if present_count <= 0:
		_initialized = true
		_pose_initialized = true
		return
	if present_count == 1:
		var only_state := _left_state if _left_state.available else _right_state
		if only_state.landing_target_valid:
			_plant_prepared_landing_contact(only_state)
		else:
			_support_failure = true
		_initialized = true
		_pose_initialized = true
		return
	var valid_count := (
		int(_left_state.landing_target_valid)
		+ int(_right_state.landing_target_valid)
	)
	if valid_count < 2:
		_support_failure = true
		if _left_state.landing_target_valid:
			_plant_prepared_landing_contact(_left_state)
		if _right_state.landing_target_valid:
			_plant_prepared_landing_contact(_right_state)
		_initialized = true
		_pose_initialized = true
		return
	var left_distance := _prepared_landing_distance(_left_state)
	var right_distance := _prepared_landing_distance(_right_state)
	var primary_side := (
		_air_preferred_landing_side
		if absf(left_distance - right_distance) <= 0.015
		else Side.LEFT if left_distance < right_distance else Side.RIGHT
	)
	var secondary_side := Side.RIGHT if primary_side == Side.LEFT else Side.LEFT
	_plant_prepared_landing_contact(_state_for_side(primary_side))
	_start_prepared_landing_contact(_state_for_side(secondary_side))
	_initialized = true
	_pose_initialized = true


func _prepare_landing_contact(state: LegState) -> void:
	if not state.available:
		_clear_leg_contact(state)
		return
	var desired := _rest_foot_world(state)
	state.landing_target_valid = _sample_contact(state, desired)
	state.swing_target_world = (
		state.center_sample.position
		if state.landing_target_valid
		else desired
	)
	state.swing_target_normal = (
		state.center_sample.normal
		if state.landing_target_valid
		else Vector3.UP
	)


func _prepared_landing_distance(state: LegState) -> float:
	var offset := state.swing_target_world - state.current_foot_world
	return absf(offset.y) + Vector2(offset.x, offset.z).length() * 0.2


func _plant_prepared_landing_contact(state: LegState) -> void:
	state.current_foot_world = state.swing_target_world
	state.planted_foot_world = state.swing_target_world
	state.current_normal = state.swing_target_normal
	state.swinging = false
	state.landing_swing = false
	state.gait_driven_swing = false
	state.impact_sequence = -1
	state.swing_progress = 1.0
	state.planted = state.landing_target_valid


func _start_prepared_landing_contact(state: LegState) -> void:
	state.swing_start_world = state.current_foot_world
	state.swing_start_normal = state.current_normal
	state.swing_progress = 0.0
	state.swing_duration = _air_landing_stagger_duration
	state.swinging = true
	state.landing_swing = true
	state.gait_driven_swing = false
	state.impact_sequence = -1
	state.planted = false
	_active_swing_side = state.side


func _begin_air_pose(
	world_velocity: Vector3,
	gait_cycle: float,
	jump_sequence: int
) -> void:
	_active_swing_side = -1
	_initialized = false
	_air_pose_progress = 0.0
	_air_pose_elapsed = 0.0
	_air_takeoff_up_speed = maxf(world_velocity.y, 0.0)
	_air_motion_phase = (
		fposmod(gait_cycle * PI, TAU)
		if is_finite(gait_cycle)
		else 0.0
	)
	_configure_air_expression(jump_sequence)
	_landing_pose_weight = 0.0
	_landing_ground_clearance = INF
	_begin_air_leg(_left_state)
	_begin_air_leg(_right_state)
	_pose_initialized = true


func _begin_air_leg(state: LegState) -> void:
	if not state.available:
		return
	state.air_takeoff_foot_local = (
		state.last_grounded_foot_local
		if state.has_grounded_pose
		else to_local(state.current_foot_world)
	)
	state.air_takeoff_normal_local = (
		state.last_grounded_normal_local
		if state.has_grounded_pose
		else global_basis.inverse() * state.current_normal
	).normalized()
	state.air_current_foot_local = state.air_takeoff_foot_local
	state.air_velocity_local = Vector3.ZERO
	state.current_foot_world = global_transform * state.air_takeoff_foot_local
	state.current_normal = (
		global_basis * state.air_takeoff_normal_local
	).normalized()
	state.planted = false
	state.swinging = false
	state.landing_swing = false


func _update_air_pose(delta: float, world_velocity: Vector3) -> void:
	_active_swing_side = -1
	_initialized = false
	_air_pose_elapsed += maxf(delta, 0.0)
	_air_motion_phase = fposmod(
		_air_motion_phase
		+ maxf(delta, 0.0)
		* TAU
		* AIR_MOTION_FREQUENCY_HZ
		* _air_motion_frequency_scale,
		TAU
	)
	var recovery_progress := clampf(
		_air_pose_elapsed / AIR_POSE_RECOVERY_SECONDS,
		0.0,
		1.0
	)
	if _air_takeoff_up_speed > 0.01:
		recovery_progress = maxf(
			recovery_progress,
			1.0 - clampf(
				maxf(world_velocity.y, 0.0) / _air_takeoff_up_speed,
				0.0,
				1.0
			)
		)
	_air_pose_progress = maxf(_air_pose_progress, recovery_progress)
	_update_landing_pose_weight(world_velocity)
	var eased := (
		_air_pose_progress
		* _air_pose_progress
		* (3.0 - 2.0 * _air_pose_progress)
	)
	_update_air_leg(_left_state, world_velocity, eased, delta)
	_update_air_leg(_right_state, world_velocity, eased, delta)


func _snap_air_pose(
	world_velocity: Vector3,
	gait_cycle: float,
	jump_sequence: int
) -> void:
	_active_swing_side = -1
	_initialized = false
	_air_pose_progress = 1.0
	_air_pose_elapsed = AIR_POSE_RECOVERY_SECONDS
	_air_takeoff_up_speed = maxf(world_velocity.y, 0.0)
	_air_motion_phase = (
		fposmod(gait_cycle * PI, TAU)
		if is_finite(gait_cycle)
		else 0.0
	)
	_configure_air_expression(jump_sequence)
	_landing_pose_weight = 0.0
	_landing_ground_clearance = INF
	_snap_air_leg(_left_state, world_velocity)
	_snap_air_leg(_right_state, world_velocity)
	_pose_initialized = true


func _snap_air_leg(state: LegState, world_velocity: Vector3) -> void:
	if not state.available:
		return
	state.air_current_foot_local = _landing_ready_foot_local(
		state,
		world_velocity
	)
	state.air_velocity_local = Vector3.ZERO
	state.current_foot_world = global_transform * state.air_current_foot_local
	state.current_normal = Vector3.UP
	state.planted = false
	state.swinging = false
	state.landing_swing = false


func _update_air_leg(
	state: LegState,
	world_velocity: Vector3,
	recovery_weight: float,
	delta: float
) -> void:
	if not state.available:
		return
	var target_local := _landing_ready_foot_local(state, world_velocity)
	target_local += _air_motion_offset(state, recovery_weight)
	state.air_current_foot_local = _smooth_damp_vector3(
		state.air_current_foot_local,
		target_local,
		state,
		delta
	)
	var normal_local := state.air_takeoff_normal_local.lerp(
		Vector3.UP,
		recovery_weight
	).normalized()
	state.current_foot_world = global_transform * state.air_current_foot_local
	state.current_normal = (global_basis * normal_local).normalized()
	state.planted = false
	state.swinging = false


func _landing_ready_foot_local(
	state: LegState,
	world_velocity: Vector3
) -> Vector3:
	var local_velocity := global_basis.inverse() * Vector3(
		world_velocity.x,
		0.0,
		world_velocity.z
	)
	var speed := local_velocity.length()
	var landing_lead := Vector3.ZERO
	if speed > 0.001:
		landing_lead = local_velocity / speed * minf(
			speed * AIR_LANDING_LEAD_SECONDS,
			AIR_LANDING_MAX_LEAD_DISTANCE
		)
	var expression_bias := (
		_air_left_pose_bias
		if state.side == Side.LEFT
		else _air_right_pose_bias
	)
	# Keep the authored variation visible through touchdown without allowing an extreme random draw
	# to compromise the safe landing envelope selected from real ground clearance.
	expression_bias *= lerpf(1.0, 0.42, _landing_pose_weight)
	return Vector3(
		state.lateral_sign * HIP_LATERAL_OFFSET * _air_stance_scale,
		(
			REST_FOOT_LOCAL_HEIGHT
			+ AIR_LANDING_TUCK_HEIGHT
			+ _air_tuck_variation
			- AIR_LANDING_EXTENSION_DISTANCE * _landing_pose_weight
		),
		0.0
	) + landing_lead + expression_bias


func _air_motion_offset(state: LegState, recovery_weight: float) -> Vector3:
	# A jump interrupts an alternating gait, so its free-limb correction should retain that phase
	# rather than becoming a mirrored mannequin pose. The right side is deliberately not offset by
	# exactly PI and each side receives a different secondary harmonic. This keeps both limbs in
	# continuous, coordinated motion without turning a long fall into a repetitive bicycle kick.
	var side_phase_offset := 0.0 if state.side == Side.LEFT else PI * 0.83
	var primary_phase := _air_motion_phase + side_phase_offset
	var secondary_phase := (
		_air_motion_phase * 1.57
		+ (0.45 if state.side == Side.LEFT else 2.05)
	)
	var landing_scale := lerpf(
		1.0,
		AIR_MOTION_LANDING_SCALE,
		_landing_pose_weight
	)
	var amplitude := (
		clampf(recovery_weight, 0.0, 1.0)
		* landing_scale
		* _air_motion_amplitude_scale
	)
	return Vector3(
		(
			state.lateral_sign
			* sin(secondary_phase)
			* AIR_MOTION_LATERAL_DISTANCE
		),
		(
			sin(primary_phase) * AIR_MOTION_VERTICAL_DISTANCE
			+ sin(secondary_phase) * AIR_MOTION_SECONDARY_DISTANCE
		),
		(
			sin(primary_phase + 0.62) * AIR_MOTION_FORWARD_DISTANCE
			+ sin(secondary_phase + 0.35)
			* AIR_MOTION_SECONDARY_DISTANCE
		)
	) * amplitude


func _configure_air_expression(jump_sequence: int) -> void:
	var resolved_sequence := jump_sequence
	if resolved_sequence < 0:
		_fallback_jump_sequence += 1
		resolved_sequence = _fallback_jump_sequence
	# Player identity and the server-owned accepted-jump sequence make this random-looking style
	# deterministic for every observer. The retained RNG avoids allocating a generator per jump.
	_expression_rng.seed = (
		int(_expression_identity + 1) * 73856093
		+ int(resolved_sequence + 1) * 19349663
	)
	_air_motion_phase = fposmod(
		_air_motion_phase + _sample_expressive_signed(0.72, 1.8),
		TAU
	)
	_air_motion_frequency_scale = 1.0 + _sample_expressive_signed(0.22, 2.1)
	_air_motion_amplitude_scale = 1.0 + _sample_expressive_signed(0.28, 1.9)
	_air_stance_scale = 1.0 + _sample_expressive_signed(0.13, 2.2)
	_air_tuck_variation = _sample_expressive_signed(0.026, 2.0)
	var height_split := _sample_expressive_signed(0.030, 1.75)
	_air_left_pose_bias = Vector3(
		_sample_expressive_signed(0.009, 2.2),
		height_split + _sample_expressive_signed(0.008, 2.2),
		_sample_expressive_signed(0.055, 1.8)
	)
	_air_right_pose_bias = Vector3(
		_sample_expressive_signed(0.009, 2.2),
		-height_split + _sample_expressive_signed(0.008, 2.2),
		_sample_expressive_signed(0.055, 1.8)
	)
	_air_preferred_landing_side = (
		Side.LEFT if _expression_rng.randf() < 0.5 else Side.RIGHT
	)
	_air_landing_stagger_duration = (
		AIR_LANDING_STAGGER_MIN_SECONDS
		+ pow(_expression_rng.randf(), 2.15)
		* AIR_LANDING_STAGGER_RANGE_SECONDS
	)


func _sample_expressive_signed(maximum: float, curve_power: float) -> float:
	var sample := _expression_rng.randf_range(-1.0, 1.0)
	# A power curve concentrates ordinary jumps around restrained body language while preserving a
	# nonlinear tail for the occasional stronger pose. Expressive systems should not feel uniform.
	return (
		signf(sample)
		* pow(absf(sample), maxf(curve_power, 1.0))
		* maxf(maximum, 0.0)
	)


func _update_landing_pose_weight(world_velocity: Vector3) -> void:
	_landing_pose_weight = 0.0
	_landing_ground_clearance = INF
	if get_present_leg_count() <= 0 or world_velocity.y > 0.0:
		return
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return
	_landing_query.from = global_position + Vector3.UP * LANDING_QUERY_UP
	_landing_query.to = (
		global_position
		+ Vector3.DOWN * LANDING_QUERY_DISTANCE
	)
	_landing_query.exclude = _query_exclusions
	_landing_query.collision_mask = contact_collision_mask
	var result := space_state.intersect_ray(_landing_query)
	_probe_cast_count += 1
	if result.is_empty():
		return
	var hit_position: Vector3 = result.get("position", global_position)
	_landing_ground_clearance = maxf(
		global_position.y
		- hit_position.y
		+ REST_FOOT_LOCAL_HEIGHT,
		0.0
	)
	var downward_speed := maxf(-world_velocity.y, 0.0)
	var prepare_clearance := clampf(
		(
			LANDING_PREPARE_BASE_CLEARANCE
			+ downward_speed * LANDING_PREPARE_LOOKAHEAD_SECONDS
		),
		LANDING_PREPARE_BASE_CLEARANCE,
		LANDING_PREPARE_MAX_CLEARANCE
	)
	var distance_weight := 1.0 - smoothstep(
		LANDING_FULL_CLEARANCE,
		prepare_clearance,
		_landing_ground_clearance
	)
	var descent_weight := clampf(
		downward_speed / LANDING_DESCENT_FULL_SPEED,
		0.0,
		1.0
	)
	_landing_pose_weight = clampf(
		distance_weight * descent_weight,
		0.0,
		1.0
	)


func _store_grounded_pose() -> void:
	_store_grounded_leg_pose(_left_state)
	_store_grounded_leg_pose(_right_state)


func _store_grounded_leg_pose(state: LegState) -> void:
	if not state.available:
		return
	var current_local := to_local(state.current_foot_world)
	state.last_grounded_foot_local = current_local
	state.last_grounded_normal_local = (
		global_basis.inverse() * state.current_normal
	).normalized()
	state.has_grounded_pose = true


func _update_body_yield(delta: float, grounded: bool) -> void:
	var target_roll := 0.0
	var target_drop := 0.0
	var target_lateral_shift := 0.0
	var target_balance_pitch := 0.0
	var target_balance_roll := 0.0
	var target_balance_shift := Vector3.ZERO
	if (
		grounded
		and _left_state.available
		and _right_state.available
		and (_left_state.planted or _left_state.swinging)
		and (_right_state.planted or _right_state.swinging)
	):
		var height_difference := (
			_right_state.current_foot_world.y
			- _left_state.current_foot_world.y
		)
		# Saturating support response: small discrepancies produce subtle organic yielding, while a
		# tall rock cannot fold the upper body without bound. The power-shaped drop gives large stance
		# splits disproportionately more compliance than ordinary uneven floor noise.
		var normalized_height := tanh(
			height_difference / BODY_YIELD_HEIGHT_SCALE
		)
		target_roll = normalized_height * BODY_YIELD_MAX_ROLL
		target_drop = -pow(absf(normalized_height), 1.35) * BODY_YIELD_MAX_DROP
		target_lateral_shift = (
			normalized_height * BODY_YIELD_MAX_LATERAL_SHIFT
		)
	if grounded:
		var support_offset := _support_offset_local()
		var lateral_balance := tanh(
			support_offset.x / BODY_BALANCE_FULL_OFFSET
		)
		var forward_balance := tanh(
			support_offset.z / BODY_BALANCE_FULL_OFFSET
		)
		# Before a replant, the upper body counterbalances the hips over the existing support polygon.
		# Once a step lands these terms naturally collapse because the contact follows the body.
		target_balance_pitch = -forward_balance * BODY_BALANCE_MAX_PITCH
		target_balance_roll = lateral_balance * BODY_BALANCE_MAX_ROLL
		target_balance_shift = Vector3(
			-lateral_balance * BODY_BALANCE_MAX_SHIFT,
			0.0,
			-forward_balance * BODY_BALANCE_MAX_SHIFT
		)
	var weight := 1.0 - exp(
		-maxf(delta, 0.0) * BODY_YIELD_RESPONSE
	)
	_body_yield_roll = lerp_angle(_body_yield_roll, target_roll, weight)
	_body_yield_drop = lerpf(_body_yield_drop, target_drop, weight)
	_body_yield_lateral_shift = lerpf(
		_body_yield_lateral_shift,
		target_lateral_shift,
		weight
	)
	_body_balance_pitch = lerp_angle(
		_body_balance_pitch,
		target_balance_pitch,
		weight
	)
	_body_balance_roll = lerp_angle(
		_body_balance_roll,
		target_balance_roll,
		weight
	)
	_body_balance_shift = _body_balance_shift.lerp(
		target_balance_shift,
		weight
	)


func _update_movement_commitment(
	delta: float,
	horizontal_velocity: Vector3,
	grounded: bool
) -> void:
	var horizontal := Vector3(
		horizontal_velocity.x,
		0.0,
		horizontal_velocity.z
	)
	if not grounded or horizontal.length_squared() <= PlayerGait.MINIMUM_SPEED_SQUARED:
		_movement_direction_commit_elapsed = 0.0
		_previous_movement_direction = Vector3.ZERO
		return
	var direction := horizontal.normalized()
	if (
		_previous_movement_direction.length_squared() > EPSILON
		and direction.dot(_previous_movement_direction)
		< BALANCE_DIRECTION_REVERSAL_DOT
	):
		_movement_direction_commit_elapsed = 0.0
	else:
		_movement_direction_commit_elapsed = minf(
			_movement_direction_commit_elapsed + maxf(delta, 0.0),
			_balance_direction_commit_seconds
		)
	_previous_movement_direction = direction


func _update_momentum_recovery(
	world_velocity: Vector3,
	recovery_weight: float
) -> void:
	var next_weight := clampf(recovery_weight, 0.0, 1.0)
	var horizontal := Vector3(
		world_velocity.x,
		0.0,
		world_velocity.z
	)
	if (
		next_weight > 0.001
		and horizontal.length_squared() > PlayerGait.MINIMUM_SPEED_SQUARED
	):
		_momentum_recovery_direction = horizontal.normalized()
	_momentum_recovery_weight = next_weight


func _balance_requires_replant(horizontal_velocity: Vector3) -> bool:
	var support_error := _maximum_rest_contact_error()
	if support_error >= EMERGENCY_REACH_DISTANCE:
		return true
	if (
		_movement_direction_commit_elapsed
		< _balance_direction_commit_seconds
	):
		return false
	var speed := Vector2(
		horizontal_velocity.x,
		horizontal_velocity.z
	).length()
	var run_weight := PlayerGait.get_run_profile_weight(speed)
	var replant_distance := lerpf(
		_balance_replant_distance,
		_balance_replant_distance * BALANCE_FAST_REPLANT_DISTANCE_SCALE,
		run_weight
	)
	return support_error >= replant_distance


func _maximum_rest_contact_error() -> float:
	var maximum_error := 0.0
	if _left_state != null and _left_state.available:
		maximum_error = maxf(
			maximum_error,
			_rest_contact_error(_left_state)
		)
	if _right_state != null and _right_state.available:
		maximum_error = maxf(
			maximum_error,
			_rest_contact_error(_right_state)
		)
	return maximum_error


func _rest_contact_error(state: LegState) -> float:
	var offset := _rest_foot_world(state) - state.current_foot_world
	return Vector2(offset.x, offset.z).length()


func _support_offset_local() -> Vector3:
	var accumulated := Vector3.ZERO
	var support_count := 0
	if _left_state != null and _left_state.available and _left_state.planted:
		accumulated += _rest_foot_world(_left_state) - _left_state.current_foot_world
		support_count += 1
	if _right_state != null and _right_state.available and _right_state.planted:
		accumulated += _rest_foot_world(_right_state) - _right_state.current_foot_world
		support_count += 1
	if support_count <= 0:
		return Vector3.ZERO
	return global_basis.inverse() * (accumulated / float(support_count))


func _update_landing_compression(
	delta: float,
	grounded: bool,
	landing_sequence: int,
	impact_strength: float
) -> void:
	var safe_sequence := maxi(landing_sequence, 0)
	var safe_strength := clampf(impact_strength, 0.0, 1.0)
	# A joining observer receives the latest cumulative sequence, not an event backlog. Establishing
	# that value as the baseline prevents an old landing from replaying when its rig first appears.
	if _last_landing_sequence < 0:
		_last_landing_sequence = safe_sequence
		_landing_compression = 0.0
		return
	if safe_sequence > _last_landing_sequence:
		# Unreliable snapshots may arrive while presentation still considers the proxy airborne. Keep
		# the sequence pending until its grounded state arrives instead of silently consuming the hit.
		if not grounded:
			return
		_last_landing_sequence = safe_sequence
		if safe_strength > 0.0001:
			_landing_compression_elapsed = 0.0
			_landing_compression_peak_seconds = lerpf(
				LANDING_COMPRESSION_PEAK_SECONDS_RANGE.x,
				LANDING_COMPRESSION_PEAK_SECONDS_RANGE.y,
				safe_strength
			)
			_landing_compression_recovery_seconds = lerpf(
				LANDING_COMPRESSION_RECOVERY_SECONDS_RANGE.x,
				LANDING_COMPRESSION_RECOVERY_SECONDS_RANGE.y,
				safe_strength
			)
			_landing_compression_depth = lerpf(
				LANDING_COMPRESSION_DROP_RANGE.x,
				LANDING_COMPRESSION_DROP_RANGE.y,
				pow(safe_strength, 1.18)
			)
			_landing_compression_active = true
	if not _landing_compression_active:
		_landing_compression = 0.0
		return
	_landing_compression_elapsed += maxf(delta, 0.0)
	if _landing_compression_elapsed <= _landing_compression_peak_seconds:
		var load_ratio := clampf(
			_landing_compression_elapsed
			/ maxf(_landing_compression_peak_seconds, EPSILON),
			0.0,
			1.0
		)
		# The knee accepts load quickly but with zero slope at contact and peak flexion.
		_landing_compression = _landing_compression_depth * smoothstep(
			0.0,
			1.0,
			load_ratio
		)
		return
	var recovery_elapsed := (
		_landing_compression_elapsed - _landing_compression_peak_seconds
	)
	var recovery_ratio := clampf(
		recovery_elapsed
		/ maxf(_landing_compression_recovery_seconds, EPSILON),
		0.0,
		1.0
	)
	_landing_compression = _landing_compression_depth * (
		1.0 - smoothstep(0.0, 1.0, recovery_ratio)
	)
	if recovery_ratio >= 1.0:
		_landing_compression = 0.0
		_landing_compression_active = false


func _smooth_damp_vector3(
	current: Vector3,
	target: Vector3,
	state: LegState,
	delta: float
) -> Vector3:
	var safe_delta := maxf(delta, 0.0)
	if safe_delta <= EPSILON:
		return current
	# Stable critically damped response (the rational decay approximation used by SmoothDamp-style
	# second-order controllers). Unlike the old origin-to-target blend, this carries velocity from
	# one frame to the next and cannot acquire a mid-curve positional shove.
	var smooth_time := lerpf(
		AIR_POSE_ASCENT_SMOOTH_TIME,
		AIR_POSE_LANDING_SMOOTH_TIME,
		_landing_pose_weight
	)
	var omega := 2.0 / smooth_time
	var scaled_delta := omega * safe_delta
	var decay := 1.0 / (
		1.0
		+ scaled_delta
		+ 0.48 * scaled_delta * scaled_delta
		+ 0.235 * scaled_delta * scaled_delta * scaled_delta
	)
	var displacement := current - target
	var maximum_displacement := AIR_POSE_MAX_LOCAL_SPEED * smooth_time
	displacement = displacement.limit_length(maximum_displacement)
	var adjusted_target := current - displacement
	var temporary := (
		state.air_velocity_local + displacement * omega
	) * safe_delta
	state.air_velocity_local = (
		state.air_velocity_local - temporary * omega
	) * decay
	var result := adjusted_target + (displacement + temporary) * decay
	# Do not overshoot a moving expressive target; its own harmonics provide the intended motion.
	var target_delta := target - current
	var remaining_delta := target - result
	if target_delta.dot(remaining_delta) < 0.0:
		result = target
		state.air_velocity_local = Vector3.ZERO
	return result


func _advance_active_swing(
	delta: float,
	horizontal_velocity: Vector3,
	gait_cycle: float
) -> void:
	if _active_swing_side < 0:
		return
	var state := _state_for_side(_active_swing_side)
	if state == null or not state.available or not state.swinging:
		_active_swing_side = -1
		return
	if state.landing_swing:
		_advance_landing_swing(state, delta)
		return
	if state.gait_driven_swing and is_finite(gait_cycle):
		state.swing_progress = clampf(
			inverse_lerp(
				state.swing_start_cycle,
				state.swing_impact_cycle,
				gait_cycle
			),
			0.0,
			1.0
		)
	else:
		state.swing_progress = minf(
			state.swing_progress
			+ delta / maxf(state.swing_duration, MIN_STEP_DURATION),
			1.0
		)
	var progress := state.swing_progress
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var lift := 16.0 * progress * progress * (1.0 - progress) * (1.0 - progress)
	# Touchdown is predicted once at lift-off. Chasing a body-relative target here used to add the
	# player's full translation to the late part of the interpolation and visibly shoved the foot.
	state.current_foot_world = state.swing_start_world.lerp(
		state.swing_target_world,
		eased
	) + Vector3.UP * state.step_arc_height * lift
	state.current_normal = state.swing_start_normal.lerp(
		state.swing_target_normal,
		eased
	).normalized()
	if progress < 1.0:
		return
	var sampled := _sample_contact(state, state.swing_target_world)
	state.swing_target_world = (
		state.center_sample.position if sampled else state.swing_target_world
	)
	state.swing_target_normal = (
		state.center_sample.normal if sampled else Vector3.UP
	)
	state.current_foot_world = state.swing_target_world
	state.planted_foot_world = state.swing_target_world
	state.current_normal = state.swing_target_normal
	state.swinging = false
	state.landing_swing = false
	state.gait_driven_swing = false
	state.landing_target_valid = sampled
	state.planted = sampled
	if not sampled:
		_support_failure = true
	elif state.impact_sequence >= 0:
		_foot_contact_event_side = state.side
		_foot_contact_event_sequence = state.impact_sequence
		# The IK solution is refreshed just after scheduling; this sampled ankle is the exact contact
		# anchor rather than the old chest-height generic sound source.
		_foot_contact_event_position = state.current_foot_world
		_foot_contact_event_surface = state.center_sample.surface
	state.impact_sequence = -1
	_active_swing_side = -1


func _release_active_swing_from_gait() -> void:
	if _active_swing_side < 0:
		return
	var state := _state_for_side(_active_swing_side)
	if state == null or not state.swinging or not state.gait_driven_swing:
		return
	state.gait_driven_swing = false
	# The authority has no matching impact sequence once its gait clock is inactive. Finish the
	# already-visible foot quietly instead of freezing it in midair or inventing a late footstep.
	state.impact_sequence = -1
	state.swing_duration = maxf(
		MIN_STEP_DURATION,
		MAX_STEP_DURATION * (1.0 - state.swing_progress)
	)


func _advance_landing_swing(state: LegState, delta: float) -> void:
	state.swing_progress = minf(
		state.swing_progress
		+ maxf(delta, 0.0) / maxf(state.swing_duration, 0.001),
		1.0
	)
	var progress := state.swing_progress
	# Quintic smoothstep makes the second foot a separate, continuous touchdown with zero velocity
	# and acceleration at both ends instead of replaying the walking step arc.
	var eased := (
		progress
		* progress
		* progress
		* (progress * (progress * 6.0 - 15.0) + 10.0)
	)
	state.current_foot_world = state.swing_start_world.lerp(
		state.swing_target_world,
		eased
	)
	state.current_normal = state.swing_start_normal.lerp(
		state.swing_target_normal,
		eased
	).normalized()
	if progress < 1.0:
		return
	_plant_prepared_landing_contact(state)
	_active_swing_side = -1


func _select_step_side(
	horizontal_velocity: Vector3,
	gait_requested: bool,
	allow_translation_recovery := true
) -> int:
	var present_count := get_present_leg_count()
	if present_count <= 0:
		return -1
	if present_count == 1:
		var only_state := _left_state if _left_state.available else _right_state
		var error := _horizontal_contact_error(only_state, horizontal_velocity)
		if (
			gait_requested
			or allow_translation_recovery
			and error >= only_state.step_trigger_distance
		):
			return only_state.side
		return -1

	var left_error := _horizontal_contact_error(_left_state, horizontal_velocity)
	var right_error := _horizontal_contact_error(_right_state, horizontal_velocity)
	var errors_are_tied := absf(left_error - right_error) <= 0.005
	var emergency_side := (
		_available_side_for_preference(_next_preferred_side)
		if errors_are_tied
		else Side.LEFT if left_error > right_error else Side.RIGHT
	)
	var emergency_error := maxf(left_error, right_error)
	if allow_translation_recovery and emergency_error >= EMERGENCY_REACH_DISTANCE:
		return emergency_side
	var speed_squared := Vector2(
		horizontal_velocity.x,
		horizontal_velocity.z
	).length_squared()
	# Turning in place rotates the hips around feet that are correctly planted in world space. It
	# needs a much earlier recovery threshold than translation: waiting for normal stride reach lets
	# each foot cross the body's centreline and turns the legs into an X.
	if (
		speed_squared <= STOP_SPEED_SQUARED
		and emergency_error >= TURN_STEP_TRIGGER_DISTANCE
	):
		return emergency_side
	if gait_requested:
		return _available_side_for_preference(_next_preferred_side)
	var recovery_trigger := maxf(
		_left_state.step_trigger_distance,
		_right_state.step_trigger_distance
	)
	if (
		allow_translation_recovery
		and maxf(left_error, right_error) >= recovery_trigger
	):
		return emergency_side
	return -1


func _horizontal_contact_error(
	state: LegState,
	horizontal_velocity: Vector3
) -> float:
	if not state.available:
		return 0.0
	var desired := _desired_foot_world(state, horizontal_velocity)
	var offset := desired - state.current_foot_world
	return Vector2(offset.x, offset.z).length()


func _start_step(
	side: int,
	horizontal_velocity: Vector3,
	impact_sequence: int,
	gait_cycle: float,
	gait_driven: bool
) -> void:
	var state := _state_for_side(side)
	if state == null or not state.available:
		return
	var horizontal_speed := Vector2(
		horizontal_velocity.x,
		horizontal_velocity.z
	).length()
	_configure_step_profile(state, impact_sequence, horizontal_speed)
	var desired := _desired_foot_world(state, horizontal_velocity)
	if gait_driven and horizontal_speed > 0.001 and is_finite(gait_cycle):
		var horizontal_direction := Vector3(
			horizontal_velocity.x,
			0.0,
			horizontal_velocity.z
		) / horizontal_speed
		var current_sequence := floori(gait_cycle)
		var remaining_phase := clampf(
			float(current_sequence + 1) - gait_cycle,
			0.0,
			1.0
		)
		var touchdown_stride := PlayerGait.get_stride_distance_for_motion(
			horizontal_speed,
			PlayerGait.is_running_profile(horizontal_speed),
			_expression_identity,
			current_sequence
		)
		desired += horizontal_direction * touchdown_stride * remaining_phase
	var sampled := _sample_contact(state, desired)
	var target := state.center_sample.position if sampled else desired
	state.swing_start_world = state.current_foot_world
	state.swing_target_world = target
	state.swing_start_normal = state.current_normal
	state.swing_target_normal = (
		state.center_sample.normal if sampled else Vector3.UP
	)
	state.swing_progress = 0.0
	state.swing_duration = (
		TURN_STEP_DURATION
		if horizontal_speed * horizontal_speed <= STOP_SPEED_SQUARED
		else clampf(
			MAX_STEP_DURATION
			- horizontal_speed * STEP_DURATION_SPEED_SCALE,
			MIN_STEP_DURATION,
			MAX_STEP_DURATION
		)
	) * state.step_duration_scale
	state.swinging = true
	state.landing_swing = false
	state.gait_driven_swing = gait_driven
	state.swing_start_cycle = gait_cycle
	state.swing_impact_cycle = float(floori(gait_cycle) + 1)
	state.impact_sequence = impact_sequence if impact_sequence >= 0 else -1
	state.planted = false
	_active_swing_side = side
	_next_preferred_side = (
		Side.RIGHT if side == Side.LEFT else Side.LEFT
	)


func _configure_step_profile(
	state: LegState,
	sequence: int,
	horizontal_speed: float
) -> void:
	var profile_sequence := absi(sequence)
	state.profile_sequence = profile_sequence
	state.step_lead_seconds = PlayerGait.get_step_lead_seconds(
		_expression_identity,
		profile_sequence
	)
	state.step_max_lead_distance = PlayerGait.get_step_max_lead_distance_for_motion(
		horizontal_speed,
		_expression_identity,
		profile_sequence
	)
	state.step_forward_variation = PlayerGait.get_step_forward_variation(
		_expression_identity,
		profile_sequence
	)
	state.step_stance_scale = PlayerGait.get_step_stance_scale_for_motion(
		horizontal_speed,
		_expression_identity,
		profile_sequence
	)
	state.step_lateral_variation = PlayerGait.get_step_lateral_variation(
		_expression_identity,
		profile_sequence
	)
	state.step_arc_height = PlayerGait.get_step_arc_height_for_motion(
		horizontal_speed,
		_expression_identity,
		profile_sequence
	) * (1.0 + _momentum_recovery_weight * MOMENTUM_RECOVERY_ARC_LIFT)
	state.step_duration_scale = PlayerGait.get_step_duration_scale(
		_expression_identity,
		profile_sequence
	) * lerpf(
		1.0,
		MOMENTUM_RECOVERY_DURATION_SCALE,
		_momentum_recovery_weight
	)
	state.step_trigger_distance = PlayerGait.get_step_trigger_distance(
		_expression_identity,
		profile_sequence
	)


func _desired_foot_world(
	state: LegState,
	horizontal_velocity: Vector3
) -> Vector3:
	var result := _rest_foot_world(state)
	var horizontal := Vector3(
		horizontal_velocity.x,
		0.0,
		horizontal_velocity.z
	)
	var speed := horizontal.length()
	var recovery_offset := (
		_momentum_recovery_direction
		* MOMENTUM_RECOVERY_FOOT_LEAD
		* _momentum_recovery_weight
	)
	if speed <= 0.001:
		return result + recovery_offset
	var direction := horizontal / speed
	var lateral := global_basis.x
	return (
		result
		+ direction * (
			minf(
				speed * state.step_lead_seconds,
				state.step_max_lead_distance
			)
			+ state.step_forward_variation
		)
		+ lateral * state.step_lateral_variation
		+ recovery_offset
	)


func _rest_foot_world(state: LegState) -> Vector3:
	return global_transform * Vector3(
		(
			state.lateral_sign
			* HIP_LATERAL_OFFSET
			* state.step_stance_scale
		),
		REST_FOOT_LOCAL_HEIGHT,
		0.0
	)


func _hip_world(state: LegState) -> Vector3:
	var lateral := state.lateral_sign * HIP_LATERAL_OFFSET
	return global_transform * Vector3(
		lateral + _body_yield_lateral_shift,
		(
			HIP_LOCAL_HEIGHT
			+ _body_yield_drop
			- _landing_compression
			+ tan(_body_yield_roll) * lateral
		),
		0.0
	)


func _sample_contact(state: LegState, desired_world: Vector3) -> bool:
	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		state.center_sample.hit = false
		return false
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length_squared() <= EPSILON:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var center_hit := _sample_ray(
		space_state,
		state,
		state.center_sample,
		desired_world
	)
	var toe_hit := _sample_ray(
		space_state,
		state,
		state.toe_sample,
		desired_world + forward * FOOT_HALF_LENGTH * 0.72
	)
	var heel_hit := _sample_ray(
		space_state,
		state,
		state.heel_sample,
		desired_world - forward * FOOT_HALF_LENGTH * 0.72
	)
	if not center_hit:
		var replacement := _best_edge_sample(state, toe_hit, heel_hit)
		if replacement == null:
			return false
		var edge_offset := (
			forward * FOOT_HALF_LENGTH * 0.72
			if replacement == state.toe_sample
			else -forward * FOOT_HALF_LENGTH * 0.72
		)
		# An edge ray reports the toe/heel contact, not the ankle centre. Promoting that point directly
		# shifted an otherwise valid foot by 15 cm and produced occasional crossed or oddly floating
		# placements. Reconstruct the centre along the sampled support plane instead.
		var tangent_offset := (
			edge_offset
			- replacement.normal * edge_offset.dot(replacement.normal)
		)
		state.center_sample.hit = true
		state.center_sample.position = replacement.position - tangent_offset
		state.center_sample.normal = replacement.normal
		state.center_sample.surface = replacement.surface

	var summed_normal := state.center_sample.normal
	var normal_count := 1.0
	if (
		toe_hit
		and absf(
			state.toe_sample.position.y - state.center_sample.position.y
		) <= MAX_SOLE_SAMPLE_HEIGHT_DELTA
	):
		summed_normal += state.toe_sample.normal
		normal_count += 1.0
	if (
		heel_hit
		and absf(
			state.heel_sample.position.y - state.center_sample.position.y
		) <= MAX_SOLE_SAMPLE_HEIGHT_DELTA
	):
		summed_normal += state.heel_sample.normal
		normal_count += 1.0
	state.center_sample.normal = (summed_normal / normal_count).normalized()
	return true


func _sample_ray(
	space_state: PhysicsDirectSpaceState3D,
	state: LegState,
	sample: GroundSample,
	origin: Vector3
) -> bool:
	sample.hit = false
	state.query.from = origin + Vector3.UP * CONTACT_PROBE_UP
	state.query.to = origin + Vector3.DOWN * CONTACT_PROBE_DOWN
	state.query.exclude = _query_exclusions
	var allowed_detail_mask := (
		contact_collision_mask
		& CharacterContactLayers.FOOT_CONTACT_DETAIL
	)
	var result: Dictionary = {}
	if allowed_detail_mask != 0:
		state.query.collision_mask = allowed_detail_mask
		result = space_state.intersect_ray(state.query)
		_probe_cast_count += 1
	var allowed_movement_mask := (
		contact_collision_mask
		& CharacterContactLayers.MOVEMENT_SURFACE
	)
	if result.is_empty() and allowed_movement_mask != 0:
		state.query.collision_mask = allowed_movement_mask
		result = space_state.intersect_ray(state.query)
		_probe_cast_count += 1
	if result.is_empty():
		return false
	var normal: Vector3 = result.get("normal", Vector3.ZERO)
	if normal.y < MIN_WALKABLE_NORMAL_Y:
		return false
	sample.hit = true
	sample.position = result.get("position", origin)
	sample.normal = normal.normalized()
	sample.surface = PhysicalSurface.from_collider(result.get("collider"))
	return true


func _best_edge_sample(
	state: LegState,
	toe_hit: bool,
	heel_hit: bool
) -> GroundSample:
	if toe_hit and heel_hit:
		return (
			state.toe_sample
			if state.toe_sample.position.y >= state.heel_sample.position.y
			else state.heel_sample
		)
	if toe_hit:
		return state.toe_sample
	if heel_hit:
		return state.heel_sample
	return null


func _solve_available_legs() -> void:
	_solve_leg(_left_state)
	_solve_leg(_right_state)


func _apply_kick_override(
	sequence: int,
	requested_side: int,
	phase: float,
	world_direction: Vector3,
	intensity: float,
	authority_active: bool,
	style: int,
	grounded: bool
) -> void:
	if style == ServerPlayer.KickStyle.DROP:
		_apply_dropkick_override(
			sequence,
			phase,
			world_direction,
			intensity,
			authority_active,
			grounded
		)
		return
	var safe_phase := clampf(phase, 0.0, 1.0)
	if sequence != _presented_kick_sequence:
		_presented_kick_sequence = sequence
		_kick_active = false
		_kick_side = -1
		_kick_style = ServerPlayer.KickStyle.SINGLE
		if sequence <= 0 or safe_phase >= 1.0:
			return
		var next_state := _state_for_side(requested_side)
		if next_state == null or not next_state.available:
			return
		_kick_side = requested_side
		_kick_active = true
		_kick_style = ServerPlayer.KickStyle.SINGLE
		_kick_start_foot_local = to_local(next_state.current_foot_world)
		_kick_return_foot_local = _kick_start_foot_local
		if _active_swing_side == _kick_side:
			_active_swing_side = -1
		next_state.swinging = false
		next_state.planted = false
	if not _kick_active:
		return
	var state := _state_for_side(_kick_side)
	if state == null or not state.available:
		_kick_active = false
		_kick_side = -1
		return
	var base_foot_world := state.current_foot_world
	if safe_phase >= 1.0:
		_finish_kick_pose(state, base_foot_world, grounded)
		return
	var direction := world_direction
	if not direction.is_finite() or direction.length_squared() <= EPSILON:
		direction = -global_basis.z
	direction = direction.normalized()
	# The body visual owns the flip rotation, so every anatomical offset must use that rotating frame.
	# World UP made a chamber become a sideways/downward shove over parts of a flip, hiding the kick
	# even though the authoritative strike direction was correct.
	var body_up := global_basis.y.normalized()
	var body_right := global_basis.x.normalized()
	var body_forward := (global_basis * Vector3.FORWARD).normalized()
	var safe_intensity := clampf(intensity, 1.0, 1.72)
	var intensity_ratio := (safe_intensity - 1.0) / 0.72
	var lateral_sign := -1.0 if _kick_side == Side.LEFT else 1.0
	var start_world := global_transform * _kick_start_foot_local
	var return_world := (
		global_transform * _kick_return_foot_local
		if grounded
		else base_foot_world
	)
	var chamber_world := (
		start_world
		- direction
		* KICK_CHAMBER_BACK_DISTANCE
		* lerpf(0.92, 1.12, intensity_ratio)
		+ body_up
		* KICK_CHAMBER_LIFT
		* lerpf(0.95, 1.14, intensity_ratio)
	)
	var extension_distance := minf(
		KICK_EXTENSION_DISTANCE + intensity_ratio * 0.055,
		UPPER_LEG_LENGTH + LOWER_LEG_LENGTH - 0.018
	)
	var extension_world := (
		_hip_world(state)
		+ direction * extension_distance
		- body_up * KICK_EXTENSION_DROP
		+ body_up * (AIRBORNE_KICK_EXTENSION_LIFT if not grounded else 0.0)
		+ body_right * lateral_sign * KICK_SIDE_CLEARANCE
	)
	var strike_orientation_weight := 0.0
	if safe_phase < KICK_CHAMBER_END_PHASE:
		var chamber_ratio := smoothstep(
			0.0,
			1.0,
			safe_phase / KICK_CHAMBER_END_PHASE
		)
		state.current_foot_world = start_world.lerp(
			chamber_world,
			chamber_ratio
		)
	elif safe_phase < KICK_EXTENSION_END_PHASE:
		var extension_ratio := smoothstep(
			0.0,
			1.0,
			inverse_lerp(
				KICK_CHAMBER_END_PHASE,
				KICK_EXTENSION_END_PHASE,
				safe_phase
			)
		)
		state.current_foot_world = chamber_world.lerp(
			extension_world,
			extension_ratio
		)
		strike_orientation_weight = extension_ratio
	elif safe_phase < KICK_EXTENSION_HOLD_END_PHASE:
		# A short committed follow-through makes the strike readable and keeps the contact phase near
		# full extension without pinning the foot to any target.
		state.current_foot_world = extension_world
		strike_orientation_weight = 1.0
	else:
		var recovery_ratio := smoothstep(
			0.0,
			1.0,
			inverse_lerp(
				KICK_EXTENSION_HOLD_END_PHASE,
				1.0,
				safe_phase
			)
		)
		state.current_foot_world = extension_world.lerp(
			return_world,
			recovery_ratio
		)
		strike_orientation_weight = 1.0 - recovery_ratio
	if not grounded:
		_apply_airborne_kick_counterpose(
			state,
			safe_phase,
			body_forward,
			body_up,
			body_right
		)
	var strike_normal := -direction
	if strike_normal.length_squared() <= EPSILON:
		strike_normal = body_up
	state.current_normal = body_up.slerp(
		strike_normal.normalized(),
		KICK_FOOT_STRIKE_TILT * strike_orientation_weight
	).normalized()
	state.planted = false
	state.swinging = false


func _apply_airborne_kick_counterpose(
	acting_state: LegState,
	phase: float,
	body_forward: Vector3,
	body_up: Vector3,
	body_right: Vector3
) -> void:
	var support_side := Side.RIGHT if acting_state.side == Side.LEFT else Side.LEFT
	var support := _state_for_side(support_side)
	if support == null or not support.available:
		return
	var weight := 1.0
	if phase < KICK_CHAMBER_END_PHASE:
		weight = smoothstep(0.0, 1.0, phase / KICK_CHAMBER_END_PHASE)
	elif phase > AIRBORNE_KICK_COUNTER_RELEASE_PHASE:
		weight = 1.0 - smoothstep(
			0.0,
			1.0,
			inverse_lerp(
				AIRBORNE_KICK_COUNTER_RELEASE_PHASE,
				1.0,
				phase
			)
		)
	# The free leg folds under the pelvis and slightly behind the striking leg. It is a counterpose,
	# not a lock-on: the ordinary airborne solver remains the source pose and regains control during
	# recovery, preserving jump variation and avoiding a snap at the end of the kick.
	var counter_target := (
		_hip_world(support)
		- body_up * AIRBORNE_KICK_COUNTER_TUCK_DISTANCE
		- body_forward * AIRBORNE_KICK_COUNTER_BACK_DISTANCE
		+ body_right
		* support.lateral_sign
		* AIRBORNE_KICK_COUNTER_SIDE_CLEARANCE
	)
	support.current_foot_world = support.current_foot_world.lerp(
		counter_target,
		weight * AIRBORNE_KICK_COUNTER_MAX_WEIGHT
	)
	support.current_normal = body_up.slerp(
		-body_forward,
		0.16 * weight
	).normalized()
	support.planted = false
	support.swinging = false


func _apply_dropkick_override(
	sequence: int,
	phase: float,
	world_direction: Vector3,
	intensity: float,
	authority_active: bool,
	grounded: bool
) -> void:
	var safe_phase := clampf(phase, 0.0, 1.0)
	if sequence != _presented_kick_sequence:
		_presented_kick_sequence = sequence
		_kick_active = false
		_kick_side = -1
		_kick_style = ServerPlayer.KickStyle.DROP
		if sequence <= 0 or not _left_state.available or not _right_state.available:
			return
		_kick_active = true
		_dropkick_start_left_local = to_local(_left_state.current_foot_world)
		_dropkick_start_right_local = to_local(_right_state.current_foot_world)
		_left_state.swinging = false
		_right_state.swinging = false
		_left_state.planted = false
		_right_state.planted = false
		_active_swing_side = -1
		_configure_dropkick_variation(sequence)
	if not _kick_active or _kick_style != ServerPlayer.KickStyle.DROP:
		return
	if not authority_active:
		_finish_dropkick_pose(grounded)
		return
	var direction := world_direction
	if not direction.is_finite() or direction.length_squared() <= EPSILON:
		direction = -global_basis.z
	direction = direction.normalized()
	var right := direction.cross(Vector3.UP)
	if right.length_squared() <= EPSILON:
		right = global_basis.x
	right = right.normalized()
	var safe_intensity := clampf(intensity, 1.0, 1.72)
	var intensity_ratio := (safe_intensity - 1.0) / 0.72
	_apply_dropkick_leg(
		_left_state,
		global_transform * _dropkick_start_left_local,
		direction,
		right,
		safe_phase,
		-1.0,
		_dropkick_left_lead,
		-_dropkick_tuck_asymmetry,
		intensity_ratio
	)
	_apply_dropkick_leg(
		_right_state,
		global_transform * _dropkick_start_right_local,
		direction,
		right,
		safe_phase,
		1.0,
		_dropkick_right_lead,
		_dropkick_tuck_asymmetry,
		intensity_ratio
	)


func _configure_dropkick_variation(sequence: int) -> void:
	var key := (_expression_identity + 1) * 4099 + maxi(sequence, 0) * 7919
	_dropkick_left_lead = lerpf(
		-DROP_KICK_EXTENSION_STAGGER,
		DROP_KICK_EXTENSION_STAGGER,
		ExpressionDeterminism.ratio(key * 214013 + 2531011)
	)
	_dropkick_right_lead = lerpf(
		-DROP_KICK_EXTENSION_STAGGER,
		DROP_KICK_EXTENSION_STAGGER,
		ExpressionDeterminism.ratio(key * 1103515245 + 12345)
	)
	# Prevent the two feet from drawing the same lead value even when the hash happens to be close.
	if absf(_dropkick_left_lead - _dropkick_right_lead) < 0.018:
		_dropkick_right_lead += 0.026 if posmod(key, 2) == 0 else -0.026
	_dropkick_spread = lerpf(
		-DROP_KICK_SPREAD_VARIATION,
		DROP_KICK_SPREAD_VARIATION,
		ExpressionDeterminism.ratio(key * 1664525 + 1013904223)
	)
	_dropkick_height_bias = lerpf(
		-DROP_KICK_HEIGHT_VARIATION,
		DROP_KICK_HEIGHT_VARIATION,
		ExpressionDeterminism.ratio(key * 22695477 + 1)
	)
	_dropkick_tuck_asymmetry = lerpf(
		-0.045,
		0.045,
		ExpressionDeterminism.ratio(key * 134775813 + 1)
	)


func _apply_dropkick_leg(
	state: LegState,
	start_world: Vector3,
	direction: Vector3,
	right: Vector3,
	phase: float,
	side_sign: float,
	lead: float,
	tuck_bias: float,
	intensity_ratio: float
) -> void:
	var hip := _hip_world(state)
	var tuck_world := (
		hip
		+ direction * (DROP_KICK_TUCK_FORWARD + tuck_bias)
		+ Vector3.UP * (
			DROP_KICK_TUCK_LIFT - absf(tuck_bias) * 0.35
		)
		+ right * side_sign * (0.025 + _dropkick_spread * 0.25)
	)
	var extension_distance := minf(
		DROP_KICK_EXTENSION_DISTANCE
		+ lead
		+ intensity_ratio * 0.035,
		UPPER_LEG_LENGTH + LOWER_LEG_LENGTH - 0.014
	)
	var extension_world := (
		hip
		+ direction * extension_distance
		+ right * side_sign * (0.040 + _dropkick_spread)
		+ Vector3.UP * (
			_dropkick_height_bias * side_sign
			+ tuck_bias * 0.22
		)
	)
	var extension_weight := 0.0
	if phase < DROP_KICK_TUCK_END_PHASE:
		var tuck_ratio := smoothstep(
			0.0,
			1.0,
			phase / DROP_KICK_TUCK_END_PHASE
		)
		state.current_foot_world = start_world.lerp(tuck_world, tuck_ratio)
	else:
		extension_weight = smoothstep(
			0.0,
			1.0,
			inverse_lerp(DROP_KICK_TUCK_END_PHASE, 1.0, phase)
		)
		state.current_foot_world = tuck_world.lerp(
			extension_world,
			extension_weight
		)
	state.current_normal = Vector3.UP.slerp(
		-direction,
		lerpf(0.18, 0.66, extension_weight)
	).normalized()
	state.planted = false
	state.swinging = false


func _finish_dropkick_pose(grounded: bool) -> void:
	_finish_dropkick_leg(_left_state, grounded)
	_finish_dropkick_leg(_right_state, grounded)
	_kick_active = false
	_kick_side = -1


func _finish_dropkick_leg(state: LegState, grounded: bool) -> void:
	if not state.available:
		return
	state.swinging = false
	state.planted = false
	state.current_normal = Vector3.UP
	if grounded and _sample_contact(state, state.current_foot_world):
		state.current_foot_world = state.center_sample.position
		state.planted_foot_world = state.center_sample.position
		state.current_normal = state.center_sample.normal
		state.planted = true


func _finish_kick_pose(
	state: LegState,
	base_foot_world: Vector3,
	grounded: bool
) -> void:
	var return_world := (
		global_transform * _kick_return_foot_local
		if grounded
		else base_foot_world
	)
	state.current_foot_world = return_world
	state.current_normal = Vector3.UP
	state.swinging = false
	state.planted = false
	if grounded and _sample_contact(state, return_world):
		state.current_foot_world = state.center_sample.position
		state.planted_foot_world = state.center_sample.position
		state.current_normal = state.center_sample.normal
		state.planted = true
	_kick_active = false
	_kick_side = -1


func _solve_leg(state: LegState) -> void:
	if not state.available:
		return
	var hip := _hip_world(state)
	var bend_hint := -global_basis.z
	if bend_hint.length_squared() <= EPSILON:
		bend_hint = Vector3.FORWARD
	LimbKinematics.solve_two_bone_into(
		state.solution,
		hip,
		state.current_foot_world,
		UPPER_LEG_LENGTH,
		LOWER_LEG_LENGTH,
		bend_hint,
		state.previous_bend_world,
		Vector3.DOWN
	)
	state.previous_bend_world = state.solution.bend_direction
	var hip_local := to_local(state.solution.hip)
	var knee_local := to_local(state.solution.knee)
	var ankle_local := to_local(state.solution.tip)
	_place_segment(state.upper_visual, hip_local, knee_local)
	_place_segment(state.lower_visual, knee_local, ankle_local)
	_place_foot(state, ankle_local)


func _place_segment(
	visual: MeshInstance3D,
	start_local: Vector3,
	end_local: Vector3
) -> void:
	var offset := end_local - start_local
	var length := maxf(offset.length(), 0.001)
	var orientation := LimbKinematics.basis_from_y(offset)
	visual.transform = Transform3D(
		orientation * Basis.from_scale(Vector3(1.0, length, 1.0)),
		(start_local + end_local) * 0.5
	)


func _place_foot(state: LegState, ankle_local: Vector3) -> void:
	var local_normal := global_basis.inverse() * state.current_normal
	if local_normal.length_squared() <= EPSILON:
		local_normal = Vector3.UP
	else:
		local_normal = local_normal.normalized()
	var local_forward := Vector3.FORWARD
	local_forward = (
		local_forward
		- local_normal * local_forward.dot(local_normal)
	)
	if local_forward.length_squared() <= EPSILON:
		local_forward = Vector3.RIGHT.cross(local_normal)
	local_forward = local_forward.normalized()
	var local_z := -local_forward
	var local_x := local_normal.cross(local_z).normalized()
	var foot_basis := Basis(local_x, local_normal, local_z).orthonormalized()
	state.foot_visual.transform = Transform3D(
		foot_basis,
		ankle_local
		+ local_normal * FOOT_HALF_HEIGHT
		+ local_forward * FOOT_CENTER_FORWARD_OFFSET
	)


func _available_side_for_preference(preferred: int) -> int:
	var preferred_state := _state_for_side(preferred)
	if preferred_state != null and preferred_state.available:
		return preferred
	return Side.RIGHT if preferred == Side.LEFT else Side.LEFT


func _state_for_side(side: int) -> LegState:
	if side == Side.LEFT:
		return _left_state
	if side == Side.RIGHT:
		return _right_state
	return null
