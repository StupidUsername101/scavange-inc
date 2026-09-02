extends Node

const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)
const LOCAL_AUDIO_PREDICTION_RUNTIME := preload(
	"res://scripts/audio/local_audio_prediction_runtime.gd"
)
const RADIO_STATE_SNAPSHOT_CODEC := preload(
	"res://scripts/audio/radio_state_snapshot_codec.gd"
)
const DAMAGE_EVENT_SCRIPT := preload(
	"res://scripts/destruction/damage_event.gd"
)

const HOST_RPC_ID = 1
const PLAYER_PROXY_SCENE := preload("res://scenes/proxy/player_proxy.tscn")
const ITEM_PROXY_SCENE := preload("res://scenes/proxy/item_proxy.tscn")
const DRONE_PROXY_SCENE := preload("res://scenes/proxy/drone_proxy.tscn")
const PROJECTILE_PROXY_SCENE := preload(
	"res://scenes/proxy/projectile_proxy.tscn"
)
const DRONE_PART_PROXY_SCENE := preload(
	"res://scenes/proxy/drone_part_proxy.tscn"
)
const ROPE_PROXY_SCENE := preload("res://scenes/proxy/rope_proxy.tscn")
const ENEMY_PROXY_SCENE := preload("res://scenes/proxy/enemy_proxy.tscn")
const PLAYER_CORPSE_PROXY := preload(
	"res://scripts/client/player_corpse_proxy.gd"
)
const DESTRUCTION_FRAGMENT_PROXY := preload(
	"res://scripts/client/destruction_fragment_proxy.gd"
)
const CLIENT_WORLD_SCENE := preload("res://scenes/proxy/world.tscn")
const USE_HOLD_SECONDS := 0.5
const MAX_GRAB_ROTATION_INPUT_TARGET := 1000000.0
const FIELDLINK_MAX_SCANNER_CONTACTS := 24
const LISTENER_ACTIVITY := preload(
	"res://scripts/audio/listener_acoustic_activity.gd"
)
const REPLICATION_SCHEDULE := preload(
	"res://scripts/network/network_replication_schedule.gd"
)
const STEAM_VOICE_CAPTURE := preload(
	"res://scripts/voice/steam_voice_capture.gd"
)
const SPATIAL_VOICE_CHAT_RENDERER := preload(
	"res://scripts/voice/spatial_voice_chat_renderer.gd"
)

signal spatial_sound_received(packet: Dictionary)
signal acoustic_perception_event_rendered(packet: Dictionary)
signal acoustic_perception_continuous_sample(
	source_id: int,
	apparent_position: Vector3,
	received_intensity: float,
	band_gain: Vector3,
	enclosure: float
)
signal voice_speaking_state_changed(
	player_id: int,
	generation: int,
	active: bool
)
signal voice_mimic_consent_changed(enabled: bool)

#######################################################
# Collects local input, sends player intents to the authority, and owns the lifecycle of
# replicated client-side proxies.
#######################################################

var item_proxies_by_item_id: Dictionary[int, ItemProxy] = {}
var item_spawn_queue: Array[Dictionary] = []
var player_proxys_by_player_id: Dictionary[int, PlayerProxy] = {}
var pending_player_inventory_by_player_id: Dictionary[int, Dictionary] = {}
var drone_proxies_by_drone_id: Dictionary[int, Node3D] = {}
var projectile_proxies_by_id: Dictionary[int, ProjectileProxy] = {}
var drone_part_proxies_by_id: Dictionary[int, Node3D] = {}
var rope_proxies_by_rope_id: Dictionary[int, RopeProxy] = {}
var enemy_proxies_by_enemy_id: Dictionary[int, EnemyProxy] = {}
var player_corpse_proxies_by_id: Dictionary[int, Node3D] = {}
var destruction_fragment_proxies_by_id: Dictionary[int, Node3D] = {}
# Client is an autoload and may parse before a fresh clone has rebuilt global script-class caches.
# The runtime contract is deliberately structural at this boundary; the scene script still owns the
# strongly typed SDF internals.
var destructible_volumes_by_id: Dictionary = {}
var pending_destruction_events: Array[Dictionary] = []
var pending_destruction_checkpoints: Dictionary[StringName, Dictionary] = {}
var fieldlink_device_beacons: Array[Node3D] = []

var client_world: Node3D
var local_player_id := -1
var grab_rotation_mode_sent := false
var grab_rotation_input_target := Vector2.ZERO
var grab_rotation_session_id := 0
var use_hold_elapsed := 0.0
var use_hold_action_sent := false
var primary_action_held_sent := false
var wrist_input_suspended := false
var spatial_audio_renderer: SpatialAudioRenderer
var radio_audio_renderer: RadioAudioRenderer
var steam_voice_capture
var spatial_voice_chat_renderer
var voice_speaking_generation_by_player_id: Dictionary[int, int] = {}
var voice_speaking_by_player_id: Dictionary[int, bool] = {}
var local_voice_mimic_consent := false
var last_network_snapshot_sequence_by_stream: Dictionary[StringName, int] = {}
var local_audio_prediction_runtime := LOCAL_AUDIO_PREDICTION_RUNTIME.new()
var next_jump_request_id := 0


func reset_session() -> void:
	for child: Node in get_children():
		if (
			child == spatial_audio_renderer
			or child == radio_audio_renderer
			or child == steam_voice_capture
			or child == spatial_voice_chat_renderer
		):
			continue
		child.queue_free()

	if is_instance_valid(client_world):
		client_world.queue_free()
	client_world = null

	item_proxies_by_item_id.clear()
	item_spawn_queue.clear()
	player_proxys_by_player_id.clear()
	pending_player_inventory_by_player_id.clear()
	drone_proxies_by_drone_id.clear()
	projectile_proxies_by_id.clear()
	drone_part_proxies_by_id.clear()
	rope_proxies_by_rope_id.clear()
	enemy_proxies_by_enemy_id.clear()
	player_corpse_proxies_by_id.clear()
	destruction_fragment_proxies_by_id.clear()
	destructible_volumes_by_id.clear()
	pending_destruction_events.clear()
	pending_destruction_checkpoints.clear()
	fieldlink_device_beacons.clear()
	local_player_id = -1
	grab_rotation_mode_sent = false
	grab_rotation_input_target = Vector2.ZERO
	grab_rotation_session_id = 0
	use_hold_elapsed = 0.0
	use_hold_action_sent = false
	primary_action_held_sent = false
	wrist_input_suspended = false
	voice_speaking_generation_by_player_id.clear()
	voice_speaking_by_player_id.clear()
	local_voice_mimic_consent = false
	last_network_snapshot_sequence_by_stream.clear()
	local_audio_prediction_runtime.reset()
	next_jump_request_id = 0
	if is_instance_valid(spatial_audio_renderer):
		spatial_audio_renderer.reset_session(true)
	if is_instance_valid(radio_audio_renderer):
		radio_audio_renderer.reset_session()
	if is_instance_valid(steam_voice_capture):
		steam_voice_capture.reset_session()
	if is_instance_valid(spatial_voice_chat_renderer):
		spatial_voice_chat_renderer.reset_session()


func register_spatial_sound(
	sound_id: StringName,
	streams: Array[AudioStream],
	settings: Dictionary = {},
	owner_token := 0
) -> bool:
	_ensure_spatial_audio_renderer()
	return spatial_audio_renderer.register_sound(
		sound_id,
		streams,
		settings,
		owner_token
	)


