class_name PlayerCharacterSkin
extends Node3D

## Temporary authored skin driven by the permanent procedural character systems. The imported FBX
## contributes only mesh, material, and bind skeleton; contacts, expression, missing limbs, and
## networking remain owned by PlayerProxy and PlayerProceduralLegRig.

const MODEL_FACING_CORRECTION := PI
const EPSILON := 0.000001
const REQUIRED_BONES := [
	&"mixamorig_Hips",
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
	&"mixamorig_Head",
	&"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm",
	&"mixamorig_LeftHand",
	&"mixamorig_RightArm",
	&"mixamorig_RightForeArm",
	&"mixamorig_RightHand",
	&"mixamorig_LeftUpLeg",
	&"mixamorig_LeftLeg",
	&"mixamorig_LeftFoot",
	&"mixamorig_RightUpLeg",
	&"mixamorig_RightLeg",
	&"mixamorig_RightFoot",
]
const SPINE_WEIGHTS := [0.20, 0.32, 0.48]
const SPINE_BONES := [
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
]
const LEFT_UPPER_LEG := &"mixamorig_LeftUpLeg"
const LEFT_LOWER_LEG := &"mixamorig_LeftLeg"
const LEFT_FOOT := &"mixamorig_LeftFoot"
const LEFT_FOREARM := &"mixamorig_LeftForeArm"
const LEFT_HAND := &"mixamorig_LeftHand"
const LEFT_UPPER_ARM := &"mixamorig_LeftArm"
const RIGHT_UPPER_LEG := &"mixamorig_RightUpLeg"
const RIGHT_LOWER_LEG := &"mixamorig_RightLeg"
const RIGHT_FOOT := &"mixamorig_RightFoot"
const RIGHT_FOREARM := &"mixamorig_RightForeArm"
const RIGHT_HAND := &"mixamorig_RightHand"
const RIGHT_UPPER_ARM := &"mixamorig_RightArm"
const UPPER_SPINE := &"mixamorig_Spine2"
const BACK_SURFACE_FROM_SPINE := 0.10
const BACKPACK_MOUNT_DROP := 0.035
const CAMERA_UP_FROM_HEAD := 0.10
# Mixamo's head origin is at the neck/skull base. Three centimetres left the first-person lens in
# the throat column; use the actual face depth so downward view begins over the chest instead of
# looking through the open neck seam left by the locally hidden head.
const CAMERA_FORWARD_FROM_HEAD := 0.085
const FIELDLINK_UPPER_FORWARD_WEIGHT := 0.80
const FIELDLINK_UPPER_UP_WEIGHT := 0.60
const FIELDLINK_UPPER_OUT_WEIGHT := 0.08
const FIELDLINK_EYE_FOCUS_LIFT := 0.032
const FIELDLINK_MOUNT_ROLL := PI * 0.5
const FIELDLINK_FOREARM_SURFACE_OFFSET := 0.055
const FIELDLINK_FOREARM_LENGTH_RATIO := 0.68
const FIELDLINK_HAND_PRONATION := PI
const FIELDLINK_HAND_TWIST := deg_to_rad(12.0)
const FIELDLINK_ELBOW_HOLD_MOTION_INHERITANCE := 0.35
const LOCOMOTION_HAND_WALK_WEIGHT := 0.34
const LOCOMOTION_HAND_RUN_WEIGHT := 0.88
const HELD_HAND_REACH_RATIO := 0.94
const HELD_PISTOL_FORWARD := 0.43
const HELD_RIFLE_FORWARD := 0.29
const HELD_TOOL_FORWARD := 0.40
const HELD_GENERIC_FORWARD := 0.31
# Fallback for skins that predate authored hand anchors. Current player scenes expose editable
# Marker3D grip points instead of relying on this value during ordinary setup.
const DEFAULT_HAND_GRIP_LOCAL_POSITION := Vector3(0.0, 0.125, 0.0)

var player_id := -1
var variant_index := -1
var variant_path := ""
var model_root: Node3D
var skeleton: Skeleton3D
var skin_meshes: Array[MeshInstance3D] = []
var _bone_indices: Dictionary[StringName, int] = {}
var _rest_global_poses: Dictionary[StringName, Transform3D] = {}
var _usable := false
var _local_view := false
var _has_head := true
var _has_left_arm := true
var _has_right_arm := true
var _has_left_leg := true
var _has_right_leg := true
var _backpack_mount: Node3D
var _eyes_mount: Node3D
var _camera_mount: Node3D
var _left_wrist_mount: Node3D
var _right_wrist_mount: Node3D
var _backpack_attachment: BoneAttachment3D
var _left_forearm_attachment: BoneAttachment3D
var _right_forearm_attachment: BoneAttachment3D
var _left_hand_attachment: BoneAttachment3D
var _right_hand_attachment: BoneAttachment3D
var _left_hand_grip_point: Node3D
var _right_hand_grip_point: Node3D
var _left_hand_grip_local_transform := Transform3D(
	Basis.IDENTITY,
	DEFAULT_HAND_GRIP_LOCAL_POSITION
)
var _right_hand_grip_local_transform := Transform3D(
	Basis.IDENTITY,
	DEFAULT_HAND_GRIP_LOCAL_POSITION
)
var _hand_grip_points_captured := false
var _left_leg_solution := LimbKinematics.TwoBoneSolution.new()
var _right_leg_solution := LimbKinematics.TwoBoneSolution.new()
var _left_previous_bend := Vector3.ZERO
var _right_previous_bend := Vector3.ZERO
var _left_upper_leg_length := 0.45
var _left_lower_leg_length := 0.45
var _right_upper_leg_length := 0.45
var _right_lower_leg_length := 0.45
var _left_upper_arm_length := 0.25
var _left_lower_arm_length := 0.25
var _right_upper_arm_length := 0.25
var _right_lower_arm_length := 0.25
var _left_arm_solution := LimbKinematics.TwoBoneSolution.new()
var _right_arm_solution := LimbKinematics.TwoBoneSolution.new()
var _left_previous_arm_bend := Vector3.ZERO
var _right_previous_arm_bend := Vector3.ZERO
var _left_hand_target_solution := LimbKinematics.TwoBoneSolution.new()
var _right_hand_target_solution := LimbKinematics.TwoBoneSolution.new()
var _left_previous_hand_target_bend := Vector3.ZERO
var _right_previous_hand_target_bend := Vector3.ZERO


