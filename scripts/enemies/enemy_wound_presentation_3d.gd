class_name EnemyWoundPresentation3D
extends Node3D

const SKIN_SHADER: Shader = preload("res://shaders/enemy_wound_skin.gdshader")
const TISSUE_SHADER: Shader = preload("res://shaders/enemy_tissue_surface.gdshader")
const ANATOMY := preload("res://scripts/enemies/enemy_destructible_anatomy.gd")
const SDF_INTERIOR_SURFACE_BUILDER := preload(
	"res://scripts/destruction/sdf_interior_surface_builder.gd"
)
const SKINNED_SURFACE_SAMPLER := preload(
	"res://scripts/characters/skinned_mesh_surface_sampler.gd"
)
const MAX_WOUNDS := 24
const MAX_PARALLEL_SURFACE_JOBS := 3
const MAX_SURFACE_COMMITS_PER_FRAME := 2
const REMESH_NEIGHBOR_RING := 1
const TISSUE_PIPELINE_WARMUP_NAME := &"EnemyTissuePipelineWarmup"
const SHELL_APERTURE_DEPTH_PER_RADIUS := 1.7
const SHELL_APERTURE_MINIMUM_VOXELS := 2.5

static var _tissue_pipeline_registered := false

var character_skin: PlayerCharacterSkin
var anatomy_definition: EnemyDestructibleAnatomyDefinition
var target_revision := -1
var target_wounds: Array[Dictionary] = []
var target_part_presence := {
	ANATOMY.PART_HEAD: true,
	ANATOMY.PART_TORSO: true,
	ANATOMY.PART_LEFT_ARM: true,
	ANATOMY.PART_RIGHT_ARM: true,
	ANATOMY.PART_LEFT_LEG: true,
	ANATOMY.PART_RIGHT_LEG: true,
}
var skin_materials: Array[ShaderMaterial] = []
var part_surface_nodes: Dictionary = {}
var part_surface_fields: Dictionary = {}
var part_chunk_surface_nodes: Dictionary = {}
var _visible_aperture_count := 0
var _tissue_material: ShaderMaterial
var _configured_variant_path := ""
var _presented_wounds: Array[Dictionary] = []
var _applied_deformation_keys: Array[String] = []
var _dirty_surface_chunks: Array[Dictionary] = []
var _dirty_surface_chunk_keys: Dictionary[String, bool] = {}
var _active_surface_jobs: Array[Dictionary] = []
var _surface_job_pool: Array[SdfChunkBuildJob] = []
var _pending_chunk_meshes: Dictionary[String, Dictionary] = {}
var _pending_visual_commit := false
var _surface_rebuild_count := 0
var _surface_worker_usec := 0
var _surface_commit_usec := 0
var _full_replay_count := 0
var _surface_sampler = SKINNED_SURFACE_SAMPLER.new()
var _surface_attachments: Dictionary[String, Dictionary] = {}
var _resolved_attachment_frames: Dictionary[String, Dictionary] = {}
var _visual_aperture_radii: Dictionary[String, float] = {}


func _process(_delta: float) -> void:
	_pump_surface_jobs()


func _exit_tree() -> void:
	_discard_surface_jobs()


func configure(
	skin: PlayerCharacterSkin,
	profile: EnemyDestructibleAnatomyDefinition = null
) -> void:
	if (
		skin == character_skin
		and profile == anatomy_definition
		and not skin_materials.is_empty()
		and _configured_variant_path == skin.get_variant_path()
	):
		return
	character_skin = skin
	anatomy_definition = profile
	_configured_variant_path = skin.get_variant_path() if skin != null else ""
	_install_skin_materials()
	_surface_sampler.configure(skin)
	_surface_attachments.clear()
	_resolved_attachment_frames.clear()
	_visual_aperture_radii.clear()
	_configure_part_surfaces()


func apply_state(value: Dictionary) -> void:
	if value.is_empty():
		return
	if anatomy_definition == null:
		var profile_path := str(value.get("profile_path", ""))
		if not profile_path.is_empty() and ResourceLoader.exists(profile_path):
			anatomy_definition = load(profile_path) as EnemyDestructibleAnatomyDefinition
			_configure_part_surfaces()
	var next_revision := int(value.get("revision", target_revision))
	var replicated_presence: Variant = value.get("part_presence", {})
	if replicated_presence is Dictionary:
		for part_key: Variant in (replicated_presence as Dictionary).keys():
			target_part_presence[StringName(str(part_key))] = bool(
				(replicated_presence as Dictionary)[part_key]
			)
	target_part_presence[ANATOMY.PART_LEFT_ARM] = bool(
		value.get("left_arm", target_part_presence[ANATOMY.PART_LEFT_ARM])
	)
	target_part_presence[ANATOMY.PART_RIGHT_ARM] = bool(
		value.get("right_arm", target_part_presence[ANATOMY.PART_RIGHT_ARM])
	)
	target_part_presence[ANATOMY.PART_LEFT_LEG] = bool(
		value.get("left_leg", target_part_presence[ANATOMY.PART_LEFT_LEG])
	)
	target_part_presence[ANATOMY.PART_RIGHT_LEG] = bool(
		value.get("right_leg", target_part_presence[ANATOMY.PART_RIGHT_LEG])
	)
	if next_revision == target_revision:
		return
	target_revision = next_revision
	target_wounds.clear()
	var raw_wounds: Variant = value.get("wounds", [])
	if raw_wounds is Array:
		for wound_value: Variant in raw_wounds:
			if not wound_value is Dictionary or target_wounds.size() >= MAX_WOUNDS - 4:
				continue
			var wound := _sanitize_wound(wound_value)
			if not wound.is_empty():
				target_wounds.append(wound)
	_append_missing_limb_stumps()
	_rebuild_part_surfaces(value.get("deformation_events", []))


