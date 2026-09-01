extends SceneTree

class FragmentVolumeStub:
	extends Node3D
	var volume_id := &"fragment_test_wall"

var assertions := 0
var failures := 0
var test_root: Node3D


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	test_root = Node3D.new()
	root.add_child(test_root)
	var kernel := SdfDualContouringMesher.create_native_kernel()
	_expect(
		kernel != null
		and kernel.has_method(&"map_structural_components")
		and kernel.has_method(&"map_load_bearing_components")
		and kernel.has_method(&"map_cached_load_bearing_components")
		and kernel.has_method(&"capture_cached_fragment_tile")
		and kernel.has_method(&"erase_cached_cells"),
		"the native backend exposes allocation-reusing connectivity and load-bearing mappers"
	)
	_expect_face_connected_support(kernel)
	_expect_load_bearing_ligament_rules(kernel)
	_expect_grounded_horizontal_split(kernel)
	var first := _build_detached_center_fixture(true)
	var second := _build_detached_center_fixture(false)
	var support_selection := SdfStructuralFragmenter.select_detached_components([
		{"id": 0, "cell_count": 8, "connects_outside": true},
		{"id": 1, "cell_count": 80, "connects_outside": false},
	], 1)
	_expect(
		support_selection.size() == 1
		and int(support_selection[0].get("id", -1)) == 1,
		"boundary support detaches a larger severed slab instead of preserving it by size"
	)
	var first_result: Dictionary = first.get("result", {})
	var fragments: Array = first_result.get("detached_fragments", [])
	_expect(
		int(first_result.get("detached_component_count", 0)) == 1
		and fragments.size() == 1,
		"localized face-neighbour mapping finds the unsupported center island"
	)
	_expect(
		int(first_result.get("fragment_scan_cells", 0)) < 10000,
		"structural mapping stays inside the merged damage neighborhood"
	)
	var descriptor: Dictionary = fragments[0] if not fragments.is_empty() else {}
	_expect(
		not (descriptor.get("vertices", PackedVector3Array()) as PackedVector3Array).is_empty()
		and not (descriptor.get("indices", PackedInt32Array()) as PackedInt32Array).is_empty(),
		"the component is extracted as indexed physics/render geometry before erasure"
	)
	var field := first.get("field") as SparseSdfVolumeData
	var fragment_locality := _mesh_triangle_locality(descriptor, field.voxel_size)
	_expect(
		int(fragment_locality.get("nonlocal_triangles", -1)) == 0,
		"detached fragment triangles remain within their source contour cells"
	)
	_expect(
		field != null and field.sample_distance(Vector3.ZERO) > 0.0,
		"detached material is removed from the authoritative wall SDF"
	)
	var second_field := second.get("field") as SparseSdfVolumeData
	_expect(
		field != null and second_field != null and field.checksum() == second_field.checksum(),
		"native and portable fallback component removal produce the same wall checksum"
	)
	await _expect_rebuilt_wall_has_no_fragment_remnant(first.get("texture") as DestructionTextureDefinition)
	await _expect_real_profile_large_break_is_local()
	_expect_large_flat_fragment_uses_bounded_tiles()

	var volume_stub := FragmentVolumeStub.new()
	test_root.add_child(volume_stub)
	var body := DestructionFragment3D.new()
	test_root.add_child(body)
	var texture := first.get("texture") as DestructionTextureDefinition
	var event := first.get("event") as DamageEvent
	_expect(
		body.configure(7, volume_stub, descriptor, texture, event)
		and body.get_node_or_null("FragmentCollision") is CollisionShape3D
		and (body.get_node("FragmentCollision") as CollisionShape3D).shape is ConvexPolygonShape3D
		and (body.get_meta("grip_surface_tags", PackedStringArray()) as PackedStringArray).has(
			"carryable"
		)
		and StringName(body.get_meta("salvage_material_id", &"")) == texture.texture_id
		and is_equal_approx(
			float(body.get_meta("salvage_volume_m3", -1.0)),
			float(descriptor.get("estimated_volume", 0.0))
		),
		"detached geometry becomes a dynamic Jolt-compatible convex body"
	)
	var server := root.get_node_or_null("/root/Server")
	var grabber := GrabberComponent.new()
	grabber.capability = GrabCapability.new()
	test_root.add_child(grabber)
	grabber.global_position = body.global_position + Vector3(0.0, 0.0, 2.0)
	var grabbed := bool(server.call("try_begin_grab", grabber, {
		"collider": body,
		"position": body.global_position,
	})) if server != null else false
	_expect(
		grabbed
		and server.call("get_grabbed_body", grabber) == body
		and body.is_being_grabbed(),
		"E routes a detached fragment through the ordinary authoritative item grab controller"
	)
	var age_while_held := float(body.get("_age_seconds"))
	body.call("_physics_process", 1.0)
	_expect(
		is_equal_approx(float(body.get("_age_seconds")), age_while_held),
		"a carried salvage fragment cannot expire out of the player's hands"
	)
	if server != null:
		server.call("end_grab", grabber)
	_expect(
		not body.is_being_grabbed()
		and server.call("get_grabbed_body", grabber) == null,
		"releasing E returns detached geometry to ordinary rigid-body simulation"
	)
	var initial_height := body.global_position.y
	for _frame: int in range(8):
		await physics_frame
	_expect(
		body.global_position.y < initial_height or body.linear_velocity.y < -0.01,
		"the fragment is simulated by gravity instead of remaining in the wall"
	)
	_expect(
		(body.spawn_packet().get("pos", Vector3.ZERO) as Vector3).is_equal_approx(
			body.global_position
		),
		"late-join manifests seed debris at its current authoritative transform"
	)
	var proxy := DestructionFragmentProxy.new()
	test_root.add_child(proxy)
	_expect(
		proxy.apply_spawn_packet(body.spawn_packet())
		and proxy.get_child_count() == 1,
		"the reliable fragment manifest reconstructs matching client geometry"
	)
	var held_motion := body.to_motion_state_dict()
	held_motion["pos"] = body.global_position + Vector3(0.3, 0.2, -0.1)
	held_motion["fragment_motion_sequence"] = 4
	held_motion["grabber_player_id"] = 17
	proxy.apply_server_motion_state(held_motion)
	_expect(
		(proxy.get("target_position") as Vector3).is_equal_approx(held_motion["pos"])
		and int(proxy.get("last_motion_sequence")) == 4
		and int(proxy.get("grabbed_by_player_id")) == 17,
		"remote clients receive the same physics-rate held-motion lane as authored items"
	)
	var released_motion := body.to_state_dict()
	released_motion["grabber_player_id"] = -1
	proxy.apply_server_state(released_motion)
	_expect(
		int(proxy.get("grabbed_by_player_id")) == -1,
		"the bulk fragment snapshot clears held presentation after release"
	)
	await _expect_detached_fragment_can_be_cut_again(texture)
	var client := root.get_node_or_null("/root/Client")
	var client_script := client.get_script() as Script if client != null else null
	var client_config: Dictionary = client_script.get_rpc_config() if client_script != null else {}
	_expect(
		client_config.has("on_destruction_fragment_spawned")
		and client_config.has("on_destruction_fragment_geometry_changed")
		and client_config.has("on_destruction_fragment_removed")
		and client_config.has("on_destruction_fragment_states_received")
		and client_config.has(
			"on_grabbed_destruction_fragment_motion_states_received"
		),
		"fragment spawn, recursive remesh/removal, snapshots and held motion have explicit RPCs"
	)

	test_root.queue_free()
	await process_frame
	if failures == 0:
		print("Destruction fragmentation tests passed: %d assertions" % assertions)
		quit(0)
	else:
		push_error("Destruction fragmentation tests failed: %d/%d" % [failures, assertions])
		quit(1)


