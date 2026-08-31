extends Node3D
class_name PlayerProxy

const INTERP_SPEED := 12.0
const MAX_EXTRAPOLATION_TIME := 0.25

const HEADBOB_BLEND_SPEED := 8.0
const HEADBOB_RUN_BLEND_SPEED := 5.0
const HEADBOB_PHASE_SYNC_SPEED := 10.0
const HEADBOB_PHASE_SNAP_CYCLES := 0.75
const EDIT_AIM_MARKER_COLOR := Color(0.16, 0.86, 0.7, 0.2)
const MAX_LOOK_PITCH_DEGREES := 85.0
# The authored head camera sits inside the one-body character mesh. A full downward hemisphere would
# expose the open underside of that mesh, so ordinary first-person look stops before the neck enters
# frame. Fieldlink has a separate lower bound aligned with the physical arm solver, so its RMB clutch
# cannot fold the real forearm and terminal underneath the camera.
const MIN_WORLD_LOOK_PITCH := deg_to_rad(-58.0)
const MAX_LOOK_PITCH := deg_to_rad(MAX_LOOK_PITCH_DEGREES)
const HELD_ITEM_SIDE_OFFSET := 0.43
const HELD_ITEM_ROLL := 0.08
const FIRST_PERSON_ITEM_SIDE_OFFSET := 0.22
const EQUIPPED_WRIST_DEVICE_SCALE := 0.45
const WRIST_LOOK_PITCH := deg_to_rad(-24.0)
const FIELDLINK_POSE_MIN_PITCH := deg_to_rad(-52.0)
const FIELDLINK_POSE_MAX_PITCH := deg_to_rad(-12.0)
# Raising the player's head must not make the arms chase the camera all the way upward. The device
# stays biased toward its useful downward operating pose; upward head motion contributes only this
# small comfort arc before the player simply looks away from the screen.
const FIELDLINK_UPWARD_FOCUS_PITCH := deg_to_rad(-20.0)
const MIN_WRIST_LOOK_PITCH := FIELDLINK_POSE_MIN_PITCH
const FIELDLINK_POSE_PITCH_RESPONSE_HZ := 7.5
const BODY_IMPACT_REPLAY_WINDOW_SECONDS := 0.75
const FLIP_FLICK_JUMP_GRACE_TICKS := 2
const FLIP_FLICK_SAMPLE_WINDOW_SECONDS := 0.10
const FLIP_FLICK_MIN_PITCH_DELTA := deg_to_rad(8.0)
const FLIP_FLICK_MIN_ANGULAR_SPEED := deg_to_rad(420.0)
# Dropkicks are already explicit actions, so their steering gesture can be slower and broader than
# the anti-accidental flip flick. A short yaw history chooses the body's roll hemisphere at commit;
# it never keeps dragging the pose after the player has kicked.
const DROP_KICK_TILT_SAMPLE_WINDOW_SECONDS := 0.16
const DROP_KICK_TILT_MIN_YAW_DELTA := deg_to_rad(2.5)
const DROP_KICK_TILT_FULL_YAW_DELTA := deg_to_rad(16.0)
const FLIP_VISUAL_RESPONSE_HZ := 16.0
const FLIP_REQUEST_TIMEOUT_SECONDS := 0.75
const FIELDLINK_HOLD_POSITION_SCALE := 1.25
const FIELDLINK_HOLD_ROTATION_SCALE := 1.35
const WRIST_POSE_BLEND_SPEED := 7.5
const WRIST_LOOK_RECENTER_SPEED := 8.0
const WRIST_REQUEST_GRACE_SECONDS := 0.5
const WRIST_SCANNER_RANGE_METERS := 36.0
const WRIST_SCANNER_REFRESH_SECONDS := 0.2
const WRIST_CONTROL_REFRESH_SECONDS := 0.5
const MOUSE_CAPTURE_TRANSITION_DISCARD_EVENTS := 2
const LEFT_ARM_REST_POSITION := Vector3(-0.47, 0.16, 0.0)
const RIGHT_ARM_REST_POSITION := Vector3(0.47, 0.16, 0.0)
const LEFT_SHOULDER_POSITION := Vector3(-0.47, 0.57, 0.0)
const RIGHT_SHOULDER_POSITION := Vector3(0.47, 0.57, 0.0)
const SOCIAL_GAZE_RANGE_METERS := 9.0
const SOCIAL_GAZE_EPOCH_SECONDS := 2.6
const SOCIAL_GAZE_ENGAGEMENT_CHANCE := 0.76
const FIELDLINK_POSE: CharacterPoseDefinition = preload(
	"res://resources/character_poses/fieldlink_terminal.tres"
)
const WRIST_PRESENTATION_SCENE := preload(
	"res://scenes/proxy/wrist_terminal_presentation.tscn"
)
const TRIP_CAMERA_BLEND_SPEED := 7.5
const TRIP_CAMERA_ORIENTATION_SPEED := 9.0
const TRIP_CAMERA_MAX_ROLL := deg_to_rad(62.0)
const TRIP_CAMERA_MAX_PITCH_INFLUENCE := deg_to_rad(24.0)
const REMOTE_WRIST_DISPLAY := preload(
	"res://scripts/client/wrist_terminal_remote_display.gd"
)
const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)
const LOCAL_AUDIO_PREDICTION := preload(
	"res://scripts/audio/local_audio_prediction.gd"
)
const HELD_DEVICE_MOTION := preload(
	"res://scripts/characters/first_person_held_device_motion.gd"
)
const PLASMA_CUTTER_BEAM_SCRIPT := preload(
	"res://scripts/client/plasma_cutter_beam_3d.gd"
)

#######################################################
# Presents replicated player movement, body parts, equipment, held items, HUD, camera motion,
# and ocular effects.
#######################################################

@onready var camera_pivot: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
@onready var audio_listener: AudioListener3D = $AudioListener3D
@onready var body_visual: Node3D = $BodyVisual
@onready var character_skin: PlayerCharacterSkin = $BodyVisual/CharacterSkin
@onready var upper_body_pose: Node3D = $BodyVisual/UpperBodyPose
@onready var torso_visual: MeshInstance3D = $BodyVisual/UpperBodyPose/Torso
@onready var head_visual: MeshInstance3D = $BodyVisual/UpperBodyPose/Head
@onready var left_arm_visual: MeshInstance3D = $BodyVisual/UpperBodyPose/LeftArm
@onready var right_arm_visual: MeshInstance3D = $BodyVisual/UpperBodyPose/RightArm
@onready var left_wrist_mount: Node3D = $BodyVisual/UpperBodyPose/LeftArm/WristMount
@onready var right_wrist_mount: Node3D = $BodyVisual/UpperBodyPose/RightArm/WristMount
@onready var procedural_leg_rig: PlayerProceduralLegRig = (
	$BodyVisual/ProceduralLegRig
)
@onready var left_leg_visual: Node3D = (
	$BodyVisual/ProceduralLegRig/LeftLeg
)
@onready var right_leg_visual: Node3D = (
	$BodyVisual/ProceduralLegRig/RightLeg
)
@onready var player_ragdoll = $PlayerRagdoll
@onready var edit_aim_hit: MeshInstance3D = $EditAimHit
@onready var backpack_mount: Node3D = $BodyVisual/UpperBodyPose/BackpackMount
@onready var eyes_mount: Node3D = $BodyVisual/UpperBodyPose/Head/EyesMount
@onready var held_item_mount: Node3D = $BodyVisual/UpperBodyPose/HeldItemMount
@onready var first_person_item_mount: Node3D = (
	$HeadPivot/Camera3D/FirstPersonItemMount
)
@onready var interface_layer: CanvasLayer = $PlayerInterface
@onready var inventory_hud: PlayerInventoryHud = (
	$PlayerInterface/PlayerHud
)
@onready var vision_layer: CanvasLayer = $OcularPostProcess
@onready var vision_effect: OcularVisionController = (
	$OcularPostProcess/VisionEffect
)
@onready var acoustic_perception: EyelessAcousticPerception = (
	$AcousticPerception/Sense
)

var headbob_weight := 0.0
var headbob_run_weight := 0.0
var camera_pivot_rest_position: Vector3
var audio_listener_rest_position: Vector3
var target_gait_cycle := 0.5
var visual_gait_cycle := 0.5
var target_gait_stride_distance := PlayerGait.WALK_STEP_DISTANCE
var target_gait_active := false
var target_gait_momentum_recovery := 0.0
var resolved_gait_momentum_recovery := 0.0
var gait_initialized := false
var last_predicted_gait_step_sequence := -1
var target_footstep_surface: StringName = PhysicalSurface.CONCRETE
var local_move_input := Vector2.ZERO
var local_run_input := false
var local_predicted_horizontal_speed := 0.0
var local_predicted_horizontal_velocity := Vector2.ZERO
var local_locomotion_prediction_initialized := false
var local_sprint_speed_ramp_elapsed := 0.0
var local_recovery_gait := PlayerGait.new()
var target_stamina_ratio := 1.0
var target_sprint_exhausted := false
var target_expression_clock := 0.0
var resolved_pose_gait_cycle := 0.5
var character_pose := PlayerCharacterPoseController.new()
var ocular_expression := PlayerOcularExpressionController.new()
var _expression_identity_player_id := -1
var ocular_social_target_player_id := -1
var ocular_social_epoch := -1
var target_faction_id := 0

var target_on_floor := false
var target_jump_sequence := 0
var target_flip_sequence := 0
var target_flip_direction := 0
var target_flip_active := false
var target_flip_phase := 0.0
var target_kick_sequence := 0
var target_kick_side := -1
var target_kick_style := ServerPlayer.KickStyle.SINGLE
var target_kick_active := false
var target_kick_phase := 1.0
var target_kick_clock := -1.0
var target_kick_direction := Vector3.FORWARD
var target_kick_view_yaw := 0.0
var target_kick_view_pitch := 0.0
var target_kick_flip_direction := 0
var target_dropkick_tilt_input := 0.0
var target_kick_guidance_direction := Vector3.FORWARD
var target_kick_guidance_weight := 0.0
var target_kick_intensity := 1.0
var presented_flip_sequence := -1
var visual_flip_direction := 0
var visual_flip_phase := 0.0
var visual_flip_angle := 0.0
var buffered_flip_intent := 0
var local_flip_input_tick := 0
var buffered_flip_expiry_tick := -1
var flip_flick_accumulated_pitch := 0.0
var flip_flick_accumulated_elapsed := 0.0
var flip_flick_sample_remaining := 0.0
var dropkick_tilt_accumulated_yaw := 0.0
var dropkick_tilt_accumulated_elapsed := 0.0
var dropkick_tilt_sample_remaining := 0.0
var local_flip_prediction_active := false
var local_flip_prediction_elapsed := 0.0
var local_flip_prediction_base_sequence := 0
var local_flip_prediction_base_jump_sequence := 0
var local_flip_prediction_request_id := 0
var local_flip_request_elapsed := 0.0
var completed_visual_flip_sequence := -1
var target_landing_sequence := 0
var target_landing_impact_strength := 0.0
var target_body_impact_sequence := 0
var target_body_impact_strength := 0.0
var target_body_impact_direction := Vector3.ZERO
var target_body_impact_contact_side := 0.0
var target_body_impact_clock := -1.0
var presented_body_impact_sequence := -1
var target_ragdoll_active := false
var target_trip_sequence := 0
var target_trip_direction := Vector3.FORWARD
var presented_trip_sequence := -1
var trip_camera_weight := 0.0
var ragdoll_camera_world_position := Vector3.ZERO
var ragdoll_camera_roll := 0.0
var ragdoll_camera_pitch := 0.0

var mouse_sensitivity := 0.002
var look_yaw := 0.0
var look_pitch := 0.0
var grab_rotation_input := Vector2.ZERO
var player_id: int = -1

var is_local_player := false

var target_position: Vector3
var target_rotation: Vector3
var target_look_pitch := 0.0
var target_velocity: Vector3
var time_since_last_state := 0.0
var target_edit_aim_active := false
var target_edit_aim_origin := Vector3.ZERO
var target_edit_aim_hit := Vector3.ZERO
var target_edit_aim_color := Color(0.2, 0.8, 1.0, 1.0)
var target_player_state: Dictionary = {}
var _last_inventory_revision := -1
var _cached_public_inventory: Dictionary = {
	"capacity": PlayerInventoryRules.BASE_CAPACITY,
	"selected_slot": 0,
	"entries": [],
	"equipment": {},
}
var equipment_visuals: Dictionary = {}
var equipment_definition_paths: Dictionary = {}
var held_item_visual: Node3D
var held_item_definition_path := ""
var held_item_state: Dictionary = {}
var held_item_signature := ""
var has_left_arm := true
var has_right_arm := true
var has_left_leg := true
var has_right_leg := true
var target_wrist_interface_open := false
var target_wrist_display_page: StringName = FIELDLINK_DISPLAY_STATE.PAGE_HOME
var local_wrist_interface_open := false
var wrist_pose_weight := 0.0
var fieldlink_pose_pitch := WRIST_LOOK_PITCH
var fieldlink_hold_motion := HELD_DEVICE_MOTION.new()
var fieldlink_hold_motion_active := false
var wrist_presentation: WristTerminalPresentation
var remote_wrist_display: Node
var wrist_session_refresh_remaining := 0.0
var wrist_scanner_refresh_remaining := 0.0
var wrist_control_refresh_remaining := 0.0
var wrist_request_grace_remaining := 0.0
var wrist_mouse_look_active := false
var wrist_mouse_look_owns_pitch := false
var wrist_mouse_look_blend := 0.0
var captured_mouse_motion_discard_remaining := 0
var target_plasma_cutter_available := false
var target_plasma_cutter_heat_ratio := 0.0
var target_plasma_cutter_overheated := false
var target_plasma_cutter_active := false
var target_plasma_cutter_has_hit := false
var target_plasma_cutter_hit_position := Vector3.ZERO
var target_plasma_cutter_range_meters := 0.0
var target_plasma_cutter_kerf_millimeters := 0.0
var target_plasma_cutter_cut_depth_millimeters := 0.0
var target_plasma_cutter_continuous_duty_seconds := 0.0
var target_plasma_cutter_full_cool_seconds := 0.0
var local_plasma_cutter_trigger_held := false
var plasma_cutter_beam: Node3D
var plasma_cutter_emitter: Node3D
var local_has_equipped_eyes := true

