class_name ServerRope
extends Node3D

const GRAVITY_ACCELERATION := 9.81
const SLEEP_DELAY_SECONDS := 0.8
const ENDPOINT_WAKE_DISTANCE_SQUARED := 0.000004

#######################################################
# Owns authoritative rope simulation and exposes the state required for replication and
# interaction.
#######################################################

var rope_id := -1
var definition: RopeDefinition
var endpoint_a: RopeEndpoint
var endpoint_b: RopeEndpoint
var deployed_length := 0.0

var points := PackedVector3Array()
var previous_points := PackedVector3Array()
var frame_start_points := PackedVector3Array()
var segment_rest_length := 0.25
var smoothed_tension_newtons := 0.0
var raw_tension_newtons := 0.0
var over_tension_time := 0.0
var current_flow_w := 0.0
var current_direction := 0
var sleep_timer := 0.0
var simulation_sleeping := false
var last_endpoint_a := Vector3.ZERO
var last_endpoint_b := Vector3.ZERO
var supported_particles: Dictionary[int, bool] = {}
var knot_a: RopeKnot
var knot_b: RopeKnot
var collision_probe_shape: SphereShape3D
var collision_probe_query: PhysicsShapeQueryParameters3D


func configure(
	new_rope_id: int,
	new_definition: RopeDefinition,
	new_endpoint_a: RopeEndpoint,
	new_endpoint_b: RopeEndpoint,
	new_deployed_length: float
) -> void:
	rope_id = new_rope_id
	definition = new_definition
	endpoint_a = new_endpoint_a
	endpoint_b = new_endpoint_b
	deployed_length = clampf(
		new_deployed_length,
		0.05,
		definition.maximum_length
	)
	_initialize_collision_probe()
	_initialize_particles()
	_create_knots()


func server_physics_tick(delta: float) -> void:
	if (
		definition == null
		or endpoint_a == null
		or endpoint_b == null
		or not endpoint_a.is_valid()
		or not endpoint_b.is_valid()
	):
		Server.detach_rope(rope_id)
		return

	var anchor_a := endpoint_a.get_rope_position()
	var anchor_b := endpoint_b.get_rope_position()
	_update_knots(anchor_a, anchor_b)
	_update_power_transfer(delta)

	var endpoint_moved := (
		anchor_a.distance_squared_to(last_endpoint_a)
		> ENDPOINT_WAKE_DISTANCE_SQUARED
		or anchor_b.distance_squared_to(last_endpoint_b)
		> ENDPOINT_WAKE_DISTANCE_SQUARED
	)
	last_endpoint_a = anchor_a
	last_endpoint_b = anchor_b
	if simulation_sleeping and not endpoint_moved:
		return
	if simulation_sleeping:
		simulation_sleeping = false
		for point_index in range(points.size()):
			previous_points[point_index] = points[point_index]

	frame_start_points = points.duplicate()
	_integrate_particles(delta, anchor_a, anchor_b)
	_solve_constraints(anchor_a, anchor_b)
	_update_tension_and_forces(delta, anchor_a, anchor_b)
	_update_sleep_state(delta, endpoint_moved)


func to_state_dict() -> Dictionary:
	return {
		"rope_id": rope_id,
		"definition_path": (
			definition.resource_path if definition != null else ""
		),
		"points": points,
		"preview": false,
		"valid": true,
		"deployed_length": deployed_length,
		"path_length": _calculate_path_length(),
		"tension_ratio": (
			smoothed_tension_newtons
			/ maxf(definition.breaking_force_newtons, 0.001)
			if definition != null
			else 0.0
		),
		"current_flow_w": current_flow_w,
		"current_direction": current_direction,
	}


func connects_body(candidate: PhysicsBody3D) -> bool:
	return (
		candidate != null
		and (
			(endpoint_a != null and endpoint_a.body == candidate)
			or (endpoint_b != null and endpoint_b.body == candidate)
		)
	)


func get_fiber_link_state_for(candidate: PhysicsBody3D) -> Dictionary:
	if (
		definition == null
		or not definition.provides_fiber_link
		or not connects_body(candidate)
	):
		return {}
	var other_body := (
		endpoint_b.body if endpoint_a.body == candidate else endpoint_a.body
	)
	var path_length := _calculate_path_length()
	return {
		"rope_id": rope_id,
		"connected_body": other_body,
		"deployed_length": deployed_length,
		"path_length": path_length,
		"remaining_slack": maxf(deployed_length - path_length, 0.0),
		"maximum_spool_length": definition.maximum_length,
		"bandwidth_mbps": definition.data_bandwidth_mbps,
		"signal_quality": clampf(
			1.0 - path_length * definition.signal_loss_per_meter,
			0.0,
			1.0
		),
	}


