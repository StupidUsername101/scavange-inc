class_name AcousticBakeArtifact
extends RefCounted

## Versioned binary container for static acoustic preprocessing. The file contains only Variant
## value types; resources and executable objects are never deserialized from the cache.

const MAGIC := 0x53414342 # "SACB"
const SCHEMA_VERSION := 1
const MAX_BAKE_BYTES := 128 * 1024 * 1024


static func load_validated(path: String, expected_signature: String) -> Dictionary:
	if path.is_empty() or expected_signature.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 12 or file.get_length() > MAX_BAKE_BYTES:
		return {}
	if file.get_32() != MAGIC or file.get_32() != SCHEMA_VERSION:
		file.close()
		return {}
	var payload_size := int(file.get_32())
	if payload_size <= 0 or payload_size != file.get_length() - file.get_position():
		file.close()
		return {}
	var payload_bytes := file.get_buffer(payload_size)
	file.close()
	var payload: Variant = bytes_to_var(payload_bytes)
	if not payload is Dictionary:
		return {}
	var result := payload as Dictionary
	if (
		int(result.get("schema_version", -1)) != SCHEMA_VERSION
		or str(result.get("signature", "")) != expected_signature
		or not result.get("graph", null) is Dictionary
		or not result.get("static_boundaries", null) is Dictionary
	):
		return {}
	return result


static func save_atomic(
	path: String,
	signature: String,
	graph_data: Dictionary,
	static_boundary_data: Dictionary
) -> bool:
	if (
		path.is_empty()
		or signature.is_empty()
		or graph_data.is_empty()
		or static_boundary_data.is_empty()
	):
		return false
	var payload := {
		"schema_version": SCHEMA_VERSION,
		"signature": signature,
		"graph": graph_data,
		"static_boundaries": static_boundary_data,
	}
	var payload_bytes := var_to_bytes(payload)
	if payload_bytes.is_empty() or payload_bytes.size() > MAX_BAKE_BYTES:
		return false
	var directory_path := path.get_base_dir()
	if not directory_path.is_empty():
		var directory := DirAccess.open(directory_path)
		if directory == null:
			var root := DirAccess.open("user://" if path.begins_with("user://") else "res://")
			if root == null:
				return false
			var relative_directory := directory_path.trim_prefix(
				"user://" if path.begins_with("user://") else "res://"
			)
			if root.make_dir_recursive(relative_directory) != OK:
				return false
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_32(MAGIC)
	file.store_32(SCHEMA_VERSION)
	file.store_32(payload_bytes.size())
	file.store_buffer(payload_bytes)
	file.flush()
	file.close()
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null:
		return false
	var final_name := path.get_file()
	var temporary_name := temporary_path.get_file()
	var previous_name := final_name + ".previous"
	if directory.file_exists(previous_name):
		if directory.remove(previous_name) != OK:
			directory.remove(temporary_name)
			return false
	var had_previous_artifact := directory.file_exists(final_name)
	if had_previous_artifact:
		if directory.rename(final_name, previous_name) != OK:
			directory.remove(temporary_name)
			return false
	if directory.rename(temporary_name, final_name) != OK:
		# A failed replacement must not destroy the last usable bake. The next startup can either
		# load this restored artifact or reject its signature and perform the ordinary rebuild.
		if had_previous_artifact:
			directory.rename(previous_name, final_name)
		directory.remove(temporary_name)
		return false
	if had_previous_artifact:
		directory.remove(previous_name)
	return true
