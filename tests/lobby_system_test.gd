extends SceneTree

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
	_test_lobby_ui_contract()
	_test_transport_wiring()

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


func _test_transport_wiring() -> void:
	var server_source := FileAccess.get_file_as_string(
		"res://scripts/server/server.gd"
	)
	var browser_source := FileAccess.get_file_as_string(
		"res://scripts/ui/lobby_browser.gd"
	)
	_expect(
		server_source.contains("Steam.createLobby("),
		"host creation uses Steam matchmaking"
	)
	_expect(
		server_source.contains("Steam.joinLobby("),
		"client admission uses Steam matchmaking"
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
		browser_source.contains("Steam.requestLobbyList()"),
		"browser actually submits its filtered request"
	)
	_expect(
		browser_source.contains(
			"Steam.addRequestLobbyListFilterSlotsAvailable(1)"
		),
		"browser asks Steam for lobbies with an open slot"
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: " + message)
