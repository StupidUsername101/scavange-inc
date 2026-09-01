class_name DestructionImpactAudit
extends RefCounted

## Test-only black-box verifier for destructive impacts. It accepts any Godot Mesh as the pristine
## reference, fires real DamageEvents through a DestructibleVolume3D, then measures both the sparse
## field delta and the ArrayMesh actually presented by the volume. Nothing here is used at runtime.
##
## The reference mesh and volume must describe the same pristine object in the volume's local space.
## That condition is intentional: passing an imported mesh to a box-only volume should fail loudly
## instead of letting a test silently validate the wrong source geometry.

const MIN_DIRECTION_LENGTH_SQUARED := 0.000001
const RAY_EPSILON := 0.00001
const DEFAULT_MAXIMUM_ANGLE_ERROR_DEGREES := 14.0
const DEFAULT_MAXIMUM_OUTLIER_FRACTION := 0.38


static func shoot_many(
	volume: DestructibleVolume3D,
	pristine_mesh: Mesh,
	shots: Array[Dictionary],
	defaults: Dictionary = {}
) -> Array[Dictionary]:
	var reports: Array[Dictionary] = []
	for shot_index: int in range(shots.size()):
		var config := defaults.duplicate(true)
		config.merge(shots[shot_index], true)
		config["shot_index"] = shot_index
		reports.append(shoot(volume, pristine_mesh, config))
	return reports


static func shoot(
	volume: DestructibleVolume3D,
	pristine_mesh: Mesh,
	config: Dictionary
) -> Dictionary:
	if volume == null or pristine_mesh == null:
		return _failure(&"missing_target")
	if volume.field == null:
		volume.initialize_volume()
	var world_origin: Vector3 = config.get("world_origin", Vector3.ZERO)
	var world_direction: Vector3 = config.get("world_direction", Vector3.FORWARD)
	if world_direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return _failure(&"invalid_direction")
	world_direction = world_direction.normalized()
	var local_origin := volume.to_local(world_origin)
	var local_direction := volume.global_basis.inverse() * world_direction
	if local_direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return _failure(&"invalid_local_direction")
	local_direction = local_direction.normalized()

	var reference_transform: Transform3D = config.get(
		"reference_transform",
		Transform3D.IDENTITY
	)
	var pristine := capture_mesh(pristine_mesh, reference_transform)
	var pristine_hits := ray_intersections(pristine, local_origin, local_direction)
	if pristine_hits.is_empty():
		var miss := _failure(&"reference_ray_miss")
		miss["world_origin"] = world_origin
		miss["world_direction"] = world_direction
		return miss
	var entry: Dictionary = pristine_hits[0]
	var entry_t := float(entry.get("distance", 0.0))
	var local_impact := local_origin + local_direction * entry_t
	var local_normal: Vector3 = entry.get("normal", -local_direction)
	if local_normal.dot(local_direction) > 0.0:
		local_normal = -local_normal
	var exit_t := entry_t
	var exit_normal := -local_normal
	if pristine_hits.size() >= 2:
		exit_t = float(pristine_hits[1].get("distance", entry_t))
		exit_normal = pristine_hits[1].get("normal", -local_normal)
		if exit_normal.dot(local_direction) < 0.0:
			exit_normal = -exit_normal
	var pristine_path_length := maxf(exit_t - entry_t, 0.0)
	var local_exit := local_origin + local_direction * exit_t

	var before_field := capture_field(volume.field)
	var sequence := int(config.get("sequence", 70000 + int(config.get("shot_index", 0))))
	var event := DamageEvent.from_dict({
		"event_id": int(config.get("event_id", sequence)),
		"sequence": sequence,
		"source_kind": config.get("source_kind", &"mesh_deformation_test"),
		"source_id": int(config.get("source_id", 81)),
		"world_position": volume.to_global(local_impact),
		"normal": (volume.global_basis * local_normal).normalized(),
		"direction": world_direction,
		"brush_kind": config.get("brush_kind", DamageEvent.BRUSH_CAPSULE),
		"radius": float(config.get("radius", 0.055)),
		"length": float(config.get("length", config.get("penetration", 0.9))),
		"energy": float(config.get("energy", 16.0)),
		"impulse": float(config.get("impulse", 2.0)),
		"penetration": float(config.get("penetration", 0.9)),
		"heat": float(config.get("heat", 0.0)),
		"damage_tags": config.get(
			"damage_tags",
			PackedStringArray([DamageEvent.TAG_BALLISTIC])
		),
		"seed": int(config.get("seed", sequence)),
		"timestamp_tick": int(config.get("timestamp_tick", 1)),
	})
	var apply_result := volume.apply_authoritative_damage_event(event)
	volume.flush_pending_rebuilds()
	var after_field := capture_field(volume.field)
	var presented := capture_volume_surface(volume, pristine)
	var report := audit_deformation(
		volume,
		pristine,
		presented,
		before_field,
		after_field,
		local_impact,
		local_normal,
		local_exit,
		exit_normal,
		local_direction,
		entry_t,
		pristine_path_length,
		event,
		config
	)
	report["ok"] = true
	report["apply_result"] = apply_result
	# Energy only authorizes a channel attempt. Density, bulk strength, impact angle, and actual
	# target thickness decide whether that channel reaches the far surface.
	report["expects_perforation"] = bool(apply_result.get("perforated", false))
	report["event"] = event.to_dict(false)
	report["reference_intersection_count"] = pristine_hits.size()
	report["impact_position"] = local_impact
	report["impact_normal"] = local_normal
	return report


