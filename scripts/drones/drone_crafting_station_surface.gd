extends StaticBody3D

#######################################################
# Implements the drone crafting station surface subsystem and keeps its gameplay data and
# behavior in one focused script.
#######################################################

@export var station_path: NodePath = NodePath("..")


func server_primary_action(player: ServerPlayer, hit: Dictionary) -> void:
	var station: Node = get_node_or_null(station_path)
	if station != null and station.has_method("handle_surface_primary_action"):
		station.call("handle_surface_primary_action", player, hit)
