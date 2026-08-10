@tool
class_name DroneCoreDefinition
extends DronePartDefinition

#######################################################
# Defines the serialized drone core configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Core")
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_health := 100.0
@export_range(0.0, 1000000.0, 1.0, "or_greater") var max_power_throughput := 120.0
@export_range(0, 32, 1, "or_greater") var propeller_slot_count := 4
@export_range(0, 8, 1) var ai_chip_slot_count := 2
@export_range(0, 32, 1, "or_greater") var attachment_slot_count: int = 2
@export var body_size := Vector3(0.65, 0.24, 0.65)

@export_group("AI Flight Authority")
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_horizontal_speed := 4.0
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_horizontal_acceleration := 5.5
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_vertical_speed := 4.5
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_max_vertical_acceleration := 7.0
@export_range(0.0, 75.0, 0.1, "or_greater") var ai_max_tilt_degrees := 26.0
@export_range(0.0, 10.0, 0.01, "or_greater") var ai_horizontal_position_gain := 0.9
@export_range(0.0, 20.0, 0.01, "or_greater") var ai_horizontal_velocity_gain := 2.25
@export_range(0.0, 10.0, 0.01, "or_greater") var ai_altitude_position_gain := 1.8
@export_range(0.0, 20.0, 0.01, "or_greater") var ai_altitude_velocity_gain := 2.8
@export_range(0.0, 100.0, 0.05, "or_greater") var ai_attitude_response := 18.0
@export_range(0.0, 30.0, 0.05, "or_greater") var ai_angular_velocity_damping := 5.5
@export_range(0.0, 1.0, 0.01) var ai_motor_mix_authority := 0.42
@export_range(0.0, 20.0, 0.05, "or_greater") var ai_emergency_upright_torque := 1.25

# Kept as a resource compatibility alias. New flight code uses the explicit
# vertical speed/acceleration envelope above.
@export_range(0.0, 5.0, 0.01, "or_greater") var ai_altitude_authority := 0.18

@export_group("Power Response")
@export_range(0.01, 100.0, 0.05, "or_greater") var spool_up_response := 1.5
@export_range(0.01, 100.0, 0.05, "or_greater") var spool_down_response := 2.5
@export_range(0.0, 1.0, 0.001) var power_output_consistency := 0.985
@export_range(0.0, 100.0, 0.01, "or_greater") var fluctuation_rate := 0.35

@export_group("Aerodynamics")
@export_range(0.001, 1000.0, 0.001, "or_greater") var drag_area := 0.45
@export_range(0.0, 10.0, 0.01, "or_greater") var drag_coefficient := 1.05
@export_range(0.0, 1000.0, 0.01, "or_greater") var angular_drag_coefficient := 0.35

func ml_part_tags() -> Array[StringName]:
	return [&"drone_part", &"core"]