func _ready() -> void:
	_ensure_mounts()


func set_player_identity(next_player_id: int) -> bool:
	var next_variant_index := (
		PlayerCharacterAppearanceCatalog.variant_index_for_player_id(
			next_player_id
		)
	)
	if (
		_usable
		and next_player_id == player_id
		and next_variant_index == variant_index
	):
		return true
	player_id = next_player_id
	variant_index = next_variant_index
	variant_path = (
		PlayerCharacterAppearanceCatalog.variant_path_for_player_id(
			next_player_id
		)
	)
	return _load_variant()


func is_usable() -> bool:
	return _usable


func get_variant_index() -> int:
	return variant_index


func get_variant_path() -> String:
	return variant_path


func copy_runtime_pose_from(source: PlayerCharacterSkin) -> bool:
	if (
		not _usable
		or skeleton == null
		or source == null
		or not source.is_usable()
		or source.skeleton == null
	):
		return false
	# Both instances use the same authored import contract, so skeleton-global poses can be copied
	# directly. The world root is copied separately so the cosmetic ragdoll starts in precisely the
	# same place as the live skin before its bones become physics-driven.
	global_transform = source.global_transform
	for bone_name: StringName in REQUIRED_BONES:
		var source_index := source.skeleton.find_bone(bone_name)
		var target_index := skeleton.find_bone(bone_name)
		if source_index < 0 or target_index < 0:
			return false
		skeleton.set_bone_global_pose(
			target_index,
			source.skeleton.get_bone_global_pose(source_index)
		)
	skeleton.force_update_all_bone_transforms()
	return true


func get_backpack_mount() -> Node3D:
	_ensure_mounts()
	return _backpack_mount


func get_eyes_mount() -> Node3D:
	_ensure_mounts()
	return _eyes_mount


func get_camera_mount() -> Node3D:
	_ensure_mounts()
	return _camera_mount


func get_wrist_mount(left_side: bool) -> Node3D:
	_ensure_mounts()
	return _left_wrist_mount if left_side else _right_wrist_mount


func get_hand_grip_point(left_side: bool) -> Node3D:
	_ensure_mounts()
	return _left_hand_grip_point if left_side else _right_hand_grip_point


## Compatibility for callers written before hand/item grip points were named explicitly.
func get_hand_item_mount(left_side: bool) -> Node3D:
	return get_hand_grip_point(left_side)


func get_hand_grip_world_position(left_side: bool) -> Vector3:
	if not _usable or skeleton == null:
		return global_position
	var grip_local_transform := (
		_left_hand_grip_local_transform
		if left_side
		else _right_hand_grip_local_transform
	)
	return (
		_bone_world_transform(LEFT_HAND if left_side else RIGHT_HAND)
		* grip_local_transform.origin
	)


func reset_fieldlink_arm_pose_history() -> void:
	# Fieldlink may be raised on the same frame as a large camera swing. Bend continuity is useful
	# while holding the device, but carrying its old hemisphere across a fresh opening can overpower
	# the authored elbow hint and preserve a grotesquely twisted solution.
	_left_previous_arm_bend = Vector3.ZERO
	_right_previous_arm_bend = Vector3.ZERO


## Applies reusable world-space hand targets after the ordinary procedural pose has been synced.
## This is intentionally item-agnostic: instruments, carried props, and future two-handed tools can
## own their grip points without adding another authored arm animation or duplicating the IK solve.
func sync_two_hand_targets(
	left_target_world: Vector3,
	right_target_world: Vector3,
	left_bend_hint_world: Vector3,
	right_bend_hint_world: Vector3,
	weight: float
) -> void:
	if not _usable or skeleton == null:
		return
	var safe_weight := clampf(weight, 0.0, 1.0)
	if safe_weight <= EPSILON:
		_left_previous_hand_target_bend = Vector3.ZERO
		_right_previous_hand_target_bend = Vector3.ZERO
		return
	if _has_left_arm:
		_sync_hand_target(
			true,
			left_target_world,
			left_bend_hint_world,
			safe_weight
		)
	if _has_right_arm:
		_sync_hand_target(
			false,
			right_target_world,
			right_bend_hint_world,
			safe_weight
		)
	skeleton.force_update_all_bone_transforms()
	force_equipment_attachment_update()


## Pulls the actual shared hands into the lower first-person frame while retaining an ordinary
## third-person running silhouette. This is applied to the authored body itself; there is no
## owner-only arm pair. The alternating target comes from the replicated gait clock.
func sync_locomotion_hands(
	gait_cycle: float,
	movement_weight: float,
	run_weight: float
) -> void:
	if not _usable or skeleton == null:
		return
	var moving := clampf(movement_weight, 0.0, 1.0)
	var running := smoothstep(0.0, 1.0, clampf(run_weight, 0.0, 1.0))
	var weight := moving * lerpf(
		LOCOMOTION_HAND_WALK_WEIGHT,
		LOCOMOTION_HAND_RUN_WEIGHT,
		running
	)
	if weight <= EPSILON:
		return
	var phase := (gait_cycle if is_finite(gait_cycle) else 0.0) * PI
	_sync_locomotion_hand_target(true, sin(phase), running, weight)
	_sync_locomotion_hand_target(false, -sin(phase), running, weight)
	skeleton.force_update_all_bone_transforms()
	force_equipment_attachment_update()


