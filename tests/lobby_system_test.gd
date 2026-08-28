extends SceneTree

const STEAM_JOIN_COMMAND := preload(
	"res://scripts/network/steam_join_command.gd"
)
const MULTIPLAYER_CHANNELS := preload(
	"res://scripts/network/multiplayer_channel_contract.gd"
)
const REPLICATION_SCHEDULE := preload(
	"res://scripts/network/network_replication_schedule.gd"
)

#######################################################
# Runs headless regression coverage for lobby system behavior and reports contract or
# integration failures.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_four_player_limit()
	_test_lobby_compatibility()
	_test_lobby_count_parsing()
	_test_steam_join_commands()
	_test_lobby_ui_contract()
	_test_lobby_browser_behavior()
	_test_transport_wiring()
	_test_disconnect_rpc_safety()
	_test_transfer_channel_capacity()
	_test_replaceable_snapshot_transport()

	if failure_count == 0:
		print("Lobby system tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Lobby system tests failed: %d/%d assertions" % [
				failure_count,
				assertion_count,
			]
		)
		quit(1)


func _test_four_player_limit() -> void:
	_expect(LobbyRules.MAX_PLAYERS == 4, "lobbies are capped at four players")
	for count: int in range(LobbyRules.MAX_PLAYERS):
		_expect(
			LobbyRules.can_register_player(count),
			"player %d can enter an available slot" % (count + 1)
		)
	_expect(
		not LobbyRules.can_register_player(LobbyRules.MAX_PLAYERS),
		"a fifth player is rejected"
	)
	_expect(
		not LobbyRules.can_register_player(LobbyRules.MAX_PLAYERS + 1),
		"an over-capacity state cannot accept another player"
	)
	_expect(
		LobbyRules.get_open_slot_count(1) == 3,
		"browser reports the remaining slots"
	)
	_expect(
		LobbyRules.get_open_slot_count(4) == 0,
		"full lobby reports no remaining slots"
	)


func _test_lobby_compatibility() -> void:
	_expect(
		LobbyRules.PROTOCOL_VERSION == "7",
		"the client-ready multiplayer handshake has its own lobby protocol"
	)
	_expect(
		LobbyRules.is_compatible_lobby(
			LobbyRules.GAME_TAG,
			LobbyRules.PROTOCOL_VERSION,
			1,
			4
		),
		"a matching open lobby is visible"
	)
	_expect(
		not LobbyRules.is_compatible_lobby(
			"another-game",
			LobbyRules.PROTOCOL_VERSION,
			1,
			4
		),
		"another game is hidden"
	)
	_expect(
		not LobbyRules.is_compatible_lobby(
			LobbyRules.GAME_TAG,
			"old-protocol",
			1,
			4
		),
		"an incompatible protocol is hidden"
	)
	_expect(
		not LobbyRules.is_compatible_lobby(
			LobbyRules.GAME_TAG,
			LobbyRules.PROTOCOL_VERSION,
			4,
			4
		),
		"a full lobby is hidden"
	)
	_expect(
		not LobbyRules.is_compatible_lobby(
			LobbyRules.GAME_TAG,
			LobbyRules.PROTOCOL_VERSION,
			1,
			8
		),
		"a lobby with a different ruleset capacity is hidden"
	)
	_expect(
		LobbyRules.has_matching_rules(
			LobbyRules.GAME_TAG,
			LobbyRules.PROTOCOL_VERSION,
			4
		),
		"the fourth player remains valid after entering the final slot"
	)


func _test_lobby_count_parsing() -> void:
	_expect(
		LobbyRules.read_non_negative_count("3", 0) == 3,
		"advertised player count is parsed"
	)
	_expect(
		LobbyRules.read_non_negative_count("", 2) == 2,
		"missing metadata falls back to Steam's count"
	)
	_expect(
		LobbyRules.read_non_negative_count("-8", 0) == 0,
		"negative metadata is clamped"
	)


