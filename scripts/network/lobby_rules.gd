class_name LobbyRules
extends RefCounted

const MAX_PLAYERS := 4
const MAX_BROWSER_RESULTS := 50

const GAME_TAG := "scavange-inc"
# Increment whenever an RPC method, channel, or replicated payload changes incompatibly. Steam
# lobby compatibility is checked before creating the transport, so mismatched source revisions are
# rejected at the browser instead of connecting far enough to fail inside SceneMultiplayer.
const PROTOCOL_VERSION := "12"

const DATA_GAME := "game"
const DATA_PROTOCOL := "protocol"
const DATA_NAME := "name"
const DATA_PLAYERS := "players"
const DATA_OPEN := "open"

#######################################################
# Centralizes deterministic lobby policy shared by clients and the server.
#######################################################

static func can_register_player(current_player_count: int) -> bool:
	return current_player_count >= 0 and current_player_count < MAX_PLAYERS


static func get_open_slot_count(
	current_player_count: int,
	capacity: int = MAX_PLAYERS
) -> int:
	return maxi(capacity - current_player_count, 0)


static func is_compatible_lobby(
	game_tag: String,
	protocol_version: String,
	member_count: int,
	capacity: int
) -> bool:
	return (
		has_matching_rules(game_tag, protocol_version, capacity)
		and member_count >= 0
		and member_count < capacity
	)


static func has_matching_rules(
	game_tag: String,
	protocol_version: String,
	capacity: int
) -> bool:
	return (
		game_tag == GAME_TAG
		and protocol_version == PROTOCOL_VERSION
		and capacity == MAX_PLAYERS
	)


static func read_non_negative_count(value: String, fallback: int) -> int:
	if value.is_valid_int():
		return maxi(value.to_int(), 0)
	return maxi(fallback, 0)
