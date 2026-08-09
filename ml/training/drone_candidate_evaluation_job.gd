class_name DroneCandidateEvaluationJob
extends Node3D

#######################################################
# Runs one frozen drone candidate through the deterministic fixed-seed suite without
# stopping training. The job owns a hidden physics drone and never feeds transitions back
# into the learner. A paused training group may therefore finish its pending evaluation.
#######################################################

signal completed(group_id: int, candidate_id: int, records: Array[Dictionary])
signal failed(group_id: int, candidate_id: int, reason: String)

const DRONE_SCENE = preload("res://scenes/server/server_drone.tscn")
const LOADOUT_CONFIG = preload("res://ml/training/drone_training_loadout_config.gd")
const SENSOR_INTERVAL_SECONDS = 0.05
const QUAD_PROPELLER_COUNT = 4
const TRAINING_CONTACTS_REPORTED = 12
const EVALUATION_WORLD_COLLISION_LAYER = 1 << 19

var group_id: int = -1
var candidate_id: int = -1
var candidate_hash: String = ""
var plan: Dictionary = {}
var target_handler_configuration: Dictionary = {}
var reward_cards: Dictionary = {}
var base_loadout: DroneLoadout
var spawn_position: Vector3 = Vector3.ZERO
var arena_size: Vector3 = Vector3(100.0, 8.0, 100.0)
var collision_layer_value: int = 1 << 1
var collision_mask_value: int = 1
var unlimited_battery: bool = true
var environment_revision: int = 0
var evaluation_contract: Dictionary = {}
var evaluation_contract_hash: String = ""
var expected_body_runtime_contract: Dictionary = {}

var drone: ServerDrone
var runtime_model: DroneMLModel
var episode: DroneTrainingEpisode
var target_handler: TrainingTargetHandler
var target_context: Dictionary = {}
var current_case: Dictionary = {}
var records: Array[Dictionary] = []
var case_index: int = -1
var current_case_duration_seconds: float = 0.0
var sensor_elapsed_seconds: float = SENSOR_INTERVAL_SECONDS
var obstacle_probe: Dictionary = {}
var current_target: Dictionary = {}
var empty_threat_probe: Dictionary = TrainingTurretThreatSensor.empty_probe()
var scenario_wall_spatial_hash: DroneTrainingWallSpatialHash = DroneTrainingWallSpatialHash.new()
var scenario_walls: Array[Node3D] = []
var evaluation_floor: StaticBody3D
var scenario_entity_spatial_hash: ServerSpatialHash3D = ServerSpatialHash3D.new(6.0)
var drone_combat_adapter: DroneTrainingCombatantAdapter
var evaluation_turret: TurretPhysicalBody3D
var evaluation_turret_adapter: TurretTrainingCombatantAdapter
var evaluation_projectiles: Array[TurretTrainingProjectile3D] = []
var status: String = "starting"
var restart_count: int = 0
var last_error: String = ""


static func supports_scenario_id(scenario_id: String) -> bool:
	return (
		scenario_id.begins_with("routed_target__")
		or scenario_id in [
			"open_static_target",
			"sparse_walls",
			"corridor",
			"moving_target",
			"degraded_propeller",
			"turret_exposure",
		]
	)