static func audit_deformation(
	volume: DestructibleVolume3D,
	pristine: Dictionary,
	presented: Dictionary,
	before_field: PackedFloat32Array,
	after_field: PackedFloat32Array,
	local_impact: Vector3,
	local_impact_normal: Vector3,
	local_exit: Vector3,
	local_exit_normal: Vector3,
	local_direction: Vector3,
	entry_ray_distance: float,
	pristine_path_length: float,
	event: DamageEvent,
	config: Dictionary = {}
) -> Dictionary:
	var field := volume.field
	var changed_positions := PackedVector3Array()
	var changed_weights := PackedFloat32Array()
	var changed_bounds := AABB()
	var has_changed_bounds := false
	# Sparse bricks quantize their narrow band when first allocated. Comparing raw distance magnitude
	# would therefore report an untouched, newly allocated brick as deformation. A removal is the
	# invariant the renderer cares about: a sample that was matter before and air afterwards.
	var change_threshold := maxf(field.voxel_size * 0.015, 0.0001)
	var sample_index := 0
	for z: int in range(field.total_cells.z + 1):
		for y: int in range(field.total_cells.y + 1):
			for x: int in range(field.total_cells.x + 1):
				if sample_index >= before_field.size() or sample_index >= after_field.size():
					break
				var before := before_field[sample_index]
				var after := after_field[sample_index]
				var delta := after - before
				sample_index += 1
				if before > 0.0 or after <= 0.0 or delta <= change_threshold:
					continue
				var position := field.global_sample_position(Vector3i(x, y, z))
				changed_positions.append(position)
				changed_weights.append(delta)
				if not has_changed_bounds:
					changed_bounds = AABB(position, Vector3.ZERO)
					has_changed_bounds = true
				else:
					changed_bounds = changed_bounds.expand(position)

	var response_radius := event.radius
	var profile := volume.get("_profile") as DestructionTextureDefinition
	if profile != null:
		response_radius = profile.response_radius(event.radius, event.energy)
	var locality_radius := maxf(
		float(config.get("locality_radius", response_radius * 3.5)),
		field.voxel_size * 2.0
	)
	var direction_measurement := _measure_direction(
		changed_positions,
		changed_weights,
		local_impact,
		local_direction,
		locality_radius,
		field.voxel_size
	)
	var aperture_measurement := _measure_aperture_axis(
		field,
		local_impact,
		local_impact_normal,
		local_exit,
		local_exit_normal,
		local_direction,
		locality_radius
	)
	var channel_measurement := _measure_channel_axis(
		field,
		local_impact,
		local_direction,
		pristine_path_length,
		maxf(response_radius * 1.6, field.voxel_size * 2.0)
	)
	var measured_local: Vector3 = direction_measurement.get(
		"measured_direction",
		Vector3.ZERO
	)
	# Exterior spall is intentionally asymmetric and can bias a point-cloud PCA. Entry/exit aperture
	# centroids measure the actual channel through the mesh and therefore own yaw/pitch whenever both
	# sides of the pristine mesh were intersected. The cloud result remains in the report as a useful
	# material-response diagnostic.
	var aperture_direction: Vector3 = aperture_measurement.get("measured_direction", Vector3.ZERO)
	var channel_direction: Vector3 = channel_measurement.get("measured_direction", Vector3.ZERO)
	if channel_direction.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
		measured_local = channel_direction
	elif aperture_direction.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
		measured_local = aperture_direction
	var expected_world := (volume.global_basis * local_direction).normalized()
	var measured_world := (
		(volume.global_basis * measured_local).normalized()
		if measured_local.length_squared() > MIN_DIRECTION_LENGTH_SQUARED
		else Vector3.ZERO
	)
	var angle_error := (
		rad_to_deg(acos(clampf(expected_world.dot(measured_world), -1.0, 1.0)))
		if measured_world.length_squared() > MIN_DIRECTION_LENGTH_SQUARED
		else 180.0
	)
	var expected_yaw_pitch := _yaw_pitch_degrees(expected_world)
	var measured_yaw_pitch := _yaw_pitch_degrees(measured_world)
	var yaw_error := absf(_wrapped_degrees(
		measured_yaw_pitch.x - expected_yaw_pitch.x
	))
	var pitch_error := absf(measured_yaw_pitch.y - expected_yaw_pitch.y)

	var corridor_outliers := 0
	var centroid := Vector3.ZERO
	var total_weight := 0.0
	for point_index: int in range(changed_positions.size()):
		var point := changed_positions[point_index]
		var weight := maxf(changed_weights[point_index], change_threshold)
		centroid += point * weight
		total_weight += weight
		var projection := (point - local_impact).dot(local_direction)
		var closest := local_impact + local_direction * maxf(projection, 0.0)
		if point.distance_to(closest) > locality_radius:
			corridor_outliers += 1
	if total_weight > 0.0:
		centroid /= total_weight
	var centroid_projection := (centroid - local_impact).dot(local_direction)
	var centroid_on_ray := local_impact + local_direction * centroid_projection
	var centroid_ray_error := centroid.distance_to(centroid_on_ray)
	var outlier_fraction := (
		float(corridor_outliers) / float(changed_positions.size())
		if not changed_positions.is_empty()
		else 1.0
	)

	var surface_tolerance := maxf(field.voxel_size * 0.42, 0.001)
	var changed_mesh_vertices := _count_changed_mesh_vertices(
		pristine,
		presented,
		local_impact,
		local_direction,
		maxf(pristine_path_length, event.penetration) + locality_radius,
		locality_radius,
		surface_tolerance
	)
	var pristine_checksum := int(pristine.get("checksum", 0))
	var presented_checksum := int(presented.get("checksum", 0))
	var mesh_modified := (
		changed_mesh_vertices > 0
		and pristine_checksum != presented_checksum
	)

	var field_path := _field_path_clear_fraction(
		field,
		local_impact,
		local_direction,
		pristine_path_length
	)
	var post_origin := local_impact - local_direction * maxf(field.voxel_size * 2.0, 0.02)
	var post_hits := ray_intersections(presented, post_origin, local_direction)
	var off_axis_intact := _off_axis_intact_fraction(
		pristine,
		presented,
		post_origin,
		local_direction,
		locality_radius,
		entry_ray_distance
	)
	var max_angle := float(config.get(
		"maximum_angle_error_degrees",
		DEFAULT_MAXIMUM_ANGLE_ERROR_DEGREES
	))
	var max_outliers := float(config.get(
		"maximum_outlier_fraction",
		DEFAULT_MAXIMUM_OUTLIER_FRACTION
	))
	return {
		"field_modified": not changed_positions.is_empty(),
		"mesh_modified": mesh_modified,
		"changed_sample_count": changed_positions.size(),
		"changed_mesh_vertex_count": changed_mesh_vertices,
		"pristine_mesh_checksum": pristine_checksum,
		"presented_mesh_checksum": presented_checksum,
		"expected_direction": expected_world,
		"measured_direction": measured_world,
		"changed_cloud_direction": (
			(volume.global_basis * (direction_measurement.get(
				"measured_direction",
				Vector3.ZERO
			) as Vector3)).normalized()
			if (direction_measurement.get("measured_direction", Vector3.ZERO) as Vector3).length_squared()
			> MIN_DIRECTION_LENGTH_SQUARED
			else Vector3.ZERO
		),
		"entry_aperture_centroid": aperture_measurement.get(
			"entry_centroid",
			local_impact
		),
		"exit_aperture_centroid": aperture_measurement.get("exit_centroid", local_exit),
		"entry_aperture_samples": int(aperture_measurement.get("entry_samples", 0)),
		"exit_aperture_samples": int(aperture_measurement.get("exit_samples", 0)),
		"channel_near_centroid": channel_measurement.get("near_centroid", local_impact),
		"channel_far_centroid": channel_measurement.get("far_centroid", local_exit),
		"channel_near_samples": int(channel_measurement.get("near_samples", 0)),
		"channel_far_samples": int(channel_measurement.get("far_samples", 0)),
		"expected_yaw_degrees": expected_yaw_pitch.x,
		"measured_yaw_degrees": measured_yaw_pitch.x,
		"expected_pitch_degrees": expected_yaw_pitch.y,
		"measured_pitch_degrees": measured_yaw_pitch.y,
		"direction_angle_error_degrees": angle_error,
		"yaw_error_degrees": yaw_error,
		"pitch_error_degrees": pitch_error,
		"direction_matches": angle_error <= max_angle,
		"yaw_matches": yaw_error <= max_angle,
		"pitch_matches": pitch_error <= max_angle,
		"changed_centroid": centroid,
		"centroid_ray_error": centroid_ray_error,
		"changed_bounds": changed_bounds if has_changed_bounds else AABB(),
		"forward_extent": float(direction_measurement.get("forward_extent", 0.0)),
		"backward_extent": float(direction_measurement.get("backward_extent", 0.0)),
		"corridor_outlier_fraction": outlier_fraction,
		"locality_matches": outlier_fraction <= max_outliers,
		"pristine_path_length": pristine_path_length,
		"field_ray_clear_fraction": field_path,
		"post_impact_ray_intersections": post_hits.size(),
		"off_axis_intact_fraction": off_axis_intact,
		"expects_perforation": false,
	}


