class_name MLModelInputVectorBuilder
extends RefCounted

#######################################################
# Shared tensor assembler. Algorithms provide their stable task/environment prefix and the
# accepted body manifest appends the topology-dependent body block. The algorithm never needs to
# know which attachment produced a body feature or how many attachments exist.
#######################################################


static func build(
	manifest: MLBodyInterfaceManifest,
	runtime_states_by_slot: Dictionary,
	host_state: Dictionary,
	extra_features: PackedFloat64Array
) -> PackedFloat64Array:
	if manifest == null or not manifest.finalized:
		return PackedFloat64Array()
	var body_features: PackedFloat64Array = manifest.encode_body_observation(
		runtime_states_by_slot,
		host_state
	)
	return combine_finalized(manifest, body_features, extra_features)


static func combine_finalized(
	manifest: MLBodyInterfaceManifest,
	body_features: PackedFloat64Array,
	extra_features: PackedFloat64Array
) -> PackedFloat64Array:
	if manifest == null or not manifest.finalized:
		return PackedFloat64Array()
	if body_features.size() != manifest.observation_count():
		return PackedFloat64Array()
	for value: float in body_features:
		if not is_finite(value) or value < -1.000001 or value > 1.000001:
			return PackedFloat64Array()
	for value: float in extra_features:
		if not is_finite(value) or value < -1.000001 or value > 1.000001:
			return PackedFloat64Array()
	var result: PackedFloat64Array = extra_features.duplicate()
	result.append_array(body_features)
	return result


static func feature_names(
	manifest: MLBodyInterfaceManifest,
	extra_feature_names: Array[String]
) -> Array[String]:
	if manifest == null or not manifest.finalized:
		return []
	var result: Array[String] = extra_feature_names.duplicate()
	result.append_array(manifest.observation_names())
	return result
