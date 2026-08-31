extends SceneTree

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_key_contract()
	_test_listener_context_packet()
	await _test_runtime_context_gate()
	await _test_renderer_reconciliation()
	_test_network_architecture_contract()
	_finish()


func _test_key_contract() -> void:
	var sequence_key := LocalAudioPrediction.sequence_key(7)
	var gait_key := LocalAudioPrediction.gait_step_key(7)
	var weapon_key := LocalAudioPrediction.weapon_shot_key(7, 3)
	_expect(
		sequence_key != gait_key
		and gait_key != weapon_key
		and sequence_key != weapon_key
		and LocalAudioPrediction.sanitize_key(sequence_key) == sequence_key
		and LocalAudioPrediction.sanitize_key(gait_key) == gait_key
		and LocalAudioPrediction.sanitize_key(weapon_key) == weapon_key
		and LocalAudioPrediction.sanitize_key(-1) == 0,
		"prediction keys are bounded and disjoint across UI, gait, and weapon events"
	)
	_expect(
		LocalAudioPrediction.weapon_shot_key(19, 0)
		!= LocalAudioPrediction.weapon_shot_key(19, 1),
		"automatic fire assigns one deterministic reconciliation key per shot"
	)


func _test_listener_context_packet() -> void:
	var context := _base_packet(
		LocalAudioPrediction.CONTEXT_SOUND_ID,
		Vector3(1.0, 2.0, 3.0)
	)
	context["early_reflections"] = [{
		"delay_seconds": 0.03,
		"gain": 0.25,
		"pan": 0.0,
		"apparent_position": Vector3(2.0, 2.0, 3.0),
	}]
	context["pressure_strength"] = 1.0
	context["pressure_reverb_send"] = 0.2
	context["pressure_reverb_room_size"] = 0.3
	context["pressure_reverb_damping"] = 0.5
	context["pressure_reverb_spread"] = 0.8
	context["pressure_reverb_predelay_msec"] = 3.0
	context["pressure_reverb_predelay_feedback"] = 0.0
	context["pressure_reverb_hipass"] = 0.0
	context["pressure_decay_seconds"] = 0.4
	context["pressure_escape"] = 0.3
	context["pressure_enclosure"] = 0.7
	context["pressure_arrivals"] = [{
		"kind": 0,
		"apparent_position": Vector3(1.0, 2.0, 3.0),
		"path_length": 0.4,
		"travel_delay_seconds": 0.02,
		"volume_db": -10.0,
		"band_gain": Vector3.ONE,
		"lowpass_hz": 9000.0,
		"highpass_hz": 30.0,
		"resonance": 0.0,
		"reverb_scale": 1.0,
	}]
	context = AcousticEventPacket.sanitize(context)
	var source_position := Vector3(11.0, 4.0, -2.0)
	var key := LocalAudioPrediction.sequence_key(99)
	var packet := LocalAudioPrediction.build_packet(
		context,
		&"fieldlink_click",
		source_position,
		-5.0,
		0.32,
		key,
		0.5
	)
	var taps: Array = packet.get("early_reflections", [])
	var arrivals: Array = packet.get("pressure_arrivals", [])
	_expect(
		packet.get("sound_id", &"") == &"fieldlink_click"
		and packet.get("source_position", Vector3.ZERO) == source_position
		and packet.get("apparent_position", Vector3.ZERO) == source_position
		and is_zero_approx(float(packet.get("travel_delay_seconds", -1.0)))
		and int(packet.get("local_prediction_key", 0)) == key,
		"a cached listener context becomes an immediate semantic owner packet"
	)
	_expect(
		taps.size() == 1
		and (taps[0] as Dictionary).get("apparent_position", Vector3.ZERO)
		== source_position + Vector3.RIGHT,
		"predicted reflection directions translate with the live owner source"
	)
	_expect(
		arrivals.size() == 1
		and is_equal_approx(
			float((arrivals[0] as Dictionary).get("volume_db", 0.0)),
			-10.0 - 5.0 + linear_to_db(0.5)
		),
		"normalized cached pressure preserves its path while scaling by the real cue energy"
	)


