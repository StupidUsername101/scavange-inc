class_name TrainingCoordinatorGroupState
extends RefCounted

#######################################################
# Shared lifecycle/UI state for integrated non-drone worker coordinators. Body-family coordinators
# add their hardware, trainer, reward deck and placement fields on top of this fresh dictionary.
#######################################################


static func create(
	group_id: int,
	body_type: String,
	group_name: String,
	color: Color,
	worker_count: int,
	maximum_worker_count: int,
	control_interval_seconds: float
) -> Dictionary:
	var clamped_worker_count: int = clampi(worker_count, 1, maximum_worker_count)
	return {
		"group_id": group_id,
		"body_type": body_type,
		"name": group_name,
		"color": color,
		"parent_group_id": -1,
		"branch_weight_variation": 0.0,
		"overwrite_saved_versions": true,
		"rolling_version_id": "",
		"pending_reward_config": {},
		"workers": [],
		"worker_count": clamped_worker_count,
		"pending_worker_count": clamped_worker_count,
		"control_interval_seconds": control_interval_seconds,
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
		"worker_label": null,
		"reward_label": null,
		"hardware_label": null,
		"overwrite_button": null,
		"card_minimum_height": 0.0,
	}

static func episode_progress_summaries(
	groups: Array[Dictionary],
	worker_instance_resolver: Callable
) -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	if not worker_instance_resolver.is_valid():
		return summaries
	for group: Dictionary in groups:
		var workers: Array = group.get("workers", [])
		var valid_instances: int = 0
		var unfinished_instances: int = 0
		var elapsed: float = 0.0
		var duration: float = 0.0
		for worker_value: Variant in workers:
			if not (worker_value is Dictionary):
				continue
			var worker: Dictionary = worker_value as Dictionary
			var worker_instance: Variant = worker_instance_resolver.call(worker)
			if not is_instance_valid(worker_instance):
				continue
			valid_instances += 1
			if not bool(worker.get("finished", false)):
				unfinished_instances += 1
			elapsed = maxf(elapsed, SafeVariant.finite_float_or(
				worker.get("episode_elapsed", 0.0),
				0.0
			))
			duration = maxf(duration, SafeVariant.finite_float_or(
				worker.get("episode_duration", 0.0),
				0.0
			))
		summaries.append({
			"group_id": int(group.get("group_id", -1)),
			"name": str(group.get("name", "Worker group")),
			"active": bool(group.get("active", false)),
			"episode": int(group.get("episode", 0)),
			"elapsed": elapsed,
			"duration": duration,
			"instance_count": valid_instances,
			"unfinished_instance_count": unfinished_instances,
			"awaiting_respawn": bool(group.get("awaiting_respawn", false)),
		})
	return summaries


static func safe_control_interval(value: Variant, fallback: float) -> float:
	return clampf(
		SafeVariant.finite_float_or(value, fallback),
		1.0 / 60.0,
		0.5
	)
