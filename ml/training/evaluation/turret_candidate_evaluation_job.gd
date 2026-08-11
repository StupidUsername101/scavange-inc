class_name TurretCandidateEvaluationJob
extends Node3D

signal completed(group_id: int, candidate_id: int, records: Array[Dictionary])
signal failed(group_id: int, candidate_id: int, reason: String)

#######################################################
# Hidden fixed-seed evaluator for stationary turret PPO policies. It builds evaluator-owned
# targets and occluders, uses the normal target sensor/projectile/reward path, and never adds
# samples to the live trainer.
#######################################################

const DECISION_INTERVAL_SECONDS = 0.05
const EVALUATION_WORLD_SPACING_M = 180.0
const EVALUATION_WORLD_BASE = Vector3(32000.0, 0.0, 32000.0)
const TURRET_TEAM_ID = 2
const TARGET_TEAM_ID = 1

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
var loadout: TurretLoadout
var reward_deck: TurretRewardDeck = TurretRewardDeck.new()
var runtime_model: TurretPPOModel = TurretPPOModel.new()
var turret: TurretPhysicalBody3D
var adapter: TurretMLBodyAdapter
var turret_combat_adapter: TurretTrainingCombatantAdapter

var wall_spatial_hash: DroneTrainingWallSpatialHash = DroneTrainingWallSpatialHash.new()
var entity_spatial_hash: ServerSpatialHash3D = ServerSpatialHash3D.new(6.0)
var scenario_walls: Array[Node3D] = []
var target_nodes: Array[Node3D] = []
var target_adapters: Array[TrainingEvaluationCombatantAdapter] = []
var projectiles: Array[TurretTrainingProjectile3D] = []

var records: Array[Dictionary] = []
var current_case: Dictionary = {}
var case_index: int = -1
var case_elapsed_seconds: float = 0.0
var case_duration_seconds: float = 0.0
var decision_elapsed_seconds: float = 0.0
var interval_elapsed_seconds: float = 0.0
var total_reward: float = 0.0
var time_precisely_aimed_seconds: float = 0.0
var previous_observation: Dictionary = {}
var previous_commands: PackedFloat64Array = TurretMLAction.neutral_commands()
var reward_state: Dictionary = {}
var latest_target_probe: Dictionary = {}
var world_offset: Vector3 = Vector3.ZERO
var fallback_target_position: Vector3 = Vector3.ZERO
var scenario_phase: float = 0.0
var total_hits: int = 0
var total_bad_shots: int = 0


static func supports_scenario_id(scenario_id: String) -> bool:
	return scenario_id in [
		"stationary_target",
		"crossing_target",
		"elevated_target",
		"occluded_target",
		"mixed_drone_limb_targets",
	]


