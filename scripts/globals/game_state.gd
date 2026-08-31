extends Node

#######################################################
# Stores mutable game runtime state and serializes the fields shared between authoritative and
# presentation systems.
#######################################################

var player_input_by_player_id: Dictionary[int, Vector2] = {}

var player_id_by_peer_id: Dictionary[int, int] = {}
var peers_by_player_id: Dictionary[int, PlayerState] = {} 
var drone_id_by_player_id: Dictionary[int, int] = {}
var drones_by_drone_id: Dictionary[int, DroneState] = {}

var next_drone_id: int = 0
var next_player_id: int = 0


func reset_session() -> void:
	player_input_by_player_id.clear()
	player_id_by_peer_id.clear()
	peers_by_player_id.clear()
	drone_id_by_player_id.clear()
	drones_by_drone_id.clear()
	next_drone_id = 0
	next_player_id = 0

func set_player_input_for_player_id(id: int, input: Vector2):
	player_input_by_player_id[id] = input

func get_player_id(peer_id: int) -> int:
	if not player_id_by_peer_id.has(peer_id):
		return -1
		
	return player_id_by_peer_id[peer_id]

## registers peer_id in dict. true if successfull, false if peer_id already in dict
## false may indicate a reconnecting player
func try_register_player(
	peer_id: int,
	default_money: int,
	max_players: int = -1,
	steam_id: int = 0
) -> int:
	if player_id_by_peer_id.has(peer_id):
		return -1
	if (
		max_players >= 0
		and peers_by_player_id.size() >= max_players
	):
		return -1
	
	next_player_id += 1
	var player_id = next_player_id
	var state = PlayerState.new(
		player_id, 
		peer_id, 
		default_money,
		steam_id
	)
	
	player_id_by_peer_id[peer_id] = player_id
	peers_by_player_id[player_id] = state
	player_input_by_player_id[player_id] = Vector2.ZERO
	return player_id
	
func unregister_peer(peer_id: int) -> void:
	if not player_id_by_peer_id.has(peer_id):
		return

	unregister_player(player_id_by_peer_id[peer_id])


func unregister_player(player_id: int) -> void:
	var state := get_player_state(player_id)
	if state == null:
		return
	if state.peer_id > 0:
		player_id_by_peer_id.erase(state.peer_id)
	peers_by_player_id.erase(player_id)
	player_input_by_player_id.erase(player_id)


func suspend_peer(peer_id: int) -> int:
	var player_id := get_player_id(peer_id)
	if player_id < 0:
		return -1
	var state := get_player_state(player_id)
	player_id_by_peer_id.erase(peer_id)
	player_input_by_player_id[player_id] = Vector2.ZERO
	if state != null:
		state.peer_id = -1
		state.connected = false
	return player_id


func rebind_player_peer(player_id: int, peer_id: int) -> bool:
	if peer_id <= 0 or player_id_by_peer_id.has(peer_id):
		return false
	var state := get_player_state(player_id)
	if state == null or state.connected:
		return false
	state.peer_id = peer_id
	state.connected = true
	player_id_by_peer_id[peer_id] = player_id
	player_input_by_player_id[player_id] = Vector2.ZERO
	return true


func get_player_id_for_steam_id(steam_id: int) -> int:
	if steam_id <= 0:
		return -1
	for player_id: int in peers_by_player_id:
		var state := peers_by_player_id[player_id] as PlayerState
		if state != null and state.steam_id == steam_id:
			return player_id
	return -1

func get_player_count() -> int:
	# Disconnected players retain their slot for the bounded reconnect lease.
	return peers_by_player_id.size()


func get_connected_player_count() -> int:
	return player_id_by_peer_id.size()


func get_player_state(player_id: int) -> PlayerState:
	return peers_by_player_id.get(player_id) as PlayerState


func get_player_money(player_id: int) -> int:
	var state := get_player_state(player_id)
	return state.money if state != null else 0


func try_spend_player_money(player_id: int, amount: int) -> bool:
	if amount < 0:
		return false
	var state := get_player_state(player_id)
	if state == null or state.money < amount:
		return false
	state.money -= amount
	return true


func add_player_money(player_id: int, amount: int) -> void:
	if amount <= 0:
		return
	var state := get_player_state(player_id)
	if state != null:
		state.money += amount
	
func serialize_peers() -> Dictionary:
	var result := {}
	
	for player_id in peers_by_player_id.keys():
		result[player_id] = peers_by_player_id[player_id].to_dict()
		
	return result
