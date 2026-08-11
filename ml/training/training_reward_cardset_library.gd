class_name TrainingRewardCardsetLibrary
extends RefCounted

#######################################################
# Shared persistent reward-card presets for drone, four-limb, and turret worker groups.
# Built-ins are generated from the current deck definitions; user presets are saved under user://.
#######################################################

const SCHEMA_VERSION = 1
const BODY_TYPE_DRONE = "drone"
const BODY_TYPE_FOUR_LIMB = "four_limb"
const BODY_TYPE_TURRET = "turret"
const STORAGE_DIRECTORY = "user://ml_reward_cardsets"
const STORAGE_PATH = STORAGE_DIRECTORY + "/cardsets.json"

var last_error = ""
var storage_path: String = STORAGE_PATH
var storage_directory: String = STORAGE_DIRECTORY
var custom_cardsets: Dictionary = {
	BODY_TYPE_DRONE: [],
	BODY_TYPE_FOUR_LIMB: [],
	BODY_TYPE_TURRET: [],
}


func _init(custom_storage_path: String = STORAGE_PATH) -> void:
	storage_path = custom_storage_path if not custom_storage_path.is_empty() else STORAGE_PATH
	storage_directory = storage_path.get_base_dir()
	_load_custom_cardsets()


func cardsets_for_body_type(body_type: String) -> Array[Dictionary]:
	var normalized = _normalized_body_type(body_type)
	var result: Array[Dictionary] = []
	for cardset: Dictionary in _built_in_cardsets(normalized):
		result.append(cardset.duplicate(true))
	var sorted_custom: Array[Dictionary] = _valid_custom_records(
		custom_cardsets.get(normalized, []),
		normalized
	)
	sorted_custom.sort_custom(_sort_by_display_name)
	result.append_array(sorted_custom)
	return result


func cardset(body_type: String, cardset_id: String) -> Dictionary:
	for record: Dictionary in cardsets_for_body_type(body_type):
		if str(record.get("id", "")) == cardset_id:
			return record
	return {}


func save_custom_cardset(
	body_type: String,
	display_name: String,
	configuration: Dictionary
) -> Dictionary:
	last_error = ""
	var normalized = _normalized_body_type(body_type)
	var cleaned_name = display_name.strip_edges()
	if cleaned_name.is_empty():
		last_error = "Enter a preset name first."
		return {}
	if not RewardCardDeckSupport.valid_configuration_payload(configuration):
		last_error = "The selected group has no valid reward-card configuration to save."
		return {}
	var stored_values: Variant = custom_cardsets.get(normalized, [])
	var previous_values: Array = (stored_values as Array).duplicate(true) if stored_values is Array else []
	var values: Array = _valid_custom_records(stored_values, normalized)
	var record_id = ""
	for value: Variant in values:
		if not (value is Dictionary):
			continue
		var existing = value as Dictionary
		var existing_id: String = str(existing.get("id", ""))
		if (
			existing_id.begins_with("user:%s:" % normalized)
			and str(existing.get("display_name", "")).nocasecmp_to(cleaned_name) == 0
		):
			record_id = existing_id
			break
	if record_id.is_empty():
		record_id = "user:%s:%s" % [
			normalized,
			cleaned_name.sha256_text().substr(0, 14),
		]
	var record = {
		"id": record_id,
		"display_name": cleaned_name,
		"body_type": normalized,
		"cards": configuration.duplicate(true),
		"builtin": false,
		"updated_unix": int(Time.get_unix_time_from_system()),
	}
	var replaced = false
	for index in range(values.size()):
		var value: Variant = values[index]
		if value is Dictionary and str((value as Dictionary).get("id", "")) == record_id:
			values[index] = record
			replaced = true
			break
	if not replaced:
		values.append(record)
	custom_cardsets[normalized] = values
	if not _save_custom_cardsets():
		custom_cardsets[normalized] = previous_values
		return {}
	return record.duplicate(true)


