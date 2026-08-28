extends SceneTree

class AuthoredGrabBody:
	extends RigidBody3D

	var default_grab_basis := Basis.IDENTITY

	func get_default_grab_basis() -> Basis:
		return default_grab_basis


#######################################################
# Regression coverage for stable held-item orientation, authored grab poses, and loss-tolerant
# absolute mouse targets.
#######################################################

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_authored_item_pose()
	_test_absolute_rotation_input()
	_test_screen_axis_mapping()
	_test_absolute_orientation_target()
	await _test_centered_anchor_preserves_hold_target()
	_test_persistent_relative_target()
	_test_shortest_rotation_error()
	await _test_physical_pose_control()
	await _test_physical_mouse_pitch_control()
	await _test_portable_radio_full_turn()
	await _test_narrow_assisted_item_acquisition()
	_finish()


func _test_narrow_assisted_item_acquisition() -> void:
	var server := root.get_node_or_null("Server")
	var grabber := GrabberComponent.new()
	grabber.capability = GrabCapability.new()
	grabber.capability.max_distance = 3.0
	root.add_child(grabber)
	var item := RigidBody3D.new()
	item.gravity_scale = 0.0
	item.position = Vector3(0.15, 0.0, -2.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.18, 0.3, 0.3)
	collision.shape = shape
	item.add_child(collision)
	root.add_child(item)
	await physics_frame
	server.call("try_begin_grab", grabber)
	_expect(
		server.call("get_grabbed_body", grabber) == item,
		"a narrow visible item just beside the exact aim ray is acquired through bounded line-of-sight assistance"
	)
	server.call("end_grab", grabber)
	item.set_meta("grip_surface_disabled", true)
	server.call("try_begin_grab", grabber)
	_expect(
		server.call("get_grabbed_body", grabber) == null,
		"the same assisted query still rejects an explicitly non-grippable item"
	)
	item.free()
	grabber.free()


func _test_authored_item_pose() -> void:
	var definition := ItemDefinition.new()
	definition.default_grab_rotation_degrees = Vector3(20.0, -35.0, 12.0)
	var expected := Basis.from_euler(Vector3(
		deg_to_rad(20.0),
		deg_to_rad(-35.0),
		deg_to_rad(12.0)
	)).orthonormalized()
	_expect(
		_basis_is_equal(definition.get_default_grab_basis(), expected),
		"item definitions expose an authored default hold rotation"
	)
	definition.default_grab_rotation_degrees = Vector3(NAN, 1.0, 2.0)
	_expect(
		definition.default_grab_rotation_degrees == Vector3.ZERO,
		"non-finite authored hold rotations fail closed"
	)

	var grabber := GrabberComponent.new()
	grabber.basis = Basis.from_euler(Vector3(0.1, 0.8, -0.05))
	var item := AuthoredGrabBody.new()
	item.default_grab_basis = definition.get_default_grab_basis()
	item.basis = Basis.from_euler(Vector3(1.0, 0.2, 0.7))
	root.add_child(grabber)
	root.add_child(item)
	var server := root.get_node_or_null("Server")
	var authored: Basis = server.call(
		"_get_initial_grab_basis",
		grabber,
		item
	) if server != null else Basis.IDENTITY
	_expect(
		server != null
		and _basis_is_equal(authored, definition.get_default_grab_basis()),
		"server items start from their authored pose instead of an arbitrary dropped pose"
	)
	item.free()
	grabber.free()


