class_name MLBodyPartCatalog
extends RefCounted

#######################################################
# Lightweight creator catalogue. Authored body parts stay in .tres files; the UI discovers them
# from the resource tree and filters them through the same MLBodySlotDefinition.accepts() contract
# used when a draft is finalized. No part list is duplicated in UI code.
#######################################################

const RESOURCE_ROOT: String = "res://resources"
const LEGACY_AI_CHIP_ROOT: String = "res://resources/drones/ai_chips"
const CREATOR_ARTICULATED_LIMB_PATH: String = (
	"res://resources/model_forge/attachments/configurable_articulated_limb.tres"
)

static var _cached_parts: Array[Resource] = []
static var _cache_ready: bool = false


static func all_parts() -> Array[Resource]:
	_ensure_cache()
	return _cached_parts.duplicate()


static func compatible_parts(slot: MLBodySlotDefinition) -> Array[Resource]:
	var result: Array[Resource] = []
	if slot == null:
		return result
	_ensure_cache()
	for part: Resource in _cached_parts:
		if part != null and slot.accepts(part) and creator_compatibility_error(part).is_empty():
			result.append(part)
	return result


static func creator_compatibility_error(part: Resource) -> String:
	if part == null:
		return ""
	var source_path: String = MLBodyPartContract.resource_source_path(part)
	# GenericLimbDefinition resources are nested anatomy, not alternative top-level hardware. The
	# creator exposes exactly one articulated attachment and edits its nested limb in place. Legacy
	# utility/grabber limb attachments stay loadable for existing presets but do not compete with the
	# generic model-forge limb in the picker.
	if part is GenericLimbDefinition:
		return "Nested limb definitions are edited through the articulated-limb attachment."
	if part is DroneLimbAttachmentDefinition and source_path != CREATOR_ARTICULATED_LIMB_PATH:
		return "Legacy articulated attachments are not separate creator limb variants."
	if part is DroneCameraAttachmentDefinition:
		if source_path.ends_with("/training_observer_camera.tres"):
			return "The training observer is instrumentation, not authored model hardware."
	# Passive attachments are allowed: they can intentionally change mass/shape without consuming
	# action channels. A non-limb attachment that *declares* controls is different—the current
	# ServerDrone runtime has no generic actuator node for it, so accepting it would silently drop
	# policy outputs. Articulated limb attachments have a concrete GenericLimbAssembly3D consumer.
	if part is DroneAttachmentDefinition and not (part is DroneLimbAttachmentDefinition):
		var controls: Array[Dictionary] = MLBodyPartContract.control_descriptors(part)
		if not controls.is_empty():
			return "Attachment declares model controls but has no supported ServerDrone runtime adapter."
	if part is DroneLimbAttachmentDefinition:
		var limb_controls: Array[Dictionary] = MLBodyPartContract.control_descriptors(part)
		var limb_observations: Array[Dictionary] = MLBodyPartContract.observation_descriptors(part)
		if limb_controls.is_empty():
			return "Articulated attachment declares no model controls."
		if limb_observations.is_empty():
			return "Articulated attachment declares no model observations."
	return ""


static func display_name(part: Resource) -> String:
	if part == null:
		return "Empty"
	var property_names: Dictionary = {}
	for property_value: Variant in part.get_property_list():
		if property_value is Dictionary:
			property_names[str((property_value as Dictionary).get("name", ""))] = true
	for candidate: String in ["display_name", "limb_name", "part_name", "name"]:
		if property_names.has(candidate):
			var value: String = str(part.get(candidate)).strip_edges()
			if not value.is_empty():
				return value
	var source_path: String = MLBodyPartContract.resource_source_path(part)
	if not source_path.is_empty():
		return source_path.get_file().get_basename().replace("_", " ").capitalize()
	return part.get_class()


static func _ensure_cache() -> void:
	if _cache_ready:
		return
	_cache_ready = true
	_cached_parts.clear()
	var paths: Array[String] = []
	_collect_resource_paths(RESOURCE_ROOT, paths)
	paths.sort()
	for path: String in paths:
		var resource: Resource = load(path) as Resource
		if resource == null:
			continue
		# The model forge replaces the old scripted AI-chip system; those legacy gameplay parts must
		# never appear as selectable model-body hardware.
		if MLBodyPartContract.part_tags(resource).has(&"ai_chip"):
			continue
		# Slot filtering below is authoritative. Caching only resources with an explicit model-part
		# method avoids pulling unrelated maps/items/loadouts into every creator dropdown.
		if resource.has_method("ml_part_tags") and creator_compatibility_error(resource).is_empty():
			_cached_parts.append(resource)


static func _collect_resource_paths(directory_path: String, target: Array[String]) -> void:
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
		if child_path == LEGACY_AI_CHIP_ROOT or child_path.begins_with(LEGACY_AI_CHIP_ROOT + "/"):
			continue
		if directory.current_is_dir():
			_collect_resource_paths(child_path, target)
		elif entry.get_extension().to_lower() in ["tres", "res"]:
			target.append(child_path)
	directory.list_dir_end()
