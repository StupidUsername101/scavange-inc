class_name DronePPOFeatureAudit
extends RefCounted

const CONSTANT_STANDARD_DEVIATION: float = 0.000001
const HIGH_CORRELATION_THRESHOLD: float = 0.995
const RANK_RELATIVE_TOLERANCE: float = 0.000001

#######################################################
# Audits the actual normalized PPO rollout. Exact empirical dependence cannot be established
# before data exists, so this report identifies constant inputs, pairwise correlation and the
# numerical rank of the varying-feature correlation matrix at a low diagnostic cadence.
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
		"max_absolute_correlation": 0.0,
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

	var correlation_matrix: Array = []
	var high_pairs: Array[Dictionary] = []
	var max_absolute_correlation: float = 0.0
	for row_position: int in range(varying_indices.size()):
		var row: Array[float] = []
		row.resize(varying_indices.size())
		row.fill(0.0)
		correlation_matrix.append(row)

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
			(correlation_matrix[row_position] as Array)[column_position] = correlation
			(correlation_matrix[column_position] as Array)[row_position] = correlation
			if row_position == column_position:
				continue
			var absolute_correlation: float = absf(correlation)
			max_absolute_correlation = maxf(
				max_absolute_correlation,
				absolute_correlation
			)
			if absolute_correlation >= HIGH_CORRELATION_THRESHOLD:
				high_pairs.append({
					"left": feature_names[left_index],
					"right": feature_names[right_index],
					"correlation": correlation,
				})

	return {
		"sample_count": sample_count,
		"feature_count": feature_count,
		"varying_feature_count": varying_indices.size(),
		"effective_rank": _matrix_rank(correlation_matrix),
		"max_absolute_correlation": max_absolute_correlation,
		"high_correlation_pairs": high_pairs,
		"constant_features": constant_features,
	}


static func status_text(report: Dictionary) -> String:
	if int(report.get("sample_count", 0)) < 2:
		return "PPO is waiting for enough flight data to check its sensor inputs."
	var high_pairs: Array = report.get("high_correlation_pairs", [])
	var constants: Array = report.get("constant_features", [])
	var result := (
		"Changing sensor values: %d of %d\n"
		+ "Independent information groups: %d\n"
		+ "Very similar sensor pairs: %d\n"
		+ "Sensors that did not change: %d"
	) % [
		int(report.get("varying_feature_count", 0)),
		int(report.get("feature_count", 0)),
		int(report.get("effective_rank", 0)),
		high_pairs.size(),
		constants.size(),
	]
	if high_pairs.is_empty():
		return result
	var pair_labels: PackedStringArray = PackedStringArray()
	for pair_index: int in range(mini(high_pairs.size(), 3)):
		var pair: Dictionary = high_pairs[pair_index]
		pair_labels.append("%s / %s" % [pair.get("left", "?"), pair.get("right", "?")])
	return "%s\nMost similar inputs: %s" % [result, ", ".join(pair_labels)]


static func _matrix_rank(source: Array) -> int:
	var size: int = source.size()
	if size <= 0:
		return 0
	var matrix: Array = []
	for source_row: Variant in source:
		matrix.append((source_row as Array).duplicate())
	var rank: int = 0
	var column: int = 0
	while rank < size and column < size:
		var pivot_row: int = rank
		var pivot_value: float = absf(float((matrix[pivot_row] as Array)[column]))
		for candidate_row: int in range(rank + 1, size):
			var candidate_value: float = absf(float(
				(matrix[candidate_row] as Array)[column]
			))
			if candidate_value > pivot_value:
				pivot_value = candidate_value
				pivot_row = candidate_row
		if pivot_value <= RANK_RELATIVE_TOLERANCE:
			column += 1
			continue
		if pivot_row != rank:
			var temporary: Variant = matrix[rank]
			matrix[rank] = matrix[pivot_row]
			matrix[pivot_row] = temporary
		var pivot: float = float((matrix[rank] as Array)[column])
		for candidate_row: int in range(rank + 1, size):
			var factor: float = float(
				(matrix[candidate_row] as Array)[column]
			) / pivot
			for trailing_column: int in range(column, size):
				(matrix[candidate_row] as Array)[trailing_column] = (
					float((matrix[candidate_row] as Array)[trailing_column])
					- factor * float((matrix[rank] as Array)[trailing_column])
				)
		rank += 1
		column += 1
	return rank
