class_name SpatialAudioEffectRack
extends RefCounted

const FILTER_BYPASS_MARGIN_HZ := 50.0
const REVERB_WET_SCALE := 0.72
const MAX_REVERB_WET := 0.75
const SPECTRAL_BLOOM_SEND_LIFT := 0.20
const SPECTRAL_BLOOM_DAMPING_LIFT := 0.10
const SPECTRAL_BLOOM_PREDELAY_FEEDBACK_LIFT := 0.08
# Godot implements stereo spread by changing only the right reverb network's comb/all-pass delay
# lengths. Moving this value while the delay is populated can wrap a read head immediately and
# emit a one-sample click in the right channel. Keep that topology fixed; room geometry still
# changes wet energy, decay, damping, filters, and apparent source position, while pre-delay is
# selected once before each input begins.
const REALTIME_SAFE_REVERB_SPREAD := 0.92
# Godot 4's Freeverb-derived return contains eight parallel feedback combs followed by all-pass
# stages. The all-pass stages preserve RMS power; the comb bank and predelay do not. These constants
# mirror servers/audio/effects/reverb_filter.cpp and let us normalize the expected diffuse return
# once from room parameters instead of compressing it in response to the music.
const GODOT_REVERB_COMB_COUNT := 8.0
const GODOT_REVERB_COMB_FEEDBACK_OFFSET := 0.7
const GODOT_REVERB_COMB_FEEDBACK_SCALE := 0.28
const GODOT_REVERB_WET_OUTPUT_SCALE := 0.6
const EARLY_REFLECTION_SLOT_COUNT := 2
const EARLY_REFLECTION_SILENT_DB := -60.0
const EARLY_REFLECTION_RETUNE_DB := -52.0
const EARLY_REFLECTION_DELAY_HYSTERESIS_MSEC := 3.0
# Godot deactivates an unused audio-bus channel after it remains below -60 dB for two seconds.
# Its Freeverb-derived comb bank can become sparse/metallic in that interval, then the engine cuts
# the channel in one block. Preserve the useful room decay, but taper an undriven return once it is
# already very quiet so both the numerical residue and the eventual engine cutoff are inaudible.
const TAIL_FLOOR_TAPER_START_DB := -60.0
const TAIL_FLOOR_SILENT_DB := -80.0
const TAIL_FLOOR_TAPER_DB_PER_SECOND := 24.0
# The last few hundred milliseconds of a feedback reverb are no longer a useful geometric echo:
# lossy program residue and sparse comb modes can become a bright, detached hiss as the dry signal
# disappears. Real rooms also lose high frequencies faster than lows. A post-return low-pass darkens
# only that already-retiring residue; it is bypassed for every driven sample and never changes the
# populated reverb topology.
const TAIL_FLOOR_DARKEN_OVER_DB := 30.0
const TAIL_FLOOR_MIN_CUTOFF_HZ := 850.0
const TAIL_FLOOR_MIN_PROTECTED_SECONDS := 0.20
const TAIL_FLOOR_FORCE_TAPER_MARGIN_SECONDS := 0.15

## Persistent DSP rack shared by short spatial voices and continuous radios. Dedicated buses are
## built once; packet updates only mutate existing effect parameters.

var bus_index := -1
var distortion: AudioEffectDistortion
var equalizer: AudioEffectEQ6
var lowpass: AudioEffectLowPassFilter
var highpass: AudioEffectHighPassFilter
var early_delay: AudioEffectDelay
var reverb: AudioEffectReverb
var tail_lowpass: AudioEffectLowPassFilter
var spectrum_analyzer: AudioEffectSpectrumAnalyzer
var spectrum_analyzer_instance: AudioEffectSpectrumAnalyzerInstance
var _distortion_effect_index := -1
var _equalizer_effect_index := 0
var _lowpass_effect_index := 1
var _highpass_effect_index := 2
var _reverb_effect_index := 3
var _tail_lowpass_effect_index := 4
var _early_delay_effect_index := -1
var _spectrum_effect_index := -1
var _persistent_processing := false
var _early_reflection_ids := PackedInt32Array([-1, -1])
var _tail_floor_gain_db := 0.0
var _tail_floor_tapering := false
var _tail_floor_armed := false
var _tail_floor_undriven_seconds := 0.0
var _tail_expected_decay_seconds := 0.25
var _reverb_topology_initialized := false


