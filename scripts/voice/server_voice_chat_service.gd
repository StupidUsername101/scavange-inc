class_name ServerVoiceChatService
extends RefCounted

## Authoritative admission, acoustic-context and captured-phrase service. Steam-compressed payloads
## remain opaque here: the server rate-limits and attributes them, evaluates geometry at 20 Hz per
## active source/listener pair, then relays only to listeners with an audible cached route.

const LIVE_SOURCE_ID_BASE := 1_300_000_000
const MIMIC_SOURCE_ID_BASE := 1_400_000_000
const CONTEXT_INTERVAL_MILLISECONDS := 50
const LIVE_SOURCE_GRACE_MILLISECONDS := 420
const MAX_VOICE_DISTANCE := 42.0
const LIVE_VOICE_LEVEL_DB := -3.0
const MIMIC_VOICE_LEVEL_DB := -1.0
const MAX_FRAMES_PER_RATE_WINDOW := 72
const MAX_BYTES_PER_RATE_WINDOW := 131072
const RATE_WINDOW_MILLISECONDS := 1000
const MAX_MIMIC_QUEUE := 4

# Keep the autoload boundary structural. Fresh clones parse Server before the global class cache has
# necessarily registered every scene script used below.
var coordinator
var utterances := VoiceUtteranceRing.new()
var _generation_by_player_id: Dictionary[int, int] = {}
var _last_sequence_by_player_id: Dictionary[int, int] = {}
var _speaking_by_player_id: Dictionary[int, bool] = {}
var _live_last_frame_msec_by_player_id: Dictionary[int, int] = {}
var _rate_state_by_player_id: Dictionary[int, Dictionary] = {}
var _context_by_source_listener: Dictionary[Vector2i, Dictionary] = {}
var _active_source_records: Dictionary[int, Dictionary] = {}
var _pending_mimics: Array[Dictionary] = []
var _next_context_refresh_msec := 0
var _next_generation := 0
var _next_mimic_generation := 0


func bind(owner: Node) -> void:
	coordinator = owner


func register_player(player_id: int) -> int:
	if player_id < 0:
		return -1
	_next_generation += 1
	_generation_by_player_id[player_id] = _next_generation
	_last_sequence_by_player_id[player_id] = 0
	_speaking_by_player_id[player_id] = false
	_live_last_frame_msec_by_player_id[player_id] = 0
	_rate_state_by_player_id.erase(player_id)
	return _next_generation


func suspend_player(player_id: int) -> void:
	_set_speaking_internal(player_id, false, Time.get_ticks_msec())
	_remove_live_source(player_id)


func forget_player(player_id: int) -> void:
	suspend_player(player_id)
	_generation_by_player_id.erase(player_id)
	_last_sequence_by_player_id.erase(player_id)
	_speaking_by_player_id.erase(player_id)
	_live_last_frame_msec_by_player_id.erase(player_id)
	_rate_state_by_player_id.erase(player_id)
	utterances.forget_player(player_id)
	for mimic_index: int in range(_pending_mimics.size() - 1, -1, -1):
		if int(_pending_mimics[mimic_index].get("source_player_id", -1)) == player_id:
			_remove_source(int(_pending_mimics[mimic_index].get(
				"source_voice_id",
				-1
			)))
			_pending_mimics.remove_at(mimic_index)


func reset() -> void:
	if coordinator != null:
		var acoustic_service := coordinator.get("acoustic_service") as ServerAcousticService
		if acoustic_service != null:
			for source_voice_id: int in _active_source_records.keys():
				acoustic_service.forget_continuous_source(source_voice_id)
	_generation_by_player_id.clear()
	_last_sequence_by_player_id.clear()
	_speaking_by_player_id.clear()
	_live_last_frame_msec_by_player_id.clear()
	_rate_state_by_player_id.clear()
	_context_by_source_listener.clear()
	_active_source_records.clear()
	_pending_mimics.clear()
	utterances.clear()
	_next_context_refresh_msec = 0
	_next_generation = 0
	_next_mimic_generation = 0


func set_mimic_consent(player_id: int, enabled: bool) -> bool:
	if not _generation_by_player_id.has(player_id):
		return false
	utterances.set_consent(player_id, enabled)
	if not enabled:
		for mimic_index: int in range(_pending_mimics.size() - 1, -1, -1):
			var pending: Dictionary = _pending_mimics[mimic_index]
			if int(pending.get("source_player_id", -1)) != player_id:
				continue
			_remove_source(int(pending.get("source_voice_id", -1)))
			_pending_mimics.remove_at(mimic_index)
	return utterances.has_consent(player_id) == enabled


