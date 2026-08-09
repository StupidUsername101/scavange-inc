@tool
class_name DroneWeaponDefinition
extends DroneAttachmentDefinition

#######################################################
# Defines the serialized drone weapon configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Weapon Contract")
@export_range(0.0, 100000.0, 0.1, "or_greater") var damage_per_shot := 8.0
@export_range(0.01, 1000.0, 0.01, "or_greater") var rounds_per_second := 3.0
@export_range(0.1, 10000.0, 0.1, "or_greater") var effective_range := 24.0
@export_range(0.0, 180.0, 0.1) var traverse_arc_degrees := 70.0
@export_range(0.0, 10000.0, 0.1, "or_greater") var projectile_speed := 45.0
@export var projectile_definition: BallisticProjectileDefinition


func _init() -> void:
	if &"weapon" not in capability_tags:
		capability_tags.append(&"weapon")


func get_ballistic_profile() -> Dictionary:
	var profile := (
		projectile_definition.to_ballistic_profile()
		if projectile_definition != null
		else {
			"damage": damage_per_shot,
			"muzzle_velocity": projectile_speed,
			"maximum_range": effective_range,
			"gravity_scale": 0.1,
			"impact_impulse": 0.5,
			"tracer_color": visual_color.lightened(0.32),
			"tracer_length": 0.7,
			"tracer_radius": 0.016,
		}
	)
	profile["damage"] = damage_per_shot
	profile["muzzle_velocity"] = projectile_speed
	profile["maximum_range"] = effective_range
	return BallisticProjectileDefinition.normalize_profile(profile)


func get_muzzle_distance() -> float:
	return maxf(body_size.z * 1.22, 0.18)
