class_name DroneTrainingActionTraceBuffer
extends RefCounted

const SEGMENT_WINDOW_SECONDS = 0.25
const MAX_SEGMENTS_PER_WORKER = 480
# Compatibility alias for the original drone-only tests/docs.
const MAX_SEGMENTS_PER_DRONE = MAX_SEGMENTS_PER_WORKER

var records_by_source: Dictionary = {}
var source_configs: Dictionary = {}


func begin_source_episode(
	source_id: String,
	group_id: int,
	episode_number: int,
	action_names: Array,
	action_minimum: float,
	action_maximum: float,
	worker_descriptors: Array = []
) -> void:
	if source_id.is_empty() or group_id < 0 or action_names.is_empty():
		return
	var safe_names: Array[String] = []
	for index in range(action_names.size()):
		var name = str(action_names[index]).strip_edges()
		safe_names.append(name if not name.is_empty() else "Action %d" % (index + 1))
	var low = minf(action_minimum, action_maximum)
	var high = maxf(action_minimum, action_maximum)
	if is_equal_approx(low, high):
		high = low + 1.0
	source_configs[source_id] = {
		"group_id": group_id,
		"episode_number": episode_number,
		"action_names": safe_names,
		"action_count": safe_names.size(),
		"action_minimum": low,
		"action_maximum": high,
	}
	records_by_source[source_id] = {}
	for descriptor_value in worker_descriptors:
		if not (descriptor_value is Dictionary):
			continue
		var descriptor: Dictionary = descriptor_value
		_ensure_record(
			source_id,
			int(descriptor.get("instance_id", -1)),
			int(descriptor.get("worker_index", -1))
		)


func remove_source(source_id: String) -> void:
	records_by_source.erase(source_id)
	source_configs.erase(source_id)


func append_source_commands(
	source_id: String,
	instance_id: int,
	worker_index: int,
	time_seconds: float,
	commands: PackedFloat64Array
) -> bool:
	var config: Dictionary = source_configs.get(source_id, {})
	var action_count = int(config.get("action_count", 0))
	if source_id.is_empty() or instance_id < 0 or action_count <= 0 or commands.size() != action_count:
		mark_source_invalid(source_id, instance_id, worker_index)
		return false
	for command in commands:
		if not is_finite(command):
			mark_source_invalid(source_id, instance_id, worker_index)
			return false

	var record = _ensure_record(source_id, instance_id, worker_index)
	if record.is_empty():
		return false
	var safe_time = maxf(time_seconds, 0.0)
	var recorded_commands = commands.duplicate()

	record["latest_commands"] = recorded_commands.duplicate()
	record["latest_time_seconds"] = safe_time
	record["total_decisions"] = int(record.get("total_decisions", 0)) + 1
	_update_episode_statistics(record, recorded_commands)

	var segments: Array = record.get("segments", [])
	if segments.is_empty():
		segments.append(_new_segment(safe_time, recorded_commands))
	else:
		var last_segment: Dictionary = segments[segments.size() - 1]
		if safe_time - float(last_segment.get("start_time_seconds", 0.0)) < SEGMENT_WINDOW_SECONDS:
			_merge_sample_into_segment(last_segment, safe_time, recorded_commands)
			segments[segments.size() - 1] = last_segment
		else:
			segments.append(_new_segment(safe_time, recorded_commands))
	while segments.size() > MAX_SEGMENTS_PER_WORKER:
		_compact_smallest_adjacent_pair(segments, action_count)
	record["segments"] = segments
	return true


func mark_source_invalid(source_id: String, instance_id: int, worker_index: int) -> void:
	if source_id.is_empty() or instance_id < 0 or not source_configs.has(source_id):
		return
	var record = _ensure_record(source_id, instance_id, worker_index)
	if record.is_empty():
		return
	record["invalid_samples"] = int(record.get("invalid_samples", 0)) + 1


func records_for_source(source_id: String) -> Dictionary:
	var value: Variant = records_by_source.get(source_id, {})
	return value as Dictionary if value is Dictionary else {}


func record_for_source(source_id: String, instance_id: int) -> Dictionary:
	var source_records = records_for_source(source_id)
	var value: Variant = source_records.get(instance_id, {})
	return value as Dictionary if value is Dictionary else {}


func source_config(source_id: String) -> Dictionary:
	var value: Variant = source_configs.get(source_id, {})
	return value as Dictionary if value is Dictionary else {}