func has_mimic_consent(player_id: int) -> bool:
	return utterances.has_consent(player_id)


func set_speaking(player_id: int, active: bool, now_msec: int) -> bool:
	if not _generation_by_player_id.has(player_id):
		return false
	_set_speaking_internal(player_id, active, now_msec)
	return true


func receive_frame(
	player_id: int,
	sequence_value: Variant,
	captured_msec_value: Variant,
	sample_rate_value: Variant,
	compressed_value: Variant,
	now_msec: int
) -> bool:
	if not _generation_by_player_id.has(player_id):
		return false
	var frame := VoiceFramePacket.sanitize_captured_frame(
		sequence_value,
		captured_msec_value,
		sample_rate_value,
		compressed_value
	)
	if frame.is_empty() or not _admit_rate(player_id, frame, now_msec):
		return false
	var sequence := int(frame["sequence"])
	if sequence <= int(_last_sequence_by_player_id.get(player_id, 0)):
		return false
	_last_sequence_by_player_id[player_id] = sequence
	_live_last_frame_msec_by_player_id[player_id] = now_msec
	# Speaking start/stop is reliable while PCM frames are expendable. A frame that overtakes the
	# stop marker may still be heard, but must never reopen capture or leave the speaker permanently
	# active; only an admitted speaking marker owns utterance lifetime.
	if bool(_speaking_by_player_id.get(player_id, false)):
		utterances.append(player_id, frame, now_msec)

	var source_voice_id := live_source_id(player_id)
	_active_source_records[source_voice_id] = {
		"source_kind": VoiceFramePacket.SOURCE_KIND_LIVE,
		"source_entity_id": player_id,
		"source_player_id": player_id,
		"generation": int(_generation_by_player_id[player_id]),
	}
	if not _has_any_context(source_voice_id):
		_refresh_source_context(source_voice_id)
	_route_frame(source_voice_id, frame, now_msec)
	return true


func try_schedule_enemy_mimic(enemy_id: int, source_player_id: int) -> bool:
	if (
		coordinator == null
		or enemy_id < 0
		or source_player_id < 0
		or _pending_mimics.size() >= MAX_MIMIC_QUEUE
	):
		return false
	for pending: Dictionary in _pending_mimics:
		if int(pending.get("enemy_id", -1)) == enemy_id:
			return false
	var clip := utterances.select_clip(
		source_player_id,
		enemy_id * 1103515245 + _next_mimic_generation * 12345
	)
	if clip.is_empty():
		return false
	var enemy := coordinator.call("get_server_enemy", enemy_id) as Node3D
	if (
		not is_instance_valid(enemy)
		or not bool(enemy.get("alive"))
		or not bool(enemy.get("active"))
	):
		return false
	_next_mimic_generation += 1
	var source_voice_id := mimic_source_id(enemy_id)
	_active_source_records[source_voice_id] = {
		"source_kind": VoiceFramePacket.SOURCE_KIND_MIMIC,
		"source_entity_id": enemy_id,
		"source_player_id": source_player_id,
		"generation": _next_mimic_generation,
	}
	_pending_mimics.append({
		"enemy_id": enemy_id,
		"source_voice_id": source_voice_id,
		"source_player_id": source_player_id,
		"generation": _next_mimic_generation,
		"started_msec": Time.get_ticks_msec(),
		"next_chunk_index": 0,
		"chunks": clip.get("chunks", []),
	})
	_refresh_source_context(source_voice_id)
	return true


func tick(_delta: float, now_msec: int) -> void:
	_expire_live_sources(now_msec)
	if now_msec >= _next_context_refresh_msec:
		_next_context_refresh_msec = now_msec + CONTEXT_INTERVAL_MILLISECONDS
		for source_voice_id: int in _active_source_records.keys():
			_refresh_source_context(source_voice_id)
	_tick_mimics(now_msec)


func is_enemy_mimic_playing(enemy_id: int) -> bool:
	for pending: Dictionary in _pending_mimics:
		if int(pending.get("enemy_id", -1)) == enemy_id:
			return true
	return false


func cancel_enemy_mimic(enemy_id: int) -> void:
	for mimic_index: int in range(_pending_mimics.size() - 1, -1, -1):
		var pending: Dictionary = _pending_mimics[mimic_index]
		if int(pending.get("enemy_id", -1)) != enemy_id:
			continue
		_remove_source(int(pending.get("source_voice_id", -1)))
		_pending_mimics.remove_at(mimic_index)


func generation_for_player(player_id: int) -> int:
	return int(_generation_by_player_id.get(player_id, -1))


static func live_source_id(player_id: int) -> int:
	return LIVE_SOURCE_ID_BASE + clampi(player_id, 0, 99999999)


