class_name DroneSACActorCritic
extends RefCounted

const STATE_SCHEMA_VERSION = 8
const LEGACY_GLOBAL_VARIANCE_STATE_SCHEMA_VERSION = 4
const ACTION_COUNT = DroneSACObservationEncoder.ACTION_COUNT
const POLICY_OUTPUT_COUNT = ACTION_COUNT * 2
const ACTION_SEMANTICS = "raw_propeller_residual_v1"
const POLICY_DISTRIBUTION_SEMANTICS = "state_dependent_tanh_gaussian_v1"
const HIDDEN_SIZE = 128
const HIDDEN_LAYER_COUNT = 2
const HOVER_COMMAND = 0.70
const HOVER_LOGIT = 0.8472978603872034
const COMMAND_EPSILON = 0.000001
const INITIAL_LOG_STANDARD_DEVIATION = -1.8
const MINIMUM_LOG_STANDARD_DEVIATION = -5.0
const MAXIMUM_LOG_STANDARD_DEVIATION = -0.2
const LOG_TWO_PI = 1.8378770664093453
const JACOBIAN_EPSILON = 0.000001
const ALPHA_ADAM_BETA_ONE = 0.9
const ALPHA_ADAM_BETA_TWO = 0.999
const ALPHA_ADAM_EPSILON = 0.00000001
const MINIMUM_LOG_ALPHA = -12.0
const MAXIMUM_LOG_ALPHA = 2.0
var actor: DronePPOMLP
var hidden_size: int = HIDDEN_SIZE
var hidden_layer_count: int = HIDDEN_LAYER_COUNT
var q_one: DronePPOMLP
var q_two: DronePPOMLP
var target_q_one: DronePPOMLP
var target_q_two: DronePPOMLP
var action_rng = RandomNumberGenerator.new()
var actor_gradient_workspace = PackedFloat64Array()
var scalar_gradient_workspace = PackedFloat64Array([0.0])
var log_alpha = log(0.002)
var alpha_adam_first_moment = 0.0
var alpha_adam_second_moment = 0.0
var alpha_optimizer_step = 0
var entropy_temperature_state_loaded = false


func _init(
	random_seed: int = 7340033,
	configured_hidden_size: int = HIDDEN_SIZE,
	configured_hidden_layer_count: int = HIDDEN_LAYER_COUNT
) -> void:
	hidden_size = clampi(
		configured_hidden_size,
		DronePPOMLP.MINIMUM_HIDDEN_WIDTH,
		DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
	)
	hidden_layer_count = clampi(
		configured_hidden_layer_count,
		DronePPOMLP.MINIMUM_HIDDEN_DEPTH,
		DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	)
	# Each actor output independently controls the propeller at the same array index,
	# matching PPO's one-output-per-rotor contract. SAC operates on a normalized
	# hover-relative residual per rotor; no collective/translation/yaw mixer is used.
	actor = DronePPOMLP.new(
		DroneSACObservationEncoder.ACTOR_FEATURE_COUNT,
		hidden_size,
		POLICY_OUTPUT_COUNT,
		random_seed,
		0.01,
		0.0,
		hidden_layer_count
	)
	# The actor predicts both the four raw-propeller means and four observation-dependent
	# log standard deviations. Start every variance head at the proven global default.
	for index in range(ACTION_COUNT):
		actor.parameters[actor.output_bias_offset() + ACTION_COUNT + index] = (
			INITIAL_LOG_STANDARD_DEVIATION
		)
	# Small final-layer initialization keeps the bootstrapped Q targets near the
	# actual reward scale instead of beginning from an arbitrary large value landscape.
	q_one = DronePPOMLP.new(
		DroneSACObservationEncoder.Q_INPUT_COUNT,
		hidden_size,
		1,
		random_seed + 1,
		0.1,
		0.0,
		hidden_layer_count
	)
	q_two = DronePPOMLP.new(
		DroneSACObservationEncoder.Q_INPUT_COUNT,
		hidden_size,
		1,
		random_seed + 2,
		0.1,
		0.0,
		hidden_layer_count
	)
	target_q_one = DronePPOMLP.new(
		DroneSACObservationEncoder.Q_INPUT_COUNT,
		hidden_size,
		1,
		random_seed + 3,
		0.1,
		0.0,
		hidden_layer_count
	)
	target_q_two = DronePPOMLP.new(
		DroneSACObservationEncoder.Q_INPUT_COUNT,
		hidden_size,
		1,
		random_seed + 4,
		0.1,
		0.0,
		hidden_layer_count
	)
	target_q_one.copy_from(q_one)
	target_q_two.copy_from(q_two)
	actor_gradient_workspace.resize(POLICY_OUTPUT_COUNT)
	action_rng.seed = random_seed + 5


func sample_action_from_inputs(
	observation: Dictionary,
	actor_input: PackedFloat64Array,
	critic_input: PackedFloat64Array,
	deterministic = false
) -> Dictionary:
	if (
		not DronePPOObservationEncoder.has_valid_quad_topology(observation)
		or not DroneSACObservationEncoder.valid_tensors(actor_input, critic_input)
	):
		return {}
	var policy_sample = _policy_sample(actor_input, deterministic)
	if policy_sample.is_empty():
		return {}
	var commands: PackedFloat64Array = policy_sample["commands"]
	return {
		"action": _action_dictionary(observation, commands),
		# The compact observation still references the controller objective, whose obstacle
		# probe is refreshed in place between geometry samples. Freeze only that mutable path;
		# all other compact snapshot branches were freshly constructed for this decision.
		"observation": _freeze_action_observation(observation),
		"actor_input": actor_input,
		"critic_input": critic_input,
		"latent_action": policy_sample["latent_action"],
		"policy_actions": policy_sample["policy_actions"],
		"commands": commands,
		"noise": policy_sample["noise"],
		"means": policy_sample["means"],
		"log_standard_deviations": policy_sample["log_standard_deviations"],
		"standard_deviations": policy_sample["standard_deviations"],
		"log_probability": policy_sample["log_probability"],
		"deterministic": deterministic,
		"behavior_source": "policy",
	}


