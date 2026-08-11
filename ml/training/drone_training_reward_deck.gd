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
	RewardCardDeckSupport.add_card(cards,
		"approach",
		"Move toward target",
		"Rewards reducing target distance and applies a small cost while searching far away.",
		1.0,
		0.0,
		6.0,
		0.05,
		FourLimbRewardCard.TYPE_MIXED
	)
	RewardCardDeckSupport.add_card(cards,
		"radius",
		"Hold near target",
		"Rewards remaining inside the accepted target radius.",
		1.0,
		0.0,
		4.0,
		0.05,
		FourLimbRewardCard.TYPE_REWARD
	)
	RewardCardDeckSupport.add_card(cards,
		"survival",
		"Stay alive",
		"Small reward for remaining operational and a timeout bonus for completing the episode.",
		1.0,
		0.0,
		2.0,
		0.05,
		FourLimbRewardCard.TYPE_REWARD
	)
	RewardCardDeckSupport.add_card(cards,
		"ground_safety",
		"Keep ground clearance",
		"Punishes dangerous low flight and descending toward the ground.",
		1.0,
		0.0,
		5.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	RewardCardDeckSupport.add_card(cards,
		"smoothness",
		"Smooth motor commands",
		"Punishes abrupt command changes and sustained extreme propeller commands.",
		1.0,
		0.0,
		3.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	RewardCardDeckSupport.add_card(cards,
		"obstacle",
		"Avoid walls",
		"Punishes closing on nearby obstacles and making contact with them.",
		1.0,
		0.0,
		6.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	RewardCardDeckSupport.add_card(cards,
		"turret_safety",
		"Avoid turret fire",
		"Punishes confirmed hits, damage taken, and remaining exposed to a turret that has line of sight and is aimed at the drone.",
		1.0,
		0.0,
		8.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	RewardCardDeckSupport.add_card(cards,
		"failure",
		"Avoid crashes and escape",
		"Applies the terminal punishment for crashes, deadlocks, destruction, and leaving the arena.",
		1.0,
		0.0,
		8.0,
		0.05,
		FourLimbRewardCard.TYPE_PUNISHMENT
	)
	load_legacy_enabled_components(enabled_components)


func card_list() -> Array[FourLimbRewardCard]:
	return RewardCardDeckSupport.card_list(cards, CARD_ORDER)


func card(card_id: String) -> FourLimbRewardCard:
	return cards.get(card_id) as FourLimbRewardCard


func enabled_components_dictionary() -> Dictionary:
	return RewardCardDeckSupport.enabled_dictionary(
		cards,
		CARD_ORDER,
		DroneTrainingReward.DEFAULT_COMPONENTS
	)


func configuration_dictionary() -> Dictionary:
	return RewardCardDeckSupport.configuration_dictionary(cards, CARD_ORDER)


func load_configuration(value: Dictionary) -> void:
	RewardCardDeckSupport.load_configuration(cards, value)


func load_legacy_enabled_components(value: Dictionary) -> void:
	for card_id: String in cards:
		if not value.has(card_id):
			continue
		var configured_value = value[card_id]
		var card_value = cards[card_id] as FourLimbRewardCard
		if configured_value is Dictionary:
			card_value.load_dictionary(configured_value)
		else:
			card_value.enabled = SafeVariant.bool_or(configured_value, card_value.enabled)
