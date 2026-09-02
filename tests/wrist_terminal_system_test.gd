extends SceneTree

const WRIST_DEVICE_PATH := (
	"res://resources/items/wrist_devices/corporate_field_terminal.tres"
)
const PLASMA_CUTTER_PATH := (
	"res://resources/items/tools/plasma_cutter_standard.tres"
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
	_test_handheld_tool_separation_contract()
	_test_selectable_device_controls()
	_test_device_contact_contract()
	_test_held_device_motion()
	_test_equipped_wrist_presentation()
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
	_expect(
		not definition.has_method("get_plasma_cutter"),
		"Fieldlink stays an interface instead of embedding a weapon module"
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
		_expect(
			world_visual.find_child("PlasmaEmitter", true, false) == null,
			"the physical Fieldlink no longer carries the handheld cutter's emitter"
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
	var mimic_button := view.find_child(
		"VoiceMimicConsent",
		true,
		false
	) as Button
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
	var requested_mimic_consent := [false]
	view.voice_mimic_consent_changed.connect(
		func(enabled: bool) -> void: requested_mimic_consent[0] = enabled
	)
	if mimic_button != null:
		mimic_button.pressed.emit()
	_expect(
		mimic_button != null
		and mimic_button.has_meta(WristTerminalView.HOVER_HINT_META)
		and str(mimic_button.get_meta(
			WristTerminalView.HOVER_HINT_META,
			""
		)).contains("Nothing is saved")
		and requested_mimic_consent[0],
		"the home page requests explicit, session-only enemy voice-memory consent"
	)
	view.set_voice_mimic_consent(true)
	_expect(
		view.voice_mimic_consent
		and mimic_button != null
		and mimic_button.text.contains("ON"),
		"only the authoritative consent acknowledgement changes the visible toggle"
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


func _test_handheld_tool_separation_contract() -> void:
	var cutter := load(PLASMA_CUTTER_PATH) as PlasmaCutterDefinition
	var generic_cutter: Resource = cutter
	var stats: Dictionary = cutter.display_stats()
	_expect(
		cutter != null
		and generic_cutter is ItemDefinition
		and not generic_cutter is EquippableItemDefinition
		and float(stats.get("range_meters", 0.0)) > 0.0
		and float(stats.get("kerf_millimeters", 0.0)) > 0.0
		and float(stats.get("continuous_duty_seconds", 1.0)) < 0.2
		and float(stats.get("full_cool_seconds", 2.0)) < 1.0,
		"the cutter is a standalone item with a finite authored operating envelope"
	)

	var view := WRIST_VIEW.new() as WristTerminalView
	root.add_child(view)
	var cutter_button := view.find_child(
		"PlasmaCutterNavigation",
		true,
		false
	) as Button
	_expect(
		cutter_button == null,
		"Fieldlink no longer exposes a hidden cutter page or weapon control"
	)
	_expect(
		FIELDLINK_DISPLAY_STATE.sanitize_page(&"plasma_cutter")
		== FIELDLINK_DISPLAY_STATE.PAGE_HOME,
		"legacy cutter page packets fail safely back to Fieldlink home"
	)
	view.free()

	var server_player_scene := load(
		"res://scenes/server/server_player.tscn"
	) as PackedScene
	var player := server_player_scene.instantiate() as ServerPlayer
	root.add_child(player)
	player.inventory_entries.append(PlayerInventoryRules.make_entry(cutter))
	player.call("_mark_inventory_changed")
	player.set_plasma_cutter_triggered(true)
	player.set_primary_action_held(true)
	_expect(
		player.plasma_cutter_active
		and player.consume_plasma_cutter_pulse(),
		"ordinary held primary action energizes the selected cutter immediately"
	)
	_expect(
		player.plasma_cutter_overheated
		and not player.plasma_cutter_active
		and not player.plasma_cutter_trigger_held
		and not player.consume_plasma_cutter_pulse(),
		"one authoritative discharge atomically overheats and stops the cutter"
	)
	for _thermal_tick: int in range(5):
		player.call("_update_plasma_cutter_thermal", 0.1)
	_expect(
		player.plasma_cutter_overheated
		and not player.plasma_cutter_active
		and not player.plasma_cutter_trigger_held,
		"the shortened cooldown still enforces a visible lockout"
	)
	for _cool_tick: int in range(4):
		player.call("_update_plasma_cutter_thermal", 0.1)
	_expect(
		not player.plasma_cutter_overheated
		and player.plasma_cutter_heat_ratio <= 0.01,
		"thermal lockout releases only after the authored recovery threshold"
	)
	var replicated_state := player.to_state_dict(false)
	_expect(
		replicated_state.get("plasma_cutter_available") == true
		and replicated_state.has("plasma_cutter_hit_position")
		and float(replicated_state.get("plasma_cutter_range_meters", 0.0)) > 0.0,
		"heat and beam endpoint remain replicated for host/client visual parity"
	)
	player.set_wrist_interface_open(true)
	_expect(
		not player.plasma_cutter_active
		and not player.set_plasma_cutter_triggered(true),
		"using Fieldlink cannot leave the separate handheld cutter energized"
	)
	player.free()

	var server_source := FileAccess.get_file_as_string(
		"res://scripts/server/server.gd"
	)
	var proxy_source := FileAccess.get_file_as_string(
		"res://scripts/client/player_proxy.gd"
	)
	_expect(
		server_source.contains("func _process_player_plasma_cutter(")
		and server_source.contains("DAMAGE_EVENT_SCRIPT.BRUSH_CAPSULE")
		and server_source.contains('"source_kind": &"plasma_cutter"')
		and proxy_source.contains('"PlasmaEmitter"')
		and not server_source.contains("func set_plasma_cutter_triggered(value: bool) -> void:"),
		"selected-tool input reaches canonical server destruction without a wrist RPC"
	)


func _test_device_contact_contract() -> void:
	var radio := load(
		"res://resources/items/radios/portable_radio.tres"
	) as ItemDefinition
	var cutter := load(PLASMA_CUTTER_PATH) as ItemDefinition
	_expect(
		radio != null
		and radio.fieldlink_detectable
		and radio.fieldlink_device_class == &"AUDIO"
		and radio.fieldlink_control_type == &"radio",
		"portable technical items opt into the generic Fieldlink contact contract"
	)
	_expect(
		cutter != null
		and cutter.fieldlink_detectable
		and cutter.fieldlink_device_class == &"CUTTING TOOL"
		and cutter.fieldlink_control_type.is_empty(),
		"loose plasma cutters use the same read-only Fieldlink scanner contract as other technical items"
	)
	var beacon := DEVICE_BEACON.new() as Node3D
	beacon.set("contact_id", &"test:fabricator")
	beacon.set("display_name", "TEST FABRICATOR")
	beacon.set("device_class", &"FABRICATOR")
	beacon.position = Vector3(3.0, 1.0, -4.0)
	root.add_child(beacon)
	var client := root.get_node_or_null("Client")
	var cutter_proxy := ItemProxy.new()
	cutter_proxy.item_id = 991
	cutter_proxy.item_definition = cutter
	cutter_proxy.position = Vector3(-2.0, 0.5, -1.0)
	root.add_child(cutter_proxy)
	var item_proxies: Dictionary = client.get("item_proxies_by_item_id")
	item_proxies[cutter_proxy.item_id] = cutter_proxy
	var contacts_value: Variant = client.call(
		"collect_nearby_fieldlink_devices",
		Vector3.ZERO,
		0.0,
		10.0
	)
	var contacts: Array = contacts_value if contacts_value is Array else []
	var found_beacon := false
	var found_cutter := false
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
		elif (
			contact_value is Dictionary
			and (contact_value as Dictionary).get("contact_id", &"") == &"item:991"
		):
			var cutter_contact := contact_value as Dictionary
			found_cutter = (
				cutter_contact.get("device_class", &"") == &"CUTTING TOOL"
				and cutter_contact.get("display_name", "")
				== "Industrial Plasma Cutter"
			)
	_expect(
		found_beacon,
		"the client scanner derives range and player-relative bearing from replicated device transforms"
	)
	_expect(
		found_cutter,
		"the real client scanner returns a nearby replicated plasma-cutter item"
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
	item_proxies.erase(cutter_proxy.item_id)
	cutter_proxy.free()
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


func _test_equipped_wrist_presentation() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	var wrist_mount := Node3D.new()
	wrist_mount.position = Vector3(-0.055, -0.105, -0.44)
	camera.add_child(wrist_mount)
	var definition := load(WRIST_DEVICE_PATH) as EquippableItemDefinition
	var equipped_visual := definition.instantiate_equipped_visual()
	equipped_visual.scale = Vector3.ONE * PlayerProxy.EQUIPPED_WRIST_DEVICE_SCALE
	wrist_mount.add_child(equipped_visual)
	var presentation := (
		WRIST_PRESENTATION_SCENE.instantiate()
		as WristTerminalPresentation
	)
	camera.add_child(presentation)
	presentation.bind_camera(camera)
	presentation.bind_equipped_visual(equipped_visual)
	presentation.bind_wrist_mount(wrist_mount)
	presentation.call("_process", 0.0)
	var equipped_screen := equipped_visual.get_node(
		"TechScreenHousing/screen_etx_1_partial/"
		+ "screen_etx_1_partial_round_screen"
	) as MeshInstance3D
	_expect(
		presentation.terminal_screen == equipped_screen,
		"the interactive controller targets the actually equipped curved screen"
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
	_expect(
		presentation.find_children("*", "MeshInstance3D", true, false).size() == 1
		and presentation.terminal_input_surface != equipped_screen,
		"the controller contains only its invisible hit surface, never a duplicate arm or PBD"
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
	var idle_transform := wrist_mount.global_transform
	for _frame_index: int in range(60):
		presentation.call("_process", 1.0 / 60.0)
	_expect(
		presentation.global_transform.is_equal_approx(
			equipped_visual.global_transform
		)
		and equipped_visual.global_position.is_equal_approx(idle_transform.origin),
		"the display and its hit controller remain on one real wrist transform while idle"
	)
	wrist_mount.position += Vector3(0.012, -0.018, 0.006)
	for _frame_index: int in range(60):
		presentation.call("_process", 1.0 / 60.0)
	_expect(
		presentation.global_transform.is_equal_approx(
			equipped_visual.global_transform
		)
		and equipped_visual.global_position.is_equal_approx(
			wrist_mount.global_position
		),
		"character movement carries the real arm, equipped PBD, and hit surface together"
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
	var right_lateral_rotation := HELD_DEVICE_MOTION.lateral_rotation_response(
		1.0,
		0.0
	)
	var left_lateral_rotation := HELD_DEVICE_MOTION.lateral_rotation_response(
		-1.0,
		0.0
	)
	var right_acceleration_position := HELD_DEVICE_MOTION.lateral_position_response(
		0.0,
		1.0
	)
	_expect(
		right_lateral_rotation.z < -0.05
		and left_lateral_rotation.z > 0.05
		and absf(right_lateral_rotation.z + left_lateral_rotation.z) < 0.0001
		and right_acceleration_position.x < -0.009
		and right_acceleration_position.y < 0.0,
		"sideways speed creates a mirrored directional roll while lateral acceleration briefly lags the heavy device"
	)
	var lateral_motion := HELD_DEVICE_MOTION.new()
	var lateral_reference := HELD_DEVICE_MOTION.new()
	lateral_motion.set_lateral_motion_ratio(0.0)
	lateral_reference.set_lateral_motion_ratio(0.0)
	for _frame_index: int in range(60):
		lateral_motion.advance(1.0 / 60.0)
		lateral_reference.advance(1.0 / 60.0)
	lateral_motion.set_lateral_motion_ratio(1.0)
	lateral_motion.advance(1.0 / 60.0)
	lateral_reference.advance(1.0 / 60.0)
	_expect(
		lateral_motion.position_offset.x
		< lateral_reference.position_offset.x - 0.0002
		and lateral_motion.rotation_offset.z
		< lateral_reference.rotation_offset.z - 0.004,
		"the reusable spring turns a new side acceleration into a small immediate inertial lag without snapping"
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
	var plasma_beam_source := FileAccess.get_file_as_string(
		"res://scripts/client/plasma_cutter_beam_3d.gd"
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
		and proxy_source.contains("_apply_mouse_look(")
		and proxy_source.contains("event.screen_relative")
		and not proxy_source.contains("is_plasma_cutter_page_active"),
		"the open Fieldlink reserves physical RMB only as press-and-hold mouse-look"
	)
	_expect(
		proxy_source.contains("var origin := camera.global_position")
		and proxy_source.contains("target_plasma_cutter_active")
		and proxy_source.contains("endpoint = target_plasma_cutter_hit_position")
		and plasma_beam_source.contains("snap_endpoint := false"),
		"the wrist beam predicts along the camera/grabber ray then snaps to authority's exact cut point"
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
		and replicated_wrist_state.get("wrist_display_page") == &"scanner"
		and is_equal_approx(
			float(replicated_wrist_state.get("look_pitch", 0.0)),
			-0.2
		),
		"late-join player snapshots retain the visible Fieldlink pose, page, and arm-facing look pitch"
	)
	movement_player.set_wrist_interface_open(false)
	movement_player.flip_active = true
	_expect(
		not movement_player.set_wrist_interface_open(true)
		and not movement_player.wrist_interface_open,
		"the server cannot raise Fieldlink through a flip already in progress"
	)
	movement_player.flip_active = false
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
	proxy.call("_apply_equipment_state", {
		PlayerInventoryRules.WRIST_DEVICE_SLOT: {
			"definition_path": WRIST_DEVICE_PATH,
		},
	})
	proxy.look_pitch = 0.0
	proxy.call("_apply_mouse_look", Vector2(0.0, 100000.0))
	_expect(
		is_equal_approx(proxy.look_pitch, PlayerProxy.MIN_WORLD_LOOK_PITCH),
		"ordinary downward look stops before the local camera can expose the inside of the neck mesh"
	)
	proxy.look_pitch = 0.0
	_expect(
		proxy.open_wrist_interface(),
		"technical interfaces can open the equipped Fieldlink through its public API"
	)
	proxy.wrist_pose_weight = 0.35
	proxy.look_pitch = deg_to_rad(35.0)
	proxy.camera_pivot.rotation.x = deg_to_rad(35.0)
	proxy.call("_set_wrist_mouse_look_active", true)
	_expect(
		proxy.wrist_mouse_look_active
		and proxy.wrist_mouse_look_owns_pitch
		and proxy.look_pitch <= PlayerProxy.WRIST_LOOK_PITCH
		and float(proxy.call("_resolved_camera_pitch"))
		<= PlayerProxy.WRIST_LOOK_PITCH,
		"RMB acquires the PBD operating pitch instead of turning a rendered camera offset into upward look"
	)
	proxy.call("_set_wrist_mouse_look_active", false)
	for _recenter_frame: int in range(12):
		proxy.call("_update_wrist_pose", 1.0 / 60.0)
	_expect(
		not proxy.wrist_mouse_look_active
		and not proxy.wrist_mouse_look_owns_pitch
		and is_zero_approx(proxy.wrist_mouse_look_blend)
		and is_equal_approx(
			float(proxy.call("_resolved_camera_pitch")),
			PlayerProxy.WRIST_LOOK_PITCH
		),
		"releasing RMB smoothly returns to the usable PBD view without closing the device"
	)
	proxy.wrist_pose_weight = 1.0
	proxy.camera_pivot.rotation.x = PlayerProxy.WRIST_LOOK_PITCH
	proxy.captured_mouse_motion_discard_remaining = 0
	proxy.call("_set_wrist_mouse_look_active", true)
	proxy.call("_apply_mouse_look", Vector2(0.0, 100000.0))
	_expect(
		is_equal_approx(proxy.look_pitch, PlayerProxy.MIN_WRIST_LOOK_PITCH)
		and is_equal_approx(
			float(proxy.call("_resolved_camera_pitch")),
			PlayerProxy.MIN_WRIST_LOOK_PITCH
		),
		"Fieldlink's RMB look clutch retains its independent vertical range"
	)
	proxy.call("_set_wrist_mouse_look_active", false)
	for _downward_release_frame: int in range(12):
		proxy.call("_update_wrist_pose", 1.0 / 60.0)
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
	for _release_frame: int in range(12):
		proxy.call("_update_wrist_pose", 1.0 / 60.0)
	_expect(
		not proxy.wrist_mouse_look_active
		and not proxy.wrist_mouse_look_owns_pitch
		and is_equal_approx(
			float(proxy.call("_resolved_camera_pitch")),
			PlayerProxy.WRIST_LOOK_PITCH
		),
		"releasing RMB recenters a deliberately moved view while returning pointer interaction"
	)
	proxy.wrist_pose_weight = 0.0
	proxy.call("_update_wrist_pose", 1.0)
	_expect(
		not proxy.left_arm_visual.visible
		and not proxy.right_arm_visual.visible
		and proxy.character_skin.visible
		and proxy.character_skin.is_usable(),
		"an authored owner never renders either legacy grey arm"
	)
	proxy.target_on_floor = true
	proxy.local_move_input = Vector2.RIGHT
	proxy.local_predicted_horizontal_speed = ServerPlayer.RUN_SPEED
	proxy.local_predicted_horizontal_velocity = Vector2(
		ServerPlayer.RUN_SPEED,
		0.0
	)
	proxy.local_locomotion_prediction_initialized = true
	proxy.call("_update_character_pose", 1.0 / 60.0)
	for _frame_index: int in range(120):
		proxy.wrist_presentation.call("_process", 1.0 / 60.0)
	var local_authored_wrist := proxy.character_skin.get_wrist_mount(true)
	var local_equipped_pbd := proxy.equipment_visuals.get(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	) as Node3D
	var local_screen_in_camera := proxy.camera.to_local(
		proxy.wrist_presentation.terminal_screen.global_position
	)
	var local_pbd_up := (
		proxy.camera.global_basis.inverse()
		* local_equipped_pbd.global_basis.y.normalized()
	).normalized()
	var local_pbd_facing := local_equipped_pbd.global_basis.z.normalized().dot(
		(proxy.camera.global_position - local_equipped_pbd.global_position).normalized()
	)
	var projected_pbd_up := Vector2(local_pbd_up.x, local_pbd_up.y).normalized()
	var local_shoulder := proxy.to_local(proxy.character_skin.call(
		"_bone_world_origin", &"mixamorig_LeftArm"
	)) as Vector3
	var local_elbow := proxy.to_local(proxy.character_skin.call(
		"_bone_world_origin", &"mixamorig_LeftForeArm"
	)) as Vector3
	var local_hand := proxy.to_local(proxy.character_skin.call(
		"_bone_world_origin", &"mixamorig_LeftHand"
	)) as Vector3
	var local_hand_index := proxy.character_skin.skeleton.find_bone(
		PlayerCharacterSkin.LEFT_HAND
	)
	var local_hand_basis_in_camera := (
		proxy.camera.global_basis.inverse()
		* proxy.character_skin.skeleton.global_basis
		* proxy.character_skin.skeleton.get_bone_global_pose(
			local_hand_index
		).basis
	).orthonormalized()
	var forearm_axis := (
		proxy.character_skin.call(
			"_bone_world_origin", &"mixamorig_LeftHand"
		) as Vector3
		- proxy.character_skin.call(
			"_bone_world_origin", &"mixamorig_LeftForeArm"
		) as Vector3
	).normalized()
	var attachment_axis_alignment := absf(
		local_equipped_pbd.global_basis.x.normalized().dot(forearm_axis)
	)
	var wrist_attachment := local_authored_wrist.get_parent() as BoneAttachment3D
	var attachment_axis_alignment_raw := (
		absf(wrist_attachment.global_basis.y.normalized().dot(forearm_axis))
		if wrist_attachment != null
		else -1.0
	)
	var expected_mount_basis := Basis.from_euler(Vector3(
		0.0,
		0.0,
		PlayerCharacterSkin.FIELDLINK_MOUNT_ROLL
	))
	_expect(
		proxy.wrist_presentation.wrist_mount == local_authored_wrist
		and proxy.wrist_presentation.global_transform.is_equal_approx(
			local_equipped_pbd.global_transform
		),
		"the owner's interactive display follows the same authored wrist used by the equipped item"
	)
	_expect(
		wrist_attachment != null
		and wrist_attachment.bone_idx == proxy.character_skin.skeleton.find_bone(
			PlayerCharacterSkin.LEFT_FOREARM
		)
		and local_authored_wrist.basis.is_equal_approx(expected_mount_basis)
		and is_equal_approx(
			local_authored_wrist.position.y,
			proxy.character_skin._left_lower_arm_length
			* PlayerCharacterSkin.FIELDLINK_FOREARM_LENGTH_RATIO
		)
		and is_equal_approx(
			local_authored_wrist.position.z,
			PlayerCharacterSkin.FIELDLINK_FOREARM_SURFACE_OFFSET
		),
		"the wearable uses one immutable authored quarter-turn beneath a real forearm BoneAttachment3D"
	)
	_expect(
		absf(local_screen_in_camera.x) < 0.08
		and local_screen_in_camera.y > -0.06
		and local_screen_in_camera.y < 0.08
		and local_screen_in_camera.z < -0.14
		and local_screen_in_camera.z > -0.45
		and local_pbd_facing > 0.98
		and projected_pbd_up.y > 0.99
		and attachment_axis_alignment > 0.999
		and local_elbow.y > local_shoulder.y + 0.02
		and local_elbow.x < local_shoulder.x
		and local_hand.x > local_elbow.x + 0.12
		and local_hand_basis_in_camera.z.y < -0.35
		and local_equipped_pbd.scale.is_equal_approx(
			Vector3.ONE * PlayerProxy.EQUIPPED_WRIST_DEVICE_SCALE
		),
		(
			"the raised upper arm folds its forearm inward while the corrected wearable mount presents a readable display (screen=%s, facing=%.3f, up=%s, attach=%.3f/raw=%.3f, mount_local=%s, attachment=%s, shoulder=%s, elbow=%s, hand=%s)"
			% [
				local_screen_in_camera,
				local_pbd_facing,
				projected_pbd_up,
				attachment_axis_alignment,
				attachment_axis_alignment_raw,
				local_authored_wrist.transform,
				wrist_attachment.global_transform if wrist_attachment != null else Transform3D.IDENTITY,
				local_shoulder,
				local_elbow,
				local_hand,
			]
		)
	)
	proxy.local_move_input = Vector2.ZERO
	proxy.local_predicted_horizontal_speed = 0.0
	proxy.local_predicted_horizontal_velocity = Vector2.ZERO
	proxy.target_velocity = Vector3.ZERO
	proxy.target_gait_active = false
	proxy.headbob_weight = 0.0
	proxy.headbob_run_weight = 0.0
	proxy.target_stamina_ratio = 1.0
	for _rest_settle_frame: int in range(120):
		proxy.call("_update_character_pose", 1.0 / 60.0)
	var rested_hold_reference := local_equipped_pbd.global_transform
	var rested_hold_position_excursion := 0.0
	var rested_hold_rotation_excursion := 0.0
	var hit_surface_follows_arm := true
	for _hold_frame: int in range(240):
		proxy.call("_update_character_pose", 1.0 / 60.0)
		proxy.wrist_presentation.call("_process", 1.0 / 60.0)
		var current_hold := local_equipped_pbd.global_transform
		rested_hold_position_excursion = maxf(
			rested_hold_position_excursion,
			current_hold.origin.distance_to(rested_hold_reference.origin)
		)
		rested_hold_rotation_excursion = maxf(
			rested_hold_rotation_excursion,
			current_hold.basis.get_rotation_quaternion().angle_to(
				rested_hold_reference.basis.get_rotation_quaternion()
			)
		)
		hit_surface_follows_arm = (
			hit_surface_follows_arm
			and proxy.wrist_presentation.global_transform.is_equal_approx(
				current_hold
			)
		)
	proxy.target_stamina_ratio = 0.05
	for _fatigue_settle_frame: int in range(120):
		proxy.call("_update_character_pose", 1.0 / 60.0)
	var fatigued_hold_reference := local_equipped_pbd.global_transform
	var fatigued_hold_position_excursion := 0.0
	var fatigued_hold_rotation_excursion := 0.0
	for _fatigue_frame: int in range(240):
		proxy.call("_update_character_pose", 1.0 / 60.0)
		proxy.wrist_presentation.call("_process", 1.0 / 60.0)
		var current_hold := local_equipped_pbd.global_transform
		fatigued_hold_position_excursion = maxf(
			fatigued_hold_position_excursion,
			current_hold.origin.distance_to(fatigued_hold_reference.origin)
		)
		fatigued_hold_rotation_excursion = maxf(
			fatigued_hold_rotation_excursion,
			current_hold.basis.get_rotation_quaternion().angle_to(
				fatigued_hold_reference.basis.get_rotation_quaternion()
			)
		)
	_expect(
		hit_surface_follows_arm
		and rested_hold_position_excursion > 0.0005
		and rested_hold_position_excursion < 0.025
		and rested_hold_rotation_excursion > deg_to_rad(0.03)
		and fatigued_hold_position_excursion > 0.0005
		and fatigued_hold_position_excursion < 0.025
		and fatigued_hold_rotation_excursion > deg_to_rad(0.03)
		and proxy.fieldlink_hold_motion.fatigue_weight > 0.9,
		(
			"the real skeletal arm inherits bounded heavy-device sway, its END-sensitive correction remains live, and the hit surface follows it exactly (rest %.4fm/%.2fdeg, tired %.4fm/%.2fdeg)"
			% [
				rested_hold_position_excursion,
				rad_to_deg(rested_hold_rotation_excursion),
				fatigued_hold_position_excursion,
				rad_to_deg(fatigued_hold_rotation_excursion),
			]
		)
	)
	proxy.target_stamina_ratio = 1.0
	for _recovery_frame: int in range(120):
		proxy.call("_update_character_pose", 1.0 / 60.0)
	proxy.local_move_input = Vector2.RIGHT
	proxy.local_predicted_horizontal_speed = ServerPlayer.RUN_SPEED
	proxy.local_predicted_horizontal_velocity = Vector2(
		ServerPlayer.RUN_SPEED,
		0.0
	)
	var entry_results: Array[Transform3D] = []
	var entry_bends: Array[Vector3] = []
	var entry_hand_down_axes: Array[float] = []
	var every_open_reset_bend_history := true
	var fixed_wrist_transform := local_authored_wrist.transform
	for fast_mouse_swing: Vector2 in [
		Vector2(0.0, -100000.0),
		Vector2(0.0, 100000.0),
	]:
		proxy.close_wrist_interface()
		proxy.wrist_pose_weight = 0.0
		proxy.look_pitch = 0.0
		proxy.call("_apply_mouse_look", fast_mouse_swing)
		proxy.camera_pivot.rotation.x = proxy.look_pitch
		proxy.character_skin._left_previous_arm_bend = Vector3.DOWN
		proxy.open_wrist_interface()
		every_open_reset_bend_history = (
			every_open_reset_bend_history
			and proxy.character_skin._left_previous_arm_bend.is_zero_approx()
		)
		for _settle_frame: int in range(30):
			proxy.call("_update_wrist_pose", 1.0 / 60.0)
			proxy.camera_pivot.rotation.x = float(
				proxy.call("_resolved_camera_pitch")
			)
			proxy.call("_update_character_pose", 1.0 / 60.0)
		entry_results.append(
			proxy.camera.global_transform.affine_inverse()
			* local_equipped_pbd.global_transform
		)
		entry_bends.append(proxy.character_skin._left_previous_arm_bend.normalized())
		entry_hand_down_axes.append((
			proxy.camera.global_basis.inverse()
			* proxy.character_skin.skeleton.global_basis
			* proxy.character_skin.skeleton.get_bone_global_pose(
				local_hand_index
			).basis
		).orthonormalized().z.y)
	var entry_position_difference := entry_results[0].origin.distance_to(
		entry_results[1].origin
	)
	var entry_rotation_difference := (
		entry_results[0].basis.orthonormalized().get_rotation_quaternion()
		.angle_to(
			entry_results[1].basis.orthonormalized().get_rotation_quaternion()
		)
	)
	_expect(
		entry_results.size() == 2
		and every_open_reset_bend_history
		and entry_bends.size() == 2
		and entry_bends[0].dot(entry_bends[1]) > 0.98
		and entry_hand_down_axes.size() == 2
		and entry_hand_down_axes[0] < -0.35
		and entry_hand_down_axes[1] < -0.35
		and entry_position_difference < 0.01
		and entry_rotation_difference < deg_to_rad(1.75)
		and local_authored_wrist.transform.is_equal_approx(
			fixed_wrist_transform
		)
		and is_equal_approx(
			proxy.camera_pivot.rotation.x,
			PlayerProxy.WRIST_LOOK_PITCH
		),
		(
			"opposite pre-open camera swings converge on one eye-relative arm pose apart from bounded live hold sway, without rotating the physical mount (position_delta=%.4f, angle_delta=%.2fdeg)"
			% [entry_position_difference, rad_to_deg(entry_rotation_difference)]
		)
	)
	var safety_positions: Array[Vector3] = []
	var safety_clearances: Array[float] = []
	var safety_pose_pitches: Array[float] = []
	proxy.wrist_mouse_look_active = true
	proxy.wrist_mouse_look_owns_pitch = true
	proxy.wrist_mouse_look_blend = 1.0
	for safety_pitch: float in [deg_to_rad(30.0), deg_to_rad(85.0)]:
		proxy.look_pitch = safety_pitch
		proxy.camera_pivot.rotation.x = safety_pitch
		for _safety_frame: int in range(120):
			proxy.call("_update_character_pose", 1.0 / 60.0)
		safety_positions.append(local_equipped_pbd.global_position)
		safety_clearances.append(_nearest_mesh_distance_to_point(
			local_equipped_pbd,
			proxy.camera.global_position
		))
		safety_pose_pitches.append(proxy.fieldlink_pose_pitch)
	_expect(
		is_equal_approx(
			safety_pose_pitches[1],
			PlayerProxy.FIELDLINK_UPWARD_FOCUS_PITCH
		)
		and safety_pose_pitches[0] < deg_to_rad(-21.0)
		and safety_pose_pitches[0] > PlayerProxy.WRIST_LOOK_PITCH
		and safety_pose_pitches[1] < deg_to_rad(-19.5)
		and proxy.camera_pivot.rotation.x > deg_to_rad(84.0)
		and safety_positions[0].distance_to(safety_positions[1]) < 0.05
		and minf(safety_clearances[0], safety_clearances[1])
		> proxy.camera.near + 0.05,
		(
			"upward RMB head look leaves the arm near its lower operating pose while the camera remains free (poses=%.1f/%.1fdeg, clearance=%.3fm)"
			% [
				rad_to_deg(safety_pose_pitches[0]),
				rad_to_deg(safety_pose_pitches[1]),
				minf(safety_clearances[0], safety_clearances[1]),
			]
		)
	)
	proxy.look_pitch = PlayerProxy.MIN_WRIST_LOOK_PITCH
	proxy.camera_pivot.rotation.x = PlayerProxy.MIN_WRIST_LOOK_PITCH
	for _downward_safety_frame: int in range(120):
		proxy.call("_update_character_pose", 1.0 / 60.0)
		proxy.wrist_presentation.call("_process", 1.0 / 60.0)
	var downward_screen_in_camera := proxy.camera.to_local(
		proxy.wrist_presentation.terminal_screen.global_position
	)
	var downward_clearance := _nearest_mesh_distance_to_point(
		local_equipped_pbd,
		proxy.camera.global_position
	)
	_expect(
		is_equal_approx(
			proxy.fieldlink_pose_pitch,
			PlayerProxy.FIELDLINK_POSE_MIN_PITCH
		)
		and absf(downward_screen_in_camera.x) < 0.15
		and absf(downward_screen_in_camera.y) < 0.20
		and downward_screen_in_camera.z < -0.12
		and downward_screen_in_camera.z > -0.55
		and downward_clearance > proxy.camera.near + 0.07,
		(
			"maximum downward Fieldlink look stays inside the physical arm's readable, camera-safe arc (screen=%s, clearance=%.3fm)"
			% [downward_screen_in_camera, downward_clearance]
		)
	)
	proxy.local_move_input = Vector2.LEFT
	proxy.update_headbob(1.0 / 60.0)
	_expect(
		proxy.local_predicted_horizontal_velocity.x > 0.0
		and proxy.local_predicted_horizontal_velocity.x < ServerPlayer.RUN_SPEED,
		"opposite local input brakes the predicted velocity through zero instead of assigning the old speed to the new direction"
	)
	proxy.local_move_input = Vector2.ZERO
	proxy.local_predicted_horizontal_speed = 0.0
	proxy.local_predicted_horizontal_velocity = Vector2.ZERO
	proxy.look_pitch = looked_up_pitch
	proxy.camera_pivot.rotation.x = looked_up_pitch
	proxy.wrist_mouse_look_active = true
	proxy.wrist_mouse_look_owns_pitch = true
	proxy.wrist_mouse_look_blend = 1.0
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
	proxy.open_wrist_interface()
	proxy.wrist_mouse_look_owns_pitch = true
	proxy.wrist_mouse_look_blend = 1.0
	# Simulate an old/replicated device-only pitch outside the new physical comfort arc.
	proxy.look_pitch = deg_to_rad(-85.0)
	proxy.close_wrist_interface()
	_expect(
		is_equal_approx(proxy.look_pitch, PlayerProxy.MIN_WORLD_LOOK_PITCH)
		and is_equal_approx(
			float(proxy.call("_resolved_camera_pitch")),
			PlayerProxy.MIN_WORLD_LOOK_PITCH
		),
		"closing Fieldlink clamps only its device-exclusive downward angle before ordinary view resumes"
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
		and torso_space_screen.z < -0.08
		and remote_device_rear_z < -0.08,
		(
			"the remote arm raises its equipped Fieldlink forward of the torso (screen_z=%.3f, rear_z=%.3f)"
			% [torso_space_screen.z, remote_device_rear_z]
		)
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
	var expected_right_wrist_mount := (
		proxy.character_skin.get_wrist_mount(false)
		if proxy.character_skin != null and proxy.character_skin.is_usable()
		else proxy.right_wrist_mount
	)
	var right_attachment := (
		expected_right_wrist_mount.get_parent() as BoneAttachment3D
		if expected_right_wrist_mount != null
		else null
	)
	var expected_right_mount_basis := Basis.from_euler(Vector3(
		0.0,
		0.0,
		-PlayerCharacterSkin.FIELDLINK_MOUNT_ROLL
	))
	var right_hand_index := proxy.character_skin.skeleton.find_bone(
		PlayerCharacterSkin.RIGHT_HAND
	)
	var right_hand_basis_in_player := (
		proxy.global_basis.inverse()
		* proxy.character_skin.skeleton.global_basis
		* proxy.character_skin.skeleton.get_bone_global_pose(
			right_hand_index
		).basis
	).orthonormalized()
	_expect(
		wrist_visual.get_parent() == expected_right_wrist_mount
		and right_attachment != null
		and right_attachment.bone_idx == proxy.character_skin.skeleton.find_bone(
			PlayerCharacterSkin.RIGHT_FOREARM
		)
		and expected_right_wrist_mount.basis.is_equal_approx(
			expected_right_mount_basis
		)
		and proxy.right_arm_visual.rotation.x > 0.0
		and not is_zero_approx(proxy.right_arm_visual.rotation.z)
		and right_hand_basis_in_player.z.y < -0.35
		and right_arm_device_rear_z < -0.08,
		(
			"the same forward shoulder pose works when the Fieldlink moves to the surviving right arm (parent=%s, pitch=%.3f, roll=%.3f, rear_z=%.3f)"
			% [
				wrist_visual.get_parent() == expected_right_wrist_mount,
				proxy.right_arm_visual.rotation.x,
				proxy.right_arm_visual.rotation.z,
				right_arm_device_rear_z,
			]
		)
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


func _nearest_mesh_distance_to_point(
	visual_root: Node3D,
	world_point: Vector3
) -> float:
	var nearest_distance := INF
	for node: Node in visual_root.find_children(
		"*",
		"MeshInstance3D",
		true,
		false
	):
		var mesh_instance := node as MeshInstance3D
		var bounds := mesh_instance.get_aabb()
		var local_point := mesh_instance.to_local(world_point)
		var nearest_local := Vector3(
			clampf(local_point.x, bounds.position.x, bounds.end.x),
			clampf(local_point.y, bounds.position.y, bounds.end.y),
			clampf(local_point.z, bounds.position.z, bounds.end.z)
		)
		nearest_distance = minf(
			nearest_distance,
			world_point.distance_to(mesh_instance.to_global(nearest_local))
		)
	return nearest_distance


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