func _test_absolute_rotation_input() -> void:
	var state := GrabState.new(
		null,
		null,
		Vector3.ZERO,
		1.0,
		0.0
	)
	state.set_rotation_active(true)
	# Only the latest absolute packet matters. A missing intermediate packet does
	# not lose any mouse movement.
	state.set_rotation_input_target(Vector2(100.0, -55.0))
	_expect(
		state.consume_rotation_input().is_equal_approx(Vector2(100.0, -55.0)),
		"absolute mouse targets recover movement across a dropped packet"
	)
	state.set_rotation_input_target(Vector2(175.0, -20.0))
	_expect(
		state.consume_rotation_input().is_equal_approx(Vector2(75.0, 35.0)),
		"successive packets apply only their unapplied rotation delta"
	)
	state.set_rotation_input_target(Vector2(1000.0, -20.0))
	_expect(
		state.consume_rotation_input().length()
		<= GrabState.MAX_ROTATION_INPUT_PER_TICK + 0.001,
		"a malicious or stalled client cannot inject an unbounded one-tick rotation"
	)
	state.set_rotation_active(false)
	state.set_rotation_active(true, 2)
	state.set_rotation_input_target(Vector2(500.0, 500.0), 1)
	state.set_rotation_input_target(Vector2(8.0, 3.0), 2)
	_expect(
		state.consume_rotation_input().is_equal_approx(Vector2(8.0, 3.0)),
		"new rotation gestures reset input and reject late packets from the old gesture"
	)


func _test_persistent_relative_target() -> void:
	var grabber := GrabberComponent.new()
	root.add_child(grabber)
	var initial_target := Basis.from_euler(Vector3(0.2, -0.1, 0.05))
	var state := GrabState.new(
		grabber,
		null,
		Vector3.ZERO,
		1.0,
		0.0,
		initial_target
	)
	state.set_rotation_active(true)
	state.rotate_target(Vector2(45.0, -18.0), 0.004)
	var edited_target := state.target_basis_relative_to_grabber
	_expect(
		not _basis_is_equal(edited_target, initial_target),
		"mouse rotation edits the held pose target"
	)
	state.set_rotation_active(false)
	_expect(
		_basis_is_equal(state.target_basis_relative_to_grabber, edited_target),
		"releasing the rotation button preserves the requested hold pose"
	)
	grabber.basis = Basis(Quaternion(Vector3.UP, 0.6))
	_expect(
		_basis_is_equal(
			state.get_target_world_basis(),
			grabber.global_basis.orthonormalized() * edited_target
		),
		"the persistent pose remains relative to the player's grab frame"
	)
	grabber.free()


func _test_screen_axis_mapping() -> void:
	var horizontal := GrabState.new(null, null, Vector3.ZERO, 1.0, 0.0)
	horizontal.rotate_target(Vector2(50.0, 0.0), 0.004)
	var horizontal_error := GrabState.rotation_error_vector(
		Basis.IDENTITY,
		horizontal.target_basis_relative_to_grabber
	)
	var vertical := GrabState.new(null, null, Vector3.ZERO, 1.0, 0.0)
	vertical.rotate_target(Vector2(0.0, 50.0), 0.004)
	var vertical_error := GrabState.rotation_error_vector(
		Basis.IDENTITY,
		vertical.target_basis_relative_to_grabber
	)
	_expect(
		absf(horizontal_error.y) > 0.19
		and absf(horizontal_error.x) < 0.001
		and absf(horizontal_error.z) < 0.001,
		"horizontal mouse drag changes only grab-frame yaw"
	)
	_expect(
		absf(vertical_error.x) > 0.19
		and absf(vertical_error.y) < 0.001
		and absf(vertical_error.z) < 0.001,
		"vertical mouse drag changes only grab-frame pitch toward or away from the player"
	)


func _test_absolute_orientation_target() -> void:
	var direct := GrabState.new(null, null, Vector3.ZERO, 1.0, 0.0)
	direct.set_rotation_active(true, 1)
	direct.set_rotation_input_target(Vector2(100.0, 80.0), 1)
	direct.advance_rotation_target(0.004)
	var packeted := GrabState.new(null, null, Vector3.ZERO, 1.0, 0.0)
	packeted.set_rotation_active(true, 1)
	packeted.set_rotation_input_target(Vector2(40.0, 20.0), 1)
	packeted.advance_rotation_target(0.004)
	packeted.set_rotation_input_target(Vector2(100.0, 80.0), 1)
	packeted.advance_rotation_target(0.004)
	_expect(
		_basis_is_equal(
			direct.target_basis_relative_to_grabber,
			packeted.target_basis_relative_to_grabber
		),
		"absolute yaw and pitch produce the same pose regardless of packet grouping"
	)


