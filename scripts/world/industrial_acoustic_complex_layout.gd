class_name IndustrialAcousticComplexLayout
extends RefCounted

const MODULAR_STRUCTURE_ASSEMBLER := preload(
	"res://scripts/world/modular_structure_assembler.gd"
)
const TUNNEL_DEFINITION: ModularStructureDefinition = preload(
	"res://resources/world/structures/bunker_straight_tunnel.tres"
)
const WIDE_TUNNEL_DEFINITION: ModularStructureDefinition = preload(
	"res://resources/world/structures/bunker_wide_tunnel.tres"
)
const HANGAR_TUNNEL_DEFINITION: ModularStructureDefinition = preload(
	"res://resources/world/structures/bunker_hangar_tunnel.tres"
)
const SPEAKER_ARRAY := preload("res://scripts/audio/speaker_array_3d.gd")
const LARGE_BUNKER_EMITTER_RIG := preload(
	"res://scenes/shared/large_bunker_speaker_array_emitters.tscn"
)
const LARGE_BUNKER_ARRAY_DEFINITION: SpeakerArrayDefinition = preload(
	"res://resources/world/large_bunker_pressure_array.tres"
)
const VALVE_BUNKER_ARRAY_DEFINITION: SpeakerArrayDefinition = preload(
	"res://resources/world/valve_reference_bunker_array.tres"
)
const VALVE_REFERENCE_CONCRETE: AcousticMaterial = preload(
	"res://resources/world/acoustic_materials/valve_reference_concrete.tres"
)
const MOVEMENT_PARKOUR_LAYOUT := preload(
	"res://scripts/world/movement_parkour_layout.gd"
)

const TUNNEL_CENTER := Vector3(11.0, 0.0, 12.0)
const WIDE_TUNNEL_CENTER := Vector3(28.0, 0.0, 12.0)
const HANGAR_TUNNEL_CENTER := Vector3(47.0, 0.0, 12.0)
const TUNNEL_FLOOR_Y := 0.01
const TUNNEL_PROBE_SPACING := 4.0
const TUNNEL_PROBE_PORTAL_INSET := 4.0
const TUNNEL_EXTERIOR_PROBE_CLEARANCE := 1.1
const TUNNEL_EXTERIOR_PROBE_CONNECT_RADIUS := 12.0
const TUNNEL_RUN_COUNT := 3

# A deliberately large, mostly open comparison room. Its east-facing entrance connects back to
# the test yard. Unlike the garage PA bunker, this room keeps ordinary geometry-sampled response.
const WORLD_POSITION := Vector3(0.0, 0.0, 19.0)
const LARGE_BUNKER_CENTER := Vector3(-55.0, 0.0, -10.0)
const VALVE_BUNKER_CENTER := Vector3(-55.0, 0.0, -58.0)
const LARGE_BUNKER_WIDTH := 40.0
const LARGE_BUNKER_DEPTH := 32.0
const LARGE_BUNKER_HEIGHT := 10.0
const LARGE_BUNKER_WALL_THICKNESS := 0.48
const LARGE_BUNKER_FLOOR_THICKNESS := 0.2
const LARGE_BUNKER_DOOR_WIDTH := 7.0
const LARGE_BUNKER_DOOR_HEIGHT := 5.5
const LARGE_BUNKER_PROBE_HEIGHT := 1.7
const LARGE_BUNKER_PROBE_SPACING := 6.4
static var LARGE_BUNKER_CONTACT_ID: StringName = (
	LARGE_BUNKER_ARRAY_DEFINITION.contact_id
)
static var LARGE_BUNKER_DISPLAY_NAME: String = (
	LARGE_BUNKER_ARRAY_DEFINITION.display_name
)
static var LARGE_BUNKER_AUDIO_ID_BASE: int = (
	LARGE_BUNKER_ARRAY_DEFINITION.audio_id_base
)
static var LARGE_BUNKER_SHARED_PROGRAM_GROUP_ID: int = (
	LARGE_BUNKER_ARRAY_DEFINITION.shared_program_group_id()
)
static var VALVE_BUNKER_CONTACT_ID: StringName = (
	VALVE_BUNKER_ARRAY_DEFINITION.contact_id
)

