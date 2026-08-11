class_name TurretTrainingCoordinator
extends RefCounted

signal group_episode_completed(group_id: int)
signal group_update_completed(group_id: int)
signal group_episode_started(group_id: int, episode_number: int)
signal worker_action_applied(
	group_id: int,
	episode_number: int,
	worker_index: int,
	instance_id: int,
	elapsed_seconds: float,
	commands: PackedFloat64Array
)

const DEFAULT_WORKER_COUNT = 1
const MAXIMUM_WORKER_COUNT = 16
const MAXIMUM_GROUP_COUNT = 9
const DECISION_INTERVAL_SECONDS = 0.05
const MAXIMUM_EPISODE_SECONDS = 600.0
const EPISODE_RESPAWN_DELAY_SECONDS = 1.0
const MINIMUM_BACKGROUND_UPDATE_SAMPLES = 64
const TURRET_TEAM_ID = 2
const TARGET_TEAM_ID = 1
const SPAWN_EDGE_INSET_M = 1.5

var host: Node3D
var wall_spatial_hash: DroneTrainingWallSpatialHash
var entity_spatial_hash: ServerSpatialHash3D
var evaluation_contract_provider: Callable
var preset_loadout_template: TurretLoadout
var groups: Array[Dictionary] = []
var groups_by_id: Dictionary = {}
var combat_adapters_by_turret_id: Dictionary[int, TurretTrainingCombatantAdapter] = {}
var active_projectiles_by_turret_id: Dictionary = {}
var last_error = ""


func _init(owner: Node3D = null) -> void:
	host = owner
	preset_loadout_template = MLBodyPresetLibrary.stationary_turret_loadout()


func create_group(
	group_id: int,
	group_name: String,
	color: Color,
	worker_count: int = DEFAULT_WORKER_COUNT,
	initial_loadout: TurretLoadout = null,
	network_config: Dictionary = {}
) -> Dictionary:
	last_error = ""
	if host == null or not is_instance_valid(host):
		last_error = "The shared training room is not available."
		return {}
	if groups_by_id.has(group_id):
		last_error = "A turret group already uses id %d." % group_id
		return {}
	if groups.size() >= MAXIMUM_GROUP_COUNT:
		last_error = "The shared arena supports up to %d turret groups." % MAXIMUM_GROUP_COUNT
		return {}
	var loadout = (
		MLBodyPartContract.deep_duplicate_resource(initial_loadout) as TurretLoadout
		if initial_loadout != null
		else MLBodyPartContract.deep_duplicate_resource(preset_loadout_template) as TurretLoadout
	)
	if loadout == null or not loadout.ensure_contract():
		last_error = "The turret body preset/loadout is incomplete."
		return {}
	var group: Dictionary = TrainingCoordinatorGroupState.create(
		group_id,
		"turret",
		group_name,
		color,
		worker_count,
		MAXIMUM_WORKER_COUNT,
		DECISION_INTERVAL_SECONDS
	)
	group.merge({
		"turret_loadout": loadout,
		"hardware_revision": 0,
		"source_description": "Fresh stationary-turret policy",
		"trainer": TurretPPOTrainer.new(9100009 + group_id * 131, network_config),
		"reward_deck": TurretRewardDeck.new(),
		"reward_cardset_id": "builtin:turret_precision",
		"reward_cardset_name": "Precision Fire",
		"worker_placements": _new_unconfigured_placements(
			clampi(worker_count, 1, MAXIMUM_WORKER_COUNT)
		),
		"placement_position": Vector3.ZERO,
		"placement_yaw_degrees": 0.0,
		"placement_configured": false,
		"target_worker_group_id": -1,
		"resolved_target_entity_id": -1,
		"resolved_target": {},
		"manual_override_enabled": false,
		"manual_yaw_drive": 0.0,
		"manual_pitch_drive": 0.0,
		"manual_trigger": 0.0,
		"add_worker_button": null,
	}, true)

	groups.append(group)
	groups_by_id[group_id] = group
	return group


func group_by_id(group_id: int) -> Dictionary:
	return groups_by_id.get(group_id, {})


func group_loadout(group_id: int) -> TurretLoadout:
	var group = group_by_id(group_id)
	return _group_loadout(group) if not group.is_empty() else null


func replace_group_loadout(group_id: int, loadout: TurretLoadout) -> bool:
	last_error = ""
	var group = group_by_id(group_id)
	if group.is_empty() or loadout == null:
		last_error = "The selected turret group or loadout is unavailable."
		return false
	if bool(group.get("active", false)):
		last_error = "Pause the turret group before changing its parts."
		return false
	var private_loadout = MLBodyPartContract.deep_duplicate_resource(loadout) as TurretLoadout
	if private_loadout == null or not private_loadout.ensure_contract():
		last_error = "The replacement turret body is incomplete."
		return false
	group["turret_loadout"] = private_loadout
	group["hardware_revision"] = int(group.get("hardware_revision", 0)) + 1
	(group["trainer"] as TurretPPOTrainer).discard_incomplete_rollout()
	_clear_group_workers(group)
	return true


func reset_group_loadout(group_id: int) -> bool:
	return replace_group_loadout(group_id, MLBodyPresetLibrary.stationary_turret_loadout())


