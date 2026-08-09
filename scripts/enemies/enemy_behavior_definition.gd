@tool
class_name EnemyBehaviorDefinition
extends Resource

#######################################################
# Defines the serialized enemy behavior configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

enum BehaviorType {
	STATIONARY,
	HUNT_ACTIVATING_PLAYER,
}

@export var behavior_type := BehaviorType.STATIONARY

@export_group("Awareness")
@export_range(0.0, 200.0, 0.1, "or_greater") var notice_range := 12.0
@export_range(0.0, 20.0, 0.05, "or_greater") var preferred_distance := 1.6

@export_group("Locomotion")
@export_range(0.0, 30.0, 0.05, "or_greater") var maximum_speed := 2.5
@export_range(0.0, 100.0, 0.1, "or_greater") var acceleration := 8.0
@export_range(0.0, 30.0, 0.1, "or_greater") var turn_speed_radians := 5.0
@export_range(0.0, 100.0, 0.1, "or_greater") var roam_radius := 4.0

@export_group("Attack")
@export_range(0.0, 20.0, 0.05, "or_greater") var attack_range := 1.8
@export_range(0.05, 30.0, 0.05, "or_greater") var attack_cooldown := 1.2
@export_range(0.0, 10000.0, 0.1, "or_greater") var attack_damage := 18.0


func can_move() -> bool:
	return (
		behavior_type == BehaviorType.HUNT_ACTIVATING_PLAYER
		and maximum_speed > 0.0
	)