static func attach(bus_name: StringName, include_distortion := false) -> SpatialAudioEffectRack:
	var result := SpatialAudioEffectRack.new()
	# Distortion racks are continuous radio voices. Keep their filters in the DSP chain and move
	# them to transparent cutoff values rather than toggling a bus effect during playback.
	result._persistent_processing = include_distortion
	result.bus_index = AudioServer.get_bus_index(bus_name)
	if result.bus_index < 0:
		AudioServer.add_bus()
		result.bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(result.bus_index, bus_name)
	AudioServer.set_bus_send(result.bus_index, &"Master")
	result._ensure_effect_layout(include_distortion)
	return result


func apply_acoustic(
	packet: Dictionary,
	spectral_room_bloom := 0.0,
	suppress_reverb := false,
	wet_reverb_only := false
) -> void:
	_apply_acoustic(
		packet,
		1.0,
		spectral_room_bloom,
		suppress_reverb,
		wet_reverb_only
	)


func approach_acoustic(
	packet: Dictionary,
	weight: float,
	spectral_room_bloom := 0.0,
	suppress_reverb := false,
	wet_reverb_only := false
) -> void:
	_apply_acoustic(
		packet,
		clampf(weight, 0.0, 1.0),
		spectral_room_bloom,
		suppress_reverb,
		wet_reverb_only
	)


