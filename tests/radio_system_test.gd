extends SceneTree

const LISTENER_ACTIVITY := preload(
	"res://scripts/audio/listener_acoustic_activity.gd"
)

const RADIO_PATH := "res://resources/items/radios/portable_radio.tres"
const MUSIC_FILE_NAME := "amerika.mp3"
const WAREHOUSE_CATALOG := preload("res://scripts/drones/dev_warehouse_catalog.gd")
const VOLUME_CONTROL := preload("res://scripts/audio/speaker_volume_control.gd")
const MUSIC_LOUDNESS := preload("res://scripts/audio/music_loudness_catalog.gd")
const MUSIC_VISUAL_ENVELOPES := preload(
	"res://scripts/audio/music_visual_envelope_catalog.gd"
)

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := load(RADIO_PATH) as RadioItemDefinition
	_expect(definition != null, "portable radio definition loads")
	if definition == null:
		_finish()
		return
	_test_speaker_volume_response()
	_test_definition_and_warehouse(definition)
	await _test_authoritative_playback(definition)
	_finish()


func _test_speaker_volume_response() -> void:
	var default_ratio := VOLUME_CONTROL.DEFAULT_CONTROL_VOLUME_RATIO
	var default_db := VOLUME_CONTROL.decibels_from_ratio(default_ratio)
	var maximum_db := VOLUME_CONTROL.decibels_from_ratio(1.0)
	var maximum_gain_multiplier := db_to_linear(
		maximum_db - VOLUME_CONTROL.LEGACY_MAX_CONTROL_VOLUME_DB
	)
	_expect(
		is_equal_approx(default_db, VOLUME_CONTROL.DEFAULT_CONTROL_VOLUME_DB)
		and absf(
			VOLUME_CONTROL.ratio_from_decibels(default_db) - default_ratio
		) < 0.0001,
		"speaker default loudness and slider position remain unchanged"
	)
	_expect(
		absf(maximum_gain_multiplier - 1.5) < 0.0001
		and is_equal_approx(maximum_db, VOLUME_CONTROL.MAX_CONTROL_VOLUME_DB),
		"shared speaker ceiling supplies exactly 50 percent more linear amplitude"
	)
	var hybrid_packet := AcousticEventPacket.sanitize({
		"sound_id": &"hybrid_contract_test",
		"source_position": Vector3.ZERO,
		"apparent_position": Vector3.ZERO,
		"early_reflections": [
			{"reflection_id": 11, "apparent_position": Vector3.LEFT, "extra_delay_seconds": 0.024, "gain": 0.4, "band_gain": Vector3(0.9, 0.8, 0.7)},
			{"reflection_id": 12, "apparent_position": Vector3.RIGHT, "extra_delay_seconds": 0.041, "gain": 0.3, "band_gain": Vector3(0.8, 0.7, 0.6)},
			{"reflection_id": 13, "apparent_position": Vector3.BACK, "extra_delay_seconds": 99.0, "gain": 99.0},
		],
	})
	var hybrid_taps: Array = hybrid_packet.get("early_reflections", [])
	_expect(
		hybrid_taps.size() == AcousticEventPacket.MAX_EARLY_REFLECTIONS,
		"the network contract caps hybrid reflection work at two validated taps"
	)
	var hybrid_rack := SpatialAudioEffectRack.attach(&"HybridReflectionContractTest")
	hybrid_rack.apply_acoustic(hybrid_packet)
	var first_delay := hybrid_rack.early_delay.tap1_delay_ms
	var normalized_power := (
		hybrid_rack.early_delay.dry * hybrid_rack.early_delay.dry
		+ pow(db_to_linear(hybrid_rack.early_delay.tap1_level_db), 2.0)
		+ pow(db_to_linear(hybrid_rack.early_delay.tap2_level_db), 2.0)
	)
	_expect(
		absf(first_delay - 24.0) < 0.01
		and absf(normalized_power - 1.0) < 0.002
		and not hybrid_rack.early_delay.feedback_active,
		"persistent early taps preserve total power and never feed back"
	)
	var retuned_packet := hybrid_packet.duplicate(true)
	(retuned_packet["early_reflections"][0] as Dictionary)["reflection_id"] = 99
	(retuned_packet["early_reflections"][0] as Dictionary)["extra_delay_seconds"] = 0.09
	hybrid_rack.approach_acoustic(retuned_packet, 0.5)
	_expect(
		is_equal_approx(hybrid_rack.early_delay.tap1_delay_ms, first_delay)
		and hybrid_rack.early_delay.tap1_level_db < linear_to_db(0.4),
		"a populated delay tap fades before its read head is retuned"
	)


