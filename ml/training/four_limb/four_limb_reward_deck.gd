class_name FourLimbRewardDeck
extends RefCounted

const JUMP_MINIMUM_LAUNCH_SUPPORT_RATIO = 0.50
const JUMP_MINIMUM_LAUNCH_VERTICAL_SPEED_MPS = 0.65
const JUMP_MINIMUM_AIRTIME_SECONDS = 0.22
const JUMP_MINIMUM_CLEARANCE_GAIN_M = 0.16
const JUMP_MINIMUM_SUPPORTED_PREPARATION_SECONDS = 0.18
const JOINT_OVERSTRETCH_GRACE_SECONDS = 0.18
const JOINT_OVERSTRETCH_FULL_PENALTY_SECONDS = 0.55
const CLIMB_HEIGHT_START_M = 0.15
const CLIMB_HEIGHT_FULL_M = 0.90
const CLIMB_FALLBACK_HEIGHT_START_M = 0.65
const CLIMB_FALLBACK_HEIGHT_FULL_M = 1.50

const CARD_ORDER = [
	"survival",
	"uprightness",
	"core_rotational_stability",
	"height_stability",
	"core_clearance",
	"core_drag",
	"target_progress",
	"climb_reach",
	"climb_grip",
	"climb_ascent",
	"jump_launch",
	"jump_air_progress",
	"jump_distance",
	"landing_quality",
	"target_search",
	"stable_target_hold",
	"item_pickup",
	"item_delivery",
	"foot_support",
	"foot_slip",
	"command_change",
	"actuator_saturation",
	"joint_overstretch",
	"torque_effort",
	"obstacle_avoidance",
	"turret_safety",
	"core_collision",
	"falling",
	"failure",
	"timeout",
]

#######################################################
# Reward/punishment cards for the physical body. Contributions are returned separately so the
# UI can show exactly why a body gained or lost reward.
#######################################################

var cards: Dictionary[String, FourLimbRewardCard] = {}


