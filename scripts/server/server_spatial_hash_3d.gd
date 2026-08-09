class_name ServerSpatialHash3D
extends RefCounted

#######################################################
# Owns authoritative spatial hash 3d simulation and exposes the state required for replication
# and interaction.
#######################################################

## Persistent broad-phase index for authoritative server entities.
##
## Bodies are registered once and only moved between buckets after crossing a
## cell boundary. Query results are cached and invalidated by membership
## changes in one of their covered cells, so an empty neighborhood remains an
## O(1) cache hit until something spatially relevant changes.

var cell_size = 8.0

var _records: Dictionary[StringName, Dictionary] = {}
var _cells: Dictionary[Vector3i, Dictionary] = {}
var _query_caches: Dictionary[StringName, Dictionary] = {}
var _cache_ids_by_cell: Dictionary[Vector3i, Dictionary] = {}
var _kind_counts: Dictionary[StringName, int] = {}
var _keys_by_kind: Dictionary[StringName, Dictionary] = {}
var _sorted_keys_by_kind: Dictionary[StringName, Array] = {}
var _empty_readonly_keys: Array = []

var cell_transition_count = 0
var query_rebuild_count = 0
var query_cache_hit_count = 0


func _init(configured_cell_size = 8.0) -> void:
	cell_size = maxf(configured_cell_size, 0.25)


func register_entity(
	entity_key: StringName,
	body: Node3D,
	kind: StringName,
	entity_id: int,
	metadata: Dictionary = {}
) -> void:
	if entity_key.is_empty() or body == null:
		return
	if _records.has(entity_key):
		unregister_entity(entity_key)

	var cell = _cell_for_position(body.global_position)
	_records[entity_key] = {
		"body": body,
		"kind": kind,
		"entity_id": entity_id,
		"metadata": metadata.duplicate(),
		"cell": cell,
	}
	_kind_counts[kind] = int(_kind_counts.get(kind, 0)) + 1
	var kind_keys: Dictionary = _keys_by_kind.get(kind, {})
	kind_keys[entity_key] = true
	_keys_by_kind[kind] = kind_keys
	var sorted_kind_keys: Array = _sorted_keys_by_kind.get(kind, [])
	if not sorted_kind_keys.has(entity_key):
		sorted_kind_keys.append(entity_key)
		sorted_kind_keys.sort()
	_sorted_keys_by_kind[kind] = sorted_kind_keys
	_insert_into_cell(entity_key, cell)


func unregister_entity(entity_key: StringName) -> void:
	var record: Dictionary = _records.get(entity_key, {})
	if record.is_empty():
		return
	var cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var kind: StringName = record.get("kind", &"")
	_remove_from_cell(entity_key, cell)
	_records.erase(entity_key)
	var remaining = maxi(int(_kind_counts.get(kind, 0)) - 1, 0)
	var kind_keys: Dictionary = _keys_by_kind.get(kind, {})
	kind_keys.erase(entity_key)
	var sorted_kind_keys: Array = _sorted_keys_by_kind.get(kind, [])
	sorted_kind_keys.erase(entity_key)
	if remaining <= 0:
		_kind_counts.erase(kind)
		_keys_by_kind.erase(kind)
		_sorted_keys_by_kind.erase(kind)
	else:
		_kind_counts[kind] = remaining
		_keys_by_kind[kind] = kind_keys
		_sorted_keys_by_kind[kind] = sorted_kind_keys


func update_entity(entity_key: StringName) -> bool:
	var record: Dictionary = _records.get(entity_key, {})
	if record.is_empty():
		return false
	var body = record.get("body") as Node3D
	if not is_instance_valid(body):
		unregister_entity(entity_key)
		return false

	var previous_cell: Vector3i = record.get("cell", Vector3i.ZERO)
	var next_cell = _cell_for_position(body.global_position)
	if next_cell == previous_cell:
		return false

	_remove_from_cell(entity_key, previous_cell)
	record["cell"] = next_cell
	_insert_into_cell(entity_key, next_cell)
	cell_transition_count += 1
	return true