func _initialize_particles() -> void:
	var anchor_a := endpoint_a.get_rope_position()
	var anchor_b := endpoint_b.get_rope_position()
	var segment_count := definition.get_segment_count(deployed_length)
	segment_rest_length = deployed_length / float(segment_count)
	points.resize(segment_count + 1)
	previous_points.resize(segment_count + 1)
	var direct_distance := anchor_a.distance_to(anchor_b)
	var available_sag := sqrt(maxf(
		deployed_length * deployed_length - direct_distance * direct_distance,
		0.0
	)) * 0.35
	for point_index in range(points.size()):
		var weight := float(point_index) / float(segment_count)
		var point := anchor_a.lerp(anchor_b, weight)
		point.y -= sin(weight * PI) * available_sag
		points[point_index] = point
		previous_points[point_index] = point
	last_endpoint_a = anchor_a
	last_endpoint_b = anchor_b


func _initialize_collision_probe() -> void:
	collision_probe_shape = SphereShape3D.new()
	collision_probe_shape.radius = definition.get_radius()
	collision_probe_query = PhysicsShapeQueryParameters3D.new()
	collision_probe_query.shape = collision_probe_shape
	collision_probe_query.collision_mask = definition.collision_mask
	collision_probe_query.collide_with_areas = false


func _create_knots() -> void:
	knot_a = RopeKnot.new()
	knot_a.name = "RopeKnotA"
	knot_a.configure(rope_id, definition.get_radius())
	add_child(knot_a)
	knot_b = RopeKnot.new()
	knot_b.name = "RopeKnotB"
	knot_b.configure(rope_id, definition.get_radius())
	add_child(knot_b)
	_update_knots(endpoint_a.get_rope_position(), endpoint_b.get_rope_position())


func _update_knots(anchor_a: Vector3, anchor_b: Vector3) -> void:
	if is_instance_valid(knot_a):
		knot_a.global_position = anchor_a
	if is_instance_valid(knot_b):
		knot_b.global_position = anchor_b


func _integrate_particles(
	delta: float,
	anchor_a: Vector3,
	anchor_b: Vector3
) -> void:
	var acceleration_step := Vector3.DOWN * GRAVITY_ACCELERATION * delta * delta
	for point_index in range(1, points.size() - 1):
		var current := points[point_index]
		var velocity: Vector3 = (
			current - previous_points[point_index]
		) * definition.motion_damping
		previous_points[point_index] = current
		points[point_index] = current + velocity + acceleration_step
	points[0] = anchor_a
	points[points.size() - 1] = anchor_b


func _solve_constraints(anchor_a: Vector3, anchor_b: Vector3) -> void:
	supported_particles.clear()
	for _iteration in range(definition.solver_iterations):
		points[0] = anchor_a
		points[points.size() - 1] = anchor_b
		for segment_index in range(points.size() - 1):
			var point_a := points[segment_index]
			var point_b := points[segment_index + 1]
			var offset := point_b - point_a
			var distance := offset.length()
			if distance <= 0.000001:
				continue
			var correction := offset * (
				(distance - segment_rest_length) / distance
			)
			if segment_index == 0:
				points[segment_index + 1] -= correction
			elif segment_index + 1 == points.size() - 1:
				points[segment_index] += correction
			else:
				points[segment_index] += correction * 0.5
				points[segment_index + 1] -= correction * 0.5
		_resolve_particle_collisions()
	_resolve_particle_penetrations()
	_resolve_segment_crossings()
	points[0] = anchor_a
	points[points.size() - 1] = anchor_b