func _expect_face_connected_support(kernel: Object) -> void:
	var cell_size := Vector3i(4, 4, 2)
	var sample_size := cell_size + Vector3i.ONE
	var distances := PackedFloat32Array()
	distances.resize(sample_size.x * sample_size.y * sample_size.z)
	distances.fill(1.0)
	# Each negative sample expands into a conservative 2x2x2 occupied-cell cluster. These clusters
	# meet only diagonally in XY: the old 26-neighbour flood called that a load-bearing connection and
	# left exactly the kind of one-voxel splinter this regression covers.
	for sample: Vector3i in [Vector3i(1, 1, 1), Vector3i(3, 3, 1)]:
		distances[sample.x + sample_size.x * (sample.y + sample_size.y * sample.z)] = -1.0
	var anchors := PackedByteArray([0, 0, 0, 0, 0, 0])
	var native_mapping := kernel.call(
		&"map_structural_components", distances, cell_size, anchors
	) as Dictionary
	var portable_mapping := SdfStructuralFragmenter._map_components_scripted(
		distances, cell_size, anchors
	)
	_expect(
		(native_mapping.get("components", []) as Array).size() == 2,
		"native structural support rejects edge/corner-only voxel contact"
	)
	_expect(
		(portable_mapping.get("components", []) as Array).size() == 2,
		"portable structural support matches native shared-face connectivity"
	)


