extends SceneTree

#######################################################
# Deterministic contracts for stationary turret workers. Run headlessly from the project root
# when Godot 4.6 is available.
#######################################################

var failure_count = 0
var assertion_count = 0
var test_root: Node3D
var turret: TurretPhysicalBody3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = Node3D.new()
	root.add_child(test_root)
	turret = TurretPhysicalBody3D.new()
	turret.loadout = MLBodyPresetLibrary.stationary_turret_loadout()
	turret.name = "TurretUnderTest"
	turret.auto_start_active = false
	test_root.add_child(turret)
	await process_frame
	turret.active = false
	_test_action_contract()
	_test_manual_keyboard_mapping()
	_test_servo_motion_is_rate_limited()
	_test_group_color_visual_contract()
	_test_observation_and_feature_contract()
	_test_turret_rewards()
	_test_trainer_rl_invariants()
	_test_checkpoint_score_sentinels_round_trip()
	_test_optimizer_swap_preserves_old_policy_interval()
	_test_stale_turret_policy_boundary_is_discarded()
	_test_background_step_accounting_reaches_trainer()
	_test_precision_tracking_state_contract()
	_test_manual_override_discards_manual_interval_time()
	_test_multi_turret_group_placement_contract()
	_test_spatial_hash_target_and_threat_contract()
	_test_projectile_hit_contract()
	_test_synthetic_target_projectile_hit_contract()
	_test_group_reward_ui_aggregation()
	_test_turret_evaluator_occlusion_success_contract()
	_test_worker_camera_filter()
	_test_worker_checkpoint_registry()
	_test_checkpoint_room_metadata_is_sanitized()
	_test_loadout_json_round_trip()
	_test_incomplete_loadout_does_not_invent_preset_parts()
	_test_invalid_turret_reset_fails_closed()
	_test_evaluation_threat_turrets_use_accepted_preset_body()
	_test_existing_workers_expose_turret_features()
	_test_drone_combat_adapter_identity()
	_test_rebuilt_turret_ui_avoids_object_capturing_lambdas()
	print("Turret assertions: %d, failures: %d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_action_contract() -> void:
	var commands = PackedFloat64Array([0.5, -0.25, 1.0])
	var action = TurretMLAction.from_commands(commands)
	var round_trip = TurretMLAction.packed_commands(action)
	_expect(
		round_trip.size() == TurretMLAction.ACTION_COUNT
		and _arrays_close(round_trip, commands),
		"turret yaw, pitch, and trigger commands round-trip without remapping"
	)
	_expect(
		TurretMLAction.from_commands(PackedFloat64Array([NAN, 0.0, 0.0])).is_empty(),
		"non-finite turret actions are rejected"
	)
	_expect(
		TurretMLAction.packed_commands({
			"schema_version": TurretMLAction.SCHEMA_VERSION,
			"yaw_drive": {"broken": true},
			"pitch_drive": 0.0,
			"trigger": 0.5,
		}).is_empty(),
		"wrong-type turret action fields are rejected without a numeric cast failure"
	)


func _test_manual_keyboard_mapping() -> void:
	_expect(
		TurretTrainingRoomUI.keyboard_yaw_drive(true, false) > 0.0,
		"A/left applies Godot-positive yaw so the barrel turns left"
	)
	_expect(
		TurretTrainingRoomUI.keyboard_yaw_drive(false, true) < 0.0,
		"D/right applies Godot-negative yaw so the barrel turns right"
	)
	_expect(
		is_zero_approx(TurretTrainingRoomUI.keyboard_yaw_drive(true, true)),
		"opposed manual yaw keys cancel cleanly"
	)


func _test_group_color_visual_contract() -> void:
	var legacy_label: Label3D = Label3D.new()
	legacy_label.name = "TrainingGroupLabel"
	turret.add_child(legacy_label)
	var expected_color: Color = Color(0.22, 0.68, 0.91, 1.0)
	turret.set_visual_color(expected_color)
	var colored_meshes: Array[MeshInstance3D] = [
		turret.base_mesh_instance,
		turret.head_mesh_instance,
		turret.barrel_mesh_instance,
	]
	var all_colored: bool = true
	for mesh_instance: MeshInstance3D in colored_meshes:
		if not is_instance_valid(mesh_instance):
			all_colored = false
			break
		var material: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
		if material == null or not _colors_close(material.albedo_color, expected_color):
			all_colored = false
			break
	_expect(
		all_colored,
		"turret base, head, and barrel use the worker-group color"
	)
	_expect(
		turret.get_node_or_null("TrainingGroupLabel") == null,
		"turret group identity is visualized by body color without the old floating label"
	)


func _test_servo_motion_is_rate_limited() -> void:
	turret.reset_body(Transform3D.IDENTITY, 101)
	turret.active = false
	_expect(turret.submit_manual_controls(1.0, 1.0, 0.0), "manual turret controls use the model action contract")
	for _step in range(100):
		turret._integrate_yaw(0.02)
		turret._integrate_pitch(0.02)
	var maximum_yaw_speed = deg_to_rad(turret.loadout.base.maximum_yaw_speed_degrees_per_second)
	var maximum_pitch_speed = deg_to_rad(turret.loadout.gun.maximum_pitch_speed_degrees_per_second)
	_expect(
		absf(turret.yaw_velocity_radians_per_second) <= maximum_yaw_speed + 0.00001,
		"manual yaw is acceleration-driven and capped by the authored servo speed"
	)
	_expect(
		absf(turret.pitch_velocity_radians_per_second) <= maximum_pitch_speed + 0.00001,
		"manual pitch is acceleration-driven and capped by the authored servo speed"
	)
	_expect(
		turret.pitch_angle_radians <= deg_to_rad(turret.loadout.gun.maximum_pitch_degrees) + 0.00001,
		"the gun cannot rotate above its physical elevation stop"
	)
	var speed_before_braking = absf(turret.yaw_velocity_radians_per_second)
	turret.submit_manual_controls(0.0, 0.0, 0.0)
	turret._integrate_yaw(0.1)
	_expect(
		absf(turret.yaw_velocity_radians_per_second) < speed_before_braking,
		"releasing manual aim brakes the rotating base instead of stopping it unrealistically"
	)


func _test_observation_and_feature_contract() -> void:
	turret.reset_body(Transform3D.IDENTITY, 202)
	turret.active = false
	var target_position = turret.muzzle_position_world() + Vector3(4.0, 1.0, -12.0)
	var direct = (target_position - turret.muzzle_position_world()).normalized()
	var probe = {
		"present": true,
		"is_combat_target": true,
		"is_shootable_target": true,
		"stable_id": "entity:drone:77",
		"target_kind": "drone",
		"entity_id": 77,
		"entity_kind": "drone",
		"position_world": target_position,
		"velocity_world": Vector3(2.0, 0.0, 0.0),
		"radius_m": 0.5,
		"distance_m": turret.muzzle_position_world().distance_to(target_position),
		"direct_direction_world": direct,
		"intercept_direction_world": direct,
		"line_of_sight": true,
		"within_range": true,
		"within_pitch_arc": true,
	}
	var observation = TurretMLObservation.capture(
		turret,
		probe,
		0.25,
		TurretMLAction.neutral_commands()
	)
	var features = TurretMLFeatureEncoder.encode(observation)
	_expect(TurretMLObservation.is_valid(observation), "a stationary turret produces a valid versioned observation")
	_expect(
		features.size() == TurretMLFeatureEncoder.FEATURE_COUNT,
		"the turret policy receives the declared fixed feature count"
	)
	_expect(_all_finite(features), "every turret observation feature is finite")
	var target_section: Dictionary = observation.get("target", {})
	_expect(
		float(target_section.get("yaw_error_radians", 0.0)) < 0.0
		and float(target_section.get("pitch_error_radians", 0.0)) > 0.0,
		"turret observations expose signed intercept yaw/pitch errors instead of forcing the MLP to reconstruct servo error from trigonometry"
	)
	_expect(
		TurretMLFeatureEncoder.FEATURE_NAMES.size() == TurretMLFeatureEncoder.FEATURE_COUNT
		and _unique_string_count(TurretMLFeatureEncoder.FEATURE_NAMES) == TurretMLFeatureEncoder.FEATURE_COUNT,
		"every turret input has one unique diagnostic name"
	)
	var combat_feature_index: int = TurretMLFeatureEncoder.FEATURE_NAMES.find("target_is_combat")
	var shootable_feature_index: int = TurretMLFeatureEncoder.FEATURE_NAMES.find("target_is_shootable")
	var synthetic_observation: Dictionary = observation.duplicate(true)
	(synthetic_observation.get("target", {}) as Dictionary)["is_combat_target"] = false
	var synthetic_features: PackedFloat64Array = TurretMLFeatureEncoder.encode(synthetic_observation)
	var aim_only_observation: Dictionary = synthetic_observation.duplicate(true)
	(aim_only_observation.get("target", {}) as Dictionary)["is_shootable_target"] = false
	var aim_only_features: PackedFloat64Array = TurretMLFeatureEncoder.encode(aim_only_observation)
	_expect(
		combat_feature_index >= 0
		and shootable_feature_index >= 0
		and features[combat_feature_index] > 0.9
		and synthetic_features.size() == TurretMLFeatureEncoder.FEATURE_COUNT
		and synthetic_features[combat_feature_index] < -0.9
		and synthetic_features[shootable_feature_index] > 0.9
		and aim_only_features.size() == TurretMLFeatureEncoder.FEATURE_COUNT
		and aim_only_features[shootable_feature_index] < -0.9,
		"the turret policy can distinguish live combat, synthetic shootable, and aim-only routed objectives"
	)
	var invalid = observation.duplicate(true)
	(invalid["body"] as Dictionary)["yaw_velocity_radians_per_second"] = NAN
	_expect(
		not TurretMLObservation.is_valid(invalid)
		and TurretMLFeatureEncoder.encode(invalid).is_empty(),
		"non-finite turret observations are rejected before reaching the policy"
	)
	var adapter = TurretMLBodyAdapter.new(turret)
	adapter.set_context(probe, 0.25, TurretMLAction.neutral_commands(), {})
	turret.yaw_velocity_radians_per_second = NAN
	_expect(
		adapter.capture_observation().is_empty(),
		"the turret body adapter rejects non-finite snapshots before reward calculation"
	)
	turret.yaw_velocity_radians_per_second = 0.0


func _test_turret_rewards() -> void:
	var observation = _reward_observation(1.0, true, true, TurretMLAction.neutral_commands(), 0.0)
	var deck = TurretRewardDeck.new()
	var state = deck.reset_state(observation)
	var aimed = deck.step_reward(observation, observation, 1.0, state, {})
	_expect(
		float((aimed.get("components", {}) as Dictionary).get("aim", 0.0)) > 0.0,
		"holding a visible finite-speed intercept solution earns bounded aim reward"
	)
	var routed_objective: Dictionary = observation.duplicate(true)
	var routed_target: Dictionary = routed_objective.get("target", {})
	routed_target["is_combat_target"] = false
	routed_target["entity_id"] = 0
	routed_target["entity_kind"] = "training_target"
	routed_target["stable_id"] = "navigation:test"
	routed_target["target_kind"] = "navigation"
	var routed_state: Dictionary = deck.reset_state(routed_objective)
	var routed_aimed: Dictionary = deck.step_reward(
		routed_objective, routed_objective, 0.05, routed_state, {}
	)
	_expect(
		float((routed_aimed.get("components", {}) as Dictionary).get("aim", 0.0)) > 0.0
		and not bool((routed_state.get("last_target_debug", {}) as Dictionary).get(
			"is_combat_target", true
		)),
		"the routed navigation objective earns dense turret aim reward even without a damageable combatant"
	)
	var routed_outside_pitch: Dictionary = routed_objective.duplicate(true)
	(routed_outside_pitch.get("target", {}) as Dictionary)["within_pitch_arc"] = false
	var routed_outside_pitch_reward: Dictionary = deck.step_reward(
		routed_outside_pitch, routed_outside_pitch, 0.05, routed_state, {}
	)
	_expect(
		float((routed_outside_pitch_reward.get("components", {}) as Dictionary).get("aim", 0.0)) > 0.0,
		"aim shaping remains active while a valid objective is temporarily outside the gun pitch envelope"
	)
	var routed_shot: Dictionary = deck.step_reward(
		routed_objective,
		routed_objective,
		0.05,
		routed_state,
		{"shots_fired": 1, "hits": 0, "damage_dealt": 0.0, "misses": 0}
	)
	_expect(
		is_zero_approx(float((routed_shot.get("components", {}) as Dictionary).get(
			"shot_discipline", 0.0
		))),
		"an aligned routed range target is a viable synthetic shot instead of an impossible aim-only objective"
	)
	var badly_aimed: Dictionary = _reward_observation(
		-0.8, true, true, TurretMLAction.neutral_commands(), 0.0
	)
	var less_badly_aimed: Dictionary = _reward_observation(
		-0.4, true, true, TurretMLAction.neutral_commands(), 0.0
	)
	var turning_toward: Dictionary = deck.step_reward(
		badly_aimed, less_badly_aimed, 0.05, state, {}
	)
	_expect(
		float((turning_toward.get("components", {}) as Dictionary).get("aim", 0.0)) > 0.0,
		"turret aim shaping rewards moving toward the intercept solution even before the barrel is already nearly aligned"
	)
	var holding_away: Dictionary = deck.step_reward(
		badly_aimed, badly_aimed, 0.05, state, {}
	)
	_expect(
		float((holding_away.get("components", {}) as Dictionary).get("aim", 0.0)) < 0.0,
		"holding the turret pointed away from a reachable target costs aim reward instead of creating a zero-reward spinning refuge"
	)
	var occluded_aligned: Dictionary = _reward_observation(
		1.0, true, false, TurretMLAction.neutral_commands(), 0.0
	)
	var tracking_through_cover: Dictionary = deck.step_reward(
		occluded_aligned, occluded_aligned, 0.05, state, {}
	)
	_expect(
		float((tracking_through_cover.get("components", {}) as Dictionary).get("aim", 0.0)) > 0.0,
		"a selected reachable target keeps dense tracking reward through temporary wall occlusion while shot discipline remains responsible for withholding fire"
	)
	var spin_alignments: PackedFloat64Array = PackedFloat64Array([1.0, 0.0, -1.0, 0.0, 1.0])
	var spin_aim_reward: float = 0.0
	for spin_index in range(1, spin_alignments.size()):
		var spin_previous: Dictionary = _reward_observation(
			spin_alignments[spin_index - 1],
			true,
			true,
			TurretMLAction.neutral_commands(),
			0.0
		)
		var spin_current: Dictionary = _reward_observation(
			spin_alignments[spin_index],
			true,
			true,
			TurretMLAction.neutral_commands(),
			0.0
		)
		var spin_result: Dictionary = deck.step_reward(
			spin_previous, spin_current, 0.05, state, {}
		)
		spin_aim_reward += float(
			(spin_result.get("components", {}) as Dictionary).get("aim", 0.0)
		)
	_expect(
		absf(spin_aim_reward) <= 0.000001,
		"one complete constant-speed rotation cannot farm positive cumulative aim reward"
	)
	var hit = deck.step_reward(
		observation,
		observation,
		0.1,
		state,
		{"shots_fired": 1, "hits": 1, "damage_dealt": 18.0, "misses": 0}
	)
	_expect(
		float((hit.get("components", {}) as Dictionary).get("hit", 0.0)) > 1.0,
		"confirmed projectile hits dominate the turret reward signal"
	)
	var unsafe_observation = _reward_observation(0.0, true, true, TurretMLAction.neutral_commands(), 0.0)
	var unsafe = deck.step_reward(
		observation,
		unsafe_observation,
		0.1,
		state,
		{"shots_fired": 1, "hits": 0, "damage_dealt": 0.0, "misses": 1}
	)
	_expect(
		float((unsafe.get("components", {}) as Dictionary).get("shot_discipline", 0.0)) < 0.0,
		"firing while misaligned and missing is punished"
	)
	var no_target_observation = _reward_observation(1.0, false, true, TurretMLAction.neutral_commands(), 0.0)
	var no_target_shot = deck.step_reward(
		observation,
		no_target_observation,
		0.1,
		state,
		{"shots_fired": 1, "hits": 0, "damage_dealt": 0.0, "misses": 0}
	)
	_expect(
		float((no_target_shot.get("components", {}) as Dictionary).get("shot_discipline", 0.0)) < 0.0,
		"firing without an acquired target is punished even when the fallback ray is clear"
	)
	var exact_bad_shot = deck.step_reward(
		observation,
		observation,
		0.1,
		state,
		{
			"shots_fired": 1,
			"viable_shots": 0,
			"bad_shots": 1,
			"hits": 0,
			"damage_dealt": 0.0,
			"misses": 0,
		}
	)
	_expect(
		float((exact_bad_shot.get("components", {}) as Dictionary).get("shot_discipline", 0.0)) < 0.0,
		"shot discipline uses the exact firing-time alignment/LOS classification instead of the later reward-sampling pose"
	)
	var damaged_observation = _reward_observation(1.0, true, true, TurretMLAction.neutral_commands(), 10.0)
	var damaged = deck.step_reward(observation, damaged_observation, 0.1, state, {})
	_expect(
		float((damaged.get("components", {}) as Dictionary).get("damage_safety", 0.0)) < 0.0,
		"damage received is exposed as a separate negative turret component"
	)


func _test_trainer_rl_invariants() -> void:
	var observation = _reward_observation(
		0.9,
		true,
		true,
		TurretMLAction.neutral_commands(),
		0.0
	)
	var trainer = TurretPPOTrainer.new(515)
	var custom_architecture = TurretPPOTrainer.new(514, {
		"hidden_layer_width": 80,
		"hidden_layer_depth": 3,
	})
	_expect(
		custom_architecture.actor_critic.hidden_size == 80
		and custom_architecture.actor_critic.hidden_layer_count == 3,
		"fresh turret models honor configurable hidden width and depth"
	)
	trainer.config["rollout_size"] = 2
	trainer.config["minimum_update_transitions"] = 2
	trainer.config["epochs"] = 1
	trainer.config["batch_size"] = 1
	trainer._sanitize_config()
	var runtime_sample = trainer.sample_runtime_action(observation, true)
	var rich_sample = trainer.sample_action(observation, true)
	_expect(
		not runtime_sample.has("action")
		and not runtime_sample.has("observation")
		and rich_sample.has("action")
		and _arrays_close(
			runtime_sample.get("commands", PackedFloat64Array()),
			rich_sample.get("commands", PackedFloat64Array())
		),
		"the turret training hot path applies packed commands without building an action dictionary"
	)
	var invalid_next = observation.duplicate(true)
	(invalid_next["body"] as Dictionary)["yaw_velocity_radians_per_second"] = NAN
	var terminal_sample = trainer.sample_runtime_action(observation)
	_expect(
		trainer.add_transition(91, terminal_sample, -0.2, {}, true, false, 0.05),
		"turret PPO retains a destroyed-body transition without a successor tensor"
	)
	trainer.discard_incomplete_rollout()
	var invalid_duration_sample = trainer.sample_runtime_action(observation)
	_expect(
		not trainer.add_transition(
			92,
			invalid_duration_sample,
			0.0,
			observation,
			false,
			false,
			NAN
		),
		"turret PPO rejects non-finite transition durations"
	)
	var malformed_tensor_sample: Dictionary = trainer.sample_runtime_action(observation).duplicate(true)
	malformed_tensor_sample["commands"] = "broken"
	_expect(
		not trainer.add_transition(90, malformed_tensor_sample, 0.0, observation, false, false),
		"turret PPO rejects malformed action tensors before typed tensor access"
	)
	var contradictory_boundary_sample = trainer.sample_runtime_action(observation)
	_expect(
		not trainer.add_transition(
			93,
			contradictory_boundary_sample,
			0.0,
			observation,
			true,
			true,
			0.05
		),
		"turret PPO rejects contradictory terminated-and-truncated boundaries"
	)
	var rejected_sample = trainer.sample_action(observation)
	_expect(
		not trainer.add_transition(
			0,
			rejected_sample,
			0.0,
			invalid_next,
			false,
			false,
			0.05
		),
		"turret PPO rejects non-finite next-state tensors at the replay boundary"
	)
	var atomic_network = TurretPPOActorCritic.new(516)
	var actor_before_failed_load: PackedFloat64Array = atomic_network.actor.parameters.duplicate()
	var corrupt_state: Dictionary = atomic_network.to_state().duplicate(true)
	var corrupt_critic: Dictionary = (corrupt_state.get("critic", {}) as Dictionary).duplicate(true)
	var corrupt_parameters: Array = (corrupt_critic.get("parameters", []) as Array).duplicate()
	corrupt_parameters[0] = NAN
	corrupt_critic["parameters"] = corrupt_parameters
	corrupt_state["critic"] = corrupt_critic
	_expect(
		not atomic_network.load_state(corrupt_state)
		and _arrays_close(actor_before_failed_load, atomic_network.actor.parameters),
		"a corrupt turret critic cannot partially replace the live actor"
	)
	var malformed_network_metadata: Dictionary = atomic_network.to_state().duplicate(true)
	malformed_network_metadata["action_count"] = [1, 2, 3]
	_expect(
		not atomic_network.load_state(malformed_network_metadata),
		"turret network restore rejects wrong-type numeric metadata without throwing"
	)
	var corrupt_moment_state: Dictionary = atomic_network.to_state().duplicate(true)
	var corrupt_moments: Array = (corrupt_moment_state.get(
		"log_standard_deviation_first_moment", []
	) as Array).duplicate()
	corrupt_moments[0] = NAN
	corrupt_moment_state["log_standard_deviation_first_moment"] = corrupt_moments
	_expect(
		not atomic_network.load_state(corrupt_moment_state),
		"turret PPO rejects non-finite exploration optimizer moments"
	)
	for index in range(2):
		var sample = trainer.sample_runtime_action(observation)
		var next_sample = trainer.sample_runtime_action(observation)
		_expect(trainer.add_transition(
			0,
			sample,
			0.05,
			observation,
			false,
			index == 1,
			0.05,
			next_sample.get("actor_input", PackedFloat64Array()),
			float(next_sample.get("value", NAN))
		), "turret PPO accepts a finite direct-servo transition")
	var metrics = trainer.update_if_ready()
	_expect(
		not metrics.is_empty()
		and float(metrics.get("initial_log_probability_error_max", INF))
		<= TurretPPOTrainer.INITIAL_LOG_PROBABILITY_TOLERANCE
		and absf(float(metrics.get("initial_approximate_kl", INF))) <= 0.00000001,
		"turret PPO optimizes from the exact yaw/pitch/trigger producer policy"
	)
	_expect(
		int(metrics.get("completed_minibatches", 0)) == 2
		and is_finite(float(metrics.get("actor_gradient_norm_mean_pre_clip", NAN)))
		and is_finite(float(metrics.get("critic_gradient_norm_mean_pre_clip", NAN))),
		"turret gradient norms are averaged over optimizer minibatches"
	)
	var candidate = trainer.pending_evaluation_candidate()
	_expect(
		not candidate.is_empty() and not trainer.has_best_checkpoint(),
		"a turret training rollout nominates a frozen candidate without becoming Best"
	)
	var pending_checkpoint: Dictionary = trainer.to_checkpoint(
		MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature(),
		TurretRewardDeck.new().configuration_dictionary(),
		false
	).duplicate(true)
	var pending_training: Dictionary = (pending_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var tampered_candidate_network: Dictionary = (pending_training.get("candidate_network_state", {}) as Dictionary).duplicate(true)
	tampered_candidate_network["log_standard_deviation_optimizer_step"] = int(
		tampered_candidate_network.get("log_standard_deviation_optimizer_step", 0)
	) + 1
	pending_training["candidate_network_state"] = tampered_candidate_network
	pending_checkpoint["training"] = pending_training
	var tampered_candidate_restore = TurretPPOTrainer.new(5152)
	_expect(
		tampered_candidate_restore.load_checkpoint(
			pending_checkpoint,
			MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature()
		)
		and tampered_candidate_restore.pending_evaluation_candidate().is_empty()
		and not is_finite(tampered_candidate_restore.candidate_nomination_score),
		"turret restore discards pending evaluation state when the frozen policy hash no longer matches"
	)
	var malformed_pending_checkpoint: Dictionary = trainer.to_checkpoint(
		MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature(),
		TurretRewardDeck.new().configuration_dictionary(),
		false
	).duplicate(true)
	var malformed_pending_training: Dictionary = (malformed_pending_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var malformed_pending: Dictionary = (malformed_pending_training.get("pending_evaluation_candidate", {}) as Dictionary).duplicate(true)
	malformed_pending["evaluation_contract"] = 17
	malformed_pending_training["pending_evaluation_candidate"] = malformed_pending
	malformed_pending_checkpoint["training"] = malformed_pending_training
	var malformed_pending_restore = TurretPPOTrainer.new(5154)
	_expect(
		malformed_pending_restore.load_checkpoint(
			malformed_pending_checkpoint,
			MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature()
		)
		and malformed_pending_restore.pending_evaluation_candidate().is_empty(),
		"turret restore discards malformed nested Candidate metadata instead of failing mid-load"
	)
	var malformed_id_checkpoint: Dictionary = trainer.to_checkpoint(
		MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature(),
		TurretRewardDeck.new().configuration_dictionary(),
		false
	).duplicate(true)
	var malformed_id_training: Dictionary = (malformed_id_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	var malformed_id_pending: Dictionary = (malformed_id_training.get("pending_evaluation_candidate", {}) as Dictionary).duplicate(true)
	malformed_id_pending["candidate_id"] = []
	malformed_id_training["pending_evaluation_candidate"] = malformed_id_pending
	malformed_id_checkpoint["training"] = malformed_id_training
	var malformed_id_restore: TurretPPOTrainer = TurretPPOTrainer.new(5155)
	_expect(
		malformed_id_restore.load_checkpoint(
			malformed_id_checkpoint,
			MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature()
		)
		and malformed_id_restore.pending_evaluation_candidate().is_empty()
		and malformed_id_restore.pending_evaluation_candidate_id() == -1,
		"turret restore discards a pending Candidate with malformed identity before evaluator scheduling"
	)
	var records: Array[Dictionary] = []
	var plan: Dictionary = candidate.get("evaluation_plan", {})
	for case_value in plan.get("cases", []):
		var evaluation_case: Dictionary = case_value
		records.append({
			"scenario_id": str(evaluation_case.get("scenario_id", "")),
			"seed": int(evaluation_case.get("seed", 0)),
			"episode_return": 1.0,
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
		and bool(trainer.best_selection_summary().get("evaluation_verified", false)),
		"a complete turret fixed-seed suite promotes the exact frozen policy"
	)
	trainer.shuffle_rng.state = 22334455
	trainer.behavior_actor_critic.action_rng.state = 66778899
	var checkpoint = trainer.to_checkpoint(
		MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature(),
		TurretRewardDeck.new().configuration_dictionary(),
		true
	)
	var continuation_restore = TurretPPOTrainer.new(9991)
	_expect(
		continuation_restore.load_checkpoint(
			checkpoint,
			MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature()
		)
		and continuation_restore.random_seed == 515
		and continuation_restore.shuffle_rng.state == 22334455
		and continuation_restore.behavior_actor_critic.action_rng.state == 66778899,
		"turret training checkpoints preserve seed, shuffle RNG, and exploration RNG continuation"
	)
	_expect(
		checkpoint.get("discount_time_base", {}) is Dictionary
		and is_equal_approx(
			float((checkpoint.get("discount_time_base", {}) as Dictionary).get(
				"reference_interval_seconds",
				0.0
			)),
			0.05
		),
		"turret checkpoints record the real-time discount reference"
	)
	var corrupt_best_checkpoint: Dictionary = checkpoint.duplicate(true)
	var corrupt_best_training: Dictionary = (corrupt_best_checkpoint.get("training", {}) as Dictionary).duplicate(true)
	corrupt_best_training["best_network"] = {"invalid": true}
	corrupt_best_checkpoint["training"] = corrupt_best_training
	var corrupt_best_restore = TurretPPOTrainer.new(5153)
	_expect(
		corrupt_best_restore.load_checkpoint(
			corrupt_best_checkpoint,
			MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature()
		)
		and not corrupt_best_restore.has_best_checkpoint()
		and corrupt_best_restore.best_evaluation.is_empty(),
		"turret restore keeps the valid live policy but drops an unusable saved Best network"
	)


func _test_checkpoint_score_sentinels_round_trip() -> void:
	var signature: String = MLBodyPresetLibrary.stationary_turret_loadout().hardware_signature()
	var source: TurretPPOTrainer = TurretPPOTrainer.new(516)
	var checkpoint: Dictionary = source.to_checkpoint(signature)
	var restored: TurretPPOTrainer = TurretPPOTrainer.new(517)
	_expect(
		restored.load_checkpoint(checkpoint, signature)
		and not is_finite(restored.best_episode_score)
		and not is_finite(restored.candidate_nomination_score),
		"turret checkpoint preserves the no-score sentinel instead of inventing a zero nomination floor"
	)
	source.best_episode_score = -2.75
	source.candidate_nomination_score = -0.75
	checkpoint = source.to_checkpoint(signature)
	var negative_restore: TurretPPOTrainer = TurretPPOTrainer.new(518)
	_expect(
		negative_restore.load_checkpoint(checkpoint, signature)
		and is_equal_approx(negative_restore.best_episode_score, -2.75)
		and is_equal_approx(negative_restore.candidate_nomination_score, -0.75),
		"turret checkpoint distinguishes a real negative nomination score from no nomination"
	)


func _test_optimizer_swap_preserves_old_policy_interval() -> void:
	var coordinator_source: String = FileAccess.get_file_as_string(
		"res://ml/training/turret/turret_training_coordinator.gd"
	)
	var poll_start: int = coordinator_source.find("func _poll_group_optimizer")
	var poll_end: int = coordinator_source.find("\nfunc ", poll_start + 1)
	var poll_body: String = (
		coordinator_source.substr(poll_start, poll_end - poll_start)
		if poll_start >= 0 and poll_end > poll_start
		else ""
	)
	_expect(
		not coordinator_source.contains("func _resample_active_workers")
		and poll_body.contains("Do not resample a live turret in the middle of its current action interval")
		and poll_body.contains("_cancel_group_projectiles(group)"),
		"turret policy adoption leaves the open old-policy action interval intact until its normal decision boundary and cancels delayed old-policy projectiles"
	)


func _test_stale_turret_policy_boundary_is_discarded() -> void:
	var trainer: TurretPPOTrainer = TurretPPOTrainer.new(515092)
	var observation: Dictionary = _sample_observation()
	var stale_sample: Dictionary = trainer.sample_runtime_action(observation)
	var stale_revision: int = int(stale_sample.get("policy_revision", -1))
	trainer.behavior_policy_update = stale_revision + 1
	var environment_steps_before: int = trainer.environment_steps
	_expect(
		trainer.add_transition(
			0,
			stale_sample,
			1.0,
			observation,
			false,
			false,
			0.05
		)
		and trainer.rollout.is_empty()
		and trainer.environment_steps == environment_steps_before + 1,
		"a held turret action that straddles policy adoption is settled as an environment step but discarded from the new PPO rollout"
	)


func _test_background_step_accounting_reaches_trainer() -> void:
	var coordinator_source: String = FileAccess.get_file_as_string(
		"res://ml/training/turret/turret_training_coordinator.gd"
	)
	_expect(
		not coordinator_source.contains("episode_collects_training")
		and coordinator_source.contains("trainer.add_transition("),
		"turret coordinator always submits held-action boundaries to PPO so optimizer-time physical steps are counted before stale samples are discarded"
	)


func _test_precision_tracking_state_contract() -> void:
	var target_state: Dictionary = {
		"present": true,
		"line_of_sight": true,
		"within_range": true,
		"within_pitch_arc": true,
		"aim_alignment": 0.999,
	}
	_expect(
		TurretTrainingTargetSensor.is_precision_tracking_state(
			target_state,
			TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
		),
		"precision tracking accepts a reachable accurately aligned target"
	)
	var out_of_range: Dictionary = target_state.duplicate(false)
	out_of_range["within_range"] = false
	_expect(
		not TurretTrainingTargetSensor.is_precision_tracking_state(
			out_of_range,
			TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
		),
		"precision tracking cannot count an out-of-range target as evaluator success"
	)
	var outside_pitch: Dictionary = target_state.duplicate(false)
	outside_pitch["within_pitch_arc"] = false
	_expect(
		not TurretTrainingTargetSensor.is_precision_tracking_state(
			outside_pitch,
			TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
		),
		"precision tracking cannot count a target outside the servo pitch envelope"
	)


func _test_manual_override_discards_manual_interval_time() -> void:
	var coordinator = TurretTrainingCoordinator.new(test_root)
	var group = coordinator.create_group(991, "ManualTimer", Color.WHITE, 2)
	var manual_worker: Dictionary = {
		"id": 0,
		"last_action_sample": {"policy_revision": 0},
		"interval_reward": 4.0,
		"interval_elapsed_seconds": 7.5,
	}
	var autonomous_worker: Dictionary = {
		"id": 1,
		"last_action_sample": {"policy_revision": 0, "sentinel": "keep"},
		"interval_reward": 2.5,
		"interval_elapsed_seconds": 3.25,
	}
	group["workers"] = [manual_worker, autonomous_worker]
	var trainer: TurretPPOTrainer = group["trainer"] as TurretPPOTrainer
	trainer.rollout = [
		{"worker_id": 0, "sentinel": "manual"},
		{"worker_id": 1, "sentinel": "autonomous"},
	]
	trainer.rollout_policy_revision = 0
	trainer.rollout_start_network_state = trainer.behavior_actor_critic.to_runtime_state()
	_expect(
		coordinator.set_manual_override(991, true)
		and is_zero_approx(float(manual_worker.get("interval_reward", -1.0)))
		and is_zero_approx(float(manual_worker.get("interval_elapsed_seconds", -1.0)))
		and bool(manual_worker.get("manual_touched_this_episode", false))
		and is_equal_approx(float(autonomous_worker.get("interval_reward", -1.0)), 2.5)
		and is_equal_approx(float(autonomous_worker.get("interval_elapsed_seconds", -1.0)), 3.25)
		and str((autonomous_worker.get("last_action_sample", {}) as Dictionary).get("sentinel", "")) == "keep"
		and trainer.rollout.size() == 1
		and int(trainer.rollout[0].get("worker_id", -1)) == 1,
		"manual control resets only turret 0 and removes only its PPO fragment while autonomous siblings keep their live interval and rollout data"
	)
	manual_worker["interval_elapsed_seconds"] = 5.0
	autonomous_worker["interval_elapsed_seconds"] = 4.25
	_expect(
		coordinator.set_manual_override(991, false)
		and is_zero_approx(float(manual_worker.get("interval_elapsed_seconds", -1.0)))
		and is_equal_approx(float(autonomous_worker.get("interval_elapsed_seconds", -1.0)), 4.25)
		and bool(manual_worker.get("manual_touched_this_episode", false)),
		"leaving manual turret control cannot leak manual seconds and does not disturb autonomous siblings"
	)
	coordinator.remove_group(991)



func _test_multi_turret_group_placement_contract() -> void:
	var coordinator = TurretTrainingCoordinator.new(test_root)
	var group: Dictionary = coordinator.create_group(992, "PlacedTurret", Color.WHITE, 1)
	_expect(
		int(group.get("worker_count", 0)) == 1
		and TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT > 1,
		"a turret group starts with one worker but may own multiple independently placed workers"
	)
	_expect(
		not coordinator.set_group_active(992, true, Vector3.ZERO, 10.0, Vector3(20.0, 10.0, 20.0)),
		"an unplaced turret group cannot silently fall back to perimeter spawning"
	)
	var first_position: Vector3 = Vector3(3.25, 2.0, -4.5)
	var second_position: Vector3 = Vector3(-2.0, 1.5, 5.0)
	_expect(
		not coordinator.set_worker_count(992, 2),
		"generic worker-count changes cannot create an unplaced turret; growth must go through the + placement flow"
	)
	_expect(
		coordinator.set_group_worker_placement(992, 0, first_position, 35.0)
		and coordinator.set_group_active(992, true, Vector3.ZERO, 10.0, Vector3(20.0, 10.0, 20.0))
		and (group.get("workers", []) as Array).size() == 1,
		"a configured one-turret group can enter its live episode before another worker is placed"
	)
	var routed_target_position: Vector3 = first_position + Vector3(0.0, 1.0, -8.0)
	var routed_target_velocity: Vector3 = Vector3(2.5, 0.0, 0.0)
	coordinator.tick(
		0.05,
		Vector3.ZERO,
		10.0,
		Vector3(20.0, 10.0, 20.0),
		{
			992: {
				"available": true,
				"stable_id": "navigation:turret-992",
				"system_type_id": "navigation_path",
				"target_kind": "navigation",
				"position_world": routed_target_position,
				"velocity_world": routed_target_velocity,
				"radius_m": 0.9,
				"metadata": {},
			},
		}
	)
	var routed_workers: Array = group.get("workers", [])
	var routed_probe: Dictionary = (
		((routed_workers[0] as Dictionary).get("latest_target_probe", {}) as Dictionary)
		if not routed_workers.is_empty()
		else {}
	)
	_expect(
		bool(routed_probe.get("present", false))
		and not bool(routed_probe.get("is_combat_target", true))
		and bool(routed_probe.get("is_shootable_target", false))
		and str(routed_probe.get("stable_id", "")) == "navigation:turret-992"
		and (routed_probe.get("velocity_world", Vector3.ZERO) as Vector3).is_equal_approx(
			routed_target_velocity
		),
		"the turret coordinator forwards the complete routed navigation target instead of dropping it to an absent position-only fallback"
	)
	coordinator.set_group_active(992, false, Vector3.ZERO, 10.0, Vector3(20.0, 10.0, 20.0))
	var original_workers: Array = group.get("workers", [])
	var original_turret: TurretPhysicalBody3D = (
		(original_workers[0] as Dictionary).get("turret") as TurretPhysicalBody3D
		if not original_workers.is_empty() and original_workers[0] is Dictionary
		else null
	)
	_expect(
		coordinator.append_group_worker_placement(992, second_position, -20.0)
		and coordinator.group_worker_count(992) == 2
		and (group.get("workers", []) as Array).size() == 1
		and is_instance_valid(original_turret)
		and ((group.get("workers", []) as Array)[0] as Dictionary).get("turret") == original_turret
		and coordinator.group_worker_placement_transform(992, 0).origin.is_equal_approx(first_position)
		and coordinator.group_worker_placement_transform(992, 1).origin.is_equal_approx(second_position),
		"adding a placement while paused keeps the already placed turret visible until the new population is activated"
	)
	_expect(
		coordinator.set_group_active(992, true, Vector3.ZERO, 10.0, Vector3(20.0, 10.0, 20.0))
		and (group.get("workers", []) as Array).size() == 2,
		"an activated multi-turret group spawns every configured placement under the shared policy"
	)
	coordinator.set_group_active(992, false, Vector3.ZERO, 10.0, Vector3(20.0, 10.0, 20.0))
	var checkpoint: Dictionary = coordinator.save_checkpoint(992)
	var settings: Dictionary = checkpoint.get("room_settings", {}) as Dictionary
	var placements_value: Variant = settings.get("placements", [])
	_expect(
		placements_value is Array
		and (placements_value as Array).size() == 2
		and int(settings.get("worker_count", 0)) == 2,
		"turret checkpoints preserve every worker placement and the shared worker count"
	)
	var malformed_checkpoint: Dictionary = checkpoint.duplicate(true)
	var malformed_settings: Dictionary = (malformed_checkpoint.get("room_settings", {}) as Dictionary).duplicate(true)
	malformed_settings["placements"] = [17, {"configured": false}]
	malformed_checkpoint["room_settings"] = malformed_settings
	_expect(
		not coordinator.load_checkpoint(992, malformed_checkpoint),
		"checkpoint restore rejects incomplete multi-turret placement state before replacing the live group"
	)
	_expect(
		coordinator.set_group_target_worker(992, -99)
		and int(group.get("target_worker_group_id", 0)) == -1,
		"negative turret target-group identifiers normalize to automatic targeting"
	)
	coordinator.remove_group(992)


func _test_spatial_hash_target_and_threat_contract() -> void:
	turret.reset_body(Transform3D.IDENTITY, 303)
	turret.active = false
	var spatial_hash = ServerSpatialHash3D.new(4.0)
	var turret_adapter = TurretTrainingCombatantAdapter.new(turret, 301, 3, 0, 2)
	var observer_body = Node3D.new()
	observer_body.name = "ThreatObserver"
	test_root.add_child(observer_body)
	observer_body.global_position = turret.muzzle_position_world() + Vector3.FORWARD * 10.0
	var observer = TrainingCombatantAdapter.new(observer_body, &"drone", 302, 4, 0, 1)
	var preferred_body = Node3D.new()
	preferred_body.name = "PreferredThreatObserver"
	test_root.add_child(preferred_body)
	preferred_body.global_position = turret.muzzle_position_world() + Vector3.FORWARD * 18.0
	var preferred_observer = TrainingCombatantAdapter.new(preferred_body, &"drone", 303, 5, 0, 1)
	var preferred_sibling_body: Node3D = Node3D.new()
	preferred_sibling_body.name = "PreferredGroupSibling"
	test_root.add_child(preferred_sibling_body)
	preferred_sibling_body.global_position = turret.muzzle_position_world() + Vector3.FORWARD * 8.0
	var preferred_sibling: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		preferred_sibling_body, &"drone", 304, 5, 1, 1
	)
	var unreachable_body: Node3D = Node3D.new()
	unreachable_body.name = "PitchUnreachableTarget"
	test_root.add_child(unreachable_body)
	unreachable_body.global_position = turret.muzzle_position_world() + Vector3.UP * 5.0
	var unreachable_adapter: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		unreachable_body, &"drone", 305, 6, 0, 1
	)
	spatial_hash.register_entity(
		turret_adapter.spatial_key(), turret, turret_adapter.entity_kind,
		turret_adapter.entity_id, turret_adapter.metadata()
	)
	spatial_hash.register_entity(
		observer.spatial_key(), observer_body, observer.entity_kind,
		observer.entity_id, observer.metadata()
	)
	spatial_hash.register_entity(
		preferred_observer.spatial_key(), preferred_body, preferred_observer.entity_kind,
		preferred_observer.entity_id, preferred_observer.metadata()
	)
	spatial_hash.register_entity(
		preferred_sibling.spatial_key(), preferred_sibling_body, preferred_sibling.entity_kind,
		preferred_sibling.entity_id, preferred_sibling.metadata()
	)
	spatial_hash.register_entity(
		unreachable_adapter.spatial_key(), unreachable_body, unreachable_adapter.entity_kind,
		unreachable_adapter.entity_id, unreachable_adapter.metadata()
	)
	_expect(
		spatial_hash.has_kind(&"turret")
		and spatial_hash.kind_count(&"turret") == 1
		and spatial_hash.kind_count(&"drone") == 4,
		"the shared hash tracks entity-kind counts for zero-cost absent-sensor fast paths"
	)
	var target_probe = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		spatial_hash,
		null,
		Vector3.ZERO,
		80.0
	)
	_expect(
		bool(target_probe.get("present", false))
		and int(target_probe.get("entity_id", 0)) == observer.entity_id,
		"the turret acquires enemy workers through the shared entity spatial hash"
	)
	var preferred_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		spatial_hash,
		null,
		Vector3.ZERO,
		80.0,
		5
	)
	_expect(
		bool(preferred_probe.get("present", false))
		and int(preferred_probe.get("entity_id", 0)) == preferred_sibling.entity_id,
		"an explicitly selected worker group hard-filters turret acquisition even when another enemy is closer"
	)
	var exact_member_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		spatial_hash,
		null,
		Vector3.ZERO,
		80.0,
		5,
		preferred_observer.entity_id
	)
	_expect(
		int(exact_member_probe.get("entity_id", 0)) == preferred_observer.entity_id,
		"the gun honors the exact live member selected by the worker-group target handler instead of independently snapping to the nearest sibling"
	)
	preferred_observer.set_simulation_active(false)
	var paused_member_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		spatial_hash,
		null,
		Vector3.ZERO,
		80.0,
		5,
		preferred_observer.entity_id
	)
	_expect(
		int(paused_member_probe.get("entity_id", 0)) == preferred_sibling.entity_id
		and not preferred_observer.receive_training_hit(
			1.0, turret_adapter.entity_id, preferred_body.global_position, 99
		)
		and not preferred_observer.has_pending_combat_events(),
		"a paused training combatant stays registered but cannot be targeted or accumulate combat reward events"
	)
	preferred_observer.set_simulation_active(true)
	var unreachable_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		spatial_hash,
		null,
		Vector3.ZERO,
		80.0,
		6
	)
	_expect(
		bool(unreachable_probe.get("present", false))
		and int(unreachable_probe.get("entity_id", 0)) == unreachable_adapter.entity_id
		and not bool(unreachable_probe.get("within_pitch_arc", true)),
		"an explicitly selected live target stays observable outside the gun pitch arc while reachability is reported separately"
	)
	_expect(
		not TurretTrainingTargetSensor.is_viable_shot(turret, unreachable_probe, 0.9),
		"an unreachable explicit target cannot be classified as a viable shot"
	)
	var navigation_position: Vector3 = turret.muzzle_position_world() + Vector3.FORWARD * 12.0
	var navigation_velocity: Vector3 = Vector3(3.0, 0.0, 0.0)
	var navigation_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		ServerSpatialHash3D.new(4.0),
		null,
		navigation_position,
		80.0,
		-1,
		-1,
		{
			"available": true,
			"stable_id": "navigation:test-marker",
			"target_kind": "navigation",
			"shootable": true,
			"position_world": navigation_position,
			"velocity_world": navigation_velocity,
			"radius_m": 0.75,
		}
	)
	_expect(
		bool(navigation_probe.get("present", false))
		and not bool(navigation_probe.get("is_combat_target", true))
		and int(navigation_probe.get("entity_id", -1)) == 0
		and str(navigation_probe.get("stable_id", "")) == "navigation:test-marker"
		and (navigation_probe.get("velocity_world", Vector3.ZERO) as Vector3).is_equal_approx(
			navigation_velocity
		)
		and float(TurretTrainingTargetSensor.aim_alignment(turret, navigation_probe)) > 0.9
		and bool(navigation_probe.get("is_shootable_target", false))
		and TurretTrainingTargetSensor.is_viable_shot(turret, navigation_probe, 0.9),
		"a routed navigation marker is a real moving synthetic range target and can be a viable shot without pretending to be a combat body"
	)
	var navigation_with_ambient_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		spatial_hash,
		null,
		navigation_position,
		80.0,
		-1,
		-1,
		{
			"available": true,
			"stable_id": "navigation:authoritative-marker",
			"target_kind": "navigation",
			"shootable": true,
			"position_world": navigation_position,
			"velocity_world": navigation_velocity,
			"radius_m": 0.75,
		}
	)
	_expect(
		str(navigation_with_ambient_probe.get("stable_id", "")) == "navigation:authoritative-marker"
		and not bool(navigation_with_ambient_probe.get("is_combat_target", true)),
		"the authored Path training target remains authoritative instead of being silently replaced by an ambient worker"
	)
	var missing_explicit_group_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_adapter,
		spatial_hash,
		null,
		navigation_position,
		80.0,
		999,
		-1,
		{
			"available": true,
			"stable_id": "navigation:not-selected-group",
			"target_kind": "navigation",
			"shootable": true,
			"position_world": navigation_position,
			"velocity_world": navigation_velocity,
			"radius_m": 0.75,
			"metadata": {},
		}
	)
	_expect(
		not bool(missing_explicit_group_probe.get("present", true))
		and not bool(missing_explicit_group_probe.get("is_shootable_target", true)),
		"an unavailable explicit worker-group target cannot silently fall back to the unrelated path range target"
	)
	var threat_probe = TrainingTurretThreatSensor.acquire(observer, spatial_hash, null, 80.0)
	_expect(
		bool(threat_probe.get("present", false))
		and int(threat_probe.get("entity_id", 0)) == turret_adapter.entity_id,
		"a drone-style combatant perceives the same turret through the polymorphic threat sensor"
	)
	var indexed_turret_kinds: Array[StringName] = [&"turret"]
	var indexed_turret_keys: Array[StringName] = spatial_hash.keys_for_kinds(indexed_turret_kinds)
	var spatial_debug: Dictionary = spatial_hash.get_debug_state()
	_expect(
		indexed_turret_keys.size() == 1
		and indexed_turret_keys[0] == turret_adapter.spatial_key(),
		"long-range combat perception uses the compact per-kind entity index"
	)
	_expect(
		int(spatial_debug.get("query_rebuilds", -1)) == 0
		and int(spatial_debug.get("query_cache_count", -1)) == 0,
		"turret target and threat sensors do not register enormous 80-metre cell-query caches"
	)
	_expect(
		float(threat_probe.get("distance_m", 0.0)) > 0.0
		and float(threat_probe.get("threat_level", -1.0)) >= 0.0
		and float(threat_probe.get("threat_level", 2.0)) <= 1.0,
		"turret distance and danger are finite bounded perception values"
	)
	var out_of_range_target = TurretTrainingTargetSensor.acquire(
		turret, turret_adapter, spatial_hash, null, Vector3.ZERO, 2.0
	)
	var out_of_range_threat = TrainingTurretThreatSensor.acquire(
		observer, spatial_hash, null, 2.0
	)
	_expect(
		not bool(out_of_range_target.get("present", true))
		and not bool(out_of_range_threat.get("present", true)),
		"spatial-hash broad-phase cells cannot expose entities beyond the requested sensor range"
	)
	spatial_hash.unregister_entity(turret_adapter.spatial_key())
	_expect(
		not spatial_hash.has_kind(&"turret")
		and spatial_hash.kind_count(&"turret") == 0,
		"unregistering the last turret activates the no-turret threat-sensor fast path"
	)
	_expect(
		spatial_hash.keys_for_kinds(indexed_turret_kinds).is_empty(),
		"unregistering an entity also removes it from the compact kind index"
	)
	spatial_hash.unregister_entity(observer.spatial_key())
	spatial_hash.unregister_entity(preferred_observer.spatial_key())
	spatial_hash.unregister_entity(preferred_sibling.spatial_key())
	spatial_hash.unregister_entity(unreachable_adapter.spatial_key())
	observer_body.queue_free()
	preferred_body.queue_free()
	preferred_sibling_body.queue_free()
	unreachable_body.queue_free()