func _test_definition_and_warehouse(definition: RadioItemDefinition) -> void:
	var songs := definition.discover_song_paths()
	_expect(
		songs.any(
			func(song_path: String) -> bool: return song_path.get_file() == MUSIC_FILE_NAME
		),
		"radio recursively discovers imported tracks from the music folder"
	)
	var loud_track := "res://assets/sounds/music/temp/amerika.mp3"
	var quiet_track := (
		"res://assets/sounds/music/not so legally downloaded music/Deutsch Swing/Regentropfen.mp3"
	)
	var quiet_outlier_track := (
		"res://assets/sounds/music/not so legally downloaded music/gothic/Gothic 3 Soundtrack - End Titles.mp3"
	)
	var quiet_outlier_envelope: PackedByteArray = (
		MUSIC_VISUAL_ENVELOPES.TRACK_ENVELOPES.get(
			quiet_outlier_track,
			PackedByteArray()
		)
	)
	var quiet_envelope_min := 255
	var quiet_envelope_max := 0
	for value: int in quiet_outlier_envelope:
		quiet_envelope_min = mini(quiet_envelope_min, value)
		quiet_envelope_max = maxi(quiet_envelope_max, value)
	var unresponsive_envelope_count := 0
	for song_path: String in songs:
		var envelope: PackedByteArray = (
			MUSIC_VISUAL_ENVELOPES.TRACK_ENVELOPES.get(
				song_path,
				PackedByteArray()
			)
		)
		var envelope_min := 255
		var envelope_max := 0
		for value: int in envelope:
			envelope_min = mini(envelope_min, value)
			envelope_max = maxi(envelope_max, value)
		if (
			envelope.size() < 20
			or envelope_max < 200
			or envelope_max - envelope_min < 96
		):
			unresponsive_envelope_count += 1
	_expect(
		songs.all(func(path: String) -> bool: return MUSIC_LOUDNESS.TRACK_MEASUREMENTS.has(path))
		and songs.all(func(path: String) -> bool: return MUSIC_VISUAL_ENVELOPES.has_envelope(path))
		and MUSIC_LOUDNESS.gain_db_for_path(loud_track) < -5.0
		and MUSIC_LOUDNESS.gain_db_for_path(quiet_track) > 1.0
		and absf(
			MUSIC_LOUDNESS.normalized_integrated_lufs(loud_track)
			- MUSIC_LOUDNESS.normalized_integrated_lufs(quiet_track)
		) < 0.5
		and absf(
			MUSIC_LOUDNESS.gain_db_for_path(loud_track)
			+ MUSIC_LOUDNESS.DEVICE_REFERENCE_GAIN_DB
		) < 1.0
		and absf(
			MUSIC_LOUDNESS.emitted_reference_lufs(loud_track)
			- MUSIC_LOUDNESS.emitted_reference_lufs(quiet_track)
		) < 0.5,
		"the baked EBU R128 catalog gives every discovered track one peak-safe reference loudness"
	)
	_expect(
		unresponsive_envelope_count == 0
		and quiet_outlier_envelope.size() > 1000
		and quiet_envelope_max >= 240
		and quiet_envelope_max - quiet_envelope_min >= 160,
		"every track has a source-level rhythmic envelope, including masters too quiet for reliable received-spectrum animation"
	)
	_expect(
		definition.speaker_local_position.z > 0.2
		and absf(definition.speaker_local_position.x + 0.17) < 0.01
		and absf(definition.speaker_local_position.y - 0.24) < 0.01,
		"sound origin sits just outside the visible speaker cone"
	)
	_expect(
		definition.source_modifier != null
		and definition.source_modifier.band_gain.z >= 0.9
		and definition.source_modifier.lowpass_hz >= 15000.0,
		"direct radio sound preserves high-frequency clarity"
	)
	_expect(
		definition.receiver_static_enabled
		and definition.static_mix_db <= -12.0
		and definition.static_mix_db >= -36.0,
		"portable radio authors a restrained receiver-static layer"
	)
	var visual := definition.instantiate_visual()
	_expect(
		visual is Node3D,
		"radio uses the ordinary item visual contract"
	)
	root.add_child(visual)
	var radio_visual := visual.get_node_or_null("PortableRadioVisual") as Node3D
	var speaker_cone := (
		radio_visual.get_node_or_null("SpeakerCone") as MeshInstance3D
		if radio_visual != null
		else null
	)
	var rest_scale := speaker_cone.scale if speaker_cone != null else Vector3.ZERO
	var rest_position := speaker_cone.position if speaker_cone != null else Vector3.ZERO
	if radio_visual != null:
		radio_visual.call("_apply_cone_level", 1.0)
	var expanded_scale := speaker_cone.scale if speaker_cone != null else Vector3.ZERO
	var expanded_position := speaker_cone.position if speaker_cone != null else Vector3.ZERO
	if radio_visual != null:
		radio_visual.call("_apply_cone_level", 0.0)
	_expect(
		speaker_cone != null
		and expanded_scale.x > rest_scale.x
		and expanded_scale.x < rest_scale.x * 1.06
		and expanded_position.z > rest_position.z
		and speaker_cone.scale.is_equal_approx(rest_scale),
		"the black speaker cone has a visible but restrained reversible music pulse"
	)
	visual.free()
	var warehouse_has_radio := false
	var warehouse_radio_is_upright := false
	for raw_slot: Variant in WAREHOUSE_CATALOG.build_layout().get("slots", []):
		var slot: Dictionary = raw_slot
		if str(slot.get("definition_path", "")) == RADIO_PATH:
			warehouse_has_radio = true
			warehouse_radio_is_upright = (
				(slot.get("rotation", Vector3.INF) as Vector3).is_zero_approx()
			)
			break
	_expect(warehouse_has_radio, "dev warehouse exposes a physical radio item")
	_expect(
		warehouse_radio_is_upright,
		"warehouse keeps the procedural radio speaker upright"
	)


