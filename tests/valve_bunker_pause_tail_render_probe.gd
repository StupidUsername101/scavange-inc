extends SceneTree

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const SERVER_COMPLEX_SCENE := preload(
	"res://scenes/server/industrial_acoustic_complex.tscn"
)
const RENDERER_SCRIPT := preload("res://scripts/audio/radio_audio_renderer.gd")
const WARMUP_SECONDS := 1.5
const TAIL_SECONDS := 9.5
const WINDOW_SECONDS := 0.5
const MIN_AUDIBLE_TAIL_DROP_DB := 1.5
const MAX_LATE_WINDOW_RISE_DB := 1.0
const MIN_FINAL_DECAY_DB := 38.0

var _mix_rate := 44100
var _capture: AudioEffectCapture
var _samples := PackedVector2Array()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mix_rate = roundi(AudioServer.get_mix_rate())
	var complex := SERVER_COMPLEX_SCENE.instantiate() as Node3D
	root.add_child(complex)
	await process_frame
	await physics_frame
	var cluster := complex.get_node_or_null(
		"ValveReferenceBunkerSpeakerArray"
	) as ServerSpeakerCluster
	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(complex)
	await process_frame
	await physics_frame
	if cluster == null or not cluster.set_powered(true):
		_fail("Valve reference array could not start")
		return

	var listener_position := (
		complex.global_transform
		* (LAYOUT.VALVE_BUNKER_CENTER + Vector3(0.0, 1.7, 0.0))
	)
	var raw_states: Dictionary = {}
	cluster.append_listener_states(
		raw_states,
		741001,
		listener_position,
		service
	)
	var packets: Array[Dictionary] = []
	for raw_state: Variant in raw_states.values():
		var packet := RadioStatePacket.sanitize(raw_state)
		if packet.is_empty():
			continue
		packet["start_delay_seconds"] = 0.0
		packet["playback_offset_seconds"] = 0.0
		packet["program_playback_offset_seconds"] = 0.0
		packets.append(packet)
	if packets.size() != 4:
		_fail("Valve reference array did not produce four listener packets")
		return

	var listener := Camera3D.new()
	listener.name = "ValvePauseTailListener"
	root.add_child(listener)
	listener.global_position = listener_position
	listener.current = true
	await process_frame

	var renderer := RENDERER_SCRIPT.new() as RadioAudioRenderer
	renderer.name = "ValvePauseTailRenderer"
	root.add_child(renderer)
	renderer.call("_ensure_pool")
	renderer.set_process(false)
	var mix_bus_index := _prepare_capture_path()
	var program := _make_test_program(WARMUP_SECONDS + TAIL_SECONDS + 1.0)
	_activate_packets(renderer, packets, program)
	var static_was_silent := (
		int(renderer.get_debug_state().get("active_static_count", -1)) == 0
	)

	var elapsed := 0.0
	var previous_elapsed := 0.0
	var pause_issued := false
	while elapsed < WARMUP_SECONDS + TAIL_SECONDS:
		_drain_capture()
		elapsed = float(_samples.size()) / float(_mix_rate)
		var delta := maxf(elapsed - previous_elapsed, 0.0)
		if delta > 0.0:
			renderer._process(delta)
		previous_elapsed = elapsed
		if not pause_issued and elapsed >= WARMUP_SECONDS:
			# This is the exact client transition produced when the authoritative paused array omits
			# its listener states. Dry voices fade out; populated room delay lines may decay naturally.
			renderer.submit_snapshot({})
			pause_issued = true
		await process_frame
	await create_timer(0.1).timeout
	_drain_capture()

	var pre_pause_db := _window_rms_db(
		WARMUP_SECONDS - WINDOW_SECONDS,
		WARMUP_SECONDS
	)
	var tail_windows := PackedFloat32Array([
		_window_rms_db(WARMUP_SECONDS + 0.5, WARMUP_SECONDS + 1.0),
		_window_rms_db(WARMUP_SECONDS + 2.0, WARMUP_SECONDS + 2.5),
		_window_rms_db(WARMUP_SECONDS + 4.0, WARMUP_SECONDS + 4.5),
		_window_rms_db(WARMUP_SECONDS + 7.5, WARMUP_SECONDS + 8.0),
		_window_rms_db(WARMUP_SECONDS + 8.75, WARMUP_SECONDS + 9.25),
	])
	var maximum_window_rise_db := 0.0
	for window_index: int in range(1, tail_windows.size()):
		maximum_window_rise_db = maxf(
			maximum_window_rise_db,
			tail_windows[window_index] - tail_windows[window_index - 1]
		)
	var program_players_stopped := true
	for player: AudioStreamPlayer3D in renderer._players:
		program_players_stopped = program_players_stopped and not player.playing
	for player: AudioStreamPlayer in renderer._shared_program_players:
		program_players_stopped = program_players_stopped and not player.playing
	var debug := renderer.get_debug_state()
	var result := {
		"frames": _samples.size(),
		"pre_pause_db": pre_pause_db,
		"tail_windows_db": tail_windows,
		"maximum_late_window_rise_db": maximum_window_rise_db,
		"final_decay_db": pre_pause_db - tail_windows[-1],
		"static_was_silent": static_was_silent,
		"active_static_after_tail": int(debug.get("active_static_count", -1)),
		"program_players_stopped": program_players_stopped,
	}
	var passed := (
		pause_issued
		and static_was_silent
		and int(debug.get("active_static_count", -1)) == 0
		and program_players_stopped
		and tail_windows[0] < pre_pause_db - MIN_AUDIBLE_TAIL_DROP_DB
		and maximum_window_rise_db <= MAX_LATE_WINDOW_RISE_DB
		and pre_pause_db - tail_windows[-1] >= MIN_FINAL_DECAY_DB
	)
	print("Valve bunker pause-tail render: %s" % JSON.stringify(result))
	if passed:
		print("Valve bunker pause-tail render probe passed")
	else:
		push_error("Valve bunker pause-tail render probe failed")

	renderer.reset_session()
	renderer.free()
	listener.free()
	service.free()
	complex.free()
	AudioServer.remove_bus_effect(
		mix_bus_index,
		AudioServer.get_bus_effect_count(mix_bus_index) - 1
	)
	quit(0 if passed else 1)


