class_name DestructionCheckpointStore
extends RefCounted

## Versioned, value-only persistence for changed destruction bricks. The immutable base geometry is
## never duplicated in a save; its bake hash is the compatibility boundary.

const MAGIC := "SCVSDF01"
const SCHEMA_VERSION := 1
const MAX_PAYLOAD_BYTES := 256 * 1024 * 1024


static func snapshot_for_volumes(
	volumes: Array[DestructibleVolume3D],
	world_id: StringName = &"game"
) -> Dictionary:
	var ordered := volumes.duplicate()
	ordered.sort_custom(func(left: DestructibleVolume3D, right: DestructibleVolume3D) -> bool:
		return str(left.volume_id) < str(right.volume_id)
	)
	var checkpoints: Array[Dictionary] = []
	for volume: DestructibleVolume3D in ordered:
		if volume != null:
			checkpoints.append(volume.checkpoint())
	return {
		"schema": SCHEMA_VERSION,
		"world_id": world_id,
		"volumes": checkpoints,
	}


static func apply_snapshot(
	snapshot: Dictionary,
	volumes_by_id: Dictionary[StringName, DestructibleVolume3D]
) -> Dictionary:
	if int(snapshot.get("schema", -1)) != SCHEMA_VERSION:
		return {"ok": false, "reason": &"schema_mismatch", "applied": 0, "rejected": 0}
	var raw_checkpoints: Variant = snapshot.get("volumes", [])
	if not raw_checkpoints is Array:
		return {"ok": false, "reason": &"invalid_volumes", "applied": 0, "rejected": 0}
	var applied := 0
	var rejected := 0
	var missing := 0
	for raw_checkpoint: Variant in raw_checkpoints:
		if not raw_checkpoint is Dictionary:
			rejected += 1
			continue
		var volume_id := StringName(str(raw_checkpoint.get("volume_id", &"")))
		var volume := volumes_by_id.get(volume_id) as DestructibleVolume3D
		if volume == null:
			missing += 1
			continue
		if volume.apply_checkpoint(raw_checkpoint):
			applied += 1
		else:
			rejected += 1
	return {
		"ok": rejected == 0,
		"reason": &"" if rejected == 0 else &"checkpoint_rejected",
		"applied": applied,
		"rejected": rejected,
		"missing": missing,
	}


static func save_snapshot(path: String, snapshot: Dictionary) -> Error:
	if path.is_empty():
		return ERR_INVALID_PARAMETER
	var payload := var_to_bytes(snapshot)
	if payload.is_empty() or payload.size() > MAX_PAYLOAD_BYTES:
		return ERR_OUT_OF_MEMORY
	var compressed := payload.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty():
		return ERR_CANT_CREATE
	var temporary_path := "%s.tmp" % path
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(MAGIC.to_utf8_buffer())
	file.store_32(SCHEMA_VERSION)
	file.store_64(payload.size())
	file.store_64(compressed.size())
	file.store_buffer(_sha256(payload))
	file.store_buffer(compressed)
	file.flush()
	file.close()
	# A failed replacement leaves the previous file or the complete temporary file available.
	var backup_path := "%s.bak" % path
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path(backup_path)
		)
		if backup_error != OK:
			return backup_error
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(path)
	)
	if rename_error != OK and FileAccess.file_exists(backup_path):
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(backup_path),
			ProjectSettings.globalize_path(path)
		)
	return rename_error


static func load_snapshot(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var magic_bytes := file.get_buffer(MAGIC.length())
	if magic_bytes.get_string_from_utf8() != MAGIC:
		return {}
	var schema := file.get_32()
	var uncompressed_size := file.get_64()
	var compressed_size := file.get_64()
	var expected_digest := file.get_buffer(32)
	if (
		schema != SCHEMA_VERSION
		or uncompressed_size <= 0
		or uncompressed_size > MAX_PAYLOAD_BYTES
		or compressed_size <= 0
		or compressed_size > MAX_PAYLOAD_BYTES
		or expected_digest.size() != 32
		or file.get_position() + compressed_size != file.get_length()
	):
		return {}
	var compressed := file.get_buffer(compressed_size)
	var payload := compressed.decompress(uncompressed_size, FileAccess.COMPRESSION_ZSTD)
	if payload.size() != uncompressed_size or _sha256(payload) != expected_digest:
		return {}
	var decoded: Variant = bytes_to_var(payload)
	return decoded if decoded is Dictionary else {}


static func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if context.update(bytes) != OK:
		return PackedByteArray()
	return context.finish()
