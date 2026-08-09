extends SceneTree

const PLAYER_SCENE := preload("res://scenes/server/server_player.tscn")
const SHOP_LAYOUT := preload(
	"res://scripts/characters/body_part_shop_layout.gd"
)
const REQUIRED_LIMB_PATHS := PackedStringArray([
	"res://resources/limbs/human_left_arm.tres",
	"res://resources/limbs/human_right_arm.tres",
	"res://resources/limbs/human_left_leg.tres",
	"res://resources/limbs/human_right_leg.tres",
])
const TEST_PEER_ID := 991337

#######################################################
# Runs headless regression coverage for body part shop system behavior and reports contract or
# integration failures.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_contract()
	_test_authoritative_order_queue()
	_test_terminal_wiring()

	if failure_count == 0:
		print(
			"Body-parts shop tests passed: %d assertions"
			% assertion_count
		)
		quit(0)
	else:
		push_error(
			"Body-parts shop tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_catalog_contract() -> void:
	var limbs := BodyPartShopCatalog.load_buyable_limbs()
	_expect(limbs.size() >= 4, "the four human baseline limbs are buyable")

	var document := BodyPartShopCatalog.build_document(limbs)
	var root_children: Array = document.get("children", [])
	_expect(
		_find_child(root_children, "Arms").size() > 0,
		"the root exposes an arms branch"
	)
	_expect(
		_find_child(root_children, "Legs").size() > 0,
		"the root exposes a legs branch"
	)

	var leaf_paths := PackedStringArray()
	_collect_leaf_paths(document, leaf_paths)
	_expect(
		leaf_paths.size() == limbs.size(),
		"every buyable limb becomes exactly one terminal leaf"
	)
	for required_path: String in REQUIRED_LIMB_PATHS:
		_expect(
			leaf_paths.has(required_path),
			"the baseline catalog contains " + required_path.get_file()
		)

	for limb: LimbDefinition in limbs:
		_expect(limb.shop_price > 0, limb.display_name + " has a price")
		_expect(
			limb.shop_category_path.size() >= 2,
			limb.display_name + " has a recursive category path"
		)
		_expect(
			leaf_paths.has(limb.resource_path),
			limb.display_name + " resolves to its resource path"
		)
		var delivery_item := load(limb.shop_item_path) as BodyPartItemDefinition
		_expect(
			delivery_item != null
			and delivery_item.limb_definition == limb,
			limb.display_name + " has a matching physical delivery item"
		)

	_expect(
		Rect2(Vector2.ZERO, SHOP_LAYOUT.SCREEN_SIZE).encloses(
			SHOP_LAYOUT.PURCHASE_RECT
		),
		"the purchase target stays inside the physical terminal screen"
	)
	var first_category_products := BodyPartShopCatalog.get_category_products(
		document,
		0
	)
	_expect(
		not first_category_products.is_empty(),
		"the flat menu exposes products from its selected department"
	)


func _test_authoritative_order_queue() -> void:
	var player_id := GameState.try_register_player(
		TEST_PEER_ID,
		1000,
		4
	)
	_expect(player_id > 0, "the test player registers with starting credit")
	if player_id <= 0:
		return

	var player := PLAYER_SCENE.instantiate() as ServerPlayer
	root.add_child(player)
	player.setup(player_id, Vector3.ZERO)
	Server.server_players_by_player_id[player_id] = player

	var limbs := BodyPartShopCatalog.load_buyable_limbs()
	var limb: LimbDefinition = (
		limbs[0] if not limbs.is_empty() else null
	)
	_expect(limb != null, "a catalog limb is available for ordering")
	if limb != null:
		var credit_before := GameState.get_player_money(player_id)
		var order_count_before := Server.body_part_delivery_orders.size()
		var result := Server.schedule_body_part_order(player_id, limb, 2)
		_expect(bool(result.get("success", false)), "a valid order succeeds")
		_expect(
			GameState.get_player_money(player_id)
				== credit_before - limb.shop_price,
			"the authoritative balance pays the exact catalog price"
		)
		_expect(
			Server.body_part_delivery_orders.size()
				== order_count_before + 1,
			"a successful purchase appends one delivery order"
		)
		var order: Dictionary = result.get("order", {})
		_expect(
			str(order.get("limb_path", "")) == limb.resource_path
			and int(order.get("player_id", -1)) == player_id
			and str(order.get("status", "")) == "scheduled",
			"the order retains its player, payload and scheduled state"
		)
		_expect(
			Server.mark_body_part_order_delivered(
				int(order.get("order_id", -1))
			),
			"the queue exposes the future delivery completion transition"
		)

	var invalid_result := Server.schedule_body_part_order(
		player_id + 5000,
		limb,
		2
	)
	_expect(
		not bool(invalid_result.get("success", false)),
		"an order without an authoritative player is rejected"
	)

	Server.server_players_by_player_id.erase(player_id)
	GameState.unregister_peer(TEST_PEER_ID)
	player.free()


func _test_terminal_wiring() -> void:
	var server_scene := load(
		"res://scenes/server/body_part_shop_terminal.tscn"
	) as PackedScene
	var proxy_scene := load(
		"res://scenes/proxy/body_part_shop_terminal.tscn"
	) as PackedScene
	_expect(server_scene != null, "the authoritative shop scene loads")
	_expect(proxy_scene != null, "the client shop scene loads")

	if server_scene != null:
		var terminal := server_scene.instantiate()
		_expect(
			terminal.has_method("server_primary_action")
			and terminal.has_method("to_state_dict"),
			"the server terminal owns navigation and replicated state"
		)
		terminal.free()

	if proxy_scene != null:
		var proxy := proxy_scene.instantiate()
		_expect(
			proxy.has_node("TerminalScreen")
			and proxy.has_node("Title")
			and proxy.has_node("OccupiedLight")
			and proxy.has_node("PickupPad"),
			"the shop has a flat kiosk screen and adjacent pickup pad"
		)
		proxy.free()

	var proxy_source := FileAccess.get_file_as_string(
		"res://scripts/client/body_part_shop_terminal_proxy.gd"
	)
	var view_source := FileAccess.get_file_as_string(
		"res://scripts/client/body_part_shop_terminal_view.gd"
	)
	_expect(
		proxy_source.contains("\"set_aim_indicator\"")
		and view_source.contains(
			"res://scripts/characters/body_part_shop_layout.gd"
		),
		"the flat shop menu retains the scanner cursor indicator"
	)
	_expect(
		view_source.contains("\"Scav. Inc.\"")
		and not view_source.contains("DEPTH")
		and not view_source.contains("breadcrumb"),
		"the shop uses corporate ordering-menu branding instead of scanner navigation"
	)


func _find_child(children: Array, title: String) -> Dictionary:
	for child_value: Variant in children:
		var child: Dictionary = child_value
		if str(child.get("title", "")) == title:
			return child
	return {}


func _collect_leaf_paths(
	node: Dictionary,
	result: PackedStringArray
) -> void:
	if BodyPartShopCatalog.is_limb_leaf(node):
		result.append(str(node.get("limb_path", "")))
	for child_value: Variant in node.get("children", []):
		var child: Dictionary = child_value
		_collect_leaf_paths(child, result)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: " + message)
