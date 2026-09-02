class_name LevelSpeakerSystemRuntimeBuilder
extends RefCounted

const PLAYBACK_PROFILE := preload(
	"res://resources/items/radios/facility_pa_playback.tres"
)


static func build_server_systems(
	parent: Node3D,
	system_values: Array[Dictionary]
) -> Array[ServerSpeakerCluster]:
	var result: Array[ServerSpeakerCluster] = []
	if parent == null:
		return result
	for raw_system: Dictionary in system_values:
		var system := LevelSpeakerSystemAuthoring.sanitize_system(raw_system)
		if system.is_empty():
			continue
		var cluster := ServerSpeakerCluster.new()
		_configure_cluster(cluster, system)
		parent.add_child(cluster)
		result.append(cluster)
	return result


static func build_client_systems(
	parent: Node3D,
	system_values: Array[Dictionary]
) -> Array[SpeakerClusterDemoProxy]:
	var result: Array[SpeakerClusterDemoProxy] = []
	if parent == null:
		return result
	for raw_system: Dictionary in system_values:
		var system := LevelSpeakerSystemAuthoring.sanitize_system(raw_system)
		if system.is_empty():
			continue
		var cluster := SpeakerClusterDemoProxy.new()
		_configure_cluster(cluster, system)
		parent.add_child(cluster)
		result.append(cluster)
	return result


static func _configure_cluster(cluster: SpeakerArray3D, system: Dictionary) -> void:
	cluster.name = "AuthoredSpeakerArray%03d" % int(system.get("id", 0))
	cluster.position = system.get("origin", Vector3.ZERO)
	cluster.array_definition = _definition_from_system(system)
	var emitters := Node3D.new()
	emitters.name = "Emitters"
	cluster.add_child(emitters)
	var speaker_index := 0
	for speaker: Dictionary in system.get("speakers", []):
		var emitter := SpeakerArrayEmitter3D.new()
		emitter.name = "Speaker%03d" % speaker_index
		emitter.sort_order = speaker_index
		emitter.position = speaker.get("position", Vector3.ZERO)
		emitter.rotation = speaker.get("rotation", Vector3.ZERO)
		emitter.is_indoor = bool(speaker.get("is_indoor", true))
		emitter.installation_gain_db = float(
			speaker.get("installation_gain_db", 0.0)
		)
		emitter.cabinet_size = speaker.get(
			"cabinet_size",
			LevelSpeakerSystemAuthoring.DEFAULT_CABINET_SIZE
		)
		emitters.add_child(emitter)
		speaker_index += 1


static func _definition_from_system(system: Dictionary) -> SpeakerArrayDefinition:
	var definition := SpeakerArrayDefinition.new()
	definition.contact_id = StringName(str(system.get("contact_id", "")))
	definition.display_name = str(system.get("display_name", "PA SYSTEM"))
	definition.device_class = &"PA ARRAY"
	definition.audio_id_base = int(system.get("audio_id_base", 1_650_000_000))
	definition.playback_profile = PLAYBACK_PROFILE
	definition.maximum_hearing_distance = float(
		system.get("maximum_hearing_distance", 72.0)
	)
	definition.playback_volume_db = float(system.get("playback_volume_db", -11.0))
	definition.shared_late_field_enabled = bool(
		system.get("shared_late_field_enabled", false)
	)
	definition.scanner_beacon_position = system.get(
		"scanner_beacon_position",
		Vector3.ZERO
	)
	definition.scanner_signal_strength = 1.35
	return definition
