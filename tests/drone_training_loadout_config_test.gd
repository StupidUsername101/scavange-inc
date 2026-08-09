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

	var private_copy = DroneTrainingLoadoutConfig.duplicate_loadout(baseline)
	_expect(private_copy != baseline, "loadout container is copied")
	_expect(private_copy.core != baseline.core, "core resource is copied")
	_expect(private_copy.battery != baseline.battery, "battery resource is copied")
	for slot_index in range(DroneTrainingLoadoutConfig.CURRENT_TRAINING_PROPELLER_COUNT):
		_expect(
			private_copy.get_propeller(slot_index) != baseline.get_propeller(slot_index),
			"propeller resource %d is copied" % slot_index
		)

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

	var summary = DroneTrainingLoadoutConfig.physical_summary(private_copy)
	_expect(not summary.is_empty(), "physical summary is produced")
	_expect(float(summary.get("mass_kg", 0.0)) > 0.0, "summary has positive mass")
	_expect(float(summary.get("hover_power_w", 0.0)) > 0.0, "summary has positive hover power")
	_expect(
		float(summary.get("nominal_lift_to_weight", 0.0)) > 0.0,
		"summary has a finite positive lift-to-weight ratio"
	)

	var record = DroneTrainingLoadoutConfig.to_record(private_copy)
	_expect(not record.is_empty(), "checkpoint hardware record is produced")
	_expect(int(record.get("schema_version", -1)) == 3, "hardware record uses generic Resource snapshots")
	var json_text = JSON.stringify(record)
	_expect(not json_text.is_empty(), "checkpoint hardware record is JSON serializable")
	var parsed = JSON.parse_string(json_text)
	_expect(parsed is Dictionary, "checkpoint hardware record survives JSON parsing")
	var restored = DroneTrainingLoadoutConfig.from_record(parsed as Dictionary)
	_expect(restored != null, "checkpoint hardware record reconstructs a loadout")
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
		restored.ai_chips.size() == private_copy.ai_chips.size(),
		"checkpoint round-trip preserves installed AI-chip slots and their mass"
	)
	for slot_index in range(private_copy.ai_chips.size()):
		var expected_chip = private_copy.get_ai_chip(slot_index)
		var restored_chip = restored.get_ai_chip(slot_index)
		_expect(
			(expected_chip == null and restored_chip == null)
			or (
				expected_chip != null
				and restored_chip != null
				and expected_chip.display_name == restored_chip.display_name
			),
			"AI-chip slot %d survives checkpoint round-trip" % slot_index
		)
	_expect(
		is_equal_approx(restored.get_total_mass(), private_copy.get_total_mass()),
		"checkpoint round-trip preserves exact installed-part mass"
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
