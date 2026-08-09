extends Control

const FRACTAL_LAYOUT := preload(
	"res://scripts/drones/inspection/fractal_terminal_layout.gd"
)
const AIM_RING_SCRIPT := preload(
	"res://scripts/client/terminal_aim_ring.gd"
)

const COLOR_BACKGROUND := Color(0.008, 0.025, 0.022, 1.0)
const COLOR_PANEL := Color(0.018, 0.075, 0.062, 0.98)
const COLOR_PANEL_INNER := Color(0.012, 0.045, 0.039, 1.0)
const COLOR_BORDER := Color(0.12, 0.58, 0.42, 1.0)
const COLOR_BORDER_DIM := Color(0.06, 0.29, 0.23, 1.0)
const COLOR_TEXT := Color(0.66, 1.0, 0.78, 1.0)
const COLOR_MUTED := Color(0.35, 0.69, 0.53, 1.0)
const COLOR_ACCENT := Color(0.96, 0.67, 0.18, 1.0)

#######################################################
# Renders and updates the inspection terminal interface without owning authoritative gameplay
# state.
#######################################################

var document: Dictionary = {}
var view_path: Array[int] = []
var aim_position := Vector2.ZERO
var aim_visible := false
var aim_ring: Control


func _ready() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = FRACTAL_LAYOUT.SCREEN_SIZE
	_render_document()


func set_document(next_document: Dictionary, next_path: Array[int]) -> void:
	document = next_document.duplicate(true)
	view_path = next_path.duplicate()
	if is_node_ready():
		_render_document()


func set_aim_indicator(next_position: Vector2, next_visible: bool) -> void:
	aim_position = next_position
	aim_visible = next_visible
	if aim_ring != null:
		aim_ring.call("set_aim", aim_position, aim_visible)


func _render_document() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	var background := ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.position = Vector2.ZERO
	background.size = FRACTAL_LAYOUT.SCREEN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	if document.is_empty():
		_add_label(
			self,
			"PART SCANNER // WAITING FOR SERVER",
			Rect2(36.0, 32.0, 1268.0, 72.0),
			32,
			COLOR_TEXT
		)
		_create_aim_ring()
		return

	var current: Dictionary = _get_node_at_path(document, view_path)
	if current.is_empty():
		view_path.clear()
		current = document

	_draw_header(current)
	var children: Array = current.get("children", [])
	if children.is_empty():
		_draw_leaf(current)
	else:
		_draw_summary(current)
		_draw_children(children)
	_create_aim_ring()


func _create_aim_ring() -> void:
	aim_ring = AIM_RING_SCRIPT.new() as Control
	if aim_ring == null:
		return
	aim_ring.name = "AimRing"
	add_child(aim_ring)
	aim_ring.call("set_aim", aim_position, aim_visible)