## Solves a held prop from anatomical hand targets and updates the hand-owned mount in the same
## frame. Profile names come from ItemDefinition, but this layer remains item-agnostic and supports
## missing arms by mirroring the primary grip.
func sync_held_item_hands(
	profile: StringName,
	aim_basis: Basis,
	gait_cycle: float,
	movement_weight: float,
	run_weight: float,
	primary_left: bool,
	pose_weight := 1.0
) -> void:
	if not _usable or skeleton == null or (not _has_left_arm and not _has_right_arm):
		return
	var safe_aim_basis := aim_basis.orthonormalized()
	if absf(safe_aim_basis.determinant()) <= EPSILON:
		safe_aim_basis = global_basis.orthonormalized()
	var forward := -safe_aim_basis.z
	var up := safe_aim_basis.y
	var right := safe_aim_basis.x
	var moving := clampf(movement_weight, 0.0, 1.0)
	var running := smoothstep(0.0, 1.0, clampf(run_weight, 0.0, 1.0))
	var safe_cycle := gait_cycle if is_finite(gait_cycle) else 0.0
	var safe_pose_weight := clampf(pose_weight, 0.0, 1.0)
	if safe_pose_weight <= EPSILON:
		return
	var stride_wave := sin(safe_cycle * PI)
	var contact_wave := sin(safe_cycle * TAU)
	# The prop is held by the arms, so running creates small gait-derived grip travel rather than a
	# synthetic camera bob. Both the owner and remote players receive this exact displacement.
	var grip_motion := (
		right * stride_wave * (0.006 + running * 0.010)
		+ up * contact_wave * (0.004 + running * 0.008)
	) * moving
	var eye := _camera_mount.global_position if _camera_mount != null else _bone_world_origin(&"mixamorig_Head")
	var primary_sign := -1.0 if primary_left else 1.0
	var primary_forward := HELD_GENERIC_FORWARD
	var primary_drop := 0.34
	var primary_side := 0.20
	match profile:
		ItemDefinition.HELD_PROFILE_PISTOL:
			primary_forward = HELD_PISTOL_FORWARD
			primary_drop = 0.27
			primary_side = 0.16
		ItemDefinition.HELD_PROFILE_RIFLE:
			primary_forward = HELD_RIFLE_FORWARD
			primary_drop = 0.29
			primary_side = 0.13
		ItemDefinition.HELD_PROFILE_TOOL:
			primary_forward = HELD_TOOL_FORWARD
			primary_drop = 0.30
			primary_side = 0.17
	var primary_target := (
		eye
		+ forward * primary_forward
		- up * primary_drop
		+ right * primary_side * primary_sign
		+ grip_motion
	)
	primary_target = _clamp_hand_target_to_reach(primary_left, primary_target)
	var primary_hint := (
		right * primary_sign * 0.78
		+ up * 0.16
		- forward * 0.10
	).normalized()
	_sync_hand_target(primary_left, primary_target, primary_hint, safe_pose_weight)

	var support_left := not primary_left
	var has_support := _has_left_arm if support_left else _has_right_arm
	if profile == ItemDefinition.HELD_PROFILE_RIFLE and has_support:
		# The support hand meets the handguard ahead of and slightly above the trigger hand. It is an
		# IK target, not a parent, so customized/multi-barrel rifle geometry stays free to vary.
		var support_target := (
			eye
			+ forward * 0.46
			- up * 0.19
			- right * primary_sign * 0.12
			+ grip_motion
			+ right * stride_wave * 0.004 * moving
		)
		support_target = _clamp_hand_target_to_reach(
			support_left,
			support_target
		)
		var support_sign := -primary_sign
		var support_hint := (
			right * support_sign * 0.76
			+ up * 0.10
			- forward * 0.18
		).normalized()
		_sync_hand_target(
			support_left,
			support_target,
			support_hint,
			safe_pose_weight
		)
	elif has_support and moving > EPSILON:
		_sync_locomotion_hand_target(
			support_left,
			-stride_wave if primary_left else stride_wave,
			running,
			moving * lerpf(0.30, 0.72, running) * safe_pose_weight
		)

	skeleton.force_update_all_bone_transforms()
	force_equipment_attachment_update()
	var mount := _left_hand_grip_point if primary_left else _right_hand_grip_point
	var mount_roll := 0.035 if primary_left else -0.035
	_set_mount_world_transform(
		mount,
		get_hand_grip_world_position(primary_left),
		(
			safe_aim_basis
			* Basis.from_euler(Vector3(0.0, 0.0, mount_roll))
		).orthonormalized()
	)


func get_hand_world_position(left_side: bool) -> Vector3:
	if not _usable or skeleton == null:
		return global_position
	return _bone_world_origin(LEFT_HAND if left_side else RIGHT_HAND)


func set_local_view(value: bool) -> void:
	_local_view = value
	_apply_presence_scales()


func set_limb_presence(
	left_arm_available: bool,
	right_arm_available: bool,
	left_leg_available: bool,
	right_leg_available: bool
) -> void:
	_has_left_arm = left_arm_available
	_has_right_arm = right_arm_available
	_has_left_leg = left_leg_available
	_has_right_leg = right_leg_available
	_apply_presence_scales()


func set_head_presence(head_available: bool) -> void:
	_has_head = head_available
	_apply_presence_scales()


func sync_from_procedural_pose(
	leg_rig: PlayerProceduralLegRig,
	pose: PlayerCharacterPoseController,
	fieldlink_weight := 0.0,
	fieldlink_on_left := true,
	fieldlink_view_basis := Basis.IDENTITY,
	fieldlink_hold_position := Vector3.ZERO
) -> void:
	if not _usable or skeleton == null or leg_rig == null or pose == null:
		return
	_reset_driven_poses()
	_sync_hips(leg_rig)
	_sync_spine(leg_rig, pose)
	_sync_head(pose)
	_sync_arm(&"mixamorig_LeftArm", pose.left_arm_rotation)
	_sync_arm(&"mixamorig_RightArm", pose.right_arm_rotation)
	_sync_arm(LEFT_FOREARM, pose.left_forearm_rotation)
	_sync_arm(RIGHT_FOREARM, pose.right_forearm_rotation)
	if fieldlink_weight > EPSILON:
		_sync_fieldlink_arm(
			fieldlink_on_left,
			clampf(fieldlink_weight, 0.0, 1.0),
			fieldlink_view_basis,
			fieldlink_hold_position
		)
	_sync_leg(leg_rig, PlayerProceduralLegRig.Side.LEFT)
	_sync_leg(leg_rig, PlayerProceduralLegRig.Side.RIGHT)
	_apply_presence_scales()
	skeleton.force_update_all_bone_transforms()
	_sync_equipment_mounts(pose)