func _test_projectile_hit_contract() -> void:
	turret.reset_body(Transform3D.IDENTITY, 404)
	turret.active = false
	var target_body = Node3D.new()
	target_body.name = "ProjectileTarget"
	test_root.add_child(target_body)
	target_body.global_position = turret.muzzle_position_world() + Vector3.FORWARD * 6.0
	var shooter_adapter = TurretTrainingCombatantAdapter.new(turret, 401, 1, 0, 2)
	var target_adapter = TrainingCombatantAdapter.new(target_body, &"drone", 402, 2, 0, 1)
	var spatial_hash = ServerSpatialHash3D.new(4.0)
	spatial_hash.register_entity(
		target_adapter.spatial_key(), target_body, target_adapter.entity_kind,
		target_adapter.entity_id, target_adapter.metadata()
	)
	var projectile = TurretTrainingProjectile3D.new()
	test_root.add_child(projectile)
	var direction = (target_adapter.aim_point_world() - turret.muzzle_position_world()).normalized()
	var configured = projectile.configure({
		"origin": turret.muzzle_position_world(),
		"direction": direction,
		"speed_mps": 100.0,
		"damage": 18.0,
		"maximum_range_m": 20.0,
		"shooter": turret,
	}, shooter_adapter, spatial_hash, null)
	_expect(configured, "a valid turret shot creates a finite-speed training projectile")
	var paused_projectile_position: Vector3 = projectile.global_position
	projectile.set_simulation_paused(true)
	projectile._physics_process(0.1)
	_expect(
		projectile.global_position.is_equal_approx(paused_projectile_position)
		and not projectile.resolved_once,
		"ordinary turret pause freezes an in-flight round instead of cancelling or advancing it"
	)
	projectile.set_simulation_paused(false)
	projectile._physics_process(0.1)
	var target_events = target_adapter.consume_combat_events()
	var weapon_events = turret.consume_weapon_events()
	_expect(
		int(target_events.get("hit_count", 0)) == 1
		and is_equal_approx(float(target_events.get("damage_taken", 0.0)), 18.0),
		"projectile impact reaches the shared victim hit ledger"
	)
	_expect(
		int(weapon_events.get("hits", 0)) == 1
		and is_equal_approx(float(weapon_events.get("damage_dealt", 0.0)), 18.0),
		"the firing turret receives one confirmed hit event for reward calculation"
	)
	var cancelled_projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	test_root.add_child(cancelled_projectile)
	_expect(
		cancelled_projectile.configure({
			"origin": turret.muzzle_position_world(),
			"direction": direction,
			"speed_mps": 100.0,
			"damage": 18.0,
			"maximum_range_m": 20.0,
			"shooter": turret,
		}, shooter_adapter, spatial_hash, null),
		"a second projectile can be created for episode-boundary cancellation coverage"
	)
	cancelled_projectile.cancel_without_reward()
	cancelled_projectile._physics_process(0.1)
	var cancelled_events: Dictionary = turret.consume_weapon_events()
	_expect(
		int(cancelled_events.get("hits", 0)) == 0
		and int(cancelled_events.get("misses", 0)) == 0,
		"cancelled in-flight rounds cannot deposit delayed hit/miss reward into a later episode or policy"
	)
	var deck: TurretRewardDeck = TurretRewardDeck.new()
	var reward_observation: Dictionary = _reward_observation(1.0, true, true, TurretMLAction.neutral_commands(), 0.0)
	var reward_state: Dictionary = deck.reset_state(reward_observation)
	var rewarded_hit: Dictionary = deck.step_reward(
		reward_observation, reward_observation, 0.05, reward_state, weapon_events
	)
	_expect(
		float((rewarded_hit.get("components", {}) as Dictionary).get("hit", 0.0)) > 0.0,
		"the real projectile hit ledger feeds a positive turret hit reward rather than only a visual hit event"
	)

	# Explicit group targeting must not let an accidental body from another group farm hit reward.
	var off_target_body: Node3D = Node3D.new()
	off_target_body.name = "OffTargetProjectileBody"
	test_root.add_child(off_target_body)
	off_target_body.global_position = turret.muzzle_position_world() + Vector3.FORWARD * 4.0
	var off_target_adapter: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		off_target_body, &"drone", 403, 9, 0, 1
	)
	var off_target_hash: ServerSpatialHash3D = ServerSpatialHash3D.new(4.0)
	off_target_hash.register_entity(
		off_target_adapter.spatial_key(), off_target_body, off_target_adapter.entity_kind,
		off_target_adapter.entity_id, off_target_adapter.metadata()
	)
	var off_target_projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	test_root.add_child(off_target_projectile)
	var off_target_direction: Vector3 = (
		off_target_adapter.aim_point_world() - turret.muzzle_position_world()
	).normalized()
	_expect(
		off_target_projectile.configure({
			"origin": turret.muzzle_position_world(),
			"direction": off_target_direction,
			"speed_mps": 100.0,
			"damage": 18.0,
			"maximum_range_m": 20.0,
			"shooter": turret,
		}, shooter_adapter, off_target_hash, null, 2),
		"an explicit reward target group can be attached to a projectile"
	)
	off_target_projectile._physics_process(0.1)
	var off_target_weapon_events: Dictionary = turret.consume_weapon_events()
	_expect(
		int(off_target_weapon_events.get("hits", 0)) == 0
		and int(off_target_weapon_events.get("misses", 0)) == 1,
		"an accidental hit on another group is physical but is not credited as target-group hit reward"
	)
	off_target_body.queue_free()
	target_body.queue_free()


