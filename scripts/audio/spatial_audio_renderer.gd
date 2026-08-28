class_name SpatialAudioRenderer
extends Node

signal foreground_transient_started(strength: float, received_volume_db: float)

const LISTENER_ACTIVITY := preload(
	"res://scripts/audio/listener_acoustic_activity.gd"
)
const LOCAL_AUDIO_PREDICTION := preload(
	"res://scripts/audio/local_audio_prediction.gd"
)
const DEFAULT_VOICE_COUNT := 24
const MAX_PENDING_EVENTS := 64
const BUS_PREFIX := "ScavangeSpatialVoice"
const PRESSURE_OUTPUT_BUS := &"ScavangePressureOutput"
const MAX_VOICE_RESERVATION_SECONDS := 12.0
const LISTENER_ACOUSTIC_RELEASE_SPEED := 5.0
const LOCAL_PREDICTION_LIFETIME_USEC := 4000000
# Listen-server authority advances before its local presentation proxy in the same frame. Give that
# proxy enough time to cross the shared gait phase before committing an authority-first owner cue.
# This is not network buffering: unkeyed remote/world events still render immediately.
const AUTHORITY_FIRST_PREDICTION_GRACE_USEC := 50000

## Client-only voice pool. Every voice owns a persistent EQ/filter bus, so applying a server path
## result requires no bus or DSP allocation during playback.

var _registrations: Dictionary[StringName, Dictionary] = {}
var _pending_events: Array[Dictionary] = []
var _players: Array[AudioStreamPlayer3D] = []
var _effect_racks: Array[SpatialAudioEffectRack] = []
var _voice_priorities := PackedFloat32Array()
var _voice_started_usec := PackedInt64Array()
var _voice_reserved_until_usec := PackedInt64Array()
var _rng := RandomNumberGenerator.new()
var _listener_acoustic_intensity := 0.0
var _predicted_events_by_key: Dictionary[int, int] = {}
var _authoritative_events_by_prediction_key: Dictionary[int, int] = {}
var _pending_authoritative_predictions: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	_rng.randomize()
	_ensure_pressure_output_bus()
	# Build the fixed voice/DSP pool while the client world is loading. Allocating 24 players and
	# their effect racks on the first footstep or trigger pull turns correct local prediction into a
	# visible input-frame hitch and an audible late start.
	_ensure_voice_pool()
	set_process(true)


func register_sound(
	sound_id: StringName,
	streams: Array[AudioStream],
	settings: Dictionary = {},
	owner_token := 0
) -> bool:
	if sound_id.is_empty():
		return false
	var valid_streams: Array[AudioStream] = []
	for stream: AudioStream in streams:
		if stream != null:
			valid_streams.append(stream)
	if valid_streams.is_empty():
		return false
	var pressure_streams: Array[AudioStream] = []
	var raw_pressure_streams: Variant = settings.get("pressure_streams", [])
	if raw_pressure_streams is Array:
		for raw_stream: Variant in raw_pressure_streams:
			var pressure_stream := raw_stream as AudioStream
			if pressure_stream != null:
				pressure_streams.append(pressure_stream)
	_registrations[sound_id] = {
		"streams": valid_streams,
		"pressure_streams": pressure_streams,
		"base_volume_db": clampf(
			SafeVariant.finite_float_or(
				settings.get("base_volume_db"),
				0.0
			),
			-60.0,
			18.0
		),
		"pitch_min": clampf(
			SafeVariant.finite_float_or(settings.get("pitch_min"), 0.97),
			0.25,
			4.0
		),
		"pitch_max": clampf(
			SafeVariant.finite_float_or(settings.get("pitch_max"), 1.03),
			0.25,
			4.0
		),
		"start_offset_seconds": clampf(
			SafeVariant.finite_float_or(
				settings.get("start_offset_seconds"),
				0.0
			),
			0.0,
			5.0
		),
		"foreground_transient_strength": clampf(
			SafeVariant.finite_float_or(
				settings.get("foreground_transient_strength"),
				0.0
			),
			0.0,
			1.0
		),
		# Local stream calibration only. The server packet continues to own reflected level and
		# room shape; this compensates differently mastered purpose-authored pressure recordings.
		"pressure_layer_gain_db": clampf(
			SafeVariant.finite_float_or(
				settings.get("pressure_layer_gain_db"),
				0.0
			),
			-18.0,
			18.0
		),
		"last_index": -1,
		"last_pressure_index": -1,
		"owner_token": owner_token,
	}
	var entry: Dictionary = _registrations[sound_id]
	if float(entry["pitch_min"]) > float(entry["pitch_max"]):
		var old_min: float = entry["pitch_min"]
		entry["pitch_min"] = entry["pitch_max"]
		entry["pitch_max"] = old_min
		_registrations[sound_id] = entry
	return true