func _draw_header(current: Dictionary) -> void:
	var back_panel := _add_panel(
		self,
		FRACTAL_LAYOUT.BACK_RECT,
		COLOR_PANEL,
		COLOR_BORDER
	)
	_add_label(
		back_panel,
		"<  BACK" if not view_path.is_empty() else "SCAVANGE INC.",
		Rect2(12.0, 4.0, 132.0, 44.0),
		19,
		COLOR_ACCENT if not view_path.is_empty() else COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)

	var breadcrumb := _build_breadcrumb()
	_add_label(
		self,
		str(current.get("title", "Part scanner")),
		Rect2(204.0, 10.0, 880.0, 40.0),
		32,
		COLOR_TEXT
	)
	_add_label(
		self,
		breadcrumb,
		Rect2(206.0, 48.0, 1000.0, 25.0),
		16,
		COLOR_MUTED
	)
	_add_label(
		self,
		"DEPTH %d" % view_path.size(),
		Rect2(1170.0, 21.0, 140.0, 34.0),
		17,
		COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_summary(current: Dictionary) -> void:
	var panel := _add_panel(
		self,
		FRACTAL_LAYOUT.SUMMARY_RECT,
		COLOR_PANEL_INNER,
		COLOR_BORDER_DIM
	)
	var subtitle := str(current.get("subtitle", ""))
	_add_label(
		panel,
		subtitle,
		Rect2(18.0, 8.0, 1238.0, 30.0),
		18,
		COLOR_MUTED
	)

	var values: Array = current.get("values", [])
	_draw_value_grid(
		panel,
		values,
		Rect2(18.0, 43.0, 1238.0, 57.0),
		4,
		18
	)
	_add_label(
		self,
		"SELECT A GROUP TO INSPECT",
		Rect2(30.0, 194.0, 500.0, 24.0),
		15,
		COLOR_MUTED
	)


func _draw_children(children: Array) -> void:
	for index: int in range(children.size()):
		var child_data: Dictionary = children[index]
		var rect: Rect2 = FRACTAL_LAYOUT.get_child_rect(
			index,
			children.size()
		)
		var panel := _add_panel(self, rect, COLOR_PANEL, COLOR_BORDER)
		panel.clip_contents = true

		var accent := ColorRect.new()
		accent.color = COLOR_ACCENT if index == 0 else COLOR_BORDER
		accent.position = Vector2.ZERO
		accent.size = Vector2(6.0, rect.size.y)
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(accent)

		_add_label(
			panel,
			str(child_data.get("title", "Group")),
			Rect2(18.0, 8.0, rect.size.x - 34.0, 30.0),
			23,
			COLOR_TEXT
		)
		_add_label(
			panel,
			str(child_data.get("subtitle", "")),
			Rect2(18.0, 38.0, rect.size.x - 34.0, 24.0),
			15,
			COLOR_MUTED
		)

		var values: Array = child_data.get("values", [])
		var grandchildren: Array = child_data.get("children", [])
		var preview_bottom: float = rect.size.y - 14.0
		if not grandchildren.is_empty():
			preview_bottom -= 34.0
		_draw_value_preview(
			panel,
			values,
			Rect2(
				18.0,
				66.0,
				rect.size.x - 36.0,
				maxf(preview_bottom - 66.0, 20.0)
			)
		)
		if not grandchildren.is_empty():
			_draw_nested_preview(panel, grandchildren, rect.size)


func _draw_nested_preview(
	parent: Control,
	grandchildren: Array,
	parent_size: Vector2
) -> void:
	var shown_count: int = mini(grandchildren.size(), 3)
	var gap := 6.0
	var available_width: float = parent_size.x - 36.0
	var mini_width: float = (
		available_width - gap * float(shown_count - 1)
	) / float(shown_count)
	for index: int in range(shown_count):
		var nested: Dictionary = grandchildren[index]
		var mini_rect := Rect2(
			18.0 + float(index) * (mini_width + gap),
			parent_size.y - 41.0,
			mini_width,
			27.0
		)
		var mini_panel := _add_panel(
			parent,
			mini_rect,
			COLOR_PANEL_INNER,
			COLOR_BORDER_DIM,
			1
		)
		_add_label(
			mini_panel,
			str(nested.get("title", "Detail")),
			Rect2(6.0, 2.0, mini_width - 12.0, 23.0),
			13,
			COLOR_MUTED,
			HORIZONTAL_ALIGNMENT_CENTER
		)


func _draw_leaf(current: Dictionary) -> void:
	var panel := _add_panel(
		self,
		Rect2(24.0, 82.0, 1292.0, 404.0),
		COLOR_PANEL,
		COLOR_BORDER
	)
	_add_label(
		panel,
		str(current.get("subtitle", "Detailed values")),
		Rect2(24.0, 14.0, 1244.0, 38.0),
		21,
		COLOR_MUTED
	)
	var values: Array = current.get("values", [])
	_draw_value_grid(
		panel,
		values,
		Rect2(24.0, 64.0, 1244.0, 316.0),
		2,
		24
	)


func _draw_value_preview(
	parent: Control,
	values: Array,
	rect: Rect2
) -> void:
	var line_height := 22.0
	var maximum_lines: int = maxi(1, floori(rect.size.y / line_height))
	var shown_count: int = mini(values.size(), maximum_lines)
	for index: int in range(shown_count):
		var value: Dictionary = values[index]
		_add_label(
			parent,
			"%s  %s" % [
				str(value.get("label", "")),
				str(value.get("value", "")),
			],
			Rect2(
				rect.position + Vector2(0.0, float(index) * line_height),
				Vector2(rect.size.x, line_height)
			),
			16,
			COLOR_TEXT
		)


func _draw_value_grid(
	parent: Control,
	values: Array,
	rect: Rect2,
	columns: int,
	font_size: int
) -> void:
	if values.is_empty():
		_add_label(
			parent,
			"No scalar values in this group.",
			rect,
			font_size,
			COLOR_MUTED
		)
		return

	var rows: int = ceili(float(values.size()) / float(columns))
	var cell_width: float = rect.size.x / float(columns)
	var cell_height: float = rect.size.y / float(maxi(rows, 1))
	for index: int in range(values.size()):
		var value: Dictionary = values[index]
		var column: int = index % columns
		var row: int = floori(float(index) / float(columns))
		var label_text := "%s\n%s" % [
			str(value.get("label", "")),
			str(value.get("value", "")),
		]
		_add_label(
			parent,
			label_text,
			Rect2(
				rect.position + Vector2(
					float(column) * cell_width,
					float(row) * cell_height
				),
				Vector2(cell_width - 10.0, cell_height)
			),
			font_size,
			COLOR_TEXT
		)


func _get_node_at_path(root: Dictionary, path: Array[int]) -> Dictionary:
	var current := root
	for child_index: int in path:
		var children: Array = current.get("children", [])
		if child_index < 0 or child_index >= children.size():
			return {}
		current = children[child_index]
	return current


func _build_breadcrumb() -> String:
	var labels: Array[String] = [str(document.get("title", "Scanner"))]
	var current := document
	for child_index: int in view_path:
		var children: Array = current.get("children", [])
		if child_index < 0 or child_index >= children.size():
			break
		current = children[child_index]
		labels.append(str(current.get("title", "Group")))
	return " / ".join(labels)


func _add_panel(
	parent: Control,
	rect: Rect2,
	background_color: Color,
	border_color: Color,
	border_width := 2
) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _add_label(
	parent: Control,
	text_value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	alignment := HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
