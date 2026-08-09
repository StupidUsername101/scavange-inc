extends SceneTree

const ARENA_COLLISION_LAYER = 1
const DRONE_COLLISION_LAYER = 1 << 1

#######################################################
# Verifies the real physics-query path used by the training room: a wall on the arena layer
# must produce horizontal clearance, target-path occlusion, and rigid-body contact state.
#######################################################

var test_root: Node3D
var drone: ServerDrone
var wall: StaticBody3D
var far_wall: StaticBody3D
var wall_spatial_hash = DroneTrainingWallSpatialHash.new()
var frame_count = 0
var failure_count = 0
var saw_wall_contact = false
var saw_horizontal_wall_contact_direction = false


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	test_root = Node3D.new()
	test_root.name = "DroneTrainingObstacleSensorTestWorld"
	root.add_child(test_root)

	var air = AirEnvironment.new()
	air.name = "AirEnvironment"
	test_root.add_child(air)
	_add_floor()
	_add_wall()
	_add_far_wall()
	var indexed_walls: Array[Node3D] = [wall, far_wall]
	wall_spatial_hash.rebuild(indexed_walls)
	_add_drone()
	physics_frame.connect(_on_physics_frame)


func _add_floor() -> void:
	var floor = StaticBody3D.new()
	floor.name = "TrainingFloor"
	floor.collision_layer = ARENA_COLLISION_LAYER
	floor.collision_mask = DRONE_COLLISION_LAYER
	floor.set_meta("training_ground", true)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(20.0, 0.5, 20.0)
	collision.shape = shape
	floor.position = Vector3(0.0, -0.25, 0.0)
	floor.add_child(collision)
	test_root.add_child(floor)


func _add_wall() -> void:
	wall = StaticBody3D.new()
	wall.name = "TrainingWall"
	wall.collision_layer = ARENA_COLLISION_LAYER
	wall.collision_mask = DRONE_COLLISION_LAYER
	wall.set_meta("training_wall", true)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.35, 3.0, 4.0)
	collision.shape = shape
	wall.position = Vector3(2.0, 1.5, 0.0)
	wall.add_child(collision)
	test_root.add_child(wall)


func _add_far_wall() -> void:
	far_wall = StaticBody3D.new()
	far_wall.name = "FarTrainingWall"
	far_wall.collision_layer = ARENA_COLLISION_LAYER
	far_wall.collision_mask = DRONE_COLLISION_LAYER
	far_wall.set_meta("training_wall", true)
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.35, 3.0, 4.0)
	collision.shape = shape
	far_wall.position = Vector3(50.0, 1.5, 0.0)
	far_wall.add_child(collision)
	test_root.add_child(far_wall)


func _add_drone() -> void:
	var scene = load("res://scenes/server/server_drone.tscn") as PackedScene
	drone = scene.instantiate() as ServerDrone
	drone.starts_activated = false
	drone.position = Vector3(0.0, 1.2, 0.0)
	drone.gravity_scale = 0.0
	drone.collision_layer = DRONE_COLLISION_LAYER
	drone.collision_mask = ARENA_COLLISION_LAYER
	drone.contact_monitor = true
	drone.max_contacts_reported = 12
	test_root.add_child(drone)
	drone.enable_ml_control()


