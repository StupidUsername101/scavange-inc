class_name RewardCardDeckSupport
extends RefCounted

#######################################################
# Shared non-mathematical reward-card plumbing. Reward equations stay inside each body-family deck;
# this helper only owns card construction, ordering, configuration serialization, and queued edits.
#######################################################


static func add_card(
	cards: Dictionary,
	id_value: String,
	name_value: String,
	explanation_value: String,
	intensity_value: float,
	minimum_value: float,
	maximum_value: float,
	step_value: float,
	signal_type_value: int,
	enabled_value: bool = true
) -> FourLimbRewardCard:
	var card_value: FourLimbRewardCard = FourLimbRewardCard.new(
		id_value,
		name_value,
		explanation_value,
		intensity_value,
		minimum_value,
		maximum_value,
		step_value,
		signal_type_value,
		enabled_value
	)
	cards[id_value] = card_value
	return card_value


static func card_list(cards: Dictionary, card_order: Array) -> Array[FourLimbRewardCard]:
	var result: Array[FourLimbRewardCard] = []
	for card_id_value: Variant in card_order:
		var card_value: FourLimbRewardCard = cards.get(str(card_id_value)) as FourLimbRewardCard
		if card_value != null:
			result.append(card_value)
	return result


static func configuration_dictionary(cards: Dictionary, card_order: Array) -> Dictionary:
	var result: Dictionary = {}
	for card_value: FourLimbRewardCard in card_list(cards, card_order):
		result[card_value.card_id] = card_value.to_dictionary()
	return result


static func enabled_dictionary(
	cards: Dictionary,
	card_order: Array,
	base: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = base.duplicate()
	for card_value: FourLimbRewardCard in card_list(cards, card_order):
		result[card_value.card_id] = card_value.enabled
	return result


static func load_configuration(cards: Dictionary, value: Dictionary) -> void:
	for card_id_value: Variant in cards.keys():
		var card_id: String = str(card_id_value)
		var configured_value: Variant = value.get(card_id, null)
		var card_value: FourLimbRewardCard = cards.get(card_id) as FourLimbRewardCard
		if card_value != null and configured_value is Dictionary:
			card_value.load_dictionary(configured_value as Dictionary)


static func pending_configuration(group: Dictionary) -> Dictionary:
	var pending_value: Variant = group.get("pending_reward_config", {})
	if not (pending_value is Dictionary):
		_clear_pending_configuration(group)
		return {}
	var pending: Dictionary = pending_value as Dictionary
	# A queued edit is persisted/UI state. Reject the whole edit if any nested record is malformed;
	# otherwise the UI can label a preset as pending even though only part of it can be applied.
	for card_id_value: Variant in pending.keys():
		var card_id: String = str(card_id_value)
		if not valid_card_configuration_record(card_id, pending[card_id_value]):
			_clear_pending_configuration(group)
			return {}
	return pending.duplicate(true)


static func apply_pending_configuration(group: Dictionary, cards: Dictionary) -> bool:
	var pending: Dictionary = pending_configuration(group)
	if pending.is_empty():
		return false
	# Validate card ownership before applying the first edit so an unknown/stale card cannot produce
	# a partially updated deck while the UI promotes the pending preset identity to active.
	for card_id_value: Variant in pending.keys():
		var card_id: String = str(card_id_value)
		if not (cards.get(card_id) is FourLimbRewardCard):
			_clear_pending_configuration(group)
			return false
	for card_id_value: Variant in pending.keys():
		var card_id: String = str(card_id_value)
		var card_value: FourLimbRewardCard = cards.get(card_id) as FourLimbRewardCard
		card_value.load_dictionary(pending[card_id_value] as Dictionary)
	group["pending_reward_config"] = {}
	group["reward_cardset_id"] = str(group.get("pending_reward_cardset_id", "custom"))
	group["reward_cardset_name"] = str(group.get("pending_reward_cardset_name", "Custom"))
	group.erase("pending_reward_cardset_id")
	group.erase("pending_reward_cardset_name")
	return true


static func _clear_pending_configuration(group: Dictionary) -> void:
	group["pending_reward_config"] = {}
	group.erase("pending_reward_cardset_id")
	group.erase("pending_reward_cardset_name")

static func valid_card_configuration_record(card_id: String, value: Variant) -> bool:
	if card_id.is_empty() or not (value is Dictionary):
		return false
	var record: Dictionary = value as Dictionary
	if record.has("id") and str(record["id"]) != card_id:
		return false
	var has_usable_field: bool = false
	if record.has("enabled"):
		var enabled_value: Variant = record["enabled"]
		if not (
			enabled_value is bool
			or enabled_value is int
			or (enabled_value is float and is_finite(float(enabled_value)))
		):
			return false
		has_usable_field = true
	if record.has("intensity"):
		if not SafeVariant.is_finite_number(record["intensity"]):
			return false
		has_usable_field = true
	return has_usable_field


static func valid_configuration_payload(cards: Dictionary) -> bool:
	if cards.is_empty():
		return false
	for card_id_value: Variant in cards.keys():
		var card_id: String = str(card_id_value)
		if not valid_card_configuration_record(card_id, cards[card_id_value]):
			return false
	return true
