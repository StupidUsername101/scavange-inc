extends SceneTree

var failure_count = 0
var assertion_count = 0


func _init() -> void:
	_test_time_aware_discount()
	_test_non_finite_config_sanitization()
	_test_deterministic_evaluation_contract()
	_test_replay_chronology_and_real_step_gate()
	_test_automatic_alpha_direction()
	_test_full_sac_checkpoint_round_trip()
	_test_variant_codec_round_trip()
	print("RL implementation-guide assertions: %d, failures: %d" % [
		assertion_count,
		failure_count,
	])
	quit(0 if failure_count == 0 else 1)


func _test_time_aware_discount() -> void:
	var gamma_reference = 0.99
	var reference_interval = 0.05
	var gamma_20_hz = RLTrainingMath.discount_for_delta(
		gamma_reference,
		0.05,
		reference_interval
	)
	var gamma_60_hz = RLTrainingMath.discount_for_delta(
		gamma_reference,
		1.0 / 60.0,
		reference_interval
	)
	_expect(
		is_equal_approx(gamma_20_hz, gamma_reference),
		"the reference control interval reproduces the legacy configured gamma exactly"
	)
	_expect(
		absf(pow(gamma_20_hz, 20.0) - pow(gamma_60_hz, 60.0)) <= 0.000000001,
		"20 Hz and 60 Hz transitions produce the same one-second discount"
	)
	_expect(
		RLTrainingMath.half_life_seconds(gamma_reference, reference_interval) > 0.0,
		"discount metrics expose a finite positive real-time half-life"
	)


func _test_non_finite_config_sanitization() -> void:
	_expect(
		is_equal_approx(RLTrainingMath.finite_float_or(NAN, 0.25), 0.25)
		and RLTrainingMath.finite_int_or(NAN, 7) == 7
		and RLTrainingMath.finite_int_or(4.0, 7) == 4
		and RLTrainingMath.finite_int_or(4.25, 7) == 7
		and not RLTrainingMath.bool_or(NAN, false),
		"shared config conversion rejects non-finite scalar values before clamping"
	)
	var drone_ppo = DronePPOTrainer.new(_ppo_config({}), 13001)
	drone_ppo.config["learning_rate"] = NAN
	drone_ppo.config["rollout_transitions"] = NAN
	drone_ppo._sanitize_config()
	_expect(
		is_finite(float(drone_ppo.config["learning_rate"]))
		and int(drone_ppo.config["rollout_transitions"]) == int(DronePPOTrainer.DEFAULT_CONFIG["rollout_transitions"]),
		"drone PPO replaces poisoned numeric config fields with finite defaults"
	)
	var limb_ppo = FourLimbPPOTrainer.new(13002)
	limb_ppo.config["gamma"] = NAN
	limb_ppo.config["batch_size"] = NAN
	limb_ppo._sanitize_config()
	_expect(
		is_finite(float(limb_ppo.config["gamma"]))
		and int(limb_ppo.config["batch_size"]) == int(FourLimbPPOTrainer.DEFAULT_CONFIG["batch_size"]),
		"four-limb PPO replaces poisoned numeric config fields with finite defaults"
	)
	var turret_ppo = TurretPPOTrainer.new(13003)
	turret_ppo.config["target_kl"] = NAN
	turret_ppo._sanitize_config()
	_expect(
		is_equal_approx(float(turret_ppo.config["target_kl"]), float(TurretPPOTrainer.DEFAULT_CONFIG["target_kl"])),
		"turret PPO replaces a poisoned KL limit with its finite default"
	)
	var sac = DroneSACTrainer.new({}, 13004)
	sac.config["target_update_rate"] = NAN
	sac.config["automatic_entropy_temperature"] = NAN
	sac._sanitize_config()
	_expect(
		is_equal_approx(float(sac.config["target_update_rate"]), float(DroneSACTrainer.DEFAULT_CONFIG["target_update_rate"]))
		and bool(sac.config["automatic_entropy_temperature"]) == bool(DroneSACTrainer.DEFAULT_CONFIG["automatic_entropy_temperature"]),
		"SAC replaces poisoned numeric/bool config fields with finite defaults"
	)


