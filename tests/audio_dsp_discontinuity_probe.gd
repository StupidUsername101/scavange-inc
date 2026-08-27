extends SceneTree

const BUS_NAME := &"ScavangeDSPDiscontinuityProbe"
const TONE_HZ := 173.0
const TONE_AMPLITUDE := 0.08
const RUN_SECONDS := 2.0
const WARMUP_SECONDS := 0.35
const EFFECT_FOLLOW_SPEED := 38.0
const MAX_IMPULSE_SCORE := 1.6

var _mix_rate := 44100
var _phase := 0.0
var _elapsed := 0.0
var _capture: AudioEffectCapture
var _playback: AudioStreamGeneratorPlayback
var _rack: SpatialAudioEffectRack
var _samples := PackedVector2Array()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mix_rate = roundi(AudioServer.get_mix_rate())
	var bus_index := _prepare_capture_bus()
	var player := _make_tone_player()
	root.add_child(player)
	player.play()
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

	var previous_usec := Time.get_ticks_usec()
	while _elapsed < RUN_SECONDS:
		var now_usec := Time.get_ticks_usec()
		var delta := clampf(
			float(now_usec - previous_usec) / 1000000.0,
			0.0,
			0.05
		)
		previous_usec = now_usec
		_elapsed += delta
		_update_production_rack(delta)
		_fill_generator()
		_drain_capture()
		await process_frame
	_fill_generator()
	await create_timer(0.08).timeout
	_drain_capture()

	var result := _analyze_samples()
	var enough_audio := _samples.size() > _mix_rate
	var continuous := (
		float(result["score_l"]) < MAX_IMPULSE_SCORE
		and float(result["score_r"]) < MAX_IMPULSE_SCORE
	)
	print(
		"DSP continuity: frames=%d score_l=%.2f score_r=%.2f step_l=%.6f step_r=%.6f"
		% [
			_samples.size(),
			float(result["score_l"]),
			float(result["score_r"]),
			float(result["step_l"]),
			float(result["step_r"]),
		]
	)
	if enough_audio and continuous:
		print("Audio DSP discontinuity test passed")
	else:
		push_error("Audio DSP discontinuity test failed")
	player.stop()
	player.free()
	AudioServer.remove_bus(bus_index)
	quit(0 if enough_audio and continuous else 1)


func _prepare_capture_bus() -> int:
	var bus_index := AudioServer.get_bus_index(BUS_NAME)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, BUS_NAME)
	AudioServer.set_bus_send(bus_index, &"Master")
	for effect_index: int in range(
		AudioServer.get_bus_effect_count(bus_index) - 1,
		-1,
		-1
	):
		AudioServer.remove_bus_effect(bus_index, effect_index)
	_rack = SpatialAudioEffectRack.attach(BUS_NAME)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = RUN_SECONDS + 1.0
	AudioServer.add_bus_effect(bus_index, _capture)
	return bus_index


func _make_tone_player() -> AudioStreamPlayer:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _mix_rate
	generator.buffer_length = 0.25
	var player := AudioStreamPlayer.new()
	player.bus = BUS_NAME
	player.stream = generator
	return player


func _update_production_rack(delta: float) -> void:
	# The old rack copied these alternating geometry values into Godot's populated right-channel
	# comb/all-pass lengths and emitted a one-sample spark. Drive the public production path hard so
	# this fails if live spread mutation is ever reintroduced.
	var high_target := int(floor(_elapsed / 0.25)) % 2 == 0
	var weight := 1.0 - exp(-EFFECT_FOLLOW_SPEED * maxf(delta, 0.0))
	_rack.approach_acoustic({
		"band_gain": Vector3.ONE,
		"lowpass_hz": AcousticPathModifier.MAX_FILTER_HZ,
		"highpass_hz": AcousticPathModifier.MIN_FILTER_HZ,
		"reverb_send": 0.48,
		"reverb_room_size": 0.63,
		"reverb_damping": 0.42,
		"reverb_spread": 0.18 if high_target else 0.98,
		"reverb_predelay_msec": 24.0,
		"reverb_predelay_feedback": 0.36,
		"reverb_hipass": 0.08,
	}, weight)


func _fill_generator() -> void:
	if _playback == null:
		return
	var phase_step := TAU * TONE_HZ / float(_mix_rate)
	for _frame: int in range(_playback.get_frames_available()):
		var value := sin(_phase) * TONE_AMPLITUDE
		_playback.push_frame(Vector2(value, value))
		_phase = fmod(_phase + phase_step, TAU)


func _drain_capture() -> void:
	if _capture == null:
		return
	var frames := _capture.get_frames_available()
	if frames > 0:
		_samples.append_array(_capture.get_buffer(frames))


func _analyze_samples() -> Dictionary:
	var warmup_frames := mini(
		roundi(WARMUP_SECONDS * float(_mix_rate)),
		_samples.size()
	)
	var derivative_count := maxi(_samples.size() - warmup_frames - 1, 0)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(derivative_count)
	right.resize(derivative_count)
	var maximum_left := 0.0
	var maximum_right := 0.0
	for sample_index: int in range(warmup_frames + 1, _samples.size()):
		var derivative_index := sample_index - warmup_frames - 1
		var sample := _samples[sample_index]
		var previous := _samples[sample_index - 1]
		left[derivative_index] = absf(sample.x - previous.x)
		right[derivative_index] = absf(sample.y - previous.y)
		maximum_left = maxf(maximum_left, left[derivative_index])
		maximum_right = maxf(maximum_right, right[derivative_index])
	left.sort()
	right.sort()
	if left.is_empty():
		return {"step_l": 0.0, "step_r": 0.0, "score_l": INF, "score_r": INF}
	var percentile_index := clampi(
		floori(float(left.size() - 1) * 0.999),
		0,
		left.size() - 1
	)
	return {
		"step_l": maximum_left,
		"step_r": maximum_right,
		"score_l": maximum_left / maxf(left[percentile_index], 0.000001),
		"score_r": maximum_right / maxf(right[percentile_index], 0.000001),
	}