static func capture_field(field: SparseSdfVolumeData) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if field == null:
		return result
	var sample_count := (
		(field.total_cells.x + 1)
		* (field.total_cells.y + 1)
		* (field.total_cells.z + 1)
	)
	result.resize(sample_count)
	var index := 0
	for z: int in range(field.total_cells.z + 1):
		for y: int in range(field.total_cells.y + 1):
			for x: int in range(field.total_cells.x + 1):
				result[index] = field.distance_at_global_sample(Vector3i(x, y, z))
				index += 1
	return result


static func capture_volume_surface(
	volume: DestructibleVolume3D,
	fallback: Dictionary = {}
) -> Dictionary:
	var captures: Array[Dictionary] = []
	var generated: Dictionary = volume.get("_generated_visuals")
	for visual_value: Variant in generated.values():
		var visual := visual_value as MeshInstance3D
		if visual == null or visual.mesh == null or not visual.visible:
			continue
		captures.append(capture_mesh(visual.mesh, visual.transform))
	if captures.is_empty():
		return fallback
	return combine_captures(captures)


static func capture_mesh(mesh: Mesh, transform := Transform3D.IDENTITY) -> Dictionary:
	var vertices := PackedVector3Array()
	var triangles := PackedVector3Array()
	if mesh == null:
		return {"vertices": vertices, "triangles": triangles, "checksum": 0}
	for surface_index: int in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var transformed := PackedVector3Array()
		transformed.resize(surface_vertices.size())
		for vertex_index: int in range(surface_vertices.size()):
			transformed[vertex_index] = transform * surface_vertices[vertex_index]
		vertices.append_array(transformed)
		if surface_indices.is_empty():
			for offset: int in range(0, transformed.size() - 2, 3):
				triangles.append(transformed[offset])
				triangles.append(transformed[offset + 1])
				triangles.append(transformed[offset + 2])
		else:
			for offset: int in range(0, surface_indices.size() - 2, 3):
				var first := surface_indices[offset]
				var second := surface_indices[offset + 1]
				var third := surface_indices[offset + 2]
				if (
					first < 0 or first >= transformed.size()
					or second < 0 or second >= transformed.size()
					or third < 0 or third >= transformed.size()
				):
					continue
				triangles.append(transformed[first])
				triangles.append(transformed[second])
				triangles.append(transformed[third])
	return {
		"vertices": vertices,
		"triangles": triangles,
		"checksum": hash(vertices),
	}