func _test_synthetic_target_projectile_hit_contract() -> void:
	turret.reset_body(Transform3D.IDENTITY, 405)
	turret.active = false
	turret.consume_weapon_events()
	var shooter_adapter: TurretTrainingCombatantAdapter = TurretTrainingCombatantAdapter.new(
		turret, 451, 1, 0, 2
	)
	var spatial_hash: ServerSpatialHash3D = ServerSpatialHash3D.new(4.0)
	var target_position: Vector3 = turret.muzzle_position_world() + Vector3.FORWARD * 6.0
	var routed_target: Dictionary = {
		"available": true,
		"present": true,
		"is_combat_target": false,
		"is_shootable_target": true,
		"stable_id": "navigation:synthetic-hit",
		"target_kind": "navigation",
		"entity_id": 0,
		"entity_kind": "training_target",
		"position_world": target_position,
		"velocity_world": Vector3.ZERO,
		"radius_m": 0.75,
		"distance_m": 6.0,
		"direct_direction_world": Vector3.FORWARD,
		"intercept_direction_world": Vector3.FORWARD,
		"line_of_sight": true,
		"within_range": true,
		"within_pitch_arc": true,
	}
	_expect(
		TurretTrainingTargetSensor.is_viable_shot(
			turret, routed_target, TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
		),
		"the routed training marker is a real viable turret shot target even without a combat adapter"
	)
	var projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	test_root.add_child(projectile)
	_expect(
		projectile.configure({
			"origin": turret.muzzle_position_world(),
			"direction": Vector3.FORWARD,
			"speed_mps": 100.0,
			"damage": 18.0,
			"maximum_range_m": 20.0,
			"shooter": turret,
		}, shooter_adapter, spatial_hash, null, -1, routed_target),
		"a projectile can retain a synthetic routed reward target"
	)
	projectile._physics_process(0.1)
	var weapon_events: Dictionary = turret.consume_weapon_events()
	_expect(
		int(weapon_events.get("hits", 0)) == 1
		and int(weapon_events.get("misses", 0)) == 0
		and is_zero_approx(float(weapon_events.get("damage_dealt", -1.0))),
		"crossing the visible routed target sphere produces one confirmed hit without inventing combat damage"
	)
	var observation: Dictionary = TurretMLObservation.capture(
		turret, routed_target, 0.2, TurretMLAction.neutral_commands(), {}
	)
	var deck: TurretRewardDeck = TurretRewardDeck.new()
	var state: Dictionary = deck.reset_state(observation)
	var rewarded: Dictionary = deck.step_reward(
		observation, observation, 0.05, state, weapon_events
	)
	_expect(
		float((rewarded.get("components", {}) as Dictionary).get("hit", 0.0)) > 0.0
		and int((state.get("weapon_event_totals", {}) as Dictionary).get("hits", 0)) == 1,
		"a synthetic routed impact reaches both Hit targets reward and its visible fire telemetry"
	)

	# A random body crossing the shot line must not steal synthetic-target credit. It is a physical
	# collision and therefore a miss for this task, even though the body still receives the hit.
	turret.reset_body(Transform3D.IDENTITY, 406)
	turret.active = false
	var blocker_body: Node3D = Node3D.new()
	blocker_body.name = "SyntheticTargetBlocker"
	test_root.add_child(blocker_body)
	blocker_body.global_position = turret.muzzle_position_world() + Vector3.FORWARD * 3.0
	var blocker_adapter: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		blocker_body, &"drone", 452, 99, 0, 1
	)
	spatial_hash.register_entity(
		blocker_adapter.spatial_key(), blocker_body, blocker_adapter.entity_kind,
		blocker_adapter.entity_id, blocker_adapter.metadata()
	)
	var blocked_projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	test_root.add_child(blocked_projectile)
	_expect(
		blocked_projectile.configure({
			"origin": turret.muzzle_position_world(),
			"direction": Vector3.FORWARD,
			"speed_mps": 100.0,
			"damage": 18.0,
			"maximum_range_m": 20.0,
			"shooter": turret,
		}, shooter_adapter, spatial_hash, null, -1, routed_target),
		"a synthetic-target projectile can coexist with unrelated combat bodies"
	)
	blocked_projectile._physics_process(0.1)
	var blocked_events: Dictionary = turret.consume_weapon_events()
	_expect(
		int(blocked_events.get("hits", 0)) == 0
		and int(blocked_events.get("misses", 0)) == 1,
		"hitting an unrelated body before the routed marker cannot farm synthetic Hit targets reward"
	)
	spatial_hash.unregister_entity(blocker_adapter.spatial_key())
	blocker_body.queue_free()

	# A real episode horizon must settle rounds that are still in flight as misses. Policy/config
	# boundaries use cancel_without_reward() instead and intentionally do not contaminate the next
	# decision context.
	turret.consume_weapon_events()
	var horizon_projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	test_root.add_child(horizon_projectile)
	_expect(
		horizon_projectile.configure({
			"origin": turret.muzzle_position_world(),
			"direction": Vector3.FORWARD,
			"speed_mps": 10.0,
			"damage": 18.0,
			"maximum_range_m": 20.0,
			"shooter": turret,
		}, shooter_adapter, spatial_hash, null, -1, routed_target),
		"an unresolved projectile can be created for terminal-horizon accounting"
	)
	horizon_projectile.cancel_as_miss()
	var horizon_events: Dictionary = turret.consume_weapon_events()
	_expect(
		int(horizon_events.get("hits", 0)) == 0
		and int(horizon_events.get("misses", 0)) == 1,
		"a projectile still in flight at a true task horizon is recorded as a miss instead of escaping shot-discipline reward"
	)


