class_name GenericLimbAssembly3D
extends Node3D

#######################################################
# Reusable model-forge limb host. Any RigidBody3D—including ServerDrone—can own arbitrary
# generic limb definitions and their end effectors without depending on the four-limb ML adapter.
# The assembly is top-level so independently simulated limb bodies do not inherit the host's
# transform a second time merely because the assembly is kept as a lifecycle child of that host.
#######################################################

var host_body: RigidBody3D
var owner_model: Node
var limb_definitions: Array[GenericLimbDefinition] = []
var limbs: Array[GenericLimb3D] = []
var limbs_by_definition_index: Dictionary = {}
var controller: LimbsController3D
var collision_layer_value := 4
var collision_mask_value := 1
var exclude_self_collision := true
var contact_reporting_enabled: bool = false
var allow_sleep: bool = true
var built := false


func _init() -> void:
	top_level = true


func configure(
	new_host_body: RigidBody3D,
	new_definitions: Array[GenericLimbDefinition],
	new_owner_model: Node = null,
	new_collision_layer: int = 4,
	new_collision_mask: int = 1,
	new_exclude_self_collision: bool = true,
	new_contact_reporting_enabled: bool = false,
	new_allow_sleep: bool = true
) -> void:
	host_body = new_host_body
	owner_model = new_owner_model if new_owner_model != null else new_host_body
	limb_definitions = new_definitions
	collision_layer_value = maxi(new_collision_layer, 0)
	collision_mask_value = maxi(new_collision_mask, 0)
	exclude_self_collision = new_exclude_self_collision
	contact_reporting_enabled = new_contact_reporting_enabled
	allow_sleep = new_allow_sleep
	if is_inside_tree():
		_build()


func _ready() -> void:
	_build()


func _build() -> void:
	if built or not is_instance_valid(host_body):
		return
	built = true
	limbs_by_definition_index.clear()
	for index in range(limb_definitions.size()):
		var definition := limb_definitions[index]
		if definition == null:
			continue
		var limb := GenericLimb3D.new()
		limb.name = "GenericLimb%02d" % index
		add_child(limb)
		limb.configure(
			owner_model,
			host_body,
			definition,
			index,
			Color.from_hsv(fmod(float(index) * 0.173, 1.0), 0.65, 0.95),
			collision_layer_value,
			collision_mask_value,
			contact_reporting_enabled,
			allow_sleep
		)
		limbs.append(limb)
		limbs_by_definition_index[index] = limb
	_configure_self_collision_exceptions()
	controller = LimbsController3D.new()
	controller.name = "LimbsController"
	add_child(controller)
	# Generic model-forge bodies only need joint diagnostics when an observation/debug snapshot is
	# sampled. Keep the 60 Hz actuator loop on typed runtime fields instead of mutating Dictionaries.
	controller.configure(host_body, limbs, -1, PackedInt32Array(), false)


func _configure_self_collision_exceptions() -> void:
	if not exclude_self_collision or not is_instance_valid(host_body):
		return
	var bodies: Array[PhysicsBody3D] = []
	bodies.append(host_body)
	for limb: GenericLimb3D in limbs:
		if not is_instance_valid(limb):
			continue
		for segment: LimbSegment3D in limb.segments:
			if is_instance_valid(segment):
				bodies.append(segment)
	for first_index in range(bodies.size()):
		var first := bodies[first_index]
		for second_index in range(first_index + 1, bodies.size()):
			var second := bodies[second_index]
			first.add_collision_exception_with(second)
			second.add_collision_exception_with(first)


func can_submit_commands(command_count: int) -> bool:
	return (
		command_count >= 0
		and is_instance_valid(controller)
		and controller.action_mapping_valid
		and controller.action_count == command_count
		and required_action_count() == command_count
	)


func submit_commands(commands: PackedFloat64Array) -> bool:
	return can_submit_commands(commands.size()) and controller.submit_commands(commands)


func neutralize() -> void:
	if is_instance_valid(controller):
		controller.neutralize()


func set_controller_external_step(value: bool) -> void:
	if is_instance_valid(controller):
		controller.set_external_step_mode(value)


func step_controller(delta: float) -> void:
	if is_instance_valid(controller):
		controller.step_controller(delta)


func set_runtime_active(value: bool, release_grip_on_deactivate: bool = true) -> void:
	for limb: GenericLimb3D in limbs:
		if is_instance_valid(limb):
			limb.set_runtime_active(value)
			if not value and release_grip_on_deactivate and is_instance_valid(limb.end_effector):
				limb.end_effector.release_grip()
	if is_instance_valid(controller):
		controller.set_active(value)


func release_grips() -> void:
	for limb: GenericLimb3D in limbs:
		if is_instance_valid(limb) and is_instance_valid(limb.end_effector):
			limb.end_effector.release_grip()


func reset_to_rest() -> void:
	neutralize()
	release_grips()
	for limb: GenericLimb3D in limbs:
		if is_instance_valid(limb):
			limb.reset_to_rest()
	if is_instance_valid(controller):
		controller.reset_runtime_state()


func limb_for_definition_index(definition_index: int) -> GenericLimb3D:
	var limb: GenericLimb3D = limbs_by_definition_index.get(definition_index) as GenericLimb3D
	return limb if is_instance_valid(limb) else null


func required_action_count() -> int:
	return LimbsController3D.required_action_count_for_limbs(limbs)


func holds_instance_id(instance_id: int) -> bool:
	if instance_id <= 0:
		return false
	for limb: GenericLimb3D in limbs:
		if (
			is_instance_valid(limb)
			and is_instance_valid(limb.end_effector)
			and limb.end_effector.holds_instance_id(instance_id)
		):
			return true
	return false


func state_snapshot() -> Dictionary:
	if is_instance_valid(controller):
		controller.sync_source_records()
	var limb_states: Array[Dictionary] = []
	for limb: GenericLimb3D in limbs:
		if not is_instance_valid(limb):
			continue
		limb_states.append(GenericLimbStateSnapshot.limb_state(limb))
	var host_transform: Transform3D = Transform3D.IDENTITY
	if is_instance_valid(host_body):
		host_transform = (
			host_body.call("model_transform_world") as Transform3D
			if host_body.has_method("model_transform_world")
			else host_body.global_transform
		)
	return {
		"host_instance_id": host_body.get_instance_id() if is_instance_valid(host_body) else 0,
		"host_transform_world": host_transform,
		"host_linear_velocity_world": (
			host_body.linear_velocity if is_instance_valid(host_body) else Vector3.ZERO
		),
		"host_angular_velocity_world": (
			host_body.angular_velocity if is_instance_valid(host_body) else Vector3.ZERO
		),
		"action_count": required_action_count(),
		"mapping_valid": (
			controller.action_mapping_valid if is_instance_valid(controller) else false
		),
		"commands": (
			controller.desired_commands.duplicate()
			if is_instance_valid(controller)
			else PackedFloat64Array()
		),
		"limbs": limb_states,
	}
