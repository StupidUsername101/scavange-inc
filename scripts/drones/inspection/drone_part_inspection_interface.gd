extends Resource

const PERCENT_SCALE := 100.0
const MINIMUM_ENERGY_CAPACITY := 0.001
const FOLLOW_BEHAVIOR_ID := &"follow_player"
const NAVIGATION_BEHAVIOR_IDS := [
	&"follow_player",
	&"guard_sphere",
	&"waypoint_guard",
]

#######################################################
# Builds scanner documents that expose drone-part capabilities, condition, power behavior, and
# compatibility.
#######################################################

## Converts a part definition into a recursive scanner document.
##
## Every node has the same shape: title, subtitle, scalar values and child
## nodes. The terminal can therefore zoom into any node without knowing which
## part type produced it, and new part interfaces can add arbitrary depth.

enum InterfaceKind {
	CORE,
	BATTERY,
	PROPELLER,
	AI_CHIP,
	WEAPON,
	ARM,
	ATTACHMENT,
}

@export var interface_kind: InterfaceKind = InterfaceKind.CORE
@export var type_label := "Drone Part"


func supports(definition: Resource) -> bool:
	var drone_part := definition as DronePartDefinition
	if drone_part == null:
		return false
	match interface_kind:
		InterfaceKind.CORE:
			return drone_part is DroneCoreDefinition
		InterfaceKind.BATTERY:
			return drone_part is DroneBatteryDefinition
		InterfaceKind.PROPELLER:
			return drone_part is DronePropellerDefinition
		InterfaceKind.AI_CHIP:
			return drone_part is DroneAIChipDefinition
		InterfaceKind.WEAPON:
			return drone_part is DroneWeaponDefinition
		InterfaceKind.ARM:
			return drone_part is DroneArmDefinition
		InterfaceKind.ATTACHMENT:
			return (
				drone_part is DroneAttachmentDefinition
				and not (drone_part is DroneWeaponDefinition)
				and not (drone_part is DroneArmDefinition)
			)
	return false


func build_document(
	definition: Resource,
	runtime_state: Dictionary
) -> Dictionary:
	var drone_part := definition as DronePartDefinition
	if drone_part == null:
		return {}
	var children: Array = []
	match interface_kind:
		InterfaceKind.CORE:
			children = _build_core_groups(
				definition as DroneCoreDefinition,
				runtime_state
			)
		InterfaceKind.BATTERY:
			children = _build_battery_groups(
				definition as DroneBatteryDefinition,
				runtime_state
			)
		InterfaceKind.PROPELLER:
			children = _build_propeller_groups(
				definition as DronePropellerDefinition
			)
		InterfaceKind.AI_CHIP:
			children = _build_ai_chip_groups(
				definition as DroneAIChipDefinition
			)
		InterfaceKind.WEAPON:
			children = _build_weapon_groups(
				definition as DroneWeaponDefinition
			)
		InterfaceKind.ARM:
			children = _build_arm_groups(
				definition as DroneArmDefinition
			)
		InterfaceKind.ATTACHMENT:
			children = _build_attachment_groups(
				definition as DroneAttachmentDefinition
			)

	return InspectionDocumentBuilder.node(
		drone_part.display_name,
		"%s diagnostic overview" % type_label,
		[
			InspectionDocumentBuilder.stat("Type", type_label),
			InspectionDocumentBuilder.stat("Quality", _quality_name(drone_part.quality)),
			InspectionDocumentBuilder.stat("Condition", _condition_name(runtime_state)),
			InspectionDocumentBuilder.stat("Mass", "%.3f kg" % drone_part.get_mass()),
		],
		children
	)


func _build_core_groups(
	core: DroneCoreDefinition,
	runtime_state: Dictionary
) -> Array:
	var current_health: float = float(runtime_state.get(
		"core_health",
		core.max_health
	))
	if current_health < 0.0:
		current_health = core.max_health

	return [
		_build_core_power_group(core),
		_build_core_expansion_group(core),
		_build_core_health_group(core, current_health),
		_build_core_body_group(core),
		_build_core_flight_group(core),
	]


