extends SceneTree

const LAYOUT := preload("res://scripts/world/speaker_cluster_demo_layout.gd")
const RENDERER_SCRIPT := preload("res://scripts/audio/radio_audio_renderer.gd")
const TRACE_SAMPLE_SPACING := 0.05
const TRACE_UPDATE_SECONDS := 0.05
const ANALYSIS_WINDOW_SECONDS := 0.20
const WARMUP_SECONDS := 0.65
const TAIL_SECONDS := 0.35
const MAX_DERIVATIVE_OUTLIER_SCORE := 3.0
const MAX_WINDOW_LEVEL_STEP_DB := 1.5
const MAX_WINDOW_BAND_STEP_DB := 2.0
const MAX_MASKED_BAND_OFFSET_DB := 24.0
const MAX_STEREO_BALANCE_STEP_DB := 1.25
const MAX_CORRELATION_STEP := 0.35
const MAX_LIMITER_REDUCTION_DB := 6.0
const MAX_OUTPUT_PEAK := 1.02
const MIN_OUTPUT_RMS := 0.0005
const TEST_TONES_HZ := [73.0, 191.0, 521.0, 1877.0, 5431.0]

var _mix_rate := 44100
var _capture: AudioEffectCapture
var _pre_limiter_capture: AudioEffectCapture
var _samples := PackedVector2Array()
var _pre_limiter_samples := PackedVector2Array()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mix_rate = roundi(AudioServer.get_mix_rate())
	var server := root.get_node_or_null("Server")
	if server == null:
		_fail("server autoload is unavailable")
		return
	server.call("spawn_server_world")
	await process_frame
	await process_frame
	await physics_frame
	var server_world := server.get("server_world") as Node3D
	var cluster := server_world.get_node_or_null(
		"SpeakerClusterDemo"
	) as ServerSpeakerCluster
	var service := server.get("acoustic_service") as ServerAcousticService
	if cluster == null or service == null:
		_fail("authoritative PA or acoustic service is unavailable")
		return
	if not cluster.set_powered(true):
		_fail("authoritative PA could not start its explicit test program")
		return

	var trace := _build_bunker_entrance_trace(cluster, service)
	if trace.size() < 200:
		_fail("the dense bunker-entrance trace could not be built")
		return

	var listener := Camera3D.new()
	listener.name = "PAFourSpeakerTestListener"
	root.add_child(listener)
	listener.current = true
	await process_frame
	var renderer := RENDERER_SCRIPT.new() as RadioAudioRenderer
	renderer.name = "PAFourSpeakerTestRenderer"
	root.add_child(renderer)
	renderer.call("_ensure_pool")
	# The dummy audio driver can render several blocks between two main-thread frames. Advance the
	# production smoother from captured audio time so controller attack/release is deterministic and
	# the test measures DSP behavior rather than host scheduling.
	renderer.set_process(false)
	var mix_bus_index := _prepare_capture_path(
		float(trace.size()) * TRACE_UPDATE_SECONDS
		+ WARMUP_SECONDS
		+ TAIL_SECONDS
		+ 1.0
	)
	var program := _make_test_program(
		float(trace.size()) * TRACE_UPDATE_SECONDS
		+ WARMUP_SECONDS
		+ TAIL_SECONDS
		+ 0.5
	)
	var first_entry: Dictionary = trace[0]
	listener.global_position = first_entry["listener_position"]
	_apply_trace_entry(renderer, first_entry, true, program)

	var trace_index := 0
	var elapsed := 0.0
	var next_trace_update := WARMUP_SECONDS + TRACE_UPDATE_SECONDS
	var stop_at := (
		WARMUP_SECONDS
		+ float(trace.size() - 1) * TRACE_UPDATE_SECONDS
		+ TAIL_SECONDS
	)
	while elapsed < stop_at:
		# Drive the trace from captured audio frames rather than render-loop wall time. The audio
		# mixer runs independently of headless frame scheduling; wall-time updates made the same
		# transition land in different FFT windows and turned a deterministic guard into a flaky one.
		_drain_captures()
		var captured_elapsed := float(_samples.size()) / float(_mix_rate)
		var captured_delta := maxf(captured_elapsed - elapsed, 0.0)
		if captured_delta > 0.0:
			renderer._process(captured_delta)
		elapsed = captured_elapsed
		while (
			trace_index + 1 < trace.size()
			and elapsed >= next_trace_update
		):
			trace_index += 1
			var entry: Dictionary = trace[trace_index]
			listener.global_position = entry["listener_position"]
			_apply_trace_entry(renderer, entry, false, program)
			next_trace_update += TRACE_UPDATE_SECONDS
		await process_frame
	await create_timer(0.10).timeout
	_drain_captures()

	var result := _analyze_render()
	var renderer_debug := renderer.get_debug_state()
	result["active_shared_late_fields"] = int(
		renderer_debug.get("active_shared_late_field_count", 0)
	)
	result["shared_program_slot_reverbs"] = int(
		renderer_debug.get("shared_program_slot_reverb_count", -1)
	)
	result["shared_program_direct_voices"] = int(
		renderer_debug.get("shared_program_direct_mix_count", 0)
	)
	var passed := (
		int(result.get("frames", 0)) >= roundi(
			(float(trace.size()) * TRACE_UPDATE_SECONDS + WARMUP_SECONDS)
			* float(_mix_rate) * 0.85
		)
		and float(result.get("derivative_score_l", INF))
		<= MAX_DERIVATIVE_OUTLIER_SCORE
		and float(result.get("derivative_score_r", INF))
		<= MAX_DERIVATIVE_OUTLIER_SCORE
		and float(result.get("max_window_level_step_db", INF))
		<= MAX_WINDOW_LEVEL_STEP_DB
		and float(result.get("max_window_band_step_db", INF))
		<= MAX_WINDOW_BAND_STEP_DB
		and float(result.get("max_stereo_balance_step_db", INF))
		<= MAX_STEREO_BALANCE_STEP_DB
		and float(result.get("max_correlation_step", INF))
		<= MAX_CORRELATION_STEP
		and float(result.get("limiter_reduction_db", INF))
		<= MAX_LIMITER_REDUCTION_DB
		and float(result.get("output_peak", INF)) <= MAX_OUTPUT_PEAK
		and float(result.get("output_rms", 0.0)) >= MIN_OUTPUT_RMS
		and int(result.get("active_shared_late_fields", -1)) == 0
		and int(result.get("shared_program_slot_reverbs", -1)) == 0
		and int(result.get("shared_program_direct_voices", 0)) == 4
		and bool(result.get("finite", false))
	)
	print("PA four-speaker rendered trace: %s" % JSON.stringify(result))
	if passed:
		print("PA four-speaker rendered continuity test passed")
	else:
		push_error("PA four-speaker rendered continuity test failed")

	for player: AudioStreamPlayer3D in renderer._players:
		player.stop()
	renderer.reset_session()
	renderer.free()
	listener.free()
	AudioServer.remove_bus_effect(
		mix_bus_index,
		AudioServer.get_bus_effect_count(mix_bus_index) - 1
	)
	AudioServer.remove_bus_effect(mix_bus_index, 0)
	quit(0 if passed else 1)


