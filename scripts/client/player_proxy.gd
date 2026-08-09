extends Node3D
class_name PlayerProxy

const INTERP_SPEED := 12.0
const MAX_EXTRAPOLATION_TIME := 0.25
const WALK_BOB_FREQUENCY := 10.0
const RUN_BOB_FREQUENCY := 15.0
const IDLE_BOB_FREQUENCY := 1.5

const WALK_BOB_VERTICAL := 0.045
const WALK_BOB_HORIZONTAL := 0.025

const RUN_BOB_VERTICAL := 0.075
const RUN_BOB_HORIZONTAL := 0.045

const HEADBOB_BLEND_SPEED := 10.0
const RUN_SPEED_THRESHOLD := 12.0
const EDIT_AIM_MARKER_COLOR := Color(0.16, 0.86, 0.7, 0.2)
const MAX_LOOK_PITCH_DEGREES := 85.0
const MOVEMENT_SPEED_THRESHOLD := 0.2
const IDLE_HEADBOB_WEIGHT := 0.5
const HELD_ITEM_SIDE_OFFSET := 0.43
const HELD_ITEM_ROLL := 0.08
const FIRST_PERSON_ITEM_SIDE_OFFSET := 0.22

#######################################################
# Presents replicated player movement, body parts, equipment, held items, HUD, camera motion,
# and ocular effects.
#######################################################

@onready var camera_pivot: Node3D = $HeadPivot
@onready var camera: Camera3D = $HeadPivot/Camera3D
@onready var left_arm_visual: MeshInstance3D = $BodyVisual/LeftArm
@onready var right_arm_visual: MeshInstance3D = $BodyVisual/RightArm
@onready var left_leg_visual: MeshInstance3D = $BodyVisual/LeftLeg
@onready var right_leg_visual: MeshInstance3D = $BodyVisual/RightLeg
@onready var edit_aim_hit: MeshInstance3D = $EditAimHit
@onready var backpack_mount: Node3D = $BodyVisual/BackpackMount
@onready var eyes_mount: Node3D = $BodyVisual/EyesMount
@onready var held_item_mount: Node3D = $BodyVisual/HeldItemMount
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

var headbob_time := 0.0
var headbob_weight := 0.0
var camera_pivot_rest_position: Vector3

var target_on_floor := false

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

func _ready() -> void:
	target_position = global_position
	target_rotation = global_rotation

	camera_pivot_rest_position = camera_pivot.position
	edit_aim_hit.material_override = _create_edit_aim_material()
	edit_aim_hit.visible = false

	set_local_player(is_local_player)

func _input(event: InputEvent) -> void:
	if not is_local_player:
		return

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		grab_rotation_input = Vector2.ZERO
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if (
			event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
		):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion:
		if (
			Input.is_action_pressed("grab")
			and Input.is_action_pressed("rotate_grabbed")
		):
			grab_rotation_input += event.relative
			return

		look_yaw -= event.relative.x * mouse_sensitivity
		look_pitch -= event.relative.y * mouse_sensitivity
		look_pitch = clamp(
			look_pitch,
			deg_to_rad(-MAX_LOOK_PITCH_DEGREES),
			deg_to_rad(MAX_LOOK_PITCH_DEGREES)
		)


func consume_grab_rotation_input() -> Vector2:
	var result := grab_rotation_input
	grab_rotation_input = Vector2.ZERO
	return result

func apply_server_state(state: Dictionary) -> void:
	player_id = state.get("player_id", -1)

	target_position = state.get("pos", global_position)
	target_rotation = state.get("rot", global_rotation)
	target_velocity = state.get("vel", Vector3.ZERO)
	time_since_last_state = 0.0
	
	target_on_floor = state.get("on_floor", false)
	target_edit_aim_active = state.get("edit_aim_active", false)
	target_edit_aim_origin = state.get(
		"edit_aim_origin",
		Vector3.ZERO
	)
	target_edit_aim_hit = state.get("edit_aim_hit", Vector3.ZERO)
	target_edit_aim_color = state.get(
		"edit_aim_color",
		target_edit_aim_color
	)
	_apply_limb_state(state.get("limbs", {}))
	_apply_player_system_state(state)


func _apply_player_system_state(state: Dictionary) -> void:
	target_player_state = state.duplicate(true)
	var inventory: Dictionary = state.get("inventory", {})
	var equipment: Dictionary = inventory.get("equipment", {})
	_apply_equipment_state(equipment)
	_apply_held_item_state(inventory)

	if inventory_hud != null:
		inventory_hud.apply_player_state(state)
	if vision_effect != null:
		var eye_entry: Dictionary = equipment.get(
			PlayerInventoryRules.EYES_SLOT,
			{}
		)
		var has_eyes := vision_effect.set_eye_entry(eye_entry)
		var distortion_state: Dictionary = state.get(
			"vision_distortion",
			{}
		)
		vision_effect.apply_distortion_state(distortion_state)
		if inventory_hud != null:
			inventory_hud.visible = is_local_player and has_eyes