func unregister_spatial_sound(
	sound_id: StringName,
	owner_token := 0
) -> void:
	if is_instance_valid(spatial_audio_renderer):
		spatial_audio_renderer.unregister_sound(sound_id, owner_token)


func get_listener_acoustic_intensity() -> float:
	var transient_intensity := (
		spatial_audio_renderer.get_listener_acoustic_intensity()
		if is_instance_valid(spatial_audio_renderer)
		else 0.0
	)
	var continuous_intensity := (
		radio_audio_renderer.get_listener_acoustic_intensity()
		if is_instance_valid(radio_audio_renderer)
		else 0.0
	)
	var world_intensity := LISTENER_ACTIVITY.combine_energy(
		transient_intensity,
		continuous_intensity
	)
	var voice_intensity: float = (
		spatial_voice_chat_renderer.get_listener_acoustic_intensity()
		if is_instance_valid(spatial_voice_chat_renderer)
		else 0.0
	)
	return LISTENER_ACTIVITY.combine_energy(world_intensity, voice_intensity)


func predict_local_player_sound(
	sound_id: StringName,
	source_position: Vector3,
	profile_value: Dictionary = {},
	prediction_key := 0
) -> int:
	_ensure_spatial_audio_renderer()
	return local_audio_prediction_runtime.predict(
		spatial_audio_renderer,
		sound_id,
		source_position,
		profile_value,
		prediction_key
	)


func register_fieldlink_device_beacon(beacon: Node3D) -> void:
	if is_instance_valid(beacon) and not fieldlink_device_beacons.has(beacon):
		fieldlink_device_beacons.append(beacon)


func unregister_fieldlink_device_beacon(beacon: Node3D) -> void:
	fieldlink_device_beacons.erase(beacon)