func _test_renderer_reconciliation() -> void:
	var renderer := SpatialAudioRenderer.new()
	root.add_child(renderer)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.5
	var streams: Array[AudioStream] = [stream]
	_expect(
		renderer.register_sound(&"prediction_test", streams),
		"prediction test registers through the ordinary pooled renderer"
	)
	var first_key := LocalAudioPrediction.sequence_key(1)
	var predicted := _base_packet(&"prediction_test", Vector3.ZERO)
	predicted["local_prediction_key"] = first_key
	_expect(
		renderer.submit_predicted(predicted)
		and renderer.has_prediction(first_key),
		"owner prediction starts on the local frame before any authority packet"
	)
	var voices_after_prediction := _started_voice_count(renderer)
	var authoritative := predicted.duplicate(true)
	authoritative["sequence"] = 42
	_expect(
		renderer.submit(authoritative)
		and not renderer.has_prediction(first_key)
		and _started_voice_count(renderer) == voices_after_prediction,
		"the owner's authoritative confirmation consumes the key without replaying the cue"
	)
	var remote := predicted.duplicate(true)
	remote.erase("local_prediction_key")
	remote["sequence"] = 43
	renderer.submit(remote)
	_expect(
		_started_voice_count(renderer) == voices_after_prediction + 1,
		"an ordinary remote event has no owner key and still renders exactly once"
	)
	var authority_first_key := LocalAudioPrediction.gait_step_key(12)
	var authority_first := predicted.duplicate(true)
	authority_first["local_prediction_key"] = authority_first_key
	renderer.submit(authority_first)
	var voices_after_authority_first := _started_voice_count(renderer)
	_expect(
		voices_after_authority_first == voices_after_prediction + 1
		and renderer._pending_authoritative_predictions.has(authority_first_key),
		"host-speed authority waits within the presentation frame instead of committing a late cue"
	)
	_expect(
		renderer.submit_predicted(authority_first)
		and not renderer._pending_authoritative_predictions.has(authority_first_key)
		and _started_voice_count(renderer) == voices_after_authority_first + 1,
		"same-frame host prediction consumes authority-first confirmation and starts exactly one cue"
	)
	var fallback_key := LocalAudioPrediction.gait_step_key(13)
	var fallback_authority := predicted.duplicate(true)
	fallback_authority["local_prediction_key"] = fallback_key
	renderer.submit(fallback_authority)
	var voices_before_fallback := _started_voice_count(renderer)
	(renderer._pending_authoritative_predictions[fallback_key] as Dictionary)[
		"received_usec"
	] = Time.get_ticks_usec() - SpatialAudioRenderer.AUTHORITY_FIRST_PREDICTION_GRACE_USEC
	renderer._process(0.016)
	_expect(
		not renderer._pending_authoritative_predictions.has(fallback_key)
		and _started_voice_count(renderer) == voices_before_fallback + 1,
		"an owner cue with no local prediction falls through to authority after the bounded grace"
	)
	var rejected_key := LocalAudioPrediction.sequence_key(2)
	var delayed := predicted.duplicate(true)
	delayed["local_prediction_key"] = rejected_key
	delayed["travel_delay_seconds"] = 0.5
	renderer.submit_predicted(delayed)
	renderer.reject_prediction(rejected_key)
	_expect(
		not renderer.has_prediction(rejected_key)
		and not _pending_has_key(renderer, rejected_key),
		"server rejection cancels unplayed predicted arrivals without touching gameplay state"
	)
	renderer.reset_session(true)
	renderer.queue_free()
	await process_frame


func _test_runtime_context_gate() -> void:
	var renderer := SpatialAudioRenderer.new()
	root.add_child(renderer)
	var stream := AudioStreamGenerator.new()
	var streams: Array[AudioStream] = [stream]
	renderer.register_sound(&"fieldlink_click", streams)
	var runtime := LocalAudioPredictionRuntime.new()
	var fallback_key := runtime.predict(
		renderer,
		&"fieldlink_click",
		Vector3.ZERO
	)
	_expect(
		fallback_key > 0 and renderer.has_prediction(fallback_key),
		"a new host or client predicts immediately with the allocation-free free-field fallback"
	)
	var context := AcousticEventPacket.sanitize(_base_packet(
		LocalAudioPrediction.CONTEXT_SOUND_ID,
		Vector3.ZERO
	))
	var prediction_key := (
		runtime.predict(renderer, &"fieldlink_click", Vector3.ZERO)
		if runtime.apply_context(context)
		else 0
	)
	_expect(
		prediction_key > 0 and renderer.has_prediction(prediction_key),
		"a valid server context enables the generic local runtime without another geometry solve"
	)
	renderer.reset_session(true)
	renderer.queue_free()
	await process_frame


