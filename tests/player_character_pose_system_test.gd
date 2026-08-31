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
	_test_dropkick_body_and_camera_pose()
	_test_directional_upper_body_lean()
	_test_momentum_recovery_pose()
	_test_environmental_impact_pose()
	_test_missing_limb_masks()
	_test_additive_action_pose()
	_test_flip_input_and_first_person_presentation()
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


func _test_dropkick_body_and_camera_pose() -> void:
	var first := PlayerCharacterPoseController.new()
	var peer_copy := PlayerCharacterPoseController.new()
	var next_kick := PlayerCharacterPoseController.new()
	var right_curve := PlayerCharacterPoseController.new()
	var left_curve := PlayerCharacterPoseController.new()
	for controller: PlayerCharacterPoseController in [
		first,
		peer_copy,
		next_kick,
		right_curve,
		left_curve,
	]:
		controller.set_expression_identity(14)
	controller_set_dropkick(first, 8)
	controller_set_dropkick(peer_copy, 8)
	controller_set_dropkick(next_kick, 9)
	controller_set_dropkick(right_curve, 10, 1.0)
	controller_set_dropkick(left_curve, 10, -1.0)
	for frame: int in range(42):
		for controller: PlayerCharacterPoseController in [
			first,
			peer_copy,
			next_kick,
			right_curve,
			left_curve,
		]:
			controller.update(
				STEP,
				float(frame) * STEP,
				3.0,
				1.0,
				1.0,
				0.0,
				Vector3(0.0, 2.0, -ServerPlayer.RUN_SPEED),
				false,
				false,
				null,
				true,
				true,
				true,
				true
			)
	_expect(
		first.body_rotation.x > 0.45
		and first.body_rotation.z < -1.20
		and first.body_rotation.z > -1.70
		and first.upper_body_rotation.x > 0.06
		and first.left_arm_rotation.z * first.right_arm_rotation.z < 0.0
		and first.camera_rotation.x < -0.08
		and first.camera_rotation.x > -0.31
		and first.camera_rotation.z < -0.18
		and first.camera_rotation.z > -0.62,
		"dropkick presentation reclines and rolls the complete body near-sideways, opens both arms, and gives the camera restrained pitch and roll inheritance"
	)
	_expect(
		first.body_rotation.distance_to(
			peer_copy.body_rotation
		) < EPSILON
		and first.left_arm_rotation.distance_to(
			peer_copy.left_arm_rotation
		) < EPSILON
		and first.body_rotation.distance_to(
			next_kick.body_rotation
		) > 0.004,
		"dropkick asymmetry is deterministic for observers but changes across successive kick sequences"
	)
	_expect(
		right_curve.body_rotation.z < -1.20
		and left_curve.body_rotation.z > 1.20
		and right_curve.camera_rotation.z < -0.18
		and left_curve.camera_rotation.z > 0.18
		and absf(
			right_curve.body_rotation.x - left_curve.body_rotation.x
		) < 0.04,
		"opposite lateral camera curves mirror the complete dropkick and its restrained first-person roll without changing the feet-forward recline"
	)
	# Root roll moves the real head mount sideways around the pelvis. The camera must remain at that
	# anatomical eye instead of translating through the torso; a mirrored yaw correction aims toward
	# the paired feet. Authored mouse curves retain a little framing yield.
	var representative_eye_height := 0.56
	var representative_aim_distance := 1.25
	var neutral_screen_lateral := dropkick_projected_lateral_error(
		first,
		representative_eye_height,
		representative_aim_distance
	)
	var right_curve_screen_lateral := dropkick_projected_lateral_error(
		right_curve,
		representative_eye_height,
		representative_aim_distance
	)
	var left_curve_screen_lateral := dropkick_projected_lateral_error(
		left_curve,
		representative_eye_height,
		representative_aim_distance
	)
	_expect(
		absf(first.camera_position.x) < 0.08
		and first.camera_position.z < -0.005
		and absf(neutral_screen_lateral) < 0.035
		and right_curve_screen_lateral < -0.015
		and right_curve_screen_lateral > -0.18
		and left_curve_screen_lateral > 0.015
		and left_curve_screen_lateral < 0.18
		and absf(
			absf(right_curve_screen_lateral)
			- absf(left_curve_screen_lateral)
		) < 0.035,
		(
			"a dropkick keeps the camera at the eye, safely forward of the chest, while gaze—not torso-crossing translation—centres the feet with mirrored gesture yield: position=%s neutral=%.4f right=%.4f left=%.4f"
			% [
				first.camera_position,
				neutral_screen_lateral,
				right_curve_screen_lateral,
				left_curve_screen_lateral,
			]
		)
	)
	var proxy := preload("res://scenes/proxy/player_proxy.tscn").instantiate() as PlayerProxy
	root.add_child(proxy)
	proxy.character_pose.body_rotation = first.body_rotation
	proxy.call("_apply_body_visual_rotation")
	_expect(
		proxy.body_visual.rotation.is_equal_approx(first.body_rotation)
		and absf(proxy.body_visual.global_basis.x.normalized().x) < 0.20
		and absf(proxy.body_visual.global_basis.x.normalized().y) > 0.65,
		"the replicated dropkick root pose rolls the complete authored body so its lateral leg axis becomes predominantly vertical instead of horizontal"
	)
	proxy.free()

	var rolling := PlayerCharacterPoseController.new()
	rolling.set_expression_identity(14)
	rolling.set_low_priority_kick_pose(
		PlayerGait.FootSide.RIGHT,
		0.0,
		1.55,
		ServerPlayer.KickStyle.DROP,
		12,
		true
	)
	rolling.update(
		STEP,
		0.0,
		3.0,
		1.0,
		1.0,
		0.0,
		Vector3(0.0, 2.0, -ServerPlayer.RUN_SPEED),
		false,
		false,
		null,
		true,
		true,
		true,
		true
	)
	var previous_roll := rolling.body_rotation.z
	var maximum_roll_step := 0.0
	for frame: int in range(24):
		var phase := float(frame + 1) / 24.0
		rolling.set_low_priority_kick_pose(
			PlayerGait.FootSide.RIGHT,
			phase,
			1.55,
			ServerPlayer.KickStyle.DROP,
			12,
			true
		)
		rolling.update(
			STEP,
			float(frame + 1) * STEP,
			3.0,
			1.0,
			1.0,
			0.0,
			Vector3(0.0, 2.0, -ServerPlayer.RUN_SPEED),
			false,
			false,
			null,
			true,
			true,
			true,
			true
		)
		maximum_roll_step = maxf(
			maximum_roll_step,
			absf(rolling.body_rotation.z - previous_roll)
		)
		previous_roll = rolling.body_rotation.z
	_expect(
		rolling.body_rotation.z < -0.90
		and maximum_roll_step < 0.20,
		"dropkick root roll develops smoothly during the opening moments instead of snapping or gluing the body to a fixed angle"
	)


