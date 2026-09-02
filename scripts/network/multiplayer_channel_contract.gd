class_name MultiplayerChannelContract
extends RefCounted

## GodotSteam configures a fixed set of SteamNetworkingSockets lanes per connection. Its current
## MultiplayerPeer implementation reserves the final configured lane and silently sends an RPC on
## lane 0 when `transfer_channel >= configured_lanes - 1`. It also maps Godot's
## `unreliable_ordered` mode to Steam *reliable* delivery because Steam has no ordered-unreliable
## equivalent.
##
## Never mix Steam-reliable and Steam-unreliable traffic on one lane. Steam assigns both classes
## from one sender message counter, but reconstructs shortened unreliable message numbers from an
## unreliable-only receive counter. A long reliable-only gap followed by unreliable traffic can
## therefore become the fatal `SNP decode unreliable msgnum underflow` at a 16-bit boundary.
## Application sequence numbers own ordering for every loss-tolerant stream instead.

const STEAM_MAX_CHANNELS_SETTING := &"steam/multiplayer_peer/max_channels"
const HIGHEST_APPLICATION_CHANNEL := 9
const GODOTSTEAM_RESERVED_LANE_COUNT := 1
const CONFIGURED_STEAM_LANE_COUNT := 11
const MINIMUM_STEAM_LANE_COUNT := (
	HIGHEST_APPLICATION_CHANNEL + GODOTSTEAM_RESERVED_LANE_COUNT + 1
)

const SPATIAL_ONE_SHOT_CHANNEL := 5
const CONTINUOUS_AUDIO_CHANNEL := 6
const LOCAL_AUDIO_CONTEXT_CHANNEL := 7
const PLAYER_SNAPSHOT_CHANNEL := 1
const ITEM_SNAPSHOT_CHANNEL := 8
const VOICE_CHANNEL := 9

const STEAM_RELIABLE_LANE_MASK := (
	(1 << 0) | (1 << 3) | (1 << 6) | (1 << 7)
)
const STEAM_UNRELIABLE_LANE_MASK := (
	(1 << 1) | (1 << 2) | (1 << 4) | (1 << 5) | (1 << 8) | (1 << 9)
)


static func has_capacity_for(channel: int, configured_lane_count: int) -> bool:
	return (
		channel >= 0
		and configured_lane_count >= MINIMUM_STEAM_LANE_COUNT
		and channel < configured_lane_count - GODOTSTEAM_RESERVED_LANE_COUNT
	)


static func ensure_runtime_capacity() -> int:
	var configured_lane_count := int(ProjectSettings.get_setting(
		STEAM_MAX_CHANNELS_SETTING,
		0
	))
	if configured_lane_count < MINIMUM_STEAM_LANE_COUNT:
		ProjectSettings.set_setting(
			STEAM_MAX_CHANNELS_SETTING,
			CONFIGURED_STEAM_LANE_COUNT
		)
		configured_lane_count = CONFIGURED_STEAM_LANE_COUNT
	return configured_lane_count


static func is_reliable_lane(channel: int) -> bool:
	return channel >= 0 and (STEAM_RELIABLE_LANE_MASK & (1 << channel)) != 0


static func is_unreliable_lane(channel: int) -> bool:
	return channel >= 0 and (STEAM_UNRELIABLE_LANE_MASK & (1 << channel)) != 0


static func has_disjoint_reliability_lanes() -> bool:
	return (STEAM_RELIABLE_LANE_MASK & STEAM_UNRELIABLE_LANE_MASK) == 0
