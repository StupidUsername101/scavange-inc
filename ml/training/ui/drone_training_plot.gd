class_name DroneTrainingPlot
extends Control

signal detail_requested
signal zoom_changed(zoom: float)
signal cut_mode_changed(active: bool)
signal history_cut(cut_x: float)

const COLOR_BACKGROUND = Color(0.008, 0.025, 0.022, 1.0)
const COLOR_GRID = Color(0.06, 0.29, 0.23, 0.55)
const COLOR_TEXT = Color(0.66, 1.0, 0.78, 1.0)
const COLOR_MUTED = Color(0.35, 0.69, 0.53, 1.0)
const PLOT_MARGIN = Rect2(42.0, 14.0, 54.0, 66.0)
const MINIMUM_X_ZOOM = 1.0
const MAXIMUM_X_ZOOM = 8.0
const X_ZOOM_STEP = 1.35
const CUT_COLOR = Color(1.0, 0.66, 0.24, 1.0)
const CUT_DASH_LENGTH = 8.0
const CUT_TRIANGLE_HALF_WIDTH = 8.0
const CUT_TRIANGLE_HEIGHT = 9.0

var series: Array[Dictionary] = []
var detailed = false
var x_axis_label = "step"
var y_axis_label = "value"
var empty_message = "No data yet — finish an episode or PPO update."
var x_zoom = MINIMUM_X_ZOOM
var x_view_start_ratio = 0.0
var panning = false
var last_plot_rect = Rect2()
var cut_mode = false
var cut_cursor_x = 0.0
var cut_cursor_visible = false
var cut_minimum_x = -INF
var display_context_id = ""


