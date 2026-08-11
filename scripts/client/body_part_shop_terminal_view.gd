extends "res://scripts/client/inspection_terminal_view.gd"

const SHOP_LAYOUT := preload(
	"res://scripts/characters/body_part_shop_layout.gd"
)

const SHOP_BACKGROUND := Color(0.925, 0.92, 0.875, 1.0)
const SHOP_HEADER := Color(0.055, 0.09, 0.105, 1.0)
const SHOP_PANEL := Color(0.985, 0.98, 0.94, 1.0)
const SHOP_PANEL_SELECTED := Color(0.12, 0.18, 0.19, 1.0)
const SHOP_BORDER := Color(0.73, 0.72, 0.66, 1.0)
const SHOP_TEXT := Color(0.075, 0.095, 0.1, 1.0)
const SHOP_TEXT_INVERSE := Color(0.96, 0.95, 0.89, 1.0)
const SHOP_MUTED := Color(0.36, 0.39, 0.39, 1.0)
const SHOP_ACCENT := Color(0.95, 0.47, 0.08, 1.0)
const SHOP_ERROR := Color(0.72, 0.12, 0.09, 1.0)

#######################################################
# Renders the body-parts shop as a flat corporate self-order menu while preserving the
# scanner-style world-space cursor indicator.
#######################################################

var credits := 0
var selected_category_index := 0
var selected_limb_path := ""
var shop_message := ""
var shop_message_is_error := false


func set_shop_state(
	next_document: Dictionary,
	next_category_index: int,
	next_limb_path: String,
	next_credits: int,
	_next_orders: Array,
	next_message: String,
	next_message_is_error: bool
) -> void:
	document = next_document.duplicate(true)
	selected_category_index = maxi(next_category_index, 0)
	selected_limb_path = next_limb_path
	credits = maxi(next_credits, 0)
	shop_message = next_message
	shop_message_is_error = next_message_is_error
	if is_node_ready():
		_render_document()


