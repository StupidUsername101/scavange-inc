class_name FourLimbPPOActorCritic
extends RefCounted

const STATE_SCHEMA_VERSION = 5
const ACTION_COUNT = FourLimbMLAction.ACTION_COUNT
const HIDDEN_SIZE = 64
const HIDDEN_LAYER_COUNT = 2
const INITIAL_LOG_STANDARD_DEVIATION = -1.4
const MINIMUM_LOG_STANDARD_DEVIATION = -4.5
const MAXIMUM_LOG_STANDARD_DEVIATION = 0.4
const LOG_TWO_PI = 1.8378770664093453
const LOG_TWO_PI_E_HALF = 1.4189385332046727
const ADAM_BETA_ONE = 0.9
const ADAM_BETA_TWO = 0.999
const ADAM_EPSILON = 0.00000001

#######################################################
# PPO actor/critic for the fixed direct-actuator contract. Gaussian latent actions are transformed with
# tanh into [-1, 1]; no premade gait or movement command exists in this policy.
#######################################################

var actor: DronePPOMLP
var critic: DronePPOMLP
var hidden_size: int = HIDDEN_SIZE
var hidden_layer_count: int = HIDDEN_LAYER_COUNT
var log_standard_deviation = PackedFloat64Array()
var log_standard_deviation_gradient = PackedFloat64Array()
var log_standard_deviation_first_moment = PackedFloat64Array()
var log_standard_deviation_second_moment = PackedFloat64Array()
var log_standard_deviation_optimizer_step = 0
var action_rng = RandomNumberGenerator.new()
var mean_gradient_workspace = PackedFloat64Array()
var critic_gradient_workspace = PackedFloat64Array()


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
	_initialize_workspaces()
	actor = DronePPOMLP.new(
		FourLimbMLFeatureEncoder.FEATURE_COUNT,
		hidden_size,
		ACTION_COUNT,
		random_seed,
		0.02,
		0.0,
		hidden_layer_count
	)
	critic = DronePPOMLP.new(
		FourLimbMLFeatureEncoder.FEATURE_COUNT,
		hidden_size,
		1,
		random_seed + 1,
		0.5,
		0.0,
		hidden_layer_count
	)
	action_rng.seed = random_seed + 2


func _initialize_workspaces() -> void:
	log_standard_deviation.resize(ACTION_COUNT)
	log_standard_deviation_gradient.resize(ACTION_COUNT)
	log_standard_deviation_first_moment.resize(ACTION_COUNT)
	log_standard_deviation_second_moment.resize(ACTION_COUNT)
	mean_gradient_workspace.resize(ACTION_COUNT)
	log_standard_deviation.fill(INITIAL_LOG_STANDARD_DEVIATION)
	log_standard_deviation_gradient.fill(0.0)
	log_standard_deviation_first_moment.fill(0.0)
	log_standard_deviation_second_moment.fill(0.0)
	mean_gradient_workspace.fill(0.0)
	critic_gradient_workspace.resize(1)


func sample_action(observation: Dictionary, deterministic: bool = false) -> Dictionary:
	return _sample_action(observation, deterministic, true, false)


func sample_runtime_action(observation: Dictionary, deterministic: bool = false) -> Dictionary:
	return _sample_action(observation, deterministic, false, false)


func sample_validated_runtime_action(
	observation: Dictionary,
	deterministic: bool = false
) -> Dictionary:
	return _sample_action(observation, deterministic, false, true)


func sample_validated_training_action(
	observation: Dictionary,
	deterministic: bool = false
) -> Dictionary:
	# The critic does not influence the physical action. Live training can defer its value prediction
	# until the detached PPO update, where the exact producer-policy critic snapshot is available.
	# This removes one 420->64->64 network pass from every limb control decision on the physics thread.
	var input: PackedFloat64Array = FourLimbMLFeatureEncoder.encode(observation, true)
	return sample_action_from_input(observation, input, deterministic, false, false)


func _sample_action(
	observation: Dictionary,
	deterministic: bool,
	include_action_dictionary: bool,
	assume_validated_snapshot: bool
) -> Dictionary:
	var input = FourLimbMLFeatureEncoder.encode(observation, assume_validated_snapshot)
	return sample_action_from_input(observation, input, deterministic, include_action_dictionary)


