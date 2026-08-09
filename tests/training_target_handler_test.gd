extends SceneTree

#######################################################
# Verifies the target-routing layer without requiring a physics world. The important
# contract is that many deterministic task candidates collapse into one unchanged policy
# objective, while each worker group may own an independent copy of the same target type.
#######################################################

var failure_count: int = 0
var assertion_count: int = 0


func _init() -> void:
	_test_group_handlers_keep_independent_path_configuration()
	_test_registered_targets_use_semantic_priority()
	_test_priority_bias_cannot_override_survival_class()
	_test_kind_priority_is_easy_to_override_per_handler()
	_test_equal_task_targets_prefer_urgency_then_distance()
	_test_equal_candidates_use_stable_id_tie_break()
	_test_registered_targets_can_be_updated_and_removed()
	_test_non_finite_target_inputs_are_contained()

	if failure_count == 0:
		print("Training target handler tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("Training target handler tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _make_handler(key: String) -> TrainingTargetHandler:
	var handler: TrainingTargetHandler = TrainingTargetHandler.new()
	handler.handler_key = key
	handler.add_system(TrainingPathTargetSystem.new())
	handler.add_system(TrainingRegisteredTargetSystem.new())
	handler.reset(12345, {"reference_position_world": Vector3.ZERO})
	return handler


func _test_group_handlers_keep_independent_path_configuration() -> void:
	var source: TrainingTargetHandler = _make_handler("group:a")
	var source_path: TrainingPathTargetSystem = source.path_system()
	source_path.set_behavior(1)
	source_path.path_radius_m = 9.0
	source_path.speed_mps = 2.5
	source.registered_system().upsert_target(
		"source-only-cargo",
		"cargo_delivery",
		Vector3(5.0, 0.0, 0.0)
	)
	source.reset(100, {"reference_position_world": Vector3.ZERO})

	var child: TrainingTargetHandler = source.clone_configured("group:b")
	var child_path: TrainingPathTargetSystem = child.path_system()
	child_path.set_behavior(3)
	child_path.random_waypoint_interval_seconds = 0.75
	child.reset(200, {"reference_position_world": Vector3.ZERO})

	_expect(source_path.behavior == 1, "changing one group's path behaviour does not alter its source group")
	_expect(child_path.behavior == 3, "a cloned group can use the same target type with another behaviour")
	_expect(is_equal_approx(source_path.path_radius_m, 9.0), "source path configuration survives independent child edits")
	_expect(source.path_system() != child.path_system(), "groups own separate target-system instances")
	_expect(child.registered_system().target_count() == 0, "branches do not clone transient world target registrations")


func _test_registered_targets_use_semantic_priority() -> void:
	var handler: TrainingTargetHandler = _make_handler("priority")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	registered.upsert_target(
		"cargo-far",
		"cargo_delivery",
		Vector3(20.0, 0.0, 0.0)
	)
	var result: Dictionary = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("stable_id", "")) == "cargo-far", "cargo delivery outranks ordinary navigation")

	registered.upsert_target(
		"escape",
		"survival_escape",
		Vector3(50.0, 0.0, 0.0)
	)
	result = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("stable_id", "")) == "escape", "survival escape outranks cargo delivery")


func _test_priority_bias_cannot_override_survival_class() -> void:
	var handler: TrainingTargetHandler = _make_handler("strict-priority")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	registered.upsert_target(
		"cargo-biased",
		"cargo_delivery",
		Vector3.ONE,
		Vector3.ZERO,
		0.75,
		1000000.0
	)
	registered.upsert_target(
		"escape",
		"survival_escape",
		Vector3(100.0, 0.0, 0.0),
		Vector3.ZERO,
		0.75,
		-1000000.0
	)
	var result: Dictionary = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("stable_id", "")) == "escape", "within-class bias cannot leapfrog the hardcoded survival hierarchy")


func _test_kind_priority_is_easy_to_override_per_handler() -> void:
	var handler: TrainingTargetHandler = _make_handler("custom-priority")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	registered.upsert_target("cargo", "cargo_delivery", Vector3.ONE)
	handler.set_kind_priority("navigation", 900.0)
	var result: Dictionary = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("target_kind", "")) == "navigation", "per-handler semantic priorities can be changed with one setter")
	var clone: TrainingTargetHandler = handler.clone_configured("custom-priority-clone")
	_expect(is_equal_approx(clone.kind_priority("navigation"), 900.0), "per-handler priority changes survive configured cloning")


