class_name DroneTrainingMetricsHistory
extends RefCounted

const MAXIMUM_POINTS = 240

# Episode history contains one record per completed worker, but plots contain one
# averaged point per episode number. Trim by distinct episode buckets so worker count
# does not divide the visible timeline (12 SAC workers previously reduced 240 records
# to only 20 plotted episodes; 24 workers reduced it to 10).

var updates: Array[Dictionary] = []
var episodes: Array[Dictionary] = []
var retained_episode_numbers: Array[int] = []
var expected_results_by_episode: Dictionary = {}
var plot_index_by_episode_number: Dictionary = {}
var next_plot_episode_index: int = 1


func record_update(metrics: Dictionary) -> void:
	if metrics.is_empty():
		return
	updates.append(metrics.duplicate(true))
	_trim(updates)


func record_episode(result: Dictionary, expected_result_count: int = 1) -> void:
	if result.is_empty():
		return
	var stored_result: Dictionary = result.duplicate(true)
	var result_episode_number = int(stored_result.get(
		"episode_number",
		retained_episode_numbers.size() + 1
	))
	var safe_expected_count = maxi(expected_result_count, 1)
	stored_result["episode_number"] = result_episode_number
	if not plot_index_by_episode_number.has(result_episode_number):
		plot_index_by_episode_number[result_episode_number] = next_plot_episode_index
		next_plot_episode_index += 1
	stored_result["plot_episode_index"] = int(plot_index_by_episode_number[result_episode_number])
	stored_result["expected_group_result_count"] = safe_expected_count
	episodes.append(stored_result)
	expected_results_by_episode[result_episode_number] = maxi(
		int(expected_results_by_episode.get(result_episode_number, 1)),
		safe_expected_count
	)
	if not retained_episode_numbers.has(result_episode_number):
		retained_episode_numbers.append(result_episode_number)
		retained_episode_numbers.sort()
	_trim_episode_buckets()


func discard_incomplete_episode(episode_number: int) -> void:
	var result_count = 0
	for record in episodes:
		if int(record.get("episode_number", -1)) == episode_number:
			result_count += 1
	var expected_count = maxi(
		int(expected_results_by_episode.get(episode_number, 1)),
		1
	)
	if result_count > 0 and result_count < expected_count:
		_remove_episode_bucket(episode_number)


func reset() -> void:
	updates.clear()
	episodes.clear()
	retained_episode_numbers.clear()
	expected_results_by_episode.clear()
	plot_index_by_episode_number.clear()
	next_plot_episode_index = 1


func episode_metric_series(
	y_key: String,
	label: String,
	color: Color
) -> Dictionary:
	return _series_from(
		_completed_episode_records(),
		"plot_episode_index",
		y_key,
		label,
		color
	)


func episode_mean_series(
	y_key: String,
	label: String,
	color: Color
) -> Dictionary:
	return _mean_series_from(
		_completed_episode_records(),
		"plot_episode_index",
		y_key,
		label,
		color
	)


func update_metric_series(
	y_key: String,
	label: String,
	color: Color
) -> Dictionary:
	return _series_from(updates, "update", y_key, label, color)


func hover_ratio_series(label: String, color: Color) -> Dictionary:
	return _ratio_series(_completed_episode_records(), label, color)


func hover_ratio_mean_series(label: String, color: Color) -> Dictionary:
	var averages: Dictionary = {}
	var completed_records = _completed_episode_records()
	for index in range(completed_records.size()):
		var record: Dictionary = completed_records[index]
		var episode_number = int(record.get("plot_episode_index", index + 1))
		var elapsed = maxf(
			float(record.get("episode_elapsed_seconds", 0.0)),
			0.000001
		)
		var ratio = clampf(
			float(record.get("time_inside_radius_seconds", 0.0)) / elapsed,
			0.0,
			1.0
		)
		if not averages.has(episode_number):
			averages[episode_number] = {"total": 0.0, "count": 0}
		var bucket: Dictionary = averages[episode_number]
		bucket["total"] = float(bucket["total"]) + ratio
		bucket["count"] = int(bucket["count"]) + 1
	return _series_from_average_buckets(averages, label, color)


func latest_episode_value(key: String, fallback = 0.0) -> float:
	var completed_records = _completed_episode_records()
	if completed_records.is_empty():
		return float(fallback)
	return float(completed_records[completed_records.size() - 1].get(
		key,
		fallback
	))


func plot_series(plot_id: String) -> Array[Dictionary]:
	var completed_records = _completed_episode_records()
	match plot_id:
		"progress":
			return [
				_mean_series_from(completed_records, "plot_episode_index", "mean_reward_per_second", "reward/s", Color("54e6b1")),
				hover_ratio_mean_series("hover ratio", Color("ffad42")),
			]
		"tracking":
			return [
				_mean_series_from(completed_records, "plot_episode_index", "distance_m", "distance m", Color("8de1ff")),
			]
		"rewards":
			return [
				_mean_series_from(completed_records, "plot_episode_index", "cumulative_approach_reward", "approach", Color("54e6b1")),
				_mean_series_from(completed_records, "plot_episode_index", "cumulative_radius_reward", "radius", Color("ffad42")),
				_mean_series_from(completed_records, "plot_episode_index", "cumulative_survival_reward", "survival", Color("8de1ff")),
				_mean_series_from(completed_records, "plot_episode_index", "cumulative_ground_safety_reward", "ground", Color("ff8b5c")),
				_mean_series_from(completed_records, "plot_episode_index", "cumulative_smoothness_reward", "smooth", Color("b08cff")),
				_mean_series_from(completed_records, "plot_episode_index", "cumulative_obstacle_reward", "walls", Color("ff5c77")),
			]
		"losses":
			return [
				_series_from(updates, "update", "actor_loss", "actor", Color("54e6b1")),
				_series_from(updates, "update", "value_loss", "critic", Color("ffad42")),
			]
		"stability":
			return [
				_series_from(updates, "update", "entropy", "latent entropy", Color("8de1ff")),
				_series_from(updates, "update", "approximate_kl", "KL", Color("ff5c77")),
				_series_from(updates, "update", "clip_fraction", "clip", Color("b08cff")),
				_series_from(updates, "update", "action_standard_deviation_mean", "latent action std", Color("54e6b1")),
			]
	return []


