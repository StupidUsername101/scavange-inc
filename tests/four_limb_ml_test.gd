extends SceneTree

#######################################################
# Plain-language checks for the four-limb body and learning contracts. Run headlessly from the
# project root when Godot 4.6 is available.
#######################################################

class TestAttachment:
	extends FourLimbAttachmentStateProvider

	func _init() -> void:
		attachment_type_id = "test_future_gun_feed"
		attachment_tags = PackedStringArray(["weapon"])
		contributed_mass_kg = 1.5

	func ml_observation_payload(_context: Dictionary = {}) -> PackedFloat64Array:
		return PackedFloat64Array([0.75, 0.25, -0.5, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


class TestSensorAttachment:
	extends FourLimbAttachmentStateProvider

	func _init() -> void:
		attachment_type_id = "test_sensor_feed"
		attachment_tags = PackedStringArray(["sensor"])


var failure_count = 0
var assertion_count = 0
var test_root: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = Node3D.new()
	root.add_child(test_root)
	_test_action_slots_are_direct()
	_test_commanded_joints_can_yield_passive_rest_spring()
	_test_fresh_stock_hips_can_reach_above_core_without_changing_legacy_bodies()
	_test_controlled_grip_is_policy_reachable()
	_test_grip_exploration_is_reachable_without_widening_joint_noise()
	_test_horizontal_hip_response_is_axis_specific_and_preset_owned()
	_test_runtime_action_uses_packed_commands()
	_test_full_direction_obstacle_feed()
	_test_default_anatomy_is_radial_light_and_long_legged()
	_test_stock_foot_pad_is_flat_and_rough_at_rest()
	_test_passive_spider_stance_support()
	_test_joint_limits_protect_leg_anatomy()
	_test_limb_ppo_matches_drone_optimizer_scale()
	_test_limb_tuning_contract()
	_test_missing_limb_keeps_its_slot()
	_test_attachment_feed_is_reserved()
	_test_attachment_slot_rules_are_respected()
	_test_held_joint_targets_reach_the_model()
	_test_observation_rejects_corrupt_proprioception()
	_test_missing_limb_keeps_model_compatibility()
	_test_workers_do_not_share_action_arrays()
	_test_wrong_body_models_are_rejected()
	_test_features_are_fixed_and_finite()
	_test_proprioception_reaches_model()
	_test_runtime_model_matches_training_model()
	_test_short_learning_update_stays_finite()
	await _test_background_learning_update_stays_finite()
	_test_checkpoint_round_trip()
	_test_checkpoint_score_sentinels_round_trip()
	_test_body_definition_round_trip_and_group_independence()
	_test_limb_policy_branch_variation()
	_test_model_files_round_trip()
	_test_unified_coordinator_contract()
	_test_background_step_accounting_reaches_trainer()
	_test_optimizer_swap_preserves_old_policy_interval()
	_test_unified_live_worker_count_and_progress_summary()
	_test_unified_spawn_uses_shared_marker()
	_test_unified_cleanup_accepts_already_freed_workers()
	_test_fallback_pickup_prop_obeys_group_pause()
	_test_terminal_grip_release_contract()
	_test_unified_episode_history_and_respawn()
	_test_unified_startup_ramp_and_terminal_contract()
	_test_arena_boundary_is_visible_and_terminal()
	_test_punishment_components_are_negative()
	_test_core_rotational_stability_ignores_yaw_and_penalizes_rocking()
	_test_contact_flicker_cannot_farm_jump_rewards()
	_test_in_place_hop_cannot_farm_landing_reward()
	_test_qualified_jump_and_landing_are_rewarded()
	_test_item_pickup_reward_value_scales_reward()
	_test_item_pickup_requires_worker_local_lift()
	_test_item_delivery_reward_is_conditional_and_potential_based()
	_test_dead_limb_workers_are_not_camera_targets()
	_test_target_progress_is_not_gated_by_posture()
	_test_full_3d_target_reward_and_climb_context()
	_test_climbing_cardset_and_evaluator_surfaces_are_grippable()
	_test_target_locomotion_outweighs_passive_posture()
	_test_target_objective_is_explicit()
	_test_stable_body_height_reward()
	_test_target_height_is_visible_without_changing_horizontal_radius()
	_test_partial_progress_keeps_reward()
	await _test_physical_body_uses_simulated_core()
	print("Four-limb assertions: %d, failures: %d" % [assertion_count, failure_count])
	quit(0 if failure_count == 0 else 1)


func _test_runtime_action_uses_packed_commands() -> void:
	var trainer = FourLimbPPOTrainer.new(7340033)
	var observation = _sample_observation()
	var runtime_sample = trainer.sample_runtime_action(observation, true)
	var validated_runtime_sample = trainer.sample_validated_runtime_action(observation, true)
	var rich_sample = trainer.sample_action(observation, true)
	var training_sample: Dictionary = trainer.sample_validated_training_action(observation, true)
	var runtime_commands: PackedFloat64Array = runtime_sample.get(
		"commands", PackedFloat64Array()
	)
	var training_critic_input: PackedFloat64Array = training_sample.get(
		"critic_input", PackedFloat64Array()
	)
	var rich_commands: PackedFloat64Array = rich_sample.get(
		"commands", PackedFloat64Array()
	)
	_expect(
		not runtime_sample.has("action")
		and not runtime_sample.has("observation")
		and runtime_commands.size() == FourLimbMLAction.ACTION_COUNT,
		"the training hot path can apply packed limb commands without building sixteen dictionaries"
	)
	_expect(
		rich_sample.has("action")
		and _arrays_close(runtime_commands, rich_commands)
		and _arrays_close(
			runtime_commands,
			validated_runtime_sample.get("commands", PackedFloat64Array())
		)
		and _arrays_close(
			runtime_commands,
			training_sample.get("commands", PackedFloat64Array())
		),
		"skipping runtime dictionaries or the live critic does not change deterministic policy commands"
	)
	_expect(
		bool(training_sample.get("critic_value_deferred", false))
		and not training_sample.has("value")
		and training_critic_input.size() == FourLimbMLFeatureEncoder.FEATURE_COUNT,
		"the live limb training sample keeps the critic tensor but defers its forward pass off the physics thread"
	)
	var next_sample = trainer.sample_runtime_action(observation, true)
	_expect(
		trainer.add_transition(
			0,
			runtime_sample,
			0.01,
			observation,
			false,
			false,
			0.05,
			next_sample.get("actor_input", PackedFloat64Array()),
			float(next_sample.get("value", NAN))
		)
		and trainer.rollout.size() == 1
		and is_equal_approx(
			float((trainer.rollout[0] as Dictionary).get("next_value", NAN)),
			float(next_sample.get("value", NAN))
		),
		"the next policy sample can close the previous transition without re-encoding or re-running the critic"
	)
	var deferred_trainer: FourLimbPPOTrainer = FourLimbPPOTrainer.new(7340033)
	var deferred_sample: Dictionary = deferred_trainer.sample_validated_training_action(
		observation,
		true
	)
	var deferred_next: Dictionary = deferred_trainer.sample_validated_training_action(
		observation,
		true
	)
	_expect(
		deferred_trainer.add_transition(
			0,
			deferred_sample,
			0.01,
			observation,
			false,
			false,
			0.05,
			deferred_next.get("actor_input", PackedFloat64Array())
		)
		and deferred_trainer.rollout.size() == 1
		and bool((deferred_trainer.rollout[0] as Dictionary).get("critic_value_deferred", false))
		and not is_finite(float((deferred_trainer.rollout[0] as Dictionary).get("value", NAN))),
		"live training can close a valid transition without performing a critic forward pass on the physics thread"
	)
	_expect(
		deferred_trainer.actor_critic.load_state(deferred_trainer.rollout_start_network_state)
		and deferred_trainer._hydrate_deferred_critic_values()
		and is_finite(float((deferred_trainer.rollout[0] as Dictionary).get("value", NAN)))
		and is_finite(float((deferred_trainer.rollout[0] as Dictionary).get("next_value", NAN)))
		and not bool((deferred_trainer.rollout[0] as Dictionary).get("critic_value_deferred", true)),
		"the detached PPO side reconstructs exactly the deferred producer-critic values before GAE"
	)


func _test_default_anatomy_is_radial_light_and_long_legged() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	_expect(
		definition.core_size.x < 0.8 and definition.core_size.z < 1.0,
		"the default four-limb chassis is compact"
	)
	_expect(definition.core_mass <= 3.2, "the central chassis is much lighter")
	var total_mass = definition.core_mass
	var unique_mounts: Dictionary[String, bool] = {}
	var stock_grip_count = 0
	for limb: FourLimbSlotDefinition in definition.limbs:
		total_mass += limb.segment_mass * 2.0
		unique_mounts[str(limb.hip_offset)] = true
		_expect(
			limb.upper_length >= 1.0 and limb.lower_length >= 1.0,
			"each default limb uses longer one-metre-plus segments"
		)
		var effector = limb.end_effector
		if effector != null and effector.effector_type_id == &"generic_grip":
			stock_grip_count += 1
			_expect(
				not effector.compatible_surface_tags.has("ground"),
				"stock walking grips require explicit opt-in before they can anchor to ground"
			)
			_expect(
				is_equal_approx(effector.candidate_refresh_seconds, 0.10),
				"stock grips refresh wide candidate perception at 10 Hz instead of querying physics every policy tick"
			)
	_expect(total_mass < 7.0, "the complete Four-Limb Walker preset is substantially lighter than before")
	_expect(stock_grip_count == 4, "all four stock limbs keep the generic climb/carry grip")
	_expect(unique_mounts.size() == 4, "all four limbs have distinct authored mount origins")
	_expect(
		definition.limbs[0].hip_offset.x > 0.0 and definition.limbs[0].hip_offset.z < 0.0
		and definition.limbs[1].hip_offset.x > 0.0 and definition.limbs[1].hip_offset.z > 0.0
		and definition.limbs[2].hip_offset.x < 0.0 and definition.limbs[2].hip_offset.z > 0.0
		and definition.limbs[3].hip_offset.x < 0.0 and definition.limbs[3].hip_offset.z < 0.0,
		"one limb is mounted at each visible chassis corner"
	)
	var diagnostic_hip_torque = LimbsController3D.spring_damper_component(
		0.5,
		0.0,
		definition.hip_stiffness,
		definition.hip_damping,
		definition.maximum_hip_torque
	)
	_expect(
		absf(diagnostic_hip_torque) > 5.0,
		"the generic hip impedance controller has useful torque authority"
	)


func _test_stock_foot_pad_is_flat_and_rough_at_rest() -> void:
	var definition: FourLimbBodyDefinition = MLBodyPresetLibrary.four_limb_walker_definition()
	for limb_index in range(definition.limbs.size()):
		var slot: FourLimbSlotDefinition = definition.limbs[limb_index]
		var effector: LimbEndEffectorDefinition = slot.end_effector
		_expect(
			effector != null
			and effector.is_physically_present()
			and effector.geometry_type == LimbEndEffectorDefinition.GeometryType.BOX
			and effector.box_size.is_equal_approx(Vector3(0.24, 0.06, 0.24))
			and is_equal_approx(effector.friction, 1.0)
			and effector.rough,
			"stock limb %d has a real flat high-friction plantar contact patch" % limb_index
		)
		var points: PackedVector3Array = EnemyGaitPlanner.solve_two_bone(
			slot.hip_offset,
			slot.rest_foot_offset,
			slot.upper_length,
			slot.lower_length,
			slot.bend_hint
		)
		_expect(points.size() == 3, "stock foot alignment uses a valid rest-pose IK chain")
		if points.size() != 3:
			continue
		var lower_direction: Vector3 = (points[2] - points[1]).normalized()
		var lower_basis: Basis = GenericLimb3D.basis_from_y(lower_direction)
		var pad_up_core: Vector3 = (lower_basis * effector.local_basis().y).normalized()
		_expect(
			pad_up_core.dot(Vector3.UP) > 0.999,
			"stock limb %d sole is authored flat to the ground in its neutral pose" % limb_index
		)
		var proximal_support: float = effector.support_offset_along_parent_direction(
			Vector3.DOWN
		)
		_expect(
			proximal_support < -0.001,
			"stock limb %d sole begins beyond the lower capsule tip instead of overlapping it" % limb_index
		)


func _test_passive_spider_stance_support() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	var total_mass = definition.core_mass
	for limb: FourLimbSlotDefinition in definition.limbs:
		total_mass += limb.segment_mass * 2.0
	_expect(
		definition.passive_joint_stiffness > 0.0
		and definition.passive_joint_damping > 0.0
		and definition.maximum_passive_joint_torque > 0.0
		and definition.passive_joint_progressive_ratio > 0.0,
		"default joints always have passive return-to-rest elasticity"
	)
	var gravity_magnitude = float(
		ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	)
	var per_leg_force = total_mass * gravity_magnitude / float(FourLimbBodyDefinition.LIMB_SLOT_COUNT)
	var worst_required_torque = 0.0
	var worst_locked_axis_share = 0.0
	for limb: FourLimbSlotDefinition in definition.limbs:
		var points = EnemyGaitPlanner.solve_two_bone(
			limb.hip_offset,
			limb.rest_foot_offset,
			limb.upper_length,
			limb.lower_length,
			limb.bend_hint
		)
		if points.size() != 3:
			continue
		var upper_direction = (points[1] - points[0]).normalized()
		var hip_basis = FourLimbPhysicalRig3D.hip_joint_basis_for_slot(
			limb,
			upper_direction
		)
		var support_torque = (points[2] - points[0]).cross(Vector3.UP * per_leg_force)
		worst_required_torque = maxf(worst_required_torque, absf(support_torque.dot(hip_basis.z)))
		worst_locked_axis_share = maxf(
			worst_locked_axis_share,
			absf(support_torque.dot(hip_basis.y)) / maxf(support_torque.length(), 0.0001)
		)
	_expect(
		worst_locked_axis_share < 0.08,
		"default hip frames place static support torque on free swing Z rather than locked Y"
	)
	_expect(
		definition.maximum_passive_joint_torque > worst_required_torque * 4.0,
		"passive torque caps have large headroom over the estimated static gravity load"
	)
	_expect(
		worst_required_torque / maxf(definition.passive_joint_stiffness, 0.001)
		< deg_to_rad(12.0),
		"the estimated static load needs only a small passive spring deflection"
	)
	var displaced_torque = LimbsController3D.progressive_spring_damper_component(
		deg_to_rad(-15.0),
		0.0,
		definition.passive_joint_stiffness,
		definition.passive_joint_damping,
		definition.maximum_passive_joint_torque,
		deg_to_rad(62.0),
		definition.passive_joint_progressive_ratio,
		definition.passive_joint_progressive_onset_ratio
	)
	var returning_fast_torque = LimbsController3D.progressive_spring_damper_component(
		deg_to_rad(-15.0),
		-2.0,
		definition.passive_joint_stiffness,
		definition.passive_joint_damping,
		definition.maximum_passive_joint_torque,
		deg_to_rad(62.0),
		definition.passive_joint_progressive_ratio,
		definition.passive_joint_progressive_onset_ratio
	)
	var edge_torque = LimbsController3D.progressive_spring_damper_component(
		deg_to_rad(55.0),
		0.0,
		definition.passive_joint_stiffness,
		definition.passive_joint_damping,
		definition.maximum_passive_joint_torque,
		deg_to_rad(62.0),
		definition.passive_joint_progressive_ratio,
		definition.passive_joint_progressive_onset_ratio
	)
	var linear_edge_torque = LimbsController3D.spring_damper_component(
		deg_to_rad(55.0),
		0.0,
		definition.passive_joint_stiffness,
		definition.passive_joint_damping,
		definition.maximum_passive_joint_torque
	)
	_expect(displaced_torque < 0.0, "passive torque points back toward the authored rest frame")
	_expect(
		absf(returning_fast_torque) < absf(displaced_torque),
		"passive damping resists overshooting while the joint returns to rest"
	)
	_expect(
		edge_torque > linear_edge_torque * 1.5,
		"passive resistance hardens progressively before the limb can fold flat"
	)
	var generic_joint = LimbJointDefinition.new()
	_expect(
		generic_joint.use_native_passive_spring
		and generic_joint.native_passive_fraction > 0.0
		and generic_joint.native_passive_fraction < 1.0,
		"generic joints use a hybrid native and explicitly bounded passive spring by default"
	)
	var restored = FourLimbBodyDefinition.from_dictionary(definition.to_dictionary())
	_expect(
		is_equal_approx(restored.passive_joint_stiffness, definition.passive_joint_stiffness)
		and is_equal_approx(restored.passive_joint_damping, definition.passive_joint_damping)
		and is_equal_approx(
			restored.maximum_passive_joint_torque,
			definition.maximum_passive_joint_torque
		)
		and is_equal_approx(
			restored.passive_joint_progressive_onset_ratio,
			definition.passive_joint_progressive_onset_ratio
		)
		and is_equal_approx(
			restored.passive_joint_progressive_ratio,
			definition.passive_joint_progressive_ratio
		)
		and is_equal_approx(
			restored.passive_joint_native_fraction,
			definition.passive_joint_native_fraction
		),
		"passive elasticity survives model and branch serialization"
	)
	var authored_variant_data = definition.to_dictionary()
	authored_variant_data["passive_joint_stiffness"] = 36.0
	authored_variant_data["passive_joint_damping"] = 5.5
	authored_variant_data["maximum_passive_joint_torque"] = 65.0
	var authored_variant = FourLimbBodyDefinition.from_dictionary(authored_variant_data)
	_expect(
		is_equal_approx(authored_variant.passive_joint_stiffness, 36.0)
		and is_equal_approx(authored_variant.passive_joint_damping, 5.5)
		and is_equal_approx(authored_variant.maximum_passive_joint_torque, 65.0),
		"serialized four-limb compatibility bodies preserve authored tuning instead of applying hidden stock migrations"
	)


func _test_joint_limits_protect_leg_anatomy() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	_expect(
		definition.joint_limit_stiffness > definition.knee_stiffness
		and definition.maximum_joint_limit_torque > definition.maximum_knee_torque,
		"the independent soft-stop guard is stronger than normal policy knee drive"
	)
	for limb: FourLimbSlotDefinition in definition.limbs:
		_expect(
			limb.knee_limit_lower_degrees >= -12.0
			and limb.knee_limit_upper_degrees >= 55.0
			and limb.knee_limit_upper_degrees > limb.knee_limit_lower_degrees,
			"default knees can bend forward but cannot fold far backwards"
		)
	var legacy_broken_limb = FourLimbSlotDefinition.new()
	legacy_broken_limb.knee_limit_lower_degrees = -100.0
	legacy_broken_limb.hip_twist_span_degrees = 110.0
	legacy_broken_limb.sanitize_joint_limits()
	_expect(
		legacy_broken_limb.knee_limit_lower_degrees >= -20.0
		and legacy_broken_limb.hip_twist_span_degrees <= 90.0
		and definition.limbs[0].hip_twist_span_degrees >= 70.0,
		"edited anatomy remains bounded while the stock hip keeps useful horizontal sweep freedom"
	)
	var limb = definition.limbs[0]
	var knee_joint = LimbJointDefinition.new()
	knee_joint.lower_limit_degrees = Vector3(0.0, 0.0, limb.knee_limit_lower_degrees)
	knee_joint.upper_limit_degrees = Vector3(0.0, 0.0, limb.knee_limit_upper_degrees)
	knee_joint.action_indices = Vector3i(-1, -1, 0)
	knee_joint.command_limit_margin_degrees = definition.joint_limit_soft_zone_degrees * 0.55
	var command_limits = knee_joint.command_limits_radians(Vector3.AXIS_Z)
	var positive_target = LimbsController3D.normalized_target(
		1.0,
		command_limits.x,
		command_limits.y
	)
	var negative_target = LimbsController3D.normalized_target(
		-1.0,
		command_limits.x,
		command_limits.y
	)
	_expect(
		positive_target < deg_to_rad(limb.knee_limit_upper_degrees)
		and negative_target > deg_to_rad(limb.knee_limit_lower_degrees),
		"policy targets remain inside the physical joint stops even at full command"
	)
	var upper_stop = LimbsController3D.soft_limit_component(
		deg_to_rad(limb.knee_limit_upper_degrees + 5.0),
		2.0,
		deg_to_rad(limb.knee_limit_lower_degrees),
		deg_to_rad(limb.knee_limit_upper_degrees),
		deg_to_rad(definition.joint_limit_soft_zone_degrees),
		definition.joint_limit_stiffness,
		definition.joint_limit_damping,
		definition.maximum_joint_limit_torque
	)
	var lower_stop = LimbsController3D.soft_limit_component(
		deg_to_rad(limb.knee_limit_lower_degrees - 5.0),
		-2.0,
		deg_to_rad(limb.knee_limit_lower_degrees),
		deg_to_rad(limb.knee_limit_upper_degrees),
		deg_to_rad(definition.joint_limit_soft_zone_degrees),
		definition.joint_limit_stiffness,
		definition.joint_limit_damping,
		definition.maximum_joint_limit_torque
	)
	_expect(
		upper_stop < 0.0 and lower_stop > 0.0,
		"soft-stop torque always pushes an overextended knee back into its valid range"
	)
	_expect(
		absf(upper_stop) <= definition.maximum_joint_limit_torque + 0.0001
		and absf(lower_stop) <= definition.maximum_joint_limit_torque + 0.0001,
		"joint-limit enforcement respects its independent safety torque cap"
	)
	var restored = FourLimbBodyDefinition.from_dictionary(definition.to_dictionary())
	_expect(
		is_equal_approx(restored.joint_limit_soft_zone_degrees, definition.joint_limit_soft_zone_degrees)
		and is_equal_approx(restored.joint_limit_stiffness, definition.joint_limit_stiffness)
		and is_equal_approx(restored.maximum_joint_limit_torque, definition.maximum_joint_limit_torque),
		"joint-limit protection survives body save, branch, and checkpoint serialization"
	)


func _test_limb_ppo_matches_drone_optimizer_scale() -> void:
	var trainer = FourLimbPPOTrainer.new(4321)
	_expect(
		FourLimbPPOActorCritic.HIDDEN_SIZE == 64
		and DronePPOActorCritic.HIDDEN_SIZE >= 64,
		"limb and drone PPO both avoid the old 32-unit policy bottleneck"
	)
	_expect(
		int(trainer.config["rollout_size"])
		== int(DronePPOTrainer.DEFAULT_CONFIG["rollout_transitions"]),
		"limb PPO learns after the same default number of decisions as drone PPO"
	)
	_expect(
		int(trainer.config["minimum_update_transitions"])
		== int(DronePPOTrainer.DEFAULT_CONFIG["minimum_update_transitions"]),
		"limb PPO uses the same partial-update threshold as drone PPO"
	)
	_expect(
		trainer.actor_critic != trainer.behavior_actor_critic,
		"limb PPO has separate optimizer and behavior-policy networks like drone PPO"
	)
	var custom = FourLimbPPOTrainer.new(4323, {
		"hidden_layer_width": 96,
		"hidden_layer_depth": 3,
	})
	_expect(
		custom.actor_critic.hidden_size == 96
		and custom.actor_critic.hidden_layer_count == 3
		and custom.behavior_actor_critic.hidden_size == 96
		and custom.behavior_actor_critic.hidden_layer_count == 3,
		"fresh four-limb models honor configurable hidden width and depth"
	)


func _test_limb_tuning_contract() -> void:
	var trainer = FourLimbPPOTrainer.new(4322)
	var controls = trainer.configuration_controls()
	_expect(not controls.is_empty(), "limb PPO exposes tuning controls to the shared room")
	var keys: Dictionary[String, bool] = {}
	for definition: Dictionary in controls:
		keys[str(definition.get("key", ""))] = true
	_expect(keys.has("learning_rate"), "the limb tuning hub exposes learning rate")
	_expect(keys.has("rollout_size"), "the limb tuning hub exposes rollout size")
	_expect(trainer.set_config_value("epochs", 6), "a limb PPO setting can be changed through the tuning contract")
	_expect(int(trainer.config_values().get("epochs", 0)) == 6, "the changed limb PPO setting is retained")


func _test_action_slots_are_direct() -> void:
	var commands = FourLimbMLAction.neutral_commands()
	commands[FourLimbMLAction.action_offset(2, 1)] = 0.73
	commands[FourLimbMLAction.grip_action_offset(1)] = 0.81
	var action = FourLimbMLAction.from_commands(commands)
	_expect(
		str(action.get("control_mode", "")) == FourLimbMLAction.CONTROL_MODE,
		"the action contract exposes direct joint-position and grip actuator targets rather than a gait remote"
	)
	var decoded = FourLimbMLAction.packed_commands(action)
	_expect(
		decoded.size() == FourLimbMLAction.ACTION_COUNT
		and FourLimbMLAction.ACTION_COUNT == 16
		and FourLimbMLAction.JOINT_ACTION_COUNT == 12,
		"the body exposes twelve joint controls plus four independent grip controls"
	)
	_expect(
		FourLimbMLAction.ACTION_NAMES[0] == "hip_elevation_target"
		and FourLimbMLAction.ACTION_NAMES[1] == "hip_horizontal_sweep_target"
		and FourLimbMLAction.ACTION_NAMES[2] == "knee_bend_target"
		and FourLimbMLAction.ACTION_NAMES[3] == "grip_activation",
		"each stable limb slot explicitly exposes lift/sweep/bend/grip semantics"
	)
	for index in range(decoded.size()):
		var expected = 0.0
		if index == FourLimbMLAction.action_offset(2, 1):
			expected = 0.73
		elif index == FourLimbMLAction.grip_action_offset(1):
			expected = 0.81
		_expect(is_equal_approx(decoded[index], expected), "one action changes only its matching actuator")
	var mislabeled_action = action.duplicate(true)
	var mislabeled_targets: Array = mislabeled_action["actuator_targets"]
	var mislabeled_entry = (mislabeled_targets[0] as Dictionary).duplicate(true)
	mislabeled_entry["actuator_name"] = "knee_bend_target"
	mislabeled_targets[0] = mislabeled_entry
	mislabeled_action["actuator_targets"] = mislabeled_targets
	_expect(
		FourLimbMLAction.packed_commands(mislabeled_action).is_empty(),
		"the body rejects a command whose descriptive actuator name disagrees with its numeric slot"
	)
	var fractional_index_action = action.duplicate(true)
	var fractional_targets: Array = fractional_index_action["actuator_targets"]
	var fractional_entry = (fractional_targets[0] as Dictionary).duplicate(true)
	fractional_entry["limb_index"] = 0.0
	fractional_targets[0] = fractional_entry
	fractional_index_action["actuator_targets"] = fractional_targets
	_expect(
		FourLimbMLAction.packed_commands(fractional_index_action).is_empty(),
		"action limb and actuator identifiers must be actual integer slots"
	)
	var text_target_action = action.duplicate(true)
	var text_targets: Array = text_target_action["actuator_targets"]
	var text_entry = (text_targets[0] as Dictionary).duplicate(true)
	text_entry["target"] = "0.5"
	text_targets[0] = text_entry
	text_target_action["actuator_targets"] = text_targets
	_expect(
		FourLimbMLAction.packed_commands(text_target_action).is_empty(),
		"actuator targets must be finite numeric values rather than coercible text"
	)
	var text_schema_action = action.duplicate(true)
	text_schema_action["schema_version"] = "5"
	_expect(
		FourLimbMLAction.packed_commands(text_schema_action).is_empty(),
		"malformed limb schema identifiers fail closed instead of being coerced or throwing"
	)


func _test_commanded_joints_can_yield_passive_rest_spring() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	var slot: FourLimbSlotDefinition = definition.limbs[0]
	var points = EnemyGaitPlanner.solve_two_bone(
		slot.hip_offset,
		slot.rest_foot_offset,
		slot.upper_length,
		slot.lower_length,
		slot.bend_hint
	)
	_expect(points.size() == 3, "the default limb has a valid two-bone rest pose")
	var action_offset: int = FourLimbMLAction.action_offset(0, 0)
	var rig = FourLimbPhysicalRig3D.new()
	rig.definition = definition
	var generic_definition = rig._generic_definition_from_slot(slot, 0, points)
	var hip_joint: LimbJointDefinition = generic_definition.segments[0].joint
	var knee_joint: LimbJointDefinition = generic_definition.segments[1].joint
	var hip_limits: Vector2 = hip_joint.command_limits_radians(Vector3.AXIS_Z)
	var knee_limits: Vector2 = knee_joint.command_limits_radians(Vector3.AXIS_Z)
	var hip_up_target: float = LimbsController3D.normalized_target(1.0, hip_limits.x, hip_limits.y)
	var knee_fold_target: float = LimbsController3D.normalized_target(1.0, knee_limits.x, knee_limits.y)
	rig.free()
	_expect(
		hip_joint.action_indices.z == action_offset
		and knee_joint.action_indices.z == action_offset + 2
		and rad_to_deg(hip_up_target) > 60.0
		and rad_to_deg(knee_fold_target) > 60.0,
		"each leg exposes enough hip elevation and knee fold range for an explicit pull-up command"
	)
	_expect(
		is_zero_approx(hip_joint.commanded_passive_yield.x)
		and is_equal_approx(hip_joint.commanded_passive_yield.z, 1.0)
		and is_equal_approx(knee_joint.commanded_passive_yield.z, 1.0)
		and is_equal_approx(hip_joint.passive_reference_span_degrees.z, 68.0),
		"only hip elevation and knee bend yield passive rest resistance; horizontal hip sweep and the established walking-side spring reference stay unchanged"
	)
	_expect(
		is_equal_approx(LimbsController3D.commanded_passive_scale(0.0, deg_to_rad(68.0)), 1.0)
		and LimbsController3D.commanded_passive_scale(hip_up_target, deg_to_rad(68.0)) < 0.20,
		"neutral legs keep full passive support while a large lift command makes the controller-side rest spring yield"
	)


func _test_fresh_stock_hips_can_reach_above_core_without_changing_legacy_bodies() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	for limb_index in range(definition.limbs.size()):
		var slot: FourLimbSlotDefinition = definition.limbs[limb_index]
		_expect(
			is_equal_approx(slot.hip_swing_span_degrees, 68.0)
			and is_equal_approx(slot.hip_elevation_upper_extension_degrees, 40.0),
			"fresh stock limb %d keeps the established walking span and adds positive-only overhead authority" % limb_index
		)
		var points = EnemyGaitPlanner.solve_two_bone(
			slot.hip_offset,
			slot.rest_foot_offset,
			slot.upper_length,
			slot.lower_length,
			slot.bend_hint
		)
		var rig = FourLimbPhysicalRig3D.new()
		rig.definition = definition
		var generic_definition = rig._generic_definition_from_slot(slot, limb_index, points)
		var hip_joint: LimbJointDefinition = generic_definition.segments[0].joint
		var hip_limits: Vector2 = hip_joint.command_limits_radians(Vector3.AXIS_Z)
		var maximum_raise = LimbsController3D.normalized_target(1.0, hip_limits.x, hip_limits.y)
		var rest_upper_direction = (points[1] - points[0]).normalized()
		var raise_rotation = LimbsController3D.rotation_from_joint_angles(
			Vector3(0.0, 0.0, maximum_raise),
			hip_joint.joint_basis_local
		)
		var raised_upper_direction = (raise_rotation * rest_upper_direction).normalized()
		var raised_foot_relative = raise_rotation * (slot.rest_foot_offset - slot.hip_offset)
		rig.free()
		_expect(
			rad_to_deg(maximum_raise) > 100.0
			and raised_upper_direction.y > 0.90
			and raised_foot_relative.y > definition.core_size.y * 0.5 + 0.15,
			"positive hip elevation can lift stock limb %d and its distal foot clearly above the core" % limb_index
		)

	var stock_slot: FourLimbSlotDefinition = definition.limbs[0]
	var legacy_dictionary = stock_slot.to_dictionary()
	legacy_dictionary.erase("hip_elevation_upper_extension_degrees")
	var legacy_slot = FourLimbSlotDefinition.from_dictionary(legacy_dictionary)
	_expect(
		is_equal_approx(legacy_slot.hip_elevation_upper_extension_degrees, 40.0)
		and legacy_slot.contract_dictionary().has("hip_elevation_upper_extension_degrees"),
		"older limb records migrate to the profile-v10 upward recovery workspace"
	)
	var legacy_points = EnemyGaitPlanner.solve_two_bone(
		legacy_slot.hip_offset,
		legacy_slot.rest_foot_offset,
		legacy_slot.upper_length,
		legacy_slot.lower_length,
		legacy_slot.bend_hint
	)
	var legacy_rig = FourLimbPhysicalRig3D.new()
	legacy_rig.definition = definition
	var legacy_generic = legacy_rig._generic_definition_from_slot(legacy_slot, 0, legacy_points)
	var legacy_hip: LimbJointDefinition = legacy_generic.segments[0].joint
	var legacy_limits: Vector2 = legacy_hip.command_limits_radians(Vector3.AXIS_Z)
	legacy_rig.free()
	_expect(
		rad_to_deg(legacy_limits.y) > 100.0,
		"migrated limb records receive the full upward recovery range instead of retaining obsolete anatomy"
	)


func _test_controlled_grip_is_policy_reachable() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	var seen_grip_indices: Dictionary[int, bool] = {}
	for limb_index in range(FourLimbMLAction.LIMB_COUNT):
		var slot: FourLimbSlotDefinition = definition.limbs[limb_index]
		var effector: LimbEndEffectorDefinition = slot.end_effector
		_expect(
			effector != null
			and effector.grip_mode == LimbEndEffectorDefinition.GripMode.CONTROLLED
			and is_equal_approx(effector.activation_response_per_second, 18.0),
			"every fresh stock limb owns a controlled grip that can cross its threshold within one 20 Hz action interval"
		)
		var points = EnemyGaitPlanner.solve_two_bone(
			slot.hip_offset,
			slot.rest_foot_offset,
			slot.upper_length,
			slot.lower_length,
			slot.bend_hint
		)
		var rig = FourLimbPhysicalRig3D.new()
		rig.definition = definition
		var generic_definition = rig._generic_definition_from_slot(slot, limb_index, points)
		var mapped_effector: LimbEndEffectorDefinition = generic_definition.end_effector
		var expected_index: int = FourLimbMLAction.grip_action_offset(limb_index)
		_expect(
			mapped_effector.grip_action_index == expected_index
			and not seen_grip_indices.has(expected_index),
			"each stock grip is mapped to its own stable PPO output"
		)
		seen_grip_indices[expected_index] = true
		rig.free()
	var grip_definition = LimbEndEffectorDefinition.new()
	grip_definition.enabled = true
	grip_definition.grip_mode = LimbEndEffectorDefinition.GripMode.CONTROLLED
	grip_definition.grip_action_index = 3
	grip_definition.activation_response_per_second = 18.0
	var owner = RigidBody3D.new()
	var grip = GenericGrip3D.new()
	grip.configure(owner, grip_definition)
	grip.step(0.05, 0.0, true)
	_expect(
		is_equal_approx(grip.requested_activation, 0.5)
		and grip.activation < grip_definition.grip_activation_threshold,
		"a zero policy grip output is a neutral hysteresis hold state and cannot engage from rest"
	)
	grip.step(0.05, 1.0, true)
	_expect(
		is_equal_approx(grip.requested_activation, 1.0)
		and grip.activation >= grip_definition.grip_activation_threshold,
		"a positive policy grip output reaches the controlled grip actuator and crosses engagement threshold"
	)
	grip.step(0.05, -1.0, true)
	_expect(
		is_zero_approx(grip.requested_activation)
		and grip.activation < grip_definition.grip_release_threshold,
		"a negative policy grip output cleanly releases the same actuator"
	)
	grip.free()
	owner.free()


func _test_grip_exploration_is_reachable_without_widening_joint_noise() -> void:
	var policy = FourLimbPPOActorCritic.new(9137)
	for action_index in range(FourLimbMLAction.ACTION_COUNT):
		_expect(
			is_equal_approx(
				policy.log_standard_deviation[action_index],
				FourLimbPPOActorCritic.INITIAL_LOG_STANDARD_DEVIATION
			),
			"bipolar grip mapping makes grip discovery reachable without injecting extra action noise"
		)



func _test_horizontal_hip_response_is_axis_specific_and_preset_owned() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	_expect(
		is_equal_approx(
			definition.hip_horizontal_response_degrees_per_second,
			190.0
		),
		"the Walker creator preset owns the tuned high-leverage horizontal hip target slew"
	)
	var slot: FourLimbSlotDefinition = definition.limbs[0]
	var points = EnemyGaitPlanner.solve_two_bone(
		slot.hip_offset,
		slot.rest_foot_offset,
		slot.upper_length,
		slot.lower_length,
		slot.bend_hint
	)
	var rig = FourLimbPhysicalRig3D.new()
	rig.definition = definition
	var generic_definition = rig._generic_definition_from_slot(slot, 0, points)
	var hip: LimbJointDefinition = generic_definition.segments[0].joint
	_expect(
		is_equal_approx(
			rad_to_deg(hip.target_response_radians_per_second(Vector3.AXIS_X)),
			definition.hip_horizontal_response_degrees_per_second
		)
		and is_equal_approx(
			rad_to_deg(hip.target_response_radians_per_second(Vector3.AXIS_Z)),
			hip.target_response_degrees_per_second
		),
		"horizontal hip sweep can be calmed without slowing the direct lift axis"
	)
	rig.free()
	var incomplete_record: Dictionary = definition.to_dictionary()
	incomplete_record.erase("hip_horizontal_response_degrees_per_second")
	_expect(
		FourLimbBodyDefinition.from_dictionary(incomplete_record) == null,
		"incomplete compatibility bodies fail closed instead of reconstructing missing Walker preset tuning"
	)
	var incomplete_limb_record: Dictionary = definition.to_dictionary()
	var incomplete_limbs: Array = incomplete_limb_record.get("limbs", [])
	incomplete_limbs[0] = {}
	incomplete_limb_record["limbs"] = incomplete_limbs
	_expect(
		FourLimbBodyDefinition.from_dictionary(incomplete_limb_record) == null,
		"incomplete compatibility limb records fail closed instead of rebuilding historical limb defaults"
	)


func _test_full_direction_obstacle_feed() -> void:
	var clear_probe = FourLimbTrainingObstacleSensor.clear_probe()
	var clearances: PackedFloat64Array = clear_probe.get(
		"ray_clearances_m",
		PackedFloat64Array()
	)
	_expect(
		clearances.size() == 26
		and FourLimbTrainingObstacleSensor.RAY_COUNT == 26,
		"the limb policy receives horizontal, upward, downward, ceiling, and floor wall rays"
	)
	_expect(
		(FourLimbTrainingObstacleSensor._yaw_basis(Basis.IDENTITY) * Vector3.FORWARD)
		.is_equal_approx(Vector3.FORWARD),
		"the forward lidar ray stays aligned with the body's forward direction"
	)
	var clear_observation = _sample_observation()
	var blocked_observation = clear_observation.duplicate(true)
	var objective: Dictionary = (blocked_observation["objective"] as Dictionary).duplicate(true)
	var blocked_probe = clear_probe.duplicate(true)
	var blocked_clearances = clearances.duplicate()
	blocked_clearances[0] = 0.4
	blocked_clearances[8] = 0.7
	blocked_clearances[16] = 0.6
	blocked_probe["ray_clearances_m"] = blocked_clearances
	blocked_probe["nearest_direction_yaw_local"] = Vector3.FORWARD
	blocked_probe["nearest_distance_m"] = 0.4
	blocked_probe["closing_speed_mps"] = 2.0
	blocked_probe["target_path_blocked"] = true
	blocked_probe["target_path_clearance_m"] = 1.0
	objective["obstacle_probe"] = blocked_probe
	blocked_observation["objective"] = objective
	_expect(
		not _arrays_close(
			FourLimbMLFeatureEncoder.encode(clear_observation),
			FourLimbMLFeatureEncoder.encode(blocked_observation)
		),
		"spatial-hash wall lidar and blocked target paths change the limb model input"
	)


func _test_missing_limb_keeps_its_slot() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	definition.limbs[2].installed = false
	_expect(definition.limbs.size() == 4, "removing a limb does not resize the four stable limb slots")
	var action = FourLimbMLAction.from_commands(FourLimbMLAction.neutral_commands())
	_expect(
		FourLimbMLAction.packed_commands(action).size() == FourLimbMLAction.ACTION_COUNT,
		"a missing limb keeps the full joint-and-grip policy output layout"
	)


func _test_attachment_feed_is_reserved() -> void:
	var feed = FourLimbAttachmentFeed.new()
	test_root.add_child(feed)
	feed.configure(MLBodyPresetLibrary.four_limb_walker_definition().attachment_slots)
	var provider = TestAttachment.new()
	_expect(feed.install_provider(1, provider), "a future gun-like provider installs into a fixed core slot")
	var features = feed.observation_features()
	var offset = FourLimbAttachmentFeed.FEATURES_PER_SLOT
	_expect(features.size() == 68, "four attachment slots always reserve the same observation space")
	_expect(is_equal_approx(features[offset], 1.0), "the model is told that the attachment is installed")
	_expect(is_equal_approx(features[offset + 2], 1.5 / 50.0), "the model is told how much mass the attachment adds")
	_expect(is_equal_approx(features[offset + 3], 1.0), "the model is told that the attachment belongs to the weapon category")
	_expect(is_equal_approx(features[offset + 7], 0.75), "attachment payload values reach the model feed")
	_expect(feed.install_provider(2, provider), "an attachment can be moved to another core mount")
	_expect(feed.provider_for_slot(1) == null, "moving an attachment clears its old model-feed slot")
	_expect(
		is_equal_approx(feed.total_contributed_mass(), 1.5),
		"moving an attachment does not count its mass twice"
	)
	feed.queue_free()


func _test_attachment_slot_rules_are_respected() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	definition.attachment_slots[0].allowed_tags = PackedStringArray(["weapon"])
	var feed = FourLimbAttachmentFeed.new()
	test_root.add_child(feed)
	feed.configure(definition.attachment_slots)
	var sensor = TestSensorAttachment.new()
	_expect(not feed.install_provider(0, sensor), "a slot reserved for weapons rejects an unrelated attachment")
	sensor.queue_free()
	var weapon = TestAttachment.new()
	_expect(feed.install_provider(0, weapon), "a compatible future weapon feed can use the reserved slot")
	feed.queue_free()


func _test_held_joint_targets_reach_the_model() -> void:
	var neutral = _sample_observation()
	var neutral_features = FourLimbMLFeatureEncoder.encode(neutral)

	var commanded = neutral.duplicate(true)
	var commanded_limbs: Array = commanded["limbs"]
	var commanded_limb = (commanded_limbs[0] as Dictionary).duplicate(true)
	commanded_limb["commands"] = Vector3(0.65, 0.0, 0.0)
	commanded_limbs[0] = commanded_limb
	commanded["limbs"] = commanded_limbs
	_expect(
		not _arrays_close(neutral_features, FourLimbMLFeatureEncoder.encode(commanded)),
		"the model can see the normalized policy command currently sent to each joint"
	)

	var held_target = neutral.duplicate(true)
	var target_limbs: Array = held_target["limbs"]
	var target_limb = (target_limbs[0] as Dictionary).duplicate(true)
	target_limb["joint_target_angles"] = Vector3(0.22, -0.17, 0.31)
	target_limb["joint_target_errors"] = Vector3(0.22, -0.17, 0.31)
	target_limbs[0] = target_limb
	held_target["limbs"] = target_limbs
	_expect(
		not _arrays_close(neutral_features, FourLimbMLFeatureEncoder.encode(held_target)),
		"the model can separately see the rate-limited physical target currently held by the actuator"
	)


func _test_observation_rejects_corrupt_proprioception() -> void:
	var valid = _sample_observation()
	_expect(FourLimbMLObservation.is_valid(valid), "a complete finite proprioceptive snapshot is accepted")
	var corrupt_joint = valid.duplicate(true)
	var corrupt_limbs: Array = corrupt_joint["limbs"]
	var first_limb = (corrupt_limbs[0] as Dictionary).duplicate(true)
	first_limb["joint_angular_velocities"] = Vector3(INF, 0.0, 0.0)
	corrupt_limbs[0] = first_limb
	corrupt_joint["limbs"] = corrupt_limbs
	_expect(
		not FourLimbMLObservation.is_valid(corrupt_joint),
		"a non-finite joint sensor value is rejected instead of being silently encoded as zero"
	)
	var corrupt_body = valid.duplicate(true)
	var body_state = (corrupt_body["body"] as Dictionary).duplicate(true)
	body_state["linear_velocity_world"] = Vector3(NAN, 0.0, 0.0)
	corrupt_body["body"] = body_state
	_expect(
		not FourLimbMLObservation.is_valid(corrupt_body),
		"a non-finite chassis sensor value cannot reach the policy"
	)
	var missing_support_contact = valid.duplicate(true)
	var incomplete_body = (missing_support_contact["body"] as Dictionary).duplicate(true)
	incomplete_body.erase("core_support_contact")
	missing_support_contact["body"] = incomplete_body
	_expect(
		not FourLimbMLObservation.is_valid(missing_support_contact),
		"the policy contract requires authoritative chassis-support contact state"
	)
	var corrupt_probe = valid.duplicate(true)
	var objective = (corrupt_probe["objective"] as Dictionary).duplicate(true)
	var probe = (objective["obstacle_probe"] as Dictionary).duplicate(true)
	var rays: PackedFloat64Array = probe["ray_clearances_m"]
	rays[3] = NAN
	probe["ray_clearances_m"] = rays
	objective["obstacle_probe"] = probe
	corrupt_probe["objective"] = objective
	_expect(
		not FourLimbMLObservation.is_valid(corrupt_probe),
		"a corrupt obstacle ray is rejected instead of changing meaning inside the encoder"
	)
	var malformed_probe = valid.duplicate(true)
	var malformed_objective = (malformed_probe["objective"] as Dictionary).duplicate(true)
	var malformed_probe_state = (malformed_objective["obstacle_probe"] as Dictionary).duplicate(true)
	malformed_probe_state["wall_contact"] = 1
	malformed_objective["obstacle_probe"] = malformed_probe_state
	malformed_probe["objective"] = malformed_objective
	_expect(
		not FourLimbMLObservation.is_valid(malformed_probe),
		"boolean and contact-count sensor fields cannot be silently coerced from another type"
	)
	var adapter = FourLimbMLBodyAdapter.new()
	_expect(
		adapter._validated_snapshot(valid).size() > 0
		and adapter._validated_snapshot(corrupt_joint).is_empty(),
		"the shared body adapter blocks corrupt sensor snapshots before reward or inference"
	)


func _test_missing_limb_keeps_model_compatibility() -> void:
	var intact = MLBodyPresetLibrary.four_limb_walker_definition()
	var damaged = MLBodyPresetLibrary.four_limb_walker_definition()
	damaged.limbs[1].installed = false
	_expect(
		intact.hardware_signature() == damaged.hardware_signature(),
		"an intact and missing-limb version can use the same locomotion model"
	)


func _test_workers_do_not_share_action_arrays() -> void:
	var first = FourLimbMLAction.neutral_commands()
	var second = FourLimbMLAction.neutral_commands()
	first[0] = 0.9
	_expect(is_zero_approx(second[0]), "one worker changing a joint command does not change another worker")


func _test_wrong_body_models_are_rejected() -> void:
	var model = FourLimbPPOModel.new()
	var fake_drone_checkpoint = {
		"artifact_type": "trained_drone_policy",
		"body_profile_id": "quadrotor_raw_propellers_v1",
		"network": {},
	}
	_expect(not model.load_checkpoint(fake_drone_checkpoint), "a drone model cannot be loaded into a four-limb body")


func _test_features_are_fixed_and_finite() -> void:
	var observation = _sample_observation()
	var features = FourLimbMLFeatureEncoder.encode(observation)
	_expect(
		FourLimbMLFeatureEncoder.FEATURE_COUNT == 420,
		"the schema-14 four-limb tensor exposes the documented 420 current physical/task features"
	)
	_expect(features.size() == FourLimbMLFeatureEncoder.FEATURE_COUNT, "every valid body snapshot produces the declared feature count")
	_expect(FourLimbMLFeatureEncoder.is_normalized(features), "body features remain finite and normalized")
	var feature_names = FourLimbMLFeatureEncoder.feature_names()
	var unique_names: Dictionary[String, bool] = {}
	for feature_name: String in feature_names:
		unique_names[feature_name] = true
	_expect(
		feature_names.size() == features.size()
		and unique_names.size() == features.size()
		and feature_names.find("turret_present") == FourLimbMLFeatureEncoder.BASE_FEATURE_COUNT
		and feature_names[feature_names.size() - 1] == "turret_threat_level",
		"every current feature has one unique semantic name and the turret block follows the complete limb state"
	)
	_expect(
		feature_names.has("limb_0_grip_target_present")
		and feature_names.has("limb_0_grip_target_offset_x")
		and feature_names.has("limb_0_grip_target_offset_y")
		and feature_names.has("limb_0_grip_target_offset_z")
		and feature_names.has("limb_0_grip_target_distance")
		and not feature_names.has("limb_0_grip_target_position_x"),
		"schema 14 gives PPO one coherent candidate-or-attached surface-to-surface grip target instead of an absolute or contradictory target point"
	)
	_expect(
		feature_names.has("limb_0_foot_up_x")
		and feature_names.has("limb_0_foot_up_y")
		and feature_names.has("limb_0_foot_up_z"),
		"schema 14 exposes the physical sole orientation directly so PPO can learn a flat planted foot without reconstructing full kinematics"
	)
	_expect(
		feature_names.has("pickup_item_reward_value"),
		"schema 14 exposes authored item value so a future take/deliver policy can distinguish otherwise identical items"
	)
	var valuable_item_observation: Dictionary = _sample_observation()
	var valuable_item_objective: Dictionary = (valuable_item_observation["objective"] as Dictionary).duplicate(true)
	valuable_item_objective["pickup_item_present"] = true
	valuable_item_objective["pickup_item_reward_value"] = 5.0
	valuable_item_observation["objective"] = valuable_item_objective
	var valuable_item_features: PackedFloat64Array = FourLimbMLFeatureEncoder.encode(valuable_item_observation)
	var reward_value_index: int = feature_names.find("pickup_item_reward_value")
	_expect(
		reward_value_index >= 0
		and is_equal_approx(valuable_item_features[reward_value_index], 0.5),
		"the authored training-item Reward value reaches the limb policy tensor instead of remaining UI-only metadata"
	)
	var attached_observation: Dictionary = _sample_observation()
	var attached_limbs: Array = attached_observation.get("limbs", [])
	var attached_limb: Dictionary = attached_limbs[0]
	attached_limb["grip_candidate_present"] = false
	attached_limb["grip_target_present"] = true
	attached_limb["grip_target_offset_local"] = Vector3(0.22, 0.0, 0.0)
	attached_limb["grip_target_distance"] = 0.22
	attached_limb["grip_attached"] = true
	var attached_features: PackedFloat64Array = FourLimbMLFeatureEncoder.encode(attached_observation)
	var target_present_index: int = feature_names.find("limb_0_grip_target_present")
	var target_offset_x_index: int = feature_names.find("limb_0_grip_target_offset_x")
	var target_distance_index: int = feature_names.find("limb_0_grip_target_distance")
	_expect(
		attached_features.size() == FourLimbMLFeatureEncoder.FEATURE_COUNT
		and target_present_index >= 0
		and is_equal_approx(attached_features[target_present_index], 1.0)
		and absf(attached_features[target_offset_x_index] - 0.20) < 0.0001
		and absf(attached_features[target_distance_index] - 0.20) < 0.0001,
		"an attached grip keeps its real anchor offset/distance visible instead of reverting to candidate-absent far state"
	)


func _test_proprioception_reaches_model() -> void:
	var baseline = _sample_observation()
	var baseline_features = FourLimbMLFeatureEncoder.encode(baseline)

	var moving_body = baseline.duplicate(true)
	var moving_body_state = (moving_body["body"] as Dictionary).duplicate(true)
	moving_body_state["linear_velocity_world"] = Vector3(1.2, -0.3, 0.6)
	moving_body_state["angular_velocity_world"] = Vector3(0.4, -0.7, 0.2)
	moving_body["body"] = moving_body_state
	_expect(
		not _arrays_close(baseline_features, FourLimbMLFeatureEncoder.encode(moving_body)),
		"the policy can distinguish chassis linear and angular motion"
	)

	var moved_joint = baseline.duplicate(true)
	var moved_limbs: Array = moved_joint["limbs"]
	var moved_limb = (moved_limbs[2] as Dictionary).duplicate(true)
	moved_limb["joint_angles"] = Vector3(0.25, -0.15, 0.35)
	moved_limb["joint_target_angles"] = Vector3(0.30, -0.10, 0.20)
	moved_limb["joint_target_errors"] = Vector3(0.05, 0.05, -0.15)
	moved_limb["joint_angular_velocities"] = Vector3(0.8, -0.4, 1.1)
	moved_limbs[2] = moved_limb
	moved_joint["limbs"] = moved_limbs
	_expect(
		not _arrays_close(baseline_features, FourLimbMLFeatureEncoder.encode(moved_joint)),
		"the policy can distinguish every limb's measured angles, targets, and speeds"
	)

	var changed_contact = baseline.duplicate(true)
	var contact_limbs: Array = changed_contact["limbs"]
	var contact_limb = (contact_limbs[1] as Dictionary).duplicate(true)
	contact_limb["foot_contact"] = false
	contact_limb["foot_clearance"] = 0.45
	contact_limb["foot_slip_speed"] = 1.4
	contact_limb["foot_velocity_local"] = Vector3(1.4, 0.0, -0.2)
	contact_limbs[1] = contact_limb
	changed_contact["limbs"] = contact_limbs
	_expect(
		not _arrays_close(baseline_features, FourLimbMLFeatureEncoder.encode(changed_contact)),
		"the policy can distinguish foot contact, clearance, velocity and slip"
	)

	var chassis_supported = baseline.duplicate(true)
	var supported_body = (chassis_supported["body"] as Dictionary).duplicate(true)
	supported_body["core_contact"] = true
	supported_body["core_support_contact"] = true
	supported_body["ground_clearance"] = 0.05
	chassis_supported["body"] = supported_body
	_expect(
		not _arrays_close(baseline_features, FourLimbMLFeatureEncoder.encode(chassis_supported)),
		"the policy is explicitly told when the chassis itself is carrying load on the ground"
	)


func _test_runtime_model_matches_training_model() -> void:
	var actor_critic = FourLimbPPOActorCritic.new(991)
	var observation = _sample_observation()
	var training_action = actor_critic.deterministic_action(observation)
	var runtime_model = FourLimbPPOModel.new()
	_expect(runtime_model.load_network_state(actor_critic.to_state()), "the runtime model accepts a training network state")
	var runtime_action = runtime_model.predict_action(observation)
	_expect(
		_arrays_close(
			FourLimbMLAction.packed_commands(training_action),
			FourLimbMLAction.packed_commands(runtime_action)
		),
		"runtime inference produces the same twelve joint targets as training inference"
	)


func _test_short_learning_update_stays_finite() -> void:
	var trainer = FourLimbPPOTrainer.new(443)
	trainer.config["rollout_size"] = 16
	trainer.config["epochs"] = 1
	trainer.config["batch_size"] = 8
	var observation = _sample_observation()
	var terminal_without_successor = trainer.sample_action(observation)
	_expect(
		trainer.add_transition(99, terminal_without_successor, -0.25, {}, true, false),
		"four-limb PPO retains a terminal failure without requiring a successor tensor"
	)
	trainer.discard_incomplete_rollout()
	var invalid_duration_sample = trainer.sample_action(observation)
	_expect(
		not trainer.add_transition(
			98,
			invalid_duration_sample,
			0.0,
			observation,
			false,
			false,
			NAN
		),
		"four-limb PPO rejects non-finite transition durations"
	)
	var malformed_tensor_sample: Dictionary = trainer.sample_action(observation).duplicate(true)
	malformed_tensor_sample["actor_input"] = {"wrong": true}
	_expect(
		not trainer.add_transition(96, malformed_tensor_sample, 0.0, observation, false, false),
		"four-limb PPO rejects malformed action tensors before typed tensor access"
	)
	var contradictory_boundary_sample = trainer.sample_action(observation)
	_expect(
		not trainer.add_transition(
			97,
			contradictory_boundary_sample,
			0.0,
			observation,
			true,
			true
		),
		"four-limb PPO rejects contradictory terminated-and-truncated boundaries"
	)
	for step_index in range(16):
		var sample = trainer.sample_action(observation)
		var terminal = step_index % 4 == 3
		_expect(
			trainer.add_transition(
				step_index % 4,
				sample,
				0.02 if not terminal else -0.1,
				observation,
				terminal,
				false
			),
			"a valid body decision can be added to the learning batch"
		)
	var metrics = trainer.update_if_ready(false)
	_expect(not metrics.is_empty() and not metrics.has("error"), "a short four-limb learning update completes")
	_expect(is_finite(float(metrics.get("actor_loss", NAN))), "the joint-policy learning error remains finite")
	_expect(is_finite(float(metrics.get("value_loss", NAN))), "the reward-prediction learning error remains finite")
	_expect(
		float(metrics.get("policy_parameter_delta_rms", 0.0)) > 0.0,
		"a completed four-limb PPO update actually changes the behavior parameters"
	)


func _test_background_learning_update_stays_finite() -> void:
	var trainer = FourLimbPPOTrainer.new(444)
	trainer.config["rollout_size"] = 8
	trainer.config["epochs"] = 1
	trainer.config["batch_size"] = 4
	var observation = _sample_observation()
	for step_index in range(8):
		var sample = trainer.sample_action(observation)
		trainer.add_transition(
			step_index % 2,
			sample,
			0.01,
			observation,
			step_index >= 6,
			false
		)
	var stale_sample = trainer.sample_action(observation)
	var previous_revision = trainer.behavior_policy_update
	_expect(trainer.begin_background_update(false), "four-limb PPO can leave the physics thread before optimizing")
	var environment_steps_before_skip: int = trainer.environment_steps
	_expect(
		trainer.add_transition(0, stale_sample, 0.01, observation, false, false)
		and trainer.rollout.is_empty()
		and trainer.environment_steps == environment_steps_before_skip + 1,
		"four-limb PPO discards on-policy data during optimization but still counts the physical environment step"
	)
	var result: Dictionary = {}
	var deadline_usec = Time.get_ticks_usec() + 5_000_000
	while result.is_empty() and Time.get_ticks_usec() < deadline_usec:
		await process_frame
		result = trainer.poll_background_update()
	_expect(not result.is_empty(), "the detached four-limb optimizer returns within the test deadline")
	_expect(not result.has("error"), "the detached four-limb optimizer completes without an error")
	_expect(is_finite(float(result.get("actor_loss", NAN))), "the detached actor loss remains finite")
	_expect(
		trainer.behavior_policy_update == trainer.update_count
		and trainer.behavior_policy_update > previous_revision,
		"a completed optimizer result becomes the visible behavior policy immediately"
	)
	var environment_steps_before_stale_boundary: int = trainer.environment_steps
	_expect(
		trainer.add_transition(0, stale_sample, 0.01, observation, false, false)
		and trainer.rollout.is_empty()
		and trainer.environment_steps == environment_steps_before_stale_boundary + 1,
		"a held limb action that straddles policy adoption is settled as an environment step but discarded from the new PPO rollout"
	)
	trainer.shutdown_background_update()


func _test_checkpoint_round_trip() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	var source = FourLimbPPOTrainer.new(551)
	var reward_deck = FourLimbRewardDeck.new()
	reward_deck.card("target_progress").intensity = 1.75
	reward_deck.card("foot_slip").enabled = false
	source.shuffle_rng.state = 123456789
	source.behavior_actor_critic.action_rng.state = 987654321
	var checkpoint = source.to_checkpoint(
		definition.hardware_signature(),
		reward_deck.configuration_dictionary()
	)
	var stored_cards: Dictionary = checkpoint.get("reward_cards", {})
	_expect(
		is_equal_approx(
			float((stored_cards.get("target_progress", {}) as Dictionary).get("intensity", 0.0)),
			1.75
		),
		"a four-limb checkpoint carries its reward-card intensities"
	)
	_expect(
		not bool((stored_cards.get("foot_slip", {}) as Dictionary).get("enabled", true)),
		"a four-limb checkpoint carries its reward-card switches"
	)
	var restored = FourLimbPPOTrainer.new(552)
	_expect(
		restored.load_checkpoint(checkpoint, definition.hardware_signature()),
		"a saved four-limb model loads back into the matching body"
	)
	_expect(
		restored.random_seed == 551
		and restored.shuffle_rng.state == 123456789
		and restored.behavior_actor_critic.action_rng.state == 987654321,
		"four-limb training checkpoints preserve seed, shuffle RNG, and exploration RNG continuation"
	)
	_expect(
		not restored.load_checkpoint(checkpoint, "different-anatomy"),
		"a model is rejected when the body anatomy contract is different"
	)
	var legacy_profile = checkpoint.duplicate(true)
	legacy_profile["body_profile_id"] = "four_limb_physics_v6"
	legacy_profile["observation_schema_version"] = 6
	legacy_profile["action_schema_version"] = 2
	var legacy_network = (legacy_profile.get("network", {}) as Dictionary).duplicate(true)
	legacy_network["body_profile_id"] = "four_limb_physics_v6"
	legacy_network["observation_schema_version"] = 6
	legacy_network["action_schema_version"] = 2
	legacy_profile["network"] = legacy_network
	_expect(
		not restored.load_checkpoint(legacy_profile, definition.hardware_signature()),
		"profile-v6 checkpoints are rejected because hip output 1 now controls a different axis"
	)
	var atomic_network = FourLimbPPOActorCritic.new(553)
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
		"a corrupt four-limb critic cannot partially replace the live actor"
	)
	var malformed_network_metadata: Dictionary = atomic_network.to_state().duplicate(true)
	malformed_network_metadata["feature_count"] = {"broken": true}
	_expect(
		not atomic_network.load_state(malformed_network_metadata),
		"four-limb network restore rejects wrong-type numeric metadata without throwing"
	)


func _test_checkpoint_score_sentinels_round_trip() -> void:
	var definition: FourLimbBodyDefinition = MLBodyPresetLibrary.four_limb_walker_definition()
	var source: FourLimbPPOTrainer = FourLimbPPOTrainer.new(554)
	var checkpoint: Dictionary = source.to_checkpoint(definition.hardware_signature())
	var restored: FourLimbPPOTrainer = FourLimbPPOTrainer.new(555)
	_expect(
		restored.load_checkpoint(checkpoint, definition.hardware_signature())
		and not is_finite(restored.best_episode_score)
		and not is_finite(restored.candidate_nomination_score),
		"four-limb checkpoint preserves the no-score sentinel instead of inventing a zero nomination floor"
	)
	source.best_episode_score = -3.5
	source.candidate_nomination_score = -1.25
	checkpoint = source.to_checkpoint(definition.hardware_signature())
	var negative_restore: FourLimbPPOTrainer = FourLimbPPOTrainer.new(556)
	_expect(
		negative_restore.load_checkpoint(checkpoint, definition.hardware_signature())
		and is_equal_approx(negative_restore.best_episode_score, -3.5)
		and is_equal_approx(negative_restore.candidate_nomination_score, -1.25),
		"four-limb checkpoint distinguishes a real negative nomination score from no nomination"
	)
	source.pending_candidate = {"candidate_id": {"wrong": true}}
	_expect(
		source.pending_evaluation_candidate_id() == -1,
		"four-limb Candidate identity access fails closed on malformed derived metadata"
	)


func _test_body_definition_round_trip_and_group_independence() -> void:
	var poisoned_body_record = MLBodyPresetLibrary.four_limb_walker_definition().to_dictionary()
	poisoned_body_record["core_mass"] = NAN
	poisoned_body_record["core_size"] = [NAN, 0.28, 0.92]
	var poisoned_limbs: Array = poisoned_body_record.get("limbs", [])
	var poisoned_first_limb: Dictionary = poisoned_limbs[0]
	poisoned_first_limb["upper_length"] = NAN
	poisoned_first_limb["hip_swing_span_degrees"] = NAN
	var poisoned_effector: Dictionary = poisoned_first_limb.get("end_effector", {})
	poisoned_effector["grip_stiffness"] = {"broken": true}
	poisoned_effector["grip_activation_threshold"] = NAN
	poisoned_first_limb["end_effector"] = poisoned_effector
	poisoned_limbs[0] = poisoned_first_limb
	poisoned_body_record["limbs"] = poisoned_limbs
	var poisoned_attachments: Array = poisoned_body_record.get("attachment_slots", [])
	var poisoned_attachment: Dictionary = poisoned_attachments[0]
	var poisoned_transform: Array = poisoned_attachment.get("core_offset", [])
	poisoned_transform[0] = {"broken": true}
	poisoned_transform[9] = NAN
	poisoned_attachment["core_offset"] = poisoned_transform
	poisoned_attachments[0] = poisoned_attachment
	poisoned_body_record["attachment_slots"] = poisoned_attachments
	var sanitized_body = FourLimbBodyDefinition.from_dictionary(poisoned_body_record)
	_expect(
		is_finite(sanitized_body.core_mass)
		and sanitized_body.core_size.is_finite()
		and is_finite(sanitized_body.limbs[0].upper_length)
		and is_finite(sanitized_body.limbs[0].hip_swing_span_degrees)
		and sanitized_body.limbs[0].end_effector != null
		and is_finite(sanitized_body.limbs[0].end_effector.grip_stiffness)
		and is_finite(sanitized_body.limbs[0].end_effector.grip_activation_threshold)
		and sanitized_body.attachment_slots[0].core_offset.origin.is_finite()
		and sanitized_body.attachment_slots[0].core_offset.basis.x.is_finite(),
		"serialized limb anatomy, end-effectors, and attachment ports cannot inject invalid numeric physics values"
	)
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	var first = coordinator.create_group(870, "Editable body", Color.WHITE, 2)
	var second = coordinator.create_group(871, "Independent body", Color.GRAY, 2)
	var edited = MLBodyPartContract.deep_duplicate_resource(coordinator.group_body_definition(870)) as FourLimbBodyDefinition
	edited.core_mass = 5.75
	edited.core_size.x = 1.15
	edited.limbs[0].upper_length = 1.48
	edited.limbs[2].hip_offset.z = 0.82
	_expect(
		coordinator.replace_group_body_definition(870, edited),
		"a paused limb group accepts a private physical-body replacement"
	)
	_expect(
		not is_equal_approx(
			coordinator.group_body_definition(870).core_mass,
			coordinator.group_body_definition(871).core_mass
		),
		"editing one limb group does not mutate another group's body"
	)
	var checkpoint = coordinator.save_checkpoint(870)
	_expect(
		checkpoint.get("body_definition", {}) is Dictionary,
		"a limb checkpoint stores the editable physical-body definition"
	)
	_expect(
		coordinator.load_checkpoint(871, checkpoint),
		"loading a limb checkpoint restores its matching custom anatomy"
	)
	var restored = coordinator.group_body_definition(871)
	_expect(
		is_equal_approx(restored.core_mass, 5.75)
		and is_equal_approx(restored.core_size.x, 1.15)
		and is_equal_approx(restored.limbs[0].upper_length, 1.48)
		and is_equal_approx(restored.limbs[2].hip_offset.z, 0.82),
		"custom core and per-limb values survive the checkpoint round trip"
	)
	coordinator.shutdown()


func _test_limb_policy_branch_variation() -> void:
	var source = FourLimbPPOTrainer.new(880)
	var exact = FourLimbPPOTrainer.new(881)
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	var checkpoint = source.to_checkpoint(definition.hardware_signature())
	_expect(
		exact.load_checkpoint(checkpoint, definition.hardware_signature()),
		"a limb branch can begin from an exact copy of live checkpoint weights"
	)
	var before = JSON.stringify(exact.stable_policy_state())
	_expect(
		exact.perturb_policy(0.025, 882),
		"a limb branch can apply the same bounded weight variation concept as drone PPO"
	)
	var after = JSON.stringify(exact.stable_policy_state())
	_expect(before != after, "non-zero limb branch variation changes the copied policy")


func _test_model_files_round_trip() -> void:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	var trainer = FourLimbPPOTrainer.new(553)
	var checkpoint = trainer.to_checkpoint(definition.hardware_signature())
	var registry = FourLimbModelRegistry.new(
		"user://tests/four_limb_model_registry_%d" % Time.get_ticks_usec()
	)
	var malformed_metadata = checkpoint.duplicate(true)
	malformed_metadata["schema_version"] = {"broken": true}
	_expect(
		registry.save_checkpoint("Malformed Limb Checkpoint", malformed_metadata).is_empty(),
		"four-limb registry rejects wrong-type checkpoint metadata without throwing"
	)
	var saved = registry.save_checkpoint("Four Limb Save Check", checkpoint)
	_expect(
		not saved.is_empty(),
		"a four-limb model is written to its own model folder"
	)
	var loaded = registry.load_checkpoint(saved)
	_expect(
		not loaded.is_empty()
		and str(loaded.get("hardware_signature", "")) == definition.hardware_signature(),
		"the saved four-limb model can be read back with the same body contract"
	)
	var incompatible = checkpoint.duplicate(true)
	incompatible["hardware_signature"] = "different-body-contract"
	_expect(
		registry.overwrite_checkpoint(saved, incompatible).is_empty()
		and not registry.load_checkpoint(saved).is_empty(),
		"keep-newest rejects a different limb body contract without deleting its saved source"
	)
	var corrupt_network = checkpoint.duplicate(true)
	corrupt_network["network"] = {}
	_expect(
		registry.overwrite_checkpoint(saved, corrupt_network).is_empty()
		and not registry.load_checkpoint(saved).is_empty(),
		"keep-newest rejects a structurally compatible but unusable limb network before replacing the saved source"
	)
	var overwritten = registry.overwrite_checkpoint(saved, checkpoint)
	_expect(
		not overwritten.is_empty()
		and str(overwritten.get("version_id", "")) == str(saved.get("version_id", ""))
		and int(overwritten.get("checkpoint_revision", 0)) == 2
		and bool(overwritten.get("overwritten_existing", false)),
		"keep-newest overwrites the group-owned limb version and advances its revision"
	)
	_expect(
		registry.list_models().size() == 1,
		"overwriting a limb model does not create another numbered version"
	)
	_expect(
		registry.delete_model(overwritten),
		"deleting the saved test model removes only that version"
	)


func _test_unified_coordinator_contract() -> void:
	_expect(
		FourLimbModelRegistry.DEFAULT_ROOT_PATH
		!= DroneTrainingModelRegistry.DEFAULT_ROOT_PATH,
		"four-limb and drone models use separate default storage roots"
	)
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	var first = coordinator.create_group(900, "Shared Room Limbs", Color.WHITE, 3)
	_expect(
		str(first.get("body_type", "")) == "four_limb",
		"the shared-room coordinator marks limb groups with their own body type"
	)
	_expect(
		first.get("reward_deck") is FourLimbRewardDeck,
		"a shared-room limb group keeps the original limb reward-card deck"
	)
	_expect(
		int(first.get("worker_count", 0)) == 3,
		"the shared-room coordinator preserves the requested limb worker count"
	)
	_expect(
		first.get("history") is DroneTrainingMetricsHistory,
		"a shared-room limb group owns the same plot-history type as a drone group"
	)
	_expect(
		bool(first.get("overwrite_saved_versions", false))
		and str(first.get("rolling_version_id", "missing")).is_empty(),
		"four-limb groups default to a fresh group-owned keep-newest save chain"
	)
	var limb_trainer = first["trainer"] as FourLimbPPOTrainer
	var incomplete_rollout: Array[Dictionary] = []
	incomplete_rollout.append({"incomplete": true})
	limb_trainer.rollout = incomplete_rollout
	limb_trainer.discard_incomplete_rollout()
	_expect(
		limb_trainer.rollout.is_empty(),
		"a limb worker-count restart can discard the old on-policy fragment like a drone group"
	)
	(first["reward_deck"] as FourLimbRewardDeck).card("target_progress").intensity = 1.6
	coordinator.set_worker_count(900, 5)
	_expect(
		int(first.get("worker_count", 0)) == 5
		and int(first.get("pending_worker_count", 0)) == 5,
		"a paused limb group applies its worker slider immediately instead of deferring it"
	)
	coordinator.set_control_interval(900, 0.1)
	var shared_checkpoint = coordinator.save_checkpoint(900)
	var shared_cards: Dictionary = shared_checkpoint.get("reward_cards", {})
	var room_settings: Dictionary = shared_checkpoint.get("room_settings", {})
	_expect(
		int(room_settings.get("worker_count", 0)) == 5,
		"a limb checkpoint preserves the selected worker count from the tuning hub"
	)
	_expect(
		is_equal_approx(float(room_settings.get("control_interval_seconds", 0.0)), 0.1),
		"a limb checkpoint preserves the selected control rate from the tuning hub"
	)
	_expect(
		coordinator.set_control_interval(900, NAN)
		and is_equal_approx(
			float(first.get("control_interval_seconds", 0.0)),
			FourLimbTrainingCoordinator.DECISION_INTERVAL_SECONDS
		),
		"the limb control-rate setter replaces non-finite values with the canonical interval"
	)
	var poisoned_checkpoint: Dictionary = shared_checkpoint.duplicate(true)
	var poisoned_settings: Dictionary = (poisoned_checkpoint.get("room_settings", {}) as Dictionary).duplicate(true)
	poisoned_settings["control_interval_seconds"] = NAN
	poisoned_checkpoint["room_settings"] = poisoned_settings
	_expect(
		coordinator.load_checkpoint(900, poisoned_checkpoint)
		and is_equal_approx(
			float(first.get("control_interval_seconds", 0.0)),
			FourLimbTrainingCoordinator.DECISION_INTERVAL_SECONDS
		),
		"a limb checkpoint cannot inject a non-finite scheduler interval"
	)
	var malformed_room_checkpoint: Dictionary = shared_checkpoint.duplicate(true)
	malformed_room_checkpoint["room_settings"] = "broken"
	_expect(
		not coordinator.load_checkpoint(900, malformed_room_checkpoint),
		"a limb checkpoint rejects malformed coordinator metadata before loading the policy"
	)
	var progress_card: Dictionary = shared_cards.get("target_progress", {})
	_expect(
		is_equal_approx(float(progress_card.get("intensity", 0.0)), 1.6),
		"saving a shared-room limb group keeps its selected reward-card intensities"
	)
	for index in range(1, FourLimbTrainingCoordinator.MAXIMUM_GROUP_COUNT):
		coordinator.create_group(
			900 + index,
			"Shared Room Limbs %d" % index,
			Color.WHITE,
			1
		)
	_expect(
		coordinator.create_group(999, "Excess Limb Group", Color.WHITE, 1).is_empty(),
		"the shared room refuses limb groups beyond its bounded layout capacity"
	)
	coordinator.shutdown()


func _test_background_step_accounting_reaches_trainer() -> void:
	var coordinator_source: String = FileAccess.get_file_as_string(
		"res://ml/training/four_limb/four_limb_training_coordinator.gd"
	)
	_expect(
		not coordinator_source.contains("episode_collects_training")
		and coordinator_source.contains("trainer.add_transition("),
		"four-limb coordinator submits physical action boundaries during background optimization so PPO can count-but-discard them consistently with drone workers"
	)


func _test_optimizer_swap_preserves_old_policy_interval() -> void:
	var coordinator_source: String = FileAccess.get_file_as_string(
		"res://ml/training/four_limb/four_limb_training_coordinator.gd"
	)
	_expect(
		not coordinator_source.contains("func _resample_active_workers")
		and coordinator_source.contains("held\n\t# old-policy action running until its normal control boundary"),
		"four-limb policy adoption leaves the open old-policy action interval intact until its normal decision boundary"
	)



func _test_unified_live_worker_count_and_progress_summary() -> void:
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	var group = coordinator.create_group(949, "Live UI Check", Color.WHITE, 1)
	group["active"] = true
	_expect(
		coordinator.apply_worker_count_now(
			949,
			3,
			Vector3(1.0, 2.0, -1.0),
			Vector3.ZERO,
			Vector3.ZERO,
			1.0,
			120.0,
			Vector3(80.0, 8.0, 80.0)
		),
		"an active limb worker slider can rebuild the current population immediately"
	)
	var workers: Array = group.get("workers", [])
	_expect(
		workers.size() == 3
		and int(group.get("worker_count", 0)) == 3
		and int(group.get("pending_worker_count", 0)) == 3,
		"the live limb population matches the slider value immediately"
	)
	var summaries = coordinator.episode_progress_summaries()
	var summary: Dictionary = summaries[0] if not summaries.is_empty() else {}
	_expect(
		bool(summary.get("active", false))
		and int(summary.get("episode", 0)) == int(group.get("episode", 0))
		and int(summary.get("instance_count", 0)) == 3
		and is_equal_approx(float(summary.get("duration", 0.0)), 120.0),
		"the Simulation & Camera UI can read live limb instance and episode progress"
	)
	coordinator.shutdown()


func _test_unified_spawn_uses_shared_marker() -> void:
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	var group = coordinator.create_group(950, "Spawn Check", Color.WHITE, 4)
	var requested = Vector3(6.5, 0.2, -3.25)
	var first_spawn = coordinator._worker_spawn_transform(
		group,
		0,
		4,
		requested,
		Vector3(80.0, 8.0, 80.0)
	)
	_expect(
		is_equal_approx(first_spawn.origin.x, requested.x)
		and is_equal_approx(first_spawn.origin.z, requested.z),
		"the first limb worker uses the shared room spawn marker exactly on X/Z"
	)
	_expect(
		first_spawn.origin.y >= coordinator._minimum_safe_spawn_height(),
		"the limb chassis is raised only enough to prevent its feet spawning inside the floor"
	)
	var second_spawn = coordinator._worker_spawn_transform(
		group,
		1,
		4,
		requested,
		Vector3(80.0, 8.0, 80.0)
	)
	_expect(
		Vector2(second_spawn.origin.x - requested.x, second_spawn.origin.z - requested.z).length()
		<= FourLimbTrainingCoordinator.WORKER_SPACING_M + 0.001,
		"additional limb workers stay in the immediate spawn-marker cluster"
	)
	var edge_requested = Vector3(39.0, 2.0, 39.0)
	var edge_spawn = coordinator._worker_spawn_transform(
		group,
		0,
		4,
		edge_requested,
		Vector3(80.0, 8.0, 80.0)
	)
	_expect(
		is_equal_approx(edge_spawn.origin.x, edge_requested.x)
		and is_equal_approx(edge_spawn.origin.z, edge_requested.z),
		"a valid spawn marker near the arena edge is not silently moved inward"
	)
	coordinator.shutdown()


func _test_unified_cleanup_accepts_already_freed_workers() -> void:
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	var group = coordinator.create_group(951, "Freed Worker Cleanup", Color.WHITE, 1)
	var body = FourLimbPhysicalBody3D.new()
	group["workers"] = [{"body": body, "adapter": null}]
	body.free()
	coordinator._clear_group_workers(group)
	_expect(
		(group.get("workers", []) as Array).is_empty(),
		"shared-room cleanup tolerates a worker body that Godot already freed"
	)
	var authored_item: TrainingItem3D = TrainingItem3D.new()
	test_root.add_child(authored_item)
	authored_item.configure_item(
		951,
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 0.4, "height": 0.4, "depth": 0.4},
		1.0,
		1.0,
		Transform3D(Basis.IDENTITY, Vector3(2.0, 0.2, 0.0)),
		true
	)
	group["workers"] = [{"body": null, "adapter": null, "pickup_item": authored_item}]
	coordinator._clear_group_workers(group)
	_expect(
		is_instance_valid(authored_item) and not authored_item.is_queued_for_deletion(),
		"limb episode cleanup never deletes an authored shared Training Item"
	)
	authored_item.queue_free()
	coordinator.shutdown()


