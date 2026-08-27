class_name ScavangeLevelEditor
extends Control

const EDITOR_SCENE_PATH := "res://scenes/UI/level_editor.tscn"
const COLOR_BACKGROUND := Color("0b1112")
const COLOR_PANEL := Color("121d1d")
const COLOR_PANEL_INNER := Color("0b1615")
const COLOR_BORDER := Color("237456")
const COLOR_TEXT := Color("b5f5ca")
const COLOR_MUTED := Color("6da985")
const COLOR_ACCENT := Color("f1a72c")
const MODE_SELECT := &"select"
const MODE_MOVE := &"move"
const MODE_ROTATE := &"rotate"
const MODE_SCALE := &"scale"
const GRID_EXTENT := 100
const GRID_MAJOR_INTERVAL := 10
const QUARTER_TURN_RADIANS := PI * 0.5
const MINIMUM_STACK_SURFACE_NORMAL_Y := 0.45

var document := LevelEditorDocument.new()
var current_file_path := ""
var dirty := false
var catalog: Array[Dictionary] = []
var filtered_catalog: Array[Dictionary] = []
var placements_by_id: Dictionary[int, LevelAssetPlacement] = {}
var selected_placement: LevelAssetPlacement
var selected_catalog_path := ""
var pending_asset_path := ""
var undo_redo := UndoRedo.new()

var viewport_container: LevelEditorViewport
var editor_viewport: SubViewport
var editor_world: Node3D
var placement_root: Node3D
var editor_camera: Camera3D
var placement_cursor: MeshInstance3D
var placement_preview: LevelAssetPlacement
var asset_list: LevelAssetCatalogList
var search_field: LineEdit
var category_filter: OptionButton
var result_count_label: Label
var preview: LevelAssetPreview
var catalog_selection_label: Label
var selection_label: Label
var status_label: Label
var level_name_field: LineEdit
var snap_button: Button
var snap_step: SpinBox
var mode_buttons: Dictionary[StringName, Button] = {}
var transform_fields: Dictionary[StringName, Array] = {}
var save_dialog: FileDialog
var load_dialog: FileDialog
var discard_dialog: ConfirmationDialog
var pending_discard_action: StringName = &""

var edit_mode: StringName = MODE_SELECT
var inspector_refreshing := false
var camera_pivot := Vector3.ZERO
var camera_yaw := deg_to_rad(42.0)
var camera_pitch := deg_to_rad(32.0)
var camera_distance := 22.0
var camera_dragging := false
var camera_panning := false
var transform_dragging := false
var transform_drag_start_mouse := Vector2.ZERO
var transform_drag_start_snapshot: Dictionary = {}
var transform_drag_move_offset := Vector3.ZERO
var last_placement_viewport_position := Vector2.ZERO
var has_placement_pointer := false
var placement_rotation_y := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_interface()
	_build_editor_world()
	_new_document_now()
	call_deferred("_load_asset_catalog")


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_build_toolbar()
	_build_catalog_panel()
	_build_viewport_panel()
	_build_inspector_panel()
	_build_status_bar()
	_build_dialogs()


func _build_toolbar() -> void:
	var panel := _panel()
	panel.anchor_right = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 8.0
	panel.offset_right = -8.0
	panel.offset_bottom = 54.0
	add_child(panel)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	_add_button(row, "BACK", _request_back, "Return to the main menu")
	_add_separator(row)
	_add_button(row, "NEW", _request_new, "Create an empty level")
	_add_button(row, "LOAD", _request_load, "Load a saved level")
	_add_button(row, "SAVE", _request_save, "Save to the current file")
	_add_button(row, "SAVE AS", _request_save_as, "Choose a new save file")
	_add_separator(row)
	_add_button(row, "UNDO", _undo, "Undo the last edit")
	_add_button(row, "REDO", _redo, "Redo the last undone edit")
	_add_separator(row)
	for mode: StringName in [MODE_SELECT, MODE_MOVE, MODE_ROTATE, MODE_SCALE]:
		var button := _add_button(
			row,
			str(mode).to_upper(),
			_set_edit_mode.bind(mode),
			"Use %s tool" % str(mode)
		)
		button.toggle_mode = true
		mode_buttons[mode] = button
	mode_buttons[MODE_SELECT].button_pressed = true
	_add_separator(row)
	snap_button = _add_button(
		row,
		"SNAP",
		_toggle_snap,
		"Snap placement and movement to the selected grid size"
	)
	snap_button.toggle_mode = true
	snap_button.button_pressed = true
	snap_step = SpinBox.new()
	snap_step.custom_minimum_size.x = 82.0
	snap_step.min_value = 0.05
	snap_step.max_value = 10.0
	snap_step.step = 0.05
	snap_step.value = 0.5
	snap_step.suffix = " m"
	snap_step.value_changed.connect(_on_snap_step_changed)
	row.add_child(snap_step)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	level_name_field = LineEdit.new()
	level_name_field.custom_minimum_size.x = 220.0
	level_name_field.placeholder_text = "Level name"
	level_name_field.text_changed.connect(_on_level_name_changed)
	row.add_child(level_name_field)