func action_sample_from_commands(
	observation: Dictionary,
	actor_input: PackedFloat64Array,
	critic_input: PackedFloat64Array,
	commands: PackedFloat64Array,
	source = "external"
) -> Dictionary:
	if (
		not DronePPOObservationEncoder.has_valid_quad_topology(observation)
		or not DroneSACObservationEncoder.valid_tensors(actor_input, critic_input)
		or commands.size() != ACTION_COUNT
	):
		return {}
	var bounded = PackedFloat64Array()
	var policy_actions = PackedFloat64Array()
	bounded.resize(ACTION_COUNT)
	policy_actions.resize(ACTION_COUNT)
	for index in range(ACTION_COUNT):
		if not is_finite(commands[index]):
			return {}
		bounded[index] = clampf(commands[index], 0.0, 1.0)
		policy_actions[index] = _policy_action_from_command(bounded[index])
	return {
		"action": _action_dictionary(observation, bounded),
		"observation": _freeze_action_observation(observation),
		"actor_input": actor_input,
		"critic_input": critic_input,
		"policy_actions": policy_actions,
		"commands": bounded,
		"deterministic": false,
		"behavior_source": source,
	}


static func _freeze_action_observation(observation: Dictionary) -> Dictionary:
	var frozen = observation.duplicate(false)
	var objective_value: Variant = observation.get("objective", {})
	if not (objective_value is Dictionary):
		return frozen
	var objective: Dictionary = (objective_value as Dictionary).duplicate(false)
	var probe_value: Variant = objective.get("obstacle_probe", {})
	if probe_value is Dictionary:
		# refresh_motion() mutates only top-level probe fields. Packed sector clearances are
		# immutable between full geometry samples, so a shallow probe copy is sufficient.
		objective["obstacle_probe"] = (probe_value as Dictionary).duplicate(false)
	frozen["objective"] = objective
	return frozen


func deterministic_action(
	observation: Dictionary,
	actor_input: PackedFloat64Array
) -> Dictionary:
	if (
		not DronePPOObservationEncoder.has_valid_quad_topology(observation)
		or actor_input.size() != DroneSACObservationEncoder.ACTOR_FEATURE_COUNT
	):
		return {}
	var sample = _policy_sample(actor_input, true)
	if sample.is_empty():
		return {}
	return _action_dictionary(observation, sample["commands"])


func train_batches(batches: Array, config: Dictionary) -> Dictionary:
	var totals = {
		"actor_loss": 0.0,
		"q_one_loss": 0.0,
		"q_two_loss": 0.0,
		"critic_loss": 0.0,
		"entropy": 0.0,
		"actor_gradient_norm": 0.0,
		"critic_gradient_norm": 0.0,
		"mean_target_q": 0.0,
		"mean_q": 0.0,
		"q_one_mean": 0.0,
		"q_two_mean": 0.0,
		"q_disagreement_mean": 0.0,
		"td_error_mean": 0.0,
		"td_error_standard_deviation": 0.0,
		"target_q_standard_deviation": 0.0,
		"command_saturation_fraction_01": 0.0,
		"command_saturation_fraction_05": 0.0,
		"command_saturation_fraction_10": 0.0,
		"non_finite_target_count": 0.0,
		"action_standard_deviation_mean": 0.0,
		"alpha": 0.0,
		"log_alpha": 0.0,
		"policy_entropy_sample": 0.0,
		"target_entropy": 0.0,
		"entropy_error": 0.0,
		"alpha_gradient_norm": 0.0,
		"alpha_clamp_fraction": 0.0,
		"actor_update_fraction": 0.0,
	}
	var minimum_deviation = INF
	var maximum_deviation = 0.0
	var target_minimum = INF
	var target_maximum = -INF
	var completed_batches = 0
	for batch_value in batches:
		if not (batch_value is Array):
			continue
		var batch: Array = batch_value
		if batch.is_empty():
			continue
		var metrics = _train_batch(batch, config)
		if metrics.is_empty():
			return {}
		for key in totals:
			totals[key] = float(totals[key]) + float(metrics.get(key, 0.0))
		minimum_deviation = minf(
			minimum_deviation,
			float(metrics.get("action_standard_deviation_minimum", INF))
		)
		maximum_deviation = maxf(
			maximum_deviation,
			float(metrics.get("action_standard_deviation_maximum", 0.0))
		)
		target_minimum = minf(target_minimum, float(metrics.get("target_q_minimum", INF)))
		target_maximum = maxf(target_maximum, float(metrics.get("target_q_maximum", -INF)))
		completed_batches += 1
	if completed_batches <= 0:
		return {}
	for key in totals:
		totals[key] = float(totals[key]) / float(completed_batches)
	totals["action_standard_deviation_minimum"] = (
		minimum_deviation if is_finite(minimum_deviation) else 0.0
	)
	totals["action_standard_deviation_maximum"] = maximum_deviation
	totals["target_q_minimum"] = target_minimum if is_finite(target_minimum) else 0.0
	totals["target_q_maximum"] = target_maximum if is_finite(target_maximum) else 0.0
	totals["gradient_steps"] = completed_batches
	return totals


