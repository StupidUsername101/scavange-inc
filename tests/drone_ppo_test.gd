extends SceneTree

const SYNTHETIC_TRANSITIONS = 16

#######################################################
# Verifies PPO tensor shape, bounded quad actions, checkpoint fidelity, GAE bootstrapping,
# and a finite optimizer update without requiring a running physics world.
#######################################################

var failure_count = 0
var assertion_count = 0


func _init() -> void:
	var observation = _observation(0.25)
	_test_network_capacity()
	_test_observation_tensor(observation)
	_test_feature_audit()
	_test_policy_and_checkpoint(observation)
	_test_belly_grabber_policy(observation)
	_test_trainable_schema_continuation(observation)
	_test_behavior_policy_identity_and_overlap(observation)
	_test_weight_variation(observation)
	_test_algorithm_catalog()
	_test_robust_elite_candidate(observation)
	_test_terminated_and_truncated_bootstrap(observation)
	_test_bootstrap_value_override(observation)
	_test_optimizer_update(observation)
	_test_incremental_optimizer(observation)
	_test_chunked_optimizer_equivalence(observation)
	_test_background_optimizer(observation)
	if failure_count == 0:
		print("Drone PPO tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("Drone PPO tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _test_network_capacity() -> void:
	_expect(
		DronePPOActorCritic.HIDDEN_SIZE >= 64
		and DronePPOActorCritic.HIDDEN_SIZE
		>= DronePPOObservationEncoder.ACTOR_FEATURE_COUNT,
		"drone PPO no longer compresses the current observation into the old 32-unit bottleneck"
	)
	var shallow = DronePPOMLP.new(5, 16, 2, 1001, 1.0, 0.0, 1)
	var wide = DronePPOMLP.new(5, 32, 2, 1001, 1.0, 0.0, 1)
	var deep = DronePPOMLP.new(5, 16, 2, 1001, 1.0, 0.0, 3)
	var shallow_forward: Dictionary = shallow.forward(PackedFloat64Array([0.1, -0.2, 0.3, -0.4, 0.5]))
	var deep_forward: Dictionary = deep.forward(PackedFloat64Array([0.1, -0.2, 0.3, -0.4, 0.5]))
	_expect(
		shallow.parameter_count == 130
		and wide.parameter_count == 258
		and deep.parameter_count == 674
		and (shallow_forward.get("hidden_layers", []) as Array).size() == 1
		and (deep_forward.get("hidden_layers", []) as Array).size() == 3,
		"hidden width/depth change the actual MLP topology and parameter count rather than only checkpoint metadata"
	)


func _test_observation_tensor(observation: Dictionary) -> void:
	var actor_input = DronePPOObservationEncoder.encode_actor(observation)
	var critic_input = DronePPOObservationEncoder.encode_critic(observation)
	var reused_critic_input = DronePPOObservationEncoder.encode_critic_from_actor(
		actor_input,
		observation
	)
	_expect(
		actor_input.size() == DronePPOObservationEncoder.ACTOR_FEATURE_COUNT,
		"actor tensor matches its named schema"
	)
	_expect(
		critic_input.size() == DronePPOObservationEncoder.CRITIC_FEATURE_COUNT,
		"critic tensor matches its declared schema"
	)
	_expect(
		DronePPOObservationEncoder.CRITIC_FEATURE_NAMES.size()
		== DronePPOObservationEncoder.CRITIC_FEATURE_COUNT,
		"critic tensor has a complete explicit named schema"
	)
	var episode_progress_index = DronePPOObservationEncoder.CRITIC_FEATURE_NAMES.find(
		"episode_progress"
	)
	_expect(
		episode_progress_index == DronePPOObservationEncoder.TARGET_ACTOR_FEATURE_COUNT
		and is_equal_approx(critic_input[episode_progress_index], -0.5),
		"critic-only episode progress keeps its schema-6 column and is normalized"
	)
	_expect(
		DronePPOObservationEncoder.is_normalized_tensor(actor_input),
		"every actor feature is finite and normalized to [-1, 1]"
	)
	_expect(
		DronePPOObservationEncoder.is_normalized_tensor(critic_input),
		"every critic feature is finite and normalized to [-1, 1]"
	)
	_expect(
		_arrays_close(critic_input, reused_critic_input),
		"critic input is identical whether encoded directly or from actor features"
	)
	var target_critic = DronePPOObservationEncoder.encode_critic_for_schema(
		observation,
		DronePPOObservationEncoder.TARGET_SCHEMA_VERSION
	)
	_expect(
		_arrays_close(
			target_critic,
			critic_input.slice(0, DronePPOObservationEncoder.TARGET_CRITIC_FEATURE_COUNT)
		),
		"schema-6 critic inputs remain the exact prefix of the current schema"
	)
	var turret_present_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"turret_present"
	)
	_expect(
		turret_present_index >= 0
		and is_equal_approx(actor_input[turret_present_index], -1.0),
		"the current drone tensor explicitly reports that no turret threat is present"
	)
	var absent_turret_details_neutral = turret_present_index >= 0
	for index in range(
		turret_present_index + 1,
		DronePPOObservationEncoder.TURRET_ACTOR_FEATURE_COUNT
	):
		absent_turret_details_neutral = (
			absent_turret_details_neutral and is_zero_approx(actor_input[index])
		)
	_expect(
		absent_turret_details_neutral,
		"optional turret details are neutral instead of seven saturated nuisance constants when absent"
	)
	var current_feature_names: Array[String] = DronePPOObservationEncoder.feature_names_for_schema(
		DronePPOObservationEncoder.SCHEMA_VERSION
	)
	_expect(
		current_feature_names.size() == DronePPOObservationEncoder.TURRET_ACTOR_FEATURE_COUNT
		and not current_feature_names.has("manipulator_present"),
		"current PPO keeps the stable task prefix free of the removed one-grip shortcut"
	)
	_expect(
		not DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.has("linear_velocity_local_x")
		and not DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.has("basis_x_world_x"),
		"known motion and full-basis redundancies are absent"
	)
	_expect(
		DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.has("nearest_obstacle_clearance")
		and DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.has("target_path_blocked"),
		"compact normalized obstacle context is included in the actor tensor"
	)
	var obstacle_direction_index = (
		DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
			"nearest_obstacle_direction_local_x"
		)
	)
	var obstacle_clearance_index = (
		DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
			"nearest_obstacle_clearance"
		)
	)
	var target_blocked_index = (
		DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find("target_path_blocked")
	)
	_expect(
		obstacle_direction_index >= 0
		and is_equal_approx(actor_input[obstacle_direction_index], -1.0)
		and is_zero_approx(actor_input[obstacle_direction_index + 1])
		and is_zero_approx(actor_input[obstacle_direction_index + 2]),
		"the actor receives the sampled wall direction in drone-local coordinates"
	)
	var tilted_observation = observation.duplicate(true)
	var tilted_objective: Dictionary = tilted_observation["objective"]
	var tilted_probe: Dictionary = tilted_objective["obstacle_probe"]
	tilted_probe["nearest_direction_local"] = Vector3(-0.7, 0.7, 0.0).normalized()
	tilted_probe["nearest_direction_yaw_local"] = Vector3.LEFT
	var current_tilted_actor = DronePPOObservationEncoder.encode_actor(tilted_observation)
	var heading_v5_tilted_actor = DronePPOObservationEncoder.encode_actor_for_schema(
		tilted_observation,
		DronePPOObservationEncoder.HEADING_SCHEMA_VERSION
	)
	var maze_v4_tilted_actor = DronePPOObservationEncoder.encode_actor_for_schema(
		tilted_observation,
		DronePPOObservationEncoder.MAZE_SCHEMA_VERSION
	)
	var legacy_tilted_actor = DronePPOObservationEncoder.encode_actor_for_schema(
		tilted_observation,
		DronePPOObservationEncoder.LEGACY_SCHEMA_VERSION
	)
	_expect(
		is_zero_approx(current_tilted_actor[obstacle_direction_index + 1])
		and is_zero_approx(heading_v5_tilted_actor[obstacle_direction_index + 1])
		and maze_v4_tilted_actor[obstacle_direction_index + 1] > 0.5
		and legacy_tilted_actor[obstacle_direction_index + 1] > 0.5,
		"schema-v5/6 wall direction stays horizontal while schema-3/4 checkpoints retain their original tilted local input"
	)
	_expect(
		obstacle_clearance_index >= 0
		and is_equal_approx(actor_input[obstacle_clearance_index], -0.25),
		"the actor receives normalized wall clearance instead of losing it in diagnostics"
	)
	_expect(
		target_blocked_index >= 0
		and is_equal_approx(actor_input[target_blocked_index], 1.0),
		"the actor receives the target-line wall occlusion flag"
	)
	var front_clearance_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"wall_clearance_front"
	)
	var right_clearance_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"wall_clearance_right"
	)
	var path_clearance_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_path_clearance"
	)
	var wall_height_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_wall_top_relative_height"
	)
	_expect(
		front_clearance_index >= 0
		and is_equal_approx(actor_input[front_clearance_index], -0.5)
		and right_clearance_index >= 0
		and is_equal_approx(actor_input[right_clearance_index], 1.0),
		"the actor receives independent egocentric maze clearances instead of one nearest point"
	)
	_expect(
		path_clearance_index >= 0
		and absf(actor_input[path_clearance_index] + (1.0 / 3.0)) < 0.000001
		and wall_height_index >= 0
		and is_equal_approx(actor_input[wall_height_index], 0.25),
		"target-path distance and the blocking wall's climb height reach the actor"
	)
	var target_present_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_present"
	)
	var target_direction_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_direction_local_x"
	)
	var target_distance_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_distance"
	)
	var target_boundary_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_boundary_error"
	)
	var target_inside_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_inside_radius"
	)
	var expected_target_offset = Vector3(3.0, 1.0, -2.0)
	var expected_target_distance = expected_target_offset.length()
	var expected_target_direction = expected_target_offset.normalized()
	_expect(
		target_present_index >= 0
		and is_equal_approx(actor_input[target_present_index], 1.0)
		and target_direction_index >= 0
		and is_equal_approx(
			actor_input[target_direction_index],
			expected_target_direction.x
		)
		and is_equal_approx(
			actor_input[target_direction_index + 1],
			expected_target_direction.y
		)
		and is_equal_approx(
			actor_input[target_direction_index + 2],
			expected_target_direction.z
		),
		"the drone actor receives an explicit target-present flag and unit target direction"
	)
	_expect(
		target_distance_index >= 0
		and is_equal_approx(
			actor_input[target_distance_index],
			clampf(
				expected_target_distance
				/ DronePPOObservationEncoder.TARGET_OFFSET_SCALE_M,
				0.0,
				1.0
			) * 2.0 - 1.0
		)
		and target_boundary_index >= 0
		and is_equal_approx(
			actor_input[target_boundary_index],
			clampf(
				(expected_target_distance - 0.75)
				/ DronePPOObservationEncoder.TARGET_OFFSET_SCALE_M,
				-1.0,
				1.0
			)
		)
		and target_inside_index >= 0
		and is_equal_approx(actor_input[target_inside_index], -1.0),
		"target distance, success-boundary error, and inside-radius state are explicit inputs"
	)
	var inside_observation = observation.duplicate(true)
	var inside_body: Dictionary = inside_observation["body"]
	var inside_objective: Dictionary = inside_observation["objective"]
	var inside_position: Vector3 = inside_body.get("position_world", Vector3.ZERO)
	inside_objective["target_position_world"] = (
		inside_position + Vector3(0.1, 0.0, 0.0)
	)
	var inside_actor = DronePPOObservationEncoder.encode_actor(inside_observation)
	_expect(
		is_equal_approx(inside_actor[target_inside_index], 1.0)
		and inside_actor[target_boundary_index] < 0.0,
		"the explicit success state turns on inside the configured target radius"
	)
	var high_target_observation: Dictionary = observation.duplicate(true)
	var high_body: Dictionary = high_target_observation["body"]
	high_body["position_world"] = Vector3(0.0, 1.2, 0.0)
	var high_objective: Dictionary = high_target_observation["objective"]
	high_objective["target_position_world"] = Vector3(0.0, 15.0, 0.0)
	var high_actor = DronePPOObservationEncoder.encode_actor(high_target_observation)
	var target_height_index: int = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_offset_local_y"
	)
	var expected_height_signal: float = clampf(
		(15.0 - 1.2) / DronePPOObservationEncoder.TARGET_OFFSET_SCALE_M,
		-1.0,
		1.0
	)
	_expect(
		target_height_index >= 0
		and is_equal_approx(high_actor[target_height_index], expected_height_signal)
		and high_actor[target_height_index] > 0.8,
		"PPO receives a strong positive vertical error for a literal 15 m target above a 1.2 m spawn"
	)
	var absent_observation = observation.duplicate(true)
	var absent_objective: Dictionary = absent_observation["objective"]
	absent_objective.erase("target_position_world")
	absent_objective.erase("target_velocity_world")
	var absent_actor = DronePPOObservationEncoder.encode_actor(absent_observation)
	_expect(
		is_equal_approx(absent_actor[target_present_index], -1.0)
		and is_zero_approx(absent_actor[target_direction_index])
		and is_zero_approx(absent_actor[target_direction_index + 1])
		and is_zero_approx(absent_actor[target_direction_index + 2])
		and is_equal_approx(absent_actor[target_inside_index], -1.0),
		"an absent target is explicit and cannot create a fake direction or success state"
	)
	var alias_observation = absent_observation.duplicate(true)
	var alias_objective: Dictionary = alias_observation["objective"]
	var original_objective: Dictionary = observation["objective"]
	alias_objective["movement_target"] = original_objective["target_position_world"]
	alias_objective["movement_target_velocity"] = original_objective[
		"target_velocity_world"
	]
	var alias_actor = DronePPOObservationEncoder.encode_actor(alias_observation)
	_expect(
		is_equal_approx(alias_actor[target_present_index], 1.0)
		and is_equal_approx(
			alias_actor[target_direction_index],
			expected_target_direction.x
		)
		and is_equal_approx(
			alias_actor[target_direction_index + 2],
			expected_target_direction.z
		),
		"runtime movement-target aliases feed the same explicit drone objective contract"
	)
	var heading_v5_actor = DronePPOObservationEncoder.encode_actor_for_schema(
		observation,
		DronePPOObservationEncoder.HEADING_SCHEMA_VERSION
	)
	_expect(
		heading_v5_actor.size() == DronePPOObservationEncoder.MAZE_ACTOR_FEATURE_COUNT
		and _arrays_close(
			heading_v5_actor,
			actor_input.slice(0, DronePPOObservationEncoder.MAZE_ACTOR_FEATURE_COUNT)
		),
		"schema-v5 checkpoints retain their original 34-feature prefix"
	)
	var legacy_actor = DronePPOObservationEncoder.encode_actor_for_schema(
		observation,
		DronePPOObservationEncoder.LEGACY_SCHEMA_VERSION
	)
	var legacy_critic = DronePPOObservationEncoder.encode_critic_for_schema(
		observation,
		DronePPOObservationEncoder.LEGACY_SCHEMA_VERSION
	)
	_expect(
		legacy_actor.size() == DronePPOObservationEncoder.LEGACY_ACTOR_FEATURE_COUNT
		and legacy_critic.size() == DronePPOObservationEncoder.LEGACY_CRITIC_FEATURE_COUNT
		and _arrays_close(legacy_actor, actor_input.slice(0, legacy_actor.size())),
		"schema-3 runtime encoding remains byte-for-byte compatible with the original feature prefix"
	)
	var collective_index: int = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"rotor_collective_feedback"
	)
	_expect(
		collective_index >= 0
		and is_zero_approx(actor_input[collective_index + 1])
		and is_zero_approx(actor_input[collective_index + 2])
		and is_zero_approx(actor_input[collective_index + 3]),
		"equal rotor feedback has no roll, pitch or yaw correlation modes"
	)
	_expect(
		DronePPOObservationEncoder.is_valid_quad_observation(observation),
		"complete quad observation validates"
	)
	var degraded_observation = observation.duplicate(true)
	var degraded_propellers: Array = degraded_observation["propellers"]
	var missing_propeller: Dictionary = degraded_propellers[2]
	missing_propeller["installed"] = false
	missing_propeller["realized_thrust_n"] = 0.0
	missing_propeller["maximum_static_thrust_n"] = 0.0
	_expect(
		DronePPOObservationEncoder.is_valid_quad_observation(degraded_observation),
		"quad slot topology remains valid when one propeller is missing"
	)
	var wrong_topology = observation.duplicate(true)
	wrong_topology["propellers"] = (wrong_topology["propellers"] as Array).slice(0, 3)
	_expect(
		not DronePPOObservationEncoder.is_valid_quad_observation(wrong_topology)
		and DronePPOObservationEncoder.has_valid_propeller_topology(wrong_topology),
		"legacy quad validation stays exact while generic PPO accepts a stable three-propeller topology"
	)
	var leg_only_observation: Dictionary = observation.duplicate(true)
	leg_only_observation["propellers"] = []
	_expect(
		DronePPOObservationEncoder.has_valid_propeller_topology(leg_only_observation)
		and not DronePPOObservationEncoder.is_valid_quad_observation(leg_only_observation),
		"generic PPO accepts a stable zero-propeller topology for leg-only articulated bodies"
	)
	var custom_geometry: Array = (observation["propellers"] as Array).duplicate(true)
	var custom_positions: Array[Vector3] = [
		Vector3(0.45, 0.0, 0.0),
		Vector3(-0.45, 0.0, 0.0),
		Vector3(0.0, 0.0, -0.45),
		Vector3(0.0, 0.0, 0.45),
	]
	for rotor_index: int in range(custom_geometry.size()):
		var custom_rotor: Dictionary = custom_geometry[rotor_index]
		custom_rotor["position_local"] = custom_positions[rotor_index]
		custom_rotor["lift_axis_local"] = Vector3.RIGHT if rotor_index == 0 else Vector3.UP
		custom_rotor["spin_direction"] = 1 if rotor_index % 2 == 0 else -1
	var custom_modes: PackedFloat64Array = PackedFloat64Array()
	DronePPOObservationEncoder._append_rotor_modes(custom_modes, custom_geometry)
	_expect(
		custom_modes.size() == 4
		and absf(custom_modes[0]) < 1.0
		and not DronePPOObservationEncoder._uses_legacy_quad_layout(custom_geometry),
		"creator-authored four-rotor geometry uses real lift axes instead of the stock slot-index mixer"
	)