func _build_core_power_group(core: DroneCoreDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Power systems",
		"Distribution, stability and motor response",
		[InspectionDocumentBuilder.stat("Throughput", "%.1f W" % core.max_power_throughput)],
		[
			InspectionDocumentBuilder.node(
				"Output stability",
				"Power regulation characteristics",
				[
					InspectionDocumentBuilder.stat(
						"Consistency",
						"%.1f%%" % (
							core.power_output_consistency * PERCENT_SCALE
						)
					),
					InspectionDocumentBuilder.stat(
						"Fluctuation rate",
						"%.2f Hz" % core.fluctuation_rate
					),
				]
			),
			InspectionDocumentBuilder.node(
				"Motor response",
				"Core-side propeller spool control",
				[
					InspectionDocumentBuilder.stat("Spool up", "%.2f" % core.spool_up_response),
					InspectionDocumentBuilder.stat("Spool down", "%.2f" % core.spool_down_response),
				]
			),
		]
	)


func _build_core_expansion_group(core: DroneCoreDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Expansion bus",
		"Physical sockets exposed by this core",
		[
			InspectionDocumentBuilder.stat("Propellers", "%d sockets" % core.propeller_slot_count),
			InspectionDocumentBuilder.stat("AI chips", "%d sockets" % core.ai_chip_slot_count),
			InspectionDocumentBuilder.stat("Belly rail", "%d sockets" % core.attachment_slot_count),
		]
	)


func _build_core_health_group(
	core: DroneCoreDefinition,
	current_health: float
) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Structural health",
		"Runtime condition of the core chassis",
		[
			InspectionDocumentBuilder.stat(
				"Health",
				"%.1f / %.1f" % [current_health, core.max_health]
			),
			InspectionDocumentBuilder.stat("Maximum health", "%.1f" % core.max_health),
		]
	)


func _build_core_body_group(core: DroneCoreDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Flight body",
		"Aerodynamic contribution of the core housing",
		[
			InspectionDocumentBuilder.stat("Drag area", "%.3f m²" % core.drag_area),
			InspectionDocumentBuilder.stat("Drag coefficient", "%.3f" % core.drag_coefficient),
			InspectionDocumentBuilder.stat("Angular drag", "%.3f" % core.angular_drag_coefficient),
			InspectionDocumentBuilder.stat("Chassis size", _format_size(core.body_size)),
		]
	)


func _build_core_flight_group(core: DroneCoreDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"AI flight authority",
		"Cascaded position, velocity and attitude controller",
		[
			InspectionDocumentBuilder.stat("Maximum speed", "%.2f m/s" % core.ai_max_horizontal_speed),
			InspectionDocumentBuilder.stat("Maximum tilt", "%.1f°" % core.ai_max_tilt_degrees),
		],
		[
			_build_core_motion_envelope(core),
			_build_core_guidance_loop(core),
			_build_core_attitude_loop(core),
		]
	)


func _build_core_motion_envelope(core: DroneCoreDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Motion envelope",
		"Bounded translational commands",
		[
			InspectionDocumentBuilder.stat(
				"Horizontal speed",
				"%.2f m/s" % core.ai_max_horizontal_speed
			),
			InspectionDocumentBuilder.stat(
				"Horizontal accel.",
				"%.2f m/s²" % core.ai_max_horizontal_acceleration
			),
			InspectionDocumentBuilder.stat("Vertical speed", "%.2f m/s" % core.ai_max_vertical_speed),
			InspectionDocumentBuilder.stat(
				"Vertical accel.",
				"%.2f m/s²" % core.ai_max_vertical_acceleration
			),
		]
	)


func _build_core_guidance_loop(core: DroneCoreDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Guidance loop",
		"Position error becomes a damped velocity request",
		[
			InspectionDocumentBuilder.stat(
				"Position gain",
				"%.2f" % core.ai_horizontal_position_gain
			),
			InspectionDocumentBuilder.stat(
				"Velocity gain",
				"%.2f" % core.ai_horizontal_velocity_gain
			),
			InspectionDocumentBuilder.stat("Altitude P", "%.2f" % core.ai_altitude_position_gain),
			InspectionDocumentBuilder.stat("Altitude V", "%.2f" % core.ai_altitude_velocity_gain),
		]
	)