func _series_from(
	records: Array[Dictionary],
	x_key: String,
	y_key: String,
	label: String,
	color: Color
) -> Dictionary:
	var points = PackedVector2Array()
	for index in range(records.size()):
		var record: Dictionary = records[index]
		# Missing readings are missing data, not measurements of zero. Treating them as
		# zero made different trainer types appear to append metrics differently and could
		# draw a fake flat line whenever an algorithm did not publish a particular field.
		if not record.has(y_key):
			continue
		var x_value: Variant = record.get(x_key, index + 1)
		var y_value: Variant = record.get(y_key)
		if not (x_value is int or x_value is float) or not (y_value is int or y_value is float):
			continue
		var x: float = float(x_value)
		var y: float = float(y_value)
		if is_finite(x) and is_finite(y):
			points.append(Vector2(x, y))
	return {"label": label, "color": color, "points": points}


func _ratio_series(
	records: Array[Dictionary],
	label: String,
	color: Color
) -> Dictionary:
	var points = PackedVector2Array()
	for index in range(records.size()):
		var record: Dictionary = records[index]
		var elapsed = maxf(float(record.get("episode_elapsed_seconds", 0.0)), 0.000001)
		var ratio = clampf(
			float(record.get("time_inside_radius_seconds", 0.0)) / elapsed,
			0.0,
			1.0
		)
		points.append(Vector2(float(record.get("plot_episode_index", index + 1)), ratio))
	return {"label": label, "color": color, "points": points}


func _mean_series_from(
	records: Array[Dictionary],
	x_key: String,
	y_key: String,
	label: String,
	color: Color
) -> Dictionary:
	var averages: Dictionary = {}
	for index in range(records.size()):
		var record: Dictionary = records[index]
		if not record.has(y_key):
			continue
		var x_value: Variant = record.get(x_key, index + 1)
		var y_value: Variant = record.get(y_key)
		if not (x_value is int or x_value is float) or not (y_value is int or y_value is float):
			continue
		var x: int = int(x_value)
		var y: float = float(y_value)
		if not is_finite(y):
			continue
		if not averages.has(x):
			averages[x] = {"total": 0.0, "count": 0}
		var bucket: Dictionary = averages[x]
		bucket["total"] = float(bucket["total"]) + y
		bucket["count"] = int(bucket["count"]) + 1
	return _series_from_average_buckets(averages, label, color)


func _series_from_average_buckets(
	averages: Dictionary,
	label: String,
	color: Color
) -> Dictionary:
	var keys: Array = averages.keys()
	keys.sort()
	var points = PackedVector2Array()
	for key in keys:
		var bucket: Dictionary = averages[key]
		var count = maxi(int(bucket.get("count", 0)), 1)
		points.append(Vector2(
			float(key),
			float(bucket.get("total", 0.0)) / float(count)
		))
	return {"label": label, "color": color, "points": points}


func _trim(records: Array[Dictionary]) -> void:
	while records.size() > MAXIMUM_POINTS:
		records.pop_front()


func _completed_episode_records() -> Array[Dictionary]:
	var completed_numbers: Dictionary = {}
	var result_counts: Dictionary = {}
	for record in episodes:
		var episode_number = int(record.get("episode_number", -1))
		result_counts[episode_number] = int(result_counts.get(episode_number, 0)) + 1
	for episode_number in result_counts:
		var expected_count = maxi(
			int(expected_results_by_episode.get(episode_number, 1)),
			1
		)
		if int(result_counts[episode_number]) >= expected_count:
			completed_numbers[episode_number] = true
	var result: Array[Dictionary] = []
	for record in episodes:
		if completed_numbers.has(int(record.get("episode_number", -1))):
			result.append(record)
	return result


func _completed_episode_numbers() -> Array[int]:
	var result: Array[int] = []
	var result_counts: Dictionary = {}
	for record in episodes:
		var episode_number = int(record.get("episode_number", -1))
		result_counts[episode_number] = int(result_counts.get(episode_number, 0)) + 1
	for episode_number in retained_episode_numbers:
		var expected_count = maxi(
			int(expected_results_by_episode.get(episode_number, 1)),
			1
		)
		if int(result_counts.get(episode_number, 0)) >= expected_count:
			result.append(episode_number)
	return result


func _remove_episode_bucket(episode_number: int) -> void:
	retained_episode_numbers.erase(episode_number)
	expected_results_by_episode.erase(episode_number)
	plot_index_by_episode_number.erase(episode_number)
	for index in range(episodes.size() - 1, -1, -1):
		if int(episodes[index].get("episode_number", -1)) == episode_number:
			episodes.remove_at(index)


func _trim_episode_buckets() -> void:
	# Keep 240 finished graph points. A new episode that is still waiting for slower
	# workers does not evict a finished point or move the graph scale early.
	var completed_numbers = _completed_episode_numbers()
	while completed_numbers.size() > MAXIMUM_POINTS:
		var expired_episode_number = completed_numbers.pop_front()
		_remove_episode_bucket(expired_episode_number)
