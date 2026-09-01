class_name EnemyHumanoidPresentation3D
extends Node3D

const LEG_RIG_SCENE: PackedScene = preload(
	"res://scenes/proxy/player_procedural_leg_rig.tscn"
)
const FLUTE_POSE: CharacterPoseDefinition = preload(
	"res://resources/character_poses/flute_runner_playing.tres"
)
const OCULAR_DEFINITION: EquippableItemDefinition = preload(
	"res://resources/items/eyes/salvaged_oculars.tres"
)
const PROCEDURAL_ROOT_HEIGHT := -PlayerProceduralLegRig.REST_FOOT_LOCAL_HEIGHT
const EPSILON := 0.000001
const FLUTE_LENGTH := 0.54
const FLUTE_MOUTH_LOCAL := Vector3(0.015, -0.09, 0.0)
const FLUTE_AXIS_TO_MOUTH_LOCAL := Vector3(0.0, 0.68, 0.73)
const FLUTE_LEFT_GRIP_LOCAL := Vector3(-0.022, 0.075, -0.004)
const FLUTE_RIGHT_GRIP_LOCAL := Vector3(0.022, -0.08, -0.004)

## Client-owned procedural presentation. No bones or foot transforms cross the network: the compact
## authority state below is enough for every observer to derive the same kind of expressive motion.

var identity := 40000
var anatomy_definition: EnemyDestructibleAnatomyDefinition
var pose_root: Node3D
var leg_rig: PlayerProceduralLegRig
var character_skin: PlayerCharacterSkin
var ocular_visual: OcularExpressionVisual
var flute_visual: Node3D
var wound_presentation: EnemyWoundPresentation3D
var ragdoll_wound_presentation: EnemyWoundPresentation3D
var ragdoll: PlayerRagdoll3D
var ragdoll_sources: Dictionary[StringName, Node3D] = {}
var character_pose := PlayerCharacterPoseController.new()
var ocular_expression := PlayerOcularExpressionController.new()

var target_velocity := Vector3.ZERO
var target_on_floor := true
var target_gait_cycle := 0.0
var target_gait_active := false
var target_gait_stride_distance := PlayerGait.WALK_STEP_DISTANCE
var target_expression_clock := 0.0
var target_alive := true
var target_active := true
var target_position := Vector3.ZERO
var has_target_position := false
var awareness_state: StringName = &"loiter"
var flute_pose_weight := 1.0
var target_anatomy_state: Dictionary = {}
var time_since_state := 0.0
var _configured := false


func _ready() -> void:
	pose_root = Node3D.new()
	pose_root.name = "ProceduralBodyPose"
	# ServerEnemy uses a feet-on-ground origin because its collision shape is offset upward. The
	# shared player leg/skin stack uses a body reference origin with its resting feet 0.985 m below
	# it. Keep that conversion in one presentation root so feet, skin, attachments, and ragdoll
	# sources all inhabit the same frame on hosts and clients.
	pose_root.position.y = PROCEDURAL_ROOT_HEIGHT
	add_child(pose_root)
	leg_rig = LEG_RIG_SCENE.instantiate() as PlayerProceduralLegRig
	leg_rig.name = "ProceduralLegRig"
	pose_root.add_child(leg_rig)
	character_skin = PlayerCharacterSkin.new()
	character_skin.name = "CharacterSkin"
	pose_root.add_child(character_skin)
	_configure_identity(identity)
	_create_wound_presentation()
	_create_ocular_visual()
	_create_flute_visual()
	_create_ragdoll_presentation()
	_configured = true


func configure(
	next_identity: int,
	next_anatomy_definition: EnemyDestructibleAnatomyDefinition = null
) -> void:
	identity = maxi(next_identity, 0)
	anatomy_definition = next_anatomy_definition
	if is_node_ready():
		_configure_identity(identity)


