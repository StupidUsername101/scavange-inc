@tool
extends Resource
class_name ItemDefinition

const HELD_PROFILE_GENERIC: StringName = &"generic"
const HELD_PROFILE_PISTOL: StringName = &"pistol"
const HELD_PROFILE_RIFLE: StringName = &"rifle"
const HELD_PROFILE_TOOL: StringName = &"tool"
const ITEM_GRIP_POINT_NAME: StringName = &"ItemGripPoint"

enum EconomyCategory {
	ITEM,
	VALUABLE,
}

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

@export_group("Fieldlink")
@export var fieldlink_detectable := false:
	set(value):
		fieldlink_detectable = value
		emit_changed()

@export var fieldlink_device_class: StringName = &"DEVICE":
	set(value):
		fieldlink_device_class = value
		emit_changed()

@export var fieldlink_control_type: StringName = &"":
	set(value):
		fieldlink_control_type = value
		emit_changed()

@export_range(0.0, 4.0, 0.05) var fieldlink_signal_strength := 1.0:
	set(value):
		fieldlink_signal_strength = maxf(value, 0.0)
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

@export var physical_surface: StringName = &"metal":
	set(value):
		physical_surface = value
		emit_changed()

@export_group("Economy")
@export_enum("Item", "Valuable") var economy_category: int = EconomyCategory.ITEM:
	set(value):
		economy_category = clampi(value, EconomyCategory.ITEM, EconomyCategory.VALUABLE)
		emit_changed()

@export_range(0.0, 1000000000.0, 0.01, "or_greater") var value_per_mass := 0.0:
	set(value):
		value_per_mass = maxf(value, 0.0) if is_finite(value) else 0.0
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

@export_subgroup("Hold Pose")
@export var default_grab_rotation_degrees := Vector3.ZERO:
	set(value):
		default_grab_rotation_degrees = value if value.is_finite() else Vector3.ZERO
		emit_changed()

## Inventory presentation uses the same world-space hands for the owner and every observer. These
## values describe how the item's authored visual origin sits relative to its primary hand; they are
## deliberately part of the item definition rather than a camera-only weapon rig.
@export var held_presentation_profile: StringName = HELD_PROFILE_GENERIC:
	set(value):
		held_presentation_profile = (
			value if not value.is_empty() else HELD_PROFILE_GENERIC
		)
		emit_changed()

@export var held_visual_position := Vector3.ZERO:
	set(value):
		held_visual_position = value if value.is_finite() else Vector3.ZERO
		emit_changed()

@export var held_visual_rotation_degrees := Vector3.ZERO:
	set(value):
		held_visual_rotation_degrees = (
			value if value.is_finite() else Vector3.ZERO
		)
		emit_changed()

@export_range(0.01, 10.0, 0.01, "or_greater") var held_visual_scale := 1.0:
	set(value):
		held_visual_scale = maxf(value, 0.01) if is_finite(value) else 1.0
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


func get_default_grab_basis() -> Basis:
	return Basis.from_euler(Vector3(
		deg_to_rad(default_grab_rotation_degrees.x),
		deg_to_rad(default_grab_rotation_degrees.y),
		deg_to_rad(default_grab_rotation_degrees.z)
	)).orthonormalized()


static func _sanitized_grip_surface_tags(value: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for raw_tag: String in value:
		var tag := raw_tag.strip_edges()
		if not tag.is_empty() and not result.has(tag):
			result.append(tag)
	return result


func instantiate_visual() -> Node3D:
	var visual_root: Node3D = _create_visual_root()

	if visual_scene == null:
		return visual_root

	var visual: Node = visual_scene.instantiate()
	visual_root.add_child(visual)

	if material_override != null:
		_apply_material_override(visual)

	return visual_root


func _create_visual_root() -> Node3D:
	var visual_root: Node3D = Node3D.new()
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
	return visual_root


func instantiate_visual_from_state(_state: Dictionary) -> Node3D:
	return instantiate_visual()


## All grippable inventory items share this presentation contract. Specialized definitions may
## replace the visual and profile, but never choose a separate owner-only mesh or transform.
func instantiate_held_visual(
	state: Dictionary,
	_first_person := false
) -> Node3D:
	# Preserve the ordinary item's authored mesh transform inside a grip-space wrapper. The wrapper
	# can then be aligned to the hand without erasing mesh offsets used by world/item proxies.
	var held_root := Node3D.new()
	held_root.name = "HeldItemVisual"
	held_root.add_child(instantiate_visual_from_state(state))
	return held_root


func get_held_presentation_profile(_state: Dictionary) -> StringName:
	return held_presentation_profile


func get_held_visual_position(_state: Dictionary) -> Vector3:
	return held_visual_position


func get_held_visual_basis(_state: Dictionary) -> Basis:
	return Basis.from_euler(Vector3(
		deg_to_rad(held_visual_rotation_degrees.x),
		deg_to_rad(held_visual_rotation_degrees.y),
		deg_to_rad(held_visual_rotation_degrees.z)
	)).orthonormalized()


func get_held_visual_scale(_state: Dictionary) -> float:
	return maxf(held_visual_scale, 0.01)


## Joins the item's grip point to the character's HandGripPoint parent. Shaped items author an
## ItemGripPoint at their real handle. For an unmarked item, the base definition derives and creates
## that point from its existing held pose, so every held object follows the same anchor contract.
func get_held_visual_transform(
	state: Dictionary,
	visual: Node3D
) -> Transform3D:
	var visual_scale := get_held_visual_scale(state)
	var legacy_transform := Transform3D(
		get_held_visual_basis(state).scaled(Vector3.ONE * visual_scale),
		get_held_visual_position(state)
	)
	if visual == null:
		return legacy_transform
	var hand_grip_space := Transform3D(
		Basis.IDENTITY.scaled(Vector3.ONE * visual_scale),
		Vector3.ZERO
	)
	var grip := visual.find_child(
		ITEM_GRIP_POINT_NAME,
		true,
		false
	) as Node3D
	if grip == null:
		grip = Marker3D.new()
		grip.name = ITEM_GRIP_POINT_NAME
		# L * G = H: with the legacy item pose L and hand scale H, G is the point on the
		# untransformed item that already occupied the player's grip. Aligning it reproduces L exactly.
		grip.transform = legacy_transform.affine_inverse() * hand_grip_space
		grip.set_meta(&"generated_item_grip", true)
		visual.add_child(grip)
	var grip_from_visual := _node_transform_from_ancestor(visual, grip)
	return hand_grip_space * grip_from_visual.affine_inverse()


static func _node_transform_from_ancestor(
	ancestor: Node3D,
	descendant: Node3D
) -> Transform3D:
	if ancestor == null or descendant == null or ancestor == descendant:
		return Transform3D.IDENTITY
	var result := descendant.transform
	var cursor := descendant.get_parent() as Node3D
	while cursor != null and cursor != ancestor:
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result if cursor == ancestor else Transform3D.IDENTITY


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


func is_valuable() -> bool:
	return economy_category == EconomyCategory.VALUABLE


func get_instance_value_per_mass(_state: Dictionary) -> float:
	return maxf(value_per_mass, 0.0) if is_valuable() else 0.0


func get_instance_total_value(state: Dictionary) -> float:
	return get_instance_mass(state) * get_instance_value_per_mass(state)


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
