class_name MovementParkourLayout
extends RefCounted

## Shared, deterministic movement-course geometry. Authoritative movement uses three smooth hidden
## ramps; client foot placement sees the matching individual tread tops. The remaining platforms
## and height course are ordinary shared boxes, so collision and presentation cannot drift apart.

const CENTER := Vector3(55.0, 0.0, -30.0)
const CLEAR_HALF_EXTENTS := Vector2(16.5, 12.0)
const STAIR_RAMP_THICKNESS := 0.18
const STAIR_TREAD_OVERLAP := 0.012
const PLATFORM_THICKNESS := 0.24

const PRECISION_STAIR_WIDTH := 3.0
const PRECISION_STAIR_RUN := 6.0
const PRECISION_STAIR_HEIGHT := 2.1
const PRECISION_STAIR_COUNT := 14
const PRECISION_PLATFORM_LENGTH := 3.0

const MIRROR_STAIR_WIDTH := 3.4
const MIRROR_STAIR_RUN := 6.0
const MIRROR_STAIR_HEIGHT := 2.4
const MIRROR_STAIR_COUNT := 12
const MIRROR_GAP := 9.0
const MIRROR_PLATFORM_LENGTH := 3.0
const MIRROR_Z_OFFSET := 6.5
const JUMP_EDGE_MARKER_SIZE := 0.085

const BOX_HEIGHTS := [
	0.12,
	0.26,
	0.48,
	0.74,
	1.02,
	0.81,
	0.57,
	0.35,
	0.18,
	1.35,
	1.65,
]
const BOX_OFFSETS := [
	Vector2(-3.0, -8.0),
	Vector2(-0.5, -8.0),
	Vector2(2.0, -8.0),
	Vector2(4.5, -8.0),
	Vector2(7.0, -8.0),
	Vector2(7.0, -5.5),
	Vector2(4.5, -5.5),
	Vector2(2.0, -5.5),
	Vector2(-0.5, -5.5),
	Vector2(10.0, -8.0),
	Vector2(10.0, -5.5),
]
const BOX_SIZE := Vector2(2.05, 2.05)

static var _built := false
static var _structural_boxes: Array[Dictionary] = []
static var _contact_detail_boxes: Array[Dictionary] = []


static func structural_boxes() -> Array[Dictionary]:
	_ensure_built()
	return _structural_boxes


static func contact_detail_boxes() -> Array[Dictionary]:
	_ensure_built()
	return _contact_detail_boxes


static func mirror_platform_top_y() -> float:
	var angle := atan2(MIRROR_STAIR_HEIGHT, MIRROR_STAIR_RUN)
	return MIRROR_STAIR_HEIGHT + cos(angle) * STAIR_RAMP_THICKNESS * 0.5


static func mirror_jump_start_position(player_half_width := 0.5) -> Vector3:
	return CENTER + Vector3(
		-MIRROR_GAP * 0.5 - maxf(player_half_width, 0.0),
		mirror_platform_top_y(),
		MIRROR_Z_OFFSET
	)


static func mirror_landing_center_bounds(player_half_width := 0.5) -> Vector2:
	var inset := maxf(player_half_width, 0.0)
	return Vector2(
		CENTER.x + MIRROR_GAP * 0.5 + inset,
		CENTER.x + MIRROR_GAP * 0.5 + MIRROR_PLATFORM_LENGTH - inset
	)


static func jump_edge_markers() -> Array[Dictionary]:
	var top_y := mirror_platform_top_y() + 0.018
	return [
		{
			"name": &"ParkourJumpEdgeLeft",
			"position": CENTER + Vector3(
				-MIRROR_GAP * 0.5,
				top_y,
				MIRROR_Z_OFFSET
			),
			"size": Vector3(
				JUMP_EDGE_MARKER_SIZE,
				0.028,
				MIRROR_STAIR_WIDTH - 0.18
			),
		},
		{
			"name": &"ParkourJumpEdgeRight",
			"position": CENTER + Vector3(
				MIRROR_GAP * 0.5,
				top_y,
				MIRROR_Z_OFFSET
			),
			"size": Vector3(
				JUMP_EDGE_MARKER_SIZE,
				0.028,
				MIRROR_STAIR_WIDTH - 0.18
			),
		},
	]


static func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_append_height_course()
	_append_precision_stair()
	_append_mirrored_jump_stairs()


static func _append_height_course() -> void:
	for box_index: int in range(BOX_HEIGHTS.size()):
		var height: float = BOX_HEIGHTS[box_index]
		var offset: Vector2 = BOX_OFFSETS[box_index]
		_append_box(
			_structural_boxes,
			StringName("ParkourHeightBox%02d" % (box_index + 1)),
			CENTER + Vector3(offset.x, height * 0.5, offset.y),
			Vector3(BOX_SIZE.x, height, BOX_SIZE.y),
			Vector3.ZERO,
			&"parkour",
			true
		)