func sample_action_from_input(
	observation: Dictionary,
	input: PackedFloat64Array,
	deterministic: bool = false,
	include_action_dictionary: bool = true,
	include_value_prediction: bool = true
) -> Dictionary:
	if not FourLimbMLFeatureEncoder.is_normalized(input):
		return {}
	var mean: PackedFloat64Array = actor.predict_reusable(input)
	var value_output: PackedFloat64Array = PackedFloat64Array()
	if include_value_prediction:
		value_output = critic.predict_reusable(input)
	if mean.size() != ACTION_COUNT or (include_value_prediction and value_output.size() != 1):
		return {}
	var latent_action = PackedFloat64Array()
	var commands = PackedFloat64Array()
	latent_action.resize(ACTION_COUNT)
	commands.resize(ACTION_COUNT)
	for index in range(ACTION_COUNT):
		latent_action[index] = (
			mean[index]
			if deterministic
			else mean[index] + exp(log_standard_deviation[index]) * action_rng.randfn()
		)
		commands[index] = tanh(latent_action[index])
	var result: Dictionary = {
		"actor_input": input,
		"critic_input": input,
		"latent_action": latent_action,
		"commands": commands,
		"log_probability": _gaussian_log_probability(latent_action, mean),
	}
	if include_value_prediction:
		result["value"] = value_output[0]
	else:
		result["critic_value_deferred"] = true
	if include_action_dictionary:
		var action = FourLimbMLAction.from_commands(commands)
		if action.is_empty():
			return {}
		result["action"] = action
		result["deterministic"] = deterministic
		result["observation"] = observation
	return result


func deterministic_action(observation: Dictionary) -> Dictionary:
	# Gameplay/evaluation only needs the actor. Avoid paying for a critic forward pass when no
	# value estimate is consumed. This keeps the shipped model on the same lightweight path as
	# live limb control while preserving sample_action() for callers that explicitly need values.
	var input: PackedFloat64Array = FourLimbMLFeatureEncoder.encode(observation)
	var sample: Dictionary = sample_action_from_input(observation, input, true, true, false)
	return sample.get("action", {}) if not sample.is_empty() else {}


func value_for_observation(observation: Dictionary) -> float:
	var input = FourLimbMLFeatureEncoder.encode(observation)
	return value_from_input(input)


func log_probability_from_input(
	actor_input: PackedFloat64Array,
	latent_action: PackedFloat64Array
) -> float:
	var mean = actor.predict_reusable(actor_input)
	if mean.size() != ACTION_COUNT or latent_action.size() != ACTION_COUNT:
		return NAN
	return _gaussian_log_probability(latent_action, mean)


func value_from_input(input: PackedFloat64Array) -> float:
	if not FourLimbMLFeatureEncoder.is_normalized(input):
		return 0.0
	var output = critic.predict_reusable(input)
	return output[0] if output.size() == 1 else 0.0


func clear_actor_gradients() -> void:
	actor.clear_gradients()
	log_standard_deviation_gradient.fill(0.0)


func clear_critic_gradients() -> void:
	critic.clear_gradients()


func accumulate_actor_gradient(
	actor_input: PackedFloat64Array,
	latent_action: PackedFloat64Array,
	old_log_probability: float,
	advantage: float,
	clip_range: float,
	entropy_coefficient: float
) -> Dictionary:
	var mean = actor.predict_reusable(actor_input, true)
	if mean.size() != ACTION_COUNT or latent_action.size() != ACTION_COUNT:
		return {}
	var new_log_probability = _gaussian_log_probability(latent_action, mean)
	var log_ratio = clampf(new_log_probability - old_log_probability, -20.0, 20.0)
	var ratio = exp(log_ratio)
	var clipped_ratio = clampf(ratio, 1.0 - clip_range, 1.0 + clip_range)
	var unclipped_objective = ratio * advantage
	var clipped_objective = clipped_ratio * advantage
	var objective = minf(unclipped_objective, clipped_objective)
	var clipped = (
		(advantage >= 0.0 and ratio > 1.0 + clip_range)
		or (advantage < 0.0 and ratio < 1.0 - clip_range)
	)
	var loss_log_probability_gradient = 0.0 if clipped else -ratio * advantage
	for index in range(ACTION_COUNT):
		var difference = latent_action[index] - mean[index]
		var inverse_variance = exp(-2.0 * log_standard_deviation[index])
		mean_gradient_workspace[index] = (
			loss_log_probability_gradient * difference * inverse_variance
		)
		log_standard_deviation_gradient[index] += (
			loss_log_probability_gradient
			* (difference * difference * inverse_variance - 1.0)
			- entropy_coefficient
		)
	actor.backward_reusable(mean_gradient_workspace)
	return {
		"actor_loss": -objective - entropy_coefficient * gaussian_entropy(),
		"entropy": gaussian_entropy(),
		"approximate_kl": (ratio - 1.0) - log_ratio,
		"clip_fraction": 1.0 if clipped else 0.0,
	}


