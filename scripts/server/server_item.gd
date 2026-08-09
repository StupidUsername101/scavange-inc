@tool
extends RigidBody3D
class_name ServerItem

const PREVIEW_NODE_NAME := "ItemVisualPreview"

#######################################################
# Owns authoritative item simulation and exposes the state required for replication and
# interaction.
#######################################################

@export var definition: ItemDefinition:
	set(value):
		if (
			definition != null
			and definition.changed.is_connected(_on_definition_changed)
		):
			definition.changed.disconnect(_on_definition_changed)

		definition = value

		if (
			definition != null
			and not definition.changed.is_connected(_on_definition_changed)
		):
			definition.changed.connect(_on_definition_changed)

		_queue_rebuild()

var item_id: int = -1
var instance_state: Dictionary = {}


func _ready() -> void:
	if definition != null and instance_state.is_empty():
		instance_state = definition.make_default_instance_state()
	_rebuild_from_definition()

	if Engine.is_editor_hint():
		return

	item_id = ServerItemFactory.get_next_id()
	Server.register_item(item_id, self)


func _exit_tree() -> void:
	if Engine.is_editor_hint() or item_id == -1:
		return

	Server.unregister_item(item_id)


func _on_definition_changed() -> void:
	_queue_rebuild()


func _queue_rebuild() -> void:
	if is_inside_tree():
		call_deferred("_rebuild_from_definition")


func _rebuild_from_definition() -> void:
	var collision := get_node_or_null("ItemCollision") as CollisionShape3D

	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "ItemCollision"
		add_child(collision)

	var old_preview := get_node_or_null(PREVIEW_NODE_NAME)

	if old_preview != null:
		remove_child(old_preview)
		old_preview.queue_free()

	if definition == null:
		collision.shape = null
		set_meta("grip_surface_disabled", true)
		remove_meta("grip_surface_tags")
		return

	set_meta("grip_surface_disabled", not definition.grippable)
	if definition.grippable:
		set_meta("grip_surface_tags", definition.get_grip_surface_tags())
	else:
		remove_meta("grip_surface_tags")
	mass = definition.get_instance_mass(instance_state)
	definition.apply_to_collision(collision)

	if Engine.is_editor_hint():
		var preview := definition.instantiate_visual()
		preview.name = PREVIEW_NODE_NAME
		add_child(preview)


func get_item_definition() -> ItemDefinition:
	return definition


func get_inspectable_definition() -> Resource:
	return definition


func serialize_instance_state() -> Dictionary:
	if definition == null:
		return instance_state.duplicate(true)
	return definition.normalize_instance_state(instance_state)


func restore_instance_state(state: Dictionary) -> void:
	instance_state = (
		definition.normalize_instance_state(state)
		if definition != null
		else state.duplicate(true)
	)
	if is_node_ready():
		_rebuild_from_definition()


func to_inventory_entry() -> Dictionary:
	return PlayerInventoryRules.make_entry(
		definition,
		serialize_instance_state()
	)


func to_state_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"definition_path": (
			definition.resource_path
			if definition != null
			else ""
		),
		"pos": global_position,
		"rot": global_rotation,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"instance_state": (
			definition.get_public_instance_state(instance_state)
			if definition != null
			else {}
		),
		"warehouse_display_name": str(get_meta(
			"dev_warehouse_display_name",
			""
		)),
	}
