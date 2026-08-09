extends SceneTree

const PART_GEOMETRY = preload("res://scripts/drones/drone_part_geometry.gd")

#######################################################
# Regression coverage for training obstacle shape contracts and the reusable massless drone
# camera attachment. Run headlessly from the project root when a Godot executable is available.
#######################################################

var failure_count := 0
var assertion_count := 0
var test_root: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = Node3D.new()
	root.add_child(test_root)
	_test_shape_contracts()
	_test_spatial_hash_for_every_shape()
	_test_compound_obstacle_hashing()
	_test_unrestricted_obstacle_hashing()
	_test_camera_part_contract()
	_test_camera_finished_drone_fade()
	_test_worker_group_rename_selection_dispatch()
	_test_random_waypoint_limits()
	_test_random_waypoint_start_and_area_preview()
	_test_saved_map_layout_rebuild()
	_test_training_item_definition_resources()
	_test_training_item_contract()
	_test_delivery_destination_contract()
	_test_training_item_dimension_editor_matches_physics()
	_test_training_item_editor_uses_authored_spawn()
	_test_training_item_map_restore_contract()
	_test_target_marker_ring_alignment()
	print("Obstacle/camera assertions: %d, failures: %d" % [
		assertion_count,
		failure_count,
	])
	quit(0 if failure_count == 0 else 1)


func _test_shape_contracts() -> void:
	for kind in range(DroneTrainingObstacleShape.DISPLAY_NAMES.size()):
		var definitions := DroneTrainingObstacleShape.dimension_definitions(kind)
		var dimensions := DroneTrainingObstacleShape.normalized_dimensions(kind, {})
		var shape := DroneTrainingObstacleShape.collision_shape(kind, dimensions)
		var mesh := DroneTrainingObstacleShape.visual_mesh(kind, dimensions)
		_expect(not definitions.is_empty(), "%s exposes shape-specific dimensions" % DroneTrainingObstacleShape.display_name(kind))
		_expect(_shape_matches_kind(shape, kind), "%s creates the matching collision primitive" % DroneTrainingObstacleShape.display_name(kind))
		_expect(mesh != null, "%s creates a matching visible primitive" % DroneTrainingObstacleShape.display_name(kind))

	var unrestricted := DroneTrainingObstacleShape.normalized_dimensions(
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 250000.0, "height": 120000.0, "depth": 80000.0}
	)
	_expect(
		is_equal_approx(float(unrestricted["width"]), 250000.0)
		and is_equal_approx(float(unrestricted["height"]), 120000.0)
		and is_equal_approx(float(unrestricted["depth"]), 80000.0),
		"large obstacle dimensions are preserved instead of clamped to the arena"
	)
	var capsule := DroneTrainingObstacleShape.normalized_dimensions(
		DroneTrainingObstacleShape.Kind.CAPSULE,
		{"radius": 2.0, "height": 1.0}
	)
	_expect(
		float(capsule["height"]) >= 4.0,
		"capsule total height remains physically valid for its radius"
	)
	var clamped_capsule = DroneTrainingObstacleShape.normalized_dimensions(
		999,
		{"radius": 2.0, "height": 1.0}
	)
	_expect(
		float(clamped_capsule["height"]) >= 4.0,
		"out-of-range shape kinds use the same clamped capsule contract for dimensions and validity rules"
	)
	var malformed_dimensions = DroneTrainingObstacleShape.normalized_dimensions(
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": {"broken": true}, "height": NAN, "depth": 2.0}
	)
	_expect(
		is_finite(float(malformed_dimensions["width"]))
		and is_finite(float(malformed_dimensions["height"]))
		and is_equal_approx(float(malformed_dimensions["depth"]), 2.0),
		"malformed persisted obstacle dimensions fall back to finite shape defaults"
	)
	var rotated_sphere_aabb := DroneTrainingObstacleShape.world_aabb(
		DroneTrainingObstacleShape.Kind.SPHERE,
		{"radius": 2.0},
		Transform3D(Basis.from_euler(Vector3(0.4, 0.7, 1.1)), Vector3.ZERO)
	)
	_expect(
		rotated_sphere_aabb.size.is_equal_approx(Vector3.ONE * 4.0),
		"rotating a sphere does not inflate its sensor broad-phase bounds"
	)

	_expect(
		is_equal_approx(
			DroneTrainingObstacleShape.bounding_radius(
				DroneTrainingObstacleShape.Kind.SPHERE,
				{"radius": 2.0}
			),
			2.0
		),
		"sphere task/collision radius is its real radius instead of the AABB diagonal"
	)
	_expect(
		is_equal_approx(
			DroneTrainingObstacleShape.bounding_radius(
				DroneTrainingObstacleShape.Kind.CYLINDER,
				{"radius": 2.0, "height": 6.0}
			),
			sqrt(13.0)
		),
		"cylinder task/collision radius reaches its rim corners exactly"
	)
	_expect(
		is_equal_approx(
			DroneTrainingObstacleShape.bounding_radius(
				DroneTrainingObstacleShape.Kind.CAPSULE,
				{"radius": 1.0, "height": 5.0}
			),
			2.5
		),
		"capsule task/collision radius uses its pole-to-origin extent"
	)
	_expect(
		is_equal_approx(
			DroneTrainingObstacleShape.bounding_radius(
				DroneTrainingObstacleShape.Kind.BOX,
				{"width": 2.0, "height": 4.0, "depth": 6.0}
			),
			sqrt(14.0)
		),
		"box task/collision radius uses the true half-diagonal"
	)

	_expect(
		is_equal_approx(
			DroneTrainingObstacleShape.support_extent_world(
				DroneTrainingObstacleShape.Kind.CYLINDER,
				{"radius": 2.0, "height": 6.0},
				Basis.IDENTITY,
				Vector3.UP
			),
			3.0
		)
		and is_equal_approx(
			DroneTrainingObstacleShape.support_extent_world(
				DroneTrainingObstacleShape.Kind.CYLINDER,
				{"radius": 2.0, "height": 6.0},
				Basis.IDENTITY,
				Vector3.RIGHT
			),
			2.0
		),
		"directional support extent rests cylinders on a surface using height axially and radius radially"
	)
	_expect(
		is_equal_approx(
			DroneTrainingObstacleShape.support_extent_world(
				DroneTrainingObstacleShape.Kind.CAPSULE,
				{"radius": 1.0, "height": 5.0},
				Basis.IDENTITY,
				Vector3.UP
			),
			2.5
		)
		and is_equal_approx(
			DroneTrainingObstacleShape.support_extent_world(
				DroneTrainingObstacleShape.Kind.CAPSULE,
				{"radius": 1.0, "height": 5.0},
				Basis.IDENTITY,
				Vector3.RIGHT
			),
			1.0
		),
		"directional support extent handles capsule side and pole contacts without AABB over-offset"
	)