func _apply_acoustic(
	packet: Dictionary,
	weight: float,
	spectral_room_bloom: float,
	suppress_reverb: bool,
	wet_reverb_only: bool
) -> void:
	var band_gain: Vector3 = packet.get("band_gain", Vector3.ONE)
	var band_db := Vector3(
		linear_to_db(maxf(band_gain.x, 0.001)),
		linear_to_db(maxf(band_gain.y, 0.001)),
		linear_to_db(maxf(band_gain.z, 0.001))
	)
	if equalizer != null:
		for band_index: int in range(equalizer.get_band_count()):
			var gain_db := (
				band_db.x
				if band_index < 2
				else band_db.y if band_index < 4 else band_db.z
			)
			equalizer.set_band_gain_db(
				band_index,
				lerpf(
					equalizer.get_band_gain_db(band_index),
					clampf(gain_db, -60.0, 12.0),
					weight
				)
			)

	var lowpass_hz := float(packet.get(
		"lowpass_hz",
		AcousticPathModifier.MAX_FILTER_HZ
	))
	if lowpass != null:
		lowpass.cutoff_hz = _lerp_frequency(
			lowpass.cutoff_hz,
			lowpass_hz,
			weight
		)
		lowpass.resonance = lerpf(
			lowpass.resonance,
			lerpf(0.5, 2.5, float(packet.get("resonance", 0.0))),
			weight
		)
	if _lowpass_effect_index >= 0:
		AudioServer.set_bus_effect_enabled(
			bus_index,
			_lowpass_effect_index,
			_persistent_processing
			or (lowpass != null and lowpass.cutoff_hz
			< AcousticPathModifier.MAX_FILTER_HZ - FILTER_BYPASS_MARGIN_HZ)
			or lowpass_hz
			< AcousticPathModifier.MAX_FILTER_HZ - FILTER_BYPASS_MARGIN_HZ
		)

	var highpass_hz := float(packet.get(
		"highpass_hz",
		AcousticPathModifier.MIN_FILTER_HZ
	))
	if highpass != null:
		highpass.cutoff_hz = _lerp_frequency(
			highpass.cutoff_hz,
			highpass_hz,
			weight
		)
	if _highpass_effect_index >= 0:
		AudioServer.set_bus_effect_enabled(
			bus_index,
			_highpass_effect_index,
			_persistent_processing
			or (highpass != null and highpass.cutoff_hz
			> AcousticPathModifier.MIN_FILTER_HZ + FILTER_BYPASS_MARGIN_HZ)
			or highpass_hz
			> AcousticPathModifier.MIN_FILTER_HZ + FILTER_BYPASS_MARGIN_HZ
		)

	_apply_early_reflections(packet, weight, wet_reverb_only)

	var bloom_response := spectral_bloom_reverb_response(
		packet,
		spectral_room_bloom
	)
	var reverb_mix := (
		Vector2(0.0, 1.0)
		if wet_reverb_only
		else power_normalized_reverb_mix(
			0.0 if suppress_reverb else bloom_response.x
		)
	)
	var return_normalization := _reverb_return_rms_normalization_for_parameters(
		float(packet.get("reverb_room_size", 0.35)),
		bloom_response.z
	)
	var target_reverb_dry := reverb_mix.x
	var target_reverb_wet := reverb_mix.y * return_normalization
	_tail_expected_decay_seconds = lerpf(
		_tail_expected_decay_seconds,
		clampf(
			SafeVariant.finite_float_or(
				packet.get("reverb_decay_seconds"),
				0.25
			),
			AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
			AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
		),
		weight
	)
	if reverb != null:
		reverb.dry = lerpf(reverb.dry, target_reverb_dry, weight)
		reverb.wet = lerpf(reverb.wet, target_reverb_wet, weight)
		reverb.room_size = lerpf(
			reverb.room_size,
			clampf(float(packet.get("reverb_room_size", 0.35)), 0.0, 1.0),
			weight
		)
		reverb.damping = lerpf(reverb.damping, bloom_response.y, weight)
		# Pre-delay is a delay-line read position, not an ordinary mix coefficient. Retuning it while
		# program or Hall samples occupy the line produces a tiny pitch bend/zipper that resembles
		# Doppler as probe targets change. Initialize it before a voice starts and keep that topology
		# stable for the lifetime of the input; room send, feedback, damping, colour, and level remain
		# continuously responsive.
		if not _reverb_topology_initialized:
			reverb.predelay_msec = clampf(
				float(packet.get("reverb_predelay_msec", 8.0)),
				0.0,
				500.0
			)
			_reverb_topology_initialized = true
		reverb.predelay_feedback = lerpf(
			reverb.predelay_feedback,
			bloom_response.z,
			weight
		)
		reverb.hipass = lerpf(
			reverb.hipass,
			clampf(float(packet.get("reverb_hipass", 0.05)), 0.0, 1.0),
			weight
		)
	AudioServer.set_bus_effect_enabled(
		bus_index,
		_reverb_effect_index,
		(_persistent_processing and not suppress_reverb)
		or (reverb != null and reverb.wet > 0.001)
		or target_reverb_wet > 0.001
	)


static func power_normalized_reverb_mix(reverb_send: float) -> Vector2:
	# The server's volume already contains direct + supported reflected energy. Reverb is the
	# renderer for that energy, not an extra source. Equal-power normalization keeps dry² + wet²
	# at one for every room, tunnel, source type, and input spectrum.
	var unnormalized_wet := clampf(
		clampf(reverb_send, 0.0, 1.0) * REVERB_WET_SCALE,
		0.0,
		MAX_REVERB_WET
	)
	var normalization := 1.0 / sqrt(
		1.0 + unnormalized_wet * unnormalized_wet
	)
	return Vector2(
		normalization,
		unnormalized_wet * normalization
	)


