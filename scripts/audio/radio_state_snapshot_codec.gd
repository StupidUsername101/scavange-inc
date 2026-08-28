class_name RadioStateSnapshotCodec
extends RefCounted

const VERSION := 1
const MAX_SOURCE_COUNT := 64
const MAX_COMPRESSED_BYTES := 64 * 1024
const MAX_DECOMPRESSED_BYTES := 256 * 1024
const COMPRESSION_MODE := FileAccess.COMPRESSION_DEFLATE

#######################################################
# Compacts the verbose, repeated-key continuous-audio dictionaries before they cross Steam.
# This layer only owns bounded serialization; RadioAudioRenderer performs the one strict sanitation
# pass at the client boundary. bytes_to_var is never allowed to create objects.
#######################################################


static func encode(states: Dictionary) -> PackedByteArray:
	if states.size() > MAX_SOURCE_COUNT:
		return PackedByteArray()
	var serialized := var_to_bytes([VERSION, states])
	if serialized.is_empty() or serialized.size() > MAX_DECOMPRESSED_BYTES:
		return PackedByteArray()
	var compressed := serialized.compress(COMPRESSION_MODE)
	if compressed.is_empty() or compressed.size() > MAX_COMPRESSED_BYTES:
		return PackedByteArray()
	return compressed


static func decode(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty() or payload.size() > MAX_COMPRESSED_BYTES:
		return {}
	var serialized := payload.decompress_dynamic(
		MAX_DECOMPRESSED_BYTES,
		COMPRESSION_MODE
	)
	if serialized.is_empty():
		return {}
	var envelope: Variant = bytes_to_var(serialized)
	if not envelope is Array:
		return {}
	var values := envelope as Array
	if (
		values.size() != 2
		or SafeVariant.integral_int_or(values[0], -1) != VERSION
		or not values[1] is Dictionary
	):
		return {}
	var raw_states := values[1] as Dictionary
	if raw_states.size() > MAX_SOURCE_COUNT:
		return {}
	return raw_states
