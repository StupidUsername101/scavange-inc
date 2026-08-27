extends "res://scripts/client/inspection_terminal_view.gd"

const LAYOUT := preload(
	"res://scripts/weapons/weapon_crafting_station_layout.gd"
)

const MACHINE_BACKGROUND := Color(0.025, 0.014, 0.019, 1.0)
const MACHINE_HEADER := Color(0.105, 0.018, 0.035, 1.0)
const MACHINE_REEL := Color(0.075, 0.046, 0.052, 1.0)
const MACHINE_REEL_DIM := Color(0.038, 0.029, 0.034, 1.0)
const MACHINE_REEL_SELECTED := Color(0.16, 0.085, 0.035, 1.0)
const MACHINE_GOLD := Color(1.0, 0.64, 0.12, 1.0)
const MACHINE_GOLD_DIM := Color(0.46, 0.28, 0.08, 1.0)
const MACHINE_TEXT := Color(1.0, 0.91, 0.72, 1.0)
const MACHINE_MUTED := Color(0.62, 0.48, 0.43, 1.0)
const MACHINE_READY := Color(0.24, 0.95, 0.54, 1.0)
const MACHINE_ERROR := Color(1.0, 0.25, 0.28, 1.0)
const MACHINE_CYAN := Color(0.25, 0.88, 0.95, 1.0)

var selection_indices: Array[int] = []
var summary: Dictionary = {}
var station_message := ""
var station_message_is_error := false
var hover_label: Label


func _ready() -> void:
	super._ready()
	size = LAYOUT.SCREEN_SIZE


func set_station_state(
	next_document: Dictionary,
	next_selection_indices: Array[int],
	next_summary: Dictionary,
	next_message: String,
	next_message_is_error: bool
) -> void:
	document = next_document.duplicate(true)
	selection_indices = next_selection_indices.duplicate()
	summary = next_summary.duplicate(true)
	station_message = next_message
	station_message_is_error = next_message_is_error
	if is_node_ready():
		_render_document()


func set_aim_indicator(next_position: Vector2, next_visible: bool) -> void:
	super.set_aim_indicator(next_position, next_visible)
	if hover_label != null:
		hover_label.text = _hover_hint(next_position) if next_visible else ""


