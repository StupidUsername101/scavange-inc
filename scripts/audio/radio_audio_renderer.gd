class_name RadioAudioRenderer
extends Node

signal acoustic_perception_sample(
	source_id: int,
	apparent_position: Vector3,
	received_intensity: float,
	band_gain: Vector3,
	enclosure: float
)

const LISTENER_ACTIVITY := preload(
	"res://scripts/audio/listener_acoustic_activity.gd"
)
const MUSIC_VISUAL_ENVELOPES := preload(
	"res://scripts/audio/music_visual_envelope_catalog.gd"
)
const MAX_RADIO_VOICES := 8
const BUS_PREFIX := "ScavangeRadioVoice"
const SHARED_PROGRAM_BUS_PREFIX := "ScavangeSharedProgram"
const START_IMMEDIATELY_SECONDS := 0.005
const POSITION_FOLLOW_SPEED := 32.0
const EFFECT_FOLLOW_SPEED := 38.0
const VOLUME_FOLLOW_SPEED := 36.0
const VOLUME_MAX_SLEW_DB_PER_SECOND := 42.0
const SHARED_DIRECT_EFFECT_FOLLOW_SPEED := 28.0
const SHARED_LATE_FIELD_FOLLOW_SPEED := 8.0
const SHARED_LATE_FIELD_MAX_SLEW_DB_PER_SECOND := 16.0
const SHARED_LATE_FIELD_BLOOM_MAX_GAIN_DB := 1.5
const SHARED_DIRECTIONAL_REDISTRIBUTION_MAX_GAIN_DB := 12.0
const MISSING_STATE_FADE_DB_PER_SECOND := 120.0
const MISSING_STATE_RELEASE_DB := -72.0
const NEW_VOICE_FADE_IN_DB := 12.0
const VISUAL_ATTACK_SPEED := 72.0
const VISUAL_RELEASE_SPEED := 22.0
const VISUAL_BASELINE_ATTACK_SPEED := 2.4
const VISUAL_BASELINE_RELEASE_SPEED := 1.4
const VISUAL_SUSTAIN_WEIGHT := 0.18
const VISUAL_ONSET_LIFT_GAIN := 1.8
const VISUAL_ONSET_FLUX_GAIN := 2.4
const VISUAL_INPUT_FLOOR := 0.006
const VISUAL_INPUT_CEILING := 0.32
const VISUAL_MAX_ATTENUATION_COMPENSATION_DB := 24.0
const VISUAL_BASS_RANGE_HZ := Vector2(45.0, 220.0)
const VISUAL_BODY_RANGE_HZ := Vector2(220.0, 1800.0)
const SPECTRAL_BLOOM_RANGE_HZ := Vector2(1800.0, 9000.0)
const SPECTRAL_BLOOM_MAX_ATTENUATION_COMPENSATION_DB := 18.0
const SPECTRAL_BLOOM_ATTACK_SPEED := 3.0
const SPECTRAL_BLOOM_RELEASE_SPEED := 1.25
const LISTENER_ACOUSTIC_ATTACK_SPEED := 18.0
const LISTENER_ACOUSTIC_RELEASE_SPEED := 4.0
const ACOUSTIC_PERCEPTION_SAMPLE_SECONDS := 1.0 / 15.0
const CONTINUOUS_MIX_BUS := &"ScavangeContinuousWorldAudio"
const CONTINUOUS_LIMITER_CEILING_DB := -0.3
const CONTINUOUS_LIMITER_RELEASE_SECONDS := 0.08
const DRIFT_CHECK_INTERVAL_USEC := 2000000
const DRIFT_HARD_RESYNC_SECONDS := 1.5
const FOREGROUND_DUCK_MAX_DB := 5.0
const FOREGROUND_DUCK_HOLD_SECONDS := 0.045
const FOREGROUND_DUCK_RELEASE_SPEED := 14.0
const FOREGROUND_DUCK_ATTACK_SPEED := 110.0
const FOREGROUND_TRANSIENT_AUDIBLE_DB := Vector2(-36.0, -7.0)
const FOREGROUND_RADIO_MASKING_DB := Vector2(-27.0, -5.0)
const SHARED_REVERB_PARAMETER_KEYS := [
	&"reverb_room_size",
	&"reverb_damping",
	&"reverb_predelay_msec",
	&"reverb_predelay_feedback",
	&"reverb_hipass",
	&"reverb_decay_seconds",
]
const SHARED_REVERB_ACCUMULATOR_KEYS := [
	&"reverb_room_size_sum",
	&"reverb_damping_sum",
	&"reverb_predelay_msec_sum",
	&"reverb_predelay_feedback_sum",
	&"reverb_hipass_sum",
	&"reverb_decay_seconds_sum",
]
const STATIC_STREAM_SOURCE: AudioStreamWAV = preload(
	"res://assets/third_party/pizza_doggy/audio/rot/radio_static_loop.wav"
)

## Client-only continuous stream pool. Track selection, timing, position, attenuation, and acoustic
## filters all arrive from the authority; this node only owns local audio resources and DSP.

var _players: Array[AudioStreamPlayer3D] = []
var _static_players: Array[AudioStreamPlayer3D] = []
var _effect_racks: Array[SpatialAudioEffectRack] = []
var _slot_by_item_id: Dictionary[int, int] = {}
var _slot_item_ids := PackedInt32Array()
var _slot_revisions := PackedInt32Array()
var _slot_pending_revisions := PackedInt32Array()
var _slot_seen_generations := PackedInt32Array()
var _slot_pending_start_usec := PackedInt64Array()
var _slot_last_drift_check_usec := PackedInt64Array()
var _slot_retiring := PackedByteArray()
var _target_volumes_db := PackedFloat32Array()
var _visual_levels := PackedFloat32Array()
var _visual_program_baselines := PackedFloat32Array()
var _visual_previous_inputs := PackedFloat32Array()
var _spectral_room_bloom_levels := PackedFloat32Array()
var _slot_song_paths: Array[String] = []
var _target_positions: Array[Vector3] = []
var _latest_packets: Array[Dictionary] = []
var _effect_target_packets: Array[Dictionary] = []
var _pending_packets: Array[Dictionary] = []
var _pending_streams: Array[AudioStream] = []
var _snapshot_packets: Array[Dictionary] = []
var _slot_shared_program_group_ids := PackedInt64Array()
var _shared_program_group_ids := PackedInt64Array()
var _shared_program_band_power_sums: Array[Vector3] = []
var _shared_program_band_amplitude_sums: Array[Vector3] = []
var _shared_program_offsets := PackedFloat32Array()
var _shared_program_start_delays := PackedFloat32Array()
var _shared_program_group_slots := PackedInt32Array()
var _shared_program_late_field_enabled := PackedByteArray()
var _shared_program_acoustic_accumulators: Array[Dictionary] = []
var _shared_program_bus_names: Array[StringName] = []
var _shared_program_racks: Array[SpatialAudioEffectRack] = []
var _shared_program_players: Array[AudioStreamPlayer] = []
var _shared_program_bus_group_ids := PackedInt64Array()
var _shared_program_target_packets: Array[Dictionary] = []
var _shared_program_target_volumes_db := PackedFloat32Array()
var _shared_program_group_active := PackedByteArray()
var _shared_program_revisions := PackedInt32Array()
var _shared_program_song_paths: Array[String] = []
var _static_stream: AudioStreamWAV
var _generation := 0
var _foreground_duck_envelope := 0.0
var _foreground_duck_hold_remaining := 0.0
var _listener_acoustic_intensity := 0.0
var _acoustic_perception_sample_remaining := 0.0


func _ready() -> void:
	set_process(true)


func submit_snapshot(raw_states: Dictionary) -> void:
	_generation += 1
	if raw_states.is_empty() and _players.is_empty():
		return
	_ensure_pool()
	_snapshot_packets.clear()
	for raw_state: Variant in raw_states.values():
		var packet := RadioStatePacket.sanitize(raw_state)
		if packet.is_empty():
			continue
		_snapshot_packets.append(packet)
	_prepare_shared_program_mix(_snapshot_packets)
	for packet: Dictionary in _snapshot_packets:
		var item_id := int(packet["item_id"])
		var slot_index := int(_slot_by_item_id.get(item_id, -1))
		if slot_index < 0:
			slot_index = _allocate_slot(packet)
		if slot_index < 0:
			continue
		_slot_seen_generations[slot_index] = _generation
		_update_slot(slot_index, packet)

	for slot_index: int in range(_players.size()):
		if (
			_slot_item_ids[slot_index] >= 0
			and _slot_seen_generations[slot_index] != _generation
		):
			_begin_slot_fade_out(slot_index)


