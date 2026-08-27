extends SceneTree

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const CLIENT_COMPLEX_SCENE := preload("res://scenes/proxy/industrial_acoustic_complex.tscn")
const SERVER_COMPLEX_SCENE := preload("res://scenes/server/industrial_acoustic_complex.tscn")
const CLIENT_COMPLEX_SCRIPT := preload("res://scripts/client/industrial_acoustic_complex_proxy.gd")
const NATURE_LAYOUT := preload("res://scripts/world/world_nature_layout.gd")
const CLIENT_NATURE_SCRIPT := preload("res://scripts/client/world_nature_dressing.gd")
const SERVER_NATURE_SCRIPT := preload("res://scripts/server/world_nature_collision.gd")
const AUDIO_LIBRARY := preload("res://scripts/audio/game_audio_library.gd")
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const IMPACT_RESPONSE := preload("res://scripts/audio/physical_impact_response.gd")
const CURATED_ROOT := "res://assets/third_party/pizza_doggy/"

class RecordingServerPlayer:
	extends ServerPlayer

	var emitted_sound_ids: Array[StringName] = []
	var emitted_wrist_sound_ids: Array[StringName] = []

	func _emit_gameplay_sound(
		sound_id: StringName,
		_max_distance: float,
		_priority: float
	) -> void:
		emitted_sound_ids.append(sound_id)

	func _emit_wrist_device_sound(sound_id: StringName) -> void:
		emitted_wrist_sound_ids.append(sound_id)


var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_source_vault_boundary()
	_test_curated_audio_catalog()
	await _test_curated_prop_contract()
	await _test_curated_nature_contract()
	_finish()


func _test_source_vault_boundary() -> void:
	_expect(
		FileAccess.file_exists("res://assets/environment/.gdignore")
		and FileAccess.file_exists("res://assets/sounds/effects/.gdignore"),
		"raw commercial source vaults are excluded from Godot imports"
	)
	_expect(
		FileAccess.file_exists(CURATED_ROOT + "README.md"),
		"curated runtime assets retain license and provenance guidance"
	)


