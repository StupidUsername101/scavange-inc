extends SceneTree

const WRIST_DEVICE_PATH := (
	"res://resources/items/wrist_devices/corporate_field_terminal.tres"
)
const WRIST_PRESENTATION_SCENE := preload(
	"res://scenes/proxy/wrist_terminal_presentation.tscn"
)
const WRIST_VIEW := preload(
	"res://scripts/client/wrist_terminal_view.gd"
)
const PLAYER_PROXY_SCENE := preload(
	"res://scenes/proxy/player_proxy.tscn"
)
const DEVICE_BEACON := preload(
	"res://scripts/client/fieldlink_device_beacon.gd"
)
const HELD_DEVICE_MOTION := preload(
	"res://scripts/characters/first_person_held_device_motion.gd"
)
const TERMINAL_AIM_RING := preload(
	"res://scripts/client/terminal_aim_ring.gd"
)
const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)

#######################################################
# Checks the Fieldlink's item, wearable, first-person screen, and session-control contracts.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_physical_item_contract()
	_test_terminal_interface()
	_test_selectable_device_controls()
	_test_device_contact_contract()
	_test_held_device_motion()
	_test_first_person_presentation()
	_test_local_body_arm_isolation()
	_test_client_input_contract()

	if failure_count == 0:
		print("Wrist terminal tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Wrist terminal tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_physical_item_contract() -> void:
	var definition := load(WRIST_DEVICE_PATH) as EquippableItemDefinition
	_expect(definition != null, "Fieldlink definition loads")
	if definition == null:
		return
	_expect(
		definition.equipment_slot == PlayerInventoryRules.WRIST_DEVICE_SLOT,
		"Fieldlink equips through the generic wrist slot"
	)
	var world_visual := definition.instantiate_visual()
	var equipped_visual := definition.instantiate_equipped_visual()
	_expect(
		world_visual != null and equipped_visual != null,
		"Fieldlink instantiates through ordinary item and equipment paths"
	)
	if world_visual != null:
		var imported_screen := world_visual.find_child(
			"screen_etx_1_partial_round_screen",
			true,
			false
		) as MeshInstance3D
		var contains_quad := false
		for mesh_node: Node in world_visual.find_children(
			"*",
			"MeshInstance3D",
			true,
			false
		):
			if (mesh_node as MeshInstance3D).mesh is QuadMesh:
				contains_quad = true
		_expect(
			imported_screen != null
			and imported_screen.mesh is ArrayMesh
			and world_visual.find_child(
				"TechScreenHousing",
				true,
				false
			) != null,
			"the physical item exposes the asset's dedicated curved screen mesh"
		)
		_expect(
			not contains_quad,
			"the physical Fieldlink visual contains no synthetic display plane"
		)
		world_visual.free()
	if equipped_visual != null:
		equipped_visual.free()


func _test_terminal_interface() -> void:
	var view := WRIST_VIEW.new() as WristTerminalView
	root.add_child(view)
	_expect(
		view.pointer_ring != null
		and view.pointer_ring.get_script() == TERMINAL_AIM_RING,
		"Fieldlink reuses the parts-scanner terminal aim ring"
	)
	view.set_session_info("HOST  /  2 OF 4", true)
	var invite := view.find_child("InviteFriend", true, false) as Button
	var return_button := view.find_child("ReturnToMenu", true, false) as Button
	var home_button := view.find_child("HomeNavigation", true, false) as Button
	var scanner_button := view.find_child(
		"ScannerNavigation",
		true,
		false
	) as Button
	var scanner_card := view.find_child("OpenScanner", true, false) as Button
	_expect(
		invite != null and not invite.disabled,
		"invite control is enabled for an open Steam lobby"
	)
	_expect(
		return_button != null
		and return_button.get_parent().name == "TopNavigation",
		"return-to-menu control lives in the persistent top bar"
	)
	_expect(
		invite != null
		and invite.has_meta(WristTerminalView.HOVER_HINT_META)
		and return_button != null
		and return_button.has_meta(WristTerminalView.HOVER_HINT_META)
		and home_button != null
		and home_button.has_meta(WristTerminalView.HOVER_HINT_META)
		and scanner_button != null
		and scanner_button.has_meta(WristTerminalView.HOVER_HINT_META),
		"every persistent navigation control explains itself in the hint bar"
	)
	_expect(
		invite != null
		and invite.tooltip_text.is_empty()
		and return_button != null
		and return_button.tooltip_text.is_empty()
		and home_button.tooltip_text.is_empty()
		and scanner_button.tooltip_text.is_empty(),
		"native SubViewport tooltips cannot cover the terminal with blank panels"
	)
	_expect(
		scanner_card != null
		and scanner_card.has_meta(WristTerminalView.HOVER_HINT_META),
		"the home hero exposes the device scanner as a self-explaining service card"
	)
	scanner_button.pressed.emit()
	_expect(
		view.current_page == WristTerminalView.PAGE_SCANNER
		and view.scanner_page.visible
		and not view.home_page.visible,
		"the top bar opens the dedicated scanner page"
	)
	view.set_scanner_contacts([{
		"contact_id": &"test:radio",
		"display_name": "Portable Radio",
		"device_class": &"AUDIO",
		"status_text": "TRANSMITTING",
		"world_offset": Vector3(0.0, 0.5, -8.0),
		"relative_position": Vector3(0.0, 0.5, -8.0),
		"distance_meters": 8.0,
		"signal_strength": 1.0,
	}], 36.0)
	view.scanner.call("set_sweep_angle", 0.0)
	view.scanner.call("_process", 1.0 / 60.0)
	_expect(
		view.scanner_count_label.text.contains("01")
		and view.scanner_name_label.text == "PORTABLE RADIO"
		and view.scanner_class_label.text.contains("AUDIO")
		and view.scanner_distance_label.text.contains("8.0")
		and view.scanner_status_label.text == "TRANSMITTING",
		"a sweep crossing a replicated contact reveals its identity and live status"
	)
	home_button.pressed.emit()
	_expect(
		view.current_page == WristTerminalView.PAGE_HOME
		and view.home_page.visible,
		"home navigation returns to the service hero"
	)
	var scanner_preview := view.find_child(
		"ScannerPreview",
		true,
		false
	) as WristDeviceScanner
	var full_scanner := view.scanner as WristDeviceScanner
	view.set_scanner_heading(0.0)
	var scanner_center := full_scanner.size * 0.5
	var north_point := full_scanner.get_cardinal_screen_point(&"N")
	var east_point := full_scanner.get_cardinal_screen_point(&"E")
	var south_point := full_scanner.get_cardinal_screen_point(&"S")
	var west_point := full_scanner.get_cardinal_screen_point(&"W")
	_expect(
		north_point.y < scanner_center.y
		and east_point.x > scanner_center.x
		and south_point.y > scanner_center.y
		and west_point.x < scanner_center.x,
		"scanner cardinal marks use world north, east, south, and west at zero yaw"
	)
	var contact_before_turn := full_scanner.get_contact_screen_point(&"test:radio")
	view.set_scanner_heading(-PI * 0.5)
	var contact_after_turn := full_scanner.get_contact_screen_point(&"test:radio")
	_expect(
		full_scanner.get_cardinal_screen_point(&"E").y < scanner_center.y
		and full_scanner.get_cardinal_screen_point(&"N").x < scanner_center.x
		and contact_before_turn.y < scanner_center.y
		and contact_after_turn.x < scanner_center.x,
		"compass and world-space returns rotate together when the player turns east"
	)
	_expect(
		scanner_preview != null
		and is_equal_approx(scanner_preview.heading_yaw, full_scanner.heading_yaw)
		and scanner_preview.get_cardinal_screen_point(&"E").y
		< scanner_preview.size.y * 0.5,
		"home preview and opened scanner receive the same live compass heading"
	)
	# The return-memory assertion below deliberately sweeps across forward/north.
	view.set_scanner_heading(0.0)
	var full_return_age := float(
		full_scanner.ping_ages.get(&"test:radio", INF)
	)
	_expect(
		scanner_preview != null
		and float(scanner_preview.ping_ages.get(&"test:radio", INF))
		== full_return_age,
		"returns discovered in the full scanner carry into its home preview"
	)
	if scanner_preview != null and full_scanner != null:
		full_scanner.ping_ages[&"test:radio"] = INF
		scanner_preview.set_sweep_angle(0.0)
		scanner_preview._process(1.0 / 60.0)
		view.show_scanner_page()
	_expect(
		scanner_preview != null
		and scanner_preview.contacts.size() == 1
		and float(full_scanner.ping_ages.get(&"test:radio", INF)) < INF
		and scanner_preview.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"preview discoveries carry into the full scanner without stealing the card click"
	)
	view.set_session_info("OFFLINE", false)
	_expect(
		invite != null
		and not invite.disabled
		and str(invite.get_meta(
			WristTerminalView.HOVER_HINT_META,
			""
		)).contains("unavailable"),
		"unavailable invites retain hover and click feedback"
	)
	view.call("_show_button_hover_hint", invite)
	_expect(
		view.hint_label.text.contains("unavailable"),
		"the in-screen hint line replaces native tooltip popups"
	)
	var sound_requests := [0, 0]
	view.hover_sound_requested.connect(func() -> void: sound_requests[0] += 1)
	view.click_sound_requested.connect(func() -> void: sound_requests[1] += 1)
	view.call("_show_button_hover_hint", invite)
	invite.pressed.emit()
	_expect(
		sound_requests == [1, 1],
		"hover and press gestures request distinct terminal cues"
	)
	_expect(
		view.feedback_message.contains("RMB")
		and view.feedback_message.contains("LOOK")
		and view.feedback_message.contains("TAB")
		and view.feedback_message.contains("CLOSE"),
		"the visible Fieldlink hint teaches its look clutch and nearby toggle key"
	)
	view.free()


func _test_device_contact_contract() -> void:
	var radio := load(
		"res://resources/items/radios/portable_radio.tres"
	) as ItemDefinition
	_expect(
		radio != null
		and radio.fieldlink_detectable
		and radio.fieldlink_device_class == &"AUDIO"
		and radio.fieldlink_control_type == &"radio",
		"portable technical items opt into the generic Fieldlink contact contract"
	)
	var beacon := DEVICE_BEACON.new() as Node3D
	beacon.set("contact_id", &"test:fabricator")
	beacon.set("display_name", "TEST FABRICATOR")
	beacon.set("device_class", &"FABRICATOR")
	beacon.position = Vector3(3.0, 1.0, -4.0)
	root.add_child(beacon)
	var client := root.get_node_or_null("Client")
	var contacts_value: Variant = client.call(
		"collect_nearby_fieldlink_devices",
		Vector3.ZERO,
		0.0,
		10.0
	)
	var contacts: Array = contacts_value if contacts_value is Array else []
	var found_beacon := false
	for contact_value: Variant in contacts:
		if (
			contact_value is Dictionary
			and (contact_value as Dictionary).get("contact_id", &"")
			== &"test:fabricator"
		):
			var contact := contact_value as Dictionary
			found_beacon = (
				is_equal_approx(
					float(contact.get("distance_meters", 0.0)),
					sqrt(26.0)
				)
				and contact.get("relative_position", Vector3.ZERO)
				== Vector3(3.0, 1.0, -4.0)
				and contact.get("world_offset", Vector3.ZERO)
				== Vector3(3.0, 1.0, -4.0)
			)
	_expect(
		found_beacon,
		"the client scanner derives range and player-relative bearing from replicated device transforms"
	)
	var out_of_range: Array = client.call(
		"collect_nearby_fieldlink_devices",
		Vector3.ZERO,
		0.0,
		4.0
	)
	var excluded_beacon := true
	for contact_value: Variant in out_of_range:
		if (
			contact_value is Dictionary
			and (contact_value as Dictionary).get("contact_id", &"")
			== &"test:fabricator"
		):
			excluded_beacon = false
	_expect(
		excluded_beacon,
		"Fieldlink excludes compatible devices beyond the scanner's bounded range"
	)
	beacon.free()
	var client_world_scene := load("res://scenes/proxy/world.tscn") as PackedScene
	var client_world := client_world_scene.instantiate() as Node3D
	root.add_child(client_world)
	var authored_contacts: Array = client.call(
		"collect_nearby_fieldlink_devices",
		Vector3(0.0, 1.0, 0.0),
		0.0,
		20.0
	)
	var authored_ids: Dictionary[StringName, bool] = {}
	for contact_value: Variant in authored_contacts:
		if contact_value is Dictionary:
			authored_ids[StringName(str(
				(contact_value as Dictionary).get("contact_id", "")
			))] = true
	_expect(
		authored_ids.has(&"station:drone_assembly")
		and authored_ids.has(&"station:drone_inspection")
		and authored_ids.has(&"station:limb_supply")
		and authored_ids.has(&"station:weapon_fabricator"),
		"the actual client world advertises every nearby technical workstation"
	)
	client_world.free()


func _test_selectable_device_controls() -> void:
	var view := WRIST_VIEW.new() as WristTerminalView
	root.add_child(view)
	view.show_scanner_page()
	var contacts: Array[Dictionary] = [{
		"contact_id": &"station:test",
		"display_name": "TEST STATION",
		"device_class": &"FABRICATOR",
		"control_type": &"",
		"status_text": "ONLINE",
		"relative_position": Vector3(-5.0, 0.0, -9.0),
		"distance_meters": 10.3,
		"signal_strength": 1.0,
	}, {
		"contact_id": &"item:42",
		"display_name": "PORTABLE RADIO",
		"device_class": &"AUDIO",
		"control_type": &"radio",
		"status_text": "STANDBY",
		"relative_position": Vector3(7.0, 0.0, -8.0),
		"distance_meters": 10.6,
		"signal_strength": 1.0,
	}]
	view.set_scanner_contacts(contacts, 36.0)
	view.scanner.ping_ages[&"station:test"] = 0.0
	view.scanner.ping_ages[&"item:42"] = 0.0
	var requested_ids: Array[StringName] = []
	view.device_control_requested.connect(
		func(contact_id: StringName) -> void: requested_ids.append(contact_id)
	)
	var station_click := InputEventMouseButton.new()
	station_click.button_index = MOUSE_BUTTON_LEFT
	station_click.pressed = true
	station_click.position = view.scanner.get_contact_screen_point(&"station:test")
	view.scanner._gui_input(station_click)
	_expect(
		view.get_selected_contact_id() == &"station:test"
		and requested_ids.is_empty()
		and view.device_placeholder_label.text.contains("IDENTITY LINK"),
		"every detected return is selectable even before it owns a control adapter"
	)
	var radio_click := InputEventMouseButton.new()
	radio_click.button_index = MOUSE_BUTTON_LEFT
	radio_click.pressed = true
	radio_click.position = view.scanner.get_contact_screen_point(&"item:42")
	view.scanner._gui_input(radio_click)
	_expect(
		view.get_selected_contact_id() == &"item:42"
		and view.get_selected_control_type() == &"radio"
		and requested_ids == [&"item:42"],
		"clicking a controllable return requests its typed snapshot by stable contact ID"
	)
	view.apply_device_control_snapshot({
		"contact_id": &"item:42",
		"control_type": &"radio",
		"display_name": "PORTABLE RADIO",
		"status_text": "PLAYING",
		"revision": 3,
		"payload": {
			"tracks": [{"track_index": 0, "display_name": "AMERIKA"}, {
				"track_index": 1,
				"display_name": "NIGHT SHIFT",
			}],
			"selected_track_index": 1,
			"current_track_index": 1,
			"playback_state": &"playing",
			"volume_ratio": 0.62,
			"elapsed_seconds": 12.0,
			"duration_seconds": 180.0,
		},
	})
	var radio_panel := view.device_control_panel as FieldlinkRadioControlPanel
	_expect(
		radio_panel != null
		and radio_panel.track_list.item_count == 2
		and radio_panel.track_list.is_selected(1)
		and radio_panel.play_pause_button.text == "PAUSE"
		and is_equal_approx(radio_panel.volume_slider.value, 62.0),
		"the radio adapter renders track selection, transport state and authoritative loudness"
	)
	var panel_hover_sound_count := [0]
	view.hover_sound_requested.connect(
		func() -> void: panel_hover_sound_count[0] += 1
	)
	radio_panel.track_list.mouse_entered.emit()
	var track_list_hover_is_silent: bool = (
		panel_hover_sound_count[0] == 0
		and view.hint_label.text.contains("LOCALLY AVAILABLE TRACK")
	)
	radio_panel.play_pause_button.mouse_entered.emit()
	_expect(
		track_list_hover_is_silent and panel_hover_sound_count[0] == 1,
		"the track-list surface keeps its hint without playing a hover cue; discrete controls retain feedback"
	)
	_expect(
		is_equal_approx(ServerPlayer.WRIST_SOUND_OUTPUT_GAIN_DB, -5.0),
		"all authoritative PBD cues share a restrained five-decibel output reduction"
	)
	var commands: Array[Dictionary] = []
	view.device_command_requested.connect(func(
		contact_id: StringName,
		action: StringName,
		payload: Dictionary
	) -> void:
		commands.append({
			"contact_id": contact_id,
			"action": action,
			"payload": payload,
		})
	)
	radio_panel.play_pause_button.pressed.emit()
	radio_panel.stop_button.pressed.emit()
	radio_panel.volume_slider.value = 41.0
	radio_panel.call("_commit_volume")
	var all_commands_target_radio := true
	for command: Dictionary in commands:
		if command.get("contact_id") != &"item:42":
			all_commands_target_radio = false
	_expect(
		commands.size() == 3
		and commands[0].get("action") == &"pause"
		and commands[1].get("action") == &"stop"
		and commands[2].get("action") == &"set_volume"
		and all_commands_target_radio,
		"radio widgets emit generic typed commands without coupling scanner geometry to playback"
	)
	view.free()


func _test_first_person_presentation() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var presentation := (
		WRIST_PRESENTATION_SCENE.instantiate()
		as WristTerminalPresentation
	)
	camera.add_child(presentation)
	_expect(
		presentation.has_node(
			"DeviceMount/CorporateFieldTerminalVisual/TechScreenHousing/"
			+ "screen_etx_1_partial/"
			+ "screen_etx_1_partial_round_screen"
		),
		"first-person presentation targets the asset's actual curved screen"
	)
	_expect(
		presentation.terminal_screen.mesh is ArrayMesh
		and not presentation.terminal_screen.mesh is QuadMesh,
		"the rendered Fieldlink display is the imported screen mesh, not a plane"
	)
	_expect(
		presentation.terminal_input_surface.mesh is QuadMesh
		and not presentation.terminal_input_surface.visible
		and presentation.terminal_input_surface.cast_shadow
		== GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"only an invisible non-shadowing plane remains for stable pointer input"
	)
	_expect(
		presentation.terminal_viewport == null,
		"the interactive render target allocates lazily"
	)
	_expect(
		presentation.find_children(
			"*",
			"AudioStreamPlayer",
			true,
			false
		).is_empty()
		and presentation.find_children(
			"*",
			"AudioStreamPlayer3D",
			true,
			false
		).is_empty(),
		"Fieldlink owns no local player that can bypass shared spatial audio"
	)
	presentation.set_session_info("CREW  /  2 OF 4", true)
	presentation.set_wrist_side(false)
	_expect(
		presentation.forearm.position.x > 0.0
		and presentation.hand.position.x < 0.0,
		"the presentation mirrors its arm geometry when only the right arm survives"
	)
	var backplate := presentation.get_node(
		"DeviceMount/CorporateFieldTerminalVisual/Backplate"
	) as MeshInstance3D
	var device_rear_z := _minimum_relative_z(backplate, presentation)
	_expect(
		_maximum_relative_z(presentation.forearm, presentation)
		< device_rear_z
		and _maximum_relative_z(presentation.hand, presentation)
		< device_rear_z,
		"forearm and hand remain behind the Fieldlink mounting plate"
	)
	_expect(
		not presentation.has_node("Cuff"),
		"the first-person rig contains no cuff box that can cover the display"
	)
	var device_sound_ids: Array[StringName] = []
	presentation.device_sound_requested.connect(
		func(sound_id: StringName) -> void:
			device_sound_ids.append(sound_id)
	)
	presentation.set_open(true)
	_expect(
		presentation.terminal_viewport != null
		and presentation.terminal_view != null,
		"opening the wrist terminal creates its interactive viewport"
	)
	var pointer_motion := InputEventMouseMotion.new()
	pointer_motion.relative = Vector2(-5000.0, 5000.0)
	_expect(
		presentation.forward_pointer_input(pointer_motion)
		and presentation.pointer_position.is_equal_approx(Vector2(
			WristTerminalPresentation.POINTER_EDGE_INSET,
			float(WristTerminalPresentation.SCREEN_VIEWPORT_SIZE.y)
			- WristTerminalPresentation.POINTER_EDGE_INSET
		))
		and presentation.terminal_view.pointer_position.is_equal_approx(
			presentation.pointer_position
		)
		and presentation.terminal_view.pointer_visible,
		"captured PBD pointer uses the shared ring and remains inside every display edge"
	)
	presentation.call("_process", 1.0)
	var input_bounds := presentation.terminal_input_surface.get_aabb()
	var input_center_z := input_bounds.get_center().z
	var local_input_samples: Array[Vector3] = [
		Vector3(input_bounds.position.x, input_bounds.end.y, input_center_z),
		Vector3(input_bounds.get_center().x, input_bounds.get_center().y, input_center_z),
		Vector3(input_bounds.end.x, input_bounds.position.y, input_center_z),
	]
	var expected_ui_samples: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(WristTerminalPresentation.SCREEN_VIEWPORT_SIZE) * 0.5,
		Vector2(WristTerminalPresentation.SCREEN_VIEWPORT_SIZE),
	]
	var input_mapping_is_exact := true
	for sample_index: int in range(local_input_samples.size()):
		var world_sample := presentation.terminal_input_surface.to_global(
			local_input_samples[sample_index]
		)
		var screen_sample := camera.unproject_position(world_sample)
		var mapped_sample: Vector2 = presentation.call(
			"_pointer_to_terminal_position",
			screen_sample
		)
		if mapped_sample.distance_to(expected_ui_samples[sample_index]) > 0.75:
			input_mapping_is_exact = false
	_expect(
		input_mapping_is_exact,
		"ray-picked plane coordinates align the rotated physical screen with exact UI texels"
	)
	var idle_position_a := presentation.position
	for _frame_index: int in range(60):
		presentation.call("_process", 1.0 / 60.0)
	var idle_position_b := presentation.position
	_expect(
		idle_position_a.distance_to(WristTerminalPresentation.OPEN_POSITION) > 0.0001
		and idle_position_b.distance_to(WristTerminalPresentation.OPEN_POSITION) > 0.0001
		and idle_position_a.distance_to(idle_position_b) > 0.0001
		and idle_position_b.distance_to(WristTerminalPresentation.OPEN_POSITION) < 0.006,
		"an open Fieldlink retains restrained heavy-arm hold motion while the player stands still"
	)
	presentation.set_motion_input(Vector3(0.02, -0.04, 0.0), 1.0)
	for _frame_index: int in range(60):
		presentation.call("_process", 1.0 / 60.0)
	var walking_position := presentation.position
	_expect(
		walking_position.x > WristTerminalPresentation.OPEN_POSITION.x + 0.003
		and walking_position.y < WristTerminalPresentation.OPEN_POSITION.y - 0.007
		and walking_position.distance_to(WristTerminalPresentation.OPEN_POSITION) < 0.018,
		"Fieldlink inherits a visible but bounded fraction of the shared gait bob"
	)
	var moving_input_mapping_is_exact := true
	for sample_index: int in range(local_input_samples.size()):
		var world_sample := presentation.terminal_input_surface.to_global(
			local_input_samples[sample_index]
		)
		var mapped_sample: Vector2 = presentation.call(
			"_pointer_to_terminal_position",
			camera.unproject_position(world_sample)
		)
		if mapped_sample.distance_to(expected_ui_samples[sample_index]) > 0.75:
			moving_input_mapping_is_exact = false
	_expect(
		moving_input_mapping_is_exact,
		"live PBD bob moves the screen and invisible input surface as one exact transform"
	)
	presentation.terminal_view.hover_sound_requested.emit()
	presentation.terminal_view.click_sound_requested.emit()
	_expect(
		device_sound_ids == [
			&"fieldlink_hover",
			&"fieldlink_click",
		],
		"the live viewport forwards semantic hover and click events for server audio"
	)
	_expect(
		presentation.terminal_screen.material_override is ShaderMaterial,
		"the device screen receives the scanner-family CRT material"
	)
	var screen_material := (
		presentation.terminal_screen.material_override as ShaderMaterial
	)
	_expect(
		screen_material.get_shader_parameter("terminal_uv_rect")
		== WristTerminalPresentation.SCREEN_ASSET_UV_RECT
		and is_equal_approx(
			float(screen_material.get_shader_parameter("curvature")),
			WristTerminalPresentation.SCREEN_CURVATURE_COMPENSATION
		),
		"the live UI fills the atlas and mildly counters the physical screen bow"
	)
	_expect(
		is_equal_approx(
			float(screen_material.get_shader_parameter("glitch_strength")),
			WristTerminalPresentation.SCREEN_GLITCH_STRENGTH
		)
		and is_equal_approx(
			float(screen_material.get_shader_parameter("glitch_event_chance")),
			WristTerminalPresentation.SCREEN_GLITCH_EVENT_CHANCE
		)
		and is_equal_approx(
			float(screen_material.get_shader_parameter("glitch_chroma_strength")),
			WristTerminalPresentation.SCREEN_GLITCH_CHROMA_STRENGTH
		)
		and is_equal_approx(
			float(screen_material.get_shader_parameter("acoustic_glitch_drive")),
			0.0
		)
		and float(screen_material.get_shader_parameter("glitch_luma_flutter"))
		> 0.0
		and float(screen_material.get_shader_parameter("glitch_luma_flutter"))
		< 0.1
		and float(screen_material.get_shader_parameter("acoustic_glitch_event_lift"))
		> 0.2,
		"the curved display keeps one restrained intermittent band-sync glitch"
	)
	_expect(
		not WristTerminalPresentation.TERMINAL_SHADER.code.contains("pixel_glitch")
		and not WristTerminalPresentation.TERMINAL_SHADER.code.contains(
			"glitch_pixel_chance"
		),
		"heard audio does not create a separate random pixel-replacement effect"
	)
	presentation.set_acoustic_intensity(0.1)
	for _frame_index: int in range(30):
		presentation.call("_process", 1.0 / 60.0)
	var ordinary_screen_drive := float(
		screen_material.get_shader_parameter("acoustic_glitch_drive")
	)
	presentation.set_acoustic_intensity(1.0)
	for _frame_index: int in range(30):
		presentation.call("_process", 1.0 / 60.0)
	var loud_screen_drive := float(
		screen_material.get_shader_parameter("acoustic_glitch_drive")
	)
	presentation.set_acoustic_intensity(0.0)
	for _frame_index: int in range(60):
		presentation.call("_process", 1.0 / 60.0)
	var recovered_screen_drive := float(
		screen_material.get_shader_parameter("acoustic_glitch_drive")
	)
	_expect(
		ordinary_screen_drive > 0.15
		and ordinary_screen_drive < 0.4
		and loud_screen_drive > 0.99
		and recovered_screen_drive < 0.01,
		"post-propagation heard audio raises the original glitch rate with a quick attack and calm release"
	)
	var idle_event_chance := WristTerminalPresentation.SCREEN_GLITCH_EVENT_CHANCE
	var ordinary_event_chance := idle_event_chance + (
		WristTerminalPresentation.SCREEN_ACOUSTIC_GLITCH_EVENT_LIFT
		* ordinary_screen_drive
	)
	var loud_event_chance := idle_event_chance + (
		WristTerminalPresentation.SCREEN_ACOUSTIC_GLITCH_EVENT_LIFT
		* loud_screen_drive
	)
	_expect(
		ordinary_event_chance > idle_event_chance * 2.5
		and loud_event_chance > ordinary_event_chance * 2.5,
		"audio changes rare-glitch event frequency rather than replacing pixels or scaling its geometry"
	)
	var refresh_min_speed := float(
		screen_material.get_shader_parameter("refresh_line_min_speed")
	)
	var refresh_max_speed := float(
		screen_material.get_shader_parameter("refresh_line_max_speed")
	)
	var refresh_opacity := float(
		screen_material.get_shader_parameter("refresh_line_opacity")
	)
	var refresh_distortion_min := float(
		screen_material.get_shader_parameter(
			"refresh_line_distortion_min"
		)
	)
	var refresh_distortion_max := float(
		screen_material.get_shader_parameter(
			"refresh_line_distortion_max"
		)
	)
	var phosphor_decay := float(
		screen_material.get_shader_parameter("phosphor_decay_per_second")
	)
	var phosphor_floor := float(
		screen_material.get_shader_parameter("phosphor_brightness_floor")
	)
	_expect(
		refresh_min_speed > 0.0
		and refresh_max_speed > refresh_min_speed
		and refresh_max_speed <= 0.18
		and refresh_opacity > 0.0
		and refresh_opacity < 0.2
		and refresh_distortion_min > 0.0
		and refresh_distortion_max > refresh_distortion_min
		and refresh_distortion_max < 0.01,
		"refresh tears choose nonzero strengths within a restrained range"
	)
	var point_count := float(
		screen_material.get_shader_parameter("refresh_line_point_count")
	)
	var point_min_strength := float(
		screen_material.get_shader_parameter(
			"refresh_line_point_min_strength"
		)
	)
	var point_max_strength := float(
		screen_material.get_shader_parameter(
			"refresh_line_point_max_strength"
		)
	)
	_expect(
		point_count >= 8.0
		and point_max_strength > point_min_strength
		and point_min_strength > 0.0,
		"each sweep varies smoothly across randomized horizontal strength points"
	)
	var refresh_start_time := float(
		screen_material.get_shader_parameter("refresh_start_time")
	)
	_expect(
		refresh_start_time >= 0.0
		and refresh_start_time
		< WristTerminalPresentation.SHADER_TIME_ROLLOVER_SECONDS,
		"opening Fieldlink starts every refresh line from the terminal top"
	)
	_expect(
		phosphor_decay > 0.0
		and phosphor_floor > 0.0
		and phosphor_floor < 1.0,
		"colored pixels use exponential decay with a readable persistence floor"
	)
	_expect(
		WristTerminalPresentation.OPEN_POSITION.z > -0.5,
		"the open Fieldlink sits closely enough to read without clipping the camera"
	)
	var grit_strength := float(
		screen_material.get_shader_parameter("grit_strength")
	)
	var grit_speck_chance := float(
		screen_material.get_shader_parameter("grit_speck_chance")
	)
	var grit_age_influence := float(
		screen_material.get_shader_parameter("grit_age_influence")
	)
	_expect(
		grit_strength > 0.0
		and grit_strength < 0.05
		and grit_speck_chance > 0.0
		and grit_speck_chance < 0.03
		and grit_age_influence > 0.0
		and grit_age_influence <= 1.0,
		"gritty pixels become more active as their last refresh ages"
	)
	var neon_strength := float(
		screen_material.get_shader_parameter("neon_glow_strength")
	)
	var color_bleed := float(
		screen_material.get_shader_parameter("color_bleed_strength")
	)
	_expect(
		neon_strength > 0.0
		and neon_strength < 0.2
		and color_bleed > 0.0
		and color_bleed < 0.2,
		"subtle neighbor glow and channel bleed dirty the terminal colors"
	)
	presentation.set_feedback("INVITES ARE NOT AVAILABLE", true)
	presentation.set_feedback("STEAM INVITE OVERLAY OPENED")
	_expect(
		device_sound_ids == [
			&"fieldlink_hover",
			&"fieldlink_click",
			&"fieldlink_warning",
			&"fieldlink_confirm",
		],
		"terminal outcomes request distinct server-routed warning and confirmation cues"
	)
	presentation.terminal_view.show_scanner_page()
	presentation.set_open(false)
	presentation.set_open(true)
	_expect(
		presentation.terminal_view.current_page == WristTerminalView.PAGE_SCANNER,
		"putting Fieldlink away preserves the page and device-console state for its next opening"
	)
	presentation.set_open(false)
	_expect(
		device_sound_ids.size() == 4,
		"predicted presentation does not double-play authoritative open and close cues"
	)
	camera.free()


