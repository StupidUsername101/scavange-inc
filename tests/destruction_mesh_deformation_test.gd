extends SceneTree

## Directional black-box coverage for the complete damage -> SDF -> presented ArrayMesh path.
## Unlike checksum/topology tests, every shot produces a geometric report that can explain whether
## matter moved along the gun ray, whether yaw/pitch agree, and whether untouched neighboring shell
## survived. The helper accepts any Mesh; these fixtures use both PrimitiveMesh and ArrayMesh inputs.

const ImpactAudit := preload("res://tests/helpers/destruction_impact_audit.gd")

var assertion_count := 0
var failure_count := 0
var test_root: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = Node3D.new()
	test_root.name = "DestructionMeshDeformationTest"
	root.add_child(test_root)
	await process_frame
	_test_multi_angle_box_mesh()
	_test_rotated_array_mesh_and_negative_direction_control()
	_test_subthreshold_shot_does_not_claim_mesh_deformation()
	_finish()


func _test_multi_angle_box_mesh() -> void:
	var volume := _make_volume(&"deformation_box", Transform3D.IDENTITY)
	var reference := BoxMesh.new()
	reference.size = volume.volume_size
	var shots: Array[Dictionary] = []
	var local_shots: Array[Dictionary] = [
		{"point": Vector3(-0.72, 0.43, volume.volume_size.z * 0.5), "direction": Vector3(0.0, 0.0, -1.0)},
		{"point": Vector3(0.02, -0.36, volume.volume_size.z * 0.5), "direction": Vector3(0.24, 0.0, -1.0).normalized()},
		{"point": Vector3(0.68, 0.34, volume.volume_size.z * 0.5), "direction": Vector3(-0.18, -0.13, -1.0).normalized()},
	]
	for index: int in range(local_shots.size()):
		var authored := local_shots[index]
		var direction: Vector3 = authored["direction"]
		var point: Vector3 = authored["point"]
		shots.append({
			"world_origin": volume.to_global(point - direction * 0.8),
			"world_direction": (volume.global_basis * direction).normalized(),
			"sequence": 81000 + index,
			"seed": 91000 + index,
		})
	var reports := ImpactAudit.shoot_many(volume, reference, shots, _shot_defaults())
	_expect(reports.size() == 3, "the reusable runner returns one report per authored shot")
	for report_index: int in range(reports.size()):
		var report := reports[report_index]
		print(
			"MESH_DEFORMATION_REPORT box shot ",
			report_index,
			": ",
			ImpactAudit.format_report(report)
		)
		_expect(
			bool((report.get("apply_result", {}) as Dictionary).get("geometry_changed", false)),
			"box shot %d reaches the production geometry path" % report_index
		)
		_expect(
			bool(report.get("field_modified", false))
			and bool(report.get("mesh_modified", false))
			and int(report.get("changed_mesh_vertex_count", 0)) > 4,
			"box shot %d changes both sampled matter and the presented mesh" % report_index
		)
		_expect(
			bool(report.get("direction_matches", false))
			and bool(report.get("yaw_matches", false))
			and bool(report.get("pitch_matches", false)),
			"box shot %d deformation follows its impact direction, yaw, and pitch: %s"
			% [report_index, _direction_summary(report)]
		)
		_expect(
			float(report.get("field_ray_clear_fraction", 0.0)) >= 0.82
			and float(report.get("off_axis_intact_fraction", 0.0)) >= 0.75,
			"box shot %d opens its own ray while preserving neighboring shell" % report_index
		)
		_expect(
			ImpactAudit.report_matches(report),
			"box shot %d satisfies the complete deformation contract" % report_index
		)
	volume.queue_free()