func configure(
	new_group_id: int,
	candidate: Dictionary,
	candidate_checkpoint: Dictionary,
	loadout: DroneLoadout,
	target_configuration: Dictionary,
	candidate_reward_cards: Dictionary,
	spawn_position_world: Vector3,
	arena_size_world: Vector3,
	collision_layer: int,
	collision_mask: int,
	use_unlimited_battery: bool,
	initial_environment_revision: int
) -> bool:
	group_id = new_group_id
	candidate_id = RLTrainingMath.finite_int_or(candidate.get("candidate_id", -1), -1)
	candidate_hash = str(candidate.get("candidate_hash", ""))
	# pending_evaluation_candidate() already returned a detached snapshot, so this job may own
	# its plan directly instead of recursively copying 30 case dictionaries a second time.
	plan = candidate.get("evaluation_plan", {}) as Dictionary
	evaluation_contract = (candidate.get("evaluation_contract", {}) as Dictionary).duplicate(true)
	evaluation_contract_hash = str(candidate.get("evaluation_contract_hash", ""))
	if (
		not RLEvaluationContract.is_valid(evaluation_contract, "drone")
		or evaluation_contract_hash != str(evaluation_contract.get("contract_hash", ""))
	):
		last_error = "candidate has no valid frozen drone evaluation contract"
		return false
	var environment: Dictionary = evaluation_contract.get("environment", {})
	target_handler_configuration = (environment.get("target_handler", target_configuration) as Dictionary).duplicate(true)
	reward_cards = (environment.get("reward_cards", candidate_reward_cards) as Dictionary).duplicate(true)
	var hardware_record: Dictionary = environment.get("hardware", {})
	base_loadout = LOADOUT_CONFIG.from_record(hardware_record) if not hardware_record.is_empty() else LOADOUT_CONFIG.duplicate_loadout(loadout)
	spawn_position = _vector3_from_record(environment.get("spawn_position_m", []), spawn_position_world)
	arena_size = _vector3_from_record(environment.get("arena_size_m", []), arena_size_world)
	collision_layer_value = collision_layer
	# Candidate physics are isolated from live editable walls. The evaluator constructs its
	# own floor and scenario geometry on a private layer, so room edits cannot redefine Best.
	collision_mask_value = EVALUATION_WORLD_COLLISION_LAYER
	unlimited_battery = bool(environment.get("unlimited_episode_battery", use_unlimited_battery))
	environment_revision = initial_environment_revision
	if candidate_id < 0 or candidate_hash.is_empty():
		last_error = "candidate metadata is incomplete"
		return false
	if plan.is_empty() or not RLDeterministicEvaluationSuite.is_valid_plan(plan, "drone"):
		last_error = "candidate has no deterministic evaluation plan"
		return false
	if str(plan.get("evaluation_contract_hash", "")) != evaluation_contract_hash:
		last_error = "candidate evaluation plan does not match its frozen environment contract"
		return false
	if candidate_checkpoint.is_empty():
		last_error = "candidate checkpoint is empty"
		return false
	if base_loadout == null:
		last_error = "candidate group has no drone loadout"
		return false
	# Load the immutable runtime policy, then let the large checkpoint dictionary fall out of
	# scope. The evaluator only needs the runtime weights and must not retain a second network.
	var runtime_contract: Dictionary = DroneTrainingAlgorithmCatalog.runtime_contract(candidate_checkpoint)
	expected_body_runtime_contract = runtime_contract.duplicate(true)
	var frozen_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(base_loadout)
	if not DroneMLBodyInterfaceFactory.matches_runtime_contract(
		frozen_manifest,
		expected_body_runtime_contract
	):
		last_error = "candidate frozen hardware does not match the accepted policy body interface"
		return false
	runtime_model = DroneTrainingAlgorithmCatalog.create_runtime_model(candidate_checkpoint)
	if runtime_model == null:
		last_error = "candidate runtime model could not load its frozen checkpoint"
		return false
	return true


func begin() -> bool:
	if runtime_model == null or base_loadout == null:
		return false
	drone = DRONE_SCENE.instantiate() as ServerDrone
	if drone == null:
		return _fail_start("could not instantiate the hidden evaluation drone")
	drone.name = "CandidateEvaluationGroup%02dCandidate%04d" % [group_id, candidate_id]
	drone.network_visible = false
	drone.position = spawn_position
	drone.collision_layer = collision_layer_value
	drone.collision_mask = collision_mask_value
	drone.contact_monitor = true
	drone.max_contacts_reported = TRAINING_CONTACTS_REPORTED
	drone.starts_activated = false
	drone.loadout = LOADOUT_CONFIG.duplicate_loadout(base_loadout)
	add_child(drone)
	_build_evaluation_floor()
	# Evaluation is intentionally invisible: it consumes physics/inference only and does not
	# add meshes, cameras, audio, cards, or multiplayer snapshots to the room.
	drone.visible = false
	drone.set_ml_training_performance_mode(true)
	drone.set_ml_episode_unlimited_battery(unlimited_battery)
	if drone.propeller_slots.size() != QUAD_PROPELLER_COUNT:
		return _fail_start("candidate evaluator requires exactly four propeller slots")
	if not DroneMLBodyInterfaceFactory.matches_runtime_contract(
		drone.model_body_interface(),
		expected_body_runtime_contract
	):
		return _fail_start("candidate evaluator body loadout does not match the accepted policy interface")
	status = "running"
	return _begin_case(0)


