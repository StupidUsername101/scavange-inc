class_name SparseSdfBrick
extends RefCounted

## Fixed-size quantized narrow-band brick. Distances are packed as signed 16-bit values in a byte
## array so the GDScript prototype has the same storage contract as a future native backend.

const MIN_BAND := 0.0001
const MAX_RAW := 32767
const MIN_RAW := -32767

var coordinate := Vector3i.ZERO
var cells := 16
var samples_per_axis := 17
var voxel_size := 0.05
var narrow_band := 0.2
var material_index := 1
var revision := 0

var _uniform := true
var _uniform_raw := MAX_RAW
var _distance_bytes := PackedByteArray()
var _damage_bytes := PackedByteArray()


func configure(
	new_coordinate: Vector3i,
	new_cells: int,
	new_voxel_size: float,
	new_narrow_band: float,
	new_material_index: int
) -> SparseSdfBrick:
	coordinate = new_coordinate
	cells = clampi(new_cells, 2, 64)
	samples_per_axis = cells + 1
	voxel_size = maxf(new_voxel_size, 0.001)
	narrow_band = maxf(new_narrow_band, MIN_BAND)
	material_index = clampi(new_material_index, 1, 255)
	return self


func sample_count() -> int:
	return samples_per_axis * samples_per_axis * samples_per_axis


func initialize_from_distances(values: PackedFloat32Array) -> void:
	assert(values.size() == sample_count())
	var first_raw := quantize(values[0]) if not values.is_empty() else MAX_RAW
	var remains_uniform := true
	for index: int in range(1, values.size()):
		if quantize(values[index]) != first_raw:
			remains_uniform = false
			break
	_uniform = remains_uniform
	_uniform_raw = first_raw
	_distance_bytes.clear()
	if _uniform:
		return
	_distance_bytes.resize(values.size() * 2)
	for index: int in range(values.size()):
		_write_raw(index, quantize(values[index]))


func initialize_from_box_samples(
	global_sample_origin: Vector3i,
	field_origin: Vector3,
	box_half_extents: Vector3
) -> void:
	# First-write bricks previously allocated a full float field, filled it, then allocated the
	# packed field and converted every value a second time. Generate quantized samples directly into
	# their final storage. The bytes are discarded again if the analytic region is uniform.
	var count := sample_count()
	_distance_bytes.resize(count * 2)
	_uniform = false
	var first_raw := 0
	var remains_uniform := true
	var linear_index := 0
	for z: int in range(samples_per_axis):
		var position_z := field_origin.z + float(global_sample_origin.z + z) * voxel_size
		for y: int in range(samples_per_axis):
			var position_y := field_origin.y + float(global_sample_origin.y + y) * voxel_size
			var position_x := field_origin.x + float(global_sample_origin.x) * voxel_size
			for _x: int in range(samples_per_axis):
				var raw := quantize(SdfMath.box(
					Vector3(position_x, position_y, position_z),
					box_half_extents
				))
				position_x += voxel_size
				if linear_index == 0:
					first_raw = raw
				elif raw != first_raw:
					remains_uniform = false
				_write_raw(linear_index, raw)
				linear_index += 1
	_uniform_raw = first_raw
	_uniform = remains_uniform
	if remains_uniform:
		_distance_bytes.clear()


func get_distance(x: int, y: int, z: int) -> float:
	return dequantize(get_raw(x, y, z))


func get_distance_at_index(index: int) -> float:
	return dequantize(_uniform_raw if _uniform else _read_raw(index))


func get_raw(x: int, y: int, z: int) -> int:
	var index := sample_index(x, y, z)
	return _uniform_raw if _uniform else _read_raw(index)


func set_distance(x: int, y: int, z: int, value: float) -> bool:
	return set_raw(x, y, z, quantize(value))


func set_distance_at_index(index: int, value: float) -> bool:
	return set_raw_at_index(index, quantize(value))


func replace_distance_storage(
	uniform: bool,
	uniform_raw: int,
	distance_bytes: PackedByteArray
) -> bool:
	if not uniform and distance_bytes.size() != sample_count() * 2:
		return false
	_uniform = uniform
	_uniform_raw = clampi(uniform_raw, MIN_RAW, MAX_RAW)
	_distance_bytes = PackedByteArray() if uniform else distance_bytes
	return true


func set_raw(x: int, y: int, z: int, value: int) -> bool:
	var index := sample_index(x, y, z)
	return set_raw_at_index(index, value)


func set_raw_at_index(index: int, value: int) -> bool:
	var safe_value := clampi(value, MIN_RAW, MAX_RAW)
	var previous := _uniform_raw if _uniform else _read_raw(index)
	if previous == safe_value:
		return false
	if _uniform:
		_materialize_uniform()
	_write_raw(index, safe_value)
	return true


func add_damage(x: int, y: int, z: int, amount: int) -> int:
	return add_damage_at_index(sample_index(x, y, z), amount)


func add_damage_at_index(index: int, amount: int) -> int:
	if _damage_bytes.is_empty():
		_damage_bytes.resize(sample_count())
		_damage_bytes.fill(0)
	var next := clampi(int(_damage_bytes[index]) + amount, 0, 255)
	_damage_bytes[index] = next
	return next


func set_damage(x: int, y: int, z: int, value: int) -> bool:
	return set_damage_at_index(sample_index(x, y, z), value)


