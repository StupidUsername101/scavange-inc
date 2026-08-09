class_name FourLimbCandidateEvaluationJob
extends Node3D

signal completed(group_id: int, candidate_id: int, records: Array[Dictionary])
signal failed(group_id: int, candidate_id: int, reason: String)

#######################################################
# Hidden fixed-seed evaluator for articulated four-limb policies. It mirrors the runtime
# observation/action/reward path without adding rollout samples to the live trainer. The
# evaluator lives far away from the editable training arena so its rigid bodies cannot collide
# with or perturb live workers while still using the normal limb collision/grip contract.
#######################################################

const DECISION_INTERVAL_SECONDS = 0.05
const SETTLE_SECONDS = 0.35
const EVALUATION_WORLD_SPACING_M = 240.0
const EVALUATION_WORLD_BASE = Vector3(20000.0, 0.0, 20000.0)
const FLOOR_THICKNESS_M = 0.5
const PICKUP_ITEM_DEFINITION: TrainingItemDefinition = preload(
	"res://resources/training/items/fallback_grabbable_cargo.tres"
)

var group_id: int = -1
var candidate_id: int = -1
var candidate_hash: String = ""
var plan: Dictionary = {}
var evaluation_contract: Dictionary = {}
var evaluation_contract_hash: String = ""
var environment_revision: int = 0
var last_error: String = ""
var status: String = "starting"
var restart_count: int = 0

var candidate_checkpoint: Dictionary = {}
var body_definition: FourLimbBodyDefinition
var reward_deck: FourLimbRewardDeck = FourLimbRewardDeck.new()
var runtime_model: FourLimbPPOModel = FourLimbPPOModel.new()
var adapter: FourLimbMLBodyAdapter
var body: FourLimbPhysicalBody3D
var combat_adapter: FourLimbTrainingCombatantAdapter

var wall_spatial_hash: DroneTrainingWallSpatialHash = DroneTrainingWallSpatialHash.new()
var entity_spatial_hash: ServerSpatialHash3D = ServerSpatialHash3D.new(6.0)
var evaluation_floor: StaticBody3D
var scenario_walls: Array[Node3D] = []
var evaluation_turret: TurretPhysicalBody3D
var evaluation_turret_adapter: TurretTrainingCombatantAdapter
var evaluation_projectiles: Array[TurretTrainingProjectile3D] = []
var evaluation_pickup_item: TrainingItem3D
var evaluation_delivery_destination: TrainingItemDeliveryDestination3D

var records: Array[Dictionary] = []
var current_case: Dictionary = {}
var case_index: int = -1
var case_elapsed_seconds: float = 0.0
var case_duration_seconds: float = 0.0
var settle_remaining_seconds: float = 0.0
var decision_elapsed_seconds: float = 0.0
var interval_elapsed_seconds: float = 0.0
var total_reward: float = 0.0
var time_inside_radius_seconds: float = 0.0
var previous_observation: Dictionary = {}
var previous_commands: PackedFloat64Array = FourLimbMLAction.neutral_commands()
var action_change_pending: float = 0.0
var reward_state: Dictionary = {}
var target_position_world: Vector3 = Vector3.ZERO
var target_velocity_world: Vector3 = Vector3.ZERO
var target_radius_m: float = 1.0
var target_subject_position_world: Vector3 = Vector3.ZERO
var has_target_subject_position: bool = false
var local_spawn_position: Vector3 = Vector3.ZERO
var arena_size: Vector3 = Vector3(100.0, 8.0, 100.0)
var world_offset: Vector3 = Vector3.ZERO


static func supports_scenario_id(scenario_id: String) -> bool:
	return (
		scenario_id.begins_with("routed_target__")
		or scenario_id in [
			"ground_target",
			"obstacle_path",
			"climb_platform",
			"item_pickup",
			"item_delivery",
			"controlled_jump",
			"landing_recovery",
			"turret_exposure",
		]
	)


