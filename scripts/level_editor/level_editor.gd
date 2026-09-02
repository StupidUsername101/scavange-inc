class_name ScavangeLevelEditor
extends Control

const THUMBNAIL_RENDERER := preload(
	"res://scripts/level_editor/level_asset_thumbnail_renderer.gd"
)
const FAVORITES_STORE := preload(
	"res://scripts/level_editor/level_asset_favorites.gd"
)
const ASSEMBLY_STORE := preload(
	"res://scripts/level_editor/level_asset_assembly_store.gd"
)
const ACOUSTIC_STATE_SCRIPT := preload(
	"res://scripts/level_editor/level_acoustic_editor_state.gd"
)
const ACOUSTIC_RUNTIME_BUILDER := preload(
	"res://scripts/level_editor/level_acoustic_runtime_builder.gd"
)
const SPEAKER_MARKER_SCRIPT := preload(
	"res://scripts/level_editor/level_speaker_authoring_marker.gd"
)
const RUNTIME_SELECTION := preload(
	"res://scripts/level_editor/level_runtime_selection.gd"
)
const BUILDING_KITS := preload(
	"res://scripts/level_editor/level_building_kit_catalog.gd"
)
const BUILDING_SHELL_GENERATOR := preload(
	"res://scripts/level_editor/level_building_shell_generator.gd"
)
const TRANSFORM_GIZMO := preload(
	"res://scripts/level_editor/level_transform_gizmo.gd"
)
const LIGHT_AUTHORING := preload(
	"res://scripts/level_editor/level_light_authoring.gd"
)
const LIGHT_MARKER_SCRIPT := preload(
	"res://scripts/level_editor/level_light_authoring_marker.gd"
)
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
const CONTENT_TOP := 140.0
const CONTENT_BOTTOM_MARGIN := 120.0
const QUARTER_TURN_RADIANS := PI * 0.5
const FINE_ROTATION_RADIANS := PI / 12.0
const SURFACE_CLEARANCE := 0.0
const DEFAULT_CATALOG_WIDTH := 400.0
const MINIMUM_CATALOG_WIDTH := 292.0
const MAXIMUM_CATALOG_WIDTH := 720.0
const MINIMUM_VIEWPORT_WIDTH := 360.0
const INSPECTOR_AND_GUTTERS_WIDTH := 336.0
const CATALOG_GUTTER := 8.0
const CATALOG_RESIZE_HANDLE_WIDTH := 12.0
const MINIMUM_CATALOG_THUMBNAIL_WIDTH := 136.0
const MAXIMUM_CATALOG_THUMBNAIL_WIDTH := 208.0
const FAVORITES_FILTER := "__favorites__"
const ACOUSTIC_TOOL_SELECT := &"select"
const ACOUSTIC_TOOL_PLACE_PROBE := &"place_probe"
const CONTEXT_MERGE_ASSEMBLY := 1
const CONTEXT_UNGROUP_ASSEMBLY := 2
const CONTEXT_FOCUS := 10
const CONTEXT_DUPLICATE := 11
const CONTEXT_DELETE := 12
const MARK_AS_STATIC := 20
const MARK_AS_ITEM := 21
const MARK_AS_VALUABLE := 22
const BUILDING_FILTER_ALL := "__all_building__"

var document := LevelEditorDocument.new()
var current_file_path := ""
var dirty := false
var catalog: Array[Dictionary] = []
var filtered_catalog: Array[Dictionary] = []
var catalog_entries_by_path: Dictionary[String, Dictionary] = {}
var catalog_item_indices_by_path: Dictionary[String, int] = {}
var favorite_asset_paths: Dictionary[String, bool] = {}
var favorite_filter_option_index := -1
var favorites_storage_path := FAVORITES_STORE.DEFAULT_PATH
var assembly_storage_path := ASSEMBLY_STORE.DEFAULT_PATH
var assembly_definitions_by_id: Dictionary[String, Dictionary] = {}
var placements_by_id: Dictionary[int, LevelAssetPlacement] = {}
var selected_placements_by_id: Dictionary[int, LevelAssetPlacement] = {}
var selected_placement: LevelAssetPlacement
var selected_catalog_path := ""
var pending_asset_path := ""
var pending_assembly_id := ""
var undo_redo := UndoRedo.new()

var viewport_container: LevelEditorViewport
var editor_viewport: SubViewport
var editor_world: Node3D
var placement_root: Node3D
var acoustic_marker_root: Node3D
var speaker_marker_root: Node3D
var light_marker_root: Node3D
var acoustic_state: LevelAcousticEditorState
var editor_camera: Camera3D
var placement_cursor: MeshInstance3D
var transform_gizmo: Node3D
var placement_preview: LevelAssetPlacement
var assembly_preview: LevelAssetAssemblyPreview
var thumbnail_renderer
var catalog_panel: PanelContainer
var catalog_resize_handle: Control
var asset_list: LevelAssetCatalogList
var search_field: LineEdit
var category_filter: OptionButton
var building_mode_button: Button
var building_controls: VBoxContainer
var building_kit_filter: OptionButton
var building_role_filter: OptionButton
var building_socket_snap_button: Button
var building_roof_button: CheckButton
var building_room_button: Button
var building_storey_button: Button
var building_compatible_options: OptionButton
var building_replace_button: Button
var building_status_label: Label
var result_count_label: Label
var used_assets_row: HBoxContainer
var used_assets_empty_label: Label
var used_asset_buttons_by_path: Dictionary[String, Button] = {}
var assembly_shelf_row: HBoxContainer
var assembly_shelf_empty_label: Label
var assembly_buttons_by_id: Dictionary[String, Button] = {}
var preview: LevelAssetPreview
var preview_tabs: TabContainer
var light_tab_index := -1
var light_list_field: OptionButton
var light_type_field: OptionButton
var light_name_field: LineEdit
var light_color_field: ColorPickerButton
var light_energy_field: SpinBox
var light_range_field: SpinBox
var light_attenuation_field: SpinBox
var light_shadow_field: CheckButton
var light_spot_angle_field: SpinBox
var light_spot_softness_field: SpinBox
var light_rotation_fields: Array[SpinBox] = []
var light_place_button: Button
var light_delete_button: Button
var light_status_label: Label
var catalog_selection_label: Label
var selection_label: Label
var status_label: Label
var level_name_field: LineEdit
var snap_button: Button
var snap_step: SpinBox
var surface_align_button: Button
var sound_authoring_button: Button
var speaker_authoring_button: Button
var acoustic_panel: PanelContainer
var acoustic_place_probe_button: Button
var acoustic_status_label: Label
var acoustic_selection_label: Label
var acoustic_spacing_field: SpinBox
var acoustic_height_field: SpinBox
var acoustic_profile_field: OptionButton
var acoustic_guided_button: Button
var acoustic_position_fields: Array[SpinBox] = []
var speaker_authoring_panel: PanelContainer
var speaker_name_field: LineEdit
var speaker_status_label: Label
var speaker_finish_button: Button
var mode_buttons: Dictionary[StringName, Button] = {}
var transform_fields: Dictionary[StringName, Array] = {}
var save_dialog: FileDialog
var load_dialog: FileDialog
var discard_dialog: ConfirmationDialog
var selection_context_menu: PopupMenu
var mark_as_menu: PopupMenu
var item_properties_dialog: ConfirmationDialog
var item_mass_field: SpinBox
var item_value_per_mass_field: SpinBox
var item_value_row: HBoxContainer
var item_total_value_label: Label
var pending_gameplay_role := LevelEditorDocument.PLACEMENT_ROLE_STATIC
var assembly_name_dialog: ConfirmationDialog
var assembly_name_field: LineEdit
var pending_merge_placement_ids: Array[int] = []
var pending_discard_action: StringName = &""
var building_mode_enabled := false
var building_room_tool_active := false
var building_room_dragging := false
var building_room_corner_a := Vector3.INF
var building_room_corner_b := Vector3.INF
var building_room_preview: MeshInstance3D
var building_room_wall_paths: Dictionary[String, String] = {}

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
var transform_drag_start_snapshots: Array[Dictionary] = []
var transform_drag_start_pivot := Vector3.ZERO
var transform_drag_move_offset := Vector3.ZERO
var transform_drag_axis := Vector3.ZERO
var transform_drag_axis_index := -1
var transform_drag_axis_start_parameter := 0.0
var transform_drag_rotation_start_vector := Vector3.ZERO
var last_placement_viewport_position := Vector2.ZERO
var has_placement_pointer := false
var placement_rotation := Vector3.ZERO
var rebuilding_placements := false
var catalog_width := DEFAULT_CATALOG_WIDTH
var catalog_grid_columns := 1
var catalog_resize_dragging := false
var catalog_resize_start_mouse_x := 0.0
var catalog_resize_start_width := DEFAULT_CATALOG_WIDTH
var acoustic_authoring_enabled := false
var acoustic_tool: StringName = ACOUSTIC_TOOL_SELECT
var acoustic_inspector_refreshing := false
var rebuilding_acoustics := false
var sound_systems_by_id: Dictionary[int, Dictionary] = {}
var speaker_authoring_active := false
var speaker_draft_markers: Array[LevelSpeakerAuthoringMarker] = []
var speaker_cursor: LevelSpeakerAuthoringMarker
var authored_lights_by_id: Dictionary[int, Node3D] = {}
var selected_light_id := 0
var light_placement_active := false
var light_cursor: Node3D
var light_inspector_refreshing := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	favorite_asset_paths = FAVORITES_STORE.load_paths(favorites_storage_path)
	assembly_definitions_by_id = ASSEMBLY_STORE.load_definitions(
		assembly_storage_path
	)
	_build_interface()
	resized.connect(_on_editor_resized)
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
	_build_thumbnail_renderer()
	_build_used_assets_bar()
	_build_assembly_shelf()
	_build_catalog_panel()
	_build_viewport_panel()
	_build_inspector_panel()
	_build_acoustic_panel()
	_build_speaker_authoring_panel()
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
		"GRID",
		_toggle_snap,
		"Quantize placement and movement; disable for exact free placement"
	)
	snap_button.toggle_mode = true
	snap_button.button_pressed = false
	snap_step = SpinBox.new()
	snap_step.custom_minimum_size.x = 82.0
	snap_step.min_value = 0.05
	snap_step.max_value = 10.0
	snap_step.step = 0.05
	snap_step.value = 0.5
	snap_step.suffix = " m"
	snap_step.value_changed.connect(_on_snap_step_changed)
	row.add_child(snap_step)
	surface_align_button = _add_button(
		row,
		"ALIGN",
		_toggle_surface_alignment,
		"Orient the asset's local up axis to the floor, wall, ceiling, or prop under the pointer"
	)
	surface_align_button.toggle_mode = true
	building_mode_button = _add_button(
		row,
		"BUILD",
		_toggle_building_mode,
		"Show compatible modular construction kits, socket snapping, room shells, and storeys"
	)
	building_mode_button.toggle_mode = true
	_add_separator(row)
	sound_authoring_button = _add_button(
		row,
		"SOUND",
		_toggle_acoustic_authoring,
		"Author the reusable probe field and explicit doorway or aperture portals"
	)
	sound_authoring_button.toggle_mode = true
	speaker_authoring_button = _add_button(
		row,
		"PA ARRAY",
		_begin_speaker_system_authoring,
		"Place any number of speakers, then finalize them as one synchronized sound system"
	)
	speaker_authoring_button.toggle_mode = true
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	level_name_field = LineEdit.new()
	level_name_field.custom_minimum_size.x = 220.0
	level_name_field.placeholder_text = "Level name"
	level_name_field.text_changed.connect(_on_level_name_changed)
	row.add_child(level_name_field)


func _build_thumbnail_renderer() -> void:
	thumbnail_renderer = THUMBNAIL_RENDERER.new()
	thumbnail_renderer.name = "AssetThumbnailRenderer"
	thumbnail_renderer.thumbnail_ready.connect(_on_asset_thumbnail_ready)
	add_child(thumbnail_renderer)


func _build_used_assets_bar() -> void:
	var panel := _panel()
	panel.anchor_right = 1.0
	panel.offset_left = 8.0
	panel.offset_top = 60.0
	panel.offset_right = -8.0
	panel.offset_bottom = 132.0
	add_child(panel)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var title := _label("USED IN LEVEL", 13, COLOR_TEXT)
	title.custom_minimum_size.x = 112.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "UsedAssetsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	used_assets_row = HBoxContainer.new()
	used_assets_row.name = "UsedAssetsRow"
	used_assets_row.add_theme_constant_override("separation", 6)
	scroll.add_child(used_assets_row)
	used_assets_empty_label = _label(
		"PLACE AN ASSET AND IT WILL STAY ONE CLICK AWAY HERE",
		12,
		COLOR_MUTED
	)
	used_assets_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	used_assets_row.add_child(used_assets_empty_label)


func _build_assembly_shelf() -> void:
	var panel := _panel()
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = -112.0
	panel.offset_right = -8.0
	panel.offset_bottom = -34.0
	add_child(panel)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT,
		Control.PRESET_MODE_MINSIZE,
		7
	)
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var title := _label("ASSEMBLIES", 13, COLOR_ACCENT)
	title.custom_minimum_size.x = 112.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.tooltip_text = (
		"Reusable groups created from the selected level assets"
	)
	row.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "AssemblyShelfScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	assembly_shelf_row = HBoxContainer.new()
	assembly_shelf_row.name = "AssemblyShelfRow"
	assembly_shelf_row.add_theme_constant_override("separation", 6)
	scroll.add_child(assembly_shelf_row)
	_refresh_assembly_shelf()


