extends RefCounted
class_name BodyPartShopLayout

const SCREEN_SIZE := Vector2(1340.0, 510.0)
const HEADER_RECT := Rect2(0.0, 0.0, 1340.0, 88.0)
const CATEGORY_RECT := Rect2(24.0, 108.0, 250.0, 374.0)
const PRODUCT_RECT := Rect2(298.0, 108.0, 1018.0, 250.0)
const DETAIL_RECT := Rect2(298.0, 374.0, 632.0, 108.0)
const PURCHASE_RECT := Rect2(946.0, 374.0, 370.0, 108.0)
const CATEGORY_GAP := 10.0
const PRODUCT_GAP := 12.0
const PRODUCT_COLUMNS := 2

#######################################################
# Defines the shared flat menu geometry used to render and hit-test the body-parts ordering
# terminal.
#######################################################


static func get_category_rect(index: int, count: int) -> Rect2:
	if index < 0 or index >= count or count <= 0:
		return Rect2()
	var height := (
		CATEGORY_RECT.size.y - CATEGORY_GAP * float(count - 1)
	) / float(count)
	return Rect2(
		CATEGORY_RECT.position
			+ Vector2(0.0, float(index) * (height + CATEGORY_GAP)),
		Vector2(CATEGORY_RECT.size.x, height)
	)


static func get_category_index_at(position: Vector2, count: int) -> int:
	for index: int in range(count):
		if get_category_rect(index, count).has_point(position):
			return index
	return -1


static func get_product_rect(index: int, count: int) -> Rect2:
	if index < 0 or index >= count or count <= 0:
		return Rect2()
	var rows := ceili(float(count) / float(PRODUCT_COLUMNS))
	var width := (
		PRODUCT_RECT.size.x
		- PRODUCT_GAP * float(PRODUCT_COLUMNS - 1)
	) / float(PRODUCT_COLUMNS)
	var height := (
		PRODUCT_RECT.size.y - PRODUCT_GAP * float(rows - 1)
	) / float(rows)
	var column := index % PRODUCT_COLUMNS
	var row := index / PRODUCT_COLUMNS
	return Rect2(
		PRODUCT_RECT.position + Vector2(
			float(column) * (width + PRODUCT_GAP),
			float(row) * (height + PRODUCT_GAP)
		),
		Vector2(width, height)
	)


static func get_product_index_at(position: Vector2, count: int) -> int:
	for index: int in range(count):
		if get_product_rect(index, count).has_point(position):
			return index
	return -1