func _build_bunker_entrance_trace(
	cluster: ServerSpeakerCluster,
	service: ServerAcousticService
) -> Array[Dictionary]:
	const LISTENER_ID := 19991
	# The entrance is where one listener crosses from the exterior field into the geometry-routed
	# indoor response while the wall-mounted and interior cabinets remain one synchronized PA. The
	# bunker A/B profile intentionally omits its synthesized late return, so this trace proves that
	# the remaining four direct voices stay continuous and do not quietly regain per-cabinet reverb.
	var endpoints := PackedVector3Array([
		Vector3(LAYOUT.DOOR_CENTER_X, 1.55, -12.0),
		Vector3(LAYOUT.DOOR_CENTER_X, 1.55, 1.0),
	])
	var emitter_ids := cluster.get_emitter_ids()
	var trace: Array[Dictionary] = []
	for pass_index: int in range(2):
		var from := endpoints[pass_index]
		var to := endpoints[1 - pass_index]
		var count := ceili(from.distance_to(to) / TRACE_SAMPLE_SPACING) + 1
		for sample_index: int in range(count):
			var ratio := float(sample_index) / float(maxi(count - 1, 1))
			var listener_position := cluster.global_transform * from.lerp(to, ratio)
			var raw_states: Dictionary = {}
			cluster.append_listener_states(
				raw_states,
				LISTENER_ID,
				listener_position,
				service
			)
			var states: Dictionary = {}
			for emitter_id: int in emitter_ids:
				var state: Dictionary = raw_states.get(emitter_id, {})
				if state.is_empty():
					continue
				states[emitter_id] = state.duplicate(false)
			if states.size() == emitter_ids.size():
				trace.append({
					"listener_position": listener_position,
					"states": states,
				})
	return trace


