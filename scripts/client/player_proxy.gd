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
const HELD_ITEM_SIDE_OFFSET := 0.43
const HELD_ITEM_ROLL := 0.08
const FIRST_PERSON_ITEM_SIDE_OFFSET := 0.22
const WRIST_LOOK_PITCH := deg_to_rad(-24.0)
const WRIST_POSE_BLEND_SPEED := 7.5
const WRIST_REQUEST_GRACE_SECONDS := 0.5
const WRIST_SCANNER_RANGE_METERS := 36.0
const WRIST_SCANNER_REFRESH_SECONDS := 0.2
const WRIST_CONTROL_REFRESH_SECONDS := 0.5
const MOUSE_CAPTURE_TRANSITION_DISCARD_EVENTS := 2
const LEFT_ARM_REST_POSITION := Vector3(-0.47, 0.16, 0.0)
const RIGHT_ARM_REST_POSITION := Vector3(0.47, 0.16, 0.0)
const LEFT_SHOULDER_POSITION := Vector3(-0.47, 0.57, 0.0)
const RIGHT_SHOULDER_POSITION := Vector3(0.47, 0.57, 0.0)
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

#######################################################
# Presents replicated player movement, body parts, equipment, held items, HUD, camera motion,
# and ocular effects.
#######################################################

@onready var camera_pivot: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
@onready var audio_listener: AudioListener3D = $AudioListener3D
@onready var body_visual: Node3D = $BodyVisual
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
@onready var eyes_mount: Node3D = $BodyVisual/UpperBodyPose/EyesMount
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
var gait_initialized := false
var last_predicted_gait_step_sequence := -1
var target_footstep_surface: StringName = PhysicalSurface.CONCRETE
var local_move_input := Vector2.ZERO
var local_run_input := false
var local_predicted_horizontal_speed := 0.0
var target_stamina_ratio := 1.0
var target_expression_clock := 0.0
var resolved_pose_gait_cycle := 0.5
var character_pose := PlayerCharacterPoseController.new()

var target_on_floor := false
var target_jump_sequence := 0
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
var target_velocity: Vector3
var time_since_last_state := 0.0
var target_edit_aim_active := false
var target_edit_aim_origin := Vector3.ZERO
var target_edit_aim_hit := Vector3.ZERO
var target_edit_aim_color := Color(0.2, 0.8, 1.0, 1.0)
var target_player_state: Dictionary = {}
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
var wrist_presentation: WristTerminalPresentation
var remote_wrist_display: Node
var wrist_session_refresh_remaining := 0.0
var wrist_scanner_refresh_remaining := 0.0
var wrist_control_refresh_remaining := 0.0
var wrist_request_grace_remaining := 0.0
var wrist_mouse_look_active := false
var wrist_mouse_look_owns_pitch := false
var captured_mouse_motion_discard_remaining := 0
var local_has_equipped_eyes := true

func _ready() -> void:
	target_position = global_position
	target_rotation = global_rotation

	camera_pivot_rest_position = camera_pivot.position
	audio_listener_rest_position = audio_listener.position
	procedural_leg_rig.set_expression_identity(player_id)
	character_pose.set_expression_identity(player_id)
	edit_aim_hit.material_override = _create_edit_aim_material()
	edit_aim_hit.visible = false
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
					_apply_mouse_look(event.relative)
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

		_apply_mouse_look(event.relative)


func _apply_mouse_look(relative_motion: Vector2) -> void:
	look_yaw -= relative_motion.x * mouse_sensitivity
	look_pitch -= relative_motion.y * mouse_sensitivity
	look_pitch = clampf(
		look_pitch,
		deg_to_rad(-MAX_LOOK_PITCH_DEGREES),
		deg_to_rad(MAX_LOOK_PITCH_DEGREES)
	)


func _consume_capture_transition_motion() -> bool:
	if captured_mouse_motion_discard_remaining <= 0:
		return false
	captured_mouse_motion_discard_remaining -= 1
	return true