func _prepare_shared_program_mix(packets: Array[Dictionary]) -> void:
	_shared_program_group_ids.clear()
	_shared_program_band_power_sums.clear()
	_shared_program_band_amplitude_sums.clear()
	_shared_program_offsets.clear()
	_shared_program_start_delays.clear()
	_shared_program_group_slots.clear()
	_shared_program_late_field_enabled.clear()
	_shared_program_acoustic_accumulators.clear()
	_shared_program_group_active.fill(0)
	_shared_program_target_volumes_db.fill(
		AcousticPathModifier.MIN_VOLUME_DB
	)
	for packet: Dictionary in packets:
		var group_id := int(packet.get("shared_program_group_id", -1))
		if group_id < 0:
			continue
		var group_index := _shared_program_group_index(group_id)
		if group_index < 0:
			group_index = _shared_program_group_ids.size()
			_shared_program_group_ids.append(group_id)
			_shared_program_band_power_sums.append(Vector3.ZERO)
			_shared_program_band_amplitude_sums.append(Vector3.ZERO)
			_shared_program_offsets.append(0.0)
			_shared_program_start_delays.append(INF)
			_shared_program_group_slots.append(
				_ensure_shared_program_group_slot(group_id)
			)
			_shared_program_late_field_enabled.append(0)
			_shared_program_acoustic_accumulators.append(
				_new_shared_program_acoustic_accumulator()
			)
		var late_field_enabled := bool(packet.get(
			"shared_program_late_field_enabled",
			true
		))
		if late_field_enabled:
			_shared_program_late_field_enabled[group_index] = 1
		var amplitude := db_to_linear(
			float(packet.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB))
		)
		var reverb_mix := SpatialAudioEffectRack.power_normalized_reverb_mix(
			float(packet.get("reverb_send", 0.0))
		)
		# When this group deliberately omits the synthesized late return, do not reserve wet energy
		# and make the experiment quieter. Geometry-derived propagation energy remains in volume_db.
		var direct_mix := reverb_mix.x if late_field_enabled else 1.0
		var direct_amplitude := amplitude * direct_mix
		# `volume_db` contains both path-direct and diffuse room energy. The diffuse recovery is
		# listener-space energy, so letting it weight each phase-locked cabinet's 3D voice makes
		# distant cabinets appear to sit beside the listener and collapses nearest-speaker cues.
		# Retain the propagated group power in the numerator below, but use only path-direct energy
		# to distribute that coherent pressure among physical cabinet positions. The shared late
		# return is accumulated from the untouched packet, so Hall and total program level remain.
		var diffuse_directional_rejection_db := (
			clampf(
				float(packet.get("diffuse_field_gain_db", 0.0)),
				0.0,
				AcousticPathModifier.MAX_VOLUME_DB
			)
			if late_field_enabled
			else 0.0
		)
		var directional_amplitude := (
			direct_amplitude
			* db_to_linear(-diffuse_directional_rejection_db)
		)
		var band_gain: Vector3 = packet.get("band_gain", Vector3.ONE)
		_shared_program_band_power_sums[group_index] += Vector3(
			direct_amplitude * direct_amplitude * band_gain.x * band_gain.x,
			direct_amplitude * direct_amplitude * band_gain.y * band_gain.y,
			direct_amplitude * direct_amplitude * band_gain.z * band_gain.z
		)
		_shared_program_band_amplitude_sums[group_index] += (
			band_gain * directional_amplitude
		)
		packet["shared_program_direct_gain_db"] = linear_to_db(
			maxf(
				direct_mix
				* db_to_linear(-diffuse_directional_rejection_db),
				0.000001
			)
		)
		packet["shared_program_diffuse_directional_rejection_db"] = (
			diffuse_directional_rejection_db
		)
		if late_field_enabled:
			_accumulate_shared_program_acoustics(
				_shared_program_acoustic_accumulators[group_index],
				packet
			)
		_shared_program_offsets[group_index] = maxf(
			_shared_program_offsets[group_index],
			float(packet.get(
				"program_playback_offset_seconds",
				packet.get("playback_offset_seconds", 0.0)
			))
		)
		_shared_program_start_delays[group_index] = minf(
			_shared_program_start_delays[group_index],
			float(packet.get("start_delay_seconds", 0.0))
		)

	for packet: Dictionary in packets:
		var group_id := int(packet.get("shared_program_group_id", -1))
		if group_id < 0:
			continue
		var group_index := _shared_program_group_index(group_id)
		if group_index < 0:
			continue
		var band_normalization := shared_program_band_normalization(
			_shared_program_band_power_sums[group_index],
			_shared_program_band_amplitude_sums[group_index]
		)
		# Put the least-attenuated band in the scalar gain, then attenuate the other bands in EQ.
		# Directional redistribution may lift one cabinet, but the bounded group normalization keeps
		# the coherent sum equal to the already-authoritative network power in every band.
		var scalar_normalization := maxf(
			band_normalization.x,
			maxf(band_normalization.y, band_normalization.z)
		)
		var normalization_db := linear_to_db(maxf(scalar_normalization, 0.000001))
		var band_correction := band_normalization / maxf(
			scalar_normalization,
			0.000001
		)
		var source_bands: Vector3 = packet.get("band_gain", Vector3.ONE)
		packet["band_gain"] = Vector3(
			clampf(source_bands.x * band_correction.x, 0.0, 4.0),
			clampf(source_bands.y * band_correction.y, 0.0, 4.0),
			clampf(source_bands.z * band_correction.z, 0.0, 4.0)
		)
		packet["volume_db"] = maxf(
			float(packet.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB))
			+ float(packet.get("shared_program_direct_gain_db", 0.0))
			+ normalization_db,
			AcousticPathModifier.MIN_VOLUME_DB
		)
		packet["playback_offset_seconds"] = _shared_program_offsets[group_index]
		packet["start_delay_seconds"] = _shared_program_start_delays[group_index]
		packet["shared_program_normalization_db"] = normalization_db
		packet["shared_program_band_normalization"] = band_normalization

	for group_index: int in range(_shared_program_group_ids.size()):
		if _shared_program_late_field_enabled[group_index] == 0:
			continue
		var group_slot := _shared_program_group_slots[group_index]
		if group_slot < 0:
			continue
		var target := _finalize_shared_program_acoustics(
			_shared_program_acoustic_accumulators[group_index]
		)
		_shared_program_target_packets[group_slot] = target
		_shared_program_target_volumes_db[group_slot] = float(
			target.get(
				"late_field_volume_db",
				AcousticPathModifier.MIN_VOLUME_DB
			)
		)
		_shared_program_group_active[group_slot] = 1


static func _new_shared_program_acoustic_accumulator() -> Dictionary:
	return {
		"power_sum": 0.0,
		"wet_power_sum": 0.0,
		"reverb_send_power_sum": 0.0,
		"parameter_weight_sum": 0.0,
		"reverb_room_size_sum": 0.0,
		"reverb_damping_sum": 0.0,
		"reverb_predelay_msec_sum": 0.0,
		"reverb_predelay_feedback_sum": 0.0,
		"reverb_hipass_sum": 0.0,
		"reverb_decay_seconds_sum": 0.0,
		"band_power_sum": Vector3.ZERO,
		"lowpass_log_sum": 0.0,
		"highpass_log_sum": 0.0,
		"resonance_sum": 0.0,
	}


