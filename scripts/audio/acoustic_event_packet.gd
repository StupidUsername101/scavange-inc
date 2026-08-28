class_name AcousticEventPacket
extends RefCounted

const LOCAL_PREDICTION_KEYS := preload(
	"res://scripts/audio/local_audio_prediction_keys.gd"
)

const VERSION := 4
const MAX_SOUND_ID_LENGTH := 96
const MAX_MODIFIER_IDS := 12
const MAX_MODIFIER_ID_LENGTH := 64
const MAX_PATH_LENGTH := 10000.0
const MAX_TRAVEL_DELAY_SECONDS := 8.0
const MAX_PRESSURE_ARRIVALS := AcousticPropagationGraph.MAX_PRESSURE_ARRIVALS
const MAX_EARLY_REFLECTIONS := 2
const MAX_EARLY_REFLECTION_DELAY_SECONDS := 0.18


static func sanitize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var packet: Dictionary = value
	var sound_id := str(packet.get("sound_id", "")).strip_edges()
	if sound_id.is_empty() or sound_id.length() > MAX_SOUND_ID_LENGTH:
		return {}
	var source_position := SafeVariant.vector3_strict_or(
		packet.get("source_position"),
		Vector3(INF, INF, INF)
	)
	var apparent_position := SafeVariant.vector3_strict_or(
		packet.get("apparent_position"),
		Vector3(INF, INF, INF)
	)
	if not source_position.is_finite() or not apparent_position.is_finite():
		return {}

	var lowpass_hz := clampf(
		SafeVariant.finite_float_or(
			packet.get("lowpass_hz"),
			AcousticPathModifier.MAX_FILTER_HZ
		),
		AcousticPathModifier.MIN_FILTER_HZ,
		AcousticPathModifier.MAX_FILTER_HZ
	)
	var highpass_hz := clampf(
		SafeVariant.finite_float_or(
			packet.get("highpass_hz"),
			AcousticPathModifier.MIN_FILTER_HZ
		),
		AcousticPathModifier.MIN_FILTER_HZ,
		lowpass_hz
	)
	var modifier_ids := PackedStringArray()
	var raw_modifier_ids: Variant = packet.get("modifier_ids", [])
	if raw_modifier_ids is Array or raw_modifier_ids is PackedStringArray:
		for raw_id: Variant in raw_modifier_ids:
			var modifier_id := str(raw_id).strip_edges()
			if (
				modifier_id.is_empty()
				or modifier_id.length() > MAX_MODIFIER_ID_LENGTH
				or modifier_ids.has(modifier_id)
			):
				continue
			modifier_ids.append(modifier_id)
			if modifier_ids.size() >= MAX_MODIFIER_IDS:
				break

	var band_gain := SafeVariant.vector3_strict_or(
		packet.get("band_gain"),
		Vector3.ONE
	)
	band_gain = Vector3(
		clampf(band_gain.x, 0.0, 4.0),
		clampf(band_gain.y, 0.0, 4.0),
		clampf(band_gain.z, 0.0, 4.0)
	)
	var result := {
		"version": VERSION,
		"sequence": maxi(
			SafeVariant.integral_int_or(packet.get("sequence"), 0),
			0
		),
		"sound_id": StringName(sound_id),
		"source_position": source_position,
		"apparent_position": apparent_position,
		"direct_distance": clampf(
			SafeVariant.finite_float_or(packet.get("direct_distance"), 0.0),
			0.0,
			MAX_PATH_LENGTH
		),
		"path_length": clampf(
			SafeVariant.finite_float_or(packet.get("path_length"), 0.0),
			0.0,
			MAX_PATH_LENGTH
		),
		"travel_delay_seconds": clampf(
			SafeVariant.finite_float_or(
				packet.get("travel_delay_seconds"),
				0.0
			),
			0.0,
			MAX_TRAVEL_DELAY_SECONDS
		),
		"volume_db": clampf(
			SafeVariant.finite_float_or(packet.get("volume_db"), 0.0),
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		),
		"band_gain": band_gain,
		"lowpass_hz": lowpass_hz,
		"highpass_hz": highpass_hz,
		"resonance": clampf(
			SafeVariant.finite_float_or(packet.get("resonance"), 0.0),
			0.0,
			1.0
		),
		"reverb_send": clampf(
			SafeVariant.finite_float_or(packet.get("reverb_send"), 0.0),
			0.0,
			1.0
		),
		"reverb_room_size": _unit_value(packet, "reverb_room_size", 0.35),
		"reverb_damping": _unit_value(packet, "reverb_damping", 0.5),
		"reverb_spread": _unit_value(packet, "reverb_spread", 0.9),
		"reverb_predelay_msec": clampf(
			SafeVariant.finite_float_or(packet.get("reverb_predelay_msec"), 8.0),
			0.0,
			500.0
		),
		"reverb_predelay_feedback": _unit_value(
			packet,
			"reverb_predelay_feedback",
			0.25
		),
		"reverb_hipass": _unit_value(packet, "reverb_hipass", 0.05),
		"reverb_decay_seconds": clampf(
			SafeVariant.finite_float_or(packet.get("reverb_decay_seconds"), 0.25),
			0.0,
			AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
		),
		"environment_enclosure": _unit_value(
			packet,
			"environment_enclosure",
			0.0
		),
		"priority": clampf(
			SafeVariant.finite_float_or(packet.get("priority"), 0.5),
			0.0,
			1.0
		),
		"modifier_ids": modifier_ids,
	}
	var local_prediction_key := LOCAL_PREDICTION_KEYS.sanitize_key(
		packet.get("local_prediction_key")
	)
	if local_prediction_key > 0:
		result["local_prediction_key"] = local_prediction_key
	var early_reflections := _sanitize_early_reflections(
		packet.get("early_reflections", [])
	)
	if not early_reflections.is_empty():
		result["early_reflections"] = early_reflections
	var pressure_strength := _unit_value(packet, "pressure_strength", 0.0)
	if pressure_strength <= 0.0001:
		return result
	var pressure_arrivals := _sanitize_pressure_arrivals(
		packet.get("pressure_arrivals", [])
	)
	if pressure_arrivals.is_empty():
		return result
	result["pressure_strength"] = pressure_strength
	result["pressure_enclosure"] = _unit_value(
		packet,
		"pressure_enclosure",
		0.0
	)
	result["pressure_reverb_send"] = _unit_value(
		packet,
		"pressure_reverb_send",
		0.0
	)
	result["pressure_reverb_room_size"] = _unit_value(
		packet,
		"pressure_reverb_room_size",
		0.02
	)
	result["pressure_reverb_damping"] = _unit_value(
		packet,
		"pressure_reverb_damping",
		0.05
	)
	result["pressure_reverb_spread"] = _unit_value(
		packet,
		"pressure_reverb_spread",
		1.0
	)
	result["pressure_reverb_predelay_msec"] = clampf(
		SafeVariant.finite_float_or(
			packet.get("pressure_reverb_predelay_msec"),
			3.0
		),
		0.0,
		500.0
	)
	result["pressure_reverb_predelay_feedback"] = _unit_value(
		packet,
		"pressure_reverb_predelay_feedback",
		0.0
	)
	result["pressure_reverb_hipass"] = _unit_value(
		packet,
		"pressure_reverb_hipass",
		0.0
	)
	result["pressure_decay_seconds"] = clampf(
		SafeVariant.finite_float_or(
			packet.get("pressure_decay_seconds"),
			AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
		),
		AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
		AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
	)
	result["pressure_escape"] = _unit_value(packet, "pressure_escape", 1.0)
	result["pressure_arrivals"] = pressure_arrivals
	return result