func _train_batch(batch: Array, config: Dictionary) -> Dictionary:
	var discount_reference = clampf(float(config.get("discount_factor", 0.995)), 0.0, 1.0)
	var discount_reference_interval = maxf(float(config.get(
		"discount_reference_interval_seconds",
		config.get("control_interval_seconds", 0.05)
	)), 0.000001)
	var automatic_alpha = bool(config.get("automatic_entropy_temperature", false))
	var alpha = (
		exp(log_alpha)
		if automatic_alpha
		else maxf(float(config.get("entropy_temperature", 0.002)), 0.0)
	)
	var learning_rate = maxf(float(config.get("learning_rate", 0.0003)), 0.0000001)
	var maximum_gradient_norm = maxf(float(config.get("maximum_gradient_norm", 1.0)), 0.0)
	var target_tau = clampf(float(config.get("target_update_rate", 0.005)), 0.0, 1.0)
	var train_actor: bool = bool(config.get("train_actor", true))

	# Reject a malformed batch before clearing/applying any optimizer state. Silently skipping
	# entries changes the sampled distribution and can let a non-finite target reach Adam.
	for transition_value in batch:
		if not (transition_value is Dictionary) or not _valid_training_transition(
			transition_value as Dictionary
		):
			return {}

	q_one.clear_gradients()
	q_two.clear_gradients()
	var q_one_loss = 0.0
	var q_two_loss = 0.0
	var target_q_total = 0.0
	var current_q_total = 0.0
	var q_one_values = PackedFloat64Array()
	var q_two_values = PackedFloat64Array()
	var target_values = PackedFloat64Array()
	var td_errors = PackedFloat64Array()
	var q_disagreements = PackedFloat64Array()
	var valid_samples = 0
	for transition_value in batch:
		if not (transition_value is Dictionary):
			continue
		var transition: Dictionary = transition_value
		var critic_input: PackedFloat64Array = transition.get("critic_input", PackedFloat64Array())
		var next_actor_input: PackedFloat64Array = transition.get("next_actor_input", PackedFloat64Array())
		var next_critic_input: PackedFloat64Array = transition.get("next_critic_input", PackedFloat64Array())
		var policy_actions: PackedFloat64Array = transition.get(
			"policy_actions",
			PackedFloat64Array()
		)
		var done: bool = bool(transition.get("done", false))
		if (
			critic_input.size() != DroneSACObservationEncoder.CRITIC_FEATURE_COUNT
			or policy_actions.size() != ACTION_COUNT
			or not DronePPOObservationEncoder.is_normalized_tensor(policy_actions)
		):
			return {}
		var soft_next_value: float = 0.0
		if not done:
			if (
				next_actor_input.size() != DroneSACObservationEncoder.ACTOR_FEATURE_COUNT
				or next_critic_input.size() != DroneSACObservationEncoder.CRITIC_FEATURE_COUNT
			):
				return {}
			var next_policy: Dictionary = _policy_sample(next_actor_input, false)
			if next_policy.is_empty():
				return {}
			var next_q_input: PackedFloat64Array = DroneSACObservationEncoder.q_input(
				next_critic_input,
				next_policy["policy_actions"]
			)
			var target_one_output: PackedFloat64Array = target_q_one.predict_reusable(next_q_input)
			var target_two_output: PackedFloat64Array = target_q_two.predict_reusable(next_q_input)
			if (
				target_one_output.size() != 1
				or target_two_output.size() != 1
				or not is_finite(target_one_output[0])
				or not is_finite(target_two_output[0])
			):
				return {}
			soft_next_value = (
				minf(target_one_output[0], target_two_output[0])
				- alpha * float(next_policy["log_probability"])
			)
		var bootstrap: float = 0.0 if done else 1.0
		var gamma_delta = RLTrainingMath.discount_for_delta(
			discount_reference,
			float(transition.get("delta_seconds", config.get("control_interval_seconds", 0.05))),
			discount_reference_interval
		)
		var target_value = (
			float(transition.get("reward", 0.0))
			+ gamma_delta * bootstrap * soft_next_value
		)
		if not is_finite(target_value):
			return {}
		var current_q_input = DroneSACObservationEncoder.q_input(critic_input, policy_actions)
		var q_one_cache = q_one.forward(current_q_input)
		var q_two_cache = q_two.forward(current_q_input)
		if q_one_cache.is_empty() or q_two_cache.is_empty():
			return {}
		var q_one_output: PackedFloat64Array = q_one_cache["output"]
		var q_two_output: PackedFloat64Array = q_two_cache["output"]
		var q_one_value = float(q_one_output[0])
		var q_two_value = float(q_two_output[0])
		if not is_finite(q_one_value) or not is_finite(q_two_value):
			return {}
		var q_one_difference = q_one_value - target_value
		var q_two_difference = q_two_value - target_value
		scalar_gradient_workspace[0] = q_one_difference
		q_one.backward(q_one_cache, scalar_gradient_workspace)
		scalar_gradient_workspace[0] = q_two_difference
		q_two.backward(q_two_cache, scalar_gradient_workspace)
		q_one_loss += 0.5 * q_one_difference * q_one_difference
		q_two_loss += 0.5 * q_two_difference * q_two_difference
		target_q_total += target_value
		current_q_total += minf(q_one_value, q_two_value)
		q_one_values.append(q_one_value)
		q_two_values.append(q_two_value)
		target_values.append(target_value)
		td_errors.append(0.5 * (absf(q_one_difference) + absf(q_two_difference)))
		q_disagreements.append(absf(q_one_value - q_two_value))
		valid_samples += 1
	if valid_samples <= 0:
		return {}
	var q_one_norm = _apply_mlp_gradients(
		q_one,
		learning_rate,
		valid_samples,
		maximum_gradient_norm
	)
	var q_two_norm = _apply_mlp_gradients(
		q_two,
		learning_rate,
		valid_samples,
		maximum_gradient_norm
	)

	actor.clear_gradients()
	var actor_loss = 0.0
	var entropy_total = 0.0
	var deviation_total = 0.0
	var deviation_minimum = INF
	var deviation_maximum = 0.0
	var deviation_count = 0
	var actor_samples = 0
	var command_count = 0
	var saturation_01 = 0
	var saturation_05 = 0
	var saturation_10 = 0
	var actor_norm = 0.0
	var policy_entropy_sample = 0.0
	var target_entropy = maxf(float(config.get("target_entropy", ACTION_COUNT)), 0.0)
	var entropy_error = 0.0
	var alpha_gradient_norm = 0.0
	var alpha_clamp_fraction = 0.0
	if train_actor:
		for transition_value in batch:
			if not (transition_value is Dictionary):
				continue
			var transition: Dictionary = transition_value
			var actor_input: PackedFloat64Array = transition.get("actor_input", PackedFloat64Array())
			var critic_input: PackedFloat64Array = transition.get("critic_input", PackedFloat64Array())
			if (
				actor_input.size() != DroneSACObservationEncoder.ACTOR_FEATURE_COUNT
				or critic_input.size() != DroneSACObservationEncoder.CRITIC_FEATURE_COUNT
			):
				return {}
			var actor_cache = actor.forward(actor_input)
			if actor_cache.is_empty():
				return {}
			var policy_outputs: PackedFloat64Array = actor_cache["output"]
			var policy_sample = _policy_sample_from_outputs(policy_outputs, false)
			if policy_sample.is_empty():
				return {}
			var policy_actions: PackedFloat64Array = policy_sample["policy_actions"]
			var q_input = DroneSACObservationEncoder.q_input(critic_input, policy_actions)
			var q_one_cache = q_one.forward(q_input)
			var q_two_cache = q_two.forward(q_input)
			if q_one_cache.is_empty() or q_two_cache.is_empty():
				return {}
			var q_one_output: PackedFloat64Array = q_one_cache["output"]
			var q_two_output: PackedFloat64Array = q_two_cache["output"]
			var q_one_value = float(q_one_output[0])
			var q_two_value = float(q_two_output[0])
			var selected_q: DronePPOMLP = q_one if q_one_value <= q_two_value else q_two
			var selected_cache: Dictionary = q_one_cache if q_one_value <= q_two_value else q_two_cache
			scalar_gradient_workspace[0] = 1.0
			var q_input_gradient = selected_q.input_gradient(
				selected_cache,
				scalar_gradient_workspace
			)
			if q_input_gradient.size() != DroneSACObservationEncoder.Q_INPUT_COUNT:
				return {}
			var noise: PackedFloat64Array = policy_sample["noise"]
			var deviations: PackedFloat64Array = policy_sample["standard_deviations"]
			for action_index in range(ACTION_COUNT):
				var policy_action = policy_actions[action_index]
				var latent_to_policy_derivative = maxf(
					1.0 - policy_action * policy_action,
					JACOBIAN_EPSILON
				)
				var q_action_gradient = q_input_gradient[
					DroneSACObservationEncoder.CRITIC_FEATURE_COUNT + action_index
				]
				var entropy_path_gradient = 2.0 * policy_action
				actor_gradient_workspace[action_index] = (
					alpha * entropy_path_gradient
					- q_action_gradient * latent_to_policy_derivative
				)
				var standard_deviation = deviations[action_index]
				var latent_noise_path = standard_deviation * noise[action_index]
				var log_std_gradient = (
					alpha * (-1.0 + entropy_path_gradient * latent_noise_path)
					- q_action_gradient * latent_to_policy_derivative * latent_noise_path
				)
				# The sampled value is hard-clamped, but a raw variance head that crosses a bound
				# must still be able to learn its way back inside. Block only gradients whose Adam
				# descent direction would push it farther out; the opposite direction remains live.
				var raw_log_std = policy_outputs[ACTION_COUNT + action_index]
				var bounded_log_std_gradient = log_std_gradient
				if (
					raw_log_std <= MINIMUM_LOG_STANDARD_DEVIATION
					and log_std_gradient > 0.0
				) or (
					raw_log_std >= MAXIMUM_LOG_STANDARD_DEVIATION
					and log_std_gradient < 0.0
				):
					bounded_log_std_gradient = 0.0
				actor_gradient_workspace[ACTION_COUNT + action_index] = (
					bounded_log_std_gradient
				)
				var command = float((policy_sample["commands"] as PackedFloat64Array)[action_index])
				if not is_finite(command):
					return {}
				var edge_distance = minf(command, 1.0 - command)
				command_count += 1
				if edge_distance <= 0.01:
					saturation_01 += 1
				if edge_distance <= 0.05:
					saturation_05 += 1
				if edge_distance <= 0.10:
					saturation_10 += 1
				deviation_total += standard_deviation
				deviation_minimum = minf(deviation_minimum, standard_deviation)
				deviation_maximum = maxf(deviation_maximum, standard_deviation)
				deviation_count += 1
			actor.backward(actor_cache, actor_gradient_workspace)
			var log_probability = float(policy_sample["log_probability"])
			actor_loss += alpha * log_probability - minf(q_one_value, q_two_value)
			entropy_total += -log_probability
			actor_samples += 1
		if actor_samples <= 0:
			return {}
		actor_norm = _apply_actor_gradients(
			learning_rate,
			actor_samples,
			maximum_gradient_norm
		)
		policy_entropy_sample = entropy_total / float(actor_samples)
		target_entropy = maxf(float(config.get("target_entropy", ACTION_COUNT)), 0.0)
		entropy_error = policy_entropy_sample - target_entropy
		alpha_gradient_norm = 0.0
		alpha_clamp_fraction = 0.0
		if automatic_alpha:
			var alpha_update = _apply_alpha_gradient(
				alpha * entropy_error,
				maxf(float(config.get("entropy_temperature_learning_rate", learning_rate)), 0.0000001)
			)
			alpha_gradient_norm = float(alpha_update.get("gradient_norm", 0.0))
			alpha_clamp_fraction = 1.0 if bool(alpha_update.get("clamped", false)) else 0.0
			alpha = exp(log_alpha)
	target_q_one.soft_update_from(q_one, target_tau)
	target_q_two.soft_update_from(q_two, target_tau)
	var q_one_stats = RLTrainingMath.finite_statistics(q_one_values)
	var q_two_stats = RLTrainingMath.finite_statistics(q_two_values)
	var target_stats = RLTrainingMath.finite_statistics(target_values)
	var td_stats = RLTrainingMath.finite_statistics(td_errors)
	var disagreement_stats = RLTrainingMath.finite_statistics(q_disagreements)
	return {
		"actor_loss": actor_loss / float(maxi(actor_samples, 1)),
		"q_one_loss": q_one_loss / float(valid_samples),
		"q_two_loss": q_two_loss / float(valid_samples),
		"critic_loss": 0.5 * (q_one_loss + q_two_loss) / float(valid_samples),
		"entropy": entropy_total / float(maxi(actor_samples, 1)),
		"actor_gradient_norm": actor_norm,
		"critic_gradient_norm": maxf(q_one_norm, q_two_norm),
		"mean_target_q": target_q_total / float(valid_samples),
		"mean_q": current_q_total / float(valid_samples),
		"q_one_mean": float(q_one_stats.get("mean", 0.0)),
		"q_two_mean": float(q_two_stats.get("mean", 0.0)),
		"q_disagreement_mean": float(disagreement_stats.get("mean", 0.0)),
		"td_error_mean": float(td_stats.get("mean", 0.0)),
		"td_error_standard_deviation": float(td_stats.get("standard_deviation", 0.0)),
		"target_q_standard_deviation": float(target_stats.get("standard_deviation", 0.0)),
		"target_q_minimum": float(target_stats.get("minimum", 0.0)),
		"target_q_maximum": float(target_stats.get("maximum", 0.0)),
		"non_finite_target_count": float(target_stats.get("non_finite_count", 0)),
		"command_saturation_fraction_01": float(saturation_01) / float(maxi(command_count, 1)),
		"command_saturation_fraction_05": float(saturation_05) / float(maxi(command_count, 1)),
		"command_saturation_fraction_10": float(saturation_10) / float(maxi(command_count, 1)),
		"action_standard_deviation_mean": (
			deviation_total / float(maxi(deviation_count, 1))
		),
		"action_standard_deviation_minimum": (
			deviation_minimum if is_finite(deviation_minimum) else 0.0
		),
		"action_standard_deviation_maximum": deviation_maximum,
		"alpha": alpha,
		"log_alpha": log_alpha,
		"policy_entropy_sample": policy_entropy_sample,
		"target_entropy": target_entropy,
		"entropy_error": entropy_error,
		"alpha_gradient_norm": alpha_gradient_norm,
		"alpha_clamp_fraction": alpha_clamp_fraction,
		"actor_update_fraction": 1.0 if train_actor else 0.0,
	}