static func _accumulate_shared_program_acoustics(
	accumulator: Dictionary,
	packet: Dictionary
) -> void:
	var amplitude := db_to_linear(
		float(packet.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB))
	)
	var power := amplitude * amplitude
	var reverb_send := clampf(float(packet.get("reverb_send", 0.0)), 0.0, 1.0)
	var reverb_mix := SpatialAudioEffectRack.power_normalized_reverb_mix(
		reverb_send
	)
	var wet_power := power * reverb_mix.y * reverb_mix.y
	# Room colour belongs to the energy feeding the late field. A tiny power floor retains stable
	# coefficients while a group fades completely outdoors instead of snapping to defaults.
	var parameter_weight := maxf(wet_power, power * 0.0001)
	accumulator["power_sum"] = float(accumulator["power_sum"]) + power
	accumulator["wet_power_sum"] = float(accumulator["wet_power_sum"]) + wet_power
	accumulator["reverb_send_power_sum"] = (
		float(accumulator["reverb_send_power_sum"])
		+ power * reverb_send * reverb_send
	)
	accumulator["parameter_weight_sum"] = (
		float(accumulator["parameter_weight_sum"]) + parameter_weight
	)
	var band_gain: Vector3 = packet.get("band_gain", Vector3.ONE)
	var accumulated_band_power: Vector3 = accumulator.get(
		"band_power_sum",
		Vector3.ZERO
	)
	accumulator["band_power_sum"] = (
		accumulated_band_power + Vector3(
			band_gain.x * band_gain.x,
			band_gain.y * band_gain.y,
			band_gain.z * band_gain.z
		) * parameter_weight
	)
	accumulator["lowpass_log_sum"] = (
		float(accumulator["lowpass_log_sum"])
		+ log(maxf(
			float(packet.get("lowpass_hz", AcousticPathModifier.MAX_FILTER_HZ)),
			AcousticPathModifier.MIN_FILTER_HZ
		)) * parameter_weight
	)
	accumulator["highpass_log_sum"] = (
		float(accumulator["highpass_log_sum"])
		+ log(maxf(
			float(packet.get("highpass_hz", AcousticPathModifier.MIN_FILTER_HZ)),
			AcousticPathModifier.MIN_FILTER_HZ
		)) * parameter_weight
	)
	accumulator["resonance_sum"] = (
		float(accumulator["resonance_sum"])
		+ float(packet.get("resonance", 0.0)) * parameter_weight
	)
	for key_index: int in range(SHARED_REVERB_PARAMETER_KEYS.size()):
		var key: StringName = SHARED_REVERB_PARAMETER_KEYS[key_index]
		var sum_key: StringName = SHARED_REVERB_ACCUMULATOR_KEYS[key_index]
		accumulator[sum_key] = (
			float(accumulator[sum_key])
			+ float(packet.get(key, _shared_reverb_default(key))) * parameter_weight
		)


static func _finalize_shared_program_acoustics(accumulator: Dictionary) -> Dictionary:
	var power_sum := maxf(float(accumulator.get("power_sum", 0.0)), 0.000000000001)
	var wet_power_sum := maxf(float(accumulator.get("wet_power_sum", 0.0)), 0.0)
	var reverb_send_power_sum := maxf(
		float(accumulator.get("reverb_send_power_sum", 0.0)),
		0.0
	)
	var parameter_weight_sum := maxf(
		float(accumulator.get("parameter_weight_sum", 0.0)),
		0.000000000001
	)
	var band_power_sum: Vector3 = accumulator.get(
		"band_power_sum",
		Vector3(parameter_weight_sum, parameter_weight_sum, parameter_weight_sum)
	)
	return {
		"band_gain": Vector3(
			sqrt(maxf(band_power_sum.x / parameter_weight_sum, 0.0)),
			sqrt(maxf(band_power_sum.y / parameter_weight_sum, 0.0)),
			sqrt(maxf(band_power_sum.z / parameter_weight_sum, 0.0))
		),
		"lowpass_hz": exp(
			float(accumulator["lowpass_log_sum"]) / parameter_weight_sum
		),
		"highpass_hz": exp(
			float(accumulator["highpass_log_sum"]) / parameter_weight_sum
		),
		"resonance": float(accumulator["resonance_sum"]) / parameter_weight_sum,
		"reverb_send": sqrt(reverb_send_power_sum / power_sum),
		"late_field_volume_db": clampf(
			10.0 * log(maxf(wet_power_sum, 0.000000000001)) / log(10.0),
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		),
		"reverb_room_size": float(accumulator["reverb_room_size_sum"]) / parameter_weight_sum,
		"reverb_damping": float(accumulator["reverb_damping_sum"]) / parameter_weight_sum,
		"reverb_predelay_msec": float(accumulator["reverb_predelay_msec_sum"]) / parameter_weight_sum,
		"reverb_predelay_feedback": float(accumulator["reverb_predelay_feedback_sum"]) / parameter_weight_sum,
		"reverb_hipass": float(accumulator["reverb_hipass_sum"]) / parameter_weight_sum,
		"reverb_decay_seconds": clampf(
			float(accumulator["reverb_decay_seconds_sum"])
			/ parameter_weight_sum,
			AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
			AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
		),
	}


static func _shared_reverb_default(key: StringName) -> float:
	match key:
		&"reverb_room_size":
			return 0.35
		&"reverb_damping":
			return 0.5
		&"reverb_predelay_msec":
			return 8.0
		&"reverb_predelay_feedback":
			return 0.25
		&"reverb_hipass":
			return 0.05
		&"reverb_decay_seconds":
			return 0.25
	return 0.0


func _shared_program_group_index(group_id: int) -> int:
	for group_index: int in range(_shared_program_group_ids.size()):
		if _shared_program_group_ids[group_index] == group_id:
			return group_index
	return -1


func _ensure_shared_program_group_slot(group_id: int) -> int:
	for group_slot: int in range(_shared_program_bus_group_ids.size()):
		if _shared_program_bus_group_ids[group_slot] == group_id:
			return group_slot
	for group_slot: int in range(_shared_program_bus_group_ids.size()):
		if _shared_program_bus_group_ids[group_slot] < 0:
			_shared_program_bus_group_ids[group_slot] = group_id
			_shared_program_racks[group_slot].reset_state()
			_shared_program_target_packets[group_slot] = {}
			AudioServer.set_bus_volume_db(
				_shared_program_racks[group_slot].bus_index,
				0.0
			)
			return group_slot
	return -1


func _shared_program_group_slot(group_id: int) -> int:
	for group_slot: int in range(_shared_program_bus_group_ids.size()):
		if _shared_program_bus_group_ids[group_slot] == group_id:
			return group_slot
	return -1


static func shared_program_normalization_db(
	power_sum: float,
	amplitude_sum: float
) -> float:
	# Phase-aligned copies would otherwise add pressure (+6.02 dB for two equal cabinets) while the
	# propagation model intentionally adds independent speaker power (+3.01 dB). This one group gain
	# makes the stable waveform sum equal the already-authoritative energy sum at the listener.
	var safe_power := maxf(power_sum, 0.000000000001)
	var safe_amplitude := maxf(amplitude_sum, 0.000001)
	return minf(
		10.0 * log(safe_power) / log(10.0)
		- 20.0 * log(safe_amplitude) / log(10.0),
		0.0
	)


static func shared_program_band_normalization(
	power_sum: Vector3,
	amplitude_sum: Vector3
) -> Vector3:
	return Vector3(
		_shared_program_band_normalization_component(power_sum.x, amplitude_sum.x),
		_shared_program_band_normalization_component(power_sum.y, amplitude_sum.y),
		_shared_program_band_normalization_component(power_sum.z, amplitude_sum.z)
	)


static func _shared_program_band_normalization_component(
	power_sum: float,
	amplitude_sum: float
) -> float:
	if power_sum <= 0.000000000001 or amplitude_sum <= 0.000001:
		return 1.0
	# Diffuse rejection can make the directional weights smaller than the propagated group power.
	# A bounded positive normalization is therefore valid: it restores exactly the same coherent
	# group pressure while redistributing it toward cabinets that still have real direct support.
	return clampf(
		sqrt(power_sum) / amplitude_sum,
		0.0,
		db_to_linear(SHARED_DIRECTIONAL_REDISTRIBUTION_MAX_GAIN_DB)
	)


func reset_session() -> void:
	for slot_index: int in range(_players.size()):
		_release_slot(slot_index)
	for rack: SpatialAudioEffectRack in _effect_racks:
		rack.reset_state()
	for group_slot: int in range(_shared_program_racks.size()):
		_shared_program_players[group_slot].stop()
		_shared_program_players[group_slot].stream = null
		_shared_program_racks[group_slot].reset_state()
		_shared_program_bus_group_ids[group_slot] = -1
		_shared_program_target_packets[group_slot] = {}
		_shared_program_target_volumes_db[group_slot] = (
			AcousticPathModifier.MIN_VOLUME_DB
		)
		_shared_program_group_active[group_slot] = 0
		_shared_program_revisions[group_slot] = -1
		_shared_program_song_paths[group_slot] = ""
		AudioServer.set_bus_volume_db(
			_shared_program_racks[group_slot].bus_index,
			0.0
		)
	_generation = 0
	_foreground_duck_envelope = 0.0
	_foreground_duck_hold_remaining = 0.0
	_listener_acoustic_intensity = 0.0
	_acoustic_perception_sample_remaining = 0.0


