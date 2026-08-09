class_name DroneTrainingTargetPad
extends Control

signal target_selected(normalized_position: Vector2)
signal selection_finished(normalized_position: Vector2)

const COLOR_BACKGROUND = Color(0.008, 0.025, 0.022, 1.0)
const COLOR_BORDER = Color(0.12, 0.58, 0.42, 1.0)
const COLOR_GRID = Color(0.06, 0.29, 0.23, 0.8)
const COLOR_TARGET = Color(1.0, 0.24, 0.44, 1.0)
const COLOR_TEXT = Color(0.66, 1.0, 0.78, 1.0)

var marker = Vector2(0.5, 0.5)
var dragging = false
var pad_caption = "X / Z target pad"
var pad_tooltip = "Move target\n\nClick or drag on the pad to move the followed subject across the arena floor."
var marker_color = COLOR_TARGET


func _ready() -> void:
	custom_minimum_size = Vector2(220.0, 150.0)
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	tooltip_text = pad_tooltip


func configure(
	caption: String,
	tooltip: String,
	color: Color = COLOR_TARGET
) -> void:
	pad_caption = caption
	pad_tooltip = tooltip
	marker_color = color
	tooltip_text = pad_tooltip
	queue_redraw()


func set_marker(normalized_position: Vector2) -> void:
	var next_marker = Vector2(
		clampf(normalized_position.x, 0.0, 1.0),
		clampf(normalized_position.y, 0.0, 1.0)
	)
	if marker.distance_squared_to(next_marker) <= 0.000001:
		return
	marker = next_marker
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mouse_button = event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if mouse_button.pressed:
			dragging = true
			_select(mouse_button.position)
		elif dragging:
			dragging = false
			selection_finished.emit(marker)
		accept_event()
		return
	var mouse_motion = event as InputEventMouseMotion
	if mouse_motion != null and dragging:
		_select(mouse_motion.position)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND, true)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BORDER, false, 2.0)
	for division in range(1, 8):
		var x = size.x * float(division) / 8.0
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), COLOR_GRID, 1.0)
	for division in range(1, 5):
		var y = size.y * float(division) / 5.0
		draw_line(Vector2(0.0, y), Vector2(size.x, y), COLOR_GRID, 1.0)
	var marker_position = Vector2(marker.x * size.x, marker.y * size.y)
	draw_circle(marker_position, 8.0, marker_color)
	draw_circle(marker_position, 15.0, Color(marker_color, 0.35), false, 2.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(8.0, 17.0),
		pad_caption,
		HORIZONTAL_ALIGNMENT_LEFT,
		120.0,
		12,
		COLOR_TEXT
	)


func _select(local_position: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	set_marker(Vector2(local_position.x / size.x, local_position.y / size.y))
	target_selected.emit(marker)