## Compatibility accessors for acoustic layout/tests. Their values come from the baked asset
## definition rather than copied measurements in this script.
static var TUNNEL_MODULE_LENGTH: float = TUNNEL_DEFINITION.module_size().z
static var TUNNEL_MODULE_COUNT: int = TUNNEL_DEFINITION.module_count
static var TUNNEL_WIDTH: float = TUNNEL_DEFINITION.module_size().x
static var TUNNEL_HEIGHT: float = TUNNEL_DEFINITION.module_size().y
static var TUNNEL_LENGTH: float = TUNNEL_DEFINITION.total_length()
static var TUNNEL_RUNS: Array[Dictionary] = [
	{
		"run_id": &"comfort",
		"definition": TUNNEL_DEFINITION,
		"center": TUNNEL_CENTER,
		"floor_y": TUNNEL_FLOOR_Y,
		"container_name": &"BunkerTunnelModules",
		"label": "COMFORT",
	},
	{
		"run_id": &"wide",
		"definition": WIDE_TUNNEL_DEFINITION,
		"center": WIDE_TUNNEL_CENTER,
		"floor_y": TUNNEL_FLOOR_Y,
		"container_name": &"BunkerWideTunnelModules",
		"label": "WIDE",
	},
	{
		"run_id": &"hangar",
		"definition": HANGAR_TUNNEL_DEFINITION,
		"center": HANGAR_TUNNEL_CENTER,
		"floor_y": TUNNEL_FLOOR_Y,
		"container_name": &"BunkerHangarTunnelModules",
		"label": "HANGAR",
	},
]


static func structural_boxes() -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	_append_tunnel(boxes)
	_append_large_bunker(boxes)
	_append_bunker_shell(
		boxes,
		VALVE_BUNKER_CENTER,
		"ValveBunker",
		&"valve_concrete",
		VALVE_REFERENCE_CONCRETE
	)
	boxes.append_array(MOVEMENT_PARKOUR_LAYOUT.structural_boxes())
	return boxes


## Presentation contact uses the authoritative shells plus the dedicated movement-course detail.
static func foot_contact_boxes() -> Array[Dictionary]:
	var boxes := structural_boxes()
	boxes.append_array(MOVEMENT_PARKOUR_LAYOUT.contact_detail_boxes())
	return boxes


static func parkour_contact_detail_boxes() -> Array[Dictionary]:
	return MOVEMENT_PARKOUR_LAYOUT.contact_detail_boxes()


static func tunnel_runs() -> Array[Dictionary]:
	return TUNNEL_RUNS


static func tunnel_module_descriptors(run_index := 0) -> Array[Dictionary]:
	var run := _tunnel_run(run_index)
	if run.is_empty():
		return []
	return MODULAR_STRUCTURE_ASSEMBLER.linear_module_descriptors(
		run.get("definition") as ModularStructureDefinition,
		run.get("center", Vector3.ZERO),
		float(run.get("floor_y", 0.0))
	)


static func tunnel_structural_boxes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for run_index: int in range(TUNNEL_RUN_COUNT):
		result.append_array(tunnel_run_structural_boxes(run_index))
	return result


static func tunnel_run_structural_boxes(run_index: int) -> Array[Dictionary]:
	var run := _tunnel_run(run_index)
	if run.is_empty():
		return []
	return MODULAR_STRUCTURE_ASSEMBLER.collision_descriptors(
		run.get("definition") as ModularStructureDefinition,
		run.get("center", Vector3.ZERO),
		float(run.get("floor_y", 0.0))
	)


