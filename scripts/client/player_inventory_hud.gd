extends Control
class_name PlayerInventoryHud

const COLOR_PANEL := Color(0.008, 0.028, 0.024, 0.86)
const COLOR_PANEL_INNER := Color(0.015, 0.06, 0.05, 0.9)
const COLOR_BORDER := Color(0.12, 0.58, 0.42, 0.95)
const COLOR_BORDER_DIM := Color(0.06, 0.29, 0.23, 0.9)
const COLOR_TEXT := Color(0.66, 1.0, 0.78, 1.0)
const COLOR_MUTED := Color(0.35, 0.69, 0.53, 1.0)
const COLOR_HEALTH := Color(0.94, 0.31, 0.21, 1.0)
const COLOR_STAMINA := Color(0.96, 0.67, 0.18, 1.0)
const SLOT_SIZE := Vector2(56.0, 48.0)
const SLOT_GAP := 7.0
const SEGMENT_COUNT := 8
const INVENTORY_WIDTH_SMOOTHING_RATE := 14.0
const CAPACITY_PULSE_DECAY_RATE := 3.8
const CAPACITY_PULSE_SCALE := 0.08
const VITALS_ORIGIN := Vector2(24.0, 25.0)
const VITALS_ROW_HEIGHT := 31.0
const INVENTORY_BOTTOM_MARGIN := 27.0

#######################################################
# Draws the eye-dependent player HUD, expandable inventory slots, equipment badges,
# interaction hints, health, and stamina.
#######################################################

var health_ratio := 1.0
var stamina_ratio := 1.0
var capacity := 1
var selected_slot := 0
var inventory_entries: Array = []
var equipment: Dictionary = {}
var interaction_hint := ""
var hold_progress := 0.0
var weapon_reload_ratio := 0.0
var plasma_cutter_selected := false
var plasma_cutter_heat_ratio := 0.0
var plasma_cutter_overheated := false
var displayed_inventory_width := SLOT_SIZE.x
var capacity_pulse := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func apply_player_state(state: Dictionary, apply_inventory := true) -> void:
	health_ratio = clampf(
		SafeVariant.finite_float_or(state.get("health_ratio", health_ratio), health_ratio),
		0.0,
		1.0
	)
	stamina_ratio = clampf(
		SafeVariant.finite_float_or(state.get("stamina_ratio", stamina_ratio), stamina_ratio),
		0.0,
		1.0
	)
	interaction_hint = str(state.get("interaction_hint", ""))
	weapon_reload_ratio = clampf(
		SafeVariant.finite_float_or(state.get("weapon_reload_ratio", 0.0), 0.0),
		0.0,
		1.0
	)
	plasma_cutter_selected = SafeVariant.strict_bool_or(
		state.get("plasma_cutter_available", false),
		false
	)
	plasma_cutter_heat_ratio = clampf(
		SafeVariant.finite_float_or(
			state.get("plasma_cutter_heat_ratio", 0.0),
			0.0
		),
		0.0,
		1.0
	)
	plasma_cutter_overheated = SafeVariant.strict_bool_or(
		state.get("plasma_cutter_overheated", false),
		false
	)

	if apply_inventory:
		var inventory: Dictionary = PlayerInventoryRules.sanitize_public_inventory(
			state.get("inventory", {})
		)
		var next_capacity: int = int(inventory["capacity"])
		if next_capacity != capacity:
			capacity = next_capacity
			capacity_pulse = 1.0
		selected_slot = int(inventory["selected_slot"])
		inventory_entries = (inventory["entries"] as Array).duplicate(true)
		equipment = (inventory["equipment"] as Dictionary).duplicate(true)
	queue_redraw()


func set_hold_progress(value: float) -> void:
	hold_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	var weight := 1.0 - exp(
		-delta * INVENTORY_WIDTH_SMOOTHING_RATE
	)
	var target_width := (
		float(capacity) * SLOT_SIZE.x
		+ float(capacity - 1) * SLOT_GAP
	)
	displayed_inventory_width = lerpf(
		displayed_inventory_width,
		target_width,
		weight
	)
	capacity_pulse = move_toward(
		capacity_pulse,
		0.0,
		delta * CAPACITY_PULSE_DECAY_RATE
	)
	queue_redraw()


func _draw() -> void:
	_draw_vitals()
	_draw_inventory()
	_draw_interaction_hint()


func _draw_vitals() -> void:
	var origin := VITALS_ORIGIN
	_draw_segment_bar(origin, "VIT", health_ratio, COLOR_HEALTH)
	_draw_segment_bar(
		origin + Vector2(0.0, VITALS_ROW_HEIGHT),
		"END",
		stamina_ratio,
		COLOR_STAMINA
	)


func _draw_segment_bar(
	origin: Vector2,
	label_text: String,
	ratio: float,
	active_color: Color
) -> void:
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		origin + Vector2(0.0, 17.0),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		38.0,
		13,
		COLOR_MUTED
	)
	draw_string(
		font,
		origin + Vector2(42.0, 17.0),
		"[",
		HORIZONTAL_ALIGNMENT_LEFT,
		10.0,
		17,
		COLOR_TEXT
	)
	var filled_segments := ceili(ratio * float(SEGMENT_COUNT))
	for segment_index: int in range(SEGMENT_COUNT):
		var segment_rect := Rect2(
			origin + Vector2(53.0 + float(segment_index) * 13.0, 6.0),
			Vector2(9.0, 11.0)
		)
		draw_rect(
			segment_rect,
			active_color if segment_index < filled_segments else COLOR_PANEL_INNER
		)
		draw_rect(segment_rect, COLOR_BORDER_DIM, false, 1.0)
	draw_string(
		font,
		origin + Vector2(158.0, 17.0),
		"]",
		HORIZONTAL_ALIGNMENT_LEFT,
		10.0,
		17,
		COLOR_TEXT
	)


