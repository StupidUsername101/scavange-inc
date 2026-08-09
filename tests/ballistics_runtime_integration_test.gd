extends SceneTree

class DamageTarget:
	extends StaticBody3D

	var damage_received := 0.0

	func apply_damage(amount: float) -> void:
		damage_received += amount


const TEST_DAMAGE := 11.0
const TEST_SPEED := 40.0
const TARGET_DISTANCE := 8.0

#######################################################
# Runs headless regression coverage for ballistics runtime integration behavior and reports
# contract or integration failures.
#######################################################

var test_root: Node3D
var emitter: Node3D
var target: DamageTarget
var projectile: ServerProjectile
var elapsed := 0.0
var checked_not_hitscan := false
var failure_count := 0


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	test_root = Node3D.new()
	root.add_child(test_root)
	emitter = Node3D.new()
	test_root.add_child(emitter)
	target = DamageTarget.new()
	target.position = Vector3(0.0, 0.0, -TARGET_DISTANCE)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.5, 0.4)
	collision.shape = shape
	target.add_child(collision)
	test_root.add_child(target)

	projectile = Server.spawn_ballistic_projectile(
		{
			"damage": TEST_DAMAGE,
			"muzzle_velocity": TEST_SPEED,
			"maximum_range": 20.0,
			"gravity_scale": 0.0,
			"impact_impulse": 0.0,
			"tracer_color": Color.WHITE,
			"tracer_length": 0.5,
			"tracer_radius": 0.015,
		},
		Vector3.ZERO,
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
	physics_frame.connect(_on_physics_frame)


func _on_physics_frame() -> void:
	elapsed += 1.0 / float(Engine.physics_ticks_per_second)
	if not checked_not_hitscan and elapsed >= 0.08:
		checked_not_hitscan = true
		_expect(
			is_zero_approx(target.damage_received),
			"target remains unharmed before projectile travel time elapses"
		)
	if target.damage_received > 0.0:
		_expect(
			is_equal_approx(target.damage_received, TEST_DAMAGE),
			"traveling projectile applies its authored damage once"
		)
		_finish()
	elif elapsed >= 0.6:
		_expect(false, "projectile reaches and damages the physical target")
		_finish()


func _finish() -> void:
	if physics_frame.is_connected(_on_physics_frame):
		physics_frame.disconnect(_on_physics_frame)
	if (
		is_instance_valid(projectile)
		and Server.get_server_projectile(projectile.projectile_id) != null
	):
		Server.despawn_projectile(projectile.projectile_id)
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