func _render_document() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	hover_label = null
	_add_color_rect(Rect2(Vector2.ZERO, LAYOUT.SCREEN_SIZE), MACHINE_BACKGROUND)
	_draw_header()
	if document.is_empty():
		_add_label(
			self,
			"CONNECTING TO HOUSE INVENTORY…",
			Rect2(120.0, 280.0, 1100.0, 70.0),
			30,
			MACHINE_MUTED,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_create_aim_ring()
		return
	var lanes: Array = SafeVariant.array_copy(document.get("lanes", []), false)
	for lane_index: int in range(lanes.size()):
		_draw_lane(lane_index, SafeVariant.dictionary_copy(lanes[lane_index], false))
	_draw_footer()
	_create_aim_ring()


func _draw_header(_current: Dictionary = {}) -> void:
	_add_color_rect(LAYOUT.HEADER_RECT, MACHINE_HEADER)
	_add_color_rect(Rect2(0.0, 78.0, 1340.0, 4.0), MACHINE_GOLD)
	_add_label(
		self,
		"SCAV INC.",
		Rect2(26.0, 8.0, 260.0, 45.0),
		35,
		MACHINE_GOLD
	)
	_add_label(
		self,
		"HOUSE ARMORY  //  CONFIGURATION PAYOUT",
		Rect2(290.0, 14.0, 720.0, 34.0),
		22,
		MACHINE_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_label(
		self,
		"NO REFUNDS  •  NO SHAPE GUARANTEE",
		Rect2(290.0, 47.0, 720.0, 23.0),
		13,
		MACHINE_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var ready := bool(summary.get("compatible", false))
	_add_label(
		self,
		"JACKPOT // %s" % ("ARMED" if ready else "MISALIGNED"),
		Rect2(1030.0, 18.0, 280.0, 38.0),
		20,
		MACHINE_READY if ready else MACHINE_ERROR,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_lane(lane_index: int, lane: Dictionary) -> void:
	var lane_rect := LAYOUT.get_lane_rect(lane_index)
	var required := bool(lane.get("required", false))
	_add_label(
		self,
		str(lane.get("label", "LANE")),
		Rect2(
			LAYOUT.LANE_LABEL_X,
			lane_rect.position.y + 5.0,
			LAYOUT.LANE_LABEL_WIDTH,
			28.0
		),
		18,
		MACHINE_TEXT
	)
	_add_label(
		self,
		"REQUIRED" if required else "OPTIONAL",
		Rect2(
			LAYOUT.LANE_LABEL_X,
			lane_rect.position.y + 34.0,
			LAYOUT.LANE_LABEL_WIDTH,
			24.0
		),
		12,
		MACHINE_ERROR if required else MACHINE_MUTED
	)
	var options: Array = SafeVariant.array_copy(lane.get("options", []), false)
	if options.is_empty():
		return
	var selected_index := clampi(
		selection_indices[lane_index] if lane_index < selection_indices.size() else 0,
		0,
		options.size() - 1
	)
	_draw_option_cube(
		LAYOUT.get_previous_rect(lane_index),
		SafeVariant.dictionary_copy(options[posmod(selected_index - 1, options.size())], false),
		false,
		"◀"
	)
	_draw_option_cube(
		LAYOUT.get_selected_rect(lane_index),
		SafeVariant.dictionary_copy(options[selected_index], false),
		true,
		"◆"
	)
	_draw_option_cube(
		LAYOUT.get_next_rect(lane_index),
		SafeVariant.dictionary_copy(options[posmod(selected_index + 1, options.size())], false),
		false,
		"▶"
	)


func _draw_option_cube(
	rect: Rect2,
	option: Dictionary,
	selected: bool,
	glyph: String
) -> void:
	var panel := _add_panel(
		self,
		rect,
		MACHINE_REEL_SELECTED if selected else MACHINE_REEL_DIM,
		MACHINE_GOLD if selected else MACHINE_GOLD_DIM,
		3 if selected else 1
	)
	var component_color: Color = option.get("color", MACHINE_GOLD_DIM)
	_add_panel(
		panel,
		Rect2(7.0, 7.0, 10.0, rect.size.y - 14.0),
		component_color,
		component_color,
		0
	)
	_add_label(
		panel,
		glyph,
		Rect2(20.0, 6.0, 30.0, rect.size.y - 12.0),
		18,
		MACHINE_GOLD if selected else MACHINE_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_label(
		panel,
		str(option.get("title", "EMPTY")),
		Rect2(54.0, 5.0, rect.size.x - 66.0, 30.0),
		17 if selected else 15,
		MACHINE_TEXT if selected else MACHINE_MUTED
	)
	_add_label(
		panel,
		"%s  //  %s  //  %.2f KG" % [
			str(option.get("inventory_code", "---")),
			str(option.get("caliber", "OPEN")),
			SafeVariant.finite_float_or(option.get("mass"), 0.0),
		],
		Rect2(54.0, 35.0, rect.size.x - 66.0, 23.0),
		11,
		MACHINE_GOLD if selected else MACHINE_MUTED
	)


func _draw_footer() -> void:
	var ready := bool(summary.get("compatible", false))
	var panel := _add_panel(
		self,
		LAYOUT.FOOTER_RECT,
		MACHINE_REEL,
		MACHINE_GOLD_DIM,
		2
	)
	_add_label(
		panel,
		"PAYOUT MANIFEST",
		Rect2(18.0, 10.0, 260.0, 30.0),
		18,
		MACHINE_GOLD
	)
	_add_label(
		panel,
		"%d BARRELS   %.2f KG   %d ROUNDS   %s   %.1f RPS" % [
			SafeVariant.integral_int_or(summary.get("barrel_count"), 0),
			SafeVariant.finite_float_or(summary.get("mass"), 0.0),
			SafeVariant.integral_int_or(summary.get("capacity"), 0),
			"AUTO" if bool(summary.get("automatic", false)) else "SEMI",
			SafeVariant.finite_float_or(summary.get("rounds_per_second"), 0.0),
		],
		Rect2(18.0, 43.0, 760.0, 30.0),
		17,
		MACHINE_TEXT
	)
	var errors: Array = SafeVariant.array_copy(summary.get("errors", []), false)
	var validation_text := (
		"ALL REQUIRED SYSTEMS PRESENT // CALIBER ALIGNED"
		if ready
		else "BLOCKED // %s" % ", ".join(errors).to_upper()
	)
	_add_label(
		panel,
		station_message if not station_message.is_empty() else validation_text,
		Rect2(18.0, 76.0, 940.0, 31.0),
		15,
		(
			MACHINE_ERROR
			if station_message_is_error or not ready
			else MACHINE_READY
		)
	)
	_add_label(
		panel,
		"OPTICS BUS RESERVED  //  MODULE NOT INSTALLED",
		Rect2(18.0, 110.0, 720.0, 24.0),
		13,
		MACHINE_CYAN
	)
	hover_label = _add_label(
		panel,
		"",
		Rect2(18.0, 137.0, 920.0, 28.0),
		12,
		MACHINE_MUTED
	)
	var craft_rect := Rect2(
		LAYOUT.CRAFT_RECT.position - LAYOUT.FOOTER_RECT.position,
		LAYOUT.CRAFT_RECT.size
	)
	var craft_panel := _add_panel(
		panel,
		craft_rect,
		MACHINE_GOLD if ready else Color(0.22, 0.12, 0.12, 1.0),
		MACHINE_TEXT if ready else MACHINE_ERROR,
		3
	)
	_add_label(
		craft_panel,
		"PULL // PAYOUT" if ready else "PAYOUT LOCKED",
		Rect2(10.0, 6.0, craft_rect.size.x - 20.0, 32.0),
		22,
		MACHINE_BACKGROUND if ready else MACHINE_ERROR,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_label(
		craft_panel,
		"FABRICATE PHYSICAL WEAPON" if ready else "ALIGN ALL REQUIRED LANES",
		Rect2(10.0, 38.0, craft_rect.size.x - 20.0, 22.0),
		11,
		MACHINE_BACKGROUND if ready else MACHINE_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _hover_hint(point: Vector2) -> String:
	var lanes: Array = SafeVariant.array_copy(document.get("lanes", []), false)
	for lane_index: int in range(lanes.size()):
		if LAYOUT.get_previous_rect(lane_index).has_point(point):
			return "CYCLE THIS REEL BACKWARD"
		if LAYOUT.get_selected_rect(lane_index).has_point(point):
			return "CYCLE SELECTED REEL FORWARD"
		if LAYOUT.get_next_rect(lane_index).has_point(point):
			return "CYCLE THIS REEL FORWARD"
	if LAYOUT.CRAFT_RECT.has_point(point):
		return "AUTHORITATIVE PAYOUT // SPAWNS BUILD ON THE OUTPUT TRAY"
	return "REPEATED PARTS ARE LEGAL // FUNCTION REQUIRES ACTION, BARREL, FEED, AND LOAD"


func _add_color_rect(rect: Rect2, color: Color) -> ColorRect:
	var result := ColorRect.new()
	result.position = rect.position
	result.size = rect.size
	result.color = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result