func _test_fallback_pickup_prop_obeys_group_pause() -> void:
	var coordinator: FourLimbTrainingCoordinator = FourLimbTrainingCoordinator.new(test_root)
	var group: Dictionary = coordinator.create_group(9511, "Pickup Pause", Color.WHITE, 1)
	var reward_deck: FourLimbRewardDeck = group.get("reward_deck") as FourLimbRewardDeck
	reward_deck.card("item_pickup").enabled = false
	reward_deck.card("item_delivery").enabled = true
	_expect(
		coordinator._group_requires_task_item(group),
		"a delivery-only limb lesson still requires an assigned cargo item"
	)
	var item: FourLimbTrainingGrabbableItem3D = FourLimbTrainingGrabbableItem3D.new()
	test_root.add_child(item)
	item.reset_item(
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)),
		0,
		"Medical Crate"
	)
	_expect(
		item.item_type == "medical_crate",
		"the private fallback prop preserves the normalized cargo type required by delivery policy"
	)
	group["workers"] = [{
		"body": null,
		"adapter": null,
		"pickup_item": item,
		"finished": false,
	}]
	coordinator.set_group_active(
		9511,
		false,
		Vector3.ZERO,
		Vector3.ZERO,
		Vector3.ZERO,
		1.0,
		10.0,
		Vector3(20.0, 8.0, 20.0)
	)
	_expect(item.freeze, "a paused limb worker freezes its private fallback pickup prop")
	coordinator.set_group_active(
		9511,
		true,
		Vector3.ZERO,
		Vector3.ZERO,
		Vector3.ZERO,
		1.0,
		10.0,
		Vector3(20.0, 8.0, 20.0)
	)
	_expect(not item.freeze, "resuming the limb worker resumes its private pickup prop")
	coordinator._set_private_task_item_simulation_active(group["workers"][0], false)
	_expect(
		item.freeze,
		"a finished limb worker can freeze its private fallback prop instead of leaving stray task physics active until the group respawns"
	)
	item.reset_item(
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.2, 0.0)),
		0,
		"Medical Crate"
	)
	_expect(
		not item.freeze and item.simulation_active,
		"next-episode reset reactivates a fallback prop that the previous finished worker froze"
	)
	item.global_position = Vector3(0.0, -20.0, 0.0)
	_expect(
		coordinator._recover_lost_private_task_item(group["workers"][0], Vector3(20.0, 8.0, 20.0))
		and item.global_position.is_equal_approx(item.spawn_transform_world.origin),
		"a lost private fallback prop is recovered so the coordinator can terminate the impossible task instead of training against unreachable cargo"
	)
	item.queue_free()
	group["workers"] = []
	coordinator.shutdown()