func _expect_detached_fragment_can_be_cut_again(
	base_texture: DestructionTextureDefinition
) -> void:
	var texture := base_texture.duplicate(true) as DestructionTextureDefinition
	texture.spatial_warp = 0.0
	texture.crack_count = 0
	texture.minimum_fragment_volume = 0.0001
	texture.maximum_physical_fragments = 8
	var source := SparseSdfVolumeData.new().configure(
		Vector3(1.6, 0.65, 0.30),
		0.05,
		12,
		texture.material_index,
		4.0
	)
	var logical_cells := Vector3i(
		ceili(source.size.x / source.voxel_size),
		ceili(source.size.y / source.voxel_size),
		ceili(source.size.z / source.voxel_size)
	)
	var cells: Array[Vector3i] = []
	for z: int in range(logical_cells.z):
		for y: int in range(logical_cells.y):
			for x: int in range(logical_cells.x):
				cells.append(Vector3i(x, y, z))
	var descriptor := SdfStructuralFragmenter._build_fragment_mesh(
		source,
		cells,
		Vector3i.ZERO,
		logical_cells - Vector3i.ONE
	)
	descriptor["estimated_volume"] = source.size.x * source.size.y * source.size.z
	var stub := FragmentVolumeStub.new()
	stub.volume_id = &"recursive_fragment_source"
	stub.position = Vector3(90.0, 40.0, 90.0)
	test_root.add_child(stub)
	var fragment := DestructionFragment3D.new()
	test_root.add_child(fragment)
	var seed_event := DamageEvent.from_dict({
		"event_id": 8000,
		"sequence": 8000,
		"source_kind": &"fragment_seed",
		"source_id": 8,
		"world_position": stub.global_position,
		"normal": Vector3.FORWARD,
		"direction": Vector3.BACK,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.02,
		"length": 0.4,
		"energy": 0.0,
		"penetration": 0.4,
		"seed": 8000,
	})
	var configured := fragment.configure(71, stub, descriptor, texture, seed_event)
	var before_packet := fragment.spawn_packet()
	var before_vertices: PackedVector3Array = before_packet.get(
		"vertices", PackedVector3Array()
	)
	var recursive_proxy := DestructionFragmentProxy.new()
	test_root.add_child(recursive_proxy)
	var proxy_configured := recursive_proxy.apply_spawn_packet(before_packet)
	var any_changed := false
	var child_descriptor: Dictionary = {}
	for index: int in range(9):
		var local_y := lerpf(-0.28, 0.28, float(index) / 8.0)
		var cut := DamageEvent.from_dict({
			"event_id": 8100 + index,
			"sequence": 8100 + index,
			"source_kind": &"plasma_cutter",
			"source_id": 8,
			"world_position": fragment.to_global(Vector3(0.0, local_y, -0.15)),
			"normal": Vector3.FORWARD,
			"direction": Vector3.BACK,
			"brush_kind": DamageEvent.BRUSH_CAPSULE,
			"radius": 0.085,
			"length": 0.65,
			"energy": 12.0,
			"penetration": 0.65,
			"heat": 8.0,
			"damage_tags": PackedStringArray(["blade", "heat"]),
			"seed": 8100 + index,
		})
		var result := fragment.apply_damage_event(cut)
		any_changed = any_changed or bool(result.get("geometry_changed", false))
		for child_value: Variant in result.get("detached_fragments", []):
			if child_value is Dictionary:
				child_descriptor = child_value
	await process_frame
	await process_frame
	var after_vertices: PackedVector3Array = fragment.spawn_packet().get(
		"vertices", PackedVector3Array()
	)
	var proxy_updated := recursive_proxy.apply_geometry_packet(fragment.geometry_packet())
	var proxy_visual := recursive_proxy.get("_visual") as MeshInstance3D
	var proxy_vertices := PackedVector3Array()
	if proxy_visual != null and proxy_visual.mesh != null:
		proxy_vertices = proxy_visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_expect(
		configured
		and fragment.has_method("apply_damage_event")
		and fragment.get("field") is SparseSdfVolumeData
		and any_changed
		and hash(before_vertices) != hash(after_vertices),
		"a detached rigid fragment retains a cropped SDF and visibly accepts later cutter damage"
	)
	_expect(
		proxy_configured
		and proxy_updated
		and hash(proxy_vertices) == hash(after_vertices)
		and not fragment.spawn_packet().has("sdf_state"),
		"remote presentation replaces exact recursive geometry without transmitting private SDF state"
	)
	_expect(
		not child_descriptor.is_empty()
		and child_descriptor.get("sdf_state", {}) is Dictionary
		and not (child_descriptor.get("sdf_state", {}) as Dictionary).is_empty(),
		"a recursive cut emits another self-contained SDF fragment instead of terminal mesh debris"
	)
	var child := DestructionFragment3D.new()
	test_root.add_child(child)
	_expect(
		not child_descriptor.is_empty()
		and child.configure(72, fragment, child_descriptor, texture, seed_event)
		and child.has_method("apply_damage_event"),
		"recursively split children enter the same damage and interaction contract as their parent"
	)