func _test_feature_audit() -> void:
	var names: Array[String] = ["first", "duplicate", "independent"]
	var samples: Array = [
		PackedFloat64Array([-1.0, -1.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 1.0]),
		PackedFloat64Array([1.0, 1.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, -1.0]),
	]
	var report: Dictionary = DronePPOFeatureAudit.analyze_samples(samples, names)
	_expect(
		int(report.get("effective_rank", 0)) == 2,
		"feature audit detects a linearly dependent input"
	)
	_expect(
		(report.get("high_correlation_pairs", []) as Array).size() == 1,
		"feature audit reports the correlated pair"
	)


func _test_policy_and_checkpoint(observation: Dictionary) -> void:
	var network = DronePPOActorCritic.new(1234)
	var actor_input = DronePPOObservationEncoder.encode_actor(observation)
	var forward_output: PackedFloat64Array = network.actor.forward(actor_input).get(
		"output",
		PackedFloat64Array()
	)
	_expect(
		_arrays_close(network.actor.predict(actor_input), forward_output),
		"allocation-light inference matches the backpropagation forward pass"
	)
	_expect(
		_arrays_close(
			network.actor.predict_reusable(actor_input),
			forward_output
		),
		"reusable inference workspace matches the public inference result"
	)
	var output_gradient = PackedFloat64Array([0.1, -0.2, 0.3, -0.4])
	network.actor.clear_gradients()
	var legacy_cache = network.actor.forward(actor_input)
	network.actor.backward(legacy_cache, output_gradient)
	var legacy_gradients = network.actor.gradients.duplicate()
	network.actor.clear_gradients()
	network.actor.predict_reusable(actor_input, true)
	network.actor.backward_reusable(output_gradient)
	_expect(
		_arrays_close(network.actor.gradients, legacy_gradients),
		"reusable backpropagation workspace preserves every gradient"
	)
	network.actor.clear_gradients()
	var deterministic = network.sample_action(observation, true)
	_expect(
		_commands(deterministic)
		== _commands({"action": network.deterministic_action(observation)}),
		"evaluation-only action path matches deterministic PPO sampling"
	)
	var commands: Array = deterministic.get("action", {}).get(
		"propeller_commands",
		[]
	)
	_expect(commands.size() == 4, "PPO actor emits four motor commands")
	var degraded_observation = observation.duplicate(true)
	var degraded_propellers: Array = degraded_observation["propellers"]
	var missing_propeller: Dictionary = degraded_propellers[1]
	missing_propeller["installed"] = false
	missing_propeller["realized_thrust_n"] = 0.0
	missing_propeller["maximum_static_thrust_n"] = 0.0
	var degraded_action: Dictionary = network.deterministic_action(degraded_observation)
	_expect(
		(degraded_action.get("propeller_commands", []) as Array).size() == 4,
		"PPO keeps commanding all four stable slots when one propeller is missing"
	)
	for index in range(commands.size()):
		var command: Dictionary = commands[index]
		_expect(
			int(command.get("slot_index", -1)) == index,
			"PPO action retains stable propeller slot identity"
		)
		_expect(
			float(command.get("command", -1.0)) >= 0.0
			and float(command.get("command", 2.0)) <= 1.0,
			"sigmoid-transformed PPO action is physically bounded"
		)

	var state = network.to_state()
	var restored = DronePPOActorCritic.new(9999)
	_expect(restored.load_state(state), "actor-critic checkpoint restores")
	var restored_action = restored.sample_action(observation, true)
	_expect(
		_commands(deterministic) == _commands(restored_action),
		"deterministic inference is unchanged by checkpoint round trip"
	)
	var atomic_target = DronePPOActorCritic.new(9998)
	var actor_before_failed_load: PackedFloat64Array = atomic_target.actor.parameters.duplicate()
	var corrupt_state: Dictionary = state.duplicate(true)
	var corrupt_critic: Dictionary = (corrupt_state.get("critic", {}) as Dictionary).duplicate(true)
	var corrupt_parameters: Array = (corrupt_critic.get("parameters", []) as Array).duplicate()
	corrupt_parameters[0] = NAN
	corrupt_critic["parameters"] = corrupt_parameters
	corrupt_state["critic"] = corrupt_critic
	_expect(
		not atomic_target.load_state(corrupt_state)
		and _arrays_close(actor_before_failed_load, atomic_target.actor.parameters),
		"a corrupt critic cannot partially replace the live PPO actor"
	)
	var malformed_network_metadata: Dictionary = state.duplicate(true)
	malformed_network_metadata["schema_version"] = {"broken": true}
	_expect(
		not atomic_target.load_state(malformed_network_metadata),
		"PPO network restore rejects wrong-type schema metadata without throwing"
	)
	var malformed_actor_shape: Dictionary = state.duplicate(true)
	malformed_actor_shape["actor"] = 17
	_expect(
		not atomic_target.load_state(malformed_actor_shape),
		"PPO network restore rejects wrong-type nested actor state without throwing"
	)
	atomic_target.actor.adam_first_moment[0] = NAN
	_expect(
		not atomic_target.is_finite_state(),
		"PPO finite-state validation includes Adam optimizer moments"
	)
	var current_trainer_for_contract = DronePPOTrainer.new(_ppo_config({}), 6601)
	var current_checkpoint = current_trainer_for_contract.to_checkpoint()
	var wrong_width_checkpoint = current_checkpoint.duplicate(true)
	var wrong_width_network: Dictionary = wrong_width_checkpoint.get(
		"network",
		{}
	).duplicate(true)
	wrong_width_network["hidden_size"] = 32
	wrong_width_checkpoint["network"] = wrong_width_network
	_expect(
		not bool(DroneTrainingAlgorithmCatalog.inspect_checkpoint(
			wrong_width_checkpoint
		).get("compatible", true)),
		"the checkpoint inspector rejects inconsistent top-level versus nested PPO architecture metadata"
	)
	# Architecture/schema changes deliberately invalidate older policies; a current model may
	# choose its own hidden shape and round-trip that exact shape.
	var old_schema_network = DronePPOActorCritic.new(5555, DronePPOObservationEncoder.TARGET_SCHEMA_VERSION)
	var current_restore = DronePPOActorCritic.new(5556)
	_expect(
		not current_restore.load_state(old_schema_network.to_state()),
		"obsolete PPO observation schemas are rejected instead of being silently migrated"
	)
	var custom_trainer = DronePPOTrainer.new(_ppo_config({
		"hidden_layer_width": 96,
		"hidden_layer_depth": 3,
	}), 6666)
	var custom_checkpoint = custom_trainer.to_checkpoint()
	var custom_inspection = DroneTrainingAlgorithmCatalog.inspect_checkpoint(custom_checkpoint)
	var custom_restored = DronePPOTrainer.new(_ppo_config({}), 6667)
	_expect(
		bool(custom_inspection.get("compatible", false))
		and custom_restored.load_checkpoint(custom_checkpoint)
		and custom_restored.actor_critic.hidden_size == 96
		and custom_restored.actor_critic.hidden_layer_count == 3,
		"custom PPO hidden width/depth are checkpointed, inspected, and restored exactly"
	)
	var legacy_network = DronePPOActorCritic.new(7777, DronePPOObservationEncoder.LEGACY_SCHEMA_VERSION)
	var current_trainer = DronePPOTrainer.new(_ppo_config({}), 7001)
	var legacy_checkpoint = current_trainer.to_checkpoint()
	legacy_checkpoint["network"] = legacy_network.to_state()
	var legacy_inspection = DroneTrainingAlgorithmCatalog.inspect_checkpoint(legacy_checkpoint)
	_expect(
		not bool(legacy_inspection.get("compatible", true)),
		"obsolete PPO model contracts are rejected rather than constraining the current architecture"
	)
	var runtime_copy = DronePPOActorCritic.new(4321)
	_expect(runtime_copy.copy_from(network), "packed runtime policy copy succeeds")
	var runtime_action = runtime_copy.sample_action(observation, true)
	_expect(
		_commands(deterministic) == _commands(runtime_action),
		"packed runtime policy copy preserves deterministic inference"
	)


