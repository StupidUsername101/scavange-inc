@tool
class_name RadioItemDefinition
extends ItemDefinition

const MUSIC_ROOT := "res://assets/sounds/music"
const GAMEPLAY_PROGRAM_ROOT := MUSIC_ROOT + "/gameplay"
const MUSIC_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]

## Item data shared by the authoritative radio body and each client's local renderer.
## Tracks are discovered instead of enumerated so dropping another supported file in the music
## folder automatically makes it available on the next game start.

@export_group("Radio")
@export_dir var music_directory := MUSIC_ROOT
## Reach at the device's calibrated playback level. Runtime amplifier control scales this range.
@export_range(1.0, 500.0, 0.5, "or_greater") var maximum_hearing_distance := 42.0
@export_range(-60.0, 18.0, 0.1) var playback_volume_db := -7.0
@export var speaker_local_position := Vector3(-0.17, 0.24, 0.235)
@export var source_modifier: AcousticPathModifier

@export_group("Radio Distortion")
@export_enum("Clip", "Atan", "Lo-Fi", "Overdrive", "Waveshape") var distortion_mode := 3
@export_range(0.0, 1.0, 0.01) var distortion_drive := 0.1
@export_range(20.0, 20000.0, 1.0, "or_greater") var distortion_keep_hf_hz := 12000.0
@export_range(-24.0, 12.0, 0.1) var distortion_post_gain_db := -1.5

@export_group("Radio Static")
## Receiver/electronics noise is a device characteristic, not a very quiet mandatory layer.
## Keep this explicit so clean PA systems do not start and render a nominally "silent" loop.
@export var receiver_static_enabled := true
@export_range(-60.0, 0.0, 0.5) var static_mix_db := -24.0


func discover_song_paths() -> Array[String]:
	var directory := _sanitized_music_directory()
	if directory.is_empty():
		return []
	var discovered := ResourcePathDiscovery.collect(directory, MUSIC_EXTENSIONS)
	var result: Array[String] = []
	for path: String in discovered:
		# Continuous gameplay programs (enemy instruments, alarms, machinery) use the same hardened
		# renderer but must never become random user-selectable radio tracks merely because the packet
		# boundary intentionally restricts all streams to one safe audio root.
		if not path.begins_with(GAMEPLAY_PROGRAM_ROOT + "/"):
			result.append(path)
	return result


func get_speaker_world_position(item_transform: Transform3D) -> Vector3:
	return item_transform * speaker_local_position


func _sanitized_music_directory() -> String:
	var directory := music_directory.strip_edges()
	while directory.ends_with("/"):
		directory = directory.trim_suffix("/")
	if (
		directory == MUSIC_ROOT
		or directory.begins_with(MUSIC_ROOT + "/")
	):
		return directory
	push_warning(
		"Radio music directory must stay beneath %s: %s"
		% [MUSIC_ROOT, music_directory]
	)
	return ""