func _load_variant() -> bool:
	_clear_variant()
	if variant_path.is_empty() or not ResourceLoader.exists(variant_path):
		return false
	var packed_value: Resource = load(variant_path)
	var packed := packed_value as PackedScene
	if packed == null:
		push_warning("Character appearance is not a PackedScene: %s" % variant_path)
		return false
	model_root = packed.instantiate() as Node3D
	if model_root == null:
		push_warning("Character appearance could not be instantiated: %s" % variant_path)
		return false
	model_root.name = "TemporaryMaleVariant"
	model_root.rotation.y = MODEL_FACING_CORRECTION
	add_child(model_root)
	skeleton = _find_skeleton(model_root)
	if skeleton == null:
		push_warning("Character appearance has no Skeleton3D: %s" % variant_path)
		_clear_variant()
		return false
	_collect_skin_meshes(model_root)
	for bone_name: StringName in REQUIRED_BONES:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			push_warning(
				"Character appearance is missing bone %s: %s"
				% [bone_name, variant_path]
			)
			_clear_variant()
			return false
		_bone_indices[bone_name] = bone_index
		_rest_global_poses[bone_name] = skeleton.get_bone_global_rest(
			bone_index
		)
	_cache_leg_lengths()
	_cache_arm_lengths()
	_bind_wrist_mounts_to_skeleton()
	_usable = not skin_meshes.is_empty()
	_apply_presence_scales()
	return _usable


func _clear_variant() -> void:
	_detach_wrist_mounts_from_skeleton()
	_usable = false
	skeleton = null
	skin_meshes.clear()
	_bone_indices.clear()
	_rest_global_poses.clear()
	if is_instance_valid(model_root):
		model_root.queue_free()
	model_root = null


func _bind_wrist_mounts_to_skeleton() -> void:
	_ensure_mounts()
	if skeleton == null:
		return
	_backpack_attachment = _create_bone_attachment(
		&"UpperSpineEquipmentAttachment",
		UPPER_SPINE
	)
	_left_forearm_attachment = _create_bone_attachment(
		&"LeftForearmEquipmentAttachment",
		LEFT_FOREARM
	)
	_right_forearm_attachment = _create_bone_attachment(
		&"RightForearmEquipmentAttachment",
		RIGHT_FOREARM
	)
	_left_hand_attachment = _create_bone_attachment(
		&"LeftHandGripAttachment",
		LEFT_HAND
	)
	_right_hand_attachment = _create_bone_attachment(
		&"RightHandGripAttachment",
		RIGHT_HAND
	)
	_bind_backpack_mount()
	_bind_wrist_mount(
		_left_wrist_mount,
		_left_forearm_attachment,
		_left_lower_arm_length,
		true
	)
	_bind_wrist_mount(
		_right_wrist_mount,
		_right_forearm_attachment,
		_right_lower_arm_length,
		false
	)
	_bind_hand_grip_point(
		_left_hand_grip_point,
		_left_hand_attachment,
		_left_hand_grip_local_transform
	)
	_bind_hand_grip_point(
		_right_hand_grip_point,
		_right_hand_attachment,
		_right_hand_grip_local_transform
	)


func _bind_backpack_mount() -> void:
	if _backpack_mount == null or _backpack_attachment == null:
		return
	_backpack_attachment.on_skeleton_update()
	_backpack_mount.reparent(_backpack_attachment, false)
	var player_basis := global_basis.orthonormalized()
	_backpack_mount.global_transform = Transform3D(
		player_basis,
		(
			_bone_world_origin(UPPER_SPINE)
			+ player_basis.z * BACK_SURFACE_FROM_SPINE
			- player_basis.y * BACKPACK_MOUNT_DROP
		)
	)


func _create_bone_attachment(
	attachment_name: StringName,
	bone_name: StringName
) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	skeleton.add_child(attachment)
	# BoneAttachment resolves its Skeleton3D on tree entry. Assigning the index beforehand leaves it
	# displaying the imported rest transform until the next skeleton notification.
	attachment.bone_idx = _bone_index(bone_name)
	return attachment


func _bind_wrist_mount(
	mount: Node3D,
	attachment: BoneAttachment3D,
	forearm_length: float,
	left_side: bool
) -> void:
	if mount == null or attachment == null:
		return
	mount.reparent(attachment, false)
	var authored_roll := FIELDLINK_MOUNT_ROLL * (1.0 if left_side else -1.0)
	mount.transform = Transform3D(
		Basis.from_euler(Vector3(0.0, 0.0, authored_roll)),
		Vector3(
			0.0,
			forearm_length * FIELDLINK_FOREARM_LENGTH_RATIO,
			FIELDLINK_FOREARM_SURFACE_OFFSET
		)
	)


func _bind_hand_grip_point(
	mount: Node3D,
	attachment: BoneAttachment3D,
	grip_local_transform: Transform3D
) -> void:
	if mount == null or attachment == null:
		return
	attachment.on_skeleton_update()
	mount.reparent(attachment, false)
	mount.transform = grip_local_transform


func _detach_wrist_mounts_from_skeleton() -> void:
	for mount: Node3D in [
		_backpack_mount,
		_left_wrist_mount,
		_right_wrist_mount,
		_left_hand_grip_point,
		_right_hand_grip_point,
	]:
		if is_instance_valid(mount) and mount.get_parent() != self:
			mount.reparent(self, false)
			mount.transform = Transform3D.IDENTITY
	_left_forearm_attachment = null
	_right_forearm_attachment = null
	_left_hand_attachment = null
	_right_hand_attachment = null
	_backpack_attachment = null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _collect_skin_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		skin_meshes.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_skin_meshes(child)


func _cache_leg_lengths() -> void:
	_left_upper_leg_length = _rest_bone_distance(
		LEFT_UPPER_LEG,
		LEFT_LOWER_LEG
	)
	_left_lower_leg_length = _rest_bone_distance(
		LEFT_LOWER_LEG,
		LEFT_FOOT
	)
	_right_upper_leg_length = _rest_bone_distance(
		RIGHT_UPPER_LEG,
		RIGHT_LOWER_LEG
	)
	_right_lower_leg_length = _rest_bone_distance(
		RIGHT_LOWER_LEG,
		RIGHT_FOOT
	)
	_left_previous_bend = Vector3.ZERO
	_right_previous_bend = Vector3.ZERO


func _cache_arm_lengths() -> void:
	_left_upper_arm_length = _rest_bone_distance(LEFT_UPPER_ARM, LEFT_FOREARM)
	_left_lower_arm_length = _rest_bone_distance(LEFT_FOREARM, LEFT_HAND)
	_right_upper_arm_length = _rest_bone_distance(RIGHT_UPPER_ARM, RIGHT_FOREARM)
	_right_lower_arm_length = _rest_bone_distance(RIGHT_FOREARM, RIGHT_HAND)
	_left_previous_arm_bend = Vector3.ZERO
	_right_previous_arm_bend = Vector3.ZERO
	_left_previous_hand_target_bend = Vector3.ZERO
	_right_previous_hand_target_bend = Vector3.ZERO


