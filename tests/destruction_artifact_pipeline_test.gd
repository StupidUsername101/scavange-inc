extends SceneTree

## Deterministic stage trace for the artifact cleanup. Unlike the older contour test, this records
## the exact geometry presented by DestructibleVolume3D after shell handling and runtime mutation.

const MeshAudit := preload("res://tests/helpers/destruction_mesh_audit.gd")
const FIXTURE_SEEDS := [73111, 73173, 73237, 73309]

var assertion_count := 0
var failure_count := 0
var test_root: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = Node3D.new()
	root.add_child(test_root)
	await process_frame
	for fixture_index: int in range(FIXTURE_SEEDS.size()):
		_run_fixture(fixture_index, FIXTURE_SEEDS[fixture_index])
	_finish()


func _run_fixture(fixture_index: int, seed: int) -> void:
	var volume := DestructibleVolume3D.new()
	volume.name = "ArtifactFixture_%d" % fixture_index
	volume.volume_id = StringName(volume.name.to_snake_case())
	volume.authoritative = false
	volume.create_collision = false
	volume.physical_surface = &"metal" if fixture_index % 2 == 0 else &"concrete"
	volume.volume_size = Vector3(4.0, 3.0, 0.45)
	volume.voxel_size = 0.06
	volume.brick_cells = 16
	test_root.add_child(volume)
	volume.initialize_volume()
	var texture := DestructionMaterialRegistry.profile_for(volume.physical_surface).duplicate(true)
	texture.spatial_warp = minf(maxf(texture.spatial_warp, 0.55), 0.8)
	texture.crack_count = 0
	texture.sanitize()
	var event_packets: Array[Dictionary] = []
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var event_count := int([12, 1, 12, 4][fixture_index])
	for event_index: int in range(event_count):
		var progress := float(event_index) / float(maxi(event_count - 1, 1))
		var point: Vector3
		var direction: Vector3
		match fixture_index:
			0:
				point = Vector3(lerpf(-1.55, 1.55, progress), 0.62, 0.225)
				direction = Vector3(0.0, -0.05, -1.0).normalized()
			1:
				# A single off-centre impact isolates the chunk-boundary regression without
				# deliberately creating a zero-width overlapping-brush singularity first.
				point = Vector3(0.41, -0.33, 0.225)
				direction = Vector3(0.0, 0.0, -1.0)
			2:
				point = Vector3(
					random.randf_range(-1.65, 1.65),
					random.randf_range(-1.15, 1.15),
					0.225
				)
				direction = Vector3(
					random.randf_range(-0.22, 0.22),
					random.randf_range(-0.22, 0.22),
					-1.0
				).normalized()
			_:
				var lane := event_index % 4
				point = Vector3(
					lerpf(-1.75, 1.75, progress),
					-0.72 + float(lane) * 0.48,
					0.225
				)
				direction = Vector3(0.16 if lane % 2 == 0 else -0.16, 0.0, -1.0).normalized()
		var packet := _damage_event(seed, event_index, point, direction).to_dict(false)
		event_packets.append(packet)
		volume.field.apply_damage_event(
			point,
			direction,
			Vector3.BACK,
			DamageEvent.from_dict(packet),
			texture
		)

	var stages := _capture_stages(volume)
	var audits: Dictionary[StringName, Dictionary] = {}
	for stage_name: StringName in stages:
		audits[stage_name] = MeshAudit.audit_results(
			stages[stage_name],
			volume.field,
			volume.voxel_size * 0.0001,
			false
		)
	print("Destruction artifact fixture %d seed %d: %s" % [fixture_index, seed, audits])
	var raw_audit := audits[&"raw"]
	var shell_audit := audits[&"shell"]
	var seam_audit := audits[&"legacy_runtime_seam"]
	var sanitized_audit := audits[&"legacy_runtime_sanitized"]
	var first_invalid_stage := _first_invalid_stage(audits)
	if not first_invalid_stage.is_empty():
		var trace_path := "res://tests/fixtures/destruction-artifact-%d" % seed
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/fixtures"))
		MeshAudit.write_trace(trace_path, {
			"fixture_index": fixture_index,
			"seed": seed,
			"profile": str(volume.physical_surface),
			"bake_hash": volume.bake_hash(),
			"field_revision": volume.field.revision,
			"field_checksum": volume.field.checksum(),
			"events": event_packets,
			"first_invalid_stage": str(first_invalid_stage),
		}, stages)
	_expect(
		MeshAudit.is_closed_valid(raw_audit)
		and MeshAudit.is_closed_valid(shell_audit),
		"fixture %d starts with closed valid globally-owned raw/shell topology: raw=%s shell=%s"
		% [fixture_index, raw_audit, shell_audit]
	)
	# These two observations pin the pre-cleanup mechanism. Once production no longer invokes them,
	# this test still prevents somebody from quietly restoring the old post-extraction mutation.
	_expect(
		int(seam_audit.get("triangle_count", 0)) > 0
		and int(sanitized_audit.get("triangle_count", 0)) > 0
		and int(seam_audit.get("boundary_edges", 0))
		> int(shell_audit.get("boundary_edges", 0))
		and MeshAudit.is_closed_valid(audits[&"production_final"]),
		"fixture %d proves the removed legacy seam mutation opens edges while production preserves shell topology"
		% fixture_index
	)
	volume.queue_free()


