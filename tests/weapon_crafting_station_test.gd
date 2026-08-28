extends SceneTree

const RIFLE_RECEIVER := "res://resources/guns/parts/automatic_rifle_receiver.tres"
const RIFLE_BARREL := "res://resources/guns/parts/automatic_rifle_barrel.tres"
const RIFLE_MAGAZINE := "res://resources/guns/parts/automatic_rifle_magazine.tres"
const RIFLE_AMMUNITION := "res://resources/guns/parts/warehouse_556_ammunition.tres"
const PISTOL_AMMUNITION := "res://resources/guns/parts/service_ball_ammunition.tres"
const SERVER_STATION_SCENE := "res://scenes/server/weapon_crafting_station.tscn"
const CLIENT_STATION_SCENE := "res://scenes/proxy/weapon_crafting_station.tscn"

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var document := WeaponCraftingCatalog.build_document()
	var selection := WeaponCraftingCatalog.default_selection_indices(document)
	_test_catalog_and_layout(document, selection)
	var ridiculous_selection := _make_ridiculous_selection(document, selection)
	_test_repeated_barrel_build(document, ridiculous_selection)
	_test_inventory_fire_contract(document, ridiculous_selection)
	_test_machine_scenes_and_replication(document, ridiculous_selection)
	_finish()


func _test_catalog_and_layout(
	document: Dictionary,
	selection: Array[int]
) -> void:
	var lanes: Array = document.get("lanes", [])
	_expect(
		lanes.size() == 6 and selection.size() == 6,
		"fabricator exposes six independent receiver, barrel, feed, and load reels"
	)
	_expect(
		str(lanes[1].get("lane_id", "")) == "barrel_0"
		and bool(lanes[1].get("required", false))
		and str(lanes[2].get("lane_id", "")) == "barrel_1"
		and not bool(lanes[2].get("required", true))
		and str(lanes[3].get("lane_id", "")) == "barrel_2",
		"one barrel is required while two repeated barrel mounts remain optional"
	)
	var optional_options: Array = lanes[2].get("options", [])
	_expect(
		not optional_options.is_empty()
		and str(optional_options[0].get("definition_path", "")).is_empty(),
		"optional reels include a deliberate empty mount instead of forcing a shape"
	)
	var lane_action := WeaponCraftingStationLayout.get_lane_cycle_action(
		WeaponCraftingStationLayout.get_next_rect(2).get_center(),
		lanes.size()
	)
	_expect(
		int(lane_action.get("lane_index", -1)) == 2
		and int(lane_action.get("direction", 0)) == 1,
		"the world-space reel grid maps each next cube to exactly one lane"
	)
	_expect(
		bool(document.get("optics_reserved", false)),
		"the first station reserves optics without pretending to implement them"
	)


func _test_repeated_barrel_build(
	document: Dictionary,
	selection: Array[int]
) -> void:
	var build := WeaponCraftingCatalog.build_from_selection(document, selection)
	_expect(
		build.is_compatible() and build.get_barrel_count() == 3,
		"the same rifle barrel can legally occupy all three independent mounts"
	)
	var profiles := build.get_ballistic_profiles()
	_expect(
		profiles.size() == 3
		and int(build.get_ballistic_profile().get("barrel_count", 0)) == 3,
		"every installed barrel produces its own authoritative ballistic profile"
	)
	var serialized := build.to_state_dict()
	var barrel_paths: Array = serialized.get("barrel_paths", [])
	var restored := GunBuild.new()
	restored.apply_state_dict(serialized)
	_expect(
		barrel_paths.size() == 3
		and restored.get_barrel_count() == 3
		and restored.is_compatible(),
		"ordered repeated barrels survive persistent item-state serialization"
	)
	var expected_mass := (
		build.receiver.mass
		+ build.barrel.mass * 3.0
		+ build.magazine.mass
		+ build.ammunition.mass
	)
	_expect(
		is_equal_approx(build.get_total_mass(), expected_mass),
		"repeated components contribute physical mass exactly once each"
	)
	var visual := GunGeometry.create_gun_visual(build)
	_expect(
		visual.get_node_or_null("Barrel") != null
		and visual.get_node_or_null("Barrel2") != null
		and visual.get_node_or_null("Barrel3") != null
		and visual.get_node_or_null("MuzzleBrake3") != null,
		"procedural geometry lays repeated barrels out without a bespoke weapon shape"
	)
	visual.free()

	var incompatible_selection := selection.duplicate()
	_set_lane_path(
		document,
		incompatible_selection,
		"ammunition",
		PISTOL_AMMUNITION
	)
	var incompatible_summary := WeaponCraftingCatalog.build_summary(
		document,
		incompatible_selection
	)
	_expect(
		not bool(incompatible_summary.get("compatible", true))
		and not (incompatible_summary.get("errors", []) as Array).is_empty(),
		"ridiculous topology stays legal while caliber mismatch still blocks an inoperable payout"
	)


