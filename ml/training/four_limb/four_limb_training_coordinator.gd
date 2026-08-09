class_name FourLimbTrainingCoordinator
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

const DEFAULT_WORKER_COUNT = 4
const MAXIMUM_WORKER_COUNT = 16
const MAXIMUM_GROUP_COUNT = 9
const DECISION_INTERVAL_SECONDS = 0.05
const MAXIMUM_EPISODE_SECONDS = 600.0
const MINIMUM_BACKGROUND_UPDATE_SAMPLES = 64
const EPISODE_RESPAWN_DELAY_SECONDS = 1.0
const WORKER_SPACING_M = 3.0
const STARTUP_SETTLE_SECONDS = 0.35
const CONTROL_RAMP_SECONDS = 0.0
# Keep feet just above contact so the articulated body settles without a destructive drop.
const SPAWN_FLOOR_CLEARANCE_M = 0.03
const ARENA_BOUNDARY_BUFFER_M = 0.08
const ARENA_FALL_CUTOFF_M = -2.0
const WORKER_OFFSETS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(-1.0, 0.0),
	Vector2(1.0, 0.0),
	Vector2(0.0, -1.0),
	Vector2(0.0, 1.0),
	Vector2(-1.0, -1.0),
	Vector2(1.0, -1.0),
	Vector2(-1.0, 1.0),
	Vector2(1.0, 1.0),
	Vector2(-2.0, 0.0),
	Vector2(2.0, 0.0),
	Vector2(0.0, -2.0),
	Vector2(0.0, 2.0),
	Vector2(-2.0, -1.0),
	Vector2(2.0, -1.0),
	Vector2(-2.0, 1.0),
]

var host: Node3D
var wall_spatial_hash: DroneTrainingWallSpatialHash
var entity_spatial_hash: ServerSpatialHash3D
var evaluation_contract_provider: Callable
var item_candidate_provider: Callable
var item_fallback_type_provider: Callable
var delivery_destination_provider: Callable
var preset_body_template: FourLimbBodyDefinition
var groups: Array[Dictionary] = []
var groups_by_id: Dictionary = {}
var last_error = ""


func _init(owner: Node3D = null) -> void:
	host = owner
	preset_body_template = _create_training_body_from_preset()


static func _create_training_body_from_preset() -> FourLimbBodyDefinition:
	var definition = MLBodyPresetLibrary.four_limb_walker_definition()
	# Training bodies should survive ordinary falls and violent early exploration. Gameplay
	# bodies keep their authored values; only this training copy receives the durability override.
	definition.core_maximum_health = 1000000.0
	definition.linear_damp = maxf(definition.linear_damp, 0.45)
	definition.angular_damp = maxf(definition.angular_damp, 0.90)
	for limb: FourLimbSlotDefinition in definition.limbs:
		if limb != null:
			limb.maximum_health = 1000000.0
	return definition


func create_group(
	group_id: int,
	group_name: String,
	color: Color,
	worker_count: int = DEFAULT_WORKER_COUNT,
	initial_body_definition: FourLimbBodyDefinition = null,
	network_config: Dictionary = {}
) -> Dictionary:
	last_error = ""
	if host == null or not is_instance_valid(host):
		last_error = "The shared training room is not available."
		return {}
	if groups_by_id.has(group_id):
		last_error = "A four-limb group already uses id %d." % group_id
		return {}
	if groups.size() >= MAXIMUM_GROUP_COUNT:
		last_error = "The shared arena supports up to %d four-limb groups at once." % MAXIMUM_GROUP_COUNT
		return {}
	var group_definition: FourLimbBodyDefinition
	if initial_body_definition != null:
		group_definition = (
			initial_body_definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
		)
	else:
		group_definition = preset_body_template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
	group_definition.ensure_contract()
	var group = {
		"group_id": group_id,
		"body_type": "four_limb",
		"name": group_name,
		"color": color,
		"body_definition": group_definition,
		"body_revision": 0,
		"parent_group_id": -1,
		"branch_weight_variation": 0.0,
		"source_description": "Fresh four-limb policy",
		# Rolling saves are group-owned and enabled by default. A branch or loaded model
		# starts a fresh chain so its source checkpoint is never overwritten.
		"overwrite_saved_versions": true,
		"rolling_version_id": "",
		"trainer": FourLimbPPOTrainer.new(7340033 + group_id * 97, network_config),
		"reward_deck": FourLimbRewardDeck.new(),
		"reward_cardset_id": "builtin:limb_ground",
		"reward_cardset_name": "Ground Locomotion",
		"pending_reward_config": {},
		"workers": [],
		"worker_count": clampi(worker_count, 1, MAXIMUM_WORKER_COUNT),
		"pending_worker_count": clampi(worker_count, 1, MAXIMUM_WORKER_COUNT),
		"control_interval_seconds": DECISION_INTERVAL_SECONDS,
		"active": false,
		"episode": 0,
		"last_mean_reward": 0.0,
		"best_mean_reward": -INF,
		"last_update": {},
		"last_reward_state": {},
		"optimizer_waiting": false,
		"respawn_delay_remaining": 0.0,
		"awaiting_respawn": false,
		"history": DroneTrainingMetricsHistory.new(),
		"card": null,
		"card_button": null,
		"pause_button": null,
		"activity_label": null,
		"candidate_evaluation_label": null,
		"candidate_evaluation_queue_position": 0,
		"candidate_evaluation_queue_ticket": 0,
		"candidate_evaluation_queued_candidate_id": -1,
		"candidate_evaluation_started_usec": 0,
		"candidate_evaluation_subject": "",
		"candidate_evaluation_last_result": {},
		"best_score_label": null,
		"worker_slider": null,
		"worker_slider_dragging": false,
		"worker_label": null,
		"name_edit": null,
		"reward_label": null,
		"hardware_label": null,
		"overwrite_button": null,
		"card_minimum_height": 0.0,
	}
	groups.append(group)
	groups_by_id[group_id] = group
	return group


func group_by_id(group_id: int) -> Dictionary:
	return groups_by_id.get(group_id, {})


func group_body_definition(group_id: int) -> FourLimbBodyDefinition:
	var group = group_by_id(group_id)
	return _group_body_definition(group) if not group.is_empty() else null


func replace_group_body_definition(
	group_id: int,
	definition: FourLimbBodyDefinition
) -> bool:
	last_error = ""
	var group = group_by_id(group_id)
	if group.is_empty() or definition == null:
		last_error = "The selected four-limb group or body definition is unavailable."
		return false
	if bool(group.get("active", false)):
		last_error = "Pause the four-limb group before changing its physical body."
		return false
	var private_definition = definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
	private_definition.ensure_contract()
	group["body_definition"] = private_definition
	group["body_revision"] = int(group.get("body_revision", 0)) + 1
	(group["trainer"] as FourLimbPPOTrainer).discard_incomplete_rollout()
	_clear_group_workers(group)
	group["awaiting_respawn"] = false
	group["respawn_delay_remaining"] = 0.0
	return true


func reset_group_body_definition(group_id: int) -> bool:
	return replace_group_body_definition(group_id, _create_training_body_from_preset())


