class_name MLBodyPresetPicker
extends Window

signal custom_requested
signal preset_requested(preset_id: StringName)

const DEFAULT_SIZE := Vector2i(760, 620)
const ORANGE := Color("ffad42")
const GREEN := Color("54e6b1")
const MUTED := Color("a8b8ad")

#######################################################
# Small entry chooser for Worker Groups +. Presets and custom bodies converge immediately on the
# existing MLBodyCreatorPanel, so there is still one acceptance/training path and one body contract.
#######################################################


func _init() -> void:
	visible = false


func _ready() -> void:
	title = "New Worker Group"
	size = DEFAULT_SIZE
	min_size = Vector2i(600, 480)
	unresizable = false
	transient = true
	exclusive = false
	close_requested.connect(hide)
	_build_ui()


func open_picker() -> void:
	_fit_to_parent_viewport()
	popup_centered()


func _fit_to_parent_viewport() -> void:
	var viewport: Viewport = get_parent().get_viewport() if get_parent() != null else null
	if viewport == null:
		return
	var available: Vector2i = Vector2i(viewport.get_visible_rect().size) - Vector2i(28, 28)
	if available.x <= 0 or available.y <= 0:
		return
	# Window.min_size is allowed to shrink with a genuinely small game window; the card list already
	# scrolls, so every preset and the cancel action remain reachable instead of falling off-screen.
	min_size = Vector2i(mini(600, available.x), mini(480, available.y))
	size = Vector2i(mini(DEFAULT_SIZE.x, available.x), mini(DEFAULT_SIZE.y, available.y))


func _build_ui() -> void:
	var outer: PanelContainer = PanelContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(false)
	)
	add_child(outer)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	outer.add_child(layout)

	var heading: Label = Label.new()
	heading.text = "NEW WORKER GROUP"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", ORANGE)
	heading.tooltip_text = "Start from a complete editable body, or open the full body creator with an empty layout."
	layout.add_child(heading)

	var hint: Label = Label.new()
	hint.text = "Choose a starting body. Every preset remains editable before the group is created."
	hint.add_theme_color_override("font_color", MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)

	var custom_button: Button = _styled_button("BUILD CUSTOM WORKER", true)
	custom_button.tooltip_text = "Open the complete 3D Core and limb editor with a fresh body draft."
	custom_button.pressed.connect(func() -> void:
		hide()
		custom_requested.emit()
	)
	layout.add_child(custom_button)

	var divider: HSeparator = HSeparator.new()
	layout.add_child(divider)

	var preset_heading: Label = Label.new()
	preset_heading.text = "PRESETS"
	preset_heading.add_theme_font_size_override("font_size", 16)
	preset_heading.add_theme_color_override("font_color", GREEN)
	preset_heading.tooltip_text = "Preset selection copies the definition. Editing it never mutates the built-in template."
	layout.add_child(preset_heading)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	var cards: VBoxContainer = VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 8)
	scroll.add_child(cards)
	for record: Dictionary in MLBodyPresetLibrary.worker_start_ui_records():
		_add_preset_card(cards, record)

	var cancel: Button = _styled_button("CANCEL", false)
	cancel.tooltip_text = "Close without changing the current training room."
	cancel.pressed.connect(hide)
	layout.add_child(cancel)


func _add_preset_card(parent: VBoxContainer, record: Dictionary) -> void:
	var preset_id: StringName = StringName(str(record.get("preset_id", "")))
	if str(preset_id).is_empty():
		return
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_slot_panel_style()
	)
	parent.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 3)
	row.add_child(copy)
	var name_label: Label = Label.new()
	name_label.text = str(record.get("display_name", "Worker preset")).to_upper()
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", GREEN)
	copy.add_child(name_label)
	var facts: Label = Label.new()
	facts.text = "%d controls  ·  %d slots  ·  %s" % [
		int(record.get("preview_control_count", 0)),
		int(record.get("slot_count", 0)),
		str(record.get("algorithm_hint", "PPO")),
	]
	facts.add_theme_color_override("font_color", MUTED)
	copy.add_child(facts)

	var description: String = str(record.get("description", ""))
	panel.tooltip_text = description
	name_label.tooltip_text = description
	facts.tooltip_text = description
	var use_button: Button = _styled_button("USE PRESET", false)
	use_button.custom_minimum_size.x = 124.0
	use_button.tooltip_text = "%s\n\nLoads an independent editable copy in the existing worker creator." % description
	use_button.pressed.connect(func() -> void:
		hide()
		preset_requested.emit(preset_id)
	)
	row.add_child(use_button)


func _styled_button(label_text: String, accent: bool) -> Button:
	var button: Button = Button.new()
	button.text = label_text
	var normal: StyleBoxFlat = DroneTrainingRoomPresentation.scanner_button_style(accent)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.09)
	hover.border_color = normal.border_color.lightened(0.12)
	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = normal.bg_color.darkened(0.10)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	return button