func _rest_bone_distance(
	first_bone: StringName,
	second_bone: StringName
) -> float:
	return maxf(
		_rest_global_pose(first_bone).origin.distance_to(
			_rest_global_pose(second_bone).origin
		),
		0.001
	)


func _ensure_mounts() -> void:
	if (
		_backpack_mount != null
		and _eyes_mount != null
		and _camera_mount != null
		and _left_wrist_mount != null
		and _right_wrist_mount != null
		and _left_hand_grip_point != null
		and _right_hand_grip_point != null
	):
		return
	_backpack_mount = _ensure_mount(&"BackpackMount")
	_eyes_mount = _ensure_mount(&"EyesMount")
	_camera_mount = _ensure_mount(&"CameraMount")
	_left_wrist_mount = _ensure_mount(&"LeftWristMount")
	_right_wrist_mount = _ensure_mount(&"RightWristMount")
	_left_hand_grip_point = _ensure_mount(&"LeftHandGripPoint")
	_right_hand_grip_point = _ensure_mount(&"RightHandGripPoint")
	if not _hand_grip_points_captured:
		_left_hand_grip_local_transform = _authored_hand_grip_transform(
			_left_hand_grip_point
		)
		_right_hand_grip_local_transform = _authored_hand_grip_transform(
			_right_hand_grip_point
		)
		_hand_grip_points_captured = true


func _authored_hand_grip_transform(point: Node3D) -> Transform3D:
	if point == null or point.get_parent() != self:
		return Transform3D(Basis.IDENTITY, DEFAULT_HAND_GRIP_LOCAL_POSITION)
	# An identity transform means the point was synthesized for an older scene, not that a grip was
	# deliberately authored at the wrist pivot. Keep those scenes usable with the anatomical default.
	if point.transform == Transform3D.IDENTITY:
		point.position = DEFAULT_HAND_GRIP_LOCAL_POSITION
	return point.transform


func _ensure_mount(mount_name: StringName) -> Node3D:
	var existing := get_node_or_null(NodePath(str(mount_name))) as Node3D
	if existing != null:
		return existing
	var created := Node3D.new()
	created.name = mount_name
	add_child(created)
	return created


func _reset_driven_poses() -> void:
	for bone_name: StringName in REQUIRED_BONES:
		skeleton.reset_bone_pose(_bone_index(bone_name))
	skeleton.force_update_all_bone_transforms()


func _sync_hips(leg_rig: PlayerProceduralLegRig) -> void:
	var left_hip := leg_rig.get_hip_world_position(
		PlayerProceduralLegRig.Side.LEFT
	)
	var right_hip := leg_rig.get_hip_world_position(
		PlayerProceduralLegRig.Side.RIGHT
	)
	var target := (left_hip + right_hip) * 0.5
	var rest := _rest_global_pose(&"mixamorig_Hips")
	rest.origin = skeleton.to_local(target)
	skeleton.set_bone_global_pose(_bone_index(&"mixamorig_Hips"), rest)
	skeleton.force_update_bone_child_transform(
		_bone_index(&"mixamorig_Hips")
	)


func _sync_spine(
	leg_rig: PlayerProceduralLegRig,
	pose: PlayerCharacterPoseController
) -> void:
	for index in SPINE_BONES.size():
		var bone_name: StringName = SPINE_BONES[index]
		var bone_index := _bone_index(bone_name)
		var current := skeleton.get_bone_global_pose(bone_index)
		var delta_basis := _player_space_rotation_delta(
			pose.upper_body_rotation * SPINE_WEIGHTS[index],
			leg_rig.global_basis
		)
		current.basis = (delta_basis * current.basis).orthonormalized()
		if index == SPINE_BONES.size() - 1:
			var residual_position := (
				pose.upper_body_position
				- leg_rig.get_body_yield_offset()
			)
			current.origin += (
				skeleton.global_basis.inverse()
				* (leg_rig.global_basis * residual_position)
			)
		skeleton.set_bone_global_pose(bone_index, current)
		skeleton.force_update_bone_child_transform(bone_index)


func _sync_head(pose: PlayerCharacterPoseController) -> void:
	var index := _bone_index(&"mixamorig_Head")
	var current := skeleton.get_bone_global_pose(index)
	current.basis = (
		_player_space_rotation_delta(
			pose.head_rotation,
			global_basis
		)
		* current.basis
	).orthonormalized()
	current.origin += (
		skeleton.global_basis.inverse()
		* (global_basis * pose.head_position)
	)
	skeleton.set_bone_global_pose(index, current)
	skeleton.force_update_bone_child_transform(index)


func _sync_arm(bone_name: StringName, pose_rotation: Vector3) -> void:
	var index := _bone_index(bone_name)
	var current := skeleton.get_bone_global_pose(index)
	current.basis = (
		_player_space_rotation_delta(pose_rotation, global_basis)
		* current.basis
	).orthonormalized()
	skeleton.set_bone_global_pose(index, current)
	skeleton.force_update_bone_child_transform(index)


