class_name SpatialVoiceChatRenderer
extends Node

## Fixed client PCM/DSP pool for live speakers and captured-phrase mimics. The server decides which
## sources are audible and supplies the same geometry-derived packet used by world sounds; clients
## continuously decode admitted Steam frames and smoothly present the latest listener context.

const MAX_VOICES := 8
const BUS_PREFIX := "ScavangeSpatialVoice"
const GENERATOR_BUFFER_SECONDS := 0.32
const POSITION_FOLLOW_SPEED := 28.0
const EFFECT_FOLLOW_SPEED := 32.0
const VOLUME_FOLLOW_SPEED := 30.0
const INPUT_GRACE_MILLISECONDS := 120
const SLOT_RELEASE_MILLISECONDS := 1800
const LISTENER_ACTIVITY := preload(
	"res://scripts/audio/listener_acoustic_activity.gd"
)

var _players: Array[AudioStreamPlayer3D] = []
var _playbacks: Array[AudioStreamGeneratorPlayback] = []
var _racks: Array[SpatialAudioEffectRack] = []
var _jitter_buffers: Array[VoiceFrameJitterBuffer] = []
var _pcm_chunks: Array[Array] = []
var _pcm_offsets := PackedInt32Array()
var _source_ids := PackedInt32Array()
var _source_player_ids := PackedInt32Array()
var _last_input_msec := PackedInt64Array()
var _target_positions: Array[Vector3] = []
var _target_packets: Array[Dictionary] = []
var _target_volumes_db := PackedFloat32Array()
var _muted_player_ids: Dictionary[int, bool] = {}
var _listener_acoustic_intensity := 0.0


func _ready() -> void:
	set_process(true)


func submit(raw_packet: Dictionary) -> bool:
	var packet := VoiceFramePacket.sanitize_delivery(raw_packet)
	if packet.is_empty():
		return false
	var source_player_id := int(packet["source_player_id"])
	if bool(_muted_player_ids.get(source_player_id, false)):
		return false
	_ensure_pool()
	var source_voice_id := int(packet["source_voice_id"])
	var slot := _find_slot(source_voice_id)
	if slot < 0:
		slot = _allocate_slot(source_voice_id, source_player_id)
	if slot < 0:
		return false
	var incoming_generation := int(packet.get("generation", -1))
	if (
		_jitter_buffers[slot].generation >= 0
		and _jitter_buffers[slot].generation != incoming_generation
	):
		_pcm_chunks[slot].clear()
		_pcm_offsets[slot] = 0
		_racks[slot].prepare_for_input()
	_target_positions[slot] = packet.get("apparent_position", packet["source_position"])
	_target_packets[slot] = packet
	_target_volumes_db[slot] = float(packet.get(
		"volume_db",
		AcousticPathModifier.MIN_VOLUME_DB
	))
	_last_input_msec[slot] = Time.get_ticks_msec()
	return _jitter_buffers[slot].push(packet, _last_input_msec[slot])


func set_player_muted(player_id: int, muted: bool) -> void:
	if muted:
		_muted_player_ids[player_id] = true
	else:
		_muted_player_ids.erase(player_id)
	for slot: int in range(_source_ids.size()):
		if _source_player_ids[slot] == player_id:
			_target_volumes_db[slot] = (
				AcousticPathModifier.MIN_VOLUME_DB
				if muted
				else float(_target_packets[slot].get(
					"volume_db",
					AcousticPathModifier.MIN_VOLUME_DB
				))
			)


func reset_session() -> void:
	for slot: int in range(_players.size()):
		_release_slot(slot, true)
	_muted_player_ids.clear()
	_listener_acoustic_intensity = 0.0


