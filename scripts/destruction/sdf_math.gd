class_name SdfMath
extends RefCounted

const MIN_DIRECTION_LENGTH_SQUARED := 0.000001


static func box(point: Vector3, half_extents: Vector3) -> float:
	var q := point.abs() - half_extents.abs()
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(
		maxf(q.x, maxf(q.y, q.z)),
		0.0
	)


static func sphere(point: Vector3, center: Vector3, radius: float) -> float:
	return point.distance_to(center) - maxf(radius, 0.0)


static func capsule(
	point: Vector3,
	start: Vector3,
	end: Vector3,
	radius: float
) -> float:
	var segment := end - start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= MIN_DIRECTION_LENGTH_SQUARED:
		return sphere(point, start, radius)
	var t := clampf((point - start).dot(segment) / segment_length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t) - maxf(radius, 0.0)


static func tapered_capsule(
	point: Vector3,
	start: Vector3,
	end: Vector3,
	start_radius: float,
	end_radius: float
) -> float:
	var segment := end - start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= MIN_DIRECTION_LENGTH_SQUARED:
		return sphere(point, start, maxf(start_radius, end_radius))
	var t := clampf((point - start).dot(segment) / segment_length_squared, 0.0, 1.0)
	var radius := lerpf(maxf(start_radius, 0.0), maxf(end_radius, 0.0), t)
	return point.distance_to(start + segment * t) - radius


static func subtract(solid_distance: float, brush_distance: float) -> float:
	return maxf(solid_distance, -brush_distance)


static func union(solid_distance: float, brush_distance: float) -> float:
	return minf(solid_distance, brush_distance)


static func deterministic_signed_noise(
	point: Vector3,
	frequency: float,
	seed: int
) -> float:
	# Spatial warp is part of the SDF itself, so it must be spatially continuous. Hashing only the
	# containing lattice cell made the cutter radius jump at every noise-cell boundary. Stronger
	# materials then exposed those discontinuities as isolated sign islands and folded contour
	# sheets. Smooth value noise keeps the authored randomness deterministic while making both the
	# distance and its finite-difference normal continuous. Keep this scalar and allocation-free: it
	# runs only over the sparse damage region, but it is still the hottest part of a destructive hit.
	var scaled := point * maxf(frequency, 0.0001)
	var x0 := floori(scaled.x)
	var y0 := floori(scaled.y)
	var z0 := floori(scaled.z)
	var tx := quintic_fade(scaled.x - float(x0))
	var ty := quintic_fade(scaled.y - float(y0))
	var tz := quintic_fade(scaled.z - float(z0))
	var x00 := lerpf(
		deterministic_lattice_noise(x0, y0, z0, seed),
		deterministic_lattice_noise(x0 + 1, y0, z0, seed),
		tx
	)
	var x10 := lerpf(
		deterministic_lattice_noise(x0, y0 + 1, z0, seed),
		deterministic_lattice_noise(x0 + 1, y0 + 1, z0, seed),
		tx
	)
	var x01 := lerpf(
		deterministic_lattice_noise(x0, y0, z0 + 1, seed),
		deterministic_lattice_noise(x0 + 1, y0, z0 + 1, seed),
		tx
	)
	var x11 := lerpf(
		deterministic_lattice_noise(x0, y0 + 1, z0 + 1, seed),
		deterministic_lattice_noise(x0 + 1, y0 + 1, z0 + 1, seed),
		tx
	)
	return lerpf(lerpf(x00, x10, ty), lerpf(x01, x11, ty), tz)


static func quintic_fade(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * clamped * (clamped * (clamped * 6.0 - 15.0) + 10.0)


static func deterministic_lattice_noise(x: int, y: int, z: int, seed: int) -> float:
	# Mix the complete lattice coordinate once. Calling the two-round scalar finalizer separately for
	# x, y, and z cost six integer multiplications per corner (48 per SDF sample).
	var value := seed ^ (x * 0x1f123bb5) ^ (y * 0x5f356495) ^ (z * 0x2c1b3c6d)
	value = (value ^ (value >> 16)) * 0x7feb352d
	value = (value ^ (value >> 15)) * 0x846ca68b
	value = (value ^ (value >> 16)) & 0x7fffffff
	return float(value & 0xffff) / 32767.5 - 1.0


static func orthogonal_basis(direction: Vector3) -> Basis:
	var forward := (
		direction.normalized()
		if direction.length_squared() > MIN_DIRECTION_LENGTH_SQUARED
		else Vector3.FORWARD
	)
	var reference := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var right := forward.cross(reference).normalized()
	var up := right.cross(forward).normalized()
	return Basis(right, up, forward).orthonormalized()


static func _hash_step(state: int, value: int) -> int:
	var mixed := state ^ (value * 0x45d9f3b)
	mixed = ((mixed >> 16) ^ mixed) * 0x45d9f3b
	mixed = ((mixed >> 16) ^ mixed) * 0x45d9f3b
	return ((mixed >> 16) ^ mixed) & 0x7fffffff
