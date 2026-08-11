extends SceneTree

const EXPECTED_WEIGHT_COUNT = 7

#######################################################
# Verifies the quad-only diagnostic policy used by the interactive ML training room.
#######################################################

class FailingVerificationDroneModelRegistry:
	extends DroneTrainingModelRegistry

	var fail_manifest_revision: int = 0
	var fail_next_resolve: bool = false

	func _write_json_file(path: String, value: Dictionary) -> bool:
		var written: bool = super._write_json_file(path, value)
		if (
			written
			and fail_manifest_revision > 0
			and path.get_file() == MANIFEST_FILE_NAME
			and SafeVariant.integral_int_or(value.get("checkpoint_revision", 0), 0)
			== fail_manifest_revision
		):
			fail_next_resolve = true
		return written

	func _resolve_version(record_or_id: Variant) -> Dictionary:
		if fail_next_resolve:
			fail_next_resolve = false
			return {}
		return super._resolve_version(record_or_id)


var failure_count = 0


func _init() -> void:
	var policy = DroneTrainingPolicy.new()
	_expect(policy.weights.size() == EXPECTED_WEIGHT_COUNT, "baseline exposes every tuning weight")
	var observation = _observation_with_propeller_count(4)
	var action = policy.predict_action(observation)
	var commands: Array = action.get("propeller_commands", [])
	_expect(commands.size() == 4, "quad observation produces four actuator commands")
	for index in range(commands.size()):
		var command: Dictionary = commands[index]
		_expect(int(command.get("slot_index", -1)) == index, "stable slot identity is retained")
		var value = float(command.get("command", -1.0))
		_expect(value >= 0.0 and value <= 1.0, "actuator command is normalized")
	_expect(
		policy.predict_action(_observation_with_propeller_count(6)).is_empty(),
		"non-quad topology fails closed"
	)
	_test_reward_components()
	_test_reward_card_configuration()
	_test_controlled_episode()
	_test_plot_aggregation()
	_test_plot_series_isolation()
	_test_sac_learning_error_plot_uses_twin_q_metrics()
	_test_plot_cutting()
	_test_immutable_model_versions()
	quit(0 if failure_count == 0 else 1)


