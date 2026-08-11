class_name DronePPOActorCritic
extends RefCounted

const STATE_SCHEMA_VERSION: int = 6
const PROPELLER_ACTION_COUNT: int = 4 # Legacy quad default.
const MINIMUM_ACTION_COUNT: int = 1
const ACTION_COUNT: int = PROPELLER_ACTION_COUNT
const MAXIMUM_ACTION_COUNT: int = 256
const HIDDEN_SIZE: int = 64
const HIDDEN_LAYER_COUNT: int = 2
const INITIAL_COMMAND = 0.70
const INITIAL_LOG_STANDARD_DEVIATION = -1.0
const MINIMUM_LOG_STANDARD_DEVIATION = -4.0
const MAXIMUM_LOG_STANDARD_DEVIATION = 0.5
const LOG_TWO_PI = 1.8378770664093453
const LOG_TWO_PI_E_HALF = 1.4189385332046727
const ADAM_BETA_ONE = 0.9
const ADAM_BETA_TWO = 0.999
const ADAM_EPSILON = 0.00000001

#######################################################
# Owns PPO's Gaussian actor and value critic. Network dimensions come from an accepted body
# interface manifest. Every output is squashed once and then mapped through its part-declared
# control range; the actor no longer knows what a limb, gun, or other attachment is.
# Stored latent actions keep PPO ratios exact.
#######################################################

var actor: DronePPOMLP
var critic: DronePPOMLP
var observation_schema_version = DronePPOObservationEncoder.SCHEMA_VERSION
var hidden_size: int = HIDDEN_SIZE
var action_count: int = ACTION_COUNT
var body_feature_count: int = 0
var body_interface_signature: String = ""
var control_descriptors: Array[Dictionary] = []
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
	random_seed = 4194301,
	configured_observation_schema_version = DronePPOObservationEncoder.SCHEMA_VERSION,
	configured_hidden_size: int = HIDDEN_SIZE,
	configured_hidden_layer_count: int = HIDDEN_LAYER_COUNT,
	configured_action_count: int = ACTION_COUNT,
	configured_body_feature_count: int = 0,
	configured_control_descriptors: Array[Dictionary] = [],
	configured_body_interface_signature: String = "",
	configured_initial_control_values: Array = []
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
	action_count = clampi(
		configured_action_count,
		MINIMUM_ACTION_COUNT,
		MAXIMUM_ACTION_COUNT
	)
	body_feature_count = maxi(configured_body_feature_count, 0)
	body_interface_signature = configured_body_interface_signature
	control_descriptors = _normalized_control_descriptors(
		configured_control_descriptors,
		action_count
	)
	_initialize_workspaces()
	_configure_networks(
		random_seed,
		int(configured_observation_schema_version),
		configured_initial_control_values
	)


func _initialize_workspaces() -> void:
	log_standard_deviation.resize(action_count)
	log_standard_deviation_gradient.resize(action_count)
	log_standard_deviation_first_moment.resize(action_count)
	log_standard_deviation_second_moment.resize(action_count)
	mean_gradient_workspace.resize(action_count)
	critic_gradient_workspace.resize(1)
	log_standard_deviation.fill(INITIAL_LOG_STANDARD_DEVIATION)
	log_standard_deviation_gradient.fill(0.0)
	log_standard_deviation_first_moment.fill(0.0)
	log_standard_deviation_second_moment.fill(0.0)


