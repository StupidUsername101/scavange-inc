extends SceneTree

const STEP := 1.0 / 60.0
const EPSILON := 0.00001
const CRITICAL_SPRING := preload(
	"res://scripts/characters/critically_damped_vector3.gd"
)

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_critical_spring_frame_rate_stability()
	_test_deterministic_idle_expression()
	_test_locomotion_and_legless_motion()
	_test_missing_limb_masks()
	_test_additive_action_pose()
	_test_network_clock_contract()
	if failure_count == 0:
		print(
			"Player character pose tests passed: %d assertions"
			% assertion_count
		)
		quit(0)
	else:
		push_error(
			"Player character pose tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_critical_spring_frame_rate_stability() -> void:
	var sixty_hz := CRITICAL_SPRING.new()
	var thirty_hz := CRITICAL_SPRING.new()
	var target := Vector3(1.0, -0.5, 0.25)
	for _frame: int in range(60):
		sixty_hz.advance(target, 1.0 / 60.0, 4.5)
	for _frame: int in range(30):
		thirty_hz.advance(target, 1.0 / 30.0, 4.5)
	_expect(
		sixty_hz.value.distance_to(thirty_hz.value) < EPSILON
		and sixty_hz.value.x <= target.x + EPSILON
		and sixty_hz.value.y >= target.y - EPSILON,
		"the shared critical spring is frame-rate stable and reaches a pose without overshoot"
	)


func _test_deterministic_idle_expression() -> void:
	var first := PlayerCharacterPoseController.new()
	var second := PlayerCharacterPoseController.new()
	var different_character := PlayerCharacterPoseController.new()
	first.set_expression_identity(17)
	second.set_expression_identity(17)
	different_character.set_expression_identity(18)
	for frame: int in range(180):
		var clock := float(frame) * STEP
		_update_idle(first, clock, true, true)
		_update_idle(second, clock, true, true)
		_update_idle(different_character, clock, true, true)
	_expect(
		first.upper_body_position.distance_to(second.upper_body_position) < EPSILON
		and first.upper_body_rotation.distance_to(second.upper_body_rotation) < EPSILON
		and first.camera_position.distance_to(second.camera_position) < EPSILON,
		"the same replicated clock and player identity produce the same pose on every peer"
	)
	_expect(
		first.upper_body_position.length() > 0.0001
		and first.upper_body_position.length() < 0.02
		and first.upper_body_rotation.length() < 0.04,
		"an idle character breathes and shifts weight subtly instead of freezing"
	)
	_expect(
		first.upper_body_position.distance_to(
			different_character.upper_body_position
		) > 0.0001,
		"identity-seeded nonlinear phase offsets prevent synchronized clone motion"
	)


func _test_locomotion_and_legless_motion() -> void:
	var biped := PlayerCharacterPoseController.new()
	biped.set_expression_identity(9)
	for frame: int in range(90):
		biped.update(
			STEP,
			float(frame) * STEP,
			2.25 + float(frame) * 0.016,
			1.0,
			0.0,
			0.0,
			Vector3(0.0, 0.0, -ServerPlayer.WALK_SPEED),
			true,
			false,
			null,
			true,
			true,
			true,
			true
		)
	_expect(
		biped.camera_position.length() > 0.004
		and absf(biped.left_arm_rotation.x) > 0.02
		and biped.left_arm_rotation.x * biped.right_arm_rotation.x < 0.0,
		"locomotion drives the camera, torso, and opposing arms from one shared phase"
	)

	var legless := PlayerCharacterPoseController.new()
	legless.set_expression_identity(9)
	var maximum_arm_crawl := 0.0
	var maximum_body_crawl := 0.0
	for frame: int in range(90):
		legless.update(
			STEP,
			float(frame) * STEP,
			4.4 + float(frame) * 0.018,
			1.0,
			0.0,
			0.0,
			Vector3(0.0, 0.0, -ServerPlayer.WALK_SPEED * 0.2),
			true,
			false,
			null,
			true,
			true,
			false,
			false
		)
		maximum_arm_crawl = maxf(
			maximum_arm_crawl,
			absf(legless.left_arm_rotation.x)
		)
		maximum_body_crawl = maxf(
			maximum_body_crawl,
			legless.upper_body_position.length()
		)
	_expect(
		maximum_arm_crawl > PlayerCharacterPoseController.WALK_ARM_SWING
		and maximum_body_crawl > 0.005,
		"a legless loadout retains independent rhythmic arm-crawl and torso motion"
	)


func _test_missing_limb_masks() -> void:
	var controller := PlayerCharacterPoseController.new()
	controller.set_expression_identity(31)
	for frame: int in range(80):
		controller.update(
			STEP,
			float(frame) * STEP,
			8.0 + float(frame) * 0.02,
			1.0,
			0.0,
			0.3,
			Vector3(0.0, 0.0, -1.0),
			true,
			false,
			null,
			true,
			false,
			false,
			false
		)
	_expect(
		controller.left_arm_rotation.length() > 0.02
		and controller.right_arm_rotation.length() < EPSILON,
		"procedural motion uses the surviving arm without animating a phantom limb"
	)


func _test_additive_action_pose() -> void:
	var pose := CharacterPoseDefinition.new()
	pose.pose_id = &"test_emote"
	pose.procedural_inheritance = 0.25
	pose.upper_body_weight = 1.0
	pose.upper_body_rotation = Vector3(0.12, -0.08, 0.04)
	pose.left_arm_weight = 1.0
	pose.left_arm_rotation = Vector3(0.9, 0.0, 0.7)
	pose.right_arm_weight = 1.0
	pose.right_arm_rotation = Vector3(0.9, 0.0, -0.7)
	var controller := PlayerCharacterPoseController.new()
	controller.set_expression_identity(5)
	controller.set_action_pose(pose, 1.0, true, false)
	for frame: int in range(90):
		controller.update(
			STEP,
			float(frame) * STEP,
			12.0 + float(frame) * 0.015,
			1.0,
			0.0,
			0.0,
			Vector3(0.0, 0.0, -ServerPlayer.WALK_SPEED),
			true,
			false,
			null,
			true,
			true,
			true,
			true
		)
	_expect(
		controller.upper_body_rotation.distance_to(pose.upper_body_rotation) < 0.08
		and controller.left_arm_rotation.distance_to(pose.left_arm_rotation) < 0.12
		and controller.right_arm_rotation.distance_to(pose.right_arm_rotation) > 0.25,
		"authored poses filter individual channels while procedural balance continues underneath"
	)


func _test_network_clock_contract() -> void:
	var server_player := preload(
		"res://scenes/server/server_player.tscn"
	).instantiate() as ServerPlayer
	root.add_child(server_player)
	server_player.player_id = 81
	server_player.expression_clock = 42.75
	server_player.wrist_interface_open = true
	server_player.wrist_display_page = &"scanner"
	var snapshot := server_player.to_state_dict()
	_expect(
		is_equal_approx(float(snapshot.get("expression_clock", -1.0)), 42.75)
		and snapshot.get("wrist_interface_open") == true
		and snapshot.get("wrist_display_page") == &"scanner",
		"late-join snapshots replicate expression time and the currently authored interaction pose"
	)
	var proxy := preload("res://scenes/proxy/player_proxy.tscn").instantiate() as PlayerProxy
	root.add_child(proxy)
	proxy.apply_server_state(snapshot)
	_expect(
		proxy.player_id == 81
		and is_equal_approx(proxy.target_expression_clock, 42.75)
		and proxy.target_wrist_interface_open,
		"joining clients consume the same clock and action state used by host presentation"
	)
	proxy.free()
	server_player.free()


func _update_idle(
	controller: PlayerCharacterPoseController,
	clock: float,
	has_left_arm: bool,
	has_right_arm: bool
) -> void:
	controller.update(
		STEP,
		clock,
		0.5,
		0.0,
		0.0,
		0.0,
		Vector3.ZERO,
		true,
		false,
		null,
		has_left_arm,
		has_right_arm,
		true,
		true
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] " + message)
		return
	failure_count += 1
	push_error("FAIL: " + message)
