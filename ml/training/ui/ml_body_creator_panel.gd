class_name MLBodyCreatorPanel
extends Window

signal create_requested(request: Dictionary)

const ORANGE: Color = Color("ffad42")
const GREEN: Color = Color("54e6b1")
const MUTED: Color = Color("a8d8c1")
const EMPTY_KEY: String = "__empty__"
const CURRENT_KEY_PREFIX: String = "__current__:"
const SAME_AS_KEY_PREFIX: String = "__same_as__:"
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(1120, 860)
const WINDOW_EDGE_MARGIN_PX: int = 36
const STAGE_CORE_LAYOUT: int = 0
const STAGE_HARDWARE: int = 1
const MINIMUM_SLOT_SPACING_M: float = 0.075
const CREATOR_SCROLL_STEP_PX: int = 72
const CORE_MOUNT_OFFSET_M: float = 0.10
const CORE_FACE_SCALE_STEP: float = 1.10

var root_panel: PanelContainer
var window_layout: VBoxContainer
var content_scroll: ScrollContainer
var root_content: VBoxContainer
var footer_panel: PanelContainer
var stage_label: Label
var layout_stage: VBoxContainer
var hardware_stage: VBoxContainer
var core_row: HBoxContainer
var layout_preview: MLBodyCoreLayoutPreview
var layout_slot_count_label: Label
var layout_selected_label: Label
var layout_slot_kind_picker: OptionButton
var core_face_edit_toggle: CheckBox
var core_width_input: SpinBox
var core_height_input: SpinBox
var core_depth_input: SpinBox
var core_face_label: Label
var core_face_shrink_button: Button
var core_face_expand_button: Button
var core_forward_button: Button
var core_up_button: Button
var core_orientation_reset_button: Button
var mirror_next_checkbox: CheckBox
var back_button: Button
var cancel_button: Button
var core_picker: OptionButton
var group_name_input: LineEdit
var description_label: Label
var core_label: Label
var slots_content: VBoxContainer
var summary_label: Label
var status_label: Label
var create_button: Button
var training_settings_panel: PanelContainer
var training_options_button: Button
var algorithm_picker: OptionButton
var hidden_width_input: SpinBox
var hidden_depth_input: SpinBox
var worker_count_input: SpinBox
var control_rate_input: SpinBox
var exploration_input: SpinBox
var reward_cardset_picker: OptionButton
var start_training_checkbox: CheckBox

var current_preset_id: StringName = &""
var current_draft: MLBodyBuildDraft
var current_body_kind: String = ""
var slot_pickers: Dictionary = {}
var slot_parts: Dictionary = {}
var slot_editor_hosts: Dictionary = {}
var limb_shape_editors: Dictionary = {}
var limb_segment_pickers: Dictionary = {}
var limb_dimension_labels: Dictionary = {}
var limb_mass_inputs: Dictionary = {}
var limb_selected_segments: Dictionary = {}
var expanded_limb_editor_slots: Dictionary = {}
var initial_slot_keys: Dictionary = {}
var changed_slot_ids: Dictionary = {}
var core_parts: Dictionary = {}
var core_preset_ids: Dictionary = {}
var reward_cardsets: Dictionary = {}
var reward_cardset_library: TrainingRewardCardsetLibrary = TrainingRewardCardsetLibrary.new()
var suppress_training_ui_callbacks: bool = false
var creator_stage: int = STAGE_CORE_LAYOUT
var layout_slot_capacity: int = 0
var layout_slot_transforms: Array[Transform3D] = []
var layout_slot_kinds: Array[StringName] = []
var layout_slot_surface_normals: Array[Vector3] = []
var layout_selected_slot_index: int = -1
var layout_selected_face_index: int = -1
var suppress_core_geometry_callbacks: bool = false
var suppress_limb_inspector_callbacks: bool = false


func _ready() -> void:
	title = "Model Body Creator"
	size = DEFAULT_WINDOW_SIZE
	min_size = Vector2i(680, 560)
	unresizable = false
	transient = true
	exclusive = false
	close_requested.connect(hide)
	_build_ui()
	_populate_core_picker()
	if core_picker.item_count > 0 and not core_picker.disabled:
		var preferred_index: int = _preferred_initial_core_index()
		core_picker.select(preferred_index)
		_on_core_selected(preferred_index)
	hide()


func _input(event: InputEvent) -> void:
	# A single Window-level wheel route keeps scrolling reliable over form controls. Ctrl+wheel over
	# either embedded 3D editor remains reserved for its camera.
	if not visible or content_scroll == null or not (event is InputEventMouseButton):
		return
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_button.pressed or mouse_button.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if mouse_button.ctrl_pressed and _point_is_over_3d_editor(mouse_button.position):
		return
	var direction: int = -1 if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP else 1
	content_scroll.scroll_vertical += direction * CREATOR_SCROLL_STEP_PX
	set_input_as_handled()


func _point_is_over_3d_editor(window_position: Vector2) -> bool:
	if (
		creator_stage == STAGE_CORE_LAYOUT
		and layout_preview != null
		and layout_preview.get_global_rect().has_point(window_position)
	):
		return true
	for editor_value: Variant in limb_shape_editors.values():
		var editor: MLLimbShapeEditor3D = editor_value as MLLimbShapeEditor3D
		if editor != null and editor.is_visible_in_tree() and editor.get_global_rect().has_point(window_position):
			return true
	return false


func open_creator() -> void:
	if core_picker == null:
		return
	if current_draft == null:
		if core_picker.item_count <= 0:
			_populate_core_picker()
		if core_picker.item_count > 0:
			var selected_index: int = maxi(core_picker.selected, 0)
			core_picker.select(selected_index)
			_on_core_selected(selected_index)
	_set_creator_stage(STAGE_CORE_LAYOUT)
	_show_creator_window()


func open_custom_creator() -> void:
	# The chooser's custom route is explicit. Do not let a previously cancelled preset silently
	# become the starting point for what the user asked to build from scratch.
	current_draft = null
	open_creator()


func open_preset(preset_id: StringName) -> bool:
	var preset: MLBodyPreset = MLBodyPresetLibrary.preset_by_id(preset_id)
	var next_draft: MLBodyBuildDraft = (
		preset.instantiate_draft() if preset != null else null
	)
	if (
		preset == null
		or next_draft == null
		or next_draft.core == null
		or not next_draft.last_error.is_empty()
	):
		if status_label != null:
			_set_error("That worker preset could not be loaded.")
		return false
	current_preset_id = preset_id
	current_draft = next_draft
	current_body_kind = str(next_draft.core_contract.get("body_kind", preset.body_kind))
	changed_slot_ids.clear()
	initial_slot_keys.clear()
	slot_parts.clear()
	_select_core_picker_for_preset(preset_id)
	group_name_input.text = "%s group" % preset.display_name
	description_label.text = preset.description
	core_picker.tooltip_text = preset.description
	core_label.text = "Core: %s" % MLBodyPartCatalog.display_name(_current_physical_core())
	_initialize_layout_for_current_core()
	_load_layout_from_current_preset()
	_rebuild_slot_rows()
	_refresh_training_settings_for_body(true)
	status_label.text = "%s loaded. Adjust hardware or training options, then create the group." % preset.display_name
	status_label.add_theme_color_override("font_color", MUTED)
	_set_creator_stage(STAGE_HARDWARE)
	_show_creator_window()
	return true


func _show_creator_window() -> void:
	_prepare_creator_window_size()
	if content_scroll != null:
		content_scroll.scroll_vertical = 0
	popup_centered()
	call_deferred("_fit_creator_window_to_content")


func _creator_viewport_size() -> Vector2i:
	var parent_node: Node = get_parent()
	var parent_viewport: Viewport = (
		parent_node.get_viewport() if parent_node != null else get_tree().root
	)
	return Vector2i(parent_viewport.get_visible_rect().size)


func _desired_creator_window_size() -> Vector2i:
	var viewport_size: Vector2i = _creator_viewport_size()
	var available_width: int = maxi(viewport_size.x - WINDOW_EDGE_MARGIN_PX, 480)
	var available_height: int = maxi(viewport_size.y - WINDOW_EDGE_MARGIN_PX, 420)
	return Vector2i(
		mini(DEFAULT_WINDOW_SIZE.x, available_width),
		mini(DEFAULT_WINDOW_SIZE.y, available_height)
	)


func _prepare_creator_window_size() -> void:
	size = _desired_creator_window_size()


func _fit_creator_window_to_content() -> void:
	if not visible:
		return
	var viewport_size: Vector2i = _creator_viewport_size()
	var desired_size: Vector2i = _desired_creator_window_size()
	size = desired_size
	position = Vector2i(
		maxi((viewport_size.x - desired_size.x) / 2, 0),
		maxi((viewport_size.y - desired_size.y) / 2, 0)
	)


func _refresh_creator_window_after_layout() -> void:
	if visible:
		_fit_creator_window_to_content()


func _focus_group_name() -> void:
	if not visible or creator_stage != STAGE_HARDWARE or group_name_input == null:
		return
	group_name_input.grab_focus()
	group_name_input.select_all()