func _test_belly_grabber_policy(observation: Dictionary) -> void:
	var loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	_expect(
		DroneTrainingLoadoutConfig.install_training_belly_grabber(loadout),
		"articulated belly limb installs for PPO topology testing"
	)
	var manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(loadout)
	_expect(manifest != null and manifest.finalized, "articulated drone body finalizes a model interface")
	if manifest == null:
		return
	var names: Array[String] = manifest.control_names()
	_expect(
		manifest.control_count() == 8
		and names.has("attachment_0.limb_0.segment_0.joint_x")
		and names.has("attachment_0.limb_0.segment_0.joint_z")
		and names.has("attachment_0.limb_0.segment_1.joint_z")
		and names.has("attachment_0.limb_0.grip"),
		"drone PPO receives the same shoulder, elbow, and grip controls declared by GenericLimbDefinition"
	)
	var body_observation: Dictionary = observation.duplicate(true)
	var body_features = PackedFloat64Array()
	body_features.resize(manifest.observation_count())
	body_features.fill(0.0)
	body_observation["model_body_features"] = body_features
	body_observation["model_body_signature"] = manifest.contract_signature
	var trainer = DronePPOTrainer.new({"body_interface": manifest.to_dictionary()}, 77113)
	var sample = trainer.sample_action(body_observation)
	var action: Dictionary = sample.get("action", {})
	var sampled_commands: Variant = sample.get("commands", PackedFloat64Array())
	var body_commands: Variant = action.get("body_commands", PackedFloat64Array())
	var limb_commands: Variant = action.get("limb_commands", PackedFloat64Array())
	_expect(
		sampled_commands is PackedFloat64Array
		and sampled_commands.size() == 8
		and body_commands is PackedFloat64Array
		and body_commands.size() == 8,
		"articulated drone PPO owns four rotors plus all four limb controls"
	)
	_expect(
		(action.get("propeller_commands", []) as Array).size() == 4
		and limb_commands is PackedFloat64Array
		and limb_commands.size() == 4,
		"compatibility mirrors retain four propeller commands and all articulated attachment commands"
	)
	var checkpoint = trainer.to_checkpoint()
	_expect(
		int((checkpoint.get("network", {}) as Dictionary).get("action_count", 0)) == 8
		and int((checkpoint.get("network", {}) as Dictionary).get("body_feature_count", -1))
		== manifest.observation_count(),
		"articulated body action and observation topology is persisted in PPO checkpoints"
	)
	var inspection = DroneTrainingAlgorithmCatalog.inspect_checkpoint(checkpoint)
	_expect(
		bool(inspection.get("compatible", false))
		and bool(inspection.get("trainable", false))
		and str(inspection.get("body_interface_signature", "")) == manifest.contract_signature,
		"articulated PPO checkpoint carries its exact accepted body contract"
	)
	var restored = DronePPOTrainer.new(_ppo_config({"body_interface": manifest.to_dictionary()}))
	_expect(
		restored.load_checkpoint(checkpoint)
		and restored.actor_critic.action_count == 8
		and restored.actor_critic.body_interface_signature == manifest.contract_signature,
		"PPO restoration requires and preserves the checkpoint's accepted body manifest"
	)
	var rotor_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(
		MLBodyPresetLibrary.drone_quad_loadout(false)
	)
	var rotor_only = DronePPOTrainer.new({"body_interface": rotor_manifest.to_dictionary()}, 77114)
	_expect(
		not rotor_only.copy_policy_from(trainer)
		and rotor_only.actor_critic.action_count == 4,
		"policy copying cannot silently replace rotor-only topology with an articulated body"
	)


