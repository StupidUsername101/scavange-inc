extends SceneTree

const FIXED_DELTA := 1.0 / 120.0

#######################################################
# Runs headless regression coverage for drone system behavior and reports contract or
# integration failures.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_stationary_arrival_and_hold()
	_test_moving_target_feed_forward()
	_test_follow_recovery_latches_world_side()
	_test_follow_ignores_view_direction()
	_test_context_avoidance_selects_a_clear_side()
	_test_context_avoidance_keeps_side_continuity()
	_test_orca_solution_is_finite_and_bounded()
	_test_all_chip_contracts_and_movement_envelopes()
	_test_perfect_drone_loadout_and_power_margin()
	_test_ml_episode_unlimited_battery()
	_test_ml_training_pause_preserves_runtime_state()
	_test_training_room_group_pause_retains_population_contract()
	_test_training_room_pause_completion_contract()
	_test_training_room_pause_configuration_boundaries_contract()
	_test_deterministic_training_power_fast_path()

	if failure_count == 0:
		print("Drone system tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Drone system tests failed: %d/%d assertions" % [
				failure_count,
				assertion_count,
			]
		)
		quit(1)


func _test_stationary_arrival_and_hold() -> void:
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var target := Vector3(12.0, 0.0, 0.0)
	var maximum_overshoot := 0.0
	for _step: int in range(1800):
		var command := DroneMovementPlanner.calculate_horizontal_velocity(
			position,
			target,
			Vector3.ZERO,
			0.5,
			9.0,
			6.0,
			1.1
		)
		var acceleration := ((command - velocity) * 2.8).limit_length(6.0)
		velocity += acceleration * FIXED_DELTA
		position += velocity * FIXED_DELTA
		maximum_overshoot = maxf(maximum_overshoot, position.x - target.x)

	_expect(position.distance_to(target) < 0.09, "stationary target is held precisely")
	_expect(velocity.length() < 0.03, "position hold removes residual velocity")
	_expect(maximum_overshoot < 0.45, "arrival does not make a broad overshoot")


func _test_moving_target_feed_forward() -> void:
	var command := DroneMovementPlanner.calculate_horizontal_velocity(
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.3, 0.0, 0.0),
		Vector3(3.0, 0.0, 0.0),
		0.5,
		8.0,
		5.0,
		1.0
	)
	_expect(
		command.distance_to(Vector3(3.0, 0.0, 0.0)) < 0.001,
		"moving target velocity is preserved inside its arrival envelope"
	)


func _test_follow_recovery_latches_world_side() -> void:
	var chip := load(
		"res://resources/drones/ai_chips/shepherd_follow_chip.tres"
	) as DroneAIChipDefinition
	var behavior := chip.create_behavior()
	var memory: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 8128
	var context := _follow_context(
		Vector3(13.0, 2.8, 1.0),
		Vector3.ZERO,
		Vector3.ZERO,
		0.0
	)
	var first: Dictionary = behavior.call(
		"evaluate",
		chip,
		context,
		memory,
		rng
	)
	var first_offset: Vector3 = first["movement_target"] - context[
		"follow_target_position"
	]
	first_offset.y = 0.0

	context = _follow_context(
		Vector3(8.0, 2.8, 7.0),
		Vector3(2.0, 0.0, -1.0),
		Vector3.ZERO,
		0.2
	)
	var second: Dictionary = behavior.call(
		"evaluate",
		chip,
		context,
		memory,
		rng
	)
	var second_offset: Vector3 = second["movement_target"] - context[
		"follow_target_position"
	]
	second_offset.y = 0.0
	_expect(
		first_offset.normalized().dot(second_offset.normalized()) > 0.999,
		"recovery destination stays on one world-space side"
	)


