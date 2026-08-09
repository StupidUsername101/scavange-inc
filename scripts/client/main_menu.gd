extends Control

#######################################################
# Implements the main menu subsystem and keeps its gameplay data and behavior in one focused
# script.
#######################################################

@onready var host_button: Button = (
	$MarginContainer/MarginContainer/VSplitContainer/Button
)
@onready var browser_button: Button = (
	$MarginContainer/MarginContainer/VSplitContainer/Button2
)
@onready var training_room_button: Button = (
	$MarginContainer/MarginContainer/VSplitContainer/TrainingRoomButton
)
@onready var status_label: Label = (
	$MarginContainer/MarginContainer/VSplitContainer/StatusLabel
)

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	browser_button.pressed.connect(_on_browser_pressed)
	training_room_button.pressed.connect(_on_training_room_pressed)
	Server.lobby_status_changed.connect(_on_lobby_status_changed)


func _exit_tree() -> void:
	if Server.lobby_status_changed.is_connected(_on_lobby_status_changed):
		Server.lobby_status_changed.disconnect(_on_lobby_status_changed)


func _on_host_pressed() -> void:
	host_button.disabled = true
	browser_button.disabled = true
	status_label.text = "Creating Steam lobby..."
	Server.start_steam_host()


func _on_browser_pressed() -> void:
	SceneController.open_lobby_browser()


func _on_training_room_pressed() -> void:
	SceneController.open_ml_training_room()


func _on_lobby_status_changed(message: String, is_error: bool) -> void:
	status_label.text = message
	if is_error:
		host_button.disabled = false
		browser_button.disabled = false
