class_name SkinnedMeshSurfaceSampler
extends RefCounted

## Allocation-bounded CPU sampler for the low-poly authored character skins. Damage authority stays
## analytic and server-owned, but presentation wounds must attach to the surface the player actually
## sees. A capture skins each cached vertex once, finds the first triangle on the incoming ray, then
## stores only three source vertices plus their bind weights. Resolving that attachment in later
## poses skins those three vertices rather than rebaking the complete mesh.

const EPSILON := 0.0000001
const DEFAULT_MAXIMUM_DISTANCE := 2.5

var _skin: PlayerCharacterSkin
var _skeleton: Skeleton3D
var _surfaces: Array[Dictionary] = []
var _bind_names := PackedStringArray()
var _bind_bones := PackedInt32Array()
var _bind_poses: Array[Transform3D] = []
var _bind_transforms: Array[Transform3D] = []


func configure(skin: PlayerCharacterSkin) -> SkinnedMeshSurfaceSampler:
	_skin = skin
	_skeleton = skin.skeleton if skin != null else null
	_surfaces.clear()
	_bind_names.resize(0)
	_bind_bones.resize(0)
	_bind_poses.clear()
	_bind_transforms.clear()
	if _skeleton == null or skin.skin_meshes.is_empty():
		return self
	for mesh_instance: MeshInstance3D in skin.skin_meshes:
		if mesh_instance == null or mesh_instance.mesh == null or mesh_instance.skin == null:
			continue
		var skin_resource := mesh_instance.skin
		if _bind_bones.is_empty():
			_cache_bindings(skin_resource)
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
			var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
			if vertices.is_empty() or bones.is_empty() or weights.size() != bones.size():
				continue
			var weights_per_vertex := bones.size() / vertices.size()
			if weights_per_vertex != 4 and weights_per_vertex != 8:
				continue
			var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			_surfaces.append({
				"mesh": mesh_instance,
				"vertices": vertices,
				"indices": indices,
				"bones": bones,
				"weights": weights,
				"weights_per_vertex": weights_per_vertex,
				"deformed": PackedVector3Array(),
			})
	return self


func is_usable() -> bool:
	return _skeleton != null and not _surfaces.is_empty() and not _bind_bones.is_empty()


func prepare_pose() -> void:
	if is_usable():
		_update_bind_transforms()


func capture_first_surface(
	world_origin: Vector3,
	world_direction: Vector3,
	reference_basis: Basis = Basis.IDENTITY,
	maximum_distance := DEFAULT_MAXIMUM_DISTANCE
) -> Dictionary:
	if not is_usable() or world_direction.length_squared() <= EPSILON:
		return {}
	var direction := world_direction.normalized()
	prepare_pose()
	var best_distance := maxf(maximum_distance, 0.001)
	var best_surface := -1
	var best_triangle := Vector3i(-1, -1, -1)
	var best_barycentric := Vector3.ZERO
	for surface_index: int in range(_surfaces.size()):
		var surface := _surfaces[surface_index]
		_deform_surface(surface)
		_surfaces[surface_index] = surface
		var deformed := surface["deformed"] as PackedVector3Array
		var indices := surface["indices"] as PackedInt32Array
		var triangle_count := (
			indices.size() / 3
			if not indices.is_empty()
			else deformed.size() / 3
		)
		for triangle_index: int in range(triangle_count):
			var first := indices[triangle_index * 3] if not indices.is_empty() else triangle_index * 3
			var second := indices[triangle_index * 3 + 1] if not indices.is_empty() else triangle_index * 3 + 1
			var third := indices[triangle_index * 3 + 2] if not indices.is_empty() else triangle_index * 3 + 2
			var hit := _ray_triangle(
				world_origin,
				direction,
				deformed[first],
				deformed[second],
				deformed[third]
			)
			var distance := hit.x
			if distance < 0.0 or distance >= best_distance:
				continue
			best_distance = distance
			best_surface = surface_index
			best_triangle = Vector3i(first, second, third)
			best_barycentric = Vector3(1.0 - hit.y - hit.z, hit.y, hit.z)
	if best_surface < 0:
		return {}
	var selected := _surfaces[best_surface]
	var dominant_bind := _dominant_triangle_bind(
		selected,
		best_triangle,
		best_barycentric
	)
	var dominant_bone := (
		_bind_bones[dominant_bind]
		if dominant_bind >= 0 and dominant_bind < _bind_bones.size()
		else -1
	)
	var bone_basis := _bone_world_basis(dominant_bone)
	var safe_reference := reference_basis.orthonormalized()
	return {
		"surface": best_surface,
		"triangle": best_triangle,
		"barycentric": best_barycentric,
		"dominant_bind": dominant_bind,
		"dominant_bone": dominant_bone,
		"local_direction": bone_basis.inverse() * direction,
		"local_reference_basis": bone_basis.inverse() * safe_reference,
		"capture_position": world_origin + direction * best_distance,
		"capture_distance": best_distance,
	}