func _build_ui() -> void:
	root_panel = PanelContainer.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(false)
	)
	add_child(root_panel)

	window_layout = VBoxContainer.new()
	window_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	window_layout.add_theme_constant_override("separation", 8)
	root_panel.add_child(window_layout)

	content_scroll = ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.follow_focus = true
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	window_layout.add_child(content_scroll)

	root_content = VBoxContainer.new()
	root_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root_content.add_theme_constant_override("separation", 10)
	content_scroll.add_child(root_content)
	var root: VBoxContainer = root_content

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	var heading: Label = Label.new()
	heading.text = "MODEL BODY CREATOR"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", ORANGE)
	heading.tooltip_text = "Build a physical worker body from the same serialized parts used by gameplay and training."
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)

	stage_label = Label.new()
	stage_label.add_theme_font_size_override("font_size", 16)
	stage_label.add_theme_color_override("font_color", GREEN)
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage_label.tooltip_text = "Body layout comes first so every hardware slot has a physical mount transform."
	header.add_child(stage_label)

	layout_stage = VBoxContainer.new()
	layout_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_stage.add_theme_constant_override("separation", 10)
	root.add_child(layout_stage)

	var identity_panel: PanelContainer = PanelContainer.new()
	identity_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	layout_stage.add_child(identity_panel)
	var identity: VBoxContainer = VBoxContainer.new()
	identity.add_theme_constant_override("separation", 7)
	identity_panel.add_child(identity)

	# The selected physical Core is the only body-entry selector. Runtime adapters are inferred
	# internally from the Core resource; there is deliberately no separate body-family state.

	core_row = HBoxContainer.new()
	core_row.add_theme_constant_override("separation", 8)
	identity.add_child(core_row)
	var physical_core_label: Label = Label.new()
	physical_core_label.text = "Physical Core"
	physical_core_label.custom_minimum_size.x = 120.0
	core_row.add_child(physical_core_label)
	core_picker = OptionButton.new()
	core_picker.fit_to_longest_item = false
	core_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	core_picker.tooltip_text = "The physical chassis determines the runtime adapter and compatible hardware slots."
	core_picker.item_selected.connect(_on_core_selected)
	core_row.add_child(core_picker)

	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_color_override("font_color", MUTED)
	description_label.visible = false
	identity.add_child(description_label)
	core_label = Label.new()
	core_label.add_theme_color_override("font_color", GREEN)
	core_label.visible = false
	identity.add_child(core_label)

	var preview_heading: Label = Label.new()
	preview_heading.text = "CORE LAYOUT"
	preview_heading.add_theme_font_size_override("font_size", 17)
	preview_heading.add_theme_color_override("font_color", ORANGE)
	layout_stage.add_child(preview_heading)

	var preview_panel: PanelContainer = PanelContainer.new()
	preview_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_stage.add_child(preview_panel)
	var preview_body: VBoxContainer = VBoxContainer.new()
	preview_body.add_theme_constant_override("separation", 7)
	preview_panel.add_child(preview_body)

	var dimensions_row: HBoxContainer = HBoxContainer.new()
	dimensions_row.add_theme_constant_override("separation", 7)
	preview_body.add_child(dimensions_row)
	var dimensions_label: Label = Label.new()
	dimensions_label.text = "Core dimensions"
	dimensions_label.custom_minimum_size.x = 120.0
	dimensions_row.add_child(dimensions_label)
	core_width_input = _core_dimension_input("X", 0.65)
	core_height_input = _core_dimension_input("Y", 0.24)
	core_depth_input = _core_dimension_input("Z", 0.65)
	dimensions_row.add_child(core_width_input.get_parent())
	dimensions_row.add_child(core_height_input.get_parent())
	dimensions_row.add_child(core_depth_input.get_parent())
	for dimension_input: SpinBox in [core_width_input, core_height_input, core_depth_input]:
		dimension_input.value_changed.connect(_on_core_dimensions_changed)

	var geometry_tools: HBoxContainer = HBoxContainer.new()
	geometry_tools.add_theme_constant_override("separation", 7)
	preview_body.add_child(geometry_tools)
	core_face_edit_toggle = CheckBox.new()
	core_face_edit_toggle.text = "Edit Core faces"
	core_face_edit_toggle.tooltip_text = "When enabled, left-click selects a Core face instead of placing a mount."
	core_face_edit_toggle.toggled.connect(_on_core_face_edit_toggled)
	geometry_tools.add_child(core_face_edit_toggle)
	core_face_shrink_button = _creator_button("SHRINK FACE", false)
	core_face_shrink_button.tooltip_text = "Scale the selected face inward around its center by 10%."
	core_face_shrink_button.pressed.connect(_shrink_selected_core_face)
	geometry_tools.add_child(core_face_shrink_button)
	core_face_expand_button = _creator_button("EXPAND FACE", false)
	core_face_expand_button.tooltip_text = "Scale the selected face outward around its center by 10%."
	core_face_expand_button.pressed.connect(_expand_selected_core_face)
	geometry_tools.add_child(core_face_expand_button)
	core_face_label = Label.new()
	core_face_label.text = "No Core face selected."
	core_face_label.add_theme_color_override("font_color", MUTED)
	geometry_tools.add_child(core_face_label)

	var orientation_tools: HBoxContainer = HBoxContainer.new()
	orientation_tools.add_theme_constant_override("separation", 7)
	preview_body.add_child(orientation_tools)
	var orientation_label: Label = Label.new()
	orientation_label.text = "Worker axes"
	orientation_label.custom_minimum_size.x = 120.0
	orientation_label.tooltip_text = "Forward and up define the worker-relative frame seen by its model."
	orientation_tools.add_child(orientation_label)
	core_forward_button = _creator_button("SET FORWARD", false)
	core_forward_button.toggle_mode = true
	core_forward_button.tooltip_text = "Then click a Core face. Its outward normal becomes model forward."
	core_forward_button.pressed.connect(
		_on_core_orientation_button_pressed.bind(MLBodyCoreLayoutPreview.ORIENTATION_EDIT_FORWARD)
	)
	orientation_tools.add_child(core_forward_button)
	core_up_button = _creator_button("SET UP", false)
	core_up_button.toggle_mode = true
	core_up_button.tooltip_text = "Then click a Core face. Its outward normal becomes model up."
	core_up_button.pressed.connect(
		_on_core_orientation_button_pressed.bind(MLBodyCoreLayoutPreview.ORIENTATION_EDIT_UP)
	)
	orientation_tools.add_child(core_up_button)
	core_orientation_reset_button = _creator_button("RESET AXES", false)
	core_orientation_reset_button.tooltip_text = "Restore conventional forward -Z and up +Y."
	core_orientation_reset_button.pressed.connect(_reset_core_orientation)
	orientation_tools.add_child(core_orientation_reset_button)

	layout_preview = MLBodyCoreLayoutPreview.new()
	layout_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_preview.surface_clicked.connect(_on_layout_surface_clicked)
	layout_preview.slot_selected.connect(_on_layout_slot_selected)
	layout_preview.slot_remove_requested.connect(_on_layout_slot_remove_requested)
	layout_preview.face_selected.connect(_on_layout_face_selected)
	layout_preview.orientation_direction_clicked.connect(_on_core_orientation_direction_clicked)
	preview_body.add_child(layout_preview)

	var preview_hint: Label = Label.new()
	preview_hint.text = "LMB place/select   ·   RMB delete   ·   MMB orbit   ·   Ctrl+wheel zoom"
	preview_hint.tooltip_text = "Choose a mount kind, then left-click the Core. Enable face editing to select and reshape a face instead. Right-click removes a mount marker."
	preview_hint.add_theme_color_override("font_color", MUTED)
	preview_body.add_child(preview_hint)

	var slot_kind_row: HBoxContainer = HBoxContainer.new()
	slot_kind_row.add_theme_constant_override("separation", 8)
	preview_body.add_child(slot_kind_row)
	var slot_kind_label: Label = Label.new()
	slot_kind_label.text = "New mount kind"
	slot_kind_label.custom_minimum_size.x = 120.0
	slot_kind_row.add_child(slot_kind_label)
	layout_slot_kind_picker = OptionButton.new()
	layout_slot_kind_picker.fit_to_longest_item = false
	layout_slot_kind_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_slot_kind_picker.add_item("Propeller")
	layout_slot_kind_picker.set_item_metadata(0, "propeller")
	layout_slot_kind_picker.add_item("Attachment")
	layout_slot_kind_picker.set_item_metadata(1, "attachment")
	layout_slot_kind_picker.tooltip_text = "Propeller clicks place the hub on that face and align thrust with the green worker-up arrow. Attachment clicks keep the clicked face orientation."
	layout_slot_kind_picker.item_selected.connect(_on_layout_slot_kind_selected)
	slot_kind_row.add_child(layout_slot_kind_picker)
	# Keep the choice above the 3D viewport so the mount type is explicit before the user clicks.
	preview_body.move_child(slot_kind_row, 0)

	var slot_controls: HBoxContainer = HBoxContainer.new()
	slot_controls.add_theme_constant_override("separation", 7)
	preview_body.add_child(slot_controls)
	var mirror_selected: Button = _creator_button("MIRROR SELECTED", false)
	mirror_selected.tooltip_text = "Duplicate the selected mount across the Core's local X axis."
	mirror_selected.pressed.connect(_mirror_selected_layout_slot)
	slot_controls.add_child(mirror_selected)
	var delete_selected: Button = _creator_button("DELETE SELECTED", false)
	delete_selected.tooltip_text = "Remove the selected mount. You can also right-click its marker."
	delete_selected.pressed.connect(_delete_selected_layout_slot)
	slot_controls.add_child(delete_selected)
	var reset_view_button: Button = _creator_button("RESET VIEW", false)
	reset_view_button.tooltip_text = "Frame the Core and restore the default camera angle."
	reset_view_button.pressed.connect(func() -> void:
		if layout_preview != null:
			layout_preview.reset_view()
	)
	slot_controls.add_child(reset_view_button)
	mirror_next_checkbox = CheckBox.new()
	mirror_next_checkbox.text = "Mirror next placement"
	mirror_next_checkbox.tooltip_text = "Places a second slot mirrored across the Core's local X axis when the selected mount kind allows it."
	slot_controls.add_child(mirror_next_checkbox)

	layout_slot_count_label = Label.new()
	layout_slot_count_label.add_theme_color_override("font_color", GREEN)
	preview_body.add_child(layout_slot_count_label)
	layout_selected_label = Label.new()
	layout_selected_label.add_theme_color_override("font_color", MUTED)
	preview_body.add_child(layout_selected_label)

	hardware_stage = VBoxContainer.new()
	hardware_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hardware_stage.add_theme_constant_override("separation", 10)
	root.add_child(hardware_stage)

	var hardware_identity_panel: PanelContainer = PanelContainer.new()
	hardware_identity_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	hardware_stage.add_child(hardware_identity_panel)
	var hardware_identity: VBoxContainer = VBoxContainer.new()
	hardware_identity.add_theme_constant_override("separation", 7)
	hardware_identity_panel.add_child(hardware_identity)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	hardware_identity.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = "Group name"
	name_label.custom_minimum_size.x = 120.0
	name_row.add_child(name_label)
	group_name_input = LineEdit.new()
	group_name_input.max_length = 48
	group_name_input.placeholder_text = "Worker group name"
	group_name_input.tooltip_text = "Display name for this independently trained worker group."
	group_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(group_name_input)

	var parts_heading: Label = Label.new()
	parts_heading.text = "HARDWARE"
	parts_heading.add_theme_font_size_override("font_size", 17)
	parts_heading.add_theme_color_override("font_color", ORANGE)
	parts_heading.tooltip_text = "Every mount from the Core layout appears here. Choose a compatible saved part for each required slot."
	hardware_stage.add_child(parts_heading)
	var parts_note: Label = Label.new()
	parts_note.text = "Choose a part for each mount. Select articulated hardware to shape it in 3D."
	parts_note.tooltip_text = "The accepted Core layout is fixed during this step. Return to Core layout to add, move, or remove mounts."
	parts_note.add_theme_color_override("font_color", MUTED)
	hardware_stage.add_child(parts_note)

	slots_content = VBoxContainer.new()
	slots_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	slots_content.add_theme_constant_override("separation", 7)
	hardware_stage.add_child(slots_content)

	_build_training_settings(hardware_stage)

	footer_panel = PanelContainer.new()
	footer_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	footer_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window_layout.add_child(footer_panel)
	var footer: VBoxContainer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	footer_panel.add_child(footer)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_color_override("font_color", GREEN)
	footer.add_child(summary_label)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", MUTED)
	footer.add_child(status_label)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	footer.add_child(actions)
	cancel_button = _creator_button("CANCEL", false)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(hide)
	actions.add_child(cancel_button)
	back_button = _creator_button("BACK TO CORE", false)
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(_back_to_core_layout)
	actions.add_child(back_button)
	create_button = _creator_button("ACCEPT CORE LAYOUT", true)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(_on_creator_primary_action)
	actions.add_child(create_button)

	_set_creator_stage(STAGE_CORE_LAYOUT)


func _set_creator_stage(stage: int) -> void:
	creator_stage = STAGE_HARDWARE if stage == STAGE_HARDWARE else STAGE_CORE_LAYOUT
	if layout_stage != null:
		layout_stage.visible = creator_stage == STAGE_CORE_LAYOUT
	if hardware_stage != null:
		hardware_stage.visible = creator_stage == STAGE_HARDWARE
	if stage_label != null:
		stage_label.text = (
			"2 / 2  ·  PARTS"
			if creator_stage == STAGE_HARDWARE
			else "1 / 2  ·  CORE"
		)
	if back_button != null:
		back_button.visible = creator_stage == STAGE_HARDWARE and current_body_kind == "drone"
	if create_button != null:
		create_button.text = (
			"CREATE WORKER GROUP"
			if creator_stage == STAGE_HARDWARE
			else "ACCEPT CORE LAYOUT"
		)
	if content_scroll != null:
		content_scroll.scroll_vertical = 0
	_refresh_summary()
	if creator_stage == STAGE_HARDWARE:
		call_deferred("_focus_group_name")


func _on_creator_primary_action() -> void:
	if creator_stage == STAGE_CORE_LAYOUT:
		_accept_core_layout()
	else:
		_accept_current_build()


func _back_to_core_layout() -> void:
	if creator_stage != STAGE_HARDWARE:
		return
	status_label.text = "Core layout editing reopened. Compatible equipped hardware will stay on matching mounts."
	status_label.add_theme_color_override("font_color", MUTED)
	_set_creator_stage(STAGE_CORE_LAYOUT)
	_refresh_layout_preview()


func _initialize_layout_for_current_core() -> void:
	layout_slot_transforms.clear()
	layout_slot_kinds.clear()
	layout_slot_surface_normals.clear()
	layout_selected_slot_index = -1
	layout_selected_face_index = -1
	layout_slot_capacity = 0
	var physical_core: Resource = _current_physical_core()
	if physical_core is DroneCoreDefinition:
		var drone_core: DroneCoreDefinition = physical_core as DroneCoreDefinition
		# Creator-authored mounts are intentionally unbounded. The Core's saved slot counts describe
		# a stock/default layout, not a physical ceiling. The runtime materializes the accepted
		# propeller and attachment topology when the worker is spawned.
		layout_slot_capacity = -1
		drone_core.ensure_editable_mesh()
	if layout_slot_kind_picker != null:
		layout_slot_kind_picker.disabled = current_body_kind != "drone"
		if layout_slot_kind_picker.item_count > 0 and layout_slot_kind_picker.selected < 0:
			layout_slot_kind_picker.select(0)
	if core_face_edit_toggle != null:
		suppress_core_geometry_callbacks = true
		core_face_edit_toggle.button_pressed = false
		suppress_core_geometry_callbacks = false
	_sync_core_geometry_controls()
	if layout_preview != null:
		layout_preview.set_core_resource(physical_core)
		layout_preview.placement_enabled = current_body_kind == "drone"
		layout_preview.set_face_edit_enabled(false)
		layout_preview.set_orientation_edit_axis(MLBodyCoreLayoutPreview.ORIENTATION_EDIT_NONE)
	_sync_core_orientation_controls()
	_refresh_layout_preview()


func _select_core_picker_for_preset(preset_id: StringName) -> void:
	if core_picker == null:
		return
	for index: int in range(core_picker.item_count):
		var key: String = str(core_picker.get_item_metadata(index))
		if str(core_preset_ids.get(key, "")) == str(preset_id):
			core_picker.select(index)
			return


func _load_layout_from_current_preset() -> void:
	if current_draft == null or current_body_kind != "drone":
		return
	for entry: Dictionary in current_draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null or str(slot.slot_type) not in ["propeller", "attachment"]:
			continue
		var kind: StringName = slot.slot_type
		layout_slot_transforms.append(slot.mount_transform)
		layout_slot_kinds.append(kind)
		layout_slot_surface_normals.append(
			_preset_mount_surface_normal(slot.mount_transform, kind)
		)
	_refresh_layout_preview()


func _preset_mount_surface_normal(mount: Transform3D, kind: StringName) -> Vector3:
	var radial: Vector3 = mount.origin.normalized()
	if radial.length_squared() <= 0.000001:
		radial = (
			mount.basis.y.normalized()
			if kind == &"propeller"
			else -mount.basis.y.normalized()
		)
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	if (
		drone_core != null
		and drone_core.editable_mesh != null
		and drone_core.editable_mesh.has_geometry()
	):
		var hit: Dictionary = drone_core.editable_mesh.ray_hit(Vector3.ZERO, radial)
		if not hit.is_empty():
			var hit_normal: Vector3 = hit.get("normal", radial).normalized()
			if hit_normal.length_squared() > 0.000001:
				return hit_normal
	return radial if radial.length_squared() > 0.000001 else Vector3.UP