static func combine_captures(captures: Array[Dictionary]) -> Dictionary:
	var vertices := PackedVector3Array()
	var triangles := PackedVector3Array()
	for capture: Dictionary in captures:
		vertices.append_array(capture.get("vertices", PackedVector3Array()))
		triangles.append_array(capture.get("triangles", PackedVector3Array()))
	return {
		"vertices": vertices,
		"triangles": triangles,
		"checksum": hash(vertices),
	}


static func ray_intersections(
	capture: Dictionary,
	origin: Vector3,
	direction: Vector3
) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return hits
	var ray := direction.normalized()
	var triangles: PackedVector3Array = capture.get("triangles", PackedVector3Array())
	for offset: int in range(0, triangles.size() - 2, 3):
		var hit := _ray_triangle(origin, ray, triangles[offset], triangles[offset + 1], triangles[offset + 2])
		if hit.is_empty():
			continue
		var distance := float(hit.get("distance", -1.0))
		var duplicate := false
		for existing: Dictionary in hits:
			if absf(float(existing.get("distance", 0.0)) - distance) <= RAY_EPSILON:
				duplicate = true
				break
		if not duplicate:
			hits.append(hit)
	hits.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("distance", 0.0)) < float(right.get("distance", 0.0))
	)
	return hits


static func report_matches(
	report: Dictionary,
	maximum_angle_error_degrees := DEFAULT_MAXIMUM_ANGLE_ERROR_DEGREES,
	minimum_ray_clear_fraction := 0.82,
	minimum_off_axis_intact_fraction := 0.75
) -> bool:
	var apply_result: Dictionary = report.get("apply_result", {})
	var geometry_committed := (
		bool(apply_result.get("geometry_changed", false))
		if not apply_result.is_empty()
		else true
	)
	var perforation_matches := (
		(
			float(report.get("field_ray_clear_fraction", 0.0)) >= minimum_ray_clear_fraction
			and int(report.get("post_impact_ray_intersections", 1)) == 0
		)
		if bool(report.get("expects_perforation", false))
		else true
	)
	return (
		bool(report.get("ok", false))
		and geometry_committed
		and bool(report.get("field_modified", false))
		and bool(report.get("mesh_modified", false))
		and float(report.get("direction_angle_error_degrees", 180.0))
		<= maximum_angle_error_degrees
		and float(report.get("yaw_error_degrees", 180.0)) <= maximum_angle_error_degrees
		and float(report.get("pitch_error_degrees", 180.0)) <= maximum_angle_error_degrees
		and bool(report.get("locality_matches", false))
		and perforation_matches
		and float(report.get("off_axis_intact_fraction", 0.0))
		>= minimum_off_axis_intact_fraction
	)