func _test_reward_components() -> void:
	var poisoned_reward = DroneTrainingReward.new()
	poisoned_reward.configure_components({
		"approach": {"enabled": true, "intensity": NAN},
	})
	_expect(
		is_equal_approx(poisoned_reward.component_intensity("approach"), 1.0),
		"legacy reward-component dictionaries replace non-finite intensity with the canonical default"
	)
	poisoned_reward.reset(Vector3.ZERO, Vector3.ONE, NAN, NAN)
	var poisoned_step = poisoned_reward.step(
		Vector3.ZERO,
		Vector3.ONE,
		NAN,
		NAN
	)
	_expect(
		is_finite(float(poisoned_step.get("total_reward", 0.0)))
		and is_finite(float(poisoned_step.get("elapsed_seconds", 0.0))),
		"non-finite reward timing/radius inputs are contained before reward accumulation"
	)
	var reward = DroneTrainingReward.new()
	reward.configure_components({"survival": false, "ground_safety": false})
	reward.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	var toward = reward.step(
		Vector3(1.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		1.0,
		1.0
	)
	_expect(int(toward.get("reward_schema_version", 0)) == DroneTrainingReward.SCHEMA_VERSION,
		"reward records identify the corrected reward contract")
	_expect(is_equal_approx(float(toward["cosine_alignment"]), 1.0),
		"straight target-directed movement has full cosine alignment")
	_expect(is_equal_approx(float(toward["progress_reward"]), 0.1),
		"one metre of actual distance reduction receives normalized progress reward")
	_expect(is_equal_approx(float(toward["search_cost_reward"]), -0.01),
		"remaining outside the accepted radius carries a small time cost")
	_expect(is_equal_approx(float(toward["approach_reward"]), 0.09),
		"the visible approach component preserves most early progress while still discouraging idling")
	_expect(is_zero_approx(float(toward["radius_reward"])),
		"approach outside the radius does not receive hold reward")

	var away = reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		1.0
	)
	_expect(float(away["approach_reward"]) < 0.0,
		"movement away from the target receives a symmetric penalty")

	reward.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	var target_moved = reward.step(
		Vector3.ZERO,
		Vector3(9.0, 0.0, 0.0),
		1.0,
		1.0
	)
	_expect(is_zero_approx(float(target_moved["progress_reward"])),
		"target motion cannot award the stationary drone progress credit")
	_expect(float(target_moved["approach_reward"]) < 0.0,
		"a stationary drone outside the radius still pays the search-time cost")

	var orbit_reward = DroneTrainingReward.new()
	orbit_reward.configure_components({"survival": false, "ground_safety": false})
	orbit_reward.reset(Vector3(10.0, 0.0, 0.0), Vector3.ZERO, 1.0)
	for angle_degrees in [15.0, 30.0, 45.0, 60.0, 75.0, 90.0]:
		var angle = deg_to_rad(angle_degrees)
		orbit_reward.step(
			Vector3(cos(angle) * 10.0, 0.0, sin(angle) * 10.0),
			Vector3.ZERO,
			1.0,
			0.1
		)
	_expect(
		absf(float(orbit_reward.latest_result["cumulative_progress_reward"])) < 0.00001,
		"constant-radius circular motion cannot farm target-progress reward"
	)
	_expect(
		float(orbit_reward.latest_result["cumulative_approach_reward"]) < 0.0,
		"orbiting far from the target accumulates only the search-time cost"
	)

	reward.reset(Vector3(9.5, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), 1.0)
	var holding = reward.step(
		Vector3(9.6, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.5
	)
	_expect(is_zero_approx(float(holding["approach_reward"])),
		"movement within the accepted radius cannot farm approach reward")
	_expect(is_equal_approx(float(holding["radius_reward"]), 0.5),
		"radius reward is accumulated per second rather than per frame")
	_expect(is_equal_approx(float(holding["total_reward"]), 0.5),
		"total reward is the sum of its visible components")
	_expect(is_equal_approx(float(holding["mean_reward_per_second"]), 1.0),
		"mean reward makes differently aged trials comparable")

	var smooth_reward = DroneTrainingReward.new()
	smooth_reward.configure_components({"survival": false, "ground_safety": false})
	smooth_reward.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	smooth_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.05,
		[0.5, 0.5, 0.5, 0.5]
	)
	var abrupt = smooth_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.05,
		[1.0, 0.0, 1.0, 0.0]
	)
	_expect(float(abrupt["smoothness_reward"]) < 0.0,
		"abrupt motor changes receive a small smoothness penalty")
	var smoothness_20_hz = _smoothness_cost_for_rate(20)
	var smoothness_60_hz = _smoothness_cost_for_rate(60)
	_expect(
		absf(smoothness_20_hz - smoothness_60_hz) < 0.00001,
		"smoothness cost is normalized so 60 Hz exploration is not punished three times as strongly"
	)

	var already_negative = DroneTrainingReward.new()
	already_negative.configure_components({"survival": false, "ground_safety": false})
	already_negative.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	already_negative.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		1.0
	)
	_expect(
		is_zero_approx(already_negative.unreached_target_terminal_correction(-1.0)),
		"unreached trajectories are never flattened at episode end"
	)

	var obstacle_reward = DroneTrainingReward.new()
	obstacle_reward.configure_components({"survival": false, "ground_safety": false})
	obstacle_reward.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	var stationary_near_wall = obstacle_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.1,
		[],
		{
			"nearest_distance_m": 0.4,
			"maximum_distance_m": 4.0,
			"closing_speed_mps": 0.0,
		}
	)
	_expect(
		is_zero_approx(float(stationary_near_wall["obstacle_reward"])),
		"being near a wall without moving into it is not punished"
	)
	var approaching_wall = obstacle_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.1,
		[],
		{
			"nearest_distance_m": 0.4,
			"maximum_distance_m": 4.0,
			"closing_speed_mps": 2.0,
		}
	)
	_expect(
		float(approaching_wall["obstacle_reward"]) < 0.0,
		"moving into nearby geometry receives a bounded avoidance penalty"
	)
	var physical_contact = obstacle_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.1,
		[],
		{
			"nearest_distance_m": 0.0,
			"maximum_distance_m": 4.0,
			"closing_speed_mps": 0.0,
			"wall_contact": true,
		}
	)
	_expect(
		float(physical_contact["obstacle_reward"]) < 0.0,
		"a confirmed wall collision receives its contact penalty even after motion stops"
	)
	var continuing_contact = obstacle_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.1,
		[],
		{
			"nearest_distance_m": 0.0,
			"maximum_distance_m": 4.0,
			"closing_speed_mps": 0.0,
			"wall_contact": true,
		}
	)
	_expect(
		is_zero_approx(float(continuing_contact["obstacle_reward"])),
		"one physical collision does not apply the bounded contact penalty every frame"
	)
	obstacle_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.1,
		[],
		{
			"nearest_distance_m": 0.0,
			"maximum_distance_m": 4.0,
			"closing_speed_mps": 0.0,
			"wall_contact": false,
		}
	)
	var resumed_contact = obstacle_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.1,
		[],
		{
			"nearest_distance_m": 0.0,
			"maximum_distance_m": 4.0,
			"closing_speed_mps": 0.0,
			"wall_contact": true,
		}
	)
	_expect(
		is_zero_approx(float(resumed_contact["obstacle_reward"])),
		"a one-sample contact-monitor gap does not duplicate the contact penalty"
	)

	var selective_reward = DroneTrainingReward.new()
	selective_reward.configure_components({
		"approach": false,
		"radius": true,
		"survival": false,
		"ground_safety": false,
		"smoothness": false,
		"obstacle": false,
		"failure": false,
	})
	selective_reward.reset(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 1.0)
	var selective_result = selective_reward.step(
		Vector3(0.5, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		1.0,
		0.5,
		[1.0, 0.0, 1.0, 0.0],
		{
			"nearest_distance_m": 0.1,
			"maximum_distance_m": 4.0,
			"closing_speed_mps": 3.0,
		}
	)
	_expect(is_zero_approx(float(selective_result["approach_reward"])),
		"a disabled approach component contributes no score")
	_expect(is_zero_approx(float(selective_result["smoothness_reward"])),
		"a disabled smoothness component contributes no score")
	_expect(is_zero_approx(float(selective_result["obstacle_reward"])),
		"a disabled obstacle component contributes no score")
	_expect(float(selective_result["radius_reward"]) > 0.0,
		"an enabled target-radius component still contributes score")

	var survival_reward = DroneTrainingReward.new()
	survival_reward.configure_components({
		"approach": false,
		"radius": false,
		"survival": true,
		"ground_safety": false,
		"smoothness": false,
		"obstacle": false,
		"failure": false,
	})
	survival_reward.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0, 20.0)
	var early_survival = survival_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		1.0
	)
	var early_survival_value = float(early_survival["survival_reward"])
	for _index in range(18):
		survival_reward.step(
			Vector3.ZERO,
			Vector3(10.0, 0.0, 0.0),
			1.0,
			1.0
		)
	var late_survival = survival_reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		1.0
	)
	_expect(
		float(late_survival["survival_reward"])
		> early_survival_value,
		"survival reward grows later in the episode"
	)
	_expect(
		float(late_survival["cumulative_survival_reward"])
		<= DroneTrainingReward.SURVIVAL_REWARD_MAX_PER_EPISODE + 0.00001,
		"dense survival reward remains bounded per episode"
	)

	var ground_reward = DroneTrainingReward.new()
	ground_reward.configure_components({
		"approach": false,
		"radius": false,
		"survival": false,
		"ground_safety": true,
		"smoothness": false,
		"obstacle": false,
		"failure": false,
	})
	ground_reward.reset(Vector3(0.0, 2.5, 0.0), Vector3.ZERO, 1.0)
	var safe_descent = ground_reward.step(
		Vector3(0.0, 2.0, 0.0), Vector3.ZERO, 1.0, 0.5, [],
		{"ground_clearance_m": 2.0}
	)
	_expect(is_zero_approx(float(safe_descent["ground_safety_reward"])),
		"descending at or above two metres of clearance is not punished")
	var unsafe_descent = ground_reward.step(
		Vector3(0.0, 1.0, 0.0), Vector3.ZERO, 1.0, 0.5, [],
		{"ground_clearance_m": 1.0}
	)
	_expect(float(unsafe_descent["ground_safety_reward"]) < 0.0,
		"descending below two metres receives a dense ground-safety penalty")
	ground_reward.reset(Vector3(0.0, 1.0, 0.0), Vector3.ZERO, 1.0)
	var low_hover = ground_reward.step(
		Vector3(0.0, 1.0, 0.0), Vector3.ZERO, 1.0, 0.5, [],
		{"ground_clearance_m": 1.0}
	)
	_expect(
		float(low_hover["ground_safety_reward"]) < 0.0,
		"hovering low without descending is still mildly undesirable instead of a zero-cost local optimum"
	)

	var abuse_reward = DroneTrainingReward.new()
	abuse_reward.configure_components({
		"approach": false,
		"radius": false,
		"survival": false,
		"ground_safety": false,
		"smoothness": true,
		"obstacle": false,
		"failure": false,
	})
	abuse_reward.reset(Vector3.ZERO, Vector3.ZERO, 1.0)
	var abuse_result: Dictionary = {}
	for _index in range(8):
		abuse_result = abuse_reward.step(
			Vector3.ZERO, Vector3.ZERO, 1.0, 0.05,
			[1.0, 0.0, 0.0, 0.0]
		)
	_expect(float(abuse_result["action_abuse_reward"]) < 0.0,
		"sustained extreme one-propeller output is punished after a short grace period")


