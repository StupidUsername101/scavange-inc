class_name LocalAudioPrediction
extends RefCounted

const KEYS := preload("res://scripts/audio/local_audio_prediction_keys.gd")

## Cosmetic owner prediction for locally knowable sounds. Gameplay and propagation remain
## server-authoritative; these keys only let the originating renderer avoid replaying a cue that
## it already started. Namespaces make deterministic gait/weapon keys disjoint from ad-hoc UI and
## jump keys without allocating strings or dictionaries in the hot path.

const CONTEXT_SOUND_ID := &"__local_listener_context"
const ENABLED := true
const MAX_SEQUENCE := KEYS.MAX_SEQUENCE
const WEAPON_MAX_SESSION := KEYS.WEAPON_MAX_SESSION
const WEAPON_MAX_SHOT := KEYS.WEAPON_MAX_SHOT


static func player_cue_profile(sound_id: StringName) -> Dictionary:
	var id_text := String(sound_id)
	if id_text.begins_with("footstep_"):
		return _profile(24.0, 0.0, 0.25, -1.0)
	if id_text.begins_with("jump_"):
		return _profile(26.0, 0.0, 0.35, -1.0)
	if id_text.begins_with("landing_"):
		return _profile(30.0, 0.0, 0.4, -1.0)
	match sound_id:
		&"fieldlink_open", &"fieldlink_close":
			return _profile(20.0, -5.0, 0.45, 0.12)
		&"fieldlink_hover":
			return _profile(8.0, -5.0, 0.22, 0.0)
		&"fieldlink_click":
			return _profile(12.0, -5.0, 0.32, 0.035)
		&"fieldlink_confirm", &"fieldlink_warning":
			return _profile(16.0, -5.0, 0.4, 0.06)
		&"mouth_click":
			return _profile(34.0, -3.0, 0.52, 0.16)
	return {}


static func resolve_pressure_strength(
	requested_strength: float,
	max_distance: float,
	base_volume_db: float,
	priority: float
) -> float:
	if requested_strength >= 0.0:
		return clampf(requested_strength, 0.0, 1.0)
	var reach := clampf(inverse_lerp(10.0, 140.0, max_distance), 0.0, 1.0)
	var level := clampf(inverse_lerp(-18.0, 6.0, base_volume_db), 0.0, 1.0)
	return clampf(
		0.10
		+ sqrt(reach) * 0.25
		+ level * 0.12
		+ clampf(priority, 0.0, 1.0) * 0.10,
		0.10,
		0.62
	)


static func sequence_key(sequence: int) -> int:
	return KEYS.sequence_key(sequence)


static func gait_step_key(step_sequence: int) -> int:
	return KEYS.gait_step_key(step_sequence)


static func weapon_shot_key(session: int, shot_index: int) -> int:
	return KEYS.weapon_shot_key(session, shot_index)


static func sanitize_key(value: Variant) -> int:
	return KEYS.sanitize_key(value)


static func sanitize_context(value: Variant) -> Dictionary:
	var context := AcousticEventPacket.sanitize(value)
	if context.get("sound_id", &"") != CONTEXT_SOUND_ID:
		return {}
	context.erase("local_prediction_key")
	return context


static func build_packet(
	context_value: Dictionary,
	sound_id: StringName,
	source_position: Vector3,
	volume_db: float,
	priority: float,
	prediction_key: int,
	pressure_strength := 0.0
) -> Dictionary:
	if (
		sound_id.is_empty()
		or not source_position.is_finite()
		or sanitize_key(prediction_key) == 0
	):
		return {}
	var context := sanitize_context(context_value)
	var packet := (
		context.duplicate(true)
		if not context.is_empty()
		else _free_field_fallback(source_position)
	)
	var context_source: Vector3 = packet.get("source_position", source_position)
	var translation := source_position - context_source
	packet["sound_id"] = sound_id
	packet["source_position"] = source_position
	packet["apparent_position"] = SafeVariant.vector3_strict_or(
		packet.get("apparent_position"),
		context_source
	) + translation
	packet["travel_delay_seconds"] = 0.0
	packet["volume_db"] = clampf(
		volume_db,
		AcousticPathModifier.MIN_VOLUME_DB,
		AcousticPathModifier.MAX_VOLUME_DB
	)
	packet["priority"] = clampf(priority, 0.0, 1.0)
	packet["local_prediction_key"] = prediction_key
	_translate_early_reflections(packet, translation)
	_apply_normalized_pressure(packet, translation, volume_db, pressure_strength)
	return AcousticEventPacket.sanitize(packet)


static func _free_field_fallback(source_position: Vector3) -> Dictionary:
	return {
		"version": AcousticEventPacket.VERSION,
		"sequence": 0,
		"sound_id": CONTEXT_SOUND_ID,
		"source_position": source_position,
		"apparent_position": source_position,
		"direct_distance": 0.0,
		"path_length": 0.0,
		"travel_delay_seconds": 0.0,
		"volume_db": 0.0,
		"band_gain": Vector3.ONE,
		"lowpass_hz": AcousticPathModifier.MAX_FILTER_HZ,
		"highpass_hz": AcousticPathModifier.MIN_FILTER_HZ,
		"resonance": 0.0,
		"reverb_send": 0.0,
		"reverb_room_size": 0.35,
		"reverb_damping": 0.5,
		"reverb_spread": 0.9,
		"reverb_predelay_msec": 8.0,
		"reverb_predelay_feedback": 0.0,
		"reverb_hipass": 0.05,
		"reverb_decay_seconds": 0.25,
		"environment_enclosure": 0.0,
		"priority": 0.5,
		"modifier_ids": PackedStringArray(),
	}


static func _profile(
	max_distance: float,
	volume_db: float,
	priority: float,
	pressure_strength: float
) -> Dictionary:
	return {
		"max_distance": max_distance,
		"volume_db": volume_db,
		"priority": priority,
		"pressure_strength": pressure_strength,
	}


static func _translate_early_reflections(packet: Dictionary, offset: Vector3) -> void:
	var raw_taps: Variant = packet.get("early_reflections", null)
	if not raw_taps is Array:
		return
	for tap_value: Variant in raw_taps as Array:
		if not tap_value is Dictionary:
			continue
		var tap := tap_value as Dictionary
		tap["apparent_position"] = SafeVariant.vector3_strict_or(
			tap.get("apparent_position"),
			packet.get("source_position", Vector3.ZERO)
		) + offset


static func _apply_normalized_pressure(
	packet: Dictionary,
	offset: Vector3,
	volume_db: float,
	pressure_strength: float
) -> void:
	var strength := clampf(pressure_strength, 0.0, 1.0)
	var raw_arrivals: Variant = packet.get("pressure_arrivals", null)
	if strength <= 0.0001 or not raw_arrivals is Array:
		packet.erase("pressure_strength")
		packet.erase("pressure_arrivals")
		return
	var strength_gain_db := linear_to_db(strength)
	for arrival_value: Variant in raw_arrivals as Array:
		if not arrival_value is Dictionary:
			continue
		var arrival := arrival_value as Dictionary
		arrival["apparent_position"] = SafeVariant.vector3_strict_or(
			arrival.get("apparent_position"),
			packet.get("source_position", Vector3.ZERO)
		) + offset
		arrival["volume_db"] = clampf(
			SafeVariant.finite_float_or(arrival.get("volume_db"), -80.0)
			+ volume_db
			+ strength_gain_db,
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		)
	packet["pressure_strength"] = strength