func _test_held_device_motion() -> void:
	var rest_position := HELD_DEVICE_MOTION.hold_position_at_time(0.47, 0.0)
	var moving_position := HELD_DEVICE_MOTION.hold_position_at_time(0.47, 1.0)
	var rest_rotation := HELD_DEVICE_MOTION.hold_rotation_at_time(0.47, 0.0)
	var exhausted_position := HELD_DEVICE_MOTION.hold_position_at_time(
		0.47,
		0.0,
		1.0
	)
	var exhausted_rotation := HELD_DEVICE_MOTION.hold_rotation_at_time(
		0.47,
		0.0,
		1.0
	)
	_expect(
		rest_position.is_finite()
		and rest_rotation.is_finite()
		and rest_position.length() > 0.0005
		and rest_position.length() < 0.004
		and rest_rotation.length() > 0.001
		and rest_rotation.length() < 0.008
		and moving_position.is_equal_approx(
			rest_position * HELD_DEVICE_MOTION.MOVING_HOLD_SWAY_RATIO
		)
		and exhausted_position.distance_to(rest_position) > 0.001
		and exhausted_rotation.distance_to(rest_rotation) > 0.004,
		"procedural hold sway is sub-centimetre, load-like, deterministic, and reduced during gait"
	)
	_expect(
		is_zero_approx(
			HELD_DEVICE_MOTION.fatigue_from_endurance_spent_ratio(0.0)
		)
		and HELD_DEVICE_MOTION.fatigue_from_endurance_spent_ratio(0.5) > 0.3
		and HELD_DEVICE_MOTION.fatigue_from_endurance_spent_ratio(0.9) > 0.99,
		"missing END drives a nonlinear fatigue response from rested to exhausted"
	)
	var walk_shoulder_position := HELD_DEVICE_MOTION.shoulder_position_at_cycle(
		0.5,
		1.0,
		0.0
	)
	var run_shoulder_position := HELD_DEVICE_MOTION.shoulder_position_at_cycle(
		0.5,
		1.0,
		1.0
	)
	var run_shoulder_rotation := HELD_DEVICE_MOTION.shoulder_rotation_at_cycle(
		0.5,
		1.0,
		1.0
	)
	var fatigued_run_rotation := HELD_DEVICE_MOTION.shoulder_rotation_at_cycle(
		0.5,
		1.0,
		1.0,
		1.0
	)
	_expect(
		walk_shoulder_position.is_finite()
		and run_shoulder_position.length() > walk_shoulder_position.length() * 2.0
		and run_shoulder_rotation.length() > 0.035
		and run_shoulder_rotation.length() < 0.075
		and fatigued_run_rotation.distance_to(run_shoulder_rotation) > 0.015
		and HELD_DEVICE_MOTION.shoulder_position_at_cycle(
			0.5,
			0.0,
			1.0,
			1.0
		).is_zero_approx(),
		"running drives a bounded phase-locked shoulder wave and fatigue adds a lagged load response"
	)
	var motion := HELD_DEVICE_MOTION.new()
	motion.set_gait_input(Vector3(0.02, -0.04, 0.0), 1.0, 0.5, 1.0)
	for _frame_index: int in range(120):
		motion.advance(1.0 / 60.0)
	_expect(
		motion.position_offset.is_finite()
		and motion.rotation_offset.is_finite()
		and motion.position_offset.x > 0.012
		and motion.position_offset.y < -0.005
		and motion.position_offset.length() < 0.030
		and motion.rotation_offset.length() > 0.035
		and motion.rotation_offset.length() < 0.080,
		"critically damped arm inertia follows the running shoulder without overshoot or an unbounded transform"
	)
	var fatigued_motion := HELD_DEVICE_MOTION.new()
	fatigued_motion.set_gait_input(Vector3.ZERO, 1.0, 0.5, 1.0)
	fatigued_motion.set_endurance_spent_ratio(0.9)
	for _frame_index: int in range(120):
		fatigued_motion.advance(1.0 / 60.0)
	var peak_fatigue := fatigued_motion.fatigue_weight
	fatigued_motion.set_endurance_spent_ratio(0.0)
	for _frame_index: int in range(120):
		fatigued_motion.advance(1.0 / 60.0)
	var rested_motion := HELD_DEVICE_MOTION.new()
	rested_motion.set_gait_input(Vector3.ZERO, 1.0, 0.5, 1.0)
	for _frame_index: int in range(240):
		rested_motion.advance(1.0 / 60.0)
	_expect(
		peak_fatigue > 0.99
		and fatigued_motion.fatigue_weight < 0.02
		and fatigued_motion.position_offset.distance_to(
			rested_motion.position_offset
		) < 0.001
		and fatigued_motion.rotation_offset.distance_to(
			rested_motion.rotation_offset
		) < 0.003,
		"END regeneration smoothly removes the fatigued shoulder lag and returns to the rested gait"
	)