func remove_group(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {}
	(group["trainer"] as TurretPPOTrainer).shutdown_background_update()
	_clear_group_workers(group)
	groups.erase(group)
	groups_by_id.erase(group_id)
	return group


func set_group_active(
	group_id: int,
	active: bool,
	fallback_target_position: Vector3,
	episode_duration: float,
	arena_size: Vector3
) -> bool:
	last_error = ""
	var group = group_by_id(group_id)
	if group.is_empty():
		last_error = "The selected turret group is unavailable."
		return false
	if active and not _all_worker_placements_configured(group):
		last_error = "Place every turret in this group before starting it."
		return false
	if not active:
		# Ordinary pause mirrors the limb-worker contract: preserve the exact live episode rather
		# than turning pause into an episode boundary. Projectiles are part of that simulation state,
		# so freeze them in flight and resume them with the group. Real policy/episode/configuration
		# boundaries still cancel them through _cancel_group_projectiles().
		_set_group_projectiles_paused(group, true)
	group["active"] = active
	var expected_worker_count: int = clampi(
		int(group.get("worker_count", DEFAULT_WORKER_COUNT)),
		1,
		MAXIMUM_WORKER_COUNT
	)
	var live_workers: Array = group.get("workers", [])
	var live_population_valid: bool = live_workers.size() == expected_worker_count
	if live_population_valid:
		for worker_value: Variant in live_workers:
			if not (worker_value is Dictionary) or not is_instance_valid(_worker_turret(worker_value as Dictionary)):
				live_population_valid = false
				break
	if active and not live_population_valid:
		_start_group_episode(group, fallback_target_position, episode_duration, arena_size)
	else:
		_set_group_projectiles_paused(group, not active)
	for worker_value in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker: Dictionary = worker_value as Dictionary
		var worker_runtime_active: bool = active and not bool(worker.get("finished", false))
		var turret = _worker_turret(worker)
		if is_instance_valid(turret):
			turret.active = worker_runtime_active
		var combat_adapter = worker.get("combat_adapter") as TrainingCombatantAdapter
		if combat_adapter != null:
			combat_adapter.set_simulation_active(worker_runtime_active)
	return true


func set_manual_override(group_id: int, enabled: bool) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	if bool(group.get("manual_override_enabled", false)) == enabled:
		return true
	group["manual_override_enabled"] = enabled
	var trainer: TurretPPOTrainer = group["trainer"] as TurretPPOTrainer
	# Manual control only owns worker 0. Keep every other turret's held action, pending
	# projectile outcomes, and valid on-policy samples intact. Remove worker 0's live rollout
	# fragments so GAE cannot bridge across an unobserved manual-control gap.
	trainer.discard_worker_transitions(0)
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker: Dictionary = worker_value as Dictionary
		if int(worker.get("id", -1)) != 0:
			continue
		worker["last_action_sample"] = {}
		worker["interval_reward"] = 0.0
		worker["interval_elapsed_seconds"] = 0.0
		if enabled and not bool(worker.get("finished", false)):
			worker["manual_touched_this_episode"] = true
		var turret: TurretPhysicalBody3D = _worker_turret(worker)
		if not is_instance_valid(turret):
			continue
		# Delayed weapon outcomes from the previous controller must not cross the
		# manual/autonomous ownership boundary. Other workers keep their projectiles.
		_cancel_projectiles_for_turret_id(int(turret.get_instance_id()))
		turret.consume_weapon_events()
		if enabled:
			turret.submit_manual_controls(
				float(group.get("manual_yaw_drive", 0.0)),
				float(group.get("manual_pitch_drive", 0.0)),
				float(group.get("manual_trigger", 0.0))
			)
		else:
			turret.submit_manual_controls(0.0, 0.0, 0.0)
	return true


func set_manual_controls(
	group_id: int,
	yaw_drive: float,
	pitch_drive: float,
	trigger: float
) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	group["manual_yaw_drive"] = clampf(yaw_drive, -1.0, 1.0)
	group["manual_pitch_drive"] = clampf(pitch_drive, -1.0, 1.0)
	group["manual_trigger"] = clampf(trigger, 0.0, 1.0)
	if not bool(group.get("manual_override_enabled", false)):
		return true
	var workers: Array = group.get("workers", [])
	if workers.is_empty() or not (workers[0] is Dictionary):
		return true
	var turret = _worker_turret(workers[0])
	return (
		turret.submit_manual_controls(
			float(group["manual_yaw_drive"]),
			float(group["manual_pitch_drive"]),
			float(group["manual_trigger"])
		)
		if is_instance_valid(turret)
		else true
	)


func live_combat_adapters() -> Array[TrainingCombatantAdapter]:
	var result: Array[TrainingCombatantAdapter] = []
	for group: Dictionary in groups:
		for worker_value: Variant in group.get("workers", []):
			if not (worker_value is Dictionary):
				continue
			var worker = worker_value as Dictionary
			if bool(worker.get("finished", false)):
				continue
			var adapter = worker.get("combat_adapter") as TrainingCombatantAdapter
			if adapter != null and adapter.is_alive():
				result.append(adapter)
	return result


func restart_group_for_configuration_change(
	group_id: int,
	fallback_target_position: Vector3,
	episode_duration: float,
	arena_size: Vector3
) -> bool:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return false
	(group["trainer"] as TurretPPOTrainer).discard_incomplete_rollout()
	group["awaiting_respawn"] = false
	group["respawn_delay_remaining"] = 0.0
	# Do not carry a previously resolved objective across an operator configuration boundary.
	# The next room tick installs the handler's fresh full target record; an immediate restart uses
	# the supplied fallback position as the same synthetic range target the turret trains against.
	group["resolved_target"] = {}
	group["resolved_target_entity_id"] = -1
	# Treat target-generator edits as episode boundaries. Dynamic target motion still happens
	# inside an episode; only operator changes to the generator discard the partial rollout.
	_clear_group_workers(group)
	if bool(group.get("active", false)):
		_start_group_episode(group, fallback_target_position, episode_duration, arena_size)
	return true


func set_worker_count(group_id: int, requested_count: int) -> bool:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return false
	last_error = ""
	var current_count: int = group_worker_count(group_id)
	var count: int = clampi(requested_count, 1, MAXIMUM_WORKER_COUNT)
	if count > current_count:
		last_error = "Adding a turret requires a placement. Use the + button on the turret group."
		return false
	group["pending_worker_count"] = count
	if not bool(group.get("active", false)):
		group["worker_count"] = count
		_resize_worker_placements(group, count)
		(group["trainer"] as TurretPPOTrainer).discard_incomplete_rollout()
		_clear_group_workers(group)
	return true


func apply_worker_count_now(
	group_id: int,
	requested_count: int,
	fallback_target_position: Vector3,
	episode_duration: float,
	arena_size: Vector3
) -> bool:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return false
	last_error = ""
	var current_count: int = group_worker_count(group_id)
	var count: int = clampi(requested_count, 1, MAXIMUM_WORKER_COUNT)
	if count > current_count:
		last_error = "Adding a turret requires a placement. Use the + button on the turret group."
		return false
	group["pending_worker_count"] = count
	group["worker_count"] = count
	_resize_worker_placements(group, count)
	(group["trainer"] as TurretPPOTrainer).discard_incomplete_rollout()
	_clear_group_workers(group)
	if bool(group.get("active", false)):
		_start_group_episode(group, fallback_target_position, episode_duration, arena_size)
	return true


func set_control_interval(group_id: int, seconds: float) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	group["control_interval_seconds"] = _safe_control_interval(seconds)
	var trainer = group["trainer"]
	trainer.config["control_interval_seconds"] = group["control_interval_seconds"]
	trainer._sanitize_config()
	(group["trainer"] as TurretPPOTrainer).discard_incomplete_rollout()
	return true


func episode_progress_summaries() -> Array[Dictionary]:
	return TrainingCoordinatorGroupState.episode_progress_summaries(
		groups,
		Callable(self, "_worker_turret")
	)


func tick(
	delta: float,
	fallback_target_position: Vector3,
	episode_duration: float,
	arena_size: Vector3,
	targets_by_group: Dictionary = {}
) -> void:
	for group in groups:
		_poll_group_optimizer(group)
		group["optimizer_waiting"] = (group["trainer"] as TurretPPOTrainer).has_background_update()
		if not bool(group.get("active", false)):
			continue
		var group_target: Dictionary = targets_by_group.get(int(group.get("group_id", -1)), {})
		var group_target_position: Vector3 = group_target.get(
			"position_world",
			fallback_target_position
		)
		group["resolved_target"] = (
			group_target.duplicate(false)
			if not group_target.is_empty()
			else _fallback_resolved_target(group_target_position)
		)
		group["resolved_target_entity_id"] = _resolved_target_entity_id(group, group_target)
		if bool(group.get("awaiting_respawn", false)):
			group["respawn_delay_remaining"] = maxf(
				float(group.get("respawn_delay_remaining", 0.0)) - delta,
				0.0
			)
			if float(group["respawn_delay_remaining"]) <= 0.0:
				_start_group_episode(group, group_target_position, episode_duration, arena_size)
			continue
		_tick_group(group, delta, group_target_position, arena_size)


func shutdown() -> void:
	for group in groups:
		(group["trainer"] as TurretPPOTrainer).shutdown_background_update()
		_clear_group_workers(group)
	groups.clear()
	groups_by_id.clear()
	combat_adapters_by_turret_id.clear()
	active_projectiles_by_turret_id.clear()


func save_checkpoint(group_id: int, use_best_policy: bool = false) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {}
	var loadout = _group_loadout(group)
	if loadout == null:
		last_error = "The turret group has no valid accepted body loadout."
		return {}
	var trainer = group["trainer"] as TurretPPOTrainer
	var checkpoint = trainer.to_checkpoint(
		loadout.hardware_signature(),
		(group["reward_deck"] as TurretRewardDeck).configuration_dictionary(),
		use_best_policy
	)
	if checkpoint.is_empty():
		last_error = trainer.last_error
		return {}
	checkpoint["turret_loadout"] = loadout.to_dictionary()
	if evaluation_contract_provider.is_valid():
		var current_contract: Dictionary = evaluation_contract_provider.call(group_id, "turret")
		if RLEvaluationContract.is_valid(current_contract, "turret"):
			checkpoint["current_room_evaluation_contract"] = current_contract
	if use_best_policy:
		var best_contract: Dictionary = trainer.best_evaluation_contract_snapshot()
		if RLEvaluationContract.is_valid(best_contract, "turret"):
			checkpoint["best_evaluation_contract"] = best_contract
	checkpoint["room_settings"] = {
		"worker_count": int(group.get("worker_count", DEFAULT_WORKER_COUNT)),
		"control_interval_seconds": _safe_control_interval(group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)),
		"placements": _placements_dictionary_array(group),
		"target_worker_group_id": int(group.get("target_worker_group_id", -1)),
	}
	return checkpoint


