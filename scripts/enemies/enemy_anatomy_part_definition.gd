@tool
class_name EnemyAnatomyPartDefinition
extends Resource

## Authored material volume and presentation binding for one destructible enemy body part.

@export_group("Identity")
@export var part_id: StringName = &"part"
@export var vital := false
@export var severable := false

@export_group("Material Volume")
@export var local_center := Vector3.ZERO
@export var size := Vector3.ONE
@export_range(0.0, 1.0, 0.001) var contribution_weight := 1.0
@export_range(0.0, 1.0, 0.001) var remaining_threshold := 0.35
## Local anatomical points whose removal is immediately fatal for a vital part.
@export var critical_points: PackedVector3Array = PackedVector3Array()

@export_group("Animated Presentation")
## Empty bone names make the part use the enemy root transform. A start/end pair maps the authored
## rest axis onto an animated skeleton segment without making the damage simulation depend on bones.
@export var presentation_start_bone: StringName = &""
@export var presentation_end_bone: StringName = &""
@export var rest_axis_start := Vector3.ZERO
@export var rest_axis_end := Vector3.ZERO

@export_group("Severed Surface")
@export var stump_local_position := Vector3.ZERO
## Points from the exposed cut into the body, never outward into the now-empty limb space.
@export var stump_inward_direction := Vector3.UP
@export_range(0.005, 1.0, 0.005, "or_greater") var stump_radius := 0.08


func sanitized_size() -> Vector3:
	return Vector3(
		maxf(absf(size.x), 0.02),
		maxf(absf(size.y), 0.02),
		maxf(absf(size.z), 0.02)
	)


func contains_local_point(point: Vector3) -> bool:
	var half := sanitized_size() * 0.5
	var offset := point - local_center
	return (
		absf(offset.x) <= half.x
		and absf(offset.y) <= half.y
		and absf(offset.z) <= half.z
	)


func normalized_center_distance_squared(point: Vector3) -> float:
	var half := sanitized_size() * 0.5
	var offset := point - local_center
	return (
		offset.x * offset.x / (half.x * half.x)
		+ offset.y * offset.y / (half.y * half.y)
		+ offset.z * offset.z / (half.z * half.z)
	)


func distance_to_volume(point: Vector3) -> float:
	var half := sanitized_size() * 0.5
	var offset := (point - local_center).abs() - half
	return Vector3(
		maxf(offset.x, 0.0),
		maxf(offset.y, 0.0),
		maxf(offset.z, 0.0)
	).length()


func project_to_volume(point: Vector3) -> Vector3:
	var half := sanitized_size() * 0.5
	var offset := point - local_center
	return local_center + Vector3(
		clampf(offset.x, -half.x, half.x),
		clampf(offset.y, -half.y, half.y),
		clampf(offset.z, -half.z, half.z)
	)


func structural_anchor_mask() -> int:
	# The animated rest axis is authored from the body attachment toward the distal joint. Anchor the
	# finite SDF on the face nearest that attachment, so a cut frees the hand/foot side instead of
	# accidentally preserving it. Zero-length severable parts use their authored stump direction;
	# nonseverable core volumes retain their grounded base anchor.
	var toward_attachment := rest_axis_start - rest_axis_end
	if toward_attachment.length_squared() <= 0.000001:
		toward_attachment = (
			stump_inward_direction
			if severable
			else Vector3.DOWN
		)
	if toward_attachment.length_squared() <= 0.000001:
		return SdfStructuralFragmenter.ANCHOR_NEGATIVE_Y
	var absolute_direction := toward_attachment.abs()
	if absolute_direction.x >= absolute_direction.y and absolute_direction.x >= absolute_direction.z:
		return (
			SdfStructuralFragmenter.ANCHOR_POSITIVE_X
			if toward_attachment.x >= 0.0
			else SdfStructuralFragmenter.ANCHOR_NEGATIVE_X
		)
	if absolute_direction.y >= absolute_direction.z:
		return (
			SdfStructuralFragmenter.ANCHOR_POSITIVE_Y
			if toward_attachment.y >= 0.0
			else SdfStructuralFragmenter.ANCHOR_NEGATIVE_Y
		)
	return (
		SdfStructuralFragmenter.ANCHOR_POSITIVE_Z
		if toward_attachment.z >= 0.0
		else SdfStructuralFragmenter.ANCHOR_NEGATIVE_Z
	)
