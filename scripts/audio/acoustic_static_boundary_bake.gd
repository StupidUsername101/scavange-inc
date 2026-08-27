class_name AcousticStaticBoundaryBake
extends RefCounted

## Sparse broadphase over static structural box shapes. It is built once with the probe graph and
## lets a direct source/listener segment accumulate every distinct wall crossing without repeated
## physics queries. Unsupported and moving geometry deliberately remains on the service's existing
## first-hit fallback.

const SCHEMA_VERSION := 2
const BUCKET_SIZE := 8.0
const MAX_BUCKETS_PER_SHAPE := 4096
const MAX_SHAPES := 200000
const MAX_MATERIALS := 1024
const MERGE_DISTANCE_METERS := 0.08
const MAX_TRANSMISSION_CROSSINGS := 24
const SEGMENT_EPSILON := 0.000001
const SPEED_OF_SOUND_METERS_PER_SECOND := 343.0
const EARLY_REFLECTION_SEARCH_DISTANCE := 32.0
const MAX_EARLY_REFLECTION_CANDIDATES := 384
const MAX_EARLY_REFLECTIONS := 2
const MIN_REFLECTOR_FACE_AREA := 2.0
const MIN_EARLY_REFLECTION_DELAY_SECONDS := 0.0015
const MAX_EARLY_REFLECTION_DELAY_SECONDS := 0.18
const EARLY_REFLECTION_LEVEL_SCALE := 0.42

var _world_transforms: Array[Transform3D] = []
var _inverse_transforms: Array[Transform3D] = []
var _half_extents := PackedVector3Array()
var _material_indices := PackedInt32Array()
var _reflection_absorption := PackedVector3Array()
var _reflection_scattering := PackedFloat32Array()
var _materials: Array[AcousticPathModifier] = []
var _material_index_by_key: Dictionary[String, int] = {}
var _shape_indices_by_bucket: Dictionary[Vector3i, PackedInt32Array] = {}
var _large_shape_indices := PackedInt32Array()
var _candidate_stamps := PackedInt32Array()
var _candidate_scratch: Array[int] = []
var _visibility_candidate_scratch: Array[int] = []
var _interval_scratch: Array[Vector3] = []
var _query_stamp := 0
var _unsupported_shape_count := 0


func clear() -> void:
	_world_transforms.clear()
	_inverse_transforms.clear()
	_half_extents.clear()
	_material_indices.clear()
	_reflection_absorption.clear()
	_reflection_scattering.clear()
	_materials.clear()
	_material_index_by_key.clear()
	_shape_indices_by_bucket.clear()
	_large_shape_indices.clear()
	_candidate_stamps.clear()
	_candidate_scratch.clear()
	_visibility_candidate_scratch.clear()
	_interval_scratch.clear()
	_query_stamp = 0
	_unsupported_shape_count = 0


func note_unsupported_shape() -> void:
	_unsupported_shape_count += 1


func add_box(
	world_transform: Transform3D,
	size: Vector3,
	modifier: AcousticPathModifier,
	reflection_material: AcousticMaterial = null
) -> bool:
	if (
		_world_transforms.size() >= MAX_SHAPES
		or not world_transform.is_finite()
		or not size.is_finite()
		or size.x <= 0.0
		or size.y <= 0.0
		or size.z <= 0.0
	):
		return false
	var safe_modifier := (
		modifier.sanitized_copy()
		if modifier != null
		else AcousticPathModifier.identity()
	)
	var material_index := _material_index(safe_modifier)
	if material_index < 0:
		return false
	var shape_index := _world_transforms.size()
	var half_extents := size.abs() * 0.5
	_world_transforms.append(world_transform)
	_inverse_transforms.append(world_transform.affine_inverse())
	_half_extents.append(half_extents)
	_material_indices.append(material_index)
	_reflection_absorption.append(
		reflection_material.sanitized_absorption()
		if reflection_material != null
		else Vector3(0.12, 0.22, 0.38)
	)
	_reflection_scattering.append(
		reflection_material.sanitized_scattering()
		if reflection_material != null
		else 0.08
	)
	_candidate_stamps.append(0)
	_index_shape(shape_index, world_transform, half_extents)
	return true


