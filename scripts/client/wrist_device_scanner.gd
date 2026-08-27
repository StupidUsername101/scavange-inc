class_name WristDeviceScanner
extends Control

signal contact_pinged(contact: Dictionary)
signal contact_selected(contact: Dictionary)
signal contact_hovered(contact: Dictionary)
signal contact_hover_ended

const SWEEP_RADIANS_PER_SECOND := 0.86
const CONTACT_MEMORY_SECONDS := 10.0
const CONTACT_HIGHLIGHT_SECONDS := 1.25
const SWEEP_TRAIL_COUNT := 7
const SWEEP_TRAIL_SPACING := 0.026
const COLOR_GRID := Color(0.055, 0.34, 0.24, 0.62)
const COLOR_GRID_DIM := Color(0.035, 0.18, 0.14, 0.48)
const COLOR_SWEEP := Color(0.38, 1.0, 0.63, 0.9)
const COLOR_CONTACT := Color(0.24, 0.95, 0.55, 1.0)
const COLOR_CONTACT_HOT := Color(1.0, 0.73, 0.2, 1.0)
const COLOR_SELECTED := Color(0.96, 0.67, 0.18, 1.0)
const COLOR_COMPASS := Color(0.45, 0.88, 0.62, 0.92)
const COLOR_COMPASS_NORTH := Color(1.0, 0.72, 0.18, 0.98)
const CONTACT_HIT_RADIUS_PIXELS := 13.0
const COMPASS_LABEL_RADIUS_RATIO := 0.81
const COMPASS_TICK_INSET_PIXELS := 5.0

#######################################################
# Draws a low-allocation submarine-style device sweep. Contacts are supplied
# from authoritative replicated transforms; the sweep only handles presentation
# and remembers a return after the beam has physically crossed it.
#######################################################

var maximum_range_meters := 36.0
var sweep_angle := 0.0
var contacts: Array[Dictionary] = []
var ping_ages: Dictionary[StringName, float] = {}
var selected_contact_id: StringName = &""
var hovered_contact_id: StringName = &""
var heading_yaw := 0.0
var world_to_heading := Basis.IDENTITY


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	mouse_exited.connect(_clear_hover)
	set_process(true)


func set_contacts(
	next_contacts: Array[Dictionary],
	next_maximum_range_meters: float
) -> void:
	maximum_range_meters = maxf(next_maximum_range_meters, 1.0)
	var live_ids: Dictionary[StringName, bool] = {}
	contacts.clear()
	for raw_contact: Dictionary in next_contacts:
		var contact_id := StringName(str(raw_contact.get("contact_id", "")))
		var relative_position := SafeVariant.vector3_strict_or(
			raw_contact.get("relative_position", Vector3.INF),
			Vector3.INF
		)
		if contact_id.is_empty() or not relative_position.is_finite():
			continue
		var contact := raw_contact.duplicate(false)
		contact["contact_id"] = contact_id
		contact["relative_position"] = relative_position
		contacts.append(contact)
		live_ids[contact_id] = true
		if not ping_ages.has(contact_id):
			ping_ages[contact_id] = INF
	for stale_id: StringName in ping_ages.keys():
		if not live_ids.has(stale_id):
			ping_ages.erase(stale_id)
	if not selected_contact_id.is_empty() and not live_ids.has(selected_contact_id):
		selected_contact_id = &""
	if not hovered_contact_id.is_empty() and not live_ids.has(hovered_contact_id):
		_clear_hover()
	queue_redraw()


func set_selected_contact(contact_id: StringName) -> void:
	selected_contact_id = contact_id if _find_contact(contact_id).is_empty() == false else &""
	queue_redraw()


func set_heading_yaw(value: float) -> void:
	if not is_finite(value):
		return
	var next_heading := wrapf(value, -PI, PI)
	if is_equal_approx(next_heading, heading_yaw):
		return
	heading_yaw = next_heading
	world_to_heading = Basis(Vector3.UP, heading_yaw).inverse()
	queue_redraw()


func get_cardinal_screen_point(cardinal: StringName) -> Vector2:
	var direction := _cardinal_screen_direction(cardinal)
	if direction == Vector2.ZERO:
		return Vector2.INF
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * 0.44, 1.0)
	return center + direction * radius * COMPASS_LABEL_RADIUS_RATIO


func share_targets_with(other: WristDeviceScanner) -> void:
	if other == null or other == self:
		return
	# The compact preview and the full scanner are two renderers for one sensor.
	# Both the sanitized target list and its detection memory therefore have one
	# owner instead of being copied and allowed to drift on page changes.
	contacts = other.contacts
	ping_ages = other.ping_ages
	heading_yaw = other.heading_yaw
	world_to_heading = other.world_to_heading
	queue_redraw()


func get_contact_screen_point(contact_id: StringName) -> Vector2:
	var contact := _find_contact(contact_id)
	if contact.is_empty():
		return Vector2.INF
	return _contact_point(contact)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hovered_contact(_contact_at(event.position))
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		var hit_contact := _contact_at(event.position)
		if hit_contact.is_empty():
			return
		selected_contact_id = hit_contact.get("contact_id", &"")
		queue_redraw()
		contact_selected.emit(hit_contact)
		accept_event()


