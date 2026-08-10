class_name MLBodyLimbEditor
extends RefCounted

const DEFAULT_SEGMENT_TEMPLATE_PATH: String = (
	"res://resources/model_forge/limbs/articulated_segment.tres"
)
const END_EFFECTOR_TEMPLATE_ROOT: String = "res://resources/model_forge/end_effectors"

#######################################################
# Mutates only the private Resource copies stored inside an MLBodyBuildDraft. The creator UI uses
# this helper so generic limb topology is authored through GenericLimbDefinition itself instead of
# maintaining a second, UI-only anatomy representation.
#######################################################


static func editable_limbs(part: Resource) -> Array[GenericLimbDefinition]:
	var result: Array[GenericLimbDefinition] = []
	if part is GenericLimbDefinition:
		result.append(part as GenericLimbDefinition)
		return result
	if part is DroneLimbAttachmentDefinition:
		var host: DroneLimbAttachmentDefinition = part as DroneLimbAttachmentDefinition
		for limb: GenericLimbDefinition in host.limb_definitions:
			if limb != null:
				result.append(limb)
	return result


static func set_segment_count(part: Resource, limb_index: int, requested_count: int) -> String:
	var limb: GenericLimbDefinition = _limb_at(part, limb_index)
	if limb == null:
		return "The selected part does not contain that editable limb."
	var target_count: int = maxi(requested_count, 1)
	while limb.segments.size() < target_count:
		var source: LimbSegmentDefinition = null
		if not limb.segments.is_empty():
			source = limb.segments[limb.segments.size() - 1]
		if source == null:
			source = load(DEFAULT_SEGMENT_TEMPLATE_PATH) as LimbSegmentDefinition
		if source == null:
			return "No saved segment template is available for extending this limb."
		var added: LimbSegmentDefinition = (
			MLBodyPartContract.deep_duplicate_resource(source) as LimbSegmentDefinition
		)
		if added == null or added.joint == null:
			return "The saved segment template is missing its joint definition."
		added.segment_name = "Segment %d" % (limb.segments.size() + 1)
		added.joint.joint_name = "Joint %d" % (limb.segments.size() + 1)
		added.joint.action_indices = Vector3i(-1, -1, -1)
		limb.segments.append(added)
	while limb.segments.size() > target_count:
		limb.segments.remove_at(limb.segments.size() - 1)
	limb.sanitize()
	limb.pack_action_indices(0)
	return limb.ml_validation_error()


static func set_segment_dimensions(
	part: Resource,
	limb_index: int,
	segment_index: int,
	length: float,
	radius: float,
	mass: float
) -> String:
	var limb: GenericLimbDefinition = _limb_at(part, limb_index)
	if limb == null or segment_index < 0 or segment_index >= limb.segments.size():
		return "The selected limb segment no longer exists."
	var segment: LimbSegmentDefinition = limb.segments[segment_index]
	if segment == null:
		return "The selected limb segment is missing its saved definition."
	segment.length = length
	segment.radius = radius
	segment.mass = mass
	segment.sanitize()
	limb.sanitize()
	return limb.ml_validation_error()


static func set_end_effector(
	part: Resource,
	limb_index: int,
	template: LimbEndEffectorDefinition
) -> String:
	var limb: GenericLimbDefinition = _limb_at(part, limb_index)
	if limb == null:
		return "The selected part does not contain that editable limb."
	if template == null:
		limb.end_effector = null
	else:
		limb.end_effector = (
			MLBodyPartContract.deep_duplicate_resource(template) as LimbEndEffectorDefinition
		)
		if limb.end_effector == null:
			return "The selected end attachment could not be copied into the body draft."
	limb.sanitize()
	limb.pack_action_indices(0)
	return limb.ml_validation_error()


static func end_effector_templates() -> Array[LimbEndEffectorDefinition]:
	var paths: Array[String] = []
	_collect_tres_paths(END_EFFECTOR_TEMPLATE_ROOT, paths)
	paths.sort()
	var result: Array[LimbEndEffectorDefinition] = []
	for path: String in paths:
		var definition: LimbEndEffectorDefinition = load(path) as LimbEndEffectorDefinition
		if definition != null:
			result.append(definition)
	return result


static func end_effector_template_key(definition: LimbEndEffectorDefinition) -> String:
	if definition == null:
		return ""
	var source_path: String = MLBodyPartContract.resource_source_path(definition)
	if not source_path.is_empty():
		return source_path
	return "%s:%d:%d" % [
		str(definition.effector_type_id),
		definition.geometry_type,
		definition.grip_mode,
	]


static func matching_end_effector_template_index(
	current: LimbEndEffectorDefinition,
	templates: Array[LimbEndEffectorDefinition]
) -> int:
	if current == null:
		return -1
	var current_source: String = MLBodyPartContract.resource_source_path(current)
	if not current_source.is_empty():
		for index: int in range(templates.size()):
			if MLBodyPartContract.resource_source_path(templates[index]) == current_source:
				return index
	for index: int in range(templates.size()):
		var candidate: LimbEndEffectorDefinition = templates[index]
		if (
			candidate != null
			and candidate.effector_type_id == current.effector_type_id
			and candidate.geometry_type == current.geometry_type
			and candidate.grip_mode == current.grip_mode
		):
			return index
	return -1


static func _limb_at(part: Resource, limb_index: int) -> GenericLimbDefinition:
	var limbs: Array[GenericLimbDefinition] = editable_limbs(part)
	if limb_index < 0 or limb_index >= limbs.size():
		return null
	return limbs[limb_index]


static func _collect_tres_paths(directory_path: String, target: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		var child_path: String = directory_path.path_join(entry)
		if directory.current_is_dir():
			_collect_tres_paths(child_path, target)
		elif entry.get_extension().to_lower() in ["tres", "res"]:
			target.append(child_path)
	directory.list_dir_end()