func tick(
	delta: float,
	space_state: PhysicsDirectSpaceState3D,
	_room_wall_spatial_hash: DroneTrainingWallSpatialHash
) -> void:
	if status != "running" or not is_instance_valid(drone) or episode == null:
		return
	var safe_delta: float = maxf(delta, 0.0)
	target_context["reference_position_world"] = drone.global_position
	if target_handler != null:
		target_handler.tick(safe_delta, target_context)
		current_target = target_handler.resolved_target(
			spawn_position + Vector3.UP * 2.0,
			0.75
		)
	var target_position: Vector3 = current_target.get(
		"position_world",
		spawn_position + Vector3.UP * 2.0
	)
	var target_velocity: Vector3 = current_target.get("velocity_world", Vector3.ZERO)
	var target_radius: float = maxf(float(current_target.get("radius_m", 0.75)), 0.05)

	sensor_elapsed_seconds += safe_delta
	scenario_entity_spatial_hash.refresh_all()
	_update_evaluation_turret_aim()
	var threat_probe: Dictionary = empty_threat_probe
	var combat_events: Dictionary = TrainingCombatantAdapter.EMPTY_COMBAT_EVENTS
	if drone_combat_adapter != null:
		threat_probe = TrainingTurretThreatSensor.acquire(
			drone_combat_adapter,
			scenario_entity_spatial_hash,
			scenario_wall_spatial_hash
		)
		combat_events = drone_combat_adapter.consume_combat_events()
	if sensor_elapsed_seconds >= SENSOR_INTERVAL_SECONDS:
		obstacle_probe = DroneTrainingObstacleSensor.sample(
			drone,
			space_state,
			target_position,
			collision_mask_value,
			scenario_wall_spatial_hash,
			arena_size
		)
		sensor_elapsed_seconds = fmod(
			sensor_elapsed_seconds,
			SENSOR_INTERVAL_SECONDS
		)
	else:
		obstacle_probe = DroneTrainingObstacleSensor.refresh_motion(drone, obstacle_probe)

	drone.set_ml_objective({
		"target_position_world": target_position,
		"target_velocity_world": target_velocity,
		"target_hover_radius_m": target_radius,
		"episode_progress": clampf(
			episode.elapsed_seconds / maxf(current_case_duration_seconds, 0.1),
			0.0,
			1.0
		),
		"obstacle_probe": obstacle_probe,
		"turret_threat_probe": threat_probe,
	})
	var reward: Dictionary = episode.step(
		drone,
		target_position,
		target_radius,
		arena_size,
		safe_delta,
		obstacle_probe,
		combat_events,
		threat_probe
	)
	if episode.finished:
		_record_case(reward)
		_begin_case(case_index + 1)


func restart_for_environment(new_environment_revision: int) -> void:
	# The evaluator owns a frozen scenario/target/hardware contract. Live room wall edits must
	# not redefine or restart an in-flight benchmark. Keep the revision only for diagnostics.
	environment_revision = new_environment_revision


func progress() -> Dictionary:
	var cases: Array = plan.get("cases", []) as Array
	var completed_count: int = records.size()
	var current_number: int = mini(case_index + 1, cases.size()) if case_index >= 0 else 0
	return {
		"status": status,
		"candidate_id": candidate_id,
		"completed_cases": completed_count,
		"total_cases": cases.size(),
		"current_case_number": current_number,
		"scenario_id": str(current_case.get("scenario_id", "")),
		"case_elapsed_seconds": episode.elapsed_seconds if episode != null else 0.0,
		"case_duration_seconds": current_case_duration_seconds,
		"restart_count": restart_count,
		"last_error": last_error,
	}


func shutdown() -> void:
	status = "cancelled"
	_clear_case_environment()
	if is_instance_valid(drone):
		drone.set_activated(false)
		drone.queue_free()
	drone = null
	if is_instance_valid(evaluation_floor):
		evaluation_floor.queue_free()
	evaluation_floor = null


