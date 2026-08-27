extends SceneTree

const EDITOR_SCENE_PATH := "res://scenes/UI/level_editor.tscn"
const TEST_ASSET := (
	"res://assets/third_party/pizza_doggy/models/nature/stone_2.glb"
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
const ASSET_SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")
const MATCHED_WALL := "res://assets/environment/PSX Mega Pack II v1.8/PSX Mega Pack II/Models/GLB (recommended)/Modular Structures/wall_hr_1.glb"
const MATCHED_DOORWAY := "res://assets/environment/PSX Mega Pack II v1.8/PSX Mega Pack II/Models/GLB (recommended)/Modular Structures/doorway_hr_1.glb"

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_contract()
	_test_source_vault_instantiation()
	_test_document_round_trip()
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
		== LevelAssetCatalog.CATEGORY_WALLS,
		"the large bundle is divided into workflow-ordered functional categories"
	)
	var wall_index := -1
	var doorway_index := -1
	for index: int in range(catalog.size()):
		var entry_path := str(catalog[index].get("asset_path", ""))
		if entry_path == MATCHED_WALL:
			wall_index = index
		elif entry_path == MATCHED_DOORWAY:
			doorway_index = index
	_expect(
		wall_index >= 0
		and doorway_index >= 0
		and catalog[wall_index].get("category", "")
		== LevelAssetCatalog.CATEGORY_WALLS
		and catalog[doorway_index].get("category", "")
		== LevelAssetCatalog.CATEGORY_WALLS
		and absi(wall_index - doorway_index) <= 12,
		"matching walls and doorways sort together across the commercial catalog"
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


func _test_document_round_trip() -> void:
	var document := LevelEditorDocument.new()
	document.level_name = "Stage One Regression"
	document.placements.append({
		"id": document.allocate_placement_id(),
		"asset_path": TEST_ASSET,
		"position": Vector3(1.25, 0.5, -3.0),
		"rotation": Vector3(0.0, 0.75, 0.0),
		"scale": Vector3(1.2, 0.8, 1.2),
	})
	var save_error := document.save_to_path(TEST_SAVE)
	var loaded := LevelEditorDocument.load_from_path(TEST_SAVE)
	_expect(
		save_error == OK
		and loaded != null
		and loaded.level_name == document.level_name
		and loaded.placements.size() == 1,
		"versioned level JSON saves and loads through the user data directory"
	)
	if loaded != null and not loaded.placements.is_empty():
		var placement: Dictionary = loaded.placements[0]
		_expect(
			(placement.get("position", Vector3.INF) as Vector3).is_equal_approx(
				Vector3(1.25, 0.5, -3.0)
			)
			and (placement.get("scale", Vector3.ZERO) as Vector3).is_equal_approx(
				Vector3(1.2, 0.8, 1.2)
			),
			"placement transforms survive JSON serialization without scene-node state"
		)


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
		and editor.asset_list.item_count == editor.catalog.size()
		and editor.viewport_container.size.x > 100.0
		and editor.preview.size.x > 100.0,
		"the main-menu editor opens with its searchable catalog, 3D view, and preview"
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
	editor.asset_list.select(catalog_index)
	var wheel_direction := (
		MOUSE_BUTTON_WHEEL_DOWN
		if catalog_index + 1 < editor.asset_list.item_count
		else MOUSE_BUTTON_WHEEL_UP
	)
	var expected_wheel_index := catalog_index + (
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
	var center_position: Vector2 = (
		editor.viewport_container.size * 0.5
		+ Vector2(37.0, 21.0)
	)
	var raw_ground_position: Vector3 = editor.call(
		"_screen_to_ground",
		editor.call("_viewport_pixel", center_position)
	)
	var expected_ground_position := Vector3(
		snappedf(raw_ground_position.x, float(editor.snap_step.value)),
		0.0,
		snappedf(raw_ground_position.z, float(editor.snap_step.value))
	)
	editor.call(
		"_update_placement_cursor",
		editor.call("_viewport_pixel", center_position)
	)
	var rotate_key := InputEventKey.new()
	rotate_key.physical_keycode = KEY_R
	rotate_key.pressed = true
	editor.call("_unhandled_key_input", rotate_key)
	_expect(
		is_equal_approx(editor.placement_rotation_y, PI * 0.5)
		and is_equal_approx(editor.placement_preview.rotation.y, PI * 0.5),
		"R rotates the armed asset preview by one exact quarter turn"
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
			expected_ground_position.x
		)
		and is_equal_approx(
			editor.selected_placement.position.z,
			expected_ground_position.z
		)
		and (
			not is_equal_approx(raw_ground_position.x, expected_ground_position.x)
			or not is_equal_approx(raw_ground_position.z, expected_ground_position.z)
		)
		and not editor.pending_asset_path.is_empty()
		and editor.placement_cursor.visible,
		"world clicks place the armed asset on the enabled position grid"
	)
	_expect(
		editor.placement_preview != null
		and editor.placement_preview.visible
		and editor.placement_preview.asset_path == TEST_ASSET
		and is_equal_approx(
			editor.placement_preview.position.x,
			expected_ground_position.x
		)
		and is_equal_approx(
			editor.placement_preview.position.z,
			expected_ground_position.z
		)
		and is_equal_approx(
			editor.placement_preview.position.y,
			editor.placement_preview.floor_offset()
		),
		"the selected model itself previews at the projected world-mouse position"
	)
	var base_placement: LevelAssetPlacement = editor.selected_placement
	var base_top_local := Vector3(
		base_placement.local_bounds.get_center().x,
		base_placement.local_bounds.end.y,
		base_placement.local_bounds.get_center().z
	)
	var base_top_world: Vector3 = base_placement.global_transform * base_top_local
	var base_top_screen: Vector2 = editor.editor_camera.unproject_position(base_top_world)
	var resolved_stack_surface: Vector3 = editor.call(
		"_screen_to_placement_surface",
		base_top_screen
	)
	editor.call("_place_asset", TEST_ASSET, resolved_stack_surface)
	var stacked_placement: LevelAssetPlacement = editor.selected_placement
	var stacked_bottom_y := (
		stacked_placement.position.y
		+ stacked_placement.local_bounds.position.y * stacked_placement.scale.y
	)
	_expect(
		editor.placements_by_id.size() == 2
		and resolved_stack_surface.is_finite()
		and is_equal_approx(resolved_stack_surface.y, base_top_world.y)
		and is_equal_approx(stacked_bottom_y, base_top_world.y),
		"surface ray placement stacks a new asset exactly on an existing asset's top face"
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
	editor.call("_duplicate_selected")
	var duplicate_count: int = editor.placements_by_id.size()
	editor.call("_undo")
	var undo_count: int = editor.placements_by_id.size()
	editor.call("_redo")
	var redo_count: int = editor.placements_by_id.size()
	_expect(
		duplicate_count == 2 and undo_count == 1 and redo_count == 2,
		"placement duplication participates in runtime undo and redo history"
	)
	editor.level_name_field.text = "Editor Save Regression"
	editor.call("_save_to_path", TEST_SAVE)
	var saved := LevelEditorDocument.load_from_path(TEST_SAVE)
	_expect(
		saved != null
		and saved.level_name == "Editor Save Regression"
		and saved.placements.size() == 2
		and not editor.dirty,
		"the visible Save action serializes the complete edited level and clears dirty state"
	)
	editor.call("_new_document_now")
	editor.call("_load_from_path", TEST_SAVE)
	_expect(
		editor.placements_by_id.size() == 2
		and editor.level_name_field.text == "Editor Save Regression"
		and not editor.dirty,
		"the Load action reconstructs asset instances and document identity"
	)
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


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)
