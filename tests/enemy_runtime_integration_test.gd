extends SceneTree

const TEST_PLAYER_ID := 92001
const TEST_DURATION_SECONDS := 6.0
const METRIC_SAMPLE_START_SECONDS := 0.75
const TRACKING_SAMPLE_END_SECONDS := 2.5
const MOVEMENT_CHECK_SECONDS := 4.5
const MINIMUM_CHASE_SPEED := 1.0
const SPIDER_LIMB_COUNT := 8
const SPIDER_SEGMENT_COUNT := 16
const SPIDER_TOTAL_BONE_COUNT := 17
const QUADRUPED_LIMB_COUNT := 4
const QUADRUPED_SEGMENT_COUNT := 8
const QUADRUPED_TOTAL_BONE_COUNT := 9
const FLOAT_COMPARISON_EPSILON := 0.0001
const MINIMUM_MOVED_DISTANCE := 0.55
const ROAM_RADIUS_TOLERANCE := 0.25
const MAXIMUM_TRACKING_ERROR := 0.65
const MAXIMUM_SEGMENT_LENGTH_ERROR := 0.35
const MAXIMUM_LOCAL_POINT_RADIUS := 4.25
const MAXIMUM_ATTACHMENT_ERROR := 0.24
const MAXIMUM_ROOT_ERROR := 0.02
const MINIMUM_OUTWARD_ALIGNMENT := 0.05
const MAXIMUM_UPRIGHT_ERROR := 0.001
const TEST_LIMB_DAMAGE := 7.0

#######################################################
# Runs headless regression coverage for enemy runtime integration behavior and reports
# contract or integration failures.
#######################################################

var test_root: Node3D
var player: ServerPlayer
var spider: ServerEnemy
var block_creature: ServerEnemy
var elapsed := 0.0
var failure_count := 0
var starting_position := Vector3.ZERO
var saw_step := false
var contract_checked := false
var movement_checked := false
var maximum_tracking_error_during_chase := 0.0
var maximum_segment_length_error := 0.0
var maximum_local_point_radius := 0.0
var maximum_spider_attachment_error := 0.0
var maximum_block_attachment_error := 0.0
var maximum_spider_root_error := 0.0
var maximum_block_root_error := 0.0
var minimum_spider_knee_alignment := 1.0
var minimum_spider_foot_outward_ratio := 1.0


func _init() -> void:
	call_deferred("_setup")


func _setup() -> void:
	test_root = Node3D.new()
	test_root.name = "EnemyRuntimeTestWorld"
	root.add_child(test_root)
	_add_ground()
	_add_player()
	_add_spider()
	_add_block_creature()
	physics_frame.connect(_on_physics_frame)


func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var collision := CollisionShape3D.new()
	collision.shape = WorldBoundaryShape3D.new()
	ground.add_child(collision)
	test_root.add_child(ground)


func _add_player() -> void:
	var scene := load("res://scenes/server/server_player.tscn") as PackedScene
	player = scene.instantiate() as ServerPlayer
	test_root.add_child(player)
	player.setup(TEST_PLAYER_ID, Vector3(8.0, 1.0, 0.0))
	Server.server_players_by_player_id[TEST_PLAYER_ID] = player


func _add_spider() -> void:
	var scene := load("res://scenes/server/server_enemy.tscn") as PackedScene
	var definition := load(
		"res://resources/enemies/giant_spider.tres"
	) as EnemyDefinition
	spider = scene.instantiate() as ServerEnemy
	spider.configure(definition, -1)
	spider.position = Vector3.ZERO
	starting_position = spider.position
	test_root.add_child(spider)
	spider.add_activation_player(TEST_PLAYER_ID)


func _add_block_creature() -> void:
	var scene := load("res://scenes/server/server_enemy.tscn") as PackedScene
	var definition := load(
		"res://resources/enemies/four_legged_block_creature.tres"
	) as EnemyDefinition
	block_creature = scene.instantiate() as ServerEnemy
	block_creature.configure(definition, -2)
	# Keep the two active-ragdoll creatures far enough apart that this attachment
	# regression measures their own joints instead of creature-to-creature hits.
	block_creature.position = Vector3(0.0, 0.0, -8.0)
	test_root.add_child(block_creature)
	block_creature.add_activation_player(TEST_PLAYER_ID)


func _on_physics_frame() -> void:
	elapsed += 1.0 / float(Engine.physics_ticks_per_second)
	if is_instance_valid(spider):
		_sample_spider_metrics()
	_sample_quadruped_metrics()

	if not contract_checked and elapsed >= METRIC_SAMPLE_START_SECONDS:
		contract_checked = true
		_verify_runtime_contracts()

	if not movement_checked and elapsed >= MOVEMENT_CHECK_SECONDS:
		movement_checked = true
		_verify_movement_contracts()

	if elapsed >= TEST_DURATION_SECONDS:
		_finish()