func apply_server_state(state: Dictionary) -> void:
	target_velocity = state.get("velocity", target_velocity)
	target_on_floor = bool(state.get("on_floor", target_on_floor))
	target_gait_cycle = float(state.get("gait_cycle", target_gait_cycle))
	target_gait_active = bool(state.get("gait_active", target_gait_active))
	target_gait_stride_distance = maxf(
		float(state.get("gait_stride_distance", target_gait_stride_distance)),
		PlayerGait.MINIMUM_STRIDE_DISTANCE
	)
	target_expression_clock = float(state.get("expression_clock", target_expression_clock))
	target_alive = bool(state.get("alive", target_alive))
	target_active = bool(state.get("active", target_active))
	target_position = state.get("target_position", target_position)
	has_target_position = bool(state.get("has_target_position", has_target_position))
	awareness_state = StringName(state.get("awareness_state", awareness_state))
	flute_pose_weight = clampf(
		float(state.get("flute_pose_weight", flute_pose_weight)),
		0.0,
		1.0
	)
	var anatomy_value: Variant = state.get("anatomy_destruction", null)
	if wound_presentation != null and anatomy_value is Dictionary and not anatomy_value.is_empty():
		target_anatomy_state = (anatomy_value as Dictionary).duplicate(true)
		wound_presentation.apply_state(target_anatomy_state)
	time_since_state = 0.0


func apply_authoritative_enemy(enemy: ServerEnemy) -> void:
	if not is_instance_valid(enemy):
		return
	target_velocity = enemy.velocity
	target_on_floor = enemy.is_on_floor()
	target_gait_cycle = enemy.humanoid_gait.get_cycle()
	target_gait_active = enemy.humanoid_gait.active
	target_gait_stride_distance = enemy.humanoid_gait.stride_distance
	target_expression_clock = enemy.expression_clock
	target_alive = enemy.alive
	target_active = enemy.active
	awareness_state = enemy.flute_runner_controller.state_name()
	var target := enemy.sensed_target
	if is_instance_valid(target):
		target_position = enemy.sensed_target_position
		has_target_position = true
	else:
		target_position = enemy.flute_runner_controller.last_known_position
		has_target_position = enemy.flute_runner_controller.has_last_known_position
	flute_pose_weight = 1.0 if enemy.active and enemy.alive else 0.0
	if wound_presentation != null and enemy.destructible_anatomy != null:
		target_anatomy_state = enemy.destructible_anatomy.state_dict()
		wound_presentation.apply_state(target_anatomy_state)
	time_since_state = 0.0
	leg_rig.set_query_exclusion_rid(enemy.get_rid())


func update_presentation(delta: float) -> void:
	if not _configured:
		return
	if not target_alive:
		_begin_death_ragdoll_if_needed()
		if ragdoll_wound_presentation != null:
			ragdoll_wound_presentation.update_presentation()
		pose_root.visible = false
		return
	if ragdoll != null and ragdoll.is_active():
		ragdoll.stop_ragdoll()
	pose_root.visible = true
	visible = true
	var safe_delta := clampf(delta, 0.0, 0.1)
	time_since_state += safe_delta
	var speed := Vector2(target_velocity.x, target_velocity.z).length()
	var gait_cycle := target_gait_cycle
	if target_gait_active:
		gait_cycle += (
			speed / maxf(target_gait_stride_distance, PlayerGait.MINIMUM_STRIDE_DISTANCE)
			* time_since_state
		)
	leg_rig.update_pose(
		safe_delta,
		target_velocity,
		target_on_floor,
		gait_cycle,
		target_gait_active
	)

	var action_weight := flute_pose_weight if target_active else 0.0
	character_pose.set_action_pose(FLUTE_POSE, action_weight, true, true)
	var local_attention_target := Vector3(0.0, 0.1, -4.0)
	if has_target_position:
		local_attention_target = global_basis.inverse() * (
			target_position - (global_position + Vector3.UP * 1.55)
		)
	var attention_weight := _attention_weight_for_state(awareness_state)
	ocular_expression.update(
		safe_delta,
		target_expression_clock + time_since_state,
		local_attention_target,
		attention_weight,
		false,
		0.0
	)
	character_pose.set_attention_pose(
		ocular_expression.head_rotation,
		attention_weight
	)
	var movement_weight := clampf(inverse_lerp(0.25, 2.2, speed), 0.0, 1.0)
	var run_weight := PlayerGait.get_run_profile_weight(speed)
	var local_velocity := global_basis.inverse() * target_velocity
	character_pose.update(
		safe_delta,
		target_expression_clock + time_since_state,
		gait_cycle,
		movement_weight,
		run_weight,
		0.0,
		local_velocity,
		target_on_floor,
		false,
		leg_rig,
		true,
		true,
		true,
		true
	)
	pose_root.rotation = character_pose.body_rotation
	character_skin.sync_from_procedural_pose(leg_rig, character_pose)
	# The two-handed flute solve is the final animated-arm pass. Wounds must sample and follow the
	# resulting skin, not the one-frame-old forearm pose that existed before the grips were applied.
	_sync_face_and_flute(gait_cycle, movement_weight, action_weight)
	if wound_presentation != null:
		wound_presentation.update_presentation()


