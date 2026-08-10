class_name DroneTrainingPlotSeriesBuilder
extends RefCounted

#######################################################
# Pure plot-series assembly for the training UI. The room owns simulation state and selection;
# this helper only translates already-recorded histories/checkpoints into chart data.
#######################################################


static func tag_series(
	entries: Array[Dictionary],
	source_id: String,
	body_type: String,
	label_prefix: String = ""
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index].duplicate(false)
		var original_label: String = str(entry.get("label", "series"))
		entry["label"] = "%s%s" % [label_prefix, original_label]
		entry["source_id"] = source_id
		entry["body_type"] = body_type
		entry["series_id"] = "%s:%s:%d" % [source_id, original_label, index]
		result.append(entry)
	return result


static func all_group_series(
	plot_id: String,
	worker_groups: Array[Dictionary],
	limb_groups: Array[Dictionary],
	turret_groups: Array[Dictionary],
	model_versions: Array[Dictionary]
) -> Array[Dictionary]:
	if plot_id == "checkpoints":
		return tag_series(
			checkpoint_improvement_series(model_versions),
			"all:checkpoints",
			"checkpoint"
		)
	var result: Array[Dictionary] = []
	for group: Dictionary in worker_groups:
		var history: DroneTrainingMetricsHistory = group["history"]
		var label: String = str(group["name"])
		var color: Color = group["color"]
		var entries: Array[Dictionary] = []
		match plot_id:
			"progress":
				entries.append(history.episode_mean_series(
					"mean_reward_per_second", label, color
				))
			"tracking":
				entries.append(history.hover_ratio_mean_series(label, color))
			"rewards":
				entries.append(history.episode_mean_series(
					"distance_m", label, color
				))
			"losses":
				var drone_trainer: DroneTrainingAlgorithm = group.get("trainer") as DroneTrainingAlgorithm
				var loss_key: String = (
					"critic_loss"
					if drone_trainer != null
					and drone_trainer.algorithm_id() == DroneSACTrainer.TRAINING_ALGORITHM_ID
					else "value_loss"
				)
				entries.append(history.update_metric_series(loss_key, label, color))
			"stability":
				entries.append(history.update_metric_series(
					"approximate_kl", label, color
				))
		for entry: Dictionary in tag_series(
			entries,
			"drone:%d" % int(group.get("group_id", -1)),
			"drone",
			"Drone · "
		):
			result.append(entry)
	for limb_group: Dictionary in limb_groups:
		var limb_history: DroneTrainingMetricsHistory = limb_group["history"] as DroneTrainingMetricsHistory
		var limb_label: String = str(limb_group["name"])
		var limb_color: Color = limb_group["color"]
		var limb_entries: Array[Dictionary] = []
		match plot_id:
			"progress":
				limb_entries.append(limb_history.episode_mean_series(
					"mean_reward_per_second", limb_label, limb_color
				))
			"tracking":
				limb_entries.append(limb_history.hover_ratio_mean_series(
					limb_label,
					limb_color
				))
			"rewards":
				limb_entries.append(limb_history.episode_mean_series(
					"distance_m", limb_label, limb_color
				))
			"losses":
				limb_entries.append(limb_history.update_metric_series(
					"value_loss", limb_label, limb_color
				))
			"stability":
				limb_entries.append(limb_history.update_metric_series(
					"approximate_kl", limb_label, limb_color
				))
		for entry: Dictionary in tag_series(
			limb_entries,
			"limb:%d" % int(limb_group.get("group_id", -1)),
			"limb",
			"Limb · "
		):
			result.append(entry)
	for turret_group: Dictionary in turret_groups:
		var turret_history: DroneTrainingMetricsHistory = turret_group["history"] as DroneTrainingMetricsHistory
		var turret_label: String = str(turret_group["name"])
		var turret_color: Color = turret_group["color"]
		var turret_entries: Array[Dictionary] = []
		match plot_id:
			"progress":
				turret_entries.append(turret_history.episode_mean_series("mean_reward_per_second", turret_label, turret_color))
			"tracking":
				turret_entries.append(turret_history.hover_ratio_mean_series(turret_label, turret_color))
			"rewards":
				turret_entries.append(turret_history.episode_mean_series("distance_m", turret_label, turret_color))
			"losses":
				turret_entries.append(turret_history.update_metric_series("value_loss", turret_label, turret_color))
			"stability":
				turret_entries.append(turret_history.update_metric_series("approximate_kl", turret_label, turret_color))
		for entry: Dictionary in tag_series(
			turret_entries,
			"turret:%d" % int(turret_group.get("group_id", -1)),
			"turret",
			"Turret · "
		):
			result.append(entry)
	return result


