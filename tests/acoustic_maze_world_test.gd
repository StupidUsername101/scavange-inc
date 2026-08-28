extends SceneTree

const LAYOUT := preload("res://scripts/world/acoustic_maze_layout.gd")
const NATURE_LAYOUT := preload("res://scripts/world/world_nature_layout.gd")
const SERVER_MAZE_SCENE := preload("res://scenes/server/acoustic_maze.tscn")
const CLIENT_MAZE_SCENE := preload("res://scenes/proxy/acoustic_maze.tscn")
const SERVER_WORLD_PATH := "res://scenes/server/server_world.tscn"
const CLIENT_WORLD_PATH := "res://scenes/proxy/world.tscn"
const EXIT_RADIO_PATH := "res://resources/world/maze_exit_beacon_radio.tres"

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_active_world_wiring()
	await _test_live_exit_radio()
	await _test_shared_runtime_geometry()
	_test_temporary_end_budget()
	if failure_count == 0:
		print("Acoustic maze world tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Acoustic maze world tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_active_world_wiring() -> void:
	var server_world_scene := load(SERVER_WORLD_PATH) as PackedScene
	var client_world_scene := load(CLIENT_WORLD_PATH) as PackedScene
	var server_world := server_world_scene.instantiate() as Node3D
	var client_world := client_world_scene.instantiate() as Node3D
	var server_maze := server_world.get_node_or_null("AcousticMaze") as StaticBody3D
	var client_maze := client_world.get_node_or_null("AcousticMaze") as Node3D
	_expect(
		server_maze != null and client_maze != null,
		"active server and client test worlds both instantiate the acoustic maze"
	)
	if server_maze != null and client_maze != null:
		_expect(
			server_maze.position.is_equal_approx(LAYOUT.WORLD_POSITION)
			and client_maze.position.is_equal_approx(server_maze.position),
			"authoritative collision and client presentation share the maze transform"
		)
		_expect(
			bool(server_maze.get("spawn_exit_radio")),
			"the active authoritative maze schedules its placed exit radio"
		)

	var bounds := LAYOUT.local_bounds()
	var world_min_x := LAYOUT.WORLD_POSITION.x + bounds.position.x
	var world_min_z := LAYOUT.WORLD_POSITION.z + bounds.position.z
	var world_max_x := world_min_x + bounds.size.x
	var world_max_z := world_min_z + bounds.size.z
	var nature_clear := true
	for descriptor: Dictionary in NATURE_LAYOUT.visual_descriptors():
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		if (
			position.x >= world_min_x - 3.0
			and position.x <= world_max_x + 3.0
			and position.z >= world_min_z - 3.0
			and position.z <= world_max_z + 3.0
		):
			nature_clear = false
			break
	_expect(
		world_min_x
		> NATURE_LAYOUT.FOREST_MAX.x + LAYOUT.WORLD_CLEARANCE_MARGIN
		and nature_clear,
		"the entire maze lies east of the generated forest and its collision/probe bounds"
	)
	server_world.free()
	client_world.free()


func _test_live_exit_radio() -> void:
	var server := root.get_node_or_null("Server")
	if server == null:
		_expect(false, "live maze beacon requires the authoritative Server autoload")
		return
	server.call("spawn_server_world")
	await process_frame
	await physics_frame
	await process_frame
	var server_world := server.get("server_world") as Node3D
	var maze := (
		server_world.get_node_or_null("AcousticMaze") as StaticBody3D
		if server_world != null
		else null
	)
	var radios := server.get("server_radios_by_item_id") as Dictionary
	var beacon: RigidBody3D
	for value: Variant in radios.values():
		var candidate := value as RigidBody3D
		if candidate != null and bool(candidate.get_meta(&"maze_exit_beacon", false)):
			beacon = candidate
			break
	_expect(
		maze != null and beacon != null,
		"the live authoritative world actually spawns and registers the maze exit radio"
	)
	if maze != null and beacon != null:
		var expected_local := LAYOUT.exit_position()
		expected_local.y = 0.05
		var expected_position := maze.global_transform * expected_local
		_expect(
			beacon.global_position.distance_to(expected_position) <= 0.08
			and not beacon.freeze
			and not bool(beacon.get_meta(&"grip_surface_disabled", false))
			and (beacon.get_meta(&"grip_surface_tags", PackedStringArray()) as PackedStringArray).has("carryable")
			and not bool(beacon.get("powered")),
			"the beacon starts at the marked exit cell as an ordinary grabbable radio without auto-starting music"
		)
	server.call("_clear_runtime_session")
	await process_frame


func _test_shared_runtime_geometry() -> void:
	var server_maze := SERVER_MAZE_SCENE.instantiate() as StaticBody3D
	var client_maze := CLIENT_MAZE_SCENE.instantiate() as Node3D
	server_maze.set("spawn_exit_radio", false)
	root.add_child(server_maze)
	root.add_child(client_maze)
	await process_frame
	await physics_frame

	var collision_count := 0
	var probe_count := 0
	var boundary_portal_count := 0
	var reciprocal_boundary_portal_count := 0
	var open_aperture_portal_count := 0
	var correctly_partitioned_interior_probe_count := 0
	var correctly_partitioned_exterior_probe_count := 0
	for child: Node in server_maze.get_children():
		if child is CollisionShape3D:
			collision_count += 1
		elif child is AcousticProbe3D:
			probe_count += 1
			var probe := child as AcousticProbe3D
			if str(probe.probe_id).begins_with("maze_exterior"):
				correctly_partitioned_exterior_probe_count += int(
					probe.auto_connect_layer == LAYOUT.EXTERIOR_AUTO_CONNECT_LAYER
					and probe.auto_connect_mask == (
						LAYOUT.EXTERIOR_AUTO_CONNECT_LAYER
						| LAYOUT.WORLD_AUTO_CONNECT_LAYER
					)
					and not probe.attachment_exclusion_half_extents.is_zero_approx()
				)
			else:
				correctly_partitioned_interior_probe_count += int(
					probe.auto_connect_layer == LAYOUT.INTERIOR_AUTO_CONNECT_LAYER
					and probe.auto_connect_mask == LAYOUT.INTERIOR_AUTO_CONNECT_LAYER
					and not probe.attachment_influence_half_extents.is_zero_approx()
					and probe.attachment_influence_boundary_fade > 0.0
				)
		elif child is AcousticPortal3D:
			boundary_portal_count += 1
			var portal := child as AcousticPortal3D
			reciprocal_boundary_portal_count += int(portal.bidirectional)
			open_aperture_portal_count += int(portal.material == null)
	var expected_boundary_portals := 0
	for descriptor: Dictionary in LAYOUT.exterior_probe_descriptors():
		expected_boundary_portals += int(descriptor.has("transmission_cell"))
	_expect(
		collision_count == LAYOUT.structural_boxes().size(),
		"one shared layout produces every authoritative floor, roof, and wall collision"
	)
	_expect(
		probe_count == (
			LAYOUT.cell_count() + LAYOUT.exterior_probe_descriptors().size()
		),
		"the playable maze deploys cell probes plus a collision-visible exterior aperture route"
	)
	_expect(
		expected_boundary_portals > 0
		and boundary_portal_count == expected_boundary_portals,
		"every generated exterior sample receives one explicit boundary radiation edge"
	)
	_expect(
		reciprocal_boundary_portal_count == boundary_portal_count
		and open_aperture_portal_count == 1,
		"maze shell radiation is reciprocal and keeps the entrance acoustically open"
	)
	_expect(
		correctly_partitioned_interior_probe_count == LAYOUT.cell_count()
		and correctly_partitioned_exterior_probe_count
		== LAYOUT.exterior_probe_descriptors().size(),
		"interior endpoints cannot auto-connect through the exterior graph while outdoor probes still join the world"
	)

	var every_visual_exists := true
	for descriptor: Dictionary in LAYOUT.structural_boxes():
		if client_maze.get_node_or_null(str(descriptor.get("name", ""))) == null:
			every_visual_exists = false
			break
	_expect(
		every_visual_exists,
		"client maze renders every box from the authoritative shared layout"
	)
	_expect(
		client_maze.get_node_or_null("MazeEntranceLabel") != null
		and client_maze.get_node_or_null("ExitBeaconLight") != null,
		"the field has a visible entrance and exit beacon"
	)
	var exit_radio := load(EXIT_RADIO_PATH) as RadioItemDefinition
	_expect(
		exit_radio != null
		and exit_radio.maximum_hearing_distance
		>= float(LAYOUT.entrance_route_distance_cells()) * LAYOUT.CELL_SIZE,
		"the exit radio has enough authored reach for the complete maze route"
	)

	server_maze.queue_free()
	client_maze.queue_free()
	await process_frame


func _test_temporary_end_budget() -> void:
	var sprint_seconds := (
		ServerPlayer.MAX_STAMINA / ServerPlayer.RUN_STAMINA_DRAIN_PER_SECOND
	)
	_expect(
		is_equal_approx(ServerPlayer.TEMPORARY_STAMINA_MULTIPLIER, 3.0)
		and is_equal_approx(
			ServerPlayer.MAX_STAMINA,
			ServerPlayer.BASE_MAX_STAMINA * 3.0
		),
		"temporary END capacity is exactly tripled at the authoritative source"
	)
	_expect(
		sprint_seconds * ServerPlayer.RUN_SPEED
		> LAYOUT.WORLD_POSITION.length(),
		"the temporary END budget can carry one uninterrupted run from the yard to the maze"
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", message)
		return
	failure_count += 1
	push_error("[FAIL] %s" % message)