func get_debug_state() -> Dictionary:
	var active_count := 0
	var active_static_count := 0
	var retiring_count := 0
	var spectrum_analyzer_count := 0
	var maximum_spectral_room_bloom := 0.0
	var active_shared_late_field_count := 0
	var shared_program_slot_reverb_count := 0
	var shared_program_direct_mix_count := 0
	for slot_index: int in range(_slot_item_ids.size()):
		var item_id := _slot_item_ids[slot_index]
		if item_id >= 0:
			active_count += 1
			maximum_spectral_room_bloom = maxf(
				maximum_spectral_room_bloom,
				_spectral_room_bloom_levels[slot_index]
			)
			retiring_count += 1 if _slot_retiring[slot_index] != 0 else 0
			if _static_players[slot_index].playing:
				active_static_count += 1
	for rack: SpatialAudioEffectRack in _effect_racks:
		if rack.spectrum_analyzer != null:
			spectrum_analyzer_count += 1
	for group_slot: int in range(_shared_program_racks.size()):
		if (
			_shared_program_bus_group_ids[group_slot] >= 0
			and not _shared_program_target_packets[group_slot].is_empty()
		):
			active_shared_late_field_count += 1
	for slot_index: int in range(_effect_racks.size()):
		if (
			_slot_item_ids[slot_index] >= 0
			and _slot_shared_program_group_ids[slot_index] >= 0
			and AudioServer.get_bus_send(_effect_racks[slot_index].bus_index)
			== CONTINUOUS_MIX_BUS
		):
			shared_program_direct_mix_count += 1
		if (
			_slot_item_ids[slot_index] >= 0
			and _slot_shared_program_group_ids[slot_index] >= 0
			and _effect_racks[slot_index].reverb != null
			and AudioServer.is_bus_effect_enabled(
				_effect_racks[slot_index].bus_index,
				_effect_racks[slot_index]._reverb_effect_index
			)
		):
			shared_program_slot_reverb_count += 1
	return {
		"voice_count": _players.size(),
		"static_voice_count": _static_players.size(),
		"active_count": active_count,
		"active_static_count": active_static_count,
		"retiring_count": retiring_count,
		"shared_static_bytes": (
			_static_stream.data.size() if _static_stream != null else 0
		),
		"distortion_rack_count": _effect_racks.size(),
		"spectrum_analyzer_count": spectrum_analyzer_count,
		"maximum_spectral_room_bloom": maximum_spectral_room_bloom,
		"continuous_mix_limiter": _continuous_mix_has_limiter(),
		"response_95_percent_msec": int(
			ceil(3000.0 / minf(EFFECT_FOLLOW_SPEED, VOLUME_FOLLOW_SPEED))
		),
		"foreground_duck_envelope": _foreground_duck_envelope,
		"listener_acoustic_intensity": _listener_acoustic_intensity,
		"shared_program_group_count": _shared_program_group_ids.size(),
		"active_shared_late_field_count": active_shared_late_field_count,
		"shared_program_slot_reverb_count": shared_program_slot_reverb_count,
		"shared_program_direct_mix_count": shared_program_direct_mix_count,
	}


func request_foreground_transient_space(
	strength: float,
	received_volume_db: float
) -> void:
	var audible_weight := smoothstep(
		FOREGROUND_TRANSIENT_AUDIBLE_DB.x,
		FOREGROUND_TRANSIENT_AUDIBLE_DB.y,
		clampf(received_volume_db, -80.0, 18.0)
	)
	var requested_envelope := clampf(strength, 0.0, 1.0) * audible_weight
	if requested_envelope <= 0.0001:
		return
	_foreground_duck_envelope = maxf(
		_foreground_duck_envelope,
		requested_envelope
	)
	_foreground_duck_hold_remaining = maxf(
		_foreground_duck_hold_remaining,
		FOREGROUND_DUCK_HOLD_SECONDS
	)


func _process(delta: float) -> void:
	_update_foreground_duck(delta)
	_acoustic_perception_sample_remaining -= maxf(delta, 0.0)
	var publish_perception_sample := _acoustic_perception_sample_remaining <= 0.0
	if publish_perception_sample:
		_acoustic_perception_sample_remaining = ACOUSTIC_PERCEPTION_SAMPLE_SECONDS
	var listener_acoustic_energy := 0.0
	var now_usec := Time.get_ticks_usec()
	var position_weight := _follow_weight(POSITION_FOLLOW_SPEED, delta)
	var effect_weight := _follow_weight(EFFECT_FOLLOW_SPEED, delta)
	var volume_weight := _follow_weight(VOLUME_FOLLOW_SPEED, delta)
	for slot_index: int in range(_players.size()):
		if _slot_item_ids[slot_index] < 0:
			_effect_racks[slot_index].update_tail_floor(false, delta)
			continue
		if (
			_slot_pending_revisions[slot_index] >= 0
			and _slot_pending_start_usec[slot_index] <= now_usec
		):
			_activate_pending(slot_index)
		var player := _players[slot_index]
		player.global_position = player.global_position.lerp(
			_target_positions[slot_index],
			position_weight
		)
		var duck_db := _foreground_duck_db(
			_target_volumes_db[slot_index]
		)
		var desired_music_volume_db := (
			_target_volumes_db[slot_index] + duck_db
		)
		var slot_volume_weight := (
			_follow_weight(FOREGROUND_DUCK_ATTACK_SPEED, delta)
			if desired_music_volume_db < player.volume_db
			else volume_weight
		)
		var volume_slew := (
			MISSING_STATE_FADE_DB_PER_SECOND
			if _slot_retiring[slot_index] != 0
			else VOLUME_MAX_SLEW_DB_PER_SECOND
		)
		player.volume_db = _approach_volume_db(
			player.volume_db,
			desired_music_volume_db,
			slot_volume_weight,
			volume_slew * maxf(delta, 0.0)
		)
		var effect_target := _effect_target_packets[slot_index]
		var static_player := _static_players[slot_index]
		static_player.global_position = player.global_position
		var static_enabled := _receiver_static_enabled(effect_target)
		var desired_static_volume_db := (
			_target_volumes_db[slot_index]
			+ duck_db
			+ float(effect_target.get("static_mix_db", -60.0))
			- float(effect_target.get("program_normalization_gain_db", 0.0))
			- float(effect_target.get("program_reference_gain_db", 0.0))
			if static_enabled
			else AcousticPathModifier.MIN_VOLUME_DB
		)
		static_player.volume_db = _approach_volume_db(
			static_player.volume_db,
			desired_static_volume_db,
			slot_volume_weight,
			volume_slew * maxf(delta, 0.0)
		)
		if (
			not static_enabled
			and static_player.playing
			and static_player.volume_db <= MISSING_STATE_RELEASE_DB
		):
			static_player.stop()
		var rack := _effect_racks[slot_index]
		var bass_magnitude := Vector2.ZERO
		var body_magnitude := Vector2.ZERO
		var brilliance_magnitude := Vector2.ZERO
		if player.playing:
			bass_magnitude = rack.sample_spectrum_range(
				VISUAL_BASS_RANGE_HZ.x,
				VISUAL_BASS_RANGE_HZ.y
			)
			body_magnitude = rack.sample_spectrum_range(
				VISUAL_BODY_RANGE_HZ.x,
				VISUAL_BODY_RANGE_HZ.y
			)
			brilliance_magnitude = rack.sample_spectrum_range(
				SPECTRAL_BLOOM_RANGE_HZ.x,
				SPECTRAL_BLOOM_RANGE_HZ.y
			)
		var received_acoustic_intensity := LISTENER_ACTIVITY.from_spectrum(
			bass_magnitude,
			body_magnitude,
			brilliance_magnitude
		)
		if (
			publish_perception_sample
			and player.playing
			and received_acoustic_intensity > 0.001
		):
			acoustic_perception_sample.emit(
				_slot_item_ids[slot_index],
				player.global_position,
				received_acoustic_intensity,
				SafeVariant.vector3_strict_or(
					effect_target.get("band_gain"),
					Vector3.ONE
				),
				clampf(
					SafeVariant.finite_float_or(
						effect_target.get("environment_enclosure"),
						0.0
					),
					0.0,
					1.0
				)
			)
		listener_acoustic_energy += (
			received_acoustic_intensity * received_acoustic_intensity
		)
		var bloom_target := spectral_room_bloom_target(
			body_magnitude,
			brilliance_magnitude,
			player.volume_db,
			effect_target
		)
		var bloom_speed := (
			SPECTRAL_BLOOM_ATTACK_SPEED
			if bloom_target > _spectral_room_bloom_levels[slot_index]
			else SPECTRAL_BLOOM_RELEASE_SPEED
		)
		_spectral_room_bloom_levels[slot_index] = lerpf(
			_spectral_room_bloom_levels[slot_index],
			bloom_target,
			_follow_weight(bloom_speed, delta)
		)
		if not effect_target.is_empty():
			_update_early_reflection_pans(effect_target)
			var slot_effect_weight := (
				_follow_weight(SHARED_DIRECT_EFFECT_FOLLOW_SPEED, delta)
				if _slot_shared_program_group_ids[slot_index] >= 0
				else effect_weight
			)
			rack.approach_acoustic(
				effect_target,
				slot_effect_weight,
				_spectral_room_bloom_levels[slot_index],
				_slot_shared_program_group_ids[slot_index] >= 0
			)
			rack.approach_radio_distortion(effect_target, effect_weight)
		# A missing authoritative snapshot starts the voice's ordinary level fade, but the player is
		# still feeding real samples into this rack during that fade. Tail cleanup belongs after the
		# input has actually stopped; starting it from transport state filtered live music and made a
		# one-packet gap audible.
		rack.update_tail_floor(player.playing, delta)
		# Animate from the track's baked source envelope, not the listener's attenuated/filtered
		# signal. This keeps every master and every cabinet responsive even when room DSP removes
		# most of a visual-analysis band. Unknown newly-added tracks retain the live FFT fallback.
		var visual_input := MUSIC_VISUAL_ENVELOPES.sample_level(
			_slot_song_paths[slot_index],
			player.get_playback_position()
		)
		if visual_input < 0.0:
			visual_input = _normalized_visual_level(
				bass_magnitude,
				body_magnitude,
				player.volume_db,
				brilliance_magnitude
			)
		var visual_target := music_pulse_target(
			visual_input,
			_visual_previous_inputs[slot_index],
			_visual_program_baselines[slot_index]
		)
		var visual_speed := (
			VISUAL_ATTACK_SPEED
			if visual_target > _visual_levels[slot_index]
			else VISUAL_RELEASE_SPEED
		)
		_visual_levels[slot_index] = lerpf(
			_visual_levels[slot_index],
			visual_target,
			_follow_weight(visual_speed, delta)
		)
		var baseline_speed := (
			VISUAL_BASELINE_ATTACK_SPEED
			if visual_input > _visual_program_baselines[slot_index]
			else VISUAL_BASELINE_RELEASE_SPEED
		)
		_visual_program_baselines[slot_index] = lerpf(
			_visual_program_baselines[slot_index],
			visual_input,
			_follow_weight(baseline_speed, delta)
		)
		_visual_previous_inputs[slot_index] = visual_input
		if (
			_slot_retiring[slot_index] != 0
			and player.volume_db <= MISSING_STATE_RELEASE_DB
			and static_player.volume_db <= MISSING_STATE_RELEASE_DB
		):
			_release_slot(slot_index)
	_listener_acoustic_intensity = LISTENER_ACTIVITY.follow(
		_listener_acoustic_intensity,
		minf(sqrt(listener_acoustic_energy), 1.0),
		delta,
		LISTENER_ACOUSTIC_ATTACK_SPEED,
		LISTENER_ACOUSTIC_RELEASE_SPEED
	)
	_update_shared_program_late_fields(delta)