func _configure_identity(next_identity: int) -> void:
	identity = maxi(next_identity, 0)
	leg_rig.set_expression_identity(identity)
	character_pose.set_expression_identity(identity)
	ocular_expression.set_expression_identity(identity)
	character_skin.set_player_identity(identity)
	character_skin.set_local_view(false)
	character_skin.set_head_presence(true)
	character_skin.set_limb_presence(true, true, true, true)
	leg_rig.visible = not character_skin.is_usable()
	character_skin.visible = character_skin.is_usable()
	if wound_presentation != null:
		wound_presentation.configure(character_skin, anatomy_definition)


func _create_wound_presentation() -> void:
	wound_presentation = EnemyWoundPresentation3D.new()
	wound_presentation.name = "DestructibleAnatomyPresentation"
	add_child(wound_presentation)
	wound_presentation.configure(character_skin, anatomy_definition)


func _create_ocular_visual() -> void:
	var visual := OCULAR_DEFINITION.instantiate_equipped_visual()
	ocular_visual = visual as OcularExpressionVisual
	if ocular_visual == null:
		return
	ocular_visual.name = "ExpressiveOculars"
	character_skin.get_eyes_mount().add_child(ocular_visual)
	ocular_visual.position = Vector3(0.0, 0.0, -0.012)


func _create_flute_visual() -> void:
	flute_visual = Node3D.new()
	flute_visual.name = "Flute"
	character_skin.get_eyes_mount().add_child(flute_visual)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.16, 0.055, 1.0)
	material.metallic = 0.18
	material.roughness = 0.72
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.018
	body_mesh.bottom_radius = 0.021
	body_mesh.height = FLUTE_LENGTH
	body_mesh.radial_segments = 10
	body_mesh.rings = 1
	body_mesh.material = material
	var body := MeshInstance3D.new()
	body.name = "FluteBody"
	body.mesh = body_mesh
	flute_visual.add_child(body)
	for hole_index: int in range(5):
		var hole_material := StandardMaterial3D.new()
		hole_material.albedo_color = Color(0.015, 0.012, 0.008, 1.0)
		var hole_mesh := SphereMesh.new()
		hole_mesh.radius = 0.008
		hole_mesh.height = 0.016
		hole_mesh.radial_segments = 8
		hole_mesh.rings = 4
		hole_mesh.material = hole_material
		var hole := MeshInstance3D.new()
		hole.name = "ToneHole%d" % hole_index
		hole.mesh = hole_mesh
		hole.position = Vector3(
			0.0,
			0.10 - float(hole_index) * 0.062,
			-0.018
		)
		flute_visual.add_child(hole)