static func drone_group_series(
	group: Dictionary,
	plot_id: String
) -> Array[Dictionary]:
	if group.is_empty():
		return []
	var history: DroneTrainingMetricsHistory = group.get("history") as DroneTrainingMetricsHistory
	if history == null:
		return []
	var trainer: DroneTrainingAlgorithm = group.get("trainer") as DroneTrainingAlgorithm
	if (
		plot_id == "losses"
		and trainer != null
		and trainer.algorithm_id() == DroneSACTrainer.TRAINING_ALGORITHM_ID
	):
		# SAC has twin Q critics; it never publishes PPO's `value_loss`.
		return [
			history.update_metric_series("actor_loss", "actor", Color("54e6b1")),
			history.update_metric_series("q_one_loss", "critic Q1", Color("ffad42")),
			history.update_metric_series("q_two_loss", "critic Q2", Color("b08cff")),
		]
	return history.plot_series(plot_id)


static func turret_group_series(
	group: Dictionary,
	plot_id: String
) -> Array[Dictionary]:
	if group.is_empty():
		return []
	var history: DroneTrainingMetricsHistory = group["history"] as DroneTrainingMetricsHistory
	match plot_id:
		"progress":
			return [
				history.episode_mean_series("mean_reward_per_second", "reward/s", Color("54e6b1")),
				history.hover_ratio_mean_series("precise aim", Color("ffad42")),
			]
		"tracking":
			return [
				history.episode_mean_series("distance_m", "target distance m", Color("8de1ff")),
				history.hover_ratio_mean_series("precise aim", Color("ffad42")),
			]
		"rewards":
			var reward_series: Array[Dictionary] = []
			var cards: Array = (group["reward_deck"] as TurretRewardDeck).card_list()
			for index: int in range(cards.size()):
				var reward_card: FourLimbRewardCard = cards[index] as FourLimbRewardCard
				if reward_card == null:
					continue
				reward_series.append(history.episode_mean_series(
					"cumulative_%s_reward" % reward_card.card_id,
					reward_card.display_name,
					Color.from_hsv(float(index) / float(maxi(cards.size(), 1)), 0.68, 0.95)
				))
			return reward_series
		"losses":
			return [
				history.update_metric_series("actor_loss", "actor", Color("54e6b1")),
				history.update_metric_series("value_loss", "critic", Color("ffad42")),
			]
		"stability":
			return [
				history.update_metric_series("entropy", "latent entropy", Color("8de1ff")),
				history.update_metric_series("approximate_kl", "KL", Color("ff5c77")),
				history.update_metric_series("clip_fraction", "clip", Color("b08cff")),
				history.update_metric_series("action_standard_deviation_mean", "latent action std", Color("54e6b1")),
			]
	return []