func collect_nearby_fieldlink_devices(
	origin: Vector3,
	listener_yaw: float,
	maximum_distance: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not origin.is_finite() or not is_finite(listener_yaw):
		return result
	var bounded_range := clampf(maximum_distance, 1.0, 100.0)
	var world_to_listener := Basis(Vector3.UP, listener_yaw).inverse()
	var seen_contact_ids: Dictionary[StringName, bool] = {}
	for item_proxy: ItemProxy in item_proxies_by_item_id.values():
		if not is_instance_valid(item_proxy):
			continue
		_append_fieldlink_contact(
			result,
			seen_contact_ids,
			item_proxy.build_fieldlink_contact(origin, bounded_range),
			origin,
			world_to_listener,
			bounded_range
		)
	for drone_id: int in drone_proxies_by_drone_id.keys():
		var drone_proxy := drone_proxies_by_drone_id[drone_id] as DroneProxy
		if not is_instance_valid(drone_proxy) or not drone_proxy.visible:
			continue
		_append_fieldlink_contact(
			result,
			seen_contact_ids,
			{
				"contact_id": StringName("worker:%d" % drone_id),
				"display_name": "DEPLOYED WORKER %03d" % drone_id,
				"device_class": &"WORKER",
				"status_text": (
					"ACTIVE  /  %02d%%" % roundi(drone_proxy.power_ratio * 100.0)
					if drone_proxy.activated
					else "STANDBY"
				),
				"world_position": drone_proxy.global_position,
				"signal_strength": 1.0,
			},
			origin,
			world_to_listener,
			bounded_range
		)
	for beacon_node: Node3D in fieldlink_device_beacons:
		if (
			not is_instance_valid(beacon_node)
			or not beacon_node.has_method("build_fieldlink_contact")
		):
			continue
		_append_fieldlink_contact(
			result,
			seen_contact_ids,
			beacon_node.call(
				"build_fieldlink_contact",
				origin,
				bounded_range
			) as Dictionary,
			origin,
			world_to_listener,
			bounded_range
		)
	result.sort_custom(_fieldlink_contact_distance_less)
	if result.size() > FIELDLINK_MAX_SCANNER_CONTACTS:
		result.resize(FIELDLINK_MAX_SCANNER_CONTACTS)
	return result


func collect_echolocation_targets(
	origin: Vector3,
	maximum_distance: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not origin.is_finite():
		return result
	var bounded_range := clampf(maximum_distance, 0.0, 32.0)
	var range_squared := bounded_range * bounded_range
	for item_proxy: ItemProxy in item_proxies_by_item_id.values():
		if (
			not is_instance_valid(item_proxy)
			or not item_proxy.visible
			or item_proxy.global_position.distance_squared_to(origin) > range_squared
		):
			continue
		result.append({
			"target_id": item_proxy.item_id,
			"world_position": item_proxy.global_position,
			"is_eyes": item_proxy.item_definition is EyeDefinition,
		})
	return result


static func _append_fieldlink_contact(
	result: Array[Dictionary],
	seen_contact_ids: Dictionary[StringName, bool],
	raw_contact: Dictionary,
	origin: Vector3,
	world_to_listener: Basis,
	maximum_distance: float
) -> void:
	if raw_contact.is_empty():
		return
	var contact_id := StringName(str(raw_contact.get("contact_id", "")))
	var world_position := SafeVariant.vector3_strict_or(
		raw_contact.get("world_position", Vector3.INF),
		Vector3.INF
	)
	if (
		contact_id.is_empty()
		or seen_contact_ids.has(contact_id)
		or not world_position.is_finite()
	):
		return
	var world_offset := world_position - origin
	var distance_squared := world_offset.length_squared()
	if distance_squared > maximum_distance * maximum_distance:
		return
	var distance_meters := sqrt(distance_squared)
	var contact := raw_contact.duplicate(false)
	contact["contact_id"] = contact_id
	# Keep the unrotated offset so the scanner renderer can follow player yaw
	# every frame without repeating device discovery or allocating a new list.
	contact["world_offset"] = world_offset
	contact["relative_position"] = world_to_listener * world_offset
	contact["distance_meters"] = distance_meters
	contact["signal_strength"] = clampf(
		SafeVariant.finite_float_or(
			raw_contact.get("signal_strength"),
			1.0
		) * lerpf(
			1.0,
			0.65,
			clampf(distance_meters / maximum_distance, 0.0, 1.0)
		),
		0.0,
		4.0
	)
	seen_contact_ids[contact_id] = true
	if result.size() < FIELDLINK_MAX_SCANNER_CONTACTS:
		result.append(contact)
		return
	var farthest_index := 0
	var farthest_distance := float(
		result[0].get("distance_meters", -INF)
	)
	for contact_index: int in range(1, result.size()):
		var candidate_distance := float(
			result[contact_index].get("distance_meters", -INF)
		)
		if candidate_distance > farthest_distance:
			farthest_distance = candidate_distance
			farthest_index = contact_index
	if distance_meters < farthest_distance:
		result[farthest_index] = contact


static func _fieldlink_contact_distance_less(
	left: Dictionary,
	right: Dictionary
) -> bool:
	return float(left.get("distance_meters", INF)) < float(
		right.get("distance_meters", INF)
	)


func _ensure_spatial_audio_renderer() -> void:
	if is_instance_valid(spatial_audio_renderer):
		return
	spatial_audio_renderer = SpatialAudioRenderer.new()
	spatial_audio_renderer.name = "SpatialAudioRenderer"
	add_child(spatial_audio_renderer)
	spatial_audio_renderer.foreground_transient_started.connect(
		_on_foreground_transient_started
	)
	spatial_audio_renderer.acoustic_perception_event_rendered.connect(
		_on_acoustic_perception_event_rendered
	)


func _on_foreground_transient_started(
	strength: float,
	received_volume_db: float
) -> void:
	if is_instance_valid(radio_audio_renderer):
		radio_audio_renderer.request_foreground_transient_space(
			strength,
			received_volume_db
		)


func _on_acoustic_perception_event_rendered(packet: Dictionary) -> void:
	acoustic_perception_event_rendered.emit(packet)


func _ensure_radio_audio_renderer() -> void:
	if is_instance_valid(radio_audio_renderer):
		return
	radio_audio_renderer = RadioAudioRenderer.new()
	radio_audio_renderer.name = "RadioAudioRenderer"
	add_child(radio_audio_renderer)
	radio_audio_renderer.acoustic_perception_sample.connect(
		_on_acoustic_perception_continuous_sample
	)


func _ensure_voice_runtime() -> void:
	if not is_instance_valid(steam_voice_capture):
		steam_voice_capture = STEAM_VOICE_CAPTURE.new()
		steam_voice_capture.name = "SteamVoiceCapture"
		add_child(steam_voice_capture)
		steam_voice_capture.speaking_changed.connect(
			_on_local_voice_speaking_changed
		)
		steam_voice_capture.frame_captured.connect(
			_on_local_voice_frame_captured
		)
	if not is_instance_valid(spatial_voice_chat_renderer):
		spatial_voice_chat_renderer = SPATIAL_VOICE_CHAT_RENDERER.new()
		spatial_voice_chat_renderer.name = "SpatialVoiceChatRenderer"
		add_child(spatial_voice_chat_renderer)


func _on_local_voice_speaking_changed(active: bool) -> void:
	if not _has_connected_multiplayer_peer():
		return
	Server.rpc_id(HOST_RPC_ID, "receive_voice_speaking", active)


func _on_local_voice_frame_captured(
	sequence: int,
	captured_msec: int,
	sample_rate: int,
	compressed: PackedByteArray
) -> void:
	if not _has_connected_multiplayer_peer():
		return
	Server.rpc_id(
		HOST_RPC_ID,
		"receive_voice_frame",
		sequence,
		captured_msec,
		sample_rate,
		compressed
	)


func _on_acoustic_perception_continuous_sample(
	source_id: int,
	apparent_position: Vector3,
	received_intensity: float,
	band_gain: Vector3,
	enclosure: float
) -> void:
	acoustic_perception_continuous_sample.emit(
		source_id,
		apparent_position,
		received_intensity,
		band_gain,
		enclosure
	)


@rpc("authority", "reliable", "call_local")
func spawn_client_world() -> void:
	if client_world != null:
		return

	client_world = CLIENT_WORLD_SCENE.instantiate()
	get_tree().current_scene.add_child(client_world)
	_index_client_destructible_volumes()
	_apply_pending_destruction_state()


func _index_client_destructible_volumes() -> void:
	destructible_volumes_by_id.clear()
	if client_world == null:
		return
	var candidates: Array[Node] = [client_world]
	candidates.append_array(client_world.find_children("*", "", true, false))
	for candidate: Node in candidates:
		if (
			not candidate.has_method("initialize_volume")
			or not candidate.has_method("bake_hash")
			or not candidate.has_method("apply_replicated_damage_event")
			or not candidate.has_method("apply_checkpoint")
		):
			continue
		var volume := candidate
		volume.call("initialize_volume")
		var volume_id := StringName(str(volume.get("volume_id")))
		if not volume_id.is_empty():
			destructible_volumes_by_id[volume_id] = volume


func _apply_pending_destruction_state() -> void:
	for volume_id: StringName in pending_destruction_checkpoints.keys():
		_apply_destruction_checkpoint(pending_destruction_checkpoints[volume_id])
	pending_destruction_checkpoints.clear()
	var queued_events := pending_destruction_events.duplicate(false)
	pending_destruction_events.clear()
	for packet: Dictionary in queued_events:
		_apply_destruction_event_packet(packet)

#####################################################
### PROCESSING
#####################################################
func _physics_process(delta: float) -> void:
	_ensure_voice_runtime()
	steam_voice_capture.set_session_available(
		_has_connected_multiplayer_peer()
	)
	if not _has_connected_multiplayer_peer():
		return

	var local_proxy := get_local_player_proxy()
	var yaw := 0.0
	var pitch := 0.0
	if local_proxy != null:
		yaw = local_proxy.look_yaw
		pitch = local_proxy.look_pitch
		local_proxy.advance_local_input_tick()

	var wrist_open := (
		local_proxy != null
		and local_proxy.is_wrist_interface_open()
	)
	_send_movement_input(yaw, pitch, local_proxy)
	_process_locomotion_action_input(local_proxy)
	if wrist_open:
		_suspend_gameplay_input(yaw, pitch, local_proxy)
		return
	wrist_input_suspended = false
	_process_action_input(delta, yaw, pitch, local_proxy)
	_process_grab_input(yaw, pitch, local_proxy)


func _has_connected_multiplayer_peer() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (
		peer != null
		and not peer is OfflineMultiplayerPeer
		and peer.get_connection_status()
		== MultiplayerPeer.CONNECTION_CONNECTED
	)


func _send_movement_input(
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	var move := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var wants_run := Input.is_action_pressed("run")
	if local_proxy != null:
		# The authority still owns collision, stamina, and the accepted gait sequence. Feeding the
		# already-sampled local intent into presentation removes one network round trip from the gait
		# clock, so the owner hears an impact on the same frame as its bob instead of after a snapshot.
		local_proxy.set_local_locomotion_input(move, wants_run)
	Server.rpc_id(
		HOST_RPC_ID,
		"receive_player_input",
		move,
		yaw,
		pitch,
		wants_run
	)


func _process_locomotion_action_input(local_proxy: PlayerProxy) -> void:
	if Input.is_action_just_pressed("jump"):
		var prediction_key := 0
		var flip_intent := 0
		var flip_run_committed := false
		var jump_request_id := _allocate_jump_request_id()
		if local_proxy != null and local_proxy.target_on_floor:
			prediction_key = predict_local_player_sound(
				PhysicalSurface.jump_sound_id(
					local_proxy.target_footstep_surface
				),
				local_proxy.global_position + Vector3.UP * 0.35
			)
		if local_proxy != null:
			flip_run_committed = local_proxy.has_local_flip_run_commitment()
			flip_intent = local_proxy.consume_buffered_flip_intent()
			local_proxy.predict_local_flip_takeoff(
				flip_intent,
				jump_request_id
			)
		Server.rpc_id(
			HOST_RPC_ID,
			"receive_jump",
			prediction_key,
			flip_intent,
			jump_request_id,
			flip_run_committed
		)
	if (
		local_proxy != null
		and InputMap.has_action(EyelessAcousticPerception.INPUT_ACTION)
		and Input.is_action_just_pressed(
			EyelessAcousticPerception.INPUT_ACTION
		)
	):
		request_echolocation_click(local_proxy)


func _allocate_jump_request_id() -> int:
	# Positive 31-bit IDs stay exactly representable across Variant/RPC boundaries. Wraparound is
	# harmless because at most one local jump request can be awaiting resolution at a time.
	next_jump_request_id = next_jump_request_id % 2147483646 + 1
	return next_jump_request_id


func request_echolocation_click(local_proxy: PlayerProxy = null) -> void:
	if not _has_connected_multiplayer_peer():
		return
	if local_proxy == null:
		local_proxy = get_local_player_proxy()
	if local_proxy == null:
		return
	var source_position := local_proxy.get_audio_listener_position()
	var prediction_key := predict_local_player_sound(
		EyelessAcousticPerception.MOUTH_CLICK_SOUND_ID,
		source_position
	)
	Server.rpc_id(
		HOST_RPC_ID,
		"request_echolocation_click",
		prediction_key
	)


func request_foot_contact(
	contact_sequence: int,
	side: int,
	local_prediction_key: int
) -> void:
	if not _has_connected_multiplayer_peer():
		return
	Server.rpc_id(
		HOST_RPC_ID,
		"receive_foot_contact",
		contact_sequence,
		side,
		local_prediction_key
	)


func _suspend_gameplay_input(
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	if wrist_input_suspended:
		return
	wrist_input_suspended = true
	use_hold_elapsed = 0.0
	use_hold_action_sent = false
	grab_rotation_input_target = Vector2.ZERO
	if local_proxy != null and local_proxy.inventory_hud != null:
		local_proxy.inventory_hud.set_hold_progress(0.0)
	Server.rpc_id(HOST_RPC_ID, "release_grab")
	if grab_rotation_mode_sent:
		grab_rotation_mode_sent = false
		Server.rpc_id(
			HOST_RPC_ID,
			"set_grab_rotation_active",
			false,
			grab_rotation_session_id
		)
	if primary_action_held_sent:
		primary_action_held_sent = false
		Server.rpc_id(
			HOST_RPC_ID,
			"set_primary_action_held",
			false,
			yaw,
			pitch
		)
	local_audio_prediction_runtime.stop_primary()


func set_wrist_interface_open(value: bool) -> void:
	if not _has_connected_multiplayer_peer():
		return
	var local_proxy := get_local_player_proxy()
	var prediction_key := 0
	if local_proxy != null:
		prediction_key = predict_local_player_sound(
			&"fieldlink_open" if value else &"fieldlink_close",
			local_proxy.get_wrist_sound_source_position()
		)
	Server.rpc_id(
		HOST_RPC_ID,
		"set_wrist_interface_open",
		value,
		prediction_key
	)


func set_wrist_display_page(page_value: Variant) -> void:
	if not _has_connected_multiplayer_peer():
		return
	Server.rpc_id(
		HOST_RPC_ID,
		"set_wrist_display_page",
		FIELDLINK_DISPLAY_STATE.sanitize_page(page_value)
	)


func request_wrist_device_sound(sound_id: StringName) -> void:
	if not _has_connected_multiplayer_peer():
		return
	var local_proxy := get_local_player_proxy()
	var prediction_key := 0
	if local_proxy != null:
		prediction_key = predict_local_player_sound(
			sound_id,
			local_proxy.get_wrist_sound_source_position()
		)
	Server.rpc_id(
		HOST_RPC_ID,
		"request_wrist_device_sound",
		sound_id,
		prediction_key
	)


func set_voice_mimic_consent(enabled: bool) -> void:
	if not _has_connected_multiplayer_peer():
		return
	Server.rpc_id(HOST_RPC_ID, "set_voice_mimic_consent", enabled)


func request_fieldlink_device_control(contact_value: StringName) -> void:
	if not _has_connected_multiplayer_peer():
		return
	var contact_id := FieldlinkDeviceControlPacket.sanitize_contact_id(
		contact_value
	)
	if contact_id.is_empty():
		return
	Server.rpc_id(
		HOST_RPC_ID,
		"request_fieldlink_device_control",
		contact_id
	)


func send_fieldlink_device_command(
	contact_value: StringName,
	action_value: StringName,
	payload_value: Dictionary
) -> void:
	if not _has_connected_multiplayer_peer():
		return
	var command := FieldlinkDeviceControlPacket.sanitize_command(
		contact_value,
		action_value,
		payload_value
	)
	if command.is_empty():
		return
	Server.rpc_id(
		HOST_RPC_ID,
		"send_fieldlink_device_command",
		command["contact_id"],
		command["action"],
		command["payload"]
	)


func _process_action_input(
	delta: float,
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	_process_use_input(delta, yaw, pitch, local_proxy)
	_process_inventory_input(local_proxy)
	if Input.is_action_just_pressed("reload_weapon"):
		Server.rpc_id(HOST_RPC_ID, "reload_selected_weapon")

	var primary_action_just_pressed := (
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_just_pressed("primary_action")
	)
	if primary_action_just_pressed:
		_ensure_spatial_audio_renderer()
		var prediction_session := local_audio_prediction_runtime.begin_primary(
			spatial_audio_renderer,
			local_proxy
		)
		Server.rpc_id(
			HOST_RPC_ID,
			"primary_action",
			yaw,
			pitch,
			prediction_session
		)

	var primary_action_held := (
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and Input.is_action_pressed("primary_action")
	)
	if primary_action_held:
		_ensure_spatial_audio_renderer()
		local_audio_prediction_runtime.update_primary(
			spatial_audio_renderer,
			delta,
			local_proxy
		)
	if primary_action_held != primary_action_held_sent:
		primary_action_held_sent = primary_action_held
		Server.rpc_id(
			HOST_RPC_ID,
			"set_primary_action_held",
			primary_action_held,
			yaw,
			pitch,
			local_audio_prediction_runtime.primary_session()
		)
		if not primary_action_held:
			local_audio_prediction_runtime.stop_primary()


func _process_grab_input(
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	if Input.is_action_just_pressed("grab"):
		var preferred_kick_side := (
			local_proxy.get_suggested_kick_side()
			if local_proxy != null
			else -1
		)
		var dropkick_tilt_input := (
			local_proxy.consume_dropkick_tilt_input()
			if local_proxy != null
			else 0.0
		)
		Server.rpc_id(
			HOST_RPC_ID,
			"begin_grab",
			yaw,
			pitch,
			preferred_kick_side,
			dropkick_tilt_input
		)

	if Input.is_action_just_released("grab"):
		Server.rpc_id(
			HOST_RPC_ID,
			"release_grab"
		)

	var wants_grab_rotation := (
		Input.is_action_pressed("grab")
		and Input.is_action_pressed("rotate_grabbed")
	)
	if wants_grab_rotation != grab_rotation_mode_sent:
		grab_rotation_mode_sent = wants_grab_rotation
		grab_rotation_input_target = Vector2.ZERO
		if wants_grab_rotation:
			grab_rotation_session_id += 1
		Server.rpc_id(
			HOST_RPC_ID,
			"set_grab_rotation_active",
			wants_grab_rotation,
			grab_rotation_session_id
		)

	if local_proxy == null:
		return
	var rotation_input := local_proxy.consume_grab_rotation_input()
	if wants_grab_rotation and not rotation_input.is_zero_approx():
		grab_rotation_input_target += rotation_input
		grab_rotation_input_target = Vector2(
			clampf(
				grab_rotation_input_target.x,
				-MAX_GRAB_ROTATION_INPUT_TARGET,
				MAX_GRAB_ROTATION_INPUT_TARGET
			),
			clampf(
				grab_rotation_input_target.y,
				-MAX_GRAB_ROTATION_INPUT_TARGET,
				MAX_GRAB_ROTATION_INPUT_TARGET
			)
		)
		Server.rpc_id(
			HOST_RPC_ID,
			"receive_grab_rotation_input",
			grab_rotation_session_id,
			grab_rotation_input_target
		)


func _process_use_input(
	delta: float,
	yaw: float,
	pitch: float,
	local_proxy: PlayerProxy
) -> void:
	if Input.is_action_just_pressed("use"):
		use_hold_elapsed = 0.0
		use_hold_action_sent = false

	if Input.is_action_pressed("use"):
		use_hold_elapsed += delta
		if (
			not use_hold_action_sent
			and use_hold_elapsed >= USE_HOLD_SECONDS
		):
			use_hold_action_sent = true
			Server.rpc_id(
				HOST_RPC_ID,
				"equip_item",
				yaw,
				pitch
			)

	var hud: PlayerInventoryHud
	if local_proxy != null:
		hud = local_proxy.inventory_hud
	if hud != null:
		hud.set_hold_progress(
			clampf(use_hold_elapsed / USE_HOLD_SECONDS, 0.0, 1.0)
			if Input.is_action_pressed("use")
			else 0.0
		)

	if Input.is_action_just_released("use"):
		if not use_hold_action_sent:
			Server.rpc_id(
				HOST_RPC_ID,
				"store_item_or_use",
				yaw,
				pitch
			)
		use_hold_elapsed = 0.0
		use_hold_action_sent = false


func _process_inventory_input(local_proxy: PlayerProxy) -> void:
	var selected_with_number_key := false
	for slot_index: int in range(PlayerInventoryRules.MAX_CAPACITY):
		if Input.is_action_just_pressed(
			"inventory_slot_%d" % (slot_index + 1)
		):
			Server.rpc_id(
				HOST_RPC_ID,
				"select_inventory_slot",
				slot_index
			)
			selected_with_number_key = true
			break

	# Wheel navigation is a backpack affordance, not a hidden replacement for the baseline single
	# pocket. Authority resolves the relative request against its current slot, so packet latency or a
	# recent inventory update cannot make the client calculate from a stale selected index.
	if (
		not selected_with_number_key
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and local_proxy != null
		and local_proxy.has_equipped_backpack()
	):
		var slot_step := (
			int(Input.is_action_just_pressed("inventory_slot_next"))
			- int(Input.is_action_just_pressed("inventory_slot_previous"))
		)
		if slot_step != 0:
			Server.rpc_id(
				HOST_RPC_ID,
				"cycle_inventory_slot",
				slot_step
			)

	if Input.is_action_just_pressed("drop_equipped_eyes"):
		Server.rpc_id(
			HOST_RPC_ID,
			"drop_equipment",
			PlayerInventoryRules.EYES_SLOT
		)
	elif Input.is_action_just_pressed("drop_inventory_item"):
		Server.rpc_id(HOST_RPC_ID, "drop_inventory_item")
	
func get_local_player_proxy() -> PlayerProxy:
	return player_proxys_by_player_id.get(
		local_player_id
	) as PlayerProxy

func process_item_spawn_queue() -> void:
	while not item_spawn_queue.is_empty():
		var state: Dictionary = item_spawn_queue.pop_front()
		var item_id: int = SafeVariant.integral_int_or(state.get("item_id", -1), -1)
		if item_id < 0:
			continue

		if item_proxies_by_item_id.has(item_id):
			continue

		var proxy: ItemProxy = ITEM_PROXY_SCENE.instantiate()
		add_child(proxy)

		proxy.global_position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
		proxy.global_rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)
		proxy.from_server_state(state)

		item_proxies_by_item_id[item_id] = proxy

func _public_state_dictionary(states: Dictionary, state_id: Variant) -> Dictionary:
	return SafeVariant.dictionary_copy(states.get(state_id, {}), false)


#####################################################
### RECEIVING SERVER STATE
#####################################################
@rpc("authority", "call_local", "reliable")
func set_local_player_id(player_id: int) -> void:
	local_player_id = player_id

	for existing_player_id in player_proxys_by_player_id:
		var proxy: PlayerProxy = (
			player_proxys_by_player_id[existing_player_id]
		)

		proxy.set_local_player(
			existing_player_id == local_player_id
		)
		if existing_player_id == local_player_id:
			proxy.apply_voice_mimic_consent(local_voice_mimic_consent)


@rpc("authority", "unreliable", "call_local", 5)
func on_spatial_sound_received(packet: Dictionary) -> void:
	var sanitized := AcousticEventPacket.sanitize(packet)
	if sanitized.is_empty():
		return
	spatial_sound_received.emit(sanitized)
	_ensure_spatial_audio_renderer()
	spatial_audio_renderer.submit(sanitized)


@rpc("authority", "unreliable_ordered", "call_local", 9)
func on_voice_frame_received(packet: Dictionary) -> void:
	_ensure_voice_runtime()
	spatial_voice_chat_renderer.submit(packet)


@rpc("authority", "call_local", "reliable", 9)
func on_voice_speaking_state_received(
	player_id: int,
	generation: int,
	active: bool
) -> void:
	if player_id < 0 or generation < 0:
		return
	var previous_generation := int(
		voice_speaking_generation_by_player_id.get(player_id, -1)
	)
	if generation < previous_generation:
		return
	voice_speaking_generation_by_player_id[player_id] = generation
	voice_speaking_by_player_id[player_id] = active
	voice_speaking_state_changed.emit(player_id, generation, active)


@rpc("authority", "call_local", "reliable", 9)
func on_voice_mimic_consent_received(enabled: bool) -> void:
	local_voice_mimic_consent = enabled
	var local_proxy := get_local_player_proxy()
	if local_proxy != null:
		local_proxy.apply_voice_mimic_consent(enabled)
	voice_mimic_consent_changed.emit(enabled)


@rpc("authority", "call_local", "reliable", 3)
func on_destruction_event_received(packet_value: Dictionary) -> void:
	var packet := packet_value.duplicate(false)
	if client_world == null:
		pending_destruction_events.append(packet)
		return
	_apply_destruction_event_packet(packet)


@rpc("authority", "call_local", "reliable", 3)
func on_destruction_checkpoint_received(checkpoint_value: Dictionary) -> void:
	var volume_id := StringName(str(checkpoint_value.get("volume_id", &"")))
	if volume_id.is_empty():
		return
	if client_world == null:
		_store_pending_destruction_checkpoint(volume_id, checkpoint_value)
		return
	_apply_destruction_checkpoint(checkpoint_value)


@rpc("authority", "call_local", "reliable", 3)
func on_destruction_fragment_spawned(packet_value: Dictionary) -> void:
	var packet := packet_value.duplicate(false)
	var fragment_id := SafeVariant.integral_int_or(packet.get("fragment_id", -1), -1)
	if fragment_id < 0:
		return
	var existing := destruction_fragment_proxies_by_id.get(fragment_id) as Node3D
	if existing != null:
		return
	var proxy := DESTRUCTION_FRAGMENT_PROXY.new() as Node3D
	if proxy == null:
		return
	add_child(proxy)
	if not bool(proxy.call("apply_spawn_packet", packet)):
		proxy.queue_free()
		return
	destruction_fragment_proxies_by_id[fragment_id] = proxy


@rpc("authority", "call_local", "reliable", 3)
func on_destruction_fragment_geometry_changed(packet_value: Dictionary) -> void:
	var packet := packet_value.duplicate(false)
	var fragment_id := SafeVariant.integral_int_or(packet.get("fragment_id", -1), -1)
	var proxy := destruction_fragment_proxies_by_id.get(fragment_id) as Node3D
	if proxy != null and proxy.has_method("apply_geometry_packet"):
		proxy.call("apply_geometry_packet", packet)


@rpc("authority", "call_local", "reliable", 3)
func on_destruction_fragment_removed(fragment_id: int) -> void:
	var proxy := destruction_fragment_proxies_by_id.get(fragment_id) as Node3D
	destruction_fragment_proxies_by_id.erase(fragment_id)
	if is_instance_valid(proxy):
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 4)
func on_destruction_fragment_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"destruction_fragments", states):
		return
	for fragment_id_value: Variant in states.keys():
		var fragment_id := int(fragment_id_value)
		var proxy := destruction_fragment_proxies_by_id.get(fragment_id) as Node3D
		if proxy == null:
			continue
		var state := _public_state_dictionary(states, fragment_id_value)
		if not state.is_empty():
			proxy.call("apply_server_state", state)
	var existing_ids := destruction_fragment_proxies_by_id.keys()
	for fragment_id_value: Variant in existing_ids:
		var fragment_id := int(fragment_id_value)
		if states.has(fragment_id):
			continue
		var proxy := destruction_fragment_proxies_by_id.get(fragment_id) as Node3D
		destruction_fragment_proxies_by_id.erase(fragment_id)
		if is_instance_valid(proxy):
			proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 8)
func on_grabbed_destruction_fragment_motion_states_received(states: Dictionary) -> void:
	# High-rate held motion is presentation-only. Reliable manifests and bulk snapshots remain the
	# lifecycle authority, so packet loss cannot create or delete salvage fragments.
	for fragment_id_value: Variant in states:
		var fragment_id := int(fragment_id_value)
		var proxy := destruction_fragment_proxies_by_id.get(fragment_id) as Node3D
		if proxy == null:
			continue
		var state := _public_state_dictionary(states, fragment_id_value)
		if not state.is_empty():
			proxy.call("apply_server_motion_state", state)


func _apply_destruction_event_packet(packet: Dictionary) -> void:
	var volume_id := StringName(str(packet.get("volume_id", &"")))
	var volume := destructible_volumes_by_id.get(volume_id) as Node
	if volume == null:
		_request_destruction_checkpoint(volume_id)
		return
	if int(packet.get("bake_hash", -1)) != int(volume.call("bake_hash")):
		_request_destruction_checkpoint(volume_id)
		return
	var event_value: Variant = packet.get("event", {})
	if not event_value is Dictionary:
		_request_destruction_checkpoint(volume_id)
		return
	var field: Variant = volume.get("field")
	if field == null:
		_request_destruction_checkpoint(volume_id)
		return
	var current_revision := int(field.get("revision"))
	var from_revision := int(packet.get("from_revision", -1))
	var to_revision := int(packet.get("to_revision", -1))
	var expected_checksum := int(packet.get("checksum", -1))
	# Reliable RPCs can overlap initial checkpoint delivery and reconnect recovery. An event already
	# covered by the local field is idempotent, while a same-revision checksum disagreement is real
	# divergence. Never replay an old event and turn an otherwise healthy client into a recovery loop.
	if to_revision <= current_revision:
		if to_revision == current_revision and int(field.call("checksum")) != expected_checksum:
			_request_destruction_checkpoint(volume_id)
		return
	if from_revision != current_revision or to_revision != from_revision + 1:
		_request_destruction_checkpoint(volume_id)
		return
	var result: Dictionary = volume.call(
		"apply_replicated_damage_event",
		DAMAGE_EVENT_SCRIPT.from_dict(event_value),
		from_revision
	)
	if (
		not bool(result.get("changed", false))
		or field == null
		or int(field.get("revision")) != to_revision
		or int(field.call("checksum")) != expected_checksum
	):
		_request_destruction_checkpoint(volume_id)


func _apply_destruction_checkpoint(checkpoint: Dictionary) -> void:
	var volume_id := StringName(str(checkpoint.get("volume_id", &"")))
	var volume := destructible_volumes_by_id.get(volume_id) as Node
	if volume == null:
		_store_pending_destruction_checkpoint(volume_id, checkpoint)
		return
	var field: Variant = volume.get("field")
	if field == null:
		_request_destruction_checkpoint(volume_id)
		return
	var checkpoint_revision := int(checkpoint.get("revision", -1))
	var checkpoint_checksum := int(checkpoint.get("checksum", -1))
	var current_revision := int(field.get("revision"))
	if checkpoint_revision < current_revision:
		return
	if (
		checkpoint_revision == current_revision
		and int(field.call("checksum")) == checkpoint_checksum
	):
		return
	var applied := bool(volume.call("apply_checkpoint", checkpoint))
	if (
		not applied
		or field == null
		or int(field.call("checksum")) != checkpoint_checksum
	):
		_request_destruction_checkpoint(volume_id)


func _store_pending_destruction_checkpoint(
	volume_id: StringName,
	checkpoint: Dictionary
) -> void:
	var existing: Dictionary = pending_destruction_checkpoints.get(volume_id, {})
	if (
		not existing.is_empty()
		and int(existing.get("revision", -1)) > int(checkpoint.get("revision", -1))
	):
		return
	pending_destruction_checkpoints[volume_id] = checkpoint.duplicate(true)


func _request_destruction_checkpoint(volume_id: StringName) -> void:
	if volume_id.is_empty() or not _has_connected_multiplayer_peer():
		return
	# A listen server receives the authoritative destruction event through Client's call_local RPC.
	# Asking peer 1 for recovery from peer 1 is forbidden for a call_remote server endpoint, and it
	# is unnecessary: both autoloads already live in this process. Use the exact same checkpoint
	# payload locally while remote clients retain the ordinary request/response path.
	if multiplayer.is_server():
		var checkpoint: Dictionary = Server.get_destruction_checkpoint(volume_id)
		if not checkpoint.is_empty():
			on_destruction_checkpoint_received(checkpoint)
		return
	Server.rpc_id(HOST_RPC_ID, "request_destruction_checkpoint", volume_id)


@rpc("authority", "unreliable_ordered", "call_local", 7)
func on_local_audio_prediction_context_received(context_value: Dictionary) -> void:
	local_audio_prediction_runtime.apply_context(context_value)


@rpc("authority", "call_local", "reliable", 3)
func on_local_audio_prediction_rejected(prediction_key: int) -> void:
	if is_instance_valid(spatial_audio_renderer):
		spatial_audio_renderer.reject_prediction(prediction_key)


@rpc("authority", "call_local", "reliable", 3)
func on_jump_request_resolved(
	request_id: int,
	jump_accepted: bool,
	accepted_flip_direction: int
) -> void:
	var local_proxy := get_local_player_proxy()
	if local_proxy == null:
		return
	local_proxy.resolve_local_jump_request(
		request_id,
		jump_accepted,
		accepted_flip_direction
	)


@rpc("authority", "unreliable_ordered", "call_local", 6)
func on_radio_states_received(payload: PackedByteArray) -> void:
	_apply_radio_state_payload(payload)


func _apply_radio_state_payload(payload: PackedByteArray) -> void:
	var states := RADIO_STATE_SNAPSHOT_CODEC.decode(payload)
	if states.is_empty() and not is_instance_valid(radio_audio_renderer):
		return
	_ensure_radio_audio_renderer()
	radio_audio_renderer.submit_snapshot(states)


@rpc("authority", "call_local", "reliable", 3)
func on_fieldlink_device_control_received(snapshot_value: Dictionary) -> void:
	var snapshot := FieldlinkDeviceControlPacket.sanitize_snapshot(snapshot_value)
	if snapshot.is_empty():
		return
	var local_proxy := player_proxys_by_player_id.get(local_player_id) as PlayerProxy
	if local_proxy != null:
		local_proxy.apply_fieldlink_device_control_snapshot(snapshot)


@rpc("authority", "call_local", "reliable", 3)
func on_player_wrist_state_received(packet_value: Dictionary) -> void:
	var packet := FIELDLINK_DISPLAY_STATE.sanitize_replication_packet(
		packet_value
	)
	if packet.is_empty():
		return
	var proxy := player_proxys_by_player_id.get(
		int(packet["player_id"])
	) as PlayerProxy
	if proxy != null:
		proxy.apply_replicated_wrist_state(
			bool(packet["open"]),
			packet["page"]
		)


@rpc("authority", "call_local", "reliable", 3)
func on_fieldlink_device_control_failed(
	contact_value: StringName,
	message: String
) -> void:
	var contact_id := FieldlinkDeviceControlPacket.sanitize_contact_id(
		contact_value
	)
	var local_proxy := player_proxys_by_player_id.get(local_player_id) as PlayerProxy
	if local_proxy != null and not contact_id.is_empty():
		local_proxy.apply_fieldlink_device_control_error(
			contact_id,
			message.left(80)
		)

@rpc("authority", "unreliable", "call_local", 8)
func on_item_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"items", states):
		return
	for item_id in states:
		var state: Dictionary = _public_state_dictionary(states, item_id)
		if state.is_empty():
			continue

		if not item_proxies_by_item_id.has(item_id):
			item_spawn_queue.append(state)
			continue

		item_proxies_by_item_id[item_id].from_server_state(state)

	process_item_spawn_queue()

	var existing_item_ids := item_proxies_by_item_id.keys()

	for item_id in existing_item_ids:
		if states.has(item_id):
			continue

		var proxy: ItemProxy = item_proxies_by_item_id[item_id]

		item_proxies_by_item_id.erase(item_id)
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 8)
func on_grabbed_item_motion_states_received(states: Dictionary) -> void:
	# This is a high-rate delta stream for already-known interactive items. Full 20 Hz item
	# snapshots remain the sole lifecycle authority, so a lost delta can neither spawn nor delete.
	for item_id: Variant in states:
		var proxy := item_proxies_by_item_id.get(item_id) as ItemProxy
		if proxy == null:
			continue
		var state := _public_state_dictionary(states, item_id)
		if not state.is_empty():
			proxy.from_server_motion_state(state)

