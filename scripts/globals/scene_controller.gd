extends Node

const MAIN_MENU_TSCN = "res://scenes/UI/main_menu.tscn"
const LOBBY_BROWSER_TSCN = "res://scenes/UI/lobby_browser.tscn"
const ML_TRAINING_ROOM_TSCN = "res://ml/training/drone_training_room.tscn"
const LEVEL_EDITOR_TSCN = "res://scenes/UI/level_editor.tscn"

#######################################################
# Coordinates scene state and translates current inputs into gameplay decisions or actuator
# targets.
#######################################################

var current_ui: Control = null


func open_main_menu() -> void:
	# Gameplay proxies capture the pointer, and the persistent main-menu scene is
	# only hidden while playing, so its _ready() does not run again on return.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	clear_ui()
	var main_scene := get_tree().current_scene as CanvasItem
	if main_scene != null:
		main_scene.show()


func open_lobby_browser() -> void:
	var main_scene := get_tree().current_scene as CanvasItem
	if main_scene != null:
		main_scene.hide()
	change_ui(LOBBY_BROWSER_TSCN)


func open_ml_training_room() -> void:
	clear_ui()
	get_tree().change_scene_to_file(ML_TRAINING_ROOM_TSCN)


func leave_ml_training_room() -> void:
	clear_ui()
	get_tree().change_scene_to_file(MAIN_MENU_TSCN)


func open_level_editor() -> void:
	clear_ui()
	get_tree().change_scene_to_file(LEVEL_EDITOR_TSCN)


func leave_level_editor() -> void:
	clear_ui()
	get_tree().change_scene_to_file(MAIN_MENU_TSCN)


func enter_game() -> void:
	clear_ui()
	var main_scene := get_tree().current_scene as CanvasItem
	if main_scene != null:
		main_scene.hide()


func change_ui(scene_path: String) -> Control:
	if current_ui:
		current_ui.queue_free()
		current_ui = null

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Could not load UI scene: " + scene_path)
		return null

	var instance := packed_scene.instantiate() as Control
	if instance == null:
		push_error("UI scene root must be Control: " + scene_path)
		return null

	get_tree().get_root().add_child(instance)

	current_ui = instance
	return instance

func clear_ui() -> void:
	if current_ui:
		current_ui.queue_free()
		current_ui = null
