class_name DroneTrainingRewardDeck
extends RefCounted

const CARD_ORDER = [
	"approach",
	"radius",
	"survival",
	"ground_safety",
	"smoothness",
	"obstacle",
	"turret_safety",
	"failure",
]

var cards: Dictionary[String, FourLimbRewardCard] = {}


func _init(enabled_components: Dictionary = {}) -> void:
	_add(
		"approach",
		"Move toward target",
		"Rewards reducing target distance and applies a small cost while searching far away.",
		1.0,
		0.0,
		6.0,
		0.05,
		FourLimbRewardCard.TYPE_MIXED
	)
	_add(
		"radius",
		"Hold near target",
		"Rewards remaining inside the accepted target radius.",
		1.0,
		0.0,
		4.0,
		0.05,
		FourLimbRewardCard.TYPE_REWARD
	)
	_add(
		"survival",
		"Stay alive",
		"Small reward for remaining operational and a timeout bonus for completing the episode.",
		1.0,
		0.0,
		2.0,
		0.05,
		FourLimbRewardCard.TYPE_REWARD
	)
	_add(
		"ground_safety",
		"Keep ground clearance",
		"Punishes dangerous low flight and descending toward the ground.",
		1.0,
		0.0,
		5.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	_add(
		"smoothness",
		"Smooth motor commands",
		"Punishes abrupt command changes and sustained extreme propeller commands.",
		1.0,
		0.0,
		3.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	_add(
		"obstacle",
		"Avoid walls",
		"Punishes closing on nearby obstacles and making contact with them.",
		1.0,
		0.0,
		6.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	_add(
		"turret_safety",
		"Avoid turret fire",
		"Punishes confirmed hits, damage taken, and remaining exposed to a turret that has line of sight and is aimed at the drone.",
		1.0,
		0.0,
		8.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	_add(
		"failure",
		"Avoid crashes and escape",
		"Applies the terminal punishment for crashes, flips, deadlocks, and leaving the arena.",
		1.0,
		0.0,
		8.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	load_legacy_enabled_components(enabled_components)


func card_list() -> Array[FourLimbRewardCard]:
	var result: Array[FourLimbRewardCard] = []
	for card_id: String in CARD_ORDER:
		var card_value = cards.get(card_id) as FourLimbRewardCard
		if card_value != null:
			result.append(card_value)
	return result


func card(card_id: String) -> FourLimbRewardCard:
	return cards.get(card_id) as FourLimbRewardCard


func enabled_components_dictionary() -> Dictionary:
	var result = DroneTrainingReward.DEFAULT_COMPONENTS.duplicate()
	for card_value: FourLimbRewardCard in card_list():
		result[card_value.card_id] = card_value.enabled
	return result


func configuration_dictionary() -> Dictionary:
	var result = {}
	for card_value: FourLimbRewardCard in card_list():
		result[card_value.card_id] = card_value.to_dictionary()
	return result


func load_configuration(value: Dictionary) -> void:
	for card_id: String in cards:
		var configured_value = value.get(card_id, null)
		var card_value = cards[card_id] as FourLimbRewardCard
		if configured_value is Dictionary:
			card_value.load_dictionary(configured_value)


func load_legacy_enabled_components(value: Dictionary) -> void:
	for card_id: String in cards:
		if not value.has(card_id):
			continue
		var configured_value = value[card_id]
		var card_value = cards[card_id] as FourLimbRewardCard
		if configured_value is Dictionary:
			card_value.load_dictionary(configured_value)
		else:
			card_value.enabled = bool(configured_value)


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
