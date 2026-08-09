extends SceneTree

var failure_count = 0
var assertion_count = 0


func _init() -> void:
	_test_catalog()
	_test_network_capacity()
	var observation = _observation(0.1, Vector3(-2.0, 2.0, 1.0))
	_test_memory_and_encoder(observation)
	_test_raw_propeller_action_space(observation)
	_test_state_dependent_exploration(observation)
	_test_structured_warmup(observation)
	_test_critic_bootstrap_before_actor_learning(observation)
	_test_exploration_bonus(observation)
	_test_boundary_safety_shaping(observation)
	_test_hindsight_reward_identity(observation)
	_test_policy_and_checkpoint(observation)
	_test_transition_validation_and_atomic_full_restore(observation)
	_test_frozen_evaluation_candidate()
	_test_legacy_global_exploration_migration(observation)
	_test_replay_and_hindsight(observation)
	_test_hindsight_uses_latest_safe_future_before_crash()
	print("SAC-HER assertions: %d, failures: %d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_network_capacity() -> void:
	_expect(
		DroneSACActorCritic.HIDDEN_SIZE >= 128
		and DroneSACActorCritic.HIDDEN_SIZE
		> DroneSACObservationEncoder.ACTOR_FEATURE_COUNT,
		"SAC no longer squeezes the expanded navigation/turret observation through the old 64-unit bottleneck"
	)


func _test_catalog() -> void:
	var descriptor = DroneTrainingAlgorithmCatalog.descriptor("sac_her_maze")
	_expect(not descriptor.is_empty(), "SAC-HER is registered in the algorithm catalog")
	var trainer = DroneTrainingAlgorithmCatalog.create("sac_her_maze", {}, 1001)
	_expect(trainer is DroneSACTrainer, "the catalog creates the maze SAC trainer")


func _test_memory_and_encoder(observation: Dictionary) -> void:
	var memory = DroneSACNavigationMemory.new()
	var first = memory.features_for(7, observation)
	var second = memory.features_for(7, observation)
	_expect(first.size() == DroneSACNavigationMemory.FEATURE_COUNT, "navigation memory exposes its fixed feature count")
	_expect(second[0] > first[0], "revisiting a cell raises its visit-density feature")
	_expect(
		first[first.size() - 2] > 0.0 and first[first.size() - 1] < 0.0,
		"the least-visited front-right heading uses Godot's positive-right local frame"
	)
	var actor_input = DroneSACObservationEncoder.encode_actor(observation, second)
	var critic_input = DroneSACObservationEncoder.encode_critic_from_actor(actor_input, observation)
	var trainer = DroneSACTrainer.new({}, 1002)
	var restored_memory = trainer._actor_memory_suffix(actor_input)
	var restored_actor = trainer._actor_prefix(critic_input)
	_expect(actor_input.size() == DroneSACObservationEncoder.ACTOR_FEATURE_COUNT, "SAC actor tensor has the declared shape")
	_expect(critic_input.size() == DroneSACObservationEncoder.CRITIC_FEATURE_COUNT, "SAC critic tensor has the declared shape")
	_expect(
		restored_memory == second,
		"SAC extracts raw navigation memory from the unchanged legacy columns before appended turret features"
	)
	_expect(
		restored_actor == actor_input,
		"SAC reconstructs the actor tensor from legacy critic columns plus the appended turret suffix"
	)
	if actor_input.size() != DroneSACObservationEncoder.ACTOR_FEATURE_COUNT:
		return
	_expect(
		actor_input[DroneSACObservationEncoder.TARGET_FORWARD_FEATURE_INDEX] > 0.0,
		"a target in Godot forward (-Z) is encoded as positive SAC forward error"
	)
	_expect(
		actor_input[DroneSACObservationEncoder.TARGET_DIRECTION_FORWARD_FEATURE_INDEX] > 0.0,
		"the explicit target direction uses the same positive-forward SAC convention"
	)
	var feature_names = DroneSACObservationEncoder.actor_feature_names()
	var target_present_index = feature_names.find("target_present")
	var target_distance_index = feature_names.find("target_distance")
	var target_boundary_index = feature_names.find("target_boundary_error")
	var target_inside_index = feature_names.find("target_inside_radius")
	_expect(
		target_present_index >= 0
		and is_equal_approx(actor_input[target_present_index], 1.0)
		and target_distance_index >= 0
		and target_boundary_index >= 0
		and target_inside_index >= 0
		and actor_input[target_distance_index] > -1.0
		and actor_input[target_boundary_index] > 0.0
		and is_equal_approx(actor_input[target_inside_index], -1.0),
		"SAC receives the explicit target presence, distance, boundary, and success state"
	)
	_expect(
		actor_input[actor_input.size() - 1] > 0.0,
		"a least-visited front-right heading is encoded with positive SAC forward sign"
	)
	var right_feedback_observation = observation.duplicate(true)
	var right_feedback_propellers: Array = right_feedback_observation.get("propellers", []).duplicate(true)
	for index in range(right_feedback_propellers.size()):
		var propeller: Dictionary = right_feedback_propellers[index]
		propeller["realized_thrust_n"] = 3.0 if index == 0 or index == 2 else 1.0
		right_feedback_propellers[index] = propeller
	right_feedback_observation["propellers"] = right_feedback_propellers
	var right_feedback_input = DroneSACObservationEncoder.encode_actor(
		right_feedback_observation,
		second
	)
	_expect(right_feedback_input.size() == DroneSACObservationEncoder.ACTOR_FEATURE_COUNT, "sign-aligned rotor feedback tensor is valid")
	if right_feedback_input.size() != DroneSACObservationEncoder.ACTOR_FEATURE_COUNT:
		return
	_expect(
		right_feedback_input[DroneSACObservationEncoder.ROTOR_LEGACY_FRONT_MINUS_BACK_FEATURE_INDEX] > 0.0,
		"left-pair thrust is encoded as positive realized move-right control"
	)
	var signed_feedback_observation = observation.duplicate(true)
	var signed_body: Dictionary = signed_feedback_observation.get("body", {}).duplicate(true)
	signed_body["angular_velocity_local"] = Vector3(-0.5, 0.0, -0.5)
	signed_feedback_observation["body"] = signed_body
	var signed_objective: Dictionary = signed_feedback_observation.get("objective", {}).duplicate(true)
	var signed_probe: Dictionary = signed_objective.get("obstacle_probe", {}).duplicate(true)
	signed_probe["nearest_direction_yaw_local"] = Vector3.FORWARD
	signed_objective["obstacle_probe"] = signed_probe
	signed_feedback_observation["objective"] = signed_objective
	var signed_feedback_input = DroneSACObservationEncoder.encode_actor(
		signed_feedback_observation,
		second
	)
	_expect(signed_feedback_input.size() == DroneSACObservationEncoder.ACTOR_FEATURE_COUNT, "signed flight feedback tensor is valid")
	if signed_feedback_input.size() != DroneSACObservationEncoder.ACTOR_FEATURE_COUNT:
		return
	_expect(
		signed_feedback_input[DroneSACObservationEncoder.FORWARD_TILT_RATE_FEATURE_INDEX] > 0.0,
		"negative local-X angular rate is positive forward-tilt rate in SAC coordinates"
	)
	_expect(
		signed_feedback_input[DroneSACObservationEncoder.RIGHT_TILT_RATE_FEATURE_INDEX] > 0.0,
		"negative local-Z angular rate is positive right-tilt rate in SAC coordinates"
	)
	_expect(
		signed_feedback_input[DroneSACObservationEncoder.NEAREST_OBSTACLE_FORWARD_FEATURE_INDEX] > 0.0,
		"an obstacle in Godot forward (-Z) has positive SAC forward direction"
	)
	_expect(
		feature_names.size() == DroneSACObservationEncoder.ACTOR_FEATURE_COUNT,
		"SAC feature names match the sign-aligned actor tensor"
	)
	_expect(DroneSACObservationEncoder.valid_tensors(actor_input, critic_input), "SAC tensors remain finite and normalized")

	# SAC intentionally retains its established rotor-only schema until it becomes body-manifest aware.
	# A PPO/body-enabled snapshot must therefore not silently change SAC's fixed input width.
	var body_augmented_observation: Dictionary = observation.duplicate(true)
	body_augmented_observation["model_body_features"] = PackedFloat64Array([0.2, -0.2, 0.4, -0.4])
	body_augmented_observation["model_body_signature"] = "test-body-contract"
	var body_augmented_input: PackedFloat64Array = DroneSACObservationEncoder.encode_actor(
		body_augmented_observation,
		second
	)
	_expect(
		body_augmented_input.size() == DroneSACObservationEncoder.ACTOR_FEATURE_COUNT
		and _arrays_close(body_augmented_input, actor_input),
		"legacy SAC is pinned to its rotor/navigation schema instead of inheriting dynamic PPO body features"
	)

	var high_target_observation: Dictionary = observation.duplicate(true)
	var high_body: Dictionary = high_target_observation.get("body", {}).duplicate(true)
	high_body["position_world"] = Vector3(0.0, 1.2, 0.0)
	high_target_observation["body"] = high_body
	var high_objective: Dictionary = high_target_observation.get("objective", {}).duplicate(true)
	high_objective["target_position_world"] = Vector3(0.0, 15.0, 0.0)
	high_target_observation["objective"] = high_objective
	var high_memory = DroneSACNavigationMemory.new().features_for(8, high_target_observation)
	var high_sac_input = DroneSACObservationEncoder.encode_actor(high_target_observation, high_memory)
	var high_ppo_input = DronePPOObservationEncoder.encode_actor(high_target_observation)
	var height_index: int = DroneSACObservationEncoder.actor_feature_names().find(
		"target_offset_local_y"
	)
	var ppo_height_index: int = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
		"target_offset_local_y"
	)
	var expected_height_signal: float = clampf(
		(15.0 - 1.2) / DronePPOObservationEncoder.TARGET_OFFSET_SCALE_M,
		-1.0,
		1.0
	)
	_expect(
		height_index >= 0
		and ppo_height_index >= 0
		and is_equal_approx(high_sac_input[height_index], expected_height_signal)
		and is_equal_approx(high_sac_input[height_index], high_ppo_input[ppo_height_index])
		and high_sac_input[height_index] > 0.8,
		"SAC preserves PPO's strong positive vertical target signal for a 15 m objective above a 1.2 m spawn"
	)