func _test_terminal_grip_release_contract() -> void:
	var rig: FourLimbPhysicalRig3D = FourLimbPhysicalRig3D.new()
	var limb: GenericLimb3D = GenericLimb3D.new()
	var effector: LimbEndEffector3D = LimbEndEffector3D.new()
	var grip: GenericGrip3D = GenericGrip3D.new()
	effector.grip_actuator = grip
	limb.end_effector = effector
	rig.generic_limbs.append(limb)
	grip.attached = true
	grip.attached_target_id = 424242
	_expect(rig.holds_instance_id(424242), "the synthetic terminal worker begins with a held cargo id")
	rig.release_all_grips()
	_expect(
		not rig.holds_instance_id(424242) and not grip.attached,
		"terminal grip release surrenders shared cargo instead of leaving it latched to a frozen finished worker"
	)
	grip.attached = true
	grip.attached_target_id = 424242
	var teardown_body: FourLimbPhysicalBody3D = FourLimbPhysicalBody3D.new()
	teardown_body.physical_rig = rig
	var coordinator: FourLimbTrainingCoordinator = FourLimbTrainingCoordinator.new(test_root)
	var group: Dictionary = coordinator.create_group(9512, "Grip Teardown", Color.WHITE, 1)
	group["workers"] = [{"body": teardown_body, "adapter": null, "pickup_item": null}]
	coordinator._clear_group_workers(group)
	_expect(
		not rig.holds_instance_id(424242) and not grip.attached,
		"configuration-driven worker teardown releases shared cargo instead of applying pause semantics until the rig is freed"
	)
	coordinator.shutdown()
	rig.free()
	limb.free()
	effector.free()
	grip.free()


