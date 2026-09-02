class_name DevZooCatalog
extends RefCounted

const WORLD_POSITION := Vector3(-72.0, 0.02, 60.0)
# Twice the width and depth gives every definition four times the floor area.
const PEN_SIZE := Vector2(20.0, 20.0)
const PEN_GAP := 2.0
const CLEAR_MARGIN := Vector2(3.0, 3.0)
const FEATURED_DEFINITION_PATHS: Array[String] = [
	"res://resources/enemies/flute_runner.tres",
	"res://resources/enemies/voice_mimic.tres",
]

#######################################################
# Builds the discoverable dev zoo catalog consumed by development or gameplay interfaces.
#######################################################

static func build_layout() -> Dictionary:
	var definitions := _load_definitions()
	var pens: Array[Dictionary] = []
	var total_width := maxf(
		float(definitions.size()) * PEN_SIZE.x
		+ float(maxi(definitions.size() - 1, 0)) * PEN_GAP,
		PEN_SIZE.x
	)
	var left := -total_width * 0.5
	for index: int in range(definitions.size()):
		var definition: EnemyDefinition = definitions[index]
		var center_x := (
			left + PEN_SIZE.x * 0.5
			+ float(index) * (PEN_SIZE.x + PEN_GAP)
		)
		pens.append({
			"slot_index": index,
			"definition_path": definition.resource_path,
			"display_name": definition.display_name,
			"center": Vector3(center_x, 0.0, 0.0),
			"size": PEN_SIZE,
		})
	return {
		"pens": pens,
		"nature_props": _build_nature_props(pens),
		"total_width": total_width,
		"depth": PEN_SIZE.y,
	}


static func _load_definitions() -> Array[EnemyDefinition]:
	var result: Array[EnemyDefinition] = []
	for resource_path: String in FEATURED_DEFINITION_PATHS:
		var definition: Resource = load(resource_path)
		if definition is EnemyDefinition:
			result.append(definition as EnemyDefinition)
		else:
			push_error("Dev zoo cannot load featured enemy: %s" % resource_path)
	result.sort_custom(
		func(left: EnemyDefinition, right: EnemyDefinition) -> bool:
			return left.display_name.naturalnocasecmp_to(right.display_name) < 0
	)
	return result


static func clear_half_extents() -> Vector2:
	var count := maxi(FEATURED_DEFINITION_PATHS.size(), 1)
	return Vector2(
		(float(count) * PEN_SIZE.x + float(count - 1) * PEN_GAP) * 0.5,
		PEN_SIZE.y * 0.5
	) + CLEAR_MARGIN


static func descriptor_transform(descriptor: Dictionary) -> Transform3D:
	var basis := Basis.from_euler(descriptor.get("rotation", Vector3.ZERO))
	basis = basis.scaled(descriptor.get("scale", Vector3.ONE))
	return Transform3D(basis, descriptor.get("position", Vector3.ZERO))


static func _build_nature_props(pens: Array[Dictionary]) -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	for pen_index: int in range(pens.size()):
		var center: Vector3 = pens[pen_index]["center"]
		var mirrored := -1.0 if pen_index % 2 == 0 else 1.0
		props.append(_nature_prop(
			"Pen%dCanopy" % pen_index,
			&"pine" if pen_index % 2 == 0 else &"broadleaf",
			center + Vector3(-6.4 * mirrored, 0.0, 6.1),
			37.0 + float(pen_index) * 113.0,
			0.76,
			&"trunk"
		))
		props.append(_nature_prop(
			"Pen%dStoneA" % pen_index,
			&"stone",
			center + Vector3(6.0 * mirrored, 0.22, 5.2),
			91.0 + float(pen_index) * 71.0,
			0.62,
			&"rock"
		))
		props.append(_nature_prop(
			"Pen%dStoneB" % pen_index,
			&"stone",
			center + Vector3(-6.7 * mirrored, 0.13, -4.8),
			214.0 + float(pen_index) * 53.0,
			0.38,
			&"rock"
		))
		var foliage_offsets: Array[Vector3] = [
			Vector3(-7.5, 0.0, 3.0),
			Vector3(-5.1, 0.0, 7.2),
			Vector3(-2.8, 0.0, 7.8),
			Vector3(2.6, 0.0, 7.4),
			Vector3(6.8, 0.0, 2.8),
			Vector3(7.3, 0.0, -3.1),
		]
		for foliage_index: int in range(foliage_offsets.size()):
			var offset := foliage_offsets[foliage_index]
			offset.x *= mirrored
			props.append(_nature_prop(
				"Pen%dFoliage%d" % [pen_index, foliage_index],
				&"fern" if (foliage_index + pen_index) % 2 == 0 else &"grass",
				center + offset,
				float((pen_index * 83 + foliage_index * 59) % 360),
				0.9 + float((pen_index + foliage_index) % 4) * 0.12
			))
	return props


static func _nature_prop(
	node_name: String,
	asset_id: StringName,
	position: Vector3,
	yaw_degrees: float,
	scale_value: float,
	collision_kind: StringName = &""
) -> Dictionary:
	return {
		"name": node_name,
		"asset_id": asset_id,
		"position": position,
		"rotation": Vector3(0.0, deg_to_rad(yaw_degrees), 0.0),
		"scale": Vector3.ONE * scale_value,
		"collision_kind": collision_kind,
	}