func remove_group(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {}
	(group["trainer"] as FourLimbPPOTrainer).shutdown_background_update()
	_clear_group_workers(group)
	groups.erase(group)
	groups_by_id.erase(group_id)
	return group


func set_group_active(
	group_id: int,
	active: bool,
	spawn_origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	target_radius: float,
	episode_duration: float,
	arena_size: Vector3
) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	group["active"] = active
	if (
		active
		and (group.get("workers", []) as Array).is_empty()
		and float(group.get("respawn_delay_remaining", 0.0)) <= 0.0
	):
		_poll_group_optimizer(group)
		_start_group_episode(
			group,
			spawn_origin,
			target_position,
			target_velocity,
			target_radius,
			episode_duration,
			arena_size
		)
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker: Dictionary = worker_value
		var body = _worker_body(worker)
		var worker_runtime_active: bool = (
			active
			and not bool(worker.get("finished", false))
			and not bool(group.get("awaiting_respawn", false))
		)
		if is_instance_valid(body) and is_instance_valid(body.physical_rig):
			body.physical_rig.set_runtime_active(worker_runtime_active)
		var combat_adapter = worker.get("combat_adapter") as TrainingCombatantAdapter
		if combat_adapter != null:
			combat_adapter.set_simulation_active(worker_runtime_active)
		_set_private_task_item_simulation_active(worker, worker_runtime_active)
	return true


static func _set_private_task_item_simulation_active(worker: Dictionary, active: bool) -> void:
	var pickup_item: TrainingItem3D = worker.get("pickup_item") as TrainingItem3D
	if is_instance_valid(pickup_item) and pickup_item is FourLimbTrainingGrabbableItem3D:
		# Fallback lesson props are private to this worker, so they must pause/finish with the
		# worker. Shared authored Training Items are coordinated by the room because another
		# active group may legitimately be interacting with the same physical object.
		pickup_item.set_simulation_active(active)


static func _recover_lost_private_task_item(worker: Dictionary, arena_size: Vector3) -> bool:
	var pickup_item: TrainingItem3D = worker.get("pickup_item") as TrainingItem3D
	if (
		not is_instance_valid(pickup_item)
		or not (pickup_item is FourLimbTrainingGrabbableItem3D)
		or not pickup_item.needs_recovery(arena_size)
	):
		return false
	pickup_item.reset_to_spawn()
	return true


func restart_group_for_configuration_change(
	group_id: int,
	spawn_origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	target_radius: float,
	episode_duration: float,
	arena_size: Vector3
) -> bool:
	var group: Dictionary = group_by_id(group_id)
	if group.is_empty():
		return false
	(group["trainer"] as FourLimbPPOTrainer).discard_incomplete_rollout()
	group["awaiting_respawn"] = false
	group["respawn_delay_remaining"] = 0.0
	# A target-generator edit is an episode-semantic boundary, not ordinary target motion.
	# Rebuild only this group's episode so one rollout never mixes two task configurations.
	_clear_group_workers(group)
	if bool(group.get("active", false)):
		_start_group_episode(
			group,
			spawn_origin,
			target_position,
			target_velocity,
			target_radius,
			episode_duration,
			arena_size
		)
	return true


func set_worker_count(group_id: int, requested_count: int) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	var worker_count = clampi(
		requested_count,
		1,
		MAXIMUM_WORKER_COUNT
	)
	group["pending_worker_count"] = worker_count
	if not bool(group.get("active", false)):
		group["worker_count"] = worker_count
		# A paused limb group may still own frozen physical workers. Worker-count edits are a
		# configuration boundary, so retire the partial on-policy rollout and rebuild the
		# requested population on resume.
		(group["trainer"] as FourLimbPPOTrainer).discard_incomplete_rollout()
		_clear_group_workers(group)
		group["awaiting_respawn"] = false
		group["respawn_delay_remaining"] = 0.0
	return true


func apply_worker_count_now(
	group_id: int,
	requested_count: int,
	spawn_origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	target_radius: float,
	episode_duration: float,
	arena_size: Vector3
) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	var worker_count = clampi(requested_count, 1, MAXIMUM_WORKER_COUNT)
	var current_count = int(group.get("worker_count", DEFAULT_WORKER_COUNT))
	var pending_count = int(group.get("pending_worker_count", current_count))
	if current_count == worker_count and pending_count == worker_count:
		return true
	group["pending_worker_count"] = worker_count
	if not bool(group.get("active", false)):
		group["worker_count"] = worker_count
		(group["trainer"] as FourLimbPPOTrainer).discard_incomplete_rollout()
		_clear_group_workers(group)
		group["awaiting_respawn"] = false
		group["respawn_delay_remaining"] = 0.0
		return true
	(group["trainer"] as FourLimbPPOTrainer).discard_incomplete_rollout()
	group["awaiting_respawn"] = false
	group["respawn_delay_remaining"] = 0.0
	_start_group_episode(
		group,
		spawn_origin,
		target_position,
		target_velocity,
		target_radius,
		episode_duration,
		arena_size
	)
	return true


func set_control_interval(group_id: int, seconds: float) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	group["control_interval_seconds"] = _safe_control_interval(seconds)
	var trainer = group["trainer"]
	trainer.config["control_interval_seconds"] = group["control_interval_seconds"]
	trainer._sanitize_config()
	# The UI requires limb workers to be paused before changing this value. Since pause now
	# preserves the open action interval/rollout, changing its temporal contract is a real
	# configuration boundary rather than something that may be mixed into old PPO samples.
	(group["trainer"] as FourLimbPPOTrainer).discard_incomplete_rollout()
	return true


func episode_progress_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for group: Dictionary in groups:
		var workers: Array = group.get("workers", [])
		var valid_instances = 0
		var unfinished_instances = 0
		var elapsed = 0.0
		var duration = 0.0
		for worker_value: Variant in workers:
			if not (worker_value is Dictionary):
				continue
			var worker: Dictionary = worker_value
			var body = _worker_body(worker)
			if not is_instance_valid(body):
				continue
			valid_instances += 1
			if not bool(worker.get("finished", false)):
				unfinished_instances += 1
			elapsed = maxf(elapsed, float(worker.get("episode_elapsed", 0.0)))
			duration = maxf(duration, float(worker.get("episode_duration", 0.0)))
		summaries.append({
			"group_id": int(group["group_id"]),
			"name": str(group["name"]),
			"active": bool(group.get("active", false)),
			"episode": int(group.get("episode", 0)),
			"elapsed": elapsed,
			"duration": duration,
			"instance_count": valid_instances,
			"unfinished_instance_count": unfinished_instances,
			"awaiting_respawn": bool(group.get("awaiting_respawn", false)),
		})
	return summaries


func tick(
	delta: float,
	spawn_origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	target_radius: float,
	episode_duration: float,
	arena_size: Vector3,
	targets_by_group: Dictionary = {}
) -> void:
	for group: Dictionary in groups:
		var trainer = group["trainer"] as FourLimbPPOTrainer
		_poll_group_optimizer(group)
		group["optimizer_waiting"] = trainer.has_background_update()
		if not bool(group.get("active", false)):
			continue
		var group_target: Dictionary = targets_by_group.get(int(group.get("group_id", -1)), {})
		var group_target_position: Vector3 = group_target.get("position_world", target_position)
		var group_target_velocity: Vector3 = group_target.get("velocity_world", target_velocity)
		var group_target_radius: float = maxf(float(group_target.get("radius_m", target_radius)), 0.05)
		var metadata_value: Variant = group_target.get("metadata", {})
		group["current_target_metadata"] = (
			(metadata_value as Dictionary).duplicate(false)
			if metadata_value is Dictionary
			else {}
		)
		_tick_group(
			group,
			delta,
			spawn_origin,
			group_target_position,
			group_target_velocity,
			group_target_radius,
			episode_duration,
			arena_size
		)


func shutdown() -> void:
	for group: Dictionary in groups:
		(group["trainer"] as FourLimbPPOTrainer).shutdown_background_update()
		_clear_group_workers(group)
	groups.clear()
	groups_by_id.clear()


func save_checkpoint(group_id: int, use_best_policy: bool = false) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {}
	var definition = _group_body_definition(group)
	if definition == null:
		last_error = "The four-limb group has no accepted body definition."
		return {}
	var trainer = group["trainer"] as FourLimbPPOTrainer
	var checkpoint = trainer.to_checkpoint(
		definition.hardware_signature(),
		(group["reward_deck"] as FourLimbRewardDeck).configuration_dictionary(),
		use_best_policy
	)
	if checkpoint.is_empty():
		last_error = trainer.last_error
		return {}
	checkpoint["body_definition"] = definition.to_dictionary()
	if evaluation_contract_provider.is_valid():
		var current_contract: Dictionary = evaluation_contract_provider.call(group_id, "four_limb")
		if RLEvaluationContract.is_valid(current_contract, "four_limb"):
			checkpoint["current_room_evaluation_contract"] = current_contract
	if use_best_policy:
		var best_contract: Dictionary = trainer.best_evaluation_contract_snapshot()
		if RLEvaluationContract.is_valid(best_contract, "four_limb"):
			checkpoint["best_evaluation_contract"] = best_contract
	checkpoint["room_settings"] = {
		"worker_count": int(group.get("pending_worker_count", group.get("worker_count", DEFAULT_WORKER_COUNT))),
		"control_interval_seconds": _safe_control_interval(group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)),
	}
	checkpoint["reward_cardset"] = {
		"id": str(group.get("reward_cardset_id", "custom")),
		"display_name": str(group.get("reward_cardset_name", "Custom")),
	}
	return checkpoint


func evaluation_candidate_checkpoint(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {}
	var definition = _group_body_definition(group)
	if definition == null:
		last_error = "The four-limb group has no accepted body definition."
		return {}
	var trainer = group["trainer"] as FourLimbPPOTrainer
	var checkpoint = trainer.candidate_checkpoint(
		definition.hardware_signature(),
		(group["reward_deck"] as FourLimbRewardDeck).configuration_dictionary()
	)
	if checkpoint.is_empty():
		return {}
	checkpoint["body_definition"] = definition.to_dictionary()
	checkpoint["room_settings"] = {
		"worker_count": int(group.get("pending_worker_count", group.get("worker_count", DEFAULT_WORKER_COUNT))),
		"control_interval_seconds": _safe_control_interval(group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)),
	}
	return checkpoint


