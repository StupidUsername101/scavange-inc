class_name FourLimbRewardContext
extends RefCounted

#######################################################
# Shared construction of non-algorithm reward context fields used by live four-limb training and
# deterministic evaluation. Reward equations stay in FourLimbRewardDeck; this only keeps task and
# delivery state encoded identically at both call sites.
#######################################################


static func task_fields(
	objective: Dictionary,
	assigned_pickup_item_id: int,
	pickup_item_reward_value: float
) -> Dictionary:
	return {
		"turret_threat_probe": objective.get("turret_threat_probe", {}),
		"assigned_pickup_item_id": maxi(assigned_pickup_item_id, 0),
		"pickup_item_reward_value": maxf(
			SafeVariant.finite_float_or(pickup_item_reward_value, 0.0),
			0.0
		),
		"delivery_destination_present": bool(objective.get("delivery_destination_present", false)),
		"delivery_destination_group_id": maxi(
			SafeVariant.integral_int_or(objective.get("delivery_destination_group_id", 0), 0),
			0
		),
		"delivery_destination_stable_id": str(objective.get("delivery_destination_stable_id", "")),
		"delivery_destination_distance_m": maxf(
			SafeVariant.finite_float_or(objective.get("delivery_destination_distance_m", 0.0), 0.0),
			0.0
		),
		"delivery_item_held": bool(objective.get("delivery_item_held", false)),
		"delivery_item_accepted": bool(objective.get("delivery_item_accepted", false)),
		"delivery_item_inside": bool(objective.get("delivery_item_inside", false)),
		"delivery_item_instance_id": maxi(
			SafeVariant.integral_int_or(objective.get("delivery_item_instance_id", 0), 0),
			0
		),
		"delivery_item_reward_value": maxf(
			SafeVariant.finite_float_or(objective.get("delivery_item_reward_value", 0.0), 0.0),
			0.0
		),
		"delivery_approach_reward_scale": maxf(
			SafeVariant.finite_float_or(objective.get("delivery_approach_reward_scale", 1.0), 1.0),
			0.0
		),
		"delivery_completion_reward_scale": maxf(
			SafeVariant.finite_float_or(objective.get("delivery_completion_reward_scale", 1.0), 1.0),
			0.0
		),
	}
