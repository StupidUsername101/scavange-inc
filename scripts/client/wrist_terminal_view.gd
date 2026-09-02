class_name WristTerminalView
extends Control

const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)

signal invite_friend_requested
signal return_to_menu_requested
signal hover_sound_requested
signal click_sound_requested
signal device_control_requested(contact_id: StringName)
signal device_command_requested(
	contact_id: StringName,
	action: StringName,
	payload: Dictionary
)
signal display_page_changed(page: StringName)
signal voice_mimic_consent_changed(enabled: bool)

const DEVICE_SCANNER := preload(
	"res://scripts/client/wrist_device_scanner.gd"
)
const AIM_RING_SCRIPT := preload(
	"res://scripts/client/terminal_aim_ring.gd"
)
const RADIO_CONTROL_PANEL := preload(
	"res://scripts/client/fieldlink_radio_control_panel.gd"
)
const CONTROL_PANEL_BY_TYPE := {
	&"radio": RADIO_CONTROL_PANEL,
	&"speaker_cluster": RADIO_CONTROL_PANEL,
}
const SCREEN_SIZE := Vector2(720.0, 520.0)
const PAGE_HOME := &"home"
const PAGE_SCANNER := &"scanner"
const COLOR_BACKGROUND := Color(0.008, 0.025, 0.022, 1.0)
const COLOR_PANEL := Color(0.018, 0.075, 0.062, 0.98)
const COLOR_PANEL_INNER := Color(0.012, 0.045, 0.039, 1.0)
const COLOR_BORDER := Color(0.12, 0.58, 0.42, 1.0)
const COLOR_BORDER_DIM := Color(0.06, 0.29, 0.23, 1.0)
const COLOR_TEXT := Color(0.66, 1.0, 0.78, 1.0)
const COLOR_MUTED := Color(0.35, 0.69, 0.53, 1.0)
const COLOR_ACCENT := Color(0.96, 0.67, 0.18, 1.0)
const COLOR_ERROR := Color(1.0, 0.32, 0.18, 1.0)
const INVITE_HINT_AVAILABLE := "Open Steam's lobby invite overlay."
const INVITE_HINT_UNAVAILABLE := (
	"Steam overlay unavailable; click for connection details."
)
const HOVER_HINT_META := &"fieldlink_hover_hint"

#######################################################
# Renders Fieldlink's persistent shell, home services, and live technical-device
# scanner using the same nested-box language as the industrial terminals.
#######################################################

var session_label := "OFFLINE"
var invite_available := false
var feedback_message := "RMB HOLD  LOOK  //  TAB  CLOSE"
var feedback_is_error := false
var current_page: StringName = PAGE_HOME
var scanner_contacts: Array[Dictionary] = []
var scanner_range_meters := 36.0
var scanner_heading_yaw := 0.0
var latest_contact_id: StringName = &""
var selected_contact_id: StringName = &""
var voice_mimic_consent := false

var session_value: Label
var invite_button: Button
var hint_label: Label
var home_button: Button
var scanner_button: Button
var return_button: Button
var home_page: Control
var scanner_page: Control
var scanner: Control
var scanner_preview: Control
var scanner_count_label: Label
var scanner_name_label: Label
var scanner_class_label: Label
var scanner_distance_label: Label
var scanner_status_label: Label
var device_panel_host: Control
var device_control_panel: FieldlinkDeviceControlPanel
var device_placeholder_label: Label
var voice_mimic_button: Button
var pointer_position := SCREEN_SIZE * 0.5
var pointer_visible := false
var pointer_ring: Control


func _ready() -> void:
	position = Vector2.ZERO
	size = SCREEN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()


func set_session_info(next_label: String, can_invite: bool) -> void:
	session_label = next_label.strip_edges()
	invite_available = can_invite
	if session_value != null:
		session_value.text = session_label
	if invite_button != null:
		invite_button.set_meta(HOVER_HINT_META, (
			INVITE_HINT_AVAILABLE
			if invite_available
			else INVITE_HINT_UNAVAILABLE
		))