@rpc("authority", "unreliable", "call_local", 1)
func on_player_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"players", states):
		return
	for player_id in states:
		var state: Dictionary = _public_state_dictionary(states, player_id)
		if state.is_empty():
			continue

		if not player_proxys_by_player_id.has(player_id):
			var proxy: PlayerProxy = PLAYER_PROXY_SCENE.instantiate()

			proxy.player_id = player_id
			proxy.is_local_player = (
				player_id == local_player_id
			)

			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			proxy.rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)

			if proxy.is_local_player:
				proxy.look_yaw = proxy.rotation.y

			add_child(proxy)
			player_proxys_by_player_id[player_id] = proxy
			if proxy.is_local_player:
				proxy.apply_voice_mimic_consent(
					local_voice_mimic_consent
				)
			var pending_inventory: Dictionary = (
				pending_player_inventory_by_player_id.get(player_id, {})
			)
			if not pending_inventory.is_empty():
				proxy.apply_replicated_inventory_state(
					int(pending_inventory.get("revision", -1)),
					pending_inventory.get("inventory", {})
				)
				pending_player_inventory_by_player_id.erase(player_id)

		var proxy: PlayerProxy = player_proxys_by_player_id[player_id]
		proxy.apply_server_state(state)

	var existing_player_ids := player_proxys_by_player_id.keys()

	for player_id in existing_player_ids:
		if states.has(player_id):
			continue

		var proxy: PlayerProxy = player_proxys_by_player_id[player_id]

		player_proxys_by_player_id.erase(player_id)
		pending_player_inventory_by_player_id.erase(player_id)
		proxy.queue_free()