func _test_reward_card_configuration() -> void:
	var source_deck = DroneTrainingRewardDeck.new()
	source_deck.card("approach").intensity = 2.0
	source_deck.card("smoothness").enabled = false
	var configuration = source_deck.configuration_dictionary()
	var restored_deck = DroneTrainingRewardDeck.new()
	restored_deck.load_configuration(configuration)
	_expect(
		is_equal_approx(restored_deck.card("approach").intensity, 2.0),
		"drone reward-card intensity survives configuration serialization"
	)
	_expect(
		not restored_deck.card("smoothness").enabled,
		"drone reward-card enable switches survive configuration serialization"
	)
	var legacy_scalar_deck: DroneTrainingRewardDeck = DroneTrainingRewardDeck.new()
	legacy_scalar_deck.card("approach").enabled = false
	legacy_scalar_deck.load_legacy_enabled_components({"approach": "true"})
	_expect(
		not legacy_scalar_deck.card("approach").enabled,
		"malformed legacy reward scalars no longer become enabled through generic bool coercion"
	)
	var malformed_pending_group: Dictionary = {
		"pending_reward_config": "broken",
		"pending_reward_cardset_id": "should-not-apply",
		"pending_reward_cardset_name": "Should not apply",
	}
	_expect(
		not RewardCardDeckSupport.apply_pending_configuration(
			malformed_pending_group,
			restored_deck.cards
		),
		"malformed queued reward-card state fails closed instead of throwing"
	)
	_expect(
		malformed_pending_group.get("pending_reward_config", {}) is Dictionary
		and not malformed_pending_group.has("pending_reward_cardset_id")
		and not malformed_pending_group.has("pending_reward_cardset_name"),
		"discarding malformed queued reward-card state also clears stale pending cardset metadata"
	)
	var malformed_nested_pending_group: Dictionary = {
		"pending_reward_config": {"approach": "broken"},
		"pending_reward_cardset_id": "should-not-apply",
		"pending_reward_cardset_name": "Should not apply",
	}
	_expect(
		not RewardCardDeckSupport.apply_pending_configuration(
			malformed_nested_pending_group,
			restored_deck.cards
		),
		"malformed nested reward-card edits are rejected as a whole instead of being labeled active"
	)
	_expect(
		not malformed_nested_pending_group.has("pending_reward_cardset_id")
		and not malformed_nested_pending_group.has("pending_reward_cardset_name"),
		"rejecting a malformed nested reward-card edit clears its pending preset identity"
	)
	var invalid_field_pending_group: Dictionary = {
		"pending_reward_config": {"approach": {"enabled": "yes"}},
		"pending_reward_cardset_id": "should-not-apply",
		"pending_reward_cardset_name": "Should not apply",
	}
	_expect(
		not RewardCardDeckSupport.apply_pending_configuration(
			invalid_field_pending_group,
			restored_deck.cards
		),
		"wrong-type fields inside queued reward-card records reject the whole pending edit"
	)
	var unknown_card_pending_group: Dictionary = {
		"pending_reward_config": {"removed_future_card": {"enabled": true}},
		"pending_reward_cardset_id": "should-not-apply",
		"pending_reward_cardset_name": "Should not apply",
	}
	_expect(
		not RewardCardDeckSupport.apply_pending_configuration(
			unknown_card_pending_group,
			restored_deck.cards
		)
		and not unknown_card_pending_group.has("pending_reward_cardset_id"),
		"unknown queued card IDs fail atomically instead of partially applying a stale preset"
	)
	var drone_enabled_before_malformed_scalar: bool = restored_deck.card("approach").enabled
	restored_deck.load_configuration({"approach": "false"})
	_expect(
		restored_deck.card("approach").enabled == drone_enabled_before_malformed_scalar,
		"current drone reward-card configuration ignores malformed scalar entries instead of coercing them to booleans"
	)
	var turret_deck: TurretRewardDeck = TurretRewardDeck.new()
	var turret_enabled_before_malformed_scalar: bool = turret_deck.card("aim").enabled
	turret_deck.load_configuration({"aim": "false"})
	_expect(
		turret_deck.card("aim").enabled == turret_enabled_before_malformed_scalar,
		"current turret reward-card configuration ignores malformed scalar entries instead of coercing them to booleans"
	)
	var finite_intensity_before: float = restored_deck.card("approach").intensity
	restored_deck.load_configuration({
		"approach": {
			"id": "approach",
			"enabled": true,
			"intensity": NAN,
		},
	})
	_expect(
		is_finite(restored_deck.card("approach").intensity)
		and is_equal_approx(restored_deck.card("approach").intensity, finite_intensity_before),
		"shared reward-card loading cannot inject a non-finite intensity into drone, limb, or turret rewards"
	)
	var shared_card = FourLimbRewardCard.new("shared", "Shared")
	var shared_intensity_before: float = shared_card.intensity
	var shared_enabled_before: bool = shared_card.enabled
	shared_card.load_dictionary({
		"id": "shared",
		"enabled": {"broken": true},
		"intensity": {"broken": true},
	})
	_expect(
		shared_card.enabled == shared_enabled_before
		and is_equal_approx(shared_card.intensity, shared_intensity_before),
		"wrong-type shared reward-card fields fall back instead of throwing or mutating live reward state"
	)
	_expect(
		not TrainingRewardCardsetLibrary.configurations_match(
			{"approach": {"enabled": {"broken": true}, "intensity": {"broken": true}}},
			{"approach": {"enabled": true, "intensity": 0.0}}
		),
		"malformed saved reward-card preset fields are rejected during preset matching instead of being cast or misidentified"
	)
	var malformed_card = FourLimbRewardCard.new(
		"malformed",
		"Malformed",
		"",
		NAN,
		NAN,
		NAN,
		NAN
	)
	_expect(
		is_finite(malformed_card.minimum_intensity)
		and is_finite(malformed_card.maximum_intensity)
		and is_finite(malformed_card.step)
		and is_finite(malformed_card.intensity),
		"shared reward-card construction contains non-finite configuration before it reaches a reward equation"
	)
	var reward = DroneTrainingReward.new()
	reward.configure_components(restored_deck.configuration_dictionary())
	reward.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	var result = reward.step(
		Vector3(1.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		1.0,
		1.0
	)
	_expect(
		is_equal_approx(float(result.get("approach_reward", 0.0)), 0.18),
		"a drone reward card scales the complete visible component"
	)
	var episode = DroneTrainingEpisode.new()
	var drone = ServerDrone.new()
	drone.current_health = 10.0
	drone.activated = true
	drone.position = Vector3(0.0, 1.0, 0.0)
	source_deck.card("failure").intensity = 2.0
	episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		99,
		99001,
		source_deck.configuration_dictionary(),
		{"ground_contact": true}
	)
	drone.position = Vector3(0.0, 0.1, 0.0)
	var terminal = episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(
		float(terminal.get("failure_penalty", 0.0)) < -4.0,
		"the terminal failure card intensity also scales drone episode failure"
	)