func _sample_spider_metrics() -> void:
	for limb_state: Dictionary in spider.get_limb_state():
		if bool(limb_state.get("stepping", false)):
			saw_step = true
		_sample_limb_geometry(limb_state)

	var rig := spider.physical_limb_rig
	if rig == null or elapsed < METRIC_SAMPLE_START_SECONDS:
		return
	if (
		elapsed <= TRACKING_SAMPLE_END_SECONDS
		and Vector2(spider.velocity.x, spider.velocity.z).length()
		> MINIMUM_CHASE_SPEED
	):
		maximum_tracking_error_during_chase = maxf(
			maximum_tracking_error_during_chase,
			rig.get_maximum_drive_position_error()
		)
	maximum_spider_attachment_error = maxf(
		maximum_spider_attachment_error,
		rig.get_maximum_attachment_error()
	)
	maximum_spider_root_error = maxf(
		maximum_spider_root_error,
		rig.get_root_anchor_position_error()
	)
	minimum_spider_knee_alignment = minf(
		minimum_spider_knee_alignment,
		rig.get_minimum_knee_bend_alignment()
	)
	minimum_spider_foot_outward_ratio = minf(
		minimum_spider_foot_outward_ratio,
		rig.get_minimum_foot_outward_projection_ratio()
	)


func _sample_limb_geometry(limb_state: Dictionary) -> void:
	var limb_index := int(limb_state.get("index", -1))
	var points := PackedVector3Array(
		limb_state.get("points", PackedVector3Array())
	)
	if (
		limb_index < 0
		or limb_index >= spider.definition.physical_anatomy.limbs.size()
		or points.size() != 3
	):
		return
	var limb: EnemyPhysicalLimbDefinition = (
		spider.definition.physical_anatomy.limbs[limb_index]
	)
	maximum_segment_length_error = maxf(
		maximum_segment_length_error,
		maxf(
			absf(points[0].distance_to(points[1]) - limb.upper_length),
			absf(points[1].distance_to(points[2]) - limb.lower_length)
		)
	)
	for point: Vector3 in points:
		maximum_local_point_radius = maxf(
			maximum_local_point_radius,
			point.length()
		)


func _sample_quadruped_metrics() -> void:
	if (
		not is_instance_valid(block_creature)
		or elapsed < METRIC_SAMPLE_START_SECONDS
		or block_creature.physical_limb_rig == null
	):
		return
	maximum_block_attachment_error = maxf(
		maximum_block_attachment_error,
		block_creature.physical_limb_rig.get_maximum_attachment_error()
	)
	maximum_block_root_error = maxf(
		maximum_block_root_error,
		block_creature.physical_limb_rig.get_root_anchor_position_error()
	)


func _verify_runtime_contracts() -> void:
	_verify_spider_rig_contract()
	_verify_quadruped_rig_contract()
	var states := spider.get_limb_state()
	_expect(states.size() == SPIDER_LIMB_COUNT, "runtime publishes all eight legs")
	for state: Dictionary in states:
		var points := PackedVector3Array(
			state.get("points", PackedVector3Array())
		)
		_expect(points.size() == 3, "runtime leg publishes three joint points")
		for point: Vector3 in points:
			_expect(_is_finite_vector(point), "physical leg point remains finite")


func _verify_spider_rig_contract() -> void:
	var rig := spider.physical_limb_rig
	_expect(rig != null, "spider creates its physical limb rig")
	if rig == null:
		return
	_expect(
		rig.get_physical_bone_count() == SPIDER_SEGMENT_COUNT,
		"runtime rig has sixteen physical bones"
	)
	_expect(
		rig.get_total_physical_bone_count() == SPIDER_TOTAL_BONE_COUNT,
		"runtime rig adds one physical chassis anchor"
	)
	_expect(
		rig.get_bone_count() == SPIDER_TOTAL_BONE_COUNT,
		"complete skeleton exists before simulator binding"
	)
	_expect(
		rig.simulator.is_simulating_physics(),
		"physical bone simulator wakes with the zoo enemy"
	)
	_expect(
		rig.has_valid_physical_bindings(true),
		"all physical segments are uniquely bound and simulating"
	)
	_expect(
		rig.has_valid_root_anchor(true),
		"spider root physical bone remains fixed to the chassis"
	)
	_verify_spider_segment_bindings(rig)


func _verify_spider_segment_bindings(
	rig: EnemyPhysicalLimbRig3D
) -> void:
	var bound_ids: Dictionary[int, bool] = {}
	for segment_record: Dictionary in rig.segment_records:
		for segment_name: String in ["upper", "lower"]:
			var bone := segment_record.get(
				segment_name
			) as EnemyPhysicalBone3D
			var expected_id := int(
				segment_record.get("%s_bone_id" % segment_name, -1)
			)
			_expect(
				bone != null and bone.get_bone_id() == expected_id,
				"every physical segment binds to its exact skeleton bone"
			)
			_expect(not bound_ids.has(expected_id), "physical bone IDs are unique")
			_verify_spider_segment_properties(bone, segment_name)
			bound_ids[expected_id] = true