func configure(
	new_group_id: int,
	candidate: Dictionary,
	checkpoint: Dictionary,
	fallback_definition: FourLimbBodyDefinition,
	initial_environment_revision: int
) -> bool:
	group_id = new_group_id
	candidate_id = RLTrainingMath.finite_int_or(candidate.get("candidate_id", -1), -1)
	candidate_hash = str(candidate.get("candidate_hash", ""))
	plan = (candidate.get("evaluation_plan", {}) as Dictionary).duplicate(true)
	evaluation_contract = (candidate.get("evaluation_contract", {}) as Dictionary).duplicate(true)
	evaluation_contract_hash = str(candidate.get("evaluation_contract_hash", ""))
	environment_revision = initial_environment_revision
	candidate_checkpoint = checkpoint.duplicate(true)
	if candidate_id < 0 or candidate_hash.is_empty():
		last_error = "candidate metadata is incomplete"
		return false
	if not RLEvaluationContract.is_valid(evaluation_contract, "four_limb"):
		last_error = "candidate has no valid frozen four-limb evaluation contract"
		return false
	if evaluation_contract_hash != str(evaluation_contract.get("contract_hash", "")):
		last_error = "candidate evaluation contract hash is inconsistent"
		return false
	if str(plan.get("evaluation_contract_hash", "")) != evaluation_contract_hash:
		last_error = "candidate evaluation plan does not match its frozen environment contract"
		return false
	if (
		not RLDeterministicEvaluationSuite.is_valid_plan(plan, "four_limb")
		or candidate_checkpoint.is_empty()
	):
		last_error = "candidate evaluation plan or checkpoint is empty"
		return false
	var environment: Dictionary = evaluation_contract.get("environment", {})
	var definition_record: Dictionary = environment.get(
		"hardware",
		candidate_checkpoint.get("body_definition", {})
	)
	if not definition_record.is_empty():
		body_definition = FourLimbBodyDefinition.from_dictionary(definition_record)
	elif fallback_definition != null:
		body_definition = fallback_definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
	if body_definition == null:
		last_error = "candidate four-limb body definition is missing"
		return false
	body_definition.ensure_contract()
	var expected_signature: String = str(candidate_checkpoint.get(
		"hardware_signature",
		body_definition.hardware_signature()
	))
	if not runtime_model.load_checkpoint(candidate_checkpoint, expected_signature):
		last_error = "frozen four-limb candidate could not load its runtime policy"
		return false
	var reward_cards: Dictionary = environment.get(
		"reward_cards",
		candidate_checkpoint.get("reward_cards", {})
	)
	if not reward_cards.is_empty():
		reward_deck.load_configuration(reward_cards)
	local_spawn_position = _vector3_from_record(
		environment.get("spawn_position_m", []),
		Vector3.ZERO
	)
	arena_size = _vector3_from_record(
		environment.get("arena_size_m", []),
		Vector3(100.0, 8.0, 100.0)
	)
	world_offset = EVALUATION_WORLD_BASE + Vector3(
		float(maxi(group_id, 0)) * EVALUATION_WORLD_SPACING_M,
		0.0,
		0.0
	)
	return true


func begin() -> bool:
	if status == "failed":
		return false
	_build_evaluation_floor()
	body = FourLimbPhysicalBody3D.new()
	body.name = "FourLimbCandidateEvaluator"
	body.definition = body_definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
	body.training_invulnerable = true
	body.auto_start_simulation = true
	add_child(body)
	adapter = FourLimbMLBodyAdapter.new(body)
	status = "running"
	if not _begin_case(0):
		return false
	return true


func tick(
	delta: float,
	_space_state: PhysicsDirectSpaceState3D,
	_room_wall_spatial_hash: DroneTrainingWallSpatialHash
) -> void:
	if status != "running" or not is_instance_valid(body) or adapter == null:
		return
	var safe_delta: float = maxf(delta, 0.0)
	_update_scenario_target(safe_delta)
	entity_spatial_hash.refresh_all()
	_update_evaluation_turret_aim()
	if settle_remaining_seconds > 0.0:
		settle_remaining_seconds = maxf(settle_remaining_seconds - safe_delta, 0.0)
		adapter.apply_commands(FourLimbMLAction.neutral_commands())
		if settle_remaining_seconds <= 0.0:
			if not _prime_policy_action():
				_fail("frozen four-limb candidate produced an invalid action")
		return
	case_elapsed_seconds += safe_delta
	decision_elapsed_seconds += safe_delta
	interval_elapsed_seconds += safe_delta
	if not body.has_finite_physics_state():
		_finish_case("unstable_physics", false)
		return
	if not body.is_body_alive():
		if not _settle_pending_reward():
			_fail("hidden four-limb evaluator could not settle its final observation")
			return
		var death_reason: String = body.last_failure_reason
		if death_reason.is_empty():
			death_reason = "destroyed"
		_finish_case(death_reason, false)
		return
	if _outside_evaluation_arena(body.core_transform().origin):
		if not _settle_pending_reward():
			_fail("hidden four-limb evaluator could not settle its final observation")
			return
		_finish_case("left_arena", false)
		return
	if case_elapsed_seconds >= case_duration_seconds:
		if not _settle_pending_reward():
			_fail("hidden four-limb evaluator could not settle its timeout observation")
			return
		_finish_case("timeout", true)
		return
	if decision_elapsed_seconds < DECISION_INTERVAL_SECONDS:
		return
	var reward_delta: float = maxf(interval_elapsed_seconds, 0.000001)
	decision_elapsed_seconds = fmod(decision_elapsed_seconds, DECISION_INTERVAL_SECONDS)
	var observation: Dictionary = _capture_observation()
	if observation.is_empty():
		_fail("frozen four-limb candidate produced an invalid observation")
		return
	var combat_events: Dictionary = (
		combat_adapter.consume_combat_events()
		if combat_adapter != null
		else TrainingCombatantAdapter.EMPTY_COMBAT_EVENTS
	)
	var reward_result: Dictionary = reward_deck.step_reward(
		previous_observation if not previous_observation.is_empty() else observation,
		observation,
		reward_delta,
		reward_state,
		_reward_context(observation, combat_events)
	)
	total_reward += float(reward_result.get("total", 0.0))
	interval_elapsed_seconds = 0.0
	var target_distance: float = _target_distance_from_observation(observation)
	if target_distance <= target_radius_m:
		time_inside_radius_seconds += reward_delta
	var action: Dictionary = runtime_model.predict_action(observation)
	var commands: PackedFloat64Array = FourLimbMLAction.packed_commands(action)
	if commands.size() != FourLimbMLAction.ACTION_COUNT or not _commands_finite(commands):
		_fail("frozen four-limb candidate produced an invalid action")
		return
	if not adapter.apply_commands(commands):
		_fail("hidden four-limb evaluator rejected the candidate action")
		return
	action_change_pending = _command_change_norm(previous_commands, commands)
	previous_commands = commands
	previous_observation = observation