func _core_dimension_input(axis_label: String, initial_value: float) -> SpinBox:
	var group: HBoxContainer = HBoxContainer.new()
	group.add_theme_constant_override("separation", 4)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = axis_label
	label.add_theme_color_override("font_color", MUTED)
	group.add_child(label)
	var input: SpinBox = SpinBox.new()
	input.min_value = 0.10
	input.max_value = 20.0
	input.step = 0.05
	input.allow_lesser = false
	input.allow_greater = true
	input.value = initial_value
	input.custom_minimum_size.x = 92.0
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(input)
	return input


func _sync_core_geometry_controls() -> void:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	var supported: bool = current_body_kind == "drone" and drone_core != null
	suppress_core_geometry_callbacks = true
	for input: SpinBox in [core_width_input, core_height_input, core_depth_input]:
		if input != null:
			input.editable = supported
	if core_face_edit_toggle != null:
		core_face_edit_toggle.disabled = not supported
	if supported:
		drone_core.ensure_editable_mesh()
		core_width_input.value = drone_core.body_size.x
		core_height_input.value = drone_core.body_size.y
		core_depth_input.value = drone_core.body_size.z
	suppress_core_geometry_callbacks = false
	_refresh_core_face_controls()
	_sync_core_orientation_controls()


func _sync_core_orientation_controls() -> void:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	var supported: bool = current_body_kind == "drone" and drone_core != null
	for button: Button in [core_forward_button, core_up_button, core_orientation_reset_button]:
		if button != null:
			button.disabled = not supported
	if layout_preview != null and supported:
		var orientation: Basis = drone_core.model_orientation_basis_local()
		layout_preview.set_model_orientation(-orientation.z, orientation.y)


func _on_core_orientation_button_pressed(axis: int) -> void:
	var selected_button: Button = (
		core_forward_button
		if axis == MLBodyCoreLayoutPreview.ORIENTATION_EDIT_FORWARD
		else core_up_button
	)
	var next_axis: int = axis if selected_button != null and selected_button.button_pressed else MLBodyCoreLayoutPreview.ORIENTATION_EDIT_NONE
	if core_forward_button != null:
		core_forward_button.button_pressed = next_axis == MLBodyCoreLayoutPreview.ORIENTATION_EDIT_FORWARD
	if core_up_button != null:
		core_up_button.button_pressed = next_axis == MLBodyCoreLayoutPreview.ORIENTATION_EDIT_UP
	if next_axis != MLBodyCoreLayoutPreview.ORIENTATION_EDIT_NONE and core_face_edit_toggle != null:
		suppress_core_geometry_callbacks = true
		core_face_edit_toggle.button_pressed = false
		suppress_core_geometry_callbacks = false
		layout_selected_face_index = -1
	if layout_preview != null:
		layout_preview.set_face_edit_enabled(false)
		layout_preview.set_orientation_edit_axis(next_axis)
	status_label.text = (
		"Click a Core face to set worker %s."
		% ("forward" if next_axis == MLBodyCoreLayoutPreview.ORIENTATION_EDIT_FORWARD else "up")
		if next_axis != MLBodyCoreLayoutPreview.ORIENTATION_EDIT_NONE
		else "Worker-axis picking cancelled."
	)
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_core_face_controls()


func _on_core_orientation_direction_clicked(direction_local: Vector3) -> void:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	if drone_core == null or layout_preview == null:
		return
	var edit_axis: int = layout_preview.orientation_edit_axis
	var accepted: bool = (
		drone_core.set_model_forward(direction_local)
		if edit_axis == MLBodyCoreLayoutPreview.ORIENTATION_EDIT_FORWARD
		else drone_core.set_model_up(direction_local)
	)
	if not accepted:
		_set_error("That face cannot define a stable worker axis.")
		return
	var changed_name: String = "forward" if edit_axis == MLBodyCoreLayoutPreview.ORIENTATION_EDIT_FORWARD else "up"
	_clear_core_orientation_pick()
	_realign_creator_propellers_to_worker_up()
	_sync_core_orientation_controls()
	status_label.text = "Worker %s now follows the selected face." % changed_name
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_summary()


func _reset_core_orientation() -> void:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	if drone_core == null:
		return
	drone_core.reset_model_orientation()
	_clear_core_orientation_pick()
	_realign_creator_propellers_to_worker_up()
	_sync_core_orientation_controls()
	status_label.text = "Worker axes reset to forward -Z and up +Y."
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_summary()


func _clear_core_orientation_pick() -> void:
	if core_forward_button != null:
		core_forward_button.button_pressed = false
	if core_up_button != null:
		core_up_button.button_pressed = false
	if layout_preview != null:
		layout_preview.set_orientation_edit_axis(MLBodyCoreLayoutPreview.ORIENTATION_EDIT_NONE)


func _refresh_core_face_controls() -> void:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	var edit_enabled: bool = (
		current_body_kind == "drone"
		and drone_core != null
		and core_face_edit_toggle != null
		and core_face_edit_toggle.button_pressed
	)
	var face_valid: bool = (
		edit_enabled
		and drone_core.editable_mesh != null
		and layout_selected_face_index >= 0
		and layout_selected_face_index < drone_core.editable_mesh.face_count()
	)
	if core_face_shrink_button != null:
		core_face_shrink_button.disabled = not face_valid
	if core_face_expand_button != null:
		core_face_expand_button.disabled = not face_valid
	if core_face_label != null:
		core_face_label.text = (
			"Selected face %d" % (layout_selected_face_index + 1)
			if face_valid
			else "Select a Core face." if edit_enabled else "Face editing off."
		)


func _on_core_face_edit_toggled(enabled: bool) -> void:
	if suppress_core_geometry_callbacks:
		return
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	if current_body_kind != "drone" or drone_core == null:
		return
	layout_selected_face_index = -1
	layout_selected_slot_index = -1
	if enabled:
		_clear_core_orientation_pick()
	if layout_preview != null:
		layout_preview.set_face_edit_enabled(enabled)
		layout_preview.set_selected_face(-1)
	status_label.text = (
		"Face edit mode: left-click a Core face, then expand or shrink it."
		if enabled
		else "Mount placement mode restored."
	)
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_core_face_controls()
	_refresh_layout_preview()


func _on_layout_face_selected(face_index: int) -> void:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	if (
		drone_core == null
		or drone_core.editable_mesh == null
		or face_index < 0
		or face_index >= drone_core.editable_mesh.face_count()
	):
		layout_selected_face_index = -1
	else:
		layout_selected_face_index = face_index
	layout_selected_slot_index = -1
	_refresh_core_face_controls()
	_refresh_layout_preview()


func _on_core_dimensions_changed(_value: float) -> void:
	if suppress_core_geometry_callbacks:
		return
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	if current_body_kind != "drone" or drone_core == null:
		return
	var old_size: Vector3 = drone_core.body_size
	var target_size: Vector3 = Vector3(
		core_width_input.value,
		core_height_input.value,
		core_depth_input.value
	)
	drone_core.set_editable_body_size(target_size)
	_scale_layout_mounts_for_core_resize(old_size, drone_core.body_size, drone_core.editable_mesh)
	_sync_core_geometry_controls()
	_refresh_core_geometry_preview(false)
	status_label.text = "Core dimensions updated to %.2f × %.2f × %.2f m." % [
		drone_core.body_size.x,
		drone_core.body_size.y,
		drone_core.body_size.z,
	]
	status_label.add_theme_color_override("font_color", MUTED)


func _shrink_selected_core_face() -> void:
	_scale_selected_core_face(1.0 / CORE_FACE_SCALE_STEP)


func _expand_selected_core_face() -> void:
	_scale_selected_core_face(CORE_FACE_SCALE_STEP)


func _scale_selected_core_face(factor: float) -> void:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	if (
		drone_core == null
		or drone_core.editable_mesh == null
		or layout_selected_face_index < 0
		or layout_selected_face_index >= drone_core.editable_mesh.face_count()
	):
		_set_error("Select a Core face first.")
		return
	if not drone_core.editable_mesh.scale_face(layout_selected_face_index, factor):
		_set_error("The selected Core face could not be edited.")
		return
	drone_core.synchronize_body_size_from_editable_mesh()
	_reproject_layout_mounts_to_mesh(drone_core.editable_mesh)
	_sync_core_geometry_controls()
	_refresh_core_geometry_preview(false)
	status_label.text = "%s face %d. Core bounds are now %.2f × %.2f × %.2f m." % [
		"Expanded" if factor > 1.0 else "Shrank",
		layout_selected_face_index + 1,
		drone_core.body_size.x,
		drone_core.body_size.y,
		drone_core.body_size.z,
	]
	status_label.add_theme_color_override("font_color", MUTED)


func _refresh_core_geometry_preview(reset_camera_distance: bool) -> void:
	if layout_preview != null:
		layout_preview.set_core_resource(_current_physical_core(), reset_camera_distance)
		layout_preview.set_face_edit_enabled(
			core_face_edit_toggle != null and core_face_edit_toggle.button_pressed
		)
		layout_preview.set_selected_face(layout_selected_face_index)
	_refresh_layout_preview()


func _scale_layout_mounts_for_core_resize(
	old_size: Vector3,
	new_size: Vector3,
	mesh_definition: DroneCoreEditableMeshDefinition
) -> void:
	if mesh_definition == null:
		return
	var scale_factor: Vector3 = Vector3(
		new_size.x / maxf(old_size.x, 0.001),
		new_size.y / maxf(old_size.y, 0.001),
		new_size.z / maxf(old_size.z, 0.001)
	)
	for slot_index: int in range(layout_slot_transforms.size()):
		var source: Transform3D = layout_slot_transforms[slot_index]
		var kind: StringName = layout_slot_kinds[slot_index]
		var outward: Vector3 = _layout_slot_surface_normal(slot_index, source)
		var surface_point: Vector3 = source.origin - outward * CORE_MOUNT_OFFSET_M
		var scaled_surface_point: Vector3 = Vector3(
			surface_point.x * scale_factor.x,
			surface_point.y * scale_factor.y,
			surface_point.z * scale_factor.z
		)
		var direction: Vector3 = scaled_surface_point.normalized()
		if direction.length_squared() <= 0.000001:
			continue
		var hit: Dictionary = mesh_definition.ray_hit(Vector3.ZERO, direction)
		if hit.is_empty():
			continue
		layout_slot_surface_normals[slot_index] = hit.get("normal", outward).normalized()
		layout_slot_transforms[slot_index] = _layout_mount_from_mesh_hit(hit, kind)


func _reproject_layout_mounts_to_mesh(mesh_definition: DroneCoreEditableMeshDefinition) -> void:
	if mesh_definition == null:
		return
	for slot_index: int in range(layout_slot_transforms.size()):
		var source: Transform3D = layout_slot_transforms[slot_index]
		var kind: StringName = layout_slot_kinds[slot_index]
		var outward: Vector3 = _layout_slot_surface_normal(slot_index, source)
		var surface_point: Vector3 = source.origin - outward * CORE_MOUNT_OFFSET_M
		var direction: Vector3 = surface_point.normalized()
		if direction.length_squared() <= 0.000001:
			continue
		var hit: Dictionary = mesh_definition.ray_hit(Vector3.ZERO, direction)
		if hit.is_empty():
			continue
		var hit_normal: Vector3 = hit.get("normal", outward).normalized()
		layout_slot_surface_normals[slot_index] = hit_normal
		layout_slot_transforms[slot_index] = _layout_mount_from_mesh_hit(hit, kind)


func _layout_mount_from_mesh_hit(hit: Dictionary, kind: StringName) -> Transform3D:
	var point: Vector3 = hit.get("point", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP).normalized()
	return Transform3D(
		_slot_basis_from_surface_normal(
			_worker_up_axis_local() if kind == &"propeller" else normal,
			kind
		),
		point + normal * CORE_MOUNT_OFFSET_M
	)


func _layout_slot_surface_normal(slot_index: int, source: Transform3D) -> Vector3:
	var result: Vector3 = (
		layout_slot_surface_normals[slot_index]
		if slot_index >= 0 and slot_index < layout_slot_surface_normals.size()
		else -source.basis.y.normalized()
	)
	return result if result.length_squared() > 0.000001 else Vector3.UP


func _worker_up_axis_local() -> Vector3:
	var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
	return (
		drone_core.model_orientation_basis_local().y.normalized()
		if drone_core != null
		else Vector3.UP
	)


func _realign_creator_propellers_to_worker_up() -> void:
	var up_axis: Vector3 = _worker_up_axis_local()
	for slot_index: int in range(layout_slot_transforms.size()):
		if slot_index >= layout_slot_kinds.size() or layout_slot_kinds[slot_index] != &"propeller":
			continue
		var source: Transform3D = layout_slot_transforms[slot_index]
		layout_slot_transforms[slot_index] = Transform3D(
			_slot_basis_from_surface_normal(up_axis, &"propeller"),
			source.origin
		)
	_refresh_layout_preview()


func _refresh_layout_preview() -> void:
	if layout_preview != null:
		layout_preview.set_slots(layout_slot_transforms, layout_slot_kinds, layout_selected_slot_index)
		layout_preview.set_selected_face(layout_selected_face_index)
		var drone_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
		if drone_core != null:
			var orientation: Basis = drone_core.model_orientation_basis_local()
			layout_preview.set_model_orientation(-orientation.z, orientation.y)
	if layout_slot_count_label != null:
		if current_body_kind == "drone":
			layout_slot_count_label.text = "%d mounts   ·   %d propellers   ·   %d attachments" % [
				layout_slot_transforms.size(),
				_layout_slot_kind_count(&"propeller"),
				_layout_slot_kind_count(&"attachment"),
			]
			layout_slot_count_label.tooltip_text = "The battery is built into the Core. Add as many explicit propeller or attachment mounts as this body needs."
		else:
			layout_slot_count_label.text = "Free Core slot placement is currently available for drone Cores."
	if layout_selected_label != null:
		if layout_selected_slot_index >= 0 and layout_selected_slot_index < layout_slot_transforms.size():
			var mount: Transform3D = layout_slot_transforms[layout_selected_slot_index]
			var kind: StringName = layout_slot_kinds[layout_selected_slot_index]
			layout_selected_label.text = "Selected %s %d  ·  local (%.2f, %.2f, %.2f)" % [
				str(kind).capitalize(),
				_layout_kind_ordinal(layout_selected_slot_index),
				mount.origin.x,
				mount.origin.y,
				mount.origin.z,
			]
		else:
			layout_selected_label.text = ""
	_refresh_summary()


