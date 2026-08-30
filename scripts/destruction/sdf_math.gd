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
	var lattice := Vector3i(
		floori(point.x * frequency),
		floori(point.y * frequency),
		floori(point.z * frequency)
	)
	var value := seed
	value = _hash_step(value, lattice.x)
	value = _hash_step(value, lattice.y)
	value = _hash_step(value, lattice.z)
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
