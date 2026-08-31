class_name WorldNatureLayout
extends RefCounted

const INDUSTRIAL_LAYOUT := preload(
	"res://scripts/world/industrial_acoustic_complex_layout.gd"
)

## Shared deterministic placement data keeps visual dressing and authoritative collision aligned.
## Low-poly foliage is visual-only; a sampled subset of trunks and all rocks use shared baked
## shapes. The forest grows denser away from the test core and around the garage pressure array.

const FOREST_MIN := Vector2(-105.0, -120.0)
const FOREST_MAX := Vector2(115.0, 115.0)
const FOREST_CELL_SIZE := 7.0
const FOREST_LAYER_OFFSET := FOREST_CELL_SIZE * 0.5
const ACOUSTIC_PROBE_CELL_SIZE := FOREST_CELL_SIZE * 2.0
const MIN_ACOUSTIC_TREE_COUNT := 2
const TEST_CORE := Vector2(8.0, 0.0)
const GARAGE_CENTER := Vector2(6.0, -48.0)
const DEV_WAREHOUSE_CENTER := Vector2(0.0, 92.0)
const DEV_WAREHOUSE_HALF_EXTENTS := Vector2(48.0, 5.0)
const DEV_WAREHOUSE_ACCESS_CENTER := Vector2(0.0, 73.0)
const DEV_WAREHOUSE_ACCESS_HALF_EXTENTS := Vector2(4.0, 14.0)

const FOLIAGE_ANCHORS := [
	Vector3(-24.0, 0.0, -18.0),
	Vector3(-25.0, 0.0, 2.0),
	Vector3(-24.0, 0.0, 23.0),
	Vector3(-24.0, 0.0, 45.0),
	Vector3(-17.0, 0.0, 64.0),
	Vector3(24.0, 0.0, -16.0),
	Vector3(26.0, 0.0, 5.0),
	Vector3(25.0, 0.0, 27.0),
	Vector3(24.0, 0.0, 50.0),
	Vector3(15.0, 0.0, 67.0),
	Vector3(-10.0, 0.0, -38.0),
	Vector3(22.0, 0.0, -36.0),
	Vector3(-9.0, 0.0, -55.0),
	Vector3(22.0, 0.0, -58.0),
	Vector3(6.0, 0.0, -64.0),
]

const FOLIAGE_OFFSETS := [
	Vector3(-2.4, 0.0, -1.2),
	Vector3(-0.7, 0.0, 1.6),
	Vector3(1.1, 0.0, -1.7),
	Vector3(2.5, 0.0, 0.7),
	Vector3(0.4, 0.0, 2.8),
	Vector3(-2.8, 0.0, 2.5),
]

static var _built := false
static var _visual_descriptors: Array[Dictionary] = []
static var _collision_descriptors: Array[Dictionary] = []
static var _acoustic_probe_descriptors: Array[Dictionary] = []


static func visual_descriptors() -> Array[Dictionary]:
	_ensure_built()
	return _visual_descriptors


static func collision_descriptors() -> Array[Dictionary]:
	_ensure_built()
	return _collision_descriptors


static func acoustic_probe_descriptors() -> Array[Dictionary]:
	_ensure_built()
	return _acoustic_probe_descriptors


static func forest_density_at(position: Vector2) -> float:
	var distance_from_core := position.distance_to(TEST_CORE)
	var general_density := clampf(
		0.12 + maxf(distance_from_core - 20.0, 0.0) / 85.0 * 0.78,
		0.12,
		0.9
	)
	var distance_from_garage := position.distance_to(GARAGE_CENTER)
	var garage_density := 0.0
	if distance_from_garage >= 11.0 and distance_from_garage <= 82.0:
		garage_density = clampf(
			0.52 + maxf(distance_from_garage - 14.0, 0.0) / 58.0 * 0.4,
			0.52,
			0.92
		)
	return maxf(general_density, garage_density)


static func _ensure_built() -> void:
	if _built:
		return
	_built = true
	var curated := _curated_collision_descriptors()
	_collision_descriptors.append_array(curated)
	_visual_descriptors.append_array(curated)
	_append_curated_foliage()
	_append_forest_layer(0, Vector2.ZERO)
	_append_forest_layer(1, Vector2.ONE * FOREST_LAYER_OFFSET)
	_build_acoustic_probe_descriptors()