func reset_sweep() -> void:
	sweep_angle = 0.0
	for contact_id: StringName in ping_ages.keys():
		ping_ages[contact_id] = INF
	queue_redraw()


func set_sweep_angle(value: float) -> void:
	sweep_angle = fposmod(value, TAU)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var bounded_delta := clampf(delta, 0.0, 0.25)
	var previous_angle := sweep_angle
	var sweep_delta := SWEEP_RADIANS_PER_SECOND * bounded_delta
	sweep_angle = fposmod(sweep_angle + sweep_delta, TAU)
	for contact: Dictionary in contacts:
		var contact_id: StringName = contact.get("contact_id", &"")
		var age := float(ping_ages.get(contact_id, INF))
		if age < INF:
			ping_ages[contact_id] = age + bounded_delta
		var contact_angle := _contact_angle(contact)
		var angle_from_previous := fposmod(
			contact_angle - previous_angle,
			TAU
		)
		if angle_from_previous <= sweep_delta + 0.018:
			ping_ages[contact_id] = 0.0
			contact_pinged.emit(contact)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * 0.44, 1.0)
	draw_circle(center, radius, Color(0.005, 0.035, 0.025, 0.92))
	draw_arc(center, radius, 0.0, TAU, 96, COLOR_GRID, 2.0, true)
	draw_arc(center, radius * 0.67, 0.0, TAU, 72, COLOR_GRID_DIM, 1.0, true)
	draw_arc(center, radius * 0.34, 0.0, TAU, 48, COLOR_GRID_DIM, 1.0, true)

	# Two compressed great circles sell a spherical volume without allocating a
	# temporary point array every rendered frame.
	draw_set_transform(center, 0.0, Vector2(0.42, 1.0))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, COLOR_GRID_DIM, 1.0, true)
	draw_set_transform(center, 0.0, Vector2(1.0, 0.38))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 80, COLOR_GRID_DIM, 1.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_line(
		center - Vector2(radius, 0.0),
		center + Vector2(radius, 0.0),
		COLOR_GRID_DIM,
		1.0,
		true
	)
	draw_line(
		center - Vector2(0.0, radius),
		center + Vector2(0.0, radius),
		COLOR_GRID_DIM,
		1.0,
		true
	)
	# Compass glyphs are part of the radar face, not badges floating above it.
	# Draw them before the beam so the sweep crosses their pixels naturally.
	_draw_compass(center, radius)

	for trail_index: int in range(SWEEP_TRAIL_COUNT - 1, -1, -1):
		var trail_ratio := 1.0 - (
			float(trail_index) / float(SWEEP_TRAIL_COUNT)
		)
		var trail_angle := sweep_angle - float(trail_index) * SWEEP_TRAIL_SPACING
		var trail_direction := Vector2(
			sin(trail_angle),
			-cos(trail_angle)
		)
		draw_line(
			center,
			center + trail_direction * radius,
			Color(
				COLOR_SWEEP.r,
				COLOR_SWEEP.g,
				COLOR_SWEEP.b,
				COLOR_SWEEP.a * trail_ratio * trail_ratio
			),
			1.0 + trail_ratio,
			true
		)

	for contact: Dictionary in contacts:
		_draw_contact(contact, center, radius)
	draw_circle(center, 3.0, COLOR_SWEEP)
	draw_arc(center, 6.5, 0.0, TAU, 20, COLOR_GRID, 1.0, true)


func _draw_compass(center: Vector2, radius: float) -> void:
	var north := Vector2(sin(heading_yaw), -cos(heading_yaw))
	var east := Vector2(-north.y, north.x)
	var font := get_theme_default_font()
	var font_size := clampi(roundi(radius * 0.14), 8, 13)
	_draw_cardinal_marker(
		"N", north, center, radius, COLOR_COMPASS_NORTH, font, font_size
	)
	_draw_cardinal_marker(
		"E", east, center, radius, COLOR_COMPASS, font, font_size
	)
	_draw_cardinal_marker(
		"S", -north, center, radius, COLOR_COMPASS, font, font_size
	)
	_draw_cardinal_marker(
		"W", -east, center, radius, COLOR_COMPASS, font, font_size
	)