func _build_catalog_panel() -> void:
	var panel := _panel()
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 60.0
	panel.offset_right = 320.0
	panel.offset_bottom = -34.0
	add_child(panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 9)
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	column.add_child(_label("ASSET CATALOG", 18, COLOR_TEXT))
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search models and packs..."
	search_field.clear_button_enabled = true
	search_field.text_changed.connect(_on_catalog_filter_changed)
	column.add_child(search_field)
	category_filter = OptionButton.new()
	category_filter.item_selected.connect(_on_category_selected)
	column.add_child(category_filter)
	asset_list = LevelAssetCatalogList.new()
	asset_list.name = "AssetCatalogList"
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.allow_reselect = true
	asset_list.item_selected.connect(_on_catalog_item_selected)
	asset_list.item_activated.connect(_on_catalog_item_activated)
	column.add_child(asset_list)
	result_count_label = _label("INDEXING ASSETS...", 12, COLOR_MUTED)
	column.add_child(result_count_label)
	var hint := _label(
		"CLICK / WHEEL SELECT  //  WORLD CLICK PLACES  //  RMB CANCELS",
		11,
		COLOR_MUTED
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)


func _build_viewport_panel() -> void:
	viewport_container = LevelEditorViewport.new()
	viewport_container.name = "EditorViewportContainer"
	viewport_container.anchor_right = 1.0
	viewport_container.anchor_bottom = 1.0
	viewport_container.offset_left = 328.0
	viewport_container.offset_top = 60.0
	viewport_container.offset_right = -320.0
	viewport_container.offset_bottom = -34.0
	viewport_container.stretch = true
	viewport_container.focus_mode = Control.FOCUS_ALL
	viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_container.asset_dropped.connect(_on_asset_dropped)
	viewport_container.gui_input.connect(_on_viewport_input)
	add_child(viewport_container)


func _build_inspector_panel() -> void:
	var panel := _panel()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -312.0
	panel.offset_top = 60.0
	panel.offset_right = -8.0
	panel.offset_bottom = -34.0
	add_child(panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 9)
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	column.add_child(_label("ASSET PREVIEW", 18, COLOR_TEXT))
	preview = LevelAssetPreview.new()
	preview.name = "AssetPreview"
	preview.custom_minimum_size = Vector2(280.0, 180.0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(preview)
	catalog_selection_label = _label("SELECT AN ASSET", 12, COLOR_MUTED)
	catalog_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	catalog_selection_label.custom_minimum_size.y = 44.0
	column.add_child(catalog_selection_label)
	column.add_child(HSeparator.new())
	selection_label = _label("NO PLACEMENT SELECTED", 15, COLOR_TEXT)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(selection_label)
	_add_transform_group(column, &"position", "POSITION", -10000.0, 10000.0, 0.05)
	_add_transform_group(column, &"rotation", "ROTATION", -3600.0, 3600.0, 1.0, "°")
	_add_transform_group(column, &"scale", "SCALE", 0.01, 1000.0, 0.01)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	column.add_child(action_row)
	_add_button(action_row, "FOCUS", _focus_selected, "Frame the selected placement")
	_add_button(action_row, "DUPLICATE", _duplicate_selected, "Duplicate selection")
	_add_button(action_row, "DELETE", _delete_selected, "Delete selection")
	_refresh_inspector()


func _build_status_bar() -> void:
	status_label = _label("LEVEL EDITOR READY", 12, COLOR_MUTED)
	status_label.anchor_top = 1.0
	status_label.anchor_right = 1.0
	status_label.anchor_bottom = 1.0
	status_label.offset_left = 12.0
	status_label.offset_top = -29.0
	status_label.offset_right = -12.0
	status_label.offset_bottom = -5.0
	add_child(status_label)


func _build_dialogs() -> void:
	save_dialog = FileDialog.new()
	save_dialog.title = "Save level"
	save_dialog.access = FileDialog.ACCESS_USERDATA
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = PackedStringArray(["*.json ; Scavange level"])
	save_dialog.file_selected.connect(_save_to_path)
	add_child(save_dialog)
	load_dialog = FileDialog.new()
	load_dialog.title = "Load level"
	load_dialog.access = FileDialog.ACCESS_USERDATA
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.filters = PackedStringArray(["*.json ; Scavange level"])
	load_dialog.file_selected.connect(_load_from_path)
	add_child(load_dialog)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "Unsaved level"
	discard_dialog.dialog_text = "Discard unsaved changes?"
	discard_dialog.confirmed.connect(_perform_pending_discard_action)
	add_child(discard_dialog)


func _build_editor_world() -> void:
	editor_viewport = SubViewport.new()
	editor_viewport.name = "EditorViewport"
	editor_viewport.size = Vector2i(1280, 720)
	editor_viewport.own_world_3d = true
	editor_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	editor_viewport.msaa_3d = Viewport.MSAA_4X
	viewport_container.add_child(editor_viewport)
	editor_world = Node3D.new()
	editor_world.name = "EditorWorld"
	editor_viewport.add_child(editor_world)
	placement_root = Node3D.new()
	placement_root.name = "Placements"
	editor_world.add_child(placement_root)
	editor_camera = Camera3D.new()
	editor_camera.name = "EditorCamera"
	editor_camera.current = true
	editor_camera.fov = 62.0
	editor_camera.near = 0.03
	editor_camera.far = 4000.0
	editor_world.add_child(editor_camera)
	var sun := DirectionalLight3D.new()
	sun.name = "EditorSun"
	sun.rotation = Vector3(-0.9, -0.65, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	editor_world.add_child(sun)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("172326")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9bc5bd")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	editor_world.add_child(environment_node)
	_build_grid()
	_build_placement_cursor()
	_update_camera()


func _build_grid() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for coordinate: int in range(-GRID_EXTENT, GRID_EXTENT + 1):
		var color := (
			Color(0.16, 0.5, 0.38, 0.48)
			if coordinate % GRID_MAJOR_INTERVAL == 0
			else Color(0.09, 0.25, 0.21, 0.28)
		)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(float(coordinate), 0.0, -GRID_EXTENT))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(float(coordinate), 0.0, GRID_EXTENT))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(-GRID_EXTENT, 0.0, float(coordinate)))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(Vector3(GRID_EXTENT, 0.0, float(coordinate)))
	mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.name = "EditorGrid"
	grid.mesh = mesh
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	editor_world.add_child(grid)