static func _build_acoustic_probe_descriptors() -> void:
	# Derive a sparse field from the collision-bearing trees instead of maintaining a second,
	# hand-authored forest map. One probe represents each occupied 14 m cell with at least two
	# trunks. Rebuilding acoustics samples the real surrounding collision/material geometry once.
	var tree_count_by_cell: Dictionary[Vector2i, int] = {}
	for descriptor: Dictionary in _collision_descriptors:
		if descriptor.get("collision_kind", &"") != &"trunk":
			continue
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var cell := Vector2i(
			floori(position.x / ACOUSTIC_PROBE_CELL_SIZE),
			floori(position.z / ACOUSTIC_PROBE_CELL_SIZE)
		)
		tree_count_by_cell[cell] = tree_count_by_cell.get(cell, 0) + 1
	var cells: Array[Vector2i] = []
	cells.assign(tree_count_by_cell.keys())
	cells.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		return left.x < right.x or (left.x == right.x and left.y < right.y)
	)
	for cell: Vector2i in cells:
		var tree_count: int = tree_count_by_cell.get(cell, 0)
		if tree_count < MIN_ACOUSTIC_TREE_COUNT:
			continue
		var center_2d := Vector2(
			(float(cell.x) + 0.5) * ACOUSTIC_PROBE_CELL_SIZE,
			(float(cell.y) + 0.5) * ACOUSTIC_PROBE_CELL_SIZE
		)
		if _is_excluded(center_2d):
			continue
		_acoustic_probe_descriptors.append({
			"name": "ForestAcousticProbe_%d_%d" % [cell.x, cell.y],
			"probe_id": "forest_%d_%d" % [cell.x, cell.y],
			"position": Vector3(center_2d.x, 1.65, center_2d.y),
			"tree_count": tree_count,
		})


static func _append_curated_foliage() -> void:
	for anchor_index: int in range(FOLIAGE_ANCHORS.size()):
		var anchor: Vector3 = FOLIAGE_ANCHORS[anchor_index]
		for offset_index: int in range(FOLIAGE_OFFSETS.size()):
			var use_fern := (anchor_index + offset_index) % 3 == 0
			var scale_value := (
				0.85 + float((anchor_index * 5 + offset_index * 3) % 6) * 0.11
				if use_fern
				else 1.25 + float((anchor_index * 7 + offset_index) % 7) * 0.13
			)
			_visual_descriptors.append(_descriptor(
				"Fern_%02d_%02d" % [anchor_index, offset_index]
				if use_fern
				else "Grass_%02d_%02d" % [anchor_index, offset_index],
				&"fern" if use_fern else &"grass",
				anchor + FOLIAGE_OFFSETS[offset_index],
				float((anchor_index * 67 + offset_index * 43) % 360),
				Vector3.ONE * scale_value
			))


static func _append_forest_layer(layer: int, layer_offset: Vector2) -> void:
	var x_count := floori((FOREST_MAX.x - FOREST_MIN.x) / FOREST_CELL_SIZE) + 1
	var z_count := floori((FOREST_MAX.y - FOREST_MIN.y) / FOREST_CELL_SIZE) + 1
	for x_index: int in range(x_count):
		for z_index: int in range(z_count):
			var base := FOREST_MIN + layer_offset + Vector2(
				float(x_index) * FOREST_CELL_SIZE,
				float(z_index) * FOREST_CELL_SIZE
			)
			var position_2d := base + Vector2(
				(_noise_01(x_index, z_index, 101 + layer * 17) - 0.5) * 4.2,
				(_noise_01(x_index, z_index, 211 + layer * 29) - 0.5) * 4.2
			)
			if _is_excluded(position_2d):
				continue
			var density := forest_density_at(position_2d)
			var acceptance := (
				density
				if layer == 0
				else clampf((density - 0.52) * 1.45, 0.0, 0.58)
			)
			if _noise_01(x_index, z_index, 307 + layer * 43) > acceptance:
				continue
			_append_forest_tree(layer, x_index, z_index, position_2d, density)