func _test_client_input_contract() -> void:
	var proxy_source := FileAccess.get_file_as_string(
		"res://scripts/client/player_proxy.gd"
	)
	var client_source := FileAccess.get_file_as_string(
		"res://scripts/client/client.gd"
	)
	var server_source := FileAccess.get_file_as_string(
		"res://scripts/server/server.gd"
	)
	var server_player_source := FileAccess.get_file_as_string(
		"res://scripts/server/server_player.gd"
	)
	var wrist_packet := FIELDLINK_DISPLAY_STATE.make_replication_packet(
		7,
		true,
		&"scanner"
	)
	_expect(
		FIELDLINK_DISPLAY_STATE.sanitize_replication_packet(wrist_packet)
		== wrist_packet
		and FIELDLINK_DISPLAY_STATE.sanitize_replication_packet({}).is_empty(),
		"wrist replication uses one validated packet instead of a signature-fragile RPC argument list"
	)
	_expect(
		InputMap.has_action("toggle_fieldlink")
		and _action_has_physical_key("toggle_fieldlink", KEY_TAB),
		"Tab is the dedicated, rebindable Fieldlink action"
	)
	_expect(
		proxy_source.contains('is_action_pressed("toggle_fieldlink")')
		and proxy_source.contains("toggle_wrist_interface()")
		and proxy_source.contains("WRIST_LOOK_PITCH"),
		"Tab toggles the wrist view and blends the camera toward the arm"
	)
	_expect(
		client_source.contains("func on_player_wrist_state_received(")
		and server_source.contains(
			'Client.rpc(\n\t\t\t"on_player_wrist_state_received"'
		)
		and server_player_source.contains(
			'"wrist_interface_open": wrist_interface_open'
		)
		and server_player_source.contains(
			'"wrist_display_page": wrist_display_page'
		),
		"Tab and visible display-page edges broadcast reliably while snapshots retain recovery state"
	)
	_expect(
		proxy_source.contains('is_action_pressed("ui_cancel")')
		and proxy_source.contains("close_wrist_interface()"),
		"Escape can close an open Fieldlink without being its primary toggle"
	)
	_expect(
		proxy_source.contains("MOUSE_BUTTON_RIGHT")
		and proxy_source.contains("_set_wrist_mouse_look_active(")
		and proxy_source.contains("_apply_mouse_look(event.relative)"),
		"the open Fieldlink reserves RMB as a press-and-hold mouse-look clutch"
	)
	_expect(
		client_source.contains("_suspend_gameplay_input(")
		and client_source.contains('"release_grab"')
		and client_source.contains('"set_primary_action_held"'),
		"opening Fieldlink releases grab/fire state instead of leaking gameplay input"
	)
	_expect(
		client_source.contains("_send_movement_input(yaw, pitch, local_proxy)")
		and client_source.contains("_process_locomotion_action_input(local_proxy)")
		and not server_player_source.contains(
			"func request_jump() -> void:\n\tif wrist_interface_open:"
		),
		"Fieldlink captures technical actions without suppressing movement, sprint or jump input"
	)
	var server_player_scene := load(
		"res://scenes/server/server_player.tscn"
	) as PackedScene
	var movement_player := server_player_scene.instantiate() as ServerPlayer
	root.add_child(movement_player)
	movement_player.set_wrist_interface_open(true)
	movement_player.set_input(Vector2(0.8, -0.4), 0.3, -0.2, true)
	movement_player.request_jump()
	_expect(
		movement_player.wrist_interface_open
		and movement_player.move_input.is_equal_approx(Vector2(0.8, -0.4))
		and movement_player.wants_run
		and movement_player.wants_jump,
		"the authoritative player preserves full locomotion while looking at Fieldlink"
	)
	movement_player.set_wrist_display_page(&"scanner")
	var replicated_wrist_state := movement_player.to_state_dict()
	_expect(
		replicated_wrist_state.get("wrist_interface_open") == true
		and replicated_wrist_state.get("wrist_display_page") == &"scanner",
		"late-join player snapshots retain the visible Fieldlink pose and page"
	)
	movement_player.free()
	_expect(
		proxy_source.contains("device_sound_requested.connect(")
		and client_source.contains("request_wrist_device_sound")
		and server_source.contains("func request_wrist_device_sound(")
		and server_player_source.contains("emit_spatial_sound"),
		"Fieldlink UI cues cross the validated server spatial-audio route"
	)