func _test_deterministic_evaluation_contract() -> void:
	for body_kind in ["drone", "four_limb", "turret"]:
		var plan = RLDeterministicEvaluationSuite.default_plan(body_kind, 9011)
		var scenario_ids: Array = plan.get("scenario_ids", [])
		var cases: Array = plan.get("cases", [])
		_expect(
			cases.size() == scenario_ids.size() * RLDeterministicEvaluationSuite.SEEDS_PER_SCENARIO,
			"%s evaluation plan assigns the required fixed seeds to every scenario" % body_kind
		)
	var plan = RLDeterministicEvaluationSuite.default_plan("drone", 12001)
	var candidate_hash = "candidate-a"
	var records = _evaluation_records(plan, candidate_hash, 2.0, false)
	var incomplete_records = records.duplicate(true)
	incomplete_records.pop_back()
	var incomplete = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		plan,
		incomplete_records,
		candidate_hash
	)
	_expect(
		not bool(incomplete.get("suite_complete", true)),
		"a partial fixed-seed evaluation cannot promote a candidate"
	)
	var first = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		plan,
		records,
		candidate_hash
	)
	var repeated = RLDeterministicEvaluationSuite.aggregate_complete_suite(
		plan,
		records,
		candidate_hash
	)
	_expect(
		RLDeterministicEvaluationSuite.is_complete_summary(first)
		and RLDeterministicEvaluationSuite.validate_summary_for_plan(
			plan,
			first,
			candidate_hash
		).get("valid", false),
		"only a complete deterministic suite satisfies the model-promotion contract"
	)
	var poisoned_rates: Dictionary = first.duplicate(true)
	poisoned_rates["crash_rate"] = NAN
	_expect(
		not RLDeterministicEvaluationSuite.is_complete_summary(poisoned_rates)
		and not bool(RLDeterministicEvaluationSuite.validate_summary_for_plan(
			plan,
			poisoned_rates,
			candidate_hash
		).get("valid", true))
		and not bool(RLDeterministicEvaluator.promotion_decision(poisoned_rates).get("promote", true)),
		"a non-finite deterministic safety rate cannot qualify or promote as Best"
	)
	var inconsistent_rates: Dictionary = first.duplicate(true)
	inconsistent_rates["termination_rate"] = 0.25
	inconsistent_rates["truncation_rate"] = 0.25
	_expect(
		not RLDeterministicEvaluationSuite.is_complete_summary(inconsistent_rates)
		and not bool(RLDeterministicEvaluationSuite.validate_summary_for_plan(
			plan,
			inconsistent_rates,
			candidate_hash
		).get("valid", true)),
		"restored evaluation rates must still describe one completed outcome per benchmark case"
	)
	var impossible_records: Array[Dictionary] = records.duplicate(true)
	impossible_records[0]["terminated"] = true
	impossible_records[0]["truncated"] = true
	_expect(
		RLDeterministicEvaluationSuite.aggregate_complete_suite(
			plan,
			impossible_records,
			candidate_hash
		).is_empty(),
		"a deterministic record cannot be both a true terminal and a time-limit truncation"
	)
	var unfinished_records: Array[Dictionary] = records.duplicate(true)
	unfinished_records[0]["terminated"] = false
	unfinished_records[0]["truncated"] = false
	_expect(
		RLDeterministicEvaluationSuite.aggregate_complete_suite(
			plan,
			unfinished_records,
			candidate_hash
		).is_empty(),
		"every completed deterministic case must be either terminal or time-limit truncated"
	)
	_expect(
		is_equal_approx(
			float(first.get("selection_score", NAN)),
			float(repeated.get("selection_score", INF))
		)
		and first.get("records", []) == repeated.get("records", []),
		"the same candidate and fixed records aggregate repeatably"
	)
	_expect(
		bool(RLDeterministicEvaluator.promotion_decision(first).get("promote", false)),
		"the first complete evaluated candidate can become the designated best"
	)
	var unsafe = first.duplicate(true)
	unsafe["selection_score"] = float(first.get("selection_score", 0.0)) + 10.0
	unsafe["crash_rate"] = 1.0
	var current_best = first.duplicate(true)
	current_best["crash_rate"] = 0.0
	_expect(
		not bool(RLDeterministicEvaluator.promotion_decision(
			unsafe,
			current_best,
			0.0,
			0.0
		).get("promote", true)),
		"a higher-return candidate cannot promote through a declared safety regression"
	)