static func _append_forest_tree(
	layer: int,
	x_index: int,
	z_index: int,
	position_2d: Vector2,
	density: float
) -> void:
	var tree_noise := _noise_01(x_index, z_index, 401 + layer * 61)
	var asset_id := &"pine" if tree_noise < 0.74 else &"broadleaf"
	var scale_value := (
		0.86
		+ _noise_01(x_index, z_index, 503 + layer * 71) * 0.38
		+ density * 0.08
	)
	var tree := _descriptor(
		"ForestTree_%d_%03d_%03d" % [layer, x_index, z_index],
		asset_id,
		Vector3(position_2d.x, 0.0, position_2d.y),
		_noise_01(x_index, z_index, 607 + layer * 83) * 360.0,
		Vector3.ONE * scale_value
	)
	_visual_descriptors.append(tree)
	var collision_chance := 0.28 + density * 0.24
	if _noise_01(x_index, z_index, 701 + layer * 97) < collision_chance:
		tree["collision_kind"] = &"trunk"
		_collision_descriptors.append(tree)

	var foliage_count := 1
	if density > 0.5 and _noise_01(x_index, z_index, 809 + layer * 101) < density:
		foliage_count += 1
	for foliage_index: int in range(foliage_count):
		var angle := _noise_01(
			x_index,
			z_index,
			907 + layer * 113 + foliage_index * 19
		) * TAU
		var radius := 1.2 + _noise_01(
			x_index,
			z_index,
			1009 + layer * 127 + foliage_index * 23
		) * 2.5
		var foliage_position := position_2d + Vector2(cos(angle), sin(angle)) * radius
		if _is_excluded(foliage_position):
			continue
		var use_fern := _noise_01(
			x_index,
			z_index,
			1103 + layer * 131 + foliage_index * 31
		) < 0.42
		_visual_descriptors.append(_descriptor(
			"ForestFoliage_%d_%03d_%03d_%d"
			% [layer, x_index, z_index, foliage_index],
			&"fern" if use_fern else &"grass",
			Vector3(foliage_position.x, 0.0, foliage_position.y),
			_noise_01(
				x_index,
				z_index,
				1201 + layer * 137 + foliage_index * 37
			) * 360.0,
			Vector3.ONE * (0.9 + density * 0.7)
		))

	if _noise_01(x_index, z_index, 1301 + layer * 149) < density * 0.025:
		var rock_position := position_2d + Vector2(
			_noise_01(x_index, z_index, 1409 + layer * 151) - 0.5,
			_noise_01(x_index, z_index, 1511 + layer * 157) - 0.5
		) * 5.0
		if not _is_excluded(rock_position):
			var rock := _rock(
				"ForestStone_%d_%03d_%03d" % [layer, x_index, z_index],
				Vector3(rock_position.x, 0.0, rock_position.y),
				_noise_01(x_index, z_index, 1601 + layer * 163) * 360.0,
				0.35 + _noise_01(x_index, z_index, 1709 + layer * 167) * 0.35
			)
			_visual_descriptors.append(rock)
			_collision_descriptors.append(rock)


