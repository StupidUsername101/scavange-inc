extends Node

const SYNC_RATE := 0.05
const DEFAULT_MONEY := 1000
const SPATIAL_CELL_SIZE := 8.0
const SPATIAL_INTEREST_COMBAT := 1
const SPATIAL_INTEREST_AVOIDANCE := 2
const LOBBY_MEMBERSHIP_CHECK_ATTEMPTS := 4
const LOBBY_MEMBERSHIP_CHECK_DELAY := 0.15
const MIN_DIRECTION_LENGTH_SQUARED := 0.000001
const STEAM_APP_ID := 480
const DEFAULT_PLAYER_SPAWN_POSITION := Vector3(0.0, 5.0, 0.0)
const NO_ARMS_DEMO_PLAYER_ID := 2
const NO_LEGS_DEMO_PLAYER_ID := 3
const DEFAULT_DISTORTION_CENTER := Vector2(0.5, 0.5)
const DEFAULT_DISTORTION_PULSE_HZ := 7.0
const MIN_TOTAL_GRAB_FORCE := 0.001
const LOBBY_CREATE_TIMEOUT_SECONDS := 10.0
const LOBBY_JOIN_TIMEOUT_SECONDS := 10.0
const HOST_CONNECTION_TIMEOUT_SECONDS := 15.0
const PRIORITY_INTERACTION_CHECK_DISTANCE_SQUARED := 36.0
const FIELDLINK_CONTROL_RANGE_METERS := 36.0
const FIELDLINK_CONTROL_RANGE_TOLERANCE_METERS := 1.5
const FIELDLINK_COMMAND_COOLDOWN_MILLISECONDS := 40
const GRAB_AIM_ASSIST_HALF_EXTENT := 0.18
const GRAB_AIM_ASSIST_MAX_RESULTS := 16
const GRAB_AIM_ASSIST_LATERAL_SCORE := 2.5
# Independent rollback switches; each can be evaluated without removing the others.
const ENABLE_ACOUSTIC_STATIC_BAKE_CACHE := true
const ENABLE_ACOUSTIC_CUMULATIVE_TRANSMISSION := true
# Independent rollback for Valve-style first-order reflection taps. Transmission, propagation,
# pressure events, and the existing late room return are unchanged when this is false.
const ENABLE_ACOUSTIC_HYBRID_EARLY_REFLECTIONS := true
const ACOUSTIC_STATIC_BAKE_CACHE_PATH := (
	"user://acoustic_bakes/server_world_v1.sacb"
)
const STEAM_JOIN_COMMAND := preload(
	"res://scripts/network/steam_join_command.gd"
)
const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)
const MULTIPLAYER_CHANNELS := preload(
	"res://scripts/network/multiplayer_channel_contract.gd"
)
const REPLICATION_SCHEDULE := preload(
	"res://scripts/network/network_replication_schedule.gd"
)
const PHYSICAL_IMPACT_RESPONSE := preload(
	"res://scripts/audio/physical_impact_response.gd"
)
const LOCAL_AUDIO_PREDICTION := preload(
	"res://scripts/audio/local_audio_prediction.gd"
)
const RADIO_STATE_SNAPSHOT_CODEC := preload(
	"res://scripts/audio/radio_state_snapshot_codec.gd"
)
const STEAM_PRESENCE_CONNECT := "connect"
const STEAM_PRESENCE_STATUS := "status"
const STEAM_PRESENCE_GROUP := "steam_player_group"
const STEAM_PRESENCE_GROUP_SIZE := "steam_player_group_size"

const SERVER_WORLD_SCENE := preload("res://scenes/server/server_world.tscn")
const SERVER_PLAYER_SCENE := preload("res://scenes/server/server_player.tscn")
const SERVER_ITEM_SCENE := preload("res://scenes/server/server_item.tscn")
const SERVER_RADIO_SCENE := preload("res://scenes/server/server_radio.tscn")
const SERVER_DRONE_PART_SCENE := preload(
	"res://scenes/server/server_drone_part.tscn"
)
const FULL_BODY_LOADOUT := preload(
	"res://resources/character_loadouts/full_body.tres"
)
const NO_ARMS_LOADOUT := preload(
	"res://resources/character_loadouts/no_arms.tres"
)
const NO_LEGS_LOADOUT := preload(
	"res://resources/character_loadouts/no_legs.tres"
)

#######################################################
# Coordinates authoritative multiplayer state, world entities, interactions, Steam lobby flow,
# and replicated snapshots.
#######################################################

signal lobby_status_changed(message: String, is_error: bool)

enum LobbyState {
	IDLE,
	CREATING,
	HOSTING,
	JOINING,
	CONNECTING,
	CONNECTED,
}

var server_players_by_player_id: Dictionary[int, ServerPlayer] = {}
var server_items_by_item_id: Dictionary[int, ServerItem] = {}
var server_radios_by_item_id: Dictionary[int, ServerRadio] = {}
var server_speaker_clusters: Array[Node3D] = []
var fieldlink_control_targets_by_contact_id: Dictionary[StringName, Node3D] = {}
var server_drones_by_drone_id: Dictionary[int, ServerDrone] = {}
var server_projectiles_by_id: Dictionary[int, ServerProjectile] = {}
var server_drone_parts_by_id: Dictionary[int, RigidBody3D] = {}
var server_enemies_by_enemy_id: Dictionary[int, ServerEnemy] = {}
var inspection_stations_by_id: Dictionary[int, Node3D] = {}
var body_part_shop_terminals_by_id: Dictionary[int, Node3D] = {}
var weapon_crafting_stations_by_id: Dictionary[int, Node3D] = {}
var body_part_delivery_orders: Array[Dictionary] = []
var server_ropes_by_rope_id: Dictionary[int, ServerRope] = {}
var rope_ids_by_body_instance_id: Dictionary[int, Array] = {}
var rope_placements_by_player_id: Dictionary[int, Dictionary] = {}
var grab_states_by_grabber_id: Dictionary[int, GrabState] = {}
var spatial_hash: ServerSpatialHash3D = ServerSpatialHash3D.new(
	SPATIAL_CELL_SIZE
)
var spatial_interest_by_drone_id: Dictionary[int, int] = {}

var server_world: Node3D
var sync_timer := 0.0
var next_drone_id := 0
var next_projectile_id := 0
var next_drone_part_id := 0
var next_drone_part_token_id := 0
var next_rope_id := 0
var next_enemy_id := 0
var next_body_part_order_id := 0

var lobby_id := 0
var pending_lobby_id := 0
var lobby_owner_id := 0
var lobby_state := LobbyState.IDLE
var steam_available := false
var steam_peer: SteamMultiplayerPeer
var steam_init_status := -1
var steam_init_message := "Steam has not been initialized."
var lobby_operation_generation := 0
var session_teardown_active := false
var acoustic_service: ServerAcousticService
var next_spatial_sound_sequence := 0
var network_snapshot_sequence := 0
var item_motion_sequence := 0
var fieldlink_next_command_msec_by_player_id: Dictionary[int, int] = {}
var grab_aim_assist_shape := BoxShape3D.new()


func _ready() -> void:
	# This must happen before a SteamMultiplayerPeer creates any connection. GodotSteam snapshots
	# the project lane count into each SteamPacketPeer; undersized configurations silently fold
	# high channels onto lane 0, which lets call_local audio work for the host while remote audio
	# queues behind unrelated reliable world state.
	MULTIPLAYER_CHANNELS.ensure_runtime_capacity()
	# Forty tiny response resources are prepared once. Bullet impacts only perform a cache lookup;
	# automatic fire never allocates a new material modifier in the physics tick.
	PHYSICAL_IMPACT_RESPONSE.prewarm()
	acoustic_service = ServerAcousticService.new()
	acoustic_service.name = "ServerAcousticService"
	acoustic_service.configure_bake_cache(
		ENABLE_ACOUSTIC_STATIC_BAKE_CACHE,
		ACOUSTIC_STATIC_BAKE_CACHE_PATH
	)
	acoustic_service.configure_cumulative_static_transmission(
		ENABLE_ACOUSTIC_CUMULATIVE_TRANSMISSION
	)
	acoustic_service.configure_hybrid_early_reflections(
		ENABLE_ACOUSTIC_HYBRID_EARLY_REFLECTIONS
	)
	add_child(acoustic_service)

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.join_requested.connect(
		_on_join_requested
	)
	Steam.join_game_requested.connect(
		_on_join_game_requested
	)

	# Give Steamworks an app identity without depending on the caller's working directory. The
	# adjacent steam_appid.txt remains useful to external Steam tooling, but is no longer our only
	# source of truth when a tester moves the executable.
	OS.set_environment("SteamAppId", str(STEAM_APP_ID))
	OS.set_environment("SteamGameId", str(STEAM_APP_ID))
	# This node already pumps Steam.run_callbacks() below, so callbacks have one explicit owner.
	var init_response: Dictionary = Steam.steamInitEx(STEAM_APP_ID, false)
	steam_init_status = int(init_response.get("status", 1))
	steam_init_message = str(
		init_response.get("verbal", "Steam returned no initialization detail.")
	).strip_edges()
	var steam_client_running := Steam.isSteamRunning()
	var steam_user_logged_on := false
	var steam_user_id := 0
	# SteamUser is unavailable after a failed API initialization; do not turn a useful init response
	# into follow-on interface errors while collecting diagnostics.
	if steam_init_status == 0 and steam_client_running:
		steam_user_logged_on = Steam.loggedOn()
		steam_user_id = Steam.getSteamID()
	# A successful SteamAPI_Init is the availability boundary: all Steam interfaces have been
	# acquired at that point. BLoggedOn and the user ID are useful diagnostics, but they can lag
	# behind initialization while the client finishes restoring its online session. Treating either
	# as an initialization requirement made fast exported builds report Steam as unavailable even
	# though the same project connected after the editor's slower launch path.
	steam_available = steam_init_status == 0 and steam_client_running
	if steam_available:
		steam_init_message = "Steam connected."
	elif steam_init_status == 0:
		if not steam_client_running:
			steam_init_message = "Steam initialized, but its desktop client is not reachable."
		elif not steam_user_logged_on:
			steam_init_message = "Steam is reachable, but the account is offline."
		else:
			steam_init_message = "Steam connected without a valid user ID."
	if steam_available:
		_clear_lobby_presence()
		var launch_lobby_id := _get_launch_lobby_id()
		if launch_lobby_id > 0:
			call_deferred(
				"_request_external_lobby_join",
				launch_lobby_id
			)

	print("Steam init response: ", init_response)
	print("Steam running: ", steam_client_running)
	print("Steam logged on: ", steam_user_logged_on)
	print("Steam ID: ", steam_user_id if steam_available else 0)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	Steam.run_callbacks()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_update_grabber_loads()

	for player: ServerPlayer in server_players_by_player_id.values():
		player.server_physics_tick(delta)
		if player.wants_automatic_fire():
			var prediction_key := player.current_automatic_audio_prediction_key()
			if try_primary_action(player, prediction_key):
				player.advance_automatic_audio_prediction()
			else:
				_reject_local_audio_prediction(player, prediction_key)
		_update_player_edit_aim(player)

	for enemy: ServerEnemy in server_enemies_by_enemy_id.values():
		if is_instance_valid(enemy):
			enemy.server_physics_tick(delta)

	_update_spatial_hash_positions()

	for drone: ServerDrone in server_drones_by_drone_id.values():
		drone.server_physics_tick(delta)

	for projectile: ServerProjectile in server_projectiles_by_id.values():
		if is_instance_valid(projectile):
			projectile.server_physics_tick(delta)

	for rope: ServerRope in server_ropes_by_rope_id.values():
		if is_instance_valid(rope):
			rope.server_physics_tick(delta)

	_apply_grab_forces(delta)
	item_motion_sequence += 1
	_publish_grabbed_item_motion_states(item_motion_sequence)

	sync_timer -= delta
	if sync_timer > 0.0:
		return

	sync_timer = SYNC_RATE
	publish_states()


func publish_states() -> void:
	var snapshot_sequence := network_snapshot_sequence
	network_snapshot_sequence += 1
	_publish_player_states(snapshot_sequence)
	_publish_item_states(snapshot_sequence)
	_publish_drone_states(snapshot_sequence)
	_publish_projectile_states(snapshot_sequence)
	_publish_radio_states()
	if REPLICATION_SCHEDULE.is_due(
		snapshot_sequence,
		REPLICATION_SCHEDULE.LOCAL_AUDIO_CONTEXT_INTERVAL_TICKS
	):
		_publish_local_audio_prediction_contexts()
	if REPLICATION_SCHEDULE.is_due(
		snapshot_sequence,
		REPLICATION_SCHEDULE.BULK_PHYSICS_INTERVAL_TICKS
	):
		_publish_drone_part_states(snapshot_sequence)
		_publish_enemy_states(snapshot_sequence)
		_publish_rope_states(snapshot_sequence)
	if REPLICATION_SCHEDULE.is_due(
		snapshot_sequence,
		REPLICATION_SCHEDULE.STATION_INTERVAL_TICKS
	):
		_publish_station_states(snapshot_sequence)


func _publish_player_states(snapshot_sequence: int) -> void:
	var states: Dictionary = {}
	for player_id: int in server_players_by_player_id:
		var player := server_players_by_player_id[player_id]
		if not is_instance_valid(player):
			continue
		states[player_id] = _sequence_state(
			player.to_state_dict(),
			snapshot_sequence
		)
	Client.rpc("on_player_states_received", states)


func _publish_item_states(snapshot_sequence: int) -> void:
	var states: Dictionary = {}
	var grabber_player_ids := _grabbed_item_player_ids()
	for item_id: int in server_items_by_item_id:
		var item := server_items_by_item_id[item_id]
		if not is_instance_valid(item):
			continue
		var state := _sequence_state(item.to_state_dict(), snapshot_sequence)
		state["item_motion_sequence"] = item_motion_sequence
		state["grabber_player_id"] = int(grabber_player_ids.get(item_id, -1))
		states[item_id] = state
	Client.rpc("on_item_states_received", states)


func _publish_grabbed_item_motion_states(motion_sequence: int) -> void:
	if grab_states_by_grabber_id.is_empty():
		return
	var states: Dictionary = {}
	for grab_state: GrabState in grab_states_by_grabber_id.values():
		if (
			grab_state == null
			or not is_instance_valid(grab_state.grabber)
			or not is_instance_valid(grab_state.body)
			or not grab_state.body is ServerItem
		):
			continue
		var item := grab_state.body as ServerItem
		var state := item.to_motion_state_dict()
		state["item_motion_sequence"] = motion_sequence
		state["grabber_player_id"] = _grabber_player_id(grab_state.grabber)
		states[item.item_id] = state
	if not states.is_empty():
		# The listen-server presentation follows its authoritative body directly; only remote peers
		# need serialized interpolation deltas.
		for peer_id: int in multiplayer.get_peers():
			Client.rpc_id(
				peer_id,
				"on_grabbed_item_motion_states_received",
				states
			)