func _on_physics_frame() -> void:
	frame_count += 1
	if frame_count == 3:
		drone.rotation = Vector3(0.0, 0.0, deg_to_rad(35.0))
		var roll_independent_right = DroneTrainingObstacleSensor._yaw_aligned_world_direction(
			drone,
			Vector3.RIGHT
		)
		_expect(
			roll_independent_right.x > 0.99 and absf(roll_independent_right.y) < 0.001,
			"maze sectors remain heading-aligned while the drone rolls"
		)
		var rolled_probe = DroneTrainingObstacleSensor.sample(
			drone,
			test_root.get_world_3d().direct_space_state,
			Vector3(4.0, 1.2, 0.0),
			ARENA_COLLISION_LAYER,
			wall_spatial_hash
		)
		var rolled_yaw_direction: Vector3 = rolled_probe.get(
			"nearest_direction_yaw_local",
			Vector3.ZERO
		)
		_expect(
			rolled_yaw_direction.x > 0.8 and is_zero_approx(rolled_yaw_direction.y),
			"nearest-wall input remains horizontal instead of turning groundward when the drone rolls"
		)
		drone.rotation = Vector3.ZERO
		var nearby_records: Array[Dictionary] = wall_spatial_hash.query_nearby(
			Vector3.ZERO,
			5.0
		)
		_expect(
			nearby_records.size() == 1,
			"wall hash excludes distant maze walls before exact sensor tests"
		)
		var cache_hits_before = int(
			wall_spatial_hash.debug_state().get("query_cache_hits", 0)
		)
		wall_spatial_hash.query_nearby(Vector3.ZERO, 5.0)
		_expect(
			int(wall_spatial_hash.debug_state().get("query_cache_hits", 0))
			> cache_hits_before,
			"repeated wall-cell queries reuse the bounded broad-phase cache"
		)
		var batch_directions := PackedVector3Array([Vector3.RIGHT, Vector3.LEFT])
		var batch_ranges := PackedFloat64Array([4.0, 4.0])
		var batch_distances = wall_spatial_hash.raycast_distances_records(
			nearby_records,
			Vector3.ZERO,
			batch_directions,
			batch_ranges,
			Vector3.ZERO
		)
		var single_distance = wall_spatial_hash.raycast_distance_records(
			nearby_records,
			Vector3.ZERO,
			Vector3.RIGHT,
			4.0,
			Vector3.ZERO
		)
		_expect(
			batch_distances.size() == 2
			and is_equal_approx(batch_distances[0], single_distance)
			and batch_distances[1] < 0.0,
			"batched lidar preserves exact single-ray oriented-box distances"
		)
		var probe = DroneTrainingObstacleSensor.sample(
			drone,
			test_root.get_world_3d().direct_space_state,
			Vector3(4.0, 1.2, 0.0),
			ARENA_COLLISION_LAYER,
			wall_spatial_hash
		)
		var direction: Vector3 = probe.get(
			"nearest_direction_local",
			Vector3.ZERO
		)
		_expect(
			direction.x > 0.8 and absf(direction.y) < 0.1,
			"training wall is reported in the correct drone-local direction"
		)
		_expect(
			float(probe.get("nearest_distance_m", 4.0)) < 1.5,
			"horizontal wall clearance is not hidden by the closer floor"
		)
		_expect(
			bool(probe.get("target_path_blocked", false)),
			"a wall between drone and target marks the target path as blocked"
		)
		var sector_clearances: PackedFloat64Array = probe.get(
			"sector_clearances_m",
			PackedFloat64Array()
		)
		_expect(
			sector_clearances.size() == DroneTrainingObstacleSensor.SECTOR_COUNT
			and sector_clearances[2] < 1.5
			and sector_clearances[6] > 10.0,
			"right and left maze sectors remain independently visible"
		)
		_expect(
			float(probe.get("target_path_clearance_m", 99.0)) < 2.0
			and float(probe.get("target_wall_top_relative_height_m", 0.0)) > 1.7,
			"target ray reports both distance to the blocker and height needed to clear it"
		)
		var hash_state = wall_spatial_hash.debug_state()
		_expect(
			int(hash_state.get("query_count", 0)) > 0
			and int(hash_state.get("candidate_count", 0)) > 0
			and int(hash_state.get("exact_test_count", 0)) > 0,
			"wall sensing performs spatial-hash broad phase before exact box tests"
		)
		_expect(
			absf(float(probe.get("ground_clearance_m", 0.0)) - 1.2) < 0.02,
			"ground clearance remains available as its own independent feature"
		)
		var downward_target_probe = DroneTrainingObstacleSensor.sample(
			drone,
			test_root.get_world_3d().direct_space_state,
			Vector3(0.0, -2.0, 0.0),
			ARENA_COLLISION_LAYER,
			null
		)
		_expect(
			not bool(downward_target_probe.get("target_path_blocked", true)),
			"physics fallback never classifies the floor as a training wall"
		)
		# The live room intentionally has no physical +Z presentation wall, but leaving the
		# rectangular training arena is still terminal. The learned policy must therefore see
		# that logical edge through the same lidar channels as any real wall.
		drone.position = Vector3(0.0, 1.2, 8.0)
		var virtual_boundary_probe = DroneTrainingObstacleSensor.sample(
			drone,
			test_root.get_world_3d().direct_space_state,
			Vector3.ZERO,
			ARENA_COLLISION_LAYER,
			wall_spatial_hash,
			Vector3(20.0, 8.0, 20.0)
		)
		var boundary_sectors: PackedFloat64Array = virtual_boundary_probe.get(
			"sector_clearances_m",
			PackedFloat64Array()
		)
		_expect(
			float(virtual_boundary_probe.get("arena_boundary_clearance_m", INF)) < 2.0,
			"logical arena edge reports a finite body-envelope clearance"
		)
		_expect(
			boundary_sectors.size() == DroneTrainingObstacleSensor.SECTOR_COUNT
			and boundary_sectors[4] < 2.0,
			"the physically open +Z arena edge reaches the normal back-sector lidar channel"
		)
		var boundary_direction: Vector3 = virtual_boundary_probe.get(
			"nearest_direction_world",
			Vector3.ZERO
		)
		_expect(
			float(virtual_boundary_probe.get("nearest_distance_m", 4.0)) < 2.0
			and boundary_direction.z > 0.8,
			"the compact obstacle probe also sees the open terminal boundary"
		)
		drone.position = Vector3.ZERO + Vector3.UP * 1.2
		drone.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
		drone.linear_velocity = Vector3.RIGHT
		var refreshed_probe = DroneTrainingObstacleSensor.refresh_motion(
			drone,
			probe.duplicate(true)
		)
		_expect(
			float(refreshed_probe.get("closing_speed_mps", 0.0)) > 0.9,
			"cached wall closing speed remains tied to the sampled world wall instead of rotating with the drone"
		)
		var refreshed_yaw_direction: Vector3 = refreshed_probe.get(
			"nearest_direction_yaw_local",
			Vector3.ZERO
		)
		_expect(
			absf(refreshed_yaw_direction.x) < 0.2
			and absf(refreshed_yaw_direction.z) > 0.8
			and is_zero_approx(refreshed_yaw_direction.y),
			"cached wall direction is re-expressed in the drone's current heading frame between geometry samples"
		)
		drone.rotation = Vector3.ZERO
		drone.linear_velocity = Vector3.ZERO

		# Follow the exact training-room route from sensor probe, through the drone objective
		# snapshot, into the actor tensor. This guards against a sensor that works only in
		# diagnostics while the learned policy silently receives zeros.
		_expect(
			drone.set_ml_objective({
				"target_position_world": Vector3(4.0, 1.2, 0.0),
				"target_velocity_world": Vector3.ZERO,
				"target_hover_radius_m": 0.5,
				"episode_progress": 0.25,
				"obstacle_probe": probe,
			}),
			"the training objective accepts the live obstacle probe"
		)
		var actor_input = DronePPOObservationEncoder.encode_actor(
			drone.get_ppo_snapshot()
		)
		var direction_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
			"nearest_obstacle_direction_local_x"
		)
		var clearance_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
			"nearest_obstacle_clearance"
		)
		var blocked_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
			"target_path_blocked"
		)
		_expect(
			direction_index >= 0 and actor_input[direction_index] > 0.8,
			"the sampled wall direction reaches the model actor tensor"
		)
		_expect(
			clearance_index >= 0 and actor_input[clearance_index] < -0.2,
			"the sampled wall clearance reaches the model actor tensor"
		)
		_expect(
			blocked_index >= 0 and actor_input[blocked_index] > 0.9,
			"target-line wall occlusion reaches the model actor tensor"
		)
		var right_sector_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
			"wall_clearance_right"
		)
		var wall_height_index = DronePPOObservationEncoder.ACTOR_FEATURE_NAMES.find(
			"target_wall_top_relative_height"
		)
		_expect(
			right_sector_index >= 0 and actor_input[right_sector_index] < -0.5
			and wall_height_index >= 0 and actor_input[wall_height_index] > 0.2,
			"maze sector and wall-top geometry reach the actual PPO actor tensor"
		)

		# Put the physical envelope into the wall and let the physics server report contact.
		drone.position = Vector3(1.1, 1.2, 0.0)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		drone.sleeping = false
		drone.reset_physics_interpolation()
	elif frame_count >= 4 and frame_count <= 9:
		var contact_probe = DroneTrainingObstacleSensor.sample(
			drone,
			test_root.get_world_3d().direct_space_state,
			Vector3(4.0, 1.2, 0.0),
			ARENA_COLLISION_LAYER,
			wall_spatial_hash
		)
		var contact_reported = bool(contact_probe.get("wall_contact", false))
		saw_wall_contact = saw_wall_contact or contact_reported
		if contact_reported:
			var contact_direction: Vector3 = contact_probe.get(
				"nearest_direction_yaw_local",
				Vector3.ZERO
			)
			saw_horizontal_wall_contact_direction = (
				saw_horizontal_wall_contact_direction
				or is_zero_approx(contact_direction.y)
			)
		if frame_count == 9:
			_expect(
				saw_wall_contact,
				"actual rigid-body contact with a tagged training wall reaches the sensor"
			)
			_expect(
				saw_horizontal_wall_contact_direction,
				"physical wall contact never becomes a vertical direction to flee from"
			)
			_finish()


func _finish() -> void:
	if physics_frame.is_connected(_on_physics_frame):
		physics_frame.disconnect(_on_physics_frame)
	if failure_count == 0:
		print("Drone training obstacle sensor runtime test passed")
		quit(0)
	else:
		push_error(
			"Drone training obstacle sensor runtime test failed: %d assertions"
			% failure_count
		)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("FAIL: %s" % description)