func update_presentation() -> void:
	if character_skin == null or not character_skin.is_usable():
		visible = false
		return
	visible = true
	character_skin.set_limb_presence(
		bool(target_part_presence[ANATOMY.PART_LEFT_ARM]),
		bool(target_part_presence[ANATOMY.PART_RIGHT_ARM]),
		bool(target_part_presence[ANATOMY.PART_LEFT_LEG]),
		bool(target_part_presence[ANATOMY.PART_RIGHT_LEG])
	)
	character_skin.set_head_presence(bool(target_part_presence[ANATOMY.PART_HEAD]))
	_prepare_attachment_frames()
	var entries := PackedVector4Array()
	var axes := PackedVector4Array()
	entries.resize(MAX_WOUNDS)
	axes.resize(MAX_WOUNDS)
	var visible_count := 0
	for wound_index: int in range(_presented_wounds.size()):
		var wound: Dictionary = _presented_wounds[wound_index]
		var part_id := StringName(str(wound.get("part", &"")))
		if not _part_is_present(part_id) and not bool(wound.get("stump", false)):
			continue
		var frame := _resolve_wound_world_frame(wound)
		var entry: Vector3 = frame["position"]
		var direction: Vector3 = frame["direction"]
		if direction.length_squared() <= 0.000001:
			direction = character_skin.global_basis.z
		direction = direction.normalized()
		var radius := float(_visual_aperture_radii.get(
			_wound_attachment_key(wound),
			float(wound.get("radius", 0.03))
		))
		var depth := _visual_shell_aperture_depth(wound, radius, part_id)
		entries[visible_count] = Vector4(entry.x, entry.y, entry.z, radius)
		axes[visible_count] = Vector4(direction.x, direction.y, direction.z, depth)
		visible_count += 1
	for material: ShaderMaterial in skin_materials:
		material.set_shader_parameter(&"wound_count", visible_count)
		material.set_shader_parameter(&"wound_entries", entries)
		material.set_shader_parameter(&"wound_axes", axes)
	_visible_aperture_count = visible_count
	_update_part_surface_transforms()


func get_visible_wound_count() -> int:
	return _visible_aperture_count


func get_generated_tissue_triangle_count() -> int:
	var count := 0
	for part_chunks_value: Variant in part_chunk_surface_nodes.values():
		if not part_chunks_value is Dictionary:
			continue
		for node_value: Variant in (part_chunks_value as Dictionary).values():
			var node := node_value as MeshInstance3D
			if node == null or not node.mesh is ArrayMesh:
				continue
			var mesh := node.mesh as ArrayMesh
			for surface_index: int in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
				count += indices.size() / 3
	return count


func has_pending_surface_rebuilds() -> bool:
	return not _dirty_surface_chunks.is_empty() or not _active_surface_jobs.is_empty()


func get_part_surface_meshes(part_id: StringName) -> Array[ArrayMesh]:
	var result: Array[ArrayMesh] = []
	var chunks_value: Variant = part_chunk_surface_nodes.get(part_id, {})
	if not chunks_value is Dictionary:
		return result
	var chunks := chunks_value as Dictionary
	for node_value: Variant in chunks.values():
		var node := node_value as MeshInstance3D
		if node != null and node.mesh is ArrayMesh:
			result.append(node.mesh as ArrayMesh)
	return result


func debug_surface_metrics() -> Dictionary:
	return {
		"pending_chunks": _dirty_surface_chunks.size(),
		"active_jobs": _active_surface_jobs.size(),
		"rebuild_count": _surface_rebuild_count,
		"worker_usec": _surface_worker_usec,
		"commit_usec": _surface_commit_usec,
		"full_replay_count": _full_replay_count,
		"applied_event_count": _applied_deformation_keys.size(),
	}


func debug_surface_alignment() -> Dictionary:
	_prepare_attachment_frames()
	var attached_wounds := 0
	var maximum_chunk_anchor_error := 0.0
	var minimum_tissue_distance := INF
	var maximum_mouth_radius := 0.0
	var maximum_legacy_offset := 0.0
	for wound: Dictionary in _presented_wounds:
		if bool(wound.get("stump", false)):
			continue
		var key := _wound_attachment_key(wound)
		var frame := _resolved_attachment_frames.get(key, {}) as Dictionary
		if frame.is_empty():
			continue
		attached_wounds += 1
		var entry: Vector3 = frame.get("position", Vector3.ZERO)
		var direction: Vector3 = frame.get("direction", Vector3.FORWARD)
		var part_id := StringName(str(wound.get("part", &"")))
		var part := anatomy_definition.get_part(part_id) if anatomy_definition != null else null
		if part != null:
			var legacy := _profile_wound_world_frame(
				wound.get("local_position", part.local_center),
				wound.get("local_direction", Vector3.FORWARD),
				part
			)
			maximum_legacy_offset = maxf(
				maximum_legacy_offset,
				entry.distance_to(legacy.get("position", entry))
			)
		var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
		var chunks_value: Variant = part_chunk_surface_nodes.get(part_id, {})
		if part == null or field == null or not chunks_value is Dictionary:
			continue
		var field_hit: Vector3 = wound.get("local_position", part.local_center) - part.local_center
		for coordinate_value: Variant in (chunks_value as Dictionary).keys():
			var coordinate: Vector3i = coordinate_value
			var nearest := _nearest_attached_wound(part, field, coordinate)
			if nearest.is_empty() or _wound_attachment_key(nearest) != key:
				continue
			var chunk := (chunks_value as Dictionary).get(coordinate) as MeshInstance3D
			if chunk == null or chunk.mesh == null:
				continue
			maximum_chunk_anchor_error = maxf(
				maximum_chunk_anchor_error,
				(chunk.global_transform * field_hit).distance_to(entry)
			)
			for surface_index: int in range(chunk.mesh.get_surface_count()):
				var arrays := chunk.mesh.surface_get_arrays(surface_index)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				for local_vertex: Vector3 in vertices:
					var from_entry := chunk.global_transform * local_vertex - entry
					minimum_tissue_distance = minf(
						minimum_tissue_distance,
						from_entry.length()
					)
					var axial := from_entry.dot(direction)
					if axial >= -0.02 and axial <= 0.04:
						maximum_mouth_radius = maxf(
							maximum_mouth_radius,
							(from_entry - direction * axial).length()
						)
	return {
		"attached_wounds": attached_wounds,
		"maximum_chunk_anchor_error": maximum_chunk_anchor_error,
		"minimum_tissue_distance": minimum_tissue_distance,
		"maximum_mouth_radius": maximum_mouth_radius,
		"maximum_legacy_offset": maximum_legacy_offset,
	}