func _ready() -> void:
	target_position = global_position
	target_rotation = global_rotation

	camera_pivot_rest_position = camera_pivot.position
	audio_listener_rest_position = audio_listener.position
	_apply_expression_identity(player_id, true)
	_sync_character_appearance()
	edit_aim_hit.material_override = _create_edit_aim_material()
	edit_aim_hit.visible = false
	_ensure_plasma_cutter_beam()
	acoustic_perception.bind_camera(camera)
	var client := get_node_or_null("/root/Client")
	if client != null:
		client.acoustic_perception_event_rendered.connect(
			_on_acoustic_perception_event_rendered
		)
		client.acoustic_perception_continuous_sample.connect(
			_on_acoustic_perception_continuous_sample
		)

	set_local_player(is_local_player)


func _apply_expression_identity(next_player_id: int, force := false) -> void:
	if not force and next_player_id == _expression_identity_player_id:
		return
	_expression_identity_player_id = next_player_id
	if procedural_leg_rig != null:
		procedural_leg_rig.set_expression_identity(next_player_id)
	character_pose.set_expression_identity(next_player_id)
	ocular_expression.set_expression_identity(next_player_id)
	local_recovery_gait.set_expression_identity(next_player_id)
	if character_skin != null:
		character_skin.set_player_identity(next_player_id)
		_sync_character_appearance()


func _input(event: InputEvent) -> void:
	if not is_local_player:
		return

	if event.is_action_pressed("toggle_fieldlink"):
		toggle_wrist_interface()
		grab_rotation_input = Vector2.ZERO
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if local_wrist_interface_open:
			close_wrist_interface()
			get_viewport().set_input_as_handled()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		grab_rotation_input = Vector2.ZERO
		return

	if local_wrist_interface_open:
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_RIGHT
		):
			_set_wrist_mouse_look_active(event.pressed)
			get_viewport().set_input_as_handled()
			return
		if wrist_mouse_look_active:
			if event is InputEventMouseMotion:
				if not _consume_capture_transition_motion():
					_apply_mouse_look(
						event.relative,
						event.screen_relative
					)
			get_viewport().set_input_as_handled()
			return
		if wrist_presentation != null:
			wrist_presentation.forward_pointer_input(event)
		get_viewport().set_input_as_handled()
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			_arm_capture_transition_guard()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return

	if event is InputEventMouseMotion:
		if _consume_capture_transition_motion():
			get_viewport().set_input_as_handled()
			return
		if (
			Input.is_action_pressed("grab")
			and Input.is_action_pressed("rotate_grabbed")
		):
			grab_rotation_input += event.relative
			return

		_apply_mouse_look(event.relative, event.screen_relative)


func _apply_mouse_look(
	relative_motion: Vector2,
	_screen_relative_motion := Vector2.ZERO,
	sample_delta := -1.0
) -> void:
	var previous_yaw := look_yaw
	var previous_pitch := look_pitch
	look_yaw -= relative_motion.x * mouse_sensitivity
	look_pitch = clampf(
		look_pitch - relative_motion.y * mouse_sensitivity,
		MIN_WRIST_LOOK_PITCH if local_wrist_interface_open else MIN_WORLD_LOOK_PITCH,
		MAX_LOOK_PITCH
	)
	var resolved_sample_delta := sample_delta
	if resolved_sample_delta <= 0.0:
		resolved_sample_delta = get_process_delta_time()
	# Gesture recognition consumes the exact post-clamp angle that presentation received. Raw mouse
	# pixels can differ across content scale and still move while pitch is clamped; neither is a real
	# camera flick and therefore neither may arm a flip.
	_record_flip_pitch_motion(
		look_pitch - previous_pitch,
		resolved_sample_delta
	)
	_record_dropkick_tilt_motion(
		angle_difference(previous_yaw, look_yaw),
		resolved_sample_delta
	)


static func dropkick_tilt_input_from_yaw_motion(yaw_delta: float) -> float:
	if not is_finite(yaw_delta):
		return 0.0
	# Camera yaw decreases for a rightward mouse sweep. Presentation uses positive input for that
	# familiar right-curve / clockwise body roll, so invert the signed camera delta here once.
	var screen_lateral_motion := -yaw_delta
	var magnitude := absf(screen_lateral_motion)
	if magnitude < DROP_KICK_TILT_MIN_YAW_DELTA:
		return 0.0
	var weight := smoothstep(
		0.0,
		1.0,
		clampf(
			inverse_lerp(
				DROP_KICK_TILT_MIN_YAW_DELTA,
				DROP_KICK_TILT_FULL_YAW_DELTA,
				magnitude
			),
			0.0,
			1.0
		)
	)
	return signf(screen_lateral_motion) * weight


func _record_dropkick_tilt_motion(
	yaw_delta: float,
	sample_delta: float
) -> void:
	if local_wrist_interface_open or not is_finite(yaw_delta):
		_clear_dropkick_tilt_gesture()
		return
	if absf(yaw_delta) <= 0.000001:
		return
	var safe_delta := clampf(sample_delta, 1.0 / 240.0, 0.05)
	var changed_direction := (
		dropkick_tilt_accumulated_yaw * yaw_delta < 0.0
	)
	var sample_window_exhausted := (
		dropkick_tilt_accumulated_elapsed + safe_delta
		> DROP_KICK_TILT_SAMPLE_WINDOW_SECONDS
	)
	if (
		dropkick_tilt_sample_remaining <= 0.0
		or changed_direction
		or sample_window_exhausted
	):
		dropkick_tilt_accumulated_yaw = yaw_delta
		dropkick_tilt_accumulated_elapsed = safe_delta
	else:
		dropkick_tilt_accumulated_yaw += yaw_delta
		dropkick_tilt_accumulated_elapsed += safe_delta
	dropkick_tilt_sample_remaining = DROP_KICK_TILT_SAMPLE_WINDOW_SECONDS


func consume_dropkick_tilt_input() -> float:
	var result := dropkick_tilt_input_from_yaw_motion(
		dropkick_tilt_accumulated_yaw
	)
	_clear_dropkick_tilt_gesture()
	return result


func _clear_dropkick_tilt_gesture() -> void:
	dropkick_tilt_accumulated_yaw = 0.0
	dropkick_tilt_accumulated_elapsed = 0.0
	dropkick_tilt_sample_remaining = 0.0


static func flip_intent_from_pitch_motion(
	pitch_delta: float,
	sample_delta: float
) -> int:
	var safe_delta := clampf(sample_delta, 1.0 / 240.0, 0.05)
	if (
		not is_finite(pitch_delta)
		or absf(pitch_delta) < FLIP_FLICK_MIN_PITCH_DELTA
		or absf(pitch_delta) / safe_delta < FLIP_FLICK_MIN_ANGULAR_SPEED
	):
		return 0
	return 1 if pitch_delta > 0.0 else -1


func _record_flip_pitch_motion(
	pitch_delta: float,
	sample_delta: float
) -> void:
	if local_wrist_interface_open:
		_clear_flip_gesture()
		return
	var safe_delta := clampf(sample_delta, 1.0 / 240.0, 0.05)
	if buffered_flip_intent != 0:
		var instantaneous_direction := 0
		if pitch_delta > 0.0:
			instantaneous_direction = 1
		elif pitch_delta < 0.0:
			instantaneous_direction = -1
		var continues_flick := (
			instantaneous_direction == buffered_flip_intent
			and absf(pitch_delta) / safe_delta
			>= FLIP_FLICK_MIN_ANGULAR_SPEED
		)
		if continues_flick:
			buffered_flip_expiry_tick = (
				local_flip_input_tick + FLIP_FLICK_JUMP_GRACE_TICKS
			)
		elif instantaneous_direction == -buffered_flip_intent:
			buffered_flip_intent = 0
			buffered_flip_expiry_tick = -1
	var changed_direction := (
		flip_flick_accumulated_pitch * pitch_delta < 0.0
	)
	var sample_window_exhausted := (
		flip_flick_accumulated_elapsed + safe_delta
		> FLIP_FLICK_SAMPLE_WINDOW_SECONDS
	)
	if (
		flip_flick_sample_remaining <= 0.0
		or changed_direction
		or sample_window_exhausted
	):
		flip_flick_accumulated_pitch = pitch_delta
		flip_flick_accumulated_elapsed = safe_delta
	else:
		flip_flick_accumulated_pitch += pitch_delta
		flip_flick_accumulated_elapsed += safe_delta
	flip_flick_sample_remaining = FLIP_FLICK_SAMPLE_WINDOW_SECONDS
	var intent := flip_intent_from_pitch_motion(
		flip_flick_accumulated_pitch,
		flip_flick_accumulated_elapsed
	)
	if intent == 0:
		return
	buffered_flip_intent = intent
	# Mouse events and jump actions meet on the fixed input tick. The gesture remains valid for the
	# next two such ticks regardless of render rate; a 30 Hz and 240 Hz client therefore get the same
	# maneuver window.
	buffered_flip_expiry_tick = (
		local_flip_input_tick + FLIP_FLICK_JUMP_GRACE_TICKS
	)
	flip_flick_accumulated_pitch = 0.0
	flip_flick_accumulated_elapsed = 0.0
	flip_flick_sample_remaining = 0.0


func consume_buffered_flip_intent() -> int:
	if (
		local_wrist_interface_open
		or buffered_flip_intent == 0
		or local_flip_input_tick > buffered_flip_expiry_tick
		or not has_local_flip_run_commitment()
	):
		_clear_flip_gesture()
		return 0
	var result := buffered_flip_intent
	buffered_flip_intent = 0
	buffered_flip_expiry_tick = -1
	return result


func _clear_flip_gesture() -> void:
	buffered_flip_intent = 0
	buffered_flip_expiry_tick = -1
	flip_flick_accumulated_pitch = 0.0
	flip_flick_accumulated_elapsed = 0.0
	flip_flick_sample_remaining = 0.0


func advance_local_input_tick() -> void:
	local_flip_input_tick += 1
	if (
		buffered_flip_intent != 0
		and local_flip_input_tick > buffered_flip_expiry_tick
	):
		_clear_flip_gesture()


func has_local_flip_run_commitment() -> bool:
	return (
		is_local_player
		and local_run_input
		and local_move_input.length_squared()
		> ServerPlayer.MOVEMENT_INPUT_THRESHOLD_SQUARED
		and target_on_floor
		and not target_ragdoll_active
		and not local_wrist_interface_open
		and not target_wrist_interface_open
		and target_stamina_ratio
		> ServerPlayer.STAMINA_EMPTY_THRESHOLD / ServerPlayer.MAX_STAMINA
		and not target_sprint_exhausted
	)


func predict_local_flip_takeoff(intent: int, request_id := 0) -> bool:
	var direction := clampi(intent, -1, 1)
	var predicted_velocity := (
		local_predicted_horizontal_velocity
		if local_locomotion_prediction_initialized
		else Vector2(target_velocity.x, target_velocity.z)
	)
	if (
		direction == 0
		or not has_local_flip_run_commitment()
		or predicted_velocity.length() < ServerPlayer.FLIP_MIN_HORIZONTAL_SPEED
	):
		return false
	local_flip_prediction_active = true
	local_flip_prediction_elapsed = 0.0
	local_flip_prediction_base_sequence = target_flip_sequence
	local_flip_prediction_base_jump_sequence = target_jump_sequence
	local_flip_prediction_request_id = maxi(request_id, 0)
	local_flip_request_elapsed = 0.0
	visual_flip_direction = direction
	visual_flip_phase = 0.0
	visual_flip_angle = 0.0
	return true


func resolve_local_jump_request(
	request_id: int,
	jump_accepted: bool,
	accepted_flip_direction: int
) -> void:
	if (
		request_id <= 0
		or request_id != local_flip_prediction_request_id
	):
		return
	var direction := clampi(accepted_flip_direction, -1, 1)
	var authority_already_presented := (
		target_flip_sequence > local_flip_prediction_base_sequence
	)
	local_flip_prediction_request_id = 0
	local_flip_request_elapsed = 0.0
	if not jump_accepted or direction == 0:
		local_flip_prediction_active = false
		# Rejection is not a new animation. Reset the provisional sub-frame pose instead of easing it
		# into a visible counter-rotation.
		if not authority_already_presented:
			visual_flip_direction = 0
			visual_flip_phase = 0.0
			visual_flip_angle = 0.0
			_apply_body_visual_rotation()
		return
	if authority_already_presented:
		local_flip_prediction_active = false
		return
	if not local_flip_prediction_active:
		local_flip_prediction_active = true
		local_flip_prediction_elapsed = 0.0
		visual_flip_phase = 0.0
		visual_flip_angle = 0.0
	visual_flip_direction = direction


func _consume_capture_transition_motion() -> bool:
	if captured_mouse_motion_discard_remaining <= 0:
		return false
	captured_mouse_motion_discard_remaining -= 1
	return true


func _arm_capture_transition_guard() -> void:
	_clear_flip_gesture()
	captured_mouse_motion_discard_remaining = (
		MOUSE_CAPTURE_TRANSITION_DISCARD_EVENTS
	)


func _set_wrist_mouse_look_active(value: bool) -> void:
	var next_value := value and local_wrist_interface_open
	if next_value == wrist_mouse_look_active:
		return
	wrist_mouse_look_active = next_value
	if wrist_mouse_look_active:
		# Do not seed free-look from CameraPivot.rotation: that transform also contains head motion,
		# impacts, and other presentation offsets. Inheriting it made RMB convert a visual offset into
		# persistent upward camera pitch. Enter from the safe operating view, while preserving a view
		# that the player had deliberately moved farther downward.
		look_pitch = clampf(
			minf(_resolved_camera_pitch(), WRIST_LOOK_PITCH),
			MIN_WRIST_LOOK_PITCH,
			WRIST_LOOK_PITCH
		)
		wrist_mouse_look_owns_pitch = true
		wrist_mouse_look_blend = 1.0
		return


func consume_grab_rotation_input() -> Vector2:
	var result := grab_rotation_input
	grab_rotation_input = Vector2.ZERO
	return result