func _sync_fieldlink_arm(
	left_side: bool,
	weight: float,
	fieldlink_view_basis: Basis,
	fieldlink_hold_position: Vector3
) -> void:
	var upper_name := LEFT_UPPER_ARM if left_side else RIGHT_UPPER_ARM
	var lower_name := LEFT_FOREARM if left_side else RIGHT_FOREARM
	var hand_name := LEFT_HAND if left_side else RIGHT_HAND
	var shoulder := _bone_world_origin(upper_name)
	var current_hand := _bone_world_origin(hand_name)
	var player_basis := global_basis.orthonormalized()
	var forward := -player_basis.z
	var up := player_basis.y
	var view_basis := fieldlink_view_basis.orthonormalized()
	if absf(view_basis.determinant()) <= EPSILON:
		view_basis = player_basis
	var view_forward := -view_basis.z
	var view_up := view_basis.y
	var view_outward_axis := view_basis.x * (-1.0 if left_side else 1.0)
	var safe_hold_position := (
		fieldlink_hold_position
		if fieldlink_hold_position.is_finite()
		else Vector3.ZERO
	)
	var world_hold_position := view_basis * safe_hold_position
	var solution := _left_arm_solution if left_side else _right_arm_solution
	var previous_bend := (
		_left_previous_arm_bend if left_side else _right_previous_arm_bend
	)
	var upper_length := (
		_left_upper_arm_length if left_side else _right_upper_arm_length
	)
	var lower_length := (
		_left_lower_arm_length if left_side else _right_lower_arm_length
	)
	# Build the readable pose anatomically: the upper arm lifts forward from the shoulder, then the
	# entire forearm crosses toward the chest. At full weight both targets are exactly one authored
	# bone length apart, so the result has no dependence on the pose that preceded opening.
	var desired_elbow_direction := (
		view_forward * FIELDLINK_UPPER_FORWARD_WEIGHT
		+ view_up * FIELDLINK_UPPER_UP_WEIGHT
		+ view_outward_axis * FIELDLINK_UPPER_OUT_WEIGHT
	).normalized()
	# Keep the heavy device slightly below the literal eye point, but high enough that its display
	# occupies the player's natural focus instead of making them stare beneath the screen centre.
	var base_desired_elbow := (
		shoulder
		+ desired_elbow_direction * upper_length
		+ view_up * FIELDLINK_EYE_FOCUS_LIFT
	)
	var desired_elbow := (
		base_desired_elbow
		+ world_hold_position * FIELDLINK_ELBOW_HOLD_MOTION_INHERITANCE
	)
	var inward_axis := view_basis.x * (1.0 if left_side else -1.0)
	var desired_hand := (
		base_desired_elbow
		+ inward_axis * lower_length
		+ world_hold_position
	)
	var hand_target := current_hand.lerp(
		desired_hand,
		smoothstep(0.0, 1.0, weight)
	)
	var elbow_hint := desired_elbow - shoulder
	# Continuity must never preserve the opposite anatomical bend hemisphere. That can happen when
	# Tab lands on the same frame as a large view swing: the previous solution is valid numerically,
	# but it twists the elbow/forearm through the body. Drop only that incompatible history and let the
	# authored raised-elbow hint select the branch again.
	if (
		previous_bend.length_squared() > EPSILON
		and previous_bend.dot(elbow_hint) < 0.0
	):
		previous_bend = Vector3.ZERO
	LimbKinematics.solve_two_bone_into(
		solution,
		shoulder,
		hand_target,
		upper_length,
		lower_length,
		elbow_hint,
		previous_bend,
		-forward
	)
	if left_side:
		_left_previous_arm_bend = solution.bend_direction
	else:
		_right_previous_arm_bend = solution.bend_direction
	_set_segment_global_pose(upper_name, solution.hip, solution.knee)
	_set_segment_global_pose(lower_name, solution.knee, solution.tip)
	# The PBD mount is a fixed quarter-turn on the forearm bone. Roll that actual bone until the
	# screen's authored up axis agrees with eye-space up; the device itself never camera-corrects.
	var forearm_axis := (solution.tip - solution.knee).normalized()
	# Aim the forearm's top surface at the actual eye point. The mount itself remains an exact fixed
	# attachment; this roll belongs to the wrist/forearm pose and remains valid while the camera moves.
	var mount_center := (
		solution.knee
		+ forearm_axis * lower_length * FIELDLINK_FOREARM_LENGTH_RATIO
	)
	var resolved_eye_position := (
		_bone_world_origin(&"mixamorig_Head")
		+ up * CAMERA_UP_FROM_HEAD
		+ forward * CAMERA_FORWARD_FROM_HEAD
	)
	var eye_direction := resolved_eye_position - mount_center
	if eye_direction.length_squared() <= EPSILON:
		eye_direction = view_basis.z
	var screen_normal := (
		eye_direction
		- forearm_axis * eye_direction.dot(forearm_axis)
	).normalized()
	if screen_normal.length_squared() <= EPSILON:
		screen_normal = view_basis.z
	var screen_up := (
		screen_normal.cross(forearm_axis)
		if left_side
		else forearm_axis.cross(screen_normal)
	).normalized()
	if screen_up.dot(view_up) < 0.0:
		screen_up = -screen_up
	if screen_up.length_squared() <= EPSILON:
		screen_up = (
			view_up - forearm_axis * view_up.dot(forearm_axis)
		).normalized()
	var forearm_x := screen_up * (-1.0 if left_side else 1.0)
	var forearm_z := forearm_x.cross(forearm_axis).normalized()
	var target_forearm_basis := Basis(
		forearm_x,
		forearm_axis,
		forearm_z
	).orthonormalized()
	var lower_index := _bone_index(lower_name)
	var current_forearm_basis := (
		skeleton.global_basis
		* skeleton.get_bone_global_pose(lower_index).basis
	).orthonormalized()
	var roll_weight := smoothstep(0.0, 1.0, weight)
	var resolved_forearm_basis := Basis(
		Quaternion(current_forearm_basis).slerp(
			Quaternion(target_forearm_basis),
			roll_weight
		)
	).orthonormalized()
	_set_bone_world_pose(lower_name, solution.knee, resolved_forearm_basis)
	var hand_index := _bone_index(hand_name)
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	hand_pose.origin = skeleton.to_local(solution.tip)
	var hand_twist_world := Basis(
		Quaternion(
			forearm_axis,
			(
				(
					FIELDLINK_HAND_PRONATION
					+ FIELDLINK_HAND_TWIST
					* (-1.0 if left_side else 1.0)
				)
				* roll_weight
			)
		)
	)
	var hand_twist_skeleton := (
		skeleton.global_basis.inverse()
		* hand_twist_world
		* skeleton.global_basis
	).orthonormalized()
	hand_pose.basis = (hand_twist_skeleton * hand_pose.basis).orthonormalized()
	skeleton.set_bone_global_pose(hand_index, hand_pose)
	skeleton.force_update_bone_child_transform(hand_index)


