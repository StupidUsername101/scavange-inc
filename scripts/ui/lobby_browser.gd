extends Control
class_name LobbyBrowser

const LOBBY_CARD_SCENE := preload("res://scenes/UI/lobby_card.tscn")
const STEAM_JOIN_COMMAND := preload(
	"res://scripts/network/steam_join_command.gd"
)
const LOBBY_LIST_TIMEOUT_SECONDS := 22.0
const MAX_LOBBY_NAME_LENGTH := 64
const STEAM_PRESENCE_CONNECT := "connect"
const STEAM_PRESENCE_GROUP := "steam_player_group"

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
var lobby_match_list_received := false
var discovered_lobby_ids: Dictionary[int, bool] = {}
var rejected_lobby_count := 0


func _ready() -> void:
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.friend_rich_presence_update.connect(
		_on_friend_rich_presence_update
	)
	Server.lobby_status_changed.connect(_on_lobby_status_changed)
	refresh_button.pressed.connect(refresh_lobbies)
	back_button.pressed.connect(_on_back_pressed)

	if not Server.is_steam_available():
		refresh_button.disabled = true
		_show_empty_state(Server.get_steam_unavailable_message())
		return

	refresh_lobbies()


func _exit_tree() -> void:
	if Steam.lobby_match_list.is_connected(_on_lobby_match_list):
		Steam.lobby_match_list.disconnect(_on_lobby_match_list)
	if Steam.lobby_data_update.is_connected(_on_lobby_data_update):
		Steam.lobby_data_update.disconnect(_on_lobby_data_update)
	if Steam.friend_rich_presence_update.is_connected(
		_on_friend_rich_presence_update
	):
		Steam.friend_rich_presence_update.disconnect(
			_on_friend_rich_presence_update
		)
	if Server.lobby_status_changed.is_connected(_on_lobby_status_changed):
		Server.lobby_status_changed.disconnect(_on_lobby_status_changed)


func _on_lobby_match_list(lobbies: Array) -> void:
	if not refresh_in_flight or join_in_flight:
		return
	print("CLIENT: Found lobbies: ", lobbies.size())
	lobby_match_list_received = true
	
	for lobby_value: Variant in lobbies:
		_queue_lobby_candidate(int(lobby_value))

	if not pending_lobby_ids.is_empty():
		status_label.text = "Loading %d lobby result(s)..." % (
			pending_lobby_ids.size()
		)
	_finish_lobby_data_batch()

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
	var is_visible := _apply_lobby_snapshot(lobby_id, {
		"name": Steam.getLobbyData(lobby_id, LobbyRules.DATA_NAME),
		"members": maxi(steam_member_count, advertised_member_count),
		"capacity": Steam.getLobbyMemberLimit(lobby_id),
		"game_tag": Steam.getLobbyData(lobby_id, LobbyRules.DATA_GAME),
		"protocol": Steam.getLobbyData(lobby_id, LobbyRules.DATA_PROTOCOL),
		"open": Steam.getLobbyData(lobby_id, LobbyRules.DATA_OPEN),
	})
	if was_pending and not is_visible:
		rejected_lobby_count += 1

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
		_show_empty_state(Server.get_steam_unavailable_message())
		return

	print("CLIENT: Refreshing lobbies...")
	refresh_generation += 1
	refresh_in_flight = true
	lobby_match_list_received = false
	pending_lobby_ids.clear()
	discovered_lobby_ids.clear()
	rejected_lobby_count = 0
	for card: LobbyCard in lobby_cards_by_id.values():
		if is_instance_valid(card):
			if card.get_parent() != null:
				card.get_parent().remove_child(card)
			card.queue_free()
	lobby_cards_by_id.clear()
	empty_label.hide()
	refresh_button.disabled = true
	status_label.text = "Searching Steam and friend lobbies..."

	# Spacewar's public lobby index is shared by a large number of test projects. A friend's
	# current lobby is authoritative and bypasses that noisy global result set, while the metadata
	# validation in _apply_lobby_snapshot still prevents incompatible projects from being joined.
	_queue_friend_lobby_candidates()
		
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListResultCountFilter(
		LobbyRules.MAX_BROWSER_RESULTS
	)
	Steam.addRequestLobbyListStringFilter(
		LobbyRules.DATA_GAME,
		LobbyRules.GAME_TAG,
		Steam.LOBBY_COMPARISON_EQUAL
	)
	# Only the immutable game tag is filtered by Steam. Protocol, availability, and capacity are
	# validated from the returned snapshot so a delayed metadata update cannot make a friend's
	# otherwise valid lobby disappear before we ever receive its ID.
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


