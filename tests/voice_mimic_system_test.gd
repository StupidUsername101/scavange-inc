extends SceneTree

## Focused deterministic coverage for spatial voice transport and session-only captured-phrase
## mimicry. Microphone/decoder hardware is deliberately outside this headless boundary; their
## installed GodotSteam signatures and the game's bounded adapters are checked structurally.

var failure_count := 0
var assertion_count := 0


class FakeVoiceCoordinator:
	extends Node

	var acoustic_service: ServerAcousticService
	var server_players_by_player_id: Dictionary = {}
	var enemy: Node3D

	func get_server_player(player_id: int) -> Node3D:
		return server_players_by_player_id.get(player_id) as Node3D

	func get_server_enemy(enemy_id: int) -> Node3D:
		if enemy != null and int(enemy.get("enemy_id")) == enemy_id:
			return enemy
		return null

	func _is_rpc_peer_reachable(_peer_id: int) -> bool:
		return false

	func get_peer_id_for_player(_player_id: int) -> int:
		return -1


class FakeVoiceBody:
	extends Node3D

	var player_id := -1
	var enemy_id := -1
	var active := true
	var alive := true

	func get_audio_listener_position() -> Vector3:
		return position + Vector3.UP * 1.55


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_captured_frame_boundary()
	_test_jitter_reordering_and_generation_reset()
	_test_consent_and_bounded_session_memory()
	_test_authoritative_service_lifecycle()
	_test_transport_and_enemy_contract()
	if failure_count == 0:
		print("Voice mimic tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("Voice mimic tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _test_captured_frame_boundary() -> void:
	var bytes := PackedByteArray([1, 2, 3, 4])
	var frame := VoiceFramePacket.sanitize_captured_frame(1, 12, 24000, bytes)
	_expect(
		int(frame.get("sequence", -1)) == 1
		and frame.get("compressed", PackedByteArray()) == bytes,
		"a bounded attributed Steam frame crosses the capture boundary"
	)
	_expect(
		VoiceFramePacket.sanitize_captured_frame(
			1,
			12,
			24000,
			PackedByteArray()
		).is_empty(),
		"empty payloads are rejected"
	)
	var oversized := PackedByteArray()
	oversized.resize(VoiceFramePacket.MAX_COMPRESSED_BYTES + 1)
	_expect(
		VoiceFramePacket.sanitize_captured_frame(
			1,
			12,
			24000,
			oversized
		).is_empty(),
		"oversized microphone payloads are rejected before retention or relay"
	)
	var delivery := VoiceFramePacket.make_delivery(
		1300000002,
		2,
		2,
		VoiceFramePacket.SOURCE_KIND_LIVE,
		4,
		frame,
		{
			"apparent_position": Vector3(2.0, 1.0, -3.0),
			"volume_db": -12.0,
			"lowpass_hz": 8700.0,
		},
		Vector3(1.0, 1.5, -2.0),
		44
	)
	_expect(
		int(delivery.get("source_player_id", -1)) == 2
		and delivery.get("source_kind", &"") == VoiceFramePacket.SOURCE_KIND_LIVE
		and delivery.get("compressed", PackedByteArray()) == bytes
		and delivery.get("apparent_position", Vector3.ZERO) == Vector3(2.0, 1.0, -3.0),
		"delivery preserves identity, compressed payload, and the mature acoustic result"
	)


func _test_jitter_reordering_and_generation_reset() -> void:
	var jitter := VoiceFrameJitterBuffer.new()
	_expect(
		jitter.push(_delivery_stub(2, 4), 1000)
		and jitter.drain_ready(1020).is_empty(),
		"one early out-of-order packet waits inside the bounded jitter window"
	)
	_expect(jitter.push(_delivery_stub(1, 4), 1021), "the missing packet is admitted")
	var ready := jitter.drain_ready(1022)
	_expect(
		ready.size() == 2
		and int(ready[0].get("voice_sequence", -1)) == 1
		and int(ready[1].get("voice_sequence", -1)) == 2,
		"reordered packets drain in speech order"
	)
	_expect(
		jitter.push(_delivery_stub(1, 5), 1100)
		and jitter.generation == 5
		and jitter.last_emitted_sequence == 0,
		"a new speaking generation cannot inherit stale sequence state"
	)


func _test_consent_and_bounded_session_memory() -> void:
	var ring := VoiceUtteranceRing.new()
	var frame := VoiceFramePacket.sanitize_captured_frame(
		1,
		10,
		24000,
		PackedByteArray([8, 6, 7, 5, 3, 0, 9])
	)
	_expect(
		not ring.begin(2, 1, 1000)
		and not ring.append(2, frame, 1100),
		"mimic memory is opt-in, not silently populated by voice chat"
	)
	ring.set_consent(2, true)
	for clip_index: int in range(VoiceUtteranceRing.MAX_UTTERANCES_PER_PLAYER + 2):
		var start := 2000 + clip_index * 1000
		_expect(ring.begin(2, 1, start), "consented utterance capture begins")
		_expect(ring.append(2, frame, start + 300), "compressed speech remains retained")
		_expect(ring.finish(2, start + 360), "a complete bounded utterance is retained")
	_expect(
		ring.retained_clip_count(2) == VoiceUtteranceRing.MAX_UTTERANCES_PER_PLAYER
		and ring.retained_byte_count(2) <= VoiceUtteranceRing.MAX_BYTES_PER_PLAYER,
		"the per-player phrase and byte rings stay hard-bounded"
	)
	_expect(
		not ring.select_clip(2, 19).is_empty(),
		"a consented enemy can deterministically select a retained phrase"
	)
	ring.set_consent(2, false)
	_expect(
		ring.retained_clip_count(2) == 0
		and ring.retained_byte_count(2) == 0
		and ring.select_clip(2, 19).is_empty(),
		"revocation destroys every session-memory phrase immediately"
	)
	var ring_source := FileAccess.get_file_as_string(
		"res://scripts/voice/voice_utterance_ring.gd"
	)
	_expect(
		not ring_source.contains("FileAccess")
		and not ring_source.contains("user://"),
		"the mimic ring has no persistence path"
	)


func _test_authoritative_service_lifecycle() -> void:
	var coordinator := FakeVoiceCoordinator.new()
	var player := FakeVoiceBody.new()
	player.player_id = 2
	coordinator.server_players_by_player_id[2] = player
	var enemy := FakeVoiceBody.new()
	enemy.enemy_id = 9
	enemy.active = true
	enemy.alive = true
	coordinator.enemy = enemy
	var service := ServerVoiceChatService.new()
	service.bind(coordinator)
	_expect(service.register_player(2) > 0, "authority assigns a voice session generation")
	_expect(service.set_mimic_consent(2, true), "authority accepts explicit mimic consent")
	_expect(service.set_speaking(2, true, 1000), "authority begins one consented utterance")
	var frame_a := PackedByteArray([1, 3, 5, 7])
	var frame_b := PackedByteArray([2, 4, 6, 8])
	_expect(
		service.receive_frame(2, 1, 20, 24000, frame_a, 1050)
		and service.receive_frame(2, 2, 40, 24000, frame_b, 1350),
		"authenticated frames are admitted while push-to-talk is active"
	)
	_expect(service.set_speaking(2, false, 1400), "authority closes the utterance")
	_expect(
		service.utterances.retained_clip_count(2) == 1,
		"the completed compressed phrase enters the bounded session ring"
	)
	_expect(
		service.receive_frame(2, 3, 60, 24000, frame_b, 1450)
		and service.utterances.retained_clip_count(2) == 1,
		"a late expendable frame cannot reopen capture after the reliable stop marker"
	)
	_expect(
		service.try_schedule_enemy_mimic(9, 2)
		and service.is_enemy_mimic_playing(9),
		"an active enemy schedules a retained phrase from its own world source"
	)
	service.cancel_enemy_mimic(9)
	_expect(
		not service.is_enemy_mimic_playing(9),
		"enemy deactivation cancels future mimic input without fabricating a tail"
	)
	_expect(
		service.try_schedule_enemy_mimic(9, 2),
		"a retained clip can be selected again after the prior replay ends"
	)
	_expect(
		service.set_mimic_consent(2, false)
		and not service.is_enemy_mimic_playing(9)
		and service.utterances.retained_clip_count(2) == 0,
		"consent revocation immediately erases queued replay payloads as well as the ring"
	)
	service.forget_player(2)
	_expect(
		not service.has_mimic_consent(2)
		and service.utterances.retained_clip_count(2) == 0,
		"lease expiry erases consent and retained speech"
	)
	player.free()
	enemy.free()
	coordinator.free()


func _test_transport_and_enemy_contract() -> void:
	var client_source := FileAccess.get_file_as_string("res://scripts/client/client.gd")
	var server_source := FileAccess.get_file_as_string("res://scripts/server/server.gd")
	var enemy_source := FileAccess.get_file_as_string(
		"res://scripts/enemies/server_enemy.gd"
	)
	_expect(
		client_source.contains(
			'@rpc("authority", "unreliable", "call_local", 9)\nfunc on_voice_frame_received'
		)
		and server_source.contains(
			'@rpc("any_peer", "call_local", "unreliable", 9)\nfunc receive_voice_frame'
		),
		"voice frames use their application jitter buffer on a genuinely loss-tolerant Steam lane"
	)
	_expect(
		server_source.contains("voice_chat_service.tick(delta")
		and server_source.contains("voice_chat_service.suspend_player")
		and server_source.contains("voice_chat_service.forget_player"),
		"voice participates in normal server ticks, reconnect suspension, and final cleanup"
	)
	var definition := FluteRunnerDefinition.new()
	var flute_enemy := load(
		"res://resources/enemies/flute_runner.tres"
	) as EnemyDefinition
	var mimic_enemy := load(
		"res://resources/enemies/voice_mimic.tres"
	) as EnemyDefinition
	_expect(
		definition.captured_voice_mimic_enabled
		and definition.mimic_interval_max_seconds
		>= definition.mimic_interval_min_seconds
		and enemy_source.contains("_update_captured_voice_mimic")
		and flute_enemy != null
		and flute_enemy.flute_runner.flute_program_enabled
		and flute_enemy.flute_runner.flute_pose_enabled
		and not flute_enemy.flute_runner.captured_voice_mimic_enabled
		and mimic_enemy != null
		and not mimic_enemy.flute_runner.flute_program_enabled
		and not mimic_enemy.flute_runner.flute_pose_enabled
		and mimic_enemy.flute_runner.captured_voice_mimic_enabled,
		"flute performance and captured speech mimicry are separate capability-driven specimens"
	)
	var steam_methods := Steam.get_method_list()
	var capture_methods := _method_names(steam_methods)
	_expect(
		capture_methods.has(&"startVoiceRecording")
		and capture_methods.has(&"stopVoiceRecording")
		and capture_methods.has(&"getAvailableVoice")
		and capture_methods.has(&"getVoice")
		and capture_methods.has(&"decompressVoice"),
		"the installed GodotSteam runtime exposes the voice capture/decode API"
	)
	_expect(
		_method_accepts_argument_count(steam_methods, &"getVoice", 1)
		and _method_accepts_argument_count(
			steam_methods,
			&"decompressVoice",
			3
		),
		"the capture and decoder calls match the installed GodotSteam signatures"
	)


static func _delivery_stub(sequence: int, generation: int) -> Dictionary:
	return {
		"voice_sequence": sequence,
		"generation": generation,
	}


static func _method_names(methods: Array) -> Dictionary[StringName, bool]:
	var result: Dictionary[StringName, bool] = {}
	for method_value: Variant in methods:
		if method_value is Dictionary:
			result[StringName(str((method_value as Dictionary).get("name", "")))] = true
	return result


static func _method_accepts_argument_count(
	methods: Array,
	method_name: StringName,
	argument_count: int
) -> bool:
	for method_value: Variant in methods:
		if not method_value is Dictionary:
			continue
		var method: Dictionary = method_value
		if StringName(str(method.get("name", ""))) != method_name:
			continue
		var arguments: Array = method.get("args", [])
		var default_arguments: Array = method.get("default_args", [])
		return (
			argument_count <= arguments.size()
			and argument_count >= arguments.size() - default_arguments.size()
		)
	return false


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("Voice mimic assertion failed: " + message)
