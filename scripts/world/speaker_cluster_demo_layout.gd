class_name SpeakerClusterDemoLayout
extends RefCounted

## The garage shell, solid props, and acoustic probes share this immutable layout. Speaker
## placement lives in the reusable emitter-rig scene and is inspected here only for diagnostics.

const SPEAKER_ARRAY := preload("res://scripts/audio/speaker_array_3d.gd")
const SPEAKER_EMITTER_RIG := preload(
	"res://scenes/shared/garage_speaker_array_emitters.tscn"
)
const SPEAKER_ARRAY_DEFINITION: SpeakerArrayDefinition = preload(
	"res://resources/world/garage_pressure_array.tres"
)

const WORLD_POSITION := Vector3(6.0, 0.0, -48.0)
static var CONTACT_ID: StringName = SPEAKER_ARRAY_DEFINITION.contact_id
static var DISPLAY_NAME: String = SPEAKER_ARRAY_DEFINITION.display_name
static var AUDIO_ID_BASE: int = SPEAKER_ARRAY_DEFINITION.audio_id_base
static var SHARED_PROGRAM_GROUP_ID: int = (
	SPEAKER_ARRAY_DEFINITION.shared_program_group_id()
)
const WIDTH := 18.0
const DEPTH := 14.0
const HEIGHT := 5.4
const WALL_THICKNESS := 0.28
const FLOOR_THICKNESS := 0.16
const DOOR_CENTER_X := -2.2
const DOOR_WIDTH := 5.4
const DOOR_HEIGHT := 3.75


static func structural_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	_add_box(boxes, &"GarageFloor", Vector3(0.0, FLOOR_THICKNESS * 0.5, 0.0), Vector3(WIDTH, FLOOR_THICKNESS, DEPTH), &"floor")
	_add_box(boxes, &"GarageRoof", Vector3(0.0, HEIGHT, 0.0), Vector3(WIDTH + WALL_THICKNESS, WALL_THICKNESS, DEPTH + WALL_THICKNESS), &"roof")
	_add_box(boxes, &"GarageLeftWall", Vector3(-WIDTH * 0.5, HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, HEIGHT, DEPTH), &"wall")
	_add_box(boxes, &"GarageRightWall", Vector3(WIDTH * 0.5, HEIGHT * 0.5, 0.0), Vector3(WALL_THICKNESS, HEIGHT, DEPTH), &"wall")
	_add_box(boxes, &"GarageBackWall", Vector3(0.0, HEIGHT * 0.5, DEPTH * 0.5), Vector3(WIDTH, HEIGHT, WALL_THICKNESS), &"wall")

	var left_edge := -WIDTH * 0.5
	var right_edge := WIDTH * 0.5
	var door_left := DOOR_CENTER_X - DOOR_WIDTH * 0.5
	var door_right := DOOR_CENTER_X + DOOR_WIDTH * 0.5
	_add_box(boxes, &"GarageFrontLeft", Vector3((left_edge + door_left) * 0.5, DOOR_HEIGHT * 0.5, -DEPTH * 0.5), Vector3(door_left - left_edge, DOOR_HEIGHT, WALL_THICKNESS), &"wall")
	_add_box(boxes, &"GarageFrontRight", Vector3((door_right + right_edge) * 0.5, DOOR_HEIGHT * 0.5, -DEPTH * 0.5), Vector3(right_edge - door_right, DOOR_HEIGHT, WALL_THICKNESS), &"wall")
	_add_box(boxes, &"GarageFrontHeader", Vector3(0.0, DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT) * 0.5, -DEPTH * 0.5), Vector3(WIDTH, HEIGHT - DOOR_HEIGHT, WALL_THICKNESS), &"wall")

	# A short service bay divider adds meaningful indoor shadowing without dividing the garage into
	# two sealed rooms. It is deliberately offset from every speaker and the main entrance.
	_add_box(boxes, &"ServiceBayDivider", Vector3(3.2, 1.15, 2.0), Vector3(0.18, 2.3, 4.6), &"divider", false)
	return boxes


