extends Control
class_name LobbyBrowser

const LOBBY_CARD_SCENE := preload("res://scenes/UI/lobby_card.tscn")
const LOBBY_LIST_TIMEOUT_SECONDS := 22.0
const MAX_LOBBY_NAME_LENGTH := 64

#######################################################
# Implements the lobby browser subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

@onready var lobby_card_container: VBoxContainer = (
	$Background/Margin/Layout/LobbyScroll/LobbyCards
)
@onready var refresh_button: Button = (
	$Background/Margin/Layout/Header/Refresh
)
@onready var back_button: Button = (
	$Background/Margin/Layout/Header/Back
)
@onready var status_label: Label = $Background/Margin/Layout/Status
@onready var empty_label: Label = (
	$Background/Margin/Layout/LobbyScroll/LobbyCards/Empty
)

var pending_lobby_ids: Dictionary[int, bool] = {}
var lobby_cards_by_id: Dictionary[int, LobbyCard] = {}
var refresh_generation := 0
var refresh_in_flight := false
var join_in_flight := false


func _ready() -> void:
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Server.lobby_status_changed.connect(_on_lobby_status_changed)
	refresh_button.pressed.connect(refresh_lobbies)
	back_button.pressed.connect(_on_back_pressed)

	if not Server.is_steam_available():
		refresh_button.disabled = true
		_show_empty_state(
			"Steam is not running. Start Steam and relaunch the game."
		)
		return

	refresh_lobbies()


func _exit_tree() -> void:
	if Steam.lobby_match_list.is_connected(_on_lobby_match_list):
		Steam.lobby_match_list.disconnect(_on_lobby_match_list)
	if Steam.lobby_data_update.is_connected(_on_lobby_data_update):
		Steam.lobby_data_update.disconnect(_on_lobby_data_update)
	if Server.lobby_status_changed.is_connected(_on_lobby_status_changed):
		Server.lobby_status_changed.disconnect(_on_lobby_status_changed)


func _on_lobby_match_list(lobbies: Array) -> void:
	if not refresh_in_flight or join_in_flight:
		return
	print("CLIENT: Found lobbies: ", lobbies.size())
	
	for lobby_value: Variant in lobbies:
		var lobby_id := int(lobby_value)
		if (
			lobby_id <= 0
			or lobby_id == Server.lobby_id
			or pending_lobby_ids.has(lobby_id)
		):
			continue
		pending_lobby_ids[lobby_id] = true
		if not Steam.requestLobbyData(lobby_id):
			pending_lobby_ids.erase(lobby_id)

	if pending_lobby_ids.is_empty():
		refresh_in_flight = false
		refresh_button.disabled = not Server.is_steam_available()
		_show_empty_state("No open lobbies found.")
	else:
		status_label.text = "Loading %d lobby result(s)..." % (
			pending_lobby_ids.size()
		)

func _on_lobby_data_update(success: bool, lobby_id: int, member_id: int) -> void:
	# LobbyDataUpdate also reports per-member changes. Only a room-level update can complete a
	# requestLobbyData batch entry.
	if member_id != lobby_id or join_in_flight:
		return
	var was_pending := pending_lobby_ids.has(lobby_id)
	var has_existing_card := lobby_cards_by_id.has(lobby_id)
	if not was_pending and not has_existing_card:
		return
	if was_pending:
		pending_lobby_ids.erase(lobby_id)

	if not success:
		_remove_lobby_card(lobby_id)
		if was_pending:
			_finish_lobby_data_batch()
		elif lobby_cards_by_id.is_empty():
			_show_empty_state("No compatible open lobbies found.")
		else:
			status_label.text = "%d open lobby(s)" % lobby_cards_by_id.size()
		return
		
	var steam_member_count: int = Steam.getNumLobbyMembers(lobby_id)
	var advertised_member_count := LobbyRules.read_non_negative_count(
		Steam.getLobbyData(lobby_id, LobbyRules.DATA_PLAYERS),
		steam_member_count
	)
	_apply_lobby_snapshot(lobby_id, {
		"name": Steam.getLobbyData(lobby_id, LobbyRules.DATA_NAME),
		"members": maxi(steam_member_count, advertised_member_count),
		"capacity": Steam.getLobbyMemberLimit(lobby_id),
		"game_tag": Steam.getLobbyData(lobby_id, LobbyRules.DATA_GAME),
		"protocol": Steam.getLobbyData(lobby_id, LobbyRules.DATA_PROTOCOL),
		"open": Steam.getLobbyData(lobby_id, LobbyRules.DATA_OPEN),
	})

	if was_pending:
		_finish_lobby_data_batch()
	elif lobby_cards_by_id.is_empty():
		_show_empty_state("No compatible open lobbies found.")
	else:
		status_label.text = "%d open lobby(s)" % lobby_cards_by_id.size()