func pending_evaluation_candidate(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	return (group["trainer"] as FourLimbPPOTrainer).pending_evaluation_candidate() if not group.is_empty() else {}


func record_deterministic_evaluation(
	group_id: int,
	candidate_id: int,
	evaluation_summary: Dictionary
) -> Dictionary:
	var group = group_by_id(group_id)
	if group.is_empty():
		return {"promoted": false, "reason": "missing_group"}
	return (group["trainer"] as FourLimbPPOTrainer).record_deterministic_evaluation(
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
	return (group["trainer"] as FourLimbPPOTrainer).record_deterministic_evaluation_records(
		candidate_id,
		records
	)


func best_selection_summary(group_id: int) -> Dictionary:
	var group = group_by_id(group_id)
	return (group["trainer"] as FourLimbPPOTrainer).best_selection_summary() if not group.is_empty() else {}


func load_checkpoint(group_id: int, checkpoint: Dictionary) -> bool:
	last_error = ""
	var group = group_by_id(group_id)
	if group.is_empty():
		last_error = "Select a four-limb worker group first."
		return false
	var stored_definition: Variant = checkpoint.get("body_definition", {})
	var reward_cards_value: Variant = checkpoint.get("reward_cards", {})
	var reward_cardset_value: Variant = checkpoint.get("reward_cardset", {})
	var room_settings_value: Variant = checkpoint.get("room_settings", {})
	if (
		not (stored_definition is Dictionary)
		or not (reward_cards_value is Dictionary)
		or not (reward_cardset_value is Dictionary)
		or not (room_settings_value is Dictionary)
	):
		last_error = "The four-limb checkpoint contains malformed room metadata."
		return false
	var checkpoint_definition = _group_body_definition(group)
	var stored_definition_dictionary: Dictionary = stored_definition as Dictionary
	if not stored_definition_dictionary.is_empty():
		checkpoint_definition = FourLimbBodyDefinition.from_dictionary(
			stored_definition_dictionary
		)
	if checkpoint_definition == null:
		last_error = "The checkpoint and selected group do not contain a valid four-limb body definition."
		return false
	var trainer = group["trainer"] as FourLimbPPOTrainer
	if not trainer.load_checkpoint(
		checkpoint,
		checkpoint_definition.hardware_signature()
	):
		last_error = (
			trainer.last_error
			if not trainer.last_error.is_empty()
			else "The selected checkpoint is not compatible with this four-limb body."
		)
		return false
	group["optimizer_waiting"] = false
	group["body_definition"] = checkpoint_definition
	group["body_revision"] = int(group.get("body_revision", 0)) + 1
	var reward_cards: Dictionary = reward_cards_value as Dictionary
	(group["reward_deck"] as FourLimbRewardDeck).load_configuration(reward_cards)
	var reward_cardset: Dictionary = reward_cardset_value as Dictionary
	group["reward_cardset_id"] = str(reward_cardset.get("id", "custom"))
	group["reward_cardset_name"] = str(reward_cardset.get("display_name", "Custom"))
	var room_settings: Dictionary = room_settings_value as Dictionary
	if not room_settings.is_empty():
		group["pending_worker_count"] = clampi(
			RLTrainingMath.finite_int_or(
				room_settings.get("worker_count"),
				int(group.get("pending_worker_count", DEFAULT_WORKER_COUNT))
			),
			1,
			MAXIMUM_WORKER_COUNT
		)
		group["control_interval_seconds"] = _safe_control_interval(
			room_settings.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)
		)
	group["pending_reward_config"] = {}
	group["episode"] = trainer.completed_episodes
	group["best_mean_reward"] = trainer.best_episode_score
	group["last_update"] = trainer.last_metrics.duplicate(true)
	_clear_group_workers(group)
	(group["history"] as DroneTrainingMetricsHistory).reset()
	group["respawn_delay_remaining"] = 0.0
	group["awaiting_respawn"] = false
	return true


func apply_pending_reward_config(group: Dictionary) -> void:
	var pending: Dictionary = group.get("pending_reward_config", {})
	if pending.is_empty():
		return
	var deck = group["reward_deck"] as FourLimbRewardDeck
	for card_id: String in pending:
		var card_value = deck.card(card_id)
		if card_value == null:
			continue
		var values: Dictionary = pending[card_id]
		card_value.load_dictionary(values)
	group["pending_reward_config"] = {}
	group["reward_cardset_id"] = str(group.get("pending_reward_cardset_id", "custom"))
	group["reward_cardset_name"] = str(group.get("pending_reward_cardset_name", "Custom"))
	group.erase("pending_reward_cardset_id")
	group.erase("pending_reward_cardset_name")


func _start_group_episode(
	group: Dictionary,
	spawn_origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	target_radius: float,
	episode_duration: float,
	arena_size: Vector3
) -> void:
	apply_pending_reward_config(group)
	var episode_trainer: FourLimbPPOTrainer = group["trainer"] as FourLimbPPOTrainer
	if evaluation_contract_provider.is_valid():
		var episode_contract: Dictionary = evaluation_contract_provider.call(
			int(group.get("group_id", -1)),
			"four_limb"
		)
		episode_trainer.set_evaluation_contract(episode_contract)
	group["worker_count"] = clampi(
		int(group.get("pending_worker_count", group.get("worker_count", DEFAULT_WORKER_COUNT))),
		1,
		MAXIMUM_WORKER_COUNT
	)
	var worker_count = int(group["worker_count"])
	var existing_workers: Array = group.get("workers", [])
	if existing_workers.size() != worker_count:
		_clear_group_workers(group)
		existing_workers = []
	var trainer: FourLimbPPOTrainer = episode_trainer
	var group_body_definition: FourLimbBodyDefinition = _group_body_definition(group)
	if group_body_definition == null:
		last_error = "The four-limb group has no accepted body definition."
		group["active"] = false
		return
	group["optimizer_waiting"] = trainer.has_background_update()
	group["respawn_delay_remaining"] = 0.0
	group["awaiting_respawn"] = false
	group["episode"] = int(group.get("episode", 0)) + 1
	group_episode_started.emit(int(group["group_id"]), int(group["episode"]))
	var objective = _objective(group, target_position, target_velocity, target_radius)
	var initial_target: Vector3 = objective["target_position_world"]
	var delivery_training_enabled = _reward_card_enabled(group, "item_delivery")
	var item_task_enabled = _group_requires_task_item(group)
	var workers: Array[Dictionary] = []
	for worker_index in range(worker_count):
		var spawn = _worker_spawn_transform(
			group,
			worker_index,
			worker_count,
			spawn_origin,
			arena_size
		)
		var body: FourLimbPhysicalBody3D = null
		var adapter: FourLimbMLBodyAdapter = null
		if worker_index < existing_workers.size() and existing_workers[worker_index] is Dictionary:
			var existing_worker: Dictionary = existing_workers[worker_index]
			body = _worker_body(existing_worker)
			adapter = existing_worker.get("adapter") as FourLimbMLBodyAdapter
		if not is_instance_valid(body):
			body = FourLimbPhysicalBody3D.new()
			body.name = "FourLimbGroup%02dWorker%03d" % [int(group["group_id"]), worker_index]
			body.definition = group_body_definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
			body.training_invulnerable = true
			body.auto_start_simulation = true
			body.transform = spawn
			host.add_child(body)
			adapter = FourLimbMLBodyAdapter.new(body)
		else:
			body.training_invulnerable = true
			if adapter == null:
				adapter = FourLimbMLBodyAdapter.new(body)
			# Match the drone episode reset path: reuse the same body node, rebuild its physical
			# state at the shared spawn transform, restore health, and immediately resume physics.
			adapter.reset_body(spawn, int(group["episode"]) * 1000 + worker_index)
		var combat_adapter = FourLimbTrainingCombatantAdapter.new(
			body,
			int(body.get_instance_id()),
			int(group["group_id"]),
			worker_index,
			1
		)
		_register_combatant(combat_adapter)
		var previous_pickup_item: TrainingItem3D = null
		if worker_index < existing_workers.size() and existing_workers[worker_index] is Dictionary:
			previous_pickup_item = (existing_workers[worker_index] as Dictionary).get(
				"pickup_item"
			) as TrainingItem3D
		# Authored items are shared task objects. Do not hide a single item from sibling workers:
		# multiple policies may need to perceive/compete for the same take-or-deliver objective.
		var pickup_item: TrainingItem3D = _room_training_item_for_worker(
			spawn.origin,
			[],
			int(group.get("group_id", -1))
		)
		if is_instance_valid(pickup_item):
			if (
				is_instance_valid(previous_pickup_item)
				and previous_pickup_item is FourLimbTrainingGrabbableItem3D
				and previous_pickup_item != pickup_item
			):
				previous_pickup_item.queue_free()
		elif item_task_enabled:
			var fallback_item: FourLimbTrainingGrabbableItem3D = (
				previous_pickup_item as FourLimbTrainingGrabbableItem3D
				if previous_pickup_item is FourLimbTrainingGrabbableItem3D
				else null
			)
			if not is_instance_valid(fallback_item):
				fallback_item = FourLimbTrainingGrabbableItem3D.new()
				fallback_item.name = "FourLimbGroup%02dPickup%03d" % [
					int(group["group_id"]),
					worker_index,
				]
				host.add_child(fallback_item)
			var fallback_item_type: String = TrainingItem3D.DEFAULT_ITEM_TYPE
			if delivery_training_enabled and item_fallback_type_provider.is_valid():
				fallback_item_type = TrainingItem3D.normalized_item_type(
					str(item_fallback_type_provider.call(int(group.get("group_id", -1))))
				)
			fallback_item.reset_item(
				_pickup_item_spawn_transform(spawn, initial_target, worker_index),
				body.get_instance_id(),
				fallback_item_type
			)
			pickup_item = fallback_item
		elif (
			is_instance_valid(previous_pickup_item)
			and previous_pickup_item is FourLimbTrainingGrabbableItem3D
		):
			previous_pickup_item.queue_free()
		_add_body_label(body, str(group["name"]), group["color"])
		var initial_commands: PackedFloat64Array = FourLimbMLAction.neutral_commands()
		var worker: Dictionary = {
			"id": worker_index,
			"body": body,
			"adapter": adapter,
			"combat_adapter": combat_adapter,
			"combat_events": {},
			"pickup_item": pickup_item,
			"episode_elapsed": 0.0,
			"elapsed": 0.0,
			"decision_elapsed": 0.0,
			"episode_duration": clampf(episode_duration, 0.1, MAXIMUM_EPISODE_SECONDS),
			"last_action_sample": {},
			"interval_reward": 0.0,
			"interval_elapsed_seconds": 0.0,
			"total_reward": 0.0,
			"previous_physics_observation": {},
			"previous_commands": initial_commands.duplicate(),
			"commands_before_latest_sample": initial_commands.duplicate(),
			"action_change_pending": 0.0,
			"reward_state": (group["reward_deck"] as FourLimbRewardDeck).create_worker_state(),
			"finished": false,
			"failure_reason": "",
			"runtime_fault_reason": "",
			"settle_remaining": STARTUP_SETTLE_SECONDS,
			"time_inside_radius_seconds": 0.0,
			"last_target_distance_m": spawn.origin.distance_to(initial_target),
			"spawn_position_world": spawn.origin,
			"maximum_horizontal_displacement_m": 0.0,
			"episode_result": {},
			"arena_size": arena_size,
		}
		workers.append(worker)
		_prime_worker_action(group, worker, objective)
	group["workers"] = workers
	group["last_reward_state"] = {}


func _prime_worker_action(
	group: Dictionary,
	worker: Dictionary,
	objective: Dictionary
) -> void:
	var adapter = worker.get("adapter") as FourLimbMLBodyAdapter
	if adapter == null:
		_record_worker_fault(worker, "missing_adapter")
		return
	# Settling is deliberately outside the episode/action interval. Building the complete fixed-size
	# observation here (and on every settle physics tick) cannot affect a policy or reward, so defer
	# that work until the first real decision after the rig has settled.
	if float(worker.get("settle_remaining", 0.0)) > 0.0:
		var neutral_commands = FourLimbMLAction.neutral_commands()
		if not adapter.apply_commands(neutral_commands):
			_record_worker_fault(worker, "invalid_neutral_action")
			return
		worker["last_action_sample"] = {}
		worker["previous_commands"] = neutral_commands.duplicate()
		worker["commands_before_latest_sample"] = neutral_commands.duplicate()
		worker["runtime_fault_reason"] = ""
		return
	var body = _worker_body(worker)
	var observation = _capture_worker_observation(
		adapter,
		body,
		objective,
		worker.get("arena_size", Vector3.ZERO),
		worker.get("pickup_item") as TrainingItem3D,
		worker.get("combat_adapter") as FourLimbTrainingCombatantAdapter,
		int(group.get("group_id", -1))
	)
	if observation.is_empty():
		_record_worker_fault(worker, "invalid_observation")
		return
	worker["previous_physics_observation"] = observation
	var sample = (group["trainer"] as FourLimbPPOTrainer).sample_validated_training_action(observation)
	if sample.is_empty():
		_record_worker_fault(worker, "invalid_policy_sample")
		return
	var commands: PackedFloat64Array = sample.get("commands", PackedFloat64Array())
	if commands.size() != FourLimbMLAction.ACTION_COUNT:
		_record_worker_fault(worker, "invalid_policy_action")
		return
	if not adapter.apply_commands(sample.get("commands", PackedFloat64Array())):
		_record_worker_fault(worker, "invalid_policy_action")
		return
	worker["last_action_sample"] = sample
	worker["previous_commands"] = commands
	worker["commands_before_latest_sample"] = FourLimbMLAction.neutral_commands()
	worker["runtime_fault_reason"] = ""
	_emit_worker_action_applied(group, worker, commands)


func _tick_group(
	group: Dictionary,
	delta: float,
	spawn_origin: Vector3,
	target_position: Vector3,
	target_velocity: Vector3,
	target_radius: float,
	episode_duration: float,
	arena_size: Vector3
) -> void:
	if bool(group.get("awaiting_respawn", false)):
		var restart_delay = maxf(
			float(group.get("respawn_delay_remaining", 0.0)) - delta,
			0.0
		)
		group["respawn_delay_remaining"] = restart_delay
		if restart_delay <= 0.0:
			_start_group_episode(
				group,
				spawn_origin,
				target_position,
				target_velocity,
				target_radius,
				episode_duration,
				arena_size
			)
		return
	var workers: Array = group.get("workers", [])
	if workers.is_empty():
		_start_group_episode(
			group,
			spawn_origin,
			target_position,
			target_velocity,
			target_radius,
			episode_duration,
			arena_size
		)
		return
	var objective = _objective(group, target_position, target_velocity, target_radius)
	var all_finished = true
	var active_worker_count = 0
	var decision_worker_count = 0
	for worker_value: Variant in workers:
		var worker: Dictionary = worker_value
		if bool(worker.get("finished", false)):
			continue
		all_finished = false
		active_worker_count += 1
		if _tick_worker(group, worker, delta, objective, arena_size):
			decision_worker_count += 1
	if all_finished:
		_finish_group_episode(group)
	elif active_worker_count > 0 and decision_worker_count == active_worker_count:
		_begin_group_update_if_ready(group, false)


func _tick_worker(
	group: Dictionary,
	worker: Dictionary,
	delta: float,
	objective: Dictionary,
	arena_size: Vector3
) -> bool:
	worker["arena_size"] = arena_size
	var body = _worker_body(worker)
	if not is_instance_valid(body):
		_finish_worker(group, worker, "missing_body", false, {})
		return false
	var previous_observation: Dictionary = worker.get("previous_physics_observation", {})
	if _recover_lost_private_task_item(worker, arena_size):
		# Private fallback cargo is not part of the room's authored-item recovery pass. Once it
		# leaves the supported task envelope the current rollout has become impossible, so end this
		# worker's episode instead of training against an unreachable objective indefinitely.
		_finish_worker(group, worker, "task_item_lost", false, previous_observation)
		return true
	var adapter = worker.get("adapter") as FourLimbMLBodyAdapter
	var settle_remaining = maxf(float(worker.get("settle_remaining", 0.0)), 0.0)
	if settle_remaining > 0.0:
		if not body.is_body_alive():
			var settle_death_reason: String = body.last_failure_reason
			if settle_death_reason.is_empty():
				settle_death_reason = "destroyed"
			_finish_worker(group, worker, settle_death_reason, false, previous_observation)
			return true
		if adapter == null:
			worker["settle_remaining"] = 0.0
			_finish_worker(group, worker, "missing_adapter", false, previous_observation)
			return true
		elif not body.has_finite_physics_state():
			worker["settle_remaining"] = 0.0
			_finish_worker(group, worker, "unstable_physics", false, previous_observation)
			return true
		else:
			settle_remaining = maxf(settle_remaining - maxf(delta, 0.0), 0.0)
			worker["settle_remaining"] = settle_remaining
			var neutral_commands = FourLimbMLAction.neutral_commands()
			if not adapter.apply_commands(neutral_commands):
				worker["settle_remaining"] = 0.0
				_record_worker_fault(worker, "invalid_neutral_action")
				return false
			# No observation/reward/action is consumed during settling. Snapshot once when settling
			# completes instead of rebuilding sensors/tensors at the physics rate.
			if settle_remaining <= 0.0:
				_prime_worker_action(group, worker, objective)
			return false
	var safe_delta: float = maxf(delta, 0.0)
	worker["episode_elapsed"] = float(worker.get("episode_elapsed", 0.0)) + safe_delta
	# This is elapsed physical time under the currently held action. Keep it separate
	# from decision_elapsed, whose fmod remainder is only a scheduler phase.
	worker["interval_elapsed_seconds"] = (
		float(worker.get("interval_elapsed_seconds", 0.0)) + safe_delta
	)
	previous_observation = worker.get("previous_physics_observation", {})
	if not body.is_body_alive():
		var death_reason = body.last_failure_reason
		if death_reason.is_empty():
			death_reason = "destroyed"
		var death_observation: Dictionary = _settle_pending_worker_reward(
			group, worker, objective, arena_size
		)
		_finish_worker(
			group,
			worker,
			death_reason,
			false,
			death_observation if not death_observation.is_empty() else previous_observation
		)
		return true
	if adapter == null:
		_finish_worker(group, worker, "missing_adapter", false, previous_observation)
		return true
	if not body.has_finite_physics_state():
		_finish_worker(group, worker, "unstable_physics", false, previous_observation)
		return true
	if (
		float(worker["episode_elapsed"])
		>= float(worker.get("episode_duration", MAXIMUM_EPISODE_SECONDS))
	):
		var timeout_observation: Dictionary = _settle_pending_worker_reward(
			group, worker, objective, arena_size
		)
		if timeout_observation.is_empty():
			_finish_worker(group, worker, "invalid_observation", false, previous_observation)
		else:
			_finish_worker(group, worker, "timeout", true, timeout_observation)
		return true
	worker["elapsed"] = float(worker.get("elapsed", 0.0)) + delta
	worker["decision_elapsed"] = float(worker.get("decision_elapsed", 0.0)) + delta
	var control_interval = _safe_control_interval(
		group.get("control_interval_seconds", DECISION_INTERVAL_SECONDS)
	)
	if float(worker["decision_elapsed"]) < control_interval:
		return false
	var reward_delta: float = maxf(
		float(worker.get("interval_elapsed_seconds", safe_delta)),
		0.000001
	)
	worker["decision_elapsed"] = fmod(
		float(worker["decision_elapsed"]),
		control_interval
	)
	var observation = _capture_worker_observation(
		adapter,
		body,
		objective,
		arena_size,
		worker.get("pickup_item") as TrainingItem3D,
		worker.get("combat_adapter") as FourLimbTrainingCombatantAdapter,
		int(group.get("group_id", -1))
	)
	if observation.is_empty():
		_record_worker_fault(worker, "invalid_observation")
		return false
	worker["runtime_fault_reason"] = ""
	var body_state: Dictionary = observation.get("body", {})
	var body_position: Vector3 = body_state.get("position_world", Vector3.ZERO)
	var spawn_position: Vector3 = worker.get("spawn_position_world", body_position)
	worker["maximum_horizontal_displacement_m"] = maxf(
		float(worker.get("maximum_horizontal_displacement_m", 0.0)),
		Vector2(body_position.x, body_position.z).distance_to(
			Vector2(spawn_position.x, spawn_position.z)
		)
	)
	var combat_adapter = worker.get("combat_adapter") as TrainingCombatantAdapter
	worker["combat_events"] = (
		combat_adapter.consume_combat_events() if combat_adapter != null else {}
	)
	var reward_result = (group["reward_deck"] as FourLimbRewardDeck).step_reward(
		worker.get("previous_physics_observation", observation),
		observation,
		reward_delta,
		worker["reward_state"],
		_reward_context(worker, observation)
	)
	worker["action_change_pending"] = 0.0
	var reward = float(reward_result.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + reward
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + reward
	worker["previous_physics_observation"] = observation
	group["last_reward_state"] = worker.get("reward_state", {})
	var target_distance = _observation_target_distance(observation)
	worker["last_target_distance_m"] = target_distance
	if target_distance <= _observation_target_radius(observation):
		worker["time_inside_radius_seconds"] = (
			float(worker.get("time_inside_radius_seconds", 0.0)) + reward_delta
		)

	var termination = _worker_termination(worker, observation, arena_size)
	if bool(termination.get("finished", false)):
		_finish_worker(
			group,
			worker,
			str(termination.get("reason", "")),
			bool(termination.get("timed_out", false)),
			observation
		)
		return true
	var trainer = group["trainer"] as FourLimbPPOTrainer
	var last_sample: Dictionary = worker.get("last_action_sample", {})
	var sample = trainer.sample_validated_training_action(observation)
	if sample.is_empty():
		if not last_sample.is_empty():
			trainer.add_transition(
				int(worker["id"]),
				last_sample,
				float(worker["interval_reward"]),
				observation,
				false,
				false,
				maxf(float(worker.get("interval_elapsed_seconds", control_interval)), 0.000001)
			)
		worker["interval_reward"] = 0.0
		worker["interval_elapsed_seconds"] = 0.0
		_record_worker_fault(worker, "invalid_policy_sample")
		return true
	var previous_commands: PackedFloat64Array = worker.get(
		"previous_commands",
		FourLimbMLAction.neutral_commands()
	)
	var sampled_commands: PackedFloat64Array = sample.get(
		"commands",
		PackedFloat64Array()
	)
	if sampled_commands.size() != FourLimbMLAction.ACTION_COUNT:
		if not last_sample.is_empty():
			trainer.add_transition(
				int(worker["id"]),
				last_sample,
				float(worker["interval_reward"]),
				observation,
				false,
				false,
				maxf(float(worker.get("interval_elapsed_seconds", control_interval)), 0.000001)
			)
		worker["interval_reward"] = 0.0
		worker["interval_elapsed_seconds"] = 0.0
		_record_worker_fault(worker, "invalid_policy_action")
		return true
	if not last_sample.is_empty():
		var transition_accepted: bool = trainer.add_transition(
			int(worker["id"]),
			last_sample,
			float(worker["interval_reward"]),
			observation,
			false,
			false,
			maxf(float(worker.get("interval_elapsed_seconds", control_interval)), 0.000001),
			sample.get("actor_input", PackedFloat64Array())
		)
		if not transition_accepted:
			worker["interval_reward"] = 0.0
			worker["interval_elapsed_seconds"] = 0.0
			_record_worker_fault(worker, "transition_rejected")
			return true
	worker["interval_reward"] = 0.0
	worker["interval_elapsed_seconds"] = 0.0
	if not adapter.apply_commands(sample.get("commands", PackedFloat64Array())):
		_record_worker_fault(worker, "invalid_policy_action")
		return false
	worker["action_change_pending"] = _command_change_norm(
		previous_commands,
		sampled_commands
	)
	worker["commands_before_latest_sample"] = previous_commands.duplicate()
	worker["previous_commands"] = sampled_commands
	worker["last_action_sample"] = sample
	worker["runtime_fault_reason"] = ""
	_emit_worker_action_applied(group, worker, sampled_commands)
	return true


func _settle_pending_worker_reward(
	group: Dictionary,
	worker: Dictionary,
	objective: Dictionary,
	arena_size: Vector3
) -> Dictionary:
	var previous_observation: Dictionary = worker.get("previous_physics_observation", {})
	var reward_delta: float = float(worker.get("interval_elapsed_seconds", 0.0))
	if reward_delta <= 0.0:
		return previous_observation
	var body = _worker_body(worker)
	var adapter = worker.get("adapter") as FourLimbMLBodyAdapter
	if (
		adapter == null
		or not is_instance_valid(body)
		or not body.has_finite_physics_state()
	):
		return {}
	var observation: Dictionary = _capture_worker_observation(
		adapter,
		body,
		objective,
		arena_size,
		worker.get("pickup_item") as TrainingItem3D,
		worker.get("combat_adapter") as FourLimbTrainingCombatantAdapter,
		int(group.get("group_id", -1))
	)
	if observation.is_empty():
		return {}
	var combat_adapter = worker.get("combat_adapter") as TrainingCombatantAdapter
	worker["combat_events"] = (
		combat_adapter.consume_combat_events()
		if combat_adapter != null
		else TrainingCombatantAdapter.EMPTY_COMBAT_EVENTS
	)
	var reward_result: Dictionary = (group["reward_deck"] as FourLimbRewardDeck).step_reward(
		previous_observation if not previous_observation.is_empty() else observation,
		observation,
		maxf(reward_delta, 0.000001),
		worker["reward_state"],
		_reward_context(worker, observation)
	)
	worker["action_change_pending"] = 0.0
	var reward: float = float(reward_result.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + reward
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + reward
	worker["previous_physics_observation"] = observation
	group["last_reward_state"] = worker.get("reward_state", {})
	var target_distance: float = _observation_target_distance(observation)
	worker["last_target_distance_m"] = target_distance
	if target_distance <= _observation_target_radius(observation):
		worker["time_inside_radius_seconds"] = (
			float(worker.get("time_inside_radius_seconds", 0.0)) + reward_delta
		)
	# Deliberately keep interval_elapsed_seconds intact. _finish_worker consumes this exact duration
	# for the final PPO transition; clearing it here would turn the final action into a fake 50 ms step.
	return observation


func _worker_termination(
	worker: Dictionary,
	observation: Dictionary,
	arena_size: Vector3
) -> Dictionary:
	var elapsed = float(worker.get(
		"episode_elapsed",
		worker.get("elapsed", 0.0)
	))
	if elapsed >= float(worker.get("episode_duration", 20.0)):
		return {"finished": true, "timed_out": true, "reason": "timeout"}
	var body = _worker_body(worker)
	if not is_instance_valid(body) or not body.is_body_alive():
		var reason = "missing_body"
		if is_instance_valid(body):
			reason = body.last_failure_reason
			if reason.is_empty():
				reason = "destroyed"
		return {
			"finished": true,
			"timed_out": false,
			"reason": reason,
		}
	var body_state: Dictionary = observation.get("body", {})
	var position: Vector3 = body_state.get("position_world", body.core_transform().origin)
	var footprint_margin = ARENA_BOUNDARY_BUFFER_M
	if body.definition != null:
		# The diagonal half-extent safely covers any chassis yaw. Limbs may probe past an edge,
		# but the load-bearing core is terminated before its center can leave the floor rectangle.
		footprint_margin += Vector2(
			body.definition.core_size.x * 0.5,
			body.definition.core_size.z * 0.5
		).length()
	if (
		position.y < ARENA_FALL_CUTOFF_M
		or outside_horizontal_arena(position, arena_size, footprint_margin)
	):
		return {"finished": true, "timed_out": false, "reason": "left_arena"}
	return {"finished": false}


static func outside_horizontal_arena(
	position: Vector3,
	arena_size: Vector3,
	margin: float = 0.0
) -> bool:
	if not position.is_finite() or not arena_size.is_finite():
		return true
	if arena_size.x <= 0.0 or arena_size.z <= 0.0:
		return false
	var half_width = maxf(arena_size.x * 0.5 - maxf(margin, 0.0), 0.0)
	var half_depth = maxf(arena_size.z * 0.5 - maxf(margin, 0.0), 0.0)
	return absf(position.x) > half_width or absf(position.z) > half_depth


func _record_worker_fault(worker: Dictionary, reason: String) -> void:
	# Invalid policy data is treated like the drone room treats a rejected action: keep the body
	# alive, retain its last valid physical command, and retry at the next control boundary.
	# Never stop physical simulation or latch the worker into a permanent frozen state.
	worker["runtime_fault_reason"] = reason
	worker["last_action_sample"] = {}


func _control_blend_factor(elapsed: float) -> float:
	if CONTROL_RAMP_SECONDS <= 0.0:
		return 1.0
	var linear = clampf(elapsed / CONTROL_RAMP_SECONDS, 0.0, 1.0)
	return linear * linear * (3.0 - 2.0 * linear)


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
	_unregister_combatant(worker.get("combat_adapter") as TrainingCombatantAdapter)
	worker["failure_reason"] = reason
	var terminal = (group["reward_deck"] as FourLimbRewardDeck).terminal_reward(
		worker["reward_state"],
		"" if timed_out else reason,
		timed_out
	)
	var terminal_reward = float(terminal.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + terminal_reward
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + terminal_reward
	group["last_reward_state"] = worker.get("reward_state", {})
	var trainer = group["trainer"] as FourLimbPPOTrainer
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
			worker["runtime_fault_reason"] = "terminal_transition_rejected"
	worker["episode_result"] = _worker_episode_result(group, worker, observation)
	var body = _worker_body(worker)
	if is_instance_valid(body) and is_instance_valid(body.physical_rig):
		# Pause keeps grips by design, but a terminal worker no longer owns shared task cargo.
		# Release before freezing the body/item so another live worker can immediately interact with
		# authored cargo and the private fallback has no stale attachment across episode respawn.
		body.physical_rig.release_all_grips()
	_set_private_task_item_simulation_active(worker, false)
	if is_instance_valid(body):
		# Mirror finished drone trials: keep the same visible body node until the shared
		# intermission ends, then reset that node for the next episode instead of deleting it.
		body.stop_simulation()


func _finish_group_episode(group: Dictionary) -> void:
	if bool(group.get("awaiting_respawn", false)):
		return
	var workers: Array = group.get("workers", [])
	var total = 0.0
	var history = group["history"] as DroneTrainingMetricsHistory
	for worker_value: Variant in workers:
		var worker: Dictionary = worker_value
		total += float(worker.get("total_reward", 0.0))
		var episode_result: Dictionary = worker.get("episode_result", {})
		if episode_result.is_empty():
			episode_result = _worker_episode_result(
				group,
				worker,
				worker.get("previous_physics_observation", {})
			)
		history.record_episode(episode_result, workers.size())
	var mean = total / float(maxi(workers.size(), 1))
	group["last_mean_reward"] = mean
	group["best_mean_reward"] = maxf(float(group.get("best_mean_reward", -INF)), mean)
	var trainer = group["trainer"] as FourLimbPPOTrainer
	if evaluation_contract_provider.is_valid():
		var evaluation_contract: Dictionary = evaluation_contract_provider.call(
			int(group.get("group_id", -1)),
			"four_limb"
		)
		trainer.set_evaluation_contract(evaluation_contract)
	trainer.record_completed_episode(mean)
	group["awaiting_respawn"] = true
	group["respawn_delay_remaining"] = EPISODE_RESPAWN_DELAY_SECONDS
	_poll_group_optimizer(group)
	var force_partial_update = (
		not trainer.has_background_update()
		and not trainer.can_update(false)
		and trainer.rollout.size() >= MINIMUM_BACKGROUND_UPDATE_SAMPLES
	)
	_begin_group_update_if_ready(group, force_partial_update)
	group_episode_completed.emit(int(group["group_id"]))


func _clear_group_workers(group: Dictionary) -> void:
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker: Dictionary = worker_value
		var body = _worker_body(worker)
		_unregister_combatant(worker.get("combat_adapter") as TrainingCombatantAdapter)
		worker["body"] = null
		worker["adapter"] = null
		worker["combat_adapter"] = null
		var pickup_item: TrainingItem3D = worker.get("pickup_item") as TrainingItem3D
		worker["pickup_item"] = null
		# Authored room items belong to the shared environment and must survive worker/episode
		# teardown. Only the old per-worker fallback prop is coordinator-owned.
		if is_instance_valid(pickup_item) and pickup_item is FourLimbTrainingGrabbableItem3D:
			pickup_item.queue_free()
		if is_instance_valid(body):
			# Configuration changes rebuild workers through this path rather than _finish_worker().
			# This is terminal teardown, not a pause: surrender shared cargo before the physical rig
			# disappears so items do not retain stale joints/collision exceptions or phantom owners.
			if is_instance_valid(body.physical_rig):
				body.physical_rig.release_all_grips()
			body.stop_simulation()
			body.queue_free()
	group["workers"] = []


func _register_combatant(adapter: TrainingCombatantAdapter) -> void:
	if entity_spatial_hash == null or adapter == null or not adapter.is_alive():
		return
	entity_spatial_hash.register_entity(
		adapter.spatial_key(),
		adapter.body,
		adapter.entity_kind,
		adapter.entity_id,
		adapter.metadata()
	)


func _unregister_combatant(adapter: TrainingCombatantAdapter) -> void:
	if entity_spatial_hash != null and adapter != null:
		entity_spatial_hash.clear_query_cache(
			TrainingTurretThreatSensor.cache_id_for(adapter)
		)
		entity_spatial_hash.unregister_entity(adapter.spatial_key())


func _worker_body(worker: Dictionary) -> FourLimbPhysicalBody3D:
	var body_value: Variant = worker.get("body", null)
	if body_value == null or not is_instance_valid(body_value):
		return null
	return body_value as FourLimbPhysicalBody3D


func _poll_group_optimizer(group: Dictionary) -> void:
	var trainer = group["trainer"] as FourLimbPPOTrainer
	var metrics = trainer.poll_background_update()
	group["optimizer_waiting"] = trainer.has_background_update()
	if metrics.is_empty():
		return
	# A completed update is installed immediately by the trainer. Keep any currently held
	# old-policy action running until its normal control boundary so reward/time accounting
	# covers the complete physical interval. The trainer accepts that one stale boundary
	# transition as an environment step but deliberately discards it from PPO.
	# Even a failed optimizer job must release the old behavior policy for fresh collection;
	# otherwise one transient thread/update error would silently disable learning forever.
	var stored_metrics = metrics.duplicate(true)
	stored_metrics["update"] = int(stored_metrics.get("update_count", trainer.update_count))
	var exploration: Dictionary = stored_metrics.get("exploration", {})
	stored_metrics["action_standard_deviation_mean"] = float(
		exploration.get("mean", 0.0)
	)
	group["last_update"] = stored_metrics
	if not stored_metrics.has("error"):
		(group["history"] as DroneTrainingMetricsHistory).record_update(stored_metrics)
	group_update_completed.emit(int(group["group_id"]))


func _begin_group_update_if_ready(
	group: Dictionary,
	force_partial: bool
) -> bool:
	var trainer = group["trainer"] as FourLimbPPOTrainer
	if trainer.has_background_update() or not trainer.can_update(force_partial):
		return false
	var started = trainer.begin_background_update(force_partial)
	group["optimizer_waiting"] = trainer.has_background_update()
	if not started:
		group["last_update"] = {
			"error": (
				trainer.last_error
				if not trainer.last_error.is_empty()
				else "The four-limb optimizer could not start."
			)
		}
		return false
	# Bodies continue simulating while the detached optimizer works. Their old-policy
	# boundaries still reach the trainer so environment-step telemetry remains truthful;
	# PPO count-but-discards those samples while the detached update is active.
	return true



func _emit_worker_action_applied(
	group: Dictionary,
	worker: Dictionary,
	commands: PackedFloat64Array
) -> void:
	if commands.size() != FourLimbMLAction.ACTION_COUNT:
		return
	var body = _worker_body(worker)
	if not is_instance_valid(body):
		return
	worker_action_applied.emit(
		int(group.get("group_id", -1)),
		int(group.get("episode", -1)),
		int(worker.get("id", -1)),
		int(body.get_instance_id()),
		float(worker.get("episode_elapsed", worker.get("elapsed", 0.0))),
		commands.duplicate()
	)


func reset_group_statistics(group_id: int) -> bool:
	var group = group_by_id(group_id)
	if group.is_empty():
		return false
	(group["trainer"] as FourLimbPPOTrainer).reset_episode_statistics()
	(group["history"] as DroneTrainingMetricsHistory).reset()
	group["last_mean_reward"] = 0.0
	group["best_mean_reward"] = -INF
	group["last_update"] = {}
	return true


func _worker_episode_result(
	group: Dictionary,
	worker: Dictionary,
	observation: Dictionary
) -> Dictionary:
	var elapsed = maxf(float(worker.get(
		"episode_elapsed",
		worker.get("elapsed", 0.0)
	)), 0.000001)
	var total_reward = float(worker.get("total_reward", 0.0))
	var usable_observation = observation
	if usable_observation.is_empty():
		usable_observation = worker.get("previous_physics_observation", {})
	var target_distance = _observation_target_distance(usable_observation)
	if not is_finite(target_distance):
		target_distance = float(worker.get("last_target_distance_m", 0.0))
	var reward_state: Dictionary = worker.get("reward_state", {})
	var episode_totals: Dictionary = reward_state.get("episode_totals", {})
	var result = {
		"episode_number": int(group.get("episode", 0)),
		"episode_elapsed_seconds": elapsed,
		"mean_reward_per_second": total_reward / elapsed,
		"distance_m": target_distance,
		"time_inside_radius_seconds": clampf(
			float(worker.get("time_inside_radius_seconds", 0.0)),
			0.0,
			elapsed
		),
		"total_reward": total_reward,
		"failure_reason": str(worker.get("failure_reason", "")),
		"maximum_horizontal_displacement_m": float(
			worker.get("maximum_horizontal_displacement_m", 0.0)
		),
		"reward_components": episode_totals.duplicate(true),
	}
	for card_id: String in FourLimbRewardDeck.CARD_ORDER:
		result["cumulative_%s_reward" % card_id] = float(
			episode_totals.get(card_id, 0.0)
		)
	return result


func _observation_target_distance(observation: Dictionary) -> float:
	var body: Dictionary = observation.get("body", {})
	var objective: Dictionary = observation.get("objective", {})
	return FourLimbRewardDeck.target_goal_distance(body, objective)


func _observation_target_radius(observation: Dictionary) -> float:
	var objective: Dictionary = observation.get("objective", {})
	return maxf(float(objective.get("target_radius", 1.0)), 0.05)


static func _reward_card_enabled(group: Dictionary, card_id: String) -> bool:
	var deck = group.get("reward_deck") as FourLimbRewardDeck
	var card: FourLimbRewardCard = deck.card(card_id) if deck != null else null
	return card != null and card.enabled and card.intensity > 0.0


static func _group_requires_task_item(group: Dictionary) -> bool:
	# Delivery is inherently a cargo task even when the standalone pickup-reward card is disabled.
	# Keeping this decision in one place prevents delivery-only lessons from starting with no item.
	return _reward_card_enabled(group, "item_pickup") or _reward_card_enabled(group, "item_delivery")


static func _reward_context(
	worker: Dictionary,
	observation: Dictionary = {}
) -> Dictionary:
	var pickup_item = worker.get("pickup_item") as TrainingItem3D
	var objective: Dictionary = observation.get("objective", {})
	return {
		"action_change_norm": float(worker.get("action_change_pending", 0.0)),
		"combat_events": worker.get("combat_events", {}),
		"turret_threat_probe": objective.get("turret_threat_probe", {}),
		"assigned_pickup_item_id": (
			pickup_item.get_instance_id() if is_instance_valid(pickup_item) else 0
		),
		"pickup_item_reward_value": (
			pickup_item.reward_value if is_instance_valid(pickup_item) else 0.0
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


func _capture_worker_observation(
	adapter: FourLimbMLBodyAdapter,
	body: FourLimbPhysicalBody3D,
	base_objective: Dictionary,
	arena_size: Vector3 = Vector3.ZERO,
	pickup_item: TrainingItem3D = null,
	combat_adapter: FourLimbTrainingCombatantAdapter = null,
	group_id: int = -1
) -> Dictionary:
	if adapter == null or not is_instance_valid(body) or not is_instance_valid(body.physical_rig):
		return {}
	# Fetch physical contacts once, then share them between hit detection, body features and
	# reward calculation. Wall rays use the room's static spatial hash rather than physics-space
	# queries, matching the drone sensor's fast broad-phase/exact-shape path.
	var contacts = body.physical_rig.world_contact_snapshot()
	var objective = base_objective.duplicate(false)
	var delivery_context: Dictionary = {}
	if delivery_destination_provider.is_valid():
		var delivery_value: Variant = delivery_destination_provider.call(body, pickup_item, group_id)
		if delivery_value is Dictionary:
			delivery_context = delivery_value as Dictionary
	var held_delivery_item: TrainingItem3D = delivery_context.get("held_item") as TrainingItem3D
	var observed_item: TrainingItem3D = (
		held_delivery_item if is_instance_valid(held_delivery_item) else pickup_item
	)
	objective["pickup_item_present"] = is_instance_valid(observed_item)
	objective["pickup_item_position_world"] = (
		observed_item.global_position if is_instance_valid(observed_item) else body.core_transform().origin
	)
	objective["pickup_item_velocity_world"] = (
		observed_item.task_velocity_world() if is_instance_valid(observed_item) else Vector3.ZERO
	)
	objective["pickup_item_mass"] = observed_item.mass if is_instance_valid(observed_item) else 0.0
	objective["pickup_item_reward_value"] = observed_item.reward_value if is_instance_valid(observed_item) else 0.0
	objective["pickup_item_id"] = observed_item.get_instance_id() if is_instance_valid(observed_item) else 0
	objective["pickup_item_held"] = (
		body.physical_rig.holds_instance_id(observed_item.get_instance_id())
		if is_instance_valid(observed_item)
		else false
	)
	var delivery_task_active: bool = bool(delivery_context.get("task_active", false))
	var delivery_available: bool = bool(delivery_context.get("available", false))
	objective["delivery_task_phase"] = str(delivery_context.get("phase", "")) if delivery_task_active else ""
	# During the pickup phase of an enabled delivery lesson, route the generic task target to the
	# compatible cargo itself. This reuses the existing target-progress/search observations/rewards
	# to teach the first stage. Once held, delivery_available below switches that exact target channel
	# to the destination volume while the dedicated pickup features keep describing the carried item.
	if delivery_task_active and not delivery_available and is_instance_valid(observed_item):
		var pickup_target_position_value: Variant = delivery_context.get(
			"pickup_target_position_world",
			observed_item.global_position
		)
		if pickup_target_position_value is Vector3 and (pickup_target_position_value as Vector3).is_finite():
			objective["target_position_world"] = pickup_target_position_value as Vector3
			var pickup_target_velocity_value: Variant = delivery_context.get(
				"pickup_target_velocity_world",
				observed_item.task_velocity_world()
			)
			objective["target_velocity_world"] = (
				pickup_target_velocity_value as Vector3
				if pickup_target_velocity_value is Vector3 and (pickup_target_velocity_value as Vector3).is_finite()
				else Vector3.ZERO
			)
			objective["target_radius"] = maxf(
				RLTrainingMath.finite_float_or(
					delivery_context.get("pickup_target_radius_m", 0.75),
					0.75
				),
				0.05
			)
			objective.erase("target_subject_position_world")
	objective["delivery_destination_present"] = delivery_available
	objective["delivery_destination_group_id"] = maxi(
		RLTrainingMath.finite_int_or(delivery_context.get("group_id", 0), 0),
		0
	)
	objective["delivery_destination_stable_id"] = str(delivery_context.get("stable_id", ""))
	objective["delivery_item_held"] = delivery_available and is_instance_valid(held_delivery_item)
	objective["delivery_item_accepted"] = bool(delivery_context.get("item_accepted", false))
	objective["delivery_item_inside"] = bool(delivery_context.get("item_inside", false))
	objective["delivery_item_instance_id"] = (
		held_delivery_item.get_instance_id() if is_instance_valid(held_delivery_item) else 0
	)
	objective["delivery_item_reward_value"] = (
		held_delivery_item.reward_value if is_instance_valid(held_delivery_item) else 0.0
	)
	objective["delivery_approach_reward_scale"] = maxf(
		RLTrainingMath.finite_float_or(delivery_context.get("approach_reward_scale", 1.0), 1.0),
		0.0
	)
	objective["delivery_completion_reward_scale"] = maxf(
		RLTrainingMath.finite_float_or(delivery_context.get("completion_reward_scale", 1.0), 1.0),
		0.0
	)
	objective["delivery_destination_distance_m"] = maxf(
		RLTrainingMath.finite_float_or(delivery_context.get("distance_m", 0.0), 0.0),
		0.0
	)
	if delivery_available:
		var delivery_position_value: Variant = delivery_context.get("position_world", null)
		if delivery_position_value is Vector3 and (delivery_position_value as Vector3).is_finite():
			objective["target_position_world"] = delivery_position_value as Vector3
			objective["target_velocity_world"] = Vector3.ZERO
			objective["target_radius"] = maxf(
				RLTrainingMath.finite_float_or(delivery_context.get("radius_m", 0.75), 0.75),
				0.05
			)
			# A delivery zone is a task volume, not the support-surface subject from the previous
			# navigation target. Keeping that stale subject would leak the old climb-height context
			# into the carry phase even though the policy target has already switched to the drop-off.
			objective.erase("target_subject_position_world")
	objective["turret_threat_probe"] = TrainingTurretThreatSensor.acquire(
		combat_adapter, entity_spatial_hash, wall_spatial_hash
	)
	objective["obstacle_probe"] = FourLimbTrainingObstacleSensor.sample(
		body,
		objective.get("target_position_world", body.global_position),
		wall_spatial_hash,
		contacts,
		arena_size
	)
	return adapter.capture_observation_with_contacts(objective, contacts)


func _objective(
	group: Dictionary,
	target_position: Vector3,
	target_velocity: Vector3,
	target_radius: float
) -> Dictionary:
	var metadata_value: Variant = group.get("current_target_metadata", {})
	var target_metadata: Dictionary = (
		(metadata_value as Dictionary).duplicate(false)
		if metadata_value is Dictionary
		else {}
	)
	var policy_target_position: Vector3 = target_position
	var subject_position_value: Variant = target_metadata.get("subject_position_world", null)
	if subject_position_value is Vector3 and (subject_position_value as Vector3).is_finite():
		var subject_position: Vector3 = subject_position_value
		# For legged navigation the authored target is a support/destination surface. Train the core
		# to occupy its natural standing height above that surface instead of inheriting the drone
		# trainer's fixed hover offset. This makes a floor marker mean "stand here" and a marker on a
		# box top mean "get onto this box" while preserving one direct 3D objective for the policy.
		var body_definition: FourLimbBodyDefinition = _group_body_definition(group)
		if body_definition != null:
			policy_target_position = subject_position + Vector3.UP * body_definition.preferred_core_height()
	var result: Dictionary = {
		"target_position_world": policy_target_position,
		"target_velocity_world": target_velocity,
		"target_radius": maxf(target_radius, 0.5),
		"target_metadata": target_metadata,
	}
	if subject_position_value is Vector3 and (subject_position_value as Vector3).is_finite():
		result["target_subject_position_world"] = subject_position_value
	return result


func _room_training_item_for_worker(
	origin_world: Vector3,
	excluded_item_ids: Array[int],
	group_id: int = -1
) -> TrainingItem3D:
	if not item_candidate_provider.is_valid():
		return null
	var candidate: Variant = item_candidate_provider.call(
		origin_world,
		excluded_item_ids,
		group_id
	)
	return candidate as TrainingItem3D if candidate is TrainingItem3D else null


static func _pickup_item_spawn_transform(
	body_spawn: Transform3D,
	target_position: Vector3,
	worker_index: int
) -> Transform3D:
	var direction = target_position - body_spawn.origin
	direction.y = 0.0
	if direction.length_squared() <= 0.000001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var side = direction.cross(Vector3.UP).normalized()
	var position = body_spawn.origin + direction * 2.25 + side * (0.35 if worker_index % 2 == 0 else -0.35)
	position.y = 0.24
	return Transform3D(Basis.IDENTITY, position)


func _worker_spawn_transform(
	_group: Dictionary,
	worker_index: int,
	_worker_count: int,
	spawn_origin: Vector3,
	arena_size: Vector3
) -> Transform3D:
	var offset_2d = (
		WORKER_OFFSETS[worker_index]
		if worker_index >= 0 and worker_index < WORKER_OFFSETS.size()
		else Vector2.ZERO
	)
	var position = spawn_origin + Vector3(
		offset_2d.x * WORKER_SPACING_M,
		0.0,
		offset_2d.y * WORKER_SPACING_M
	)
	position.y = maxf(position.y, _minimum_safe_spawn_height(_group))
	var horizontal_margin = _minimum_horizontal_spawn_margin(_group)
	position.x = clampf(
		position.x,
		-arena_size.x * 0.5 + horizontal_margin,
		arena_size.x * 0.5 - horizontal_margin
	)
	position.z = clampf(
		position.z,
		-arena_size.z * 0.5 + horizontal_margin,
		arena_size.z * 0.5 - horizontal_margin
	)
	return Transform3D(Basis.IDENTITY, position)


func _minimum_safe_spawn_height(group: Dictionary) -> float:
	var definition: FourLimbBodyDefinition = _group_body_definition(group)
	if definition == null:
		return SPAWN_FLOOR_CLEARANCE_M
	return definition.minimum_spawn_height(SPAWN_FLOOR_CLEARANCE_M)


func _minimum_horizontal_spawn_margin(group: Dictionary) -> float:
	var definition: FourLimbBodyDefinition = _group_body_definition(group)
	if definition == null:
		return SPAWN_FLOOR_CLEARANCE_M
	return definition.horizontal_rest_extent() + SPAWN_FLOOR_CLEARANCE_M


func _group_body_definition(group: Dictionary) -> FourLimbBodyDefinition:
	var definition = group.get("body_definition") as FourLimbBodyDefinition
	if definition == null:
		return null
	definition.ensure_contract()
	return definition


func _add_body_label(body: FourLimbPhysicalBody3D, label_text: String, color: Color) -> void:
	if not is_instance_valid(body.physical_rig) or not is_instance_valid(body.physical_rig.core_bone):
		return
	var label = Label3D.new()
	label.name = "TrainingGroupLabel"
	label.text = label_text
	label.position = Vector3(0.0, 0.75, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 24
	label.outline_size = 6
	label.pixel_size = 0.006
	label.modulate = color
	body.physical_rig.core_bone.add_child(label)


func _command_change_norm(
	previous: PackedFloat64Array,
	current: PackedFloat64Array
) -> float:
	if (
		previous.size() != FourLimbMLAction.ACTION_COUNT
		or current.size() != FourLimbMLAction.ACTION_COUNT
	):
		return 0.0
	var sum = 0.0
	var joint_sample_count = 0
	for limb_index in range(FourLimbMLAction.LIMB_COUNT):
		for joint_axis in range(FourLimbMLAction.JOINT_AXES_PER_LIMB):
			var action_index = FourLimbMLAction.action_offset(limb_index, joint_axis)
			var difference = current[action_index] - previous[action_index]
			sum += difference * difference
			joint_sample_count += 1
	# This reward card is specifically "Joint command spam". Grip activation is a discrete-ish
	# end-effector command with its own filtered actuator state and must not dilute or inflate the
	# smoothness measure for the twelve actual joint targets. RMS keeps the scale independent of
	# the number of joint channels while preserving the existing 0..2 normalized difference range.
	return sqrt(sum / float(maxi(joint_sample_count, 1)))


func _safe_control_interval(value: Variant) -> float:
	return clampf(
		RLTrainingMath.finite_float_or(value, DECISION_INTERVAL_SECONDS),
		1.0 / 60.0,
		0.5
	)
