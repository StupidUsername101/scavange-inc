extends SceneTree

const SERVER_PLAYER_SCENE := preload(
	"res://scenes/server/server_player.tscn"
)
const SODA := preload(
	"res://scripts/items/definitions/soda_red.tres"
)
const BACKPACK_PATHS: Array[String] = [
	"res://resources/items/backpacks/scavenger_sling.tres",
	"res://resources/items/backpacks/field_pack.tres",
	"res://resources/items/backpacks/industrial_frame_pack.tres",
]
const EYE_PATHS: Array[String] = [
	"res://resources/items/eyes/factory_oculars.tres",
	"res://resources/items/eyes/salvaged_oculars.tres",
	"res://resources/items/eyes/precision_oculars.tres",
]
const WRIST_DEVICE_PATH := (
	"res://resources/items/wrist_devices/corporate_field_terminal.tres"
)

#######################################################
# Runs headless regression coverage for player equipment system behavior and reports contract
# or integration failures.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_definition_contracts()
	_test_inventory_and_equipment_transactions()
	_test_public_inventory_sanitization()
	_test_ocular_distortion_contract()
	_test_client_draw_order()
	_test_server_wiring()
	_test_starting_loadout_contract()

	if failure_count == 0:
		print(
			"Player equipment tests passed: %d assertions"
			% assertion_count
		)
		quit(0)
	else:
		push_error(
			"Player equipment tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_definition_contracts() -> void:
	var expected_capacities: Array[int] = [3, 6, 9]
	for index: int in range(BACKPACK_PATHS.size()):
		var backpack := load(BACKPACK_PATHS[index]) as BackpackDefinition
		_expect(backpack != null, "backpack %d loads" % index)
		if backpack == null:
			continue
		_expect(
			backpack.equipment_slot == &"backpack",
			"backpack %d uses the generic backpack slot" % index
		)
		_expect(
			backpack.inventory_capacity == expected_capacities[index],
			"backpack %d has the intended capacity" % index
		)
		_expect(
			backpack.equipped_visual_scene != null,
			"backpack %d has a mounted visual" % index
		)

	var shader_paths: Array[String] = []
	for index: int in range(EYE_PATHS.size()):
		var eyes := load(EYE_PATHS[index]) as EyeDefinition
		_expect(eyes != null, "ocular pair %d loads" % index)
		if eyes == null:
			continue
		_expect(
			eyes.equipment_slot == &"eyes",
			"ocular pair %d uses the generic eyes slot" % index
		)
		_expect(
			eyes.visual_acuity >= 0.0
			and eyes.visual_acuity <= 1.0
			and eyes.contrast_sensitivity >= 0.0
			and eyes.contrast_sensitivity <= 1.0
			and eyes.light_sensitivity >= 0.0
			and eyes.light_sensitivity <= 1.0
			and eyes.optical_quality >= 0.0
			and eyes.optical_quality <= 1.0,
			"ocular pair %d keeps all sight stats normalized" % index
		)
		_expect(
			eyes.special_sight_effects.is_empty(),
			"ocular pair %d reserves but does not enable special sight" % index
		)
		_expect(
			eyes.vision_shader != null,
			"ocular pair %d has a vision shader" % index
		)
		if eyes.vision_shader != null:
			shader_paths.append(eyes.vision_shader.resource_path)

	_expect(
		shader_paths.size() == 3
		and shader_paths[0] != shader_paths[1]
		and shader_paths[0] != shader_paths[2]
		and shader_paths[1] != shader_paths[2],
		"the three ocular variants use distinct shaders"
	)

	var wrist_device := load(WRIST_DEVICE_PATH) as EquippableItemDefinition
	_expect(wrist_device != null, "the Fieldlink item definition loads")
	if wrist_device != null:
		_expect(
			wrist_device.equipment_slot
			== PlayerInventoryRules.WRIST_DEVICE_SLOT,
			"the Fieldlink uses the generic wrist-device slot"
		)
		_expect(
			wrist_device.visual_scene != null
			and wrist_device.equipped_visual_scene != null,
			"the Fieldlink is both a physical item and equipped visual"
		)

	var inspection_interface := load(
		"res://resources/items/player_equipment_inspection_interface.tres"
	)
	_expect(
		inspection_interface != null
		and inspection_interface.call(
			"supports",
			load(EYE_PATHS[0])
		),
		"the parts scanner exposes ocular diagnostics"
	)


func _test_inventory_and_equipment_transactions() -> void:
	var player := SERVER_PLAYER_SCENE.instantiate() as ServerPlayer
	root.add_child(player)
	var initial_revision := player.inventory_revision

	_expect(
		player.get_inventory_capacity() == 1 and initial_revision > 0,
		"a player without a backpack has one inventory slot"
	)
	_expect(
		not player.cycle_inventory_slot(1)
		and player.selected_inventory_slot == 0,
		"mouse-wheel slot cycling is unavailable without an equipped backpack"
	)
	_expect(player.has_equipped_eyes(), "players begin with factory eyes")
	_expect(
		player.has_equipped_wrist_device(),
		"players begin with an equipped Fieldlink"
	)
	player.set_wrist_interface_open(true)
	player.set_input(Vector2.ONE, 0.5, 0.25, true)
	player.request_jump()
	player.set_primary_action_held(true)
	_expect(
		player.wrist_interface_open
		and is_equal_approx(player.move_input.length(), 1.0)
		and player.wants_run
		and player.wants_jump
		and not player.primary_action_held,
		"an open wrist terminal preserves locomotion while suppressing weapon input"
	)
	var removed_wrist := player.try_unequip_to_world(
		PlayerInventoryRules.WRIST_DEVICE_SLOT
	)
	_expect(
		not removed_wrist.is_empty()
		and not player.has_equipped_wrist_device()
		and not player.wrist_interface_open
		and player.inventory_revision > initial_revision,
		"losing the wrist item immediately closes its interface"
	)

	var soda_entry := PlayerInventoryRules.make_entry(
		SODA,
		{"temperature": 4.0}
	)
	_expect(
		player.try_store_inventory_entry(soda_entry),
		"the baseline slot accepts one item"
	)
	var filled_revision := player.inventory_revision
	_expect(
		not player.try_store_inventory_entry(soda_entry)
		and player.inventory_revision == filled_revision,
		"the baseline slot rejects a second item"
	)

	var field_pack := load(BACKPACK_PATHS[1]) as BackpackDefinition
	var field_result := player.try_equip_world_entry(
		PlayerInventoryRules.make_entry(field_pack)
	)
	_expect(
		bool(field_result.get("success", false)),
		"a world backpack equips through the generic transaction"
	)
	_expect(
		player.get_inventory_capacity() == 6,
		"the field pack expands inventory to six slots"
	)
	for _item_index: int in range(4):
		_expect(
			player.try_store_inventory_entry(soda_entry),
			"the expanded backpack accepts carried items"
		)

	var sling := load(BACKPACK_PATHS[0]) as BackpackDefinition
	var revision_before_rejected_downsize := player.inventory_revision
	var downsize_result := player.try_equip_world_entry(
		PlayerInventoryRules.make_entry(sling)
	)
	_expect(
		not bool(downsize_result.get("success", false))
		and player.inventory_revision == revision_before_rejected_downsize,
		"a smaller backpack cannot discard overflow items"
	)
	_expect(
		player.get_inventory_capacity() == 6,
		"a rejected backpack swap leaves equipment unchanged"
	)
	player.select_inventory_slot(5)
	var selection_revision := player.inventory_revision
	_expect(
		player.cycle_inventory_slot(1)
		and player.selected_inventory_slot == 0
		and player.inventory_revision > selection_revision,
		"backpack slot cycling advances and wraps through authoritative capacity"
	)
	_expect(
		player.cycle_inventory_slot(-1)
		and player.selected_inventory_slot == 5
		and not player.cycle_inventory_slot(0),
		"backpack slot cycling moves backward, wraps, and rejects a zero direction"
	)

	var salvaged_eyes := load(EYE_PATHS[1]) as EyeDefinition
	var eye_result := player.try_equip_world_entry(
		PlayerInventoryRules.make_entry(
			salvaged_eyes,
			{"wear": 0.37}
		)
	)
	_expect(
		bool(eye_result.get("success", false)),
		"eyes equip through the same generic transaction"
	)
	var displaced: Dictionary = eye_result.get("displaced", {})
	_expect(
		not displaced.is_empty(),
		"replacing eyes returns the previous pair instead of deleting it"
	)

	var removed_eyes := player.try_unequip_to_world(
		PlayerInventoryRules.EYES_SLOT
	)
	_expect(not removed_eyes.is_empty(), "equipped eyes can be removed")
	_expect(
		not player.has_equipped_eyes(),
		"an empty eyes slot produces a genuine no-eyes state"
	)
	_expect(
		float(
			removed_eyes.get("instance_state", {}).get("wear", -1.0)
		) == 0.37,
		"equipped items preserve per-instance state"
	)
	var snapshot := player.to_state_dict()
	var lean_snapshot := player.to_state_dict(false)
	_expect(
		int(snapshot.get("inventory_revision", -1)) == player.inventory_revision
		and snapshot.get("inventory", {}) is Dictionary
		and int(lean_snapshot.get("inventory_revision", -1)) == player.inventory_revision
		and not lean_snapshot.has("inventory"),
		"authoritative snapshots carry the revision for their cached public inventory"
	)
	var quiet_probability := ServerPlayer.ragdoll_backpack_release_probability(
		1.5,
		2.0,
		2.0,
		1.0
	)
	var hard_probability := ServerPlayer.ragdoll_backpack_release_probability(
		10.0,
		18.0,
		8.0,
		8.0
	)
	var extreme_probability := ServerPlayer.ragdoll_backpack_release_probability(
		100.0,
		100.0,
		100.0,
		100.0
	)
	_expect(
		is_zero_approx(quiet_probability)
		and hard_probability > 0.08
		and hard_probability < extreme_probability
		and extreme_probability
		<= ServerPlayer.RAGDOLL_BACKPACK_MAX_RELEASE_PROBABILITY,
		"backpack loss ignores ordinary motion, rises nonlinearly with violent ragdoll load, and remains capped"
	)
	var ragdoll_release := player.release_backpack_for_ragdoll()
	var released_backpack: Dictionary = ragdoll_release.get("backpack", {})
	var spilled_entries: Array = ragdoll_release.get("spilled", [])
	_expect(
		str(released_backpack.get("definition_path", ""))
		== BACKPACK_PATHS[1]
		and spilled_entries.size() == 4
		and player.inventory_entries.size() == PlayerInventoryRules.BASE_CAPACITY
		and player.get_inventory_capacity() == PlayerInventoryRules.BASE_CAPACITY
		and not player.equipment_entries.has(PlayerInventoryRules.BACKPACK_SLOT),
		"ragdoll backpack release preserves one baseline-pocket item and spills every backpack-only entry"
	)

	player.free()


func _test_public_inventory_sanitization() -> void:
	var sanitized: Dictionary = PlayerInventoryRules.sanitize_public_inventory({
		"capacity": 6.0,
		"selected_slot": 99,
		"entries": [
			{"definition_path": "res://one.tres", "instance_state": "broken"},
			"broken-slot",
			{"definition_path": "res://three.tres"},
		],
		"equipment": {
			"eyes": "broken-equipment",
			"backpack": {
				"definition_path": "res://pack.tres",
				"instance_state": ["broken"],
			},
		},
	})
	_expect(int(sanitized.get("capacity", 0)) == 6, "public inventory keeps valid integral capacity")
	_expect(int(sanitized.get("selected_slot", -1)) == 5, "public inventory clamps selected slot to capacity")
	var entries_value: Variant = sanitized.get("entries", [])
	var entries: Array = entries_value as Array if entries_value is Array else []
	_expect(entries.size() == 3, "malformed public inventory entries do not shift later slot indices")
	if entries.size() == 3:
		var first: Dictionary = entries[0] as Dictionary if entries[0] is Dictionary else {}
		var second: Dictionary = entries[1] as Dictionary if entries[1] is Dictionary else {}
		var third: Dictionary = entries[2] as Dictionary if entries[2] is Dictionary else {}
		_expect(not first.has("instance_state"), "wrong-type public instance state is discarded")
		_expect(second.is_empty(), "wrong-type public slot becomes an empty slot")
		_expect(str(third.get("definition_path", "")) == "res://three.tres", "later public slots retain their original index")
	var equipment_value: Variant = sanitized.get("equipment", {})
	var sanitized_equipment: Dictionary = (
		equipment_value as Dictionary if equipment_value is Dictionary else {}
	)
	_expect(not sanitized_equipment.has("eyes"), "wrong-type public equipment entries are discarded")
	var backpack_value: Variant = sanitized_equipment.get("backpack", {})
	var backpack: Dictionary = backpack_value as Dictionary if backpack_value is Dictionary else {}
	_expect(not backpack.has("instance_state"), "wrong-type equipment instance state is discarded")
	_expect(
		PlayerInventoryRules.get_capacity({PlayerInventoryRules.BACKPACK_SLOT: "broken"})
		== PlayerInventoryRules.BASE_CAPACITY,
		"malformed internal backpack state falls back to base capacity"
	)
	var empty_state: Dictionary = PlayerInventoryRules.sanitize_public_inventory("broken")
	_expect(
		int(empty_state.get("capacity", 0)) == PlayerInventoryRules.BASE_CAPACITY
		and int(empty_state.get("selected_slot", -1)) == 0,
		"wrong-type top-level public inventory fails closed to defaults"
	)


func _test_ocular_distortion_contract() -> void:
	var player := SERVER_PLAYER_SCENE.instantiate() as ServerPlayer
	root.add_child(player)
	player.apply_vision_distortion(
		4.0,
		3.0,
		2.0,
		40.0,
		Vector2(-3.0, 5.0),
		90.0
	)
	var state: Dictionary = player.call("_get_vision_distortion_state")
	_expect(float(state["warp"]) <= 1.0, "warp is bounded")
	_expect(float(state["glitch"]) <= 1.0, "glitch is bounded")
	_expect(float(state["smear"]) <= 1.0, "smear is bounded")
	_expect(
		state["center"] == Vector2(0.0, 1.0),
		"distortion center is clamped to the screen"
	)
	_expect(float(state["pulse_hz"]) <= 30.0, "pulse rate is bounded")
	player.free()


func _test_client_draw_order() -> void:
	var proxy_scene := load(
		"res://scenes/proxy/player_proxy.tscn"
	) as PackedScene
	_expect(proxy_scene != null, "player proxy scene loads")
	if proxy_scene == null:
		return
	var proxy := proxy_scene.instantiate() as PlayerProxy
	_expect(proxy != null, "player proxy uses the expected script")
	if proxy == null:
		return
	_expect(
		proxy.has_node("PlayerInterface/PlayerHud"),
		"player proxy contains the dynamic HUD"
	)
	_expect(
		proxy.has_node("OcularPostProcess/VisionEffect"),
		"player proxy contains the ocular post-process"
	)
	_expect(
		proxy.has_node("BodyVisual/UpperBodyPose/LeftArm/WristMount")
		and proxy.has_node("BodyVisual/UpperBodyPose/RightArm/WristMount"),
		"either surviving arm can carry replicated wrist equipment"
	)
	var interface_layer := proxy.get_node("PlayerInterface") as CanvasLayer
	var ocular_layer := proxy.get_node("OcularPostProcess") as CanvasLayer
	_expect(
		interface_layer.layer < ocular_layer.layer,
		"ocular shaders process the HUD together with the world"
	)

	proxy.set_local_player(true)
	proxy.apply_server_state({
		"inventory": {
			"capacity": 1,
			"selected_slot": 0,
			"entries": [],
			"equipment": {},
		},
	})
	var hud := proxy.get_node(
		"PlayerInterface/PlayerHud"
	) as PlayerInventoryHud
	var vision := proxy.get_node(
		"OcularPostProcess/VisionEffect"
	) as OcularVisionController
	_expect(
		not hud.visible
		and vision.material == null
		and vision.color == Color.BLACK,
		"no eyes black out vision and hide the player HUD"
	)

	var factory_eyes := load(EYE_PATHS[0]) as EyeDefinition
	proxy.apply_server_state({
		"inventory": {
			"capacity": 1,
			"selected_slot": 0,
			"entries": [],
			"equipment": {
				PlayerInventoryRules.EYES_SLOT:
					PlayerInventoryRules.to_public_entry(
						PlayerInventoryRules.make_entry(factory_eyes)
					),
			},
		},
	})
	_expect(
		hud.visible and vision.material is ShaderMaterial,
		"equipped eyes restore both vision and the player HUD"
	)
	proxy.apply_replicated_inventory_state(10, {
		"capacity": 1,
		"selected_slot": 0,
		"entries": [],
		"equipment": {},
	})
	proxy.apply_server_state({
		"player_id": 71,
		"inventory_revision": 10,
		"health_ratio": 0.6,
	})
	_expect(
		not hud.visible
		and is_equal_approx(hud.health_ratio, 0.6),
		"lean movement snapshots update vitals without reapplying unchanged inventory"
	)
	proxy.apply_replicated_inventory_state(9, {
		"capacity": 1,
		"selected_slot": 0,
		"entries": [],
		"equipment": {
			PlayerInventoryRules.EYES_SLOT:
				PlayerInventoryRules.to_public_entry(
					PlayerInventoryRules.make_entry(factory_eyes)
				),
		},
	})
	_expect(
		not hud.visible,
		"a late reliable inventory revision cannot rewind newer equipment"
	)
	proxy.apply_replicated_inventory_state(11, {
		"capacity": 1,
		"selected_slot": 0,
		"entries": [],
		"equipment": {
			PlayerInventoryRules.EYES_SLOT:
				PlayerInventoryRules.to_public_entry(
					PlayerInventoryRules.make_entry(factory_eyes)
				),
		},
	})
	_expect(
		hud.visible and vision.material is ShaderMaterial,
		"the next reliable inventory revision applies equipment immediately"
	)
	proxy.free()


func _test_server_wiring() -> void:
	var server_source := FileAccess.get_file_as_string(
		"res://scripts/server/server.gd"
	)
	var client_source := FileAccess.get_file_as_string(
		"res://scripts/client/client.gd"
	)
	_expect(
		server_source.contains("func distort_player_vision("),
		"monsters have one server-facing distortion entry point"
	)
	_expect(
		server_source.contains("try_equip_world_entry(")
		and server_source.contains("try_equip_inventory_entry("),
		"world and inventory equipment use authoritative transactions"
	)
	_expect(
		client_source.contains("USE_HOLD_SECONDS")
		and client_source.contains("\"equip_item\""),
		"holding F sends an equip intent"
	)
	var has_wheel_previous := false
	for event: InputEvent in InputMap.action_get_events(
		"inventory_slot_previous"
	):
		has_wheel_previous = (
			has_wheel_previous
			or (
				event is InputEventMouseButton
				and (event as InputEventMouseButton).button_index
				== MOUSE_BUTTON_WHEEL_UP
			)
		)
	var has_wheel_next := false
	for event: InputEvent in InputMap.action_get_events("inventory_slot_next"):
		has_wheel_next = (
			has_wheel_next
			or (
				event is InputEventMouseButton
				and (event as InputEventMouseButton).button_index
				== MOUSE_BUTTON_WHEEL_DOWN
			)
		)
	_expect(
		has_wheel_previous
		and has_wheel_next
		and client_source.contains("\"cycle_inventory_slot\""),
		"mouse wheel up/down routes backpack slot changes through the authoritative relative-selection RPC"
	)


func _test_starting_loadout_contract() -> void:
	var server := root.get_node_or_null("Server")
	var expected_path := "res://resources/character_loadouts/full_body.tres"
	var all_players_receive_default := server != null
	for player_id: int in [1, 2, 3, 999]:
		var loadout := (
			server.call("_get_starting_body_loadout", player_id) as CharacterLoadout
			if server != null
			else null
		)
		all_players_receive_default = (
			all_players_receive_default
			and loadout != null
			and loadout.resource_path == expected_path
		)
	_expect(
		all_players_receive_default,
		"joining player identity never selects a hidden demo body loadout"
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: " + message)
