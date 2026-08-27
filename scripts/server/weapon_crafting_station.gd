extends StaticBody3D

const LAYOUT := preload(
	"res://scripts/weapons/weapon_crafting_station_layout.gd"
)
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const SCREEN_CENTER := Vector2(-0.5, 1.72)
const SCREEN_WORLD_SIZE := Vector2(3.05, 1.73)
const CRAFT_COOLDOWN_MSEC := 350
const OUTPUT_LOCAL_POSITION := Vector3(1.43, 0.79, -1.4)
const OUTPUT_LOCAL_VELOCITY := Vector3(0.0, 0.18, -0.28)

@export var station_id := 3

var catalog_document: Dictionary = {}
var selection_indices_by_player_id: Dictionary = {}
var summaries_by_player_id: Dictionary = {}
var status_by_player_id: Dictionary = {}
var last_craft_msec_by_player_id: Dictionary = {}
var craft_sequence := 0


func _ready() -> void:
	add_to_group("weapon_crafting_stations")
	PHYSICAL_SURFACE.apply_to(self, &"metal")
	catalog_document = WeaponCraftingCatalog.build_document()
	var server := _server()
	if server != null:
		server.call("register_weapon_crafting_station", station_id, self)


func _exit_tree() -> void:
	var server := _server()
	if server != null:
		server.call("unregister_weapon_crafting_station", station_id, self)


func server_primary_action(player: ServerPlayer, hit: Dictionary) -> void:
	if player == null or not _is_screen_hit(hit):
		return
	var player_id := player.player_id
	_ensure_player_state(player_id)
	var screen_position := _hit_to_screen_position(hit)
	var lanes: Array = catalog_document.get("lanes", [])
	var cycle_action := LAYOUT.get_lane_cycle_action(
		screen_position,
		lanes.size()
	)
	if not cycle_action.is_empty():
		_cycle_lane(
			player_id,
			int(cycle_action["lane_index"]),
			int(cycle_action["direction"])
		)
		var server := _server()
		if server != null:
			server.call(
				"emit_spatial_sound",
				&"industrial_button",
				global_position + Vector3.UP * 1.4,
				18.0,
				-3.0,
				null,
				0.35
			)
		return
	if LAYOUT.CRAFT_RECT.has_point(screen_position):
		_craft_for_player(player)


func server_use(player: ServerPlayer, hit: Dictionary) -> void:
	server_primary_action(player, hit)


func get_server_interaction_hint(
	_player: ServerPlayer,
	hit: Dictionary
) -> String:
	return (
		"LMB / F // OPERATE WEAPON FABRICATOR"
		if _is_screen_hit(hit)
		else ""
	)


func prefers_primary_action_over_weapon() -> bool:
	return true


func should_prioritize_primary_action(
	_player: ServerPlayer,
	hit: Dictionary
) -> bool:
	return _is_screen_hit(hit)


func _cycle_lane(player_id: int, lane_index: int, direction: int) -> void:
	var lanes: Array = catalog_document.get("lanes", [])
	if lane_index < 0 or lane_index >= lanes.size():
		return
	var lane: Dictionary = SafeVariant.dictionary_copy(lanes[lane_index], false)
	var options: Array = SafeVariant.array_copy(lane.get("options", []), false)
	if options.is_empty():
		return
	var selection: Array[int] = _selection_for_player(player_id)
	selection[lane_index] = posmod(
		selection[lane_index] + (1 if direction >= 0 else -1),
		options.size()
	)
	selection_indices_by_player_id[player_id] = selection
	_refresh_summary(player_id)
	status_by_player_id.erase(player_id)


