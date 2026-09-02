extends SceneTree

class DamageSink:
	extends StaticBody3D
	var received_event: DamageEvent

	func apply_damage_event(event: DamageEvent) -> Dictionary:
		received_event = event
		return {"changed": true}


const PLAYER_SCENE := preload("res://scenes/server/server_player.tscn")
const CUTTER_DEFINITION := preload(
	"res://resources/items/tools/plasma_cutter_standard.tres"
)
const BEAM_SCRIPT := preload(
	"res://scripts/client/plasma_cutter_beam_3d.gd"
)
const WAREHOUSE_CATALOG := preload(
	"res://scripts/drones/dev_warehouse_catalog.gd"
)

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_authoritative_cut_route()
	_test_cut_only_thermal_overlay()
	_test_physical_emitter_presentation()
	if failure_count == 0:
		print("Plasma cutter runtime tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Plasma cutter runtime tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_authoritative_cut_route() -> void:
	var player := PLAYER_SCENE.instantiate() as ServerPlayer
	player.player_id = 17
	root.add_child(player)
	var sink := DamageSink.new()
	sink.position = Vector3(0.0, 0.56, -2.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 0.2)
	collision.shape = shape
	sink.add_child(collision)
	root.add_child(sink)
	await physics_frame

	player.inventory_entries.append(
		PlayerInventoryRules.make_entry(CUTTER_DEFINITION)
	)
	player.call("_mark_inventory_changed")
	_expect(
		player.get_plasma_cutter_definition() == CUTTER_DEFINITION,
		"the selected inventory item owns the cutter operating envelope"
	)
	var server := root.get_node_or_null("Server")
	_expect(server != null, "the authoritative server coordinator is available")
	_expect(
		server.call("try_primary_action", player)
		and player.plasma_cutter_trigger_held
		and player.plasma_cutter_active,
		"ordinary primary action energizes the selected handheld cutter before the authoritative cut tick"
	)
	server.call("_process_player_plasma_cutter", player)
	var first_query := player.plasma_cutter_ray_query
	server.call("_process_player_plasma_cutter", player)
	_expect(
		first_query != null and player.plasma_cutter_ray_query == first_query,
		"the single discharge reuses its cached physics query without allocating a second one"
	)
	_expect(
		player.plasma_cutter_overheated
		and not player.plasma_cutter_active
		and is_equal_approx(player.plasma_cutter_heat_ratio, 1.0),
		"one authoritative cutter pulse consumes the complete heat cycle"
	)
	var event := sink.received_event
	_expect(
		event != null
		and event.source_kind == &"plasma_cutter"
		and event.source_id == 17
		and event.brush_kind == DamageEvent.BRUSH_CAPSULE,
		"the server ray emits one canonical capsule event owned by the cutting player"
	)
	_expect(
		event != null
		and event.has_tag(DamageEvent.TAG_BLADE)
		and event.has_tag(DamageEvent.TAG_HEAT)
		and event.radius > 0.0
		and event.length > event.radius,
		"the cut carries blade/heat channels and a narrow penetrating kerf"
	)
	_expect(
		player.plasma_cutter_has_hit
		and player.plasma_cutter_hit_position.distance_to(sink.global_position) < 0.25,
		"the authoritative contact endpoint is retained for every client's beam"
	)
	player.suspend_network_input()
	_expect(
		not player.plasma_cutter_active and not player.plasma_cutter_trigger_held,
		"losing the input route cannot leave an authoritative cutter energized"
	)
	player.set_primary_action_held(true)
	player.set_wrist_interface_open(true)
	_expect(
		not player.plasma_cutter_active
		and not player.plasma_cutter_trigger_held,
		"opening Fieldlink disarms the separate handheld cutter immediately"
	)
	player.free()
	sink.free()


func _test_cut_only_thermal_overlay() -> void:
	var volume := DestructibleVolume3D.new()
	volume.volume_id = &"plasma_thermal_test"
	volume.volume_size = Vector3(1.2, 1.0, 0.22)
	volume.voxel_size = 0.055
	volume.brick_cells = 8
	volume.create_collision = false
	root.add_child(volume)
	volume.initialize_volume()
	var ballistic := DamageEvent.from_dict({
		"event_id": 91001,
		"sequence": 91001,
		"source_kind": &"pistol_projectile",
		"source_id": 4,
		"world_position": Vector3(-0.30, 0.0, -0.11),
		"normal": Vector3.FORWARD,
		"direction": Vector3.BACK,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": 0.045,
		"length": 0.22,
		"penetration": 0.22,
		"energy": 18.0,
		"damage_tags": PackedStringArray(["ballistic"]),
	})
	var ballistic_result := volume.apply_authoritative_damage_event(ballistic)
	volume.flush_pending_rebuilds()
	var generated_material := volume.get("_generated_surface_material") as StandardMaterial3D
	var ballistic_thermal: Dictionary = volume.debug_state().get("thermal_cuts", {})
	_expect(
		bool(ballistic_result.get("geometry_changed", false))
		and generated_material != null
		and generated_material.next_pass == null
		and not bool(ballistic_thermal.get("active", true)),
		"ballistic destruction leaves the ordinary wall material untouched and never installs the thermal shader"
	)
	var live_replay := DestructibleVolume3D.new()
	live_replay.volume_id = volume.volume_id
	live_replay.volume_size = volume.volume_size
	live_replay.voxel_size = volume.voxel_size
	live_replay.brick_cells = volume.brick_cells
	live_replay.create_collision = false
	live_replay.authoritative = false
	root.add_child(live_replay)
	live_replay.initialize_volume()
	_expect(
		live_replay.apply_checkpoint(volume.checkpoint()),
		"the live client fixture begins from the authority's cold ballistic revision"
	)
	live_replay.flush_pending_rebuilds()
	var cutter_event := DamageEvent.from_dict({
		"event_id": 91002,
		"sequence": 91002,
		"source_kind": &"plasma_cutter",
		"source_id": 17,
		"world_position": Vector3(0.30, 0.0, -0.11),
		"normal": Vector3.FORWARD,
		"direction": Vector3.BACK,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": CUTTER_DEFINITION.cut_radius,
		"length": CUTTER_DEFINITION.cut_depth,
		"penetration": CUTTER_DEFINITION.cut_depth,
		"energy": CUTTER_DEFINITION.destruction_energy,
		"heat": CUTTER_DEFINITION.heat_energy,
		"damage_tags": PackedStringArray(["blade", "heat"]),
	})
	var cutter_result := volume.apply_authoritative_damage_event(cutter_event)
	volume.flush_pending_rebuilds()
	var replicated_packet := cutter_event.to_dict(true)
	replicated_packet["seed"] = DamageEvent.deterministic_seed(
		volume.volume_id,
		cutter_event.sequence,
		cutter_event.source_id,
		cutter_event.seed
	)
	var replay_cut_result := live_replay.apply_replicated_damage_event(
		DamageEvent.from_dict(replicated_packet),
		int(cutter_result.get("from_revision", -1))
	)
	live_replay.flush_pending_rebuilds()
	var thermal_state: Dictionary = volume.debug_state().get("thermal_cuts", {})
	var thermal_material := generated_material.next_pass as ShaderMaterial
	var checkpoint := volume.checkpoint()
	_expect(
		bool(cutter_result.get("geometry_changed", false))
		and bool(thermal_state.get("active", false))
		and int(thermal_state.get("imprint_count", 0)) == 1
		and thermal_material != null
		and thermal_material.shader == ThermalCutOverlay3D.SHADER
		and int(thermal_material.get_shader_parameter(&"cut_count")) == 1
		and not (checkpoint.get("thermal_cuts", []) as Array).is_empty(),
		"a blade-plus-heat cut installs one localized molten overlay and includes its remaining heat in late-join recovery"
	)
	_expect(
		bool(replay_cut_result.get("geometry_changed", false))
		and bool((live_replay.debug_state().get("thermal_cuts", {}) as Dictionary).get("active", false))
		and live_replay.field.checksum() == volume.field.checksum(),
		"live remote clients replay the same cutter event into matching geometry and a local cooling overlay"
	)
	var replay := DestructibleVolume3D.new()
	replay.volume_id = volume.volume_id
	replay.volume_size = volume.volume_size
	replay.voxel_size = volume.voxel_size
	replay.brick_cells = volume.brick_cells
	replay.create_collision = false
	replay.authoritative = false
	root.add_child(replay)
	replay.initialize_volume()
	var restored := replay.apply_checkpoint(checkpoint)
	replay.flush_pending_rebuilds()
	_expect(
		restored and bool((replay.debug_state().get("thermal_cuts", {}) as Dictionary).get("active", false)),
		"checkpoint clients restore a still-hot cut instead of receiving cold geometry during its visible cooling window"
	)
	var fragment_proxy := DestructionFragmentProxy.new()
	root.add_child(fragment_proxy)
	var fragment_packet := {
		"fragment_id": 901,
		"vertices": PackedVector3Array([
			Vector3(-0.1, 0.0, -0.1),
			Vector3(0.1, 0.0, -0.1),
			Vector3(0.0, 0.18, 0.0),
			Vector3(0.0, 0.0, 0.1),
		]),
		"normals": PackedVector3Array([
			Vector3.UP,
			Vector3.UP,
			Vector3.UP,
			Vector3.UP,
		]),
		"indices": PackedInt32Array([0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3]),
		"surface_mask": PackedColorArray([Color.WHITE, Color.WHITE, Color.BLACK, Color.BLACK]),
		"exterior_color": Color(0.4, 0.42, 0.4),
		"interior_color": Color(0.2, 0.18, 0.16),
		"roughness": 0.8,
		"metallic": 0.1,
		"pos": Vector3.ZERO,
		"rot": Vector3.ZERO,
		"thermal_cut": {
			"position": Vector3.ZERO,
			"direction": Vector3.BACK,
			"radius": 0.04,
			"depth": 0.18,
			"heat": CUTTER_DEFINITION.heat_energy,
		},
	}
	_expect(
		fragment_proxy.apply_spawn_packet(fragment_packet)
		and fragment_proxy.get_node_or_null("ThermalCutOverlay") is ThermalCutOverlay3D
		and bool((fragment_proxy.get_node("ThermalCutOverlay") as ThermalCutOverlay3D).debug_state().get("active", false)),
		"a freshly detached cut fragment retains the same cooling material imprint after becoming its own physics entity"
	)
	var overlay := volume.get_node_or_null("ThermalCutOverlay") as ThermalCutOverlay3D
	overlay._process(ThermalCutOverlay3D.MAX_COOL_SECONDS + 0.1)
	_expect(
		overlay != null
		and generated_material.next_pass == null
		and not bool((overlay.debug_state()).get("active", true)),
		"the glow cools nonlinearly to zero and removes its extra material pass completely"
	)
	volume.free()
	live_replay.free()
	replay.free()
	fragment_proxy.free()


func _test_physical_emitter_presentation() -> void:
	var visual := CUTTER_DEFINITION.instantiate_held_visual({}, true)
	var generic_definition: Resource = CUTTER_DEFINITION
	root.add_child(visual)
	visual.transform = CUTTER_DEFINITION.get_held_visual_transform({}, visual)
	var primary_grip := visual.find_child(
		ItemDefinition.ITEM_GRIP_POINT_NAME,
		true,
		false
	) as Node3D
	var emitter := visual.find_child("PlasmaEmitter", true, false) as Node3D
	var beam := BEAM_SCRIPT.new() as Node3D
	root.add_child(beam)
	beam.call("bind_emitter", emitter)
	var expected_endpoint := (
		emitter.global_position
		- emitter.global_basis.z.normalized() * 2.5
	)
	beam.call(
		"update_beam",
		expected_endpoint,
		true,
		true,
		0.75,
		1.0 / 60.0,
		true
	)
	var core := beam.get_node_or_null("Core") as MeshInstance3D
	var impact := beam.get_node_or_null("Impact") as MeshInstance3D
	_expect(
		emitter != null
		and primary_grip != null
		and generic_definition is ItemDefinition
		and not generic_definition is EquippableItemDefinition,
		"the cutter is an ordinary handheld inventory item with an authored grip and its own muzzle"
	)
	var grip_in_mount := (
		visual.transform * primary_grip.transform
		if primary_grip != null
		else Transform3D.IDENTITY
	)
	_expect(
		primary_grip != null
		and grip_in_mount.origin.length() < 0.0001
		and emitter.global_position.distance_to(primary_grip.global_position) > 0.35,
		"the cutter's ItemGripPoint resolves exactly onto its parent HandGripPoint while its live emitter remains clear"
	)
	var warehouse_has_cutter := false
	for slot_value: Variant in WAREHOUSE_CATALOG.build_layout().get("slots", []):
		var slot: Dictionary = slot_value
		if str(slot.get("definition_path", "")) == CUTTER_DEFINITION.resource_path:
			warehouse_has_cutter = true
			break
	_expect(
		warehouse_has_cutter,
		"the dev warehouse exposes the cutter on its ordinary field-tools shelf"
	)
	_expect(
		beam.visible
		and core != null
		and core.scale.y > 2.4
		and impact != null
		and impact.visible,
		"the beam starts on the handheld tool muzzle and spans the replicated hit distance"
	)
	_expect(
		impact.global_position.distance_to(expected_endpoint) < 0.0001,
		"the local beam snaps to the exact destruction target without visual endpoint lag"
	)
	visual.free()
	beam.free()


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("Plasma cutter assertion failed: %s" % message)
