class_name DronePropellerSlot
extends Node3D

#######################################################
# Implements the drone propeller slot subsystem and keeps its gameplay data and behavior in
# one focused script.
#######################################################

@export_range(0, 31, 1, "or_greater") var slot_index := 0
@export_enum("Counter-clockwise:-1", "Clockwise:1") var spin_direction := 1
