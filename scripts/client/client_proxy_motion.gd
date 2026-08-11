class_name ClientProxyMotion
extends RefCounted

#######################################################
# Shared client-side smoothing for proxies that mirror authoritative Node3D physics state.
# Callers keep their own interpolation/extrapolation constants and authoritative-server shortcut.
#######################################################


static func decode_rigid_state(
	state: Dictionary,
	fallback_position: Vector3,
	fallback_rotation_euler: Vector3,
	linear_velocity_key: String = "linear_velocity",
	angular_velocity_key: String = "angular_velocity"
) -> Dictionary:
	var rotation_euler: Vector3 = SafeVariant.vector3_strict_or(
		state.get("rot", fallback_rotation_euler),
		fallback_rotation_euler
	)
	return {
		"position": SafeVariant.vector3_strict_or(
			state.get("pos", fallback_position),
			fallback_position
		),
		"rotation": Quaternion.from_euler(rotation_euler),
		"linear_velocity": SafeVariant.vector3_strict_or(
			state.get(linear_velocity_key, Vector3.ZERO),
			Vector3.ZERO
		),
		"angular_velocity": SafeVariant.vector3_strict_or(
			state.get(angular_velocity_key, Vector3.ZERO),
			Vector3.ZERO
		),
	}


static func apply_smoothed_motion(
	proxy: Node3D,
	delta: float,
	time_since_last_state: float,
	target_position: Vector3,
	target_rotation: Quaternion,
	target_linear_velocity: Vector3,
	target_angular_velocity: Vector3,
	maximum_extrapolation_time: float,
	interpolation_speed: float,
	minimum_angular_speed: float = 0.0001
) -> void:
	if not is_instance_valid(proxy):
		return
	var extrapolation_time: float = minf(
		time_since_last_state,
		maximum_extrapolation_time
	)
	var predicted_position: Vector3 = (
		target_position
		+ target_linear_velocity * extrapolation_time
	)
	var predicted_rotation: Quaternion = target_rotation
	var angular_speed: float = target_angular_velocity.length()
	if angular_speed > minimum_angular_speed:
		predicted_rotation = (
			Quaternion(
				target_angular_velocity / angular_speed,
				angular_speed * extrapolation_time
			)
			* target_rotation
		)
	var weight: float = clampf(interpolation_speed * delta, 0.0, 1.0)
	# Advance with the reported velocity before lerping toward the extrapolated target. Otherwise a
	# proxy following an equally fast target develops a permanent trailing gap.
	proxy.global_position += target_linear_velocity * delta
	proxy.global_position = proxy.global_position.lerp(predicted_position, weight)
	var current_rotation: Quaternion = proxy.global_basis.get_rotation_quaternion()
	proxy.global_basis = Basis(current_rotation.slerp(predicted_rotation, weight))