func _test_raw_propeller_action_space(observation: Dictionary) -> void:
	var actor_critic = DroneSACActorCritic.new(1441)
	var neutral_command = actor_critic._command_from_policy_action(0.0)
	_expect(is_equal_approx(neutral_command, DroneSACActorCritic.HOVER_COMMAND), "zero residual maps one rotor to hover")
	var raw_actions = PackedFloat64Array([0.50, 0.0, 0.0, 0.0])
	var raw_commands = PackedFloat64Array()
	for action in raw_actions:
		raw_commands.append(actor_critic._command_from_policy_action(action))
	_expect(raw_commands[0] > DroneSACActorCritic.HOVER_COMMAND, "positive rotor-0 action raises rotor 0")
	for index in range(1, raw_commands.size()):
		_expect(is_equal_approx(raw_commands[index], DroneSACActorCritic.HOVER_COMMAND), "rotor-0 action does not alter another rotor")
	var independent_commands = PackedFloat64Array([0.61, 0.73, 0.82, 0.68])
	var memory = DroneSACNavigationMemory.new().features_for(3, observation)
	var actor_input = DroneSACObservationEncoder.encode_actor(observation, memory)
	var critic_input = DroneSACObservationEncoder.encode_critic_from_actor(actor_input, observation)
	var external = actor_critic.action_sample_from_commands(
		observation,
		actor_input,
		critic_input,
		independent_commands,
		"raw_contract_test"
	)
	_expect(_arrays_close(external.get("commands", PackedFloat64Array()), independent_commands), "raw motor commands pass through without mixing")
	var policy_actions: PackedFloat64Array = external.get("policy_actions", PackedFloat64Array())
	_expect(policy_actions.size() == DroneSACObservationEncoder.ACTION_COUNT, "replay stores one normalized residual per propeller")
	for index in range(policy_actions.size()):
		_expect(
			is_equal_approx(actor_critic._command_from_policy_action(policy_actions[index]), independent_commands[index]),
			"each replay action reconstructs only its matching propeller command"
		)
	var q_input = DroneSACObservationEncoder.q_input(critic_input, policy_actions)
	_expect(q_input.size() == DroneSACObservationEncoder.Q_INPUT_COUNT, "Q input includes four independent propeller actions")
	for index in range(policy_actions.size()):
		_expect(
			is_equal_approx(q_input[DroneSACObservationEncoder.LEGACY_CRITIC_FEATURE_COUNT + index], policy_actions[index]),
			"Q critics receive the matching raw propeller residual"
		)
	for index in range(DroneSACObservationEncoder.TURRET_THREAT_FEATURE_COUNT):
		_expect(
			is_equal_approx(
				q_input[DroneSACObservationEncoder.LEGACY_Q_INPUT_COUNT + index],
				critic_input[DroneSACObservationEncoder.LEGACY_CRITIC_FEATURE_COUNT + index]
			),
			"Q critics preserve each appended turret feature after the legacy action columns"
		)
	var policy_outputs = PackedFloat64Array([
		0.0, 0.0, 0.0, 0.0,
		DroneSACActorCritic.INITIAL_LOG_STANDARD_DEVIATION,
		DroneSACActorCritic.INITIAL_LOG_STANDARD_DEVIATION,
		DroneSACActorCritic.INITIAL_LOG_STANDARD_DEVIATION,
		DroneSACActorCritic.INITIAL_LOG_STANDARD_DEVIATION,
	])
	var sampled_command_total = 0.0
	var sampled_command_count = 0
	for _sample_index in range(512):
		var policy_sample = actor_critic._policy_sample_from_outputs(
			policy_outputs,
			false
		)
		for command in policy_sample.get("commands", PackedFloat64Array()):
			sampled_command_total += float(command)
			sampled_command_count += 1
	var sampled_mean = sampled_command_total / float(maxi(sampled_command_count, 1))
	_expect(
		absf(sampled_mean - DroneSACActorCritic.HOVER_COMMAND) < 0.015,
		"symmetric per-rotor exploration remains centred close to physical hover"
	)


func _test_state_dependent_exploration(observation: Dictionary) -> void:
	var actor_critic = DroneSACActorCritic.new(1553)
	_expect(
		actor_critic.actor.output_size == DroneSACActorCritic.POLICY_OUTPUT_COUNT,
		"SAC actor exposes one mean and one state-dependent variance output per propeller"
	)
	var precise_outputs = PackedFloat64Array([
		0.1, -0.1, 0.05, -0.05,
		-4.0, -4.0, -4.0, -4.0,
	])
	var exploratory_outputs = PackedFloat64Array([
		0.1, -0.1, 0.05, -0.05,
		-0.5, -0.5, -0.5, -0.5,
	])
	var precise = actor_critic._policy_sample_from_outputs(precise_outputs, true)
	var exploratory = actor_critic._policy_sample_from_outputs(
		exploratory_outputs,
		true
	)
	_expect(
		_arrays_close(
			precise.get("commands", PackedFloat64Array()),
			exploratory.get("commands", PackedFloat64Array())
		),
		"changing exploration spread does not change deterministic raw-propeller commands"
	)
	var precise_deviation: PackedFloat64Array = precise.get(
		"standard_deviations",
		PackedFloat64Array()
	)
	var exploratory_deviation: PackedFloat64Array = exploratory.get(
		"standard_deviations",
		PackedFloat64Array()
	)
	_expect(
		precise_deviation.size() == 4
		and exploratory_deviation.size() == 4
		and exploratory_deviation[0] > precise_deviation[0] * 10.0,
		"each observation can request substantially different exploration strength"
	)
	var memory = DroneSACNavigationMemory.new()
	var actor_input = DroneSACObservationEncoder.encode_actor(
		observation,
		memory.features_for(3, observation)
	)
	var statistics = actor_critic.exploration_statistics_for(actor_input)
	_expect(
		float(statistics.get("minimum", 0.0)) > 0.0
		and float(statistics.get("maximum", 0.0)) <= exp(
			DroneSACActorCritic.MAXIMUM_LOG_STANDARD_DEVIATION
		) + 0.000001,
		"network-produced state-dependent exploration stays finite and clamped"
	)


