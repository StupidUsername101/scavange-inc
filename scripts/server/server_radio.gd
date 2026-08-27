@tool
class_name ServerRadio
extends ServerItem

const PLAYLIST_CHECK_INTERVAL_SECONDS := 0.1
const MIN_STREAM_LENGTH_SECONDS := 0.05
const UNKNOWN_STREAM_LENGTH_SECONDS := 300.0
const TOGGLE_COOLDOWN_MILLISECONDS := 150
const VOLUME_CONTROL := preload("res://scripts/audio/speaker_volume_control.gd")
const MUSIC_LOUDNESS := preload("res://scripts/audio/music_loudness_catalog.gd")
const MIN_CONTROL_VOLUME_DB := VOLUME_CONTROL.MIN_CONTROL_VOLUME_DB
const MAX_CONTROL_VOLUME_DB := VOLUME_CONTROL.MAX_CONTROL_VOLUME_DB
const MUTED_CONTROL_VOLUME_DB := VOLUME_CONTROL.MUTED_CONTROL_VOLUME_DB
const CONTROL_VOLUME_CURVE := VOLUME_CONTROL.CONTROL_VOLUME_CURVE

## Server-authoritative continuous radio. Clients never decide which track is playing or where on
## its timeline they should be; they only render listener-specific snapshots from this body.

var powered := false
var current_song_path := ""
var current_song_length_seconds := 0.0
var playback_revision := 0
var playback_started_msec := 0
var paused := false
var paused_offset_seconds := 0.0
var selected_song_path := ""
var control_volume_db := VOLUME_CONTROL.DEFAULT_CONTROL_VOLUME_DB
var control_revision := 0

var _playlist: Array[String] = []
var _track_descriptors: Array[Dictionary] = []
var _last_song_path := ""
var _song_check_remaining := 0.0
var _next_toggle_msec := 0
var _rng := RandomNumberGenerator.new()
var _sanitized_source_modifier: AcousticPathModifier


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	_rng.seed = hash("radio:%d:%d" % [item_id, Time.get_ticks_usec()])
	var radio := get_radio_definition()
	if radio != null:
		_ensure_playlist()
		_sanitized_source_modifier = (
			radio.source_modifier.sanitized_copy()
			if radio.source_modifier != null
			else AcousticPathModifier.identity()
		)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not multiplayer.is_server() or not powered or paused:
		return
	_song_check_remaining -= delta
	if _song_check_remaining > 0.0:
		return
	_song_check_remaining = PLAYLIST_CHECK_INTERVAL_SECONDS
	if get_elapsed_seconds() >= current_song_length_seconds:
		_start_random_song()


func get_radio_definition() -> RadioItemDefinition:
	return definition as RadioItemDefinition


func prefers_server_use() -> bool:
	return true


func get_server_interaction_hint(player: ServerPlayer, hit: Dictionary) -> String:
	var power_hint := "TURN OFF" if powered else "TURN ON"
	if hit.get("collider") == self:
		return "F // %s" % power_hint
	var can_store := (
		player != null
		and player.inventory_entries.size() < player.get_inventory_capacity()
	)
	return "%s   LMB // %s" % [
		"F // STORE" if can_store else "INVENTORY FULL",
		power_hint,
	]