func _test_group_reward_ui_aggregation() -> void:
	var group: Dictionary = {
		"workers": [
			{"reward_state": {
				"last_components": {"hit": 0.0},
				"episode_totals": {"hit": 0.0},
				"weapon_event_totals": {"shots_fired": 2, "hits": 0, "misses": 1},
			}},
			{"reward_state": {
				"last_components": {"hit": 1.25},
				"episode_totals": {"hit": 2.5},
				"weapon_event_totals": {"shots_fired": 3, "hits": 2, "misses": 1},
			}},
		],
	}
	var state: Dictionary = DroneTrainingRoom._worker_group_reward_ui_state(group)
	_expect(
		is_equal_approx(float((state.get("last_components", {}) as Dictionary).get("hit", 0.0)), 0.625)
		and is_equal_approx(float((state.get("episode_totals", {}) as Dictionary).get("hit", 0.0)), 1.25)
		and int((state.get("weapon_event_totals", {}) as Dictionary).get("hits", 0)) == 2,
		"multi-turret reward UI averages reward values but sums hit counters instead of showing only the last worker"
	)


func _test_turret_evaluator_occlusion_success_contract() -> void:
	var evaluator: TurretCandidateEvaluationJob = TurretCandidateEvaluationJob.new()
	evaluator.current_case = {"scenario_id": "occluded_target"}
	evaluator.total_hits = 0
	evaluator.total_bad_shots = 0
	_expect(
		evaluator._case_success(),
		"the deterministic occlusion case can succeed by correctly withholding fire"
	)
	evaluator.total_bad_shots = 1
	_expect(
		not evaluator._case_success(),
		"the deterministic occlusion case fails when the policy fires a classified bad shot through cover"
	)