func part_is_present(part_id: StringName) -> bool:
	return _part_is_present(part_id)


func _install_skin_materials() -> void:
	skin_materials.clear()
	if character_skin == null or not character_skin.is_usable():
		return
	for mesh_instance: MeshInstance3D in character_skin.skin_meshes:
		if mesh_instance.mesh == null:
			continue
		for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = SKIN_SHADER
			if source != null:
				material.set_shader_parameter(&"albedo_color", source.albedo_color)
				material.set_shader_parameter(&"albedo_texture", source.albedo_texture)
				material.set_shader_parameter(&"has_albedo_texture", source.albedo_texture != null)
				material.set_shader_parameter(&"material_roughness", source.roughness)
				material.set_shader_parameter(&"material_metallic", source.metallic)
			if anatomy_definition != null and anatomy_definition.damage_texture != null:
				material.set_shader_parameter(
					&"wound_inner_color",
					anatomy_definition.damage_texture.interior_color
				)
				material.set_shader_parameter(
					&"wound_deep_color",
					anatomy_definition.damage_texture.deep_interior_color
				)
			mesh_instance.set_surface_override_material(surface_index, material)
			skin_materials.append(material)


func _configure_part_surfaces() -> void:
	_discard_surface_jobs()
	for node_value: Variant in part_surface_nodes.values():
		var old_node := node_value as Node3D
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()
	part_surface_nodes.clear()
	part_surface_fields.clear()
	part_chunk_surface_nodes.clear()
	_applied_deformation_keys.clear()
	_presented_wounds.clear()
	_visual_aperture_radii.clear()
	_pending_visual_commit = false
	if anatomy_definition == null:
		return
	_tissue_material = ShaderMaterial.new()
	_tissue_material.shader = TISSUE_SHADER
	_tissue_material.set_shader_parameter(
		&"material_roughness",
		anatomy_definition.damage_texture.roughness
	)
	_tissue_material.set_shader_parameter(
		&"material_metallic",
		anatomy_definition.damage_texture.metallic
	)
	_register_tissue_pipeline()
	for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
		if part == null:
			continue
		var field := SparseSdfVolumeData.new().configure(
			part.sanitized_size(),
			anatomy_definition.voxel_size,
			anatomy_definition.brick_cells,
			anatomy_definition.damage_texture.material_index,
			4.0
		)
		field.structural_anchor_faces = part.structural_anchor_mask()
		part_surface_fields[part.part_id] = field
		var surface_root := Node3D.new()
		surface_root.name = "SdfTissue_%s" % part.part_id
		surface_root.visible = false
		add_child(surface_root)
		part_surface_nodes[part.part_id] = surface_root
		part_chunk_surface_nodes[part.part_id] = {}


func _register_tissue_pipeline() -> void:
	if _tissue_pipeline_registered or _tissue_material == null:
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.005, -0.005, 0.0),
		Vector3(0.005, -0.005, 0.0),
		Vector3(0.0, 0.005, 0.0),
	])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.RED, Color.RED])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var warmup := MeshInstance3D.new()
	warmup.name = TISSUE_PIPELINE_WARMUP_NAME
	warmup.mesh = mesh
	warmup.material_override = _tissue_material
	warmup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warmup.visible = false
	add_child(warmup)
	_tissue_pipeline_registered = true


func _rebuild_part_surfaces(raw_events: Variant) -> void:
	if anatomy_definition == null:
		return
	var events: Array = raw_events if raw_events is Array else []
	if events.is_empty():
		events = _legacy_deformation_events_from_wounds()
	var event_keys: Array[String] = []
	for event_value: Variant in events:
		event_keys.append(_deformation_event_key(event_value))
	var preserves_prefix := _applied_deformation_keys.size() <= event_keys.size()
	if preserves_prefix:
		for key_index: int in range(_applied_deformation_keys.size()):
			if _applied_deformation_keys[key_index] != event_keys[key_index]:
				preserves_prefix = false
				break
	if not preserves_prefix:
		# Live replication appends. Only a replacement/recovery snapshot rebuilds from the immutable
		# profile; normal bullets keep all six fields and never replay prior damage on the render thread.
		_reset_surface_fields()
		_full_replay_count += 1
	var first_new_event := _applied_deformation_keys.size()
	for event_index: int in range(first_new_event, events.size()):
		var raw_event: Variant = events[event_index]
		if not raw_event is Dictionary:
			continue
		var event_state := raw_event as Dictionary
		var part_id := StringName(str(event_state.get("part", &"")))
		var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
		if field == null:
			continue
		var damage_state: Variant = event_state.get("event", null)
		if not damage_state is Dictionary:
			continue
		var damage := DamageEvent.from_dict(damage_state)
		var local_position := damage.world_position
		var local_direction := damage.direction
		var local_normal := damage.normal
		var result := field.apply_damage_event(
			local_position,
			local_direction,
			local_normal,
			damage,
			anatomy_definition.damage_texture
		)
		if bool(result.get("geometry_changed", false)):
			var changed_chunks: Array[Vector3i] = result.get("changed_chunks", [])
			_queue_surface_chunks(
				part_id,
				_remesh_chunks_for_changed_samples(field, result, changed_chunks)
			)
	_applied_deformation_keys = event_keys
	if has_pending_surface_rebuilds():
		_pending_visual_commit = true
		set_process(true)
		_schedule_surface_jobs()
	else:
		_commit_target_wounds()