func _build_catalog_panel() -> void:
	catalog_panel = _panel()
	catalog_panel.anchor_bottom = 1.0
	catalog_panel.offset_left = CATALOG_GUTTER
	catalog_panel.offset_top = CONTENT_TOP
	catalog_panel.offset_right = CATALOG_GUTTER + catalog_width
	catalog_panel.offset_bottom = -CONTENT_BOTTOM_MARGIN
	add_child(catalog_panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 9)
	column.add_theme_constant_override("separation", 7)
	catalog_panel.add_child(column)
	column.add_child(_label("ASSET CATALOG", 18, COLOR_TEXT))
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search models and packs..."
	search_field.clear_button_enabled = true
	search_field.text_changed.connect(_on_catalog_filter_changed)
	column.add_child(search_field)
	category_filter = OptionButton.new()
	category_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_filter.item_selected.connect(_on_category_selected)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 5)
	filter_row.add_child(category_filter)
	_add_button(
		filter_row,
		"REFRESH",
		_reload_asset_catalog,
		"Rescan asset folders for newly imported GLB models"
	)
	column.add_child(filter_row)
	building_controls = VBoxContainer.new()
	building_controls.name = "BuildingKitControls"
	building_controls.visible = false
	building_controls.add_theme_constant_override("separation", 5)
	column.add_child(building_controls)
	var kit_row := HBoxContainer.new()
	kit_row.add_theme_constant_override("separation", 5)
	building_controls.add_child(kit_row)
	building_kit_filter = OptionButton.new()
	building_kit_filter.name = "BuildingKitFilter"
	building_kit_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_kit_filter.tooltip_text = "Only show pieces from one compatible construction family"
	building_kit_filter.item_selected.connect(_on_building_filter_changed)
	kit_row.add_child(building_kit_filter)
	building_role_filter = OptionButton.new()
	building_role_filter.name = "BuildingRoleFilter"
	building_role_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_role_filter.tooltip_text = "Show walls, openings, floors, roofs, stairs, or supports"
	building_role_filter.item_selected.connect(_on_building_filter_changed)
	kit_row.add_child(building_role_filter)
	var build_action_row := HBoxContainer.new()
	build_action_row.add_theme_constant_override("separation", 5)
	building_controls.add_child(build_action_row)
	building_socket_snap_button = _add_button(
		build_action_row,
		"SOCKET SNAP",
		_toggle_building_socket_snap,
		"Join compatible wall endpoints, slab corners, and structural anchors using their actual mesh bounds"
	)
	building_socket_snap_button.toggle_mode = true
	building_socket_snap_button.button_pressed = true
	building_room_button = _add_button(
		build_action_row,
		"ROOM SHELL",
		_toggle_room_shell_tool,
		"Drag a rectangle to generate modular walls and a floor from the selected kit"
	)
	building_room_button.toggle_mode = true
	building_roof_button = CheckButton.new()
	building_roof_button.text = "ROOF"
	building_roof_button.button_pressed = true
	building_roof_button.tooltip_text = "Generate the kit's roof pieces at wall height"
	build_action_row.add_child(building_roof_button)
	var compatible_row := HBoxContainer.new()
	compatible_row.add_theme_constant_override("separation", 5)
	building_controls.add_child(compatible_row)
	building_compatible_options = OptionButton.new()
	building_compatible_options.name = "CompatibleBuildingPieces"
	building_compatible_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_compatible_options.tooltip_text = "Wall, doorway, and window variants sharing the selected segment socket"
	compatible_row.add_child(building_compatible_options)
	building_replace_button = _add_button(
		compatible_row,
		"REPLACE",
		_replace_selected_building_piece,
		"Swap the selected segment while preserving its placement and authored metadata"
	)
	building_storey_button = _add_button(
		compatible_row,
		"STOREY +",
		_duplicate_building_storey,
		"Duplicate the selected generated room storey at its measured wall height"
	)
	building_status_label = _label(
		"SELECT A WALL PIECE, THEN DRAG ROOM SHELL",
		10,
		COLOR_MUTED
	)
	building_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	building_controls.add_child(building_status_label)
	asset_list = LevelAssetCatalogList.new()
	asset_list.name = "AssetCatalogList"
	asset_list.icon_mode = ItemList.ICON_MODE_TOP
	asset_list.same_column_width = true
	asset_list.max_text_lines = 2
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.allow_reselect = true
	asset_list.item_selected.connect(_on_catalog_item_selected)
	asset_list.item_activated.connect(_on_catalog_item_activated)
	asset_list.favorite_toggle_requested.connect(_on_asset_favorite_toggle_requested)
	asset_list.visible_asset_range_changed.connect(
		_on_catalog_visible_range_changed
	)
	asset_list.set_favorite_paths(favorite_asset_paths)
	_configure_catalog_grid()
	column.add_child(asset_list)
	result_count_label = _label("INDEXING ASSETS...", 12, COLOR_MUTED)
	column.add_child(result_count_label)
	var hint := _label(
		"CLICK / WHEEL SELECT  //  PLACE ON ANY SURFACE  //  RMB CANCELS",
		11,
		COLOR_MUTED
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_build_catalog_resize_handle()


func _build_catalog_resize_handle() -> void:
	catalog_resize_handle = Control.new()
	catalog_resize_handle.name = "CatalogResizeHandle"
	catalog_resize_handle.anchor_bottom = 1.0
	catalog_resize_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	catalog_resize_handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	catalog_resize_handle.tooltip_text = (
		"Drag to resize the asset catalog and its model previews"
	)
	catalog_resize_handle.gui_input.connect(_on_catalog_resize_handle_input)
	add_child(catalog_resize_handle)
	var grip := ColorRect.new()
	grip.color = COLOR_BORDER
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.anchor_left = 0.5
	grip.anchor_right = 0.5
	grip.anchor_bottom = 1.0
	grip.offset_left = -1.0
	grip.offset_top = 5.0
	grip.offset_right = 1.0
	grip.offset_bottom = -5.0
	catalog_resize_handle.add_child(grip)
	_position_catalog_resize_handle()


func _build_viewport_panel() -> void:
	viewport_container = LevelEditorViewport.new()
	viewport_container.name = "EditorViewportContainer"
	viewport_container.anchor_right = 1.0
	viewport_container.anchor_bottom = 1.0
	viewport_container.offset_left = CATALOG_GUTTER * 2.0 + catalog_width
	viewport_container.offset_top = CONTENT_TOP
	viewport_container.offset_right = -320.0
	viewport_container.offset_bottom = -CONTENT_BOTTOM_MARGIN
	viewport_container.stretch = true
	viewport_container.focus_mode = Control.FOCUS_ALL
	viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_container.asset_dropped.connect(_on_asset_dropped)
	viewport_container.gui_input.connect(_on_viewport_input)
	add_child(viewport_container)


func _input(event: InputEvent) -> void:
	if not catalog_resize_dragging:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_set_catalog_width(
			catalog_resize_start_width
			+ motion.global_position.x
			- catalog_resize_start_mouse_x
		)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
			catalog_resize_dragging = false
			get_viewport().set_input_as_handled()


func _on_catalog_resize_handle_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button := event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	catalog_resize_dragging = button.pressed
	if button.pressed:
		catalog_resize_start_mouse_x = button.global_position.x
		catalog_resize_start_width = catalog_width
	catalog_resize_handle.accept_event()


func _on_editor_resized() -> void:
	_set_catalog_width(catalog_width)


func _set_catalog_width(requested_width: float) -> void:
	var available_max := maxf(
		size.x - INSPECTOR_AND_GUTTERS_WIDTH - MINIMUM_VIEWPORT_WIDTH,
		MINIMUM_CATALOG_WIDTH
	)
	catalog_width = clampf(
		requested_width,
		MINIMUM_CATALOG_WIDTH,
		minf(MAXIMUM_CATALOG_WIDTH, available_max)
	)
	if catalog_panel != null:
		catalog_panel.offset_right = CATALOG_GUTTER + catalog_width
	if viewport_container != null:
		viewport_container.offset_left = CATALOG_GUTTER * 2.0 + catalog_width
	_position_catalog_resize_handle()
	_position_acoustic_panel()
	_position_speaker_authoring_panel()
	if asset_list != null:
		var column_count_changed := _configure_catalog_grid()
		if column_count_changed and not catalog.is_empty():
			_refresh_catalog_list()
		else:
			asset_list.invalidate_visible_range()


func _position_catalog_resize_handle() -> void:
	if catalog_resize_handle == null:
		return
	var center_x := CATALOG_GUTTER + catalog_width
	catalog_resize_handle.offset_left = (
		center_x - CATALOG_RESIZE_HANDLE_WIDTH * 0.5
	)
	catalog_resize_handle.offset_top = CONTENT_TOP
	catalog_resize_handle.offset_right = (
		center_x + CATALOG_RESIZE_HANDLE_WIDTH * 0.5
	)
	catalog_resize_handle.offset_bottom = -CONTENT_BOTTOM_MARGIN


func _position_acoustic_panel() -> void:
	if acoustic_panel == null:
		return
	var left := CATALOG_GUTTER * 2.0 + catalog_width + 8.0
	acoustic_panel.offset_left = left
	acoustic_panel.offset_right = left + 430.0


func _position_speaker_authoring_panel() -> void:
	if speaker_authoring_panel == null:
		return
	var left := CATALOG_GUTTER * 2.0 + catalog_width + 8.0
	speaker_authoring_panel.offset_left = left
	speaker_authoring_panel.offset_right = left + 430.0


func _catalog_thumbnail_size(for_catalog_width: float) -> Vector2i:
	var expansion := inverse_lerp(
		MINIMUM_CATALOG_WIDTH,
		MAXIMUM_CATALOG_WIDTH,
		clampf(for_catalog_width, MINIMUM_CATALOG_WIDTH, MAXIMUM_CATALOG_WIDTH)
	)
	var icon_width := roundi(lerpf(
		MINIMUM_CATALOG_THUMBNAIL_WIDTH,
		MAXIMUM_CATALOG_THUMBNAIL_WIDTH,
		expansion
	))
	return Vector2i(icon_width, roundi(float(icon_width) * 0.75))


func _configure_catalog_grid() -> bool:
	if asset_list == null:
		return false
	var icon_size := _catalog_thumbnail_size(catalog_width)
	var column_width := icon_size.x + 18
	var usable_width := maxf(catalog_width - 24.0, float(column_width))
	var next_column_count := maxi(
		1,
		int(floor(usable_width / float(column_width)))
	)
	var changed := next_column_count != catalog_grid_columns
	catalog_grid_columns = next_column_count
	asset_list.fixed_icon_size = icon_size
	asset_list.fixed_column_width = column_width
	asset_list.max_columns = catalog_grid_columns
	return changed


func _build_inspector_panel() -> void:
	var panel := _panel()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -312.0
	panel.offset_top = CONTENT_TOP
	panel.offset_right = -8.0
	panel.offset_bottom = -CONTENT_BOTTOM_MARGIN
	add_child(panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 9)
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	column.add_child(_label("EDITOR PREVIEW", 18, COLOR_TEXT))
	preview_tabs = TabContainer.new()
	preview_tabs.name = "PreviewTabs"
	preview_tabs.custom_minimum_size = Vector2(280.0, 300.0)
	preview_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_tabs.tab_changed.connect(_on_preview_tab_changed)
	column.add_child(preview_tabs)
	var asset_page := VBoxContainer.new()
	asset_page.name = "ASSET"
	asset_page.add_theme_constant_override("separation", 5)
	preview_tabs.add_child(asset_page)
	preview = LevelAssetPreview.new()
	preview.name = "AssetPreview"
	preview.custom_minimum_size = Vector2(280.0, 190.0)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_page.add_child(preview)
	asset_page.add_child(_label(
		"DRAG PREVIEW: ORBIT  //  WHEEL: ZOOM  //  DOUBLE-CLICK: RESET",
		10,
		COLOR_MUTED
	))
	catalog_selection_label = _label("SELECT AN ASSET", 12, COLOR_MUTED)
	catalog_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	catalog_selection_label.custom_minimum_size.y = 36.0
	asset_page.add_child(catalog_selection_label)
	_build_light_preview_tab()
	column.add_child(HSeparator.new())
	selection_label = _label("NO PLACEMENT SELECTED", 15, COLOR_TEXT)
	selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(selection_label)
	var selection_hint := _label(
		"SHIFT/CTRL + CLICK: GROUP  //  CTRL+A: ALL",
		10,
		COLOR_MUTED
	)
	selection_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(selection_hint)
	_add_transform_group(column, &"position", "POSITION", -10000.0, 10000.0, 0.05)
	_add_transform_group(column, &"rotation", "ROTATION", -3600.0, 3600.0, 1.0, "°")
	_add_transform_group(column, &"scale", "SCALE", 0.01, 1000.0, 0.01)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	column.add_child(action_row)
	_add_button(action_row, "FOCUS", _focus_selected, "Frame all selected placements")
	_add_button(action_row, "DUPLICATE", _duplicate_selected, "Duplicate all selected placements")
	_add_button(action_row, "DELETE", _delete_selected, "Delete all selected placements")
	_refresh_inspector()


func _build_light_preview_tab() -> void:
	var light_page := VBoxContainer.new()
	light_page.name = "LIGHTS"
	light_page.add_theme_constant_override("separation", 5)
	preview_tabs.add_child(light_page)
	light_tab_index = preview_tabs.get_tab_count() - 1
	light_status_label = _label("NEW LIGHT SETTINGS", 11, COLOR_MUTED)
	light_page.add_child(light_status_label)
	var selection_row := HBoxContainer.new()
	selection_row.add_theme_constant_override("separation", 4)
	light_page.add_child(selection_row)
	light_list_field = OptionButton.new()
	light_list_field.name = "AuthoredLightSelection"
	light_list_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	light_list_field.item_selected.connect(_on_light_list_selected)
	selection_row.add_child(light_list_field)
	light_delete_button = _add_button(
		selection_row,
		"DELETE",
		_delete_selected_light,
		"Delete the selected authored light"
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	light_page.add_child(scroll)
	var settings := VBoxContainer.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override("separation", 4)
	scroll.add_child(settings)
	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 4)
	settings.add_child(identity_row)
	light_type_field = OptionButton.new()
	light_type_field.name = "AuthoredLightType"
	for type: StringName in [
		LIGHT_AUTHORING.TYPE_OMNI,
		LIGHT_AUTHORING.TYPE_SPOT,
		LIGHT_AUTHORING.TYPE_DIRECTIONAL,
	]:
		light_type_field.add_item(LIGHT_AUTHORING.type_label(type))
		light_type_field.set_item_metadata(light_type_field.item_count - 1, type)
	light_type_field.item_selected.connect(_on_light_setting_changed.unbind(1))
	identity_row.add_child(light_type_field)
	light_name_field = LineEdit.new()
	light_name_field.name = "AuthoredLightName"
	light_name_field.placeholder_text = "Light name"
	light_name_field.max_length = 80
	light_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	light_name_field.text_changed.connect(_on_light_setting_changed.unbind(1))
	identity_row.add_child(light_name_field)
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 4)
	settings.add_child(color_row)
	color_row.add_child(_label("COLOR", 10, COLOR_MUTED))
	light_color_field = ColorPickerButton.new()
	light_color_field.name = "AuthoredLightColor"
	light_color_field.color = LIGHT_AUTHORING.DEFAULT_COLOR
	light_color_field.custom_minimum_size = Vector2(74.0, 28.0)
	light_color_field.color_changed.connect(_on_light_setting_changed.unbind(1))
	color_row.add_child(light_color_field)
	light_shadow_field = CheckButton.new()
	light_shadow_field.name = "AuthoredLightShadows"
	light_shadow_field.text = "SHADOWS"
	light_shadow_field.button_pressed = true
	light_shadow_field.toggled.connect(_on_light_setting_changed.unbind(1))
	color_row.add_child(light_shadow_field)
	var numeric_grid := GridContainer.new()
	numeric_grid.columns = 2
	numeric_grid.add_theme_constant_override("h_separation", 5)
	numeric_grid.add_theme_constant_override("v_separation", 3)
	settings.add_child(numeric_grid)
	light_energy_field = _add_light_numeric_field(
		numeric_grid, "ENERGY", 0.0, LIGHT_AUTHORING.MAXIMUM_ENERGY, 0.05, 2.0
	)
	light_range_field = _add_light_numeric_field(
		numeric_grid, "RANGE", 0.1, LIGHT_AUTHORING.MAXIMUM_RANGE, 0.1, 12.0, " m"
	)
	light_attenuation_field = _add_light_numeric_field(
		numeric_grid, "FALLOFF", 0.0, 4.0, 0.05, 1.0
	)
	light_spot_angle_field = _add_light_numeric_field(
		numeric_grid, "CONE", 1.0, 89.0, 1.0, 42.0, "°"
	)
	light_spot_softness_field = _add_light_numeric_field(
		numeric_grid, "EDGE", 0.0, 4.0, 0.05, 1.0
	)
	settings.add_child(_label("ROTATION", 10, COLOR_MUTED))
	var rotation_row := HBoxContainer.new()
	rotation_row.add_theme_constant_override("separation", 4)
	settings.add_child(rotation_row)
	for axis_name: String in ["X", "Y", "Z"]:
		var rotation_field := SpinBox.new()
		rotation_field.name = "AuthoredLightRotation%s" % axis_name
		rotation_field.min_value = -360.0
		rotation_field.max_value = 360.0
		rotation_field.step = 1.0
		rotation_field.suffix = "°"
		rotation_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rotation_field.value_changed.connect(_on_light_setting_changed.unbind(1))
		rotation_row.add_child(rotation_field)
		light_rotation_fields.append(rotation_field)
	light_place_button = _add_button(
		settings,
		"PLACE LIGHT",
		_toggle_light_placement,
		"Arm the configured light; click surfaces to place copies and right-click to finish"
	)
	light_place_button.toggle_mode = true
	_refresh_light_inspector()


func _add_light_numeric_field(
	parent: GridContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step_value: float,
	default_value: float,
	suffix := ""
) -> SpinBox:
	parent.add_child(_label(label_text, 10, COLOR_MUTED))
	var field := SpinBox.new()
	field.name = "AuthoredLight%s" % label_text.capitalize()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step_value
	field.value = default_value
	field.suffix = suffix
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.value_changed.connect(_on_light_setting_changed.unbind(1))
	parent.add_child(field)
	return field


func _on_preview_tab_changed(tab_index: int) -> void:
	if tab_index != light_tab_index:
		_cancel_light_placement()
	_refresh_light_inspector()
	_refresh_transform_gizmo()


func _on_light_list_selected(index: int) -> void:
	if light_inspector_refreshing or light_list_field == null:
		return
	_select_authored_light(int(light_list_field.get_item_metadata(index)))


func _select_authored_light(light_id: int) -> void:
	selected_light_id = light_id if authored_lights_by_id.has(light_id) else 0
	for marker_id: int in authored_lights_by_id:
		authored_lights_by_id[marker_id].call(
			"set_selected",
			marker_id == selected_light_id
		)
	_refresh_light_inspector()


func _refresh_light_inspector() -> void:
	if light_list_field == null:
		return
	light_inspector_refreshing = true
	light_list_field.clear()
	light_list_field.add_item("NEW LIGHT SETTINGS")
	light_list_field.set_item_metadata(0, 0)
	var selected_index := 0
	var ids: Array[int] = []
	for light_id: int in authored_lights_by_id:
		ids.append(light_id)
	ids.sort()
	for light_id: int in ids:
		var marker: Node3D = authored_lights_by_id[light_id]
		var descriptor: Dictionary = marker.call("descriptor")
		var index := light_list_field.item_count
		light_list_field.add_item("%03d  %s" % [
			light_id,
			str(descriptor.get("display_name", "LIGHT")).to_upper(),
		])
		light_list_field.set_item_metadata(index, light_id)
		if light_id == selected_light_id:
			selected_index = index
	light_list_field.select(selected_index)
	var marker := authored_lights_by_id.get(selected_light_id) as Node3D
	if marker != null:
		_apply_light_descriptor_to_fields(marker.call("descriptor"))
		light_status_label.text = "EDITING LIGHT %03d" % selected_light_id
	elif light_status_label != null:
		light_status_label.text = "%d LIGHT%s  //  NEW SETTINGS" % [
			authored_lights_by_id.size(),
			"" if authored_lights_by_id.size() == 1 else "S",
		]
	if light_delete_button != null:
		light_delete_button.disabled = marker == null
	light_inspector_refreshing = false
	_refresh_light_field_availability()


func _apply_light_descriptor_to_fields(descriptor: Dictionary) -> void:
	var safe: Dictionary = LIGHT_AUTHORING.sanitize_descriptor(descriptor)
	if safe.is_empty():
		return
	var type: StringName = safe["type"]
	for index: int in range(light_type_field.item_count):
		if light_type_field.get_item_metadata(index) == type:
			light_type_field.select(index)
			break
	light_name_field.text = safe["display_name"]
	light_color_field.color = safe["color"]
	light_energy_field.value = safe["energy"]
	light_range_field.value = safe["range"]
	light_attenuation_field.value = safe["attenuation"]
	light_shadow_field.button_pressed = safe["shadows"]
	light_spot_angle_field.value = safe["spot_angle"]
	light_spot_softness_field.value = safe["spot_angle_attenuation"]
	var rotation_degrees: Vector3 = safe["rotation"] * (180.0 / PI)
	for axis_index: int in range(light_rotation_fields.size()):
		light_rotation_fields[axis_index].value = rotation_degrees[axis_index]


func _on_light_setting_changed() -> void:
	if light_inspector_refreshing:
		return
	_refresh_light_field_availability()
	var marker := authored_lights_by_id.get(selected_light_id) as Node3D
	if marker != null:
		var previous: Dictionary = marker.call("descriptor")
		var next := _light_descriptor_from_fields(
			selected_light_id,
			previous.get("position", Vector3.ZERO),
			_light_field_rotation()
		)
		marker.call("configure", next, true)
		_mark_dirty()
		_refresh_light_selection_label_only()
	elif light_placement_active:
		_update_light_cursor(last_placement_viewport_position)


func _refresh_light_selection_label_only() -> void:
	if light_list_field == null:
		return
	for index: int in range(light_list_field.item_count):
		if int(light_list_field.get_item_metadata(index)) != selected_light_id:
			continue
		var marker := authored_lights_by_id.get(selected_light_id) as Node3D
		if marker != null:
			light_list_field.set_item_text(index, "%03d  %s" % [
				selected_light_id,
				str((marker.call("descriptor") as Dictionary).get(
					"display_name", "LIGHT"
				)).to_upper(),
			])
		return


func _refresh_light_field_availability() -> void:
	if light_type_field == null:
		return
	var type: StringName = light_type_field.get_item_metadata(
		light_type_field.selected
	)
	var is_spot := type == LIGHT_AUTHORING.TYPE_SPOT
	var has_range := type != LIGHT_AUTHORING.TYPE_DIRECTIONAL
	light_range_field.editable = has_range
	light_attenuation_field.editable = has_range
	light_spot_angle_field.editable = is_spot
	light_spot_softness_field.editable = is_spot


func _light_descriptor_from_fields(
	light_id: int,
	position: Vector3,
	rotation: Vector3
) -> Dictionary:
	var type: StringName = LIGHT_AUTHORING.TYPE_OMNI
	if light_type_field != null and light_type_field.item_count > 0:
		type = light_type_field.get_item_metadata(light_type_field.selected)
	var result: Dictionary = LIGHT_AUTHORING.create_descriptor(
		light_id,
		type,
		position,
		rotation,
		light_name_field.text if light_name_field != null else ""
	)
	result["color"] = light_color_field.color
	result["energy"] = light_energy_field.value
	result["range"] = light_range_field.value
	result["attenuation"] = light_attenuation_field.value
	result["shadows"] = light_shadow_field.button_pressed
	result["spot_angle"] = light_spot_angle_field.value
	result["spot_angle_attenuation"] = light_spot_softness_field.value
	return LIGHT_AUTHORING.sanitize_descriptor(result)


func _light_field_rotation() -> Vector3:
	var result := Vector3.ZERO
	for axis_index: int in range(mini(light_rotation_fields.size(), 3)):
		result[axis_index] = deg_to_rad(light_rotation_fields[axis_index].value)
	return result


func _toggle_light_placement() -> void:
	if light_place_button != null and light_place_button.button_pressed:
		_begin_light_placement()
	else:
		_cancel_light_placement()


func _begin_light_placement() -> void:
	if building_room_tool_active:
		_cancel_room_shell_tool()
	if speaker_authoring_active:
		_cancel_speaker_system_authoring()
	if acoustic_authoring_enabled:
		_toggle_acoustic_authoring()
	_cancel_asset_placement()
	light_placement_active = true
	selected_light_id = 0
	if light_place_button != null:
		light_place_button.button_pressed = true
	_ensure_light_cursor()
	light_cursor.visible = false
	_refresh_light_inspector()
	_refresh_transform_gizmo()
	_set_status("LIGHT ARMED  //  CLICK A SURFACE TO PLACE  //  RMB CANCELS")


func _cancel_light_placement() -> void:
	if not light_placement_active:
		return
	light_placement_active = false
	if light_cursor != null:
		light_cursor.visible = false
	if light_place_button != null:
		light_place_button.button_pressed = false
	_refresh_transform_gizmo()
	_set_status("LIGHT PLACEMENT CANCELLED")


func _ensure_light_cursor() -> void:
	if light_cursor != null and is_instance_valid(light_cursor):
		return
	light_cursor = LIGHT_MARKER_SCRIPT.new() as Node3D
	light_cursor.name = "LightPlacementCursor"
	light_cursor.process_mode = Node.PROCESS_MODE_DISABLED
	light_marker_root.add_child(light_cursor)


func _update_light_cursor(viewport_position: Vector2) -> void:
	if not light_placement_active:
		return
	last_placement_viewport_position = viewport_position
	_ensure_light_cursor()
	var hit := _screen_to_placement_hit(viewport_position)
	light_cursor.visible = not hit.is_empty()
	if hit.is_empty():
		return
	var placement_transform := _light_transform_for_hit(hit)
	var descriptor := _light_descriptor_from_fields(
		maxi(document.next_light_id, 1),
		placement_transform.origin,
		placement_transform.basis.get_euler()
	)
	light_cursor.call("configure", descriptor, false)


func _place_authored_light(hit: Dictionary) -> void:
	if hit.is_empty() or not light_placement_active:
		return
	var placement_transform := _light_transform_for_hit(hit)
	var light_id := document.allocate_light_id()
	var descriptor := _light_descriptor_from_fields(
		light_id,
		placement_transform.origin,
		placement_transform.basis.get_euler()
	)
	var marker := LIGHT_MARKER_SCRIPT.new() as Node3D
	marker.name = "AuthoredLight%03d" % light_id
	marker.process_mode = Node.PROCESS_MODE_DISABLED
	if not bool(marker.call("configure", descriptor, true)):
		marker.free()
		return
	light_marker_root.add_child(marker)
	authored_lights_by_id[light_id] = marker
	light_placement_active = false
	if light_cursor != null:
		light_cursor.visible = false
	if light_place_button != null:
		light_place_button.button_pressed = false
	selected_light_id = light_id
	_mark_dirty()
	_refresh_light_inspector()
	_set_status("PLACED %s  //  LIGHT %03d" % [
		LIGHT_AUTHORING.type_label(descriptor.get("type", LIGHT_AUTHORING.TYPE_OMNI)),
		light_id,
	])


func _delete_selected_light() -> void:
	var marker := authored_lights_by_id.get(selected_light_id) as Node3D
	if marker == null:
		return
	var removed_id := selected_light_id
	authored_lights_by_id.erase(removed_id)
	selected_light_id = 0
	if marker.get_parent() != null:
		marker.get_parent().remove_child(marker)
	marker.free()
	_mark_dirty()
	_refresh_light_inspector()
	_set_status("DELETED LIGHT %03d" % removed_id)


func _pick_authored_light(viewport_position: Vector2) -> Node3D:
	var ray_origin := editor_camera.project_ray_origin(viewport_position)
	var ray_direction := editor_camera.project_ray_normal(viewport_position)
	var nearest_distance := INF
	var nearest: Node3D
	for marker: Node3D in authored_lights_by_id.values():
		var distance := float(marker.call("ray_distance", ray_origin, ray_direction))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = marker
	return nearest


