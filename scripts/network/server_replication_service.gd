class_name ServerReplicationService
extends RefCounted

const REPLICATION_SCHEDULE := preload(
	"res://scripts/network/network_replication_schedule.gd"
)
const SNAPSHOT_STREAM_TRACKER := preload(
	"res://scripts/network/network_snapshot_stream_tracker.gd"
)
const LOCAL_AUDIO_PREDICTION := preload(
	"res://scripts/audio/local_audio_prediction.gd"
)
const RADIO_STATE_SNAPSHOT_CODEC := preload(
	"res://scripts/audio/radio_state_snapshot_codec.gd"
)
const PROJECTILE_SNAPSHOT_STREAM := &"projectiles"
const DRONE_PART_SNAPSHOT_STREAM := &"drone_parts"
const ENEMY_SNAPSHOT_STREAM := &"enemies"
const ROPE_SNAPSHOT_STREAM := &"ropes"

#######################################################
# Owns authoritative snapshot cadence, sequencing, optional-stream lifecycle, and publication.
# Gameplay entities remain owned by the server coordinator; this service only reads their state.
#######################################################

var coordinator
var stream_tracker := SNAPSHOT_STREAM_TRACKER.new()
var snapshot_sequence := 0
var item_motion_sequence := 0


func bind(owner: Node) -> void:
	assert(owner != null)
	assert(owner.has_method("get_server_player"))
	assert(owner.has_method("_is_rpc_peer_reachable"))
	assert(owner.has_method("_get_rope_placement_state"))
	coordinator = owner


func publish_states() -> void:
	if coordinator == null:
		return
	var current_sequence := snapshot_sequence
	snapshot_sequence += 1
	_publish_player_states(current_sequence)
	_publish_item_states(current_sequence)
	_publish_drone_states(current_sequence)
	_publish_projectile_states(current_sequence)
	_publish_radio_states()
	if REPLICATION_SCHEDULE.is_due(
		current_sequence,
		REPLICATION_SCHEDULE.LOCAL_AUDIO_CONTEXT_INTERVAL_TICKS
	):
		_publish_local_audio_prediction_contexts()
	if REPLICATION_SCHEDULE.is_due(
		current_sequence,
		REPLICATION_SCHEDULE.BULK_PHYSICS_INTERVAL_TICKS
	):
		_publish_drone_part_states(current_sequence)
		_publish_enemy_states(current_sequence)
		_publish_rope_states(current_sequence)
	if REPLICATION_SCHEDULE.is_due(
		current_sequence,
		REPLICATION_SCHEDULE.STATION_INTERVAL_TICKS
	):
		_publish_station_states(current_sequence)


func publish_grabbed_item_motion_states() -> void:
	item_motion_sequence += 1
	if coordinator == null or coordinator.grab_states_by_grabber_id.is_empty():
		return
	var states: Dictionary = {}
	for grab_state: GrabState in coordinator.grab_states_by_grabber_id.values():
		if (
			grab_state == null
			or not is_instance_valid(grab_state.grabber)
			or not is_instance_valid(grab_state.body)
			or not grab_state.body is ServerItem
		):
			continue
		var item := grab_state.body as ServerItem
		var state := item.to_motion_state_dict()
		state["item_motion_sequence"] = item_motion_sequence
		state["grabber_player_id"] = _grabber_player_id(grab_state.grabber)
		states[item.item_id] = state
	if states.is_empty():
		return
	# The listen-server presentation follows its authoritative body directly; only remote peers
	# need serialized interpolation deltas.
	for peer_id: int in coordinator.multiplayer.get_peers():
		Client.rpc_id(
			peer_id,
			"on_grabbed_item_motion_states_received",
			states
		)


func force_optional_snapshot_refresh() -> void:
	# A joining client clears all proxy registries before admission. Force one current publication;
	# active streams carry their entities and empty streams explicitly confirm there is no stale state.
	stream_tracker.force_next_publish(PROJECTILE_SNAPSHOT_STREAM)
	stream_tracker.force_next_publish(DRONE_PART_SNAPSHOT_STREAM)
	stream_tracker.force_next_publish(ENEMY_SNAPSHOT_STREAM)
	stream_tracker.force_next_publish(ROPE_SNAPSHOT_STREAM)


func publish_all_player_inventories_to_peer(peer_id: int) -> void:
	if coordinator == null or not coordinator._is_rpc_peer_reachable(peer_id):
		return
	for player_id: int in coordinator.server_players_by_player_id:
		publish_player_inventory_state(player_id, peer_id)


func publish_player_inventory_state(player_id: int, peer_id := 0) -> void:
	if coordinator == null:
		return
	var player: ServerPlayer = coordinator.get_server_player(player_id) as ServerPlayer
	if player == null:
		return
	var inventory: Dictionary = player._get_public_inventory_state()
	if peer_id > 0:
		if coordinator._is_rpc_peer_reachable(peer_id):
			Client.rpc_id(
				peer_id,
				"on_player_inventory_state_received",
				player_id,
				player.inventory_revision,
				inventory
			)
		return
	Client.rpc(
		"on_player_inventory_state_received",
		player_id,
		player.inventory_revision,
		inventory
	)


