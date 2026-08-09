extends SceneTree

#######################################################
# Verifies the topology-independent ML action contract without requiring a trained model or
# a running physics world.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	_test_variable_propeller_counts()
	_test_slot_identity_validation()
	_test_invalid_values_fail_closed()
	_test_limb_action_contract()
	_test_feature_encoder_preserves_topology()
	_test_feature_encoder_includes_target_motion_and_radius()
	_test_model_is_intentionally_empty()

	if failure_count == 0:
		print("Drone ML pipeline tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("Drone ML pipeline tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _test_variable_propeller_counts() -> void:
	for propeller_count: int in [1, 3, 4, 6, 12]:
		var slots := _make_slots(propeller_count)
		var commands: Array = []
		for slot_index: int in range(propeller_count):
			commands.append({
				"slot_index": slot_index,
				"command": float(slot_index + 1) / float(propeller_count),
			})
		var validation := DroneMLAction.validate(
			{"propeller_commands": commands},
			slots
		)
		_expect(bool(validation.get("valid", false)),
			"%d-propeller action validates" % propeller_count)
		_expect((validation.get("commands", []) as Array).size() == propeller_count,
			"%d-propeller action preserves its topology" % propeller_count)


func _test_slot_identity_validation() -> void:
	var slots := _make_slots(3)
	var validation := DroneMLAction.validate({
		"propeller_commands": [
			{"slot_index": 0, "command": 0.5},
			{"slot_index": 2, "command": 0.5},
			{"slot_index": 1, "command": 0.5},
		],
	}, slots)
	_expect(not bool(validation.get("valid", true)),
		"reordered slot identities are rejected")


func _test_invalid_values_fail_closed() -> void:
	var slots := _make_slots(2)
	var wrong_count := DroneMLAction.validate(
		{"propeller_commands": [0.5]},
		slots
	)
	_expect(not bool(wrong_count.get("valid", true)),
		"wrong command count is rejected")

	var non_finite := DroneMLAction.validate(
		{"propeller_commands": [0.5, NAN]},
		slots
	)
	_expect(not bool(non_finite.get("valid", true)),
		"non-finite commands are rejected")

	var clamped := DroneMLAction.validate(
		{"propeller_commands": PackedFloat32Array([-4.0, 7.0])},
		slots
	)
	var commands: Array = clamped.get("commands", [])
	_expect(commands == [0.0, 1.0],
		"packed finite commands are clamped to the actuator range")

	var non_numeric := DroneMLAction.validate(
		{"propeller_commands": [0.5, Vector3.ZERO]},
		slots
	)
	_expect(not bool(non_numeric.get("valid", true)),
		"non-numeric commands are rejected without conversion")

	var malformed_slot = DroneMLAction.validate(
		{
			"propeller_commands": [
				{"slot_index": "0", "command": 0.5},
				{"slot_index": 1, "command": 0.5},
			],
		},
		slots
	)
	_expect(not bool(malformed_slot.get("valid", true)),
		"malformed slot identities fail closed instead of being coerced or throwing")


func _test_limb_action_contract() -> void:
	var legacy = DroneMLAction.validate_limb_commands({}, 1)
	var legacy_commands: Variant = legacy.get("commands", PackedFloat64Array())
	_expect(
		bool(legacy.get("valid", false))
		and legacy_commands is PackedFloat64Array
		and legacy_commands.size() == 1
		and is_zero_approx(legacy_commands[0]),
		"legacy actions receive the requested number of neutral limb commands"
	)
	var valid = DroneMLAction.validate_limb_commands(
		{"limb_commands": PackedFloat64Array([-0.75])},
		1
	)
	var valid_commands: Variant = valid.get("commands", PackedFloat64Array())
	_expect(
		bool(valid.get("valid", false))
		and valid_commands is PackedFloat64Array
		and valid_commands.size() == 1
		and is_equal_approx(valid_commands[0], -0.75),
		"a bounded legacy limb command validates without losing sign"
	)
	_expect(
		not bool(DroneMLAction.validate_limb_commands(
			{"limb_commands": [0.0, 1.0]},
			1
		).get("valid", true)),
		"legacy limb command-count mismatches fail closed"
	)


func _test_model_is_intentionally_empty() -> void:
	var model := DroneMLModel.new()
	_expect(model.predict_action({"example": true}).is_empty(),
		"placeholder model produces no algorithmic action")


func _test_feature_encoder_preserves_topology() -> void:
	var propellers: Array[Dictionary] = []
	for slot_index: int in range(6):
		propellers.append({
			"installed": slot_index != 4,
			"slot_index": slot_index,
			"position_local": Vector3(float(slot_index), 0.0, 0.0),
		})
	var encoded := DroneMLFeatureEncoder.encode({
		"body": {
			"position_world": Vector3.ZERO,
			"basis_world": Basis.IDENTITY,
		},
		"objective": {},
		"propellers": propellers,
	})
	var global_features: PackedFloat32Array = encoded["global_features"]
	var propeller_features: Array = encoded["propeller_features"]
	_expect(global_features.size() == DroneMLFeatureEncoder.GLOBAL_FEATURE_NAMES.size(),
		"global feature names match the numeric tensor")
	_expect(propeller_features.size() == 6,
		"feature encoder preserves all six propeller slots")
	_expect((propeller_features[0] as PackedFloat32Array).size()
		== DroneMLFeatureEncoder.PROPELLER_FEATURE_NAMES.size(),
		"propeller feature names match every numeric row")


func _test_feature_encoder_includes_target_motion_and_radius() -> void:
	_expect(
		DroneMLObservation.SCHEMA_VERSION == 3,
		"the generic drone observation schema records the expanded target contract"
	)
	var encoded := DroneMLFeatureEncoder.encode({
		"body": {
			"position_world": Vector3(1.0, 2.0, 3.0),
			"basis_world": Basis.IDENTITY,
		},
		"objective": {
			"target_position_world": Vector3(4.0, 6.0, 3.0),
			"target_velocity_world": Vector3(2.0, 0.0, -1.0),
			"target_hover_radius_m": 1.25,
		},
		"propellers": [],
	})
	var names: Array[String] = encoded["global_feature_names"]
	var features: PackedFloat32Array = encoded["global_features"]
	_expect(is_equal_approx(features[names.find("target_velocity_local_x")], 2.0),
		"target velocity is encoded for moving-target tracking")
	_expect(is_equal_approx(features[names.find("target_hover_radius_m")], 1.25),
		"accepted hover radius is visible to the model")
	_expect(is_equal_approx(features[names.find("target_distance_m")], 5.0),
		"target distance is encoded in physical units")
	_expect(
		is_equal_approx(features[names.find("target_direction_local_x")], 0.6)
		and is_equal_approx(features[names.find("target_direction_local_y")], 0.8)
		and is_zero_approx(features[names.find("target_direction_local_z")]),
		"the generic drone tensor exposes an explicit unit target direction"
	)
	_expect(
		is_equal_approx(features[names.find("target_boundary_error_m")], 3.75)
		and is_zero_approx(features[names.find("target_inside_radius")]),
		"the generic drone tensor exposes success-boundary error and inside-radius state"
	)


func _make_slots(count: int) -> Array:
	var result: Array = []
	for slot_index: int in range(count):
		var slot := DronePropellerSlot.new()
		slot.slot_index = slot_index
		result.append(slot)
	return result


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)