func _test_worker_camera_filter() -> void:
	turret.reset_body(Transform3D.IDENTITY, 505)
	turret.active = false
	_expect(
		DroneTrainingRoom._turret_worker_is_camera_focus_candidate({"finished": false}, turret),
		"a live unfinished turret can be selected by the shared worker camera"
	)
	_expect(
		not DroneTrainingRoom._turret_worker_is_camera_focus_candidate({"finished": true}, turret),
		"a finished turret is removed from selected-group camera focus"
	)
	turret.training_invulnerable = false
	turret.apply_damage(turret.loadout.maximum_health())
	_expect(
		not DroneTrainingRoom._turret_worker_is_camera_focus_candidate({"finished": false}, turret),
		"a destroyed turret is removed from camera focus immediately"
	)
	turret.training_invulnerable = true


func _test_worker_checkpoint_registry() -> void:
	var root_path = "user://tests/turret_model_registry_%d" % Time.get_ticks_usec()
	var registry = TurretModelRegistry.new(root_path)
	var loadout = MLBodyPresetLibrary.stationary_turret_loadout()
	var trainer = TurretPPOTrainer.new(606)
	var checkpoint = trainer.to_checkpoint(
		loadout.hardware_signature(),
		TurretRewardDeck.new().configuration_dictionary()
	)
	var malformed_metadata = checkpoint.duplicate(true)
	malformed_metadata["action_count"] = {"broken": true}
	_expect(
		registry.save_checkpoint("Malformed Turret", malformed_metadata).is_empty(),
		"turret registry rejects wrong-type checkpoint metadata without throwing"
	)
	var saved = registry.save_checkpoint("Regression Turret", checkpoint)
	_expect(not saved.is_empty(), "a turret policy saves into its own model library")
	var overwritten = registry.overwrite_checkpoint(saved, checkpoint)
	_expect(
		not overwritten.is_empty()
		and int(overwritten.get("checkpoint_revision", 0)) == 2
		and registry.list_models().size() == 1,
		"keep-newest overwrites one turret version and increments its revision"
	)
	var incompatible = checkpoint.duplicate(true)
	incompatible["hardware_signature"] = "different-turret-hardware"
	_expect(
		registry.overwrite_checkpoint(overwritten, incompatible).is_empty(),
		"rolling saves refuse a checkpoint from different turret parts"
	)
	var corrupt_network = checkpoint.duplicate(true)
	corrupt_network["network"] = {}
	_expect(
		registry.overwrite_checkpoint(overwritten, corrupt_network).is_empty()
		and not registry.load_checkpoint(overwritten).is_empty(),
		"rolling saves reject an unusable turret network before replacing the valid checkpoint"
	)
	registry.delete_model(overwritten)
	_remove_directory(ProjectSettings.globalize_path(root_path))