func unregister_sound(sound_id: StringName, owner_token := 0) -> void:
	var entry: Dictionary = _registrations.get(sound_id, {})
	if entry.is_empty():
		return
	if owner_token != 0 and int(entry.get("owner_token", 0)) != owner_token:
		return
	_registrations.erase(sound_id)


func submit(packet: Dictionary) -> bool:
	var prediction_key := LOCAL_AUDIO_PREDICTION.sanitize_key(
		packet.get("local_prediction_key")
	)
	if prediction_key > 0 and _predicted_events_by_key.has(prediction_key):
		# The owner already rendered this cosmetic event on the input/visual frame. The server
		# packet is still the authoritative acceptance, but replaying it would create a flam whose
		# spacing equals the round trip. Other clients never receive this key and use the normal path.
		_predicted_events_by_key.erase(prediction_key)
		return true
	if prediction_key > 0:
		# Authority can beat the local gait presentation on a listen server because the Server autoload
		# receives the physics callback first. Keep the confirmation for a small bounded grace window;
		# submit_predicted() will consume it later in this same rendered frame. If prediction never
		# arrives, _process() renders the untouched authoritative packet.
		_pending_authoritative_predictions[prediction_key] = {
			"packet": packet,
			"received_usec": Time.get_ticks_usec(),
		}
		return true
	var accepted := _submit_unreconciled(packet)
	return accepted


func submit_predicted(packet_value: Dictionary) -> bool:
	var packet := AcousticEventPacket.sanitize(packet_value)
	var prediction_key := LOCAL_AUDIO_PREDICTION.sanitize_key(
		packet.get("local_prediction_key")
	)
	if prediction_key == 0 or _predicted_events_by_key.has(prediction_key):
		return false
	if _pending_authoritative_predictions.has(prediction_key):
		# The server already accepted this action, but had not committed its acoustically delayed copy.
		# Render the input-frame packet now and remember the completed key so neither ordering can flam.
		_pending_authoritative_predictions.erase(prediction_key)
		var accepted := _submit_unreconciled(packet)
		if accepted:
			_authoritative_events_by_prediction_key[prediction_key] = (
				Time.get_ticks_usec()
			)
		return accepted
	if _authoritative_events_by_prediction_key.has(prediction_key):
		_authoritative_events_by_prediction_key.erase(prediction_key)
		return false
	var accepted := _submit_unreconciled(packet)
	if accepted:
		_predicted_events_by_key[prediction_key] = Time.get_ticks_usec()
	return accepted


func reject_prediction(prediction_key_value: int) -> void:
	var prediction_key := LOCAL_AUDIO_PREDICTION.sanitize_key(prediction_key_value)
	if prediction_key == 0:
		return
	_predicted_events_by_key.erase(prediction_key)
	_authoritative_events_by_prediction_key.erase(prediction_key)
	_pending_authoritative_predictions.erase(prediction_key)
	for event_index: int in range(_pending_events.size() - 1, -1, -1):
		if int(_pending_events[event_index].get("local_prediction_key", 0)) == prediction_key:
			_pending_events.remove_at(event_index)


func has_prediction(prediction_key: int) -> bool:
	return _predicted_events_by_key.has(prediction_key)


