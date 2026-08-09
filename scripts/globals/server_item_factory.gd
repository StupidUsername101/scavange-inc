extends Node

#######################################################
# Owns authoritative item factory simulation and exposes the state required for replication
# and interaction.
#######################################################

static var next_item_id: int = 0

func get_next_id() -> int:
	next_item_id += 1
	return next_item_id
