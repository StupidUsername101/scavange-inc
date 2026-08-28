# Generated data is stored in resources/generated/music_visual_envelopes.bin. Keep this loader small.
class_name MusicVisualEnvelopeCatalog
extends RefCounted

const SAMPLE_RATE_HZ := 20.0
const DATA_PATH := "res://resources/generated/music_visual_envelopes.bin"
const DATA_MAGIC := "SCVMVE1 "
const DATA_VERSION := 1
const MAX_TRACK_COUNT := 4096
const MAX_PATH_BYTES := 4096
const MAX_ENVELOPE_BYTES := 10_000_000

static var _loaded := false
static var _track_envelopes: Dictionary[String, PackedByteArray] = {}


static func has_envelope(path: String) -> bool:
	_ensure_loaded()
	return _track_envelopes.has(path)


static func get_envelope(path: String) -> PackedByteArray:
	_ensure_loaded()
	return _track_envelopes.get(path, PackedByteArray())


static func get_track_paths() -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	result.assign(_track_envelopes.keys())
	return result


static func sample_level(path: String, playback_seconds: float) -> float:
	_ensure_loaded()
	var envelope: PackedByteArray = _track_envelopes.get(
		path,
		PackedByteArray()
	)
	if envelope.is_empty():
		return -1.0
	var sample_position := clampf(
		maxf(playback_seconds, 0.0) * SAMPLE_RATE_HZ,
		0.0,
		float(envelope.size() - 1)
	)
	var first_index := floori(sample_position)
	var second_index := mini(first_index + 1, envelope.size() - 1)
	return lerpf(
		float(envelope[first_index]) / 255.0,
		float(envelope[second_index]) / 255.0,
		sample_position - float(first_index)
	)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_fail_load("could not open the generated envelope data")
		return
	var magic_bytes := file.get_buffer(DATA_MAGIC.length())
	if (
		magic_bytes.size() != DATA_MAGIC.length()
		or magic_bytes.get_string_from_ascii() != DATA_MAGIC
	):
		_fail_load("the envelope data header is invalid")
		return
	var version := file.get_32()
	var sample_rate := file.get_32()
	var track_count := file.get_32()
	if (
		version != DATA_VERSION
		or sample_rate != roundi(SAMPLE_RATE_HZ)
		or track_count > MAX_TRACK_COUNT
	):
		_fail_load("the envelope data version or bounds are invalid")
		return
	for _track_index: int in range(track_count):
		var path_size := file.get_32()
		if path_size <= 0 or path_size > MAX_PATH_BYTES:
			_fail_load("an envelope path exceeds its bounds")
			return
		var path_bytes := file.get_buffer(path_size)
		if path_bytes.size() != path_size:
			_fail_load("an envelope path is truncated")
			return
		var envelope_size := file.get_32()
		if envelope_size <= 0 or envelope_size > MAX_ENVELOPE_BYTES:
			_fail_load("an envelope exceeds its bounds")
			return
		var envelope := file.get_buffer(envelope_size)
		if envelope.size() != envelope_size:
			_fail_load("an envelope is truncated")
			return
		_track_envelopes[path_bytes.get_string_from_utf8()] = envelope


static func _fail_load(reason: String) -> void:
	_track_envelopes.clear()
	push_warning("Music visual envelopes unavailable: %s." % reason)
