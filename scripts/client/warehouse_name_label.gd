class_name WarehouseNameLabel
extends RefCounted

#######################################################
# Shared presentation for warehouse display-name labels on loose client-side item/part proxies.
#######################################################


static func create(parent: Node3D) -> Label3D:
	if not is_instance_valid(parent):
		return null
	var label: Label3D = Label3D.new()
	label.name = "WarehouseItemName"
	label.top_level = true
	label.visible = false
	label.font_size = 38
	label.outline_size = 10
	label.modulate = Color(0.96, 0.98, 1.0, 1.0)
	label.outline_modulate = Color(0.005, 0.008, 0.012, 1.0)
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Labels stay readable while still respecting walls, shelves, parts, and scene geometry.
	label.no_depth_test = false
	parent.add_child(label)
	return label


static func set_display_name(
	label: Label3D,
	display_name: String,
	owner_position: Vector3,
	height: float
) -> void:
	if not is_instance_valid(label):
		return
	label.text = display_name
	label.visible = not display_name.is_empty()
	update_position(label, owner_position, height)


static func update_position(
	label: Label3D,
	owner_position: Vector3,
	height: float
) -> void:
	if not is_instance_valid(label) or not label.visible:
		return
	label.global_position = owner_position + Vector3.UP * height