static func mimic_source_id(enemy_id: int) -> int:
	return MIMIC_SOURCE_ID_BASE + clampi(enemy_id, 0, 99999999)


func _set_speaking_internal(player_id: int, active: bool, now_msec: int) -> void:
	var previous := bool(_speaking_by_player_id.get(player_id, false))
	if previous == active:
		return
	_speaking_by_player_id[player_id] = active
	var generation := int(_generation_by_player_id.get(player_id, -1))
	if active:
		utterances.begin(player_id, generation, now_msec)
	else:
		utterances.finish(player_id, now_msec)
		_live_last_frame_msec_by_player_id[player_id] = now_msec
	_publish_speaking_state(player_id, generation, active)


func _publish_speaking_state(player_id: int, generation: int, active: bool) -> void:
	if coordinator == null:
		return
	for listener_player_id: int in coordinator.server_players_by_player_id.keys():
		var peer_id := int(coordinator.call(
			"get_peer_id_for_player",
			listener_player_id
		))
		if peer_id <= 0 or not coordinator.call("_is_rpc_peer_reachable", peer_id):
			continue
		coordinator.call(
			"publish_voice_speaking_state_to_peer",
			peer_id,
			player_id,
			generation,
			active
		)


func _admit_rate(player_id: int, frame: Dictionary, now_msec: int) -> bool:
	var state: Dictionary = _rate_state_by_player_id.get(player_id, {})
	var window_started := int(state.get("window_started_msec", now_msec))
	if now_msec - window_started >= RATE_WINDOW_MILLISECONDS:
		state = {
			"window_started_msec": now_msec,
			"frame_count": 0,
			"byte_count": 0,
		}
	var frame_count := int(state.get("frame_count", 0)) + 1
	var compressed: PackedByteArray = frame.get("compressed", PackedByteArray())
	var byte_count := int(state.get("byte_count", 0)) + compressed.size()
	if (
		frame_count > MAX_FRAMES_PER_RATE_WINDOW
		or byte_count > MAX_BYTES_PER_RATE_WINDOW
	):
		_rate_state_by_player_id[player_id] = state
		return false
	state["frame_count"] = frame_count
	state["byte_count"] = byte_count
	_rate_state_by_player_id[player_id] = state
	return true


func _expire_live_sources(now_msec: int) -> void:
	var stale_player_ids: Array[int] = []
	for player_id: int in _live_last_frame_msec_by_player_id.keys():
		var last_frame_msec := int(_live_last_frame_msec_by_player_id[player_id])
		if (
			bool(_speaking_by_player_id.get(player_id, false))
			or last_frame_msec <= 0
			or now_msec - last_frame_msec <= LIVE_SOURCE_GRACE_MILLISECONDS
		):
			continue
		stale_player_ids.append(player_id)
	for player_id: int in stale_player_ids:
		_remove_live_source(player_id)


func _remove_live_source(player_id: int) -> void:
	var source_voice_id := live_source_id(player_id)
	_remove_source(source_voice_id)


func _remove_source(source_voice_id: int) -> void:
	_active_source_records.erase(source_voice_id)
	for key: Vector2i in _context_by_source_listener.keys():
		if key.x == source_voice_id:
			_context_by_source_listener.erase(key)
	if coordinator != null:
		var acoustic_service := coordinator.get("acoustic_service") as ServerAcousticService
		if acoustic_service != null:
			acoustic_service.forget_continuous_source(source_voice_id)


func _has_any_context(source_voice_id: int) -> bool:
	for key: Vector2i in _context_by_source_listener.keys():
		if key.x == source_voice_id:
			return true
	return false


