class_name LevelAssetCatalogList
extends ItemList

signal visible_asset_range_changed(first_index: int, last_index: int)
signal favorite_toggle_requested(asset_path: String)

var _last_visible_range := Vector2i(-1, -1)
var _favorite_paths: Dictionary[String, bool] = {}


func _ready() -> void:
	set_process(true)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	# ItemList performs its native selection handling during GUI dispatch. Intercept the small
	# overlay target one stage earlier so a star press cannot become a card selection or drag.
	if (
		not is_visible_in_tree()
		or not event is InputEventMouseButton
		or not (event as InputEventMouseButton).pressed
		or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT
	):
		return
	var mouse_button := event as InputEventMouseButton
	var local_position := (
		get_global_transform_with_canvas().affine_inverse()
		* mouse_button.position
	)
	if not Rect2(Vector2.ZERO, size).has_point(local_position):
		return
	if _try_toggle_favorite_at(local_position):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if item_count <= 0 or size.x <= 0.0 or size.y <= 0.0:
		return
	var first_index := get_item_at_position(Vector2(4.0, 2.0), false)
	var last_index := get_item_at_position(
		Vector2(maxf(size.x - 4.0, 4.0), maxf(size.y - 2.0, 2.0)),
		false
	)
	if first_index < 0:
		first_index = 0
	if last_index < first_index:
		last_index = mini(first_index + 12, item_count - 1)
	first_index = maxi(first_index - 2, 0)
	last_index = mini(last_index + 3, item_count - 1)
	var next_range := Vector2i(first_index, last_index)
	if next_range == _last_visible_range:
		return
	_last_visible_range = next_range
	visible_asset_range_changed.emit(first_index, last_index)


func invalidate_visible_range() -> void:
	_last_visible_range = Vector2i(-1, -1)
	queue_redraw()


func set_favorite_paths(paths: Dictionary) -> void:
	_favorite_paths.clear()
	for asset_path_value: Variant in paths.keys():
		var asset_path := str(asset_path_value)
		if bool(paths.get(asset_path_value, false)) and not asset_path.is_empty():
			_favorite_paths[asset_path] = true
	queue_redraw()


func set_asset_favorite(asset_path: String, favorite: bool) -> void:
	if favorite:
		_favorite_paths[asset_path] = true
	else:
		_favorite_paths.erase(asset_path)
	queue_redraw()


func is_asset_favorite(asset_path: String) -> bool:
	return _favorite_paths.has(asset_path)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed:
		return
	if mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if _try_toggle_favorite_at(mouse_button.position):
			accept_event()
			return
	var direction := 0
	if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1
	elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1
	if direction == 0:
		return
	_select_relative(direction, mouse_button.position)
	accept_event()


func _try_toggle_favorite_at(local_position: Vector2) -> bool:
	# exact_match_only=false is essential: the star lives in the card cell, not necessarily over
	# ItemList's icon/text mask. Native selection already treats that complete cell as clickable.
	var item_index := get_item_at_position(local_position, false)
	if (
		item_index < 0
		or not _star_rect_for_item(item_index).has_point(local_position)
	):
		return false
	var asset_path := str(get_item_metadata(item_index))
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return false
	favorite_toggle_requested.emit(asset_path)
	return true


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := 19
	for item_index: int in range(item_count):
		var asset_path := str(get_item_metadata(item_index))
		if asset_path.is_empty():
			continue
		var star_rect := _star_rect_for_item(item_index)
		if star_rect.end.y < 0.0 or star_rect.position.y > size.y:
			continue
		draw_rect(star_rect, Color(0.025, 0.055, 0.05, 0.88), true)
		draw_string(
			font,
			star_rect.position + Vector2(1.0, float(font_size)),
			"★" if _favorite_paths.has(asset_path) else "☆",
			HORIZONTAL_ALIGNMENT_CENTER,
			star_rect.size.x - 2.0,
			font_size,
			Color("f1a72c") if _favorite_paths.has(asset_path) else Color("6da985")
		)


func _star_rect_for_item(item_index: int) -> Rect2:
	if item_index < 0 or item_index >= item_count:
		return Rect2()
	var item_rect := get_item_rect(item_index, false)
	# ItemList reports item rectangles in its scrollable content space while drawing and mouse
	# events use the visible control space. Keep the overlay attached to the card after scrolling.
	item_rect.position.y -= get_v_scroll_bar().value
	return Rect2(
		Vector2(item_rect.end.x - 27.0, item_rect.position.y + 4.0),
		Vector2(23.0, 23.0)
	)


func _select_relative(direction: int, mouse_position: Vector2) -> void:
	if item_count <= 0:
		return
	var selected_items := get_selected_items()
	var current_index := -1
	if not selected_items.is_empty():
		current_index = selected_items[0]
	else:
		current_index = get_item_at_position(mouse_position, true)
	if current_index < 0:
		current_index = -1 if direction > 0 else item_count
	current_index = _next_asset_index(current_index, direction)
	if current_index < 0:
		return
	select(current_index)
	ensure_current_is_visible()
	item_selected.emit(current_index)


func _next_asset_index(start_index: int, direction: int) -> int:
	var candidate := start_index + direction
	while candidate >= 0 and candidate < item_count:
		if not str(get_item_metadata(candidate)).is_empty():
			return candidate
		candidate += direction
	return -1


func _get_drag_data(at_position: Vector2) -> Variant:
	var item_index := get_item_at_position(at_position, true)
	if item_index < 0:
		return null
	if _star_rect_for_item(item_index).has_point(at_position):
		return null
	select(item_index)
	var asset_path := str(get_item_metadata(item_index))
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return null
	var preview := PanelContainer.new()
	var label := Label.new()
	label.text = "  %s  " % get_item_text(item_index)
	label.add_theme_font_size_override("font_size", 16)
	preview.add_child(label)
	set_drag_preview(preview)
	return {
		"type": &"level_asset",
		"asset_path": asset_path,
	}