func evaluation_candidate_checkpoint(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {}
	var loadout = _group_loadout(group)
	if loadout == null:
		last_error = "The turret group has no valid accepted body loadout."
		return {}
	var trainer = group["trainer"] as TurretPPOTrainer
	var checkpoint = trainer.candidate_checkpoint(
		loadout.hardware_signature(),
		(group["reward_deck"] as TurretRewardDeck).configuration_dictionary()
	)
	if checkpoint.is_empty():
		return {}
	checkpoint["turret_loadout"] = loadout.to_dictionary()
	checkpoint["room_settings"] = {
		"worker_count": int(group.get("worker_count", DEFAULT_WORKER_COUNT)),
		"control_interval_seconds": _safe_control_interval(group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)),
		"placements": _placements_dictionary_array(group),
		"target_worker_group_id": int(group.get("target_worker_group_id", -1)),
	}
	return checkpoint


func pending_evaluation_candidate(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	return (group["trainer"] as TurretPPOTrainer).pending_evaluation_candidate() if not group.is_empty() else {}


func record_deterministic_evaluation(
	group_id: int,
	candidate_id: int,
	evaluation_summary: Dictionary
) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {"promoted": false, "reason": "missing_group"}
	return (group["trainer"] as TurretPPOTrainer).record_deterministic_evaluation(
		candidate_id,
		evaluation_summary
	)


func record_deterministic_evaluation_records(
	group_id: int,
	candidate_id: int,
	records: Array[Dictionary]
) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {"promoted": false, "reason": "missing_group"}
	return (group["trainer"] as TurretPPOTrainer).record_deterministic_evaluation_records(
		candidate_id,
		records
	)


func best_selection_summary(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	return (group["trainer"] as TurretPPOTrainer).best_selection_summary() if not group.is_empty() else {}


func load_checkpoint(group_id: int, checkpoint: Dictionary) -> bool:
	last_error = ""
	var group = group_by_id(group_id)
	if group.is_empty():
		last_error = "Select a turret worker group first."
		return false
	var stored_loadout: Variant = checkpoint.get("turret_loadout", {})
	var reward_cards_value: Variant = checkpoint.get("reward_cards", {})
	var settings_value: Variant = checkpoint.get("room_settings", {})
	if (
		not (stored_loadout is Dictionary)
		or not (reward_cards_value is Dictionary)
		or not (settings_value is Dictionary)
	):
		last_error = "The turret checkpoint contains malformed room metadata."
		return false
	var loadout = _group_loadout(group)
	var stored_loadout_dictionary: Dictionary = stored_loadout as Dictionary
	if not stored_loadout_dictionary.is_empty():
		loadout = TurretLoadout.from_dictionary(stored_loadout_dictionary)
		if loadout == null or not loadout.ensure_contract():
			last_error = "The turret checkpoint contains an incomplete body definition."
			return false
	if loadout == null:
		last_error = "The turret checkpoint did not provide a body and the group has no valid accepted body."
		return false
	var settings: Dictionary = settings_value as Dictionary
	var restored_worker_count: int = clampi(
		RLTrainingMath.finite_int_or(settings.get("worker_count"), DEFAULT_WORKER_COUNT),
		1,
		MAXIMUM_WORKER_COUNT
	)
	var restored_placements: Array[Dictionary] = _parse_placements_array(
		settings.get("placements", []),
		restored_worker_count
	)
	if restored_placements.size() != restored_worker_count:
		last_error = "The turret checkpoint contains invalid or incomplete worker placements."
		return false
	var trainer = group["trainer"] as TurretPPOTrainer
	if not trainer.load_checkpoint(checkpoint, loadout.hardware_signature()):
		last_error = trainer.last_error
		return false
	group["turret_loadout"] = loadout
	group["hardware_revision"] = int(group.get("hardware_revision", 0)) + 1
	var reward_cards: Dictionary = reward_cards_value as Dictionary
	(group["reward_deck"] as TurretRewardDeck).load_configuration(reward_cards)
	group["worker_count"] = restored_worker_count
	group["pending_worker_count"] = restored_worker_count
	group["worker_placements"] = restored_placements
	_sync_primary_placement_fields(group)
	var restored_target_group_id: int = RLTrainingMath.finite_int_or(
		settings.get("target_worker_group_id"),
		-1
	)
	group["target_worker_group_id"] = restored_target_group_id if restored_target_group_id >= 0 else -1
	group["resolved_target_entity_id"] = -1
	group["control_interval_seconds"] = _safe_control_interval(
		settings.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)
	)
	group["episode"] = trainer.completed_episodes
	group["best_mean_reward"] = trainer.best_episode_score
	group["last_update"] = trainer.last_metrics.duplicate(true)
	_clear_group_workers(group)
	(group["history"] as DroneTrainingMetricsHistory).reset()
	return true


func reset_group_statistics(group_id: int) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	(group["trainer"] as TurretPPOTrainer).reset_episode_statistics()
	(group["history"] as DroneTrainingMetricsHistory).reset()
	group["last_mean_reward"] = 0.0
	group["best_mean_reward"] = -INF
	group["last_update"] = {}
	return true


func _start_group_episode(
	group: Dictionary,
	fallback_target_position: Vector3,
	episode_duration: float,
	arena_size: Vector3
) -> void:
	_apply_pending_reward_config(group)
	var episode_trainer: TurretPPOTrainer = group["trainer"] as TurretPPOTrainer
	if evaluation_contract_provider.is_valid():
		var episode_contract: Dictionary = evaluation_contract_provider.call(
			int(group.get("group_id", -1)),
			"turret"
		)
		episode_trainer.set_evaluation_contract(episode_contract)
	group["worker_count"] = clampi(
		int(group.get("pending_worker_count", DEFAULT_WORKER_COUNT)),
		1,
		MAXIMUM_WORKER_COUNT
	)
	_resize_worker_placements(group, int(group["worker_count"]))
	var count = int(group["worker_count"])
	var existing: Array = group.get("workers", [])
	if existing.size() != count:
		_clear_group_workers(group)
		existing = []
	var trainer: TurretPPOTrainer = episode_trainer
	var group_loadout: TurretLoadout = _group_loadout(group)
	if group_loadout == null:
		last_error = "The turret group cannot start without a valid accepted body loadout."
		group["active"] = false
		return
	group["episode"] = int(group.get("episode", 0)) + 1
	group_episode_started.emit(int(group["group_id"]), int(group["episode"]))
	group["awaiting_respawn"] = false
	group["respawn_delay_remaining"] = 0.0
	var workers: Array[Dictionary] = []
	for worker_index in range(count):
		var turret: TurretPhysicalBody3D = null
		if worker_index < existing.size() and existing[worker_index] is Dictionary:
			turret = _worker_turret(existing[worker_index])
		if not is_instance_valid(turret):
			var worker_loadout: TurretLoadout = (
				MLBodyPartContract.deep_duplicate_resource(group_loadout) as TurretLoadout
			)
			if worker_loadout == null or not worker_loadout.ensure_contract():
				last_error = "The accepted turret body could not be duplicated for a training worker."
				group["active"] = false
				_clear_group_workers(group)
				return
			turret = TurretPhysicalBody3D.new()
			turret.name = "TurretGroup%02dWorker%03d" % [int(group["group_id"]), worker_index]
			turret.loadout = worker_loadout
			turret.training_invulnerable = true
			host.add_child(turret)
		var spawn: Transform3D = _group_spawn_transform(group, worker_index, count, arena_size)
		_cancel_projectiles_for_turret_id(int(turret.get_instance_id()))
		if not turret.reset_body(spawn, int(group["episode"]) * 1000 + worker_index):
			last_error = "A turret worker rejected its accepted body during episode reset."
			group["active"] = false
			if is_instance_valid(turret):
				turret.queue_free()
			_clear_group_workers(group)
			return
		turret.set_visual_color(group["color"])
		var entity_id = int(turret.get_instance_id())
		var combat_adapter = TurretTrainingCombatantAdapter.new(
			turret,
			entity_id,
			int(group["group_id"]),
			worker_index,
			TURRET_TEAM_ID
		)
		_register_combatant(combat_adapter)
		var ml_adapter = TurretMLBodyAdapter.new(turret)
		var initial_commands = TurretMLAction.neutral_commands()
		var probe = TurretTrainingTargetSensor.acquire(
			turret,
			combat_adapter,
			entity_spatial_hash,
			wall_spatial_hash,
			fallback_target_position,
			turret.loadout.gun.maximum_range_m,
			int(group.get("target_worker_group_id", -1)),
			_preferred_target_entity_id(group),
			_resolved_target_for_group(group, fallback_target_position)
		)
		ml_adapter.set_context(probe, 0.0, initial_commands, {})
		var observation = ml_adapter.capture_observation()
		var worker = {
			"id": worker_index,
			"turret": turret,
			"adapter": ml_adapter,
			"combat_adapter": combat_adapter,
			"episode_elapsed": 0.0,
			"decision_elapsed": 0.0,
			"episode_duration": clampf(episode_duration, 0.1, MAXIMUM_EPISODE_SECONDS),
			"last_action_sample": {},
			"interval_reward": 0.0,
			"interval_elapsed_seconds": 0.0,
			"total_reward": 0.0,
			"previous_observation": observation,
			"previous_commands": initial_commands,
			"reward_state": (group["reward_deck"] as TurretRewardDeck).reset_state(observation),
			"finished": false,
			"failure_reason": "",
			"latest_target_probe": probe,
			"time_precisely_aimed_seconds": 0.0,
			"manual_touched_this_episode": (
				bool(group.get("manual_override_enabled", false))
				and worker_index == 0
			),
			"episode_result": {},
		}
		var shot_callable = _on_shot_requested.bind(turret)
		if not turret.shot_requested.is_connected(shot_callable):
			turret.shot_requested.connect(shot_callable)
		if bool(group.get("manual_override_enabled", false)) and worker_index == 0:
			turret.submit_manual_controls(
				float(group.get("manual_yaw_drive", 0.0)),
				float(group.get("manual_pitch_drive", 0.0)),
				float(group.get("manual_trigger", 0.0))
			)
		else:
			var sample = trainer.sample_runtime_action(observation)
			if (
				not sample.is_empty()
				and ml_adapter.apply_commands(sample.get("commands", PackedFloat64Array()))
			):
				worker["last_action_sample"] = sample
				var sampled_commands: PackedFloat64Array = sample.get("commands", initial_commands)
				worker["previous_commands"] = sampled_commands
				_emit_worker_action_applied(group, worker, sampled_commands)
		workers.append(worker)
	group["workers"] = workers


func _tick_group(
	group: Dictionary,
	delta: float,
	fallback_target_position: Vector3,
	_arena_size: Vector3
) -> void:
	var all_finished = true
	for worker in group.get("workers", []):
		if not (worker is Dictionary) or bool((worker as Dictionary).get("finished", false)):
			continue
		all_finished = false
		_tick_worker(group, worker, delta, fallback_target_position)
	if all_finished or _all_workers_finished(group):
		_finish_group_episode(group)


func _tick_worker(
	group: Dictionary,
	worker: Dictionary,
	delta: float,
	fallback_target_position: Vector3
) -> void:
	var turret = _worker_turret(worker)
	var adapter = worker.get("adapter") as TurretMLBodyAdapter
	var combat_adapter = worker.get("combat_adapter") as TurretTrainingCombatantAdapter
	if not is_instance_valid(turret) or adapter == null or combat_adapter == null:
		_finish_worker(group, worker, "missing_body", false, worker.get("previous_observation", {}))
		return
	var safe_delta: float = maxf(delta, 0.0)
	worker["episode_elapsed"] = float(worker.get("episode_elapsed", 0.0)) + safe_delta
	worker["decision_elapsed"] = float(worker.get("decision_elapsed", 0.0)) + safe_delta
	# Track actual time under the held action independently from the scheduler's fmod phase.
	worker["interval_elapsed_seconds"] = (
		float(worker.get("interval_elapsed_seconds", 0.0)) + safe_delta
	)
	if not turret.is_body_alive():
		_cancel_projectiles_for_turret_id(int(turret.get_instance_id()), true)
		var death_observation: Dictionary = _settle_pending_worker_reward(
			group, worker, fallback_target_position
		)
		_finish_worker(
			group,
			worker,
			"destroyed",
			false,
			death_observation if not death_observation.is_empty() else worker.get("previous_observation", {})
		)
		return
	if float(worker["episode_elapsed"]) >= float(worker.get("episode_duration", 20.0)):
		_cancel_projectiles_for_turret_id(int(turret.get_instance_id()), true)
		var timeout_observation: Dictionary = _settle_pending_worker_reward(
			group, worker, fallback_target_position
		)
		if timeout_observation.is_empty():
			_finish_worker(
				group, worker, "invalid_observation", false, worker.get("previous_observation", {})
			)
		else:
			_finish_worker(group, worker, "timeout", true, timeout_observation)
		return
	var interval = _safe_control_interval(group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS))
	if float(worker["decision_elapsed"]) < interval:
		return
	var reward_delta: float = maxf(
		float(worker.get("interval_elapsed_seconds", safe_delta)),
		0.000001
	)
	worker["decision_elapsed"] = fmod(float(worker["decision_elapsed"]), interval)
	var probe = TurretTrainingTargetSensor.acquire(
		turret,
		combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		fallback_target_position,
		turret.loadout.gun.maximum_range_m,
		int(group.get("target_worker_group_id", -1)),
		_preferred_target_entity_id(group),
		_resolved_target_for_group(group, fallback_target_position)
	)
	worker["latest_target_probe"] = probe
	var combat_events = combat_adapter.consume_combat_events()
	adapter.set_context(
		probe,
		float(worker["episode_elapsed"]) / maxf(float(worker["episode_duration"]), 0.1),
		worker.get("previous_commands", TurretMLAction.neutral_commands()),
		combat_events
	)
	var observation = adapter.capture_observation()
	if observation.is_empty():
		_finish_worker(group, worker, "invalid_observation", false, worker.get("previous_observation", {}))
		return
	var weapon_events = turret.consume_weapon_events()
	var reward_result = (group["reward_deck"] as TurretRewardDeck).step_reward(
		worker.get("previous_observation", observation),
		observation,
		reward_delta,
		worker["reward_state"],
		weapon_events
	)
	var reward = float(reward_result.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + reward
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + reward
	worker["previous_observation"] = observation
	var observed_target: Dictionary = observation.get("target", {})
	if TurretTrainingTargetSensor.is_precision_tracking_state(
		observed_target,
		TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
	):
		worker["time_precisely_aimed_seconds"] = float(worker.get("time_precisely_aimed_seconds", 0.0)) + reward_delta
	group["last_reward_state"] = worker["reward_state"]
	var manual_override = (
		bool(group.get("manual_override_enabled", false))
		and int(worker.get("id", -1)) == 0
	)
	if manual_override:
		worker["last_action_sample"] = {}
		worker["interval_reward"] = 0.0
		worker["interval_elapsed_seconds"] = 0.0
		turret.submit_manual_controls(
			float(group.get("manual_yaw_drive", 0.0)),
			float(group.get("manual_pitch_drive", 0.0)),
			float(group.get("manual_trigger", 0.0))
		)
		return
	var trainer = group["trainer"] as TurretPPOTrainer
	var last_sample: Dictionary = worker.get("last_action_sample", {})
	var sample = trainer.sample_runtime_action(observation)
	if not last_sample.is_empty():
		var transition_accepted: bool
		if sample.is_empty():
			transition_accepted = trainer.add_transition(
				int(worker["id"]),
				last_sample,
				float(worker["interval_reward"]),
				observation,
				false,
				false,
				maxf(float(worker.get("interval_elapsed_seconds", interval)), 0.000001)
			)
		else:
			transition_accepted = trainer.add_transition(
				int(worker["id"]),
				last_sample,
				float(worker["interval_reward"]),
				observation,
				false,
				false,
				maxf(float(worker.get("interval_elapsed_seconds", interval)), 0.000001),
				sample.get("actor_input", PackedFloat64Array()),
				float(sample.get("value", NAN))
			)
		if not transition_accepted:
			last_error = trainer.last_error
			worker["last_action_sample"] = {}
			worker["interval_reward"] = 0.0
			worker["interval_elapsed_seconds"] = 0.0
			return
	worker["interval_reward"] = 0.0
	worker["interval_elapsed_seconds"] = 0.0
	if sample.is_empty() or not adapter.apply_commands(sample.get("commands", PackedFloat64Array())):
		worker["last_action_sample"] = {}
		return
	worker["last_action_sample"] = sample
	var sampled_commands: PackedFloat64Array = sample.get("commands", TurretMLAction.neutral_commands())
	worker["previous_commands"] = sampled_commands
	_emit_worker_action_applied(group, worker, sampled_commands)


func _settle_pending_worker_reward(
	group: Dictionary,
	worker: Dictionary,
	fallback_target_position: Vector3
) -> Dictionary:
	var previous_observation: Dictionary = worker.get("previous_observation", {})
	var reward_delta: float = float(worker.get("interval_elapsed_seconds", 0.0))
	if reward_delta <= 0.0:
		return previous_observation
	var turret = _worker_turret(worker)
	var adapter = worker.get("adapter") as TurretMLBodyAdapter
	var combat_adapter = worker.get("combat_adapter") as TurretTrainingCombatantAdapter
	if not is_instance_valid(turret) or adapter == null or combat_adapter == null:
		return {}
	var probe: Dictionary = TurretTrainingTargetSensor.acquire(
		turret,
		combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		fallback_target_position,
		turret.loadout.gun.maximum_range_m,
		int(group.get("target_worker_group_id", -1)),
		_preferred_target_entity_id(group),
		_resolved_target_for_group(group, fallback_target_position)
	)
	worker["latest_target_probe"] = probe
	var combat_events: Dictionary = combat_adapter.consume_combat_events()
	adapter.set_context(
		probe,
		float(worker["episode_elapsed"]) / maxf(float(worker["episode_duration"]), 0.1),
		worker.get("previous_commands", TurretMLAction.neutral_commands()),
		combat_events
	)
	var observation: Dictionary = adapter.capture_observation()
	if observation.is_empty():
		return {}
	var weapon_events: Dictionary = turret.consume_weapon_events()
	var reward_result: Dictionary = (group["reward_deck"] as TurretRewardDeck).step_reward(
		previous_observation if not previous_observation.is_empty() else observation,
		observation,
		maxf(reward_delta, 0.000001),
		worker["reward_state"],
		weapon_events
	)
	var reward: float = float(reward_result.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + reward
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + reward
	worker["previous_observation"] = observation
	var observed_target: Dictionary = observation.get("target", {})
	if TurretTrainingTargetSensor.is_precision_tracking_state(
		observed_target,
		TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
	):
		worker["time_precisely_aimed_seconds"] = (
			float(worker.get("time_precisely_aimed_seconds", 0.0)) + reward_delta
		)
	group["last_reward_state"] = worker["reward_state"]
	# Keep interval_elapsed_seconds intact so _finish_worker records the true final-action duration.
	return observation


func _finish_worker(
	group: Dictionary,
	worker: Dictionary,
	reason: String,
	timed_out: bool,
	observation: Dictionary
) -> void:
	if bool(worker.get("finished", false)):
		return
	worker["finished"] = true
	worker["failure_reason"] = reason
	var terminal = (group["reward_deck"] as TurretRewardDeck).terminal_reward(
		worker["reward_state"],
		"" if timed_out else reason,
		timed_out
	)
	var terminal_reward = float(terminal.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + terminal_reward
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + terminal_reward
	var trainer = group["trainer"] as TurretPPOTrainer
	var last_sample: Dictionary = worker.get("last_action_sample", {})
	if not last_sample.is_empty():
		var terminal_transition_accepted: bool = trainer.add_transition(
			int(worker["id"]),
			last_sample,
			float(worker["interval_reward"]),
			observation,
			not timed_out,
			timed_out,
			maxf(
				RLTrainingMath.finite_float_or(
					worker.get(
						"interval_elapsed_seconds",
						_safe_control_interval(group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS))
					),
					_safe_control_interval(group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS))
				),
				0.000001
			)
		)
		if not terminal_transition_accepted:
			last_error = trainer.last_error
	worker["episode_result"] = _worker_episode_result(group, worker)
	var turret = _worker_turret(worker)
	if is_instance_valid(turret):
		_cancel_projectiles_for_turret_id(int(turret.get_instance_id()))
	_unregister_combatant(worker.get("combat_adapter") as TrainingCombatantAdapter)
	if is_instance_valid(turret):
		turret.active = false


func _finish_group_episode(group: Dictionary) -> void:
	if bool(group.get("awaiting_respawn", false)):
		return
	var workers: Array = group.get("workers", [])
	var total = 0.0
	var scored_worker_count = 0
	var history = group["history"] as DroneTrainingMetricsHistory
	var expected_scored_workers = 0
	for worker_value: Variant in workers:
		if worker_value is Dictionary and not bool(
			(worker_value as Dictionary).get("manual_touched_this_episode", false)
		):
			expected_scored_workers += 1
	expected_scored_workers = maxi(expected_scored_workers, 1)
	for worker_value: Variant in workers:
		if not (worker_value is Dictionary):
			continue
		var worker = worker_value as Dictionary
		if not bool(worker.get("finished", false)):
			_finish_worker(group, worker, "timeout", true, worker.get("previous_observation", {}))
		if bool(worker.get("manual_touched_this_episode", false)):
			continue
		total += float(worker.get("total_reward", 0.0))
		scored_worker_count += 1
		history.record_episode(worker.get("episode_result", {}), expected_scored_workers)
	var trainer = group["trainer"] as TurretPPOTrainer
	if scored_worker_count > 0:
		var mean = total / float(scored_worker_count)
		group["last_mean_reward"] = mean
		group["best_mean_reward"] = maxf(float(group.get("best_mean_reward", -INF)), mean)
		if evaluation_contract_provider.is_valid():
			var evaluation_contract: Dictionary = evaluation_contract_provider.call(
				int(group.get("group_id", -1)),
				"turret"
			)
			trainer.set_evaluation_contract(evaluation_contract)
		trainer.record_completed_episode(mean)
	group["awaiting_respawn"] = true
	group["respawn_delay_remaining"] = EPISODE_RESPAWN_DELAY_SECONDS
	var force_partial = not trainer.can_update(false) and trainer.rollout.size() >= MINIMUM_BACKGROUND_UPDATE_SAMPLES
	_begin_group_update_if_ready(group, force_partial)
	group_episode_completed.emit(int(group["group_id"]))


func _worker_episode_result(group: Dictionary, worker: Dictionary) -> Dictionary:
	var elapsed = maxf(float(worker.get("episode_elapsed", 0.0)), 0.000001)
	var totals: Dictionary = (worker.get("reward_state", {}) as Dictionary).get("episode_totals", {})
	var result = {
		"episode_number": int(group.get("episode", 0)),
		"episode_elapsed_seconds": elapsed,
		"mean_reward_per_second": float(worker.get("total_reward", 0.0)) / elapsed,
		"distance_m": float(((worker.get("previous_observation", {}) as Dictionary).get("target", {}) as Dictionary).get("distance_m", 0.0)),
		"time_inside_radius_seconds": float(worker.get("time_precisely_aimed_seconds", 0.0)),
		"total_reward": float(worker.get("total_reward", 0.0)),
		"failure_reason": str(worker.get("failure_reason", "")),
		"reward_components": totals.duplicate(true),
	}
	for card_id in TurretRewardDeck.CARD_ORDER:
		result["cumulative_%s_reward" % card_id] = float(totals.get(card_id, 0.0))
	return result


func _on_shot_requested(request: Dictionary, shooter: TurretPhysicalBody3D) -> void:
	if not is_instance_valid(shooter):
		return
	var combat_adapter: TurretTrainingCombatantAdapter = combat_adapters_by_turret_id.get(
		shooter.get_instance_id()
	) as TurretTrainingCombatantAdapter
	if combat_adapter == null or host == null:
		return
	var projectile = TurretTrainingProjectile3D.new()
	projectile.name = "TurretProjectile%08d" % projectile.get_instance_id()
	host.add_child(projectile)
	var group: Dictionary = group_by_id(combat_adapter.group_id)
	var shot_probe: Dictionary = _shot_target_probe(group, shooter, combat_adapter)
	shooter.notify_shot_viability(TurretTrainingTargetSensor.is_viable_shot(
		shooter,
		shot_probe,
		TurretRewardDeck.SHOT_ALIGNMENT_MINIMUM
	))
	var reward_target_group_id: int = (
		int(group.get("target_worker_group_id", -1))
		if not group.is_empty()
		else -1
	)
	if not projectile.configure(
		request,
		combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		reward_target_group_id,
		shot_probe
	):
		projectile.queue_free()
		return
	_track_projectile(combat_adapter.entity_id, projectile)


func _shot_target_probe(
	group: Dictionary,
	shooter: TurretPhysicalBody3D,
	combat_adapter: TurretTrainingCombatantAdapter
) -> Dictionary:
	var fallback_position: Vector3 = shooter.muzzle_position_world() + shooter.aim_direction_world() * 10.0
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker: Dictionary = worker_value as Dictionary
		if _worker_turret(worker) != shooter:
			continue
		var probe_value: Variant = worker.get("latest_target_probe", {})
		if probe_value is Dictionary:
			var previous_probe: Dictionary = probe_value as Dictionary
			var position_value: Variant = previous_probe.get("position_world", fallback_position)
			if position_value is Vector3 and (position_value as Vector3).is_finite():
				fallback_position = position_value
		break
	return TurretTrainingTargetSensor.acquire(
		shooter,
		combat_adapter,
		entity_spatial_hash,
		wall_spatial_hash,
		fallback_position,
		shooter.loadout.gun.maximum_range_m,
		int(group.get("target_worker_group_id", -1)),
		_preferred_target_entity_id(group),
		_resolved_target_for_group(group, fallback_position)
	)


func _track_projectile(turret_id: int, projectile: TurretTrainingProjectile3D) -> void:
	if turret_id <= 0 or not is_instance_valid(projectile):
		return
	var bucket_value: Variant = active_projectiles_by_turret_id.get(turret_id, [])
	var bucket: Array = bucket_value as Array if bucket_value is Array else []
	if not bucket.has(projectile):
		bucket.append(projectile)
	active_projectiles_by_turret_id[turret_id] = bucket
	var resolved_callable: Callable = _on_projectile_resolved.bind(turret_id)
	if not projectile.resolved.is_connected(resolved_callable):
		projectile.resolved.connect(resolved_callable)


func _on_projectile_resolved(
	projectile: TurretTrainingProjectile3D,
	_hit: bool,
	_target: TrainingCombatantAdapter,
	_damage: float,
	turret_id: int
) -> void:
	var bucket_value: Variant = active_projectiles_by_turret_id.get(turret_id, [])
	if not (bucket_value is Array):
		return
	var bucket: Array = bucket_value as Array
	bucket.erase(projectile)
	if bucket.is_empty():
		active_projectiles_by_turret_id.erase(turret_id)
	else:
		active_projectiles_by_turret_id[turret_id] = bucket


func _cancel_projectiles_for_turret_id(
	turret_id: int,
	count_as_misses: bool = false
) -> void:
	var bucket_value: Variant = active_projectiles_by_turret_id.get(turret_id, [])
	active_projectiles_by_turret_id.erase(turret_id)
	if not (bucket_value is Array):
		return
	for projectile_value: Variant in bucket_value as Array:
		var projectile: TurretTrainingProjectile3D = projectile_value as TurretTrainingProjectile3D
		if not is_instance_valid(projectile):
			continue
		if count_as_misses:
			projectile.cancel_as_miss()
		else:
			projectile.cancel_without_reward()


func _cancel_group_projectiles(group: Dictionary) -> void:
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var turret: TurretPhysicalBody3D = _worker_turret(worker_value as Dictionary)
		if is_instance_valid(turret):
			_cancel_projectiles_for_turret_id(int(turret.get_instance_id()))


func _set_group_projectiles_paused(group: Dictionary, paused: bool) -> void:
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var turret: TurretPhysicalBody3D = _worker_turret(worker_value as Dictionary)
		if not is_instance_valid(turret):
			continue
		var turret_id: int = int(turret.get_instance_id())
		var bucket_value: Variant = active_projectiles_by_turret_id.get(turret_id, [])
		if not (bucket_value is Array):
			continue
		for projectile_value: Variant in bucket_value as Array:
			var projectile = projectile_value as TurretTrainingProjectile3D
			if is_instance_valid(projectile):
				projectile.set_simulation_paused(paused)


func _begin_group_update_if_ready(group: Dictionary, force_partial: bool) -> bool:
	var trainer = group["trainer"] as TurretPPOTrainer
	if trainer.has_background_update() or not trainer.can_update(force_partial):
		return false
	var started = trainer.begin_background_update(force_partial)
	if started:
		group["optimizer_waiting"] = true
	return started


func _poll_group_optimizer(group: Dictionary) -> void:
	var trainer = group["trainer"] as TurretPPOTrainer
	if not trainer.has_background_update():
		return
	var metrics = trainer.poll_background_update()
	if metrics.is_empty():
		return
	var stored_metrics: Dictionary = metrics.duplicate(true)
	stored_metrics["update"] = int(stored_metrics.get("update_count", trainer.update_count))
	var exploration: Dictionary = stored_metrics.get("exploration", {})
	stored_metrics["action_standard_deviation_mean"] = float(
		exploration.get("mean", 0.0)
	)
	group["last_update"] = stored_metrics
	group["optimizer_waiting"] = false
	# Any projectile still in flight belongs to the behavior policy that just finished its
	# rollout. Its held action is intentionally discarded at the next control boundary, so a
	# delayed hit/miss from that old policy must not leak into a new-policy reward interval.
	_cancel_group_projectiles(group)
	# Do not resample a live turret in the middle of its current action interval. The next
	# normal control boundary settles the complete old-policy reward/time span first; the
	# trainer then counts-but-discards that stale PPO transition and the freshly sampled policy takes over.
	if not stored_metrics.has("error"):
		(group["history"] as DroneTrainingMetricsHistory).record_update(stored_metrics)
	group_update_completed.emit(int(group["group_id"]))



func _emit_worker_action_applied(
	group: Dictionary,
	worker: Dictionary,
	commands: PackedFloat64Array
) -> void:
	if commands.size() != TurretMLAction.ACTION_COUNT:
		return
	var turret = _worker_turret(worker)
	if not is_instance_valid(turret):
		return
	worker_action_applied.emit(
		int(group.get("group_id", -1)),
		int(group.get("episode", -1)),
		int(worker.get("id", -1)),
		int(turret.get_instance_id()),
		float(worker.get("episode_elapsed", 0.0)),
		commands.duplicate()
	)


func _apply_pending_reward_config(group: Dictionary) -> void:
	var deck: TurretRewardDeck = group.get("reward_deck") as TurretRewardDeck
	if deck == null:
		return
	RewardCardDeckSupport.apply_pending_configuration(group, deck.cards)


func _register_combatant(adapter: TrainingCombatantAdapter) -> void:
	if entity_spatial_hash == null or adapter == null or not is_instance_valid(adapter.body):
		return
	if adapter is TurretTrainingCombatantAdapter:
		combat_adapters_by_turret_id[adapter.entity_id] = adapter
	entity_spatial_hash.register_entity(
		adapter.spatial_key(),
		adapter.body,
		adapter.entity_kind,
		adapter.entity_id,
		adapter.metadata()
	)


func _unregister_combatant(adapter: TrainingCombatantAdapter) -> void:
	if adapter == null:
		return
	if adapter is TurretTrainingCombatantAdapter:
		combat_adapters_by_turret_id.erase(adapter.entity_id)
	if entity_spatial_hash != null:
		entity_spatial_hash.unregister_entity(adapter.spatial_key())


func _clear_group_workers(group: Dictionary) -> void:
	for worker in group.get("workers", []):
		if not (worker is Dictionary):
			continue
		var turret = _worker_turret(worker)
		if is_instance_valid(turret):
			_cancel_projectiles_for_turret_id(int(turret.get_instance_id()))
		_unregister_combatant((worker as Dictionary).get("combat_adapter") as TrainingCombatantAdapter)
		if is_instance_valid(turret):
			turret.queue_free()
	group["workers"] = []


func _all_workers_finished(group: Dictionary) -> bool:
	var workers: Array = group.get("workers", [])
	return not workers.is_empty() and workers.all(func(worker: Variant) -> bool:
		return worker is Dictionary and bool((worker as Dictionary).get("finished", false))
	)


func _worker_turret(worker: Dictionary) -> TurretPhysicalBody3D:
	var value: Variant = worker.get("turret")
	return value as TurretPhysicalBody3D if value != null and is_instance_valid(value) else null


func _group_loadout(group: Dictionary) -> TurretLoadout:
	var loadout = group.get("turret_loadout") as TurretLoadout
	if loadout == null or not loadout.ensure_contract():
		return null
	return loadout


func prepare_group_for_placement(group_id: int) -> bool:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return false
	(group["trainer"] as TurretPPOTrainer).discard_incomplete_rollout()
	group["awaiting_respawn"] = false
	group["respawn_delay_remaining"] = 0.0
	_clear_group_workers(group)
	return true


func clear_group_placement(group_id: int) -> bool:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return false
	var count: int = clampi(int(group.get("worker_count", DEFAULT_WORKER_COUNT)), 1, MAXIMUM_WORKER_COUNT)
	group["worker_placements"] = _new_unconfigured_placements(count)
	_sync_primary_placement_fields(group)
	_clear_group_workers(group)
	return true


func set_group_placement(
	group_id: int,
	position_world: Vector3,
	yaw_degrees: float = 0.0
) -> bool:
	return set_group_worker_placement(group_id, 0, position_world, yaw_degrees)


func set_group_worker_placement(
	group_id: int,
	worker_index: int,
	position_world: Vector3,
	yaw_degrees: float = 0.0
) -> bool:
	var group: Dictionary = group_by_id(group_id)
	last_error = ""
	if (
		group.is_empty()
		or worker_index < 0
		or worker_index >= int(group.get("worker_count", DEFAULT_WORKER_COUNT))
		or not position_world.is_finite()
		or not is_finite(yaw_degrees)
	):
		return false
	_resize_worker_placements(group, int(group.get("worker_count", DEFAULT_WORKER_COUNT)))
	var placements: Array = group.get("worker_placements", [])
	placements[worker_index] = {
		"configured": true,
		"position_world": position_world,
		"yaw_degrees": wrapf(yaw_degrees, -180.0, 180.0),
	}
	group["worker_placements"] = placements
	_sync_primary_placement_fields(group)
	_clear_group_workers(group)
	return true


func append_group_worker_placement(
	group_id: int,
	position_world: Vector3,
	yaw_degrees: float = 0.0
) -> bool:
	var group: Dictionary = group_by_id(group_id)
	last_error = ""
	if (
		group.is_empty()
		or not position_world.is_finite()
		or not is_finite(yaw_degrees)
	):
		return false
	var old_count: int = clampi(int(group.get("worker_count", DEFAULT_WORKER_COUNT)), 1, MAXIMUM_WORKER_COUNT)
	if old_count >= MAXIMUM_WORKER_COUNT:
		last_error = "This turret group already has the maximum of %d workers." % MAXIMUM_WORKER_COUNT
		return false
	_resize_worker_placements(group, old_count)
	var placements: Array = group.get("worker_placements", [])
	placements.append({
		"configured": true,
		"position_world": position_world,
		"yaw_degrees": wrapf(yaw_degrees, -180.0, 180.0),
	})
	group["worker_placements"] = placements
	group["worker_count"] = old_count + 1
	group["pending_worker_count"] = old_count + 1
	_sync_primary_placement_fields(group)
	(group["trainer"] as TurretPPOTrainer).discard_incomplete_rollout()
	# Adding a worker is configured while the group is paused. Keep the already placed
	# turrets visible and frozen; set_group_active(true) rebuilds the population when it sees
	# that the authored worker count is now larger than the live population.
	return true


func group_placement_transform(group_id: int) -> Transform3D:
	return group_worker_placement_transform(group_id, 0)


func group_worker_placement_transform(group_id: int, worker_index: int) -> Transform3D:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return Transform3D.IDENTITY
	return _placement_transform_from_dictionary(_worker_placement(group, worker_index))


func group_worker_placement_yaw_degrees(group_id: int, worker_index: int) -> float:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return 0.0
	return RLTrainingMath.finite_float_or(
		_worker_placement(group, worker_index).get("yaw_degrees", 0.0),
		0.0
	)


func group_worker_count(group_id: int) -> int:
	var group: Dictionary = group_by_id(group_id)
	return (
		clampi(int(group.get("worker_count", DEFAULT_WORKER_COUNT)), 1, MAXIMUM_WORKER_COUNT)
		if not group.is_empty()
		else 0
	)


func group_can_add_worker(group_id: int) -> bool:
	return group_worker_count(group_id) < MAXIMUM_WORKER_COUNT


func set_group_target_worker(group_id: int, target_group_id: int) -> bool:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty() or target_group_id == group_id:
		return false
	var normalized_target_group_id: int = target_group_id if target_group_id >= 0 else -1
	if int(group.get("target_worker_group_id", -1)) == normalized_target_group_id:
		return true
	# Changing the task target is an action/reward boundary, not an episode reset. Cancel rounds
	# fired for the old task and force the next physics tick to sample a fresh action so one PPO
	# transition cannot straddle two different target groups.
	_cancel_group_projectiles(group)
	var control_interval: float = _safe_control_interval(
		group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)
	)
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker: Dictionary = worker_value as Dictionary
		worker["last_action_sample"] = {}
		worker["interval_reward"] = 0.0
		worker["interval_elapsed_seconds"] = 0.0
		worker["decision_elapsed"] = control_interval
		worker["previous_commands"] = TurretMLAction.neutral_commands()
		var turret: TurretPhysicalBody3D = _worker_turret(worker)
		if is_instance_valid(turret):
			turret.consume_weapon_events()
			turret.submit_raw_commands(TurretMLAction.neutral_commands())
	group["target_worker_group_id"] = normalized_target_group_id
	group["resolved_target_entity_id"] = -1
	group["resolved_target"] = {}
	return true