func _test_curated_audio_catalog() -> void:
	var ids: Array[StringName] = AUDIO_LIBRARY.registered_sound_ids()
	var unique_ids: Dictionary[StringName, bool] = {}
	var all_streams_valid := true
	var projectile_impacts_are_short := true
	var stream_count := 0
	for sound_id: StringName in ids:
		if sound_id.is_empty() or unique_ids.has(sound_id):
			all_streams_valid = false
		unique_ids[sound_id] = true
	for surface_spec: Dictionary in AUDIO_LIBRARY.SURFACE_SPECS:
		for stream_value: Variant in surface_spec.get("footstep_streams", []):
			var stream := stream_value as AudioStream
			stream_count += 1
			if stream == null or not stream.resource_path.begins_with(CURATED_ROOT):
				all_streams_valid = false
	for spec: Dictionary in AUDIO_LIBRARY.PROJECTILE_IMPACT_SPECS:
		for stream_value: Variant in spec.get("streams", []):
			var stream := stream_value as AudioStream
			stream_count += 1
			if stream == null or not stream.resource_path.begins_with(CURATED_ROOT):
				all_streams_valid = false
			elif (
				stream.get_length() > 0.65
				or not stream.resource_path.contains("/projectile_impacts/")
			):
				projectile_impacts_are_short = false
	for spec: Dictionary in AUDIO_LIBRARY.WEAPON_REPORT_SPECS:
		for field: String in ["streams", "pressure_streams"]:
			for stream_value: Variant in spec.get(field, []):
				var stream := stream_value as AudioStream
				stream_count += 1
				if (
					stream == null
					or not (
						stream.resource_path.begins_with(CURATED_ROOT)
						or stream.resource_path.begins_with(
							"res://assets/sounds/pistol/"
						)
					)
				):
					all_streams_valid = false
	for spec: Dictionary in AUDIO_LIBRARY.SOUND_SPECS:
		for stream_value: Variant in spec.get("streams", []):
			var stream := stream_value as AudioStream
			stream_count += 1
			if stream == null or not stream.resource_path.begins_with(CURATED_ROOT):
				all_streams_valid = false
	_expect(
		ids.size() == 35
		and unique_ids.size() == ids.size()
		and stream_count == 63
		and ids.has(&"service_pistol_fire")
		and ids.has(&"automatic_rifle_fire")
		and ids.has(&"rifle_reload_out")
		and ids.has(&"rifle_reload_in")
		and ids.has(&"fieldlink_open")
		and ids.has(&"fieldlink_warning")
		and ids.has(&"footstep_stone")
		and ids.has(&"footstep_soil")
		and ids.has(&"projectile_impact_9mm")
		and ids.has(&"projectile_impact_556")
		and ids.has(&"projectile_impact_nail")
		and ids.has(&"projectile_impact_coil"),
		"game audio library exposes all movement and material-impact cues backed by curated clips"
	)
	_expect(
		all_streams_valid and projectile_impacts_are_short,
		"every cue is curated and projectile transients release pooled voices within 650 ms"
	)
	var metal_floor := StaticBody3D.new()
	metal_floor.set_meta(&"footstep_surface", &"metal")
	var rock := StaticBody3D.new()
	PHYSICAL_SURFACE.apply_to(rock, &"stone")
	_expect(
		ServerPlayer._get_footstep_surface(metal_floor) == &"metal"
		and ServerPlayer._get_footstep_surface(rock) == &"stone"
		and ServerPlayer._get_footstep_surface(null) == &"concrete",
		"the unified physical surface tag drives locomotion with legacy fallback"
	)
	var quiet_wood := IMPACT_RESPONSE.modifier_for(&"wood", 0.15)
	var hard_wood := IMPACT_RESPONSE.modifier_for(&"wood", 0.95)
	var hard_metal := IMPACT_RESPONSE.modifier_for(&"metal", 0.95)
	var hard_soil := IMPACT_RESPONSE.modifier_for(&"soil", 0.95)
	_expect(
		hard_wood.volume_db > quiet_wood.volume_db
		and hard_wood.band_gain.z > quiet_wood.band_gain.z
		and hard_metal.resonance > hard_wood.resonance
		and hard_metal.lowpass_hz > hard_soil.lowpass_hz
		and IMPACT_RESPONSE.modifier_for(&"metal", 0.95) == hard_metal,
		"projectile energy drives nonlinear, cached material response curves"
	)
	_expect(
		ServerPlayer._jump_sound_id(&"metal") == &"jump_metal"
		and ServerPlayer._landing_sound_id(&"wood") == &"landing_wood"
		and ServerPlayer._footstep_sound_id(&"soil") == &"footstep_soil"
		and ids.has(&"jump_concrete")
		and ids.has(&"landing_concrete"),
		"takeoff and landing select registered material-aware spatial cues"
	)
	var movement_player := RecordingServerPlayer.new()
	var player_collision := CollisionShape3D.new()
	player_collision.name = "CollisionShape3D"
	player_collision.shape = BoxShape3D.new()
	movement_player.add_child(player_collision)
	var player_grabber := GrabberComponent.new()
	player_grabber.name = "Grabber"
	player_grabber.capability = GrabCapability.new()
	movement_player.add_child(player_grabber)
	movement_player.body_loadout = load(
		"res://resources/character_loadouts/full_body.tres"
	) as CharacterLoadout
	root.add_child(movement_player)
	movement_player.on_floor = true
	movement_player.footstep_surface = &"metal"
	movement_player.request_jump()
	movement_player.server_physics_tick(1.0 / 60.0)
	_expect(
		movement_player.velocity.y > 0.0
		and movement_player.emitted_sound_ids == [&"jump_metal"],
		"an accepted authoritative jump emits its takeoff cue at the actual launch"
	)
	movement_player.set_wrist_interface_open(true)
	var accepted_hover := movement_player.request_wrist_device_sound(
		&"fieldlink_hover"
	)
	var repeated_hover := movement_player.request_wrist_device_sound(
		&"fieldlink_hover"
	)
	var accepted_click := movement_player.request_wrist_device_sound(
		&"fieldlink_click"
	)
	var accepted_confirm := movement_player.request_wrist_device_sound(
		&"fieldlink_confirm"
	)
	var accepted_warning := movement_player.request_wrist_device_sound(
		&"fieldlink_warning"
	)
	var rejected_unknown := movement_player.request_wrist_device_sound(
		&"arbitrary_client_sound"
	)
	movement_player.set_wrist_interface_open(false)
	var rejected_while_closed := movement_player.request_wrist_device_sound(
		&"fieldlink_click"
	)
	_expect(
		accepted_hover
		and not repeated_hover
		and accepted_click
		and accepted_confirm
		and accepted_warning
		and not rejected_unknown
		and not rejected_while_closed
		and movement_player.emitted_wrist_sound_ids == [
			&"fieldlink_open",
			&"fieldlink_hover",
			&"fieldlink_click",
			&"fieldlink_confirm",
			&"fieldlink_warning",
			&"fieldlink_close",
		],
		"the authoritative wrist state validates, throttles, and emits every device cue"
	)
	movement_player.free()
	metal_floor.free()
	rock.free()
	var library := AUDIO_LIBRARY.new()
	root.add_child(library)
	var client := root.get_node_or_null("Client")
	var renderer := (
		client.get("spatial_audio_renderer") as SpatialAudioRenderer
		if client != null
		else null
	)
	var registrations: Dictionary = renderer.get("_registrations") if renderer != null else {}
	var registered_all := renderer != null
	for sound_id: StringName in ids:
		registered_all = registered_all and registrations.has(sound_id)
	_expect(
		registered_all,
		"client startup registers the complete semantic catalog with the pooled renderer"
	)
	var movement_transients_authored := true
	for surface_spec: Dictionary in AUDIO_LIBRARY.SURFACE_SPECS:
		var surface := str(surface_spec.get("surface", &"concrete"))
		movement_transients_authored = (
			movement_transients_authored
			and is_equal_approx(float(registrations.get(
				StringName("footstep_%s" % surface),
				{}
			).get("foreground_transient_strength", 0.0)), 0.78)
			and is_equal_approx(float(registrations.get(
				StringName("jump_%s" % surface),
				{}
			).get("foreground_transient_strength", 0.0)), 0.58)
			and is_equal_approx(float(registrations.get(
				StringName("landing_%s" % surface),
				{}
			).get("foreground_transient_strength", 0.0)), 0.88)
		)
	_expect(
		movement_transients_authored,
		"every material-aware step, takeoff, and landing preserves its attack around loud radios"
	)
	var pistol_report: Dictionary = registrations.get(&"service_pistol_fire", {})
	var rifle_report: Dictionary = registrations.get(&"automatic_rifle_fire", {})
	_expect(
		(pistol_report.get("pressure_streams", []) as Array).size() == 4
		and (rifle_report.get("pressure_streams", []) as Array).size() == 4
		and is_zero_approx(float(pistol_report.get("pressure_layer_gain_db", 1.0)))
		and is_equal_approx(float(rifle_report.get("pressure_layer_gain_db", 0.0)), 5.5),
		"weapon reports share the catalog while rifle pressure mastering is explicitly calibrated"
	)
	var fieldlink_open: Dictionary = registrations.get(&"fieldlink_open", {})
	var fieldlink_close: Dictionary = registrations.get(&"fieldlink_close", {})
	_expect(
		is_equal_approx(
			float(fieldlink_open.get("start_offset_seconds", 0.0)),
			0.04
		)
		and is_equal_approx(
			float(fieldlink_close.get("start_offset_seconds", 0.0)),
			0.075
		),
		"Fieldlink motion cues skip their authored leading silence"
	)
	library.free()