func apply_server_state(state: Dictionary) -> void:
	player_id = SafeVariant.integral_int_or(state.get("player_id", -1), -1)
	_apply_expression_identity(player_id)
	target_faction_id = SafeVariant.integral_int_or(
		state.get("faction_id", target_faction_id),
		target_faction_id
	)
	var current_position := global_position if is_inside_tree() else position
	var current_rotation := global_rotation if is_inside_tree() else rotation

	target_position = SafeVariant.vector3_strict_or(
		state.get("pos", current_position), current_position
	)
	target_rotation = SafeVariant.vector3_strict_or(
		state.get("rot", current_rotation), current_rotation
	)
	target_look_pitch = clampf(
		SafeVariant.finite_float_or(
			state.get("look_pitch"),
			target_look_pitch
		),
		deg_to_rad(-MAX_LOOK_PITCH_DEGREES),
		deg_to_rad(MAX_LOOK_PITCH_DEGREES)
	)
	target_velocity = SafeVariant.vector3_strict_or(
		state.get("vel", Vector3.ZERO), Vector3.ZERO
	)
	time_since_last_state = 0.0
	
	target_on_floor = SafeVariant.strict_bool_or(state.get("on_floor", false), false)
	target_jump_sequence = maxi(
		SafeVariant.integral_int_or(
			state.get("jump_sequence", target_jump_sequence),
			target_jump_sequence
		),
		0
	)
	target_flip_sequence = maxi(
		SafeVariant.integral_int_or(
			state.get("flip_sequence", target_flip_sequence),
			target_flip_sequence
		),
		0
	)
	target_flip_direction = clampi(
		SafeVariant.integral_int_or(
			state.get("flip_direction", target_flip_direction),
			target_flip_direction
		),
		-1,
		1
	)
	target_flip_active = SafeVariant.strict_bool_or(
		state.get("flip_active", target_flip_active),
		target_flip_active
	)
	target_flip_phase = clampf(
		SafeVariant.finite_float_or(
			state.get("flip_phase"),
			target_flip_phase
		),
		0.0,
		1.0
	)
	target_kick_sequence = maxi(
		SafeVariant.integral_int_or(
			state.get("kick_sequence", target_kick_sequence),
			target_kick_sequence
		),
		0
	)
	target_kick_side = clampi(
		SafeVariant.integral_int_or(
			state.get("kick_side", target_kick_side),
			target_kick_side
		),
		-1,
		1
	)
	target_kick_style = clampi(
		SafeVariant.integral_int_or(
			state.get("kick_style", target_kick_style),
			target_kick_style
		),
		ServerPlayer.KickStyle.SINGLE,
		ServerPlayer.KickStyle.DROP
	)
	target_kick_active = SafeVariant.strict_bool_or(
		state.get("kick_active", target_kick_active),
		target_kick_active
	)
	target_kick_phase = clampf(
		SafeVariant.finite_float_or(
			state.get("kick_phase"),
			target_kick_phase
		),
		0.0,
		1.0
	)
	target_kick_clock = SafeVariant.finite_float_or(
		state.get("kick_clock"),
		target_kick_clock
	)
	target_kick_direction = SafeVariant.vector3_strict_or(
		state.get("kick_direction", target_kick_direction),
		target_kick_direction
	)
	target_kick_view_yaw = SafeVariant.finite_float_or(
		state.get("kick_view_yaw"),
		target_kick_view_yaw
	)
	target_kick_view_pitch = SafeVariant.finite_float_or(
		state.get("kick_view_pitch"),
		target_kick_view_pitch
	)
	target_kick_flip_direction = clampi(
		SafeVariant.integral_int_or(
			state.get("kick_flip_direction", target_kick_flip_direction),
			target_kick_flip_direction
		),
		-1,
		1
	)
	target_dropkick_tilt_input = clampf(
		SafeVariant.finite_float_or(
			state.get("dropkick_tilt_input"),
			target_dropkick_tilt_input
		),
		-1.0,
		1.0
	)
	target_kick_guidance_direction = SafeVariant.vector3_strict_or(
		state.get(
			"kick_guidance_direction",
			target_kick_guidance_direction
		),
		target_kick_guidance_direction
	)
	target_kick_guidance_weight = clampf(
		SafeVariant.finite_float_or(
			state.get("kick_guidance_weight"),
			target_kick_guidance_weight
		),
		0.0,
		ServerPlayer.KICK_GUIDANCE_MAX_WEIGHT
	)
	target_kick_intensity = clampf(
		SafeVariant.finite_float_or(
			state.get("kick_intensity"),
			target_kick_intensity
		),
		1.0,
		1.72
	)
	target_ragdoll_active = SafeVariant.strict_bool_or(
		state.get("ragdoll_active", false),
		false
	)
	target_expression_clock = maxf(
		SafeVariant.finite_float_or(
			state.get("expression_clock"),
			target_expression_clock
		),
		0.0
	)
	target_trip_sequence = maxi(
		SafeVariant.integral_int_or(
			state.get("trip_sequence", target_trip_sequence),
			target_trip_sequence
		),
		0
	)
	target_trip_direction = SafeVariant.vector3_strict_or(
		state.get("trip_direction", target_trip_direction),
		target_trip_direction
	)
	target_landing_sequence = maxi(
		SafeVariant.integral_int_or(
			state.get("landing_sequence", target_landing_sequence),
			target_landing_sequence
		),
		0
	)
	target_landing_impact_strength = clampf(
		SafeVariant.finite_float_or(
			state.get(
				"landing_impact_strength",
				target_landing_impact_strength
			),
			target_landing_impact_strength
		),
		0.0,
		1.0
	)
	target_body_impact_sequence = maxi(
		SafeVariant.integral_int_or(
			state.get("body_impact_sequence", target_body_impact_sequence),
			target_body_impact_sequence
		),
		0
	)
	target_body_impact_strength = clampf(
		SafeVariant.finite_float_or(
			state.get("body_impact_strength"),
			target_body_impact_strength
		),
		0.0,
		1.0
	)
	target_body_impact_direction = SafeVariant.vector3_strict_or(
		state.get("body_impact_direction", target_body_impact_direction),
		target_body_impact_direction
	)
	target_body_impact_contact_side = clampf(
		SafeVariant.finite_float_or(
			state.get("body_impact_contact_side"),
			target_body_impact_contact_side
		),
		-1.0,
		1.0
	)
	target_body_impact_clock = SafeVariant.finite_float_or(
		state.get("body_impact_clock"),
		target_body_impact_clock
	)
	var next_gait_cycle := maxf(
		SafeVariant.finite_float_or(
			state.get("gait_cycle"),
			target_gait_cycle
		),
		0.0
	)
	target_gait_stride_distance = maxf(
		SafeVariant.finite_float_or(
			state.get("gait_stride_distance"),
			PlayerGait.WALK_STEP_DISTANCE
		),
		PlayerGait.MINIMUM_STRIDE_DISTANCE
	)
	target_gait_active = SafeVariant.strict_bool_or(
		state.get("gait_active", false),
		false
	)
	target_gait_momentum_recovery = clampf(
		SafeVariant.finite_float_or(
			state.get("gait_momentum_recovery"),
			target_gait_momentum_recovery
		),
		0.0,
		1.0
	)
	target_footstep_surface = PhysicalSurface.normalize(
		state.get("footstep_surface", target_footstep_surface)
	)
	if not gait_initialized:
		visual_gait_cycle = next_gait_cycle
		last_predicted_gait_step_sequence = floori(next_gait_cycle)
		gait_initialized = true
	target_gait_cycle = next_gait_cycle
	target_edit_aim_active = SafeVariant.strict_bool_or(
		state.get("edit_aim_active", false),
		false
	)
	target_edit_aim_origin = SafeVariant.vector3_strict_or(
		state.get("edit_aim_origin", Vector3.ZERO),
		Vector3.ZERO
	)
	target_edit_aim_hit = SafeVariant.vector3_strict_or(
		state.get("edit_aim_hit", Vector3.ZERO),
		Vector3.ZERO
	)
	target_edit_aim_color = SafeVariant.color_strict_or(
		state.get("edit_aim_color", target_edit_aim_color),
		target_edit_aim_color
	)
	_apply_limb_state(SafeVariant.dictionary_copy(state.get("limbs", {}), false))
	_apply_player_system_state(state)


func apply_replicated_inventory_state(
	revision: int,
	inventory: Dictionary
) -> void:
	if revision < 0 or revision <= _last_inventory_revision:
		return
	var merged_state := target_player_state.duplicate(false)
	merged_state["inventory_revision"] = revision
	merged_state["inventory"] = inventory
	_apply_player_system_state(merged_state)


func _apply_player_system_state(state: Dictionary) -> void:
	# Scene inspection and tests can apply a snapshot before _ready initializes
	# @onready references. The children already exist on an instantiated scene.
	if inventory_hud == null:
		inventory_hud = get_node_or_null(
			"PlayerInterface/PlayerHud"
		) as PlayerInventoryHud
	if vision_effect == null:
		vision_effect = get_node_or_null(
			"OcularPostProcess/VisionEffect"
		) as OcularVisionController
	if acoustic_perception == null:
		acoustic_perception = get_node_or_null(
			"AcousticPerception/Sense"
		) as EyelessAcousticPerception
	target_stamina_ratio = clampf(
		SafeVariant.finite_float_or(
			state.get("stamina_ratio"),
			target_stamina_ratio
		),
		0.0,
		1.0
	)
	target_sprint_exhausted = SafeVariant.strict_bool_or(
		state.get("sprint_exhausted", target_sprint_exhausted),
		target_sprint_exhausted
	)
	var next_inventory_revision := SafeVariant.integral_int_or(
		state.get("inventory_revision"),
		-1
	)
	var has_inventory_payload := state.has("inventory")
	var inventory_changed := false
	if has_inventory_payload:
		inventory_changed = (
			next_inventory_revision < 0
			or next_inventory_revision > _last_inventory_revision
		)
	if inventory_changed:
		_cached_public_inventory = PlayerInventoryRules.sanitize_public_inventory(
			state.get("inventory", {})
		)
		_last_inventory_revision = next_inventory_revision
	var inventory := _cached_public_inventory
	var equipment: Dictionary = inventory["equipment"]
	if inventory_changed:
		_apply_equipment_state(equipment)
		_apply_held_item_state(inventory)
	target_player_state = state.duplicate(false)
	target_player_state["inventory"] = inventory
	var server_wrist_open := SafeVariant.strict_bool_or(
		state.get("wrist_interface_open", false),
		false
	)
	var server_wrist_page := FIELDLINK_DISPLAY_STATE.sanitize_page(
		state.get("wrist_display_page", FIELDLINK_DISPLAY_STATE.PAGE_HOME)
	)
	_apply_plasma_cutter_snapshot(state)
	target_wrist_interface_open = server_wrist_open
	target_wrist_display_page = server_wrist_page
	if is_local_player:
		if not _can_use_wrist_device():
			_set_wrist_interface_open(false, false)
		elif server_wrist_open == local_wrist_interface_open:
			wrist_request_grace_remaining = 0.0
		elif wrist_request_grace_remaining <= 0.0:
			_set_wrist_interface_open(server_wrist_open, false)
		if wrist_presentation != null and wrist_request_grace_remaining <= 0.0:
			wrist_presentation.apply_replicated_page(server_wrist_page)
	else:
		_sync_remote_wrist_display()
	if inventory_hud != null:
		inventory_hud.apply_player_state(target_player_state, inventory_changed)
	if vision_effect != null:
		var eye_entry: Dictionary = SafeVariant.dictionary_copy(
			equipment.get(PlayerInventoryRules.EYES_SLOT, {}),
			false
		)
		var has_eyes := vision_effect.set_eye_entry(eye_entry)
		local_has_equipped_eyes = has_eyes
		var distortion_state: Dictionary = SafeVariant.dictionary_copy(
			state.get("vision_distortion", {}),
			false
		)
		vision_effect.apply_distortion_state(distortion_state)
		if inventory_hud != null:
			inventory_hud.visible = is_local_player and has_eyes
		if acoustic_perception != null:
			acoustic_perception.set_perception_active(
				is_local_player and not has_eyes
			)


func _apply_equipment_state(equipment: Dictionary) -> void:
	var next_paths: Dictionary = {}
	for slot_value: Variant in equipment.keys():
		var slot := str(slot_value)
		var entry: Dictionary = SafeVariant.dictionary_copy(equipment[slot_value], false)
		if entry.is_empty():
			continue
		next_paths[slot] = str(entry.get("definition_path", ""))

	for slot_value: Variant in equipment_visuals.keys():
		var slot := str(slot_value)
		if next_paths.has(slot):
			continue
		var old_visual := equipment_visuals[slot] as Node3D
		if is_instance_valid(old_visual):
			old_visual.queue_free()
		equipment_visuals.erase(slot)
		equipment_definition_paths.erase(slot)

	for slot_value: Variant in next_paths.keys():
		var slot := str(slot_value)
		var definition_path := str(next_paths[slot])
		if equipment_definition_paths.get(slot, "") == definition_path:
			continue
		var old_visual := equipment_visuals.get(slot) as Node3D
		if is_instance_valid(old_visual):
			old_visual.queue_free()
		equipment_visuals.erase(slot)
		equipment_definition_paths.erase(slot)

		var definition := load(definition_path) as EquippableItemDefinition
		if definition == null:
			continue
		var mount := _get_equipment_mount(slot)
		if mount == null:
			continue
		var visual := definition.instantiate_equipped_visual()
		visual.name = ("%sVisual" % slot).to_pascal_case()
		if slot == PlayerInventoryRules.WRIST_DEVICE_SLOT:
			visual.scale *= EQUIPPED_WRIST_DEVICE_SCALE
		mount.add_child(visual)
		equipment_visuals[slot] = visual
		equipment_definition_paths[slot] = definition_path

	_update_local_equipment_visibility()
	_sync_remote_wrist_display()
	_sync_local_wrist_presentation_mount()
	if target_ragdoll_active:
		_sync_backpack_ragdoll_mount(true)


func has_equipped_backpack() -> bool:
	var equipment: Dictionary = _cached_public_inventory.get("equipment", {})
	var entry: Dictionary = SafeVariant.dictionary_copy(
		equipment.get(PlayerInventoryRules.BACKPACK_SLOT, {}),
		false
	)
	return not entry.is_empty()