func _fallback_resolved_target(position_world: Vector3) -> Dictionary:
	var safe_position: Vector3 = position_world if position_world.is_finite() else Vector3.ZERO
	return {
		"available": true,
		"stable_id": "turret-coordinator:fallback-objective",
		"system_type_id": "fallback",
		"target_kind": "navigation",
		"shootable": true,
		"position_world": safe_position,
		"velocity_world": Vector3.ZERO,
		"radius_m": 0.75,
		"metadata": {},
	}


func _resolved_target_for_group(group: Dictionary, fallback_position: Vector3) -> Dictionary:
	var resolved_value: Variant = group.get("resolved_target", {})
	if resolved_value is Dictionary and not (resolved_value as Dictionary).is_empty():
		var resolved: Dictionary = resolved_value as Dictionary
		var position_value: Variant = resolved.get("position_world", null)
		if position_value is Vector3 and (position_value as Vector3).is_finite():
			return resolved
	return _fallback_resolved_target(fallback_position)


func _resolved_target_entity_id(group: Dictionary, resolved_target: Dictionary) -> int:
	if int(group.get("target_worker_group_id", -1)) < 0:
		return -1
	var metadata_value: Variant = resolved_target.get("metadata", {})
	if not (metadata_value is Dictionary):
		return -1
	var metadata: Dictionary = metadata_value as Dictionary
	return maxi(RLTrainingMath.finite_int_or(metadata.get("target_entity_id", -1), -1), -1)


