extends StaticBody3D

#######################################################
# Implements the drone station button subsystem and keeps its gameplay data and behavior in
# one focused script.
#######################################################

@export var action: StringName
@export var station_path: NodePath = NodePath("../..")


func server_use(player: ServerPlayer, _hit: Dictionary) -> void:
	var station := get_node_or_null(station_path)
	if station != null and station.has_method("handle_button"):
		station.call("handle_button", action, player)


func server_primary_action(player: ServerPlayer, hit: Dictionary) -> void:
	server_use(player, hit)
