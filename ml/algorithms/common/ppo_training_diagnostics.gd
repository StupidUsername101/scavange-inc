class_name PPOTrainingDiagnostics
extends RefCounted

#######################################################
# Pure PPO diagnostics shared across body trainers. These helpers inspect immutable rollout/policy
# snapshots only; optimizer state and update ordering stay owned by each trainer.
#######################################################


static func policy_divergence_metrics(
	source_rollout: Array[Dictionary],
	log_probability_function: Callable,
	clip_range: float,
	maximum_samples: int = 64
) -> Dictionary:
	if source_rollout.is_empty() or not log_probability_function.is_valid():
		return _invalid_divergence()
	var count: int = mini(source_rollout.size(), maxi(maximum_samples, 1))
	var maximum_error: float = 0.0
	var kl_total: float = 0.0
	var clipped_count: int = 0
	for index: int in range(count):
		var transition: Dictionary = source_rollout[index]
		var current_log_probability: float = RLTrainingMath.finite_float_or(
			log_probability_function.call(
				transition.get("actor_input", PackedFloat64Array()),
				transition.get("latent_action", PackedFloat64Array())
			),
			NAN
		)
		var old_log_probability: float = RLTrainingMath.finite_float_or(
			transition.get("old_log_probability", NAN),
			NAN
		)
		if not is_finite(current_log_probability) or not is_finite(old_log_probability):
			return _invalid_divergence()
		var error: float = absf(current_log_probability - old_log_probability)
		maximum_error = maxf(maximum_error, error)
		kl_total += old_log_probability - current_log_probability
		var ratio: float = exp(clampf(
			current_log_probability - old_log_probability,
			-20.0,
			20.0
		))
		if absf(ratio - 1.0) > clip_range:
			clipped_count += 1
	return {
		"maximum_log_probability_error": maximum_error,
		"approximate_kl": kl_total / float(count),
		"clip_fraction": float(clipped_count) / float(count),
	}


static func parameter_delta_rms(
	actor_parameters_before: PackedFloat64Array,
	actor_parameters_after: PackedFloat64Array,
	log_standard_deviation_before: PackedFloat64Array,
	log_standard_deviation_after: PackedFloat64Array
) -> float:
	var sum_squared: float = 0.0
	var count: int = 0
	var actor_count: int = mini(actor_parameters_before.size(), actor_parameters_after.size())
	for index: int in range(actor_count):
		var difference: float = actor_parameters_after[index] - actor_parameters_before[index]
		sum_squared += difference * difference
		count += 1
	var deviation_count: int = mini(
		log_standard_deviation_before.size(),
		log_standard_deviation_after.size()
	)
	for index: int in range(deviation_count):
		var difference: float = (
			log_standard_deviation_after[index]
			- log_standard_deviation_before[index]
		)
		sum_squared += difference * difference
		count += 1
	return sqrt(sum_squared / float(maxi(count, 1)))


static func _invalid_divergence() -> Dictionary:
	return {
		"maximum_log_probability_error": INF,
		"approximate_kl": INF,
		"clip_fraction": 1.0,
	}