static func _grabber_player_id(grabber: GrabberComponent) -> int:
	if grabber == null or not is_instance_valid(grabber):
		return -1
	var carrier := grabber.get_carrier_body() as ServerPlayer
	return carrier.player_id if carrier != null else -1


func _grabbed_item_player_ids() -> Dictionary[int, int]:
	var result: Dictionary[int, int] = {}
	for grab_state: GrabState in grab_states_by_grabber_id.values():
		if (
			grab_state == null
			or not is_instance_valid(grab_state.grabber)
			or not is_instance_valid(grab_state.body)
			or not grab_state.body is ServerItem
		):
			continue
		var item := grab_state.body as ServerItem
		result[item.item_id] = _grabber_player_id(grab_state.grabber)
	return result


func _publish_drone_states(snapshot_sequence: int) -> void:
	var states: Dictionary = {}
	for drone_id: int in server_drones_by_drone_id:
		var drone: ServerDrone = server_drones_by_drone_id[drone_id]
		if not is_instance_valid(drone) or not drone.network_visible:
			continue
		states[drone_id] = _sequence_state(drone.to_state_dict(), snapshot_sequence)
	Client.rpc("on_drone_states_received", states)


func _publish_projectile_states(snapshot_sequence: int) -> void:
	var states: Dictionary = {}
	for projectile_id: int in server_projectiles_by_id:
		var projectile: ServerProjectile = server_projectiles_by_id[projectile_id]
		if is_instance_valid(projectile):
			states[projectile_id] = _sequence_state(
				projectile.to_state_dict(),
				snapshot_sequence
			)
	Client.rpc("on_projectile_states_received", states)


func _publish_drone_part_states(snapshot_sequence: int) -> void:
	var states: Dictionary = {}
	for part_id: int in server_drone_parts_by_id:
		var part := server_drone_parts_by_id[part_id]
		if is_instance_valid(part):
			states[part_id] = _sequence_state(
				part.call("to_state_dict") as Dictionary,
				snapshot_sequence
			)
	Client.rpc("on_drone_part_states_received", states)


func _publish_enemy_states(snapshot_sequence: int) -> void:
	var states: Dictionary = {}
	for enemy_id: int in server_enemies_by_enemy_id:
		var enemy: ServerEnemy = server_enemies_by_enemy_id[enemy_id]
		if is_instance_valid(enemy):
			states[enemy_id] = _sequence_state(
				enemy.to_state_dict(),
				snapshot_sequence
			)
	Client.rpc("on_enemy_states_received", states)


func _publish_rope_states(snapshot_sequence: int) -> void:
	var states: Dictionary = {}
	for rope_id: int in server_ropes_by_rope_id:
		var rope: ServerRope = server_ropes_by_rope_id[rope_id]
		if is_instance_valid(rope):
			states[rope_id] = _sequence_state(
				rope.to_state_dict(),
				snapshot_sequence
			)
	for player_id: int in rope_placements_by_player_id:
		var preview_state := _get_rope_placement_state(player_id)
		if not preview_state.is_empty():
			states[-player_id - 1] = _sequence_state(
				preview_state,
				snapshot_sequence
			)
	Client.rpc("on_rope_states_received", states)


func _publish_station_states(snapshot_sequence: int) -> void:
	var inspection_states: Dictionary = {}
	for station_id: int in inspection_stations_by_id:
		var station: Node3D = inspection_stations_by_id[station_id]
		if is_instance_valid(station):
			inspection_states[station_id] = _sequence_state(
				station.call("to_state_dict") as Dictionary,
				snapshot_sequence
			)
	Client.rpc("on_inspection_station_states_received", inspection_states)

	var body_shop_states: Dictionary = {}
	for terminal_id: int in body_part_shop_terminals_by_id:
		var terminal: Node3D = body_part_shop_terminals_by_id[terminal_id]
		if is_instance_valid(terminal):
			body_shop_states[terminal_id] = _sequence_state(
				terminal.call("to_state_dict") as Dictionary,
				snapshot_sequence
			)
	Client.rpc("on_body_part_shop_states_received", body_shop_states)

	var weapon_states: Dictionary = {}
	for station_id: int in weapon_crafting_stations_by_id:
		var weapon_station: Node3D = weapon_crafting_stations_by_id[station_id]
		if is_instance_valid(weapon_station):
			weapon_states[station_id] = _sequence_state(
				weapon_station.call("to_state_dict") as Dictionary,
				snapshot_sequence
			)
	Client.rpc("on_weapon_crafting_station_states_received", weapon_states)


static func _sequence_state(state: Dictionary, snapshot_sequence: int) -> Dictionary:
	state["network_snapshot_sequence"] = snapshot_sequence
	return state


func _publish_radio_states() -> void:
	for player_id: int in server_players_by_player_id:
		var listener := server_players_by_player_id[player_id]
		if not is_instance_valid(listener):
			continue
		var player_state := GameState.get_player_state(player_id)
		if (
			player_state == null
			or not _is_rpc_peer_reachable(player_state.peer_id)
		):
			continue
		var radio_states: Dictionary = {}
		var listener_position := listener.get_audio_listener_position()
		for radio_id: int in server_radios_by_item_id:
			var radio: ServerRadio = server_radios_by_item_id[radio_id]
			if not is_instance_valid(radio) or not radio.powered:
				continue
			var state := radio.build_listener_state(
				player_id,
				listener_position,
				acoustic_service,
				listener.get_rid()
			)
			if not state.is_empty():
				radio_states[radio.item_id] = state
		for cluster: Node3D in server_speaker_clusters:
			if (
				not is_instance_valid(cluster)
				or not cluster.has_method("append_listener_states")
			):
				continue
			cluster.call(
				"append_listener_states",
				radio_states,
				player_id,
				listener_position,
				acoustic_service,
				listener.get_rid()
			)
		var payload := RADIO_STATE_SNAPSHOT_CODEC.encode(radio_states)
		if payload.is_empty():
			push_warning(
				"Continuous audio snapshot exceeded its bounded wire contract"
			)
			continue
		# Every continuous state, including starts and stops, uses one replaceable ordered lane.
		# A second reliable lane can overtake these snapshots and re-excite an already populated
		# room return with stale program state. At 20 Hz, a lost transition heals on the next tick.
		Client.rpc_id(
			player_state.peer_id,
			"on_radio_states_received",
			payload
		)


func _publish_local_audio_prediction_contexts() -> void:
	if not LOCAL_AUDIO_PREDICTION.ENABLED:
		return
	for player_id: int in server_players_by_player_id:
		var listener := server_players_by_player_id[player_id]
		if not is_instance_valid(listener):
			continue
		var player_state := GameState.get_player_state(player_id)
		if (
			player_state == null
			or not _is_rpc_peer_reachable(player_state.peer_id)
		):
			continue
		var context := acoustic_service.build_local_prediction_context(
			player_id,
			listener.get_audio_listener_position(),
			listener.get_rid()
		)
		if context.is_empty():
			continue
		Client.rpc_id(
			player_state.peer_id,
			"on_local_audio_prediction_context_received",
			context
		)


func spawn_server_world() -> void:
	if server_world != null:
		return

	server_world = SERVER_WORLD_SCENE.instantiate()
	add_child(server_world)
	acoustic_service.bind_world(server_world)

	print("spawned server world: ", server_world.get_path())