func _test_trainable_schema_continuation(observation: Dictionary) -> void:
	for schema_version in [DronePPOObservationEncoder.SCHEMA_VERSION]:
		var checkpoint_source = DronePPOTrainer.new(_ppo_config({
			"rollout_transitions": 4,
			"minimum_update_transitions": 4,
			"minibatch_size": 2,
			"update_epochs": 1,
		}), 7900 + schema_version)
		var checkpoint = checkpoint_source.to_checkpoint()
		var resumed = DronePPOTrainer.new(_ppo_config({}), 8000 + schema_version)
		_expect(
			resumed.load_checkpoint(checkpoint),
			"trainable schema %d loads for continuation" % schema_version
		)
		for index in range(4):
			var sample = resumed.sample_action(observation)
			_expect(
				resumed.add_transition(
					0,
					sample,
					0.01,
					observation,
					false,
					index == 3
				),
				"trainable schema %d accepts a schema-matched transition" % schema_version
			)
		var metrics = resumed.update()
		_expect(
			not metrics.is_empty()
			and int(metrics.get("rollout_policy_revision", -1)) >= 0,
			"trainable schema %d completes a PPO continuation update" % schema_version
		)


func _test_behavior_policy_identity_and_overlap(observation: Dictionary) -> void:
	var config = {
		"rollout_transitions": 4,
		"minimum_update_transitions": 4,
		"minibatch_size": 2,
		"update_epochs": 1,
		"optimizer_samples_per_frame": 2,
	}
	var identity_trainer = DronePPOTrainer.new(_ppo_config(config), 8101)
	for index in range(4):
		var sample = identity_trainer.sample_action(observation)
		_expect(identity_trainer.add_transition(
			0,
			sample,
			0.02,
			observation,
			false,
			index == 3
		), "producer-policy identity transition is accepted")
	_expect(identity_trainer.begin_update(), "producer-policy identity update starts")
	_expect(
		identity_trainer.update_initial_log_probability_error_max
		<= DronePPOTrainer.INITIAL_LOG_PROBABILITY_TOLERANCE
		and absf(identity_trainer.update_initial_approximate_kl) <= 0.00000001
		and is_zero_approx(identity_trainer.update_initial_clip_fraction),
		"the optimizer starts from the exact policy that generated old log probabilities"
	)
	identity_trainer.discard_incomplete_rollout()

	var mixed = DronePPOTrainer.new(_ppo_config(config), 8102)
	var first = mixed.sample_action(observation)
	_expect(mixed.add_transition(0, first, 0.0, observation, false, false), "first policy revision enters rollout")
	var wrong_revision = mixed.sample_action(observation)
	wrong_revision["policy_revision"] = int(wrong_revision.get("policy_revision", 0)) + 1
	_expect(
		not mixed.add_transition(0, wrong_revision, 0.0, observation, false, false)
		and mixed.last_error.contains("behavior policy"),
		"a transition from a different producer policy is rejected before optimization"
	)

	var overlapping = DronePPOTrainer.new(_ppo_config(config), 8103)
	for index in range(4):
		var sample = overlapping.sample_action(observation)
		overlapping.add_transition(0, sample, 0.03, observation, false, index == 3)
	_expect(overlapping.begin_background_update(), "rollout A begins its detached background update")
	for index in range(4):
		var sample = overlapping.sample_action(observation)
		_expect(overlapping.add_transition(
			1,
			sample,
			0.04,
			observation,
			false,
			index == 3
		), "rollout B remains owned by producer revision zero while A optimizes")
	var deadline = Time.get_ticks_msec() + 5000
	while overlapping.has_background_update() and Time.get_ticks_msec() < deadline:
		overlapping.poll_background_update()
		if overlapping.has_background_update():
			OS.delay_msec(1)
	if overlapping.has_background_update():
		overlapping.shutdown_background_update()
	_expect(not overlapping.has_background_update(), "rollout A background update completes")
	_expect(
		overlapping.rollout_policy_revision == 0
		and overlapping.policy_sync_pending,
		"rollout B keeps its immutable revision while optimizer revision one waits to synchronize"
	)
	_expect(overlapping.begin_update(), "rollout B starts from its own producer snapshot")
	_expect(
		int(overlapping.update_prepared.get("rollout_policy_revision", -1)) == 0
		and overlapping.update_initial_log_probability_error_max
		<= DronePPOTrainer.INITIAL_LOG_PROBABILITY_TOLERANCE,
		"overlapping rollout B optimizes from revision zero rather than the newer optimizer"
	)
	overlapping.discard_incomplete_rollout()


