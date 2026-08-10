class_name MLBodyCreatorPanel
extends Window

signal create_requested(request: Dictionary)

const ORANGE: Color = Color("ffad42")
const GREEN: Color = Color("54e6b1")
const MUTED: Color = Color("a8d8c1")
const EMPTY_KEY: String = "__empty__"
const CURRENT_KEY_PREFIX: String = "__current__:"
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(1040, 820)
const WINDOW_EDGE_MARGIN_PX: int = 36
const STAGE_CORE_LAYOUT: int = 0
const STAGE_HARDWARE: int = 1
const MINIMUM_SLOT_SPACING_M: float = 0.075

var root_panel: PanelContainer
var window_layout: VBoxContainer
var content_scroll: ScrollContainer
var root_content: VBoxContainer
var footer_panel: PanelContainer
var stage_label: Label
var layout_stage: VBoxContainer
var hardware_stage: VBoxContainer
var preset_row: HBoxContainer
var core_row: HBoxContainer
var layout_preview: MLBodyCoreLayoutPreview
var layout_slot_count_label: Label
var layout_selected_label: Label
var mirror_next_checkbox: CheckBox
var back_button: Button
var cancel_button: Button
var preset_picker: OptionButton
var core_picker: OptionButton
var group_name_input: LineEdit
var description_label: Label
var core_label: Label
var slots_content: VBoxContainer
var summary_label: Label
var status_label: Label
var create_button: Button
var training_settings_panel: PanelContainer
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
var initial_slot_keys: Dictionary = {}
var changed_slot_ids: Dictionary = {}
var core_parts: Dictionary = {}
var reward_cardsets: Dictionary = {}
var reward_cardset_library: TrainingRewardCardsetLibrary = TrainingRewardCardsetLibrary.new()
var suppress_training_ui_callbacks: bool = false
var creator_stage: int = STAGE_CORE_LAYOUT
var layout_attachment_capacity: int = 0
var layout_attachment_transforms: Array[Transform3D] = []
var layout_selected_slot_index: int = -1


func _ready() -> void:
	title = "Model Body Creator"
	size = DEFAULT_WINDOW_SIZE
	min_size = Vector2i(680, 560)
	unresizable = false
	transient = true
	exclusive = false
	close_requested.connect(hide)
	_build_ui()
	_populate_presets()
	hide()


