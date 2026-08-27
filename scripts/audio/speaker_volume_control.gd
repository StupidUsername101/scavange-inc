@tool
class_name SpeakerVolumeControl
extends RefCounted

## Shared control response for every world speaker. The original response is preserved up to
## the default setting; the extra headroom is introduced smoothly only above that point.

const MIN_CONTROL_VOLUME_DB := -30.0
const LEGACY_MAX_CONTROL_VOLUME_DB := 6.0
const MUTED_CONTROL_VOLUME_DB := -80.0
const CONTROL_VOLUME_CURVE := 0.62
const DEFAULT_CONTROL_VOLUME_DB := 0.0
const DEFAULT_CONTROL_VOLUME_RATIO := 0.745226539405129
const MAX_AMPLITUDE_MULTIPLIER := 1.5
const MAX_GAIN_EXTENSION_DB := 3.521825181113625
const MAX_CONTROL_VOLUME_DB := (
	LEGACY_MAX_CONTROL_VOLUME_DB + MAX_GAIN_EXTENSION_DB
)
const INVERSE_SOLVE_ITERATIONS := 16


static func decibels_from_ratio(value: float) -> float:
	var ratio := clampf(value, 0.0, 1.0)
	if is_zero_approx(ratio):
		return MUTED_CONTROL_VOLUME_DB
	var volume_db := lerpf(
		MIN_CONTROL_VOLUME_DB,
		LEGACY_MAX_CONTROL_VOLUME_DB,
		pow(ratio, CONTROL_VOLUME_CURVE)
	)
	if ratio <= DEFAULT_CONTROL_VOLUME_RATIO:
		return volume_db
	var extension_weight := inverse_lerp(
		DEFAULT_CONTROL_VOLUME_RATIO,
		1.0,
		ratio
	)
	# Smoothstep keeps the preserved response free of a slope discontinuity at the default.
	extension_weight *= extension_weight * (3.0 - 2.0 * extension_weight)
	return volume_db + MAX_GAIN_EXTENSION_DB * extension_weight


static func ratio_from_decibels(value_db: float) -> float:
	if value_db <= MUTED_CONTROL_VOLUME_DB + 0.01:
		return 0.0
	var safe_db := clampf(
		value_db,
		MIN_CONTROL_VOLUME_DB,
		MAX_CONTROL_VOLUME_DB
	)
	if safe_db <= DEFAULT_CONTROL_VOLUME_DB:
		var normalized := inverse_lerp(
			MIN_CONTROL_VOLUME_DB,
			LEGACY_MAX_CONTROL_VOLUME_DB,
			safe_db
		)
		return pow(clampf(normalized, 0.0, 1.0), 1.0 / CONTROL_VOLUME_CURVE)

	# The smooth upper extension has no useful closed-form inverse. A fixed bounded search is
	# allocation-free, monotonic, and substantially more precise than the UI/network payload.
	var lower := DEFAULT_CONTROL_VOLUME_RATIO
	var upper := 1.0
	var iteration := 0
	while iteration < INVERSE_SOLVE_ITERATIONS:
		var candidate := (lower + upper) * 0.5
		if decibels_from_ratio(candidate) < safe_db:
			lower = candidate
		else:
			upper = candidate
		iteration += 1
	return (lower + upper) * 0.5
