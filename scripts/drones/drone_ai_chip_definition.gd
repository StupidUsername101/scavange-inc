@tool
class_name DroneAIChipDefinition
extends DronePartDefinition

#######################################################
# Defines the serialized drone ai chip configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Behavior Contract")
@export var behavior_id: StringName = &"unassigned"
@export_multiline var behavior_description := ""
@export var behavior_script: Script
@export var behavior_parameters: Dictionary = {}
@export_range(-100, 100, 1) var processing_priority := 0

@export_group("Finalized ML Model")
@export var finalized_model_id: String = ""
@export_file("*.json") var finalized_model_path: String = ""
@export_file("*.json") var finalized_manifest_path: String = ""
@export var finalized_body_signature: String = ""
@export var finalized_algorithm_id: String = ""

@export_group("Processing")
@export_range(0.01, 30.0, 0.01, "or_greater") var response_time := 0.25
@export_range(0.01, 1.0, 0.01) var processing_efficiency := 0.75
@export_range(0.01, 1.0, 0.01) var minimum_operating_power_ratio := 0.35

@export_group("Power")
@export_range(0.0, 10000.0, 0.01, "or_greater") var idle_power_draw := 1.0
@export_range(0.0, 10000.0, 0.01, "or_greater") var active_power_draw := 4.0

@export_group("Perception")
@export_range(0.1, 1000.0, 0.1, "or_greater") var sensor_range := 18.0
@export_range(0.0, 45.0, 0.05) var aim_error_degrees := 3.0
@export_range(0.0, 1.0, 0.0001) var friendly_identification_accuracy := 0.998

@export_group("Surge Durability")
@export_range(1.0, 5.0, 0.01, "or_greater") var damaging_spike_threshold := 1.3
@export_range(0.0, 20.0, 0.01, "or_greater") var surge_fragility := 1.0
@export var surge_immune := false

@export_group("Physical")
@export var body_size := Vector3(0.2, 0.035, 0.15)


func has_behavior_contract() -> bool:
	return (
		has_finalized_model_identity()
		or (
			not behavior_id.is_empty()
			and behavior_id != &"unassigned"
			and behavior_script != null
		)
	)


func has_finalized_model_identity() -> bool:
	return (
		behavior_id == &"trained_ml_policy"
		and not finalized_model_id.strip_edges().is_empty()
		and not finalized_body_signature.strip_edges().is_empty()
		and not finalized_algorithm_id.strip_edges().is_empty()
	)


func has_finalized_model_contract() -> bool:
	return (
		has_finalized_model_identity()
		and not finalized_model_path.strip_edges().is_empty()
		and not finalized_manifest_path.strip_edges().is_empty()
	)


func create_behavior() -> RefCounted:
	if behavior_script == null or not behavior_script.can_instantiate():
		return null
	return behavior_script.new() as RefCounted


func get_effective_response_time(power_ratio: float) -> float:
	var processing_rate := (
		maxf(processing_efficiency, 0.01)
		* clampf(power_ratio, 0.01, 1.0)
	)
	return maxf(response_time / processing_rate, 0.01)


func get_power_draw(activity: float) -> float:
	return maxf(
		idle_power_draw,
		active_power_draw * clampf(activity, 0.0, 1.0)
	)


func get_parameter(key: StringName, fallback: Variant) -> Variant:
	if behavior_parameters.has(key):
		return behavior_parameters[key]
	return behavior_parameters.get(String(key), fallback)


func get_follow_inner_radius() -> float:
	return maxf(float(get_parameter(&"inner_radius", 2.0)), 0.0)


func get_follow_outer_radius() -> float:
	return maxf(
		float(get_parameter(&"outer_radius", 4.0)),
		get_follow_inner_radius() + 0.1
	)


func get_follow_preferred_radius() -> float:
	var inner_radius := get_follow_inner_radius()
	var outer_radius := get_follow_outer_radius()
	return clampf(
		float(get_parameter(
			&"preferred_radius",
			(inner_radius + outer_radius) * 0.5
		)),
		inner_radius,
		outer_radius
	)


func get_follow_height_offset() -> float:
	return float(get_parameter(&"height_offset", 1.8))


func get_follow_mode() -> StringName:
	return StringName(get_parameter(&"follow_mode", &"roam"))


func get_follow_target_area_description() -> String:
	return "Target ring: %.1f - %.1f m from player" % [
		get_follow_inner_radius(),
		get_follow_outer_radius(),
	]


func get_navigation_speed_scale() -> float:
	return clampf(float(get_parameter(&"navigation_speed_scale", 1.0)), 0.05, 1.0)


func get_navigation_acceleration_scale() -> float:
	return clampf(
		float(get_parameter(&"navigation_acceleration_scale", 1.0)),
		0.05,
		1.0
	)


func get_navigation_jerk_scale() -> float:
	return clampf(float(get_parameter(&"navigation_jerk_scale", 1.0)), 0.05, 1.0)


func is_collision_avoidance_chip() -> bool:
	return behavior_id == &"orca_collision_avoidance"


func get_avoidance_neighbor_distance() -> float:
	return maxf(float(get_parameter(&"neighbor_distance", sensor_range)), 0.1)


func get_avoidance_time_horizon() -> float:
	return maxf(float(get_parameter(&"time_horizon", 2.0)), 0.05)


func get_avoidance_radius_padding() -> float:
	return maxf(float(get_parameter(&"radius_padding", 0.2)), 0.0)


func get_avoidance_vertical_tolerance() -> float:
	return maxf(float(get_parameter(&"vertical_tolerance", 1.0)), 0.1)


func get_avoidance_max_neighbors() -> int:
	return maxi(int(get_parameter(&"max_neighbors", 8)), 1)

func ml_part_tags() -> Array[StringName]:
	return [&"drone_part", &"ai_chip"]
