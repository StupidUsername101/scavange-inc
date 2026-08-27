class_name FieldlinkRadioControlPanel
extends FieldlinkDeviceControlPanel

const COLOR_BACKGROUND := Color(0.008, 0.025, 0.022, 1.0)
const COLOR_PANEL := Color(0.018, 0.075, 0.062, 0.98)
const COLOR_BORDER := Color(0.12, 0.58, 0.42, 1.0)
const COLOR_BORDER_DIM := Color(0.06, 0.29, 0.23, 1.0)
const COLOR_TEXT := Color(0.66, 1.0, 0.78, 1.0)
const COLOR_MUTED := Color(0.35, 0.69, 0.53, 1.0)
const COLOR_ACCENT := Color(0.96, 0.67, 0.18, 1.0)
const VOLUME_COMMIT_DELAY_SECONDS := 0.08

var track_list: ItemList
var status_label: Label
var time_label: Label
var play_pause_button: Button
var stop_button: Button
var volume_slider: HSlider
var volume_label: Label
var volume_commit_timer: Timer
var selected_track_index := 0
var playback_state: StringName = &"stopped"
var _track_names := PackedStringArray()
var _applying_snapshot := false
var _local_selection_dirty := false
var _device_label := "AUDIO DEVICE"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_interface()
	if not control_snapshot.is_empty():
		apply_control_snapshot(control_snapshot)


func apply_control_snapshot(snapshot: Dictionary) -> void:
	super(snapshot)
	_device_label = str(snapshot.get("display_name", "AUDIO DEVICE")).strip_edges().to_upper()
	if _device_label.is_empty():
		_device_label = "AUDIO DEVICE"
	if track_list == null:
		return
	var payload: Dictionary = snapshot.get("payload", {})
	playback_state = payload.get("playback_state", &"stopped")
	var next_track_names := PackedStringArray()
	for track_value: Variant in payload.get("tracks", []):
		if track_value is Dictionary:
			next_track_names.append(str(
				(track_value as Dictionary).get("display_name", "UNKNOWN TRACK")
			))
	if next_track_names != _track_names:
		_track_names = next_track_names
		track_list.clear()
		for track_name: String in _track_names:
			track_list.add_item(track_name)
	var server_selected_track_index := clampi(
		int(payload.get("selected_track_index", 0)),
		0,
		maxi(track_list.item_count - 1, 0)
	)
	if not _local_selection_dirty or server_selected_track_index == selected_track_index:
		selected_track_index = server_selected_track_index
		_local_selection_dirty = false
	if track_list.item_count > 0:
		track_list.select(selected_track_index)
	_applying_snapshot = true
	volume_slider.value = float(payload.get("volume_ratio", 0.75)) * 100.0
	_applying_snapshot = false
	_update_volume_label(volume_slider.value)
	_update_transport(
		float(payload.get("elapsed_seconds", 0.0)),
		float(payload.get("duration_seconds", 0.0))
	)