func _selected_layout_slot_kind() -> StringName:
	if layout_slot_kind_picker == null or layout_slot_kind_picker.selected < 0:
		return &"propeller"
	return StringName(str(layout_slot_kind_picker.get_item_metadata(layout_slot_kind_picker.selected)))


func _layout_slot_kind_count(kind: StringName) -> int:
	var result: int = 0
	for existing_kind: StringName in layout_slot_kinds:
		if existing_kind == kind:
			result += 1
	return result


func _layout_kind_ordinal(layout_index: int) -> int:
	if layout_index < 0 or layout_index >= layout_slot_kinds.size():
		return 0
	var kind: StringName = layout_slot_kinds[layout_index]
	var ordinal: int = 0
	for index: int in range(layout_index + 1):
		if layout_slot_kinds[index] == kind:
			ordinal += 1
	return ordinal


func _layout_capacity_error(kind: StringName, additional_count: int) -> String:
	if additional_count <= 0:
		return ""
	if kind == &"attachment":
		return ""
	if kind == &"propeller":
		return ""
	return "Slot kind '%s' is not supported by the drone runtime." % str(kind)


func _on_layout_slot_kind_selected(_picker_index: int) -> void:
	# This selector describes the *next* mount. Selecting an existing marker must never make a later
	# picker change silently rewrite an already-authored slot. Retype by RMB-removing and replacing it.
	status_label.text = "New placements will create %s mounts." % str(_selected_layout_slot_kind())
	status_label.add_theme_color_override("font_color", MUTED)


func _on_layout_surface_clicked(mount_transform: Transform3D) -> void:
	if current_body_kind != "drone":
		return
	var slot_kind: StringName = _selected_layout_slot_kind()
	var surface_normal: Vector3 = -mount_transform.basis.y.normalized()
	if surface_normal.length_squared() <= 0.000001:
		surface_normal = Vector3.UP
	mount_transform = _mount_transform_for_kind(mount_transform, slot_kind)
	var mirror_pair: bool = mirror_next_checkbox != null and mirror_next_checkbox.button_pressed
	var required_capacity: int = 2 if mirror_pair else 1
	var capacity_error: String = _layout_capacity_error(slot_kind, required_capacity)
	if not capacity_error.is_empty():
		_set_error(capacity_error)
		return
	if _layout_slot_too_close(mount_transform.origin):
		_set_error("That slot overlaps an existing mount. Pick a different point on the Core.")
		return
	var mirrored: Transform3D = Transform3D.IDENTITY
	var mirrored_surface_normal: Vector3 = surface_normal
	if mirror_pair:
		mirrored_surface_normal.x = -mirrored_surface_normal.x
		mirrored = _mirrored_layout_transform(
			mount_transform,
			slot_kind,
			mirrored_surface_normal
		)
		if mirrored.origin.distance_to(mount_transform.origin) <= 0.02:
			_set_error("Mirror placement needs a point away from the Core's center plane.")
			return
		if _layout_slot_too_close(mirrored.origin):
			_set_error("The mirrored mount overlaps an existing slot.")
			return
	layout_slot_transforms.append(mount_transform)
	layout_slot_kinds.append(slot_kind)
	layout_slot_surface_normals.append(surface_normal)
	layout_selected_slot_index = layout_slot_transforms.size() - 1
	if mirror_pair:
		layout_slot_transforms.append(mirrored)
		layout_slot_kinds.append(slot_kind)
		layout_slot_surface_normals.append(mirrored_surface_normal)
		layout_selected_slot_index = layout_slot_transforms.size() - 1
	status_label.text = ""
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_layout_preview()