func _sync_hand_target(
	left_side: bool,
	target_world: Vector3,
	bend_hint_world: Vector3,
	weight: float
) -> void:
	if not target_world.is_finite() or not bend_hint_world.is_finite():
		return
	var upper_name := LEFT_UPPER_ARM if left_side else RIGHT_UPPER_ARM
	var lower_name := LEFT_FOREARM if left_side else RIGHT_FOREARM
	var hand_name := LEFT_HAND if left_side else RIGHT_HAND
	var shoulder := _bone_world_origin(upper_name)
	var current_hand := _bone_world_origin(hand_name)
	var solution := (
		_left_hand_target_solution if left_side else _right_hand_target_solution
	)
	var previous_bend := (
		_left_previous_hand_target_bend
		if left_side
		else _right_previous_hand_target_bend
	)
	var upper_length := (
		_left_upper_arm_length if left_side else _right_upper_arm_length
	)
	var lower_length := (
		_left_lower_arm_length if left_side else _right_lower_arm_length
	)
	var eased_weight := smoothstep(0.0, 1.0, weight)
	var resolved_target := current_hand.lerp(target_world, eased_weight)
	var elbow_hint := bend_hint_world
	if elbow_hint.length_squared() <= EPSILON:
		elbow_hint = global_basis.x * (-1.0 if left_side else 1.0)
	if (
		previous_bend.length_squared() > EPSILON
		and previous_bend.dot(elbow_hint) < 0.0
	):
		previous_bend = Vector3.ZERO
	LimbKinematics.solve_two_bone_into(
		solution,
		shoulder,
		resolved_target,
		upper_length,
		lower_length,
		elbow_hint,
		previous_bend,
		-global_basis.z
	)
	if left_side:
		_left_previous_hand_target_bend = solution.bend_direction
	else:
		_right_previous_hand_target_bend = solution.bend_direction
	_set_segment_global_pose(upper_name, solution.hip, solution.knee)
	_set_segment_global_pose(lower_name, solution.knee, solution.tip)
	# Keep the authored wrist twist from the action pose, but move its origin to the grip. This makes
	# the prop control position while preserving character-specific hand shape and finger orientation.
	var hand_index := _bone_index(hand_name)
	var hand_pose := skeleton.get_bone_global_pose(hand_index)
	hand_pose.origin = skeleton.to_local(solution.tip)
	skeleton.set_bone_global_pose(hand_index, hand_pose)
	skeleton.force_update_bone_child_transform(hand_index)


func _sync_locomotion_hand_target(
	left_side: bool,
	stride_wave: float,
	run_weight: float,
	weight: float
) -> void:
	var player_basis := global_basis.orthonormalized()
	var forward := -player_basis.z
	var up := player_basis.y
	var right := player_basis.x
	var side_sign := -1.0 if left_side else 1.0
	var eye := _camera_mount.global_position if _camera_mount != null else _bone_world_origin(&"mixamorig_Head")
	var forward_distance := (
		lerpf(0.10, 0.24, run_weight)
		+ stride_wave * lerpf(0.055, 0.14, run_weight)
	)
	var target := (
		eye
		+ right * side_sign * lerpf(0.27, 0.22, run_weight)
		- up * lerpf(0.50, 0.39, run_weight)
		+ forward * forward_distance
		+ up * absf(stride_wave) * 0.025 * run_weight
	)
	target = _clamp_hand_target_to_reach(left_side, target)
	var bend_hint := (
		right * side_sign * 0.84
		- up * 0.08
		- forward * (0.12 + run_weight * 0.12)
	).normalized()
	_sync_hand_target(left_side, target, bend_hint, weight)


func _clamp_hand_target_to_reach(
	left_side: bool,
	target_world: Vector3
) -> Vector3:
	var shoulder := _bone_world_origin(
		LEFT_UPPER_ARM if left_side else RIGHT_UPPER_ARM
	)
	var maximum_reach := (
		(
			_left_upper_arm_length + _left_lower_arm_length
			if left_side
			else _right_upper_arm_length + _right_lower_arm_length
		)
		* HELD_HAND_REACH_RATIO
	)
	var offset := target_world - shoulder
	if offset.length_squared() <= maximum_reach * maximum_reach:
		return target_world
	return shoulder + offset.normalized() * maximum_reach


func _sync_equipment_mounts(pose: PlayerCharacterPoseController) -> void:
	_ensure_mounts()
	force_equipment_attachment_update()
	var player_basis := global_basis.orthonormalized()
	var forward := -player_basis.z
	var up := player_basis.y
	var head_basis := (
		player_basis * Basis.from_euler(pose.head_rotation)
	).orthonormalized()
	_set_mount_world_transform(
		_eyes_mount,
		_bone_world_origin(&"mixamorig_Head") + forward * 0.13 + up * 0.015,
		head_basis
	)
	# Mixamo's Head origin sits at the base of the skull. Treating it as the eye point leaves the
	# camera between the shoulders. Move anatomically upward and a little through the owner's hidden
	# head mesh so the lens clears the neck while remaining part of the same world body.
	_set_mount_world_transform(
		_camera_mount,
		(
			_bone_world_origin(&"mixamorig_Head")
			+ up * CAMERA_UP_FROM_HEAD
			+ forward * CAMERA_FORWARD_FROM_HEAD
		),
		head_basis
	)
	_sync_arm_mounts(
		true,
		pose.left_arm_rotation,
		forward,
		up,
		player_basis
	)
	_sync_arm_mounts(
		false,
		pose.right_arm_rotation,
		forward,
		up,
		player_basis
	)


func force_equipment_attachment_update() -> void:
	# BoneAttachment3D normally receives this at the end of the skeleton update. Equipment is read in
	# the same frame as the procedural solve, so update now and avoid one stale/rest-pose frame when
	# the PBD opens or changes arms.
	if is_instance_valid(_backpack_attachment):
		_backpack_attachment.on_skeleton_update()
	if is_instance_valid(_left_forearm_attachment):
		_left_forearm_attachment.on_skeleton_update()
	if is_instance_valid(_right_forearm_attachment):
		_right_forearm_attachment.on_skeleton_update()
	if is_instance_valid(_left_hand_attachment):
		_left_hand_attachment.on_skeleton_update()
	if is_instance_valid(_right_hand_attachment):
		_right_hand_attachment.on_skeleton_update()


func _sync_arm_mounts(
	left_side: bool,
	arm_rotation: Vector3,
	forward: Vector3,
	up: Vector3,
	player_basis: Basis
) -> void:
	var hand_grip := get_hand_grip_world_position(left_side)
	var arm_basis := (
		player_basis * Basis.from_euler(arm_rotation)
	).orthonormalized()
	var item_mount := (
		_left_hand_grip_point if left_side else _right_hand_grip_point
	)
	var item_roll := 0.08 if left_side else -0.08
	var item_basis := (
		arm_basis
		* Basis.from_euler(Vector3(0.04, -0.08, item_roll))
	).orthonormalized()
	_set_mount_world_transform(
		item_mount,
		hand_grip,
		item_basis
	)


func _set_mount_world_transform(
	mount: Node3D,
	world_position: Vector3,
	world_basis: Basis
) -> void:
	if mount == null:
		return
	mount.global_transform = Transform3D(world_basis, world_position)