func _settle_pending_reward() -> bool:
	if interval_elapsed_seconds <= 0.0:
		return true
	var observation: Dictionary = _capture_observation()
	if observation.is_empty():
		return false
	var combat_events: Dictionary = (
		combat_adapter.consume_combat_events()
		if combat_adapter != null
		else TrainingCombatantAdapter.EMPTY_COMBAT_EVENTS
	)
	var reward_delta: float = maxf(interval_elapsed_seconds, 0.000001)
	var reward_result: Dictionary = reward_deck.step_reward(
		previous_observation if not previous_observation.is_empty() else observation,
		observation,
		reward_delta,
		reward_state,
		_reward_context(observation, combat_events)
	)
	total_reward += float(reward_result.get("total", 0.0))
	var target_distance: float = _target_distance_from_observation(observation)
	if target_distance <= target_radius_m:
		time_inside_radius_seconds += reward_delta
	previous_observation = observation
	action_change_pending = 0.0
	interval_elapsed_seconds = 0.0
	return true


func restart_for_environment(new_environment_revision: int) -> void:
	# Live room edits do not redefine this frozen evaluator world. Keep the counter solely for UI
	# diagnostics so the job has the same interface as the drone evaluator.
	environment_revision = new_environment_revision


func progress() -> Dictionary:
	var total_cases: int = (plan.get("cases", []) as Array).size()
	return {
		"status": status,
		"group_id": group_id,
		"candidate_id": candidate_id,
		"completed_cases": records.size(),
		"current_case_number": mini(case_index + 1, total_cases),
		"total_cases": total_cases,
		"scenario_id": str(current_case.get("scenario_id", "")),
		"case_elapsed_seconds": case_elapsed_seconds,
		"case_duration_seconds": case_duration_seconds,
		"restart_count": restart_count,
		"last_error": last_error,
	}


func shutdown() -> void:
	status = "cancelled"
	_clear_case_environment()
	if is_instance_valid(body):
		body.stop_simulation()
		body.queue_free()
	body = null
	adapter = null
	if is_instance_valid(evaluation_floor):
		evaluation_floor.collision_layer = 0
		evaluation_floor.queue_free()
	evaluation_floor = null


func _begin_case(next_case_index: int) -> bool:
	var cases: Array = plan.get("cases", [])
	if next_case_index >= cases.size():
		status = "completed"
		completed.emit(group_id, candidate_id, records)
		return true
	if not (cases[next_case_index] is Dictionary):
		return _fail_start("evaluation case descriptor is malformed")
	_clear_case_environment()
	case_index = next_case_index
	current_case = (cases[case_index] as Dictionary).duplicate(true)
	case_elapsed_seconds = 0.0
	case_duration_seconds = maxf(
		float(current_case.get("duration_seconds", RLDeterministicEvaluationSuite.DEFAULT_CASE_DURATION_SECONDS)),
		0.5
	)
	settle_remaining_seconds = SETTLE_SECONDS
	decision_elapsed_seconds = 0.0
	interval_elapsed_seconds = 0.0
	total_reward = 0.0
	time_inside_radius_seconds = 0.0
	previous_observation.clear()
	previous_commands = FourLimbMLAction.neutral_commands()
	action_change_pending = 0.0
	reward_state = reward_deck.create_worker_state()
	var scenario_id: String = str(current_case.get("scenario_id", ""))
	var seed: int = int(current_case.get("seed", 0))
	if not _build_case_environment(scenario_id, seed):
		var environment_error: String = last_error.strip_edges()
		if environment_error.is_empty():
			environment_error = "unsupported deterministic four-limb scenario: %s" % scenario_id
		return _fail_start(environment_error)
	var spawn_transform: Transform3D = _case_spawn_transform(scenario_id, seed)
	if not adapter.reset_body(spawn_transform, seed):
		return _fail_start("hidden four-limb body could not reset")
	_register_limb_combatant()
	adapter.apply_commands(FourLimbMLAction.neutral_commands())
	return true