func _on_layout_slot_selected(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= layout_slot_transforms.size():
		return
	layout_selected_slot_index = slot_index
	layout_selected_face_index = -1
	_refresh_core_face_controls()
	_refresh_layout_preview()


func _on_layout_slot_remove_requested(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= layout_slot_transforms.size():
		return
	layout_selected_slot_index = slot_index
	_delete_selected_layout_slot()


func _mirror_selected_layout_slot() -> void:
	if layout_selected_slot_index < 0 or layout_selected_slot_index >= layout_slot_transforms.size():
		_set_error("Select a slot marker first.")
		return
	var source_kind: StringName = layout_slot_kinds[layout_selected_slot_index]
	var capacity_error: String = _layout_capacity_error(source_kind, 1)
	if not capacity_error.is_empty():
		_set_error(capacity_error)
		return
	var source: Transform3D = layout_slot_transforms[layout_selected_slot_index]
	var mirrored_surface_normal: Vector3 = _layout_slot_surface_normal(
		layout_selected_slot_index,
		source
	)
	mirrored_surface_normal.x = -mirrored_surface_normal.x
	var mirrored: Transform3D = _mirrored_layout_transform(
		source,
		source_kind,
		mirrored_surface_normal
	)
	if mirrored.origin.distance_to(source.origin) <= 0.02:
		_set_error("A slot on the mirror plane has no distinct left/right counterpart.")
		return
	if _layout_slot_too_close(mirrored.origin):
		_set_error("The mirrored mount already overlaps an existing slot.")
		return
	layout_slot_transforms.append(mirrored)
	layout_slot_kinds.append(source_kind)
	layout_slot_surface_normals.append(mirrored_surface_normal)
	layout_selected_slot_index = layout_slot_transforms.size() - 1
	status_label.text = "Mirrored the selected %s slot across the Core's local X axis." % str(source_kind)
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_layout_preview()


func _delete_selected_layout_slot() -> void:
	if layout_selected_slot_index < 0 or layout_selected_slot_index >= layout_slot_transforms.size():
		_set_error("Select a slot marker first.")
		return
	layout_slot_transforms.remove_at(layout_selected_slot_index)
	if layout_selected_slot_index < layout_slot_kinds.size():
		layout_slot_kinds.remove_at(layout_selected_slot_index)
	if layout_selected_slot_index < layout_slot_surface_normals.size():
		layout_slot_surface_normals.remove_at(layout_selected_slot_index)
	layout_selected_slot_index = mini(layout_selected_slot_index, layout_slot_transforms.size() - 1)
	status_label.text = "Slot removed. Remaining mounts were renumbered in layout order."
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_layout_preview()


func _layout_slot_too_close(position: Vector3) -> bool:
	for existing: Transform3D in layout_slot_transforms:
		if existing.origin.distance_to(position) < MINIMUM_SLOT_SPACING_M:
			return true
	return false


func _mount_transform_for_kind(source: Transform3D, kind: StringName) -> Transform3D:
	# The click chooses a mount position/surface. Articulated attachments keep that outward surface
	# frame, while an ordinary creator propeller defaults to the green worker-up axis. The previous
	# face-normal behavior silently made every side-mounted rotor a lateral thruster, even though the
	# dialog offered no separate rotor rotation tool and then reported 0.00x nominal uplift.
	var outward_normal: Vector3 = -source.basis.y.normalized()
	var mount_axis: Vector3 = (
		_worker_up_axis_local() if kind == &"propeller" else outward_normal
	)
	return Transform3D(_slot_basis_from_surface_normal(mount_axis, kind), source.origin)


func _mirrored_layout_transform(
	source: Transform3D,
	kind: StringName,
	mirrored_surface_normal: Vector3 = Vector3.ZERO
) -> Transform3D:
	var mirrored_origin: Vector3 = source.origin
	mirrored_origin.x = -mirrored_origin.x
	var surface_normal: Vector3 = mirrored_surface_normal
	if surface_normal.length_squared() <= 0.000001:
		surface_normal = -source.basis.y.normalized()
		surface_normal.x = -surface_normal.x
	var mount_axis: Vector3 = (
		_worker_up_axis_local() if kind == &"propeller" else surface_normal
	)
	var mirrored_basis: Basis = _slot_basis_from_surface_normal(mount_axis, kind)
	return Transform3D(mirrored_basis, mirrored_origin)


func _slot_basis_from_surface_normal(
	surface_normal: Vector3,
	kind: StringName = &"attachment"
) -> Basis:
	var normal: Vector3 = surface_normal.normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.DOWN
	var y_axis: Vector3 = normal if kind == &"propeller" else -normal
	var helper: Vector3 = Vector3.FORWARD
	if absf(y_axis.dot(helper)) > 0.92:
		helper = Vector3.RIGHT
	var x_axis: Vector3 = helper.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


func _accept_core_layout() -> void:
	if current_draft == null or _current_physical_core() == null:
		_set_error("Choose a Core first.")
		return
	if current_body_kind == "drone":
		var source_core: DroneCoreDefinition = _current_physical_core() as DroneCoreDefinition
		if source_core == null:
			_set_error("The selected drone body has no physical Core.")
			return
		var propeller_count: int = _layout_slot_kind_count(&"propeller")
		var attachment_count: int = _layout_slot_kind_count(&"attachment")
		var core_copy: DroneCoreDefinition = (
			MLBodyPartContract.deep_duplicate_resource(source_core) as DroneCoreDefinition
		)
		if core_copy == null:
			_set_error("The selected Core could not be copied into the hardware stage.")
			return
		var previously_equipped: Dictionary = _equipped_parts_by_slot_id(current_draft)
		core_copy.propeller_slot_count = propeller_count
		core_copy.attachment_slot_count = attachment_count
		core_copy.ai_chip_slot_count = 0
		var empty_loadout: DroneLoadout = DroneLoadout.new()
		empty_loadout.install_core(core_copy)
		var propeller_index: int = 0
		var attachment_index: int = 0
		for layout_index: int in range(layout_slot_transforms.size()):
			var slot_kind: StringName = layout_slot_kinds[layout_index]
			var slot_transform: Transform3D = layout_slot_transforms[layout_index]
			if slot_kind == &"propeller":
				if not empty_loadout.set_propeller_slot_transform(propeller_index, slot_transform):
					_set_error("Propeller mount %d could not be transferred to the runtime body." % (layout_index + 1))
					return
				propeller_index += 1
			elif slot_kind == &"attachment":
				if not empty_loadout.set_attachment_slot_transform(attachment_index, slot_transform):
					_set_error("Attachment mount %d could not be transferred to the runtime body." % (layout_index + 1))
					return
				attachment_index += 1
		var next_draft: MLBodyBuildDraft = DroneMLBodyInterfaceFactory.create_draft(empty_loadout)
		if next_draft == null or next_draft.core == null or not next_draft.last_error.is_empty():
			_set_error("The accepted Core layout could not create an empty hardware draft.")
			return
		next_draft.core_contract["preset_id"] = str(current_preset_id)
		_restore_compatible_equipment(next_draft, previously_equipped)
		current_draft = next_draft
		changed_slot_ids.clear()
		initial_slot_keys.clear()
		slot_parts.clear()
		_rebuild_slot_rows()
		_refresh_training_settings_for_body(true)
	else:
		# Non-drone runtimes still use their authored fixed topology until they gain a generic Core
		# mount installer. The family selector is gone; selecting such a Core chooses that adapter.
		for entry: Dictionary in current_draft.slots:
			var authored_slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
			if authored_slot != null and _slot_runtime_edit_supported(authored_slot):
				current_draft.unequip(authored_slot.slot_id)
		changed_slot_ids.clear()
		initial_slot_keys.clear()
		slot_parts.clear()
		_rebuild_slot_rows()
		_refresh_training_settings_for_body(true)
	status_label.text = "Core locked. Equip each mount."
	status_label.add_theme_color_override("font_color", MUTED)
	_set_creator_stage(STAGE_HARDWARE)
	_refresh_summary()


func _equipped_parts_by_slot_id(draft: MLBodyBuildDraft) -> Dictionary:
	var result: Dictionary = {}
	if draft == null:
		return result
	for entry: Dictionary in draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		var part: Resource = entry.get("part") as Resource
		if slot != null and part != null:
			result[str(slot.slot_id)] = part
	return result


func _restore_compatible_equipment(
	draft: MLBodyBuildDraft,
	parts_by_slot_id: Dictionary
) -> void:
	if draft == null or parts_by_slot_id.is_empty():
		return
	for entry: Dictionary in draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null:
			continue
		var source: Resource = parts_by_slot_id.get(str(slot.slot_id)) as Resource
		if source == null or not slot.accepts(source):
			continue
		var copied: Resource = MLBodyPartContract.deep_duplicate_resource(source)
		if copied != null:
			draft.equip(slot.slot_id, copied)


func _build_training_settings(root: VBoxContainer) -> void:
	training_options_button = _creator_button("TRAINING OPTIONS  ▸", false)
	training_options_button.toggle_mode = true
	training_options_button.tooltip_text = "Network, reward, worker-count, and rollout settings. Defaults are ready to use."
	training_options_button.toggled.connect(func(expanded: bool) -> void:
		if training_settings_panel != null:
			training_settings_panel.visible = expanded
		training_options_button.text = "TRAINING OPTIONS  ▾" if expanded else "TRAINING OPTIONS  ▸"
		call_deferred("_refresh_creator_window_after_layout")
	)
	root.add_child(training_options_button)

	training_settings_panel = PanelContainer.new()
	training_settings_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	training_settings_panel.visible = false
	root.add_child(training_settings_panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	training_settings_panel.add_child(body)

	var algorithm_row: HBoxContainer = HBoxContainer.new()
	algorithm_row.add_theme_constant_override("separation", 8)
	body.add_child(algorithm_row)
	var algorithm_label: Label = Label.new()
	algorithm_label.text = "Algorithm"
	algorithm_label.custom_minimum_size.x = 170.0
	algorithm_row.add_child(algorithm_label)
	algorithm_picker = OptionButton.new()
	algorithm_picker.fit_to_longest_item = false
	algorithm_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	algorithm_picker.item_selected.connect(_on_algorithm_selected)
	algorithm_row.add_child(algorithm_picker)

	hidden_width_input = _add_numeric_setting(
		body,
		"Hidden layer width",
		float(DronePPOMLP.MINIMUM_HIDDEN_WIDTH),
		float(DronePPOMLP.MAXIMUM_HIDDEN_WIDTH),
		8.0,
		float(DronePPOActorCritic.HIDDEN_SIZE),
		"Neurons in each hidden layer. Wider networks can represent more complicated control relationships but cost more inference and optimizer work."
	)
	hidden_depth_input = _add_numeric_setting(
		body,
		"Hidden layer depth",
		float(DronePPOMLP.MINIMUM_HIDDEN_DEPTH),
		float(DronePPOMLP.MAXIMUM_HIDDEN_DEPTH),
		1.0,
		float(DronePPOActorCritic.HIDDEN_LAYER_COUNT),
		"Number of hidden layers. This topology is fixed when the worker group is created."
	)
	worker_count_input = _add_numeric_setting(
		body,
		"Starting workers",
		1.0,
		48.0,
		1.0,
		8.0,
		"Number of physical workers that initially collect experience for this model."
	)
	control_rate_input = _add_numeric_setting(
		body,
		"Control rate (Hz)",
		2.0,
		60.0,
		1.0,
		20.0,
		"How often the model chooses new actuator commands per simulated second."
	)
	exploration_input = _add_numeric_setting(
		body,
		"Exploration strength",
		0.0,
		2.0,
		0.005,
		0.01,
		"Initial PPO entropy coefficient or SAC entropy temperature. This is available only for drone algorithms in this first creator pass."
	)
	exploration_input.allow_greater = false

	var reward_row: HBoxContainer = HBoxContainer.new()
	reward_row.add_theme_constant_override("separation", 8)
	body.add_child(reward_row)
	var reward_label: Label = Label.new()
	reward_label.text = "Reward preset"
	reward_label.custom_minimum_size.x = 170.0
	reward_label.tooltip_text = "Starting reward-card preset. This uses the same reward-card library as the worker-group tuning UI and can be changed later while the group is paused."
	reward_row.add_child(reward_label)
	reward_cardset_picker = OptionButton.new()
	reward_cardset_picker.fit_to_longest_item = false
	reward_cardset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_cardset_picker.tooltip_text = reward_label.tooltip_text
	reward_cardset_picker.item_selected.connect(func(_index: int) -> void:
		if current_draft != null and not suppress_training_ui_callbacks:
			_refresh_summary()
	)
	reward_row.add_child(reward_cardset_picker)

	start_training_checkbox = CheckBox.new()
	start_training_checkbox.text = "Start training immediately"
	start_training_checkbox.button_pressed = true
	start_training_checkbox.tooltip_text = "Off creates the worker group paused so you can inspect it first. Fresh bodies use random weights; saved-model branching remains in BRANCH VARIANT so incompatible body contracts cannot mix."
	body.add_child(start_training_checkbox)
	for input: SpinBox in [hidden_width_input, hidden_depth_input, worker_count_input, control_rate_input, exploration_input]:
		input.value_changed.connect(func(_value: float) -> void:
			if current_draft != null and not suppress_training_ui_callbacks:
				_refresh_summary()
		)
	start_training_checkbox.toggled.connect(func(_pressed: bool) -> void:
		if current_draft != null and not suppress_training_ui_callbacks:
			_refresh_summary()
	)


func _add_numeric_setting(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	initial_value: float,
	tooltip: String
) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 170.0
	label.tooltip_text = tooltip
	row.add_child(label)
	var input: SpinBox = SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = initial_value
	input.allow_lesser = false
	input.allow_greater = false
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.tooltip_text = tooltip
	row.add_child(input)
	return input


func _on_algorithm_selected(_index: int) -> void:
	if suppress_training_ui_callbacks:
		return
	_refresh_training_settings_for_body(true)
	_refresh_summary()


func _selected_algorithm_id() -> String:
	if algorithm_picker == null or algorithm_picker.selected < 0:
		return "ppo_clip"
	return str(algorithm_picker.get_item_metadata(algorithm_picker.selected))


func _create_algorithm_preview(algorithm_id: String) -> DroneTrainingAlgorithm:
	var config: Dictionary = {}
	if algorithm_id == "ppo_clip" and current_draft != null:
		var preview_draft: MLBodyBuildDraft = current_draft.duplicate_editable()
		var manifest: MLBodyInterfaceManifest = preview_draft.accept_build()
		if manifest != null:
			config["body_interface"] = manifest.to_dictionary()
			config["action_count"] = manifest.control_count()
	return DroneTrainingAlgorithmCatalog.create(algorithm_id, config)


func _algorithm_configuration_control(
	algorithm: DroneTrainingAlgorithm,
	key: String
) -> Dictionary:
	if algorithm == null:
		return {}
	for control: Dictionary in algorithm.configuration_controls():
		if str(control.get("key", "")) == key:
			return control.duplicate(true)
	return {}


func _refresh_training_settings_for_body(reset_values: bool = false) -> void:
	if algorithm_picker == null:
		return
	suppress_training_ui_callbacks = true
	var previous_algorithm: String = _selected_algorithm_id()
	algorithm_picker.clear()
	if current_body_kind == "drone":
		var legacy_four_propeller_body: bool = _drone_body_supports_legacy_four_propeller_algorithm()
		var selected_valid_index: int = -1
		var ppo_index: int = -1
		for descriptor: Dictionary in DroneTrainingAlgorithmCatalog.descriptors():
			var index: int = algorithm_picker.item_count
			var descriptor_id: String = str(descriptor.get("id", "ppo_clip"))
			algorithm_picker.add_item(str(descriptor.get("display_name", "Learning algorithm")))
			algorithm_picker.set_item_metadata(index, descriptor_id)
			var supported: bool = descriptor_id == "ppo_clip" or legacy_four_propeller_body
			var algorithm_tooltip: String = str(descriptor.get("description", ""))
			if not supported:
				algorithm_tooltip += "\n\nThis algorithm still assumes the authored stock four-rotor geometry. Use PPO for freely placed rotors or controlled attachments."
			algorithm_picker.set_item_tooltip(index, algorithm_tooltip)
			algorithm_picker.set_item_disabled(index, not supported)
			if descriptor_id == "ppo_clip":
				ppo_index = index
			if descriptor_id == previous_algorithm and supported:
				selected_valid_index = index
		if selected_valid_index >= 0:
			algorithm_picker.select(selected_valid_index)
		elif ppo_index >= 0:
			algorithm_picker.select(ppo_index)
		algorithm_picker.disabled = false
		var algorithm_id: String = _selected_algorithm_id()
		var algorithm_changed: bool = algorithm_id != previous_algorithm
		var preview: DroneTrainingAlgorithm = _create_algorithm_preview(algorithm_id)
		if preview != null:
			var architecture: Dictionary = preview.network_architecture()
			var exploration_key: String = "entropy_coefficient" if algorithm_id == "ppo_clip" else "entropy_temperature"
			var exploration_control: Dictionary = _algorithm_configuration_control(preview, exploration_key)
			if not exploration_control.is_empty():
				exploration_input.min_value = float(exploration_control.get("minimum", 0.0))
				exploration_input.max_value = float(exploration_control.get("maximum", 2.0))
				exploration_input.step = maxf(float(exploration_control.get("step", 0.005)), 0.000001)
				exploration_input.tooltip_text = str(exploration_control.get(
					"tooltip",
					"Initial exploration strength for the selected learning algorithm."
				))
			if reset_values or algorithm_changed:
				hidden_width_input.value = float(architecture.get("hidden_layer_width", DronePPOActorCritic.HIDDEN_SIZE))
				hidden_depth_input.value = float(architecture.get("hidden_layer_depth", DronePPOActorCritic.HIDDEN_LAYER_COUNT))
				worker_count_input.value = float(preview.default_worker_count())
				control_rate_input.value = 1.0 / maxf(float(preview.config_values().get("control_interval_seconds", 0.05)), 0.001)
				exploration_input.value = float(preview.config_values().get(exploration_key, 0.01))
			worker_count_input.max_value = float(preview.maximum_worker_count())
		exploration_input.editable = true
	else:
		algorithm_picker.add_item("Clipped PPO + GAE")
		algorithm_picker.set_item_metadata(0, "ppo_clip")
		algorithm_picker.select(0)
		algorithm_picker.disabled = true
		exploration_input.editable = false
		exploration_input.value = 0.0
		if current_body_kind == "articulated_body":
			worker_count_input.max_value = float(FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT)
			if reset_values:
				hidden_width_input.value = float(FourLimbPPOActorCritic.HIDDEN_SIZE)
				hidden_depth_input.value = float(FourLimbPPOActorCritic.HIDDEN_LAYER_COUNT)
				worker_count_input.value = float(FourLimbTrainingCoordinator.DEFAULT_WORKER_COUNT)
				control_rate_input.value = 1.0 / FourLimbTrainingCoordinator.DECISION_INTERVAL_SECONDS
		elif current_body_kind == "turret":
			worker_count_input.max_value = float(TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT)
			if reset_values:
				hidden_width_input.value = float(TurretPPOActorCritic.HIDDEN_SIZE)
				hidden_depth_input.value = float(TurretPPOActorCritic.HIDDEN_LAYER_COUNT)
				worker_count_input.value = float(TurretTrainingCoordinator.DEFAULT_WORKER_COUNT)
				control_rate_input.value = 1.0 / TurretTrainingCoordinator.DECISION_INTERVAL_SECONDS
	_refresh_reward_cardsets(false)
	suppress_training_ui_callbacks = false


func _drone_body_supports_legacy_four_propeller_algorithm() -> bool:
	if current_draft == null:
		return false
	var manifest: MLBodyInterfaceManifest = current_draft.duplicate_editable().accept_build()
	return DroneMLBodyInterfaceFactory.is_legacy_stock_quad_manifest(manifest)


func _reward_body_type() -> String:
	match current_body_kind:
		"drone":
			return TrainingRewardCardsetLibrary.BODY_TYPE_DRONE
		"articulated_body":
			return TrainingRewardCardsetLibrary.BODY_TYPE_FOUR_LIMB
		"turret":
			return TrainingRewardCardsetLibrary.BODY_TYPE_TURRET
	return TrainingRewardCardsetLibrary.BODY_TYPE_DRONE


func _default_reward_cardset_id() -> String:
	match _reward_body_type():
		TrainingRewardCardsetLibrary.BODY_TYPE_FOUR_LIMB:
			return "builtin:limb_ground"
		TrainingRewardCardsetLibrary.BODY_TYPE_TURRET:
			return "builtin:turret_precision"
	return "builtin:drone_balanced"


func _refresh_reward_cardsets(reset_selection: bool) -> void:
	if reward_cardset_picker == null:
		return
	var previous_id: String = _selected_reward_cardset().get("id", "") if not reset_selection else ""
	reward_cardset_picker.clear()
	reward_cardsets.clear()
	var selected_index: int = -1
	var fallback_index: int = -1
	var default_id: String = _default_reward_cardset_id()
	for record: Dictionary in reward_cardset_library.cardsets_for_body_type(_reward_body_type()):
		var cardset_id: String = str(record.get("id", ""))
		if cardset_id.is_empty():
			continue
		var index: int = reward_cardset_picker.item_count
		reward_cardsets[cardset_id] = record.duplicate(true)
		reward_cardset_picker.add_item(str(record.get("display_name", "Reward preset")))
		reward_cardset_picker.set_item_metadata(index, cardset_id)
		if cardset_id == previous_id:
			selected_index = index
		if cardset_id == default_id:
			fallback_index = index
	if selected_index < 0:
		selected_index = fallback_index if fallback_index >= 0 else (0 if reward_cardset_picker.item_count > 0 else -1)
	if selected_index >= 0:
		reward_cardset_picker.select(selected_index)
	reward_cardset_picker.disabled = reward_cardset_picker.item_count <= 1


func _selected_reward_cardset() -> Dictionary:
	if reward_cardset_picker == null or reward_cardset_picker.selected < 0:
		return {}
	var cardset_id: String = str(reward_cardset_picker.get_item_metadata(reward_cardset_picker.selected))
	var value: Variant = reward_cardsets.get(cardset_id, {})
	return SafeVariant.dictionary_copy(value)


func _training_request() -> Dictionary:
	var algorithm_id: String = _selected_algorithm_id()
	var reward_cardset: Dictionary = _selected_reward_cardset()
	var reward_cards_value: Variant = reward_cardset.get("cards", {})
	var reward_cards: Dictionary = SafeVariant.dictionary_copy(reward_cards_value)
	return {
		"algorithm_id": algorithm_id,
		"hidden_layer_width": int(round(hidden_width_input.value)),
		"hidden_layer_depth": int(round(hidden_depth_input.value)),
		"worker_count": int(round(worker_count_input.value)),
		"control_rate_hz": maxf(control_rate_input.value, 1.0),
		"exploration_strength": maxf(exploration_input.value, 0.0),
		"reward_cardset_id": str(reward_cardset.get("id", "custom")),
		"reward_cardset_name": str(reward_cardset.get("display_name", "Custom")),
		"reward_cards": reward_cards,
		"start_active": start_training_checkbox.button_pressed,
	}


func _populate_core_picker() -> void:
	core_picker.clear()
	core_parts.clear()
	core_preset_ids.clear()
	core_picker.disabled = false

	# Saved gameplay Cores are the primary creator entry point. The runtime family is inferred from
	# the concrete Core resource, so drone and turret Cores can coexist in one list without a second
	# selector that can contradict the selected Core.
	for part: Resource in MLBodyPartCatalog.all_parts():
		if part is DroneCoreDefinition:
			_add_core_option(
				part,
				(
					MLBodyPresetLibrary.DRONE_HEX
					if MLBodyPartContract.resource_source_path(part)
					== MLBodyPresetLibrary.DRONE_HEX_CORE_PATH
					else MLBodyPresetLibrary.DRONE_QUAD
				)
			)
		elif part is TurretBaseDefinition:
			_add_core_option(part, MLBodyPresetLibrary.STATIONARY_TURRET)

	# Articulated presets currently share the fixed four-limb runtime adapter rather than standalone
	# gameplay Core assets. Their generated rigid Cores are still concrete creator choices.
	for articulated_preset_id: StringName in [
		MLBodyPresetLibrary.TINY_HUMANOID,
		MLBodyPresetLibrary.FOUR_LIMB_WALKER,
	]:
		var articulated_draft: MLBodyBuildDraft = MLBodyPresetLibrary.instantiate_draft(
			articulated_preset_id
		)
		if articulated_draft == null or articulated_draft.core == null:
			continue
		var articulated_core: Resource = _physical_core_from_draft(articulated_draft)
		if articulated_core != null:
			_add_core_option(
				articulated_core,
				articulated_preset_id,
				"builtin:%s_core" % str(articulated_preset_id)
			)

	if core_picker.item_count <= 0:
		core_picker.add_item("No physical Cores found")
		core_picker.disabled = true


func _add_core_option(
	core_resource: Resource,
	preset_id: StringName,
	explicit_key: String = ""
) -> void:
	if core_resource == null:
		return
	var source_path: String = MLBodyPartContract.resource_source_path(core_resource)
	var key: String = explicit_key if not explicit_key.is_empty() else source_path
	if key.is_empty():
		key = "builtin:%s:%d" % [str(preset_id), core_picker.item_count]
	if core_parts.has(key):
		return
	core_parts[key] = MLBodyPartContract.deep_duplicate_resource(core_resource)
	core_preset_ids[key] = str(preset_id)
	var option_index: int = core_picker.item_count
	core_picker.add_item(MLBodyPartCatalog.display_name(core_resource))
	core_picker.set_item_metadata(option_index, key)


func _preferred_initial_core_index() -> int:
	var preferred_path: String = MLBodyPresetLibrary.DRONE_QUAD_LOADOUT_PATH
	var default_loadout: DroneLoadout = load(preferred_path) as DroneLoadout
	var default_core_path: String = (
		MLBodyPartContract.resource_source_path(default_loadout.core)
		if default_loadout != null and default_loadout.core != null
		else ""
	)
	for index: int in range(core_picker.item_count):
		var key: String = str(core_picker.get_item_metadata(index))
		if key == default_core_path:
			return index
	return 0



func _on_core_selected(index: int) -> void:
	if index < 0 or index >= core_picker.item_count:
		return
	var key: String = str(core_picker.get_item_metadata(index))
	var selected_core: Resource = core_parts.get(key) as Resource
	if selected_core == null:
		_set_error("The selected Core is no longer available.")
		return
	var preset_id: StringName = StringName(str(core_preset_ids.get(key, "")))
	var preset: MLBodyPreset = MLBodyPresetLibrary.preset_by_id(preset_id)
	if preset == null:
		_set_error("The selected Core has no training runtime adapter.")
		return
	var next_draft: MLBodyBuildDraft = null
	if selected_core is DroneCoreDefinition:
		var empty_loadout: DroneLoadout = DroneLoadout.new()
		empty_loadout.install_core(
			MLBodyPartContract.deep_duplicate_resource(selected_core) as DroneCoreDefinition
		)
		next_draft = DroneMLBodyInterfaceFactory.create_draft(empty_loadout)
	elif selected_core is TurretBaseDefinition:
		var source_turret: TurretLoadout = (
			MLBodyPresetLibrary.instantiate_runtime_template(MLBodyPresetLibrary.STATIONARY_TURRET) as TurretLoadout
		)
		if source_turret != null:
			source_turret.base = (
				MLBodyPartContract.deep_duplicate_resource(selected_core) as TurretBaseDefinition
			)
			next_draft = TurretMLBodyInterfaceFactory.create_draft(source_turret)
	elif selected_core is MLRigidCorePartDefinition:
		next_draft = MLBodyPresetLibrary.instantiate_draft(preset_id)
	else:
		_set_error("This Core type does not have a creator runtime adapter yet.")
		return
	if next_draft == null or next_draft.core == null or not next_draft.last_error.is_empty():
		_set_error("The selected Core could not build its editable body.")
		return
	current_preset_id = preset_id
	current_draft = next_draft
	current_body_kind = str(next_draft.core_contract.get("body_kind", preset.body_kind))
	next_draft.core_contract["preset_id"] = str(current_preset_id)
	changed_slot_ids.clear()
	initial_slot_keys.clear()
	slot_parts.clear()
	status_label.text = "Core ready. Place its mounts."
	status_label.add_theme_color_override("font_color", MUTED)
	description_label.text = _creator_description_for_core(selected_core, preset)
	core_picker.tooltip_text = description_label.text
	core_label.text = "Core: %s" % MLBodyPartCatalog.display_name(_current_physical_core())
	group_name_input.text = "%s group" % MLBodyPartCatalog.display_name(_current_physical_core())
	_initialize_layout_for_current_core()
	_refresh_training_settings_for_body(true)
	_set_creator_stage(STAGE_CORE_LAYOUT)
	_refresh_summary()


func _creator_description_for_core(core: Resource, preset: MLBodyPreset) -> String:
	if core is DroneCoreDefinition:
		return "Drone Core. Battery is intrinsic; every propeller and attachment mount is authored explicitly in the 3D layout below."
	if preset != null:
		return preset.description
	return "Select the Core and configure the physical slots supported by its runtime."


func _current_physical_core() -> Resource:
	return _physical_core_from_draft(current_draft)


func _physical_core_from_draft(draft: MLBodyBuildDraft) -> Resource:
	if draft == null or draft.core == null:
		return null
	if draft.core is MLBodyCoreDefinition:
		return (draft.core as MLBodyCoreDefinition).physical_core
	return draft.core


func _rebuild_slot_rows() -> void:
	for child: Node in slots_content.get_children():
		child.queue_free()
	slot_pickers.clear()
	slot_editor_hosts.clear()
	limb_shape_editors.clear()
	limb_segment_pickers.clear()
	limb_dimension_labels.clear()
	limb_mass_inputs.clear()
	if current_draft == null:
		return
	for entry: Dictionary in current_draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot != null:
			_build_slot_row(slot, entry.get("part") as Resource)
	# queue_free() removes old rows at the end of the frame. Measure after that point so stale rows
	# do not inflate the next preset/Core's opening size.
	call_deferred("_refresh_creator_window_after_layout")


func _creator_part_label(part: Resource, suffix: String = "") -> String:
	var label_text: String = MLBodyPartCatalog.display_name(part)
	var controls: int = MLBodyPartContract.control_descriptors(part).size()
	var observations: int = MLBodyPartContract.observation_descriptors(part).size()
	if controls > 0 or observations > 0:
		label_text += "  • ML %dC/%dO" % [controls, observations]
	elif part is DroneAttachmentDefinition:
		label_text += "  • passive (no ML controls)"
	if not suffix.is_empty():
		label_text += suffix
	return label_text


func _same_as_limb_sources(
	target_slot: MLBodySlotDefinition
) -> Array[MLBodySlotDefinition]:
	var result: Array[MLBodySlotDefinition] = []
	if current_draft == null or target_slot == null or not _slot_runtime_edit_supported(target_slot):
		return result
	for entry: Dictionary in current_draft.slots:
		var source_slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if (
			source_slot == null
			or source_slot.slot_id == target_slot.slot_id
			or source_slot.slot_type != target_slot.slot_type
			or not _slot_runtime_edit_supported(source_slot)
		):
			continue
		var source_part: Resource = entry.get("part") as Resource
		if (
			source_part == null
			or not target_slot.accepts(source_part)
			or MLBodyLimbEditor.editable_limbs(source_part).is_empty()
		):
			continue
		result.append(source_slot)
	return result


func _build_slot_row(slot: MLBodySlotDefinition, current_part: Resource) -> void:
	var slot_id: String = str(slot.slot_id)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_slot_panel_style()
	)
	slots_content.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	panel.add_child(body)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	var label: Label = Label.new()
	label.text = slot.display_name
	label.custom_minimum_size.x = 180.0
	label.add_theme_color_override("font_color", GREEN)
	row.add_child(label)
	var picker: OptionButton = OptionButton.new()
	picker.fit_to_longest_item = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	slot_pickers[slot_id] = picker
	var part_map: Dictionary = {}
	slot_parts[slot_id] = part_map

	var required: bool = _slot_is_required(slot)
	var editable: bool = _slot_runtime_edit_supported(slot)
	var selected_index: int = -1
	var selected_key: String = EMPTY_KEY
	if not required:
		picker.add_item("Empty")
		picker.set_item_metadata(0, EMPTY_KEY)
		if current_part == null:
			selected_index = 0
	elif current_part == null:
		picker.add_item("Select required part…")
		picker.set_item_metadata(0, EMPTY_KEY)
		picker.set_item_disabled(0, true)
		selected_index = 0
	if current_part != null:
		var current_key: String = CURRENT_KEY_PREFIX + slot_id
		part_map[current_key] = MLBodyPartContract.deep_duplicate_resource(current_part)
		var current_index: int = picker.item_count
		picker.add_item(_creator_part_label(current_part, "  • current"))
		picker.set_item_metadata(current_index, current_key)
		selected_index = current_index
		selected_key = current_key
	for source_slot: MLBodySlotDefinition in _same_as_limb_sources(slot):
		var source_slot_id: String = str(source_slot.slot_id)
		var same_as_key: String = SAME_AS_KEY_PREFIX + source_slot_id
		var same_as_index: int = picker.item_count
		picker.add_item("Same as %s" % source_slot.display_name)
		picker.set_item_metadata(same_as_index, same_as_key)
		picker.get_popup().set_item_tooltip(
			same_as_index,
			"Copy the current modeled limb from %s. This slot keeps its own mount and receives an independent editable copy." % source_slot.display_name
		)
	var current_source: String = MLBodyPartContract.resource_source_path(current_part)
	if editable:
		for part: Resource in MLBodyPartCatalog.compatible_parts(slot):
			var source_path: String = MLBodyPartContract.resource_source_path(part)
			if source_path.is_empty() or source_path == current_source:
				continue
			if part_map.has(source_path):
				continue
			part_map[source_path] = part
			var option_index: int = picker.item_count
			picker.add_item(_creator_part_label(part))
			picker.set_item_metadata(option_index, source_path)
	if selected_index >= 0:
		picker.select(selected_index)
	# Keep the original stage-entry selection as the change baseline. Rebuilding rows after
	# copying a configuration must not make the newly copied hardware look unchanged.
	if not initial_slot_keys.has(slot_id):
		initial_slot_keys[slot_id] = selected_key
	picker.disabled = not editable
	picker.item_selected.connect(_on_slot_part_selected.bind(slot_id))

	var accepted_tags: Array = slot.contract_dictionary().get("accepted_part_tags", [])
	var accepted_tag_strings: PackedStringArray = PackedStringArray()
	for accepted_tag_value: Variant in accepted_tags:
		accepted_tag_strings.append(str(accepted_tag_value))
	var slot_hint: String = "Slot type: %s. Compatible part tags: %s." % [
		str(slot.slot_type),
		", ".join(accepted_tag_strings),
	]
	label.tooltip_text = slot_hint
	picker.tooltip_text = slot_hint
	if not editable:
		var detail: Label = Label.new()
		detail.text = "Compatibility-mounted hardware"
		detail.add_theme_color_override("font_color", MUTED)
		detail.tooltip_text = "This slot is represented by the generic creator contract, but the current four-limb runtime does not yet install arbitrary Core attachments."
		body.add_child(detail)

	var editor_host: VBoxContainer = VBoxContainer.new()
	editor_host.add_theme_constant_override("separation", 7)
	body.add_child(editor_host)
	slot_editor_hosts[slot_id] = editor_host
	_rebuild_limb_editor(slot_id)
func _rebuild_limb_editor(slot_id: String) -> void:
	if current_draft == null or not slot_editor_hosts.has(slot_id):
		return
	var host: VBoxContainer = slot_editor_hosts.get(slot_id) as VBoxContainer
	if host == null:
		return
	for child: Node in host.get_children():
		child.queue_free()
	_clear_limb_editor_references(slot_id)
	var part: Resource = current_draft.equipped_part(StringName(slot_id))
	var limbs: Array[GenericLimbDefinition] = MLBodyLimbEditor.editable_limbs(part)
	if limbs.is_empty():
		return

	var separator: HSeparator = HSeparator.new()
	host.add_child(separator)
	var shape_header: HBoxContainer = HBoxContainer.new()
	shape_header.add_theme_constant_override("separation", 8)
	host.add_child(shape_header)
	var heading: Label = Label.new()
	var total_parts: int = 0
	for editable_limb: GenericLimbDefinition in limbs:
		if editable_limb != null:
			total_parts += editable_limb.segments.size()
	heading.text = "LIMB SHAPE  ·  %d %s" % [
		total_parts,
		"part" if total_parts == 1 else "parts",
	]
	heading.add_theme_color_override("font_color", ORANGE)
	heading.tooltip_text = "Edits the GenericLimbDefinition stored in this body draft—the same resource the physics runtime will build."
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_header.add_child(heading)
	var legacy_limb: bool = current_body_kind == "articulated_body" and part is GenericLimbDefinition
	var expanded: bool = bool(expanded_limb_editor_slots.get(slot_id, false)) and not legacy_limb
	var edit_shape_button: Button = _creator_button(
		"CLOSE EDITOR  ▴" if expanded else "EDIT IN 3D  ▾",
		false
	)
	edit_shape_button.toggle_mode = true
	edit_shape_button.button_pressed = expanded
	edit_shape_button.disabled = legacy_limb
	edit_shape_button.tooltip_text = (
		"The compatibility walker still maps this part through its fixed two-segment rig."
		if legacy_limb
		else "Open the interactive joint-pose, length, and thickness editor for this mounted limb."
	)
	edit_shape_button.toggled.connect(_on_limb_editor_expansion_toggled.bind(slot_id))
	shape_header.add_child(edit_shape_button)
	var hint: Label = Label.new()
	if legacy_limb:
		hint.text = "Fixed compatibility rig"
		hint.tooltip_text = "Use a drone Core attachment mount with Articulated Limb hardware for arbitrary serial-chain editing."
		hint.add_theme_color_override("font_color", MUTED)
		host.add_child(hint)
		return
	if not expanded:
		return
	hint.text = "Click a joint to pose its part and children; shape handles edit size."
	hint.tooltip_text = "Rotation rings pose the selected rigid part and every child. Each part keeps its own size and mass; changing part count changes model topology."
	hint.add_theme_color_override("font_color", MUTED)
	host.add_child(hint)

	for limb_index: int in range(limbs.size()):
		var limb: GenericLimbDefinition = limbs[limb_index]
		if limb == null:
			continue
		_build_single_limb_editor(host, slot_id, limb_index, limb)


func _on_limb_editor_expansion_toggled(expanded: bool, slot_id: String) -> void:
	if expanded:
		expanded_limb_editor_slots[slot_id] = true
	else:
		expanded_limb_editor_slots.erase(slot_id)
	_rebuild_limb_editor(slot_id)
	call_deferred("_refresh_creator_window_after_layout")


func _build_single_limb_editor(
	parent: VBoxContainer,
	slot_id: String,
	limb_index: int,
	limb: GenericLimbDefinition
) -> void:
	var editor_key: String = _limb_editor_key(slot_id, limb_index)
	var selected_index: int = clampi(
		int(limb_selected_segments.get(editor_key, 0)),
		0,
		maxi(limb.segments.size() - 1, 0)
	)
	limb_selected_segments[editor_key] = selected_index

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 7)
	parent.add_child(title_row)
	var title: Label = Label.new()
	title.text = "%s  ·  %d parts  ·  %.2f m reach" % [
		limb.limb_name if not limb.limb_name.strip_edges().is_empty() else "Limb %d" % (limb_index + 1),
		limb.segments.size(),
		limb.maximum_reach(),
	]
	title.add_theme_color_override("font_color", GREEN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = "A part is one rigid segment and its joint. Part count changes the limb's control and observation topology."
	title_row.add_child(title)
	var remove_part_button: Button = _creator_button("− PART", false)
	remove_part_button.disabled = limb.segments.size() <= 1
	remove_part_button.tooltip_text = "Remove the last rigid part from this serial limb."
	remove_part_button.pressed.connect(
		_on_limb_segment_count_delta_pressed.bind(-1, slot_id, limb_index)
	)
	title_row.add_child(remove_part_button)
	var add_part_button: Button = _creator_button("+ PART", false)
	add_part_button.tooltip_text = "Append a copy of the distal part with fresh, densely packed action indices."
	add_part_button.pressed.connect(
		_on_limb_segment_count_delta_pressed.bind(1, slot_id, limb_index)
	)
	title_row.add_child(add_part_button)

	var shape_editor: MLLimbShapeEditor3D = MLLimbShapeEditor3D.new()
	shape_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_editor.set_limb_definition(limb, selected_index)
	shape_editor.segment_selected.connect(
		_on_limb_shape_segment_selected.bind(slot_id, limb_index)
	)
	shape_editor.dimensions_change_requested.connect(
		_on_limb_shape_dimensions_requested.bind(slot_id, limb_index)
	)
	shape_editor.joint_pose_change_requested.connect(
		_on_limb_shape_joint_pose_requested.bind(slot_id, limb_index)
	)
	parent.add_child(shape_editor)
	limb_shape_editors[editor_key] = shape_editor

	var viewport_tools: HBoxContainer = HBoxContainer.new()
	viewport_tools.add_theme_constant_override("separation", 7)
	parent.add_child(viewport_tools)
	var viewport_hint: Label = Label.new()
	viewport_hint.text = "Click joint + drag RGB ring   ·   Shift snap   ·   ◇ length / □ thickness   ·   MMB orbit"
	viewport_hint.add_theme_color_override("font_color", MUTED)
	viewport_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_hint.tooltip_text = shape_editor.tooltip_text
	viewport_tools.add_child(viewport_hint)
	var reset_view_button: Button = _creator_button("RESET VIEW", false)
	reset_view_button.tooltip_text = "Frame this limb and restore the default camera angle."
	reset_view_button.pressed.connect(shape_editor.reset_view)
	viewport_tools.add_child(reset_view_button)

	var inspector_row: HBoxContainer = HBoxContainer.new()
	inspector_row.add_theme_constant_override("separation", 8)
	parent.add_child(inspector_row)
	var segment_picker: OptionButton = OptionButton.new()
	segment_picker.fit_to_longest_item = false
	segment_picker.custom_minimum_size.x = 220.0
	segment_picker.tooltip_text = "Select the rigid limb part to edit. You can also click it in the 3D view."
	for segment_index: int in range(limb.segments.size()):
		var segment: LimbSegmentDefinition = limb.segments[segment_index]
		var segment_name: String = (
			segment.segment_name
			if segment != null and not segment.segment_name.strip_edges().is_empty()
			else "Segment"
		)
		segment_picker.add_item("Part %d  ·  %s" % [segment_index + 1, segment_name])
	segment_picker.select(selected_index)
	segment_picker.item_selected.connect(
		_on_limb_shape_segment_selected.bind(slot_id, limb_index)
	)
	inspector_row.add_child(segment_picker)
	limb_segment_pickers[editor_key] = segment_picker

	var dimensions_label: Label = Label.new()
	dimensions_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dimensions_label.add_theme_color_override("font_color", GREEN)
	dimensions_label.tooltip_text = "Live dimensions from the 3D handles."
	inspector_row.add_child(dimensions_label)
	limb_dimension_labels[editor_key] = dimensions_label

	var mass_label: Label = Label.new()
	mass_label.text = "Mass"
	mass_label.tooltip_text = "Physical mass cannot be inferred from visible dimensions, so it remains an explicit material property."
	inspector_row.add_child(mass_label)
	var mass_input: SpinBox = SpinBox.new()
	mass_input.min_value = 0.01
	mass_input.max_value = 500.0
	mass_input.step = 0.01
	mass_input.suffix = " kg"
	mass_input.custom_minimum_size.x = 120.0
	mass_input.tooltip_text = mass_label.tooltip_text
	mass_input.value_changed.connect(
		_on_limb_selected_mass_changed.bind(slot_id, limb_index)
	)
	inspector_row.add_child(mass_input)
	limb_mass_inputs[editor_key] = mass_input
	_sync_limb_inspector(slot_id, limb_index)

	var effector_row: HBoxContainer = HBoxContainer.new()
	effector_row.add_theme_constant_override("separation", 8)
	parent.add_child(effector_row)
	var effector_label: Label = Label.new()
	effector_label.text = "Tip"
	effector_label.custom_minimum_size.x = 150.0
	effector_label.tooltip_text = "Optional terminal hardware mounted after the last segment, such as a passive foot or a model-controlled grip."
	effector_row.add_child(effector_label)
	var effector_picker: OptionButton = OptionButton.new()
	effector_picker.fit_to_longest_item = false
	effector_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effector_picker.tooltip_text = effector_label.tooltip_text
	effector_picker.add_item("None")
	effector_picker.set_item_metadata(0, "")
	var selected_effector_index: int = 0 if limb.end_effector == null else -1
	var templates: Array[LimbEndEffectorDefinition] = MLBodyLimbEditor.end_effector_templates()
	var matching_template_index: int = MLBodyLimbEditor.matching_end_effector_template_index(
		limb.end_effector,
		templates
	)
	for template_index: int in range(templates.size()):
		var template: LimbEndEffectorDefinition = templates[template_index]
		var option_index: int = effector_picker.item_count
		effector_picker.add_item(template.effector_name)
		effector_picker.set_item_metadata(option_index, MLBodyLimbEditor.end_effector_template_key(template))
		if template_index == matching_template_index:
			selected_effector_index = option_index
	if limb.end_effector != null and selected_effector_index < 0:
		selected_effector_index = effector_picker.item_count
		effector_picker.add_item("Current custom attachment")
		effector_picker.set_item_metadata(selected_effector_index, "__current_effector__")
	if selected_effector_index >= 0:
		effector_picker.select(selected_effector_index)
	effector_picker.item_selected.connect(
		_on_limb_end_effector_selected.bind(slot_id, limb_index, effector_picker)
	)
	effector_row.add_child(effector_picker)


func _on_limb_segment_count_delta_pressed(
	delta: int,
	slot_id: String,
	limb_index: int
) -> void:
	if current_draft == null:
		return
	var part: Resource = current_draft.equipped_part(StringName(slot_id))
	var limbs: Array[GenericLimbDefinition] = MLBodyLimbEditor.editable_limbs(part)
	if limb_index < 0 or limb_index >= limbs.size() or limbs[limb_index] == null:
		return
	var requested_count: int = maxi(limbs[limb_index].segments.size() + delta, 1)
	var error: String = MLBodyLimbEditor.set_segment_count(part, limb_index, requested_count)
	if not error.is_empty():
		_set_error(error)
		return
	var editor_key: String = _limb_editor_key(slot_id, limb_index)
	limb_selected_segments[editor_key] = mini(
		int(limb_selected_segments.get(editor_key, 0)),
		requested_count - 1
	)
	_mark_limb_slot_edited(slot_id, true)
	_rebuild_limb_editor(slot_id)


func _on_limb_shape_segment_selected(
	segment_index: int,
	slot_id: String,
	limb_index: int
) -> void:
	if suppress_limb_inspector_callbacks:
		return
	var editor_key: String = _limb_editor_key(slot_id, limb_index)
	limb_selected_segments[editor_key] = segment_index
	var editor: MLLimbShapeEditor3D = limb_shape_editors.get(editor_key) as MLLimbShapeEditor3D
	if editor != null:
		editor.set_selected_segment(segment_index)
	_sync_limb_inspector(slot_id, limb_index)


func _on_limb_shape_dimensions_requested(
	segment_index: int,
	length: float,
	radius: float,
	slot_id: String,
	limb_index: int
) -> void:
	if current_draft == null:
		return
	var part: Resource = current_draft.equipped_part(StringName(slot_id))
	var limbs: Array[GenericLimbDefinition] = MLBodyLimbEditor.editable_limbs(part)
	if limb_index < 0 or limb_index >= limbs.size():
		return
	var limb: GenericLimbDefinition = limbs[limb_index]
	if limb == null or segment_index < 0 or segment_index >= limb.segments.size():
		return
	var segment: LimbSegmentDefinition = limb.segments[segment_index]
	if segment == null:
		return
	var error: String = MLBodyLimbEditor.set_segment_dimensions(
		part,
		limb_index,
		segment_index,
		length,
		radius,
		segment.mass
	)
	if not error.is_empty():
		_set_error(error)
		return
	var editor_key: String = _limb_editor_key(slot_id, limb_index)
	var editor: MLLimbShapeEditor3D = limb_shape_editors.get(editor_key) as MLLimbShapeEditor3D
	if editor != null:
		editor.refresh_geometry()
	_sync_limb_inspector(slot_id, limb_index)
	_mark_limb_slot_edited(slot_id, false)


func _on_limb_shape_joint_pose_requested(
	segment_index: int,
	rest_directions: Array,
	joint_bases: Array,
	slot_id: String,
	limb_index: int
) -> void:
	if current_draft == null:
		return
	var part: Resource = current_draft.equipped_part(StringName(slot_id))
	var error: String = MLBodyLimbEditor.set_joint_subtree_pose(
		part,
		limb_index,
		segment_index,
		rest_directions,
		joint_bases
	)
	if not error.is_empty():
		_set_error(error)
		return
	var editor_key: String = _limb_editor_key(slot_id, limb_index)
	var editor: MLLimbShapeEditor3D = limb_shape_editors.get(editor_key) as MLLimbShapeEditor3D
	if editor != null:
		editor.refresh_geometry()
	_mark_limb_slot_edited(slot_id, false)


func _on_limb_selected_mass_changed(
	value: float,
	slot_id: String,
	limb_index: int
) -> void:
	if current_draft == null or suppress_limb_inspector_callbacks:
		return
	var part: Resource = current_draft.equipped_part(StringName(slot_id))
	var limbs: Array[GenericLimbDefinition] = MLBodyLimbEditor.editable_limbs(part)
	if limb_index < 0 or limb_index >= limbs.size():
		return
	var limb: GenericLimbDefinition = limbs[limb_index]
	var editor_key: String = _limb_editor_key(slot_id, limb_index)
	var segment_index: int = int(limb_selected_segments.get(editor_key, 0))
	if limb == null or segment_index < 0 or segment_index >= limb.segments.size():
		return
	var segment: LimbSegmentDefinition = limb.segments[segment_index]
	if segment == null:
		return
	var error: String = MLBodyLimbEditor.set_segment_dimensions(
		part,
		limb_index,
		segment_index,
		segment.length,
		segment.radius,
		value
	)
	if not error.is_empty():
		_set_error(error)
		return
	_mark_limb_slot_edited(slot_id, false)


func _sync_limb_inspector(slot_id: String, limb_index: int) -> void:
	if current_draft == null:
		return
	var part: Resource = current_draft.equipped_part(StringName(slot_id))
	var limbs: Array[GenericLimbDefinition] = MLBodyLimbEditor.editable_limbs(part)
	if limb_index < 0 or limb_index >= limbs.size():
		return
	var limb: GenericLimbDefinition = limbs[limb_index]
	var editor_key: String = _limb_editor_key(slot_id, limb_index)
	var segment_index: int = clampi(
		int(limb_selected_segments.get(editor_key, 0)),
		0,
		maxi(limb.segments.size() - 1, 0)
	)
	limb_selected_segments[editor_key] = segment_index
	if limb == null or segment_index < 0 or segment_index >= limb.segments.size():
		return
	var segment: LimbSegmentDefinition = limb.segments[segment_index]
	if segment == null:
		return
	suppress_limb_inspector_callbacks = true
	var picker: OptionButton = limb_segment_pickers.get(editor_key) as OptionButton
	if picker != null and picker.selected != segment_index:
		picker.select(segment_index)
	var dimension_label: Label = limb_dimension_labels.get(editor_key) as Label
	if dimension_label != null:
		dimension_label.text = "%.2f m long   ·   Ø %.3f m" % [segment.length, segment.radius * 2.0]
	var mass_input: SpinBox = limb_mass_inputs.get(editor_key) as SpinBox
	if mass_input != null and not is_equal_approx(mass_input.value, segment.mass):
		mass_input.value = segment.mass
	suppress_limb_inspector_callbacks = false


func _limb_editor_key(slot_id: String, limb_index: int) -> String:
	return "%s:%d" % [slot_id, limb_index]


func _clear_limb_editor_references(slot_id: String) -> void:
	var prefix: String = "%s:" % slot_id
	for key_value: Variant in limb_shape_editors.keys():
		var key: String = str(key_value)
		if not key.begins_with(prefix):
			continue
		limb_shape_editors.erase(key)
		limb_segment_pickers.erase(key)
		limb_dimension_labels.erase(key)
		limb_mass_inputs.erase(key)


func _on_limb_end_effector_selected(
	index: int,
	slot_id: String,
	limb_index: int,
	picker: OptionButton
) -> void:
	if current_draft == null or picker == null or index < 0 or index >= picker.item_count:
		return
	var key: String = str(picker.get_item_metadata(index))
	if key == "__current_effector__":
		return
	var template: LimbEndEffectorDefinition = null
	if not key.is_empty():
		template = load(key) as LimbEndEffectorDefinition
		if template == null:
			_set_error("The selected foot-end attachment resource is no longer available.")
			return
	var part: Resource = current_draft.equipped_part(StringName(slot_id))
	var error: String = MLBodyLimbEditor.set_end_effector(part, limb_index, template)
	if not error.is_empty():
		_set_error(error)
		return
	_mark_limb_slot_edited(slot_id, true)
	_rebuild_limb_editor(slot_id)


func _mark_limb_slot_edited(slot_id: String, topology_changed: bool = false) -> void:
	changed_slot_ids[slot_id] = true
	status_label.text = "Limb draft updated."
	status_label.tooltip_text = "The edited GenericLimbDefinition will be copied directly into the runtime body."
	status_label.add_theme_color_override("font_color", MUTED)
	if topology_changed:
		_refresh_training_settings_for_body(false)
		_refresh_summary()


func _on_slot_part_selected(index: int, slot_id: String) -> void:
	if current_draft == null or not slot_pickers.has(slot_id):
		return
	var picker: OptionButton = slot_pickers[slot_id] as OptionButton
	if picker == null or index < 0 or index >= picker.item_count:
		return
	var key: String = str(picker.get_item_metadata(index))
	var changed: bool = key != str(initial_slot_keys.get(slot_id, EMPTY_KEY))
	if changed:
		changed_slot_ids[slot_id] = true
	else:
		changed_slot_ids.erase(slot_id)
	if key == EMPTY_KEY:
		current_draft.unequip(StringName(slot_id))
	elif key.begins_with(SAME_AS_KEY_PREFIX):
		var source_slot_id: String = key.substr(SAME_AS_KEY_PREFIX.length())
		var target_slot: MLBodySlotDefinition = current_draft.slot_definition(StringName(slot_id))
		var source_slot: MLBodySlotDefinition = current_draft.slot_definition(
			StringName(source_slot_id)
		)
		var source_part: Resource = current_draft.equipped_part(StringName(source_slot_id))
		if (
			target_slot == null
			or source_slot == null
			or source_slot.slot_id == target_slot.slot_id
			or source_slot.slot_type != target_slot.slot_type
			or source_part == null
			or not target_slot.accepts(source_part)
			or MLBodyLimbEditor.editable_limbs(source_part).is_empty()
		):
			_set_error("That source limb is no longer available for this slot.")
			_rebuild_slot_rows()
			return
		var copied_limb_part: Resource = MLBodyPartContract.deep_duplicate_resource(source_part)
		if copied_limb_part == null or not current_draft.equip(
			StringName(slot_id),
			copied_limb_part
		):
			_set_error(
				current_draft.last_error
				if not current_draft.last_error.is_empty()
				else "The modeled limb could not be copied."
			)
			return
		status_label.text = "Copied %s to %s. Mount preserved." % [
			source_slot.display_name,
			target_slot.display_name,
		]
		status_label.tooltip_text = "This is an independent copy: editing either limb later will not silently change the other."
		status_label.add_theme_color_override("font_color", MUTED)
		_rebuild_slot_rows()
		_refresh_training_settings_for_body(false)
		_refresh_summary()
		return
	else:
		var part_map: Dictionary = slot_parts.get(slot_id, {})
		var source_part: Resource = part_map.get(key) as Resource
		if source_part == null:
			_set_error("The selected part is no longer available.")
			return
		var copied_part: Resource = MLBodyPartContract.deep_duplicate_resource(source_part)
		if not current_draft.equip(StringName(slot_id), copied_part):
			_set_error(current_draft.last_error)
			return
	status_label.text = ""
	status_label.tooltip_text = ""
	status_label.add_theme_color_override("font_color", MUTED)
	# Other dropdowns gain or lose their live "Same as …" sources when this slot changes.
	_rebuild_slot_rows()
	_refresh_training_settings_for_body(false)
	_refresh_summary()


func _refresh_summary() -> void:
	if summary_label == null:
		return
	if current_draft == null:
		summary_label.text = "No body selected."
		return
	if creator_stage == STAGE_CORE_LAYOUT:
		var core_name: String = MLBodyPartCatalog.display_name(_current_physical_core())
		if current_body_kind == "drone":
			summary_label.text = "%s   ·   %d mounts   ·   P %d   ·   A %d" % [
				core_name,
				layout_slot_transforms.size(),
				_layout_slot_kind_count(&"propeller"),
				_layout_slot_kind_count(&"attachment"),
			]
			summary_label.tooltip_text = "Every mount becomes an explicit slot in the accepted body contract."
		else:
			summary_label.text = "Core: %s   •   this runtime currently uses its authored fixed mount topology" % core_name
		return
	var snapshot: Dictionary = current_draft.ui_snapshot()
	var algorithm_name: String = (
		algorithm_picker.get_item_text(algorithm_picker.selected)
		if algorithm_picker != null and algorithm_picker.selected >= 0
		else "PPO"
	)
	var reward_name: String = str(_selected_reward_cardset().get("display_name", "Custom rewards"))
	summary_label.text = "%d controls   ·   %d observations   ·   %d slots   ·   %s   ·   %d workers   ·   %s Hz" % [
		int(snapshot.get("preview_control_count", 0)),
		int(snapshot.get("preview_observation_count", 0)),
		int(snapshot.get("slot_count", 0)),
		algorithm_name,
		int(round(worker_count_input.value)),
		String.num(control_rate_input.value, 0),
	]
	summary_label.tooltip_text = "Network: %d × %d hidden layers. Rewards: %s. Group %s." % [
		int(round(hidden_width_input.value)),
		int(round(hidden_depth_input.value)),
		reward_name,
		"starts immediately" if start_training_checkbox.button_pressed else "starts paused",
	]


func _accept_current_build() -> void:
	if current_draft == null:
		_set_error("Choose a Core first.")
		return
	var missing_required_slot: String = _missing_required_slot_name()
	if not missing_required_slot.is_empty():
		_set_error("Select hardware for required slot: %s." % missing_required_slot)
		return
	var runtime_body: Resource = MLBodyCreatorRuntimeFactory.runtime_from_draft(
		current_preset_id,
		current_draft,
		changed_slot_ids
	)
	if runtime_body == null:
		_set_error(MLBodyCreatorRuntimeFactory.last_error)
		return
	var accepted_draft: MLBodyBuildDraft = current_draft.duplicate_editable()
	var manifest: MLBodyInterfaceManifest = accepted_draft.accept_build()
	if manifest == null:
		_set_error(accepted_draft.last_error)
		return
	var runtime_manifest: MLBodyInterfaceManifest = MLBodyCreatorRuntimeFactory.runtime_manifest(runtime_body)
	if runtime_manifest == null:
		_set_error("The selected parts could not be represented by the training runtime.")
		return
	if runtime_body is DroneLoadout:
		var readiness_error: String = DroneTrainingLoadoutConfig.training_readiness_error(
			runtime_body as DroneLoadout,
			runtime_manifest
		)
		if not readiness_error.is_empty():
			# Keep the creator and its draft open so the mount layout/hardware can be corrected;
			# emitting a doomed request would close the Window and discard the authored body.
			_set_error(readiness_error)
			return
	if runtime_manifest.contract_signature != manifest.contract_signature:
		_set_error("The gameplay body does not reproduce the accepted neural contract; the group was not created.")
		return
	var requested_name: String = group_name_input.text.strip_edges()
	if requested_name.is_empty():
		requested_name = "Model worker group"
	create_requested.emit({
		"preset_id": str(current_preset_id),
		"body_kind": current_body_kind,
		"name": requested_name,
		"runtime_body": runtime_body,
		"body_interface": manifest.to_dictionary(),
		"body_interface_signature": manifest.contract_signature,
		"training": _training_request(),
	})
	# This Window is reused by the room. A completed body must not become the implicit starting
	# point for the next + click; in particular its reduced custom Core slot count belongs only to
	# the group we just emitted. Cancel/close still preserves an unfinished draft.
	current_draft = null
	layout_slot_transforms.clear()
	layout_slot_kinds.clear()
	layout_slot_surface_normals.clear()
	layout_selected_slot_index = -1
	changed_slot_ids.clear()
	initial_slot_keys.clear()
	slot_parts.clear()
	hide()


func _missing_required_slot_name() -> String:
	if current_draft == null:
		return ""
	for entry: Dictionary in current_draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot == null or not _slot_is_required(slot):
			continue
		var equipped_part: Resource = entry.get("part") as Resource
		if equipped_part == null:
			return slot.display_name
	return ""


func _slot_is_required(slot: MLBodySlotDefinition) -> bool:
	var slot_type: String = str(slot.slot_type)
	# A drone attachment slot exists only because the creator explicitly placed that mount in Step 1.
	# Leaving it empty would create a different body than the layout the user just authored; delete
	# the slot in the Core-layout stage instead when no attachment should exist there.
	if current_body_kind == "drone" and slot_type == "attachment":
		return true
	return slot_type in ["battery", "propeller", "limb", "gun"]


func _slot_runtime_edit_supported(slot: MLBodySlotDefinition) -> bool:
	if current_body_kind == "articulated_body" and str(slot.slot_type) == "attachment":
		return false
	return true


func _set_error(message: String) -> void:
	status_label.text = message if not message.strip_edges().is_empty() else "Body creation failed."
	status_label.add_theme_color_override("font_color", Color("ff8f7a"))


func _creator_button(text: String, accent: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	var normal_style: StyleBoxFlat = DroneTrainingRoomPresentation.scanner_button_style(accent)
	var hover_style: StyleBoxFlat = normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = normal_style.bg_color.lightened(0.09)
	hover_style.border_color = normal_style.border_color.lightened(0.12)
	var pressed_style: StyleBoxFlat = normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = normal_style.bg_color.darkened(0.10)
	pressed_style.border_color = ORANGE if accent else GREEN
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", hover_style)
	return button
