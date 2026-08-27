extends SceneTree

#######################################################
# Lightweight creator-pose regression. This deliberately avoids a server/physics world so the
# serialized worker frame and descendant-joint mutation can be checked deterministically.
#######################################################

var failures: int = 0
var assertions: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_worker_orientation()
	_test_joint_rotation_propagates()
	await _test_editor_gizmos_instantiate()
	print("ML body editor pose assertions: %d, failures: %d" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_worker_orientation() -> void:
	var core: DroneCoreDefinition = DroneCoreDefinition.new()
	_expect(core.set_model_forward(Vector3.RIGHT), "forward face is accepted")
	_expect(core.set_model_up(Vector3.BACK), "up face is accepted")
	var orientation: Basis = core.model_orientation_basis_local()
	_expect((-orientation.z).is_equal_approx(Vector3.RIGHT), "forward remains exact")
	_expect(orientation.y.is_equal_approx(Vector3.BACK), "up remains exact")
	_expect(is_equal_approx(orientation.determinant(), 1.0), "worker frame is right-handed")
	var requested_spawn_basis: Basis = Basis(Vector3.UP, deg_to_rad(23.0))
	var physical_core_basis: Basis = (
		requested_spawn_basis * orientation.transposed()
	).orthonormalized()
	_expect(
		(physical_core_basis * orientation).is_equal_approx(requested_spawn_basis),
		"physical spawn alignment reconstructs the requested worker frame"
	)
	var snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(core)
	var restored: DroneCoreDefinition = (
		MLBodyResourceSnapshot.decode_resource(snapshot) as DroneCoreDefinition
	)
	_expect(
		restored != null
		and restored.model_forward_local.is_equal_approx(core.model_forward_local)
		and restored.model_up_local.is_equal_approx(core.model_up_local),
		"worker frame survives the body snapshot used by checkpoints and export"
	)
	var loadout: DroneLoadout = DroneLoadout.new()
	core.propeller_slot_count = 1
	loadout.install_core(core)
	loadout.set_propeller_slot_transform(
		0,
		Transform3D(
			Basis(orientation.x, orientation.y, orientation.z),
			Vector3.ZERO
		)
	)
	_expect(
		is_equal_approx(DroneTrainingLoadoutConfig._propeller_up_component(loadout, 0), 1.0),
		"lift readiness follows worker up instead of hard-coded Core +Y"
	)


func _test_joint_rotation_propagates() -> void:
	var source: DroneLimbAttachmentDefinition = load(
		"res://resources/model_forge/attachments/configurable_articulated_limb.tres"
	) as DroneLimbAttachmentDefinition
	var edited: DroneLimbAttachmentDefinition = (
		MLBodyPartContract.deep_duplicate_resource(source) as DroneLimbAttachmentDefinition
	)
	_expect(edited != null and edited.mount_adaptive_neutral_pose, "configurable limb starts adaptive")
	if edited == null or edited.limb_definitions.is_empty():
		return
	var limb: GenericLimbDefinition = edited.limb_definitions[0]
	var original_first: Vector3 = limb.segments[0].rest_direction_local
	var original_child: Vector3 = limb.segments[1].rest_direction_local
	var delta: Basis = Basis(Vector3.BACK, deg_to_rad(41.0))
	var directions: Array = []
	var bases: Array = []
	for segment: LimbSegmentDefinition in limb.segments:
		directions.append((delta * segment.rest_direction_local).normalized())
		bases.append((delta * segment.joint.joint_basis_local).orthonormalized())
	var error: String = MLBodyLimbEditor.set_joint_subtree_pose(
		edited,
		0,
		0,
		directions,
		bases
	)
	_expect(error.is_empty(), "joint subtree pose is accepted")
	_expect(
		limb.segments[0].rest_direction_local.is_equal_approx(
			(delta * original_first).normalized()
		),
		"selected part rotates"
	)
	_expect(
		limb.segments[1].rest_direction_local.is_equal_approx(
			(delta * original_child).normalized()
		),
		"child part follows the selected joint"
	)
	_expect(not edited.mount_adaptive_neutral_pose, "manual pose disables adaptive stance overwrite")
	var mounted: Array[GenericLimbDefinition] = edited.mounted_limb_definitions(
		Transform3D(Basis.IDENTITY, Vector3.RIGHT)
	)
	_expect(
		mounted.size() == 1
		and mounted[0].segments[0].rest_direction_local.is_equal_approx(
			limb.segments[0].rest_direction_local
		),
		"runtime mounting preserves the authored pose"
	)


func _test_editor_gizmos_instantiate() -> void:
	var source: DroneLimbAttachmentDefinition = load(
		"res://resources/model_forge/attachments/configurable_articulated_limb.tres"
	) as DroneLimbAttachmentDefinition
	var shape_editor: MLLimbShapeEditor3D = MLLimbShapeEditor3D.new()
	root.add_child(shape_editor)
	await process_frame
	shape_editor.set_limb_definition(source.limb_definitions[0], 0)
	await process_frame
	_expect(
		shape_editor.segment_visuals.size() == source.limb_definitions[0].segments.size()
		and shape_editor.joint_visuals.size() == source.limb_definitions[0].segments.size()
		and shape_editor.rotation_ring_visuals.size() == 3,
		"limb viewport builds selectable joints and three rotation rings"
	)
	shape_editor.queue_free()

	var core_preview: MLBodyCoreLayoutPreview = MLBodyCoreLayoutPreview.new()
	root.add_child(core_preview)
	await process_frame
	var core: DroneCoreDefinition = DroneCoreDefinition.new()
	core.set_model_orientation(Vector3.RIGHT, Vector3.BACK)
	core_preview.set_core_resource(core)
	await process_frame
	_expect(
		core_preview.orientation_root != null
		and core_preview.orientation_root.get_child_count() == 6,
		"Core viewport renders forward and up arrows from the serialized worker frame"
	)
	core_preview.queue_free()


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failures += 1
	push_error(message)