func _refresh_source_context(source_voice_id: int) -> void:
	if coordinator == null:
		return
	var source_record: Dictionary = _active_source_records.get(source_voice_id, {})
	if source_record.is_empty():
		return
	var source_position := _resolve_source_position(source_record)
	if not source_position.is_finite():
		_remove_source(source_voice_id)
		return
	var source_body := _resolve_source_body(source_record)
	var acoustic_service := coordinator.get("acoustic_service") as ServerAcousticService
	if acoustic_service == null:
		return
	var source_kind: StringName = source_record.get(
		"source_kind",
		VoiceFramePacket.SOURCE_KIND_LIVE
	)
	var output_level_db := (
		MIMIC_VOICE_LEVEL_DB
		if source_kind == VoiceFramePacket.SOURCE_KIND_MIMIC
		else LIVE_VOICE_LEVEL_DB
	)
	var hearing_distance := AcousticPropagationGraph.level_scaled_hearing_distance(
		MAX_VOICE_DISTANCE,
		output_level_db
	)
	for listener_id: int in coordinator.server_players_by_player_id.keys():
		var key := Vector2i(source_voice_id, listener_id)
		if (
			source_kind == VoiceFramePacket.SOURCE_KIND_LIVE
			and listener_id == int(source_record.get("source_player_id", -1))
		):
			_context_by_source_listener.erase(key)
			continue
		var listener := coordinator.call("get_server_player", listener_id) as ServerPlayer
		if not is_instance_valid(listener):
			_context_by_source_listener.erase(key)
			continue
		var exclusions: Array[RID] = [listener.get_rid()]
		if is_instance_valid(source_body) and source_body is CollisionObject3D:
			exclusions.append((source_body as CollisionObject3D).get_rid())
		var result := acoustic_service.calculate_listener_result(
			listener_id,
			listener.get_audio_listener_position(),
			source_position,
			hearing_distance,
			null,
			AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
			false,
			exclusions,
			source_voice_id
		)
		if not bool(result.get("audible", false)):
			_context_by_source_listener.erase(key)
			continue
		result.erase("audible")
		result["volume_db"] = clampf(
			float(result.get("volume_db", 0.0)) + output_level_db,
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		)
		result["priority"] = 0.84
		_context_by_source_listener[key] = result


func _resolve_source_body(source_record: Dictionary) -> Node3D:
	if coordinator == null:
		return null
	var source_kind: StringName = source_record.get("source_kind", &"")
	var source_entity_id := int(source_record.get("source_entity_id", -1))
	if source_kind == VoiceFramePacket.SOURCE_KIND_MIMIC:
		return coordinator.call("get_server_enemy", source_entity_id) as Node3D
	return coordinator.call("get_server_player", source_entity_id) as Node3D


func _resolve_source_position(source_record: Dictionary) -> Vector3:
	var body := _resolve_source_body(source_record)
	if not is_instance_valid(body):
		return Vector3.INF
	if body.has_method("get_audio_listener_position"):
		return body.call("get_audio_listener_position") as Vector3
	return body.global_position + Vector3.UP * 1.55


func _route_frame(source_voice_id: int, frame: Dictionary, now_msec: int) -> void:
	if coordinator == null:
		return
	var source_record: Dictionary = _active_source_records.get(source_voice_id, {})
	if source_record.is_empty():
		return
	var source_position := _resolve_source_position(source_record)
	if not source_position.is_finite():
		return
	for listener_id: int in coordinator.server_players_by_player_id.keys():
		var context: Dictionary = _context_by_source_listener.get(
			Vector2i(source_voice_id, listener_id),
			{}
		)
		if context.is_empty():
			continue
		var peer_id := int(coordinator.call(
			"get_peer_id_for_player",
			listener_id
		))
		if (
			peer_id <= 0
			or not coordinator.call("_is_rpc_peer_reachable", peer_id)
		):
			continue
		var packet := VoiceFramePacket.make_delivery(
			source_voice_id,
			int(source_record.get("source_player_id", -1)),
			int(source_record.get("source_entity_id", -1)),
			source_record.get("source_kind", VoiceFramePacket.SOURCE_KIND_LIVE),
			int(source_record.get("generation", 0)),
			frame,
			context,
			source_position,
			now_msec
		)
		if not packet.is_empty():
			coordinator.call(
				"publish_voice_frame_to_peer",
				peer_id,
				packet
			)


func _tick_mimics(now_msec: int) -> void:
	for mimic_index: int in range(_pending_mimics.size() - 1, -1, -1):
		var pending := _pending_mimics[mimic_index]
		var chunks: Array = pending.get("chunks", [])
		var chunk_index := int(pending.get("next_chunk_index", 0))
		var elapsed := maxi(now_msec - int(pending.get("started_msec", now_msec)), 0)
		while chunk_index < chunks.size():
			var chunk := chunks[chunk_index] as Dictionary
			if int(chunk.get("offset_msec", 0)) > elapsed:
				break
			var frame := VoiceFramePacket.sanitize_captured_frame(
				chunk_index + 1,
				int(chunk.get("offset_msec", 0)),
				chunk.get("sample_rate", VoiceFramePacket.DEFAULT_SAMPLE_RATE),
				chunk.get("compressed", PackedByteArray())
			)
			if not frame.is_empty():
				_route_frame(int(pending["source_voice_id"]), frame, now_msec)
			chunk_index += 1
		pending["next_chunk_index"] = chunk_index
		_pending_mimics[mimic_index] = pending
		if chunk_index >= chunks.size():
			_remove_source(int(pending["source_voice_id"]))
			_pending_mimics.remove_at(mimic_index)