func _test_controlled_episode() -> void:
	var drone = ServerDrone.new()
	drone.current_health = 10.0
	drone.activated = true
	drone.position = Vector3(0.0, 1.0, 0.0)
	var episode = DroneTrainingEpisode.new()
	episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		2.0,
		3,
		12345
	)
	var running = episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(not bool(running.get("finished", true)),
		"a valid episode remains active before its timeout")
	var timed_out = episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(bool(timed_out.get("finished", false)),
		"episode ends at its configured duration")
	_expect(str(timed_out.get("termination_reason", "")) == "time_limit",
		"ordinary duration completion is identified as the time limit")
	_expect(bool(timed_out.get("truncated", false)),
		"time limits are marked as truncations for future value learning")
	_expect(not bool(timed_out.get("terminated", true)),
		"time limits are not mislabeled as natural terminal states")
	_expect(int(timed_out.get("episode_seed", 0)) == 12345,
		"episode result retains the deterministic comparison seed")
	_expect(
		not episode._is_outside_arena(Vector3(0.0, 50.0, 0.0), Vector3(24.0, 8.0, 16.0)),
		"drone arena bounds do not impose a hidden vertical ceiling on high target pursuit"
	)

	var permissive_episode = DroneTrainingEpisode.new()
	drone.current_health = 10.0
	drone.activated = true
	drone.position = Vector3(0.0, 0.1, 0.0)
	drone.rotation = Vector3(PI, 0.0, 0.0)
	permissive_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		30,
		123451
	)
	var permissive_result = permissive_episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(
		str(permissive_result.get("termination_reason", "")) == "running",
		"ground contact and inverted orientation are non-terminal by default"
	)
	_expect(
		not bool(permissive_result.get("episode_termination_options", {}).get("ground_contact", true)),
		"episode results expose the permissive default ground-contact policy"
	)
	_expect(
		not bool(DroneTrainingEpisode.sanitize_termination_options(
			{"ground_contact": 1}
		).get("ground_contact", true)),
		"malformed numeric terminal flags fail closed instead of becoming enabled booleans"
	)

	# Historical saved options may still contain a `flipped` key. It must be ignored: inverted
	# orientation is part of the behavior space, not an artificial terminal condition.
	var inverted_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	drone.rotation = Vector3(PI, 0.0, 0.0)
	inverted_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		31,
		123452,
		{},
		{"flipped": true}
	)
	var inverted_result = inverted_episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(
		str(inverted_result.get("termination_reason", "")) == "running",
		"inverted orientation stays non-terminal even when an old flipped option is supplied"
	)
	_expect(
		not inverted_result.get("episode_termination_options", {}).has("flipped"),
		"episode results no longer expose the removed flipped terminal option"
	)
	drone.rotation = Vector3.ZERO

	var crash_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	crash_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		4,
		12346,
		{},
		{"ground_contact": true}
	)
	drone.position = Vector3(0.0, 0.1, 0.0)
	var crashed = crash_episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(str(crashed.get("termination_reason", "")) == "ground_crash",
		"ground contact ends a controlled episode early")
	_expect(bool(crashed.get("terminated", false)) and not bool(crashed.get("truncated", true)),
		"physical failure is a terminal state rather than a time-limit truncation")
	_expect(float(crashed.get("external_penalty", 0.0)) < 0.0,
		"physical failure receives an explicit learning penalty")

	var late_failure_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	late_failure_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		40,
		22346,
		{
			"approach": false,
			"radius": false,
			"survival": false,
			"ground_safety": false,
			"smoothness": false,
			"obstacle": false,
			"failure": true,
		},
		{"ground_contact": true}
	)
	for _index in range(18):
		late_failure_episode.step(
			drone,
			Vector3(5.0, 1.0, 0.0),
			0.5,
			Vector3(24.0, 8.0, 16.0),
			1.0
		)
	drone.position = Vector3(0.0, 0.1, 0.0)
	var late_crash = late_failure_episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		0.1
	)
	_expect(
		float(crashed.get("failure_penalty", 0.0))
		< float(late_crash.get("failure_penalty", 0.0)),
		"early suicide receives a stronger terminal penalty than a late failure"
	)

	var no_failure_penalty_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	no_failure_penalty_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		5,
		12347,
		{"failure": false},
		{"ground_contact": true}
	)
	drone.position = Vector3(0.0, 0.1, 0.0)
	var unpunished_crash = no_failure_penalty_episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(bool(unpunished_crash.get("terminated", false)),
		"disabling failure reward does not disable physical episode termination")
	_expect(not unpunished_crash.has("external_penalty"),
		"a group can disable the terminal failure score independently")

	var destroyed_episode = DroneTrainingEpisode.new()
	drone.current_health = 10.0
	drone.activated = true
	drone.position = Vector3(0.0, 0.1, 0.0)
	destroyed_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		32,
		123453
	)
	drone.current_health = 0.0
	var destroyed_result = destroyed_episode.step(
		drone,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(
		str(destroyed_result.get("termination_reason", "")) == "destroyed",
		"zero health remains terminal even when the optional ground cutoff is disabled"
	)
	drone.current_health = 10.0
	drone.activated = true

	var arena_exit_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	drone.activated = true
	arena_exit_episode.start(
		drone.position,
		Vector3(0.0, 3.0, 0.0),
		0.5,
		600.0,
		6,
		12348
	)
	drone.position = Vector3(0.0, 20.0, 0.0)
	var high_flight = arena_exit_episode.step(
		drone,
		Vector3(0.0, 3.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(
		str(high_flight.get("termination_reason", "")) == "running",
		"altitude alone never marks a drone as having left the arena"
	)
	drone.position = Vector3(12.3, 20.0, 0.0)
	var horizontal_exit = arena_exit_episode.step(
		drone,
		Vector3(0.0, 3.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		0.1
	)
	_expect(
		str(horizontal_exit.get("termination_reason", "")) == "left_arena",
		"crossing the horizontal arena boundary still terminates immediately"
	)

	var edge_exploit_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	drone.activated = true
	edge_exploit_episode.start(
		drone.position,
		Vector3(20.0, 1.0, 0.0),
		0.5,
		600.0,
		7,
		12349
	)
	drone.position = Vector3(10.0, 1.0, 0.0)
	edge_exploit_episode.step(
		drone,
		Vector3(20.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	drone.position = Vector3(12.3, 1.0, 0.0)
	var edge_exploit = edge_exploit_episode.step(
		drone,
		Vector3(20.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		0.1
	)
	_expect(
		float(edge_exploit.get("cumulative_progress_reward", 0.0)) > 0.0,
		"the edge-bound flight receives dense progress guidance before it fails"
	)
	_expect(
		is_zero_approx(float(edge_exploit.get("unreached_target_progress_correction", 0.0))),
		"unreached terminal episodes keep their complete dense progress signal"
	)
	_expect(
		float(edge_exploit.get("cumulative_approach_reward", 0.0)) > 0.0,
		"useful dense progress remains visible instead of being erased wholesale at failure"
	)
	_expect(
		float(edge_exploit.get("total_reward", 1.0)) < 0.0,
		"flying toward an edge and dying without reaching the target cannot finish positive"
	)

	var partial_timeout_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	drone.activated = true
	partial_timeout_episode.start(
		drone.position,
		Vector3(10.0, 1.0, 0.0),
		0.5,
		1.0,
		8,
		12350
	)
	drone.position = Vector3(5.0, 1.0, 0.0)
	var partial_timeout = partial_timeout_episode.step(
		drone,
		Vector3(10.0, 1.0, 0.0),
		0.5,
		Vector3(24.0, 8.0, 16.0),
		1.0
	)
	_expect(
		str(partial_timeout.get("termination_reason", "")) == "time_limit",
		"partial progress that reaches the configured duration ends as a truncation"
	)
	_expect(
		is_zero_approx(float(partial_timeout.get("unreached_target_progress_correction", 0.0))),
		"time-limit episodes are not flattened merely because they missed the radius"
	)
	_expect(
		float(partial_timeout.get("total_reward", -1.0)) > 0.0,
		"useful partial movement plus surviving to timeout can finish modestly positive"
	)
	_expect(
		float(partial_timeout.get("timeout_survival_bonus", 0.0)) > 0.0,
		"reaching the time limit adds the bounded survival bonus"
	)

	var wall_deadlock_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	drone.activated = true
	wall_deadlock_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		600.0,
		9,
		12351
	)
	var wall_deadlock_result: Dictionary = {}
	for _step_index in range(50):
		wall_deadlock_result = wall_deadlock_episode.step(
			drone,
			Vector3(5.0, 1.0, 0.0),
			0.5,
			Vector3(24.0, 8.0, 16.0),
			0.1,
			{"wall_contact": true}
		)
		if bool(wall_deadlock_result.get("finished", false)):
			break
	_expect(
		str(wall_deadlock_result.get("termination_reason", ""))
		== "wall_deadlock",
		"sustained physical wall contact ends a long episode early"
	)
	_expect(
		float(wall_deadlock_result.get("episode_elapsed_seconds", 600.0)) < 5.0,
		"a jammed worker cannot hold the entire group at a long time limit"
	)

	var recovered_contact_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, 0.0)
	recovered_contact_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		7,
		12349
	)
	var recovered_contact_result: Dictionary = {}
	for step_index in range(50):
		recovered_contact_result = recovered_contact_episode.step(
			drone,
			Vector3(5.0, 1.0, 0.0),
			0.5,
			Vector3(24.0, 8.0, 16.0),
			0.1,
			{"wall_contact": step_index < 10}
		)
	_expect(
		not bool(recovered_contact_result.get("finished", true)),
		"a brief wall scrape that separates before the limit remains recoverable"
	)
	_expect(
		is_zero_approx(float(recovered_contact_result.get(
			"wall_deadlock_seconds",
			-1.0
		))),
		"the sustained-contact timer resets after genuine wall separation"
	)

	var sliding_contact_episode = DroneTrainingEpisode.new()
	drone.position = Vector3(0.0, 1.0, -2.0)
	sliding_contact_episode.start(
		drone.position,
		Vector3(5.0, 1.0, 0.0),
		0.5,
		20.0,
		8,
		12350
	)
	var sliding_contact_result: Dictionary = {}
	for _step_index in range(50):
		drone.position.z += 0.1
		sliding_contact_result = sliding_contact_episode.step(
			drone,
			Vector3(5.0, 1.0, 0.0),
			0.5,
			Vector3(24.0, 8.0, 16.0),
			0.1,
			{"wall_contact": true}
		)
	_expect(
		not bool(sliding_contact_result.get("finished", true)),
		"continuous wall contact that makes real positional progress is not a deadlock"
	)
	_expect(
		float(sliding_contact_result.get("wall_deadlock_seconds", 99.0)) < 1.0,
		"moving along a wall repeatedly resets the bounded-contact deadlock window"
	)


func _test_immutable_model_versions() -> void:
	var test_root = "user://tests/ml_model_registry"
	var registry = DroneTrainingModelRegistry.new(test_root)
	var model_name = "Automated Test %d" % Time.get_ticks_usec()
	var first = registry.save_version(model_name, DroneTrainingPolicy.DEFAULT_WEIGHTS)
	var second = registry.save_version(
		model_name,
		DroneTrainingPolicy.DEFAULT_WEIGHTS,
		str(first.get("version_id", ""))
	)
	_expect(not first.is_empty() and not second.is_empty(),
		"model registry persists candidate versions")
	_expect(str(first.get("version_id", "")) != str(second.get("version_id", "")),
		"saving again creates a distinct immutable version")
	_expect(int(second.get("version", 0)) == int(first.get("version", 0)) + 1,
		"model versions increase monotonically")
	var external_model_name: String = "External Removal %d" % Time.get_ticks_usec()
	var external_first: Dictionary = registry.save_version(
		external_model_name,
		DroneTrainingPolicy.DEFAULT_WEIGHTS
	)
	_expect(
		not external_first.is_empty(),
		"separate drone model family can be saved for identity-floor coverage"
	)
	_expect(
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(str(external_first.get("storage_path", "")))
		),
		"test can simulate a valid drone model directory being removed outside the registry"
	)
	var external_second: Dictionary = registry.save_version(
		external_model_name,
		DroneTrainingPolicy.DEFAULT_WEIGHTS
	)
	_expect(
		int(external_second.get("version", 0)) == 2,
		"successfully issued drone model identities remain reserved after external directory removal"
	)
	_expect(
		FileAccess.file_exists(
			str(first.get("storage_path", "")).path_join("model.json")
		),
		"the earlier model artifact still exists after saving a newer version"
	)
	var first_run = registry.record_episode(first, {"total_reward": 1.0})
	var second_run = registry.record_episode(first, {"total_reward": 2.0})
	_expect(not first_run.is_empty() and not second_run.is_empty(),
		"episode results are persisted beside their exact model version")
	_expect(first_run != second_run,
		"each episode receives a separate result artifact instead of overwriting history")
	var trainer = DronePPOTrainer.new(_ppo_config({}), 9876)
	var ppo_checkpoint = trainer.to_checkpoint()
	ppo_checkpoint["training_environment"] = {
		"reward_schema_version": DroneTrainingReward.SCHEMA_VERSION,
		"reward_components": DroneTrainingReward.DEFAULT_COMPONENTS.duplicate(),
	}
	var malformed_checkpoint_to_save = ppo_checkpoint.duplicate(true)
	malformed_checkpoint_to_save["training"] = "broken"
	_expect(
		registry.save_training_checkpoint(
			"Malformed Training Checkpoint",
			malformed_checkpoint_to_save
		).is_empty(),
		"drone model registry rejects wrong-type checkpoint training metadata before writing a model version"
	)
	var verification_root: String = "user://tests/drone_model_verification_%d" % Time.get_ticks_usec()
	var verification_registry: FailingVerificationDroneModelRegistry = (
		FailingVerificationDroneModelRegistry.new(verification_root)
	)
	verification_registry.fail_manifest_revision = 1
	var failed_verified_save: Dictionary = verification_registry.save_training_checkpoint(
		"Verification Save",
		ppo_checkpoint
	)
	_expect(
		failed_verified_save.is_empty(),
		"drone model first-save verification failure rejects and removes the unverified version"
	)
	verification_registry.fail_manifest_revision = 0
	var verified_retry: Dictionary = verification_registry.save_training_checkpoint(
		"Verification Save",
		ppo_checkpoint
	)
	_expect(
		int(verified_retry.get("version", 0)) == 1,
		"failed drone model verification does not burn an immutable version identity"
	)
	var ppo_version = registry.save_ppo_checkpoint(
		model_name,
		ppo_checkpoint,
		str(second.get("version_id", ""))
	)
	_expect(not ppo_version.is_empty(),
		"PPO network checkpoint receives its own immutable model version")
	_expect(
		FileAccess.file_exists(
			str(ppo_version.get("storage_path", "")).path_join("checkpoint.json")
		),
		"PPO parameters and optimizer state are stored beside the manifest"
	)
	_expect(
		not str(ppo_version.get("created_utc", "")).is_empty()
		and not str(ppo_version.get("training_updated_utc", "")).is_empty(),
		"saved training checkpoints expose creation and last-training timestamps"
	)
	_expect(
		registry.mark_version_used(ppo_version),
		"model registry records when a saved checkpoint is used"
	)
	var used_version = registry.get_version(str(ppo_version.get("version_id", "")))
	_expect(
		not str(used_version.get("last_used_utc", "")).is_empty()
		and int(used_version.get("use_count", 0)) == 1,
		"last-used metadata is merged back into Model Library records"
	)
	var forged_storage_record: Dictionary = ppo_version.duplicate(true)
	forged_storage_record["storage_path"] = "user://tests/forged-drone-model-path"
	var forged_storage_checkpoint: Dictionary = registry.load_ppo_checkpoint(
		forged_storage_record
	)
	_expect(
		not forged_storage_checkpoint.is_empty(),
		"drone model loads re-resolve immutable version identity instead of trusting caller-provided storage paths"
	)
	_expect(
		registry.mark_version_used(forged_storage_record)
		and int(registry.get_version(str(ppo_version.get("version_id", ""))).get(
			"use_count",
			0
		)) == 2,
		"drone model usage metadata is written only to the registered version directory"
	)
	var manifest_path: String = str(ppo_version.get("storage_path", "")).path_join(
		DroneTrainingModelRegistry.MANIFEST_FILE_NAME
	)
	var original_manifest: Dictionary = TrainingFileIO.read_json_dictionary(manifest_path)
	var redirected_manifest: Dictionary = original_manifest.duplicate(true)
	redirected_manifest["checkpoint_file"] = "../redirected-checkpoint.json"
	var redirected_manifest_written: bool = TrainingFileIO.write_json_dictionary_atomic(
		manifest_path,
		redirected_manifest
	)
	_expect(
		redirected_manifest_written
		and registry.get_version(str(ppo_version.get("version_id", ""))).is_empty()
		and registry.load_ppo_checkpoint(ppo_version).is_empty(),
		"drone model registry rejects a manifest that redirects its immutable checkpoint path"
	)
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, original_manifest)
		and not registry.get_version(str(ppo_version.get("version_id", ""))).is_empty(),
		"restoring a valid drone manifest restores the registered model version"
	)
	var restored_checkpoint = registry.load_ppo_checkpoint(ppo_version)
	_expect(
		str(restored_checkpoint.get("algorithm", ""))
		== DronePPOTrainer.ALGORITHM_NAME,
		"registered PPO checkpoint is retrievable by version"
	)
	_expect(
		str(ppo_version.get("checkpoint_kind", "")) == "current",
		"checkpoint manifest identifies whether current or best weights were saved"
	)
	_expect(
		ppo_version.has("has_best_episode"),
		"checkpoint manifest distinguishes a real best score from a placeholder zero"
	)
	_expect(
		not bool(ppo_version.get("score_matches_checkpoint", true)),
		"current-weight saves do not pretend a historical best score belongs to those exact weights"
	)
	var saved_environment: Dictionary = ppo_version.get("training_environment", {})
	_expect(
		int(saved_environment.get("reward_schema_version", 0))
		== DroneTrainingReward.SCHEMA_VERSION,
		"checkpoint manifests retain the reward contract used for their scores"
	)
	var legacy_tooltip_record = ppo_version.duplicate(true)
	legacy_tooltip_record["training_environment"] = {
		"reward_components": DroneTrainingReward.DEFAULT_COMPONENTS.duplicate(),
	}
	_expect(
		registry.tooltip_for_version(legacy_tooltip_record).contains("legacy reward v1"),
		"older checkpoint scores are visibly marked as incomparable instead of reused silently"
	)
	var malformed_manifest = ppo_version.duplicate(true)
	malformed_manifest["training_environment"] = 17
	malformed_manifest["runtime_contract"] = "broken"
	malformed_manifest["weights"] = 4
	malformed_manifest["training_update"] = {"broken": true}
	malformed_manifest["environment_steps"] = NAN
	malformed_manifest["score_matches_checkpoint"] = {"broken": true}
	malformed_manifest["best_candidate_score"] = NAN
	var malformed_manifest_tooltip: String = registry.tooltip_for_version(malformed_manifest)
	var malformed_manifest_color: Color = registry.color_for_version(malformed_manifest)
	_expect(
		not malformed_manifest_tooltip.is_empty()
		and malformed_manifest_color.a >= 0.0,
		"malformed optional manifest metadata degrades safely when the model browser renders it"
	)
	var malformed_checkpoint = restored_checkpoint.duplicate(true)
	malformed_checkpoint["network"] = 17
	malformed_checkpoint["config"] = "broken"
	var malformed_checkpoint_inspection = (
		DroneTrainingAlgorithmCatalog.inspect_checkpoint(malformed_checkpoint)
	)
	var malformed_runtime_contract = (
		DroneTrainingAlgorithmCatalog.runtime_contract(malformed_checkpoint)
	)
	_expect(
		not bool(malformed_checkpoint_inspection.get("compatible", true))
		and int(malformed_runtime_contract.get("action_count", -1)) == 0
		and is_finite(float(malformed_runtime_contract.get("control_interval_seconds", NAN))),
		"malformed nested checkpoint metadata is inspectable without throwing or emitting NaN runtime settings"
	)
	var inspection = registry.inspect_version(ppo_version)
	var runtime_contract: Dictionary = inspection.get("runtime_contract", {})
	_expect(bool(inspection.get("compatible", false)),
		"saved PPO models advertise compatibility with the current runtime")
	_expect(
		int(runtime_contract.get("observation_schema_version", 0))
		== DronePPOObservationEncoder.SCHEMA_VERSION,
		"model inspection exposes the exact observation schema for later in-game use"
	)
	_expect(
		int(runtime_contract.get("actor_feature_count", 0))
		== DronePPOObservationEncoder.ACTOR_FEATURE_COUNT,
		"model inspection exposes the actor input shape"
	)
	_expect(
		int(runtime_contract.get("action_count", 0))
		== DronePPOActorCritic.ACTION_COUNT,
		"model inspection exposes the four-motor runtime action contract"
	)
	_expect(
		bool(inspection.get("trainable", false)),
		"current observation-schema checkpoints can be continued by the trainer"
	)
	var rolling_source := ppo_version.duplicate(true)
	var rolling_run_id: String = registry.record_episode(
		rolling_source,
		{"total_reward": 3.0}
	)
	var rolling_result_path: String = str(ppo_version.get("storage_path", "")).path_join(
		DroneTrainingModelRegistry.RUN_DIRECTORY_NAME
	).path_join(rolling_run_id + ".json")
	_expect(
		not rolling_run_id.is_empty()
		and FileAccess.file_exists(rolling_result_path),
		"a rolling candidate can initially own exact-policy evaluation results"
	)
	var version_count_before_overwrite := registry.list_versions().size()
	var rolling_checkpoint := trainer.to_checkpoint()
	rolling_checkpoint["training_environment"] = ppo_checkpoint[
		"training_environment"
	].duplicate(true)
	var rolling_training: Dictionary = rolling_checkpoint.get(
		"training",
		{}
	).duplicate(true)
	rolling_training["update_count"] = 17
	rolling_training["environment_steps"] = 1234
	rolling_checkpoint["training"] = rolling_training
	var verification_rolling_source: Dictionary = verified_retry.duplicate(true)
	var verification_run_id: String = verification_registry.record_episode(
		verification_rolling_source,
		{"total_reward": 8.0}
	)
	var verification_run_path: String = str(verified_retry.get("storage_path", "")).path_join(
		DroneTrainingModelRegistry.RUN_DIRECTORY_NAME
	).path_join(verification_run_id + ".json")
	var verification_replacement: Dictionary = ppo_checkpoint.duplicate(true)
	verification_replacement["test_overwrite_marker"] = "replacement"
	verification_registry.fail_manifest_revision = 2
	_expect(
		verification_registry.overwrite_training_checkpoint(
			verified_retry,
			verification_replacement,
			"current"
		).is_empty(),
		"rolling drone save rejects a stored model whose post-write verification fails"
	)
	verification_registry.fail_manifest_revision = 0
	var verification_restored: Dictionary = verification_registry.load_training_checkpoint(
		verified_retry
	)
	var verification_restored_record: Dictionary = verification_registry.get_version(
		str(verified_retry.get("version_id", ""))
	)
	_expect(
		not verification_restored.is_empty()
		and not verification_restored.has("test_overwrite_marker")
		and int(verification_restored_record.get("checkpoint_revision", 0)) == 1
		and FileAccess.file_exists(verification_run_path),
		"failed rolling verification restores the previous drone checkpoint, manifest, and evaluation results"
	)
	verification_registry.delete_version(verified_retry)

	var corrupt_rolling_checkpoint = rolling_checkpoint.duplicate(true)
	corrupt_rolling_checkpoint["network"] = {}
	_expect(
		registry.overwrite_training_checkpoint(
			ppo_version,
			corrupt_rolling_checkpoint,
			"current"
		).is_empty()
		and not registry.load_ppo_checkpoint(ppo_version).is_empty(),
		"rolling drone saves reject an unusable network before replacing the valid checkpoint"
	)
	var overwritten = registry.overwrite_training_checkpoint(
		ppo_version,
		rolling_checkpoint,
		"current"
	)
	_expect(
		not overwritten.is_empty()
		and str(overwritten.get("version_id", ""))
		== str(ppo_version.get("version_id", ""))
		and int(overwritten.get("checkpoint_revision", 0)) == 2,
		"rolling save updates the same version identity and advances its checkpoint revision"
	)
	_expect(
		registry.list_versions().size() == version_count_before_overwrite
		and str(overwritten.get("created_utc", ""))
		== str(ppo_version.get("created_utc", ""))
		and int(overwritten.get("training_update", 0)) == 17,
		"rolling save preserves creation identity without creating another model folder"
	)
	_expect(
		not FileAccess.file_exists(rolling_result_path),
		"overwriting weights removes evaluation results that belonged to the previous revision"
	)
	_expect(
		registry.record_episode(rolling_source, {"total_reward": 4.0}).is_empty(),
		"an evaluator using stale rolling weights cannot attach results to the replacement revision"
	)
	var current_revision_result := registry.record_episode(
		overwritten,
		{"total_reward": 5.0}
	)
	_expect(
		not current_revision_result.is_empty(),
		"an evaluator using the current rolling revision can persist its result"
	)
	ppo_version = overwritten
	var first_storage_path = str(first.get("storage_path", ""))
	_expect(
		registry.delete_version(first),
		"an explicitly selected old model version can be permanently deleted"
	)
	var deleted_record = registry.get_version(str(first.get("version_id", "")))
	var retained_record = registry.get_version(str(second.get("version_id", "")))
	_expect(
		not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(first_storage_path)
		)
		and deleted_record.is_empty()
		and not retained_record.is_empty(),
		"deletion removes only that version directory and preserves newer siblings"
	)
	_expect(
		registry.delete_version(ppo_version),
		"the newest checkpoint can also be deleted without touching older versions"
	)
	var replacement = registry.save_version(
		model_name,
		DroneTrainingPolicy.DEFAULT_WEIGHTS,
		str(second.get("version_id", ""))
	)
	_expect(
		int(replacement.get("version", 0)) > int(ppo_version.get("version", 0)),
		"deleted version identities are never reused by later saves"
	)