func _test_steam_join_commands() -> void:
	const LOBBY_ID := 109775241012345678
	_expect(
		Steam.has_method("activateGameOverlayInviteDialog"),
		"the installed GodotSteam build exposes the lobby invite overlay"
	)
	_expect(
		Steam.has_method("isOverlayEnabled"),
		"the installed GodotSteam build exposes overlay readiness"
	)
	_expect(
		Steam.has_signal("join_requested")
		and Steam.has_signal("join_game_requested"),
		"the installed GodotSteam build exposes invite and rich-presence joins"
	)
	var command: String = STEAM_JOIN_COMMAND.build(LOBBY_ID)
	_expect(
		command == "+connect_lobby %d" % LOBBY_ID,
		"Steam rich presence advertises the native lobby launch command"
	)
	_expect(
		STEAM_JOIN_COMMAND.parse_command_line(command) == LOBBY_ID,
		"a rich-presence Join Game callback resolves its lobby"
	)
	_expect(
		STEAM_JOIN_COMMAND.parse_arguments(
			PackedStringArray(["--unrelated", "+connect_lobby", str(LOBBY_ID)])
		) == LOBBY_ID,
		"a cold Steam launch resolves +connect_lobby from OS arguments"
	)
	_expect(
		STEAM_JOIN_COMMAND.parse_command_line(
			"+connect_lobby=%d" % LOBBY_ID
		) == LOBBY_ID,
		"assignment-style Steam launch commands remain compatible"
	)
	_expect(
		STEAM_JOIN_COMMAND.parse_command_line(
			"+connect_lobby definitely-not-a-lobby"
		) == 0,
		"malformed external lobby IDs are rejected"
	)
	_expect(
		STEAM_JOIN_COMMAND.parse_command_line("+connect_lobby -5") == 0,
		"non-positive external lobby IDs are rejected"
	)


func _test_lobby_ui_contract() -> void:
	var browser_scene := load(
		"res://scenes/UI/lobby_browser.tscn"
	) as PackedScene
	var card_scene := load(
		"res://scenes/UI/lobby_card.tscn"
	) as PackedScene
	_expect(browser_scene != null, "lobby browser scene loads")
	_expect(card_scene != null, "lobby card scene loads")
	if browser_scene != null:
		var browser := browser_scene.instantiate()
		_expect(
			browser.has_node(
				"Background/Margin/Layout/LobbyScroll/LobbyCards"
			),
			"browser exposes the lobby-card container"
		)
		_expect(
			browser.has_node("Background/Margin/Layout/Header/Refresh"),
			"browser exposes refresh"
		)
		_expect(
			browser.has_node("Background/Margin/Layout/Header/Back"),
			"browser exposes back navigation"
		)
		browser.free()
	if card_scene != null:
		var card := card_scene.instantiate()
		_expect(card is LobbyCard, "lobby card has the expected script")
		_expect(card.has_node("Panel/Margin/HBox/Join"), "card exposes join")
		_expect(
			card.has_node("Panel/Margin/HBox/PlayerCount"),
			"card exposes the player count"
		)
		card.free()