func _test_follow_ignores_view_direction() -> void:
	var chip := load(
		"res://resources/drones/ai_chips/surveyor_orbit_follow_chip.tres"
	) as DroneAIChipDefinition
	var behavior_a := chip.create_behavior()
	var behavior_b := chip.create_behavior()
	var memory_a: Dictionary = {}
	var memory_b: Dictionary = {}
	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 144
	rng_b.seed = 144
	var context_a := _follow_context(
		Vector3(5.2, 3.0, 0.0),
		Vector3.ZERO,
		Vector3.ZERO,
		4.0
	)
	var context_b := context_a.duplicate(true)
	context_a["basis"] = Basis.IDENTITY
	context_b["basis"] = Basis(Vector3.UP, 2.4)
	context_b["player_forward"] = Vector3(0.6, 0.0, -0.8)
	var result_a: Dictionary = behavior_a.call(
		"evaluate", chip, context_a, memory_a, rng_a
	)
	var result_b: Dictionary = behavior_b.call(
		"evaluate", chip, context_b, memory_b, rng_b
	)
	_expect(
		(result_a["movement_target"] as Vector3).distance_to(
			result_b["movement_target"] as Vector3
		) < 0.0001,
		"player view direction cannot alter a follow path"
	)


func _test_context_avoidance_selects_a_clear_side() -> void:
	var directions := _context_directions(Vector3.FORWARD)
	var clearances: Array[float] = []
	for index: int in range(directions.size()):
		clearances.append(1.0 if index == 0 else 8.0)
	var result := DroneObstacleAvoidance.select_context_velocity(
		Vector3.FORWARD * 5.0,
		directions,
		clearances,
		8.0,
		3.0
	)
	var velocity: Vector3 = result["velocity"]
	_expect(absf(velocity.x) > 0.5, "blocked route selects a lateral bypass")
	_expect(velocity.z < 0.0, "bypass retains forward progress")


func _test_context_avoidance_keeps_side_continuity() -> void:
	var directions := _context_directions(Vector3.FORWARD)
	var clearances: Array[float] = []
	for index: int in range(directions.size()):
		clearances.append(1.0 if index == 0 else 8.0)
	var continuity := Vector3(-1.0, 0.0, -1.0).normalized()
	var result := DroneObstacleAvoidance.select_context_velocity(
		Vector3.FORWARD * 5.0,
		directions,
		clearances,
		8.0,
		3.0,
		continuity
	)
	var velocity: Vector3 = result["velocity"]
	_expect(
		velocity.normalized().dot(continuity) > 0.6,
		"avoidance keeps its chosen side instead of left-right twitching"
	)


func _test_orca_solution_is_finite_and_bounded() -> void:
	var neighbors: Array[Dictionary] = [{
		"entity_id": 2,
		"position": Vector2(4.0, 0.0),
		"velocity": Vector2(-3.0, 0.0),
		"radius": 0.9,
		"responsibility": 0.5,
	}]
	var result := OrcaVelocitySolver.solve(
		Vector2.ZERO,
		Vector2(3.0, 0.0),
		Vector2(3.0, 0.0),
		6.0,
		0.9,
		2.0,
		FIXED_DELTA,
		1,
		neighbors
	)
	var velocity: Vector2 = result["velocity"]
	_expect(is_finite(velocity.x) and is_finite(velocity.y), "ORCA stays finite")
	_expect(velocity.length() <= 6.0001, "ORCA respects navigation speed")
	_expect(
		velocity.distance_to(Vector2(3.0, 0.0)) > 0.01,
		"head-on ORCA case produces an avoidance correction"
	)


func _test_all_chip_contracts_and_movement_envelopes() -> void:
	var directory := DirAccess.open("res://resources/drones/ai_chips")
	_expect(directory != null, "AI chip catalog opens")
	if directory == null:
		return
	var chip_count := 0
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var chip := load(
			"res://resources/drones/ai_chips".path_join(file_name)
		) as DroneAIChipDefinition
		chip_count += 1
		_expect(chip != null and chip.has_behavior_contract(), "%s has behavior" % file_name)
		if chip == null:
			continue
		_expect(
			chip.get_navigation_speed_scale() > 0.0
			and chip.get_navigation_speed_scale() <= 1.0,
			"%s has bounded movement speed" % file_name
		)
		_expect(
			chip.get_navigation_acceleration_scale() > 0.0
			and chip.get_navigation_acceleration_scale() <= 1.0,
			"%s has bounded movement acceleration" % file_name
		)
		if chip.behavior_id == &"follow_player":
			_expect(
				chip.get_follow_outer_radius() - chip.get_follow_inner_radius() >= 1.5,
				"%s has a usable follow annulus" % file_name
			)
			_expect(
				chip.get_follow_height_offset() >= 2.5,
				"%s keeps safe natural altitude" % file_name
			)
	_expect(chip_count >= 10, "all current AI chips were audited")