func _valid_training_transition(transition: Dictionary) -> bool:
	var actor_input: PackedFloat64Array = transition.get("actor_input", PackedFloat64Array())
	var critic_input: PackedFloat64Array = transition.get("critic_input", PackedFloat64Array())
	var next_actor_input: PackedFloat64Array = transition.get("next_actor_input", PackedFloat64Array())
	var next_critic_input: PackedFloat64Array = transition.get("next_critic_input", PackedFloat64Array())
	var policy_actions: PackedFloat64Array = transition.get("policy_actions", PackedFloat64Array())
	var terminated = bool(transition.get("terminated", false))
	var truncated = bool(transition.get("truncated", false))
	var done = bool(transition.get("done", false))
	var omitted_terminal_successor: bool = (
		terminated and next_actor_input.is_empty() and next_critic_input.is_empty()
	)
	if (
		terminated and truncated
		or done != terminated
		or not DroneSACObservationEncoder.valid_tensors(actor_input, critic_input)
		or (
			not omitted_terminal_successor
			and not DroneSACObservationEncoder.valid_tensors(next_actor_input, next_critic_input)
		)
		or policy_actions.size() != ACTION_COUNT
		or not DronePPOObservationEncoder.is_normalized_tensor(policy_actions)
		or not is_finite(float(transition.get("reward", NAN)))
		or not is_finite(float(transition.get("delta_seconds", NAN)))
		or float(transition.get("delta_seconds", 0.0)) <= 0.0
	):
		return false
	return true