func _test_centered_anchor_preserves_hold_target() -> void:
	var server := root.get_node_or_null("Server")
	var grabber := GrabberComponent.new()
	grabber.capability = GrabCapability.new()
	grabber.position = Vector3(1.0, 0.5, 2.0)
	grabber.basis = Basis.from_euler(Vector3(0.15, 0.4, 0.0))
	root.add_child(grabber)
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.position = Vector3(-0.5, 1.2, -1.0)
	body.basis = Basis.from_euler(Vector3(0.2, -0.3, 0.1))
	var collision := CollisionShape3D.new()
	collision.position = Vector3(0.0, 0.24, 0.0)
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	root.add_child(body)
	await physics_frame
	var direct_state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var actual_center_of_mass := (
		direct_state.center_of_mass_local
		if direct_state != null
		else body.center_of_mass
	)
	var state := GrabState.new(
		grabber,
		body,
		Vector3(0.45, -0.2, 0.3),
		2.4,
		0.35,
		Basis.IDENTITY,
		-0.25
	)
	var previous_point := body.to_global(state.local_grab_point)
	var previous_target := grabber.get_grab_target(
		state.grab_distance,
		state.lift_offset,
		state.side_offset
	)
	var expected_center_target := (
		previous_target
		+ body.to_global(actual_center_of_mass)
		- previous_point
	)
	if server != null:
		server.call("_center_grab_rotation_anchor", state)
	var centered_target := grabber.get_grab_target(
		state.grab_distance,
		state.lift_offset,
		state.side_offset
	)
	_expect(
		server != null
		and state.local_grab_point.distance_to(actual_center_of_mass) < 0.0001
		and centered_target.distance_to(expected_center_target) < 0.0001,
		"centering uses the physical center of mass and preserves the full hold target"
	)
	body.free()
	grabber.free()


func _test_shortest_rotation_error() -> void:
	var quarter_turn := Basis(Quaternion(Vector3.UP, PI * 0.5))
	var error := GrabState.rotation_error_vector(Basis.IDENTITY, quarter_turn)
	_expect(
		error.distance_to(Vector3.UP * PI * 0.5) < 0.0001,
		"orientation control produces the expected axis-angle error"
	)
	_expect(
		GrabState.rotation_error_vector(quarter_turn, quarter_turn).is_zero_approx(),
		"orientation control applies no torque at its remembered target"
	)
	var long_way := Basis(Quaternion(Vector3.UP, PI * 1.5))
	var shortest := GrabState.rotation_error_vector(Basis.IDENTITY, long_way)
	_expect(
		shortest.distance_to(Vector3.DOWN * PI * 0.5) < 0.0001,
		"orientation control always chooses the shortest turn"
	)


func _test_physical_pose_control() -> void:
	var server := root.get_node_or_null("Server")
	var grabber := GrabberComponent.new()
	grabber.capability = GrabCapability.new()
	root.add_child(grabber)
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.mass = 3.0
	body.basis = Basis(Quaternion(Vector3(1.0, 1.0, 0.0).normalized(), PI * 0.5))
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	root.add_child(body)
	await physics_frame
	var state := GrabState.new(
		grabber,
		body,
		Vector3.ZERO,
		1.0,
		0.0,
		Basis.IDENTITY
	)
	var initial_error := GrabState.rotation_error_vector(
		body.global_basis,
		state.get_target_world_basis()
	).length()
	for step: int in range(120):
		if server != null:
			server.call(
				"_apply_grab_rotation",
				state,
				body,
				1.0 / 60.0
			)
		await physics_frame
	var final_error := GrabState.rotation_error_vector(
		body.global_basis,
		state.get_target_world_basis()
	).length()
	_expect(
		server != null
		and body.global_basis.is_finite()
		and body.angular_velocity.is_finite()
		and final_error < initial_error * 0.1,
		"the real rigid-body controller converges smoothly across pitch and yaw"
	)
	body.free()
	grabber.free()