func _test_unified_episode_history_and_respawn() -> void:
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	var group = coordinator.create_group(952, "Respawn and Plot Check", Color.WHITE, 1)
	group["active"] = true
	group["episode"] = 4
	var observation = _sample_observation()
	var reward_state = (group["reward_deck"] as FourLimbRewardDeck).create_worker_state()
	reward_state["episode_totals"] = {
		"target_progress": 1.25,
		"failure": -2.0,
	}
	var worker = {
		"id": 0,
		"body": null,
		"adapter": null,
		"elapsed": 2.0,
		"total_reward": -0.75,
		"time_inside_radius_seconds": 0.5,
		"maximum_horizontal_displacement_m": 1.75,
		"failure_reason": "fallen_on_side",
		"reward_state": reward_state,
		"previous_physics_observation": observation,
		"episode_result": {},
		"finished": true,
	}
	worker["episode_result"] = coordinator._worker_episode_result(
		group, worker, observation
	)
	group["workers"] = [worker]
	coordinator._finish_group_episode(group)
	var history = group["history"] as DroneTrainingMetricsHistory
	var progress_series: Dictionary = history.episode_mean_series(
		"mean_reward_per_second", "reward/s", Color.WHITE
	)
	var failure_series: Dictionary = history.episode_mean_series(
		"cumulative_failure_reward", "failure", Color.WHITE
	)
	var progress_points: PackedVector2Array = progress_series.get(
		"points", PackedVector2Array()
	)
	_expect(
		progress_points.size() == 1,
		"a completed limb episode produces a point in the shared plotting history"
	)
	var failure_points: PackedVector2Array = failure_series.get(
		"points", PackedVector2Array()
	)
	_expect(
		failure_points.size() == 1 and failure_points[0].y < 0.0,
		"limb punishment totals remain negative in the reward-component plot"
	)
	var travel_series: Dictionary = history.episode_mean_series(
		"maximum_horizontal_displacement_m", "travel", Color.WHITE
	)
	var travel_points: PackedVector2Array = travel_series.get(
		"points", PackedVector2Array()
	)
	_expect(
		travel_points.size() == 1 and is_equal_approx(travel_points[0].y, 1.75),
		"the shared tracking plot exposes how far limb bodies actually moved"
	)
	_expect(
		(group.get("workers", []) as Array).size() == 1
		and bool(group.get("awaiting_respawn", false))
		and float(group.get("respawn_delay_remaining", 0.0)) > 0.0,
		"finishing a limb episode keeps the body node and schedules a drone-style reset"
	)
	# The old merged-room path treated this display flag as a hard simulation lock and
	# therefore never reset the retained worker population while PPO was working.
	group["optimizer_waiting"] = true
	coordinator._tick_group(
		group,
		FourLimbTrainingCoordinator.EPISODE_RESPAWN_DELAY_SECONDS + 0.01,
		Vector3(2.0, 2.0, -3.0),
		Vector3.ZERO,
		Vector3.ZERO,
		1.0,
		600.0,
		Vector3(80.0, 8.0, 80.0)
	)
	var restarted_worker: Dictionary = (group.get("workers", []) as Array)[0]
	var restarted_body = restarted_worker.get("body") as FourLimbPhysicalBody3D
	_expect(
		(group.get("workers", []) as Array).size() == 1
		and int(group.get("episode", 0)) == 5
		and is_equal_approx(float(restarted_worker.get("episode_duration", 0.0)), 600.0)
		and is_instance_valid(restarted_body)
		and restarted_body.training_invulnerable,
		"an active limb group reuses a tanky body for the full shared episode without waiting for PPO"
	)
	coordinator.shutdown()