func open_creator() -> void:
	if preset_picker == null:
		return
	if preset_picker.item_count > 0 and current_draft == null:
		preset_picker.select(0)
		_load_preset_at(0)
	_set_creator_stage(STAGE_CORE_LAYOUT)
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

	var heading: Label = Label.new()
	heading.text = "MODEL BODY CREATOR"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", ORANGE)
	heading.tooltip_text = "Build a physical worker body from the same serialized parts used by gameplay and training."
	root.add_child(heading)

	stage_label = Label.new()
	stage_label.add_theme_font_size_override("font_size", 16)
	stage_label.add_theme_color_override("font_color", GREEN)
	root.add_child(stage_label)

	var intro: Label = Label.new()
	intro.text = "First lay out the physical Core and its mount points. Then assign actual saved hardware and training settings."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", MUTED)
	root.add_child(intro)

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

	preset_row = HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	identity.add_child(preset_row)
	var preset_label: Label = Label.new()
	preset_label.text = "Body family"
	preset_label.custom_minimum_size.x = 120.0
	preset_row.add_child(preset_label)
	preset_picker = OptionButton.new()
	preset_picker.fit_to_longest_item = false
	preset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_picker.item_selected.connect(_on_preset_selected)
	preset_row.add_child(preset_picker)

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
	core_picker.item_selected.connect(_on_core_selected)
	core_row.add_child(core_picker)

	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_color_override("font_color", MUTED)
	identity.add_child(description_label)
	core_label = Label.new()
	core_label.add_theme_color_override("font_color", GREEN)
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
	layout_preview = MLBodyCoreLayoutPreview.new()
	layout_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_preview.surface_clicked.connect(_on_layout_surface_clicked)
	layout_preview.slot_selected.connect(_on_layout_slot_selected)
	preview_body.add_child(layout_preview)

	var preview_hint: Label = Label.new()
	preview_hint.text = "Left-click the Core to place a universal attachment slot. Click a marker to select it. Right-drag rotates the view; Ctrl+wheel zooms. Normal wheel scrolling still scrolls the creator."
	preview_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_hint.add_theme_color_override("font_color", MUTED)
	preview_body.add_child(preview_hint)

	var slot_controls: HBoxContainer = HBoxContainer.new()
	slot_controls.add_theme_constant_override("separation", 7)
	preview_body.add_child(slot_controls)
	var mirror_selected: Button = _creator_button("MIRROR SELECTED", false)
	mirror_selected.pressed.connect(_mirror_selected_layout_slot)
	slot_controls.add_child(mirror_selected)
	var delete_selected: Button = _creator_button("DELETE SELECTED", false)
	delete_selected.pressed.connect(_delete_selected_layout_slot)
	slot_controls.add_child(delete_selected)
	var reset_view_button: Button = _creator_button("RESET VIEW", false)
	reset_view_button.pressed.connect(func() -> void:
		if layout_preview != null:
			layout_preview.reset_view()
	)
	slot_controls.add_child(reset_view_button)
	mirror_next_checkbox = CheckBox.new()
	mirror_next_checkbox.text = "Mirror next placement"
	mirror_next_checkbox.tooltip_text = "Places a second slot mirrored across the Core's local X axis when capacity allows."
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
	group_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(group_name_input)

	_build_training_settings(hardware_stage)

	var parts_heading: Label = Label.new()
	parts_heading.text = "HARDWARE ASSIGNMENT"
	parts_heading.add_theme_font_size_override("font_size", 17)
	parts_heading.add_theme_color_override("font_color", ORANGE)
	hardware_stage.add_child(parts_heading)
	var parts_note: Label = Label.new()
	parts_note.text = "The Core layout is frozen for this step. Newly created slots begin empty; choose a compatible saved part for every required slot."
	parts_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parts_note.add_theme_color_override("font_color", MUTED)
	hardware_stage.add_child(parts_note)

	slots_content = VBoxContainer.new()
	slots_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	slots_content.add_theme_constant_override("separation", 7)
	hardware_stage.add_child(slots_content)

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
			"STEP 2 / 2  ·  HARDWARE + TRAINING"
			if creator_stage == STAGE_HARDWARE
			else "STEP 1 / 2  ·  CORE + SLOT LAYOUT"
		)
	if back_button != null:
		back_button.visible = creator_stage == STAGE_HARDWARE
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
	status_label.text = "Core layout editing reopened. Accepting the layout again rebuilds the hardware list empty."
	status_label.add_theme_color_override("font_color", MUTED)
	_set_creator_stage(STAGE_CORE_LAYOUT)
	_refresh_layout_preview()


func _initialize_layout_for_current_core() -> void:
	layout_attachment_transforms.clear()
	layout_selected_slot_index = -1
	layout_attachment_capacity = 0
	var physical_core: Resource = _current_physical_core()
	if physical_core is DroneCoreDefinition:
		layout_attachment_capacity = maxi((physical_core as DroneCoreDefinition).attachment_slot_count, 0)
	if layout_preview != null:
		layout_preview.set_core_resource(physical_core)
		layout_preview.placement_enabled = current_body_kind == "drone" and layout_attachment_capacity > 0
	_refresh_layout_preview()


func _refresh_layout_preview() -> void:
	if layout_preview != null:
		layout_preview.set_slot_transforms(layout_attachment_transforms, layout_selected_slot_index)
	if layout_slot_count_label != null:
		if current_body_kind == "drone":
			layout_slot_count_label.text = "Attachment slots: %d / %d placed" % [
				layout_attachment_transforms.size(),
				layout_attachment_capacity,
			]
		else:
			layout_slot_count_label.text = "Free Core slot placement is currently available for drone Cores."
	if layout_selected_label != null:
		if layout_selected_slot_index >= 0 and layout_selected_slot_index < layout_attachment_transforms.size():
			var mount: Transform3D = layout_attachment_transforms[layout_selected_slot_index]
			layout_selected_label.text = "Selected attachment slot %d  ·  local mount (%.2f, %.2f, %.2f)" % [
				layout_selected_slot_index + 1,
				mount.origin.x,
				mount.origin.y,
				mount.origin.z,
			]
		else:
			layout_selected_label.text = "No attachment slot selected."
	_refresh_summary()


