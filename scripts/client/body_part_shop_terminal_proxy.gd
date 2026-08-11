extends Node3D

const TERMINAL_VIEW_SCRIPT := preload(
	"res://scripts/client/body_part_shop_terminal_view.gd"
)
const SHOP_LAYOUT := preload(
	"res://scripts/characters/body_part_shop_layout.gd"
)

const SCREEN_CENTER := Vector2(0.0, 1.73)
const SCREEN_WORLD_SIZE := Vector2(2.68, 1.02)
const SCREEN_PLANE_Z := -0.555
const MAX_AIM_DISTANCE := 4.0

#######################################################
# Mirrors authoritative body part shop terminal state on clients and updates its local visual
# presentation.
#######################################################

@export var station_id := 2

@onready var terminal_screen: MeshInstance3D = $TerminalScreen
@onready var order_light: MeshInstance3D = $OccupiedLight
@onready var title_label: Label3D = $Title
@onready var instructions_label: Label3D = $Instructions

var catalog_document: Dictionary = {}
var selected_category_index := 0
var selected_limb_path := ""
var credits := 0
var orders: Array = []
var shop_message := ""
var shop_message_is_error := false
var has_fulfilled_orders := false
var terminal_viewport: SubViewport
var terminal_view: Control


func _ready() -> void:
	add_to_group("body_part_shop_terminal_proxies")
	title_label.text = "Scav. Inc."
	instructions_label.text = (
		"ORDERING TERMINAL  •  SELECT DEPARTMENT  •  PICK UP BESIDE KIOSK"
	)
	_build_terminal_surface()
	_update_order_indicator(false)
	set_process(true)


func _process(_delta: float) -> void:
	_update_terminal_aim_indicator()


func apply_server_state(state: Dictionary) -> void:
	var next_document: Dictionary = state.get("catalog_document", {})
	var next_category_index := int(_get_local_value(
		state.get("category_indices", {}),
		0
	))
	var next_limb_path := str(_get_local_value(
		state.get("selected_limb_paths", {}),
		""
	))
	var next_credits := int(_get_local_value(
		state.get("credits_by_player_id", {}),
		0
	))
	var next_orders_value: Variant = _get_local_value(
		state.get("orders_by_player_id", {}),
		[]
	)
	var next_orders: Array = next_orders_value
	var status_value: Variant = _get_local_value(
		state.get("status_by_player_id", {}),
		{}
	)
	var status: Dictionary = status_value
	var next_message := str(status.get("message", ""))
	var next_message_is_error := bool(status.get("is_error", false))

	if (
		next_document != catalog_document
		or next_category_index != selected_category_index
		or next_limb_path != selected_limb_path
		or next_credits != credits
		or next_orders != orders
		or next_message != shop_message
		or next_message_is_error != shop_message_is_error
	):
		catalog_document = next_document.duplicate(true)
		selected_category_index = next_category_index
		selected_limb_path = next_limb_path
		credits = next_credits
		orders = next_orders.duplicate(true)
		shop_message = next_message
		shop_message_is_error = next_message_is_error
		if terminal_view != null:
			terminal_view.call(
				"set_shop_state",
				catalog_document,
				selected_category_index,
				selected_limb_path,
				credits,
				orders,
				shop_message,
				shop_message_is_error
			)

	var next_has_fulfilled_orders := (
		int(state.get("fulfilled_order_count", 0)) > 0
	)
	if next_has_fulfilled_orders != has_fulfilled_orders:
		has_fulfilled_orders = next_has_fulfilled_orders
		_update_order_indicator(has_fulfilled_orders)


func _build_terminal_surface() -> void:
	terminal_viewport = SubViewport.new()
	terminal_viewport.name = "BodyPartShopViewport"
	terminal_viewport.size = Vector2i(
		roundi(SHOP_LAYOUT.SCREEN_SIZE.x),
		roundi(SHOP_LAYOUT.SCREEN_SIZE.y)
	)
	terminal_viewport.disable_3d = true
	terminal_viewport.gui_disable_input = true
	terminal_viewport.transparent_bg = false
	terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(terminal_viewport)

	terminal_view = TERMINAL_VIEW_SCRIPT.new() as Control
	terminal_viewport.add_child(terminal_view)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = terminal_viewport.get_texture()
	terminal_screen.material_override = material
	terminal_view.call(
		"set_shop_state",
		catalog_document,
		selected_category_index,
		selected_limb_path,
		credits,
		orders,
		shop_message,
		shop_message_is_error
	)


func _update_terminal_aim_indicator() -> void:
	TerminalAimIndicator.update(
		self,
		terminal_view,
		SCREEN_PLANE_Z,
		SCREEN_CENTER,
		SCREEN_WORLD_SIZE,
		MAX_AIM_DISTANCE,
		SHOP_LAYOUT.SCREEN_SIZE
	)

func _get_local_value(
	values_by_player_id: Dictionary,
	default_value: Variant
) -> Variant:
	if values_by_player_id.has(Client.local_player_id):
		return values_by_player_id[Client.local_player_id]
	var player_id_string := str(Client.local_player_id)
	if values_by_player_id.has(player_id_string):
		return values_by_player_id[player_id_string]
	return default_value


func _update_order_indicator(has_fulfilled_orders: bool) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	if has_fulfilled_orders:
		material.albedo_color = Color(0.12, 0.9, 0.42, 1.0)
		material.emission = Color(0.04, 0.7, 0.22, 1.0)
	else:
		material.albedo_color = Color(0.9, 0.56, 0.08, 1.0)
		material.emission = Color(0.55, 0.24, 0.015, 1.0)
	order_light.material_override = material