static func format_report(report: Dictionary) -> String:
	return (
		"mesh=%s field=%s samples=%d new_vertices=%d "
		+ "yaw=%.2f->%.2f (err %.2fdeg) pitch=%.2f->%.2f (err %.2fdeg) "
		+ "axis_err=%.2fdeg clear=%.3f off_axis_intact=%.3f outliers=%.3f"
	) % [
		str(bool(report.get("mesh_modified", false))),
		str(bool(report.get("field_modified", false))),
		int(report.get("changed_sample_count", 0)),
		int(report.get("changed_mesh_vertex_count", 0)),
		float(report.get("expected_yaw_degrees", 180.0)),
		float(report.get("measured_yaw_degrees", 180.0)),
		float(report.get("yaw_error_degrees", 180.0)),
		float(report.get("expected_pitch_degrees", 180.0)),
		float(report.get("measured_pitch_degrees", 180.0)),
		float(report.get("pitch_error_degrees", 180.0)),
		float(report.get("direction_angle_error_degrees", 180.0)),
		float(report.get("field_ray_clear_fraction", 0.0)),
		float(report.get("off_axis_intact_fraction", 0.0)),
		float(report.get("corridor_outlier_fraction", 1.0)),
	]


static func direction_matches(
	report: Dictionary,
	expected_world_direction: Vector3,
	maximum_angle_error_degrees := DEFAULT_MAXIMUM_ANGLE_ERROR_DEGREES
) -> bool:
	var measured: Vector3 = report.get("measured_direction", Vector3.ZERO)
	if (
		measured.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED
		or expected_world_direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED
	):
		return false
	var error := rad_to_deg(acos(clampf(
		measured.normalized().dot(expected_world_direction.normalized()),
		-1.0,
		1.0
	)))
	return error <= maximum_angle_error_degrees


