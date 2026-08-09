extends SceneTree

const GUN_PATH := (
	"res://resources/items/guns/basic_service_pistol.tres"
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
	_test_warehouse_catalog()
	_test_inventory_fire_and_reload()
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
	_expect(
		is_equal_approx(gun.get_instance_mass(state), build.get_total_mass()),
		"crafted component mass determines the physical gun instance"
	)
	var profile := gun.get_ballistic_profile(state)
	_expect(
		float(profile.get("muzzle_velocity", 0.0)) > 0.0
		and float(profile.get("maximum_range", 0.0)) > 0.0
		and float(profile.get("damage", 0.0)) > 0.0,
		"assembled parts produce a usable ballistic profile"
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
	player.weapon_fire_cooldown_remaining = 0.0
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
	var drone_source := _read_text(
		"res://scripts/server/server_drone.gd"
	)
	var client_source := _read_text("res://scripts/client/client.gd")
	_expect(
		server_source.contains("spawn_ballistic_projectile(")
		and server_source.contains("on_projectile_states_received"),
		"server publishes authoritative projectile state"
	)
	_expect(
		drone_source.contains("Server.spawn_ballistic_projectile(")
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