func _submit_unreconciled(packet: Dictionary) -> bool:
	var sound_id: StringName = packet.get("sound_id", &"")
	if not _registrations.has(sound_id):
		return false
	var pressure_arrivals: Array = packet.get("pressure_arrivals", [])
	if pressure_arrivals.is_empty():
		return _submit_single(packet)
	var entry: Dictionary = _registrations.get(sound_id, {})
	var main_streams: Array = entry.get("streams", [])
	var main_stream_index := _choose_stream_index(
		main_streams.size(),
		int(entry.get("last_index", -1))
	)
	if main_stream_index < 0:
		return false
	entry["last_index"] = main_stream_index
	_registrations[sound_id] = entry

	# Pick once per semantic event so authored dry/body pairs keep the same take and pitch.
	var primary_packet := packet.duplicate(false)
	primary_packet["stream_index_hint"] = main_stream_index
	primary_packet["pitch_scale_hint"] = _rng.randf_range(
		float(entry.get("pitch_min", 0.97)),
		float(entry.get("pitch_max", 1.03))
	)
	var accepted := _submit_single(primary_packet)
	var pressure_streams: Array = entry.get("pressure_streams", [])
	# Replaying an arbitrary full source recording as a delayed pressure impulse produces a
	# flam/air-whoosh artifact. Every sound still receives propagation and room DSP, but an extra
	# wavefront voice is emitted only when a short, purpose-authored pressure layer exists.
	if pressure_streams.is_empty():
		return accepted
	var pressure_stream_index := (
		main_stream_index
		if pressure_streams.size() == main_streams.size()
		else _choose_stream_index(
			pressure_streams.size(),
			int(entry.get("last_pressure_index", -1))
		)
	)
	if pressure_stream_index < 0:
		return accepted
	entry["last_pressure_index"] = pressure_stream_index
	_registrations[sound_id] = entry
	for arrival_value: Variant in pressure_arrivals:
		if not arrival_value is Dictionary:
			continue
		var pressure_packet := _pressure_packet(
			packet,
			arrival_value as Dictionary
		)
		pressure_packet["pitch_scale_hint"] = primary_packet["pitch_scale_hint"]
		# Matching variation counts are authored pairs. All physical routes replay the same
		# pressure take instead of rolling a different transient at each doorway.
		pressure_packet["stream_index_hint"] = pressure_stream_index
		accepted = _submit_single(pressure_packet) or accepted
	return accepted


func _submit_single(packet: Dictionary) -> bool:
	if _pending_events.size() >= MAX_PENDING_EVENTS:
		_drop_least_important_pending(float(packet.get("priority", 0.5)))
		if _pending_events.size() >= MAX_PENDING_EVENTS:
			return false
	var delay_seconds := float(packet.get("travel_delay_seconds", 0.0))
	if delay_seconds <= 0.005:
		return _play_packet(packet)
	var pending := packet.duplicate(false)
	pending["play_at_usec"] = (
		Time.get_ticks_usec() + int(delay_seconds * 1000000.0)
	)
	_pending_events.append(pending)
	return true


static func _pressure_packet(
	parent: Dictionary,
	arrival: Dictionary
) -> Dictionary:
	var reverb_scale := clampf(
		SafeVariant.finite_float_or(arrival.get("reverb_scale"), 1.0),
		0.0,
		1.0
	)
	var kind := SafeVariant.integral_int_or(arrival.get("kind"), 0)
	return {
		"sound_id": parent.get("sound_id", &""),
		"source_position": parent.get("source_position", Vector3.ZERO),
		"apparent_position": arrival.get(
			"apparent_position",
			parent.get("apparent_position", Vector3.ZERO)
		),
		"direct_distance": parent.get("direct_distance", 0.0),
		"path_length": arrival.get("path_length", 0.0),
		"travel_delay_seconds": arrival.get("travel_delay_seconds", 0.0),
		"volume_db": clampf(
			SafeVariant.finite_float_or(arrival.get("volume_db"), -80.0),
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		),
		"band_gain": arrival.get("band_gain", Vector3.ONE),
		"lowpass_hz": arrival.get(
			"lowpass_hz",
			AcousticPathModifier.MAX_FILTER_HZ
		),
		"highpass_hz": arrival.get(
			"highpass_hz",
			AcousticPathModifier.MIN_FILTER_HZ
		),
		"resonance": arrival.get("resonance", 0.0),
		"reverb_send": clampf(
			SafeVariant.finite_float_or(
				parent.get("pressure_reverb_send"),
				0.0
			) * reverb_scale,
			0.0,
			1.0
		),
		"reverb_room_size": parent.get("pressure_reverb_room_size", 0.02),
		"reverb_damping": parent.get("pressure_reverb_damping", 0.05),
		"reverb_spread": parent.get("pressure_reverb_spread", 1.0),
		"reverb_predelay_msec": parent.get(
			"pressure_reverb_predelay_msec",
			3.0
		),
		"reverb_predelay_feedback": parent.get(
			"pressure_reverb_predelay_feedback",
			0.0
		),
		"reverb_hipass": parent.get("pressure_reverb_hipass", 0.0),
		"reverb_decay_seconds": parent.get(
			"pressure_decay_seconds",
			AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
		),
		"environment_enclosure": parent.get("pressure_enclosure", 0.0),
		"priority": clampf(
			SafeVariant.finite_float_or(parent.get("priority"), 0.5)
			* (0.88 if kind == 0 else 0.70),
			0.0,
			1.0
		),
		"pressure_layer": true,
		"pressure_uses_source_stream": false,
		"local_prediction_key": parent.get("local_prediction_key", 0),
	}