static func reverb_return_rms_normalization(
	packet: Dictionary,
	spectral_room_bloom := 0.0
) -> float:
	# For decorrelated delayed samples, a feedback comb y[n] = f * (x[n-d] + y[n-d])
	# has RMS gain f / sqrt(1 - f²). Eight parallel combs add in power (sqrt(8)); Godot then
	# applies a 0.6 wet scale. The predelay feedback loop contributes 1 / sqrt(1 - p²).
	# Taking the reciprocal bounds the undamped diffuse return at unity without following program
	# content. Godot's frequency damping makes the measured broadband return quieter, never hotter.
	# This is deliberately time invariant: no pumping, no beat-dependent Hall.
	# Spectral bloom can lift feedback slightly, so normalize the actual target network rather than
	# the unexcited base packet. This remains a parameter-only correction, never a signal follower.
	var predelay_feedback := spectral_bloom_reverb_response(
		packet,
		spectral_room_bloom
	).z
	return _reverb_return_rms_normalization_for_parameters(
		float(packet.get("reverb_room_size", 0.35)),
		predelay_feedback
	)


static func _reverb_return_rms_normalization_for_parameters(
	room_size: float,
	predelay_feedback: float
) -> float:
	room_size = clampf(room_size, 0.0, 1.0)
	predelay_feedback = clampf(predelay_feedback, 0.0, 0.90)
	var comb_feedback := clampf(
		GODOT_REVERB_COMB_FEEDBACK_OFFSET
		+ room_size * GODOT_REVERB_COMB_FEEDBACK_SCALE,
		0.0,
		0.98
	)
	var comb_rms_gain := (
		comb_feedback
		/ sqrt(maxf(1.0 - comb_feedback * comb_feedback, 0.000001))
	)
	var predelay_rms_gain := 1.0 / sqrt(maxf(
		1.0 - predelay_feedback * predelay_feedback,
		0.000001
	))
	var return_rms_gain := (
		sqrt(GODOT_REVERB_COMB_COUNT)
		* comb_rms_gain
		* GODOT_REVERB_WET_OUTPUT_SCALE
		* predelay_rms_gain
	)
	return 1.0 / maxf(return_rms_gain, 1.0)


static func spectral_bloom_reverb_response(
	packet: Dictionary,
	spectral_room_bloom: float
) -> Vector3:
	# This is deliberately a small change to the same geometry-authored reverb. Bright sustained
	# material may excite a reflective room more vividly, but it cannot invent a room outdoors or
	# escape the power-normalized dry/wet budget.
	var base_send := clampf(float(packet.get("reverb_send", 0.0)), 0.0, 1.0)
	var base_damping := clampf(
		float(packet.get("reverb_damping", 0.5)),
		0.0,
		1.0
	)
	var base_feedback := clampf(
		float(packet.get("reverb_predelay_feedback", 0.25)),
		0.0,
		1.0
	)
	var bloom := clampf(spectral_room_bloom, 0.0, 1.0)
	return Vector3(
		clampf(
			base_send
			+ SPECTRAL_BLOOM_SEND_LIFT * bloom * lerpf(0.35, 1.0, base_send),
			0.0,
			1.0
		),
		clampf(
			base_damping + SPECTRAL_BLOOM_DAMPING_LIFT * bloom,
			0.0,
			0.98
		),
		clampf(
			base_feedback + SPECTRAL_BLOOM_PREDELAY_FEEDBACK_LIFT * bloom,
			0.0,
			0.90
		)
	)


func apply_radio_distortion(packet: Dictionary) -> void:
	_apply_radio_distortion(packet, 1.0)


func approach_radio_distortion(packet: Dictionary, weight: float) -> void:
	_apply_radio_distortion(packet, clampf(weight, 0.0, 1.0))


func sample_spectrum_range(from_hz: float, to_hz: float) -> Vector2:
	if _spectrum_effect_index < 0:
		return Vector2.ZERO
	if spectrum_analyzer_instance == null:
		spectrum_analyzer_instance = AudioServer.get_bus_effect_instance(
			bus_index,
			_spectrum_effect_index
		) as AudioEffectSpectrumAnalyzerInstance
	if spectrum_analyzer_instance == null:
		return Vector2.ZERO
	return spectrum_analyzer_instance.get_magnitude_for_frequency_range(
		maxf(from_hz, 0.0),
		maxf(to_hz, from_hz),
		AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
	)