func _process(delta: float) -> void:
	_listener_acoustic_intensity = LISTENER_ACTIVITY.follow(
		_listener_acoustic_intensity,
		0.0,
		delta,
		10.0,
		7.0
	)
	if _players.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	var position_weight := 1.0 - exp(-POSITION_FOLLOW_SPEED * maxf(delta, 0.0))
	var effect_weight := 1.0 - exp(-EFFECT_FOLLOW_SPEED * maxf(delta, 0.0))
	var volume_weight := 1.0 - exp(-VOLUME_FOLLOW_SPEED * maxf(delta, 0.0))
	for slot: int in range(_players.size()):
		if _source_ids[slot] < 0:
			continue
		var ready := _jitter_buffers[slot].drain_ready(now_msec)
		for packet: Dictionary in ready:
			_decode_packet_into_slot(slot, packet)
		var player := _players[slot]
		player.global_position = player.global_position.lerp(
			_target_positions[slot],
			position_weight
		)
		player.volume_db = lerpf(
			player.volume_db,
			_target_volumes_db[slot],
			volume_weight
		)
		var target_packet := _target_packets[slot]
		if not target_packet.is_empty():
			_racks[slot].approach_acoustic(target_packet, effect_weight)
		var pushed_audio := _push_pcm(slot)
		if pushed_audio:
			_listener_acoustic_intensity = LISTENER_ACTIVITY.combine_energy(
				_listener_acoustic_intensity,
				LISTENER_ACTIVITY.from_received_volume_db(player.volume_db)
			)
		var recently_driven := (
			pushed_audio
			or now_msec - _last_input_msec[slot] <= INPUT_GRACE_MILLISECONDS
		)
		_racks[slot].update_tail_floor(recently_driven, delta)
		if (
			not recently_driven
			and now_msec - _last_input_msec[slot] >= SLOT_RELEASE_MILLISECONDS
			and _pcm_chunks[slot].is_empty()
			and _jitter_buffers[slot].queued_packet_count() == 0
		):
			_release_slot(slot)


func _ensure_pool() -> void:
	if not _players.is_empty():
		return
	_source_ids.resize(MAX_VOICES)
	_source_ids.fill(-1)
	_source_player_ids.resize(MAX_VOICES)
	_source_player_ids.fill(-1)
	_last_input_msec.resize(MAX_VOICES)
	_last_input_msec.fill(0)
	_pcm_offsets.resize(MAX_VOICES)
	_pcm_offsets.fill(0)
	_target_volumes_db.resize(MAX_VOICES)
	_target_volumes_db.fill(AcousticPathModifier.MIN_VOLUME_DB)
	for slot: int in range(MAX_VOICES):
		var bus_name := StringName("%s%d" % [BUS_PREFIX, slot])
		var rack := SpatialAudioEffectRack.attach(bus_name)
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = VoiceFramePacket.DEFAULT_SAMPLE_RATE
		stream.buffer_length = GENERATOR_BUFFER_SECONDS
		var player := AudioStreamPlayer3D.new()
		player.name = "SpatialVoice%d" % slot
		player.stream = stream
		player.bus = bus_name
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = 10000.0
		player.panning_strength = 1.0
		player.volume_db = AcousticPathModifier.MIN_VOLUME_DB
		add_child(player)
		player.play()
		_players.append(player)
		_playbacks.append(player.get_stream_playback() as AudioStreamGeneratorPlayback)
		_racks.append(rack)
		_jitter_buffers.append(VoiceFrameJitterBuffer.new())
		_pcm_chunks.append([])
		_target_positions.append(Vector3.ZERO)
		_target_packets.append({})


func _find_slot(source_voice_id: int) -> int:
	for slot: int in range(_source_ids.size()):
		if _source_ids[slot] == source_voice_id:
			return slot
	return -1


func _allocate_slot(source_voice_id: int, source_player_id: int) -> int:
	var slot := _find_slot(-1)
	if slot < 0:
		# The pool is deliberately hard-bounded. Replace the stalest voice; a four-player session and
		# one mimic per enemy normally stay well below this path.
		var oldest_msec := 0x7fffffffffffffff
		for candidate: int in range(_last_input_msec.size()):
			if _last_input_msec[candidate] < oldest_msec:
				oldest_msec = _last_input_msec[candidate]
				slot = candidate
		_release_slot(slot, true)
	_source_ids[slot] = source_voice_id
	_source_player_ids[slot] = source_player_id
	_last_input_msec[slot] = Time.get_ticks_msec()
	_target_volumes_db[slot] = AcousticPathModifier.MIN_VOLUME_DB
	_players[slot].volume_db = AcousticPathModifier.MIN_VOLUME_DB
	_jitter_buffers[slot].reset()
	_racks[slot].prepare_for_input()
	return slot


