extends SceneTree

class DamageTarget:
	extends StaticBody3D

	var damage_received := 0.0

	func apply_damage(amount: float) -> void:
		damage_received += amount


const TEST_DAMAGE := 11.0
const TEST_SPEED := 40.0
const TARGET_DISTANCE := 8.0
const SERVICE_PROJECTILE := preload(
	"res://resources/weapons/projectiles/service_9mm.tres"
)

#######################################################
# Runs headless regression coverage for ballistics runtime integration behavior and reports
# contract or integration failures.
#######################################################

var test_root: Node3D
var server: Node
var client: Node
var game_state: Node
var client_world: Node3D
var emitter: Node3D
var target: DamageTarget
var projectile: ServerProjectile
var elapsed := 0.0
var checked_not_hitscan := false
var impact_observed := false
var impact_observed_at := 0.0
var failure_count := 0
var sound_sequence_before_impact := 0
var expected_impact_sound_id: StringName = &""
var received_impact_packet: Dictionary = {}


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	server = root.get_node_or_null("/root/Server")
	client = root.get_node_or_null("/root/Client")
	game_state = root.get_node_or_null("/root/GameState")
	if server == null or client == null or game_state == null:
		_expect(false, "audio and ballistics autoloads are available to the runtime test")
		_finish()
		return
	game_state.call("reset_session")
	server.call("spawn_server_world")
	var player_id: int = game_state.call("try_register_player", 1, 1000, 4)
	server.call("spawn_server_player", player_id, Vector3(2.0, 3.0, 0.0))
	client_world = (load("res://scenes/proxy/world.tscn") as PackedScene).instantiate()
	root.add_child(client_world)
	await process_frame
	var renderer := client.get("spatial_audio_renderer") as SpatialAudioRenderer
	var registrations: Dictionary = (
		renderer.get("_registrations") if renderer != null else {}
	)
	_expect(
		registrations.has(&"projectile_impact_9mm"),
		"live client world registers the 9mm impact cue"
	)
	var pistol_registration: Dictionary = registrations.get(
		&"service_pistol_fire", {}
	)
	var rifle_registration: Dictionary = registrations.get(
		&"automatic_rifle_fire", {}
	)
	_expect(
		(pistol_registration.get("streams", []) as Array).size() == 4
		and (pistol_registration.get("pressure_streams", []) as Array).size() == 4
		and (rifle_registration.get("streams", []) as Array).size() == 4
		and (rifle_registration.get("pressure_streams", []) as Array).size() == 4
		and float(rifle_registration.get("pressure_layer_gain_db", 0.0)) > 5.0,
		"live pooled renderer retains pistol and calibrated rifle room-pressure registrations"
	)
	client.connect("spatial_sound_received", _on_spatial_sound_received)
	test_root = Node3D.new()
	root.add_child(test_root)
	emitter = Node3D.new()
	emitter.position = Vector3(0.0, 3.0, 0.0)
	test_root.add_child(emitter)
	target = DamageTarget.new()
	target.position = Vector3(0.0, 3.0, -TARGET_DISTANCE)
	target.set_meta(&"physical_surface", &"wood")
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.5, 0.4)
	collision.shape = shape
	target.add_child(collision)
	test_root.add_child(target)

	var projectile_profile := SERVICE_PROJECTILE.to_ballistic_profile()
	projectile_profile["damage"] = TEST_DAMAGE
	projectile_profile["muzzle_velocity"] = TEST_SPEED
	projectile_profile["maximum_range"] = 20.0
	projectile_profile["gravity_scale"] = 0.0
	projectile_profile["impact_impulse"] = 0.0
	expected_impact_sound_id = ServerProjectile.impact_sound_id_for_profile(
		projectile_profile
	)
	projectile = server.call(
		"spawn_ballistic_projectile",
		projectile_profile,
		emitter.global_position,
		Vector3.FORWARD,
		Vector3.ZERO,
		[],
		&"test",
		1,
		emitter
	)
	_expect(projectile != null, "projectile spawns")
	_expect(
		is_zero_approx(target.damage_received),
		"spawning a shot does not apply immediate hitscan damage"
	)
	sound_sequence_before_impact = int(server.get("next_spatial_sound_sequence"))
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	elapsed += 1.0 / float(Engine.physics_ticks_per_second)
	if not checked_not_hitscan and elapsed >= 0.08:
		checked_not_hitscan = true
		_expect(
			is_zero_approx(target.damage_received),
			"target remains unharmed before projectile travel time elapses"
		)
	if target.damage_received > 0.0 and not impact_observed:
		impact_observed = true
		impact_observed_at = elapsed
		_expect(
			is_equal_approx(target.damage_received, TEST_DAMAGE),
			"traveling projectile applies its authored damage once"
		)
		_expect(
			expected_impact_sound_id == &"projectile_impact_9mm"
			and int(server.get("next_spatial_sound_sequence")) == sound_sequence_before_impact + 1,
			"projectile impact emits one server-routed ammunition cue"
		)
	if impact_observed and elapsed >= impact_observed_at + 0.1:
		var renderer := client.get("spatial_audio_renderer") as SpatialAudioRenderer
		var voice_start_times: PackedInt64Array = (
			renderer.get("_voice_started_usec")
			if renderer != null
			else PackedInt64Array()
		)
		var rendered_voice := false
		for started_at: int in voice_start_times:
			if started_at > 0:
				rendered_voice = true
				break
		_expect(
			received_impact_packet.get("sound_id", &"") == &"projectile_impact_9mm",
			"nearby client receives the resolved 9mm impact packet"
		)
		var modifier_ids: PackedStringArray = received_impact_packet.get(
			"modifier_ids",
			PackedStringArray()
		)
		var impact_band_gain: Vector3 = received_impact_packet.get(
			"band_gain",
			Vector3.ZERO
		)
		_expect(
			not modifier_ids.has("generic_solid")
			and impact_band_gain.z > 0.35
			and float(received_impact_packet.get("volume_db", -80.0)) > -15.0,
			"exposed impact stays present instead of self-occluding"
		)
		_expect(
			rendered_voice,
			"registered client renderer allocates and starts an impact voice"
		)
		_finish()
	elif elapsed >= 0.6:
		_expect(false, "projectile reaches and damages the physical target")
		_finish()


func _on_spatial_sound_received(packet: Dictionary) -> void:
	if packet.get("sound_id", &"") == &"projectile_impact_9mm":
		received_impact_packet = packet.duplicate(false)


func _finish() -> void:
	if physics_frame.is_connected(_on_physics_frame):
		physics_frame.disconnect(_on_physics_frame)
	if (
		client != null
		and client.is_connected("spatial_sound_received", _on_spatial_sound_received)
	):
		client.disconnect("spatial_sound_received", _on_spatial_sound_received)
	if (
		is_instance_valid(projectile)
		and server.call("get_server_projectile", projectile.projectile_id) != null
	):
		server.call("despawn_projectile", projectile.projectile_id)
	if failure_count == 0:
		print("Ballistics runtime integration test passed")
		quit(0)
	else:
		push_error(
			"Ballistics runtime integration test failed: %d assertions"
			% failure_count
		)
		quit(1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("FAIL: %s" % description)