func _policy_sample(actor_input: PackedFloat64Array, deterministic: bool) -> Dictionary:
	var policy_outputs = actor.predict_reusable(actor_input)
	return _policy_sample_from_outputs(policy_outputs, deterministic)


func _policy_sample_from_outputs(
	policy_outputs: PackedFloat64Array,
	deterministic: bool
) -> Dictionary:
	if policy_outputs.size() != POLICY_OUTPUT_COUNT:
		return {}
	for output in policy_outputs:
		if not is_finite(output):
			return {}
	var latent_action = PackedFloat64Array()
	var policy_actions = PackedFloat64Array()
	var commands = PackedFloat64Array()
	var noise = PackedFloat64Array()
	var means = PackedFloat64Array()
	var log_standard_deviations = PackedFloat64Array()
	var standard_deviations = PackedFloat64Array()
	latent_action.resize(ACTION_COUNT)
	policy_actions.resize(ACTION_COUNT)
	commands.resize(ACTION_COUNT)
	noise.resize(ACTION_COUNT)
	means.resize(ACTION_COUNT)
	log_standard_deviations.resize(ACTION_COUNT)
	standard_deviations.resize(ACTION_COUNT)
	var log_probability = 0.0
	for index in range(ACTION_COUNT):
		var mean = policy_outputs[index]
		var log_standard_deviation = clampf(
			policy_outputs[ACTION_COUNT + index],
			MINIMUM_LOG_STANDARD_DEVIATION,
			MAXIMUM_LOG_STANDARD_DEVIATION
		)
		var standard_deviation = exp(log_standard_deviation)
		var sample_noise = 0.0 if deterministic else action_rng.randfn()
		var latent = mean + standard_deviation * sample_noise
		var policy_action = tanh(latent)
		var command = _command_from_policy_action(policy_action)
		if (
			not is_finite(mean)
			or not is_finite(log_standard_deviation)
			or not is_finite(standard_deviation)
			or not is_finite(sample_noise)
			or not is_finite(latent)
			or not is_finite(policy_action)
			or not is_finite(command)
		):
			return {}
		means[index] = mean
		log_standard_deviations[index] = log_standard_deviation
		standard_deviations[index] = standard_deviation
		latent_action[index] = latent
		policy_actions[index] = policy_action
		commands[index] = command
		noise[index] = sample_noise
		if not deterministic:
			log_probability += -0.5 * (
				sample_noise * sample_noise
				+ 2.0 * log_standard_deviation
				+ LOG_TWO_PI
			)
			var tanh_jacobian = maxf(
				1.0 - policy_action * policy_action,
				JACOBIAN_EPSILON
			)
			log_probability -= log(tanh_jacobian)
	if not is_finite(log_probability):
		return {}
	return {
		"means": means,
		"log_standard_deviations": log_standard_deviations,
		"standard_deviations": standard_deviations,
		"latent_action": latent_action,
		"policy_actions": policy_actions,
		"commands": commands,
		"noise": noise,
		"log_probability": log_probability,
	}


