class_name DroneSACNavigationMemory
extends RefCounted

const CELL_SIZE_M = 1.5
const SECTOR_COUNT = 8
const NEAR_RADIUS_CELLS = 1
const FAR_RADIUS_CELLS = 3
const VISIT_SATURATION = 4.0
const CLEARANCE_REQUIRED_M = 2.0
const FEATURE_COUNT = 19
const SECTOR_DIRECTIONS_LOCAL: Array[Vector3] = [
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.70710678118, 0.0, -0.70710678118),
	Vector3(1.0, 0.0, 0.0),
	Vector3(0.70710678118, 0.0, 0.70710678118),
	Vector3(0.0, 0.0, 1.0),
	Vector3(-0.70710678118, 0.0, 0.70710678118),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(-0.70710678118, 0.0, -0.70710678118),
]

var memories: Dictionary = {}


func features_for(worker_id: int, observation: Dictionary) -> PackedFloat64Array:
	var body: Dictionary = observation.get("body", {})
	var objective: Dictionary = observation.get("objective", {})
	var position: Vector3 = body.get("position_world", Vector3.ZERO)
	var progress = clampf(float(objective.get("episode_progress", 0.0)), 0.0, 1.0)
	var memory: Dictionary = memories.get(worker_id, {})
	var last_progress = float(memory.get("last_progress", -1.0))
	var last_position: Vector3 = memory.get("last_position", position)
	if (
		memory.is_empty()
		or (last_progress >= 0.0 and progress + 0.1 < last_progress)
		or position.distance_to(last_position) > CELL_SIZE_M * 8.0
	):
		memory = {
			"visits": {},
			"last_progress": progress,
			"last_position": position,
		}
		memories[worker_id] = memory

	var visits: Dictionary = memory.get("visits", {})
	var cell = _cell(position)
	var key = _cell_key(cell)
	visits[key] = int(visits.get(key, 0)) + 1
	memory["visits"] = visits
	memory["last_progress"] = progress
	memory["last_position"] = position
	memories[worker_id] = memory

	var result = PackedFloat64Array()
	result.append(_visit_feature(int(visits.get(key, 0))))
	var near_counts: Array[int] = []
	var far_counts: Array[int] = []
	for sector in range(SECTOR_COUNT):
		var world_direction = _sector_world_direction(observation, sector)
		var near_cell = _cell(
			position + world_direction * CELL_SIZE_M * float(NEAR_RADIUS_CELLS)
		)
		var far_cell = _cell(
			position + world_direction * CELL_SIZE_M * float(FAR_RADIUS_CELLS)
		)
		var near_count = int(visits.get(_cell_key(near_cell), 0))
		var far_count = int(visits.get(_cell_key(far_cell), 0))
		near_counts.append(near_count)
		far_counts.append(far_count)
		result.append(_visit_feature(near_count))
	for count in far_counts:
		result.append(_visit_feature(count))

	var exploration_heading = _least_visited_heading(
		observation,
		near_counts,
		far_counts
	)
	result.append(exploration_heading.x)
	result.append(exploration_heading.y)
	return result


func reset(worker_id: int) -> void:
	memories.erase(worker_id)


func reset_all() -> void:
	memories.clear()


func to_state() -> Dictionary:
	return {
		"schema_version": 1,
		"memories": RLTrainingVariantCodec.encode(memories),
	}


func load_state(state: Dictionary) -> bool:
	if RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1) != 1:
		return false
	var decoded: Variant = RLTrainingVariantCodec.decode(state.get("memories", {}))
	if not (decoded is Dictionary):
		return false
	var candidate: Dictionary = decoded
	for worker_id in candidate:
		if not (worker_id is int) or not (candidate[worker_id] is Dictionary):
			return false
		var memory: Dictionary = candidate[worker_id]
		var visits_value: Variant = memory.get("visits", {})
		var position_value: Variant = memory.get("last_position", Vector3.ZERO)
		var progress: float = RLTrainingMath.finite_float_or(memory.get("last_progress", NAN), NAN)
		if not (visits_value is Dictionary) or not (position_value is Vector3):
			return false
		var last_position: Vector3 = position_value
		if (
			not is_finite(last_position.x)
			or not is_finite(last_position.y)
			or not is_finite(last_position.z)
			or not is_finite(progress)
			or progress < 0.0
			or progress > 1.0
		):
			return false
		var visits: Dictionary = visits_value
		for cell_key: Variant in visits:
			if not (cell_key is String):
				return false
			var count_value: Variant = visits[cell_key]
			if not (count_value is int) or int(count_value) < 0:
				return false
	memories = candidate.duplicate(true)
	return true


func _least_visited_heading(
	observation: Dictionary,
	near_counts: Array[int],
	far_counts: Array[int]
) -> Vector2:
	var objective: Dictionary = observation.get("objective", {})
	var probe: Dictionary = objective.get("obstacle_probe", {})
	var clearances_value: Variant = probe.get("sector_clearances_m", [])
	var clearances = PackedFloat64Array()
	if clearances_value is PackedFloat64Array:
		clearances = clearances_value
	elif clearances_value is Array:
		for value in clearances_value:
			clearances.append(float(value))
	var best_sector = -1
	var best_score = INF
	for sector in range(SECTOR_COUNT):
		var clearance = (
			float(clearances[sector])
			if sector < clearances.size()
			else float(probe.get("sector_maximum_distance_m", 4.0))
		)
		if clearance < CLEARANCE_REQUIRED_M:
			continue
		var score = float(near_counts[sector] * 3 + far_counts[sector])
		# Prefer wider corridors when visit counts tie.
		score -= minf(clearance, 4.0) * 0.05
		if score < best_score:
			best_score = score
			best_sector = sector
	if best_sector < 0:
		return Vector2.ZERO
	var angle = float(best_sector) * TAU / float(SECTOR_COUNT)
	return Vector2(sin(angle), -cos(angle)).normalized()


func _cell(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / CELL_SIZE_M),
		floori(position.z / CELL_SIZE_M)
	)


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


func _sector_world_direction(
	observation: Dictionary,
	sector: int
) -> Vector3:
	var body: Dictionary = observation.get("body", {})
	var basis: Basis = body.get("basis_world", Basis.IDENTITY)
	var world_direction = basis * SECTOR_DIRECTIONS_LOCAL[posmod(sector, SECTOR_COUNT)]
	world_direction.y = 0.0
	if world_direction.length_squared() <= 0.000001:
		return SECTOR_DIRECTIONS_LOCAL[posmod(sector, SECTOR_COUNT)]
	return world_direction.normalized()


func _visit_feature(count: int) -> float:
	var normalized = 1.0 - exp(-float(maxi(count, 0)) / VISIT_SATURATION)
	return clampf(normalized * 2.0 - 1.0, -1.0, 1.0)