func _test_perfect_drone_loadout_and_power_margin() -> void:
	var loadout := load(
		"res://resources/drones/loadouts/perfect_combat_follow_quad.tres"
	) as DroneLoadout
	_expect(loadout != null, "perfect reference loadout exists")
	if loadout == null:
		return
	_expect(loadout.core != null and loadout.battery != null, "reference powertrain is complete")
	for slot_index: int in range(4):
		_expect(loadout.get_propeller(slot_index) != null, "reference rotor %d exists" % slot_index)
	var behavior_ids: Array[StringName] = []
	for slot_index: int in range(loadout.core.ai_chip_slot_count):
		var chip := loadout.get_ai_chip(slot_index)
		if chip != null:
			behavior_ids.append(chip.behavior_id)
	_expect(&"follow_player" in behavior_ids, "reference drone follows a player")
	_expect(&"orca_collision_avoidance" in behavior_ids, "reference drone coordinates with peers")
	_expect(&"combat_targeting" in behavior_ids, "reference drone targets enemies")
	_expect(
		not loadout.find_attachment_slots_with_capability(&"weapon").is_empty(),
		"reference drone carries a weapon"
	)

	var gravity := 9.8
	var hover_thrust_per_rotor := loadout.get_total_mass() * gravity / 4.0
	var hover_power := 0.0
	for slot_index: int in range(4):
		var propeller := loadout.get_propeller(slot_index)
		var denominator: float = (
			propeller.aerodynamic_efficiency
			* sqrt(2.0 * 1.225 * propeller.get_disk_area())
		)
		hover_power += pow(hover_thrust_per_rotor, 1.5) / denominator
	var active_system_power := 0.0
	for slot_index: int in range(loadout.core.ai_chip_slot_count):
		var chip := loadout.get_ai_chip(slot_index)
		if chip != null:
			active_system_power += chip.active_power_draw
	for slot_index: int in range(loadout.core.attachment_slot_count):
		var attachment := loadout.get_attachment(slot_index)
		if attachment != null:
			active_system_power += (
				attachment.idle_power_draw + attachment.active_power_draw
			)
	var simultaneous_demand := hover_power + active_system_power
	_expect(
		loadout.battery.nominal_power_output >= simultaneous_demand * 1.5,
		"reference battery has 50% margin while hovering and firing"
	)
	_expect(
		loadout.core.max_power_throughput >= simultaneous_demand * 1.5,
		"reference core has 50% margin while hovering and firing"
	)


func _follow_context(
	drone_position: Vector3,
	drone_velocity: Vector3,
	player_velocity: Vector3,
	time: float
) -> Dictionary:
	return {
		"position": drone_position,
		"velocity": drone_velocity,
		"simulation_time": time,
		"follow_target_valid": true,
		"follow_target_position": Vector3.ZERO,
		"follow_target_velocity": player_velocity,
	}


