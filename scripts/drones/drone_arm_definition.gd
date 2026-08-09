@tool
class_name DroneArmDefinition
extends DroneAttachmentDefinition

#######################################################
# Defines the serialized drone arm configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Manipulator Contract")
@export_range(0.0, 100000.0, 0.1, "or_greater") var manipulation_force := 45.0
@export_range(0.0, 100.0, 0.05, "or_greater") var reach := 1.2
@export_range(0.0, 100000.0, 0.1, "or_greater") var rotation_torque := 18.0


func _init() -> void:
	if &"manipulator" not in capability_tags:
		capability_tags.append(&"manipulator")
