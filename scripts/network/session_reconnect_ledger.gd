class_name SessionReconnectLedger
extends RefCounted

const DEFAULT_GRACE_MILLISECONDS := 20000
const CLIENT_RETRY_WINDOW_MILLISECONDS := 15000
## Steam P2P symmetric connections retain a short native teardown lifetime after CloseConnection.
## Reopening the same identity/virtual-port pair immediately can let an old connection epoch race
## the replacement. Keep recovery sub-second, but give both endpoints time to retire their SNP lane
## counters before creating the first replacement connection.
const FIRST_RETRY_DELAY_MILLISECONDS := 600
const MAX_RETRY_DELAY_MILLISECONDS := 1200

#######################################################
# Tracks authoritative player leases across short transport outages. Steam identity, rather than
# the ephemeral SceneMultiplayer peer route, owns a lease. This keeps reconnect policy independent
# from the world entities whose state it protects.
#######################################################

var grace_milliseconds := DEFAULT_GRACE_MILLISECONDS
var _leases_by_steam_id: Dictionary[int, Dictionary] = {}


func _init(grace_value := DEFAULT_GRACE_MILLISECONDS) -> void:
	grace_milliseconds = maxi(grace_value, 1)


func suspend(
	steam_id: int,
	player_id: int,
	peer_id: int,
	now_milliseconds: int
) -> bool:
	if steam_id <= 0 or player_id < 0 or peer_id <= 0:
		return false
	_leases_by_steam_id[steam_id] = {
		"steam_id": steam_id,
		"player_id": player_id,
		"peer_id": peer_id,
		"expires_milliseconds": (
			maxi(now_milliseconds, 0) + grace_milliseconds
		),
	}
	return true


func claim(steam_id: int, now_milliseconds: int) -> Dictionary:
	var lease: Dictionary = _leases_by_steam_id.get(steam_id, {})
	if lease.is_empty():
		return {}
	if now_milliseconds > int(lease.get("expires_milliseconds", -1)):
		return {}
	_leases_by_steam_id.erase(steam_id)
	return lease


func take_expired(now_milliseconds: int) -> Array[Dictionary]:
	var expired: Array[Dictionary] = []
	if _leases_by_steam_id.is_empty():
		return expired
	for steam_id: int in _leases_by_steam_id:
		var lease: Dictionary = _leases_by_steam_id[steam_id]
		if now_milliseconds <= int(lease.get("expires_milliseconds", -1)):
			continue
		expired.append(lease)
	for lease: Dictionary in expired:
		_leases_by_steam_id.erase(int(lease.get("steam_id", 0)))
	return expired


func has_lease(steam_id: int) -> bool:
	return _leases_by_steam_id.has(steam_id)


func erase(steam_id: int) -> void:
	_leases_by_steam_id.erase(steam_id)


func is_empty() -> bool:
	return _leases_by_steam_id.is_empty()


func reset() -> void:
	_leases_by_steam_id.clear()


static func retry_delay_milliseconds(attempt_index: int) -> int:
	var exponent := clampi(attempt_index, 0, 3)
	return mini(
		FIRST_RETRY_DELAY_MILLISECONDS * (1 << exponent),
		MAX_RETRY_DELAY_MILLISECONDS
	)
