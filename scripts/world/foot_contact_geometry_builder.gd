class_name FootContactGeometryBuilder
extends RefCounted

## Builds client-side, presentation-only collision from the same descriptors and baked shapes used
## by authoritative structures. These bodies never block movement; they exist so every peer can
## solve procedural contacts locally without receiving per-foot transforms over the network.

const STRUCTURE_BUILDER := preload(
	"res://scripts/world/static_structure_collision_builder.gd"
)


static func build_clustered_boxes(
	parent: Node3D,
	descriptors: Array[Dictionary],
	body_prefix := "FootContact"
) -> Array[StaticBody3D]:
	var bodies := STRUCTURE_BUILDER.build_clustered_box_bodies(
		parent,
		descriptors,
		&"concrete",
		null,
		body_prefix
	)
	_mark_detail_only(bodies)
	return bodies


static func build_baked_props(
	parent: Node3D,
	descriptors: Array[Dictionary],
	shapes_by_asset: Dictionary,
	surfaces_by_asset: Dictionary,
	default_surface := &"concrete"
) -> Array[StaticBody3D]:
	var bodies := STRUCTURE_BUILDER.build_baked_prop_bodies(
		parent,
		descriptors,
		shapes_by_asset,
		surfaces_by_asset,
		default_surface
	)
	_mark_detail_only(bodies)
	return bodies


static func add_box(
	parent: Node3D,
	node_name: String,
	local_position: Vector3,
	size: Vector3,
	local_rotation := Vector3.ZERO
) -> StaticBody3D:
	if parent == null or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return null
	var body := DetailedFootContactSurface3D.new()
	body.name = node_name.validate_node_name()
	body.position = local_position
	body.rotation = local_rotation
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "Contact"
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body


static func _mark_detail_only(bodies: Array[StaticBody3D]) -> void:
	for body: StaticBody3D in bodies:
		body.collision_layer = CharacterContactLayers.FOOT_CONTACT_DETAIL
		body.collision_mask = 0
		body.add_to_group(&"foot_contact_geometry")
