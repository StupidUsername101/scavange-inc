class_name RLTrainingMath
extends RefCounted

const MINIMUM_INTERVAL_SECONDS = 0.000001
const MINIMUM_DISCOUNT = 0.000000001

#######################################################
# Shared real-time discount helpers. A configured discount is defined at one reference
# decision interval and converted for the actual transition duration. This keeps the
# planning horizon stable when worker groups use different control rates.
#######################################################

static func finite_float_or(value: Variant, fallback: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback


static func finite_int_or(value: Variant, fallback: int) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)):
		var numeric_value: float = float(value)
		var rounded_value: float = round(numeric_value)
		if is_equal_approx(numeric_value, rounded_value):
			return int(rounded_value)
	return fallback


static func bool_or(value: Variant, fallback: bool) -> bool:
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) != 0
	if value is float and is_finite(float(value)):
		return not is_zero_approx(float(value))
	return fallback


static func discount_for_delta(
	discount_at_reference: float,
	delta_seconds: float,
	reference_interval_seconds: float
) -> float:
	var discount = clampf(finite_float_or(discount_at_reference, 0.0), 0.0, 1.0)
	var delta = maxf(finite_float_or(delta_seconds, 0.0), 0.0)
	var reference = maxf(
		finite_float_or(reference_interval_seconds, MINIMUM_INTERVAL_SECONDS),
		MINIMUM_INTERVAL_SECONDS
	)
	if delta <= 0.0 or is_equal_approx(discount, 1.0):
		return 1.0
	if discount <= 0.0:
		return 0.0
	return exp(log(maxf(discount, MINIMUM_DISCOUNT)) * delta / reference)


static func half_life_seconds(
	discount_at_reference: float,
	reference_interval_seconds: float
) -> float:
	var discount = clampf(finite_float_or(discount_at_reference, 0.0), 0.0, 1.0)
	var reference = maxf(
		finite_float_or(reference_interval_seconds, MINIMUM_INTERVAL_SECONDS),
		MINIMUM_INTERVAL_SECONDS
	)
	if discount <= 0.0:
		return 0.0
	if is_equal_approx(discount, 1.0):
		return INF
	return log(0.5) / log(discount) * reference


static func packed_all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func packed_all_in_range(
	values: PackedFloat64Array,
	minimum: float,
	maximum: float
) -> bool:
	if minimum > maximum:
		return false
	for value: float in values:
		if not is_finite(value) or value < minimum or value > maximum:
			return false
	return true


static func finite_statistics(values: PackedFloat64Array) -> Dictionary:
	var count = 0
	var total = 0.0
	var minimum = INF
	var maximum = -INF
	for value in values:
		if not is_finite(value):
			continue
		count += 1
		total += value
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	if count <= 0:
		return {
			"count": 0,
			"mean": 0.0,
			"standard_deviation": 0.0,
			"minimum": 0.0,
			"maximum": 0.0,
			"non_finite_count": values.size(),
		}
	var mean = total / float(count)
	var variance = 0.0
	for value in values:
		if is_finite(value):
			var difference = value - mean
			variance += difference * difference
	variance /= float(count)
	return {
		"count": count,
		"mean": mean,
		"standard_deviation": sqrt(maxf(variance, 0.0)),
		"minimum": minimum,
		"maximum": maximum,
		"non_finite_count": values.size() - count,
	}


static func finite_transition_statistics(
	transitions: Array[Dictionary],
	field: String,
	fallback: float = NAN
) -> Dictionary:
	var count = 0
	var total = 0.0
	var minimum = INF
	var maximum = -INF
	for transition: Dictionary in transitions:
		var value = finite_float_or(transition.get(field), fallback)
		if not is_finite(value):
			continue
		count += 1
		total += value
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	if count <= 0:
		return {
			"count": 0,
			"mean": 0.0,
			"standard_deviation": 0.0,
			"minimum": 0.0,
			"maximum": 0.0,
			"non_finite_count": transitions.size(),
		}
	var mean = total / float(count)
	var variance = 0.0
	for transition: Dictionary in transitions:
		var value = finite_float_or(transition.get(field), fallback)
		if is_finite(value):
			var difference = value - mean
			variance += difference * difference
	variance /= float(count)
	return {
		"count": count,
		"mean": mean,
		"standard_deviation": sqrt(maxf(variance, 0.0)),
		"minimum": minimum,
		"maximum": maximum,
		"non_finite_count": transitions.size() - count,
	}


