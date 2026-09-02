@tool
class_name PlasmaCutterDefinition
extends ItemDefinition

## Inventory item and authored operating envelope for a handheld plasma cutter. Gameplay reads
## this resource on the server; clients receive only its public item state and replicated beam.

const MIN_RANGE_METERS := 0.25
const MAX_RANGE_METERS := 12.0
const MIN_PULSE_INTERVAL := 0.04
const MAX_PULSE_INTERVAL := 0.5

@export_group("Cut")
@export_range(MIN_RANGE_METERS, MAX_RANGE_METERS, 0.05) var range_meters := 4.5
@export_range(0.005, 0.25, 0.005) var cut_radius := 0.055
@export_range(0.01, 1.0, 0.01) var cut_depth := 0.18
@export_range(0.01, 1000.0, 0.05) var destruction_energy := 5.5
@export_range(0.0, 1000.0, 0.05) var heat_energy := 18.0
@export_range(0.0, 250.0, 0.5) var contact_damage_per_second := 32.0
@export_range(MIN_PULSE_INTERVAL, MAX_PULSE_INTERVAL, 0.005) var pulse_interval := 0.085

@export_group("Thermal")
@export_range(0.01, 1.0, 0.01) var heat_per_discharge := 1.0
@export_range(0.01, 2.0, 0.01) var cooling_per_second := 0.26
@export_range(0.0, 0.95, 0.01) var overheat_recovery_ratio := 0.28


func sanitize() -> PlasmaCutterDefinition:
	range_meters = clampf(_finite_or(range_meters, 4.5), MIN_RANGE_METERS, MAX_RANGE_METERS)
	cut_radius = clampf(_finite_or(cut_radius, 0.055), 0.005, 0.25)
	cut_depth = clampf(_finite_or(cut_depth, 0.18), 0.01, 1.0)
	destruction_energy = clampf(_finite_or(destruction_energy, 5.5), 0.01, 1000.0)
	heat_energy = clampf(_finite_or(heat_energy, 18.0), 0.0, 1000.0)
	contact_damage_per_second = clampf(
		_finite_or(contact_damage_per_second, 32.0),
		0.0,
		250.0
	)
	pulse_interval = clampf(
		_finite_or(pulse_interval, 0.085),
		MIN_PULSE_INTERVAL,
		MAX_PULSE_INTERVAL
	)
	heat_per_discharge = clampf(_finite_or(heat_per_discharge, 1.0), 0.01, 1.0)
	cooling_per_second = clampf(_finite_or(cooling_per_second, 0.26), 0.01, 2.0)
	overheat_recovery_ratio = clampf(
		_finite_or(overheat_recovery_ratio, 0.28),
		0.0,
		0.95
	)
	return self


func continuous_duty_seconds() -> float:
	return pulse_interval * ceilf(1.0 / maxf(heat_per_discharge, 0.01))


func full_cool_seconds() -> float:
	return 1.0 / maxf(cooling_per_second, 0.01)


func display_stats() -> Dictionary:
	sanitize()
	return {
		"range_meters": range_meters,
		"kerf_millimeters": cut_radius * 2000.0,
		"cut_depth_millimeters": cut_depth * 1000.0,
		"continuous_duty_seconds": continuous_duty_seconds(),
		"full_cool_seconds": full_cool_seconds(),
		"pulse_hz": 1.0 / pulse_interval,
	}


func instantiate_held_visual(
	_state: Dictionary,
	_first_person := false
) -> Node3D:
	var visual := (
		visual_scene.instantiate() as Node3D
		if visual_scene != null
		else Node3D.new()
	)
	return visual


func get_held_presentation_profile(_state: Dictionary) -> StringName:
	return ItemDefinition.HELD_PROFILE_TOOL


func get_inventory_status_text(_state: Dictionary) -> String:
	return ""


static func _finite_or(value: float, fallback: float) -> float:
	return value if is_finite(value) else fallback
