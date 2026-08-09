class_name TrainingPathTargetSystem
extends TrainingTargetSystem

#######################################################
# Current moving-target implementation extracted into a reusable per-group system. Every
# instance owns its configuration and runtime state, so two worker groups can use the same
# target type with completely different behaviours without changing policy observations.
#######################################################

const TYPE_ID: StringName = &"navigation_path"
const DISPLAY_NAME = "Navigation path"
const BEHAVIORS: Array[String] = [
	"Stationary", "Orbit", "Line", "Random waypoints", "Manual pad",
]
const MANUAL_BEHAVIOR = 4
# The path system stores literal policy objective coordinates. Five metres preserves the
# historical drone objective (old subject Y=3 plus a hidden +2 m hover offset) without
# keeping two different meanings for the same height field.
const DEFAULT_SUBJECT_POSITION = Vector3(0.0, 5.0, 0.0)

var behavior: int = 0
var speed_mps: float = 1.0
var hover_radius_m: float = 0.75
var base_height_m: float = DEFAULT_SUBJECT_POSITION.y
var path_radius_m: float = 4.0
var path_rotation_degrees: Vector3 = Vector3.ZERO
var path_phase_degrees: float = 0.0
var path_reverse: bool = false
var line_half_length_m: float = 6.0
var random_horizontal_extent_m: Vector2 = Vector2(8.0, 5.0)
var random_height_range_m: Vector2 = Vector2(3.5, 7.5)
var random_max_jump_distance_m: float = 8.0
var random_waypoint_interval_seconds: float = 5.0
var manual_subject_position: Vector3 = DEFAULT_SUBJECT_POSITION
var random_area_visible: bool = false

var subject_position_world: Vector3 = DEFAULT_SUBJECT_POSITION
var target_velocity_world: Vector3 = Vector3.ZERO
var elapsed_seconds: float = 0.0
var random_target_world: Vector3 = DEFAULT_SUBJECT_POSITION
var random_timer_seconds: float = 0.0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var candidate_instance_key: String = ""
var candidate_metadata: Dictionary = {
	"behavior": "Stationary",
	"subject_position_world": DEFAULT_SUBJECT_POSITION,
}
var candidate_record: Dictionary = {
	"available": true,
	"stable_id": "",
	"system_type_id": str(TYPE_ID),
	"target_kind": "navigation",
	"shootable": true,
	"position_world": DEFAULT_SUBJECT_POSITION,
	"velocity_world": Vector3.ZERO,
	"radius_m": 0.75,
	"priority_bias": 0.0,
	"urgency": 0.0,
	"distance_weight": 0.0,
	"metadata": {},
}


func type_id() -> StringName:
	return TYPE_ID


func display_name() -> String:
	return DISPLAY_NAME


func behavior_name() -> String:
	if behavior < 0 or behavior >= BEHAVIORS.size():
		return "Unknown"
	return BEHAVIORS[behavior]


func objective_position_world() -> Vector3:
	# Navigation-path coordinates are already policy objective coordinates. Body-specific
	# offsets belong in the body coordinator (for example, limb core height above a support
	# surface), not in this shared target primitive.
	return subject_position_world


func reset(seed: int, _context: Dictionary = {}) -> void:
	elapsed_seconds = 0.0
	target_velocity_world = Vector3.ZERO
	rng.seed = seed
	if behavior == MANUAL_BEHAVIOR:
		subject_position_world = manual_subject_position
		subject_position_world.y = base_height_m
	elif behavior == 3:
		subject_position_world = _random_area_point()
		random_target_world = _choose_random_waypoint(subject_position_world)
		random_timer_seconds = maxf(random_waypoint_interval_seconds, 0.1)
	else:
		subject_position_world = Vector3(0.0, base_height_m, 0.0)
		random_target_world = subject_position_world
		random_timer_seconds = 0.0
	# Preserve the original room behavior: stationary/orbit/line targets reset to their
	# center and advance to the configured phase on the first physics tick.


func tick(delta: float, _context: Dictionary = {}) -> void:
	if not enabled:
		target_velocity_world = Vector3.ZERO
		return
	var safe_delta: float = maxf(RLTrainingMath.finite_float_or(delta, 0.0), 0.0)
	elapsed_seconds += safe_delta
	_tick_path(safe_delta)