static func _is_excluded(position: Vector2) -> bool:
	var large_bunker_world_center_3d: Vector3 = (
		INDUSTRIAL_LAYOUT.WORLD_POSITION
		+ INDUSTRIAL_LAYOUT.LARGE_BUNKER_CENTER
	)
	var large_bunker_world_center := Vector2(
		large_bunker_world_center_3d.x,
		large_bunker_world_center_3d.z
	)
	var large_bunker_east_x := (
		large_bunker_world_center.x
		+ INDUSTRIAL_LAYOUT.LARGE_BUNKER_WIDTH * 0.5
	)
	var large_bunker_access_yard_x := -20.0
	var large_bunker_access_center_x := (
		large_bunker_east_x + large_bunker_access_yard_x
	) * 0.5
	var large_bunker_access_half_width := (
		absf(large_bunker_east_x - large_bunker_access_yard_x) * 0.5 + 1.5
	)
	var valve_bunker_world_center_3d: Vector3 = (
		INDUSTRIAL_LAYOUT.WORLD_POSITION
		+ INDUSTRIAL_LAYOUT.VALVE_BUNKER_CENTER
	)
	var valve_bunker_world_center := Vector2(
		valve_bunker_world_center_3d.x,
		valve_bunker_world_center_3d.z
	)
	var valve_bunker_east_x := (
		valve_bunker_world_center.x
		+ INDUSTRIAL_LAYOUT.LARGE_BUNKER_WIDTH * 0.5
	)
	var valve_access_center_x := (valve_bunker_east_x + large_bunker_access_yard_x) * 0.5
	var valve_access_half_width := (
		absf(valve_bunker_east_x - large_bunker_access_yard_x) * 0.5 + 1.5
	)
	var parkour_world_center_3d: Vector3 = (
		INDUSTRIAL_LAYOUT.WORLD_POSITION
		+ INDUSTRIAL_LAYOUT.MOVEMENT_PARKOUR_LAYOUT.CENTER
	)
	var parkour_world_center := Vector2(
		parkour_world_center_3d.x,
		parkour_world_center_3d.z
	)
	# Central interaction yard and its connection to the PA bunker.
	return (
		_inside_rect(position, Vector2(2.0, -9.0), Vector2(22.0, 25.0))
		or _inside_rect(position, Vector2(6.0, -34.0), Vector2(5.0, 6.0))
		# Garage shell plus a south-facing walkable entrance corridor.
		or _inside_rect(position, GARAGE_CENTER, Vector2(13.0, 11.0))
		or _inside_rect(position, Vector2(3.8, -69.0), Vector2(4.0, 14.0))
		# Three long bunker runs.
		or _inside_rect(position, Vector2(11.0, 31.0), Vector2(5.0, 29.0))
		or _inside_rect(position, Vector2(28.0, 31.0), Vector2(6.0, 29.0))
		or _inside_rect(position, Vector2(47.0, 31.0), Vector2(7.0, 29.0))
		# The long dev shelf now faces south from the north perimeter, with a narrow approach rather
		# than bisecting the central test yard.
		or _inside_rect(
			position,
			DEV_WAREHOUSE_CENTER,
			DEV_WAREHOUSE_HALF_EXTENTS
		)
		or _inside_rect(
			position,
			DEV_WAREHOUSE_ACCESS_CENTER,
			DEV_WAREHOUSE_ACCESS_HALF_EXTENTS
		)
		# Large comparison bunker plus its east-facing access route to the central yard.
		or _inside_rect(
			position,
			large_bunker_world_center,
			Vector2(
				INDUSTRIAL_LAYOUT.LARGE_BUNKER_WIDTH * 0.5 + 2.5,
				INDUSTRIAL_LAYOUT.LARGE_BUNKER_DEPTH * 0.5 + 2.5
			)
		)
		or _inside_rect(
			position,
			Vector2(large_bunker_access_center_x, large_bunker_world_center.y),
			Vector2(large_bunker_access_half_width, 4.0)
		)
		# Same shell and furnishing, Valve's documented default-concrete coefficients.
		or _inside_rect(
			position,
			valve_bunker_world_center,
			Vector2(
				INDUSTRIAL_LAYOUT.LARGE_BUNKER_WIDTH * 0.5 + 2.5,
				INDUSTRIAL_LAYOUT.LARGE_BUNKER_DEPTH * 0.5 + 2.5
			)
		)
		or _inside_rect(
			position,
			Vector2(valve_access_center_x, valve_bunker_world_center.y),
			Vector2(valve_access_half_width, 4.0)
		)
		# Dedicated movement lab: keep every tread, landing deck, and run-up readable.
		or _inside_rect(
			position,
			parkour_world_center,
			INDUSTRIAL_LAYOUT.MOVEMENT_PARKOUR_LAYOUT.CLEAR_HALF_EXTENTS
		)
	)


static func _inside_rect(position: Vector2, center: Vector2, half_extents: Vector2) -> bool:
	var delta := (position - center).abs()
	return delta.x <= half_extents.x and delta.y <= half_extents.y


static func _noise_01(x: int, z: int, salt: int) -> float:
	var value := sin(
		float(x) * 12.9898
		+ float(z) * 78.233
		+ float(salt) * 37.719
	) * 43758.5453
	return value - floorf(value)