func _test_checkpoint_room_metadata_is_sanitized() -> void:
	var coordinator = TurretTrainingCoordinator.new(test_root)
	var group = coordinator.create_group(993, "CheckpointSanitize", Color.WHITE, 1)
	_expect(
		coordinator.set_control_interval(993, NAN)
		and is_equal_approx(
			float(group.get("control_interval_seconds", 0.0)),
			TurretTrainingCoordinator.DECISION_INTERVAL_SECONDS
		),
		"turret control-rate setter replaces non-finite values with the canonical interval"
	)
	var checkpoint: Dictionary = coordinator.save_checkpoint(993)
	var poisoned: Dictionary = checkpoint.duplicate(true)
	var poisoned_settings: Dictionary = (poisoned.get("room_settings", {}) as Dictionary).duplicate(true)
	poisoned_settings["control_interval_seconds"] = NAN
	poisoned["room_settings"] = poisoned_settings
	_expect(
		coordinator.load_checkpoint(993, poisoned)
		and is_equal_approx(
			float(group.get("control_interval_seconds", 0.0)),
			TurretTrainingCoordinator.DECISION_INTERVAL_SECONDS
		),
		"turret checkpoint restore cannot inject a non-finite scheduler interval"
	)
	var poisoned_loadout_checkpoint: Dictionary = checkpoint.duplicate(true)
	var poisoned_loadout: Dictionary = (
		(poisoned_loadout_checkpoint.get("turret_loadout", {}) as Dictionary).duplicate(true)
	)
	var poisoned_base: Dictionary = (poisoned_loadout.get("base", {}) as Dictionary).duplicate(true)
	var poisoned_gun: Dictionary = (poisoned_loadout.get("gun", {}) as Dictionary).duplicate(true)
	poisoned_base["mass_kg"] = {"broken": true}
	poisoned_gun["trigger_threshold"] = NAN
	poisoned_loadout["base"] = poisoned_base
	poisoned_loadout["gun"] = poisoned_gun
	poisoned_loadout_checkpoint["turret_loadout"] = poisoned_loadout
	_expect(
		coordinator.load_checkpoint(993, poisoned_loadout_checkpoint)
		and is_finite((group.get("turret_loadout") as TurretLoadout).base.mass_kg)
		and is_finite((group.get("turret_loadout") as TurretLoadout).gun.trigger_threshold),
		"turret checkpoint hardware deserialization contains malformed/non-finite scalar fields"
	)
	var malformed: Dictionary = checkpoint.duplicate(true)
	malformed["room_settings"] = 17
	_expect(
		not coordinator.load_checkpoint(993, malformed),
		"turret checkpoint restore rejects malformed coordinator metadata before loading the policy"
	)