func _test_equal_task_targets_prefer_urgency_then_distance() -> void:
	var handler: TrainingTargetHandler = _make_handler("ranking")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	registered.upsert_target(
		"near",
		"cargo_delivery",
		Vector3(2.0, 0.0, 0.0),
		Vector3.ZERO,
		0.75,
		0.0,
		0.0,
		1.0
	)
	registered.upsert_target(
		"far",
		"cargo_delivery",
		Vector3(12.0, 0.0, 0.0),
		Vector3.ZERO,
		0.75,
		0.0,
		0.0,
		1.0
	)
	var result: Dictionary = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("stable_id", "")) == "near", "equal cargo targets choose the nearer destination")

	registered.upsert_target(
		"urgent-far",
		"cargo_delivery",
		Vector3(30.0, 0.0, 0.0),
		Vector3.ZERO,
		0.75,
		0.0,
		4.0,
		1.0
	)
	result = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("stable_id", "")) == "urgent-far", "urgency ranks before distance inside one target class")


func _test_equal_candidates_use_stable_id_tie_break() -> void:
	var handler: TrainingTargetHandler = _make_handler("deterministic")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	registered.upsert_target("z-destination", "cargo_delivery", Vector3(4.0, 0.0, 0.0))
	registered.upsert_target("a-destination", "cargo_delivery", Vector3(-4.0, 0.0, 0.0))
	var result: Dictionary = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("stable_id", "")) == "a-destination", "stable IDs make exact ties deterministic")


func _test_registered_targets_can_be_updated_and_removed() -> void:
	var handler: TrainingTargetHandler = _make_handler("runtime")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	registered.upsert_target("dropoff", "cargo_delivery", Vector3(8.0, 0.0, 0.0))
	registered.upsert_target("dropoff", "cargo_delivery", Vector3(3.0, 0.0, 0.0))
	var result: Dictionary = handler.resolve({"reference_position_world": Vector3.ZERO})
	var result_position: Vector3 = result.get("position_world", Vector3.ZERO)
	_expect(result_position.is_equal_approx(Vector3(3.0, 0.0, 0.0)), "runtime providers can continuously update one stable target")
	registered.remove_target("dropoff")
	result = handler.resolve({"reference_position_world": Vector3.ZERO})
	_expect(str(result.get("target_kind", "")) == "navigation", "removing a task target falls back to the navigation system")


func _test_non_finite_target_inputs_are_contained() -> void:
	var handler: TrainingTargetHandler = _make_handler("finite-boundary")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	registered.upsert_target("valid-cargo", "cargo_delivery", Vector3(2.0, 0.0, 0.0))
	registered.upsert_target("invalid-escape", "survival_escape", Vector3(NAN, 0.0, 0.0))
	var result: Dictionary = handler.resolve({"reference_position_world": Vector3(NAN, 0.0, 0.0)})
	_expect(
		str(result.get("stable_id", "")) == "valid-cargo"
		and (result.get("position_world", Vector3.ZERO) as Vector3).is_finite(),
		"non-finite registered targets cannot poison semantic target selection"
	)
	var previous_navigation_priority: float = handler.kind_priority("navigation")
	handler.load_configuration({"priority_by_kind": {"navigation": NAN}})
	_expect(
		is_finite(handler.kind_priority("navigation"))
		and is_equal_approx(handler.kind_priority("navigation"), previous_navigation_priority),
		"non-finite restored target priorities keep their last finite value"
	)
	var path: TrainingPathTargetSystem = handler.path_system()
	var previous_height: float = path.base_height_m
	path.load_configuration({
		"type_id": str(TrainingPathTargetSystem.TYPE_ID),
		"base_height_m": NAN,
		"speed_mps": NAN,
		"path_rotation_degrees": [NAN, 20.0, NAN],
		"manual_subject_position": [NAN, NAN, NAN],
	})
	_expect(
		is_finite(path.base_height_m)
		and is_equal_approx(path.base_height_m, previous_height)
		and is_finite(path.speed_mps)
		and path.path_rotation_degrees.is_finite()
		and path.manual_subject_position.is_finite(),
		"path configuration cannot inject non-finite coordinates or timing into policy objectives"
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)
