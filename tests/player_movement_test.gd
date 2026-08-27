extends SceneTree

const STEP := 1.0 / 60.0
const EPSILON := 0.0001
const FULL_BODY := preload(
	"res://resources/character_loadouts/full_body.tres"
)
const INDUSTRIAL_COMPLEX_SCENE := preload(
	"res://scenes/server/industrial_acoustic_complex.tscn"
)
const ACOUSTIC_HOUSE_SCENE := preload(
	"res://scenes/server/acoustic_test_house.tscn"
)

class RecordingServerPlayer:
	extends ServerPlayer

	var emitted_sound_ids: Array[StringName] = []

	func _emit_gameplay_sound(
		sound_id: StringName,
		_max_distance: float,
		_priority: float
	) -> void:
		emitted_sound_ids.append(sound_id)


var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ground_acceleration_and_braking()
	_test_airborne_momentum_and_control()
	_test_wall_collision_velocity()
	_test_shared_gait_clock()
	_test_authoritative_jump_arc()
	await _test_authoritative_step_traversal()
	await _test_authored_entrance_traversal()
	_finish()


func _test_ground_acceleration_and_braking() -> void:
	_expect(
		ServerPlayer.WALK_SPEED < ServerPlayer.RUN_SPEED * 0.55,
		"normal walking keeps a deliberate pace distinct from sprinting"
	)
	var velocity := ServerPlayer.calculate_horizontal_velocity(
		Vector3.ZERO,
		Vector3.FORWARD,
		ServerPlayer.WALK_SPEED,
		true,
		STEP
	)
	_expect(
		velocity.length() > 0.0
		and velocity.length() < ServerPlayer.WALK_SPEED,
		"ground movement accelerates instead of snapping to full speed"
	)
	for _step: int in range(30):
		velocity = ServerPlayer.calculate_horizontal_velocity(
			velocity,
			Vector3.FORWARD,
			ServerPlayer.WALK_SPEED,
			true,
			STEP
		)
	_expect(
		is_equal_approx(velocity.length(), ServerPlayer.WALK_SPEED),
		"sustained ground input reaches the authored walk speed"
	)
	var braking := ServerPlayer.calculate_horizontal_velocity(
		velocity,
		Vector3.ZERO,
		ServerPlayer.WALK_SPEED,
		true,
		STEP
	)
	_expect(
		braking.length() > 0.0 and braking.length() < velocity.length(),
		"releasing ground input brakes progressively instead of stopping instantly"
	)


func _test_airborne_momentum_and_control() -> void:
	var takeoff_velocity := Vector3(13.5, 4.0, -2.75)
	var coasting := ServerPlayer.calculate_horizontal_velocity(
		takeoff_velocity,
		Vector3.ZERO,
		ServerPlayer.WALK_SPEED,
		false,
		STEP
	)
	_expect(
		coasting.is_equal_approx(Vector3(13.5, 0.0, -2.75)),
		"an airborne player preserves horizontal takeoff momentum without input"
	)

	var fast_takeoff := Vector3(18.0, 0.0, 0.0)
	var holding_forward := ServerPlayer.calculate_horizontal_velocity(
		fast_takeoff,
		Vector3.RIGHT,
		ServerPlayer.WALK_SPEED,
		false,
		STEP
	)
	_expect(
		holding_forward.is_equal_approx(fast_takeoff),
		"air control does not clamp carried momentum down to normal movement speed"
	)

	var steered := ServerPlayer.calculate_horizontal_velocity(
		Vector3(ServerPlayer.RUN_SPEED, 0.0, 0.0),
		Vector3.FORWARD,
		ServerPlayer.RUN_SPEED,
		false,
		STEP
	)
	_expect(
		steered.z < 0.0
		and steered.length() <= ServerPlayer.RUN_SPEED + EPSILON,
		"limited air steering changes heading without creating extra speed"
	)

	var opposed := ServerPlayer.calculate_horizontal_velocity(
		Vector3(ServerPlayer.RUN_SPEED, 0.0, 0.0),
		Vector3.LEFT,
		ServerPlayer.RUN_SPEED,
		false,
		STEP
	)
	_expect(
		opposed.x > 0.0 and opposed.x < ServerPlayer.RUN_SPEED,
		"opposite air input cannot reverse momentum in a single frame"
	)