func set_voice_mimic_consent(enabled: bool) -> void:
	voice_mimic_consent = enabled
	_update_voice_mimic_button()


func set_scanner_contacts(
	next_contacts: Array[Dictionary],
	next_range_meters: float
) -> void:
	scanner_contacts.clear()
	for contact: Dictionary in next_contacts:
		scanner_contacts.append(contact.duplicate(false))
	scanner_range_meters = maxf(next_range_meters, 1.0)
	if scanner != null:
		scanner.call("set_contacts", scanner_contacts, scanner_range_meters)
		if scanner_preview != null:
			scanner_preview.queue_redraw()
	elif scanner_preview != null:
		scanner_preview.call(
			"set_contacts",
			scanner_contacts,
			scanner_range_meters
		)
	_update_scanner_count()
	if not latest_contact_id.is_empty() and not _has_scanner_contact(latest_contact_id):
		latest_contact_id = &""
	if not selected_contact_id.is_empty():
		var selected_contact := _get_scanner_contact(selected_contact_id)
		if selected_contact.is_empty():
			_clear_scanner_return()
		else:
			_render_contact_header(selected_contact)


func set_scanner_heading(value: float) -> void:
	if not is_finite(value):
		return
	scanner_heading_yaw = wrapf(value, -PI, PI)
	if scanner != null:
		scanner.call("set_heading_yaw", scanner_heading_yaw)
	if scanner_preview != null:
		scanner_preview.call("set_heading_yaw", scanner_heading_yaw)


func is_scanner_page_active() -> bool:
	return current_page == PAGE_SCANNER


func show_home_page() -> void:
	_set_page(PAGE_HOME)


func show_scanner_page() -> void:
	_set_page(PAGE_SCANNER)


func apply_replicated_page(page_value: Variant) -> void:
	_set_page(FIELDLINK_DISPLAY_STATE.sanitize_page(page_value), true, false)


func set_feedback(message: String, is_error := false) -> void:
	feedback_message = message.strip_edges()
	feedback_is_error = is_error
	_update_hint()


func set_pointer_indicator(next_position: Vector2, next_visible: bool) -> void:
	pointer_position = Vector2(
		clampf(next_position.x, 0.0, SCREEN_SIZE.x),
		clampf(next_position.y, 0.0, SCREEN_SIZE.y)
	)
	pointer_visible = next_visible
	if pointer_ring != null:
		pointer_ring.call("set_aim", pointer_position, pointer_visible)


func get_selected_contact_id() -> StringName:
	return selected_contact_id


func get_selected_control_type() -> StringName:
	return StringName(str(
		_get_scanner_contact(selected_contact_id).get("control_type", "")
	))


func apply_device_control_snapshot(snapshot_value: Dictionary) -> void:
	var snapshot := FieldlinkDeviceControlPacket.sanitize_snapshot(snapshot_value)
	if (
		snapshot.is_empty()
		or snapshot.get("contact_id", &"") != selected_contact_id
	):
		return
	var control_type: StringName = snapshot.get("control_type", &"")
	if (
		device_control_panel == null
		or not is_instance_valid(device_control_panel)
		or device_control_panel.control_snapshot.get("control_type", &"") != control_type
	):
		_mount_device_control_panel(control_type)
	if device_control_panel != null:
		device_control_panel.apply_control_snapshot(snapshot)
	if scanner_status_label != null:
		scanner_status_label.text = str(snapshot.get("status_text", "ONLINE")).to_upper()


func apply_device_control_error(contact_id: StringName, message: String) -> void:
	if contact_id != selected_contact_id:
		return
	_show_device_placeholder(message.to_upper(), COLOR_ERROR)
	if scanner_status_label != null:
		scanner_status_label.text = "LINK ERROR"
		scanner_status_label.add_theme_color_override("font_color", COLOR_ERROR)


