@tool
class_name DroneBatteryDefinition
extends DronePartDefinition

#######################################################
# Defines the serialized drone battery configuration shared by gameplay, inspection, and
# replication systems.
#######################################################

@export_group("Energy")
@export_range(0.001, 100000.0, 0.001, "or_greater") var energy_capacity_wh := 1.6
@export_range(0.1, 1000.0, 0.1, "or_greater") var nominal_voltage_v := 12.0
@export_range(0.0, 1000000.0, 0.1, "or_greater") var nominal_power_output := 96.0
@export_range(0.0, 1000000.0, 0.1, "or_greater") var maximum_power_output := 130.0
@export var body_size := Vector3(0.35, 0.12, 0.26)

@export_group("Consistency")
@export_range(0.0, 1.0, 0.001) var power_output_consistency := 0.96
@export_range(0.0, 100.0, 0.01, "or_greater") var fluctuation_rate := 0.8

@export_group("Spikes")
@export_range(0.0, 100.0, 0.001, "or_greater") var spike_chance_per_second := 0.08
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_spike_duration := 0.12
@export_range(0.01, 10.0, 0.01, "or_greater") var maximum_spike_duration := 0.4
@export_range(0.0, 1.0, 0.01) var minimum_drop_multiplier := 0.55
@export_range(0.0, 1.0, 0.01) var maximum_drop_multiplier := 0.8
@export_range(1.0, 5.0, 0.01, "or_greater") var minimum_boost_multiplier := 1.15
@export_range(1.0, 5.0, 0.01, "or_greater") var maximum_boost_multiplier := 1.35

@export_group("Electronics Protection")
@export_range(0.0, 1.0, 0.01) var surge_protection := 0.55
@export_range(0.0, 1.0, 0.001) var extreme_spike_damage_coupling := 0.04

func ml_part_tags() -> Array[StringName]:
	return [&"drone_part", &"battery"]