func _update_shared_program_late_fields(delta: float) -> void:
	var late_field_weight := _follow_weight(
		SHARED_LATE_FIELD_FOLLOW_SPEED,
		delta
	)
	for group_slot: int in range(_shared_program_racks.size()):
		var target := _shared_program_target_packets[group_slot]
		if target.is_empty():
			continue
		var player := _shared_program_players[group_slot]
		var group_id := _shared_program_bus_group_ids[group_slot]
		var bloom_weight_sum := 0.0
		var bloom_sum := 0.0
		for slot_index: int in range(_slot_item_ids.size()):
			if (
				_slot_item_ids[slot_index] < 0
				or _slot_shared_program_group_ids[slot_index] != group_id
			):
				continue
			var power := pow(10.0, _target_volumes_db[slot_index] / 10.0)
			bloom_weight_sum += power
			bloom_sum += _spectral_room_bloom_levels[slot_index] * power
		var spectral_bloom := (
			bloom_sum / bloom_weight_sum
			if bloom_weight_sum > 0.000000000001
			else 0.0
		)
		var bloom_gain_db := shared_late_field_bloom_gain_db(
			target,
			spectral_bloom
		)
		var target_volume_db := (
			_shared_program_target_volumes_db[group_slot]
			+ bloom_gain_db
		)
		var desired_volume_db := target_volume_db + _foreground_duck_db(
			target_volume_db
		)
		player.volume_db = _approach_volume_db(
			player.volume_db,
			desired_volume_db,
			late_field_weight,
			(
				MISSING_STATE_FADE_DB_PER_SECOND
				if _shared_program_group_active[group_slot] == 0
				else SHARED_LATE_FIELD_MAX_SLEW_DB_PER_SECOND
			) * maxf(delta, 0.0)
		)
		_shared_program_racks[group_slot].approach_acoustic(
			target,
			late_field_weight,
			spectral_bloom,
			false,
			true
		)
		_shared_program_racks[group_slot].update_tail_floor(
			player.playing,
			delta
		)
		if (
			_shared_program_group_active[group_slot] == 0
			and player.volume_db <= MISSING_STATE_RELEASE_DB
		):
			player.stop()
			player.stream = null
			_shared_program_revisions[group_slot] = -1
			_shared_program_song_paths[group_slot] = ""

static func shared_late_field_bloom_gain_db(
	packet: Dictionary,
	spectral_bloom: float
) -> float:
	var base_response := SpatialAudioEffectRack.spectral_bloom_reverb_response(
		packet,
		0.0
	)
	var bloom_response := SpatialAudioEffectRack.spectral_bloom_reverb_response(
		packet,
		spectral_bloom
	)
	var base_wet := SpatialAudioEffectRack.power_normalized_reverb_mix(
		base_response.x
	).y
	var bloom_wet := SpatialAudioEffectRack.power_normalized_reverb_mix(
		bloom_response.x
	).y
	if base_wet <= 0.000001 or bloom_wet <= base_wet:
		return 0.0
	return clampf(
		linear_to_db(bloom_wet / base_wet),
		0.0,
		SHARED_LATE_FIELD_BLOOM_MAX_GAIN_DB
	)


func _update_foreground_duck(delta: float) -> void:
	var release_delta := maxf(delta, 0.0)
	if _foreground_duck_hold_remaining > 0.0:
		var hold_delta := minf(
			_foreground_duck_hold_remaining,
			release_delta
		)
		_foreground_duck_hold_remaining -= hold_delta
		release_delta -= hold_delta
	if release_delta <= 0.0:
		return
	_foreground_duck_envelope = lerpf(
		_foreground_duck_envelope,
		0.0,
		_follow_weight(FOREGROUND_DUCK_RELEASE_SPEED, release_delta)
	)
	if _foreground_duck_envelope < 0.0001:
		_foreground_duck_envelope = 0.0


func _foreground_duck_db(radio_volume_db: float) -> float:
	var masking_weight := smoothstep(
		FOREGROUND_RADIO_MASKING_DB.x,
		FOREGROUND_RADIO_MASKING_DB.y,
		clampf(radio_volume_db, -80.0, 18.0)
	)
	return (
		-FOREGROUND_DUCK_MAX_DB
		* _foreground_duck_envelope
		* masking_weight
	)


static func _follow_weight(speed: float, delta: float) -> float:
	return 1.0 - exp(-maxf(speed, 0.0) * maxf(delta, 0.0))


static func _approach_volume_db(
	current_db: float,
	target_db: float,
	exponential_weight: float,
	maximum_step_db: float
) -> float:
	var exponential_target := lerpf(
		current_db,
		target_db,
		clampf(exponential_weight, 0.0, 1.0)
	)
	return move_toward(
		current_db,
		exponential_target,
		maxf(maximum_step_db, 0.0)
	)


func get_music_visual_level(
	item_id: int,
	shared_program_group_id := -1
) -> float:
	var slot_index := int(_slot_by_item_id.get(item_id, -1))
	if slot_index >= 0 and slot_index < _visual_levels.size():
		return _visual_levels[slot_index]
	if shared_program_group_id >= 0:
		for candidate_index: int in range(_slot_shared_program_group_ids.size()):
			if (
				_slot_item_ids[candidate_index] >= 0
				and _slot_shared_program_group_ids[candidate_index]
				== shared_program_group_id
			):
				return _visual_levels[candidate_index]
	return 0.0