func _set_bone_world_pose(
	bone_name: StringName,
	world_position: Vector3,
	world_basis: Basis
) -> void:
	var bone_index := _bone_index(bone_name)
	if bone_index < 0:
		return
	var skeleton_basis := (
		skeleton.global_basis.inverse() * world_basis
	).orthonormalized()
	skeleton.set_bone_global_pose(
		bone_index,
		Transform3D(skeleton_basis, skeleton.to_local(world_position))
	)
	skeleton.force_update_bone_child_transform(bone_index)


func _bone_world_origin(bone_name: StringName) -> Vector3:
	return _bone_world_transform(bone_name).origin


func _bone_world_transform(bone_name: StringName) -> Transform3D:
	var index := _bone_index(bone_name)
	if index < 0:
		return global_transform
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(index)
	)


func _sync_leg(leg_rig: PlayerProceduralLegRig, side: int) -> void:
	var available := (
		_has_left_leg
		if side == PlayerProceduralLegRig.Side.LEFT
		else _has_right_leg
	)
	if not available:
		return
	var upper_name := (
		LEFT_UPPER_LEG
		if side == PlayerProceduralLegRig.Side.LEFT
		else RIGHT_UPPER_LEG
	)
	var lower_name := (
		LEFT_LOWER_LEG
		if side == PlayerProceduralLegRig.Side.LEFT
		else RIGHT_LOWER_LEG
	)
	var foot_name := (
		LEFT_FOOT
		if side == PlayerProceduralLegRig.Side.LEFT
		else RIGHT_FOOT
	)
	var ankle_world := leg_rig.get_ankle_world_position(side)
	# Preserve the imported pelvis-to-thigh bind offset. Driving this origin from the prototype
	# capsule stance visually tears weighted hip vertices even though the target coordinates match.
	var hip_world := _bone_world_origin(upper_name)
	var authored_knee_hint := leg_rig.get_knee_world_position(side) - hip_world
	var solution := (
		_left_leg_solution
		if side == PlayerProceduralLegRig.Side.LEFT
		else _right_leg_solution
	)
	var previous_bend := (
		_left_previous_bend
		if side == PlayerProceduralLegRig.Side.LEFT
		else _right_previous_bend
	)
	var upper_length := (
		_left_upper_leg_length
		if side == PlayerProceduralLegRig.Side.LEFT
		else _right_upper_leg_length
	)
	var lower_length := (
		_left_lower_leg_length
		if side == PlayerProceduralLegRig.Side.LEFT
		else _right_lower_leg_length
	)
	LimbKinematics.solve_two_bone_into(
		solution,
		hip_world,
		ankle_world,
		upper_length,
		lower_length,
		authored_knee_hint,
		previous_bend,
		-global_basis.z
	)
	if side == PlayerProceduralLegRig.Side.LEFT:
		_left_previous_bend = solution.bend_direction
	else:
		_right_previous_bend = solution.bend_direction
	_set_segment_global_pose(upper_name, solution.hip, solution.knee)
	_set_segment_global_pose(lower_name, solution.knee, solution.tip)
	var foot_index := _bone_index(foot_name)
	var foot_pose := _rest_global_pose(foot_name)
	var flat_world_basis := leg_rig.global_basis.orthonormalized()
	var target_world_basis := leg_rig.get_foot_world_basis(side)
	var world_delta := (
		target_world_basis * flat_world_basis.inverse()
	).orthonormalized()
	var skeleton_delta := (
		skeleton.global_basis.inverse()
		* world_delta
		* skeleton.global_basis
	).orthonormalized()
	foot_pose.basis = (skeleton_delta * foot_pose.basis).orthonormalized()
	foot_pose.origin = skeleton.to_local(solution.tip)
	skeleton.set_bone_global_pose(foot_index, foot_pose)
	skeleton.force_update_bone_child_transform(foot_index)


func _set_segment_global_pose(
	bone_name: StringName,
	start_world: Vector3,
	end_world: Vector3
) -> void:
	var direction_world := end_world - start_world
	if direction_world.length_squared() <= EPSILON:
		return
	var rest := _rest_global_pose(bone_name)
	var direction_local := (
		skeleton.global_basis.inverse() * direction_world.normalized()
	).normalized()
	var rest_axis := rest.basis.y.normalized()
	var alignment := Quaternion(rest_axis, direction_local)
	var target := Transform3D(
		(Basis(alignment) * rest.basis).orthonormalized(),
		skeleton.to_local(start_world)
	)
	var index := _bone_index(bone_name)
	skeleton.set_bone_global_pose(index, target)
	skeleton.force_update_bone_child_transform(index)


func _player_space_rotation_delta(
	euler: Vector3,
	player_basis: Basis
) -> Basis:
	if euler.length_squared() <= EPSILON:
		return Basis.IDENTITY
	var safe_player_basis := player_basis.orthonormalized()
	var world_delta := (
		safe_player_basis
		* Basis.from_euler(euler)
		* safe_player_basis.inverse()
	)
	return (
		skeleton.global_basis.inverse()
		* world_delta
		* skeleton.global_basis
	).orthonormalized()


func _apply_presence_scales() -> void:
	if not _usable or skeleton == null:
		return
	_set_bone_visible(&"mixamorig_LeftArm", _has_left_arm)
	_set_bone_visible(&"mixamorig_RightArm", _has_right_arm)
	_set_bone_visible(&"mixamorig_LeftUpLeg", _has_left_leg)
	_set_bone_visible(&"mixamorig_RightUpLeg", _has_right_leg)
	# A first-person camera lives inside the imported head. Collapsing that one bone keeps the body
	# and procedural legs visible without a second mesh copy or a camera-near clipping shader.
	_set_bone_visible(&"mixamorig_Head", _has_head and not _local_view)


func _set_bone_visible(bone_name: StringName, value: bool) -> void:
	var index := _bone_index(bone_name)
	if index < 0:
		return
	skeleton.set_bone_pose_scale(
		index,
		Vector3.ONE if value else Vector3.ONE * 0.001
	)


func _bone_index(bone_name: StringName) -> int:
	return int(_bone_indices.get(bone_name, -1))


func _rest_global_pose(bone_name: StringName) -> Transform3D:
	return _rest_global_poses.get(bone_name, Transform3D.IDENTITY)