func _expect_load_bearing_ligament_rules(kernel: Object) -> void:
	var cell_size := Vector3i(17, 11, 5)
	var thin := _two_slab_support_fixture(cell_size, 1)
	var anchors := PackedByteArray([1, 0, 0, 0, 0, 0])
	var portable := SdfStructuralFragmenter._map_load_bearing_from_solid(
		thin,
		cell_size,
		anchors,
		0.13
	)
	var portable_components: Array = portable.get("components", [])
	var detached := SdfStructuralFragmenter.select_detached_components(
		portable_components,
		int(portable.get("largest_component", -1))
	)
	_expect(
		bool(portable.get("support_refined", false))
		and int(portable.get("weak_bond_count", 0)) == 1
		and portable_components.size() == 2
		and detached.size() == 1
		and int(detached[0].get("cell_count", 0)) > 250,
		"a large slab carried by one hidden voxel-wide ligament becomes a detached region"
	)
	var broad := _two_slab_support_fixture(cell_size, 5)
	var broad_mapping := SdfStructuralFragmenter._map_load_bearing_from_solid(
		broad,
		cell_size,
		anchors,
		0.13
	)
	_expect(
		(broad_mapping.get("components", []) as Array).size() == 1
		and SdfStructuralFragmenter.select_detached_components(
			broad_mapping.get("components", []),
			int(broad_mapping.get("largest_component", -1))
		).is_empty(),
		"a broad load-bearing bridge remains part of the anchored wall"
	)
	var tough_mapping := SdfStructuralFragmenter._map_load_bearing_from_solid(
		thin,
		cell_size,
		anchors,
		0.02
	)
	_expect(
		SdfStructuralFragmenter.select_detached_components(
			tough_mapping.get("components", []),
			int(tough_mapping.get("largest_component", -1))
		).is_empty(),
		"the same narrow bond can carry its region when the material authors enough support strength"
	)
	if kernel != null and kernel.has_method(&"map_load_bearing_components"):
		var distances := _sample_distances_for_solid_cells(thin, cell_size)
		var portable_captured := SdfStructuralFragmenter._map_load_bearing_components_scripted(
			distances,
			cell_size,
			anchors,
			0.13
		)
		var native := kernel.call(
			&"map_load_bearing_components",
			distances,
			cell_size,
			anchors,
			0.13
		) as Dictionary
		_expect(
			_native_component_signature(native) == _native_component_signature(portable_captured),
			"native and portable ligament-capacity mapping produce identical support regions"
		)
		var scratch_before := kernel.call(&"scratch_state") as Dictionary
		for _repeat: int in range(6):
			kernel.call(
				&"map_load_bearing_components",
				distances,
				cell_size,
				anchors,
				0.13
			)
		var scratch_after := kernel.call(&"scratch_state") as Dictionary
		var capacities_stable := true
		for key: StringName in [
			&"structural_solid_capacity",
			&"structural_core_capacity",
			&"structural_label_capacity",
			&"structural_queue_capacity",
			&"structural_bond_capacity",
			&"structural_bond_hash_capacity",
		]:
			capacities_stable = (
				int(scratch_before.get(key, -1)) == int(scratch_after.get(key, -2))
				and capacities_stable
			)
		_expect(
			capacities_stable,
			"repeated native support mapping reuses its core, queue, bond, and hash storage"
		)