func _test_spatial_hash_for_every_shape() -> void:
	var shapes: Array[Dictionary] = [
		{"kind": DroneTrainingObstacleShape.Kind.BOX, "dimensions": {"width": 2.0, "height": 3.0, "depth": 2.0}},
		{"kind": DroneTrainingObstacleShape.Kind.CYLINDER, "dimensions": {"radius": 1.0, "height": 3.0}},
		{"kind": DroneTrainingObstacleShape.Kind.SPHERE, "dimensions": {"radius": 1.0}},
		{"kind": DroneTrainingObstacleShape.Kind.CAPSULE, "dimensions": {"radius": 1.0, "height": 3.0}},
	]
	for index in range(shapes.size()):
		var spec: Dictionary = shapes[index]
		var dimensions: Dictionary = spec.get("dimensions", {})
		var body := DroneTrainingRoomPresentation.add_static_obstacle(
			test_root,
			"ShapeTest%d" % index,
			Vector3(5.0, 1.5, float(index) * 20.0),
			int(spec["kind"]),
			dimensions,
			Color.WHITE
		)
		body.set_meta("training_wall", true)
		var spatial_hash := DroneTrainingWallSpatialHash.new()
		var walls: Array[Node3D] = [body]
		spatial_hash.rebuild(walls)
		var origin := Vector3(0.0, 1.5, float(index) * 20.0)
		var records := spatial_hash.query_segment(origin, origin + Vector3.RIGHT * 10.0)
		var distance := spatial_hash.raycast_distance_records(
			records,
			origin,
			Vector3.RIGHT,
			10.0
		)
		_expect(
			distance > 3.9 and distance < 4.1,
			"%s has an exact selectable/sensor ray intersection" % DroneTrainingObstacleShape.display_name(int(spec["kind"]))
		)


func _test_compound_obstacle_hashing() -> void:
	var body = StaticBody3D.new()
	body.name = "CompoundObstacle"
	test_root.add_child(body)
	for local_x in [2.0, 14.0]:
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = Vector3(2.0, 2.0, 2.0)
		collision.shape = shape
		collision.position = Vector3(local_x, 1.0, 0.0)
		body.add_child(collision)
	var spatial_hash = DroneTrainingWallSpatialHash.new()
	var walls: Array[Node3D] = [body]
	spatial_hash.rebuild(walls)
	var debug: Dictionary = spatial_hash.debug_state()
	_expect(
		spatial_hash.wall_count() == 1
		and int(debug.get("collision_shape_count", 0)) == 2,
		"one compound wall indexes every collision shape without inflating the wall count"
	)
	var origin = Vector3(10.0, 1.0, 0.0)
	var records = spatial_hash.query_segment(origin, origin + Vector3.RIGHT * 10.0)
	var distance = spatial_hash.raycast_distance_records(
		records,
		origin,
		Vector3.RIGHT,
		10.0
	)
	_expect(
		distance > 2.9 and distance < 3.1,
		"a later collision child on a compound wall remains visible to ML obstacle rays"
	)



func _test_unrestricted_obstacle_hashing() -> void:
	var huge_body := DroneTrainingRoomPresentation.add_static_obstacle(
		test_root,
		"HugeUnrestrictedObstacle",
		Vector3(0.0, 2.0, 0.0),
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 50000.0, "height": 4.0, "depth": 50000.0},
		Color.WHITE
	)
	var spatial_hash := DroneTrainingWallSpatialHash.new()
	var walls: Array[Node3D] = [huge_body]
	spatial_hash.rebuild(walls)
	var debug := spatial_hash.debug_state()
	_expect(
		int(debug.get("global_obstacle_count", 0)) == 1,
		"a huge unrestricted obstacle uses the bounded global candidate set"
	)
	var records := spatial_hash.query_nearby(Vector3.ZERO, 1.0)
	_expect(
		records.size() == 1,
		"global candidate obstacles remain visible to small local sensor queries"
	)
	_expect(
		is_zero_approx(spatial_hash.raycast_distance_records(
			records,
			Vector3.ZERO,
			Vector3.RIGHT,
			10.0
		)),
		"exact ray tests still detect a sensor origin inside a huge obstacle"
	)


func _shape_matches_kind(shape: Shape3D, kind: int) -> bool:
	match kind:
		DroneTrainingObstacleShape.Kind.BOX:
			return shape is BoxShape3D
		DroneTrainingObstacleShape.Kind.CYLINDER:
			return shape is CylinderShape3D
		DroneTrainingObstacleShape.Kind.SPHERE:
			return shape is SphereShape3D
		DroneTrainingObstacleShape.Kind.CAPSULE:
			return shape is CapsuleShape3D
	return false


func _test_camera_part_contract() -> void:
	var definition := load(
		"res://resources/drones/attachments/training_observer_camera.tres"
	) as DroneCameraAttachmentDefinition
	_expect(definition != null, "the observer camera loads as a normal drone attachment definition")
	if definition == null:
		return
	_expect(is_zero_approx(definition.get_mass()), "the installed camera part contributes exactly zero mass")
	_expect(definition.provides_capability(&"camera"), "the camera part advertises its reusable camera capability")
	_expect(PART_GEOMETRY.create_collision_shape(definition) == null, "the camera part has no collision before visuals are implemented")
	var visual := PART_GEOMETRY.create_visual(definition)
	_expect(visual != null and visual.get_child_count() == 0, "the camera part intentionally has no visual geometry yet")

	var loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	var mass_before := loadout.get_total_mass()
	_expect(loadout.install_attachment(0, definition), "the camera installs through an existing core attachment slot")
	_expect(is_equal_approx(loadout.get_total_mass(), mass_before), "installing the camera does not change drone mass")

	var camera := Camera3D.new()
	definition.configure_camera(camera)
	_expect(camera.near > 0.0 and camera.far > camera.near, "the camera part configures a valid view frustum")
	_expect(camera.position.is_equal_approx(definition.mount_position), "the runtime camera uses the part's core-relative mount")
	camera.free()
	visual.free()