static func prop_descriptors() -> Array[Dictionary]:
	# These transforms are shared by the visual and authoritative worlds. Collision uses a cheap
	# authored box per prop instead of generating trimeshes from imported art at runtime.
	var tunnel_floor_y := TUNNEL_FLOOR_Y
	var result: Array[Dictionary] = [
		_prop(&"TunnelCrateSouth", &"metal_crate", Vector3(9.75, tunnel_floor_y, -5.0), Vector3(0.0, deg_to_rad(12.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"TunnelPallet", &"wood_pallet", Vector3(12.0, tunnel_floor_y, 1.5), Vector3(0.0, deg_to_rad(-8.0), 0.0), Vector3(1.44, 0.2, 1.31), Vector3(0.0, 0.1, 0.0)),
		_prop(&"TunnelBarrelOnPallet", &"water_barrel", Vector3(12.0, tunnel_floor_y + 0.2, 1.5), Vector3.ZERO, Vector3(0.73, 1.13, 0.73), Vector3(0.0, 0.565, 0.0)),
		_prop(&"TunnelMachinery", &"machinery", Vector3(9.85, tunnel_floor_y, 17.5), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.14, 0.64, 0.68), Vector3(0.0, 0.32, 0.0)),
		_prop(&"TunnelControlPanel", &"control_panel", Vector3(12.45, tunnel_floor_y, 12.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(0.711, 1.188, 0.448), Vector3(0.0, 0.594, 0.0)),
		_prop(&"TunnelCrateNorth", &"metal_crate", Vector3(12.2, tunnel_floor_y, 29.0), Vector3(0.0, deg_to_rad(-17.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"WideTunnelGenerator", &"generator", Vector3(25.9, tunnel_floor_y, 0.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(3.4, 1.8, 1.0), Vector3(0.0, 0.9, 0.0)),
		_prop(&"WideTunnelTerminal", &"computer_terminal", Vector3(30.45, tunnel_floor_y, -5.0), Vector3(0.0, deg_to_rad(-90.0), 0.0), Vector3(0.918, 0.684, 0.468), Vector3(0.0, 0.342, 0.0)),
		_prop(&"WideTunnelCrateBase", &"metal_crate", Vector3(29.75, tunnel_floor_y, 8.0), Vector3(0.0, deg_to_rad(-11.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"WideTunnelCrateTop", &"metal_crate", Vector3(29.75, tunnel_floor_y + 1.12, 8.0), Vector3(0.0, deg_to_rad(7.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"WideTunnelPallet", &"wood_pallet", Vector3(26.0, tunnel_floor_y, 17.0), Vector3(0.0, deg_to_rad(8.0), 0.0), Vector3(1.44, 0.2, 1.31), Vector3(0.0, 0.1, 0.0)),
		_prop(&"WideTunnelBarrel", &"water_barrel", Vector3(26.0, tunnel_floor_y + 0.2, 17.0), Vector3.ZERO, Vector3(0.73, 1.13, 0.73), Vector3(0.0, 0.565, 0.0)),
		_prop(&"WideTunnelMachinery", &"machinery", Vector3(30.15, tunnel_floor_y, 27.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.14, 0.64, 0.68), Vector3(0.0, 0.32, 0.0)),
		_prop(&"WideTunnelControlPanel", &"control_panel", Vector3(25.55, tunnel_floor_y, 31.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(0.711, 1.188, 0.448), Vector3(0.0, 0.594, 0.0)),
		_prop(&"HangarTunnelTerminal", &"computer_terminal", Vector3(50.0, tunnel_floor_y, -4.0), Vector3(0.0, deg_to_rad(-90.0), 0.0), Vector3(0.918, 0.684, 0.468), Vector3(0.0, 0.342, 0.0)),
		_prop(&"HangarTunnelGenerator", &"generator", Vector3(44.8, tunnel_floor_y, 3.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(3.4, 1.8, 1.0), Vector3(0.0, 0.9, 0.0)),
		_prop(&"HangarTunnelMachinery", &"machinery", Vector3(49.5, tunnel_floor_y, 9.0), Vector3(0.0, deg_to_rad(-90.0), 0.0), Vector3(1.14, 0.64, 0.68), Vector3(0.0, 0.32, 0.0)),
		_prop(&"HangarTunnelCrateBase", &"metal_crate", Vector3(44.6, tunnel_floor_y, 18.0), Vector3(0.0, deg_to_rad(13.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"HangarTunnelCrateTop", &"metal_crate", Vector3(44.6, tunnel_floor_y + 1.12, 18.0), Vector3(0.0, deg_to_rad(-4.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"HangarTunnelPallet", &"wood_pallet", Vector3(49.7, tunnel_floor_y, 24.0), Vector3(0.0, deg_to_rad(-9.0), 0.0), Vector3(1.44, 0.2, 1.31), Vector3(0.0, 0.1, 0.0)),
		_prop(&"HangarTunnelBarrel", &"water_barrel", Vector3(49.7, tunnel_floor_y + 0.2, 24.0), Vector3.ZERO, Vector3(0.73, 1.13, 0.73), Vector3(0.0, 0.565, 0.0)),
		_prop(&"HangarTunnelControlPanel", &"control_panel", Vector3(44.0, tunnel_floor_y, 30.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(0.711, 1.188, 0.448), Vector3(0.0, 0.594, 0.0)),
	]
	var hall_floor_y := LARGE_BUNKER_FLOOR_THICKNESS
	var bunker_props: Array[Dictionary] = [
		_prop(&"LargeBunkerGeneratorWest", &"generator", LARGE_BUNKER_CENTER + Vector3(-16.2, hall_floor_y, -12.7), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(3.4, 1.8, 1.0), Vector3(0.0, 0.9, 0.0)),
		_prop(&"LargeBunkerMachineryWest", &"machinery", LARGE_BUNKER_CENTER + Vector3(-17.2, hall_floor_y, -7.8), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.14, 0.64, 0.68), Vector3(0.0, 0.32, 0.0)),
		_prop(&"LargeBunkerTerminalNorth", &"computer_terminal", LARGE_BUNKER_CENTER + Vector3(-12.0, hall_floor_y, 14.4), Vector3.ZERO, Vector3(0.918, 0.684, 0.468), Vector3(0.0, 0.342, 0.0)),
		_prop(&"LargeBunkerControlNorth", &"control_panel", LARGE_BUNKER_CENTER + Vector3(-8.2, hall_floor_y, 14.35), Vector3.ZERO, Vector3(0.711, 1.188, 0.448), Vector3(0.0, 0.594, 0.0)),
		_prop(&"LargeBunkerCrateSouthA", &"metal_crate", LARGE_BUNKER_CENTER + Vector3(11.5, hall_floor_y, -13.7), Vector3(0.0, deg_to_rad(8.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"LargeBunkerCrateSouthB", &"metal_crate", LARGE_BUNKER_CENTER + Vector3(12.7, hall_floor_y, -13.4), Vector3(0.0, deg_to_rad(-5.0), 0.0), Vector3(1.12, 1.12, 1.12), Vector3(0.0, 0.56, 0.0)),
		_prop(&"LargeBunkerPalletEast", &"wood_pallet", LARGE_BUNKER_CENTER + Vector3(16.8, hall_floor_y, 9.6), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.44, 0.2, 1.31), Vector3(0.0, 0.1, 0.0)),
		_prop(&"LargeBunkerBarrelEast", &"water_barrel", LARGE_BUNKER_CENTER + Vector3(16.8, hall_floor_y + 0.2, 9.6), Vector3.ZERO, Vector3(0.73, 1.13, 0.73), Vector3(0.0, 0.565, 0.0)),
	]
	result.append_array(bunker_props)
	var valve_offset := VALVE_BUNKER_CENTER - LARGE_BUNKER_CENTER
	for source_descriptor: Dictionary in bunker_props:
		var copy := source_descriptor.duplicate(false)
		copy["name"] = StringName("Valve%s" % str(copy.get("name", "BunkerProp")))
		copy["position"] = (copy.get("position", Vector3.ZERO) as Vector3) + valve_offset
		result.append(copy)
	return result


static func large_bunker_probe_descriptors() -> Array[Dictionary]:
	return _bunker_probe_descriptors(
		LARGE_BUNKER_CENTER,
		"LargeBunker",
		"industrial_large_bunker"
	)


static func valve_bunker_probe_descriptors() -> Array[Dictionary]:
	return _bunker_probe_descriptors(
		VALVE_BUNKER_CENTER,
		"ValveBunker",
		"industrial_valve_bunker"
	)


static func _bunker_probe_descriptors(
	center: Vector3,
	node_prefix: String,
	probe_prefix: String
) -> Array[Dictionary]:
	# Two interleaved height layers keep the large air volume represented without a dense runtime
	# voxel field. All expensive reflection sampling happens when the server graph is rebuilt.
	var result: Array[Dictionary] = []
	var ground_x_offsets: Array[float] = [
		-2.5 * LARGE_BUNKER_PROBE_SPACING,
		-1.5 * LARGE_BUNKER_PROBE_SPACING,
		-0.5 * LARGE_BUNKER_PROBE_SPACING,
		0.5 * LARGE_BUNKER_PROBE_SPACING,
		1.5 * LARGE_BUNKER_PROBE_SPACING,
		2.5 * LARGE_BUNKER_PROBE_SPACING,
	]
	var ground_z_offsets: Array[float] = [
		-2.0 * LARGE_BUNKER_PROBE_SPACING,
		-LARGE_BUNKER_PROBE_SPACING,
		0.0,
		LARGE_BUNKER_PROBE_SPACING,
		2.0 * LARGE_BUNKER_PROBE_SPACING,
	]
	for x_index: int in range(ground_x_offsets.size()):
		for z_index: int in range(ground_z_offsets.size()):
			result.append(_large_bunker_probe_descriptor(
				"%sGroundProbe_%02d_%02d" % [node_prefix, x_index, z_index],
				"%s_ground_%02d_%02d" % [probe_prefix, x_index, z_index],
				center + Vector3(
					ground_x_offsets[x_index],
					LARGE_BUNKER_PROBE_HEIGHT,
					ground_z_offsets[z_index]
				)
			))
	var upper_x_offsets: Array[float] = [
		-2.25 * LARGE_BUNKER_PROBE_SPACING,
		-0.75 * LARGE_BUNKER_PROBE_SPACING,
		0.75 * LARGE_BUNKER_PROBE_SPACING,
		2.25 * LARGE_BUNKER_PROBE_SPACING,
	]
	var upper_z_offsets: Array[float] = [
		-1.5 * LARGE_BUNKER_PROBE_SPACING,
		0.0,
		1.5 * LARGE_BUNKER_PROBE_SPACING,
	]
	for x_index: int in range(upper_x_offsets.size()):
		for z_index: int in range(upper_z_offsets.size()):
			result.append(_large_bunker_probe_descriptor(
				"%sUpperProbe_%02d_%02d" % [node_prefix, x_index, z_index],
				"%s_upper_%02d_%02d" % [probe_prefix, x_index, z_index],
				center + Vector3(
					upper_x_offsets[x_index],
					6.0,
					upper_z_offsets[z_index]
				)
			))
	var half_width := LARGE_BUNKER_WIDTH * 0.5
	result.append({
		"name": "%sDoorInsideProbe" % node_prefix,
		"probe_id": "%s_door_inside" % probe_prefix,
		"role": &"door_inside",
		"position": center + Vector3(
			half_width - 1.8,
			LARGE_BUNKER_PROBE_HEIGHT,
			0.0
		),
		"auto_connect_radius": 8.0,
		"reflection_sample_distance": 60.0,
		"environment_influence_radius": 6.0,
		"reverb_scale": 1.0,
	})
	result.append({
		"name": "%sDoorOutsideProbe" % node_prefix,
		"probe_id": "%s_door_outside" % probe_prefix,
		"role": &"door_outside",
		"position": center + Vector3(
			half_width + 3.0,
			LARGE_BUNKER_PROBE_HEIGHT,
			0.0
		),
		"auto_connect_radius": 12.0,
		"sample_reflections": false,
		"environment_influence_radius": 7.0,
	})
	return result


static func large_bunker_speaker_descriptors() -> Array[Dictionary]:
	return SPEAKER_ARRAY.describe_emitter_rig(
		LARGE_BUNKER_EMITTER_RIG,
		LARGE_BUNKER_ARRAY_DEFINITION
	)


static func large_bunker_speaker_source_local_position(
	descriptor: Dictionary
) -> Vector3:
	return descriptor.get("source_position", Vector3.ZERO)


static func large_bunker_speaker_installation_gain_db(
	descriptor: Dictionary
) -> float:
	return clampf(float(descriptor.get("installation_gain_db", 0.0)), -24.0, 12.0)


static func _large_bunker_probe_descriptor(
	node_name: String,
	probe_id: String,
	position: Vector3
) -> Dictionary:
	return {
		"name": node_name,
		"probe_id": probe_id,
		"role": &"inside",
		"position": position,
		"auto_connect_radius": 9.0,
		"reflection_sample_distance": 60.0,
		"environment_influence_radius": 6.5,
		"reverb_scale": 1.0,
		# Ownership boxes stop a geometrically near indoor sample being selected through a wall.
		"attachment_influence_half_extents": Vector3(3.8, 4.2, 3.8),
		"attachment_influence_boundary_fade": 0.9,
	}


static func tunnel_probe_positions(run_index := 0) -> PackedVector3Array:
	var result := PackedVector3Array()
	var run := _tunnel_run(run_index)
	if run.is_empty():
		return result
	var definition := run.get("definition") as ModularStructureDefinition
	var center: Vector3 = run.get("center", Vector3.ZERO)
	var floor_y := float(run.get("floor_y", 0.0))
	var length := definition.total_length()
	var first_offset := -length * 0.5 + TUNNEL_PROBE_PORTAL_INSET
	var sampled_length := length - TUNNEL_PROBE_PORTAL_INSET * 2.0
	var probe_count := floori(sampled_length / TUNNEL_PROBE_SPACING) + 1
	for probe_index: int in range(probe_count):
		var z_offset := first_offset + float(probe_index) * TUNNEL_PROBE_SPACING
		result.append(Vector3(center.x, floor_y + 1.7, center.z + z_offset))
	return result


static func tunnel_acoustic_probe_descriptors() -> Array[Dictionary]:
	# All modular tunnel runs use one geometry-derived acoustic layout. Interior probes describe
	# the guide; un-guided exterior chains describe ordinary air beside the shell and connect only
	# around its open mouths. This prevents a hidden nearest interior probe from becoming an
	# accidental shortcut through a side wall without requiring emitter-specific fixes.
	var result: Array[Dictionary] = []
	for run_index: int in range(TUNNEL_RUN_COUNT):
		var run := _tunnel_run(run_index)
		var run_id := str(run.get("run_id", &"tunnel"))
		var definition := run.get("definition") as ModularStructureDefinition
		var center: Vector3 = run.get("center", Vector3.ZERO)
		var floor_y := float(run.get("floor_y", 0.0))
		var size := definition.module_size()
		var positions := tunnel_probe_positions(run_index)
		for probe_index: int in range(positions.size()):
			var is_endpoint := probe_index == 0 or probe_index == positions.size() - 1
			result.append({
				"name": "%sTunnelProbe%02d" % [run_id.to_pascal_case(), probe_index],
				"probe_id": "industrial_%s_tunnel_%02d" % [run_id, probe_index],
				"run_id": run.get("run_id", &"tunnel"),
				"role": &"inside",
				"position": positions[probe_index],
				"auto_connect_radius": 6.0,
				"reflection_sample_distance": 32.0,
				"environment_influence_radius": maxf(size.x * 0.7, 5.0),
				"reverb_scale": 1.15,
				"guided_influence_half_extents": Vector3(
					maxf(size.x * 0.5 - definition.shell_thickness, 0.5),
					maxf(size.y * 0.5 - definition.shell_thickness, 0.5),
					6.25 if is_endpoint else 4.25
				),
				"guided_influence_boundary_fade": clampf(size.x * 0.12, 0.5, 1.2),
			})
		var exterior_x_offset := (
			size.x * 0.5 + TUNNEL_EXTERIOR_PROBE_CLEARANCE
		)
		for lateral_side: int in [-1, 1]:
			var lateral_name := "left" if lateral_side < 0 else "right"
			for probe_index: int in range(positions.size()):
				result.append({
					"name": "%sTunnelExterior%s%02d" % [
						run_id.to_pascal_case(),
						lateral_name.to_pascal_case(),
						probe_index,
					],
					"probe_id": "industrial_%s_tunnel_exterior_%s_%02d" % [
						run_id,
						lateral_name,
						probe_index,
					],
					"run_id": run.get("run_id", &"tunnel"),
					"role": &"exterior_air",
					"position": Vector3(
						center.x + float(lateral_side) * exterior_x_offset,
						floor_y + 1.7,
						positions[probe_index].z
					),
					"auto_connect_radius": TUNNEL_EXTERIOR_PROBE_CONNECT_RADIUS,
					"sample_reflections": false,
					"environment_influence_radius": TUNNEL_PROBE_SPACING,
				})
		for side: int in [-1, 1]:
			var side_name := "South" if side < 0 else "North"
			var shell_corner_z := (
				center.z
				+ float(side) * (
					definition.total_length() * 0.5
					+ TUNNEL_EXTERIOR_PROBE_CLEARANCE
				)
			)
			var mouth_z := (
				center.z
				+ float(side) * (definition.total_length() * 0.5 + 2.0)
			)
			result.append({
				"name": "%sTunnel%sOutsideProbe" % [run_id.to_pascal_case(), side_name],
				"probe_id": "industrial_%s_tunnel_%s_outside" % [run_id, side_name.to_lower()],
				"run_id": run.get("run_id", &"tunnel"),
				"role": &"south_outside" if side < 0 else &"north_outside",
				"position": Vector3(
					center.x,
					floor_y + 1.7,
					mouth_z
				),
				"auto_connect_radius": 10.0,
				"sample_reflections": false,
				"environment_influence_radius": maxf(size.x, 8.0),
				"guided_spill_strength": 0.82,
				# The sample sits two metres clear of the shell so its graph links remain visible.
				# Radiation begins at the physical mouth and widens continuously into open air.
				"guided_spill_origin_offset": Vector3(
					0.0, 0.0, -float(side) * 2.0
				),
				"guided_spill_axis": Vector3(0.0, 0.0, float(side)),
				"guided_spill_aperture_half_extents": Vector2(
					maxf(size.x * 0.5 - definition.shell_thickness, 0.5),
					maxf(size.y * 0.5 - definition.shell_thickness, 0.5)
				),
				"guided_spill_divergence": Vector2(0.46, 0.32),
				"guided_spill_falloff_distance": maxf(size.x * 2.5, 10.0),
			})
			for lateral_side: int in [-1, 1]:
				var lateral_name := "left" if lateral_side < 0 else "right"
				# Resolve the physical shell corner before the farther mouth flank. Without this
				# sample the exterior graph follows two long axis-aligned legs, then jumps to a
				# much shorter diagonal route as soon as the centre mouth becomes partly visible.
				result.append({
					"name": "%sTunnel%s%sCornerProbe" % [
						run_id.to_pascal_case(),
						side_name,
						lateral_name.to_pascal_case(),
					],
					"probe_id": "industrial_%s_tunnel_%s_%s_corner" % [
						run_id,
						side_name.to_lower(),
						lateral_name,
					],
					"run_id": run.get("run_id", &"tunnel"),
					"role": &"exterior_air",
					"position": Vector3(
						center.x + float(lateral_side) * exterior_x_offset,
						floor_y + 1.7,
						shell_corner_z
					),
					"auto_connect_radius": TUNNEL_EXTERIOR_PROBE_CONNECT_RADIUS,
					"sample_reflections": false,
					"environment_influence_radius": TUNNEL_PROBE_SPACING,
				})
				result.append({
					"name": "%sTunnel%s%sFlankProbe" % [
						run_id.to_pascal_case(),
						side_name,
						lateral_name.to_pascal_case(),
					],
					"probe_id": "industrial_%s_tunnel_%s_%s_flank" % [
						run_id,
						side_name.to_lower(),
						lateral_name,
					],
					"run_id": run.get("run_id", &"tunnel"),
					"role": &"exterior_air",
					"position": Vector3(
						center.x + float(lateral_side) * exterior_x_offset,
						floor_y + 1.7,
						mouth_z
					),
					"auto_connect_radius": TUNNEL_EXTERIOR_PROBE_CONNECT_RADIUS,
					"sample_reflections": false,
					"environment_influence_radius": TUNNEL_PROBE_SPACING,
				})
	return result


## Compatibility for tools written while only the two comparison runs were generated at runtime.
static func additional_tunnel_probe_descriptors() -> Array[Dictionary]:
	return tunnel_acoustic_probe_descriptors()


static func _tunnel_run(run_index: int) -> Dictionary:
	var runs := tunnel_runs()
	return runs[run_index] if run_index >= 0 and run_index < runs.size() else {}


static func _append_tunnel(boxes: Array[Dictionary]) -> void:
	boxes.append_array(tunnel_structural_boxes())


static func _append_large_bunker(boxes: Array[Dictionary]) -> void:
	_append_bunker_shell(boxes, LARGE_BUNKER_CENTER, "LargeBunker", &"concrete")


static func _append_bunker_shell(
	boxes: Array[Dictionary],
	center: Vector3,
	name_prefix: String,
	material_id: StringName,
	acoustic_material: AcousticMaterial = null
) -> void:
	var half_width := LARGE_BUNKER_WIDTH * 0.5
	var half_depth := LARGE_BUNKER_DEPTH * 0.5
	var wall_half_height := LARGE_BUNKER_HEIGHT * 0.5
	_add_box(
		boxes,
		StringName("%sFloor" % name_prefix),
		center + Vector3(0.0, LARGE_BUNKER_FLOOR_THICKNESS * 0.5, 0.0),
		Vector3(
			LARGE_BUNKER_WIDTH + LARGE_BUNKER_WALL_THICKNESS,
			LARGE_BUNKER_FLOOR_THICKNESS,
			LARGE_BUNKER_DEPTH + LARGE_BUNKER_WALL_THICKNESS
		),
		Vector3.ZERO,
		material_id,
		true,
		acoustic_material
	)
	_add_box(
		boxes,
		StringName("%sRoof" % name_prefix),
		center + Vector3(
			0.0,
			LARGE_BUNKER_HEIGHT + LARGE_BUNKER_FLOOR_THICKNESS * 0.5,
			0.0
		),
		Vector3(
			LARGE_BUNKER_WIDTH + LARGE_BUNKER_WALL_THICKNESS,
			LARGE_BUNKER_FLOOR_THICKNESS,
			LARGE_BUNKER_DEPTH + LARGE_BUNKER_WALL_THICKNESS
		),
		Vector3.ZERO,
		material_id,
		true,
		acoustic_material
	)
	_add_box(
		boxes,
		StringName("%sWestWall" % name_prefix),
		center + Vector3(-half_width, wall_half_height, 0.0),
		Vector3(LARGE_BUNKER_WALL_THICKNESS, LARGE_BUNKER_HEIGHT, LARGE_BUNKER_DEPTH),
		Vector3.ZERO,
		material_id,
		true,
		acoustic_material
	)
	for z_side: int in [-1, 1]:
		_add_box(
			boxes,
			StringName("%s%sWall" % [name_prefix, "South" if z_side < 0 else "North"]),
			center + Vector3(0.0, wall_half_height, float(z_side) * half_depth),
			Vector3(LARGE_BUNKER_WIDTH, LARGE_BUNKER_HEIGHT, LARGE_BUNKER_WALL_THICKNESS),
			Vector3.ZERO,
			material_id,
			true,
			acoustic_material
		)
	var door_half_width := LARGE_BUNKER_DOOR_WIDTH * 0.5
	var east_x := center.x + half_width
	var south_edge := center.z - half_depth
	var north_edge := center.z + half_depth
	var door_south := center.z - door_half_width
	var door_north := center.z + door_half_width
	_add_box(
		boxes,
		StringName("%sEastWallSouth" % name_prefix),
		Vector3(east_x, wall_half_height, (south_edge + door_south) * 0.5),
		Vector3(LARGE_BUNKER_WALL_THICKNESS, LARGE_BUNKER_HEIGHT, door_south - south_edge),
		Vector3.ZERO,
		material_id,
		true,
		acoustic_material
	)
	_add_box(
		boxes,
		StringName("%sEastWallNorth" % name_prefix),
		Vector3(east_x, wall_half_height, (door_north + north_edge) * 0.5),
		Vector3(LARGE_BUNKER_WALL_THICKNESS, LARGE_BUNKER_HEIGHT, north_edge - door_north),
		Vector3.ZERO,
		material_id,
		true,
		acoustic_material
	)
	_add_box(
		boxes,
		StringName("%sEastWallHeader" % name_prefix),
		Vector3(
			east_x,
			LARGE_BUNKER_DOOR_HEIGHT
			+ (LARGE_BUNKER_HEIGHT - LARGE_BUNKER_DOOR_HEIGHT) * 0.5,
			center.z
		),
		Vector3(
			LARGE_BUNKER_WALL_THICKNESS,
			LARGE_BUNKER_HEIGHT - LARGE_BUNKER_DOOR_HEIGHT,
			LARGE_BUNKER_DOOR_WIDTH
		),
		Vector3.ZERO,
		material_id,
		true,
		acoustic_material
	)

	# Sparse columns and ceiling beams give the large room meaningful secondary reflections while
	# preserving a broad unobstructed central listening floor.
	for x_offset: float in [-12.0, 0.0, 12.0]:
		for z_offset: float in [-10.5, 10.5]:
			_add_box(
				boxes,
				StringName("%sColumn_%s_%s" % [name_prefix,
					str(x_offset).replace("-", "m").replace(".", "p"),
					str(z_offset).replace("-", "m").replace(".", "p"),
				]),
				center + Vector3(
					x_offset,
					LARGE_BUNKER_HEIGHT * 0.5,
					z_offset
				),
				Vector3(0.58, LARGE_BUNKER_HEIGHT, 0.58),
				Vector3.ZERO,
				material_id,
				true,
				acoustic_material
			)
	for z_offset: float in [-10.5, 10.5]:
		_add_box(
			boxes,
			StringName("%sCeilingBeam_%s" % [name_prefix, str(z_offset).replace("-", "m").replace(".", "p")]),
			center + Vector3(0.0, LARGE_BUNKER_HEIGHT - 0.45, z_offset),
			Vector3(LARGE_BUNKER_WIDTH - 0.9, 0.65, 0.58),
			Vector3.ZERO,
			material_id,
			true,
			acoustic_material
		)


static func _add_box(
	boxes: Array[Dictionary],
	node_name: StringName,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
	material_id: StringName,
	visual := true,
	acoustic_material: AcousticMaterial = null
) -> void:
	var descriptor := {
		"name": node_name,
		"position": position,
		"size": size,
		"rotation": rotation,
		"material_id": material_id,
		"visual": visual,
	}
	if acoustic_material != null:
		descriptor["acoustic_material"] = acoustic_material
	boxes.append(descriptor)


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
