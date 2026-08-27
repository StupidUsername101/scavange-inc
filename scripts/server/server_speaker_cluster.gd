class_name ServerSpeakerCluster
extends "res://scripts/audio/speaker_array_3d.gd"

const COLLISION_BUILDER := preload(
	"res://scripts/world/static_structure_collision_builder.gd"
)
const SPEAKER_CABINET_ACOUSTIC_MATERIAL := preload(
	"res://resources/world/acoustic_materials/speaker_cabinet.tres"
)
const DEFAULT_PLAYBACK_PROFILE_PATH := (
	"res://resources/items/radios/facility_pa_playback.tres"
)
const PLAYLIST_CHECK_INTERVAL_SECONDS := 0.1
const MIN_STREAM_LENGTH_SECONDS := 0.05
const UNKNOWN_STREAM_LENGTH_SECONDS := 300.0
const VOLUME_CONTROL := preload("res://scripts/audio/speaker_volume_control.gd")
const MUSIC_LOUDNESS := preload("res://scripts/audio/music_loudness_catalog.gd")
const MIN_CONTROL_VOLUME_DB := VOLUME_CONTROL.MIN_CONTROL_VOLUME_DB
const MAX_CONTROL_VOLUME_DB := VOLUME_CONTROL.MAX_CONTROL_VOLUME_DB
const MUTED_CONTROL_VOLUME_DB := VOLUME_CONTROL.MUTED_CONTROL_VOLUME_DB
const CONTROL_VOLUME_CURVE := VOLUME_CONTROL.CONTROL_VOLUME_CURVE

@export var start_powered := false

# Cached definition values preserve the small public surface used by audio diagnostics without
# duplicating configuration across authoritative and visible scenes.
var playback_profile: RadioItemDefinition
var source_modifier: AcousticPathModifier
var use_shared_late_field := false
var maximum_hearing_distance := 72.0
var playback_volume_db := -11.0

var powered := false
var paused := false
var current_song_path := ""
var current_song_length_seconds := 0.0
var playback_revision := 0
var playback_started_msec := 0
var paused_offset_seconds := 0.0
var selected_song_path := ""
var control_volume_db := VOLUME_CONTROL.DEFAULT_CONTROL_VOLUME_DB
var control_revision := 0

var _playlist: Array[String] = []
var _track_descriptors: Array[Dictionary] = []
var _speaker_positions := PackedVector3Array()
var _emitter_ids := PackedInt32Array()
var _emitter_installation_gains_db := PackedFloat32Array()
var _emitter_reach_multipliers := PackedFloat32Array()
var _last_song_path := ""
var _song_check_remaining := 0.0
var _rng := RandomNumberGenerator.new()
var _sanitized_source_modifier: AcousticPathModifier


func _ready() -> void:
	super._ready()
	add_to_group(&"speaker_cluster_demo")
	_apply_array_definition()
	_cache_emitters()
	_build_speaker_collision()
	if _speaker_markers.is_empty():
		push_warning("%s has no SpeakerArrayEmitter3D children" % _cluster_display_name())
		return
	_rng.seed = hash("%s:%d" % [_cluster_contact_id(), Time.get_ticks_usec()])
	_ensure_playlist()
	_sanitized_source_modifier = (
		source_modifier.sanitized_copy()
		if source_modifier != null
		else AcousticPathModifier.identity()
	)
	var server := get_node_or_null("/root/Server")
	if server != null:
		server.call("register_speaker_cluster", self)
		server.call("register_fieldlink_control_target", _cluster_contact_id(), self)
	if start_powered and multiplayer.is_server():
		_start_random_song()


func _exit_tree() -> void:
	var server := get_node_or_null("/root/Server")
	if server == null:
		return
	server.call("unregister_speaker_cluster", self)
	server.call("unregister_fieldlink_control_target", _cluster_contact_id())
	var acoustic_service := server.get("acoustic_service") as ServerAcousticService
	if acoustic_service != null:
		for emitter_id: int in _emitter_ids:
			acoustic_service.forget_continuous_source(emitter_id)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not powered or paused:
		return
	_song_check_remaining -= delta
	if _song_check_remaining <= 0.0:
		_song_check_remaining = PLAYLIST_CHECK_INTERVAL_SECONDS
		if get_elapsed_seconds() >= current_song_length_seconds:
			_start_random_song()