func _build_placement_cursor() -> void:
	var marker_mesh := ImmediateMesh.new()
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = COLOR_ACCENT
	marker_material.no_depth_test = true
	marker_mesh.surface_begin(Mesh.PRIMITIVE_LINES, marker_material)
	const SEGMENTS := 32
	const RADIUS := 0.42
	for segment_index: int in range(SEGMENTS):
		var angle_a := TAU * float(segment_index) / float(SEGMENTS)
		var angle_b := TAU * float(segment_index + 1) / float(SEGMENTS)
		marker_mesh.surface_add_vertex(
			Vector3(cos(angle_a) * RADIUS, 0.0, sin(angle_a) * RADIUS)
		)
		marker_mesh.surface_add_vertex(
			Vector3(cos(angle_b) * RADIUS, 0.0, sin(angle_b) * RADIUS)
		)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.FORWARD]:
		marker_mesh.surface_add_vertex(-axis * 0.62)
		marker_mesh.surface_add_vertex(axis * 0.62)
	marker_mesh.surface_end()
	placement_cursor = MeshInstance3D.new()
	placement_cursor.name = "PlacementCursor"
	placement_cursor.mesh = marker_mesh
	placement_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	placement_cursor.visible = false
	editor_world.add_child(placement_cursor)


func _load_asset_catalog() -> void:
	catalog = LevelAssetCatalog.entries()
	category_filter.clear()
	category_filter.add_item("All assets")
	for category: String in LevelAssetCatalog.category_names(catalog):
		category_filter.add_item(category)
	_refresh_catalog_list()
	_set_status("INDEXED %d UNIQUE GLB ASSETS" % catalog.size())


func _refresh_catalog_list() -> void:
	var category := (
		category_filter.get_item_text(category_filter.selected)
		if category_filter.item_count > 0
		else "All assets"
	)
	filtered_catalog = LevelAssetCatalog.filter_entries(
		catalog,
		search_field.text,
		category
	)
	asset_list.clear()
	var restored_index := -1
	for entry: Dictionary in filtered_catalog:
		var index := asset_list.add_item(str(entry.get("display_name", "Asset")))
		var asset_path := str(entry.get("asset_path", ""))
		asset_list.set_item_metadata(index, asset_path)
		asset_list.set_item_tooltip(index, "%s\n%s\n%s" % [
			str(entry.get("category", "Other")),
			str(entry.get("pack", "Unknown pack")),
			asset_path,
		])
		if asset_path == selected_catalog_path:
			asset_list.select(index)
			restored_index = index
	if restored_index >= 0:
		asset_list.ensure_current_is_visible()
	result_count_label.text = "%d / %d ASSETS" % [filtered_catalog.size(), catalog.size()]


func _on_catalog_filter_changed(_value: String) -> void:
	_refresh_catalog_list()


func _on_category_selected(_index: int) -> void:
	_refresh_catalog_list()


func _on_catalog_item_selected(index: int) -> void:
	if index < 0 or index >= asset_list.item_count:
		return
	selected_catalog_path = str(asset_list.get_item_metadata(index))
	preview.show_asset(selected_catalog_path)
	catalog_selection_label.text = "%s\n%s" % [
		asset_list.get_item_text(index).to_upper(),
		"%s  //  %s" % [
			str(filtered_catalog[index].get("category", "Other")),
			str(filtered_catalog[index].get("pack", "Unknown pack")),
		],
	]
	_arm_asset_placement(selected_catalog_path)


func _on_catalog_item_activated(index: int) -> void:
	_on_catalog_item_selected(index)
	var world_position := _screen_to_placement_surface(editor_viewport.size * 0.5)
	if world_position.is_finite():
		_place_asset(selected_catalog_path, world_position)


func _on_asset_dropped(asset_path: String, local_position: Vector2) -> void:
	var world_position := _screen_to_placement_surface(_viewport_pixel(local_position))
	if not world_position.is_finite():
		_set_status("DROP MISSED THE EDITOR GROUND", true)
		return
	selected_catalog_path = asset_path
	_arm_asset_placement(asset_path)
	_place_asset(asset_path, world_position)