func reset_session(clear_registrations := false) -> void:
	_pending_events.clear()
	_predicted_events_by_key.clear()
	_authoritative_events_by_prediction_key.clear()
	_pending_authoritative_predictions.clear()
	for player: AudioStreamPlayer3D in _players:
		player.stop()
	for rack: SpatialAudioEffectRack in _effect_racks:
		rack.reset_state()
	_voice_priorities.fill(0.0)
	_voice_started_usec.fill(0)
	_voice_reserved_until_usec.fill(0)
	_listener_acoustic_intensity = 0.0
	if clear_registrations:
		_registrations.clear()


func _process(delta: float) -> void:
	_listener_acoustic_intensity = LISTENER_ACTIVITY.follow(
		_listener_acoustic_intensity,
		0.0,
		delta,
		LISTENER_ACOUSTIC_RELEASE_SPEED,
		LISTENER_ACOUSTIC_RELEASE_SPEED
	)
	if not _pending_events.is_empty():
		var now_usec := Time.get_ticks_usec()
		for event_index: int in range(_pending_events.size() - 1, -1, -1):
			var packet: Dictionary = _pending_events[event_index]
			if int(packet.get("play_at_usec", 0)) > now_usec:
				continue
			_pending_events.remove_at(event_index)
			_play_packet(packet)
	if not _pending_authoritative_predictions.is_empty():
		var authority_now_usec := Time.get_ticks_usec()
		for prediction_key: int in _pending_authoritative_predictions.keys():
			var pending: Dictionary = _pending_authoritative_predictions[prediction_key]
			if authority_now_usec - int(pending.get("received_usec", 0)) < (
				AUTHORITY_FIRST_PREDICTION_GRACE_USEC
			):
				continue
			_pending_authoritative_predictions.erase(prediction_key)
			var packet: Dictionary = pending.get("packet", {})
			if _submit_unreconciled(packet):
				_authoritative_events_by_prediction_key[prediction_key] = (
					authority_now_usec
				)
	if not _predicted_events_by_key.is_empty():
		var prediction_cutoff := Time.get_ticks_usec() - LOCAL_PREDICTION_LIFETIME_USEC
		for prediction_key: int in _predicted_events_by_key.keys():
			if _predicted_events_by_key[prediction_key] < prediction_cutoff:
				_predicted_events_by_key.erase(prediction_key)
	if not _authoritative_events_by_prediction_key.is_empty():
		var authoritative_cutoff := (
			Time.get_ticks_usec() - LOCAL_PREDICTION_LIFETIME_USEC
		)
		for prediction_key: int in _authoritative_events_by_prediction_key.keys():
			if (
				_authoritative_events_by_prediction_key[prediction_key]
				< authoritative_cutoff
			):
				_authoritative_events_by_prediction_key.erase(prediction_key)
	for voice_index: int in range(_effect_racks.size()):
		_effect_racks[voice_index].update_tail_floor(
			_players[voice_index].playing,
			delta
		)