func _test_plot_aggregation() -> void:
	var history = DroneTrainingMetricsHistory.new()
	history.record_episode({
		"episode_number": 1,
		"mean_reward_per_second": 1.0,
		"episode_elapsed_seconds": 10.0,
		"time_inside_radius_seconds": 2.0,
	}, 2)
	var unfinished_series = history.episode_mean_series(
		"mean_reward_per_second",
		"workers",
		Color.WHITE
	)
	var unfinished_points: PackedVector2Array = unfinished_series.get(
		"points",
		PackedVector2Array()
	)
	_expect(
		unfinished_points.is_empty(),
		"a group point waits for every worker before changing the graph scale"
	)
	history.record_episode({
		"episode_number": 1,
		"mean_reward_per_second": 3.0,
		"episode_elapsed_seconds": 10.0,
		"time_inside_radius_seconds": 6.0,
	}, 2)
	var reward_series = history.episode_mean_series(
		"mean_reward_per_second",
		"workers",
		Color.WHITE
	)
	var reward_points: PackedVector2Array = reward_series.get(
		"points",
		PackedVector2Array()
	)
	_expect(
		reward_points.size() == 1 and is_equal_approx(reward_points[0].y, 2.0),
		"comparison plots average every worker into one fair group point per episode"
	)
	var hover_series = history.hover_ratio_mean_series("workers", Color.WHITE)
	var hover_points: PackedVector2Array = hover_series.get(
		"points",
		PackedVector2Array()
	)
	_expect(
		hover_points.size() == 1 and is_equal_approx(hover_points[0].y, 0.4),
		"hover comparison averages worker time-inside-target ratios"
	)
	var absent_metric_series: Dictionary = history.episode_mean_series(
		"not_published_by_this_algorithm",
		"missing",
		Color.WHITE
	)
	var absent_metric_points: PackedVector2Array = absent_metric_series.get(
		"points",
		PackedVector2Array()
	)
	_expect(
		absent_metric_points.is_empty(),
		"plots do not invent zero-valued readings when a worker type does not publish a metric"
	)
	var late_group_history = DroneTrainingMetricsHistory.new()
	late_group_history.record_episode({
		"episode_number": 123,
		"mean_reward_per_second": 2.0,
	}, 1)
	var late_group_series: Dictionary = late_group_history.episode_mean_series(
		"mean_reward_per_second",
		"late group",
		Color.WHITE
	)
	var late_group_points: PackedVector2Array = late_group_series.get("points", PackedVector2Array())
	_expect(
		late_group_points.size() == 1 and is_equal_approx(late_group_points[0].x, 1.0),
		"every worker type starts its plot timeline at local episode 1 even when room-global episode numbering started earlier"
	)

	# History limits describe plotted episode points, not raw worker completions. SAC
	# commonly uses 12+ workers, so trimming the raw records would silently reduce a
	# 240-point timeline to only 20 (or fewer) visible episodes.
	var multi_worker_history = DroneTrainingMetricsHistory.new()
	var test_worker_count = 24
	var test_episode_count = DroneTrainingMetricsHistory.MAXIMUM_POINTS + 11
	for episode in range(1, test_episode_count + 1):
		for worker in range(test_worker_count):
			multi_worker_history.record_episode({
				"episode_number": episode,
				"mean_reward_per_second": float(worker),
			}, test_worker_count)
	var retained_series = multi_worker_history.episode_mean_series(
		"mean_reward_per_second",
		"many workers",
		Color.WHITE
	)
	var retained_points: PackedVector2Array = retained_series.get(
		"points",
		PackedVector2Array()
	)
	_expect(
		retained_points.size() == DroneTrainingMetricsHistory.MAXIMUM_POINTS,
		"episode plot history retains 240 averaged episodes regardless of worker count"
	)
	_expect(
		not retained_points.is_empty()
		and is_equal_approx(retained_points[0].x, 12.0)
		and is_equal_approx(retained_points[retained_points.size() - 1].x, float(test_episode_count)),
		"episode history drops only complete oldest episode buckets"
	)
	_expect(
		not retained_points.is_empty()
		and is_equal_approx(retained_points[0].y, 11.5),
		"retained episode buckets still average every worker result"
	)