func _preferred_target_entity_id(group: Dictionary) -> int:
	if int(group.get("target_worker_group_id", -1)) < 0:
		return -1
	return maxi(RLTrainingMath.finite_int_or(group.get("resolved_target_entity_id", -1), -1), -1)


func _group_spawn_transform(
	group: Dictionary,
	worker_index: int,
	worker_count: int,
	arena_size: Vector3
) -> Transform3D:
	var placement: Dictionary = _worker_placement(group, worker_index)
	if bool(placement.get("configured", false)):
		return _placement_transform_from_dictionary(placement)
	return _worker_spawn_transform(worker_index, worker_count, arena_size)


func _new_unconfigured_placements(count: int) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	for _index in range(clampi(count, 1, MAXIMUM_WORKER_COUNT)):
		placements.append({"configured": false})
	return placements


func _resize_worker_placements(group: Dictionary, requested_count: int) -> void:
	var count: int = clampi(requested_count, 1, MAXIMUM_WORKER_COUNT)
	var placements_value: Variant = group.get("worker_placements", [])
	var placements: Array = []
	if placements_value is Array:
		placements = placements_value as Array
	while placements.size() < count:
		placements.append({"configured": false})
	while placements.size() > count:
		placements.remove_at(placements.size() - 1)
	group["worker_placements"] = placements
	_sync_primary_placement_fields(group)