func _test_authoritative_playback(definition: RadioItemDefinition) -> void:
	var server := root.get_node_or_null("Server")
	var client := root.get_node_or_null("Client")
	var game_state := root.get_node_or_null("GameState")
	_expect(
		server != null and client != null and game_state != null,
		"radio integration autoloads are available"
	)
	if server == null or client == null or game_state == null:
		return
	server.call("spawn_server_world")
	await process_frame
	await process_frame
	var radio: Node = server.call(
		"spawn_item",
		definition,
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 5.0))
	) as Node
	_expect(
		radio != null
		and str(radio.get_script().resource_path)
		== "res://scripts/server/server_radio.gd",
		"ordinary server item factory selects the specialized radio body"
	)
	if radio == null:
		return
	_expect(bool(radio.call("set_powered", true)), "server authority powers the radio on")
	var available_songs := definition.discover_song_paths()
	_expect(
		str(radio.get("current_song_path")) in available_songs
		and int(radio.get("playback_revision")) > 0,
		"server chooses a discovered song and starts an authoritative timeline"
	)

	var service := server.get("acoustic_service") as ServerAcousticService
	var state: Dictionary = radio.call(
		"build_listener_state",
		1,
		Vector3.ZERO,
		service
	)
	var packet := RadioStatePacket.sanitize(state)
	_expect(
		not packet.is_empty()
		and int(packet.get("item_id", -1)) == int(radio.get("item_id")),
		"listener receives a valid radio state through the acoustic boundary"
	)
	_expect(
		float(packet.get("travel_delay_seconds", 0.0)) > 0.0
		and float(packet.get("distortion_drive", 0.0)) > 0.0
		and bool(packet.get("receiver_static_enabled", false))
		and is_equal_approx(
			float(packet.get("static_mix_db", 0.0)),
			definition.static_mix_db
		)
		and is_equal_approx(
			float(packet.get("program_normalization_gain_db", INF)),
			MUSIC_LOUDNESS.gain_db_for_path(str(radio.get("current_song_path")))
		)
		and is_equal_approx(
			float(packet.get("program_reference_gain_db", INF)),
			MUSIC_LOUDNESS.DEVICE_REFERENCE_GAIN_DB
		),
		"radio packet carries propagation delay, distortion, static, balancing gain and calibrated speaker output"
	)
	var legacy_clean_state := state.duplicate(false)
	legacy_clean_state.erase("receiver_static_enabled")
	legacy_clean_state["static_mix_db"] = -60.0
	_expect(
		not bool(RadioStatePacket.sanitize(legacy_clean_state).get(
			"receiver_static_enabled",
			true
		)),
		"version-seven clean profiles remain static-free at the packet compatibility boundary"
	)
	var synchronized_boundary_state := state.duplicate(false)
	synchronized_boundary_state["shared_program_group_id"] = 9191
	synchronized_boundary_state["diffuse_field_gain_db"] = 12.5
	var synchronized_boundary_packet := RadioStatePacket.sanitize(
		synchronized_boundary_state
	)
	_expect(
		int(synchronized_boundary_packet.get("radio_version", -1))
		== RadioStatePacket.VERSION
		and is_equal_approx(
			float(synchronized_boundary_packet.get("diffuse_field_gain_db", -1.0)),
			12.5
		),
		"the strict continuous-audio boundary preserves bounded diffuse recovery for synchronized cabinet localization"
	)
	var speaker_position := definition.get_speaker_world_position(
		(radio as Node3D).global_transform
	)
	var clear_state: Dictionary = radio.call(
		"build_listener_state",
		2,
		speaker_position + Vector3(0.0, 0.0, 1.0),
		service
	)
	var clear_packet := RadioStatePacket.sanitize(clear_state)
	var clear_band_gain: Vector3 = clear_packet.get("band_gain", Vector3.ZERO)
	var clear_modifiers: PackedStringArray = clear_packet.get(
		"modifier_ids",
		PackedStringArray()
	)
	_expect(
		not clear_packet.is_empty()
		and clear_band_gain.z > 0.85
		and float(clear_packet.get("lowpass_hz", 0.0)) >= 15000.0,
		"listener directly in front receives a clear near-field packet"
	)
	_expect(
		clear_modifiers.has("portable_radio_speaker")
		and not clear_modifiers.has("steel_backboard"),
		"clear near-field route does not inherit a wall modifier"
	)
	_test_fieldlink_control_adapter(
		radio,
		definition,
		service,
		speaker_position
	)

	var unsafe_state := state.duplicate(false)
	unsafe_state["song_path"] = "res://project.godot"
	_expect(
		RadioStatePacket.sanitize(unsafe_state).is_empty(),
		"client rejects network-directed loads outside the music folder"
	)

	var renderer := RadioAudioRenderer.new()
	root.add_child(renderer)
	var immediate_render_state := state.duplicate(false)
	immediate_render_state["start_delay_seconds"] = 0.0
	renderer.submit_snapshot({int(radio.get("item_id")): immediate_render_state})
	await process_frame
	var debug := renderer.get_debug_state()
	var continuous_mix_bus_index := AudioServer.get_bus_index(
		RadioAudioRenderer.CONTINUOUS_MIX_BUS
	)
	var continuous_limiter := (
		AudioServer.get_bus_effect(continuous_mix_bus_index, 0)
		as AudioEffectHardLimiter
		if continuous_mix_bus_index >= 0
		and AudioServer.get_bus_effect_count(continuous_mix_bus_index) == 1
		else null
	)
	_expect(
		int(debug.get("voice_count", 0)) == RadioAudioRenderer.MAX_RADIO_VOICES
		and int(debug.get("static_voice_count", 0)) == RadioAudioRenderer.MAX_RADIO_VOICES
			and int(debug.get("active_count", 0)) == 1
			and int(debug.get("active_static_count", 0)) == 1
			and int(debug.get("shared_static_bytes", 0)) > 10000
			and int(debug.get("spectrum_analyzer_count", 0))
			== RadioAudioRenderer.MAX_RADIO_VOICES
			and bool(debug.get("continuous_mix_limiter", false)),
		"client renders music and shared-loop static through a fixed reusable radio voice pool"
	)
	var clean_pa_state := immediate_render_state.duplicate(true)
	var clean_pa_id := int(radio.get("item_id")) + 100000
	clean_pa_state["item_id"] = clean_pa_id
	clean_pa_state["receiver_static_enabled"] = false
	# Deliberately leave an audible authored gain behind: the explicit device policy must be the
	# authority, rather than allowing another magic threshold to become an implicit off-switch.
	clean_pa_state["static_mix_db"] = -12.0
	clean_pa_state["shared_program_group_id"] = clean_pa_id
	clean_pa_state["shared_program_late_field_enabled"] = false
	renderer.submit_snapshot({
		int(radio.get("item_id")): immediate_render_state,
		clean_pa_id: clean_pa_state,
	})
	await process_frame
	var clean_pa_slot := int(renderer._slot_by_item_id.get(clean_pa_id, -1))
	var clean_pa_debug := renderer.get_debug_state()
	_expect(
		clean_pa_slot >= 0
		and renderer._players[clean_pa_slot].playing
		and not renderer._static_players[clean_pa_slot].playing
		and int(clean_pa_debug.get("active_static_count", -1)) == 1,
		"a clean synchronized PA renders its program without starting a hidden receiver-noise voice"
	)
	# Return the shared renderer fixture to its original one-radio state before the existing
	# missing-snapshot lifecycle checks below.
	renderer.submit_snapshot({int(radio.get("item_id")): immediate_render_state})
	renderer._process(1.0)
	_expect(
		continuous_limiter != null
		and is_equal_approx(continuous_limiter.pre_gain_db, 0.0)
		and is_equal_approx(
			continuous_limiter.ceiling_db,
			RadioAudioRenderer.CONTINUOUS_LIMITER_CEILING_DB
		)
		and is_equal_approx(
			continuous_limiter.release,
			RadioAudioRenderer.CONTINUOUS_LIMITER_RELEASE_SECONDS
		),
		"the shared PA bus preserves normal program dynamics and hard-limits only genuine digital overs"
	)
	var shared_packets: Array[Dictionary] = [
		{
			"shared_program_group_id": 99001,
			"volume_db": -6.0,
			"reverb_send": 0.68,
			"reverb_room_size": 0.72,
			"reverb_damping": 0.66,
		},
		{
			"shared_program_group_id": 99001,
			"volume_db": -11.0,
			"reverb_send": 0.34,
			"reverb_room_size": 0.58,
			"reverb_damping": 0.52,
		},
	]
	var original_shared_power := 0.0
	for shared_packet: Dictionary in shared_packets:
		original_shared_power += pow(
			10.0,
			float(shared_packet["volume_db"]) / 10.0
		)
	renderer._prepare_shared_program_mix(shared_packets)
	var coherent_direct_amplitude := 0.0
	for shared_packet: Dictionary in shared_packets:
		coherent_direct_amplitude += db_to_linear(
			float(shared_packet["volume_db"])
		)
	var shared_group_slot := renderer._shared_program_group_slot(99001)
	var shared_late_power := pow(
		10.0,
		renderer._shared_program_target_volumes_db[shared_group_slot] / 10.0
	)
	var reconstructed_shared_power := (
		coherent_direct_amplitude * coherent_direct_amplitude
		+ shared_late_power
	)
	var shared_late_rack := renderer._shared_program_racks[shared_group_slot]
	var shared_late_target: Dictionary = (
		renderer._shared_program_target_packets[shared_group_slot]
	)
	shared_late_rack.apply_acoustic(
		shared_late_target,
		0.0,
		false,
		true
	)
	var expected_return_normalization := (
		SpatialAudioEffectRack.reverb_return_rms_normalization(
			shared_late_target
		)
	)
	_expect(
		shared_group_slot >= 0
		and absf(reconstructed_shared_power / original_shared_power - 1.0)
		< 0.001
		and AudioServer.get_bus_effect_count(shared_late_rack.bus_index) == 5
		and shared_late_rack.equalizer != null
		and shared_late_rack.lowpass != null
		and shared_late_rack.highpass != null
		and shared_late_rack.early_delay != null
		and is_equal_approx(shared_late_rack.early_delay.dry, 1.0)
		and shared_late_rack.early_delay.tap1_level_db <= -59.0
		and shared_late_rack.early_delay.tap2_level_db <= -59.0
		and is_zero_approx(shared_late_rack.reverb.dry)
		and is_equal_approx(
			shared_late_rack.reverb.wet,
			expected_return_normalization
		)
		and expected_return_normalization > 0.0
		and expected_return_normalization < 1.0,
		"a synchronized speaker group preserves authoritative power while rendering one wet-only listener-space late field"
	)
	var larger_room_target := shared_late_target.duplicate()
	larger_room_target["reverb_room_size"] = 0.92
	larger_room_target["reverb_predelay_feedback"] = 0.72
	var larger_room_normalization := (
		SpatialAudioEffectRack.reverb_return_rms_normalization(
			larger_room_target
		)
	)
	_expect(
		larger_room_normalization > 0.0
		and larger_room_normalization < expected_return_normalization
		and is_equal_approx(
			expected_return_normalization,
			SpatialAudioEffectRack.reverb_return_rms_normalization(
				shared_late_target
			)
		),
		"Godot's reverb return is normalized analytically and remains independent of program peaks"
	)
	var propagation_only_packets: Array[Dictionary] = [
		{
			"shared_program_group_id": 99002,
			"shared_program_late_field_enabled": false,
			"volume_db": -6.0,
			"reverb_send": 0.68,
		},
		{
			"shared_program_group_id": 99002,
			"shared_program_late_field_enabled": false,
			"volume_db": -11.0,
			"reverb_send": 0.34,
		},
	]
	var propagation_only_input_power := 0.0
	for propagation_packet: Dictionary in propagation_only_packets:
		propagation_only_input_power += pow(
			10.0,
			float(propagation_packet["volume_db"]) / 10.0
		)
	renderer._prepare_shared_program_mix(propagation_only_packets)
	var propagation_only_amplitude := 0.0
	for propagation_packet: Dictionary in propagation_only_packets:
		propagation_only_amplitude += db_to_linear(
			float(propagation_packet["volume_db"])
		)
	var propagation_only_slot := renderer._shared_program_group_slot(99002)
	_expect(
		propagation_only_slot >= 0
		and renderer._shared_program_target_packets[propagation_only_slot].is_empty()
		and renderer._shared_program_group_active[propagation_only_slot] == 0
		and absf(
			propagation_only_amplitude * propagation_only_amplitude
			/ propagation_only_input_power
			- 1.0
		) < 0.001,
		"a synchronized propagation-only group omits the wet return without losing its reserved energy"
	)
	_expect(
		RadioAudioRenderer.STATIC_STREAM_SOURCE.resource_path
		== "res://assets/third_party/pizza_doggy/audio/rot/radio_static_loop.wav"
		and RadioAudioRenderer.STATIC_STREAM_SOURCE.get_length() > 4.0,
		"radio static uses the curated multi-second receiver recording instead of generated noise"
	)
	var quiet_visual_level := RadioAudioRenderer._normalized_visual_level(
		Vector2(0.0001, 0.0001),
		Vector2(0.0001, 0.0001),
		-8.0
	)
	var loud_visual_level := RadioAudioRenderer._normalized_visual_level(
		Vector2(0.12, 0.1),
		Vector2(0.06, 0.05),
		-8.0
	)
	var rhythmic_onset := RadioAudioRenderer.music_pulse_target(
		0.82,
		0.28,
		0.34
	)
	var sustained_program := RadioAudioRenderer.music_pulse_target(
		0.82,
		0.82,
		0.82
	)
	var pulse_response := lerpf(
		0.0,
		rhythmic_onset,
		RadioAudioRenderer._follow_weight(
			RadioAudioRenderer.VISUAL_ATTACK_SPEED,
			1.0 / 60.0
		)
	)
	var pulse_peak := pulse_response
	for _frame: int in range(8):
		pulse_response = lerpf(
			pulse_response,
			sustained_program,
			RadioAudioRenderer._follow_weight(
				RadioAudioRenderer.VISUAL_RELEASE_SPEED,
				1.0 / 60.0
			)
		)
	var quiet_listener_activity := LISTENER_ACTIVITY.from_spectrum(
		Vector2(0.0001, 0.0001),
		Vector2(0.0001, 0.0001),
		Vector2(0.0001, 0.0001)
	)
	var loud_listener_activity := LISTENER_ACTIVITY.from_spectrum(
		Vector2(0.14, 0.12),
		Vector2(0.08, 0.07),
		Vector2(0.04, 0.03)
	)
	_expect(
		quiet_visual_level < 0.05
		and loud_visual_level > 0.9
		and rhythmic_onset > 0.9
		and sustained_program < 0.2
		and rhythmic_onset > sustained_program + 0.7
		and pulse_peak > 0.65
		and pulse_response < 0.25
		and quiet_listener_activity < 0.01
		and loud_listener_activity > 0.9,
		"radio spectrum energy drives a transient-rich rhythmic cone pulse separately from received listener activity"
	)
	var response_value := 0.0
	for _frame: int in range(7):
		response_value = lerpf(
			response_value,
			1.0,
			RadioAudioRenderer._follow_weight(
				RadioAudioRenderer.VOLUME_FOLLOW_SPEED,
				1.0 / 60.0
			)
		)
	_expect(
		response_value >= 0.95
		and int(debug.get("response_95_percent_msec", 1000)) <= 120,
		"continuous radio volume and DSP settle within about 120 ms instead of trailing movement for half a second"
	)
	_expect(
		RadioAudioRenderer.DRIFT_CHECK_INTERVAL_USEC >= 1000000
		and RadioAudioRenderer.DRIFT_HARD_RESYNC_SECONDS >= 1.0,
		"snapshot jitter cannot trigger frequent hard seeks in a healthy continuous song"
	)
	var pooled_voice_count := renderer._players.size()
	renderer.request_foreground_transient_space(0.78, -5.0)
	var loud_radio_duck_db := renderer._foreground_duck_db(-5.0)
	var quiet_radio_duck_db := renderer._foreground_duck_db(-35.0)
	_expect(
		loud_radio_duck_db < -3.5
		and is_zero_approx(quiet_radio_duck_db)
		and renderer._players.size() == pooled_voice_count,
		"an audible footstep briefly clears headroom only in masking-level radios without allocating a voice"
	)
	var held_envelope := float(
		renderer.get_debug_state().get("foreground_duck_envelope", 0.0)
	)
	renderer._update_foreground_duck(
		RadioAudioRenderer.FOREGROUND_DUCK_HOLD_SECONDS * 0.5
	)
	var envelope_during_attack := float(
		renderer.get_debug_state().get("foreground_duck_envelope", 0.0)
	)
	renderer._update_foreground_duck(0.25)
	var released_envelope := float(
		renderer.get_debug_state().get("foreground_duck_envelope", 1.0)
	)
	_expect(
		is_equal_approx(envelope_during_attack, held_envelope)
		and released_envelope < held_envelope * 0.1,
		"foreground headroom holds through the footstep slap then releases smoothly in well under a beat"
	)
	var bus_index := AudioServer.get_bus_index(&"ScavangeRadioVoice00")
	_expect(
		bus_index >= 0
		and AudioServer.get_bus_effect(bus_index, 0) is AudioEffectDistortion
		and AudioServer.get_bus_effect(bus_index, 4) is AudioEffectSpectrumAnalyzer
		and AudioServer.get_bus_effect(bus_index, 5) is AudioEffectDelay
		and AudioServer.get_bus_effect(bus_index, 6) is AudioEffectReverb,
		"radio voice analyzes its filtered program before hybrid early and late room effects"
	)
	var distortion := AudioServer.get_bus_effect(
		bus_index,
		0
	) as AudioEffectDistortion
	_expect(
		distortion != null
		and distortion.mode == AudioEffectDistortion.MODE_OVERDRIVE,
		"portable radio uses clear overdrive rather than destructive lo-fi filtering"
	)
	var smoothing_rack := SpatialAudioEffectRack.attach(
		&"ScavangeRadioSmoothingTest",
		true
	)
	smoothing_rack.apply_acoustic({"lowpass_hz": 1200.0})
	smoothing_rack.approach_acoustic({"lowpass_hz": 16000.0}, 0.25)
	_expect(
		smoothing_rack.lowpass.cutoff_hz > 1200.0
		and smoothing_rack.lowpass.cutoff_hz < 16000.0,
		"continuous filter changes interpolate logarithmically instead of switching in one snapshot"
	)
	_expect(
		AudioServer.is_bus_effect_enabled(
			smoothing_rack.bus_index,
			2
		),
		"continuous low-pass processing stays connected while its cutoff is lerped, avoiding an audible bypass switch"
	)
	smoothing_rack.apply_acoustic({
		"reverb_send": 0.5,
		"reverb_room_size": 0.8,
		"reverb_damping": 0.7,
		"reverb_spread": 0.55,
		"reverb_predelay_msec": 24.0,
		"reverb_predelay_feedback": 0.4,
	})
	var stable_reverb_spread := smoothing_rack.reverb.spread
	smoothing_rack.approach_acoustic({
		"reverb_send": 0.5,
		"reverb_room_size": 0.8,
		"reverb_damping": 0.7,
		"reverb_spread": 0.98,
		"reverb_predelay_msec": 24.0,
		"reverb_predelay_feedback": 0.4,
	}, 0.8)
	var normalized_mix := SpatialAudioEffectRack.power_normalized_reverb_mix(0.5)
	var normalized_return := (
		SpatialAudioEffectRack.reverb_return_rms_normalization({
			"reverb_room_size": 0.8,
			"reverb_predelay_feedback": 0.4,
		})
	)
	_expect(
		smoothing_rack.reverb is AudioEffectReverb
		and is_equal_approx(
			smoothing_rack.reverb.wet,
			normalized_mix.y * normalized_return
		)
		and absf(
			normalized_mix.x * normalized_mix.x
			+ normalized_mix.y * normalized_mix.y
			- 1.0
		) < 0.0001
		and is_equal_approx(smoothing_rack.reverb.dry, normalized_mix.x)
		and is_equal_approx(smoothing_rack.reverb.room_size, 0.8)
		and is_equal_approx(smoothing_rack.reverb.predelay_msec, 24.0)
		and is_equal_approx(
			stable_reverb_spread,
			SpatialAudioEffectRack.REALTIME_SAFE_REVERB_SPREAD
		)
		and is_equal_approx(
			smoothing_rack.reverb.spread,
			stable_reverb_spread
		),
		"continuous voice rack power-bounds its hall and never rewrites the populated stereo delay topology"
	)
	var reflective_room := {
		"reverb_send": 0.6,
		"environment_enclosure": 0.85,
		"reverb_damping": 0.85,
		"reverb_predelay_feedback": 0.4,
	}
	var bright_bloom := RadioAudioRenderer.spectral_room_bloom_target(
		Vector2(0.04, 0.04),
		Vector2(0.12, 0.12),
		0.0,
		reflective_room
	)
	var dark_bloom := RadioAudioRenderer.spectral_room_bloom_target(
		Vector2(0.12, 0.12),
		Vector2(0.02, 0.02),
		0.0,
		reflective_room
	)
	var outdoor_bloom := RadioAudioRenderer.spectral_room_bloom_target(
		Vector2(0.04, 0.04),
		Vector2(0.12, 0.12),
		0.0,
		{"reverb_send": 0.0, "environment_enclosure": 0.0}
	)
	var base_room_response := SpatialAudioEffectRack.spectral_bloom_reverb_response(
		reflective_room,
		0.0
	)
	var bright_room_response := SpatialAudioEffectRack.spectral_bloom_reverb_response(
		reflective_room,
		bright_bloom
	)
	var bright_room_mix := SpatialAudioEffectRack.power_normalized_reverb_mix(
		bright_room_response.x
	)
	var shared_bloom_gain_db := RadioAudioRenderer.shared_late_field_bloom_gain_db(
		reflective_room,
		bright_bloom
	)
	_expect(
		bright_bloom > 0.75
		and dark_bloom < 0.05
		and is_zero_approx(outdoor_bloom)
		and bright_room_response.x > base_room_response.x + 0.1
		and bright_room_response.y > base_room_response.y
		and bright_room_mix.y > normalized_mix.y
		and shared_bloom_gain_db > 0.0
		and shared_bloom_gain_db
		<= RadioAudioRenderer.SHARED_LATE_FIELD_BLOOM_MAX_GAIN_DB
		and absf(
			bright_room_mix.x * bright_room_mix.x
			+ bright_room_mix.y * bright_room_mix.y
			- 1.0
		) < 0.0001
		and smoothing_rack._spectrum_effect_index
		< smoothing_rack._reverb_effect_index,
		"sustained brilliance blooms only inside a reflective room and remains power bounded"
	)
	_expect(
		is_equal_approx(
			RadioAudioRenderer._approach_volume_db(-10.0, -30.0, 1.0, 0.7),
			-10.7
		),
		"large continuous volume changes obey the per-frame decibel slew limit"
	)

	var player_id: int = game_state.call("try_register_player", 1, 1000, 4)
	if player_id < 0:
		player_id = int(game_state.call("get_player_id", 1))
	server.call("spawn_server_player", player_id, Vector3.ZERO, null, null)
	var server_player := server.call(
		"get_server_player",
		player_id
	) as ServerPlayer
	if server_player != null:
		server_player.set_wrist_interface_open(true)
	_expect(
		server_player != null
		and server.call(
			"_validate_fieldlink_control_target",
			server_player,
			StringName("item:%d" % int(radio.get("item_id")))
		) == radio,
		"server accepts a nearby equipped Fieldlink link to the authoritative radio"
	)
	if server_player != null:
		server_player.global_position = Vector3(100.0, 0.0, 0.0)
	_expect(
		server_player != null
		and server.call(
			"_validate_fieldlink_control_target",
			server_player,
			StringName("item:%d" % int(radio.get("item_id")))
		) == null,
		"server rejects remote device commands after their sender leaves scanner range"
	)
	if server_player != null:
		server_player.global_position = Vector3.ZERO
	server.call("publish_states")
	await process_frame
	var network_renderer := client.get("radio_audio_renderer") as RadioAudioRenderer
	_expect(
		network_renderer != null
		and int(network_renderer.get_debug_state().get("active_count", 0)) >= 1,
		"server sends the owning client its listener-specific continuous radio state"
	)
	if network_renderer != null:
		client.call("_on_foreground_transient_started", 0.78, -5.0)
	_expect(
		network_renderer != null
		and float(network_renderer.get_debug_state().get(
			"foreground_duck_envelope",
			0.0
		)) > 0.7,
		"the client routes received foreground attacks into its active radio mix"
	)
	var item_proxies: Dictionary = client.get("item_proxies_by_item_id")
	var radio_proxy := item_proxies.get(int(radio.get("item_id"))) as Node
	var power_light := (
		radio_proxy.get_node_or_null(
			"ItemVisual/PortableRadioVisual/PowerLight"
		) as GeometryInstance3D
		if radio_proxy != null
		else null
	)
	_expect(
		power_light != null and power_light.visible,
		"replicated item presentation shows the powered radio light"
	)

	var first_revision := int(radio.get("playback_revision"))
	radio.call("set_powered", false)
	_expect(
		not bool((radio.call("to_state_dict") as Dictionary).get("radio_powered", true)),
		"server replicates the powered-off presentation state"
	)
	server.call("publish_states")
	await process_frame
	_expect(
		power_light != null and not power_light.visible,
		"powered-off state clears the client radio light"
	)
	radio.call("set_powered", true)
	_expect(
		int(radio.get("playback_revision")) > first_revision,
		"each restart creates a new authoritative song revision"
	)
	renderer.submit_snapshot({})
	var fading_debug := renderer.get_debug_state()
	var fading_slot := int(renderer._slot_by_item_id.get(
		int(radio.get("item_id")),
		-1
	))
	var fading_volume_before := (
		renderer._players[fading_slot].volume_db if fading_slot >= 0 else -80.0
	)
	renderer._process(0.05)
	var fading_volume_after := (
		renderer._players[fading_slot].volume_db if fading_slot >= 0 else -80.0
	)
	_expect(
		int(fading_debug.get("active_count", -1)) == 1
		and int(fading_debug.get("retiring_count", 0)) == 1
		and fading_slot >= 0
		and renderer._players[fading_slot].playing
		and fading_volume_after < fading_volume_before,
		"a missing continuous snapshot fades its existing voice instead of hard-stopping it"
	)
	var recovery_state: Dictionary = radio.call(
		"build_listener_state",
		1,
		Vector3.ZERO,
		service
	)
	renderer.submit_snapshot({int(radio.get("item_id")): recovery_state})
	_expect(
		int(renderer._slot_by_item_id.get(int(radio.get("item_id")), -1))
		== fading_slot
		and renderer._slot_retiring[fading_slot] == 0
		and renderer._players[fading_slot].playing
		and is_equal_approx(
			renderer._players[fading_slot].volume_db,
			fading_volume_after
		),
		"a continuous state returning after one skipped snapshot resumes the same smoothly faded voice"
	)
	renderer.submit_snapshot({})
	renderer._process(1.0)
	_expect(
		int(renderer.get_debug_state().get("active_count", -1)) == 0,
		"an inaudible retired continuous voice returns its fixed pool slot"
	)

	renderer.queue_free()
	radio.queue_free()
	client.call("reset_session")
	await process_frame