func get_listener_acoustic_intensity() -> float:
	return _listener_acoustic_intensity


static func _normalized_visual_level(
	bass_magnitude: Vector2,
	body_magnitude: Vector2,
	voice_volume_db: float,
	brilliance_magnitude := Vector2.ZERO
) -> float:
	var bass_amplitude := maxf(bass_magnitude.x, bass_magnitude.y) * 1.25
	var body_amplitude := maxf(body_magnitude.x, body_magnitude.y) * 0.72
	var brilliance_amplitude := maxf(
		brilliance_magnitude.x,
		brilliance_magnitude.y
	) * 0.32
	var attenuation_compensation := db_to_linear(clampf(
		-voice_volume_db,
		0.0,
		VISUAL_MAX_ATTENUATION_COMPENSATION_DB
	))
	var compensated_amplitude := (
		maxf(
			bass_amplitude,
			maxf(body_amplitude, brilliance_amplitude)
		) * attenuation_compensation
	)
	# Leave useful headroom for mastered tracks. The old 0.16 ceiling made much of a song read as
	# constant full scale, so the visual envelope had no rhythmic information left to animate.
	return smoothstep(
		VISUAL_INPUT_FLOOR,
		VISUAL_INPUT_CEILING,
		compensated_amplitude
	)


static func music_pulse_target(
	visual_input: float,
	previous_input: float,
	program_baseline: float
) -> float:
	var safe_input := clampf(visual_input, 0.0, 1.0)
	var safe_previous := clampf(previous_input, 0.0, 1.0)
	var safe_baseline := clampf(program_baseline, 0.0, 1.0)
	# Spectral flux catches the leading edge of a kick. Lift above a slow program baseline keeps a
	# broad bass hit alive for more than one render frame. Both are relative, so quiet masters and
	# dense loud masters produce useful motion without a beat detector or per-frame allocations.
	var positive_flux := maxf(safe_input - safe_previous, 0.0)
	var relative_lift := (
		maxf(safe_input - safe_baseline, 0.0)
		/ maxf(1.0 - safe_baseline, 0.2)
	)
	var onset_drive := (
		relative_lift * VISUAL_ONSET_LIFT_GAIN
		+ positive_flux * VISUAL_ONSET_FLUX_GAIN
	)
	var transient := smoothstep(0.04, 0.72, onset_drive)
	var sustain := safe_input * VISUAL_SUSTAIN_WEIGHT
	return clampf(sustain + transient * (1.0 - sustain), 0.0, 1.0)


static func spectral_room_bloom_target(
	body_magnitude: Vector2,
	brilliance_magnitude: Vector2,
	voice_volume_db: float,
	packet: Dictionary
) -> float:
	var reverb_send := clampf(float(packet.get("reverb_send", 0.0)), 0.0, 1.0)
	var enclosure := clampf(
		float(packet.get("environment_enclosure", 0.0)),
		0.0,
		1.0
	)
	var high_reflectivity := clampf(
		float(packet.get("reverb_damping", 0.0)),
		0.0,
		1.0
	)
	if reverb_send <= 0.001 or enclosure <= 0.001:
		return 0.0
	var attenuation_compensation := db_to_linear(clampf(
		-voice_volume_db,
		0.0,
		SPECTRAL_BLOOM_MAX_ATTENUATION_COMPENSATION_DB
	))
	var body_amplitude := maxf(
		body_magnitude.x,
		body_magnitude.y
	) * attenuation_compensation
	var brilliance_amplitude := maxf(
		brilliance_magnitude.x,
		brilliance_magnitude.y
	) * attenuation_compensation
	# A ratio detects tonal brilliance independently of mastering loudness. The absolute gate keeps
	# quiet broadband receiver static and distant analyzer noise from opening the room.
	var brilliance_ratio := brilliance_amplitude / maxf(
		brilliance_amplitude + body_amplitude * 0.8,
		0.000001
	)
	var program_gate := smoothstep(0.018, 0.14, brilliance_amplitude)
	var spectral_gate := smoothstep(0.34, 0.72, brilliance_ratio)
	var room_gate := (
		smoothstep(0.18, 0.65, reverb_send)
		* smoothstep(0.30, 0.82, enclosure)
		* smoothstep(0.32, 0.88, high_reflectivity)
	)
	return clampf(program_gate * spectral_gate * room_gate, 0.0, 1.0)


func _ensure_pool() -> void:
	if not _players.is_empty():
		return
	_ensure_continuous_mix_bus()
	_ensure_shared_program_bus_pool()
	_static_stream = _make_static_stream()
	_slot_item_ids.resize(MAX_RADIO_VOICES)
	_slot_item_ids.fill(-1)
	_slot_revisions.resize(MAX_RADIO_VOICES)
	_slot_revisions.fill(-1)
	_slot_pending_revisions.resize(MAX_RADIO_VOICES)
	_slot_pending_revisions.fill(-1)
	_slot_seen_generations.resize(MAX_RADIO_VOICES)
	_slot_seen_generations.fill(0)
	_slot_pending_start_usec.resize(MAX_RADIO_VOICES)
	_slot_pending_start_usec.fill(0)
	_slot_last_drift_check_usec.resize(MAX_RADIO_VOICES)
	_slot_last_drift_check_usec.fill(0)
	_slot_retiring.resize(MAX_RADIO_VOICES)
	_slot_retiring.fill(0)
	_slot_shared_program_group_ids.resize(MAX_RADIO_VOICES)
	_slot_shared_program_group_ids.fill(-1)
	_target_volumes_db.resize(MAX_RADIO_VOICES)
	_target_volumes_db.fill(-80.0)
	_visual_levels.resize(MAX_RADIO_VOICES)
	_visual_levels.fill(0.0)
	_visual_program_baselines.resize(MAX_RADIO_VOICES)
	_visual_program_baselines.fill(0.0)
	_visual_previous_inputs.resize(MAX_RADIO_VOICES)
	_visual_previous_inputs.fill(0.0)
	_spectral_room_bloom_levels.resize(MAX_RADIO_VOICES)
	_spectral_room_bloom_levels.fill(0.0)

	for slot_index: int in range(MAX_RADIO_VOICES):
		var bus_name := StringName("%s%02d" % [BUS_PREFIX, slot_index])
		var rack := SpatialAudioEffectRack.attach(bus_name, true)
		AudioServer.set_bus_send(rack.bus_index, CONTINUOUS_MIX_BUS)
		_effect_racks.append(rack)
		var player := _make_voice_player(
			"RadioVoice%02d" % slot_index,
			bus_name
		)
		add_child(player)
		_players.append(player)
		var static_player := _make_voice_player(
			"RadioStatic%02d" % slot_index,
			bus_name
		)
		static_player.stream = _static_stream
		add_child(static_player)
		_static_players.append(static_player)
		_slot_song_paths.append("")
		_target_positions.append(Vector3.ZERO)
		_latest_packets.append({})
		_effect_target_packets.append({})
		_pending_packets.append({})
		_pending_streams.append(null)


func _ensure_shared_program_bus_pool() -> void:
	if not _shared_program_racks.is_empty():
		return
	_shared_program_bus_group_ids.resize(MAX_RADIO_VOICES)
	_shared_program_bus_group_ids.fill(-1)
	_shared_program_target_volumes_db.resize(MAX_RADIO_VOICES)
	_shared_program_target_volumes_db.fill(AcousticPathModifier.MIN_VOLUME_DB)
	_shared_program_group_active.resize(MAX_RADIO_VOICES)
	_shared_program_group_active.fill(0)
	_shared_program_revisions.resize(MAX_RADIO_VOICES)
	_shared_program_revisions.fill(-1)
	for group_slot: int in range(MAX_RADIO_VOICES):
		var bus_name := StringName(
			"%s%02d" % [SHARED_PROGRAM_BUS_PREFIX, group_slot]
		)
		var rack := SpatialAudioEffectRack.attach(bus_name)
		AudioServer.set_bus_send(rack.bus_index, CONTINUOUS_MIX_BUS)
		AudioServer.set_bus_volume_db(rack.bus_index, 0.0)
		_shared_program_bus_names.append(bus_name)
		_shared_program_racks.append(rack)
		_shared_program_target_packets.append({})
		var player := AudioStreamPlayer.new()
		player.name = "SharedProgramLateField%02d" % group_slot
		player.bus = bus_name
		player.max_polyphony = 1
		player.volume_db = AcousticPathModifier.MIN_VOLUME_DB
		add_child(player)
		_shared_program_players.append(player)
		_shared_program_song_paths.append("")