# Compatibility wrappers for older drone-only callers/tests. New code should use the source-aware API.
func begin_episode(new_episode_number: int, drone_descriptors: Array[Dictionary]) -> void:
	# Preserve the old API's meaning: a new drone episode clears every prior drone trace,
	# while leaving independent non-drone worker-kind episodes untouched.
	var prior_source_ids: Array = source_configs.keys()
	for source_id_value in prior_source_ids:
		var source_id = str(source_id_value)
		if source_id.begins_with("drone:"):
			remove_source(source_id)
	var descriptors_by_group: Dictionary = {}
	for descriptor in drone_descriptors:
		var group_id = int(descriptor.get("group_id", -1))
		if group_id < 0:
			continue
		if not descriptors_by_group.has(group_id):
			descriptors_by_group[group_id] = []
		(descriptors_by_group[group_id] as Array).append(descriptor)
	for group_id_value in descriptors_by_group:
		var group_id = int(group_id_value)
		begin_source_episode(
			"drone:%d" % group_id,
			group_id,
			new_episode_number,
			["P0 thrust", "P1 thrust", "P2 thrust", "P3 thrust"],
			0.0,
			1.0,
			descriptors_by_group[group_id]
		)


func remove_group(group_id: int) -> void:
	remove_source("drone:%d" % group_id)


func append_commands(
	group_id: int,
	instance_id: int,
	worker_index: int,
	time_seconds: float,
	commands: PackedFloat64Array
) -> bool:
	return append_source_commands(
		"drone:%d" % group_id,
		instance_id,
		worker_index,
		time_seconds,
		commands
	)


func mark_invalid(group_id: int, instance_id: int, worker_index: int) -> void:
	mark_source_invalid("drone:%d" % group_id, instance_id, worker_index)


func records_for_group(group_id: int) -> Dictionary:
	return records_for_source("drone:%d" % group_id)


func record_for(group_id: int, instance_id: int) -> Dictionary:
	return record_for_source("drone:%d" % group_id, instance_id)


func _ensure_record(source_id: String, instance_id: int, worker_index: int) -> Dictionary:
	if instance_id < 0:
		return {}
	var config: Dictionary = source_configs.get(source_id, {})
	var action_count = int(config.get("action_count", 0))
	if action_count <= 0:
		return {}
	if not records_by_source.has(source_id):
		records_by_source[source_id] = {}
	var source_records: Dictionary = records_by_source[source_id]
	if not source_records.has(instance_id):
		source_records[instance_id] = {
			"episode_number": int(config.get("episode_number", -1)),
			"group_id": int(config.get("group_id", -1)),
			"source_id": source_id,
			"instance_id": instance_id,
			"worker_index": worker_index,
			"action_names": (config.get("action_names", []) as Array).duplicate(),
			"action_count": action_count,
			"action_minimum": float(config.get("action_minimum", -1.0)),
			"action_maximum": float(config.get("action_maximum", 1.0)),
			"segments": [],
			"latest_commands": PackedFloat64Array(),
			"latest_time_seconds": 0.0,
			"total_decisions": 0,
			"invalid_samples": 0,
			"saturated_channel_samples": 0,
			"all_high_decisions": 0,
			"all_low_decisions": 0,
			"sum_commands": _filled_array(action_count, 0.0),
			"minimum_commands": _filled_array(action_count, INF),
			"maximum_commands": _filled_array(action_count, -INF),
		}
	var record: Dictionary = source_records[instance_id]
	if worker_index >= 0:
		record["worker_index"] = worker_index
	return record


func _update_episode_statistics(record: Dictionary, commands: PackedFloat64Array) -> void:
	var action_count = int(record.get("action_count", commands.size()))
	var sums: PackedFloat64Array = record.get("sum_commands", _filled_array(action_count, 0.0))
	var minimums: PackedFloat64Array = record.get("minimum_commands", _filled_array(action_count, INF))
	var maximums: PackedFloat64Array = record.get("maximum_commands", _filled_array(action_count, -INF))
	var command_minimum = float(record.get("action_minimum", -1.0))
	var command_maximum = float(record.get("action_maximum", 1.0))
	var saturation_epsilon = maxf((command_maximum - command_minimum) * 0.01, 0.000001)
	var low_threshold = command_minimum + saturation_epsilon
	var high_threshold = command_maximum - saturation_epsilon
	var all_high = true
	var all_low = true
	var saturated_channels = 0
	for index in range(action_count):
		var command = commands[index]
		sums[index] += command
		minimums[index] = minf(minimums[index], command)
		maximums[index] = maxf(maximums[index], command)
		all_high = all_high and command >= high_threshold
		all_low = all_low and command <= low_threshold
		if command <= low_threshold or command >= high_threshold:
			saturated_channels += 1
	record["saturated_channel_samples"] = int(record.get("saturated_channel_samples", 0)) + saturated_channels
	if all_high:
		record["all_high_decisions"] = int(record.get("all_high_decisions", 0)) + 1
	if all_low:
		record["all_low_decisions"] = int(record.get("all_low_decisions", 0)) + 1
	record["sum_commands"] = sums
	record["minimum_commands"] = minimums
	record["maximum_commands"] = maximums