func _prime_policy_action() -> bool:
	var observation: Dictionary = _capture_observation()
	if observation.is_empty():
		return false
	var action: Dictionary = runtime_model.predict_action(observation)
	var commands: PackedFloat64Array = FourLimbMLAction.packed_commands(action)
	if commands.size() != FourLimbMLAction.ACTION_COUNT or not _commands_finite(commands):
		return false
	if not adapter.apply_commands(commands):
		return false
	previous_observation = observation
	previous_commands = commands
	action_change_pending = 0.0
	return true


func _capture_observation() -> Dictionary:
	if not is_instance_valid(body) or not is_instance_valid(body.physical_rig):
		return {}
	var contacts: Dictionary = body.physical_rig.world_contact_snapshot()
	var threat_probe: Dictionary = (
		TrainingTurretThreatSensor.acquire(combat_adapter, entity_spatial_hash, wall_spatial_hash)
		if combat_adapter != null
		else TrainingTurretThreatSensor.empty_probe()
	)
	var pickup_item_valid: bool = is_instance_valid(evaluation_pickup_item)
	var pickup_item_held: bool = (
		body.physical_rig.holds_instance_id(evaluation_pickup_item.get_instance_id())
		if pickup_item_valid
		else false
	)
	var delivery_valid: bool = is_instance_valid(evaluation_delivery_destination)
	var delivery_active: bool = pickup_item_held and delivery_valid
	var delivery_pickup_phase: bool = delivery_valid and pickup_item_valid and not pickup_item_held
	var delivery_distance_m: float = (
		evaluation_delivery_destination.distance_to_item(evaluation_pickup_item)
		if delivery_active
		else 0.0
	)
	var effective_target_position: Vector3 = target_position_world
	var effective_target_velocity: Vector3 = target_velocity_world
	var effective_target_radius: float = target_radius_m
	if delivery_pickup_phase:
		effective_target_position = evaluation_pickup_item.global_position
		effective_target_position.y = body.core_transform().origin.y
		var pickup_task_velocity: Vector3 = evaluation_pickup_item.task_velocity_world()
		effective_target_velocity = Vector3(pickup_task_velocity.x, 0.0, pickup_task_velocity.z)
		effective_target_radius = maxf(evaluation_pickup_item.collision_radius_m() + 0.75, 0.75)
	elif delivery_active:
		var destination_up: Vector3 = evaluation_delivery_destination.global_basis.y.normalized()
		if destination_up.length_squared() <= 0.000001:
			destination_up = Vector3.UP
		effective_target_position = (
			evaluation_delivery_destination.global_position
			+ destination_up * body.definition.preferred_core_height()
		)
		effective_target_velocity = Vector3.ZERO
		effective_target_radius = evaluation_delivery_destination.radius_m
	var objective: Dictionary = {
		"target_position_world": effective_target_position,
		"target_velocity_world": effective_target_velocity,
		"target_radius": effective_target_radius,
		"pickup_item_present": pickup_item_valid,
		"pickup_item_position_world": (
			evaluation_pickup_item.global_position if pickup_item_valid else body.core_transform().origin
		),
		"pickup_item_velocity_world": (
			evaluation_pickup_item.task_velocity_world() if pickup_item_valid else Vector3.ZERO
		),
		"pickup_item_mass": evaluation_pickup_item.mass if pickup_item_valid else 0.0,
		"pickup_item_reward_value": (
			evaluation_pickup_item.reward_value if pickup_item_valid else 0.0
		),
		"pickup_item_id": (
			evaluation_pickup_item.get_instance_id() if pickup_item_valid else 0
		),
		"pickup_item_held": pickup_item_held,
		"delivery_task_phase": (
			"delivery" if delivery_active else ("pickup" if delivery_pickup_phase else "")
		),
		"delivery_destination_present": delivery_active,
		"delivery_destination_group_id": 1 if delivery_active else 0,
		"delivery_destination_stable_id": (
			evaluation_delivery_destination.stable_id() if delivery_active else ""
		),
		"delivery_destination_distance_m": delivery_distance_m,
		"delivery_item_held": delivery_active,
		"delivery_item_accepted": delivery_active,
		"delivery_item_inside": (
			evaluation_delivery_destination.contains_item(evaluation_pickup_item)
			if delivery_active
			else false
		),
		"delivery_item_instance_id": (
			evaluation_pickup_item.get_instance_id() if delivery_active else 0
		),
		"delivery_item_reward_value": (
			evaluation_pickup_item.reward_value if delivery_active else 0.0
		),
		"delivery_approach_reward_scale": 1.0,
		"delivery_completion_reward_scale": 1.0,
		"turret_threat_probe": threat_probe,
		# The evaluator is deliberately far from the live arena, so virtual arena-boundary rays
		# are disabled here. Scenario geometry remains visible through the private wall hash.
		"obstacle_probe": FourLimbTrainingObstacleSensor.sample(
			body,
			effective_target_position,
			wall_spatial_hash,
			contacts,
			Vector3.ZERO
		),
	}
	if has_target_subject_position and not delivery_active and not delivery_pickup_phase:
		objective["target_subject_position_world"] = target_subject_position_world
	return adapter.capture_observation_with_contacts(objective, contacts)