func _configure_networks(
	random_seed: int,
	schema_version: int,
	configured_initial_control_values: Array = []
) -> bool:
	if not DronePPOObservationEncoder.supports_schema(schema_version):
		return false
	observation_schema_version = schema_version
	var initial_actor_bias = log(INITIAL_COMMAND / (1.0 - INITIAL_COMMAND))
	actor = DronePPOMLP.new(
		DronePPOObservationEncoder.actor_feature_count_for_schema(schema_version, body_feature_count),
		hidden_size,
		action_count,
		random_seed,
		0.01,
		initial_actor_bias,
		hidden_layer_count
	)
	# Each serialized part declares its physical command range and neutral value. Fresh creator bodies
	# may provide body-specific startup targets (for example a mass/power-aware rotor hover bias);
	# otherwise rotors retain the legacy 70% fallback and other controls start at neutral.
	var output_bias_offset = actor.output_bias_offset()
	for index in range(action_count):
		var descriptor: Dictionary = control_descriptors[index]
		var minimum: float = float(descriptor.get("minimum", -1.0))
		var maximum: float = float(descriptor.get("maximum", 1.0))
		var neutral: float = float(descriptor.get("neutral", 0.0))
		var target: float = neutral
		if str(descriptor.get("kind", "")) == "propeller_throttle":
			target = minimum + (maximum - minimum) * INITIAL_COMMAND
		if index < configured_initial_control_values.size():
			var configured_value: Variant = configured_initial_control_values[index]
			if (configured_value is int or configured_value is float) and is_finite(float(configured_value)):
				target = clampf(float(configured_value), minimum, maximum)
		var normalized: float = clampf(
			(target - minimum) / maxf(maximum - minimum, 0.000001),
			0.001,
			0.999
		)
		actor.parameters[output_bias_offset + index] = log(normalized / (1.0 - normalized))
	critic = DronePPOMLP.new(
		DronePPOObservationEncoder.critic_feature_count_for_schema(schema_version, body_feature_count),
		hidden_size,
		1,
		random_seed + 1,
		1.0,
		0.0,
		hidden_layer_count
	)
	action_rng.seed = random_seed + 2
	return true


func sample_action(
	observation: Dictionary,
	deterministic = false
) -> Dictionary:
	if not _observation_matches_body_interface(observation):
		return {}
	var actor_input = DronePPOObservationEncoder.encode_actor_for_schema(
		observation,
		observation_schema_version,
		body_feature_count
	)
	var critic_input = DronePPOObservationEncoder.encode_critic_from_actor_for_schema(
		actor_input,
		observation,
		observation_schema_version,
		body_feature_count
	)
	return sample_action_from_inputs(
		observation,
		actor_input,
		critic_input,
		deterministic
	)


func deterministic_action(observation: Dictionary) -> Dictionary:
	if not _observation_matches_body_interface(observation):
		return {}
	var actor_input = DronePPOObservationEncoder.encode_actor_for_schema(
		observation,
		observation_schema_version,
		body_feature_count
	)
	if not DronePPOObservationEncoder.is_normalized_tensor(actor_input):
		return {}
	var mean = actor.predict_reusable(actor_input)
	if mean.size() != action_count:
		return {}
	var commands = PackedFloat64Array()
	commands.resize(action_count)
	for index in range(action_count):
		commands[index] = _sigmoid(mean[index])
	return _action_dictionary(observation, commands)


func sample_action_from_inputs(
	observation: Dictionary,
	actor_input: PackedFloat64Array,
	critic_input: PackedFloat64Array,
	deterministic = false
) -> Dictionary:
	if not _observation_matches_body_interface(observation):
		return {}
	if not DronePPOObservationEncoder.are_valid_encoded_tensors(
		actor_input,
		critic_input,
		observation_schema_version,
		body_feature_count
	):
		return {}
	var mean = actor.predict_reusable(actor_input)
	var value_output = critic.predict_reusable(critic_input)
	if mean.size() != action_count or value_output.size() != 1:
		return {}

	var latent_action = PackedFloat64Array()
	var commands = PackedFloat64Array()
	latent_action.resize(action_count)
	commands.resize(action_count)
	for index in range(action_count):
		latent_action[index] = (
			mean[index]
			if deterministic
			else mean[index] + exp(log_standard_deviation[index]) * action_rng.randfn()
		)
		commands[index] = _sigmoid(latent_action[index])
	return {
		"action": _action_dictionary(observation, commands),
		"actor_input": actor_input,
		"critic_input": critic_input,
		"latent_action": latent_action,
		"commands": commands,
		"log_probability": _gaussian_log_probability(latent_action, mean),
		"value": value_output[0],
		"deterministic": deterministic,
	}


func log_probability_from_input(
	actor_input: PackedFloat64Array,
	latent_action: PackedFloat64Array
) -> float:
	var mean = actor.predict_reusable(actor_input)
	if mean.size() != action_count or latent_action.size() != action_count:
		return NAN
	return _gaussian_log_probability(latent_action, mean)


func value_for_observation(observation: Dictionary) -> float:
	return value_from_input(DronePPOObservationEncoder.encode_critic_for_schema(
		observation,
		observation_schema_version,
		body_feature_count
	))


