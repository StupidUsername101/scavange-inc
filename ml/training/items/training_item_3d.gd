class_name TrainingItem3D
extends RigidBody3D

#######################################################
# Generic authored item used inside the shared ML training room. The item intentionally exposes
# only world/task facts (shape, mass, reward value, stable id, grip tags) so limb grippers, future
# drone/tool attachments, and take/deliver task providers can all discover the same object without
# depending on a body-specific training class.
#######################################################

const ENTITY_KIND: StringName = &"item"
const DEFAULT_DEFINITION: TrainingItemDefinition = preload("res://resources/training/items/generic_cargo.tres")
const TARGET_KIND: String = "cargo_pickup"
const DEFAULT_ITEM_TYPE: String = "generic"
const DEFAULT_RECOVERY_HORIZONTAL_MARGIN_M: float = 8.0
const DEFAULT_RECOVERY_MINIMUM_WORLD_Y_M: float = -6.0
const DEFAULT_RECOVERY_MAXIMUM_WORLD_Y_M: float = 64.0
const FALLBACK_COLOR = Color("f2b84b")
const SELECTED_COLOR = Color("7de9ff")

var training_item_id: int = 0
var item_definition: TrainingItemDefinition
var definition_resource_path: String = ""
var shape_kind: int = DroneTrainingObstacleShape.Kind.BOX
var dimensions: Dictionary = {}
var reward_value: float = 0.0
var item_type: String = DEFAULT_ITEM_TYPE
var grip_surface_tags: PackedStringArray = PackedStringArray(["carryable"])
var visual_color: Color = FALLBACK_COLOR
var spawn_transform_world: Transform3D = Transform3D.IDENTITY
var selected: bool = false
var simulation_active: bool = true


func _ready() -> void:
	var source_definition: TrainingItemDefinition = (
		item_definition if item_definition != null else DEFAULT_DEFINITION
	)
	var ready_definition: TrainingItemDefinition = (
		source_definition.sanitized_copy() if source_definition != null else null
	)
	if ready_definition == null and DEFAULT_DEFINITION != null:
		source_definition = DEFAULT_DEFINITION
		ready_definition = DEFAULT_DEFINITION.sanitized_copy()
	item_definition = ready_definition
	_apply_definition_state(ready_definition)
	if definition_resource_path.is_empty() and source_definition != null:
		definition_resource_path = MLBodyPartContract.resource_source_path(source_definition)
	collision_layer = 1
	collision_mask = 1 | (1 << 1) | (1 << 2)
	continuous_cd = true
	can_sleep = true
	linear_damp = 0.15
	angular_damp = 0.20
	set_meta("training_item", true)
	set_meta("training_grabbable_item", true)
	_refresh_item_metadata()
	_rebuild_geometry()


func configure_from_definition(
	item_id: int,
	source_definition: TrainingItemDefinition,
	new_transform: Transform3D,
	set_spawn_transform: bool = true,
	item_type_override: String = "",
	definition_path_override: String = ""
) -> bool:
	if source_definition == null:
		return false
	var safe_definition: TrainingItemDefinition = source_definition.sanitized_copy()
	if safe_definition == null:
		return false
	item_definition = safe_definition
	definition_resource_path = (
		definition_path_override.strip_edges()
		if not definition_path_override.strip_edges().is_empty()
		else MLBodyPartContract.resource_source_path(source_definition)
	)
	_apply_definition_state(safe_definition)
	var configured_type: String = safe_definition.item_type
	if not item_type_override.strip_edges().is_empty():
		configured_type = item_type_override
	configure_item(
		item_id,
		safe_definition.shape_kind,
		safe_definition.dimensions,
		safe_definition.mass_kg,
		safe_definition.reward_value,
		new_transform,
		set_spawn_transform,
		configured_type
	)
	_refresh_item_metadata()
	_apply_visual_color()
	return true


func configure_item(
	item_id: int,
	new_shape_kind: int,
	new_dimensions: Dictionary,
	new_mass: float,
	new_reward_value: float,
	new_transform: Transform3D,
	set_spawn_transform: bool = true,
	new_item_type: String = DEFAULT_ITEM_TYPE
) -> void:
	training_item_id = maxi(item_id, 1)
	shape_kind = clampi(
		new_shape_kind,
		0,
		DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1
	)
	dimensions = DroneTrainingObstacleShape.normalized_dimensions(shape_kind, new_dimensions)
	mass = maxf(RLTrainingMath.finite_float_or(new_mass, 1.0), 0.01)
	reward_value = maxf(RLTrainingMath.finite_float_or(new_reward_value, 0.0), 0.0)
	item_type = normalized_item_type(new_item_type)
	var safe_transform: Transform3D = _sanitized_transform(new_transform, spawn_transform_world)
	_refresh_item_metadata()
	if set_spawn_transform:
		spawn_transform_world = safe_transform
	freeze = true
	global_transform = safe_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	_rebuild_geometry()
	freeze = not simulation_active