func _test_rotated_array_mesh_and_negative_direction_control() -> void:
	var rotated := Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(-8.0), deg_to_rad(37.0), deg_to_rad(4.0))),
		Vector3(5.0, 1.2, -3.0)
	)
	var volume := _make_volume(&"deformation_rotated_array_mesh", rotated)
	var primitive := BoxMesh.new()
	primitive.size = volume.volume_size
	var reference := _copy_as_array_mesh(primitive)
	var local_direction := Vector3(0.22, 0.16, -1.0).normalized()
	var local_point := Vector3(-0.20, 0.12, volume.volume_size.z * 0.5)
	var expected_world := (volume.global_basis * local_direction).normalized()
	var report := ImpactAudit.shoot(volume, reference, _shot_defaults().merged({
		"world_origin": volume.to_global(local_point - local_direction * 0.9),
		"world_direction": expected_world,
		"sequence": 82001,
		"seed": 92001,
	}, true))
	print(
		"MESH_DEFORMATION_REPORT rotated ArrayMesh: ",
		ImpactAudit.format_report(report)
	)
	_expect(
		ImpactAudit.report_matches(report),
		"the generic Mesh input and world/local transforms preserve directional deformation"
	)
	_expect(
		ImpactAudit.direction_matches(report, expected_world, 14.0),
		"the measured world-space deformation agrees with the rotated gun ray"
	)
	var deliberately_wrong_direction := expected_world.rotated(Vector3.UP, deg_to_rad(65.0))
	_expect(
		not ImpactAudit.direction_matches(report, deliberately_wrong_direction, 14.0),
		"the oracle rejects a deliberately wrong yaw instead of passing every changed mesh"
	)
	volume.queue_free()


func _test_subthreshold_shot_does_not_claim_mesh_deformation() -> void:
	var volume := _make_volume(&"deformation_noop_control", Transform3D.IDENTITY)
	var reference := BoxMesh.new()
	reference.size = volume.volume_size
	var local_direction := Vector3(0.0, 0.0, -1.0)
	var local_point := Vector3(0.0, 0.0, volume.volume_size.z * 0.5)
	var report := ImpactAudit.shoot(volume, reference, _shot_defaults().merged({
		"world_origin": local_point - local_direction * 0.8,
		"world_direction": local_direction,
		"energy": 0.01,
		"sequence": 83001,
		"seed": 93001,
	}, true))
	print(
		"MESH_DEFORMATION_REPORT subthreshold control: ",
		ImpactAudit.format_report(report)
	)
	var apply_result: Dictionary = report.get("apply_result", {})
	_expect(
		not bool(apply_result.get("geometry_changed", false)),
		"a subthreshold shot does not enter visible geometry rebuilding"
	)
	_expect(
		not bool(report.get("field_modified", true))
		and not bool(report.get("mesh_modified", true))
		and not ImpactAudit.report_matches(report),
		"the verifier does not confuse fatigue bookkeeping with mesh deformation"
	)
	volume.queue_free()


func _make_volume(volume_id: StringName, transform: Transform3D) -> DestructibleVolume3D:
	var profile := DestructionMaterialRegistry.profile_for(&"concrete").duplicate(true)
	# Direction is the subject of this suite. Disable intentionally lateral material character here;
	# production warp/crack topology remains covered by universal_destruction_system_test.gd.
	profile.spatial_warp = 0.0
	profile.crack_count = 0
	profile.maximum_physical_fragments = 0
	profile.sanitize()
	var volume := DestructibleVolume3D.new()
	volume.name = str(volume_id)
	volume.volume_id = volume_id
	volume.transform = transform
	volume.authoritative = true
	volume.create_collision = false
	volume.volume_size = Vector3(3.2, 2.4, 0.5)
	volume.voxel_size = 0.05
	volume.brick_cells = 10
	volume.remesh_neighbor_ring = 1
	volume.destruction_texture = profile
	test_root.add_child(volume)
	volume.initialize_volume()
	return volume


func _shot_defaults() -> Dictionary:
	return {
		"radius": 0.055,
		"length": 0.9,
		"energy": 16.0,
		"impulse": 2.0,
		"penetration": 0.9,
		"damage_tags": PackedStringArray([DamageEvent.TAG_BALLISTIC]),
		"maximum_angle_error_degrees": 14.0,
		"maximum_outlier_fraction": 0.38,
	}


func _copy_as_array_mesh(source: Mesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface_index: int in range(source.get_surface_count()):
		result.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			source.surface_get_arrays(surface_index)
		)
	return result


func _direction_summary(report: Dictionary) -> String:
	return "angle=%.2fdeg yaw=%.2fdeg pitch=%.2fdeg outliers=%.3f" % [
		float(report.get("direction_angle_error_degrees", 180.0)),
		float(report.get("yaw_error_degrees", 180.0)),
		float(report.get("pitch_error_degrees", 180.0)),
		float(report.get("corridor_outlier_fraction", 1.0)),
	]


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	print(
		"Destruction mesh deformation: %d assertions, %d failures"
		% [assertion_count, failure_count]
	)
	quit(1 if failure_count > 0 else 0)