func _test_lobby_browser_behavior() -> void:
	var browser_scene := load(
		"res://scenes/UI/lobby_browser.tscn"
	) as PackedScene
	if browser_scene == null:
		_expect(false, "functional lobby browser scene loads")
		return
	var browser: Variant = browser_scene.instantiate()
	root.add_child(browser)
	_expect(
		browser.extract_friend_lobby_id(
			{"id": 480, "lobby": 109775241012345678},
			"",
			""
		) == 109775241012345678,
		"friend game state resolves its exact 64-bit Steam lobby ID"
	)
	_expect(
		browser.extract_friend_lobby_id(
			{},
			"109775241087654321",
			""
		) == 109775241087654321,
		"friend group presence recovers a lobby missing from game state"
	)
	_expect(
		browser.extract_friend_lobby_id(
			{},
			"",
			"+connect_lobby 109775241099999999"
		) == 109775241099999999,
		"friend Join Game presence provides the final discovery fallback"
	)
	_expect(
		browser.extract_friend_lobby_id(
			{},
			"not-an-id",
			"+connect_lobby nope"
		) == 0,
		"malformed friend presence cannot produce a lobby candidate"
	)
	var valid_snapshot := {
		"name": "  Test\nLobby  ",
		"members": 2,
		"capacity": LobbyRules.MAX_PLAYERS,
		"game_tag": LobbyRules.GAME_TAG,
		"protocol": LobbyRules.PROTOCOL_VERSION,
		"open": "1",
	}
	_expect(
		browser._apply_lobby_snapshot(101, valid_snapshot),
		"a compatible Steam metadata snapshot creates a browser card"
	)
	var card := browser.lobby_cards_by_id.get(101) as LobbyCard
	_expect(card != null, "the compatible lobby is indexed by Steam lobby ID")
	if card != null:
		_expect(
			card.name_label.text == "Test Lobby"
			and card.player_count_label.text == "2 / 4",
			"browser cards sanitize names and present the authoritative count"
		)
		var requested_lobby_ids: Array[int] = []
		card.join_requested.connect(
			func(lobby_id: int) -> void:
				requested_lobby_ids.append(lobby_id)
		)
		card.call("_on_join_pressed")
		_expect(
			requested_lobby_ids == [101],
			"a card emits its exact 64-bit lobby ID when Join is pressed"
		)

	browser.pending_lobby_ids[101] = true
	browser.refresh_in_flight = true
	browser._on_lobby_data_update(false, 101, 999)
	_expect(
		browser.pending_lobby_ids.has(101),
		"member-data callbacks cannot prematurely complete lobby metadata"
	)
	browser._on_refresh_timeout(browser.refresh_generation)
	_expect(
		browser.lobby_cards_by_id.has(101)
		and not browser.empty_label.visible
		and browser.status_label.text.contains("some results timed out"),
		"a partial metadata timeout preserves cards that already loaded"
	)

	var incompatible_snapshot := valid_snapshot.duplicate()
	incompatible_snapshot["protocol"] = "old-protocol"
	_expect(
		browser._apply_lobby_snapshot(101, incompatible_snapshot)
		and browser.lobby_cards_by_id.has(101),
		"discovery does not hide a lobby because replicated protocol metadata is stale"
	)
	browser._on_lobby_data_update(false, 101, 101)
	_expect(
		browser.lobby_cards_by_id.has(101)
		and not browser.empty_label.visible,
		"a failed metadata refresh preserves the directly discovered lobby"
	)

	var card_scene := load("res://scenes/UI/lobby_card.tscn") as PackedScene
	var full_card := card_scene.instantiate() as LobbyCard
	root.add_child(full_card)
	full_card.configure(202, "Full lobby", 4, 4)
	full_card.set_join_enabled(true)
	_expect(
		full_card.join_button.disabled and full_card.join_button.text == "Full",
		"generic error recovery cannot re-enable a full lobby"
	)
	full_card.free()
	browser.free()