func _test_curated_prop_contract() -> void:
	var known_assets: Dictionary = CLIENT_COMPLEX_SCRIPT.PROP_SCENES
	var descriptors := LAYOUT.prop_descriptors()
	var unique_names: Dictionary[StringName, bool] = {}
	var valid_descriptors := not descriptors.is_empty()
	for descriptor: Dictionary in descriptors:
		var prop_name: StringName = descriptor.get("name", &"")
		var asset_id: StringName = descriptor.get("asset_id", &"")
		var collision_size: Vector3 = descriptor.get("collision_size", Vector3.ZERO)
		var position: Vector3 = descriptor.get("position", Vector3.INF)
		if (
			prop_name.is_empty()
			or unique_names.has(prop_name)
			or not known_assets.has(asset_id)
			or collision_size.x <= 0.0
			or collision_size.y <= 0.0
			or collision_size.z <= 0.0
			or not position.is_finite()
		):
			valid_descriptors = false
		unique_names[prop_name] = true
	_expect(
		valid_descriptors and known_assets.size() == 8 and descriptors.size() >= 10,
		"shared layout places a valid collision proxy for every selected industrial model"
	)

	var client_complex := CLIENT_COMPLEX_SCENE.instantiate() as Node3D
	var server_complex := SERVER_COMPLEX_SCENE.instantiate() as StaticBody3D
	root.add_child(client_complex)
	root.add_child(server_complex)
	await process_frame
	var paired_count := 0
	for descriptor: Dictionary in descriptors:
		var prop_name := str(descriptor.get("name", ""))
		if (
			client_complex.get_node_or_null(prop_name) != null
			and server_complex.find_child(prop_name + "Collision", true, false) != null
		):
			paired_count += 1
	_expect(
		paired_count == descriptors.size(),
		"all curated prop visuals instantiate with matching authoritative collision"
	)
	client_complex.free()
	server_complex.free()


