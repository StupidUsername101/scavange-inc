class_name StaticStructureCollisionBuilder
extends RefCounted

## Converts modular structure descriptions into broad-phase-friendly static collision. Adjacent
## boxes are merged only when their union is exactly another box, their orientation matches, and
## their collision group/material matches. Openings and L-shaped junctions therefore stay open.

const DEFAULT_MERGE_EPSILON := 0.001
const META_CLUSTER := &"structure_collision_cluster"
const META_SOURCE_NAMES := &"collision_source_names"
const META_SOURCE := &"collision_source"
const META_ACOUSTIC_BOUNDARY := &"acoustic_boundary"


static func cluster_box_descriptors(
	descriptors: Array[Dictionary],
	epsilon := DEFAULT_MERGE_EPSILON
) -> Array[Dictionary]:
	var safe_epsilon := maxf(epsilon, 0.00001)
	var working: Array[Dictionary] = []
	for descriptor: Dictionary in descriptors:
		var size: Vector3 = descriptor.get("size", Vector3.ZERO)
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var rotation: Vector3 = descriptor.get("rotation", Vector3.ZERO)
		if (
			not size.is_finite()
			or not position.is_finite()
			or not rotation.is_finite()
			or size.x <= 0.0
			or size.y <= 0.0
			or size.z <= 0.0
		):
			continue
		var basis := Basis.from_euler(rotation).orthonormalized()
		var oriented_center := basis.inverse() * position
		var half_size := size.abs() * 0.5
		var source_name := StringName(str(descriptor.get("name", &"Structure")))
		var candidate := descriptor.duplicate(true)
		candidate["rotation"] = rotation
		candidate["_basis"] = basis
		candidate["_minimum"] = oriented_center - half_size
		candidate["_maximum"] = oriented_center + half_size
		candidate["_merge_key"] = _merge_key(descriptor, rotation, safe_epsilon)
		candidate["source_names"] = PackedStringArray([str(source_name)])
		working.append(candidate)

	var merged_any := true
	while merged_any:
		merged_any = false
		for first_index: int in range(working.size()):
			if merged_any:
				break
			for second_index: int in range(first_index + 1, working.size()):
				if _merge_axis(working[first_index], working[second_index], safe_epsilon) < 0:
					continue
				working[first_index] = _merged_descriptor(
					working[first_index],
					working[second_index]
				)
				working.remove_at(second_index)
				merged_any = true
				break

	working.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str((a.get("source_names", PackedStringArray()) as PackedStringArray)[0]) < str((b.get("source_names", PackedStringArray()) as PackedStringArray)[0])
	)
	var result: Array[Dictionary] = []
	for cluster_index: int in range(working.size()):
		var cluster := working[cluster_index]
		var minimum: Vector3 = cluster.get("_minimum", Vector3.ZERO)
		var maximum: Vector3 = cluster.get("_maximum", Vector3.ZERO)
		var basis: Basis = cluster.get("_basis", Basis.IDENTITY)
		var source_names: PackedStringArray = cluster.get("source_names", PackedStringArray())
		cluster.erase("_minimum")
		cluster.erase("_maximum")
		cluster.erase("_basis")
		cluster.erase("_merge_key")
		cluster["position"] = basis * ((minimum + maximum) * 0.5)
		cluster["size"] = maximum - minimum
		cluster["source_names"] = source_names
		cluster["name"] = (
			StringName(source_names[0])
			if source_names.size() == 1
			else StringName("%sCluster%02d" % [source_names[0], cluster_index])
		)
		result.append(cluster)
	return result