func _light_transform_for_hit(hit: Dictionary) -> Transform3D:
	var position: Vector3 = hit.get("position", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if not normal.is_finite() or normal.length_squared() <= 0.000001:
		normal = Vector3.UP
	normal = normal.normalized()
	var type: StringName = LIGHT_AUTHORING.TYPE_OMNI
	if light_type_field != null and light_type_field.item_count > 0:
		type = light_type_field.get_item_metadata(light_type_field.selected)
	if type == LIGHT_AUTHORING.TYPE_DIRECTIONAL:
		return Transform3D(
			Basis.from_euler(_light_field_rotation()),
			position + normal * 0.08
		)
	var base := Basis.IDENTITY
	if type == LIGHT_AUTHORING.TYPE_SPOT:
		var backward := -normal
		var up := Vector3.UP - backward * Vector3.UP.dot(backward)
		if up.length_squared() <= 0.000001:
			up = editor_camera.global_basis.y
			up -= backward * up.dot(backward)
		if up.length_squared() <= 0.000001:
			up = Vector3.FORWARD
		up = up.normalized()
		var right := up.cross(backward).normalized()
		up = backward.cross(right).normalized()
		base = Basis(right, up, backward).orthonormalized()
	base = (base * Basis.from_euler(_light_field_rotation())).orthonormalized()
	return Transform3D(base, position + normal * 0.08)


func _build_acoustic_panel() -> void:
	acoustic_panel = _panel()
	acoustic_panel.visible = false
	acoustic_panel.offset_top = CONTENT_TOP + 8.0
	acoustic_panel.offset_bottom = CONTENT_TOP + 326.0
	acoustic_panel.offset_right = 0.0
	add_child(acoustic_panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT,
		Control.PRESET_MODE_MINSIZE,
		8
	)
	column.add_theme_constant_override("separation", 5)
	acoustic_panel.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	title_row.add_child(_label("SOUND MAP", 17, COLOR_TEXT))
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_spacer)
	_add_button(title_row, "×", _toggle_acoustic_authoring, "Close sound authoring")
	acoustic_status_label = _label("0 PROBES  //  0 PORTALS", 11, COLOR_MUTED)
	column.add_child(acoustic_status_label)
	var generation_row := HBoxContainer.new()
	generation_row.add_theme_constant_override("separation", 4)
	column.add_child(generation_row)
	_add_button(
		generation_row,
		"AUTO PROBES",
		_generate_automatic_acoustic_probes,
		"Regenerate only automatic ground probes; hand-authored probes and portals remain"
	)
	acoustic_place_probe_button = _add_button(
		generation_row,
		"PLACE PROBE",
		_arm_acoustic_probe_placement,
		"Place reusable acoustic samples by clicking surfaces in the 3D view"
	)
	acoustic_place_probe_button.toggle_mode = true
	var probe_settings_row := HBoxContainer.new()
	probe_settings_row.add_theme_constant_override("separation", 4)
	column.add_child(probe_settings_row)
	probe_settings_row.add_child(_label("SPACING", 10, COLOR_MUTED))
	acoustic_spacing_field = SpinBox.new()
	acoustic_spacing_field.min_value = 1.0
	acoustic_spacing_field.max_value = 25.0
	acoustic_spacing_field.step = 0.25
	acoustic_spacing_field.value = LevelAcousticAuthoring.DEFAULT_PROBE_SPACING
	acoustic_spacing_field.suffix = " m"
	acoustic_spacing_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	probe_settings_row.add_child(acoustic_spacing_field)
	probe_settings_row.add_child(_label("HEIGHT", 10, COLOR_MUTED))
	acoustic_height_field = SpinBox.new()
	acoustic_height_field.min_value = 0.1
	acoustic_height_field.max_value = 20.0
	acoustic_height_field.step = 0.1
	acoustic_height_field.value = LevelAcousticAuthoring.DEFAULT_PROBE_HEIGHT
	acoustic_height_field.suffix = " m"
	acoustic_height_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	probe_settings_row.add_child(acoustic_height_field)
	var portal_row := HBoxContainer.new()
	portal_row.add_theme_constant_override("separation", 4)
	column.add_child(portal_row)
	_add_button(
		portal_row,
		"LINK 2",
		_link_selected_acoustic_probes,
		"Create an explicit aperture edge between exactly two selected probes"
	)
	_add_button(
		portal_row,
		"PORTAL FROM ASSET",
		_create_portal_from_selected_asset,
		"Use the selected wall or doorway's thin axis to place both portal probes"
	)
	acoustic_profile_field = OptionButton.new()
	for profile_label: String in ["OPEN", "VENT", "THIN WALL"]:
		acoustic_profile_field.add_item(profile_label)
	acoustic_profile_field.item_selected.connect(_on_acoustic_profile_selected)
	acoustic_profile_field.tooltip_text = (
		"Open carries sound freely; vent and thin wall apply the shared runtime modifiers"
	)
	portal_row.add_child(acoustic_profile_field)
	acoustic_guided_button = _add_button(
		portal_row,
		"GUIDED",
		_on_acoustic_guided_toggled,
		"Carry tunnel/duct waveguide energy through this aperture"
	)
	acoustic_guided_button.toggle_mode = true
	var boundary_row := HBoxContainer.new()
	boundary_row.add_theme_constant_override("separation", 4)
	column.add_child(boundary_row)
	_add_button(
		boundary_row,
		"SOLID TO SOUND",
		_set_selected_acoustic_boundary.bind(true),
		"Selected geometry blocks and reflects sound"
	)
	_add_button(
		boundary_row,
		"PASS-THROUGH",
		_set_selected_acoustic_boundary.bind(false),
		"Selected geometry remains physical but is ignored as an acoustic wall"
	)
	_add_button(
		boundary_row,
		"DELETE MARKER",
		_delete_acoustic_selection,
		"Delete selected probes or portal; deleting a probe also removes connected portals"
	)
	acoustic_selection_label = _label("NO ACOUSTIC SELECTION", 11, COLOR_TEXT)
	acoustic_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(acoustic_selection_label)
	var position_row := HBoxContainer.new()
	position_row.add_theme_constant_override("separation", 4)
	column.add_child(position_row)
	position_row.add_child(_label("PROBE XYZ", 10, COLOR_MUTED))
	for axis_index: int in range(3):
		var field := SpinBox.new()
		field.min_value = -10000.0
		field.max_value = 10000.0
		field.step = 0.05
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.value_changed.connect(_on_acoustic_position_changed.bind(axis_index))
		position_row.add_child(field)
		acoustic_position_fields.append(field)
	var validation_row := HBoxContainer.new()
	column.add_child(validation_row)
	_add_button(
		validation_row,
		"VALIDATE BAKE",
		_validate_acoustic_bake,
		"Verify IDs, portal endpoints, and construction of the real runtime acoustic nodes"
	)
	var explanation := _label(
		"AUTO = COARSE FIELD  //  HAND PROBES = CORNERS & FLOORS  //  PORTALS = DOORS, VENTS, HOLES",
		9,
		COLOR_MUTED
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)
	_position_acoustic_panel()