func _place_asset(asset_path: String, world_position: Vector3) -> void:
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		_set_status("INVALID ASSET PATH", true)
		return
	var placement := _instantiate_placement(document.allocate_placement_id(), asset_path)
	if placement == null:
		_set_status("COULD NOT INSTANTIATE %s" % asset_path, true)
		return
	placement.rotation.y = placement_rotation_y
	var snapped_position := _snap_horizontal_position(world_position)
	placement.position = snapped_position + Vector3.UP * placement.floor_offset()
	var snapshot := placement.snapshot()
	undo_redo.create_action("Place asset")
	undo_redo.add_do_method(_restore_placement.bind(snapshot))
	undo_redo.add_undo_method(_remove_placement_by_id.bind(placement.placement_id))
	undo_redo.commit_action(false)
	_select_placement(placement)
	_mark_dirty()
	_set_status("PLACED %s" % asset_path.get_file().get_basename().to_upper())


func _instantiate_placement(
	placement_id: int,
	asset_path: String
) -> LevelAssetPlacement:
	if placements_by_id.has(placement_id):
		return placements_by_id[placement_id]
	var placement := LevelAssetPlacement.new()
	placement_root.add_child(placement)
	if not placement.configure(placement_id, asset_path):
		placement_root.remove_child(placement)
		placement.free()
		return null
	placements_by_id[placement_id] = placement
	return placement


func _restore_placement(snapshot: Dictionary) -> void:
	var safe := LevelEditorDocument.sanitize_placement(snapshot)
	if safe.is_empty():
		return
	var placement_id := int(safe.get("id", 0))
	var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
	if placement == null:
		placement = _instantiate_placement(placement_id, str(safe.get("asset_path", "")))
	if placement != null:
		placement.apply_snapshot(safe)


func _remove_placement_by_id(placement_id: int) -> void:
	var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
	if placement == null:
		return
	if placement == selected_placement:
		selected_placement = null
	placement.set_selected(false)
	placements_by_id.erase(placement_id)
	placement_root.remove_child(placement)
	placement.free()
	_refresh_inspector()


func _apply_placement_snapshot(placement_id: int, snapshot: Dictionary) -> void:
	var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
	if placement == null:
		return
	placement.apply_snapshot(snapshot)
	if placement == selected_placement:
		_refresh_inspector()


func _select_placement(placement: LevelAssetPlacement) -> void:
	if selected_placement == placement:
		return
	if selected_placement != null:
		selected_placement.set_selected(false)
	selected_placement = placement
	if selected_placement != null:
		selected_placement.set_selected(true)
	_refresh_inspector()


func _pick_placement(viewport_position: Vector2) -> LevelAssetPlacement:
	var ray_origin := editor_camera.project_ray_origin(viewport_position)
	var ray_direction := editor_camera.project_ray_normal(viewport_position)
	var nearest_distance := INF
	var nearest: LevelAssetPlacement
	for placement: LevelAssetPlacement in placements_by_id.values():
		var distance := placement.ray_distance(ray_origin, ray_direction)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = placement
	return nearest


func _on_viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_viewport_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_viewport_motion(event as InputEventMouseMotion)


func _handle_viewport_button(event: InputEventMouseButton) -> void:
	viewport_container.grab_focus()
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		camera_distance = maxf(camera_distance * 0.86, 0.4)
		_update_camera()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		camera_distance = minf(camera_distance / 0.86, 1200.0)
		_update_camera()
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		camera_dragging = event.pressed
		camera_panning = event.shift_pressed
		return
	if (
		event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and not pending_asset_path.is_empty()
	):
		_cancel_asset_placement()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var viewport_position := _viewport_pixel(event.position)
	if event.pressed:
		if not pending_asset_path.is_empty():
			var placement_position := _screen_to_placement_surface(viewport_position)
			if placement_position.is_finite():
				_place_asset(pending_asset_path, placement_position)
				_update_placement_cursor(viewport_position)
			return
		var hit := _pick_placement(viewport_position)
		if hit != selected_placement:
			_select_placement(hit)
			return
		if hit != null and edit_mode != MODE_SELECT:
			_begin_transform_drag(event.position, viewport_position)
	else:
		_finish_transform_drag()


func _handle_viewport_motion(event: InputEventMouseMotion) -> void:
	if camera_dragging:
		if camera_panning:
			var scale_factor := camera_distance * 0.0015
			var right := editor_camera.global_basis.x
			var forward := -editor_camera.global_basis.z
			forward.y = 0.0
			forward = forward.normalized()
			camera_pivot += (
				right * -event.relative.x
				+ forward * event.relative.y
			) * scale_factor
		else:
			camera_yaw -= event.relative.x * 0.008
			camera_pitch = clampf(
				camera_pitch + event.relative.y * 0.008,
				deg_to_rad(4.0),
				deg_to_rad(86.0)
			)
		_update_camera()
		return
	if transform_dragging and selected_placement != null:
		_update_transform_drag(event.position)
		return
	_update_placement_cursor(_viewport_pixel(event.position))