func refresh_all() -> void:
	if _records.is_empty():
		return
	var keys: Array[StringName] = []
	for raw_key: StringName in _records.keys():
		keys.append(raw_key)
	for entity_key: StringName in keys:
		update_entity(entity_key)


func get_record(entity_key: StringName) -> Dictionary:
	return _records.get(entity_key, {})


func set_entity_metadata(entity_key: StringName, metadata: Dictionary) -> bool:
	var record: Dictionary = _records.get(entity_key, {})
	if record.is_empty():
		return false
	record["metadata"] = metadata.duplicate()
	return true


func all_keys() -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_key: StringName in _records.keys():
		result.append(raw_key)
	result.sort()
	return result


func has_entity(entity_key: StringName) -> bool:
	return _records.has(entity_key)


func has_kind(kind: StringName) -> bool:
	return int(_kind_counts.get(kind, 0)) > 0


func kind_count(kind: StringName) -> int:
	return int(_kind_counts.get(kind, 0))


func readonly_keys_for_kind(kind: StringName) -> Array:
	# This is a read-only hot-path view. Registration keeps it sorted, so long-range sensors can
	# iterate a sparse entity kind without rebuilding arrays or walking thousands of empty cells.
	return _sorted_keys_by_kind.get(kind, _empty_readonly_keys)


func keys_for_kinds(kinds: Array[StringName]) -> Array[StringName]:
	# Sparse long-range sensors should iterate the few entities of the requested kind instead of
	# walking every empty cell in a large 3D radius. Exact range checks remain the caller's job.
	var unique_keys: Dictionary[StringName, bool] = {}
	for kind: StringName in kinds:
		var kind_keys: Dictionary = _keys_by_kind.get(kind, {})
		for entity_key: StringName in kind_keys.keys():
			unique_keys[entity_key] = true
	var result: Array[StringName] = []
	for entity_key: StringName in unique_keys.keys():
		result.append(entity_key)
	result.sort()
	return result


func query_keys_uncached(
	origin: Vector3,
	radius: float,
	kinds: Array[StringName]
) -> Array[StringName]:
	var safe_radius = maxf(radius, 0.0)
	var minimum_cell = _cell_for_position(origin - Vector3.ONE * safe_radius)
	var maximum_cell = _cell_for_position(origin + Vector3.ONE * safe_radius)
	var unique_keys: Dictionary[StringName, bool] = {}
	for x: int in range(minimum_cell.x, maximum_cell.x + 1):
		for y: int in range(minimum_cell.y, maximum_cell.y + 1):
			for z: int in range(minimum_cell.z, maximum_cell.z + 1):
				var bucket: Dictionary = _cells.get(Vector3i(x, y, z), {})
				for raw_key: StringName in bucket.keys():
					var record: Dictionary = _records.get(raw_key, {})
					var record_kind: StringName = record.get("kind", &"")
					if not record.is_empty() and record_kind in kinds:
						unique_keys[raw_key] = true
	var result: Array[StringName] = []
	for raw_key: StringName in unique_keys.keys():
		result.append(raw_key)
	result.sort()
	return result