@rpc("authority", "call_local", "reliable", 3)
func on_player_corpse_spawned(state: Dictionary) -> void:
	_apply_player_corpse_state(state)


@rpc("authority", "unreliable", "call_local", 4)
func on_player_corpse_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"player_corpses", states):
		return
	for corpse_id_value: Variant in states.keys():
		var state: Dictionary = _public_state_dictionary(states, corpse_id_value)
		if not state.is_empty():
			_apply_player_corpse_state(state)
	var existing_ids := player_corpse_proxies_by_id.keys()
	for corpse_id: int in existing_ids:
		if states.has(corpse_id):
			continue
		var proxy := player_corpse_proxies_by_id.get(corpse_id) as Node3D
		player_corpse_proxies_by_id.erase(corpse_id)
		if is_instance_valid(proxy):
			proxy.queue_free()


func _apply_player_corpse_state(state: Dictionary) -> void:
	var corpse_id := SafeVariant.integral_int_or(state.get("corpse_id"), -1)
	if corpse_id < 0:
		return
	var proxy := player_corpse_proxies_by_id.get(corpse_id) as Node3D
	if proxy == null:
		proxy = PLAYER_CORPSE_PROXY.new()
		proxy.name = "PlayerCorpse%d" % corpse_id
		add_child(proxy)
		player_corpse_proxies_by_id[corpse_id] = proxy
		var source_player_id := SafeVariant.integral_int_or(
			state.get("source_player_id"),
			-1
		)
		proxy.call(
			"initialize_from_player",
			player_proxys_by_player_id.get(source_player_id) as PlayerProxy,
			state
		)
		return
	proxy.call("apply_server_state", state)