func delete_custom_cardset(body_type: String, cardset_id: String) -> bool:
	last_error = ""
	if cardset_id.begins_with("builtin:"):
		last_error = "Built-in reward cardsets cannot be deleted."
		return false
	var normalized = _normalized_body_type(body_type)
	var stored_values: Variant = custom_cardsets.get(normalized, [])
	var previous_values: Array = (stored_values as Array).duplicate(true) if stored_values is Array else []
	var values: Array = _valid_custom_records(stored_values, normalized)
	for index in range(values.size() - 1, -1, -1):
		var value: Variant = values[index]
		if value is Dictionary and str((value as Dictionary).get("id", "")) == cardset_id:
			values.remove_at(index)
			custom_cardsets[normalized] = values
			if _save_custom_cardsets():
				return true
			custom_cardsets[normalized] = previous_values
			return false
	last_error = "The selected reward preset no longer exists."
	return false


func matching_cardset_id(body_type: String, configuration: Dictionary) -> String:
	for record: Dictionary in cardsets_for_body_type(body_type):
		var cards: Dictionary = record.get("cards", {})
		if configurations_match(cards, configuration):
			return str(record.get("id", ""))
	return ""


static func configurations_match(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for card_id: String in left:
		if not right.has(card_id):
			return false
		var left_card: Variant = left[card_id]
		var right_card: Variant = right[card_id]
		if not (left_card is Dictionary) or not (right_card is Dictionary):
			return false
		var left_values = left_card as Dictionary
		var right_values = right_card as Dictionary
		var left_enabled_value: Variant = left_values.get("enabled", true)
		var right_enabled_value: Variant = right_values.get("enabled", true)
		if not (left_enabled_value is bool) or not (right_enabled_value is bool):
			return false
		if (left_enabled_value as bool) != (right_enabled_value as bool):
			return false
		var left_intensity_value: Variant = left_values.get("intensity", 0.0)
		var right_intensity_value: Variant = right_values.get("intensity", 0.0)
		if not (left_intensity_value is float or left_intensity_value is int):
			return false
		if not (right_intensity_value is float or right_intensity_value is int):
			return false
		var left_intensity: float = float(left_intensity_value)
		var right_intensity: float = float(right_intensity_value)
		if not is_finite(left_intensity) or not is_finite(right_intensity):
			return false
		if not is_equal_approx(left_intensity, right_intensity):
			return false
	return true


func _built_in_cardsets(body_type: String) -> Array[Dictionary]:
	if body_type == BODY_TYPE_TURRET:
		var precision = TurretRewardDeck.new().configuration_dictionary()
		var conservative = precision.duplicate(true)
		_configure(conservative, "aim", true, 1.35)
		_configure(conservative, "hit", true, 1.60)
		_configure(conservative, "shot_discipline", true, 1.75)
		_configure(conservative, "smoothness", true, 1.25)
		return [
			_builtin("builtin:turret_precision", "Precision Fire", body_type, precision),
			_builtin("builtin:turret_conservative", "Conservative Fire", body_type, conservative),
		]
	if body_type == BODY_TYPE_FOUR_LIMB:
		var ground = FourLimbRewardDeck.new().configuration_dictionary()
		var long_jump = ground.duplicate(true)
		_configure(long_jump, "survival", true, 0.001)
		_configure(long_jump, "uprightness", true, 0.012)
		# Do not teach airborne jump bodies to resist pitch/roll rotation. Ground locomotion and
		# pickup keep this card enabled; sustained deliberate yaw is free in the signal itself.
		_configure(long_jump, "core_rotational_stability", false, 0.0)
		_configure(long_jump, "height_stability", false, 0.0)
		_configure(long_jump, "core_clearance", true, 0.08)
		_configure(long_jump, "core_drag", true, 0.70)
		_configure(long_jump, "target_progress", true, 0.25)
		_configure(long_jump, "climb_reach", false, 0.0)
		_configure(long_jump, "climb_grip", false, 0.0)
		_configure(long_jump, "climb_ascent", false, 0.0)
		# Jump card weights are deliberately modest. A qualified jump must gain real height
		# and airtime before any of these can pay, so contact chatter is worth zero.
		_configure(long_jump, "jump_launch", true, 0.40)
		_configure(long_jump, "jump_air_progress", true, 0.80)
		_configure(long_jump, "jump_distance", true, 1.50)
		_configure(long_jump, "landing_quality", true, 0.50)
		_configure(long_jump, "target_search", true, 0.025)
		_configure(long_jump, "stable_target_hold", true, 1.25)
		_configure(long_jump, "foot_support", false, 0.0)
		_configure(long_jump, "foot_slip", true, 0.04)
		_configure(long_jump, "command_change", false, 0.0)
		_configure(long_jump, "actuator_saturation", false, 0.0)
		_configure(long_jump, "joint_overstretch", true, 0.18)
		_configure(long_jump, "torque_effort", false, 0.0)
		_configure(long_jump, "obstacle_avoidance", false, 0.0)
		_configure(long_jump, "core_collision", true, 0.35)
		_configure(long_jump, "falling", false, 0.0)
		_configure(long_jump, "failure", true, 1.75)
		_configure(long_jump, "timeout", true, 0.05)
		var climbing = ground.duplicate(true)
		# Climbing needs the normal direct joint/grip actions, not a macro controller. Raise the
		# contextual grip signal and target progress while removing the wall-avoidance conflict that
		# otherwise teaches a worker to stay away from the exact surface it must climb.
		_configure(climbing, "target_progress", true, 1.75)
		_configure(climbing, "climb_reach", true, 1.10)
		_configure(climbing, "climb_grip", true, 1.50)
		_configure(climbing, "climb_ascent", true, 1.25)
		_configure(climbing, "target_search", true, 0.10)
		_configure(climbing, "stable_target_hold", true, 1.25)
		_configure(climbing, "obstacle_avoidance", false, 0.0)
		_configure(climbing, "core_collision", true, 0.12)
		_configure(climbing, "command_change", true, 0.002)

		var pickup = ground.duplicate(true)
		_configure(pickup, "climb_reach", false, 0.0)
		_configure(pickup, "climb_grip", false, 0.0)
		_configure(pickup, "climb_ascent", false, 0.0)
		_configure(pickup, "item_pickup", true, 4.0)
		_configure(pickup, "target_progress", true, 0.65)
		_configure(pickup, "target_search", true, 0.10)
		_configure(pickup, "stable_target_hold", false, 0.0)
		_configure(pickup, "command_change", true, 0.002)
		var delivery = pickup.duplicate(true)
		# Delivery uses the same generic task-target channel as locomotion, but the room changes its
		# meaning by phase: compatible cargo before grip, then the nearest accepting destination while
		# carrying. Keep modest target progress/search shaping so the sparse grip event is learnable;
		# item_delivery adds the held-item potential and one-time completion reward on top.
		_configure(delivery, "item_pickup", true, 3.0)
		_configure(delivery, "item_delivery", true, 4.0)
		_configure(delivery, "target_progress", true, 0.65)
		_configure(delivery, "target_search", true, 0.10)
		_configure(delivery, "stable_target_hold", false, 0.0)
		return [
			_builtin("builtin:limb_ground", "Ground Locomotion", body_type, ground),
			_builtin("builtin:limb_climbing", "Climbing / Grip", body_type, climbing),
			_builtin("builtin:limb_long_jump", "Long Jump", body_type, long_jump),
			_builtin("builtin:limb_item_pickup", "Item Pickup", body_type, pickup),
			_builtin("builtin:limb_item_delivery", "Item Pickup + Delivery", body_type, delivery),
		]
	var balanced = DroneTrainingRewardDeck.new().configuration_dictionary()
	var chase = balanced.duplicate(true)
	_configure(chase, "approach", true, 2.50)
	_configure(chase, "radius", true, 1.50)
	_configure(chase, "survival", true, 0.50)
	_configure(chase, "ground_safety", true, 1.25)
	_configure(chase, "smoothness", true, 0.35)
	_configure(chase, "obstacle", true, 0.90)
	_configure(chase, "failure", true, 1.25)
	return [
		_builtin("builtin:drone_balanced", "Balanced Flight", body_type, balanced),
		_builtin("builtin:drone_chase", "Fast Target Chase", body_type, chase),
	]


static func _builtin(
	cardset_id: String,
	display_name: String,
	body_type: String,
	cards: Dictionary
) -> Dictionary:
	return {
		"id": cardset_id,
		"display_name": display_name,
		"body_type": body_type,
		"cards": cards.duplicate(true),
		"builtin": true,
	}


static func _configure(
	configuration: Dictionary,
	card_id: String,
	enabled: bool,
	intensity: float
) -> void:
	var value: Variant = configuration.get(card_id, null)
	if not (value is Dictionary):
		return
	var card = (value as Dictionary).duplicate(true)
	card["enabled"] = enabled
	card["intensity"] = intensity
	configuration[card_id] = card


func _load_custom_cardsets() -> void:
	if not FileAccess.file_exists(storage_path):
		return
	var file: FileAccess = FileAccess.open(storage_path, FileAccess.READ)
	if file == null:
		last_error = "Could not read saved reward cardsets."
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		last_error = "Saved reward cardsets are not valid JSON."
		return
	var root: Dictionary = parsed as Dictionary
	var schema_version: int = SafeVariant.integral_int_or(root.get("schema_version", -1), -1)
	if schema_version != SCHEMA_VERSION:
		last_error = "Saved reward cardsets use an unsupported schema version."
		return
	var body_records: Variant = root.get("body_types", {})
	if not (body_records is Dictionary):
		last_error = "Saved reward cardsets have a malformed body-type index."
		return
	for body_type in [BODY_TYPE_DRONE, BODY_TYPE_FOUR_LIMB, BODY_TYPE_TURRET]:
		var loaded: Variant = (body_records as Dictionary).get(body_type, [])
		custom_cardsets[body_type] = _valid_custom_records(loaded, body_type)


static func _valid_custom_records(value: Variant, body_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	var id_prefix: String = "user:%s:" % body_type
	for item: Variant in value:
		if not (item is Dictionary):
			continue
		var record: Dictionary = (item as Dictionary).duplicate(true)
		if (
			not str(record.get("id", "")).begins_with(id_prefix)
			or str(record.get("display_name", "")).strip_edges().is_empty()
			or not record.has("cards")
			or not (record["cards"] is Dictionary)
			or not RewardCardDeckSupport.valid_configuration_payload(record["cards"] as Dictionary)
		):
			continue
		record["body_type"] = body_type
		record["builtin"] = false
		result.append(record)
	return result


func _save_custom_cardsets() -> bool:
	last_error = ""
	var absolute_directory = ProjectSettings.globalize_path(storage_directory)
	var directory_error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		last_error = "Could not create the reward-cardset directory."
		return false
	var content: String = JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"body_types": custom_cardsets,
	}, "\t")
	if not TrainingFileIO.write_text_atomic(storage_path, content):
		last_error = "Could not save reward cardsets."
		return false
	return true


static func _normalized_body_type(body_type: String) -> String:
	if body_type == BODY_TYPE_FOUR_LIMB:
		return BODY_TYPE_FOUR_LIMB
	if body_type == BODY_TYPE_TURRET:
		return BODY_TYPE_TURRET
	return BODY_TYPE_DRONE


static func _sort_by_display_name(left: Dictionary, right: Dictionary) -> bool:
	return str(left.get("display_name", "")).nocasecmp_to(
		str(right.get("display_name", ""))
	) < 0