func _test_physical_mouse_pitch_control() -> void:
	var server := root.get_node_or_null("Server")
	var grabber := GrabberComponent.new()
	grabber.capability = GrabCapability.new()
	root.add_child(grabber)
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	body.mass = 2.0
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	root.add_child(body)
	await physics_frame
	var state := GrabState.new(
		grabber,
		body,
		Vector3.ZERO,
		1.0,
		0.0,
		Basis.IDENTITY
	)
	state.set_rotation_active(true, 5)
	state.set_rotation_input_target(Vector2(30.0, 120.0), 5)
	for step: int in range(120):
		if server != null:
			server.call("_apply_grab_rotation", state, body, 1.0 / 60.0)
		await physics_frame
	var target_delta := GrabState.rotation_error_vector(
		Basis.IDENTITY,
		state.get_target_world_basis()
	)
	var final_error := GrabState.rotation_error_vector(
		body.global_basis,
		state.get_target_world_basis()
	).length()
	_expect(
		server != null
		and absf(target_delta.x) > absf(target_delta.y) * 2.0
		and final_error < 0.05,
		"vertical live mouse input physically pitches an item toward or away from the player"
	)
	body.free()
	grabber.free()


func _test_portable_radio_full_turn() -> void:
	var server := root.get_node_or_null("Server")
	var grabber := GrabberComponent.new()
	grabber.capability = GrabCapability.new()
	root.add_child(grabber)
	var radio := RigidBody3D.new()
	radio.mass = 2.4
	radio.gravity_scale = 0.0
	radio.position = Vector3(0.0, 0.35, -2.0)
	var radio_collision := CollisionShape3D.new()
	var radio_shape := BoxShape3D.new()
	radio_shape.size = Vector3(0.78, 0.48, 0.32)
	radio_collision.position = Vector3(0.0, 0.24, 0.0)
	radio_collision.shape = radio_shape
	radio.add_child(radio_collision)
	root.add_child(radio)
	await physics_frame
	if server != null:
		server.call("grab_body_directly", grabber, radio)
		server.call("set_grabber_rotation_active", grabber, true, 9)

	var previous_basis := radio.global_basis
	var accumulated_yaw := 0.0
	var full_turn_pixels := -TAU / grabber.capability.rotation_radians_per_pixel
	for step: int in range(150):
		var progress := float(step + 1) / 150.0
		if server != null:
			server.call(
				"set_grab_rotation_input_target",
				grabber,
				Vector2(full_turn_pixels * progress, 0.0),
				9
			)
		await physics_frame
		var turn_delta := GrabState.rotation_error_vector(
			previous_basis,
			radio.global_basis
		)
		accumulated_yaw += turn_delta.y
		previous_basis = radio.global_basis
	for settle_step: int in range(60):
		await physics_frame
		var turn_delta := GrabState.rotation_error_vector(
			previous_basis,
			radio.global_basis
		)
		accumulated_yaw += turn_delta.y
		previous_basis = radio.global_basis

	var state := (
		server.get("grab_states_by_grabber_id").get(grabber.get_instance_id())
		as GrabState
		if server != null
		else null
	)
	var final_error := (
		GrabState.rotation_error_vector(
			radio.global_basis,
			state.get_target_world_basis()
		).length()
		if state != null
		else INF
	)
	_expect(
		absf(accumulated_yaw) > TAU * 0.9
		and final_error < 0.08,
		"the offset portable radio follows a complete physical turn without reversing"
	)
	if server != null:
		server.call("end_grab", grabber)
	radio.free()
	grabber.free()


func _basis_is_equal(a: Basis, b: Basis, tolerance := 0.0001) -> bool:
	return (
		a.x.distance_to(b.x) <= tolerance
		and a.y.distance_to(b.y) <= tolerance
		and a.z.distance_to(b.z) <= tolerance
	)


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)


func _finish() -> void:
	print(
		"Grab rotation test: %d assertions, %d failures"
		% [assertion_count, failure_count]
	)
	quit(0 if failure_count == 0 else 1)