func _build_case_environment(scenario_id: String, seed: int) -> bool:
	if not supports_scenario_id(scenario_id):
		return false
	target_radius_m = 1.25
	var spawn: Vector3 = _world_spawn_position()
	var ground_target_height: float = world_offset.y + (
		body_definition.preferred_core_height()
		if body_definition != null
		else maxf(local_spawn_position.y, 0.0)
	)
	target_velocity_world = Vector3.ZERO
	has_target_subject_position = true
	target_subject_position_world = Vector3(spawn.x, world_offset.y, spawn.z)
	if scenario_id.begins_with("routed_target__"):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed
		target_position_world = spawn + Vector3(
			rng.randf_range(-8.0, 8.0),
			0.0,
			rng.randf_range(-9.0, -4.0)
		)
		target_subject_position_world = Vector3(
			target_position_world.x, world_offset.y, target_position_world.z
		)
		target_position_world.y = ground_target_height
		wall_spatial_hash.rebuild(scenario_walls)
		return true
	match scenario_id:
		"ground_target":
			target_position_world = spawn + Vector3(7.0, 0.0, -4.0)
		"obstacle_path":
			target_position_world = spawn + Vector3(0.0, 0.0, -9.0)
			_add_box_wall(spawn + Vector3(-1.8, 1.0, -3.2), Vector3(2.0, 2.0, 1.0), 0.18)
			_add_box_wall(spawn + Vector3(2.0, 1.1, -5.7), Vector3(2.2, 2.2, 1.0), -0.2)
		"climb_platform":
			var platform_top_y: float = world_offset.y + 2.0
			var platform_center = Vector3(spawn.x, world_offset.y + 1.0, spawn.z - 4.0)
			_add_box_wall(platform_center, Vector3(4.0, 2.0, 3.5), 0.0)
			target_subject_position_world = Vector3(platform_center.x, platform_top_y, platform_center.z)
			target_position_world = target_subject_position_world + Vector3.UP * body_definition.preferred_core_height()
			wall_spatial_hash.rebuild(scenario_walls)
			return true
		"item_pickup":
			target_position_world = spawn + Vector3(0.0, 0.0, -6.0)
			if not _build_pickup_item(spawn + Vector3(0.0, 0.17, -2.25)):
				return false
		"item_delivery":
			# This canonical case tests the full pickup -> conditional route switch -> carry into
			# destination contract. Before grip, the dedicated pickup observation identifies cargo;
			# once held, capture_observation redirects the generic task target to the drop-off.
			target_position_world = spawn + Vector3(0.0, 0.0, -7.0)
			if not _build_pickup_item(spawn + Vector3(0.0, 0.17, -2.25)):
				return false
			_build_delivery_destination(spawn + Vector3(0.0, 0.0, -7.0))
		"controlled_jump":
			target_position_world = spawn + Vector3(0.0, 0.0, -8.0)
			_add_box_wall(spawn + Vector3(0.0, 0.18, -3.0), Vector3(5.5, 0.36, 0.55), 0.0)
		"landing_recovery":
			target_position_world = spawn + Vector3(5.0, 0.0, -3.0)
		"turret_exposure":
			target_position_world = spawn + Vector3(7.0, 0.0, -5.0)
			if not _build_threat_turret(seed):
				return false
		_:
			return false
	# Ground benchmark targets are support-surface destinations, matching live four-limb target
	# semantics. The policy core goal stays one authored standing height above that surface.
	target_subject_position_world = Vector3(
		target_position_world.x, world_offset.y, target_position_world.z
	)
	target_position_world.y = ground_target_height
	wall_spatial_hash.rebuild(scenario_walls)
	return true


func _case_spawn_transform(scenario_id: String, seed: int) -> Transform3D:
	var position: Vector3 = _world_spawn_position()
	position.y = maxf(
		position.y,
		world_offset.y + body_definition.minimum_spawn_height(0.03)
	)
	var basis: Basis = Basis.IDENTITY
	if scenario_id == "landing_recovery":
		var sign_value: float = -1.0 if posmod(seed, 2) == 0 else 1.0
		basis = (
			Basis(Vector3.FORWARD, deg_to_rad(18.0 * sign_value))
			* Basis(Vector3.RIGHT, deg_to_rad(24.0))
		)
		position.y += 0.25
	return Transform3D(basis, position)


