extends StaticBody3D

const CATALOG := preload("res://scripts/drones/dev_warehouse_catalog.gd")
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const REFILL_DELAY_SECONDS := 1.25

#######################################################
# Implements the dev warehouse subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

var slot_descriptors: Array[Dictionary] = []
var socketed_parts: Dictionary[int, RigidBody3D] = {}
@export var acoustic_material: AcousticMaterial


func _ready() -> void:
	PHYSICAL_SURFACE.apply_to(self, &"metal")
	var layout: Dictionary = CATALOG.build_layout()
	var raw_slots: Array = layout.get("slots", [])
	for raw_slot: Variant in raw_slots:
		var slot: Dictionary = raw_slot
		slot_descriptors.append(slot)
	_build_collision(layout)
	call_deferred("_populate_all_slots")


func _exit_tree() -> void:
	for part: RigidBody3D in socketed_parts.values():
		if is_instance_valid(part):
			part.queue_free()
	socketed_parts.clear()


func get_acoustic_material() -> AcousticMaterial:
	return acoustic_material


func release_socketed_part(part: RigidBody3D) -> bool:
	if not is_instance_valid(part):
		return false
	var slot_index := int(part.get_meta("dev_warehouse_slot_index", -1))
	if socketed_parts.get(slot_index) != part:
		return false

	socketed_parts.erase(slot_index)
	part.remove_meta("dev_warehouse_owner")
	part.remove_meta("dev_warehouse_slot_index")
	part.remove_meta("dev_warehouse_display_name")
	part.freeze = false
	part.gravity_scale = 1.0
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO

	var refill_timer := get_tree().create_timer(REFILL_DELAY_SECONDS)
	refill_timer.timeout.connect(_spawn_slot.bind(slot_index), CONNECT_ONE_SHOT)
	return true


func _populate_all_slots() -> void:
	for descriptor: Dictionary in slot_descriptors:
		_spawn_slot(int(descriptor["slot_index"]))


func _spawn_slot(slot_index: int) -> void:
	if not is_inside_tree() or socketed_parts.has(slot_index):
		return
	if slot_index < 0 or slot_index >= slot_descriptors.size():
		return

	var descriptor: Dictionary = slot_descriptors[slot_index]
	var definition := load(str(descriptor["definition_path"]))
	if not definition is Resource:
		push_error(
			"Dev warehouse failed to load %s"
			% str(descriptor["definition_path"])
		)
		return

	var local_rotation: Vector3 = descriptor["rotation"]
	var local_position: Vector3 = descriptor["position"]
	var local_transform := Transform3D(
		Basis.from_euler(local_rotation),
		local_position
	)
	var part: RigidBody3D
	if definition is DronePartDefinition:
		part = Server.spawn_drone_part(
			definition as DronePartDefinition,
			global_transform * local_transform
		)
	elif definition is ItemDefinition:
		part = Server.spawn_item(
			definition as ItemDefinition,
			global_transform * local_transform
		)
	if part == null:
		return

	part.set_meta("dev_warehouse_owner", self)
	part.set_meta("dev_warehouse_slot_index", slot_index)
	part.set_meta(
		"dev_warehouse_display_name",
		str((definition as Resource).get("display_name"))
	)
	part.gravity_scale = 0.0
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	part.freeze = true
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	socketed_parts[slot_index] = part


func _build_collision(layout: Dictionary) -> void:
	var total_width := float(layout.get("total_width", 1.0))
	var max_height := float(layout.get("max_height", 1.0))
	_add_box_collision(
		"BackboardCollision",
		Vector3(0.0, max_height * 0.5, 0.0),
		Vector3(total_width + 0.3, max_height, 0.16)
	)
	_add_box_collision(
		"FloorCollision",
		Vector3(0.0, 0.09, 1.0),
		Vector3(total_width + 1.0, 0.18, 2.2)
	)


func _add_box_collision(
	node_name: String,
	position: Vector3,
	size: Vector3
) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = node_name
	collision.position = position
	collision.shape = shape
	add_child(collision)