static func speaker_descriptors() -> Array[Dictionary]:
	return SPEAKER_ARRAY.describe_emitter_rig(
		SPEAKER_EMITTER_RIG,
		SPEAKER_ARRAY_DEFINITION
	)


static func prop_descriptors() -> Array[Dictionary]:
	return [
		_prop(&"GarageGenerator", &"generator", Vector3(-5.2, FLOOR_THICKNESS, 3.5), Vector3(0.0, deg_to_rad(10.0), 0.0), Vector3(3.4, 1.8, 1.0), Vector3(0.0, 0.9, 0.0)),
		_prop(&"GarageMachinery", &"machinery", Vector3(5.7, FLOOR_THICKNESS, 4.75), Vector3(0.0, deg_to_rad(-24.0), 0.0), Vector3(1.14, 0.64, 0.68), Vector3(0.0, 0.32, 0.0)),
		_prop(&"GarageControlPanel", &"control_panel", Vector3(6.75, 1.0, -6.78), Vector3(0.0, PI, 0.0), Vector3(0.711, 1.188, 0.448), Vector3(0.0, 0.594, 0.0)),
		_prop(&"GarageFuseBox", &"fuse_box", Vector3(-8.72, 2.0, 2.25), Vector3(0.0, PI * 0.5, 0.0), Vector3(0.55, 0.95, 0.3), Vector3(0.0, -0.03, 0.15)),
		_prop(&"GarageCrateA", &"metal_crate", Vector3(-0.2, FLOOR_THICKNESS, 4.9), Vector3(0.0, deg_to_rad(13.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"GarageCrateB", &"metal_crate", Vector3(1.05, FLOOR_THICKNESS, 5.25), Vector3(0.0, deg_to_rad(-8.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"GaragePallet", &"wood_pallet", Vector3(5.75, FLOOR_THICKNESS, -3.2), Vector3(0.0, deg_to_rad(19.0), 0.0), Vector3(1.44, 0.2, 1.31), Vector3(0.0, 0.1, 0.0)),
		_prop(&"GarageBarrel", &"water_barrel", Vector3(5.75, FLOOR_THICKNESS + 0.2, -3.2), Vector3.ZERO, Vector3(0.73, 1.13, 0.73), Vector3(0.0, 0.565, 0.0)),
	]


static func acoustic_probe_descriptors() -> Array[Dictionary]:
	return [
		_probe(&"GarageProbeFrontLeft", &"garage_inside_front_left", Vector3(-5.7, 1.55, -3.8), 4.8, true),
		_probe(&"GarageProbeFrontRight", &"garage_inside_front_right", Vector3(4.2, 1.55, -3.7), 4.8, true),
		# The centre pair is routing-critical for sources entering through the doorway. Without it,
		# clear resident speakers masked a disconnected front/rear graph while exterior sound fell
		# back to transmission through the wall in the rear half of the bunker.
		_probe(&"GarageProbeMidLeft", &"garage_inside_mid_left", Vector3(-4.5, 1.55, 0.0), 4.8, true),
		_probe(&"GarageProbeMidRight", &"garage_inside_mid_right", Vector3(4.0, 1.55, 0.0), 4.8, true),
		_probe(&"GarageProbeCenter", &"garage_inside_center", Vector3(-0.4, 1.55, 0.0), 5.0, true),
		_probe(&"GarageProbeBackLeft", &"garage_inside_back_left", Vector3(-5.5, 1.55, 4.3), 4.8, true),
		_probe(&"GarageProbeBackRight", &"garage_inside_back_right", Vector3(5.5, 1.55, 4.4), 4.8, true),
		_probe(&"GarageProbeDivider", &"garage_inside_divider", Vector3(5.7, 1.55, 1.3), 4.0, true),
		# Doorways need samples on both sides: the aperture owns no room tail, while the recessed
		# probe carries the garage response. Their overlap produces a continuous portal transition.
		_probe(&"GarageProbeThreshold", &"garage_threshold", Vector3(DOOR_CENTER_X, 1.55, -7.15), 4.2, false),
		_probe(&"GarageProbeDoor", &"garage_door", Vector3(DOOR_CENTER_X, 1.55, -5.35), 4.8, true),
		# Coarse outdoor routing follows the whole shell. These samples describe shared exterior air,
		# so every source—not only the PA—can diffract continuously around any bunker corner.
		_probe(&"GarageProbeApron", &"garage_outside_apron", Vector3(DOOR_CENTER_X, 1.55, -10.0), 13.0, false),
		_probe(&"GarageProbeFrontLeftExterior", &"garage_outside_front_left", Vector3(-10.0, 1.55, -8.0), 13.0, false),
		_probe(&"GarageProbeFrontRightExterior", &"garage_outside_front_right", Vector3(10.0, 1.55, -8.0), 13.0, false),
		_probe(&"GarageProbeOutsideLeft", &"garage_outside_left", Vector3(-11.5, 1.55, -1.0), 13.0, false),
		_probe(&"GarageProbeOutsideRight", &"garage_outside_right", Vector3(11.5, 1.55, 1.0), 13.0, false),
		_probe(&"GarageProbeRearLeftExterior", &"garage_outside_rear_left", Vector3(-10.0, 1.55, 8.0), 13.0, false),
		_probe(&"GarageProbeRearCenterLeft", &"garage_outside_rear_center_left", Vector3(-4.0, 1.55, 10.0), 13.0, false),
		_probe(&"GarageProbeRearRightExterior", &"garage_outside_rear_right", Vector3(10.0, 1.55, 8.0), 13.0, false),
		_probe(&"GarageProbeOutsideRear", &"garage_outside_rear", Vector3(2.5, 1.55, 10.2), 13.0, false),
	]


static func emitter_id(index: int) -> int:
	return SPEAKER_ARRAY_DEFINITION.emitter_id(index)


static func speaker_source_local_position(descriptor: Dictionary) -> Vector3:
	return descriptor.get("source_position", Vector3.ZERO)


static func speaker_installation_gain_db(descriptor: Dictionary) -> float:
	return clampf(float(descriptor.get("installation_gain_db", 0.0)), -24.0, 12.0)


static func _probe(
	node_name: StringName,
	probe_id: StringName,
	position: Vector3,
	connect_radius: float,
	sample_reflections: bool
) -> Dictionary:
	return {
		"name": node_name,
		"probe_id": probe_id,
		"position": position,
		"auto_connect_radius": connect_radius,
		"sample_reflections": sample_reflections,
		# Reflected probes need overlapping support over the full cell they represent. A fixed
		# five-metre radius left a rear-centre hole between otherwise connected bunker probes.
		"environment_influence_radius": (
			maxf(connect_radius * 1.5, 5.0)
			if sample_reflections
			else 5.0
		),
	}


static func _add_box(
	result: Array[Dictionary],
	node_name: StringName,
	position: Vector3,
	size: Vector3,
	material_id: StringName,
	acoustic_boundary := true
) -> void:
	result.append({
		"name": node_name,
		"position": position,
		"size": size,
		"rotation": Vector3.ZERO,
		"material_id": material_id,
		"acoustic_boundary": acoustic_boundary,
	})


static func _prop(
	node_name: StringName,
	asset_id: StringName,
	position: Vector3,
	rotation: Vector3,
	collision_size: Vector3,
	collision_offset: Vector3,
	scale := Vector3.ONE
) -> Dictionary:
	return {
		"name": node_name,
		"asset_id": asset_id,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"collision_size": collision_size,
		"collision_offset": collision_offset,
	}
