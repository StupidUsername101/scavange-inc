@tool
class_name AcousticPathModifier
extends Resource

const MIN_FILTER_HZ := 20.0
const MAX_FILTER_HZ := 20000.0
const MIN_VOLUME_DB := -80.0
const MAX_VOLUME_DB := 18.0
const MAX_EXTRA_DELAY_SECONDS := 4.0

## Composable, server-side description of how one section of an acoustic path changes sound.
## Band gains are linear amplitude multipliers ordered low, mid, high. Passive materials should
## normally stay at or below one, but a small authored boost remains possible for resonant paths.

@export var modifier_id: StringName = &""
@export var band_gain := Vector3.ONE
@export_range(-80.0, 18.0, 0.1) var volume_db := 0.0
@export_range(0.0, 4.0, 0.001, "or_greater") var extra_delay_seconds := 0.0
@export_range(20.0, 20000.0, 1.0, "or_greater") var lowpass_hz := MAX_FILTER_HZ
@export_range(20.0, 20000.0, 1.0, "or_greater") var highpass_hz := MIN_FILTER_HZ
@export_range(0.0, 1.0, 0.01) var resonance := 0.0
@export_range(0.0, 1.0, 0.01) var reverb_send := 0.0


func sanitized_copy() -> AcousticPathModifier:
	var result := AcousticPathModifier.new()
	result.modifier_id = modifier_id
	result.band_gain = sanitized_band_gain()
	result.volume_db = clampf(
		SafeVariant.finite_float_or(volume_db, 0.0),
		MIN_VOLUME_DB,
		MAX_VOLUME_DB
	)
	result.extra_delay_seconds = clampf(
		SafeVariant.finite_float_or(extra_delay_seconds, 0.0),
		0.0,
		MAX_EXTRA_DELAY_SECONDS
	)
	result.lowpass_hz = clampf(
		SafeVariant.finite_float_or(lowpass_hz, MAX_FILTER_HZ),
		MIN_FILTER_HZ,
		MAX_FILTER_HZ
	)
	result.highpass_hz = clampf(
		SafeVariant.finite_float_or(highpass_hz, MIN_FILTER_HZ),
		MIN_FILTER_HZ,
		result.lowpass_hz
	)
	result.resonance = clampf(
		SafeVariant.finite_float_or(resonance, 0.0),
		0.0,
		1.0
	)
	result.reverb_send = clampf(
		SafeVariant.finite_float_or(reverb_send, 0.0),
		0.0,
		1.0
	)
	return result


func sanitized_band_gain() -> Vector3:
	if not band_gain.is_finite():
		return Vector3.ONE
	return Vector3(
		clampf(band_gain.x, 0.0, 4.0),
		clampf(band_gain.y, 0.0, 4.0),
		clampf(band_gain.z, 0.0, 4.0)
	)


func combined_with(other: AcousticPathModifier) -> AcousticPathModifier:
	var left := sanitized_copy()
	if other == null:
		return left
	var right := other.sanitized_copy()
	var result := AcousticPathModifier.new()
	result.modifier_id = _combined_id(left.modifier_id, right.modifier_id)
	result.band_gain = left.band_gain * right.band_gain
	result.volume_db = clampf(
		left.volume_db + right.volume_db,
		MIN_VOLUME_DB,
		MAX_VOLUME_DB
	)
	result.extra_delay_seconds = minf(
		left.extra_delay_seconds + right.extra_delay_seconds,
		MAX_EXTRA_DELAY_SECONDS
	)
	result.lowpass_hz = minf(left.lowpass_hz, right.lowpass_hz)
	result.highpass_hz = minf(
		maxf(left.highpass_hz, right.highpass_hz),
		result.lowpass_hz
	)
	result.resonance = maxf(left.resonance, right.resonance)
	result.reverb_send = 1.0 - (
		(1.0 - left.reverb_send) * (1.0 - right.reverb_send)
	)
	return result


static func identity() -> AcousticPathModifier:
	return AcousticPathModifier.new()


static func _combined_id(left: StringName, right: StringName) -> StringName:
	if left.is_empty():
		return right
	if right.is_empty() or left == right:
		return left
	return StringName("%s+%s" % [left, right])