func _test_wall_collision_velocity() -> void:
	var slid := ServerPlayer.horizontal_velocity_after_wall_collision(
		Vector3(-8.0, 4.0, 3.0),
		Vector3.RIGHT
	)
	_expect(
		is_zero_approx(slid.x)
		and is_equal_approx(slid.y, 4.0)
		and is_equal_approx(slid.z, 3.0),
		"wall impacts shed only the blocked momentum and preserve the tangent"
	)
	var separating := ServerPlayer.horizontal_velocity_after_wall_collision(
		Vector3(2.0, -1.0, 3.0),
		Vector3.RIGHT
	)
	_expect(
		separating.is_equal_approx(Vector3(2.0, -1.0, 3.0)),
		"a wall normal never removes velocity already moving away from it"
	)


func _test_shared_gait_clock() -> void:
	var gait := PlayerGait.new()
	var frames_to_first_step := 0
	var first_step_count := 0
	while first_step_count == 0 and frames_to_first_step < 120:
		frames_to_first_step += 1
		first_step_count = gait.advance(
			ServerPlayer.WALK_SPEED,
			true,
			false,
			STEP
		)
	_expect(
		first_step_count == 1
		and frames_to_first_step >= 18
		and gait.active
		and gait.get_phase() < 0.05,
		"movement gets half a settling stride before its first shared footfall"
	)

	var frames_to_next_step := 0
	var next_step_count := 0
	while next_step_count == 0 and frames_to_next_step < 120:
		frames_to_next_step += 1
		next_step_count = gait.advance(
			ServerPlayer.WALK_SPEED,
			true,
			false,
			STEP
		)
	_expect(
		next_step_count == 1
		and frames_to_next_step >= 38,
		"the slower walk cycle waits for shared stride distance instead of a fast visual timer"
	)

	var impact_offset := PlayerGait.calculate_bob_offset(2.0, 0.04, 0.02)
	var high_offset := PlayerGait.calculate_bob_offset(2.5, 0.04, 0.02)
	var before_boundary := PlayerGait.calculate_bob_offset(
		2.9999,
		0.04,
		0.02
	)
	var after_boundary := PlayerGait.calculate_bob_offset(3.0, 0.04, 0.02)
	_expect(
		impact_offset.y < 0.0
		and high_offset.y > 0.0,
		"camera bob reaches its low point on the footstep and rises halfway to the next one"
	)
	_expect(
		before_boundary.distance_to(after_boundary) < 0.001,
		"alternating lateral sway remains continuous when the planted foot changes"
	)

	var phase_before_run := gait.get_phase()
	gait.advance(0.0, true, true, 0.0)
	_expect(
		is_equal_approx(gait.get_phase(), phase_before_run)
		and is_equal_approx(
			gait.stride_distance,
			PlayerGait.RUN_STEP_DISTANCE
		),
		"changing between walk and run preserves gait phase while changing stride length"
	)
	_expect(
		PlayerGait.WALK_STEP_DISTANCE / ServerPlayer.WALK_SPEED > 0.7
		and PlayerGait.RUN_STEP_DISTANCE / ServerPlayer.RUN_SPEED > 0.23
		and PlayerGait.RUN_STEP_DISTANCE / ServerPlayer.RUN_SPEED < 0.27
		and ServerPlayer.RUN_SPEED / PlayerGait.RUN_STEP_DISTANCE
		> ServerPlayer.WALK_SPEED / PlayerGait.WALK_STEP_DISTANCE * 2.5
		and ServerPlayer.RUN_SPEED / PlayerGait.RUN_STEP_DISTANCE
		< ServerPlayer.WALK_SPEED / PlayerGait.WALK_STEP_DISTANCE * 3.5,
		"sprint keeps a fast but human-readable quarter-second synchronized cadence"
	)
	var run_impact := PlayerGait.calculate_run_bob_offset(2.0, 0.04, 0.026)
	var run_flight := PlayerGait.calculate_run_bob_offset(2.5, 0.04, 0.026)
	var run_before_boundary := PlayerGait.calculate_run_bob_offset(
		2.9999,
		0.04,
		0.026
	)
	var run_after_boundary := PlayerGait.calculate_run_bob_offset(
		3.0,
		0.04,
		0.026
	)
	_expect(
		run_impact.y < 0.0
		and run_flight.y > 0.0
		and absf(run_impact.y) < 0.03
		and run_flight.y < 0.02,
		"sprint uses restrained landing compression and flight instead of a faster walk pogo"
	)
	_expect(
		run_before_boundary.distance_to(run_after_boundary) < 0.001,
		"sprint compression and lateral transfer remain continuous at each footfall"
	)

	var server_player := RecordingServerPlayer.new()
	server_player.velocity = Vector3(ServerPlayer.WALK_SPEED, 0.0, 0.0)
	server_player.on_floor = true
	server_player.gait.distance_since_step = (
		server_player.gait.stride_distance
		- ServerPlayer.WALK_SPEED * STEP * 0.5
	)
	server_player.call("_update_footsteps", STEP)
	var server_cycle := server_player.gait.get_cycle()
	var server_impact := PlayerGait.calculate_bob_offset(
		server_cycle,
		0.04,
		0.02
	)
	_expect(
		server_player.emitted_sound_ids == [&"footstep_concrete"]
		and server_impact.y < -0.039,
		"the authoritative footstep event and replicated camera cycle meet at impact"
	)
	server_player.free()