func set_powered(value: bool) -> bool:
	if not multiplayer.is_server() or powered == value:
		return powered
	if value:
		return _start_random_song()
	_stop_playback()
	return false


func set_paused(value: bool) -> bool:
	if not multiplayer.is_server() or not powered or paused == value:
		return paused
	if value:
		paused_offset_seconds = get_elapsed_seconds()
		paused = true
	else:
		playback_started_msec = Time.get_ticks_msec() - roundi(paused_offset_seconds * 1000.0)
		paused = false
	playback_revision += 1
	control_revision += 1
	return paused


func set_control_volume_ratio(value: float) -> float:
	if not multiplayer.is_server():
		return get_control_volume_ratio()
	control_volume_db = VOLUME_CONTROL.decibels_from_ratio(value)
	control_revision += 1
	return get_control_volume_ratio()


func get_control_volume_ratio() -> float:
	return VOLUME_CONTROL.ratio_from_decibels(control_volume_db)


func get_elapsed_seconds() -> float:
	if not powered:
		return 0.0
	if paused:
		return paused_offset_seconds
	if playback_started_msec <= 0:
		return 0.0
	return maxf(float(Time.get_ticks_msec() - playback_started_msec) / 1000.0, 0.0)


func build_fieldlink_control_snapshot(_player: ServerPlayer) -> Dictionary:
	_ensure_playlist()
	if _track_descriptors.is_empty():
		return {}
	return {
		"control_type": &"speaker_cluster",
		"display_name": _cluster_display_name(),
		"status_text": _playback_state_name().to_upper(),
		"revision": control_revision,
		"payload": {
			"tracks": _track_descriptors,
			"selected_track_index": _playlist.find(selected_song_path),
			"current_track_index": _playlist.find(current_song_path),
			"playback_state": _playback_state_name(),
			"volume_ratio": get_control_volume_ratio(),
			"elapsed_seconds": get_elapsed_seconds(),
			"duration_seconds": current_song_length_seconds,
		},
	}


func apply_fieldlink_command(
	_player: ServerPlayer,
	action: StringName,
	payload: Dictionary
) -> bool:
	if not multiplayer.is_server():
		return false
	match action:
		&"play_track":
			return _start_song_at_index(SafeVariant.integral_int_or(payload.get("track_index"), -1))
		&"pause":
			return powered and not paused and set_paused(true)
		&"resume":
			if not powered or not paused:
				return false
			set_paused(false)
			return not paused
		&"stop":
			if not powered:
				return false
			_stop_playback()
			return true
		&"set_volume":
			var ratio := SafeVariant.finite_float_or(payload.get("volume_ratio"), INF)
			if not is_finite(ratio):
				return false
			set_control_volume_ratio(ratio)
			return true
	return false