func _test_structured_warmup(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"warmup_exploration_steps": 64,
		"learning_starts": 64,
		"batch_size": 16,
		"replay_capacity": 128,
	}, 1771)
	var encoded = trainer.encode_observation(observation, 17)
	trainer.warmup_controls[17] = {
		"remaining": 4,
		"collective": 0.73,
		"move_right": 0.04,
		"move_forward": 0.02,
		"yaw": 0.01,
	}
	var first = trainer.sample_action_from_inputs(
		observation,
		encoded["actor_input"],
		encoded["critic_input"],
		17
	)
	var second = trainer.sample_action_from_inputs(
		observation,
		encoded["actor_input"],
		encoded["critic_input"],
		17
	)
	_expect(str(first.get("behavior_source", "")) == "structured_warmup", "early replay uses structured warm-up controls")
	var expected_commands = PackedFloat64Array([0.76, 0.66, 0.78, 0.72])
	_expect(
		_arrays_close(first.get("commands", PackedFloat64Array()), expected_commands),
		"warm-up movement segments are converted to explicit raw motor commands"
	)
	_expect(
		_arrays_close(first.get("commands", PackedFloat64Array()), second.get("commands", PackedFloat64Array())),
		"warm-up control segments are temporally coherent instead of white-noise rotor commands"
	)
	var policy_actions: PackedFloat64Array = first.get("policy_actions", PackedFloat64Array())
	_expect(policy_actions.size() == DroneSACObservationEncoder.ACTION_COUNT, "warm-up replay stores one residual for each raw propeller command")
	for policy_action in policy_actions:
		_expect(policy_action >= -1.0 and policy_action <= 1.0, "warm-up propeller residuals stay normalized")
	trainer.environment_steps = 64
	trainer.update_count = DroneSACTrainer.MINIMUM_CRITIC_UPDATES_BEFORE_POLICY_CONTROL - 1
	var guarded = trainer.sample_action_from_inputs(
		observation, encoded["actor_input"], encoded["critic_input"], 17
	)
	_expect(
		str(guarded.get("behavior_source", "")) == "structured_warmup",
		"the actor cannot take control before enough replay updates have completed"
	)
	trainer.update_count = DroneSACTrainer.MINIMUM_CRITIC_UPDATES_BEFORE_POLICY_CONTROL
	var learned = trainer.sample_action_from_inputs(
		observation, encoded["actor_input"], encoded["critic_input"], 17
	)
	_expect(
		str(learned.get("behavior_source", "")) == "policy",
		"the initialized actor takes live control after replay warm-up and critic bootstrap"
	)
	_expect(
		not trainer._actor_updates_enabled(),
		"actor optimization remains frozen when policy control has only just begun"
	)
	trainer.policy_environment_steps_since_replay_reset = (
		DroneSACTrainer.MINIMUM_POLICY_TRANSITIONS_BEFORE_ACTOR_UPDATES
	)
	_expect(
		trainer._actor_updates_enabled(),
		"actor optimization starts only after the live policy has populated replay with its own transitions"
	)

	var low_observation: Dictionary = observation.duplicate(true)
	var low_environment: Dictionary = low_observation.get("environment", {}).duplicate(true)
	low_environment["ground_clearance_m"] = 0.6
	low_observation["environment"] = low_environment
	var high_observation: Dictionary = observation.duplicate(true)
	var high_environment: Dictionary = high_observation.get("environment", {}).duplicate(true)
	high_environment["ground_clearance_m"] = 3.0
	high_observation["environment"] = high_environment
	var warmup_state: Dictionary = {
		"remaining": 4,
		"collective": 0.68,
		"move_right": 0.06,
		"move_forward": 0.04,
		"yaw": 0.03,
	}
	trainer.environment_steps = 0
	trainer.update_count = 0
	trainer.warmup_controls[17] = warmup_state.duplicate(true)
	var low_encoded = trainer.encode_observation(low_observation, 17)
	var low_warmup = trainer.sample_action_from_inputs(
		low_observation, low_encoded["actor_input"], low_encoded["critic_input"], 17
	)
	trainer.warmup_controls[17] = warmup_state.duplicate(true)
	var high_encoded = trainer.encode_observation(high_observation, 17)
	var high_warmup = trainer.sample_action_from_inputs(
		high_observation, high_encoded["actor_input"], high_encoded["critic_input"], 17
	)
	var low_commands: PackedFloat64Array = low_warmup.get("commands", PackedFloat64Array())
	var high_commands: PackedFloat64Array = high_warmup.get("commands", PackedFloat64Array())
	_expect(
		_command_mean(low_commands) > _command_mean(high_commands),
		"structured SAC warm-up adds collective lift near the floor instead of repeatedly demonstrating spawn crashes"
	)
	_expect(
		_command_spread(low_commands) < _command_spread(high_commands),
		"structured SAC warm-up reduces attitude excursions until the drone has safe ground clearance"
	)


func _test_critic_bootstrap_before_actor_learning(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"warmup_exploration_steps": 0,
		"learning_starts": 1,
		"batch_size": 4,
	}, 1772)
	var encoded = trainer.encode_observation(observation, 21)
	var sample = trainer.actor_critic.action_sample_from_commands(
		observation,
		encoded["actor_input"],
		encoded["critic_input"],
		PackedFloat64Array([0.70, 0.72, 0.68, 0.71]),
		"structured_warmup"
	)
	var transition: Dictionary = {
		"actor_input": sample["actor_input"],
		"critic_input": sample["critic_input"],
		"policy_actions": sample["policy_actions"],
		"reward": 0.15,
		"next_actor_input": sample["actor_input"],
		"next_critic_input": sample["critic_input"],
		"done": false,
		"delta_seconds": 0.05,
	}
	var batch: Array = [transition, transition, transition, transition]
	var actor_before: PackedFloat64Array = trainer.actor_critic.actor.parameters.duplicate()
	var q_before: PackedFloat64Array = trainer.actor_critic.q_one.parameters.duplicate()
	var bootstrap_config: Dictionary = trainer.config.duplicate(true)
	bootstrap_config["train_actor"] = false
	var metrics: Dictionary = trainer.actor_critic.train_batches([batch], bootstrap_config)
	_expect(not metrics.is_empty(), "SAC critic-only bootstrap produces optimizer metrics")
	_expect(
		float(metrics.get("critic_loss", 0.0)) > 0.0
		and float(metrics.get("q_one_loss", 0.0)) > 0.0
		and float(metrics.get("q_two_loss", 0.0)) > 0.0
		and float(metrics.get("critic_gradient_norm", 0.0)) > 0.0,
		"critic bootstrap reports real twin-Q loss and gradient activity"
	)
	_expect(
		is_zero_approx(float(metrics.get("actor_update_fraction", -1.0)))
		and _arrays_close(actor_before, trainer.actor_critic.actor.parameters),
		"critic bootstrap leaves the actor parameters untouched"
	)
	_expect(
		not _arrays_close(q_before, trainer.actor_critic.q_one.parameters),
		"critic bootstrap actually changes Q-network parameters"
	)


func _test_exploration_bonus(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"exploration_bonus": 0.01,
		"exploration_cell_cooldown_seconds": 0.2,
		"control_interval_seconds": 0.05,
	}, 1881)
	# Sanitization deliberately enforces a one-second production minimum. Override only in
	# this focused unit test so the cooldown can be exercised without dozens of calls.
	trainer.config["exploration_cell_cooldown_seconds"] = 0.2
	var worker_id = 73
	var cell_a = observation.duplicate(true)
	var cell_a_body: Dictionary = cell_a["body"]
	cell_a_body["position_world"] = Vector3(-1.9, 2.0, 1.1)
	cell_a["body"] = cell_a_body
	var cell_b = observation.duplicate(true)
	var cell_b_body: Dictionary = cell_b["body"]
	cell_b_body["position_world"] = Vector3(0.5, 2.0, 1.0)
	cell_b["body"] = cell_b_body

	_expect(
		is_zero_approx(trainer._exploration_bonus(worker_id, cell_a, cell_a)),
		"remaining inside one fresh cell cannot farm exploration reward"
	)
	_expect(
		trainer._exploration_bonus(worker_id, cell_a, cell_b) > 0.0,
		"entering a genuinely new maze cell earns exploration reward"
	)
	_expect(
		is_zero_approx(trainer._exploration_bonus(worker_id, cell_b, cell_a)),
		"returning immediately to the already registered starting cell earns nothing"
	)
	_expect(
		is_zero_approx(trainer._exploration_bonus(worker_id, cell_a, cell_b)),
		"a short donut loop cannot reward the same destination twice"
	)
	for _index in range(5):
		trainer._exploration_bonus(worker_id, cell_b, cell_b)
	_expect(
		trainer._exploration_bonus(worker_id, cell_b, cell_a) > 0.0,
		"a cell becomes rewardable again only after this drone's cooldown expires"
	)

	var other_worker_id = 74
	_expect(
		trainer._exploration_bonus(other_worker_id, cell_a, cell_b) > 0.0,
		"timed exploration memory is isolated per drone"
	)
	trainer._reset_exploration_memory(worker_id)
	_expect(
		trainer._exploration_bonus(worker_id, cell_a, cell_b) > 0.0,
		"episode-boundary reset makes cells fresh for the next episode"
	)

	var boundary_worker_id = 75
	var boundary_a = cell_a.duplicate(true)
	var boundary_b = cell_b.duplicate(true)
	var boundary_a_objective: Dictionary = boundary_a["objective"]
	var boundary_a_probe: Dictionary = boundary_a_objective["obstacle_probe"]
	boundary_a_probe["arena_boundary_clearance_m"] = 1.5
	boundary_a_objective["obstacle_probe"] = boundary_a_probe
	boundary_a["objective"] = boundary_a_objective
	var boundary_b_objective: Dictionary = boundary_b["objective"]
	var boundary_b_probe: Dictionary = boundary_b_objective["obstacle_probe"]
	boundary_b_probe["arena_boundary_clearance_m"] = 1.0
	boundary_b_objective["obstacle_probe"] = boundary_b_probe
	boundary_b["objective"] = boundary_b_objective
	_expect(
		is_zero_approx(trainer._exploration_bonus(
			boundary_worker_id,
			boundary_a,
			boundary_b
		)),
		"SAC intrinsic novelty cannot pay a drone for exploring into the terminal arena edge"
	)
	var timing_worker_id = 76
	trainer._exploration_bonus(timing_worker_id, cell_a, cell_a, 0.2)
	_expect(
		is_equal_approx(
			float(trainer.exploration_elapsed_seconds.get(timing_worker_id, 0.0)),
			0.2
		),
		"SAC exploration cooldown advances by the real held-action duration instead of nominal control rate"
	)