func _activate_packets(
	renderer: RadioAudioRenderer,
	packets: Array[Dictionary],
	program: AudioStreamWAV
) -> void:
	renderer._prepare_shared_program_mix(packets)
	packets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("item_id", -1)) < int(b.get("item_id", -1))
	)
	for slot_index: int in range(packets.size()):
		var packet := packets[slot_index]
		var item_id := int(packet["item_id"])
		renderer._bind_slot(slot_index, item_id)
		renderer._route_slot_to_shared_program(
			slot_index,
			int(packet.get("shared_program_group_id", -1))
		)
		renderer._target_positions[slot_index] = packet.get(
			"apparent_position",
			Vector3.ZERO
		)
		renderer._target_volumes_db[slot_index] = float(
			packet.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB)
		)
		renderer._effect_target_packets[slot_index] = packet
		renderer._pending_packets[slot_index] = packet
		renderer._pending_streams[slot_index] = program
		renderer._slot_pending_revisions[slot_index] = int(packet["revision"])
		renderer._slot_pending_start_usec[slot_index] = 0
		renderer._activate_pending(slot_index)


func _prepare_capture_path() -> int:
	var mix_bus_index := AudioServer.get_bus_index(
		RadioAudioRenderer.CONTINUOUS_MIX_BUS
	)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = WARMUP_SECONDS + TAIL_SECONDS + 2.0
	AudioServer.add_bus_effect(mix_bus_index, _capture)
	return mix_bus_index


func _make_test_program(duration_seconds: float) -> AudioStreamWAV:
	var frame_count := ceili(duration_seconds * float(_mix_rate))
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	for frame_index: int in range(frame_count):
		var time_seconds := float(frame_index) / float(_mix_rate)
		var value := (
			sin(TAU * 173.0 * time_seconds) * 0.20
			+ sin(TAU * 463.0 * time_seconds + 0.4) * 0.14
			+ sin(TAU * 1523.0 * time_seconds + 1.1) * 0.09
		)
		var encoded := clampi(roundi(value * 32767.0), -32768, 32767)
		data.encode_s16(frame_index * 4, encoded)
		data.encode_s16(frame_index * 4 + 2, encoded)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _mix_rate
	stream.stereo = true
	stream.data = data
	return stream


func _drain_capture() -> void:
	if _capture == null:
		return
	var available := _capture.get_frames_available()
	if available > 0:
		_samples.append_array(_capture.get_buffer(available))


func _window_rms_db(from_seconds: float, to_seconds: float) -> float:
	var from_frame := clampi(
		roundi(from_seconds * float(_mix_rate)),
		0,
		_samples.size()
	)
	var to_frame := clampi(
		roundi(to_seconds * float(_mix_rate)),
		from_frame,
		_samples.size()
	)
	if to_frame <= from_frame:
		return -120.0
	var square_sum := 0.0
	for frame_index: int in range(from_frame, to_frame):
		var sample := _samples[frame_index]
		square_sum += sample.x * sample.x + sample.y * sample.y
	var rms := sqrt(square_sum / float((to_frame - from_frame) * 2))
	return linear_to_db(maxf(rms, 0.000001))


func _fail(message: String) -> void:
	push_error("Valve bunker pause-tail render probe failed: %s" % message)
	quit(1)