func register_peer(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	if GameState.get_player_id(peer_id) != -1:
		return true

	if not LobbyRules.can_register_player(GameState.get_player_count()):
		return false

	spawn_server_world()

	var player_id := GameState.try_register_player(
		peer_id,
		DEFAULT_MONEY,
		LobbyRules.MAX_PLAYERS
	)

	if player_id == -1:
		return false

	if not server_players_by_player_id.has(player_id):
		spawn_server_player(
			player_id,
			DEFAULT_PLAYER_SPAWN_POSITION,
			null,
			_get_starting_body_loadout(player_id)
		)

	Client.rpc_id(
		peer_id,
		"set_local_player_id",
		player_id
	)

	Client.rpc_id(
		peer_id,
		"spawn_client_world"
	)

	print(
		"registered peer=",
		peer_id,
		" player_id=",
		player_id
	)
	_sync_lobby_availability()
	return true

func get_sending_player() -> ServerPlayer:
	var peer_id := multiplayer.get_remote_sender_id()

	if peer_id == 0:
		peer_id = multiplayer.get_unique_id()

	var player_id := GameState.get_player_id(peer_id)

	if player_id == -1:
		return null

	return server_players_by_player_id.get(
		player_id
	) as ServerPlayer


func _is_rpc_peer_reachable(peer_id: int) -> bool:
	if peer_id <= 0 or multiplayer.multiplayer_peer == null:
		return false
	# MultiplayerAPI.get_peers() intentionally excludes this process. The listen-server host is
	# nevertheless a valid call_local RPC recipient.
	if peer_id == multiplayer.get_unique_id():
		return true
	return multiplayer.get_peers().has(peer_id)


func _reject_local_audio_prediction(
	player: ServerPlayer,
	local_prediction_key: int
) -> void:
	var prediction_key := LOCAL_AUDIO_PREDICTION.sanitize_key(local_prediction_key)
	if player == null or prediction_key == 0:
		return
	var player_state := GameState.get_player_state(player.player_id)
	if (
		player_state == null
		or not _is_rpc_peer_reachable(player_state.peer_id)
	):
		return
	Client.rpc_id(
		player_state.peer_id,
		"on_local_audio_prediction_rejected",
		prediction_key
	)

func spawn_server_player(
	player_id: int,
	spawn_pos: Vector3,
	grab_capability: GrabCapability = null,
	body_loadout: CharacterLoadout = null
) -> void:
	if server_world == null:
		spawn_server_world()

	var p: ServerPlayer = SERVER_PLAYER_SCENE.instantiate()
	server_world.add_child(p)

	p.setup(player_id, spawn_pos)

	if grab_capability != null:
		p.set_grab_capability(grab_capability)

	if body_loadout != null:
		p.set_body_loadout(body_loadout)

	server_players_by_player_id[player_id] = p
	spatial_hash.register_entity(
		_get_player_spatial_key(player_id),
		p,
		&"player",
		player_id
	)

	print("spawned server player=", player_id, " at ", spawn_pos)


func _get_starting_body_loadout(player_id: int) -> CharacterLoadout:
	match player_id:
		# i disabled this because it makes debugging difficult. 
		#NO_ARMS_DEMO_PLAYER_ID:
			#return NO_ARMS_LOADOUT
		#NO_LEGS_DEMO_PLAYER_ID:
			#return NO_LEGS_LOADOUT
		_:
			return FULL_BODY_LOADOUT


func register_item(item_id: int, item: ServerItem) -> void:
	server_items_by_item_id[item_id] = item
	if (
		item.has_method("build_fieldlink_control_snapshot")
		and item.has_method("apply_fieldlink_command")
	):
		register_fieldlink_control_target(
			StringName("item:%d" % item_id),
			item
		)
	var radio := item as ServerRadio
	if radio != null:
		server_radios_by_item_id[item_id] = radio


func unregister_item(item_id: int) -> void:
	var item := get_server_item(item_id)
	if item != null:
		_release_grabs_for_body(item)
		_remove_ropes_for_body(item)
		_cancel_rope_placements_using_body(item)
	if acoustic_service != null and server_radios_by_item_id.has(item_id):
		acoustic_service.forget_continuous_source(item_id)

	server_items_by_item_id.erase(item_id)
	server_radios_by_item_id.erase(item_id)
	unregister_fieldlink_control_target(StringName("item:%d" % item_id))


func get_server_item(item_id: int) -> ServerItem:
	return server_items_by_item_id.get(item_id) as ServerItem


func _resolve_fieldlink_control_target(contact_id: StringName) -> Node3D:
	var target := fieldlink_control_targets_by_contact_id.get(contact_id) as Node3D
	if not is_instance_valid(target):
		fieldlink_control_targets_by_contact_id.erase(contact_id)
		return null
	return target


func register_fieldlink_control_target(
	contact_id: StringName,
	target: Node3D
) -> bool:
	var sanitized_id := FieldlinkDeviceControlPacket.sanitize_contact_id(
		contact_id
	)
	if sanitized_id.is_empty() or not is_instance_valid(target):
		return false
	fieldlink_control_targets_by_contact_id[sanitized_id] = target
	return true


func unregister_fieldlink_control_target(contact_id: StringName) -> void:
	fieldlink_control_targets_by_contact_id.erase(contact_id)


func register_speaker_cluster(cluster: Node3D) -> void:
	if is_instance_valid(cluster) and not server_speaker_clusters.has(cluster):
		server_speaker_clusters.append(cluster)


func unregister_speaker_cluster(cluster: Node3D) -> void:
	server_speaker_clusters.erase(cluster)


func _fieldlink_control_target_world_position(target: Node3D) -> Vector3:
	if target == null:
		return Vector3.ZERO
	if target.has_method("get_fieldlink_control_world_position"):
		var position_value: Variant = target.call(
			"get_fieldlink_control_world_position"
		)
		if position_value is Vector3:
			var control_position := position_value as Vector3
			if control_position.is_finite():
				return control_position
	return target.global_position


func _validate_fieldlink_control_target(
	player: ServerPlayer,
	contact_id: StringName
) -> Node3D:
	if (
		player == null
		or not player.wrist_interface_open
		or not player.has_equipped_wrist_device()
	):
		return null
	var target := _resolve_fieldlink_control_target(contact_id)
	if (
		not is_instance_valid(target)
		or not target.has_method("build_fieldlink_control_snapshot")
		or not target.has_method("apply_fieldlink_command")
	):
		return null
	var maximum_distance := (
		FIELDLINK_CONTROL_RANGE_METERS
		+ FIELDLINK_CONTROL_RANGE_TOLERANCE_METERS
	)
	if (
		player.global_position.distance_squared_to(
			_fieldlink_control_target_world_position(target)
		)
		> maximum_distance * maximum_distance
	):
		return null
	return target


func _send_fieldlink_control_snapshot(
	player: ServerPlayer,
	contact_id: StringName,
	target: Node3D
) -> void:
	var snapshot_value: Variant = target.call(
		"build_fieldlink_control_snapshot",
		player
	)
	if not snapshot_value is Dictionary:
		_send_fieldlink_control_error(player, contact_id, "CONTROL LINK UNAVAILABLE")
		return
	var snapshot := (snapshot_value as Dictionary).duplicate(true)
	snapshot["contact_id"] = contact_id
	snapshot = FieldlinkDeviceControlPacket.sanitize_snapshot(snapshot)
	if snapshot.is_empty():
		_send_fieldlink_control_error(player, contact_id, "INVALID DEVICE RESPONSE")
		return
	var player_state := GameState.get_player_state(player.player_id)
	if (
		player_state != null
		and _is_rpc_peer_reachable(player_state.peer_id)
	):
		Client.rpc_id(
			player_state.peer_id,
			"on_fieldlink_device_control_received",
			snapshot
		)


func _send_fieldlink_control_error(
	player: ServerPlayer,
	contact_id: StringName,
	message: String
) -> void:
	if player == null:
		return
	var player_state := GameState.get_player_state(player.player_id)
	if (
		player_state != null
		and _is_rpc_peer_reachable(player_state.peer_id)
	):
		Client.rpc_id(
			player_state.peer_id,
			"on_fieldlink_device_control_failed",
			contact_id,
			message.left(80)
		)


func get_server_player(player_id: int) -> ServerPlayer:
	return server_players_by_player_id.get(player_id) as ServerPlayer


func register_drone(drone: ServerDrone) -> int:
	next_drone_id += 1
	server_drones_by_drone_id[next_drone_id] = drone
	spatial_hash.register_entity(
		_get_drone_spatial_key(next_drone_id),
		drone,
		&"drone",
		next_drone_id
	)
	return next_drone_id


func unregister_drone(drone_id: int) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		_release_grabs_for_body(drone)
		_remove_ropes_for_body(drone)

	server_drones_by_drone_id.erase(drone_id)
	spatial_interest_by_drone_id.erase(drone_id)
	spatial_hash.clear_query_cache(_get_combat_cache_key(drone_id))
	spatial_hash.clear_query_cache(_get_avoidance_cache_key(drone_id))
	spatial_hash.unregister_entity(_get_drone_spatial_key(drone_id))


func get_server_drone(drone_id: int) -> ServerDrone:
	return server_drones_by_drone_id.get(drone_id) as ServerDrone


func spawn_ballistic_projectile(
	profile: Dictionary,
	origin: Vector3,
	direction: Vector3,
	inherited_velocity := Vector3.ZERO,
	excluded_rids: Array = [],
	source_kind: StringName = &"unknown",
	source_id := -1,
	world_source: Node3D = null,
	source_slot := -1
) -> ServerProjectile:
	if (
		direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED
		or profile.is_empty()
	):
		return null
	var parent: Node = server_world
	if is_instance_valid(world_source) and world_source.get_parent() != null:
		parent = world_source.get_parent()
	if parent == null:
		spawn_server_world()
		parent = server_world

	next_projectile_id += 1
	var projectile := ServerProjectile.new()
	projectile.name = "ServerProjectile%d" % next_projectile_id
	parent.add_child(projectile)
	projectile.configure(
		next_projectile_id,
		profile,
		origin,
		direction,
		inherited_velocity,
		excluded_rids,
		source_kind,
		source_id,
		source_slot,
		Callable(self, "despawn_projectile")
	)
	server_projectiles_by_id[next_projectile_id] = projectile
	Client.rpc(
		"spawn_projectile_proxy",
		projectile.to_state_dict()
	)
	return projectile


func despawn_projectile(projectile_id: int) -> void:
	var projectile := get_server_projectile(projectile_id)
	server_projectiles_by_id.erase(projectile_id)
	Client.rpc("despawn_projectile_proxy", projectile_id)
	if is_instance_valid(projectile):
		projectile.queue_free()


func get_server_projectile(projectile_id: int) -> ServerProjectile:
	return server_projectiles_by_id.get(
		projectile_id
	) as ServerProjectile


func emit_spatial_sound(
	sound_id: StringName,
	source_position: Vector3,
	max_distance := 48.0,
	base_volume_db := 0.0,
	source_modifier: AcousticPathModifier = null,
	priority := 0.5,
	pressure_strength := -1.0,
	origin_player_id := -1,
	local_prediction_key := 0
) -> int:
	if (
		not multiplayer.is_server()
		or sound_id.is_empty()
		or not source_position.is_finite()
	):
		return -1
	next_spatial_sound_sequence += 1
	var sequence := next_spatial_sound_sequence
	var safe_max_distance := clampf(max_distance, 0.1, 10000.0)
	var safe_base_volume_db := clampf(base_volume_db, -80.0, 18.0)
	var level_scaled_max_distance := (
		AcousticPropagationGraph.level_scaled_hearing_distance(
			safe_max_distance,
			safe_base_volume_db
		)
	)
	var safe_priority := clampf(priority, 0.0, 1.0)
	var safe_prediction_key := LOCAL_AUDIO_PREDICTION.sanitize_key(
		local_prediction_key
	)
	var safe_origin_player_id := (
		origin_player_id
		if safe_prediction_key > 0
		and server_players_by_player_id.has(origin_player_id)
		else -1
	)
	var safe_pressure_strength := resolve_spatial_pressure_strength(
		pressure_strength,
		safe_max_distance,
		safe_base_volume_db,
		safe_priority
	)
	var prepared_pressure_emission: Dictionary = {}
	var source_attachment: AcousticSourceAttachment
	var effective_max_distance := 0.0
	for player_id: int in server_players_by_player_id.keys():
		var listener := server_players_by_player_id[player_id]
		if not is_instance_valid(listener):
			continue
		var listener_position := listener.get_audio_listener_position()
		if source_attachment == null:
			source_attachment = acoustic_service.create_source_attachment(
				source_position
			)
			effective_max_distance = (
				acoustic_service.source_hearing_distance_upper_bound(
				level_scaled_max_distance,
				source_position,
				0,
				[],
				source_attachment
				)
			)
		if listener_position.distance_squared_to(source_position) > (
			effective_max_distance * effective_max_distance
		):
			continue
		# Bake/snapshot the source side only when at least one listener can hear the event, then
		# reuse the same dictionary for every listener. No source response means no extra work.
		if (
			safe_pressure_strength > 0.0001
			and prepared_pressure_emission.is_empty()
		):
			prepared_pressure_emission = acoustic_service.create_pressure_emission(
				source_position,
				safe_pressure_strength,
				[],
				source_attachment
			)
		var listener_exclusions: Array[RID] = [listener.get_rid()]
		var result := acoustic_service.calculate_listener_result(
			player_id,
			listener_position,
			source_position,
			level_scaled_max_distance,
			source_modifier,
			AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
			false,
			listener_exclusions,
			0,
			safe_pressure_strength,
			prepared_pressure_emission,
			source_attachment
		)
		if not bool(result.get("audible", false)):
			continue
		var player_state := GameState.get_player_state(player_id)
		if (
			player_state == null
			or not _is_rpc_peer_reachable(player_state.peer_id)
		):
			continue
		result.erase("audible")
		result["version"] = AcousticEventPacket.VERSION
		result["sequence"] = sequence
		result["sound_id"] = sound_id
		result["volume_db"] = (
			float(result.get("volume_db", 0.0))
			+ safe_base_volume_db
		)
		var pressure_arrivals: Array = result.get("pressure_arrivals", [])
		for arrival_index: int in range(pressure_arrivals.size()):
			var arrival: Dictionary = pressure_arrivals[arrival_index]
			arrival["volume_db"] = clampf(
				SafeVariant.finite_float_or(arrival.get("volume_db"), 0.0)
				+ safe_base_volume_db,
				AcousticPathModifier.MIN_VOLUME_DB,
				AcousticPathModifier.MAX_VOLUME_DB
			)
			pressure_arrivals[arrival_index] = arrival
		if not pressure_arrivals.is_empty():
			result["pressure_arrivals"] = pressure_arrivals
		result["priority"] = safe_priority
		if player_id == safe_origin_player_id:
			result["local_prediction_key"] = safe_prediction_key
		Client.rpc_id(
			player_state.peer_id,
			"on_spatial_sound_received",
			result
		)
	return sequence


static func resolve_spatial_pressure_strength(
	requested_strength: float,
	max_distance: float,
	base_volume_db: float,
	priority: float
) -> float:
	return LOCAL_AUDIO_PREDICTION.resolve_pressure_strength(
		requested_strength,
		max_distance,
		base_volume_db,
		priority
	)


func rebuild_server_acoustics() -> void:
	if acoustic_service != null:
		acoustic_service.request_rebuild()


func get_acoustic_debug_state() -> Dictionary:
	return (
		acoustic_service.get_debug_state()
		if acoustic_service != null
		else {}
	)


func register_enemy(enemy: ServerEnemy) -> int:
	if enemy == null:
		return -1
	next_enemy_id += 1
	server_enemies_by_enemy_id[next_enemy_id] = enemy
	if enemy.is_ai_targetable():
		set_enemy_spatial_active(next_enemy_id, true)
	return next_enemy_id


func unregister_enemy(enemy_id: int) -> void:
	server_enemies_by_enemy_id.erase(enemy_id)
	spatial_hash.unregister_entity(_get_enemy_spatial_key(enemy_id))


func set_enemy_spatial_active(enemy_id: int, active: bool) -> void:
	var enemy := get_server_enemy(enemy_id)
	var spatial_key := _get_enemy_spatial_key(enemy_id)
	if not active or not is_instance_valid(enemy):
		spatial_hash.unregister_entity(spatial_key)
		return
	spatial_hash.register_entity(
		spatial_key,
		enemy,
		&"enemy",
		enemy_id
	)


func get_server_enemy(enemy_id: int) -> ServerEnemy:
	return server_enemies_by_enemy_id.get(enemy_id) as ServerEnemy


func get_combat_target_body(
	target_kind: StringName,
	target_id: int
) -> Node3D:
	match target_kind:
		&"player":
			return get_server_player(target_id)
		&"drone":
			return get_server_drone(target_id)
		&"enemy":
			return get_server_enemy(target_id)
	return null


func allocate_drone_part_token_id() -> int:
	next_drone_part_token_id += 1
	return next_drone_part_token_id


func register_drone_part(part: RigidBody3D) -> int:
	next_drone_part_id += 1
	server_drone_parts_by_id[next_drone_part_id] = part
	return next_drone_part_id


func unregister_drone_part(part_id: int) -> void:
	var part := get_server_drone_part(part_id)
	if part != null:
		_release_grabs_for_body(part)
		_remove_ropes_for_body(part)
	server_drone_parts_by_id.erase(part_id)


func get_server_drone_part(part_id: int) -> RigidBody3D:
	return server_drone_parts_by_id.get(part_id) as RigidBody3D


func spawn_item(
	definition: ItemDefinition,
	item_transform: Transform3D
) -> ServerItem:
	if definition == null:
		return null
	if server_world == null:
		spawn_server_world()
	var item_scene := (
		SERVER_RADIO_SCENE
		if definition is RadioItemDefinition
		else SERVER_ITEM_SCENE
	)
	var item := item_scene.instantiate() as ServerItem
	item.definition = definition
	server_world.add_child(item)
	item.global_transform = item_transform
	return item


func spawn_item_from_entry(
	entry: Dictionary,
	item_transform: Transform3D
) -> ServerItem:
	var definition := PlayerInventoryRules.get_definition(entry)
	if definition == null:
		return null
	var item := spawn_item(definition, item_transform)
	if item != null:
		var instance_state: Dictionary = entry.get("instance_state", {})
		item.restore_instance_state(instance_state)
	return item


func register_inspection_station(
	station_id: int,
	station: Node3D
) -> void:
	if station_id < 0 or station == null:
		return
	inspection_stations_by_id[station_id] = station


func unregister_inspection_station(
	station_id: int,
	station: Node3D
) -> void:
	if inspection_stations_by_id.get(station_id) == station:
		inspection_stations_by_id.erase(station_id)


func register_body_part_shop_terminal(
	terminal_id: int,
	terminal: Node3D
) -> void:
	if terminal_id < 0 or terminal == null:
		return
	body_part_shop_terminals_by_id[terminal_id] = terminal


func unregister_body_part_shop_terminal(
	terminal_id: int,
	terminal: Node3D
) -> void:
	if body_part_shop_terminals_by_id.get(terminal_id) == terminal:
		body_part_shop_terminals_by_id.erase(terminal_id)


func register_weapon_crafting_station(
	station_id: int,
	station: Node3D
) -> void:
	if station_id < 0 or station == null:
		return
	weapon_crafting_stations_by_id[station_id] = station


func unregister_weapon_crafting_station(
	station_id: int,
	station: Node3D
) -> void:
	if weapon_crafting_stations_by_id.get(station_id) == station:
		weapon_crafting_stations_by_id.erase(station_id)


func get_active_player_ids() -> Array[int]:
	var result: Array[int] = []
	for player_id: int in server_players_by_player_id.keys():
		result.append(player_id)
	return result


func schedule_body_part_order(
	player_id: int,
	limb: LimbDefinition,
	terminal_id: int = -1
) -> Dictionary:
	if (
		get_server_player(player_id) == null
		or limb == null
		or not limb.shop_buyable
		or limb.resource_path.is_empty()
		or limb.shop_item_path.is_empty()
		or limb.shop_price < 0
	):
		return {
			"success": false,
			"message": "ORDER REJECTED // INVALID CATALOG ENTRY",
		}
	var delivery_item := load(limb.shop_item_path) as ItemDefinition
	if (
		delivery_item == null
		or not delivery_item is BodyPartItemDefinition
		or (delivery_item as BodyPartItemDefinition).limb_definition != limb
	):
		return {
			"success": false,
			"message": "ORDER REJECTED // FULFILLMENT ITEM UNAVAILABLE",
		}

	if not GameState.try_spend_player_money(player_id, limb.shop_price):
		return {
			"success": false,
			"message": "ORDER REJECTED // INSUFFICIENT CREDIT",
		}

	next_body_part_order_id += 1
	var order := {
		"order_id": next_body_part_order_id,
		"player_id": player_id,
		"terminal_id": terminal_id,
		"limb_path": limb.resource_path,
		"display_name": limb.display_name,
		"socket": int(limb.slot),
		"price": limb.shop_price,
		"quantity": 1,
		"status": "scheduled",
		"created_at_msec": Time.get_ticks_msec(),
	}
	body_part_delivery_orders.append(order)
	return {
		"success": true,
		"message": "ORDER #%04d SCHEDULED // %s" % [
			next_body_part_order_id,
			limb.display_name.to_upper(),
		],
		"order": order.duplicate(true),
	}


func get_body_part_orders_for_player(
	player_id: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order: Dictionary in body_part_delivery_orders:
		if int(order.get("player_id", -1)) == player_id:
			result.append(order.duplicate(true))
	return result


func get_scheduled_body_part_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order: Dictionary in body_part_delivery_orders:
		if str(order.get("status", "")) == "scheduled":
			result.append(order.duplicate(true))
	return result


func mark_body_part_order_delivered(order_id: int) -> bool:
	for order: Dictionary in body_part_delivery_orders:
		if int(order.get("order_id", -1)) != order_id:
			continue
		if str(order.get("status", "")) != "scheduled":
			return false
		order["status"] = "delivered"
		order["delivered_at_msec"] = Time.get_ticks_msec()
		return true
	return false


func spawn_drone_part(
	definition: DronePartDefinition,
	part_transform: Transform3D,
	battery_energy_wh := -1.0,
	core_health := -1.0,
	part_token_id := -1,
	broken := false
) -> RigidBody3D:
	if definition == null:
		return null
	if server_world == null:
		spawn_server_world()

	var part := SERVER_DRONE_PART_SCENE.instantiate() as RigidBody3D
	part.call(
		"configure",
		definition,
		battery_energy_wh,
		core_health,
		part_token_id,
		broken
	)
	server_world.add_child(part)
	part.global_transform = part_transform
	return part


func despawn_drone_part(part: RigidBody3D) -> void:
	if not is_instance_valid(part):
		return
	_release_grabs_for_body(part)
	part.queue_free()


func set_drone_core(
	drone_id: int,
	core: DroneCoreDefinition
) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.install_core(core)


func install_drone_battery(
	drone_id: int,
	battery: DroneBatteryDefinition
) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.install_battery(battery)


func remove_drone_battery(drone_id: int) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.remove_battery()


func install_drone_propeller(
	drone_id: int,
	slot_index: int,
	propeller: DronePropellerDefinition
) -> bool:
	var drone := get_server_drone(drone_id)
	if drone == null:
		return false

	return drone.install_propeller(slot_index, propeller)


func remove_drone_propeller(
	drone_id: int,
	slot_index: int
) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.remove_propeller(slot_index)


func install_drone_ai_chip(
	drone_id: int,
	slot_index: int,
	chip: DroneAIChipDefinition
) -> bool:
	var drone := get_server_drone(drone_id)
	if drone == null:
		return false
	return drone.install_ai_chip(slot_index, chip)


func remove_drone_ai_chip(drone_id: int, slot_index: int) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.remove_ai_chip(slot_index)


func install_drone_attachment(
	drone_id: int,
	slot_index: int,
	attachment: DroneAttachmentDefinition
) -> bool:
	var drone := get_server_drone(drone_id)
	if drone == null:
		return false
	return drone.install_attachment(slot_index, attachment)


func remove_drone_attachment(drone_id: int, slot_index: int) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.remove_attachment(slot_index)


func set_drone_ai_waypoint_plan(
	drone_id: int,
	points: Array[Vector3],
	loop := true
) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.set_ai_waypoint_plan(points, loop)


func set_drone_ai_guard_sphere(
	drone_id: int,
	center: Vector3,
	radius: float
) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.set_ai_guard_sphere(center, radius)


func set_drone_ai_follow_player(drone_id: int, player_id: int) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.set_ai_follow_player(player_id)


func clear_drone_ai_orders(drone_id: int) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.clear_ai_orders()


func set_drone_faction(drone_id: int, faction_id: int) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.faction_id = faction_id


func get_drone_ai_candidates(
	observer: ServerDrone,
	center: Vector3,
	maximum_range: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if observer == null or maximum_range <= 0.0:
		return result
	var target_kinds: Array[StringName] = [&"player", &"drone", &"enemy"]
	var keys := spatial_hash.query_keys(
		_get_combat_cache_key(observer.drone_id),
		center,
		maximum_range,
		target_kinds
	)
	var observer_key := _get_drone_spatial_key(observer.drone_id)
	var maximum_range_squared = maximum_range * maximum_range
	for entity_key: StringName in keys:
		if entity_key == observer_key:
			continue
		var record: Dictionary = spatial_hash.get_record(entity_key)
		var body := record.get("body") as Node3D
		if (
			record.is_empty()
			or not is_instance_valid(body)
			or center.distance_squared_to(body.global_position) > maximum_range_squared
		):
			continue
		var kind: StringName = record.get("kind", &"unknown")
		if kind == &"player":
			var player := body as ServerPlayer
			if player == null:
				continue
			result.append({
				"target_id": player.player_id,
				"kind": kind,
				"position": player.global_position,
				"velocity": player.velocity,
				"faction_id": player.faction_id,
			})
		elif kind == &"drone":
			var drone := body as ServerDrone
			if drone == null or drone.is_edit_preview:
				continue
			result.append({
				"target_id": drone.drone_id,
				"kind": kind,
				"position": drone.global_position,
				"velocity": drone.linear_velocity,
				"faction_id": drone.faction_id,
			})
		elif kind == &"enemy":
			var enemy := body as ServerEnemy
			if enemy == null:
				continue
			var snapshot := enemy.get_ai_target_snapshot()
			if not snapshot.is_empty():
				result.append(snapshot)
	return result


func get_drone_avoidance_neighbors(
	observer: ServerDrone,
	maximum_range: float,
	vertical_tolerance: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if observer == null or maximum_range <= 0.0:
		return result
	var drone_kinds: Array[StringName] = [&"drone"]
	var keys := spatial_hash.query_keys(
		_get_avoidance_cache_key(observer.drone_id),
		observer.global_position,
		maximum_range,
		drone_kinds
	)
	var observer_key := _get_drone_spatial_key(observer.drone_id)
	var maximum_range_squared = maximum_range * maximum_range
	for entity_key: StringName in keys:
		if entity_key == observer_key:
			continue
		var record: Dictionary = spatial_hash.get_record(entity_key)
		var drone := record.get("body") as ServerDrone
		if (
			drone == null
			or not is_instance_valid(drone)
			or drone.is_edit_preview
			or absf(drone.global_position.y - observer.global_position.y)
			> vertical_tolerance
		):
			continue
		var horizontal_offset := Vector2(
			drone.global_position.x - observer.global_position.x,
			drone.global_position.z - observer.global_position.z
		)
		if horizontal_offset.length_squared() > maximum_range_squared:
			continue
		result.append({
			"entity_id": drone.drone_id,
			"position": Vector2(
				drone.global_position.x,
				drone.global_position.z
			),
			"velocity": Vector2(
				drone.linear_velocity.x,
				drone.linear_velocity.z
			),
			"radius": drone.get_ai_collision_radius(),
			# An equipped peer assumes its half of the maneuver. A drone
			# without a working ORCA chip remains passive, so the observer
			# must take full responsibility.
			"responsibility": (
				0.5
				if drone.is_collision_avoidance_operational()
				else 1.0
			),
			"distance_squared": horizontal_offset.length_squared(),
		})
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return float(left.get("distance_squared", INF)) < float(
				right.get("distance_squared", INF)
			)
	)
	return result


func set_drone_spatial_interest(
	drone_id: int,
	combat_enabled: bool,
	avoidance_enabled: bool
) -> void:
	if drone_id < 0:
		return
	var was_active := not spatial_interest_by_drone_id.is_empty()
	var previous_mask := int(spatial_interest_by_drone_id.get(drone_id, 0))
	var next_mask := 0
	if combat_enabled:
		next_mask |= SPATIAL_INTEREST_COMBAT
	if avoidance_enabled:
		next_mask |= SPATIAL_INTEREST_AVOIDANCE
	if next_mask == 0:
		spatial_interest_by_drone_id.erase(drone_id)
	else:
		spatial_interest_by_drone_id[drone_id] = next_mask

	if (
		(previous_mask & SPATIAL_INTEREST_COMBAT) != 0
		and (next_mask & SPATIAL_INTEREST_COMBAT) == 0
	):
		spatial_hash.clear_query_cache(_get_combat_cache_key(drone_id))
	if (
		(previous_mask & SPATIAL_INTEREST_AVOIDANCE) != 0
		and (next_mask & SPATIAL_INTEREST_AVOIDANCE) == 0
	):
		spatial_hash.clear_query_cache(_get_avoidance_cache_key(drone_id))

	if not was_active and not spatial_interest_by_drone_id.is_empty():
		# The grid may have slept while nobody needed spatial work. Catch
		# every registered body up once without rebuilding the buckets.
		spatial_hash.refresh_all()


func get_spatial_hash_debug_state() -> Dictionary:
	var result := spatial_hash.get_debug_state()
	result["active_consumer_count"] = spatial_interest_by_drone_id.size()
	return result


func _update_spatial_hash_positions() -> void:
	if spatial_interest_by_drone_id.is_empty():
		return
	for player_id: int in server_players_by_player_id.keys():
		spatial_hash.update_entity(_get_player_spatial_key(player_id))
	for drone_id: int in server_drones_by_drone_id.keys():
		spatial_hash.update_entity(_get_drone_spatial_key(drone_id))
	for enemy_id: int in server_enemies_by_enemy_id.keys():
		spatial_hash.update_entity(_get_enemy_spatial_key(enemy_id))


func _get_player_spatial_key(player_id: int) -> StringName:
	return StringName("player:%d" % player_id)


func _get_drone_spatial_key(drone_id: int) -> StringName:
	return StringName("drone:%d" % drone_id)


func _get_enemy_spatial_key(enemy_id: int) -> StringName:
	return StringName("enemy:%d" % enemy_id)


func _get_combat_cache_key(drone_id: int) -> StringName:
	return StringName("combat:%d" % drone_id)


func _get_avoidance_cache_key(drone_id: int) -> StringName:
	return StringName("avoidance:%d" % drone_id)


func set_drone_activated(drone_id: int, active: bool) -> void:
	var drone := get_server_drone(drone_id)
	if drone != null:
		drone.set_activated(active)


func get_server_rope(rope_id: int) -> ServerRope:
	return server_ropes_by_rope_id.get(rope_id) as ServerRope


func detach_rope(rope_id: int) -> void:
	var rope := get_server_rope(rope_id)
	server_ropes_by_rope_id.erase(rope_id)
	if is_instance_valid(rope):
		_unindex_rope_body(rope.endpoint_a.body, rope_id)
		_unindex_rope_body(rope.endpoint_b.body, rope_id)
		rope.queue_free()


func break_rope(rope_id: int, _break_position: Vector3) -> void:
	detach_rope(rope_id)


func get_fiber_link_states_for_body(
	body: PhysicsBody3D
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if body == null:
		return result
	var rope_ids: Array = rope_ids_by_body_instance_id.get(
		body.get_instance_id(),
		[]
	)
	for rope_id_value: Variant in rope_ids:
		var rope := get_server_rope(int(rope_id_value))
		if not is_instance_valid(rope):
			continue
		var link_state := rope.get_fiber_link_state_for(body)
		if not link_state.is_empty():
			result.append(link_state)
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return float(left.get("signal_quality", 0.0)) > float(
				right.get("signal_quality", 0.0)
			)
	)
	return result


func get_rope_debug_state() -> Dictionary:
	var simulated_segment_count := 0
	var sleeping_rope_count := 0
	for rope: ServerRope in server_ropes_by_rope_id.values():
		if not is_instance_valid(rope):
			continue
		simulated_segment_count += maxi(rope.points.size() - 1, 0)
		if rope.simulation_sleeping:
			sleeping_rope_count += 1
	return {
		"rope_count": server_ropes_by_rope_id.size(),
		"placement_count": rope_placements_by_player_id.size(),
		"segment_count": simulated_segment_count,
		"sleeping_rope_count": sleeping_rope_count,
	}


func _try_rope_primary_action(
	player: ServerPlayer,
	held_body: RigidBody3D,
	hit: Dictionary
) -> bool:
	var spool := held_body as ServerItem
	var definition: RopeDefinition
	if spool != null:
		definition = spool.definition as RopeDefinition
	if definition == null:
		return false
	var target_body := hit.get("collider") as PhysicsBody3D
	if target_body == null or target_body.is_in_group("rope_knots"):
		return true
	var hit_position: Vector3 = hit.get("position", target_body.global_position)
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	var existing: Dictionary = rope_placements_by_player_id.get(
		player.player_id,
		{}
	)
	if existing.is_empty() or existing.get("spool") != spool:
		rope_placements_by_player_id[player.player_id] = {
			"spool": spool,
			"definition": definition,
			"endpoint": RopeEndpoint.new(
				target_body,
				hit_position,
				hit_normal,
				definition.get_radius()
			),
		}
		return true

	var endpoint_a := existing.get("endpoint") as RopeEndpoint
	if endpoint_a == null or not endpoint_a.is_valid():
		rope_placements_by_player_id.erase(player.player_id)
		return true
	if endpoint_a.body == target_body:
		return true
	var endpoint_b := RopeEndpoint.new(
		target_body,
		hit_position,
		hit_normal,
		definition.get_radius()
	)
	var direct_distance := endpoint_a.get_rope_position().distance_to(
		endpoint_b.get_rope_position()
	)
	if direct_distance > definition.maximum_length:
		return true
	var deployed_length := minf(
		direct_distance + definition.placement_slack,
		definition.maximum_length
	)
	next_rope_id += 1
	var rope := ServerRope.new()
	rope.name = "ServerRope%d" % next_rope_id
	server_world.add_child(rope)
	rope.configure(
		next_rope_id,
		definition,
		endpoint_a,
		endpoint_b,
		deployed_length
	)
	server_ropes_by_rope_id[next_rope_id] = rope
	_index_rope_body(endpoint_a.body, next_rope_id)
	_index_rope_body(endpoint_b.body, next_rope_id)
	rope_placements_by_player_id.erase(player.player_id)
	end_grab(player.grabber)
	spool.queue_free()
	return true


func _try_cancel_rope_placement(player: ServerPlayer) -> bool:
	if player == null or not rope_placements_by_player_id.has(player.player_id):
		return false
	var held_body := get_grabbed_body(player.grabber) as ServerItem
	if held_body == null:
		return false
	var definition := held_body.definition as RopeDefinition
	if definition == null:
		return false
	rope_placements_by_player_id.erase(player.player_id)
	return true


func _get_rope_placement_state(player_id: int) -> Dictionary:
	var placement: Dictionary = rope_placements_by_player_id.get(player_id, {})
	if placement.is_empty():
		return {}
	var spool := placement.get("spool") as ServerItem
	var definition := placement.get("definition") as RopeDefinition
	var endpoint := placement.get("endpoint") as RopeEndpoint
	if (
		spool == null
		or not is_instance_valid(spool)
		or definition == null
		or endpoint == null
		or not endpoint.is_valid()
	):
		rope_placements_by_player_id.erase(player_id)
		return {}
	var start := endpoint.get_rope_position()
	var end := spool.global_position
	return {
		"rope_id": -player_id - 1,
		"definition_path": definition.resource_path,
		"points": PackedVector3Array([start, end]),
		"preview": true,
		"valid": start.distance_to(end) <= definition.maximum_length,
		"deployed_length": minf(
			start.distance_to(end) + definition.placement_slack,
			definition.maximum_length
		),
		"path_length": start.distance_to(end),
		"tension_ratio": 0.0,
		"current_flow_w": 0.0,
		"current_direction": 0,
	}


func _remove_ropes_for_body(body: PhysicsBody3D) -> void:
	if body == null:
		return
	var rope_ids: Array = rope_ids_by_body_instance_id.get(
		body.get_instance_id(),
		[]
	).duplicate()
	for rope_id_value: Variant in rope_ids:
		detach_rope(int(rope_id_value))


func _index_rope_body(body: PhysicsBody3D, rope_id: int) -> void:
	if body == null:
		return
	var body_instance_id := body.get_instance_id()
	var rope_ids: Array = rope_ids_by_body_instance_id.get(
		body_instance_id,
		[]
	)
	if not rope_ids.has(rope_id):
		rope_ids.append(rope_id)
	rope_ids_by_body_instance_id[body_instance_id] = rope_ids


func _unindex_rope_body(body: PhysicsBody3D, rope_id: int) -> void:
	if body == null:
		return
	var body_instance_id := body.get_instance_id()
	var rope_ids: Array = rope_ids_by_body_instance_id.get(
		body_instance_id,
		[]
	)
	rope_ids.erase(rope_id)
	if rope_ids.is_empty():
		rope_ids_by_body_instance_id.erase(body_instance_id)
	else:
		rope_ids_by_body_instance_id[body_instance_id] = rope_ids


func _cancel_rope_placements_using_body(body: PhysicsBody3D) -> void:
	var player_ids_to_cancel: Array[int] = []
	for player_id: int in rope_placements_by_player_id.keys():
		var placement: Dictionary = rope_placements_by_player_id[player_id]
		var endpoint := placement.get("endpoint") as RopeEndpoint
		if placement.get("spool") == body or (
			endpoint != null and endpoint.body == body
		):
			player_ids_to_cancel.append(player_id)
	for player_id: int in player_ids_to_cancel:
		rope_placements_by_player_id.erase(player_id)


func _raycast_player_aim(player: ServerPlayer) -> Dictionary:
	if player == null:
		return {}

	var origin := player.grabber.get_grab_origin()
	var direction := player.grabber.get_grab_direction()
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * 4.0
	)
	query.exclude = [player.get_rid()]
	var held_body := get_grabbed_body(player.grabber)
	if held_body != null:
		query.exclude.append(held_body.get_rid())
	query.collide_with_areas = false
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _get_context_item(
	player: ServerPlayer,
	hit: Dictionary
) -> ServerItem:
	var held_item := get_grabbed_body(player.grabber) as ServerItem
	if held_item != null:
		return held_item
	return hit.get("collider") as ServerItem


func _release_warehouse_item(item: ServerItem) -> void:
	if item == null or not item.has_meta("dev_warehouse_owner"):
		return
	var warehouse := item.get_meta("dev_warehouse_owner") as Node
	if (
		warehouse != null
		and warehouse.has_method("release_socketed_part")
	):
		warehouse.call("release_socketed_part", item)


func _consume_world_item(item: ServerItem) -> void:
	if not is_instance_valid(item):
		return
	_release_warehouse_item(item)
	_release_grabs_for_body(item)
	item.queue_free()


func _get_player_drop_transform(
	player: ServerPlayer,
	offset_index := 0
) -> Transform3D:
	var forward = -Basis(Vector3.UP, player.look_yaw).z.normalized()
	var right := Basis(Vector3.UP, player.look_yaw).x.normalized()
	var side_offset := (
		float(posmod(offset_index, 3) - 1) * 0.38
	)
	var row := float(floori(float(offset_index) / 3.0))
	return Transform3D(
		Basis.IDENTITY,
		player.global_position
		+ Vector3.UP * (0.45 + row * 0.16)
		+ forward * (1.15 + row * 0.22)
		+ right * side_offset
	)


func _drop_entry_for_player(
	player: ServerPlayer,
	entry: Dictionary,
	offset_index := 0
) -> ServerItem:
	if player == null or entry.is_empty():
		return null
	var item := spawn_item_from_entry(
		entry,
		_get_player_drop_transform(player, offset_index)
	)
	if item != null:
		var forward = -Basis(Vector3.UP, player.look_yaw).z.normalized()
		item.linear_velocity = player.velocity + forward * 1.2
	return item


func _try_store_context_item(
	player: ServerPlayer,
	hit: Dictionary
) -> bool:
	var item := _get_context_item(player, hit)
	if item == null:
		return false
	var entry := item.to_inventory_entry()
	if not player.try_store_inventory_entry(entry):
		return true
	_consume_world_item(item)
	emit_spatial_sound(&"item_pickup", player.global_position, 22.0, 0.0, null, 0.35)
	return true


func try_store_item_or_use(player: ServerPlayer) -> void:
	if player == null:
		return
	if _try_cancel_rope_placement(player):
		return
	var hit := _raycast_player_aim(player)
	var aimed_collider := hit.get("collider") as Node
	if (
		aimed_collider != null
		and aimed_collider.has_method("server_use")
		and aimed_collider.has_method("prefers_server_use")
		and bool(aimed_collider.call("prefers_server_use"))
	):
		aimed_collider.call("server_use", player, hit)
		return
	if _try_store_context_item(player, hit):
		return
	_try_use_hit(player, hit)


func try_equip_item(player: ServerPlayer) -> void:
	if player == null:
		return
	var hit := _raycast_player_aim(player)
	var context_item := _get_context_item(player, hit)
	if context_item != null:
		var definition := (
			context_item.definition as EquippableItemDefinition
		)
		if definition == null:
			return
		var result := player.try_equip_world_entry(
			context_item.to_inventory_entry()
		)
		if not bool(result.get("success", false)):
			return
		_consume_world_item(context_item)
		var displaced: Dictionary = result.get("displaced", {})
		if not displaced.is_empty():
			_drop_entry_for_player(player, displaced)
		emit_spatial_sound(&"item_equip", player.global_position, 22.0, 0.0, null, 0.35)
		return

	# An aimed world interaction always wins over equipping the selected
	# inventory entry. This keeps scanners, drones, and future terminals
	# from being shadowed by the generic hold action.
	if hit.get("collider") != null:
		return
	var result := player.try_equip_inventory_entry(player.selected_inventory_slot)
	if bool(result.get("success", false)):
		emit_spatial_sound(&"item_equip", player.global_position, 22.0, 0.0, null, 0.35)


func try_drop_inventory_item(player: ServerPlayer) -> void:
	if player == null:
		return
	var entry := player.take_selected_inventory_entry()
	if entry.is_empty():
		entry = player.try_unequip_to_world(
			PlayerInventoryRules.BACKPACK_SLOT
		)
	_drop_entry_for_player(player, entry)


func try_drop_equipment(
	player: ServerPlayer,
	equipment_slot: String
) -> void:
	if player == null:
		return
	if (
		equipment_slot != PlayerInventoryRules.EYES_SLOT
		and equipment_slot != PlayerInventoryRules.BACKPACK_SLOT
		and equipment_slot != PlayerInventoryRules.WRIST_DEVICE_SLOT
	):
		return
	var entry := player.try_unequip_to_world(equipment_slot)
	_drop_entry_for_player(player, entry)


func distort_player_vision(
	player_id: int,
	warp: float,
	glitch: float,
	smear: float,
	duration: float,
	center: Vector2 = DEFAULT_DISTORTION_CENTER,
	pulse_hz: float = DEFAULT_DISTORTION_PULSE_HZ
) -> void:
	var player := get_server_player(player_id)
	if player == null:
		return
	player.apply_vision_distortion(
		warp,
		glitch,
		smear,
		duration,
		center,
		pulse_hz
	)


func try_use(player: ServerPlayer) -> void:
	if player == null:
		return
	if _try_cancel_rope_placement(player):
		return
	_try_use_hit(player, _raycast_player_aim(player))


func _try_use_hit(player: ServerPlayer, hit: Dictionary) -> void:
	if hit.is_empty():
		return

	var collider := hit.get("collider") as Node
	if collider != null and collider.has_method("server_use"):
		collider.call("server_use", player, hit)
		return

	var drone := collider as ServerDrone
	if drone != null:
		if drone.is_edit_preview and drone.edit_session != null:
			drone.edit_session.call("try_remove_part", player, hit)
		else:
			drone.set_ai_follow_player(player.player_id)
			drone.toggle_activated()


func _update_player_edit_aim(player: ServerPlayer) -> void:
	var hit := _raycast_player_aim(player)
	var drone := hit.get("collider") as ServerDrone
	var active := drone != null and drone.is_edit_preview
	var hit_position: Vector3 = hit.get(
		"position",
		player.grabber.get_grab_origin()
	)
	player.set_edit_aim(
		active,
		player.grabber.get_grab_origin(),
		hit_position,
		_get_player_edit_aim_color(player.player_id)
	)
	player.set_interaction_hint(
		_get_player_interaction_hint(player, hit)
	)


func _get_player_interaction_hint(
	player: ServerPlayer,
	hit: Dictionary
) -> String:
	var item := _get_context_item(player, hit)
	if item != null:
		if item.has_method("get_server_interaction_hint"):
			return str(item.call("get_server_interaction_hint", player, hit))
		var can_store := (
			player.inventory_entries.size()
			< player.get_inventory_capacity()
		)
		if item.definition is EquippableItemDefinition:
			return (
				"F // STORE   HOLD F // EQUIP"
				if can_store
				else "INVENTORY FULL   HOLD F // EQUIP"
			)
		return "F // STORE" if can_store else "INVENTORY FULL"

	var collider := hit.get("collider") as Node
	if collider != null and collider.has_method("get_server_interaction_hint"):
		return str(collider.call("get_server_interaction_hint", player, hit))
	if (
		collider != null
		and (
			collider.has_method("server_use")
			or collider is ServerDrone
		)
	):
		return "F // USE"

	if collider == null:
		var selected := player.get_selected_inventory_entry()
		if (
			PlayerInventoryRules.get_definition(selected)
			is GunItemDefinition
		):
			return (
				"LMB // FIRE   R // RELOAD"
				if (
					player.body_loadout != null
					and player.body_loadout.has_any_arm()
				)
				else "NO ARM // WEAPON INOPERABLE"
			)
		if (
			PlayerInventoryRules.get_equippable_definition(selected)
			!= null
		):
			return "HOLD F // EQUIP SELECTED"
	return ""


func _get_player_edit_aim_color(player_id: int) -> Color:
	var palette: Array[Color] = [
		Color(0.16, 0.82, 1.0, 1.0),
		Color(1.0, 0.28, 0.72, 1.0),
		Color(0.48, 1.0, 0.28, 1.0),
		Color(1.0, 0.74, 0.18, 1.0),
	]
	return palette[posmod(player_id, palette.size())]


func try_primary_action(
	player: ServerPlayer,
	local_prediction_key := 0
) -> bool:
	if player == null:
		return false
	# Close world-space controls must remain usable while a firearm occupies the
	# selected inventory slot. Only colliders that explicitly opt in receive this
	# priority, so ordinary targets still get the weapon action.
	var priority_hit := (
		_raycast_player_aim(player)
		if _is_near_priority_primary_interaction(player)
		else {}
	)
	var priority_collider := priority_hit.get("collider") as Node
	if (
		priority_collider != null
		and priority_collider.has_method("prefers_primary_action_over_weapon")
		and bool(priority_collider.call("prefers_primary_action_over_weapon"))
		and (
			not priority_collider.has_method("should_prioritize_primary_action")
			or bool(priority_collider.call(
				"should_prioritize_primary_action",
				player,
				priority_hit
			))
		)
		and priority_collider.has_method("server_primary_action")
	):
		priority_collider.call("server_primary_action", player, priority_hit)
		return false
	var gun_result := player.try_fire_selected_gun()
	if bool(gun_result.get("handled", false)):
		var fired := bool(gun_result.get("fired", false))
		if fired:
			_spawn_player_gun_projectiles(
				player,
				gun_result.get("profiles", []),
				int(gun_result.get("installed_barrel_count", 1)),
				gun_result.get("fire_sound", {}),
				local_prediction_key
			)
		return fired

	var held_body := get_grabbed_body(player.grabber) as RigidBody3D
	if held_body != null and held_body.has_method("server_held_primary_action"):
		held_body.call("server_held_primary_action", player)
		return false
	var hit := priority_hit
	if hit.is_empty():
		var origin := player.grabber.get_grab_origin()
		var direction := player.grabber.get_grab_direction()
		var query := PhysicsRayQueryParameters3D.create(
			origin,
			origin + direction * 4.0
		)
		query.exclude = [player.get_rid()]
		if held_body != null:
			query.exclude.append(held_body.get_rid())
		query.collide_with_areas = false
		hit = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider := hit.get("collider") as Node
	if collider != null and collider.has_method("server_primary_action"):
		var held_item := held_body as ServerItem
		if held_item != null and held_item.definition is RopeDefinition:
			rope_placements_by_player_id.erase(player.player_id)
		collider.call("server_primary_action", player, hit)
		return false
	if _try_rope_primary_action(player, held_body, hit):
		return false

	if held_body == null or not held_body.is_in_group("drone_parts"):
		return false

	var drone := collider as ServerDrone
	if (
		drone == null
		or not drone.is_edit_preview
		or drone.edit_session == null
	):
		return false

	drone.edit_session.call(
		"try_install_part",
		player,
		held_body,
		hit
	)
	return false


func _is_near_priority_primary_interaction(player: ServerPlayer) -> bool:
	for station: Node3D in weapon_crafting_stations_by_id.values():
		if (
			is_instance_valid(station)
			and station.global_position.distance_squared_to(player.global_position)
			<= PRIORITY_INTERACTION_CHECK_DISTANCE_SQUARED
		):
			return true
	return false


func _spawn_player_gun_projectiles(
	player: ServerPlayer,
	profiles_value: Variant,
	installed_barrel_count: int,
	fire_sound: Dictionary = {},
	local_prediction_key := 0
) -> void:
	var profiles: Array = (
		profiles_value as Array
		if profiles_value is Array
		else []
	)
	if profiles.is_empty():
		return
	var layout_barrel_count := maxi(installed_barrel_count, profiles.size())
	var aim_direction := player.grabber.get_grab_direction().normalized()
	var right := aim_direction.cross(Vector3.UP)
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var up := right.cross(aim_direction).normalized()
	var exclusions: Array = [player.get_rid()]
	var held_body := get_grabbed_body(player.grabber)
	if held_body != null:
		exclusions.append(held_body.get_rid())
	var sound_origin := player.grabber.get_grab_origin()
	for profile_index: int in range(profiles.size()):
		var profile: Dictionary = SafeVariant.dictionary_copy(
			profiles[profile_index]
		)
		if profile.is_empty():
			continue
		var direction := player.apply_weapon_spread(
			aim_direction,
			SafeVariant.finite_float_or(
				profile.get("spread_degrees"),
				0.0
			)
		)
		var barrel_offset := GunGeometry.get_barrel_layout_offset(
			profile_index,
			layout_barrel_count,
			0.115
		)
		var desired_origin := (
			player.grabber.get_grab_origin()
			+ direction * 0.92
			+ right * (0.2 + barrel_offset.x)
			+ Vector3.DOWN * 0.18
			+ up * barrel_offset.y
		)
		var origin := desired_origin
		var muzzle_query := PhysicsRayQueryParameters3D.create(
			player.grabber.get_grab_origin(),
			desired_origin
		)
		muzzle_query.exclude = exclusions
		muzzle_query.collide_with_areas = false
		var muzzle_hit := (
			player.get_world_3d().direct_space_state.intersect_ray(
				muzzle_query
			)
		)
		if not muzzle_hit.is_empty():
			origin = (
				muzzle_hit.get("position", desired_origin)
				- direction * 0.035
			)
		spawn_ballistic_projectile(
			profile,
			origin,
			direction,
			player.velocity,
			exclusions,
			&"player",
			player.player_id,
			player,
			profile_index
		)
		if profile_index == 0:
			sound_origin = origin
	var sound_id := StringName(str(fire_sound.get("sound_id", "")).strip_edges())
	if not sound_id.is_empty():
		emit_spatial_sound(
			sound_id,
			sound_origin,
			clampf(
				SafeVariant.finite_float_or(fire_sound.get("max_distance"), 80.0),
				0.1,
				10000.0
			),
			clampf(
				SafeVariant.finite_float_or(fire_sound.get("volume_db"), 0.0),
				-60.0,
				18.0
			),
			null,
			clampf(
				SafeVariant.finite_float_or(fire_sound.get("priority"), 0.9),
				0.0,
				1.0
			),
			clampf(
				SafeVariant.finite_float_or(
					fire_sound.get("pressure_strength"),
					-1.0
				),
				-1.0,
				1.0
			),
			player.player_id,
			local_prediction_key
		)


func set_player_grab_capability(
	player_id: int,
	capability: GrabCapability
) -> void:
	var player := get_server_player(player_id)
	if player != null:
		player.set_grab_capability(capability)


func set_player_body_loadout(
	player_id: int,
	loadout: CharacterLoadout
) -> void:
	var player := get_server_player(player_id)
	if player != null:
		player.set_body_loadout(loadout)


func install_player_limb(
	player_id: int,
	limb: LimbDefinition
) -> void:
	var player := get_server_player(player_id)
	if player != null:
		player.install_limb(limb)


func remove_player_limb(
	player_id: int,
	slot: LimbDefinition.Slot
) -> void:
	var player := get_server_player(player_id)
	if player != null:
		player.remove_limb(slot)


func try_begin_grab(grabber: GrabberComponent) -> void:
	if grabber == null or not grabber.can_grab():
		return

	end_grab(grabber)

	var capability := grabber.capability
	var origin := grabber.get_grab_origin()
	var direction := grabber.get_grab_direction()
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * capability.max_distance
	)

	var carrier := grabber.get_carrier_body()
	if carrier != null:
		query.exclude = [carrier.get_rid()]

	query.collide_with_areas = false

	var space_state := grabber.get_world_3d().direct_space_state
	var hit := space_state.intersect_ray(query)
	var body := hit.get("collider") as PhysicsBody3D
	var hit_position: Vector3 = hit.get("position", origin)
	if not _is_grab_candidate(body):
		var assisted := _find_assisted_grab_candidate(
			space_state,
			origin,
			direction,
			capability.max_distance,
			query.exclude
		)
		body = assisted.get("body") as PhysicsBody3D
		hit_position = assisted.get("position", origin)
	if not _prepare_grab_candidate(body):
		return
	_begin_grab_body(grabber, body, hit_position)


func _is_grab_candidate(body: PhysicsBody3D) -> bool:
	if (
		body == null
		or body is CharacterBody3D
		or body is StaticBody3D
		or not body is RigidBody3D
		or body.is_in_group("rope_knots")
		or body.has_meta("inspection_station_id")
		or bool(body.get_meta("grip_surface_disabled", false))
	):
		return false
	if body is ServerDrone and (body as ServerDrone).is_edit_preview:
		return false
	var rigid_body := body as RigidBody3D
	return not rigid_body.freeze or body.has_meta("dev_warehouse_owner")


func _prepare_grab_candidate(body: PhysicsBody3D) -> bool:
	if not _is_grab_candidate(body):
		return false
	if not body.has_meta("dev_warehouse_owner"):
		return true
	var warehouse := body.get_meta("dev_warehouse_owner") as Node
	var warehouse_part := body as RigidBody3D
	return (
		warehouse != null
		and warehouse_part != null
		and warehouse.has_method("release_socketed_part")
		and bool(warehouse.call("release_socketed_part", warehouse_part))
	)


func _find_assisted_grab_candidate(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	direction: Vector3,
	maximum_distance: float,
	excluded_rids: Array[RID]
) -> Dictionary:
	if space_state == null or maximum_distance <= 0.0:
		return {}
	direction = direction.normalized()
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.96:
		up = Vector3.FORWARD
	grab_aim_assist_shape.size = Vector3(
		GRAB_AIM_ASSIST_HALF_EXTENT * 2.0,
		GRAB_AIM_ASSIST_HALF_EXTENT * 2.0,
		maximum_distance
	)
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = grab_aim_assist_shape
	shape_query.transform = Transform3D(
		Basis.looking_at(direction, up),
		origin + direction * maximum_distance * 0.5
	)
	shape_query.exclude = excluded_rids
	shape_query.collide_with_areas = false
	shape_query.collide_with_bodies = true
	var best_score := INF
	var best: Dictionary = {}
	for result: Dictionary in space_state.intersect_shape(
		shape_query,
		GRAB_AIM_ASSIST_MAX_RESULTS
	):
		var candidate := result.get("collider") as PhysicsBody3D
		if not _is_grab_candidate(candidate):
			continue
		var candidate_point := _grab_candidate_world_point(candidate)
		var offset := candidate_point - origin
		var forward_distance := offset.dot(direction)
		if forward_distance <= 0.0 or forward_distance > maximum_distance:
			continue
		var lateral_distance := (
			offset - direction * forward_distance
		).length()
		var score := (
			forward_distance
			+ lateral_distance * GRAB_AIM_ASSIST_LATERAL_SCORE
		)
		if score >= best_score:
			continue
		var sight_query := PhysicsRayQueryParameters3D.create(
			origin,
			candidate_point
		)
		sight_query.exclude = excluded_rids
		sight_query.collide_with_areas = false
		var sight_hit := space_state.intersect_ray(sight_query)
		if sight_hit.get("collider") != candidate:
			continue
		best_score = score
		best = {
			"body": candidate,
			"position": sight_hit.get("position", candidate_point),
		}
	return best


static func _grab_candidate_world_point(body: PhysicsBody3D) -> Vector3:
	if body == null:
		return Vector3.ZERO
	var item_collision := body.get_node_or_null("ItemCollision") as CollisionShape3D
	if item_collision != null and not item_collision.disabled:
		return item_collision.global_position
	return body.global_position


func _begin_grab_body(
	grabber: GrabberComponent,
	body: PhysicsBody3D,
	hit_position: Vector3
) -> void:
	if grabber == null or body == null or not grabber.can_grab():
		return

	end_grab(grabber)
	var capability := grabber.capability
	var origin := grabber.get_grab_origin()
	var grab_distance := clampf(
		origin.distance_to(hit_position),
		capability.get_clamped_min_distance(),
		capability.max_distance
	)

	var state := GrabState.new(
		grabber,
		body,
		body.to_local(hit_position),
		grab_distance,
		capability.lift_offset,
		_get_initial_grab_basis(grabber, body)
	)
	grab_states_by_grabber_id[grabber.get_instance_id()] = state
	_center_grab_rotation_anchor(state)


func _get_initial_grab_basis(
	grabber: GrabberComponent,
	body: PhysicsBody3D
) -> Basis:
	if body.has_method("get_default_grab_basis"):
		var authored_value: Variant = body.call("get_default_grab_basis")
		if typeof(authored_value) == TYPE_BASIS:
			var authored_basis: Basis = authored_value
			if authored_basis.is_finite():
				return authored_basis.orthonormalized()

	# Physics bodies without an authored item pose keep the orientation they had
	# when grabbed. This avoids surprising snaps for drones and loose body parts.
	return (
		grabber.global_basis.orthonormalized().transposed()
		* body.global_basis.orthonormalized()
	).orthonormalized()


func grab_body_directly(
	grabber: GrabberComponent,
	body: PhysicsBody3D
) -> void:
	if body == null:
		return
	_begin_grab_body(grabber, body, body.global_position)


func release_grabs_for_body(body: PhysicsBody3D) -> void:
	if body != null:
		_release_grabs_for_body(body)


func get_grabbed_body(grabber: GrabberComponent) -> PhysicsBody3D:
	if grabber == null:
		return null

	var state := grab_states_by_grabber_id.get(
		grabber.get_instance_id()
	) as GrabState
	if state == null or not is_instance_valid(state.body):
		return null
	return state.body


func end_grab(grabber: GrabberComponent) -> void:
	if grabber == null:
		return

	_end_grab_by_id(grabber.get_instance_id())


func set_grabber_rotation_active(
	grabber: GrabberComponent,
	active: bool,
	session_id := 0
) -> void:
	if grabber == null:
		return

	var state := grab_states_by_grabber_id.get(
		grabber.get_instance_id()
	) as GrabState
	if state != null:
		state.set_rotation_active(active, session_id)
		if active:
			_center_grab_rotation_anchor(state)


func set_grab_rotation_input_target(
	grabber: GrabberComponent,
	input_target: Vector2,
	session_id := 0
) -> void:
	if grabber == null or not input_target.is_finite():
		return

	var state := grab_states_by_grabber_id.get(
		grabber.get_instance_id()
	) as GrabState
	if state != null and state.rotation_active:
		_center_grab_rotation_anchor(state)
		state.set_rotation_input_target(input_target, session_id)


func _center_grab_rotation_anchor(state: GrabState) -> void:
	if state.rotation_anchor_centered:
		return

	var rigid_body := state.body as RigidBody3D
	var capability := state.grabber.capability
	if rigid_body == null or capability == null:
		return

	var previous_grab_point := rigid_body.to_global(state.local_grab_point)
	var previous_target := state.grabber.get_grab_target(
		state.grab_distance,
		state.lift_offset,
		state.side_offset
	)
	state.center_rotation_anchor(
		_get_rigid_body_center_of_mass_local(rigid_body),
		capability.rotation_anchor_centering
	)

	# Moving the force anchor to the center of mass removes rotational resistance. Shift its hold
	# target by the same world-space amount so the object does not jump or get pulled sideways.
	var origin := state.grabber.get_grab_origin()
	var direction := state.grabber.get_grab_direction()
	var up_direction := state.grabber.global_basis.y.normalized()
	var side_direction := state.grabber.global_basis.x.normalized()
	var centered_point := rigid_body.to_global(state.local_grab_point)
	var centered_target := previous_target + centered_point - previous_grab_point
	var centered_offset := centered_target - origin
	state.grab_distance = clampf(
		centered_offset.dot(direction),
		capability.get_clamped_min_distance(),
		capability.max_distance
	)
	state.lift_offset = centered_offset.dot(up_direction)
	state.side_offset = centered_offset.dot(side_direction)


static func _get_rigid_body_center_of_mass_local(
	rigid_body: RigidBody3D
) -> Vector3:
	if rigid_body == null:
		return Vector3.ZERO
	if (
		rigid_body.center_of_mass_mode
		== RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	):
		return rigid_body.center_of_mass

	# In automatic mode RigidBody3D.center_of_mass remains the authored default;
	# only the direct physics state exposes the value computed from offset shapes.
	var direct_state := PhysicsServer3D.body_get_direct_state(
		rigid_body.get_rid()
	)
	if direct_state != null and direct_state.center_of_mass_local.is_finite():
		return direct_state.center_of_mass_local
	return rigid_body.center_of_mass


func _end_grab_by_id(grabber_id: int) -> void:
	var state := grab_states_by_grabber_id.get(grabber_id) as GrabState

	if state != null and is_instance_valid(state.grabber):
		state.grabber.clear_load()

	grab_states_by_grabber_id.erase(grabber_id)


func _release_grabs_for_body(body: PhysicsBody3D) -> void:
	for grabber_id: int in grab_states_by_grabber_id.keys():
		var state: GrabState = grab_states_by_grabber_id[grabber_id]

		if state.body == body:
			_end_grab_by_id(grabber_id)


func _get_total_force_capacity(body: PhysicsBody3D) -> float:
	var result := 0.0

	for state: GrabState in grab_states_by_grabber_id.values():
		if (
			state.body == body
			and is_instance_valid(state.grabber)
			and state.grabber.capability != null
		):
			result += state.grabber.get_effective_max_force()

	return maxf(result, MIN_TOTAL_GRAB_FORCE)


func _get_force_share(state: GrabState) -> float:
	if state.grabber.capability == null:
		return 0.0

	return (
		state.grabber.get_effective_max_force()
		/ _get_total_force_capacity(state.body)
	)


func _update_grabber_loads() -> void:
	for grabber_id: int in grab_states_by_grabber_id.keys():
		var state: GrabState = grab_states_by_grabber_id[grabber_id]

		if (
			not is_instance_valid(state.grabber)
			or not is_instance_valid(state.body)
		):
			_end_grab_by_id(grabber_id)
			continue

		if state.body is StaticBody3D:
			state.grabber.apply_load(0.0, true)
			continue

		var rigid_body := state.body as RigidBody3D
		if rigid_body == null or rigid_body.freeze:
			state.grabber.apply_load(0.0, true)
			continue

		var shared_mass := (
			rigid_body.mass
			* _get_force_share(state)
		)
		state.grabber.apply_load(shared_mass, false)


func _apply_grab_forces(delta: float) -> void:
	for grabber_id: int in grab_states_by_grabber_id.keys():
		var state: GrabState = grab_states_by_grabber_id[grabber_id]
		_apply_grab_state_force(grabber_id, state, delta)


func _apply_grab_state_force(
	grabber_id: int,
	state: GrabState,
	delta: float
) -> void:
	if (
		not is_instance_valid(state.grabber)
		or not is_instance_valid(state.body)
	):
		_end_grab_by_id(grabber_id)
		return

	var capability := state.grabber.capability
	if capability == null or not state.grabber.enabled:
		_end_grab_by_id(grabber_id)
		return

	var grab_point := state.body.to_global(state.local_grab_point)
	if (
		grab_point.distance_to(state.grabber.get_grab_origin())
		> capability.get_clamped_break_distance()
	):
		_end_grab_by_id(grabber_id)
		return

	var rigid_body := state.body as RigidBody3D
	if rigid_body == null or rigid_body.freeze:
		return

	var force_state := _calculate_grab_force(
		state,
		rigid_body,
		grab_point,
		capability
	)
	var desired_force: Vector3 = force_state["desired_force"]
	var spring_force: Vector3 = force_state["spring_force"]
	var force_share := float(force_state["force_share"])
	var body_offset: Vector3 = force_state["body_offset"]

	# Strong and weak grabbers contribute force and load in the same ratio.
	var effective_max_force := state.grabber.get_effective_max_force()
	state.grabber.apply_tether_force(
		_calculate_required_tether_force(
			state,
			grab_point,
			spring_force,
			force_share
		),
		effective_max_force,
		grab_point
	)

	var applied_max_force := effective_max_force
	if (
		state.grabber.get_carrier_velocity().y
		> capability.jump_lift_min_velocity
		and desired_force.y > 0.0
	):
		applied_max_force *= capability.jump_lift_force_multiplier
	desired_force = desired_force.limit_length(applied_max_force)

	rigid_body.apply_force(desired_force, body_offset)
	state.grabber.apply_reaction_force(-desired_force)
	_apply_grab_rotation(state, rigid_body, delta)


func _calculate_grab_force(
	state: GrabState,
	rigid_body: RigidBody3D,
	grab_point: Vector3,
	capability: GrabCapability
) -> Dictionary:
	var target := state.grabber.get_grab_target(
		state.grab_distance,
		state.lift_offset,
		state.side_offset
	)
	var body_offset := grab_point - rigid_body.global_position
	var point_velocity := (
		rigid_body.linear_velocity
		+ rigid_body.angular_velocity.cross(body_offset)
	)
	var relative_velocity := (
		state.grabber.get_carrier_velocity() - point_velocity
	)
	var spring_force = (
		rigid_body.mass
		* (target - grab_point)
		* capability.spring_acceleration
	)
	var damping_force = (
		rigid_body.mass
		* relative_velocity
		* capability.damping_acceleration
	)
	var force_share := _get_force_share(state)
	return {
		"body_offset": body_offset,
		"spring_force": spring_force,
		"force_share": force_share,
		"desired_force": (spring_force + damping_force) * force_share,
	}


func _calculate_required_tether_force(
	state: GrabState,
	grab_point: Vector3,
	spring_force: Vector3,
	force_share: float
) -> float:
	var tether_direction := state.grabber.get_grab_origin() - grab_point
	tether_direction.y = 0.0
	if tether_direction.length_squared() <= MIN_DIRECTION_LENGTH_SQUARED:
		return 0.0
	return maxf(
		(spring_force * force_share).dot(tether_direction.normalized()),
		0.0
	)


func _apply_grab_rotation(
	state: GrabState,
	rigid_body: RigidBody3D,
	_delta: float
) -> void:
	var grabber := state.grabber
	var capability := grabber.capability
	if capability == null:
		return

	if state.rotation_active:
		state.advance_rotation_target(capability.rotation_radians_per_pixel)

	var max_torque := grabber.get_effective_max_rotation_torque()
	if max_torque <= 0.0:
		return

	var rotation_error := GrabState.rotation_error_vector(
		rigid_body.global_basis,
		state.get_target_world_basis()
	)
	var desired_angular_acceleration := (
		rotation_error * capability.rotation_target_stiffness
		- rigid_body.angular_velocity * capability.rotation_target_damping
	)
	if desired_angular_acceleration.is_zero_approx():
		return
	var inertia_tensor := rigid_body.get_inverse_inertia_tensor().inverse()
	var desired_torque := (
		inertia_tensor * desired_angular_acceleration
	).limit_length(max_torque)

	rigid_body.apply_torque(desired_torque)
	grabber.apply_reaction_torque(-desired_torque)

func start_steam_host() -> void:
	if not is_steam_available():
		_emit_lobby_status(get_steam_unavailable_message(), true)
		return
	if lobby_state != LobbyState.IDLE:
		_emit_lobby_status("A lobby operation is already active.", true)
		return

	lobby_state = LobbyState.CREATING
	pending_lobby_id = 0
	lobby_operation_generation += 1
	_emit_lobby_status("Creating a public Steam lobby...", false)
	Steam.createLobby(
		Steam.LOBBY_TYPE_PUBLIC,
		LobbyRules.MAX_PLAYERS
	)
	_schedule_lobby_timeout(
		LobbyState.CREATING,
		LOBBY_CREATE_TIMEOUT_SECONDS,
		"Steam did not finish creating the lobby."
	)


func join_steam_lobby(target_lobby_id: int) -> void:
	if not is_steam_available():
		_emit_lobby_status(get_steam_unavailable_message(), true)
		return
	if target_lobby_id <= 0:
		_emit_lobby_status("That lobby ID is invalid.", true)
		return
	if lobby_state != LobbyState.IDLE:
		_emit_lobby_status("A lobby operation is already active.", true)
		return

	pending_lobby_id = target_lobby_id
	lobby_state = LobbyState.JOINING
	lobby_operation_generation += 1
	_emit_lobby_status("Joining Steam lobby...", false)
	Steam.joinLobby(target_lobby_id)
	_schedule_lobby_timeout(
		LobbyState.JOINING,
		LOBBY_JOIN_TIMEOUT_SECONDS,
		"Steam did not answer the lobby join request."
	)


func cancel_pending_lobby_join() -> void:
	if (
		lobby_state != LobbyState.JOINING
		and lobby_state != LobbyState.CONNECTING
	):
		return

	pending_lobby_id = 0
	if lobby_id > 0:
		Steam.leaveLobby(lobby_id)
	_reset_lobby_identity()
	_set_offline_multiplayer_peer()


func is_steam_available() -> bool:
	return steam_available and Steam.isSteamRunning()


func get_steam_unavailable_message() -> String:
	if is_steam_available():
		return "Steam connected."
	var detail := steam_init_message.strip_edges()
	if detail.is_empty():
		detail = "No initialization detail was returned."
	return "Steam unavailable: %s" % detail


func _on_lobby_created(connect_result: int, created_lobby_id: int) -> void:
	if lobby_state != LobbyState.CREATING:
		if connect_result == 1 and created_lobby_id > 0:
			Steam.leaveLobby(created_lobby_id)
		return
	if connect_result != 1 or created_lobby_id <= 0:
		_fail_lobby_operation(
			"Steam could not create the lobby (result %d)."
			% connect_result
		)
		return

	lobby_id = created_lobby_id
	lobby_owner_id = Steam.getSteamID()
	pending_lobby_id = 0

	var lobby_name: String = Steam.getPersonaName().strip_edges()
	if lobby_name.is_empty():
		lobby_name = "ScavangeInc"
	else:
		lobby_name += "'s game"

	var lobby_configured: bool = Steam.setLobbyMemberLimit(
		lobby_id,
		LobbyRules.MAX_PLAYERS
	)
	lobby_configured = Steam.setLobbyData(
		lobby_id,
		LobbyRules.DATA_GAME,
		LobbyRules.GAME_TAG
	) and lobby_configured
	lobby_configured = Steam.setLobbyData(
		lobby_id,
		LobbyRules.DATA_PROTOCOL,
		LobbyRules.PROTOCOL_VERSION
	) and lobby_configured
	lobby_configured = Steam.setLobbyData(
		lobby_id,
		LobbyRules.DATA_NAME,
		lobby_name
	) and lobby_configured
	lobby_configured = Steam.setLobbyData(
		lobby_id,
		LobbyRules.DATA_PLAYERS,
		"0"
	) and lobby_configured
	lobby_configured = Steam.setLobbyData(
		lobby_id,
		LobbyRules.DATA_OPEN,
		"1"
	) and lobby_configured
	lobby_configured = Steam.setLobbyJoinable(
		lobby_id,
		true
	) and lobby_configured
	if not lobby_configured:
		_fail_lobby_operation("Steam rejected the lobby configuration.")
		return

	_start_steam_host_transport()


func _start_steam_host_transport() -> void:
	steam_peer = SteamMultiplayerPeer.new()
	steam_peer.server_relay = true

	var err := steam_peer.create_host(0)
	if err != OK:
		_fail_lobby_operation(
			"Steam networking could not host the game (%s)." % err
		)
		return

	multiplayer.multiplayer_peer = steam_peer
	lobby_state = LobbyState.HOSTING

	spawn_server_world()

	var host_peer_id := multiplayer.get_unique_id()
	if not register_peer(host_peer_id):
		_fail_lobby_operation("The host could not claim a player slot.")
		return

	print("HOST STARTED. peer_id=", host_peer_id)
	_emit_lobby_status(
		"Hosting game (%d/%d)." % [
			GameState.get_player_count(),
			LobbyRules.MAX_PLAYERS,
		],
		false
	)
	SceneController.enter_game()


func join_steam_host(host_steam_id: int) -> void:
	if host_steam_id <= 0:
		_fail_lobby_operation("The lobby has no valid host.")
		return

	steam_peer = SteamMultiplayerPeer.new()
	steam_peer.server_relay = true

	var err := steam_peer.create_client(host_steam_id)
	if err != OK:
		_fail_lobby_operation(
			"Steam networking could not connect to the host (%s)." % err
		)
		return

	multiplayer.multiplayer_peer = steam_peer
	lobby_state = LobbyState.CONNECTING
	_emit_lobby_status("Connecting to lobby host...", false)
	_schedule_lobby_timeout(
		LobbyState.CONNECTING,
		HOST_CONNECTION_TIMEOUT_SECONDS,
		"Timed out while connecting to the lobby host."
	)

	print("JOINING HOST: ", host_steam_id)


func _on_lobby_joined(
	joined_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:
	# Steam emits both LobbyCreated_t and LobbyEnter_t for the host. Their
	# delivery is normally ordered, but the host must never interpret its own
	# enter callback as a client join even if LobbyEnter_t arrives first.
	if (
		lobby_state == LobbyState.CREATING
		and response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS
	):
		return

	if (
		joined_lobby_id == lobby_id
		and lobby_owner_id == Steam.getSteamID()
		and (
			lobby_state == LobbyState.HOSTING
			or lobby_state == LobbyState.CREATING
		)
	):
		return

	if (
		lobby_state != LobbyState.JOINING
		or joined_lobby_id != pending_lobby_id
	):
		if (
			response == Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS
			and joined_lobby_id > 0
		):
			Steam.leaveLobby(joined_lobby_id)
		return

	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_fail_lobby_operation(
			_get_lobby_join_error(response)
		)
		return

	lobby_id = joined_lobby_id
	pending_lobby_id = 0
	lobby_owner_id = Steam.getLobbyOwner(lobby_id)

	var capacity: int = Steam.getLobbyMemberLimit(lobby_id)
	var members: int = Steam.getNumLobbyMembers(lobby_id)
	var game_tag: String = Steam.getLobbyData(
		lobby_id,
		LobbyRules.DATA_GAME
	)
	var protocol: String = Steam.getLobbyData(
		lobby_id,
		LobbyRules.DATA_PROTOCOL
	)
	if (
		not LobbyRules.has_matching_rules(
			game_tag,
			protocol,
			capacity
		)
		or members > LobbyRules.MAX_PLAYERS
	):
		_fail_lobby_operation(
			"The lobby is full or uses an incompatible game version."
		)
		return

	join_steam_host(lobby_owner_id)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	print("PEER CONNECTED: ", peer_id)
	_admit_connected_peer(peer_id)


func _admit_connected_peer(peer_id: int) -> void:
	for _attempt: int in range(LOBBY_MEMBERSHIP_CHECK_ATTEMPTS):
		if not multiplayer.get_peers().has(peer_id):
			return
		if _is_peer_in_current_lobby(peer_id):
			if register_peer(peer_id):
				return
			_reject_connected_peer(
				peer_id,
				"the four-player lobby is full"
			)
			return
		await get_tree().create_timer(
			LOBBY_MEMBERSHIP_CHECK_DELAY
		).timeout

	if multiplayer.get_peers().has(peer_id):
		_reject_connected_peer(
			peer_id,
			"the Steam account is not in this lobby"
		)


func _is_peer_in_current_lobby(peer_id: int) -> bool:
	if lobby_id <= 0 or steam_peer == null:
		return false

	var peer_steam_id: int = steam_peer.get_steam_id_for_peer_id(
		peer_id
	)
	if peer_steam_id <= 0:
		return false

	var member_count: int = Steam.getNumLobbyMembers(lobby_id)
	for member_index: int in range(member_count):
		if (
			Steam.getLobbyMemberByIndex(lobby_id, member_index)
			== peer_steam_id
		):
			return true
	return false


func _reject_connected_peer(peer_id: int, reason: String) -> void:
	push_warning("Rejecting peer %d: %s." % [peer_id, reason])
	multiplayer.multiplayer_peer.disconnect_peer(peer_id, true)
	_sync_lobby_availability()


func _on_peer_disconnected(peer_id: int) -> void:
	if session_teardown_active:
		return
	if not multiplayer.is_server():
		return

	var player_id := GameState.get_player_id(peer_id)
	if player_id == -1:
		return
	# The transport has already removed this peer before emitting peer_disconnected. Invalidate its
	# application route before cleanup can close the PBD, spill equipment, or emit other effects.
	# Those effects may still be sent to the remaining players through the normal broadcasters.
	GameState.unregister_peer(peer_id)
	if acoustic_service != null:
		acoustic_service.forget_listener(player_id)

	var player := get_server_player(player_id)
	if player != null:
		end_grab(player.grabber)
		var spill_entries := player.spill_all_item_entries()
		for entry_index: int in range(spill_entries.size()):
			_drop_entry_for_player(
				player,
				spill_entries[entry_index],
				entry_index
			)
	rope_placements_by_player_id.erase(player_id)

	if server_players_by_player_id.has(player_id):
		spatial_hash.unregister_entity(_get_player_spatial_key(player_id))
		server_players_by_player_id[player_id].queue_free()
		server_players_by_player_id.erase(player_id)

	_sync_lobby_availability()

	print("PEER DISCONNECTED: ", peer_id)


func _on_connected_to_server() -> void:
	if lobby_state != LobbyState.CONNECTING:
		return
	lobby_state = LobbyState.CONNECTED
	_refresh_lobby_presence_from_membership()
	_emit_lobby_status("Connected to lobby host.", false)
	SceneController.enter_game()


func _on_connection_failed() -> void:
	if (
		lobby_state == LobbyState.CONNECTING
		or lobby_state == LobbyState.JOINING
	):
		_fail_lobby_operation("Could not connect to the lobby host.")


func _on_server_disconnected() -> void:
	if lobby_state != LobbyState.CONNECTED:
		return
	if lobby_id > 0:
		Steam.leaveLobby(lobby_id)
	_reset_lobby_identity()
	_set_offline_multiplayer_peer()
	Client.reset_session()
	_emit_lobby_status("The lobby host disconnected.", true)
	SceneController.open_main_menu()


func _on_lobby_chat_update(
	changed_lobby_id: int,
	_changed_user_id: int,
	_making_change_user_id: int,
	_chat_state: int
) -> void:
	if changed_lobby_id != lobby_id:
		return
	if lobby_state == LobbyState.HOSTING:
		_sync_lobby_availability()
	elif lobby_state == LobbyState.CONNECTED:
		_refresh_lobby_presence_from_membership()


func _on_join_requested(
	requested_lobby_id: int,
	_friend_id: int
) -> void:
	_request_external_lobby_join(requested_lobby_id)


func _on_join_game_requested(
	_friend_id: int,
	connect_string: String
) -> void:
	var requested_lobby_id: int = STEAM_JOIN_COMMAND.parse_command_line(
		connect_string
	)
	if requested_lobby_id <= 0:
		_emit_lobby_status(
			"Steam sent an invalid Join Game request.",
			true
		)
		return
	_request_external_lobby_join(requested_lobby_id)


func _request_external_lobby_join(requested_lobby_id: int) -> void:
	if requested_lobby_id <= 0:
		_emit_lobby_status("Steam sent an invalid lobby ID.", true)
		return
	if (
		requested_lobby_id == lobby_id
		or requested_lobby_id == pending_lobby_id
	):
		return
	if lobby_state != LobbyState.IDLE:
		_emit_lobby_status(
			"Leave the current lobby before joining another friend.",
			true
		)
		return
	SceneController.open_lobby_browser()
	join_steam_lobby(requested_lobby_id)


func _get_launch_lobby_id() -> int:
	var requested_lobby_id: int = STEAM_JOIN_COMMAND.parse_command_line(
		Steam.getLaunchCommandLine()
	)
	if requested_lobby_id > 0:
		return requested_lobby_id
	return STEAM_JOIN_COMMAND.parse_arguments(OS.get_cmdline_args())


func can_invite_to_current_lobby() -> bool:
	if (
		not is_steam_available()
		or not Steam.isOverlayEnabled()
		or lobby_id <= 0
		or (
			lobby_state != LobbyState.HOSTING
			and lobby_state != LobbyState.CONNECTED
		)
	):
		return false
	var member_count := Steam.getNumLobbyMembers(lobby_id)
	return (
		LobbyRules.can_register_player(member_count)
		and Steam.getLobbyData(lobby_id, LobbyRules.DATA_OPEN) != "0"
	)


func is_lobby_idle() -> bool:
	return lobby_state == LobbyState.IDLE


func get_lobby_session_label() -> String:
	if lobby_id <= 0 or not is_steam_available():
		return "OFFLINE"
	var role := "HOST" if lobby_state == LobbyState.HOSTING else "CREW"
	return "%s  /  %d OF %d" % [
		role,
		clampi(
			Steam.getNumLobbyMembers(lobby_id),
			1,
			LobbyRules.MAX_PLAYERS
		),
		LobbyRules.MAX_PLAYERS,
	]


func open_steam_invite_overlay() -> bool:
	if not can_invite_to_current_lobby():
		_emit_lobby_status(
			"Steam invites need an open lobby and Steam overlay.",
			true
		)
		return false
	Steam.activateGameOverlayInviteDialog(lobby_id)
	_emit_lobby_status("Steam invite overlay opened.", false)
	return true


func leave_steam_session() -> void:
	if session_teardown_active:
		return
	session_teardown_active = true
	var previous_lobby_id := lobby_id
	if previous_lobby_id > 0 and is_steam_available():
		Steam.leaveLobby(previous_lobby_id)
	_reset_lobby_identity()
	_set_offline_multiplayer_peer()
	_clear_runtime_session()
	Client.reset_session()
	session_teardown_active = false
	_emit_lobby_status("Left the Steam session.", false)
	SceneController.open_main_menu()


func _clear_runtime_session() -> void:
	if is_instance_valid(server_world):
		server_world.queue_free()
	server_world = null
	if acoustic_service != null:
		acoustic_service.bind_world(null)

	server_players_by_player_id.clear()
	server_items_by_item_id.clear()
	server_radios_by_item_id.clear()
	server_speaker_clusters.clear()
	fieldlink_control_targets_by_contact_id.clear()
	server_drones_by_drone_id.clear()
	server_projectiles_by_id.clear()
	server_drone_parts_by_id.clear()
	server_enemies_by_enemy_id.clear()
	inspection_stations_by_id.clear()
	body_part_shop_terminals_by_id.clear()
	weapon_crafting_stations_by_id.clear()
	body_part_delivery_orders.clear()
	server_ropes_by_rope_id.clear()
	rope_ids_by_body_instance_id.clear()
	rope_placements_by_player_id.clear()
	grab_states_by_grabber_id.clear()
	spatial_interest_by_drone_id.clear()
	fieldlink_next_command_msec_by_player_id.clear()
	spatial_hash = ServerSpatialHash3D.new(SPATIAL_CELL_SIZE)
	sync_timer = 0.0
	next_drone_id = 0
	next_projectile_id = 0
	next_drone_part_id = 0
	next_drone_part_token_id = 0
	next_rope_id = 0
	next_enemy_id = 0
	next_body_part_order_id = 0
	next_spatial_sound_sequence = 0
	network_snapshot_sequence = 0
	item_motion_sequence = 0
	GameState.reset_session()


func _sync_lobby_availability() -> void:
	if (
		lobby_state != LobbyState.HOSTING
		or lobby_id <= 0
		or Steam.getLobbyOwner(lobby_id) != Steam.getSteamID()
	):
		return

	var registered_player_count: int = GameState.get_player_count()
	var advertised_player_count: int = maxi(
		registered_player_count,
		Steam.getNumLobbyMembers(lobby_id)
	)
	var has_open_slot := LobbyRules.can_register_player(
		advertised_player_count
	)
	if steam_peer != null:
		steam_peer.refuse_new_connections = (
			not LobbyRules.can_register_player(
				registered_player_count
			)
		)
	Steam.setLobbyData(
		lobby_id,
		LobbyRules.DATA_PLAYERS,
		str(advertised_player_count)
	)
	Steam.setLobbyData(
		lobby_id,
		LobbyRules.DATA_OPEN,
		"1" if has_open_slot else "0"
	)
	Steam.setLobbyJoinable(lobby_id, has_open_slot)
	_publish_lobby_presence(
		has_open_slot,
		advertised_player_count
	)


func _refresh_lobby_presence_from_membership() -> void:
	if lobby_id <= 0 or not is_steam_available():
		return
	var member_count: int = Steam.getNumLobbyMembers(lobby_id)
	var advertised_open: String = Steam.getLobbyData(
		lobby_id,
		LobbyRules.DATA_OPEN
	)
	_publish_lobby_presence(
		advertised_open != "0"
		and LobbyRules.can_register_player(member_count),
		member_count
	)


func _publish_lobby_presence(
	has_open_slot: bool,
	member_count: int
) -> void:
	if lobby_id <= 0 or not is_steam_available():
		return
	var safe_member_count := clampi(
		member_count,
		1,
		LobbyRules.MAX_PLAYERS
	)
	var status := "In game (%d/%d)" % [
		safe_member_count,
		LobbyRules.MAX_PLAYERS,
	]
	Steam.setRichPresence(STEAM_PRESENCE_STATUS, status)
	Steam.setRichPresence(STEAM_PRESENCE_GROUP, str(lobby_id))
	Steam.setRichPresence(
		STEAM_PRESENCE_GROUP_SIZE,
		str(safe_member_count)
	)
	Steam.setRichPresence(
		STEAM_PRESENCE_CONNECT,
		STEAM_JOIN_COMMAND.build(lobby_id) if has_open_slot else ""
	)


func _clear_lobby_presence() -> void:
	if not is_steam_available():
		return
	Steam.setRichPresence(STEAM_PRESENCE_CONNECT, "")
	Steam.setRichPresence(STEAM_PRESENCE_STATUS, "")
	Steam.setRichPresence(STEAM_PRESENCE_GROUP, "")
	Steam.setRichPresence(STEAM_PRESENCE_GROUP_SIZE, "")


func _fail_lobby_operation(message: String) -> void:
	push_error(message)
	if lobby_id > 0:
		Steam.leaveLobby(lobby_id)
	_reset_lobby_identity()
	_set_offline_multiplayer_peer()
	_emit_lobby_status(message, true)


func _reset_lobby_identity() -> void:
	_clear_lobby_presence()
	lobby_operation_generation += 1
	lobby_id = 0
	pending_lobby_id = 0
	lobby_owner_id = 0
	lobby_state = LobbyState.IDLE
	steam_peer = null


func _set_offline_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _emit_lobby_status(message: String, is_error: bool) -> void:
	lobby_status_changed.emit(message, is_error)


func _schedule_lobby_timeout(
	expected_state: int,
	timeout_seconds: float,
	message: String
) -> void:
	var scheduled_generation: int = lobby_operation_generation
	get_tree().create_timer(timeout_seconds).timeout.connect(
		func() -> void:
			if (
				lobby_operation_generation == scheduled_generation
				and lobby_state == expected_state
			):
				_fail_lobby_operation(message)
	)


func _get_lobby_join_error(response: int) -> String:
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
			return "That Steam lobby no longer exists."
		Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
			return "You are not allowed to join that Steam lobby."
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
			return "That Steam lobby is full."
		Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED:
			return "You are banned from that Steam lobby."
		Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED:
			return "This Steam account is not allowed to join lobbies."
		Steam.CHAT_ROOM_ENTER_RESPONSE_COMMUNITY_BAN:
			return "Steam community access is restricted for this account."
		Steam.CHAT_ROOM_ENTER_RESPONSE_MEMBER_BLOCKED_YOU:
			return "A lobby member has blocked you."
		Steam.CHAT_ROOM_ENTER_RESPONSE_YOU_BLOCKED_MEMBER:
			return "You have blocked a lobby member."
		Steam.CHAT_ROOM_ENTER_RESPONSE_RATE_LIMIT_EXCEEDED:
			return "Steam is rate-limiting lobby joins. Try again shortly."
		_:
			return "Steam could not join the lobby (response %d)." % response

@rpc("any_peer", "call_local", "reliable", 3)
func receive_jump(local_prediction_key := 0) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()

	if player == null:
		return

	if not player.on_floor:
		_reject_local_audio_prediction(player, local_prediction_key)
		return
	player.request_jump(local_prediction_key)


@rpc("any_peer", "call_local", "reliable", 3)
func use(yaw: float, pitch: float) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()
	if player == null:
		return

	player.set_look_direction(yaw, pitch)
	try_use(player)


@rpc("any_peer", "call_local", "reliable", 3)
func store_item_or_use(yaw: float, pitch: float) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player == null:
		return
	player.set_look_direction(yaw, pitch)
	try_store_item_or_use(player)


@rpc("any_peer", "call_local", "reliable", 3)
func equip_item(yaw: float, pitch: float) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player == null:
		return
	player.set_look_direction(yaw, pitch)
	try_equip_item(player)


@rpc("any_peer", "call_local", "reliable", 3)
func select_inventory_slot(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player == null:
		return
	player.select_inventory_slot(slot_index)


@rpc("any_peer", "call_local", "reliable", 3)
func drop_inventory_item() -> void:
	if not multiplayer.is_server():
		return
	try_drop_inventory_item(get_sending_player())


@rpc("any_peer", "call_local", "reliable", 3)
func drop_equipment(equipment_slot: String) -> void:
	if not multiplayer.is_server():
		return
	try_drop_equipment(get_sending_player(), equipment_slot)


@rpc("any_peer", "call_local", "reliable", 3)
func set_wrist_interface_open(value: bool, local_prediction_key := 0) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player != null:
		var changed := player.set_wrist_interface_open(
			value,
			local_prediction_key
		)
		if not changed:
			_reject_local_audio_prediction(player, local_prediction_key)
		Client.rpc(
			"on_player_wrist_state_received",
			FIELDLINK_DISPLAY_STATE.make_replication_packet(
				player.player_id,
				player.wrist_interface_open,
				player.wrist_display_page
			)
		)


@rpc("any_peer", "call_local", "reliable", 3)
func set_wrist_display_page(page_value: Variant) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player == null or not player.set_wrist_display_page(page_value):
		return
	Client.rpc(
		"on_player_wrist_state_received",
		FIELDLINK_DISPLAY_STATE.make_replication_packet(
			player.player_id,
			player.wrist_interface_open,
			player.wrist_display_page
		)
	)


@rpc("any_peer", "call_local", "reliable", 3)
func request_wrist_device_sound(
	sound_id: StringName,
	local_prediction_key := 0
) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player != null and not player.request_wrist_device_sound(
		sound_id,
		local_prediction_key
	):
		_reject_local_audio_prediction(player, local_prediction_key)


@rpc("any_peer", "call_local", "reliable", 3)
func request_fieldlink_device_control(contact_value: StringName) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	var contact_id := FieldlinkDeviceControlPacket.sanitize_contact_id(
		contact_value
	)
	if player == null or contact_id.is_empty():
		return
	var target := _validate_fieldlink_control_target(player, contact_id)
	if target == null:
		_send_fieldlink_control_error(player, contact_id, "DEVICE OUT OF RANGE OR OFFLINE")
		return
	_send_fieldlink_control_snapshot(player, contact_id, target)


@rpc("any_peer", "call_local", "reliable", 3)
func send_fieldlink_device_command(
	contact_value: StringName,
	action_value: StringName,
	payload_value: Dictionary
) -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player == null:
		return
	var command := FieldlinkDeviceControlPacket.sanitize_command(
		contact_value,
		action_value,
		payload_value
	)
	if command.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	if (
		now_msec
		< fieldlink_next_command_msec_by_player_id.get(player.player_id, 0)
	):
		return
	fieldlink_next_command_msec_by_player_id[player.player_id] = (
		now_msec + FIELDLINK_COMMAND_COOLDOWN_MILLISECONDS
	)
	var contact_id: StringName = command["contact_id"]
	var target := _validate_fieldlink_control_target(player, contact_id)
	if target == null:
		_send_fieldlink_control_error(player, contact_id, "DEVICE OUT OF RANGE OR OFFLINE")
		return
	target.call(
		"apply_fieldlink_command",
		player,
		command["action"],
		command["payload"]
	)
	_send_fieldlink_control_snapshot(player, contact_id, target)


@rpc("any_peer", "call_local", "reliable", 3)
func reload_selected_weapon() -> void:
	if not multiplayer.is_server():
		return
	var player := get_sending_player()
	if player != null:
		player.begin_reload_selected_gun()


@rpc("any_peer", "call_local", "reliable", 3)
func primary_action(
	yaw: float,
	pitch: float,
	prediction_session := 0
) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()
	if player == null:
		return

	player.set_look_direction(yaw, pitch)
	var prediction_key := (
		LOCAL_AUDIO_PREDICTION.weapon_shot_key(prediction_session, 0)
		if prediction_session > 0
		else 0
	)
	if not try_primary_action(player, prediction_key):
		_reject_local_audio_prediction(player, prediction_key)


@rpc("any_peer", "call_local", "reliable", 3)
func set_primary_action_held(
	held: bool,
	yaw: float,
	pitch: float,
	prediction_session := 0
) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()
	if player == null:
		return

	player.set_look_direction(yaw, pitch)
	player.set_primary_action_held(held, prediction_session)


@rpc("any_peer", "call_local", "reliable", 3)
func begin_grab(yaw: float, pitch: float) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()
	if player == null:
		return

	player.set_look_direction(yaw, pitch)
	try_begin_grab(player.grabber)


@rpc("any_peer", "call_local", "reliable", 3)
func release_grab() -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()
	if player == null:
		return

	end_grab(player.grabber)


@rpc("any_peer", "call_local", "reliable", 3)
func set_grab_rotation_active(active: bool, session_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()
	if player == null:
		return

	set_grabber_rotation_active(player.grabber, active, session_id)


@rpc("any_peer", "call_local", "unreliable_ordered", 3)
func receive_grab_rotation_input(
	session_id: int,
	input_target: Vector2
) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()
	if player == null:
		return

	set_grab_rotation_input_target(player.grabber, input_target, session_id)

@rpc("any_peer", "call_local", "unreliable")
func receive_player_input(
	move: Vector2,
	yaw: float,
	pitch: float,
	running: bool
) -> void:
	if not multiplayer.is_server():
		return

	var player := get_sending_player()

	if player == null:
		return

	player.set_input(
		move,
		yaw,
		pitch,
		running
	)
