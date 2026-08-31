extends RefCounted
class_name PlayerState

#######################################################
# Stores mutable player runtime state and serializes the fields shared between authoritative
# and presentation systems.
#######################################################

var player_id: int
var peer_id: int
var steam_id: int
var connected: bool
var money: int = 0

func _init(
	_player_id: int = -1,
	_peer_id: int = -1,
	_money: int = 0,
	_steam_id: int = 0
) -> void:
	player_id = _player_id
	peer_id = _peer_id
	steam_id = _steam_id
	connected = _peer_id > 0
	money = _money
	
func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"peer_id": peer_id,
		"steam_id": steam_id,
		"connected": connected,
		"money": money
	}
	
func from_dict(data: Dictionary) -> PlayerState:
	var state := PlayerState.new()

	state.player_id = data.get("player_id", -1)
	state.peer_id = data.get("peer_id", -1)
	state.steam_id = data.get("steam_id", 0)
	state.connected = data.get("connected", state.peer_id > 0)
	state.money = data.get("money", 0)

	return state