func accumulate_critic_gradient(
	critic_input: PackedFloat64Array,
	return_target: float,
	value_coefficient: float
) -> Dictionary:
	var output = critic.predict_reusable(critic_input, true)
	if output.size() != 1:
		return {}
	var difference = output[0] - return_target
	critic_gradient_workspace[0] = value_coefficient * difference
	critic.backward_reusable(critic_gradient_workspace)
	return {
		"value_loss": 0.5 * value_coefficient * difference * difference,
		"value_prediction": output[0],
	}


func apply_actor_gradients(
	learning_rate: float,
	batch_size: int,
	maximum_gradient_norm: float
) -> float:
	var inverse_batch = 1.0 / float(maxi(batch_size, 1))
	actor.scale_gradients(inverse_batch)
	for index in range(ACTION_COUNT):
		log_standard_deviation_gradient[index] *= inverse_batch
	var norm_squared = actor.gradient_norm_squared()
	for gradient in log_standard_deviation_gradient:
		norm_squared += gradient * gradient
	var norm = sqrt(norm_squared)
	if maximum_gradient_norm > 0.0 and norm > maximum_gradient_norm:
		var scale = maximum_gradient_norm / norm
		actor.scale_gradients(scale)
		for index in range(ACTION_COUNT):
			log_standard_deviation_gradient[index] *= scale
	actor.apply_adam(learning_rate)
	_apply_log_standard_deviation_adam(learning_rate)
	return norm


func apply_critic_gradients(
	learning_rate: float,
	batch_size: int,
	maximum_gradient_norm: float
) -> float:
	critic.scale_gradients(1.0 / float(maxi(batch_size, 1)))
	var norm = sqrt(critic.gradient_norm_squared())
	if maximum_gradient_norm > 0.0 and norm > maximum_gradient_norm:
		critic.scale_gradients(maximum_gradient_norm / norm)
	critic.apply_adam(learning_rate)
	return norm


# This is the entropy of the latent diagonal Normal, before sigmoid/tanh squashing.
# PPO likelihood ratios remain consistent because the fixed transform Jacobian cancels
# for the same sampled action, but this metric/regularizer must not be presented as
# physical actuator-space entropy. Keep a transformed-entropy change as an isolated
# learning experiment with explicit Jacobian/Monte-Carlo tests.
func gaussian_entropy() -> float:
	var result = 0.0
	for value in log_standard_deviation:
		result += value + LOG_TWO_PI_E_HALF
	return result


func exploration_statistics() -> Dictionary:
	var minimum = INF
	var maximum = 0.0
	var total = 0.0
	for log_value in log_standard_deviation:
		var deviation = exp(log_value)
		minimum = minf(minimum, deviation)
		maximum = maxf(maximum, deviation)
		total += deviation
	return {
		"mean": total / float(ACTION_COUNT),
		"minimum": minimum if is_finite(minimum) else 0.0,
		"maximum": maximum,
	}


