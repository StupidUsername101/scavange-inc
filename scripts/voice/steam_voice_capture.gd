class_name SteamVoiceCapture
extends Node

signal speaking_changed(active: bool)
signal frame_captured(
	sequence: int,
	captured_msec: int,
	sample_rate: int,
	compressed: PackedByteArray
)

## Push-to-talk capture adapter for the locally installed GodotSteam API. Steam owns microphone
## selection, capture and compression; this node only drains bounded compressed frames while the
## action is held. It never retains raw microphone audio.

const MAX_DRAINED_FRAMES_PER_PROCESS := 4
const FALLBACK_GET_VOICE_BUFFER_BYTES := VoiceFramePacket.MAX_COMPRESSED_BYTES

var session_available := false
var recording := false
var sequence := 0
var sample_rate := VoiceFramePacket.DEFAULT_SAMPLE_RATE


func _ready() -> void:
	set_process(true)


func set_session_available(value: bool) -> void:
	session_available = value
	if not session_available:
		stop_recording()


func reset_session() -> void:
	stop_recording()
	session_available = false
	sequence = 0
	sample_rate = VoiceFramePacket.DEFAULT_SAMPLE_RATE


func _process(_delta: float) -> void:
	var wants_recording := (
		session_available
		and InputMap.has_action("push_to_talk")
		and Input.is_action_pressed("push_to_talk")
	)
	if wants_recording != recording:
		if wants_recording:
			start_recording()
		else:
			stop_recording()
	if not recording:
		return
	for _drain_index: int in range(MAX_DRAINED_FRAMES_PER_PROCESS):
		if not _capture_one_frame():
			break


func start_recording() -> bool:
	if recording or not session_available or not _steam_voice_ready():
		return false
	var optimal_rate := int(Steam.getVoiceOptimalSampleRate())
	sample_rate = clampi(
		optimal_rate if optimal_rate > 0 else VoiceFramePacket.DEFAULT_SAMPLE_RATE,
		VoiceFramePacket.MIN_SAMPLE_RATE,
		VoiceFramePacket.MAX_SAMPLE_RATE
	)
	Steam.startVoiceRecording()
	var steam_id := int(Steam.getSteamID())
	if steam_id > 0:
		Steam.setInGameVoiceSpeaking(steam_id, true)
	recording = true
	speaking_changed.emit(true)
	return true


func stop_recording() -> void:
	if not recording:
		return
	Steam.stopVoiceRecording()
	var steam_id := int(Steam.getSteamID())
	if steam_id > 0:
		Steam.setInGameVoiceSpeaking(steam_id, false)
	recording = false
	speaking_changed.emit(false)


func _capture_one_frame() -> bool:
	var available := Steam.getAvailableVoice() as Dictionary
	if (
		int(available.get("result", -1)) != int(Steam.VOICE_RESULT_OK)
		or int(available.get("buffer", 0)) <= 0
	):
		return false
	var requested_bytes := clampi(
		int(available.get("buffer", FALLBACK_GET_VOICE_BUFFER_BYTES)),
		1,
		VoiceFramePacket.MAX_COMPRESSED_BYTES
	)
	var voice := Steam.getVoice(requested_bytes) as Dictionary
	if int(voice.get("result", -1)) != int(Steam.VOICE_RESULT_OK):
		return false
	var compressed_value: Variant = voice.get("buffer", PackedByteArray())
	if not compressed_value is PackedByteArray:
		return false
	var compressed: PackedByteArray = compressed_value
	var written := clampi(
		int(voice.get("written", compressed.size())),
		0,
		compressed.size()
	)
	if written <= 0:
		return false
	if written < compressed.size():
		compressed = compressed.slice(0, written)
	sequence = sequence % 0x7ffffffe + 1
	frame_captured.emit(
		sequence,
		int(Time.get_ticks_msec() & VoiceFramePacket.MAX_CAPTURE_CLOCK_MSEC),
		sample_rate,
		compressed
	)
	return true


static func _steam_voice_ready() -> bool:
	return (
		Steam.has_method("startVoiceRecording")
		and Steam.has_method("stopVoiceRecording")
		and Steam.has_method("getAvailableVoice")
		and Steam.has_method("getVoice")
		and Steam.has_method("decompressVoice")
		and Steam.isSteamRunning()
		and Steam.loggedOn()
	)