func _expect_grounded_horizontal_split(kernel: Object) -> void:
	var cell_size := Vector3i(13, 12, 5)
	var anchors := SdfStructuralFragmenter._full_volume_boundary_anchors(
		SdfStructuralFragmenter.ANCHOR_NEGATIVE_Y
	)
	_expect(
		anchors == PackedByteArray([0, 1, 0, 0, 0, 0]),
		"structural face masks preserve the min-X,min-Y,min-Z,max-X,max-Y,max-Z contract"
	)
	var solid := PackedByteArray()
	solid.resize(cell_size.x * cell_size.y * cell_size.z)
	# The unsupported upper slab is deliberately larger. Size must never outrank grounded support.
	for z: int in range(cell_size.z):
		for y: int in range(cell_size.y):
			if y > 3 and y < 7:
				continue
			for x: int in range(cell_size.x):
				solid[x + cell_size.x * (y + cell_size.y * z)] = 1
	var portable := SdfStructuralFragmenter._map_load_bearing_from_solid(
		solid,
		cell_size,
		anchors,
		0.13
	)
	var portable_components: Array = portable.get("components", [])
	var portable_detached := SdfStructuralFragmenter.select_detached_components(
		portable_components,
		int(portable.get("largest_component", -1))
	)
	var detached_minimum: Vector3i = (
		portable_detached[0].get("minimum", Vector3i.ZERO)
		if portable_detached.size() == 1
		else Vector3i.ZERO
	)
	_expect(
		portable_detached.size() == 1
		and detached_minimum.y >= 7
		and int(portable_detached[0].get("id", -1))
		== int(portable.get("largest_component", -2)),
		"a larger upper wall section detaches while the smaller -Y-grounded base remains"
	)
	if kernel != null and kernel.has_method(&"map_load_bearing_components"):
		var native := kernel.call(
			&"map_load_bearing_components",
			_sample_distances_for_solid_cells(solid, cell_size),
			cell_size,
			anchors,
			0.13
		) as Dictionary
		var native_components: Array[Dictionary] = []
		for component_value: Variant in native.get("components", []):
			if component_value is Dictionary:
				native_components.append(component_value)
		var native_detached := SdfStructuralFragmenter.select_detached_components(
			native_components,
			int(native.get("largest_component", -1))
		)
		_expect(
			native_detached.size() == 1
			and (native_detached[0].get("minimum", Vector3i.ZERO) as Vector3i).y >= 6,
			"the C++ structural backend applies the same grounded upper-slab rule"
		)


func _two_slab_support_fixture(cell_size: Vector3i, bridge_width: int) -> PackedByteArray:
	var solid := PackedByteArray()
	solid.resize(cell_size.x * cell_size.y * cell_size.z)
	for z: int in range(cell_size.z):
		for y: int in range(1, cell_size.y - 1):
			for x: int in range(0, 6):
				solid[x + cell_size.x * (y + cell_size.y * z)] = 1
			for x: int in range(10, cell_size.x):
				solid[x + cell_size.x * (y + cell_size.y * z)] = 1
	var first_bridge_y := (cell_size.y - bridge_width) / 2
	for z: int in range(1, cell_size.z - 1):
		for y: int in range(first_bridge_y, first_bridge_y + bridge_width):
			for x: int in range(6, 10):
				solid[x + cell_size.x * (y + cell_size.y * z)] = 1
	return solid


func _sample_distances_for_solid_cells(
	solid: PackedByteArray,
	cell_size: Vector3i
) -> PackedFloat32Array:
	var sample_size := cell_size + Vector3i.ONE
	var distances := PackedFloat32Array()
	distances.resize(sample_size.x * sample_size.y * sample_size.z)
	distances.fill(1.0)
	# This is only a native/portable parity fixture: both paths conservatively classify the same
	# negative-corner sample lattice, including its deliberate one-cell surface dilation.
	for z: int in range(cell_size.z):
		for y: int in range(cell_size.y):
			for x: int in range(cell_size.x):
				if solid[x + cell_size.x * (y + cell_size.y * z)] == 0:
					continue
				for oz: int in range(2):
					for oy: int in range(2):
						for ox: int in range(2):
							var sample := Vector3i(x + ox, y + oy, z + oz)
							distances[sample.x + sample_size.x * (
								sample.y + sample_size.y * sample.z
							)] = -1.0
	return distances