func _build_speaker_authoring_panel() -> void:
	speaker_authoring_panel = _panel()
	speaker_authoring_panel.visible = false
	speaker_authoring_panel.offset_top = CONTENT_TOP + 8.0
	speaker_authoring_panel.offset_bottom = CONTENT_TOP + 236.0
	add_child(speaker_authoring_panel)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT,
		Control.PRESET_MODE_MINSIZE,
		8
	)
	column.add_theme_constant_override("separation", 7)
	speaker_authoring_panel.add_child(column)
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	title_row.add_child(_label("PA ARRAY AUTHORING", 17, COLOR_TEXT))
	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_spacer)
	_add_button(
		title_row,
		"×",
		_cancel_speaker_system_authoring,
		"Discard this unfinished speaker array"
	)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	column.add_child(name_row)
	name_row.add_child(_label("NAME", 10, COLOR_MUTED))
	speaker_name_field = LineEdit.new()
	speaker_name_field.placeholder_text = "PA system name"
	speaker_name_field.max_length = 64
	speaker_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(speaker_name_field)
	speaker_status_label = _label("0 SPEAKERS PLACED", 12, COLOR_ACCENT)
	column.add_child(speaker_status_label)
	var hint := _label(
		"CLICK A FLOOR, WALL, CEILING, OR PROP TO PLACE A CABINET.  "
		+ "ITS FRONT FACES AWAY FROM THE SURFACE.  RMB REMOVES THE LAST.",
		10,
		COLOR_MUTED
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	column.add_child(action_row)
	speaker_finish_button = _add_button(
		action_row,
		"FINALIZE ARRAY",
		_finalize_speaker_system,
		"Store every placed cabinet as one synchronized server-authoritative PA system"
	)
	speaker_finish_button.disabled = true
	_add_button(
		action_row,
		"CANCEL",
		_cancel_speaker_system_authoring,
		"Discard this unfinished array"
	)
	_position_speaker_authoring_panel()


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
	selection_context_menu = PopupMenu.new()
	selection_context_menu.name = "SelectionContextMenu"
	selection_context_menu.add_item(
		"MERGE AS REUSABLE ASSEMBLY...",
		CONTEXT_MERGE_ASSEMBLY
	)
	selection_context_menu.add_item("UNGROUP", CONTEXT_UNGROUP_ASSEMBLY)
	selection_context_menu.add_separator()
	mark_as_menu = PopupMenu.new()
	mark_as_menu.name = "MarkAsMenu"
	mark_as_menu.add_radio_check_item("STATIC GEOMETRY", MARK_AS_STATIC)
	mark_as_menu.add_radio_check_item("ITEM...", MARK_AS_ITEM)
	mark_as_menu.add_radio_check_item("VALUABLE...", MARK_AS_VALUABLE)
	mark_as_menu.id_pressed.connect(_on_mark_as_action)
	selection_context_menu.add_child(mark_as_menu)
	selection_context_menu.add_submenu_node_item("MARK AS", mark_as_menu)
	selection_context_menu.add_separator()
	selection_context_menu.add_item("FOCUS SELECTION", CONTEXT_FOCUS)
	selection_context_menu.add_item("DUPLICATE", CONTEXT_DUPLICATE)
	selection_context_menu.add_item("DELETE", CONTEXT_DELETE)
	selection_context_menu.id_pressed.connect(_on_selection_context_action)
	add_child(selection_context_menu)
	item_properties_dialog = ConfirmationDialog.new()
	item_properties_dialog.name = "ItemPropertiesDialog"
	item_properties_dialog.title = "Mark placed assets"
	item_properties_dialog.ok_button_text = "APPLY"
	item_properties_dialog.min_size = Vector2i(470, 250)
	item_properties_dialog.confirmed.connect(_confirm_mark_as_item)
	var item_content := VBoxContainer.new()
	item_content.name = "ItemProperties"
	item_content.position = Vector2(18.0, 62.0)
	item_content.custom_minimum_size = Vector2(430.0, 125.0)
	item_content.add_theme_constant_override("separation", 10)
	item_properties_dialog.add_child(item_content)
	var mass_row := HBoxContainer.new()
	mass_row.add_child(_label("MASS / KG", 12, COLOR_TEXT))
	item_mass_field = SpinBox.new()
	item_mass_field.min_value = LevelEditorDocument.MINIMUM_ITEM_MASS_KG
	item_mass_field.max_value = LevelEditorDocument.MAXIMUM_ITEM_MASS_KG
	item_mass_field.step = 0.01
	item_mass_field.allow_greater = false
	item_mass_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_mass_field.tooltip_text = "Authoritative rigid-body mass used by grabbing and impacts"
	item_mass_field.value_changed.connect(_refresh_item_total_value)
	mass_row.add_child(item_mass_field)
	item_content.add_child(mass_row)
	item_value_row = HBoxContainer.new()
	item_value_row.add_child(_label("VALUE / KG", 12, COLOR_ACCENT))
	item_value_per_mass_field = SpinBox.new()
	item_value_per_mass_field.min_value = 0.0
	item_value_per_mass_field.max_value = LevelEditorDocument.MAXIMUM_VALUE_PER_MASS
	item_value_per_mass_field.step = 0.25
	item_value_per_mass_field.allow_greater = false
	item_value_per_mass_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_value_per_mass_field.tooltip_text = (
		"Loot value is mass multiplied by this material/type rate"
	)
	item_value_per_mass_field.value_changed.connect(_refresh_item_total_value)
	item_value_row.add_child(item_value_per_mass_field)
	item_content.add_child(item_value_row)
	item_total_value_label = _label("TOTAL VALUE  0.00", 12, COLOR_ACCENT)
	item_content.add_child(item_total_value_label)
	add_child(item_properties_dialog)
	assembly_name_dialog = ConfirmationDialog.new()
	assembly_name_dialog.name = "AssemblyNameDialog"
	assembly_name_dialog.title = "Save reusable assembly"
	assembly_name_dialog.dialog_text = (
		"The selected assets remain ordinary runtime placements, but will move as one group.\n"
		+ "The reusable definition is stored in your assembly shelf."
	)
	assembly_name_dialog.ok_button_text = "MERGE & SAVE"
	assembly_name_dialog.confirmed.connect(_confirm_merge_selected)
	assembly_name_dialog.canceled.connect(_clear_pending_merge)
	assembly_name_field = LineEdit.new()
	assembly_name_field.name = "AssemblyName"
	assembly_name_field.placeholder_text = "Assembly name"
	assembly_name_field.custom_minimum_size = Vector2(420.0, 34.0)
	assembly_name_field.max_length = ASSEMBLY_STORE.MAXIMUM_NAME_LENGTH
	assembly_name_field.text_submitted.connect(
		func(_value: String) -> void:
			assembly_name_dialog.get_ok_button().emit_signal("pressed")
	)
	assembly_name_dialog.add_child(assembly_name_field)
	add_child(assembly_name_dialog)


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
	acoustic_marker_root = Node3D.new()
	acoustic_marker_root.name = "AcousticAuthoringMarkers"
	editor_world.add_child(acoustic_marker_root)
	speaker_marker_root = Node3D.new()
	speaker_marker_root.name = "SpeakerSystemAuthoringMarkers"
	editor_world.add_child(speaker_marker_root)
	light_marker_root = Node3D.new()
	light_marker_root.name = "AuthoredLights"
	editor_world.add_child(light_marker_root)
	acoustic_state = ACOUSTIC_STATE_SCRIPT.new() as LevelAcousticEditorState
	acoustic_state.name = "LevelAcousticEditorState"
	add_child(acoustic_state)
	acoustic_state.configure(acoustic_marker_root)
	acoustic_state.changed.connect(_on_acoustic_state_changed)
	acoustic_state.selection_changed.connect(_refresh_acoustic_panel)
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
	_build_transform_gizmo()
	_build_building_room_preview()
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


func _build_transform_gizmo() -> void:
	transform_gizmo = TRANSFORM_GIZMO.new()
	transform_gizmo.name = "SelectionTransformGizmo"
	editor_world.add_child(transform_gizmo)
	transform_gizmo.set_mode(TRANSFORM_GIZMO.MODE_HIDDEN)


func _build_building_room_preview() -> void:
	building_room_preview = MeshInstance3D.new()
	building_room_preview.name = "BuildingRoomPreview"
	building_room_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	building_room_preview.visible = false
	editor_world.add_child(building_room_preview)


func _toggle_acoustic_authoring() -> void:
	acoustic_authoring_enabled = not acoustic_authoring_enabled
	if acoustic_authoring_enabled and light_placement_active:
		_cancel_light_placement()
	if acoustic_authoring_enabled and speaker_authoring_active:
		_cancel_speaker_system_authoring()
	if sound_authoring_button != null:
		sound_authoring_button.button_pressed = acoustic_authoring_enabled
	if acoustic_panel != null:
		acoustic_panel.visible = acoustic_authoring_enabled
	if acoustic_state != null:
		acoustic_state.set_editor_visible(acoustic_authoring_enabled)
	if acoustic_authoring_enabled:
		_cancel_asset_placement()
		_set_status("SOUND MAP AUTHORING ACTIVE  //  MARKERS ARE EDITOR-ONLY VISUALS")
	else:
		acoustic_tool = ACOUSTIC_TOOL_SELECT
		if acoustic_place_probe_button != null:
			acoustic_place_probe_button.button_pressed = false
		_set_status("SOUND MAP AUTHORING CLOSED")
	_refresh_acoustic_panel()
	_refresh_transform_gizmo()


func _begin_speaker_system_authoring() -> void:
	if speaker_authoring_active:
		return
	if building_room_tool_active:
		_cancel_room_shell_tool()
	_cancel_asset_placement()
	_cancel_light_placement()
	if acoustic_authoring_enabled:
		acoustic_authoring_enabled = false
		acoustic_tool = ACOUSTIC_TOOL_SELECT
		if sound_authoring_button != null:
			sound_authoring_button.button_pressed = false
		if acoustic_place_probe_button != null:
			acoustic_place_probe_button.button_pressed = false
		if acoustic_panel != null:
			acoustic_panel.visible = false
		if acoustic_state != null:
			acoustic_state.set_editor_visible(false)
	_clear_speaker_draft()
	speaker_authoring_active = true
	if speaker_authoring_button != null:
		speaker_authoring_button.button_pressed = true
	if speaker_authoring_panel != null:
		speaker_authoring_panel.visible = true
	if speaker_name_field != null:
		speaker_name_field.text = "PA SYSTEM %03d" % document.next_sound_system_id
	_ensure_speaker_cursor()
	_refresh_speaker_authoring_status()
	_refresh_transform_gizmo()
	_set_status("PA ARRAY ACTIVE  //  PLACE ANY NUMBER OF SPEAKERS, THEN FINALIZE")


func _cancel_speaker_system_authoring() -> void:
	var discarded_count := speaker_draft_markers.size()
	_clear_speaker_draft()
	speaker_authoring_active = false
	if speaker_cursor != null:
		speaker_cursor.visible = false
	if speaker_authoring_button != null:
		speaker_authoring_button.button_pressed = false
	if speaker_authoring_panel != null:
		speaker_authoring_panel.visible = false
	_refresh_transform_gizmo()
	_refresh_speaker_authoring_status()
	if discarded_count > 0:
		_set_status("DISCARDED UNFINISHED PA ARRAY")


func _ensure_speaker_cursor() -> void:
	if speaker_cursor != null and is_instance_valid(speaker_cursor):
		return
	speaker_cursor = SPEAKER_MARKER_SCRIPT.new() as LevelSpeakerAuthoringMarker
	speaker_cursor.name = "SpeakerPlacementCursor"
	speaker_cursor.process_mode = Node.PROCESS_MODE_DISABLED
	speaker_cursor.configure_editor_marker(false)
	speaker_cursor.visible = false
	speaker_marker_root.add_child(speaker_cursor)


func _clear_speaker_draft() -> void:
	for marker: LevelSpeakerAuthoringMarker in speaker_draft_markers:
		if marker != null and is_instance_valid(marker):
			if marker.get_parent() != null:
				marker.get_parent().remove_child(marker)
			marker.free()
	speaker_draft_markers.clear()


func _remove_last_draft_speaker() -> void:
	if speaker_draft_markers.is_empty():
		_cancel_speaker_system_authoring()
		return
	var marker: LevelSpeakerAuthoringMarker = speaker_draft_markers.pop_back()
	if marker != null and is_instance_valid(marker):
		if marker.get_parent() != null:
			marker.get_parent().remove_child(marker)
		marker.free()
	_refresh_speaker_authoring_status()
	_set_status("REMOVED LAST DRAFT SPEAKER")


func _place_draft_speaker(hit: Dictionary) -> void:
	if hit.is_empty() or not speaker_authoring_active:
		return
	var marker := SPEAKER_MARKER_SCRIPT.new() as LevelSpeakerAuthoringMarker
	marker.name = "DraftSpeaker%03d" % (speaker_draft_markers.size() + 1)
	marker.process_mode = Node.PROCESS_MODE_DISABLED
	marker.transform = _speaker_transform_for_hit(hit)
	marker.configure_editor_marker(false)
	speaker_marker_root.add_child(marker)
	speaker_draft_markers.append(marker)
	_refresh_speaker_authoring_status()
	_set_status("PLACED PA SPEAKER %03d  //  RMB REMOVES LAST" % speaker_draft_markers.size())


func _finalize_speaker_system() -> void:
	if speaker_draft_markers.is_empty():
		_set_status("PLACE AT LEAST ONE SPEAKER BEFORE FINALIZING", true)
		return
	var world_speakers: Array[Dictionary] = []
	for marker: LevelSpeakerAuthoringMarker in speaker_draft_markers:
		if marker != null and is_instance_valid(marker):
			world_speakers.append(marker.descriptor())
	var system_id := document.allocate_sound_system_id()
	var system := LevelSpeakerSystemAuthoring.create_system(
		system_id,
		speaker_name_field.text if speaker_name_field != null else "",
		world_speakers
	)
	if system.is_empty():
		_set_status("COULD NOT FINALIZE PA ARRAY", true)
		return
	for marker: LevelSpeakerAuthoringMarker in speaker_draft_markers:
		marker.system_id = system_id
		marker.set_finalized(true)
	sound_systems_by_id[system_id] = system
	var speaker_count := speaker_draft_markers.size()
	speaker_draft_markers.clear()
	speaker_authoring_active = false
	if speaker_cursor != null:
		speaker_cursor.visible = false
	if speaker_authoring_button != null:
		speaker_authoring_button.button_pressed = false
	if speaker_authoring_panel != null:
		speaker_authoring_panel.visible = false
	_refresh_transform_gizmo()
	_mark_dirty()
	_set_status("FINALIZED %s  //  %d SPEAKERS" % [
		str(system.get("display_name", "PA SYSTEM")).to_upper(),
		speaker_count,
	])


func _refresh_speaker_authoring_status() -> void:
	var count := speaker_draft_markers.size()
	if speaker_status_label != null:
		speaker_status_label.text = "%d SPEAKER%s PLACED" % [
			count,
			"" if count == 1 else "S",
		]
	if speaker_finish_button != null:
		speaker_finish_button.disabled = count <= 0


func _update_speaker_cursor(viewport_position: Vector2) -> void:
	_ensure_speaker_cursor()
	var hit := _screen_to_placement_hit(viewport_position)
	speaker_cursor.visible = not hit.is_empty()
	if not hit.is_empty():
		speaker_cursor.transform = _speaker_transform_for_hit(hit)


func _speaker_transform_for_hit(hit: Dictionary) -> Transform3D:
	var position: Vector3 = hit.get("position", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if not normal.is_finite() or normal.length_squared() < 0.0001:
		normal = Vector3.UP
	normal = normal.normalized()
	var front := normal
	var surface_is_floor := normal.dot(Vector3.UP) > 0.55
	if surface_is_floor:
		front = editor_camera.global_position - position
		front.y = 0.0
		if front.length_squared() < 0.0001:
			front = -editor_camera.global_basis.z
			front.y = 0.0
		front = front.normalized()
	var up := Vector3.UP - front * Vector3.UP.dot(front)
	if up.length_squared() < 0.0001:
		up = -editor_camera.global_basis.z
		up -= front * up.dot(front)
	if up.length_squared() < 0.0001:
		up = Vector3.FORWARD
	up = up.normalized()
	var right := up.cross(front).normalized()
	up = front.cross(right).normalized()
	var offset := (
		LevelSpeakerSystemAuthoring.DEFAULT_CABINET_SIZE.y * 0.5
		if surface_is_floor
		else LevelSpeakerSystemAuthoring.DEFAULT_CABINET_SIZE.z * 0.5
	)
	return Transform3D(Basis(right, up, front), position + normal * offset)


func _arm_acoustic_probe_placement() -> void:
	acoustic_tool = (
		ACOUSTIC_TOOL_SELECT
		if acoustic_tool == ACOUSTIC_TOOL_PLACE_PROBE
		else ACOUSTIC_TOOL_PLACE_PROBE
	)
	acoustic_place_probe_button.button_pressed = (
		acoustic_tool == ACOUSTIC_TOOL_PLACE_PROBE
	)
	_set_status(
		"CLICK A SURFACE TO PLACE PROBES  //  RMB CANCELS"
		if acoustic_tool == ACOUSTIC_TOOL_PLACE_PROBE
		else "ACOUSTIC PROBE PLACEMENT CANCELLED"
	)


func _place_acoustic_probe_from_hit(hit: Dictionary) -> void:
	if hit.is_empty() or acoustic_state == null:
		return
	var surface_position: Vector3 = hit.get("position", Vector3.ZERO)
	var surface_normal: Vector3 = hit.get("normal", Vector3.UP).normalized()
	var height := float(acoustic_height_field.value)
	var position := (
		surface_position + surface_normal * height
		if absf(surface_normal.dot(Vector3.UP)) >= 0.55
		else surface_position + surface_normal * 0.45
	)
	var previous := acoustic_state.capture_state()
	var probe_id := acoustic_state.add_probe(position, true)
	if probe_id <= 0:
		_set_status("COULD NOT PLACE ACOUSTIC PROBE", true)
		return
	var next := acoustic_state.capture_state()
	_commit_acoustic_state_action("Place acoustic probe", previous, next)
	_set_status("PLACED ACOUSTIC PROBE %03d" % probe_id)


func _generate_automatic_acoustic_probes() -> void:
	if acoustic_state == null or placements_by_id.is_empty():
		_set_status("PLACE LEVEL GEOMETRY BEFORE GENERATING A SOUND FIELD", true)
		return
	var world_bounds: Array[AABB] = []
	for placement: LevelAssetPlacement in placements_by_id.values():
		if placement.acoustic_boundary:
			world_bounds.append(placement.global_transform * placement.local_bounds)
	if world_bounds.is_empty():
		_set_status("NO SOUND-BLOCKING LEVEL GEOMETRY TO SAMPLE", true)
		return
	var previous := acoustic_state.capture_state()
	var added := acoustic_state.regenerate_automatic_probes(
		world_bounds,
		float(acoustic_spacing_field.value),
		float(acoustic_height_field.value)
	)
	var next := acoustic_state.capture_state()
	_commit_acoustic_state_action("Regenerate automatic acoustic probes", previous, next)
	_set_status("GENERATED %d REUSABLE ACOUSTIC PROBES" % added, added <= 0)


func _link_selected_acoustic_probes() -> void:
	if acoustic_state == null or acoustic_state.selected_probe_ids.size() != 2:
		_set_status("SELECT EXACTLY TWO CYAN PROBES TO CREATE A PORTAL", true)
		return
	var previous := acoustic_state.capture_state()
	var portal_id := acoustic_state.link_selected_probes(
		_selected_acoustic_profile(),
		acoustic_guided_button.button_pressed
	)
	if portal_id <= 0:
		_set_status("THOSE PROBES ARE ALREADY LINKED", true)
		return
	var next := acoustic_state.capture_state()
	_commit_acoustic_state_action("Link acoustic portal", previous, next)
	_set_status("CREATED ACOUSTIC PORTAL %03d" % portal_id)


func _create_portal_from_selected_asset() -> void:
	if acoustic_state == null or selected_placement == null:
		_set_status("SELECT ONE WALL, DOORWAY, VENT, OR HOLE ASSET FIRST", true)
		return
	if selected_placements_by_id.size() != 1:
		_set_status("PORTAL FROM ASSET REQUIRES ONE SELECTED ASSET", true)
		return
	var previous := acoustic_state.capture_state()
	var portal_id := acoustic_state.portal_from_placement(
		selected_placement,
		_selected_acoustic_profile(),
		acoustic_guided_button.button_pressed
	)
	if portal_id <= 0:
		_set_status("COULD NOT DERIVE A PORTAL FROM THIS ASSET", true)
		return
	var next := acoustic_state.capture_state()
	_commit_acoustic_state_action("Create portal from asset", previous, next)
	_set_status(
		"MARKED %s WITH PORTAL %03d"
		% [selected_placement.name.to_upper(), portal_id]
	)


func _selected_acoustic_profile() -> String:
	if acoustic_profile_field == null:
		return "open"
	return ["open", "vent", "thin_wall"][acoustic_profile_field.selected]


func _on_acoustic_profile_selected(_index: int) -> void:
	if acoustic_inspector_refreshing or acoustic_state == null:
		return
	var portal := acoustic_state.portals_by_id.get(
		acoustic_state.selected_portal_id
	) as LevelAcousticPortalMarker
	if portal == null:
		return
	var previous := acoustic_state.capture_state()
	portal.descriptor["profile"] = _selected_acoustic_profile()
	var next := acoustic_state.capture_state()
	_commit_acoustic_state_action("Change acoustic portal profile", previous, next)
	_refresh_acoustic_panel()


func _on_acoustic_guided_toggled() -> void:
	if acoustic_inspector_refreshing or acoustic_state == null:
		return
	var portal := acoustic_state.portals_by_id.get(
		acoustic_state.selected_portal_id
	) as LevelAcousticPortalMarker
	if portal == null:
		return
	var previous := acoustic_state.capture_state()
	portal.descriptor["carries_guided_energy"] = (
		acoustic_guided_button.button_pressed
	)
	var next := acoustic_state.capture_state()
	_commit_acoustic_state_action("Toggle guided acoustic portal", previous, next)
	_refresh_acoustic_panel()


func _set_selected_acoustic_boundary(value: bool) -> void:
	if selected_placements_by_id.is_empty():
		_set_status("SELECT LEVEL GEOMETRY TO CHANGE ITS SOUND BOUNDARY", true)
		return
	var previous := _capture_selected_snapshots()
	for placement: LevelAssetPlacement in _selected_placements():
		placement.acoustic_boundary = value
	var next := _capture_selected_snapshots()
	undo_redo.create_action("Set acoustic boundary")
	undo_redo.add_do_method(_apply_placement_snapshots.bind(next))
	undo_redo.add_undo_method(_apply_placement_snapshots.bind(previous))
	undo_redo.commit_action(false)
	_mark_dirty()
	_set_status(
		"%d ASSET%s %s SOUND"
		% [
			next.size(),
			"" if next.size() == 1 else "S",
			"BLOCK" if value else "PASS",
		]
	)


func _delete_acoustic_selection() -> void:
	if acoustic_state == null:
		return
	var previous := acoustic_state.capture_state()
	if not acoustic_state.delete_selection():
		_set_status("SELECT AN ACOUSTIC PROBE OR PORTAL TO DELETE", true)
		return
	var next := acoustic_state.capture_state()
	_commit_acoustic_state_action("Delete acoustic marker", previous, next)
	_set_status("DELETED ACOUSTIC MARKER")


func _on_acoustic_position_changed(_value: float, axis_index: int) -> void:
	if acoustic_inspector_refreshing or acoustic_state == null:
		return
	if acoustic_state.selected_probe_ids.size() != 1:
		return
	var previous := acoustic_state.capture_state()
	var position := acoustic_state.single_selected_probe_position()
	position[axis_index] = float(acoustic_position_fields[axis_index].value)
	if not acoustic_state.move_single_selected_probe(position):
		return
	var next := acoustic_state.capture_state()
	undo_redo.create_action("Move acoustic probe", UndoRedo.MERGE_ENDS)
	undo_redo.add_do_method(_restore_acoustic_state.bind(next))
	undo_redo.add_undo_method(_restore_acoustic_state.bind(previous))
	undo_redo.commit_action(false)
	_mark_dirty()
	_refresh_acoustic_panel()


func _validate_acoustic_bake() -> void:
	if acoustic_state == null:
		return
	var state := acoustic_state.capture_state()
	var temporary_root := Node3D.new()
	var report: Dictionary = ACOUSTIC_RUNTIME_BUILDER.build_into(
		temporary_root,
		state["probes"] as Array[Dictionary],
		state["portals"] as Array[Dictionary],
		level_name_field.text.strip_edges()
	)
	temporary_root.free()
	var valid := bool(report.get("valid", false)) and int(report.get("probe_count", 0)) > 0
	_set_status(
		"SOUND BAKE READY  //  %d PROBES  //  %d PORTALS"
		% [int(report.get("probe_count", 0)), int(report.get("portal_count", 0))]
		if valid
		else "SOUND BAKE INVALID  //  ADD PROBES OR REPAIR PORTAL LINKS",
		not valid
	)


func _commit_acoustic_state_action(
	action_name: String,
	previous: Dictionary,
	next: Dictionary
) -> void:
	undo_redo.create_action(action_name)
	undo_redo.add_do_method(_restore_acoustic_state.bind(next))
	undo_redo.add_undo_method(_restore_acoustic_state.bind(previous))
	undo_redo.commit_action(false)
	_mark_dirty()
	_refresh_acoustic_panel()


func _restore_acoustic_state(state: Dictionary) -> void:
	if acoustic_state == null:
		return
	rebuilding_acoustics = true
	acoustic_state.restore_state(state)
	rebuilding_acoustics = false
	_refresh_acoustic_panel()


func _on_acoustic_state_changed() -> void:
	if not rebuilding_acoustics:
		_refresh_acoustic_panel()


func _refresh_acoustic_panel() -> void:
	if acoustic_state == null or acoustic_status_label == null:
		return
	acoustic_inspector_refreshing = true
	acoustic_status_label.text = "%d PROBES  //  %d PORTALS" % [
		acoustic_state.probes_by_id.size(),
		acoustic_state.portals_by_id.size(),
	]
	var marker_selection := acoustic_state.selection_label()
	if marker_selection == "NO ACOUSTIC SELECTION" and selected_placement != null:
		marker_selection = "ASSET %03d  //  %s" % [
			selected_placement.placement_id,
			"SOLID TO SOUND" if selected_placement.acoustic_boundary else "SOUND PASS-THROUGH",
		]
	acoustic_selection_label.text = marker_selection
	var has_single_probe := acoustic_state.selected_probe_ids.size() == 1
	var position := acoustic_state.single_selected_probe_position()
	for axis_index: int in range(acoustic_position_fields.size()):
		acoustic_position_fields[axis_index].editable = has_single_probe
		acoustic_position_fields[axis_index].value = position[axis_index]
	var selected_portal := acoustic_state.portals_by_id.get(
		acoustic_state.selected_portal_id
	) as LevelAcousticPortalMarker
	if selected_portal != null:
		var profiles := ["open", "vent", "thin_wall"]
		acoustic_profile_field.select(maxi(
			profiles.find(str(selected_portal.descriptor.get("profile", "open"))),
			0
		))
		acoustic_guided_button.button_pressed = bool(
			selected_portal.descriptor.get("carries_guided_energy", false)
		)
	acoustic_inspector_refreshing = false


func _load_asset_catalog() -> void:
	# Opening the editor is an explicit authoring action, so a single cheap GLB
	# header scan is preferable to hiding assets added during this Godot session.
	catalog = LevelAssetCatalog.entries(true)
	catalog_entries_by_path.clear()
	var category_counts: Dictionary[String, int] = {}
	for entry: Dictionary in catalog:
		catalog_entries_by_path[str(entry.get("asset_path", ""))] = entry
		var entry_category := str(entry.get("category", "Other"))
		category_counts[entry_category] = category_counts.get(entry_category, 0) + 1
	category_filter.clear()
	category_filter.add_item("All assets  [%d]" % catalog.size())
	category_filter.set_item_metadata(0, "All assets")
	favorite_filter_option_index = category_filter.item_count
	category_filter.add_item(_favorite_filter_label())
	category_filter.set_item_metadata(
		favorite_filter_option_index,
		FAVORITES_FILTER
	)
	for category: String in LevelAssetCatalog.category_names(catalog):
		var option_index := category_filter.item_count
		category_filter.add_item("%s  [%d]" % [
			category,
			category_counts.get(category, 0),
		])
		category_filter.set_item_metadata(option_index, category)
	_populate_building_filters()
	_prune_favorite_paths()
	asset_list.set_favorite_paths(favorite_asset_paths)
	_update_favorite_filter_label()
	_refresh_catalog_list()
	_refresh_used_assets_bar()
	_set_status("INDEXED %d UNIQUE GLB ASSETS" % catalog.size())


func _reload_asset_catalog() -> void:
	_set_status("RESCANNING ASSET FOLDERS...")
	_load_asset_catalog()


func _refresh_catalog_list() -> void:
	var category := (
		str(category_filter.get_item_metadata(category_filter.selected))
		if category_filter.item_count > 0
		else "All assets"
	)
	if building_mode_enabled:
		filtered_catalog = _filtered_building_catalog()
	elif category == FAVORITES_FILTER:
		filtered_catalog = []
		for entry: Dictionary in LevelAssetCatalog.filter_entries(
			catalog,
			search_field.text,
			"All assets"
		):
			if favorite_asset_paths.has(str(entry.get("asset_path", ""))):
				filtered_catalog.append(entry)
	else:
		filtered_catalog = LevelAssetCatalog.filter_entries(
			catalog,
			search_field.text,
			category
		)
	asset_list.clear()
	catalog_item_indices_by_path.clear()
	var restored_index := -1
	var previous_folder_path := ""
	for entry: Dictionary in filtered_catalog:
		var folder_path := str(entry.get(
			"browser_group_path",
			entry.get("folder_path", "")
		))
		if folder_path != previous_folder_path:
			_add_catalog_folder_row(
				str(entry.get(
					"browser_group_name",
					entry.get("folder_name", "Assets")
				))
			)
			previous_folder_path = folder_path
		var asset_path := str(entry.get("asset_path", ""))
		var index := asset_list.add_item(
			str(entry.get("display_name", "Asset")),
			thumbnail_renderer.cached(asset_path)
		)
		asset_list.set_item_metadata(index, asset_path)
		catalog_item_indices_by_path[asset_path] = index
		asset_list.set_item_tooltip(index, "%s\n%s\n%s" % [
			str(entry.get(
				"browser_group_name",
				entry.get("folder_name", "Assets")
			)),
			str(entry.get("pack", "Unknown pack")),
			asset_path + "\nClick the star to toggle favorite",
		])
		if asset_path == selected_catalog_path:
			asset_list.select(index)
			restored_index = index
	if restored_index >= 0:
		asset_list.ensure_current_is_visible()
	asset_list.invalidate_visible_range()
	result_count_label.text = "%d / %d ASSETS" % [filtered_catalog.size(), catalog.size()]
	_refresh_building_controls()


func _add_catalog_folder_row(folder_name: String) -> void:
	# ItemList keeps thousands of assets cheap, but it has no spanning cells.
	# Pad to a fresh row, then color every cell in that row as one folder band.
	while asset_list.item_count % catalog_grid_columns != 0:
		_add_catalog_grid_spacer()
	for column_index: int in range(catalog_grid_columns):
		var index := asset_list.add_item(
			"▾  %s" % folder_name.to_upper()
			if column_index == 0
			else ""
		)
		asset_list.set_item_selectable(index, false)
		asset_list.set_item_disabled(index, true)
		asset_list.set_item_custom_fg_color(index, COLOR_ACCENT)
		asset_list.set_item_custom_bg_color(index, COLOR_PANEL_INNER)
		asset_list.set_item_metadata(index, "")


func _add_catalog_grid_spacer() -> void:
	var index := asset_list.add_item("")
	asset_list.set_item_selectable(index, false)
	asset_list.set_item_disabled(index, true)
	asset_list.set_item_metadata(index, "")


func _on_catalog_filter_changed(_value: String) -> void:
	_refresh_catalog_list()


func _on_category_selected(_index: int) -> void:
	_refresh_catalog_list()


func _populate_building_filters() -> void:
	if building_kit_filter == null or building_role_filter == null:
		return
	var previous_kit := _selected_building_kit()
	var previous_role := _selected_building_role()
	building_kit_filter.clear()
	building_kit_filter.add_item("ALL KITS")
	building_kit_filter.set_item_metadata(0, BUILDING_FILTER_ALL)
	for kit_id: String in BUILDING_KITS.kit_ids(catalog):
		var index := building_kit_filter.item_count
		building_kit_filter.add_item("KIT %s" % kit_id)
		building_kit_filter.set_item_metadata(index, kit_id)
		if kit_id == previous_kit or (previous_kit.is_empty() and kit_id == "HR"):
			building_kit_filter.select(index)
	building_role_filter.clear()
	building_role_filter.add_item("ALL PIECES")
	building_role_filter.set_item_metadata(0, BUILDING_FILTER_ALL)
	for role: StringName in BUILDING_KITS.ROLE_ORDER:
		var index := building_role_filter.item_count
		building_role_filter.add_item(BUILDING_KITS.role_label(role))
		building_role_filter.set_item_metadata(index, role)
		if str(role) == previous_role:
			building_role_filter.select(index)


func _toggle_building_mode() -> void:
	building_mode_enabled = not building_mode_enabled
	if building_mode_button != null:
		building_mode_button.button_pressed = building_mode_enabled
	if building_controls != null:
		building_controls.visible = building_mode_enabled
	if category_filter != null:
		category_filter.disabled = building_mode_enabled
		category_filter.tooltip_text = (
			"Building mode uses the kit and structural-role filters below"
			if building_mode_enabled
			else "Filter the complete asset catalog by functional category"
		)
	if not building_mode_enabled:
		_cancel_room_shell_tool()
	_refresh_catalog_list()
	_set_status(
		"BUILDING KITS ACTIVE  //  PICK A FAMILY AND STRUCTURAL ROLE"
		if building_mode_enabled
		else "BUILDING KIT FILTER CLOSED"
	)


func _on_building_filter_changed(_index: int) -> void:
	if building_mode_enabled:
		_refresh_catalog_list()


func _selected_building_kit() -> String:
	if building_kit_filter == null or building_kit_filter.item_count <= 0:
		return ""
	return str(building_kit_filter.get_item_metadata(
		building_kit_filter.selected
	))


func _selected_building_role() -> String:
	if building_role_filter == null or building_role_filter.item_count <= 0:
		return ""
	return str(building_role_filter.get_item_metadata(
		building_role_filter.selected
	))


func _filtered_building_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kit_filter := _selected_building_kit()
	var role_filter := _selected_building_role()
	var query := search_field.text.strip_edges().to_lower()
	for entry: Dictionary in catalog:
		var entry_kit := str(entry.get("building_kit", ""))
		var entry_role := str(entry.get("building_role", ""))
		if entry_kit.is_empty():
			continue
		if kit_filter != BUILDING_FILTER_ALL and entry_kit != kit_filter:
			continue
		if role_filter != BUILDING_FILTER_ALL and entry_role != role_filter:
			continue
		if not query.is_empty() and not str(entry.get("search_text", "")).contains(query):
			continue
		result.append(entry)
	return result


func _toggle_building_socket_snap() -> void:
	_refresh_armed_placement_cursor()
	_set_status(
		"BUILDING SOCKET SNAP %s" % (
			"ENABLED" if building_socket_snap_button.button_pressed else "DISABLED"
		)
	)


func _room_wall_path(requested_kit: String) -> String:
	var kit_id := requested_kit
	if kit_id.is_empty() or kit_id == BUILDING_FILTER_ALL:
		var selected_entry: Dictionary = catalog_entries_by_path.get(
			selected_catalog_path,
			{}
		)
		kit_id = str(selected_entry.get("building_kit", "HR"))
	if building_room_wall_paths.has(kit_id):
		var remembered := str(building_room_wall_paths[kit_id])
		if LevelAssetCatalog.is_valid_asset_path(remembered):
			return remembered
	var entry := BUILDING_KITS.default_entry(
		catalog,
		kit_id,
		BUILDING_KITS.ROLE_WALL
	)
	return str(entry.get("asset_path", ""))


func _room_role_path(kit_id: String, role: StringName) -> String:
	var entry := BUILDING_KITS.default_entry(catalog, kit_id, role)
	return str(entry.get("asset_path", ""))


func _effective_room_kit() -> String:
	var kit_id := _selected_building_kit()
	if kit_id == BUILDING_FILTER_ALL or kit_id.is_empty():
		var selected_entry: Dictionary = catalog_entries_by_path.get(
			selected_catalog_path,
			{}
		)
		kit_id = str(selected_entry.get("building_kit", "HR"))
	return kit_id


func _toggle_room_shell_tool() -> void:
	if building_room_tool_active:
		_cancel_room_shell_tool()
		return
	var kit_id := _effective_room_kit()
	var wall_path := _room_wall_path(kit_id)
	var floor_path := _room_role_path(kit_id, BUILDING_KITS.ROLE_FLOOR)
	if wall_path.is_empty() or floor_path.is_empty():
		building_room_button.button_pressed = false
		_set_status("THIS KIT HAS NO USABLE WALL + FLOOR PAIR", true)
		return
	_cancel_asset_placement()
	building_room_tool_active = true
	building_room_dragging = false
	building_room_corner_a = Vector3.INF
	building_room_corner_b = Vector3.INF
	building_room_button.button_pressed = true
	_refresh_transform_gizmo()
	_set_status(
		"ROOM SHELL  //  DRAG ON A HORIZONTAL SURFACE  //  R ROTATES KIT AXES  //  RMB CANCELS"
	)


func _cancel_room_shell_tool() -> void:
	building_room_tool_active = false
	building_room_dragging = false
	building_room_corner_a = Vector3.INF
	building_room_corner_b = Vector3.INF
	if building_room_button != null:
		building_room_button.button_pressed = false
	if building_room_preview != null:
		building_room_preview.visible = false
	_refresh_transform_gizmo()
	_set_status("ROOM SHELL CANCELLED")


func _room_surface_position(viewport_position: Vector2) -> Vector3:
	var hit := _screen_to_placement_hit(viewport_position)
	if hit.is_empty():
		return Vector3.INF
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if normal.length_squared() <= 0.000001 or normal.normalized().dot(Vector3.UP) < 0.72:
		return Vector3.INF
	var position: Vector3 = hit.get("position", Vector3.INF)
	return _snap_horizontal_position(position) if position.is_finite() else Vector3.INF


func _begin_room_shell_drag(viewport_position: Vector2) -> void:
	var position := _room_surface_position(viewport_position)
	if not position.is_finite():
		_set_status("ROOM SHELL NEEDS A HORIZONTAL FLOOR OR GROUND SURFACE", true)
		return
	building_room_dragging = true
	building_room_corner_a = position
	building_room_corner_b = position
	_update_room_shell_preview(position)


func _update_room_shell_drag(viewport_position: Vector2) -> void:
	if not building_room_dragging:
		return
	var position := _room_surface_position(viewport_position)
	if not position.is_finite():
		return
	# The first surface owns the storey elevation; moving over props during the
	# drag must not make one corner of the generated room jump upward.
	position.y = building_room_corner_a.y
	building_room_corner_b = position
	_update_room_shell_preview(position)


func _finish_room_shell_drag(viewport_position: Vector2) -> void:
	if not building_room_dragging:
		return
	_update_room_shell_drag(viewport_position)
	building_room_dragging = false
	if building_room_preview != null:
		building_room_preview.visible = false
	var kit_id := _effective_room_kit()
	var wall_path := _room_wall_path(kit_id)
	var floor_path := _room_role_path(kit_id, BUILDING_KITS.ROLE_FLOOR)
	var roof_path := _room_role_path(kit_id, BUILDING_KITS.ROLE_ROOF)
	var group_id := document.allocate_building_group_id()
	var templates := BUILDING_SHELL_GENERATOR.generate(
		building_room_corner_a,
		building_room_corner_b,
		placement_rotation.y,
		wall_path,
		LevelAssetPlacement.asset_bounds(wall_path),
		floor_path,
		LevelAssetPlacement.asset_bounds(floor_path),
		roof_path,
		LevelAssetPlacement.asset_bounds(roof_path),
		building_roof_button.button_pressed,
		group_id,
		0
	)
	if templates.is_empty():
		_set_status("ROOM DRAG WAS TOO SMALL FOR THIS KIT", true)
		return
	var snapshots: Array[Dictionary] = []
	var placement_ids: Array[int] = []
	for template: Dictionary in templates:
		var snapshot := template.duplicate(false)
		var placement_id := document.allocate_placement_id()
		snapshot["id"] = placement_id
		placement_ids.append(placement_id)
		snapshots.append(snapshot)
	undo_redo.create_action("Generate building room shell")
	undo_redo.add_do_method(_restore_placements.bind(snapshots))
	undo_redo.add_undo_method(_remove_placements_by_id.bind(placement_ids))
	undo_redo.commit_action()
	_select_placement_ids(placement_ids)
	_mark_dirty()
	_set_status("GENERATED KIT %s ROOM  //  %d MODULAR PARTS" % [
		kit_id,
		snapshots.size(),
	])


func _update_room_shell_preview(current_corner: Vector3) -> void:
	if building_room_preview == null or not building_room_corner_a.is_finite():
		return
	var room_basis := Basis(Vector3.UP, placement_rotation.y)
	var local_delta := room_basis.inverse() * (current_corner - building_room_corner_a)
	var wall_path := _room_wall_path(_effective_room_kit())
	var wall_bounds := LevelAssetPlacement.asset_bounds(wall_path)
	var span := maxf(BUILDING_SHELL_GENERATOR.horizontal_span(wall_bounds), 0.1)
	var width := maxf(float(maxi(roundi(absf(local_delta.x) / span), 1)) * span, span)
	var depth := maxf(float(maxi(roundi(absf(local_delta.z) / span), 1)) * span, span)
	var sign_x := -1.0 if local_delta.x < 0.0 else 1.0
	var sign_z := -1.0 if local_delta.z < 0.0 else 1.0
	var right := room_basis * Vector3.RIGHT * sign_x
	var back := room_basis * Vector3.BACK * sign_z
	var a := building_room_corner_a + Vector3.UP * 0.025
	var b := a + right * width
	var c := b + back * depth
	var d := a + back * depth
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR_ACCENT
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge: Array in [[a, b], [b, c], [c, d], [d, a]]:
		mesh.surface_set_color(Color(COLOR_ACCENT, 0.92))
		mesh.surface_add_vertex(edge[0])
		mesh.surface_set_color(Color(COLOR_ACCENT, 0.92))
		mesh.surface_add_vertex(edge[1])
	mesh.surface_end()
	building_room_preview.mesh = mesh
	building_room_preview.visible = true
	if building_status_label != null:
		building_status_label.text = "ROOM %.2f × %.2f M  //  MODULE %.2f M" % [
			width,
			depth,
			span,
		]


func _replace_selected_building_piece() -> void:
	if selected_placement == null or selected_placements_by_id.size() != 1:
		_set_status("SELECT ONE MODULAR BUILDING PIECE TO REPLACE", true)
		return
	var option_index := building_compatible_options.selected
	if option_index < 0:
		return
	var replacement_path := str(
		building_compatible_options.get_item_metadata(option_index)
	)
	if (
		replacement_path.is_empty()
		or replacement_path == selected_placement.asset_path
		or not LevelAssetCatalog.is_valid_asset_path(replacement_path)
	):
		return
	var old_snapshot := selected_placement.snapshot()
	var old_bounds := selected_placement.local_bounds
	var new_bounds := LevelAssetPlacement.asset_bounds(replacement_path)
	var old_axis := BUILDING_SHELL_GENERATOR.horizontal_span_axis(old_bounds)
	var old_direction := selected_placement.basis * old_axis
	old_direction.y = 0.0
	if old_direction.length_squared() <= 0.000001:
		old_direction = Vector3.RIGHT
	var old_base_center := selected_placement.transform * Vector3(
		old_bounds.get_center().x,
		old_bounds.position.y,
		old_bounds.get_center().z
	)
	var old_world_span := (
		selected_placement.basis * old_axis
	).length() * BUILDING_SHELL_GENERATOR.horizontal_span(old_bounds)
	var replacement_scale := Vector3.ONE
	var new_axis := BUILDING_SHELL_GENERATOR.horizontal_span_axis(new_bounds)
	if new_axis == Vector3.RIGHT:
		replacement_scale.x = old_world_span / maxf(new_bounds.size.x, 0.001)
	else:
		replacement_scale.z = old_world_span / maxf(new_bounds.size.z, 0.001)
	replacement_scale.y = selected_placement.scale.y
	var replacement := BUILDING_SHELL_GENERATOR.pose_with_base_center(
		replacement_path,
		new_bounds,
		old_base_center,
		old_direction,
		replacement_scale,
		selected_placement.building_group_id,
		selected_placement.building_storey
	)
	replacement["id"] = selected_placement.placement_id
	for preserved_key: String in [
		"acoustic_boundary", "gameplay_role", "item_mass_kg", "value_per_mass",
		"assembly_group_id", "assembly_definition_id",
	]:
		replacement[preserved_key] = old_snapshot.get(
			preserved_key,
			replacement.get(preserved_key)
		)
	undo_redo.create_action("Replace compatible building piece")
	undo_redo.add_do_method(_replace_placement_snapshot.bind(replacement))
	undo_redo.add_undo_method(_replace_placement_snapshot.bind(old_snapshot))
	undo_redo.commit_action()
	selected_catalog_path = replacement_path
	_mark_dirty()
	_set_status("REPLACED WITH %s" % replacement_path.get_file().get_basename().to_upper())


func _replace_placement_snapshot(snapshot: Dictionary) -> void:
	var placement_id := int(snapshot.get("id", 0))
	if placements_by_id.has(placement_id):
		_remove_placement_by_id(placement_id, false)
	_restore_placement(snapshot)
	var replacement := placements_by_id.get(placement_id) as LevelAssetPlacement
	_select_placement(replacement)
	_refresh_used_assets_bar()


func _duplicate_building_storey() -> void:
	if selected_placement == null or selected_placement.building_group_id <= 0:
		_set_status("SELECT A PART OF A GENERATED ROOM", true)
		return
	var group_id := selected_placement.building_group_id
	var source_storey := selected_placement.building_storey
	var source: Array[LevelAssetPlacement] = []
	var has_roof := false
	var storey_height := 0.0
	for placement: LevelAssetPlacement in placements_by_id.values():
		if placement.building_group_id != group_id or placement.building_storey != source_storey:
			continue
		source.append(placement)
		var entry: Dictionary = catalog_entries_by_path.get(placement.asset_path, {})
		var role: StringName = entry.get("building_role", &"")
		has_roof = has_roof or role == BUILDING_KITS.ROLE_ROOF
		if role == BUILDING_KITS.ROLE_WALL:
			storey_height = maxf(
				storey_height,
				placement.local_bounds.size.y * placement.scale.y
			)
	if source.is_empty() or storey_height <= 0.05:
		_set_status("COULD NOT MEASURE THIS ROOM'S WALL HEIGHT", true)
		return
	var snapshots: Array[Dictionary] = []
	var new_ids: Array[int] = []
	for placement: LevelAssetPlacement in source:
		var entry: Dictionary = catalog_entries_by_path.get(placement.asset_path, {})
		if has_roof and entry.get("building_role", &"") == BUILDING_KITS.ROLE_FLOOR:
			continue
		var snapshot := placement.snapshot()
		var next_id := document.allocate_placement_id()
		snapshot["id"] = next_id
		snapshot["position"] = (snapshot["position"] as Vector3) + Vector3.UP * storey_height
		snapshot["building_storey"] = source_storey + 1
		new_ids.append(next_id)
		snapshots.append(snapshot)
	undo_redo.create_action("Duplicate building storey")
	undo_redo.add_do_method(_restore_placements.bind(snapshots))
	undo_redo.add_undo_method(_remove_placements_by_id.bind(new_ids))
	undo_redo.commit_action()
	_select_placement_ids(new_ids)
	_mark_dirty()
	_set_status("ADDED STOREY %d  //  %.2f M ABOVE" % [
		source_storey + 2,
		storey_height,
	])


func _refresh_building_controls() -> void:
	if building_compatible_options == null:
		return
	building_compatible_options.clear()
	var source_path := ""
	if selected_placement != null and selected_placements_by_id.size() == 1:
		source_path = selected_placement.asset_path
	elif not selected_catalog_path.is_empty():
		source_path = selected_catalog_path
	var source_entry: Dictionary = catalog_entries_by_path.get(source_path, {})
	var kit_id := str(source_entry.get("building_kit", ""))
	var socket: StringName = source_entry.get("building_socket", &"")
	if kit_id.is_empty() or socket.is_empty():
		building_compatible_options.add_item("NO COMPATIBLE SEGMENT SELECTED")
		building_compatible_options.set_item_metadata(0, "")
	else:
		var current_index := 0
		for candidate: Dictionary in BUILDING_KITS.compatible_entries(
			catalog,
			kit_id,
			socket
		):
			var path := str(candidate.get("asset_path", ""))
			var index := building_compatible_options.item_count
			building_compatible_options.add_item("[%s] %s" % [
				str(candidate.get("building_role_label", "PART")).to_upper(),
				str(candidate.get("display_name", "Asset")),
			])
			building_compatible_options.set_item_metadata(index, path)
			if path == source_path:
				current_index = index
		building_compatible_options.select(current_index)
	var has_single_building := (
		selected_placement != null
		and selected_placements_by_id.size() == 1
		and not str(catalog_entries_by_path.get(
			selected_placement.asset_path,
			{}
		).get("building_kit", "")).is_empty()
	)
	building_replace_button.disabled = not has_single_building
	building_storey_button.disabled = (
		not has_single_building or selected_placement.building_group_id <= 0
	)
	if building_status_label != null:
		var active_kit := _selected_building_kit()
		var wall_path := _room_wall_path(active_kit)
		building_status_label.text = (
			"KIT %s  //  ROOM WALL %s  //  DRAG IN VIEWPORT" % [
				active_kit,
				wall_path.get_file().get_basename().to_upper()
			]
			if not wall_path.is_empty()
			else "SELECT A KIT WITH WALL AND FLOOR PIECES"
		)


func _on_asset_favorite_toggle_requested(asset_path: String) -> void:
	if not catalog_entries_by_path.has(asset_path):
		return
	var next_favorite := not favorite_asset_paths.has(asset_path)
	if next_favorite:
		favorite_asset_paths[asset_path] = true
	else:
		favorite_asset_paths.erase(asset_path)
	asset_list.set_asset_favorite(asset_path, next_favorite)
	_update_favorite_filter_label()
	var save_error: Error = FAVORITES_STORE.save_paths(
		favorite_asset_paths,
		favorites_storage_path
	)
	if save_error != OK:
		_set_status("COULD NOT SAVE ASSET FAVORITES", true)
		return
	_set_status(
		("FAVORITED " if next_favorite else "REMOVED FAVORITE ")
		+ asset_path.get_file().get_basename().to_upper()
	)
	if _selected_catalog_filter() == FAVORITES_FILTER:
		_refresh_catalog_list()


func _selected_catalog_filter() -> String:
	if category_filter == null or category_filter.item_count <= 0:
		return "All assets"
	return str(category_filter.get_item_metadata(category_filter.selected))


func _favorite_filter_label() -> String:
	return "★ Favorites  [%d]" % favorite_asset_paths.size()


func _update_favorite_filter_label() -> void:
	if (
		category_filter == null
		or favorite_filter_option_index < 0
		or favorite_filter_option_index >= category_filter.item_count
	):
		return
	category_filter.set_item_text(
		favorite_filter_option_index,
		_favorite_filter_label()
	)


func _prune_favorite_paths() -> void:
	var changed := false
	for asset_path: String in favorite_asset_paths.keys():
		if not catalog_entries_by_path.has(asset_path):
			favorite_asset_paths.erase(asset_path)
			changed = true
	if changed:
		FAVORITES_STORE.save_paths(
			favorite_asset_paths,
			favorites_storage_path
		)


func _on_catalog_item_selected(index: int) -> void:
	if index < 0 or index >= asset_list.item_count:
		return
	var asset_path := str(asset_list.get_item_metadata(index))
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return
	_select_asset_path(asset_path)


func _on_catalog_item_activated(index: int) -> void:
	_on_catalog_item_selected(index)
	if selected_catalog_path.is_empty():
		return
	var hit := _screen_to_placement_hit(editor_viewport.size * 0.5)
	if not hit.is_empty():
		_place_asset_at_hit(selected_catalog_path, hit)


func _select_asset_path(asset_path: String) -> void:
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return
	selected_catalog_path = asset_path
	var entry: Dictionary = catalog_entries_by_path.get(asset_path, {})
	if entry.get("building_role", &"") == BUILDING_KITS.ROLE_WALL:
		building_room_wall_paths[str(entry.get("building_kit", ""))] = asset_path
	preview.show_asset(selected_catalog_path)
	var context_label := str(entry.get("subcategory", ""))
	if not str(entry.get("building_kit", "")).is_empty():
		var module_span := BUILDING_SHELL_GENERATOR.horizontal_span(
			LevelAssetPlacement.asset_bounds(asset_path)
		)
		context_label = "KIT %s  /  %s  /  %s SOCKET  /  %.2f M MODULE" % [
			str(entry.get("building_kit", "")),
			str(entry.get("building_role_label", "PART")),
			str(entry.get("building_socket", &"detail")).replace("_", " ").to_upper(),
			module_span,
		]
	if context_label.is_empty():
		context_label = str(entry.get("folder_name", "Assets"))
	catalog_selection_label.text = "%s\n%s" % [
		str(entry.get(
			"display_name",
			asset_path.get_file().get_basename().replace("_", " ").capitalize()
		)).to_upper(),
		"%s  //  %s" % [
			str(entry.get("category", "Other")),
			context_label,
		],
	]
	_arm_asset_placement(selected_catalog_path)
	_refresh_building_controls()
	if catalog_item_indices_by_path.has(asset_path):
		var item_index := catalog_item_indices_by_path[asset_path]
		asset_list.select(item_index)
		asset_list.ensure_current_is_visible()


func _on_catalog_visible_range_changed(first_index: int, last_index: int) -> void:
	if asset_list.item_count <= 0:
		return
	for item_index: int in range(
		clampi(first_index, 0, asset_list.item_count - 1),
		clampi(last_index + 1, 0, asset_list.item_count)
	):
		var asset_path := str(asset_list.get_item_metadata(item_index))
		if asset_path.is_empty():
			continue
		asset_list.set_item_icon(
			item_index,
			thumbnail_renderer.request(asset_path, true)
		)


func _on_asset_thumbnail_ready(asset_path: String, texture: Texture2D) -> void:
	if catalog_item_indices_by_path.has(asset_path):
		var item_index := catalog_item_indices_by_path[asset_path]
		if item_index >= 0 and item_index < asset_list.item_count:
			asset_list.set_item_icon(item_index, texture)
	if used_asset_buttons_by_path.has(asset_path):
		used_asset_buttons_by_path[asset_path].icon = texture
	for definition_id: String in assembly_buttons_by_id:
		var definition: Dictionary = assembly_definitions_by_id.get(
			definition_id,
			{}
		)
		var parts: Array = definition.get("parts", [])
		if (
			not parts.is_empty()
			and str((parts[0] as Dictionary).get("asset_path", "")) == asset_path
		):
			assembly_buttons_by_id[definition_id].icon = texture


func _refresh_used_assets_bar() -> void:
	if used_assets_row == null:
		return
	for child: Node in used_assets_row.get_children():
		used_assets_row.remove_child(child)
		child.queue_free()
	used_asset_buttons_by_path.clear()
	var placement_ids: Array[int] = []
	for placement_id: int in placements_by_id:
		placement_ids.append(placement_id)
	placement_ids.sort()
	var seen_paths: Dictionary[String, bool] = {}
	for placement_id: int in placement_ids:
		var placement := placements_by_id[placement_id] as LevelAssetPlacement
		if placement == null or seen_paths.has(placement.asset_path):
			continue
		seen_paths[placement.asset_path] = true
		var entry: Dictionary = catalog_entries_by_path.get(placement.asset_path, {})
		var button := Button.new()
		button.custom_minimum_size = Vector2(156.0, 54.0)
		button.text = str(entry.get(
			"display_name",
			placement.asset_path.get_file().get_basename().replace("_", " ").capitalize()
		))
		button.icon = thumbnail_renderer.request(placement.asset_path, true)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 58)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = "%s\n%s" % [
			str(entry.get(
				"browser_group_name",
				entry.get("folder_name", "Assets")
			)),
			placement.asset_path,
		]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_asset_path.bind(placement.asset_path))
		used_assets_row.add_child(button)
		used_asset_buttons_by_path[placement.asset_path] = button
	if not seen_paths.is_empty():
		used_assets_empty_label = null
		return
	used_assets_empty_label = _label(
		"PLACE AN ASSET AND IT WILL STAY ONE CLICK AWAY HERE",
		12,
		COLOR_MUTED
	)
	used_assets_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	used_assets_row.add_child(used_assets_empty_label)