func _build_core_attitude_loop(core: DroneCoreDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Attitude loop",
		"Upright stability and physical rotor mixing",
		[
			InspectionDocumentBuilder.stat("Tilt limit", "%.1f°" % core.ai_max_tilt_degrees),
			InspectionDocumentBuilder.stat("Attitude response", "%.2f" % core.ai_attitude_response),
			InspectionDocumentBuilder.stat(
				"Angular damping",
				"%.2f" % core.ai_angular_velocity_damping
			),
			InspectionDocumentBuilder.stat(
				"Motor mix",
				"%.0f%%" % (
					core.ai_motor_mix_authority * PERCENT_SCALE
				)
			),
			InspectionDocumentBuilder.stat(
				"Recovery torque",
				"%.2f Nm" % core.ai_emergency_upright_torque
			),
		]
	)


func _build_battery_groups(
	battery: DroneBatteryDefinition,
	runtime_state: Dictionary
) -> Array:
	var stored_energy: float = float(runtime_state.get(
		"battery_energy_wh",
		battery.energy_capacity_wh
	))
	if stored_energy < 0.0:
		stored_energy = battery.energy_capacity_wh
	var charge_ratio: float = clampf(
		stored_energy / maxf(
			battery.energy_capacity_wh,
			MINIMUM_ENERGY_CAPACITY
		),
		0.0,
		1.0
	)

	return [
		_build_battery_charge_group(battery, stored_energy, charge_ratio),
		_build_battery_power_group(battery),
		_build_battery_package_group(battery),
	]


func _build_battery_charge_group(
	battery: DroneBatteryDefinition,
	stored_energy: float,
	charge_ratio: float
) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Charge",
		"Current runtime energy state",
		[
			InspectionDocumentBuilder.stat(
				"Charge level",
				"%.1f%%" % (charge_ratio * PERCENT_SCALE)
			),
			InspectionDocumentBuilder.stat("Stored", "%.3f Wh" % stored_energy),
			InspectionDocumentBuilder.stat("Capacity", "%.3f Wh" % battery.energy_capacity_wh),
		]
	)


func _build_battery_power_group(
	battery: DroneBatteryDefinition
) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Power systems",
		"Output envelope and power quality",
		[
			InspectionDocumentBuilder.stat("Nominal output", "%.1f W" % battery.nominal_power_output),
			InspectionDocumentBuilder.stat("Maximum output", "%.1f W" % battery.maximum_power_output),
		],
		[
			InspectionDocumentBuilder.node(
				"Output stability",
				"Normal delivery characteristics",
				[
					InspectionDocumentBuilder.stat(
						"Consistency",
						"%.1f%%" % (
							battery.power_output_consistency * PERCENT_SCALE
						)
					),
					InspectionDocumentBuilder.stat(
						"Fluctuation rate",
						"%.2f Hz" % battery.fluctuation_rate
					),
				]
			),
			_build_battery_fault_group(battery),
		]
	)


func _build_battery_fault_group(
	battery: DroneBatteryDefinition
) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Fault envelope",
		"Rare drops, boosts and surge coupling",
		[
			InspectionDocumentBuilder.stat(
				"Spike chance",
				"%.3f / s" % battery.spike_chance_per_second
			),
			InspectionDocumentBuilder.stat(
				"Spike duration",
				"%.2f–%.2f s" % [
					battery.minimum_spike_duration,
					battery.maximum_spike_duration,
				]
			),
			InspectionDocumentBuilder.stat(
				"Drop range",
				"%.0f–%.0f%%" % [
					battery.minimum_drop_multiplier * PERCENT_SCALE,
					battery.maximum_drop_multiplier * PERCENT_SCALE,
				]
			),
			InspectionDocumentBuilder.stat(
				"Boost range",
				"%.0f–%.0f%%" % [
					battery.minimum_boost_multiplier * PERCENT_SCALE,
					battery.maximum_boost_multiplier * PERCENT_SCALE,
				]
			),
			InspectionDocumentBuilder.stat(
				"Surge protection",
				"%.1f%%" % (battery.surge_protection * PERCENT_SCALE)
			),
			InspectionDocumentBuilder.stat(
				"Damage coupling",
				"%.2f%%" % (
					battery.extreme_spike_damage_coupling * PERCENT_SCALE
				)
			),
		]
	)


