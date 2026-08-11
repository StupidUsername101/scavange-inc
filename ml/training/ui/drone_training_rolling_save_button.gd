class_name DroneTrainingRollingSaveButton
extends Button

const DASH_LENGTH_PX = 9.0
const GAP_LENGTH_PX = 6.0
const BORDER_INSET_PX = 2.0
const BORDER_WIDTH_PX = 2.0
const DASH_SPEED_PX_PER_SECOND = 12.0

var rolling_active = false
var rolling_color = Color.WHITE
var dash_phase_px = 0.0


func configure(group_color: Color, enabled: bool) -> void:
	rolling_color = group_color
	set_rolling_active(enabled)


func set_rolling_active(enabled: bool) -> void:
	rolling_active = enabled
	set_pressed_no_signal(enabled)
	set_process(enabled)
	if not enabled:
		dash_phase_px = 0.0
	queue_redraw()


static func refresh_group(group: Dictionary) -> void:
	var button: Button = group.get("overwrite_button") as Button
	if button == null:
		return
	var enabled: bool = bool(group.get("overwrite_saved_versions", true))
	button.set_pressed_no_signal(enabled)
	button.text = "KEEP NEWEST: ON" if enabled else "KEEP NEWEST: OFF"
	button.call("set_rolling_active", enabled)


func _process(delta: float) -> void:
	if not rolling_active:
		return
	dash_phase_px = fmod(
		dash_phase_px + maxf(delta, 0.0) * DASH_SPEED_PX_PER_SECOND,
		DASH_LENGTH_PX + GAP_LENGTH_PX
	)
	queue_redraw()


func _draw() -> void:
	if not rolling_active:
		return
	var border_size = size - Vector2.ONE * BORDER_INSET_PX * 2.0
	if border_size.x <= 1.0 or border_size.y <= 1.0:
		return
	var border = Rect2(
		Vector2.ONE * BORDER_INSET_PX,
		border_size
	)
	_draw_dashed_perimeter(border)


func _draw_dashed_perimeter(border: Rect2) -> void:
	var width = border.size.x
	var height = border.size.y
	var perimeter = 2.0 * (width + height)
	var pattern_length = DASH_LENGTH_PX + GAP_LENGTH_PX
	var cursor = -dash_phase_px
	while cursor < perimeter:
		var dash_start = maxf(cursor, 0.0)
		var dash_end = minf(cursor + DASH_LENGTH_PX, perimeter)
		if dash_end > dash_start:
			_draw_perimeter_interval(border, dash_start, dash_end)
		cursor += pattern_length


func _draw_perimeter_interval(
	border: Rect2,
	start_distance: float,
	end_distance: float
) -> void:
	var width = border.size.x
	var height = border.size.y
	var corners = PackedFloat32Array([
		width,
		width + height,
		width * 2.0 + height,
		width * 2.0 + height * 2.0,
	])
	var cursor = start_distance
	while cursor < end_distance - 0.001:
		var segment_end = end_distance
		for corner_distance in corners:
			if corner_distance > cursor + 0.001:
				segment_end = minf(segment_end, corner_distance)
				break
		draw_line(
			_point_on_perimeter(border, cursor),
			_point_on_perimeter(border, segment_end),
			rolling_color,
			BORDER_WIDTH_PX,
			true
		)
		cursor = segment_end


func _point_on_perimeter(border: Rect2, distance: float) -> Vector2:
	var width = border.size.x
	var height = border.size.y
	var clamped = clampf(distance, 0.0, 2.0 * (width + height))
	if clamped <= width:
		return border.position + Vector2(clamped, 0.0)
	clamped -= width
	if clamped <= height:
		return border.position + Vector2(width, clamped)
	clamped -= height
	if clamped <= width:
		return border.position + Vector2(width - clamped, height)
	clamped -= width
	return border.position + Vector2(0.0, height - minf(clamped, height))