func _test_transport_wiring() -> void:
	var server_source := FileAccess.get_file_as_string(
		"res://scripts/server/server.gd"
	)
	_expect(
		Steam.get_godotsteam_version() == "4.22",
		"the bundled GodotSteam bridge is the Godot 4.7-compatible 4.22 build"
	)
	var engine_version := Engine.get_version_info()
	_expect(
		int(engine_version.get("major", 0)) == 4
		and int(engine_version.get("minor", 0)) == 7,
		"the multiplayer contract is exercised with the authored Godot 4.7 runtime"
	)
	var browser_source := FileAccess.get_file_as_string(
		"res://scripts/ui/lobby_browser.gd"
	)
	var main_menu_source := FileAccess.get_file_as_string(
		"res://scripts/client/main_menu.gd"
	)
	var scene_controller_source := FileAccess.get_file_as_string(
		"res://scripts/globals/scene_controller.gd"
	)
	var main_menu_scene := load(
		"res://scenes/UI/main_menu.tscn"
	) as PackedScene
	_expect(
		server_source.contains("Steam.createLobby("),
		"host creation uses Steam matchmaking"
	)
	_expect(
		server_source.contains("Steam.joinLobby("),
		"client admission uses Steam matchmaking"
	)
	_expect(
		server_source.contains("Steam.join_game_requested.connect("),
		"running clients accept Steam rich-presence Join Game requests"
	)
	_expect(
		server_source.contains("Steam.getLaunchCommandLine()")
		and server_source.contains("OS.get_cmdline_args()"),
		"closed clients accept Steam's cold-launch lobby command"
	)
	_expect(
		server_source.contains("Steam.setRichPresence(")
		and server_source.contains("STEAM_PRESENCE_CONNECT"),
		"open sessions publish Steam's Join Game action"
	)
	_expect(
		server_source.contains("activateGameOverlayInviteDialog")
		and server_source.contains("func open_steam_invite_overlay("),
		"the in-game wrist menu opens Steam's lobby invite overlay"
	)
	_expect(
		server_source.contains("func leave_steam_session(")
		and server_source.contains("func _clear_runtime_session("),
		"returning to the menu tears down both transport and runtime state"
	)
	_expect(
		main_menu_source.contains("Server.is_lobby_idle()"),
		"returning from a session restores the main-menu host controls"
	)
	var main_menu := main_menu_scene.instantiate() if main_menu_scene != null else null
	_expect(
		main_menu != null
		and main_menu.has_node(
			"MarginContainer/MarginContainer/VSplitContainer/ExitButton"
		)
		and main_menu_source.contains("func _on_exit_pressed()")
		and main_menu_source.contains("get_tree().quit()"),
		"main menu exposes a working exit button"
	)
	if main_menu != null:
		main_menu.free()
	_expect(
		main_menu_source.contains(
			"Input.mouse_mode = Input.MOUSE_MODE_VISIBLE"
		)
		and scene_controller_source.contains(
			"Input.mouse_mode = Input.MOUSE_MODE_VISIBLE"
		),
		"both fresh and persistent main-menu entries release gameplay cursor capture"
	)
	_expect(
		server_source.contains("disconnect_peer(peer_id, true)"),
		"host forcibly rejects an over-capacity peer"
	)
	_expect(
		server_source.contains("get_steam_id_for_peer_id(")
		and server_source.contains("getLobbyMemberByIndex("),
		"host admits only Steam accounts in its current lobby"
	)
	_expect(
		server_source.contains("func confirm_client_session_ready(")
		and server_source.contains("pending_admission_peer_ids[peer_id] = true")
		and server_source.contains('rpc_id(\n\t\t1,\n\t\t"confirm_client_session_ready"'),
		"gameplay registration waits for an application-ready RPC from the client"
	)
	_expect(
		server_source.contains("steam_peer.debug_level = 2")
		and server_source.contains("func _on_steam_connection_status_changed("),
		"Steam transport failures retain their native end reason"
	)
	_expect(
		server_source.find("MULTIPLAYER_CHANNELS.ensure_runtime_capacity()")
		>= 0
		and server_source.find("MULTIPLAYER_CHANNELS.ensure_runtime_capacity()")
		< server_source.find("SteamMultiplayerPeer.new()"),
		"host establishes its lane capacity before constructing the Steam transport"
	)
	_expect(
		browser_source.contains("Steam.requestLobbyList()"),
		"browser actually submits its filtered request"
	)
	_expect(
		browser_source.contains("Steam.getFriendGamePlayed(")
		and browser_source.contains("Steam.getFriendRichPresence(")
		and browser_source.contains("friend_rich_presence_update.connect("),
		"browser discovers a friend's current lobby independently of Spacewar's public index"
	)
	_expect(
		not browser_source.contains(
			"Steam.addRequestLobbyList"
		),
		"browser submits an entirely unfiltered Steam lobby request"
	)


func _test_disconnect_rpc_safety() -> void:
	var server := root.get_node_or_null("Server")
	_expect(server != null, "authoritative server autoload is available")
	if server == null:
		return
	var local_peer_id := server.get_multiplayer().get_unique_id()
	_expect(
		bool(server.call("_is_rpc_peer_reachable", local_peer_id)),
		"listen-server host remains a valid call-local RPC recipient"
	)
	_expect(
		not bool(server.call("_is_rpc_peer_reachable", 1667114797)),
		"a departed or unknown Steam peer cannot receive a targeted RPC"
	)
	var server_source := FileAccess.get_file_as_string(
		"res://scripts/server/server.gd"
	)
	var disconnect_start := server_source.find(
		"func _on_peer_disconnected(peer_id: int) -> void:"
	)
	var next_function := server_source.find(
		"\nfunc _on_connected_to_server() -> void:",
		disconnect_start
	)
	var disconnect_source := server_source.substr(
		disconnect_start,
		next_function - disconnect_start
	)
	var unregister_position := disconnect_source.find(
		"GameState.unregister_peer(peer_id)"
	)
	var spill_position := disconnect_source.find("spill_all_item_entries()")
	_expect(
		unregister_position >= 0
		and spill_position >= 0
		and unregister_position < spill_position,
		"disconnect routing is invalidated before inventory and PBD cleanup can emit RPCs"
	)