func reset() -> void:
	stream_tracker.reset()
	snapshot_sequence = 0
	item_motion_sequence = 0


func _publish_player_states(current_sequence: int) -> void:
	var states: Dictionary = {}
	for player_id: int in coordinator.server_players_by_player_id:
		var player: ServerPlayer = coordinator.server_players_by_player_id[player_id]
		if not is_instance_valid(player):
			continue
		states[player_id] = _sequence_state(
			player.to_state_dict(false),
			current_sequence
		)
	Client.rpc("on_player_states_received", states)


func _publish_item_states(current_sequence: int) -> void:
	var states: Dictionary = {}
	var grabber_player_ids := _grabbed_item_player_ids()
	for item_id: int in coordinator.server_items_by_item_id:
		var item: ServerItem = coordinator.server_items_by_item_id[item_id]
		if not is_instance_valid(item):
			continue
		var state := _sequence_state(item.to_state_dict(), current_sequence)
		state["item_motion_sequence"] = item_motion_sequence
		state["grabber_player_id"] = int(grabber_player_ids.get(item_id, -1))
		states[item_id] = state
	Client.rpc("on_item_states_received", states)


func _publish_drone_states(current_sequence: int) -> void:
	var states: Dictionary = {}
	for drone_id: int in coordinator.server_drones_by_drone_id:
		var drone: ServerDrone = coordinator.server_drones_by_drone_id[drone_id]
		if not is_instance_valid(drone) or not drone.network_visible:
			continue
		states[drone_id] = _sequence_state(drone.to_state_dict(), current_sequence)
	Client.rpc("on_drone_states_received", states)


func _publish_projectile_states(current_sequence: int) -> void:
	if coordinator.server_projectiles_by_id.is_empty():
		if stream_tracker.should_publish(PROJECTILE_SNAPSHOT_STREAM, false):
			Client.rpc("on_projectile_states_received", {})
		return
	var states: Dictionary = {}
	for projectile_id: int in coordinator.server_projectiles_by_id:
		var projectile: ServerProjectile = (
			coordinator.server_projectiles_by_id[projectile_id]
		)
		if is_instance_valid(projectile):
			states[projectile_id] = _sequence_state(
				projectile.to_state_dict(),
				current_sequence
			)
	if stream_tracker.should_publish(
		PROJECTILE_SNAPSHOT_STREAM,
		not states.is_empty()
	):
		Client.rpc("on_projectile_states_received", states)


func _publish_drone_part_states(current_sequence: int) -> void:
	if coordinator.server_drone_parts_by_id.is_empty():
		if stream_tracker.should_publish(DRONE_PART_SNAPSHOT_STREAM, false):
			Client.rpc("on_drone_part_states_received", {})
		return
	var states: Dictionary = {}
	for part_id: int in coordinator.server_drone_parts_by_id:
		var part: RigidBody3D = coordinator.server_drone_parts_by_id[part_id]
		if is_instance_valid(part):
			states[part_id] = _sequence_state(
				part.call("to_state_dict") as Dictionary,
				current_sequence
			)
	if stream_tracker.should_publish(
		DRONE_PART_SNAPSHOT_STREAM,
		not states.is_empty()
	):
		Client.rpc("on_drone_part_states_received", states)


func _publish_enemy_states(current_sequence: int) -> void:
	if coordinator.server_enemies_by_enemy_id.is_empty():
		if stream_tracker.should_publish(ENEMY_SNAPSHOT_STREAM, false):
			Client.rpc("on_enemy_states_received", {})
		return
	var states: Dictionary = {}
	for enemy_id: int in coordinator.server_enemies_by_enemy_id:
		var enemy: ServerEnemy = coordinator.server_enemies_by_enemy_id[enemy_id]
		if is_instance_valid(enemy):
			states[enemy_id] = _sequence_state(
				enemy.to_state_dict(),
				current_sequence
			)
	if stream_tracker.should_publish(ENEMY_SNAPSHOT_STREAM, not states.is_empty()):
		Client.rpc("on_enemy_states_received", states)


func _publish_rope_states(current_sequence: int) -> void:
	if (
		coordinator.server_ropes_by_rope_id.is_empty()
		and coordinator.rope_placements_by_player_id.is_empty()
	):
		if stream_tracker.should_publish(ROPE_SNAPSHOT_STREAM, false):
			Client.rpc("on_rope_states_received", {})
		return
	var states: Dictionary = {}
	for rope_id: int in coordinator.server_ropes_by_rope_id:
		var rope: ServerRope = coordinator.server_ropes_by_rope_id[rope_id]
		if is_instance_valid(rope):
			states[rope_id] = _sequence_state(
				rope.to_state_dict(),
				current_sequence
			)
	for player_id: int in coordinator.rope_placements_by_player_id:
		var preview_state: Dictionary = coordinator._get_rope_placement_state(player_id)
		if not preview_state.is_empty():
			states[-player_id - 1] = _sequence_state(
				preview_state,
				current_sequence
			)
	if stream_tracker.should_publish(ROPE_SNAPSHOT_STREAM, not states.is_empty()):
		Client.rpc("on_rope_states_received", states)


