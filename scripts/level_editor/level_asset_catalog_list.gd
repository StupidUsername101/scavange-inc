class_name LevelAssetCatalogList
extends ItemList


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed:
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
		current_index = 0 if direction > 0 else item_count - 1
	else:
		current_index = clampi(current_index + direction, 0, item_count - 1)
	select(current_index)
	ensure_current_is_visible()
	item_selected.emit(current_index)


func _get_drag_data(at_position: Vector2) -> Variant:
	var item_index := get_item_at_position(at_position, true)
	if item_index < 0:
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