func _apply_equipment_state(equipment: Dictionary) -> void:
	var next_paths: Dictionary = {}
	for slot_value: Variant in equipment.keys():
		var slot := str(slot_value)
		var entry: Dictionary = equipment[slot_value]
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


func _get_equipment_mount(slot: String) -> Node3D:
	match slot:
		PlayerInventoryRules.BACKPACK_SLOT:
			return backpack_mount
		PlayerInventoryRules.EYES_SLOT:
			return eyes_mount
	return null


func _update_local_equipment_visibility() -> void:
	var eye_visual := equipment_visuals.get(
		PlayerInventoryRules.EYES_SLOT
	) as Node3D
	if is_instance_valid(eye_visual):
		eye_visual.visible = not is_local_player


func _apply_held_item_state(inventory: Dictionary) -> void:
	var entries: Array = inventory.get("entries", [])
	var selected_slot := int(inventory.get("selected_slot", 0))
	var entry: Dictionary = (
		entries[selected_slot]
		if selected_slot >= 0 and selected_slot < entries.size()
		else {}
	)
	var definition_path := str(entry.get("definition_path", ""))
	var state: Dictionary = entry.get("instance_state", {})
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
	left_arm_visual.visible = has_left_arm
	right_arm_visual.visible = has_right_arm
	left_leg_visual.visible = limbs.get("left_leg", true)
	right_leg_visual.visible = limbs.get("right_leg", true)
	_update_held_item_mount()


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
		held_item_visual.visible = has_left_arm or has_right_arm
	
func update_headbob(delta: float) -> void:
	var horizontal_speed := Vector2(
		target_velocity.x,
		target_velocity.z
	).length()

	var is_moving := (
		horizontal_speed > MOVEMENT_SPEED_THRESHOLD
		and target_on_floor
	)
	var is_running := horizontal_speed >= RUN_SPEED_THRESHOLD

	var target_weight := 1.0 if is_moving else IDLE_HEADBOB_WEIGHT

	headbob_weight = move_toward(
		headbob_weight,
		target_weight,
		HEADBOB_BLEND_SPEED * delta
	)

	var frequency := IDLE_BOB_FREQUENCY
	if is_moving and is_running:
		frequency = RUN_BOB_FREQUENCY
	elif is_moving:
		frequency = WALK_BOB_FREQUENCY
	
	headbob_time += delta * frequency

	var vertical_amount := (
		RUN_BOB_VERTICAL
		if is_running
		else WALK_BOB_VERTICAL
	)

	var horizontal_amount := (
		RUN_BOB_HORIZONTAL
		if is_running
		else WALK_BOB_HORIZONTAL
	)

	var bob_offset := Vector3(
		cos(headbob_time * 0.5) * horizontal_amount,
		sin(headbob_time) * vertical_amount,
		0.0
	)

	camera_pivot.position = camera_pivot_rest_position + (
		bob_offset * headbob_weight
	)
	
func set_local_player(value: bool) -> void:
	is_local_player = value

	if not is_node_ready():
		return

	camera.current = is_local_player
	interface_layer.visible = is_local_player
	vision_layer.visible = is_local_player

	if is_local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if not target_player_state.is_empty():
			_apply_player_system_state(target_player_state)
	_update_local_equipment_visibility()
	held_item_signature = ""
	_rebuild_held_item_visual()

func _process(delta: float) -> void:
	if is_local_player and vision_effect != null:
		vision_effect.update_view(look_yaw, look_pitch, delta)

	# The host can follow its authoritative CharacterBody3D without any
	# snapshot delay. Joining clients use the extrapolated snapshot below.
	if multiplayer.is_server():
		var server_player := Server.get_server_player(player_id)

		if is_instance_valid(server_player):
			global_position = server_player.global_position
			target_velocity = server_player.velocity
			target_on_floor = server_player.on_floor
			target_edit_aim_active = server_player.edit_aim_active
			target_edit_aim_origin = server_player.edit_aim_origin
			target_edit_aim_hit = server_player.edit_aim_hit
			target_edit_aim_color = server_player.edit_aim_color
			_update_edit_aim_visual()

			if is_local_player:
				rotation.y = look_yaw
				camera_pivot.rotation.x = look_pitch
				update_headbob(delta)
			else:
				rotation.y = server_player.rotation.y

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
		camera_pivot.rotation.x = look_pitch
		update_headbob(delta)
	else:
		rotation.y = lerp_angle(
			rotation.y,
			target_rotation.y,
			weight
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
