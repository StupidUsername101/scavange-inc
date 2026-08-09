extends StaticBody3D

const SHOP_LAYOUT := preload(
	"res://scripts/characters/body_part_shop_layout.gd"
)

const SCREEN_CENTER := Vector2(0.0, 1.73)
const SCREEN_WORLD_SIZE := Vector2(2.68, 1.02)
const PURCHASE_COOLDOWN_MSEC := 220
const FULFILLMENT_OFFSETS := [
	Vector3(2.05, 0.62, 0.3),
	Vector3(2.05, 0.62, -0.25),
	Vector3(2.05, 0.62, 0.85),
]
const FULFILLMENT_LAUNCH_VELOCITY := Vector3(0.0, 0.35, 0.0)

#######################################################
# Owns authoritative body-parts menu selection, purchase validation, and immediate physical
# fulfillment beside the terminal.
#######################################################

@export var station_id := 2

var buyable_limbs: Array[LimbDefinition] = []
var catalog_document: Dictionary = {}
var category_indices_by_player_id: Dictionary = {}
var selected_limb_paths_by_player_id: Dictionary = {}
var status_by_player_id: Dictionary = {}
var last_purchase_msec_by_player_id: Dictionary = {}
var fulfillment_index := 0


func _ready() -> void:
	add_to_group("body_part_shop_terminals")
	buyable_limbs = BodyPartShopCatalog.load_buyable_limbs()
	catalog_document = BodyPartShopCatalog.build_document(buyable_limbs)
	Server.register_body_part_shop_terminal(station_id, self)


func _exit_tree() -> void:
	Server.unregister_body_part_shop_terminal(station_id, self)


func server_primary_action(player: ServerPlayer, hit: Dictionary) -> void:
	if player == null or not _is_terminal_hit(hit):
		return
	_handle_menu_action(player.player_id, hit)


func _handle_menu_action(player_id: int, hit: Dictionary) -> void:
	var screen_position := _hit_to_screen_position(hit)
	var categories: Array = catalog_document.get("children", [])
	var category_index := clampi(
		int(category_indices_by_player_id.get(player_id, 0)),
		0,
		maxi(categories.size() - 1, 0)
	)
	var clicked_category := SHOP_LAYOUT.get_category_index_at(
		screen_position,
		categories.size()
	)
	if clicked_category >= 0:
		category_indices_by_player_id[player_id] = clicked_category
		selected_limb_paths_by_player_id.erase(player_id)
		_clear_status(player_id)
		return

	var products := BodyPartShopCatalog.get_category_products(
		catalog_document,
		category_index
	)
	var clicked_product := SHOP_LAYOUT.get_product_index_at(
		screen_position,
		products.size()
	)
	if clicked_product >= 0:
		selected_limb_paths_by_player_id[player_id] = str(
			products[clicked_product].get("limb_path", "")
		)
		_clear_status(player_id)
		return

	if SHOP_LAYOUT.PURCHASE_RECT.has_point(screen_position):
		var selected_path := str(
			selected_limb_paths_by_player_id.get(player_id, "")
		)
		for product: Dictionary in products:
			if str(product.get("limb_path", "")) == selected_path:
				_purchase_and_fulfill(player_id, product)
				return