func _craft_for_player(player: ServerPlayer) -> void:
	var player_id := player.player_id
	var now := Time.get_ticks_msec()
	var last_craft := int(
		last_craft_msec_by_player_id.get(player_id, -100000)
	)
	if now - last_craft < CRAFT_COOLDOWN_MSEC:
		return
	last_craft_msec_by_player_id[player_id] = now
	var selection := _selection_for_player(player_id)
	var build := WeaponCraftingCatalog.build_from_selection(
		catalog_document,
		selection
	)
	var errors := build.get_compatibility_errors()
	if not errors.is_empty():
		_set_status(
			player_id,
			"PAYOUT BLOCKED // %s" % ", ".join(errors).to_upper(),
			true
		)
		return
	var weapon_definition := load(
		WeaponCraftingCatalog.CRAFTED_WEAPON_PATH
	) as GunItemDefinition
	if weapon_definition == null:
		_set_status(player_id, "PAYOUT BLOCKED // FABRICATOR TEMPLATE OFFLINE", true)
		return
	var output_transform := global_transform * Transform3D(
		Basis(Vector3.UP, PI * 0.5),
		OUTPUT_LOCAL_POSITION
	)
	var server := _server()
	if server == null:
		_set_status(player_id, "PAYOUT BLOCKED // AUTHORITY OFFLINE", true)
		return
	var item := server.call(
		"spawn_item",
		weapon_definition,
		output_transform
	) as ServerItem
	if item == null:
		_set_status(player_id, "PAYOUT BLOCKED // OUTPUT JAM", true)
		return
	item.restore_instance_state(
		WeaponCraftingCatalog.make_crafted_instance_state(build)
	)
	item.linear_velocity = global_basis * OUTPUT_LOCAL_VELOCITY
	item.angular_velocity = global_basis.y * 0.4
	craft_sequence += 1
	item.set_meta(
		"dev_warehouse_display_name",
		"FABRICATED %d-BARREL WEAPON #%03d" % [
			build.get_barrel_count(),
			craft_sequence,
		]
	)
	_set_status(
		player_id,
		"PAYOUT #%03d // %d-BARREL BUILD READY" % [
			craft_sequence,
			build.get_barrel_count(),
		],
		false
	)
	server.call(
		"emit_spatial_sound",
		&"industrial_button",
		output_transform.origin,
		24.0,
		0.0,
		null,
		0.5
	)


func _ensure_player_state(player_id: int) -> void:
	if selection_indices_by_player_id.has(player_id):
		return
	selection_indices_by_player_id[player_id] = (
		WeaponCraftingCatalog.default_selection_indices(catalog_document)
	)
	_refresh_summary(player_id)


func _selection_for_player(player_id: int) -> Array[int]:
	_ensure_player_state(player_id)
	var result := WeaponCraftingCatalog.sanitized_selection_indices(
		catalog_document,
		selection_indices_by_player_id.get(player_id, [])
	)
	selection_indices_by_player_id[player_id] = result
	return result


func _refresh_summary(player_id: int) -> void:
	summaries_by_player_id[player_id] = WeaponCraftingCatalog.build_summary(
		catalog_document,
		selection_indices_by_player_id.get(player_id, [])
	)


func _set_status(player_id: int, message: String, is_error: bool) -> void:
	status_by_player_id[player_id] = {
		"message": message,
		"is_error": is_error,
	}


func _is_screen_hit(hit: Dictionary) -> bool:
	var world_position: Vector3 = hit.get("position", global_position)
	var local_position := to_local(world_position)
	return (
		absf(local_position.x - SCREEN_CENTER.x)
			<= SCREEN_WORLD_SIZE.x * 0.5
		and absf(local_position.y - SCREEN_CENTER.y)
			<= SCREEN_WORLD_SIZE.y * 0.5
		and local_position.z < -0.48
	)


func _hit_to_screen_position(hit: Dictionary) -> Vector2:
	var world_position: Vector3 = hit.get("position", global_position)
	var local_position := to_local(world_position)
	var normalized_x := (
		local_position.x - (SCREEN_CENTER.x - SCREEN_WORLD_SIZE.x * 0.5)
	) / SCREEN_WORLD_SIZE.x
	var normalized_y := (
		(SCREEN_CENTER.y + SCREEN_WORLD_SIZE.y * 0.5) - local_position.y
	) / SCREEN_WORLD_SIZE.y
	return Vector2(
		clampf(normalized_x, 0.0, 1.0) * LAYOUT.SCREEN_SIZE.x,
		clampf(normalized_y, 0.0, 1.0) * LAYOUT.SCREEN_SIZE.y
	)


func to_state_dict() -> Dictionary:
	var server := _server()
	if server != null:
		var active_ids_value: Variant = server.call("get_active_player_ids")
		if active_ids_value is Array:
			for player_id_value: Variant in active_ids_value as Array:
				_ensure_player_state(int(player_id_value))
	return {
		"station_id": station_id,
		"catalog_document": catalog_document,
		"selection_indices_by_player_id": selection_indices_by_player_id,
		"summaries_by_player_id": summaries_by_player_id,
		"status_by_player_id": status_by_player_id,
		"craft_sequence": craft_sequence,
	}


func _server() -> Node:
	return get_node_or_null("/root/Server")