func _resolve_particle_collisions() -> void:
	if not is_inside_tree():
		return
	var exclusions: Array[RID] = []
	endpoint_a.append_collision_exclusion(exclusions)
	endpoint_b.append_collision_exclusion(exclusions)
	var space_state := get_world_3d().direct_space_state
	for point_index in range(1, points.size() - 1):
		var from_position := frame_start_points[point_index]
		var to_position := points[point_index]
		if from_position.distance_squared_to(to_position) < 0.0000001:
			continue
		var query := PhysicsRayQueryParameters3D.create(
			from_position,
			to_position,
			definition.collision_mask,
			exclusions
		)
		query.collide_with_areas = false
		query.hit_from_inside = false
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if normal.length_squared() < 0.000001:
			normal = Vector3.UP
		points[point_index] = (
			hit.get("position", to_position)
			+ normal.normalized() * definition.get_radius()
		)
		var displacement := points[point_index] - previous_points[point_index]
		var tangential := displacement.slide(normal)
		previous_points[point_index] = (
			points[point_index]
			- tangential * (1.0 - definition.surface_friction)
		)
		if normal.y > 0.45:
			supported_particles[point_index] = true


func _resolve_particle_penetrations() -> void:
	if not is_inside_tree() or collision_probe_query == null:
		return
	var exclusions: Array[RID] = []
	endpoint_a.append_collision_exclusion(exclusions)
	endpoint_b.append_collision_exclusion(exclusions)
	collision_probe_query.exclude = exclusions
	var space_state := get_world_3d().direct_space_state
	for point_index in range(1, points.size() - 1):
		collision_probe_query.transform = Transform3D(
			Basis.IDENTITY,
			points[point_index]
		)
		var rest_info := space_state.get_rest_info(collision_probe_query)
		if rest_info.is_empty():
			continue
		var normal: Vector3 = rest_info.get("normal", Vector3.UP)
		if normal.length_squared() < 0.000001:
			continue
		points[point_index] = (
			rest_info.get("point", points[point_index])
			+ normal.normalized() * definition.get_radius()
		)
		previous_points[point_index] = points[point_index]
		if normal.y > 0.45:
			supported_particles[point_index] = true


func _resolve_segment_crossings() -> void:
	if not is_inside_tree():
		return
	var exclusions: Array[RID] = []
	endpoint_a.append_collision_exclusion(exclusions)
	endpoint_b.append_collision_exclusion(exclusions)
	var space_state := get_world_3d().direct_space_state
	for segment_index in range(points.size() - 1):
		var start := points[segment_index]
		var end := points[segment_index + 1]
		if start.distance_squared_to(end) < 0.0000001:
			continue
		var query := PhysicsRayQueryParameters3D.create(
			start,
			end,
			definition.collision_mask,
			exclusions
		)
		query.collide_with_areas = false
		query.hit_from_inside = false
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		if normal.length_squared() < 0.000001:
			continue
		var movable_index: int = segment_index + 1
		if movable_index >= points.size() - 1:
			movable_index = segment_index
		if movable_index <= 0 or movable_index >= points.size() - 1:
			continue
		points[movable_index] = (
			hit.get("position", points[movable_index])
			+ normal.normalized() * definition.get_radius()
		)
		previous_points[movable_index] = points[movable_index]
		if normal.y > 0.45:
			supported_particles[movable_index] = true


func _update_tension_and_forces(
	delta: float,
	anchor_a: Vector3,
	anchor_b: Vector3
) -> void:
	var path_length := _calculate_path_length()
	var extension := maxf(path_length - deployed_length, 0.0)
	var separation_axis := (anchor_b - anchor_a).normalized()
	var separation_speed := 0.0
	if separation_axis.length_squared() > 0.000001:
		separation_speed = (
			endpoint_b.get_point_velocity() - endpoint_a.get_point_velocity()
		).dot(separation_axis)
	raw_tension_newtons = maxf(
		extension * definition.stretch_stiffness_newtons_per_m
		+ maxf(separation_speed, 0.0) * definition.tension_damping,
		0.0
	)
	var blend := 1.0 - exp(-definition.force_response * delta)
	var filtered_tension: float = lerpf(
		smoothed_tension_newtons,
		minf(raw_tension_newtons, definition.breaking_force_newtons),
		blend
	)
	smoothed_tension_newtons = move_toward(
		smoothed_tension_newtons,
		filtered_tension,
		definition.tension_slew_rate_newtons_per_second * delta
	)

	if raw_tension_newtons >= definition.breaking_force_newtons:
		over_tension_time += delta
	else:
		over_tension_time = maxf(over_tension_time - delta * 2.0, 0.0)
	if over_tension_time >= definition.break_grace_seconds:
		Server.break_rope(rope_id, (anchor_a + anchor_b) * 0.5)
		return

	if points.size() >= 2 and smoothed_tension_newtons > 0.0:
		var direction_a := (points[1] - points[0]).normalized()
		var direction_b := (
			points[points.size() - 2] - points[points.size() - 1]
		).normalized()
		endpoint_a.apply_force(direction_a * smoothed_tension_newtons)
		endpoint_b.apply_force(direction_b * smoothed_tension_newtons)

	var internal_count := maxi(points.size() - 2, 1)
	var supported_ratio := clampf(
		float(supported_particles.size()) / float(internal_count),
		0.0,
		1.0
	)
	var suspended_weight := (
		definition.get_deployed_mass(deployed_length)
		* GRAVITY_ACCELERATION
		* (1.0 - supported_ratio)
	)
	var endpoint_weight := Vector3.DOWN * suspended_weight * 0.5
	endpoint_a.apply_force(endpoint_weight)
	endpoint_b.apply_force(endpoint_weight)