func _update_scenario_target(_delta: float) -> void:
	# Current limb scenarios use fixed task destinations. The hook is intentionally explicit so
	# future moving/cargo targets can be added without changing the policy observation contract.
	pass


func _finish_case(reason: String, timed_out: bool) -> void:
	if status != "running":
		return
	var terminal: Dictionary = reward_deck.terminal_reward(
		reward_state,
		"" if timed_out else reason,
		timed_out
	)
	total_reward += float(terminal.get("total", 0.0))
	var final_observation: Dictionary = _capture_observation()
	var distance: float = _target_distance_from_observation(final_observation)
	var scenario_id: String = str(current_case.get("scenario_id", ""))
	var pickup_lifted: bool = not (
		reward_state.get("rewarded_pickup_ids", {}) as Dictionary
	).is_empty()
	var item_delivered: bool = not (
		reward_state.get("rewarded_delivery_keys", {}) as Dictionary
	).is_empty()
	var success: bool = (
		pickup_lifted and timed_out
		if scenario_id == "item_pickup"
		else (
			item_delivered and timed_out
			if scenario_id == "item_delivery"
			else distance <= target_radius_m and timed_out
		)
	)
	records.append({
		"scenario_id": scenario_id,
		"seed": int(current_case.get("seed", 0)),
		"deterministic": true,
		"suite_hash": str(plan.get("suite_hash", "")),
		"episode_return": total_reward / maxf(case_duration_seconds, 0.000001),
		"raw_episode_return": total_reward,
		"episode_return_per_second": total_reward / maxf(case_elapsed_seconds, 0.000001),
		"planned_duration_seconds": case_duration_seconds,
		"success": success,
		"pickup_lifted": pickup_lifted,
		"item_delivered": item_delivered,
		"crashed": not timed_out,
		"terminated": not timed_out,
		"truncated": timed_out,
		"distance_m": distance,
		"time_inside_radius_seconds": time_inside_radius_seconds,
		"termination_reason": reason,
		"elapsed_seconds": case_elapsed_seconds,
		"candidate_hash": candidate_hash,
		"evaluation_contract_hash": evaluation_contract_hash,
	})
	_begin_case(case_index + 1)


func _build_evaluation_floor() -> void:
	if is_instance_valid(evaluation_floor):
		return
	evaluation_floor = StaticBody3D.new()
	evaluation_floor.name = "FourLimbEvaluationFloor"
	evaluation_floor.collision_layer = 1
	evaluation_floor.collision_mask = 0
	evaluation_floor.position = world_offset + Vector3(0.0, -FLOOR_THICKNESS_M * 0.5, 0.0)
	evaluation_floor.add_to_group("training_ground")
	evaluation_floor.set_meta("grip_surface_tags", ["ground"])
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(maxf(arena_size.x, 40.0), FLOOR_THICKNESS_M, maxf(arena_size.z, 40.0))
	collision.shape = shape
	evaluation_floor.add_child(collision)
	add_child(evaluation_floor)


func _add_box_wall(center: Vector3, size: Vector3, yaw_radians: float) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.name = "FourLimbEvaluationWall%02d" % scenario_walls.size()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = center
	wall.rotation.y = yaw_radians
	wall.add_to_group("training_wall")
	# Match the live training-room wall contract. GenericGrip3D reads metadata rather than
	# group membership when deciding whether a surface is climbable.
	wall.set_meta("training_wall", true)
	wall.set_meta("grip_surface_tags", PackedStringArray(["climbable"]))
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	scenario_walls.append(wall)


func _build_pickup_item(position_world: Vector3) -> bool:
	evaluation_pickup_item = TrainingItem3D.new()
	evaluation_pickup_item.name = "FourLimbEvaluationPickupItem"
	evaluation_pickup_item.visible = false
	add_child(evaluation_pickup_item)
	if not evaluation_pickup_item.configure_from_definition(
		930000000 + candidate_id * 100 + case_index,
		PICKUP_ITEM_DEFINITION,
		Transform3D(Basis.IDENTITY, position_world)
	):
		last_error = "four-limb evaluator could not build its frozen pickup-item fixture"
		evaluation_pickup_item.queue_free()
		evaluation_pickup_item = null
		return false
	return true


func _build_delivery_destination(position_world: Vector3) -> void:
	evaluation_delivery_destination = TrainingItemDeliveryDestination3D.new()
	evaluation_delivery_destination.name = "FourLimbEvaluationDeliveryDestination"
	evaluation_delivery_destination.visible = false
	add_child(evaluation_delivery_destination)
	evaluation_delivery_destination.configure_destination(
		1,
		1,
		1.25,
		1.25,
		Transform3D(Basis.IDENTITY, position_world),
		Color("54e6b1")
	)


