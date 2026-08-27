class_name FieldlinkDeviceControlPanel
extends Control

signal command_requested(action: StringName, payload: Dictionary)
signal hover_hint_requested(text: String, play_sound: bool)
signal hover_hint_ended
signal click_sound_requested

var control_snapshot: Dictionary = {}


func apply_control_snapshot(snapshot: Dictionary) -> void:
	control_snapshot = snapshot.duplicate(true)


func request_command(action: StringName, payload: Dictionary = {}) -> void:
	if action.is_empty():
		return
	click_sound_requested.emit()
	command_requested.emit(action, payload)


func bind_hover(control: Control, hint: String, play_sound := true) -> void:
	control.mouse_entered.connect(
		hover_hint_requested.emit.bind(hint, play_sound)
	)
	control.mouse_exited.connect(hover_hint_ended.emit)