## Samples a bounded first-order image-source approximation from the baked static boxes. The
## geometry and material coefficients are baked; callers can cache this result for static sources.
## Only broad wall-like faces participate, which prevents a forest of tiny props from becoming a
## bank of metallic delay taps.
func sample_early_reflections(
	listener_position: Vector3,
	source_position: Vector3,
	direct_path_length: float,
	max_reflections := MAX_EARLY_REFLECTIONS
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if (
		_world_transforms.is_empty()
		or not listener_position.is_finite()
		or not source_position.is_finite()
		or direct_path_length <= SEGMENT_EPSILON
		or max_reflections <= 0
	):
		return result
	_advance_query_stamp()
	_candidate_scratch.clear()
	for shape_index: int in _large_shape_indices:
		_append_candidate(shape_index, _candidate_scratch)
	_collect_region_bucket_candidates(
		listener_position,
		source_position,
		EARLY_REFLECTION_SEARCH_DISTANCE,
		_candidate_scratch
	)
	var candidate_reflections: Array[Dictionary] = []
	var sampled_shape_count := mini(
		_candidate_scratch.size(),
		MAX_EARLY_REFLECTION_CANDIDATES
	)
	for candidate_index: int in range(sampled_shape_count):
		var shape_index := _candidate_scratch[candidate_index]
		_append_box_reflections(
			shape_index,
			listener_position,
			source_position,
			direct_path_length,
			candidate_reflections
		)
	candidate_reflections.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var gain_delta := float(left.get("gain", 0.0)) - float(right.get("gain", 0.0))
			if absf(gain_delta) > 0.00001:
				return gain_delta > 0.0
			return int(left.get("reflection_id", 0)) < int(right.get("reflection_id", 0))
	)
	var limit := mini(max_reflections, MAX_EARLY_REFLECTIONS)
	for reflection: Dictionary in candidate_reflections:
		if result.size() >= limit:
			break
		var delay := float(reflection.get("extra_delay_seconds", 0.0))
		var too_similar := false
		for accepted: Dictionary in result:
			if absf(delay - float(accepted.get("extra_delay_seconds", 0.0))) < 0.001:
				too_similar = true
				break
		if not too_similar:
			result.append(reflection)
	return result


func sample_transmission(from: Vector3, to: Vector3) -> Dictionary:
	if (
		_world_transforms.is_empty()
		or not from.is_finite()
		or not to.is_finite()
		or from.distance_squared_to(to) <= SEGMENT_EPSILON
	):
		return {"crossing_count": 0}
	_advance_query_stamp()
	_candidate_scratch.clear()
	_interval_scratch.clear()
	for shape_index: int in _large_shape_indices:
		_append_candidate(shape_index, _candidate_scratch)
	_collect_segment_bucket_candidates(from, to, _candidate_scratch)
	if _candidate_scratch.is_empty():
		return {"crossing_count": 0}
	for shape_index: int in _candidate_scratch:
		var interval := _box_segment_interval(shape_index, from, to)
		if interval.x > interval.y:
			continue
		_interval_scratch.append(Vector3(
			interval.x,
			interval.y,
			float(_material_indices[shape_index])
		))
	if _interval_scratch.is_empty():
		return {"crossing_count": 0}
	_interval_scratch.sort_custom(
		func(left: Vector3, right: Vector3) -> bool:
			return left.x < right.x
	)
	var segment_length := from.distance_to(to)
	var first_entry_distance := _interval_scratch[0].x * segment_length
	var merge_epsilon := MERGE_DISTANCE_METERS / maxf(segment_length, 0.001)
	var modifier := AcousticPathModifier.identity()
	var crossing_count := 0
	var run_exit := -INF
	var run_material := -1
	for interval: Vector3 in _interval_scratch:
		var material_index := int(interval.z)
		if interval.x <= run_exit + merge_epsilon:
			run_exit = maxf(run_exit, interval.y)
			run_material = _more_restrictive_material(
				run_material,
				material_index
			)
			continue
		if run_material >= 0:
			_accumulate_material(modifier, run_material)
			crossing_count += 1
			if crossing_count >= MAX_TRANSMISSION_CROSSINGS:
				break
		run_exit = interval.y
		run_material = material_index
	if crossing_count < MAX_TRANSMISSION_CROSSINGS and run_material >= 0:
		_accumulate_material(modifier, run_material)
		crossing_count += 1
	modifier.volume_db = clampf(
		modifier.volume_db,
		AcousticPathModifier.MIN_VOLUME_DB,
		0.0
	)
	modifier.extra_delay_seconds = minf(
		modifier.extra_delay_seconds,
		AcousticPathModifier.MAX_EXTRA_DELAY_SECONDS
	)
	return {
		"crossing_count": crossing_count,
		"candidate_shape_count": _candidate_scratch.size(),
		"first_entry_distance": first_entry_distance,
		"modifier": modifier,
	}