static func normalize_in_place(
	values: PackedFloat64Array,
	variance_epsilon: float = 0.00000001
) -> Vector2:
	if values.is_empty():
		return Vector2.ZERO
	var mean = 0.0
	for value: float in values:
		mean += value
	mean /= float(values.size())
	var variance = 0.0
	for value: float in values:
		var difference = value - mean
		variance += difference * difference
	variance /= float(values.size())
	var standard_deviation = sqrt(variance + maxf(variance_epsilon, 0.0))
	for index: int in range(values.size()):
		values[index] = (values[index] - mean) / standard_deviation
	return Vector2(mean, standard_deviation)


static func shuffle_indices_in_place(
	indices: Array[int],
	random: RandomNumberGenerator
) -> void:
	for index: int in range(indices.size() - 1, 0, -1):
		var swap_index = random.randi_range(0, index)
		var temporary = indices[index]
		indices[index] = indices[swap_index]
		indices[swap_index] = temporary


static func generalized_advantage_estimates(
	transitions: Array[Dictionary],
	discount_at_reference: float,
	lambda_at_reference: float,
	reference_interval_seconds: float,
	default_interval_seconds: float,
	value_field: String
) -> Dictionary:
	if transitions.is_empty():
		return {}
	var advantages = PackedFloat64Array()
	var returns = PackedFloat64Array()
	var value_predictions = PackedFloat64Array()
	advantages.resize(transitions.size())
	returns.resize(transitions.size())
	value_predictions.resize(transitions.size())
	# Rollouts are interleaved across workers. One reverse scan needs only the next trace value
	# for each worker, avoiding a temporary index Array per worker at every PPO update.
	var next_advantage_by_worker: Dictionary[int, float] = {}
	for transition_index: int in range(transitions.size() - 1, -1, -1):
		var transition: Dictionary = transitions[transition_index]
		var worker_id = int(transition.get("worker_id", -1))
		var terminated = bool(transition.get("terminated", false))
		var truncated = bool(transition.get("truncated", false))
		var value = float(transition.get(value_field, 0.0))
		var next_value = (
			0.0
			if terminated
			else float(transition.get("next_value", 0.0))
		)
		var delta_seconds = float(transition.get(
			"delta_seconds",
			default_interval_seconds
		))
		var gamma_delta = discount_for_delta(
			discount_at_reference,
			delta_seconds,
			reference_interval_seconds
		)
		var lambda_delta = discount_for_delta(
			lambda_at_reference,
			delta_seconds,
			reference_interval_seconds
		)
		var advantage = (
			float(transition.get("reward", 0.0))
			+ gamma_delta * next_value
			- value
		)
		if (
			not terminated
			and not truncated
			and next_advantage_by_worker.has(worker_id)
		):
			advantage += (
				gamma_delta
				* lambda_delta
				* next_advantage_by_worker[worker_id]
			)
		advantages[transition_index] = advantage
		returns[transition_index] = advantage + value
		value_predictions[transition_index] = value
		if (
			not is_finite(advantage)
			or not is_finite(returns[transition_index])
			or not is_finite(value)
		):
			return {}
		next_advantage_by_worker[worker_id] = advantage
	return {
		"advantages": advantages,
		"returns": returns,
		"value_predictions": value_predictions,
	}