func _prepare_capture_path(buffer_seconds: float) -> int:
	var mix_bus_index := AudioServer.get_bus_index(
		RadioAudioRenderer.CONTINUOUS_MIX_BUS
	)
	_pre_limiter_capture = AudioEffectCapture.new()
	_pre_limiter_capture.buffer_length = buffer_seconds
	AudioServer.add_bus_effect(mix_bus_index, _pre_limiter_capture, 0)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = buffer_seconds
	# Capture effects pass their input through unchanged. Keeping both taps on the production mix
	# bus avoids Godot's acyclic bus-send ordering constraint: pre tap -> hard limiter -> post tap.
	AudioServer.add_bus_effect(mix_bus_index, _capture)
	return mix_bus_index


func _make_test_program(duration_seconds: float) -> AudioStreamWAV:
	var frame_count := ceili(duration_seconds * float(_mix_rate))
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	for frame_index: int in range(frame_count):
		var time_seconds := float(frame_index) / float(_mix_rate)
		var modulation := 0.78 + 0.22 * sin(TAU * 0.43 * time_seconds)
		var value := (
			sin(TAU * TEST_TONES_HZ[0] * time_seconds) * 0.19
			+ sin(TAU * TEST_TONES_HZ[1] * time_seconds + 0.3) * 0.16
			+ sin(TAU * TEST_TONES_HZ[2] * time_seconds + 0.8) * 0.13
			+ sin(TAU * TEST_TONES_HZ[3] * time_seconds + 1.2) * 0.09
			+ sin(TAU * TEST_TONES_HZ[4] * time_seconds + 1.7) * 0.06
		) * modulation
		var encoded := clampi(roundi(value * 32767.0), -32768, 32767)
		data.encode_s16(frame_index * 4, encoded)
		data.encode_s16(frame_index * 4 + 2, encoded)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = _mix_rate
	stream.stereo = true
	stream.data = data
	return stream


func _apply_trace_entry(
	renderer: RadioAudioRenderer,
	entry: Dictionary,
	first_entry: bool,
	program: AudioStreamWAV
) -> void:
	var states: Dictionary = entry["states"]
	var packets: Array[Dictionary] = []
	for state: Dictionary in states.values():
		packets.append(state.duplicate(false))
	renderer._prepare_shared_program_mix(packets)
	packets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("item_id", -1)) < int(b.get("item_id", -1))
	)
	for slot_index: int in range(packets.size()):
		var packet := packets[slot_index]
		var item_id := int(packet.get("item_id", -1))
		if first_entry:
			renderer._bind_slot(slot_index, item_id)
		renderer._route_slot_to_shared_program(
			slot_index,
			int(packet.get("shared_program_group_id", -1))
		)
		renderer._target_positions[slot_index] = packet.get(
			"apparent_position",
			Vector3.ZERO
		)
		renderer._target_volumes_db[slot_index] = float(packet.get("volume_db", -80.0))
		renderer._effect_target_packets[slot_index] = packet
		if not first_entry:
			continue
		var player := renderer._players[slot_index]
		player.stream = program
		player.global_position = renderer._target_positions[slot_index]
		player.volume_db = renderer._target_volumes_db[slot_index]
		renderer._effect_racks[slot_index].apply_acoustic(
			packet,
			0.0,
			true
		)
		renderer._effect_racks[slot_index].apply_radio_distortion(packet)
		player.play()
	if first_entry and not packets.is_empty():
		var group_packet: Dictionary = packets[0]
		renderer._activate_shared_program_late_field(
			int(group_packet.get("shared_program_group_id", -1)),
			program,
			group_packet,
			0.0
		)


func _drain_captures() -> void:
	if _capture != null:
		var frames := _capture.get_frames_available()
		if frames > 0:
			_samples.append_array(_capture.get_buffer(frames))
	if _pre_limiter_capture != null:
		var pre_frames := _pre_limiter_capture.get_frames_available()
		if pre_frames > 0:
			_pre_limiter_samples.append_array(
				_pre_limiter_capture.get_buffer(pre_frames)
			)


