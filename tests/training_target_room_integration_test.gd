extends SceneTree

#######################################################
# Focused room-level regression coverage for the per-group target migration. The room-default
# target is evaluator/template state, not an extra worker target, and every runtime worker group
# must own an independent handler before target dispatch.
#######################################################

var failure_count: int = 0
var assertion_count: int = 0


func _init() -> void:
	_test_default_target_visual_only_tracks_evaluators()
	_test_runtime_group_dispatch_repairs_missing_handler()
	_test_drone_target_height_is_literal()
	_test_limb_target_marker_is_support_surface()
	_test_turret_group_publishes_live_runtime_members()
	_test_fresh_drone_model_architecture_reaches_constructor()
	_test_model_body_creator_carries_training_setup()
	_test_paused_drone_candidate_keeps_frozen_hardware()
	_test_room_episode_status_is_one_shared_line()
	_test_room_ready_does_not_create_default_worker_group()
	_test_library_windows_start_hidden()

	if failure_count == 0:
		print("Training target room integration tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("Training target room integration tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _new_room_with_target_visuals() -> DroneTrainingRoom:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room._initialize_targeting()
	room._build_target()
	return room



func _test_library_windows_start_hidden() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.turret_ui.configure(room, room.turret_training, room.turret_model_registry)
	room._build_model_browser()
	room._build_limb_model_browser()
	room.turret_ui.build_model_browser()
	room._build_map_browser()
	_expect(not room.model_browser.visible, "drone model library starts hidden")
	_expect(not room.limb_model_browser.visible, "four-limb model library starts hidden")
	_expect(not room.turret_ui.model_browser.visible, "turret model library starts hidden")
	_expect(not room.map_browser.visible, "training map library starts hidden")
	room.free()


func _test_model_body_creator_carries_training_setup() -> void:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	get_root().add_child(panel)
	panel._load_preset_at(0)
	_expect(panel.current_body_kind == "drone", "model creator opens on the authored quad-drone preset")
	panel.hidden_width_input.value = 96.0
	panel.hidden_depth_input.value = 3.0
	panel.worker_count_input.value = 6.0
	panel.control_rate_input.value = 30.0
	panel.exploration_input.value = 0.035
	panel.start_training_checkbox.button_pressed = false
	var request: Dictionary = panel._training_request()
	_expect(
		int(request.get("hidden_layer_width", -1)) == 96
		and int(request.get("hidden_layer_depth", -1)) == 3,
		"model creator preserves the requested neural-network width/depth"
	)
	_expect(
		int(request.get("worker_count", -1)) == 6
		and is_equal_approx(float(request.get("control_rate_hz", 0.0)), 30.0),
		"model creator preserves starting worker count and policy control rate"
	)
	_expect(
		is_equal_approx(float(request.get("exploration_strength", -1.0)), 0.035)
		and not bool(request.get("start_active", true)),
		"model creator can create a tuned group without starting training immediately"
	)
	_expect(
		str(request.get("reward_cardset_id", "")) == "builtin:drone_balanced"
		and not (request.get("reward_cards", {}) as Dictionary).is_empty(),
		"model creator sends the selected reward-card preset with the fresh worker group"
	)
	panel.free()


func _test_paused_drone_candidate_keeps_frozen_hardware() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	var live_loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	var frozen_record: Dictionary = DroneTrainingLoadoutConfig.to_record(live_loadout)
	var contract: Dictionary = RLEvaluationContract.create("drone", {
		"hardware": frozen_record,
	})
	var candidate: Dictionary = {
		"candidate_id": 81,
		"evaluation_contract": contract,
		"evaluation_contract_hash": str(contract.get("contract_hash", "")),
	}
	var trainer: DroneTrainingAlgorithm = DroneTrainingAlgorithmCatalog.create("ppo_clip")
	trainer.set_evaluation_contract(contract)
	var group: Dictionary = {
		"group_id": 81,
		"active": false,
		"trainer": trainer,
		"drone_loadout": live_loadout,
		"candidate_drone_loadout_cache": {},
	}
	room._cache_drone_evaluation_loadout(group, contract, live_loadout)
	# The optimizer may still be running when the user pauses. Fill the bounded cache with newer
	# pause-time hardware contracts before a pending candidate formally exists; the trainer's frozen
	# pre-nomination contract must remain protected from eviction.
	for edit_index in range(8):
		var edited: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(live_loadout)
		edited.battery.energy_capacity_wh += float(edit_index + 1)
		var edited_contract: Dictionary = RLEvaluationContract.create("drone", {
			"hardware": DroneTrainingLoadoutConfig.to_record(edited),
		})
		room._cache_drone_evaluation_loadout(group, edited_contract, edited)
	_expect(
		(group.get("candidate_drone_loadout_cache", {}) as Dictionary).has(
			str(contract.get("contract_hash", ""))
		),
		"paused drone cache retains the trainer contract while a background update can still nominate it"
	)
	# Paused hardware editing is intentionally allowed. The pending candidate must keep the exact
	# body it was nominated with instead of inheriting this later live edit or failing reconstruction.
	live_loadout.battery.energy_capacity_wh += 0.75
	_expect(
		not DroneTrainingLoadoutConfig.records_match(
			frozen_record,
			DroneTrainingLoadoutConfig.to_record(live_loadout)
		),
		"test mutation changes the paused group's live drone hardware record"
	)
	var frozen_loadout: DroneLoadout = room._candidate_drone_loadout(group, candidate)
	_expect(
		frozen_loadout != null
		and DroneTrainingLoadoutConfig.records_match(
			frozen_record,
			DroneTrainingLoadoutConfig.to_record(frozen_loadout)
		),
		"paused drone fixed-seed evaluation resolves the candidate's frozen body independently of later live edits"
	)
	room.free()


func _test_room_episode_status_is_one_shared_line() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.episode_status_label = Label.new()
	room.add_child(room.episode_status_label)
	room.worker_groups.append({
		"group_id": 91,
		"active": false,
	})
	room.limb_training.groups.append({
		"group_id": 92,
		"name": "Walker",
		"active": true,
		"episode": 7,
		"workers": [],
		"awaiting_respawn": false,
	})
	room._refresh_episode_status()
	_expect(
		not room.episode_status_label.text.contains("\n")
		and room.episode_status_label.text.contains("Episode length 20.0 s")
		and room.episode_status_label.text.contains("1 active model")
		and room.episode_status_label.text.contains("1 paused model")
		and not room.episode_status_label.text.contains("Drones ·")
		and not room.episode_status_label.text.contains("Walker ·"),
		"room episode status uses one shared-duration line instead of one timer row per worker family"
	)
	room.free()


func _test_room_ready_does_not_create_default_worker_group() -> void:
	var source: String = FileAccess.get_file_as_string("res://ml/training/drone_training_room.gd")
	var ready_start: int = source.find("func _ready() -> void:")
	var next_function: int = source.find("\nfunc ", ready_start + 1)
	var ready_source: String = source.substr(
		ready_start,
		(next_function - ready_start) if next_function > ready_start else source.length() - ready_start
	)
	_expect(
		ready_start >= 0 and not ready_source.contains("_create_worker_group("),
		"training-room startup does not silently create the old default drone worker group"
	)

func _test_default_target_visual_only_tracks_evaluators() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	_expect(not room.target_marker.visible, "room-default marker starts hidden without an evaluator")
	_expect(not room.target_radius_ring.visible, "room-default radius starts hidden without an evaluator")

	room.trials.append({"mode": "algorithm_training", "group_id": 1})
	room._refresh_default_target_visual_visibility()
	_expect(not room.target_marker.visible, "ordinary training workers do not reveal the room-default target")

	var evaluator_trial: Dictionary = {"mode": "evaluation", "group_id": -1}
	room.trials.append(evaluator_trial)
	room._refresh_default_target_visual_visibility()
	_expect(room.target_marker.visible, "an evaluator reveals the room-default target it actually consumes")
	_expect(room.target_radius_ring.visible, "an evaluator reveals the matching room-default radius")

	room.trials.erase(evaluator_trial)
	room._refresh_default_target_visual_visibility()
	_expect(not room.target_marker.visible, "removing the last evaluator hides the room-default target again")
	room.free()


func _test_runtime_group_dispatch_repairs_missing_handler() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var group: Dictionary = {
		"group_id": 17,
		"color": Color("65d8ff"),
		"parent_group_id": -1,
	}
	room.worker_groups.append(group)
	_expect(not room.target_handlers_by_group_id.has(17), "test begins with a deliberately missing group handler")

	var targets: Dictionary = room._resolved_targets_by_group()
	var handler: TrainingTargetHandler = room._target_handler_for_group_id(17)
	_expect(handler != null, "dispatch repairs a missing runtime group handler")
	_expect(handler != room.default_target_handler, "repaired worker groups never alias the room-default handler")
	_expect(targets.has(17), "repaired group receives an explicit routed target entry")
	_expect(
		room._target_group_id_for_trial({"mode": "algorithm_training", "group_id": 17}) == 17,
		"training trials keep their explicit target-owner group id"
	)
	_expect(
		room._target_group_id_for_trial({"mode": "evaluation", "group_id": 17}) == -1,
		"evaluation trials stay on the room-default evaluator target"
	)
	room.free()


func _test_limb_target_marker_is_support_surface() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var group: Dictionary = {
		"group_id": 23,
		"color": Color("ffb45e"),
		"parent_group_id": -1,
	}
	room.limb_training.groups.append(group)
	room.limb_training.groups_by_id[23] = group
	var handler: TrainingTargetHandler = room._ensure_group_target_handler(23, group["color"])
	var path_system: TrainingPathTargetSystem = handler.path_system()
	_expect(
		path_system != null
		and is_zero_approx(path_system.base_height_m)
		and path_system.random_height_range_m.is_equal_approx(Vector2.ZERO),
		"fresh four-limb targets start on the ground and represent the actual support/destination surface instead of inheriting drone height assumptions"
	)
	room.limb_training.groups.erase(group)
	room.limb_training.groups_by_id.erase(23)
	room.free()


func _test_turret_group_publishes_live_runtime_members() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var drone_group: Dictionary = {
		"group_id": 31,
		"name": "Runtime targets",
		"color": Color.WHITE,
		"parent_group_id": -1,
	}
	room.worker_groups.append(drone_group)
	room.worker_groups_by_id[31] = drone_group
	var turret_group: Dictionary = {
		"group_id": 32,
		"name": "Targeting turret",
		"color": Color("ff9f5a"),
		"parent_group_id": -1,
		"target_worker_group_id": 31,
		"workers": [],
	}
	room.turret_training.groups.append(turret_group)
	room.turret_training.groups_by_id[32] = turret_group
	var first_body: Node3D = Node3D.new()
	var second_body: Node3D = Node3D.new()
	room.add_child(first_body)
	room.add_child(second_body)
	first_body.global_position = Vector3(1.0, 2.0, 3.0)
	second_body.global_position = Vector3(4.0, 2.0, 5.0)
	var first_adapter: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		first_body, &"drone", 3101, 31, 0, 1
	)
	var second_adapter: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		second_body, &"drone", 3102, 31, 1, 1
	)
	room.training_entity_spatial_hash.register_entity(
		first_adapter.spatial_key(), first_body, first_adapter.entity_kind,
		first_adapter.entity_id, first_adapter.metadata()
	)
	room.training_entity_spatial_hash.register_entity(
		second_adapter.spatial_key(), second_body, second_adapter.entity_kind,
		second_adapter.entity_id, second_adapter.metadata()
	)
	var handler: TrainingTargetHandler = room._ensure_group_target_handler(32, turret_group["color"])
	room._sync_turret_group_target_registration(32, handler)
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	handler.resolve(room._target_context_for_group(32))
	var selected: Dictionary = handler.selected_candidate
	_expect(
		registered != null and registered.target_count() == 2,
		"a selected turret target group publishes each live worker as an individual runtime candidate"
	)
	_expect(
		str(selected.get("target_kind", "")) == "combat_objective"
		and int((selected.get("metadata", {}) as Dictionary).get("target_worker_group_id", -1)) == 31
		and [3101, 3102].has(int((selected.get("metadata", {}) as Dictionary).get("target_entity_id", 0))),
		"the registered target handler resolves directly to a real member of the selected group instead of a moving centroid surrogate"
	)
	var locked_entity_id: int = int((selected.get("metadata", {}) as Dictionary).get("target_entity_id", 0))
	room._push_turret_resolved_target_identity(32, handler)
	_expect(
		int(turret_group.get("resolved_target_entity_id", -1)) == locked_entity_id,
		"the target handler pushes its exact selected worker into the turret policy immediately instead of waiting for a later coordinator tick"
	)
	second_body.global_position = Vector3(0.1, 2.0, 0.1)
	room.training_entity_spatial_hash.update_entity(second_adapter.spatial_key())
	room._sync_turret_group_target_registration(32, handler)
	handler.resolve(room._target_context_for_group(32))
	_expect(
		int((handler.selected_candidate.get("metadata", {}) as Dictionary).get("target_entity_id", 0)) == locked_entity_id,
		"an explicit turret target stays locked to the same live worker instead of thrashing when a sibling becomes slightly more attractive"
	)
	second_adapter.body = null
	room._sync_turret_group_target_registration(32, handler)
	_expect(
		registered.target_count() == 1,
		"dead or removed target members disappear from the runtime candidate provider immediately"
	)
	room.free()


