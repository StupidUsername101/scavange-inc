@tool
class_name DestructibleVolume3D
extends Node3D

## Opt-in finite destructible volume. Untouched volumes remain cheap boxes. The first accepted edit
## stages one globally-owned generated surface behind the boxes, then atomically switches render and
## collision once every chunk is ready. Later edits rebuild only their affected chunk neighborhood.

signal damage_committed(event: DamageEvent, result: Dictionary)
signal acoustic_aperture_changed(world_bounds: AABB, revision: int)

const DEFAULT_PHYSICAL_SURFACE := &"concrete"
const MIN_SIZE := 0.01
const MIN_DIRECTION_LENGTH_SQUARED := 0.000001
const RUNTIME_WARMUP_NAME := &"DestructionGeneratedSurfaceWarmup"
const RUNTIME_THERMAL_WARMUP_NAME := &"DestructionThermalCutWarmup"

# Generated wall patches are the first meshes in the game to combine a runtime ArrayMesh color
# stream with this StandardMaterial3D variant. Forward+/Mobile can only precompile that surface
# pipeline after it has seen one matching instance in the SceneTree. Keep one invisible instance
# alive from world loading onward so the first real bullet never becomes a shader-discovery event.
static var _generated_surface_pipeline_registered := false

@export_group("Identity")
@export var volume_id := &"destructible"
@export var enabled := true
@export var authoritative := true
@export var create_collision := true
@export var physical_surface := DEFAULT_PHYSICAL_SURFACE
@export var destruction_texture: DestructionTextureDefinition

@export_group("Volume")
@export var volume_size := Vector3(4.0, 3.0, 0.45)
@export_range(0.01, 0.5, 0.005, "or_greater") var voxel_size := 0.06
@export_range(4, 48, 1) var brick_cells := 16
@export_range(2.0, 8.0, 0.25) var narrow_band_voxels := 4.0

@export_group("Structural Support")
@export_flags(
	"Negative X",
	"Positive X",
	"Negative Y (Ground)",
	"Positive Y (Ceiling)",
	"Negative Z",
	"Positive Z"
) var structural_anchor_faces := SdfStructuralFragmenter.ANCHOR_NEGATIVE_Y

@export_group("Scheduling")
@export_range(1, 8, 1) var maximum_chunk_rebuilds_per_frame := 1
@export_range(1, 8, 1) var maximum_parallel_chunk_jobs := 2
@export_range(0, 2, 1) var remesh_neighbor_ring := 1

@export_group("Presentation")
@export var cast_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON

var field: SparseSdfVolumeData

var _profile: DestructionTextureDefinition
var _surface_material: StandardMaterial3D
var _generated_surface_material: StandardMaterial3D
var _thermal_overlay: ThermalCutOverlay3D
var _base_visuals: Dictionary[Vector3i, MeshInstance3D] = {}
var _base_bodies: Dictionary[Vector3i, DestructibleCollisionBody3D] = {}
var _base_shapes: Dictionary[Vector3i, CollisionShape3D] = {}
var _generated_visuals: Dictionary[Vector3i, MeshInstance3D] = {}
var _generated_bodies: Dictionary[Vector3i, DestructibleCollisionBody3D] = {}
var _generated_shapes: Dictionary[Vector3i, CollisionShape3D] = {}
var _generated_collision_faces: Dictionary[Vector3i, PackedVector3Array] = {}
var _dirty_chunks: Array[Vector3i] = []
var _dirty_chunk_flags := PackedByteArray()
var _active_chunk_jobs: Array[SdfChunkBuildJob] = []
var _chunk_job_pool: Array[SdfChunkBuildJob] = []
var _edited_chunks: Dictionary[Vector3i, bool] = {}
var _generated_surface_active := false
var _full_surface_transition_pending := false
var _accumulated_open_area := 0.0
var _acoustic_aperture_cells: Dictionary[Vector3i, bool] = {}
var _acoustic_aperture_open := false
var _initialized := false
var _rebuild_count := 0
var _last_rebuilt_revision := 0
var _committed_event_count := 0
var _evaluated_event_count := 0
var _rejected_event_count := 0
var _event_apply_total_usec := 0
var _event_apply_max_usec := 0
var _rebuild_total_usec := 0
var _rebuild_max_usec := 0
var _maximum_queue_depth := 0
var _queue_started_usec := 0
var _discarded_stale_jobs := 0


func _ready() -> void:
	initialize_volume()


func initialize_volume() -> void:
	if _initialized:
		return
	volume_size = Vector3(
		maxf(absf(volume_size.x), MIN_SIZE),
		maxf(absf(volume_size.y), MIN_SIZE),
		maxf(absf(volume_size.z), MIN_SIZE)
	)
	if volume_id.is_empty():
		volume_id = StringName(name.to_snake_case())
	_profile = (
		destruction_texture
		if destruction_texture != null
		else DestructionMaterialRegistry.profile_for(physical_surface)
	)
	_profile.sanitize()
	physical_surface = _profile.physical_surface
	field = SparseSdfVolumeData.new().configure(
		volume_size,
		voxel_size,
		brick_cells,
		_profile.material_index,
		narrow_band_voxels
	)
	field.structural_anchor_faces = clampi(
		structural_anchor_faces,
		0,
		SdfStructuralFragmenter.ALL_ANCHOR_FACES
	)
	_dirty_chunk_flags.resize(field.brick_counts.x * field.brick_counts.y * field.brick_counts.z)
	_dirty_chunk_flags.fill(0)
	_surface_material = _create_surface_material(_profile)
	_generated_surface_material = _create_generated_surface_material(_profile)
	_build_base_chunks()
	_register_generated_surface_pipeline()
	add_to_group(&"destructible_volumes")
	_initialized = true
	set_process(false)