func _test_transfer_channel_capacity() -> void:
	var client_source := FileAccess.get_file_as_string(
		"res://scripts/client/client.gd"
	)
	var configured_lane_count := int(ProjectSettings.get_setting(
		MULTIPLAYER_CHANNELS.STEAM_MAX_CHANNELS_SETTING,
		0
	))
	_expect(
		configured_lane_count
		== MULTIPLAYER_CHANNELS.CONFIGURED_STEAM_LANE_COUNT,
		"Steam transport uses the authored application lane capacity"
	)
	_expect(
		MULTIPLAYER_CHANNELS.has_capacity_for(
			MULTIPLAYER_CHANNELS.SPATIAL_ONE_SHOT_CHANNEL,
			configured_lane_count
		)
		and MULTIPLAYER_CHANNELS.has_capacity_for(
			MULTIPLAYER_CHANNELS.CONTINUOUS_AUDIO_CHANNEL,
			configured_lane_count
		)
		and MULTIPLAYER_CHANNELS.has_capacity_for(
			MULTIPLAYER_CHANNELS.ITEM_SNAPSHOT_CHANNEL,
			configured_lane_count
		),
		"one-shot audio, continuous audio, and interactive items own valid Steam lanes"
	)
	_expect(
		client_source.contains(
			'@rpc("authority", "unreliable", "call_local", %d)\nfunc on_spatial_sound_received'
			% MULTIPLAYER_CHANNELS.SPATIAL_ONE_SHOT_CHANNEL
		)
		and client_source.contains(
			'@rpc("authority", "unreliable_ordered", "call_local", %d)\nfunc on_radio_states_received'
			% MULTIPLAYER_CHANNELS.CONTINUOUS_AUDIO_CHANNEL
		)
		and not client_source.contains("on_radio_state_keyframe_received"),
		"remote one-shots and all continuous-audio lifecycle updates use their single contracted lanes"
	)
	var highest_declared_channel := _highest_rpc_channel_in("res://scripts")
	_expect(
		highest_declared_channel
		== MULTIPLAYER_CHANNELS.HIGHEST_APPLICATION_CHANNEL
		and MULTIPLAYER_CHANNELS.has_capacity_for(
			highest_declared_channel,
			configured_lane_count
		),
		"every declared RPC channel fits without GodotSteam lane-zero fallback"
	)
	ProjectSettings.set_setting(
		MULTIPLAYER_CHANNELS.STEAM_MAX_CHANNELS_SETTING,
		4
	)
	var repaired_lane_count := MULTIPLAYER_CHANNELS.ensure_runtime_capacity()
	_expect(
		repaired_lane_count
		== MULTIPLAYER_CHANNELS.CONFIGURED_STEAM_LANE_COUNT,
		"the host repairs a stale lane setting before creating its Steam peer"
	)
	ProjectSettings.set_setting(
		MULTIPLAYER_CHANNELS.STEAM_MAX_CHANNELS_SETTING,
		configured_lane_count
	)


