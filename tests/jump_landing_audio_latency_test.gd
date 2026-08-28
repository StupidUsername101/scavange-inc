extends SceneTree

## Full local-host landing latency probe.
##
## A production ServerPlayer performs a ballistic jump against the production server world's floor.
## Its landing follows the real Server.emit_spatial_sound -> acoustic solve -> local RPC ->
## SpatialAudioRenderer path. AudioEffectCapture then finds the first audible sample on Master.
## Capture is upstream of the OS and Bluetooth transport, which separates game latency from device
## latency. The onset search starts at physical contact; the full ballistic flight leaves the launch
## recording enough time to finish before that measurement window.

const AUDIO_LIBRARY_SCRIPT := preload(
	"res://scripts/audio/game_audio_library.gd"
)
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")

const LANDING_SOUND_ID := &"landing_concrete"
const PHYSICS_DELTA := 1.0 / 60.0
const MAX_SIMULATION_TICKS := 240
const CAPTURE_SETTLE_SECONDS := 0.35
const AUDIBLE_SAMPLE_THRESHOLD := 0.005
const MAX_CONTACT_TO_CAPTURE_SECONDS := 0.080

var _capture: AudioEffectCapture
var _capture_effect_index := -1
var _mix_rate := 44100
var _initial_bus_count := 0
var _server: Node
var _client: Node
var _game_state: Node
var _player: ServerPlayer
var _audio_library: Node
var _camera: Camera3D
var _server_physics_was_enabled := true

var _jump_request_usec := -1
var _contact_tick_usec := -1
var _contact_capture_frame := -1
var _landing_packet_usec := -1
var _landing_packet_travel_seconds := 0.0
var _landing_voice_start_usec := -1
var _landing_packet_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_mix_rate = roundi(AudioServer.get_mix_rate())
	_initial_bus_count = AudioServer.bus_count
	_server = root.get_node_or_null("Server")
	_client = root.get_node_or_null("Client")
	_game_state = root.get_node_or_null("GameState")
	if _server == null or _client == null or _game_state == null:
		_fail("required Server, Client, or GameState autoload is unavailable")
		return

	_prepare_master_capture()
	_client.call("reset_session")
	_server.call("spawn_server_world")
	var server_world := _server.get("server_world") as Node3D
	if server_world == null:
		_fail("production server world could not be spawned")
		return
	var ground := server_world.get_node_or_null("Ground") as StaticBody3D
	if ground == null:
		_fail("production server floor is unavailable")
		return
	# Keep the semantic deterministic; concrete streams are short and have an immediate measured
	# transient, unlike a few deliberately scuff-heavy soil variations.
	PHYSICAL_SURFACE.apply_to(ground, PHYSICAL_SURFACE.CONCRETE)

	_audio_library = AUDIO_LIBRARY_SCRIPT.new()
	_audio_library.name = "LandingLatencyAudioLibrary"
	root.add_child(_audio_library)
	var renderer := _client.get("spatial_audio_renderer") as SpatialAudioRenderer
	if renderer == null:
		_fail("production spatial renderer was not created by the audio library")
		return
	renderer.foreground_transient_started.connect(_on_foreground_transient_started)
	_client.connect("spatial_sound_received", _on_spatial_sound_received)
	_add_listener()

	var player_id: int = _game_state.call("try_register_player", 1, 1000, 4)
	if player_id < 0:
		player_id = int(_game_state.call("get_player_id", 1))
	if player_id < 0:
		_fail("offline host player could not be registered")
		return
	_server.call(
		"spawn_server_player",
		player_id,
		Vector3(0.0, 1.0, 0.0),
		null,
		null
	)
	_player = _server.call("get_server_player", player_id) as ServerPlayer
	if _player == null:
		_fail("production ServerPlayer could not be spawned")
		return

	# Drive this one player deterministically ourselves. The normal Server autoload loop is disabled
	# for the duration so a physics frame cannot advance the jump a second time behind the probe.
	_server_physics_was_enabled = _server.is_physics_processing()
	_server.set_physics_process(false)
	_player.on_floor = true
	_player.footstep_surface = PHYSICAL_SURFACE.CONCRETE
	_camera.global_position = _player.get_audio_listener_position() + Vector3.BACK * 0.15

	await physics_frame
	await physics_frame
	await create_timer(0.08).timeout
	_discard_capture()

	_jump_request_usec = Time.get_ticks_usec()
	_player.request_jump()
	var previous_on_floor := true
	var landed := false
	for _tick: int in range(MAX_SIMULATION_TICKS):
		var tick_start_usec := Time.get_ticks_usec()
		var capture_frame_at_tick_start := _capture.get_frames_available()
		_player.server_physics_tick(PHYSICS_DELTA)
		if not previous_on_floor and _player.on_floor:
			_contact_tick_usec = tick_start_usec
			_contact_capture_frame = capture_frame_at_tick_start
			landed = true
			break
		previous_on_floor = _player.on_floor
		await create_timer(PHYSICS_DELTA).timeout
	if not landed:
		_fail("the production ServerPlayer did not land after its ballistic jump")
		return
	if _landing_packet_usec <= 0:
		_fail("landing contact did not cross the real server-to-client acoustic bridge")
		return

	await create_timer(CAPTURE_SETTLE_SECONDS).timeout
	var captured := _capture.get_buffer(_capture.get_frames_available())
	var first_audible_frame := _find_first_audible_frame(
		captured,
		_contact_capture_frame
	)
	if first_audible_frame < 0:
		_fail("Master capture never observed the curated landing transient")
		return

	var flight_seconds := float(
		_contact_tick_usec - _jump_request_usec
	) / 1000000.0
	var bridge_seconds := float(
		_landing_packet_usec - _contact_tick_usec
	) / 1000000.0
	var voice_seconds := float(
		_landing_voice_start_usec - _contact_tick_usec
	) / 1000000.0
	var capture_seconds := float(
		first_audible_frame - _contact_capture_frame
	) / float(_mix_rate)
	var output_latency_seconds := AudioServer.get_output_latency()
	print("Jump landing audio latency probe (full local-host path)")
	print("  ballistic flight (not latency): %.1f ms" % (flight_seconds * 1000.0))
	print("  contact tick -> client packet: %.3f ms" % (bridge_seconds * 1000.0))
	print("  packet physical travel delay: %.3f ms" % (
		_landing_packet_travel_seconds * 1000.0
	))
	print("  contact tick -> renderer voice: %.3f ms" % (voice_seconds * 1000.0))
	print("  contact tick -> first captured sample: %.3f ms" % (
		capture_seconds * 1000.0
	))
	print("  AudioServer reported output latency: %.3f ms" % (
		output_latency_seconds * 1000.0
	))
	print("  estimated game + output buffer before Bluetooth: %.3f ms" % (
		(capture_seconds + output_latency_seconds) * 1000.0
	))

	var passed := (
		_landing_packet_count == 1
		and bridge_seconds >= 0.0
		and bridge_seconds <= 0.020
		and voice_seconds >= 0.0
		and voice_seconds <= MAX_CONTACT_TO_CAPTURE_SECONDS
		and capture_seconds >= 0.0
		and capture_seconds <= MAX_CONTACT_TO_CAPTURE_SECONDS
	)
	if passed:
		print("Jump landing audio latency test passed")
	else:
		push_error(
			"Jump landing audio latency exceeded the %.0f ms in-engine budget"
			% (MAX_CONTACT_TO_CAPTURE_SECONDS * 1000.0)
		)
	_cleanup()
	quit(0 if passed else 1)