func _test_boundary_safety_shaping(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"blocked_detour_relief": 1.0,
		"exploration_bonus": 0.0,
	}, 1907)
	var safe_observation = observation.duplicate(true)
	var safe_objective: Dictionary = safe_observation["objective"]
	var safe_probe: Dictionary = safe_objective["obstacle_probe"]
	safe_probe["arena_boundary_clearance_m"] = 8.0
	safe_objective["obstacle_probe"] = safe_probe
	safe_observation["objective"] = safe_objective
	_expect(
		trainer._safe_hindsight_goal(safe_observation),
		"HER accepts an otherwise safe achieved goal with comfortable arena-boundary clearance"
	)

	var boundary_observation = safe_observation.duplicate(true)
	var boundary_objective: Dictionary = boundary_observation["objective"]
	var boundary_probe: Dictionary = boundary_objective["obstacle_probe"]
	boundary_probe["arena_boundary_clearance_m"] = 1.0
	boundary_objective["obstacle_probe"] = boundary_probe
	boundary_observation["objective"] = boundary_objective
	_expect(
		not trainer._safe_hindsight_goal(boundary_observation),
		"HER refuses to relabel a terminal-edge danger state into a desirable achieved goal"
	)

	var low_observation = safe_observation.duplicate(true)
	var low_environment: Dictionary = low_observation.get("environment", {}).duplicate(true)
	low_environment["ground_clearance_m"] = DroneTrainingReward.GROUND_SAFETY_HEIGHT_M - 0.1
	low_observation["environment"] = low_environment
	_expect(
		not trainer._safe_hindsight_goal(low_observation),
		"HER cannot turn the last low-altitude frame before a ground crash into a desirable goal"
	)

	var moved_away = safe_observation.duplicate(true)
	var moved_away_body: Dictionary = moved_away["body"]
	moved_away_body["position_world"] = (
		(safe_observation["body"] as Dictionary).get("position_world", Vector3.ZERO)
		+ Vector3(-0.8, 0.0, 0.0)
	)
	moved_away["body"] = moved_away_body
	_expect(
		trainer._blocked_detour_relief(safe_observation, moved_away) > 0.0,
		"a blocked central route can still receive detour relief while temporarily moving away"
	)

	var boundary_moved_away = moved_away.duplicate(true)
	var boundary_next_objective: Dictionary = boundary_moved_away["objective"]
	var boundary_next_probe: Dictionary = boundary_next_objective["obstacle_probe"]
	boundary_next_probe["arena_boundary_clearance_m"] = 1.0
	boundary_next_objective["obstacle_probe"] = boundary_next_probe
	boundary_moved_away["objective"] = boundary_next_objective
	_expect(
		is_zero_approx(trainer._blocked_detour_relief(
			boundary_observation,
			boundary_moved_away
		)),
		"blocked-detour relief cannot cancel target-away punishment while moving into the arena edge"
	)


func _test_hindsight_reward_identity(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"exploration_bonus": 0.0,
		"blocked_detour_relief": 0.0,
	}, 1931)
	var goal = Vector3(5.0, 2.0, -1.0)
	var old_observation = trainer._relabel_goal(
		_observation(0.1, Vector3.ZERO),
		goal
	)
	var toward_observation = trainer._relabel_goal(
		_observation(0.2, Vector3(0.5, 0.0, -0.1)),
		goal
	)
	var away_observation = trainer._relabel_goal(
		_observation(0.2, Vector3(-0.5, 0.0, 0.1)),
		goal
	)
	var toward_trace = _reward_trace(old_observation, toward_observation, false, false)
	var identity = trainer._relabel_interval_reward(
		toward_trace,
		old_observation,
		toward_observation,
		{
			"position_world": goal,
			"target_radius_m": 0.75,
		}
	)
	_expect(
		bool(identity.get("valid", false))
		and absf(float(identity.get("reward", INF)) - float(toward_trace["original_total"])) <= 0.000000001,
		"HER reproduces the production interval reward when the original goal is substituted"
	)
	var compact_trace = _compact_reward_trace(toward_trace)
	var compact_identity = trainer._relabel_interval_reward(
		compact_trace,
		old_observation,
		toward_observation,
		{
			"position_world": goal,
			"target_radius_m": 0.75,
		}
	)
	_expect(
		bool(compact_identity.get("valid", false))
		and absf(
			float(compact_identity.get("reward", INF))
			- float(compact_trace["original_total"])
		) <= 0.000000001,
		"the compact allocation-light HER trace preserves exact production reward identity"
	)
	var toward = trainer._relabel_interval_reward(
		toward_trace,
		old_observation,
		toward_observation,
		{"position_world": goal, "target_radius_m": 0.75}
	)
	var away_trace = _reward_trace(old_observation, away_observation, false, false)
	var away = trainer._relabel_interval_reward(
		away_trace,
		old_observation,
		away_observation,
		{"position_world": goal, "target_radius_m": 0.75}
	)
	_expect(
		float(toward.get("reward", 0.0)) > float(away.get("reward", 0.0)),
		"HER uses the production approach sign instead of a separate reward formula"
	)
	var success_observation = trainer._relabel_goal(_observation(0.2, goal), goal)
	var continuing = trainer._relabel_interval_reward(
		_reward_trace(old_observation, success_observation, false, false),
		old_observation,
		success_observation,
		{"position_world": goal, "target_radius_m": 0.75}
	)
	_expect(
		not bool(continuing.get("terminated", true)),
		"reaching a substituted hover position does not terminate the continuing live task"
	)
	var crash = trainer._relabel_interval_reward(
		_reward_trace(old_observation, toward_observation, true, false),
		old_observation,
		toward_observation,
		{"position_world": goal, "target_radius_m": 0.75}
	)
	_expect(bool(crash.get("terminated", false)), "a genuine source crash remains terminal after HER relabelling")
	var timeout = trainer._relabel_interval_reward(
		_reward_trace(old_observation, toward_observation, false, true),
		old_observation,
		toward_observation,
		{"position_world": goal, "target_radius_m": 0.75}
	)
	_expect(
		not bool(timeout.get("terminated", true)) and bool(timeout.get("truncated", false)),
		"a source time limit remains bootstrap-eligible truncation after HER relabelling"
	)


