extends Control

const RING_COLOR := Color(0.96, 0.72, 0.2, 0.94)
const RING_SHADOW := Color(0.02, 0.06, 0.045, 0.9)
const RING_RADIUS := 11.0

#######################################################
# Implements the terminal aim ring subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

var active := false
var aim_position := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func set_aim(next_position: Vector2, next_active: bool) -> void:
	aim_position = next_position
	active = next_active
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	draw_arc(
		aim_position,
		RING_RADIUS + 2.0,
		0.0,
		TAU,
		32,
		RING_SHADOW,
		5.0,
		true
	)
	draw_arc(
		aim_position,
		RING_RADIUS,
		0.0,
		TAU,
		32,
		RING_COLOR,
		2.5,
		true
	)
	draw_circle(aim_position, 1.8, RING_COLOR)
