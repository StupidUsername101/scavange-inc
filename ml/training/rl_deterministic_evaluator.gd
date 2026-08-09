class_name RLDeterministicEvaluator
extends RefCounted

#######################################################
# Pure, body-agnostic evaluator aggregation and promotion gate. The simulation rooms own how
# frozen candidates are run; this class owns deterministic records, robust aggregates and the
# rule that a noisy training outlier cannot become the designated best checkpoint by itself.
#######################################################

const DEFAULT_PROMOTION_MARGIN = 0.001
const DEFAULT_MAXIMUM_CRASH_RATE_REGRESSION = 0.0
const LOWER_PERCENTILE_FRACTION = 0.10
const BOOTSTRAP_SAMPLE_COUNT = 512
const BOOTSTRAP_SEED = 173205080


static func candidate_hash(checkpoint: Dictionary) -> String:
	return JSON.stringify(checkpoint, "", true, true).sha256_text()


static func aggregate(records: Array[Dictionary]) -> Dictionary:
	var rewards: Array[float] = []
	var successes = 0
	var crashes = 0
	var terminations = 0
	var truncations = 0
	var seeds: Array[int] = []
	for record in records:
		var reward: float = RLTrainingMath.finite_float_or(record.get("episode_return", NAN), NAN)
		if not is_finite(reward):
			continue
		rewards.append(reward)
		if RLTrainingMath.bool_or(record.get("success", false), false):
			successes += 1
		if RLTrainingMath.bool_or(record.get("crashed", false), false):
			crashes += 1
		if RLTrainingMath.bool_or(record.get("terminated", false), false):
			terminations += 1
		if RLTrainingMath.bool_or(record.get("truncated", false), false):
			truncations += 1
		seeds.append(RLTrainingMath.finite_int_or(record.get("seed", 0), 0))
	if rewards.is_empty():
		return {}
	rewards.sort()
	var count = rewards.size()
	var mean = _mean(rewards)
	var standard_deviation = _standard_deviation(rewards, mean)
	var selection_interval: Vector2 = _stratified_bootstrap_iqm_interval(records)
	return {
		"record_count": count,
		"success_rate": float(successes) / float(count),
		"mean_return": mean,
		"median_return": _percentile(rewards, 0.5),
		"interquartile_mean_return": _interquartile_mean(rewards),
		"lower_percentile_return": _percentile(rewards, LOWER_PERCENTILE_FRACTION),
		"return_standard_deviation": standard_deviation,
		# The fixed suite is stratified by scenario, not an IID sample. Report uncertainty for
		# the actual selection statistic by resampling within each scenario instead of labeling
		# a pooled normal mean interval as a classical 95% confidence interval.
		"selection_score_confidence_low": selection_interval.x,
		"selection_score_confidence_high": selection_interval.y,
		"confidence_method": "stratified_bootstrap_iqm_95_v2",
		"crash_rate": float(crashes) / float(count),
		"termination_rate": float(terminations) / float(count),
		"truncation_rate": float(truncations) / float(count),
		"seeds": seeds,
		"records": records.duplicate(true),
		"selection_statistic": "interquartile_mean_return",
		"selection_score": _interquartile_mean(rewards),
	}


static func _stratified_bootstrap_iqm_interval(records: Array[Dictionary]) -> Vector2:
	var rewards_by_scenario: Dictionary = {}
	for record: Dictionary in records:
		var reward: float = RLTrainingMath.finite_float_or(record.get("episode_return", NAN), NAN)
		if not is_finite(reward):
			continue
		var scenario_id: String = str(record.get("scenario_id", "baseline"))
		var values: Array = rewards_by_scenario.get(scenario_id, [])
		values.append(reward)
		rewards_by_scenario[scenario_id] = values
	if rewards_by_scenario.is_empty():
		return Vector2.ZERO
	var scenario_ids: Array = rewards_by_scenario.keys()
	scenario_ids.sort()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = BOOTSTRAP_SEED
	var estimates: Array[float] = []
	for _sample_index in range(BOOTSTRAP_SAMPLE_COUNT):
		var sampled_rewards: Array[float] = []
		for scenario_value: Variant in scenario_ids:
			var source: Array = rewards_by_scenario.get(str(scenario_value), [])
			if source.is_empty():
				continue
			for _value_index in range(source.size()):
				var chosen_index: int = rng.randi_range(0, source.size() - 1)
				sampled_rewards.append(float(source[chosen_index]))
		if sampled_rewards.is_empty():
			continue
		sampled_rewards.sort()
		estimates.append(_interquartile_mean(sampled_rewards))
	if estimates.is_empty():
		var fallback_rewards: Array[float] = []
		for record: Dictionary in records:
			var fallback_reward: float = RLTrainingMath.finite_float_or(
				record.get("episode_return", NAN),
				NAN
			)
			if is_finite(fallback_reward):
				fallback_rewards.append(fallback_reward)
		fallback_rewards.sort()
		var fallback_value: float = _interquartile_mean(fallback_rewards)
		return Vector2(fallback_value, fallback_value)
	estimates.sort()
	return Vector2(
		_percentile(estimates, 0.025),
		_percentile(estimates, 0.975)
	)


