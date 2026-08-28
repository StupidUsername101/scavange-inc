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
@onready var level_editor_button: Button = (
	$MarginContainer/MarginContainer/VSplitContainer/LevelEditorButton
)
@onready var exit_button: Button = (
	$MarginContainer/MarginContainer/VSplitContainer/ExitButton
)
@onready var status_label: Label = (
	$MarginContainer/MarginContainer/VSplitContainer/StatusLabel
)

func _ready() -> void:
	# Own the cursor state at the UI boundary as well as in SceneController so
	# cold starts and direct scene changes cannot inherit gameplay capture.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	host_button.pressed.connect(_on_host_pressed)
	browser_button.pressed.connect(_on_browser_pressed)
	# Shipping builds contain the playable client/server world, not the ML room or asset editor.
	# A custom export feature keeps development launches unchanged while ensuring the trimmed
	# package cannot navigate to resources deliberately omitted from its PCK.
	var runtime_only := OS.has_feature("game_runtime")
	training_room_button.visible = not runtime_only
	level_editor_button.visible = not runtime_only
	if not runtime_only:
		training_room_button.pressed.connect(_on_training_room_pressed)
		level_editor_button.pressed.connect(_on_level_editor_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	Server.lobby_status_changed.connect(_on_lobby_status_changed)
	if not Server.is_steam_available():
		status_label.text = Server.get_steam_unavailable_message()


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


func _on_level_editor_pressed() -> void:
	SceneController.open_level_editor()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_lobby_status_changed(message: String, is_error: bool) -> void:
	status_label.text = message
	if is_error or Server.is_lobby_idle():
		host_button.disabled = false
		browser_button.disabled = false