func _begin_case(next_case_index: int) -> bool:
	var cases: Array = plan.get("cases", []) as Array
	if next_case_index >= cases.size():
		status = "complete"
		if is_instance_valid(drone):
			drone.set_activated(false)
			drone.freeze = true
		completed.emit(group_id, candidate_id, records.duplicate(true))
		return true
	if next_case_index < 0 or not (cases[next_case_index] is Dictionary):
		return _fail_start("evaluation plan contains an invalid case")
	case_index = next_case_index
	current_case = (cases[case_index] as Dictionary).duplicate(true)
	current_case_duration_seconds = maxf(
		float(current_case.get(
			"duration_seconds",
			RLDeterministicEvaluationSuite.DEFAULT_CASE_DURATION_SECONDS
		)),
		0.5
	)
	var case_seed: int = int(current_case.get("seed", 0))
	var scenario_id: String = str(current_case.get("scenario_id", ""))
	_restore_full_loadout()
	_clear_case_environment()
	if not _build_case_environment(scenario_id, case_seed):
		return _fail_start("unsupported deterministic evaluation scenario: %s" % scenario_id)
	_configure_case_target(scenario_id, case_seed)
	if target_handler == null:
		return _fail_start("evaluation target handler could not be created")
	target_context.clear()
	target_context["group_id"] = group_id
	target_context["reference_position_world"] = spawn_position
	target_context["arena_size"] = arena_size
	target_handler.reset(case_seed, target_context)
	current_target = target_handler.resolved_target(
		spawn_position + Vector3.UP * 2.0,
		0.75
	)
	var spawn_transform: Transform3D = Transform3D(Basis.IDENTITY, spawn_position)
	if not drone.reset_ml_episode(spawn_transform, case_seed, runtime_model):
		return _fail_start("hidden evaluation drone could not reset with the frozen policy")
	_register_evaluation_drone_combatant()
	if _scenario_is_degraded_propeller(scenario_id):
		var degraded_slot: int = posmod(case_seed, QUAD_PROPELLER_COUNT)
		drone.remove_propeller(degraded_slot)
	obstacle_probe = DroneTrainingObstacleSensor.clear_probe()
	obstacle_probe["ground_clearance_m"] = spawn_position.y
	sensor_elapsed_seconds = SENSOR_INTERVAL_SECONDS
	var initial_target_position: Vector3 = current_target.get(
		"position_world",
		spawn_position + Vector3.UP * 2.0
	)
	var initial_radius: float = maxf(float(current_target.get("radius_m", 0.75)), 0.05)
	episode = DroneTrainingEpisode.new()
	episode.start(
		spawn_position,
		initial_target_position,
		initial_radius,
		current_case_duration_seconds,
		case_index + 1,
		case_seed,
		reward_cards
	)
	var initial_threat_probe: Dictionary = (
		TrainingTurretThreatSensor.acquire(
			drone_combat_adapter,
			scenario_entity_spatial_hash,
			scenario_wall_spatial_hash
		)
		if drone_combat_adapter != null
		else empty_threat_probe
	)
	drone.set_ml_objective({
		"target_position_world": initial_target_position,
		"target_velocity_world": current_target.get("velocity_world", Vector3.ZERO),
		"target_hover_radius_m": initial_radius,
		"episode_progress": 0.0,
		"obstacle_probe": obstacle_probe,
		"turret_threat_probe": initial_threat_probe,
	})
	var preview_observation: Dictionary = _runtime_observation_for_model(drone, runtime_model)
	var preview_action: Dictionary = runtime_model.predict_action(preview_observation)
	var preview_validation: Dictionary = DroneMLAction.validate(
		preview_action,
		drone.propeller_slots
	)
	if not bool(preview_validation.get("valid", false)):
		return _fail_start(
			"scenario %s (seed %d) produced an invalid frozen-policy action: %s" % [
				scenario_id,
				case_seed,
				str(preview_validation.get("error", "unknown action error")),
			]
		)
	var preview_body_validation: Dictionary = DroneMLAction.validate_body_commands(
		preview_action,
		drone.model_body_interface()
	)
	if not bool(preview_body_validation.get("valid", false)):
		return _fail_start(
			"scenario %s (seed %d) produced an invalid body action: %s" % [
				scenario_id,
				case_seed,
				str(preview_body_validation.get("error", "unknown body action error")),
			]
		)
	# Validation-only prediction is observable state for SAC navigation memory. Erase that
	# synthetic visit so the first physics control decision starts from a genuinely clean case.
	runtime_model.reset_episode_state(case_seed)
	return true