static func _curated_collision_descriptors() -> Array[Dictionary]:
	return [
		_tree(&"PineWestSouth", &"pine", Vector3(-25.0, 0.0, -24.0), 18.0, 1.02),
		_tree(&"PineWestYard", &"pine", Vector3(-29.0, 0.0, -7.0), 103.0, 0.94),
		_tree(&"PineWestHouse", &"pine", Vector3(-28.0, 0.0, 17.0), 211.0, 1.16),
		_tree(&"PineWestNorthMid", &"pine", Vector3(-29.0, 0.0, 33.0), 286.0, 1.08),
		_tree(&"PineWestTunnel", &"pine", Vector3(-25.0, 0.0, 53.0), 34.0, 1.22),
		_tree(&"PineNorthWest", &"pine", Vector3(-18.0, 0.0, 68.0), 147.0, 1.05),
		_tree(&"PineEastSouth", &"pine", Vector3(28.0, 0.0, -23.0), 321.0, 1.13),
		_tree(&"PineEastYard", &"pine", Vector3(31.0, 0.0, -4.0), 76.0, 0.98),
		_tree(&"PineEastHouse", &"pine", Vector3(30.0, 0.0, 15.0), 188.0, 1.19),
		_tree(&"PineEastNorthMid", &"pine", Vector3(31.0, 0.0, 35.0), 252.0, 1.04),
		_tree(&"PineEastTunnel", &"pine", Vector3(28.0, 0.0, 57.0), 12.0, 1.24),
		_tree(&"PineNorthEast", &"pine", Vector3(18.0, 0.0, 70.0), 132.0, 1.08),
		_tree(&"BroadleafWestSouth", &"broadleaf", Vector3(-21.0, 0.0, -12.0), 229.0, 1.13),
		_tree(&"BroadleafWestMid", &"broadleaf", Vector3(-24.0, 0.0, 3.0), 41.0, 0.96),
		_tree(&"BroadleafWestNorth", &"broadleaf", Vector3(-22.0, 0.0, 43.0), 168.0, 1.07),
		_tree(&"BroadleafEastSouth", &"broadleaf", Vector3(23.0, 0.0, -10.0), 305.0, 1.02),
		_tree(&"BroadleafEastMid", &"broadleaf", Vector3(25.0, 0.0, 25.0), 92.0, 1.18),
		_tree(&"BroadleafEastNorth", &"broadleaf", Vector3(23.0, 0.0, 47.0), 196.0, 0.93),
		_rock(&"StoneWestSouth", Vector3(-19.5, 0.0, -4.0), 23.0, 0.52),
		_rock(&"StoneWestMid", Vector3(-21.5, 0.0, 20.0), 117.0, 0.64),
		_rock(&"StoneWestNorth", Vector3(-19.0, 0.0, 57.0), 271.0, 0.48),
		_rock(&"StoneEastSouth", Vector3(20.0, 0.0, 1.0), 194.0, 0.46),
		_rock(&"StoneEastMid", Vector3(23.0, 0.0, 38.0), 309.0, 0.58),
		_rock(&"StoneEastNorth", Vector3(19.5, 0.0, 61.0), 68.0, 0.55),
		_rock(&"StoneNorthWest", Vector3(-7.5, 0.0, 66.0), 142.0, 0.42),
		_rock(&"StoneNorthEast", Vector3(8.0, 0.0, 69.0), 248.0, 0.61),
		_tree(&"PineGarageApproachWest", &"pine", Vector3(-12.0, 0.0, -37.0), 57.0, 1.08),
		_tree(&"BroadleafGarageApproachEast", &"broadleaf", Vector3(23.0, 0.0, -36.0), 214.0, 1.03),
		_tree(&"PineGarageWest", &"pine", Vector3(-8.5, 0.0, -49.0), 127.0, 1.17),
		_tree(&"BroadleafGarageSouthWest", &"broadleaf", Vector3(-6.5, 0.0, -61.0), 312.0, 0.96),
		_tree(&"PineGarageEast", &"pine", Vector3(22.5, 0.0, -49.5), 268.0, 1.22),
		_tree(&"PineGarageSouthEast", &"pine", Vector3(20.0, 0.0, -62.0), 31.0, 1.05),
		_tree(&"BroadleafGarageRear", &"broadleaf", Vector3(6.0, 0.0, -66.0), 176.0, 1.08),
		_rock(&"StoneGarageApproach", Vector3(17.0, 0.0, -38.0), 93.0, 0.66),
		_rock(&"StoneGarageWest", Vector3(-5.5, 0.0, -54.5), 238.0, 0.51),
		_rock(&"StoneGarageEast", Vector3(20.0, 0.0, -56.0), 17.0, 0.59),
		_rock(&"StoneGarageRear", Vector3(12.5, 0.0, -64.0), 154.0, 0.47),
	]


static func _tree(
	name: StringName,
	asset_id: StringName,
	position: Vector3,
	yaw_degrees: float,
	scale_value: float
) -> Dictionary:
	var result := _descriptor(
		name,
		asset_id,
		position,
		yaw_degrees,
		Vector3.ONE * scale_value
	)
	result["collision_kind"] = &"trunk"
	return result


static func _rock(
	name: StringName,
	position: Vector3,
	yaw_degrees: float,
	scale_value: float
) -> Dictionary:
	var result := _descriptor(
		name,
		&"stone",
		position + Vector3.UP * (0.22 * scale_value),
		yaw_degrees,
		Vector3.ONE * scale_value
	)
	result["collision_kind"] = &"rock"
	return result


static func descriptor_transform(descriptor: Dictionary) -> Transform3D:
	var basis := Basis.from_euler(descriptor.get("rotation", Vector3.ZERO))
	basis = basis.scaled(descriptor.get("scale", Vector3.ONE))
	return Transform3D(basis, descriptor.get("position", Vector3.ZERO))


static func _descriptor(
	name: StringName,
	asset_id: StringName,
	position: Vector3,
	yaw_degrees: float,
	scale_value: Vector3
) -> Dictionary:
	return {
		"name": name,
		"asset_id": asset_id,
		"position": position,
		"rotation": Vector3(0.0, deg_to_rad(yaw_degrees), 0.0),
		"scale": scale_value,
	}