func _arm_asset_placement(asset_path: String) -> void:
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return
	if placement_preview == null or placement_preview.asset_path != asset_path:
		_clear_placement_preview()
		placement_preview = LevelAssetPlacement.new()
		editor_world.add_child(placement_preview)
		if not placement_preview.configure(0, asset_path):
			editor_world.remove_child(placement_preview)
			placement_preview.free()
			placement_preview = null
			pending_asset_path = ""
			_set_status("COULD NOT PREVIEW %s" % asset_path, true)
			return
		placement_preview.name = "PlacementPreview"
		placement_preview.process_mode = Node.PROCESS_MODE_DISABLED
		placement_preview.set_selected(true)
	placement_preview.rotation.y = placement_rotation_y
	pending_asset_path = asset_path
	has_placement_pointer = false
	if placement_cursor != null:
		placement_cursor.visible = false
	placement_preview.visible = false
	_set_status(
		"PLACEMENT ARMED  //  R ROTATES 90 DEGREES  //  RMB CANCELS"
	)


func _cancel_asset_placement() -> void:
	if pending_asset_path.is_empty():
		return
	pending_asset_path = ""
	has_placement_pointer = false
	placement_rotation_y = 0.0
	if placement_cursor != null:
		placement_cursor.visible = false
	_clear_placement_preview()
	_set_status("PLACEMENT CANCELLED")


func _update_placement_cursor(viewport_position: Vector2) -> void:
	if placement_cursor == null or pending_asset_path.is_empty():
		return
	last_placement_viewport_position = viewport_position
	has_placement_pointer = true
	var world_position := _screen_to_placement_surface(viewport_position)
	var has_position := world_position.is_finite()
	placement_cursor.visible = has_position
	if placement_preview != null:
		placement_preview.visible = has_position
	if not has_position:
		return
	world_position = _snap_horizontal_position(world_position)
	placement_cursor.position = world_position + Vector3.UP * 0.012
	if placement_preview != null:
		placement_preview.position = (
			world_position
			+ Vector3.UP * placement_preview.floor_offset()
		)


func _clear_placement_preview() -> void:
	if placement_preview == null:
		return
	if placement_preview.get_parent() != null:
		placement_preview.get_parent().remove_child(placement_preview)
	placement_preview.free()
	placement_preview = null


func _begin_transform_drag(
	mouse_position: Vector2,
	viewport_position: Vector2
) -> void:
	transform_dragging = true
	transform_drag_start_mouse = mouse_position
	transform_drag_start_snapshot = selected_placement.snapshot()
	if edit_mode == MODE_MOVE:
		var hit := _screen_to_height(viewport_position, selected_placement.position.y)
		transform_drag_move_offset = (
			selected_placement.position - hit
			if hit.is_finite()
			else Vector3.ZERO
		)


func _update_transform_drag(mouse_position: Vector2) -> void:
	var start_position: Vector3 = transform_drag_start_snapshot.get(
		"position",
		selected_placement.position
	)
	var start_rotation: Vector3 = transform_drag_start_snapshot.get(
		"rotation",
		selected_placement.rotation
	)
	var start_scale: Vector3 = transform_drag_start_snapshot.get(
		"scale",
		selected_placement.scale
	)
	match edit_mode:
		MODE_MOVE:
			var hit := _screen_to_height(
				_viewport_pixel(mouse_position),
				start_position.y
			)
			if hit.is_finite():
				var next_position := hit + transform_drag_move_offset
				next_position = _snap_horizontal_position(next_position)
				selected_placement.position = next_position
		MODE_ROTATE:
			var delta_x := mouse_position.x - transform_drag_start_mouse.x
			var next_yaw := start_rotation.y - delta_x * 0.01
			if snap_button.button_pressed:
				next_yaw = snappedf(next_yaw, deg_to_rad(15.0))
			selected_placement.rotation = Vector3(
				start_rotation.x,
				next_yaw,
				start_rotation.z
			)
		MODE_SCALE:
			var delta := (
				mouse_position.x - transform_drag_start_mouse.x
				- mouse_position.y + transform_drag_start_mouse.y
			)
			var factor := exp(delta * 0.008)
			var next_scale := (start_scale * factor).clamp(
				Vector3.ONE * 0.01,
				Vector3.ONE * 1000.0
			)
			if snap_button.button_pressed:
				next_scale = Vector3(
					snappedf(next_scale.x, 0.05),
					snappedf(next_scale.y, 0.05),
					snappedf(next_scale.z, 0.05)
				).max(Vector3.ONE * 0.01)
			selected_placement.scale = next_scale
	_refresh_inspector()


func _finish_transform_drag() -> void:
	if not transform_dragging:
		return
	transform_dragging = false
	if selected_placement == null or transform_drag_start_snapshot.is_empty():
		return
	var next_snapshot := selected_placement.snapshot()
	if _snapshots_match(transform_drag_start_snapshot, next_snapshot):
		return
	var placement_id := selected_placement.placement_id
	undo_redo.create_action("Transform asset")
	undo_redo.add_do_method(_apply_placement_snapshot.bind(placement_id, next_snapshot))
	undo_redo.add_undo_method(
		_apply_placement_snapshot.bind(placement_id, transform_drag_start_snapshot)
	)
	undo_redo.commit_action(false)
	_mark_dirty()