func to_state() -> Dictionary:
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"body_profile_id": FourLimbBodyDefinition.BODY_PROFILE_ID,
		"observation_schema_version": FourLimbMLObservation.SCHEMA_VERSION,
		"action_schema_version": FourLimbMLAction.SCHEMA_VERSION,
		"action_count": ACTION_COUNT,
		"feature_count": FourLimbMLFeatureEncoder.FEATURE_COUNT,
		"hidden_size": hidden_size,
		"hidden_layer_count": hidden_layer_count,
		"actor": actor.to_state(),
		"critic": critic.to_state(),
		"log_standard_deviation": Array(log_standard_deviation),
		"log_standard_deviation_first_moment": Array(log_standard_deviation_first_moment),
		"log_standard_deviation_second_moment": Array(log_standard_deviation_second_moment),
		"log_standard_deviation_optimizer_step": log_standard_deviation_optimizer_step,
	}


func to_runtime_state() -> Dictionary:
	# Keep in-memory optimizer handoffs in packed arrays. Checkpoint serialization still
	# uses to_state(), which preserves the established JSON-compatible schema.
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"body_profile_id": FourLimbBodyDefinition.BODY_PROFILE_ID,
		"observation_schema_version": FourLimbMLObservation.SCHEMA_VERSION,
		"action_schema_version": FourLimbMLAction.SCHEMA_VERSION,
		"action_count": ACTION_COUNT,
		"feature_count": FourLimbMLFeatureEncoder.FEATURE_COUNT,
		"hidden_size": hidden_size,
		"hidden_layer_count": hidden_layer_count,
		"actor": actor.to_runtime_state(),
		"critic": critic.to_runtime_state(),
		"log_standard_deviation": log_standard_deviation.duplicate(),
		"log_standard_deviation_first_moment": (
			log_standard_deviation_first_moment.duplicate()
		),
		"log_standard_deviation_second_moment": (
			log_standard_deviation_second_moment.duplicate()
		),
		"log_standard_deviation_optimizer_step": log_standard_deviation_optimizer_step,
	}


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
		or loaded_hidden_size < DronePPOMLP.MINIMUM_HIDDEN_WIDTH
		or loaded_hidden_size > DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
		or loaded_hidden_layer_count < DronePPOMLP.MINIMUM_HIDDEN_DEPTH
		or loaded_hidden_layer_count > DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	):
		return false
	var staged: FourLimbPPOActorCritic = FourLimbPPOActorCritic.new(
		7340033,
		loaded_hidden_size,
		loaded_hidden_layer_count
	)
	if not staged._load_state_in_place(state) or not staged.is_finite_state():
		return false
	hidden_size = staged.hidden_size
	hidden_layer_count = staged.hidden_layer_count
	actor = staged.actor
	critic = staged.critic
	log_standard_deviation = staged.log_standard_deviation.duplicate()
	log_standard_deviation_first_moment = staged.log_standard_deviation_first_moment.duplicate()
	log_standard_deviation_second_moment = staged.log_standard_deviation_second_moment.duplicate()
	log_standard_deviation_optimizer_step = staged.log_standard_deviation_optimizer_step
	action_rng.state = staged.action_rng.state
	clear_actor_gradients()
	clear_critic_gradients()
	return true


func _load_state_in_place(state: Dictionary) -> bool:
	if (
		RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1) != STATE_SCHEMA_VERSION
		or str(state.get("body_profile_id", "")) != FourLimbBodyDefinition.BODY_PROFILE_ID
		or RLTrainingMath.finite_int_or(state.get("observation_schema_version", 0), -1) != FourLimbMLObservation.SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(state.get("action_schema_version", 0), -1) != FourLimbMLAction.SCHEMA_VERSION
		or RLTrainingMath.finite_int_or(state.get("action_count", 0), -1) != ACTION_COUNT
		or RLTrainingMath.finite_int_or(state.get("feature_count", 0), -1) != FourLimbMLFeatureEncoder.FEATURE_COUNT
		or RLTrainingMath.finite_int_or(state.get("hidden_size", 0), -1) != hidden_size
		or RLTrainingMath.finite_int_or(state.get("hidden_layer_count", 0), -1) != hidden_layer_count
		or not (state.get("actor", {}) is Dictionary)
		or not (state.get("critic", {}) is Dictionary)
	):
		return false
	var loaded_log_std = _packed_array(state.get("log_standard_deviation", []))
	var loaded_first = _packed_array(state.get("log_standard_deviation_first_moment", []))
	var loaded_second = _packed_array(state.get("log_standard_deviation_second_moment", []))
	if (
		loaded_log_std.size() != ACTION_COUNT
		or loaded_first.size() != ACTION_COUNT
		or loaded_second.size() != ACTION_COUNT
	):
		return false
	for values: PackedFloat64Array in [loaded_log_std, loaded_first, loaded_second]:
		for value: float in values:
			if not is_finite(value):
				return false
	if not actor.load_state(state.get("actor", {})):
		return false
	if not critic.load_state(state.get("critic", {})):
		return false
	log_standard_deviation = loaded_log_std
	log_standard_deviation_first_moment = loaded_first
	log_standard_deviation_second_moment = loaded_second
	log_standard_deviation_optimizer_step = maxi(
		RLTrainingMath.finite_int_or(
			state.get("log_standard_deviation_optimizer_step", 0),
			0
		),
		0
	)
	return true


