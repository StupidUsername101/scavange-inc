class_name VoiceFrameJitterBuffer
extends RefCounted

## Tiny bounded reorder window for short-lived voice. New speech never queues behind arbitrarily
## late packets: duplicates and old generations are discarded, gaps are concealed after a short
## hold, and the queue has a hard packet ceiling.

const MAX_PACKETS := 8
const TARGET_PACKETS := 2
const MAX_HOLD_MILLISECONDS := 45

var generation := -1
var last_emitted_sequence := 0
var _packets: Array[Dictionary] = []


func reset(next_generation := -1) -> void:
	generation = next_generation
	last_emitted_sequence = 0
	_packets.clear()


func push(packet: Dictionary, received_msec: int) -> bool:
	var packet_generation := int(packet.get("generation", -1))
	var sequence := int(packet.get("voice_sequence", -1))
	if packet_generation < 0 or sequence <= 0:
		return false
	if generation != packet_generation:
		reset(packet_generation)
	if sequence <= last_emitted_sequence:
		return false
	for existing: Dictionary in _packets:
		if int(existing.get("voice_sequence", -1)) == sequence:
			return false
	var queued := packet.duplicate(false)
	queued["_received_msec"] = maxi(received_msec, 0)
	var insert_index := _packets.size()
	for packet_index: int in range(_packets.size()):
		if sequence < int(_packets[packet_index].get("voice_sequence", 0)):
			insert_index = packet_index
			break
	_packets.insert(insert_index, queued)
	if _packets.size() > MAX_PACKETS:
		# Prefer fresh speech over a packet that has already spent the longest time waiting.
		_packets.pop_front()
	return true


func drain_ready(now_msec: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	while not _packets.is_empty():
		var oldest := _packets[0]
		var oldest_age := maxi(
			now_msec - int(oldest.get("_received_msec", now_msec)),
			0
		)
		var sequence := int(oldest.get("voice_sequence", -1))
		var next_expected := last_emitted_sequence + 1
		var contiguous := last_emitted_sequence == 0 or sequence == next_expected
		if (
			not contiguous
			and _packets.size() < TARGET_PACKETS
			and oldest_age < MAX_HOLD_MILLISECONDS
		):
			break
		if (
			result.is_empty()
			and _packets.size() < TARGET_PACKETS
			and oldest_age < MAX_HOLD_MILLISECONDS
		):
			break
		_packets.pop_front()
		oldest.erase("_received_msec")
		last_emitted_sequence = sequence
		result.append(oldest)
	return result


func queued_packet_count() -> int:
	return _packets.size()