func configure(
	new_group_id: int,
	candidate: Dictionary,
	checkpoint: Dictionary,
	fallback_loadout: TurretLoadout,
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
	if not RLEvaluationContract.is_valid(evaluation_contract, "turret"):
		last_error = "candidate has no valid frozen turret evaluation contract"
		return false
	if evaluation_contract_hash != str(evaluation_contract.get("contract_hash", "")):
		last_error = "candidate evaluation contract hash is inconsistent"
		return false
	if str(plan.get("evaluation_contract_hash", "")) != evaluation_contract_hash:
		last_error = "candidate evaluation plan does not match its frozen environment contract"
		return false
	if (
		not RLDeterministicEvaluationSuite.is_valid_plan(plan, "turret")
		or candidate_checkpoint.is_empty()
	):
		last_error = "candidate evaluation plan or checkpoint is empty"
		return false
	var environment: Dictionary = evaluation_contract.get("environment", {})
	var loadout_record: Dictionary = environment.get(
		"hardware",
		candidate_checkpoint.get("turret_loadout", {})
	)
	if not loadout_record.is_empty():
		loadout = TurretLoadout.from_dictionary(loadout_record)
	elif fallback_loadout != null:
		loadout = MLBodyPartContract.deep_duplicate_resource(fallback_loadout) as TurretLoadout
	if loadout == null or not loadout.ensure_contract():
		last_error = "candidate turret loadout is missing or incomplete"
		return false
	var expected_signature: String = str(candidate_checkpoint.get(
		"hardware_signature",
		loadout.hardware_signature()
	))
	if not runtime_model.load_checkpoint(candidate_checkpoint, expected_signature):
		last_error = "frozen turret candidate could not load its runtime policy"
		return false
	var reward_cards: Dictionary = environment.get(
		"reward_cards",
		candidate_checkpoint.get("reward_cards", {})
	)
	if not reward_cards.is_empty():
		reward_deck.load_configuration(reward_cards)
	world_offset = EVALUATION_WORLD_BASE + Vector3(
		float(maxi(group_id, 0)) * EVALUATION_WORLD_SPACING_M,
		0.0,
		0.0
	)
	fallback_target_position = world_offset + Vector3(0.0, 1.6, -10.0)
	return true


func begin() -> bool:
	var runtime_loadout: TurretLoadout = (
		MLBodyPartContract.deep_duplicate_resource(loadout) as TurretLoadout
	)
	if runtime_loadout == null or not runtime_loadout.ensure_contract():
		return _fail_start("hidden turret evaluator could not duplicate its accepted body")
	turret = TurretPhysicalBody3D.new()
	turret.name = "TurretCandidateEvaluator"
	turret.loadout = runtime_loadout
	turret.auto_start_active = true
	turret.training_invulnerable = true
	turret.visible = false
	add_child(turret)
	adapter = TurretMLBodyAdapter.new(turret)
	turret_combat_adapter = TurretTrainingCombatantAdapter.new(
		turret,
		930000000 + candidate_id,
		group_id,
		0,
		TURRET_TEAM_ID
	)
	entity_spatial_hash.register_entity(
		turret_combat_adapter.spatial_key(),
		turret,
		turret_combat_adapter.entity_kind,
		turret_combat_adapter.entity_id,
		turret_combat_adapter.metadata()
	)
	var shot_callable: Callable = _on_shot_requested
	if not turret.shot_requested.is_connected(shot_callable):
		turret.shot_requested.connect(shot_callable)
	status = "running"
	return _begin_case(0)


func tick(
	delta: float,
	_space_state: PhysicsDirectSpaceState3D,
	_room_wall_spatial_hash: DroneTrainingWallSpatialHash
) -> void:
	if status != "running" or not is_instance_valid(turret) or adapter == null:
		return
	var safe_delta: float = maxf(delta, 0.0)
	case_elapsed_seconds += safe_delta
	decision_elapsed_seconds += safe_delta
	interval_elapsed_seconds += safe_delta
	_update_targets(safe_delta)
	entity_spatial_hash.refresh_all()
	if not turret.is_body_alive():
		# The body can still expose a valid final snapshot after a normal destroyed flag. Settle any
		# held-action reward if possible, but do not turn a genuine terminal into an evaluator error.
		_cancel_case_projectiles(true)
		_settle_pending_reward()
		_finish_case("destroyed", false)
		return
	if case_elapsed_seconds >= case_duration_seconds:
		_cancel_case_projectiles(true)
		if not _settle_pending_reward():
			_fail("hidden turret evaluator could not settle its timeout observation")
			return
		_finish_case("timeout", true)
		return
	if decision_elapsed_seconds < DECISION_INTERVAL_SECONDS:
		return
	var reward_delta: float = maxf(interval_elapsed_seconds, 0.000001)
	decision_elapsed_seconds = fmod(decision_elapsed_seconds, DECISION_INTERVAL_SECONDS)
	latest_target_probe = TurretTrainingTargetSensor.acquire(
		turret,
		turret_combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		fallback_target_position,
		turret.loadout.gun.maximum_range_m
	)
	var combat_events: Dictionary = turret_combat_adapter.consume_combat_events()
	adapter.set_context(
		latest_target_probe,
		case_elapsed_seconds / maxf(case_duration_seconds, 0.1),
		previous_commands,
		combat_events
	)
	var observation: Dictionary = adapter.capture_observation()
	if observation.is_empty():
		_fail("frozen turret candidate produced an invalid observation")
		return
	var weapon_events: Dictionary = turret.consume_weapon_events()
	total_hits += maxi(int(weapon_events.get("hits", 0)), 0)
	total_bad_shots += maxi(int(weapon_events.get("bad_shots", 0)), 0)
	var reward_result: Dictionary = reward_deck.step_reward(
		previous_observation if not previous_observation.is_empty() else observation,
		observation,
		reward_delta,
		reward_state,
		weapon_events
	)
	total_reward += float(reward_result.get("total", 0.0))
	interval_elapsed_seconds = 0.0
	var observed_target: Dictionary = observation.get("target", {})
	if TurretTrainingTargetSensor.is_precision_tracking_state(
		observed_target,
		TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
	):
		time_precisely_aimed_seconds += reward_delta
	var action: Dictionary = runtime_model.predict_action(observation)
	var commands: PackedFloat64Array = TurretMLAction.packed_commands(action)
	if commands.size() != TurretMLAction.ACTION_COUNT or not RLTrainingMath.packed_all_finite(commands):
		_fail("frozen turret candidate produced an invalid action")
		return
	if not adapter.apply_commands(commands):
		_fail("hidden turret evaluator rejected the candidate action")
		return
	previous_commands = commands
	previous_observation = observation


func _settle_pending_reward() -> bool:
	if interval_elapsed_seconds <= 0.0:
		return true
	latest_target_probe = TurretTrainingTargetSensor.acquire(
		turret,
		turret_combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		fallback_target_position,
		turret.loadout.gun.maximum_range_m
	)
	var combat_events: Dictionary = turret_combat_adapter.consume_combat_events()
	adapter.set_context(
		latest_target_probe,
		case_elapsed_seconds / maxf(case_duration_seconds, 0.1),
		previous_commands,
		combat_events
	)
	var observation: Dictionary = adapter.capture_observation()
	if observation.is_empty():
		return false
	var weapon_events: Dictionary = turret.consume_weapon_events()
	total_hits += maxi(int(weapon_events.get("hits", 0)), 0)
	total_bad_shots += maxi(int(weapon_events.get("bad_shots", 0)), 0)
	var reward_delta: float = maxf(interval_elapsed_seconds, 0.000001)
	var reward_result: Dictionary = reward_deck.step_reward(
		previous_observation if not previous_observation.is_empty() else observation,
		observation,
		reward_delta,
		reward_state,
		weapon_events
	)
	total_reward += float(reward_result.get("total", 0.0))
	var observed_target: Dictionary = observation.get("target", {})
	if TurretTrainingTargetSensor.is_precision_tracking_state(
		observed_target,
		TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
	):
		time_precisely_aimed_seconds += reward_delta
	previous_observation = observation
	interval_elapsed_seconds = 0.0
	return true


func restart_for_environment(new_environment_revision: int) -> void:
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
	if turret_combat_adapter != null:
		entity_spatial_hash.unregister_entity(turret_combat_adapter.spatial_key())
	turret_combat_adapter = null
	if is_instance_valid(turret):
		turret.active = false
		turret.queue_free()
	turret = null
	adapter = null


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
	decision_elapsed_seconds = 0.0
	interval_elapsed_seconds = 0.0
	total_reward = 0.0
	time_precisely_aimed_seconds = 0.0
	previous_observation.clear()
	previous_commands = TurretMLAction.neutral_commands()
	reward_state.clear()
	latest_target_probe.clear()
	total_hits = 0
	total_bad_shots = 0
	var scenario_id: String = str(current_case.get("scenario_id", ""))
	var seed: int = int(current_case.get("seed", 0))
	scenario_phase = deg_to_rad(float(posmod(seed, 360)))
	if not _build_case_environment(scenario_id, seed):
		return _fail_start("unsupported deterministic turret scenario: %s" % scenario_id)
	if not turret.reset_body(Transform3D(Basis.IDENTITY, world_offset), seed):
		return _fail_start("hidden turret evaluator could not reset its accepted body")
	entity_spatial_hash.refresh_all()
	_update_targets(0.0)
	latest_target_probe = TurretTrainingTargetSensor.acquire(
		turret,
		turret_combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		fallback_target_position,
		turret.loadout.gun.maximum_range_m
	)
	adapter.set_context(latest_target_probe, 0.0, previous_commands, {})
	var initial_observation: Dictionary = adapter.capture_observation()
	if initial_observation.is_empty():
		return _fail_start("hidden turret evaluator produced an invalid initial observation")
	reward_state = reward_deck.reset_state(initial_observation)
	previous_observation = initial_observation
	var action: Dictionary = runtime_model.predict_action(initial_observation)
	var commands: PackedFloat64Array = TurretMLAction.packed_commands(action)
	if commands.size() != TurretMLAction.ACTION_COUNT or not RLTrainingMath.packed_all_finite(commands):
		return _fail_start("frozen turret candidate produced an invalid initial action")
	if not adapter.apply_commands(commands):
		return _fail_start("hidden turret evaluator rejected the initial candidate action")
	previous_commands = commands
	return true


func _build_case_environment(scenario_id: String, seed: int) -> bool:
	if not supports_scenario_id(scenario_id):
		return false
	match scenario_id:
		"stationary_target":
			_add_target(&"drone", world_offset + Vector3(0.0, 1.6, -12.0), 0.55, 0)
		"crossing_target":
			_add_target(&"drone", world_offset + Vector3(-6.0, 1.8, -13.0), 0.55, 0)
		"elevated_target":
			_add_target(&"drone", world_offset + Vector3(1.5, 6.5, -14.0), 0.55, 0)
		"occluded_target":
			_add_target(&"drone", world_offset + Vector3(0.0, 1.7, -14.0), 0.55, 0)
			_add_wall(world_offset + Vector3(0.0, 2.0, -7.0), Vector3(5.0, 4.0, 0.8))
		"mixed_drone_limb_targets":
			_add_target(&"drone", world_offset + Vector3(-4.0, 2.0, -11.0), 0.55, 0)
			_add_target(&"four_limb", world_offset + Vector3(5.0, 0.8, -14.0), 0.75, 1)
		_:
			return false
	wall_spatial_hash.rebuild(scenario_walls)
	entity_spatial_hash.refresh_all()
	return true


func _add_target(
	kind: StringName,
	position_world: Vector3,
	radius_m: float,
	index: int
) -> void:
	var target_node: Node3D = Node3D.new()
	target_node.name = "TurretEvaluationTarget%02d" % index
	target_node.position = position_world
	add_child(target_node)
	target_nodes.append(target_node)
	var target_adapter: TrainingEvaluationCombatantAdapter = TrainingEvaluationCombatantAdapter.new(
		target_node,
		kind,
		940000000 + candidate_id * 100 + case_index * 10 + index,
		-9400 - group_id,
		index,
		TARGET_TEAM_ID,
		radius_m
	)
	target_adapters.append(target_adapter)
	entity_spatial_hash.register_entity(
		target_adapter.spatial_key(),
		target_node,
		target_adapter.entity_kind,
		target_adapter.entity_id,
		target_adapter.metadata()
	)


func _update_targets(_delta: float) -> void:
	var scenario_id: String = str(current_case.get("scenario_id", ""))
	if target_adapters.is_empty():
		return
	match scenario_id:
		"crossing_target":
			var omega: float = 0.65
			var phase: float = scenario_phase + case_elapsed_seconds * omega
			var position: Vector3 = world_offset + Vector3(sin(phase) * 6.0, 1.8, -13.0)
			var velocity: Vector3 = Vector3(cos(phase) * 6.0 * omega, 0.0, 0.0)
			target_adapters[0].update_state(position, velocity)
		"mixed_drone_limb_targets":
			var omega: float = 0.45
			var phase: float = scenario_phase + case_elapsed_seconds * omega
			var drone_position: Vector3 = world_offset + Vector3(-3.0 + sin(phase) * 2.0, 2.0, -10.0)
			var drone_velocity: Vector3 = Vector3(cos(phase) * 2.0 * omega, 0.0, 0.0)
			target_adapters[0].update_state(drone_position, drone_velocity)
			if target_adapters.size() > 1:
				var limb_position: Vector3 = world_offset + Vector3(4.5 + cos(phase) * 1.5, 0.8, -13.0)
				var limb_velocity: Vector3 = Vector3(-sin(phase) * 1.5 * omega, 0.0, 0.0)
				target_adapters[1].update_state(limb_position, limb_velocity)
		_:
			pass


func _add_wall(center: Vector3, size: Vector3) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.name = "TurretEvaluationOccluder"
	wall.position = center
	wall.add_to_group("training_wall")
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	scenario_walls.append(wall)


func _on_shot_requested(request: Dictionary) -> void:
	if turret_combat_adapter == null:
		return
	var exact_probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		turret_combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		fallback_target_position,
		turret.loadout.gun.maximum_range_m
	)
	turret.notify_shot_viability(TurretTrainingTargetSensor.is_viable_shot(
		turret,
		exact_probe,
		TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
	))
	var projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	add_child(projectile)
	if not projectile.configure(request, turret_combat_adapter, entity_spatial_hash, wall_spatial_hash):
		projectile.queue_free()
		return
	projectile.visible = false
	projectiles.append(projectile)
	if not projectile.resolved.is_connected(_on_projectile_resolved):
		projectile.resolved.connect(_on_projectile_resolved)