func _update_sleep_state(delta: float, endpoint_moved: bool) -> void:
	var maximum_particle_speed_squared := 0.0
	var safe_delta := maxf(delta, 0.001)
	for point_index in range(1, points.size() - 1):
		var velocity := (
			points[point_index] - previous_points[point_index]
		) / safe_delta
		maximum_particle_speed_squared = maxf(
			maximum_particle_speed_squared,
			velocity.length_squared()
		)
	if (
		not endpoint_moved
		and maximum_particle_speed_squared < 0.0025
		and raw_tension_newtons < 0.5
	):
		sleep_timer += delta
		if sleep_timer >= SLEEP_DELAY_SECONDS:
			simulation_sleeping = true
	else:
		sleep_timer = 0.0


func _update_power_transfer(delta: float) -> void:
	current_flow_w = 0.0
	current_direction = 0
	if (
		definition == null
		or not definition.transfers_power
		or definition.maximum_transfer_power_w <= 0.0
		or delta <= 0.0
	):
		return
	var state_a := _get_power_state(endpoint_a.body)
	var state_b := _get_power_state(endpoint_b.body)
	if state_a.is_empty() or state_b.is_empty():
		return
	var ratio_a := float(state_a.get("energy_wh", 0.0)) / maxf(
		float(state_a.get("capacity_wh", 0.0)),
		0.001
	)
	var ratio_b := float(state_b.get("energy_wh", 0.0)) / maxf(
		float(state_b.get("capacity_wh", 0.0)),
		0.001
	)
	if absf(ratio_a - ratio_b) < 0.002:
		return
	var source: PhysicsBody3D = endpoint_a.body if ratio_a > ratio_b else endpoint_b.body
	var sink: PhysicsBody3D = endpoint_b.body if ratio_a > ratio_b else endpoint_a.body
	var source_state: Dictionary = state_a if ratio_a > ratio_b else state_b
	var sink_state: Dictionary = state_b if ratio_a > ratio_b else state_a
	var maximum_power := minf(
		definition.maximum_transfer_power_w,
		minf(
			float(source_state.get("maximum_output_w", 0.0)),
			float(sink_state.get("maximum_input_w", 0.0))
		)
	)
	if maximum_power <= 0.0:
		return
	var efficiency := clampf(definition.transfer_efficiency, 0.001, 1.0)
	var source_energy := float(source_state.get("energy_wh", 0.0))
	var sink_room := maxf(
		float(sink_state.get("capacity_wh", 0.0))
		- float(sink_state.get("energy_wh", 0.0)),
		0.0
	)
	var requested_wh := minf(
		maximum_power * delta / 3600.0,
		minf(source_energy, sink_room / efficiency)
	)
	if requested_wh <= 0.0:
		return
	var extracted_wh := float(source.call("extract_rope_energy", requested_wh))
	var accepted_wh := float(sink.call(
		"receive_rope_energy",
		extracted_wh * efficiency
	))
	current_flow_w = accepted_wh * 3600.0 / delta
	current_direction = 1 if source == endpoint_a.body else -1


func _get_power_state(body: PhysicsBody3D) -> Dictionary:
	if (
		body == null
		or not body.has_method("get_rope_power_state")
		or not body.has_method("extract_rope_energy")
		or not body.has_method("receive_rope_energy")
	):
		return {}
	var result: Dictionary = body.call("get_rope_power_state")
	return result


func _calculate_path_length() -> float:
	var result := 0.0
	for point_index in range(points.size() - 1):
		result += points[point_index].distance_to(points[point_index + 1])
	return result
