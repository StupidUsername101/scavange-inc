class_name MLBodyPartCatalog
extends RefCounted

#######################################################
# Lightweight creator catalogue. Authored body parts stay in .tres files; the UI discovers them
# from the resource tree and filters them through the same MLBodySlotDefinition.accepts() contract
# used when a draft is finalized. No part list is duplicated in UI code.
#######################################################

const RESOURCE_ROOT: String = "res://resources"

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
		if part != null and slot.accepts(part):
			result.append(part)
	return result


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
		# Slot filtering below is authoritative. Caching only resources with an explicit model-part
		# method avoids pulling unrelated maps/items/loadouts into every creator dropdown.
		if resource.has_method("ml_part_tags"):
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
		if directory.current_is_dir():
			_collect_resource_paths(child_path, target)
		elif entry.get_extension().to_lower() in ["tres", "res"]:
			target.append(child_path)
	directory.list_dir_end()