func _process(_delta: float) -> void:
	var remaining := maxi(maximum_chunk_rebuilds_per_frame, 1)
	for job_index: int in range(_active_chunk_jobs.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var job := _active_chunk_jobs[job_index]
		var coordinate: Vector3i = job.coordinate if job != null else Vector3i.ZERO
		var task_id := job.task_id if job != null else -1
		if task_id < 0 or not WorkerThreadPool.is_task_completed(task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(task_id)
		_active_chunk_jobs.remove_at(job_index)
		if (
			job == null
			or int(job.snapshot.get("source_signature", -1))
			!= field.chunk_sample_revision_signature(coordinate)
		):
			_discarded_stale_jobs += 1
			_recycle_chunk_job(job)
			_queue_chunk(coordinate)
			continue
		_rebuild_chunk(coordinate, job.result, job.elapsed_usec)
		_recycle_chunk_job(job)
		remaining -= 1
	_schedule_chunk_jobs()
	if _dirty_chunks.is_empty() and _active_chunk_jobs.is_empty():
		_commit_generated_surface_transition()
		set_process(false)
		_queue_started_usec = 0


func apply_authoritative_damage_event(event: DamageEvent) -> Dictionary:
	return _apply_damage_event(event, true)


func apply_replicated_damage_event(event: DamageEvent, expected_from_revision: int) -> Dictionary:
	if not _initialized:
		initialize_volume()
	if field.revision != expected_from_revision:
		return {
			"changed": false,
			"reason": &"revision_gap",
			"expected": expected_from_revision,
			"actual": field.revision,
		}
	return _apply_damage_event(event, false)


func accepts_current_sdf_hit(world_position: Vector3, world_direction: Vector3) -> bool:
	if not _initialized:
		initialize_volume()
	var local_position := to_local(world_position)
	var local_direction := global_basis.inverse() * world_direction
	if local_direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		local_direction = Vector3.FORWARD
	local_direction = local_direction.normalized()
	# The physics ray reports the old triangle/box surface. Probe just inside and just outside the
	# current field; a real solid boundary has negative matter on at least one side, while a stale
	# collider over an opened hole has air on both sides.
	var probe_distance := field.voxel_size * 0.65
	return (
		field.sample_distance(local_position + local_direction * probe_distance) <= 0.0
		or field.sample_distance(local_position - local_direction * probe_distance) <= 0.0
	)


func flush_pending_rebuilds() -> void:
	for job: SdfChunkBuildJob in _active_chunk_jobs:
		var coordinate: Vector3i = job.coordinate if job != null else Vector3i.ZERO
		var task_id := job.task_id if job != null else -1
		if task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(task_id)
		if (
			job != null
			and int(job.snapshot.get("source_signature", -1))
			== field.chunk_sample_revision_signature(coordinate)
		):
			_rebuild_chunk(coordinate, job.result, job.elapsed_usec)
		else:
			# flush_pending_rebuilds() is the synchronous barrier used by tests/checkpoints. Rebuild a
			# stale capture immediately instead of allocating another queue entry that cannot run until
			# after the active array has been cleared.
			_rebuild_chunk(coordinate)
		_recycle_chunk_job(job)
	_active_chunk_jobs.clear()
	while not _dirty_chunks.is_empty():
		var coordinate: Vector3i = _dirty_chunks.pop_back() as Vector3i
		var flat_index := coordinate.x + field.brick_counts.x * (
			coordinate.y + field.brick_counts.y * coordinate.z
		)
		_dirty_chunk_flags[flat_index] = 0
		_rebuild_chunk(coordinate)
	_commit_generated_surface_transition()
	set_process(false)
	_queue_started_usec = 0


func checkpoint() -> Dictionary:
	if not _initialized:
		initialize_volume()
	return {
		"volume_id": volume_id,
		"bake_hash": bake_hash(),
		"revision": field.revision,
		"checksum": field.checksum(),
		"bricks": field.changed_brick_states(),
		"edited_chunks": _edited_chunk_array(),
		"generated_surface_active": _generated_surface_active,
		"acoustic_open_area": _accumulated_open_area,
		"acoustic_aperture_cells": _acoustic_aperture_cell_array(),
		"fragment_scan_regions": field.fragment_scan_region_states(),
		"thermal_cuts": (
			_thermal_overlay.checkpoint_state()
			if _thermal_overlay != null
			else []
		),
	}


func apply_checkpoint(value: Dictionary) -> bool:
	if not _initialized:
		initialize_volume()
	if (
		StringName(str(value.get("volume_id", &""))) != volume_id
		or int(value.get("bake_hash", -1)) != bake_hash()
	):
		return false
	var states: Array = value.get("bricks", [])
	if not field.apply_checkpoint(int(value.get("revision", 0)), states):
		return false
	field.restore_fragment_scan_regions(value.get("fragment_scan_regions", []))
	# A recovery checkpoint replaces the complete sparse state. Any queued/worker topology belongs to
	# the previous state and can have the same revision signature despite different bytes, so it must
	# never be allowed to commit afterward. Reset presentation to the analytic base before rebuilding
	# the checkpoint's edited ring; this also removes holes that are absent from the recovered state.
	_discard_pending_rebuilds()
	_restore_base_presentation()
	_edited_chunks.clear()
	var raw_edited: Array = value.get("edited_chunks", [])
	for raw_coordinate: Variant in raw_edited:
		if raw_coordinate is Vector3i and field.brick_is_valid(raw_coordinate):
			_edited_chunks[raw_coordinate] = true
	_generated_surface_active = (
		bool(value.get("generated_surface_active", false))
		or not _edited_chunks.is_empty()
	)
	_full_surface_transition_pending = _generated_surface_active
	_acoustic_aperture_cells.clear()
	var raw_aperture_cells: Variant = value.get("acoustic_aperture_cells", [])
	if raw_aperture_cells is Array:
		for raw_cell: Variant in raw_aperture_cells:
			if raw_cell is Vector3i:
				_acoustic_aperture_cells[raw_cell] = true
	_accumulated_open_area = (
		float(_acoustic_aperture_cells.size()) * field.voxel_size * field.voxel_size
		if not _acoustic_aperture_cells.is_empty()
		else maxf(float(value.get("acoustic_open_area", 0.0)), 0.0)
	)
	_acoustic_aperture_open = _accumulated_open_area >= _profile.acoustic_aperture_area
	_restore_thermal_cut_checkpoint(value.get("thermal_cuts", []))
	_queue_chunks(
		_all_chunk_coordinates()
		if _generated_surface_active
		else field.expanded_chunk_ring(_edited_chunk_array(), remesh_neighbor_ring)
	)
	return true


func _discard_pending_rebuilds() -> void:
	for job: SdfChunkBuildJob in _active_chunk_jobs:
		if job != null and job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		_recycle_chunk_job(job)
	_active_chunk_jobs.clear()
	_dirty_chunks.clear()
	_dirty_chunk_flags.fill(0)
	set_process(false)
	_queue_started_usec = 0


func _restore_base_presentation() -> void:
	_generated_surface_active = false
	_full_surface_transition_pending = false
	for visual: MeshInstance3D in _base_visuals.values():
		if is_instance_valid(visual):
			visual.visible = true
	for shape: CollisionShape3D in _base_shapes.values():
		if is_instance_valid(shape):
			shape.set_deferred("disabled", false)
	var generated_coordinates: Array = _generated_visuals.keys()
	for coordinate: Vector3i in generated_coordinates:
		_remove_generated_chunk(coordinate)
	# A generated collision body can exist without a visual when rendering failed closed. Clear that
	# residual path too instead of leaving a checkpoint client with stale collision.
	generated_coordinates = _generated_bodies.keys()
	for coordinate: Vector3i in generated_coordinates:
		_remove_generated_chunk(coordinate)


func bake_hash() -> int:
	var value := hash(str(volume_id))
	value = _hash_step(value, roundi(volume_size.x * 1000.0))
	value = _hash_step(value, roundi(volume_size.y * 1000.0))
	value = _hash_step(value, roundi(volume_size.z * 1000.0))
	value = _hash_step(value, roundi(voxel_size * 100000.0))
	value = _hash_step(value, brick_cells)
	value = _hash_step(value, structural_anchor_faces)
	value = _hash_step(value, _profile.content_signature() if _profile != null else 0)
	return value & 0x7fffffff


func world_bounds() -> AABB:
	var local_bounds := AABB(-volume_size * 0.5, volume_size)
	return global_transform * local_bounds


func debug_state() -> Dictionary:
	return {
		"volume_id": volume_id,
		"bake_hash": bake_hash(),
		"profile": _profile.texture_id if _profile != null else &"",
		"field": field.debug_state() if field != null else {},
		"queued_chunks": _dirty_chunks.size(),
		"active_chunk_jobs": _active_chunk_jobs.size(),
		"pooled_chunk_jobs": _chunk_job_pool.size(),
		"edited_chunks": _edited_chunks.size(),
		"generated_surface_active": _generated_surface_active,
		"full_surface_transition_pending": _full_surface_transition_pending,
		"generated_visuals": _generated_visuals.size(),
		"generated_bodies": _generated_bodies.size(),
		"rebuild_count": _rebuild_count,
		"last_rebuilt_revision": _last_rebuilt_revision,
		"committed_events": _committed_event_count,
		"evaluated_events": _evaluated_event_count,
		"rejected_events": _rejected_event_count,
		"event_apply_average_usec": (
			float(_event_apply_total_usec) / float(_evaluated_event_count)
			if _evaluated_event_count > 0
			else 0.0
		),
		"event_apply_max_usec": _event_apply_max_usec,
		"rebuild_average_usec": (
			float(_rebuild_total_usec) / float(_rebuild_count)
			if _rebuild_count > 0
			else 0.0
		),
		"rebuild_max_usec": _rebuild_max_usec,
		"maximum_queue_depth": _maximum_queue_depth,
		"discarded_stale_jobs": _discarded_stale_jobs,
		"oldest_queued_usec": (
			Time.get_ticks_usec() - _queue_started_usec
			if _queue_started_usec > 0
			else 0
		),
		"acoustic_open_area": _accumulated_open_area,
		"acoustic_aperture_open": _acoustic_aperture_open,
		"thermal_cuts": (
			_thermal_overlay.debug_state()
			if _thermal_overlay != null
			else {"active": false, "imprint_count": 0}
		),
	}


func _apply_damage_event(event: DamageEvent, notify_authority: bool) -> Dictionary:
	if not _initialized:
		initialize_volume()
	if not enabled or event == null or not event.is_valid():
		_rejected_event_count += 1
		return {"changed": false, "reason": &"disabled_or_invalid"}
	if notify_authority and not authoritative:
		_rejected_event_count += 1
		return {"changed": false, "reason": &"not_authoritative"}
	var started_usec := Time.get_ticks_usec()
	# Authoritative geometry is evaluated from the exact packet clients will replay. This prevents
	# sub-millimetre hit coordinates or unquantized directions from creating checksum drift.
	var applied_event := event
	if notify_authority:
		var canonical_packet := event.to_dict(true)
		canonical_packet["seed"] = DamageEvent.deterministic_seed(
			volume_id,
			event.sequence,
			event.source_id,
			event.seed
		)
		applied_event = DamageEvent.from_dict(canonical_packet)
	var local_position := to_local(applied_event.world_position)
	var inverse_basis := global_basis.inverse()
	var local_direction := inverse_basis * applied_event.direction
	var local_normal := inverse_basis * applied_event.normal
	var previous_revision := field.revision
	var result := field.apply_damage_event(
		local_position,
		local_direction,
		local_normal,
		applied_event,
		_profile
	)
	result["volume_id"] = volume_id
	result["bake_hash"] = bake_hash()
	result["from_revision"] = previous_revision
	if not bool(result.get("changed", false)):
		_record_event_timing(started_usec, false)
		return result
	var changed_chunks: Array[Vector3i] = result.get("changed_chunks", [])
	result["world_changed_bounds"] = _world_bounds_for_chunks(changed_chunks)
	if bool(result.get("geometry_changed", true)):
		for coordinate: Vector3i in changed_chunks:
			_edited_chunks[coordinate] = true
		var remesh_chunks: Array[Vector3i]
		if not _generated_surface_active:
			# A generated contour and an analytic BoxMesh do not share a topology description. The old
			# implementation moved already-emitted contour vertices onto the box boundary and then
			# collapsed the resulting slivers; deterministic artifact traces proved that transition
			# opened the mesh. Activate one global-lattice presentation for the finite volume instead.
			# Chunks build incrementally behind the intact base surface and swap atomically when ready.
			_generated_surface_active = true
			_full_surface_transition_pending = true
			remesh_chunks = _all_chunk_coordinates()
		else:
			remesh_chunks = _remesh_chunks_for_changed_samples(result, changed_chunks)
		result["remesh_chunks"] = remesh_chunks
		_queue_chunks(remesh_chunks)
		var newly_opened_area := _record_acoustic_aperture(
			local_position,
			local_normal,
			float(result.get("aperture_radius", 0.0))
		)
		result["opened_area_estimate"] = newly_opened_area
		_accumulated_open_area += newly_opened_area
		var was_open := _acoustic_aperture_open
		_acoustic_aperture_open = _accumulated_open_area >= _profile.acoustic_aperture_area
		if _acoustic_aperture_open and not was_open:
			acoustic_aperture_changed.emit(world_bounds(), field.revision)
	if bool(result.get("geometry_changed", true)):
		_record_thermal_cut(applied_event, local_position, local_direction, result)
	damage_committed.emit(applied_event, result)
	if notify_authority:
		var server := get_node_or_null("/root/Server")
		if server != null and server.has_method("on_destructible_volume_changed"):
			server.call("on_destructible_volume_changed", self, applied_event, result)
	_record_event_timing(started_usec, true)
	return result


func _record_thermal_cut(
	event: DamageEvent,
	local_position: Vector3,
	local_direction: Vector3,
	result: Dictionary
) -> void:
	if not ThermalCutOverlay3D.is_thermal_cut_event(event):
		return
	var response_radius := _profile.response_radius(event.radius, event.energy)
	var perforated := bool(result.get("perforated", false))
	var channel_radius := maxf(
		response_radius * (
			lerpf(1.0, _profile.channel_radius_scale, 0.55)
			if perforated
			else 0.92
		),
		field.voxel_size * 0.45
	)
	var channel_depth := maxf(
		float(result.get("penetration_depth", 0.0)),
		maxf(response_radius * _profile.entry_depth_scale, field.voxel_size)
	)
	_ensure_thermal_overlay().add_damage_event(
		event,
		local_position,
		local_direction,
		channel_radius,
		channel_depth
	)


func _restore_thermal_cut_checkpoint(value: Variant) -> void:
	if value is Array and not (value as Array).is_empty():
		_ensure_thermal_overlay().apply_checkpoint_state(value)
	elif _thermal_overlay != null:
		_thermal_overlay.apply_checkpoint_state([])


func _ensure_thermal_overlay() -> ThermalCutOverlay3D:
	if _thermal_overlay != null:
		return _thermal_overlay
	_thermal_overlay = ThermalCutOverlay3D.new()
	_thermal_overlay.name = "ThermalCutOverlay"
	add_child(_thermal_overlay)
	_thermal_overlay.configure(_generated_surface_material)
	return _thermal_overlay


func _remesh_chunks_for_changed_samples(
	result: Dictionary,
	changed_chunks: Array[Vector3i]
) -> Array[Vector3i]:
	if remesh_neighbor_ring <= 0:
		return changed_chunks.duplicate()
	if not bool(result.get("has_changed_sample_bounds", false)):
		return field.expanded_chunk_ring(changed_chunks, remesh_neighbor_ring)
	var changed_minimum: Vector3i = result.get("changed_sample_minimum", Vector3i.ZERO)
	var changed_maximum: Vector3i = result.get("changed_sample_maximum", Vector3i.ZERO)
	var candidates := field.expanded_chunk_ring(changed_chunks, remesh_neighbor_ring)
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


func _queue_chunks(coordinates: Array[Vector3i]) -> void:
	for coordinate: Vector3i in coordinates:
		_queue_chunk(coordinate)


func _queue_chunk(coordinate: Vector3i) -> void:
	if not field.brick_is_valid(coordinate) or _coordinate_has_active_job(coordinate):
		return
	var flat_index := coordinate.x + field.brick_counts.x * (
		coordinate.y + field.brick_counts.y * coordinate.z
	)
	if _dirty_chunk_flags[flat_index] != 0:
		return
	var queue_was_empty := _dirty_chunks.is_empty()
	_dirty_chunk_flags[flat_index] = 1
	_dirty_chunks.append(coordinate)
	if queue_was_empty:
		_queue_started_usec = Time.get_ticks_usec()
	_maximum_queue_depth = maxi(_maximum_queue_depth, _dirty_chunks.size())
	set_process(true)


func _schedule_chunk_jobs() -> void:
	var capacity := maxi(maximum_parallel_chunk_jobs, 1) - _active_chunk_jobs.size()
	while capacity > 0 and not _dirty_chunks.is_empty():
		# Rebuild order carries no topology semantics. Pop from the tail so a broad impact does not
		# repeatedly shift the entire pending array as pop_front() did.
		var coordinate: Vector3i = _dirty_chunks.pop_back() as Vector3i
		var flat_index := coordinate.x + field.brick_counts.x * (
			coordinate.y + field.brick_counts.y * coordinate.z
		)
		_dirty_chunk_flags[flat_index] = 0
		if _coordinate_has_active_job(coordinate):
			continue
		var job: SdfChunkBuildJob = (
			_chunk_job_pool.pop_back()
			if not _chunk_job_pool.is_empty()
			else SdfChunkBuildJob.new()
		)
		job.capture(field, coordinate)
		job.task_id = WorkerThreadPool.add_task(
			job.execute,
			false,
			"Destruction chunk"
		)
		_active_chunk_jobs.append(job)
		capacity -= 1


func _coordinate_has_active_job(coordinate: Vector3i) -> bool:
	# The exported limit caps this at eight entries, so a linear scan is cheaper than allocating and
	# maintaining a second hash entry for every short-lived worker job.
	for job: SdfChunkBuildJob in _active_chunk_jobs:
		if job != null and job.coordinate == coordinate:
			return true
	return false


func _recycle_chunk_job(job: SdfChunkBuildJob) -> void:
	if job == null:
		return
	job.task_id = -1
	_chunk_job_pool.append(job)


func _build_base_chunks() -> void:
	for z: int in range(field.brick_counts.z):
		for y: int in range(field.brick_counts.y):
			for x: int in range(field.brick_counts.x):
				var coordinate := Vector3i(x, y, z)
				var minimum := field.brick_origin(coordinate)
				var maximum := Vector3(
					minf(minimum.x + field.brick_extent, field.half_extents.x),
					minf(minimum.y + field.brick_extent, field.half_extents.y),
					minf(minimum.z + field.brick_extent, field.half_extents.z)
				)
				var chunk_size := maximum - minimum
				if chunk_size.x <= 0.0 or chunk_size.y <= 0.0 or chunk_size.z <= 0.0:
					continue
				var center := (minimum + maximum) * 0.5
				var visual := MeshInstance3D.new()
				visual.name = "BaseVisual_%d_%d_%d" % [x, y, z]
				var mesh := BoxMesh.new()
				mesh.size = chunk_size
				visual.mesh = mesh
				visual.position = center
				visual.cast_shadow = cast_shadow
				visual.material_override = _surface_material
				add_child(visual)
				_base_visuals[coordinate] = visual
				if not create_collision:
					continue
				var body := DestructibleCollisionBody3D.new().configure(
					self,
					coordinate,
					physical_surface
				)
				body.name = "BaseBody_%d_%d_%d" % [x, y, z]
				var collision := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = chunk_size
				collision.shape = shape
				collision.position = center
				body.add_child(collision)
				add_child(body)
				_base_bodies[coordinate] = body
				_base_shapes[coordinate] = collision


func _register_generated_surface_pipeline() -> void:
	if _generated_surface_pipeline_registered or _generated_surface_material == null:
		return
	# Match the real generated surface's vertex layout exactly. A plain BoxMesh would not advertise
	# ARRAY_COLOR, leaving the destructive surface pipeline cold despite using the same material.
	var warmup_result := {
		"vertices": PackedVector3Array([
			Vector3(-0.01, -0.01, 0.0),
			Vector3(0.01, -0.01, 0.0),
			Vector3(0.0, 0.01, 0.0),
		]),
		"normals": PackedVector3Array([
			Vector3.BACK,
			Vector3.BACK,
			Vector3.BACK,
		]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		"indices": PackedInt32Array([0, 1, 2]),
	}
	var mesh := SdfDualContouringMesher.create_array_mesh(warmup_result)
	if mesh == null:
		return
	mesh.surface_set_material(0, _generated_surface_material)
	var warmup := MeshInstance3D.new()
	warmup.name = RUNTIME_WARMUP_NAME
	warmup.mesh = mesh
	warmup.material_override = _generated_surface_material
	warmup.cast_shadow = cast_shadow
	# Godot 4.4+ registers surface pipelines when an instance enters the tree even when invisible.
	# Keeping this hidden also makes it safe with Compatibility and dedicated/headless servers; it
	# has no draw calls, processing, collision, or per-frame allocations.
	warmup.visible = false
	add_child(warmup)
	var thermal_warmup := MeshInstance3D.new()
	thermal_warmup.name = RUNTIME_THERMAL_WARMUP_NAME
	thermal_warmup.mesh = mesh
	thermal_warmup.material_override = ThermalCutOverlay3D.create_shader_material()
	thermal_warmup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	thermal_warmup.visible = false
	add_child(thermal_warmup)
	_generated_surface_pipeline_registered = true


func _rebuild_chunk(
	coordinate: Vector3i,
	prepared_result: Dictionary = {},
	worker_elapsed_usec := 0
) -> void:
	if not field.brick_is_valid(coordinate):
		return
	var started_usec := Time.get_ticks_usec()
	var base_visual := _base_visuals.get(coordinate) as MeshInstance3D
	var base_shape := _base_shapes.get(coordinate) as CollisionShape3D
	var result := (
		prepared_result
		if not prepared_result.is_empty()
		else SdfDualContouringMesher.build_chunk(field, coordinate)
	)
	var retains_base_surface := _result_matches_untouched_base(result)
	if base_visual != null:
		base_visual.visible = (
			true
			if _full_surface_transition_pending
			else retains_base_surface
		)
	if base_shape != null:
		base_shape.set_deferred(
			"disabled",
			false if _full_surface_transition_pending else not retains_base_surface
		)
	if retains_base_surface or bool(result.get("empty", true)):
		_remove_generated_chunk(coordinate)
	else:
		result["colors"] = _surface_colors_for_result(result)
		var visual := _generated_visuals.get(coordinate) as MeshInstance3D
		var reusable_mesh := visual.mesh as ArrayMesh if visual != null else null
		var mesh := SdfDualContouringMesher.create_array_mesh(result, reusable_mesh)
		if mesh != null:
			if visual == null:
				visual = MeshInstance3D.new()
				visual.name = "GeneratedVisual_%d_%d_%d" % [coordinate.x, coordinate.y, coordinate.z]
				visual.cast_shadow = cast_shadow
				visual.material_override = _generated_surface_material
				add_child(visual)
				_generated_visuals[coordinate] = visual
			visual.mesh = mesh
			visual.visible = not _full_surface_transition_pending
		if create_collision:
			var reusable_faces: PackedVector3Array = _generated_collision_faces.get(
				coordinate,
				PackedVector3Array()
			)
			var faces := SdfDualContouringMesher.create_collision_faces(result, reusable_faces)
			if not faces.is_empty():
				var body := _generated_bodies.get(coordinate) as DestructibleCollisionBody3D
				var collision := _generated_shapes.get(coordinate) as CollisionShape3D
				if body != null and body.damage_call_is_active():
					# A synchronous fragmentation barrier can rebuild the exact body currently
					# forwarding apply_damage_event(). Godot forbids mutating/freeing that call-locked
					# object, so retain in-place updates normally but retire this exceptional body.
					_remove_generated_collision(coordinate)
					body = null
					collision = null
				if body == null or collision == null:
					body = DestructibleCollisionBody3D.new().configure(
						self,
						coordinate,
						physical_surface
					)
					body.name = "GeneratedBody_%d_%d_%d" % [coordinate.x, coordinate.y, coordinate.z]
					collision = CollisionShape3D.new()
					body.add_child(collision)
					add_child(body)
					_generated_bodies[coordinate] = body
					_generated_shapes[coordinate] = collision
				_generated_collision_faces[coordinate] = faces
				var shape := collision.shape as ConcavePolygonShape3D
				if shape == null:
					shape = ConcavePolygonShape3D.new()
				shape.set_faces(faces)
				collision.shape = shape
				collision.set_deferred("disabled", _full_surface_transition_pending)
			else:
				_remove_generated_collision(coordinate)
	_rebuild_count += 1
	_last_rebuilt_revision = field.revision
	var elapsed_usec := Time.get_ticks_usec() - started_usec + worker_elapsed_usec
	_rebuild_total_usec += elapsed_usec
	_rebuild_max_usec = maxi(_rebuild_max_usec, elapsed_usec)


func _result_matches_untouched_base(result: Dictionary) -> bool:
	if _generated_surface_active:
		return false
	if bool(result.get("empty", true)):
		return false
	if not result.has("vertices"):
		return false
	var vertices: PackedVector3Array = result["vertices"]
	if vertices.is_empty():
		return false
	# The seam-safety ring still gets evaluated because a neighboring cut can alter its owned faces.
	# Keep the cheap original box only when every extracted vertex remains on the immutable analytic
	# shell. This local equivalence test avoids replacing a broad square of unaffected presentation or
	# collision without guessing which neighbors are safe to skip.
	var surface_tolerance := maxf(field.voxel_size * 0.01, 0.00001)
	for vertex: Vector3 in vertices:
		if absf(field.base_distance(vertex)) > surface_tolerance:
			return false
	return true


func _commit_generated_surface_transition() -> void:
	if not _full_surface_transition_pending:
		return
	# Every finite-volume chunk has now been evaluated from the same global sample lattice. Commit
	# render and collision together so no frame observes a generated/BoxMesh seam or double collider.
	for visual: MeshInstance3D in _base_visuals.values():
		if is_instance_valid(visual):
			visual.visible = false
	for shape: CollisionShape3D in _base_shapes.values():
		if is_instance_valid(shape):
			shape.set_deferred("disabled", true)
	for visual: MeshInstance3D in _generated_visuals.values():
		if is_instance_valid(visual):
			visual.visible = true
	for shape: CollisionShape3D in _generated_shapes.values():
		if is_instance_valid(shape):
			shape.set_deferred("disabled", false)
	_full_surface_transition_pending = false


func _record_event_timing(started_usec: int, committed: bool) -> void:
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	_evaluated_event_count += 1
	if committed:
		_committed_event_count += 1
	else:
		_rejected_event_count += 1
	_event_apply_total_usec += elapsed_usec
	_event_apply_max_usec = maxi(_event_apply_max_usec, elapsed_usec)


func _remove_generated_chunk(coordinate: Vector3i) -> void:
	var visual := _generated_visuals.get(coordinate) as MeshInstance3D
	if visual != null:
		visual.free()
	_generated_visuals.erase(coordinate)
	_remove_generated_collision(coordinate)


func _remove_generated_collision(coordinate: Vector3i) -> void:
	var body := _generated_bodies.get(coordinate) as DestructibleCollisionBody3D
	# A projectile reaches this volume by calling apply_damage_event() on the collision body it hit.
	# Fragment detachment uses a synchronous topology barrier, so that call can rebuild this exact
	# chunk before the adapter method has returned. Object.free() is illegal while Godot has the body
	# call-locked. Retire ownership immediately, make its physics removal explicit at the safe sync
	# point, and let SceneTree destroy it after the current call stack unwinds.
	_generated_bodies.erase(coordinate)
	_generated_shapes.erase(coordinate)
	_generated_collision_faces.erase(coordinate)
	if body != null:
		if not body.is_queued_for_deletion():
			body.set_deferred("collision_layer", 0)
			body.set_deferred("collision_mask", 0)
			for child_index: int in range(body.get_child_count()):
				var collision := body.get_child(child_index) as CollisionShape3D
				if collision != null:
					collision.set_deferred("disabled", true)
			body.queue_free()


func _edited_chunk_array() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for coordinate: Vector3i in _edited_chunks.keys():
		result.append(coordinate)
	result.sort_custom(_vector3i_less)
	return result


func _all_chunk_coordinates() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	result.resize(field.brick_counts.x * field.brick_counts.y * field.brick_counts.z)
	var write_index := 0
	for z: int in range(field.brick_counts.z):
		for y: int in range(field.brick_counts.y):
			for x: int in range(field.brick_counts.x):
				result[write_index] = Vector3i(x, y, z)
				write_index += 1
	return result


func _acoustic_aperture_cell_array() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for coordinate: Vector3i in _acoustic_aperture_cells.keys():
		result.append(coordinate)
	result.sort_custom(_vector3i_less)
	return result


func _record_acoustic_aperture(
	local_position: Vector3,
	local_normal: Vector3,
	radius: float
) -> float:
	if radius <= 0.0:
		return 0.0
	var absolute_normal := local_normal.abs()
	var axis := 0
	var first_coordinate := local_position.y
	var second_coordinate := local_position.z
	if absolute_normal.y >= absolute_normal.x and absolute_normal.y >= absolute_normal.z:
		axis = 1
		first_coordinate = local_position.x
		second_coordinate = local_position.z
	elif absolute_normal.z >= absolute_normal.x:
		axis = 2
		first_coordinate = local_position.x
		second_coordinate = local_position.y
	var first_center := roundi(first_coordinate / field.voxel_size)
	var second_center := roundi(second_coordinate / field.voxel_size)
	var cell_radius := ceili(radius / field.voxel_size)
	var radius_squared := radius * radius
	var added_cells := 0
	for second_offset: int in range(-cell_radius, cell_radius + 1):
		for first_offset: int in range(-cell_radius, cell_radius + 1):
			var first_delta := (
				float(first_center + first_offset) * field.voxel_size - first_coordinate
			)
			var second_delta := (
				float(second_center + second_offset) * field.voxel_size - second_coordinate
			)
			if first_delta * first_delta + second_delta * second_delta > radius_squared:
				continue
			var key := Vector3i(axis, first_center + first_offset, second_center + second_offset)
			if _acoustic_aperture_cells.has(key):
				continue
			_acoustic_aperture_cells[key] = true
			added_cells += 1
	return float(added_cells) * field.voxel_size * field.voxel_size


func _world_bounds_for_chunks(coordinates: Array[Vector3i]) -> AABB:
	if coordinates.is_empty():
		return AABB(global_position, Vector3.ZERO)
	var local_minimum := Vector3(INF, INF, INF)
	var local_maximum := Vector3(-INF, -INF, -INF)
	for coordinate: Vector3i in coordinates:
		var minimum := field.brick_origin(coordinate)
		var maximum := Vector3(
			minf(minimum.x + field.brick_extent, field.half_extents.x),
			minf(minimum.y + field.brick_extent, field.half_extents.y),
			minf(minimum.z + field.brick_extent, field.half_extents.z)
		)
		local_minimum = Vector3(
			minf(local_minimum.x, minimum.x),
			minf(local_minimum.y, minimum.y),
			minf(local_minimum.z, minimum.z)
		)
		local_maximum = Vector3(
			maxf(local_maximum.x, maximum.x),
			maxf(local_maximum.y, maximum.y),
			maxf(local_maximum.z, maximum.z)
		)
	return global_transform * AABB(local_minimum, local_maximum - local_minimum)


static func _create_surface_material(profile: DestructionTextureDefinition) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = profile.exterior_color
	material.roughness = profile.roughness
	material.metallic = profile.metallic
	return material


static func _create_generated_surface_material(
	profile: DestructionTextureDefinition
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	# Use the exact same albedo as the untouched BoxMesh. Vertex color then only modulates exposed
	# interior faces, which avoids running the exterior color through a second color-space path.
	material.albedo_color = profile.exterior_color
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = false
	material.roughness = profile.roughness
	material.metallic = profile.metallic
	return material


func _surface_colors_for_result(result: Dictionary) -> PackedColorArray:
	SdfDualContouringMesher.split_box_reference_surface_classes(result)
	var vertices := result["vertices"] as PackedVector3Array
	var surface_classes := result.get("surface_classes", PackedByteArray()) as PackedByteArray
	if vertices.is_empty() or surface_classes.size() != vertices.size():
		return PackedColorArray()
	var exterior := _profile.exterior_color
	var interior_modulation := Color(
		_profile.interior_color.r / maxf(exterior.r, 0.000001),
		_profile.interior_color.g / maxf(exterior.g, 0.000001),
		_profile.interior_color.b / maxf(exterior.b, 0.000001),
		_profile.interior_color.a / maxf(exterior.a, 0.000001)
	)
	var deep_interior_modulation := Color(
		_profile.deep_interior_color.r / maxf(exterior.r, 0.000001),
		_profile.deep_interior_color.g / maxf(exterior.g, 0.000001),
		_profile.deep_interior_color.b / maxf(exterior.b, 0.000001),
		_profile.deep_interior_color.a / maxf(exterior.a, 0.000001)
	)
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for index: int in range(vertices.size()):
		if surface_classes[index] == 0:
			colors[index] = Color.WHITE
		else:
			var fracture_depth := maxf(-field.base_distance(vertices[index]), field.voxel_size * 0.5)
			var depth_weight := (
				clampf(fracture_depth / _profile.interior_color_depth, 0.0, 1.0)
				if _profile.interior_color_depth > 0.000001
				else 0.0
			)
			colors[index] = interior_modulation.lerp(deep_interior_modulation, depth_weight)
	result["colors"] = colors
	return colors


static func _vector3i_less(left: Vector3i, right: Vector3i) -> bool:
	if left.z != right.z:
		return left.z < right.z
	if left.y != right.y:
		return left.y < right.y
	return left.x < right.x


static func _hash_step(state: int, value: int) -> int:
	return ((state ^ value) * 16777619) & 0xffffffff