func _build_threat_turret(seed: int) -> bool:
	var threat_loadout: TurretLoadout = MLBodyPresetLibrary.stationary_turret_loadout()
	if threat_loadout == null or not threat_loadout.ensure_contract():
		last_error = "four-limb evaluator could not load the stationary threat-turret preset"
		return false
	var threat_runtime_loadout: TurretLoadout = (
		MLBodyPartContract.deep_duplicate_resource(threat_loadout) as TurretLoadout
	)
	if threat_runtime_loadout == null or not threat_runtime_loadout.ensure_contract():
		last_error = "four-limb evaluator could not duplicate the stationary threat-turret preset"
		return false
	evaluation_turret = TurretPhysicalBody3D.new()
	evaluation_turret.name = "FourLimbEvaluationThreatTurret"
	# _ready() validates the loadout, so the authored preset must be assigned before add_child().
	# The previous order created a body with a Nil loadout and then reset it, which explains the
	# loadout + maximum_health errors even when no live-room turret had been placed.
	evaluation_turret.loadout = threat_runtime_loadout
	evaluation_turret.auto_start_active = true
	evaluation_turret.training_invulnerable = true
	evaluation_turret.visible = false
	add_child(evaluation_turret)
	if not evaluation_turret.reset_body(
		Transform3D(Basis.IDENTITY, _world_spawn_position() + Vector3(7.0, 0.0, 3.0)),
		seed + 90001
	):
		last_error = "four-limb evaluator threat turret could not initialize its accepted body"
		evaluation_turret.queue_free()
		evaluation_turret = null
		return false
	evaluation_turret_adapter = TurretTrainingCombatantAdapter.new(
		evaluation_turret,
		910000000 + candidate_id * 100 + case_index,
		-9100 - group_id,
		0,
		2
	)
	entity_spatial_hash.register_entity(
		evaluation_turret_adapter.spatial_key(),
		evaluation_turret,
		evaluation_turret_adapter.entity_kind,
		evaluation_turret_adapter.entity_id,
		evaluation_turret_adapter.metadata()
	)
	var shot_callable: Callable = _on_evaluation_turret_shot_requested
	if not evaluation_turret.shot_requested.is_connected(shot_callable):
		evaluation_turret.shot_requested.connect(shot_callable)
	return true


func _register_limb_combatant() -> void:
	if not is_instance_valid(body):
		return
	if combat_adapter != null:
		entity_spatial_hash.unregister_entity(combat_adapter.spatial_key())
	combat_adapter = FourLimbTrainingCombatantAdapter.new(
		body,
		920000000 + candidate_id * 100 + case_index,
		group_id,
		0,
		1
	)
	entity_spatial_hash.register_entity(
		combat_adapter.spatial_key(),
		body,
		combat_adapter.entity_kind,
		combat_adapter.entity_id,
		combat_adapter.metadata()
	)


func _update_evaluation_turret_aim() -> void:
	if not is_instance_valid(evaluation_turret) or not is_instance_valid(body):
		return
	var direction_world: Vector3 = body.core_transform().origin - evaluation_turret.global_position
	if direction_world.length_squared() <= 0.000001:
		return
	var local_direction: Vector3 = evaluation_turret.global_basis.inverse() * direction_world.normalized()
	var horizontal: float = sqrt(local_direction.x * local_direction.x + local_direction.z * local_direction.z)
	evaluation_turret.yaw_angle_radians = atan2(-local_direction.x, -local_direction.z)
	evaluation_turret.pitch_angle_radians = clampf(
		atan2(local_direction.y, maxf(horizontal, 0.000001)),
		deg_to_rad(evaluation_turret.loadout.gun.minimum_pitch_degrees),
		deg_to_rad(evaluation_turret.loadout.gun.maximum_pitch_degrees)
	)
	evaluation_turret.yaw_velocity_radians_per_second = 0.0
	evaluation_turret.pitch_velocity_radians_per_second = 0.0
	evaluation_turret._apply_joint_transforms()
	evaluation_turret.submit_manual_controls(0.0, 0.0, 1.0)


func _on_evaluation_turret_shot_requested(request: Dictionary) -> void:
	if evaluation_turret_adapter == null:
		return
	var projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	add_child(projectile)
	if not projectile.configure(request, evaluation_turret_adapter, entity_spatial_hash, wall_spatial_hash):
		projectile.queue_free()
		return
	projectile.visible = false
	evaluation_projectiles.append(projectile)


