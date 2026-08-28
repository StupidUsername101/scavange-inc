class_name NetworkSnapshotStreamTracker
extends RefCounted

## Suppresses repeated empty full-snapshot streams without losing lifecycle clears. A non-empty
## stream publishes normally. Its first empty state publishes once to delete client proxies; later
## stable-empty ticks are silent. Joining peers can force one complete publication per stream.

var _active_streams: Dictionary[StringName, bool] = {}
var _forced_streams: Dictionary[StringName, bool] = {}


func should_publish(stream_id: StringName, has_entities: bool) -> bool:
	if stream_id.is_empty():
		return true
	var forced := _forced_streams.erase(stream_id)
	if has_entities:
		_active_streams[stream_id] = true
		return true
	if _active_streams.erase(stream_id):
		return true
	return forced


func force_next_publish(stream_id: StringName) -> void:
	if not stream_id.is_empty():
		_forced_streams[stream_id] = true


func is_active(stream_id: StringName) -> bool:
	return _active_streams.has(stream_id)


func reset() -> void:
	_active_streams.clear()
	_forced_streams.clear()