func _test_plot_series_isolation() -> void:
	var plot = DroneTrainingPlot.new()
	plot.set_display_context("all:progress")
	plot.set_series([
		{
			"series_id": "drone:1:reward",
			"source_id": "drone:1",
			"body_type": "drone",
			"label": "same visible label",
			"color": Color.WHITE,
			"points": PackedVector2Array([Vector2(100.0, 5.0)]),
		},
		{
			"series_id": "limb:2:reward",
			"source_id": "limb:2",
			"body_type": "limb",
			"label": "same visible label",
			"color": Color(0.5, 0.5, 0.5, 1.0),
			"points": PackedVector2Array([Vector2(1.0, -2.0)]),
		},
	])
	_expect(
		plot.series.size() == 2
		and str(plot.series[0].get("source_id", "")) == "drone:1"
		and str(plot.series[1].get("source_id", "")) == "limb:2",
		"drone and limb measurements remain separate even when their visible labels match"
	)
	plot.cut_history_before(50.0)
	_expect(
		plot.visible_points_for_entry(plot.series[1]).is_empty(),
		"a cut made on the long drone timeline can hide an early limb point in the combined view"
	)
	plot.set_display_context("limb:2:progress")
	plot.set_series([plot.series[1]])
	_expect(
		not is_finite(plot.history_cut_minimum())
		and plot.visible_points_for_entry(plot.series[0]).size() == 1,
		"switching from drone or combined plots clears source-specific cuts instead of making limb history appear deleted"
	)
	plot.set_series([
		{
			"series_id": "duplicate",
			"label": "first",
			"points": PackedVector2Array([Vector2(1.0, 1.0)]),
		},
		{
			"series_id": "duplicate",
			"label": "second",
			"points": PackedVector2Array([Vector2(1.0, 2.0)]),
		},
	])
	_expect(
		plot.series.size() == 2
		and str(plot.series[0].get("series_id", ""))
		!= str(plot.series[1].get("series_id", "")),
		"duplicate series identities are disambiguated rather than overwriting a displayed line"
	)