func prepare_for_input() -> void:
	# New input must never inherit the previous voice's tail attenuation. The old return is already
	# below the taper threshold, and the new transient masks that tiny reset without an allocation or
	# rebuilding populated DSP delay lines on the hot path.
	_tail_floor_gain_db = 0.0
	_tail_floor_tapering = false
	_tail_floor_armed = true
	_tail_floor_undriven_seconds = 0.0
	_reverb_topology_initialized = false
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, 0.0)
		if tail_lowpass != null:
			tail_lowpass.cutoff_hz = AcousticPathModifier.MAX_FILTER_HZ
		AudioServer.set_bus_effect_enabled(
			bus_index,
			_tail_lowpass_effect_index,
			false
		)


func update_tail_floor(input_driven: bool, delta: float) -> void:
	if bus_index < 0:
		return
	if input_driven:
		# A tail filter is enabled on the first undriven frame, before the gain taper starts. A
		# continuous source can legitimately disappear for one unreliable snapshot and return during
		# that hold. Reset the whole retirement state on that transition; checking only the gain left
		# the post-reverb low-pass engaged and permanently darkened the resumed program/Hall.
		if _tail_floor_undriven_seconds > 0.0:
			prepare_for_input()
		else:
			_tail_floor_armed = true
		return
	if not _tail_floor_armed:
		return
	_tail_floor_undriven_seconds += maxf(delta, 0.0)
	if not _tail_floor_tapering:
		var tail_peak_db := maxf(
			AudioServer.get_bus_peak_volume_left_db(bus_index, 0),
			AudioServer.get_bus_peak_volume_right_db(bus_index, 0)
		)
		var protected_seconds := maxf(
			_tail_expected_decay_seconds,
			TAIL_FLOOR_MIN_PROTECTED_SECONDS
		)
		if (
			_tail_floor_undriven_seconds < TAIL_FLOOR_MIN_PROTECTED_SECONDS
			or (
				tail_peak_db > TAIL_FLOOR_TAPER_START_DB
				and _tail_floor_undriven_seconds
				< protected_seconds + TAIL_FLOOR_FORCE_TAPER_MARGIN_SECONDS
			)
		):
			return
		_tail_floor_tapering = true
		AudioServer.set_bus_effect_enabled(
			bus_index,
			_tail_lowpass_effect_index,
			true
		)
	_tail_floor_gain_db = move_toward(
		_tail_floor_gain_db,
		TAIL_FLOOR_SILENT_DB,
		TAIL_FLOOR_TAPER_DB_PER_SECOND * maxf(delta, 0.0)
	)
	var gain_darken_progress := clampf(
		-_tail_floor_gain_db / TAIL_FLOOR_DARKEN_OVER_DB,
		0.0,
		1.0
	)
	_apply_tail_lowpass(gain_darken_progress)
	AudioServer.set_bus_volume_db(bus_index, _tail_floor_gain_db)
	if _tail_floor_gain_db <= TAIL_FLOOR_SILENT_DB + 0.001:
		_tail_floor_armed = false


func reset_state() -> void:
	# Audio effects own delay-line state outside the stream player. Rebuilding only at a session
	# boundary guarantees that an old room/radio tail cannot bleed into the next world. This is
	# deliberately not used on the hot playback path.
	for effect_index: int in range(
		AudioServer.get_bus_effect_count(bus_index) - 1,
		-1,
		-1
	):
		AudioServer.remove_bus_effect(bus_index, effect_index)
	_tail_floor_gain_db = 0.0
	_tail_floor_tapering = false
	_tail_floor_armed = false
	_tail_floor_undriven_seconds = 0.0
	_tail_expected_decay_seconds = 0.25
	_reverb_topology_initialized = false
	AudioServer.set_bus_volume_db(bus_index, 0.0)
	_early_reflection_ids = PackedInt32Array([-1, -1])
	_ensure_effect_layout(_persistent_processing)


