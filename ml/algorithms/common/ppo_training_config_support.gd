class_name PPOTrainingConfigSupport
extends RefCounted

#######################################################
# Shared configuration surface for the fixed-width PPO body trainers. Drone PPO intentionally
# keeps its older public tuning vocabulary; limb and turret PPO use this common schema so their
# bounds and safety sanitization cannot drift independently.
#######################################################


static func body_configuration_controls(command_description: String) -> Array[Dictionary]:
	var controls: Array[Dictionary] = [
		{"key": "learning_rate", "title": "Learning rate", "minimum": 0.000001, "maximum": 0.01, "step": 0.000001, "tooltip": "Adam learning rate used by both actor and critic."},
		{"key": "gamma", "title": "Discount factor", "minimum": 0.90, "maximum": 1.0, "step": 0.001, "tooltip": "How strongly future reward contributes to the current update."},
		{"key": "gae_lambda", "title": "GAE lambda", "minimum": 0.0, "maximum": 1.0, "step": 0.01, "tooltip": "Bias/variance balance for generalized advantage estimation."},
		{"key": "clip_range", "title": "PPO clip range", "minimum": 0.01, "maximum": 0.5, "step": 0.01, "tooltip": "Maximum trusted policy-ratio change per PPO update."},
		{"key": "entropy_coefficient", "title": "Exploration strength", "minimum": 0.0, "maximum": 0.1, "step": 0.0005, "tooltip": "Regularizes the Gaussian policy before tanh squashes it into %s. This is latent-policy entropy, not literal actuator-command entropy." % command_description},
		{"key": "value_coefficient", "title": "Value loss weight", "minimum": 0.0, "maximum": 2.0, "step": 0.01, "tooltip": "Relative critic-loss weight."},
		{"key": "maximum_gradient_norm", "title": "Maximum gradient norm", "minimum": 0.0, "maximum": 10.0, "step": 0.05, "tooltip": "Gradient clipping threshold used to limit unstable updates."},
		{"key": "rollout_size", "title": "Rollout transitions", "minimum": 64.0, "maximum": 4096.0, "step": 64.0, "integer": true, "tooltip": "Transitions collected before a normal background PPO update starts."},
		{"key": "minimum_update_transitions", "title": "Minimum partial update", "minimum": 16.0, "maximum": 1024.0, "step": 16.0, "integer": true, "tooltip": "Smallest rollout accepted for a forced partial update at an episode boundary."},
		{"key": "epochs", "title": "PPO epochs", "minimum": 1.0, "maximum": 16.0, "step": 1.0, "integer": true, "tooltip": "Number of optimization passes over each detached rollout."},
		{"key": "batch_size", "title": "Minibatch size", "minimum": 16.0, "maximum": 512.0, "step": 16.0, "integer": true, "tooltip": "Samples processed before each optimizer step."},
		{"key": "target_kl", "title": "Target KL", "minimum": 0.0, "maximum": 0.2, "step": 0.001, "tooltip": "Stops an update early when the policy moves too far from the behavior policy."},
	]
	return controls


static func sanitize_body_config(config: Dictionary, defaults: Dictionary) -> void:
	config["learning_rate"] = clampf(
		RLTrainingMath.finite_float_or(config.get("learning_rate"), defaults["learning_rate"]),
		0.000001,
		0.1
	)
	config["gamma"] = clampf(
		RLTrainingMath.finite_float_or(config.get("gamma"), defaults["gamma"]),
		0.0,
		1.0
	)
	config["gae_lambda"] = clampf(
		RLTrainingMath.finite_float_or(config.get("gae_lambda"), defaults["gae_lambda"]),
		0.0,
		1.0
	)
	config["clip_range"] = clampf(
		RLTrainingMath.finite_float_or(config.get("clip_range"), defaults["clip_range"]),
		0.01,
		1.0
	)
	config["entropy_coefficient"] = maxf(
		RLTrainingMath.finite_float_or(
			config.get("entropy_coefficient"),
			defaults["entropy_coefficient"]
		),
		0.0
	)
	config["value_coefficient"] = maxf(
		RLTrainingMath.finite_float_or(config.get("value_coefficient"), defaults["value_coefficient"]),
		0.0
	)
	config["maximum_gradient_norm"] = maxf(
		RLTrainingMath.finite_float_or(
			config.get("maximum_gradient_norm"),
			defaults["maximum_gradient_norm"]
		),
		0.0
	)
	config["rollout_size"] = maxi(
		RLTrainingMath.finite_int_or(config.get("rollout_size"), defaults["rollout_size"]),
		1
	)
	config["minimum_update_transitions"] = clampi(
		RLTrainingMath.finite_int_or(
			config.get("minimum_update_transitions"),
			defaults["minimum_update_transitions"]
		),
		1,
		int(config["rollout_size"])
	)
	config["epochs"] = maxi(
		RLTrainingMath.finite_int_or(config.get("epochs"), defaults["epochs"]),
		1
	)
	config["batch_size"] = maxi(
		RLTrainingMath.finite_int_or(config.get("batch_size"), defaults["batch_size"]),
		1
	)
	config["target_kl"] = maxf(
		RLTrainingMath.finite_float_or(config.get("target_kl"), defaults["target_kl"]),
		0.0
	)
	config["control_interval_seconds"] = clampf(
		RLTrainingMath.finite_float_or(
			config.get("control_interval_seconds"),
			defaults["control_interval_seconds"]
		),
		0.001,
		1.0
	)
	config["discount_reference_interval_seconds"] = clampf(
		RLTrainingMath.finite_float_or(
			config.get("discount_reference_interval_seconds"),
			defaults["discount_reference_interval_seconds"]
		),
		0.001,
		1.0
	)
	config["hidden_layer_width"] = clampi(
		RLTrainingMath.finite_int_or(
			config.get("hidden_layer_width"),
			defaults["hidden_layer_width"]
		),
		DronePPOMLP.MINIMUM_HIDDEN_WIDTH,
		DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
	)
	config["hidden_layer_depth"] = clampi(
		RLTrainingMath.finite_int_or(
			config.get("hidden_layer_depth"),
			defaults["hidden_layer_depth"]
		),
		DronePPOMLP.MINIMUM_HIDDEN_DEPTH,
		DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
	)