@rpc("authority", "reliable", "call_local", 1)
func on_player_inventory_state_received(
	player_id_value: int,
	revision_value: int,
	inventory_value: Dictionary
) -> void:
	var player_id := maxi(player_id_value, -1)
	var revision := maxi(revision_value, -1)
	if player_id < 0 or revision < 0:
		return
	var proxy := player_proxys_by_player_id.get(player_id) as PlayerProxy
	if proxy != null:
		proxy.apply_replicated_inventory_state(revision, inventory_value)
		return
	var pending: Dictionary = pending_player_inventory_by_player_id.get(
		player_id,
		{}
	)
	if revision < int(pending.get("revision", -1)):
		return
	pending_player_inventory_by_player_id[player_id] = {
		"revision": revision,
		"inventory": inventory_value.duplicate(true),
	}
	
@rpc("authority", "unreliable", "call_local", 2)
func on_drone_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"drones", states):
		return
	for drone_id in states:
		var state: Dictionary = _public_state_dictionary(states, drone_id)
		if state.is_empty():
			continue

		if not drone_proxies_by_drone_id.has(drone_id):
			var proxy := DRONE_PROXY_SCENE.instantiate() as Node3D
			if proxy == null:
				push_error("Drone proxy scene root must inherit Node3D")
				continue

			proxy.set("drone_id", drone_id)
			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			proxy.rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)
			add_child(proxy)
			drone_proxies_by_drone_id[drone_id] = proxy

		drone_proxies_by_drone_id[drone_id].call(
			"apply_server_state",
			state
		)

	var existing_drone_ids := drone_proxies_by_drone_id.keys()
	for drone_id in existing_drone_ids:
		if states.has(drone_id):
			continue

		var proxy: Node3D = drone_proxies_by_drone_id[drone_id]
		drone_proxies_by_drone_id.erase(drone_id)
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 2)
func spawn_projectile_proxy(state: Dictionary) -> void:
	_upsert_projectile_proxy(state)