func _test_network_architecture_contract() -> void:
	var client_source := FileAccess.get_file_as_string("res://scripts/client/client.gd")
	var server_source := FileAccess.get_file_as_string("res://scripts/server/server.gd")
	var replication_source := FileAccess.get_file_as_string(
		"res://scripts/network/server_replication_service.gd"
	)
	var player_source := FileAccess.get_file_as_string(
		"res://scripts/server/server_player.gd"
	)
	_expect(
		client_source.contains("predict_local_player_sound(")
		and client_source.contains("on_local_audio_prediction_rejected")
		and server_source.contains("player_id == safe_origin_player_id")
		and server_source.contains("on_local_audio_prediction_rejected"),
		"server validates actions and returns prediction identity only to the originating listener"
	)
	_expect(
		client_source.contains(
			'@rpc("authority", "unreliable_ordered", "call_local", 7)\nfunc on_local_audio_prediction_context_received'
		)
		and MultiplayerChannelContract.LOCAL_AUDIO_CONTEXT_CHANNEL == 7
		and MultiplayerChannelContract.has_capacity_for(
			MultiplayerChannelContract.LOCAL_AUDIO_CONTEXT_CHANNEL,
			MultiplayerChannelContract.CONFIGURED_STEAM_LANE_COUNT
		),
		"host and clients receive the same replaceable acoustic context on an independent lane"
	)
	_expect(
		NetworkReplicationSchedule.LOCAL_AUDIO_CONTEXT_INTERVAL_TICKS == 4
		and replication_source.contains("build_local_prediction_context(")
		and player_source.contains("current_automatic_audio_prediction_key"),
		"cached listener context runs at 5 Hz while held fire reconciles every deterministic shot"
	)
	_expect(
		client_source.contains("set_local_locomotion_input(move, wants_run)")
		and client_source.contains("request_foot_contact(")
		and server_source.contains("func receive_foot_contact(")
		and player_source.contains("accept_presented_foot_contact(")
		and FileAccess.get_file_as_string(
			"res://scripts/client/player_proxy.gd"
		).contains("var predicts_from_local_intent := is_local_player")
		and FileAccess.get_file_as_string(
			"res://scripts/client/player_proxy.gd"
		).contains("cycle_error = maxf(cycle_error, 0.0)"),
		"host and joining-client gait both advance from current input and reject delayed rollback"
	)


func _base_packet(sound_id: StringName, source_position: Vector3) -> Dictionary:
	return {
		"version": AcousticEventPacket.VERSION,
		"sequence": 1,
		"sound_id": sound_id,
		"source_position": source_position,
		"apparent_position": source_position,
		"direct_distance": 0.35,
		"path_length": 0.35,
		"travel_delay_seconds": 0.0,
		"volume_db": 0.0,
		"band_gain": Vector3.ONE,
		"lowpass_hz": 18000.0,
		"highpass_hz": 20.0,
		"resonance": 0.0,
		"reverb_send": 0.25,
		"reverb_room_size": 0.4,
		"reverb_damping": 0.5,
		"reverb_spread": 0.9,
		"reverb_predelay_msec": 8.0,
		"reverb_predelay_feedback": 0.1,
		"reverb_hipass": 0.05,
		"reverb_decay_seconds": 0.6,
		"environment_enclosure": 0.5,
		"priority": 0.5,
		"modifier_ids": PackedStringArray(),
	}


func _started_voice_count(renderer: SpatialAudioRenderer) -> int:
	var count := 0
	for started_usec: int in renderer._voice_started_usec:
		if started_usec > 0:
			count += 1
	return count


func _pending_has_key(renderer: SpatialAudioRenderer, prediction_key: int) -> bool:
	for packet: Dictionary in renderer._pending_events:
		if int(packet.get("local_prediction_key", 0)) == prediction_key:
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)


func _finish() -> void:
	if failure_count == 0:
		print("Audio prediction tests passed: %d assertions" % assertion_count)
		quit(0)
		return
	push_error(
		"Audio prediction tests failed: %d/%d assertions"
		% [failure_count, assertion_count]
	)
	quit(1)
