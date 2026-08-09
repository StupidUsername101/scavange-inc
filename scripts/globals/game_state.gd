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
	max_players: int = -1
) -> int:
	if player_id_by_peer_id.has(peer_id):
		return -1
	if (
		max_players >= 0
		and player_id_by_peer_id.size() >= max_players
	):
		return -1
	
	next_player_id += 1
	var player_id = next_player_id
	var state = PlayerState.new(
		player_id, 
		peer_id, 
		default_money
	)
	
	player_id_by_peer_id[peer_id] = player_id
	peers_by_player_id[player_id] = state
	player_input_by_player_id[player_id] = Vector2.ZERO
	return player_id
	
func unregister_peer(peer_id: int) -> void:
	if not player_id_by_peer_id.has(peer_id):
		return

	var player_id = player_id_by_peer_id[peer_id]
		
	player_id_by_peer_id.erase(peer_id)
	peers_by_player_id.erase(player_id)
	player_input_by_player_id.erase(player_id)

func get_player_count() -> int:
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