func value_from_input(input: PackedFloat64Array) -> float:
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
	if mean.size() != action_count or latent_action.size() != action_count:
		return {}
	var new_log_probability = _gaussian_log_probability(latent_action, mean)
	var log_ratio = clampf(
		new_log_probability - old_log_probability,
		-20.0,
		20.0
	)
	var ratio = exp(log_ratio)
	var clipped_ratio = clampf(ratio, 1.0 - clip_range, 1.0 + clip_range)
	var unclipped_objective = ratio * advantage
	var clipped_objective = clipped_ratio * advantage
	var objective = minf(unclipped_objective, clipped_objective)
	var gradient_is_clipped = (
		(advantage >= 0.0 and ratio > 1.0 + clip_range)
		or (advantage < 0.0 and ratio < 1.0 - clip_range)
	)
	var loss_log_probability_gradient = (
		0.0 if gradient_is_clipped else -ratio * advantage
	)
	for index in range(action_count):
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
	var entropy = gaussian_entropy()
	return {
		"actor_loss": -objective - entropy_coefficient * entropy,
		"entropy": entropy,
		"approximate_kl": (ratio - 1.0) - log_ratio,
		"clip_fraction": (
			1.0
			if ratio < 1.0 - clip_range or ratio > 1.0 + clip_range
			else 0.0
		),
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
	var inverse_batch_size = 1.0 / float(maxi(batch_size, 1))
	actor.scale_gradients(inverse_batch_size)
	for index in range(action_count):
		log_standard_deviation_gradient[index] *= inverse_batch_size
	var norm_squared = actor.gradient_norm_squared()
	for gradient in log_standard_deviation_gradient:
		norm_squared += gradient * gradient
	var gradient_norm = sqrt(norm_squared)
	if gradient_norm > maximum_gradient_norm and maximum_gradient_norm > 0.0:
		var scale = maximum_gradient_norm / gradient_norm
		actor.scale_gradients(scale)
		for index in range(action_count):
			log_standard_deviation_gradient[index] *= scale
	actor.apply_adam(learning_rate)
	_apply_log_standard_deviation_adam(learning_rate)
	return gradient_norm


func apply_critic_gradients(
	learning_rate: float,
	batch_size: int,
	maximum_gradient_norm: float
) -> float:
	critic.scale_gradients(1.0 / float(maxi(batch_size, 1)))
	var gradient_norm = sqrt(critic.gradient_norm_squared())
	if gradient_norm > maximum_gradient_norm and maximum_gradient_norm > 0.0:
		critic.scale_gradients(maximum_gradient_norm / gradient_norm)
	critic.apply_adam(learning_rate)
	return gradient_norm


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
		"mean": total / float(maxi(log_standard_deviation.size(), 1)),
		"minimum": minimum if is_finite(minimum) else 0.0,
		"maximum": maximum,
	}


func to_state() -> Dictionary:
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"observation_schema_version": observation_schema_version,
		"action_count": action_count,
		"body_feature_count": body_feature_count,
		"body_interface_signature": body_interface_signature,
		"control_descriptors": control_descriptors.duplicate(true),
		"hidden_size": hidden_size,
		"hidden_layer_count": hidden_layer_count,
		"actor": actor.to_state(),
		"critic": critic.to_state(),
		"log_standard_deviation": Array(log_standard_deviation),
		"log_standard_deviation_first_moment": Array(
			log_standard_deviation_first_moment
		),
		"log_standard_deviation_second_moment": Array(
			log_standard_deviation_second_moment
		),
		"log_standard_deviation_optimizer_step": (
			log_standard_deviation_optimizer_step
		),
		"action_rng_state": action_rng.state,
	}


func to_runtime_state() -> Dictionary:
	return {
		"schema_version": STATE_SCHEMA_VERSION,
		"observation_schema_version": observation_schema_version,
		"action_count": action_count,
		"body_feature_count": body_feature_count,
		"body_interface_signature": body_interface_signature,
		"control_descriptors": control_descriptors.duplicate(true),
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
		"log_standard_deviation_optimizer_step": (
			log_standard_deviation_optimizer_step
		),
		"action_rng_state": action_rng.state,
	}


func copy_from(source: DronePPOActorCritic) -> bool:
	return source != null and load_state(source.to_runtime_state())


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
	# Exploration magnitude is copied, but its old optimizer momentum is not applicable to
	# the mutated networks. The child will learn its own standard-deviation trajectory.
	log_standard_deviation_first_moment.fill(0.0)
	log_standard_deviation_second_moment.fill(0.0)
	log_standard_deviation_optimizer_step = 0
	action_rng.seed = perturbation_seed + 2
	clear_actor_gradients()
	clear_critic_gradients()
	return is_finite_state()