func controller_set_dropkick(
	controller: PlayerCharacterPoseController,
	sequence: int,
	tilt_input := 0.0
) -> void:
	controller.set_low_priority_kick_pose(
		PlayerGait.FootSide.RIGHT,
		1.0,
		1.55,
		ServerPlayer.KickStyle.DROP,
		sequence,
		true,
		tilt_input
	)


func dropkick_projected_lateral_error(
	controller: PlayerCharacterPoseController,
	eye_height: float,
	aim_distance: float
) -> float:
	var eye_lateral := (
		-sin(controller.body_rotation.z) * eye_height
		+ controller.camera_position.x
	)
	var to_impact := Vector3(-eye_lateral, 0.0, -aim_distance)
	var camera_space := Basis.from_euler(
		Vector3(0.0, controller.camera_rotation.y, 0.0)
	).inverse() * to_impact
	return camera_space.x / maxf(-camera_space.z, 0.001)


func _test_directional_upper_body_lean() -> void:
	var controller := PlayerCharacterPoseController.new()
	controller.set_expression_identity(22)
	var minimum_right_roll := 0.0
	for frame: int in range(36):
		controller.update(
			STEP,
			float(frame) * STEP,
			2.0,
			1.0,
			0.0,
			0.0,
			Vector3(ServerPlayer.WALK_SPEED, 0.0, 0.0),
			true,
			false,
			null,
			true,
			true,
			true,
			true
		)
		minimum_right_roll = minf(
			minimum_right_roll,
			controller.upper_body_rotation.z
		)
	var maximum_left_roll := 0.0
	for frame: int in range(36):
		controller.update(
			STEP,
			1.0 + float(frame) * STEP,
			2.0,
			1.0,
			0.0,
			0.0,
			Vector3(-ServerPlayer.WALK_SPEED, 0.0, 0.0),
			true,
			false,
			null,
			true,
			true,
			true,
			true
		)
		maximum_left_roll = maxf(
			maximum_left_roll,
			controller.upper_body_rotation.z
		)
	_expect(
		minimum_right_roll < deg_to_rad(-0.7)
		and maximum_left_roll > deg_to_rad(0.7),
		"sideways travel rolls the torso and shoulders in either direction rather than moving only hips and feet"
	)