func _on_layout_surface_clicked(mount_transform: Transform3D) -> void:
	if current_body_kind != "drone":
		return
	var mirror_pair: bool = mirror_next_checkbox != null and mirror_next_checkbox.button_pressed
	var required_capacity: int = 2 if mirror_pair else 1
	if layout_attachment_transforms.size() + required_capacity > layout_attachment_capacity:
		_set_error(
			"Mirror placement needs two free attachment slots on this Core."
			if mirror_pair
			else "This Core supports at most %d creator attachment slots." % layout_attachment_capacity
		)
		return
	if _layout_slot_too_close(mount_transform.origin):
		_set_error("That attachment slot overlaps an existing mount. Pick a different point on the Core.")
		return
	var mirrored: Transform3D = Transform3D.IDENTITY
	if mirror_pair:
		mirrored = _mirrored_layout_transform(mount_transform)
		if mirrored.origin.distance_to(mount_transform.origin) <= 0.02:
			_set_error("Mirror placement needs a point away from the Core's center plane.")
			return
		if _layout_slot_too_close(mirrored.origin):
			_set_error("The mirrored mount overlaps an existing attachment slot.")
			return
	layout_attachment_transforms.append(mount_transform)
	layout_selected_slot_index = layout_attachment_transforms.size() - 1
	if mirror_pair:
		layout_attachment_transforms.append(mirrored)
		layout_selected_slot_index = layout_attachment_transforms.size() - 1
	status_label.text = ""
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_layout_preview()