func query_keys(
	cache_id: StringName,
	origin: Vector3,
	radius: float,
	kinds: Array[StringName]
) -> Array[StringName]:
	var safe_radius = maxf(radius, 0.0)
	var minimum_cell = _cell_for_position(
		origin - Vector3.ONE * safe_radius
	)
	var maximum_cell = _cell_for_position(
		origin + Vector3.ONE * safe_radius
	)
	var cache: Dictionary = _query_caches.get(cache_id, {})
	if (
		not cache.is_empty()
		and not bool(cache.get("dirty", true))
		and cache.get("minimum_cell", Vector3i.ZERO) == minimum_cell
		and cache.get("maximum_cell", Vector3i.ZERO) == maximum_cell
		and cache.get("kinds", []) == kinds
	):
		query_cache_hit_count += 1
		var cached_keys: Array = cache.get("keys", [])
		return _copy_string_name_array(cached_keys)

	_clear_query_cache_registration(cache_id, cache)
	var covered_cells: Array[Vector3i] = []
	var unique_keys: Dictionary[StringName, bool] = {}
	for x: int in range(minimum_cell.x, maximum_cell.x + 1):
		for y: int in range(minimum_cell.y, maximum_cell.y + 1):
			for z: int in range(minimum_cell.z, maximum_cell.z + 1):
				var cell = Vector3i(x, y, z)
				covered_cells.append(cell)
				var bucket: Dictionary = _cells.get(cell, {})
				for raw_key: StringName in bucket.keys():
					var record: Dictionary = _records.get(raw_key, {})
					var record_kind: StringName = record.get("kind", &"")
					if (
						not record.is_empty()
						and record_kind in kinds
					):
						unique_keys[raw_key] = true

	var result: Array[StringName] = []
	for raw_key: StringName in unique_keys.keys():
		result.append(raw_key)
	result.sort()
	cache = {
		"dirty": false,
		"minimum_cell": minimum_cell,
		"maximum_cell": maximum_cell,
		"kinds": kinds.duplicate(),
		"cells": covered_cells,
		"keys": result,
	}
	_query_caches[cache_id] = cache
	for cell: Vector3i in covered_cells:
		var cache_ids: Dictionary = _cache_ids_by_cell.get(cell, {})
		cache_ids[cache_id] = true
		_cache_ids_by_cell[cell] = cache_ids
	query_rebuild_count += 1
	return result


func clear_query_cache(cache_id: StringName) -> void:
	var cache: Dictionary = _query_caches.get(cache_id, {})
	_clear_query_cache_registration(cache_id, cache)
	_query_caches.erase(cache_id)


func get_debug_state() -> Dictionary:
	return {
		"entity_count": _records.size(),
		"occupied_cell_count": _cells.size(),
		"query_cache_count": _query_caches.size(),
		"cell_transitions": cell_transition_count,
		"query_rebuilds": query_rebuild_count,
		"query_cache_hits": query_cache_hit_count,
		"kind_counts": _kind_counts.duplicate(),
		"indexed_kind_count": _keys_by_kind.size(),
		"sorted_kind_index_count": _sorted_keys_by_kind.size(),
	}


func _cell_for_position(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / cell_size),
		floori(position.y / cell_size),
		floori(position.z / cell_size)
	)


func _insert_into_cell(entity_key: StringName, cell: Vector3i) -> void:
	var bucket: Dictionary = _cells.get(cell, {})
	bucket[entity_key] = true
	_cells[cell] = bucket
	_mark_cell_dirty(cell)


func _remove_from_cell(entity_key: StringName, cell: Vector3i) -> void:
	var bucket: Dictionary = _cells.get(cell, {})
	if bucket.is_empty():
		return
	bucket.erase(entity_key)
	if bucket.is_empty():
		_cells.erase(cell)
	else:
		_cells[cell] = bucket
	_mark_cell_dirty(cell)


func _mark_cell_dirty(cell: Vector3i) -> void:
	var cache_ids: Dictionary = _cache_ids_by_cell.get(cell, {})
	for raw_cache_id: StringName in cache_ids.keys():
		var cache: Dictionary = _query_caches.get(raw_cache_id, {})
		if not cache.is_empty():
			cache["dirty"] = true


func _clear_query_cache_registration(
	cache_id: StringName,
	cache: Dictionary
) -> void:
	if cache.is_empty():
		return
	var covered_cells: Array = cache.get("cells", [])
	for raw_cell: Variant in covered_cells:
		var cell: Vector3i = raw_cell
		var cache_ids: Dictionary = _cache_ids_by_cell.get(cell, {})
		cache_ids.erase(cache_id)
		if cache_ids.is_empty():
			_cache_ids_by_cell.erase(cell)
		else:
			_cache_ids_by_cell[cell] = cache_ids


func _copy_string_name_array(raw_values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for raw_value: Variant in raw_values:
		result.append(StringName(raw_value))
	return result