func _ensure_continuous_mix_bus() -> void:
	var mix_bus_index := AudioServer.get_bus_index(CONTINUOUS_MIX_BUS)
	if mix_bus_index < 0:
		AudioServer.add_bus()
		mix_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(mix_bus_index, CONTINUOUS_MIX_BUS)
	AudioServer.set_bus_send(mix_bus_index, &"Master")
	if (
		AudioServer.get_bus_effect_count(mix_bus_index) == 1
		and AudioServer.get_bus_effect(mix_bus_index, 0) is AudioEffectHardLimiter
	):
		return
	for effect_index: int in range(
		AudioServer.get_bus_effect_count(mix_bus_index) - 1,
		-1,
		-1
	):
		AudioServer.remove_bus_effect(mix_bus_index, effect_index)
	# Preserve normal multi-speaker dynamics and catch only true digital overs. The legacy soft
	# limiter began gain reduction at -3 dB, so coherent bass from the PA could pull the whole mix
	# down before it approached clipping.
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = CONTINUOUS_LIMITER_CEILING_DB
	limiter.pre_gain_db = 0.0
	limiter.release = CONTINUOUS_LIMITER_RELEASE_SECONDS
	AudioServer.add_bus_effect(mix_bus_index, limiter)


func _continuous_mix_has_limiter() -> bool:
	var mix_bus_index := AudioServer.get_bus_index(CONTINUOUS_MIX_BUS)
	return (
		mix_bus_index >= 0
		and AudioServer.get_bus_effect_count(mix_bus_index) == 1
		and AudioServer.get_bus_effect(mix_bus_index, 0) is AudioEffectHardLimiter
	)


static func _make_voice_player(
	player_name: String,
	bus_name: StringName
) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.bus = bus_name
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.max_polyphony = 1
	return player


static func _make_static_stream() -> AudioStreamWAV:
	# The selected receiver recording is duplicated once, then shared by every pooled static voice.
	var stream := STATIC_STREAM_SOURCE.duplicate(true) as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = maxi(roundi(stream.get_length() * float(stream.mix_rate)), 1)
	return stream


func _allocate_slot(packet: Dictionary) -> int:
	for slot_index: int in range(_players.size()):
		if _slot_item_ids[slot_index] < 0:
			_bind_slot(slot_index, int(packet["item_id"]))
			return slot_index
	var candidate_index := 0
	for slot_index: int in range(1, _players.size()):
		if _target_volumes_db[slot_index] < _target_volumes_db[candidate_index]:
			candidate_index = slot_index
	if float(packet.get("volume_db", -80.0)) <= _target_volumes_db[candidate_index]:
		return -1
	_release_slot(candidate_index)
	_bind_slot(candidate_index, int(packet["item_id"]))
	return candidate_index


func _bind_slot(slot_index: int, item_id: int) -> void:
	_slot_item_ids[slot_index] = item_id
	_slot_retiring[slot_index] = 0
	_slot_by_item_id[item_id] = slot_index


func _update_slot(slot_index: int, packet: Dictionary) -> void:
	_slot_retiring[slot_index] = 0
	_route_slot_to_shared_program(
		slot_index,
		int(packet.get("shared_program_group_id", -1))
	)
	_target_positions[slot_index] = packet.get("apparent_position", Vector3.ZERO)
	_target_volumes_db[slot_index] = float(packet.get("volume_db", -80.0))
	_effect_target_packets[slot_index] = packet

	var revision := int(packet["revision"])
	var song_path := str(packet["song_path"])
	if (
		_slot_revisions[slot_index] == revision
		and _slot_song_paths[slot_index] == song_path
	):
		_latest_packets[slot_index] = packet
		_correct_drift_if_needed(slot_index)
		if (
			not _players[slot_index].playing
			and not _is_at_stream_end(packet)
		):
			_queue_packet(slot_index, packet, true)
		return

	if (
		_slot_pending_revisions[slot_index] != revision
		or str(_pending_packets[slot_index].get("song_path", "")) != song_path
	):
		_queue_packet(slot_index, packet)
	else:
		_pending_packets[slot_index] = packet
		var desired_start_usec := (
			Time.get_ticks_usec()
			+ int(float(packet.get("start_delay_seconds", 0.0)) * 1000000.0)
		)
		_slot_pending_start_usec[slot_index] = mini(
			_slot_pending_start_usec[slot_index],
			desired_start_usec
		)
	if (
		_slot_pending_start_usec[slot_index]
		<= Time.get_ticks_usec() + int(START_IMMEDIATELY_SECONDS * 1000000.0)
	):
		_activate_pending(slot_index)


func _queue_packet(
	slot_index: int,
	packet: Dictionary,
	force_immediate := false
) -> void:
	var stream := load(str(packet["song_path"])) as AudioStream
	if stream == null:
		_release_slot(slot_index)
		return
	_pending_packets[slot_index] = packet
	_pending_streams[slot_index] = stream
	_slot_pending_revisions[slot_index] = int(packet["revision"])
	var delay_seconds := (
		0.0
		if force_immediate
		else float(packet.get("start_delay_seconds", 0.0))
	)
	_slot_pending_start_usec[slot_index] = (
		Time.get_ticks_usec() + int(delay_seconds * 1000000.0)
	)


func _activate_pending(slot_index: int) -> void:
	var stream := _pending_streams[slot_index]
	var packet := _pending_packets[slot_index]
	if stream == null or packet.is_empty():
		return
	var player := _players[slot_index]
	var static_player := _static_players[slot_index]
	var song_path := str(packet["song_path"])
	var program_changed := _slot_song_paths[slot_index] != song_path
	var was_playing := player.playing
	var previous_volume_db := player.volume_db
	_effect_racks[slot_index].prepare_for_input()
	player.stop()
	player.stream = stream
	player.global_position = _target_positions[slot_index]
	player.volume_db = (
		previous_volume_db
		if was_playing
		else _target_volumes_db[slot_index] - NEW_VOICE_FADE_IN_DB
	)
	static_player.global_position = _target_positions[slot_index]
	var static_enabled := _receiver_static_enabled(packet)
	static_player.volume_db = (
		minf(
			static_player.volume_db if static_player.playing else 0.0,
			_target_volumes_db[slot_index]
			+ float(packet.get("static_mix_db", -60.0))
			- float(packet.get("program_normalization_gain_db", 0.0))
			- float(packet.get("program_reference_gain_db", 0.0))
			- NEW_VOICE_FADE_IN_DB
		)
		if static_enabled
		else AcousticPathModifier.MIN_VOLUME_DB
	)
	_update_early_reflection_pans(packet)
	_effect_racks[slot_index].apply_acoustic(
		packet,
		_spectral_room_bloom_levels[slot_index],
		_slot_shared_program_group_ids[slot_index] >= 0
	)
	_effect_racks[slot_index].apply_radio_distortion(packet)
	var offset := _clamped_playback_offset(
		packet,
		stream.get_length()
	)
	player.play(offset)
	_activate_shared_program_late_field(
		(
			_slot_shared_program_group_ids[slot_index]
			if bool(packet.get("shared_program_late_field_enabled", true))
			else -1
		),
		stream,
		packet,
		offset
	)
	if static_enabled and not static_player.playing:
		var static_offset := fmod(
			absf(float(_slot_item_ids[slot_index])) * 0.137,
			maxf(_static_stream.get_length(), 0.01)
		)
		static_player.play(static_offset)
	elif not static_enabled and static_player.playing:
		static_player.stop()
	_slot_revisions[slot_index] = _slot_pending_revisions[slot_index]
	_slot_song_paths[slot_index] = song_path
	if program_changed:
		# A loud previous track must not suppress the first beats of a quieter replacement.
		_visual_program_baselines[slot_index] = 0.0
		_visual_previous_inputs[slot_index] = 0.0
	_latest_packets[slot_index] = packet
	_slot_pending_revisions[slot_index] = -1
	_slot_pending_start_usec[slot_index] = 0
	_pending_packets[slot_index] = {}
	_pending_streams[slot_index] = null
	_slot_last_drift_check_usec[slot_index] = Time.get_ticks_usec()