func _capture_stages(volume: DestructibleVolume3D) -> Dictionary[StringName, Array]:
	var stages: Dictionary[StringName, Array] = {
		&"raw": [],
		&"shell": [],
		&"legacy_runtime_seam": [],
		&"legacy_runtime_sanitized": [],
		&"production_final": [],
	}
	for z: int in range(volume.field.brick_counts.z):
		for y: int in range(volume.field.brick_counts.y):
			for x: int in range(volume.field.brick_counts.x):
				var coordinate := Vector3i(x, y, z)
				var snapshot := SdfDualContouringMesher.capture_chunk(volume.field, coordinate)
				var raw := SdfDualContouringMesher.build_chunk_snapshot(snapshot)
				var shell := SdfDualContouringMesher.finalize_box_shell(
					MeshAudit.clone_result(raw), snapshot
				)
				var seam: Dictionary = MeshAudit.clone_result(shell)
				_apply_legacy_runtime_seam(volume, seam, coordinate)
				var sanitized: Dictionary = MeshAudit.clone_result(seam)
				SdfDualContouringMesher.legacy_sanitize_after_vertex_edit_for_test(sanitized)
				(stages[&"raw"] as Array).append(raw)
				(stages[&"shell"] as Array).append(shell)
				(stages[&"legacy_runtime_seam"] as Array).append(seam)
				(stages[&"legacy_runtime_sanitized"] as Array).append(sanitized)
				(stages[&"production_final"] as Array).append(
					MeshAudit.clone_result(shell)
				)
	return stages


func _first_invalid_stage(audits: Dictionary[StringName, Dictionary]) -> StringName:
	for stage_name: StringName in [&"raw", &"shell", &"production_final"]:
		if not MeshAudit.is_closed_valid(audits[stage_name]):
			return stage_name
	return &""


func _apply_legacy_runtime_seam(
	volume: DestructibleVolume3D,
	result: Dictionary,
	coordinate: Vector3i
) -> void:
	# Retained solely as a test oracle for the minimized pre-cleanup failure. Production no longer
	# owns this operation. Keeping it beside the fixture prevents the diagnosed regression from being
	# forgotten without carrying dead geometry mutation code in DestructibleVolume3D.
	if bool(result.get("empty", true)) or not result.has("vertices"):
		return
	var vertices: PackedVector3Array = result["vertices"]
	var minimum := volume.field.brick_origin(coordinate)
	var maximum := Vector3(
		minf(minimum.x + volume.field.brick_extent, volume.field.half_extents.x),
		minf(minimum.y + volume.field.brick_extent, volume.field.half_extents.y),
		minf(minimum.z + volume.field.brick_extent, volume.field.half_extents.z)
	)
	var shell_tolerance := maxf(volume.field.voxel_size * 0.01, 0.00001)
	var seam_band := volume.field.voxel_size * 0.55
	for index: int in range(vertices.size()):
		var vertex := vertices[index]
		if absf(volume.field.base_distance(vertex)) > shell_tolerance:
			continue
		var on_x_shell := absf(absf(vertex.x) - volume.field.half_extents.x) <= shell_tolerance
		var on_y_shell := absf(absf(vertex.y) - volume.field.half_extents.y) <= shell_tolerance
		var on_z_shell := absf(absf(vertex.z) - volume.field.half_extents.z) <= shell_tolerance
		if not on_x_shell:
			vertex.x = (
				minimum.x if vertex.x <= minimum.x + seam_band
				else maximum.x if vertex.x >= maximum.x - seam_band
				else vertex.x
			)
		if not on_y_shell:
			vertex.y = (
				minimum.y if vertex.y <= minimum.y + seam_band
				else maximum.y if vertex.y >= maximum.y - seam_band
				else vertex.y
			)
		if not on_z_shell:
			vertex.z = (
				minimum.z if vertex.z <= minimum.z + seam_band
				else maximum.z if vertex.z >= maximum.z - seam_band
				else vertex.z
			)
		vertices[index] = vertex
	result["vertices"] = vertices


func _damage_event(seed: int, index: int, point: Vector3, direction: Vector3) -> DamageEvent:
	var event_id := seed * 100 + index
	return DamageEvent.from_dict({
		"event_id": event_id,
		"sequence": event_id,
		"source_kind": &"artifact_fixture",
		"source_id": 1,
		"world_position": point,
		"normal": Vector3.BACK,
		"direction": direction,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.075,
		"length": 0.72,
		"energy": 18.0,
		"impulse": 0.0,
		"penetration": 0.72,
		"heat": 1.0,
		"damage_tags": PackedStringArray(["blade", "heat"]),
		"seed": event_id,
	})


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", label)
		return
	failure_count += 1
	push_error("FAIL: %s" % label)


func _finish() -> void:
	print("Destruction artifact pipeline: %d assertions, %d failures" % [
		assertion_count, failure_count,
	])
	quit(1 if failure_count > 0 else 0)