func _build_battery_package_group(
	battery: DroneBatteryDefinition
) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Physical package",
		"Envelope occupied inside the battery dock",
		[InspectionDocumentBuilder.stat("Body size", _format_size(battery.body_size))]
	)


func _build_propeller_groups(propeller: DronePropellerDefinition) -> Array:
	return [
		InspectionDocumentBuilder.node(
			"Power systems",
			"Electrical demand at maximum command",
			[
				InspectionDocumentBuilder.stat("Maximum draw", "%.1f W" % propeller.max_power_draw),
			]
		),
		InspectionDocumentBuilder.node(
			"Rotor geometry",
			"Physical dimensions and air-working area",
			[
				InspectionDocumentBuilder.stat(
					"Radius",
					"%.1f cm" % (propeller.rotor_radius * PERCENT_SCALE)
				),
				InspectionDocumentBuilder.stat("Disc area", "%.4f m²" % propeller.get_disk_area()),
			],
			[
				InspectionDocumentBuilder.node(
					"Aerodynamics",
					"Conversion of shaft power into airflow",
					[
						InspectionDocumentBuilder.stat(
							"Efficiency",
							"%.1f%%" % (
								propeller.aerodynamic_efficiency * PERCENT_SCALE
							)
						),
						InspectionDocumentBuilder.stat(
							"Axial response",
							"%.3f" % propeller.axial_flow_response
						),
						InspectionDocumentBuilder.stat(
							"Axial range",
							"%.2f–%.2f" % [
								propeller.minimum_axial_flow_factor,
								propeller.maximum_axial_flow_factor,
							]
						),
					]
				),
				InspectionDocumentBuilder.node(
					"Reaction dynamics",
					"Counter-torque fed into the airframe",
					[
						InspectionDocumentBuilder.stat(
							"Reaction torque",
							"%.4f Nm/N" % propeller.reaction_torque_per_newton
						),
					]
				),
			]
		),
	]


func _build_ai_chip_groups(chip: DroneAIChipDefinition) -> Array:
	return [
		_build_ai_behavior_group(chip),
		_build_ai_processing_group(chip),
		_build_ai_power_group(chip),
		_build_ai_sensing_group(chip),
		_build_ai_surge_group(chip),
		_build_ai_package_group(chip),
	]


func _build_ai_behavior_group(chip: DroneAIChipDefinition) -> Dictionary:
	var behavior_values: Array = [
		InspectionDocumentBuilder.stat("Behavior", str(chip.behavior_id)),
		InspectionDocumentBuilder.stat("Priority", "%d" % chip.processing_priority),
		InspectionDocumentBuilder.stat(
			"Implementation",
			(
				chip.behavior_script.resource_path
				if chip.behavior_script != null
				else "Not assigned"
			)
		),
	]
	if chip.has_finalized_model_identity():
		behavior_values.append(InspectionDocumentBuilder.stat(
			"Model artifact",
			chip.finalized_model_id
		))
		behavior_values.append(InspectionDocumentBuilder.stat(
			"Algorithm",
			chip.finalized_algorithm_id
		))
		behavior_values.append(InspectionDocumentBuilder.stat(
			"Body signature",
			chip.finalized_body_signature
		))
	if not chip.behavior_description.is_empty():
		behavior_values.append(InspectionDocumentBuilder.stat("Profile", chip.behavior_description))
	return InspectionDocumentBuilder.node(
		"Behavior package",
		"Commands and movement policy supplied by the chip",
		behavior_values,
		_build_ai_behavior_children(chip)
	)


func _build_ai_behavior_children(chip: DroneAIChipDefinition) -> Array:
	var children: Array = []
	if chip.behavior_id == FOLLOW_BEHAVIOR_ID:
		children.append(_build_ai_follow_group(chip))
	elif chip.is_collision_avoidance_chip():
		children.append(_build_ai_collision_group(chip))

	if chip.behavior_id in NAVIGATION_BEHAVIOR_IDS:
		children.append(_build_ai_movement_group(chip))
	var parameter_values: Array = _build_parameter_stats(chip)
	if not parameter_values.is_empty():
		children.append(InspectionDocumentBuilder.node(
			"Behavior parameters",
			"Raw resource values supplied to the behavior module",
			parameter_values
		))
	return children