static func bounded_command_diagnostics(
	transitions: Array[Dictionary],
	minimum_command: float,
	maximum_command: float
) -> Dictionary:
	var span = maxf(maximum_command - minimum_command, MINIMUM_INTERVAL_SECONDS)
	var action_count = 0
	for transition in transitions:
		var commands: PackedFloat64Array = transition.get("commands", PackedFloat64Array())
		action_count = maxi(action_count, commands.size())
	if action_count <= 0:
		return {
			"command_count": 0,
			"saturation_fraction_01": 0.0,
			"saturation_fraction_05": 0.0,
			"saturation_fraction_10": 0.0,
			"mean_absolute_command_delta_per_second": 0.0,
			"per_action": [],
		}
	var sums = PackedFloat64Array()
	var squared_sums = PackedFloat64Array()
	var counts = PackedInt32Array()
	var saturated_01 = PackedInt32Array()
	var saturated_05 = PackedInt32Array()
	var saturated_10 = PackedInt32Array()
	sums.resize(action_count)
	squared_sums.resize(action_count)
	counts.resize(action_count)
	saturated_01.resize(action_count)
	saturated_05.resize(action_count)
	saturated_10.resize(action_count)
	var previous_by_worker: Dictionary = {}
	var command_total = 0
	var delta_total = 0.0
	var delta_count = 0
	for transition in transitions:
		var commands: PackedFloat64Array = transition.get("commands", PackedFloat64Array())
		if commands.size() != action_count:
			continue
		if not packed_all_finite(commands):
			continue
		var worker_id = int(transition.get("worker_id", 0))
		var delta_seconds = maxf(
			finite_float_or(transition.get("delta_seconds", 0.05), 0.05),
			MINIMUM_INTERVAL_SECONDS
		)
		var previous: PackedFloat64Array = previous_by_worker.get(worker_id, PackedFloat64Array())
		for index in range(action_count):
			var command = clampf(commands[index], minimum_command, maximum_command)
			var distance_to_bound = minf(command - minimum_command, maximum_command - command)
			sums[index] += command
			squared_sums[index] += command * command
			counts[index] += 1
			command_total += 1
			if distance_to_bound <= span * 0.01:
				saturated_01[index] += 1
			if distance_to_bound <= span * 0.05:
				saturated_05[index] += 1
			if distance_to_bound <= span * 0.10:
				saturated_10[index] += 1
			if previous.size() == action_count:
				delta_total += absf(command - previous[index]) / delta_seconds
				delta_count += 1
		# Rollout command arrays are immutable snapshots, so retaining their shared reference is safe
		# and avoids cloning one packed array for every transition inspected by this diagnostic.
		previous_by_worker[worker_id] = commands
	var per_action: Array[Dictionary] = []
	var total_saturated_01 = 0
	var total_saturated_05 = 0
	var total_saturated_10 = 0
	for index in range(action_count):
		var count = maxi(counts[index], 1)
		var mean = sums[index] / float(count)
		var variance = maxf(squared_sums[index] / float(count) - mean * mean, 0.0)
		per_action.append({
			"index": index,
			"mean": mean,
			"standard_deviation": sqrt(variance),
			"saturation_fraction_01": float(saturated_01[index]) / float(count),
			"saturation_fraction_05": float(saturated_05[index]) / float(count),
			"saturation_fraction_10": float(saturated_10[index]) / float(count),
		})
		total_saturated_01 += saturated_01[index]
		total_saturated_05 += saturated_05[index]
		total_saturated_10 += saturated_10[index]
	return {
		"command_count": command_total,
		"saturation_fraction_01": float(total_saturated_01) / float(maxi(command_total, 1)),
		"saturation_fraction_05": float(total_saturated_05) / float(maxi(command_total, 1)),
		"saturation_fraction_10": float(total_saturated_10) / float(maxi(command_total, 1)),
		"mean_absolute_command_delta_per_second": delta_total / float(maxi(delta_count, 1)),
		"per_action": per_action,
	}


static func explained_variance(
	targets: PackedFloat64Array,
	predictions: PackedFloat64Array
) -> float:
	if targets.is_empty() or targets.size() != predictions.size():
		return 0.0
	var target_mean = 0.0
	var error_mean = 0.0
	for index in range(targets.size()):
		if not is_finite(targets[index]) or not is_finite(predictions[index]):
			return 0.0
		target_mean += targets[index]
		error_mean += targets[index] - predictions[index]
	target_mean /= float(targets.size())
	error_mean /= float(targets.size())
	var target_variance = 0.0
	var error_variance = 0.0
	for index in range(targets.size()):
		var target_difference = targets[index] - target_mean
		var error_difference = (targets[index] - predictions[index]) - error_mean
		target_variance += target_difference * target_difference
		error_variance += error_difference * error_difference
	target_variance /= float(targets.size())
	error_variance /= float(targets.size())
	if target_variance <= 0.000000000001:
		return 0.0
	return 1.0 - error_variance / target_variance