func _worker_placement(group: Dictionary, worker_index: int) -> Dictionary:
	var placements_value: Variant = group.get("worker_placements", [])
	if not (placements_value is Array):
		return {"configured": false}
	var placements: Array = placements_value as Array
	if worker_index < 0 or worker_index >= placements.size():
		return {"configured": false}
	var value: Variant = placements[worker_index]
	return value as Dictionary if value is Dictionary else {"configured": false}


func _all_worker_placements_configured(group: Dictionary) -> bool:
	var count: int = clampi(int(group.get("worker_count", DEFAULT_WORKER_COUNT)), 1, MAXIMUM_WORKER_COUNT)
	var placements_value: Variant = group.get("worker_placements", [])
	if not (placements_value is Array) or (placements_value as Array).size() != count:
		return false
	for index in range(count):
		if not bool(_worker_placement(group, index).get("configured", false)):
			return false
	return true


func _sync_primary_placement_fields(group: Dictionary) -> void:
	var first: Dictionary = _worker_placement(group, 0)
	var configured: bool = bool(first.get("configured", false))
	var position_value: Variant = first.get("position_world", Vector3.ZERO)
	group["placement_position"] = (
		position_value as Vector3
		if position_value is Vector3 and (position_value as Vector3).is_finite()
		else Vector3.ZERO
	)
	group["placement_yaw_degrees"] = RLTrainingMath.finite_float_or(
		first.get("yaw_degrees", 0.0),
		0.0
	)
	group["placement_configured"] = _all_worker_placements_configured(group) if configured else false


