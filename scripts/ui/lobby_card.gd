extends Control
class_name LobbyCard

#######################################################
# Implements the lobby card subsystem and keeps its gameplay data and behavior in one focused
# script.
#######################################################

signal join_requested(lobby_id: int)

@onready var name_label: Label = $Panel/Margin/HBox/Name
@onready var player_count_label: Label = $Panel/Margin/HBox/PlayerCount
@onready var join_button: Button = $Panel/Margin/HBox/Join

var lobby_id := 0
var has_open_slot := false


func _ready() -> void:
	join_button.pressed.connect(_on_join_pressed)


func configure(
	new_lobby_id: int,
	lobby_name: String,
	member_count: int,
	capacity: int
) -> void:
	lobby_id = new_lobby_id
	name_label.text = lobby_name
	player_count_label.text = "%d / %d" % [member_count, capacity]
	has_open_slot = member_count >= 0 and member_count < capacity
	join_button.disabled = not has_open_slot
	join_button.text = "Full" if join_button.disabled else "Join"


func set_join_enabled(enabled: bool) -> void:
	join_button.disabled = not enabled or not has_open_slot
	join_button.text = "Full" if not has_open_slot else "Join"


func _on_join_pressed() -> void:
	if lobby_id <= 0 or join_button.disabled:
		return
	join_requested.emit(lobby_id)
