class_name TurretPPOFeatureAudit
extends RefCounted

const CONSTANT_STANDARD_DEVIATION: float = 0.000001
const HIGH_CORRELATION_THRESHOLD: float = 0.995
const RANK_RELATIVE_TOLERANCE: float = 0.000001
const MAXIMUM_REPORTED_CORRELATION_PAIRS = 16

#######################################################
# Audits the actual normalized turret PPO rollout. Exact empirical dependence cannot be established
# before data exists, so this report identifies constant inputs, pairwise correlation and the
# numerical rank of the centered, standardized varying-feature samples at a low cadence.
#######################################################


static func analyze_rollout(
	rollout: Array[Dictionary],
	feature_names: Array[String]
) -> Dictionary:
	var samples: Array = []
	for transition: Dictionary in rollout:
		var input_value: Variant = transition.get("actor_input")
		if not (input_value is PackedFloat64Array):
			continue
		var packed_input: PackedFloat64Array = input_value
		if packed_input.size() == feature_names.size():
			samples.append(packed_input)
	return analyze_samples(samples, feature_names)


static func analyze_samples(
	samples: Array,
	feature_names: Array[String]
) -> Dictionary:
	var sample_count: int = samples.size()
	var feature_count: int = feature_names.size()
	var empty_report: Dictionary = {
		"sample_count": sample_count,
		"feature_count": feature_count,
		"varying_feature_count": 0,
		"effective_rank": 0,
		"maximum_observable_rank": maxi(mini(sample_count - 1, feature_count), 0),
		"max_absolute_correlation": 0.0,
		"high_correlation_pair_count": 0,
		"high_correlation_pairs": [],
		"constant_features": [],
	}
	if sample_count < 2 or feature_count <= 0:
		return empty_report

	var means: PackedFloat64Array = PackedFloat64Array()
	means.resize(feature_count)
	means.fill(0.0)
	for raw_sample: Variant in samples:
		var sample: PackedFloat64Array = raw_sample
		for feature_index: int in range(feature_count):
			means[feature_index] += sample[feature_index]
	for feature_index: int in range(feature_count):
		means[feature_index] /= float(sample_count)

	var standard_deviations: PackedFloat64Array = PackedFloat64Array()
	standard_deviations.resize(feature_count)
	standard_deviations.fill(0.0)
	for raw_sample: Variant in samples:
		var sample: PackedFloat64Array = raw_sample
		for feature_index: int in range(feature_count):
			var difference: float = sample[feature_index] - means[feature_index]
			standard_deviations[feature_index] += difference * difference
	for feature_index: int in range(feature_count):
		standard_deviations[feature_index] = sqrt(
			standard_deviations[feature_index] / float(sample_count - 1)
		)

	var varying_indices: Array[int] = []
	var constant_features: Array[String] = []
	for feature_index: int in range(feature_count):
		if standard_deviations[feature_index] <= CONSTANT_STANDARD_DEVIATION:
			constant_features.append(feature_names[feature_index])
		else:
			varying_indices.append(feature_index)

	var high_pairs: Array[Dictionary] = []
	var high_pair_count = 0
	var max_absolute_correlation: float = 0.0
	for row_position: int in range(varying_indices.size()):
		var left_index: int = varying_indices[row_position]
		for column_position: int in range(row_position, varying_indices.size()):
			var right_index: int = varying_indices[column_position]
			var covariance: float = 0.0
			for raw_sample: Variant in samples:
				var sample: PackedFloat64Array = raw_sample
				covariance += (
					(sample[left_index] - means[left_index])
					* (sample[right_index] - means[right_index])
				)
			covariance /= float(sample_count - 1)
			var correlation: float = covariance / (
				standard_deviations[left_index]
				* standard_deviations[right_index]
			)
			correlation = clampf(correlation, -1.0, 1.0)
			if row_position == column_position:
				continue
			var absolute_correlation: float = absf(correlation)
			max_absolute_correlation = maxf(
				max_absolute_correlation,
				absolute_correlation
			)
			if absolute_correlation >= HIGH_CORRELATION_THRESHOLD:
				high_pair_count += 1
				_record_strong_pair(high_pairs, {
					"left": feature_names[left_index],
					"right": feature_names[right_index],
					"correlation": correlation,
				})

	high_pairs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return absf(float(left.get("correlation", 0.0))) > absf(float(right.get("correlation", 0.0)))
	)
	return {
		"sample_count": sample_count,
		"feature_count": feature_count,
		"varying_feature_count": varying_indices.size(),
		"effective_rank": _standardized_sample_rank(
			samples,
			means,
			standard_deviations,
			varying_indices
		),
		"maximum_observable_rank": mini(varying_indices.size(), sample_count - 1),
		"max_absolute_correlation": max_absolute_correlation,
		"high_correlation_pair_count": high_pair_count,
		"high_correlation_pairs": high_pairs,
		"constant_features": constant_features,
	}