func _apply_tail_lowpass(progress: float) -> void:
	if tail_lowpass == null:
		return
	# The curved response preserves the clear early echo, then retires hiss/comb residue before it
	# can become perceptually separate from the musical tail.
	progress = pow(clampf(progress, 0.0, 1.0), 0.72)
	tail_lowpass.cutoff_hz = exp(lerpf(
		log(AcousticPathModifier.MAX_FILTER_HZ),
		log(TAIL_FLOOR_MIN_CUTOFF_HZ),
		progress
	))


func _apply_early_reflections(
	packet: Dictionary,
	weight: float,
	wet_reverb_only: bool
) -> void:
	if early_delay == null:
		return
	var taps: Array = [] if wet_reverb_only else packet.get("early_reflections", [])
	var raw_gains := Vector2.ZERO
	for slot: int in range(EARLY_REFLECTION_SLOT_COUNT):
		if slot < taps.size() and taps[slot] is Dictionary:
			raw_gains[slot] = clampf(
				float((taps[slot] as Dictionary).get("gain", 0.0)),
				0.0,
				0.70
			)
	var normalization := 1.0 / sqrt(
		1.0 + raw_gains.x * raw_gains.x + raw_gains.y * raw_gains.y
	)
	early_delay.dry = lerpf(early_delay.dry, normalization, weight)
	for slot: int in range(EARLY_REFLECTION_SLOT_COUNT):
		var tap: Dictionary = (
			taps[slot] as Dictionary
			if slot < taps.size() and taps[slot] is Dictionary
			else {}
		)
		var target_id := int(tap.get("reflection_id", -1))
		var target_delay_msec := clampf(
			float(tap.get("extra_delay_seconds", 0.0)) * 1000.0,
			1.0,
			180.0
		)
		var current_level_db := _early_tap_level_db(slot)
		var topology_changed := (
			target_id != _early_reflection_ids[slot]
			or absf(target_delay_msec - _early_tap_delay_msec(slot))
			> EARLY_REFLECTION_DELAY_HYSTERESIS_MSEC
		)
		if target_id < 0:
			_set_early_tap_level_db(
				slot,
				lerpf(current_level_db, EARLY_REFLECTION_SILENT_DB, weight)
			)
			continue
		if topology_changed and current_level_db > EARLY_REFLECTION_RETUNE_DB:
			# Delay read heads are retuned only after their return is inaudible. This avoids the
			# one-sample zipper/spark artifact that moving a populated delay line can produce.
			_set_early_tap_level_db(
				slot,
				lerpf(current_level_db, EARLY_REFLECTION_SILENT_DB, weight)
			)
			continue
		if topology_changed:
			_set_early_tap_delay_msec(slot, target_delay_msec)
			_early_reflection_ids[slot] = target_id
		_set_early_tap_pan(
			slot,
			lerpf(_early_tap_pan(slot), clampf(float(tap.get("pan", 0.0)), -1.0, 1.0), weight)
		)
		var target_level_db := linear_to_db(maxf(raw_gains[slot] * normalization, 0.001))
		_set_early_tap_level_db(
			slot,
			lerpf(_early_tap_level_db(slot), target_level_db, weight)
		)


func _early_tap_level_db(slot: int) -> float:
	return early_delay.tap1_level_db if slot == 0 else early_delay.tap2_level_db


func _set_early_tap_level_db(slot: int, value: float) -> void:
	if slot == 0:
		early_delay.tap1_level_db = value
	else:
		early_delay.tap2_level_db = value


func _early_tap_delay_msec(slot: int) -> float:
	return early_delay.tap1_delay_ms if slot == 0 else early_delay.tap2_delay_ms


func _set_early_tap_delay_msec(slot: int, value: float) -> void:
	if slot == 0:
		early_delay.tap1_delay_ms = value
	else:
		early_delay.tap2_delay_ms = value