func append_listener_states(
	result: Dictionary,
	listener_id: int,
	listener_position: Vector3,
	acoustic_service: ServerAcousticService,
	listener_collision_rid: RID = RID()
) -> void:
	if (
		not powered
		or paused
		or current_song_path.is_empty()
		or playback_profile == null
		or acoustic_service == null
	):
		return
	var program_normalization_gain_db := (
		MUSIC_LOUDNESS.gain_db_for_path(current_song_path)
	)
	var program_reference_gain_db := MUSIC_LOUDNESS.DEVICE_REFERENCE_GAIN_DB
	var output_level_db := clampf(
		playback_volume_db
		+ control_volume_db
		+ program_normalization_gain_db
		+ program_reference_gain_db,
		AcousticPropagationGraph.MIN_SOURCE_LEVEL_DB,
		AcousticPropagationGraph.MAX_SOURCE_LEVEL_DB
	)
	var level_scaled_max_distance := AcousticPropagationGraph.level_scaled_hearing_distance(
		maximum_hearing_distance,
		control_volume_db
	)
	var elapsed := get_elapsed_seconds()
	var exclusions: Array[RID] = []
	if listener_collision_rid.is_valid():
		exclusions.append(listener_collision_rid)
	for speaker_index: int in range(_speaker_positions.size()):
		var source_position := global_transform * _speaker_positions[speaker_index]
		var emitter_id := _emitter_ids[speaker_index]
		var installation_gain_db := _emitter_installation_gains_db[speaker_index]
		var emitter_max_distance := minf(
			level_scaled_max_distance * _emitter_reach_multipliers[speaker_index],
			AcousticPropagationGraph.MAX_LEVEL_SCALED_HEARING_DISTANCE
		)
		var maximum_world_distance := acoustic_service.source_hearing_distance_upper_bound(
			emitter_max_distance,
			source_position,
			emitter_id,
			exclusions
		)
		if listener_position.distance_squared_to(source_position) > maximum_world_distance * maximum_world_distance:
			continue
		var state := acoustic_service.calculate_listener_result(
			listener_id,
			listener_position,
			source_position,
			emitter_max_distance,
			_sanitized_source_modifier,
			AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
			true,
			exclusions,
			emitter_id
		)
		if not bool(state.get("audible", false)):
			continue
		state.erase("audible")
		var travel_delay := float(state.get("travel_delay_seconds", 0.0))
		state["item_id"] = emitter_id
		state["revision"] = playback_revision
		state["song_path"] = current_song_path
		state["playback_offset_seconds"] = maxf(elapsed - travel_delay, 0.0)
		state["start_delay_seconds"] = maxf(travel_delay - elapsed, 0.0)
		# Every cabinet carries the same digital program. Preserve physical per-path delay for
		# diagnostics, but also identify the shared timeline so the client can prevent perfectly
		# correlated copies from comb-filtering each other at arbitrary listener positions.
		state["shared_program_group_id"] = _shared_program_group_id()
		state["shared_program_late_field_enabled"] = use_shared_late_field
		state["program_playback_offset_seconds"] = maxf(elapsed, 0.0)
		state["stream_length_seconds"] = current_song_length_seconds
		state["program_normalization_gain_db"] = program_normalization_gain_db
		state["program_reference_gain_db"] = program_reference_gain_db
		state["volume_db"] = (
			float(state.get("volume_db", 0.0))
			+ output_level_db
			+ installation_gain_db
		)
		state["installation_gain_db"] = installation_gain_db
		state["priority"] = 0.78
		state["distortion_mode"] = playback_profile.distortion_mode
		state["distortion_drive"] = playback_profile.distortion_drive
		state["distortion_keep_hf_hz"] = playback_profile.distortion_keep_hf_hz
		state["distortion_post_gain_db"] = playback_profile.distortion_post_gain_db
		state["receiver_static_enabled"] = playback_profile.receiver_static_enabled
		state["static_mix_db"] = playback_profile.static_mix_db
		result[emitter_id] = state


func get_emitter_ids() -> PackedInt32Array:
	return _emitter_ids


func _start_random_song() -> bool:
	_ensure_playlist()
	if _playlist.is_empty():
		_stop_playback()
		push_warning("%s has no supported music tracks" % _cluster_display_name())
		return false
	var song_index := _rng.randi_range(0, _playlist.size() - 1)
	if _playlist.size() > 1 and _playlist[song_index] == _last_song_path:
		song_index = (song_index + 1) % _playlist.size()
	return _start_song_at_index(song_index)


