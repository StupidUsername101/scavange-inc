extends SceneTree

const RIG_SCENE := preload(
	"res://scenes/proxy/player_procedural_leg_rig.tscn"
)
const CORPSE_PROXY := preload(
	"res://scripts/client/player_corpse_proxy.gd"
)
const STEP := 1.0 / 60.0
const POSITION_EPSILON := 0.015

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_explicit_deterministic_catalog()
	await _test_selected_variants_share_runtime_contract()
	await _test_all_variants_backpack_mount_contract()
	await _test_variant_swap_preserves_equipment_mounts()
	await _test_procedural_leg_retargeting()
	await _test_missing_limb_and_first_person_masks()
	await _test_late_join_corpse_uses_authored_skin()
	if failure_count == 0:
		print(
			"Player character skin tests passed: %d assertions"
			% assertion_count
		)
		quit(0)
	else:
		push_error(
			"Player character skin tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_explicit_deterministic_catalog() -> void:
	var paths: Array[String] = []
	for player_id: int in range(1, LobbyRules.MAX_PLAYERS + 1):
		var first := (
			PlayerCharacterAppearanceCatalog.variant_path_for_player_id(
				player_id
			)
		)
		var second := (
			PlayerCharacterAppearanceCatalog.variant_path_for_player_id(
				player_id
			)
		)
		paths.append(first)
		_expect(
			first == second and ResourceLoader.exists(first),
			"player %d resolves to one explicit imported male resource"
			% player_id
		)
	var unique := {}
	for path: String in paths:
		unique[path] = true
	_expect(
		unique.size() == LobbyRules.MAX_PLAYERS,
		"all four lobby identities receive distinct variants without directory-order enumeration"
	)


func _test_selected_variants_share_runtime_contract() -> void:
	for player_id: int in range(1, LobbyRules.MAX_PLAYERS + 1):
		var skin := PlayerCharacterSkin.new()
		root.add_child(skin)
		var loaded := skin.set_player_identity(player_id)
		_expect(
			loaded
			and skin.is_usable()
			and skin.skeleton != null
			and not skin.skin_meshes.is_empty(),
			"selected male variant %d imports with a skinned skeleton"
			% player_id
		)
		var left_mount := skin.get_wrist_mount(true)
		var right_mount := skin.get_wrist_mount(false)
		var left_attachment := left_mount.get_parent() as BoneAttachment3D
		var right_attachment := right_mount.get_parent() as BoneAttachment3D
		_expect(
			left_attachment != null
			and right_attachment != null
			and left_attachment.bone_idx == skin.skeleton.find_bone(
				PlayerCharacterSkin.LEFT_FOREARM
			)
			and right_attachment.bone_idx == skin.skeleton.find_bone(
				PlayerCharacterSkin.RIGHT_FOREARM
			),
			"selected male variant %d exposes real left/right forearm equipment attachments"
			% player_id
		)
		skin.queue_free()
		await process_frame


func _test_late_join_corpse_uses_authored_skin() -> void:
	var corpse := CORPSE_PROXY.new()
	root.add_child(corpse)
	var initial_state := {
		"corpse_id": 4,
		"source_player_id": 2,
		"pos": Vector3(0.0, 1.0, 0.0),
		"vel": Vector3(1.0, 0.0, 0.0),
		"yaw": 0.4,
		"trip_direction": Vector3.FORWARD,
		"limbs": {
			"left_arm": true,
			"right_arm": true,
			"left_leg": true,
			"right_leg": true,
		},
	}
	corpse.initialize_from_player(null, initial_state)
	await physics_frame
	_expect(
		corpse.ragdoll != null
		and corpse.ragdoll.is_active()
		and corpse.ragdoll.has_authored_skin()
		and corpse.ragdoll.get_authored_skin().player_id == 2,
		"a corpse received without its original live proxy reconstructs the deterministic authored player skin instead of grey goo"
	)
	var corrected_state := initial_state.duplicate(true)
	corrected_state["pos"] = Vector3(5.0, 1.0, -2.0)
	corrected_state["vel"] = Vector3.ZERO
	corpse.apply_server_state(corrected_state)
	_expect(
		corpse.ragdoll.get_torso_world_position().distance_to(
			Vector3(5.0, 1.0, -2.0) + PlayerRagdoll3D.TORSO_OFFSET_FROM_PLAYER
		) < 0.05,
		"a late or divergent corpse moves its complete articulated island to the authoritative torso"
	)
	corpse.queue_free()
	await process_frame


func _test_variant_swap_preserves_equipment_mounts() -> void:
	var skin := PlayerCharacterSkin.new()
	root.add_child(skin)
	skin.set_player_identity(1)
	var original_mount := skin.get_wrist_mount(true)
	var equipped_marker := Node3D.new()
	original_mount.add_child(equipped_marker)
	var swapped := skin.set_player_identity(2)
	var rebound_attachment := original_mount.get_parent() as BoneAttachment3D
	_expect(
		swapped
		and skin.get_wrist_mount(true) == original_mount
		and equipped_marker.get_parent() == original_mount
		and rebound_attachment != null
		and rebound_attachment.bone_idx == skin.skeleton.find_bone(
			PlayerCharacterSkin.LEFT_FOREARM
		),
		"changing an explicit player skin rebinds the same equipment mount without deleting its equipped item"
	)
	skin.queue_free()
	await process_frame


func _test_all_variants_backpack_mount_contract() -> void:
	var seen_paths := {}
	var backpack_paths: Array[String] = [
		"res://resources/items/backpacks/scavenger_sling.tres",
		"res://resources/items/backpacks/field_pack.tres",
		"res://resources/items/backpacks/industrial_frame_pack.tres",
	]
	for player_id: int in range(
		PlayerCharacterAppearanceCatalog.variant_count()
	):
		var skin := PlayerCharacterSkin.new()
		root.add_child(skin)
		var loaded := skin.set_player_identity(player_id)
		seen_paths[skin.get_variant_path()] = true
		var mount := skin.get_backpack_mount()
		var attachment := mount.get_parent() as BoneAttachment3D
		var spine_origin := _bone_world_origin(skin, PlayerCharacterSkin.UPPER_SPINE)
		var back := skin.global_basis.z.normalized()
		var up := skin.global_basis.y.normalized()
		_expect(
			loaded
			and attachment != null
			and attachment.bone_idx == skin.skeleton.find_bone(
				PlayerCharacterSkin.UPPER_SPINE
			)
			and absf(
				(mount.global_position - spine_origin).dot(back)
				- PlayerCharacterSkin.BACK_SURFACE_FROM_SPINE
			) < POSITION_EPSILON
			and absf(
				(mount.global_position - spine_origin).dot(up)
				+ PlayerCharacterSkin.BACKPACK_MOUNT_DROP
			) < POSITION_EPSILON,
			"male variant %d binds its backpack mount to the real upper-spine bone and back surface"
			% player_id
		)
		for backpack_path: String in backpack_paths:
			var backpack := load(backpack_path) as BackpackDefinition
			var visual := backpack.instantiate_equipped_visual()
			mount.add_child(visual)
			var inner_surface_depth := _minimum_mesh_projection(
				visual,
				spine_origin,
				back
			)
			_expect(
				absf(
					inner_surface_depth
					- PlayerCharacterSkin.BACK_SURFACE_FROM_SPINE
				) < POSITION_EPSILON
				and (-visual.global_basis.z.normalized()).dot(back) > 0.98,
				"%s sits flush and faces outward on male variant %d (inner %.3f, facing %.3f)"
				% [
					backpack.display_name,
					player_id,
					inner_surface_depth,
					(-visual.global_basis.z.normalized()).dot(back),
				]
			)
			visual.free()
		skin.queue_free()
		await process_frame
	_expect(
		seen_paths.size() == PlayerCharacterAppearanceCatalog.variant_count(),
		"the backpack attachment contract covers every explicit human model rather than filesystem order"
	)


func _minimum_mesh_projection(
	node: Node,
	origin: Vector3,
	axis: Vector3
) -> float:
	var minimum := INF
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var bounds := mesh_instance.mesh.get_aabb()
			for x_side: int in range(2):
				for y_side: int in range(2):
					for z_side: int in range(2):
						var corner := bounds.position + Vector3(
							bounds.size.x * float(x_side),
							bounds.size.y * float(y_side),
							bounds.size.z * float(z_side)
						)
						minimum = minf(
							minimum,
							(
								mesh_instance.global_transform * corner
								- origin
							).dot(axis)
						)
	for child: Node in node.get_children():
		minimum = minf(
			minimum,
			_minimum_mesh_projection(child, origin, axis)
		)
	return minimum


func _test_procedural_leg_retargeting() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	_add_floor(fixture)
	var body_root := Node3D.new()
	body_root.position.y = 0.985
	fixture.add_child(body_root)
	var rig := RIG_SCENE.instantiate() as PlayerProceduralLegRig
	body_root.add_child(rig)
	var skin := PlayerCharacterSkin.new()
	body_root.add_child(skin)
	skin.set_player_identity(1)
	await physics_frame
	await physics_frame
	rig.update_pose(STEP, Vector3.ZERO, true, 0.5, false)
	var pose := PlayerCharacterPoseController.new()
	pose.set_expression_identity(1)
	pose.update(
		STEP,
		0.0,
		0.5,
		0.0,
		0.0,
		0.0,
		Vector3.ZERO,
		true,
		false,
		rig,
		true,
		true,
		true,
		true
	)
	skin.sync_from_procedural_pose(rig, pose)
	var camera_anchor := skin.get_camera_mount().global_position
	var head_origin := _bone_world_origin(skin, &"mixamorig_Head")
	var camera_offset := camera_anchor - head_origin
	_expect(
		camera_offset.dot(skin.global_basis.y) > 0.085
		and camera_offset.dot(-skin.global_basis.z) > 0.075
		and camera_offset.length() < 0.16,
		"the owner camera derives an anatomical eye/face position forward of the open neck seam"
	)
	for side: int in [
		PlayerProceduralLegRig.Side.LEFT,
		PlayerProceduralLegRig.Side.RIGHT,
	]:
		var prefix := (
			"Left"
			if side == PlayerProceduralLegRig.Side.LEFT
			else "Right"
		)
		var points := rig.get_leg_points(side)
		var upper_origin := _bone_world_origin(
			skin,
			StringName("mixamorig_%sUpLeg" % prefix)
		)
		var lower_origin := _bone_world_origin(
			skin,
			StringName("mixamorig_%sLeg" % prefix)
		)
		var foot_origin := _bone_world_origin(
			skin,
			StringName("mixamorig_%sFoot" % prefix)
		)
		var hips_origin := _bone_world_origin(skin, &"mixamorig_Hips")
		var skeleton := skin.skeleton
		var hips_index := skeleton.find_bone(&"mixamorig_Hips")
		var upper_index := skeleton.find_bone(
			StringName("mixamorig_%sUpLeg" % prefix)
		)
		var lower_index := skeleton.find_bone(
			StringName("mixamorig_%sLeg" % prefix)
		)
		var foot_index := skeleton.find_bone(
			StringName("mixamorig_%sFoot" % prefix)
		)
		var rest_hip_offset := skeleton.get_bone_global_rest(
			hips_index
		).origin.distance_to(
			skeleton.get_bone_global_rest(upper_index).origin
		)
		var rest_upper_length := skeleton.get_bone_global_rest(
			upper_index
		).origin.distance_to(
			skeleton.get_bone_global_rest(lower_index).origin
		)
		var rest_lower_length := skeleton.get_bone_global_rest(
			lower_index
		).origin.distance_to(
			skeleton.get_bone_global_rest(foot_index).origin
		)
		_expect(
			absf(hips_origin.distance_to(upper_origin) - rest_hip_offset)
			< POSITION_EPSILON
			and absf(upper_origin.distance_to(lower_origin) - rest_upper_length)
			< POSITION_EPSILON
			and absf(lower_origin.distance_to(foot_origin) - rest_lower_length)
			< POSITION_EPSILON
			and foot_origin.distance_to(points[2]) < POSITION_EPSILON,
			"the %s imported leg preserves its pelvis seams and authored segment lengths while reaching the procedural ankle contact"
			% prefix.to_lower()
		)
	fixture.queue_free()
	await process_frame


func _test_missing_limb_and_first_person_masks() -> void:
	var skin := PlayerCharacterSkin.new()
	root.add_child(skin)
	skin.set_player_identity(2)
	skin.set_limb_presence(false, true, true, false)
	skin.set_local_view(true)
	_expect(
		_bone_scale(skin, &"mixamorig_LeftArm").x < 0.01
		and _bone_scale(skin, &"mixamorig_RightArm").x > 0.99
		and _bone_scale(skin, &"mixamorig_LeftUpLeg").x > 0.99
		and _bone_scale(skin, &"mixamorig_RightUpLeg").x < 0.01,
		"authored skin masks the same independently missing limbs as the gameplay loadout"
	)
	_expect(
		_bone_scale(skin, &"mixamorig_Head").x < 0.01,
		"the local first-person skin collapses only its camera-occluding head"
	)
	skin.set_local_view(false)
	_expect(
		_bone_scale(skin, &"mixamorig_Head").x > 0.99,
		"remote observers retain the authored head"
	)
	skin.queue_free()
	await process_frame


func _add_floor(parent: Node3D) -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = CharacterContactLayers.MOVEMENT_SURFACE
	floor.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.0, 0.2, 8.0)
	shape_node.shape = shape
	floor.position.y = -0.1
	floor.add_child(shape_node)
	parent.add_child(floor)


func _bone_world_origin(
	skin: PlayerCharacterSkin,
	bone_name: StringName
) -> Vector3:
	var index := skin.skeleton.find_bone(bone_name)
	return (
		skin.skeleton.global_transform
		* skin.skeleton.get_bone_global_pose(index)
	).origin


func _bone_scale(
	skin: PlayerCharacterSkin,
	bone_name: StringName
) -> Vector3:
	return skin.skeleton.get_bone_pose_scale(
		skin.skeleton.find_bone(bone_name)
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", message)
		return
	failure_count += 1
	push_error("[FAIL] %s" % message)