func _test_camera_finished_drone_fade() -> void:
	var room := DroneTrainingRoom.new()
	var alive_weight := room._trial_camera_focus_weight({
		"episode_finished": false,
		"camera_focus_retired_at_usec": -1,
	})
	_expect(is_equal_approx(alive_weight, 1.0), "a living drone has full spectator influence")
	var now_usec := Time.get_ticks_usec()
	var fading_weight := room._trial_camera_focus_weight({
		"episode_finished": true,
		"camera_focus_retired_at_usec": now_usec - 500000,
	})
	_expect(
		fading_weight > 0.35 and fading_weight < 0.65,
		"a finished drone fades through the spectator centroid for about one second"
	)
	var expired_weight := room._trial_camera_focus_weight({
		"episode_finished": true,
		"camera_focus_retired_at_usec": now_usec - 2000000,
	})
	_expect(is_zero_approx(expired_weight), "a dead drone stops affecting spectator focus after the fade")
	room.free()


func _test_worker_group_rename_selection_dispatch() -> void:
	var room = DroneTrainingRoom.new()
	room.selected_group_id = 11
	var target: Dictionary = room._selected_group_rename_target()
	_expect(
		str(target.get("kind", "")) == "drone" and int(target.get("group_id", -1)) == 11,
		"F2 rename dispatch still recognizes selected drone groups"
	)
	room.selected_group_id = -1
	room.selected_limb_group_id = 12
	target = room._selected_group_rename_target()
	_expect(
		str(target.get("kind", "")) == "four_limb" and int(target.get("group_id", -1)) == 12,
		"F2 rename dispatch recognizes selected four-limb groups"
	)
	room.selected_limb_group_id = -1
	room.selected_turret_group_id = 13
	target = room._selected_group_rename_target()
	_expect(
		str(target.get("kind", "")) == "turret" and int(target.get("group_id", -1)) == 13,
		"F2 rename dispatch recognizes selected turret groups"
	)

	# Numeric group ids may overlap across worker kinds. Ignoring the selected group's own name
	# must therefore be kind-aware or an unrelated same-id group could be skipped accidentally.
	room.worker_groups.append({"group_id": 7, "name": "Drone Seven"})
	room.limb_training.groups.append({"group_id": 7, "name": "Limb Seven"})
	_expect(
		room._unique_group_name_for_kind("Drone Seven", "drone", 7) == "Drone Seven",
		"renaming a group may keep its own existing name"
	)
	_expect(
		room._unique_group_name_for_kind("Limb Seven", "drone", 7) == "Limb Seven 2",
		"same numeric ids in another worker kind do not bypass cross-kind name conflicts"
	)
	_expect(
		room._rolling_record_matches_requested_name({"model_name": "Original Model"}, "Original Model")
		and not room._rolling_record_matches_requested_name({"model_name": "Original Model"}, "Renamed Model"),
		"rolling saves fork when a runtime/save name changes instead of hiding the renamed policy under the old manifest"
	)
	room.free()


func _test_random_waypoint_limits() -> void:
	var room := DroneTrainingRoom.new()
	room.target_random_horizontal_extent = Vector2(4.0, 3.0)
	room.target_random_height_range = Vector2(1.0, 6.0)
	room.target_random_max_jump_distance = 2.5
	room.target_rng.seed = 123456
	var origin := Vector3(1.0, 3.0, -1.0)
	for _sample_index in range(128):
		var waypoint := room._choose_random_target_waypoint(origin)
		_expect(
			origin.distance_to(waypoint) <= 2.50001,
			"random waypoint respects the configured maximum jump distance"
		)
		_expect(
			absf(waypoint.x) <= 4.00001
			and absf(waypoint.z) <= 3.00001
			and waypoint.y >= 0.99999
			and waypoint.y <= 6.00001,
			"random waypoint remains inside the configured movement bounds"
		)
	room.free()


func _test_random_waypoint_start_and_area_preview() -> void:
	var room := DroneTrainingRoom.new()
	room.target_marker = MeshInstance3D.new()
	room.target_radius_ring = MeshInstance3D.new()
	room.target_random_area_preview = MeshInstance3D.new()
	room.add_child(room.target_marker)
	room.add_child(room.target_radius_ring)
	room.add_child(room.target_random_area_preview)
	room.target_behavior = 3
	room.target_random_horizontal_extent = Vector2(5.0, 4.0)
	room.target_random_height_range = Vector2(1.0, 3.0)
	room.target_random_area_visible = true
	room.episode_seed = 98765
	room._reset_target_for_episode()
	_expect(
		absf(room.target_subject_position.x) <= 5.00001
		and absf(room.target_subject_position.z) <= 4.00001
		and room.target_subject_position.y >= 0.99999
		and room.target_subject_position.y <= 3.00001,
		"a random-waypoint episode starts with the target inside the selected area"
	)
	room._refresh_random_target_area_preview()
	var box := room.target_random_area_preview.mesh as BoxMesh
	_expect(
		room.target_random_area_preview.visible
		and box != null
		and box.size.is_equal_approx(Vector3(10.0, 2.0, 8.0)),
		"the optional preview box matches the selected waypoint area"
	)
	_expect(
		room.target_marker.position.y >= 1.0
		and room.target_marker.position.y <= 3.0,
		"the visible target stays inside the literal waypoint preview volume without a hidden vertical offset"
	)
	room.free()