static func _receiver_static_enabled(packet: Dictionary) -> bool:
	return bool(packet.get(
		"receiver_static_enabled",
		float(packet.get("static_mix_db", -60.0)) > -60.0
	))


func _update_early_reflection_pans(packet: Dictionary) -> void:
	var raw_taps: Variant = packet.get("early_reflections", null)
	if not raw_taps is Array:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var listener_position := camera.global_position
	var listener_right := camera.global_basis.x.normalized()
	for raw_tap: Variant in raw_taps as Array:
		if not raw_tap is Dictionary:
			continue
		var tap := raw_tap as Dictionary
		var apparent_position: Vector3 = tap.get(
			"apparent_position",
			listener_position
		)
		var arrival_offset := apparent_position - listener_position
		if arrival_offset.length_squared() <= 0.000001:
			tap["pan"] = 0.0
		else:
			tap["pan"] = clampf(
				arrival_offset.normalized().dot(listener_right),
				-1.0,
				1.0
			)


func _activate_shared_program_late_field(
	group_id: int,
	stream: AudioStream,
	packet: Dictionary,
	playback_offset: float
) -> void:
	if group_id < 0 or stream == null:
		return
	var group_slot := _shared_program_group_slot(group_id)
	if group_slot < 0:
		return
	var revision := int(packet.get("revision", -1))
	var song_path := str(packet.get("song_path", ""))
	var player := _shared_program_players[group_slot]
	if (
		_shared_program_revisions[group_slot] == revision
		and _shared_program_song_paths[group_slot] == song_path
		and player.playing
	):
		return
	player.stop()
	_shared_program_racks[group_slot].prepare_for_input()
	player.stream = stream
	player.volume_db = (
		_shared_program_target_volumes_db[group_slot] - NEW_VOICE_FADE_IN_DB
	)
	var target := _shared_program_target_packets[group_slot]
	if not target.is_empty():
		_shared_program_racks[group_slot].apply_acoustic(
			target,
			0.0,
			false,
			true
		)
	player.play(playback_offset)
	_shared_program_revisions[group_slot] = revision
	_shared_program_song_paths[group_slot] = song_path


func _correct_drift_if_needed(slot_index: int) -> void:
	var shared_group_id := _slot_shared_program_group_ids[slot_index]
	if shared_group_id >= 0:
		_correct_shared_program_drift_if_needed(
			shared_group_id,
			slot_index
		)
		return
	var now_usec := Time.get_ticks_usec()
	if (
		now_usec - _slot_last_drift_check_usec[slot_index]
		< DRIFT_CHECK_INTERVAL_USEC
	):
		return
	_slot_last_drift_check_usec[slot_index] = now_usec
	var player := _players[slot_index]
	if not player.playing:
		return
	var desired := float(
		_latest_packets[slot_index].get("playback_offset_seconds", 0.0)
	)
	if player.stream != null:
		desired = _clamped_playback_offset(
			_latest_packets[slot_index],
			player.stream.get_length()
		)
	# Snapshot jitter must not repeatedly seek a healthy continuous stream: hard seeks are audible
	# discontinuities. Normal clocks are close enough to free-run; only recover a real desync.
	if absf(player.get_playback_position() - desired) > DRIFT_HARD_RESYNC_SECONDS:
		player.seek(desired)


func _correct_shared_program_drift_if_needed(
	group_id: int,
	requesting_slot: int
) -> void:
	var leader_slot := -1
	for candidate_slot: int in range(_slot_item_ids.size()):
		if (
			_slot_item_ids[candidate_slot] >= 0
			and _slot_shared_program_group_ids[candidate_slot] == group_id
		):
			leader_slot = candidate_slot
			break
	if leader_slot < 0 or requesting_slot != leader_slot:
		return
	var now_usec := Time.get_ticks_usec()
	if (
		now_usec - _slot_last_drift_check_usec[leader_slot]
		< DRIFT_CHECK_INTERVAL_USEC
	):
		return
	var leader := _players[leader_slot]
	if not leader.playing:
		return
	var desired := float(
		_latest_packets[leader_slot].get("playback_offset_seconds", 0.0)
	)
	if leader.stream != null:
		desired = _clamped_playback_offset(
			_latest_packets[leader_slot],
			leader.stream.get_length()
		)
	var leader_position := leader.get_playback_position()
	var server_desynced := (
		absf(leader_position - desired) > DRIFT_HARD_RESYNC_SECONDS
	)
	for candidate_slot: int in range(_slot_item_ids.size()):
		if (
			_slot_item_ids[candidate_slot] < 0
			or _slot_shared_program_group_ids[candidate_slot] != group_id
		):
			continue
		_slot_last_drift_check_usec[candidate_slot] = now_usec
		var candidate := _players[candidate_slot]
		if not candidate.playing:
			continue
		# Never let one cabinet cross the resync threshold alone. A genuine clock recovery seeks the
		# complete coherent program in one render frame; otherwise every decoder remains free-running.
		if (
			server_desynced
			or absf(candidate.get_playback_position() - leader_position)
			> DRIFT_HARD_RESYNC_SECONDS
		):
			candidate.seek(desired if server_desynced else leader_position)
	var group_slot := _shared_program_group_slot(group_id)
	if group_slot < 0:
		return
	var late_player := _shared_program_players[group_slot]
	if (
		late_player.playing
		and (
			server_desynced
			or absf(late_player.get_playback_position() - leader_position)
			> DRIFT_HARD_RESYNC_SECONDS
		)
	):
		late_player.seek(desired if server_desynced else leader_position)


static func _is_at_stream_end(packet: Dictionary) -> bool:
	var stream_length := float(packet.get("stream_length_seconds", 0.0))
	return (
		stream_length > 0.05
		and float(packet.get("playback_offset_seconds", 0.0))
		>= stream_length - 0.05
	)


static func _clamped_playback_offset(
	packet: Dictionary,
	stream_length: float
) -> float:
	var offset := maxf(
		float(packet.get("playback_offset_seconds", 0.0)),
		0.0
	)
	if stream_length <= 0.01:
		return offset
	return minf(offset, maxf(stream_length - 0.01, 0.0))


func _release_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _players.size():
		return
	var item_id := _slot_item_ids[slot_index]
	if item_id >= 0:
		_slot_by_item_id.erase(item_id)
	var player := _players[slot_index]
	_route_slot_to_shared_program(slot_index, -1)
	player.stop()
	player.stream = null
	_static_players[slot_index].stop()
	_slot_item_ids[slot_index] = -1
	_slot_revisions[slot_index] = -1
	_slot_pending_revisions[slot_index] = -1
	_slot_seen_generations[slot_index] = 0
	_slot_pending_start_usec[slot_index] = 0
	_slot_last_drift_check_usec[slot_index] = 0
	_slot_retiring[slot_index] = 0
	_slot_shared_program_group_ids[slot_index] = -1
	_slot_song_paths[slot_index] = ""
	_target_volumes_db[slot_index] = -80.0
	_visual_levels[slot_index] = 0.0
	_visual_program_baselines[slot_index] = 0.0
	_visual_previous_inputs[slot_index] = 0.0
	_spectral_room_bloom_levels[slot_index] = 0.0
	_target_positions[slot_index] = Vector3.ZERO
	_latest_packets[slot_index] = {}
	_effect_target_packets[slot_index] = {}
	_pending_packets[slot_index] = {}
	_pending_streams[slot_index] = null


func _route_slot_to_shared_program(slot_index: int, group_id: int) -> void:
	if slot_index < 0 or slot_index >= _effect_racks.size():
		return
	var group_slot := (
		_shared_program_group_slot(group_id)
		if group_id >= 0
		else -1
	)
	var resolved_group_id := group_id if group_slot >= 0 else -1
	_slot_shared_program_group_ids[slot_index] = resolved_group_id
	var rack := _effect_racks[slot_index]
	# Godot buses have one send rather than an auxiliary send. Keep every spatial direct voice on
	# the final mix and render one additional listener-space wet voice on the group bus; inserting
	# reverb on the summed direct bus would weaken a clear exterior cabinet merely because another
	# cabinet happens to excite the room.
	if AudioServer.get_bus_send(rack.bus_index) != CONTINUOUS_MIX_BUS:
		AudioServer.set_bus_send(rack.bus_index, CONTINUOUS_MIX_BUS)


func _begin_slot_fade_out(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _players.size():
		return
	if _slot_item_ids[slot_index] < 0:
		return
	_slot_retiring[slot_index] = 1
	_target_volumes_db[slot_index] = AcousticPathModifier.MIN_VOLUME_DB