func load_state(state: Dictionary) -> bool:
	var loaded_observation_schema: int = RLTrainingMath.finite_int_or(
		state.get("observation_schema_version", 0),
		-1
	)
	var loaded_hidden_size: int = RLTrainingMath.finite_int_or(
		state.get("hidden_size", 0),
		-1
	)
	var loaded_hidden_layer_count: int = RLTrainingMath.finite_int_or(
		state.get("hidden_layer_count", 0),
		-1
	)
	var loaded_action_count: int = RLTrainingMath.finite_int_or(
		state.get("action_count", 0),
		-1
	)
	var loaded_body_feature_count: int = RLTrainingMath.finite_int_or(
		state.get("body_feature_count", 0),
		-1
	)
	var loaded_control_descriptors: Array[Dictionary] = _dictionary_array(
		state.get("control_descriptors", [])
	)
	var loaded_body_interface_signature: String = str(state.get("body_interface_signature", ""))
	if (
		RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1)
		!= STATE_SCHEMA_VERSION
		or not DronePPOObservationEncoder.is_trainable_schema(loaded_observation_schema)
		or loaded_action_count < MINIMUM_ACTION_COUNT
		or loaded_action_count > MAXIMUM_ACTION_COUNT
		or loaded_body_feature_count < 0
		or loaded_control_descriptors.size() != loaded_action_count
		or loaded_hidden_size < DronePPOMLP.MINIMUM_HIDDEN_WIDTH
		or loaded_hidden_size > DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
		or loaded_hidden_layer_count < DronePPOMLP.MINIMUM_HIDDEN_DEPTH
		or loaded_hidden_layer_count > DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	):
		return false
	var staged: DronePPOActorCritic = DronePPOActorCritic.new(
		4194301,
		loaded_observation_schema,
		loaded_hidden_size,
		loaded_hidden_layer_count,
		loaded_action_count,
		loaded_body_feature_count,
		loaded_control_descriptors,
		loaded_body_interface_signature
	)
	if not staged._load_state_in_place(state) or not staged.is_finite_state():
		return false
	_adopt_state(staged)
	return true


func _adopt_state(staged: DronePPOActorCritic) -> void:
	observation_schema_version = staged.observation_schema_version
	hidden_size = staged.hidden_size
	hidden_layer_count = staged.hidden_layer_count
	action_count = staged.action_count
	body_feature_count = staged.body_feature_count
	body_interface_signature = staged.body_interface_signature
	control_descriptors = staged.control_descriptors.duplicate(true)
	_initialize_workspaces()
	actor = staged.actor
	critic = staged.critic
	log_standard_deviation = staged.log_standard_deviation.duplicate()
	log_standard_deviation_first_moment = staged.log_standard_deviation_first_moment.duplicate()
	log_standard_deviation_second_moment = staged.log_standard_deviation_second_moment.duplicate()
	log_standard_deviation_optimizer_step = staged.log_standard_deviation_optimizer_step
	action_rng.state = staged.action_rng.state
	clear_actor_gradients()
	clear_critic_gradients()


func _load_state_in_place(state: Dictionary) -> bool:
	var loaded_observation_schema: int = RLTrainingMath.finite_int_or(
		state.get("observation_schema_version", 0),
		-1
	)
	if (
		RLTrainingMath.finite_int_or(state.get("schema_version", 0), -1)
		!= STATE_SCHEMA_VERSION
		or loaded_observation_schema != observation_schema_version
		or RLTrainingMath.finite_int_or(state.get("action_count", 0), -1) != action_count
		or RLTrainingMath.finite_int_or(state.get("body_feature_count", -1), -1) != body_feature_count
		or str(state.get("body_interface_signature", "")) != body_interface_signature
		or _dictionary_array(state.get("control_descriptors", [])) != control_descriptors
		or RLTrainingMath.finite_int_or(state.get("hidden_size", 0), -1) != hidden_size
		or RLTrainingMath.finite_int_or(state.get("hidden_layer_count", 0), -1)
		!= hidden_layer_count
		or not (state.get("actor", {}) is Dictionary)
		or not (state.get("critic", {}) is Dictionary)
	):
		return false
	var loaded_log_standard_deviation = _packed_array(
		state.get("log_standard_deviation", [])
	)
	var loaded_first = _packed_array(
		state.get("log_standard_deviation_first_moment", [])
	)
	var loaded_second = _packed_array(
		state.get("log_standard_deviation_second_moment", [])
	)
	if (
		loaded_log_standard_deviation.size() != action_count
		or loaded_first.size() != action_count
		or loaded_second.size() != action_count
		or not actor.load_state(state.get("actor", {}))
		or not critic.load_state(state.get("critic", {}))
		or not _all_finite(loaded_log_standard_deviation)
		or not _all_finite(loaded_first)
		or not _all_finite(loaded_second)
	):
		return false
	log_standard_deviation = loaded_log_standard_deviation
	log_standard_deviation_first_moment = loaded_first
	log_standard_deviation_second_moment = loaded_second
	log_standard_deviation_optimizer_step = maxi(
		RLTrainingMath.finite_int_or(
			state.get("log_standard_deviation_optimizer_step", 0),
			0
		),
		0
	)
	action_rng.state = RLTrainingMath.finite_int_or(
		state.get("action_rng_state", action_rng.state),
		action_rng.state
	)
	clear_actor_gradients()
	clear_critic_gradients()
	return true


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