func _reward_context(observation: Dictionary, combat_events: Dictionary) -> Dictionary:
	var objective: Dictionary = observation.get("objective", {})
	var pickup_item_valid: bool = is_instance_valid(evaluation_pickup_item)
	return {
		"action_change_norm": action_change_pending,
		"combat_events": combat_events,
		"turret_threat_probe": objective.get("turret_threat_probe", {}),
		"assigned_pickup_item_id": (
			evaluation_pickup_item.get_instance_id() if pickup_item_valid else 0
		),
		"pickup_item_reward_value": (
			evaluation_pickup_item.reward_value if pickup_item_valid else 0.0
		),
		"delivery_destination_present": bool(objective.get("delivery_destination_present", false)),
		"delivery_destination_group_id": maxi(
			RLTrainingMath.finite_int_or(objective.get("delivery_destination_group_id", 0), 0),
			0
		),
		"delivery_destination_stable_id": str(objective.get("delivery_destination_stable_id", "")),
		"delivery_destination_distance_m": maxf(
			RLTrainingMath.finite_float_or(objective.get("delivery_destination_distance_m", 0.0), 0.0),
			0.0
		),
		"delivery_item_held": bool(objective.get("delivery_item_held", false)),
		"delivery_item_accepted": bool(objective.get("delivery_item_accepted", false)),
		"delivery_item_inside": bool(objective.get("delivery_item_inside", false)),
		"delivery_item_instance_id": maxi(
			RLTrainingMath.finite_int_or(objective.get("delivery_item_instance_id", 0), 0),
			0
		),
		"delivery_item_reward_value": maxf(
			RLTrainingMath.finite_float_or(objective.get("delivery_item_reward_value", 0.0), 0.0),
			0.0
		),
		"delivery_approach_reward_scale": maxf(
			RLTrainingMath.finite_float_or(objective.get("delivery_approach_reward_scale", 1.0), 1.0),
			0.0
		),
		"delivery_completion_reward_scale": maxf(
			RLTrainingMath.finite_float_or(objective.get("delivery_completion_reward_scale", 1.0), 1.0),
			0.0
		),
	}


func _clear_case_environment() -> void:
	for projectile: TurretTrainingProjectile3D in evaluation_projectiles:
		if is_instance_valid(projectile):
			projectile.set_physics_process(false)
			projectile.queue_free()
	evaluation_projectiles.clear()
	if combat_adapter != null:
		entity_spatial_hash.unregister_entity(combat_adapter.spatial_key())
	combat_adapter = null
	if evaluation_turret_adapter != null:
		entity_spatial_hash.unregister_entity(evaluation_turret_adapter.spatial_key())
	evaluation_turret_adapter = null
	if is_instance_valid(evaluation_turret):
		evaluation_turret.active = false
		evaluation_turret.queue_free()
	evaluation_turret = null
	if is_instance_valid(evaluation_pickup_item):
		evaluation_pickup_item.set_simulation_active(false)
		evaluation_pickup_item.collision_layer = 0
		evaluation_pickup_item.collision_mask = 0
		evaluation_pickup_item.queue_free()
	evaluation_pickup_item = null
	if is_instance_valid(evaluation_delivery_destination):
		evaluation_delivery_destination.queue_free()
	evaluation_delivery_destination = null
	for wall: Node3D in scenario_walls:
		if is_instance_valid(wall):
			var collision_object: CollisionObject3D = wall as CollisionObject3D
			if collision_object != null:
				collision_object.collision_layer = 0
				collision_object.collision_mask = 0
			wall.queue_free()
	scenario_walls.clear()
	wall_spatial_hash.clear()


func _world_spawn_position() -> Vector3:
	return world_offset + local_spawn_position


func _outside_evaluation_arena(position_world: Vector3) -> bool:
	var local_position: Vector3 = position_world - world_offset
	if not local_position.is_finite():
		return true
	if local_position.y < -2.0:
		return true
	return (
		absf(local_position.x) > arena_size.x * 0.5
		or absf(local_position.z) > arena_size.z * 0.5
	)


func _target_distance_from_observation(observation: Dictionary) -> float:
	var body_state: Dictionary = observation.get("body", {})
	var objective: Dictionary = observation.get("objective", {})
	return FourLimbRewardDeck.target_goal_distance(body_state, objective)


static func _commands_finite(commands: PackedFloat64Array) -> bool:
	for value: float in commands:
		if not is_finite(value):
			return false
	return true


static func _command_change_norm(previous: PackedFloat64Array, current: PackedFloat64Array) -> float:
	if (
		previous.size() != FourLimbMLAction.ACTION_COUNT
		or current.size() != FourLimbMLAction.ACTION_COUNT
	):
		return 0.0
	var sum_value: float = 0.0
	var joint_sample_count: int = 0
	for limb_index in range(FourLimbMLAction.LIMB_COUNT):
		for joint_axis in range(FourLimbMLAction.JOINT_AXES_PER_LIMB):
			var action_index: int = FourLimbMLAction.action_offset(limb_index, joint_axis)
			var difference: float = current[action_index] - previous[action_index]
			sum_value += difference * difference
			joint_sample_count += 1
	# Match live training exactly: this is a joint-target smoothness cost, not a grip-toggle cost.
	return sqrt(sum_value / float(maxi(joint_sample_count, 1)))


static func _vector3_from_record(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var values: Array = value as Array
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return fallback


func _fail_start(reason: String) -> bool:
	_fail(reason)
	return false


func _fail(reason: String) -> void:
	if status == "failed" or status == "completed":
		return
	last_error = reason
	status = "failed"
	failed.emit(group_id, candidate_id, reason)
