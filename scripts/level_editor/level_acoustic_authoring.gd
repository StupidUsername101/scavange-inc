class_name LevelAcousticAuthoring
extends RefCounted

## Value-only authoring helpers shared by the level editor and the eventual runtime level loader.
## The game already owns the acoustic graph solver; level files only describe sparse air samples,
## explicit aperture edges, and which placed geometry participates in acoustic obstruction.

const DEFAULT_PROBE_HEIGHT := 1.7
const DEFAULT_PROBE_SPACING := 5.0
const DEFAULT_CONNECT_RADIUS := 7.5
const DEFAULT_REFLECTION_DISTANCE := 28.0
const MIN_PROBE_SEPARATION := 0.35
const MAX_AUTO_PROBES := 512


static func sanitize_probe(raw: Dictionary) -> Dictionary:
	var probe_id := int(raw.get("id", 0))
	if probe_id <= 0:
		return {}
	var position := _finite_vector3(raw.get("position", Vector3.ZERO), Vector3.ZERO)
	return {
		"id": probe_id,
		"position": position,
		"auto_connect": bool(raw.get("auto_connect", true)),
		"auto_connect_radius": clampf(
			SafeVariant.finite_float_or(
				raw.get("auto_connect_radius", DEFAULT_CONNECT_RADIUS),
				DEFAULT_CONNECT_RADIUS
			),
			0.25,
			100.0
		),
		"sample_reflections": bool(raw.get("sample_reflections", true)),
		"reflection_sample_distance": clampf(
			SafeVariant.finite_float_or(
				raw.get("reflection_sample_distance", DEFAULT_REFLECTION_DISTANCE),
				DEFAULT_REFLECTION_DISTANCE
			),
			2.0,
			100.0
		),
		"environment_influence_radius": clampf(
			SafeVariant.finite_float_or(
				raw.get("environment_influence_radius", 0.0),
				0.0
			),
			0.0,
			100.0
		),
		"reverb_scale": clampf(
			SafeVariant.finite_float_or(raw.get("reverb_scale", 1.0), 1.0),
			0.0,
			2.0
		),
		"authored": bool(raw.get("authored", true)),
	}


static func sanitize_portal(raw: Dictionary) -> Dictionary:
	var portal_id := int(raw.get("id", 0))
	var probe_a_id := int(raw.get("probe_a_id", 0))
	var probe_b_id := int(raw.get("probe_b_id", 0))
	if (
		portal_id <= 0
		or probe_a_id <= 0
		or probe_b_id <= 0
		or probe_a_id == probe_b_id
	):
		return {}
	return {
		"id": portal_id,
		"probe_a_id": probe_a_id,
		"probe_b_id": probe_b_id,
		"bidirectional": bool(raw.get("bidirectional", true)),
		"carries_guided_energy": bool(raw.get("carries_guided_energy", false)),
		"profile": _sanitize_portal_profile(str(raw.get("profile", "open"))),
		"anchor_placement_id": maxi(int(raw.get("anchor_placement_id", 0)), 0),
	}


static func validate(
	probes: Array[Dictionary],
	portals: Array[Dictionary]
) -> Dictionary:
	var probe_ids: Dictionary[int, bool] = {}
	var duplicate_probe_count := 0
	for raw_probe: Dictionary in probes:
		var probe := sanitize_probe(raw_probe)
		var probe_id := int(probe.get("id", 0))
		if probe.is_empty() or probe_ids.has(probe_id):
			duplicate_probe_count += 1
			continue
		probe_ids[probe_id] = true
	var valid_portal_count := 0
	var broken_portal_count := 0
	var portal_pairs: Dictionary[String, bool] = {}
	for raw_portal: Dictionary in portals:
		var portal := sanitize_portal(raw_portal)
		if portal.is_empty():
			broken_portal_count += 1
			continue
		var probe_a_id := int(portal["probe_a_id"])
		var probe_b_id := int(portal["probe_b_id"])
		var low := mini(probe_a_id, probe_b_id)
		var high := maxi(probe_a_id, probe_b_id)
		var pair_key := "%d:%d" % [low, high]
		if (
			not probe_ids.has(probe_a_id)
			or not probe_ids.has(probe_b_id)
			or portal_pairs.has(pair_key)
		):
			broken_portal_count += 1
			continue
		portal_pairs[pair_key] = true
		valid_portal_count += 1
	return {
		"valid": duplicate_probe_count == 0 and broken_portal_count == 0,
		"probe_count": probe_ids.size(),
		"portal_count": valid_portal_count,
		"duplicate_probe_count": duplicate_probe_count,
		"broken_portal_count": broken_portal_count,
	}