@rpc("authority", "unreliable", "call_local", 2)
func despawn_projectile_proxy(projectile_id: int) -> void:
	var proxy := projectile_proxies_by_id.get(
		projectile_id
	) as ProjectileProxy
	projectile_proxies_by_id.erase(projectile_id)
	if is_instance_valid(proxy):
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 2)
func on_projectile_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"projectiles", states):
		return
	for projectile_id_value: Variant in states.keys():
		var state: Dictionary = _public_state_dictionary(states, projectile_id_value)
		if state.is_empty():
			continue
		_upsert_projectile_proxy(state)

	var existing_ids := projectile_proxies_by_id.keys()
	for projectile_id_value: Variant in existing_ids:
		var projectile_id := int(projectile_id_value)
		if states.has(projectile_id):
			continue
		despawn_projectile_proxy(projectile_id)


func _upsert_projectile_proxy(state: Dictionary) -> void:
	var projectile_id: int = SafeVariant.integral_int_or(state.get("projectile_id", -1), -1)
	if projectile_id < 0:
		return
	var proxy := projectile_proxies_by_id.get(
		projectile_id
	) as ProjectileProxy
	if proxy == null:
		proxy = PROJECTILE_PROXY_SCENE.instantiate() as ProjectileProxy
		if proxy == null:
			return
		add_child(proxy)
		projectile_proxies_by_id[projectile_id] = proxy
	proxy.apply_server_state(state)
	if str(state.get("source_kind", "")) == "drone":
		var source_drone: Node3D = drone_proxies_by_drone_id.get(
			SafeVariant.integral_int_or(state.get("source_id", -1), -1)
		) as Node3D
		if source_drone != null:
			source_drone.call(
				"apply_projectile_muzzle_aim",
				SafeVariant.integral_int_or(state.get("source_slot", -1), -1),
				SafeVariant.vector3_strict_or(
					state.get(
						"launch_direction",
						state.get("velocity", Vector3.ZERO)
					),
					Vector3.ZERO
				)
			)


