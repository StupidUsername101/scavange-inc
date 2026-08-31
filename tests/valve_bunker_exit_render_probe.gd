extends SceneTree

## Render-level counterpart to bunker_entrance_reverb_motion_probe.gd.
##
## The state probe proves that authoritative and presented wet/direct ratios agree. This probe
## additionally fills the real Valve late-reverb delay network, walks the listener through the
## doorway at the fastest supported regression speed, and captures that processed return after its
## presentation gain. It therefore catches indoor samples that survive in DSP even after the input
## player's pre-effect level has moved outdoors.

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const SERVER_COMPLEX_SCENE := preload(
	"res://scenes/server/industrial_acoustic_complex.tscn"
)
const RENDERER_SCRIPT := preload("res://scripts/audio/radio_audio_renderer.gd")
const SNAPSHOT_SECONDS := 0.05
const WARMUP_SECONDS := 1.5
const SETTLE_SECONDS := 0.75
const SPEED_MPS := 14.0
const START_INSIDE_METERS := 4.0
const END_OUTSIDE_METERS := 6.0
const END_LATERAL_METERS := 4.0
const ANALYSIS_WINDOW_SECONDS := 0.10
const MAX_PRESENTATION_RATIO_ERROR_DB := 1.0
const MAX_POST_EXIT_LATE_RISE_DB := 1.5
const MIN_RENDERED_LATE_DROP_DB := 30.0
const MAX_DERIVATIVE_OUTLIER_SCORE := 4.0
const LATE_CAPTURE_BUS := &"ValveBunkerLateCapture"

var _mix_rate := 44100
var _mix_capture: AudioEffectCapture
var _late_capture: AudioEffectCapture
var _mix_samples := PackedVector2Array()
var _late_samples := PackedVector2Array()
var _mix_bus_index := -1
var _late_bus_index := -1


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
	if (
		cluster == null
		or not cluster.set_powered(true)
		or cluster._playlist.is_empty()
		or not cluster.apply_fieldlink_command(
			null,
			&"play_track",
			{"track_index": 0}
		)
	):
		_fail("Valve reference array could not start its render program")
		return

	var trace := _build_trace(cluster, service, 741003)
	if trace.size() < 8:
		_fail("Valve reference exit trace could not be built")
		return
	var listener := Camera3D.new()
	listener.name = "ValveExitRenderListener"
	root.add_child(listener)
	listener.current = true
	listener.global_position = trace[0]["listener_position"]
	await process_frame

	var renderer := RENDERER_SCRIPT.new() as RadioAudioRenderer
	renderer.name = "ValveExitRenderRenderer"
	root.add_child(renderer)
	renderer.set_process(false)
	_prepare_capture_path(renderer)
	var movement_seconds := float(trace.size() - 1) * SNAPSHOT_SECONDS
	var total_seconds := WARMUP_SECONDS + movement_seconds + SETTLE_SECONDS
	var program := _make_test_program(total_seconds + 1.0)
	_apply_trace_entry(renderer, trace[0], true, program)

	var trace_index := 0
	var elapsed := 0.0
	var previous_elapsed := 0.0
	var next_trace_update := WARMUP_SECONDS + SNAPSHOT_SECONDS
	while elapsed < total_seconds:
		_drain_captures()
		elapsed = float(_mix_samples.size()) / float(_mix_rate)
		var delta := maxf(elapsed - previous_elapsed, 0.0)
		if delta > 0.0:
			renderer._process(delta)
		previous_elapsed = elapsed
		while trace_index + 1 < trace.size() and elapsed >= next_trace_update:
			trace_index += 1
			var entry: Dictionary = trace[trace_index]
			listener.global_position = entry["listener_position"]
			_apply_trace_entry(renderer, entry, false, program)
			next_trace_update += SNAPSHOT_SECONDS
		await process_frame
	await create_timer(0.1).timeout
	_drain_captures()

	var doorway_fraction := START_INSIDE_METERS / (
		START_INSIDE_METERS + END_OUTSIDE_METERS
	)
	var doorway_seconds := WARMUP_SECONDS + movement_seconds * doorway_fraction
	var inside_db := _window_rms_db(
		_late_samples,
		WARMUP_SECONDS - 0.25,
		WARMUP_SECONDS
	)
	var far_outside_db := _window_rms_db(
		_late_samples,
		total_seconds - 0.25,
		total_seconds
	)
	var maximum_post_exit_rise_db := _maximum_window_rise_db(
		_late_samples,
		doorway_seconds,
		total_seconds
	)
	var derivative_score := _derivative_outlier_score(
		_mix_samples,
		roundi(WARMUP_SECONDS * float(_mix_rate))
	)
	var debug := renderer.get_debug_state()
	# The deterministic state probe owns per-snapshot ratio tracking. The dummy audio driver can
	# cross multiple 50 ms boundaries between main-thread frames, so this render probe checks the
	# final settled ratio and reserves its time-domain assertions for captured PCM.
	var final_ratio_error := _presented_ratio_error(renderer)
	var result := {
		"frames": _mix_samples.size(),
		"late_frames": _late_samples.size(),
		"speed_mps": SPEED_MPS,
		"exit_angle_degrees": rad_to_deg(atan2(
			END_LATERAL_METERS,
			START_INSIDE_METERS + END_OUTSIDE_METERS
		)),
		"movement_seconds": movement_seconds,
		"doorway_seconds": doorway_seconds,
		"inside_late_rms_db": inside_db,
		"far_outside_late_rms_db": far_outside_db,
		"rendered_late_drop_db": inside_db - far_outside_db,
		"maximum_post_exit_late_rise_db": maximum_post_exit_rise_db,
		"settled_wet_to_direct_tracking_error_db": final_ratio_error,
		"mix_derivative_outlier_score": derivative_score,
		"active_shared_late_fields": int(
			debug.get("active_shared_late_field_count", 0)
		),
	}
	var passed := (
		_mix_samples.size() >= roundi(total_seconds * float(_mix_rate) * 0.85)
		and _late_samples.size() >= roundi(total_seconds * float(_mix_rate) * 0.85)
		and inside_db > -90.0
		and inside_db - far_outside_db >= MIN_RENDERED_LATE_DROP_DB
		and maximum_post_exit_rise_db <= MAX_POST_EXIT_LATE_RISE_DB
		and final_ratio_error <= MAX_PRESENTATION_RATIO_ERROR_DB
		and derivative_score <= MAX_DERIVATIVE_OUTLIER_SCORE
		and int(result["active_shared_late_fields"]) == 1
	)
	print("Valve bunker live-exit render: %s" % JSON.stringify(result))
	if passed:
		print("Valve bunker live-exit render probe passed")
	else:
		push_error("Valve bunker live-exit render probe failed")

	service.forget_listener(741003)
	renderer.reset_session()
	# Let the audio thread observe the stopped streams before dropping the generated WAV. Quitting in
	# the same frame leaves four playback handles alive and hides real lifecycle leaks in test output.
	program = null
	await create_timer(0.1).timeout
	_restore_capture_path(renderer)
	renderer.free()
	listener.free()
	service.free()
	complex.free()
	await process_frame
	quit(0 if passed else 1)


