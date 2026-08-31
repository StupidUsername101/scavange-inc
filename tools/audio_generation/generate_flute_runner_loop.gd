extends SceneTree

## Reproducibly authors the deliberately simple flute-runner melody. Keeping the recipe beside the
## generated WAV makes the placeholder easy to replace or retune without depending on a DAW file.

const MIX_RATE := 44100
const NOTE_SECONDS := 0.50
const NOTES := [
	74, 76, 77, 74,
	69, 71, 74, 69,
	74, 77, 79, 77,
	76, 71, 69, 71,
	74, 76, 77, 81,
	79, 77, 74, -1,
]
const OUTPUT_BASE := "res://assets/sounds/music/gameplay/flute_runner_loop"


func _init() -> void:
	var sample_count := roundi(float(NOTES.size()) * NOTE_SECONDS * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	var noise_state := 0x51F15EED
	var filtered_breath := 0.0
	for sample_index: int in range(sample_count):
		var seconds := float(sample_index) / float(MIX_RATE)
		var note_index := mini(floori(seconds / NOTE_SECONDS), NOTES.size() - 1)
		var note_time := fmod(seconds, NOTE_SECONDS)
		var midi: int = NOTES[note_index]
		var sample := 0.0
		if midi >= 0:
			var frequency := 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
			var vibrato := sin(seconds * TAU * 5.15 + float(note_index) * 0.37)
			frequency *= pow(2.0, vibrato * 0.11 / 12.0)
			phase = fmod(phase + TAU * frequency / float(MIX_RATE), TAU)
			var attack := smoothstep(0.0, 0.038, note_time)
			var release := 1.0 - smoothstep(NOTE_SECONDS - 0.14, NOTE_SECONDS, note_time)
			var envelope := attack * release
			var tone := (
				sin(phase) * 0.78
				+ sin(phase * 2.0 + 0.11) * 0.16
				+ sin(phase * 3.0 + 0.47) * 0.055
				+ sin(phase * 4.0 + 0.83) * 0.022
			)
			noise_state = int((noise_state * 1664525 + 1013904223) & 0x7fffffff)
			var white := float(noise_state) / float(0x7fffffff) * 2.0 - 1.0
			filtered_breath = lerpf(filtered_breath, white, 0.075)
			var breath := filtered_breath * (0.035 + 0.018 * sin(phase * 0.5))
			var wobble := 0.94 + sin(seconds * TAU * 0.73 + 1.1) * 0.06
			sample = (tone * 0.46 + breath) * envelope * wobble
		else:
			phase = 0.0
		var encoded := clampi(roundi(sample * 32767.0), -32768, 32767)
		bytes.encode_s16(sample_index * 2, encoded)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = sample_count
	var error := stream.save_to_wav(OUTPUT_BASE)
	if error != OK:
		push_error("Could not save flute runner loop: %s" % error_string(error))
		quit(1)
		return
	print("Generated %s.wav (%0.2f s)" % [OUTPUT_BASE, stream.get_length()])
	quit()