func _test_fieldlink_control_adapter(
	radio: Node,
	definition: RadioItemDefinition,
	service: ServerAcousticService,
	speaker_position: Vector3
) -> void:
	var raw_snapshot := radio.call(
		"build_fieldlink_control_snapshot",
		null
	) as Dictionary
	raw_snapshot["contact_id"] = StringName(
		"item:%d" % int(radio.get("item_id"))
	)
	var snapshot := FieldlinkDeviceControlPacket.sanitize_snapshot(raw_snapshot)
	var payload: Dictionary = snapshot.get("payload", {})
	var tracks: Array = payload.get("tracks", [])
	_expect(
		not snapshot.is_empty()
		and tracks.size() == mini(
			definition.discover_song_paths().size(),
			FieldlinkDeviceControlPacket.MAX_TRACK_COUNT
		)
		and payload.get("playback_state") == &"playing",
		"radio exposes a bounded generic Fieldlink snapshot with its available tracks"
	)
	var unsafe_command := FieldlinkDeviceControlPacket.sanitize_command(
		raw_snapshot.get("contact_id"),
		&"play_track",
		{
			"track_index": 0,
			"resource": definition,
		}
	)
	_expect(
		unsafe_command.get("payload", {}).has("track_index")
		and not unsafe_command.get("payload", {}).has("resource"),
		"generic device commands discard object and resource payloads at the network boundary"
	)
	radio.call("set_control_volume_ratio", 1.0)
	var loud_state := radio.call(
		"build_listener_state",
		91,
		speaker_position + Vector3(0.0, 0.0, 1.0),
		service
	) as Dictionary
	radio.call("apply_fieldlink_command", null, &"set_volume", {
		"volume_ratio": 0.2,
	})
	var quiet_state := radio.call(
		"build_listener_state",
		91,
		speaker_position + Vector3(0.0, 0.0, 1.0),
		service
	) as Dictionary
	var far_listener_position := speaker_position + Vector3(0.0, 0.0, 30.0)
	var quiet_far_state := radio.call(
		"build_listener_state",
		93,
		far_listener_position,
		service
	) as Dictionary
	radio.call("set_control_volume_ratio", 1.0)
	var loud_far_state := radio.call(
		"build_listener_state",
		94,
		far_listener_position,
		service
	) as Dictionary
	_expect(
		float(quiet_state.get("volume_db", 0.0))
		< float(loud_state.get("volume_db", 0.0)) - 5.0,
		"remote loudness changes the authoritative spatial signal heard by every listener"
	)
	_expect(
		quiet_far_state.is_empty() and not loud_far_state.is_empty(),
		"radio volume changes both received level and physically supported hearing distance"
	)
	_expect(
		bool(radio.call("apply_fieldlink_command", null, &"pause", {}))
		and (radio.call(
			"build_listener_state",
			92,
			speaker_position,
			service
		) as Dictionary).is_empty(),
		"pausing through Fieldlink suspends the shared continuous sound"
	)
	var paused_snapshot := radio.call(
		"build_fieldlink_control_snapshot",
		null
	) as Dictionary
	_expect(
		paused_snapshot.get("payload", {}).get("playback_state") == &"paused"
		and bool(radio.call("apply_fieldlink_command", null, &"resume", {})),
		"pause state round-trips to the panel and can resume the same timeline"
	)
	_expect(
		bool(radio.call("apply_fieldlink_command", null, &"stop", {}))
		and not bool(radio.get("powered")),
		"stop is distinct from pause and clears active playback"
	)
	_expect(
		bool(radio.call("apply_fieldlink_command", null, &"play_track", {
			"track_index": 0,
		}))
		and str(radio.get("current_song_path"))
		== definition.discover_song_paths()[0],
		"selecting a listed track starts that exact server-owned stream"
	)
	radio.call("set_control_volume_ratio", 0.75)


func _finish() -> void:
	if failure_count == 0:
		print("Radio system tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Radio system tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)