func _build_trace(
	cluster: ServerSpeakerCluster,
	service: ServerAcousticService,
	listener_id: int
) -> Array[Dictionary]:
	var half_width := LAYOUT.LARGE_BUNKER_WIDTH * 0.5
	var from := Vector3(
		half_width - START_INSIDE_METERS,
		1.7,
		0.0
	)
	var to := Vector3(
		half_width + END_OUTSIDE_METERS,
		1.7,
		END_LATERAL_METERS
	)
	var sample_count := ceili(
		from.distance_to(to) / (SPEED_MPS * SNAPSHOT_SECONDS)
	) + 1
	var result: Array[Dictionary] = []
	for sample_index: int in range(sample_count):
		var ratio := float(sample_index) / float(maxi(sample_count - 1, 1))
		var local_position := LAYOUT.VALVE_BUNKER_CENTER + from.lerp(to, ratio)
		var listener_position := (
			cluster.get_parent_node_3d().global_transform * local_position
		)
		var raw_states: Dictionary = {}
		cluster.append_listener_states(
			raw_states,
			listener_id,
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
		if packets.size() == 4:
			result.append({
				"listener_position": listener_position,
				"packets": packets,
			})
	return result


func _apply_trace_entry(
	renderer: RadioAudioRenderer,
	entry: Dictionary,
	first_entry: bool,
	program: AudioStreamWAV
) -> void:
	var packets: Array[Dictionary] = []
	for source_packet: Dictionary in entry["packets"]:
		packets.append(source_packet.duplicate(false))
	renderer._prepare_shared_program_mix(packets)
	packets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("item_id", -1)) < int(b.get("item_id", -1))
	)
	for packet_index: int in range(packets.size()):
		var packet := packets[packet_index]
		var item_id := int(packet["item_id"])
		var slot_index := int(renderer._slot_by_item_id.get(item_id, -1))
		if first_entry:
			slot_index = packet_index
			renderer._bind_slot(slot_index, item_id)
		if slot_index < 0:
			continue
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
		if not first_entry:
			continue
		var player := renderer._players[slot_index]
		player.stream = program
		player.global_position = renderer._target_positions[slot_index]
		player.volume_db = renderer._target_volumes_db[slot_index]
		renderer._effect_racks[slot_index].prepare_for_input()
		renderer._effect_racks[slot_index].apply_acoustic(
			packet,
			0.0,
			true
		)
		player.play()
	if first_entry and not packets.is_empty():
		var group_packet: Dictionary = packets[0]
		renderer._activate_shared_program_late_field(
			int(group_packet.get("shared_program_group_id", -1)),
			program,
			group_packet,
			0.0
		)


