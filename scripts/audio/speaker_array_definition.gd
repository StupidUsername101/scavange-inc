@tool
class_name SpeakerArrayDefinition
extends Resource

## Shared identity and playback policy for a marker-driven speaker array.
##
## Speaker count, placement, orientation, and per-cabinet installation gain deliberately do not
## live here. They are authored as SpeakerArrayEmitter3D children of the array scene, so the same
## controller can drive one cabinet, a symmetric hall, or an irregular facility installation.

@export_group("Identity")
@export var contact_id: StringName = &"facility:speaker_array"
@export var display_name := "SPEAKER ARRAY"
@export var device_class: StringName = &"PA ARRAY"
@export_range(1, 2_000_000_000, 1) var audio_id_base := 1_500_000_000

@export_group("Playback")
@export var playback_profile: RadioItemDefinition
@export var source_modifier: AcousticPathModifier
@export_range(1.0, 1000.0, 0.5, "or_greater") var maximum_hearing_distance := 72.0
@export_range(-60.0, 18.0, 0.1) var playback_volume_db := -11.0
## Enables the client-rendered shared wet return for synchronized cabinets. The propagation graph
## still owns routing, obstruction, diffraction, and geometry-derived room energy either way.
@export var shared_late_field_enabled := false

@export_group("Scanner")
@export var scanner_beacon_position := Vector3(0.0, 1.6, 0.0)
@export_range(0.0, 8.0, 0.05, "or_greater") var scanner_signal_strength := 1.35


func emitter_id(sorted_index: int) -> int:
	return audio_id_base + maxi(sorted_index, 0)


func shared_program_group_id() -> int:
	return audio_id_base

