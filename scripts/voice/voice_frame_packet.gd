class_name VoiceFramePacket
extends RefCounted

## Strict boundary for Steam-compressed voice frames. The authority never accepts arbitrary audio
## resources or raw PCM; one bounded compressed frame is attributed to the authenticated sender,
## then wrapped with a sanitized acoustic result before it reaches a listener.

const VERSION := 1
const MAX_COMPRESSED_BYTES := 8192
const MAX_DECOMPRESSED_BYTES := 192000
const MIN_SAMPLE_RATE := 11025
const MAX_SAMPLE_RATE := 48000
const DEFAULT_SAMPLE_RATE := 24000
const MAX_CAPTURE_CLOCK_MSEC := 0x7fffffff
const MAX_SOURCE_ID := 0x7fffffff
const SOURCE_KIND_LIVE := &"live_voice"
const SOURCE_KIND_MIMIC := &"mimic_voice"


static func sanitize_captured_frame(
	sequence_value: Variant,
	captured_msec_value: Variant,
	sample_rate_value: Variant,
	compressed_value: Variant
) -> Dictionary:
	if not compressed_value is PackedByteArray:
		return {}
	var compressed: PackedByteArray = compressed_value
	var sequence := SafeVariant.integral_int_or(sequence_value, -1)
	var captured_msec := SafeVariant.integral_int_or(captured_msec_value, -1)
	var sample_rate := SafeVariant.integral_int_or(
		sample_rate_value,
		DEFAULT_SAMPLE_RATE
	)
	if (
		sequence <= 0
		or captured_msec < 0
		or captured_msec > MAX_CAPTURE_CLOCK_MSEC
		or sample_rate < MIN_SAMPLE_RATE
		or sample_rate > MAX_SAMPLE_RATE
		or compressed.is_empty()
		or compressed.size() > MAX_COMPRESSED_BYTES
	):
		return {}
	return {
		"sequence": sequence,
		"captured_msec": captured_msec,
		"sample_rate": sample_rate,
		# Packed arrays are copy-on-write. Keeping the validated frame does not clone its payload.
		"compressed": compressed,
	}


static func make_delivery(
	source_voice_id: int,
	source_player_id: int,
	source_entity_id: int,
	source_kind: StringName,
	generation: int,
	frame: Dictionary,
	acoustic_result: Dictionary,
	source_position: Vector3,
	server_send_msec: int
) -> Dictionary:
	if frame.is_empty() or acoustic_result.is_empty() or not source_position.is_finite():
		return {}
	var result := acoustic_result.duplicate(false)
	result["version"] = VERSION
	result["source_voice_id"] = source_voice_id
	result["source_player_id"] = source_player_id
	result["source_entity_id"] = source_entity_id
	result["source_kind"] = source_kind
	result["generation"] = generation
	result["voice_sequence"] = int(frame.get("sequence", -1))
	result["captured_msec"] = int(frame.get("captured_msec", 0))
	result["server_send_msec"] = maxi(server_send_msec, 0)
	result["sample_rate"] = int(frame.get("sample_rate", DEFAULT_SAMPLE_RATE))
	result["compressed"] = frame.get("compressed", PackedByteArray())
	result["source_position"] = source_position
	return sanitize_delivery(result)


static func sanitize_delivery(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw: Dictionary = value
	var source_voice_id := SafeVariant.integral_int_or(
		raw.get("source_voice_id"),
		-1
	)
	var source_player_id := SafeVariant.integral_int_or(
		raw.get("source_player_id"),
		-1
	)
	var source_entity_id := SafeVariant.integral_int_or(
		raw.get("source_entity_id"),
		-1
	)
	var generation := SafeVariant.integral_int_or(raw.get("generation"), -1)
	var source_kind := StringName(str(raw.get("source_kind", "")))
	if (
		source_voice_id < 0
		or source_voice_id > MAX_SOURCE_ID
		or source_player_id < 0
		or source_entity_id < 0
		or generation < 0
		or not [SOURCE_KIND_LIVE, SOURCE_KIND_MIMIC].has(source_kind)
	):
		return {}
	var frame := sanitize_captured_frame(
		raw.get("voice_sequence"),
		raw.get("captured_msec"),
		raw.get("sample_rate"),
		raw.get("compressed")
	)
	if frame.is_empty():
		return {}

	# Reuse the mature acoustic packet validator. Voice adds identity and compressed bytes, not a
	# second, subtly different set of filter/reverb bounds.
	var acoustic_input := raw.duplicate(false)
	acoustic_input["sound_id"] = &"spatial_voice"
	acoustic_input["sequence"] = int(frame["sequence"])
	var acoustic := AcousticEventPacket.sanitize(acoustic_input)
	if acoustic.is_empty():
		return {}
	acoustic.erase("sound_id")
	acoustic["voice_version"] = VERSION
	acoustic["source_voice_id"] = source_voice_id
	acoustic["source_player_id"] = source_player_id
	acoustic["source_entity_id"] = source_entity_id
	acoustic["source_kind"] = source_kind
	acoustic["generation"] = generation
	acoustic["voice_sequence"] = int(frame["sequence"])
	acoustic["captured_msec"] = int(frame["captured_msec"])
	acoustic["server_send_msec"] = maxi(
		SafeVariant.integral_int_or(raw.get("server_send_msec"), 0),
		0
	)
	acoustic["sample_rate"] = int(frame["sample_rate"])
	acoustic["compressed"] = frame["compressed"]
	return acoustic