func _analyze_render() -> Dictionary:
	var warmup_frames := mini(
		roundi(WARMUP_SECONDS * float(_mix_rate)),
		_samples.size()
	)
	var derivative_l := PackedFloat32Array()
	var derivative_r := PackedFloat32Array()
	var output_peak := 0.0
	var finite := true
	for sample_index: int in range(warmup_frames + 1, _samples.size()):
		var sample := _samples[sample_index]
		var previous := _samples[sample_index - 1]
		finite = finite and is_finite(sample.x) and is_finite(sample.y)
		output_peak = maxf(output_peak, maxf(absf(sample.x), absf(sample.y)))
		derivative_l.append(absf(sample.x - previous.x))
		derivative_r.append(absf(sample.y - previous.y))
	var derivative_result := _derivative_result(derivative_l, derivative_r)
	var window_result := _window_result(warmup_frames)
	var pre_rms := _stereo_rms(_pre_limiter_samples, warmup_frames)
	var post_rms := _stereo_rms(_samples, warmup_frames)
	var limiter_reduction_db := maxf(
		linear_to_db(maxf(pre_rms, 0.000001))
		- linear_to_db(maxf(post_rms, 0.000001)),
		0.0
	)
	return {
		"frames": _samples.size(),
		"finite": finite,
		"output_peak": output_peak,
		"output_rms": post_rms,
		"crest_factor_db": linear_to_db(
			maxf(output_peak, 0.000001) / maxf(post_rms, 0.000001)
		),
		"limiter_reduction_db": limiter_reduction_db,
		"derivative_score_l": derivative_result["score_l"],
		"derivative_score_r": derivative_result["score_r"],
		"max_window_level_step_db": window_result["max_level_step_db"],
		"max_window_band_step_db": window_result["max_band_step_db"],
		"worst_window_band_step": window_result["worst_band_step"],
		"max_stereo_balance_step_db": window_result["max_balance_step_db"],
		"max_correlation_step": window_result["max_correlation_step"],
	}


func _derivative_result(left: PackedFloat32Array, right: PackedFloat32Array) -> Dictionary:
	if left.is_empty() or right.is_empty():
		return {"score_l": INF, "score_r": INF}
	var maximum_left := 0.0
	var maximum_right := 0.0
	for value: float in left:
		maximum_left = maxf(maximum_left, value)
	for value: float in right:
		maximum_right = maxf(maximum_right, value)
	left.sort()
	right.sort()
	var percentile_index := clampi(
		floori(float(left.size() - 1) * 0.999),
		0,
		left.size() - 1
	)
	return {
		"score_l": maximum_left / maxf(left[percentile_index], 0.000001),
		"score_r": maximum_right / maxf(right[percentile_index], 0.000001),
	}


func _window_result(start_frame: int) -> Dictionary:
	# A 200 ms perceptual window spans enough cycles of the 73 Hz low-band probe to distinguish a
	# real timbre step from ordinary short-window phase leakage. It still advances at every 50 ms
	# authoritative packet, so a corner transition cannot hide between measurements.
	var window_frames := maxi(roundi(ANALYSIS_WINDOW_SECONDS * float(_mix_rate)), 64)
	var stride_frames := maxi(roundi(TRACE_UPDATE_SECONDS * float(_mix_rate)), 1)
	var previous_level_db := NAN
	var previous_balance_db := NAN
	var previous_correlation := NAN
	var previous_bands := Vector3(NAN, NAN, NAN)
	var max_level_step_db := 0.0
	var max_balance_step_db := 0.0
	var max_correlation_step := 0.0
	var max_band_step_db := 0.0
	var worst_band_step: Dictionary = {}
	for from_frame: int in range(start_frame, _samples.size() - window_frames, stride_frames):
		var statistics := _window_statistics(from_frame, window_frames)
		var level_db := float(statistics["level_db"])
		var balance_db := float(statistics["balance_db"])
		var correlation := float(statistics["correlation"])
		var bands: Vector3 = statistics["bands_db"]
		if is_finite(previous_level_db):
			max_level_step_db = maxf(max_level_step_db, absf(level_db - previous_level_db))
			max_balance_step_db = maxf(
				max_balance_step_db,
				absf(balance_db - previous_balance_db)
			)
			max_correlation_step = maxf(
				max_correlation_step,
				absf(correlation - previous_correlation)
			)
			# Do not turn harmless FFT-bin motion into a false hard-cut failure after a band has
			# fallen beneath the program's masking floor. Overall level, derivatives, balance, and
			# correlation remain independently guarded at every window.
			var audible_band_floor_db := maxf(
				level_db,
				previous_level_db
			) - MAX_MASKED_BAND_OFFSET_DB
			var band_step := maxf(
				_audible_band_step(
					bands.x,
					previous_bands.x,
					audible_band_floor_db
				),
				maxf(
					_audible_band_step(
						bands.y,
						previous_bands.y,
						audible_band_floor_db
					),
					_audible_band_step(
						bands.z,
						previous_bands.z,
						audible_band_floor_db
					)
				)
			)
			if band_step > max_band_step_db:
				max_band_step_db = band_step
				worst_band_step = {
					"time_seconds": float(from_frame) / float(_mix_rate),
					"previous_bands_db": previous_bands,
					"bands_db": bands,
				}
		previous_level_db = level_db
		previous_balance_db = balance_db
		previous_correlation = correlation
		previous_bands = bands
	return {
		"max_level_step_db": max_level_step_db,
		"max_balance_step_db": max_balance_step_db,
		"max_correlation_step": max_correlation_step,
		"max_band_step_db": max_band_step_db,
		"worst_band_step": worst_band_step,
	}