func _native_component_signature(mapping: Dictionary) -> Array:
	var signature: Array = [
		int(mapping.get("weak_bond_count", -1)),
		int(mapping.get("largest_component", -1)),
	]
	for component_value: Variant in mapping.get("components", []):
		var component := component_value as Dictionary
		signature.append([
			int(component.get("cell_count", -1)),
			bool(component.get("connects_outside", false)),
			int(component.get("required_support_faces", -1)),
		])
	return signature


func _build_detached_center_fixture(prefer_native: bool) -> Dictionary:
	var texture := DestructionMaterialRegistry.profile_for(&"concrete").duplicate(true)
	texture.spatial_warp = 0.0
	texture.crack_count = 0
	texture.radius_energy_exponent = 0.0
	texture.entry_radius_scale = 1.0
	texture.channel_radius_scale = 1.0
	texture.entry_depth_scale = 1.0
	texture.exit_spall_radius_scale = 0.0
	texture.minimum_fragment_volume = 0.001
	texture.maximum_physical_fragments = 8
	var field := SparseSdfVolumeData.new()
	field.prefer_native_backend = prefer_native
	field.configure(
		Vector3(2.0, 2.0, 0.32),
		0.05,
		12,
		texture.material_index,
		4.0
	)
	var final_result: Dictionary = {}
	var final_event: DamageEvent
	for index: int in range(12):
		var angle := TAU * float(index) / 12.0
		var point := Vector2(cos(angle), sin(angle)) * 0.32
		var event := DamageEvent.from_dict({
			"event_id": index + 1,
			"sequence": index + 1,
			"source_kind": &"fragment_test",
			"source_id": 1,
			"world_position": Vector3(point.x, point.y, -0.16),
			"normal": Vector3.FORWARD,
			"direction": Vector3.BACK,
			"brush_kind": DamageEvent.BRUSH_CAPSULE,
			"radius": 0.105,
			"length": 1.0,
			"energy": 4.0,
			"impulse": 2.0,
			"penetration": 1.0,
			"damage_tags": PackedStringArray(["ballistic"]),
			"seed": 100 + index,
		})
		final_event = event
		final_result = field.apply_damage_event(
			Vector3(point.x, point.y, -0.16),
			Vector3.BACK,
			Vector3.FORWARD,
			event,
			texture
		)
	return {"field": field, "texture": texture, "event": final_event, "result": final_result}


func _expect_rebuilt_wall_has_no_fragment_remnant(
	texture: DestructionTextureDefinition
) -> void:
	var volume := DestructibleVolume3D.new()
	volume.name = "FragmentRemeshFixture"
	volume.volume_id = &"fragment_remesh_fixture"
	volume.authoritative = false
	volume.volume_size = Vector3(2.0, 2.0, 0.32)
	volume.voxel_size = 0.05
	volume.brick_cells = 12
	volume.destruction_texture = texture.duplicate(true)
	volume.position = Vector3(40.0, 20.0, 40.0)
	test_root.add_child(volume)
	for index: int in range(12):
		var angle := TAU * float(index) / 12.0
		var point := Vector2(cos(angle), sin(angle)) * 0.32
		var event := DamageEvent.from_dict({
			"event_id": 1000 + index,
			"sequence": 1000 + index,
			"source_kind": &"fragment_remesh_test",
			"source_id": 1,
			"world_position": volume.to_global(Vector3(point.x, point.y, -0.16)),
			"normal": Vector3.FORWARD,
			"direction": Vector3.BACK,
			"brush_kind": DamageEvent.BRUSH_CAPSULE,
			"radius": 0.105,
			"length": 1.0,
			"energy": 4.0,
			"impulse": 2.0,
			"penetration": 1.0,
			"damage_tags": PackedStringArray(["ballistic"]),
			"seed": 1100 + index,
		})
		volume.apply_replicated_damage_event(event, volume.field.revision)
	volume.flush_pending_rebuilds()
	await physics_frame
	await physics_frame
	var center := volume.global_position
	var query := PhysicsRayQueryParameters3D.create(
		center + Vector3(0.0, 0.0, -1.0),
		center + Vector3(0.0, 0.0, 1.0)
	)
	var hit := volume.get_world_3d().direct_space_state.intersect_ray(query)
	_expect(
		hit.is_empty(),
		"rebuilt render/collision topology contains no duplicate floating wall remnant"
	)
	var generated_locality := _generated_triangle_locality(volume)
	_expect(
		int(generated_locality.get("nonlocal_triangles", -1)) == 0,
		"post-fragment wall remesh does not contain cross-region triangle sheets"
	)
	volume.queue_free()
	await process_frame