static func limb_group_series(
	group: Dictionary,
	plot_id: String
) -> Array[Dictionary]:
	if group.is_empty():
		return []
	var history: DroneTrainingMetricsHistory = group["history"] as DroneTrainingMetricsHistory
	match plot_id:
		"progress":
			return [
				history.episode_mean_series(
					"mean_reward_per_second",
					"reward/s",
					Color("54e6b1")
				),
				history.hover_ratio_mean_series(
					"target hold",
					Color("ffad42")
				),
			]
		"tracking":
			return [
				history.episode_mean_series(
					"distance_m",
					"distance m",
					Color("8de1ff")
				),
				history.episode_mean_series(
					"maximum_horizontal_displacement_m",
					"travel m",
					Color("ffad42")
				),
			]
		"rewards":
			var reward_series: Array[Dictionary] = []
			var deck: FourLimbRewardDeck = group["reward_deck"] as FourLimbRewardDeck
			var cards: Array = deck.card_list()
			for index: int in range(cards.size()):
				var card_value: FourLimbRewardCard = cards[index]
				if card_value == null:
					continue
				reward_series.append(history.episode_mean_series(
					"cumulative_%s_reward" % card_value.card_id,
					card_value.display_name,
					Color.from_hsv(
						float(index) / float(maxi(cards.size(), 1)),
						0.68,
						0.95
					)
				))
			return reward_series
		"losses":
			return [
				history.update_metric_series(
					"actor_loss", "actor", Color("54e6b1")
				),
				history.update_metric_series(
					"value_loss", "critic", Color("ffad42")
				),
			]
		"stability":
			return [
				history.update_metric_series(
					"entropy", "latent entropy", Color("8de1ff")
				),
				history.update_metric_series(
					"approximate_kl", "KL", Color("ff5c77")
				),
				history.update_metric_series(
					"clip_fraction", "clip", Color("b08cff")
				),
				history.update_metric_series(
					"action_standard_deviation_mean",
					"latent action std",
					Color("54e6b1")
				),
				history.update_metric_series(
					"policy_parameter_delta_rms",
					"policy change",
					Color("ffd166")
				),
			]
	return []


static func checkpoint_improvement_series(
	model_versions: Array[Dictionary],
	model_name_filter: String = ""
) -> Array[Dictionary]:
	var records_by_id: Dictionary = {}
	var records_by_family: Dictionary = {}
	for version: Dictionary in model_versions:
		if not DroneTrainingAlgorithmCatalog.is_training_checkpoint(version):
			continue
		if not (str(version.get("checkpoint_kind", "")) in ["best", "auto_best"]):
			continue
		if not RLTrainingMath.bool_or(version.get("score_matches_checkpoint", false), false):
			continue
		var model_name: String = str(version.get("model_name", "Model"))
		if not model_name_filter.is_empty() and model_name != model_name_filter:
			continue
		records_by_id[str(version.get("version_id", ""))] = version
		if not records_by_family.has(model_name):
			records_by_family[model_name] = []
		(records_by_family[model_name] as Array).append(version)
	var result: Array[Dictionary] = []
	for model_name: String in records_by_family:
		var records: Array = records_by_family[model_name]
		records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return RLTrainingMath.finite_int_or(a.get("version", 0), 0) < RLTrainingMath.finite_int_or(b.get("version", 0), 0)
		)
		var points: PackedVector2Array = PackedVector2Array()
		var previous_score: float = NAN
		for record: Dictionary in records:
			var score: float = RLTrainingMath.finite_float_or(record.get("best_candidate_score", 0.0), 0.0)
			var reference_score: float = previous_score
			var parent_id: String = str(record.get("parent_version_id", ""))
			if records_by_id.has(parent_id):
				reference_score = RLTrainingMath.finite_float_or(
					(records_by_id[parent_id] as Dictionary).get("best_candidate_score", score),
					score
				)
			var improvement: float = 0.0 if not is_finite(reference_score) else score - reference_score
			points.append(Vector2(
				float(RLTrainingMath.finite_int_or(record.get("version", 0), 0)),
				improvement
			))
			previous_score = score
		var hue: float = float(posmod(model_name.hash(), 10000)) / 10000.0
		result.append({
			"label": "%s gain" % model_name,
			"color": Color.from_hsv(hue, 0.68, 0.95),
			"points": points,
		})
	return result