func _apply_mlp_gradients(
	network: DronePPOMLP,
	learning_rate: float,
	batch_size: int,
	maximum_gradient_norm: float
) -> float:
	network.scale_gradients(1.0 / float(maxi(batch_size, 1)))
	var gradient_norm = sqrt(network.gradient_norm_squared())
	if gradient_norm > maximum_gradient_norm and maximum_gradient_norm > 0.0:
		network.scale_gradients(maximum_gradient_norm / gradient_norm)
	network.apply_adam(learning_rate)
	return gradient_norm


func _apply_actor_gradients(
	learning_rate: float,
	batch_size: int,
	maximum_gradient_norm: float
) -> float:
	actor.scale_gradients(1.0 / float(maxi(batch_size, 1)))
	var gradient_norm = sqrt(actor.gradient_norm_squared())
	if gradient_norm > maximum_gradient_norm and maximum_gradient_norm > 0.0:
		actor.scale_gradients(maximum_gradient_norm / gradient_norm)
	actor.apply_adam(learning_rate)
	return gradient_norm


func configure_entropy_temperature(fixed_alpha: float, force_reset = false) -> void:
	if entropy_temperature_state_loaded and not force_reset:
		return
	log_alpha = clampf(log(maxf(fixed_alpha, exp(MINIMUM_LOG_ALPHA))), MINIMUM_LOG_ALPHA, MAXIMUM_LOG_ALPHA)
	alpha_adam_first_moment = 0.0
	alpha_adam_second_moment = 0.0
	alpha_optimizer_step = 0
	entropy_temperature_state_loaded = true


func entropy_temperature(automatic: bool, fixed_alpha: float) -> float:
	return exp(log_alpha) if automatic else maxf(fixed_alpha, 0.0)


func alpha_direction_probe(entropy_sample: float, target_entropy: float, learning_rate: float) -> Dictionary:
	var previous = log_alpha
	var previous_first = alpha_adam_first_moment
	var previous_second = alpha_adam_second_moment
	var previous_step = alpha_optimizer_step
	var alpha = exp(log_alpha)
	var result = _apply_alpha_gradient(
		alpha * (entropy_sample - target_entropy),
		learning_rate
	)
	result["log_alpha_before"] = previous
	result["log_alpha_after"] = log_alpha
	log_alpha = previous
	alpha_adam_first_moment = previous_first
	alpha_adam_second_moment = previous_second
	alpha_optimizer_step = previous_step
	return result


func _apply_alpha_gradient(gradient: float, learning_rate: float) -> Dictionary:
	if not is_finite(gradient):
		return {"gradient_norm": INF, "clamped": false}
	alpha_optimizer_step += 1
	alpha_adam_first_moment = (
		ALPHA_ADAM_BETA_ONE * alpha_adam_first_moment
		+ (1.0 - ALPHA_ADAM_BETA_ONE) * gradient
	)
	alpha_adam_second_moment = (
		ALPHA_ADAM_BETA_TWO * alpha_adam_second_moment
		+ (1.0 - ALPHA_ADAM_BETA_TWO) * gradient * gradient
	)
	var first_correction = 1.0 - pow(ALPHA_ADAM_BETA_ONE, alpha_optimizer_step)
	var second_correction = 1.0 - pow(ALPHA_ADAM_BETA_TWO, alpha_optimizer_step)
	var corrected_first = alpha_adam_first_moment / maxf(first_correction, 0.000000001)
	var corrected_second = alpha_adam_second_moment / maxf(second_correction, 0.000000001)
	var proposed = log_alpha - learning_rate * corrected_first / (
		sqrt(maxf(corrected_second, 0.0)) + ALPHA_ADAM_EPSILON
	)
	var bounded = clampf(proposed, MINIMUM_LOG_ALPHA, MAXIMUM_LOG_ALPHA)
	var clamped = not is_equal_approx(proposed, bounded)
	log_alpha = bounded
	entropy_temperature_state_loaded = true
	return {"gradient_norm": absf(gradient), "clamped": clamped}


