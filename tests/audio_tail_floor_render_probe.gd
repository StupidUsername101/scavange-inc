extends SceneTree

const BUS_NAME := &"ScavangeTailFloorProbe"
const SOURCE_SECONDS := 0.65
const RUN_SECONDS := 7.0
const WINDOW_SECONDS := 0.25

var _mix_rate := 44100
var _capture: AudioEffectCapture
var _capture_effect_index := -1
var _rack: SpatialAudioEffectRack
var _samples := PackedVector2Array()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mix_rate = roundi(AudioServer.get_mix_rate())
	var bus_index := _prepare_bus()
	var player := AudioStreamPlayer.new()
	player.bus = BUS_NAME
	player.stream = _make_tonal_step()
	root.add_child(player)
	player.play()

	var elapsed := 0.0
	var previous_elapsed := 0.0
	while elapsed < RUN_SECONDS:
		_drain_capture()
		elapsed = float(_samples.size()) / float(_mix_rate)
		var delta := maxf(elapsed - previous_elapsed, 0.0)
		if delta > 0.0:
			_rack.update_tail_floor(player.playing, delta)
		previous_elapsed = elapsed
		await process_frame
	await create_timer(0.08).timeout
	_drain_capture()
	# Restoring a retired rack without new input must not reveal a frozen reverb/delay buffer. This
	# is the pause -> silence -> resume boundary used by radios and synchronized speaker arrays.
	var resume_from_frame := _samples.size()
	_rack.prepare_for_input()
	var resume_frame_count := roundi(0.5 * float(_mix_rate))
	while _samples.size() < resume_from_frame + resume_frame_count:
		_drain_capture()
		await process_frame
	_drain_capture()

	var windows := PackedFloat32Array()
	var window_count := floori(RUN_SECONDS / WINDOW_SECONDS)
	for window_index: int in range(window_count):
		windows.append(_window_rms_db(
			float(window_index) * WINDOW_SECONDS,
			float(window_index + 1) * WINDOW_SECONDS
		))
	var transition := _late_transition_metrics()
	var taper_window_index := _first_window_below(windows, -50.0)
	var residue_window_index := mini(taper_window_index + 3, windows.size() - 1)
	var resume_rms_db := _frame_window_rms_db(
		resume_from_frame,
		mini(resume_from_frame + resume_frame_count, _samples.size())
	)
	var passed := (
		taper_window_index >= 0
		and windows[4] > -55.0
		and windows[residue_window_index] <= -88.0
		and float(transition["last_nonzero_seconds"]) < 4.2
		and resume_rms_db <= -90.0
	)
	print("Audio tail-floor diagnostic: %s" % JSON.stringify({
		"frames": _samples.size(),
		"windows_db": windows,
		"late_max_step": transition["maximum_step"],
		"late_max_step_db": linear_to_db(maxf(
			float(transition["maximum_step"]),
			0.000001
		)),
		"last_nonzero_seconds": transition["last_nonzero_seconds"],
		"taper_window_index": taper_window_index,
		"residue_window_db": windows[residue_window_index],
		"resume_rms_db": resume_rms_db,
	}))
	if passed:
		print("Audio tail-floor render probe passed")
	else:
		push_error("Audio tail-floor render probe failed")

	player.stop()
	player.free()
	AudioServer.remove_bus_effect(0, _capture_effect_index)
	AudioServer.remove_bus(bus_index)
	quit(0 if passed else 1)


func _prepare_bus() -> int:
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, BUS_NAME)
	AudioServer.set_bus_send(bus_index, &"Master")
	_rack = SpatialAudioEffectRack.attach(BUS_NAME)
	_rack.prepare_for_input()
	_rack.apply_acoustic({
		"band_gain": Vector3.ONE,
		"lowpass_hz": AcousticPathModifier.MAX_FILTER_HZ,
		"highpass_hz": AcousticPathModifier.MIN_FILTER_HZ,
		"reverb_send": 0.68,
		"reverb_room_size": 0.82,
		"reverb_damping": 0.52,
		"reverb_predelay_msec": 28.0,
		"reverb_predelay_feedback": 0.38,
		"reverb_hipass": 0.08,
	})
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = RUN_SECONDS + 1.0
	_capture_effect_index = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, _capture)
	return bus_index


func _make_tonal_step() -> AudioStreamWAV:
	var frame_count := ceili(SOURCE_SECONDS * float(_mix_rate))
	var fade_frames := maxi(roundi(0.012 * float(_mix_rate)), 1)
	var data := PackedByteArray()
	data.resize(frame_count * 4)
	for frame_index: int in range(frame_count):
		var time_seconds := float(frame_index) / float(_mix_rate)
		var fade := clampf(
			float(frame_count - frame_index) / float(fade_frames),
			0.0,
			1.0
		)
		var value := (
			sin(TAU * 173.0 * time_seconds) * 0.18
			+ sin(TAU * 463.0 * time_seconds + 0.4) * 0.11
			+ sin(TAU * 1523.0 * time_seconds + 1.1) * 0.07
		) * fade
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
	return _frame_window_rms_db(from_frame, to_frame)


func _frame_window_rms_db(from_frame: int, to_frame: int) -> float:
	if to_frame <= from_frame:
		return -120.0
	var square_sum := 0.0
	for frame_index: int in range(from_frame, to_frame):
		var sample := _samples[frame_index]
		square_sum += sample.x * sample.x + sample.y * sample.y
	return linear_to_db(maxf(
		sqrt(square_sum / float((to_frame - from_frame) * 2)),
		0.000001
	))


func _first_window_below(windows: PackedFloat32Array, threshold_db: float) -> int:
	for window_index: int in range(ceili(SOURCE_SECONDS / WINDOW_SECONDS), windows.size()):
		if windows[window_index] <= threshold_db:
			return window_index
	return -1


func _late_transition_metrics() -> Dictionary:
	var from_frame := clampi(
		roundi(SOURCE_SECONDS * float(_mix_rate)),
		1,
		_samples.size()
	)
	var maximum_step := 0.0
	var last_nonzero_frame := from_frame
	for frame_index: int in range(from_frame, _samples.size()):
		var sample := _samples[frame_index]
		var previous := _samples[frame_index - 1]
		maximum_step = maxf(
			maximum_step,
			maxf(
				absf(sample.x - previous.x),
				absf(sample.y - previous.y)
			)
		)
		if maxf(absf(sample.x), absf(sample.y)) > 0.000001:
			last_nonzero_frame = frame_index
	return {
		"maximum_step": maximum_step,
		"last_nonzero_seconds": (
			float(last_nonzero_frame) / float(_mix_rate)
		),
	}