func export_bake_data() -> Dictionary:
	var boxes: Array[Dictionary] = []
	boxes.resize(_world_transforms.size())
	for shape_index: int in range(_world_transforms.size()):
		boxes[shape_index] = {
			"transform": _world_transforms[shape_index],
			"half_extents": _half_extents[shape_index],
			"material_index": _material_indices[shape_index],
			"reflection_absorption": _reflection_absorption[shape_index],
			"reflection_scattering": _reflection_scattering[shape_index],
		}
	var materials: Array[Dictionary] = []
	materials.resize(_materials.size())
	for material_index: int in range(_materials.size()):
		materials[material_index] = _modifier_to_data(_materials[material_index])
	return {
		"schema_version": SCHEMA_VERSION,
		"boxes": boxes,
		"materials": materials,
		"unsupported_shape_count": _unsupported_shape_count,
	}


func import_bake_data(data: Dictionary) -> bool:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	var raw_boxes: Variant = data.get("boxes", null)
	var raw_materials: Variant = data.get("materials", null)
	if not raw_boxes is Array or not raw_materials is Array:
		return false
	var boxes := raw_boxes as Array
	var materials := raw_materials as Array
	if boxes.size() > MAX_SHAPES or materials.size() > MAX_MATERIALS:
		return false
	clear()
	for raw_material: Variant in materials:
		if not raw_material is Dictionary:
			clear()
			return false
		var modifier := _modifier_from_data(raw_material as Dictionary)
		if modifier == null:
			clear()
			return false
		_material_index(modifier)
	for raw_box: Variant in boxes:
		if not raw_box is Dictionary:
			clear()
			return false
		var box := raw_box as Dictionary
		var world_transform: Variant = box.get("transform", null)
		var half_extents: Variant = box.get("half_extents", null)
		var material_index := int(box.get("material_index", -1))
		var reflection_absorption := SafeVariant.vector3_strict_or(
			box.get("reflection_absorption"),
			Vector3(INF, INF, INF)
		)
		var reflection_scattering := SafeVariant.finite_float_or(
			box.get("reflection_scattering"),
			INF
		)
		if (
			not world_transform is Transform3D
			or not half_extents is Vector3
			or material_index < 0
			or material_index >= _materials.size()
			or not reflection_absorption.is_finite()
			or not is_finite(reflection_scattering)
		):
			clear()
			return false
		var reflection_material := AcousticMaterial.new()
		reflection_material.absorption = reflection_absorption
		reflection_material.scattering = reflection_scattering
		if not add_box(
			world_transform as Transform3D,
			(half_extents as Vector3) * 2.0,
			_materials[material_index],
			reflection_material
		):
			clear()
			return false
	_unsupported_shape_count = maxi(
		int(data.get("unsupported_shape_count", 0)),
		0
	)
	return true


func debug_state() -> Dictionary:
	return {
		"static_boundary_box_count": _world_transforms.size(),
		"static_boundary_material_count": _materials.size(),
		"static_boundary_bucket_count": _shape_indices_by_bucket.size(),
		"static_boundary_large_shape_count": _large_shape_indices.size(),
		"static_boundary_unsupported_shape_count": _unsupported_shape_count,
		"static_boundary_reflector_count": _reflection_absorption.size(),
	}