func _test_loadout_json_round_trip() -> void:
	var source = MLBodyPresetLibrary.stationary_turret_loadout()
	source.base.footprint_size = Vector3(1.25, 0.4, 0.8)
	source.gun.barrel_mount_offset = Vector3(0.1, 0.25, -0.15)
	var encoded = JSON.stringify(source.to_dictionary())
	var parsed: Variant = JSON.parse_string(encoded)
	var restored = TurretLoadout.from_dictionary(parsed if parsed is Dictionary else {})
	_expect(
		restored.base.footprint_size.is_equal_approx(source.base.footprint_size)
		and restored.gun.barrel_mount_offset.is_equal_approx(source.gun.barrel_mount_offset),
		"turret part vectors survive the JSON checkpoint path without Variant-only serialization"
	)
	_expect(
		restored.hardware_signature() == source.hardware_signature(),
		"JSON-round-tripped turret parts preserve their hardware compatibility signature"
	)


func _test_incomplete_loadout_does_not_invent_preset_parts() -> void:
	var empty = TurretLoadout.new()
	_expect(
		not empty.ensure_contract()
		and empty.base == null
		and empty.gun == null
		and empty.hardware_signature().is_empty(),
		"incomplete turret bodies remain invalid instead of manufacturing the Stationary Turret preset"
	)
	var decoded: TurretLoadout = TurretLoadout.from_dictionary({})
	_expect(
		decoded != null and not decoded.ensure_contract(),
		"empty serialized turret data does not create hidden preset parts"
	)


