extends RefCounted
class_name DroneState

#######################################################
# Stores mutable drone runtime state and serializes the fields shared between authoritative
# and presentation systems.
#######################################################

var _drone_id: int

func _init(
	drone_id: int = -1
	) -> void:
	_drone_id = drone_id

func to_dict() -> Dictionary:
	return {
		"drone_id": _drone_id
	}
	
func from_dict(data: Dictionary):
	var state = DroneState.new()
	
	state._drone_id = data["drone_id"]
	return state
