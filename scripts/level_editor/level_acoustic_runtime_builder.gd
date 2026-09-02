class_name LevelAcousticRuntimeBuilder
extends RefCounted

const AUTHORING := preload("res://scripts/level_editor/level_acoustic_authoring.gd")
const ACOUSTIC_PROBE_SCRIPT := preload("res://scripts/audio/acoustic_probe_3d.gd")
const ACOUSTIC_PORTAL_SCRIPT := preload("res://scripts/audio/acoustic_portal_3d.gd")
const PATH_MODIFIER_SCRIPT := preload("res://scripts/audio/acoustic_path_modifier.gd")


static func build_into(
	root: Node3D,
	probes: Array[Dictionary],
	portals: Array[Dictionary],
	name_prefix := "Level"
) -> Dictionary:
	if root == null:
		return {"valid": false, "probe_count": 0, "portal_count": 0}
	var validation := AUTHORING.validate(probes, portals)
	if not bool(validation.get("valid", false)):
		return validation
	var probe_nodes_by_id: Dictionary[int, Node] = {}
	for raw_probe: Dictionary in probes:
		var descriptor := AUTHORING.sanitize_probe(raw_probe)
		if descriptor.is_empty():
			continue
		var probe = ACOUSTIC_PROBE_SCRIPT.new()
		var probe_id := int(descriptor["id"])
		probe.name = "%sAcousticProbe%03d" % [name_prefix, probe_id]
		probe.probe_id = StringName("%s_probe_%03d" % [name_prefix.to_snake_case(), probe_id])
		probe.position = descriptor["position"]
		probe.auto_connect = bool(descriptor["auto_connect"])
		probe.auto_connect_radius = float(descriptor["auto_connect_radius"])
		probe.sample_reflections = bool(descriptor["sample_reflections"])
		probe.reflection_sample_distance = float(descriptor["reflection_sample_distance"])
		probe.environment_influence_radius = float(descriptor["environment_influence_radius"])
		probe.reverb_scale = float(descriptor["reverb_scale"])
		root.add_child(probe)
		probe_nodes_by_id[probe_id] = probe
	for raw_portal: Dictionary in portals:
		var descriptor := AUTHORING.sanitize_portal(raw_portal)
		if descriptor.is_empty():
			continue
		var probe_a: Node = probe_nodes_by_id.get(int(descriptor["probe_a_id"]))
		var probe_b: Node = probe_nodes_by_id.get(int(descriptor["probe_b_id"]))
		if probe_a == null or probe_b == null:
			continue
		var portal = ACOUSTIC_PORTAL_SCRIPT.new()
		var portal_id := int(descriptor["id"])
		portal.name = "%sAcousticPortal%03d" % [name_prefix, portal_id]
		portal.bidirectional = bool(descriptor["bidirectional"])
		portal.carries_guided_energy = bool(descriptor["carries_guided_energy"])
		portal.modifier = _modifier_for_profile(str(descriptor["profile"]))
		root.add_child(portal)
		portal.probe_a_path = portal.get_path_to(probe_a)
		portal.probe_b_path = portal.get_path_to(probe_b)
	return validation


static func apply_placement_boundary(
	collision_object: CollisionObject3D,
	placement: Dictionary
) -> void:
	if collision_object != null:
		collision_object.set_meta(
			&"acoustic_boundary",
			bool(placement.get("acoustic_boundary", true))
		)


static func _modifier_for_profile(profile: String):
	if profile == "open":
		return null
	var modifier = PATH_MODIFIER_SCRIPT.new()
	if profile == "vent":
		modifier.modifier_id = &"authored_vent"
		modifier.band_gain = Vector3(0.88, 0.72, 0.42)
		modifier.volume_db = -1.5
		modifier.lowpass_hz = 7200.0
		modifier.reverb_send = 0.08
	else:
		modifier.modifier_id = &"authored_thin_wall"
		modifier.band_gain = Vector3(0.76, 0.44, 0.18)
		modifier.volume_db = -3.0
		modifier.lowpass_hz = 4200.0
		modifier.reverb_send = 0.12
	return modifier