func _test_invalid_turret_reset_fails_closed() -> void:
	var invalid: TurretPhysicalBody3D = TurretPhysicalBody3D.new()
	_expect(
		not invalid.reset_body(Transform3D.IDENTITY, 77)
		and not invalid.alive
		and not invalid.active
		and is_zero_approx(invalid.current_health),
		"turret reset fails closed when no accepted/preset base + gun body exists"
	)
	invalid.free()


func _test_evaluation_threat_turrets_use_accepted_preset_body() -> void:
	var drone_job: DroneCandidateEvaluationJob = DroneCandidateEvaluationJob.new()
	test_root.add_child(drone_job)
	var drone_threat_ready: bool = drone_job._build_turret_exposure(701)
	_expect(
		drone_threat_ready
		and is_instance_valid(drone_job.evaluation_turret)
		and drone_job.evaluation_turret.loadout != null
		and drone_job.evaluation_turret.loadout.ensure_contract(),
		"drone fixed-seed turret-exposure fixture receives the authored turret preset before _ready"
	)
	test_root.remove_child(drone_job)
	drone_job.free()

	var limb_job: FourLimbCandidateEvaluationJob = FourLimbCandidateEvaluationJob.new()
	test_root.add_child(limb_job)
	var limb_threat_ready: bool = limb_job._build_threat_turret(702)
	_expect(
		limb_threat_ready
		and is_instance_valid(limb_job.evaluation_turret)
		and limb_job.evaluation_turret.loadout != null
		and limb_job.evaluation_turret.loadout.ensure_contract(),
		"four-limb fixed-seed turret-exposure fixture receives the authored turret preset before _ready"
	)
	test_root.remove_child(limb_job)
	limb_job.free()


func _test_existing_workers_expose_turret_features() -> void:
	var drone_names = DronePPOObservationEncoder.feature_names_for_schema(
		DronePPOObservationEncoder.SCHEMA_VERSION
	)
	var sac_names = DroneSACObservationEncoder.actor_feature_names()
	var limb_names = FourLimbMLFeatureEncoder.feature_names()
	_expect(
		"turret_threat_level" in drone_names
		and "turret_threat_level" in sac_names
		and "turret_threat_level" in limb_names,
		"drone PPO, drone SAC, and limb policies all expose a named turret-danger input"
	)
	var previous_actor_names = DronePPOObservationEncoder.feature_names_for_schema(
		DronePPOObservationEncoder.TARGET_SCHEMA_VERSION
	)
	var previous_critic_names = DronePPOObservationEncoder.critic_feature_names_for_schema(
		DronePPOObservationEncoder.TARGET_SCHEMA_VERSION
	)
	var current_critic_names = DronePPOObservationEncoder.critic_feature_names_for_schema(
		DronePPOObservationEncoder.SCHEMA_VERSION
	)
	_expect(
		drone_names.slice(0, previous_actor_names.size()) == previous_actor_names
		and current_critic_names.slice(0, previous_critic_names.size()) == previous_critic_names
		and limb_names.find("turret_present") == FourLimbMLFeatureEncoder.BASE_FEATURE_COUNT
		and sac_names.find("turret_present") == DroneSACObservationEncoder.LEGACY_ACTOR_FEATURE_COUNT,
		"turret perception follows the complete current limb tensor while drone PPO/SAC retain their own versioned layouts"
	)


func _test_drone_combat_adapter_identity() -> void:
	var drone = ServerDrone.new()
	var evaluator_adapter = DroneTrainingRoom._new_drone_combat_adapter(drone)
	var training_adapter = DroneTrainingRoom._new_drone_combat_adapter(drone, 17, 3)
	_expect(
		evaluator_adapter != null
		and evaluator_adapter.group_id == -1
		and evaluator_adapter.worker_id == -1,
		"evaluation drones use explicit non-training combat identity instead of leaking worker locals"
	)
	_expect(
		training_adapter != null
		and training_adapter.group_id == 17
		and training_adapter.worker_id == 3,
		"training drones preserve their group and worker combat identity"
	)
	drone.free()


func _reward_observation(
	alignment: float,
	target_present: bool,
	line_of_sight: bool,
	commands: PackedFloat64Array,
	damage_taken: float
) -> Dictionary:
	var target_position = turret.muzzle_position_world() + Vector3.FORWARD * 10.0
	var observation = TurretMLObservation.capture(
		turret,
		{
			"present": target_present,
			"is_combat_target": target_present,
			"stable_id": "entity:drone:900" if target_present else "",
			"target_kind": "drone" if target_present else "fallback",
			"entity_id": 900 if target_present else 0,
			"entity_kind": "drone" if target_present else "training_target",
			"position_world": target_position,
			"velocity_world": Vector3.ZERO,
			"radius_m": 0.5,
			"distance_m": 10.0,
			"direct_direction_world": Vector3.FORWARD,
			"intercept_direction_world": Vector3.FORWARD,
			"line_of_sight": line_of_sight,
			"within_range": true,
			"within_pitch_arc": true,
		},
		0.5,
		commands,
		{"damage_taken": damage_taken, "hit_count": 1 if damage_taken > 0.0 else 0}
	)
	(observation["target"] as Dictionary)["aim_alignment"] = alignment
	return observation


func _arrays_close(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not is_equal_approx(left[index], right[index]):
			return false
	return true


func _all_finite(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _colors_close(left: Color, right: Color) -> bool:
	return (
		is_equal_approx(left.r, right.r)
		and is_equal_approx(left.g, right.g)
		and is_equal_approx(left.b, right.b)
		and is_equal_approx(left.a, right.a)
	)


func _unique_string_count(values: Array[String]) -> int:
	var unique: Dictionary[String, bool] = {}
	for value: String in values:
		unique[value] = true
	return unique.size()


func _remove_directory(path: String) -> void:
	var directory = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry = directory.get_next()
	while not entry.is_empty():
		var child_path = path.path_join(entry)
		if directory.current_is_dir():
			_remove_directory(child_path)
		else:
			DirAccess.remove_absolute(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _test_rebuilt_turret_ui_avoids_object_capturing_lambdas() -> void:
	var turret_ui_source = FileAccess.get_file_as_string(
		"res://ml/training/turret/turret_training_room_ui.gd"
	)
	var room_source = FileAccess.get_file_as_string(
		"res://ml/training/drone_training_room.gd"
	)
	_expect(
		not turret_ui_source.contains("connect(func"),
		"turret cards use bound stable identifiers instead of lambdas that retain freed controls"
	)
	_expect(
		turret_ui_source.contains('room._button("+")')
		and turret_ui_source.contains("_begin_add_turret_worker"),
		"the turret card exposes a + worker button next to its worker count and routes it through placement"
	)
	_expect(
		turret_ui_source.contains("branch_dialog.wrap_controls = false")
		and turret_ui_source.contains("branch_dialog.size = BRANCH_DIALOG_SIZE")
		and turret_ui_source.contains("var scroll = ScrollContainer.new()")
		and turret_ui_source.contains("scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED")
		and turret_ui_source.contains("branch_dialog.popup_centered()"),
		"the turret creation dialog disables AcceptDialog auto-resizing, owns an exact first-open size, and scrolls overflowing content"
	)
	_expect(
		room_source.count("wrap_controls = false") >= 2
		and room_source.contains("limb_branch_dialog.size = Vector2i(580, 600)")
		and room_source.contains("branch_dialog.size = Vector2i(620, 760)"),
		"drone and limb custom creation dialogs use the same explicit-size contract instead of build-time control wrapping"
	)
	_expect(
		turret_ui_source.contains("Policy source: fresh random stationary-turret model")
		and turret_ui_source.contains("Policy source: live turret weights from %s"),
		"the turret creation dialog describes fresh models and live branches accurately"
	)
	_expect(
		room_source.contains("if not adds_worker:\n\t\tturret_training.prepare_group_for_placement(group_id)"),
		"adding a turret keeps the already placed paused workers alive while the placement preview is active"
	)
	_expect(
		room_source.contains("Placement itself is a configuration boundary, but pause should not mean \"no body\".")
		and room_source.contains("if turret_training.set_group_active("),
		"confirming placement for an already-paused turret group rematerializes the authored population and freezes it again"
	)
	var coordinator_source: String = FileAccess.get_file_as_string(
		"res://ml/training/turret/turret_training_coordinator.gd"
	)
	_expect(
		coordinator_source.contains("_set_group_projectiles_paused(group, true)")
		and coordinator_source.contains("func _set_group_projectiles_paused(group: Dictionary, paused: bool) -> void:"),
		"turret pause preserves in-flight simulation state while real policy and episode boundaries still cancel stale projectiles"
	)
	_expect(
		room_source.contains("func _clear_turret_target_references_to_group(removed_group_id: int) -> void:")
		and room_source.count("_clear_turret_target_references_to_group(group_id)") >= 2
		and turret_ui_source.contains("room._clear_turret_target_references_to_group(group_id)"),
		"removing a drone, limb, or turret group clears explicit turret target references through the normal target-boundary path"
	)
	_expect(
		not room_source.contains("tween.finished.connect(\n\t\tfunc"),
		"box animation completion uses instance identifiers instead of capturing freed controls"
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: " + message)
		return
	failure_count += 1
	push_error("FAIL: " + message)
