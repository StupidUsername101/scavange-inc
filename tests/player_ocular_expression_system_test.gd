extends SceneTree

const STEP := 1.0 / 120.0
const EPSILON := 0.00001
const OCULAR_SCENES := [
	"res://scenes/items/visuals/factory_oculars_visual.tscn",
	"res://scenes/items/visuals/precision_oculars_visual.tscn",
	"res://scenes/items/visuals/salvaged_oculars_visual.tscn",
]

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_deterministic_expression()
	_test_eye_first_head_follow()
	_test_near_target_vergence()
	_test_irregular_blinks_and_bounds()
	_test_all_ocular_visuals_have_expression_surfaces()
	_test_player_eye_hierarchy_and_missing_eye_safety()
	if failure_count == 0:
		print("Player ocular expression tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Player ocular expression tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_deterministic_expression() -> void:
	var first := PlayerOcularExpressionController.new()
	var second := PlayerOcularExpressionController.new()
	var different := PlayerOcularExpressionController.new()
	first.set_expression_identity(42)
	second.set_expression_identity(42)
	different.set_expression_identity(43)
	for frame: int in range(360):
		var clock := float(frame) * STEP
		first.update(STEP, clock, Vector3(1.2, 0.3, -3.0), 0.8, false, 0.2)
		second.update(STEP, clock, Vector3(1.2, 0.3, -3.0), 0.8, false, 0.2)
		different.update(STEP, clock, Vector3(1.2, 0.3, -3.0), 0.8, false, 0.2)
	_expect(
		first.left_pupil_offset.distance_to(second.left_pupil_offset) < EPSILON
		and first.head_rotation.distance_to(second.head_rotation) < EPSILON
		and is_equal_approx(first.left_lid_openness, second.left_lid_openness),
		"replicated clock and identity produce identical eyes, lids, and head follow on every peer"
	)
	_expect(
		absf(first.left_lid_tilt - different.left_lid_tilt) > 0.005
		or absf(first.pupil_scale - different.pupil_scale) > 0.005,
		"identity phases keep neighboring characters from blinking and emoting as clones"
	)


func _test_eye_first_head_follow() -> void:
	var small_shift := PlayerOcularExpressionController.new()
	small_shift.set_expression_identity(7)
	for frame: int in range(120):
		small_shift.update(
			STEP,
			float(frame) * STEP,
			Vector3(0.45, 0.0, -4.0),
			1.0,
			false,
			0.0
		)
	_expect(
		absf(small_shift.head_rotation.y) < deg_to_rad(1.0)
		and small_shift.left_pupil_offset.x > 0.08,
		"small gaze shifts remain in the pupils instead of making the whole head twitch"
	)

	var large_shift := PlayerOcularExpressionController.new()
	large_shift.set_expression_identity(7)
	for frame: int in range(180):
		large_shift.update(
			STEP,
			float(frame) * STEP,
			Vector3(4.0, 0.0, -2.0),
			1.0,
			false,
			0.0
		)
	_expect(
		large_shift.head_rotation.y < deg_to_rad(-8.0)
		and large_shift.left_pupil_offset.x > 0.05,
		"large gaze shifts are led by the pupils and then recruit the head toward the target"
	)


func _test_near_target_vergence() -> void:
	var controller := PlayerOcularExpressionController.new()
	controller.set_expression_identity(19)
	for frame: int in range(90):
		controller.update(
			STEP,
			float(frame) * STEP,
			Vector3(0.0, -0.45, -0.65),
			1.0,
			true,
			0.0
		)
	_expect(
		controller.left_pupil_offset.x > controller.right_pupil_offset.x + 0.15,
		"the two pupils converge independently on a close wrist display"
	)
	_expect(
		controller.head_rotation.x < -deg_to_rad(1.0),
		"a close target below the eyes produces a restrained downward head follow"
	)


func _test_irregular_blinks_and_bounds() -> void:
	var controller := PlayerOcularExpressionController.new()
	controller.set_expression_identity(91)
	var minimum_open := 1.0
	var blink_onsets: Array[float] = []
	var previously_closed := false
	for frame: int in range(int(30.0 / STEP)):
		var clock := float(frame) * STEP
		controller.update(
			STEP,
			clock,
			Vector3(0.0, 0.0, -4.0),
			0.2,
			false,
			0.4
		)
		minimum_open = minf(minimum_open, controller.left_lid_openness)
		var closed := controller.left_lid_openness < 0.55
		if closed and not previously_closed:
			blink_onsets.append(clock)
		previously_closed = closed
		if (
			controller.left_lid_openness < -EPSILON
			or controller.left_lid_openness > 1.0 + EPSILON
			or controller.pupil_scale < 0.72 - EPSILON
			or controller.pupil_scale > 1.24 + EPSILON
		):
			_expect(false, "ocular expression channels remain within safe visual bounds")
			return
	_expect(true, "ocular expression channels remain within safe visual bounds")
	var intervals_differ := false
	for index: int in range(2, blink_onsets.size()):
		var current_interval := blink_onsets[index] - blink_onsets[index - 1]
		var previous_interval := blink_onsets[index - 1] - blink_onsets[index - 2]
		if absf(current_interval - previous_interval) > 0.25:
			intervals_differ = true
			break
	_expect(
		minimum_open < 0.30 and blink_onsets.size() >= 4 and intervals_differ,
		"blinks fully read as blinks and use irregular deterministic timing rather than a loop"
	)


func _test_all_ocular_visuals_have_expression_surfaces() -> void:
	for scene_path: String in OCULAR_SCENES:
		var packed := load(scene_path) as PackedScene
		var visual := packed.instantiate() as OcularExpressionVisual
		root.add_child(visual)
		var left_pupil := visual.get_node_or_null("LeftLens/LeftExpression/Pupil") as MeshInstance3D
		var left_upper_lid := visual.get_node_or_null(
			"LeftLens/LeftExpression/UpperLid"
		) as MeshInstance3D
		var right_lower_lid := visual.get_node_or_null(
			"RightLens/RightExpression/LowerLid"
		) as MeshInstance3D
		_expect(
			left_pupil != null and left_upper_lid != null and right_lower_lid != null,
			"%s derives independent pupils and upper/lower lids from its lens geometry"
			% scene_path.get_file()
		)
		if left_pupil != null and left_upper_lid != null:
			var open_lid_y := left_upper_lid.position.y
			visual.apply_ocular_expression(
				Vector2(1.0, 0.4),
				Vector2(-1.0, 0.4),
				1.1,
				0.0,
				0.0,
				0.1,
				-0.1
			)
			_expect(
				left_pupil.position.x > 0.0
				and left_upper_lid.position.y < open_lid_y
				and left_upper_lid.rotation.z > 0.05,
				"%s applies gaze, blink, dilation, and expressive lid tilt through cached transforms"
				% scene_path.get_file()
			)
		visual.free()


func _test_player_eye_hierarchy_and_missing_eye_safety() -> void:
	var proxy := preload("res://scenes/proxy/player_proxy.tscn").instantiate() as PlayerProxy
	root.add_child(proxy)
	_expect(
		proxy.eyes_mount.get_parent() == proxy.head_visual,
		"equipped oculars inherit procedural head motion instead of floating beside the head"
	)
	proxy.call("_update_ocular_expression", STEP, 1.0)
	proxy.character_pose.update(
		STEP,
		1.0,
		0.5,
		0.0,
		0.0,
		0.0,
		Vector3.ZERO,
		true,
		false,
		null,
		true,
		true,
		true,
		true
	)
	_expect(
		proxy.character_pose.head_rotation.length() < 0.1,
		"a missing eye item disables ocular attention cleanly without creating a phantom surface"
	)
	proxy.free()


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] " + message)
		return
	failure_count += 1
	push_error("FAIL: " + message)
