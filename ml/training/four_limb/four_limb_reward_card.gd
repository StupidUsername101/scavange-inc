class_name FourLimbRewardCard
extends RefCounted

#######################################################
# One understandable reward or punishment rule with its own enable switch and intensity.
# The class is shared by drone and limb reward decks despite the historical name.
#######################################################

const TYPE_REWARD = 0
const TYPE_PUNISHMENT = 1
const TYPE_MIXED = 2

var card_id = ""
var display_name = "Reward"
var explanation = ""
var enabled = true
var intensity = 1.0
var minimum_intensity = 0.0
var maximum_intensity = 5.0
var step = 0.01
var signal_type = TYPE_REWARD


func _init(
	id_value: String = "",
	name_value: String = "Reward",
	explanation_value: String = "",
	intensity_value: float = 1.0,
	minimum_value: float = 0.0,
	maximum_value: float = 5.0,
	step_value: float = 0.01,
	signal_type_value: int = TYPE_REWARD,
	enabled_value: bool = true
) -> void:
	card_id = id_value
	display_name = name_value
	explanation = explanation_value
	minimum_intensity = minimum_value if is_finite(minimum_value) else 0.0
	var safe_maximum: float = maximum_value if is_finite(maximum_value) else minimum_intensity
	maximum_intensity = maxf(safe_maximum, minimum_intensity)
	var safe_step: float = step_value if is_finite(step_value) else 0.01
	step = maxf(safe_step, 0.000001)
	var safe_intensity: float = intensity_value if is_finite(intensity_value) else 1.0
	intensity = clampf(safe_intensity, minimum_intensity, maximum_intensity)
	signal_type = clampi(signal_type_value, TYPE_REWARD, TYPE_MIXED)
	enabled = enabled_value


func signal_label() -> String:
	match signal_type:
		TYPE_PUNISHMENT:
			return "PUNISHMENT"
		TYPE_MIXED:
			return "REWARD / PUNISHMENT"
	return "REWARD"


func to_dictionary() -> Dictionary:
	return {
		"id": card_id,
		"display_name": display_name,
		"explanation": explanation,
		"enabled": enabled,
		"intensity": intensity,
		"minimum_intensity": minimum_intensity,
		"maximum_intensity": maximum_intensity,
		"step": step,
		"signal_type": signal_type,
	}


func load_dictionary(value: Dictionary) -> void:
	if str(value.get("id", card_id)) != card_id:
		return
	enabled = RLTrainingMath.bool_or(value.get("enabled", enabled), enabled)
	var loaded_intensity: float = RLTrainingMath.finite_float_or(value.get("intensity", intensity), intensity)
	if is_finite(loaded_intensity):
		intensity = clampf(loaded_intensity, minimum_intensity, maximum_intensity)