func _on_projectile_resolved(
	projectile: TurretTrainingProjectile3D,
	_hit: bool,
	_target: TrainingCombatantAdapter,
	_damage: float
) -> void:
	projectiles.erase(projectile)


func _finish_case(reason: String, timed_out: bool) -> void:
	if status != "running":
		return
	var terminal: Dictionary = reward_deck.terminal_reward(
		reward_state,
		"" if timed_out else reason,
		timed_out
	)
	total_reward += float(terminal.get("total", 0.0))
	var distance: float = float(latest_target_probe.get("distance_m", 0.0))
	records.append({
		"scenario_id": str(current_case.get("scenario_id", "")),
		"seed": int(current_case.get("seed", 0)),
		"deterministic": true,
		"suite_hash": str(plan.get("suite_hash", "")),
		"episode_return": total_reward / maxf(case_duration_seconds, 0.000001),
		"raw_episode_return": total_reward,
		"episode_return_per_second": total_reward / maxf(case_elapsed_seconds, 0.000001),
		"planned_duration_seconds": case_duration_seconds,
		"success": _case_success(),
		"crashed": not timed_out,
		"terminated": not timed_out,
		"truncated": timed_out,
		"distance_m": distance,
		"time_inside_radius_seconds": time_precisely_aimed_seconds,
		"hit_count": total_hits,
		"bad_shot_count": total_bad_shots,
		"termination_reason": reason,
		"elapsed_seconds": case_elapsed_seconds,
		"candidate_hash": candidate_hash,
		"evaluation_contract_hash": evaluation_contract_hash,
	})
	_begin_case(case_index + 1)