func _get_equipment_mount(slot: String) -> Node3D:
	if character_skin != null and character_skin.is_usable():
		match slot:
			PlayerInventoryRules.BACKPACK_SLOT:
				return character_skin.get_backpack_mount()
			PlayerInventoryRules.EYES_SLOT:
				return character_skin.get_eyes_mount()
			PlayerInventoryRules.WRIST_DEVICE_SLOT:
				if has_left_arm:
					return character_skin.get_wrist_mount(true)
				if has_right_arm:
					return character_skin.get_wrist_mount(false)
	match slot:
		PlayerInventoryRules.BACKPACK_SLOT:
			return backpack_mount
		PlayerInventoryRules.EYES_SLOT:
			return eyes_mount
		PlayerInventoryRules.WRIST_DEVICE_SLOT:
			if has_left_arm:
				return left_wrist_mount
			if has_right_arm:
				return right_wrist_mount
	return null


func _update_local_equipment_visibility() -> void:
	var eye_visual := equipment_visuals.get(
		PlayerInventoryRules.EYES_SLOT
	) as Node3D
	if is_instance_valid(eye_visual):
		eye_visual.visible = not is_local_player
	var wrist_visual := equipment_visuals.get(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	) as Node3D
	if is_instance_valid(wrist_visual):
		# There is no camera-only Fieldlink copy. Owners and observers render this same equipped
		# visual, mounted to the same authored wrist pose.
		wrist_visual.visible = true


func _ensure_remote_wrist_display() -> Node:
	if is_local_player:
		return null
	if remote_wrist_display == null:
		remote_wrist_display = REMOTE_WRIST_DISPLAY.new()
		remote_wrist_display.name = "RemoteFieldlinkDisplay"
		add_child(remote_wrist_display)
	var wrist_visual := equipment_visuals.get(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	) as Node3D
	remote_wrist_display.bind_equipped_visual(
		wrist_visual if is_instance_valid(wrist_visual) else null
	)
	return remote_wrist_display


func _sync_remote_wrist_display() -> void:
	if is_local_player:
		if remote_wrist_display != null:
			remote_wrist_display.set_open(false)
		return
	var display := _ensure_remote_wrist_display()
	if display == null:
		return
	display.set_page(target_wrist_display_page)
	display.set_open(
		target_wrist_interface_open and has_equipped_wrist_device()
	)
	var server := get_node_or_null("/root/Server")
	if server != null and server.has_method("get_lobby_session_label"):
		display.set_session_info(str(server.call("get_lobby_session_label")))


func _apply_held_item_state(inventory: Dictionary) -> void:
	var entries: Array = inventory.get("entries", [])
	var selected_slot := int(inventory.get("selected_slot", 0))
	var entry: Dictionary = (
		entries[selected_slot]
		if selected_slot >= 0 and selected_slot < entries.size()
		else {}
	)
	var definition_path := str(entry.get("definition_path", ""))
	var state: Dictionary = SafeVariant.dictionary_copy(
		entry.get("instance_state", {}),
		false
	)
	var build_signature := str(state.get(
		GunItemDefinition.BUILD_SIGNATURE_KEY,
		""
	))
	if build_signature.is_empty():
		build_signature = GunBuild.visual_signature_from_state(
			SafeVariant.dictionary_copy(state.get("build", {}), false)
		)
	var signature := (
		definition_path
		+ "|"
		+ build_signature
		+ ("|local" if is_local_player else "|remote")
	)
	if signature == held_item_signature:
		return
	held_item_signature = signature
	held_item_definition_path = definition_path
	held_item_state = state.duplicate(true)
	_rebuild_held_item_visual()


func _rebuild_held_item_visual() -> void:
	if is_instance_valid(held_item_visual):
		held_item_visual.queue_free()
	held_item_visual = null
	if held_item_definition_path.is_empty():
		return
	var definition := load(held_item_definition_path) as ItemDefinition
	if (
		definition == null
		or not (
			definition is GunItemDefinition
			or definition is PlasmaCutterDefinition
		)
		or not definition.has_method("instantiate_held_visual")
	):
		return
	var mount := _get_held_item_visual_mount()
	held_item_visual = definition.call(
		"instantiate_held_visual",
		held_item_state,
		is_local_player
	) as Node3D
	if held_item_visual == null:
		return
	held_item_visual.name = "HeldItemVisual"
	mount.add_child(held_item_visual)
	_update_held_item_mount()
	_sync_plasma_cutter_emitter()


func _get_held_item_visual_mount() -> Node3D:
	if is_local_player:
		return first_person_item_mount
	if character_skin != null and character_skin.is_usable():
		var uses_left := not has_right_arm and has_left_arm
		return character_skin.get_hand_item_mount(uses_left)
	return held_item_mount


func _apply_limb_state(limbs: Dictionary) -> void:
	if limbs.is_empty():
		return

	has_left_arm = bool(limbs.get("left_arm", true))
	has_right_arm = bool(limbs.get("right_arm", true))
	has_left_leg = bool(limbs.get("left_leg", true))
	has_right_leg = bool(limbs.get("right_leg", true))
	procedural_leg_rig.set_limb_presence(has_left_leg, has_right_leg)
	if character_skin != null:
		character_skin.set_limb_presence(
			has_left_arm,
			has_right_arm,
			has_left_leg,
			has_right_leg
		)
	_sync_character_appearance()
	player_ragdoll.set_limb_presence(
		has_left_arm,
		has_right_arm,
		has_left_leg,
		has_right_leg
	)
	_update_held_item_mount()
	_reparent_wrist_visual()
	if wrist_presentation != null:
		_sync_local_wrist_presentation_mount()


func _update_held_item_mount() -> void:
	var uses_right := has_right_arm or not has_left_arm
	held_item_mount.position.x = (
		HELD_ITEM_SIDE_OFFSET
		if uses_right
		else -HELD_ITEM_SIDE_OFFSET
	)
	held_item_mount.rotation.z = (
		-HELD_ITEM_ROLL
		if uses_right
		else HELD_ITEM_ROLL
	)
	first_person_item_mount.position.x = (
		FIRST_PERSON_ITEM_SIDE_OFFSET
		if uses_right
		else -FIRST_PERSON_ITEM_SIDE_OFFSET
	)
	if is_instance_valid(held_item_visual):
		held_item_visual.visible = (
			(has_left_arm or has_right_arm)
			and not (
				local_wrist_interface_open
				or target_wrist_interface_open
			)
			and not target_ragdoll_active
		)


func _reparent_wrist_visual() -> void:
	var wrist_visual := equipment_visuals.get(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	) as Node3D
	if not is_instance_valid(wrist_visual):
		return
	var next_mount := _get_equipment_mount(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	)
	if next_mount == null or wrist_visual.get_parent() == next_mount:
		return
	wrist_visual.reparent(next_mount, false)


func _reparent_equipment_visuals() -> void:
	for slot_value: Variant in equipment_visuals.keys():
		var slot := str(slot_value)
		var visual := equipment_visuals.get(slot) as Node3D
		if not is_instance_valid(visual):
			continue
		var next_mount := _get_equipment_mount(slot)
		if next_mount == null or visual.get_parent() == next_mount:
			continue
		visual.reparent(next_mount, false)


func _reparent_held_item_visual() -> void:
	if not is_instance_valid(held_item_visual):
		return
	var next_mount := _get_held_item_visual_mount()
	if next_mount == null or held_item_visual.get_parent() == next_mount:
		return
	held_item_visual.reparent(next_mount, false)


func has_equipped_wrist_device() -> bool:
	return equipment_definition_paths.has(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	)


func has_equipped_eyes() -> bool:
	return local_has_equipped_eyes


func get_audio_listener_position() -> Vector3:
	if is_instance_valid(audio_listener):
		return audio_listener.global_position
	if is_instance_valid(camera):
		return camera.global_position
	return global_position + Vector3.UP * 0.55


func is_wrist_interface_open() -> bool:
	return local_wrist_interface_open


func _on_acoustic_perception_event_rendered(packet: Dictionary) -> void:
	if is_local_player and acoustic_perception != null:
		acoustic_perception.submit_acoustic_event(packet)


func _on_acoustic_perception_continuous_sample(
	source_id: int,
	apparent_position: Vector3,
	received_intensity: float,
	band_gain: Vector3,
	enclosure: float
) -> void:
	if is_local_player and acoustic_perception != null:
		acoustic_perception.submit_continuous_sample(
			source_id,
			apparent_position,
			received_intensity,
			band_gain,
			enclosure
		)


func get_wrist_sound_source_position() -> Vector3:
	if is_instance_valid(audio_listener):
		return audio_listener.global_position + Vector3.DOWN * 0.12
	return global_position + Vector3.UP * 0.44


func get_weapon_sound_source_position() -> Vector3:
	if is_instance_valid(camera):
		return (
			camera.global_position
			- camera.global_basis.z.normalized() * 0.92
			+ Vector3.DOWN * 0.18
		)
	return global_position + Vector3.UP * 0.45


func get_weapon_audio_prediction_profile() -> Dictionary:
	if (
		SafeVariant.finite_float_or(
			target_player_state.get("weapon_reload_ratio"),
			0.0
		) > 0.0001
		or not (has_left_arm or has_right_arm)
	):
		return {}
	var inventory := _cached_public_inventory
	if inventory.is_empty():
		return {}
	var entries: Array = inventory.get("entries", [])
	var selected_slot := int(inventory.get("selected_slot", 0))
	if selected_slot < 0 or selected_slot >= entries.size():
		return {}
	var entry: Dictionary = entries[selected_slot]
	var definition := PlayerInventoryRules.get_definition(entry) as GunItemDefinition
	if definition == null:
		return {}
	var state := definition.normalize_instance_state(
		SafeVariant.dictionary_copy(entry.get("instance_state", {}))
	)
	var rounds := int(state.get("rounds", 0))
	if rounds <= 0:
		return {}
	var build := definition.get_build(state)
	if not build.is_compatible():
		return {}
	var ballistic_profiles := build.get_ballistic_profiles()
	var sound_profile := build.get_fire_sound_profile()
	if ballistic_profiles.is_empty() or sound_profile.is_empty():
		return {}
	var result := sound_profile.duplicate(false)
	result["automatic"] = build.is_automatic()
	result["rounds_per_second"] = maxf(
		SafeVariant.finite_float_or(
			(ballistic_profiles[0] as Dictionary).get("rounds_per_second"),
			1.0
		),
		0.1
	)
	result["available_rounds"] = rounds
	result["rounds_per_trigger"] = ballistic_profiles.size()
	return result


func set_local_locomotion_input(move_input: Vector2, wants_run: bool) -> void:
	if not is_local_player:
		return
	local_move_input = move_input.limit_length(1.0)
	local_run_input = wants_run
	if (
		not local_run_input
		or local_move_input.length_squared()
		<= ServerPlayer.MOVEMENT_INPUT_THRESHOLD_SQUARED
	):
		_clear_flip_gesture()


# Shared entry point for the keyboard and technical-object interfaces. Server-
# driven devices can open the same view through the replicated wrist state.
func open_wrist_interface() -> bool:
	if not _can_use_wrist_device():
		return false
	_set_wrist_interface_open(true)
	return local_wrist_interface_open


func close_wrist_interface() -> void:
	_set_wrist_interface_open(false)


func toggle_wrist_interface() -> bool:
	if local_wrist_interface_open:
		close_wrist_interface()
		return false
	return open_wrist_interface()


func _can_use_wrist_device() -> bool:
	return (
		has_equipped_wrist_device()
		and (has_left_arm or has_right_arm)
		and not target_ragdoll_active
		and not target_flip_active
		and not local_flip_prediction_active
	)


func _set_wrist_interface_open(
	value: bool,
	notify_server := true
) -> void:
	var next_value := value and _can_use_wrist_device()
	if next_value == local_wrist_interface_open:
		return
	if not next_value:
		local_plasma_cutter_trigger_held = false
	if next_value:
		_clear_flip_gesture()
		wrist_mouse_look_owns_pitch = false
		wrist_mouse_look_blend = 0.0
		fieldlink_pose_pitch = WRIST_LOOK_PITCH
		fieldlink_hold_motion_active = false
		if character_skin != null:
			character_skin.reset_fieldlink_arm_pose_history()
	else:
		# RMB may legitimately have used Fieldlink's wider pitch range. Do not leak that device-only
		# angle back into ordinary view when the terminal closes.
		look_pitch = maxf(look_pitch, MIN_WORLD_LOOK_PITCH)
	wrist_mouse_look_active = false
	local_wrist_interface_open = next_value
	target_wrist_interface_open = next_value
	if notify_server:
		wrist_request_grace_remaining = WRIST_REQUEST_GRACE_SECONDS
	_ensure_wrist_presentation()
	if wrist_presentation != null:
		wrist_presentation.set_scanner_heading(look_yaw)
		_refresh_wrist_session_info()
		wrist_presentation.set_open(local_wrist_interface_open)
		wrist_session_refresh_remaining = 0.0
		wrist_scanner_refresh_remaining = 0.0
		wrist_control_refresh_remaining = 0.0
	# Fieldlink owns a bounded in-screen cursor. Keep raw mouse motion captured
	# for both pointer control and the RMB look clutch so no desktop cursor can
	# escape the physical display or accumulate a transition delta.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	grab_rotation_input = Vector2.ZERO
	_update_held_item_mount()
	var client := get_node_or_null("/root/Client")
	if notify_server and client != null:
		client.call(
			"set_wrist_interface_open",
			local_wrist_interface_open
		)


func _ensure_wrist_presentation() -> void:
	if wrist_presentation != null or not is_local_player:
		return
	wrist_presentation = (
		WRIST_PRESENTATION_SCENE.instantiate()
		as WristTerminalPresentation
	)
	if wrist_presentation == null:
		return
	add_child(wrist_presentation)
	wrist_presentation.bind_camera(camera)
	var client := get_node_or_null("/root/Client")
	if client != null and client.has_method("get_listener_acoustic_intensity"):
		wrist_presentation.set_acoustic_intensity_provider(
			Callable(client, "get_listener_acoustic_intensity")
		)
	_sync_local_wrist_presentation_mount()
	wrist_presentation.set_scanner_heading(look_yaw)
	wrist_presentation.invite_friend_requested.connect(
		_on_invite_friend_requested
	)
	wrist_presentation.return_to_menu_requested.connect(
		_on_return_to_menu_requested
	)
	wrist_presentation.device_sound_requested.connect(
		_on_wrist_device_sound_requested
	)
	wrist_presentation.device_control_requested.connect(
		_on_wrist_device_control_requested
	)
	wrist_presentation.device_command_requested.connect(
		_on_wrist_device_command_requested
	)
	wrist_presentation.display_page_changed.connect(
		_on_wrist_display_page_changed
	)
	wrist_presentation.apply_replicated_page(target_wrist_display_page)