static func _measure_direction(
	positions: PackedVector3Array,
	weights: PackedFloat32Array,
	impact: Vector3,
	expected_direction: Vector3,
	locality_radius: float,
	voxel_size: float
) -> Dictionary:
	if positions.size() < 2:
		return {
			"measured_direction": Vector3.ZERO,
			"forward_extent": 0.0,
			"backward_extent": 0.0,
		}
	var minimum_projection := INF
	var maximum_projection := -INF
	for position: Vector3 in positions:
		var projection := (position - impact).dot(expected_direction)
		minimum_projection = minf(minimum_projection, projection)
		maximum_projection = maxf(maximum_projection, projection)
	var span := maximum_projection - minimum_projection
	if span <= maxf(voxel_size, 0.0001):
		return {
			"measured_direction": Vector3.ZERO,
			"forward_extent": maxf(maximum_projection, 0.0),
			"backward_extent": maxf(-minimum_projection, 0.0),
		}
	var low_limit := minimum_projection + span * 0.28
	var high_limit := maximum_projection - span * 0.28
	var low_centroid := Vector3.ZERO
	var high_centroid := Vector3.ZERO
	var low_weight := 0.0
	var high_weight := 0.0
	for index: int in range(positions.size()):
		var position := positions[index]
		var projection := (position - impact).dot(expected_direction)
		var closest := impact + expected_direction * projection
		if position.distance_to(closest) > locality_radius:
			continue
		var weight := maxf(weights[index], 0.0001)
		if projection <= low_limit:
			low_centroid += position * weight
			low_weight += weight
		if projection >= high_limit:
			high_centroid += position * weight
			high_weight += weight
	var measured := Vector3.ZERO
	if low_weight > 0.0 and high_weight > 0.0:
		measured = high_centroid / high_weight - low_centroid / low_weight
		if measured.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
			measured = measured.normalized()
			if measured.dot(expected_direction) < 0.0:
				measured = -measured
	return {
		"measured_direction": measured,
		"forward_extent": maxf(maximum_projection, 0.0),
		"backward_extent": maxf(-minimum_projection, 0.0),
	}


static func _measure_aperture_axis(
	field: SparseSdfVolumeData,
	entry: Vector3,
	entry_normal: Vector3,
	exit: Vector3,
	exit_normal: Vector3,
	direction: Vector3,
	search_radius: float
) -> Dictionary:
	if entry.distance_squared_to(exit) <= field.voxel_size * field.voxel_size:
		return {"measured_direction": Vector3.ZERO, "entry_samples": 0, "exit_samples": 0}
	var entry_result := _aperture_centroid(
		field,
		entry + direction * field.voxel_size * 0.35,
		entry_normal,
		search_radius
	)
	var exit_result := _aperture_centroid(
		field,
		exit - direction * field.voxel_size * 0.35,
		exit_normal,
		search_radius
	)
	var entry_count := int(entry_result.get("sample_count", 0))
	var exit_count := int(exit_result.get("sample_count", 0))
	var entry_centroid: Vector3 = entry_result.get("centroid", entry)
	var exit_centroid: Vector3 = exit_result.get("centroid", exit)
	var measured := Vector3.ZERO
	if entry_count >= 3 and exit_count >= 3:
		measured = exit_centroid - entry_centroid
		if measured.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
			measured = measured.normalized()
			if measured.dot(direction) < 0.0:
				measured = -measured
	return {
		"measured_direction": measured,
		"entry_centroid": entry_centroid,
		"exit_centroid": exit_centroid,
		"entry_samples": entry_count,
		"exit_samples": exit_count,
	}