static func build_clustered_box_bodies(
	parent: Node3D,
	descriptors: Array[Dictionary],
	default_surface: StringName,
	default_acoustic_material: AcousticMaterial = null,
	body_prefix := "Structure",
	epsilon := DEFAULT_MERGE_EPSILON
) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if parent == null:
		return result
	for descriptor: Dictionary in cluster_box_descriptors(descriptors, epsilon):
		var shape := BoxShape3D.new()
		shape.size = descriptor.get("size", Vector3.ONE)
		var cluster_name := str(descriptor.get("name", &"Cluster"))
		var source_names: PackedStringArray = descriptor.get(
			"source_names",
			PackedStringArray([cluster_name])
		)
		var body := _create_single_shape_body(
			parent,
			"%s_%sBody" % [body_prefix, cluster_name],
			cluster_name + "Collision",
			shape,
			Transform3D(
				Basis.from_euler(descriptor.get("rotation", Vector3.ZERO)),
				descriptor.get("position", Vector3.ZERO)
			),
			descriptor.get("physical_surface", default_surface),
			descriptor.get("acoustic_material", default_acoustic_material),
			&"clustered_box_primitive"
		)
		body.set_meta(META_CLUSTER, true)
		body.set_meta(META_SOURCE_NAMES, source_names)
		body.set_meta(
			META_ACOUSTIC_BOUNDARY,
			bool(descriptor.get("acoustic_boundary", true))
		)
		result.append(body)
	return result


static func build_baked_prop_bodies(
	parent: Node3D,
	descriptors: Array[Dictionary],
	shapes_by_asset: Dictionary,
	surfaces_by_asset: Dictionary,
	default_surface: StringName,
	default_acoustic_material: AcousticMaterial = null,
	acoustic_materials_by_asset: Dictionary = {}
) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if parent == null:
		return result
	for descriptor: Dictionary in descriptors:
		var asset_id: StringName = descriptor.get("asset_id", &"")
		var shape := shapes_by_asset.get(asset_id) as Shape3D
		if shape == null:
			push_warning("No baked collision shape for structure prop: %s" % asset_id)
			continue
		var scale: Vector3 = descriptor.get("scale", Vector3.ONE)
		var instance_shape := _shape_scaled_copy(shape, scale)
		var prop_name := str(descriptor.get("name", &"StructureProp"))
		var prop_acoustic_material := descriptor.get(
			"acoustic_material",
			acoustic_materials_by_asset.get(
				asset_id,
				default_acoustic_material
			)
		) as AcousticMaterial
		var body := _create_single_shape_body(
			parent,
			prop_name + "Body",
			prop_name + "Collision",
			instance_shape,
			Transform3D(
				Basis.from_euler(descriptor.get("rotation", Vector3.ZERO)),
				descriptor.get("position", Vector3.ZERO)
			),
			surfaces_by_asset.get(asset_id, default_surface),
			prop_acoustic_material,
			&"manifest_baked_asset"
		)
		body.set_meta(&"collision_asset_id", asset_id)
		body.set_meta(META_SOURCE_NAMES, PackedStringArray([prop_name]))
		# Props may shadow direct sound, but they do not separate two air volumes.
		body.set_meta(META_ACOUSTIC_BOUNDARY, false)
		result.append(body)
	return result


static func debug_cluster_report(
	descriptors: Array[Dictionary],
	epsilon := DEFAULT_MERGE_EPSILON
) -> Dictionary:
	var clusters := cluster_box_descriptors(descriptors, epsilon)
	var merged_piece_count := 0
	for cluster: Dictionary in clusters:
		merged_piece_count += maxi(
			(cluster.get("source_names", PackedStringArray()) as PackedStringArray).size() - 1,
			0
		)
	return {
		"input_piece_count": descriptors.size(),
		"cluster_count": clusters.size(),
		"merged_piece_count": merged_piece_count,
	}


