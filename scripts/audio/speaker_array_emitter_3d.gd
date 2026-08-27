@tool
class_name SpeakerArrayEmitter3D
extends Marker3D

## One authored cabinet in a SpeakerArrayController scene.
##
## The controller discovers these markers recursively. `sort_order` only makes emitter IDs stable
## when scene-tree order changes; ties are resolved by scene path, so arbitrary counts are valid.

@export var sort_order := 0
@export var is_indoor := true
@export_range(-24.0, 12.0, 0.1) var installation_gain_db := 0.0
@export var source_offset := Vector3(0.0, 0.0, 0.36)
@export var cabinet_size := Vector3(0.92, 1.34, 0.42)


func source_position_relative_to(array_root: Node3D) -> Vector3:
	var safe_offset := source_offset if source_offset.is_finite() else Vector3.ZERO
	return transform_relative_to(array_root) * safe_offset


func transform_relative_to(array_root: Node3D) -> Transform3D:
	if array_root == null:
		return Transform3D.IDENTITY
	var relative_transform := transform
	var ancestor := get_parent()
	while ancestor != null and ancestor != array_root:
		if ancestor is Node3D:
			relative_transform = (
				(ancestor as Node3D).transform * relative_transform
			)
		ancestor = ancestor.get_parent()
	return relative_transform if ancestor == array_root else Transform3D.IDENTITY


func sanitized_cabinet_size() -> Vector3:
	if not cabinet_size.is_finite():
		return Vector3(0.92, 1.34, 0.42)
	var absolute_size := cabinet_size.abs()
	return Vector3(
		maxf(absolute_size.x, 0.05),
		maxf(absolute_size.y, 0.05),
		maxf(absolute_size.z, 0.05)
	)