func _deformation_event_key(raw_event: Variant) -> String:
	if not raw_event is Dictionary:
		return "invalid:%d" % hash(raw_event)
	var state := raw_event as Dictionary
	var damage_state: Variant = state.get("event", {})
	if not damage_state is Dictionary:
		return "invalid:%d" % hash(state)
	var damage := damage_state as Dictionary
	return "%s:%d:%d:%d" % [
		str(state.get("part", &"")),
		int(damage.get("event_id", 0)),
		int(damage.get("sequence", 0)),
		int(damage.get("seed", 0)),
	]


func _reset_surface_fields() -> void:
	_discard_surface_jobs()
	_applied_deformation_keys.clear()
	_presented_wounds.clear()
	_visual_aperture_radii.clear()
	for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
		if part == null:
			continue
		var field := SparseSdfVolumeData.new().configure(
			part.sanitized_size(),
			anatomy_definition.voxel_size,
			anatomy_definition.brick_cells,
			anatomy_definition.damage_texture.material_index,
			4.0
		)
		field.structural_anchor_faces = part.structural_anchor_mask()
		part_surface_fields[part.part_id] = field
		var chunks_value: Variant = part_chunk_surface_nodes.get(part.part_id, {})
		if chunks_value is Dictionary:
			for node_value: Variant in (chunks_value as Dictionary).values():
				var node := node_value as MeshInstance3D
				if node != null and is_instance_valid(node):
					node.queue_free()
		part_chunk_surface_nodes[part.part_id] = {}


func _remesh_chunks_for_changed_samples(
	field: SparseSdfVolumeData,
	result: Dictionary,
	changed_chunks: Array[Vector3i]
) -> Array[Vector3i]:
	if changed_chunks.is_empty():
		return []
	if not bool(result.get("has_changed_sample_bounds", false)):
		return field.expanded_chunk_ring(changed_chunks, REMESH_NEIGHBOR_RING)
	var changed_minimum: Vector3i = result.get("changed_sample_minimum", Vector3i.ZERO)
	var changed_maximum: Vector3i = result.get("changed_sample_maximum", Vector3i.ZERO)
	var candidates := field.expanded_chunk_ring(changed_chunks, REMESH_NEIGHBOR_RING)
	var selected_count := 0
	var halo := SdfDualContouringMesher.SAMPLE_CACHE_HALO
	for candidate: Vector3i in candidates:
		if changed_chunks.has(candidate):
			candidates[selected_count] = candidate
			selected_count += 1
			continue
		var capture_minimum := candidate * field.brick_cells - Vector3i.ONE * halo
		var capture_maximum := (
			candidate * field.brick_cells
			+ Vector3i.ONE * (field.brick_cells + halo - 1)
		)
		if not (
			changed_maximum.x < capture_minimum.x
			or changed_minimum.x > capture_maximum.x
			or changed_maximum.y < capture_minimum.y
			or changed_minimum.y > capture_maximum.y
			or changed_maximum.z < capture_minimum.z
			or changed_minimum.z > capture_maximum.z
		):
			candidates[selected_count] = candidate
			selected_count += 1
	candidates.resize(selected_count)
	return candidates


func _queue_surface_chunks(part_id: StringName, coordinates: Array[Vector3i]) -> void:
	for coordinate: Vector3i in coordinates:
		_queue_surface_chunk(part_id, coordinate)


func _queue_surface_chunk(part_id: StringName, coordinate: Vector3i) -> void:
	var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
	if field == null or not field.brick_is_valid(coordinate):
		return
	var key := _surface_chunk_key(part_id, coordinate)
	if _dirty_surface_chunk_keys.has(key) or _surface_chunk_has_active_job(key):
		return
	_dirty_surface_chunk_keys[key] = true
	_dirty_surface_chunks.append({
		"part": part_id,
		"coordinate": coordinate,
		"key": key,
	})


func _surface_chunk_key(part_id: StringName, coordinate: Vector3i) -> String:
	return "%s:%d:%d:%d" % [part_id, coordinate.x, coordinate.y, coordinate.z]


func _surface_chunk_has_active_job(key: String) -> bool:
	for state: Dictionary in _active_surface_jobs:
		if str(state.get("key", "")) == key:
			return true
	return false


func _schedule_surface_jobs() -> void:
	var capacity := MAX_PARALLEL_SURFACE_JOBS - _active_surface_jobs.size()
	while capacity > 0 and not _dirty_surface_chunks.is_empty():
		var state := _dirty_surface_chunks.pop_back() as Dictionary
		var key := str(state.get("key", ""))
		_dirty_surface_chunk_keys.erase(key)
		if _surface_chunk_has_active_job(key):
			continue
		var part_id := StringName(str(state.get("part", &"")))
		var coordinate: Vector3i = state.get("coordinate", Vector3i.ZERO)
		var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
		if field == null:
			continue
		var job: SdfChunkBuildJob = (
			_surface_job_pool.pop_back()
			if not _surface_job_pool.is_empty()
			else SdfChunkBuildJob.new()
		)
		job.capture(field, coordinate)
		job.task_id = WorkerThreadPool.add_task(job.execute, false, "Enemy tissue chunk")
		state["job"] = job
		state["source_signature"] = int(job.snapshot.get("source_signature", -1))
		_active_surface_jobs.append(state)
		capacity -= 1