func _tick_path(delta: float) -> void:
	var previous_position: Vector3 = subject_position_world
	var path_center: Vector3 = Vector3(0.0, base_height_m, 0.0)
	var next_subject_position: Vector3 = subject_position_world
	match behavior:
		0:
			next_subject_position = path_center
		1:
			var orbit_direction: float = -1.0 if path_reverse else 1.0
			var orbit_phase: float = deg_to_rad(path_phase_degrees)
			var orbit_basis: Basis = _path_basis()
			var orbit_angle: float = orbit_phase + (
				orbit_direction
				* elapsed_seconds
				* speed_mps
				/ maxf(path_radius_m, 0.001)
			)
			next_subject_position = path_center + orbit_basis * Vector3(
				cos(orbit_angle),
				0.0,
				sin(orbit_angle)
			) * path_radius_m
		2:
			var line_direction: float = -1.0 if path_reverse else 1.0
			var line_phase: float = deg_to_rad(path_phase_degrees)
			var line_basis: Basis = _path_basis()
			var line_angle: float = line_phase + (
				line_direction
				* elapsed_seconds
				* speed_mps
				/ maxf(line_half_length_m, 0.001)
			)
			next_subject_position = path_center + line_basis * Vector3(
				sin(line_angle) * line_half_length_m,
				0.0,
				0.0
			)
		3:
			random_timer_seconds -= delta
			if random_timer_seconds <= 0.0:
				random_timer_seconds = maxf(random_waypoint_interval_seconds, 0.1)
				random_target_world = _choose_random_waypoint(subject_position_world)
			next_subject_position = subject_position_world.move_toward(
				random_target_world,
				maxf(speed_mps, 0.0) * delta
			)
		MANUAL_BEHAVIOR:
			next_subject_position = subject_position_world.move_toward(
				manual_subject_position,
				maxf(speed_mps, 0.0) * delta
			)
	subject_position_world = next_subject_position
	target_velocity_world = (
		(subject_position_world - previous_position) / delta
		if delta > 0.0
		else Vector3.ZERO
	)

func _path_basis() -> Basis:
	return Basis.from_euler(Vector3(
		deg_to_rad(path_rotation_degrees.x),
		deg_to_rad(path_rotation_degrees.y),
		deg_to_rad(path_rotation_degrees.z)
	))


func append_candidates(output: Array[Dictionary], _context: Dictionary = {}) -> void:
	if not enabled:
		return
	if candidate_instance_key != instance_key:
		candidate_instance_key = instance_key
		candidate_record["stable_id"] = "%s:navigation" % instance_key
	candidate_record["position_world"] = objective_position_world()
	candidate_record["velocity_world"] = target_velocity_world
	candidate_record["radius_m"] = maxf(hover_radius_m, 0.05)
	candidate_metadata["behavior"] = behavior_name()
	candidate_metadata["subject_position_world"] = subject_position_world
	candidate_record["metadata"] = candidate_metadata
	output.append(candidate_record)


func set_behavior(next_behavior: int) -> void:
	behavior = clampi(next_behavior, 0, BEHAVIORS.size() - 1)
	if behavior == MANUAL_BEHAVIOR:
		manual_subject_position = subject_position_world
		manual_subject_position.y = base_height_m


func set_base_height(value: float) -> void:
	if not is_finite(value):
		return
	base_height_m = value
	manual_subject_position.y = value
	if behavior == MANUAL_BEHAVIOR:
		subject_position_world = manual_subject_position
	elif behavior in [0, 1, 2]:
		_tick_path(0.0)
	elif behavior == 3:
		subject_position_world.y = value
	target_velocity_world = Vector3.ZERO


func move_manual_target(subject_position: Vector3) -> void:
	if not subject_position.is_finite():
		return
	manual_subject_position = subject_position
	manual_subject_position.y = base_height_m
	behavior = MANUAL_BEHAVIOR
	subject_position_world = manual_subject_position
	target_velocity_world = Vector3.ZERO


func random_area_point() -> Vector3:
	return _random_area_point()


func choose_random_waypoint(origin: Vector3) -> Vector3:
	return _choose_random_waypoint(origin)


func _random_area_point() -> Vector3:
	var x_extent: float = absf(random_horizontal_extent_m.x)
	var z_extent: float = absf(random_horizontal_extent_m.y)
	var minimum_height: float = minf(random_height_range_m.x, random_height_range_m.y)
	var maximum_height: float = maxf(random_height_range_m.x, random_height_range_m.y)
	return Vector3(
		rng.randf_range(-x_extent, x_extent),
		rng.randf_range(minimum_height, maximum_height),
		rng.randf_range(-z_extent, z_extent)
	)


func _choose_random_waypoint(origin: Vector3) -> Vector3:
	var maximum_jump: float = maxf(random_max_jump_distance_m, 0.1)
	var candidate: Vector3 = _random_area_point()
	var offset: Vector3 = candidate - origin
	if offset.length() > maximum_jump:
		candidate = origin + offset.normalized() * maximum_jump
	return candidate