func _action_dictionary(
	observation: Dictionary,
	commands: PackedFloat64Array
) -> Dictionary:
	if commands.size() != action_count or control_descriptors.size() != action_count:
		return {}
	var body_commands = PackedFloat64Array()
	body_commands.resize(action_count)
	for index in range(action_count):
		var descriptor: Dictionary = control_descriptors[index]
		var minimum: float = float(descriptor.get("minimum", -1.0))
		var maximum: float = float(descriptor.get("maximum", 1.0))
		body_commands[index] = clampf(
			minimum + clampf(commands[index], 0.0, 1.0) * (maximum - minimum),
			minimum,
			maximum
		)
	var action: Dictionary = {
		"body_commands": body_commands,
		"body_interface_signature": body_interface_signature,
	}
	# Compatibility mirrors keep existing visualizers/runtime code useful while the generic
	# body_commands contract becomes authoritative. They are derived, never independently learned.
	var propellers: Array = observation.get("propellers", [])
	if not propellers.is_empty():
		var propeller_commands: Array[Dictionary] = []
		var propeller_mirror_valid: bool = true
		for propeller_index in range(propellers.size()):
			var propeller: Dictionary = propellers[propeller_index]
			var slot_index: int = int(propeller.get("slot_index", propeller_index))
			var descriptor_index: int = _control_descriptor_index(
				"propeller_%d" % slot_index,
				"propeller_throttle"
			)
			if descriptor_index < 0:
				propeller_mirror_valid = false
				break
			propeller_commands.append({
				"slot_index": slot_index,
				"command": body_commands[descriptor_index],
			})
		if propeller_mirror_valid:
			action["propeller_commands"] = propeller_commands

	var attachment_commands = PackedFloat64Array()
	var limb_commands = PackedFloat64Array()
	for index in range(control_descriptors.size()):
		var descriptor: Dictionary = control_descriptors[index]
		var slot_id: String = str(descriptor.get("slot_id", ""))
		var kind: String = str(descriptor.get("kind", ""))
		if slot_id.begins_with("attachment_"):
			attachment_commands.append(body_commands[index])
		if kind == "joint_target" or kind == "grip_activation":
			limb_commands.append(body_commands[index])
	if not attachment_commands.is_empty():
		action["attachment_commands"] = attachment_commands
	if not limb_commands.is_empty():
		action["limb_commands"] = limb_commands
	return action


func _control_descriptor_index(slot_id: String, kind: String) -> int:
	for index in range(control_descriptors.size()):
		var descriptor: Dictionary = control_descriptors[index]
		if (
			str(descriptor.get("slot_id", "")) == slot_id
			and str(descriptor.get("kind", "")) == kind
		):
			return index
	return -1