func _early_tap_pan(slot: int) -> float:
	return early_delay.tap1_pan if slot == 0 else early_delay.tap2_pan


func _set_early_tap_pan(slot: int, value: float) -> void:
	if slot == 0:
		early_delay.tap1_pan = value
	else:
		early_delay.tap2_pan = value


func _apply_radio_distortion(packet: Dictionary, weight: float) -> void:
	if distortion == null:
		return
	distortion.mode = _distortion_mode(
		int(packet.get("distortion_mode", 3))
	)
	var target_drive := float(packet.get("distortion_drive", 0.0))
	distortion.drive = lerpf(distortion.drive, target_drive, weight)
	var keep_hf_log := lerpf(
		log(maxf(distortion.keep_hf_hz, AcousticPathModifier.MIN_FILTER_HZ)),
		log(maxf(
			float(packet.get("distortion_keep_hf_hz", 20000.0)),
			AcousticPathModifier.MIN_FILTER_HZ
		)),
		weight
	)
	distortion.keep_hf_hz = exp(keep_hf_log)
	distortion.post_gain = lerpf(
		distortion.post_gain,
		float(packet.get("distortion_post_gain_db", 0.0)),
		weight
	)
	AudioServer.set_bus_effect_enabled(
		bus_index,
		_distortion_effect_index,
		_persistent_processing
		or distortion.drive > 0.0001
		or target_drive > 0.0001
	)


static func _lerp_frequency(from_hz: float, to_hz: float, weight: float) -> float:
	var safe_from := maxf(from_hz, AcousticPathModifier.MIN_FILTER_HZ)
	var safe_to := maxf(to_hz, AcousticPathModifier.MIN_FILTER_HZ)
	return exp(lerpf(log(safe_from), log(safe_to), clampf(weight, 0.0, 1.0)))


static func _distortion_mode(mode_index: int) -> int:
	match mode_index:
		0:
			return AudioEffectDistortion.MODE_CLIP
		1:
			return AudioEffectDistortion.MODE_ATAN
		2:
			return AudioEffectDistortion.MODE_LOFI
		4:
			return AudioEffectDistortion.MODE_WAVESHAPE
		_:
			return AudioEffectDistortion.MODE_OVERDRIVE