func set_damage_at_index(index: int, value: int) -> bool:
	var safe_value := clampi(value, 0, 255)
	if _damage_bytes.is_empty():
		if safe_value == 0:
			return false
		_damage_bytes.resize(sample_count())
		_damage_bytes.fill(0)
	if int(_damage_bytes[index]) == safe_value:
		return false
	_damage_bytes[index] = safe_value
	return true


func get_damage(x: int, y: int, z: int) -> int:
	return get_damage_at_index(sample_index(x, y, z))


func get_damage_at_index(index: int) -> int:
	if _damage_bytes.is_empty():
		return 0
	return int(_damage_bytes[index])


func has_damage_channel() -> bool:
	return not _damage_bytes.is_empty()


func storage_byte_count() -> int:
	return _distance_bytes.size() + _damage_bytes.size()


func native_is_uniform() -> bool:
	return _uniform


func native_uniform_raw() -> int:
	return _uniform_raw


func native_distance_bytes() -> PackedByteArray:
	return _distance_bytes


func replace_native_distances(values: PackedByteArray, baseline_uniform_raw: int) -> bool:
	if values.size() != sample_count() * 2:
		return false
	_uniform = false
	_uniform_raw = clampi(baseline_uniform_raw, MIN_RAW, MAX_RAW)
	_distance_bytes = values
	return true


func compact_if_uniform() -> bool:
	if _uniform or _distance_bytes.is_empty():
		return _uniform
	var first := _read_raw(0)
	for index: int in range(1, sample_count()):
		if _read_raw(index) != first:
			return false
	_uniform = true
	_uniform_raw = first
	_distance_bytes.clear()
	return true


func duplicate_for_write() -> SparseSdfBrick:
	var result := SparseSdfBrick.new().configure(
		coordinate,
		cells,
		voxel_size,
		narrow_band,
		material_index
	)
	result.revision = revision
	result._uniform = _uniform
	result._uniform_raw = _uniform_raw
	result._distance_bytes = _distance_bytes.duplicate()
	result._damage_bytes = _damage_bytes.duplicate()
	return result


func checksum() -> int:
	var value := 2166136261
	value = _checksum_step(value, coordinate.x)
	value = _checksum_step(value, coordinate.y)
	value = _checksum_step(value, coordinate.z)
	value = _checksum_step(value, revision)
	value = _checksum_step(value, _uniform_raw)
	for byte: int in _distance_bytes:
		value = _checksum_step(value, byte)
	for byte: int in _damage_bytes:
		value = _checksum_step(value, byte)
	return value & 0x7fffffff


func encoded_state() -> Dictionary:
	return {
		"coordinate": coordinate,
		"cells": cells,
		"voxel_size": voxel_size,
		"narrow_band": narrow_band,
		"material_index": material_index,
		"revision": revision,
		"uniform": _uniform,
		"uniform_raw": _uniform_raw,
		"distance_bytes": _distance_bytes,
		"damage_bytes": _damage_bytes,
	}


static func from_encoded_state(value: Dictionary) -> SparseSdfBrick:
	var result := SparseSdfBrick.new().configure(
		value.get("coordinate", Vector3i.ZERO),
		int(value.get("cells", 16)),
		float(value.get("voxel_size", 0.05)),
		float(value.get("narrow_band", 0.2)),
		int(value.get("material_index", 1))
	)
	result.revision = maxi(int(value.get("revision", 0)), 0)
	result._uniform = bool(value.get("uniform", true))
	result._uniform_raw = clampi(int(value.get("uniform_raw", MAX_RAW)), MIN_RAW, MAX_RAW)
	result._distance_bytes = (value.get("distance_bytes", PackedByteArray()) as PackedByteArray).duplicate()
	result._damage_bytes = (value.get("damage_bytes", PackedByteArray()) as PackedByteArray).duplicate()
	var expected_bytes := result.sample_count() * 2
	if not result._uniform and result._distance_bytes.size() != expected_bytes:
		result._uniform = true
		result._uniform_raw = MAX_RAW
		result._distance_bytes.clear()
	if not result._damage_bytes.is_empty() and result._damage_bytes.size() != result.sample_count():
		result._damage_bytes.clear()
	return result


func quantize(value: float) -> int:
	var safe_value := clampf(value, -narrow_band, narrow_band)
	return clampi(roundi(safe_value / narrow_band * float(MAX_RAW)), MIN_RAW, MAX_RAW)


func dequantize(value: int) -> float:
	return float(clampi(value, MIN_RAW, MAX_RAW)) / float(MAX_RAW) * narrow_band


func sample_index(x: int, y: int, z: int) -> int:
	assert(x >= 0 and x < samples_per_axis)
	assert(y >= 0 and y < samples_per_axis)
	assert(z >= 0 and z < samples_per_axis)
	return x + samples_per_axis * (y + samples_per_axis * z)


func _materialize_uniform() -> void:
	_distance_bytes.resize(sample_count() * 2)
	for index: int in range(sample_count()):
		_write_raw(index, _uniform_raw)
	_uniform = false


func _read_raw(index: int) -> int:
	var byte_index := index * 2
	var encoded := int(_distance_bytes[byte_index]) | (int(_distance_bytes[byte_index + 1]) << 8)
	return encoded - 65536 if encoded >= 32768 else encoded


func _write_raw(index: int, value: int) -> void:
	var encoded := value & 0xffff
	var byte_index := index * 2
	_distance_bytes[byte_index] = encoded & 0xff
	_distance_bytes[byte_index + 1] = (encoded >> 8) & 0xff


static func _checksum_step(state: int, value: int) -> int:
	return ((state ^ value) * 16777619) & 0xffffffff