func configuration_dictionary() -> Dictionary:
	return {
		"type_id": str(TYPE_ID),
		"enabled": enabled,
		"behavior": behavior,
		"speed_mps": speed_mps,
		"hover_radius_m": hover_radius_m,
		"base_height_m": base_height_m,
		"path_radius_m": path_radius_m,
		"path_rotation_degrees": [
			path_rotation_degrees.x,
			path_rotation_degrees.y,
			path_rotation_degrees.z,
		],
		"path_phase_degrees": path_phase_degrees,
		"path_reverse": path_reverse,
		"line_half_length_m": line_half_length_m,
		"random_horizontal_extent_m": [
			random_horizontal_extent_m.x,
			random_horizontal_extent_m.y,
		],
		"random_height_range_m": [
			random_height_range_m.x,
			random_height_range_m.y,
		],
		"random_max_jump_distance_m": random_max_jump_distance_m,
		"random_waypoint_interval_seconds": random_waypoint_interval_seconds,
		"manual_subject_position": [
			manual_subject_position.x,
			manual_subject_position.y,
			manual_subject_position.z,
		],
		"random_area_visible": random_area_visible,
	}


func load_configuration(configuration: Dictionary) -> void:
	super.load_configuration(configuration)
	behavior = clampi(RLTrainingMath.finite_int_or(configuration.get("behavior", behavior), behavior), 0, BEHAVIORS.size() - 1)
	speed_mps = maxf(RLTrainingMath.finite_float_or(configuration.get("speed_mps", speed_mps), speed_mps), 0.0)
	hover_radius_m = maxf(RLTrainingMath.finite_float_or(configuration.get("hover_radius_m", hover_radius_m), hover_radius_m), 0.05)
	base_height_m = RLTrainingMath.finite_float_or(configuration.get("base_height_m", base_height_m), base_height_m)
	path_radius_m = maxf(RLTrainingMath.finite_float_or(configuration.get("path_radius_m", path_radius_m), path_radius_m), 0.001)
	var rotation_value: Variant = configuration.get("path_rotation_degrees", [])
	if rotation_value is Array and (rotation_value as Array).size() >= 3:
		path_rotation_degrees = Vector3(
			RLTrainingMath.finite_float_or((rotation_value as Array)[0], path_rotation_degrees.x),
			RLTrainingMath.finite_float_or((rotation_value as Array)[1], path_rotation_degrees.y),
			RLTrainingMath.finite_float_or((rotation_value as Array)[2], path_rotation_degrees.z)
		)
	path_phase_degrees = RLTrainingMath.finite_float_or(
		configuration.get("path_phase_degrees", path_phase_degrees),
		path_phase_degrees
	)
	path_reverse = RLTrainingMath.bool_or(configuration.get("path_reverse", path_reverse), path_reverse)
	line_half_length_m = maxf(RLTrainingMath.finite_float_or(
		configuration.get("line_half_length_m", line_half_length_m),
		line_half_length_m
	), 0.001)
	var horizontal_value: Variant = configuration.get("random_horizontal_extent_m", [])
	if horizontal_value is Array and (horizontal_value as Array).size() >= 2:
		random_horizontal_extent_m = Vector2(
			RLTrainingMath.finite_float_or((horizontal_value as Array)[0], random_horizontal_extent_m.x),
			RLTrainingMath.finite_float_or((horizontal_value as Array)[1], random_horizontal_extent_m.y)
		)
	var height_value: Variant = configuration.get("random_height_range_m", [])
	if height_value is Array and (height_value as Array).size() >= 2:
		random_height_range_m = Vector2(
			RLTrainingMath.finite_float_or((height_value as Array)[0], random_height_range_m.x),
			RLTrainingMath.finite_float_or((height_value as Array)[1], random_height_range_m.y)
		)
	random_max_jump_distance_m = maxf(RLTrainingMath.finite_float_or(
		configuration.get("random_max_jump_distance_m", random_max_jump_distance_m),
		random_max_jump_distance_m
	), 0.1)
	random_waypoint_interval_seconds = maxf(RLTrainingMath.finite_float_or(
		configuration.get("random_waypoint_interval_seconds", random_waypoint_interval_seconds),
		random_waypoint_interval_seconds
	), 0.1)
	var manual_value: Variant = configuration.get("manual_subject_position", [])
	if manual_value is Array and (manual_value as Array).size() >= 3:
		manual_subject_position = Vector3(
			RLTrainingMath.finite_float_or((manual_value as Array)[0], manual_subject_position.x),
			RLTrainingMath.finite_float_or((manual_value as Array)[1], manual_subject_position.y),
			RLTrainingMath.finite_float_or((manual_value as Array)[2], manual_subject_position.z)
		)
	else:
		manual_subject_position.y = base_height_m
	random_area_visible = RLTrainingMath.bool_or(configuration.get("random_area_visible", random_area_visible), random_area_visible)


func clone_configured() -> TrainingTargetSystem:
	var result: TrainingPathTargetSystem = TrainingPathTargetSystem.new()
	result.load_configuration(configuration_dictionary())
	return result