func _prepare_capture_path(renderer: RadioAudioRenderer) -> void:
	renderer._ensure_continuous_mix_bus()
	_mix_bus_index = AudioServer.get_bus_index(
		RadioAudioRenderer.CONTINUOUS_MIX_BUS
	)
	AudioServer.add_bus()
	_late_bus_index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_late_bus_index, LATE_CAPTURE_BUS)
	AudioServer.set_bus_send(
		_late_bus_index,
		RadioAudioRenderer.CONTINUOUS_MIX_BUS
	)
	_late_capture = AudioEffectCapture.new()
	_late_capture.buffer_length = 5.0
	AudioServer.add_bus_effect(_late_bus_index, _late_capture)
	renderer._ensure_pool()
	for rack: SpatialAudioEffectRack in renderer._shared_program_racks:
		AudioServer.set_bus_send(rack.bus_index, LATE_CAPTURE_BUS)
	_mix_capture = AudioEffectCapture.new()
	_mix_capture.buffer_length = 5.0
	AudioServer.add_bus_effect(_mix_bus_index, _mix_capture)


func _restore_capture_path(renderer: RadioAudioRenderer) -> void:
	for rack: SpatialAudioEffectRack in renderer._shared_program_racks:
		AudioServer.set_bus_send(
			rack.bus_index,
			RadioAudioRenderer.CONTINUOUS_MIX_BUS
		)
	if _mix_bus_index >= 0 and AudioServer.get_bus_effect_count(_mix_bus_index) > 0:
		AudioServer.remove_bus_effect(
			_mix_bus_index,
			AudioServer.get_bus_effect_count(_mix_bus_index) - 1
		)
	if _late_bus_index >= 0:
		AudioServer.remove_bus(_late_bus_index)


func _make_test_program(duration_seconds: float) -> AudioStreamWAV:
	var frame_count := ceili(duration_seconds * float(_mix_rate))
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	for frame_index: int in range(frame_count):
		var time_seconds := float(frame_index) / float(_mix_rate)
		var value := (
			sin(TAU * 83.0 * time_seconds) * 0.18
			+ sin(TAU * 227.0 * time_seconds + 0.3) * 0.14
			+ sin(TAU * 617.0 * time_seconds + 0.7) * 0.10
			+ sin(TAU * 1901.0 * time_seconds + 1.1) * 0.07
			+ sin(TAU * 4877.0 * time_seconds + 1.7) * 0.04
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


func _drain_captures() -> void:
	if _mix_capture != null:
		var frames := _mix_capture.get_frames_available()
		if frames > 0:
			_mix_samples.append_array(_mix_capture.get_buffer(frames))
	if _late_capture != null:
		var frames := _late_capture.get_frames_available()
		if frames > 0:
			_late_samples.append_array(_late_capture.get_buffer(frames))


func _presented_ratio_error(renderer: RadioAudioRenderer) -> float:
	for group_slot: int in range(renderer._shared_program_bus_group_ids.size()):
		if renderer._shared_program_group_active[group_slot] == 0:
			continue
		return absf(
			renderer._shared_program_presented_wet_to_direct_db[group_slot]
			- renderer._shared_program_target_ratio_db(group_slot)
		)
	return 0.0


func _window_rms_db(
	samples: PackedVector2Array,
	from_seconds: float,
	to_seconds: float
) -> float:
	var from_frame := clampi(
		roundi(from_seconds * float(_mix_rate)),
		0,
		samples.size()
	)
	var to_frame := clampi(
		roundi(to_seconds * float(_mix_rate)),
		from_frame,
		samples.size()
	)
	if to_frame <= from_frame:
		return -120.0
	var square_sum := 0.0
	for frame_index: int in range(from_frame, to_frame):
		var sample := samples[frame_index]
		square_sum += sample.x * sample.x + sample.y * sample.y
	return linear_to_db(maxf(
		sqrt(square_sum / float((to_frame - from_frame) * 2)),
		0.000001
	))


func _maximum_window_rise_db(
	samples: PackedVector2Array,
	from_seconds: float,
	to_seconds: float
) -> float:
	var maximum_rise := 0.0
	var previous_db := INF
	var cursor := from_seconds
	while cursor + ANALYSIS_WINDOW_SECONDS <= to_seconds + 0.000001:
		var window_db := _window_rms_db(
			samples,
			cursor,
			cursor + ANALYSIS_WINDOW_SECONDS
		)
		if previous_db < INF:
			maximum_rise = maxf(maximum_rise, window_db - previous_db)
		previous_db = window_db
		cursor += ANALYSIS_WINDOW_SECONDS
	return maximum_rise


func _derivative_outlier_score(
	samples: PackedVector2Array,
	start_frame: int
) -> float:
	var derivatives := PackedFloat32Array()
	for frame_index: int in range(maxi(start_frame, 1), samples.size()):
		var difference := samples[frame_index] - samples[frame_index - 1]
		derivatives.append(maxf(absf(difference.x), absf(difference.y)))
	if derivatives.is_empty():
		return INF
	var maximum := 0.0
	for value: float in derivatives:
		maximum = maxf(maximum, value)
	derivatives.sort()
	var percentile_index := clampi(
		floori(float(derivatives.size() - 1) * 0.999),
		0,
		derivatives.size() - 1
	)
	return maximum / maxf(derivatives[percentile_index], 0.000001)


func _fail(message: String) -> void:
	push_error("Valve bunker live-exit render: %s" % message)
	quit(1)
