class_name LevelSpeakerSystemAuthoring
extends RefCounted

const DEFAULT_CABINET_SIZE := Vector3(0.92, 1.34, 0.42)
const DEFAULT_MAXIMUM_HEARING_DISTANCE := 72.0
const DEFAULT_PLAYBACK_VOLUME_DB := -11.0
const AUDIO_ID_BASE_START := 1_650_000_000
const AUDIO_ID_STRIDE := 4096


static func create_system(
	system_id: int,
	display_name: String,
	world_speaker_descriptors: Array[Dictionary]
) -> Dictionary:
	if system_id <= 0 or world_speaker_descriptors.is_empty():
		return {}
	var pivot := Vector3.ZERO
	var valid_world_speakers: Array[Dictionary] = []
	for raw_speaker: Dictionary in world_speaker_descriptors:
		var position := _finite_vector3(
			raw_speaker.get("position", Vector3.INF),
			Vector3.INF
		)
		if not position.is_finite():
			continue
		var speaker := sanitize_speaker(raw_speaker)
		if speaker.is_empty():
			continue
		speaker["position"] = position
		valid_world_speakers.append(speaker)
		pivot += position
	if valid_world_speakers.is_empty():
		return {}
	pivot /= float(valid_world_speakers.size())
	var relative_speakers: Array[Dictionary] = []
	for speaker: Dictionary in valid_world_speakers:
		var relative := speaker.duplicate(true)
		relative["position"] = (speaker["position"] as Vector3) - pivot
		relative_speakers.append(relative)
	var clean_name := display_name.strip_edges().replace("\n", " ").left(64)
	if clean_name.is_empty():
		clean_name = "PA SYSTEM %03d" % system_id
	var contact_id := "level:pa_array:%d" % system_id
	return sanitize_system({
		"id": system_id,
		"contact_id": contact_id,
		"display_name": clean_name,
		"audio_id_base": AUDIO_ID_BASE_START + system_id * AUDIO_ID_STRIDE,
		"origin": pivot,
		"scanner_beacon_position": Vector3.ZERO,
		"maximum_hearing_distance": DEFAULT_MAXIMUM_HEARING_DISTANCE,
		"playback_volume_db": DEFAULT_PLAYBACK_VOLUME_DB,
		"shared_late_field_enabled": false,
		"speakers": relative_speakers,
	})


static func sanitize_system(raw: Dictionary) -> Dictionary:
	var system_id := int(raw.get("id", 0))
	var contact_id := str(raw.get("contact_id", "")).strip_edges().left(128)
	var display_name := str(raw.get("display_name", "")).strip_edges().left(64)
	var audio_id_base := int(raw.get("audio_id_base", 0))
	if (
		system_id <= 0
		or contact_id.is_empty()
		or display_name.is_empty()
		or audio_id_base <= 0
		or audio_id_base >= 2_000_000_000
	):
		return {}
	var speakers: Array[Dictionary] = []
	var raw_speakers: Variant = raw.get("speakers", [])
	if not raw_speakers is Array:
		return {}
	for raw_speaker: Variant in raw_speakers:
		if not raw_speaker is Dictionary:
			continue
		var speaker := sanitize_speaker(raw_speaker)
		if not speaker.is_empty():
			speakers.append(speaker)
	if speakers.is_empty() or audio_id_base + speakers.size() >= 2_000_000_000:
		return {}
	return {
		"id": system_id,
		"contact_id": contact_id,
		"display_name": display_name,
		"audio_id_base": audio_id_base,
		"origin": _finite_vector3(raw.get("origin", Vector3.ZERO), Vector3.ZERO),
		"scanner_beacon_position": _finite_vector3(
			raw.get("scanner_beacon_position", Vector3.ZERO),
			Vector3.ZERO
		),
		"maximum_hearing_distance": clampf(
			_finite_float(raw.get(
				"maximum_hearing_distance",
				DEFAULT_MAXIMUM_HEARING_DISTANCE
			), DEFAULT_MAXIMUM_HEARING_DISTANCE),
			1.0,
			1000.0
		),
		"playback_volume_db": clampf(
			_finite_float(raw.get(
				"playback_volume_db",
				DEFAULT_PLAYBACK_VOLUME_DB
			), DEFAULT_PLAYBACK_VOLUME_DB),
			-60.0,
			18.0
		),
		"shared_late_field_enabled": bool(
			raw.get("shared_late_field_enabled", false)
		),
		"speakers": speakers,
	}


static func sanitize_speaker(raw: Dictionary) -> Dictionary:
	var position := _finite_vector3(
		raw.get("position", Vector3.INF),
		Vector3.INF
	)
	if not position.is_finite():
		return {}
	var size := _finite_vector3(
		raw.get("cabinet_size", DEFAULT_CABINET_SIZE),
		DEFAULT_CABINET_SIZE
	).abs()
	size = Vector3(
		maxf(size.x, 0.05),
		maxf(size.y, 0.05),
		maxf(size.z, 0.05)
	)
	return {
		"position": position,
		"rotation": _finite_vector3(
			raw.get("rotation", Vector3.ZERO),
			Vector3.ZERO
		),
		"is_indoor": bool(raw.get("is_indoor", true)),
		"installation_gain_db": clampf(
			_finite_float(raw.get("installation_gain_db", 0.0), 0.0),
			-24.0,
			12.0
		),
		"cabinet_size": size,
	}


static func serialize_system(raw: Dictionary) -> Dictionary:
	var system := sanitize_system(raw)
	if system.is_empty():
		return {}
	var serialized_speakers: Array[Dictionary] = []
	for speaker: Dictionary in system.get("speakers", []):
		serialized_speakers.append({
			"position": _vector3_to_array(speaker["position"]),
			"rotation": _vector3_to_array(speaker["rotation"]),
			"is_indoor": bool(speaker.get("is_indoor", true)),
			"installation_gain_db": float(
				speaker.get("installation_gain_db", 0.0)
			),
			"cabinet_size": _vector3_to_array(speaker["cabinet_size"]),
		})
	return {
		"id": system["id"],
		"contact_id": system["contact_id"],
		"display_name": system["display_name"],
		"audio_id_base": system["audio_id_base"],
		"origin": _vector3_to_array(system["origin"]),
		"scanner_beacon_position": _vector3_to_array(
			system["scanner_beacon_position"]
		),
		"maximum_hearing_distance": system["maximum_hearing_distance"],
		"playback_volume_db": system["playback_volume_db"],
		"shared_late_field_enabled": system["shared_late_field_enabled"],
		"speakers": serialized_speakers,
	}


static func world_speaker_descriptors(system_value: Dictionary) -> Array[Dictionary]:
	var system := sanitize_system(system_value)
	var result: Array[Dictionary] = []
	if system.is_empty():
		return result
	var origin: Vector3 = system.get("origin", Vector3.ZERO)
	for speaker: Dictionary in system.get("speakers", []):
		var world_speaker := speaker.duplicate(true)
		world_speaker["position"] = origin + (
			speaker.get("position", Vector3.ZERO) as Vector3
		)
		result.append(world_speaker)
	return result


static func _finite_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3 and (value as Vector3).is_finite():
		return value
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		var result := Vector3(
			_finite_float(array[0], fallback.x),
			_finite_float(array[1], fallback.y),
			_finite_float(array[2], fallback.z)
		)
		if result.is_finite():
			return result
	return fallback


static func _finite_float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var result := float(value)
		return result if is_finite(result) else fallback
	return fallback


static func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