func _build_interface() -> void:
	for child: Node in get_children():
		child.queue_free()

	var background := ColorRect.new()
	background.name = "Background"
	background.color = COLOR_BACKGROUND
	background.position = Vector2.ZERO
	background.size = SCREEN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var header := _add_panel(
		self,
		Rect2(18.0, 14.0, 684.0, 60.0),
		COLOR_PANEL_INNER,
		COLOR_BORDER_DIM
	)
	header.name = "Header"
	_add_label(
		header,
		"SCAVANGE INC.  /  FIELDLINK",
		Rect2(16.0, 7.0, 435.0, 30.0),
		23,
		COLOR_TEXT
	)
	_add_label(
		header,
		"SESSION",
		Rect2(16.0, 35.0, 100.0, 18.0),
		12,
		COLOR_MUTED
	)
	session_value = _add_label(
		header,
		session_label,
		Rect2(382.0, 17.0, 284.0, 27.0),
		15,
		COLOR_ACCENT,
		HORIZONTAL_ALIGNMENT_RIGHT
	)

	var navigation := _add_panel(
		self,
		Rect2(18.0, 86.0, 684.0, 54.0),
		COLOR_PANEL_INNER,
		COLOR_BORDER_DIM
	)
	navigation.name = "TopNavigation"
	home_button = _add_action_button(
		navigation,
		"HomeNavigation",
		"01  HOME",
		Rect2(9.0, 8.0, 116.0, 38.0),
		COLOR_BORDER,
		"Open Fieldlink's service overview.",
		16
	)
	home_button.pressed.connect(show_home_page)
	scanner_button = _add_action_button(
		navigation,
		"ScannerNavigation",
		"02  SCANNER",
		Rect2(133.0, 8.0, 146.0, 38.0),
		COLOR_BORDER,
		"Sweep nearby space for compatible technical devices.",
		14
	)
	scanner_button.pressed.connect(show_scanner_page)
	return_button = _add_action_button(
		navigation,
		"ReturnToMenu",
		"EXIT",
		Rect2(553.0, 8.0, 122.0, 38.0),
		COLOR_ERROR,
		"Leave the current session and return to the main menu.",
		16
	)
	return_button.pressed.connect(return_to_menu_requested.emit)

	var content := _add_panel(
		self,
		Rect2(18.0, 152.0, 684.0, 296.0),
		COLOR_PANEL_INNER,
		COLOR_BORDER
	)
	content.name = "PageContent"
	home_page = Control.new()
	home_page.name = "HomePage"
	home_page.position = Vector2.ZERO
	home_page.size = content.size
	content.add_child(home_page)
	_build_home_page()
	scanner_page = Control.new()
	scanner_page.name = "ScannerPage"
	scanner_page.position = Vector2.ZERO
	scanner_page.size = content.size
	content.add_child(scanner_page)
	_build_scanner_page()

	var hint_panel := _add_panel(
		self,
		Rect2(18.0, 460.0, 684.0, 42.0),
		COLOR_PANEL_INNER,
		COLOR_BORDER_DIM,
		1
	)
	hint_panel.name = "TooltipBar"
	hint_label = _add_label(
		hint_panel,
		feedback_message,
		Rect2(12.0, 3.0, 660.0, 34.0),
		14,
		COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_set_page(PAGE_HOME, true)
	_update_hint()
	_create_pointer_ring()


func _create_pointer_ring() -> void:
	pointer_ring = AIM_RING_SCRIPT.new() as Control
	if pointer_ring == null:
		return
	pointer_ring.name = "FieldlinkCursor"
	add_child(pointer_ring)
	pointer_ring.call("set_aim", pointer_position, pointer_visible)


func _build_home_page() -> void:
	_add_label(
		home_page,
		"FIELDLINK SERVICES",
		Rect2(14.0, 7.0, 360.0, 28.0),
		17,
		COLOR_MUTED
	)
	_add_label(
		home_page,
		"LOCAL BUS  /  READY",
		Rect2(404.0, 8.0, 264.0, 26.0),
		13,
		COLOR_BORDER,
		HORIZONTAL_ALIGNMENT_RIGHT
	)

	var scanner_card := _add_action_button(
		home_page,
		"OpenScanner",
		"",
		Rect2(14.0, 41.0, 425.0, 240.0),
		COLOR_BORDER,
		"Locate radios, fabrication stations, and other compatible devices.",
		22
	)
	scanner_card.pressed.connect(show_scanner_page)
	_add_label(
		scanner_card,
		"PROXIMITY",
		Rect2(20.0, 18.0, 240.0, 24.0),
		14,
		COLOR_MUTED
	)
	_add_label(
		scanner_card,
		"DEVICE\nSCANNER",
		Rect2(20.0, 48.0, 235.0, 95.0),
		31,
		COLOR_TEXT
	)
	_add_label(
		scanner_card,
		"RANGE  36M\nPASSIVE CONTACT BUS",
		Rect2(20.0, 174.0, 245.0, 46.0),
		13,
		COLOR_MUTED
	)
	scanner_preview = DEVICE_SCANNER.new() as Control
	scanner_preview.name = "ScannerPreview"
	scanner_preview.position = Vector2(272.0, 50.0)
	scanner_preview.size = Vector2(132.0, 132.0)
	scanner_card.add_child(scanner_preview)
	# This is a live miniature, while the whole service card remains the button.
	scanner_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scanner_preview.connect("contact_pinged", _on_scanner_contact_pinged)
	scanner_preview.call(
		"set_contacts",
		scanner_contacts,
		scanner_range_meters
	)
	scanner_preview.call("set_heading_yaw", scanner_heading_yaw)

	invite_button = _add_action_button(
		home_page,
		"InviteFriend",
		"CREW LINK\nINVITE",
		Rect2(451.0, 41.0, 217.0, 111.0),
		COLOR_BORDER,
		INVITE_HINT_AVAILABLE,
		20
	)
	invite_button.set_meta(HOVER_HINT_META, (
		INVITE_HINT_AVAILABLE
		if invite_available
		else INVITE_HINT_UNAVAILABLE
	))
	invite_button.pressed.connect(invite_friend_requested.emit)

	var network_card := _add_panel(
		home_page,
		Rect2(451.0, 164.0, 217.0, 117.0),
		COLOR_PANEL,
		COLOR_BORDER_DIM,
		1
	)
	_add_label(
		network_card,
		"NETWORK",
		Rect2(14.0, 9.0, 189.0, 21.0),
		13,
		COLOR_MUTED
	)
	_add_label(
		network_card,
		"VOICE [V]  READY",
		Rect2(14.0, 31.0, 189.0, 22.0),
		13,
		COLOR_TEXT
	)
	voice_mimic_button = _add_action_button(
		network_card,
		"VoiceMimicConsent",
		"",
		Rect2(10.0, 56.0, 197.0, 50.0),
		COLOR_ACCENT,
		"Allow enemies to replay up to three short voice phrases in this session. Nothing is saved to disk.",
		13
	)
	voice_mimic_button.pressed.connect(_on_voice_mimic_pressed)
	_update_voice_mimic_button()


func _on_voice_mimic_pressed() -> void:
	voice_mimic_consent_changed.emit(not voice_mimic_consent)


func _update_voice_mimic_button() -> void:
	if voice_mimic_button == null:
		return
	voice_mimic_button.text = (
		"MIMIC MEMORY  ON"
		if voice_mimic_consent
		else "MIMIC MEMORY  OFF"
	)


func _build_scanner_page() -> void:
	_add_label(
		scanner_page,
		"LOCAL DEVICE SWEEP",
		Rect2(14.0, 7.0, 350.0, 28.0),
		17,
		COLOR_MUTED
	)
	scanner_count_label = _add_label(
		scanner_page,
		"RETURNS  00",
		Rect2(420.0, 8.0, 248.0, 26.0),
		13,
		COLOR_ACCENT,
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	var sweep_panel := _add_panel(
		scanner_page,
		Rect2(14.0, 41.0, 302.0, 240.0),
		Color(0.005, 0.035, 0.027, 1.0),
		COLOR_BORDER_DIM,
		1
	)
	scanner = DEVICE_SCANNER.new() as Control
	scanner.name = "DeviceSweep"
	scanner.position = Vector2(5.0, 5.0)
	scanner.size = Vector2(292.0, 230.0)
	scanner.connect("contact_pinged", _on_scanner_contact_pinged)
	scanner.connect("contact_selected", _on_scanner_contact_selected)
	scanner.connect("contact_hovered", _on_scanner_contact_hovered)
	scanner.connect("contact_hover_ended", _restore_feedback_hint)
	sweep_panel.add_child(scanner)
	(scanner as WristDeviceScanner).share_targets_with(
		scanner_preview as WristDeviceScanner
	)
	scanner.call("set_heading_yaw", scanner_heading_yaw)

	var return_panel := _add_panel(
		scanner_page,
		Rect2(328.0, 41.0, 340.0, 240.0),
		COLOR_PANEL,
		COLOR_BORDER_DIM,
		1
	)
	_add_label(
		return_panel,
		"DEVICE LINK  /  SELECT RETURN",
		Rect2(13.0, 5.0, 314.0, 20.0),
		13,
		COLOR_MUTED
	)
	scanner_name_label = _add_label(
		return_panel,
		"NO CONTACT",
		Rect2(13.0, 24.0, 160.0, 24.0),
		15,
		COLOR_TEXT
	)
	scanner_class_label = _add_label(
		return_panel,
		"CLASS  --",
		Rect2(177.0, 25.0, 150.0, 20.0),
		11,
		COLOR_MUTED
	)
	scanner_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scanner_distance_label = _add_label(
		return_panel,
		"RANGE  --.- M",
		Rect2(13.0, 45.0, 150.0, 18.0),
		11,
		COLOR_ACCENT
	)
	scanner_status_label = _add_label(
		return_panel,
		"SWEEPING",
		Rect2(177.0, 45.0, 150.0, 18.0),
		11,
		COLOR_BORDER,
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	device_panel_host = Control.new()
	device_panel_host.name = "DevicePanelHost"
	device_panel_host.position = Vector2(13.0, 66.0)
	device_panel_host.size = Vector2(314.0, 165.0)
	device_panel_host.mouse_filter = Control.MOUSE_FILTER_PASS
	return_panel.add_child(device_panel_host)
	_show_device_placeholder("SELECT A RETURN ON THE SWEEP", COLOR_MUTED)
	scanner.call("set_contacts", scanner_contacts, scanner_range_meters)
	_update_scanner_count()


func _set_page(
	page: StringName,
	force := false,
	notify_observers := true
) -> void:
	if (
		page != PAGE_HOME
		and page != PAGE_SCANNER
	):
		return
	if page == current_page and not force:
		return
	current_page = page
	if home_page != null:
		home_page.visible = current_page == PAGE_HOME
	if scanner_page != null:
		scanner_page.visible = current_page == PAGE_SCANNER
	_update_navigation_styles()
	if notify_observers:
		display_page_changed.emit(current_page)


func _update_navigation_styles() -> void:
	_set_navigation_active(home_button, current_page == PAGE_HOME)
	_set_navigation_active(scanner_button, current_page == PAGE_SCANNER)


func _set_navigation_active(button: Button, active: bool) -> void:
	if button == null:
		return
	button.add_theme_stylebox_override(
		"normal",
		_make_style(
			Color(0.028, 0.13, 0.095, 1.0) if active else COLOR_PANEL,
			COLOR_TEXT if active else COLOR_BORDER_DIM,
			2 if active else 1
		)
	)
	button.add_theme_color_override(
		"font_color",
		COLOR_TEXT if active else COLOR_MUTED
	)


func _on_scanner_contact_pinged(contact: Dictionary) -> void:
	latest_contact_id = StringName(str(contact.get("contact_id", "")))
	if scanner_name_label == null or not selected_contact_id.is_empty():
		return
	_render_contact_header(contact)


func _on_scanner_contact_selected(contact: Dictionary) -> void:
	var contact_id := StringName(str(contact.get("contact_id", "")))
	if contact_id.is_empty():
		return
	selected_contact_id = contact_id
	latest_contact_id = contact_id
	click_sound_requested.emit()
	_render_contact_header(contact)
	var control_type := StringName(str(contact.get("control_type", "")))
	if control_type.is_empty():
		_show_device_placeholder(
			"IDENTITY LINK ONLY\nNO REMOTE CONTROLS REGISTERED",
			COLOR_MUTED
		)
		return
	_show_device_placeholder(
		"NEGOTIATING %s CONTROL LINK..." % str(control_type).to_upper(),
		COLOR_ACCENT
	)
	device_control_requested.emit(contact_id)


func _on_scanner_contact_hovered(contact: Dictionary) -> void:
	hover_sound_requested.emit()
	if hint_label == null:
		return
	hint_label.text = "SELECT %s  //  %05.1f M  //  %s" % [
		str(contact.get("display_name", "DEVICE")).to_upper(),
		float(contact.get("distance_meters", 0.0)),
		str(contact.get("status_text", "DETECTED")).to_upper(),
	]
	hint_label.add_theme_color_override("font_color", COLOR_TEXT)


func _render_contact_header(contact: Dictionary) -> void:
	scanner_name_label.text = str(
		contact.get("display_name", "UNKNOWN DEVICE")
	).to_upper()
	scanner_class_label.text = "CLASS  %s" % str(
		contact.get("device_class", &"DEVICE")
	).to_upper()
	scanner_distance_label.text = "RANGE  %05.1f M" % float(
		contact.get("distance_meters", 0.0)
	)
	scanner_status_label.text = str(
		contact.get("status_text", "DETECTED")
	).to_upper()
	scanner_status_label.add_theme_color_override("font_color", COLOR_ACCENT)


func _clear_scanner_return() -> void:
	latest_contact_id = &""
	selected_contact_id = &""
	if scanner != null:
		scanner.call("set_selected_contact", &"")
	if scanner_name_label == null:
		return
	scanner_name_label.text = "NO CONTACT"
	scanner_class_label.text = "CLASS  --"
	scanner_distance_label.text = "RANGE  --.- M"
	scanner_status_label.text = "SWEEPING"
	scanner_status_label.add_theme_color_override("font_color", COLOR_BORDER)
	_show_device_placeholder("SELECT A RETURN ON THE SWEEP", COLOR_MUTED)


func _mount_device_control_panel(control_type: StringName) -> void:
	_clear_device_control_panel()
	var panel_script := CONTROL_PANEL_BY_TYPE.get(control_type) as Script
	if panel_script == null:
		_show_device_placeholder(
			"UNSUPPORTED CONTROL ADAPTER  //  %s" % str(control_type).to_upper(),
			COLOR_ERROR
		)
		return
	device_control_panel = panel_script.new() as FieldlinkDeviceControlPanel
	if device_control_panel == null:
		_show_device_placeholder("CONTROL ADAPTER FAILED TO LOAD", COLOR_ERROR)
		return
	device_control_panel.name = "DeviceControlPanel"
	device_control_panel.position = Vector2.ZERO
	device_control_panel.size = device_panel_host.size
	device_control_panel.command_requested.connect(_on_device_panel_command)
	device_control_panel.hover_hint_requested.connect(_show_device_panel_hint)
	device_control_panel.hover_hint_ended.connect(_restore_feedback_hint)
	device_control_panel.click_sound_requested.connect(click_sound_requested.emit)
	device_panel_host.add_child(device_control_panel)


func _on_device_panel_command(action: StringName, payload: Dictionary) -> void:
	if selected_contact_id.is_empty():
		return
	device_command_requested.emit(
		selected_contact_id,
		action,
		payload.duplicate(false)
	)


func _show_device_panel_hint(text: String, play_sound: bool) -> void:
	if play_sound:
		hover_sound_requested.emit()
	if hint_label == null:
		return
	hint_label.text = text.to_upper()
	hint_label.add_theme_color_override("font_color", COLOR_TEXT)


func _show_device_placeholder(text: String, color: Color) -> void:
	_clear_device_control_panel()
	if device_panel_host == null:
		return
	device_placeholder_label = _add_label(
		device_panel_host,
		text,
		Rect2(0.0, 0.0, device_panel_host.size.x, device_panel_host.size.y),
		13,
		color,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	device_placeholder_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _clear_device_control_panel() -> void:
	if device_panel_host == null:
		return
	for child: Node in device_panel_host.get_children():
		device_panel_host.remove_child(child)
		child.queue_free()
	device_control_panel = null
	device_placeholder_label = null


func _update_scanner_count() -> void:
	if scanner_count_label != null:
		scanner_count_label.text = "RETURNS  %02d" % scanner_contacts.size()


func _has_scanner_contact(contact_id: StringName) -> bool:
	for contact: Dictionary in scanner_contacts:
		if StringName(str(contact.get("contact_id", ""))) == contact_id:
			return true
	return false


func _get_scanner_contact(contact_id: StringName) -> Dictionary:
	for contact: Dictionary in scanner_contacts:
		if StringName(str(contact.get("contact_id", ""))) == contact_id:
			return contact
	return {}


func _add_action_button(
	parent: Control,
	node_name: String,
	text_value: String,
	rect: Rect2,
	accent: Color,
	hint: String,
	font_size := 20
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	button.add_theme_color_override("font_disabled_color", COLOR_BORDER_DIM)
	button.add_theme_stylebox_override(
		"normal",
		_make_style(COLOR_PANEL, accent, 2)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_style(Color(0.025, 0.13, 0.1, 1.0), COLOR_TEXT, 3)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_style(COLOR_PANEL_INNER, COLOR_ACCENT, 4)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_make_style(COLOR_BACKGROUND, COLOR_BORDER_DIM, 1)
	)
	# Native tooltip popups render as opaque blank rectangles in this 3D
	# SubViewport. The persistent bottom bar is the terminal's tooltip surface.
	button.tooltip_text = ""
	button.set_meta(HOVER_HINT_META, hint)
	button.mouse_entered.connect(_show_button_hover_hint.bind(button))
	button.mouse_exited.connect(_restore_feedback_hint)
	button.pressed.connect(click_sound_requested.emit)
	parent.add_child(button)
	return button


func _show_button_hover_hint(button: Button) -> void:
	hover_sound_requested.emit()
	if hint_label == null:
		return
	hint_label.text = str(button.get_meta(HOVER_HINT_META, ""))
	hint_label.add_theme_color_override("font_color", COLOR_TEXT)


func _restore_feedback_hint() -> void:
	_update_hint()


func _update_hint() -> void:
	if hint_label == null:
		return
	hint_label.text = (
		feedback_message
		if not feedback_message.is_empty()
		else "RMB HOLD  LOOK  //  TAB  CLOSE"
	)
	hint_label.add_theme_color_override(
		"font_color",
		COLOR_ERROR if feedback_is_error else COLOR_MUTED
	)


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
	panel.add_theme_stylebox_override(
		"panel",
		_make_style(background_color, border_color, border_width)
	)
	parent.add_child(panel)
	return panel


func _make_style(
	background_color: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
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
	return style


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
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