func _append_box_reflections(
	shape_index: int,
	listener_position: Vector3,
	source_position: Vector3,
	direct_path_length: float,
	result: Array[Dictionary]
) -> void:
	var inverse := _inverse_transforms[shape_index]
	var local_listener := inverse * listener_position
	var local_source := inverse * source_position
	var extents := _half_extents[shape_index]
	var absorption := _reflection_absorption[shape_index]
	var scattering := _reflection_scattering[shape_index]
	var reflected_energy := Vector3.ONE - absorption
	var specular_energy := reflected_energy * (1.0 - scattering)
	for axis: int in range(3):
		var other_a := (axis + 1) % 3
		var other_b := (axis + 2) % 3
		var face_area := 4.0 * extents[other_a] * extents[other_b]
		if face_area < MIN_REFLECTOR_FACE_AREA:
			continue
		for sign_value: float in [-1.0, 1.0]:
			var plane_value := sign_value * extents[axis]
			# Both endpoints must see the same exposed face; otherwise this is transmission, not a
			# first-order reflection.
			if (
				sign_value * local_listener[axis] < extents[axis] - 0.002
				or sign_value * local_source[axis] < extents[axis] - 0.002
			):
				continue
			var image_source := local_source
			image_source[axis] = 2.0 * plane_value - local_source[axis]
			var image_direction := image_source - local_listener
			if absf(image_direction[axis]) <= SEGMENT_EPSILON:
				continue
			var intersection_t := (
				plane_value - local_listener[axis]
			) / image_direction[axis]
			if intersection_t <= 0.0001 or intersection_t >= 0.9999:
				continue
			var local_hit := local_listener + image_direction * intersection_t
			if (
				absf(local_hit[other_a]) > extents[other_a] - 0.001
				or absf(local_hit[other_b]) > extents[other_b] - 0.001
			):
				continue
			var world_hit := _world_transforms[shape_index] * local_hit
			var reflected_path_length := (
				source_position.distance_to(world_hit)
				+ world_hit.distance_to(listener_position)
			)
			var delay_seconds := maxf(
				reflected_path_length - direct_path_length,
				0.0
			) / SPEED_OF_SOUND_METERS_PER_SECOND
			if (
				delay_seconds < MIN_EARLY_REFLECTION_DELAY_SECONDS
				or delay_seconds > MAX_EARLY_REFLECTION_DELAY_SECONDS
				or not _segment_unobstructed_ignoring(
					source_position,
					world_hit,
					shape_index
				)
				or not _segment_unobstructed_ignoring(
					listener_position,
					world_hit,
					shape_index
				)
			):
				continue
			var world_normal := (
				_world_transforms[shape_index].basis[axis].normalized()
				* sign_value
			)
			var source_incidence := absf(
				(source_position - world_hit).normalized().dot(world_normal)
			)
			var listener_incidence := absf(
				(listener_position - world_hit).normalized().dot(world_normal)
			)
			var incidence := sqrt(source_incidence * listener_incidence)
			var distance_ratio := clampf(
				direct_path_length / maxf(reflected_path_length, 0.001),
				0.0,
				1.0
			)
			var band_gain := Vector3(
				sqrt(maxf(specular_energy.x, 0.0)),
				sqrt(maxf(specular_energy.y, 0.0)),
				sqrt(maxf(specular_energy.z, 0.0))
			) * distance_ratio * lerpf(0.25, 1.0, incidence) * EARLY_REFLECTION_LEVEL_SCALE
			var gain := sqrt(
				(band_gain.x * band_gain.x
				+ band_gain.y * band_gain.y
				+ band_gain.z * band_gain.z) / 3.0
			)
			if gain <= 0.01:
				continue
			var face_index := axis * 2 + (1 if sign_value > 0.0 else 0)
			result.append({
				"reflection_id": shape_index * 6 + face_index,
				"apparent_position": world_hit,
				"extra_delay_seconds": delay_seconds,
				"gain": minf(gain, 0.70),
				"band_gain": band_gain,
			})


func _segment_unobstructed_ignoring(
	from: Vector3,
	to: Vector3,
	ignored_shape_index: int
) -> bool:
	_advance_query_stamp()
	_visibility_candidate_scratch.clear()
	for shape_index: int in _large_shape_indices:
		_append_candidate(shape_index, _visibility_candidate_scratch)
	_collect_segment_bucket_candidates(from, to, _visibility_candidate_scratch)
	for shape_index: int in _visibility_candidate_scratch:
		if shape_index == ignored_shape_index:
			continue
		var interval := _box_segment_interval(shape_index, from, to)
		if interval.x <= interval.y and interval.y > 0.001 and interval.x < 0.999:
			return false
	return true


func _collect_region_bucket_candidates(
	from: Vector3,
	to: Vector3,
	expansion: float,
	result: Array[int]
) -> void:
	var minimum := from.min(to) - Vector3.ONE * expansion
	var maximum := from.max(to) + Vector3.ONE * expansion
	var minimum_cell := _bucket_cell(minimum)
	var maximum_cell := _bucket_cell(maximum)
	for x: int in range(minimum_cell.x, maximum_cell.x + 1):
		for y: int in range(minimum_cell.y, maximum_cell.y + 1):
			for z: int in range(minimum_cell.z, maximum_cell.z + 1):
				var bucket: PackedInt32Array = _shape_indices_by_bucket.get(
					Vector3i(x, y, z),
					PackedInt32Array()
				)
				for shape_index: int in bucket:
					_append_candidate(shape_index, result)