func _test_frozen_evaluation_candidate() -> void:
	var trainer = DroneSACTrainer.new({}, 1997)
	trainer.record_completed_episode(1.0)
	var first_candidate: Dictionary = trainer.pending_evaluation_candidate()
	var first_id: int = int(first_candidate.get("candidate_id", -1))
	var first_hash: String = str(first_candidate.get("candidate_hash", ""))
	_expect(
		first_id >= 0 and not first_hash.is_empty(),
		"a strong SAC episode freezes one deterministic evaluation candidate"
	)
	trainer.record_completed_episode(100.0)
	var still_frozen: Dictionary = trainer.pending_evaluation_candidate()
	_expect(
		int(still_frozen.get("candidate_id", -1)) == first_id
		and str(still_frozen.get("candidate_hash", "")) == first_hash,
		"continued SAC episodes cannot replace the policy snapshot while fixed-seed evaluation owns it"
	)
	_expect(
		trainer.completed_episode_count() == 2,
		"freezing a SAC candidate does not stop ordinary episode accounting"
	)
	var tampered_checkpoint: Dictionary = trainer.to_checkpoint().duplicate(true)
	var tampered_training: Dictionary = (tampered_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var tampered_network: Dictionary = (tampered_training.get("candidate_network_state", {}) as Dictionary).duplicate(true)
	tampered_network["action_rng_state"] = int(tampered_network.get("action_rng_state", 0)) + 1
	tampered_training["candidate_network_state"] = tampered_network
	tampered_checkpoint["training"] = tampered_training
	var tampered_restore = DroneSACTrainer.new({}, 1998)
	_expect(
		tampered_restore.load_checkpoint(tampered_checkpoint)
		and tampered_restore.pending_evaluation_candidate().is_empty()
		and not is_finite(tampered_restore.best_episode_mean_reward),
		"SAC restore discards a pending candidate whose network no longer matches its frozen evaluation hash"
	)
	var malformed_candidate_checkpoint: Dictionary = trainer.to_checkpoint().duplicate(true)
	var malformed_training: Dictionary = (malformed_candidate_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var malformed_pending: Dictionary = (malformed_training.get("pending_evaluation_candidate", {}) as Dictionary).duplicate(true)
	malformed_pending["evaluation_plan"] = "broken"
	malformed_training["pending_evaluation_candidate"] = malformed_pending
	malformed_candidate_checkpoint["training"] = malformed_training
	var malformed_restore = DroneSACTrainer.new({}, 1999)
	_expect(
		malformed_restore.load_checkpoint(malformed_candidate_checkpoint)
		and malformed_restore.pending_evaluation_candidate().is_empty(),
		"SAC restore treats malformed nested Candidate metadata as disposable derived state"
	)
	var malformed_id_checkpoint: Dictionary = trainer.to_checkpoint().duplicate(true)
	var malformed_id_training: Dictionary = (malformed_id_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var malformed_id_pending: Dictionary = (malformed_id_training.get("pending_evaluation_candidate", {}) as Dictionary).duplicate(true)
	malformed_id_pending["candidate_id"] = "broken"
	malformed_id_training["pending_evaluation_candidate"] = malformed_id_pending
	malformed_id_checkpoint["training"] = malformed_id_training
	var malformed_id_restore: DroneSACTrainer = DroneSACTrainer.new({}, 2000)
	_expect(
		malformed_id_restore.load_checkpoint(malformed_id_checkpoint)
		and malformed_id_restore.pending_evaluation_candidate().is_empty()
		and malformed_id_restore.pending_evaluation_candidate_id() == -1,
		"SAC restore discards a pending Candidate with a malformed identity before evaluator scheduling"
	)
	_expect(
		trainer.discard_pending_evaluation_candidate(first_id)
		and trainer.pending_evaluation_candidate().is_empty(),
		"a failed runtime evaluator can explicitly release a frozen SAC candidate instead of leaving the UI pending forever"
	)


func _test_policy_and_checkpoint(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"learning_starts": 4,
		"warmup_exploration_steps": 0,
		"batch_size": 4,
		"replay_capacity": 64,
	}, 2002)
	var encoded = trainer.encode_observation(observation, 1)
	var sample = trainer.sample_action_from_inputs(
		observation,
		encoded["actor_input"],
		encoded["critic_input"]
	)
	var sample_observation: Dictionary = sample.get("observation", {})
	var sample_objective: Dictionary = sample_observation.get("objective", {})
	var sample_probe: Dictionary = sample_objective.get("obstacle_probe", {})
	var live_objective: Dictionary = observation.get("objective", {})
	var live_probe: Dictionary = live_objective.get("obstacle_probe", {})
	var frozen_closing_speed = float(sample_probe.get("closing_speed_mps", 0.0))
	live_probe["closing_speed_mps"] = frozen_closing_speed + 123.0
	_expect(
		is_equal_approx(
			float(sample_probe.get("closing_speed_mps", 0.0)),
			frozen_closing_speed
		),
		"SAC action snapshots isolate the in-place obstacle motion fields without cloning the whole observation"
	)
	live_probe["closing_speed_mps"] = frozen_closing_speed
	var commands: Array = sample.get("action", {}).get("propeller_commands", [])
	_expect(commands.size() == 4, "SAC emits one command for every rotor")
	for index in range(commands.size()):
		var value = float((commands[index] as Dictionary).get("command", -1.0))
		_expect(value >= 0.0 and value <= 1.0, "SAC motor commands stay normalized")
	var checkpoint = trainer.to_checkpoint()
	var network: Dictionary = checkpoint.get("network", {})
	var atomic_network = DroneSACActorCritic.new(2003)
	var actor_before_failed_load: PackedFloat64Array = atomic_network.actor.parameters.duplicate()
	var corrupt_network: Dictionary = network.duplicate(true)
	var corrupt_q_two: Dictionary = (corrupt_network.get("q_two", {}) as Dictionary).duplicate(true)
	var corrupt_q_parameters: Array = (corrupt_q_two.get("parameters", []) as Array).duplicate()
	corrupt_q_parameters[0] = NAN
	corrupt_q_two["parameters"] = corrupt_q_parameters
	corrupt_network["q_two"] = corrupt_q_two
	_expect(
		not atomic_network.load_state(corrupt_network)
		and _arrays_close(actor_before_failed_load, atomic_network.actor.parameters),
		"a corrupt SAC critic cannot partially replace the live actor"
	)
	var malformed_network_metadata: Dictionary = network.duplicate(true)
	malformed_network_metadata["action_count"] = {"broken": true}
	_expect(
		not atomic_network.load_state(malformed_network_metadata),
		"SAC network restore rejects wrong-type numeric metadata without throwing"
	)
	var malformed_q_shape: Dictionary = network.duplicate(true)
	malformed_q_shape["q_one"] = "broken"
	_expect(
		not atomic_network.load_state(malformed_q_shape),
		"SAC network restore rejects wrong-type nested critic state without throwing"
	)
	var malformed_alpha_state: Dictionary = network.duplicate(true)
	var malformed_alpha: Dictionary = (
		malformed_alpha_state.get("entropy_temperature_state", {}) as Dictionary
	).duplicate(true)
	malformed_alpha["optimizer_step"] = {"broken": true}
	malformed_alpha_state["entropy_temperature_state"] = malformed_alpha
	_expect(
		not atomic_network.load_state(malformed_alpha_state),
		"SAC network restore rejects malformed entropy optimizer metadata"
	)
	_expect(
		str(network.get("action_semantics", "")) == DroneSACActorCritic.ACTION_SEMANTICS,
		"SAC checkpoints identify their raw propeller action contract"
	)
	_expect(
		str(network.get("policy_distribution_semantics", ""))
		== DroneSACActorCritic.POLICY_DISTRIBUTION_SEMANTICS
		and int(network.get("policy_output_count", 0))
		== DroneSACActorCritic.POLICY_OUTPUT_COUNT,
		"SAC checkpoints identify the observation-dependent exploration contract"
	)
	var inspection = DroneTrainingAlgorithmCatalog.inspect_checkpoint(checkpoint)
	_expect(
		bool(inspection.get("compatible", false))
		and bool(inspection.get("trainable", false)),
		"fresh SAC checkpoints remain both evaluator-compatible and trainable"
	)
	var wrong_width_checkpoint = checkpoint.duplicate(true)
	var wrong_width_network: Dictionary = wrong_width_checkpoint.get(
		"network",
		{}
	).duplicate(true)
	wrong_width_network["hidden_size"] = 64
	wrong_width_checkpoint["network"] = wrong_width_network
	_expect(
		not bool(DroneTrainingAlgorithmCatalog.inspect_checkpoint(
			wrong_width_checkpoint
		).get("compatible", true)),
		"the checkpoint inspector rejects inconsistent top-level versus nested SAC architecture metadata"
	)
	var model = DroneTrainingAlgorithmCatalog.create_runtime_model(checkpoint)
	_expect(model is DroneSACModel, "SAC checkpoint creates its runtime model")
	_expect(not model.predict_action(observation).is_empty(), "runtime SAC model produces deterministic actions")
	var degraded_observation = observation.duplicate(true)
	var degraded_propellers: Array = degraded_observation["propellers"]
	var missing_propeller: Dictionary = degraded_propellers[0]
	missing_propeller["installed"] = false
	missing_propeller["realized_thrust_n"] = 0.0
	missing_propeller["maximum_static_thrust_n"] = 0.0
	var degraded_runtime_action: Dictionary = model.predict_action(degraded_observation)
	_expect(
		(degraded_runtime_action.get("propeller_commands", []) as Array).size() == 4,
		"runtime SAC keeps commanding all four stable slots when one propeller is missing"
	)
	var sac_model = model as DroneSACModel
	_expect(
		sac_model != null and not sac_model.navigation_memory.memories.is_empty(),
		"runtime SAC inference records episode-local navigation memory"
	)
	if sac_model != null:
		sac_model.reset_episode_state(2002)
	_expect(
		sac_model != null and sac_model.navigation_memory.memories.is_empty(),
		"runtime SAC episode reset clears navigation memory before deterministic evaluation or respawn"
	)
	var stale_checkpoint = checkpoint.duplicate(true)
	var stale_network: Dictionary = stale_checkpoint.get("network", {}).duplicate(true)
	stale_network.erase("action_semantics")
	stale_checkpoint["network"] = stale_network
	_expect(
		not bool(DroneTrainingAlgorithmCatalog.inspect_checkpoint(stale_checkpoint).get("compatible", true)),
		"checkpoints without the raw-propeller action contract are rejected"
	)
	var global_noise_checkpoint = checkpoint.duplicate(true)
	var global_noise_network: Dictionary = global_noise_checkpoint.get(
		"network",
		{}
	).duplicate(true)
	global_noise_network.erase("policy_distribution_semantics")
	global_noise_checkpoint["network"] = global_noise_network
	_expect(
		not bool(DroneTrainingAlgorithmCatalog.inspect_checkpoint(
			global_noise_checkpoint
		).get("compatible", true)),
		"old global-noise SAC checkpoints cannot be misread as state-dependent actors"
	)


func _test_transition_validation_and_atomic_full_restore(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"learning_starts": 4,
		"warmup_exploration_steps": 0,
		"batch_size": 4,
		"replay_capacity": 64,
		"hindsight_goals_per_transition": 0,
	}, 2301)
	var encoded = trainer.encode_observation(observation, 17)
	var sample = trainer.sample_action_from_inputs(
		observation,
		encoded["actor_input"],
		encoded["critic_input"],
		17
	)
	_expect(
		not trainer.add_transition(
			17,
			sample,
			0.0,
			observation,
			false,
			false,
			encoded["critic_input"],
			NAN,
			{"delta_seconds": NAN}
		),
		"SAC rejects a non-finite transition duration before it can poison replay"
	)
	_expect(
		not trainer.add_transition(
			17,
			sample,
			0.0,
			observation,
			false,
			false,
			encoded["critic_input"],
			NAN,
			{"delta_seconds": ["broken"]}
		),
		"SAC rejects wrong-type transition duration metadata without a numeric cast failure"
	)
	_expect(
		not trainer.add_transition(
			17,
			sample,
			0.0,
			observation,
			true,
			true,
			encoded["critic_input"],
			NAN,
			{"delta_seconds": 0.05}
		),
		"SAC rejects contradictory terminated-and-truncated boundaries"
	)
	var terminal_sample = trainer.sample_action_from_inputs(
		observation,
		encoded["actor_input"],
		encoded["critic_input"],
		18
	)
	_expect(
		trainer.add_transition(
			18,
			terminal_sample,
			-1.0,
			{},
			true,
			false,
			PackedFloat64Array(),
			NAN,
			{"delta_seconds": 0.05}
		),
		"SAC preserves a true terminal transition without fabricating a successor state"
	)
	var terminal_transition: Dictionary = trainer.replay_buffer[trainer.replay_buffer.size() - 1]
	var stored_next_actor: PackedFloat64Array = terminal_transition.get(
		"next_actor_input",
		PackedFloat64Array()
	)
	var stored_next_critic: PackedFloat64Array = terminal_transition.get(
		"next_critic_input",
		PackedFloat64Array()
	)
	_expect(
		stored_next_actor.is_empty()
		and stored_next_critic.is_empty()
		and trainer.actor_critic._valid_training_transition(terminal_transition),
		"SAC optimizer validation accepts an omitted successor only on a true terminal boundary"
	)
	var terminal_network = DroneSACActorCritic.new(23015)
	var terminal_metrics: Dictionary = terminal_network._train_batch(
		[terminal_transition],
		trainer.config
	)
	_expect(
		not terminal_metrics.is_empty(),
		"SAC critic can train the terminal failure signal without evaluating a successor policy or target Q"
	)

	var live = DroneSACTrainer.new({
		"learning_starts": 4,
		"warmup_exploration_steps": 0,
		"batch_size": 4,
		"replay_capacity": 64,
	}, 2302)
	var source = DroneSACTrainer.new({
		"learning_starts": 8,
		"warmup_exploration_steps": 0,
		"batch_size": 4,
		"replay_capacity": 128,
	}, 2303)
	var source_encoded = source.encode_observation(observation, 23)
	var source_sample = source.sample_action_from_inputs(
		observation,
		source_encoded["actor_input"],
		source_encoded["critic_input"],
		23
	)
	_expect(
		source.add_transition(
			23, source_sample, 0.1, observation, false, false,
			source_encoded["critic_input"], NAN, {"delta_seconds": 0.05}
		),
		"SAC creates a valid replay transition for checkpoint-corruption tests"
	)
	var contradictory_done: Dictionary = source.to_training_checkpoint().duplicate(true)
	var contradictory_state: Dictionary = (
		contradictory_done.get("training_state", {}) as Dictionary
	).duplicate(true)
	var decoded_replay: Array = RLTrainingVariantCodec.decode(
		contradictory_state.get("replay_buffer", [])
	)
	var mismatched_transition: Dictionary = (decoded_replay[0] as Dictionary).duplicate(true)
	mismatched_transition["terminated"] = true
	mismatched_transition["done"] = false
	contradictory_state["replay_buffer"] = RLTrainingVariantCodec.encode([mismatched_transition])
	contradictory_done["training_state"] = contradictory_state
	_expect(
		not live.load_training_checkpoint(contradictory_done)
		and not live.actor_critic._valid_training_transition(mismatched_transition),
		"SAC rejects replay whose done flag disagrees with the terminal boundary at restore and optimizer boundaries"
	)

	var wrong_tensor_checkpoint: Dictionary = source.to_training_checkpoint().duplicate(true)
	var wrong_tensor_state: Dictionary = (wrong_tensor_checkpoint.get("training_state", {}) as Dictionary).duplicate(true)
	var wrong_tensor_replay: Array = RLTrainingVariantCodec.decode(wrong_tensor_state.get("replay_buffer", []))
	var wrong_tensor_transition: Dictionary = (wrong_tensor_replay[0] as Dictionary).duplicate(true)
	wrong_tensor_transition["actor_input"] = {"wrong": true}
	wrong_tensor_state["replay_buffer"] = RLTrainingVariantCodec.encode([wrong_tensor_transition])
	wrong_tensor_checkpoint["training_state"] = wrong_tensor_state
	_expect(
		not live.load_training_checkpoint(wrong_tensor_checkpoint),
		"SAC full restore rejects a wrong-type replay tensor before typed tensor access can fail"
	)

	var wrong_logical_id_checkpoint: Dictionary = source.to_training_checkpoint().duplicate(true)
	var wrong_logical_id_state: Dictionary = (wrong_logical_id_checkpoint.get("training_state", {}) as Dictionary).duplicate(true)
	var wrong_logical_id_replay: Array = RLTrainingVariantCodec.decode(wrong_logical_id_state.get("replay_buffer", []))
	var wrong_logical_id_transition: Dictionary = (wrong_logical_id_replay[0] as Dictionary).duplicate(true)
	wrong_logical_id_transition["logical_transition_id"] = "broken"
	wrong_logical_id_state["replay_buffer"] = RLTrainingVariantCodec.encode([wrong_logical_id_transition])
	wrong_logical_id_checkpoint["training_state"] = wrong_logical_id_state
	_expect(
		not live.load_training_checkpoint(wrong_logical_id_checkpoint),
		"SAC full restore validates replay logical IDs before committing trainer state"
	)

	# Full checkpoints intentionally resume durable replay/optimizer state only. Worker-local
	# episode memory belongs to a physics-world snapshot that is not serialized.
	source.episode_transitions[23] = [{"stale": true}]
	source.warmup_controls[23] = {"remaining": 5, "collective": 0.7}
	source.exploration_elapsed_seconds[23] = 9.0
	source.exploration_cell_last_visit_seconds[23] = {"0:0": 9.0}
	source.navigation_memory.features_for(23, observation)
	var durable_checkpoint: Dictionary = source.to_training_checkpoint()
	var durable_state: Dictionary = durable_checkpoint.get("training_state", {})
	var durable_restore = DroneSACTrainer.new({}, 2304)
	_expect(
		not durable_state.has("episode_transitions")
		and not durable_state.has("navigation_memory")
		and not durable_state.has("warmup_controls")
		and not durable_state.has("exploration_elapsed_seconds")
		and durable_restore.load_training_checkpoint(durable_checkpoint)
		and durable_restore.episode_transitions.is_empty()
		and durable_restore.warmup_controls.is_empty()
		and durable_restore.exploration_elapsed_seconds.is_empty()
		and durable_restore.navigation_memory.memories.is_empty(),
		"full SAC resume never attaches stale worker-local episode state to fresh bodies"
	)
	var corrupt_full: Dictionary = source.to_training_checkpoint().duplicate(true)
	var corrupt_training_state: Dictionary = (
		corrupt_full.get("training_state", {}) as Dictionary
	).duplicate(true)
	corrupt_training_state["replay_buffer"] = RLTrainingVariantCodec.encode([
		{"invalid_transition": true},
	])
	corrupt_full["training_state"] = corrupt_training_state
	var live_actor_before: PackedFloat64Array = live.actor_critic.actor.parameters.duplicate()
	var live_capacity_before: int = int(live.config.get("replay_capacity", 0))
	var malformed_config: Dictionary = live.to_checkpoint().duplicate(true)
	malformed_config["config"] = 17
	_expect(
		not live.load_checkpoint(malformed_config)
		and _arrays_close(live_actor_before, live.actor_critic.actor.parameters)
		and int(live.config.get("replay_capacity", 0)) == live_capacity_before,
		"SAC rejects malformed checkpoint container shapes without mutating live state"
	)
	_expect(
		not live.load_training_checkpoint(corrupt_full)
		and _arrays_close(live_actor_before, live.actor_critic.actor.parameters)
		and int(live.config.get("replay_capacity", 0)) == live_capacity_before,
		"a corrupt full SAC replay cannot commit a different network or config before restore fails"
	)
	var malformed_full_metadata: Dictionary = source.to_training_checkpoint().duplicate(true)
	var malformed_full_state: Dictionary = (
		malformed_full_metadata.get("training_state", {}) as Dictionary
	).duplicate(true)
	malformed_full_state["schema_version"] = {"broken": true}
	malformed_full_metadata["training_state"] = malformed_full_state
	_expect(
		not live.load_training_checkpoint(malformed_full_metadata)
		and _arrays_close(live_actor_before, live.actor_critic.actor.parameters),
		"full SAC restore rejects wrong-type continuation schema metadata before mutating live state"
	)
	var malformed_write_index: Dictionary = source.to_training_checkpoint().duplicate(true)
	var malformed_write_state: Dictionary = (
		malformed_write_index.get("training_state", {}) as Dictionary
	).duplicate(true)
	malformed_write_state["replay_write_index"] = [0]
	malformed_write_index["training_state"] = malformed_write_state
	_expect(
		not live.load_training_checkpoint(malformed_write_index)
		and _arrays_close(live_actor_before, live.actor_critic.actor.parameters),
		"full SAC restore rejects wrong-type replay-ring metadata before mutating live state"
	)


func _test_legacy_global_exploration_migration(_observation: Dictionary) -> void:
	var legacy_actor = DronePPOMLP.new(
		DroneSACObservationEncoder.ACTOR_FEATURE_COUNT,
		DroneSACActorCritic.HIDDEN_SIZE,
		DroneSACObservationEncoder.ACTION_COUNT,
		2441,
		0.01,
		0.0
	)
	var legacy_network_source = DroneSACActorCritic.new(2442)
	var legacy_network = {
		"schema_version": DroneSACActorCritic.LEGACY_GLOBAL_VARIANCE_STATE_SCHEMA_VERSION,
		"observation_schema_version": DroneSACObservationEncoder.SCHEMA_VERSION,
		"action_count": DroneSACObservationEncoder.ACTION_COUNT,
		"action_semantics": DroneSACActorCritic.ACTION_SEMANTICS,
		"hidden_size": DroneSACActorCritic.HIDDEN_SIZE,
		"actor": legacy_actor.to_state(),
		"q_one": legacy_network_source.q_one.to_state(),
		"q_two": legacy_network_source.q_two.to_state(),
		"target_q_one": legacy_network_source.target_q_one.to_state(),
		"target_q_two": legacy_network_source.target_q_two.to_state(),
	}
	var legacy_trainer_seed = DroneSACTrainer.new({}, 2443)
	var legacy_checkpoint = legacy_trainer_seed.to_checkpoint()
	legacy_checkpoint["schema_version"] = DroneSACTrainer.LEGACY_GLOBAL_VARIANCE_CHECKPOINT_SCHEMA_VERSION
	legacy_checkpoint["network"] = legacy_network
	var inspection = DroneTrainingAlgorithmCatalog.inspect_checkpoint(legacy_checkpoint)
	_expect(
		not bool(inspection.get("compatible", true))
		and not DroneSACTrainer.new({}, 2444).load_checkpoint(legacy_checkpoint),
		"obsolete SAC policy architectures are deliberately rejected instead of migrated"
	)
	var custom = DroneSACTrainer.new({
		"hidden_layer_width": 160,
		"hidden_layer_depth": 3,
	}, 2445)
	var custom_checkpoint = custom.to_checkpoint()
	var restored = DroneSACTrainer.new({}, 2446)
	_expect(
		bool(DroneTrainingAlgorithmCatalog.inspect_checkpoint(custom_checkpoint).get("compatible", false))
		and restored.load_checkpoint(custom_checkpoint)
		and restored.actor_critic.hidden_size == 160
		and restored.actor_critic.hidden_layer_count == 3,
		"custom SAC hidden width/depth survive checkpoint inspection and restore"
	)


func _test_replay_and_hindsight(observation: Dictionary) -> void:
	var trainer = DroneSACTrainer.new({
		"learning_starts": 4,
		"warmup_exploration_steps": 0,
		"batch_size": 4,
		"replay_capacity": 128,
		"hindsight_goals_per_transition": 1,
		"gradient_steps_per_update": 1,
		"update_interval_transitions": 1,
	}, 3003)
	var worker_id = 9
	for index in range(4):
		var current = _observation(
			float(index) / 4.0,
			Vector3(-2.0 + float(index), 2.0, 1.0)
		)
		var next = _observation(
			float(index + 1) / 4.0,
			Vector3(-1.0 + float(index), 2.0, 1.0)
		)
		var encoded = trainer.encode_observation(current, worker_id)
		var next_encoded = trainer.encode_observation(next, worker_id)
		var sample = trainer.sample_action_from_inputs(
			current,
			encoded["actor_input"],
			encoded["critic_input"],
			worker_id
		)
		var reward_trace = _reward_trace(current, next, index == 3, false)
		_expect(trainer.add_transition(
			worker_id,
			sample,
			float(reward_trace["original_total"]),
			next,
			index == 3,
			false,
			next_encoded["critic_input"],
			NAN,
			reward_trace
		), "SAC accepts a valid production-traced replay transition")
	_expect(trainer.replay_buffer.size() > 4, "episode completion adds hindsight-relabelled transitions")
	var stored_policy_actions: PackedFloat64Array = trainer.replay_buffer[0].get("policy_actions", PackedFloat64Array())
	_expect(stored_policy_actions.size() == DroneSACObservationEncoder.ACTION_COUNT, "replay stores independent hover-relative propeller actions for original and HER samples")
	_expect(trainer.can_update(), "SAC becomes update-ready after replay warmup")
	var relabelled = trainer._relabel_goal(
		observation,
		Vector3(-2.0, 2.0, -5.0)
	)
	var relabelled_probe: Dictionary = (relabelled.get("objective", {}) as Dictionary).get(
		"obstacle_probe",
		{}
	)
	_expect(bool(relabelled_probe.get("target_path_blocked", false)), "HER rebuilds target blockage from the relabelled goal direction")
	_expect(is_zero_approx(float(relabelled_probe.get("target_wall_top_relative_height_m", 1.0))), "HER does not reuse the original target ray's wall height")
	var batch = trainer._sample_replay_batch(4)
	var before = trainer.actor_critic.actor.parameters.duplicate()
	var metrics = trainer.actor_critic.train_batches([batch], trainer.config)
	_expect(not metrics.is_empty(), "one detached SAC replay update produces metrics")
	_expect(trainer.actor_critic.is_finite_state(), "SAC update leaves every network finite")
	_expect(not _arrays_close(before, trainer.actor_critic.actor.parameters), "SAC replay update changes the actor")


func _test_hindsight_uses_latest_safe_future_before_crash() -> void:
	var trainer = DroneSACTrainer.new({
		"learning_starts": 64,
		"warmup_exploration_steps": 0,
		"batch_size": 4,
		"replay_capacity": 128,
		"hindsight_goals_per_transition": 1,
	}, 3559)
	var worker_id = 41
	for index in range(3):
		var current = _observation(
			float(index) / 3.0,
			Vector3(float(index), 2.0, 0.0)
		)
		var next = _observation(
			float(index + 1) / 3.0,
			Vector3(float(index + 1), 2.0, 0.0)
		)
		if index == 2:
			var unsafe_environment: Dictionary = next.get("environment", {}).duplicate(true)
			unsafe_environment["ground_clearance_m"] = 0.1
			next["environment"] = unsafe_environment
		var encoded = trainer.encode_observation(current, worker_id)
		var next_encoded = trainer.encode_observation(next, worker_id)
		var sample = trainer.sample_action_from_inputs(
			current,
			encoded["actor_input"],
			encoded["critic_input"],
			worker_id
		)
		var reward_trace = _reward_trace(current, next, index == 2, false)
		_expect(trainer.add_transition(
			worker_id,
			sample,
			float(reward_trace["original_total"]),
			next,
			index == 2,
			false,
			next_encoded["critic_input"],
			NAN,
			reward_trace
		), "SAC accepts crash-episode transitions with production reward traces")
	var hindsight_count = 0
	for transition: Dictionary in trainer.replay_buffer:
		if bool(transition.get("hindsight", false)):
			hindsight_count += 1
	_expect(
		hindsight_count > 0,
		"an unsafe final crash state falls back to the latest safe achieved future goal"
	)


func _reward_trace(
	old_observation: Dictionary,
	next_observation: Dictionary,
	terminated: bool,
	truncated: bool
) -> Dictionary:
	var old_body: Dictionary = old_observation.get("body", {})
	var next_body: Dictionary = next_observation.get("body", {})
	var objective: Dictionary = old_observation.get("objective", {})
	var target_position: Vector3 = objective.get("target_position_world", Vector3.ZERO)
	var target_radius = maxf(float(objective.get("target_hover_radius_m", 0.75)), 0.0)
	var component_configuration = {}
	for key in DroneTrainingReward.DEFAULT_COMPONENTS:
		component_configuration[key] = {"enabled": true, "intensity": 1.0}
	var delta_seconds = 0.05
	var goal_terms = DroneTrainingReward.evaluate_goal_terms(
		old_body.get("position_world", Vector3.ZERO),
		next_body.get("position_world", Vector3.ZERO),
		target_position,
		target_radius,
		delta_seconds,
		component_configuration
	)
	var survival_reward = 0.0005
	return {
		"schema_version": 1,
		"goal_schema": "stationary_position_v1",
		"reward_components": component_configuration,
		"delta_seconds": delta_seconds,
		"frames": [{
			"previous_position_world": old_body.get("position_world", Vector3.ZERO),
			"next_position_world": next_body.get("position_world", Vector3.ZERO),
			"target_position_world": target_position,
			"target_radius_m": target_radius,
			"delta_seconds": delta_seconds,
			"survival_reward": survival_reward,
			"ground_safety_reward": 0.0,
			"smoothness_reward": 0.0,
			"action_abuse_reward": 0.0,
			"obstacle_reward": 0.0,
			"turret_safety_reward": 0.0,
		}],
		"terminal_adjustments": {
			"progress_correction": 0.0,
			"failure_penalty": 0.0,
			"timeout_survival_bonus": 0.0,
		},
		"algorithm_shaping": {
			"blocked_detour_relief": 0.0,
			"exploration_bonus": 0.0,
		},
		"source_terminated": terminated,
		"source_truncated": truncated,
		"original_total": float(goal_terms.get("total", 0.0)) + survival_reward,
	}


func _compact_reward_trace(legacy_trace: Dictionary) -> Dictionary:
	var frames: Array = legacy_trace.get("frames", [])
	if frames.is_empty() or not (frames[0] is Dictionary):
		return {}
	var frame: Dictionary = frames[0]
	return {
		"schema_version": 1,
		"goal_schema": "stationary_position_v1",
		"reward_components": legacy_trace.get("reward_components", {}),
		"target_position_world": frame.get("target_position_world", Vector3.ZERO),
		"target_radius_m": float(frame.get("target_radius_m", 0.75)),
		"delta_seconds": float(legacy_trace.get("delta_seconds", 0.05)),
		"frame_previous_positions": PackedVector3Array([
			frame.get("previous_position_world", Vector3.ZERO),
		]),
		"frame_next_positions": PackedVector3Array([
			frame.get("next_position_world", Vector3.ZERO),
		]),
		"frame_delta_seconds": PackedFloat64Array([
			float(frame.get("delta_seconds", 0.0)),
		]),
		"frame_reward_components": PackedFloat64Array([
			float(frame.get("survival_reward", 0.0)),
			float(frame.get("ground_safety_reward", 0.0)),
			float(frame.get("smoothness_reward", 0.0)),
			float(frame.get("action_abuse_reward", 0.0)),
			float(frame.get("obstacle_reward", 0.0)),
			float(frame.get("turret_safety_reward", 0.0)),
		]),
		"terminal_adjustments": legacy_trace.get("terminal_adjustments", {}),
		"algorithm_shaping": legacy_trace.get("algorithm_shaping", {}),
		"source_terminated": bool(legacy_trace.get("source_terminated", false)),
		"source_truncated": bool(legacy_trace.get("source_truncated", false)),
		"original_total": float(legacy_trace.get("original_total", 0.0)),
	}


func _observation(episode_progress: float, position: Vector3) -> Dictionary:
	var propellers: Array[Dictionary] = []
	for index in range(4):
		propellers.append({
			"slot_index": index,
			"realized_thrust_n": 2.0,
			"maximum_static_thrust_n": 4.0,
		})
	return {
		"body": {
			"position_world": position,
			"basis_world": Basis.IDENTITY,
			"inverse_basis_world": Basis.IDENTITY,
			"linear_velocity_local": Vector3(0.2, -0.1, 0.3),
			"linear_velocity_world": Vector3(0.2, -0.1, 0.3),
			"angular_velocity_local": Vector3(0.1, 0.2, -0.1),
		},
		"objective": {
			"target_position_world": Vector3(5.0, 2.0, -1.0),
			"target_velocity_world": Vector3.ZERO,
			"target_hover_radius_m": 0.75,
			"episode_progress": episode_progress,
			"obstacle_probe": {
				"nearest_direction_local": Vector3.LEFT,
				"nearest_direction_yaw_local": Vector3.LEFT,
				"nearest_distance_m": 1.5,
				"maximum_distance_m": 4.0,
				"target_path_blocked": true,
				"sector_clearances_m": PackedFloat64Array([3.0, 4.0, 4.0, 3.0, 2.0, 4.0, 4.0, 3.0]),
				"sector_maximum_distance_m": 4.0,
				"target_path_clearance_m": 1.5,
				"target_path_maximum_distance_m": 4.0,
				"target_wall_top_relative_height_m": 2.0,
				"closing_speed_mps": 0.0,
				"wall_contact": false,
				"arena_boundary_clearance_m": INF,
			},
		},
		"electrical": {
			"available_power_w": 100.0,
		},
		"environment": {"ground_clearance_m": 2.0},
		"parts": {
			"core": {"maximum_power_throughput_w": 120.0},
		},
		"propellers": propellers,
	}


func _lift_torque_from_commands(commands: PackedFloat64Array) -> Vector3:
	var positions = [
		Vector3(-0.58, 0.15, -0.58),
		Vector3(0.58, 0.15, -0.58),
		Vector3(-0.58, 0.15, 0.58),
		Vector3(0.58, 0.15, 0.58),
	]
	var torque = Vector3.ZERO
	for index in range(mini(commands.size(), positions.size())):
		torque += positions[index].cross(Vector3.UP * commands[index])
	return torque


func _reaction_yaw_from_commands(commands: PackedFloat64Array) -> float:
	var spin_directions = PackedFloat64Array([1.0, -1.0, -1.0, 1.0])
	var result = 0.0
	for index in range(mini(commands.size(), spin_directions.size())):
		result += commands[index] * spin_directions[index]
	return result


func _command_mean(commands: PackedFloat64Array) -> float:
	if commands.is_empty():
		return 0.0
	var total = 0.0
	for command in commands:
		total += float(command)
	return total / float(commands.size())


func _command_spread(commands: PackedFloat64Array) -> float:
	if commands.is_empty():
		return 0.0
	var mean = _command_mean(commands)
	var maximum_deviation = 0.0
	for command in commands:
		maximum_deviation = maxf(maximum_deviation, absf(float(command) - mean))
	return maximum_deviation


func _arrays_close(first: PackedFloat64Array, second: PackedFloat64Array) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if not is_equal_approx(first[index], second[index]):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)