func _play_packet(packet: Dictionary) -> bool:
	var sound_id: StringName = packet.get("sound_id", &"")
	var entry: Dictionary = _registrations.get(sound_id, {})
	if entry.is_empty():
		return false
	_ensure_voice_pool()
	var priority := float(packet.get("priority", 0.5))
	var voice_index := _select_voice(priority)
	if voice_index < 0:
		return false
	var pressure_layer := bool(packet.get("pressure_layer", false))
	var pressure_streams: Array = entry.get("pressure_streams", [])
	var uses_source_stream := pressure_layer and pressure_streams.is_empty()
	var streams: Array = (
		entry.get("streams", [])
		if not pressure_layer or uses_source_stream
		else pressure_streams
	)
	var previous_index_key := (
		"last_pressure_index"
		if pressure_layer and not uses_source_stream
		else "last_index"
	)
	var stream_index := SafeVariant.integral_int_or(
		packet.get("stream_index_hint"),
		-1
	)
	if stream_index < 0 or stream_index >= streams.size():
		stream_index = _choose_stream_index(
			streams.size(),
			int(entry.get(previous_index_key, -1))
		)
		if stream_index >= 0:
			entry[previous_index_key] = stream_index
			_registrations[sound_id] = entry
	if stream_index < 0:
		return false

	_configure_voice_effects(voice_index, packet)
	var player := _players[voice_index]
	player.stop()
	AudioServer.set_bus_send(
		_effect_racks[voice_index].bus_index,
		PRESSURE_OUTPUT_BUS
		if pressure_layer
		else &"Master"
	)
	player.stream = streams[stream_index] as AudioStream
	player.global_position = packet.get("apparent_position", Vector3.ZERO)
	player.volume_db = clampf(
		float(packet.get("volume_db", 0.0))
		+ float(entry.get("base_volume_db", 0.0))
		+ (
			float(entry.get("pressure_layer_gain_db", 0.0))
			if pressure_layer
			else 0.0
		),
		-80.0,
		18.0
	)
	player.pitch_scale = clampf(
		SafeVariant.finite_float_or(
			packet.get("pitch_scale_hint"),
			_rng.randf_range(
				float(entry.get("pitch_min", 0.97)),
				float(entry.get("pitch_max", 1.03))
			)
		),
		0.25,
		4.0
	)
	var start_offset_seconds := float(
		entry.get("start_offset_seconds", 0.0)
	)
	player.play(start_offset_seconds)
	if not pressure_layer:
		_listener_acoustic_intensity = LISTENER_ACTIVITY.combine_energy(
			_listener_acoustic_intensity,
			LISTENER_ACTIVITY.from_received_volume_db(player.volume_db)
		)
	var transient_strength := float(
		entry.get("foreground_transient_strength", 0.0)
	)
	if not pressure_layer and transient_strength > 0.0001:
		foreground_transient_started.emit(
			transient_strength,
			player.volume_db
		)
	var now_usec := Time.get_ticks_usec()
	_voice_priorities[voice_index] = priority
	_voice_started_usec[voice_index] = now_usec
	_voice_reserved_until_usec[voice_index] = (
		now_usec + int(
			_voice_reservation_seconds(
				player,
				packet,
				start_offset_seconds
			) * 1000000.0
		)
	)
	return true


func get_listener_acoustic_intensity() -> float:
	return _listener_acoustic_intensity


func _ensure_voice_pool() -> void:
	if not _players.is_empty():
		return
	_voice_priorities.resize(DEFAULT_VOICE_COUNT)
	_voice_priorities.fill(0.0)
	_voice_started_usec.resize(DEFAULT_VOICE_COUNT)
	_voice_started_usec.fill(0)
	_voice_reserved_until_usec.resize(DEFAULT_VOICE_COUNT)
	_voice_reserved_until_usec.fill(0)
	for voice_index: int in range(DEFAULT_VOICE_COUNT):
		var bus_name := "%s%02d" % [BUS_PREFIX, voice_index]
		var rack := SpatialAudioEffectRack.attach(StringName(bus_name))
		_effect_racks.append(rack)
		var player := AudioStreamPlayer3D.new()
		player.name = "SpatialVoice%02d" % voice_index
		player.bus = StringName(bus_name)
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		player.max_polyphony = 1
		add_child(player)
		_players.append(player)