static func promotion_decision(
	candidate_summary: Dictionary,
	current_best_summary: Dictionary = {},
	minimum_margin: float = DEFAULT_PROMOTION_MARGIN,
	maximum_crash_rate_regression: float = DEFAULT_MAXIMUM_CRASH_RATE_REGRESSION
) -> Dictionary:
	if candidate_summary.is_empty():
		return {"promote": false, "reason": "missing_candidate_evaluation"}
	if not RLTrainingMath.bool_or(candidate_summary.get("deterministic", false), false):
		return {"promote": false, "reason": "evaluation_not_deterministic"}
	if not RLTrainingMath.bool_or(candidate_summary.get("suite_complete", false), false):
		return {"promote": false, "reason": "incomplete_evaluation_suite"}
	var candidate_score: float = RLTrainingMath.finite_float_or(
		candidate_summary.get("selection_score", -INF),
		-INF
	)
	if not is_finite(candidate_score):
		return {"promote": false, "reason": "non_finite_candidate_score"}
	var candidate_crash_rate: float = RLTrainingMath.finite_float_or(
		candidate_summary.get("crash_rate", NAN),
		NAN
	)
	if not _is_probability(candidate_crash_rate):
		return {"promote": false, "reason": "invalid_candidate_crash_rate"}
	if current_best_summary.is_empty():
		return {"promote": true, "reason": "first_evaluated_candidate"}
	var candidate_suite_hash: String = str(candidate_summary.get("suite_hash", ""))
	var best_suite_hash: String = str(current_best_summary.get("suite_hash", ""))
	if (
		candidate_suite_hash.is_empty()
		or best_suite_hash.is_empty()
		or candidate_suite_hash != best_suite_hash
	):
		return {"promote": false, "reason": "evaluation_suite_mismatch"}
	var candidate_contract_hash: String = str(candidate_summary.get("evaluation_contract_hash", ""))
	var best_contract_hash: String = str(current_best_summary.get("evaluation_contract_hash", ""))
	if (
		candidate_contract_hash.is_empty()
		or best_contract_hash.is_empty()
		or candidate_contract_hash != best_contract_hash
	):
		return {"promote": false, "reason": "evaluation_contract_mismatch"}
	var current_score: float = RLTrainingMath.finite_float_or(
		current_best_summary.get("selection_score", NAN),
		NAN
	)
	var current_crash_rate: float = RLTrainingMath.finite_float_or(
		current_best_summary.get("crash_rate", NAN),
		NAN
	)
	if not is_finite(current_score) or not _is_probability(current_crash_rate):
		return {"promote": false, "reason": "invalid_current_best_evaluation"}
	var safe_crash_regression: float = maxf(
		maximum_crash_rate_regression if is_finite(maximum_crash_rate_regression) else DEFAULT_MAXIMUM_CRASH_RATE_REGRESSION,
		0.0
	)
	var safe_margin: float = maxf(
		minimum_margin if is_finite(minimum_margin) else DEFAULT_PROMOTION_MARGIN,
		0.0
	)
	if candidate_crash_rate > current_crash_rate + safe_crash_regression:
		return {"promote": false, "reason": "safety_regression"}
	if candidate_score < current_score + safe_margin:
		return {"promote": false, "reason": "insufficient_margin"}
	return {"promote": true, "reason": "robust_score_improved"}


static func _is_probability(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 1.0


static func _mean(values: Array[float]) -> float:
	var total = 0.0
	for value in values:
		total += value
	return total / float(maxi(values.size(), 1))


static func _standard_deviation(values: Array[float], mean: float) -> float:
	var total = 0.0
	for value in values:
		var difference = value - mean
		total += difference * difference
	return sqrt(maxf(total / float(maxi(values.size(), 1)), 0.0))


static func _percentile(sorted_values: Array[float], fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var position = clampf(fraction, 0.0, 1.0) * float(sorted_values.size() - 1)
	var lower = floori(position)
	var upper = ceili(position)
	if lower == upper:
		return sorted_values[lower]
	return lerpf(sorted_values[lower], sorted_values[upper], position - float(lower))


static func _interquartile_mean(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	if sorted_values.size() < 4:
		return _mean(sorted_values)
	var trim = floori(float(sorted_values.size()) * 0.25)
	var first = clampi(trim, 0, sorted_values.size() - 1)
	var end = clampi(sorted_values.size() - trim, first + 1, sorted_values.size())
	var total = 0.0
	for index in range(first, end):
		total += sorted_values[index]
	return total / float(maxi(end - first, 1))