func _refresh_wrist_session_info() -> void:
	if wrist_presentation == null:
		return
	var server := get_node_or_null("/root/Server")
	wrist_presentation.set_session_info(
		str(server.call("get_lobby_session_label"))
		if server != null
		else "OFFLINE",
		bool(server.call("can_invite_to_current_lobby"))
		if server != null
		else false
	)


func _refresh_wrist_scanner_contacts() -> void:
	if wrist_presentation == null:
		return
	wrist_presentation.set_scanner_contacts(
		_collect_wrist_scanner_contacts(
			global_position + Vector3.UP * 0.56,
			look_yaw
		),
		WRIST_SCANNER_RANGE_METERS
	)


func _collect_wrist_scanner_contacts(
	origin: Vector3,
	yaw: float
) -> Array[Dictionary]:
	var client := get_node_or_null("/root/Client")
	if client == null or not client.has_method("collect_nearby_fieldlink_devices"):
		return []
	var contacts_value: Variant = client.call(
		"collect_nearby_fieldlink_devices",
		origin,
		yaw,
		WRIST_SCANNER_RANGE_METERS
	)
	var contacts: Array[Dictionary] = []
	if contacts_value is Array:
		for contact_value: Variant in contacts_value:
			if contact_value is Dictionary:
				contacts.append((contact_value as Dictionary).duplicate(false))
	return contacts


func _on_invite_friend_requested() -> void:
	if wrist_presentation == null:
		return
	var server := get_node_or_null("/root/Server")
	var opened := (
		bool(server.call("open_steam_invite_overlay"))
		if server != null
		else false
	)
	wrist_presentation.set_feedback(
		"STEAM INVITE OVERLAY OPENED"
		if opened
		else "INVITES ARE NOT AVAILABLE",
		not opened
	)


func _on_return_to_menu_requested() -> void:
	if not local_wrist_interface_open:
		return
	_set_wrist_interface_open(false)
	var server := get_node_or_null("/root/Server")
	if server != null:
		server.call("leave_steam_session")


func _on_wrist_device_sound_requested(sound_id: StringName) -> void:
	if not local_wrist_interface_open:
		return
	var client := get_node_or_null("/root/Client")
	if client != null:
		client.call("request_wrist_device_sound", sound_id)


func _on_wrist_device_control_requested(contact_id: StringName) -> void:
	if not local_wrist_interface_open:
		return
	wrist_control_refresh_remaining = WRIST_CONTROL_REFRESH_SECONDS
	var client := get_node_or_null("/root/Client")
	if client != null:
		client.call("request_fieldlink_device_control", contact_id)


func _on_wrist_device_command_requested(
	contact_id: StringName,
	action: StringName,
	payload: Dictionary
) -> void:
	if not local_wrist_interface_open:
		return
	wrist_control_refresh_remaining = WRIST_CONTROL_REFRESH_SECONDS
	var client := get_node_or_null("/root/Client")
	if client != null:
		client.call(
			"send_fieldlink_device_command",
			contact_id,
			action,
			payload
		)


func _on_wrist_display_page_changed(page_value: StringName) -> void:
	if not is_local_player:
		return
	target_wrist_display_page = FIELDLINK_DISPLAY_STATE.sanitize_page(page_value)
	var client := get_node_or_null("/root/Client")
	if client != null:
		client.call("set_wrist_display_page", target_wrist_display_page)


func apply_replicated_wrist_state(
	open_value: bool,
	page_value: Variant
) -> void:
	if open_value and not target_wrist_interface_open:
		fieldlink_pose_pitch = WRIST_LOOK_PITCH
	target_wrist_interface_open = open_value
	target_wrist_display_page = FIELDLINK_DISPLAY_STATE.sanitize_page(page_value)
	if is_local_player:
		if wrist_request_grace_remaining <= 0.0:
			_set_wrist_interface_open(open_value, false)
			if wrist_presentation != null:
				wrist_presentation.apply_replicated_page(
					target_wrist_display_page
				)
		return
	_sync_remote_wrist_display()


func _apply_plasma_cutter_snapshot(state: Dictionary) -> void:
	target_plasma_cutter_available = SafeVariant.strict_bool_or(
		state.get("plasma_cutter_available", false),
		false
	)
	target_plasma_cutter_heat_ratio = clampf(
		SafeVariant.finite_float_or(
			state.get("plasma_cutter_heat_ratio"),
			target_plasma_cutter_heat_ratio
		),
		0.0,
		1.0
	)
	target_plasma_cutter_overheated = SafeVariant.strict_bool_or(
		state.get("plasma_cutter_overheated", false),
		false
	)
	target_plasma_cutter_active = SafeVariant.strict_bool_or(
		state.get("plasma_cutter_active", false),
		false
	)
	target_plasma_cutter_has_hit = SafeVariant.strict_bool_or(
		state.get("plasma_cutter_has_hit", false),
		false
	)
	target_plasma_cutter_hit_position = SafeVariant.vector3_strict_or(
		state.get("plasma_cutter_hit_position", target_plasma_cutter_hit_position),
		target_plasma_cutter_hit_position
	)
	target_plasma_cutter_range_meters = maxf(
		SafeVariant.finite_float_or(
			state.get("plasma_cutter_range_meters"),
			target_plasma_cutter_range_meters
		),
		0.0
	)
	target_plasma_cutter_kerf_millimeters = maxf(
		SafeVariant.finite_float_or(
			state.get("plasma_cutter_kerf_millimeters"),
			target_plasma_cutter_kerf_millimeters
		),
		0.0
	)
	target_plasma_cutter_cut_depth_millimeters = maxf(
		SafeVariant.finite_float_or(
			state.get("plasma_cutter_cut_depth_millimeters"),
			target_plasma_cutter_cut_depth_millimeters
		),
		0.0
	)
	target_plasma_cutter_continuous_duty_seconds = maxf(
		SafeVariant.finite_float_or(
			state.get("plasma_cutter_continuous_duty_seconds"),
			target_plasma_cutter_continuous_duty_seconds
		),
		0.0
	)
	target_plasma_cutter_full_cool_seconds = maxf(
		SafeVariant.finite_float_or(
			state.get("plasma_cutter_full_cool_seconds"),
			target_plasma_cutter_full_cool_seconds
		),
		0.0
	)
	if target_plasma_cutter_overheated and local_plasma_cutter_trigger_held:
		local_plasma_cutter_trigger_held = false


func _ensure_plasma_cutter_beam() -> void:
	if plasma_cutter_beam != null:
		return
	plasma_cutter_beam = PLASMA_CUTTER_BEAM_SCRIPT.new() as Node3D
	if plasma_cutter_beam == null:
		return
	plasma_cutter_beam.name = "PlasmaCutterBeam"
	add_child(plasma_cutter_beam)
	_sync_plasma_cutter_emitter()


func _sync_plasma_cutter_emitter() -> void:
	plasma_cutter_emitter = null
	if is_instance_valid(held_item_visual):
		plasma_cutter_emitter = held_item_visual.find_child(
			"PlasmaEmitter",
			true,
			false
		) as Node3D
	if plasma_cutter_beam != null:
		plasma_cutter_beam.call("bind_emitter", plasma_cutter_emitter)


