class_name MouthClickAudioCatalog
extends RefCounted

## Drop recorded variations into this folder; the client library discovers them at world startup.
## The existing terminal click is intentionally only a development fallback so the complete
## multiplayer/propagation path remains testable before purpose-recorded mouth sounds arrive.

const RECORDING_DIRECTORY := "res://assets/sounds/player/mouth_clicks"
const FALLBACK_PATH := (
	"res://assets/third_party/pizza_doggy/audio/fieldlink/fieldlink_click.ogg"
)
const MAX_VARIATIONS := 16
const SUPPORTED_EXTENSIONS := ["ogg", "wav", "mp3"]


static func streams() -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	var file_names := DirAccess.get_files_at(RECORDING_DIRECTORY)
	file_names.sort()
	for file_name: String in file_names:
		if file_name.ends_with(".import"):
			continue
		var extension := file_name.get_extension().to_lower()
		if not SUPPORTED_EXTENSIONS.has(extension):
			continue
		var stream := load(RECORDING_DIRECTORY.path_join(file_name)) as AudioStream
		if stream == null:
			continue
		result.append(stream)
		if result.size() >= MAX_VARIATIONS:
			break
	if not result.is_empty():
		return result
	var fallback := load(FALLBACK_PATH) as AudioStream
	if fallback != null:
		result.append(fallback)
	return result
