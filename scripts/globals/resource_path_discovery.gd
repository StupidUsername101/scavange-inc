class_name ResourcePathDiscovery
extends RefCounted

#######################################################
# Dependency-free recursive discovery for authored resource files. Callers own filtering/loading;
# this helper only keeps directory traversal, extension matching, and excluded subtrees consistent.
#######################################################


static func collect(
	root_path: String,
	extensions: Array[String] = ["tres", "res"],
	excluded_roots: Array[String] = []
) -> Array[String]:
	var result: Array[String] = []
	var normalized_extensions: Dictionary = _extension_lookup(extensions)
	var normalized_root_path: String = _normalized_root(root_path)
	if normalized_root_path.is_empty() or normalized_extensions.is_empty():
		return result
	var normalized_exclusions: Array[String] = []
	for excluded_root: String in excluded_roots:
		var normalized_root: String = _normalized_root(excluded_root)
		if not normalized_root.is_empty():
			normalized_exclusions.append(normalized_root)
	_collect_recursive(
		normalized_root_path,
		normalized_extensions,
		normalized_exclusions,
		result
	)
	result.sort()
	return result


static func collect_shallow(
	root_path: String,
	extensions: Array[String] = ["tres", "res"]
) -> Array[String]:
	var result: Array[String] = []
	var normalized_extensions: Dictionary = _extension_lookup(extensions)
	var normalized_root_path: String = _normalized_root(root_path)
	if normalized_root_path.is_empty() or normalized_extensions.is_empty():
		return result
	var directory: DirAccess = DirAccess.open(normalized_root_path)
	if directory == null:
		return result
	for file_name: String in directory.get_files():
		if normalized_extensions.has(file_name.get_extension().to_lower()):
			result.append(normalized_root_path.path_join(file_name))
	result.sort()
	return result


static func _extension_lookup(extensions: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for extension_value: String in extensions:
		var normalized_extension: String = extension_value.to_lower().trim_prefix(".")
		if not normalized_extension.is_empty():
			result[normalized_extension] = true
	return result


static func _collect_recursive(
	directory_path: String,
	extensions: Dictionary,
	excluded_roots: Array[String],
	target: Array[String]
) -> void:
	if _is_excluded(directory_path, excluded_roots):
		return
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = directory_path.path_join(entry)
			if not _is_excluded(child_path, excluded_roots):
				if directory.current_is_dir():
					_collect_recursive(child_path, extensions, excluded_roots, target)
				elif extensions.has(entry.get_extension().to_lower()):
					target.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()


static func _is_excluded(path: String, excluded_roots: Array[String]) -> bool:
	for excluded_root: String in excluded_roots:
		if path == excluded_root or path.begins_with(excluded_root + "/"):
			return true
	return false


static func _normalized_root(path: String) -> String:
	var result: String = path.strip_edges()
	while result.ends_with("/") and not result.ends_with("://"):
		result = result.trim_suffix("/")
	return result