func _test_replaceable_snapshot_transport() -> void:
	var client_source := FileAccess.get_file_as_string(
		"res://scripts/client/client.gd"
	)
	var server_source := FileAccess.get_file_as_string(
		"res://scripts/server/server.gd"
	)
	_expect(
		client_source.contains(
			'@rpc("authority", "unreliable", "call_local", %d)\nfunc on_player_states_received'
			% MULTIPLAYER_CHANNELS.PLAYER_SNAPSHOT_CHANNEL
		),
		"player poses use their own loss-tolerant Steam lane"
	)
	_expect(
		client_source.contains(
			'@rpc("authority", "unreliable", "call_local", %d)\nfunc on_item_states_received'
			% MULTIPLAYER_CHANNELS.ITEM_SNAPSHOT_CHANNEL
		)
		and client_source.contains(
			'@rpc("authority", "unreliable", "call_local", %d)\nfunc on_grabbed_item_motion_states_received'
			% MULTIPLAYER_CHANNELS.ITEM_SNAPSHOT_CHANNEL
		)
		and server_source.contains('"on_grabbed_item_motion_states_received"'),
		"full item lifecycle and high-rate held motion share one dedicated replaceable lane"
	)
	for handler_name: String in [
		"on_item_states_received",
		"on_grabbed_item_motion_states_received",
		"on_player_states_received",
		"on_drone_states_received",
		"on_projectile_states_received",
		"on_drone_part_states_received",
		"on_rope_states_received",
		"on_enemy_states_received",
		"on_inspection_station_states_received",
		"on_body_part_shop_states_received",
		"on_weapon_crafting_station_states_received",
	]:
		var declaration_index := client_source.find("func %s" % handler_name)
		var annotation_index := client_source.rfind("@rpc(", declaration_index)
		var annotation := client_source.substr(
			annotation_index,
			declaration_index - annotation_index
		)
		_expect(
			annotation_index >= 0
			and annotation.contains('"unreliable"')
			and not annotation.contains('"unreliable_ordered"'),
			"%s cannot accumulate behind a reliable snapshot" % handler_name
		)
	_expect(
		REPLICATION_SCHEDULE.is_due(
			0,
			REPLICATION_SCHEDULE.REALTIME_INTERVAL_TICKS
		)
		and REPLICATION_SCHEDULE.is_due(
			1,
			REPLICATION_SCHEDULE.REALTIME_INTERVAL_TICKS
		),
		"realtime state remains on every 20 Hz network tick"
	)
	_expect(
		REPLICATION_SCHEDULE.is_due(
			0,
			REPLICATION_SCHEDULE.BULK_PHYSICS_INTERVAL_TICKS
		)
		and not REPLICATION_SCHEDULE.is_due(
			1,
			REPLICATION_SCHEDULE.BULK_PHYSICS_INTERVAL_TICKS
		)
		and REPLICATION_SCHEDULE.is_due(
			2,
			REPLICATION_SCHEDULE.BULK_PHYSICS_INTERVAL_TICKS
		),
		"interpolated rigid bodies use the 10 Hz bulk schedule"
	)
	_expect(
		REPLICATION_SCHEDULE.is_due(
			0,
			REPLICATION_SCHEDULE.STATION_INTERVAL_TICKS
		)
		and not REPLICATION_SCHEDULE.is_due(
			9,
			REPLICATION_SCHEDULE.STATION_INTERVAL_TICKS
		)
		and REPLICATION_SCHEDULE.is_due(
			10,
			REPLICATION_SCHEDULE.STATION_INTERVAL_TICKS
		),
		"mostly-static station panels use the 2 Hz schedule"
	)
	_expect(
		server_source.contains(
			'state["network_snapshot_sequence"] = snapshot_sequence'
		)
		and client_source.contains("func _accept_network_snapshot("),
		"replaceable snapshots carry a client-side stale-packet guard"
	)
	_expect(
		REPLICATION_SCHEDULE.read_snapshot_sequence(
			{1: {"network_snapshot_sequence": 42}}
		) == 42,
		"the transport reads a snapshot's monotonic sequence"
	)
	_expect(
		not REPLICATION_SCHEDULE.is_newer_snapshot(41, 42),
		"a late packet cannot rewind a newer pose"
	)
	_expect(
		REPLICATION_SCHEDULE.is_newer_snapshot(43, 42),
		"a newer replacement snapshot advances normally"
	)


func _highest_rpc_channel_in(directory_path: String) -> int:
	var highest_channel := 0
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return -1
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if entry_name == "." or entry_name == "..":
			entry_name = directory.get_next()
			continue
		var entry_path := directory_path.path_join(entry_name)
		if directory.current_is_dir():
			highest_channel = maxi(
				highest_channel,
				_highest_rpc_channel_in(entry_path)
			)
		elif entry_name.ends_with(".gd"):
			for source_line: String in FileAccess.get_file_as_string(entry_path).split(
				"\n"
			):
				var stripped_line := source_line.strip_edges()
				if not stripped_line.begins_with("@rpc("):
					continue
				var close_index := stripped_line.find(")")
				if close_index < 0:
					continue
				var arguments := stripped_line.substr(
					5,
					close_index - 5
				).split(",")
				if arguments.size() < 4:
					continue
				var channel_text := str(arguments[3]).strip_edges()
				if channel_text.is_valid_int():
					highest_channel = maxi(
						highest_channel,
						channel_text.to_int()
					)
		entry_name = directory.get_next()
	directory.list_dir_end()
	return highest_channel


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: " + message)