func _create_ragdoll_presentation() -> void:
	ragdoll = PlayerRagdoll3D.new()
	ragdoll.name = "HumanoidRagdoll"
	add_child(ragdoll)
	for body_name: StringName in [
		&"torso",
		&"head",
		&"left_arm",
		&"right_arm",
		&"left_upper_leg",
		&"left_lower_leg",
		&"left_foot",
		&"right_upper_leg",
		&"right_lower_leg",
		&"right_foot",
	]:
		var marker := Node3D.new()
		marker.name = StringName("RagdollSource_%s" % body_name)
		add_child(marker)
		ragdoll_sources[body_name] = marker


func _begin_death_ragdoll_if_needed() -> void:
	if ragdoll == null or ragdoll.is_active() or character_skin == null:
		return
	_sync_ragdoll_source_transforms()
	var trip_direction := Vector3(target_velocity.x, 0.0, target_velocity.z)
	if trip_direction.length_squared() <= EPSILON:
		trip_direction = -global_basis.z
	if wound_presentation != null:
		ragdoll.set_limb_presence(
			wound_presentation.part_is_present(EnemyDestructibleAnatomy.PART_LEFT_ARM),
			wound_presentation.part_is_present(EnemyDestructibleAnatomy.PART_RIGHT_ARM),
			wound_presentation.part_is_present(EnemyDestructibleAnatomy.PART_LEFT_LEG),
			wound_presentation.part_is_present(EnemyDestructibleAnatomy.PART_RIGHT_LEG)
		)
	ragdoll.start_ragdoll(
		ragdoll_sources,
		target_velocity,
		trip_direction,
		character_skin,
		false
	)
	var ragdoll_skin := ragdoll.get_authored_skin()
	if ragdoll_skin != null:
		ragdoll_wound_presentation = EnemyWoundPresentation3D.new()
		ragdoll_wound_presentation.name = "RagdollDestructibleAnatomyPresentation"
		ragdoll.add_child(ragdoll_wound_presentation)
		ragdoll_wound_presentation.configure(ragdoll_skin, anatomy_definition)
		ragdoll_wound_presentation.apply_state(target_anatomy_state)


func _sync_ragdoll_source_transforms() -> void:
	if character_skin == null or character_skin.skeleton == null:
		return
	_set_ragdoll_bone_source(&"torso", &"mixamorig_Spine1")
	_set_ragdoll_bone_source(&"head", &"mixamorig_Head")
	_set_ragdoll_segment_source(
		&"left_arm",
		&"mixamorig_LeftArm",
		&"mixamorig_LeftHand"
	)
	_set_ragdoll_segment_source(
		&"right_arm",
		&"mixamorig_RightArm",
		&"mixamorig_RightHand"
	)
	_set_ragdoll_segment_source(
		&"left_upper_leg",
		&"mixamorig_LeftUpLeg",
		&"mixamorig_LeftLeg"
	)
	_set_ragdoll_segment_source(
		&"left_lower_leg",
		&"mixamorig_LeftLeg",
		&"mixamorig_LeftFoot"
	)
	_set_ragdoll_bone_source(&"left_foot", &"mixamorig_LeftFoot")
	_set_ragdoll_segment_source(
		&"right_upper_leg",
		&"mixamorig_RightUpLeg",
		&"mixamorig_RightLeg"
	)
	_set_ragdoll_segment_source(
		&"right_lower_leg",
		&"mixamorig_RightLeg",
		&"mixamorig_RightFoot"
	)
	_set_ragdoll_bone_source(&"right_foot", &"mixamorig_RightFoot")


func _set_ragdoll_bone_source(body_name: StringName, bone_name: StringName) -> void:
	var marker := ragdoll_sources.get(body_name) as Node3D
	var bone_transform := _bone_world_transform(bone_name)
	if marker != null and bone_transform != Transform3D.IDENTITY:
		marker.global_transform = bone_transform.orthonormalized()