func _ensure_pressure_output_bus() -> void:
	var bus_index := AudioServer.get_bus_index(PRESSURE_OUTPUT_BUS)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, PRESSURE_OUTPUT_BUS)
	AudioServer.set_bus_send(bus_index, &"Master")
	var valid_layout := (
		AudioServer.get_bus_effect_count(bus_index) == 1
		and AudioServer.get_bus_effect(bus_index, 0) is AudioEffectLimiter
	)
	if valid_layout:
		return
	for effect_index: int in range(
		AudioServer.get_bus_effect_count(bus_index) - 1,
		-1,
		-1
	):
		AudioServer.remove_bus_effect(bus_index, effect_index)
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -0.8
	limiter.threshold_db = -4.0
	limiter.soft_clip_db = 2.0
	limiter.soft_clip_ratio = 8.0
	AudioServer.add_bus_effect(bus_index, limiter)


func _configure_voice_effects(voice_index: int, packet: Dictionary) -> void:
	_effect_racks[voice_index].prepare_for_input()
	_update_early_reflection_pans(packet)
	_effect_racks[voice_index].apply_acoustic(packet)


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
		tap["pan"] = (
			clampf(arrival_offset.normalized().dot(listener_right), -1.0, 1.0)
			if arrival_offset.length_squared() > 0.000001
			else 0.0
		)


func _select_voice(new_priority: float) -> int:
	var now_usec := Time.get_ticks_usec()
	for voice_index: int in range(_players.size()):
		if (
			not _players[voice_index].playing
			and _voice_reserved_until_usec[voice_index] <= now_usec
		):
			return voice_index
	var candidate_index := 0
	for voice_index: int in range(1, _players.size()):
		if (
			_voice_priorities[voice_index] < _voice_priorities[candidate_index]
			or (
				is_equal_approx(
					_voice_priorities[voice_index],
					_voice_priorities[candidate_index]
				)
				and _voice_started_usec[voice_index]
				< _voice_started_usec[candidate_index]
			)
		):
			candidate_index = voice_index
	if new_priority < _voice_priorities[candidate_index]:
		return -1
	return candidate_index


static func _voice_reservation_seconds(
	player: AudioStreamPlayer3D,
	packet: Dictionary,
	start_offset_seconds := 0.0
) -> float:
	var stream_seconds := 0.0
	if player != null and player.stream != null:
		stream_seconds = maxf(
			(
				player.stream.get_length()
				- maxf(start_offset_seconds, 0.0)
			) / maxf(player.pitch_scale, 0.25),
			0.0
		)
	var reverb_send := clampf(
		SafeVariant.finite_float_or(packet.get("reverb_send"), 0.0),
		0.0,
		1.0
	)
	var decay_seconds := clampf(
		SafeVariant.finite_float_or(packet.get("reverb_decay_seconds"), 0.0),
		0.0,
		AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
	)
	# A very quiet wet signal does not need to occupy a voice for the full mathematical RT60.
	# Strong room responses retain their bus until the baked decay has elapsed.
	var audible_tail_seconds := decay_seconds * smoothstep(0.0, 0.35, reverb_send)
	return clampf(
		stream_seconds + audible_tail_seconds,
		0.0,
		MAX_VOICE_RESERVATION_SECONDS
	)


func _choose_stream_index(stream_count: int, previous_index: int) -> int:
	if stream_count <= 0:
		return -1
	if stream_count == 1:
		return 0
	var result := _rng.randi_range(0, stream_count - 2)
	if result >= previous_index:
		result += 1
	return result


func _drop_least_important_pending(new_priority: float) -> void:
	if _pending_events.is_empty():
		return
	var candidate_index := 0
	for event_index: int in range(1, _pending_events.size()):
		if float(_pending_events[event_index].get("priority", 0.5)) < float(
			_pending_events[candidate_index].get("priority", 0.5)
		):
			candidate_index = event_index
	if new_priority >= float(
		_pending_events[candidate_index].get("priority", 0.5)
	):
		_pending_events.remove_at(candidate_index)
