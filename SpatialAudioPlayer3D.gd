@tool
extends Node3D
class_name SpatialAudioPlayer3D

## Registers one semantic sound with the local renderer. Gameplay invokes emit_authoritative()
## on the server; clients never decide propagation or broadcast their own sound results.

@export var sound_id: StringName = &""
@export var variations: Array[AudioStream] = []
@export var pressure_variations: Array[AudioStream] = []
@export_range(-60.0, 18.0, 0.1) var base_volume_db := 0.0
@export_range(0.25, 4.0, 0.01) var pitch_min := 0.97
@export_range(0.25, 4.0, 0.01) var pitch_max := 1.03
## Reach at 0 dB. emit_authoritative() scales it from base_volume_db before server culling.
@export_range(0.1, 10000.0, 0.1, "or_greater") var max_distance := 48.0
@export_range(0.0, 1.0, 0.01) var priority := 0.5
## Briefly creates mix headroom in loud continuous sources so a critical attack remains audible.
@export_range(0.0, 1.0, 0.01) var foreground_transient_strength := 0.0
## -1 derives a conservative response from reach, level and priority. Set 0 to opt out or
## 0..1 to override it for unusually soft or explosive sources.
@export_range(-1.0, 1.0, 0.01) var pressure_strength := -1.0
@export var source_modifier: AcousticPathModifier


func _ready() -> void:
	if Engine.is_editor_hint() or sound_id.is_empty() or variations.is_empty():
		return
	Client.register_spatial_sound(
		sound_id,
		variations,
		{
			"base_volume_db": base_volume_db,
			"pitch_min": pitch_min,
			"pitch_max": pitch_max,
			"pressure_streams": pressure_variations,
			"foreground_transient_strength": foreground_transient_strength,
		},
		get_instance_id()
	)


func _exit_tree() -> void:
	if Engine.is_editor_hint() or sound_id.is_empty():
		return
	Client.unregister_spatial_sound(sound_id, get_instance_id())


func emit_authoritative() -> int:
	if not multiplayer.is_server():
		push_warning("Only the server may emit an authoritative spatial sound")
		return -1
	return Server.emit_spatial_sound(
		sound_id,
		global_position,
		max_distance,
		0.0,
		source_modifier,
		priority,
		pressure_strength
	)