func _on_layout_slot_selected(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= layout_attachment_transforms.size():
		return
	layout_selected_slot_index = slot_index
	_refresh_layout_preview()


func _mirror_selected_layout_slot() -> void:
	if layout_selected_slot_index < 0 or layout_selected_slot_index >= layout_attachment_transforms.size():
		_set_error("Select an attachment-slot marker first.")
		return
	if layout_attachment_transforms.size() >= layout_attachment_capacity:
		_set_error("This Core has no unused attachment-slot capacity to mirror into.")
		return
	var source: Transform3D = layout_attachment_transforms[layout_selected_slot_index]
	var mirrored: Transform3D = _mirrored_layout_transform(source)
	if mirrored.origin.distance_to(source.origin) <= 0.02:
		_set_error("A slot on the mirror plane has no distinct left/right counterpart.")
		return
	if _layout_slot_too_close(mirrored.origin):
		_set_error("The mirrored mount already overlaps an existing attachment slot.")
		return
	layout_attachment_transforms.append(mirrored)
	layout_selected_slot_index = layout_attachment_transforms.size() - 1
	status_label.text = "Mirrored the selected slot across the Core's local X axis."
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_layout_preview()


func _delete_selected_layout_slot() -> void:
	if layout_selected_slot_index < 0 or layout_selected_slot_index >= layout_attachment_transforms.size():
		_set_error("Select an attachment-slot marker first.")
		return
	layout_attachment_transforms.remove_at(layout_selected_slot_index)
	layout_selected_slot_index = mini(layout_selected_slot_index, layout_attachment_transforms.size() - 1)
	status_label.text = "Attachment slot removed. Remaining slots were renumbered in layout order."
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_layout_preview()


func _layout_slot_too_close(position: Vector3) -> bool:
	for existing: Transform3D in layout_attachment_transforms:
		if existing.origin.distance_to(position) < MINIMUM_SLOT_SPACING_M:
			return true
	return false


func _mirrored_layout_transform(source: Transform3D) -> Transform3D:
	var mirrored_origin: Vector3 = source.origin
	mirrored_origin.x = -mirrored_origin.x
	var surface_normal: Vector3 = -source.basis.y.normalized()
	surface_normal.x = -surface_normal.x
	var mirrored_basis: Basis = _slot_basis_from_surface_normal(surface_normal)
	return Transform3D(mirrored_basis, mirrored_origin)


func _slot_basis_from_surface_normal(surface_normal: Vector3) -> Basis:
	var normal: Vector3 = surface_normal.normalized()
	if normal.length_squared() <= 0.000001:
		normal = Vector3.DOWN
	var y_axis: Vector3 = -normal
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
		var core_copy: DroneCoreDefinition = (
			MLBodyPartContract.deep_duplicate_resource(source_core) as DroneCoreDefinition
		)
		if core_copy == null:
			_set_error("The selected Core could not be copied into the hardware stage.")
			return
		core_copy.attachment_slot_count = layout_attachment_transforms.size()
		var empty_loadout: DroneLoadout = DroneLoadout.new()
		empty_loadout.install_core(core_copy)
		for slot_index: int in range(layout_attachment_transforms.size()):
			if not empty_loadout.set_attachment_slot_transform(
				slot_index,
				layout_attachment_transforms[slot_index]
			):
				_set_error("Attachment-slot layout %d could not be transferred to the runtime body." % (slot_index + 1))
				return
		var next_draft: MLBodyBuildDraft = DroneMLBodyInterfaceFactory.create_draft(empty_loadout)
		if next_draft == null or next_draft.core == null or not next_draft.last_error.is_empty():
			_set_error("The accepted Core layout could not create an empty hardware draft.")
			return
		next_draft.core_contract["preset_id"] = str(current_preset_id)
		current_draft = next_draft
		changed_slot_ids.clear()
		initial_slot_keys.clear()
		slot_parts.clear()
		_rebuild_slot_rows()
		_refresh_training_settings_for_body(true)
	else:
		# The staged UI is shared now, but arbitrary mount placement is intentionally not faked for
		# body families whose physics runtimes do not yet consume generic Core mount transforms. Their
		# authored topology is retained, while every runtime-editable hardware slot still begins empty.
		for entry: Dictionary in current_draft.slots:
			var authored_slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
			if authored_slot != null and _slot_runtime_edit_supported(authored_slot):
				current_draft.unequip(authored_slot.slot_id)
		changed_slot_ids.clear()
		initial_slot_keys.clear()
		slot_parts.clear()
		_rebuild_slot_rows()
		_refresh_training_settings_for_body(true)
	status_label.text = "Core layout accepted. Assign hardware to the empty slots below."
	status_label.add_theme_color_override("font_color", MUTED)
	_set_creator_stage(STAGE_HARDWARE)
	_refresh_summary()


func _build_training_settings(root: VBoxContainer) -> void:
	var heading: Label = Label.new()
	heading.text = "TRAINING SETUP"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", ORANGE)
	root.add_child(heading)

	training_settings_panel = PanelContainer.new()
	training_settings_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	root.add_child(training_settings_panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	training_settings_panel.add_child(body)

	var algorithm_row: HBoxContainer = HBoxContainer.new()
	algorithm_row.add_theme_constant_override("separation", 8)
	body.add_child(algorithm_row)
	var algorithm_label: Label = Label.new()
	algorithm_label.text = "Learning algorithm"
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
	start_training_checkbox.tooltip_text = "Off creates the worker group paused so you can inspect or tune it before any episode starts."
	body.add_child(start_training_checkbox)
	var branch_note: Label = Label.new()
	branch_note.text = "Fresh bodies start with random weights. Saved-model sources and weight variation stay under BRANCH VARIANT so incompatible body contracts cannot be mixed accidentally."
	branch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	branch_note.add_theme_color_override("font_color", MUTED)
	body.add_child(branch_note)
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
		var control_count: int = int(current_draft.ui_snapshot().get("preview_control_count", 0)) if current_draft != null else 0
		var selected_valid_index: int = -1
		var ppo_index: int = -1
		for descriptor: Dictionary in DroneTrainingAlgorithmCatalog.descriptors():
			var index: int = algorithm_picker.item_count
			var descriptor_id: String = str(descriptor.get("id", "ppo_clip"))
			algorithm_picker.add_item(str(descriptor.get("display_name", "Learning algorithm")))
			algorithm_picker.set_item_metadata(index, descriptor_id)
			algorithm_picker.set_item_tooltip(index, str(descriptor.get("description", "")))
			var supported: bool = descriptor_id == "ppo_clip" or control_count == 4
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
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _training_request() -> Dictionary:
	var algorithm_id: String = _selected_algorithm_id()
	var reward_cardset: Dictionary = _selected_reward_cardset()
	var reward_cards_value: Variant = reward_cardset.get("cards", {})
	var reward_cards: Dictionary = (
		(reward_cards_value as Dictionary).duplicate(true)
		if reward_cards_value is Dictionary
		else {}
	)
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


func _populate_presets() -> void:
	preset_picker.clear()
	var presets: Array[MLBodyPreset] = MLBodyPresetLibrary.built_in_presets()
	for preset: MLBodyPreset in presets:
		var index: int = preset_picker.item_count
		preset_picker.add_item(preset.display_name)
		preset_picker.set_item_metadata(index, str(preset.preset_id))
	if preset_picker.item_count > 0:
		preset_picker.select(0)
		_load_preset_at(0)


func _on_preset_selected(index: int) -> void:
	_load_preset_at(index)


func _load_preset_at(index: int) -> void:
	if index < 0 or index >= preset_picker.item_count:
		return
	var preset_id: StringName = StringName(str(preset_picker.get_item_metadata(index)))
	var preset: MLBodyPreset = MLBodyPresetLibrary.preset_by_id(preset_id)
	if preset == null:
		_set_error("The selected body preset could not be loaded.")
		return
	var draft: MLBodyBuildDraft = preset.instantiate_draft()
	if draft == null or draft.core == null or not draft.last_error.is_empty():
		_set_error("The selected body preset could not create an editable draft.")
		return
	current_preset_id = preset_id
	current_draft = draft
	current_body_kind = str(draft.core_contract.get("body_kind", preset.body_kind))
	changed_slot_ids.clear()
	initial_slot_keys.clear()
	status_label.text = ""
	status_label.add_theme_color_override("font_color", MUTED)
	slot_parts.clear()
	description_label.text = preset.description
	core_label.text = "Core: %s   •   Family: %s" % [
		str(draft.ui_snapshot().get("core_name", "Core")),
		current_body_kind.replace("_", " ").capitalize(),
	]
	group_name_input.text = "%s group" % preset.display_name
	_refresh_training_settings_for_body(true)
	_populate_core_picker()
	_initialize_layout_for_current_core()
	_set_creator_stage(STAGE_CORE_LAYOUT)
	_refresh_summary()


func _populate_core_picker() -> void:
	core_picker.clear()
	core_parts.clear()
	var current_core: Resource = _current_physical_core()
	if current_core == null:
		core_picker.add_item("No compatible physical Core")
		core_picker.disabled = true
		return
	core_picker.disabled = false
	var current_key: String = CURRENT_KEY_PREFIX + "core"
	core_parts[current_key] = MLBodyPartContract.deep_duplicate_resource(current_core)
	core_picker.add_item("%s  • current" % MLBodyPartCatalog.display_name(current_core))
	core_picker.set_item_metadata(0, current_key)
	core_picker.select(0)
	var current_source: String = MLBodyPartContract.resource_source_path(current_core)
	for part: Resource in MLBodyPartCatalog.all_parts():
		if not _same_core_family(part, current_core):
			continue
		var source_path: String = MLBodyPartContract.resource_source_path(part)
		if source_path.is_empty() or source_path == current_source or core_parts.has(source_path):
			continue
		core_parts[source_path] = part
		var option_index: int = core_picker.item_count
		var label: String = "%s   [%s]" % [
			MLBodyPartCatalog.display_name(part),
			source_path.get_base_dir().get_file(),
		]
		if part is DroneCoreDefinition and (part as DroneCoreDefinition).propeller_slot_count != 4:
			label += "   • 4-prop trainer required"
		core_picker.add_item(label)
		core_picker.set_item_metadata(option_index, source_path)
		if part is DroneCoreDefinition and (part as DroneCoreDefinition).propeller_slot_count != 4:
			core_picker.set_item_disabled(option_index, true)


func _on_core_selected(index: int) -> void:
	if current_draft == null or index < 0 or index >= core_picker.item_count:
		return
	var key: String = str(core_picker.get_item_metadata(index))
	if key.begins_with(CURRENT_KEY_PREFIX):
		return
	var selected_core: Resource = core_parts.get(key) as Resource
	if selected_core == null:
		_set_error("The selected Core is no longer available.")
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
			MLBodyPresetLibrary.instantiate_runtime_template(current_preset_id) as TurretLoadout
		)
		if source_turret != null:
			source_turret.base = (
				MLBodyPartContract.deep_duplicate_resource(selected_core) as TurretBaseDefinition
			)
			next_draft = TurretMLBodyInterfaceFactory.create_draft(source_turret)
	else:
		_set_error("This body family does not support swapping that Core yet.")
		_populate_core_picker()
		return
	if next_draft == null or next_draft.core == null or not next_draft.last_error.is_empty():
		_set_error("The selected Core could not rebuild the body slot topology.")
		_populate_core_picker()
		return
	next_draft.core_contract["preset_id"] = str(current_preset_id)
	current_draft = next_draft
	changed_slot_ids.clear()
	initial_slot_keys.clear()
	slot_parts.clear()
	status_label.text = "Core changed. Place the attachment slots you want on its 3D surface."
	status_label.add_theme_color_override("font_color", MUTED)
	core_label.text = "Core: %s   •   Family: %s" % [
		MLBodyPartCatalog.display_name(_current_physical_core()),
		current_body_kind.replace("_", " ").capitalize(),
	]
	_populate_core_picker()
	_initialize_layout_for_current_core()
	_refresh_training_settings_for_body(false)
	_refresh_summary()


func _current_physical_core() -> Resource:
	if current_draft == null or current_draft.core == null:
		return null
	if current_draft.core is MLBodyCoreDefinition:
		return (current_draft.core as MLBodyCoreDefinition).physical_core
	return current_draft.core


func _same_core_family(candidate: Resource, current_core: Resource) -> bool:
	if candidate == null or current_core == null:
		return false
	if current_core is DroneCoreDefinition:
		return candidate is DroneCoreDefinition
	if current_core is TurretBaseDefinition:
		return candidate is TurretBaseDefinition
	if current_core is MLRigidCorePartDefinition:
		return candidate is MLRigidCorePartDefinition
	return candidate.get_script() == current_core.get_script()


func _rebuild_slot_rows() -> void:
	for child: Node in slots_content.get_children():
		child.queue_free()
	slot_pickers.clear()
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
			picker.add_item("%s   [%s]" % [
				_creator_part_label(part),
				source_path.get_base_dir().get_file(),
			])
			picker.set_item_metadata(option_index, source_path)
	if selected_index >= 0:
		picker.select(selected_index)
	initial_slot_keys[slot_id] = selected_key
	picker.disabled = not editable
	picker.item_selected.connect(_on_slot_part_selected.bind(slot_id))

	var detail: Label = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", MUTED)
	var accepted_tags: Array = slot.contract_dictionary().get("accepted_part_tags", [])
	var accepted_tag_strings: PackedStringArray = PackedStringArray()
	for accepted_tag_value: Variant in accepted_tags:
		accepted_tag_strings.append(str(accepted_tag_value))
	detail.text = "Slot: %s   •   accepts: %s" % [
		str(slot.slot_type),
		", ".join(accepted_tag_strings),
	]
	if not editable:
		detail.text += "   •   read-only in this first runtime pass"
		detail.tooltip_text = "This slot is represented by the generic creator contract, but the current four-limb runtime does not yet install arbitrary Core attachments."
	body.add_child(detail)


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
	status_label.add_theme_color_override("font_color", MUTED)
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
			summary_label.text = "Core: %s   •   %d/%d attachment slots placed   •   right-drag to orbit" % [
				core_name,
				layout_attachment_transforms.size(),
				layout_attachment_capacity,
			]
		else:
			summary_label.text = "Core: %s   •   this body family currently uses its authored fixed mount topology" % core_name
		return
	var snapshot: Dictionary = current_draft.ui_snapshot()
	var algorithm_name: String = (
		algorithm_picker.get_item_text(algorithm_picker.selected)
		if algorithm_picker != null and algorithm_picker.selected >= 0
		else "PPO"
	)
	var reward_name: String = str(_selected_reward_cardset().get("display_name", "Custom rewards"))
	summary_label.text = "Neural body contract: %d controls   •   %d observations   •   %d slots\nTraining: %s   •   hidden %d × %d   •   %d workers   •   %s Hz\nRewards: %s   •   %s" % [
		int(snapshot.get("preview_control_count", 0)),
		int(snapshot.get("preview_observation_count", 0)),
		int(snapshot.get("slot_count", 0)),
		algorithm_name,
		int(round(hidden_width_input.value)),
		int(round(hidden_depth_input.value)),
		int(round(worker_count_input.value)),
		String.num(control_rate_input.value, 0),
		reward_name,
		"starts immediately" if start_training_checkbox.button_pressed else "starts paused",
	]


func _accept_current_build() -> void:
	if current_draft == null:
		_set_error("Choose a body first.")
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
	layout_attachment_transforms.clear()
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
	button.add_theme_stylebox_override(
		"normal",
		DroneTrainingRoomPresentation.scanner_button_style(accent)
	)
	return button