func _test_momentum_recovery_pose() -> void:
	var controller := PlayerCharacterPoseController.new()
	controller.set_expression_identity(28)
	var minimum_height := INF
	var maximum_height := -INF
	for frame: int in range(72):
		var recovery_weight := 1.0 - float(frame) / 72.0
		controller.update(
			STEP,
			float(frame) * STEP,
			float(frame) * 0.045,
			1.0,
			recovery_weight * 0.78,
			0.0,
			Vector3.ZERO,
			true,
			false,
			null,
			true,
			true,
			true,
			true,
			recovery_weight
		)
		minimum_height = minf(minimum_height, controller.upper_body_position.y)
		maximum_height = maxf(maximum_height, controller.upper_body_position.y)
	_expect(
		maximum_height - minimum_height > 0.012,
		"momentum-shedding contacts remain visibly springy in the torso after horizontal speed reaches zero"
	)


func _test_environmental_impact_pose() -> void:
	var impacted := PlayerCharacterPoseController.new()
	var reference := PlayerCharacterPoseController.new()
	impacted.set_expression_identity(44)
	reference.set_expression_identity(44)
	_update_idle(impacted, 0.0, true, true)
	_update_idle(reference, 0.0, true, true)
	var reaction := Vector3(0.65, 0.0, 0.76).normalized()
	impacted.apply_body_impact(reaction, 1.0, 1.0)
	_update_idle(impacted, STEP, true, true)
	_update_idle(reference, STEP, true, true)
	var body_position_delta := (
		impacted.upper_body_position - reference.upper_body_position
	)
	var body_rotation_delta := (
		impacted.upper_body_rotation - reference.upper_body_rotation
	)
	var camera_rotation_delta := (
		impacted.camera_rotation - reference.camera_rotation
	)
	_expect(
		body_position_delta.dot(reaction) > 0.0005
		and body_rotation_delta.x > 0.001
		and body_rotation_delta.z < -0.001
		and camera_rotation_delta.x > 0.0005
		and camera_rotation_delta.z < -0.0005
		and impacted.upper_body_position.length()
		< PlayerCharacterPoseController.BODY_IMPACT_MAX_POSITION + 0.02,
		"a replicated shoulder contact displaces and twists the torso, head camera, and body along the experienced force"
	)
	for frame: int in range(1, 121):
		var clock := float(frame + 1) * STEP
		_update_idle(impacted, clock, true, true)
		_update_idle(reference, clock, true, true)
	_expect(
		impacted.upper_body_position.distance_to(reference.upper_body_position)
		< 0.001
		and impacted.upper_body_rotation.distance_to(
			reference.upper_body_rotation
		) < 0.001
		and impacted.camera_rotation.distance_to(reference.camera_rotation)
		< 0.001,
		"the environmental flinch returns smoothly to the ordinary procedural pose instead of leaving a camera offset"
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


func _test_flip_input_and_first_person_presentation() -> void:
	_expect(
		PlayerProxy.flip_intent_from_pitch_motion(
			deg_to_rad(10.0),
			STEP
		) == 1
		and PlayerProxy.flip_intent_from_pitch_motion(
			-deg_to_rad(10.0),
			STEP
		) == -1
		and PlayerProxy.flip_intent_from_pitch_motion(
			deg_to_rad(3.0),
			STEP
		) == 0
		and PlayerProxy.flip_intent_from_pitch_motion(
			deg_to_rad(10.0),
			0.05
		) == 0,
		"only a fast, deliberate pitch flick produces signed front/back flip intent"
	)
	_expect(
		PlayerProxy.dropkick_tilt_input_from_yaw_motion(
			-deg_to_rad(12.0)
		) > 0.55
		and PlayerProxy.dropkick_tilt_input_from_yaw_motion(
			deg_to_rad(12.0)
		) < -0.55
		and is_zero_approx(
			PlayerProxy.dropkick_tilt_input_from_yaw_motion(
				deg_to_rad(1.0)
			)
		),
		"a deliberate right/left mouse curve produces mirrored dropkick tilt input while ordinary aim noise remains neutral"
	)
	var proxy := preload(
		"res://scenes/proxy/player_proxy.tscn"
	).instantiate() as PlayerProxy
	root.add_child(proxy)
	proxy.is_local_player = true
	proxy.target_on_floor = true
	proxy.target_stamina_ratio = 1.0
	proxy.set_local_locomotion_input(Vector2(0.0, -1.0), true)
	for _sample: int in range(3):
		proxy._record_dropkick_tilt_motion(
			-deg_to_rad(4.0),
			1.0 / 120.0
		)
	_expect(
		proxy.consume_dropkick_tilt_input() > 0.55
		and is_zero_approx(proxy.consume_dropkick_tilt_input()),
		"lateral mouse motion accumulates only inside one short gesture and is consumed exactly once by dropkick commitment"
	)
	var partial_flick_pitch := deg_to_rad(4.0)
	for _sample: int in range(3):
		proxy._record_flip_pitch_motion(
			partial_flick_pitch,
			1.0 / 120.0
		)
	_expect(
		proxy.consume_buffered_flip_intent() == 1,
		"a fast flick spread over several input samples is accumulated inside one short gesture window"
	)
	var slow_pitch_delta := deg_to_rad(1.0)
	for _sample: int in range(30):
		proxy._record_flip_pitch_motion(
			slow_pitch_delta,
			STEP
		)
	_expect(
		proxy.consume_buffered_flip_intent() == 0,
		"a long ordinary camera sweep cannot accumulate forever into a false flip gesture"
	)
	proxy.flip_flick_sample_remaining = 0.0
	proxy.flip_flick_accumulated_pitch = 0.0
	proxy.flip_flick_accumulated_elapsed = 0.0
	var flick_pixels := deg_to_rad(12.0) / proxy.mouse_sensitivity
	proxy._apply_mouse_look(
		Vector2(0.0, -flick_pixels),
		Vector2(0.0, -flick_pixels),
		STEP
	)
	proxy.advance_local_input_tick()
	proxy.advance_local_input_tick()
	_expect(
		proxy.consume_buffered_flip_intent() == 1
		and proxy.consume_buffered_flip_intent() == 0,
		"an upward flick remains consumable through exactly its second following fixed input tick"
	)
	proxy._apply_mouse_look(
		Vector2(0.0, -flick_pixels),
		Vector2(0.0, -flick_pixels),
		STEP
	)
	proxy.advance_local_input_tick()
	proxy.advance_local_input_tick()
	proxy.advance_local_input_tick()
	_expect(
		proxy.consume_buffered_flip_intent() == 0
		and not proxy.local_flip_prediction_active,
		"a jump after the two-frame gesture grace receives no intent and cannot begin a rejected cosmetic flip"
	)
	proxy.look_pitch = PlayerProxy.MAX_LOOK_PITCH
	proxy._apply_mouse_look(
		Vector2(0.0, -flick_pixels),
		Vector2(0.0, -flick_pixels * 4.0),
		STEP
	)
	_expect(
		proxy.consume_buffered_flip_intent() == 0,
		"raw mouse motion against the camera pitch clamp cannot arm an invisible flip gesture"
	)
	proxy.look_pitch = 0.0
	proxy._apply_mouse_look(
		Vector2(0.0, -deg_to_rad(3.0) / proxy.mouse_sensitivity),
		Vector2(0.0, -flick_pixels * 8.0),
		STEP
	)
	_expect(
		proxy.consume_buffered_flip_intent() == 0,
		"content-scaled screen-relative pixels cannot exaggerate the camera motion used by flip recognition"
	)
	proxy._apply_mouse_look(
		Vector2(0.0, flick_pixels),
		Vector2(0.0, flick_pixels),
		STEP
	)
	_expect(
		proxy.consume_buffered_flip_intent() == -1,
		"a downward captured-mouse flick maps to a frontflip request"
	)
	proxy._apply_mouse_look(
		Vector2(0.0, -flick_pixels),
		Vector2(0.0, -flick_pixels),
		STEP
	)
	proxy.set_local_locomotion_input(Vector2(0.0, -1.0), false)
	_expect(
		proxy.consume_buffered_flip_intent() == 0,
		"releasing sprint clears an armed flick instead of converting residual momentum into a flip"
	)
	proxy.set_local_locomotion_input(Vector2(0.0, -1.0), true)
	proxy.local_wrist_interface_open = true
	proxy.target_wrist_interface_open = true
	proxy._apply_mouse_look(
		Vector2(0.0, -flick_pixels),
		Vector2(0.0, -flick_pixels),
		STEP
	)
	proxy.target_on_floor = true
	proxy.local_locomotion_prediction_initialized = true
	proxy.local_predicted_horizontal_velocity = Vector2(
		0.0,
		-ServerPlayer.RUN_SPEED
	)
	_expect(
		proxy.consume_buffered_flip_intent() == 0
		and not proxy.predict_local_flip_takeoff(1),
		"an open Fieldlink clears camera-flick intent and cannot locally predict a flip"
	)
	proxy.local_wrist_interface_open = false
	proxy.target_wrist_interface_open = false
	proxy.local_locomotion_prediction_initialized = true
	proxy.local_predicted_horizontal_velocity = Vector2(
		0.0,
		-ServerPlayer.RUN_SPEED
	)
	var predicted_valid_flip := proxy.predict_local_flip_takeoff(1, 40)
	proxy.local_flip_prediction_elapsed = 0.12
	proxy.visual_flip_phase = 0.17
	proxy.resolve_local_jump_request(40, true, 1)
	_expect(
		predicted_valid_flip
		and proxy.local_flip_prediction_active
		and is_equal_approx(proxy.local_flip_prediction_elapsed, 0.12)
		and is_equal_approx(proxy.visual_flip_phase, 0.17),
		"authoritative acceptance preserves the immediate local flip trajectory without restarting its motion"
	)
	proxy.local_flip_prediction_active = false
	proxy.local_flip_prediction_request_id = 0
	proxy.visual_flip_direction = 0
	proxy.visual_flip_phase = 0.0
	proxy.visual_flip_angle = 0.0

	proxy.target_flip_sequence = 1
	proxy.target_flip_direction = 1
	proxy.target_flip_active = true
	proxy.target_flip_phase = 0.25
	proxy.presented_flip_sequence = 0
	proxy.visual_flip_phase = 0.0
	proxy.look_pitch = 0.0
	proxy.wrist_pose_weight = 0.0
	proxy.trip_camera_weight = 0.0
	proxy._update_flip_presentation(1.0)
	proxy._update_trip_camera(STEP)
	_expect(
		absf(proxy.body_visual.rotation.x - PI * 0.5) < 0.001
		and absf(proxy.camera_pivot.rotation.x - PI * 0.5) < 0.001,
		"a backflip rotates the authored body and the real first-person camera through the same quarter-turn"
	)
	proxy.target_flip_sequence = 2
	proxy.target_flip_direction = -1
	proxy.target_flip_phase = 0.25
	proxy.visual_flip_phase = 0.0
	proxy._update_flip_presentation(1.0)
	proxy._update_trip_camera(STEP)
	_expect(
		absf(proxy.body_visual.rotation.x + PI * 0.5) < 0.001
		and absf(proxy.camera_pivot.rotation.x + PI * 0.5) < 0.001,
		"a frontflip performs the corresponding physical first-person rotation in the opposite direction"
	)
	proxy.target_flip_active = false
	proxy.target_flip_phase = 1.0
	proxy._update_flip_presentation(1.0)
	proxy.target_flip_direction = 0
	proxy.target_flip_phase = 0.0
	proxy._update_flip_presentation(STEP)
	_expect(
		is_zero_approx(proxy.visual_flip_angle)
		and is_zero_approx(proxy.body_visual.rotation.x),
		"a completed flip followed by an ordinary jump stays at identity instead of replaying the old cycle backwards"
	)
	proxy.target_flip_sequence = 2
	proxy.target_flip_direction = 0
	proxy.target_flip_active = false
	proxy.target_flip_phase = 0.0
	proxy.target_jump_sequence = 7
	proxy.local_flip_prediction_active = true
	proxy.local_flip_prediction_request_id = 41
	proxy.local_flip_prediction_base_sequence = 2
	proxy.local_flip_prediction_base_jump_sequence = 6
	proxy.visual_flip_direction = 1
	proxy.visual_flip_phase = 0.18
	proxy.visual_flip_angle = 0.18 * TAU
	proxy.resolve_local_jump_request(41, false, 0)
	_expect(
		not proxy.local_flip_prediction_active
		and proxy.local_flip_prediction_request_id == 0
		and is_zero_approx(proxy.visual_flip_angle),
		"an explicit authoritative rejection cancels a provisional flip without a visible counter-rotation"
	)
	proxy.free()


func _test_network_clock_contract() -> void:
	var server_player := preload(
		"res://scenes/server/server_player.tscn"
	).instantiate() as ServerPlayer
	root.add_child(server_player)
	server_player.player_id = 81
	server_player.expression_clock = 42.75
	server_player.gait.momentum_recovery_weight = 0.64
	server_player.wrist_interface_open = true
	server_player.wrist_display_page = &"scanner"
	server_player.body_impact_sequence = 7
	server_player.body_impact_strength = 0.72
	server_player.body_impact_direction = Vector3(0.6, 0.0, 0.8)
	server_player.body_impact_contact_side = -0.4
	server_player.body_impact_clock = 42.6
	server_player.flip_sequence = 3
	server_player.flip_direction = -1
	server_player.flip_active = true
	server_player.flip_phase = 0.42
	server_player.kick_sequence = 4
	server_player.kick_side = PlayerGait.FootSide.RIGHT
	server_player.kick_style = ServerPlayer.KickStyle.DROP
	server_player.kick_active = true
	server_player.kick_phase = 0.86
	server_player.kick_intensity = 1.55
	var snapshot := server_player.to_state_dict()
	_expect(
		is_equal_approx(float(snapshot.get("expression_clock", -1.0)), 42.75)
		and snapshot.get("wrist_interface_open") == true
		and snapshot.get("wrist_display_page") == &"scanner"
		and int(snapshot.get("body_impact_sequence", 0)) == 7
		and int(snapshot.get("flip_sequence", 0)) == 3
		and int(snapshot.get("flip_direction", 0)) == -1
		and snapshot.get("flip_active") == true
		and is_equal_approx(float(snapshot.get("flip_phase", 0.0)), 0.42)
		and int(snapshot.get("kick_style", -1))
		== ServerPlayer.KickStyle.DROP
		and is_equal_approx(
			float(snapshot.get("body_impact_strength", 0.0)),
			0.72
		),
		"late-join snapshots replicate expression time, interaction pose, and the latest environmental contact"
	)
	var proxy := preload("res://scenes/proxy/player_proxy.tscn").instantiate() as PlayerProxy
	root.add_child(proxy)
	proxy.apply_server_state(snapshot)
	_expect(
		proxy.player_id == 81
		and is_equal_approx(proxy.target_expression_clock, 42.75)
		and is_equal_approx(proxy.target_gait_momentum_recovery, 0.64)
		and proxy.target_wrist_interface_open
		and proxy.target_body_impact_sequence == 7
		and proxy.target_flip_sequence == 3
		and proxy.target_flip_direction == -1
		and proxy.target_flip_active
		and is_equal_approx(proxy.target_flip_phase, 0.42)
		and proxy.target_kick_sequence == 4
		and proxy.target_kick_style == ServerPlayer.KickStyle.DROP
		and proxy.target_kick_active
		and is_equal_approx(proxy.target_kick_phase, 0.86)
		and is_equal_approx(proxy.target_kick_intensity, 1.55)
		and is_equal_approx(proxy.target_body_impact_strength, 0.72)
		and proxy.target_body_impact_direction.is_equal_approx(
			Vector3(0.6, 0.0, 0.8)
		)
		and is_equal_approx(proxy.target_body_impact_contact_side, -0.4),
		"joining clients consume the same clock, action, and environmental response state used by host presentation"
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