func _test_unified_startup_ramp_and_terminal_contract() -> void:
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	_expect(
		FourLimbTrainingCoordinator.STARTUP_SETTLE_SECONDS >= 0.25
		and FourLimbTrainingCoordinator.STARTUP_SETTLE_SECONDS <= 0.5
		and FourLimbTrainingCoordinator.CONTROL_RAMP_SECONDS <= 0.0
		and is_equal_approx(coordinator._control_blend_factor(0.0), 1.0),
		"new limb episodes hold neutral posture briefly before exploratory policy commands"
	)
	_expect(
		FourLimbTrainingCoordinator.MAXIMUM_EPISODE_SECONDS >= 600.0,
		"four-limb workers honor the full shared-room episode-duration range"
	)
	_expect(
		coordinator.preset_body_template.core_maximum_health >= 1000000.0
		and coordinator.preset_body_template.limbs[0].maximum_health >= 1000000.0,
		"shared-room limb workers use a training-only tanky body definition"
	)
	var body = FourLimbPhysicalBody3D.new()
	var rig = FourLimbPhysicalRig3D.new()
	var core = LimbSegment3D.new()
	core.maximum_health = 100.0
	core.current_health = 100.0
	rig.core_bone = core
	rig.owner_body = body
	body.physical_rig = rig
	body.alive = true
	var worker = {
		"body": body,
		"episode_elapsed": 5.0,
		"episode_duration": 20.0,
		"runtime_fault_reason": "",
	}
	var extreme_pose_observation = {
		"body": {
			"position_world": Vector3(500.0, -20.0, 500.0),
			"uprightness": -1.0,
			"core_contact": true,
		}
	}
	var arena_exit = coordinator._worker_termination(
		worker,
		extreme_pose_observation,
		Vector3(80.0, 8.0, 80.0)
	)
	_expect(
		bool(arena_exit.get("finished", false))
		and str(arena_exit.get("reason", "")) == "left_arena",
		"a limb worker cannot continue falling through the room's open viewing edge"
	)
	var recoverable_side_pose = {
		"body": {
			"position_world": Vector3(0.0, 0.35, 0.0),
			"uprightness": -1.0,
			"core_contact": true,
		}
	}
	worker["runtime_fault_reason"] = "invalid_observation"
	_expect(
		not bool(coordinator._worker_termination(
			worker,
			recoverable_side_pose,
			Vector3(80.0, 8.0, 80.0)
		).get("finished", false)),
		"a sideways body inside the room remains alive so the policy can learn recovery"
	)
	worker["episode_elapsed"] = 20.0
	var timeout = coordinator._worker_termination(
		worker,
		extreme_pose_observation,
		Vector3(80.0, 8.0, 80.0)
	)
	_expect(
		bool(timeout.get("finished", false))
		and bool(timeout.get("timed_out", false)),
		"the episode timer removes the worker at the configured boundary"
	)
	worker["episode_elapsed"] = 5.0
	worker["runtime_fault_reason"] = ""
	body.definition = coordinator.preset_body_template
	body.training_invulnerable = true
	core.current_health = 0.0
	_expect(
		body.is_body_alive() and core.current_health > 0.0,
		"training invulnerability prevents one-frame physical-bone health deaths"
	)
	body.training_invulnerable = false
	body.kill("destroyed")
	var death = coordinator._worker_termination(
		worker,
		extreme_pose_observation,
		Vector3(80.0, 8.0, 80.0)
	)
	_expect(
		bool(death.get("finished", false))
		and not bool(death.get("timed_out", true))
		and str(death.get("reason", "")) == "destroyed",
		"actual body death still removes a limb worker immediately"
	)
	body.alive = true
	body.last_failure_reason = ""
	rig._stop_unstable_simulation()
	_expect(
		body.alive and body.last_failure_reason == "unstable_physics",
		"a genuine non-finite physics fault remains distinct from gameplay death"
	)
	core.free()
	rig.free()
	body.free()
	coordinator.shutdown()


func _test_arena_boundary_is_visible_and_terminal() -> void:
	var arena_size = Vector3(80.0, 8.0, 80.0)
	var inflation = Vector3(0.45, 0.2, 0.55)
	var center_distance = FourLimbTrainingObstacleSensor.arena_boundary_distance(
		Vector3.ZERO,
		Vector3.FORWARD,
		arena_size,
		inflation
	)
	_expect(
		is_equal_approx(center_distance, 40.0 - inflation.z),
		"the open room edge enters the same directional lidar feed as a non-traversable wall"
	)
	var near_edge_distance = FourLimbTrainingObstacleSensor.arena_boundary_distance(
		Vector3(0.0, 1.0, 35.0),
		Vector3.BACK,
		arena_size,
		inflation
	)
	_expect(
		near_edge_distance > 0.0
		and near_edge_distance < FourLimbMLObservation.OBSTACLE_RAY_MAXIMUM_DISTANCE_M,
		"a limb policy sees the open floor edge before its chassis reaches it"
	)
	var target_direction = Vector3(0.0, 0.0, 1.0)
	var target_distance = 12.0
	var target_edge_distance = FourLimbTrainingObstacleSensor.arena_boundary_distance(
		Vector3(0.0, 1.0, 35.0),
		target_direction,
		arena_size,
		inflation
	)
	_expect(
		target_edge_distance >= 0.0 and target_edge_distance < target_distance,
		"a target path that leaves the floor is detected as crossing the virtual arena boundary"
	)
	_expect(
		not FourLimbTrainingCoordinator.outside_horizontal_arena(
			Vector3(0.0, 1.0, 0.0),
			arena_size,
			0.6
		)
		and FourLimbTrainingCoordinator.outside_horizontal_arena(
			Vector3(0.0, 1.0, 39.6),
			arena_size,
			0.6
		),
		"the terminal boundary keeps the load-bearing chassis footprint on the floor"
	)


func _test_punishment_components_are_negative() -> void:
	var deck = FourLimbRewardDeck.new()
	var state = deck.create_worker_state()
	var previous = _sample_observation()
	var current = previous.duplicate(true)
	var current_body: Dictionary = (current["body"] as Dictionary).duplicate(true)
	current_body["ground_clearance"] = 0.08
	current_body["core_contact"] = true
	current_body["core_support_contact"] = true
	current_body["linear_velocity_world"] = Vector3(0.0, -3.0, 0.0)
	current["body"] = current_body
	var current_objective: Dictionary = (current["objective"] as Dictionary).duplicate(true)
	var danger_probe = FourLimbTrainingObstacleSensor.clear_probe()
	var danger_clearances = danger_probe["ray_clearances_m"] as PackedFloat64Array
	danger_clearances[0] = 0.2
	danger_probe["ray_clearances_m"] = danger_clearances
	danger_probe["nearest_distance_m"] = 0.2
	danger_probe["nearest_direction_yaw_local"] = Vector3.FORWARD
	danger_probe["closing_speed_mps"] = 3.0
	danger_probe["wall_contact"] = true
	danger_probe["wall_contact_count"] = 1
	danger_probe["maximum_contact_impulse"] = 20.0
	current_objective["obstacle_probe"] = danger_probe
	current["objective"] = current_objective
	var dangerous_limbs: Array = (current["limbs"] as Array).duplicate(true)
	for limb_value: Variant in dangerous_limbs:
		var limb: Dictionary = limb_value
		limb["foot_slip_speed"] = 4.0
		limb["applied_torque"] = Vector3(120.0, 120.0, 120.0)
		limb["saturation"] = Vector3.ONE
		limb["joint_angles"] = Vector3(deg_to_rad(67.0), deg_to_rad(71.0), deg_to_rad(70.0))
	current["limbs"] = dangerous_limbs
	var result = deck.step_reward(
		previous,
		current,
		0.4,
		state,
		{"action_change_norm": 1.0}
	)
	var components: Dictionary = result.get("components", {})
	for punishment_id in [
		"core_clearance", "core_drag", "foot_slip", "command_change", "actuator_saturation",
		"joint_overstretch",
		"torque_effort", "obstacle_avoidance", "core_collision", "falling",
		"target_search",
	]:
		_expect(
			float(components.get(punishment_id, 0.0)) < 0.0,
			"four-limb punishment '%s' contributes a visible negative value" % punishment_id
		)
	var terminal = deck.terminal_reward(state, "fallen_on_side", false)
	_expect(
		float((terminal.get("components", {}) as Dictionary).get("failure", 0.0)) < 0.0,
		"four-limb terminal failure contributes a visible negative punishment"
	)


func _test_item_pickup_reward_value_scales_reward() -> void:
	var previous: Dictionary = _pickup_observation(4242, 2.0, false)
	var grabbed: Dictionary = _pickup_observation(4242, 2.0, true)
	var lifted: Dictionary = _pickup_observation(4242, 2.20, true)

	var unit_deck: FourLimbRewardDeck = FourLimbRewardDeck.new()
	unit_deck.card("item_pickup").enabled = true
	var unit_state: Dictionary = unit_deck.create_worker_state()
	var unit_grab: Dictionary = unit_deck.step_reward(
		previous,
		grabbed,
		0.05,
		unit_state,
		{
			"assigned_pickup_item_id": 4242,
			"pickup_item_reward_value": 1.0,
		}
	)
	var unit_lift: Dictionary = unit_deck.step_reward(
		grabbed,
		lifted,
		0.05,
		unit_state,
		{
			"assigned_pickup_item_id": 4242,
			"pickup_item_reward_value": 1.0,
		}
	)

	var valuable_deck: FourLimbRewardDeck = FourLimbRewardDeck.new()
	valuable_deck.card("item_pickup").enabled = true
	var valuable_state: Dictionary = valuable_deck.create_worker_state()
	var valuable_grab: Dictionary = valuable_deck.step_reward(
		previous,
		grabbed,
		0.05,
		valuable_state,
		{
			"assigned_pickup_item_id": 4242,
			"pickup_item_reward_value": 3.0,
		}
	)
	var valuable_lift: Dictionary = valuable_deck.step_reward(
		grabbed,
		lifted,
		0.05,
		valuable_state,
		{
			"assigned_pickup_item_id": 4242,
			"pickup_item_reward_value": 3.0,
		}
	)
	var unit_component: float = (
		float((unit_grab.get("components", {}) as Dictionary).get("item_pickup", 0.0))
		+ float((unit_lift.get("components", {}) as Dictionary).get("item_pickup", 0.0))
	)
	var valuable_component: float = (
		float((valuable_grab.get("components", {}) as Dictionary).get("item_pickup", 0.0))
		+ float((valuable_lift.get("components", {}) as Dictionary).get("item_pickup", 0.0))
	)
	_expect(
		unit_component > 0.0
		and is_equal_approx(valuable_component, unit_component * 3.0),
		"authored training-item Reward value scales both first-grab and lift pickup reward"
	)


func _test_item_pickup_requires_worker_local_lift() -> void:
	var deck: FourLimbRewardDeck = FourLimbRewardDeck.new()
	deck.card("item_pickup").enabled = true
	var state: Dictionary = deck.create_worker_state()
	# The item is already high before this worker touches it. That inherited world height must not
	# satisfy the lift stage; only height gained after this worker's first observed grip counts.
	var before_grip: Dictionary = _pickup_observation(5151, 4.0, false)
	var first_grip: Dictionary = _pickup_observation(5151, 4.0, true)
	var grab_result: Dictionary = deck.step_reward(
		before_grip,
		first_grip,
		0.05,
		state,
		{
			"assigned_pickup_item_id": 5151,
			"pickup_item_reward_value": 1.0,
		}
	)
	_expect(
		(state.get("rewarded_pickup_ids", {}) as Dictionary).is_empty(),
		"grabbing an item that another worker already raised does not inherit the lift reward"
	)
	_expect(
		float((grab_result.get("components", {}) as Dictionary).get("item_pickup", 0.0)) > 0.0,
		"the first real grip still receives its discovery reward"
	)
	var after_lift: Dictionary = _pickup_observation(5151, 4.15, true)
	deck.step_reward(
		first_grip,
		after_lift,
		0.05,
		state,
		{
			"assigned_pickup_item_id": 5151,
			"pickup_item_reward_value": 1.0,
		}
	)
	_expect(
		(state.get("rewarded_pickup_ids", {}) as Dictionary).has(5151),
		"raising the item after gripping it earns the lift stage"
	)


func _test_item_delivery_reward_is_conditional_and_potential_based() -> void:
	var deck: FourLimbRewardDeck = FourLimbRewardDeck.new()
	for card_id: String in FourLimbRewardDeck.CARD_ORDER:
		var card: FourLimbRewardCard = deck.card(card_id)
		if card != null:
			card.enabled = false
	var delivery_card: FourLimbRewardCard = deck.card("item_delivery")
	delivery_card.enabled = true
	delivery_card.intensity = 1.0
	var state: Dictionary = deck.create_worker_state()
	var item_id: int = 8181
	var previous: Dictionary = _delivery_observation(item_id, 5.0, false)
	var closer: Dictionary = _delivery_observation(item_id, 4.6, false)
	var closer_result: Dictionary = deck.step_reward(
		previous,
		closer,
		0.05,
		state,
		_delivery_reward_context(item_id, 4.6, false)
	)
	_expect(
		float((closer_result.get("components", {}) as Dictionary).get("item_delivery", 0.0)) > 0.0,
		"an accepted held item earns signed delivery progress when it moves closer"
	)
	var farther: Dictionary = _delivery_observation(item_id, 5.0, false)
	var farther_result: Dictionary = deck.step_reward(
		closer,
		farther,
		0.05,
		state,
		_delivery_reward_context(item_id, 5.0, false)
	)
	_expect(
		float((farther_result.get("components", {}) as Dictionary).get("item_delivery", 0.0)) < 0.0,
		"moving held cargo away from its accepting destination gives the potential reward back"
	)
	var sibling_previous: Dictionary = _delivery_observation(item_id, 3.0, false)
	var sibling_previous_objective: Dictionary = (sibling_previous.get("objective", {}) as Dictionary).duplicate(true)
	sibling_previous_objective["delivery_destination_stable_id"] = "training_delivery:7:1"
	sibling_previous["objective"] = sibling_previous_objective
	var sibling_current: Dictionary = _delivery_observation(item_id, 2.6, false)
	var sibling_current_objective: Dictionary = (sibling_current.get("objective", {}) as Dictionary).duplicate(true)
	sibling_current_objective["delivery_destination_stable_id"] = "training_delivery:7:2"
	sibling_current["objective"] = sibling_current_objective
	var sibling_context: Dictionary = _delivery_reward_context(item_id, 2.6, false)
	sibling_context["delivery_destination_stable_id"] = "training_delivery:7:2"
	var sibling_result: Dictionary = deck.step_reward(
		sibling_previous,
		sibling_current,
		0.05,
		deck.create_worker_state(),
		sibling_context
	)
	_expect(
		float((sibling_result.get("components", {}) as Dictionary).get("item_delivery", 0.0)) > 0.0,
		"switching between sibling volumes in one destination group preserves the group's signed approach potential instead of creating a free zero-reward boundary"
	)

	# Nearest routing is allowed to switch between accepting destination groups. If the item was
	# already held outside all destinations, crossing into the newly selected group must still emit
	# completion instead of losing the event because its group id changed on the boundary frame.
	var group_switch_state: Dictionary = deck.create_worker_state()
	var group_switch_outside: Dictionary = _delivery_observation(8282, 1.0, false)
	deck.step_reward(
		group_switch_outside,
		group_switch_outside,
		0.05,
		group_switch_state,
		_delivery_reward_context(8282, 1.0, false)
	)
	var group_switch_inside: Dictionary = _delivery_observation(8282, 0.2, true)
	var group_switch_objective: Dictionary = (group_switch_inside.get("objective", {}) as Dictionary).duplicate(true)
	group_switch_objective["delivery_destination_group_id"] = 8
	group_switch_objective["delivery_destination_stable_id"] = "training_delivery:8:1"
	group_switch_inside["objective"] = group_switch_objective
	var group_switch_context: Dictionary = _delivery_reward_context(8282, 0.2, true)
	group_switch_context["delivery_destination_group_id"] = 8
	group_switch_context["delivery_destination_stable_id"] = "training_delivery:8:1"
	var group_switch_result: Dictionary = deck.step_reward(
		group_switch_outside,
		group_switch_inside,
		0.05,
		group_switch_state,
		group_switch_context
	)
	_expect(
		float((group_switch_result.get("components", {}) as Dictionary).get("item_delivery", 0.0)) > 1.0,
		"crossing into an accepting bay still completes delivery when nearest routing changes destination groups on the entry frame"
	)

	var delivered: Dictionary = _delivery_observation(item_id, 0.2, true)
	var delivered_result: Dictionary = deck.step_reward(
		farther,
		delivered,
		0.05,
		state,
		_delivery_reward_context(item_id, 0.2, true)
	)
	_expect(
		float((delivered_result.get("components", {}) as Dictionary).get("item_delivery", 0.0)) > 1.0,
		"entering the accepting volume while holding cargo adds the one-time completion reward"
	)
	var repeated_result: Dictionary = deck.step_reward(
		delivered,
		delivered,
		0.05,
		state,
		_delivery_reward_context(item_id, 0.2, true)
	)
	_expect(
		is_zero_approx(float((repeated_result.get("components", {}) as Dictionary).get("item_delivery", 0.0))),
		"remaining inside the same destination cannot farm repeated completion reward"
	)
	var moved_out_other_group: Dictionary = _delivery_observation(item_id, 1.0, false)
	var moved_out_other_objective: Dictionary = (moved_out_other_group.get("objective", {}) as Dictionary).duplicate(true)
	moved_out_other_objective["delivery_destination_group_id"] = 8
	moved_out_other_objective["delivery_destination_stable_id"] = "training_delivery:8:1"
	moved_out_other_group["objective"] = moved_out_other_objective
	var moved_out_other_context: Dictionary = _delivery_reward_context(item_id, 1.0, false)
	moved_out_other_context["delivery_destination_group_id"] = 8
	moved_out_other_context["delivery_destination_stable_id"] = "training_delivery:8:1"
	deck.step_reward(
		delivered,
		moved_out_other_group,
		0.05,
		state,
		moved_out_other_context
	)
	var entered_other_group: Dictionary = _delivery_observation(item_id, 0.0, true)
	var entered_other_objective: Dictionary = (entered_other_group.get("objective", {}) as Dictionary).duplicate(true)
	entered_other_objective["delivery_destination_group_id"] = 8
	entered_other_objective["delivery_destination_stable_id"] = "training_delivery:8:1"
	entered_other_group["objective"] = entered_other_objective
	var entered_other_context: Dictionary = _delivery_reward_context(item_id, 0.0, true)
	entered_other_context["delivery_destination_group_id"] = 8
	entered_other_context["delivery_destination_stable_id"] = "training_delivery:8:1"
	var second_group_result: Dictionary = deck.step_reward(
		moved_out_other_group,
		entered_other_group,
		0.05,
		state,
		entered_other_context
	)
	_expect(
		float((second_group_result.get("components", {}) as Dictionary).get("item_delivery", 0.0)) <= 1.0,
		"one physical cargo item cannot earn another completion bonus merely by entering a second accepting destination group in the same episode"
	)
	var not_held_context: Dictionary = _delivery_reward_context(item_id, 4.0, false)
	not_held_context["delivery_item_held"] = false
	var not_held: Dictionary = deck.step_reward(
		previous,
		closer,
		0.05,
		deck.create_worker_state(),
		not_held_context
	)
	_expect(
		is_zero_approx(float((not_held.get("components", {}) as Dictionary).get("item_delivery", 0.0))),
		"delivery approach shaping is conditional on actually holding the accepted item"
	)

	# Cargo that is first observed as held while already inside a matching bay is already delivered.
	# It must not be able to mint a completion bonus by walking out and re-entering that same policy.
	var pre_delivered_state: Dictionary = deck.create_worker_state()
	var pre_delivered_inside: Dictionary = _delivery_observation(9191, 0.2, true)
	deck.step_reward(
		pre_delivered_inside,
		pre_delivered_inside,
		0.05,
		pre_delivered_state,
		_delivery_reward_context(9191, 0.2, true)
	)
	var pre_delivered_outside: Dictionary = _delivery_observation(9191, 2.0, false)
	deck.step_reward(
		pre_delivered_inside,
		pre_delivered_outside,
		0.05,
		pre_delivered_state,
		_delivery_reward_context(9191, 2.0, false)
	)
	var pre_delivered_return: Dictionary = _delivery_observation(9191, 0.2, true)
	deck.step_reward(
		pre_delivered_outside,
		pre_delivered_return,
		0.05,
		pre_delivered_state,
		_delivery_reward_context(9191, 0.2, true)
	)
	var pre_delivered_keys: Dictionary = pre_delivered_state.get("rewarded_delivery_keys", {})
	_expect(
		pre_delivered_keys.is_empty(),
		"cargo first picked up inside an accepting destination cannot farm completion by stepping out and back into the bay"
	)

	var phase_deck: FourLimbRewardDeck = FourLimbRewardDeck.new()
	for phase_card_id: String in FourLimbRewardDeck.CARD_ORDER:
		var phase_card: FourLimbRewardCard = phase_deck.card(phase_card_id)
		if phase_card != null:
			phase_card.enabled = false
	phase_deck.card("target_progress").enabled = true
	phase_deck.card("target_progress").intensity = 1.0
	var pickup_phase_observation: Dictionary = _sample_observation()
	var pickup_phase_objective: Dictionary = (pickup_phase_observation.get("objective", {}) as Dictionary).duplicate(true)
	pickup_phase_objective["target_position_world"] = Vector3(0.0, 1.5, -1.0)
	pickup_phase_objective["delivery_task_phase"] = "pickup"
	pickup_phase_observation["objective"] = pickup_phase_objective
	var carry_phase_observation: Dictionary = pickup_phase_observation.duplicate(true)
	var carry_phase_body: Dictionary = (carry_phase_observation.get("body", {}) as Dictionary).duplicate(true)
	# Move one metre toward the *new* destination during the semantic phase swap. Without the
	# phase guard below, generic target-progress would incorrectly credit that movement even though
	# the action was chosen while the policy was still targeting the pickup item.
	carry_phase_body["position_world"] = Vector3(0.0, 1.5, -1.0)
	carry_phase_observation["body"] = carry_phase_body
	var carry_phase_objective: Dictionary = (carry_phase_observation.get("objective", {}) as Dictionary).duplicate(true)
	carry_phase_objective["target_position_world"] = Vector3(0.0, 1.5, -10.0)
	carry_phase_objective["delivery_task_phase"] = "delivery"
	carry_phase_observation["objective"] = carry_phase_objective
	var phase_switch_result: Dictionary = phase_deck.step_reward(
		pickup_phase_observation,
		carry_phase_observation,
		0.05,
		phase_deck.create_worker_state()
	)
	_expect(
		is_zero_approx(float((phase_switch_result.get("components", {}) as Dictionary).get("target_progress", 1.0))),
		"switching the shared task target from cargo to destination does not create a fake target-progress penalty on the successful grip frame"
	)


