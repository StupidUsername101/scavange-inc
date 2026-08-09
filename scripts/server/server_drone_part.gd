extends RigidBody3D

const PART_GEOMETRY := preload(
	"res://scripts/drones/drone_part_geometry.gd"
)

#######################################################
# Owns authoritative drone part simulation and exposes the state required for replication and
# interaction.
#######################################################

@export var definition: DronePartDefinition

var drone_part_id := -1
var part_token_id := -1
var battery_energy_wh := -1.0
var core_health := -1.0
var broken := false


func configure(
	new_definition: DronePartDefinition,
	new_battery_energy_wh := -1.0,
	new_core_health := -1.0,
	new_part_token_id := -1,
	is_broken := false
) -> void:
	definition = new_definition
	battery_energy_wh = new_battery_energy_wh
	core_health = new_core_health
	part_token_id = new_part_token_id
	broken = is_broken

	if is_node_ready():
		_rebuild_from_definition()


func _ready() -> void:
	add_to_group("drone_parts")
	_rebuild_from_definition()

	if part_token_id == -1:
		part_token_id = Server.allocate_drone_part_token_id()
	drone_part_id = Server.register_drone_part(self)


func _exit_tree() -> void:
	if drone_part_id != -1:
		Server.unregister_drone_part(drone_part_id)


func _rebuild_from_definition() -> void:
	if definition == null:
		$CollisionShape3D.shape = null
		return

	mass = maxf(definition.get_mass(), 0.001)
	$CollisionShape3D.shape = (
		PART_GEOMETRY.create_collision_shape(definition)
	)

	if definition is DroneBatteryDefinition and battery_energy_wh < 0.0:
		battery_energy_wh = (
			definition as DroneBatteryDefinition
		).energy_capacity_wh
	if definition is DroneCoreDefinition and core_health < 0.0:
		core_health = (
			definition as DroneCoreDefinition
		).max_health


func get_drone_part_definition() -> DronePartDefinition:
	return definition


func get_inspectable_definition() -> Resource:
	return definition


func get_part_kind() -> StringName:
	if definition == null:
		return &"unknown"
	return PART_GEOMETRY.get_part_kind(definition)


func is_operational() -> bool:
	return not broken


func get_rope_power_state() -> Dictionary:
	var battery := definition as DroneBatteryDefinition
	if battery == null or broken:
		return {}
	return {
		"capacity_wh": battery.energy_capacity_wh,
		"energy_wh": clampf(
			battery_energy_wh,
			0.0,
			battery.energy_capacity_wh
		),
		"maximum_output_w": battery.maximum_power_output,
		"maximum_input_w": battery.maximum_power_output,
	}


func extract_rope_energy(requested_wh: float) -> float:
	var battery := definition as DroneBatteryDefinition
	if battery == null or broken:
		return 0.0
	var extracted := minf(maxf(requested_wh, 0.0), battery_energy_wh)
	battery_energy_wh -= extracted
	return extracted


func receive_rope_energy(offered_wh: float) -> float:
	var battery := definition as DroneBatteryDefinition
	if battery == null or broken:
		return 0.0
	var accepted := minf(
		maxf(offered_wh, 0.0),
		maxf(battery.energy_capacity_wh - battery_energy_wh, 0.0)
	)
	battery_energy_wh += accepted
	return accepted


func to_state_dict() -> Dictionary:
	return {
		"drone_part_id": drone_part_id,
		"part_token_id": part_token_id,
		"definition_path": (
			definition.resource_path
			if definition != null
			else ""
		),
		"battery_energy_wh": battery_energy_wh,
		"core_health": core_health,
		"broken": broken,
		"warehouse_display_name": str(get_meta(
			"dev_warehouse_display_name",
			""
		)),
		"pos": global_position,
		"rot": global_rotation,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
	}