func _test_authoritative_jump_arc() -> void:
	var player := RecordingServerPlayer.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	player.add_child(collision)
	var grabber := GrabberComponent.new()
	grabber.name = "Grabber"
	grabber.capability = GrabCapability.new()
	player.add_child(grabber)
	player.body_loadout = FULL_BODY
	root.add_child(player)

	var carried_velocity := Vector3(12.0, 0.0, -3.5)
	player.velocity = carried_velocity
	player.on_floor = true
	player.request_jump()
	player.server_physics_tick(STEP)
	_expect(
		is_equal_approx(player.velocity.x, carried_velocity.x)
		and is_equal_approx(player.velocity.z, carried_velocity.z)
		and is_equal_approx(player.velocity.y, ServerPlayer.JUMP_VELOCITY),
		"the authoritative takeoff tick carries existing horizontal momentum"
	)
	_expect(
		player.emitted_sound_ids == [&"jump_concrete"],
		"momentum-preserving takeoff still emits exactly one jump cue"
	)
	var public_state := player.to_state_dict()
	_expect(
		public_state.has("gait_cycle")
		and public_state.has("gait_stride_distance")
		and public_state.has("gait_active")
		and is_equal_approx(float(public_state.get("stamina_ratio", -1.0)), 1.0),
		"authoritative movement snapshots replicate the shared gait clock and END ratio"
	)

	var launch_horizontal := Vector2(player.velocity.x, player.velocity.z)
	player.server_physics_tick(STEP)
	_expect(
		Vector2(player.velocity.x, player.velocity.z).is_equal_approx(
			launch_horizontal
		)
		and is_equal_approx(
			player.velocity.y,
			ServerPlayer.JUMP_VELOCITY - ServerPlayer.GRAVITY * STEP
		),
		"airborne simulation uses a stable ballistic arc without erasing momentum"
	)
	player.free()


func _test_authoritative_step_traversal() -> void:
	var floor_body := _add_static_box(
		"StepTestFloor",
		Vector3(12.0, 0.2, 5.0),
		Vector3(0.0, -0.1, 0.0)
	)
	var curb_body := _add_static_box(
		"FiveCentimeterCurb",
		Vector3(4.0, 0.05, 1.5),
		Vector3(2.0, 0.025, -1.25)
	)
	var wall_body := _add_static_box(
		"UnclimbableWall",
		Vector3(1.0, 1.0, 1.5),
		Vector3(0.5, 0.5, 1.25)
	)
	var curb_player := _make_physics_player(
		Vector3(-1.1, ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5, -1.25)
	)
	var wall_player := _make_physics_player(
		Vector3(-1.1, ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5, 1.25)
	)
	await physics_frame
	curb_player.on_floor = true
	wall_player.on_floor = true
	for _tick: int in range(36):
		curb_player.set_input(Vector2.RIGHT, 0.0, 0.0, false)
		wall_player.set_input(Vector2.RIGHT, 0.0, 0.0, false)
		curb_player.server_physics_tick(STEP)
		wall_player.server_physics_tick(STEP)
	_expect(
		curb_player.global_position.x > 0.6
		and absf(
			curb_player.global_position.y
			- (ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5 + 0.05)
		) < 0.015,
		"grounded movement crosses a five-centimeter curb without losing forward travel"
	)
	_expect(
		wall_player.global_position.x < -0.45
		and absf(
			wall_player.global_position.y
			- ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5
		) < 0.015,
		"the same solver cannot convert a full-height wall into a climbable step"
	)
	curb_player.free()
	wall_player.free()
	floor_body.free()
	curb_body.free()
	wall_body.free()


