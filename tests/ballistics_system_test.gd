extends SceneTree

const GUN_PATH := (
	"res://resources/items/guns/basic_service_pistol.tres"
)
const RIFLE_PATH := (
	"res://resources/items/guns/warehouse_automatic_rifle.tres"
)
const WAREHOUSE_CATALOG := preload(
	"res://scripts/drones/dev_warehouse_catalog.gd"
)
const DRONE_WEAPON_PATHS: Array[String] = [
	"res://resources/drones/attachments/scrap_nailgun.tres",
	"res://resources/drones/attachments/industrial_coilgun.tres",
]

#######################################################
# Runs headless regression coverage for ballistics system behavior and reports contract or
# integration failures.
#######################################################

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_modular_gun_contract()
	_test_automatic_rifle_contract()
	_test_warehouse_catalog()
	_test_inventory_fire_and_reload()
	_test_automatic_fire_cadence()
	_test_drone_projectile_profiles()
	_test_intercept_solution()
	_test_projectile_network_wiring()

	if failure_count == 0:
		print(
			"Ballistics system tests passed: %d assertions"
			% assertion_count
		)
		quit(0)
	else:
		push_error(
			"Ballistics system tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_modular_gun_contract() -> void:
	var gun := load(GUN_PATH) as GunItemDefinition
	_expect(gun != null, "basic service pistol loads")
	if gun == null:
		return
	var state := gun.make_default_instance_state()
	var build := gun.get_build(state)
	_expect(build.is_complete(), "default gun build contains every component")
	_expect(build.is_compatible(), "default gun components share one caliber")
	_expect(
		build.receiver.resource_path.contains("/parts/")
		and build.barrel.resource_path.contains("/parts/")
		and build.magazine.resource_path.contains("/parts/")
		and build.ammunition.resource_path.contains("/parts/"),
		"receiver, barrel, magazine and ammunition are independent resources"
	)
	_expect(
		int(state.get("rounds", 0)) == build.get_magazine_capacity(),
		"new gun state begins with one full magazine"
	)
	var build_signature := str(state.get(
		GunItemDefinition.BUILD_SIGNATURE_KEY,
		""
	))
	var fired_state := gun.consume_round(state)
	_expect(
		not build_signature.is_empty()
		and build_signature == build.visual_signature()
		and str(fired_state.get(
			GunItemDefinition.BUILD_SIGNATURE_KEY,
			""
		)) == build_signature,
		"gun visuals use one stable build signature that survives ammunition mutations"
	)
	_expect(
		is_equal_approx(gun.get_instance_mass(state), build.get_total_mass()),
		"crafted component mass determines the physical gun instance"
	)
	var world_visual := gun.instantiate_visual_from_state(state)
	_expect(
		gun.authored_visual_scene != null
		and world_visual.find_child("AuthoredPistolModel", true, false) != null
		and world_visual.find_child(
			ItemDefinition.ITEM_GRIP_POINT_NAME,
			true,
			false
		) != null,
		"the service pistol uses the same authored model and handle anchor as a world item"
	)
	world_visual.free()
	var profile := gun.get_ballistic_profile(state)
	_expect(
		float(profile.get("muzzle_velocity", 0.0)) > 0.0
		and float(profile.get("maximum_range", 0.0)) > 0.0
		and float(profile.get("damage", 0.0)) > 0.0
		and profile.get("impact_sound_id", &"") == &"projectile_impact_9mm"
		and float(profile.get("impact_sound_volume_db", 0.0)) >= 3.0,
		"assembled parts produce a usable ballistic profile"
	)
	var fire_sound := build.get_fire_sound_profile()
	_expect(
		fire_sound.get("sound_id", &"") == &"service_pistol_fire"
		and float(fire_sound.get("max_distance", 0.0)) >= 100.0
		and float(fire_sound.get("pressure_strength", 0.0)) >= 0.9,
		"assembled service receiver exposes its spatial report and pressure profile"
	)

	var incompatible := build.duplicate(true) as GunBuild
	incompatible.barrel = build.barrel.duplicate(true) as GunBarrelDefinition
	incompatible.barrel.caliber_id = &"12ga"
	_expect(
		not incompatible.is_compatible(),
		"caliber mismatch prevents an invalid crafted gun from firing"
	)
	var removable := build.duplicate(true) as GunBuild
	var removed := removable.remove_part(
		GunPartDefinition.PartSlot.BARREL
	)
	_expect(
		removed is GunBarrelDefinition
		and not removable.is_complete()
		and removable.install_part(removed)
		and removable.is_compatible(),
		"shared slot API supports partial builds and reinstalling parts"
	)


func _test_automatic_rifle_contract() -> void:
	var rifle := load(RIFLE_PATH) as GunItemDefinition
	_expect(rifle != null, "warehouse automatic rifle loads")
	if rifle == null:
		return
	var state := rifle.make_default_instance_state()
	var build := rifle.get_build(state)
	var profile := build.get_ballistic_profile()
	_expect(
		build.is_compatible()
		and build.is_automatic()
		and rifle.is_automatic(state),
		"rifle build is caliber-compatible and explicitly automatic"
	)
	_expect(
		build.get_magazine_capacity() == 30
		and float(profile.get("rounds_per_second", 0.0)) >= 9.0
		and float(profile.get("muzzle_velocity", 0.0)) > 100.0
		and profile.get("impact_sound_id", &"") == &"projectile_impact_556",
		"rifle exposes its 30-round magazine, automatic cadence, and rifle ballistics"
	)
	var sound_profile := build.get_fire_sound_profile()
	_expect(
		sound_profile.get("sound_id", &"") == &"automatic_rifle_fire"
		and sound_profile.get("sound_id", &"") != &"service_pistol_fire"
		and float(sound_profile.get("pressure_strength", 0.0)) >= 1.0,
		"rifle publishes a distinct full-strength semantic report"
	)
	_expect(
		build.get_reload_sound_id(false) == &"rifle_reload_out"
		and build.get_reload_sound_id(true) == &"rifle_reload_in",
		"rifle receiver selects its matching magazine cues"
	)
	var visual := rifle.instantiate_held_visual(state, true)
	var grip_point := visual.find_child(
		ItemDefinition.ITEM_GRIP_POINT_NAME,
		true,
		false
	) as Node3D
	_expect(
		visual.get_node_or_null("UpperReceiver") != null
		and visual.get_node_or_null("Handguard") != null
		and visual.get_node_or_null("Stock") != null
		and visual.get_node_or_null("MuzzleBrake") != null
		and visual.get_node_or_null("MagazineLower") != null
		and grip_point != null
		and grip_point.position.distance_to(
			Vector3(0.0, -0.19, build.receiver.component_size.z * 0.24)
		) < 0.0001,
		"rifle presentation has a stock, handguard, curved magazine, muzzle detail, and a grip point at its real handle"
	)
	visual.free()

	var sound_spec: Dictionary = {}
	for candidate: Dictionary in GameAudioLibrary.WEAPON_REPORT_SPECS:
		if candidate.get("id", &"") == &"automatic_rifle_fire":
			sound_spec = candidate
			break
	_expect(
		not sound_spec.is_empty()
		and (sound_spec.get("streams", []) as Array).size() == 4
		and (sound_spec.get("pressure_streams", []) as Array).size() == 4
		and float(sound_spec.get("pressure_layer_gain_db", 0.0)) > 5.0,
		"shared client catalog registers four rifle reports and calibrated pressure transients"
	)


func _test_warehouse_catalog() -> void:
	var layout := WAREHOUSE_CATALOG.build_layout()
	var paths: Array[String] = []
	for slot_value: Variant in layout.get("slots", []):
		var slot: Dictionary = slot_value
		paths.append(str(slot.get("definition_path", "")))
	_expect(
		GUN_PATH in paths,
		"basic gun is physically available in the dev warehouse"
	)
	_expect(
		RIFLE_PATH in paths,
		"automatic rifle is physically available in the dev warehouse"
	)
	for part_path: String in [
		"res://resources/guns/parts/stamped_service_receiver.tres",
		"res://resources/guns/parts/service_pistol_barrel.tres",
		"res://resources/guns/parts/compact_service_magazine.tres",
		"res://resources/guns/parts/service_ball_ammunition.tres",
	]:
		_expect(
			part_path in paths,
			"%s is available for future crafting" % part_path.get_file()
		)


func _test_inventory_fire_and_reload() -> void:
	var scene := load(
		"res://scenes/server/server_player.tscn"
	) as PackedScene
	var player := scene.instantiate() as ServerPlayer
	root.add_child(player)
	player.setup(420, Vector3.ZERO)
	var gun := load(GUN_PATH) as GunItemDefinition
	_expect(
		player.try_store_inventory_entry(
			PlayerInventoryRules.make_entry(gun)
		),
		"gun enters the ordinary player inventory"
	)
	var capacity := gun.default_build.get_magazine_capacity()
	for shot_index: int in range(capacity):
		player.weapon_fire_cooldown_remaining = 0.0
		var result := player.try_fire_selected_gun()
		_expect(
			bool(result.get("fired", false)),
			"round %d fires authoritatively" % shot_index
		)
		if shot_index == 0:
			_expect(
				result.get("fire_sound", {}).get("sound_id", &"")
				== &"service_pistol_fire",
				"authoritative fire result carries the receiver's semantic sound"
			)
	player.weapon_fire_cooldown_remaining = 0.0
	var empty_result := player.try_fire_selected_gun()
	_expect(
		bool(empty_result.get("handled", false))
		and not bool(empty_result.get("fired", false)),
		"empty gun consumes the weapon action without spawning a shot"
	)
	_expect(
		player.weapon_reload_remaining > 0.0,
		"empty trigger begins a bounded reload"
	)
	var initial_reload_time := player.weapon_reload_remaining
	player.weapon_fire_cooldown_remaining = 0.0
	player.call(
		"_update_weapon_state",
		initial_reload_time * 0.6
	)
	_expect(
		player.weapon_reload_remaining > 0.0
		and player.weapon_reload_insert_emitted,
		"reload stages the magazine-out and magazine-in cues before completion"
	)
	player.call(
		"_update_weapon_state",
		player.weapon_reload_remaining + 0.01
	)
	var entry := player.get_selected_inventory_entry()
	_expect(
		int(entry.get("instance_state", {}).get("rounds", 0)) == capacity,
		"reload restores the installed magazine capacity"
	)
	player.set_body_loadout(CharacterLoadout.new())
	player.weapon_fire_cooldown_remaining = 0.0
	var armless_result := player.try_fire_selected_gun()
	_expect(
		bool(armless_result.get("handled", false))
		and not bool(armless_result.get("fired", false)),
		"players without arms cannot fire a selected gun"
	)
	player.queue_free()


func _test_automatic_fire_cadence() -> void:
	var scene := load(
		"res://scenes/server/server_player.tscn"
	) as PackedScene
	var rifle_player := scene.instantiate() as ServerPlayer
	root.add_child(rifle_player)
	rifle_player.setup(421, Vector3.ZERO)
	var rifle := load(RIFLE_PATH) as GunItemDefinition
	_expect(
		rifle_player.try_store_inventory_entry(
			PlayerInventoryRules.make_entry(rifle)
		),
		"automatic rifle enters the ordinary player inventory"
	)
	rifle_player.set_primary_action_held(true)
	_expect(
		rifle_player.wants_automatic_fire(),
		"held primary action requests server-driven fire for the automatic receiver"
	)
	var first_shot := rifle_player.try_fire_selected_gun()
	var cooldown := rifle_player.weapon_fire_cooldown_remaining
	rifle_player.call("_update_weapon_state", cooldown * 0.5)
	var early_shot := rifle_player.try_fire_selected_gun()
	rifle_player.call("_update_weapon_state", cooldown * 0.5 + 0.001)
	var next_shot := rifle_player.try_fire_selected_gun()
	_expect(
		bool(first_shot.get("fired", false))
		and not bool(early_shot.get("fired", false))
		and bool(next_shot.get("fired", false)),
		"server cooldown gates held fire to the receiver-authored cadence"
	)
	rifle_player.set_primary_action_held(false)
	_expect(
		not rifle_player.wants_automatic_fire(),
		"releasing primary action immediately clears automatic-fire intent"
	)
	rifle_player.queue_free()

	var pistol_player := scene.instantiate() as ServerPlayer
	root.add_child(pistol_player)
	pistol_player.setup(422, Vector3.ZERO)
	var pistol := load(GUN_PATH) as GunItemDefinition
	pistol_player.try_store_inventory_entry(
		PlayerInventoryRules.make_entry(pistol)
	)
	pistol_player.set_primary_action_held(true)
	_expect(
		not pistol_player.wants_automatic_fire(),
		"held primary action cannot turn the service pistol automatic"
	)
	pistol_player.queue_free()


func _test_drone_projectile_profiles() -> void:
	for weapon_path: String in DRONE_WEAPON_PATHS:
		var weapon := load(weapon_path) as DroneWeaponDefinition
		_expect(weapon != null, "%s loads" % weapon_path.get_file())
		if weapon == null:
			continue
		var profile := weapon.get_ballistic_profile()
		_expect(
			weapon.projectile_definition != null,
			"%s references visible projectile data" % weapon.display_name
		)
		_expect(
			is_equal_approx(
				float(profile.get("damage", -1.0)),
				weapon.damage_per_shot
			)
			and is_equal_approx(
				float(profile.get("muzzle_velocity", -1.0)),
				weapon.projectile_speed
			)
			and is_equal_approx(
				float(profile.get("maximum_range", -1.0)),
				weapon.effective_range
			),
			"%s preserves authored turret performance" % weapon.display_name
		)


func _test_intercept_solution() -> void:
	var origin := Vector3.ZERO
	var target := Vector3(0.0, 0.0, -20.0)
	var velocity := Vector3(5.0, 0.0, 0.0)
	var intercept := BallisticAim.calculate_intercept_point(
		origin,
		target,
		velocity,
		Vector3.ZERO,
		40.0
	)
	var travel_time := origin.distance_to(intercept) / 40.0
	var target_at_impact := target + velocity * travel_time
	_expect(
		intercept.distance_to(target_at_impact) < 0.001,
		"moving-target lead converges at projectile impact time"
	)
	_expect(
		BallisticAim.calculate_intercept_point(
			origin,
			target,
			Vector3.ZERO,
			Vector3.ZERO,
			40.0
		).distance_to(target) < 0.001,
		"stationary targets require no artificial lead"
	)
	var shooter_velocity := Vector3(2.0, 0.0, 0.0)
	var moving_origin_intercept := BallisticAim.calculate_intercept_point(
		origin,
		target,
		velocity,
		shooter_velocity,
		40.0
	)
	var relative_aim := moving_origin_intercept - origin
	var moving_time := relative_aim.length() / 40.0
	var projectile_at_impact := (
		relative_aim.normalized() * 40.0 * moving_time
		+ shooter_velocity * moving_time
	)
	var moving_target_at_impact := target + velocity * moving_time
	_expect(
		projectile_at_impact.distance_to(moving_target_at_impact) < 0.001,
		"lead solution accounts for inherited shooter velocity"
	)
	var gravity_scale := 0.55
	var launch_direction := BallisticAim.calculate_launch_direction(
		origin,
		target,
		Vector3.ZERO,
		Vector3.ZERO,
		32.0,
		gravity_scale
	)
	var horizontal_speed := Vector2(
		launch_direction.x,
		launch_direction.z
	).length() * 32.0
	var ballistic_time := 20.0 / horizontal_speed
	var ballistic_height := (
		launch_direction.y * 32.0 * ballistic_time
		- 0.5 * 9.8 * gravity_scale * ballistic_time * ballistic_time
	)
	_expect(
		absf(ballistic_height) < 0.001,
		"turret launch direction compensates authored projectile gravity"
	)


func _test_projectile_network_wiring() -> void:
	var server_source := _read_text("res://scripts/server/server.gd")
	var replication_source := _read_text(
		"res://scripts/network/server_replication_service.gd"
	)
	var drone_source := _read_text(
		"res://scripts/server/server_drone.gd"
	)
	var client_source := _read_text("res://scripts/client/client.gd")
	_expect(
		server_source.contains("spawn_ballistic_projectile(")
		and replication_source.contains("on_projectile_states_received"),
		"server publishes authoritative projectile state"
	)
	_expect(
		drone_source.contains("server_service.call(")
		and drone_source.contains('"spawn_ballistic_projectile"')
		and not drone_source.contains(
			"collider.call(\"apply_damage\", weapon.damage_per_shot)"
		),
		"drone weapons spawn projectiles instead of applying hitscan damage"
	)
	_expect(
		client_source.contains("spawn_projectile_proxy")
		and client_source.contains("PROJECTILE_PROXY_SCENE"),
		"clients create immediate visible projectile proxies"
	)
	_expect(
		client_source.contains("set_primary_action_held")
		and server_source.contains("player.wants_automatic_fire()"),
		"held trigger state crosses the network once and advances on the server tick"
	)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _expect(condition: bool, description: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: %s" % description)