func _index_shape(
	shape_index: int,
	world_transform: Transform3D,
	half_extents: Vector3
) -> void:
	var basis := world_transform.basis
	var world_extents := (
		basis.x.abs() * half_extents.x
		+ basis.y.abs() * half_extents.y
		+ basis.z.abs() * half_extents.z
	)
	var minimum_cell := _bucket_cell(world_transform.origin - world_extents)
	var maximum_cell := _bucket_cell(world_transform.origin + world_extents)
	var bucket_count := (
		(maximum_cell.x - minimum_cell.x + 1)
		* (maximum_cell.y - minimum_cell.y + 1)
		* (maximum_cell.z - minimum_cell.z + 1)
	)
	if bucket_count > MAX_BUCKETS_PER_SHAPE:
		_large_shape_indices.append(shape_index)
		return
	for x: int in range(minimum_cell.x, maximum_cell.x + 1):
		for y: int in range(minimum_cell.y, maximum_cell.y + 1):
			for z: int in range(minimum_cell.z, maximum_cell.z + 1):
				var cell := Vector3i(x, y, z)
				var indices: PackedInt32Array = _shape_indices_by_bucket.get(
					cell,
					PackedInt32Array()
				)
				indices.append(shape_index)
				_shape_indices_by_bucket[cell] = indices


func _collect_segment_bucket_candidates(
	from: Vector3,
	to: Vector3,
	result: Array[int]
) -> void:
	var current := _bucket_cell(from)
	var destination := _bucket_cell(to)
	var direction := to - from
	var step := Vector3i(
		1 if direction.x > 0.0 else -1 if direction.x < 0.0 else 0,
		1 if direction.y > 0.0 else -1 if direction.y < 0.0 else 0,
		1 if direction.z > 0.0 else -1 if direction.z < 0.0 else 0
	)
	var t_delta := Vector3(
		BUCKET_SIZE / absf(direction.x) if step.x != 0 else INF,
		BUCKET_SIZE / absf(direction.y) if step.y != 0 else INF,
		BUCKET_SIZE / absf(direction.z) if step.z != 0 else INF
	)
	var next_boundary := Vector3(
		(float(current.x + (1 if step.x > 0 else 0))) * BUCKET_SIZE,
		(float(current.y + (1 if step.y > 0 else 0))) * BUCKET_SIZE,
		(float(current.z + (1 if step.z > 0 else 0))) * BUCKET_SIZE
	)
	var t_max := Vector3(
		(next_boundary.x - from.x) / direction.x if step.x != 0 else INF,
		(next_boundary.y - from.y) / direction.y if step.y != 0 else INF,
		(next_boundary.z - from.z) / direction.z if step.z != 0 else INF
	)
	var maximum_steps := (
		absi(destination.x - current.x)
		+ absi(destination.y - current.y)
		+ absi(destination.z - current.z)
		+ 4
	)
	for _step_index: int in range(maximum_steps):
		var bucket: PackedInt32Array = _shape_indices_by_bucket.get(
			current,
			PackedInt32Array()
		)
		for shape_index: int in bucket:
			_append_candidate(shape_index, result)
		if current == destination:
			return
		if t_max.x <= t_max.y and t_max.x <= t_max.z:
			current.x += step.x
			t_max.x += t_delta.x
		elif t_max.y <= t_max.z:
			current.y += step.y
			t_max.y += t_delta.y
		else:
			current.z += step.z
			t_max.z += t_delta.z


func _append_candidate(shape_index: int, result: Array[int]) -> void:
	if shape_index < 0 or shape_index >= _candidate_stamps.size():
		return
	if _candidate_stamps[shape_index] == _query_stamp:
		return
	_candidate_stamps[shape_index] = _query_stamp
	result.append(shape_index)


func _advance_query_stamp() -> void:
	_query_stamp += 1
	if _query_stamp < 0x7FFFFFFF:
		return
	_candidate_stamps.fill(0)
	_query_stamp = 1


func _box_segment_interval(
	shape_index: int,
	from: Vector3,
	to: Vector3
) -> Vector2:
	var inverse := _inverse_transforms[shape_index]
	var local_from := inverse * from
	var local_to := inverse * to
	var direction := local_to - local_from
	var extents := _half_extents[shape_index]
	var minimum_t := 0.0
	var maximum_t := 1.0
	for axis: int in range(3):
		var origin_value := local_from[axis]
		var direction_value := direction[axis]
		var extent := extents[axis]
		if absf(direction_value) <= SEGMENT_EPSILON:
			if origin_value < -extent or origin_value > extent:
				return Vector2(1.0, 0.0)
			continue
		var first := (-extent - origin_value) / direction_value
		var second := (extent - origin_value) / direction_value
		if first > second:
			var swap := first
			first = second
			second = swap
		minimum_t = maxf(minimum_t, first)
		maximum_t = minf(maximum_t, second)
		if minimum_t > maximum_t:
			return Vector2(1.0, 0.0)
	return Vector2(minimum_t, maximum_t)