static func _measure_channel_axis(
	field: SparseSdfVolumeData,
	entry: Vector3,
	direction: Vector3,
	path_length: float,
	search_radius: float
) -> Dictionary:
	if path_length <= field.voxel_size * 2.0:
		return {"measured_direction": Vector3.ZERO, "near_samples": 0, "far_samples": 0}
	# Stay away from the intentionally flared entry/exit spall. Two interior aperture centroids
	# measure the actual bore axis rather than the silhouette of either crater.
	var near_center := entry + direction * (path_length * 0.32)
	var far_center := entry + direction * (path_length * 0.68)
	var near_result := _aperture_centroid(field, near_center, direction, search_radius)
	var far_result := _aperture_centroid(field, far_center, direction, search_radius)
	var near_count := int(near_result.get("sample_count", 0))
	var far_count := int(far_result.get("sample_count", 0))
	var near_centroid: Vector3 = near_result.get("centroid", near_center)
	var far_centroid: Vector3 = far_result.get("centroid", far_center)
	var measured := Vector3.ZERO
	if near_count >= 3 and far_count >= 3:
		measured = far_centroid - near_centroid
		if measured.length_squared() > MIN_DIRECTION_LENGTH_SQUARED:
			measured = measured.normalized()
			if measured.dot(direction) < 0.0:
				measured = -measured
	return {
		"measured_direction": measured,
		"near_centroid": near_centroid,
		"far_centroid": far_centroid,
		"near_samples": near_count,
		"far_samples": far_count,
	}


static func _aperture_centroid(
	field: SparseSdfVolumeData,
	center: Vector3,
	surface_normal: Vector3,
	search_radius: float
) -> Dictionary:
	var normal := (
		surface_normal.normalized()
		if surface_normal.length_squared() > MIN_DIRECTION_LENGTH_SQUARED
		else Vector3.BACK
	)
	var tangent := normal.cross(Vector3.UP)
	if tangent.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(normal).normalized()
	var step := maxf(field.voxel_size * 0.45, 0.004)
	var radius_steps := maxi(ceili(search_radius / step), 1)
	var weighted_center := Vector3.ZERO
	var total_weight := 0.0
	var sample_count := 0
	for y: int in range(-radius_steps, radius_steps + 1):
		for x: int in range(-radius_steps, radius_steps + 1):
			var offset := tangent * (float(x) * step) + bitangent * (float(y) * step)
			if offset.length_squared() > search_radius * search_radius:
				continue
			var point := center + offset
			var distance := field.sample_distance(point)
			if distance <= 0.0:
				continue
			var weight := maxf(distance, field.voxel_size * 0.1)
			weighted_center += point * weight
			total_weight += weight
			sample_count += 1
	return {
		"centroid": weighted_center / total_weight if total_weight > 0.0 else center,
		"sample_count": sample_count,
	}


static func _count_changed_mesh_vertices(
	pristine: Dictionary,
	presented: Dictionary,
	impact: Vector3,
	direction: Vector3,
	maximum_depth: float,
	locality_radius: float,
	tolerance: float
) -> int:
	var vertices: PackedVector3Array = presented.get("vertices", PackedVector3Array())
	var pristine_triangles: PackedVector3Array = pristine.get(
		"triangles",
		PackedVector3Array()
	)
	var count := 0
	for vertex: Vector3 in vertices:
		var projection := (vertex - impact).dot(direction)
		if projection < -locality_radius or projection > maximum_depth:
			continue
		var axis_point := impact + direction * projection
		if vertex.distance_to(axis_point) > locality_radius:
			continue
		if _distance_to_triangles(vertex, pristine_triangles, tolerance) > tolerance:
			count += 1
	return count


static func _field_path_clear_fraction(
	field: SparseSdfVolumeData,
	impact: Vector3,
	direction: Vector3,
	path_length: float
) -> float:
	if path_length <= 0.0:
		return 0.0
	var steps := maxi(ceili(path_length / maxf(field.voxel_size * 0.45, 0.002)), 3)
	var clear := 0
	for index: int in range(steps + 1):
		var alpha := float(index) / float(steps)
		var point := impact + direction * (path_length * alpha)
		if field.sample_distance(point) > -field.voxel_size * 0.08:
			clear += 1
	return float(clear) / float(steps + 1)


static func _off_axis_intact_fraction(
	pristine: Dictionary,
	presented: Dictionary,
	origin: Vector3,
	direction: Vector3,
	offset_distance: float,
	reference_entry_distance: float
) -> float:
	var right := direction.cross(Vector3.UP)
	if right.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		right = direction.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(direction).normalized()
	var intact := 0
	var checked := 0
	for axis: Vector3 in [right, -right, up, -up]:
		var shifted_origin := origin + axis * offset_distance
		var pristine_hits := ray_intersections(pristine, shifted_origin, direction)
		if pristine_hits.is_empty():
			continue
		checked += 1
		var post_hits := ray_intersections(presented, shifted_origin, direction)
		if post_hits.is_empty():
			continue
		var expected := float(pristine_hits[0].get("distance", reference_entry_distance))
		var actual := float(post_hits[0].get("distance", INF))
		if absf(expected - actual) <= maxf(offset_distance * 0.35, 0.04):
			intact += 1
	return float(intact) / float(checked) if checked > 0 else 0.0