func _purchase_and_fulfill(player_id: int, leaf: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var last_purchase := int(
		last_purchase_msec_by_player_id.get(player_id, -100000)
	)
	if now - last_purchase < PURCHASE_COOLDOWN_MSEC:
		return
	last_purchase_msec_by_player_id[player_id] = now

	var limb_path := str(leaf.get("limb_path", ""))
	var limb := BodyPartShopCatalog.find_limb_by_path(
		buyable_limbs,
		limb_path
	)
	if limb == null:
		_set_status(
			player_id,
			"ORDER REJECTED // CATALOG ENTRY NO LONGER AVAILABLE",
			true
		)
		return

	var result := Server.schedule_body_part_order(
		player_id,
		limb,
		station_id
	)
	if not bool(result.get("success", false)):
		_set_status(
			player_id,
			str(result.get("message", "ORDER REJECTED")),
			true
		)
		return

	var order: Dictionary = result.get("order", {})
	var delivered_item := _spawn_ordered_limb(limb)
	if delivered_item == null:
		_set_status(
			player_id,
			"ORDER PAID // FULFILLMENT ERROR — CONTACT SUPERVISOR",
			true
		)
		return
	Server.mark_body_part_order_delivered(int(order.get("order_id", -1)))
	_set_status(
		player_id,
		"ORDER #%04d READY ON PICKUP PAD" % int(
			order.get("order_id", 0)
		),
		false
	)


func _spawn_ordered_limb(limb: LimbDefinition) -> ServerItem:
	if limb == null or limb.shop_item_path.is_empty():
		return null
	var item_definition := load(limb.shop_item_path) as ItemDefinition
	if item_definition == null:
		return null
	var offset: Vector3 = FULFILLMENT_OFFSETS[
		fulfillment_index % FULFILLMENT_OFFSETS.size()
	]
	fulfillment_index += 1
	var item := Server.spawn_item(
		item_definition,
		global_transform * Transform3D(Basis.IDENTITY, offset)
	)
	if item != null:
		item.linear_velocity = global_basis * FULFILLMENT_LAUNCH_VELOCITY
	return item


func _set_status(player_id: int, message: String, is_error: bool) -> void:
	status_by_player_id[player_id] = {
		"message": message,
		"is_error": is_error,
	}


func _clear_status(player_id: int) -> void:
	status_by_player_id.erase(player_id)


func _is_terminal_hit(hit: Dictionary) -> bool:
	var world_position: Vector3 = hit.get("position", global_position)
	var local_position := to_local(world_position)
	return (
		absf(local_position.x - SCREEN_CENTER.x)
			<= SCREEN_WORLD_SIZE.x * 0.5
		and absf(local_position.y - SCREEN_CENTER.y)
			<= SCREEN_WORLD_SIZE.y * 0.5
		and local_position.z < -0.42
	)


func _hit_to_screen_position(hit: Dictionary) -> Vector2:
	var world_position: Vector3 = hit.get("position", global_position)
	var local_position := to_local(world_position)
	var normalized_x := (
		local_position.x - (SCREEN_CENTER.x - SCREEN_WORLD_SIZE.x * 0.5)
	) / SCREEN_WORLD_SIZE.x
	var normalized_y := (
		(SCREEN_CENTER.y + SCREEN_WORLD_SIZE.y * 0.5) - local_position.y
	) / SCREEN_WORLD_SIZE.y
	return Vector2(
		clampf(normalized_x, 0.0, 1.0) * SHOP_LAYOUT.SCREEN_SIZE.x,
		clampf(normalized_y, 0.0, 1.0) * SHOP_LAYOUT.SCREEN_SIZE.y
	)


func to_state_dict() -> Dictionary:
	var credits_by_player_id: Dictionary = {}
	var orders_by_player_id: Dictionary = {}
	var fulfilled_order_count := 0
	for player_id: int in Server.get_active_player_ids():
		credits_by_player_id[player_id] = GameState.get_player_money(
			player_id
		)
		orders_by_player_id[player_id] = (
			Server.get_body_part_orders_for_player(player_id)
		)
	for order: Dictionary in Server.body_part_delivery_orders:
		if str(order.get("status", "")) == "delivered":
			fulfilled_order_count += 1

	return {
		"station_id": station_id,
		"catalog_document": catalog_document,
		"category_indices": category_indices_by_player_id,
		"selected_limb_paths": selected_limb_paths_by_player_id,
		"credits_by_player_id": credits_by_player_id,
		"orders_by_player_id": orders_by_player_id,
		"status_by_player_id": status_by_player_id,
		"fulfilled_order_count": fulfilled_order_count,
	}