func _build_interface() -> void:
	status_label = _add_label("AUDIO DEVICE  //  STOPPED", Rect2(0.0, 0.0, 190.0, 20.0), 13, COLOR_ACCENT)
	time_label = _add_label("00:00 / --:--", Rect2(190.0, 0.0, 120.0, 20.0), 12, COLOR_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	track_list = ItemList.new()
	track_list.name = "TrackList"
	track_list.position = Vector2(0.0, 24.0)
	track_list.size = Vector2(310.0, 76.0)
	track_list.select_mode = ItemList.SELECT_SINGLE
	track_list.allow_reselect = true
	track_list.focus_mode = Control.FOCUS_NONE
	track_list.add_theme_font_size_override("font_size", 12)
	track_list.add_theme_color_override("font_color", COLOR_MUTED)
	track_list.add_theme_color_override("font_selected_color", COLOR_TEXT)
	track_list.add_theme_stylebox_override("panel", _make_style(COLOR_BACKGROUND, COLOR_BORDER_DIM, 1))
	track_list.add_theme_stylebox_override("selected", _make_style(COLOR_PANEL, COLOR_ACCENT, 1))
	track_list.item_selected.connect(_on_track_selected)
	track_list.item_activated.connect(_on_track_activated)
	# The list is a continuous browsing surface, not one discrete control. Keep its explanatory
	# hint, but reserve hover ticks for actual buttons and sliders.
	bind_hover(
		track_list,
		"Choose a locally available track; activate it to play immediately.",
		false
	)
	add_child(track_list)

	play_pause_button = _add_button(
		"PlayPause",
		"PLAY",
		Rect2(0.0, 106.0, 149.0, 34.0),
		"Play the selected track, or pause/resume the current one."
	)
	play_pause_button.pressed.connect(_on_play_pause_pressed)
	stop_button = _add_button(
		"Stop",
		"STOP",
		Rect2(161.0, 106.0, 149.0, 34.0),
		"Stop playback while keeping the selected track queued."
	)
	stop_button.pressed.connect(request_command.bind(&"stop", {}))

	volume_label = _add_label("OUTPUT  75%", Rect2(0.0, 145.0, 124.0, 20.0), 12, COLOR_MUTED)
	volume_slider = HSlider.new()
	volume_slider.name = "Volume"
	volume_slider.position = Vector2(124.0, 145.0)
	volume_slider.size = Vector2(186.0, 20.0)
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.value = 75.0
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.value_changed.connect(_on_volume_changed)
	bind_hover(volume_slider, "Set this device's authoritative output level for every listener.")
	add_child(volume_slider)

	volume_commit_timer = Timer.new()
	volume_commit_timer.name = "VolumeCommitTimer"
	volume_commit_timer.one_shot = true
	volume_commit_timer.wait_time = VOLUME_COMMIT_DELAY_SECONDS
	volume_commit_timer.timeout.connect(_commit_volume)
	add_child(volume_commit_timer)


func _on_track_selected(index: int) -> void:
	selected_track_index = clampi(index, 0, maxi(track_list.item_count - 1, 0))
	_local_selection_dirty = true
	click_sound_requested.emit()


func _on_track_activated(index: int) -> void:
	selected_track_index = clampi(index, 0, maxi(track_list.item_count - 1, 0))
	_local_selection_dirty = true
	request_command(&"play_track", {"track_index": selected_track_index})


func _on_play_pause_pressed() -> void:
	match playback_state:
		&"playing":
			request_command(&"pause")
		&"paused":
			request_command(&"resume")
		_:
			request_command(&"play_track", {"track_index": selected_track_index})


func _on_volume_changed(value: float) -> void:
	_update_volume_label(value)
	if _applying_snapshot:
		return
	volume_commit_timer.start()


func _commit_volume() -> void:
	request_command(&"set_volume", {
		"volume_ratio": clampf(float(volume_slider.value) / 100.0, 0.0, 1.0),
	})


func _update_volume_label(value: float) -> void:
	volume_label.text = "OUTPUT  %03d%%" % roundi(value)


func _update_transport(elapsed: float, duration: float) -> void:
	status_label.text = "%s  //  %s" % [
		_device_label.left(20),
		str(playback_state).to_upper(),
	]
	play_pause_button.text = (
		"PAUSE"
		if playback_state == &"playing"
		else ("RESUME" if playback_state == &"paused" else "PLAY")
	)
	time_label.text = "%s / %s" % [_format_time(elapsed), _format_time(duration)]


static func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "00:00"
	var total_seconds := maxi(floori(seconds), 0)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _add_button(
	node_name: String,
	text_value: String,
	rect: Rect2,
	hint: String
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	button.add_theme_stylebox_override("normal", _make_style(COLOR_PANEL, COLOR_BORDER, 1))
	button.add_theme_stylebox_override("hover", _make_style(Color(0.025, 0.13, 0.1, 1.0), COLOR_TEXT, 2))
	button.add_theme_stylebox_override("pressed", _make_style(COLOR_BACKGROUND, COLOR_ACCENT, 2))
	bind_hover(button, hint)
	add_child(button)
	return button


func _add_label(
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
	add_child(label)
	return label


static func _make_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	return style