func _test_core_rotational_stability_ignores_yaw_and_penalizes_rocking() -> void:
	var delta = 0.05
	var calm = FourLimbRewardDeck.core_rotational_stability_signal(
		Vector3.ZERO,
		Vector3.ZERO,
		delta
	)
	var smooth_yaw = FourLimbRewardDeck.core_rotational_stability_signal(
		Vector3(0.0, 5.0, 0.0),
		Vector3(0.0, 5.0, 0.0),
		delta
	)
	var reversing_yaw = FourLimbRewardDeck.core_rotational_stability_signal(
		Vector3(0.0, -5.0, 0.0),
		Vector3(0.0, 5.0, 0.0),
		delta
	)
	var steady_roll = FourLimbRewardDeck.core_rotational_stability_signal(
		Vector3(2.5, 0.0, 0.0),
		Vector3(2.5, 0.0, 0.0),
		delta
	)
	var jittering_roll = FourLimbRewardDeck.core_rotational_stability_signal(
		Vector3(-2.5, 0.0, 0.0),
		Vector3(2.5, 0.0, 0.0),
		delta
	)
	_expect(
		calm > 0.0 and is_equal_approx(smooth_yaw, calm),
		"core rotational stability rewards calm support while sustained deliberate yaw remains free"
	)
	_expect(
		reversing_yaw < 0.0 and reversing_yaw < smooth_yaw,
		"rapid left-right yaw reversal is punished as rotational jitter without charging steady turning"
	)
	_expect(
		steady_roll < 0.0 and jittering_roll < steady_roll,
		"pitch/roll motion is discouraged and a rapid horizontal-axis reversal is punished more strongly"
	)
	var long_jump_cards = TrainingRewardCardsetLibrary.new().cardsets_for_body_type(
		TrainingRewardCardsetLibrary.BODY_TYPE_FOUR_LIMB
	)
	var jump_cardset: Dictionary = {}
	for cardset_value: Variant in long_jump_cards:
		var cardset: Dictionary = cardset_value
		if str(cardset.get("id", "")) == "builtin:limb_long_jump":
			jump_cardset = cardset
			break
	var jump_config: Dictionary = jump_cardset.get("cards", {})
	var jump_rotation: Dictionary = jump_config.get("core_rotational_stability", {})
	_expect(
		not bool(jump_rotation.get("enabled", true)),
		"the long-jump lesson disables rotational steadiness so airborne pitch/roll remains available"
	)


func _test_contact_flicker_cannot_farm_jump_rewards() -> void:
	var deck = FourLimbRewardDeck.new()
	for card_id: String in ["jump_launch", "jump_air_progress", "jump_distance", "landing_quality"]:
		deck.card(card_id).enabled = true
	var state = deck.create_worker_state()
	var supported = _sample_observation()
	deck.step_reward(supported, supported, 0.10, state)
	deck.step_reward(supported, supported, 0.10, state)
	var flicker_air = _with_foot_support(supported, false)
	var flicker_body: Dictionary = (flicker_air["body"] as Dictionary).duplicate(true)
	flicker_body["linear_velocity_world"] = Vector3(0.0, 0.70, 0.0)
	flicker_body["ground_clearance"] = 1.27
	flicker_air["body"] = flicker_body
	var launch_result = deck.step_reward(supported, flicker_air, 0.05, state)
	var landed = _with_foot_support(flicker_air, true)
	var landing_body: Dictionary = (landed["body"] as Dictionary).duplicate(true)
	landing_body["linear_velocity_world"] = Vector3.ZERO
	landing_body["ground_clearance"] = 1.25
	landed["body"] = landing_body
	var landing_result = deck.step_reward(flicker_air, landed, 0.10, state)
	for result: Dictionary in [launch_result, landing_result]:
		var components: Dictionary = result.get("components", {})
		for card_id: String in ["jump_launch", "jump_air_progress", "jump_distance", "landing_quality"]:
			_expect(
				is_zero_approx(float(components.get(card_id, 0.0))),
				"brief support flicker pays no '%s' jump reward" % card_id
			)


func _test_in_place_hop_cannot_farm_landing_reward() -> void:
	var deck = FourLimbRewardDeck.new()
	for card_id: String in ["jump_launch", "jump_air_progress", "jump_distance", "landing_quality"]:
		deck.card(card_id).enabled = true
	var state = deck.create_worker_state()
	var supported = _sample_observation()
	deck.step_reward(supported, supported, 0.10, state)
	deck.step_reward(supported, supported, 0.10, state)
	var launch = _with_foot_support(supported, false)
	var launch_body: Dictionary = (launch["body"] as Dictionary).duplicate(true)
	launch_body["linear_velocity_world"] = Vector3(0.0, 1.50, 0.0)
	launch["body"] = launch_body
	deck.step_reward(supported, launch, 0.05, state)
	var airborne = _with_foot_support(launch, false)
	var airborne_body: Dictionary = (airborne["body"] as Dictionary).duplicate(true)
	airborne_body["position_world"] = Vector3(0.0, 1.75, 0.0)
	airborne_body["linear_velocity_world"] = Vector3(0.0, 0.20, 0.0)
	airborne_body["ground_clearance"] = 1.50
	airborne["body"] = airborne_body
	deck.step_reward(launch, airborne, 0.20, state)
	var landed = _with_foot_support(airborne, true)
	var landing_body: Dictionary = (landed["body"] as Dictionary).duplicate(true)
	landing_body["position_world"] = Vector3(0.0, 1.50, 0.0)
	landing_body["linear_velocity_world"] = Vector3.ZERO
	landing_body["ground_clearance"] = 1.25
	landed["body"] = landing_body
	var landing_result = deck.step_reward(airborne, landed, 0.10, state)
	var landing_components: Dictionary = landing_result.get("components", {})
	_expect(
		is_zero_approx(float(landing_components.get("jump_distance", 0.0)))
		and is_zero_approx(float(landing_components.get("landing_quality", 0.0))),
		"a qualified in-place jumping-jack hop cannot farm distance or controlled-landing reward"
	)


func _test_qualified_jump_and_landing_are_rewarded() -> void:
	var deck = FourLimbRewardDeck.new()
	for card_id: String in ["jump_launch", "jump_air_progress", "jump_distance", "landing_quality"]:
		deck.card(card_id).enabled = true
	var state = deck.create_worker_state()
	var supported = _sample_observation()
	deck.step_reward(supported, supported, 0.10, state)
	deck.step_reward(supported, supported, 0.10, state)
	var launch = _with_foot_support(supported, false)
	var launch_body: Dictionary = (launch["body"] as Dictionary).duplicate(true)
	launch_body["linear_velocity_world"] = Vector3(0.0, 1.50, -2.0)
	launch["body"] = launch_body
	deck.step_reward(supported, launch, 0.05, state)
	var airborne = _with_foot_support(launch, false)
	var airborne_body: Dictionary = (airborne["body"] as Dictionary).duplicate(true)
	airborne_body["position_world"] = Vector3(0.0, 1.75, -0.60)
	airborne_body["linear_velocity_world"] = Vector3(0.0, 0.20, -2.0)
	airborne_body["ground_clearance"] = 1.50
	airborne["body"] = airborne_body
	var airborne_result = deck.step_reward(launch, airborne, 0.20, state)
	var airborne_components: Dictionary = airborne_result.get("components", {})
	_expect(
		float(airborne_components.get("jump_launch", 0.0)) > 0.0
		and float(airborne_components.get("jump_air_progress", 0.0)) > 0.0,
		"a jump pays takeoff and airborne progress only after real height and airtime"
	)
	var landed = _with_foot_support(airborne, true)
	var landing_body: Dictionary = (landed["body"] as Dictionary).duplicate(true)
	landing_body["position_world"] = Vector3(0.0, 1.50, -1.0)
	landing_body["linear_velocity_world"] = Vector3.ZERO
	landing_body["ground_clearance"] = 1.25
	landed["body"] = landing_body
	var landing_result = deck.step_reward(airborne, landed, 0.10, state)
	var landing_components: Dictionary = landing_result.get("components", {})
	_expect(
		float(landing_components.get("jump_distance", 0.0)) > 0.0
		and float(landing_components.get("landing_quality", 0.0)) > 0.0,
		"a qualified forward jump can still earn distance and controlled-landing reward"
	)


func _test_dead_limb_workers_are_not_camera_targets() -> void:
	_expect(
		not DroneTrainingRoom._limb_worker_is_camera_focus_candidate(
			{"finished": true},
			null
		),
		"finished limb workers are rejected before selected-group camera focus is calculated"
	)
	var dead_body = FourLimbPhysicalBody3D.new()
	dead_body.alive = false
	_expect(
		not DroneTrainingRoom._limb_worker_is_camera_focus_candidate(
			{"finished": false},
			dead_body
		),
		"dead limb bodies are rejected even before the worker record is marked finished"
	)
	dead_body.free()


func _test_target_progress_is_not_gated_by_posture() -> void:
	var deck = FourLimbRewardDeck.new()
	var previous = _sample_observation()
	var upright_current = previous.duplicate(true)
	var upright_body: Dictionary = (upright_current["body"] as Dictionary).duplicate(true)
	upright_body["position_world"] = Vector3(0.0, 1.5, -0.5)
	upright_body["transform_world"] = Transform3D(Basis.IDENTITY, upright_body["position_world"])
	upright_current["body"] = upright_body
	var upright_result = deck.step_reward(
		previous,
		upright_current,
		0.05,
		deck.create_worker_state()
	)
	var upright_components: Dictionary = upright_result.get("components", {})
	_expect(
		float(upright_components.get("target_progress", 0.0)) > 0.0,
		"distance gained while the chassis is carried by planted legs remains useful progress"
	)

	# The navigation objective must remain visible before the body has learned a clean gait, but
	# chassis-supported rolling/crawling is an explicit exploit state rather than merely poor posture.
	var rolling_current = previous.duplicate(true)
	var rolling_body: Dictionary = (rolling_current["body"] as Dictionary).duplicate(true)
	rolling_body["position_world"] = Vector3(0.0, 1.5, -0.04)
	rolling_body["transform_world"] = Transform3D(Basis.IDENTITY, rolling_body["position_world"])
	rolling_body["uprightness"] = 0.0
	rolling_body["core_contact"] = true
	rolling_body["core_support_contact"] = true
	rolling_body["ground_clearance"] = 0.10
	rolling_current["body"] = rolling_body
	var rolling_limbs: Array = (rolling_current["limbs"] as Array).duplicate(true)
	for limb_value: Variant in rolling_limbs:
		var limb: Dictionary = limb_value
		limb["foot_contact"] = false
	rolling_current["limbs"] = rolling_limbs
	var rolling_state = deck.create_worker_state()
	rolling_state["collision_active"] = true
	var rolling_result = deck.step_reward(
		previous,
		rolling_current,
		0.05,
		rolling_state
	)
	var rolling_components: Dictionary = rolling_result.get("components", {})
	_expect(
		float(rolling_components.get("target_progress", 0.0)) > 0.0
		and absf(
			float(rolling_components.get("target_progress", 0.0))
			- float(upright_components.get("target_progress", 0.0)) * 0.008
		) <= 0.00001
		and float(rolling_components.get("core_drag", 0.0)) < 0.0
		and float(rolling_result.get("total", 0.0)) < 0.0,
		"chassis-supported rolling keeps only a recovery hint of positive target progress and is net-negative under the stock deck"
	)

	var high_priority_deck = FourLimbRewardDeck.new()
	high_priority_deck.card("target_progress").intensity = 4.0
	var high_priority_state = high_priority_deck.create_worker_state()
	high_priority_state["collision_active"] = true
	var high_priority_result = high_priority_deck.step_reward(
		previous,
		rolling_current,
		0.05,
		high_priority_state
	)
	_expect(
		float(high_priority_result.get("total", 0.0)) > float(rolling_result.get("total", 0.0)),
		"raising target priority directly strengthens real targetward motion instead of being capped by posture quality"
	)

	var wall_brush_current = upright_current.duplicate(true)
	var wall_brush_body = (wall_brush_current["body"] as Dictionary).duplicate(true)
	wall_brush_body["core_contact"] = true
	wall_brush_body["core_support_contact"] = false
	wall_brush_body["core_wall_contact"] = true
	wall_brush_current["body"] = wall_brush_body
	var wall_brush_result = deck.step_reward(
		previous,
		wall_brush_current,
		0.05,
		deck.create_worker_state()
	)
	var wall_brush_components: Dictionary = wall_brush_result.get("components", {})
	_expect(
		float(wall_brush_components.get("target_progress", 0.0)) > 0.0
		and is_zero_approx(float(wall_brush_components.get("core_drag", 0.0))),
		"a brief upright wall brush is not misclassified as chassis crawling"
	)

	var moving_away = rolling_current.duplicate(true)
	var away_body: Dictionary = (moving_away["body"] as Dictionary).duplicate(true)
	away_body["position_world"] = Vector3(0.0, 1.5, 0.04)
	away_body["transform_world"] = Transform3D(Basis.IDENTITY, away_body["position_world"])
	moving_away["body"] = away_body
	var away_state = deck.create_worker_state()
	away_state["collision_active"] = true
	var away_result = deck.step_reward(
		previous,
		moving_away,
		0.05,
		away_state
	)
	_expect(
		float((away_result.get("components", {}) as Dictionary).get("target_progress", 0.0)) < 0.0,
		"moving away from the target stays fully negative in every posture"
	)


func _test_full_3d_target_reward_and_climb_context() -> void:
	var deck = FourLimbRewardDeck.new()
	var previous = _sample_observation()
	var elevated_previous = previous.duplicate(true)
	var elevated_objective: Dictionary = (elevated_previous["objective"] as Dictionary).duplicate(true)
	elevated_objective["target_position_world"] = Vector3(0.0, 3.0, 0.0)
	elevated_objective["target_radius"] = 0.20
	elevated_previous["objective"] = elevated_objective
	var elevated_current = elevated_previous.duplicate(true)
	var elevated_body: Dictionary = (elevated_current["body"] as Dictionary).duplicate(true)
	elevated_body["position_world"] = Vector3(0.0, 1.65, 0.0)
	elevated_body["transform_world"] = Transform3D(Basis.IDENTITY, elevated_body["position_world"])
	elevated_current["body"] = elevated_body
	var elevated_result = deck.step_reward(
		elevated_previous,
		elevated_current,
		0.05,
		deck.create_worker_state()
	)
	_expect(
		float((elevated_result.get("components", {}) as Dictionary).get("target_progress", 0.0)) > 0.0
		and FourLimbRewardDeck.target_goal_distance(
			elevated_body,
			elevated_objective
		) > 1.0,
		"vertical motion toward an elevated routed objective now earns target progress and still has distance left"
	)

	var climb_observation = _sample_observation()
	var climb_limbs: Array = (climb_observation["limbs"] as Array).duplicate(true)
	var climb_limb: Dictionary = (climb_limbs[0] as Dictionary).duplicate(true)
	climb_limb["grip_command"] = 1.0
	climb_limb["grip_activation"] = 1.0
	climb_limb["grip_candidate_climbable"] = true
	climb_limb["grip_candidate_distance"] = 0.02
	climb_limb["end_effector"] = {"grip_acquisition_radius": 0.24, "grip_detection_radius": 1.10}
	climb_limbs[0] = climb_limb
	climb_observation["limbs"] = climb_limbs
	var ground_objective: Dictionary = (climb_observation["objective"] as Dictionary).duplicate(true)
	ground_objective["target_position_world"] = Vector3(0.0, 2.0, -5.0)
	ground_objective["target_subject_position_world"] = Vector3(0.0, 0.0, -5.0)
	climb_observation["objective"] = ground_objective
	var ground_result = deck.step_reward(
		climb_observation,
		climb_observation,
		0.05,
		deck.create_worker_state()
	)
	var elevated_climb = climb_observation.duplicate(true)
	var box_objective: Dictionary = (elevated_climb["objective"] as Dictionary).duplicate(true)
	box_objective["target_position_world"] = Vector3(0.0, 4.0, -5.0)
	box_objective["target_subject_position_world"] = Vector3(0.0, 2.0, -5.0)
	elevated_climb["objective"] = box_objective
	var box_result = deck.step_reward(
		elevated_climb,
		elevated_climb,
		0.05,
		deck.create_worker_state()
	)
	_expect(
		is_zero_approx(float((ground_result.get("components", {}) as Dictionary).get("climb_grip", 0.0)))
		and is_zero_approx(float((box_result.get("components", {}) as Dictionary).get("climb_grip", 0.0))),
		"neither the ordinary path-height offset nor merely requesting grip beside a wall can farm climbing reward"
	)

	var reach_previous = elevated_climb.duplicate(true)
	var reach_previous_limbs: Array = (reach_previous["limbs"] as Array).duplicate(true)
	var reach_previous_limb: Dictionary = (reach_previous_limbs[0] as Dictionary).duplicate(true)
	reach_previous_limb["grip_candidate_present"] = true
	reach_previous_limb["grip_candidate_climbable"] = true
	reach_previous_limb["grip_candidate_distance"] = 0.95
	reach_previous_limb["end_effector"] = {"grip_acquisition_radius": 0.24, "grip_detection_radius": 1.10}
	reach_previous_limbs[0] = reach_previous_limb
	reach_previous["limbs"] = reach_previous_limbs
	var reach_current = reach_previous.duplicate(true)
	var reach_current_limbs: Array = (reach_current["limbs"] as Array).duplicate(true)
	var reach_current_limb: Dictionary = (reach_current_limbs[0] as Dictionary).duplicate(true)
	reach_current_limb["grip_candidate_distance"] = 0.35
	reach_current_limbs[0] = reach_current_limb
	reach_current["limbs"] = reach_current_limbs
	var reach_result = deck.step_reward(
		reach_previous, reach_current, 0.05, deck.create_worker_state()
	)
	var retreat_result = deck.step_reward(
		reach_current, reach_previous, 0.05, deck.create_worker_state()
	)
	_expect(
		float((reach_result.get("components", {}) as Dictionary).get("climb_reach", 0.0)) > 0.0
		and float((retreat_result.get("components", {}) as Dictionary).get("climb_reach", 0.0)) < 0.0,
		"climbing shaping exposes a signed approach gradient to visible climbable surfaces and cannot be farmed by approach-retreat cycles"
	)

	var attached_climb = elevated_climb.duplicate(true)
	var attached_limbs: Array = (attached_climb["limbs"] as Array).duplicate(true)
	var attached_limb: Dictionary = (attached_limbs[0] as Dictionary).duplicate(true)
	attached_limb["grip_candidate_climbable"] = false
	attached_limb["grip_attached_climbable"] = true
	attached_limb["grip_attached_target_id"] = 4242
	attached_limbs[0] = attached_limb
	attached_climb["limbs"] = attached_limbs
	var climb_state = deck.create_worker_state()
	var first_latch = deck.step_reward(attached_climb, attached_climb, 0.05, climb_state)
	var held_latch = deck.step_reward(attached_climb, attached_climb, 0.05, climb_state)
	_expect(
		float((first_latch.get("components", {}) as Dictionary).get("climb_grip", 0.0)) > 0.0
		and is_zero_approx(
			float((held_latch.get("components", {}) as Dictionary).get("climb_grip", 0.0))
		),
		"the first real climbable latch gets a one-time discovery bonus while simply hanging there pays nothing"
	)

	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	var objective_body = MLBodyPresetLibrary.four_limb_walker_definition()
	var objective_with_metadata = coordinator._objective(
		{
			"body_definition": objective_body,
			"current_target_metadata": {"subject_position_world": Vector3(1.0, 2.0, 3.0)},
		},
		Vector3(1.0, 2.0, 3.0),
		Vector3.ZERO,
		1.0
	)
	var preserved_subject: Vector3 = objective_with_metadata.get(
		"target_subject_position_world",
		Vector3.ZERO
	)
	var policy_target: Vector3 = objective_with_metadata.get("target_position_world", Vector3.ZERO)
	_expect(
		preserved_subject.is_equal_approx(Vector3(1.0, 2.0, 3.0))
		and is_equal_approx(policy_target.y, 2.0 + objective_body.preferred_core_height()),
		"the limb coordinator treats the path marker as a support surface and derives the policy core goal from authored standing height"
	)
	coordinator.shutdown()