func _test_saved_map_layout_rebuild() -> void:
	var room := DroneTrainingRoom.new()
	room.custom_wall_container = Node3D.new()
	room.add_child(room.custom_wall_container)
	room._replace_custom_walls_from_records([
		{
			"shape_kind": DroneTrainingObstacleShape.Kind.BOX,
			"dimensions_m": {"width": 3.0, "height": 2.0, "depth": 1.0},
			"position_m": [2.0, 1.0, -4.0],
			"rotation_degrees": [0.0, 25.0, 0.0],
		},
		{
			"shape_kind": DroneTrainingObstacleShape.Kind.SPHERE,
			"dimensions_m": {"radius": 1.5},
			"position_m": [-3.0, 2.0, 5.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
		},
		{
			"shape_kind": {"broken": true},
			"dimensions_m": {"broken": true},
			"position_m": [NAN, {"broken": true}, 3.0],
			"rotation_degrees": [0.0, NAN, {"broken": true}],
		},
	])
	_expect(room.custom_walls.size() == 3, "loading a saved map restores every valid/malformed obstacle with safe defaults")
	_expect(
		room.custom_walls[0].position.is_equal_approx(Vector3(2.0, 1.0, -4.0))
		and room.custom_walls[0].rotation_degrees.is_equal_approx(Vector3(0.0, 25.0, 0.0)),
		"loaded obstacles keep their saved position and rotation"
	)
	_expect(
		room._custom_wall_shape_kind(room.custom_walls[1]) == DroneTrainingObstacleShape.Kind.SPHERE,
		"loaded obstacles keep their saved shape"
	)
	_expect(
		room.custom_walls[2].position.is_finite()
		and room.custom_walls[2].rotation.is_finite()
		and room._custom_wall_shape_kind(room.custom_walls[2]) == DroneTrainingObstacleShape.Kind.BOX,
		"malformed saved obstacle metadata falls back to finite transforms and a valid shape"
	)
	room.free()


func _test_training_item_definition_resources() -> void:
	var generic_definition: TrainingItemDefinition = load(
		"res://resources/training/items/generic_cargo.tres"
	) as TrainingItemDefinition
	var fallback_definition: TrainingItemDefinition = load(
		"res://resources/training/items/fallback_grabbable_cargo.tres"
	) as TrainingItemDefinition
	_expect(
		generic_definition != null
		and fallback_definition != null
		and not generic_definition.resource_path.is_empty()
		and not fallback_definition.resource_path.is_empty()
		and fallback_definition.grip_surface_tags.has("carryable"),
		"stock training items are authored as reusable .tres definitions rather than literal runtime cargo values"
	)
	var fallback_item: FourLimbTrainingGrabbableItem3D = FourLimbTrainingGrabbableItem3D.new()
	test_root.add_child(fallback_item)
	_expect(
		is_equal_approx(fallback_item.mass, fallback_definition.mass_kg)
		and fallback_item.dimensions == fallback_definition.dimensions
		and fallback_item.definition_resource_path == fallback_definition.resource_path,
		"fallback limb lesson cargo initializes directly from its saved item definition"
	)
	fallback_item.queue_free()



func _test_training_item_contract() -> void:
	var item: TrainingItem3D = TrainingItem3D.new()
	test_root.add_child(item)
	item.configure_item(
		17,
		DroneTrainingObstacleShape.Kind.CYLINDER,
		{"radius": 0.4, "height": 1.2},
		3.5,
		2.25,
		Transform3D(Basis.IDENTITY, Vector3(4.0, 0.6, -3.0)),
		true,
		"Medical Crate"
	)
	var record: Dictionary = item.environment_record()
	var candidate: Dictionary = item.target_candidate()
	var tags: PackedStringArray = GenericGrip3D.surface_tags_for(item)
	_expect(
		item.collision_layer == 1
		and (item.collision_mask & 1) != 0
		and (item.collision_mask & 2) != 0
		and (item.collision_mask & 4) != 0
		and bool(item.get_meta("training_grabbable_item", false))
		and tags.has("carryable"),
		"authored training items collide with arena/drones/limbs and use the generic carryable grip contract"
	)
	_expect(
		is_equal_approx(item.mass, 3.5)
		and is_equal_approx(item.reward_value, 2.25)
		and item.item_type == "medical_crate"
		and item.stable_id() == "training_item:17",
		"training items preserve physical mass, normalized cargo type, task reward value, and stable identity"
	)
	_expect(
		int(record.get("shape_kind", -1)) == DroneTrainingObstacleShape.Kind.CYLINDER
		and is_equal_approx(float(record.get("mass", 0.0)), 3.5)
		and is_equal_approx(float(record.get("reward_value", 0.0)), 2.25)
		and str(record.get("item_type", "")) == "medical_crate",
		"training item map records preserve shape, type, weight, and task value"
	)
	_expect(
		str(candidate.get("stable_id", "")) == item.stable_id()
		and str(candidate.get("target_kind", "")) == TrainingItem3D.TARGET_KIND
		and str(candidate.get("task_role", "")) == "pickup_item"
		and not bool(candidate.get("shootable", true))
		and (candidate.get("position_world", Vector3.ZERO) as Vector3).is_equal_approx(item.global_position),
		"training items expose a non-combat cargo-pickup target candidate for future take/deliver handlers"
	)
	_expect(
		float(TrainingTargetHandler.DEFAULT_PRIORITY_BY_KIND.get(TrainingItem3D.TARGET_KIND, 0.0))
		> float(TrainingTargetHandler.DEFAULT_PRIORITY_BY_KIND.get("navigation", 0.0)),
		"training-item task candidates use the configured cargo-pickup priority instead of an unknown zero-priority kind"
	)
	_expect(
		is_equal_approx(item.collision_radius_m(), sqrt(0.52)),
		"training-item target radius matches the authored cylinder geometry"
	)
	var grip_definition: LimbEndEffectorDefinition = LimbEndEffectorDefinition.new()
	grip_definition.enabled = true
	grip_definition.grip_mode = LimbEndEffectorDefinition.GripMode.CONTROLLED
	grip_definition.allow_dynamic_grip = true
	grip_definition.maximum_held_mass = 4.0
	grip_definition.compatible_surface_tags = PackedStringArray(["carryable"])
	var grip_contract: GenericGrip3D = GenericGrip3D.new()
	grip_contract.definition = grip_definition
	_expect(
		grip_contract._candidate_is_compatible(item, item.get_rid(), tags),
		"a training item within the gripper mass limit is accepted through the real generic-grip compatibility contract"
	)
	grip_definition.maximum_held_mass = 3.0
	_expect(
		not grip_contract._candidate_is_compatible(item, item.get_rid(), tags),
		"training-item Weight participates in the real gripper carrying limit rather than being display-only metadata"
	)
	grip_contract.free()
	var spatial_hash: ServerSpatialHash3D = ServerSpatialHash3D.new(4.0)
	spatial_hash.register_entity(
		item.spatial_key(),
		item,
		TrainingItem3D.ENTITY_KIND,
		item.training_item_id,
		item.discovery_metadata()
	)
	_expect(
		spatial_hash.readonly_keys_for_kind(TrainingItem3D.ENTITY_KIND).has(item.spatial_key()),
		"training items are discoverable through the shared worker entity index"
	)
	item.set_simulation_active(false)
	var paused_at: Vector3 = item.global_position
	item.linear_velocity = Vector3(3.0, 0.0, -1.0)
	_expect(
		item.freeze
		and item.global_position.is_equal_approx(paused_at)
		and item.task_velocity_world().is_zero_approx()
		and (item.target_candidate().get("velocity_world", Vector3.ONE) as Vector3).is_zero_approx(),
		"frozen shared items keep their physics state for resume but expose zero current task velocity to other active workers"
	)
	item.set_simulation_active(true)
	_expect(not item.freeze, "authored training items resume rigid-body physics with the training simulation")
	item.linear_velocity = Vector3(NAN, 0.0, 0.0)
	_expect(
		item.task_velocity_world().is_zero_approx()
		and item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"non-finite item physics velocity fails closed in observations and schedules a safe authored-spawn recovery"
	)
	item.linear_velocity = Vector3.ZERO

	item.set_simulation_active(false)
	item.global_position = Vector3(60.0, 0.6, -3.0)
	_expect(
		item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an authored item that escapes the ordinary arena envelope is detected for recovery"
	)
	item.reset_to_spawn()
	item.global_position = Vector3(4.0, -8.0, -3.0)
	_expect(
		item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an authored item that falls through the open arena edge is detected for recovery"
	)
	item.reset_to_spawn()
	item.configure_item(
		17,
		DroneTrainingObstacleShape.Kind.CYLINDER,
		{"radius": 0.4, "height": 1.2},
		3.5,
		2.25,
		Transform3D(Basis.IDENTITY, Vector3(45.0, 0.6, -3.0)),
		true
	)
	item.global_position = Vector3(60.0, 0.6, -3.0)
	_expect(
		item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an authored spawn inside the recovery margin still arms that axis and recovers a later escape beyond the margin"
	)
	item.configure_item(
		17,
		DroneTrainingObstacleShape.Kind.CYLINDER,
		{"radius": 0.4, "height": 1.2},
		3.5,
		2.25,
		Transform3D(Basis.IDENTITY, Vector3(60.0, 0.6, -3.0)),
		true
	)
	item.global_position = Vector3(66.0, 0.6, -3.0)
	_expect(
		not item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an intentionally out-of-bounds authored spawn expands that axis's recovery envelope instead of immediately snapping back"
	)
	item.global_position = Vector3(70.0, 0.6, -3.0)
	_expect(
		item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an out-of-bounds authored item is still recoverable after escaping beyond its spawn-aware margin"
	)
	item.global_position = Vector3(60.0, -12.0, -3.0)
	_expect(
		item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an item authored outside one horizontal axis is still recovered if it later falls through a valid floor envelope"
	)
	item.configure_item(
		17,
		DroneTrainingObstacleShape.Kind.CYLINDER,
		{"radius": 0.4, "height": 1.2},
		3.5,
		2.25,
		Transform3D(Basis.IDENTITY, Vector3(4.0, 0.6, -3.0)),
		true
	)
	item.global_position = Vector3(4.0, 80.0, -3.0)
	_expect(
		item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an ordinary authored item launched far above the usable training volume is recovered instead of remaining unreachable forever"
	)
	item.configure_item(
		17,
		DroneTrainingObstacleShape.Kind.CYLINDER,
		{"radius": 0.4, "height": 1.2},
		3.5,
		2.25,
		Transform3D(Basis.IDENTITY, Vector3(4.0, 80.0, -3.0)),
		true
	)
	item.global_position = Vector3(4.0, 84.0, -3.0)
	_expect(
		not item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an intentionally high authored item receives a spawn-aware upper margin instead of immediately snapping down"
	)
	item.global_position = Vector3(4.0, 90.0, -3.0)
	_expect(
		item.needs_recovery(Vector3(80.0, 20.0, 80.0), 8.0, -6.0),
		"an intentionally high authored item is still recovered if it later escapes far beyond its authored height"
	)

	var malformed_item: TrainingItem3D = TrainingItem3D.new()
	test_root.add_child(malformed_item)
	var valid_spawn: Transform3D = Transform3D(
		Basis.from_euler(Vector3(0.1, 0.2, 0.3)),
		Vector3(-2.0, 0.4, 1.0)
	)
	malformed_item.configure_item(18, DroneTrainingObstacleShape.Kind.SPHERE, {"radius": 0.5}, 2.0, 4.0, valid_spawn, true)
	var malformed_basis: Basis = Basis(
		Vector3(NAN, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0)
	)
	malformed_item.configure_item(18, DroneTrainingObstacleShape.Kind.SPHERE, {"radius": 0.5}, NAN, NAN, Transform3D(malformed_basis, Vector3(NAN, 2.0, 3.0)), true)
	_expect(
		is_finite(malformed_item.mass)
		and is_finite(malformed_item.reward_value)
		and malformed_item.spawn_transform_world.is_equal_approx(valid_spawn),
		"malformed external item mass/value/transform fail closed to finite physical state and the last valid authored spawn"
	)
	var scaled_transform: Transform3D = Transform3D(
		Basis.from_scale(Vector3(2.0, 3.0, 4.0)),
		Vector3(1.0, 2.0, 3.0)
	)
	malformed_item.configure_item(18, DroneTrainingObstacleShape.Kind.BOX, {"width": 1.0, "height": 1.0, "depth": 1.0}, 1.0, 1.0, scaled_transform, true)
	_expect(
		is_equal_approx(absf(malformed_item.global_transform.basis.determinant()), 1.0)
		and malformed_item.global_position.is_equal_approx(Vector3(1.0, 2.0, 3.0)),
		"item transforms cannot smuggle scale/shear into collision geometry owned by the explicit dimension fields"
	)
	var safe_scaled_spawn: Transform3D = malformed_item.spawn_transform_world
	var reflected_transform: Transform3D = Transform3D(
		Basis.from_scale(Vector3(-1.0, 1.0, 1.0)),
		Vector3(8.0, 9.0, 10.0)
	)
	malformed_item.configure_item(18, DroneTrainingObstacleShape.Kind.BOX, {"width": 1.0, "height": 1.0, "depth": 1.0}, 1.0, 1.0, reflected_transform, true)
	_expect(
		malformed_item.spawn_transform_world.is_equal_approx(safe_scaled_spawn),
		"mirrored item transforms fail closed instead of introducing a negative-scale physics basis"
	)
	malformed_item.queue_free()
	item.queue_free()


func _test_delivery_destination_contract() -> void:
	var item: TrainingItem3D = TrainingItem3D.new()
	test_root.add_child(item)
	item.configure_item(
		91,
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 0.5, "height": 0.5, "depth": 0.5},
		2.0,
		3.0,
		Transform3D(Basis.IDENTITY, Vector3(2.0, 0.25, -4.0)),
		true,
		"medical_crate"
	)
	var destination: TrainingItemDeliveryDestination3D = TrainingItemDeliveryDestination3D.new()
	test_root.add_child(destination)
	destination.configure_destination(
		3,
		2,
		1.5,
		1.25,
		Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, -4.0)),
		Color("54e6b1")
	)
	var candidate: Dictionary = destination.target_candidate({"accepted_item_types": ["ore", "medical_crate"]})
	_expect(
		destination.stable_id() == "training_delivery:3:2"
		and str(candidate.get("target_kind", "")) == "cargo_delivery"
		and str(candidate.get("task_role", "")) == "delivery_destination"
		and not bool(candidate.get("shootable", true)),
		"delivery destinations expose stable non-combat cargo-delivery targets"
	)
	_expect(
		float(TrainingTargetHandler.DEFAULT_PRIORITY_BY_KIND.get(TrainingItemDeliveryDestination3D.TARGET_KIND, 0.0))
		> float(TrainingTargetHandler.DEFAULT_PRIORITY_BY_KIND.get(TrainingItem3D.TARGET_KIND, 0.0)),
		"cargo-delivery destinations have explicit task priority above cargo pickup once the worker is in the carry phase"
	)
	_expect(
		destination.contains_item(item),
		"an item physically inside the destination volume satisfies delivery containment"
	)
	_expect(
		is_zero_approx(destination.distance_to_item(item)),
		"delivery potential is zero everywhere inside the accepted destination volume"
	)
	item.global_position = Vector3(5.0, 0.25, -4.0)
	_expect(
		not destination.contains_item(item),
		"an item outside the destination radius is not falsely delivered"
	)
	_expect(
		is_equal_approx(destination.distance_to_item(item), 1.5),
		"delivery potential measures distance to the volume boundary rather than its centre"
	)
	var wide_flat_item: TrainingItem3D = TrainingItem3D.new()
	test_root.add_child(wide_flat_item)
	wide_flat_item.configure_item(
		92,
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 10.0, "height": 0.2, "depth": 10.0},
		2.0,
		3.0,
		Transform3D(Basis.IDENTITY, Vector3(2.0, 4.0, -4.0)),
		true,
		"medical_crate"
	)
	_expect(
		not destination.contains_item(wide_flat_item),
		"a wide flat item is not falsely delivered metres above a bay merely because its enclosing sphere is large"
	)
	_expect(
		is_equal_approx(destination.distance_to_item(wide_flat_item), 2.65),
		"delivery distance uses the item's true oriented vertical support extent rather than its full bounding radius"
	)
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.delivery_destination_container = Node3D.new()
	room.add_child(room.delivery_destination_container)
	room._replace_delivery_destinations_from_records([
		{
			"group_id": 7,
			"name": "Warehouse bays",
			"color": "54e6b1",
			"accept_all_item_types": false,
			"accepted_item_types": ["ore", "Medical Crate", "ore"],
			"radius_m": 1.75,
			"height_m": 1.5,
			"approach_reward_scale": 1.25,
			"completion_reward_scale": 4.0,
			"destinations": [
				{"destination_id": 1, "position_m": [1.0, 0.0, 2.0], "rotation_degrees": [0.0, 0.0, 0.0]},
				{"destination_id": 2, "position_m": [-3.0, 0.0, 4.0], "rotation_degrees": [0.0, 30.0, 0.0]},
			],
		},
	])
	_expect(room.delivery_destination_groups.size() == 1, "saved maps restore destination groups")
	var group: Dictionary = room.delivery_destination_groups[0]
	var accepted: PackedStringArray = group.get("accepted_item_types", PackedStringArray())
	var restored_destinations: Array[TrainingItemDeliveryDestination3D] = room._valid_delivery_destinations(group)
	var shared_geometry: bool = true
	for restored_destination: TrainingItemDeliveryDestination3D in restored_destinations:
		shared_geometry = (
			shared_geometry
			and is_equal_approx(restored_destination.radius_m, 1.75)
			and is_equal_approx(restored_destination.height_m, 1.5)
		)
	_expect(
		accepted.size() == 2
		and accepted.has("ore")
		and accepted.has("medical_crate")
		and restored_destinations.size() == 2
		and shared_geometry,
		"one delivery-group policy can accept several normalized item types and applies its shared geometry to every placed destination"
	)
	item.item_type = "medical_crate"
	_expect(
		room._delivery_group_accepts_item(group, item),
		"delivery-group acceptance uses the Training Item type contract"
	)
	item.item_type = "junk"
	_expect(
		not room._delivery_group_accepts_item(group, item),
		"unlisted item types are rejected when accept-all is disabled"
	)
	var accept_all_group: Dictionary = group.duplicate(false)
	accept_all_group["accept_all_item_types"] = true
	_expect(
		room._delivery_group_accepts_item(accept_all_group, item),
		"accept-all destination policies accept an item even when its type is not listed explicitly"
	)
	var parsed_types: PackedStringArray = room._parse_delivery_item_types(
		"ore,   , Medical Crate, ,ore"
	)
	_expect(
		parsed_types.size() == 2
		and parsed_types.has("ore")
		and parsed_types.has("medical_crate")
		and not parsed_types.has("generic"),
		"blank comma-separated delivery-type fields are ignored instead of silently accepting generic cargo"
	)
	_expect(
		room.training_entity_spatial_hash.readonly_keys_for_kind(
			TrainingItemDeliveryDestination3D.ENTITY_KIND
		).size() == 2,
		"every restored destination is discoverable through the shared training entity index"
	)
	var accepted_item: TrainingItem3D = TrainingItem3D.new()
	room.add_child(accepted_item)
	accepted_item.configure_item(
		101,
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 0.4, "height": 0.4, "depth": 0.4},
		1.0,
		1.0,
		Transform3D(Basis.IDENTITY, Vector3(4.0, 0.2, 0.0)),
		true,
		"medical_crate"
	)
	accepted_item.set_meta("training_authored_item", true)
	room.training_items.append(accepted_item)
	room._register_training_item(accepted_item)
	var rejected_item: TrainingItem3D = TrainingItem3D.new()
	room.add_child(rejected_item)
	rejected_item.configure_item(
		102,
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 0.4, "height": 0.4, "depth": 0.4},
		1.0,
		1.0,
		Transform3D(Basis.IDENTITY, Vector3(1.0, 0.2, 0.0)),
		true,
		"junk"
	)
	rejected_item.set_meta("training_authored_item", true)
	room.training_items.append(rejected_item)
	room._register_training_item(rejected_item)
	var delivery_deck: FourLimbRewardDeck = FourLimbRewardDeck.new()
	delivery_deck.card("item_delivery").enabled = true
	room.limb_training.groups_by_id[44] = {
		"group_id": 44,
		"reward_deck": delivery_deck,
	}
	var fallback_item_type: String = room._delivery_fallback_item_type_for_limb(44)
	_expect(
		accepted.has(fallback_item_type),
		"delivery fallback cargo deterministically uses a type accepted by a placed destination instead of generic cargo that may be impossible to deliver"
	)
	var fallback_item: FourLimbTrainingGrabbableItem3D = FourLimbTrainingGrabbableItem3D.new()
	room.add_child(fallback_item)
	fallback_item.reset_item(
		Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 0.0)),
		0,
		fallback_item_type
	)
	_expect(
		room._any_delivery_group_accepts_item(fallback_item),
		"fallback cargo selected for a delivery lesson is actually compatible with an active destination"
	)
	fallback_item.queue_free()
	var delivery_candidate: TrainingItem3D = room._training_item_candidate_for_limb(
		Vector3.ZERO,
		[],
		44
	)
	_expect(
		delivery_candidate == accepted_item,
		"delivery-trained workers are assigned a cargo type accepted by at least one active destination instead of an observationally indistinguishable rejected item"
	)
	var pickup_phase: Dictionary = room._delivery_destination_for_limb(null, accepted_item, 44)
	_expect(
		bool(pickup_phase.get("task_active", false))
		and str(pickup_phase.get("phase", "")) == "pickup"
		and (pickup_phase.get("pickup_target_position_world", Vector3.INF) as Vector3).is_equal_approx(accepted_item.global_position)
		and float(pickup_phase.get("pickup_target_radius_m", 0.0)) > accepted_item.collision_radius_m(),
		"delivery lessons route the generic task objective to compatible cargo before grip so policies receive dense approach guidance before the conditional carry phase"
	)
	var round_trip: Array[Dictionary] = room._delivery_destination_environment_records()
	_expect(
		round_trip.size() == 1
		and (round_trip[0].get("destinations", []) as Array).size() == 2
		and (round_trip[0].get("accepted_item_types", []) as Array).has("medical_crate"),
		"destination groups round-trip their shared policy and all placed volumes through map data"
	)
	var malformed_bool_room: DroneTrainingRoom = DroneTrainingRoom.new()
	malformed_bool_room.delivery_destination_container = Node3D.new()
	malformed_bool_room.add_child(malformed_bool_room.delivery_destination_container)
	malformed_bool_room._replace_delivery_destinations_from_records([
		{
			"group_id": 1,
			"accept_all_item_types": "false",
			"accepted_item_types": ["ore"],
			"destinations": [],
		},
	])
	_expect(
		not bool(malformed_bool_room.delivery_destination_groups[0].get("accept_all_item_types", true)),
		"malformed string booleans in map data fail closed instead of broadening a delivery policy"
	)
	malformed_bool_room.queue_free()

	# Completion must win over a merely closer centre in another compatible group. Otherwise an
	# item already inside a wide destination could be routed to a tiny neighbouring zone and never
	# report delivery even though it satisfies a valid accepting volume.
	var contained_destination: TrainingItemDeliveryDestination3D = room._valid_delivery_destinations(group)[0]
	contained_destination.configure_destination(
		7,
		contained_destination.destination_id,
		1.75,
		1.5,
		Transform3D(Basis.IDENTITY, Vector3.ZERO),
		group.get("color", Color("54e6b1"))
	)
	room._register_delivery_destination(contained_destination, group)
	accepted_item.global_position = Vector3(1.6, 0.2, 0.0)
	var tiny_destination: TrainingItemDeliveryDestination3D = TrainingItemDeliveryDestination3D.new()
	room.delivery_destination_container.add_child(tiny_destination)
	tiny_destination.configure_destination(
		8,
		1,
		0.10,
		1.0,
		Transform3D(Basis.IDENTITY, Vector3(1.45, 0.0, 0.0)),
		Color("8de1ff")
	)
	var tiny_group: Dictionary = {
		"group_id": 8,
		"name": "Tiny bay",
		"color": Color("8de1ff"),
		"accept_all_item_types": false,
		"accepted_item_types": PackedStringArray(["medical_crate"]),
		"radius_m": 0.10,
		"height_m": 1.0,
		"approach_reward_scale": 1.0,
		"completion_reward_scale": 1.0,
		"destination_counter": 1,
		"destinations": [tiny_destination],
	}
	room.delivery_destination_groups.append(tiny_group)
	room.delivery_destination_groups_by_id[8] = tiny_group
	room._register_delivery_destination(tiny_destination, tiny_group)
	var containment_match: Dictionary = room._best_delivery_destination_for_item(accepted_item)
	_expect(
		containment_match.get("destination") == contained_destination
		and bool(containment_match.get("item_inside", false)),
		"a destination that already contains the cargo outranks a closer non-containing compatible centre"
	)
	var delivered_candidate: TrainingItem3D = room._training_item_candidate_for_limb(
		Vector3.ZERO,
		[],
		44
	)
	_expect(
		delivered_candidate == null,
		"cargo already resting in any accepting destination is treated as delivered instead of being reassigned as fresh pickup cargo"
	)
	room.free()
	destination.queue_free()
	item.queue_free()