func _test_weight_variation(observation: Dictionary) -> void:
	var source = DronePPOTrainer.new(_ppo_config({}), 8128)
	var first_child = DronePPOTrainer.new(_ppo_config({}), 8129)
	var second_child = DronePPOTrainer.new(_ppo_config({}), 8130)
	_expect(first_child.copy_policy_from(source), "variation child copies its parent")
	_expect(second_child.copy_policy_from(source), "second variation child copies its parent")
	_expect(first_child.perturb_policy(0.025, 99173), "nearby PPO variation is finite")
	_expect(second_child.perturb_policy(0.025, 99173), "same seeded variation is finite")
	var parent_commands = _commands({
		"action": source.behavior_actor_critic.deterministic_action(observation),
	})
	var first_commands = _commands({
		"action": first_child.behavior_actor_critic.deterministic_action(observation),
	})
	var second_commands = _commands({
		"action": second_child.behavior_actor_critic.deterministic_action(observation),
	})
	_expect(
		parent_commands != first_commands,
		"weight variation produces a behaviorally distinct child"
	)
	_expect(
		first_commands == second_commands,
		"weight variation is reproducible from its branch seed"
	)
	_expect(
		first_child.actor_critic.actor.optimizer_step == 0
		and first_child.actor_critic.critic.optimizer_step == 0,
		"weight variation clears inherited Adam momentum"
	)
	_expect(
		first_child.actor_critic.is_finite_state()
		and first_child.behavior_actor_critic.is_finite_state(),
		"varied optimizer and behavior policies remain finite"
	)


func _test_algorithm_catalog() -> void:
	var algorithm = DroneTrainingAlgorithmCatalog.create(
		DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID,
		_ppo_config({}),
		7171
	)
	_expect(algorithm != null, "PPO training algorithm is registered when an accepted body is supplied")
	_expect(
		DroneTrainingAlgorithmCatalog.create(
			DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID, {}, 7172
		) == null,
		"PPO initialization cannot silently invent a stock body when no accepted manifest is supplied"
	)
	_expect(
		algorithm.algorithm_id() == "ppo_clip",
		"training-room algorithm boundary identifies PPO without concrete casts"
	)
	var configuration_controls = algorithm.configuration_controls()
	_expect(
		not configuration_controls.is_empty(),
		"registered algorithm provides its own maintainable tuning schema"
	)
	var exploration_maximum = 0.0
	for definition: Dictionary in configuration_controls:
		if str(definition.get("key", "")) == "entropy_coefficient":
			exploration_maximum = float(definition.get("maximum", 0.0))
			break
	_expect(
		exploration_maximum >= 2.0,
		"exploration strength is not artificially capped at 0.2"
	)