static func _append_precision_stair() -> void:
	var low_end := CENTER + Vector3(-9.0, 0.0, -8.0)
	var top_y := _append_staircase(
		&"ParkourPrecision",
		low_end,
		Vector3.BACK,
		PRECISION_STAIR_WIDTH,
		PRECISION_STAIR_RUN,
		PRECISION_STAIR_HEIGHT,
		PRECISION_STAIR_COUNT
	)
	var high_end := low_end + Vector3.BACK * PRECISION_STAIR_RUN
	_append_box(
		_structural_boxes,
		&"ParkourPrecisionTopDeck",
		high_end
		+ Vector3.BACK * (PRECISION_PLATFORM_LENGTH * 0.5)
		+ Vector3.UP * (top_y - PLATFORM_THICKNESS * 0.5),
		Vector3(
			PRECISION_STAIR_WIDTH,
			PLATFORM_THICKNESS,
			PRECISION_PLATFORM_LENGTH
		),
		Vector3.ZERO,
		&"parkour",
		true
	)


static func _append_mirrored_jump_stairs() -> void:
	var platform_top_y := mirror_platform_top_y()
	var high_abs_x := MIRROR_GAP * 0.5 + MIRROR_PLATFORM_LENGTH
	var low_abs_x := high_abs_x + MIRROR_STAIR_RUN
	var left_low_end := CENTER + Vector3(-low_abs_x, 0.0, MIRROR_Z_OFFSET)
	var right_low_end := CENTER + Vector3(low_abs_x, 0.0, MIRROR_Z_OFFSET)
	_append_staircase(
		&"ParkourMirrorLeft",
		left_low_end,
		Vector3.RIGHT,
		MIRROR_STAIR_WIDTH,
		MIRROR_STAIR_RUN,
		MIRROR_STAIR_HEIGHT,
		MIRROR_STAIR_COUNT
	)
	_append_staircase(
		&"ParkourMirrorRight",
		right_low_end,
		Vector3.LEFT,
		MIRROR_STAIR_WIDTH,
		MIRROR_STAIR_RUN,
		MIRROR_STAIR_HEIGHT,
		MIRROR_STAIR_COUNT
	)
	for side: int in [-1, 1]:
		var platform_center_x := float(side) * (
			MIRROR_GAP * 0.5 + MIRROR_PLATFORM_LENGTH * 0.5
		)
		_append_box(
			_structural_boxes,
			StringName(
				"ParkourMirror%sTakeoffDeck" % (
					"Left" if side < 0 else "Right"
				)
			),
			CENTER + Vector3(
				platform_center_x,
				platform_top_y - PLATFORM_THICKNESS * 0.5,
				MIRROR_Z_OFFSET
			),
			Vector3(
				MIRROR_PLATFORM_LENGTH,
				PLATFORM_THICKNESS,
				MIRROR_STAIR_WIDTH
			),
			Vector3.ZERO,
			&"parkour",
			true
		)


static func _append_staircase(
	prefix: StringName,
	low_end: Vector3,
	travel_axis: Vector3,
	width: float,
	run: float,
	height: float,
	tread_count: int
) -> float:
	var axis := travel_axis.normalized()
	var ramp_angle := atan2(height, run)
	var ramp_length := sqrt(run * run + height * height)
	var ramp_size := (
		Vector3(ramp_length, STAIR_RAMP_THICKNESS, width)
		if absf(axis.x) > 0.5
		else Vector3(width, STAIR_RAMP_THICKNESS, ramp_length)
	)
	var ramp_rotation := Vector3(
		-axis.z * ramp_angle,
		0.0,
		axis.x * ramp_angle
	)
	_append_box(
		_structural_boxes,
		StringName("%sRamp" % prefix),
		low_end + axis * (run * 0.5) + Vector3.UP * (height * 0.5),
		ramp_size,
		ramp_rotation,
		&"ramp",
		false
	)
	var tread_run := run / float(tread_count)
	var tread_rise := height / float(tread_count)
	var surface_offset := cos(ramp_angle) * STAIR_RAMP_THICKNESS * 0.5
	for tread_index: int in range(tread_count):
		var top_y := surface_offset + float(tread_index + 1) * tread_rise
		var tread_height := tread_rise + STAIR_TREAD_OVERLAP
		var tread_size := (
			Vector3(
				tread_run + STAIR_TREAD_OVERLAP,
				tread_height,
				width - 0.18
			)
			if absf(axis.x) > 0.5
			else Vector3(
				width - 0.18,
				tread_height,
				tread_run + STAIR_TREAD_OVERLAP
			)
		)
		_append_box(
			_contact_detail_boxes,
			StringName("%sTread%02d" % [prefix, tread_index + 1]),
			low_end
			+ axis * ((float(tread_index) + 0.5) * tread_run)
			+ Vector3.UP * (top_y - tread_height * 0.5),
			tread_size,
			Vector3.ZERO,
			&"ramp",
			true
		)
	return height + surface_offset


static func _append_box(
	boxes: Array[Dictionary],
	node_name: StringName,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
	material_id: StringName,
	visual: bool
) -> void:
	boxes.append({
		"name": node_name,
		"position": position,
		"size": size,
		"rotation": rotation,
		"material_id": material_id,
		"visual": visual,
		"acoustic_boundary": false,
	})