func exploration_statistics_for(actor_input: PackedFloat64Array) -> Dictionary:
	var outputs = actor.predict(actor_input)
	if outputs.size() != POLICY_OUTPUT_COUNT:
		return {"mean": 0.0, "minimum": 0.0, "maximum": 0.0}
	var minimum = INF
	var maximum = 0.0
	var total = 0.0
	for index in range(ACTION_COUNT):
		var deviation = exp(clampf(
			outputs[ACTION_COUNT + index],
			MINIMUM_LOG_STANDARD_DEVIATION,
			MAXIMUM_LOG_STANDARD_DEVIATION
		))
		minimum = minf(minimum, deviation)
		maximum = maxf(maximum, deviation)
		total += deviation
	return {
		"mean": total / float(ACTION_COUNT),
		"minimum": minimum if is_finite(minimum) else 0.0,
		"maximum": maximum,
	}


func copy_from(source: DroneSACActorCritic) -> bool:
	return source != null and load_state(source.to_state(true))


func perturb_weights(relative_strength: float, perturbation_seed: int) -> bool:
	var strength = clampf(relative_strength, 0.0, 0.5)
	if strength <= 0.0:
		return true
	var rng = RandomNumberGenerator.new()
	rng.seed = perturbation_seed
	if not actor.perturb_parameters(rng, strength):
		return false
	# New critics are safer than inheriting a value landscape for a deliberately changed actor.
	q_one = DronePPOMLP.new(
		DroneSACObservationEncoder.Q_INPUT_COUNT,
		hidden_size,
		1,
		perturbation_seed + 1,
		0.1,
		0.0,
		hidden_layer_count
	)
	q_two = DronePPOMLP.new(
		DroneSACObservationEncoder.Q_INPUT_COUNT,
		hidden_size,
		1,
		perturbation_seed + 2,
		0.1,
		0.0,
		hidden_layer_count
	)
	target_q_one.copy_from(q_one)
	target_q_two.copy_from(q_two)
	action_rng.seed = perturbation_seed + 5
	return is_finite_state()


func to_state(runtime_only = false) -> Dictionary:
	var state = {
		"schema_version": STATE_SCHEMA_VERSION,
		"observation_schema_version": DroneSACObservationEncoder.SCHEMA_VERSION,
		"action_count": ACTION_COUNT,
		"action_semantics": ACTION_SEMANTICS,
		"policy_distribution_semantics": POLICY_DISTRIBUTION_SEMANTICS,
		"policy_output_count": POLICY_OUTPUT_COUNT,
		"hidden_size": hidden_size,
		"hidden_layer_count": hidden_layer_count,
		"actor": actor.to_runtime_state() if runtime_only else actor.to_state(),
		"action_rng_state": action_rng.state,
		"entropy_temperature_state": {
			"log_alpha": log_alpha,
			"adam_first_moment": alpha_adam_first_moment,
			"adam_second_moment": alpha_adam_second_moment,
			"optimizer_step": alpha_optimizer_step,
		},
	}
	if not runtime_only:
		state["q_one"] = q_one.to_state()
		state["q_two"] = q_two.to_state()
		state["target_q_one"] = target_q_one.to_state()
		state["target_q_two"] = target_q_two.to_state()
	else:
		state["q_one"] = q_one.to_runtime_state()
		state["q_two"] = q_two.to_runtime_state()
		state["target_q_one"] = target_q_one.to_runtime_state()
		state["target_q_two"] = target_q_two.to_runtime_state()
	return state


func load_state(state: Dictionary) -> bool:
	var loaded_hidden_size: int = RLTrainingMath.finite_int_or(
		state.get("hidden_size", 0),
		-1
	)
	var loaded_hidden_layer_count: int = RLTrainingMath.finite_int_or(
		state.get("hidden_layer_count", 0),
		-1
	)
	if (
		RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1)
		!= STATE_SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(state.get("observation_schema_version", 0), -1)
		!= DroneSACObservationEncoder.SCHEMA_VERSION
		or loaded_hidden_size < DronePPOMLP.MINIMUM_HIDDEN_WIDTH
		or loaded_hidden_size > DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
		or loaded_hidden_layer_count < DronePPOMLP.MINIMUM_HIDDEN_DEPTH
		or loaded_hidden_layer_count > DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	):
		return false
	var staged: DroneSACActorCritic = DroneSACActorCritic.new(
		7340033,
		loaded_hidden_size,
		loaded_hidden_layer_count
	)
	if not staged._load_state_in_place(state) or not staged.is_finite_state():
		return false
	hidden_size = staged.hidden_size
	hidden_layer_count = staged.hidden_layer_count
	actor = staged.actor
	q_one = staged.q_one
	q_two = staged.q_two
	target_q_one = staged.target_q_one
	target_q_two = staged.target_q_two
	action_rng.state = staged.action_rng.state
	log_alpha = staged.log_alpha
	alpha_adam_first_moment = staged.alpha_adam_first_moment
	alpha_adam_second_moment = staged.alpha_adam_second_moment
	alpha_optimizer_step = staged.alpha_optimizer_step
	entropy_temperature_state_loaded = staged.entropy_temperature_state_loaded
	return true