func _test_robust_elite_candidate(observation: Dictionary) -> void:
	var worker_scores: Array[float] = [
		1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 100.0,
	]
	var trainer = DronePPOTrainer.new(_ppo_config({
		"control_interval_seconds": 0.05,
		"rollout_transitions": 32,
		"minimum_update_transitions": 32,
		"minibatch_size": 8,
	}), 7272)
	for worker_id in range(worker_scores.size()):
		for transition_index in range(4):
			var sample = trainer.sample_action(observation)
			_expect(
				trainer.add_transition(
					worker_id,
					sample,
					worker_scores[worker_id] * 0.10,
					observation,
					transition_index == 3,
					false,
					PackedFloat64Array(),
					NAN,
					{"delta_seconds": 0.10}
				),
				"elite-selection transition is accepted"
			)
	_expect(trainer.begin_update(), "complete rollout nominates a frozen evaluation candidate")
	var candidate = trainer.pending_evaluation_candidate()
	_expect(
		is_equal_approx(float(candidate.get("best_worker_reward_per_second", 0.0)), 100.0),
		"best worker uses actual transition time and remains visible instead of being swallowed by an average"
	)
	_expect(
		float(candidate.get("robust_best_worker_reward_per_second", 100.0)) < 3.0,
		"one extreme worker is capped by the interquartile outlier fence"
	)
	_expect(
		float(candidate.get("selection_score", 0.0)) > 1.5
		and float(candidate.get("selection_score", 0.0)) < 3.0,
		"training performance nominates an outlier-resistant candidate"
	)
	_expect(
		bool(candidate.get("exact_policy_match", false))
		and trainer.pending_auto_save_candidate().is_empty()
		and not trainer.has_best_checkpoint(),
		"a training rollout cannot auto-save or become Best before deterministic evaluation"
	)
	var plan: Dictionary = candidate.get("evaluation_plan", {})
	var plan_cases: Array = plan.get("cases", []) as Array
	_expect(
		plan_cases.size() == 30
		and RLDeterministicEvaluationSuite.DEFAULT_CASE_DURATION_SECONDS > 0.0,
		"drone candidate plans expose 30 cases with a finite runtime evaluation duration"
	)
	var frozen_candidate_id: int = int(candidate.get("candidate_id", -1))
	var frozen_candidate_hash: String = str(candidate.get("candidate_hash", ""))
	var tampered_candidate_checkpoint: Dictionary = trainer.to_checkpoint().duplicate(true)
	var tampered_training: Dictionary = (tampered_candidate_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var tampered_candidate_network: Dictionary = (tampered_training.get("candidate_network_state", {}) as Dictionary).duplicate(true)
	tampered_candidate_network["action_rng_state"] = int(tampered_candidate_network.get("action_rng_state", 0)) + 1
	tampered_training["candidate_network_state"] = tampered_candidate_network
	tampered_candidate_checkpoint["training"] = tampered_training
	var tampered_restore = DronePPOTrainer.new(_ppo_config({}), 7323)
	_expect(
		tampered_restore.load_checkpoint(tampered_candidate_checkpoint)
		and tampered_restore.pending_evaluation_candidate().is_empty()
		and not is_finite(tampered_restore.best_candidate_score),
		"PPO restore discards a pending candidate whose frozen network no longer matches its evaluation hash"
	)
	var malformed_candidate_checkpoint: Dictionary = trainer.to_checkpoint().duplicate(true)
	var malformed_training: Dictionary = (malformed_candidate_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var malformed_pending: Dictionary = (malformed_training.get("pending_evaluation_candidate", {}) as Dictionary).duplicate(true)
	malformed_pending["evaluation_contract"] = 17
	malformed_training["pending_evaluation_candidate"] = malformed_pending
	malformed_candidate_checkpoint["training"] = malformed_training
	var malformed_restore = DronePPOTrainer.new(_ppo_config({}), 7324)
	_expect(
		malformed_restore.load_checkpoint(malformed_candidate_checkpoint)
		and malformed_restore.pending_evaluation_candidate().is_empty(),
		"PPO restore treats malformed nested Candidate metadata as disposable derived state"
	)
	var malformed_id_checkpoint: Dictionary = trainer.to_checkpoint().duplicate(true)
	var malformed_id_training: Dictionary = (malformed_id_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var malformed_id_pending: Dictionary = (malformed_id_training.get("pending_evaluation_candidate", {}) as Dictionary).duplicate(true)
	malformed_id_pending["candidate_id"] = {"wrong": true}
	malformed_id_training["pending_evaluation_candidate"] = malformed_id_pending
	malformed_id_checkpoint["training"] = malformed_id_training
	var malformed_id_restore: DronePPOTrainer = DronePPOTrainer.new(_ppo_config({}), 7326)
	_expect(
		malformed_id_restore.load_checkpoint(malformed_id_checkpoint)
		and malformed_id_restore.pending_evaluation_candidate().is_empty()
		and malformed_id_restore.pending_evaluation_candidate_id() == -1,
		"PPO restore discards a pending Candidate with a malformed identity before evaluator scheduling"
	)
	var malformed_best_checkpoint: Dictionary = trainer.to_checkpoint().duplicate(true)
	var malformed_best_training: Dictionary = (
		(malformed_best_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	)
	malformed_best_training["best_candidate"] = "broken"
	malformed_best_training["has_best_episode"] = true
	malformed_best_training["best_episode_mean_reward"] = NAN
	malformed_best_checkpoint["training"] = malformed_best_training
	var malformed_best_restore = DronePPOTrainer.new(_ppo_config({}), 7325)
	_expect(
		malformed_best_restore.load_checkpoint(malformed_best_checkpoint)
		and not is_finite(malformed_best_restore.best_episode_mean_reward)
		and not is_finite(malformed_best_restore.best_candidate_score),
		"PPO restore discards malformed/non-finite Best diagnostics without interrupting policy restore"
	)
	var later_rollout: Array[Dictionary] = []
	for worker_id in range(worker_scores.size()):
		for _transition_index in range(4):
			later_rollout.append({
				"worker_id": worker_id,
				"reward": 1000.0 * 0.05,
			})
	trainer._consider_rollout_candidate(later_rollout)
	var still_frozen: Dictionary = trainer.pending_evaluation_candidate()
	_expect(
		int(still_frozen.get("candidate_id", -1)) == frozen_candidate_id
		and str(still_frozen.get("candidate_hash", "")) == frozen_candidate_hash,
		"an in-flight PPO evaluation candidate cannot be replaced by a newer rollout before its fixed-seed suite finishes"
	)
	var records: Array[Dictionary] = []
	for case_value in plan.get("cases", []):
		var evaluation_case: Dictionary = case_value
		records.append({
			"scenario_id": str(evaluation_case.get("scenario_id", "")),
			"seed": int(evaluation_case.get("seed", 0)),
			"episode_return": 2.0,
			"success": true,
			"crashed": false,
			"terminated": false,
			"truncated": true,
		})
	var promotion = trainer.record_deterministic_evaluation_records(
		int(candidate.get("candidate_id", -1)),
		records
	)
	_expect(
		bool(promotion.get("promoted", false))
		and trainer.has_best_checkpoint()
		and not trainer.pending_auto_save_candidate().is_empty(),
		"the complete fixed-seed suite promotes and auto-saves the frozen candidate"
	)
	var best_summary = trainer.best_selection_summary()
	_expect(
		bool(best_summary.get("evaluation_verified", false))
		and is_equal_approx(float(best_summary.get("selection_score", 0.0)), 2.0),
		"Best is labelled with the deterministic evaluation statistic"
	)
	var best_checkpoint = trainer.to_best_checkpoint()
	var best_training: Dictionary = best_checkpoint.get("training", {})
	_expect(
		int(best_training.get("update_count", -1))
		== int(candidate.get("policy_update", -2))
		and int(best_training.get("environment_steps", -1))
		== int(candidate.get("environment_steps", -2)),
		"saved-best counters describe the exact evaluated candidate policy"
	)
	var restored = DronePPOTrainer.new(_ppo_config({}), 7373)
	_expect(
		restored.load_checkpoint(best_checkpoint)
		and restored.has_best_checkpoint()
		and bool(restored.best_selection_summary().get("evaluation_verified", false)),
		"deterministic evaluation metadata and policy survive a checkpoint round trip"
	)
	var legacy_checkpoint = best_checkpoint.duplicate(true)
	var legacy_training: Dictionary = legacy_checkpoint["training"]
	legacy_training.erase("best_evaluation")
	legacy_training.erase("promoted_training_summary")
	legacy_checkpoint["training"] = legacy_training
	var legacy_restored = DronePPOTrainer.new(_ppo_config({}), 7474)
	_expect(
		legacy_restored.load_checkpoint(legacy_checkpoint)
		and not legacy_restored.has_best_checkpoint()
		and not legacy_restored.pending_evaluation_candidate().is_empty(),
		"pre-evaluator checkpoints load as pending candidates instead of falsely retaining Best"
	)
	trainer.discard_incomplete_rollout()


func _test_terminated_and_truncated_bootstrap(observation: Dictionary) -> void:
	var trainer = DronePPOTrainer.new(_ppo_config({
		"rollout_transitions": 2,
		"minimum_update_transitions": 2,
	}), 2222)
	trainer.actor_critic.critic.parameters[
		trainer.actor_critic.critic.output_bias_offset()
	] = 2.0
	trainer.behavior_actor_critic.critic.parameters[
		trainer.behavior_actor_critic.critic.output_bias_offset()
	] = 2.0
	var terminal_sample = trainer.sample_action(observation)
	var truncated_sample = trainer.sample_action(observation)
	_expect(
		trainer.add_transition(0, terminal_sample, 0.0, {}, true, false),
		"terminal transition is accepted without fabricating a successor observation"
	)
	_expect(
		trainer.add_transition(1, truncated_sample, 0.0, observation, false, true),
		"time-limit transition is accepted"
	)
	var invalid_duration_sample = trainer.sample_action(observation)
	_expect(
		not trainer.add_transition(
			2,
			invalid_duration_sample,
			0.0,
			observation,
			false,
			false,
			PackedFloat64Array(),
			NAN,
			{"delta_seconds": NAN}
		),
		"PPO rejects non-finite transition durations before GAE"
	)
	var malformed_duration_sample: Dictionary = trainer.sample_action(observation)
	_expect(
		not trainer.add_transition(
			4, malformed_duration_sample, 0.0, observation, false, false,
			PackedFloat64Array(), NAN, {"delta_seconds": {"wrong": true}}
		),
		"PPO rejects wrong-type transition duration metadata without a numeric cast failure"
	)
	var contradictory_boundary_sample = trainer.sample_action(observation)
	_expect(
		not trainer.add_transition(
			3,
			contradictory_boundary_sample,
			0.0,
			observation,
			true,
			true
		),
		"PPO rejects a transition that is both terminated and truncated"
	)
	_expect(
		is_zero_approx(float(trainer.rollout[0]["next_value"])),
		"natural terminal state does not bootstrap"
	)
	_expect(
		absf(float(trainer.rollout[1]["next_value"])) > 0.1,
		"time-limit truncation bootstraps from the critic"
	)


func _test_bootstrap_value_override(observation: Dictionary) -> void:
	var trainer = DronePPOTrainer.new(_ppo_config({}), 2323)
	var sample = trainer.sample_action(observation)
	var actor_input = DronePPOObservationEncoder.encode_actor(observation)
	var critic_input = DronePPOObservationEncoder.encode_critic_from_actor(
		actor_input,
		observation
	)
	var reused_value = 0.375
	_expect(
		trainer.add_transition(
			0,
			sample,
			0.1,
			observation,
			false,
			false,
			critic_input,
			reused_value
		),
		"a precomputed next-state value is accepted"
	)
	_expect(
		is_equal_approx(float(trainer.rollout[0]["next_value"]), reused_value),
		"the room can reuse the next action's critic value without another critic pass"
	)
	var terminal_sample = trainer.sample_action(observation)
	_expect(
		trainer.add_transition(
			1,
			terminal_sample,
			0.0,
			observation,
			true,
			false,
			critic_input,
			5.0
		),
		"terminal transition still accepts the optimized API"
	)
	_expect(
		is_zero_approx(float(trainer.rollout[1]["next_value"])),
		"terminal transitions ignore any bootstrap override"
	)


func _test_optimizer_update(observation: Dictionary) -> void:
	var trainer = DronePPOTrainer.new(_ppo_config({
		"rollout_transitions": SYNTHETIC_TRANSITIONS,
		"minimum_update_transitions": 4,
		"minibatch_size": 4,
		"update_epochs": 2,
	}), 3333)
	var before = trainer.actor_critic.actor.parameters.duplicate()
	for index in range(SYNTHETIC_TRANSITIONS):
		var sample = trainer.sample_action(observation)
		var terminated = index == SYNTHETIC_TRANSITIONS - 1
		_expect(
			trainer.add_transition(
				index % 2,
				sample,
				0.1 + float(index % 3) * 0.02,
				observation,
				terminated,
				false
			),
			"synthetic PPO transition is accepted"
		)
	var metrics = trainer.update()
	_expect(not metrics.is_empty(), "full rollout triggers a PPO update")
	_expect(trainer.update_count == 1, "optimizer update counter advances")
	_expect(trainer.rollout.is_empty(), "on-policy rollout is consumed once")
	_expect(
		trainer.actor_critic.is_finite_state(),
		"PPO update leaves every network parameter finite"
	)
	var parameter_changed = false
	for index in range(before.size()):
		if not is_equal_approx(before[index], trainer.actor_critic.actor.parameters[index]):
			parameter_changed = true
			break
	_expect(parameter_changed, "PPO gradients change actor parameters")


func _test_background_optimizer(observation: Dictionary) -> void:
	var config = {
		"rollout_transitions": 8,
		"minimum_update_transitions": 4,
		"minibatch_size": 4,
		"update_epochs": 2,
		"optimizer_samples_per_frame": 2,
	}
	var trainer = DronePPOTrainer.new(_ppo_config(config), 3366)
	var synchronous = DronePPOTrainer.new(_ppo_config(config), 3366)
	for index in range(8):
		var sample = trainer.sample_action(observation)
		for candidate in [trainer, synchronous]:
			_expect(
				candidate.add_transition(
					index % 2,
					sample,
					0.08 + float(index) * 0.01,
					observation,
					index == 7,
					false
				),
				"background-equivalence PPO transition is accepted"
			)
	var synchronous_metrics = synchronous.update()
	_expect(
		not synchronous_metrics.is_empty(),
		"background reference update completes synchronously"
	)
	_expect(
		trainer.begin_background_update(),
		"detached PPO update starts on a background thread"
	)
	_expect(
		trainer.rollout.is_empty(),
		"background worker owns the detached rollout"
	)
	var stale_during_update = trainer.sample_action(observation)
	_expect(
		trainer.add_transition(
			3,
			stale_during_update,
			0.05,
			observation,
			false,
			false
		)
		and trainer.rollout.is_empty(),
		"PPO keeps workers flying during optimization without collecting a stale second rollout"
	)
	var metrics: Dictionary = {}
	var deadline = Time.get_ticks_msec() + 5000
	while trainer.has_background_update() and Time.get_ticks_msec() < deadline:
		metrics = trainer.poll_background_update()
		if trainer.has_background_update():
			OS.delay_msec(1)
	if trainer.has_background_update():
		trainer.shutdown_background_update()
	_expect(
		not metrics.has("error"),
		"background PPO update returns no worker error"
	)
	_expect(not metrics.is_empty(), "background PPO update returns metrics")
	_expect(trainer.update_count == 1, "background update counter advances")
	_expect(
		float(metrics.get("optimizer_wall_time_ms", 0.0)) >= 0.0,
		"background update reports its wall-clock duration"
	)
	_expect(
		trainer.actor_critic.is_finite_state(),
		"background PPO update adopts a finite optimizer state"
	)
	_expect(
		trainer.behavior_policy_revision() == trainer.optimizer_policy_revision
		and not trainer.policy_sync_pending,
		"a completed PPO update becomes the live behavior policy immediately"
	)
	_expect(
		int(metrics.get("discarded_on_policy_transitions", 0)) >= 1,
		"PPO reports on-policy samples deliberately discarded during asynchronous optimization"
	)
	_expect(
		trainer.add_transition(
			3,
			stale_during_update,
			0.05,
			observation,
			false,
			false
		)
		and trainer.rollout.is_empty(),
		"a held action that straddles policy adoption is dropped instead of contaminating the new rollout"
	)
	_expect(
		_arrays_close(
			trainer.actor_critic.actor.parameters,
			synchronous.actor_critic.actor.parameters
		)
		and _arrays_close(
			trainer.actor_critic.critic.parameters,
			synchronous.actor_critic.critic.parameters
		)
		and _arrays_close(
			trainer.actor_critic.log_standard_deviation,
			synchronous.actor_critic.log_standard_deviation
		),
		"background optimizer is mathematically equivalent to the synchronous path"
	)


func _test_incremental_optimizer(observation: Dictionary) -> void:
	var trainer = DronePPOTrainer.new(_ppo_config({
		"rollout_transitions": 8,
		"minimum_update_transitions": 4,
		"minibatch_size": 2,
		"update_epochs": 2,
		"optimizer_samples_per_frame": 1,
	}), 4444)
	for index in range(8):
		var sample = trainer.sample_action(observation)
		trainer.add_transition(
			index % 2,
			sample,
			0.05,
			observation,
			index == 7,
			false
		)
	_expect(trainer.begin_update(), "a full rollout starts an incremental PPO job")
	var first_frame = trainer.process_update(1)
	_expect(
		first_frame.is_empty() and trainer.update_in_progress,
		"one optimizer example does not synchronously consume every epoch"
	)
	var concurrent_sample = trainer.sample_action(observation)
	_expect(
		not concurrent_sample.is_empty(),
		"stable behavior policy keeps producing actions while optimization advances"
	)
	while trainer.update_in_progress:
		trainer.process_update(1)
	_expect(trainer.update_count == 1, "incremental optimizer completes exactly one update")
	_expect(trainer.actor_critic.is_finite_state(), "incremental update remains finite")


func _test_chunked_optimizer_equivalence(observation: Dictionary) -> void:
	var config = {
		"rollout_transitions": 8,
		"minimum_update_transitions": 4,
		"minibatch_size": 4,
		"update_epochs": 2,
		"optimizer_samples_per_frame": 1,
	}
	var immediate = DronePPOTrainer.new(_ppo_config(config), 5555)
	var chunked = DronePPOTrainer.new(_ppo_config(config), 5555)
	for index in range(8):
		var immediate_sample = immediate.sample_action(observation)
		var chunked_sample = chunked.sample_action(observation)
		var reward = 0.02 * float(index + 1)
		var terminated = index == 7
		immediate.add_transition(
			index % 2, immediate_sample, reward, observation, terminated, false
		)
		chunked.add_transition(
			index % 2, chunked_sample, reward, observation, terminated, false
		)
	immediate.update()
	chunked.begin_update()
	while chunked.update_in_progress:
		chunked.process_update(1)
	_expect(
		_arrays_close(
			immediate.actor_critic.actor.parameters,
			chunked.actor_critic.actor.parameters
		)
		and _arrays_close(
			immediate.actor_critic.critic.parameters,
			chunked.actor_critic.critic.parameters
		)
		and _arrays_close(
			immediate.actor_critic.log_standard_deviation,
			chunked.actor_critic.log_standard_deviation
		),
		"sample-chunked optimization is mathematically equivalent to an immediate update"
	)


func _observation(episode_progress: float) -> Dictionary:
	var propellers: Array[Dictionary] = []
	for index in range(4):
		propellers.append({
			"slot_index": index,
			"realized_thrust_n": 2.0,
			"maximum_static_thrust_n": 4.0,
		})
	return {
		"body": {
			"position_world": Vector3(-2.0, 2.0, 1.0),
			"basis_world": Basis.IDENTITY,
			"linear_velocity_local": Vector3(0.2, -0.1, 0.3),
			"angular_velocity_local": Vector3(0.1, 0.2, -0.1),
		},
		"objective": {
			"target_position_world": Vector3(1.0, 3.0, -1.0),
			"target_velocity_world": Vector3(0.5, 0.0, 0.0),
			"target_hover_radius_m": 0.75,
			"episode_progress": episode_progress,
			"obstacle_probe": {
				"nearest_direction_local": Vector3.LEFT,
				"nearest_direction_yaw_local": Vector3.LEFT,
				"nearest_distance_m": 1.5,
				"maximum_distance_m": 4.0,
				"target_path_blocked": true,
				"sector_clearances_m": PackedFloat64Array([3.0, 6.0, 12.0, 12.0, 9.0, 12.0, 4.0, 2.0]),
				"sector_maximum_distance_m": 12.0,
				"target_path_clearance_m": 2.0,
				"target_path_maximum_distance_m": 6.0,
				"target_wall_top_relative_height_m": 2.0,
			},
		},
		"electrical": {
			"battery_charge_ratio": 0.8,
			"bus_voltage_v": 11.5,
			"available_power_w": 100.0,
			"power_spool_ratio": 0.9,
			"spike_multiplier": 1.0,
		},
		"environment": {"ground_clearance_m": 2.0},
		"parts": {
			"battery": {"nominal_voltage_v": 12.0},
			"core": {"maximum_power_throughput_w": 120.0},
		},
		"propellers": propellers,
	}


func _arrays_close(first: PackedFloat64Array, second: PackedFloat64Array) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if not is_equal_approx(first[index], second[index]):
			return false
	return true


func _commands(sample: Dictionary) -> Array[float]:
	var result: Array[float] = []
	for command: Dictionary in sample.get("action", {}).get(
		"propeller_commands",
		[]
	):
		result.append(float(command.get("command", 0.0)))
	return result


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)

func _ppo_config(overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = overrides.duplicate(true)
	if not result.has("body_interface"):
		var preset: MLBodyPreset = MLBodyPresetLibrary.preset_by_id(MLBodyPresetLibrary.DRONE_QUAD)
		var manifest: MLBodyInterfaceManifest = preset.instantiate_manifest() if preset != null else null
		if manifest != null:
			result["body_interface"] = manifest.to_dictionary()
	return result