func _test_curated_nature_contract() -> void:
	var visual_descriptors: Array[Dictionary] = NATURE_LAYOUT.visual_descriptors()
	var collision_descriptors: Array[Dictionary] = NATURE_LAYOUT.collision_descriptors()
	var known_assets: Dictionary = CLIENT_NATURE_SCRIPT.ASSET_SCENES
	var unique_names: Dictionary[StringName, bool] = {}
	var descriptors_valid := visual_descriptors.size() >= 80
	for descriptor: Dictionary in visual_descriptors:
		var descriptor_name: StringName = descriptor.get("name", &"")
		var asset_id: StringName = descriptor.get("asset_id", &"")
		var position: Vector3 = descriptor.get("position", Vector3.INF)
		if (
			descriptor_name.is_empty()
			or unique_names.has(descriptor_name)
			or not known_assets.has(asset_id)
			or not position.is_finite()
		):
			descriptors_valid = false
		unique_names[descriptor_name] = true
	_expect(
		descriptors_valid
		and known_assets.size() == 5
		and collision_descriptors.size() >= 20,
		"curated nature placement uses five known assets with unique deterministic transforms"
	)
	var forest_tree_count := 0
	var garage_quadrant_counts := PackedInt32Array([0, 0, 0, 0])
	var generated_tree_inside_clear_zone := false
	var farthest_garage_tree_distance := 0.0
	for descriptor: Dictionary in visual_descriptors:
		if not str(descriptor.get("name", "")).begins_with("ForestTree_"):
			continue
		forest_tree_count += 1
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var garage_offset := Vector2(position.x, position.z) - NATURE_LAYOUT.GARAGE_CENTER
		var garage_distance := garage_offset.length()
		farthest_garage_tree_distance = maxf(
			farthest_garage_tree_distance,
			garage_distance
		)
		if garage_distance >= 14.0 and garage_distance <= 60.0:
			var quadrant := (2 if garage_offset.y >= 0.0 else 0) + (
				1 if garage_offset.x >= 0.0 else 0
			)
			garage_quadrant_counts[quadrant] += 1
		if (
			absf(garage_offset.x) <= 13.0
			and absf(garage_offset.y) <= 11.0
		):
			generated_tree_inside_clear_zone = true
	print(
		"Forest field: %d trees, %d solid placements, garage quadrants=%s, reach=%.1f m"
		% [
			forest_tree_count,
			collision_descriptors.size(),
			str(garage_quadrant_counts),
			farthest_garage_tree_distance,
		]
	)
	var minimum_garage_quadrant_count := garage_quadrant_counts[0]
	for quadrant_count: int in garage_quadrant_counts:
		minimum_garage_quadrant_count = mini(
			minimum_garage_quadrant_count,
			quadrant_count
		)
	_expect(
		forest_tree_count >= 500
		and collision_descriptors.size() >= 200
		and minimum_garage_quadrant_count >= 20
		and farthest_garage_tree_distance >= 70.0
		and not generated_tree_inside_clear_zone
		and NATURE_LAYOUT.forest_density_at(NATURE_LAYOUT.GARAGE_CENTER + Vector2(60.0, 0.0))
		> NATURE_LAYOUT.forest_density_at(NATURE_LAYOUT.GARAGE_CENTER + Vector2(15.0, 0.0)),
		"the PA bunker has a wide four-sided forest whose configured density increases outward"
	)

	var client_nature := CLIENT_NATURE_SCRIPT.new() as Node3D
	var server_nature := SERVER_NATURE_SCRIPT.new() as Node3D
	root.add_child(client_nature)
	root.add_child(server_nature)
	await process_frame
	var rendered_instance_count := 0
	var batch_count := 0
	for child: Node in client_nature.get_children():
		if child is MultiMeshInstance3D:
			batch_count += 1
			var multimesh := (child as MultiMeshInstance3D).multimesh
			if multimesh != null:
				rendered_instance_count += multimesh.instance_count
	var collision_count := 0
	var baked_convex_count := 0
	var shapes_by_asset: Dictionary[StringName, ConvexPolygonShape3D] = {}
	var descriptor_by_collision_name: Dictionary[String, Dictionary] = {}
	for descriptor: Dictionary in collision_descriptors:
		descriptor_by_collision_name[
			str(descriptor.get("name", &"")) + "Collision"
		] = descriptor
	for body: Node in server_nature.get_children():
		for child: Node in body.get_children():
			if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
				collision_count += 1
				var collision := child as CollisionShape3D
				var shape := collision.shape as ConvexPolygonShape3D
				var asset_id: StringName = collision.get_meta(&"nature_asset_id", &"")
				var descriptor: Dictionary = descriptor_by_collision_name.get(
					str(collision.name),
					{}
				)
				if (
					shape != null
					and shape.points.size() >= 8
					and shape.points.size() <= 32
					and collision.get_meta(&"collision_source", &"") == &"baked_mesh_convex"
					and collision.transform.is_equal_approx(
						NATURE_LAYOUT.descriptor_transform(descriptor)
					)
				):
					baked_convex_count += 1
				if not shapes_by_asset.has(asset_id):
					shapes_by_asset[asset_id] = shape
				elif shapes_by_asset[asset_id] != shape:
					baked_convex_count = -1000
	_expect(
		batch_count == known_assets.size()
		and rendered_instance_count == visual_descriptors.size(),
		"nature visuals batch every placement by source mesh"
	)
	_expect(
		collision_count == collision_descriptors.size()
		and baked_convex_count == collision_count
		and shapes_by_asset.size() == 3
		and PHYSICAL_SURFACE.from_collider(server_nature.get_node("TreeCollision")) == &"wood"
		and PHYSICAL_SURFACE.from_collider(server_nature.get_node("RockCollision")) == &"stone",
		"solid nature assets share bounded Godot-baked convex hulls and material tags"
	)
	await physics_frame
	var first_tree: Dictionary = {}
	var first_rock: Dictionary = {}
	for descriptor: Dictionary in collision_descriptors:
		var collision_kind: StringName = descriptor.get("collision_kind", &"")
		if collision_kind == &"trunk" and first_tree.is_empty():
			first_tree = descriptor
		elif collision_kind == &"rock" and first_rock.is_empty():
			first_rock = descriptor
	var tree_position: Vector3 = first_tree.get("position", Vector3.ZERO)
	var rock_position: Vector3 = first_rock.get("position", Vector3.ZERO)
	var tree_hit := server_nature.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			tree_position + Vector3(-2.0, 1.0, 0.0),
			tree_position + Vector3(2.0, 1.0, 0.0)
		)
	)
	var rock_hit := server_nature.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			rock_position + Vector3.UP * 4.0,
			rock_position + Vector3.DOWN * 2.0
		)
	)
	_expect(
		(tree_hit.get("collider") as Node) == server_nature.get_node("TreeCollision")
		and (rock_hit.get("collider") as Node) == server_nature.get_node("RockCollision"),
		"baked trunk and rock silhouettes participate in authoritative physics queries"
	)
	client_nature.free()
	server_nature.free()

	var client_world_scene := load("res://scenes/proxy/world.tscn") as PackedScene
	var client_world := client_world_scene.instantiate() as Node3D
	var world_environment := client_world.get_node("WorldEnvironment") as WorldEnvironment
	var sky_material := world_environment.environment.sky.sky_material as PanoramaSkyMaterial
	_expect(
		sky_material != null
		and sky_material.panorama != null
		and sky_material.panorama.resource_path == (
			CURATED_ROOT + "environment/skyboxes/bleak_mountains.png"
		)
		and client_world.get_node("WorldNature").get_script() == CLIENT_NATURE_SCRIPT,
		"client world lighting uses the curated Brutal Skyboxes panorama"
	)
	client_world.free()


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", message)
		return
	failure_count += 1
	push_error("[FAIL] %s" % message)


func _finish() -> void:
	if failure_count == 0:
		print("Asset bundle integration tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Asset bundle integration tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)
