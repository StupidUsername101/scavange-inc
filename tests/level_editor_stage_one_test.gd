extends SceneTree

const EDITOR_SCENE_PATH := "res://scenes/UI/level_editor.tscn"
const TEST_ASSET := (
	"res://assets/third_party/pizza_doggy/models/nature/stone_2.glb"
)
const TEST_HOLLOW_TUNNEL := (
	"res://assets/third_party/pizza_doggy/models/bunkers/tunnel_straight.glb"
)
const TEST_OFFSET_NATURE_ASSET := (
	"res://assets/environment/PSX Nature v1.7.3/PSX Nature (Tree branches separated)/Models/GLB (recommended)/tree_8.glb"
)
const RAW_VAULT_TEST_ASSETS := [
	"res://assets/environment/Modular Retro FPS Kit/Models/other-formats/GLB/doorway_slim_1.glb",
	"res://assets/environment/PSX Bunkers/Models/other-formats/GLB/kids_computer_1.glb",
	"res://assets/environment/PSX Tech/Models/GLB (recommended)/lever_etx_4.glb",
	"res://assets/environment/PSX Nature v1.7.3/PSX Nature/Models/GLB/wheat_1_1.glb",
	"res://assets/environment/PSX Mega Pack/Models/GLB (recommended)/Items & Weapons/key_mp_3_1.glb",
	"res://assets/environment/PSX Mega Pack II v1.8/PSX Mega Pack II/Models/GLB (recommended)/Large Props & Machinery/shipping_container_mx_1_hollow_1_1.glb",
]
const TEST_SAVE := "res://tests/__stage_one_regression.json"
const TEST_FAVORITES_SAVE := "res://tests/__asset_favorites_regression.cfg"
const TEST_ASSEMBLY_SAVE := "res://tests/__asset_assemblies_regression.json"
const ASSET_SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")
const PREVIEW_FRAMING := preload("res://scripts/level_editor/level_asset_preview_framing.gd")
const FAVORITES_STORE := preload("res://scripts/level_editor/level_asset_favorites.gd")
const ASSEMBLY_STORE := preload("res://scripts/level_editor/level_asset_assembly_store.gd")
const AUTHORED_ITEM_DEFINITION := preload(
	"res://scripts/level_editor/authored_level_item_definition.gd"
)
const GAMEPLAY_RUNTIME_BUILDER := preload(
	"res://scripts/level_editor/level_gameplay_runtime_builder.gd"
)
const LIGHT_AUTHORING := preload(
	"res://scripts/level_editor/level_light_authoring.gd"
)
const LIGHT_RUNTIME_BUILDER := preload(
	"res://scripts/level_editor/level_light_runtime_builder.gd"
)
const BUILDING_KITS := preload(
	"res://scripts/level_editor/level_building_kit_catalog.gd"
)
const BUILDING_SHELL_GENERATOR := preload(
	"res://scripts/level_editor/level_building_shell_generator.gd"
)
const MATCHED_WALL := "res://assets/environment/PSX Mega Pack II v1.8/PSX Mega Pack II/Models/GLB (recommended)/Modular Structures/wall_hr_1.glb"
const MATCHED_DOORWAY := "res://assets/environment/PSX Mega Pack II v1.8/PSX Mega Pack II/Models/GLB (recommended)/Modular Structures/doorway_hr_1.glb"

