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
	_test_ocular_distortion_contract()
	_test_client_draw_order()
	_test_server_wiring()

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

	_expect(
		player.get_inventory_capacity() == 1,
		"a player without a backpack has one inventory slot"
	)
	_expect(player.has_equipped_eyes(), "players begin with factory eyes")

	var soda_entry := PlayerInventoryRules.make_entry(
		SODA,
		{"temperature": 4.0}
	)
	_expect(
		player.try_store_inventory_entry(soda_entry),
		"the baseline slot accepts one item"
	)
	_expect(
		not player.try_store_inventory_entry(soda_entry),
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
	var downsize_result := player.try_equip_world_entry(
		PlayerInventoryRules.make_entry(sling)
	)
	_expect(
		not bool(downsize_result.get("success", false)),
		"a smaller backpack cannot discard overflow items"
	)
	_expect(
		player.get_inventory_capacity() == 6,
		"a rejected backpack swap leaves equipment unchanged"
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

	player.free()


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


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: " + message)
