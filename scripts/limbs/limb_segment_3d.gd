class_name LimbSegment3D
extends RigidBody3D

#######################################################
# One independent rigid part in a modular creature. The same class is used for the chassis and
# every limb segment so damage, mass, collision, and runtime state have one implementation.
#######################################################

var owner_body: Node
var limb_slot_index := -1
var segment_index := -1
var binding_name: StringName = &""
var maximum_health := 100.0
var current_health := 100.0
var actuator_effectiveness := 1.0
var rest_transform_local := Transform3D.IDENTITY
var rest_transform_core_local: Transform3D = Transform3D.IDENTITY


func configure(
	body: Node,
	slot_index: int,
	new_segment_index: int,
	new_binding_name: StringName,
	health_value: float
) -> void:
	owner_body = body
	limb_slot_index = slot_index
	segment_index = new_segment_index
	binding_name = new_binding_name
	maximum_health = maxf(health_value, 0.001)
	current_health = maximum_health


func configure_surface_material(
	friction_value: float,
	bounce_value: float,
	rough_value: bool = false,
	absorbent_value: bool = false
) -> PhysicsMaterial:
	# RigidBody3D does not expose friction or bounce as direct properties in Godot 4. Surface
	# response belongs to a PhysicsMaterial assigned through physics_material_override. Keep this
	# construction in the shared rigid-part class so future creature-editor parts cannot repeat the
	# invalid `body.friction = ...` pattern that prevented the complete limb rig from spawning.
	var surface := PhysicsMaterial.new()
	surface.friction = clampf(friction_value, 0.0, 1.0)
	surface.bounce = clampf(bounce_value, 0.0, 1.0)
	surface.rough = rough_value
	surface.absorbent = absorbent_value
	physics_material_override = surface
	return surface


func health_ratio() -> float:
	return clampf(current_health / maxf(maximum_health, 0.001), 0.0, 1.0)


func functional_ratio() -> float:
	return health_ratio() * clampf(actuator_effectiveness, 0.0, 1.0)


func apply_segment_damage(amount: float) -> void:
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if is_instance_valid(owner_body) and limb_slot_index >= 0 and owner_body.has_method("notify_limb_damage"):
		owner_body.notify_limb_damage(limb_slot_index)


func has_finite_state() -> bool:
	return (
		global_transform.is_finite()
		and linear_velocity.is_finite()
		and angular_velocity.is_finite()
	)