func _expect_real_profile_large_break_is_local() -> void:
	var volume := DestructibleVolume3D.new()
	volume.name = "ConcreteLargeBreakFixture"
	volume.volume_id = &"concrete_large_break_fixture"
	volume.authoritative = false
	volume.create_collision = false
	volume.physical_surface = &"concrete"
	volume.volume_size = Vector3(4.0, 3.0, 0.45)
	volume.voxel_size = 0.06
	volume.brick_cells = 12
	volume.position = Vector3(48.0, 20.0, 48.0)
	test_root.add_child(volume)
	var found_fragment := false
	var all_local := true
	var texture := DestructionMaterialRegistry.profile_for(&"concrete")
	for index: int in range(18):
		var angle := TAU * float(index) / 18.0
		var point := Vector2(cos(angle) * 0.58, sin(angle) * 0.48)
		var event := DamageEvent.from_dict({
			"event_id": 2000 + index,
			"sequence": 2000 + index,
			"source_kind": &"real_profile_large_break",
			"source_id": 1,
			"world_position": volume.to_global(Vector3(point.x, point.y, 0.225)),
			"normal": Vector3.BACK,
			"direction": Vector3.FORWARD,
			"brush_kind": DamageEvent.BRUSH_CAPSULE,
			"radius": 0.05,
			"length": 1.2,
			"energy": 16.0,
			"impulse": 3.0,
			"penetration": 1.2,
			"damage_tags": PackedStringArray(["ballistic"]),
			"seed": 2000 + index,
		})
		var result := volume.apply_replicated_damage_event(event, volume.field.revision)
		for descriptor_value: Variant in result.get("detached_fragments", []):
			if not descriptor_value is Dictionary:
				continue
			found_fragment = true
			var locality := _mesh_triangle_locality(descriptor_value, volume.voxel_size)
			all_local = int(locality.get("nonlocal_triangles", 0)) == 0 and all_local
		volume.flush_pending_rebuilds()
		var wall_locality := _generated_triangle_locality(volume)
		all_local = int(wall_locality.get("nonlocal_triangles", 0)) == 0 and all_local
	_expect(
		found_fragment and all_local,
		"the shipped brittle concrete profile cannot create long triangle sheets during a large break"
	)
	var logical_cells := Vector3i(
		maxi(ceili(volume.field.size.x / volume.field.voxel_size), 1),
		maxi(ceili(volume.field.size.y / volume.field.voxel_size), 1),
		maxi(ceili(volume.field.size.z / volume.field.voxel_size), 1)
	)
	var orphan_audit := SdfStructuralFragmenter.detach_components(
		volume.field,
		Vector3i.ZERO,
		logical_cells - Vector3i.ONE,
		texture
	)
	_expect(
		int(orphan_audit.get("detached_component_count", -1)) == 0,
		"localized large-break passes leave no splinter-sized unsupported SDF islands"
	)
	volume.queue_free()
	await process_frame