func _start_song_at_index(song_index: int) -> bool:
	_ensure_playlist()
	if song_index < 0 or song_index >= _playlist.size():
		return false
	var song_path := _playlist[song_index]
	var stream := load(song_path) as AudioStream
	if stream == null:
		_playlist.remove_at(song_index)
		_rebuild_track_descriptors()
		return false
	var stream_length := stream.get_length()
	if stream_length < MIN_STREAM_LENGTH_SECONDS:
		stream_length = UNKNOWN_STREAM_LENGTH_SECONDS
	_last_song_path = song_path
	selected_song_path = song_path
	current_song_path = song_path
	current_song_length_seconds = stream_length
	playback_started_msec = Time.get_ticks_msec()
	playback_revision += 1
	control_revision += 1
	_song_check_remaining = PLAYLIST_CHECK_INTERVAL_SECONDS
	powered = true
	paused = false
	paused_offset_seconds = 0.0
	return true


func _stop_playback() -> void:
	powered = false
	paused = false
	current_song_path = ""
	current_song_length_seconds = 0.0
	playback_started_msec = 0
	paused_offset_seconds = 0.0
	playback_revision += 1
	control_revision += 1


func _ensure_playlist() -> void:
	if not _playlist.is_empty() or playback_profile == null:
		return
	_playlist = playback_profile.discover_song_paths()
	_rebuild_track_descriptors()
	if selected_song_path.is_empty() and not _playlist.is_empty():
		selected_song_path = _playlist[0]


func _rebuild_track_descriptors() -> void:
	_track_descriptors.clear()
	for track_index: int in range(_playlist.size()):
		_track_descriptors.append({
			"track_index": track_index,
			"display_name": _playlist[track_index].get_file().get_basename().replace("_", " ").strip_edges().to_upper(),
		})


func _playback_state_name() -> StringName:
	if not powered:
		return &"stopped"
	return &"paused" if paused else &"playing"


func _apply_array_definition() -> void:
	if array_definition == null:
		push_warning("Speaker array has no definition; using safe local defaults")
		playback_profile = load(DEFAULT_PLAYBACK_PROFILE_PATH) as RadioItemDefinition
		source_modifier = null
		use_shared_late_field = false
		maximum_hearing_distance = 72.0
		playback_volume_db = -11.0
		return
	playback_profile = array_definition.playback_profile
	if playback_profile == null:
		playback_profile = load(DEFAULT_PLAYBACK_PROFILE_PATH) as RadioItemDefinition
	source_modifier = array_definition.source_modifier
	use_shared_late_field = array_definition.shared_late_field_enabled
	maximum_hearing_distance = array_definition.maximum_hearing_distance
	playback_volume_db = array_definition.playback_volume_db


func _cache_emitters() -> void:
	_speaker_markers = _discover_speaker_markers()
	for speaker_index: int in range(_speaker_markers.size()):
		var marker := _speaker_markers[speaker_index]
		_speaker_positions.append(marker.source_position_relative_to(self))
		_emitter_ids.append(_emitter_id(speaker_index))
		var installation_gain_db := clampf(
			marker.installation_gain_db,
			-24.0,
			12.0
		)
		_emitter_installation_gains_db.append(installation_gain_db)
		# Installation gain is authored once per fixed cabinet. Cache its linear pressure/reach
		# multiplier instead of evaluating an exponential for every listener and network tick.
		_emitter_reach_multipliers.append(db_to_linear(installation_gain_db))


func _build_speaker_collision() -> void:
	var speaker_boxes: Array[Dictionary] = []
	for marker: SpeakerArrayEmitter3D in _speaker_markers:
		var relative_transform := marker.transform_relative_to(self)
		speaker_boxes.append({
			"name": marker.name,
			"position": relative_transform.origin,
			"rotation": relative_transform.basis.get_euler(),
			"size": marker.sanitized_cabinet_size(),
			"material_id": &"speaker_cabinet",
			"physical_surface": &"metal",
			"acoustic_material": SPEAKER_CABINET_ACOUSTIC_MATERIAL,
		})
	COLLISION_BUILDER.build_clustered_box_bodies(
		self,
		speaker_boxes,
		&"metal",
		SPEAKER_CABINET_ACOUSTIC_MATERIAL,
		"FacilitySpeaker"
	)