func _test_local_body_arm_isolation() -> void:
	var proxy := PLAYER_PROXY_SCENE.instantiate() as PlayerProxy
	root.add_child(proxy)
	proxy.set_local_player(true)
	_expect(
		not proxy.open_wrist_interface(),
		"technical interfaces cannot summon a Fieldlink the player has lost"
	)
	proxy.equipment_definition_paths[
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	] = WRIST_DEVICE_PATH
	_expect(
		proxy.open_wrist_interface(),
		"technical interfaces can open the equipped Fieldlink through its public API"
	)
	proxy.wrist_pose_weight = 1.0
	proxy.camera_pivot.rotation.x = PlayerProxy.WRIST_LOOK_PITCH
	var look_before := Vector2(proxy.look_yaw, proxy.look_pitch)
	proxy.captured_mouse_motion_discard_remaining = 0
	proxy.call("_set_wrist_mouse_look_active", true)
	var clutch_keeps_capture_continuous := (
		proxy.captured_mouse_motion_discard_remaining == 0
	)
	var pitch_at_clutch := proxy.look_pitch
	proxy.call("_apply_mouse_look", Vector2(0.0, -12.0))
	var looked_up_pitch := proxy.look_pitch
	_expect(
		proxy.wrist_mouse_look_active
		and clutch_keeps_capture_continuous
		and is_equal_approx(pitch_at_clutch, PlayerProxy.WRIST_LOOK_PITCH)
		and looked_up_pitch > pitch_at_clutch
		and is_equal_approx(
			float(proxy.call("_resolved_camera_pitch")),
			looked_up_pitch
		)
		and is_equal_approx(proxy.look_yaw, look_before.x),
		"holding RMB exposes vertical Fieldlink mouse look without a capture transition"
	)
	proxy.call("_set_wrist_mouse_look_active", false)
	_expect(
		not proxy.wrist_mouse_look_active
		and is_equal_approx(
			float(proxy.call("_resolved_camera_pitch")),
			looked_up_pitch
		),
		"releasing RMB returns pointer interaction without hiding its camera pitch"
	)
	proxy.wrist_pose_weight = 0.0
	proxy.call("_update_wrist_pose", 1.0)
	_expect(
		is_zero_approx(proxy.left_arm_visual.rotation.x)
		and is_zero_approx(proxy.left_arm_visual.rotation.z)
		and is_zero_approx(proxy.right_arm_visual.rotation.x)
		and is_zero_approx(proxy.right_arm_visual.rotation.z),
		"the owner's replicated body arms cannot pierce the camera-mounted screen"
	)
	var look_before_close := Vector2(proxy.look_yaw, proxy.look_pitch)
	proxy.close_wrist_interface()
	_expect(
		Vector2(proxy.look_yaw, proxy.look_pitch).is_equal_approx(
			look_before_close
		)
		and proxy.captured_mouse_motion_discard_remaining == 0
		and is_equal_approx(
			float(proxy.call("_resolved_camera_pitch")),
			looked_up_pitch
		),
		"closing Fieldlink needs no recapture and reveals no hidden pitch"
	)
	proxy.set_local_player(false)
	# The local-use portion above installs only the capability marker; force the
	# ordinary replicated equipment path to construct the third-person visual.
	proxy.equipment_definition_paths.clear()
	proxy.call("_apply_equipment_state", {
		PlayerInventoryRules.WRIST_DEVICE_SLOT: {
			"definition_path": WRIST_DEVICE_PATH,
		},
	})
	proxy.target_wrist_interface_open = true
	proxy.wrist_pose_weight = 0.0
	proxy.call("_update_wrist_pose", 1.0)
	proxy.call("_update_character_pose", 1.0)
	proxy.apply_replicated_wrist_state(true, &"scanner")
	var wrist_visual := proxy.equipment_visuals.get(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	) as Node3D
	var remote_screen := wrist_visual.find_child(
		"screen_etx_1_partial_round_screen",
		true,
		false
	) as MeshInstance3D
	var remote_display := proxy.remote_wrist_display
	var body_visual := proxy.get_node("BodyVisual") as Node3D
	var torso_space_screen: Vector3 = body_visual.to_local(
		remote_screen.global_position
	)
	var remote_backplate := wrist_visual.find_child(
		"Backplate",
		true,
		false
	) as MeshInstance3D
	var remote_device_rear_z := _maximum_relative_z(
		remote_backplate,
		body_visual
	)
	var remote_viewport := remote_display.get("terminal_viewport") as SubViewport
	var remote_view := remote_display.get("terminal_view") as WristTerminalView
	_expect(
		proxy.left_arm_visual.rotation.x > 0.0
		and not is_zero_approx(proxy.left_arm_visual.rotation.z)
		and torso_space_screen.z < -0.2
		and remote_device_rear_z < -0.2,
		"the remote arm raises its equipped Fieldlink forward of the torso"
	)
	_expect(
		remote_display != null
		and bool(remote_display.get("open"))
		and remote_display.is_processing()
		and remote_viewport.render_target_update_mode
		== SubViewport.UPDATE_ONCE
		and remote_view.current_page == &"scanner"
		and remote_screen.material_override is ShaderMaterial
		and (remote_screen.material_override as ShaderMaterial).shader
		== WristTerminalPresentation.TERMINAL_SHADER
		and remote_display.find_children(
			"*",
			"MeshInstance3D",
			true,
			false
		).is_empty(),
		"remote players render the replicated live UI on the real curved screen"
	)
	proxy.call("_apply_limb_state", {
		"left_arm": false,
		"right_arm": true,
		"left_leg": true,
		"right_leg": true,
	})
	proxy.wrist_pose_weight = 0.0
	proxy.call("_update_wrist_pose", 1.0)
	proxy.call("_update_character_pose", 1.0)
	var right_arm_device_rear_z := _maximum_relative_z(
		remote_backplate,
		body_visual
	)
	_expect(
		wrist_visual.get_parent() == proxy.right_wrist_mount
		and proxy.right_arm_visual.rotation.x > 0.0
		and not is_zero_approx(proxy.right_arm_visual.rotation.z)
		and right_arm_device_rear_z < -0.2,
		"the same forward shoulder pose works when the Fieldlink moves to the surviving right arm"
	)
	proxy.apply_replicated_wrist_state(false, &"scanner")
	_expect(
		not bool(remote_display.get("open"))
		and remote_viewport.render_target_update_mode
		== SubViewport.UPDATE_DISABLED
		and remote_screen.material_override
		== remote_display.get("original_material_override"),
		"closing the remote Fieldlink stops its viewport and restores the item screen"
	)
	proxy.free()


func _action_has_physical_key(action: StringName, key: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == key:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: " + message)


func _minimum_relative_z(mesh_node: MeshInstance3D, root_node: Node3D) -> float:
	return _relative_z_extents(mesh_node, root_node).x


func _maximum_relative_z(mesh_node: MeshInstance3D, root_node: Node3D) -> float:
	return _relative_z_extents(mesh_node, root_node).y


func _relative_z_extents(
	mesh_node: MeshInstance3D,
	root_node: Node3D
) -> Vector2:
	var bounds := mesh_node.get_aabb()
	var relative_transform := (
		root_node.global_transform.affine_inverse()
		* mesh_node.global_transform
	)
	var minimum_z := INF
	var maximum_z := -INF
	for x_index: int in range(2):
		for y_index: int in range(2):
			for z_index: int in range(2):
				var corner := Vector3(
					bounds.position.x + bounds.size.x * float(x_index),
					bounds.position.y + bounds.size.y * float(y_index),
					bounds.position.z + bounds.size.z * float(z_index)
				)
				var relative_corner := relative_transform * corner
				minimum_z = minf(minimum_z, relative_corner.z)
				maximum_z = maxf(maximum_z, relative_corner.z)
	return Vector2(minimum_z, maximum_z)
