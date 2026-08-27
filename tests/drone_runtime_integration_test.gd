extends SceneTree

const TEST_PLAYER_ID := 91001
const TEST_DURATION_SECONDS := 16.0
const HOLD_CHECK_SECONDS := 2.5
const FOLLOW_START_SECONDS := 3.0
const RELOCATION_SECONDS := 8.0
const RECOVERY_CHECK_SECONDS := 15.0

#######################################################
# Runs headless regression coverage for drone runtime integration behavior and reports
# contract or integration failures.
#######################################################

var test_root: Node3D
var player: ServerPlayer
var drone: ServerDrone
var enemy: ServerEnemy
var initial_hold_position := Vector3.ZERO
var elapsed := 0.0
var failure_count := 0
var hold_checked := false
var follow_started := false
var relocated := false
var recovery_checked := false
var saw_static_avoidance := false


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	test_root = Node3D.new()
	test_root.name = "DroneRuntimeTestWorld"
	root.add_child(test_root)

	var air := AirEnvironment.new()
	air.name = "AirEnvironment"
	test_root.add_child(air)
	_add_ground()
	_add_relocation_obstacle()
	_add_player()
	_add_enemy()
	_add_drone()
	physics_frame.connect(_on_physics_frame)


func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	ground.add_child(collision)
	test_root.add_child(ground)


func _add_relocation_obstacle() -> void:
	var wall := StaticBody3D.new()
	wall.name = "RelocationObstacle"
	wall.position = Vector3(12.0, 3.0, 2.5)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.65, 6.0, 6.0)
	collision.shape = shape
	wall.add_child(collision)
	test_root.add_child(wall)


func _add_player() -> void:
	var scene := load(
		"res://scenes/server/server_player.tscn"
	) as PackedScene
	player = scene.instantiate() as ServerPlayer
	test_root.add_child(player)
	player.setup(TEST_PLAYER_ID, Vector3(0.0, 1.0, 0.0))
	var server := root.get_node_or_null("Server")
	if server != null:
		(server.get("server_players_by_player_id") as Dictionary)[TEST_PLAYER_ID] = player


func _add_enemy() -> void:
	var scene := load(
		"res://scenes/server/server_enemy.tscn"
	) as PackedScene
	var definition := load(
		"res://resources/enemies/stationary_dummy.tres"
	) as EnemyDefinition
	enemy = scene.instantiate() as ServerEnemy
	enemy.configure(definition, -1)
	enemy.position = Vector3(0.0, 0.0, -8.0)
	test_root.add_child(enemy)
	enemy.set_active(true)


func _add_drone() -> void:
	var scene := load(
		"res://scenes/server/server_drone.tscn"
	) as PackedScene
	var reference_loadout := load(
		"res://resources/drones/loadouts/perfect_combat_follow_quad.tres"
	) as DroneLoadout
	drone = scene.instantiate() as ServerDrone
	drone.loadout = reference_loadout
	drone.starts_activated = true
	drone.position = Vector3(5.1, 3.8, 0.0)
	initial_hold_position = drone.position
	test_root.add_child(drone)


func _on_physics_frame() -> void:
	elapsed += 1.0 / float(Engine.physics_ticks_per_second)
	if (
		drone != null
		and drone.ai_controller != null
		and bool(drone.ai_controller.combined_intent.get(
			"static_avoidance_active",
			false
		))
	):
		saw_static_avoidance = true
	if not hold_checked and elapsed >= HOLD_CHECK_SECONDS:
		hold_checked = true
		_expect(
			drone.global_position.distance_to(initial_hold_position) < 0.25,
			"reference drone holds position while the gunner is active"
		)
		_expect(drone.linear_velocity.length() < 0.35, "hover velocity settles")
		_expect(
			drone.global_basis.y.normalized().dot(Vector3.UP) > 0.985,
			"hover attitude stays upright"
		)
		_expect(
			not is_instance_valid(enemy) or enemy.current_health < 120.0,
			"reference drone can fire while holding position"
		)

	if not follow_started and elapsed >= FOLLOW_START_SECONDS:
		follow_started = true
		drone.set_ai_follow_player(TEST_PLAYER_ID)

	if not relocated and elapsed >= RELOCATION_SECONDS:
		relocated = true
		player.global_position = Vector3(20.0, 1.0, 5.0)
		player.velocity = Vector3.ZERO

	if not recovery_checked and elapsed >= RECOVERY_CHECK_SECONDS:
		recovery_checked = true
		var chip := load(
			"res://resources/drones/ai_chips/shepherd_follow_chip.tres"
		) as DroneAIChipDefinition
		var offset := drone.global_position - player.global_position
		var horizontal_radius := Vector2(offset.x, offset.z).length()
		_expect(
			horizontal_radius >= chip.get_follow_inner_radius() - 0.35
			and horizontal_radius <= chip.get_follow_outer_radius() + 0.35,
			"drone reacquires the follow annulus after relocation"
		)
		_expect(
			absf(offset.y - chip.get_follow_height_offset()) < 0.5,
			"drone recovers follow altitude"
		)
		_expect(
			drone.global_basis.y.normalized().dot(Vector3.UP) > 0.94,
			"recovery does not leave the drone on its head"
		)
		_expect(
			drone.global_position.y > 2.4,
			"recovery maintains ground clearance"
		)
		_expect(
			saw_static_avoidance,
			"shared navigation detects and steers around the relocation wall"
		)

	if elapsed >= TEST_DURATION_SECONDS:
		_finish()


func _finish() -> void:
	if physics_frame.is_connected(_on_physics_frame):
		physics_frame.disconnect(_on_physics_frame)
	var server := root.get_node_or_null("Server")
	if server != null:
		(server.get("server_players_by_player_id") as Dictionary).erase(TEST_PLAYER_ID)
	if failure_count == 0:
		print("Drone runtime integration test passed")
		quit(0)
	else:
		push_error(
			"Drone runtime integration test failed: %d assertions" % failure_count
		)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("FAIL: %s" % description)