func _material_index(modifier: AcousticPathModifier) -> int:
	var key := _modifier_key(modifier)
	if _material_index_by_key.has(key):
		return _material_index_by_key[key]
	if _materials.size() >= MAX_MATERIALS:
		return -1
	var result := _materials.size()
	_materials.append(modifier.sanitized_copy())
	_material_index_by_key[key] = result
	return result


func _more_restrictive_material(left: int, right: int) -> int:
	if left < 0:
		return right
	if right < 0:
		return left
	var left_modifier := _materials[left]
	var right_modifier := _materials[right]
	var left_energy := (
		left_modifier.band_gain.x
		+ left_modifier.band_gain.y
		+ left_modifier.band_gain.z
	) * db_to_linear(left_modifier.volume_db)
	var right_energy := (
		right_modifier.band_gain.x
		+ right_modifier.band_gain.y
		+ right_modifier.band_gain.z
	) * db_to_linear(right_modifier.volume_db)
	return left if left_energy <= right_energy else right


func _accumulate_material(result: AcousticPathModifier, material_index: int) -> void:
	if material_index < 0 or material_index >= _materials.size():
		return
	var material := _materials[material_index]
	if result.modifier_id.is_empty():
		result.modifier_id = material.modifier_id
	elif (
		not material.modifier_id.is_empty()
		and material.modifier_id != result.modifier_id
		and not str(result.modifier_id).split("+").has(str(material.modifier_id))
	):
		result.modifier_id = StringName(
			"%s+%s" % [result.modifier_id, material.modifier_id]
		)
	result.band_gain *= material.band_gain
	result.volume_db += material.volume_db
	result.extra_delay_seconds += material.extra_delay_seconds
	result.lowpass_hz = minf(result.lowpass_hz, material.lowpass_hz)
	result.highpass_hz = minf(
		maxf(result.highpass_hz, material.highpass_hz),
		result.lowpass_hz
	)
	result.resonance = maxf(result.resonance, material.resonance)
	result.reverb_send = 1.0 - (
		(1.0 - result.reverb_send) * (1.0 - material.reverb_send)
	)


static func _bucket_cell(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / BUCKET_SIZE),
		floori(position.y / BUCKET_SIZE),
		floori(position.z / BUCKET_SIZE)
	)


static func _modifier_key(modifier: AcousticPathModifier) -> String:
	return "%s|%s|%.5f|%.5f|%.2f|%.2f|%.4f|%.4f" % [
		str(modifier.modifier_id),
		str(modifier.band_gain),
		modifier.volume_db,
		modifier.extra_delay_seconds,
		modifier.lowpass_hz,
		modifier.highpass_hz,
		modifier.resonance,
		modifier.reverb_send,
	]


static func _modifier_to_data(modifier: AcousticPathModifier) -> Dictionary:
	return {
		"id": str(modifier.modifier_id),
		"band_gain": modifier.band_gain,
		"volume_db": modifier.volume_db,
		"extra_delay_seconds": modifier.extra_delay_seconds,
		"lowpass_hz": modifier.lowpass_hz,
		"highpass_hz": modifier.highpass_hz,
		"resonance": modifier.resonance,
		"reverb_send": modifier.reverb_send,
	}


static func _modifier_from_data(data: Dictionary) -> AcousticPathModifier:
	var band_gain: Variant = data.get("band_gain", null)
	if not band_gain is Vector3:
		return null
	var result := AcousticPathModifier.new()
	result.modifier_id = StringName(str(data.get("id", "")))
	result.band_gain = band_gain as Vector3
	result.volume_db = float(data.get("volume_db", 0.0))
	result.extra_delay_seconds = float(data.get("extra_delay_seconds", 0.0))
	result.lowpass_hz = float(data.get("lowpass_hz", AcousticPathModifier.MAX_FILTER_HZ))
	result.highpass_hz = float(data.get("highpass_hz", AcousticPathModifier.MIN_FILTER_HZ))
	result.resonance = float(data.get("resonance", 0.0))
	result.reverb_send = float(data.get("reverb_send", 0.0))
	return result.sanitized_copy()