func _new_segment(time_seconds: float, commands: PackedFloat64Array) -> Dictionary:
	return {
		"start_time_seconds": time_seconds,
		"end_time_seconds": time_seconds,
		"sample_count": 1,
		"sum_commands": commands.duplicate(),
		"minimum_commands": commands.duplicate(),
		"maximum_commands": commands.duplicate(),
		"last_commands": commands.duplicate(),
	}


func _merge_sample_into_segment(
	segment: Dictionary,
	time_seconds: float,
	commands: PackedFloat64Array
) -> void:
	var action_count = commands.size()
	var sums: PackedFloat64Array = segment.get("sum_commands", _filled_array(action_count, 0.0))
	var minimums: PackedFloat64Array = segment.get("minimum_commands", commands.duplicate())
	var maximums: PackedFloat64Array = segment.get("maximum_commands", commands.duplicate())
	for index in range(action_count):
		sums[index] += commands[index]
		minimums[index] = minf(minimums[index], commands[index])
		maximums[index] = maxf(maximums[index], commands[index])
	segment["end_time_seconds"] = maxf(
		float(segment.get("end_time_seconds", time_seconds)),
		time_seconds
	)
	segment["sample_count"] = int(segment.get("sample_count", 0)) + 1
	segment["sum_commands"] = sums
	segment["minimum_commands"] = minimums
	segment["maximum_commands"] = maximums
	segment["last_commands"] = commands.duplicate()


func _compact_smallest_adjacent_pair(segments: Array, action_count: int) -> void:
	if segments.size() < 2:
		return
	var best_index = 0
	var best_span = INF
	for index in range(segments.size() - 1):
		var first: Dictionary = segments[index]
		var second: Dictionary = segments[index + 1]
		var span = (
			float(second.get("end_time_seconds", 0.0))
			- float(first.get("start_time_seconds", 0.0))
		)
		if span < best_span:
			best_span = span
			best_index = index
	segments[best_index] = _merge_segments(
		segments[best_index],
		segments[best_index + 1],
		action_count
	)
	segments.remove_at(best_index + 1)


func _merge_segments(first: Dictionary, second: Dictionary, action_count: int) -> Dictionary:
	var first_count = maxi(int(first.get("sample_count", 0)), 0)
	var second_count = maxi(int(second.get("sample_count", 0)), 0)
	var first_sums: PackedFloat64Array = first.get("sum_commands", _filled_array(action_count, 0.0))
	var second_sums: PackedFloat64Array = second.get("sum_commands", _filled_array(action_count, 0.0))
	var first_minimums: PackedFloat64Array = first.get("minimum_commands", _filled_array(action_count, INF))
	var second_minimums: PackedFloat64Array = second.get("minimum_commands", _filled_array(action_count, INF))
	var first_maximums: PackedFloat64Array = first.get("maximum_commands", _filled_array(action_count, -INF))
	var second_maximums: PackedFloat64Array = second.get("maximum_commands", _filled_array(action_count, -INF))
	var sums = _filled_array(action_count, 0.0)
	var minimums = _filled_array(action_count, INF)
	var maximums = _filled_array(action_count, -INF)
	for index in range(action_count):
		sums[index] = first_sums[index] + second_sums[index]
		minimums[index] = minf(first_minimums[index], second_minimums[index])
		maximums[index] = maxf(first_maximums[index], second_maximums[index])
	return {
		"start_time_seconds": float(first.get("start_time_seconds", 0.0)),
		"end_time_seconds": float(second.get("end_time_seconds", 0.0)),
		"sample_count": first_count + second_count,
		"sum_commands": sums,
		"minimum_commands": minimums,
		"maximum_commands": maximums,
		"last_commands": _packed_array(second.get("last_commands", PackedFloat64Array())),
	}


func _filled_array(size: int, value: float) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(maxi(size, 0))
	for index in range(result.size()):
		result[index] = value
	return result


func _packed_array(value: Variant) -> PackedFloat64Array:
	if value is PackedFloat64Array:
		return (value as PackedFloat64Array).duplicate()
	if value is Array:
		return PackedFloat64Array(value)
	return PackedFloat64Array()