static func extract_friend_lobby_id(
	game_info: Dictionary,
	group_presence: String,
	connect_presence: String
) -> int:
	var game_lobby_id := _positive_integral_id(game_info.get("lobby", 0))
	if game_lobby_id > 0:
		return game_lobby_id

	var group_lobby_id := _positive_integral_id(group_presence)
	if group_lobby_id > 0:
		return group_lobby_id

	return STEAM_JOIN_COMMAND.parse_command_line(connect_presence)


static func _positive_integral_id(value: Variant) -> int:
	var numeric_id := SafeVariant.integral_int_or(value, 0)
	if numeric_id > 0:
		return numeric_id
	var text_id := str(value).strip_edges()
	if not text_id.is_valid_int():
		return 0
	var parsed_id := text_id.to_int()
	return parsed_id if parsed_id > 0 else 0


func _queue_friend_lobby_candidates() -> void:
	var friend_count := Steam.getFriendCount(Steam.FRIEND_FLAG_IMMEDIATE)
	for friend_index: int in range(friend_count):
		var friend_id := Steam.getFriendByIndex(
			friend_index,
			Steam.FRIEND_FLAG_IMMEDIATE
		)
		if friend_id <= 0:
			continue
		# Refreshing presence is asynchronous, but both getters also expose Steam's current cache.
		# getFriendGamePlayed is the primary route; our explicit presence keys cover SDK/platform
		# cases where the lobby field is temporarily absent.
		Steam.requestFriendRichPresence(friend_id)
		_queue_friend_lobby_candidate(friend_id)


func _queue_friend_lobby_candidate(friend_id: int) -> bool:
	if friend_id <= 0:
		return false
	var game_info: Dictionary = Steam.getFriendGamePlayed(friend_id)
	var lobby_id := extract_friend_lobby_id(
		game_info,
		Steam.getFriendRichPresence(friend_id, STEAM_PRESENCE_GROUP),
		Steam.getFriendRichPresence(friend_id, STEAM_PRESENCE_CONNECT)
	)
	return _queue_lobby_candidate(lobby_id)


func _on_friend_rich_presence_update(friend_id: int, _app_id: int) -> void:
	if join_in_flight or not Server.is_steam_available():
		return
	if not _queue_friend_lobby_candidate(friend_id):
		return
	# Steam may complete the public search before the separately requested friend presence. Resume
	# the finished batch in that case rather than making the user press Refresh a second time.
	if not refresh_in_flight:
		refresh_in_flight = true
		lobby_match_list_received = true
		refresh_button.disabled = true
	status_label.text = "Loading friend lobby..."


func _queue_lobby_candidate(lobby_id: int) -> bool:
	if (
		lobby_id <= 0
		or lobby_id == Server.lobby_id
		or pending_lobby_ids.has(lobby_id)
		or lobby_cards_by_id.has(lobby_id)
	):
		return false
	discovered_lobby_ids[lobby_id] = true
	pending_lobby_ids[lobby_id] = true
	if Steam.requestLobbyData(lobby_id):
		return true
	pending_lobby_ids.erase(lobby_id)
	rejected_lobby_count += 1
	return false


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
	if (
		not lobby_match_list_received
		or not pending_lobby_ids.is_empty()
	):
		return
	refresh_in_flight = false
	refresh_button.disabled = not Server.is_steam_available()
	if lobby_cards_by_id.is_empty():
		if discovered_lobby_ids.is_empty():
			_show_empty_state("Steam found no game or friend lobbies.")
		else:
			_show_empty_state(
				"Steam found %d candidate(s), but none were compatible and open."
				% discovered_lobby_ids.size()
			)
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
	discovered_lobby_ids.clear()
	Server.cancel_pending_lobby_join()
	SceneController.open_main_menu()