func _test_replay_chronology_and_real_step_gate() -> void:
	var trainer = DroneSACTrainer.new({
		"batch_size": 1,
		"replay_capacity": 10,
		"learning_starts": 4,
		"update_interval_transitions": 1,
		"warmup_exploration_steps": 0,
	}, 13001)
	for logical_id in range(14):
		trainer._add_replay_transition(_minimal_replay_transition(logical_id, false))
	trainer.set_config_value("replay_capacity", 5)
	var ordered = trainer._replay_in_chronological_order()
	var logical_ids: Array[int] = []
	for transition in ordered:
		logical_ids.append(int((transition as Dictionary).get("logical_transition_id", -1)))
	_expect(
		logical_ids == [9, 10, 11, 12, 13],
		"shrinking wrapped replay retains the newest samples in logical chronology"
	)
	var external = _minimal_replay_transition(99, false)
	trainer._add_replay_transition(external)
	external["reward"] = 999.0
	var newest = trainer._replay_in_chronological_order().back() as Dictionary
	_expect(
		not is_equal_approx(float(newest.get("reward", 0.0)), 999.0),
		"replay owns duplicated transitions instead of mutable caller dictionaries"
	)
	for hindsight_id in range(20, 28):
		trainer._add_replay_transition(_minimal_replay_transition(hindsight_id, true))
	trainer.environment_steps_since_replay_reset = 3
	trainer.transitions_since_update = 1
	_expect(
		not trainer.can_update(),
		"HER replay volume cannot satisfy learning_starts before enough real environment steps"
	)
	trainer.environment_steps_since_replay_reset = 4
	_expect(
		trainer.can_update(),
		"the update gate opens at the configured real environment-step count"
	)


func _test_automatic_alpha_direction() -> void:
	var actor_critic = DroneSACActorCritic.new(14001)
	actor_critic.configure_entropy_temperature(0.01, true)
	var low = actor_critic.alpha_direction_probe(1.0, 4.0, 0.001)
	var high = actor_critic.alpha_direction_probe(7.0, 4.0, 0.001)
	var target = actor_critic.alpha_direction_probe(4.0, 4.0, 0.001)
	_expect(
		float(low.get("log_alpha_after", -INF)) > float(low.get("log_alpha_before", INF)),
		"low policy entropy increases automatic SAC alpha"
	)
	_expect(
		float(high.get("log_alpha_after", INF)) < float(high.get("log_alpha_before", -INF)),
		"high policy entropy decreases automatic SAC alpha"
	)
	_expect(
		is_equal_approx(
			float(target.get("log_alpha_after", NAN)),
			float(target.get("log_alpha_before", INF))
		),
		"target policy entropy leaves automatic SAC alpha unchanged"
	)


func _test_full_sac_checkpoint_round_trip() -> void:
	var trainer = DroneSACTrainer.new({
		"batch_size": 1,
		"replay_capacity": 8,
		"learning_starts": 2,
		"warmup_exploration_steps": 0,
	}, 15001)
	for logical_id in range(6):
		trainer._add_replay_transition(_minimal_replay_transition(logical_id, logical_id % 2 == 1))
	trainer.environment_steps_since_replay_reset = 5
	trainer.transitions_since_update = 3
	var checkpoint = trainer.to_training_checkpoint()
	var restored = DroneSACTrainer.new({}, 15002)
	_expect(
		restored.load_training_checkpoint(checkpoint),
		"a full SAC checkpoint restores replay and optimizer-continuation state"
	)
	var original_ids = _logical_ids(trainer._replay_in_chronological_order())
	var restored_ids = _logical_ids(restored._replay_in_chronological_order())
	_expect(
		original_ids == restored_ids
		and trainer.replay_write_index == restored.replay_write_index
		and trainer.environment_steps_since_replay_reset == restored.environment_steps_since_replay_reset,
		"full SAC resume preserves replay order, write position, and real-step warm-up state"
	)
	var original_batch = trainer._sample_replay_batch(4)
	var restored_batch = restored._sample_replay_batch(4)
	_expect(
		_logical_ids(original_batch) == _logical_ids(restored_batch),
		"restored replay RNG produces the same next sampled batch"
	)
	var model_only = DroneSACTrainer.new({}, 15003)
	_expect(
		model_only.load_checkpoint(trainer.to_checkpoint())
		and model_only.replay_buffer.is_empty()
		and model_only.environment_steps_since_replay_reset == 0,
		"a model-only SAC resume intentionally clears replay and restarts warm-up"
	)


