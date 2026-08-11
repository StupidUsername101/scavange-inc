extends SceneTree

#######################################################
# Regression coverage for authoritative proxy-state decoding. Network corruption must fall back at
# the boundary instead of reaching typed Node3D assignments before per-proxy state handling runs.
#######################################################

var failure_count: int = 0


func _init() -> void:
	var fallback_position: Vector3 = Vector3(3.0, 4.0, 5.0)
	var fallback_rotation: Vector3 = Vector3(0.1, 0.2, 0.3)
	var decoded: Dictionary = ClientProxyMotion.decode_rigid_state(
		{
			"pos": [1.0, 2.0, 3.0],
			"rot": "broken",
			"linear_velocity": [4.0, 5.0, 6.0],
			"angular_velocity": [0.0, NAN, 0.0],
		},
		fallback_position,
		fallback_rotation
	)
	_expect(
		decoded.get("position", Vector3.ZERO) == Vector3(1.0, 2.0, 3.0),
		"finite array positions decode at the shared proxy boundary"
	)
	_expect(
		decoded.get("rotation", Quaternion.IDENTITY) == Quaternion.from_euler(fallback_rotation),
		"malformed rotations use the caller fallback before reaching Node3D"
	)
	_expect(
		decoded.get("linear_velocity", Vector3.ZERO) == Vector3(4.0, 5.0, 6.0),
		"finite proxy velocity remains unchanged"
	)
	_expect(
		decoded.get("angular_velocity", Vector3.ONE) == Vector3.ZERO,
		"non-finite proxy angular velocity fails closed"
	)
	quit(0 if failure_count == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)