var assertion_count := 0
var failure_count := 0
var captured_runtime_items: Array[ServerItem] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_contract()
	_test_building_kit_workflow()
	_test_preview_framing()
	_test_favorite_storage()
	_test_assembly_storage()
	_test_source_vault_instantiation()
	_test_detached_nature_pivot_normalization()
	_test_hollow_asset_picking()
	_test_document_round_trip()
	_test_authored_item_runtime_contract()
	await _test_runtime_editor()
	_test_main_menu_entry()
	_cleanup()
	if failure_count == 0:
		print("Level editor Stage 1 tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Level editor Stage 1 tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_catalog_contract() -> void:
	var catalog := LevelAssetCatalog.entries(true)
	var paths: Dictionary[String, bool] = {}
	var all_glb := true
	for entry: Dictionary in catalog:
		var path := str(entry.get("asset_path", ""))
		if path.get_extension().to_lower() != "glb" or paths.has(path):
			all_glb = false
		paths[path] = true
	_expect(
		catalog.size() >= 1400 and paths.size() == catalog.size() and all_glb,
		"the runtime catalog exposes one valid preferred GLB entry per bundled model"
	)
	_expect(
		not paths.has("res://assets/models/wooden-table.glb"),
		"catalog validation rejects truncated GLBs before the user can select them"
	)
	var filtered := LevelAssetCatalog.filter_entries(catalog, "pine tree")
	_expect(
		not filtered.is_empty()
		and str(filtered[0].get("search_text", "")).contains("pine tree"),
		"catalog search matches normalized display names without loading model scenes"
	)
	_expect(
		LevelAssetCatalog.category_names(catalog).size() >= 12
		and LevelAssetCatalog.category_names(catalog)[0]
		== LevelAssetCatalog.CATEGORY_WALLS
		and LevelAssetCatalog.category_names(catalog).has(
			LevelAssetCatalog.CATEGORY_NATURE
		),
		"the large bundle is divided into workflow-ordered functional categories"
	)
	var nature_entries := LevelAssetCatalog.filter_entries(
		catalog,
		"",
		LevelAssetCatalog.CATEGORY_NATURE
	)
	var nature_subcategories: Dictionary[String, bool] = {}
	var all_nature_paths_valid := true
	for entry: Dictionary in nature_entries:
		nature_subcategories[str(entry.get("subcategory", ""))] = true
		if not LevelAssetCatalog.is_valid_asset_path(
			str(entry.get("asset_path", ""))
		):
			all_nature_paths_valid = false
	_expect(
		nature_entries.size() >= 100
		and all_nature_paths_valid
		and nature_subcategories.has("Trees & Logs")
		and nature_subcategories.has("Plants & Ground Cover")
		and nature_subcategories.has("Rocks & Terrain"),
		"all nature GLBs are exposed through one category with useful grid subgroups"
	)
	var folder_metadata_valid := true
	for entry: Dictionary in catalog:
		if (
			str(entry.get("folder_path", "")).is_empty()
			or str(entry.get("folder_name", "")).is_empty()
		):
			folder_metadata_valid = false
			break
	_expect(
		folder_metadata_valid,
		"every catalog asset carries its source-folder grouping metadata"
	)
	var wall_index := -1
	var doorway_index := -1
	for index: int in range(catalog.size()):
		var entry_path := str(catalog[index].get("asset_path", ""))
		if entry_path == MATCHED_WALL:
			wall_index = index
		elif entry_path == MATCHED_DOORWAY:
			doorway_index = index
	var wall_entry: Dictionary = catalog[wall_index] if wall_index >= 0 else {}
	var doorway_entry: Dictionary = (
		catalog[doorway_index] if doorway_index >= 0 else {}
	)
	_expect(
		wall_index >= 0
		and doorway_index >= 0
		and wall_entry.get("category", "") == LevelAssetCatalog.CATEGORY_WALLS
		and doorway_entry.get("category", "") == LevelAssetCatalog.CATEGORY_WALLS
		and wall_entry.get("building_kit", "") == "HR"
		and doorway_entry.get("building_kit", "") == "HR"
		and wall_entry.get("building_socket", &"")
		== BUILDING_KITS.SOCKET_WALL_SEGMENT
		and doorway_entry.get("building_socket", &"")
		== BUILDING_KITS.SOCKET_WALL_SEGMENT,
		"matching walls and openings expose one explicit kit and replacement socket"
	)


func _test_building_kit_workflow() -> void:
	var catalog := LevelAssetCatalog.entries()
	var compatible := BUILDING_KITS.compatible_entries(
		catalog,
		"HR",
		BUILDING_KITS.SOCKET_WALL_SEGMENT
	)
	var compatible_paths: Dictionary[String, bool] = {}
	for entry: Dictionary in compatible:
		compatible_paths[str(entry.get("asset_path", ""))] = true
	var default_floor := BUILDING_KITS.default_entry(
		catalog,
		"HR",
		BUILDING_KITS.ROLE_FLOOR
	)
	var default_roof := BUILDING_KITS.default_entry(
		catalog,
		"HR",
		BUILDING_KITS.ROLE_ROOF
	)
	var hs_shell_floor := BUILDING_KITS.default_entry(
		catalog,
		"HS",
		BUILDING_KITS.ROLE_FLOOR
	)
	_expect(
		compatible_paths.has(MATCHED_WALL)
		and compatible_paths.has(MATCHED_DOORWAY)
		and not default_floor.is_empty()
		and not default_roof.is_empty()
		and not str(hs_shell_floor.get("asset_path", "")).contains("slope"),
		"kit metadata supplies compatible openings plus ordinary floor and roof assets"
	)
	var actual_wall_bounds := LevelAssetPlacement.asset_bounds(MATCHED_WALL)
	var actual_floor_bounds := LevelAssetPlacement.asset_bounds(
		str(default_floor.get("asset_path", ""))
	)
	var actual_roof_bounds := LevelAssetPlacement.asset_bounds(
		str(default_roof.get("asset_path", ""))
	)
	_expect(
		actual_wall_bounds.size.length_squared() > 0.001
		and actual_floor_bounds.size.length_squared() > 0.001
		and actual_roof_bounds.size.length_squared() > 0.001
		and BUILDING_SHELL_GENERATOR.horizontal_span(actual_wall_bounds) > 0.1,
		"room generation reads usable dimensions from the real bundled kit meshes"
	)

	var wall_bounds := AABB(
		Vector3(-2.0, 0.0, -0.1),
		Vector3(4.0, 3.0, 0.2)
	)
	var slab_bounds := AABB(
		Vector3(-2.0, 0.0, -2.0),
		Vector3(4.0, 0.2, 4.0)
	)
	var generated := BUILDING_SHELL_GENERATOR.generate(
		Vector3.ZERO,
		Vector3(8.0, 0.0, 8.0),
		0.0,
		MATCHED_WALL,
		wall_bounds,
		str(default_floor.get("asset_path", "")),
		slab_bounds,
		str(default_roof.get("asset_path", "")),
		slab_bounds,
		true,
		7,
		2
	)
	var wall_count := 0
	var floor_height_count := 0
	var roof_height_count := 0
	var metadata_valid := true
	for snapshot: Dictionary in generated:
		if int(snapshot.get("building_group_id", 0)) != 7:
			metadata_valid = false
		if int(snapshot.get("building_storey", -1)) != 2:
			metadata_valid = false
		if snapshot.get("gameplay_role", &"") != (
			LevelEditorDocument.PLACEMENT_ROLE_STATIC
		):
			metadata_valid = false
		if str(snapshot.get("asset_path", "")) == MATCHED_WALL:
			wall_count += 1
		elif is_equal_approx(
			(snapshot.get("position", Vector3.ZERO) as Vector3).y,
			0.0
		):
			floor_height_count += 1
		else:
			roof_height_count += 1
	_expect(
		generated.size() == 16
		and wall_count == 8
		and floor_height_count == 4
		and roof_height_count == 4
		and metadata_valid,
		"room-shell generation closes four modular edges and tiles a reusable floor and roof"
	)

	var left_pose := BUILDING_SHELL_GENERATOR.pose_with_base_center(
		MATCHED_WALL,
		wall_bounds,
		Vector3.ZERO,
		Vector3.RIGHT
	)
	var right_pose := BUILDING_SHELL_GENERATOR.pose_with_base_center(
		MATCHED_WALL,
		wall_bounds,
		Vector3(4.0, 0.0, 0.0),
		Vector3.RIGHT
	)
	var left_anchors := BUILDING_SHELL_GENERATOR.socket_anchors(
		Transform3D(
			Basis.from_euler(left_pose["rotation"]),
			left_pose["position"]
		),
		wall_bounds,
		BUILDING_KITS.SOCKET_WALL_SEGMENT
	)
	var right_anchors := BUILDING_SHELL_GENERATOR.socket_anchors(
		Transform3D(
			Basis.from_euler(right_pose["rotation"]),
			right_pose["position"]
		),
		wall_bounds,
		BUILDING_KITS.SOCKET_WALL_SEGMENT
	)
	_expect(
		left_anchors.size() == 2
		and right_anchors.size() == 2
		and left_anchors[1].is_equal_approx(right_anchors[0]),
		"dimension-derived wall sockets meet without a hard-coded pack grid"
	)


func _test_source_vault_instantiation() -> void:
	var valid_count := 0
	for asset_path: String in RAW_VAULT_TEST_ASSETS:
		var instance: Node3D = ASSET_SCENE_LOADER.instantiate(asset_path)
		if instance != null:
			var bounds := LevelAssetPlacement.calculate_visual_bounds(instance)
			if bounds.size.is_finite() and bounds.size.length_squared() > 0.0:
				valid_count += 1
			instance.free()
	_expect(
		valid_count == RAW_VAULT_TEST_ASSETS.size(),
		"ignored commercial source vaults instantiate through the runtime GLB loader"
	)


func _test_detached_nature_pivot_normalization() -> void:
	var placement := LevelAssetPlacement.new()
	root.add_child(placement)
	var configured := placement.configure(91_000, TEST_OFFSET_NATURE_ASSET)
	var bounds := placement.local_bounds
	var center := bounds.get_center()
	_expect(
		configured
		and is_zero_approx(bounds.position.y)
		and absf(center.x) <= 0.001
		and absf(center.z) <= 0.001
		and bounds.size.y > bounds.size.z,
		"nature source assets with collection-scene offsets are upright and anchored under the placement cursor"
	)
	placement.free()


func _test_hollow_asset_picking() -> void:
	var tunnel := LevelAssetPlacement.new()
	root.add_child(tunnel)
	var configured := tunnel.configure(91_001, TEST_HOLLOW_TUNNEL)
	var found_open_ray := false
	if configured and tunnel.surface_bvh != null:
		var bounds := tunnel.local_bounds
		var center := bounds.get_center()
		for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
			var axis_extent := bounds.size.x if absf(axis.x) > 0.5 else bounds.size.z
			for height_ratio: float in [0.3, 0.45, 0.6]:
				var ray_center := center
				ray_center.y = bounds.position.y + bounds.size.y * height_ratio
				var ray_origin := ray_center - axis * (axis_extent + 2.0)
				var aabb_hit: Variant = bounds.intersects_ray(ray_origin, axis)
				var precise_hit := tunnel.surface_ray_hit(ray_origin, axis)
				if (
					aabb_hit is Vector3
					and (
						precise_hit.normal.length_squared() <= 0.000001
						or not is_finite(precise_hit.d)
					)
				):
					found_open_ray = true
					break
			if found_open_ray:
				break
	_expect(
		configured and tunnel.surface_bvh != null and found_open_ray,
		"hollow tunnel openings remain open to placement rays instead of becoming solid AABB caps"
	)
	tunnel.free()


func _test_preview_framing() -> void:
	var wall_bounds := AABB(
		Vector3(-3.0, -1.5, -0.08),
		Vector3(6.0, 3.0, 0.16)
	)
	var wall_direction: Vector3 = PREVIEW_FRAMING.camera_direction(wall_bounds)
	_expect(
		absf(wall_direction.z) > 0.95
		and absf(wall_direction.x) < 0.25,
		"thin walls are previewed broad-face instead of edge-on"
	)
	var floor_direction: Vector3 = PREVIEW_FRAMING.camera_direction(
		AABB(Vector3(-2.0, -0.04, -2.0), Vector3(4.0, 0.08, 4.0))
	)
	_expect(
		floor_direction.y > 0.94,
		"flat horizontal assets receive a readable mostly top-down preview"
	)


func _test_favorite_storage() -> void:
	var favorites: Dictionary[String, bool] = {
		TEST_ASSET: true,
		MATCHED_WALL: true,
	}
	var save_error: Error = FAVORITES_STORE.save_paths(
		favorites,
		TEST_FAVORITES_SAVE
	)
	var restored: Dictionary[String, bool] = FAVORITES_STORE.load_paths(
		TEST_FAVORITES_SAVE
	)
	_expect(
		save_error == OK
		and restored.size() == 2
		and restored.has(TEST_ASSET)
		and restored.has(MATCHED_WALL),
		"asset favorites persist as a compact path set across editor sessions"
	)


func _test_assembly_storage() -> void:
	var snapshots: Array[Dictionary] = [
		{
			"id": 1,
			"asset_path": MATCHED_WALL,
			"position": Vector3(-1.0, 0.0, 0.0),
			"rotation": Vector3.ZERO,
			"scale": Vector3.ONE,
			"acoustic_boundary": true,
		},
		{
			"id": 2,
			"asset_path": MATCHED_DOORWAY,
			"position": Vector3(1.0, 0.0, 0.0),
			"rotation": Vector3(0.0, PI * 0.5, 0.0),
			"scale": Vector3.ONE,
			"acoustic_boundary": false,
			"gameplay_role": LevelEditorDocument.PLACEMENT_ROLE_VALUABLE,
			"item_mass_kg": 8.5,
			"value_per_mass": 14.0,
		},
	]
	var definition := ASSEMBLY_STORE.create_definition(
		"Door Wall",
		snapshots,
		Vector3.ZERO
	)
	var definitions: Dictionary[String, Dictionary] = {}
	definitions[str(definition.get("id", ""))] = definition
	var save_error: Error = ASSEMBLY_STORE.save_definitions(
		definitions,
		TEST_ASSEMBLY_SAVE
	)
	var restored: Dictionary[String, Dictionary] = (
		ASSEMBLY_STORE.load_definitions(TEST_ASSEMBLY_SAVE)
	)
	var restored_definition: Dictionary = restored.get(
		str(definition.get("id", "")),
		{}
	)
	var restored_parts: Array = restored_definition.get("parts", [])
	_expect(
		save_error == OK
		and restored.size() == 1
		and restored_parts.size() == 2
		and (restored_parts[0] as Dictionary).get("position", Vector3.ZERO)
		== Vector3(-1.0, 0.0, 0.0)
		and not bool((restored_parts[1] as Dictionary).get(
			"acoustic_boundary",
			true
		))
		and (restored_parts[1] as Dictionary).get("gameplay_role")
		== LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		and is_equal_approx(
			float((restored_parts[1] as Dictionary).get("item_mass_kg", 0.0)),
			8.5
		)
		and is_equal_approx(
			float((restored_parts[1] as Dictionary).get("value_per_mass", 0.0)),
			14.0
		),
		"reusable assemblies preserve transforms, acoustics, item roles, mass, and loot rates"
	)
func _test_document_round_trip() -> void:
	var generated_positions := LevelAcousticAuthoring.automatic_ground_probe_positions(
		[
			AABB(Vector3(-4.0, 0.0, -4.0), Vector3(8.0, 0.25, 8.0)),
			AABB(Vector3(-3.0, 3.0, -3.0), Vector3(6.0, 0.25, 6.0)),
		],
		2.0,
		1.7,
		128
	)
	var has_upper_floor_probe := false
	for generated_position: Vector3 in generated_positions:
		if generated_position.y > 4.0:
			has_upper_floor_probe = true
			break
	_expect(
		not generated_positions.is_empty() and has_upper_floor_probe,
		"automatic sound-field placement covers broad elevated floors while remaining sparse"
	)
	var document := LevelEditorDocument.new()
	document.level_name = "Stage One Regression"
	var building_group_id := document.allocate_building_group_id()
	document.placements.append({
		"id": document.allocate_placement_id(),
		"asset_path": TEST_ASSET,
		"position": Vector3(1.25, 0.5, -3.0),
		"rotation": Vector3(0.0, 0.75, 0.0),
		"scale": Vector3(1.2, 0.8, 1.2),
		"acoustic_boundary": false,
		"gameplay_role": LevelEditorDocument.PLACEMENT_ROLE_VALUABLE,
		"item_mass_kg": 6.25,
		"value_per_mass": 12.0,
		"assembly_group_id": document.allocate_assembly_group_id(),
		"assembly_definition_id": "door_wall_fixture",
		"building_group_id": building_group_id,
		"building_storey": 3,
	})
	var probe_a_id := document.allocate_acoustic_id()
	var probe_b_id := document.allocate_acoustic_id()
	document.acoustic_probes.append({
		"id": probe_a_id,
		"position": Vector3(0.0, 1.7, -1.0),
		"authored": true,
	})
	document.acoustic_probes.append({
		"id": probe_b_id,
		"position": Vector3(0.0, 1.7, 1.0),
		"authored": true,
	})
	document.acoustic_portals.append({
		"id": document.allocate_acoustic_id(),
		"probe_a_id": probe_a_id,
		"probe_b_id": probe_b_id,
		"profile": "vent",
	})
	var sound_system := LevelSpeakerSystemAuthoring.create_system(
		document.allocate_sound_system_id(),
		"Warehouse Test PA",
		[
			{
				"position": Vector3(-3.0, 2.4, 1.0),
				"rotation": Vector3(0.0, 0.25, 0.0),
				"is_indoor": true,
			},
			{
				"position": Vector3(3.0, 2.4, 1.0),
				"rotation": Vector3(0.0, -0.25, 0.0),
				"is_indoor": true,
			},
		]
	)
	document.sound_systems.append(sound_system)
	document.authored_lights.append(LIGHT_AUTHORING.create_descriptor(
		document.allocate_light_id(),
		LIGHT_AUTHORING.TYPE_SPOT,
		Vector3(2.0, 3.0, -4.0),
		Vector3(-0.4, 0.25, 0.0),
		"Loading Bay Spot"
	))
	var save_error := document.save_to_path(TEST_SAVE)
	var loaded := LevelEditorDocument.load_from_path(TEST_SAVE)
	_expect(
		save_error == OK
		and loaded != null
		and loaded.level_name == document.level_name
		and loaded.placements.size() == 1
		and loaded.acoustic_probes.size() == 2
		and loaded.acoustic_portals.size() == 1
		and loaded.sound_systems.size() == 1
		and loaded.authored_lights.size() == 1
		and loaded.next_sound_system_id == 2,
		"versioned level JSON saves and loads through the user data directory"
	)
	if loaded != null and not loaded.sound_systems.is_empty():
		var restored_system: Dictionary = loaded.sound_systems[0]
		var restored_speakers := (
			LevelSpeakerSystemAuthoring.world_speaker_descriptors(restored_system)
		)
		_expect(
			str(restored_system.get("display_name", "")) == "Warehouse Test PA"
			and restored_speakers.size() == 2
			and (restored_speakers[0].get("position", Vector3.ZERO) as Vector3)
			.is_equal_approx(Vector3(-3.0, 2.4, 1.0))
			and (restored_speakers[1].get("position", Vector3.ZERO) as Vector3)
			.is_equal_approx(Vector3(3.0, 2.4, 1.0)),
			"PA arrays preserve arbitrary speaker transforms around one compact shared origin"
		)
	if loaded != null and not loaded.placements.is_empty():
		var placement: Dictionary = loaded.placements[0]
		_expect(
			(placement.get("position", Vector3.INF) as Vector3).is_equal_approx(
				Vector3(1.25, 0.5, -3.0)
			)
			and (placement.get("scale", Vector3.ZERO) as Vector3).is_equal_approx(
				Vector3(1.2, 0.8, 1.2)
			)
			and not bool(placement.get("acoustic_boundary", true)),
			"placement transforms and sound-boundary role survive value-only JSON serialization"
		)
		_expect(
			placement.get("gameplay_role")
			== LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
			and is_equal_approx(float(placement.get("item_mass_kg", 0.0)), 6.25)
			and is_equal_approx(float(placement.get("value_per_mass", 0.0)), 12.0),
			"valuable role, physical mass, and value-per-mass survive level JSON"
		)
		_expect(
			int(placement.get("assembly_group_id", 0)) == 1
			and str(placement.get("assembly_definition_id", ""))
			== "door_wall_fixture"
			and loaded.next_assembly_group_id == 2,
			"reusable assembly membership survives level save and load"
		)
		_expect(
			int(placement.get("building_group_id", 0)) == 1
			and int(placement.get("building_storey", -1)) == 3
			and loaded.next_building_group_id == 2,
			"generated room identity and storey survive level save and load"
		)
	var runtime_root := Node3D.new()
	var runtime_report := LevelAcousticRuntimeBuilder.build_into(
		runtime_root,
		loaded.acoustic_probes,
		loaded.acoustic_portals,
		"RoundTrip"
	)
	var runtime_portal := runtime_root.get_node_or_null("RoundTripAcousticPortal003") as AcousticPortal3D
	_expect(
		bool(runtime_report.get("valid", false))
		and runtime_root.get_child_count() == 3
		and runtime_portal != null
		and runtime_portal.get_probe_a() != null
		and runtime_portal.get_probe_b() != null
		and runtime_portal.modifier != null,
		"saved probes and portal profiles construct the real runtime acoustic node types"
	)
	runtime_root.free()
	var light_runtime_root := Node3D.new()
	var runtime_lights := LIGHT_RUNTIME_BUILDER.build_into(
		light_runtime_root,
		loaded.authored_lights,
		"RoundTripLights"
	)
	var restored_spot := (
		runtime_lights[0] as SpotLight3D
		if runtime_lights.size() == 1 and runtime_lights[0] is SpotLight3D
		else null
	)
	_expect(
		restored_spot != null
		and restored_spot.position.is_equal_approx(Vector3(2.0, 3.0, -4.0))
		and restored_spot.shadow_enabled
		and is_equal_approx(restored_spot.spot_range, 12.0),
		"authored light descriptors round-trip into real runtime Light3D nodes"
	)
	light_runtime_root.free()


func _test_authored_item_runtime_contract() -> void:
	var valuable_placement := {
		"id": 44,
		"asset_path": TEST_ASSET,
		"position": Vector3(3.0, 1.0, -2.0),
		"rotation": Vector3(0.0, 0.4, 0.0),
		"scale": Vector3(0.8, 1.1, 0.9),
		"gameplay_role": LevelEditorDocument.PLACEMENT_ROLE_VALUABLE,
		"item_mass_kg": 7.5,
		"value_per_mass": 16.0,
	}
	var definition := AUTHORED_ITEM_DEFINITION.new()
	var configured: bool = definition.configure_from_placement(
		valuable_placement,
		true
	)
	var descriptor: Dictionary = definition.to_network_descriptor()
	var remote_definition := AUTHORED_ITEM_DEFINITION.new()
	var remote_configured: bool = (
		remote_definition.configure_from_network_descriptor(descriptor)
	)
	var remote_visual: Node3D = (
		remote_definition.instantiate_visual()
		if remote_configured
		else null
	)
	_expect(
		configured
		and definition.collision_shape is ConvexPolygonShape3D
		and definition.economy_category == ItemDefinition.EconomyCategory.VALUABLE
		and is_equal_approx(definition.get_instance_total_value({}), 120.0)
		and remote_configured
		and remote_visual != null
		and remote_definition.source_asset_path == TEST_ASSET
		and remote_definition.authored_scale.is_equal_approx(Vector3(0.8, 1.1, 0.9))
		and is_equal_approx(remote_definition.get_instance_total_value({}), 120.0),
		"authored valuables build collision and replicate their asset, scale, mass, and economy without a generated tres"
	)
	if remote_visual != null:
		remote_visual.free()
	captured_runtime_items.clear()
	var placements: Array[Dictionary] = [
		valuable_placement,
		{
			"id": 45,
			"asset_path": MATCHED_WALL,
			"position": Vector3.ZERO,
			"rotation": Vector3.ZERO,
			"scale": Vector3.ONE,
			"gameplay_role": LevelEditorDocument.PLACEMENT_ROLE_STATIC,
		},
	]
	var spawned := GAMEPLAY_RUNTIME_BUILDER.spawn_placement_items(
		placements,
		Callable(self, "_capture_runtime_item_spawn")
	)
	var state := spawned[0].to_state_dict() if not spawned.is_empty() else {}
	var proxy := ItemProxy.new()
	root.add_child(proxy)
	if not state.is_empty():
		proxy.from_server_state(state)
	var proxy_definition := (
		proxy.item_definition as AuthoredLevelItemDefinition
		if proxy.item_definition is AuthoredLevelItemDefinition
		else null
	)
	_expect(
		spawned.size() == 1
		and int(spawned[0].get_meta("authored_level_placement_id", 0)) == 44
		and state.has("authored_level_item")
		and is_equal_approx(float(state.get("mass_kg", 0.0)), 7.5)
		and is_equal_approx(float(state.get("total_value", 0.0)), 120.0)
		and proxy_definition != null
		and proxy_definition.source_asset_path == TEST_ASSET
		and proxy.visual != null,
		"the authoritative runtime builder ignores static geometry and emits marked assets through ServerItem state"
	)
	proxy.free()
	for item: ServerItem in captured_runtime_items:
		item.free()
	captured_runtime_items.clear()


func _capture_runtime_item_spawn(
	definition: ItemDefinition,
	item_transform: Transform3D
) -> ServerItem:
	var item := ServerItem.new()
	item.definition = definition
	item.transform = item_transform
	root.add_child(item)
	captured_runtime_items.append(item)
	return item


func _test_runtime_editor() -> void:
	var editor_scene := load(EDITOR_SCENE_PATH) as PackedScene
	var editor := editor_scene.instantiate()
	editor.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	editor.size = Vector2(1600.0, 900.0)
	root.add_child(editor)
	await process_frame
	await process_frame
	_expect(
		editor.asset_list != null
		and editor.asset_list.item_count > editor.catalog.size()
		and editor.catalog_item_indices_by_path.size() == editor.catalog.size()
		and editor.viewport_container.size.x > 100.0
		and editor.preview.size.x > 100.0
		and editor.thumbnail_renderer != null
		and editor.used_assets_row != null,
		"the editor opens with its folder browser, thumbnail renderer, used strip, and 3D preview"
	)
	_expect(
		editor.preview_tabs != null
		and editor.preview_tabs.get_tab_count() == 2
		and editor.preview_tabs.get_tab_title(editor.light_tab_index) == "LIGHTS"
		and editor.light_place_button != null,
		"the preview window exposes a dedicated authored-light tab"
	)
	editor.call("_toggle_building_mode")
	var building_catalog_valid: bool = not editor.filtered_catalog.is_empty()
	for building_entry: Dictionary in editor.filtered_catalog:
		if str(building_entry.get("building_kit", "")).is_empty():
			building_catalog_valid = false
			break
	_expect(
		editor.building_controls.visible
		and editor.building_kit_filter.item_count >= 3
		and editor.building_role_filter.item_count >= 6
		and editor.building_socket_snap_button.button_pressed
		and building_catalog_valid,
		"BUILD mode exposes kit and role filters while excluding unrelated props"
	)
	editor.call("_toggle_building_mode")
	var folder_header_count := 0
	for item_index: int in range(editor.asset_list.item_count):
		if not editor.asset_list.is_item_selectable(item_index):
			folder_header_count += 1
	_expect(
		folder_header_count > 1,
		"catalog rows are visibly separated by their real source folders"
	)
	_expect(
		editor.asset_list.icon_mode == ItemList.ICON_MODE_TOP
		and editor.catalog_grid_columns >= 2
		and editor.asset_list.max_columns == editor.catalog_grid_columns,
		"the default catalog presents assets as a responsive thumbnail grid"
	)
	var nature_option_index := -1
	for option_index: int in range(editor.category_filter.item_count):
		if str(editor.category_filter.get_item_metadata(option_index)) == (
			LevelAssetCatalog.CATEGORY_NATURE
		):
			nature_option_index = option_index
			break
	if nature_option_index >= 0:
		editor.category_filter.select(nature_option_index)
		editor.call("_on_category_selected", nature_option_index)
	var nature_filter_only: bool = not editor.filtered_catalog.is_empty()
	for entry: Dictionary in editor.filtered_catalog:
		if str(entry.get("category", "")) != LevelAssetCatalog.CATEGORY_NATURE:
			nature_filter_only = false
			break
	_expect(
		nature_option_index >= 0
		and editor.category_filter.get_item_text(nature_option_index).contains("[")
		and nature_filter_only,
		"the counted Nature filter is visible and isolates nature assets in the editor"
	)
	editor.category_filter.select(0)
	editor.call("_on_category_selected", 0)
	editor.favorites_storage_path = TEST_FAVORITES_SAVE
	editor.favorite_asset_paths.clear()
	editor.asset_list.set_favorite_paths(editor.favorite_asset_paths)
	editor.call("_on_asset_favorite_toggle_requested", TEST_ASSET)
	var stored_editor_favorites: Dictionary[String, bool] = (
		FAVORITES_STORE.load_paths(TEST_FAVORITES_SAVE)
	)
	var favorite_item_index: int = editor.catalog_item_indices_by_path.get(
		TEST_ASSET,
		-1
	)
	_expect(
		editor.favorite_asset_paths.has(TEST_ASSET)
		and editor.asset_list.is_asset_favorite(TEST_ASSET)
		and stored_editor_favorites.has(TEST_ASSET)
		and favorite_item_index >= 0
		and editor.asset_list.call(
			"_star_rect_for_item",
			favorite_item_index
		).size.x > 0.0
		and editor.category_filter.get_item_text(
			editor.favorite_filter_option_index
		).contains("[1]"),
		"asset cards expose a clickable star and update the persistent Favorites filter"
	)
	editor.asset_list.select(favorite_item_index)
	editor.asset_list.ensure_current_is_visible()
	await process_frame
	var favorite_star_center: Vector2 = editor.asset_list.call(
		"_star_rect_for_item",
		favorite_item_index
	).get_center()
	var favorite_click := InputEventMouseButton.new()
	favorite_click.button_index = MOUSE_BUTTON_LEFT
	favorite_click.pressed = true
	favorite_click.position = (
		editor.asset_list.get_global_transform_with_canvas()
		* favorite_star_center
	)
	editor.asset_list._input(favorite_click)
	_expect(
		not editor.favorite_asset_paths.has(TEST_ASSET)
		and not editor.asset_list.is_asset_favorite(TEST_ASSET),
		"favorite stars consume the press before native ItemList card selection"
	)
	editor.asset_list._input(favorite_click)
	var initial_catalog_width: float = editor.catalog_width
	var initial_thumbnail_size: Vector2i = editor.asset_list.fixed_icon_size
	editor.call("_set_catalog_width", editor.MAXIMUM_CATALOG_WIDTH)
	_expect(
		editor.catalog_width > initial_catalog_width
		and editor.catalog_panel.size.x > initial_catalog_width
		and editor.asset_list.fixed_icon_size.x > initial_thumbnail_size.x
		and editor.catalog_grid_columns >= 3
		and is_equal_approx(
			editor.viewport_container.offset_left,
			16.0 + editor.catalog_width
		),
		"drag-width state expands the catalog, thumbnails, and viewport boundary together"
	)
	var drop_data := {
		"type": &"level_asset",
		"asset_path": TEST_ASSET,
	}
	_expect(
		editor.viewport_container._can_drop_data(Vector2.ZERO, drop_data),
		"the 3D view accepts catalog drag payloads for valid project assets"
	)
	var catalog_index := -1
	for item_index: int in range(editor.asset_list.item_count):
		if str(editor.asset_list.get_item_metadata(item_index)) == TEST_ASSET:
			catalog_index = item_index
			break
	editor.call("_on_catalog_visible_range_changed", catalog_index, catalog_index)
	# The renderer may already be settling the previous visible card when a far-away favorite
	# scrolls into view. Wait for this requested asset, not an incidental fixed frame count.
	for _frame_index: int in range(48):
		if editor.thumbnail_renderer._cache.has(TEST_ASSET):
			break
		await process_frame
	_expect(
		editor.thumbnail_renderer._cache.has(TEST_ASSET)
		and editor.asset_list.get_item_icon(catalog_index)
		== editor.thumbnail_renderer.cached(TEST_ASSET),
		"visible catalog rows receive a lazily baked model thumbnail beside their name"
	)
	editor.asset_list.select(catalog_index)
	var wheel_direction := (
		MOUSE_BUTTON_WHEEL_DOWN
		if catalog_index + 1 < editor.asset_list.item_count
		else MOUSE_BUTTON_WHEEL_UP
	)
	var expected_wheel_index: int = editor.asset_list.call(
		"_next_asset_index",
		catalog_index,
		1 if wheel_direction == MOUSE_BUTTON_WHEEL_DOWN else -1
	)
	var wheel_event := InputEventMouseButton.new()
	wheel_event.button_index = wheel_direction
	wheel_event.pressed = true
	wheel_event.position = Vector2(8.0, 8.0)
	editor.asset_list._gui_input(wheel_event)
	_expect(
		editor.asset_list.get_selected_items()[0] == expected_wheel_index
		and editor.pending_asset_path
		== str(editor.asset_list.get_item_metadata(expected_wheel_index)),
		"catalog mouse wheel advances the active asset and keeps placement armed"
	)
	editor.asset_list.select(catalog_index)
	editor.call("_on_catalog_item_selected", catalog_index)
	_expect(
		not editor.snap_button.button_pressed
		and not editor.surface_align_button.button_pressed,
		"free placement is the editor default while grid and surface alignment remain optional"
	)
	var center_position: Vector2 = (
		editor.viewport_container.size * 0.5
		+ Vector2(37.0, 21.0)
	)
	var raw_ground_position: Vector3 = editor.call(
		"_screen_to_ground",
		editor.call("_viewport_pixel", center_position)
	)
	editor.call(
		"_update_placement_cursor",
		editor.call("_viewport_pixel", center_position)
	)
	var snapped_ground_position := Vector3(
		snappedf(raw_ground_position.x, float(editor.snap_step.value)),
		0.0,
		snappedf(raw_ground_position.z, float(editor.snap_step.value))
	)
	editor.snap_button.button_pressed = true
	editor.call("_toggle_snap")
	_expect(
		is_equal_approx(editor.placement_preview.position.x, snapped_ground_position.x)
		and is_equal_approx(editor.placement_preview.position.z, snapped_ground_position.z),
		"the optional grid quantizes the same live free-placement preview"
	)
	editor.snap_button.button_pressed = false
	editor.call("_toggle_snap")
	var rotate_key := InputEventKey.new()
	rotate_key.physical_keycode = KEY_R
	rotate_key.pressed = true
	editor.call("_unhandled_key_input", rotate_key)
	_expect(
		is_equal_approx(editor.placement_rotation.y, PI * 0.5)
		and is_equal_approx(editor.placement_preview.rotation.y, PI * 0.5),
		"R rotates the armed asset preview by one exact yaw quarter turn"
	)
	var fine_tilt_key := InputEventKey.new()
	fine_tilt_key.physical_keycode = KEY_X
	fine_tilt_key.shift_pressed = true
	fine_tilt_key.pressed = true
	editor.call("_unhandled_key_input", fine_tilt_key)
	_expect(
		is_equal_approx(editor.placement_rotation.x, deg_to_rad(15.0))
		and is_equal_approx(editor.placement_preview.rotation.x, deg_to_rad(15.0)),
		"Shift+X gives armed assets a fine 15-degree pitch adjustment"
	)
	var placement_click := InputEventMouseButton.new()
	placement_click.button_index = MOUSE_BUTTON_LEFT
	placement_click.pressed = true
	placement_click.position = center_position
	editor.call("_handle_viewport_button", placement_click)
	_expect(
		editor.placements_by_id.size() == 1
		and editor.selected_placement != null
		and editor.selected_placement.position.y >= 0.0
		and is_equal_approx(editor.selected_placement.rotation.y, PI * 0.5)
		and is_equal_approx(
			editor.selected_placement.position.x,
			raw_ground_position.x
		)
		and is_equal_approx(
			editor.selected_placement.position.z,
			raw_ground_position.z
		)
		and not editor.pending_asset_path.is_empty()
		and editor.placement_cursor.visible,
		"world clicks preserve the exact projected position while the grid is disabled"
	)
	_expect(
		editor.used_asset_buttons_by_path.size() == 1
		and editor.used_asset_buttons_by_path.has(TEST_ASSET)
		and editor.used_asset_buttons_by_path[TEST_ASSET].icon != null,
		"placing an asset adds one thumbnail-backed shortcut to the used-in-level bar"
	)
	var live_preview_hit: Dictionary = editor.call(
		"_screen_to_placement_hit",
		editor.call("_viewport_pixel", center_position)
	)
	var live_preview_normal: Vector3 = live_preview_hit.get("normal", Vector3.UP)
	var preview_contact: float = (
		editor.placement_preview.position.dot(live_preview_normal)
		- editor.placement_preview.surface_support_distance(live_preview_normal)
	)
	_expect(
		editor.placement_preview != null
		and editor.placement_preview.visible
		and editor.placement_preview.asset_path == TEST_ASSET
		and not live_preview_hit.is_empty()
		and is_equal_approx(
			preview_contact,
			(live_preview_hit.get("position", Vector3.ZERO) as Vector3).dot(
				live_preview_normal
			)
		),
		"the actual selected model previews flush against the pointed surface"
	)
	var base_placement: LevelAssetPlacement = editor.selected_placement
	var side_normal := Vector3.ZERO
	var side_ray_origin := Vector3.ZERO
	var side_result := Plane(Vector3.ZERO, INF)
	var mesh_faces := base_placement.surface_bvh.get_faces()
	for face_index: int in range(0, mesh_faces.size(), 3):
		var local_a := mesh_faces[face_index]
		var local_b := mesh_faces[face_index + 1]
		var local_c := mesh_faces[face_index + 2]
		var local_normal := (local_b - local_a).cross(local_c - local_a).normalized()
		if absf(local_normal.y) > 0.75:
			continue
		var face_center := base_placement.global_transform * (
			(local_a + local_b + local_c) / 3.0
		)
		var normal_basis := base_placement.global_basis.inverse().transposed()
		var candidate_normal := (normal_basis * local_normal).normalized()
		for sign_value: float in [1.0, -1.0]:
			side_ray_origin = face_center + candidate_normal * sign_value * 2.0
			side_result = base_placement.surface_ray_hit(
				side_ray_origin,
				-candidate_normal * sign_value
			)
			if (
				is_finite(side_result.d)
				and side_result.normal.length_squared() > 0.9
				and absf(side_result.normal.dot(Vector3.UP)) < 0.8
			):
				side_normal = side_result.normal
				break
		if side_normal.length_squared() > 0.9:
			break
	var side_hit := {
		"distance": side_result.d,
		"position": side_ray_origin + (
			-side_normal * side_result.d
		),
		"normal": side_result.normal,
	}
	_expect(
		is_finite(side_result.d)
		and side_normal.length_squared() > 0.9,
		"placement raycasts expose vertical and rotated faces instead of filtering them out"
	)
	editor.surface_align_button.button_pressed = true
	editor.call("_toggle_surface_alignment")
	editor.call("_apply_placement_pose", editor.placement_preview, side_hit)
	_expect(
		editor.placement_preview.global_basis.y.normalized().dot(
			side_result.normal
		) > 0.99,
		"surface alignment can orient an asset's local up axis onto walls and ceilings"
	)
	editor.surface_align_button.button_pressed = false
	editor.call("_toggle_surface_alignment")
	var resolved_stack_surface := Vector3(
		base_placement.position.x,
		base_placement.position.y
		+ base_placement.surface_support_distance(Vector3.DOWN),
		base_placement.position.z
	)
	editor.call("_place_asset", TEST_ASSET, resolved_stack_surface)
	var stacked_placement: LevelAssetPlacement = editor.selected_placement
	var stacked_contact_y := (
		stacked_placement.position.y
		- stacked_placement.surface_support_distance(Vector3.UP)
	)
	_expect(
		editor.placements_by_id.size() == 2
		and resolved_stack_surface.is_finite()
		and is_equal_approx(stacked_contact_y, resolved_stack_surface.y),
		"surface placement stacks a new asset exactly on an existing asset's top face"
	)
	editor.call("_cancel_asset_placement")
	editor.call("_set_edit_mode", editor.MODE_MOVE)
	var gizmo = editor.transform_gizmo
	var gizmo_pivot: Vector3 = gizmo.global_position
	var gizmo_scale: float = gizmo.scale.x
	var move_start_viewport: Vector2 = editor.editor_camera.unproject_position(
		gizmo_pivot + Vector3.RIGHT * gizmo_scale * 0.72
	)
	var move_end_viewport: Vector2 = editor.editor_camera.unproject_position(
		gizmo_pivot + Vector3.RIGHT * gizmo_scale * 1.62
	)
	var viewport_to_panel := Vector2(
		editor.viewport_container.size.x / float(editor.editor_viewport.size.x),
		editor.viewport_container.size.y / float(editor.editor_viewport.size.y)
	)
	var move_start_mouse: Vector2 = move_start_viewport * viewport_to_panel
	var move_end_mouse: Vector2 = move_end_viewport * viewport_to_panel
	var gizmo_move_start := stacked_placement.position
	var began_x_move: bool = editor.call(
		"_begin_transform_gizmo_drag",
		move_start_mouse,
		move_start_viewport
	)
	editor.call("_update_transform_drag", move_end_mouse)
	var gizmo_move_delta := stacked_placement.position - gizmo_move_start
	editor.call("_finish_transform_drag")
	_expect(
		gizmo.visible
		and gizmo.active_mode == gizmo.MODE_MOVE
		and gizmo.move_roots.size() == 3
		and began_x_move
		and gizmo_move_delta.x > 0.01
		and absf(gizmo_move_delta.y) < 0.001
		and absf(gizmo_move_delta.z) < 0.001,
		"the three-arrow gizmo picks X and constrains movement without leaking into Y or Z"
	)
	editor.call("_undo")
	editor.call("_set_edit_mode", editor.MODE_ROTATE)
	gizmo_pivot = gizmo.global_position
	gizmo_scale = gizmo.scale.x
	var ring_axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var all_rings_pickable: bool = gizmo.rotate_roots.size() == 3
	var x_ring_start_world := Vector3.INF
	for ring_axis_index: int in range(ring_axes.size()):
		var ring_axis := ring_axes[ring_axis_index]
		var tangent := (
			Vector3.RIGHT
			if absf(ring_axis.dot(Vector3.RIGHT)) < 0.9
			else Vector3.UP
		)
		var bitangent := ring_axis.cross(tangent).normalized()
		var found_ring_point := false
		for sample_index: int in range(72):
			var sample_angle := TAU * float(sample_index) / 72.0
			var sample_world: Vector3 = gizmo_pivot + (
				tangent * cos(sample_angle) + bitangent * sin(sample_angle)
			) * gizmo_scale * gizmo.RING_RADIUS
			var sample_viewport: Vector2 = editor.editor_camera.unproject_position(sample_world)
			if gizmo.pick_axis(editor.editor_camera, sample_viewport) == ring_axis_index:
				found_ring_point = true
				if ring_axis_index == 0:
					x_ring_start_world = sample_world
				break
		all_rings_pickable = all_rings_pickable and found_ring_point
	var rotation_before := stacked_placement.basis
	var rotation_started := false
	if x_ring_start_world.is_finite():
		var rotation_end_world := gizmo_pivot + Basis(
			Vector3.RIGHT,
			deg_to_rad(28.0)
		) * (x_ring_start_world - gizmo_pivot)
		var rotation_start_viewport: Vector2 = editor.editor_camera.unproject_position(
			x_ring_start_world
		)
		var rotation_end_viewport: Vector2 = editor.editor_camera.unproject_position(
			rotation_end_world
		)
		rotation_started = editor.call(
			"_begin_transform_gizmo_drag",
			rotation_start_viewport * viewport_to_panel,
			rotation_start_viewport
		)
		editor.call(
			"_update_transform_drag",
			rotation_end_viewport * viewport_to_panel
		)
		editor.call("_finish_transform_drag")
	_expect(
		gizmo.active_mode == gizmo.MODE_ROTATE
		and all_rings_pickable
		and rotation_started
		and not stacked_placement.basis.is_equal_approx(rotation_before),
		"all three colored rotation circles are pickable and an X-ring drag rotates the selection"
	)
	editor.call("_undo")
	editor.call("_set_edit_mode", editor.MODE_SELECT)
	stacked_placement.position.x += 2.0
	editor.call("_select_placement", base_placement)
	editor.call("_toggle_placement_selection", stacked_placement)
	var group_distance_before := base_placement.position.distance_to(
		stacked_placement.position
	)
	var base_position_before := base_placement.position
	var stacked_position_before := stacked_placement.position
	var group_pivot: Vector3 = editor.call(
		"_snapshots_pivot",
		editor.call("_capture_selected_snapshots")
	)
	var position_fields := editor.transform_fields[&"position"] as Array
	(position_fields[0] as SpinBox).value = group_pivot.x + 1.25
	var base_position_delta := base_placement.position.x - base_position_before.x
	var stacked_position_delta := (
		stacked_placement.position.x - stacked_position_before.x
	)
	_expect(
		absf(base_position_delta - 1.25) <= 0.03
		and is_equal_approx(base_position_delta, stacked_position_delta),
		"editing a group pivot translates every selected placement by the same delta"
	)
	editor.call("_undo")
	_expect(
		base_placement.position.is_equal_approx(base_position_before)
		and stacked_placement.position.is_equal_approx(stacked_position_before),
		"group inspector corrections undo without breaking relative placement"
	)
	var base_rotation_before := base_placement.rotation
	var stacked_rotation_before := stacked_placement.rotation
	editor.call("_rotate_asset", Vector3.UP, PI * 0.5)
	_expect(
		editor.selected_placements_by_id.size() == 2
		and base_placement.selection_box.visible
		and stacked_placement.selection_box.visible
		and editor.selection_label.text.begins_with("2 ASSETS")
		and is_equal_approx(
			base_placement.position.distance_to(stacked_placement.position),
			group_distance_before
		)
		and not base_placement.rotation.is_equal_approx(base_rotation_before)
		and not stacked_placement.rotation.is_equal_approx(stacked_rotation_before),
		"multi-selection highlights every member and rotates them around one group pivot"
	)
	editor.call("_undo")
	_expect(
		base_placement.rotation.is_equal_approx(base_rotation_before)
		and stacked_placement.rotation.is_equal_approx(stacked_rotation_before),
		"a grouped transform is recorded as one atomic undo action"
	)
	editor.assembly_storage_path = TEST_ASSEMBLY_SAVE
	editor.assembly_definitions_by_id.clear()
	editor.call("_refresh_assembly_shelf")
	editor.call("_open_selection_context_menu", Vector2(420.0, 260.0))
	var merge_menu_index: int = editor.selection_context_menu.get_item_index(
		editor.CONTEXT_MERGE_ASSEMBLY
	)
	_expect(
		editor.selection_context_menu.visible
		and not editor.selection_context_menu.is_item_disabled(merge_menu_index),
		"right-click exposes assembly actions for the active placed-asset selection"
	)
	editor.selection_context_menu.hide()
	editor.call("_on_mark_as_action", editor.MARK_AS_VALUABLE)
	editor.item_mass_field.value = 9.0
	editor.item_value_per_mass_field.value = 15.0
	editor.call("_confirm_mark_as_item")
	editor.item_properties_dialog.hide()
	_expect(
		editor.item_value_row.visible
		and base_placement.gameplay_role
		== LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		and stacked_placement.gameplay_role
		== LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		and is_equal_approx(base_placement.item_mass_kg, 9.0)
		and is_equal_approx(base_placement.value_per_mass, 15.0),
		"Mark as Valuable applies shared mass and value-per-mass to the complete selection"
	)
	editor.call("_request_merge_selected")
	editor.assembly_name_dialog.hide()
	editor.assembly_name_field.text = "Stacked Stone Fixture"
	editor.call("_confirm_merge_selected")
	var assembly_definition_id := str(
		editor.assembly_definitions_by_id.keys()[0]
		if not editor.assembly_definitions_by_id.is_empty()
		else ""
	)
	var merged_group_id := base_placement.assembly_group_id
	editor.call("_select_placement", base_placement)
	_expect(
		merged_group_id > 0
		and stacked_placement.assembly_group_id == merged_group_id
		and base_placement.assembly_definition_id == assembly_definition_id
		and editor.selected_placements_by_id.size() == 2
		and editor.assembly_buttons_by_id.has(assembly_definition_id)
		and ASSEMBLY_STORE.load_definitions(TEST_ASSEMBLY_SAVE).has(
			assembly_definition_id
		),
		"merging persists a reusable definition and makes every member select as one group"
	)
	editor.call("_arm_assembly_placement", assembly_definition_id)
	var assembly_preview_part_count: int = (
		editor.assembly_preview.parts.size()
		if editor.assembly_preview != null
		else 0
	)
	editor.call("_place_assembly_at_hit", assembly_definition_id, {
		"position": Vector3(12.0, 0.0, 12.0),
		"normal": Vector3.UP,
	})
	var placed_assembly_parts: Array = editor.call("_selected_placements")
	var placed_group_id: int = (
		(placed_assembly_parts[0] as LevelAssetPlacement).assembly_group_id
		if not placed_assembly_parts.is_empty()
		else 0
	)
	_expect(
		assembly_preview_part_count == 2
		and editor.placements_by_id.size() == 4
		and placed_assembly_parts.size() == 2
		and placed_group_id > 0
		and placed_group_id != merged_group_id
		and is_equal_approx(
			(placed_assembly_parts[0] as LevelAssetPlacement).position.distance_to(
				(placed_assembly_parts[1] as LevelAssetPlacement).position
			),
			group_distance_before
		),
		"assembly shelf placement restores all child transforms as a fresh selectable group"
	)
	editor.call("_undo")
	editor.call("_cancel_asset_placement")
	editor.call("_select_placement", base_placement)
	editor.call("_duplicate_selected")
	var duplicate_group_id := 0
	for duplicated: LevelAssetPlacement in editor.call("_selected_placements"):
		duplicate_group_id = duplicated.assembly_group_id
		break
	_expect(
		editor.placements_by_id.size() == 4
		and editor.selected_placements_by_id.size() == 2
		and duplicate_group_id > 0
		and duplicate_group_id != merged_group_id,
		"duplicate treats the selected assembly as one operation and selects its copies"
	)
	editor.call("_undo")
	_expect(
		editor.placements_by_id.size() == 2,
		"undo removes a duplicated selection as one batched operation"
	)
	editor.call("_remove_placement_by_id", stacked_placement.placement_id)
	editor.call("_select_placement", base_placement)
	editor.undo_redo.clear_history()
	await process_frame
	_expect(
		editor.preview.current_visual != null
		and editor.preview.camera.is_current()
		and editor.preview.viewport.render_target_update_mode
		== SubViewport.UPDATE_ALWAYS
		and editor.preview.camera.size > 0.0,
		"catalog selection renders its asset through the lit side-view preview"
	)
	var automatic_preview_direction: Vector3 = editor.preview.preview_direction
	editor.preview.call("_apply_orbit_delta", Vector2(32.0, -14.0))
	var orbited_preview_direction: Vector3 = editor.preview.preview_direction
	editor.preview.call("reset_view")
	_expect(
		not orbited_preview_direction.is_equal_approx(automatic_preview_direction)
		and editor.preview.preview_direction.is_equal_approx(
			automatic_preview_direction
		),
		"the detailed preview can orbit away from and reset to its automatic readable angle"
	)
	editor.call("_duplicate_selected")
	var duplicate_count: int = editor.placements_by_id.size()
	editor.call("_undo")
	var undo_count: int = editor.placements_by_id.size()
	editor.call("_redo")
	var redo_count: int = editor.placements_by_id.size()
	_expect(
		duplicate_count == 2
		and undo_count == 1
		and redo_count == 2
		and editor.used_asset_buttons_by_path.size() == 1,
		"duplicate placements retain one used-asset shortcut through undo and redo"
	)
	editor.call("_toggle_acoustic_authoring")
	_expect(
		editor.acoustic_authoring_enabled
		and editor.acoustic_panel.visible
		and editor.acoustic_marker_root.visible,
		"the SOUND tool exposes editor-only probe and portal authoring overlays"
	)
	editor.call("_generate_automatic_acoustic_probes")
	var automatic_probe_count: int = editor.acoustic_state.probes_by_id.size()
	var manual_probe_position := Vector3(0.25, 1.7, 0.25)
	var manual_previous: Dictionary = editor.acoustic_state.capture_state()
	var manual_probe_id: int = editor.acoustic_state.add_probe(
		manual_probe_position,
		true
	)
	var manual_next: Dictionary = editor.acoustic_state.capture_state()
	editor.call(
		"_commit_acoustic_state_action",
		"Test manual probe",
		manual_previous,
		manual_next
	)
	editor.call("_select_placement", base_placement)
	editor.call("_create_portal_from_selected_asset")
	var portal_count: int = editor.acoustic_state.portals_by_id.size()
	var anchored_portal: LevelAcousticPortalMarker = (
		editor.acoustic_state.portals_by_id.values()[0]
		as LevelAcousticPortalMarker
	)
	var anchored_probe_before: Vector3 = (
		editor.acoustic_state.probes_by_id[anchored_portal.probe_a_id].position
	)
	base_placement.position.x += 0.75
	editor.acoustic_state.sync_anchored_portals(editor.placements_by_id)
	var anchored_probe_after: Vector3 = (
		editor.acoustic_state.probes_by_id[anchored_portal.probe_a_id].position
	)
	_expect(
		automatic_probe_count > 0
		and manual_probe_id > 0
		and portal_count == 1
		and editor.acoustic_state.probes_by_id.size() >= automatic_probe_count + 3
		and is_equal_approx(
			anchored_probe_after.x - anchored_probe_before.x,
			0.75
		),
		"automatic and hand-placed probes coexist while asset-derived portals follow their wall"
	)
	var portal_probe_ids := [anchored_portal.probe_a_id, anchored_portal.probe_b_id]
	editor.acoustic_state.select_probe(portal_probe_ids[0], false)
	editor.acoustic_state.select_probe(portal_probe_ids[1], true)
	_expect(
		editor.acoustic_state.selected_probe_ids.size() == 2
		and editor.acoustic_state.link_selected_probes("open") == 0,
		"two probe markers are selectable and duplicate explicit portal links are rejected"
	)
	editor.call("_select_placement", base_placement)
	editor.call("_set_selected_acoustic_boundary", false)
	_expect(
		not base_placement.acoustic_boundary,
		"selected decorative openings can remain physical while passing acoustic rays"
	)
	editor.call("_validate_acoustic_bake")
	_expect(
		editor.status_label.text.begins_with("SOUND BAKE READY"),
		"the bake validator constructs and verifies the authored runtime probe graph"
	)
	editor.preview_tabs.current_tab = editor.light_tab_index
	editor.light_type_field.select(1)
	editor.light_name_field.text = "Bunker Door Spot"
	editor.light_color_field.color = Color(0.58, 0.77, 1.0)
	editor.light_energy_field.value = 4.5
	editor.light_range_field.value = 18.0
	editor.light_spot_angle_field.value = 36.0
	editor.call("_begin_light_placement")
	editor.call("_place_authored_light", {
		"position": Vector3(4.0, 2.4, 7.0),
		"normal": Vector3(0.0, 0.0, -1.0),
	})
	var editor_light_marker: Node3D = editor.authored_lights_by_id.get(1)
	var editor_light_descriptor: Dictionary = (
		editor_light_marker.call("descriptor")
		if editor_light_marker != null
		else {}
	)
	var editor_light_forward := (
		-Basis.from_euler(
			editor_light_descriptor.get("rotation", Vector3.ZERO)
		).z
	)
	_expect(
		editor.authored_lights_by_id.size() == 1
		and editor.selected_light_id == 1
		and editor_light_descriptor.get("type") == LIGHT_AUTHORING.TYPE_SPOT
		and is_equal_approx(
			float(editor_light_descriptor.get("energy", 0.0)),
			4.5
		)
		and editor_light_forward.dot(Vector3(0.0, 0.0, -1.0)) > 0.99,
		"light placement creates a live spot oriented away from the clicked surface"
	)
	editor.light_energy_field.value = 5.75
	editor.call("_on_light_setting_changed")
	editor_light_descriptor = editor_light_marker.call("descriptor")
	_expect(
		is_equal_approx(
			float(editor_light_descriptor.get("energy", 0.0)),
			5.75
		)
		and is_equal_approx(
			float(editor_light_descriptor.get("range", 0.0)),
			18.0
		)
		and bool(editor_light_descriptor.get("shadows", false)),
		"selected lights expose editable color, energy, range, cone, falloff, and shadow settings"
	)
	editor.call("_begin_speaker_system_authoring")
	_expect(
		editor.speaker_authoring_active
		and editor.speaker_authoring_panel.visible
		and not editor.acoustic_authoring_enabled
		and editor.speaker_finish_button.disabled,
		"the PA ARRAY button enters an isolated multi-speaker placement workflow"
	)
	editor.call("_place_draft_speaker", {
		"position": Vector3(-4.0, 0.0, 5.0),
		"normal": Vector3.UP,
	})
	editor.call("_place_draft_speaker", {
		"position": Vector3(0.0, 2.0, 8.0),
		"normal": Vector3(0.0, 0.0, -1.0),
	})
	editor.call("_place_draft_speaker", {
		"position": Vector3(4.0, 2.0, 8.0),
		"normal": Vector3(0.0, 0.0, -1.0),
	})
	editor.speaker_name_field.text = "Editor Regression Array"
	editor.call("_finalize_speaker_system")
	var finalized_marker_count := 0
	for marker_node: Node in editor.speaker_marker_root.get_children():
		if (
			marker_node is LevelSpeakerAuthoringMarker
			and (marker_node as LevelSpeakerAuthoringMarker).system_id > 0
		):
			finalized_marker_count += 1
	_expect(
		not editor.speaker_authoring_active
		and editor.sound_systems_by_id.size() == 1
		and finalized_marker_count == 3
		and not editor.speaker_authoring_panel.visible,
		"finalize turns every draft cabinet into one persistent arbitrary-count PA array"
	)
	var runtime_server_root := Node3D.new()
	var runtime_client_root := Node3D.new()
	root.add_child(runtime_server_root)
	root.add_child(runtime_client_root)
	var authored_systems: Array[Dictionary] = []
	for system_value: Dictionary in editor.sound_systems_by_id.values():
		authored_systems.append(system_value)
	var server_arrays := LevelSpeakerSystemRuntimeBuilder.build_server_systems(
		runtime_server_root,
		authored_systems
	)
	var client_arrays := LevelSpeakerSystemRuntimeBuilder.build_client_systems(
		runtime_client_root,
		authored_systems
	)
	await process_frame
	var server_speakers: Array[SpeakerArrayEmitter3D] = (
		server_arrays[0].get_speaker_markers()
		if not server_arrays.is_empty()
		else []
	)
	var client_speakers: Array[SpeakerArrayEmitter3D] = (
		client_arrays[0].get_speaker_markers()
		if not client_arrays.is_empty()
		else []
	)
	var positions_match := server_speakers.size() == client_speakers.size()
	for speaker_index: int in range(server_speakers.size()):
		positions_match = (
			positions_match
			and server_speakers[speaker_index].global_position.is_equal_approx(
				client_speakers[speaker_index].global_position
			)
		)
	_expect(
		server_arrays.size() == 1
		and client_arrays.size() == 1
		and server_speakers.size() == 3
		and client_speakers.size() == 3
		and server_arrays[0].get_emitter_ids().size() == 3
		and client_arrays[0].find_children(
			"SpeakerCone",
			"MeshInstance3D",
			true,
			false
		).size() == 3
		and positions_match
		and not server_arrays[0].powered,
		"one saved definition constructs matching silent server and client PA systems"
	)
	runtime_server_root.free()
	runtime_client_root.free()
	editor.level_name_field.text = "Editor Save Regression"
	editor.call("_save_to_path", TEST_SAVE)
	var saved := LevelEditorDocument.load_from_path(TEST_SAVE)
	_expect(
		saved != null
		and saved.level_name == "Editor Save Regression"
		and saved.placements.size() == 2
		and not saved.acoustic_probes.is_empty()
		and saved.acoustic_portals.size() == 1
		and saved.sound_systems.size() == 1
		and saved.authored_lights.size() == 1
		and not editor.dirty,
		"the visible Save action serializes geometry, sound map, PA arrays, and authored lights"
	)
	editor.call("_new_document_now")
	editor.call("_load_from_path", TEST_SAVE)
	_expect(
		editor.placements_by_id.size() == 2
		and not editor.acoustic_state.probes_by_id.is_empty()
		and editor.acoustic_state.portals_by_id.size() == 1
		and editor.sound_systems_by_id.size() == 1
		and editor.authored_lights_by_id.size() == 1
		and editor.level_name_field.text == "Editor Save Regression"
		and not editor.dirty,
		"the Load action reconstructs assets, acoustic markers, PA speakers, and lights"
	)
	var building_catalog := LevelAssetCatalog.entries()
	var building_floor := BUILDING_KITS.default_entry(
		building_catalog,
		"HR",
		BUILDING_KITS.ROLE_FLOOR
	)
	var building_roof := BUILDING_KITS.default_entry(
		building_catalog,
		"HR",
		BUILDING_KITS.ROLE_ROOF
	)
	var actual_wall_bounds := LevelAssetPlacement.asset_bounds(MATCHED_WALL)
	var actual_span := BUILDING_SHELL_GENERATOR.horizontal_span(actual_wall_bounds)
	var building_group_id: int = editor.document.allocate_building_group_id()
	var room_templates := BUILDING_SHELL_GENERATOR.generate(
		Vector3(30.0, 0.0, 30.0),
		Vector3(30.0 + actual_span, 0.0, 30.0 + actual_span),
		0.0,
		MATCHED_WALL,
		actual_wall_bounds,
		str(building_floor.get("asset_path", "")),
		LevelAssetPlacement.asset_bounds(str(building_floor.get("asset_path", ""))),
		str(building_roof.get("asset_path", "")),
		LevelAssetPlacement.asset_bounds(str(building_roof.get("asset_path", ""))),
		true,
		building_group_id,
		0
	)
	var room_snapshots: Array[Dictionary] = []
	var room_ids: Array[int] = []
	var room_wall_id := 0
	for room_template: Dictionary in room_templates:
		var room_snapshot := room_template.duplicate(false)
		var room_id: int = editor.document.allocate_placement_id()
		room_snapshot["id"] = room_id
		room_ids.append(room_id)
		room_snapshots.append(room_snapshot)
		if (
			room_wall_id == 0
			and str(room_snapshot.get("asset_path", "")) == MATCHED_WALL
		):
			room_wall_id = room_id
	editor.call("_restore_placements", room_snapshots)
	editor.call("_select_placement", editor.placements_by_id.get(room_wall_id))
	editor.call("_refresh_building_controls")
	var doorway_option := -1
	for option_index: int in range(editor.building_compatible_options.item_count):
		if str(editor.building_compatible_options.get_item_metadata(option_index)) == (
			MATCHED_DOORWAY
		):
			doorway_option = option_index
			break
	var original_wall: LevelAssetPlacement = editor.placements_by_id.get(room_wall_id)
	var original_span := (
		original_wall.basis
		* BUILDING_SHELL_GENERATOR.horizontal_span_axis(original_wall.local_bounds)
	).length() * BUILDING_SHELL_GENERATOR.horizontal_span(original_wall.local_bounds)
	if doorway_option >= 0:
		editor.building_compatible_options.select(doorway_option)
		editor.call("_replace_selected_building_piece")
	var replaced_wall: LevelAssetPlacement = editor.placements_by_id.get(room_wall_id)
	var replacement_span := -1.0
	if replaced_wall != null:
		replacement_span = (
			replaced_wall.basis
			* BUILDING_SHELL_GENERATOR.horizontal_span_axis(replaced_wall.local_bounds)
		).length() * BUILDING_SHELL_GENERATOR.horizontal_span(replaced_wall.local_bounds)
	_expect(
		doorway_option >= 0
		and replaced_wall != null
		and replaced_wall.asset_path == MATCHED_DOORWAY
		and replaced_wall.building_group_id == building_group_id
		and is_equal_approx(original_span, replacement_span),
		"compatible replacement swaps a wall for a doorway without changing its module span"
	)
	var before_storey_count: int = editor.placements_by_id.size()
	editor.call("_duplicate_building_storey")
	var duplicated_storey_valid: bool = (
		not editor.selected_placements_by_id.is_empty()
	)
	for duplicate: LevelAssetPlacement in editor.selected_placements_by_id.values():
		duplicated_storey_valid = (
			duplicated_storey_valid
			and duplicate.building_group_id == building_group_id
			and duplicate.building_storey == 1
			and duplicate.position.y >= actual_wall_bounds.size.y - 0.01
		)
	_expect(
		editor.placements_by_id.size() > before_storey_count
		and duplicated_storey_valid,
		"STOREY + copies the generated structure by measured wall height as one selected level"
	)
	editor.call("_undo")
	editor.call("_remove_placements_by_id", room_ids)
	editor.free()


func _test_main_menu_entry() -> void:
	var menu_scene_source := FileAccess.get_file_as_string(
		"res://scenes/UI/main_menu.tscn"
	)
	var menu_source := FileAccess.get_file_as_string(
		"res://scripts/client/main_menu.gd"
	)
	var controller_source := FileAccess.get_file_as_string(
		"res://scripts/globals/scene_controller.gd"
	)
	_expect(
		menu_scene_source.contains("LevelEditorButton")
		and menu_scene_source.contains('text = "Level Editor"')
		and menu_source.contains("_on_level_editor_pressed")
		and controller_source.contains("func open_level_editor()")
		and controller_source.contains("func leave_level_editor()"),
		"the main menu and scene controller expose both directions of editor navigation"
	)


func _cleanup() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_SAVE)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(absolute)
	var favorites_absolute := ProjectSettings.globalize_path(TEST_FAVORITES_SAVE)
	if FileAccess.file_exists(TEST_FAVORITES_SAVE):
		DirAccess.remove_absolute(favorites_absolute)
	var assemblies_absolute := ProjectSettings.globalize_path(TEST_ASSEMBLY_SAVE)
	if FileAccess.file_exists(TEST_ASSEMBLY_SAVE):
		DirAccess.remove_absolute(assemblies_absolute)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)