func _publish_station_states(current_sequence: int) -> void:
	var inspection_states: Dictionary = {}
	for station_id: int in coordinator.inspection_stations_by_id:
		var station: Node3D = coordinator.inspection_stations_by_id[station_id]
		if is_instance_valid(station):
			inspection_states[station_id] = _sequence_state(
				station.call("to_state_dict") as Dictionary,
				current_sequence
			)
	Client.rpc("on_inspection_station_states_received", inspection_states)

	var body_shop_states: Dictionary = {}
	for terminal_id: int in coordinator.body_part_shop_terminals_by_id:
		var terminal: Node3D = coordinator.body_part_shop_terminals_by_id[terminal_id]
		if is_instance_valid(terminal):
			body_shop_states[terminal_id] = _sequence_state(
				terminal.call("to_state_dict") as Dictionary,
				current_sequence
			)
	Client.rpc("on_body_part_shop_states_received", body_shop_states)

	var weapon_states: Dictionary = {}
	for station_id: int in coordinator.weapon_crafting_stations_by_id:
		var weapon_station: Node3D = (
			coordinator.weapon_crafting_stations_by_id[station_id]
		)
		if is_instance_valid(weapon_station):
			weapon_states[station_id] = _sequence_state(
				weapon_station.call("to_state_dict") as Dictionary,
				current_sequence
			)
	Client.rpc("on_weapon_crafting_station_states_received", weapon_states)


func _publish_radio_states() -> void:
	for player_id: int in coordinator.server_players_by_player_id:
		var listener: ServerPlayer = coordinator.server_players_by_player_id[player_id]
		if not is_instance_valid(listener):
			continue
		var player_state := GameState.get_player_state(player_id)
		if (
			player_state == null
			or not coordinator._is_rpc_peer_reachable(player_state.peer_id)
		):
			continue
		var radio_states: Dictionary = {}
		var listener_position: Vector3 = listener.get_audio_listener_position()
		for radio_id: int in coordinator.server_radios_by_item_id:
			var radio: ServerRadio = coordinator.server_radios_by_item_id[radio_id]
			if not is_instance_valid(radio) or not radio.powered:
				continue
			var state := radio.build_listener_state(
				player_id,
				listener_position,
				coordinator.acoustic_service,
				listener.get_rid()
			)
			if not state.is_empty():
				radio_states[radio.item_id] = state
		for cluster: Node3D in coordinator.server_speaker_clusters:
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
				coordinator.acoustic_service,
				listener.get_rid()
			)
		var payload := RADIO_STATE_SNAPSHOT_CODEC.encode(radio_states)
		if payload.is_empty():
			push_warning("Continuous audio snapshot exceeded its bounded wire contract")
			continue
		# Starts, stops, and continuous updates share one replaceable ordered lane. A reliable second
		# lane can overtake these snapshots and re-excite a populated room return with stale state.
		Client.rpc_id(
			player_state.peer_id,
			"on_radio_states_received",
			payload
		)


func _publish_local_audio_prediction_contexts() -> void:
	if not LOCAL_AUDIO_PREDICTION.ENABLED:
		return
	for player_id: int in coordinator.server_players_by_player_id:
		var listener: ServerPlayer = coordinator.server_players_by_player_id[player_id]
		if not is_instance_valid(listener):
			continue
		var player_state := GameState.get_player_state(player_id)
		if (
			player_state == null
			or not coordinator._is_rpc_peer_reachable(player_state.peer_id)
		):
			continue
		var context: Dictionary = coordinator.acoustic_service.build_local_prediction_context(
			player_id,
			listener.get_audio_listener_position(),
			listener.get_rid()
		)
		if not context.is_empty():
			Client.rpc_id(
				player_state.peer_id,
				"on_local_audio_prediction_context_received",
				context
			)


func _grabbed_item_player_ids() -> Dictionary[int, int]:
	var result: Dictionary[int, int] = {}
	for grab_state: GrabState in coordinator.grab_states_by_grabber_id.values():
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


static func _grabber_player_id(grabber: GrabberComponent) -> int:
	if grabber == null or not is_instance_valid(grabber):
		return -1
	var carrier := grabber.get_carrier_body() as ServerPlayer
	return carrier.player_id if carrier != null else -1


static func _sequence_state(
	state: Dictionary,
	current_sequence: int
) -> Dictionary:
	state["network_snapshot_sequence"] = current_sequence
	return state