func resolve_attachment(
	attachment: Dictionary,
	refresh_pose := true
) -> Dictionary:
	if not is_usable() or attachment.is_empty():
		return {}
	var surface_index := int(attachment.get("surface", -1))
	if surface_index < 0 or surface_index >= _surfaces.size():
		return {}
	var triangle: Vector3i = attachment.get("triangle", Vector3i(-1, -1, -1))
	var barycentric: Vector3 = attachment.get("barycentric", Vector3.ZERO)
	var surface := _surfaces[surface_index]
	var vertices := surface["vertices"] as PackedVector3Array
	if (
		triangle.x < 0
		or triangle.y < 0
		or triangle.z < 0
		or triangle.x >= vertices.size()
		or triangle.y >= vertices.size()
		or triangle.z >= vertices.size()
	):
		return {}
	if refresh_pose:
		prepare_pose()
	var first := _skin_vertex_world(surface, triangle.x)
	var second := _skin_vertex_world(surface, triangle.y)
	var third := _skin_vertex_world(surface, triangle.z)
	var position := (
		first * barycentric.x
		+ second * barycentric.y
		+ third * barycentric.z
	)
	var bone_basis := _bone_world_basis(int(attachment.get("dominant_bone", -1)))
	var direction: Vector3 = bone_basis * attachment.get(
		"local_direction",
		Vector3.FORWARD
	)
	var reference_basis: Basis = bone_basis * attachment.get(
		"local_reference_basis",
		Basis.IDENTITY
	)
	var normal := (second - first).cross(third - first).normalized()
	return {
		"position": position,
		"direction": direction.normalized(),
		"basis": reference_basis.orthonormalized(),
		"normal": normal,
	}


func surface_count() -> int:
	return _surfaces.size()


func _cache_bindings(skin_resource: Skin) -> void:
	var bind_count := skin_resource.get_bind_count()
	_bind_names.resize(bind_count)
	_bind_bones.resize(bind_count)
	_bind_poses.resize(bind_count)
	_bind_transforms.resize(bind_count)
	for bind_index: int in range(bind_count):
		var bind_name := skin_resource.get_bind_name(bind_index)
		var bone_index := _skeleton.find_bone(bind_name)
		if bone_index < 0:
			bone_index = skin_resource.get_bind_bone(bind_index)
			if bone_index >= 0 and bone_index < _skeleton.get_bone_count():
				bind_name = _skeleton.get_bone_name(bone_index)
		_bind_names[bind_index] = str(bind_name)
		_bind_bones[bind_index] = bone_index
		_bind_poses[bind_index] = skin_resource.get_bind_pose(bind_index)


func _update_bind_transforms() -> void:
	for bind_index: int in range(_bind_bones.size()):
		var bone_index := _bind_bones[bind_index]
		_bind_transforms[bind_index] = (
			_skeleton.get_bone_global_pose(bone_index) * _bind_poses[bind_index]
			if bone_index >= 0 and bone_index < _skeleton.get_bone_count()
			else Transform3D.IDENTITY
		)