func _runtime_observation_for_model(
	body: ServerDrone,
	model: DroneMLModel
) -> Dictionary:
	if body == null or model == null:
		return {}
	return (
		body.get_ppo_snapshot()
		if model.uses_compact_ppo_observation()
		else body.get_ml_snapshot()
	)


func _restore_full_loadout() -> void:
	if not is_instance_valid(drone) or base_loadout == null:
		return
	drone.loadout = LOADOUT_CONFIG.duplicate_loadout(base_loadout)
	# ServerDrone exposes loadout mutation through part install/remove methods; replacing the
	# complete deterministic evaluation loadout needs the same cache refresh in one operation.
	drone._apply_loadout(true, true)


func _configure_case_target(scenario_id: String, case_seed: int) -> void:
	target_handler = TrainingTargetHandler.new()
	target_handler.handler_key = "candidate-eval:%d:%d" % [group_id, candidate_id]
	var path_system: TrainingPathTargetSystem = TrainingPathTargetSystem.new()
	var registered_system: TrainingRegisteredTargetSystem = TrainingRegisteredTargetSystem.new()
	target_handler.add_system(path_system)
	target_handler.add_system(registered_system)
	target_handler.load_configuration(target_handler_configuration)
	path_system = target_handler.path_system()
	registered_system = target_handler.registered_system()
	if path_system == null or registered_system == null:
		return
	var phase_degrees: float = float(posmod(case_seed, 360))
	if scenario_id.begins_with("routed_target__"):
		var target_kind: String = scenario_id.trim_prefix("routed_target__")
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = case_seed
		var task_position: Vector3 = Vector3(
			rng.randf_range(-9.0, 9.0),
			maxf(path_system.base_height_m, 1.5),
			rng.randf_range(-7.0, 7.0)
		)
		registered_system.enabled = true
		registered_system.upsert_target(
			"fixed-eval:%s:%d" % [target_kind, case_seed],
			target_kind,
			task_position,
			Vector3.ZERO,
			maxf(path_system.hover_radius_m, 0.75),
			0.0,
			1.0,
			1.0,
			{"deterministic_evaluation": true}
		)
		return
	# Core navigation scenarios deliberately use the navigation provider and no live task
	# registrations, but preserve the group's navigation settings before applying the scenario.
	path_system.enabled = true
	registered_system.clear_targets()
	match scenario_id:
		"open_static_target", "sparse_walls", "turret_exposure", "degraded_propeller":
			path_system.move_manual_target(Vector3(10.0, path_system.base_height_m, -8.0))
		"corridor":
			path_system.set_behavior(2)
			path_system.path_rotation_degrees = Vector3(0.0, 0.0, 0.0)
			path_system.path_phase_degrees = phase_degrees
			path_system.line_half_length_m = 7.0
			path_system.speed_mps = maxf(path_system.speed_mps, 1.0)
		"moving_target":
			path_system.set_behavior(1)
			path_system.path_phase_degrees = phase_degrees
			path_system.path_radius_m = maxf(path_system.path_radius_m, 4.0)
			path_system.speed_mps = maxf(path_system.speed_mps, 1.0)
		_:
			# Unknown identifiers are rejected by _build_case_environment(); this fallback only
			# keeps target construction total for a future scenario that explicitly needs stationary.
			path_system.set_behavior(0)