func _case_success() -> bool:
	if str(current_case.get("scenario_id", "")) == "occluded_target":
		# The correct behavior for a target fully hidden by the evaluator wall is disciplined
		# withholding of fire. The old generic success rule made this case impossible to pass.
		return total_hits == 0 and total_bad_shots == 0
	return total_hits > 0 or time_precisely_aimed_seconds >= 1.0


func _cancel_case_projectiles(count_as_misses: bool) -> void:
	for projectile: TurretTrainingProjectile3D in projectiles:
		if not is_instance_valid(projectile):
			continue
		if count_as_misses:
			projectile.cancel_as_miss()
		else:
			projectile.cancel_without_reward()
	projectiles.clear()


func _clear_case_environment() -> void:
	_cancel_case_projectiles(false)
	for target_adapter: TrainingEvaluationCombatantAdapter in target_adapters:
		if target_adapter != null:
			entity_spatial_hash.unregister_entity(target_adapter.spatial_key())
	target_adapters.clear()
	for target_node: Node3D in target_nodes:
		if is_instance_valid(target_node):
			target_node.queue_free()
	target_nodes.clear()
	for wall: Node3D in scenario_walls:
		if is_instance_valid(wall):
			var collision_object: CollisionObject3D = wall as CollisionObject3D
			if collision_object != null:
				collision_object.collision_layer = 0
				collision_object.collision_mask = 0
			wall.queue_free()
	scenario_walls.clear()
	wall_spatial_hash.clear()


func _fail_start(reason: String) -> bool:
	_fail(reason)
	return false


func _fail(reason: String) -> void:
	if status == "failed" or status == "completed":
		return
	last_error = reason
	status = "failed"
	failed.emit(group_id, candidate_id, reason)