func _decode_packet_into_slot(slot: int, packet: Dictionary) -> void:
	var compressed: PackedByteArray = packet.get("compressed", PackedByteArray())
	if compressed.is_empty():
		return
	var sample_rate := int(packet.get(
		"sample_rate",
		VoiceFramePacket.DEFAULT_SAMPLE_RATE
	))
	var stream := _players[slot].stream as AudioStreamGenerator
	if stream != null and int(stream.mix_rate) != sample_rate:
		stream.mix_rate = sample_rate
		_players[slot].stop()
		_players[slot].play()
		_playbacks[slot] = (
			_players[slot].get_stream_playback() as AudioStreamGeneratorPlayback
		)
	var decoded := Steam.decompressVoice(
		compressed,
		sample_rate,
		VoiceFramePacket.MAX_DECOMPRESSED_BYTES
	) as Dictionary
	if int(decoded.get("result", -1)) != int(Steam.VOICE_RESULT_OK):
		return
	var pcm_value: Variant = decoded.get("uncompressed", PackedByteArray())
	if not pcm_value is PackedByteArray:
		return
	var pcm: PackedByteArray = pcm_value
	var written := clampi(
		int(decoded.get("written", pcm.size())),
		0,
		mini(pcm.size(), VoiceFramePacket.MAX_DECOMPRESSED_BYTES)
	)
	written -= written % 2
	if written <= 0:
		return
	if written < pcm.size():
		pcm = pcm.slice(0, written)
	_pcm_chunks[slot].append(pcm)


func _push_pcm(slot: int) -> bool:
	var playback := _playbacks[slot]
	if playback == null:
		return false
	var available := playback.get_frames_available()
	var pushed := false
	while available > 0 and not _pcm_chunks[slot].is_empty():
		var pcm: PackedByteArray = _pcm_chunks[slot][0]
		var byte_offset := _pcm_offsets[slot]
		while available > 0 and byte_offset + 1 < pcm.size():
			var sample := clampf(float(pcm.decode_s16(byte_offset)) / 32768.0, -1.0, 1.0)
			playback.push_frame(Vector2(sample, sample))
			byte_offset += 2
			available -= 1
			pushed = true
		if byte_offset + 1 >= pcm.size():
			_pcm_chunks[slot].pop_front()
			_pcm_offsets[slot] = 0
		else:
			_pcm_offsets[slot] = byte_offset
	return pushed


func _release_slot(slot: int, immediate := false) -> void:
	if slot < 0 or slot >= _source_ids.size():
		return
	_source_ids[slot] = -1
	_source_player_ids[slot] = -1
	_target_packets[slot].clear()
	_target_volumes_db[slot] = AcousticPathModifier.MIN_VOLUME_DB
	_target_positions[slot] = Vector3.ZERO
	_pcm_chunks[slot].clear()
	_pcm_offsets[slot] = 0
	_jitter_buffers[slot].reset()
	if immediate:
		_players[slot].volume_db = AcousticPathModifier.MIN_VOLUME_DB
		_racks[slot].reset_state()


func get_debug_state() -> Dictionary:
	var active_count := 0
	var queued_pcm_chunks := 0
	for slot: int in range(_source_ids.size()):
		active_count += int(_source_ids[slot] >= 0)
		queued_pcm_chunks += _pcm_chunks[slot].size()
	return {
		"pool_size": _players.size(),
		"active_voice_count": active_count,
		"queued_pcm_chunks": queued_pcm_chunks,
		"muted_player_count": _muted_player_ids.size(),
	}


func get_listener_acoustic_intensity() -> float:
	return _listener_acoustic_intensity