func _pump_surface_jobs() -> void:
	var remaining := MAX_SURFACE_COMMITS_PER_FRAME
	for job_index: int in range(_active_surface_jobs.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var state: Dictionary = _active_surface_jobs[job_index]
		var job := state.get("job") as SdfChunkBuildJob
		if job == null or job.task_id < 0 or not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_active_surface_jobs.remove_at(job_index)
		var part_id := StringName(str(state.get("part", &"")))
		var coordinate: Vector3i = state.get("coordinate", Vector3i.ZERO)
		var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
		if (
			field == null
			or int(state.get("source_signature", -1))
			!= field.chunk_sample_revision_signature(coordinate)
		):
			_queue_surface_chunk(part_id, coordinate)
		else:
			_surface_worker_usec += job.elapsed_usec
			_commit_surface_chunk(part_id, coordinate, field, job.result)
		_surface_job_pool.append(job)
		remaining -= 1
	_schedule_surface_jobs()
	if not has_pending_surface_rebuilds():
		if _pending_visual_commit:
			_commit_target_wounds()
		set_process(false)


func _commit_surface_chunk(
	part_id: StringName,
	coordinate: Vector3i,
	field: SparseSdfVolumeData,
	contour: Dictionary
) -> void:
	var started_usec := Time.get_ticks_usec()
	var build: Dictionary = SDF_INTERIOR_SURFACE_BUILDER.build_chunk(
		field,
		anatomy_definition.damage_texture,
		coordinate,
		contour
	)
	_pending_chunk_meshes[_surface_chunk_key(part_id, coordinate)] = {
		"part": part_id,
		"coordinate": coordinate,
		"mesh": build.get("mesh") as ArrayMesh,
	}
	_surface_rebuild_count += 1
	_surface_commit_usec += Time.get_ticks_usec() - started_usec


func _apply_surface_chunk_mesh(
	part_id: StringName,
	coordinate: Vector3i,
	mesh: ArrayMesh
) -> void:
	var chunks_value: Variant = part_chunk_surface_nodes.get(part_id, {})
	if not chunks_value is Dictionary:
		return
	var chunks := chunks_value as Dictionary
	var surface := chunks.get(coordinate) as MeshInstance3D
	if mesh == null:
		if surface != null:
			surface.mesh = null
			surface.visible = false
	else:
		if surface == null:
			surface = MeshInstance3D.new()
			surface.name = "Chunk_%d_%d_%d" % [coordinate.x, coordinate.y, coordinate.z]
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			surface.material_override = _tissue_material
			var root := part_surface_nodes.get(part_id) as Node3D
			if root == null:
				return
			root.add_child(surface)
			chunks[coordinate] = surface
		surface.mesh = mesh
		surface.visible = _part_surface_should_be_visible(part_id)
	part_chunk_surface_nodes[part_id] = chunks


func _commit_target_wounds() -> void:
	for state: Dictionary in _pending_chunk_meshes.values():
		_apply_surface_chunk_mesh(
			StringName(str(state.get("part", &""))),
			state.get("coordinate", Vector3i.ZERO),
			state.get("mesh") as ArrayMesh
		)
	_pending_chunk_meshes.clear()
	_refresh_surface_attachments()
	_presented_wounds.assign(target_wounds)
	_refresh_visual_aperture_radii()
	_pending_visual_commit = false


func _discard_surface_jobs() -> void:
	# Reconfiguration is rare and must not leave a worker writing into a recycled job object.
	for state: Dictionary in _active_surface_jobs:
		var job := state.get("job") as SdfChunkBuildJob
		if job != null and job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			job.task_id = -1
			_surface_job_pool.append(job)
	_active_surface_jobs.clear()
	_dirty_surface_chunks.clear()
	_dirty_surface_chunk_keys.clear()
	_pending_chunk_meshes.clear()
	set_process(false)


func _legacy_deformation_events_from_wounds() -> Array:
	# Compatibility for old captures and hand-authored tests. Live authority always supplies exact
	# canonical events; this path still uses the same SDF and mesher rather than reviving visual balls.
	var result: Array = []
	for wound: Dictionary in target_wounds:
		if bool(wound.get("stump", false)):
			continue
		var part_id := StringName(str(wound.get("part", &"")))
		var part := anatomy_definition.get_part(part_id)
		if part == null:
			continue
		var local_position: Vector3 = wound.get("local_position", part.local_center)
		var direction: Vector3 = wound.get("local_direction", Vector3.FORWARD)
		var field_position := local_position - part.local_center
		var radius := float(wound.get("radius", 0.03))
		var depth := float(wound.get("depth", radius * 1.4))
		result.append({
			"part": part_id,
			"event": {
				"event_id": int(wound.get("event_id", result.size() + 1)),
				"sequence": int(wound.get("event_id", result.size() + 1)),
				"source_kind": &"legacy_enemy_wound",
				"world_position": field_position,
				"normal": -direction,
				"direction": direction,
				"brush_kind": DamageEvent.BRUSH_CAPSULE,
				"radius": radius,
				"length": depth,
				"penetration": depth,
				"energy": maxf(anatomy_definition.damage_texture.geometry_threshold + 1.0, 8.0),
				"damage_tags": PackedStringArray([DamageEvent.TAG_BALLISTIC]),
				"seed": int(wound.get("event_id", result.size() + 1)),
			},
		})
	return result


func _update_part_surface_transforms() -> void:
	if anatomy_definition == null:
		return
	for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
		if part == null:
			continue
		var surface := part_surface_nodes.get(part.part_id) as Node3D
		if surface == null:
			continue
		var fallback_transform := _profile_part_world_transform(part)
		surface.global_transform = fallback_transform
		surface.visible = _part_surface_should_be_visible(part.part_id)
		var chunks_value: Variant = part_chunk_surface_nodes.get(part.part_id, {})
		if not chunks_value is Dictionary:
			continue
		var field := part_surface_fields.get(part.part_id) as SparseSdfVolumeData
		for coordinate_value: Variant in (chunks_value as Dictionary).keys():
			var coordinate: Vector3i = coordinate_value
			var chunk := (chunks_value as Dictionary).get(coordinate) as MeshInstance3D
			if chunk == null or field == null:
				continue
			chunk.global_transform = _chunk_world_transform(
				part,
				field,
				coordinate,
				fallback_transform
			)


func _chunk_world_transform(
	part: EnemyAnatomyPartDefinition,
	field: SparseSdfVolumeData,
	coordinate: Vector3i,
	fallback: Transform3D
) -> Transform3D:
	if not _surface_sampler.is_usable():
		return fallback
	var nearest_wound := _nearest_attached_wound(part, field, coordinate)
	if nearest_wound.is_empty():
		return fallback
	var resolved := _resolve_wound_world_frame(nearest_wound)
	if resolved.is_empty():
		return fallback
	var field_hit: Vector3 = (
		nearest_wound.get("local_position", part.local_center)
		- part.local_center
	)
	var resolved_basis: Basis = resolved.get("basis", fallback.basis)
	return Transform3D(
		resolved_basis,
		resolved.get("position", fallback * field_hit) - resolved_basis * field_hit
	)


func _nearest_attached_wound(
	part: EnemyAnatomyPartDefinition,
	field: SparseSdfVolumeData,
	coordinate: Vector3i
) -> Dictionary:
	var chunk_center := (
		field.brick_origin(coordinate)
		+ Vector3.ONE * field.brick_extent * 0.5
	)
	var nearest_wound: Dictionary = {}
	var nearest_distance_squared := INF
	for wound: Dictionary in _presented_wounds:
		if (
			bool(wound.get("stump", false))
			or StringName(str(wound.get("part", &""))) != part.part_id
			or not _surface_attachments.has(_wound_attachment_key(wound))
		):
			continue
		var field_hit: Vector3 = wound.get("local_position", part.local_center) - part.local_center
		var distance_squared := chunk_center.distance_squared_to(field_hit)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_wound = wound
	return nearest_wound


func _profile_part_world_transform(part: EnemyAnatomyPartDefinition) -> Transform3D:
	var root_basis := character_skin.global_basis.orthonormalized()
	if part.presentation_start_bone.is_empty() or character_skin.skeleton == null:
		return Transform3D(
			root_basis,
			character_skin.global_transform * part.local_center
		)
	var start := _bone_world_origin(part.presentation_start_bone)
	if part.presentation_end_bone.is_empty():
		return Transform3D(
			root_basis,
			start + root_basis * (part.local_center - part.rest_axis_start)
		)
	var end := _bone_world_origin(part.presentation_end_bone)
	var rest_delta := part.rest_axis_end - part.rest_axis_start
	var current_delta := end - start
	if rest_delta.length_squared() <= 0.000001 or current_delta.length_squared() <= 0.000001:
		return Transform3D(
			root_basis,
			start + root_basis * (part.local_center - part.rest_axis_start)
		)
	var t := clampf(
		(part.local_center - part.rest_axis_start).dot(rest_delta) / rest_delta.length_squared(),
		0.0,
		1.0
	)
	var rest_axis_position := part.rest_axis_start + rest_delta * t
	var axis_mapping := (
		LimbKinematics.basis_from_y(current_delta)
		* LimbKinematics.basis_from_y(rest_delta).inverse()
	)
	return Transform3D(
		axis_mapping,
		start.lerp(end, t) + axis_mapping * (part.local_center - rest_axis_position)
	)


func _sanitize_wound(value: Dictionary) -> Dictionary:
	var part_id := StringName(str(value.get("part", &"")))
	if (
		part_id.is_empty()
		or (
			anatomy_definition != null
			and anatomy_definition.get_part(part_id) == null
		)
		or (
			anatomy_definition == null
			and not ANATOMY.PART_ORDER.has(part_id)
		)
	):
		return {}
	var local_position: Variant = value.get("local_position", null)
	var local_direction: Variant = value.get("local_direction", null)
	if not local_position is Vector3 or not local_direction is Vector3:
		return {}
	if not (local_position as Vector3).is_finite() or not (local_direction as Vector3).is_finite():
		return {}
	return {
		"event_id": maxi(int(value.get("event_id", 0)), 0),
		"part": part_id,
		"local_position": local_position,
		"local_direction": (local_direction as Vector3).normalized(),
		"radius": clampf(float(value.get("radius", 0.03)), 0.005, 0.3),
		"depth": clampf(float(value.get("depth", 0.05)), 0.005, 1.5),
		"stump": bool(value.get("stump", false)),
	}


func _append_missing_limb_stumps() -> void:
	if anatomy_definition != null:
		for part: EnemyAnatomyPartDefinition in anatomy_definition.parts:
			if (
				part == null
				or not part.severable
				or _part_is_present(part.part_id)
				or target_wounds.size() >= MAX_WOUNDS
			):
				continue
			target_wounds.append({
				"event_id": 0,
				"part": part.part_id,
				"local_position": part.stump_local_position,
				"local_direction": part.stump_inward_direction.normalized(),
				"radius": part.stump_radius,
				"depth": part.stump_radius * 1.8,
				"stump": true,
			})
		return
	var stump_layout := {
		ANATOMY.PART_LEFT_ARM: [Vector3(-0.32, 1.47, 0.0), 0.105],
		ANATOMY.PART_RIGHT_ARM: [Vector3(0.32, 1.47, 0.0), 0.105],
		ANATOMY.PART_LEFT_LEG: [Vector3(-0.17, 0.91, 0.0), 0.12],
		ANATOMY.PART_RIGHT_LEG: [Vector3(0.17, 0.91, 0.0), 0.12],
	}
	for part_id: StringName in stump_layout.keys():
		if _part_is_present(part_id) or target_wounds.size() >= MAX_WOUNDS:
			continue
		var descriptor: Array = stump_layout[part_id]
		target_wounds.append({
			"event_id": 0,
			"part": part_id,
			"local_position": descriptor[0],
			"local_direction": Vector3.UP if str(part_id).ends_with("leg") else (
				Vector3.RIGHT if part_id == ANATOMY.PART_LEFT_ARM else Vector3.LEFT
			),
			"radius": float(descriptor[1]),
			"depth": float(descriptor[1]) * 1.8,
			"stump": true,
		})


func _refresh_surface_attachments() -> void:
	if not _surface_sampler.is_usable():
		_surface_attachments.clear()
		return
	var retained: Dictionary[String, Dictionary] = {}
	for wound: Dictionary in target_wounds:
		if bool(wound.get("stump", false)):
			continue
		var key := _wound_attachment_key(wound)
		var attachment := _surface_attachments.get(key, {}) as Dictionary
		if attachment.is_empty():
			attachment = _capture_surface_attachment(wound)
		if not attachment.is_empty():
			retained[key] = attachment
	_surface_attachments = retained
	_resolved_attachment_frames.clear()


func _refresh_visual_aperture_radii() -> void:
	_visual_aperture_radii.clear()
	if anatomy_definition == null:
		return
	for wound: Dictionary in _presented_wounds:
		var key := _wound_attachment_key(wound)
		var base_radius := float(wound.get("radius", 0.03))
		if bool(wound.get("stump", false)):
			_visual_aperture_radii[key] = base_radius
			continue
		var part_id := StringName(str(wound.get("part", &"")))
		var part := anatomy_definition.get_part(part_id)
		var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
		var chunks_value: Variant = part_chunk_surface_nodes.get(part_id, {})
		if part == null or field == null or not chunks_value is Dictionary:
			_visual_aperture_radii[key] = base_radius
			continue
		var field_hit: Vector3 = wound.get("local_position", part.local_center) - part.local_center
		var direction: Vector3 = wound.get("local_direction", Vector3.FORWARD)
		direction = direction.normalized() if direction.length_squared() > 0.000001 else Vector3.FORWARD
		var measured_radius := base_radius
		var mouth_depth := maxf(field.voxel_size * 4.0, base_radius * 2.5)
		var candidate_limit := base_radius + field.voxel_size * 3.0
		for node_value: Variant in (chunks_value as Dictionary).values():
			var chunk := node_value as MeshInstance3D
			if chunk == null or chunk.mesh == null:
				continue
			for surface_index: int in range(chunk.mesh.get_surface_count()):
				var arrays := chunk.mesh.surface_get_arrays(surface_index)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				for vertex: Vector3 in vertices:
					var from_hit := vertex - field_hit
					var axial := from_hit.dot(direction)
					if axial < -field.voxel_size * 1.5 or axial > mouth_depth:
						continue
					var radial := (from_hit - direction * axial).length()
					if radial <= candidate_limit:
						measured_radius = maxf(measured_radius, radial)
		# Dual contouring may place the last cavity vertex just outside the analytic brush. Let the
		# imported shell overlap the actual SDF mouth by a fraction of a voxel, while bounding that
		# allowance so a neighboring wound can never recreate a tank-sized aperture.
		_visual_aperture_radii[key] = minf(
			measured_radius + field.voxel_size * 0.35,
			base_radius + field.voxel_size
		)


func _visual_shell_aperture_depth(
	wound: Dictionary,
	radius: float,
	part_id: StringName
) -> float:
	var simulated_depth := maxf(float(wound.get("depth", radius)), radius)
	var field := part_surface_fields.get(part_id) as SparseSdfVolumeData
	var minimum_depth := (
		field.voxel_size * SHELL_APERTURE_MINIMUM_VOXELS
		if field != null
		else radius
	)
	# Ballistic penetration belongs to the SDF/material simulation. The imported skin is only a
	# zero-thickness presentation shell, so extending its clip capsule through the full projectile
	# range erases the far side (or a folded neighboring limb). Clip just enough shell around the
	# measured mouth. A real exit can later be represented by its own second surface attachment.
	return minf(
		simulated_depth,
		maxf(radius * SHELL_APERTURE_DEPTH_PER_RADIUS, minimum_depth)
	)


func _capture_surface_attachment(wound: Dictionary) -> Dictionary:
	var local_position: Vector3 = wound.get("local_position", Vector3.ZERO)
	var local_direction: Vector3 = wound.get("local_direction", Vector3.FORWARD)
	if local_direction.length_squared() <= 0.000001:
		return {}
	var world_direction := (global_basis * local_direction).normalized()
	var part_id := StringName(str(wound.get("part", &"")))
	var part := anatomy_definition.get_part(part_id) if anatomy_definition != null else null
	var reference_basis := (
		_profile_part_world_transform(part).basis
		if part != null
		else global_basis.orthonormalized()
	)
	var ray_span := maxf(
		part.sanitized_size().length() * 1.25 if part != null else 1.0,
		0.8
	)
	var estimated_world_position := global_transform * local_position
	return _surface_sampler.capture_first_surface(
		estimated_world_position - world_direction * ray_span,
		world_direction,
		reference_basis,
		ray_span * 2.0
	)


func _wound_attachment_key(wound: Dictionary) -> String:
	var position: Vector3 = wound.get("local_position", Vector3.ZERO)
	var direction: Vector3 = wound.get("local_direction", Vector3.FORWARD)
	return "%s:%d:%d:%d:%d:%d:%d:%d" % [
		str(wound.get("part", &"")),
		int(wound.get("event_id", 0)),
		roundi(position.x * 10000.0),
		roundi(position.y * 10000.0),
		roundi(position.z * 10000.0),
		roundi(direction.x * 1000.0),
		roundi(direction.y * 1000.0),
		roundi(direction.z * 1000.0),
	]


func _prepare_attachment_frames() -> void:
	_resolved_attachment_frames.clear()
	if not _surface_sampler.is_usable():
		return
	_surface_sampler.prepare_pose()
	for wound: Dictionary in _presented_wounds:
		var key := _wound_attachment_key(wound)
		var attachment := _surface_attachments.get(key, {}) as Dictionary
		if attachment.is_empty():
			continue
		var resolved: Dictionary = _surface_sampler.resolve_attachment(
			attachment,
			false
		)
		if not resolved.is_empty():
			_resolved_attachment_frames[key] = resolved


func _resolve_wound_world_frame(wound: Dictionary) -> Dictionary:
	var key := _wound_attachment_key(wound)
	var cached := _resolved_attachment_frames.get(key, {}) as Dictionary
	if not cached.is_empty():
		return cached
	var attachment := _surface_attachments.get(key, {}) as Dictionary
	if not attachment.is_empty():
		var resolved: Dictionary = _surface_sampler.resolve_attachment(attachment)
		if not resolved.is_empty():
			_resolved_attachment_frames[key] = resolved
			return resolved
	var local_position: Vector3 = wound.get("local_position", Vector3.ZERO)
	var local_direction: Vector3 = wound.get("local_direction", Vector3.FORWARD)
	var part_id := StringName(str(wound.get("part", &"")))
	var part := (
		anatomy_definition.get_part(part_id)
		if anatomy_definition != null
		else null
	)
	if part != null:
		return _profile_wound_world_frame(local_position, local_direction, part)
	return _legacy_wound_world_frame(local_position, local_direction, part_id)


func _profile_wound_world_frame(
	local_position: Vector3,
	local_direction: Vector3,
	part: EnemyAnatomyPartDefinition
) -> Dictionary:
	var root_basis := character_skin.global_basis.orthonormalized()
	if (
		part.presentation_start_bone.is_empty()
		or character_skin.skeleton == null
	):
		return {
			"position": character_skin.global_transform * local_position,
			"direction": (root_basis * local_direction).normalized(),
		}
	var start := _bone_world_origin(part.presentation_start_bone)
	if part.presentation_end_bone.is_empty():
		return {
			"position": start + root_basis * (local_position - part.rest_axis_start),
			"direction": (root_basis * local_direction).normalized(),
		}
	var end := _bone_world_origin(part.presentation_end_bone)
	var rest_delta := part.rest_axis_end - part.rest_axis_start
	var current_delta := end - start
	if rest_delta.length_squared() <= 0.000001 or current_delta.length_squared() <= 0.000001:
		return {
			"position": start + root_basis * (local_position - part.rest_axis_start),
			"direction": (root_basis * local_direction).normalized(),
		}
	var t := clampf(
		(local_position - part.rest_axis_start).dot(rest_delta) / rest_delta.length_squared(),
		0.0,
		1.0
	)
	var rest_axis_position := part.rest_axis_start + rest_delta * t
	var rest_basis := LimbKinematics.basis_from_y(rest_delta)
	var current_basis := LimbKinematics.basis_from_y(current_delta)
	var axis_mapping := current_basis * rest_basis.inverse()
	return {
		"position": start.lerp(end, t) + axis_mapping * (local_position - rest_axis_position),
		"direction": (axis_mapping * local_direction).normalized(),
	}


func _legacy_wound_world_frame(
	local_position: Vector3,
	local_direction: Vector3,
	part_id: StringName
) -> Dictionary:
	var root_basis := character_skin.global_basis.orthonormalized()
	var position := character_skin.global_transform * local_position
	match part_id:
		ANATOMY.PART_HEAD:
			position = _bone_world_origin(&"mixamorig_Head") + root_basis * (
				local_position - Vector3(0.0, 1.66, 0.0)
			)
		ANATOMY.PART_TORSO:
			position = _bone_world_origin(&"mixamorig_Spine1") + root_basis * (
				local_position - Vector3(0.0, 1.18, 0.0)
			)
		ANATOMY.PART_LEFT_ARM:
			position = _limb_world_position(
				local_position,
				-0.38,
				&"mixamorig_LeftArm",
				&"mixamorig_LeftHand",
				1.53,
				1.00
			)
		ANATOMY.PART_RIGHT_ARM:
			position = _limb_world_position(
				local_position,
				0.38,
				&"mixamorig_RightArm",
				&"mixamorig_RightHand",
				1.53,
				1.00
			)
		ANATOMY.PART_LEFT_LEG:
			position = _limb_world_position(
				local_position,
				-0.17,
				&"mixamorig_LeftUpLeg",
				&"mixamorig_LeftFoot",
				0.92,
				0.05
			)
		ANATOMY.PART_RIGHT_LEG:
			position = _limb_world_position(
				local_position,
				0.17,
				&"mixamorig_RightUpLeg",
				&"mixamorig_RightFoot",
				0.92,
				0.05
			)
	return {
		"position": position,
		"direction": (root_basis * local_direction).normalized(),
	}


func _limb_world_position(
	local_position: Vector3,
	rest_x: float,
	start_bone: StringName,
	end_bone: StringName,
	rest_start_y: float,
	rest_end_y: float
) -> Vector3:
	var start := _bone_world_origin(start_bone)
	var end := _bone_world_origin(end_bone)
	var t := clampf(inverse_lerp(rest_start_y, rest_end_y, local_position.y), 0.0, 1.0)
	var root_basis := character_skin.global_basis.orthonormalized()
	return (
		start.lerp(end, t)
		+ root_basis.x * (local_position.x - rest_x)
		+ root_basis.z * local_position.z
	)


func _bone_world_origin(bone_name: StringName) -> Vector3:
	if character_skin == null or character_skin.skeleton == null:
		return global_position
	var bone_index := character_skin.skeleton.find_bone(bone_name)
	if bone_index < 0:
		return global_position
	return (
		character_skin.skeleton.global_transform
		* character_skin.skeleton.get_bone_global_pose(bone_index)
	).origin


func _part_is_present(part_id: StringName) -> bool:
	return not target_part_presence.has(part_id) or bool(target_part_presence[part_id])


func _part_surface_should_be_visible(part_id: StringName) -> bool:
	if _part_is_present(part_id):
		return true
	for wound: Dictionary in target_wounds:
		if (
			bool(wound.get("stump", false))
			and StringName(str(wound.get("part", &""))) == part_id
		):
			return true
	return false
