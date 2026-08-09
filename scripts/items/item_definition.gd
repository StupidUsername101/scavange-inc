@tool
extends Resource
class_name ItemDefinition

#######################################################
# Defines the serialized item configuration shared by gameplay, inspection, and replication
# systems.
#######################################################

@export_group("Identity")
@export var display_name := "New Item":
	set(value):
		display_name = value
		emit_changed()

@export var inventory_code := "":
	set(value):
		inventory_code = value.left(3).to_upper()
		emit_changed()
		
@export_group("Sizing")
@export var sync_size_sliders := true
@export_range(0.01, 10.0, 0.01, "or_greater") var overall_size := 1.0:
	set(value):
		overall_size = value
		emit_changed()

var _syncing_mesh_size := false
var _syncing_shape_size := false

@export_group("Physics")
@export_range(0.01, 1000.0, 0.01, "or_greater") var mass := 1.0:
	set(value):
		mass = value
		emit_changed()

@export_group("Grip")
@export var grippable := true:
	set(value):
		grippable = value
		emit_changed()

@export var grip_surface_tags: PackedStringArray = PackedStringArray(["carryable"]):
	set(value):
		grip_surface_tags = _sanitized_grip_surface_tags(value)
		emit_changed()

@export_group("Mesh")
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		emit_changed()

@export var material_override: Material:
	set(value):
		material_override = value
		emit_changed()

@export var mesh_position := Vector3.ZERO:
	set(value):
		mesh_position = value
		emit_changed()

@export_subgroup("Rotation")
@export_range(0.0, 360.0, 1.0) var mesh_rotation_x := 0.0:
	set(value):
		mesh_rotation_x = value
		emit_changed()

@export_range(0.0, 360.0, 1.0) var mesh_rotation_y := 0.0:
	set(value):
		mesh_rotation_y = value
		emit_changed()

@export_range(0.0, 360.0, 1.0) var mesh_rotation_z := 0.0:
	set(value):
		mesh_rotation_z = value
		emit_changed()

@export_subgroup("Size")
@export_range(0.01, 100.0, 0.01, "or_greater") var mesh_size_x := 1.0:
	set(value):
		mesh_size_x = value

		if sync_size_sliders and not _syncing_mesh_size:
			_syncing_mesh_size = true
			mesh_size_y = value
			mesh_size_z = value
			_syncing_mesh_size = false

		emit_changed()

@export_range(0.01, 100.0, 0.01, "or_greater") var mesh_size_y := 1.0:
	set(value):
		mesh_size_y = value

		if sync_size_sliders and not _syncing_mesh_size:
			_syncing_mesh_size = true
			mesh_size_x = value
			mesh_size_z = value
			_syncing_mesh_size = false

		emit_changed()

@export_range(0.01, 100.0, 0.01, "or_greater") var mesh_size_z := 1.0:
	set(value):
		mesh_size_z = value

		if sync_size_sliders and not _syncing_mesh_size:
			_syncing_mesh_size = true
			mesh_size_x = value
			mesh_size_y = value
			_syncing_mesh_size = false

		emit_changed()

@export_group("Collision")
@export var collision_shape: Shape3D:
	set(value):
		collision_shape = value
		emit_changed()

@export var shape_position := Vector3.ZERO:
	set(value):
		shape_position = value
		emit_changed()

@export_subgroup("Rotation")
@export_range(0.0, 360.0, 1.0) var shape_rotation_x := 0.0:
	set(value):
		shape_rotation_x = value
		emit_changed()

@export_range(0.0, 360.0, 1.0) var shape_rotation_y := 0.0:
	set(value):
		shape_rotation_y = value
		emit_changed()

@export_range(0.0, 360.0, 1.0) var shape_rotation_z := 0.0:
	set(value):
		shape_rotation_z = value
		emit_changed()

@export_subgroup("Size")
@export_range(0.01, 100.0, 0.01, "or_greater") var shape_size_x := 1.0:
	set(value):
		shape_size_x = value

		if sync_size_sliders and not _syncing_shape_size:
			_syncing_shape_size = true
			shape_size_y = value
			shape_size_z = value
			_syncing_shape_size = false

		emit_changed()

@export_range(0.01, 100.0, 0.01, "or_greater") var shape_size_y := 1.0:
	set(value):
		shape_size_y = value

		if sync_size_sliders and not _syncing_shape_size:
			_syncing_shape_size = true
			shape_size_x = value
			shape_size_z = value
			_syncing_shape_size = false

		emit_changed()

@export_range(0.01, 100.0, 0.01, "or_greater") var shape_size_z := 1.0:
	set(value):
		shape_size_z = value

		if sync_size_sliders and not _syncing_shape_size:
			_syncing_shape_size = true
			shape_size_x = value
			shape_size_y = value
			_syncing_shape_size = false

		emit_changed()


func get_grip_surface_tags() -> PackedStringArray:
	return _sanitized_grip_surface_tags(grip_surface_tags) if grippable else PackedStringArray()


static func _sanitized_grip_surface_tags(value: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_tag: String in value:
		var tag := raw_tag.strip_edges()
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	return result


func instantiate_visual() -> Node3D:
	var visual_root := Node3D.new()
	visual_root.name = "ItemVisual"
	visual_root.position = mesh_position * overall_size
	visual_root.rotation_degrees = Vector3(
		mesh_rotation_x,
		mesh_rotation_y,
		mesh_rotation_z
	)
	visual_root.scale = Vector3(
		mesh_size_x,
		mesh_size_y,
		mesh_size_z
	) * overall_size

	if visual_scene == null:
		return visual_root

	var visual := visual_scene.instantiate()
	visual_root.add_child(visual)

	if material_override != null:
		_apply_material_override(visual)

	return visual_root


func instantiate_visual_from_state(_state: Dictionary) -> Node3D:
	return instantiate_visual()


func make_default_instance_state() -> Dictionary:
	return {}


func normalize_instance_state(state: Dictionary) -> Dictionary:
	return state.duplicate(true)


func get_public_instance_state(_state: Dictionary) -> Dictionary:
	return {}


func get_inventory_status_text(_state: Dictionary) -> String:
	return ""


func get_instance_mass(_state: Dictionary) -> float:
	return maxf(mass, 0.01)


func get_inventory_code() -> String:
	if not inventory_code.is_empty():
		return inventory_code

	var words := display_name.strip_edges().split(" ", false)
	if words.size() >= 2:
		var result := ""
		for word_index: int in range(mini(words.size(), 3)):
			var word := str(words[word_index])
			if not word.is_empty():
				result += word.left(1)
		return result.to_upper()

	return display_name.left(3).to_upper()


func apply_to_collision(collision: CollisionShape3D) -> void:
	collision.shape = collision_shape
	collision.position = shape_position * overall_size
	collision.rotation_degrees = Vector3(
		shape_rotation_x,
		shape_rotation_y,
		shape_rotation_z
	)
	collision.scale = Vector3(
		shape_size_x,
		shape_size_y,
		shape_size_z
	) * overall_size


func _apply_material_override(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = material_override

	for child: Node in node.get_children():
		_apply_material_override(child)
