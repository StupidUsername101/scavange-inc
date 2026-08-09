extends RefCounted

## Shared layout contract for the scanner's recursive terminal view.
##
## The renderer and the authoritative station both use these rectangles. This
## keeps a world-space click aligned with the child box shown on the terminal
## without coupling the server to Control nodes.

const SCREEN_SIZE := Vector2(1340.0, 510.0)
const BACK_RECT := Rect2(24.0, 16.0, 156.0, 52.0)
const SUMMARY_RECT := Rect2(24.0, 82.0, 1292.0, 112.0)
const CHILD_AREA := Rect2(24.0, 218.0, 1292.0, 268.0)
const CHILD_GAP := 14.0
const ACTION_RECT := Rect2(24.0, 400.0, 1292.0, 86.0)

#######################################################
# Lays out recursive terminal documents as zoomable boxes and resolves pointer selection
# through the hierarchy.
#######################################################

static func get_column_count(child_count: int) -> int:
	if child_count <= 1:
		return 1
	if child_count >= 5:
		return 3
	return 2


static func get_child_rect(index: int, child_count: int) -> Rect2:
	if index < 0 or index >= child_count:
		return Rect2()

	var columns: int = get_column_count(child_count)
	var rows: int = ceili(float(child_count) / float(columns))
	var cell_width: float = (
		CHILD_AREA.size.x - CHILD_GAP * float(columns - 1)
	) / float(columns)
	var cell_height: float = (
		CHILD_AREA.size.y - CHILD_GAP * float(rows - 1)
	) / float(rows)
	var column: int = index % columns
	var row: int = floori(float(index) / float(columns))

	return Rect2(
		CHILD_AREA.position + Vector2(
			float(column) * (cell_width + CHILD_GAP),
			float(row) * (cell_height + CHILD_GAP)
		),
		Vector2(cell_width, cell_height)
	)


static func get_child_index_at(
	screen_position: Vector2,
	child_count: int
) -> int:
	for index: int in range(child_count):
		if get_child_rect(index, child_count).has_point(screen_position):
			return index
	return -1


static func is_back_position(screen_position: Vector2) -> bool:
	return BACK_RECT.has_point(screen_position)