func _placement_transform_from_dictionary(placement: Dictionary) -> Transform3D:
	var position_value: Variant = placement.get("position_world", Vector3.ZERO)
	var position_world: Vector3 = (
		position_value as Vector3
		if position_value is Vector3 and (position_value as Vector3).is_finite()
		else Vector3.ZERO
	)
	var yaw_degrees: float = RLTrainingMath.finite_float_or(
		placement.get("yaw_degrees", 0.0),
		0.0
	)
	var transform: Transform3D = Transform3D.IDENTITY
	transform.basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	transform.origin = position_world
	return transform


func _placement_dictionary_from_internal(placement: Dictionary) -> Dictionary:
	if not bool(placement.get("configured", false)):
		return {"configured": false}
	var transform: Transform3D = _placement_transform_from_dictionary(placement)
	return {
		"configured": true,
		"position": [transform.origin.x, transform.origin.y, transform.origin.z],
		"yaw_degrees": RLTrainingMath.finite_float_or(
			placement.get("yaw_degrees", 0.0),
			0.0
		),
	}


func _placements_dictionary_array(group: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count: int = clampi(int(group.get("worker_count", DEFAULT_WORKER_COUNT)), 1, MAXIMUM_WORKER_COUNT)
	for index in range(count):
		result.append(_placement_dictionary_from_internal(_worker_placement(group, index)))
	return result


func _parse_placement_dictionary(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var placement: Dictionary = value as Dictionary
	if not (placement.get("configured", false) is bool):
		return {}
	if not bool(placement.get("configured", false)):
		return {"configured": false}
	var position_value: Variant = placement.get("position", [])
	if not (position_value is Array) or (position_value as Array).size() != 3:
		return {}
	var position_array: Array = position_value as Array
	var x_value: float = RLTrainingMath.finite_float_or(position_array[0], NAN)
	var y_value: float = RLTrainingMath.finite_float_or(position_array[1], NAN)
	var z_value: float = RLTrainingMath.finite_float_or(position_array[2], NAN)
	var yaw_degrees: float = RLTrainingMath.finite_float_or(placement.get("yaw_degrees"), NAN)
	if (
		not is_finite(x_value)
		or not is_finite(y_value)
		or not is_finite(z_value)
		or not is_finite(yaw_degrees)
	):
		return {}
	return {
		"configured": true,
		"position_world": Vector3(x_value, y_value, z_value),
		"yaw_degrees": wrapf(yaw_degrees, -180.0, 180.0),
	}


func _parse_placements_array(value: Variant, expected_count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array) or (value as Array).size() != expected_count:
		return result
	for placement_value: Variant in (value as Array):
		var parsed: Dictionary = _parse_placement_dictionary(placement_value)
		if parsed.is_empty():
			return []
		result.append(parsed)
	return result


func _worker_spawn_transform(worker_index: int, worker_count: int, arena_size: Vector3) -> Transform3D:
	var half_x = maxf(arena_size.x * 0.5 - SPAWN_EDGE_INSET_M, 2.0)
	var half_z = maxf(arena_size.z * 0.5 - SPAWN_EDGE_INSET_M, 2.0)
	var perimeter_positions: Array[Vector3] = [
		Vector3(-half_x, 0.0, -half_z),
		Vector3(half_x, 0.0, half_z),
		Vector3(half_x, 0.0, -half_z),
		Vector3(-half_x, 0.0, half_z),
		Vector3(0.0, 0.0, -half_z),
		Vector3(0.0, 0.0, half_z),
		Vector3(-half_x, 0.0, 0.0),
		Vector3(half_x, 0.0, 0.0),
	]
	var position = perimeter_positions[worker_index % perimeter_positions.size()]
	var facing = -position
	facing.y = 0.0
	var transform = Transform3D.IDENTITY
	transform.origin = position
	if facing.length_squared() > 0.000001:
		transform = transform.looking_at(position + facing.normalized(), Vector3.UP)
	return transform


func _safe_control_interval(value: Variant) -> float:
	return TrainingCoordinatorGroupState.safe_control_interval(
		value,
		DECISION_INTERVAL_SECONDS
	)