func _ensure_effect_layout(include_distortion: bool) -> void:
	var expected_count := 8 if include_distortion else 6
	var valid := AudioServer.get_bus_effect_count(bus_index) == expected_count
	var offset := 1 if include_distortion else 0
	if valid and include_distortion:
		valid = AudioServer.get_bus_effect(bus_index, 0) is AudioEffectDistortion
	if valid:
		valid = (
			AudioServer.get_bus_effect(bus_index, offset) is AudioEffectEQ6
			and AudioServer.get_bus_effect(bus_index, offset + 1)
			is AudioEffectLowPassFilter
			and AudioServer.get_bus_effect(bus_index, offset + 2)
			is AudioEffectHighPassFilter
			and (
				(
					not include_distortion
					and AudioServer.get_bus_effect(bus_index, offset + 3)
					is AudioEffectDelay
					and AudioServer.get_bus_effect(bus_index, offset + 4)
					is AudioEffectReverb
					and AudioServer.get_bus_effect(bus_index, offset + 5)
					is AudioEffectLowPassFilter
				)
				or (
					include_distortion
					and AudioServer.get_bus_effect(bus_index, offset + 3)
					is AudioEffectSpectrumAnalyzer
					and AudioServer.get_bus_effect(bus_index, offset + 4)
					is AudioEffectDelay
					and AudioServer.get_bus_effect(bus_index, offset + 5)
					is AudioEffectReverb
					and AudioServer.get_bus_effect(bus_index, offset + 6)
					is AudioEffectLowPassFilter
				)
			)
		)
	if not valid:
		for effect_index: int in range(
			AudioServer.get_bus_effect_count(bus_index) - 1,
			-1,
			-1
		):
			AudioServer.remove_bus_effect(bus_index, effect_index)
		if include_distortion:
			AudioServer.add_bus_effect(bus_index, AudioEffectDistortion.new())
		AudioServer.add_bus_effect(bus_index, AudioEffectEQ6.new())
		AudioServer.add_bus_effect(bus_index, AudioEffectLowPassFilter.new())
		AudioServer.add_bus_effect(bus_index, AudioEffectHighPassFilter.new())
		if include_distortion:
			var analyzer := AudioEffectSpectrumAnalyzer.new()
			analyzer.buffer_length = 0.25
			analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
			AudioServer.add_bus_effect(bus_index, analyzer)
		var delay := AudioEffectDelay.new()
		delay.dry = 1.0
		delay.tap1_active = true
		delay.tap1_delay_ms = 40.0
		delay.tap1_level_db = EARLY_REFLECTION_SILENT_DB
		delay.tap2_active = true
		delay.tap2_delay_ms = 80.0
		delay.tap2_level_db = EARLY_REFLECTION_SILENT_DB
		delay.feedback_active = false
		AudioServer.add_bus_effect(bus_index, delay)
		AudioServer.add_bus_effect(bus_index, AudioEffectReverb.new())
		var tail_filter := AudioEffectLowPassFilter.new()
		tail_filter.cutoff_hz = AcousticPathModifier.MAX_FILTER_HZ
		tail_filter.resonance = 0.5
		AudioServer.add_bus_effect(bus_index, tail_filter)

	_distortion_effect_index = 0 if include_distortion else -1
	_equalizer_effect_index = 1 if include_distortion else 0
	_lowpass_effect_index = _equalizer_effect_index + 1
	_highpass_effect_index = _equalizer_effect_index + 2
	_spectrum_effect_index = _equalizer_effect_index + 3 if include_distortion else -1
	_early_delay_effect_index = (
		_spectrum_effect_index + 1
		if include_distortion
		else _equalizer_effect_index + 3
	)
	_reverb_effect_index = (
		_early_delay_effect_index + 1
	)
	_tail_lowpass_effect_index = _reverb_effect_index + 1
	distortion = (
		AudioServer.get_bus_effect(bus_index, _distortion_effect_index)
		as AudioEffectDistortion
		if include_distortion
		else null
	)
	equalizer = AudioServer.get_bus_effect(
		bus_index,
		_equalizer_effect_index
	) as AudioEffectEQ6
	lowpass = AudioServer.get_bus_effect(
		bus_index,
		_lowpass_effect_index
	) as AudioEffectLowPassFilter
	highpass = AudioServer.get_bus_effect(
		bus_index,
		_highpass_effect_index
	) as AudioEffectHighPassFilter
	early_delay = AudioServer.get_bus_effect(
		bus_index,
		_early_delay_effect_index
	) as AudioEffectDelay
	reverb = AudioServer.get_bus_effect(
		bus_index,
		_reverb_effect_index
	) as AudioEffectReverb
	tail_lowpass = AudioServer.get_bus_effect(
		bus_index,
		_tail_lowpass_effect_index
	) as AudioEffectLowPassFilter
	AudioServer.set_bus_effect_enabled(
		bus_index,
		_tail_lowpass_effect_index,
		false
	)
	if reverb != null:
		# Delay topology is initialized once while the bus is silent, never rewritten on the hot path.
		reverb.spread = REALTIME_SAFE_REVERB_SPREAD
	spectrum_analyzer = (
		AudioServer.get_bus_effect(bus_index, _spectrum_effect_index)
		as AudioEffectSpectrumAnalyzer
		if include_distortion
		else null
	)
	spectrum_analyzer_instance = (
		AudioServer.get_bus_effect_instance(bus_index, _spectrum_effect_index)
		as AudioEffectSpectrumAnalyzerInstance
		if include_distortion
		else null
	)
