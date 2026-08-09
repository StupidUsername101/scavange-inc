class_name TurretRewardDeck
extends RefCounted

const CARD_ORDER: Array[String] = [
	"aim",
	"hit",
	"shot_discipline",
	"smoothness",
	"damage_safety",
	"failure",
]
const AIM_REWARD_PER_SECOND = 0.30
const AIM_PROGRESS_REWARD_SCALE = 0.25
const SHOT_ALIGNMENT_MINIMUM = 0.995
const HIT_REWARD_PER_HIT = 1.25
const DAMAGE_REWARD_SCALE = 0.02
const BAD_SHOT_PENALTY = 0.08
const MISS_PENALTY = 0.05
const ACTION_CHANGE_DEADBAND = 0.04
const ACTION_SMOOTHNESS_WEIGHT = 0.015
const DAMAGE_TAKEN_PENALTY_SCALE = 0.04
const TERMINAL_FAILURE_PENALTY = 1.0

var cards: Dictionary[String, FourLimbRewardCard] = {}


func _init() -> void:
	_add("aim", "Track the intercept point", "Gives dense signed shaping for the finite-speed intercept solution: turning toward it is rewarded, remaining pointed away is punished, and temporary wall occlusion does not erase the tracking objective. Firing still requires line of sight.", 1.0, 0.0, 5.0, 0.05, FourLimbRewardCard.TYPE_MIXED)
	_add("hit", "Hit targets", "Rewards confirmed projectile impacts on the routed training target or a live combat target. Live combat hits also receive a small damage-dealt bonus.", 1.0, 0.0, 8.0, 0.05, FourLimbRewardCard.TYPE_REWARD)
	_add("shot_discipline", "Take viable shots", "Punishes firing without a shootable target, without line of sight, outside the weapon envelope, far off target, and projectile misses.", 1.0, 0.0, 5.0, 0.05, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("smoothness", "Use realistic servo control", "Punishes abrupt changes in yaw, pitch, and trigger commands instead of teleport-like oscillation.", 1.0, 0.0, 3.0, 0.05, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("damage_safety", "Avoid incoming fire", "Punishes damage received if turrets later fight combat-capable entities.", 1.0, 0.0, 6.0, 0.05, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("failure", "Remain operational", "Applies a terminal punishment when the turret is destroyed.", 1.0, 0.0, 8.0, 0.05, FourLimbRewardCard.TYPE_PUNISHMENT)


func card_list() -> Array[FourLimbRewardCard]:
	var result: Array[FourLimbRewardCard] = []
	for card_id in CARD_ORDER:
		var value = cards.get(card_id) as FourLimbRewardCard
		if value != null:
			result.append(value)
	return result


func card(card_id: String) -> FourLimbRewardCard:
	return cards.get(card_id) as FourLimbRewardCard


func configuration_dictionary() -> Dictionary:
	var result = {}
	for value in card_list():
		result[value.card_id] = value.to_dictionary()
	return result


func enabled_components_dictionary() -> Dictionary:
	var result = {}
	for value in card_list():
		result[value.card_id] = value.enabled
	return result


func load_configuration(value: Dictionary) -> void:
	for card_id in cards:
		var configured: Variant = value.get(card_id)
		var reward_card = cards[card_id] as FourLimbRewardCard
		if configured is Dictionary:
			reward_card.load_dictionary(configured)


func reset_state(initial_observation: Dictionary) -> Dictionary:
	return {
		# Observations are fresh immutable snapshots in the coordinator. Retain them rather than
		# recursively copying the complete nested target/body/weapon payload every control step.
		"previous_observation": initial_observation,
		"previous_commands": initial_observation.get(
			"previous_commands",
			TurretMLAction.neutral_commands()
		),
		"episode_totals": {},
		"last_weapon_events": _empty_weapon_events(),
		"weapon_event_totals": _empty_weapon_events(),
	}


func step_reward(
	previous_observation: Dictionary,
	observation: Dictionary,
	delta: float,
	state: Dictionary,
	weapon_events: Dictionary
) -> Dictionary:
	var safe_delta = maxf(delta, 0.0)
	var target: Dictionary = observation.get("target", {})
	var alignment = clampf(float(target.get("aim_alignment", -1.0)), -1.0, 1.0)
	var target_present = bool(target.get("present", false))
	var line_of_sight = bool(target.get("line_of_sight", false))
	var within_pitch_arc = bool(target.get("within_pitch_arc", false))
	var precise_ratio = clampf((alignment + 1.0) * 0.5, 0.0, 1.0)
	# Tracking is useful even while the objective is temporarily outside the firing pitch arc.
	# Gating the dense term on reachability created another zero-reward state: a turret could see
	# the routed objective and receive meaningful direction inputs, yet get no learning signal at
	# all until the objective happened to enter the weapon envelope. Shot viability still uses the
	# strict range/pitch/LOS contract below.
	var tracking_active: bool = target_present
	# The old hold term was max(alignment, 0)^2. That made every complete rotation earn a
	# positive average reward because the front half of the spin paid while the rear half cost
	# nothing. A constant drive also avoided the action-change smoothness penalty, so spinning was
	# a real local optimum. Signed cosine alignment makes a full rotation average to zero while a
	# settled barrel earns continuously and a barrel facing away continuously loses reward.
	var aim_hold_reward = (
		AIM_REWARD_PER_SECOND * alignment * safe_delta
		if tracking_active
		else 0.0
	)
	var previous_target: Dictionary = previous_observation.get("target", {})
	var target_stable_id: String = str(target.get("stable_id", ""))
	var previous_target_stable_id: String = str(previous_target.get("stable_id", ""))
	var same_trackable_target: bool = (
		target_present
		and bool(previous_target.get("present", false))
		and not target_stable_id.is_empty()
		and target_stable_id == previous_target_stable_id
	)
	var previous_alignment: float = clampf(
		RLTrainingMath.finite_float_or(previous_target.get("aim_alignment", alignment), alignment),
		-1.0,
		1.0
	)
	# This signed difference telescopes while tracking one target: rotating toward the solution is
	# rewarded even when the barrel starts behind it, while rotating away pays the reward back.
	# It therefore supplies the missing early learning signal without creating an oscillation farm.
	var aim_progress_reward: float = (
		(alignment - previous_alignment) * AIM_PROGRESS_REWARD_SCALE
		if same_trackable_target
		else 0.0
	)
	var aim_reward: float = aim_hold_reward + aim_progress_reward
	var hits = maxi(RLTrainingMath.finite_int_or(weapon_events.get("hits", 0), 0), 0)
	var damage_dealt = maxf(
		RLTrainingMath.finite_float_or(weapon_events.get("damage_dealt", 0.0), 0.0),
		0.0
	)
	var hit_reward = hits * HIT_REWARD_PER_HIT + damage_dealt * DAMAGE_REWARD_SCALE
	var shots_fired = maxi(
		RLTrainingMath.finite_int_or(weapon_events.get("shots_fired", 0), 0),
		0
	)
	var misses = maxi(RLTrainingMath.finite_int_or(weapon_events.get("misses", 0), 0), 0)
	var viable_shot = (
		target_present
		and bool(target.get(
			"is_shootable_target",
			bool(target.get("is_combat_target", int(target.get("entity_id", 0)) > 0))
		))
		and line_of_sight
		and bool(target.get("within_range", false))
		and within_pitch_arc
		and alignment >= SHOT_ALIGNMENT_MINIMUM
	)
	var exact_bad_shots: int = RLTrainingMath.finite_int_or(
		weapon_events.get("bad_shots", -1),
		-1
	)
	var exact_viable_shots: int = RLTrainingMath.finite_int_or(
		weapon_events.get("viable_shots", -1),
		-1
	)
	var exact_classification_valid: bool = (
		exact_bad_shots >= 0
		and exact_viable_shots >= 0
		and exact_bad_shots + exact_viable_shots == shots_fired
	)
	# Older/custom event producers may not expose exact shot-time classification. Retain the
	# previous observation-time fallback for them, but normal turret training uses the exact
	# barrel/LOS state captured when each shot was actually fired.
	var bad_shots = (
		exact_bad_shots
		if exact_classification_valid
		else (0 if viable_shot else shots_fired)
	)
	var shot_discipline_reward = -(
		bad_shots * BAD_SHOT_PENALTY
		+ misses * MISS_PENALTY
	)
	var current_commands: PackedFloat64Array = observation.get(
		"previous_commands",
		TurretMLAction.neutral_commands()
	)
	var prior_commands: PackedFloat64Array = previous_observation.get(
		"previous_commands",
		TurretMLAction.neutral_commands()
	)
	var smoothness_reward = -_command_change_norm(prior_commands, current_commands) * ACTION_SMOOTHNESS_WEIGHT
	var combat: Dictionary = observation.get("combat", {})
	var damage_safety_reward = -maxf(
		RLTrainingMath.finite_float_or(combat.get("damage_taken", 0.0), 0.0),
		0.0
	) * DAMAGE_TAKEN_PENALTY_SCALE
	var components = {
		"aim": _scaled("aim", aim_reward),
		"hit": _scaled("hit", hit_reward),
		"shot_discipline": _scaled("shot_discipline", shot_discipline_reward),
		"smoothness": _scaled("smoothness", smoothness_reward),
		"damage_safety": _scaled("damage_safety", damage_safety_reward),
		"failure": 0.0,
	}
	var total = 0.0
	for card_id in CARD_ORDER:
		total += float(components.get(card_id, 0.0))
	state["last_components"] = components.duplicate(false)
	state["last_target_debug"] = {
		"present": target_present,
		"is_combat_target": bool(target.get(
			"is_combat_target", int(target.get("entity_id", 0)) > 0
		)),
		"is_shootable_target": bool(target.get(
			"is_shootable_target", false
		)),
		"target_kind": str(target.get("target_kind", "fallback")),
		"stable_id": target_stable_id,
		"entity_id": int(target.get("entity_id", 0)),
		"alignment": alignment,
		"line_of_sight": line_of_sight,
		"within_range": bool(target.get("within_range", false)),
		"within_pitch_arc": within_pitch_arc,
	}
	var normalized_weapon_events: Dictionary = {
		"shots_fired": shots_fired,
		"viable_shots": maxi(exact_viable_shots, 0) if exact_classification_valid else maxi(shots_fired - bad_shots, 0),
		"bad_shots": bad_shots,
		"hits": hits,
		"damage_dealt": damage_dealt,
		"misses": misses,
	}
	state["last_weapon_events"] = normalized_weapon_events
	_accumulate_weapon_events(state, normalized_weapon_events)
	_accumulate(state, components)
	state["previous_observation"] = observation
	state["previous_commands"] = current_commands
	return _result(total, components, state, alignment, precise_ratio)


func terminal_reward(state: Dictionary, failure_reason: String, timed_out: bool) -> Dictionary:
	var failure_reward = 0.0
	if not timed_out and not failure_reason.is_empty():
		failure_reward = _scaled("failure", -TERMINAL_FAILURE_PENALTY)
	var components = {
		"aim": 0.0,
		"hit": 0.0,
		"shot_discipline": 0.0,
		"smoothness": 0.0,
		"damage_safety": 0.0,
		"failure": failure_reward,
	}
	state["last_components"] = components.duplicate(false)
	_accumulate(state, components)
	return _result(failure_reward, components, state, 0.0, 0.0)


static func _empty_weapon_events() -> Dictionary:
	return {
		"shots_fired": 0,
		"viable_shots": 0,
		"bad_shots": 0,
		"hits": 0,
		"damage_dealt": 0.0,
		"misses": 0,
	}


static func _accumulate_weapon_events(state: Dictionary, events: Dictionary) -> void:
	var totals_value: Variant = state.get("weapon_event_totals", {})
	var totals: Dictionary = (
		(totals_value as Dictionary).duplicate(false)
		if totals_value is Dictionary
		else _empty_weapon_events()
	)
	for key: String in ["shots_fired", "viable_shots", "bad_shots", "hits", "misses"]:
		totals[key] = maxi(
			RLTrainingMath.finite_int_or(totals.get(key, 0), 0)
			+ RLTrainingMath.finite_int_or(events.get(key, 0), 0),
			0
		)
	totals["damage_dealt"] = maxf(
		RLTrainingMath.finite_float_or(totals.get("damage_dealt", 0.0), 0.0)
		+ RLTrainingMath.finite_float_or(events.get("damage_dealt", 0.0), 0.0),
		0.0
	)
	state["weapon_event_totals"] = totals


func _scaled(card_id: String, value: float) -> float:
	var reward_card = card(card_id)
	return value * reward_card.intensity if reward_card != null and reward_card.enabled else 0.0


func _accumulate(state: Dictionary, components: Dictionary) -> void:
	var totals: Dictionary = state.get("episode_totals", {})
	for card_id in CARD_ORDER:
		totals[card_id] = float(totals.get(card_id, 0.0)) + float(components.get(card_id, 0.0))
	state["episode_totals"] = totals


func _result(
	total: float,
	components: Dictionary,
	state: Dictionary,
	alignment: float,
	precise_ratio: float
) -> Dictionary:
	return {
		"total": total,
		"components": components,
		"episode_totals": (state.get("episode_totals", {}) as Dictionary).duplicate(false),
		"aim_alignment": alignment,
		"precise_aim_ratio": precise_ratio,
	}


static func _command_change_norm(previous: PackedFloat64Array, current: PackedFloat64Array) -> float:
	if previous.size() != current.size() or current.is_empty():
		return 0.0
	var sum = 0.0
	for index in range(current.size()):
		var difference = maxf(absf(current[index] - previous[index]) - ACTION_CHANGE_DEADBAND, 0.0)
		sum += difference * difference
	return sqrt(sum / float(current.size()))


func _add(
	id_value: String,
	name_value: String,
	explanation_value: String,
	intensity_value: float,
	minimum_value: float,
	maximum_value: float,
	step_value: float,
	signal_type_value: int
) -> void:
	cards[id_value] = FourLimbRewardCard.new(
		id_value,
		name_value,
		explanation_value,
		intensity_value,
		minimum_value,
		maximum_value,
		step_value,
		signal_type_value
	)