func set_simulation_active(value: bool) -> void:
	var desired_freeze: bool = not value
	if simulation_active == value and freeze == desired_freeze:
		return
	simulation_active = value
	freeze = desired_freeze
	sleeping = false


func reset_to_spawn() -> void:
	freeze = true
	global_transform = spawn_transform_world
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	freeze = not simulation_active


func set_selected(value: bool) -> void:
	selected = value
	_apply_visual_color()


func spatial_key() -> StringName:
	return StringName("training:item:%d" % training_item_id)


func stable_id() -> String:
	return "training_item:%d" % training_item_id


func discovery_metadata() -> Dictionary:
	return {
		"item": self,
		"item_id": training_item_id,
		"stable_id": stable_id(),
		"target_kind": TARGET_KIND,
		"task_role": "pickup_item",
		"mass": mass,
		"reward_value": reward_value,
		"item_type": item_type,
		"shape_kind": shape_kind,
		"dimensions_m": dimensions.duplicate(true),
		"grippable": true,
		"grip_surface_tags": Array(grip_surface_tags),
		"definition_resource_path": definition_resource_path,
	}


func target_candidate(priority_bias: float = 0.0, urgency: float = 0.0) -> Dictionary:
	return {
		"available": is_inside_tree() and global_position.is_finite(),
		"stable_id": stable_id(),
		"target_kind": TARGET_KIND,
		"task_role": "pickup_item",
		"shootable": false,
		"position_world": global_position,
		"velocity_world": task_velocity_world(),
		"radius_m": collision_radius_m(),
		"priority_bias": RLTrainingMath.finite_float_or(priority_bias, 0.0),
		"urgency": RLTrainingMath.finite_float_or(urgency, 0.0),
		"distance_weight": 1.0,
		"metadata": discovery_metadata(),
	}


func collision_radius_m() -> float:
	return maxf(DroneTrainingObstacleShape.bounding_radius(shape_kind, dimensions), 0.05)


func task_velocity_world() -> Vector3:
	# freeze intentionally preserves RigidBody3D.linear_velocity for exact pause/resume. Task and
	# policy observations must describe the current world, however: a frozen shared item is not
	# moving from another active worker's point of view. Also fail closed if physics ever produces
	# a non-finite velocity; needs_recovery() will restore the body at the next room physics tick.
	if freeze or not linear_velocity.is_finite():
		return Vector3.ZERO
	return linear_velocity


func needs_recovery(
	arena_size: Vector3,
	horizontal_margin_m: float = DEFAULT_RECOVERY_HORIZONTAL_MARGIN_M,
	minimum_world_y: float = DEFAULT_RECOVERY_MINIMUM_WORLD_Y_M,
	maximum_world_y: float = DEFAULT_RECOVERY_MAXIMUM_WORLD_Y_M
) -> bool:
	# Authored items are dynamic and the training arena intentionally has an open edge. A task
	# object that falls into the void must not remain the assigned objective forever. Respect an
	# intentionally out-of-bounds authored spawn, however: recovery is only armed on axes where
	# the authored point itself is inside the recovery envelope.
	if (
		not global_transform.origin.is_finite()
		or not global_transform.basis.is_finite()
		or not linear_velocity.is_finite()
		or not angular_velocity.is_finite()
	):
		return true
	var margin: float = maxf(
		RLTrainingMath.finite_float_or(
			horizontal_margin_m,
			DEFAULT_RECOVERY_HORIZONTAL_MARGIN_M
		),
		0.0
	)
	var minimum_y: float = RLTrainingMath.finite_float_or(
		minimum_world_y,
		DEFAULT_RECOVERY_MINIMUM_WORLD_Y_M
	)
	var maximum_y: float = maxf(
		RLTrainingMath.finite_float_or(
			maximum_world_y,
			DEFAULT_RECOVERY_MAXIMUM_WORLD_Y_M
		),
		minimum_y + 1.0
	)
	var authored_half_x: float = maxf(absf(arena_size.x) * 0.5, 0.0)
	var authored_half_z: float = maxf(absf(arena_size.z) * 0.5, 0.0)
	var spawn: Vector3 = spawn_transform_world.origin
	var current: Vector3 = global_position
	# Numeric authoring is intentionally unbounded. Build each recovery envelope independently and
	# expand it when the authored spawn itself lies outside the ordinary arena envelope. This keeps
	# the authored point valid without disabling loss recovery for that axis forever.
	var recovery_min_x: float = -authored_half_x - margin
	var recovery_max_x: float = authored_half_x + margin
	var recovery_min_z: float = -authored_half_z - margin
	var recovery_max_z: float = authored_half_z + margin
	var recovery_min_y: float = minimum_y
	var recovery_max_y: float = maximum_y
	if spawn.x < recovery_min_x:
		recovery_min_x = spawn.x - margin
	elif spawn.x > recovery_max_x:
		recovery_max_x = spawn.x + margin
	if spawn.z < recovery_min_z:
		recovery_min_z = spawn.z - margin
	elif spawn.z > recovery_max_z:
		recovery_max_z = spawn.z + margin
	if spawn.y < recovery_min_y:
		recovery_min_y = spawn.y - margin
	elif spawn.y > recovery_max_y:
		recovery_max_y = spawn.y + margin
	if current.x < recovery_min_x or current.x > recovery_max_x:
		return true
	if current.z < recovery_min_z or current.z > recovery_max_z:
		return true
	if current.y < recovery_min_y or current.y > recovery_max_y:
		return true
	return false