static func _sanitize_early_reflections(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for raw_tap: Variant in value as Array:
		if not raw_tap is Dictionary:
			continue
		var tap := raw_tap as Dictionary
		var apparent_position := SafeVariant.vector3_strict_or(
			tap.get("apparent_position"),
			Vector3(INF, INF, INF)
		)
		var band_gain := SafeVariant.vector3_strict_or(
			tap.get("band_gain"),
			Vector3.ONE
		)
		if not apparent_position.is_finite() or not band_gain.is_finite():
			continue
		result.append({
			"reflection_id": maxi(
				SafeVariant.integral_int_or(tap.get("reflection_id"), 0),
				0
			),
			"apparent_position": apparent_position,
			"extra_delay_seconds": clampf(
				SafeVariant.finite_float_or(
					tap.get("extra_delay_seconds"),
					0.0
				),
				0.0,
				MAX_EARLY_REFLECTION_DELAY_SECONDS
			),
			"gain": clampf(
				SafeVariant.finite_float_or(tap.get("gain"), 0.0),
				0.0,
				0.70
			),
			"band_gain": Vector3(
				clampf(band_gain.x, 0.0, 1.0),
				clampf(band_gain.y, 0.0, 1.0),
				clampf(band_gain.z, 0.0, 1.0)
			),
			"pan": clampf(
				SafeVariant.finite_float_or(tap.get("pan"), 0.0),
				-1.0,
				1.0
			),
		})
		if result.size() >= MAX_EARLY_REFLECTIONS:
			break
	return result


static func _sanitize_pressure_arrivals(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	var raw_arrivals: Array = value
	for raw_value: Variant in raw_arrivals:
		if not raw_value is Dictionary:
			continue
		var raw: Dictionary = raw_value
		var apparent_position := SafeVariant.vector3_strict_or(
			raw.get("apparent_position"),
			Vector3(INF, INF, INF)
		)
		if not apparent_position.is_finite():
			continue
		var lowpass_hz := clampf(
			SafeVariant.finite_float_or(
				raw.get("lowpass_hz"),
				AcousticPathModifier.MAX_FILTER_HZ
			),
			AcousticPathModifier.MIN_FILTER_HZ,
			AcousticPathModifier.MAX_FILTER_HZ
		)
		var band_gain := SafeVariant.vector3_strict_or(
			raw.get("band_gain"),
			Vector3.ONE
		)
		band_gain = Vector3(
			clampf(band_gain.x, 0.0, 4.0),
			clampf(band_gain.y, 0.0, 4.0),
			clampf(band_gain.z, 0.0, 4.0)
		)
		result.append({
			"kind": clampi(
				SafeVariant.integral_int_or(raw.get("kind"), 0),
				0,
				1
			),
			"apparent_position": apparent_position,
			"path_length": clampf(
				SafeVariant.finite_float_or(raw.get("path_length"), 0.0),
				0.0,
				MAX_PATH_LENGTH
			),
			"travel_delay_seconds": clampf(
				SafeVariant.finite_float_or(
					raw.get("travel_delay_seconds"),
					0.0
				),
				0.0,
				MAX_TRAVEL_DELAY_SECONDS
			),
			"volume_db": clampf(
				SafeVariant.finite_float_or(raw.get("volume_db"), 0.0),
				AcousticPathModifier.MIN_VOLUME_DB,
				AcousticPathModifier.MAX_VOLUME_DB
			),
			"band_gain": band_gain,
			"lowpass_hz": lowpass_hz,
			"highpass_hz": clampf(
				SafeVariant.finite_float_or(
					raw.get("highpass_hz"),
					AcousticPathModifier.MIN_FILTER_HZ
				),
				AcousticPathModifier.MIN_FILTER_HZ,
				lowpass_hz
			),
			"resonance": clampf(
				SafeVariant.finite_float_or(raw.get("resonance"), 0.0),
				0.0,
				1.0
			),
			"reverb_scale": clampf(
				SafeVariant.finite_float_or(raw.get("reverb_scale"), 1.0),
				0.0,
				1.0
			),
		})
		if result.size() >= MAX_PRESSURE_ARRIVALS:
			break
	return result


static func _unit_value(packet: Dictionary, key: String, fallback: float) -> float:
	return clampf(
		SafeVariant.finite_float_or(packet.get(key), fallback),
		0.0,
		1.0
	)
