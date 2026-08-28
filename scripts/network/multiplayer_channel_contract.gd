class_name MultiplayerChannelContract
extends RefCounted

## GodotSteam configures a fixed set of SteamNetworkingSockets lanes per connection. Its current
## MultiplayerPeer implementation reserves the final configured lane and silently sends an RPC on
## lane 0 when `transfer_channel >= configured_lanes - 1`. Keeping this contract next to the lobby
## transport prevents presentation-heavy snapshots from collapsing back onto the world-state lane.
## Steam lanes are directional: the host's capacity governs server-to-client audio even when the
## receiving build was authored with a smaller outgoing lane count.

const STEAM_MAX_CHANNELS_SETTING := &"steam/multiplayer_peer/max_channels"
const HIGHEST_APPLICATION_CHANNEL := 7
const GODOTSTEAM_RESERVED_LANE_COUNT := 1
const CONFIGURED_STEAM_LANE_COUNT := 9
const MINIMUM_STEAM_LANE_COUNT := (
	HIGHEST_APPLICATION_CHANNEL + GODOTSTEAM_RESERVED_LANE_COUNT + 1
)

const SPATIAL_ONE_SHOT_CHANNEL := 5
const CONTINUOUS_AUDIO_CHANNEL := 6
const LOCAL_AUDIO_CONTEXT_CHANNEL := 7
const PLAYER_SNAPSHOT_CHANNEL := 1


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
