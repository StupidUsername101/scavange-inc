extends SceneTree

const LAYOUT := preload(
	"res://scripts/world/industrial_acoustic_complex_layout.gd"
)
const PARKOUR := preload("res://scripts/world/movement_parkour_layout.gd")
const SERVER_COMPLEX_SCENE := preload(
	"res://scenes/server/industrial_acoustic_complex.tscn"
)
const CLIENT_COMPLEX_SCENE := preload(
	"res://scenes/proxy/industrial_acoustic_complex.tscn"
)
const FULL_BODY := preload(
	"res://resources/character_loadouts/full_body.tres"
)
const STEP := 1.0 / 60.0
const PLAYER_HALF_WIDTH := 0.5


class RecordingServerPlayer:
	extends ServerPlayer

	func _emit_gameplay_sound(
		_sound_id: StringName,
		_max_distance: float,
		_priority: float,
		_local_prediction_key := 0
	) -> void:
		pass


var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_layout_contract()
	await _test_runtime_geometry_and_jump()
	if failure_count == 0:
		print("Movement parkour tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Movement parkour tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_layout_contract() -> void:
	var structural := PARKOUR.structural_boxes()
	var details := PARKOUR.contact_detail_boxes()
	var height_boxes: Array[Dictionary] = []
	var left_treads: Array[Dictionary] = []
	var right_treads: Array[Dictionary] = []
	var hidden_ramp_count := 0
	for descriptor: Dictionary in structural:
		var name := str(descriptor.get("name", ""))
		if name.begins_with("ParkourHeightBox"):
			height_boxes.append(descriptor)
		if name.ends_with("Ramp") and not bool(descriptor.get("visual", true)):
			hidden_ramp_count += 1
	for descriptor: Dictionary in details:
		var name := str(descriptor.get("name", ""))
		if name.begins_with("ParkourMirrorLeftTread"):
			left_treads.append(descriptor)
		elif name.begins_with("ParkourMirrorRightTread"):
			right_treads.append(descriptor)
	_expect(
		height_boxes.size() == PARKOUR.BOX_HEIGHTS.size()
		and details.size()
		== PARKOUR.PRECISION_STAIR_COUNT + PARKOUR.MIRROR_STAIR_COUNT * 2
		and hidden_ramp_count == 3,
		"one shared layout owns the height course and all three smooth-ramp/discrete-tread staircases"
	)
	var box_top_min := INF
	var box_top_max := -INF
	for descriptor: Dictionary in height_boxes:
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var size: Vector3 = descriptor.get("size", Vector3.ZERO)
		box_top_min = minf(box_top_min, position.y + size.y * 0.5)
		box_top_max = maxf(box_top_max, position.y + size.y * 0.5)
	_expect(
		box_top_min <= 0.13
		and box_top_max >= 1.0
		and box_top_max - box_top_min >= 0.85,
		"the box loop spans subtle curb contacts through metre-high split-foot and jump contacts"
	)
	var mirrored_heights := true
	for tread_index: int in range(PARKOUR.MIRROR_STAIR_COUNT):
		var left_position: Vector3 = left_treads[tread_index].get(
			"position", Vector3.ZERO
		)
		var right_position: Vector3 = right_treads[tread_index].get(
			"position", Vector3.ZERO
		)
		mirrored_heights = (
			mirrored_heights
			and is_equal_approx(left_position.y, right_position.y)
			and is_equal_approx(
				left_position.x + right_position.x,
				PARKOUR.CENTER.x * 2.0
			)
		)
	_expect(
		mirrored_heights
		and left_treads.back().get("position", Vector3.ZERO).x
		< PARKOUR.CENTER.x
		and right_treads.back().get("position", Vector3.ZERO).x
		> PARKOUR.CENTER.x,
		"the opposed stairs are exact mirrors whose highest treads face the central gap"
	)

	var equal_height_flight_seconds := (
		2.0 * ServerPlayer.JUMP_VELOCITY / ServerPlayer.GRAVITY
	)
	var walk_range := ServerPlayer.WALK_SPEED * equal_height_flight_seconds
	var run_range := ServerPlayer.RUN_SPEED * equal_height_flight_seconds
	var start := PARKOUR.mirror_jump_start_position(PLAYER_HALF_WIDTH)
	var predicted_landing_x := start.x + run_range
	var landing_bounds := PARKOUR.mirror_landing_center_bounds(
		PLAYER_HALF_WIDTH
	)
	_expect(
		walk_range < PARKOUR.MIRROR_GAP
		and run_range > PARKOUR.MIRROR_GAP
		and predicted_landing_x > landing_bounds.x
		and predicted_landing_x < landing_bounds.y,
		"the nine-metre transfer rejects walking speed while a committed sprint lands inside the far deck"
	)


func _test_runtime_geometry_and_jump() -> void:
	var server_complex := SERVER_COMPLEX_SCENE.instantiate() as StaticBody3D
	var client_complex := CLIENT_COMPLEX_SCENE.instantiate() as Node3D
	root.add_child(server_complex)
	root.add_child(client_complex)
	await physics_frame

	var detail_samples: Array[Dictionary] = []
	var detail_boxes := PARKOUR.contact_detail_boxes()
	detail_samples.append(detail_boxes.front())
	detail_samples.append(detail_boxes[PARKOUR.PRECISION_STAIR_COUNT - 1])
	detail_samples.append(detail_boxes[PARKOUR.PRECISION_STAIR_COUNT])
	detail_samples.append(detail_boxes.back())
	var height_box := _find_descriptor(
		PARKOUR.structural_boxes(),
		"ParkourHeightBox05"
	)
	detail_samples.append(height_box)
	var every_detail_top_matches := true
	for descriptor: Dictionary in detail_samples:
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var size: Vector3 = descriptor.get("size", Vector3.ZERO)
		var query := PhysicsRayQueryParameters3D.new()
		query.from = position + Vector3.UP * 1.0
		query.to = position + Vector3.DOWN * 1.0
		query.collision_mask = CharacterContactLayers.FOOT_CONTACT_DETAIL
		var hit := root.world_3d.direct_space_state.intersect_ray(query)
		every_detail_top_matches = (
			every_detail_top_matches
			and not hit.is_empty()
			and absf(
				(hit.get("position", Vector3.ZERO) as Vector3).y
				- (position.y + size.y * 0.5)
			) < 0.012
		)
	_expect(
		every_detail_top_matches,
		"client foot rays resolve the real first, final, mirrored, and height-box top surfaces"
	)
	_expect(
		client_complex.get_node_or_null("ParkourHeightBox01") != null
		and client_complex.get_node_or_null("ParkourPrecisionTread01") != null
		and client_complex.get_node_or_null("ParkourMirrorLeftTread12") != null
		and client_complex.get_node_or_null("ParkourMirrorRightTread12") != null
		and client_complex.get_node_or_null("ParkourJumpEdgeLeft") != null
		and client_complex.get_node_or_null("ParkourJumpEdgeRight") != null
		and client_complex.get_node_or_null("ParkourMirrorLeftRamp") == null,
		"the proxy renders every test contact and edge marker while keeping movement-guide ramps invisible"
	)

	var player := _make_physics_player()
	var takeoff_surface := PARKOUR.mirror_jump_start_position(PLAYER_HALF_WIDTH)
	player.global_position = takeoff_surface + Vector3.UP * (
		ServerPlayer.STANDING_COLLISION_HEIGHT * 0.5 + 0.01
	)
	player.velocity = Vector3(ServerPlayer.RUN_SPEED, 0.0, 0.0)
	player.on_floor = true
	player.set_input(Vector2.UP, -PI * 0.5, 0.0, true)
	player.request_jump()
	var saw_airborne := false
	var landed := false
	for _frame: int in range(120):
		player.server_physics_tick(STEP)
		saw_airborne = saw_airborne or not player.on_floor
		if saw_airborne and player.on_floor:
			landed = true
			break
	var landing_bounds := PARKOUR.mirror_landing_center_bounds(
		PLAYER_HALF_WIDTH
	)
	_expect(
		landed
		and not player.ragdoll_active
		and player.global_position.x > landing_bounds.x
		and player.global_position.x < landing_bounds.y
		and absf(
			player.global_position.z
			- (PARKOUR.CENTER.z + PARKOUR.MIRROR_Z_OFFSET)
		) < 0.25,
		"the authoritative controller completes the opposed-stair sprint jump and lands supported on the far deck"
	)

	player.free()
	server_complex.free()
	client_complex.free()


func _make_physics_player() -> RecordingServerPlayer:
	var player := RecordingServerPlayer.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		PLAYER_HALF_WIDTH * 2.0,
		ServerPlayer.STANDING_COLLISION_HEIGHT,
		PLAYER_HALF_WIDTH * 2.0
	)
	collision.shape = shape
	player.add_child(collision)
	var grabber := GrabberComponent.new()
	grabber.name = "Grabber"
	grabber.capability = GrabCapability.new()
	player.add_child(grabber)
	player.body_loadout = FULL_BODY
	root.add_child(player)
	return player


func _find_descriptor(
	descriptors: Array[Dictionary],
	name: String
) -> Dictionary:
	for descriptor: Dictionary in descriptors:
		if str(descriptor.get("name", "")) == name:
			return descriptor
	return {}


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] " + message)
		return
	failure_count += 1
	push_error("FAIL: " + message)
