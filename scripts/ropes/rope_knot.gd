class_name RopeKnot
extends AnimatableBody3D

const KNOT_COLLISION_LAYER := 128

#######################################################
# Implements the rope knot subsystem and keeps its gameplay data and behavior in one focused
# script.
#######################################################

var rope_id := -1


func configure(new_rope_id: int, radius: float) -> void:
	rope_id = new_rope_id
	collision_layer = KNOT_COLLISION_LAYER
	collision_mask = 0
	add_to_group("rope_knots")
	var shape := SphereShape3D.new()
	shape.radius = maxf(radius * 2.2, 0.055)
	var collision := CollisionShape3D.new()
	collision.name = "KnotCollision"
	collision.shape = shape
	add_child(collision)


func server_use(_player: ServerPlayer, _hit: Dictionary) -> void:
	Server.detach_rope(rope_id)