func _test_inventory_fire_contract(
	document: Dictionary,
	selection: Array[int]
) -> void:
	var build := WeaponCraftingCatalog.build_from_selection(document, selection)
	var definition := load(
		WeaponCraftingCatalog.CRAFTED_WEAPON_PATH
	) as GunItemDefinition
	_expect(definition != null, "fabricated weapon has an ordinary persistent item definition")
	if definition == null:
		return
	var state := WeaponCraftingCatalog.make_crafted_instance_state(build)
	_expect(
		str(state.get(GunItemDefinition.BUILD_SIGNATURE_KEY, ""))
		== build.visual_signature(),
		"fabrication stamps one stable visual signature onto the crafted instance"
	)
	var player_scene := load("res://scenes/server/server_player.tscn") as PackedScene
	var player := player_scene.instantiate() as ServerPlayer
	root.add_child(player)
	player.setup(904, Vector3.ZERO)
	_expect(
		player.try_store_inventory_entry(
			PlayerInventoryRules.make_entry(definition, state)
		),
		"fabricator payout enters the existing player inventory path"
	)
	var initial_rounds := build.get_magazine_capacity()
	var result := player.try_fire_selected_gun()
	var entry := player.get_selected_inventory_entry()
	var remaining_rounds := int(entry.get("instance_state", {}).get("rounds", -1))
	_expect(
		bool(result.get("fired", false))
		and int(result.get("fired_barrel_count", 0)) == 3
		and int(result.get("installed_barrel_count", 0)) == 3
		and (result.get("profiles", []) as Array).size() == 3
		and remaining_rounds == initial_rounds - 3,
		"one trigger pull fires every installed barrel and consumes one round per muzzle"
	)
	entry["instance_state"]["rounds"] = 2
	player.inventory_entries[player.selected_inventory_slot] = entry
	player.weapon_fire_cooldown_remaining = 0.0
	var partial_result := player.try_fire_selected_gun()
	_expect(
		int(partial_result.get("fired_barrel_count", 0)) == 2
		and int(partial_result.get("installed_barrel_count", 0)) == 3
		and int(player.get_selected_inventory_entry().get(
			"instance_state",
			{}
		).get("rounds", -1)) == 0,
		"a nearly empty magazine fires only loaded barrels while preserving the three-muzzle layout"
	)
	player.queue_free()


func _test_machine_scenes_and_replication(
	document: Dictionary,
	selection: Array[int]
) -> void:
	var server_scene := load(SERVER_STATION_SCENE) as PackedScene
	var client_scene := load(CLIENT_STATION_SCENE) as PackedScene
	var server_station := server_scene.instantiate() as Node3D
	var client_station := client_scene.instantiate() as Node3D
	root.add_child(server_station)
	root.add_child(client_station)
	_expect(
		server_station != null
		and server_station.has_method("server_primary_action")
		and server_station.has_method("server_use")
		and client_station.get_node_or_null("TerminalScreen") != null,
		"server collision and client slot-machine presentation instantiate together"
	)
	var client := root.get_node_or_null("Client")
	var player_id := int(client.get("local_player_id")) if client != null else -1
	var summary := WeaponCraftingCatalog.build_summary(document, selection)
	client_station.call("apply_server_state", {
		"catalog_document": document,
		"selection_indices_by_player_id": {player_id: selection},
		"summaries_by_player_id": {player_id: summary},
		"status_by_player_id": {},
	})
	var preview_visual := client_station.get("preview_visual") as Node3D
	_expect(
		preview_visual != null
		and preview_visual.get_node_or_null("Barrel3") != null
		and client_station.get("terminal_view") != null,
		"replicated local selection drives both the reel UI and rotating physical preview"
	)
	client_station.call("apply_server_state", {
		"catalog_document": document,
		"selection_indices_by_player_id": {player_id: selection},
		"summaries_by_player_id": {player_id: summary},
		"status_by_player_id": {},
	})
	_expect(
		client_station.get("preview_visual") == preview_visual,
		"unchanged snapshots reuse the preview and terminal tree instead of allocating them again"
	)
	var server_world := load("res://scenes/server/server_world.tscn") as PackedScene
	var client_world := load("res://scenes/proxy/world.tscn") as PackedScene
	var server_world_instance := server_world.instantiate()
	var client_world_instance := client_world.instantiate()
	_expect(
		server_world_instance.get_node_or_null("WeaponCraftingStation") != null
		and client_world_instance.get_node_or_null("WeaponCraftingStation") != null,
		"the authoritative and rendered game worlds place the same crafting station"
	)
	server_world_instance.free()
	client_world_instance.free()
	var replication_source := FileAccess.get_file_as_string(
		"res://scripts/network/server_replication_service.gd"
	)
	var client_source := FileAccess.get_file_as_string("res://scripts/client/client.gd")
	_expect(
		replication_source.contains("on_weapon_crafting_station_states_received")
		and client_source.contains("on_weapon_crafting_station_states_received"),
		"station selections replicate through the established server/client snapshot boundary"
	)
	_test_authoritative_payout(server_station, document, selection)
	server_station.queue_free()
	client_station.queue_free()


