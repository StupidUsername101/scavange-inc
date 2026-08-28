class_name ServerAcousticMaze
extends StaticBody3D

const LAYOUT := preload("res://scripts/world/acoustic_maze_layout.gd")
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const EXIT_RADIO_DEFINITION_PATH := (
	"res://resources/world/maze_exit_beacon_radio.tres"
)

@export var spawn_exit_radio := true

var acoustic_material: AcousticMaterial
var exit_radio: RigidBody3D


func _ready() -> void:
	add_to_group(&"acoustic_maze")
	PHYSICAL_SURFACE.apply_to(self, &"concrete")
	acoustic_material = LAYOUT.create_acoustic_material()
	set_meta(&"acoustic_boundary", true)
	set_meta(&"acoustic_material", acoustic_material)
	_build_collision()
	_build_probes()
	if spawn_exit_radio and multiplayer.is_server():
		call_deferred("_spawn_exit_radio")


func _exit_tree() -> void:
	if is_instance_valid(exit_radio) and not exit_radio.is_queued_for_deletion():
		exit_radio.queue_free()


func get_acoustic_material() -> AcousticMaterial:
	return acoustic_material


func _build_collision() -> void:
	for descriptor: Dictionary in LAYOUT.structural_boxes():
		var shape := BoxShape3D.new()
		shape.size = descriptor.get("size", Vector3.ONE)
		var collision := CollisionShape3D.new()
		collision.name = "%sCollision" % str(descriptor.get("name", &"MazeBox"))
		collision.position = descriptor.get("position", Vector3.ZERO)
		collision.shape = shape
		add_child(collision)


func _build_probes() -> void:
	var probes_by_id: Dictionary = {}
	for descriptor: Dictionary in LAYOUT.probe_descriptors():
		var probe := _add_probe(descriptor)
		probes_by_id[probe.probe_id] = probe
	for descriptor: Dictionary in LAYOUT.exterior_probe_descriptors():
		var probe := _add_probe(descriptor)
		probes_by_id[probe.probe_id] = probe
		var transmission_cell := int(descriptor.get("transmission_cell", -1))
		if transmission_cell < 0:
			continue
		_add_boundary_transmission_portal(
			probes_by_id.get(StringName("maze_%03d" % transmission_cell)) as AcousticProbe3D,
			probe,
			bool(descriptor.get("is_open_aperture", false))
		)


func _add_probe(descriptor: Dictionary) -> AcousticProbe3D:
	var probe := AcousticProbe3D.new()
	probe.name = str(descriptor.get("name", "MazeProbe"))
	probe.probe_id = StringName(str(descriptor.get("probe_id", "")))
	probe.position = descriptor.get("position", Vector3.ZERO)
	probe.auto_connect_radius = float(descriptor.get(
		"auto_connect_radius",
		LAYOUT.CELL_SIZE * 1.08
	))
	probe.auto_connect_layer = int(descriptor.get("auto_connect_layer", 1))
	probe.auto_connect_mask = int(descriptor.get("auto_connect_mask", 0x7fffffff))
	probe.sample_reflections = bool(descriptor.get("sample_reflections", true))
	probe.environment_influence_radius = float(descriptor.get(
		"environment_influence_radius",
		LAYOUT.CELL_SIZE * 0.92
	))
	probe.reflection_sample_distance = float(descriptor.get(
		"reflection_sample_distance",
		22.0
	))
	probe.attachment_exclusion_center_offset = descriptor.get(
		"attachment_exclusion_center_offset",
		Vector3.ZERO
	)
	probe.attachment_exclusion_half_extents = descriptor.get(
		"attachment_exclusion_half_extents",
		Vector3.ZERO
	)
	probe.attachment_influence_center_offset = descriptor.get(
		"attachment_influence_center_offset",
		Vector3.ZERO
	)
	probe.attachment_influence_half_extents = descriptor.get(
		"attachment_influence_half_extents",
		Vector3.ZERO
	)
	probe.attachment_influence_boundary_fade = float(descriptor.get(
		"attachment_influence_boundary_fade",
		0.0
	))
	add_child(probe)
	return probe


func _add_boundary_transmission_portal(
	interior_probe: AcousticProbe3D,
	exterior_probe: AcousticProbe3D,
	is_open_aperture := false
) -> void:
	if interior_probe == null or exterior_probe == null:
		return
	var portal := AcousticPortal3D.new()
	portal.name = "%sTransmission" % exterior_probe.name
	portal.material = null if is_open_aperture else acoustic_material
	portal.bidirectional = true
	add_child(portal)
	portal.probe_a_path = portal.get_path_to(exterior_probe)
	portal.probe_b_path = portal.get_path_to(interior_probe)


func _spawn_exit_radio() -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var server := get_node_or_null("/root/Server")
	if server == null or server.get("server_world") == null:
		return
	var local_position := LAYOUT.exit_position()
	local_position.y = 0.05
	var exit_radio_definition := load(
		EXIT_RADIO_DEFINITION_PATH
	) as RadioItemDefinition
	if exit_radio_definition == null:
		push_warning("Acoustic maze could not load its exit radio definition")
		return
	var radio_transform := global_transform * Transform3D(
		Basis.from_euler(Vector3(0.0, PI, 0.0)),
		local_position
	)
	exit_radio = server.call(
		"spawn_item",
		exit_radio_definition,
		radio_transform
	) as RigidBody3D
	if exit_radio == null:
		push_warning("Acoustic maze could not spawn its exit radio")
		return
	exit_radio.name = "MazeExitBeaconRadio"
	# The beacon is an ordinary physical radio after placement. Freezing it here silently overrode
	# the definition's grippable contract and made a successful player grab look like a failed one.
	exit_radio.freeze = false
	exit_radio.gravity_scale = 1.0
	exit_radio.set_meta(&"maze_exit_beacon", true)
	exit_radio.call("set_control_volume_ratio", 1.0)
	# Installed sources follow the same contract as portable radios: the world may place and
	# register them, but only an explicit player/Fieldlink command begins playback.