func _refresh_assembly_shelf() -> void:
	if assembly_shelf_row == null:
		return
	for child: Node in assembly_shelf_row.get_children():
		assembly_shelf_row.remove_child(child)
		child.queue_free()
	assembly_buttons_by_id.clear()
	var definitions: Array[Dictionary] = []
	for definition_value: Variant in assembly_definitions_by_id.values():
		if definition_value is Dictionary:
			definitions.append(definition_value as Dictionary)
	definitions.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_name := str(left.get("name", "")).to_lower()
			var right_name := str(right.get("name", "")).to_lower()
			if left_name == right_name:
				return str(left.get("id", "")) < str(right.get("id", ""))
			return left_name < right_name
	)
	for definition: Dictionary in definitions:
		var definition_id := str(definition.get("id", ""))
		var parts: Array = definition.get("parts", [])
		if definition_id.is_empty() or parts.is_empty():
			continue
		var first_part := parts[0] as Dictionary
		var preview_path := str(first_part.get("asset_path", ""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(190.0, 62.0)
		button.text = "%s\n%d PART%s" % [
			str(definition.get("name", "Assembly")),
			parts.size(),
			"" if parts.size() == 1 else "S",
		]
		button.icon = thumbnail_renderer.request(preview_path, true)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 62)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = (
			"Place every saved part with its original relative transform"
		)
		button.pressed.connect(_arm_assembly_placement.bind(definition_id))
		assembly_shelf_row.add_child(button)
		assembly_buttons_by_id[definition_id] = button
	if not assembly_buttons_by_id.is_empty():
		assembly_shelf_empty_label = null
		return
	assembly_shelf_empty_label = _label(
		"SELECT 2+ PLACED ASSETS, RIGHT-CLICK, THEN MERGE & SAVE",
		12,
		COLOR_MUTED
	)
	assembly_shelf_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	assembly_shelf_row.add_child(assembly_shelf_empty_label)


func _on_asset_dropped(asset_path: String, local_position: Vector2) -> void:
	var hit := _screen_to_placement_hit(_viewport_pixel(local_position))
	if hit.is_empty():
		_set_status("DROP MISSED THE EDITOR WORLD", true)
		return
	selected_catalog_path = asset_path
	_arm_asset_placement(asset_path)
	_place_asset_at_hit(asset_path, hit)


func _place_asset(asset_path: String, world_position: Vector3) -> void:
	_place_asset_at_hit(asset_path, {
		"position": world_position,
		"normal": Vector3.UP,
	})


func _place_asset_at_hit(asset_path: String, hit: Dictionary) -> void:
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		_set_status("INVALID ASSET PATH", true)
		return
	if hit.is_empty():
		_set_status("NO PLACEMENT SURFACE", true)
		return
	var placement := _instantiate_placement(document.allocate_placement_id(), asset_path)
	if placement == null:
		_set_status("COULD NOT INSTANTIATE %s" % asset_path, true)
		return
	_apply_placement_pose(placement, hit)
	var snapshot := placement.snapshot()
	undo_redo.create_action("Place asset")
	undo_redo.add_do_method(_restore_placement.bind(snapshot))
	undo_redo.add_undo_method(_remove_placement_by_id.bind(placement.placement_id))
	undo_redo.commit_action(false)
	_select_placement(placement)
	_mark_dirty()
	_set_status("PLACED %s" % asset_path.get_file().get_basename().to_upper())


func _place_assembly_at_hit(definition_id: String, hit: Dictionary) -> void:
	var definition: Dictionary = assembly_definitions_by_id.get(
		definition_id,
		{}
	)
	if definition.is_empty() or hit.is_empty():
		_set_status("ASSEMBLY OR PLACEMENT SURFACE IS INVALID", true)
		return
	if assembly_preview == null or assembly_preview.definition_id != definition_id:
		_set_status("ASSEMBLY PREVIEW IS NOT READY", true)
		return
	_apply_assembly_preview_pose(assembly_preview, hit)
	var assembly_transform := assembly_preview.transform
	var group_id := document.allocate_assembly_group_id()
	var snapshots: Array[Dictionary] = []
	var placement_ids: Array[int] = []
	for part_value: Dictionary in definition.get("parts", []):
		var part := ASSEMBLY_STORE.sanitize_part(part_value)
		if part.is_empty():
			continue
		var part_rotation: Vector3 = part.get("rotation", Vector3.ZERO)
		var part_scale: Vector3 = part.get("scale", Vector3.ONE)
		var part_position: Vector3 = part.get("position", Vector3.ZERO)
		var local_basis := Basis.from_euler(part_rotation).scaled(part_scale)
		var local_transform := Transform3D(
			local_basis,
			part_position
		)
		var world_transform := assembly_transform * local_transform
		var world_scale := world_transform.basis.get_scale().abs()
		var rotation_basis := world_transform.basis.orthonormalized()
		var placement_id := document.allocate_placement_id()
		placement_ids.append(placement_id)
		snapshots.append({
			"id": placement_id,
			"asset_path": part["asset_path"],
			"position": world_transform.origin,
			"rotation": rotation_basis.get_euler(),
			"scale": world_scale,
			"acoustic_boundary": bool(part.get("acoustic_boundary", true)),
			"gameplay_role": part.get(
				"gameplay_role",
				LevelEditorDocument.PLACEMENT_ROLE_STATIC
			),
			"item_mass_kg": float(part.get("item_mass_kg", 1.0)),
			"value_per_mass": float(part.get("value_per_mass", 0.0)),
			"assembly_group_id": group_id,
			"assembly_definition_id": definition_id,
		})
	if snapshots.is_empty():
		_set_status("ASSEMBLY CONTAINS NO VALID PARTS", true)
		return
	undo_redo.create_action("Place assembly %s" % str(definition.get("name", "")))
	undo_redo.add_do_method(_restore_placements.bind(snapshots))
	undo_redo.add_undo_method(_remove_placements_by_id.bind(placement_ids))
	undo_redo.commit_action()
	_select_placement_ids(placement_ids)
	_mark_dirty()
	_set_status("PLACED ASSEMBLY  //  %d PARTS" % snapshots.size())


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
	if not rebuilding_placements:
		_refresh_used_assets_bar()
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


func _remove_placement_by_id(placement_id: int, refresh_ui := true) -> void:
	var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
	if placement == null:
		return
	selected_placements_by_id.erase(placement_id)
	if placement == selected_placement:
		selected_placement = _last_selected_placement()
	placement.set_selected(false)
	placements_by_id.erase(placement_id)
	placement_root.remove_child(placement)
	placement.free()
	if refresh_ui:
		_refresh_used_assets_bar()
		_refresh_inspector()


func _apply_placement_snapshot(placement_id: int, snapshot: Dictionary) -> void:
	var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
	if placement == null:
		return
	placement.apply_snapshot(snapshot)
	if acoustic_state != null:
		acoustic_state.sync_anchored_portals(placements_by_id)
	if selected_placements_by_id.has(placement_id):
		_refresh_inspector()


func _select_placement(placement: LevelAssetPlacement) -> void:
	for selected: LevelAssetPlacement in selected_placements_by_id.values():
		selected.set_selected(false)
	selected_placements_by_id.clear()
	selected_placement = placement
	if selected_placement != null:
		for member: LevelAssetPlacement in _assembly_members(placement):
			selected_placements_by_id[member.placement_id] = member
			member.set_selected(true)
	_refresh_inspector()


func _toggle_placement_selection(placement: LevelAssetPlacement) -> void:
	if placement == null:
		return
	var members := _assembly_members(placement)
	var all_selected := true
	for member: LevelAssetPlacement in members:
		if not selected_placements_by_id.has(member.placement_id):
			all_selected = false
			break
	if all_selected:
		for member: LevelAssetPlacement in members:
			selected_placements_by_id.erase(member.placement_id)
			member.set_selected(false)
		selected_placement = _last_selected_placement()
	else:
		for member: LevelAssetPlacement in members:
			selected_placements_by_id[member.placement_id] = member
			member.set_selected(true)
		selected_placement = placement
	_refresh_inspector()
	_set_selection_status()


func _assembly_members(placement: LevelAssetPlacement) -> Array[LevelAssetPlacement]:
	var result: Array[LevelAssetPlacement] = []
	if placement == null:
		return result
	var group_id := placement.assembly_group_id
	if group_id <= 0:
		result.append(placement)
		return result
	var member_ids: Array[int] = []
	for placement_id: int in placements_by_id:
		var candidate := placements_by_id[placement_id] as LevelAssetPlacement
		if candidate != null and candidate.assembly_group_id == group_id:
			member_ids.append(placement_id)
	member_ids.sort()
	for placement_id: int in member_ids:
		result.append(placements_by_id[placement_id] as LevelAssetPlacement)
	if result.is_empty():
		result.append(placement)
	return result


func _select_placement_ids(placement_ids: Array[int]) -> void:
	_select_placement(null)
	for placement_id: int in placement_ids:
		var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
		if placement == null:
			continue
		selected_placements_by_id[placement_id] = placement
		placement.set_selected(true)
		selected_placement = placement
	_refresh_inspector()
	_set_selection_status()


func _last_selected_placement() -> LevelAssetPlacement:
	var selected_ids: Array[int] = []
	for placement_id: int in selected_placements_by_id:
		selected_ids.append(placement_id)
	selected_ids.sort()
	if selected_ids.is_empty():
		return null
	return (
		selected_placements_by_id[selected_ids.back()] as LevelAssetPlacement
	)


func _selected_placements() -> Array[LevelAssetPlacement]:
	var selected_ids: Array[int] = []
	for placement_id: int in selected_placements_by_id:
		selected_ids.append(placement_id)
	selected_ids.sort()
	var result: Array[LevelAssetPlacement] = []
	for placement_id: int in selected_ids:
		var placement := (
			selected_placements_by_id.get(placement_id) as LevelAssetPlacement
		)
		if placement != null and is_instance_valid(placement):
			result.append(placement)
	return result


func _capture_selected_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for placement: LevelAssetPlacement in _selected_placements():
		snapshots.append(placement.snapshot())
	return snapshots


func _apply_placement_snapshots(
	snapshots: Array,
	refresh_inspector := true
) -> void:
	for snapshot_value: Variant in snapshots:
		if not snapshot_value is Dictionary:
			continue
		var snapshot := snapshot_value as Dictionary
		var placement_id := int(snapshot.get("id", 0))
		var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
		if placement != null:
			placement.apply_snapshot(snapshot)
	if acoustic_state != null:
		acoustic_state.sync_anchored_portals(placements_by_id)
	if refresh_inspector:
		_refresh_inspector()


func _restore_placements(snapshots: Array) -> void:
	var previous_rebuild_state := rebuilding_placements
	rebuilding_placements = true
	for snapshot_value: Variant in snapshots:
		if snapshot_value is Dictionary:
			_restore_placement(snapshot_value as Dictionary)
	rebuilding_placements = previous_rebuild_state
	_refresh_used_assets_bar()
	_refresh_inspector()


func _remove_placements_by_id(placement_ids: Array) -> void:
	for placement_id_value: Variant in placement_ids:
		_remove_placement_by_id(int(placement_id_value), false)
	_refresh_used_assets_bar()
	_refresh_inspector()


func _snapshot_for_id(
	snapshots: Array[Dictionary],
	placement_id: int
) -> Dictionary:
	for snapshot: Dictionary in snapshots:
		if int(snapshot.get("id", 0)) == placement_id:
			return snapshot
	return {}


func _snapshots_pivot(snapshots: Array[Dictionary]) -> Vector3:
	if snapshots.is_empty():
		return Vector3.ZERO
	var pivot := Vector3.ZERO
	for snapshot: Dictionary in snapshots:
		pivot += snapshot.get("position", Vector3.ZERO) as Vector3
	return pivot / float(snapshots.size())


func _translated_snapshots(
	snapshots: Array[Dictionary],
	delta: Vector3
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in snapshots:
		var next := source.duplicate(false)
		next["position"] = (
			source.get("position", Vector3.ZERO) as Vector3
		) + delta
		result.append(next)
	return result


func _rotated_snapshots(
	snapshots: Array[Dictionary],
	axis: Vector3,
	angle: float,
	pivot: Vector3
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rotation_basis := Basis(axis.normalized(), angle)
	for source: Dictionary in snapshots:
		var next := source.duplicate(false)
		var source_position := source.get("position", Vector3.ZERO) as Vector3
		next["position"] = pivot + rotation_basis * (source_position - pivot)
		var source_rotation := source.get("rotation", Vector3.ZERO) as Vector3
		# Compose the global-axis rotation as a basis. Adding one Euler component
		# only works for otherwise unrotated objects and made X/Z handles produce
		# coupled or visibly incorrect turns after a previous rotation.
		next["rotation"] = (
			rotation_basis * Basis.from_euler(source_rotation)
		).orthonormalized().get_euler()
		result.append(next)
	return result


func _uniformly_scaled_snapshots(
	snapshots: Array[Dictionary],
	factor: float,
	pivot: Vector3
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in snapshots:
		var next := source.duplicate(false)
		var source_position := source.get("position", Vector3.ZERO) as Vector3
		next["position"] = pivot + (source_position - pivot) * factor
		next["scale"] = (
			(source.get("scale", Vector3.ONE) as Vector3) * factor
		).clamp(Vector3.ONE * 0.01, Vector3.ONE * 1000.0)
		result.append(next)
	return result


func _axis_scaled_snapshots(
	snapshots: Array[Dictionary],
	axis_index: int,
	factor: float,
	pivot: Vector3
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for source: Dictionary in snapshots:
		var next := source.duplicate(false)
		var offset := (
			source.get("position", Vector3.ZERO) as Vector3
		) - pivot
		offset[axis_index] *= factor
		next["position"] = pivot + offset
		var next_scale := source.get("scale", Vector3.ONE) as Vector3
		next_scale[axis_index] = clampf(
			next_scale[axis_index] * factor,
			0.01,
			1000.0
		)
		next["scale"] = next_scale
		result.append(next)
	return result


func _snapshot_arrays_match(
	a: Array[Dictionary],
	b: Array[Dictionary]
) -> bool:
	if a.size() != b.size():
		return false
	for index: int in range(a.size()):
		if (
			int(a[index].get("id", 0)) != int(b[index].get("id", 0))
			or not _snapshots_match(a[index], b[index])
		):
			return false
	return true


func _set_selection_status() -> void:
	var count := selected_placements_by_id.size()
	if count <= 0:
		_set_status("SELECTION CLEARED")
	elif count == 1:
		_set_status("ASSET SELECTED  //  SHIFT OR CTRL CLICK TO ADD")
	else:
		_set_status(
			"%d ASSETS SELECTED  //  TRANSFORMS USE GROUP PIVOT" % count
		)


func _open_selection_context_menu(global_position: Vector2) -> void:
	if selected_placements_by_id.is_empty():
		return
	var merge_index := selection_context_menu.get_item_index(
		CONTEXT_MERGE_ASSEMBLY
	)
	selection_context_menu.set_item_disabled(
		merge_index,
		selected_placements_by_id.size() < 2
	)
	var has_group := false
	for placement: LevelAssetPlacement in _selected_placements():
		if placement.assembly_group_id > 0:
			has_group = true
			break
	var ungroup_index := selection_context_menu.get_item_index(
		CONTEXT_UNGROUP_ASSEMBLY
	)
	selection_context_menu.set_item_disabled(ungroup_index, not has_group)
	var selected_role := (
		selected_placement.gameplay_role
		if selected_placement != null
		else LevelEditorDocument.PLACEMENT_ROLE_STATIC
	)
	for role_id: int in [MARK_AS_STATIC, MARK_AS_ITEM, MARK_AS_VALUABLE]:
		mark_as_menu.set_item_checked(
			mark_as_menu.get_item_index(role_id),
			(role_id == MARK_AS_STATIC and selected_role == LevelEditorDocument.PLACEMENT_ROLE_STATIC)
			or (role_id == MARK_AS_ITEM and selected_role == LevelEditorDocument.PLACEMENT_ROLE_ITEM)
			or (role_id == MARK_AS_VALUABLE and selected_role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE)
		)
	selection_context_menu.position = Vector2i(global_position.round())
	selection_context_menu.popup()


func _on_selection_context_action(action_id: int) -> void:
	match action_id:
		CONTEXT_MERGE_ASSEMBLY:
			_request_merge_selected()
		CONTEXT_UNGROUP_ASSEMBLY:
			_ungroup_selected()
		CONTEXT_FOCUS:
			_focus_selected()
		CONTEXT_DUPLICATE:
			_duplicate_selected()
		CONTEXT_DELETE:
			_delete_selected()


func _on_mark_as_action(action_id: int) -> void:
	if selected_placements_by_id.is_empty():
		return
	match action_id:
		MARK_AS_STATIC:
			_set_selected_gameplay_role(
				LevelEditorDocument.PLACEMENT_ROLE_STATIC,
				1.0,
				0.0
			)
		MARK_AS_ITEM:
			_open_item_properties_dialog(LevelEditorDocument.PLACEMENT_ROLE_ITEM)
		MARK_AS_VALUABLE:
			_open_item_properties_dialog(LevelEditorDocument.PLACEMENT_ROLE_VALUABLE)


func _open_item_properties_dialog(role: StringName) -> void:
	pending_gameplay_role = LevelEditorDocument.sanitize_gameplay_role(role)
	var primary := selected_placement
	item_mass_field.value = primary.item_mass_kg if primary != null else 1.0
	item_value_per_mass_field.value = (
		maxf(primary.value_per_mass, 10.0)
		if primary != null and pending_gameplay_role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		else 0.0
	)
	item_value_row.visible = (
		pending_gameplay_role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
	)
	item_properties_dialog.title = (
		"Mark as Valuable"
		if item_value_row.visible
		else "Mark as Item"
	)
	_refresh_item_total_value()
	item_properties_dialog.popup_centered(Vector2i(470, 250))
	item_mass_field.get_line_edit().grab_focus()
	item_mass_field.get_line_edit().select_all()


func _refresh_item_total_value(_ignored := 0.0) -> void:
	if item_total_value_label == null:
		return
	var total := (
		float(item_mass_field.value) * float(item_value_per_mass_field.value)
		if pending_gameplay_role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		else 0.0
	)
	item_total_value_label.visible = (
		pending_gameplay_role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
	)
	item_total_value_label.text = "TOTAL VALUE  %.2f" % total


func _confirm_mark_as_item() -> void:
	_set_selected_gameplay_role(
		pending_gameplay_role,
		float(item_mass_field.value),
		float(item_value_per_mass_field.value)
	)


func _set_selected_gameplay_role(
	role: StringName,
	mass_kg: float,
	value_rate: float
) -> void:
	if selected_placements_by_id.is_empty():
		return
	var safe_role := LevelEditorDocument.sanitize_gameplay_role(role)
	var safe_mass := clampf(
		mass_kg,
		LevelEditorDocument.MINIMUM_ITEM_MASS_KG,
		LevelEditorDocument.MAXIMUM_ITEM_MASS_KG
	)
	var safe_value := (
		clampf(value_rate, 0.0, LevelEditorDocument.MAXIMUM_VALUE_PER_MASS)
		if safe_role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		else 0.0
	)
	var previous := _capture_selected_snapshots()
	for placement: LevelAssetPlacement in _selected_placements():
		placement.gameplay_role = safe_role
		if safe_role != LevelEditorDocument.PLACEMENT_ROLE_STATIC:
			placement.item_mass_kg = safe_mass
			placement.value_per_mass = safe_value
	var next := _capture_selected_snapshots()
	undo_redo.create_action("Mark assets as %s" % str(safe_role))
	undo_redo.add_do_method(_apply_placement_snapshots.bind(next))
	undo_redo.add_undo_method(_apply_placement_snapshots.bind(previous))
	undo_redo.commit_action(false)
	_mark_dirty()
	_refresh_inspector()
	_set_status(
		"%d ASSET%s MARKED %s%s"
		% [
			next.size(),
			"" if next.size() == 1 else "S",
			str(safe_role).to_upper(),
			(
				"  //  %.2f KG  //  %.2f VALUE"
				% [safe_mass, safe_mass * safe_value]
				if safe_role != LevelEditorDocument.PLACEMENT_ROLE_STATIC
				else ""
			),
		]
	)


func _request_merge_selected() -> void:
	if selected_placements_by_id.size() < 2:
		_set_status("SELECT AT LEAST 2 ASSETS TO MERGE", true)
		return
	pending_merge_placement_ids.clear()
	for placement: LevelAssetPlacement in _selected_placements():
		pending_merge_placement_ids.append(placement.placement_id)
	var primary_name := (
		selected_placement.asset_path.get_file().get_basename()
		if selected_placement != null
		else "assembly"
	)
	assembly_name_field.text = "%s Assembly" % (
		primary_name.replace("_", " ").capitalize()
	)
	assembly_name_dialog.popup_centered(Vector2i(500, 190))
	assembly_name_field.grab_focus()
	assembly_name_field.select_all()


func _clear_pending_merge() -> void:
	pending_merge_placement_ids.clear()


func _confirm_merge_selected() -> void:
	var snapshots: Array[Dictionary] = []
	for placement_id: int in pending_merge_placement_ids:
		var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
		if placement != null:
			snapshots.append(placement.snapshot())
	if snapshots.size() < 2:
		_clear_pending_merge()
		_set_status("ASSEMBLY SELECTION CHANGED BEFORE SAVE", true)
		return
	var bounds := _bounds_for_placement_ids(pending_merge_placement_ids)
	if bounds.size.length_squared() <= 0.000001:
		_clear_pending_merge()
		_set_status("ASSEMBLY HAS NO USABLE BOUNDS", true)
		return
	var definition := ASSEMBLY_STORE.create_definition(
		assembly_name_field.text,
		snapshots,
		bounds.get_center(),
		assembly_definitions_by_id
	)
	if definition.is_empty():
		_clear_pending_merge()
		_set_status("ASSEMBLY NAME OR PARTS ARE INVALID", true)
		return
	var definition_id := str(definition.get("id", ""))
	assembly_definitions_by_id[definition_id] = definition
	var save_error := ASSEMBLY_STORE.save_definitions(
		assembly_definitions_by_id,
		assembly_storage_path
	)
	if save_error != OK:
		assembly_definitions_by_id.erase(definition_id)
		_clear_pending_merge()
		_set_status(
			"ASSEMBLY SAVE FAILED  //  %s" % error_string(save_error).to_upper(),
			true
		)
		return
	var group_id := document.allocate_assembly_group_id()
	var grouped_snapshots: Array[Dictionary] = []
	for snapshot: Dictionary in snapshots:
		var grouped := snapshot.duplicate(true)
		grouped["assembly_group_id"] = group_id
		grouped["assembly_definition_id"] = definition_id
		grouped_snapshots.append(grouped)
	undo_redo.create_action("Merge %d assets as assembly" % snapshots.size())
	undo_redo.add_do_method(_apply_placement_snapshots.bind(grouped_snapshots))
	undo_redo.add_undo_method(_apply_placement_snapshots.bind(snapshots))
	undo_redo.commit_action()
	_refresh_assembly_shelf()
	_select_placement_ids(pending_merge_placement_ids)
	_clear_pending_merge()
	_mark_dirty()
	_set_status("MERGED & SAVED  //  %s" % str(definition.get("name", "")))


func _ungroup_selected() -> void:
	var previous := _capture_selected_snapshots()
	var next: Array[Dictionary] = []
	var changed := false
	for snapshot: Dictionary in previous:
		var ungrouped := snapshot.duplicate(true)
		if int(ungrouped.get("assembly_group_id", 0)) > 0:
			changed = true
		ungrouped["assembly_group_id"] = 0
		ungrouped["assembly_definition_id"] = ""
		next.append(ungrouped)
	if not changed:
		return
	undo_redo.create_action("Ungroup %d assets" % previous.size())
	undo_redo.add_do_method(_apply_placement_snapshots.bind(next))
	undo_redo.add_undo_method(_apply_placement_snapshots.bind(previous))
	undo_redo.commit_action()
	_mark_dirty()
	_set_status("ASSEMBLY GROUP RELEASED  //  REUSABLE COPY KEPT")


func _bounds_for_placement_ids(placement_ids: Array[int]) -> AABB:
	var result := AABB()
	var found := false
	for placement_id: int in placement_ids:
		var placement := placements_by_id.get(placement_id) as LevelAssetPlacement
		if placement == null:
			continue
		var placement_bounds := placement.global_transform * placement.local_bounds
		result = result.merge(placement_bounds) if found else placement_bounds
		found = true
	return result


func _select_all_placements() -> void:
	var placement_ids: Array[int] = []
	for placement_id: int in placements_by_id:
		placement_ids.append(placement_id)
	placement_ids.sort()
	_select_placement_ids(placement_ids)


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
		and building_room_tool_active
	):
		_cancel_room_shell_tool()
		return
	if (
		event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and speaker_authoring_active
	):
		_remove_last_draft_speaker()
		return
	if (
		event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and light_placement_active
	):
		_cancel_light_placement()
		return
	if (
		event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
		and (
			_has_pending_placement()
			or acoustic_tool == ACOUSTIC_TOOL_PLACE_PROBE
		)
	):
		if _has_pending_placement():
			_cancel_asset_placement()
		else:
			acoustic_tool = ACOUSTIC_TOOL_SELECT
			acoustic_place_probe_button.button_pressed = false
			_set_status("ACOUSTIC PROBE PLACEMENT CANCELLED")
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var context_hit := _pick_placement(_viewport_pixel(event.position))
		if context_hit != null:
			if not selected_placements_by_id.has(context_hit.placement_id):
				_select_placement(context_hit)
				_set_selection_status()
			else:
				selected_placement = context_hit
		if not selected_placements_by_id.is_empty():
			_open_selection_context_menu(event.global_position)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var viewport_position := _viewport_pixel(event.position)
	if event.pressed and _begin_transform_gizmo_drag(
		event.position,
		viewport_position
	):
		return
	if building_room_tool_active:
		if event.pressed:
			_begin_room_shell_drag(viewport_position)
		else:
			_finish_room_shell_drag(viewport_position)
		return
	if event.pressed:
		if light_placement_active:
			_place_authored_light(_screen_to_placement_hit(viewport_position))
			return
		if speaker_authoring_active:
			_place_draft_speaker(_screen_to_placement_hit(viewport_position))
			_update_speaker_cursor(viewport_position)
			return
		if acoustic_authoring_enabled:
			if acoustic_tool == ACOUSTIC_TOOL_PLACE_PROBE:
				_place_acoustic_probe_from_hit(
					_screen_to_placement_hit(viewport_position)
				)
				return
			var ray_origin := editor_camera.project_ray_origin(viewport_position)
			var ray_direction := editor_camera.project_ray_normal(viewport_position)
			var acoustic_hit := acoustic_state.pick(ray_origin, ray_direction)
			if not acoustic_hit.is_empty():
				if acoustic_hit.get("kind", &"") == &"probe":
					acoustic_state.select_probe(
						int(acoustic_hit.get("id", 0)),
						event.shift_pressed or event.ctrl_pressed or event.meta_pressed
					)
				else:
					acoustic_state.select_portal(int(acoustic_hit.get("id", 0)))
				return
		if _has_pending_placement():
			var hit := _screen_to_placement_hit(viewport_position)
			if not hit.is_empty():
				if not pending_assembly_id.is_empty():
					_place_assembly_at_hit(pending_assembly_id, hit)
				else:
					_place_asset_at_hit(pending_asset_path, hit)
				_update_placement_cursor(viewport_position)
			return
		if preview_tabs != null and preview_tabs.current_tab == light_tab_index:
			var light_hit: Node3D = _pick_authored_light(viewport_position)
			if light_hit != null:
				_select_authored_light(int(light_hit.get("light_id")))
				return
		var hit := _pick_placement(viewport_position)
		if event.shift_pressed or event.ctrl_pressed or event.meta_pressed:
			_toggle_placement_selection(hit)
			return
		if hit == null:
			_select_placement(null)
			_set_selection_status()
			return
		if not selected_placements_by_id.has(hit.placement_id):
			_select_placement(hit)
			_set_selection_status()
			return
		selected_placement = hit
		if edit_mode != MODE_SELECT:
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
	if transform_dragging and not selected_placements_by_id.is_empty():
		_update_transform_drag(event.position)
		return
	if building_room_tool_active and building_room_dragging:
		_update_room_shell_drag(_viewport_pixel(event.position))
		return
	if speaker_authoring_active:
		_update_speaker_cursor(_viewport_pixel(event.position))
		return
	if light_placement_active:
		_update_light_cursor(_viewport_pixel(event.position))
		return
	_update_transform_gizmo_hover(_viewport_pixel(event.position))
	_update_placement_cursor(_viewport_pixel(event.position))


func _arm_asset_placement(asset_path: String) -> void:
	if not LevelAssetCatalog.is_valid_asset_path(asset_path):
		return
	if building_room_tool_active:
		_cancel_room_shell_tool()
	if speaker_authoring_active:
		_cancel_speaker_system_authoring()
	_cancel_light_placement()
	pending_assembly_id = ""
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
	placement_preview.rotation = placement_rotation
	pending_asset_path = asset_path
	_refresh_transform_gizmo()
	has_placement_pointer = false
	if placement_cursor != null:
		placement_cursor.visible = false
	placement_preview.visible = false
	_set_status(
		"FREE PLACEMENT  //  R YAW  //  X/Z TILT  //  SHIFT = 15 DEGREES"
	)


func _arm_assembly_placement(definition_id: String) -> void:
	var definition: Dictionary = assembly_definitions_by_id.get(
		definition_id,
		{}
	)
	if definition.is_empty():
		_set_status("ASSEMBLY DEFINITION IS MISSING", true)
		return
	_cancel_light_placement()
	_clear_placement_preview()
	assembly_preview = LevelAssetAssemblyPreview.new()
	editor_world.add_child(assembly_preview)
	if not assembly_preview.configure(definition):
		editor_world.remove_child(assembly_preview)
		assembly_preview.free()
		assembly_preview = null
		pending_assembly_id = ""
		_set_status("COULD NOT PREVIEW ASSEMBLY", true)
		return
	assembly_preview.name = "AssemblyPlacementPreview"
	assembly_preview.process_mode = Node.PROCESS_MODE_DISABLED
	assembly_preview.rotation = placement_rotation
	assembly_preview.visible = false
	pending_asset_path = ""
	pending_assembly_id = definition_id
	_refresh_transform_gizmo()
	has_placement_pointer = false
	if placement_cursor != null:
		placement_cursor.visible = false
	_set_status(
		"ASSEMBLY ARMED  //  CLICK TO PLACE  //  R YAW  //  RMB CANCELS"
	)


func _has_pending_placement() -> bool:
	return not pending_asset_path.is_empty() or not pending_assembly_id.is_empty()


func _cancel_asset_placement() -> void:
	if not _has_pending_placement():
		return
	pending_asset_path = ""
	pending_assembly_id = ""
	has_placement_pointer = false
	placement_rotation = Vector3.ZERO
	if placement_cursor != null:
		placement_cursor.visible = false
	_clear_placement_preview()
	_refresh_transform_gizmo()
	_set_status("PLACEMENT CANCELLED")


func _update_placement_cursor(viewport_position: Vector2) -> void:
	if placement_cursor == null or not _has_pending_placement():
		return
	last_placement_viewport_position = viewport_position
	has_placement_pointer = true
	var hit := _screen_to_placement_hit(viewport_position)
	var has_position := not hit.is_empty()
	placement_cursor.visible = has_position
	if placement_preview != null:
		placement_preview.visible = has_position
	if assembly_preview != null:
		assembly_preview.visible = has_position
	if not has_position:
		return
	var surface_position: Vector3 = hit.get("position", Vector3.ZERO)
	var surface_normal: Vector3 = hit.get("normal", Vector3.UP)
	surface_position = _snap_surface_position(surface_position, surface_normal)
	placement_cursor.position = surface_position + surface_normal * 0.012
	placement_cursor.basis = _surface_marker_basis(surface_normal)
	if placement_preview != null:
		_apply_placement_pose(placement_preview, hit)
	elif assembly_preview != null:
		_apply_assembly_preview_pose(assembly_preview, hit)


func _clear_placement_preview() -> void:
	if placement_preview != null:
		if placement_preview.get_parent() != null:
			placement_preview.get_parent().remove_child(placement_preview)
		placement_preview.free()
		placement_preview = null
	if assembly_preview != null:
		if assembly_preview.get_parent() != null:
			assembly_preview.get_parent().remove_child(assembly_preview)
		assembly_preview.free()
		assembly_preview = null


func _begin_transform_drag(
	mouse_position: Vector2,
	viewport_position: Vector2
) -> void:
	if selected_placement == null or selected_placements_by_id.is_empty():
		return
	transform_drag_axis = Vector3.ZERO
	transform_drag_axis_index = -1
	transform_drag_axis_start_parameter = 0.0
	transform_drag_rotation_start_vector = Vector3.ZERO
	_prepare_transform_drag(mouse_position)
	if edit_mode == MODE_MOVE:
		var hit := _screen_to_height(viewport_position, selected_placement.position.y)
		transform_drag_move_offset = (
			selected_placement.position - hit
			if hit.is_finite()
			else Vector3.ZERO
		)


func _begin_transform_gizmo_drag(
	mouse_position: Vector2,
	viewport_position: Vector2
) -> bool:
	if (
		transform_gizmo == null
		or not transform_gizmo.visible
		or selected_placement == null
		or selected_placements_by_id.is_empty()
	):
		return false
	var axis_index: int = transform_gizmo.pick_axis(editor_camera, viewport_position)
	if axis_index < 0:
		return false
	transform_drag_axis_index = axis_index
	transform_drag_axis = transform_gizmo.axis_vector(axis_index)
	_prepare_transform_drag(mouse_position)
	if edit_mode == MODE_MOVE:
		transform_drag_axis_start_parameter = _axis_ray_parameter(
			viewport_position,
			transform_drag_start_pivot,
			transform_drag_axis
		)
	elif edit_mode == MODE_ROTATE:
		transform_drag_rotation_start_vector = _rotation_plane_vector(
			viewport_position,
			transform_drag_start_pivot,
			transform_drag_axis
		)
	transform_gizmo.set_hover_axis(axis_index)
	_set_status("DRAGGING %s %s  //  %s AXIS" % [
		str(edit_mode).to_upper(),
		"HANDLE",
		["X", "Y", "Z"][axis_index],
	])
	return true


func _prepare_transform_drag(mouse_position: Vector2) -> void:
	transform_dragging = true
	transform_drag_start_mouse = mouse_position
	transform_drag_start_snapshots = _capture_selected_snapshots()
	transform_drag_start_pivot = _snapshots_pivot(transform_drag_start_snapshots)


func _update_transform_gizmo_hover(viewport_position: Vector2) -> void:
	if transform_gizmo == null or transform_dragging:
		return
	transform_gizmo.set_hover_axis(
		transform_gizmo.pick_axis(editor_camera, viewport_position)
	)


func _axis_ray_parameter(
	viewport_position: Vector2,
	pivot: Vector3,
	axis: Vector3
) -> float:
	var ray_origin := editor_camera.project_ray_origin(viewport_position)
	var ray_direction := editor_camera.project_ray_normal(viewport_position).normalized()
	var normalized_axis := axis.normalized()
	var alignment := ray_direction.dot(normalized_axis)
	var denominator := 1.0 - alignment * alignment
	if denominator <= 0.0001:
		return NAN
	var origin_offset := ray_origin - pivot
	return (
		normalized_axis.dot(origin_offset)
		- alignment * ray_direction.dot(origin_offset)
	) / denominator


func _rotation_plane_vector(
	viewport_position: Vector2,
	pivot: Vector3,
	axis: Vector3
) -> Vector3:
	var ray_origin := editor_camera.project_ray_origin(viewport_position)
	var ray_direction := editor_camera.project_ray_normal(viewport_position).normalized()
	var normalized_axis := axis.normalized()
	var denominator := normalized_axis.dot(ray_direction)
	if absf(denominator) <= 0.0001:
		return Vector3.ZERO
	var ray_distance := normalized_axis.dot(pivot - ray_origin) / denominator
	if ray_distance < 0.0 or not is_finite(ray_distance):
		return Vector3.ZERO
	var result := ray_origin + ray_direction * ray_distance - pivot
	return result.normalized() if result.length_squared() > 0.000001 else Vector3.ZERO


func _update_transform_drag(mouse_position: Vector2) -> void:
	if transform_drag_start_snapshots.is_empty() or selected_placement == null:
		return
	var primary_start := _snapshot_for_id(
		transform_drag_start_snapshots,
		selected_placement.placement_id
	)
	if primary_start.is_empty():
		return
	var start_position: Vector3 = primary_start.get(
		"position",
		selected_placement.position
	)
	var start_rotation: Vector3 = primary_start.get(
		"rotation",
		selected_placement.rotation
	)
	var start_scale: Vector3 = primary_start.get(
		"scale",
		selected_placement.scale
	)
	var next_snapshots: Array[Dictionary] = []
	match edit_mode:
		MODE_MOVE:
			if transform_drag_axis.length_squared() > 0.5:
				var parameter := _axis_ray_parameter(
					_viewport_pixel(mouse_position),
					transform_drag_start_pivot,
					transform_drag_axis
				)
				var delta_amount := parameter - transform_drag_axis_start_parameter
				if is_finite(parameter) and is_finite(delta_amount):
					if snap_button.button_pressed:
						var axis_index := transform_drag_axis_index
						var target_component := (
							transform_drag_start_pivot[axis_index] + delta_amount
						)
						delta_amount = (
							snappedf(target_component, float(snap_step.value))
							- transform_drag_start_pivot[axis_index]
						)
					next_snapshots = _translated_snapshots(
						transform_drag_start_snapshots,
						transform_drag_axis * delta_amount
					)
			else:
				var hit := _screen_to_height(
					_viewport_pixel(mouse_position),
					start_position.y
				)
				if hit.is_finite():
					var next_position := hit + transform_drag_move_offset
					next_position = _snap_horizontal_position(next_position)
					next_snapshots = _translated_snapshots(
						transform_drag_start_snapshots,
						next_position - start_position
					)
		MODE_ROTATE:
			if transform_drag_axis.length_squared() > 0.5:
				var current_vector := _rotation_plane_vector(
					_viewport_pixel(mouse_position),
					transform_drag_start_pivot,
					transform_drag_axis
				)
				var angle := 0.0
				if (
					transform_drag_rotation_start_vector.length_squared() > 0.5
					and current_vector.length_squared() > 0.5
				):
					angle = transform_drag_rotation_start_vector.signed_angle_to(
						current_vector,
						transform_drag_axis
					)
				else:
					angle = (
						mouse_position.x - transform_drag_start_mouse.x
						- mouse_position.y + transform_drag_start_mouse.y
					) * 0.01
				if snap_button.button_pressed:
					angle = snappedf(angle, deg_to_rad(15.0))
				next_snapshots = _rotated_snapshots(
					transform_drag_start_snapshots,
					transform_drag_axis,
					angle,
					transform_drag_start_pivot
				)
			else:
				var delta_x := mouse_position.x - transform_drag_start_mouse.x
				var next_yaw := start_rotation.y - delta_x * 0.01
				if snap_button.button_pressed:
					next_yaw = snappedf(next_yaw, deg_to_rad(15.0))
				next_snapshots = _rotated_snapshots(
					transform_drag_start_snapshots,
					Vector3.UP,
					next_yaw - start_rotation.y,
					transform_drag_start_pivot
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
			var applied_factor := (
				next_scale.x / maxf(absf(start_scale.x), 0.0001)
			)
			next_snapshots = _uniformly_scaled_snapshots(
				transform_drag_start_snapshots,
				applied_factor,
				transform_drag_start_pivot
			)
	if not next_snapshots.is_empty():
		_apply_placement_snapshots(next_snapshots, false)
	_refresh_inspector()


func _finish_transform_drag() -> void:
	if not transform_dragging:
		return
	transform_dragging = false
	if selected_placement == null or transform_drag_start_snapshots.is_empty():
		_clear_transform_drag_state()
		return
	var next_snapshots := _capture_selected_snapshots()
	if _snapshot_arrays_match(transform_drag_start_snapshots, next_snapshots):
		_clear_transform_drag_state()
		return
	undo_redo.create_action(
		"Transform %d asset%s" % [
			next_snapshots.size(),
			"" if next_snapshots.size() == 1 else "s",
		]
	)
	undo_redo.add_do_method(_apply_placement_snapshots.bind(next_snapshots))
	undo_redo.add_undo_method(
		_apply_placement_snapshots.bind(transform_drag_start_snapshots)
	)
	undo_redo.commit_action(false)
	_clear_transform_drag_state()
	_mark_dirty()


func _clear_transform_drag_state() -> void:
	transform_drag_start_snapshots = []
	transform_drag_axis = Vector3.ZERO
	transform_drag_axis_index = -1
	transform_drag_axis_start_parameter = 0.0
	transform_drag_rotation_start_vector = Vector3.ZERO
	if transform_gizmo != null:
		transform_gizmo.set_hover_axis(-1)
	_refresh_transform_gizmo()


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
	if (
		inspector_refreshing
		or selected_placement == null
		or selected_placements_by_id.is_empty()
	):
		return
	var previous := _capture_selected_snapshots()
	var primary_previous := _snapshot_for_id(
		previous,
		selected_placement.placement_id
	)
	if primary_previous.is_empty():
		return
	var field := (transform_fields[property_name] as Array)[axis_index] as SpinBox
	var component := float(field.value)
	if property_name == &"rotation":
		component = deg_to_rad(component)
	var pivot := _snapshots_pivot(previous)
	var next: Array[Dictionary] = []
	match property_name:
		&"position":
			var delta := Vector3.ZERO
			delta[axis_index] = component - pivot[axis_index]
			next = _translated_snapshots(previous, delta)
		&"rotation":
			var current_rotation := (
				primary_previous.get("rotation", Vector3.ZERO) as Vector3
			)
			var axis: Vector3 = [
				Vector3.RIGHT,
				Vector3.UP,
				Vector3.BACK,
			][axis_index]
			next = _rotated_snapshots(
				previous,
				axis,
				component - current_rotation[axis_index],
				pivot
			)
		&"scale":
			var current_scale := (
				primary_previous.get("scale", Vector3.ONE) as Vector3
			)
			var factor := component / maxf(absf(current_scale[axis_index]), 0.0001)
			next = _axis_scaled_snapshots(previous, axis_index, factor, pivot)
	if next.is_empty():
		return
	var selected_id_labels := PackedStringArray()
	for snapshot: Dictionary in previous:
		selected_id_labels.append(str(int(snapshot.get("id", 0))))
	undo_redo.create_action(
		"Edit %s [%s] on %d asset%s" % [
			property_name,
			",".join(selected_id_labels),
			previous.size(),
			"" if previous.size() == 1 else "s",
		],
		UndoRedo.MERGE_ENDS
	)
	undo_redo.add_do_method(_apply_placement_snapshots.bind(next))
	undo_redo.add_undo_method(_apply_placement_snapshots.bind(previous))
	undo_redo.commit_action()
	_mark_dirty()


func _refresh_inspector() -> void:
	inspector_refreshing = true
	var selection_count := selected_placements_by_id.size()
	var has_selection := selected_placement != null and selection_count > 0
	if selection_count > 1:
		selection_label.text = "%d ASSETS  //  PRIMARY %03d" % [
			selection_count,
			selected_placement.placement_id,
		]
	elif has_selection:
		selection_label.text = "%03d  //  %s\n%s" % [
			selected_placement.placement_id,
			selected_placement.asset_path.get_file().get_basename().to_upper(),
			_placement_role_summary(selected_placement),
		]
	else:
		selection_label.text = "NO PLACEMENT SELECTED"
	for property_name: StringName in transform_fields:
		var vector := Vector3.ZERO
		if has_selection:
			match property_name:
				&"position":
					vector = _snapshots_pivot(_capture_selected_snapshots())
				&"rotation": vector = selected_placement.rotation * (180.0 / PI)
				&"scale": vector = selected_placement.scale
		elif property_name == &"scale":
			vector = Vector3.ONE
		var fields := transform_fields[property_name] as Array
		for axis_index: int in range(3):
			(fields[axis_index] as SpinBox).editable = has_selection
			(fields[axis_index] as SpinBox).value = vector[axis_index]
	inspector_refreshing = false
	_refresh_acoustic_panel()
	_refresh_building_controls()
	_refresh_transform_gizmo()


func _refresh_transform_gizmo() -> void:
	if transform_gizmo == null:
		return
	var mode: StringName = TRANSFORM_GIZMO.MODE_HIDDEN
	if (
		selected_placement != null
		and not selected_placements_by_id.is_empty()
		and not _has_pending_placement()
		and not building_room_tool_active
		and not acoustic_authoring_enabled
		and not speaker_authoring_active
		and not light_placement_active
		and (
			preview_tabs == null
			or preview_tabs.current_tab != light_tab_index
		)
	):
		if edit_mode == MODE_MOVE:
			mode = TRANSFORM_GIZMO.MODE_MOVE
		elif edit_mode == MODE_ROTATE:
			mode = TRANSFORM_GIZMO.MODE_ROTATE
	if mode == TRANSFORM_GIZMO.MODE_HIDDEN:
		transform_gizmo.set_mode(mode)
		return
	transform_gizmo.global_position = _snapshots_pivot(
		_capture_selected_snapshots()
	)
	transform_gizmo.set_mode(mode)
	transform_gizmo.update_screen_scale(
		editor_camera,
		float(editor_viewport.size.y) if editor_viewport != null else 720.0
	)


static func _placement_role_summary(placement: LevelAssetPlacement) -> String:
	if placement.gameplay_role == LevelEditorDocument.PLACEMENT_ROLE_VALUABLE:
		return "VALUABLE  //  %.2f KG  //  %.2f / KG  //  %.2f TOTAL" % [
			placement.item_mass_kg,
			placement.value_per_mass,
			placement.item_mass_kg * placement.value_per_mass,
		]
	if placement.gameplay_role == LevelEditorDocument.PLACEMENT_ROLE_ITEM:
		return "ITEM  //  %.2f KG" % placement.item_mass_kg
	return "STATIC GEOMETRY"


func _duplicate_selected() -> void:
	if selected_placements_by_id.is_empty():
		return
	var snapshots: Array[Dictionary] = []
	var new_ids: Array[int] = []
	var duplicated_group_ids: Dictionary[int, int] = {}
	var offset := float(snap_step.value) if snap_button.button_pressed else 0.5
	for placement: LevelAssetPlacement in _selected_placements():
		var snapshot := placement.snapshot()
		var next_id := document.allocate_placement_id()
		snapshot["id"] = next_id
		snapshot["position"] = (
			(snapshot.get("position") as Vector3)
			+ Vector3(offset, 0.0, offset)
		)
		var source_group_id := int(snapshot.get("assembly_group_id", 0))
		if source_group_id > 0:
			if not duplicated_group_ids.has(source_group_id):
				duplicated_group_ids[source_group_id] = (
					document.allocate_assembly_group_id()
				)
			snapshot["assembly_group_id"] = duplicated_group_ids[source_group_id]
		snapshots.append(snapshot)
		new_ids.append(next_id)
	undo_redo.create_action("Duplicate %d asset%s" % [
		snapshots.size(),
		"" if snapshots.size() == 1 else "s",
	])
	undo_redo.add_do_method(_restore_placements.bind(snapshots))
	undo_redo.add_undo_method(_remove_placements_by_id.bind(new_ids))
	undo_redo.commit_action()
	_select_placement_ids(new_ids)
	_mark_dirty()


func _delete_selected() -> void:
	if selected_placements_by_id.is_empty():
		return
	var snapshots := _capture_selected_snapshots()
	var placement_ids: Array[int] = []
	for snapshot: Dictionary in snapshots:
		placement_ids.append(int(snapshot.get("id", 0)))
	var previous_acoustic := acoustic_state.capture_state()
	acoustic_state.remove_portals_anchored_to(placement_ids)
	var next_acoustic := acoustic_state.capture_state()
	undo_redo.create_action("Delete %d asset%s" % [
		snapshots.size(),
		"" if snapshots.size() == 1 else "s",
	])
	undo_redo.add_do_method(_remove_placements_by_id.bind(placement_ids))
	undo_redo.add_do_method(_restore_acoustic_state.bind(next_acoustic))
	undo_redo.add_undo_method(_restore_placements.bind(snapshots))
	undo_redo.add_undo_method(_restore_acoustic_state.bind(previous_acoustic))
	undo_redo.commit_action()
	_mark_dirty()


func _focus_selected() -> void:
	var selected := _selected_placements()
	if selected.is_empty():
		return
	var bounds := selected[0].global_transform * selected[0].local_bounds
	for index: int in range(1, selected.size()):
		bounds = bounds.merge(
			selected[index].global_transform * selected[index].local_bounds
		)
	camera_pivot = bounds.get_center()
	camera_distance = maxf(bounds.size.length() * 1.35, 1.5)
	_update_camera()


func _set_edit_mode(mode: StringName) -> void:
	if transform_dragging:
		_finish_transform_drag()
	edit_mode = mode
	for candidate: StringName in mode_buttons:
		mode_buttons[candidate].button_pressed = candidate == edit_mode
	_refresh_transform_gizmo()
	_set_status(
		"%s TOOL ACTIVE%s" % [
			str(edit_mode).to_upper(),
			"  //  DRAG X, Y, OR Z HANDLE"
			if edit_mode == MODE_MOVE or edit_mode == MODE_ROTATE
			else "",
		]
	)


func _toggle_snap() -> void:
	_refresh_armed_placement_cursor()
	_set_status(
		"GRID %s  //  %.2f M STEP" % [
			"ENABLED" if snap_button.button_pressed else "DISABLED",
			float(snap_step.value),
		]
	)


func _toggle_surface_alignment() -> void:
	_refresh_armed_placement_cursor()
	_set_status(
		"SURFACE ALIGN %s" % (
			"ENABLED" if surface_align_button.button_pressed else "DISABLED"
		)
	)


func _on_snap_step_changed(_value: float) -> void:
	_refresh_armed_placement_cursor()


func _refresh_armed_placement_cursor() -> void:
	if _has_pending_placement() and has_placement_pointer:
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


func _snap_surface_position(value: Vector3, surface_normal: Vector3) -> Vector3:
	if snap_button == null or snap_step == null or not snap_button.button_pressed:
		return value
	var step_value := maxf(float(snap_step.value), 0.0001)
	var snapped := Vector3(
		snappedf(value.x, step_value),
		snappedf(value.y, step_value),
		snappedf(value.z, step_value)
	)
	var normal := surface_normal.normalized()
	if normal.length_squared() <= 0.000001:
		return snapped
	return snapped - normal * (snapped - value).dot(normal)


func _apply_placement_pose(
	placement: LevelAssetPlacement,
	hit: Dictionary
) -> void:
	var surface_position: Vector3 = hit.get("position", Vector3.ZERO)
	var surface_normal: Vector3 = hit.get("normal", Vector3.UP)
	if surface_normal.length_squared() <= 0.000001:
		surface_normal = Vector3.UP
	surface_normal = surface_normal.normalized()
	placement.rotation = placement_rotation
	if surface_align_button != null and surface_align_button.button_pressed:
		placement.rotation = _basis_aligned_to_surface(
			Basis.from_euler(placement_rotation),
			surface_normal
		).get_euler()
	surface_position = _snap_surface_position(surface_position, surface_normal)
	placement.position = (
		surface_position
		+ surface_normal * (
			placement.surface_support_distance(surface_normal)
			+ SURFACE_CLEARANCE
		)
		)
	_apply_building_socket_snap(placement)


func _apply_assembly_preview_pose(
	preview_node: LevelAssetAssemblyPreview,
	hit: Dictionary
) -> void:
	var surface_position: Vector3 = hit.get("position", Vector3.ZERO)
	var surface_normal: Vector3 = hit.get("normal", Vector3.UP)
	if surface_normal.length_squared() <= 0.000001:
		surface_normal = Vector3.UP
	surface_normal = surface_normal.normalized()
	preview_node.rotation = placement_rotation
	if surface_align_button != null and surface_align_button.button_pressed:
		preview_node.rotation = _basis_aligned_to_surface(
			Basis.from_euler(placement_rotation),
			surface_normal
		).get_euler()
	surface_position = _snap_surface_position(surface_position, surface_normal)
	preview_node.position = (
		surface_position
		+ surface_normal * (
			preview_node.surface_support_distance(surface_normal)
			+ SURFACE_CLEARANCE
		)
	)
func _apply_building_socket_snap(placement: LevelAssetPlacement) -> void:
	if (
		not building_mode_enabled
		or building_socket_snap_button == null
		or not building_socket_snap_button.button_pressed
		or placement == null
	):
		return
	var entry: Dictionary = catalog_entries_by_path.get(placement.asset_path, {})
	var kit_id := str(entry.get("building_kit", ""))
	var socket: StringName = entry.get("building_socket", &"")
	if kit_id.is_empty() or socket.is_empty():
		return
	var preview_anchors := BUILDING_SHELL_GENERATOR.socket_anchors(
		placement.transform,
		placement.local_bounds,
		socket
	)
	if preview_anchors.is_empty():
		return
	var nearest_offset := Vector3.ZERO
	var nearest_distance := INF
	for target: LevelAssetPlacement in placements_by_id.values():
		if target == placement:
			continue
		var target_entry: Dictionary = catalog_entries_by_path.get(target.asset_path, {})
		if (
			str(target_entry.get("building_kit", "")) != kit_id
			or target_entry.get("building_socket", &"") != socket
		):
			continue
		var target_anchors := BUILDING_SHELL_GENERATOR.socket_anchors(
			target.transform,
			target.local_bounds,
			socket
		)
		for preview_anchor: Vector3 in preview_anchors:
			for target_anchor: Vector3 in target_anchors:
				var distance := preview_anchor.distance_to(target_anchor)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_offset = target_anchor - preview_anchor
	var threshold := clampf(
		BUILDING_SHELL_GENERATOR.horizontal_span(placement.local_bounds)
		* maxf(placement.scale.x, placement.scale.z) * 0.4,
		0.22,
		1.75
	)
	if nearest_distance <= threshold:
		placement.position += nearest_offset


static func _basis_aligned_to_surface(
	base: Basis,
	surface_normal: Vector3
) -> Basis:
	var up := surface_normal.normalized()
	if up.length_squared() <= 0.000001:
		return base.orthonormalized()
	var backward := base.z - up * base.z.dot(up)
	if backward.length_squared() <= 0.000001:
		backward = base.x - up * base.x.dot(up)
	if backward.length_squared() <= 0.000001:
		backward = Vector3.FORWARD.cross(up)
		if backward.length_squared() <= 0.000001:
			backward = Vector3.RIGHT
	backward = backward.normalized()
	var right := up.cross(backward).normalized()
	return Basis(right, up, backward).orthonormalized()


func _surface_marker_basis(surface_normal: Vector3) -> Basis:
	var up := surface_normal.normalized()
	if up.length_squared() <= 0.000001:
		return Basis.IDENTITY
	var right := editor_camera.global_basis.x
	right -= up * right.dot(up)
	if right.length_squared() <= 0.000001:
		right = Vector3.FORWARD.cross(up)
		if right.length_squared() <= 0.000001:
			right = Vector3.RIGHT
	right = right.normalized()
	var backward := right.cross(up).normalized()
	return Basis(right, up, backward).orthonormalized()


func _rotate_asset(axis: Vector3, angle_radians: float) -> void:
	var axis_name := "X" if axis == Vector3.RIGHT else ("Z" if axis == Vector3.BACK else "Y")
	if building_room_tool_active:
		if axis != Vector3.UP:
			_set_status("ROOM SHELLS ROTATE AROUND Y ONLY", true)
			return
		placement_rotation.y = wrapf(
			placement_rotation.y + angle_radians,
			-PI,
			PI
		)
		if building_room_dragging:
			_update_room_shell_preview(building_room_corner_b)
		_set_status("ROOM KIT AXES ROTATED  //  %d DEGREES" % int(round(
			rad_to_deg(placement_rotation.y)
		)))
		return
	if _has_pending_placement():
		if axis == Vector3.RIGHT:
			placement_rotation.x = wrapf(placement_rotation.x + angle_radians, -PI, PI)
		elif axis == Vector3.BACK:
			placement_rotation.z = wrapf(placement_rotation.z + angle_radians, -PI, PI)
		else:
			placement_rotation.y = wrapf(placement_rotation.y + angle_radians, -PI, PI)
		if placement_preview != null:
			placement_preview.rotation = placement_rotation
		if assembly_preview != null:
			assembly_preview.rotation = placement_rotation
		_refresh_armed_placement_cursor()
		_set_status(
			"PLACEMENT ROTATION %s  //  %d DEGREES"
			% [axis_name, int(round(rad_to_deg(angle_radians)))]
		)
		return
	if selected_placement == null or selected_placements_by_id.is_empty():
		_set_status("SELECT OR ARM AN ASSET TO ROTATE", true)
		return
	var previous := _capture_selected_snapshots()
	var next := _rotated_snapshots(
		previous,
		axis,
		angle_radians,
		_snapshots_pivot(previous)
	)
	undo_redo.create_action("Rotate %d asset%s %s" % [
		previous.size(),
		"" if previous.size() == 1 else "s",
		axis_name,
	])
	undo_redo.add_do_method(_apply_placement_snapshots.bind(next))
	undo_redo.add_undo_method(_apply_placement_snapshots.bind(previous))
	undo_redo.commit_action()
	_mark_dirty()
	_set_status("ROTATED %d ASSET%s %s  //  %d DEGREES" % [
		previous.size(),
		"" if previous.size() == 1 else "S",
		axis_name,
		int(round(rad_to_deg(angle_radians))),
	])


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
	_refresh_transform_gizmo()


func _screen_to_ground(viewport_position: Vector2) -> Vector3:
	return _screen_to_height(viewport_position, 0.0)


func _screen_to_placement_surface(viewport_position: Vector2) -> Vector3:
	var hit := _screen_to_placement_hit(viewport_position)
	return hit.get("position", Vector3.INF) if not hit.is_empty() else Vector3.INF


func _screen_to_placement_hit(viewport_position: Vector2) -> Dictionary:
	var ray_origin := editor_camera.project_ray_origin(viewport_position)
	var ray_direction := editor_camera.project_ray_normal(viewport_position).normalized()
	if (
		not ray_origin.is_finite()
		or not ray_direction.is_finite()
		or ray_direction.length_squared() <= 0.000001
	):
		return {}
	var ground_position := _screen_to_ground(viewport_position)
	var nearest_distance := (
		(ground_position - ray_origin).dot(ray_direction)
		if ground_position.is_finite()
		else INF
	)
	var nearest_hit := (
		{
			"distance": nearest_distance,
			"position": ground_position,
			"normal": Vector3.UP,
		}
		if ground_position.is_finite()
		else {}
	)
	for placement_id: int in placements_by_id:
		var placement := placements_by_id[placement_id] as LevelAssetPlacement
		var hit := placement.surface_ray_hit(ray_origin, ray_direction)
		if hit.normal.length_squared() <= 0.000001 or not is_finite(hit.d):
			continue
		var hit_distance := hit.d
		if hit_distance < nearest_distance:
			nearest_distance = hit_distance
			nearest_hit = {
				"distance": hit_distance,
				"position": ray_origin + ray_direction * hit_distance,
				"normal": hit.normal,
			}
	return nearest_hit


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
	# A user://levels save becomes the host's active authored level. The server
	# reads only this tiny local pointer; clients receive spawned item descriptors
	# through ordinary authoritative replication.
	RUNTIME_SELECTION.set_active_level(path)
	dirty = false
	_update_window_title()
	_set_status("SAVED  //  %s" % path)


func _load_from_path(path: String) -> void:
	var loaded := LevelEditorDocument.load_from_path(path)
	if loaded == null:
		_set_status("LOAD FAILED  //  INVALID LEVEL FILE", true)
		return
	_cancel_asset_placement()
	if building_room_tool_active:
		_cancel_room_shell_tool()
	_clear_sound_systems()
	_clear_authored_lights()
	_clear_placements()
	document = loaded
	var skipped := 0
	rebuilding_placements = true
	for snapshot: Dictionary in document.placements:
		var placement := _instantiate_placement(
			int(snapshot.get("id", 0)),
			str(snapshot.get("asset_path", ""))
		)
		if placement == null:
			skipped += 1
			continue
		placement.apply_snapshot(snapshot)
	rebuilding_placements = false
	rebuilding_acoustics = true
	acoustic_state.load_state(
		document.acoustic_probes,
		document.acoustic_portals,
		document.next_acoustic_id
	)
	rebuilding_acoustics = false
	_load_sound_system_state(document.sound_systems)
	_load_authored_light_state(document.authored_lights)
	_refresh_used_assets_bar()
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
	if building_room_tool_active:
		_cancel_room_shell_tool()
	_clear_sound_systems()
	_clear_authored_lights()
	_clear_placements()
	document = LevelEditorDocument.new()
	rebuilding_acoustics = true
	acoustic_state.load_state([], [], document.next_acoustic_id)
	rebuilding_acoustics = false
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
	_refresh_used_assets_bar()


func _clear_sound_systems() -> void:
	speaker_authoring_active = false
	speaker_draft_markers.clear()
	sound_systems_by_id.clear()
	speaker_cursor = null
	if speaker_marker_root != null:
		for child: Node in speaker_marker_root.get_children():
			speaker_marker_root.remove_child(child)
			child.free()
	if speaker_authoring_button != null:
		speaker_authoring_button.button_pressed = false
	if speaker_authoring_panel != null:
		speaker_authoring_panel.visible = false
	_refresh_speaker_authoring_status()


func _clear_authored_lights() -> void:
	light_placement_active = false
	selected_light_id = 0
	authored_lights_by_id.clear()
	light_cursor = null
	if light_marker_root != null:
		for child: Node in light_marker_root.get_children():
			light_marker_root.remove_child(child)
			child.free()
	if light_place_button != null:
		light_place_button.button_pressed = false
	_refresh_light_inspector()


func _load_authored_light_state(light_values: Array[Dictionary]) -> void:
	for raw_light: Dictionary in light_values:
		var descriptor: Dictionary = LIGHT_AUTHORING.sanitize_descriptor(raw_light)
		if descriptor.is_empty():
			continue
		var light_id := int(descriptor.get("id", 0))
		if authored_lights_by_id.has(light_id):
			continue
		var marker := LIGHT_MARKER_SCRIPT.new() as Node3D
		marker.name = "AuthoredLight%03d" % light_id
		marker.process_mode = Node.PROCESS_MODE_DISABLED
		if not bool(marker.call("configure", descriptor, false)):
			marker.free()
			continue
		light_marker_root.add_child(marker)
		authored_lights_by_id[light_id] = marker
	_refresh_light_inspector()


func _load_sound_system_state(system_values: Array[Dictionary]) -> void:
	for raw_system: Dictionary in system_values:
		var system := LevelSpeakerSystemAuthoring.sanitize_system(raw_system)
		if system.is_empty():
			continue
		var system_id := int(system.get("id", 0))
		if sound_systems_by_id.has(system_id):
			continue
		sound_systems_by_id[system_id] = system
		for speaker: Dictionary in LevelSpeakerSystemAuthoring.world_speaker_descriptors(system):
			var marker := SPEAKER_MARKER_SCRIPT.new() as LevelSpeakerAuthoringMarker
			marker.name = "PA%03dSpeaker" % system_id
			marker.system_id = system_id
			marker.is_indoor = bool(speaker.get("is_indoor", true))
			marker.installation_gain_db = float(
				speaker.get("installation_gain_db", 0.0)
			)
			marker.cabinet_size = speaker.get(
				"cabinet_size",
				LevelSpeakerSystemAuthoring.DEFAULT_CABINET_SIZE
			)
			marker.position = speaker.get("position", Vector3.ZERO)
			marker.rotation = speaker.get("rotation", Vector3.ZERO)
			marker.process_mode = Node.PROCESS_MODE_DISABLED
			marker.configure_editor_marker(true)
			speaker_marker_root.add_child(marker)


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
	var acoustic_snapshot := acoustic_state.capture_state()
	document.acoustic_probes = (
		acoustic_snapshot.get("probes", []) as Array[Dictionary]
	).duplicate(true)
	document.acoustic_portals = (
		acoustic_snapshot.get("portals", []) as Array[Dictionary]
	).duplicate(true)
	document.next_acoustic_id = int(acoustic_snapshot.get("next_id", 1))
	document.sound_systems.clear()
	var sound_system_ids: Array[int] = []
	for system_id: int in sound_systems_by_id:
		sound_system_ids.append(system_id)
	sound_system_ids.sort()
	for system_id: int in sound_system_ids:
		document.sound_systems.append(
			(sound_systems_by_id[system_id] as Dictionary).duplicate(true)
		)
	document.authored_lights.clear()
	var light_ids: Array[int] = []
	for light_id: int in authored_lights_by_id:
		light_ids.append(light_id)
	light_ids.sort()
	for light_id: int in light_ids:
		document.authored_lights.append(
			authored_lights_by_id[light_id].call("descriptor")
		)


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
	if key.physical_keycode == KEY_ESCAPE and (
		_has_pending_placement()
		or speaker_authoring_active
		or building_room_tool_active
		or light_placement_active
	):
		if speaker_authoring_active:
			_cancel_speaker_system_authoring()
		elif light_placement_active:
			_cancel_light_placement()
		elif building_room_tool_active:
			_cancel_room_shell_tool()
		else:
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
	elif key.ctrl_pressed and key.physical_keycode == KEY_A:
		_select_all_placements()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_DELETE:
		if (
			acoustic_authoring_enabled
			and acoustic_state != null
			and (
				acoustic_state.selected_portal_id > 0
				or not acoustic_state.selected_probe_ids.is_empty()
			)
		):
			_delete_acoustic_selection()
		elif (
			preview_tabs != null
			and preview_tabs.current_tab == light_tab_index
			and selected_light_id > 0
		):
			_delete_selected_light()
		else:
			_delete_selected()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_F:
		_focus_selected()
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_R:
		_rotate_asset(
			Vector3.UP,
			-FINE_ROTATION_RADIANS if key.alt_pressed and key.shift_pressed
			else (FINE_ROTATION_RADIANS if key.shift_pressed else QUARTER_TURN_RADIANS)
		)
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_X:
		_rotate_asset(
			Vector3.RIGHT,
			-FINE_ROTATION_RADIANS if key.alt_pressed and key.shift_pressed
			else (FINE_ROTATION_RADIANS if key.shift_pressed else QUARTER_TURN_RADIANS)
		)
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_Z:
		_rotate_asset(
			Vector3.BACK,
			-FINE_ROTATION_RADIANS if key.alt_pressed and key.shift_pressed
			else (FINE_ROTATION_RADIANS if key.shift_pressed else QUARTER_TURN_RADIANS)
		)
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