func _test_authoritative_payout(
	server_station: Node3D,
	document: Dictionary,
	selection: Array[int]
) -> void:
	var server := root.get_node_or_null("Server")
	if server == null:
		_fail("autoload authority exists for physical fabricator payout")
		return
	var previous_world: Variant = server.get("server_world")
	var payout_world := Node3D.new()
	payout_world.name = "WeaponPayoutTestWorld"
	root.add_child(payout_world)
	server.set("server_world", payout_world)
	var player_scene := load("res://scenes/server/server_player.tscn") as PackedScene
	var player := player_scene.instantiate() as ServerPlayer
	root.add_child(player)
	player.setup(905, Vector3.ZERO)
	_expect(
		bool(server.call("_is_near_priority_primary_interaction", player))
		and bool(server_station.call("prefers_primary_action_over_weapon"))
		and bool(server_station.call(
			"should_prioritize_primary_action",
			player,
			{"position": Vector3(-0.5, 1.72, -1.045)}
		))
		and not bool(server_station.call(
			"should_prioritize_primary_action",
			player,
			{"position": Vector3(1.43, 0.42, -1.15)}
		)),
		"only the nearby reel screen takes click priority, without adding weapon raycasts elsewhere"
	)
	server_station.set(
		"selection_indices_by_player_id",
		{player.player_id: selection}
	)
	server_station.call("_refresh_summary", player.player_id)
	server_station.call("_craft_for_player", player)
	var item_values: Array = (server.get("server_items_by_item_id") as Dictionary).values()
	var payout := item_values.back() as Node if not item_values.is_empty() else null
	var payout_build: GunBuild = null
	var payout_definition := (
		payout.get("definition") as GunItemDefinition
		if payout != null
		else null
	)
	if payout_definition != null:
		payout_build = payout_definition.get_build(
			payout.call("serialize_instance_state")
		)
	_expect(
		payout != null
		and payout_definition != null
		and payout_definition.resource_path
		== WeaponCraftingCatalog.CRAFTED_WEAPON_PATH
		and payout_build != null
		and payout_build.get_barrel_count() == 3
		and payout_build.is_compatible(),
		"server payout creates a physical, pickup-ready item with the selected repeated build"
	)
	var projectile_count_before := (
		server.get("server_projectiles_by_id") as Dictionary
	).size()
	var stored_payout := (
		player.try_store_inventory_entry(payout.call("to_inventory_entry"))
		if payout != null
		else false
	)
	server.call("try_primary_action", player)
	var projectile_count_after := (
		server.get("server_projectiles_by_id") as Dictionary
	).size()
	_expect(
		stored_payout and projectile_count_after == projectile_count_before + 3,
		"the complete authority path spawns one replicated projectile for every fabricated muzzle"
	)
	var projectile_ids: Array = (
		server.get("server_projectiles_by_id") as Dictionary
	).keys()
	for projectile_id_value: Variant in projectile_ids:
		server.call("despawn_projectile", int(projectile_id_value))
	if payout != null:
		payout.free()
	player.free()
	server.set("server_world", previous_world)
	payout_world.free()


func _make_ridiculous_selection(
	document: Dictionary,
	base_selection: Array[int]
) -> Array[int]:
	var result := base_selection.duplicate()
	_set_lane_path(document, result, "receiver", RIFLE_RECEIVER)
	_set_lane_path(document, result, "barrel_0", RIFLE_BARREL)
	_set_lane_path(document, result, "barrel_1", RIFLE_BARREL)
	_set_lane_path(document, result, "barrel_2", RIFLE_BARREL)
	_set_lane_path(document, result, "magazine", RIFLE_MAGAZINE)
	_set_lane_path(document, result, "ammunition", RIFLE_AMMUNITION)
	return result


func _set_lane_path(
	document: Dictionary,
	selection: Array[int],
	lane_id: String,
	definition_path: String
) -> void:
	var lanes: Array = document.get("lanes", [])
	for lane_index: int in range(lanes.size()):
		var lane: Dictionary = lanes[lane_index]
		if str(lane.get("lane_id", "")) != lane_id:
			continue
		var options: Array = lane.get("options", [])
		for option_index: int in range(options.size()):
			if str(options[option_index].get("definition_path", "")) == definition_path:
				selection[lane_index] = option_index
				return
		_fail("catalog lane %s exposes %s" % [lane_id, definition_path.get_file()])


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	failure_count += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if failure_count == 0:
		print("Weapon crafting station tests: %d passed" % assertion_count)
		quit(0)
	else:
		push_error(
			"Weapon crafting station tests: %d/%d failed"
			% [failure_count, assertion_count]
		)
		quit(1)