func _init() -> void:
	_add("survival", "Stay alive", "Tiny reward for remaining operational.\nIt must never outweigh locomotion toward the target.", 0.003, 0.0, 0.1, 0.001, FourLimbRewardCard.TYPE_REWARD)
	_add("uprightness", "Stay upright", "Small support reward for keeping the core upright.\nTarget progress remains the primary objective.", 0.02, 0.0, 0.5, 0.005, FourLimbRewardCard.TYPE_REWARD)
	_add("core_rotational_stability", "Steady core rotation", "Rewards a calm core and punishes pitch/roll angular motion or oscillation.\nSustained yaw turning is free; only rapid left-right yaw reversal counts as jitter.", 0.025, 0.0, 0.5, 0.005, FourLimbRewardCard.TYPE_MIXED)
	_add("height_stability", "Stable body height", "Rewards holding the chassis at the body's authored standing height and punishes vertical bouncing.\nDisable or reduce this card for jumping lessons.", 0.04, 0.0, 1.0, 0.005, FourLimbRewardCard.TYPE_MIXED)
	_add("core_clearance", "Protect the core", "Punishes letting the core approach the floor or an object below it.", 0.25, 0.0, 2.0, 0.01, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("core_drag", "Do not crawl on the chassis", "Continuous punishment while the core itself supports or drags across the ground.\nLeg recovery remains possible, but head-rolling cannot farm travel reward.", 0.45, 0.0, 3.0, 0.01, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("target_progress", "Move toward target", "Primary locomotion signal.\nPays for reducing full 3D distance to the routed objective, including its target-height requirement, and punishes moving away.", 1.25, 0.0, 4.0, 0.05, FourLimbRewardCard.TYPE_MIXED)
	_add("climb_reach", "Reach for climbable surface", "Potential-based shaping while an elevated destination requires climbing.\nPays only for moving a free distal grip closer to a visible climbable candidate; backing away gives the reward back, so oscillating cannot farm it.", 0.60, 0.0, 3.0, 0.05, FourLimbRewardCard.TYPE_MIXED)
	_add("climb_grip", "Useful climbing grip", "One-time contextual discovery reward when an independently controlled limb actually latches a climbable surface while the target is above the body.\nHolding the wall without making target progress pays nothing, so grip cannot replace the real objective.", 1.00, 0.0, 3.0, 0.05, FourLimbRewardCard.TYPE_REWARD)
	_add("climb_ascent", "Climb upward", "Rewards new high-water core height reached while at least one independently controlled grip is attached to a climbable surface.\nOnly new height pays, so bobbing up and down on one hold cannot farm reward.", 1.00, 0.0, 4.0, 0.05, FourLimbRewardCard.TYPE_REWARD)
	_add("jump_launch", "Explosive takeoff", "One-time reward after a real jump gains meaningful height and airtime.\nBrief contact flicker or jumping-jack motion cannot trigger it. Disabled in the stock ground-locomotion cardset.", 1.0, 0.0, 5.0, 0.05, FourLimbRewardCard.TYPE_REWARD, false)
	_add("jump_air_progress", "Airborne target progress", "Rewards horizontal target progress only after a jump has gained meaningful height and airtime.\nUnlike ordinary locomotion progress, it does not require foot support or standing height.", 1.0, 0.0, 6.0, 0.05, FourLimbRewardCard.TYPE_REWARD, false)
	_add("jump_distance", "Long jump distance", "One-time reward when a qualified jump ends on the feet.\nLonger horizontal travel earns more, scaled by landing quality.", 1.0, 0.0, 8.0, 0.05, FourLimbRewardCard.TYPE_REWARD, false)
	_add("landing_quality", "Controlled landing", "Rewards an upright low-impact foot landing after a qualified jump and punishes a hard or chassis-first qualified landing.\nOrdinary foot-contact chatter pays nothing.", 1.0, 0.0, 5.0, 0.05, FourLimbRewardCard.TYPE_MIXED, false)
	_add("target_search", "Do not idle away from target", "Time cost while outside the accepted target radius.\nA perfectly stable worker that makes no target progress must still lose reward; locomotion progress is what turns a ground episode positive.", 0.10, 0.0, 0.5, 0.005, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("stable_target_hold", "Stable target hold", "Strong reward near the target.\nIt is reduced by speed, poor uprightness, and unstable body height.", 1.0, 0.0, 4.0, 0.05, FourLimbRewardCard.TYPE_REWARD)
	_add("item_pickup", "Pick up an item", "Rewards first gripping the assigned carryable and pays the larger reward after raising it from the height where this worker first gripped it. Authored training items scale both stages by their Reward value.\nEach item can pay each stage only once per episode, so inherited item height or dropping and re-grabbing cannot farm reward.", 1.5, 0.0, 10.0, 0.05, FourLimbRewardCard.TYPE_REWARD, false)
	_add("item_delivery", "Deliver held item", "Conditional carry reward. While a compatible item is actually held, pays signed potential progress toward the nearest accepting delivery destination and pays a one-time completion reward when cargo crosses into that destination after being picked up outside it. Moving away gives the shaping reward back, and each physical item can complete only once per worker episode even when several destination groups accept it. Cargo first grabbed while already inside a matching bay is treated as already delivered and cannot be farmed by stepping out and back in.", 2.0, 0.0, 12.0, 0.05, FourLimbRewardCard.TYPE_MIXED, false)
	_add("foot_support", "Useful foot support", "Tiny support reward when multiple feet support an upright body.\nIt should help locomotion, not replace it.", 0.01, 0.0, 0.4, 0.005, FourLimbRewardCard.TYPE_REWARD)
	_add("foot_slip", "Foot slipping", "Punishes a planted foot sliding tangentially across its support surface.\nOnly the actual terminal foot shape counts as planted support; shin scraping is not treated as a good foot plant. The stock weight is deliberately strong enough that skating is materially worse than taking real planted steps.", 1.00, 0.0, 1.0, 0.01, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("command_change", "Joint command spam", "Punishes large repeated changes to joint targets.\nThe normalized cost is intentionally small enough to permit exploratory gait discovery.", 0.004, 0.0, 0.2, 0.001, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("actuator_saturation", "Sustained actuator limit", "Punishes holding many joints at their extreme limits for too long.", 0.06, 0.0, 0.5, 0.005, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("joint_overstretch", "Joint overstretch / deep crouch", "Punishes continuously loading real joints near their authored physical limits.\nHip elevation and horizontal sweep are weighted most strongly; brief compression for a step or jump is tolerated before the penalty ramps in.", 0.28, 0.0, 2.0, 0.01, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("torque_effort", "Torque use", "Very small cost for unnecessary actuator effort.\nStrong recovery actions remain worthwhile.", 0.002, 0.0, 0.05, 0.0005, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("obstacle_avoidance", "Unsafe wall approach", "Punishes moving quickly toward nearby wall geometry detected by the spatial-hash lidar.", 0.12, 0.0, 2.0, 0.01, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("turret_safety", "Avoid turret fire", "Punishes confirmed projectile hits and damage, with a smaller continuous cost while a visible turret is already aligned and ready to fire.\nThe body can learn evasive movement before impact without drowning out locomotion rewards.", 1.0, 0.0, 8.0, 0.05, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("core_collision", "Body collision", "One-time punishment when any body segment contacts a wall, or when the core contacts the ground.", 0.15, 0.0, 2.0, 0.01, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("falling", "Dangerous fall", "Punishes downward speed when the core is already low.\nReduce or disable this for lessons that deliberately include airborne motion.", 0.20, 0.0, 2.0, 0.01, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("failure", "Fall or destruction", "Large terminal punishment.\nVery early failure is punished more strongly.", 1.0, 0.0, 8.0, 0.05, FourLimbRewardCard.TYPE_PUNISHMENT)
	_add("timeout", "Survive full episode", "Small bonus for reaching the episode time limit alive.", 0.10, 0.0, 1.0, 0.01, FourLimbRewardCard.TYPE_REWARD)


func card_list() -> Array[FourLimbRewardCard]:
	var result: Array[FourLimbRewardCard] = []
	for card_id: String in CARD_ORDER:
		var card = cards.get(card_id) as FourLimbRewardCard
		if card != null:
			result.append(card)
	return result


func card(card_id: String) -> FourLimbRewardCard:
	return cards.get(card_id) as FourLimbRewardCard


func create_worker_state() -> Dictionary:
	return {
		"elapsed": 0.0,
		"collision_active": false,
		"saturation_elapsed": 0.0,
		"joint_overstretch_elapsed": 0.0,
		"episode_totals": {},
		"last_components": {},
		"support_state_initialized": false,
		"previous_support_ratio": 0.0,
		"jump_active": false,
		"jump_qualified": false,
		"jump_launch_rewarded": false,
		"jump_elapsed": 0.0,
		"jump_start_position": Vector3.ZERO,
		"jump_start_clearance": 0.0,
		"jump_target_direction": Vector3.ZERO,
		"jump_launch_quality": 0.0,
		"jump_max_clearance": 0.0,
		"supported_preparation_elapsed": 0.0,
		"rewarded_grab_ids": {},
		"rewarded_pickup_ids": {},
		"rewarded_delivery_keys": {},
		"delivery_item_eligibility": {},
		"pickup_grab_height_by_id": {},
		"rewarded_climb_grab_ids": {},
		"climb_max_core_y": -INF,
	}


func step_reward(
	previous_observation: Dictionary,
	current_observation: Dictionary,
	delta: float,
	worker_state: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	var safe_delta = maxf(delta, 0.0)
	worker_state["elapsed"] = float(worker_state.get("elapsed", 0.0)) + safe_delta
	var previous_body: Dictionary = previous_observation.get("body", {})
	var current_body: Dictionary = current_observation.get("body", {})
	var objective: Dictionary = current_observation.get("objective", {})
	var target_goal = target_goal_position_world(current_body, objective)
	var target_radius = maxf(float(objective.get("target_radius", 1.0)), 0.05)
	var previous_position: Vector3 = previous_body.get("position_world", target_goal)
	var current_position: Vector3 = current_body.get("position_world", target_goal)
	# Navigation and registered target systems already resolve the final policy objective in world
	# space. Reward the same full 3D point the encoder exposes instead of silently flattening Y.
	# Jump-specific cards keep a horizontal copy below so their established semantics remain.
	var previous_offset = target_goal - previous_position
	var current_offset = target_goal - current_position
	var previous_target_offset_horizontal = previous_offset
	previous_target_offset_horizontal.y = 0.0
	var current_target_offset_horizontal = current_offset
	current_target_offset_horizontal.y = 0.0
	var previous_distance = previous_offset.length()
	var current_distance = current_offset.length()
	var previous_horizontal_distance = previous_target_offset_horizontal.length()
	var current_horizontal_distance = current_target_offset_horizontal.length()
	var climb_need = climb_height_need(current_body, objective)
	var uprightness = float(current_body.get("uprightness", 0.0))
	var velocity: Vector3 = current_body.get("linear_velocity_world", Vector3.ZERO)
	var angular_velocity: Vector3 = current_body.get(
		"angular_velocity_world",
		Vector3.ZERO
	)
	var previous_angular_velocity: Vector3 = previous_body.get(
		"angular_velocity_world",
		angular_velocity
	)
	var target_velocity: Vector3 = objective.get("target_velocity_world", Vector3.ZERO)
	var relative_target_velocity = velocity - target_velocity
	var clearance = float(current_body.get("ground_clearance", 0.0))
	var previous_clearance = float(previous_body.get("ground_clearance", clearance))
	var preferred_clearance: float = maxf(
		float(current_body.get("preferred_ground_clearance", clearance)),
		0.05
	)
	var height_tolerance = maxf(preferred_clearance * 0.20, 0.22)
	var height_error = absf(clearance - preferred_clearance)
	var height_level_quality = exp(-pow(height_error / height_tolerance, 2.0))
	var vertical_speed_quality = exp(-pow(absf(velocity.y) / 0.75, 2.0))
	var previous_velocity: Vector3 = previous_body.get("linear_velocity_world", velocity)
	var vertical_acceleration = (
		absf(velocity.y - previous_velocity.y) / safe_delta
		if safe_delta > 0.000001
		else 0.0
	)
	var vertical_smoothness = exp(-pow(vertical_acceleration / 8.0, 2.0))
	var height_quality = height_level_quality * vertical_speed_quality * vertical_smoothness
	var height_recovery = clampf(
		(absf(previous_clearance - preferred_clearance) - height_error) / height_tolerance,
		-1.0,
		1.0
	)
	var core_contact = bool(current_body.get("core_contact", false))
	var core_support_contact = bool(current_body.get("core_support_contact", false))
	var obstacle_probe: Dictionary = objective.get("obstacle_probe", {})
	var wall_contact = bool(obstacle_probe.get("wall_contact", false))
	var pickup_item_reward_value: float = maxf(
		float(context.get("pickup_item_reward_value", 1.0)),
		0.0
	)
	var limbs: Array = current_observation.get("limbs", [])

	var raw_target_progress = clampf(previous_distance - current_distance, -1.0, 1.0)
	var raw_horizontal_target_progress = clampf(
		previous_horizontal_distance - current_horizontal_distance,
		-1.0,
		1.0
	)
	# Delivery intentionally reuses the generic target channel for a two-phase objective: cargo
	# before grip, destination after grip. A potential difference across that semantic target swap
	# is meaningless and could otherwise punish the exact frame where a successful grip occurs.
	var previous_objective_for_phase: Dictionary = previous_observation.get("objective", {})
	var previous_delivery_phase: String = str(previous_objective_for_phase.get("delivery_task_phase", ""))
	var current_delivery_phase: String = str(objective.get("delivery_task_phase", ""))
	if previous_delivery_phase != current_delivery_phase and (
		not previous_delivery_phase.is_empty() or not current_delivery_phase.is_empty()
	):
		raw_target_progress = 0.0
		raw_horizontal_target_progress = 0.0
	var components = {
		"survival": safe_delta,
		"uprightness": maxf((uprightness - 0.35) / 0.65, 0.0) * safe_delta,
		"core_rotational_stability": core_rotational_stability_signal(
			previous_angular_velocity,
			angular_velocity,
			safe_delta
		),
		"height_stability": (height_quality - 0.20 + maxf(height_recovery, 0.0) * 0.10) * safe_delta,
		"core_clearance": -pow(clampf((0.42 - clearance) / 0.42, 0.0, 1.0), 2.0) * safe_delta,
		"core_drag": -safe_delta if core_support_contact else 0.0,
		"target_progress": 0.0,
		"climb_reach": 0.0,
		"climb_grip": 0.0,
		"climb_ascent": 0.0,
		"jump_launch": 0.0,
		"jump_air_progress": 0.0,
		"jump_distance": 0.0,
		"landing_quality": 0.0,
		"target_search": -safe_delta if current_distance > target_radius else 0.0,
		"stable_target_hold": 0.0,
		"item_pickup": 0.0,
		"item_delivery": 0.0,
		"foot_support": 0.0,
		"foot_slip": 0.0,
		"command_change": -maxf(float(context.get("action_change_norm", 0.0)) - 0.12, 0.0),
		"actuator_saturation": 0.0,
		"joint_overstretch": 0.0,
		"torque_effort": 0.0,
		"obstacle_avoidance": 0.0,
		"turret_safety": 0.0,
		"core_collision": 0.0,
		"falling": 0.0,
	}
	if current_distance <= target_radius:
		var speed_factor = 1.0 - clampf(relative_target_velocity.length() / 3.0, 0.0, 1.0)
		var upright_factor = clampf((uprightness - 0.2) / 0.8, 0.0, 1.0)
		components["stable_target_hold"] = (
			speed_factor * upright_factor * lerpf(0.35, 1.0, height_quality) * safe_delta
		)

	var installed_count = 0
	var contact_count = 0
	var total_slip = 0.0
	var total_torque = 0.0
	var saturated_axis_count = 0
	var climb_grip_signal = 0.0
	var climbable_grip_attached = false
	for limb_index in range(limbs.size()):
		var limb_value: Variant = limbs[limb_index]
		if not (limb_value is Dictionary):
			continue
		var limb: Dictionary = limb_value
		if not bool(limb.get("installed", false)):
			continue
		installed_count += 1
		if bool(limb.get("foot_contact", false)):
			contact_count += 1
			total_slip += float(limb.get("foot_slip_speed", 0.0))
		var torque: Vector3 = limb.get("applied_torque", Vector3.ZERO)
		total_torque += absf(torque.x) + absf(torque.y) + absf(torque.z)
		var saturation: Vector3 = limb.get("saturation", Vector3.ZERO)
		saturated_axis_count += int(saturation.x > 0.5) + int(saturation.y > 0.5) + int(saturation.z > 0.5)
		if climb_need > 0.0 and bool(limb.get("grip_attached_climbable", false)):
			climbable_grip_attached = true
			var climb_target_id: int = int(limb.get("grip_attached_target_id", 0))
			# Pay a real attachment event, never the mere command or an indefinitely held wall. The
			# full-3D target-progress card pays the actual ascent afterward, so wall-hugging cannot
			# become a profitable substitute for reaching the elevated objective. Include the limb
			# index in the key so each independently controlled grip can discover useful support once.
			var climb_grab_key: String = "%d:%d" % [limb_index, climb_target_id]
			var rewarded_climb_grabs: Dictionary = worker_state.get(
				"rewarded_climb_grab_ids",
				{}
			)
			if climb_target_id > 0 and not rewarded_climb_grabs.has(climb_grab_key):
				rewarded_climb_grabs[climb_grab_key] = true
				worker_state["rewarded_climb_grab_ids"] = rewarded_climb_grabs
				climb_grip_signal += 1.0 * climb_need
		if bool(limb.get("grip_attached", false)) and bool(limb.get("grip_attached_dynamic", false)):
			var held_id = int(limb.get("grip_attached_target_id", 0))
			var assigned_id = int(context.get("assigned_pickup_item_id", 0))
			var tags_value: Variant = limb.get(
				"grip_attached_surface_tags",
				PackedStringArray()
			)
			var carryable = _surface_tags_have(tags_value, "carryable")
			var matches_assignment = assigned_id <= 0 or held_id == assigned_id
			if held_id > 0 and carryable and matches_assignment:
				var grabbed: Dictionary = worker_state.get("rewarded_grab_ids", {})
				var grip_heights: Dictionary = worker_state.get("pickup_grab_height_by_id", {})
				var current_item_height: float = _pickup_item_height_for_id(
					current_observation,
					held_id
				)
				if not grip_heights.has(held_id):
					# Establish the worker-local lift baseline at the first observed attachment.
					# Shared authored items may already have been moved or lifted by another worker.
					grip_heights[held_id] = current_item_height
					worker_state["pickup_grab_height_by_id"] = grip_heights
				if not grabbed.has(held_id):
					grabbed[held_id] = true
					worker_state["rewarded_grab_ids"] = grabbed
					components["item_pickup"] = (
						float(components["item_pickup"])
						+ 0.20 * pickup_item_reward_value
					)
				var lifted: Dictionary = worker_state.get("rewarded_pickup_ids", {})
				var grip_height: float = float(grip_heights.get(held_id, current_item_height))
				var lift_height: float = maxf(current_item_height - grip_height, 0.0)
				if lift_height >= 0.12 and not lifted.has(held_id):
					lifted[held_id] = true
					worker_state["rewarded_pickup_ids"] = lifted
					var mass_quality = clampf(
						float(limb.get("grip_attached_target_mass", 0.0)) / 5.0,
						0.0,
						1.0
					)
					var lift_quality = clampf(lift_height / 0.45, 0.0, 1.0)
					components["item_pickup"] = (
						float(components["item_pickup"])
						+ (
							0.80
							+ mass_quality * 0.20
							+ lift_quality * 0.25
						) * pickup_item_reward_value
					)
	var delivery_present: bool = bool(context.get("delivery_destination_present", false))
	var delivery_held: bool = bool(context.get("delivery_item_held", false))
	var delivery_accepted: bool = bool(context.get("delivery_item_accepted", false))
	var delivery_item_id: int = maxi(
		RLTrainingMath.finite_int_or(context.get("delivery_item_instance_id", 0), 0),
		0
	)
	var delivery_group_id: int = maxi(
		RLTrainingMath.finite_int_or(context.get("delivery_destination_group_id", 0), 0),
		0
	)
	var delivery_stable_id: String = str(context.get("delivery_destination_stable_id", ""))
	if delivery_present and delivery_held and delivery_accepted and delivery_item_id > 0 and not delivery_stable_id.is_empty():
		var current_delivery_distance: float = maxf(
			RLTrainingMath.finite_float_or(context.get("delivery_destination_distance_m", 0.0), 0.0),
			0.0
		)
		var previous_objective: Dictionary = previous_observation.get("objective", {})
		var previous_delivery_group_id: int = maxi(
			RLTrainingMath.finite_int_or(
				previous_objective.get("delivery_destination_group_id", 0),
				0
			),
			0
		)
		var same_delivery_policy: bool = (
			RLTrainingMath.finite_int_or(previous_objective.get("delivery_item_instance_id", 0), 0) == delivery_item_id
			and bool(previous_objective.get("delivery_item_held", false))
			and (
				previous_delivery_group_id == delivery_group_id
				if delivery_group_id > 0
				else str(previous_objective.get("delivery_destination_stable_id", "")) == delivery_stable_id
			)
		)
		if same_delivery_policy:
			var previous_delivery_distance: float = maxf(
				RLTrainingMath.finite_float_or(
					previous_objective.get("delivery_destination_distance_m", current_delivery_distance),
					current_delivery_distance
				),
				0.0
			)
			var approach_scale: float = maxf(
				RLTrainingMath.finite_float_or(context.get("delivery_approach_reward_scale", 1.0), 1.0),
				0.0
			)
			var delivery_item_value: float = maxf(
				RLTrainingMath.finite_float_or(context.get("delivery_item_reward_value", 1.0), 1.0),
				0.0
			)
			components["item_delivery"] = clampf(
				previous_delivery_distance - current_delivery_distance,
				-0.5,
				0.5
			) * approach_scale * delivery_item_value
		# A physical cargo item can complete at most one delivery per worker episode, even when
		# several destination groups accept its type. Group-scoped keys let the same parcel be walked
		# out of one bay and sold again in another, which is a completion-reward exploit rather than a
		# second task. Routing may still switch groups freely before the first valid delivery.
		var delivery_key: String = "item:%d" % delivery_item_id
		var item_eligibility: Dictionary = worker_state.get("delivery_item_eligibility", {})
		var item_eligibility_key: String = str(delivery_item_id)
		if not item_eligibility.has(item_eligibility_key):
			# Eligibility is fixed on the first held observation for the item, not per destination. If
			# cargo was first grabbed while already sitting in any accepting bay, walking it out and
			# back in must never manufacture a delivery. Conversely, an item first held outside stays
			# eligible even if nearest-destination routing switches groups as it crosses a valid bay.
			item_eligibility[item_eligibility_key] = not bool(context.get("delivery_item_inside", false))
			worker_state["delivery_item_eligibility"] = item_eligibility
		var previous_item_id: int = RLTrainingMath.finite_int_or(
			previous_objective.get("delivery_item_instance_id", 0),
			0
		)
		var previous_held_same_item: bool = (
			bool(previous_objective.get("delivery_item_held", false))
			and previous_item_id == delivery_item_id
		)
		# `_best_delivery_destination_for_item()` is containment-first across *all* accepting
		# groups, so previous_inside=false means the item was outside every accepting destination.
		# Completion therefore remains correct even if the routed nearest group changes on entry.
		var previous_inside: bool = bool(previous_objective.get("delivery_item_inside", false))
		var crossed_into_destination: bool = (
			bool(item_eligibility.get(item_eligibility_key, false))
			and previous_held_same_item
			and not previous_inside
			and bool(context.get("delivery_item_inside", false))
		)
		if crossed_into_destination:
			var delivered: Dictionary = worker_state.get("rewarded_delivery_keys", {})
			if not delivered.has(delivery_key):
				delivered[delivery_key] = true
				worker_state["rewarded_delivery_keys"] = delivered
				var completion_scale: float = maxf(
					RLTrainingMath.finite_float_or(context.get("delivery_completion_reward_scale", 1.0), 1.0),
					0.0
				)
				var completion_item_value: float = maxf(
					RLTrainingMath.finite_float_or(context.get("delivery_item_reward_value", 1.0), 1.0),
					0.0
				)
				components["item_delivery"] = float(components["item_delivery"]) + completion_scale * completion_item_value

	var previous_limbs: Array = previous_observation.get("limbs", [])
	if climb_need > 0.0:
		components["climb_reach"] = (
			_climb_reach_potential(limbs) - _climb_reach_potential(previous_limbs)
		) * climb_need
		var previous_climb_max: float = float(worker_state.get("climb_max_core_y", -INF))
		if not is_finite(previous_climb_max):
			previous_climb_max = previous_position.y
		if climbable_grip_attached and current_position.y > previous_climb_max:
			components["climb_ascent"] = current_position.y - previous_climb_max
		worker_state["climb_max_core_y"] = maxf(previous_climb_max, current_position.y)
	else:
		worker_state["climb_max_core_y"] = -INF

	var support_ratio = float(contact_count) / float(maxi(installed_count, 1))
	components["climb_grip"] = climb_grip_signal
	# Target pursuit is the task objective, so keep its signed potential difference independent of
	# uprightness and foot support: an ugly first step must still teach PPO that locomotion matters.
	# Chassis support is different: it is an explicit exploit state. A body rolling/crawling on the
	# core could previously earn metres of target progress faster than the fixed per-second core-drag
	# cost, despite the card claiming that head-rolling could not farm reward. Preserve 10% of positive
	# progress as a recovery hint while the chassis is load-bearing, but never attenuate moving away.
	var locomotion_progress: float = raw_target_progress
	if core_support_contact and locomotion_progress > 0.0:
		locomotion_progress *= 0.10
	components["target_progress"] = locomotion_progress
	components["foot_support"] = support_ratio * maxf(uprightness, 0.0) * safe_delta
	# One metre/second of average planted-foot slip is already severe skating for this body scale.
	# The old /4 normalization made even visibly sliding feet nearly free compared with target
	# progress, so PPO could be rewarded for translating by skating instead of learning stance
	# transfer. Keep a little headroom for impacts while making ordinary planted slip meaningful.
	components["foot_slip"] = -clampf(
		total_slip / float(maxi(contact_count, 1)) / 1.5,
		0.0,
		1.0
	) * safe_delta
	components["torque_effort"] = -clampf(total_torque / 1200.0, 0.0, 1.0) * safe_delta
	var joint_overstretch_ratio = _joint_overstretch_ratio(limbs, climb_need)
	if joint_overstretch_ratio > 0.001:
		worker_state["joint_overstretch_elapsed"] = (
			float(worker_state.get("joint_overstretch_elapsed", 0.0)) + safe_delta
		)
	else:
		worker_state["joint_overstretch_elapsed"] = maxf(
			float(worker_state.get("joint_overstretch_elapsed", 0.0)) - safe_delta * 2.0,
			0.0
		)
	var overstretch_elapsed = float(worker_state.get("joint_overstretch_elapsed", 0.0))
	var sustained_factor = clampf(
		(overstretch_elapsed - JOINT_OVERSTRETCH_GRACE_SECONDS)
		/ maxf(
			JOINT_OVERSTRETCH_FULL_PENALTY_SECONDS - JOINT_OVERSTRETCH_GRACE_SECONDS,
			0.001
		),
		0.0,
		1.0
	)
	components["joint_overstretch"] = -joint_overstretch_ratio * sustained_factor * safe_delta

	_update_jump_components(
		components,
		worker_state,
		previous_position,
		current_position,
		current_target_offset_horizontal,
		previous_velocity,
		velocity,
		clearance,
		uprightness,
		support_ratio,
		core_support_contact,
		raw_horizontal_target_progress,
		safe_delta
	)

	var saturation_ratio = float(saturated_axis_count) / float(FourLimbMLAction.JOINT_ACTION_COUNT)
	if saturation_ratio >= 0.5:
		worker_state["saturation_elapsed"] = float(worker_state.get("saturation_elapsed", 0.0)) + safe_delta
	else:
		worker_state["saturation_elapsed"] = maxf(float(worker_state.get("saturation_elapsed", 0.0)) - safe_delta * 2.0, 0.0)
	if float(worker_state.get("saturation_elapsed", 0.0)) > 0.3:
		components["actuator_saturation"] = -saturation_ratio * safe_delta
	var nearest_wall_distance = float(obstacle_probe.get(
		"nearest_distance_m",
		FourLimbMLObservation.OBSTACLE_RAY_MAXIMUM_DISTANCE_M
	))
	var closing_speed = float(obstacle_probe.get("closing_speed_mps", 0.0))
	var danger_distance = 2.5
	if nearest_wall_distance < danger_distance and closing_speed > 0.1:
		var proximity = 1.0 - clampf(nearest_wall_distance / danger_distance, 0.0, 1.0)
		var closing = clampf((closing_speed - 0.1) / 4.0, 0.0, 1.0)
		var climb_approach_scale = 1.0
		if climb_need > 0.0 and bool(obstacle_probe.get("target_path_blocked", false)):
			# An elevated target behind the nearby wall is the one case where approaching that wall is
			# necessary. Keep a residual safety cost so smashing the core into it is still undesirable.
			climb_approach_scale = lerpf(1.0, 0.20, climb_need)
		components["obstacle_avoidance"] = (
			-proximity * closing * climb_approach_scale * safe_delta
		)
	var combat_events: Dictionary = context.get("combat_events", {})
	var turret_threat: Dictionary = context.get("turret_threat_probe", {})
	var hit_count = maxi(int(combat_events.get("hit_count", 0)), 0)
	var damage_taken = maxf(float(combat_events.get("damage_taken", 0.0)), 0.0)
	var threat_level = (
		clampf(float(turret_threat.get("threat_level", 0.0)), 0.0, 1.0)
		if bool(turret_threat.get("present", false))
		else 0.0
	)
	components["turret_safety"] = -(
		0.65 * float(hit_count)
		+ 0.025 * damage_taken
		+ 0.08 * threat_level * safe_delta
	)
	var collision_active = core_contact or wall_contact
	var contact_was_active = bool(worker_state.get(
		"collision_active",
		worker_state.get("core_contact_active", false)
	))
	if collision_active and not contact_was_active:
		var impulse = float(obstacle_probe.get("maximum_contact_impulse", 0.0))
		components["core_collision"] = -1.0 - clampf(impulse / 120.0, 0.0, 1.0)
	worker_state["collision_active"] = collision_active
	if clearance < 0.8 and velocity.y < -0.25:
		components["falling"] = -clampf((-velocity.y - 0.25) / 4.0, 0.0, 1.0) * (1.0 - clampf(clearance / 0.8, 0.0, 1.0)) * safe_delta

	return _apply_components(components, worker_state)


func _update_jump_components(
	components: Dictionary,
	worker_state: Dictionary,
	previous_position: Vector3,
	current_position: Vector3,
	current_target_offset_horizontal: Vector3,
	previous_velocity: Vector3,
	current_velocity: Vector3,
	clearance: float,
	uprightness: float,
	support_ratio: float,
	core_support_contact: bool,
	raw_target_progress: float,
	delta: float
) -> void:
	var initialized = bool(worker_state.get("support_state_initialized", false))
	var previous_support_ratio = float(worker_state.get("previous_support_ratio", support_ratio))
	var jump_active = bool(worker_state.get("jump_active", false))
	var supported_preparation_elapsed = float(worker_state.get(
		"supported_preparation_elapsed",
		0.0
	))
	var launched = (
		initialized
		and not jump_active
		and previous_support_ratio >= JUMP_MINIMUM_LAUNCH_SUPPORT_RATIO
		and support_ratio <= 0.0
		and current_velocity.y >= JUMP_MINIMUM_LAUNCH_VERTICAL_SPEED_MPS
		and supported_preparation_elapsed >= JUMP_MINIMUM_SUPPORTED_PREPARATION_SECONDS
		and not core_support_contact
	)
	if launched:
		jump_active = true
		worker_state["jump_active"] = true
		worker_state["jump_qualified"] = false
		worker_state["jump_launch_rewarded"] = false
		worker_state["jump_elapsed"] = 0.0
		worker_state["jump_start_position"] = previous_position
		worker_state["jump_start_clearance"] = clearance
		worker_state["jump_max_clearance"] = clearance
		var target_direction = current_target_offset_horizontal.normalized()
		worker_state["jump_target_direction"] = target_direction
		var target_speed = (
			current_velocity.dot(target_direction)
			if not target_direction.is_zero_approx()
			else Vector3(current_velocity.x, 0.0, current_velocity.z).length()
		)
		var upward_quality = clampf(
			(current_velocity.y - JUMP_MINIMUM_LAUNCH_VERTICAL_SPEED_MPS) / 3.35,
			0.0,
			1.0
		)
		var target_speed_quality = clampf(target_speed / 6.0, 0.0, 1.0)
		# Upward impulse is necessary, but a long-jump lesson should prefer takeoff velocity
		# aimed at the target over a stationary jumping-jack hop.
		worker_state["jump_launch_quality"] = upward_quality * 0.45 + target_speed_quality * 0.55

	if jump_active:
		worker_state["jump_elapsed"] = float(worker_state.get("jump_elapsed", 0.0)) + delta
		worker_state["jump_max_clearance"] = maxf(
			float(worker_state.get("jump_max_clearance", clearance)),
			clearance
		)
		if support_ratio <= 0.0 and not core_support_contact:
			var jump_elapsed = float(worker_state.get("jump_elapsed", 0.0))
			var clearance_gain = (
				float(worker_state.get("jump_max_clearance", clearance))
				- float(worker_state.get("jump_start_clearance", clearance))
			)
			var qualified = bool(worker_state.get("jump_qualified", false))
			if (
				not qualified
				and jump_elapsed >= JUMP_MINIMUM_AIRTIME_SECONDS
				and clearance_gain >= JUMP_MINIMUM_CLEARANCE_GAIN_M
			):
				qualified = true
				worker_state["jump_qualified"] = true
			if qualified:
				if not bool(worker_state.get("jump_launch_rewarded", false)):
					components["jump_launch"] = float(worker_state.get("jump_launch_quality", 0.0))
					worker_state["jump_launch_rewarded"] = true
				var airborne_uprightness = clampf((uprightness - 0.10) / 0.90, 0.0, 1.0)
				components["jump_air_progress"] = maxf(raw_target_progress, 0.0) * airborne_uprightness
		else:
			var jump_elapsed = float(worker_state.get("jump_elapsed", 0.0))
			var qualified = bool(worker_state.get("jump_qualified", false))
			if qualified and jump_elapsed >= JUMP_MINIMUM_AIRTIME_SECONDS:
				var jump_start: Vector3 = worker_state.get("jump_start_position", previous_position)
				var displacement = current_position - jump_start
				displacement.y = 0.0
				var jump_direction: Vector3 = worker_state.get("jump_target_direction", Vector3.ZERO)
				var jump_distance = (
					maxf(displacement.dot(jump_direction), 0.0)
					if not jump_direction.is_zero_approx()
					else displacement.length()
				)
				var feet_first = support_ratio > 0.0 and not core_support_contact
				var landing_uprightness = clampf((uprightness - 0.15) / 0.85, 0.0, 1.0)
				var impact_speed = maxf(-previous_velocity.y, 0.0)
				var impact_quality = 1.0 - clampf((impact_speed - 0.5) / 5.0, 0.0, 1.0)
				var support_quality = clampf(support_ratio / 0.5, 0.0, 1.0)
				var landing_score = (
					landing_uprightness * impact_quality * support_quality
					if feet_first
					else 0.0
				)
				var distance_quality = clampf((jump_distance - 0.15) / 0.85, 0.0, 1.0)
				components["jump_distance"] = clampf(jump_distance / 6.0, 0.0, 1.0) * landing_score
				components["landing_quality"] = (
					clampf((landing_score - 0.35) / 0.65, 0.0, 1.0) * distance_quality
					if feet_first and landing_score >= 0.35
					else -(1.0 - landing_score)
				)
			worker_state["jump_active"] = false
			worker_state["jump_qualified"] = false
			worker_state["jump_launch_rewarded"] = false
			worker_state["jump_elapsed"] = 0.0
			worker_state["jump_start_position"] = current_position
			worker_state["jump_start_clearance"] = clearance
			worker_state["jump_target_direction"] = Vector3.ZERO
			worker_state["jump_launch_quality"] = 0.0
			worker_state["jump_max_clearance"] = clearance

	if support_ratio >= JUMP_MINIMUM_LAUNCH_SUPPORT_RATIO and not core_support_contact:
		worker_state["supported_preparation_elapsed"] = supported_preparation_elapsed + delta
	else:
		worker_state["supported_preparation_elapsed"] = 0.0
	worker_state["support_state_initialized"] = true
	worker_state["previous_support_ratio"] = support_ratio


static func _climb_reach_potential(limbs: Array) -> float:
	if limbs.is_empty():
		return 0.0
	var accumulated = 0.0
	var installed_count = 0
	for limb_value: Variant in limbs:
		if not (limb_value is Dictionary):
			continue
		var limb: Dictionary = limb_value
		if not bool(limb.get("installed", false)) or not bool(limb.get("grip_present", false)):
			continue
		installed_count += 1
		if bool(limb.get("grip_attached_climbable", false)):
			accumulated += 1.0
			continue
		if not bool(limb.get("grip_candidate_present", false)) or not bool(limb.get("grip_candidate_climbable", false)):
			continue
		var effector: Dictionary = limb.get("end_effector", {})
		var detection_radius: float = maxf(
			float(effector.get("grip_detection_radius", 1.10)),
			float(effector.get("grip_acquisition_radius", 0.24))
		)
		var distance: float = maxf(float(limb.get("grip_candidate_distance", detection_radius)), 0.0)
		accumulated += 1.0 - clampf(distance / maxf(detection_radius, 0.01), 0.0, 1.0)
	return accumulated / float(maxi(installed_count, 1))


static func _joint_overstretch_ratio(limbs: Array, climb_need: float = 0.0) -> float:
	var installed_count = 0
	var accumulated_risk = 0.0
	for limb_value: Variant in limbs:
		if not (limb_value is Dictionary):
			continue
		var limb: Dictionary = limb_value
		if not bool(limb.get("installed", false)):
			continue
		installed_count += 1
		var angles: Vector3 = limb.get("joint_angles", Vector3.ZERO)
		var lower: Vector3 = limb.get(
			"joint_limit_lower",
			Vector3(deg_to_rad(-68.0), deg_to_rad(-72.0), deg_to_rad(-8.0))
		)
		var upper: Vector3 = limb.get(
			"joint_limit_upper",
			Vector3(deg_to_rad(68.0), deg_to_rad(72.0), deg_to_rad(72.0))
		)
		var hip_elevation_onset: float = (
			lerpf(0.78, 0.96, clampf(climb_need, 0.0, 1.0))
			if angles.x > 0.0
			else 0.78
		)
		var hip_elevation_risk = _joint_edge_risk(
			angles.x, lower.x, upper.x, hip_elevation_onset
		)
		var hip_sweep_risk = _joint_edge_risk(angles.y, lower.y, upper.y, 0.80)
		var knee_risk = _joint_edge_risk(angles.z, lower.z, upper.z, 0.70) * 0.60
		# A limb is only as safe as its most overextended joint. Averaging limbs keeps the
		# signal independent of the number of installed legs while weighting hips strongest.
		accumulated_risk += maxf(maxf(hip_elevation_risk, hip_sweep_risk), knee_risk)
	return accumulated_risk / float(maxi(installed_count, 1))


static func _joint_edge_risk(
	angle: float,
	lower_limit: float,
	upper_limit: float,
	onset_ratio: float
) -> float:
	var available_range = upper_limit if angle >= 0.0 else absf(lower_limit)
	if available_range <= 0.000001:
		return 0.0
	var utilization = absf(angle) / available_range
	return pow(
		clampf((utilization - onset_ratio) / maxf(1.0 - onset_ratio, 0.001), 0.0, 1.0),
		2.0
	)


static func core_rotational_stability_signal(
	previous_angular_velocity_world: Vector3,
	current_angular_velocity_world: Vector3,
	delta: float
) -> float:
	var safe_delta = maxf(delta, 0.0)
	if safe_delta <= 0.000001:
		return 0.0
	# Intentional heading changes are yaw around the world's up axis. Exclude sustained yaw speed
	# from the rocking cost so a body can turn freely, but keep a small explicit penalty for a fast
	# yaw direction reversal because left-right heading chatter is still rotational jitter.
	var previous_yaw_rate = previous_angular_velocity_world.dot(Vector3.UP)
	var current_yaw_rate = current_angular_velocity_world.dot(Vector3.UP)
	var previous_tilt_rate = previous_angular_velocity_world - (
		Vector3.UP * previous_yaw_rate
	)
	var current_tilt_rate = current_angular_velocity_world - (
		Vector3.UP * current_yaw_rate
	)
	var tilt_speed = current_tilt_rate.length()
	var stable_speed = 0.35
	var full_cost_speed = 3.5
	var rate_penalty = clampf(
		(tilt_speed - stable_speed) / maxf(full_cost_speed - stable_speed, 0.001),
		0.0,
		1.0
	)
	var stable_quality = 1.0 - clampf(tilt_speed / stable_speed, 0.0, 1.0)
	var tilt_acceleration = (current_tilt_rate - previous_tilt_rate).length() / safe_delta
	var acceleration_penalty = clampf(
		(tilt_acceleration - 3.0) / 17.0,
		0.0,
		1.0
	)
	var yaw_reversal_penalty = 0.0
	if previous_yaw_rate * current_yaw_rate < 0.0:
		var reversal_speed = minf(absf(previous_yaw_rate), absf(current_yaw_rate))
		yaw_reversal_penalty = clampf((reversal_speed - 0.35) / 2.65, 0.0, 1.0)
	# A small calmness reward helps discover stable support. Sustained yaw has no rate cost, while
	# pitch/roll motion and abrupt yaw reversals dominate only when the body actually jitters.
	return (
		0.20 * stable_quality
		- rate_penalty
		- 0.35 * acceleration_penalty
		- 0.35 * yaw_reversal_penalty
	) * safe_delta



static func current_support_surface_height(body: Dictionary) -> float:
	var core_position: Vector3 = body.get("position_world", Vector3.ZERO)
	var clearance: float = maxf(float(body.get("ground_clearance", 0.0)), 0.0)
	var preferred_core_height: float = maxf(float(body.get("preferred_core_height", 0.0)), 0.0)
	var preferred_clearance: float = maxf(
		float(body.get("preferred_ground_clearance", preferred_core_height)),
		0.0
	)
	# The preferred values differ by the core's vertical half extent. Removing both the current
	# clearance and that extent recovers the approximate support-surface height under the body.
	var core_half_height: float = maxf(preferred_core_height - preferred_clearance, 0.0)
	return core_position.y - clearance - core_half_height


static func climb_height_need(body: Dictionary, objective: Dictionary) -> float:
	var support_height: float = current_support_surface_height(body)
	var subject_value: Variant = objective.get("target_subject_position_world", null)
	if subject_value is Vector3 and (subject_value as Vector3).is_finite():
		var subject_height: float = (subject_value as Vector3).y
		return clampf(
			(subject_height - support_height - CLIMB_HEIGHT_START_M)
			/ maxf(CLIMB_HEIGHT_FULL_M - CLIMB_HEIGHT_START_M, 0.001),
			0.0,
			1.0
		)
	# Custom target providers may not expose a visible support-surface subject. In that case compare
	# their routed policy point against the body's nominal core height with a wider dead zone, so an
	# arbitrary elevated custom objective does not immediately masquerade as a full climbing lesson.
	var preferred_core_height: float = maxf(float(body.get("preferred_core_height", 0.0)), 0.0)
	var nominal_core_target_height: float = support_height + preferred_core_height
	var target_goal: Vector3 = target_goal_position_world(body, objective)
	var excess_height: float = target_goal.y - nominal_core_target_height
	return clampf(
		(excess_height - CLIMB_FALLBACK_HEIGHT_START_M)
		/ maxf(CLIMB_FALLBACK_HEIGHT_FULL_M - CLIMB_FALLBACK_HEIGHT_START_M, 0.001),
		0.0,
		1.0
	)


static func target_goal_position_world(body: Dictionary, objective: Dictionary) -> Vector3:
	var body_position: Vector3 = body.get("position_world", Vector3.ZERO)
	# The coordinator has already resolved the final body-specific core objective. For four-limb path
	# targets that means one authored standing height above the destination support surface. Reward
	# exactly the point exposed to the observation tensor.
	return objective.get("target_position_world", body_position)


static func target_goal_distance(body: Dictionary, objective: Dictionary) -> float:
	if not body.has("position_world") or not objective.has("target_position_world"):
		return INF
	var position: Vector3 = body["position_world"]
	return position.distance_to(target_goal_position_world(body, objective))


static func _pickup_item_height_for_id(observation: Dictionary, item_id: int) -> float:
	if item_id <= 0:
		return 0.0
	var objective: Dictionary = observation.get("objective", {})
	if int(objective.get("pickup_item_id", 0)) != item_id:
		return 0.0
	var position_value: Variant = objective.get("pickup_item_position_world", Vector3.ZERO)
	if not (position_value is Vector3):
		return 0.0
	var position: Vector3 = position_value as Vector3
	return position.y if is_finite(position.y) else 0.0


static func _surface_tags_have(value: Variant, expected: String) -> bool:
	if value is PackedStringArray:
		return (value as PackedStringArray).has(expected)
	if value is Array:
		for entry: Variant in value:
			if str(entry) == expected:
				return true
	return false


func terminal_reward(
	worker_state: Dictionary,
	failure_reason: String,
	timed_out: bool
) -> Dictionary:
	var components = {"failure": 0.0, "timeout": 0.0}
	if timed_out:
		components["timeout"] = 1.0
	elif not failure_reason.is_empty():
		var elapsed = float(worker_state.get("elapsed", 0.0))
		var early_multiplier = 1.0 + clampf((4.0 - elapsed) / 4.0, 0.0, 1.0) * 1.5
		components["failure"] = -early_multiplier
	return _apply_components(components, worker_state)


func configuration_dictionary() -> Dictionary:
	var result = {}
	for card_value: FourLimbRewardCard in card_list():
		result[card_value.card_id] = card_value.to_dictionary()
	return result


func load_configuration(value: Dictionary) -> void:
	for card_id: String in cards:
		if value.get(card_id, {}) is Dictionary:
			(cards[card_id] as FourLimbRewardCard).load_dictionary(value[card_id])


func _apply_components(
	raw_components: Dictionary,
	worker_state: Dictionary
) -> Dictionary:
	var scaled = {}
	var total = 0.0
	var episode_totals: Dictionary = worker_state.get("episode_totals", {})
	for card_id: String in raw_components:
		var card_value = card(card_id)
		if card_value == null:
			continue
		var contribution = (
			float(raw_components[card_id]) * card_value.intensity
			if card_value.enabled
			else 0.0
		)
		scaled[card_id] = contribution
		total += contribution
		episode_totals[card_id] = float(episode_totals.get(card_id, 0.0)) + contribution
	worker_state["episode_totals"] = episode_totals
	worker_state["last_components"] = scaled
	return {"total": total, "components": scaled}


func _add(
	id_value: String,
	name_value: String,
	explanation_value: String,
	intensity_value: float,
	minimum_value: float,
	maximum_value: float,
	step_value: float,
	signal_type_value: int,
	enabled_value: bool = true
) -> void:
	cards[id_value] = FourLimbRewardCard.new(
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