func _arm_capture_transition_guard() -> void:
	captured_mouse_motion_discard_remaining = (
		MOUSE_CAPTURE_TRANSITION_DISCARD_EVENTS
	)


func _set_wrist_mouse_look_active(value: bool) -> void:
	var next_value := value and local_wrist_interface_open
	if next_value == wrist_mouse_look_active:
		return
	wrist_mouse_look_active = next_value
	if wrist_mouse_look_active:
		# Until RMB is held, the presentation pose aims the camera down at the
		# device. Hand control to ordinary mouse look from the pitch currently
		# on screen so vertical input is visible immediately instead of being
		# hidden by the pose and appearing as a jump when the device closes.
		look_pitch = camera_pivot.rotation.x
		wrist_mouse_look_owns_pitch = true
		return


func consume_grab_rotation_input() -> Vector2:
	var result := grab_rotation_input
	grab_rotation_input = Vector2.ZERO
	return result

func apply_server_state(state: Dictionary) -> void:
	player_id = SafeVariant.integral_int_or(state.get("player_id", -1), -1)
	if procedural_leg_rig != null:
		procedural_leg_rig.set_expression_identity(player_id)
	character_pose.set_expression_identity(player_id)
	var current_position := global_position if is_inside_tree() else position
	var current_rotation := global_rotation if is_inside_tree() else rotation

	target_position = SafeVariant.vector3_strict_or(
		state.get("pos", current_position), current_position
	)
	target_rotation = SafeVariant.vector3_strict_or(
		state.get("rot", current_rotation), current_rotation
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
	target_player_state = state.duplicate(true)
	var inventory: Dictionary = PlayerInventoryRules.sanitize_public_inventory(
		state.get("inventory", {})
	)
	var equipment: Dictionary = inventory["equipment"]
	_apply_equipment_state(equipment)
	_apply_held_item_state(inventory)
	var server_wrist_open := SafeVariant.strict_bool_or(
		state.get("wrist_interface_open", false),
		false
	)
	var server_wrist_page := FIELDLINK_DISPLAY_STATE.sanitize_page(
		state.get("wrist_display_page", FIELDLINK_DISPLAY_STATE.PAGE_HOME)
	)
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
		inventory_hud.apply_player_state(state)
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
		mount.add_child(visual)
		equipment_visuals[slot] = visual
		equipment_definition_paths[slot] = definition_path

	_update_local_equipment_visibility()
	_sync_remote_wrist_display()


func _get_equipment_mount(slot: String) -> Node3D:
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
		wrist_visual.visible = not is_local_player


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
	var signature := (
		definition_path
		+ "|"
		+ JSON.stringify(state.get("build", {}))
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
	var definition := load(
		held_item_definition_path
	) as GunItemDefinition
	if definition == null:
		return
	var mount := (
		first_person_item_mount
		if is_local_player
		else held_item_mount
	)
	held_item_visual = definition.instantiate_held_visual(
		held_item_state,
		is_local_player
	)
	held_item_visual.name = "HeldGunVisual"
	mount.add_child(held_item_visual)
	_update_held_item_mount()


func _apply_limb_state(limbs: Dictionary) -> void:
	if limbs.is_empty():
		return

	has_left_arm = bool(limbs.get("left_arm", true))
	has_right_arm = bool(limbs.get("right_arm", true))
	has_left_leg = bool(limbs.get("left_leg", true))
	has_right_leg = bool(limbs.get("right_leg", true))
	left_arm_visual.visible = has_left_arm
	right_arm_visual.visible = has_right_arm
	procedural_leg_rig.set_limb_presence(has_left_leg, has_right_leg)
	player_ragdoll.set_limb_presence(
		has_left_arm,
		has_right_arm,
		has_left_leg,
		has_right_leg
	)
	_update_held_item_mount()
	_reparent_wrist_visual()
	if wrist_presentation != null:
		wrist_presentation.set_wrist_side(has_left_arm)


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
	var inventory := PlayerInventoryRules.sanitize_public_inventory(
		target_player_state.get("inventory", {})
	)
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
	)


func _set_wrist_interface_open(
	value: bool,
	notify_server := true
) -> void:
	var next_value := value and _can_use_wrist_device()
	if next_value == local_wrist_interface_open:
		return
	if next_value:
		wrist_mouse_look_owns_pitch = false
	wrist_mouse_look_active = false
	local_wrist_interface_open = next_value
	target_wrist_interface_open = next_value
	if notify_server:
		wrist_request_grace_remaining = WRIST_REQUEST_GRACE_SECONDS
	_ensure_wrist_presentation()
	if wrist_presentation != null:
		wrist_presentation.set_wrist_side(has_left_arm)
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
	camera.add_child(wrist_presentation)
	var client := get_node_or_null("/root/Client")
	if client != null and client.has_method("get_listener_acoustic_intensity"):
		wrist_presentation.set_acoustic_intensity_provider(
			Callable(client, "get_listener_acoustic_intensity")
		)
	wrist_presentation.set_wrist_side(has_left_arm)
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
	if not pose_active and is_zero_approx(wrist_pose_weight):
		wrist_mouse_look_owns_pitch = false
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
		var wish_speed := (
			ServerPlayer.RUN_SPEED if local_run_input else ServerPlayer.WALK_SPEED
		) * input_strength
		var predicted_velocity := ServerPlayer.calculate_horizontal_velocity(
			Vector3(local_predicted_horizontal_speed, 0.0, 0.0),
			Vector3.RIGHT if input_strength > 0.001 else Vector3.ZERO,
			wish_speed,
			true,
			delta
		)
		local_predicted_horizontal_speed = predicted_velocity.length()
		horizontal_speed = local_predicted_horizontal_speed
		stride_distance = PlayerGait.get_stride_distance(local_run_input)
		is_moving = (
			target_on_floor
			and not target_ragdoll_active
			and horizontal_speed * horizontal_speed
			>= PlayerGait.MINIMUM_SPEED_SQUARED
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
			PlayerGait.WALK_STEP_DISTANCE,
			PlayerGait.RUN_STEP_DISTANCE,
			stride_distance
		),
		0.0,
		1.0
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
		horizontal_speed / stride_distance
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
	_predict_local_footstep(is_moving)


func _predict_local_footstep(is_moving: bool) -> void:
	if not is_local_player or not gait_initialized:
		return
	var current_step_sequence := floori(visual_gait_cycle)
	if current_step_sequence < last_predicted_gait_step_sequence:
		last_predicted_gait_step_sequence = current_step_sequence
		return
	if not is_moving or current_step_sequence <= last_predicted_gait_step_sequence:
		return
	# A multi-step correction means a snapshot discontinuity, not several physical impacts. Catch
	# up silently; ordinary one-step crossings are the exact phase shared with the camera bob.
	if current_step_sequence - last_predicted_gait_step_sequence == 1:
		var client := get_node_or_null("/root/Client")
		if client != null and client.has_method("predict_local_player_sound"):
			client.call(
				"predict_local_player_sound",
				PhysicalSurface.footstep_sound_id(target_footstep_surface),
				global_position + Vector3.UP * 0.35,
				{},
				LOCAL_AUDIO_PREDICTION.gait_step_key(current_step_sequence)
			)
	last_predicted_gait_step_sequence = current_step_sequence
	
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

	if is_local_player:
		_arm_capture_transition_guard()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not target_player_state.is_empty():
			_apply_player_system_state(target_player_state)
	else:
		local_wrist_interface_open = false
		wrist_mouse_look_active = false
		wrist_mouse_look_owns_pitch = false
		wrist_request_grace_remaining = 0.0
		if wrist_presentation != null:
			wrist_presentation.set_open(false)
	_update_local_equipment_visibility()
	held_item_signature = ""
	_rebuild_held_item_visual()


func _resolved_camera_pitch() -> float:
	if wrist_mouse_look_owns_pitch:
		return look_pitch
	return lerp_angle(
		look_pitch,
		WRIST_LOOK_PITCH,
		wrist_pose_weight
	)


func _process(delta: float) -> void:
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
			target_expression_clock = server_player.expression_clock
			target_jump_sequence = server_player.jump_sequence
			target_ragdoll_active = server_player.ragdoll_active
			target_trip_sequence = server_player.trip_sequence
			target_trip_direction = server_player.trip_direction
			target_stamina_ratio = clampf(
				server_player.stamina / maxf(ServerPlayer.MAX_STAMINA, 0.001),
				0.0,
				1.0
			)
			gait_initialized = true
			_update_edit_aim_visual()

			if is_local_player:
				rotation.y = look_yaw
				camera_pivot.rotation.x = _resolved_camera_pitch()
				update_headbob(delta)
			else:
				rotation.y = server_player.rotation.y
			_update_procedural_legs(delta, server_player)
			_update_character_pose(delta)
			_sync_trip_presentation(delta)
			_update_trip_camera(delta)

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
	_update_procedural_legs(delta)
	_update_character_pose(delta)
	_sync_trip_presentation(delta)
	_update_trip_camera(delta)


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
			player_ragdoll.start_ragdoll(
				_ragdoll_source_visuals(),
				target_velocity,
				target_trip_direction
			)
			_update_held_item_mount()
		player_ragdoll.synchronize_authoritative_torso(
			global_position + PlayerRagdoll3D.TORSO_OFFSET_FROM_PLAYER,
			target_velocity,
			delta
		)
		body_visual.visible = false
		return
	if player_ragdoll.is_active():
		player_ragdoll.stop_ragdoll()
		_update_held_item_mount()
	body_visual.visible = true


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


func _update_trip_camera(delta: float) -> void:
	if not is_local_player:
		return
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
	var gait_cycle := target_gait_cycle
	if is_local_player and gait_initialized:
		gait_cycle = visual_gait_cycle
	elif target_gait_active:
		gait_cycle += (
			Vector2(target_velocity.x, target_velocity.z).length()
			/ maxf(
				target_gait_stride_distance,
				PlayerGait.MINIMUM_STRIDE_DISTANCE
			)
			* time_since_last_state
		)
	procedural_leg_rig.update_pose(
		delta,
		target_velocity,
		target_on_floor,
		gait_cycle,
		target_gait_active,
		target_jump_sequence
	)
	resolved_pose_gait_cycle = gait_cycle


func _update_character_pose(delta: float) -> void:
	var action_weight := (
		0.0
		if is_local_player
		else smoothstep(0.0, 1.0, wrist_pose_weight)
	)
	var fieldlink_on_left := has_left_arm
	character_pose.set_action_pose(
		FIELDLINK_POSE,
		action_weight,
		fieldlink_on_left,
		not fieldlink_on_left and has_right_arm
	)
	var expression_clock := target_expression_clock
	if not multiplayer.is_server():
		expression_clock += time_since_last_state
	var pose_movement_weight := headbob_weight
	var pose_run_weight := headbob_run_weight
	if not is_local_player:
		pose_movement_weight = (
			1.0
			if target_gait_active and target_on_floor and not target_ragdoll_active
			else 0.0
		)
		pose_run_weight = clampf(
			inverse_lerp(
				PlayerGait.WALK_STEP_DISTANCE,
				PlayerGait.RUN_STEP_DISTANCE,
				target_gait_stride_distance
			),
			0.0,
			1.0
		)
	var local_velocity := global_basis.inverse() * target_velocity
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
		has_right_leg
	)
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
	if is_local_player:
		camera_pivot.position = camera_pivot_rest_position + character_pose.camera_position
		if wrist_presentation != null:
			wrist_presentation.set_motion_input(
				character_pose.camera_position,
				headbob_weight,
				1.0 - target_stamina_ratio,
				resolved_pose_gait_cycle,
				headbob_run_weight
			)


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