func _draw_inventory() -> void:
	var pulse_scale := (
		1.0 + capacity_pulse * CAPACITY_PULSE_SCALE
	)
	var visual_width := maxf(displayed_inventory_width, SLOT_SIZE.x)
	var bar_origin := Vector2(
		(size.x - visual_width) * 0.5,
		size.y - SLOT_SIZE.y - INVENTORY_BOTTOM_MARGIN
	)
	var slot_step := 0.0
	if capacity > 1:
		slot_step = (
			visual_width - SLOT_SIZE.x
		) / float(capacity - 1)

	for slot_index: int in range(capacity):
		var slot_center := bar_origin + Vector2(
			float(slot_index) * slot_step
			+ SLOT_SIZE.x * 0.5,
			SLOT_SIZE.y * 0.5
		)
		var slot_size := SLOT_SIZE
		if slot_index == selected_slot:
			slot_size *= pulse_scale
		var slot_rect := Rect2(slot_center - slot_size * 0.5, slot_size)
		var selected := slot_index == selected_slot
		draw_rect(
			slot_rect,
			COLOR_PANEL_INNER if selected else COLOR_PANEL
		)
		draw_rect(
			slot_rect,
			COLOR_BORDER if selected else COLOR_BORDER_DIM,
			false,
			2.0 if selected else 1.0
		)

		var code := ""
		if slot_index < inventory_entries.size():
			var entry: Dictionary = inventory_entries[slot_index]
			code = str(entry.get("inventory_code", ""))
		if code.is_empty():
			code = "·"
		draw_string(
			ThemeDB.fallback_font,
			slot_rect.position + Vector2(0.0, 31.0),
			"[ %s ]" % code,
			HORIZONTAL_ALIGNMENT_CENTER,
			slot_rect.size.x,
			14,
			COLOR_TEXT if selected else COLOR_MUTED
		)
		if slot_index < inventory_entries.size():
			var entry: Dictionary = inventory_entries[slot_index]
			var status_text := str(entry.get("status_text", ""))
			if not status_text.is_empty():
				draw_string(
					ThemeDB.fallback_font,
					slot_rect.position + Vector2(4.0, 13.0),
					status_text,
					HORIZONTAL_ALIGNMENT_LEFT,
					slot_rect.size.x - 8.0,
					9,
					COLOR_STAMINA if selected else COLOR_MUTED
				)
		if selected and weapon_reload_ratio > 0.0:
			var reload_progress := 1.0 - weapon_reload_ratio
			draw_rect(
				Rect2(
					slot_rect.position
					+ Vector2(3.0, slot_rect.size.y - 4.0),
					Vector2(
						(slot_rect.size.x - 6.0) * reload_progress,
						2.0
					)
				),
				COLOR_STAMINA
			)
		if selected and plasma_cutter_selected:
			var heat_color := (
				COLOR_HEALTH
				if plasma_cutter_overheated
				else COLOR_STAMINA.lerp(
					COLOR_HEALTH,
					plasma_cutter_heat_ratio * plasma_cutter_heat_ratio
				)
			)
			draw_rect(
				Rect2(
					slot_rect.position + Vector2(3.0, slot_rect.size.y - 4.0),
					Vector2(
						(slot_rect.size.x - 6.0) * plasma_cutter_heat_ratio,
						2.0
					)
				),
				heat_color
			)

	_draw_equipment_badges(bar_origin, visual_width)


func _draw_equipment_badges(bar_origin: Vector2, visual_width: float) -> void:
	var badges := PackedStringArray()
	if equipment.has(PlayerInventoryRules.EYES_SLOT):
		badges.append("EYE")
	if equipment.has(PlayerInventoryRules.BACKPACK_SLOT):
		badges.append("PACK")
	if equipment.has(PlayerInventoryRules.WRIST_DEVICE_SLOT):
		badges.append("LINK")
	if badges.is_empty():
		return

	var text := "  ".join(badges)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(bar_origin.x, bar_origin.y - 10.0),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		visual_width,
		12,
		COLOR_MUTED
	)


func _draw_interaction_hint() -> void:
	if interaction_hint.is_empty() and hold_progress <= 0.0:
		return
	var panel_width := 430.0
	var panel_rect := Rect2(
		Vector2((size.x - panel_width) * 0.5, size.y - 132.0),
		Vector2(panel_width, 34.0)
	)
	draw_rect(panel_rect, COLOR_PANEL)
	draw_rect(panel_rect, COLOR_BORDER_DIM, false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		panel_rect.position + Vector2(10.0, 22.0),
		interaction_hint,
		HORIZONTAL_ALIGNMENT_CENTER,
		panel_rect.size.x - 20.0,
		13,
		COLOR_TEXT
	)
	if hold_progress > 0.0:
		var progress_rect := Rect2(
			panel_rect.position + Vector2(4.0, panel_rect.size.y - 4.0),
			Vector2((panel_rect.size.x - 8.0) * hold_progress, 2.0)
		)
		draw_rect(progress_rect, COLOR_STAMINA)