func _test_climbing_cardset_and_evaluator_surfaces_are_grippable() -> void:
	var evaluation_plan: Dictionary = RLDeterministicEvaluationSuite.default_plan("four_limb")
	_expect(
		(evaluation_plan.get("scenario_ids", []) as Array).has("climb_platform"),
		"the default four-limb evaluator retains climbing skill instead of selecting walking-only checkpoints"
	)
	var library = TrainingRewardCardsetLibrary.new()
	var climbing: Dictionary = library.cardset(
		TrainingRewardCardsetLibrary.BODY_TYPE_FOUR_LIMB,
		"builtin:limb_climbing"
	)
	var cards: Dictionary = climbing.get("cards", {})
	var reach_card: Dictionary = cards.get("climb_reach", {})
	var climb_card: Dictionary = cards.get("climb_grip", {})
	var ascent_card: Dictionary = cards.get("climb_ascent", {})
	var obstacle_card: Dictionary = cards.get("obstacle_avoidance", {})
	_expect(
		bool(reach_card.get("enabled", false))
		and float(reach_card.get("intensity", 0.0)) > 1.0
		and bool(climb_card.get("enabled", false))
		and float(climb_card.get("intensity", 0.0)) > 1.0
		and bool(ascent_card.get("enabled", false))
		and float(ascent_card.get("intensity", 0.0)) > 1.0
		and not bool(obstacle_card.get("enabled", true)),
		"the dedicated climbing preset shapes reach, latch, and ascent without simultaneously teaching the worker to avoid the wall"
	)

	var evaluator = FourLimbCandidateEvaluationJob.new()
	test_root.add_child(evaluator)
	evaluator.body_definition = MLBodyPresetLibrary.four_limb_walker_definition()
	evaluator.world_offset = Vector3.ZERO
	evaluator.local_spawn_position = Vector3(0.0, 1.2, 0.0)
	_expect(
		evaluator._build_case_environment("ground_target", 7123)
		and is_equal_approx(
			evaluator.target_position_world.y,
			evaluator.body_definition.preferred_core_height()
		),
		"existing ground evaluation goals use the authored standing core height once target success becomes full 3D"
	)
	evaluator._clear_case_environment()
	_expect(
		evaluator._build_case_environment("climb_platform", 7124)
		and evaluator.has_target_subject_position
		and is_equal_approx(evaluator.target_subject_position_world.y, 2.0)
		and is_equal_approx(
			evaluator.target_position_world.y,
			2.0 + evaluator.body_definition.preferred_core_height()
		)
		and not evaluator.scenario_walls.is_empty(),
		"deterministic Best-model evaluation now includes a real elevated platform objective that requires retaining climbing skill"
	)
	evaluator._clear_case_environment()
	evaluator._add_box_wall(Vector3.ZERO, Vector3.ONE, 0.0)
	var wall: Node3D = evaluator.scenario_walls[0] if not evaluator.scenario_walls.is_empty() else null
	var surface_tags = (
		wall.get_meta("grip_surface_tags", PackedStringArray())
		if wall != null
		else PackedStringArray()
	)
	_expect(
		wall != null
		and bool(wall.get_meta("training_wall", false))
		and surface_tags is PackedStringArray
		and (surface_tags as PackedStringArray).has("climbable"),
		"hidden limb evaluation walls use the same climbable grip metadata as live training walls"
	)

	var evaluator_observation = _sample_observation()
	var evaluator_body: Dictionary = (evaluator_observation["body"] as Dictionary).duplicate(true)
	evaluator_body["position_world"] = Vector3(0.0, 1.5, 0.0)
	evaluator_observation["body"] = evaluator_body
	var evaluator_objective: Dictionary = (evaluator_observation["objective"] as Dictionary).duplicate(true)
	evaluator_objective["target_position_world"] = Vector3(0.0, 3.0, 0.0)
	evaluator_observation["objective"] = evaluator_objective
	_expect(
		is_equal_approx(evaluator._target_distance_from_observation(evaluator_observation), 1.5),
		"hidden limb evaluation uses the same full-3D target distance as live reward and success metrics"
	)

	var previous_commands = FourLimbMLAction.neutral_commands()
	var grip_only_commands = previous_commands.duplicate()
	grip_only_commands[FourLimbMLAction.grip_action_offset(0)] = 1.0
	var joint_commands = previous_commands.duplicate()
	joint_commands[FourLimbMLAction.action_offset(0, 0)] = 1.0
	_expect(
		is_zero_approx(
			FourLimbCandidateEvaluationJob._command_change_norm(
				previous_commands,
				grip_only_commands
			)
		)
		and FourLimbCandidateEvaluationJob._command_change_norm(
			previous_commands,
			joint_commands
		) > 0.0,
		"hidden evaluation does not punish direct grip toggles as joint-command spam"
	)
	evaluator.queue_free()


func _test_target_locomotion_outweighs_passive_posture() -> void:
	var deck = FourLimbRewardDeck.new()
	var still_observation = _sample_observation()
	var still_body: Dictionary = (still_observation["body"] as Dictionary).duplicate(true)
	still_body["ground_clearance"] = float(still_body.get("preferred_ground_clearance", 1.5))
	still_body["ground_clearance_error"] = 0.0
	still_observation["body"] = still_body
	var still_result = deck.step_reward(
		still_observation,
		still_observation,
		0.05,
		deck.create_worker_state(),
		{"action_change_norm": 0.0}
	)
	_expect(
		float(still_result.get("total", 0.0)) <= 0.0,
		"standing upright far from the target is not a profitable local optimum"
	)
	var moving_observation = still_observation.duplicate(true)
	var moving_body: Dictionary = (moving_observation["body"] as Dictionary).duplicate(true)
	moving_body["position_world"] = Vector3(0.0, 1.5, -0.10)
	moving_body["transform_world"] = Transform3D(
		Basis.IDENTITY,
		moving_body["position_world"]
	)
	moving_observation["body"] = moving_body
	var moving_result = deck.step_reward(
		still_observation,
		moving_observation,
		0.05,
		deck.create_worker_state(),
		{"action_change_norm": 0.0}
	)
	_expect(
		float(moving_result.get("total", 0.0))
		> absf(float(still_result.get("total", 0.0))) * 10.0,
		"actual horizontal progress dominates passive posture rewards"
	)
	var skating_observation: Dictionary = moving_observation.duplicate(true)
	var skating_limbs: Array = (skating_observation["limbs"] as Array).duplicate(true)
	for limb_value: Variant in skating_limbs:
		var skating_limb: Dictionary = limb_value
		skating_limb["foot_slip_speed"] = 1.0
	skating_observation["limbs"] = skating_limbs
	var skating_result: Dictionary = deck.step_reward(
		still_observation,
		skating_observation,
		0.05,
		deck.create_worker_state(),
		{"action_change_norm": 0.0}
	)
	_expect(
		float(skating_result.get("total", 0.0))
		< float(moving_result.get("total", 0.0)) * 0.75,
		"visible planted-foot skating loses a material share of locomotion reward"
	)
	var zero_commands = FourLimbMLAction.neutral_commands()
	var full_commands = PackedFloat64Array()
	full_commands.resize(FourLimbMLAction.ACTION_COUNT)
	full_commands.fill(1.0)
	var joint_only_commands = FourLimbMLAction.neutral_commands()
	var grip_only_commands = FourLimbMLAction.neutral_commands()
	for limb_index in range(FourLimbMLAction.LIMB_COUNT):
		for joint_axis in range(FourLimbMLAction.JOINT_AXES_PER_LIMB):
			joint_only_commands[FourLimbMLAction.action_offset(limb_index, joint_axis)] = 1.0
		grip_only_commands[FourLimbMLAction.grip_action_offset(limb_index)] = 1.0
	var coordinator = FourLimbTrainingCoordinator.new(test_root)
	_expect(
		is_equal_approx(coordinator._command_change_norm(zero_commands, full_commands), 1.0),
		"joint smoothness uses actuator-count-independent RMS instead of a sqrt(12) penalty"
	)
	_expect(
		is_equal_approx(coordinator._command_change_norm(zero_commands, joint_only_commands), 1.0),
		"joint smoothness measures all twelve real joint target channels"
	)
	_expect(
		is_zero_approx(coordinator._command_change_norm(zero_commands, grip_only_commands)),
		"grip activation no longer dilutes the Joint command spam reward"
	)
	coordinator.shutdown()


func _test_target_objective_is_explicit() -> void:
	var observation = _sample_observation()
	var features = FourLimbMLFeatureEncoder.encode(observation)
	_expect(features.size() == FourLimbMLFeatureEncoder.FEATURE_COUNT, "the target observation keeps the versioned tensor size")
	_expect(
		is_equal_approx(features[0], 0.0)
		and is_equal_approx(features[1], 0.0)
		and is_equal_approx(features[2], -5.0 / 25.0)
		and is_equal_approx(features[6], 5.0 / 25.0)
		and is_equal_approx(features[7], 5.0 / 25.0),
		"the limb model receives target displacement, height, horizontal distance, and full 3D distance"
	)
	_expect(
		is_equal_approx(features[11], 1.25 / 10.0)
		and is_equal_approx(features[12], 0.0),
		"the target radius and full-3D inside-radius state remain explicit"
	)
	var vertically_wrong = observation.duplicate(true)
	var vertically_wrong_objective: Dictionary = (vertically_wrong["objective"] as Dictionary).duplicate(true)
	vertically_wrong_objective["target_position_world"] = Vector3(0.0, 40.0, -0.5)
	vertically_wrong["objective"] = vertically_wrong_objective
	var vertically_wrong_features = FourLimbMLFeatureEncoder.encode(vertically_wrong)
	_expect(
		is_equal_approx(vertically_wrong_features[12], 0.0),
		"being horizontally underneath an elevated target no longer produces a false inside-target cue"
	)
	var inside = observation.duplicate(true)
	var inside_objective: Dictionary = (inside["objective"] as Dictionary).duplicate(true)
	inside_objective["target_position_world"] = Vector3(0.0, 1.5, -0.5)
	inside["objective"] = inside_objective
	var inside_features = FourLimbMLFeatureEncoder.encode(inside)
	_expect(
		is_equal_approx(inside_features[12], 1.0),
		"the inside-target cue agrees with the same full-3D radius used by reward and success"
	)


func _test_stable_body_height_reward() -> void:
	var deck = FourLimbRewardDeck.new()
	var stable_previous = _sample_observation()
	var stable_current = stable_previous.duplicate(true)
	var preferred_clearance = 1.51
	for observation_variant: Variant in [stable_previous, stable_current]:
		var observation_value = observation_variant as Dictionary
		var body: Dictionary = (observation_value["body"] as Dictionary).duplicate(true)
		body["ground_clearance"] = preferred_clearance
		body["preferred_ground_clearance"] = preferred_clearance
		body["ground_clearance_error"] = 0.0
		body["linear_velocity_world"] = Vector3(1.5, 0.0, 0.0)
		observation_value["body"] = body
	var stable_result = deck.step_reward(
		stable_previous,
		stable_current,
		0.05,
		deck.create_worker_state()
	)
	var stable_height = float((stable_result.get("components", {}) as Dictionary).get("height_stability", 0.0))
	_expect(stable_height > 0.0, "smooth horizontal motion at the authored body height earns height-stability reward")

	var bouncing = stable_current.duplicate(true)
	var bouncing_body: Dictionary = (bouncing["body"] as Dictionary).duplicate(true)
	bouncing_body["ground_clearance"] = 0.55
	bouncing_body["ground_clearance_error"] = 0.55 - preferred_clearance
	bouncing_body["linear_velocity_world"] = Vector3(1.5, -3.0, 0.0)
	bouncing["body"] = bouncing_body
	var bouncing_result = deck.step_reward(
		stable_previous,
		bouncing,
		0.05,
		deck.create_worker_state()
	)
	var bouncing_height = float((bouncing_result.get("components", {}) as Dictionary).get("height_stability", 0.0))
	_expect(
		bouncing_height < stable_height and bouncing_height < 0.0,
		"dropping and bouncing away from the authored level loses height-stability reward"
	)


func _test_target_height_is_visible_without_changing_horizontal_radius() -> void:
	var low_target = _sample_observation()
	var high_target = low_target.duplicate(true)
	var high_objective: Dictionary = (high_target["objective"] as Dictionary).duplicate(true)
	high_objective["target_position_world"] = Vector3(0.0, 80.0, -5.0)
	high_objective["target_velocity_world"] = Vector3(0.0, 25.0, 0.0)
	high_target["objective"] = high_objective
	var low_features = FourLimbMLFeatureEncoder.encode(low_target)
	var high_features = FourLimbMLFeatureEncoder.encode(high_target)
	_expect(
		not is_equal_approx(low_features[1], high_features[1])
		and not is_equal_approx(low_features[4], high_features[4])
		and not is_equal_approx(low_features[7], high_features[7])
		and not is_equal_approx(low_features[9], high_features[9]),
		"target height, 3D direction/distance, and vertical target-relative speed remain visible"
	)
	_expect(
		is_equal_approx(low_features[6], high_features[6])
		and is_equal_approx(low_features[11], high_features[11])
		and is_equal_approx(low_features[12], high_features[12]),
		"changing only target height does not change horizontal distance or radius semantics"
	)


func _test_partial_progress_keeps_reward() -> void:
	var deck = FourLimbRewardDeck.new()
	var state = deck.create_worker_state()
	var previous = _sample_observation()
	var current = previous.duplicate(true)
	var previous_body: Dictionary = previous["body"]
	var current_body: Dictionary = (current["body"] as Dictionary).duplicate(true)
	current_body["position_world"] = Vector3(0.0, 1.5, -1.0)
	current_body["transform_world"] = Transform3D(Basis.IDENTITY, current_body["position_world"])
	current["body"] = current_body
	var result = deck.step_reward(previous, current, 0.05, state)
	_expect(float(result.get("total", 0.0)) > 0.0, "useful movement toward the target keeps positive training value even before arrival")
	var terminal = deck.terminal_reward(state, "", true)
	_expect(float(terminal.get("total", 0.0)) > 0.0, "surviving the full round ends with a small positive bonus")


