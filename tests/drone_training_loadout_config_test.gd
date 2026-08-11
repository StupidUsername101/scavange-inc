extends SceneTree

#######################################################
# Verifies that training-room hardware templates are private per group, retain the exact
# gameplay-part physics through checkpoint serialization, while generic persistence preserves creator topology.
#######################################################

var failure_count = 0


func _init() -> void:
	var baseline = MLBodyPresetLibrary.drone_quad_loadout(false)
	_expect(baseline != null, "Quad Drone preset can be created")
	_expect(baseline.core != null, "Quad Drone preset has a core")
	_expect(baseline.battery != null, "Quad Drone preset has a battery")
	_expect(
		baseline.propellers.size() == DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT,
		"Quad Drone preset exposes exactly four propeller records"
	)
	for slot_index in range(DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT):
		_expect(
			baseline.get_propeller(slot_index) != null,
			"Quad Drone preset has propeller slot %d" % slot_index
		)

	_expect(
		baseline.ai_chips.is_empty(),
		"model-forge drone presets do not carry the removed legacy AI chips"
	)

	# Core-mounted hardware must never survive without the Core that owns its slots. A previous
	# edit-session path could remove a Core while leaving propellers invisibly installed.
	var coreless_loadout: DroneLoadout = DroneLoadout.new()
	var detached_propeller: DronePropellerDefinition = (
		MLBodyPartContract.deep_duplicate_resource(baseline.get_propeller(0)) as DronePropellerDefinition
	)
	_expect(
		not coreless_loadout.install_propeller(0, detached_propeller),
		"a propeller cannot be installed before a Core provides its mount slot"
	)
	coreless_loadout.install_core(
		MLBodyPartContract.deep_duplicate_resource(baseline.core) as DroneCoreDefinition
	)
	coreless_loadout.install_battery(
		MLBodyPartContract.deep_duplicate_resource(baseline.battery) as DroneBatteryDefinition
	)
	_expect(
		coreless_loadout.install_propeller(0, detached_propeller)
		and coreless_loadout.has_core_mounted_parts(),
		"Core-owned hardware is detected before Core removal"
	)
	var battery_only_mass: float = coreless_loadout.battery.get_mass()
	coreless_loadout.remove_core()
	_expect(
		coreless_loadout.core == null
		and coreless_loadout.propellers.is_empty()
		and coreless_loadout.ai_chips.is_empty()
		and coreless_loadout.attachments.is_empty()
		and coreless_loadout.get_propeller_presence().is_empty()
		and not coreless_loadout.has_core_mounted_parts(),
		"removing a Core removes every part mounted to Core-owned slots"
	)
	_expect(
		is_equal_approx(coreless_loadout.get_total_mass(), maxf(battery_only_mass, 0.001)),
		"orphaned Core hardware cannot continue contributing invisible runtime mass"
	)

	var replacement_guard_loadout: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(baseline)
	var undersized_replacement_core: DroneCoreDefinition = (
		MLBodyPartContract.deep_duplicate_resource(baseline.core) as DroneCoreDefinition
	)
	if undersized_replacement_core != null:
		undersized_replacement_core.propeller_slot_count = 3
	_expect(
		undersized_replacement_core != null
		and not replacement_guard_loadout.can_replace_core_without_dropping_parts(
			undersized_replacement_core
		),
		"Core replacement refuses to silently discard an occupied propeller slot"
	)
	var compatible_replacement_core: DroneCoreDefinition = (
		MLBodyPartContract.deep_duplicate_resource(baseline.core) as DroneCoreDefinition
	)
	_expect(
		compatible_replacement_core != null
		and replacement_guard_loadout.can_replace_core_without_dropping_parts(
			compatible_replacement_core
		),
		"Core replacement accepts a chassis that still exposes every occupied slot"
	)
	var malformed_replacement_core: DroneCoreDefinition = (
		MLBodyPartContract.deep_duplicate_resource(baseline.core) as DroneCoreDefinition
	)
	if malformed_replacement_core != null:
		malformed_replacement_core.propeller_slot_count = -1
	_expect(
		malformed_replacement_core != null
		and not replacement_guard_loadout.can_replace_core_without_dropping_parts(
			malformed_replacement_core
		),
		"malformed negative Core slot counts fail closed instead of indexing from the array tail"
	)

	var private_copy = DroneTrainingLoadoutConfig.duplicate_loadout(baseline)
	_expect(private_copy != baseline, "loadout container is copied")
	_expect(private_copy.core != baseline.core, "core resource is copied")
	_expect(private_copy.battery != baseline.battery, "battery resource is copied")
	for slot_index in range(DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT):
		_expect(
			private_copy.get_propeller(slot_index) != baseline.get_propeller(slot_index),
			"propeller resource %d is copied" % slot_index
		)
	_expect(
		DroneLoadout.definition_path(private_copy.core) == DroneLoadout.definition_path(baseline.core)
		and DroneLoadout.definition_path(private_copy.battery) == DroneLoadout.definition_path(baseline.battery)
		and private_copy.get_propeller_definition_paths() == baseline.get_propeller_definition_paths(),
		"deep-copied drone hardware keeps stable .tres definition paths for UI/network replication"
	)
	var loose_part_scene: PackedScene = load("res://scenes/server/server_drone_part.tscn") as PackedScene
	var loose_part: RigidBody3D = null
	if loose_part_scene != null:
		loose_part = loose_part_scene.instantiate() as RigidBody3D
	var loose_part_state: Dictionary = {}
	if loose_part != null:
		loose_part.call("configure", private_copy.core)
		loose_part_state = loose_part.call("to_state_dict") as Dictionary
	_expect(
		loose_part != null
		and str(loose_part_state.get("definition_path", "")) == DroneLoadout.definition_path(baseline.core),
		"loose copied drone parts replicate the original .tres definition path"
	)
	if loose_part != null:
		loose_part.free()

	var original_power = baseline.get_propeller(0).max_power_draw
	_expect(
		DroneTrainingLoadoutConfig.set_part_stat(
			private_copy,
			&"propeller",
			&"max_power_draw",
			original_power + 17.0
		),
		"one stat edit applies to the private quad loadout"
	)
	for slot_index in range(DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT):
		_expect(
			is_equal_approx(
				private_copy.get_propeller(slot_index).max_power_draw,
				original_power + 17.0
			),
			"all four propellers receive a symmetric stat edit"
		)
	_expect(
		is_equal_approx(baseline.get_propeller(0).max_power_draw, original_power),
		"editing one worker-group template cannot mutate its isolated preset source"
	)

	var linked_power = 42.0
	_expect(
		DroneTrainingLoadoutConfig.set_linked_flight_power_per_rotor(
			private_copy,
			linked_power
		),
		"linked power control can update a complete quad loadout"
	)
	for slot_index in range(DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT):
		_expect(
			is_equal_approx(
				private_copy.get_propeller(slot_index).max_power_draw,
				linked_power
			),
			"linked power updates propeller slot %d" % slot_index
		)
	var linked_total = linked_power * DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT
	_expect(
		is_equal_approx(private_copy.battery.nominal_power_output, linked_total),
		"linked power updates nominal battery output"
	)
	_expect(
		is_equal_approx(private_copy.battery.maximum_power_output, linked_total),
		"linked power updates maximum battery output"
	)
	_expect(
		is_equal_approx(private_copy.core.max_power_throughput, linked_total),
		"linked power updates core throughput"
	)
	_expect(
		is_equal_approx(
			DroneTrainingLoadoutConfig.linked_flight_power_per_rotor(private_copy),
			linked_power
		),
		"linked power readback reflects the real shared bottleneck"
	)

	var attachment_power_copy: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(baseline)
	var powered_attachment: DroneAttachmentDefinition = DroneAttachmentDefinition.new()
	powered_attachment.idle_power_draw = 19.0
	_expect(
		attachment_power_copy.install_attachment(0, powered_attachment),
		"linked-power overhead test can install a generic powered attachment"
	)
	_expect(
		DroneTrainingLoadoutConfig.set_linked_flight_power_per_rotor(
			attachment_power_copy,
			linked_power
		),
		"linked power can reserve bus headroom for attachment idle draw"
	)
	var linked_total_with_attachment: float = (
		linked_power * DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT
		+ powered_attachment.idle_power_draw
	)
	_expect(
		is_equal_approx(
			attachment_power_copy.battery.nominal_power_output,
			linked_total_with_attachment
		)
		and is_equal_approx(
			attachment_power_copy.core.max_power_throughput,
			linked_total_with_attachment
		)
		and is_equal_approx(
			DroneTrainingLoadoutConfig.linked_flight_power_per_rotor(attachment_power_copy),
			linked_power
		),
		"linked flight power accounts for runtime attachment idle draw before rotor allocation"
	)

	var summary = DroneTrainingLoadoutConfig.physical_summary(private_copy)
	_expect(not summary.is_empty(), "physical summary is produced")
	_expect(float(summary.get("mass_kg", 0.0)) > 0.0, "summary has positive mass")
	_expect(float(summary.get("hover_power_w", 0.0)) > 0.0, "summary has positive hover power")
	_expect(
		float(summary.get("nominal_lift_to_weight", 0.0)) > 0.0,
		"summary has a finite positive lift-to-weight ratio"
	)

	var rotor_for_math: DronePropellerDefinition = private_copy.get_propeller(0)
	var rotor_test_power: float = rotor_for_math.max_power_draw * 0.63
	var shared_thrust: float = DroneRotorPhysics.thrust_for_power(
		rotor_test_power,
		rotor_for_math.get_disk_area(),
		rotor_for_math.aerodynamic_efficiency,
		DroneTrainingLoadoutConfig.DEFAULT_AIR_DENSITY_KG_M3
	)
	var runtime_air: AirEnvironment = AirEnvironment.new()
	runtime_air.air_density = DroneTrainingLoadoutConfig.DEFAULT_AIR_DENSITY_KG_M3
	_expect(
		is_equal_approx(
			runtime_air.calculate_rotor_thrust(
				rotor_test_power,
				rotor_for_math.get_disk_area(),
				rotor_for_math.aerodynamic_efficiency
			),
			shared_thrust
		)
		and is_equal_approx(
			DroneTrainingLoadoutConfig._rotor_thrust(
				rotor_test_power,
				rotor_for_math,
				DroneTrainingLoadoutConfig.DEFAULT_AIR_DENSITY_KG_M3
			),
			shared_thrust
		),
		"training diagnostics and runtime flight use one shared rotor thrust equation"
	)
	var recovered_power: float = runtime_air.calculate_rotor_power(
		shared_thrust,
		rotor_for_math.get_disk_area(),
		rotor_for_math.aerodynamic_efficiency
	)
	_expect(
		is_equal_approx(recovered_power, rotor_test_power),
		"shared rotor power/thrust equations remain inverse for normal flight hardware"
	)
	var edge_rotor: DronePropellerDefinition = DronePropellerDefinition.new()
	edge_rotor.rotor_radius = 0.01
	edge_rotor.aerodynamic_efficiency = 0.01
	var edge_air: AirEnvironment = AirEnvironment.new()
	edge_air.air_density = 0.01
	var edge_power: float = 7.5
	var edge_thrust: float = DroneTrainingLoadoutConfig._rotor_thrust(
		edge_power,
		edge_rotor,
		edge_air.air_density
	)
	_expect(
		is_equal_approx(
			DroneTrainingLoadoutConfig._rotor_power(edge_thrust, edge_rotor, edge_air.air_density),
			edge_power
		)
		and is_equal_approx(
			edge_air.calculate_rotor_power(
				edge_thrust,
				edge_rotor.get_disk_area(),
				edge_rotor.aerodynamic_efficiency
			),
			edge_power
		),
		"runtime and diagnostics stay inverse-consistent at the creator's minimum valid rotor radius and efficiency"
	)
	edge_air.free()
	runtime_air.free()

	var stock_quad_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(private_copy)
	_expect(
		DroneMLBodyInterfaceFactory.is_legacy_stock_quad_manifest(stock_quad_manifest),
		"legacy SAC-compatible detection accepts the real stock four-corner rotor geometry"
	)

	var custom_propeller_mount: Transform3D = Transform3D(
		Basis(Vector3.UP, 0.35),
		Vector3(0.37, 0.16, 0.29)
	)
	_expect(
		private_copy.set_propeller_slot_transform(0, custom_propeller_mount),
		"creator-authored propeller mount can be stored on a training loadout"
	)
	_expect(
		not DroneMLBodyInterfaceFactory.is_legacy_stock_quad_manifest(
			DroneMLBodyInterfaceFactory.finalize_loadout(private_copy)
		),
		"four arbitrary rotor controls are not mislabeled as the stock SAC mixer geometry"
	)
	var custom_mount_basis: Basis = Basis(
		Vector3(0.0, 0.0, -1.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0)
	)
	var custom_mount: Transform3D = Transform3D(custom_mount_basis, Vector3(0.425, 0.01, -0.08))
	_expect(
		private_copy.set_attachment_slot_transform(0, custom_mount),
		"creator-authored attachment mount can be stored on a training loadout"
	)
	var copied_with_mounts: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(private_copy)
	_expect(
		copied_with_mounts != null
		and DroneMLBodyInterfaceFactory._transforms_match(
			copied_with_mounts.get_attachment_slot_transform(0),
			custom_mount
		),
		"deep loadout copies preserve creator-authored attachment position and orientation"
	)
	_expect(
		copied_with_mounts != null
		and DroneMLBodyInterfaceFactory._transforms_match(
			copied_with_mounts.get_propeller_slot_transform(0),
			custom_propeller_mount
		),
		"deep loadout copies preserve creator-authored propeller position and orientation"
	)

	var replacement_core: DroneCoreDefinition = (
		MLBodyPartContract.deep_duplicate_resource(copied_with_mounts.core) as DroneCoreDefinition
	)
	if replacement_core != null:
		replacement_core.body_size.x += 0.35
		copied_with_mounts.install_core(replacement_core)
	_expect(
		replacement_core != null
		and not DroneMLBodyInterfaceFactory._transforms_match(
			copied_with_mounts.get_attachment_slot_transform(0),
			custom_mount
		),
		"replacing the physical Core invalidates attachment coordinates authored for the previous chassis"
	)

	var record = DroneTrainingLoadoutConfig.to_record(private_copy)
	_expect(not record.is_empty(), "checkpoint hardware record is produced")
	_expect(int(record.get("schema_version", -1)) == 6, "hardware record persists generic Resource snapshots plus propeller/attachment mount transforms")
	_expect(not record.has("ai_chips"), "training hardware persistence no longer serializes legacy AI chips")
	var json_text = JSON.stringify(record)
	_expect(not json_text.is_empty(), "checkpoint hardware record is JSON serializable")
	var parsed = JSON.parse_string(json_text)
	_expect(parsed is Dictionary, "checkpoint hardware record survives JSON parsing")
	var restored = DroneTrainingLoadoutConfig.from_record(parsed as Dictionary)
	_expect(restored != null, "checkpoint hardware record reconstructs a loadout")
	var evaluation_contract: Dictionary = RLEvaluationContract.create(
		"drone",
		{"hardware": record}
	)
	var frozen_environment: Dictionary = evaluation_contract.get("environment", {})
	var frozen_hardware: Dictionary = frozen_environment.get("hardware", {})
	var frozen_live_copy: DroneLoadout = DroneTrainingLoadoutConfig.frozen_loadout(
		frozen_hardware,
		private_copy
	)
	_expect(
		frozen_live_copy != null
		and frozen_live_copy != private_copy
		and DroneTrainingLoadoutConfig.records_match(
			frozen_hardware,
			DroneTrainingLoadoutConfig.to_record(frozen_live_copy)
		),
		"fixed-seed evaluation clones an unchanged live drone body when it exactly matches the frozen candidate hardware"
	)
	_expect(
		DroneTrainingLoadoutConfig.from_record({}) == null
		and DroneTrainingLoadoutConfig.from_record({"core": {}, "battery": {}, "propellers": []}) == null,
		"missing serialized drone bodies stay invalid instead of silently becoming a stock preset"
	)
	_expect(
		restored.propellers.size() == DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT,
		"restored checkpoint retains the four-rotor topology"
	)
	_expect(
		is_equal_approx(restored.core.mass, private_copy.core.mass),
		"core physical stats survive checkpoint round-trip"
	)
	_expect(
		is_equal_approx(
			restored.core.ai_max_vertical_acceleration,
			private_copy.core.ai_max_vertical_acceleration
		),
		"the complete core definition survives checkpoint round-trip"
	)
	_expect(
		is_equal_approx(
			restored.battery.nominal_power_output,
			private_copy.battery.nominal_power_output
		),
		"battery power stats survive checkpoint round-trip"
	)
	_expect(
		is_equal_approx(
			restored.get_propeller(0).max_power_draw,
			private_copy.get_propeller(0).max_power_draw
		),
		"propeller power survives checkpoint round-trip"
	)
	_expect(
		restored.ai_chips.is_empty(),
		"checkpoint round-trip keeps model-forge drone loadouts free of legacy AI chips"
	)
	_expect(
		is_equal_approx(restored.get_total_mass(), private_copy.get_total_mass()),
		"checkpoint round-trip preserves exact installed-part mass"
	)
	_expect(
		DroneMLBodyInterfaceFactory._transforms_match(
			restored.get_propeller_slot_transform(0),
			custom_propeller_mount
		),
		"checkpoint round-trip preserves creator-authored propeller mount transforms"
	)
	_expect(
		DroneMLBodyInterfaceFactory._transforms_match(
			restored.get_attachment_slot_transform(0),
			custom_mount
		),
		"checkpoint round-trip preserves creator-authored attachment mount transforms"
	)
	var legacy_v4_record: Dictionary = record.duplicate(true)
	legacy_v4_record["schema_version"] = 4
	legacy_v4_record.erase("propeller_mounts")
	legacy_v4_record.erase("attachment_mounts")
	var legacy_v4_restored: DroneLoadout = DroneTrainingLoadoutConfig.from_record(legacy_v4_record)
	_expect(
		legacy_v4_restored != null
		and legacy_v4_restored.get_attachment_slot_transforms().size()
			== legacy_v4_restored.core.attachment_slot_count,
		"pre-layout version-4 hardware records still restore using authored Core default mounts"
	)
	var malformed_mount_record: Dictionary = record.duplicate(true)
	var malformed_mounts: Array = (malformed_mount_record.get("attachment_mounts", []) as Array).duplicate(true)
	if not malformed_mounts.is_empty():
		malformed_mounts[0] = {"origin": [0.0, 0.0], "basis": []}
	malformed_mount_record["attachment_mounts"] = malformed_mounts
	_expect(
		DroneTrainingLoadoutConfig.from_record(malformed_mount_record) == null,
		"malformed creator mount records fail closed instead of silently snapping to an unrelated default"
	)
	var malformed_propeller_mount_record: Dictionary = record.duplicate(true)
	var malformed_propeller_mounts: Array = (malformed_propeller_mount_record.get("propeller_mounts", []) as Array).duplicate(true)
	if not malformed_propeller_mounts.is_empty():
		malformed_propeller_mounts[0] = {"origin": [0.0], "basis": []}
	malformed_propeller_mount_record["propeller_mounts"] = malformed_propeller_mounts
	_expect(
		DroneTrainingLoadoutConfig.from_record(malformed_propeller_mount_record) == null,
		"malformed creator propeller mounts fail closed instead of silently reverting to a stock rotor location"
	)

	var grabber_loadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	_expect(
		DroneTrainingLoadoutConfig.install_training_belly_grabber(grabber_loadout),
		"articulated training belly limb installs into a free attachment slot"
	)
	_expect(
		DroneTrainingLoadoutConfig.has_training_belly_grabber(grabber_loadout),
		"installed loadout reports its belly grabber capability"
	)
	_expect(
		DroneTrainingLoadoutConfig.limb_action_count(grabber_loadout) == 4,
		"loadout topology reports shoulder X/Z, elbow Z, and grip as independent controls"
	)
	var grabber_slots = grabber_loadout.find_attachment_slots_with_capability(
		DroneTrainingLoadoutConfig.TRAINING_BELLY_GRABBER_CAPABILITY
	)
	_expect(grabber_slots.size() == 1, "belly grabber occupies exactly one attachment slot")
	if grabber_slots.size() == 1:
		var grabber = grabber_loadout.get_attachment(grabber_slots[0]) as DroneLimbAttachmentDefinition
		_expect(grabber != null, "belly grabber is a generic limb-host attachment")
		_expect(
			grabber != null and grabber.required_limb_action_count() == 4,
			"belly limb exposes three joint controls plus one grip control"
		)
		if grabber != null and not grabber.limb_definitions.is_empty():
			var limb: GenericLimbDefinition = grabber.limb_definitions[0]
			_expect(
				limb.segments.size() == 2
				and limb.maximum_reach() < 0.85
				and limb.mount_offset_local.length() + limb.maximum_reach() < 1.0,
				"belly limb is a compact two-segment articulated arm"
			)
			_expect(
				limb.end_effector != null
				and limb.end_effector.allow_static_grip
				and limb.end_effector.allow_dynamic_grip
				and "climbable" in limb.end_effector.compatible_surface_tags
				and "carryable" in limb.end_effector.compatible_surface_tags,
				"belly limb uses the normal grip effector for walls and carryable items"
			)
	# Creator edits must survive persistence even when the edited properties live in Resources nested
	# inside typed Resource arrays. This is the shape used by arbitrary articulated attachments.
	var edited_grabber_slot: int = int(grabber_slots[0]) if grabber_slots.size() == 1 else -1
	if edited_grabber_slot >= 0:
		var edited_grabber: DroneLimbAttachmentDefinition = (
			grabber_loadout.get_attachment(edited_grabber_slot) as DroneLimbAttachmentDefinition
		)
		if edited_grabber != null and not edited_grabber.limb_definitions.is_empty():
			var edited_limb: GenericLimbDefinition = edited_grabber.limb_definitions[0]
			if edited_limb != null and edited_limb.segments.size() >= 2:
				edited_limb.segments[0].length = 0.413
				edited_limb.segments[1].mass = 0.287
			if edited_limb != null and edited_limb.end_effector != null:
				edited_limb.end_effector.maximum_held_mass = 17.25

	var grabber_summary = DroneTrainingLoadoutConfig.physical_summary(grabber_loadout)
	_expect(
		float(grabber_summary.get("mass_kg", 0.0)) > grabber_loadout.get_total_mass(),
		"flight summary includes the grabber segment and end-effector rigid-body mass"
	)
	var grabber_record = DroneTrainingLoadoutConfig.to_record(grabber_loadout)
	var grabber_json: String = JSON.stringify(grabber_record)
	var parsed_grabber: Variant = JSON.parse_string(grabber_json)
	var grabber_restored: DroneLoadout = (
		DroneTrainingLoadoutConfig.from_record(parsed_grabber as Dictionary)
		if parsed_grabber is Dictionary
		else null
	)
	_expect(
		DroneTrainingLoadoutConfig.has_training_belly_grabber(grabber_restored),
		"belly grabber hardware survives JSON checkpoint loadout restoration"
	)
	_expect(
		DroneTrainingLoadoutConfig.limb_action_count(grabber_restored) == 4,
		"restored grabber loadout preserves its action topology"
	)
	if grabber_restored != null and edited_grabber_slot >= 0:
		var restored_grabber: DroneLimbAttachmentDefinition = (
			grabber_restored.get_attachment(edited_grabber_slot) as DroneLimbAttachmentDefinition
		)
		_expect(restored_grabber != null, "restored creator attachment keeps its concrete part type")
		if restored_grabber != null and not restored_grabber.limb_definitions.is_empty():
			var restored_limb: GenericLimbDefinition = restored_grabber.limb_definitions[0]
			_expect(
				restored_limb != null
				and restored_limb.segments.size() >= 2
				and is_equal_approx(restored_limb.segments[0].length, 0.413)
				and is_equal_approx(restored_limb.segments[1].mass, 0.287),
				"nested creator-edited limb segment properties survive JSON persistence"
			)
			_expect(
				restored_limb != null
				and restored_limb.end_effector != null
				and is_equal_approx(restored_limb.end_effector.maximum_held_mass, 17.25),
				"nested creator-edited end-effector properties survive JSON persistence"
			)

	# Generic loadout copying/serialization must preserve the Core's declared physical slot count even
	# though the current drone flight room intentionally remains a four-rotor specialized trainer.
	var extended: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(baseline)
	extended.core.propeller_slot_count = 6
	var extra_propeller: DronePropellerDefinition = (
		MLBodyPartContract.deep_duplicate_resource(baseline.get_propeller(0)) as DronePropellerDefinition
	)
	_expect(extended.install_propeller(4, extra_propeller), "generic loadout accepts a creator-added fifth propeller slot")
	var extended_copy: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(extended)
	_expect(
		extended_copy.core.propeller_slot_count == 6
		and extended_copy.propellers.size() == 6
		and extended_copy.get_propeller(4) != null
		and extended_copy.get_propeller(5) == null,
		"generic loadout cloning preserves creator Core slot topology including empty slots"
	)
	var extended_record: Dictionary = DroneTrainingLoadoutConfig.to_record(extended)
	var extended_parsed: Variant = JSON.parse_string(JSON.stringify(extended_record))
	var extended_restored: DroneLoadout = (
		DroneTrainingLoadoutConfig.from_record(extended_parsed as Dictionary)
		if extended_parsed is Dictionary
		else null
	)
	_expect(
		extended_restored != null
		and extended_restored.core.propeller_slot_count == 6
		and extended_restored.propellers.size() == 6
		and extended_restored.get_propeller(4) != null
		and extended_restored.get_propeller(5) == null,
		"generic hardware snapshots preserve creator Core slot topology without forcing quad defaults"
	)

	# Creator flight regression: a flat/wide Core with heavy-lift propellers must preserve real
	# upward rotor axes, start PPO near a body-specific hover command, and must not inherit the
	# invisible legacy X-arm collisions from the stock quad scene.
	var flat_lift_loadout: DroneLoadout = DroneLoadout.new()
	var flat_core_source: DroneCoreDefinition = load(
		"res://resources/drones/cores/large_standard_core.tres"
	) as DroneCoreDefinition
	var lift_battery_source: DroneBatteryDefinition = load(
		"res://resources/drones/batteries/industrial_battery.tres"
	) as DroneBatteryDefinition
	var heavy_propeller_source: DronePropellerDefinition = load(
		"res://resources/drones/propellers/heavy_lift_propeller.tres"
	) as DronePropellerDefinition
	var flat_core: DroneCoreDefinition = (
		MLBodyPartContract.deep_duplicate_resource(flat_core_source) as DroneCoreDefinition
	)
	var lift_battery: DroneBatteryDefinition = (
		MLBodyPartContract.deep_duplicate_resource(lift_battery_source) as DroneBatteryDefinition
	)
	if flat_core != null:
		flat_core.set_editable_body_size(Vector3(2.4, 0.14, 1.8))
	flat_lift_loadout.install_core(flat_core)
	flat_lift_loadout.install_battery(lift_battery)
	var flat_mounts: Array[Vector3] = [
		Vector3(-0.95, 0.17, -0.68),
		Vector3(0.95, 0.17, -0.68),
		Vector3(-0.95, 0.17, 0.68),
		Vector3(0.95, 0.17, 0.68),
	]
	for slot_index: int in range(4):
		flat_lift_loadout.install_propeller(
			slot_index,
			MLBodyPartContract.deep_duplicate_resource(heavy_propeller_source) as DronePropellerDefinition
		)
		flat_lift_loadout.set_propeller_slot_transform(
			slot_index,
			Transform3D(Basis.IDENTITY, flat_mounts[slot_index])
		)
	var flat_summary: Dictionary = DroneTrainingLoadoutConfig.physical_summary(flat_lift_loadout)
	var flat_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(
		flat_lift_loadout
	)
	var flat_initial_controls: Array = DroneTrainingLoadoutConfig.recommended_initial_control_values(
		flat_lift_loadout,
		flat_manifest
	)
	_expect(
		flat_manifest != null
		and float(flat_summary.get("nominal_lift_to_weight", 0.0)) > 1.0
		and flat_initial_controls.size() == flat_manifest.control_count()
		and float(flat_summary.get("initial_propeller_command", 0.0)) > 0.70,
		"flat/wide heavy-lift creator body keeps upward lift authority and receives a mass-aware PPO startup command"
	)

	var drone_scene: PackedScene = load("res://scenes/server/server_drone.tscn") as PackedScene
	var air_environment: AirEnvironment = AirEnvironment.new()
	get_root().add_child(air_environment)
	var flat_lift_drone: ServerDrone = null
	if drone_scene != null:
		flat_lift_drone = drone_scene.instantiate() as ServerDrone
	if flat_lift_drone != null:
		flat_lift_drone.loadout = DroneTrainingLoadoutConfig.duplicate_loadout(flat_lift_loadout)
		get_root().add_child(flat_lift_drone)
		_expect(
			(flat_lift_drone.get_node("ArmCollisionA") as CollisionShape3D).disabled
			and (flat_lift_drone.get_node("ArmCollisionB") as CollisionShape3D).disabled,
			"creator-authored Core disables the invisible legacy quad X-arm collision boxes"
		)
		var reset_started: bool = flat_lift_drone.reset_ml_episode(Transform3D.IDENTITY, 44191, null)
		_expect(
			reset_started and is_equal_approx(flat_lift_drone.power_spool_ratio, 1.0),
			"ML episode reset starts with the already-powered training bus fully spooled"
		)
		_expect(
			not flat_lift_drone.submit_ml_action({}),
			"ServerDrone propagates ML action validation failure instead of reporting rejected commands as accepted"
		)
		_expect(
			not flat_lift_drone.ml_controller.latest_action_error.is_empty(),
			"rejected ML action exposes the controller validation reason to training diagnostics"
		)
		var initial_command: float = float(flat_summary.get("initial_propeller_command", 1.0))
		flat_lift_drone.ai_motor_thrust_targets.resize(flat_lift_drone.propeller_slots.size())
		for array_index: int in range(flat_lift_drone.propeller_slots.size()):
			var propeller: DronePropellerDefinition = flat_lift_drone.loadout.get_propeller(array_index)
			flat_lift_drone.ai_motor_thrust_targets[array_index] = air_environment.calculate_rotor_thrust(
				propeller.max_power_draw,
				propeller.get_disk_area(),
				propeller.aerodynamic_efficiency
			) * initial_command
		var available_power: float = float(flat_summary.get("nominal_rotor_power_w", 0.0))
		flat_lift_drone._apply_propeller_forces(available_power)
		var realized_upward_force: float = 0.0
		for array_index: int in range(flat_lift_drone.propeller_slots.size()):
			realized_upward_force += flat_lift_drone.last_propeller_realized_thrust_n[array_index] * maxf(
				flat_lift_drone.propeller_slots[array_index].global_basis.y.normalized().dot(Vector3.UP),
				0.0
			)
		_expect(
			realized_upward_force > flat_lift_loadout.get_total_mass() * 9.8,
			"heavy-lift creator rotor commands reach the real force path with enough realized upward thrust to exceed body weight"
		)
		flat_lift_drone.free()
	air_environment.free()
	var degraded_drone: ServerDrone = null
	if drone_scene != null:
		degraded_drone = drone_scene.instantiate() as ServerDrone
	if degraded_drone != null:
		degraded_drone.loadout = DroneTrainingLoadoutConfig.duplicate_loadout(baseline)
		get_root().add_child(degraded_drone)
		var topology_signature: String = degraded_drone.model_body_contract_signature()
		_expect(
			degraded_drone.set_ml_propeller_degraded(2, true)
			and degraded_drone.loadout.get_propeller(2) != null
			and degraded_drone.model_body_contract_signature() == topology_signature,
			"degraded-propeller evaluation disables thrust without deleting the accepted rotor slot/body contract"
		)
		_expect(
			not degraded_drone.set_ml_propeller_degraded(99, true),
			"degraded-propeller setup rejects unknown authored slot ids instead of treating them as array indices"
		)
		var degraded_states: Array[Dictionary] = DroneMLObservation.capture_ppo_propeller_states(degraded_drone)
		_expect(
			degraded_states.size() == 4
			and not bool(degraded_states[2].get("installed", true))
			and is_zero_approx(float(degraded_states[2].get("realized_thrust_n", 1.0)))
			and is_zero_approx(float(degraded_states[2].get("maximum_static_thrust_n", 1.0))),
			"degraded rotor remains a stable policy slot while observations report it as failed"
		)
		degraded_drone.free()

	# Exercise the creator/factory -> real ServerDrone -> controller path with a serialized articulated
	# attachment. The accepted body must not merely count the arm channels; the instantiated worker
	# must expose their observations and consume every routed command in the same local order.
	var arm_drone: ServerDrone = null
	if drone_scene != null:
		arm_drone = drone_scene.instantiate() as ServerDrone
	var utility_arm: DroneLimbAttachmentDefinition = load(
		"res://resources/drones/attachments/utility_arm.tres"
	) as DroneLimbAttachmentDefinition
	var arm_loadout: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(baseline)
	var arm_slot: int = -1
	if arm_loadout != null and arm_loadout.core != null:
		for slot_index: int in range(arm_loadout.core.attachment_slot_count):
			if arm_loadout.get_attachment(slot_index) == null:
				arm_slot = slot_index
				break
	var side_arm_mount: Transform3D = Transform3D(
		Basis(
			Vector3(0.0, 0.0, -1.0),
			Vector3(-1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0)
		),
		Vector3(0.425, 0.0, 0.0)
	)
	var arm_installed: bool = (
		arm_slot >= 0
		and utility_arm != null
		and arm_loadout.set_attachment_slot_transform(arm_slot, side_arm_mount)
		and arm_loadout.install_attachment(
			arm_slot,
			MLBodyPartContract.deep_duplicate_resource(utility_arm) as DroneLimbAttachmentDefinition
		)
	)
	_expect(arm_installed, "serialized Utility Manipulator Arm installs into a normal creator attachment slot")
	if arm_drone != null and arm_installed:
		arm_drone.loadout = arm_loadout
		get_root().add_child(arm_drone)
		var arm_manifest: MLBodyInterfaceManifest = arm_drone.model_body_interface()
		var arm_runtime_error: String = DroneMLBodyInterfaceFactory.training_runtime_validation_error(arm_drone, arm_manifest)
		_expect(
			arm_manifest != null
			and arm_manifest.control_count() == 8
			and arm_runtime_error.is_empty(),
			"factory-created articulated drone resolves all 8 policy controls to real worker actuators"
		)
		var shifted_mount: Transform3D = side_arm_mount
		shifted_mount.origin.z += 0.11
		arm_drone.loadout.set_attachment_slot_transform(arm_slot, shifted_mount)
		var mismatched_mount_error: String = DroneMLBodyInterfaceFactory.training_runtime_validation_error(
			arm_drone,
			arm_manifest
		)
		_expect(
			mismatched_mount_error.contains("mount transform differs"),
			"worker preflight rejects a live attachment mount that differs from the accepted creator layout"
		)
		arm_drone.loadout.set_attachment_slot_transform(arm_slot, side_arm_mount)
		var arm_features: PackedFloat64Array = arm_drone.model_body_observation_features()
		_expect(
			arm_manifest != null
			and arm_features.size() == arm_manifest.observation_count()
			and arm_features.size() > 8,
			"real articulated worker emits the complete finalized body-observation block"
		)
		if arm_manifest != null and arm_drone.ml_controller != null:
			var commands: PackedFloat64Array = PackedFloat64Array()
			commands.resize(arm_manifest.control_count())
			for control_index: int in range(commands.size()):
				commands[control_index] = 0.5 if control_index < 4 else 0.0
			var control_names: Array[String] = arm_manifest.control_names()
			var local_arm_values: Array[float] = [0.25, -0.5, 0.75, 1.0]
			var local_cursor: int = 0
			for control_index: int in range(control_names.size()):
				if control_names[control_index].begins_with("attachment_%d." % arm_slot):
					if local_cursor < local_arm_values.size():
						commands[control_index] = local_arm_values[local_cursor]
						local_cursor += 1
			arm_drone.ml_controller.enable()
			arm_drone.ml_controller.submit_external_action({
				"body_interface_signature": arm_manifest.contract_signature,
				"body_commands": commands,
			})
			var assembly: GenericLimbAssembly3D = arm_drone.get_limb_attachment_assembly(arm_slot)
			var mounted_limb: GenericLimbDefinition = (
				assembly.limb_definitions[0]
				if is_instance_valid(assembly) and not assembly.limb_definitions.is_empty()
				else null
			)
			var authored_limb: GenericLimbDefinition = (
				utility_arm.limb_definitions[0]
				if utility_arm != null and not utility_arm.limb_definitions.is_empty()
				else null
			)
			_expect(
				mounted_limb != null
				and authored_limb != null
				and mounted_limb.mount_offset_local.is_equal_approx(
					side_arm_mount.origin + side_arm_mount.basis * authored_limb.mount_offset_local
				)
				and mounted_limb.mount_basis_local.x.is_equal_approx(side_arm_mount.basis.x)
				and mounted_limb.mount_basis_local.y.is_equal_approx(side_arm_mount.basis.y)
				and mounted_limb.mount_basis_local.z.is_equal_approx(side_arm_mount.basis.z),
				"freely placed articulated attachment reaches the live worker with its Core-local position and surface orientation"
			)
			var routed_correctly: bool = (
				local_cursor == 4
				and is_instance_valid(assembly)
				and is_instance_valid(assembly.controller)
				and assembly.controller.desired_commands.size() == 4
			)
			if routed_correctly:
				for local_index: int in range(local_arm_values.size()):
					routed_correctly = routed_correctly and is_equal_approx(
						assembly.controller.desired_commands[local_index],
						local_arm_values[local_index]
					)
			_expect(
				routed_correctly and arm_drone.ml_controller.latest_action_error.is_empty(),
				"body action router delivers shoulder X/Z, elbow Z and grip to the live arm controller in manifest order"
			)
		arm_drone.free()

	var core_presets = DroneTrainingLoadoutConfig.core_presets()
	_expect(not core_presets.is_empty(), "compatible core presets are discovered")
	for preset in core_presets:
		var core = load(str(preset.get("path", ""))) as DroneCoreDefinition
		_expect(
			core != null and core.propeller_slot_count == 4,
			"training-room core presets remain exact quadrotor cores"
		)

	quit(0 if failure_count == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)