func _test_training_item_dimension_editor_matches_physics() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.training_item_dimensions_body = VBoxContainer.new()
	room.add_child(room.training_item_dimensions_body)
	room.training_item_shape_kind = DroneTrainingObstacleShape.Kind.CAPSULE
	room.training_item_dimensions = {"radius": 2.0, "height": 1.0}
	room._rebuild_training_item_dimension_inputs()
	var normalized_height: float = float(room.training_item_dimensions.get("height", 0.0))
	var height_input: SpinBox = room.training_item_dimension_inputs.get("height") as SpinBox
	_expect(
		is_equal_approx(normalized_height, 4.0)
		and height_input != null
		and is_equal_approx(height_input.value, 4.0),
		"item dimension UI shows the normalized capsule size that collision/visual geometry will actually use"
	)
	room.free()


func _test_training_item_editor_uses_authored_spawn() -> void:
	var item: TrainingItem3D = TrainingItem3D.new()
	test_root.add_child(item)
	var authored_rotation: Vector3 = Vector3(deg_to_rad(15.0), deg_to_rad(25.0), deg_to_rad(-10.0))
	var authored_transform: Transform3D = Transform3D(
		Basis.from_euler(authored_rotation),
		Vector3(2.0, 0.75, -3.0)
	)
	item.configure_item(29, DroneTrainingObstacleShape.Kind.BOX, {"width": 1.0, "height": 0.5, "depth": 2.0}, 6.0, 7.0, authored_transform, true)
	item.set_simulation_active(false)
	item.global_transform = Transform3D(Basis.IDENTITY, Vector3(19.0, 8.0, 11.0))

	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.selected_training_item = item
	room._sync_training_item_editor_from_selected()
	_expect(
		Vector3(
			room.training_item_position_x_m,
			room.training_item_position_y_m,
			room.training_item_position_z_m
		).is_equal_approx(authored_transform.origin),
		"selecting a physically moved item edits its authored reset spawn instead of its transient rigid-body pose"
	)
	_expect(
		is_equal_approx(room.training_item_pitch_degrees, 15.0)
		and is_equal_approx(room.training_item_yaw_degrees, 25.0)
		and is_equal_approx(room.training_item_roll_degrees, -10.0),
		"training-item editor restores the authored spawn rotation after the item has moved"
	)
	room.free()
	item.queue_free()


