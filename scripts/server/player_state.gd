extends RefCounted
class_name PlayerState

#######################################################
# Stores mutable player runtime state and serializes the fields shared between authoritative
# and presentation systems.
#######################################################

var player_id: int
var peer_id: int
var money: int = 0

func _init(
	_player_id: int = -1,
	_peer_id: int = -1,
	_money: int = 0
) -> void:
	player_id = _player_id
	peer_id = _peer_id
	money = _money
	
func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"peer_id": peer_id,
		"money": money
	}
	
func from_dict(data: Dictionary) -> PlayerState:
	var state := PlayerState.new()

	state.player_id = data.get("player_id", -1)
	state.peer_id = data.get("peer_id", -1)
	state.money = data.get("money", 0)

	return state