func environment_record() -> Dictionary:
	var spawn_rotation_degrees: Vector3 = spawn_transform_world.basis.get_euler() * (180.0 / PI)
	return {
		"item_id": training_item_id,
		"shape_kind": shape_kind,
		"shape": DroneTrainingObstacleShape.display_name(shape_kind),
		"dimensions_m": dimensions.duplicate(true),
		"mass": mass,
		"reward_value": reward_value,
		"item_type": item_type,
		"definition_resource_path": definition_resource_path,
		"position_m": [
			spawn_transform_world.origin.x,
			spawn_transform_world.origin.y,
			spawn_transform_world.origin.z,
		],
		"rotation_degrees": [
			spawn_rotation_degrees.x,
			spawn_rotation_degrees.y,
			spawn_rotation_degrees.z,
		],
	}


static func normalized_item_type(value: String) -> String:
	return TrainingItemDefinition.normalized_item_type(value)


static func _sanitized_transform(value: Transform3D, fallback: Transform3D) -> Transform3D:
	var fallback_value: Transform3D = fallback
	if (
		not fallback_value.origin.is_finite()
		or not fallback_value.basis.is_finite()
		or fallback_value.basis.determinant() <= 0.000001
	):
		fallback_value = Transform3D.IDENTITY
	if (
		not value.origin.is_finite()
		or not value.basis.is_finite()
		or value.basis.determinant() <= 0.000001
	):
		return fallback_value
	# Item dimensions are owned by the primitive shape, never by transform scale/shear. Keeping an
	# orthonormal basis prevents a malformed external/map transform from making visual and physics
	# sizes disagree.
	return Transform3D(value.basis.orthonormalized(), value.origin)


func _apply_definition_state(source_definition: TrainingItemDefinition) -> void:
	if source_definition == null:
		return
	shape_kind = clampi(
		source_definition.shape_kind,
		0,
		DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1
	)
	dimensions = DroneTrainingObstacleShape.normalized_dimensions(
		shape_kind,
		source_definition.dimensions
	)
	mass = maxf(RLTrainingMath.finite_float_or(source_definition.mass_kg, 1.0), 0.01)
	reward_value = maxf(
		RLTrainingMath.finite_float_or(source_definition.reward_value, 0.0),
		0.0
	)
	item_type = normalized_item_type(source_definition.item_type)
	grip_surface_tags = source_definition.grip_surface_tags.duplicate()
	visual_color = source_definition.visual_color



func _refresh_item_metadata() -> void:
	set_meta("training_item_id", training_item_id)
	set_meta("training_item_stable_id", stable_id())
	set_meta("training_item_reward_value", reward_value)
	set_meta("training_item_mass", mass)
	set_meta("training_item_type", item_type)
	set_meta("grip_surface_tags", grip_surface_tags.duplicate())
	if definition_resource_path.is_empty():
		remove_meta("training_item_definition_path")
	else:
		set_meta("training_item_definition_path", definition_resource_path)


func _rebuild_geometry() -> void:
	var collision: CollisionShape3D = get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "Collision"
		add_child(collision)
	collision.shape = DroneTrainingObstacleShape.collision_shape(shape_kind, dimensions)

	var visual: MeshInstance3D = get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = "Visual"
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
	visual.mesh = DroneTrainingObstacleShape.visual_mesh(shape_kind, dimensions)
	_apply_visual_color()


func _apply_visual_color() -> void:
	var visual: MeshInstance3D = get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		return
	var color: Color = SELECTED_COLOR if selected else visual_color
	visual.material_override = DroneTrainingRoomPresentation.material(color, false)