static func _audible_band_step(
	current_db: float,
	previous_db: float,
	audible_floor_db: float
) -> float:
	if maxf(current_db, previous_db) < audible_floor_db:
		return 0.0
	return absf(current_db - previous_db)


func _window_statistics(from_frame: int, frame_count: int) -> Dictionary:
	var left_square := 0.0
	var right_square := 0.0
	var cross := 0.0
	for frame_index: int in range(from_frame, from_frame + frame_count):
		var sample := _samples[frame_index]
		left_square += sample.x * sample.x
		right_square += sample.y * sample.y
		cross += sample.x * sample.y
	var left_rms := sqrt(left_square / float(frame_count))
	var right_rms := sqrt(right_square / float(frame_count))
	var combined_rms := sqrt((left_square + right_square) / float(frame_count * 2))
	var correlation := cross / maxf(sqrt(left_square * right_square), 0.000001)
	var low_energy := _tone_energy(from_frame, frame_count, 0) + _tone_energy(from_frame, frame_count, 1)
	var mid_energy := _tone_energy(from_frame, frame_count, 2) + _tone_energy(from_frame, frame_count, 3)
	var high_energy := _tone_energy(from_frame, frame_count, 4)
	return {
		"level_db": linear_to_db(maxf(combined_rms, 0.000001)),
		"balance_db": linear_to_db(maxf(left_rms, 0.000001)) - linear_to_db(maxf(right_rms, 0.000001)),
		"correlation": clampf(correlation, -1.0, 1.0),
		"bands_db": Vector3(
			linear_to_db(sqrt(maxf(low_energy, 0.000000000001))),
			linear_to_db(sqrt(maxf(mid_energy, 0.000000000001))),
			linear_to_db(sqrt(maxf(high_energy, 0.000000000001)))
		),
	}


func _tone_energy(from_frame: int, frame_count: int, tone_index: int) -> float:
	var omega: float = TAU * float(TEST_TONES_HZ[tone_index]) / float(_mix_rate)
	var left_real := 0.0
	var left_imaginary := 0.0
	var right_real := 0.0
	var right_imaginary := 0.0
	for local_index: int in range(frame_count):
		var angle: float = omega * float(local_index)
		var cosine := cos(angle)
		var sine := sin(angle)
		var sample := _samples[from_frame + local_index]
		left_real += sample.x * cosine
		left_imaginary -= sample.x * sine
		right_real += sample.y * cosine
		right_imaginary -= sample.y * sine
	var normalization := 4.0 / float(frame_count * frame_count)
	return (
		left_real * left_real
		+ left_imaginary * left_imaginary
		+ right_real * right_real
		+ right_imaginary * right_imaginary
	) * normalization * 0.5


func _stereo_rms(samples: PackedVector2Array, start_frame: int) -> float:
	if samples.size() <= start_frame:
		return 0.0
	var square_sum := 0.0
	for frame_index: int in range(start_frame, samples.size()):
		var sample := samples[frame_index]
		square_sum += sample.x * sample.x + sample.y * sample.y
	return sqrt(square_sum / float((samples.size() - start_frame) * 2))


func _fail(message: String) -> void:
	push_error("PA four-speaker rendered continuity test failed: %s" % message)
	quit(1)