func _deform_surface(surface: Dictionary) -> void:
	var mesh_instance := surface["mesh"] as MeshInstance3D
	var vertices := surface["vertices"] as PackedVector3Array
	var deformed := surface["deformed"] as PackedVector3Array
	if deformed.size() != vertices.size():
		deformed.resize(vertices.size())
	for vertex_index: int in range(vertices.size()):
		deformed[vertex_index] = mesh_instance.global_transform * _skin_vertex_local(
			surface,
			vertex_index
		)
	surface["deformed"] = deformed


func _skin_vertex_world(surface: Dictionary, vertex_index: int) -> Vector3:
	var mesh_instance := surface["mesh"] as MeshInstance3D
	return mesh_instance.global_transform * _skin_vertex_local(surface, vertex_index)


func _skin_vertex_local(surface: Dictionary, vertex_index: int) -> Vector3:
	var vertices := surface["vertices"] as PackedVector3Array
	var bones := surface["bones"] as PackedInt32Array
	var weights := surface["weights"] as PackedFloat32Array
	var weights_per_vertex := int(surface["weights_per_vertex"])
	var source := vertices[vertex_index]
	var result := Vector3.ZERO
	var total_weight := 0.0
	var offset := vertex_index * weights_per_vertex
	for weight_index: int in range(weights_per_vertex):
		var weight := weights[offset + weight_index]
		if weight <= 0.0:
			continue
		var bind_index := bones[offset + weight_index]
		if bind_index < 0 or bind_index >= _bind_transforms.size():
			continue
		result += (_bind_transforms[bind_index] * source) * weight
		total_weight += weight
	return result if total_weight > EPSILON else source


func _dominant_triangle_bind(
	surface: Dictionary,
	triangle: Vector3i,
	barycentric: Vector3
) -> int:
	var bones := surface["bones"] as PackedInt32Array
	var weights := surface["weights"] as PackedFloat32Array
	var weights_per_vertex := int(surface["weights_per_vertex"])
	var scores: Dictionary[int, float] = {}
	var triangle_vertices := [triangle.x, triangle.y, triangle.z]
	for corner_index: int in range(3):
		var vertex_index: int = triangle_vertices[corner_index]
		var corner_weight := barycentric[corner_index]
		var offset := vertex_index * weights_per_vertex
		for weight_index: int in range(weights_per_vertex):
			var skin_weight := weights[offset + weight_index] * corner_weight
			if skin_weight <= 0.0:
				continue
			var bind_index := bones[offset + weight_index]
			scores[bind_index] = float(scores.get(bind_index, 0.0)) + skin_weight
	var best_bind := -1
	var best_score := -1.0
	for bind_index: int in scores:
		var score := scores[bind_index]
		if score > best_score:
			best_bind = bind_index
			best_score = score
	return best_bind


func _bone_world_basis(bone_index: int) -> Basis:
	if bone_index < 0 or bone_index >= _skeleton.get_bone_count():
		return _skeleton.global_basis.orthonormalized()
	return (
		_skeleton.global_basis
		* _skeleton.get_bone_global_pose(bone_index).basis
	).orthonormalized()


static func _ray_triangle(
	origin: Vector3,
	direction: Vector3,
	first: Vector3,
	second: Vector3,
	third: Vector3
) -> Vector3:
	var edge_first := second - first
	var edge_second := third - first
	var perpendicular := direction.cross(edge_second)
	var determinant := edge_first.dot(perpendicular)
	if absf(determinant) <= EPSILON:
		return Vector3(-1.0, 0.0, 0.0)
	var inverse := 1.0 / determinant
	var from_first := origin - first
	var second_weight := inverse * from_first.dot(perpendicular)
	if second_weight < 0.0 or second_weight > 1.0:
		return Vector3(-1.0, 0.0, 0.0)
	var cross := from_first.cross(edge_first)
	var third_weight := inverse * direction.dot(cross)
	if third_weight < 0.0 or second_weight + third_weight > 1.0:
		return Vector3(-1.0, 0.0, 0.0)
	var distance := inverse * edge_second.dot(cross)
	if distance < 0.0:
		return Vector3(-1.0, 0.0, 0.0)
	# Packed t/u/v avoids allocating a Dictionary for every tested triangle. Captures are rare, but
	# one wound still probes the complete low-poly body and should not create a temporary-object storm.
	return Vector3(distance, second_weight, third_weight)
