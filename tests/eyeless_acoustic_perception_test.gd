extends SceneTree

const PLAYER_PROXY_SCENE := preload("res://scenes/proxy/player_proxy.tscn")
const SERVER_PLAYER_SCENE := preload("res://scenes/server/server_player.tscn")
const MOUTH_CLICK_AUDIO := preload(
	"res://scripts/audio/mouth_click_audio_catalog.gd"
)

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_static_contract()
	await _test_renderer_handoff()
	await _test_local_perception_lifecycle()
	_test_server_click_gate()
	if failure_count == 0:
		print("Eyeless acoustic perception tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Eyeless acoustic perception tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_static_contract() -> void:
	EyelessAcousticPerception.ensure_input_action()
	var events := InputMap.action_get_events(
		EyelessAcousticPerception.INPUT_ACTION
	)
	var has_default_key := false
	for event: InputEvent in events:
		var key := event as InputEventKey
		if (
			key != null
			and key.physical_keycode
			== EyelessAcousticPerception.DEFAULT_INPUT_KEY
		):
			has_default_key = true
	_expect(
		has_default_key,
		"eyeless echolocation owns a discoverable Q input without mutating project settings"
	)
	var profile := LocalAudioPrediction.player_cue_profile(&"mouth_click")
	_expect(
		GameAudioLibrary.registered_sound_ids().has(&"mouth_click")
		and not MOUTH_CLICK_AUDIO.streams().is_empty()
		and float(profile.get("max_distance", 0.0)) >= 30.0
		and float(profile.get("pressure_strength", 0.0)) > 0.0,
		"the mouth click has a playable fallback and one shared spatial-acoustic profile"
	)


func _test_renderer_handoff() -> void:
	var renderer := SpatialAudioRenderer.new()
	root.add_child(renderer)
	var streams := MOUTH_CLICK_AUDIO.streams()
	var registered := renderer.register_sound(&"sense_test", streams, {
		"base_volume_db": -2.0,
	})
	var rendered_packets: Array[Dictionary] = []
	renderer.acoustic_perception_event_rendered.connect(
		func(packet: Dictionary) -> void:
			rendered_packets.append(packet.duplicate(false))
	)
	var accepted := renderer.submit({
		"sound_id": &"sense_test",
		"apparent_position": Vector3(0.0, 1.0, -3.0),
		"volume_db": -7.0,
		"priority": 0.5,
		"travel_delay_seconds": 0.0,
		"band_gain": Vector3.ONE,
	})
	await process_frame
	_expect(
		registered
		and accepted
		and rendered_packets.size() == 1
		and is_equal_approx(
			float(rendered_packets[0].get("rendered_volume_db", INF)),
			-9.0
		),
		"perception receives only an admitted voice at its exact rendered listener level"
	)
	renderer.reset_session(true)
	renderer.free()


func _test_local_perception_lifecycle() -> void:
	var proxy := PLAYER_PROXY_SCENE.instantiate() as PlayerProxy
	root.add_child(proxy)
	proxy.set_local_player(true)
	proxy.apply_server_state(_state_with_eye_entry({}))
	var sense := proxy.get_node(
		"AcousticPerception/Sense"
	) as EyelessAcousticPerception
	var ocular_layer := proxy.get_node("OcularPostProcess") as CanvasLayer
	var perception_layer := proxy.get_node("AcousticPerception") as CanvasLayer
	_expect(
		sense.is_perception_active()
		and perception_layer.layer > ocular_layer.layer,
		"losing eyes activates a smooth sensory layer above the intentionally black ocular view"
	)

	var camera := proxy.get_node("HeadPivot/Camera3D") as Camera3D
	var audible_position := camera.global_position - camera.global_basis.z * 4.0
	sense.submit_acoustic_event({
		"sequence": 41,
		"sound_id": &"footstep_concrete",
		"apparent_position": audible_position,
		"volume_db": -12.0,
		"rendered_volume_db": -9.0,
		"band_gain": Vector3(0.8, 1.0, 0.55),
		"early_reflections": [{
			"apparent_position": audible_position + Vector3.RIGHT * 1.2,
			"extra_delay_seconds": 0.04,
			"gain": 0.32,
			"band_gain": Vector3(0.7, 0.8, 0.4),
		}],
	})
	sense.submit_continuous_sample(
		77,
		audible_position + Vector3.LEFT,
		0.45,
		Vector3(1.0, 0.8, 0.5),
		0.7
	)
	var heard_state := sense.debug_state()
	_expect(
		int(heard_state.get("pulse_count", 0)) == 2
		and int(heard_state.get("continuous_source_count", 0)) == 1,
		"final apparent sound positions create direct, reflected, and continuous impressions"
	)

	var echo_body := StaticBody3D.new()
	echo_body.collision_layer = CharacterContactLayers.MOVEMENT_SURFACE
	echo_body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 5.0, 0.35)
	collision.shape = box
	echo_body.add_child(collision)
	root.add_child(echo_body)
	echo_body.global_position = camera.global_position - camera.global_basis.z * 3.0
	await physics_frame
	sense.capture_near_field_echo(camera.global_position)
	_expect(
		int(sense.debug_state().get("surface_echo_count", 0)) > 0,
		"one voluntary click finds only first-hit nearby contact geometry"
	)

	var factory_eyes := load(
		"res://resources/items/eyes/factory_oculars.tres"
	) as EyeDefinition
	proxy.apply_server_state(
		_state_with_eye_entry(
			PlayerInventoryRules.to_public_entry(
				PlayerInventoryRules.make_entry(factory_eyes)
			)
		)
	)
	var restored_state := sense.debug_state()
	_expect(
		not sense.is_perception_active()
		and int(restored_state.get("pulse_count", -1)) == 0
		and int(restored_state.get("surface_echo_count", -1)) == 0,
		"re-equipping eyes immediately removes every acoustic impression"
	)

	echo_body.free()
	proxy.free()


func _test_server_click_gate() -> void:
	var player := SERVER_PLAYER_SCENE.instantiate() as ServerPlayer
	root.add_child(player)
	_expect(
		not player.request_echolocation_click(),
		"a sighted player cannot emit the special echolocation action"
	)
	var dropped_eyes := player.try_unequip_to_world(
		PlayerInventoryRules.EYES_SLOT
	)
	var accepted := player.request_echolocation_click()
	var throttled := player.request_echolocation_click()
	_expect(
		not dropped_eyes.is_empty() and accepted and not throttled,
		"the authority accepts clicks only while eyeless and rate-limits repeated requests"
	)
	player.free()


static func _state_with_eye_entry(eye_entry: Dictionary) -> Dictionary:
	var equipment: Dictionary = {}
	if not eye_entry.is_empty():
		equipment[PlayerInventoryRules.EYES_SLOT] = eye_entry
	return {
		"inventory": {
			"capacity": 1,
			"selected_slot": 0,
			"entries": [],
			"equipment": equipment,
		},
		"limbs": {
			"left_arm": true,
			"right_arm": true,
			"left_leg": true,
			"right_leg": true,
		},
	}


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] " + message)
		return
	failure_count += 1
	push_error("FAIL: " + message)