func _context_directions(forward: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for angle: float in [0.0, -45.0, 45.0, -90.0, 90.0, 180.0]:
		result.append(forward.rotated(Vector3.UP, deg_to_rad(angle)).normalized())
	return result


func _test_ml_episode_unlimited_battery() -> void:
	var drone := ServerDrone.new()
	drone.loadout = load(
		"res://resources/ml_body_presets/drone_quad.tres"
	) as DroneLoadout
	var capacity = drone.loadout.battery.energy_capacity_wh
	drone.remaining_battery_energy_wh = capacity * 0.25
	drone.set_ml_episode_unlimited_battery(true)
	drone.call("_drain_battery", 120.0, 60.0)
	_expect(
		is_equal_approx(drone.remaining_battery_energy_wh, capacity),
		"unlimited ML episode battery remains full under sustained power draw"
	)
	drone.set_ml_episode_unlimited_battery(false)
	drone.call("_drain_battery", 120.0, 1.0)
	_expect(
		drone.remaining_battery_energy_wh < capacity,
		"finite battery mode still drains the normal gameplay battery"
	)
	drone.free()


func _test_ml_training_pause_preserves_runtime_state() -> void:
	var drone = ServerDrone.new()
	drone.activated = true
	drone.freeze = false
	drone.linear_velocity = Vector3(1.5, -0.25, 2.0)
	drone.angular_velocity = Vector3(0.1, 0.2, -0.3)
	var linear_before: Vector3 = drone.linear_velocity
	var angular_before: Vector3 = drone.angular_velocity
	drone.set_ml_training_paused(true)
	_expect(
		drone.ml_training_paused
		and drone.freeze
		and drone.activated
		and drone.linear_velocity.is_equal_approx(linear_before)
		and drone.angular_velocity.is_equal_approx(angular_before),
		"pausing an ML drone freezes the live body without deactivating or resetting its motion state"
	)
	drone.server_physics_tick(3.0)
	_expect(
		drone.linear_velocity.is_equal_approx(linear_before)
		and drone.angular_velocity.is_equal_approx(angular_before),
		"a paused ML drone does not advance its server-side power/controller simulation"
	)
	drone.set_ml_training_paused(false)
	_expect(
		not drone.ml_training_paused
		and not drone.freeze
		and drone.activated
		and drone.linear_velocity.is_equal_approx(linear_before)
		and drone.angular_velocity.is_equal_approx(angular_before),
		"resuming an ML drone restores the same live physics state instead of creating a new episode body"
	)
	var drone_source: String = FileAccess.get_file_as_string("res://scripts/server/server_drone.gd")
	var limb_assembly_source: String = FileAccess.get_file_as_string(
		"res://scripts/limbs/generic_limb_assembly_3d.gd"
	)
	_expect(
		drone_source.contains("assembly.set_runtime_active(false, false)")
		and limb_assembly_source.contains("release_grip_on_deactivate: bool = true"),
		"pausing a drone also freezes attached generic limbs without dropping an established grip"
	)
	drone.free()


func _test_training_room_group_pause_retains_population_contract() -> void:
	var room_source: String = FileAccess.get_file_as_string(
		"res://ml/training/drone_training_room.gd"
	)
	_expect(
		room_source.contains(
			'else:\n\t\tgroup["active"] = false\n\t\t_set_drone_group_trials_paused(group, true)'
		)
		and room_source.contains("func _drone_group_population_matches(group: Dictionary) -> bool:")
		and room_source.contains("if training_group.is_empty() or not bool(training_group.get(\"active\", false)):\n\t\t\t\tcontinue"),
		"drone group pause retains the live population and stops trial advancement instead of despawning workers"
	)


func _test_training_room_pause_completion_contract() -> void:
	var room = DroneTrainingRoom.new()
	var paused_group: Dictionary = {"group_id": 41, "active": false, "trials": []}
	var active_group: Dictionary = {"group_id": 42, "active": true, "trials": []}
	var test_groups: Array[Dictionary] = [paused_group, active_group]
	room.worker_groups = test_groups
	room.worker_groups_by_id = {41: paused_group, 42: active_group}
	var paused_trial: Dictionary = {
		"mode": "algorithm_training",
		"group_id": 41,
		"episode_finished": false,
	}
	var active_trial: Dictionary = {
		"mode": "algorithm_training",
		"group_id": 42,
		"episode_finished": false,
	}
	var evaluation_trial: Dictionary = {
		"mode": "evaluation",
		"group_id": -1,
		"episode_finished": false,
	}
	var test_trials: Array[Dictionary] = [paused_trial, active_trial, evaluation_trial]
	room.trials = test_trials
	room.evaluation_drones_keep_episode_running = false
	var training_blockers: Array[Dictionary] = room._episode_completion_trials()
	_expect(
		training_blockers.size() == 1 and training_blockers[0] == active_trial,
		"paused drone groups do not block another active group's shared episode completion"
	)
	room.evaluation_drones_keep_episode_running = true
	var evaluation_blockers: Array[Dictionary] = room._episode_completion_trials()
	_expect(
		evaluation_blockers.size() == 2
		and evaluation_blockers.has(active_trial)
		and evaluation_blockers.has(evaluation_trial)
		and not evaluation_blockers.has(paused_trial),
		"evaluation drones still participate in completion when configured to keep the episode alive while paused training groups remain excluded"
	)
	active_group["active"] = false
	var evaluator_only_blockers: Array[Dictionary] = room._episode_completion_trials()
	_expect(
		evaluator_only_blockers.size() == 1 and evaluator_only_blockers[0] == evaluation_trial,
		"an evaluator-only room can still complete while every training group is paused"
	)
	room.free()


func _test_training_room_pause_configuration_boundaries_contract() -> void:
	var room_source: String = FileAccess.get_file_as_string(
		"res://ml/training/drone_training_room.gd"
	)
	var limb_source: String = FileAccess.get_file_as_string(
		"res://ml/training/four_limb/four_limb_training_coordinator.gd"
	)
	var turret_source: String = FileAccess.get_file_as_string(
		"res://ml/training/turret/turret_training_coordinator.gd"
	)
	_expect(
		room_source.contains("func _clear_drone_group_runtime_for_configuration_change(group: Dictionary) -> void:")
		and room_source.contains("_clear_drone_group_runtime_for_configuration_change(group)\n\tgroup[\"hardware_revision\"]")
		and room_source.contains("Paused drone episode cleared so one rollout cannot mix target configurations")
		and room_source.contains("Drone episode spawn position changed.\", true, true, false")
		and room_source.contains("Custom obstacle added; episode restarted.\", true, true, true"),
		"ordinary drone pause is state-preserving, while hardware, target, spawn, and shared-environment edits explicitly create configuration boundaries"
	)
	_expect(
		limb_source.contains("(group[\"trainer\"] as FourLimbPPOTrainer).discard_incomplete_rollout()\n\t\t_clear_group_workers(group)")
		and limb_source.contains("changing its temporal contract is a real")
		and turret_source.contains("(group[\"trainer\"] as TurretPPOTrainer).discard_incomplete_rollout()\n\t\t_clear_group_workers(group)"),
		"paused limb/turret population and control-rate edits retire the old on-policy fragment before rebuilding or resuming"
	)


func _test_deterministic_training_power_fast_path() -> void:
	var drone := ServerDrone.new()
	var source := load(
		"res://resources/ml_body_presets/drone_quad.tres"
	) as DroneLoadout
	drone.loadout = MLBodyPartContract.deep_duplicate_resource(source) as DroneLoadout
	drone.remaining_battery_energy_wh = drone.loadout.battery.energy_capacity_wh
	drone.call("_refresh_propeller_runtime_cache")
	var battery_phase_before := drone.battery_fluctuation_phase
	var core_phase_before := drone.core_fluctuation_phase
	var forwarded_power := float(drone.call(
		"_calculate_forwarded_battery_power",
		1.0 / 60.0
	))
	_expect(
		drone.deterministic_power_output_cache,
		"the calibrated training powertrain selects the deterministic runtime path"
	)
	_expect(
		is_equal_approx(
			forwarded_power,
			minf(
				drone.loadout.battery.nominal_power_output,
				drone.loadout.core.max_power_throughput
			)
		),
		"the deterministic path preserves the exact forwarded power"
	)
	_expect(
		is_equal_approx(
			drone.current_bus_voltage_v,
			drone.loadout.battery.nominal_voltage_v
		),
		"the deterministic path preserves nominal bus voltage"
	)
	_expect(
		is_equal_approx(drone.battery_fluctuation_phase, battery_phase_before)
		and is_equal_approx(drone.core_fluctuation_phase, core_phase_before),
		"unused fluctuation oscillators are not evaluated for regulated training parts"
	)
	drone.free()


func _expect(condition: bool, description: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: %s" % description)