func _vector3_from_record(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var values: Array = value as Array
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return fallback


func _build_case_environment(scenario_id: String, case_seed: int) -> bool:
	if not supports_scenario_id(scenario_id):
		return false
	if scenario_id.begins_with("routed_target__"):
		scenario_wall_spatial_hash.rebuild(scenario_walls)
		return true
	match scenario_id:
		"open_static_target", "moving_target", "degraded_propeller":
			pass
		"sparse_walls":
			_build_sparse_wall_course(case_seed)
		"corridor":
			_build_corridor_course(case_seed)
		"turret_exposure":
			_build_turret_exposure(case_seed)
		_:
			return false
	scenario_wall_spatial_hash.rebuild(scenario_walls)
	return true


func _build_sparse_wall_course(case_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = case_seed
	var destination: Vector3 = Vector3(10.0, spawn_position.y, -8.0)
	var travel: Vector3 = destination - spawn_position
	var horizontal: Vector3 = Vector3(travel.x, 0.0, travel.z)
	var perpendicular: Vector3 = Vector3(-horizontal.z, 0.0, horizontal.x).normalized()
	for index in range(3):
		var fraction: float = 0.28 + float(index) * 0.21
		var center: Vector3 = spawn_position.lerp(destination, fraction)
		center.y = 2.0
		center += perpendicular * rng.randf_range(-3.4, 3.4)
		var size: Vector3 = Vector3(
			rng.randf_range(1.2, 2.2),
			rng.randf_range(3.0, 5.0),
			rng.randf_range(1.2, 2.2)
		)
		center.y = size.y * 0.5
		_add_scenario_box_wall(center, size, rng.randf_range(-0.35, 0.35))


func _build_corridor_course(case_seed: int) -> void:
	var jitter: float = (float(posmod(case_seed, 7)) - 3.0) * 0.12
	var corridor_center_z: float = spawn_position.z
	_add_scenario_box_wall(
		Vector3(0.0, 2.25, corridor_center_z - 4.0 + jitter),
		Vector3(28.0, 4.5, 0.8),
		0.0
	)
	_add_scenario_box_wall(
		Vector3(0.0, 2.25, corridor_center_z + 4.0 + jitter),
		Vector3(28.0, 4.5, 0.8),
		0.0
	)


func _build_turret_exposure(case_seed: int) -> void:
	evaluation_turret = TurretPhysicalBody3D.new()
	evaluation_turret.name = "CandidateEvaluationThreatTurret"
	evaluation_turret.auto_start_active = true
	evaluation_turret.training_invulnerable = true
	evaluation_turret.visible = false
	add_child(evaluation_turret)
	var turret_position: Vector3 = Vector3(5.5, 0.0, -5.0)
	evaluation_turret.reset_body(Transform3D(Basis.IDENTITY, turret_position), case_seed + 70001)
	evaluation_turret_adapter = TurretTrainingCombatantAdapter.new(
		evaluation_turret,
		900000000 + candidate_id * 100 + case_index,
		-9000 - group_id,
		0,
		2
	)
	scenario_entity_spatial_hash.register_entity(
		evaluation_turret_adapter.spatial_key(),
		evaluation_turret,
		evaluation_turret_adapter.entity_kind,
		evaluation_turret_adapter.entity_id,
		evaluation_turret_adapter.metadata()
	)
	var shot_callable: Callable = _on_evaluation_turret_shot_requested
	if not evaluation_turret.shot_requested.is_connected(shot_callable):
		evaluation_turret.shot_requested.connect(shot_callable)


func _register_evaluation_drone_combatant() -> void:
	if not is_instance_valid(drone):
		return
	if drone_combat_adapter != null:
		scenario_entity_spatial_hash.unregister_entity(drone_combat_adapter.spatial_key())
	drone_combat_adapter = DroneTrainingCombatantAdapter.new(
		drone,
		800000000 + candidate_id * 100 + case_index,
		group_id,
		0,
		1
	)
	scenario_entity_spatial_hash.register_entity(
		drone_combat_adapter.spatial_key(),
		drone,
		drone_combat_adapter.entity_kind,
		drone_combat_adapter.entity_id,
		drone_combat_adapter.metadata()
	)


func _update_evaluation_turret_aim() -> void:
	if not is_instance_valid(evaluation_turret) or not is_instance_valid(drone):
		return
	var direction_world: Vector3 = drone.global_position - evaluation_turret.global_position
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
	if not projectile.configure(
		request,
		evaluation_turret_adapter,
		scenario_entity_spatial_hash,
		scenario_wall_spatial_hash
	):
		projectile.queue_free()
		return
	projectile.visible = false
	evaluation_projectiles.append(projectile)


func _build_evaluation_floor() -> void:
	if is_instance_valid(evaluation_floor):
		return
	evaluation_floor = StaticBody3D.new()
	evaluation_floor.name = "CandidateEvaluationFloor"
	evaluation_floor.collision_layer = EVALUATION_WORLD_COLLISION_LAYER
	evaluation_floor.collision_mask = 0
	evaluation_floor.position = Vector3(0.0, -0.25, 0.0)
	evaluation_floor.add_to_group("training_ground")
	evaluation_floor.set_meta("grip_surface_tags", ["ground"])
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(maxf(arena_size.x, 40.0), 0.5, maxf(arena_size.z, 40.0))
	collision.shape = shape
	evaluation_floor.add_child(collision)
	add_child(evaluation_floor)


func _add_scenario_box_wall(center: Vector3, size: Vector3, yaw_radians: float) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.name = "EvaluationWall%02d" % scenario_walls.size()
	wall.collision_layer = EVALUATION_WORLD_COLLISION_LAYER
	wall.collision_mask = 0
	wall.position = center
	wall.rotation.y = yaw_radians
	wall.add_to_group("training_wall")
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.1), maxf(size.y, 0.1), maxf(size.z, 0.1))
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	scenario_walls.append(wall)


