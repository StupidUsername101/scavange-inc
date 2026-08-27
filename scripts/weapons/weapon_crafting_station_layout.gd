class_name WeaponCraftingStationLayout
extends RefCounted

const SCREEN_SIZE := Vector2(1340.0, 760.0)
const HEADER_RECT := Rect2(0.0, 0.0, 1340.0, 82.0)
const LANE_START_Y := 92.0
const LANE_HEIGHT := 68.0
const LANE_GAP := 8.0
const LANE_LABEL_X := 24.0
const LANE_LABEL_WIDTH := 158.0
const PREVIOUS_X := 196.0
const OPTION_WIDTH := 360.0
const OPTION_GAP := 10.0
const FOOTER_RECT := Rect2(20.0, 558.0, 1300.0, 182.0)
const CRAFT_RECT := Rect2(1018.0, 652.0, 282.0, 68.0)


static func get_lane_rect(index: int) -> Rect2:
	return Rect2(
		20.0,
		LANE_START_Y + float(index) * (LANE_HEIGHT + LANE_GAP),
		1300.0,
		LANE_HEIGHT
	)


static func get_previous_rect(index: int) -> Rect2:
	return Rect2(
		PREVIOUS_X,
		get_lane_rect(index).position.y,
		OPTION_WIDTH,
		LANE_HEIGHT
	)


static func get_selected_rect(index: int) -> Rect2:
	return Rect2(
		PREVIOUS_X + OPTION_WIDTH + OPTION_GAP,
		get_lane_rect(index).position.y,
		OPTION_WIDTH,
		LANE_HEIGHT
	)


static func get_next_rect(index: int) -> Rect2:
	return Rect2(
		PREVIOUS_X + (OPTION_WIDTH + OPTION_GAP) * 2.0,
		get_lane_rect(index).position.y,
		OPTION_WIDTH,
		LANE_HEIGHT
	)


static func get_lane_cycle_action(
	point: Vector2,
	lane_count: int
) -> Dictionary:
	for lane_index: int in range(maxi(lane_count, 0)):
		if get_previous_rect(lane_index).has_point(point):
			return {"lane_index": lane_index, "direction": -1}
		if get_next_rect(lane_index).has_point(point):
			return {"lane_index": lane_index, "direction": 1}
		# The bright middle cube acts like a physical reel button as well.
		if get_selected_rect(lane_index).has_point(point):
			return {"lane_index": lane_index, "direction": 1}
	return {}
