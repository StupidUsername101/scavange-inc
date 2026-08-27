extends SceneTree

const BUS_NAME := &"ScavangeReverbReturnCalibration"
const RUN_SECONDS := 4.0
const WARMUP_SECONDS := 1.5
const NOISE_AMPLITUDE := 0.08
const MIN_EFFECTIVE_RETURN_DB := -8.0
const MAX_EFFECTIVE_RETURN_DB := 2.0

var _mix_rate := 44100
var _noise_state := 0x4D595DF4


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mix_rate = roundi(AudioServer.get_mix_rate())
	var bunker_result := await _measure_case(
		"bunker",
		{
			"reverb_room_size": 0.62,
			"reverb_damping": 0.48,
			"reverb_predelay_msec": 28.0,
			"reverb_predelay_feedback": 0.48,
			"reverb_hipass": 0.05,
		}
	)
	var tunnel_result := await _measure_case(
		"large_tunnel",
		{
			"reverb_room_size": 0.86,
			"reverb_damping": 0.64,
			"reverb_predelay_msec": 42.0,
			"reverb_predelay_feedback": 0.58,
			"reverb_hipass": 0.04,
		}
	)
	var passed := _case_passed(bunker_result) and _case_passed(tunnel_result)
	print("Reverb return calibration: %s" % JSON.stringify({
		"bunker": bunker_result,
		"large_tunnel": tunnel_result,
	}))
	if passed:
		print("Reverb return normalization probe passed")
	else:
		push_error("Reverb return normalization probe failed")
	quit(0 if passed else 1)


func _measure_case(label: String, packet_overrides: Dictionary) -> Dictionary:
	var existing_index := AudioServer.get_bus_index(BUS_NAME)
	if existing_index >= 0:
		AudioServer.remove_bus(existing_index)
	var rack := SpatialAudioEffectRack.attach(BUS_NAME)
	AudioServer.set_bus_volume_db(rack.bus_index, 0.0)
	var packet := {
		"band_gain": Vector3.ONE,
		"lowpass_hz": AcousticPathModifier.MAX_FILTER_HZ,
		"highpass_hz": AcousticPathModifier.MIN_FILTER_HZ,
		"resonance": 0.0,
		"reverb_send": 1.0,
	}
	packet.merge(packet_overrides, true)
	rack.apply_acoustic(packet, 0.0, false, true)
	var normalization := SpatialAudioEffectRack.reverb_return_rms_normalization(
		packet
	)

	var capture := AudioEffectCapture.new()
	capture.buffer_length = RUN_SECONDS + 1.0
	AudioServer.add_bus_effect(rack.bus_index, capture)
	var player := AudioStreamPlayer.new()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _mix_rate
	generator.buffer_length = 0.5
	player.stream = generator
	player.bus = BUS_NAME
	root.add_child(player)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback

	_noise_state = 0x4D595DF4
	var input_square_sum := 0.0
	var input_sample_count := 0
	var started_usec := Time.get_ticks_usec()
	while (
		float(Time.get_ticks_usec() - started_usec) / 1000000.0
		< RUN_SECONDS
	):
		while playback != null and playback.can_push_buffer(256):
			var frames := PackedVector2Array()
			frames.resize(256)
			for frame_index: int in range(frames.size()):
				var sample := Vector2(
					_next_white_sample(),
					_next_white_sample()
				) * NOISE_AMPLITUDE
				frames[frame_index] = sample
				input_square_sum += sample.x * sample.x + sample.y * sample.y
				input_sample_count += 2
			playback.push_buffer(frames)
		await process_frame
	await create_timer(0.15).timeout

	var captured := capture.get_buffer(capture.get_frames_available())
	var warmup_frames := mini(
		roundi(WARMUP_SECONDS * float(_mix_rate)),
		captured.size()
	)
	var output_square_sum := 0.0
	var output_sample_count := 0
	var output_peak := 0.0
	for frame_index: int in range(warmup_frames, captured.size()):
		var sample := captured[frame_index]
		output_square_sum += sample.x * sample.x + sample.y * sample.y
		output_sample_count += 2
		output_peak = maxf(output_peak, maxf(absf(sample.x), absf(sample.y)))
	var input_rms := sqrt(
		input_square_sum / maxf(float(input_sample_count), 1.0)
	)
	var output_rms := sqrt(
		output_square_sum / maxf(float(output_sample_count), 1.0)
	)
	var effective_return_db := linear_to_db(
		maxf(output_rms / maxf(input_rms, 0.000001), 0.000001)
	)
	player.stop()
	player.free()
	AudioServer.remove_bus(rack.bus_index)
	return {
		"label": label,
		"captured_frames": captured.size(),
		"normalization": normalization,
		"input_rms": input_rms,
		"output_rms": output_rms,
		"effective_return_db": effective_return_db,
		"output_peak": output_peak,
	}


func _next_white_sample() -> float:
	# A deterministic allocation-free LCG is sufficient here: the probe needs broadband stationary
	# input, not cryptographic randomness. Independent consecutive values feed left and right.
	_noise_state = int((_noise_state * 1664525 + 1013904223) & 0x7FFFFFFF)
	return float(_noise_state) / 1073741823.5 - 1.0


static func _case_passed(result: Dictionary) -> bool:
	return (
		int(result.get("captured_frames", 0)) > 44100
		and float(result.get("normalization", 0.0)) > 0.0
		and float(result.get("normalization", 1.0)) < 1.0
		and float(result.get("effective_return_db", -INF))
		>= MIN_EFFECTIVE_RETURN_DB
		and float(result.get("effective_return_db", INF))
		<= MAX_EFFECTIVE_RETURN_DB
		and float(result.get("output_peak", INF)) < 1.0
	)