static func _create_single_shape_body(
	parent: Node3D,
	body_name: String,
	collision_name: String,
	shape: Shape3D,
	transform: Transform3D,
	physical_surface: StringName,
	acoustic_material: AcousticMaterial,
	source_kind: StringName
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.transform = transform
	PhysicalSurface.apply_to(body, physical_surface)
	if acoustic_material != null:
		body.set_meta(&"acoustic_material", acoustic_material)
	body.set_meta(META_SOURCE, source_kind)
	var collision := CollisionShape3D.new()
	collision.name = collision_name
	collision.shape = shape
	collision.position = Vector3.ZERO
	collision.rotation = Vector3.ZERO
	body.add_child(collision)
	parent.add_child(body)
	return body


static func _shape_scaled_copy(shape: Shape3D, scale: Vector3) -> Shape3D:
	if scale.is_equal_approx(Vector3.ONE):
		return shape
	if shape is BoxShape3D:
		var result := BoxShape3D.new()
		result.size = (shape as BoxShape3D).size * scale.abs()
		return result
	if shape is ConvexPolygonShape3D:
		var result := ConvexPolygonShape3D.new()
		var points := (shape as ConvexPolygonShape3D).points
		for point_index: int in range(points.size()):
			points[point_index] *= scale
		result.points = points
		return result
	if shape is ConcavePolygonShape3D:
		var result := ConcavePolygonShape3D.new()
		var faces := (shape as ConcavePolygonShape3D).get_faces()
		for face_index: int in range(faces.size()):
			faces[face_index] *= scale
		result.set_faces(faces)
		return result
	push_warning("Unsupported scaled collision type; using unscaled shape: %s" % shape)
	return shape


static func _merge_key(
	descriptor: Dictionary,
	rotation: Vector3,
	epsilon: float
) -> String:
	var group_value: Variant = descriptor.get(
		"collision_group",
		descriptor.get("material_id", &"default")
	)
	return "%s|%s|%d|%d|%d" % [
		str(group_value),
		str(descriptor.get("physical_surface", &"")),
		roundi(rotation.x / epsilon),
		roundi(rotation.y / epsilon),
		roundi(rotation.z / epsilon),
	]


static func _merge_axis(a: Dictionary, b: Dictionary, epsilon: float) -> int:
	if a.get("_merge_key", "") != b.get("_merge_key", ""):
		return -1
	var a_min: Vector3 = a.get("_minimum", Vector3.ZERO)
	var a_max: Vector3 = a.get("_maximum", Vector3.ZERO)
	var b_min: Vector3 = b.get("_minimum", Vector3.ZERO)
	var b_max: Vector3 = b.get("_maximum", Vector3.ZERO)
	for merge_axis: int in range(3):
		var aligned := true
		for other_axis: int in range(3):
			if other_axis == merge_axis:
				continue
			if (
				absf(a_min[other_axis] - b_min[other_axis]) > epsilon
				or absf(a_max[other_axis] - b_max[other_axis]) > epsilon
			):
				aligned = false
				break
		if not aligned:
			continue
		if (
			absf(a_max[merge_axis] - b_min[merge_axis]) <= epsilon
			or absf(b_max[merge_axis] - a_min[merge_axis]) <= epsilon
		):
			return merge_axis
	return -1


static func _merged_descriptor(a: Dictionary, b: Dictionary) -> Dictionary:
	var result := a.duplicate(true)
	var a_min: Vector3 = a.get("_minimum", Vector3.ZERO)
	var a_max: Vector3 = a.get("_maximum", Vector3.ZERO)
	var b_min: Vector3 = b.get("_minimum", Vector3.ZERO)
	var b_max: Vector3 = b.get("_maximum", Vector3.ZERO)
	result["_minimum"] = Vector3(
		minf(a_min.x, b_min.x),
		minf(a_min.y, b_min.y),
		minf(a_min.z, b_min.z)
	)
	result["_maximum"] = Vector3(
		maxf(a_max.x, b_max.x),
		maxf(a_max.y, b_max.y),
		maxf(a_max.z, b_max.z)
	)
	var source_names: PackedStringArray = a.get("source_names", PackedStringArray())
	source_names.append_array(b.get("source_names", PackedStringArray()))
	source_names.sort()
	result["source_names"] = source_names
	return result