func _test_sac_learning_error_plot_uses_twin_q_metrics() -> void:
	var room = DroneTrainingRoom.new()
	var history = DroneTrainingMetricsHistory.new()
	history.record_update({
		"update": 1,
		"actor_loss": 0.07,
		"q_one_loss": 0.31,
		"q_two_loss": 0.27,
		"critic_loss": 0.29,
	})
	var group: Dictionary = {
		"history": history,
		"trainer": DroneSACTrainer.new({}, 9091),
	}
	var series: Array[Dictionary] = room._drone_group_plot_series(group, "losses")
	_expect(
		series.size() == 3
		and str(series[0].get("label", "")) == "actor"
		and str(series[1].get("label", "")) == "critic Q1"
		and str(series[2].get("label", "")) == "critic Q2",
		"SAC learning-error plot exposes the actor and both actual Q critics instead of PPO's missing value_loss metric"
	)
	var q_one_points: PackedVector2Array = series[1].get("points", PackedVector2Array())
	var q_two_points: PackedVector2Array = series[2].get("points", PackedVector2Array())
	_expect(
		q_one_points.size() == 1
		and q_two_points.size() == 1
		and is_equal_approx(q_one_points[0].y, 0.31)
		and is_equal_approx(q_two_points[0].y, 0.27),
		"SAC critic plot values come from q_one_loss/q_two_loss and cannot silently flatten to zero"
	)
	room.free()