func _test_training_item_map_restore_contract() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.training_item_container = Node3D.new()
	room.add_child(room.training_item_container)
	room._replace_training_items_from_records([
		{
			"item_id": 4,
			"shape_kind": DroneTrainingObstacleShape.Kind.SPHERE,
			"dimensions_m": {"radius": 0.7},
			"mass": 3.25,
			"reward_value": 8.5,
			"item_type": "Medical Crate",
			"position_m": [1.0, 2.0, -3.0],
			"rotation_degrees": [0.0, 45.0, 0.0],
		},
		{
			"item_id": 4,
			"shape_kind": DroneTrainingObstacleShape.Kind.BOX,
			"dimensions_m": {"width": 2.0, "height": 1.0, "depth": 0.5},
			"mass": 1.5,
			"reward_value": 2.0,
			"position_m": [-4.0, 0.5, 5.0],
			"rotation_degrees": [10.0, 20.0, 30.0],
		},
		{
			"item_id": {"broken": true},
			"shape_kind": {"broken": true},
			"dimensions_m": {"width": NAN, "height": {"broken": true}},
			"mass": NAN,
			"reward_value": NAN,
			"position_m": [NAN, {"broken": true}, 2.0],
			"rotation_degrees": [NAN, 0.0, {"broken": true}],
		},
		{
			"item_id": 75,
			"definition_resource_path": "res://resources/training/items/fallback_grabbable_cargo.tres",
			"position_m": [7.0, 0.5, 1.0],
		},
		{
			"item_id": 77,
			"definition_resource_path": "res://resources/training/items/does_not_exist.tres",
			"position_m": [0.0, 1.0, 0.0],
		},
	])
	_expect(
		room.training_items.size() == 4,
		"legacy item records migrate to generic cargo, resource-backed records inherit their .tres, and missing definitions fail closed"
	)
	var first: TrainingItem3D = room.training_items[0]
	var second: TrainingItem3D = room.training_items[1]
	var malformed: TrainingItem3D = room.training_items[2]
	var resource_backed: TrainingItem3D = room.training_items[3]
	_expect(
		first.training_item_id == 4
		and second.training_item_id != first.training_item_id
		and malformed.training_item_id != first.training_item_id
		and malformed.training_item_id != second.training_item_id,
		"saved-map restore remaps duplicate or malformed item ids so stable task addresses remain unique"
	)
	_expect(
		first.shape_kind == DroneTrainingObstacleShape.Kind.SPHERE
		and is_equal_approx(float(first.dimensions.get("radius", 0.0)), 0.7)
		and is_equal_approx(first.mass, 3.25)
		and is_equal_approx(first.reward_value, 8.5)
		and first.item_type == "medical_crate"
		and first.spawn_transform_world.origin.is_equal_approx(Vector3(1.0, 2.0, -3.0)),
		"saved-map restore preserves authored item shape, type, dimensions, weight, value, and transform"
	)
	_expect(
		malformed.global_position.is_finite()
		and malformed.spawn_transform_world.origin.is_finite()
		and is_finite(malformed.mass)
		and malformed.mass >= 0.01
		and is_finite(malformed.reward_value)
		and malformed.reward_value >= 0.0,
		"malformed saved item records recover to finite usable physics/task values"
	)
	_expect(
		resource_backed.definition_resource_path
		== "res://resources/training/items/fallback_grabbable_cargo.tres"
		and is_equal_approx(resource_backed.mass, 0.85)
		and is_equal_approx(float(resource_backed.dimensions.get("width", 0.0)), 0.34),
		"resource-backed map items inherit omitted physics fields from their saved .tres archetype"
	)
	_expect(
		room.training_entity_spatial_hash.readonly_keys_for_kind(TrainingItem3D.ENTITY_KIND).size() == 4,
		"every restored training item is re-registered in the shared worker discovery index"
	)
	first.set_simulation_active(false)
	first.global_position = Vector3(1.0, -9.0, -3.0)
	var recovered_count: int = room._recover_lost_training_items()
	_expect(
		recovered_count == 1
		and first.global_position.is_equal_approx(first.spawn_transform_world.origin),
		"room-level lost-item recovery restores the authored spawn instead of leaving a permanent unreachable task object"
	)
	var records: Array[Dictionary] = room._training_item_environment_records()
	_expect(
		records.size() == 4
		and is_equal_approx(float(records[0].get("mass", 0.0)), 3.25)
		and is_equal_approx(float(records[0].get("reward_value", 0.0)), 8.5)
		and str(records[0].get("item_type", "")) == "medical_crate"
		and str(records[0].get("definition_resource_path", ""))
		== "res://resources/training/items/generic_cargo.tres",
		"restored item map records round-trip their source .tres plus physical/task overrides without reading transient motion"
	)
	room.free()


func _test_target_marker_ring_alignment() -> void:
	var room := DroneTrainingRoom.new()
	room.target_marker = MeshInstance3D.new()
	room.target_radius_ring = MeshInstance3D.new()
	room.add_child(room.target_marker)
	room.add_child(room.target_radius_ring)
	var subject_position := Vector3(3.0, 1.75, -4.0)
	room._set_target_subject_position(subject_position)
	_expect(
		room.target_marker.position.is_equal_approx(room.target_radius_ring.position),
		"the visible target ball remains centered inside its hover-radius ring"
	)
	_expect(
		room.target_marker.position.is_equal_approx(subject_position),
		"the shared target visual is the literal routed navigation target with no hidden vertical offset"
	)
	_expect(
		room._target_objective_local_position().is_equal_approx(
			room.target_marker.position
		),
		"the reward objective uses the same position shown by the ball and ring"
	)
	room.free()


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAILED: %s" % message)