static func status_text(report: Dictionary) -> String:
	if int(report.get("sample_count", 0)) < 2:
		return "Turret PPO is waiting for enough movement data to check its body inputs."
	var high_pairs: Array = report.get("high_correlation_pairs", [])
	var high_pair_count = int(report.get("high_correlation_pair_count", high_pairs.size()))
	var constants: Array = report.get("constant_features", [])
	var result = (
		"Audit samples: %d\n"
		+ "Changing sensor values: %d of %d\n"
		+ "Numerical rank: %d / %d observable\n"
		+ "Maximum |Pearson r|: %.5f\n"
		+ "Very similar sensor pairs: %d\n"
		+ "Sensors that did not change: %d"
	) % [
		int(report.get("sample_count", 0)),
		int(report.get("varying_feature_count", 0)),
		int(report.get("feature_count", 0)),
		int(report.get("effective_rank", 0)),
		int(report.get("maximum_observable_rank", 0)),
		float(report.get("max_absolute_correlation", 0.0)),
		high_pair_count,
		constants.size(),
	]
	var details: PackedStringArray = PackedStringArray()
	if not high_pairs.is_empty():
		var pair_labels: PackedStringArray = PackedStringArray()
		for pair_index: int in range(mini(high_pairs.size(), 3)):
			var pair: Dictionary = high_pairs[pair_index]
			pair_labels.append("%s / %s" % [pair.get("left", "?"), pair.get("right", "?")])
		details.append("Most similar inputs: %s" % ", ".join(pair_labels))
	if not constants.is_empty():
		var constant_labels: PackedStringArray = PackedStringArray()
		for constant_index: int in range(mini(constants.size(), 3)):
			constant_labels.append(str(constants[constant_index]))
		details.append("Constant in this rollout: %s" % ", ".join(constant_labels))
	return result if details.is_empty() else "%s\n%s" % [result, "\n".join(details)]


static func _record_strong_pair(
	pairs: Array[Dictionary],
	candidate: Dictionary
) -> void:
	if pairs.size() < MAXIMUM_REPORTED_CORRELATION_PAIRS:
		pairs.append(candidate)
		return
	var weakest_index = 0
	var weakest_strength = absf(float(pairs[0].get("correlation", 0.0)))
	for pair_index: int in range(1, pairs.size()):
		var strength = absf(float(pairs[pair_index].get("correlation", 0.0)))
		if strength < weakest_strength:
			weakest_strength = strength
			weakest_index = pair_index
	if absf(float(candidate.get("correlation", 0.0))) > weakest_strength:
		pairs[weakest_index] = candidate


static func _standardized_sample_rank(
	samples: Array,
	means: PackedFloat64Array,
	standard_deviations: PackedFloat64Array,
	varying_indices: Array[int]
) -> int:
	if samples.size() < 2 or varying_indices.is_empty():
		return 0
	var basis_vectors: Array[PackedFloat64Array] = []
	var maximum_rank = mini(varying_indices.size(), samples.size() - 1)
	for raw_sample: Variant in samples:
		var sample: PackedFloat64Array = raw_sample
		var vector = PackedFloat64Array()
		vector.resize(varying_indices.size())
		var original_norm_squared = 0.0
		for position: int in range(varying_indices.size()):
			var feature_index: int = varying_indices[position]
			var value = (
				(sample[feature_index] - means[feature_index])
				/ standard_deviations[feature_index]
			)
			vector[position] = value
			original_norm_squared += value * value
		if original_norm_squared <= 0.0:
			continue
		# Modified Gram-Schmidt with one re-orthogonalization pass is stable enough for this
		# low-cadence diagnostic and avoids eliminating a full square feature matrix in GDScript.
		for _pass_index: int in range(2):
			for basis: PackedFloat64Array in basis_vectors:
				var projection = 0.0
				for position: int in range(vector.size()):
					projection += vector[position] * basis[position]
				if absf(projection) <= 0.0:
					continue
				for position: int in range(vector.size()):
					vector[position] -= projection * basis[position]
		var residual_norm_squared = 0.0
		for value: float in vector:
			residual_norm_squared += value * value
		if (
			residual_norm_squared
			<= original_norm_squared * RANK_RELATIVE_TOLERANCE * RANK_RELATIVE_TOLERANCE
		):
			continue
		var inverse_norm = 1.0 / sqrt(residual_norm_squared)
		for position: int in range(vector.size()):
			vector[position] *= inverse_norm
		basis_vectors.append(vector)
		if basis_vectors.size() >= maximum_rank:
			break
	return basis_vectors.size()
