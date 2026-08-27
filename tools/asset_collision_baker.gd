class_name AssetCollisionBaker
extends RefCounted

## Deterministic, opt-in collision baking for curated 3D assets. The manifest is intentionally
## explicit: automatically turning every render mesh into physics would import tiny visual detail,
## seal openings in concave structures, and create exactly the collision load this tool avoids.

const MANIFEST_VERSION := 1


static func bake_manifest(
	manifest_path: String,
	requested_ids := PackedStringArray()
) -> bool:
	var manifest_text := FileAccess.get_file_as_string(manifest_path)
	if manifest_text.is_empty():
		push_error("Collision manifest is missing or empty: %s" % manifest_path)
		return false
	var parsed: Variant = JSON.parse_string(manifest_text)
	if not parsed is Dictionary:
		push_error("Collision manifest is not valid JSON: %s" % manifest_path)
		return false
	var manifest: Dictionary = parsed
	if int(manifest.get("version", 0)) != MANIFEST_VERSION:
		push_error("Unsupported collision manifest version: %s" % manifest.get("version"))
		return false
	var raw_assets: Variant = manifest.get("assets", [])
	if not raw_assets is Array:
		push_error("Collision manifest has no assets array: %s" % manifest_path)
		return false
	var baked_count := 0
	for raw_spec: Variant in raw_assets:
		if not raw_spec is Dictionary:
			continue
		var spec: Dictionary = raw_spec
		var asset_id := str(spec.get("id", "")).strip_edges()
		if asset_id.is_empty():
			push_error("Collision manifest contains an asset without an id")
			return false
		if not requested_ids.is_empty() and asset_id not in requested_ids:
			continue
		if not _bake_spec(spec):
			return false
		baked_count += 1
	if not requested_ids.is_empty() and baked_count != requested_ids.size():
		push_error(
			"Requested %d collision assets but manifest baked %d"
			% [requested_ids.size(), baked_count]
		)
		return false
	print("Collision bake complete: %d asset(s)" % baked_count)
	return true


static func _bake_spec(spec: Dictionary) -> bool:
	var source_path := str(spec.get("source", "")).strip_edges()
	var output_path := str(spec.get("output", "")).strip_edges()
	var mode := StringName(str(spec.get("mode", "convex")).to_lower())
	if source_path.is_empty() or output_path.is_empty():
		push_error("Collision spec needs source and output paths: %s" % spec.get("id"))
		return false
	if mode not in [&"convex", &"trimesh"]:
		push_error("Unsupported collision mode '%s' for %s" % [mode, spec.get("id")])
		return false
	var output_directory := output_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(output_directory)
	)
	if directory_error != OK:
		push_error(
			"Could not create collision output directory %s: %s"
			% [output_directory, error_string(directory_error)]
		)
		return false
	var packed_scene := load(source_path) as PackedScene
	if packed_scene == null:
		push_error("Could not load collision source: %s" % source_path)
		return false
	var sample := packed_scene.instantiate() as Node3D
	if sample == null:
		push_error("Collision source has no Node3D root: %s" % source_path)
		return false
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangle_count := _append_node_triangles(
		sample,
		Transform3D.IDENTITY,
		surface_tool,
		str(spec.get("material_contains", "")).to_lower(),
		str(spec.get("node_contains", "")).to_lower(),
		float(spec.get("maximum_radius", INF))
	)
	sample.free()
	if triangle_count <= 0:
		push_error("Collision filters removed every triangle: %s" % source_path)
		return false
	var collision_mesh := surface_tool.commit()
	if collision_mesh == null:
		push_error("Could not build collision mesh: %s" % source_path)
		return false
	var shape: Shape3D
	if mode == &"trimesh":
		shape = collision_mesh.create_trimesh_shape()
	else:
		shape = collision_mesh.create_convex_shape(
			bool(spec.get("clean", true)),
			bool(spec.get("simplify", true))
		)
	if shape == null:
		push_error("Godot could not generate collision shape: %s" % source_path)
		return false
	shape.resource_name = str(spec.get("id", output_path.get_file().get_basename()))
	shape.set_meta(&"collision_bake_source", source_path)
	shape.set_meta(&"collision_bake_mode", mode)
	shape.set_meta(&"collision_bake_manifest_version", MANIFEST_VERSION)
	var save_error := ResourceSaver.save(shape, output_path)
	if save_error != OK:
		push_error("Could not save collision shape: %s" % error_string(save_error))
		return false
	var point_count := (
		(shape as ConvexPolygonShape3D).points.size()
		if shape is ConvexPolygonShape3D
		else (shape as ConcavePolygonShape3D).get_faces().size()
	)
	print(
		"Baked %s -> %s (%d triangles, %d stored vertices)"
		% [spec.get("id"), output_path, triangle_count, point_count]
	)
	return true


static func _append_node_triangles(
	node: Node,
	parent_transform: Transform3D,
	surface_tool: SurfaceTool,
	material_filter: String,
	node_filter: String,
	maximum_radius: float
) -> int:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform *= (node as Node3D).transform
	var appended := 0
	if node is MeshInstance3D and (
		node_filter.is_empty()
		or str(node.name).to_lower().contains(node_filter)
	):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface_index: int in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface_index)
				var material_name := (
					material.resource_name.to_lower()
					if material != null
					else ""
				)
				if not material_filter.is_empty() and not material_name.contains(material_filter):
					continue
				appended += _append_surface_triangles(
					mesh.surface_get_arrays(surface_index),
					current_transform,
					surface_tool,
					maximum_radius
				)
	for child: Node in node.get_children():
		appended += _append_node_triangles(
			child,
			current_transform,
			surface_tool,
			material_filter,
			node_filter,
			maximum_radius
		)
	return appended


static func _append_surface_triangles(
	arrays: Array,
	mesh_transform: Transform3D,
	surface_tool: SurfaceTool,
	maximum_radius: float
) -> int:
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var element_count := indices.size() if not indices.is_empty() else vertices.size()
	var appended := 0
	for element_index: int in range(0, element_count - 2, 3):
		var triangle := PackedVector3Array()
		triangle.resize(3)
		var include_triangle := true
		for corner: int in range(3):
			var vertex_index := (
				indices[element_index + corner]
				if not indices.is_empty()
				else element_index + corner
			)
			var vertex := mesh_transform * vertices[vertex_index]
			triangle[corner] = vertex
			if Vector2(vertex.x, vertex.z).length() > maximum_radius:
				include_triangle = false
		if not include_triangle:
			continue
		for vertex: Vector3 in triangle:
			surface_tool.add_vertex(vertex)
		appended += 1
	return appended