func _load_state_in_place(state: Dictionary) -> bool:
	if (
		RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1)
		!= STATE_SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(state.get("observation_schema_version", 0), -1)
		!= DroneSACObservationEncoder.SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(state.get("action_count", 0), -1) != ACTION_COUNT
		or str(state.get("action_semantics", "")) != ACTION_SEMANTICS
		or str(state.get("policy_distribution_semantics", ""))
		!= POLICY_DISTRIBUTION_SEMANTICS
		or RLTrainingMath.finite_int_or(state.get("policy_output_count", 0), -1)
		!= POLICY_OUTPUT_COUNT
		or RLTrainingMath.finite_int_or(state.get("hidden_size", 0), -1) != hidden_size
		or RLTrainingMath.finite_int_or(state.get("hidden_layer_count", 0), -1)
		!= hidden_layer_count
		or not (state.get("actor", {}) is Dictionary)
		or not (state.get("q_one", {}) is Dictionary)
		or not (state.get("q_two", {}) is Dictionary)
		or not (state.get("target_q_one", {}) is Dictionary)
		or not (state.get("target_q_two", {}) is Dictionary)
	):
		return false
	if (
		not actor.load_state(state.get("actor", {}))
		or not q_one.load_state(state.get("q_one", {}))
		or not q_two.load_state(state.get("q_two", {}))
		or not target_q_one.load_state(state.get("target_q_one", {}))
		or not target_q_two.load_state(state.get("target_q_two", {}))
	):
		return false
	action_rng.state = RLTrainingMath.finite_int_or(
		state.get("action_rng_state", action_rng.state),
		action_rng.state
	)
	if not _load_entropy_temperature_state(state):
		return false
	return is_finite_state()


func _load_entropy_temperature_state(state: Dictionary) -> bool:
	var value: Variant = state.get("entropy_temperature_state", {})
	if not (value is Dictionary) or (value as Dictionary).is_empty():
		entropy_temperature_state_loaded = false
		return true
	var alpha_state: Dictionary = value
	var loaded_log_alpha: float = RLTrainingMath.finite_float_or(
		alpha_state.get("log_alpha", NAN), NAN
	)
	var loaded_first_moment: float = RLTrainingMath.finite_float_or(
		alpha_state.get("adam_first_moment", NAN), NAN
	)
	var loaded_second_moment: float = RLTrainingMath.finite_float_or(
		alpha_state.get("adam_second_moment", NAN), NAN
	)
	var loaded_optimizer_step: int = RLTrainingMath.finite_int_or(
		alpha_state.get("optimizer_step", -1), -1
	)
	if (
		not is_finite(loaded_log_alpha)
		or not is_finite(loaded_first_moment)
		or not is_finite(loaded_second_moment)
		or loaded_second_moment < 0.0
		or loaded_optimizer_step < 0
	):
		return false
	log_alpha = clampf(loaded_log_alpha, MINIMUM_LOG_ALPHA, MAXIMUM_LOG_ALPHA)
	alpha_adam_first_moment = loaded_first_moment
	alpha_adam_second_moment = loaded_second_moment
	alpha_optimizer_step = loaded_optimizer_step
	entropy_temperature_state_loaded = true
	return true


func is_finite_state() -> bool:
	return (
		actor.is_finite_state()
		and q_one.is_finite_state()
		and q_two.is_finite_state()
		and target_q_one.is_finite_state()
		and target_q_two.is_finite_state()
		and is_finite(log_alpha)
		and is_finite(alpha_adam_first_moment)
		and is_finite(alpha_adam_second_moment)
	)


func _action_dictionary(
	observation: Dictionary,
	commands: PackedFloat64Array
) -> Dictionary:
	var propellers: Array = observation.get("propellers", [])
	if propellers.size() != ACTION_COUNT:
		return {}
	var result: Array[Dictionary] = []
	for index in range(ACTION_COUNT):
		var propeller: Dictionary = propellers[index]
		result.append({
			"slot_index": int(propeller.get("slot_index", index)),
			"command": commands[index],
		})
	return {"propeller_commands": result}


func _command_from_policy_action(policy_action: float) -> float:
	# Shift a logistic actuator map so residual zero is exactly the known hover
	# command. Unlike the first piecewise map, symmetric policy noise no longer has
	# a strong downward motor bias merely because there is more range below hover.
	if policy_action <= -1.0:
		return 0.0
	if policy_action >= 1.0:
		return 1.0
	var bounded = clampf(
		policy_action,
		-1.0 + COMMAND_EPSILON,
		1.0 - COMMAND_EPSILON
	)
	var latent = 0.5 * log((1.0 + bounded) / (1.0 - bounded))
	return _sigmoid(HOVER_LOGIT + latent)


func _policy_action_from_command(command: float) -> float:
	if command <= 0.0:
		return -1.0
	if command >= 1.0:
		return 1.0
	var bounded = clampf(command, COMMAND_EPSILON, 1.0 - COMMAND_EPSILON)
	var command_logit = log(bounded / (1.0 - bounded))
	return clampf(tanh(command_logit - HOVER_LOGIT), -1.0, 1.0)


func _sigmoid(value: float) -> float:
	if value >= 0.0:
		return 1.0 / (1.0 + exp(-value))
	var exponential = exp(value)
	return exponential / (1.0 + exponential)


func _packed_array(value: Variant) -> PackedFloat64Array:
	if value is PackedFloat64Array:
		var packed_value: PackedFloat64Array = value
		return packed_value.duplicate()
	var result = PackedFloat64Array()
	if not (value is Array):
		return result
	for item in value:
		if not (item is int or item is float):
			return PackedFloat64Array()
		result.append(float(item))
	return result