func _test_plot_cutting() -> void:
	var plot = DroneTrainingPlot.new()
	plot.set_series([{
		"label": "example",
		"color": Color.WHITE,
		"points": PackedVector2Array([
			Vector2(1.0, 10.0),
			Vector2(2.0, 20.0),
			Vector2(3.0, 30.0),
			Vector2(4.0, 40.0),
		]),
	}])
	plot.cut_history_before(2.5)
	var remaining = plot.visible_points_for_entry(plot.series[0])
	_expect(
		remaining.size() == 2
		and is_equal_approx(remaining[0].x, 3.0)
		and is_equal_approx(remaining[1].x, 4.0),
		"cutting a graph removes only the older points on its left"
	)
	plot.clear_history_cut()
	_expect(
		plot.visible_points_for_entry(plot.series[0]).size() == 4,
		"clearing a graph cut makes the complete history visible again"
	)
	_expect(
		plot.begin_cut_mode(),
		"cut mode can be opened again after an earlier cut"
	)
	plot.cancel_cut_mode()
	_expect(
		plot.begin_cut_mode(),
		"cut mode does not get stuck after being cancelled"
	)
	plot.cancel_cut_mode()


func _smoothness_cost_for_rate(control_rate_hz: int) -> float:
	var reward = DroneTrainingReward.new()
	reward.configure_components({
		"approach": false,
		"radius": false,
		"survival": false,
		"ground_safety": false,
		"smoothness": true,
		"obstacle": false,
		"failure": false,
	})
	reward.reset(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	var first_actions: Array[float] = [0.25, 0.75, 0.25, 0.75]
	var second_actions: Array[float] = [0.75, 0.25, 0.75, 0.25]
	reward.step(
		Vector3.ZERO,
		Vector3(10.0, 0.0, 0.0),
		1.0,
		0.0,
		first_actions
	)
	var interval = 1.0 / float(control_rate_hz)
	for step_index in range(control_rate_hz):
		reward.step(
			Vector3.ZERO,
			Vector3(10.0, 0.0, 0.0),
			1.0,
			interval,
			second_actions if step_index % 2 == 0 else first_actions
		)
	return float(reward.latest_result.get("cumulative_smoothness_reward", 0.0))


func _observation_with_propeller_count(count: int) -> Dictionary:
	var propellers: Array[Dictionary] = []
	for index in range(count):
		propellers.append({"slot_index": index})
	return {
		"body": {
			"position_world": Vector3.ZERO,
			"basis_world": Basis.IDENTITY,
			"linear_velocity_world": Vector3.ZERO,
			"angular_velocity_local": Vector3.ZERO,
		},
		"objective": {
			"target_position_world": Vector3(2.0, 3.0, -1.0),
			"target_hover_radius_m": 0.5,
		},
		"propellers": propellers,
	}


func _expect(condition: bool, message: String) -> void:
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