func _draw_cardinal_marker(
	label: String,
	direction: Vector2,
	center: Vector2,
	radius: float,
	color: Color,
	font: Font,
	font_size: int
) -> void:
	var tick_outer := center + direction * radius
	var tick_inner := center + direction * maxf(
		radius - COMPASS_TICK_INSET_PIXELS,
		0.0
	)
	draw_line(tick_inner, tick_outer, color, 1.5, true)

	var point := center + direction * radius * COMPASS_LABEL_RADIUS_RATIO
	var label_size := font.get_string_size(
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)
	draw_string(
		font,
		point + Vector2(-label_size.x * 0.5, label_size.y * 0.34),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _draw_contact(
	contact: Dictionary,
	center: Vector2,
	radius: float
) -> void:
	var contact_id: StringName = contact.get("contact_id", &"")
	var age := float(ping_ages.get(contact_id, INF))
	if age > CONTACT_MEMORY_SECONDS:
		return
	var relative_position := _resolved_relative_position(contact)
	var planar := Vector2(relative_position.x, relative_position.z)
	var normalized_planar := planar / maximum_range_meters
	if normalized_planar.length_squared() > 1.0:
		normalized_planar = normalized_planar.normalized()
	var point := center + normalized_planar * radius
	var hot := 1.0 - clampf(age / CONTACT_HIGHLIGHT_SECONDS, 0.0, 1.0)
	var memory := 1.0 - clampf(age / CONTACT_MEMORY_SECONDS, 0.0, 1.0)
	var strength := clampf(
		SafeVariant.finite_float_or(contact.get("signal_strength"), 1.0),
		0.15,
		2.0
	)
	var color := COLOR_CONTACT.lerp(COLOR_CONTACT_HOT, hot)
	color.a = clampf((0.34 + memory * 0.66) * strength, 0.0, 1.0)
	draw_circle(point, 2.7 + hot * 2.2, color)
	draw_arc(
		point,
		6.0 + hot * 5.0,
		0.0,
		TAU,
		24,
		Color(color.r, color.g, color.b, hot * 0.72),
		1.2,
		true
	)
	if contact_id == selected_contact_id:
		draw_arc(point, 11.5, 0.0, TAU, 28, COLOR_SELECTED, 1.8, true)
		draw_line(point + Vector2(-15.0, 0.0), point + Vector2(-9.0, 0.0), COLOR_SELECTED, 1.4, true)
		draw_line(point + Vector2(9.0, 0.0), point + Vector2(15.0, 0.0), COLOR_SELECTED, 1.4, true)
	var elevation_ratio := clampf(
		relative_position.y / maximum_range_meters,
		-1.0,
		1.0
	)
	if absf(elevation_ratio) > 0.025:
		var elevation_tip := point + Vector2(0.0, -elevation_ratio * 18.0)
		draw_line(point, elevation_tip, color, 1.0, true)
		draw_circle(elevation_tip, 1.8, color)


func _contact_angle(contact: Dictionary) -> float:
	var relative_position := _resolved_relative_position(contact)
	return fposmod(
		atan2(relative_position.x, -relative_position.z),
		TAU
	)


func _contact_point(contact: Dictionary) -> Vector2:
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * 0.44, 1.0)
	var relative_position := _resolved_relative_position(contact)
	var normalized_planar := Vector2(
		relative_position.x,
		relative_position.z
	) / maximum_range_meters
	if normalized_planar.length_squared() > 1.0:
		normalized_planar = normalized_planar.normalized()
	return center + normalized_planar * radius


func _resolved_relative_position(contact: Dictionary) -> Vector3:
	var world_offset := SafeVariant.vector3_strict_or(
		contact.get("world_offset", Vector3.INF),
		Vector3.INF
	)
	if world_offset.is_finite():
		return world_to_heading * world_offset
	return SafeVariant.vector3_strict_or(
		contact.get("relative_position", Vector3.ZERO),
		Vector3.ZERO
	)


func _cardinal_screen_direction(cardinal: StringName) -> Vector2:
	var north := Vector2(sin(heading_yaw), -cos(heading_yaw))
	match cardinal:
		&"N":
			return north
		&"E":
			return Vector2(-north.y, north.x)
		&"S":
			return -north
		&"W":
			return Vector2(north.y, -north.x)
	return Vector2.ZERO


func _contact_at(local_position: Vector2) -> Dictionary:
	var closest: Dictionary = {}
	var closest_distance_squared := CONTACT_HIT_RADIUS_PIXELS * CONTACT_HIT_RADIUS_PIXELS
	for contact: Dictionary in contacts:
		var contact_id: StringName = contact.get("contact_id", &"")
		if float(ping_ages.get(contact_id, INF)) > CONTACT_MEMORY_SECONDS:
			continue
		var distance_squared := local_position.distance_squared_to(
			_contact_point(contact)
		)
		if distance_squared <= closest_distance_squared:
			closest_distance_squared = distance_squared
			closest = contact
	return closest


func _find_contact(contact_id: StringName) -> Dictionary:
	for contact: Dictionary in contacts:
		if contact.get("contact_id", &"") == contact_id:
			return contact
	return {}


func _set_hovered_contact(contact: Dictionary) -> void:
	var next_contact_id: StringName = contact.get("contact_id", &"")
	if next_contact_id == hovered_contact_id:
		return
	if not hovered_contact_id.is_empty():
		contact_hover_ended.emit()
	hovered_contact_id = next_contact_id
	mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
		if not hovered_contact_id.is_empty()
		else Control.CURSOR_ARROW
	)
	if not contact.is_empty():
		contact_hovered.emit(contact)


func _clear_hover() -> void:
	_set_hovered_contact({})