func _predicted_plasma_cutter_hit() -> Dictionary:
	if (
		camera == null
		or target_plasma_cutter_range_meters <= 0.0
	):
		return {}
	# Authority casts from ServerPlayer/Grabber, whose authored transform matches this camera. The
	# visible beam begins at the handheld emitter and converges on this shared aim ray so its
	# endpoint and the resulting destruction can never be parallel-but-offset.
	var origin := camera.global_position
	var direction := -camera.global_basis.z.normalized()
	var finish := origin + direction * target_plasma_cutter_range_meters
	var query := PhysicsRayQueryParameters3D.create(origin, finish)
	query.collide_with_areas = false
	var server := get_node_or_null("/root/Server")
	if server != null and server.has_method("get_server_player"):
		var server_player := server.call("get_server_player", player_id) as PhysicsBody3D
		if server_player != null:
			query.exclude = [server_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": finish, "has_hit": false}
	return {
		"position": hit.get("position", finish),
		"has_hit": true,
	}


func _update_plasma_cutter_presentation(delta: float) -> void:
	_ensure_plasma_cutter_beam()
	if plasma_cutter_beam == null:
		return
	var active := target_plasma_cutter_active
	var endpoint := target_plasma_cutter_hit_position
	var has_hit := target_plasma_cutter_has_hit
	if is_local_player:
		active = (
			local_plasma_cutter_trigger_held
			and not local_wrist_interface_open
			and not target_plasma_cutter_overheated
		)
		if active:
			var prediction := _predicted_plasma_cutter_hit()
			endpoint = prediction.get("position", endpoint)
			has_hit = bool(prediction.get("has_hit", has_hit))
			# Prediction makes the first press visible immediately. As soon as authority has evaluated
			# that same held press, its endpoint wins: this is the exact world point receiving cuts.
			if (
				target_plasma_cutter_active
				and target_plasma_cutter_hit_position.is_finite()
			):
				endpoint = target_plasma_cutter_hit_position
				has_hit = target_plasma_cutter_has_hit
	plasma_cutter_beam.call(
		"update_beam",
		endpoint,
		active,
		has_hit,
		target_plasma_cutter_heat_ratio,
		delta,
		is_local_player
	)


func apply_fieldlink_device_control_snapshot(snapshot: Dictionary) -> void:
	if local_wrist_interface_open and wrist_presentation != null:
		wrist_presentation.apply_device_control_snapshot(snapshot)


func apply_fieldlink_device_control_error(
	contact_id: StringName,
	message: String
) -> void:
	if local_wrist_interface_open and wrist_presentation != null:
		wrist_presentation.apply_device_control_error(contact_id, message)


func _update_wrist_pose(delta: float) -> void:
	var pose_active := (
		local_wrist_interface_open
		if is_local_player
		else target_wrist_interface_open
	)
	wrist_pose_weight = move_toward(
		wrist_pose_weight,
		1.0 if pose_active else 0.0,
		WRIST_POSE_BLEND_SPEED * maxf(delta, 0.0)
	)
	wrist_mouse_look_blend = move_toward(
		wrist_mouse_look_blend,
		1.0 if wrist_mouse_look_active else 0.0,
		WRIST_LOOK_RECENTER_SPEED * maxf(delta, 0.0)
	)
	if (
		not wrist_mouse_look_active
		and is_zero_approx(wrist_mouse_look_blend)
	):
		wrist_mouse_look_owns_pitch = false
	if not pose_active and is_zero_approx(wrist_pose_weight):
		wrist_mouse_look_owns_pitch = false
		wrist_mouse_look_blend = 0.0
	_update_held_item_mount()


static func _apply_remote_arm_pose(
	arm: MeshInstance3D,
	rest_position: Vector3,
	shoulder_position: Vector3,
	pose_rotation: Vector3,
	weight: float
) -> void:
	var bounded_weight := clampf(weight, 0.0, 1.0)
	var next_rotation := pose_rotation * bounded_weight
	arm.rotation = next_rotation
	arm.position = (
		shoulder_position
		+ Basis.from_euler(next_rotation) * (
			rest_position - shoulder_position
		)
	)

func update_headbob(delta: float) -> void:
	var replicated_horizontal_speed := Vector2(
		target_velocity.x,
		target_velocity.z
	).length()
	var horizontal_speed := replicated_horizontal_speed
	var stride_distance := maxf(
		target_gait_stride_distance,
		PlayerGait.MINIMUM_STRIDE_DISTANCE
	)
	resolved_gait_momentum_recovery = target_gait_momentum_recovery
	var is_moving := (
		target_gait_active
		and target_on_floor
		and not target_ragdoll_active
	)
	# A listen-server owner is still a local presentation client. Using the authoritative branch for
	# that one peer made host gait feedback follow a different clock than joining clients and hid the
	# split during local testing. Reconciliation keys make the prediction safe regardless of whether
	# the authority packet arrives before or after this phase crossing.
	var predicts_from_local_intent := is_local_player
	if predicts_from_local_intent:
		var input_strength := clampf(local_move_input.length(), 0.0, 1.0)
		if target_ragdoll_active:
			input_strength = 0.0
		if not local_locomotion_prediction_initialized:
			var initial_local_velocity := global_basis.inverse() * target_velocity
			local_predicted_horizontal_velocity = Vector2(
				initial_local_velocity.x,
				initial_local_velocity.z
			)
			local_locomotion_prediction_initialized = true
		var local_sprint_requested := (
			local_run_input
			and input_strength > 0.001
			and not target_sprint_exhausted
			and target_stamina_ratio
			> ServerPlayer.STAMINA_EMPTY_THRESHOLD / ServerPlayer.MAX_STAMINA
		)
		local_recovery_gait.update_momentum_recovery(
			local_predicted_horizontal_speed,
			target_on_floor,
			local_sprint_requested,
			delta
		)
		resolved_gait_momentum_recovery = (
			local_recovery_gait.get_momentum_recovery_weight()
		)
		local_sprint_speed_ramp_elapsed = (
			ServerPlayer.advance_sprint_speed_ramp(
				local_sprint_speed_ramp_elapsed,
				local_sprint_requested,
				target_on_floor,
				delta
			)
		)
		var wish_speed_limit := ServerPlayer.WALK_SPEED
		if local_sprint_requested:
			wish_speed_limit = ServerPlayer.sprint_speed_at_elapsed(
				local_sprint_speed_ramp_elapsed
			)
		var wish_speed := wish_speed_limit * input_strength
		var predicted_velocity := Vector3.ZERO
		if not target_ragdoll_active:
			predicted_velocity = ServerPlayer.calculate_horizontal_velocity(
				Vector3(
					local_predicted_horizontal_velocity.x,
					0.0,
					local_predicted_horizontal_velocity.y
				),
				Vector3(
					local_move_input.x / input_strength,
					0.0,
					local_move_input.y / input_strength
				) if input_strength > 0.001 else Vector3.ZERO,
				wish_speed,
				target_on_floor,
				delta,
				resolved_gait_momentum_recovery
			)
		local_predicted_horizontal_velocity = Vector2(
			predicted_velocity.x,
			predicted_velocity.z
		)
		local_predicted_horizontal_speed = predicted_velocity.length()
		horizontal_speed = local_predicted_horizontal_speed
		stride_distance = PlayerGait.get_stride_distance_for_motion_and_recovery(
			horizontal_speed,
			local_run_input,
			player_id,
			floori(visual_gait_cycle),
			resolved_gait_momentum_recovery
		)
		is_moving = (
			target_on_floor
			and not target_ragdoll_active
			and (
				horizontal_speed * horizontal_speed
				>= PlayerGait.MINIMUM_SPEED_SQUARED
				or resolved_gait_momentum_recovery > 0.001
			)
		)
	else:
		local_predicted_horizontal_speed = replicated_horizontal_speed
	headbob_weight = move_toward(
		headbob_weight,
		1.0 if is_moving else 0.0,
		HEADBOB_BLEND_SPEED * delta
	)
	var run_target := clampf(
		inverse_lerp(
			PlayerGait.WALK_STEP_DISTANCE_RANGE.y,
			PlayerGait.RUN_STEP_DISTANCE_RANGE.x,
			stride_distance
		),
		0.0,
		1.0
	)
	run_target = maxf(
		run_target,
		resolved_gait_momentum_recovery * 0.78
	)
	headbob_run_weight = move_toward(
		headbob_run_weight,
		run_target,
		HEADBOB_RUN_BLEND_SPEED * delta
	)

	if not gait_initialized:
		return
	stride_distance = maxf(stride_distance, PlayerGait.MINIMUM_STRIDE_DISTANCE)
	var cycles_per_second := (
		PlayerGait.get_effective_gait_speed(
			horizontal_speed,
			resolved_gait_momentum_recovery
		) / stride_distance
		if is_moving
		else 0.0
	)
	visual_gait_cycle += cycles_per_second * maxf(delta, 0.0)
	var predicted_cycle := (
		target_gait_cycle
		+ cycles_per_second * time_since_last_state
	)
	var cycle_error := predicted_cycle - visual_gait_cycle
	if predicts_from_local_intent and is_moving:
		# The received owner snapshot describes an earlier simulation instant. Never drag an active
		# locally-integrated gait backwards toward that stale phase; the monotonically increasing server
		# sequence still catches up and reconciles the predicted sound key without replaying it.
		cycle_error = maxf(cycle_error, 0.0)
	if absf(cycle_error) >= HEADBOB_PHASE_SNAP_CYCLES:
		visual_gait_cycle = predicted_cycle
	else:
		visual_gait_cycle += cycle_error * clampf(
			HEADBOB_PHASE_SYNC_SPEED * delta,
			0.0,
			1.0
		)


func _predict_local_footstep() -> void:
	if (
		not is_local_player
		or not gait_initialized
		or procedural_leg_rig == null
		or not procedural_leg_rig.has_foot_contact_event()
	):
		return
	var contact_sequence := procedural_leg_rig.get_foot_contact_event_sequence()
	if contact_sequence <= last_predicted_gait_step_sequence:
		return
	var sound_id := PhysicalSurface.footstep_sound_id(
		procedural_leg_rig.get_foot_contact_event_surface()
	)
	var profile := LOCAL_AUDIO_PREDICTION.player_cue_profile(sound_id)
	profile["volume_db"] = PlayerGait.get_footstep_volume_db_for_motion(
		Vector2(target_velocity.x, target_velocity.z).length(),
		player_id,
		contact_sequence
	)
	var prediction_key := LOCAL_AUDIO_PREDICTION.gait_step_key(
		contact_sequence
	)
	var client := get_node_or_null("/root/Client")
	if client != null:
		client.call(
			"predict_local_player_sound",
			sound_id,
			procedural_leg_rig.get_foot_contact_event_position(),
			profile,
			prediction_key
		)
		client.call(
			"request_foot_contact",
			contact_sequence,
			procedural_leg_rig.get_foot_contact_event_side(),
			prediction_key
		)
	last_predicted_gait_step_sequence = contact_sequence
	
func set_local_player(value: bool) -> void:
	is_local_player = value

	if not is_node_ready():
		return

	camera.current = is_local_player
	if is_local_player:
		audio_listener.make_current()
	elif audio_listener.is_current():
		audio_listener.clear_current()
	interface_layer.visible = is_local_player
	vision_layer.visible = is_local_player
	if acoustic_perception != null:
		acoustic_perception.set_perception_active(
			is_local_player and not local_has_equipped_eyes
		)
	if character_skin != null:
		character_skin.set_local_view(is_local_player)
	if player_ragdoll != null:
		player_ragdoll.set_local_view(is_local_player)
	_sync_character_appearance()

	if is_local_player:
		_arm_capture_transition_guard()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not target_player_state.is_empty():
			_apply_player_system_state(target_player_state)
	else:
		local_plasma_cutter_trigger_held = false
		local_wrist_interface_open = false
		wrist_mouse_look_active = false
		wrist_mouse_look_owns_pitch = false
		wrist_mouse_look_blend = 0.0
		wrist_request_grace_remaining = 0.0
		if wrist_presentation != null:
			wrist_presentation.set_open(false)
	_update_local_equipment_visibility()
	held_item_signature = ""
	_rebuild_held_item_visual()


func _resolved_camera_pitch() -> float:
	var operating_pitch := lerp_angle(
		look_pitch,
		WRIST_LOOK_PITCH,
		wrist_pose_weight
	)
	if not wrist_mouse_look_owns_pitch:
		return operating_pitch
	return lerp_angle(
		operating_pitch,
		look_pitch,
		clampf(wrist_mouse_look_blend, 0.0, 1.0)
	)


static func _safe_fieldlink_pose_pitch(value: float) -> float:
	return clampf(
		value if is_finite(value) else WRIST_LOOK_PITCH,
		FIELDLINK_POSE_MIN_PITCH,
		FIELDLINK_POSE_MAX_PITCH
	)


static func _focused_fieldlink_pose_pitch(camera_pitch: float) -> float:
	var resolved_pitch := camera_pitch if is_finite(camera_pitch) else WRIST_LOOK_PITCH
	if resolved_pitch <= WRIST_LOOK_PITCH:
		# Looking farther down remains a useful request: follow it across the physical arm's readable arc.
		return _safe_fieldlink_pose_pitch(resolved_pitch)
	var upward_head_ratio := clampf(
		inverse_lerp(WRIST_LOOK_PITCH, MAX_LOOK_PITCH, resolved_pitch),
		0.0,
		1.0
	)
	return lerpf(
		WRIST_LOOK_PITCH,
		FIELDLINK_UPWARD_FOCUS_PITCH,
		smoothstep(0.0, 1.0, upward_head_ratio)
	)


func _process(delta: float) -> void:
	# LMB is already streamed through the ordinary primary-action route. Mirror it locally only for
	# zero-latency beam presentation; authority still decides every destructive contact.
	if is_local_player:
		local_plasma_cutter_trigger_held = (
			target_plasma_cutter_available
			and not target_plasma_cutter_overheated
			and not local_wrist_interface_open
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		)
	flip_flick_sample_remaining = maxf(
		flip_flick_sample_remaining - maxf(delta, 0.0),
		0.0
	)
	if flip_flick_sample_remaining <= 0.0:
		flip_flick_accumulated_pitch = 0.0
		flip_flick_accumulated_elapsed = 0.0
	dropkick_tilt_sample_remaining = maxf(
		dropkick_tilt_sample_remaining - maxf(delta, 0.0),
		0.0
	)
	if dropkick_tilt_sample_remaining <= 0.0:
		dropkick_tilt_accumulated_yaw = 0.0
		dropkick_tilt_accumulated_elapsed = 0.0
	if local_flip_prediction_request_id > 0:
		local_flip_request_elapsed += maxf(delta, 0.0)
		if local_flip_request_elapsed >= FLIP_REQUEST_TIMEOUT_SECONDS:
			resolve_local_jump_request(
				local_flip_prediction_request_id,
				false,
				0
			)
	_update_wrist_pose(delta)
	if (
		is_local_player
		and local_wrist_interface_open
		and wrist_presentation != null
	):
		wrist_presentation.set_scanner_heading(look_yaw)
	elif (
		not is_local_player
		and target_wrist_interface_open
		and remote_wrist_display != null
	):
		remote_wrist_display.set_scanner_heading(rotation.y)
	if is_local_player:
		wrist_request_grace_remaining = maxf(
			wrist_request_grace_remaining - maxf(delta, 0.0),
			0.0
		)
	if is_local_player and local_wrist_interface_open:
		wrist_session_refresh_remaining -= delta
		if wrist_session_refresh_remaining <= 0.0:
			wrist_session_refresh_remaining = 1.0
			_refresh_wrist_session_info()
		if (
			wrist_presentation != null
		):
			wrist_scanner_refresh_remaining -= delta
			if wrist_scanner_refresh_remaining <= 0.0:
				wrist_scanner_refresh_remaining = WRIST_SCANNER_REFRESH_SECONDS
				_refresh_wrist_scanner_contacts()
			if not wrist_presentation.is_scanner_page_active():
				wrist_control_refresh_remaining = 0.0
			else:
				var selected_contact_id := wrist_presentation.get_selected_contact_id()
				if (
					selected_contact_id.is_empty()
					or wrist_presentation.get_selected_control_type().is_empty()
				):
					wrist_control_refresh_remaining = 0.0
				else:
					wrist_control_refresh_remaining -= delta
					if wrist_control_refresh_remaining <= 0.0:
						wrist_control_refresh_remaining = WRIST_CONTROL_REFRESH_SECONDS
						_on_wrist_device_control_requested(selected_contact_id)
		else:
			wrist_scanner_refresh_remaining = 0.0
			wrist_control_refresh_remaining = 0.0
	elif not is_local_player and target_wrist_interface_open:
		wrist_scanner_refresh_remaining -= delta
		if wrist_scanner_refresh_remaining <= 0.0:
			wrist_scanner_refresh_remaining = WRIST_SCANNER_REFRESH_SECONDS
			var display := _ensure_remote_wrist_display()
			if display != null:
				display.set_scanner_heading(rotation.y)
				display.set_scanner_contacts(
					_collect_wrist_scanner_contacts(
						global_position + Vector3.UP * 0.56,
						rotation.y
					),
					WRIST_SCANNER_RANGE_METERS
				)
	if is_local_player and vision_effect != null:
		vision_effect.update_view(look_yaw, look_pitch, delta)

	# The host can follow its authoritative CharacterBody3D without any
	# snapshot delay. Joining clients use the extrapolated snapshot below.
	if multiplayer.is_server():
		var server := get_node_or_null("/root/Server")
		var server_player: ServerPlayer = (
			server.call("get_server_player", player_id) as ServerPlayer
			if server != null
			else null
		)

		if is_instance_valid(server_player):
			global_position = server_player.global_position
			target_velocity = server_player.velocity
			target_on_floor = server_player.on_floor
			target_edit_aim_active = server_player.edit_aim_active
			target_edit_aim_origin = server_player.edit_aim_origin
			target_edit_aim_hit = server_player.edit_aim_hit
			target_edit_aim_color = server_player.edit_aim_color
			target_gait_cycle = server_player.gait.get_cycle()
			target_gait_stride_distance = server_player.gait.stride_distance
			target_gait_active = server_player.gait.active
			target_gait_momentum_recovery = (
				server_player.gait.get_momentum_recovery_weight()
			)
			target_expression_clock = server_player.expression_clock
			target_jump_sequence = server_player.jump_sequence
			target_flip_sequence = server_player.flip_sequence
			target_flip_direction = server_player.flip_direction
			target_flip_active = server_player.flip_active
			target_flip_phase = server_player.flip_phase
			target_kick_sequence = server_player.kick_sequence
			target_kick_side = server_player.kick_side
			target_kick_style = server_player.kick_style
			target_kick_active = server_player.kick_active
			target_kick_phase = server_player.kick_phase
			target_kick_clock = server_player.kick_clock
			target_kick_direction = server_player.kick_direction
			target_kick_view_yaw = server_player.kick_view_yaw
			target_kick_view_pitch = server_player.kick_view_pitch
			target_kick_flip_direction = server_player.kick_flip_direction
			target_dropkick_tilt_input = server_player.dropkick_tilt_input
			target_kick_guidance_direction = (
				server_player.kick_guidance_direction
			)
			target_kick_guidance_weight = server_player.kick_guidance_weight
			target_kick_intensity = server_player.kick_intensity
			target_landing_sequence = server_player.landing_sequence
			target_landing_impact_strength = (
				server_player.landing_impact_strength
			)
			target_body_impact_sequence = server_player.body_impact_sequence
			target_body_impact_strength = server_player.body_impact_strength
			target_body_impact_direction = server_player.body_impact_direction
			target_body_impact_contact_side = (
				server_player.body_impact_contact_side
			)
			target_body_impact_clock = server_player.body_impact_clock
			target_ragdoll_active = server_player.ragdoll_active
			target_trip_sequence = server_player.trip_sequence
			target_trip_direction = server_player.trip_direction
			target_stamina_ratio = clampf(
				server_player.stamina / maxf(ServerPlayer.MAX_STAMINA, 0.001),
				0.0,
				1.0
			)
			target_sprint_exhausted = server_player.sprint_exhausted
			target_plasma_cutter_available = (
				server_player.get_plasma_cutter_definition() != null
			)
			target_plasma_cutter_heat_ratio = server_player.plasma_cutter_heat_ratio
			target_plasma_cutter_overheated = server_player.plasma_cutter_overheated
			target_plasma_cutter_active = server_player.plasma_cutter_active
			target_plasma_cutter_has_hit = server_player.plasma_cutter_has_hit
			target_plasma_cutter_hit_position = server_player.plasma_cutter_hit_position
			var cutter := server_player.get_plasma_cutter_definition()
			if cutter != null:
				target_plasma_cutter_range_meters = float(cutter.get("range_meters"))
				target_plasma_cutter_kerf_millimeters = float(cutter.get("cut_radius")) * 2000.0
				target_plasma_cutter_cut_depth_millimeters = float(cutter.get("cut_depth")) * 1000.0
				target_plasma_cutter_continuous_duty_seconds = 1.0 / maxf(float(cutter.get("heat_per_second")), 0.01)
				target_plasma_cutter_full_cool_seconds = 1.0 / maxf(float(cutter.get("cooling_per_second")), 0.01)
			gait_initialized = true
			_update_edit_aim_visual()

			if is_local_player:
				rotation.y = look_yaw
				camera_pivot.rotation.x = _resolved_camera_pitch()
				update_headbob(delta)
			else:
				rotation.y = server_player.rotation.y
			_update_flip_presentation(delta)
			_update_procedural_legs(delta, server_player)
			_predict_local_footstep()
			_update_character_pose(delta)
			_sync_trip_presentation(delta)
			_update_trip_camera(delta)
			_update_plasma_cutter_presentation(delta)

			return

	_update_edit_aim_visual()
	time_since_last_state += delta
	var extrapolation_time := minf(
		time_since_last_state,
		MAX_EXTRAPOLATION_TIME
	)
	var predicted_position := (
		target_position
		+ target_velocity * extrapolation_time
	)
	var weight := clampf(INTERP_SPEED * delta, 0.0, 1.0)

	# Follow the reported velocity immediately, then smooth only the residual
	# snapshot error. This prevents the proxy from permanently trailing.
	global_position += target_velocity * delta
	global_position = global_position.lerp(predicted_position, weight)

	if is_local_player:
		rotation.y = look_yaw
		camera_pivot.rotation.x = _resolved_camera_pitch()
		update_headbob(delta)
	else:
		rotation.y = lerp_angle(
			rotation.y,
			target_rotation.y,
			weight
		)
	_update_flip_presentation(delta)
	_update_procedural_legs(delta)
	_predict_local_footstep()
	_update_character_pose(delta)
	_sync_trip_presentation(delta)
	_update_trip_camera(delta)
	_update_plasma_cutter_presentation(delta)


func _update_flip_presentation(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	var sequence_changed := presented_flip_sequence != target_flip_sequence
	if (
		sequence_changed
		and not local_flip_prediction_active
		and not target_flip_active
		and target_flip_phase >= 0.999
	):
		# A late observer may first learn about a flip after it has completed. TAU is the identity pose;
		# replaying that historical cycle is both misleading and the source of the old reverse flip.
		presented_flip_sequence = target_flip_sequence
		completed_visual_flip_sequence = target_flip_sequence
		visual_flip_direction = 0
		visual_flip_phase = 0.0
		visual_flip_angle = 0.0
		_apply_body_visual_rotation()
		return
	var authoritative_arrived := (
		target_flip_sequence > local_flip_prediction_base_sequence
	)
	if local_flip_prediction_active and authoritative_arrived:
		local_flip_prediction_active = false
	elif (
		local_flip_prediction_active
		and target_jump_sequence > local_flip_prediction_base_jump_sequence
		and target_flip_sequence == local_flip_prediction_base_sequence
	):
		# The jump was accepted but authority rejected the flip gate. Return the provisional pose instead
		# of letting an untrusted client flick become a cosmetic flip on that client alone.
		local_flip_prediction_active = false
		visual_flip_direction = 0
		visual_flip_phase = 0.0
		visual_flip_angle = 0.0

	var desired_direction := 0
	var desired_phase := 0.0
	if local_flip_prediction_active:
		local_flip_prediction_elapsed = minf(
			local_flip_prediction_elapsed + safe_delta,
			ServerPlayer.FLIP_DURATION_SECONDS
		)
		desired_direction = visual_flip_direction
		desired_phase = clampf(
			local_flip_prediction_elapsed
			/ maxf(ServerPlayer.FLIP_DURATION_SECONDS, 0.001),
			0.0,
			1.0
		)
	elif target_flip_active:
		desired_direction = target_flip_direction
		desired_phase = target_flip_phase
		if not multiplayer.is_server():
			desired_phase = clampf(
				target_flip_phase
				+ minf(time_since_last_state, MAX_EXTRAPOLATION_TIME)
				/ maxf(ServerPlayer.FLIP_DURATION_SECONDS, 0.001),
				0.0,
				1.0
			)
	elif (
		target_flip_direction != 0
		and target_flip_phase >= 0.999
		and completed_visual_flip_sequence != target_flip_sequence
	):
		# Finish the currently observed cycle in its original direction. Never interpolate a normalized
		# phase from one back to zero: that is a complete reverse rotation, not a reset.
		desired_direction = target_flip_direction
		desired_phase = 1.0

	if sequence_changed:
		presented_flip_sequence = target_flip_sequence
		if desired_direction != 0:
			visual_flip_direction = desired_direction
		if not local_flip_prediction_active:
			visual_flip_phase = maxf(visual_flip_phase, desired_phase)
	if desired_direction != 0:
		visual_flip_direction = desired_direction
	var response := 1.0 - exp(-FLIP_VISUAL_RESPONSE_HZ * safe_delta)
	visual_flip_phase = lerpf(visual_flip_phase, desired_phase, response)
	if (
		not local_flip_prediction_active
		and not target_flip_active
		and desired_direction != 0
		and desired_phase >= 0.999
		and visual_flip_phase >= 0.995
	):
		completed_visual_flip_sequence = target_flip_sequence
		visual_flip_direction = 0
		visual_flip_phase = 0.0
	if desired_direction == 0 and visual_flip_phase <= 0.001:
		visual_flip_direction = 0
		visual_flip_phase = 0.0
	visual_flip_angle = (
		float(visual_flip_direction) * visual_flip_phase * TAU
	)
	_apply_body_visual_rotation()


func _apply_body_visual_rotation() -> void:
	if body_visual == null:
		return
	var procedural_root := character_pose.body_rotation
	body_visual.rotation = Vector3(
		visual_flip_angle + procedural_root.x,
		procedural_root.y,
		procedural_root.z
	)


func _sync_trip_presentation(delta := 0.0) -> void:
	if player_ragdoll == null or body_visual == null:
		return
	if target_ragdoll_active:
		if is_local_player and local_wrist_interface_open:
			_set_wrist_interface_open(false, false)
		if (
			not player_ragdoll.is_active()
			or presented_trip_sequence != target_trip_sequence
		):
			presented_trip_sequence = target_trip_sequence
			_rearm_gait_after_full_body_interruption()
			player_ragdoll.start_ragdoll(
				_ragdoll_source_visuals(),
				target_velocity,
				target_trip_direction,
				character_skin,
				is_local_player
			)
			_sync_backpack_ragdoll_mount(true)
			_update_held_item_mount()
		player_ragdoll.synchronize_authoritative_torso(
			global_position + PlayerRagdoll3D.TORSO_OFFSET_FROM_PLAYER,
			target_velocity,
			delta
		)
		body_visual.visible = false
		return
	if player_ragdoll.is_active():
		_rearm_gait_after_full_body_interruption()
		_sync_backpack_ragdoll_mount(false)
		player_ragdoll.stop_ragdoll()
		_update_held_item_mount()
	body_visual.visible = true


func _rearm_gait_after_full_body_interruption() -> void:
	var authoritative_cycle := maxf(target_gait_cycle, 0.0)
	visual_gait_cycle = authoritative_cycle
	last_predicted_gait_step_sequence = floori(authoritative_cycle)
	gait_initialized = true
	local_locomotion_prediction_initialized = false
	local_predicted_horizontal_velocity = Vector2.ZERO
	local_predicted_horizontal_speed = 0.0
	local_sprint_speed_ramp_elapsed = 0.0
	local_recovery_gait = PlayerGait.new()
	local_recovery_gait.set_expression_identity(player_id)
	if procedural_leg_rig != null:
		procedural_leg_rig.reset_contacts()


func _sync_backpack_ragdoll_mount(use_ragdoll_skin: bool) -> void:
	var visual := equipment_visuals.get(
		PlayerInventoryRules.BACKPACK_SLOT
	) as Node3D
	if not is_instance_valid(visual):
		return
	var target_mount: Node3D
	if use_ragdoll_skin and player_ragdoll != null:
		var ragdoll_skin: PlayerCharacterSkin = (
			player_ragdoll.get_authored_skin()
		)
		if ragdoll_skin != null and ragdoll_skin.is_usable():
			target_mount = ragdoll_skin.get_backpack_mount()
	elif character_skin != null and character_skin.is_usable():
		target_mount = character_skin.get_backpack_mount()
	else:
		target_mount = backpack_mount
	if target_mount != null and visual.get_parent() != target_mount:
		# Both skins expose the same upper-spine mount contract. Keeping the local authored equipment
		# transform makes the actual pack follow the physical torso without making a camera-only copy.
		visual.reparent(target_mount, false)


func _ragdoll_source_visuals() -> Dictionary:
	return {
		&"torso": torso_visual,
		&"head": head_visual,
		&"left_arm": left_arm_visual,
		&"right_arm": right_arm_visual,
		&"left_upper_leg": left_leg_visual.get_node("Upper"),
		&"left_lower_leg": left_leg_visual.get_node("Lower"),
		&"left_foot": left_leg_visual.get_node("Foot"),
		&"right_upper_leg": right_leg_visual.get_node("Upper"),
		&"right_lower_leg": right_leg_visual.get_node("Lower"),
		&"right_foot": right_leg_visual.get_node("Foot"),
	}


func configure_corpse_ragdoll(
	corpse_ragdoll: PlayerRagdoll3D,
	base_velocity: Vector3,
	death_direction: Vector3
) -> bool:
	if corpse_ragdoll == null or body_visual == null:
		return false
	var source_visuals := _ragdoll_source_visuals()
	var source_skin := character_skin
	if player_ragdoll != null and player_ragdoll.is_active():
		# Death now has a short replicated hold. Snapshot the settled physical pose at handoff instead of
		# rebuilding the corpse from the hidden upright procedural body beneath it.
		source_visuals = player_ragdoll.get_body_source_visuals()
		var active_ragdoll_skin: PlayerCharacterSkin = (
			player_ragdoll.get_authored_skin()
		)
		if active_ragdoll_skin != null and active_ragdoll_skin.is_usable():
			source_skin = active_ragdoll_skin
	corpse_ragdoll.set_limb_presence(
		has_left_arm,
		has_right_arm,
		has_left_leg,
		has_right_leg
	)
	corpse_ragdoll.start_ragdoll(
		source_visuals,
		base_velocity,
		death_direction,
		source_skin,
		false
	)
	return true


func _update_trip_camera(delta: float) -> void:
	if not is_local_player:
		return
	if player_ragdoll != null:
		player_ragdoll.set_local_view(true)
	audio_listener.position = audio_listener_rest_position
	var target_weight := 1.0 if target_ragdoll_active else 0.0
	var blend := 1.0 - exp(
		-maxf(delta, 0.0) * TRIP_CAMERA_BLEND_SPEED
	)
	trip_camera_weight = lerpf(trip_camera_weight, target_weight, blend)
	if player_ragdoll != null and player_ragdoll.is_active():
		ragdoll_camera_world_position = player_ragdoll.get_head_world_position()
		var physical_up: Vector3 = player_ragdoll.get_head_world_up()
		var view_basis := Basis(Vector3.UP, look_yaw)
		var target_roll := clampf(
			-asin(clampf(physical_up.dot(view_basis.x), -1.0, 1.0)),
			-TRIP_CAMERA_MAX_ROLL,
			TRIP_CAMERA_MAX_ROLL
		)
		var target_pitch := clampf(
			asin(clampf(physical_up.dot(-view_basis.z), -1.0, 1.0)) * 0.45,
			-TRIP_CAMERA_MAX_PITCH_INFLUENCE,
			TRIP_CAMERA_MAX_PITCH_INFLUENCE
		)
		var orientation_weight := 1.0 - exp(
			-maxf(delta, 0.0) * TRIP_CAMERA_ORIENTATION_SPEED
		)
		ragdoll_camera_roll = lerp_angle(
			ragdoll_camera_roll,
			target_roll,
			orientation_weight
		)
		ragdoll_camera_pitch = lerp_angle(
			ragdoll_camera_pitch,
			target_pitch,
			orientation_weight
		)
	var regular_camera_world_position := camera_pivot.global_position
	var regular_listener_world_position := audio_listener.global_position
	camera_pivot.global_position = regular_camera_world_position.lerp(
		ragdoll_camera_world_position,
		trip_camera_weight
	)
	audio_listener.global_position = regular_listener_world_position.lerp(
		ragdoll_camera_world_position,
		trip_camera_weight
	)
	camera_pivot.rotation.x = (
		_resolved_camera_pitch()
		+ character_pose.camera_rotation.x * (1.0 - trip_camera_weight)
		+ visual_flip_angle * (1.0 - trip_camera_weight)
		+ ragdoll_camera_pitch * trip_camera_weight
	)
	camera_pivot.rotation.y = (
		character_pose.camera_rotation.y * (1.0 - trip_camera_weight)
	)
	camera_pivot.rotation.z = (
		character_pose.camera_rotation.z * (1.0 - trip_camera_weight)
		+ ragdoll_camera_roll * trip_camera_weight
	)


func _update_procedural_legs(
	delta: float,
	server_player: ServerPlayer = null
) -> void:
	if procedural_leg_rig == null:
		return
	if is_instance_valid(server_player):
		procedural_leg_rig.set_query_exclusion_rid(server_player.get_rid())
	var recovery_weight := (
		resolved_gait_momentum_recovery
		if is_local_player
		else target_gait_momentum_recovery
	)
	var gait_cycle := target_gait_cycle
	if is_local_player and gait_initialized:
		gait_cycle = visual_gait_cycle
	elif target_gait_active:
		gait_cycle += (
			PlayerGait.get_effective_gait_speed(
				Vector2(target_velocity.x, target_velocity.z).length(),
				target_gait_momentum_recovery
			)
			/ maxf(
				target_gait_stride_distance,
				PlayerGait.MINIMUM_STRIDE_DISTANCE
			)
			* time_since_last_state
		)
	var presentation_velocity := target_velocity
	if is_local_player and local_locomotion_prediction_initialized:
		presentation_velocity = global_basis * Vector3(
			local_predicted_horizontal_velocity.x,
			0.0,
			local_predicted_horizontal_velocity.y
		)
	procedural_leg_rig.update_pose(
		delta,
		presentation_velocity,
		target_on_floor,
		gait_cycle,
		target_gait_active,
		target_jump_sequence,
		target_landing_sequence,
		target_landing_impact_strength,
		recovery_weight,
		target_kick_sequence,
		target_kick_side,
		_resolved_kick_phase(),
		_resolved_kick_direction(),
		target_kick_intensity,
		target_kick_active,
		target_kick_style
	)
	resolved_pose_gait_cycle = gait_cycle


func get_suggested_kick_side() -> int:
	if procedural_leg_rig == null:
		return -1
	return procedural_leg_rig.suggest_kick_side(
		-global_basis.z,
		resolved_pose_gait_cycle
	)


func _resolved_kick_phase() -> float:
	if target_kick_sequence <= 0:
		return 1.0
	var presentation_clock := target_expression_clock
	if not multiplayer.is_server():
		presentation_clock += time_since_last_state
	if target_kick_clock >= 0.0 and is_finite(target_kick_clock):
		var pose_duration := (
			ServerPlayer.DROP_KICK_POSE_BUILD_SECONDS
			if target_kick_style == ServerPlayer.KickStyle.DROP
			else ServerPlayer.KICK_DURATION_SECONDS
		)
		return clampf(
			(presentation_clock - target_kick_clock)
			/ maxf(pose_duration, 0.001),
			0.0,
			1.0
		)
	return target_kick_phase


func _resolved_kick_direction() -> Vector3:
	if target_kick_sequence <= 0:
		return target_kick_direction
	return ServerPlayer.apply_kick_guidance(
		ServerPlayer.kick_direction_from_view(
			target_kick_view_yaw,
			target_kick_view_pitch,
			target_kick_flip_direction,
			visual_flip_phase if target_kick_flip_direction != 0 else 0.0
		),
		target_kick_guidance_direction,
		target_kick_guidance_weight
	)


func _sync_body_impact_presentation() -> void:
	if presented_body_impact_sequence == target_body_impact_sequence:
		return
	presented_body_impact_sequence = target_body_impact_sequence
	if target_body_impact_sequence <= 0 or target_body_impact_strength <= 0.0:
		return
	if (
		not is_finite(target_body_impact_clock)
		or target_body_impact_clock < 0.0
		or target_expression_clock - target_body_impact_clock
		> BODY_IMPACT_REPLAY_WINDOW_SECONDS
	):
		return
	var local_reaction := (
		global_basis.inverse() * target_body_impact_direction
	)
	character_pose.apply_body_impact(
		local_reaction,
		target_body_impact_strength,
		target_body_impact_contact_side
	)


func _update_character_pose(delta: float) -> void:
	# The authored local body is visible in first person, so it must raise its real arm just like a
	# remote body. WristTerminalPresentation follows that wrist and supplies only the live device UI.
	var action_weight := smoothstep(0.0, 1.0, wrist_pose_weight)
	var fieldlink_on_left := has_left_arm
	character_pose.set_action_pose(
		FIELDLINK_POSE,
		action_weight,
		fieldlink_on_left,
		not fieldlink_on_left and has_right_arm
	)
	character_pose.set_low_priority_kick_pose(
		target_kick_side,
		_resolved_kick_phase(),
		target_kick_intensity,
		target_kick_style,
		target_kick_sequence,
		target_kick_active,
		target_dropkick_tilt_input
	)
	_sync_body_impact_presentation()
	var expression_clock := target_expression_clock
	if not multiplayer.is_server():
		expression_clock += time_since_last_state
	_update_ocular_expression(delta, expression_clock)
	var pose_movement_weight := headbob_weight
	var pose_run_weight := headbob_run_weight
	var recovery_weight := (
		resolved_gait_momentum_recovery
		if is_local_player
		else target_gait_momentum_recovery
	)
	if not is_local_player:
		pose_movement_weight = (
			1.0
			if target_gait_active and target_on_floor and not target_ragdoll_active
			else 0.0
		)
		pose_run_weight = clampf(
			inverse_lerp(
				PlayerGait.WALK_STEP_DISTANCE_RANGE.y,
				PlayerGait.RUN_STEP_DISTANCE_RANGE.x,
				target_gait_stride_distance
			),
			0.0,
			1.0
		)
		pose_run_weight = maxf(
			pose_run_weight,
			recovery_weight * 0.78
		)
	var local_velocity := global_basis.inverse() * target_velocity
	if is_local_player and local_locomotion_prediction_initialized:
		local_velocity = Vector3(
			local_predicted_horizontal_velocity.x,
			0.0,
			local_predicted_horizontal_velocity.y
		)
	character_pose.update(
		delta,
		expression_clock,
		resolved_pose_gait_cycle,
		pose_movement_weight,
		pose_run_weight,
		1.0 - target_stamina_ratio,
		local_velocity,
		target_on_floor,
		target_ragdoll_active,
		procedural_leg_rig,
		has_left_arm,
		has_right_arm,
		has_left_leg,
		has_right_leg,
		recovery_weight
	)
	# BodyVisual owns the complete authored character, including the procedural legs. Applying the
	# dropkick root pose here makes the pelvis and legs recline with the torso while preserving the
	# separately controlled first-person camera and the full-cycle flip rotation.
	_apply_body_visual_rotation()
	# The old camera-only PBD rig used this heavy-arm spring directly. Feed the same motion into the
	# authored skeleton now: the real shoulder, forearm, equipped mesh, display, and hit surface all
	# inherit one physical response instead of leaving the PSX arm unnaturally pinned in place.
	var hold_motion_active := wrist_pose_weight > 0.0001
	if hold_motion_active:
		fieldlink_hold_motion.set_gait_input(
			character_pose.camera_position,
			pose_movement_weight,
			resolved_pose_gait_cycle,
			pose_run_weight
		)
		fieldlink_hold_motion.set_endurance_spent_ratio(
			1.0 - target_stamina_ratio
		)
		fieldlink_hold_motion.set_lateral_motion_ratio(
			clampf(
				local_velocity.x / maxf(ServerPlayer.RUN_SPEED, 0.001),
				-1.0,
				1.0
			)
		)
		if not fieldlink_hold_motion_active:
			fieldlink_hold_motion.synchronize_lateral_motion()
		fieldlink_hold_motion.advance(delta)
	fieldlink_hold_motion_active = hold_motion_active
	upper_body_pose.position = character_pose.upper_body_position
	upper_body_pose.rotation = character_pose.upper_body_rotation
	head_visual.position = Vector3(0.0, 0.78, 0.0) + character_pose.head_position
	head_visual.rotation = character_pose.head_rotation
	_apply_remote_arm_pose(
		left_arm_visual,
		LEFT_ARM_REST_POSITION,
		LEFT_SHOULDER_POSITION,
		character_pose.left_arm_rotation,
		1.0 if has_left_arm else 0.0
	)
	_apply_remote_arm_pose(
		right_arm_visual,
		RIGHT_ARM_REST_POSITION,
		RIGHT_SHOULDER_POSITION,
		character_pose.right_arm_rotation,
		1.0 if has_right_arm else 0.0
	)
	if character_skin != null and character_skin.is_usable():
		var desired_fieldlink_pitch := WRIST_LOOK_PITCH
		if is_local_player and wrist_mouse_look_owns_pitch:
			desired_fieldlink_pitch = _focused_fieldlink_pose_pitch(
				_resolved_camera_pitch()
			)
		elif not is_local_player:
			desired_fieldlink_pitch = _focused_fieldlink_pose_pitch(
				target_look_pitch
			)
		var fieldlink_pitch_response := (
			1.0
			- exp(
				-FIELDLINK_POSE_PITCH_RESPONSE_HZ
				* clampf(delta, 0.0, 0.1)
			)
		)
		fieldlink_pose_pitch = lerp_angle(
			fieldlink_pose_pitch,
			desired_fieldlink_pitch,
			fieldlink_pitch_response
		)
		var fieldlink_view_basis := (
			global_basis.orthonormalized()
			* Basis.from_euler(Vector3(fieldlink_pose_pitch, 0.0, 0.0))
			* Basis.from_euler(
				fieldlink_hold_motion.rotation_offset
				* FIELDLINK_HOLD_ROTATION_SCALE
			)
		).orthonormalized()
		character_skin.sync_from_procedural_pose(
			procedural_leg_rig,
			character_pose,
			wrist_pose_weight,
			has_left_arm,
			fieldlink_view_basis,
			fieldlink_hold_motion.position_offset
			* FIELDLINK_HOLD_POSITION_SCALE
		)
	if is_local_player:
		if character_skin != null and character_skin.is_usable():
			camera_pivot_rest_position = to_local(
				character_skin.get_camera_mount().global_position
			)
			audio_listener_rest_position = camera_pivot_rest_position
			audio_listener.position = audio_listener_rest_position
		camera_pivot.position = camera_pivot_rest_position + character_pose.camera_position


func _sync_character_appearance() -> void:
	if (
		character_skin == null
		or torso_visual == null
		or head_visual == null
		or left_arm_visual == null
		or right_arm_visual == null
		or procedural_leg_rig == null
	):
		return
	var uses_authored_skin := character_skin.is_usable()
	torso_visual.visible = not uses_authored_skin
	head_visual.visible = not uses_authored_skin
	left_arm_visual.visible = has_left_arm and not uses_authored_skin
	right_arm_visual.visible = has_right_arm and not uses_authored_skin
	procedural_leg_rig.visible = not uses_authored_skin
	character_skin.visible = uses_authored_skin
	character_skin.set_local_view(is_local_player)
	character_skin.set_limb_presence(
		has_left_arm,
		has_right_arm,
		has_left_leg,
		has_right_leg
	)
	_reparent_equipment_visuals()
	_reparent_held_item_visual()
	_sync_local_wrist_presentation_mount()


func _sync_local_wrist_presentation_mount() -> void:
	var wrist_visual := equipment_visuals.get(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	) as Node3D
	_sync_plasma_cutter_emitter()
	if wrist_presentation == null:
		return
	wrist_presentation.bind_equipped_visual(wrist_visual)
	var mount: Node3D
	if character_skin != null and character_skin.is_usable():
		if has_left_arm:
			mount = character_skin.get_wrist_mount(true)
		elif has_right_arm:
			mount = character_skin.get_wrist_mount(false)
	wrist_presentation.bind_wrist_mount(mount)


func _update_ocular_expression(delta: float, expression_clock: float) -> void:
	var eye_visual := equipment_visuals.get(
		PlayerInventoryRules.EYES_SLOT
	) as OcularExpressionVisual
	if not is_instance_valid(eye_visual):
		character_pose.set_attention_pose(Vector3.ZERO, 0.0)
		return

	var eye_origin := eyes_mount.global_position
	var target_world := eye_origin - upper_body_pose.global_basis.z * 4.0
	var attention_weight := 0.20
	var device_focus := false
	if target_wrist_interface_open and has_equipped_wrist_device():
		var wrist_mount := left_wrist_mount if has_left_arm else right_wrist_mount
		if wrist_mount != null:
			target_world = wrist_mount.global_position
			attention_weight = 1.0
			device_focus = true
	else:
		var social_target := _resolve_social_gaze_target(expression_clock)
		if social_target != null and social_target.head_visual != null:
			target_world = social_target.head_visual.global_position
			attention_weight = 0.88

	var local_target := upper_body_pose.global_basis.inverse() * (
		target_world - eye_origin
	)
	ocular_expression.update(
		delta,
		expression_clock,
		local_target,
		attention_weight,
		device_focus,
		1.0 - target_stamina_ratio
	)
	character_pose.set_attention_pose(
		ocular_expression.head_rotation,
		attention_weight
	)
	eye_visual.apply_ocular_expression(
		ocular_expression.left_pupil_offset,
		ocular_expression.right_pupil_offset,
		ocular_expression.pupil_scale,
		ocular_expression.left_lid_openness,
		ocular_expression.right_lid_openness,
		ocular_expression.left_lid_tilt,
		ocular_expression.right_lid_tilt
	)


func _resolve_social_gaze_target(expression_clock: float) -> PlayerProxy:
	var client := get_node_or_null("/root/Client")
	if client == null:
		return null
	var proxies_value: Variant = client.get("player_proxys_by_player_id")
	if not proxies_value is Dictionary:
		return null
	var proxies: Dictionary = proxies_value
	var epoch := floori(maxf(expression_clock, 0.0) / SOCIAL_GAZE_EPOCH_SECONDS)
	if epoch != ocular_social_epoch:
		ocular_social_epoch = epoch
		ocular_social_target_player_id = -1
		var engagement := ExpressionDeterminism.ratio(
			(absi(player_id) + 1) * 65537 + epoch * 8191
		)
		if engagement <= 1.0 - SOCIAL_GAZE_ENGAGEMENT_CHANCE:
			return null
		var best_score := INF
		var forward := -global_basis.z
		for candidate_id_value: Variant in proxies:
			var candidate_id := int(candidate_id_value)
			if candidate_id == player_id:
				continue
			var candidate := proxies.get(candidate_id_value) as PlayerProxy
			if (
				candidate == null
				or candidate.target_faction_id != target_faction_id
				or candidate.target_ragdoll_active
			):
				continue
			var offset := candidate.global_position - global_position
			var distance_squared := offset.length_squared()
			if (
				distance_squared < 0.25
				or distance_squared > SOCIAL_GAZE_RANGE_METERS * SOCIAL_GAZE_RANGE_METERS
			):
				continue
			var distance := sqrt(distance_squared)
			var facing := forward.dot(offset / distance)
			if facing < -0.15:
				continue
			var score := distance * (1.18 - maxf(facing, 0.0) * 0.34)
			if score < best_score:
				best_score = score
				ocular_social_target_player_id = candidate_id

	if ocular_social_target_player_id < 0:
		return null
	var target := proxies.get(ocular_social_target_player_id) as PlayerProxy
	if (
		target == null
		or target.target_faction_id != target_faction_id
		or target.global_position.distance_squared_to(global_position)
		> SOCIAL_GAZE_RANGE_METERS * SOCIAL_GAZE_RANGE_METERS
	):
		ocular_social_target_player_id = -1
		return null
	return target
func _create_edit_aim_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = EDIT_AIM_MARKER_COLOR
	return material


func _update_edit_aim_visual() -> void:
	edit_aim_hit.visible = target_edit_aim_active
	if not target_edit_aim_active:
		return

	var hit_material := edit_aim_hit.material_override as StandardMaterial3D
	if hit_material != null:
		hit_material.albedo_color = EDIT_AIM_MARKER_COLOR
	edit_aim_hit.global_position = target_edit_aim_hit