static func _distance_to_triangles(
	point: Vector3,
	triangles: PackedVector3Array,
	early_exit: float
) -> float:
	var minimum_squared := INF
	var early_exit_squared := early_exit * early_exit
	for offset: int in range(0, triangles.size() - 2, 3):
		var closest := Geometry3D.get_closest_point_to_segment(
			point,
			triangles[offset],
			triangles[offset + 1]
		)
		# Segment distance is a cheap rejection. The exact triangle point is needed only nearby.
		minimum_squared = minf(minimum_squared, point.distance_squared_to(closest))
		closest = Geometry3D.get_closest_point_to_segment(
			point,
			triangles[offset + 1],
			triangles[offset + 2]
		)
		minimum_squared = minf(minimum_squared, point.distance_squared_to(closest))
		closest = Geometry3D.get_closest_point_to_segment(
			point,
			triangles[offset + 2],
			triangles[offset]
		)
		minimum_squared = minf(minimum_squared, point.distance_squared_to(closest))
		var plane := Plane(triangles[offset], triangles[offset + 1], triangles[offset + 2])
		var projected := plane.project(point)
		if _point_is_in_triangle(
			projected,
			triangles[offset],
			triangles[offset + 1],
			triangles[offset + 2]
		):
			minimum_squared = minf(minimum_squared, point.distance_squared_to(projected))
		if minimum_squared <= early_exit_squared:
			return sqrt(minimum_squared)
	return sqrt(minimum_squared) if minimum_squared < INF else INF


static func _point_is_in_triangle(
	point: Vector3,
	first: Vector3,
	second: Vector3,
	third: Vector3
) -> bool:
	var edge_zero := second - first
	var edge_one := third - first
	var relative := point - first
	var dot00 := edge_zero.dot(edge_zero)
	var dot01 := edge_zero.dot(edge_one)
	var dot11 := edge_one.dot(edge_one)
	var dot20 := relative.dot(edge_zero)
	var dot21 := relative.dot(edge_one)
	var denominator := dot00 * dot11 - dot01 * dot01
	if absf(denominator) <= 0.0000000001:
		return false
	var inverse := 1.0 / denominator
	var u := (dot11 * dot20 - dot01 * dot21) * inverse
	var v := (dot00 * dot21 - dot01 * dot20) * inverse
	return u >= -RAY_EPSILON and v >= -RAY_EPSILON and u + v <= 1.0 + RAY_EPSILON


static func _ray_triangle(
	origin: Vector3,
	direction: Vector3,
	first: Vector3,
	second: Vector3,
	third: Vector3
) -> Dictionary:
	var edge_one := second - first
	var edge_two := third - first
	var p := direction.cross(edge_two)
	var determinant := edge_one.dot(p)
	if absf(determinant) <= 0.00000001:
		return {}
	var inverse := 1.0 / determinant
	var translated := origin - first
	var u := translated.dot(p) * inverse
	if u < -RAY_EPSILON or u > 1.0 + RAY_EPSILON:
		return {}
	var q := translated.cross(edge_one)
	var v := direction.dot(q) * inverse
	if v < -RAY_EPSILON or u + v > 1.0 + RAY_EPSILON:
		return {}
	var distance := edge_two.dot(q) * inverse
	if distance < RAY_EPSILON:
		return {}
	var normal := edge_one.cross(edge_two)
	if normal.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return {}
	return {
		"distance": distance,
		"position": origin + direction * distance,
		"normal": normal.normalized(),
	}


static func _yaw_pitch_degrees(direction: Vector3) -> Vector2:
	if direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return Vector2(180.0, 180.0)
	var normalized := direction.normalized()
	return Vector2(
		rad_to_deg(atan2(normalized.x, -normalized.z)),
		rad_to_deg(atan2(normalized.y, Vector2(normalized.x, normalized.z).length()))
	)


static func _wrapped_degrees(value: float) -> float:
	return fposmod(value + 180.0, 360.0) - 180.0


static func _failure(reason: StringName) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"field_modified": false,
		"mesh_modified": false,
	}
