class_name VoiceUtteranceRing
extends RefCounted

## Session-memory-only captured utterances for Tier-A mimicry. This object has no file API by
## design. Consent gates collection, every player owns a bounded phrase/byte ring, and revocation
## destroys both completed and in-progress material immediately.

const MAX_UTTERANCES_PER_PLAYER := 3
const MAX_UTTERANCE_MILLISECONDS := 4200
const MIN_UTTERANCE_MILLISECONDS := 240
const MAX_BYTES_PER_UTTERANCE := 65536
const MAX_BYTES_PER_PLAYER := 131072
const MAX_CHUNKS_PER_UTTERANCE := 192

var _consent_by_player_id: Dictionary[int, bool] = {}
var _active_by_player_id: Dictionary[int, Dictionary] = {}
var _clips_by_player_id: Dictionary[int, Array] = {}
var _next_clip_id := 0


func set_consent(player_id: int, enabled: bool) -> void:
	if player_id < 0:
		return
	if enabled:
		_consent_by_player_id[player_id] = true
		return
	_consent_by_player_id.erase(player_id)
	_active_by_player_id.erase(player_id)
	_clips_by_player_id.erase(player_id)


func has_consent(player_id: int) -> bool:
	return bool(_consent_by_player_id.get(player_id, false))


func begin(player_id: int, generation: int, now_msec: int) -> bool:
	if not has_consent(player_id) or generation < 0:
		return false
	_active_by_player_id[player_id] = {
		"generation": generation,
		"started_msec": maxi(now_msec, 0),
		"last_msec": maxi(now_msec, 0),
		"byte_count": 0,
		"chunks": [],
	}
	return true


func append(player_id: int, frame: Dictionary, now_msec: int) -> bool:
	if not has_consent(player_id):
		return false
	var active: Dictionary = _active_by_player_id.get(player_id, {})
	if active.is_empty():
		return false
	var compressed_value: Variant = frame.get("compressed")
	if not compressed_value is PackedByteArray:
		return false
	var compressed: PackedByteArray = compressed_value
	var chunks: Array = active.get("chunks", [])
	var byte_count := int(active.get("byte_count", 0))
	var elapsed := maxi(now_msec - int(active.get("started_msec", now_msec)), 0)
	if (
		compressed.is_empty()
		or chunks.size() >= MAX_CHUNKS_PER_UTTERANCE
		or byte_count + compressed.size() > MAX_BYTES_PER_UTTERANCE
		or elapsed > MAX_UTTERANCE_MILLISECONDS
	):
		return false
	chunks.append({
		"offset_msec": elapsed,
		"sample_rate": int(frame.get(
			"sample_rate",
			VoiceFramePacket.DEFAULT_SAMPLE_RATE
		)),
		"compressed": compressed,
	})
	active["chunks"] = chunks
	active["byte_count"] = byte_count + compressed.size()
	active["last_msec"] = maxi(now_msec, int(active.get("last_msec", now_msec)))
	_active_by_player_id[player_id] = active
	return true


func finish(player_id: int, now_msec: int) -> bool:
	var active: Dictionary = _active_by_player_id.get(player_id, {})
	_active_by_player_id.erase(player_id)
	if active.is_empty() or not has_consent(player_id):
		return false
	var chunks: Array = active.get("chunks", [])
	var duration_msec := clampi(
		maxi(
			int(active.get("last_msec", now_msec)),
			mini(now_msec, int(active.get("started_msec", now_msec)) + MAX_UTTERANCE_MILLISECONDS)
		) - int(active.get("started_msec", now_msec)),
		0,
		MAX_UTTERANCE_MILLISECONDS
	)
	if chunks.is_empty() or duration_msec < MIN_UTTERANCE_MILLISECONDS:
		return false
	_next_clip_id += 1
	var clips: Array = _clips_by_player_id.get(player_id, [])
	clips.append({
		"clip_id": _next_clip_id,
		"source_player_id": player_id,
		"generation": int(active.get("generation", -1)),
		"duration_msec": duration_msec,
		"byte_count": int(active.get("byte_count", 0)),
		"chunks": chunks,
	})
	while (
		clips.size() > MAX_UTTERANCES_PER_PLAYER
		or _clip_bytes(clips) > MAX_BYTES_PER_PLAYER
	):
		clips.pop_front()
	_clips_by_player_id[player_id] = clips
	return true


func select_clip(player_id: int, deterministic_seed: int) -> Dictionary:
	if not has_consent(player_id):
		return {}
	var clips: Array = _clips_by_player_id.get(player_id, [])
	if clips.is_empty():
		return {}
	var index := posmod(deterministic_seed, clips.size())
	# The compressed payloads remain copy-on-write, while callers get independent dictionaries.
	return (clips[index] as Dictionary).duplicate(true)


func forget_player(player_id: int) -> void:
	set_consent(player_id, false)


func clear() -> void:
	_consent_by_player_id.clear()
	_active_by_player_id.clear()
	_clips_by_player_id.clear()
	_next_clip_id = 0


func retained_clip_count(player_id: int) -> int:
	return (_clips_by_player_id.get(player_id, []) as Array).size()


func retained_byte_count(player_id: int) -> int:
	return _clip_bytes(_clips_by_player_id.get(player_id, []) as Array)


static func _clip_bytes(clips: Array) -> int:
	var result := 0
	for clip_value: Variant in clips:
		if clip_value is Dictionary:
			result += int((clip_value as Dictionary).get("byte_count", 0))
	return result