func _expect_large_flat_fragment_uses_bounded_tiles() -> void:
	# Regression for a wall section wider than the former 48-cell cubic extraction guard. Its thin
	# axis must not force a mostly-empty 59^3 allocation, and most importantly it must still produce
	# one complete physical-fragment descriptor instead of being erased without a body.
	var field := SparseSdfVolumeData.new()
	field.prefer_native_backend = true
	field.configure(Vector3(3.2, 1.0, 0.4), 0.05, 12, 1, 4.0)
	var component_minimum := Vector3i(4, 4, 1)
	var component_size := Vector3i(55, 11, 5)
	var component_maximum := component_minimum + component_size - Vector3i.ONE
	var component_cells: Array[Vector3i] = []
	component_cells.resize(component_size.x * component_size.y * component_size.z)
	var write_index := 0
	for z: int in range(component_size.z):
		for y: int in range(component_size.y):
			for x: int in range(component_size.x):
				component_cells[write_index] = component_minimum + Vector3i(x, y, z)
				write_index += 1
	var descriptor := SdfStructuralFragmenter._build_fragment_mesh(
		field,
		component_cells,
		component_minimum,
		component_maximum
	)
	var vertices: PackedVector3Array = descriptor.get("vertices", PackedVector3Array())
	var locality := _mesh_triangle_locality(descriptor, field.voxel_size)
	var bounds := AABB()
	if not vertices.is_empty():
		bounds = AABB(vertices[0], Vector3.ZERO)
		for vertex: Vector3 in vertices:
			bounds = bounds.expand(vertex)
	descriptor["estimated_volume"] = (
		float(component_cells.size()) * pow(field.voxel_size, 3.0)
	)
	var volume_stub := FragmentVolumeStub.new()
	test_root.add_child(volume_stub)
	var body := DestructionFragment3D.new()
	test_root.add_child(body)
	var profile := DestructionMaterialRegistry.profile_for(&"concrete")
	var body_configured := body.configure(99, volume_stub, descriptor, profile, null)
	var collision := body.get_node_or_null("FragmentCollision") as CollisionShape3D
	_expect(
		not descriptor.is_empty()
		and int(descriptor.get("mesh_tile_count", 0)) >= 3
		and bounds.size.x > 2.5
		and int(locality.get("nonlocal_triangles", -1)) == 0,
		"a very large flat wall fragment is tiled into one complete local mesh instead of despawning"
	)
	_expect(
		body_configured
		and collision != null
		and collision.shape is ConvexPolygonShape3D,
		"the merged large-fragment descriptor remains a valid single Jolt body"
	)
	body.queue_free()
	volume_stub.queue_free()


func _generated_triangle_locality(volume: DestructibleVolume3D) -> Dictionary:
	var total_nonlocal := 0
	var maximum_ratio := 0.0
	for child: Node in volume.get_children():
		var visual := child as MeshInstance3D
		if visual == null or not visual.name.begins_with("GeneratedVisual_"):
			continue
		var mesh := visual.mesh as ArrayMesh
		if mesh == null:
			continue
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface_index)
			var locality := _mesh_triangle_locality({
				"vertices": arrays[Mesh.ARRAY_VERTEX],
				"indices": arrays[Mesh.ARRAY_INDEX],
			}, volume.voxel_size)
			total_nonlocal += int(locality.get("nonlocal_triangles", 0))
			maximum_ratio = maxf(maximum_ratio, float(locality.get("maximum_edge_voxels", 0.0)))
	return {
		"nonlocal_triangles": total_nonlocal,
		"maximum_edge_voxels": maximum_ratio,
	}


func _mesh_triangle_locality(mesh_data: Dictionary, voxel_size: float) -> Dictionary:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var maximum_ratio := 0.0
	var nonlocal_triangles := 0
	var safe_voxel := maxf(voxel_size, 0.000001)
	# A dual-contour triangle connects vertices from adjacent cells around one lattice edge. Even if
	# each centroid sits at the far corner of its cell, no edge can span four voxel widths. Anything
	# longer is a post-process remap crossing disconnected contour regions, not valid geometry.
	for offset: int in range(0, indices.size(), 3):
		var first := indices[offset]
		var second := indices[offset + 1]
		var third := indices[offset + 2]
		if (
			first < 0 or first >= vertices.size()
			or second < 0 or second >= vertices.size()
			or third < 0 or third >= vertices.size()
		):
			nonlocal_triangles += 1
			continue
		var longest := maxf(
			vertices[first].distance_to(vertices[second]),
			maxf(
				vertices[second].distance_to(vertices[third]),
				vertices[third].distance_to(vertices[first])
			)
		) / safe_voxel
		maximum_ratio = maxf(maximum_ratio, longest)
		if longest > 4.0:
			nonlocal_triangles += 1
	if nonlocal_triangles > 0:
		print(
			"NONLOCAL TRIANGLE DIAGNOSTIC count=", nonlocal_triangles,
			" maximum_edge_voxels=", maximum_ratio
		)
	return {
		"nonlocal_triangles": nonlocal_triangles,
		"maximum_edge_voxels": maximum_ratio,
	}


func _expect(condition: bool, label: String) -> void:
	assertions += 1
	if condition:
		print("PASS: ", label)
		return
	failures += 1
	push_error("FAIL: %s" % label)