func _build_ai_follow_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Follow envelope",
		"World-space donut targeted around the assigned player",
		[
			InspectionDocumentBuilder.stat("Target area", chip.get_follow_target_area_description()),
			InspectionDocumentBuilder.stat(
				"Preferred radius",
				"%.1f m" % chip.get_follow_preferred_radius()
			),
			InspectionDocumentBuilder.stat(
				"Height offset",
				"%.1f m" % chip.get_follow_height_offset()
			),
			InspectionDocumentBuilder.stat(
				"Movement style",
				str(chip.get_follow_mode()).capitalize()
			),
		]
	)


func _build_ai_collision_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Collision envelope",
		"Server-side reciprocal velocity planning",
		[
			InspectionDocumentBuilder.stat(
				"Neighbor distance",
				"%.1f m" % chip.get_avoidance_neighbor_distance()
			),
			InspectionDocumentBuilder.stat("Time horizon", "%.2f s" % chip.get_avoidance_time_horizon()),
			InspectionDocumentBuilder.stat(
				"Safety padding",
				"%.2f m" % chip.get_avoidance_radius_padding()
			),
			InspectionDocumentBuilder.stat(
				"Vertical window",
				"±%.2f m" % chip.get_avoidance_vertical_tolerance()
			),
			InspectionDocumentBuilder.stat(
				"Maximum peers",
				"%d drones" % chip.get_avoidance_max_neighbors()
			),
			InspectionDocumentBuilder.stat(
				"Reciprocity",
				"50% with ORCA peer / 100% with passive drone"
			),
		]
	)


func _build_ai_movement_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Movement envelope",
		"Stable shared flight limits requested by this chip",
		[
			InspectionDocumentBuilder.stat(
				"Speed authority",
				"%.0f%%" % (
					chip.get_navigation_speed_scale() * PERCENT_SCALE
				)
			),
			InspectionDocumentBuilder.stat(
				"Acceleration authority",
				"%.0f%%" % (
					chip.get_navigation_acceleration_scale() * PERCENT_SCALE
				)
			),
			InspectionDocumentBuilder.stat(
				"Jerk authority",
				"%.0f%%" % (
					chip.get_navigation_jerk_scale() * PERCENT_SCALE
				)
			),
		]
	)


func _build_ai_processing_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Processing",
		"Decision latency and brownout tolerance",
		[
			InspectionDocumentBuilder.stat("Response time", "%.3f s" % chip.response_time),
			InspectionDocumentBuilder.stat(
				"Efficiency",
				"%.1f%%" % (chip.processing_efficiency * PERCENT_SCALE)
			),
			InspectionDocumentBuilder.stat(
				"Minimum power",
				"%.1f%%" % (
					chip.minimum_operating_power_ratio * PERCENT_SCALE
				)
			),
		]
	)


func _build_ai_power_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Power systems",
		"Core-bus demand while idle and executing",
		[
			InspectionDocumentBuilder.stat("Idle draw", "%.2f W" % chip.idle_power_draw),
			InspectionDocumentBuilder.stat("Active draw", "%.2f W" % chip.active_power_draw),
		]
	)


func _build_ai_sensing_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Sensing & targeting",
		"Perception and combat-processing quality",
		[
			InspectionDocumentBuilder.stat("Sensor range", "%.1f m" % chip.sensor_range),
			InspectionDocumentBuilder.stat("Aim error", "%.2f°" % chip.aim_error_degrees),
			InspectionDocumentBuilder.stat(
				"Friendly ID",
				"%.3f%%" % (
					chip.friendly_identification_accuracy * PERCENT_SCALE
				)
			),
		]
	)


func _build_ai_surge_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Surge tolerance",
		"Destructive battery-spike resistance",
		[
			InspectionDocumentBuilder.stat("Threshold", "%.2fx" % chip.damaging_spike_threshold),
			InspectionDocumentBuilder.stat(
				"Protection",
				(
					"Immune"
					if chip.surge_immune
					else "Fragility %.2f" % chip.surge_fragility
				)
			),
		]
	)


func _build_ai_package_group(chip: DroneAIChipDefinition) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Physical package",
		"Envelope occupied on the core's AI bus",
		[InspectionDocumentBuilder.stat("Body size", _format_size(chip.body_size))]
	)


