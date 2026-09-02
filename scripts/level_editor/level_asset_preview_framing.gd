class_name LevelAssetPreviewFraming
extends RefCounted

## Shared deterministic framing for catalog thumbnails and the detailed preview.
## Thin geometry is shown broad-face; volumetric props receive a readable
## elevated three-quarter view. This avoids relying on inconsistent asset axes.

const PLANAR_RATIO := 0.52
const DEPTH_REVEAL := 0.16
const ELEVATION_REVEAL := 0.10
const FRAME_MARGIN := 1.18


static func camera_direction(bounds: AABB) -> Vector3:
	var dimensions := bounds.size.abs().max(Vector3.ONE * 0.0001)
	var ordered_axes := [0, 1, 2]
	ordered_axes.sort_custom(func(a: int, b: int) -> bool:
		return dimensions[a] < dimensions[b]
	)
	var thinnest_axis: int = ordered_axes[0]
	var second_dimension: float = dimensions[ordered_axes[1]]
	if dimensions[thinnest_axis] <= second_dimension * PLANAR_RATIO:
		var direction := _axis_vector(thinnest_axis)
		if thinnest_axis == 1:
			# Floors and other horizontal sheets read best from mostly above.
			direction += Vector3(DEPTH_REVEAL, 0.0, DEPTH_REVEAL)
		else:
			# Preserve the broad face while revealing just enough top/side depth.
			direction += Vector3.UP * ELEVATION_REVEAL
			var horizontal_reveal := 2 if thinnest_axis == 0 else 0
			direction += _axis_vector(horizontal_reveal) * DEPTH_REVEAL
		return direction.normalized()
	return Vector3(1.0, 0.52, 1.0).normalized()


static func frame(
	bounds: AABB,
	aspect_ratio := 4.0 / 3.0,
	direction_override := Vector3.ZERO,
	zoom := 1.0
) -> Dictionary:
	var direction := (
		direction_override.normalized()
		if direction_override.length_squared() > 0.000001
		else camera_direction(bounds)
	)
	var up_hint := (
		Vector3.FORWARD
		if absf(direction.dot(Vector3.UP)) > 0.94
		else Vector3.UP
	)
	var right := up_hint.cross(direction).normalized()
	if right.length_squared() <= 0.000001:
		right = Vector3.RIGHT
	var view_up := direction.cross(right).normalized()
	var half_horizontal := 0.0
	var half_vertical := 0.0
	var half_depth := 0.0
	var half_size := bounds.size.abs() * 0.5
	for x_sign: float in [-1.0, 1.0]:
		for y_sign: float in [-1.0, 1.0]:
			for z_sign: float in [-1.0, 1.0]:
				var corner := Vector3(
					half_size.x * x_sign,
					half_size.y * y_sign,
					half_size.z * z_sign
				)
				half_horizontal = maxf(half_horizontal, absf(corner.dot(right)))
				half_vertical = maxf(half_vertical, absf(corner.dot(view_up)))
				half_depth = maxf(half_depth, absf(corner.dot(direction)))
	var safe_aspect := maxf(aspect_ratio, 0.1)
	var orthographic_size := maxf(
		half_vertical * 2.0,
		half_horizontal * 2.0 / safe_aspect
	)
	orthographic_size = maxf(orthographic_size * FRAME_MARGIN * zoom, 0.25)
	var extent := maxf(
		maxf(bounds.size.x, bounds.size.y),
		maxf(bounds.size.z, 0.25)
	)
	var distance := maxf(extent * 2.25 + half_depth, 1.0)
	return {
		"direction": direction,
		"up": view_up,
		"position": direction * distance,
		"size": orthographic_size,
		"near": maxf(extent * 0.001, 0.01),
		"far": maxf(distance + extent * 5.0, 100.0),
	}


static func _axis_vector(axis_index: int) -> Vector3:
	match axis_index:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		_:
			return Vector3.BACK