func _test_physical_body_uses_simulated_core() -> void:
	var floor = StaticBody3D.new()
	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20.0, 0.5, 20.0)
	floor_shape.shape = box
	floor.add_child(floor_shape)
	floor.collision_layer = 1
	floor.collision_mask = 4
	floor.position.y = -0.25
	test_root.add_child(floor)
	var body = FourLimbPhysicalBody3D.new()
	body.definition = MLBodyPresetLibrary.four_limb_walker_definition()
	# Display labels are intentionally duplicated here. Runtime identity must use stable slot
	# indices so future editor labels can never merge physical limb chains.
	for limb: FourLimbSlotDefinition in body.definition.limbs:
		limb.slot_name = "Limb"
	body.position = Vector3(
		0.0,
		body.definition.minimum_spawn_height(0.03),
		0.0
	)
	_expect(
		absf(body.position.y - 1.747) < 0.005,
		"the generic rig includes the separated physical sole when spawning with floor clearance"
	)
	test_root.add_child(body)
	await physics_frame
	await physics_frame
	_expect(body.physical_rig != null, "the gameplay body builds its reusable physical rig")
	_expect(
		body.physical_rig.core_bone is LimbSegment3D
		and body.physical_rig.core_bone is RigidBody3D,
		"the chassis is an ordinary simulated rigid part rather than a hidden movement body"
	)
	_expect(
		body.physical_rig.limbs_controller is LimbsController3D,
		"the limb worker owns one generic limbs controller analogous to the drone controller"
	)
	_expect(
		body.physical_rig.limbs_controller.action_mapping_valid
		and body.physical_rig.limbs_controller.action_count == FourLimbMLAction.ACTION_COUNT
		and LimbsController3D.has_complete_action_mapping_for_limbs(
			body.physical_rig.generic_limbs,
			FourLimbMLAction.ACTION_COUNT
		),
		"all sixteen policy outputs map to twelve direct joint axes plus four independent grips with no holes"
	)
	_expect(body.physical_rig.limb_records.size() == 4, "the first body creates four independent physical limb slots")
	_expect(body.physical_rig.installed_limb_chain_count() == 4, "the body contains exactly four complete generic limb chains")
	_expect(body.physical_rig.physical_limb_segment_count() == 8, "four two-segment legs create exactly eight rigid limb parts")
	_expect(body.physical_rig.has_exact_four_limb_topology(), "duplicate display names cannot create extra or shared limb chains")
	_expect(body.physical_rig.has_valid_physical_bindings(false), "the core, generic limbs, and constraints are fully connected")
	_expect(body.physical_rig.has_safe_joint_constraints(), "all joint translations are locked and anatomical rotations are bounded")
	_expect(body.physical_rig.has_passive_rest_elasticity(), "every free joint axis has permanent passive elasticity")
	_expect(
		body.physical_rig.limbs_controller.publish_source_records_each_step,
		"the legacy four-limb rig keeps per-frame joint diagnostics for its reward and observation code"
	)
	var legacy_contact_reporting_preserved: bool = true
	for chain: GenericLimb3D in body.physical_rig.generic_limbs:
		for segment: LimbSegment3D in chain.segments:
			legacy_contact_reporting_preserved = (
				legacy_contact_reporting_preserved
				and not segment.can_sleep
				and segment.contact_monitor
				and segment.max_contacts_reported == GenericLimb3D.MAX_CONTACTS_REPORTED
			)
	_expect(
		legacy_contact_reporting_preserved,
		"the legacy four-limb rig keeps contact reporting and always-awake limbs required by its support rewards"
	)
	var aligned_hip_frames = 0
	var correctly_mapped_hip_axes = 0
	var high_priority_joint_count = 0
	var rough_lower_foot_count = 0
	var rough_upper_leg_count = 0
	var physical_sole_count = 0
	var hidden_terminal_cap_count = 0
	var upper_ccd_count = 0
	var lower_ccd_count = 0
	for record_value: Variant in body.physical_rig.limb_records:
		var record: Dictionary = record_value
		var chain = record.get("chain") as GenericLimb3D
		var hip_record: Dictionary = record.get("hip_joint", {})
		if not is_instance_valid(chain) or hip_record.is_empty():
			continue
		var hip_definition = hip_record.get("definition") as LimbJointDefinition
		var slot_index = int(record.get("slot_index", -1))
		if (
			hip_definition != null
			and slot_index >= 0
			and slot_index < body.definition.limbs.size()
			and not chain.definition.segments.is_empty()
		):
			var upper_definition = chain.definition.segments[0]
			var expected_basis = FourLimbPhysicalRig3D.hip_joint_basis_for_slot(
				body.definition.limbs[slot_index],
				upper_definition.rest_direction_local
			)
			if (
				absf(hip_definition.joint_basis_local.x.normalized().dot(Vector3.UP)) > 0.999
				and absf(hip_definition.joint_basis_local.z.normalized().dot(expected_basis.z)) > 0.999
			):
				aligned_hip_frames += 1
			var action_offset = slot_index * FourLimbMLAction.AXES_PER_LIMB
			if hip_definition.action_indices == Vector3i(action_offset + 1, -1, action_offset):
				correctly_mapped_hip_axes += 1
		if (
			is_instance_valid(chain.end_effector)
			and not chain.end_effector.disabled
			and chain.end_effector.definition != null
			and chain.end_effector.definition.geometry_type == LimbEndEffectorDefinition.GeometryType.BOX
		):
			physical_sole_count += 1
			if chain.segments.size() >= 2:
				var terminal_cap: MeshInstance3D = chain.segments[-1].get_node_or_null("JointCap") as MeshInstance3D
				if terminal_cap != null and not terminal_cap.visible:
					hidden_terminal_cap_count += 1
		if chain.segments.size() >= 2:
			var upper_surface: PhysicsMaterial = chain.segments[0].physics_material_override
			var lower_surface: PhysicsMaterial = chain.segments[1].physics_material_override
			if upper_surface != null and upper_surface.rough:
				rough_upper_leg_count += 1
			if lower_surface != null and lower_surface.rough:
				rough_lower_foot_count += 1
			if chain.segments[0].continuous_cd:
				upper_ccd_count += 1
			if chain.segments[1].continuous_cd:
				lower_ccd_count += 1
		for joint: Generic6DOFJoint3D in chain.joints:
			if joint.solver_priority == 1:
				high_priority_joint_count += 1
	_expect(
		physical_sole_count == FourLimbBodyDefinition.LIMB_SLOT_COUNT
		and rough_lower_foot_count == FourLimbBodyDefinition.LIMB_SLOT_COUNT
		and rough_upper_leg_count == 0,
		"all four stock distal segments carry a physical rough sole while upper legs stay ordinary"
	)
	_expect(
		hidden_terminal_cap_count == FourLimbBodyDefinition.LIMB_SLOT_COUNT,
		"a physical sole replaces the protruding decorative distal joint cap instead of visually intersecting it"
	)
	_expect(
		upper_ccd_count == 0
		and lower_ccd_count == FourLimbBodyDefinition.LIMB_SLOT_COUNT
		and body.physical_rig.core_bone.continuous_cd,
		"CCD is reserved for the core and distal contact links instead of all nine articulated bodies"
	)
	_expect(
		aligned_hip_frames == FourLimbBodyDefinition.LIMB_SLOT_COUNT,
		"every hip has body-up horizontal sweep plus radial load-bearing elevation"
	)
	_expect(
		correctly_mapped_hip_axes == FourLimbBodyDefinition.LIMB_SLOT_COUNT,
		"each limb maps output 0 to elevation and output 1 to physical horizontal sweep"
	)
	_expect(
		high_priority_joint_count == 8,
		"all load-bearing articulated constraints use Godot's highest normal solver priority"
	)
	var unique_binding_names: Dictionary[StringName, bool] = {}
	unique_binding_names[body.physical_rig.core_bone.binding_name] = true
	for chain: GenericLimb3D in body.physical_rig.generic_limbs:
		for segment: LimbSegment3D in chain.segments:
			unique_binding_names[segment.binding_name] = true
	_expect(
		unique_binding_names.size() == 9,
		"the core plus eight limb parts always use unique stable binding names"
	)
	var visible_socket_count = 0
	var visible_distal_cap_count = 0
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		if body.physical_rig.core_bone.get_node_or_null("LimbMount%02d" % limb_index) != null:
			visible_socket_count += 1
		var record: Dictionary = body.physical_rig.limb_records[limb_index]
		var upper = record.get("upper") as LimbSegment3D
		if is_instance_valid(upper):
			var cap = upper.get_node_or_null("JointCap") as MeshInstance3D
			var upper_definition = (record.get("chain") as GenericLimb3D).definition.segments[0]
			if (
				is_instance_valid(cap)
				and cap.position.is_equal_approx(Vector3.UP * upper_definition.length * 0.5)
			):
				visible_distal_cap_count += 1
	_expect(visible_socket_count == 4, "the chassis shows exactly four authored limb sockets")
	_expect(visible_distal_cap_count == 4, "each upper part marks its real distal knee connection")
	_expect(body.physical_rig.rest_bindings_finalized, "generic rigid constraints are complete before simulation starts")
	_expect(
		body.physical_rig.maximum_limb_mount_error() < 0.08,
		"every generic hip starts at its own authored body-edge mount"
	)
	_expect(
		body.physical_rig.minimum_limb_mount_separation() > 0.35,
		"the four physical limb origins are visibly separated"
	)
	_expect(body.submit_raw_commands(FourLimbMLAction.neutral_commands()), "the generic body preserves the same raw twelve-axis action contract")
	for _frame in range(240):
		await physics_frame
	_expect(body.has_finite_physics_state(), "the neutral generic rig remains finite while settling on the floor")
	var standing_state = body.physical_rig.body_snapshot()
	var preferred_clearance = float(standing_state.get("preferred_ground_clearance", 0.0))
	_expect(
		float(standing_state.get("ground_clearance", 0.0)) >= preferred_clearance * 0.75,
		"an unpiloted neutral body retains at least three quarters of its authored standing height"
	)
	_expect(
		float(standing_state.get("uprightness", -1.0)) >= 0.85
		and not bool(standing_state.get("core_contact", true)),
		"default passive and neutral impedance keeps the chassis upright and off the floor"
	)
	var minimum_outward_ratio = INF
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var limb_definition = body.definition.limbs[limb_index]
		var limb_state = body.physical_rig.limb_snapshot(limb_index)
		var rest_horizontal = limb_definition.rest_foot_offset - limb_definition.hip_offset
		rest_horizontal.y = 0.0
		var current_horizontal: Vector3 = (
			limb_state.get("foot_position_local", Vector3.ZERO) - limb_definition.hip_offset
		)
		current_horizontal.y = 0.0
		var ratio = (
			current_horizontal.dot(rest_horizontal.normalized()) / rest_horizontal.length()
			if rest_horizontal.length_squared() > 0.000001
			else 1.0
		)
		minimum_outward_ratio = minf(minimum_outward_ratio, ratio)
	_expect(
		minimum_outward_ratio >= 0.65,
		"neutral feet keep a broad spider stance instead of folding beneath the chassis"
	)
	var contact_snapshot = body.physical_rig.world_contact_snapshot()
	var support_counts: PackedInt32Array = contact_snapshot.get(
		"limb_distal_support_contact_counts",
		PackedInt32Array()
	)
	var support_speeds: PackedFloat64Array = contact_snapshot.get(
		"limb_maximum_support_relative_speeds",
		PackedFloat64Array()
	)
	var support_normals: PackedVector3Array = contact_snapshot.get(
		"limb_support_normals_world",
		PackedVector3Array()
	)
	_expect(
		support_counts.size() == FourLimbBodyDefinition.LIMB_SLOT_COUNT
		and support_speeds.size() == FourLimbBodyDefinition.LIMB_SLOT_COUNT
		and support_normals.size() == FourLimbBodyDefinition.LIMB_SLOT_COUNT,
		"the contact feed reserves authoritative distal-foot contact, normal and slip slots per limb"
	)
	var supporting_feet = 0
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var support_count = support_counts[limb_index] if limb_index < support_counts.size() else 0
		if support_count > 0:
			supporting_feet += 1
		var contact_limb_state = body.physical_rig.limb_snapshot(limb_index, contact_snapshot)
		_expect(
			bool(contact_limb_state.get("foot_contact", false)) == (support_count > 0),
			"limb %d reports the distal rigid-part contact state actually seen by Jolt" % limb_index
		)
		if support_count > 0:
			_expect(
				is_zero_approx(float(contact_limb_state.get("foot_clearance", INF))),
				"limb %d reports zero clearance while its distal segment has support" % limb_index
			)
		if support_count > 0 and limb_index < support_normals.size():
			var support_normal = support_normals[limb_index]
			_expect(
				support_normal.is_finite()
				and support_normal.normalized().dot(Vector3.UP)
				>= FourLimbPhysicalRig3D.MINIMUM_SUPPORT_NORMAL_UP_DOT,
				"limb %d counts only upward-facing contacts as body support" % limb_index
			)
	_expect(
		supporting_feet >= 2,
		"a standing body exposes multiple physically meaningful support contacts to the model"
	)
	var live_observation = body.get_ml_snapshot(
		{
			"target_position_world": Vector3(0.0, body.global_position.y, -4.0),
			"target_velocity_world": Vector3.ZERO,
			"target_radius": 1.0,
		},
		contact_snapshot
	)
	_expect(
		FourLimbMLObservation.is_valid(live_observation),
		"the assembled standing body produces a complete finite model observation"
	)
	_expect(
		FourLimbMLFeatureEncoder.is_normalized(
			FourLimbMLFeatureEncoder.encode(live_observation)
		),
		"the assembled body's complete proprioception reaches the policy as finite normalized input"
	)
	var diagnostic_commands = FourLimbMLAction.neutral_commands()
	diagnostic_commands[FourLimbMLAction.action_offset(0, 0)] = 0.55
	diagnostic_commands[FourLimbMLAction.action_offset(2, 0)] = -0.55
	diagnostic_commands[FourLimbMLAction.action_offset(1, 2)] = 0.45
	diagnostic_commands[FourLimbMLAction.action_offset(3, 2)] = -0.45
	_expect(body.submit_raw_commands(diagnostic_commands), "asymmetric raw joint targets reach the generic controller")
	var maximum_torque_sum = 0.0
	for _frame in range(8):
		await physics_frame
		var frame_torque_sum = 0.0
		for torque_value in body.physical_rig.applied_torque_values:
			frame_torque_sum += absf(torque_value)
		maximum_torque_sum = maxf(maximum_torque_sum, frame_torque_sum)
	_expect(maximum_torque_sum > 0.01, "the limb controller produces real equal-and-opposite physical torques")
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var snapshot = body.physical_rig.limb_snapshot(limb_index)
		var angle = (snapshot.get("joint_angles", Vector3.ZERO) as Vector3).z
		var limb_definition = body.definition.limbs[limb_index]
		_expect(
			angle >= deg_to_rad(limb_definition.knee_limit_lower_degrees) - deg_to_rad(3.0)
			and angle <= deg_to_rad(limb_definition.knee_limit_upper_degrees) + deg_to_rad(3.0),
			"a commanded knee remains inside its anatomical Generic6DOF range"
		)
		var record: Dictionary = body.physical_rig.limb_records[limb_index]
		var hip_error: Vector3 = (record.get("hip_joint", {}) as Dictionary).get(
			"target_error_angles",
			Vector3.ZERO
		)
		var knee_error: Vector3 = (record.get("knee_joint", {}) as Dictionary).get(
			"target_error_angles",
			Vector3.ZERO
		)
		var observed_error: Vector3 = snapshot.get("joint_target_errors", Vector3.ZERO)
		var observed_angles: Vector3 = snapshot.get("joint_angles", Vector3.ZERO)
		var observed_targets: Vector3 = snapshot.get("joint_target_angles", Vector3.ZERO)
		var expected_coordinate_error = Vector3(
			wrapf(observed_targets.x - observed_angles.x, -PI, PI),
			wrapf(observed_targets.y - observed_angles.y, -PI, PI),
			wrapf(observed_targets.z - observed_angles.z, -PI, PI)
		)
		_expect(
			observed_error.is_equal_approx(expected_coordinate_error),
			"limb %d exposes profile-v8 elevation, horizontal-sweep, and knee coordinate error" % limb_index
		)
		var controller_error: Vector3 = snapshot.get("controller_target_errors", Vector3.ZERO)
		_expect(
			controller_error.is_equal_approx(Vector3(hip_error.z, hip_error.x, knee_error.z)),
			"limb %d exposes the exact quaternion-controller error as non-schema diagnostics" % limb_index
		)
	body.submit_raw_commands(FourLimbMLAction.neutral_commands())
	var attachment = TestAttachment.new()
	_expect(body.install_attachment(0, attachment), "a future attachment can be mounted on the gameplay body")
	_expect(
		is_equal_approx(body.physical_rig.core_bone.mass, body.definition.core_mass + 1.5),
		"mounted equipment contributes its declared mass to the simulated core"
	)
	var attachment_snapshot = body.get_ml_snapshot({
		"target_position_world": Vector3.ZERO,
		"target_velocity_world": Vector3.ZERO,
		"target_radius": 1.0,
	})
	var attachment_features: PackedFloat64Array = attachment_snapshot.get(
		"attachment_features",
		PackedFloat64Array()
	)
	_expect(
		attachment_features.size() == 68 and is_equal_approx(attachment_features[2], 1.5 / 50.0),
		"mounted equipment mass and state are present in the complete body observation"
	)
	_expect(body.install_attachment(2, attachment), "mounted equipment can move to another core slot")
	_expect(
		body.physical_rig.attachment_feed.provider_for_slot(0) == null
		and body.physical_rig.attachment_feed.provider_for_slot(2) == attachment,
		"moving mounted equipment clears the old physical and model-feed slot"
	)
	_expect(
		attachment.mounted_body == body and attachment.mounted_slot_index == 2,
		"a future attachment is told which body and slot currently own it"
	)
	_expect(
		is_equal_approx(body.physical_rig.core_bone.mass, body.definition.core_mass + 1.5),
		"moving mounted equipment does not double its physical mass"
	)
	body.configure(MLBodyPartContract.deep_duplicate_resource(body.definition) as FourLimbBodyDefinition)
	await physics_frame
	_expect(
		body.physical_rig.attachment_feed.provider_for_slot(2) == attachment,
		"mounted attachment feeds survive a body rebuild in their current slot"
	)
	body.queue_free()
	floor.queue_free()


func _pickup_observation(item_id: int, item_height: float, attached: bool) -> Dictionary:
	var observation: Dictionary = _sample_observation()
	var objective: Dictionary = (observation.get("objective", {}) as Dictionary).duplicate(true)
	objective["pickup_item_present"] = true
	objective["pickup_item_held"] = attached
	objective["pickup_item_position_world"] = Vector3(0.0, item_height, -1.0)
	objective["pickup_item_velocity_world"] = Vector3.ZERO
	objective["pickup_item_mass"] = 2.0
	objective["pickup_item_reward_value"] = 1.0
	objective["pickup_item_id"] = item_id
	observation["objective"] = objective
	if attached:
		var limbs: Array = observation.get("limbs", [])
		var first_limb: Dictionary = (limbs[0] as Dictionary).duplicate(true)
		first_limb["grip_attached"] = true
		first_limb["grip_attached_dynamic"] = true
		first_limb["grip_attached_target_id"] = item_id
		first_limb["grip_attached_target_mass"] = 2.0
		first_limb["grip_attached_surface_tags"] = PackedStringArray(["carryable"])
		limbs[0] = first_limb
		observation["limbs"] = limbs
	return observation


func _delivery_observation(item_id: int, distance_m: float, inside: bool) -> Dictionary:
	var observation: Dictionary = _pickup_observation(item_id, 1.0, true)
	var objective: Dictionary = (observation.get("objective", {}) as Dictionary).duplicate(true)
	objective["delivery_task_phase"] = "delivery"
	objective["delivery_destination_present"] = true
	objective["delivery_destination_group_id"] = 7
	objective["delivery_destination_stable_id"] = "training_delivery:7:1"
	objective["delivery_destination_distance_m"] = distance_m
	objective["delivery_item_held"] = true
	objective["delivery_item_accepted"] = true
	objective["delivery_item_inside"] = inside
	objective["delivery_item_instance_id"] = item_id
	objective["delivery_item_reward_value"] = 2.0
	objective["delivery_approach_reward_scale"] = 1.0
	objective["delivery_completion_reward_scale"] = 1.0
	observation["objective"] = objective
	return observation


func _delivery_reward_context(item_id: int, distance_m: float, inside: bool) -> Dictionary:
	return {
		"delivery_destination_present": true,
		"delivery_destination_group_id": 7,
		"delivery_destination_stable_id": "training_delivery:7:1",
		"delivery_destination_distance_m": distance_m,
		"delivery_item_held": true,
		"delivery_item_accepted": true,
		"delivery_item_inside": inside,
		"delivery_item_instance_id": item_id,
		"delivery_item_reward_value": 2.0,
		"delivery_approach_reward_scale": 1.0,
		"delivery_completion_reward_scale": 1.0,
	}


func _sample_observation() -> Dictionary:
	var limbs: Array[Dictionary] = []
	for index in range(4):
		limbs.append({
			"slot_index": index,
			"slot_name": ["Front Right", "Rear Right", "Rear Left", "Front Left"][index],
			"installed": true,
			"functional": true,
			"health_ratio": 1.0,
			"actuator_effectiveness": 1.0,
			"hip_offset_local": [
				Vector3(0.40, 0.0, -0.50),
				Vector3(0.40, 0.0, 0.50),
				Vector3(-0.40, 0.0, 0.50),
				Vector3(-0.40, 0.0, -0.50),
			][index],
			"upper_length": 1.05,
			"lower_length": 1.10,
			"joint_angles": Vector3.ZERO,
			"joint_limit_lower": Vector3(
				deg_to_rad(-68.0),
				deg_to_rad(-72.0),
				deg_to_rad(-8.0)
			),
			"joint_limit_upper": Vector3(
				deg_to_rad(68.0),
				deg_to_rad(72.0),
				deg_to_rad(72.0)
			),
			"joint_target_angles": Vector3.ZERO,
			"joint_target_errors": Vector3.ZERO,
			"joint_angular_velocities": Vector3.ZERO,
			"previous_commands": Vector3.ZERO,
			"commands": Vector3.ZERO,
			"applied_torque": Vector3.ZERO,
			"saturation": Vector3.ZERO,
			"foot_position_local": Vector3(0.0, -1.4, 0.0),
			"foot_velocity_local": Vector3.ZERO,
			"foot_up_local": Vector3.UP,
			"foot_contact": true,
			"ground_normal_local": Vector3.UP,
			"foot_clearance": 0.0,
			"foot_slip_speed": 0.0,
			"world_contact_count": 0,
			"wall_contact": false,
			"wall_contact_count": 0,
			"maximum_wall_contact_impulse": 0.0,
			"grip_present": true,
			"grip_command": 0.0,
			"grip_activation": 0.0,
			"grip_requires_rearm": false,
			"grip_candidate_present": false,
			"grip_candidate_distance": 0.0,
			"grip_target_present": false,
			"grip_target_offset_local": Vector3.ZERO,
			"grip_target_normal_local": Vector3.UP,
			"grip_target_distance": 0.0,
			"grip_candidate_dynamic": false,
			"grip_candidate_target_mass": 0.0,
			"grip_candidate_climbable": false,
			"grip_candidate_carryable": false,
			"grip_attached": false,
			"grip_attached_dynamic": false,
			"grip_attached_target_id": 0,
			"grip_attached_target_mass": 0.0,
			"grip_attached_climbable": false,
			"grip_attached_carryable": false,
			"grip_load_ratio": 0.0,
			"grip_pickup_sequence": 0,
			"end_effector": {
				"grip_acquisition_radius": 0.24,
				"grip_detection_radius": 1.10,
			},
		})
	var attachment_features = PackedFloat64Array()
	attachment_features.resize(FourLimbBodyDefinition.ATTACHMENT_SLOT_COUNT * FourLimbAttachmentFeed.FEATURES_PER_SLOT)
	attachment_features.fill(0.0)
	return {
		"schema_version": FourLimbMLObservation.SCHEMA_VERSION,
		"body_profile_id": FourLimbBodyDefinition.BODY_PROFILE_ID,
		"hardware_signature": MLBodyPresetLibrary.four_limb_walker_definition().hardware_signature(),
		"body": {
			"transform_world": Transform3D(Basis.IDENTITY, Vector3(0.0, 1.5, 0.0)),
			"position_world": Vector3(0.0, 1.5, 0.0),
			"basis_world": Basis.IDENTITY,
			"linear_velocity_world": Vector3.ZERO,
			"angular_velocity_world": Vector3.ZERO,
			"uprightness": 1.0,
			"ground_clearance": 1.25,
			"preferred_core_height": 1.65,
			"preferred_ground_clearance": 1.51,
			"ground_clearance_error": -0.26,
			"core_contact": false,
			"core_support_contact": false,
			"core_wall_contact": false,
			"world_contact_count": 4,
			"wall_contact_count": 0,
			"maximum_contact_impulse": 0.0,
			"ground_normal_world": Vector3.UP,
			"health_ratio": 1.0,
			"mass": 6.24,
		},
		"limbs": limbs,
		"attachments": [],
		"attachment_features": attachment_features,
		"objective": {
			"target_position_world": Vector3(0.0, 1.5, -5.0),
			"target_velocity_world": Vector3.ZERO,
			"target_radius": 1.25,
			"pickup_item_present": false,
			"pickup_item_held": false,
			"pickup_item_position_world": Vector3.ZERO,
			"pickup_item_velocity_world": Vector3.ZERO,
			"pickup_item_mass": 0.0,
			"pickup_item_reward_value": 0.0,
			"pickup_item_id": 0,
			"obstacle_probe": FourLimbTrainingObstacleSensor.clear_probe(),
			"turret_threat_probe": TrainingTurretThreatSensor.empty_probe(),
		},
		"previous_action_age": 0.05,
	}


func _with_foot_support(observation: Dictionary, supported: bool) -> Dictionary:
	var result = observation.duplicate(true)
	var limbs: Array = result.get("limbs", [])
	for limb_value: Variant in limbs:
		if limb_value is Dictionary:
			(limb_value as Dictionary)["foot_contact"] = supported
	result["limbs"] = limbs
	return result


func _arrays_close(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if not is_equal_approx(left[index], right[index]):
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: " + message)
		return
	failure_count += 1
	push_error("FAIL: " + message)