func _ready() -> void:
	custom_minimum_size = Vector2(220.0, 150.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Chart controls\n\nClick to expand.\nIn the large view: wheel zooms, middle-drag moves through history, and right-click resets."
	mouse_exited.connect(_on_plot_mouse_exited)


func set_series(next_series: Array[Dictionary]) -> void:
	# Series are freshly built immutable display data. A deep copy duplicated every point
	# in every plot during refresh and was one cause of the regular UI hitch.
	series = _normalize_series(next_series)
	if is_finite(cut_minimum_x) and not _has_points() and _has_unfiltered_points():
		cut_minimum_x = -INF
		x_zoom = MINIMUM_X_ZOOM
		x_view_start_ratio = 0.0
	if not _has_points():
		cancel_cut_mode()
	queue_redraw()


func set_display_context(next_context_id: String) -> void:
	if display_context_id == next_context_id:
		return
	display_context_id = next_context_id
	# Cuts and timeline zoom belong to the data source that created them. Carrying a cut from a
	# long-running drone group into a new limb group can hide every limb point and look exactly
	# like the drone measurements deleted it.
	cut_minimum_x = -INF
	x_zoom = MINIMUM_X_ZOOM
	x_view_start_ratio = 0.0
	panning = false
	cancel_cut_mode()
	zoom_changed.emit(x_zoom)
	queue_redraw()


static func _normalize_series(next_series: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var used_ids: Dictionary[String, int] = {}
	for index in range(next_series.size()):
		var source: Dictionary = next_series[index]
		var entry = source.duplicate(false)
		var base_id = str(entry.get("series_id", "")).strip_edges()
		if base_id.is_empty():
			base_id = "%s:%d" % [str(entry.get("label", "series")), index]
		var duplicate_index = int(used_ids.get(base_id, 0))
		used_ids[base_id] = duplicate_index + 1
		entry["series_id"] = (
			base_id
			if duplicate_index == 0
			else "%s#%d" % [base_id, duplicate_index + 1]
		)
		result.append(entry)
	return result


func begin_cut_mode() -> bool:
	if not _has_points():
		return false
	panning = false
	cut_mode = true
	var mouse_position = get_local_mouse_position()
	cut_cursor_visible = last_plot_rect.has_point(mouse_position)
	if cut_cursor_visible:
		cut_cursor_x = clampf(
			mouse_position.x,
			last_plot_rect.position.x,
			last_plot_rect.end.x
		)
	cut_mode_changed.emit(true)
	queue_redraw()
	return true


func cancel_cut_mode() -> void:
	if not cut_mode:
		return
	cut_mode = false
	cut_cursor_visible = false
	cut_mode_changed.emit(false)
	queue_redraw()


func is_cut_mode_active() -> bool:
	return cut_mode


func cut_history_before(cut_x: float) -> void:
	if not _has_points():
		return
	var latest_x = _latest_visible_x()
	if not is_finite(latest_x):
		return
	var requested_cut = minf(cut_x, latest_x)
	cut_minimum_x = (
		maxf(cut_minimum_x, requested_cut)
		if is_finite(cut_minimum_x)
		else requested_cut
	)
	x_zoom = MINIMUM_X_ZOOM
	x_view_start_ratio = 0.0
	zoom_changed.emit(x_zoom)
	history_cut.emit(cut_minimum_x)
	queue_redraw()


func clear_history_cut() -> void:
	if not is_finite(cut_minimum_x):
		return
	cut_minimum_x = -INF
	reset_zoom()
	queue_redraw()


func history_cut_minimum() -> float:
	return cut_minimum_x


func visible_points_for_entry(entry: Dictionary) -> PackedVector2Array:
	return _visible_points(entry)


func set_detailed(value: bool) -> void:
	if detailed == value:
		return
	detailed = value
	custom_minimum_size = Vector2(220.0, 410.0) if detailed else Vector2(220.0, 150.0)
	queue_redraw()


func reset_zoom() -> void:
	if is_equal_approx(x_zoom, MINIMUM_X_ZOOM) and is_zero_approx(x_view_start_ratio):
		return
	x_zoom = MINIMUM_X_ZOOM
	x_view_start_ratio = 0.0
	zoom_changed.emit(x_zoom)
	queue_redraw()


func set_axis_labels(next_x_axis_label: String, next_y_axis_label: String) -> void:
	if x_axis_label == next_x_axis_label and y_axis_label == next_y_axis_label:
		return
	x_axis_label = next_x_axis_label
	y_axis_label = next_y_axis_label
	queue_redraw()


func set_empty_message(value: String) -> void:
	if empty_message == value:
		return
	empty_message = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mouse_event = event as InputEventMouseButton
	if mouse_event != null:
		if cut_mode:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
				if last_plot_rect.has_point(mouse_event.position):
					cut_cursor_visible = true
					cut_cursor_x = mouse_event.position.x
					_apply_history_cut(mouse_event.position.x)
				accept_event()
				return
			if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
				cancel_cut_mode()
				accept_event()
				return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			if not detailed:
				return
			_zoom_at(mouse_event.position, X_ZOOM_STEP)
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			if not detailed:
				return
			_zoom_at(mouse_event.position, 1.0 / X_ZOOM_STEP)
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			if not detailed:
				return
			panning = mouse_event.pressed
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			if not detailed:
				return
			reset_zoom()
			accept_event()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			detail_requested.emit()
			accept_event()
			return
	var motion_event = event as InputEventMouseMotion
	if motion_event != null:
		if cut_mode:
			cut_cursor_visible = last_plot_rect.has_point(motion_event.position)
			cut_cursor_x = clampf(
				motion_event.position.x,
				last_plot_rect.position.x,
				last_plot_rect.end.x
			)
			queue_redraw()
			accept_event()
			return
		if panning and x_zoom > MINIMUM_X_ZOOM:
			var plot_width = maxf(last_plot_rect.size.x, 1.0)
			var window_ratio = 1.0 / x_zoom
			x_view_start_ratio = clampf(
				x_view_start_ratio - motion_event.relative.x / plot_width * window_ratio,
				0.0,
				1.0 - window_ratio
			)
			queue_redraw()
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND, true)
	var bottom_margin = 142.0 if detailed else PLOT_MARGIN.size.y
	var plot_rect = Rect2(
		Vector2(PLOT_MARGIN.position.x, PLOT_MARGIN.position.y),
		Vector2(
			maxf(size.x - PLOT_MARGIN.position.x - PLOT_MARGIN.size.x, 1.0),
			maxf(size.y - PLOT_MARGIN.position.y - bottom_margin, 1.0)
		)
	)
	last_plot_rect = plot_rect
	var division_count = 9 if detailed else 5
	for division in range(division_count):
		var ratio = float(division) / float(division_count - 1)
		var y = lerpf(plot_rect.position.y, plot_rect.end.y, ratio)
		draw_line(
			Vector2(plot_rect.position.x, y),
			Vector2(plot_rect.end.x, y),
			COLOR_GRID,
			1.0
		)
	var bounds = _bounds()
	var minimum = bounds[0]
	var maximum = bounds[1]
	var font = ThemeDB.fallback_font
	_draw_axis_labels(font, plot_rect, minimum, maximum, division_count)
	if not _has_points():
		draw_string(
			font,
			Vector2(plot_rect.position.x, plot_rect.get_center().y),
			empty_message,
			HORIZONTAL_ALIGNMENT_CENTER,
			plot_rect.size.x,
			13,
			COLOR_MUTED
		)
		return
	for entry in series:
		var points = _visible_points(entry)
		if points.is_empty():
			continue
		var rendered = PackedVector2Array()
		for point in points:
			if point.x < minimum.x or point.x > maximum.x:
				continue
			rendered.append(_map_point(point, minimum, maximum, plot_rect))
		if rendered.is_empty():
			continue
		if rendered.size() == 1:
			draw_circle(rendered[0], 2.5, entry.get("color", COLOR_TEXT))
		else:
			draw_polyline(rendered, entry.get("color", COLOR_TEXT), 2.0, true)
		if detailed:
			for rendered_point in rendered:
				draw_circle(rendered_point, 2.5, entry.get("color", COLOR_TEXT))
	if detailed:
		_draw_numeric_summary(font)
	else:
		_draw_legend(font)
	if cut_mode and cut_cursor_visible:
		_draw_cut_cursor(plot_rect)
	if x_zoom > MINIMUM_X_ZOOM:
		draw_string(
			font,
			Vector2(plot_rect.end.x - 112.0, plot_rect.position.y + 12.0),
			"timeline ×%s" % String.num(x_zoom, 1),
			HORIZONTAL_ALIGNMENT_RIGHT,
			112.0,
			11,
			COLOR_MUTED
		)


func _visible_points(entry: Dictionary) -> PackedVector2Array:
	var points: PackedVector2Array = entry.get("points", PackedVector2Array())
	if not is_finite(cut_minimum_x):
		return points
	var visible = PackedVector2Array()
	for point in points:
		if point.x + 0.000001 >= cut_minimum_x:
			visible.append(point)
	return visible


func _apply_history_cut(mouse_x: float) -> void:
	if not _has_points():
		cancel_cut_mode()
		return
	var bounds = _bounds()
	var minimum: Vector2 = bounds[0]
	var maximum: Vector2 = bounds[1]
	var ratio = clampf(
		(mouse_x - last_plot_rect.position.x) / maxf(last_plot_rect.size.x, 1.0),
		0.0,
		1.0
	)
	var requested_cut = lerpf(minimum.x, maximum.x, ratio)
	cut_history_before(requested_cut)
	cancel_cut_mode()


func _latest_visible_x() -> float:
	var latest = -INF
	for entry in series:
		var points = _visible_points(entry)
		for point in points:
			latest = maxf(latest, point.x)
	return latest


func _draw_cut_cursor(plot_rect: Rect2) -> void:
	var x = clampf(cut_cursor_x, plot_rect.position.x, plot_rect.end.x)
	draw_dashed_line(
		Vector2(x, plot_rect.end.y),
		Vector2(x, plot_rect.position.y),
		CUT_COLOR,
		2.0,
		CUT_DASH_LENGTH,
		true
	)
	var triangle = PackedVector2Array([
		Vector2(x - CUT_TRIANGLE_HALF_WIDTH, plot_rect.end.y + CUT_TRIANGLE_HEIGHT),
		Vector2(x + CUT_TRIANGLE_HALF_WIDTH, plot_rect.end.y + CUT_TRIANGLE_HEIGHT),
		Vector2(x, plot_rect.end.y),
	])
	draw_colored_polygon(triangle, CUT_COLOR)


func _on_plot_mouse_exited() -> void:
	panning = false
	if cut_mode:
		cancel_cut_mode()
	else:
		cut_cursor_visible = false
		queue_redraw()


func _bounds() -> Array[Vector2]:
	var full_minimum = Vector2(INF, INF)
	var full_maximum = Vector2(-INF, -INF)
	for entry in series:
		var points = _visible_points(entry)
		for point in points:
			full_minimum.x = minf(full_minimum.x, point.x)
			full_minimum.y = minf(full_minimum.y, point.y)
			full_maximum.x = maxf(full_maximum.x, point.x)
			full_maximum.y = maxf(full_maximum.y, point.y)
	if not is_finite(full_minimum.x):
		return [Vector2.ZERO, Vector2.ONE]
	if is_equal_approx(full_minimum.x, full_maximum.x):
		full_maximum.x = full_minimum.x + 1.0
	var full_x_range = full_maximum.x - full_minimum.x
	var window_ratio = 1.0 / x_zoom
	var minimum = Vector2(
		full_minimum.x + full_x_range * x_view_start_ratio,
		INF
	)
	var maximum = Vector2(
		minimum.x + full_x_range * window_ratio,
		-INF
	)
	for entry in series:
		var points = _visible_points(entry)
		for point in points:
			if point.x < minimum.x or point.x > maximum.x:
				continue
			minimum.y = minf(minimum.y, point.y)
			maximum.y = maxf(maximum.y, point.y)
	if not is_finite(minimum.y):
		minimum.y = full_minimum.y
		maximum.y = full_maximum.y
	if is_equal_approx(minimum.y, maximum.y):
		var padding = maxf(absf(minimum.y) * 0.1, 0.1)
		minimum.y -= padding
		maximum.y += padding
	return [minimum, maximum]


func _zoom_at(mouse_position: Vector2, multiplier: float) -> void:
	if not _has_points():
		return
	var previous_zoom = x_zoom
	var next_zoom = clampf(
		previous_zoom * multiplier,
		MINIMUM_X_ZOOM,
		MAXIMUM_X_ZOOM
	)
	if is_equal_approx(previous_zoom, next_zoom):
		return
	var cursor_ratio = clampf(
		(mouse_position.x - last_plot_rect.position.x)
		/ maxf(last_plot_rect.size.x, 1.0),
		0.0,
		1.0
	)
	var previous_window_ratio = 1.0 / previous_zoom
	var anchor_ratio = x_view_start_ratio + cursor_ratio * previous_window_ratio
	var next_window_ratio = 1.0 / next_zoom
	x_view_start_ratio = clampf(
		anchor_ratio - cursor_ratio * next_window_ratio,
		0.0,
		1.0 - next_window_ratio
	)
	x_zoom = next_zoom
	zoom_changed.emit(x_zoom)
	queue_redraw()


func _has_unfiltered_points() -> bool:
	for entry in series:
		var points: PackedVector2Array = entry.get("points", PackedVector2Array())
		if not points.is_empty():
			return true
	return false


func _has_points() -> bool:
	for entry in series:
		var points = _visible_points(entry)
		if not points.is_empty():
			return true
	return false


func _map_point(
	point: Vector2,
	minimum: Vector2,
	maximum: Vector2,
	plot_rect: Rect2
) -> Vector2:
	var x_ratio = (point.x - minimum.x) / maxf(maximum.x - minimum.x, 0.000001)
	var y_ratio = (point.y - minimum.y) / maxf(maximum.y - minimum.y, 0.000001)
	return Vector2(
		lerpf(plot_rect.position.x, plot_rect.end.x, x_ratio),
		lerpf(plot_rect.end.y, plot_rect.position.y, y_ratio)
	)


func _draw_legend(font: Font) -> void:
	var column_width = maxf(size.x * 0.5, 100.0)
	var visible_count = mini(series.size(), 4)
	var legend_top = last_plot_rect.end.y + 34.0
	for index in range(visible_count):
		var entry: Dictionary = series[index]
		var column = index % 2
		var row = floori(float(index) * 0.5)
		var x = 8.0 + float(column) * column_width
		var y = legend_top + float(row) * 14.0
		var color: Color = entry.get("color", COLOR_TEXT)
		draw_line(Vector2(x, y - 4.0), Vector2(x + 14.0, y - 4.0), color, 3.0)
		x += 19.0
		var label = str(entry.get("label", "series"))
		draw_string(
			font,
			Vector2(x, y),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			column_width - 27.0,
			12,
			COLOR_TEXT
		)
	if series.size() > visible_count:
		draw_string(
			font,
			Vector2(8.0, legend_top + 29.0),
			"+%d more — click to expand" % (series.size() - visible_count),
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 16.0,
			10,
			COLOR_MUTED
		)


func _draw_axis_labels(
	font: Font,
	plot_rect: Rect2,
	minimum: Vector2,
	maximum: Vector2,
	division_count: int
) -> void:
	for division in range(division_count):
		if not detailed and division > 0 and division < division_count - 1:
			continue
		var ratio = float(division) / float(division_count - 1)
		var value = lerpf(maximum.y, minimum.y, ratio)
		var y = lerpf(plot_rect.position.y, plot_rect.end.y, ratio)
		draw_string(
			font,
			Vector2(4.0, y + 4.0),
			_format_number(value),
			HORIZONTAL_ALIGNMENT_LEFT,
			36.0,
			11,
			COLOR_MUTED
		)
	draw_string(
		font,
		Vector2(plot_rect.position.x, plot_rect.end.y + 15.0),
		_format_number(minimum.x),
		HORIZONTAL_ALIGNMENT_LEFT,
		72.0,
		11,
		COLOR_MUTED
	)
	draw_string(
		font,
		Vector2(plot_rect.end.x - 72.0, plot_rect.end.y + 15.0),
		_format_number(maximum.x),
		HORIZONTAL_ALIGNMENT_RIGHT,
		72.0,
		11,
		COLOR_MUTED
	)
	if detailed:
		draw_string(
			font,
			Vector2(plot_rect.position.x, 11.0),
			y_axis_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			180.0,
			11,
			COLOR_MUTED
		)
		draw_string(
			font,
			Vector2(plot_rect.end.x - 180.0, plot_rect.end.y + 29.0),
			x_axis_label,
			HORIZONTAL_ALIGNMENT_RIGHT,
			180.0,
			11,
			COLOR_MUTED
		)


func _draw_numeric_summary(font: Font) -> void:
	var row = 0
	for entry in series:
		if row >= 8:
			break
		var points = _visible_points(entry)
		if points.is_empty():
			continue
		var minimum_value = INF
		var maximum_value = -INF
		for point in points:
			minimum_value = minf(minimum_value, point.y)
			maximum_value = maxf(maximum_value, point.y)
		var summary = "%s  latest %s  min %s  max %s" % [
			str(entry.get("label", "series")),
			_format_number(points[points.size() - 1].y),
			_format_number(minimum_value),
			_format_number(maximum_value),
		]
		draw_string(
			font,
			Vector2(8.0, size.y - 8.0 - float(row) * 15.0),
			summary,
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 16.0,
			11,
			entry.get("color", COLOR_TEXT)
		)
		row += 1
	if series.size() > row:
		draw_string(
			font,
			Vector2(8.0, size.y - 8.0 - float(row) * 15.0),
			"+%d additional series are still drawn" % (series.size() - row),
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 16.0,
			11,
			COLOR_MUTED
		)


func _format_number(value: float) -> String:
	if not is_finite(value):
		return "--"
	var absolute = absf(value)
	if absolute >= 1000.0:
		return String.num(value, 0)
	if absolute >= 10.0:
		return String.num(value, 1)
	if absolute >= 1.0:
		return String.num(value, 2)
	return String.num(value, 3)