func _observation_matches_body_interface(observation: Dictionary) -> bool:
	if not DronePPOObservationEncoder.has_valid_propeller_topology(observation):
		return false
	var expected_propeller_count: int = 0
	for descriptor: Dictionary in control_descriptors:
		if str(descriptor.get("kind", "")) == "propeller_throttle":
			expected_propeller_count += 1
	if (observation.get("propellers", []) as Array).size() != expected_propeller_count:
		return false
	if observation_schema_version < DronePPOObservationEncoder.BODY_INTERFACE_SCHEMA_VERSION:
		return true
	var signature: String = str(observation.get("model_body_signature", ""))
	var features_value: Variant = observation.get("model_body_features", PackedFloat64Array())
	var feature_count: int = -1
	if features_value is PackedFloat64Array:
		var features64: PackedFloat64Array = features_value
		feature_count = features64.size()
	elif features_value is PackedFloat32Array:
		var features32: PackedFloat32Array = features_value
		feature_count = features32.size()
	elif features_value is Array:
		var features_array: Array = features_value
		feature_count = features_array.size()
	if body_interface_signature.is_empty():
		return signature.is_empty() and body_feature_count == 0 and feature_count == 0
	if signature != body_interface_signature:
		return false
	return feature_count == body_feature_count

static func _normalized_control_descriptors(
	source: Array[Dictionary],
	expected_count: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source.size() == expected_count:
		for index in range(source.size()):
			var descriptor: Dictionary = source[index].duplicate(true)
			var minimum: float = float(descriptor.get("minimum", -1.0))
			var maximum: float = float(descriptor.get("maximum", 1.0))
			if not is_finite(minimum) or not is_finite(maximum) or maximum <= minimum:
				minimum = -1.0
				maximum = 1.0
			descriptor["minimum"] = minimum
			descriptor["maximum"] = maximum
			descriptor["neutral"] = clampf(float(descriptor.get("neutral", 0.0)), minimum, maximum)
			result.append(descriptor)
		return result
	# Descriptor-less states are only interpreted as the historical stock quad when the entire
	# action width matches that legacy contract. A wider creator body must not silently turn its
	# first four arbitrary controls into propellers with a 70% startup bias.
	var legacy_quad_fallback: bool = expected_count == PROPELLER_ACTION_COUNT
	for index in range(expected_count):
		var propeller_fallback: bool = legacy_quad_fallback
		result.append({
			"name": ("propeller_%d.throttle" % index) if propeller_fallback else "control_%d" % index,
			"slot_id": ("propeller_%d" % index) if propeller_fallback else "",
			"local_index": 0 if propeller_fallback else index,
			"index": index,
			"kind": "propeller_throttle" if propeller_fallback else "generic",
			"minimum": 0.0 if propeller_fallback else -1.0,
			"maximum": 1.0,
			"neutral": 0.0,
		})
	return result


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _gaussian_log_probability(
	latent_action: PackedFloat64Array,
	mean: PackedFloat64Array
) -> float:
	var result = 0.0
	for index in range(action_count):
		var difference = latent_action[index] - mean[index]
		var inverse_variance = exp(-2.0 * log_standard_deviation[index])
		result += -0.5 * (
			difference * difference * inverse_variance
			+ 2.0 * log_standard_deviation[index]
			+ LOG_TWO_PI
		)
	return result


func _apply_log_standard_deviation_adam(learning_rate: float) -> void:
	log_standard_deviation_optimizer_step += 1
	var first_correction = (
		1.0 - pow(ADAM_BETA_ONE, log_standard_deviation_optimizer_step)
	)
	var second_correction = (
		1.0 - pow(ADAM_BETA_TWO, log_standard_deviation_optimizer_step)
	)
	for index in range(action_count):
		var gradient = log_standard_deviation_gradient[index]
		log_standard_deviation_first_moment[index] = (
			ADAM_BETA_ONE * log_standard_deviation_first_moment[index]
			+ (1.0 - ADAM_BETA_ONE) * gradient
		)
		log_standard_deviation_second_moment[index] = (
			ADAM_BETA_TWO * log_standard_deviation_second_moment[index]
			+ (1.0 - ADAM_BETA_TWO) * gradient * gradient
		)
		var corrected_first = (
			log_standard_deviation_first_moment[index] / first_correction
		)
		var corrected_second = (
			log_standard_deviation_second_moment[index] / second_correction
		)
		log_standard_deviation[index] = clampf(
			log_standard_deviation[index]
			- learning_rate * corrected_first
			/ (sqrt(corrected_second) + ADAM_EPSILON),
			MINIMUM_LOG_STANDARD_DEVIATION,
			MAXIMUM_LOG_STANDARD_DEVIATION
		)
	log_standard_deviation_gradient.fill(0.0)


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
	if not (value is Array or value is PackedFloat64Array):
		return result
	for item in value:
		if not (item is int or item is float):
			return PackedFloat64Array()
		result.append(float(item))
	return result


func _all_finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true