func _test_variant_codec_round_trip() -> void:
	var source = {
		7: Vector3(1.0, 2.0, 3.0),
		"basis": Basis.IDENTITY,
		"tensor": PackedFloat64Array([0.25, -0.5, 1.0]),
		"cell": Vector2i(4, -2),
	}
	var decoded: Variant = RLTrainingVariantCodec.decode(RLTrainingVariantCodec.encode(source))
	_expect(decoded is Dictionary, "full-checkpoint variant codec restores dictionaries")
	if not (decoded is Dictionary):
		return
	var dictionary: Dictionary = decoded
	_expect(
		dictionary.has(7)
		and dictionary[7] == Vector3(1.0, 2.0, 3.0)
		and dictionary.get("basis", Basis()) == Basis.IDENTITY
		and dictionary.get("cell", Vector2i.ZERO) == Vector2i(4, -2),
		"variant codec preserves typed dictionary keys and Godot math values"
	)
	var tensor: PackedFloat64Array = dictionary.get("tensor", PackedFloat64Array())
	_expect(
		tensor == PackedFloat64Array([0.25, -0.5, 1.0]),
		"variant codec preserves packed replay tensors exactly"
	)
	var malformed_tensor: Variant = RLTrainingVariantCodec.decode({
		RLTrainingVariantCodec.TYPE_KEY: "PackedFloat64Array",
		RLTrainingVariantCodec.VALUE_KEY: [0.5, {"wrong": true}],
	})
	_expect(
		malformed_tensor is PackedFloat64Array
		and (malformed_tensor as PackedFloat64Array).is_empty(),
		"variant codec rejects malformed packed numeric payloads before replay validation"
	)
	var malformed_dictionary: Variant = RLTrainingVariantCodec.decode({
		RLTrainingVariantCodec.TYPE_KEY: "Dictionary",
		RLTrainingVariantCodec.ENTRIES_KEY: "broken",
	})
	_expect(
		malformed_dictionary is Dictionary
		and (malformed_dictionary as Dictionary).is_empty(),
		"variant codec rejects malformed tagged dictionary entries without throwing"
	)


func _evaluation_records(
	plan: Dictionary,
	candidate_hash: String,
	episode_return: float,
	crashed: bool
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for case_value in plan.get("cases", []):
		var evaluation_case: Dictionary = case_value
		records.append({
			"candidate_hash": candidate_hash,
			"scenario_id": str(evaluation_case.get("scenario_id", "")),
			"seed": int(evaluation_case.get("seed", 0)),
			"deterministic": true,
			"suite_hash": str(plan.get("suite_hash", "")),
			"planned_duration_seconds": float(evaluation_case.get("duration_seconds", 0.0)),
			"episode_return": episode_return,
			"success": not crashed,
			"crashed": crashed,
			"terminated": crashed,
			"truncated": not crashed,
		})
	return records


func _minimal_replay_transition(logical_id: int, hindsight: bool) -> Dictionary:
	return {
		"logical_transition_id": logical_id,
		"actor_input": _zeros(DroneSACObservationEncoder.ACTOR_FEATURE_COUNT),
		"critic_input": _zeros(DroneSACObservationEncoder.CRITIC_FEATURE_COUNT),
		"policy_actions": _zeros(DroneSACObservationEncoder.ACTION_COUNT),
		"commands": _filled(DroneSACObservationEncoder.ACTION_COUNT, 0.5),
		"reward": float(logical_id) * 0.01,
		"next_actor_input": _zeros(DroneSACObservationEncoder.ACTOR_FEATURE_COUNT),
		"next_critic_input": _zeros(DroneSACObservationEncoder.CRITIC_FEATURE_COUNT),
		"terminated": false,
		"truncated": false,
		"done": false,
		"delta_seconds": 0.05,
		"hindsight": hindsight,
		"origin": "hindsight" if hindsight else "real",
	}


func _zeros(count: int) -> PackedFloat64Array:
	return _filled(count, 0.0)


func _filled(count: int, value: float) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(count)
	result.fill(value)
	return result


func _logical_ids(transitions: Array) -> Array[int]:
	var result: Array[int] = []
	for transition_value in transitions:
		if transition_value is Dictionary:
			result.append(int((transition_value as Dictionary).get("logical_transition_id", -1)))
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
