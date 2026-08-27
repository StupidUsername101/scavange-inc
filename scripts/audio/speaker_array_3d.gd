class_name SpeakerArray3D
extends Node3D

## Composition root shared by authoritative and presentation-side speaker arrays.
##
## Add any number of SpeakerArrayEmitter3D descendants, assign one shared definition, and derive
## the side-specific controller from this class. Emitter IDs are deterministic across server and
## client even when marker insertion order differs.

@export var array_definition: SpeakerArrayDefinition

var _speaker_markers: Array[SpeakerArrayEmitter3D] = []


func _ready() -> void:
	_speaker_markers = _discover_speaker_markers()


func get_speaker_markers() -> Array[SpeakerArrayEmitter3D]:
	return _speaker_markers.duplicate()


func _discover_speaker_markers() -> Array[SpeakerArrayEmitter3D]:
	return collect_speaker_markers(self)


static func collect_speaker_markers(
	array_root: Node
) -> Array[SpeakerArrayEmitter3D]:
	var result: Array[SpeakerArrayEmitter3D] = []
	if array_root == null:
		return result
	for descendant: Node in array_root.find_children("*", "", true, false):
		if descendant is SpeakerArrayEmitter3D:
			result.append(descendant as SpeakerArrayEmitter3D)
	result.sort_custom(func(a: SpeakerArrayEmitter3D, b: SpeakerArrayEmitter3D) -> bool:
		if a.sort_order != b.sort_order:
			return a.sort_order < b.sort_order
		return str(array_root.get_path_to(a)) < str(array_root.get_path_to(b))
	)
	return result


## Allocation-bearing editor/test inspection path. Runtime controllers cache the typed markers and
## packed values once in `_ready`; compatibility diagnostics use this to avoid a duplicate layout.
static func describe_emitter_rig(
	rig_scene: PackedScene,
	definition: SpeakerArrayDefinition
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if rig_scene == null:
		return result
	var rig := rig_scene.instantiate() as Node3D
	if rig == null:
		return result
	var markers := collect_speaker_markers(rig)
	for speaker_index: int in range(markers.size()):
		var marker := markers[speaker_index]
		var relative_transform := marker.transform_relative_to(rig)
		result.append({
			"name": marker.name,
			"position": relative_transform.origin,
			"rotation": relative_transform.basis.get_euler(),
			"inside": marker.is_indoor,
			"emitter_id": (
				definition.emitter_id(speaker_index)
				if definition != null
				else 1_500_000_000 + speaker_index
			),
			"installation_gain_db": clampf(
				marker.installation_gain_db,
				-24.0,
				12.0
			),
			"source_position": marker.source_position_relative_to(rig),
		})
	rig.free()
	return result


func _cluster_contact_id() -> StringName:
	return (
		array_definition.contact_id
		if array_definition != null
		else &"facility:speaker_array"
	)


func _cluster_display_name() -> String:
	return array_definition.display_name if array_definition != null else "SPEAKER ARRAY"


func get_fieldlink_control_local_position() -> Vector3:
	return (
		array_definition.scanner_beacon_position
		if array_definition != null
		else Vector3(0.0, 1.6, 0.0)
	)


## Installed arrays may use a facility-level composition root far away from their cabinets. The
## scanner and the authoritative range check must therefore share this authored interaction point.
func get_fieldlink_control_world_position() -> Vector3:
	return global_transform * get_fieldlink_control_local_position()


func _shared_program_group_id() -> int:
	return (
		array_definition.shared_program_group_id()
		if array_definition != null
		else 1_500_000_000
	)


func _emitter_id(sorted_index: int) -> int:
	return (
		array_definition.emitter_id(sorted_index)
		if array_definition != null
		else 1_500_000_000 + sorted_index
	)