func _verify_spider_segment_properties(
	bone: EnemyPhysicalBone3D,
	segment_name: String
) -> void:
	var limb: EnemyPhysicalLimbDefinition = (
		spider.definition.physical_anatomy.limbs[bone.limb_index]
	)
	var segment_length = (
		limb.upper_length
		if segment_name == "upper"
		else limb.lower_length
	)
	_expect(
		bone.joint_offset.origin.distance_to(
			Vector3.DOWN * segment_length * 0.5
		) < FLOAT_COMPARISON_EPSILON,
		"every segment joint is at its proximal endpoint"
	)
	_expect(
		absf(
			bone.gravity_scale
			- spider.definition.physical_anatomy.driven_gravity_scale
		) < FLOAT_COMPARISON_EPSILON,
		"active physical legs use driven rather than ragdoll gravity"
	)
	_expect(
		not bone.can_sleep,
		"active physical legs cannot sleep behind the moving chassis"
	)


func _verify_quadruped_rig_contract() -> void:
	var rig := block_creature.physical_limb_rig
	_expect(rig != null, "quadruped creates the shared physical limb rig")
	if rig == null:
		return
	_expect(
		rig.get_physical_bone_count() == QUADRUPED_SEGMENT_COUNT,
		"quadruped has eight simulated segment bodies"
	)
	_expect(
		rig.get_total_physical_bone_count() == QUADRUPED_TOTAL_BONE_COUNT,
		"quadruped adds exactly one physical chassis anchor"
	)
	_expect(
		rig.get_bone_count() == QUADRUPED_TOTAL_BONE_COUNT,
		"quadruped skeleton derives its size from four limbs"
	)
	_expect(
		rig.has_valid_physical_bindings(true),
		"quadruped segments bind through the same root-anchor contract"
	)
	_expect(
		rig.has_valid_root_anchor(true),
		"quadruped root remains fixed while its limbs simulate"
	)
	_expect(
		block_creature.get_limb_state().size() == QUADRUPED_LIMB_COUNT,
		"quadruped publishes four replicated legs"
	)


func _verify_movement_contracts() -> void:
	var moved_distance := Vector2(
		spider.global_position.x - starting_position.x,
		spider.global_position.z - starting_position.z
	).length()
	_expect(
		moved_distance > MINIMUM_MOVED_DISTANCE,
		"active spider advances toward the player"
	)
	_expect(
		moved_distance <= (
			spider.definition.behavior.roam_radius + ROAM_RADIUS_TOLERANCE
		),
		"spider stays inside its zoo roam envelope"
	)
	_expect(saw_step, "movement activates the alternating physical gait")
	_expect(
		maximum_tracking_error_during_chase < MAXIMUM_TRACKING_ERROR,
		"physical legs track a moving chassis without trailing into a smear"
	)
	_expect(
		maximum_segment_length_error < MAXIMUM_SEGMENT_LENGTH_ERROR,
		"physical leg joints retain segment lengths while chasing"
	)
	_expect(
		maximum_local_point_radius < MAXIMUM_LOCAL_POINT_RADIUS,
		"all chasing leg points stay bounded around the chassis"
	)
	_expect(
		maximum_spider_attachment_error < MAXIMUM_ATTACHMENT_ERROR,
		"spider hips and knees remain physically attached while chasing"
	)
	_expect(
		maximum_block_attachment_error < MAXIMUM_ATTACHMENT_ERROR,
		"quadruped hips and knees remain physically attached while chasing"
	)
	_expect(
		maximum_spider_root_error < MAXIMUM_ROOT_ERROR,
		"spider physical root follows its moving chassis"
	)
	_expect(
		minimum_spider_knee_alignment > MINIMUM_OUTWARD_ALIGNMENT,
		"every spider knee stays on its authored outward side while chasing"
	)
	_expect(
		minimum_spider_foot_outward_ratio > MINIMUM_OUTWARD_ALIGNMENT,
		"no spider foot is pulled beneath or across its own hip while chasing"
	)
	_expect(
		maximum_block_root_error < MAXIMUM_ROOT_ERROR,
		"quadruped physical root follows its moving chassis"
	)
	_expect(
		absf(spider.global_basis.y.dot(Vector3.UP) - 1.0)
		< MAXIMUM_UPRIGHT_ERROR,
		"stable chassis stays upright"
	)
	var health_before: float = spider.current_health
	var first_bone := spider.physical_limb_rig.segment_records[0].get(
		"upper"
	) as EnemyPhysicalBone3D
	first_bone.apply_damage(TEST_LIMB_DAMAGE)
	_expect(
		spider.current_health == health_before - TEST_LIMB_DAMAGE,
		"hits on physical legs forward damage to the enemy"
	)


func _finish() -> void:
	if physics_frame.is_connected(_on_physics_frame):
		physics_frame.disconnect(_on_physics_frame)
	Server.server_players_by_player_id.erase(TEST_PLAYER_ID)
	if failure_count == 0:
		print("Enemy runtime integration test passed")
		quit(0)
	else:
		push_error("Enemy runtime integration test failed: %d assertions" % failure_count)
		quit(1)


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _expect(condition: bool, description: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("FAIL: %s" % description)