func refresh_lobbies() -> void:
	if join_in_flight:
		return
	if not Server.is_steam_available():
		refresh_in_flight = false
		refresh_button.disabled = true
		_show_empty_state(
			"Steam is not running. Start Steam and relaunch the game."
		)
		return

	print("CLIENT: Refreshing lobbies...")
	refresh_generation += 1
	refresh_in_flight = true
	pending_lobby_ids.clear()
	for card: LobbyCard in lobby_cards_by_id.values():
		if is_instance_valid(card):
			if card.get_parent() != null:
				card.get_parent().remove_child(card)
			card.queue_free()
	lobby_cards_by_id.clear()
	empty_label.hide()
	refresh_button.disabled = true
	status_label.text = "Searching Steam lobbies..."
		
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListResultCountFilter(
		LobbyRules.MAX_BROWSER_RESULTS
	)
	Steam.addRequestLobbyListStringFilter(
		LobbyRules.DATA_GAME,
		LobbyRules.GAME_TAG,
		Steam.LOBBY_COMPARISON_EQUAL
	)
	Steam.addRequestLobbyListStringFilter(
		LobbyRules.DATA_PROTOCOL,
		LobbyRules.PROTOCOL_VERSION,
		Steam.LOBBY_COMPARISON_EQUAL
	)
	Steam.addRequestLobbyListStringFilter(
		LobbyRules.DATA_OPEN,
		"1",
		Steam.LOBBY_COMPARISON_EQUAL
	)
	Steam.addRequestLobbyListFilterSlotsAvailable(1)
	Steam.requestLobbyList()

	var this_generation: int = refresh_generation
	get_tree().create_timer(LOBBY_LIST_TIMEOUT_SECONDS).timeout.connect(
		_on_refresh_timeout.bind(this_generation)
	)


func _apply_lobby_snapshot(lobby_id: int, snapshot: Dictionary) -> bool:
	if lobby_id <= 0:
		return false
	var lobby_name := (
		str(snapshot.get("name", ""))
		.replace("\r", " ")
		.replace("\n", " ")
		.strip_edges()
	)
	if lobby_name.is_empty():
		lobby_name = "Unnamed lobby"
	lobby_name = lobby_name.left(MAX_LOBBY_NAME_LENGTH)
	var members := maxi(
		SafeVariant.integral_int_or(snapshot.get("members", 0), 0),
		0
	)
	var capacity := maxi(
		SafeVariant.integral_int_or(snapshot.get("capacity", 0), 0),
		0
	)
	var is_visible := (
		str(snapshot.get("open", "0")) == "1"
		and LobbyRules.is_compatible_lobby(
			str(snapshot.get("game_tag", "")),
			str(snapshot.get("protocol", "")),
			members,
			capacity
		)
	)
	if is_visible:
		_add_lobby_card(lobby_id, lobby_name, members, capacity)
	else:
		_remove_lobby_card(lobby_id)
	return is_visible


func _on_refresh_timeout(generation: int) -> void:
	if (
		not is_inside_tree()
		or generation != refresh_generation
		or not refresh_in_flight
	):
		return
	refresh_in_flight = false
	pending_lobby_ids.clear()
	refresh_button.disabled = not Server.is_steam_available()
	if lobby_cards_by_id.is_empty():
		_show_empty_state(
			"Steam did not return a lobby list. Try refresh."
		)
	else:
		empty_label.hide()
		status_label.text = (
			"%d open lobby(s); some results timed out."
			% lobby_cards_by_id.size()
		)


func _add_lobby_card(
	lobby_id: int,
	lobby_name: String,
	member_count: int,
	capacity: int
) -> void:
	if lobby_cards_by_id.has(lobby_id):
		lobby_cards_by_id[lobby_id].configure(
			lobby_id,
			lobby_name,
			member_count,
			capacity
		)
		return
	var card := LOBBY_CARD_SCENE.instantiate() as LobbyCard
	if card == null:
		push_error("Lobby card scene root must be LobbyCard")
		return
	lobby_card_container.add_child(card)
	card.configure(lobby_id, lobby_name, member_count, capacity)
	card.join_requested.connect(_on_join_requested)
	lobby_cards_by_id[lobby_id] = card


func _remove_lobby_card(lobby_id: int) -> void:
	if not lobby_cards_by_id.has(lobby_id):
		return
	var card = lobby_cards_by_id[lobby_id]
	lobby_cards_by_id.erase(lobby_id)
	if is_instance_valid(card):
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
		card.queue_free()


func _finish_lobby_data_batch() -> void:
	if not pending_lobby_ids.is_empty():
		return
	refresh_in_flight = false
	refresh_button.disabled = not Server.is_steam_available()
	if lobby_cards_by_id.is_empty():
		_show_empty_state("No compatible open lobbies found.")
	else:
		empty_label.hide()
		status_label.text = "%d open lobby(s)" % lobby_cards_by_id.size()


func _show_empty_state(message: String) -> void:
	status_label.text = message
	empty_label.text = message
	empty_label.show()


func _on_join_requested(lobby_id: int) -> void:
	if join_in_flight or not lobby_cards_by_id.has(lobby_id):
		return
	join_in_flight = true
	refresh_in_flight = false
	pending_lobby_ids.clear()
	for card: LobbyCard in lobby_cards_by_id.values():
		card.set_join_enabled(false)
	refresh_button.disabled = true
	back_button.disabled = true
	status_label.text = "Joining lobby..."
	Server.join_steam_lobby(lobby_id)


func _on_lobby_status_changed(message: String, is_error: bool) -> void:
	status_label.text = message
	if is_error:
		join_in_flight = false
		refresh_button.disabled = not Server.is_steam_available()
		back_button.disabled = false
		for card: LobbyCard in lobby_cards_by_id.values():
			card.set_join_enabled(Server.is_steam_available())


func _on_back_pressed() -> void:
	refresh_generation += 1
	refresh_in_flight = false
	join_in_flight = false
	pending_lobby_ids.clear()
	Server.cancel_pending_lobby_join()
	SceneController.open_main_menu()