func server_use(_player: ServerPlayer, _hit: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_toggle_msec:
		return
	_next_toggle_msec = now_msec + TOGGLE_COOLDOWN_MILLISECONDS
	set_powered(not powered)


func server_held_primary_action(player: ServerPlayer) -> void:
	server_use(player, {})


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
		playback_started_msec = (
			Time.get_ticks_msec()
			- roundi(paused_offset_seconds * 1000.0)
		)
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


func build_fieldlink_control_snapshot(_player: ServerPlayer) -> Dictionary:
	_ensure_playlist()
	if _track_descriptors.is_empty():
		return {}
	return {
		"control_type": &"radio",
		"display_name": definition.display_name if definition != null else "RADIO",
		"status_text": _playback_state_name().to_upper(),
		"revision": control_revision,
		"payload": {
			"tracks": _track_descriptors,
			"selected_track_index": _track_index(selected_song_path),
			"current_track_index": _track_index(current_song_path),
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
			return _start_song_at_index(SafeVariant.integral_int_or(
				payload.get("track_index"),
				-1
			))
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
			var ratio := SafeVariant.finite_float_or(
				payload.get("volume_ratio"),
				INF
			)
			if not is_finite(ratio):
				return false
			set_control_volume_ratio(ratio)
			return true
	return false


func _stop_playback() -> void:
	powered = false
	current_song_path = ""
	current_song_length_seconds = 0.0
	playback_started_msec = 0
	paused = false
	paused_offset_seconds = 0.0
	playback_revision += 1
	control_revision += 1


func get_elapsed_seconds() -> float:
	if not powered:
		return 0.0
	if paused:
		return paused_offset_seconds
	if playback_started_msec <= 0:
		return 0.0
	return maxf(
		float(Time.get_ticks_msec() - playback_started_msec) / 1000.0,
		0.0
	)


func build_listener_state(
	listener_id: int,
	listener_position: Vector3,
	acoustic_service: ServerAcousticService,
	listener_collision_rid: RID = RID()
) -> Dictionary:
	var radio := get_radio_definition()
	if (
		not powered
		or paused
		or current_song_path.is_empty()
		or radio == null
		or acoustic_service == null
	):
		return {}
	var source_position := radio.get_speaker_world_position(global_transform)
	# The offline EBU R128 catalog makes the authored output mean the same thing for a modern
	# brick-walled master and an old quiet recording. The amplifier remains the user-controlled
	# relative gain that changes physical reach.
	var program_normalization_gain_db := (
		MUSIC_LOUDNESS.gain_db_for_path(current_song_path)
	)
	var program_reference_gain_db := MUSIC_LOUDNESS.DEVICE_REFERENCE_GAIN_DB
	var output_level_db := clampf(
		radio.playback_volume_db
		+ control_volume_db
		+ program_normalization_gain_db
		+ program_reference_gain_db,
		AcousticPropagationGraph.MIN_SOURCE_LEVEL_DB,
		AcousticPropagationGraph.MAX_SOURCE_LEVEL_DB
	)
	var level_scaled_max_distance := (
		AcousticPropagationGraph.level_scaled_hearing_distance(
			radio.maximum_hearing_distance,
			control_volume_db
		)
	)
	var exclusions: Array[RID] = [get_rid()]
	if listener_collision_rid.is_valid():
		exclusions.append(listener_collision_rid)
	var maximum_world_distance := (
		acoustic_service.source_hearing_distance_upper_bound(
			level_scaled_max_distance,
			source_position,
			item_id,
			exclusions
		)
	)
	if listener_position.distance_squared_to(source_position) > (
		maximum_world_distance * maximum_world_distance
	):
		return {}
	var result := acoustic_service.calculate_listener_result(
		listener_id,
		listener_position,
		source_position,
		level_scaled_max_distance,
		_sanitized_source_modifier,
		AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
		true,
		exclusions,
		item_id
	)
	if not bool(result.get("audible", false)):
		return {}
	result.erase("audible")
	var elapsed := get_elapsed_seconds()
	var travel_delay := float(result.get("travel_delay_seconds", 0.0))
	result["item_id"] = item_id
	result["revision"] = playback_revision
	result["song_path"] = current_song_path
	result["playback_offset_seconds"] = maxf(elapsed - travel_delay, 0.0)
	result["start_delay_seconds"] = maxf(travel_delay - elapsed, 0.0)
	result["stream_length_seconds"] = current_song_length_seconds
	result["program_normalization_gain_db"] = program_normalization_gain_db
	result["program_reference_gain_db"] = program_reference_gain_db
	result["volume_db"] = (
		float(result.get("volume_db", 0.0))
		+ output_level_db
	)
	result["priority"] = 0.72
	result["distortion_mode"] = radio.distortion_mode
	result["distortion_drive"] = radio.distortion_drive
	result["distortion_keep_hf_hz"] = radio.distortion_keep_hf_hz
	result["distortion_post_gain_db"] = radio.distortion_post_gain_db
	result["receiver_static_enabled"] = radio.receiver_static_enabled
	result["static_mix_db"] = radio.static_mix_db
	return result


func to_state_dict() -> Dictionary:
	var result := super.to_state_dict()
	result["radio_powered"] = powered
	result["radio_paused"] = paused
	return result


func _start_random_song() -> bool:
	_ensure_playlist()
	if _playlist.is_empty():
		powered = false
		current_song_path = ""
		push_warning("Radio has no supported songs in its music directory")
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


func _ensure_playlist() -> void:
	if not _playlist.is_empty():
		return
	var radio := get_radio_definition()
	if radio == null:
		return
	_playlist = radio.discover_song_paths()
	_rebuild_track_descriptors()
	if selected_song_path.is_empty() and not _playlist.is_empty():
		selected_song_path = _playlist[0]


func _rebuild_track_descriptors() -> void:
	_track_descriptors.clear()
	for track_index: int in range(_playlist.size()):
		_track_descriptors.append({
			"track_index": track_index,
			"display_name": _track_display_name(_playlist[track_index]),
		})


static func _track_display_name(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").strip_edges().to_upper()


func _track_index(path: String) -> int:
	return _playlist.find(path)


func _playback_state_name() -> StringName:
	if not powered:
		return &"stopped"
	return &"paused" if paused else &"playing"