static func portal_endpoints_for_bounds(
	world_transform: Transform3D,
	local_bounds: AABB,
	clearance := 0.55
) -> PackedVector3Array:
	var scaled_axes := [
		world_transform.basis.x * local_bounds.size.x,
		world_transform.basis.y * local_bounds.size.y,
		world_transform.basis.z * local_bounds.size.z,
	]
	var normal_axis_index := 0
	var minimum_length := (scaled_axes[0] as Vector3).length()
	for axis_index: int in range(1, 3):
		var axis_length := (scaled_axes[axis_index] as Vector3).length()
		if axis_length < minimum_length:
			minimum_length = axis_length
			normal_axis_index = axis_index
	var normal_axis := (
		world_transform.basis[normal_axis_index].normalized()
		if world_transform.basis[normal_axis_index].length_squared() > 0.000001
		else Vector3.FORWARD
	)
	var center := world_transform * local_bounds.get_center()
	var endpoint_distance := minimum_length * 0.5 + maxf(clearance, 0.05)
	return PackedVector3Array([
		center - normal_axis * endpoint_distance,
		center + normal_axis * endpoint_distance,
	])


static func automatic_ground_probe_positions(
	world_bounds: Array[AABB],
	spacing := DEFAULT_PROBE_SPACING,
	height := DEFAULT_PROBE_HEIGHT,
	maximum_count := MAX_AUTO_PROBES
) -> PackedVector3Array:
	if world_bounds.is_empty() or maximum_count <= 0:
		return PackedVector3Array()
	var merged := world_bounds[0]
	for bounds_index: int in range(1, world_bounds.size()):
		merged = merged.merge(world_bounds[bounds_index])
	if not merged.position.is_finite() or not merged.size.is_finite():
		return PackedVector3Array()
	var safe_spacing := clampf(spacing, 1.0, 25.0)
	var minimum := merged.position - Vector3(safe_spacing, 0.0, safe_spacing)
	var maximum := merged.end + Vector3(safe_spacing, 0.0, safe_spacing)
	var x_count := maxi(1, ceili((maximum.x - minimum.x) / safe_spacing) + 1)
	var z_count := maxi(1, ceili((maximum.z - minimum.z) / safe_spacing) + 1)
	var candidate_count := x_count * z_count
	if candidate_count > maximum_count:
		safe_spacing *= sqrt(float(candidate_count) / float(maximum_count))
		x_count = maxi(1, ceili((maximum.x - minimum.x) / safe_spacing) + 1)
		z_count = maxi(1, ceili((maximum.z - minimum.z) / safe_spacing) + 1)
	var result := PackedVector3Array()
	var ground_budget := maxi(1, floori(float(maximum_count) * 0.72))
	_append_probe_grid(
		result,
		AABB(
			Vector3(minimum.x, height, minimum.z),
			Vector3(maximum.x - minimum.x, 0.0, maximum.z - minimum.z)
		),
		height,
		safe_spacing,
		world_bounds,
		ground_budget
	)
	# A broad, shallow elevated asset is likely a floor, roof, catwalk, or platform. Sampling its
	# top gives multistory maps useful coverage without filling the volume above every wall/prop.
	var elevated_surfaces: Array[AABB] = []
	for bounds: AABB in world_bounds:
		if (
			bounds.end.y <= 0.15
			or bounds.size.x < 1.0
			or bounds.size.z < 1.0
			or bounds.size.y > minf(bounds.size.x, bounds.size.z) * 0.42
		):
			continue
		elevated_surfaces.append(bounds)
	elevated_surfaces.sort_custom(
		func(left: AABB, right: AABB) -> bool:
			return left.end.y < right.end.y
	)
	for surface: AABB in elevated_surfaces:
		if result.size() >= maximum_count:
			break
		var layer_y := surface.end.y + height
		_append_probe_grid(
			result,
			surface,
			layer_y,
			safe_spacing,
			world_bounds,
			maximum_count
		)
	return result


static func _append_probe_grid(
	result: PackedVector3Array,
	horizontal_bounds: AABB,
	y: float,
	spacing: float,
	blockers: Array[AABB],
	maximum_count: int
) -> void:
	var x_count := maxi(1, ceili(horizontal_bounds.size.x / spacing) + 1)
	var z_count := maxi(1, ceili(horizontal_bounds.size.z / spacing) + 1)
	for z_index: int in range(z_count):
		for x_index: int in range(x_count):
			if result.size() >= maximum_count:
				return
			var candidate := Vector3(
				horizontal_bounds.position.x + float(x_index) * spacing,
				y,
				horizontal_bounds.position.z + float(z_index) * spacing
			)
			if _point_inside_any_bounds(candidate, blockers, 0.18):
				continue
			var duplicate := false
			for existing: Vector3 in result:
				if existing.distance_squared_to(candidate) < (
					MIN_PROBE_SEPARATION * MIN_PROBE_SEPARATION
				):
					duplicate = true
					break
			if not duplicate:
				result.append(candidate)


static func _point_inside_any_bounds(
	point: Vector3,
	bounds_list: Array[AABB],
	padding: float
) -> bool:
	for bounds: AABB in bounds_list:
		if bounds.grow(padding).has_point(point):
			return true
	return false


static func _sanitize_portal_profile(value: String) -> String:
	return value if value in ["open", "vent", "thin_wall"] else "open"


static func _finite_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		var result := Vector3(
			SafeVariant.finite_float_or(array[0], fallback.x),
			SafeVariant.finite_float_or(array[1], fallback.y),
			SafeVariant.finite_float_or(array[2], fallback.z)
		)
		return result if result.is_finite() else fallback
	return fallback