func _test_authored_entrance_traversal() -> void:
	var outside_floor := _add_static_box(
		"EntranceTestOutsideFloor",
		Vector3(120.0, 0.2, 70.0),
		Vector3(0.0, -0.1, 5.0)
	)
	var complex := INDUSTRIAL_COMPLEX_SCENE.instantiate() as StaticBody3D
	root.add_child(complex)
	var house := ACOUSTIC_HOUSE_SCENE.instantiate() as StaticBody3D
	# Keep this independent entrance fixture clear of the three parallel bunker runs.
	house.position = Vector3(-25.0, 0.0, 0.0)
	root.add_child(house)

	var standing_y := ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5
	var tunnel_player := _make_physics_player(
		Vector3(11.0, standing_y, -13.4)
	)
	var wide_tunnel_player := _make_physics_player(
		Vector3(28.0, standing_y, -13.4)
	)
	var hangar_tunnel_player := _make_physics_player(
		Vector3(47.0, standing_y, -13.4)
	)
	var building_player := _make_physics_player(
		Vector3(-10.3, standing_y, 0.6)
	)
	var house_player := _make_physics_player(
		Vector3(-25.0, standing_y, 4.2)
	)
	await physics_frame
	for player: ServerPlayer in [
		tunnel_player,
		wide_tunnel_player,
		hangar_tunnel_player,
		building_player,
		house_player,
	]:
		player.on_floor = true
	for _tick: int in range(42):
		tunnel_player.set_input(Vector2.DOWN, 0.0, 0.0, false)
		wide_tunnel_player.set_input(Vector2.DOWN, 0.0, 0.0, false)
		hangar_tunnel_player.set_input(Vector2.DOWN, 0.0, 0.0, false)
		building_player.set_input(Vector2.DOWN, 0.0, 0.0, false)
		house_player.set_input(Vector2.UP, 0.0, 0.0, false)
		tunnel_player.server_physics_tick(STEP)
		wide_tunnel_player.server_physics_tick(STEP)
		hangar_tunnel_player.server_physics_tick(STEP)
		building_player.server_physics_tick(STEP)
		house_player.server_physics_tick(STEP)

	var slab_height := standing_y + 0.12
	_expect(
		tunnel_player.global_position.z > -11.5
		and wide_tunnel_player.global_position.z > -11.5
		and hangar_tunnel_player.global_position.z > -11.5
		and absf(tunnel_player.global_position.y - standing_y) < 0.02,
		"all three authored tunnel lips are walkable from the outside world"
	)
	_expect(
		building_player.global_position.z > 2.5
		and absf(building_player.global_position.y - slab_height) < 0.02,
		"the multistorey building doorway no longer blocks ordinary walking"
	)
	_expect(
		house_player.global_position.z < 2.4
		and absf(house_player.global_position.y - slab_height) < 0.02,
		"the acoustic test house threshold is traversable without jumping"
	)
	tunnel_player.free()
	wide_tunnel_player.free()
	hangar_tunnel_player.free()
	building_player.free()
	house_player.free()
	house.free()
	complex.free()
	outside_floor.free()


func _make_physics_player(spawn_position: Vector3) -> ServerPlayer:
	var player := ServerPlayer.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, ServerPlayer.STANDING_COLLISION_HEIGHT, 1.0)
	collision.shape = shape
	player.add_child(collision)
	var grabber := GrabberComponent.new()
	grabber.name = "Grabber"
	grabber.position = Vector3(0.0, 0.56, -0.42)
	grabber.capability = GrabCapability.new()
	player.add_child(grabber)
	player.body_loadout = FULL_BODY
	root.add_child(player)
	player.global_position = spawn_position
	return player


func _add_static_box(
	node_name: String,
	size: Vector3,
	box_position: Vector3
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	body.global_position = box_position
	return body


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", label)
		return
	failure_count += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print(
		"Player movement tests: ",
		assertion_count - failure_count,
		" passed, ",
		failure_count,
		" failed"
	)
	quit(0 if failure_count == 0 else 1)