func _clear_case_environment() -> void:
	# Case N+1 can start in the same physics callback that queues case N for deletion. Disable
	# the old physics actors immediately so one deferred queue_free frame cannot contaminate the
	# next deterministic case.
	for projectile: TurretTrainingProjectile3D in evaluation_projectiles:
		if is_instance_valid(projectile):
			projectile.set_physics_process(false)
			projectile.queue_free()
	evaluation_projectiles.clear()
	if drone_combat_adapter != null:
		scenario_entity_spatial_hash.unregister_entity(drone_combat_adapter.spatial_key())
	drone_combat_adapter = null
	if evaluation_turret_adapter != null:
		scenario_entity_spatial_hash.unregister_entity(evaluation_turret_adapter.spatial_key())
	evaluation_turret_adapter = null
	if is_instance_valid(evaluation_turret):
		evaluation_turret.active = false
		evaluation_turret.queue_free()
	evaluation_turret = null
	for wall: Node3D in scenario_walls:
		if is_instance_valid(wall):
			var collision_object: CollisionObject3D = wall as CollisionObject3D
			if collision_object != null:
				collision_object.collision_layer = 0
				collision_object.collision_mask = 0
			wall.queue_free()
	scenario_walls.clear()
	scenario_wall_spatial_hash.clear()


func _scenario_record() -> Dictionary:
	return {
		"wall_count": scenario_wall_spatial_hash.wall_count(),
		"turret_exposure": is_instance_valid(evaluation_turret),
		"target_kind": str(current_target.get("target_kind", "fallback")),
	}


func _scenario_is_degraded_propeller(scenario_id: String) -> bool:
	return scenario_id == "degraded_propeller"


func _record_case(reward: Dictionary) -> void:
	var termination_reason: String = str(reward.get("termination_reason", "unknown"))
	var terminated: bool = bool(reward.get("terminated", false))
	records.append({
		"scenario_id": str(current_case.get("scenario_id", "")),
		"seed": int(current_case.get("seed", 0)),
		"deterministic": true,
		"suite_hash": str(plan.get("suite_hash", "")),
		# Promotion uses reward per *planned* benchmark second. Dividing by actual elapsed time
		# lets an early terminal failure change the scale of its own score; planned duration keeps
		# every seed/scenario on the same denominator while still retaining raw/elapsed diagnostics.
		"episode_return": (
			float(reward.get("total_reward", 0.0))
			/ maxf(current_case_duration_seconds, 0.000001)
		),
		"raw_episode_return": float(reward.get("total_reward", 0.0)),
		"episode_return_per_second": float(reward.get("mean_reward_per_second", 0.0)),
		"planned_duration_seconds": current_case_duration_seconds,
		"success": bool(reward.get("reached_target_radius", false)) and not terminated,
		"crashed": terminated,
		"terminated": terminated,
		"truncated": bool(reward.get("truncated", false)),
		"termination_reason": termination_reason,
		"elapsed_seconds": float(reward.get("episode_elapsed_seconds", 0.0)),
		"candidate_hash": candidate_hash,
		"evaluation_contract_hash": evaluation_contract_hash,
		"scenario_environment": _scenario_record(),
	})


func _fail_start(reason: String) -> bool:
	last_error = reason
	status = "error"
	if is_instance_valid(drone):
		drone.set_activated(false)
	failed.emit(group_id, candidate_id, reason)
	return false