func _test_fresh_drone_model_architecture_reaches_constructor() -> void:
	var ppo: DroneTrainingAlgorithm = DroneTrainingRoom._create_group_training_algorithm(
		"ppo_clip",
		{"config": {"hidden_layer_width": 96, "hidden_layer_depth": 3}},
		70001
	)
	var ppo_architecture: Dictionary = ppo.network_architecture() if ppo != null else {}
	_expect(
		ppo != null
		and int(ppo_architecture.get("hidden_layer_width", -1)) == 96
		and int(ppo_architecture.get("hidden_layer_depth", -1)) == 3,
		"fresh drone PPO group creation applies requested hidden width/depth before the immutable network is constructed"
	)
	var sac: DroneTrainingAlgorithm = DroneTrainingRoom._create_group_training_algorithm(
		"sac_her_maze",
		{"config": {"hidden_layer_width": 192, "hidden_layer_depth": 4}},
		70002
	)
	var sac_architecture: Dictionary = sac.network_architecture() if sac != null else {}
	_expect(
		sac != null
		and int(sac_architecture.get("hidden_layer_width", -1)) == 192
		and int(sac_architecture.get("hidden_layer_depth", -1)) == 4,
		"fresh drone SAC-HER group creation applies requested hidden width/depth before the immutable network is constructed"
	)
	var malformed: DroneTrainingAlgorithm = DroneTrainingRoom._create_group_training_algorithm(
		"ppo_clip",
		{"config": "broken"},
		70003
	)
	var malformed_architecture: Dictionary = malformed.network_architecture() if malformed != null else {}
	_expect(
		malformed != null
		and int(malformed_architecture.get("hidden_layer_width", -1)) == DronePPOActorCritic.HIDDEN_SIZE
		and int(malformed_architecture.get("hidden_layer_depth", -1)) == DronePPOActorCritic.HIDDEN_LAYER_COUNT,
		"malformed startup config falls back to the default architecture instead of throwing during group creation"
	)


func _test_drone_target_height_is_literal() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var group: Dictionary = {
		"group_id": 19,
		"color": Color("65d8ff"),
		"parent_group_id": -1,
	}
	room.worker_groups.append(group)
	var handler: TrainingTargetHandler = room._ensure_group_target_handler(19, group["color"])
	var path_system: TrainingPathTargetSystem = handler.path_system()
	_expect(
		path_system != null and is_equal_approx(path_system.base_height_m, DroneTrainingRoom.TARGET_START.y),
		"fresh drone targets start at the authored five-metre navigation height"
	)
	path_system.set_base_height(15.0)
	handler.resolve(room._target_context_for_group(19))
	var resolved: Dictionary = room._resolved_target_for_group_id(19)
	var resolved_position: Vector3 = resolved.get("position_world", Vector3.ZERO)
	_expect(
		is_equal_approx(resolved_position.y, 15.0),
		"a drone target height of 15 m routes exactly Y=15 m with no hidden hover offset"
	)
	room.free()


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)
