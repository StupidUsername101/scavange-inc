class_name DroneTrainingObstacleShape
extends RefCounted

#######################################################
# Shared shape contract for editable training obstacles. UI, collision, rendering, sensing,
# selection, and spatial hashing all use the same kind/dimension representation.
#######################################################

enum Kind {
	BOX,
	CYLINDER,
	SPHERE,
	CAPSULE,
}

const DISPLAY_NAMES: Array[String] = [
	"Box",
	"Cylinder",
	"Sphere",
	"Capsule",
]
const MINIMUM_DIMENSION_M := 0.001


static func display_name(kind: int) -> String:
	return DISPLAY_NAMES[clampi(kind, 0, DISPLAY_NAMES.size() - 1)]


static func dimension_definitions(kind: int) -> Array[Dictionary]:
	match clampi(kind, 0, DISPLAY_NAMES.size() - 1):
		Kind.CYLINDER:
			return [
				{"key": "radius", "label": "Radius", "default": 1.0, "step": 0.05},
				{"key": "height", "label": "Height", "default": 3.0, "step": 0.1},
			]
		Kind.SPHERE:
			return [
				{"key": "radius", "label": "Radius", "default": 1.0, "step": 0.05},
			]
		Kind.CAPSULE:
			return [
				{"key": "radius", "label": "Radius", "default": 0.8, "step": 0.05},
				{"key": "height", "label": "Total height", "default": 3.0, "step": 0.1},
			]
	return [
		{"key": "width", "label": "Width", "default": 4.0, "step": 0.1},
		{"key": "height", "label": "Height", "default": 3.0, "step": 0.1},
		{"key": "depth", "label": "Depth", "default": 0.35, "step": 0.05},
	]


static func normalized_dimensions(kind: int, values: Dictionary) -> Dictionary:
	var safe_kind = clampi(kind, 0, DISPLAY_NAMES.size() - 1)
	var result: Dictionary = {}
	for definition in dimension_definitions(safe_kind):
		var key := str(definition.get("key", ""))
		var default_value = RLTrainingMath.finite_float_or(definition.get("default", 1.0), 1.0)
		var dimension = RLTrainingMath.finite_float_or(values.get(key, default_value), default_value)
		result[key] = maxf(absf(dimension), MINIMUM_DIMENSION_M)
	if safe_kind == Kind.CAPSULE:
		result["height"] = maxf(
			float(result.get("height", 1.0)),
			float(result.get("radius", 0.5)) * 2.0
		)
	return result


static func collision_shape(kind: int, values: Dictionary) -> Shape3D:
	var dimensions := normalized_dimensions(kind, values)
	match clampi(kind, 0, DISPLAY_NAMES.size() - 1):
		Kind.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = float(dimensions["radius"])
			cylinder.height = float(dimensions["height"])
			return cylinder
		Kind.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = float(dimensions["radius"])
			return sphere
		Kind.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = float(dimensions["radius"])
			capsule.height = float(dimensions["height"])
			return capsule
	var box := BoxShape3D.new()
	box.size = Vector3(
		float(dimensions["width"]),
		float(dimensions["height"]),
		float(dimensions["depth"])
	)
	return box


static func visual_mesh(kind: int, values: Dictionary) -> PrimitiveMesh:
	var dimensions := normalized_dimensions(kind, values)
	match clampi(kind, 0, DISPLAY_NAMES.size() - 1):
		Kind.CYLINDER:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = float(dimensions["radius"])
			cylinder.bottom_radius = float(dimensions["radius"])
			cylinder.height = float(dimensions["height"])
			return cylinder
		Kind.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = float(dimensions["radius"])
			sphere.height = float(dimensions["radius"]) * 2.0
			return sphere
		Kind.CAPSULE:
			var capsule := CapsuleMesh.new()
			capsule.radius = float(dimensions["radius"])
			capsule.height = float(dimensions["height"])
			return capsule
	var box := BoxMesh.new()
	box.size = Vector3(
		float(dimensions["width"]),
		float(dimensions["height"]),
		float(dimensions["depth"])
	)
	return box


static func kind_from_shape(shape: Shape3D) -> int:
	if shape is CylinderShape3D:
		return Kind.CYLINDER
	if shape is SphereShape3D:
		return Kind.SPHERE
	if shape is CapsuleShape3D:
		return Kind.CAPSULE
	return Kind.BOX


static func dimensions_from_shape(shape: Shape3D) -> Dictionary:
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return {"radius": cylinder.radius, "height": cylinder.height}
	if shape is SphereShape3D:
		return {"radius": (shape as SphereShape3D).radius}
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return {"radius": capsule.radius, "height": capsule.height}
	var box := shape as BoxShape3D
	if box != null:
		return {"width": box.size.x, "height": box.size.y, "depth": box.size.z}
	return normalized_dimensions(Kind.BOX, {})


static func local_half_extents(kind: int, values: Dictionary) -> Vector3:
	var dimensions := normalized_dimensions(kind, values)
	match clampi(kind, 0, DISPLAY_NAMES.size() - 1):
		Kind.CYLINDER, Kind.CAPSULE:
			return Vector3(
				float(dimensions["radius"]),
				float(dimensions["height"]) * 0.5,
				float(dimensions["radius"])
			)
		Kind.SPHERE:
			var radius := float(dimensions["radius"])
			return Vector3(radius, radius, radius)
	return Vector3(
		float(dimensions["width"]) * 0.5,
		float(dimensions["height"]) * 0.5,
		float(dimensions["depth"]) * 0.5
	)


