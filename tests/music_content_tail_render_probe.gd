extends SceneTree

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const SERVER_COMPLEX_SCENE := preload(
	"res://scenes/server/industrial_acoustic_complex.tscn"
)
const RENDERER_SCRIPT := preload("res://scripts/audio/radio_audio_renderer.gd")
const DEFAULT_TRACK_PATH := (
	"res://assets/sounds/music/not so legally downloaded music/Deutsch Swing/"
	+ "Es geht alles vorüber es geht alles vorbei.mp3"
)
const TRACK_OVERRIDE_ENV := "SCAVANGE_AUDIO_REGRESSION_TRACK"
const PLAYBACK_OFFSET_SECONDS := 72.0
const WARMUP_SECONDS := 3.0
const TAIL_SECONDS := 9.0
const WINDOW_SECONDS := 0.25

var _mix_rate := 44100
var _capture: AudioEffectCapture
var _samples := PackedVector2Array()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mix_rate = roundi(AudioServer.get_mix_rate())
	var track_path := OS.get_environment(TRACK_OVERRIDE_ENV).strip_edges()
	if track_path.is_empty():
		track_path = DEFAULT_TRACK_PATH
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
	var track_index := cluster._playlist.find(track_path)
	if (
		track_index < 0
		or not cluster.apply_fieldlink_command(
			null,
			&"play_track",
			{"track_index": track_index}
		)
	):
		_fail("Valve reference array could not select the regression track")
		return

	var listener_position := (
		complex.global_transform
		* (LAYOUT.VALVE_BUNKER_CENTER + Vector3(0.0, 1.7, 0.0))
	)
	var raw_states: Dictionary = {}
	cluster.append_listener_states(
		raw_states,
		741002,
		listener_position,
		service
	)
	var packets: Array[Dictionary] = []
	for raw_state: Variant in raw_states.values():
		var packet := RadioStatePacket.sanitize(raw_state)
		if packet.is_empty():
			continue
		packet["start_delay_seconds"] = 0.0
		packet["playback_offset_seconds"] = PLAYBACK_OFFSET_SECONDS
		packet["program_playback_offset_seconds"] = PLAYBACK_OFFSET_SECONDS
		packets.append(packet)
	if packets.size() != 4:
		_fail("Valve reference array did not produce four listener packets")
		return

	var stream := load(track_path) as AudioStream
	if stream == null:
		_fail("Content regression track did not import as audio")
		return
	var listener := Camera3D.new()
	listener.name = "MusicTailListener"
	root.add_child(listener)
	listener.global_position = listener_position
	listener.current = true
	await process_frame

	var renderer := RENDERER_SCRIPT.new() as RadioAudioRenderer
	renderer.name = "MusicTailRenderer"
	root.add_child(renderer)
	renderer.call("_ensure_pool")
	renderer.set_process(false)
	var mix_bus_index := _prepare_capture_path()
	_activate_packets(renderer, packets, stream)

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
			renderer.submit_snapshot({})
			pause_issued = true
		await process_frame
	await create_timer(0.1).timeout
	_drain_capture()

	var windows: Array[Dictionary] = []
	var window_count := floori(TAIL_SECONDS / WINDOW_SECONDS)
	for window_index: int in range(window_count):
		var from_seconds := WARMUP_SECONDS + float(window_index) * WINDOW_SECONDS
		windows.append(_window_metrics(
			from_seconds,
			from_seconds + WINDOW_SECONDS
		))
	var pre_pause := _window_metrics(
		WARMUP_SECONDS - WINDOW_SECONDS,
		WARMUP_SECONDS
	)
	var maximum_window_rise_db := 0.0
	for window_index: int in range(1, windows.size()):
		maximum_window_rise_db = maxf(
			maximum_window_rise_db,
			float(windows[window_index]["rms_db"])
			- float(windows[window_index - 1]["rms_db"])
		)
	var shared_late_target: Dictionary = (
		renderer._shared_program_target_packets[0]
		if not renderer._shared_program_target_packets.is_empty()
		else {}
	)
	var passed := (
		windows.size() >= 20
		# The recognizable first echo remains; the cure is not an immediate hard gate.
		and float(windows[0]["rms_db"]) > float(pre_pause["rms_db"]) - 6.0
		# The renderer first fades the still-driven program, then retires the actual undriven return.
		# The large bunker reports an eight-second RT60, so the recognizable musical decay must remain
		# well past the old forced 0.34-second cleanup boundary. Cleanup begins only once that return is
		# genuinely quiet, and must still remove the detached comb/noise floor before bus shutdown.
		and float(shared_late_target.get("reverb_decay_seconds", 0.0)) >= 7.5
		and float(windows[5]["rms_db"]) > -70.0
		and float(windows[11]["rms_db"]) > -90.0
		# Different masters excite the same network with slightly different spectra. Require complete
		# retirement by five seconds instead of treating a -109 dB fourth-second remainder as audible.
		and float(windows[19]["rms_db"]) <= -110.0
		and maximum_window_rise_db <= 0.75
	)
	var summary := {
		"track": track_path,
		"playback_offset_seconds": PLAYBACK_OFFSET_SECONDS,
		"shared_late_target": shared_late_target,
		"pre_pause": pre_pause,
		"tail_windows": windows,
		"maximum_window_rise_db": maximum_window_rise_db,
	}
	print("Music content tail diagnostic: %s" % JSON.stringify(summary))
	if passed:
		print("Music content tail render probe passed")
	else:
		push_error("Music content tail render probe failed")

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
	program: AudioStream
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


func _drain_capture() -> void:
	var available := _capture.get_frames_available()
	if available > 0:
		_samples.append_array(_capture.get_buffer(available))


func _window_metrics(from_seconds: float, to_seconds: float) -> Dictionary:
	var from_frame := clampi(
		roundi(from_seconds * float(_mix_rate)),
		1,
		_samples.size()
	)
	var to_frame := clampi(
		roundi(to_seconds * float(_mix_rate)),
		from_frame,
		_samples.size()
	)
	if to_frame <= from_frame:
		return {
			"rms_db": -120.0,
			"roughness": 0.0,
			"stereo_difference": 0.0,
		}
	var square_sum := 0.0
	var difference_sum := 0.0
	var stereo_difference_sum := 0.0
	for frame_index: int in range(from_frame, to_frame):
		var sample := _samples[frame_index]
		var previous := _samples[frame_index - 1]
		square_sum += sample.x * sample.x + sample.y * sample.y
		var difference := sample - previous
		difference_sum += (
			difference.x * difference.x + difference.y * difference.y
		)
		var stereo_difference := sample.x - sample.y
		stereo_difference_sum += stereo_difference * stereo_difference
	var divisor := float((to_frame - from_frame) * 2)
	var rms := sqrt(square_sum / divisor)
	return {
		"rms_db": linear_to_db(maxf(rms, 0.000001)),
		"roughness": sqrt(difference_sum / divisor) / maxf(rms, 0.000001),
		"stereo_difference": (
			sqrt(stereo_difference_sum / float(to_frame - from_frame))
			/ maxf(rms, 0.000001)
		),
	}


func _fail(message: String) -> void:
	push_error("Music content tail render probe failed: %s" % message)
	quit(1)