func _set_ragdoll_segment_source(
	body_name: StringName,
	start_bone: StringName,
	end_bone: StringName
) -> void:
	var marker := ragdoll_sources.get(body_name) as Node3D
	if marker == null:
		return
	var start := _bone_world_transform(start_bone).origin
	var end := _bone_world_transform(end_bone).origin
	var direction := end - start
	if direction.length_squared() <= EPSILON:
		return
	marker.global_transform = Transform3D(
		LimbKinematics.basis_from_y(direction.normalized()),
		start.lerp(end, 0.5)
	)


func _bone_world_transform(bone_name: StringName) -> Transform3D:
	if character_skin == null or character_skin.skeleton == null:
		return Transform3D.IDENTITY
	var bone_index := character_skin.skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Transform3D.IDENTITY
	return (
		character_skin.skeleton.global_transform
		* character_skin.skeleton.get_bone_global_pose(bone_index)
	)


func _sync_face_and_flute(
	gait_cycle: float,
	movement_weight: float,
	action_weight: float
) -> void:
	if ocular_visual != null:
		ocular_visual.apply_ocular_expression(
			ocular_expression.left_pupil_offset,
			ocular_expression.right_pupil_offset,
			ocular_expression.pupil_scale,
			ocular_expression.left_lid_openness,
			ocular_expression.right_lid_openness,
			ocular_expression.left_lid_tilt,
			ocular_expression.right_lid_tilt
		)
	if flute_visual == null:
		return
	var clock := target_expression_clock + time_since_state
	var breath := sin(clock * TAU * 0.31 + float(identity) * 0.17)
	var chase_sway := sin(gait_cycle * PI) * movement_weight
	var axis_to_mouth := FLUTE_AXIS_TO_MOUTH_LOCAL.normalized()
	var flute_x := Vector3.RIGHT
	var flute_z := flute_x.cross(axis_to_mouth).normalized()
	var flute_basis := Basis(flute_x, axis_to_mouth, flute_z).orthonormalized()
	var expressive_rotation := Basis.from_euler(Vector3(
		breath * 0.012,
		chase_sway * 0.018,
		sin(clock * 0.71) * 0.012 + chase_sway * 0.022
	))
	flute_visual.basis = (flute_basis * expressive_rotation).orthonormalized()
	flute_visual.position = (
		FLUTE_MOUTH_LOCAL
		- axis_to_mouth * FLUTE_LENGTH * 0.5
		+ Vector3(
			chase_sway * 0.006,
			breath * 0.003 + absf(chase_sway) * 0.004,
			0.0
		)
	)
	var has_flute_arm := (
		wound_presentation == null
		or wound_presentation.part_is_present(EnemyDestructibleAnatomy.PART_LEFT_ARM)
		or wound_presentation.part_is_present(EnemyDestructibleAnatomy.PART_RIGHT_ARM)
	)
	flute_visual.visible = flute_pose_weight > 0.02 and target_active and has_flute_arm
	if not flute_visual.visible or character_skin == null:
		return
	var player_basis := global_basis.orthonormalized()
	character_skin.sync_two_hand_targets(
		flute_visual.to_global(FLUTE_LEFT_GRIP_LOCAL),
		flute_visual.to_global(FLUTE_RIGHT_GRIP_LOCAL),
		-player_basis.x * 0.72 + player_basis.y * 0.10 + player_basis.z * 0.08,
		player_basis.x * 0.72 + player_basis.y * 0.06 + player_basis.z * 0.08,
		action_weight
	)


func get_flute_axis_world() -> Vector3:
	if flute_visual == null:
		return Vector3.UP
	return flute_visual.global_basis.y.normalized()


func get_flute_grip_world_position(left_side: bool) -> Vector3:
	if flute_visual == null:
		return global_position
	return flute_visual.to_global(
		FLUTE_LEFT_GRIP_LOCAL if left_side else FLUTE_RIGHT_GRIP_LOCAL
	)


static func _attention_weight_for_state(state_name: StringName) -> float:
	match state_name:
		&"chase":
			return 1.0
		&"pursue":
			return 0.88
		&"curious", &"search":
			return 0.64
		&"fumble":
			return 0.28
	return 0.18
