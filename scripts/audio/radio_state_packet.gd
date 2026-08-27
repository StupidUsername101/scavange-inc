class_name RadioStatePacket
extends RefCounted

const VERSION := 9
const MAX_PLAYBACK_SECONDS := 86400.0
const MAX_START_DELAY_SECONDS := 8.0
const MAX_DISTORTION_KEEP_HF_HZ := 20000.0
const MAX_CACHED_RESOURCE_PATHS := 256
const MUSIC_LOUDNESS := preload("res://scripts/audio/music_loudness_catalog.gd")

static var _resource_validity_by_path: Dictionary[String, bool] = {}

## Strict client boundary for continuous radio state. In particular, a network packet may never
## persuade a client to load an arbitrary project resource as audio.


static func sanitize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var state: Dictionary = value
	var item_id := SafeVariant.integral_int_or(state.get("item_id"), -1)
	var revision := SafeVariant.integral_int_or(state.get("revision"), -1)
	var song_path := str(state.get("song_path", "")).strip_edges()
	if item_id < 0 or revision < 0 or not _is_safe_song_path(song_path):
		return {}

	# Reuse the one-shot packet's well-tested acoustic validation, then discard its semantic ID.
	var acoustic_input := state.duplicate(false)
	acoustic_input["sound_id"] = &"continuous_radio"
	var acoustic := AcousticEventPacket.sanitize(acoustic_input)
	if acoustic.is_empty():
		return {}
	acoustic.erase("sound_id")
	acoustic["radio_version"] = VERSION
	acoustic["item_id"] = item_id
	acoustic["revision"] = revision
	acoustic["song_path"] = song_path
	acoustic["playback_offset_seconds"] = clampf(
		SafeVariant.finite_float_or(
			state.get("playback_offset_seconds"),
			0.0
		),
		0.0,
		MAX_PLAYBACK_SECONDS
	)
	acoustic["start_delay_seconds"] = clampf(
		SafeVariant.finite_float_or(state.get("start_delay_seconds"), 0.0),
		0.0,
		MAX_START_DELAY_SECONDS
	)
	acoustic["stream_length_seconds"] = clampf(
		SafeVariant.finite_float_or(state.get("stream_length_seconds"), 0.0),
		0.0,
		MAX_PLAYBACK_SECONDS
	)
	acoustic["distortion_mode"] = clampi(
		SafeVariant.integral_int_or(state.get("distortion_mode"), 3),
		0,
		4
	)
	acoustic["distortion_drive"] = clampf(
		SafeVariant.finite_float_or(state.get("distortion_drive"), 0.0),
		0.0,
		1.0
	)
	acoustic["distortion_keep_hf_hz"] = clampf(
		SafeVariant.finite_float_or(
			state.get("distortion_keep_hf_hz"),
			MAX_DISTORTION_KEEP_HF_HZ
		),
		AcousticPathModifier.MIN_FILTER_HZ,
		MAX_DISTORTION_KEEP_HF_HZ
	)
	acoustic["distortion_post_gain_db"] = clampf(
		SafeVariant.finite_float_or(
			state.get("distortion_post_gain_db"),
			0.0
		),
		-24.0,
		12.0
	)
	acoustic["static_mix_db"] = clampf(
		SafeVariant.finite_float_or(state.get("static_mix_db"), -60.0),
		-60.0,
		0.0
	)
	acoustic["receiver_static_enabled"] = SafeVariant.strict_bool_or(
		state.get("receiver_static_enabled"),
		# Version-seven senders used -60 dB as their de-facto disabled value. Preserve that
		# behavior at the compatibility boundary without carrying the magic number into playback.
		float(acoustic["static_mix_db"]) > -60.0
	)
	acoustic["program_normalization_gain_db"] = clampf(
		SafeVariant.finite_float_or(
			state.get("program_normalization_gain_db"),
			0.0
		),
		MUSIC_LOUDNESS.MIN_NORMALIZATION_GAIN_DB,
		MUSIC_LOUDNESS.MAX_NORMALIZATION_GAIN_DB
	)
	acoustic["program_reference_gain_db"] = clampf(
		SafeVariant.finite_float_or(
			state.get("program_reference_gain_db"),
			0.0
		),
		0.0,
		12.0
	)
	var shared_program_group_id := SafeVariant.integral_int_or(
		state.get("shared_program_group_id"),
		-1
	)
	if shared_program_group_id >= 0:
		acoustic["shared_program_group_id"] = shared_program_group_id
		acoustic["shared_program_late_field_enabled"] = (
			SafeVariant.strict_bool_or(
				state.get("shared_program_late_field_enabled"),
				true
			)
		)
		# A synchronized array needs this already-bounded server diagnostic to keep listener-space
		# diffuse recovery out of its per-cabinet directional weights. Ordinary single-source
		# radios do not consume it, so older packets safely retain the zero fallback.
		acoustic["diffuse_field_gain_db"] = clampf(
			SafeVariant.finite_float_or(
				state.get("diffuse_field_gain_db"),
				0.0
			),
			0.0,
			AcousticPathModifier.MAX_VOLUME_DB
		)
		acoustic["program_playback_offset_seconds"] = clampf(
			SafeVariant.finite_float_or(
				state.get("program_playback_offset_seconds"),
				acoustic["playback_offset_seconds"]
			),
			0.0,
			MAX_PLAYBACK_SECONDS
		)
	return acoustic


static func _is_safe_song_path(path: String) -> bool:
	if (
		path.is_empty()
		or path.contains("\\")
		or path.contains("..")
		or not path.begins_with(RadioItemDefinition.MUSIC_ROOT + "/")
		or not RadioItemDefinition.MUSIC_EXTENSIONS.has(
			path.get_extension().to_lower()
		)
	):
		return false
	if _resource_validity_by_path.has(path):
		return _resource_validity_by_path[path]
	var is_valid := ResourceLoader.exists(path, "AudioStream")
	if _resource_validity_by_path.size() < MAX_CACHED_RESOURCE_PATHS:
		_resource_validity_by_path[path] = is_valid
	return is_valid