@rpc("authority", "unreliable", "call_local", 4)
func on_drone_part_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"drone_parts", states):
		return
	for part_id in states:
		var state: Dictionary = _public_state_dictionary(states, part_id)
		if state.is_empty():
			continue

		if not drone_part_proxies_by_id.has(part_id):
			var proxy := DRONE_PART_PROXY_SCENE.instantiate() as Node3D
			if proxy == null:
				push_error("Drone part proxy root must inherit Node3D")
				continue

			proxy.set("drone_part_id", part_id)
			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			proxy.rotation = SafeVariant.vector3_strict_or(state.get("rot", Vector3.ZERO), Vector3.ZERO)
			add_child(proxy)
			drone_part_proxies_by_id[part_id] = proxy

		drone_part_proxies_by_id[part_id].call(
			"apply_server_state",
			state
		)

	var existing_part_ids := drone_part_proxies_by_id.keys()
	for part_id in existing_part_ids:
		if states.has(part_id):
			continue

		var proxy: Node3D = drone_part_proxies_by_id[part_id]
		drone_part_proxies_by_id.erase(part_id)
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 4)
func on_rope_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"ropes", states):
		return
	for rope_id_value: Variant in states.keys():
		var rope_id := int(rope_id_value)
		var state: Dictionary = _public_state_dictionary(states, rope_id_value)
		if state.is_empty():
			continue
		if not rope_proxies_by_rope_id.has(rope_id):
			var proxy := ROPE_PROXY_SCENE.instantiate() as RopeProxy
			if proxy == null:
				push_error("Rope proxy scene root must inherit RopeProxy")
				continue
			proxy.rope_id = rope_id
			add_child(proxy)
			rope_proxies_by_rope_id[rope_id] = proxy
		rope_proxies_by_rope_id[rope_id].apply_server_state(state)

	var existing_rope_ids := rope_proxies_by_rope_id.keys()
	for rope_id: int in existing_rope_ids:
		if states.has(rope_id):
			continue
		var proxy: RopeProxy = rope_proxies_by_rope_id[rope_id]
		rope_proxies_by_rope_id.erase(rope_id)
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 4)
func on_enemy_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"enemies", states):
		return
	for enemy_id_value: Variant in states.keys():
		var enemy_id := int(enemy_id_value)
		var state: Dictionary = _public_state_dictionary(states, enemy_id_value)
		if state.is_empty():
			continue
		if not enemy_proxies_by_enemy_id.has(enemy_id):
			var proxy := ENEMY_PROXY_SCENE.instantiate() as EnemyProxy
			if proxy == null:
				push_error("Enemy proxy scene root must inherit EnemyProxy")
				continue
			proxy.enemy_id = enemy_id
			proxy.position = SafeVariant.vector3_strict_or(state.get("pos", Vector3.ZERO), Vector3.ZERO)
			add_child(proxy)
			enemy_proxies_by_enemy_id[enemy_id] = proxy
		enemy_proxies_by_enemy_id[enemy_id].apply_server_state(state)

	var existing_enemy_ids := enemy_proxies_by_enemy_id.keys()
	for enemy_id: int in existing_enemy_ids:
		if states.has(enemy_id):
			continue
		var proxy: EnemyProxy = enemy_proxies_by_enemy_id[enemy_id]
		enemy_proxies_by_enemy_id.erase(enemy_id)
		proxy.queue_free()


@rpc("authority", "unreliable", "call_local", 4)
func on_inspection_station_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"inspection_stations", states):
		return
	if client_world == null:
		return

	var station_nodes: Array[Node] = get_tree().get_nodes_in_group(
		"drone_inspection_station_proxies"
	)
	for station_node: Node in station_nodes:
		var station_id := int(station_node.get("station_id"))
		if states.has(station_id):
			station_node.call(
				"apply_server_state",
				_public_state_dictionary(states, station_id)
			)


@rpc("authority", "unreliable", "call_local", 4)
func on_body_part_shop_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"body_part_shop", states):
		return
	if client_world == null:
		return

	var terminal_nodes := get_tree().get_nodes_in_group(
		"body_part_shop_terminal_proxies"
	)
	for terminal_node: Node in terminal_nodes:
		var station_id := int(terminal_node.get("station_id"))
		if states.has(station_id):
			terminal_node.call(
				"apply_server_state",
				_public_state_dictionary(states, station_id)
			)


@rpc("authority", "unreliable", "call_local", 4)
func on_weapon_crafting_station_states_received(states: Dictionary) -> void:
	if not _accept_network_snapshot(&"weapon_crafting", states):
		return
	if client_world == null:
		return
	var station_nodes := get_tree().get_nodes_in_group(
		"weapon_crafting_station_proxies"
	)
	for station_node: Node in station_nodes:
		var station_id := int(station_node.get("station_id"))
		if states.has(station_id):
			station_node.call(
				"apply_server_state",
				_public_state_dictionary(states, station_id)
			)


func _accept_network_snapshot(
	stream_id: StringName,
	states: Dictionary
) -> bool:
	var snapshot_sequence := REPLICATION_SCHEDULE.read_snapshot_sequence(states)
	# Accept legacy servers and empty snapshots. An empty compatibility-format snapshot has no
	# entity carrying a sequence; its next scheduled complete replacement converges the stream.
	var last_sequence := int(last_network_snapshot_sequence_by_stream.get(
		stream_id,
		-1
	))
	if not REPLICATION_SCHEDULE.is_newer_snapshot(
		snapshot_sequence,
		last_sequence
	):
		return false
	if snapshot_sequence >= 0:
		last_network_snapshot_sequence_by_stream[stream_id] = snapshot_sequence
	return true