func _prepare_master_capture() -> void:
	var master_index := AudioServer.get_bus_index(&"Master")
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 8.0
	_capture_effect_index = AudioServer.get_bus_effect_count(master_index)
	AudioServer.add_bus_effect(master_index, _capture)


func _add_listener() -> void:
	_camera = Camera3D.new()
	_camera.name = "LandingLatencyListener"
	_camera.current = true
	root.add_child(_camera)


func _on_spatial_sound_received(packet: Dictionary) -> void:
	if packet.get("sound_id", &"") != LANDING_SOUND_ID:
		return
	_landing_packet_count += 1
	if _landing_packet_usec > 0:
		return
	_landing_packet_usec = Time.get_ticks_usec()
	_landing_packet_travel_seconds = float(
		packet.get("travel_delay_seconds", 0.0)
	)


func _on_foreground_transient_started(
	_strength: float,
	_received_volume_db: float
) -> void:
	if _landing_packet_usec > 0 and _landing_voice_start_usec < 0:
		_landing_voice_start_usec = Time.get_ticks_usec()


func _discard_capture() -> void:
	var available := _capture.get_frames_available()
	if available > 0:
		_capture.get_buffer(available)


static func _find_first_audible_frame(
	samples: PackedVector2Array,
	from_frame: int
) -> int:
	for frame_index: int in range(clampi(from_frame, 0, samples.size()), samples.size()):
		var sample := samples[frame_index]
		if maxf(absf(sample.x), absf(sample.y)) >= AUDIBLE_SAMPLE_THRESHOLD:
			return frame_index
	return -1


func _cleanup() -> void:
	if is_instance_valid(_server):
		_server.set_physics_process(_server_physics_was_enabled)
	if is_instance_valid(_client):
		_client.call("reset_session")
	if is_instance_valid(_audio_library):
		_audio_library.free()
	if is_instance_valid(_camera):
		_camera.free()
	var master_index := AudioServer.get_bus_index(&"Master")
	if (
		_capture_effect_index >= 0
		and _capture_effect_index < AudioServer.get_bus_effect_count(master_index)
	):
		AudioServer.remove_bus_effect(master_index, _capture_effect_index)
	for bus_index: int in range(AudioServer.bus_count - 1, _initial_bus_count - 1, -1):
		AudioServer.remove_bus(bus_index)


func _fail(message: String) -> void:
	push_error("Jump landing audio latency test failed: %s" % message)
	_cleanup()
	quit(1)