func copy_from(source: FourLimbPPOActorCritic) -> bool:
	return source != null and load_state(source.to_state())


func perturb_weights(relative_strength: float, perturbation_seed: int) -> bool:
	var strength = clampf(relative_strength, 0.0, 0.5)
	if strength <= 0.0:
		return true
	var rng = RandomNumberGenerator.new()
	rng.seed = perturbation_seed
	if (
		not actor.perturb_parameters(rng, strength)
		or not critic.perturb_parameters(rng, strength)
	):
		return false
	log_standard_deviation_first_moment.fill(0.0)
	log_standard_deviation_second_moment.fill(0.0)
	log_standard_deviation_optimizer_step = 0
	action_rng.seed = perturbation_seed + 2
	clear_actor_gradients()
	clear_critic_gradients()
	return is_finite_state()


func is_finite_state() -> bool:
	if not actor.is_finite_state() or not critic.is_finite_state():
		return false
	for values: PackedFloat64Array in [
		log_standard_deviation,
		log_standard_deviation_first_moment,
		log_standard_deviation_second_moment,
	]:
		for value: float in values:
			if not is_finite(value):
				return false
	return true


func _gaussian_log_probability(
	latent_action: PackedFloat64Array,
	mean: PackedFloat64Array
) -> float:
	var result = 0.0
	for index in range(ACTION_COUNT):
		var log_std = log_standard_deviation[index]
		var difference = latent_action[index] - mean[index]
		var inverse_variance = exp(-2.0 * log_std)
		result += -0.5 * (
			difference * difference * inverse_variance
			+ 2.0 * log_std
			+ LOG_TWO_PI
		)
	return result


func _apply_log_standard_deviation_adam(learning_rate: float) -> void:
	log_standard_deviation_optimizer_step += 1
	var first_correction = 1.0 - pow(ADAM_BETA_ONE, log_standard_deviation_optimizer_step)
	var second_correction = 1.0 - pow(ADAM_BETA_TWO, log_standard_deviation_optimizer_step)
	for index in range(ACTION_COUNT):
		var gradient = log_standard_deviation_gradient[index]
		log_standard_deviation_first_moment[index] = (
			ADAM_BETA_ONE * log_standard_deviation_first_moment[index]
			+ (1.0 - ADAM_BETA_ONE) * gradient
		)
		log_standard_deviation_second_moment[index] = (
			ADAM_BETA_TWO * log_standard_deviation_second_moment[index]
			+ (1.0 - ADAM_BETA_TWO) * gradient * gradient
		)
		var corrected_first = log_standard_deviation_first_moment[index] / first_correction
		var corrected_second = log_standard_deviation_second_moment[index] / second_correction
		log_standard_deviation[index] = clampf(
			log_standard_deviation[index]
			- learning_rate * corrected_first / (sqrt(corrected_second) + ADAM_EPSILON),
			MINIMUM_LOG_STANDARD_DEVIATION,
			MAXIMUM_LOG_STANDARD_DEVIATION
		)
	log_standard_deviation_gradient.fill(0.0)


func _packed_array(value: Variant) -> PackedFloat64Array:
	if value is PackedFloat64Array:
		return (value as PackedFloat64Array).duplicate()
	var result = PackedFloat64Array()
	if value is Array:
		for item: Variant in value:
			if not (item is int or item is float):
				return PackedFloat64Array()
			result.append(float(item))
	return result