static func vertical_half_extent(kind: int, values: Dictionary) -> float:
	return local_half_extents(kind, values).y


static func bounding_radius(kind: int, values: Dictionary) -> float:
	# Exact origin-centred bounding sphere for each primitive. Do not derive this from the AABB
	# half-extents: doing so overestimates rotationally symmetric shapes (a sphere would become
	# sqrt(3) times too large), which in turn makes target arrival/pickup radii misleading.
	var dimensions: Dictionary = normalized_dimensions(kind, values)
	match clampi(kind, 0, DISPLAY_NAMES.size() - 1):
		Kind.CYLINDER:
			var radius: float = float(dimensions["radius"])
			var half_height: float = float(dimensions["height"]) * 0.5
			return sqrt(radius * radius + half_height * half_height)
		Kind.SPHERE:
			return float(dimensions["radius"])
		Kind.CAPSULE:
			# Capsule height is total pole-to-pole height and normalized to at least 2r. The poles
			# are therefore the farthest points from the primitive origin.
			return float(dimensions["height"]) * 0.5
	return local_half_extents(Kind.BOX, dimensions).length()


static func support_extent_world(
	kind: int,
	values: Dictionary,
	basis: Basis,
	direction_world: Vector3
) -> float:
	# Distance from the primitive centre to its supporting plane in direction_world. Mouse
	# placement uses this instead of a world-Y AABB half-height so rotated items rest exactly on
	# sloped/upward-facing authored surfaces rather than being embedded or floating.
	if not direction_world.is_finite() or direction_world.length_squared() <= 0.000001:
		return 0.0
	var direction: Vector3 = direction_world.normalized()
	var safe_basis: Basis = basis
	if not safe_basis.is_finite() or safe_basis.determinant() <= 0.000001:
		safe_basis = Basis.IDENTITY
	else:
		safe_basis = safe_basis.orthonormalized()
	var dimensions: Dictionary = normalized_dimensions(kind, values)
	var axis_y_projection: float = absf(direction.dot(safe_basis.y))
	match clampi(kind, 0, DISPLAY_NAMES.size() - 1):
		Kind.CYLINDER:
			var radius: float = float(dimensions["radius"])
			var half_height: float = float(dimensions["height"]) * 0.5
			var radial_projection: float = sqrt(maxf(1.0 - axis_y_projection * axis_y_projection, 0.0))
			return half_height * axis_y_projection + radius * radial_projection
		Kind.SPHERE:
			return float(dimensions["radius"])
		Kind.CAPSULE:
			var radius: float = float(dimensions["radius"])
			var body_half_height: float = maxf(float(dimensions["height"]) * 0.5 - radius, 0.0)
			return body_half_height * axis_y_projection + radius
	var half: Vector3 = local_half_extents(Kind.BOX, dimensions)
	return (
		absf(direction.dot(safe_basis.x)) * half.x
		+ absf(direction.dot(safe_basis.y)) * half.y
		+ absf(direction.dot(safe_basis.z)) * half.z
	)


static func world_aabb(
	kind: int,
	values: Dictionary,
	transform: Transform3D
) -> AABB:
	var dimensions := normalized_dimensions(kind, values)
	var basis := transform.basis
	var extent := Vector3.ZERO
	match clampi(kind, 0, DISPLAY_NAMES.size() - 1):
		Kind.CYLINDER:
			var radius := float(dimensions["radius"])
			var half_height := float(dimensions["height"]) * 0.5
			extent = _axial_radial_world_extent(
				basis,
				half_height,
				radius
			)
		Kind.SPHERE:
			var radius := float(dimensions["radius"])
			extent = Vector3(
				radius * _basis_row_length(basis, 0),
				radius * _basis_row_length(basis, 1),
				radius * _basis_row_length(basis, 2)
			)
		Kind.CAPSULE:
			var radius := float(dimensions["radius"])
			var body_half_height := maxf(
				float(dimensions["height"]) * 0.5 - radius,
				0.0
			)
			extent = Vector3(
				absf(basis.y.x) * body_half_height
					+ radius * _basis_row_length(basis, 0),
				absf(basis.y.y) * body_half_height
					+ radius * _basis_row_length(basis, 1),
				absf(basis.y.z) * body_half_height
					+ radius * _basis_row_length(basis, 2)
			)
		_:
			var half := local_half_extents(Kind.BOX, dimensions)
			extent = Vector3(
				absf(basis.x.x) * half.x
					+ absf(basis.y.x) * half.y
					+ absf(basis.z.x) * half.z,
				absf(basis.x.y) * half.x
					+ absf(basis.y.y) * half.y
					+ absf(basis.z.y) * half.z,
				absf(basis.x.z) * half.x
					+ absf(basis.y.z) * half.y
					+ absf(basis.z.z) * half.z
			)
	return AABB(transform.origin - extent, extent * 2.0)


static func _axial_radial_world_extent(
	basis: Basis,
	half_height: float,
	radius: float
) -> Vector3:
	return Vector3(
		absf(basis.y.x) * half_height
			+ radius * sqrt(basis.x.x * basis.x.x + basis.z.x * basis.z.x),
		absf(basis.y.y) * half_height
			+ radius * sqrt(basis.x.y * basis.x.y + basis.z.y * basis.z.y),
		absf(basis.y.z) * half_height
			+ radius * sqrt(basis.x.z * basis.x.z + basis.z.z * basis.z.z)
	)


static func _basis_row_length(basis: Basis, row: int) -> float:
	return sqrt(
		basis.x[row] * basis.x[row]
		+ basis.y[row] * basis.y[row]
		+ basis.z[row] * basis.z[row]
	)