func _build_weapon_groups(weapon: DroneWeaponDefinition) -> Array:
	return [
		InspectionDocumentBuilder.node(
			"Weapon performance",
			"Damage output and firing cadence",
			[
				InspectionDocumentBuilder.stat("Damage / shot", "%.1f" % weapon.damage_per_shot),
				InspectionDocumentBuilder.stat("Fire rate", "%.2f rounds/s" % weapon.rounds_per_second),
				InspectionDocumentBuilder.stat(
					"Sustained damage",
					"%.1f / s" % (
						weapon.damage_per_shot * weapon.rounds_per_second
					)
				),
			],
			[
				InspectionDocumentBuilder.node(
					"Ballistics",
					"Range and projectile travel",
					[
						InspectionDocumentBuilder.stat("Effective range", "%.1f m" % weapon.effective_range),
						InspectionDocumentBuilder.stat(
							"Projectile speed",
							"%.1f m/s" % weapon.projectile_speed
						),
					]
				),
				InspectionDocumentBuilder.node(
					"Mount mechanics",
					"Physical aiming limits",
					[
						InspectionDocumentBuilder.stat(
							"Traverse arc",
							"%.1f°" % weapon.traverse_arc_degrees
						),
					]
				),
			]
		),
		_build_attachment_power_node(weapon),
		_build_attachment_package_node(weapon),
	]


func _build_arm_groups(arm: DroneArmDefinition) -> Array:
	return [
		InspectionDocumentBuilder.node(
			"Manipulation",
			"Physical work envelope of the arm",
			[
				InspectionDocumentBuilder.stat("Force", "%.1f N" % arm.manipulation_force),
				InspectionDocumentBuilder.stat("Reach", "%.2f m" % arm.reach),
				InspectionDocumentBuilder.stat("Rotation torque", "%.1f Nm" % arm.rotation_torque),
			]
		),
		_build_attachment_power_node(arm),
		_build_attachment_package_node(arm),
	]


func _build_attachment_groups(
	attachment: DroneAttachmentDefinition
) -> Array:
	return [
		_build_attachment_power_node(attachment),
		_build_attachment_package_node(attachment),
	]


func _build_attachment_power_node(
	attachment: DroneAttachmentDefinition
) -> Dictionary:
	var tag_names: Array[String] = []
	for tag: StringName in attachment.capability_tags:
		tag_names.append(str(tag))
	return InspectionDocumentBuilder.node(
		"Power & capabilities",
		"Bus demand and services advertised to AI chips",
		[
			InspectionDocumentBuilder.stat(
				"Capabilities",
				", ".join(tag_names) if not tag_names.is_empty() else "None"
			),
			InspectionDocumentBuilder.stat("Idle draw", "%.2f W" % attachment.idle_power_draw),
			InspectionDocumentBuilder.stat("Active draw", "%.2f W" % attachment.active_power_draw),
		]
	)


func _build_attachment_package_node(
	attachment: DroneAttachmentDefinition
) -> Dictionary:
	return InspectionDocumentBuilder.node(
		"Physical package",
		"Envelope occupied on a belly attachment rail",
		[
			InspectionDocumentBuilder.stat("Body size", _format_size(attachment.body_size)),
		]
	)


func _build_parameter_stats(chip: DroneAIChipDefinition) -> Array:
	var parameter_names: Array[String] = []
	for parameter_key: Variant in chip.behavior_parameters.keys():
		parameter_names.append(str(parameter_key))
	parameter_names.sort()

	var result: Array = []
	for parameter_name: String in parameter_names:
		result.append(InspectionDocumentBuilder.stat(
			parameter_name.replace("_", " ").capitalize(),
			str(chip.get_parameter(StringName(parameter_name), ""))
		))
	return result




func _format_size(value: Vector3) -> String:
	return "%.2f × %.2f × %.2f m" % [value.x, value.y, value.z]


func _quality_name(quality: int) -> String:
	match quality:
		DronePartDefinition.Quality.SCRAP:
			return "Scrap"
		DronePartDefinition.Quality.INDUSTRIAL:
			return "Industrial"
	return "Standard"


func _condition_name(runtime_state: Dictionary) -> String:
	return "Broken" if bool(runtime_state.get("broken", false)) else "Operational"
