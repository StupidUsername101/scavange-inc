class_name TrainingItemDeliveryDestination3D
extends Node3D

#######################################################
# Authored delivery volume shared by all training body types. Policy/acceptance lives on the
# destination group in DroneTrainingRoom; this node only owns one placed volume and exposes a
# stable world/task address. It deliberately has no blocking collision body so a delivery zone
# never changes locomotion physics merely by existing.
#######################################################

const ENTITY_KIND: StringName = &"delivery_destination"
const TARGET_KIND: String = "cargo_delivery"

var destination_group_id: int = 0
var destination_id: int = 0
var radius_m: float = 1.25
var height_m: float = 1.25
var spawn_transform_world: Transform3D = Transform3D.IDENTITY
var display_color: Color = Color("54e6b1")
var selected: bool = false


func configure_destination(
	group_id: int,
	placed_destination_id: int,
	new_radius_m: float,
	new_height_m: float,
	new_transform: Transform3D,
	color: Color
) -> void:
	destination_group_id = maxi(group_id, 1)
	destination_id = maxi(placed_destination_id, 1)
	radius_m = maxf(RLTrainingMath.finite_float_or(new_radius_m, 1.25), 0.10)
	height_m = maxf(RLTrainingMath.finite_float_or(new_height_m, 1.25), 0.10)
	display_color = color if is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a) else Color("54e6b1")
	spawn_transform_world = _sanitized_transform(new_transform)
	global_transform = spawn_transform_world
	set_meta("training_delivery_destination", true)
	set_meta("delivery_destination_group_id", destination_group_id)
	set_meta("delivery_destination_id", destination_id)
	set_meta("delivery_destination_stable_id", stable_id())
	_rebuild_visual()


func stable_id() -> String:
	return "training_delivery:%d:%d" % [destination_group_id, destination_id]


func spatial_key() -> StringName:
	return StringName("training:delivery:%d:%d" % [destination_group_id, destination_id])


func target_position_world() -> Vector3:
	return global_position + global_basis.y.normalized() * (height_m * 0.5)


func target_candidate(metadata: Dictionary = {}) -> Dictionary:
	var copied_metadata: Dictionary = metadata.duplicate(false)
	copied_metadata["delivery_destination_group_id"] = destination_group_id
	copied_metadata["delivery_destination_id"] = destination_id
	copied_metadata["task_role"] = "delivery_destination"
	return {
		"available": is_inside_tree() and global_position.is_finite(),
		"stable_id": stable_id(),
		"target_kind": TARGET_KIND,
		"task_role": "delivery_destination",
		"shootable": false,
		"position_world": target_position_world(),
		"velocity_world": Vector3.ZERO,
		"radius_m": radius_m,
		"priority_bias": 0.0,
		"urgency": 0.0,
		"distance_weight": 1.0,
		"metadata": copied_metadata,
	}


func contains_item(item: TrainingItem3D) -> bool:
	if not is_instance_valid(item):
		return false
	var local_position: Vector3 = global_transform.affine_inverse() * item.global_position
	if not local_position.is_finite():
		return false
	var item_vertical_extent: float = _item_vertical_support_extent(item)
	var horizontal_distance: float = Vector2(local_position.x, local_position.z).length()
	# Requiring the center to cross the nominal radius avoids credit while a huge item merely
	# brushes the outside edge. Vertical tolerance uses the primitive's actual support extent along
	# this destination's up axis; a very wide flat crate must not count as several metres tall just
	# because its enclosing bounding sphere is large.
	if horizontal_distance > radius_m:
		return false
	return (
		local_position.y >= -item_vertical_extent
		and local_position.y <= height_m + item_vertical_extent
	)


func distance_to_item(item: TrainingItem3D) -> float:
	if not is_instance_valid(item):
		return INF
	# Delivery shaping uses distance to the *accepted volume*, not distance to its centre. Once an
	# item is validly inside the bay the potential is exactly zero, so harmless motion within the
	# destination cannot create approach reward or a penalty after completion. Outside the bay, this
	# is the Euclidean distance to the nearest point of the same cylindrical acceptance region used
	# by contains_item().
	var local_position: Vector3 = global_transform.affine_inverse() * item.global_position
	if not local_position.is_finite():
		return INF
	var item_vertical_extent: float = _item_vertical_support_extent(item)
	var horizontal_distance: float = Vector2(local_position.x, local_position.z).length()
	var horizontal_excess: float = maxf(horizontal_distance - radius_m, 0.0)
	var vertical_excess: float = 0.0
	if local_position.y < -item_vertical_extent:
		vertical_excess = -item_vertical_extent - local_position.y
	elif local_position.y > height_m + item_vertical_extent:
		vertical_excess = local_position.y - (height_m + item_vertical_extent)
	return sqrt(horizontal_excess * horizontal_excess + vertical_excess * vertical_excess)


func _item_vertical_support_extent(item: TrainingItem3D) -> float:
	if not is_instance_valid(item):
		return 0.0
	var destination_up: Vector3 = global_basis.y
	if not destination_up.is_finite() or destination_up.length_squared() <= 0.000001:
		destination_up = Vector3.UP
	return maxf(
		DroneTrainingObstacleShape.support_extent_world(
			item.shape_kind,
			item.dimensions,
			item.global_transform.basis,
			destination_up
		),
		0.0
	)


func set_selected(value: bool) -> void:
	selected = value
	_apply_visual_material()


func environment_record() -> Dictionary:
	var rotation_degrees: Vector3 = spawn_transform_world.basis.get_euler() * (180.0 / PI)
	return {
		"destination_id": destination_id,
		"position_m": [
			spawn_transform_world.origin.x,
			spawn_transform_world.origin.y,
			spawn_transform_world.origin.z,
		],
		"rotation_degrees": [
			rotation_degrees.x,
			rotation_degrees.y,
			rotation_degrees.z,
		],
	}


func _rebuild_visual() -> void:
	var visual: MeshInstance3D = get_node_or_null("Volume") as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = "Volume"
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius_m
	mesh.bottom_radius = radius_m
	mesh.height = height_m
	mesh.radial_segments = 40
	visual.mesh = mesh
	visual.position = Vector3.UP * (height_m * 0.5)
	_apply_visual_material()


func _apply_visual_material() -> void:
	var visual: MeshInstance3D = get_node_or_null("Volume") as MeshInstance3D
	if visual == null:
		return
	var alpha: float = 0.34 if selected else 0.18
	var color: Color = Color(display_color.r, display_color.g, display_color.b, alpha)
	visual.material_override = DroneTrainingRoomPresentation.material(color, true)


static func _sanitized_transform(value: Transform3D) -> Transform3D:
	if (
		not value.origin.is_finite()
		or not value.basis.is_finite()
		or value.basis.determinant() <= 0.000001
	):
		return Transform3D.IDENTITY
	return Transform3D(value.basis.orthonormalized(), value.origin)
