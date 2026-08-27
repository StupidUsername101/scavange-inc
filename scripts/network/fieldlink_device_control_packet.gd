class_name FieldlinkDeviceControlPacket
extends RefCounted

## Strict boundary shared by Fieldlink's generic device-console transport. The outer envelope is
## device-agnostic; each registered control type owns a small payload sanitizer.

const VERSION := 1
const MAX_CONTACT_ID_LENGTH := 96
const MAX_CONTROL_TYPE_LENGTH := 32
const MAX_ACTION_LENGTH := 40
const MAX_DISPLAY_NAME_LENGTH := 80
const MAX_STATUS_LENGTH := 32
const MAX_TRACK_COUNT := 64
const MAX_TRACK_NAME_LENGTH := 96
const MAX_COMMAND_FIELDS := 12


static func sanitize_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw: Dictionary = value
	var contact_id := sanitize_contact_id(raw.get("contact_id", ""))
	var control_type := _bounded_name(
		raw.get("control_type", ""),
		MAX_CONTROL_TYPE_LENGTH
	)
	if contact_id.is_empty() or control_type.is_empty():
		return {}
	var payload: Dictionary = {}
	match control_type:
		&"radio", &"speaker_cluster":
			payload = _sanitize_playlist_audio_payload(raw.get("payload", {}))
		_:
			return {}
	if payload.is_empty():
		return {}
	return {
		"version": VERSION,
		"contact_id": contact_id,
		"control_type": control_type,
		"display_name": _bounded_text(
			raw.get("display_name", "TECHNICAL DEVICE"),
			MAX_DISPLAY_NAME_LENGTH
		),
		"status_text": _bounded_text(
			raw.get("status_text", "ONLINE"),
			MAX_STATUS_LENGTH
		),
		"revision": maxi(
			SafeVariant.integral_int_or(raw.get("revision"), 0),
			0
		),
		"payload": payload,
	}


static func sanitize_command(
	contact_value: Variant,
	action_value: Variant,
	payload_value: Variant
) -> Dictionary:
	var contact_id := sanitize_contact_id(contact_value)
	var action := _bounded_name(action_value, MAX_ACTION_LENGTH)
	if contact_id.is_empty() or action.is_empty():
		return {}
	var payload: Dictionary = {}
	if payload_value is Dictionary:
		for raw_key: Variant in (payload_value as Dictionary).keys():
			if payload.size() >= MAX_COMMAND_FIELDS:
				break
			var key := _bounded_text(raw_key, 32)
			if key.is_empty():
				continue
			var field: Variant = (payload_value as Dictionary)[raw_key]
			if (
				field is bool
				or field is int
				or field is float
			):
				payload[key] = field
			elif field is String or field is StringName:
				payload[key] = str(field).left(128)
	return {
		"contact_id": contact_id,
		"action": action,
		"payload": payload,
	}


static func sanitize_contact_id(value: Variant) -> StringName:
	var result := _bounded_text(value, MAX_CONTACT_ID_LENGTH)
	if result.is_empty() or result.contains("/") or result.contains("\\"):
		return &""
	return StringName(result)


static func _sanitize_playlist_audio_payload(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var raw: Dictionary = value
	var tracks: Array[Dictionary] = []
	var raw_tracks: Variant = raw.get("tracks", [])
	if raw_tracks is Array:
		for raw_track: Variant in raw_tracks:
			if tracks.size() >= MAX_TRACK_COUNT:
				break
			if not raw_track is Dictionary:
				continue
			var track: Dictionary = raw_track
			var track_index := SafeVariant.integral_int_or(
				track.get("track_index"),
				-1
			)
			var display_name := _bounded_text(
				track.get("display_name", ""),
				MAX_TRACK_NAME_LENGTH
			)
			if track_index < 0 or display_name.is_empty():
				continue
			tracks.append({
				"track_index": track_index,
				"display_name": display_name,
			})
	if tracks.is_empty():
		return {}
	var playback_state := _bounded_name(raw.get("playback_state", &"stopped"), 16)
	if playback_state not in [&"playing", &"paused", &"stopped"]:
		playback_state = &"stopped"
	return {
		"tracks": tracks,
		"selected_track_index": clampi(
			SafeVariant.integral_int_or(raw.get("selected_track_index"), 0),
			0,
			tracks.size() - 1
		),
		"current_track_index": clampi(
			SafeVariant.integral_int_or(raw.get("current_track_index"), -1),
			-1,
			tracks.size() - 1
		),
		"playback_state": playback_state,
		"volume_ratio": clampf(
			SafeVariant.finite_float_or(raw.get("volume_ratio"), 0.75),
			0.0,
			1.0
		),
		"elapsed_seconds": maxf(
			SafeVariant.finite_float_or(raw.get("elapsed_seconds"), 0.0),
			0.0
		),
		"duration_seconds": maxf(
			SafeVariant.finite_float_or(raw.get("duration_seconds"), 0.0),
			0.0
		),
	}


static func _bounded_name(value: Variant, maximum_length: int) -> StringName:
	return StringName(_bounded_text(value, maximum_length).to_lower())


static func _bounded_text(value: Variant, maximum_length: int) -> String:
	return str(value).strip_edges().left(maxi(maximum_length, 0))