func _add_transform_group(
	parent: VBoxContainer,
	property_name: StringName,
	title: String,
	minimum: float,
	maximum: float,
	step_value: float,
	suffix := ""
) -> void:
	parent.add_child(_label(title, 12, COLOR_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var fields: Array[SpinBox] = []
	for axis_index: int in range(3):
		var field := SpinBox.new()
		field.name = "%s%s" % [title.capitalize(), ["X", "Y", "Z"][axis_index]]
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.min_value = minimum
		field.max_value = maximum
		field.step = step_value
		field.suffix = suffix
		field.value_changed.connect(
			_on_transform_field_changed.bind(property_name, axis_index)
		)
		row.add_child(field)
		fields.append(field)
	transform_fields[property_name] = fields


func _on_transform_field_changed(
	_value: float,
	property_name: StringName,
	axis_index: int
) -> void:
	if inspector_refreshing or selected_placement == null:
		return
	var previous := selected_placement.snapshot()
	var next := previous.duplicate(false)
	var vector: Vector3 = next.get(property_name, Vector3.ZERO)
	var field := (transform_fields[property_name] as Array)[axis_index] as SpinBox
	var component := float(field.value)
	if property_name == &"rotation":
		component = deg_to_rad(component)
	vector[axis_index] = component
	next[property_name] = vector
	var placement_id := selected_placement.placement_id
	undo_redo.create_action(
		"Edit %s %d" % [property_name, placement_id],
		UndoRedo.MERGE_ENDS
	)
	undo_redo.add_do_method(_apply_placement_snapshot.bind(placement_id, next))
	undo_redo.add_undo_method(_apply_placement_snapshot.bind(placement_id, previous))
	undo_redo.commit_action()
	_mark_dirty()


func _refresh_inspector() -> void:
	inspector_refreshing = true
	var has_selection := selected_placement != null
	selection_label.text = (
		"%03d  //  %s" % [
			selected_placement.placement_id,
			selected_placement.asset_path.get_file().get_basename().to_upper(),
		]
		if has_selection
		else "NO PLACEMENT SELECTED"
	)
	for property_name: StringName in transform_fields:
		var vector := Vector3.ZERO
		if has_selection:
			match property_name:
				&"position": vector = selected_placement.position
				&"rotation": vector = selected_placement.rotation * (180.0 / PI)
				&"scale": vector = selected_placement.scale
		elif property_name == &"scale":
			vector = Vector3.ONE
		var fields := transform_fields[property_name] as Array
		for axis_index: int in range(3):
			(fields[axis_index] as SpinBox).editable = has_selection
			(fields[axis_index] as SpinBox).value = vector[axis_index]
	inspector_refreshing = false


func _duplicate_selected() -> void:
	if selected_placement == null:
		return
	var snapshot := selected_placement.snapshot()
	snapshot["id"] = document.allocate_placement_id()
	var offset := float(snap_step.value) if snap_button.button_pressed else 0.5
	snapshot["position"] = (snapshot.get("position") as Vector3) + Vector3(offset, 0.0, offset)
	undo_redo.create_action("Duplicate asset")
	undo_redo.add_do_method(_restore_placement.bind(snapshot))
	undo_redo.add_undo_method(_remove_placement_by_id.bind(int(snapshot["id"])))
	undo_redo.commit_action()
	_select_placement(placements_by_id.get(int(snapshot["id"])) as LevelAssetPlacement)
	_mark_dirty()


func _delete_selected() -> void:
	if selected_placement == null:
		return
	var snapshot := selected_placement.snapshot()
	var placement_id := selected_placement.placement_id
	undo_redo.create_action("Delete asset")
	undo_redo.add_do_method(_remove_placement_by_id.bind(placement_id))
	undo_redo.add_undo_method(_restore_placement.bind(snapshot))
	undo_redo.commit_action()
	_mark_dirty()


func _focus_selected() -> void:
	if selected_placement == null:
		return
	camera_pivot = selected_placement.global_transform * selected_placement.local_bounds.get_center()
	var scaled_size := selected_placement.local_bounds.size * selected_placement.scale.abs()
	camera_distance = maxf(scaled_size.length() * 1.35, 1.5)
	_update_camera()


func _set_edit_mode(mode: StringName) -> void:
	edit_mode = mode
	for candidate: StringName in mode_buttons:
		mode_buttons[candidate].button_pressed = candidate == edit_mode
	_set_status("%s TOOL ACTIVE" % str(edit_mode).to_upper())


func _toggle_snap() -> void:
	_refresh_armed_placement_cursor()
	_set_status(
		"SNAP %s  //  %.2f M GRID" % [
			"ENABLED" if snap_button.button_pressed else "DISABLED",
			float(snap_step.value),
		]
	)


func _on_snap_step_changed(_value: float) -> void:
	_refresh_armed_placement_cursor()


func _refresh_armed_placement_cursor() -> void:
	if not pending_asset_path.is_empty() and has_placement_pointer:
		_update_placement_cursor(last_placement_viewport_position)


func _snap_horizontal_position(value: Vector3) -> Vector3:
	if snap_button == null or snap_step == null or not snap_button.button_pressed:
		return value
	var step_value := maxf(float(snap_step.value), 0.0001)
	return Vector3(
		snappedf(value.x, step_value),
		value.y,
		snappedf(value.z, step_value)
	)


func _rotate_asset_quarter_turn() -> void:
	if not pending_asset_path.is_empty() and placement_preview != null:
		placement_rotation_y = wrapf(
			placement_rotation_y + QUARTER_TURN_RADIANS,
			0.0,
			TAU
		)
		placement_preview.rotation.y = placement_rotation_y
		_refresh_armed_placement_cursor()
		_set_status(
			"PLACEMENT ROTATION  //  %d DEGREES"
			% int(round(rad_to_deg(placement_rotation_y)))
		)
		return
	if selected_placement == null:
		_set_status("SELECT OR ARM AN ASSET TO ROTATE", true)
		return
	var previous := selected_placement.snapshot()
	var next := previous.duplicate(false)
	var next_rotation: Vector3 = next.get("rotation", Vector3.ZERO)
	next_rotation.y = wrapf(
		next_rotation.y + QUARTER_TURN_RADIANS,
		0.0,
		TAU
	)
	next["rotation"] = next_rotation
	var placement_id := selected_placement.placement_id
	undo_redo.create_action("Rotate asset 90 degrees")
	undo_redo.add_do_method(_apply_placement_snapshot.bind(placement_id, next))
	undo_redo.add_undo_method(_apply_placement_snapshot.bind(placement_id, previous))
	undo_redo.commit_action()
	_mark_dirty()
	_set_status("ROTATED ASSET 90 DEGREES")


func _update_camera() -> void:
	if editor_camera == null:
		return
	var direction := Vector3(
		sin(camera_yaw) * cos(camera_pitch),
		sin(camera_pitch),
		cos(camera_yaw) * cos(camera_pitch)
	)
	editor_camera.position = camera_pivot + direction * camera_distance
	editor_camera.look_at(camera_pivot, Vector3.UP)


func _screen_to_ground(viewport_position: Vector2) -> Vector3:
	return _screen_to_height(viewport_position, 0.0)


func _screen_to_placement_surface(viewport_position: Vector2) -> Vector3:
	var ray_origin := editor_camera.project_ray_origin(viewport_position)
	var ray_direction := editor_camera.project_ray_normal(viewport_position).normalized()
	if (
		not ray_origin.is_finite()
		or not ray_direction.is_finite()
		or ray_direction.length_squared() <= 0.000001
	):
		return Vector3.INF
	var ground_position := _screen_to_ground(viewport_position)
	var nearest_distance := (
		ray_origin.distance_to(ground_position)
		if ground_position.is_finite()
		else INF
	)
	var surface_position := ground_position
	for placement_id: int in placements_by_id:
		var placement := placements_by_id[placement_id] as LevelAssetPlacement
		var hit_distance := placement.upward_surface_ray_distance(
			ray_origin,
			ray_direction,
			MINIMUM_STACK_SURFACE_NORMAL_Y
		)
		if hit_distance < nearest_distance:
			nearest_distance = hit_distance
			surface_position = ray_origin + ray_direction * hit_distance
	return surface_position


func _screen_to_height(viewport_position: Vector2, height: float) -> Vector3:
	var origin := editor_camera.project_ray_origin(viewport_position)
	var direction := editor_camera.project_ray_normal(viewport_position)
	if absf(direction.y) <= 0.000001:
		return Vector3.INF
	var distance := (height - origin.y) / direction.y
	if distance < 0.0:
		return Vector3.INF
	return origin + direction * distance


func _viewport_pixel(container_position: Vector2) -> Vector2:
	if viewport_container.size.x <= 0.0 or viewport_container.size.y <= 0.0:
		return container_position
	return Vector2(
		container_position.x / viewport_container.size.x * editor_viewport.size.x,
		container_position.y / viewport_container.size.y * editor_viewport.size.y
	)


func _undo() -> void:
	if undo_redo.has_undo():
		undo_redo.undo()
		_mark_dirty()
		_set_status("UNDO  //  %s" % undo_redo.get_current_action_name().to_upper())


func _redo() -> void:
	if undo_redo.has_redo():
		undo_redo.redo()
		_mark_dirty()
		_set_status("REDO  //  %s" % undo_redo.get_current_action_name().to_upper())


func _request_new() -> void:
	_request_discard_or(&"new")


func _request_load() -> void:
	_request_discard_or(&"load")


func _request_back() -> void:
	_request_discard_or(&"back")


func _request_discard_or(action: StringName) -> void:
	if dirty:
		pending_discard_action = action
		discard_dialog.popup_centered()
		return
	_perform_discard_action(action)


func _perform_pending_discard_action() -> void:
	var action := pending_discard_action
	pending_discard_action = &""
	_perform_discard_action(action)


func _perform_discard_action(action: StringName) -> void:
	match action:
		&"new": _new_document_now()
		&"load":
			_prepare_level_directory()
			load_dialog.current_dir = LevelEditorDocument.DEFAULT_DIRECTORY
			load_dialog.popup_centered_ratio(0.72)
		&"back": SceneController.leave_level_editor()


func _request_save() -> void:
	if current_file_path.is_empty():
		_request_save_as()
	else:
		_save_to_path(current_file_path)


func _request_save_as() -> void:
	_prepare_level_directory()
	save_dialog.current_dir = LevelEditorDocument.DEFAULT_DIRECTORY
	var file_stem := level_name_field.text.strip_edges().to_snake_case()
	if file_stem.is_empty():
		file_stem = "untitled_level"
	save_dialog.current_file = file_stem + ".json"
	save_dialog.popup_centered_ratio(0.72)


func _save_to_path(path: String) -> void:
	_sync_document_from_scene()
	var error := document.save_to_path(path)
	if error != OK:
		_set_status("SAVE FAILED  //  %s" % error_string(error).to_upper(), true)
		return
	current_file_path = path
	dirty = false
	_update_window_title()
	_set_status("SAVED  //  %s" % path)


func _load_from_path(path: String) -> void:
	var loaded := LevelEditorDocument.load_from_path(path)
	if loaded == null:
		_set_status("LOAD FAILED  //  INVALID LEVEL FILE", true)
		return
	_cancel_asset_placement()
	_clear_placements()
	document = loaded
	var skipped := 0
	for snapshot: Dictionary in document.placements:
		var placement := _instantiate_placement(
			int(snapshot.get("id", 0)),
			str(snapshot.get("asset_path", ""))
		)
		if placement == null:
			skipped += 1
			continue
		placement.apply_snapshot(snapshot)
	current_file_path = path
	inspector_refreshing = true
	level_name_field.text = document.level_name
	inspector_refreshing = false
	undo_redo.clear_history()
	dirty = false
	_update_window_title()
	_set_status(
		"LOADED %d PLACEMENTS%s" % [
			placements_by_id.size(),
			"  //  %d SKIPPED" % skipped if skipped > 0 else "",
		],
		skipped > 0
	)


func _new_document_now() -> void:
	_cancel_asset_placement()
	_clear_placements()
	document = LevelEditorDocument.new()
	current_file_path = ""
	inspector_refreshing = true
	level_name_field.text = document.level_name
	inspector_refreshing = false
	undo_redo.clear_history()
	dirty = false
	_update_window_title()
	_set_status("NEW LEVEL READY")


func _clear_placements() -> void:
	_select_placement(null)
	for placement: LevelAssetPlacement in placements_by_id.values():
		placement_root.remove_child(placement)
		placement.free()
	placements_by_id.clear()


func _sync_document_from_scene() -> void:
	document.level_name = level_name_field.text.strip_edges()
	if document.level_name.is_empty():
		document.level_name = "Untitled Level"
	document.placements.clear()
	var ids: Array[int] = []
	for placement_id: int in placements_by_id:
		ids.append(placement_id)
	ids.sort()
	for placement_id: int in ids:
		document.placements.append(placements_by_id[placement_id].snapshot())


func _on_level_name_changed(_value: String) -> void:
	if inspector_refreshing:
		return
	_mark_dirty()


func _mark_dirty() -> void:
	dirty = true
	_update_window_title()


func _update_window_title() -> void:
	var display_name := level_name_field.text.strip_edges()
	if display_name.is_empty():
		display_name = "Untitled Level"
	get_window().title = "ScavangeInc Level Editor  //  %s%s" % [
		display_name,
		" *" if dirty else "",
	]


func _prepare_level_directory() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(LevelEditorDocument.DEFAULT_DIRECTORY)
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_ESCAPE and not pending_asset_path.is_empty():
		_cancel_asset_placement()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.physical_keycode == KEY_S:
		if key.shift_pressed:
			_request_save_as()
		else:
			_request_save()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.physical_keycode == KEY_O:
		_request_load()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.physical_keycode == KEY_Z:
		_undo()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.physical_keycode == KEY_Y:
		_redo()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.physical_keycode == KEY_D:
		_duplicate_selected()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_DELETE:
		_delete_selected()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_F:
		_focus_selected()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_R:
		_rotate_asset_quarter_turn()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_Q:
		_set_edit_mode(MODE_SELECT)
	elif key.physical_keycode == KEY_W:
		_set_edit_mode(MODE_MOVE)
	elif key.physical_keycode == KEY_E:
		_set_edit_mode(MODE_ROTATE)
	elif key.physical_keycode == KEY_S:
		_set_edit_mode(MODE_SCALE)


func _set_status(message: String, is_error := false) -> void:
	if status_label == null:
		return
	status_label.text = message.to_upper()
	status_label.add_theme_color_override(
		"font_color",
		Color("ff6747") if is_error else COLOR_MUTED
	)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _add_button(
	parent: Container,
	text: String,
	callback: Callable,
	tooltip: String
) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_separator(parent: HBoxContainer) -> void:
	var separator := VSeparator.new()
	separator.custom_minimum_size.x = 5.0
	parent.add_child(separator)


static func _snapshots_match(a: Dictionary, b: Dictionary) -> bool:
	return (
		(a.get("position", Vector3.ZERO) as Vector3).is_equal_approx(
			b.get("position", Vector3.ZERO)
		)
		and (a.get("rotation", Vector3.ZERO) as Vector3).is_equal_approx(
			b.get("rotation", Vector3.ZERO)
		)
		and (a.get("scale", Vector3.ONE) as Vector3).is_equal_approx(
			b.get("scale", Vector3.ONE)
		)
	)