func _render_document() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_add_color_rect(self, Rect2(Vector2.ZERO, SHOP_LAYOUT.SCREEN_SIZE), SHOP_BACKGROUND)
	_draw_header()
	if document.is_empty():
		_add_label(
			self,
			"Connecting to product services…",
			Rect2(298.0, 190.0, 1018.0, 60.0),
			26,
			SHOP_MUTED,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_create_aim_ring()
		return

	var categories: Array = SafeVariant.array_copy(document.get("children", []), false)
	if not categories.is_empty():
		selected_category_index = clampi(
			selected_category_index,
			0,
			categories.size() - 1
		)
	_draw_categories(categories)
	var products := BodyPartShopCatalog.get_category_products(
		document,
		selected_category_index
	)
	_draw_products(products)
	_draw_selection(products)
	_create_aim_ring()


func _draw_header(d={}) -> void:
	_add_color_rect(self, SHOP_LAYOUT.HEADER_RECT, SHOP_HEADER)
	_add_color_rect(self, Rect2(0.0, 84.0, 1340.0, 4.0), SHOP_ACCENT)
	_add_label(
		self,
		"Scav. Inc.",
		Rect2(28.0, 12.0, 360.0, 58.0),
		43,
		SHOP_TEXT_INVERSE
	)
	_add_label(
		self,
		"BODY PARTS  /  EMPLOYEE PROCUREMENT",
		Rect2(390.0, 29.0, 580.0, 34.0),
		18,
		Color(0.7, 0.74, 0.72, 1.0)
	)
	_add_label(
		self,
		"BALANCE  %04d CR" % credits,
		Rect2(1010.0, 25.0, 300.0, 38.0),
		22,
		SHOP_TEXT_INVERSE,
		HORIZONTAL_ALIGNMENT_RIGHT
	)


func _draw_categories(categories: Array) -> void:
	_add_label(
		self,
		"DEPARTMENTS",
		Rect2(24.0, 88.0, 250.0, 20.0),
		13,
		SHOP_MUTED
	)
	for index: int in range(categories.size()):
		var category: Dictionary = SafeVariant.dictionary_copy(categories[index], false)
		var selected: bool = index == selected_category_index
		var rect := SHOP_LAYOUT.get_category_rect(index, categories.size())
		var panel := _add_panel(
			self,
			rect,
			SHOP_PANEL_SELECTED if selected else SHOP_PANEL,
			SHOP_PANEL_SELECTED if selected else SHOP_BORDER,
			2
		)
		_add_color_rect(
			panel,
			Rect2(0.0, 0.0, 7.0, rect.size.y),
			SHOP_ACCENT if selected else SHOP_BORDER
		)
		_add_label(
			panel,
			str(category.get("title", "Department")),
			Rect2(24.0, 14.0, rect.size.x - 38.0, 34.0),
			24,
			SHOP_TEXT_INVERSE if selected else SHOP_TEXT
		)
		var product_count := BodyPartShopCatalog.get_category_products(
			document,
			index
		).size()
		_add_label(
			panel,
			"%d PRODUCTS" % product_count,
			Rect2(24.0, 48.0, rect.size.x - 38.0, 24.0),
			14,
			Color(0.72, 0.76, 0.74, 1.0) if selected else SHOP_MUTED
		)


func _draw_products(products: Array[Dictionary]) -> void:
	_add_label(
		self,
		"AVAILABLE REPLACEMENTS",
		Rect2(298.0, 88.0, 1018.0, 20.0),
		13,
		SHOP_MUTED
	)
	for index: int in range(products.size()):
		var product = products[index]
		var selected := str(product.get("limb_path", "")) == selected_limb_path
		var rect := SHOP_LAYOUT.get_product_rect(index, products.size())
		var panel := _add_panel(
			self,
			rect,
			SHOP_PANEL,
			SHOP_ACCENT if selected else SHOP_BORDER,
			4 if selected else 2
		)
		_add_label(
			panel,
			str(product.get("title", "Replacement")),
			Rect2(20.0, 14.0, rect.size.x - 165.0, 34.0),
			24,
			SHOP_TEXT
		)
		_add_label(
			panel,
			"%d CR" % int(product.get("price", 0)),
			Rect2(rect.size.x - 150.0, 15.0, 128.0, 32.0),
			22,
			SHOP_ACCENT,
			HORIZONTAL_ALIGNMENT_RIGHT
		)
		_add_label(
			panel,
			str(product.get("subtitle", "")),
			Rect2(20.0, 53.0, rect.size.x - 40.0, 44.0),
			15,
			SHOP_MUTED
		)
		_add_label(
			panel,
			BodyPartShopCatalog.get_slot_name(
				int(product.get("socket", 0))
			).to_upper(),
			Rect2(20.0, rect.size.y - 32.0, rect.size.x - 40.0, 22.0),
			13,
			SHOP_TEXT
		)


func _draw_selection(products: Array[Dictionary]) -> void:
	var selected := _find_selected_product(products)
	var detail_panel := _add_panel(
		self,
		SHOP_LAYOUT.DETAIL_RECT,
		SHOP_PANEL,
		SHOP_BORDER,
		2
	)
	if selected.is_empty():
		_add_label(
			detail_panel,
			"Select a replacement",
			Rect2(20.0, 16.0, 590.0, 36.0),
			24,
			SHOP_TEXT
		)
		_add_label(
			detail_panel,
			"Choose a product above to review and order.",
			Rect2(20.0, 54.0, 590.0, 28.0),
			16,
			SHOP_MUTED
		)
	else:
		_add_label(
			detail_panel,
			str(selected.get("title", "Replacement")),
			Rect2(20.0, 12.0, 590.0, 34.0),
			23,
			SHOP_TEXT
		)
		var status_text := (
			shop_message
			if not shop_message.is_empty()
			else "Ready for immediate pickup beside this terminal."
		)
		_add_label(
			detail_panel,
			status_text,
			Rect2(20.0, 51.0, 590.0, 38.0),
			15,
			SHOP_ERROR if shop_message_is_error else SHOP_MUTED
		)

	var price := maxi(int(selected.get("price", 0)), 0)
	var can_buy := not selected.is_empty() and credits >= price
	var purchase_panel := _add_panel(
		self,
		SHOP_LAYOUT.PURCHASE_RECT,
		SHOP_ACCENT if can_buy else Color(0.72, 0.71, 0.66, 1.0),
		SHOP_ACCENT if can_buy else SHOP_BORDER,
		2
	)
	_add_label(
		purchase_panel,
		"ORDER NOW" if can_buy else "UNAVAILABLE",
		Rect2(18.0, 17.0, 334.0, 38.0),
		27,
		SHOP_HEADER,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_label(
		purchase_panel,
		(
			"%d CR  •  PICKUP NEXT TO KIOSK" % price
			if can_buy
			else "SELECT PRODUCT / CHECK BALANCE"
		),
		Rect2(18.0, 58.0, 334.0, 25.0),
		14,
		SHOP_HEADER,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _find_selected_product(products: Array[Dictionary]) -> Dictionary:
	for product: Dictionary in products:
		if str(product.get("limb_path", "")) == selected_limb_path:
			return product
	return {}


func _add_color_rect(
	parent: Control,
	rect: Rect2,
	color: Color
) -> ColorRect:
	var result := ColorRect.new()
	result.position = rect.position
	result.size = rect.size
	result.color = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result
