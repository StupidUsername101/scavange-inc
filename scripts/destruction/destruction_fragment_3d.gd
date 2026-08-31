class_name DestructionFragment3D
extends RigidBody3D

const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")

var fragment_id := -1
var volume_id := &""
var source_volume_id := &""
var field: SparseSdfVolumeData
var lifetime_seconds := 180.0
var estimated_volume_m3 := 0.0
var material_texture_id := &""
var physical_surface_id := &"concrete"
var _age_seconds := 0.0
var _active_grab_count := 0
var _spawn_packet: Dictionary = {}
var _profile: DestructionTextureDefinition
var _pending_damage_notifications: Array[Dictionary] = []
var _damage_commit_queued := false


func configure(
	new_fragment_id: int,
	volume: Node3D,
	descriptor: Dictionary,
	profile: DestructionTextureDefinition,
	event: DamageEvent
) -> bool:
	if volume == null or profile == null:
		return false
	if not _configure_fragment_field(descriptor):
		return false
	fragment_id = new_fragment_id
	volume_id = StringName("fragment_%d" % fragment_id)
	source_volume_id = (
		StringName(str(volume.call("destruction_source_volume_id")))
		if volume.has_method("destruction_source_volume_id")
		else StringName(str(volume.get("volume_id")))
	)
	_profile = profile
	lifetime_seconds = profile.fragment_lifetime_seconds
	estimated_volume_m3 = maxf(float(descriptor.get("estimated_volume", 0.001)), 0.0)
	material_texture_id = profile.texture_id
	physical_surface_id = profile.physical_surface
	mass = clampf(
		estimated_volume_m3 * profile.fragment_density_kg_m3,
		0.05,
		500.0
	)
	linear_damp = 0.08
	angular_damp = 0.12
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	PHYSICAL_SURFACE.apply_to(self, profile.physical_surface)
	# Detached geometry participates in the same generic grip contract as authored items. The tags
	# are deliberately semantic rather than checked by the grab controller, so hands, scanners and
	# the future salvage pipeline can all recognize it without a fragment-only interaction branch.
	set_meta(&"grip_surface_tags", PackedStringArray([
		"carryable",
		"destruction_fragment",
		"salvage",
	]))
	set_meta(&"salvage_material_id", material_texture_id)
	set_meta(&"salvage_volume_m3", estimated_volume_m3)

	global_transform = volume.global_transform * Transform3D(
		Basis.IDENTITY,
		descriptor.get("local_center", Vector3.ZERO)
	)
	if not _apply_geometry_descriptor(descriptor):
		return false
	if event != null:
		_store_thermal_cut(event)
		var direction := event.direction.normalized() if event.direction.length_squared() > 0.000001 else Vector3.UP
		var impulse := direction * maxf(event.impulse, 0.0)
		call_deferred(&"_apply_spawn_impulse", impulse)
	return true


func destruction_source_volume_id() -> StringName:
	return source_volume_id


func _configure_fragment_field(descriptor: Dictionary) -> bool:
	var state_value: Variant = descriptor.get("sdf_state", null)
	if not state_value is Dictionary:
		return false
	var state := state_value as Dictionary
	var dense_sample_size: Vector3i = state.get("dense_sample_size", Vector3i.ZERO)
	var distances: PackedFloat32Array = state.get("distances", PackedFloat32Array())
	field = SparseSdfVolumeData.new().configure(
		state.get("size", Vector3.ONE),
		float(state.get("voxel_size", 0.05)),
		int(state.get("brick_cells", 16)),
		int(state.get("material_index", 1)),
		float(state.get("narrow_band_voxels", 4.0))
	)
	return field.initialize_from_dense_samples(dense_sample_size, distances)


func _apply_geometry_descriptor(descriptor: Dictionary) -> bool:
	var vertices: PackedVector3Array = descriptor.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = descriptor.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = descriptor.get("indices", PackedInt32Array())
	var surface_mask: PackedColorArray = descriptor.get("surface_mask", PackedColorArray())
	if vertices.size() < 4 or normals.size() != vertices.size() or indices.size() < 12:
		return false
	var collision := get_node_or_null("FragmentCollision") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "FragmentCollision"
		add_child(collision)
	var convex := ConvexPolygonShape3D.new()
	convex.points = vertices
	collision.shape = convex
	estimated_volume_m3 = maxf(
		float(descriptor.get("estimated_volume", estimated_volume_m3)),
		0.000001
	)
	mass = clampf(estimated_volume_m3 * _profile.fragment_density_kg_m3, 0.05, 500.0)
	set_meta(&"salvage_volume_m3", estimated_volume_m3)
	_spawn_packet.merge({
		"fragment_id": fragment_id,
		"source_volume_id": source_volume_id,
		"material_texture_id": material_texture_id,
		"physical_surface": physical_surface_id,
		"estimated_volume_m3": estimated_volume_m3,
		"mass_kg": mass,
		"vertices": vertices,
		"normals": normals,
		"indices": indices,
		"surface_mask": surface_mask,
		"exterior_color": _profile.exterior_color,
		"interior_color": _profile.interior_color,
		"roughness": _profile.roughness,
		"metallic": _profile.metallic,
	}, true)
	return true


func apply_damage_event(event: DamageEvent) -> Dictionary:
	if field == null or _profile == null or event == null or not event.is_valid():
		return {"changed": false, "reason": &"invalid_fragment_damage"}
	var canonical_packet := event.to_dict(true)
	canonical_packet["seed"] = DamageEvent.deterministic_seed(
		volume_id,
		event.sequence,
		event.source_id,
		event.seed
	)
	var applied_event := DamageEvent.from_dict(canonical_packet)
	var inverse_basis := global_basis.inverse()
	var previous_revision := field.revision
	var result := field.apply_damage_event(
		to_local(applied_event.world_position),
		inverse_basis * applied_event.direction,
		inverse_basis * applied_event.normal,
		applied_event,
		_profile
	)
	result["volume_id"] = volume_id
	result["from_revision"] = previous_revision
	if not bool(result.get("changed", false)):
		return result
	_pending_damage_notifications.append({"event": applied_event, "result": result})
	if not _damage_commit_queued:
		_damage_commit_queued = true
		call_deferred(&"_flush_pending_damage_results")
	return result


func accepts_current_sdf_hit(world_position: Vector3, world_direction: Vector3) -> bool:
	if field == null:
		return true
	var local_position := to_local(world_position)
	var local_direction := global_basis.inverse() * world_direction
	if local_direction.length_squared() <= 0.000001:
		local_direction = Vector3.FORWARD
	local_direction = local_direction.normalized()
	var probe_distance := field.voxel_size * 0.65
	return (
		field.sample_distance(local_position + local_direction * probe_distance) <= 0.0
		or field.sample_distance(local_position - local_direction * probe_distance) <= 0.0
	)


func _flush_pending_damage_results() -> void:
	_damage_commit_queued = false
	if _pending_damage_notifications.is_empty() or field == null:
		return
	var notifications := _pending_damage_notifications
	_pending_damage_notifications = []
	var descriptor := SdfStructuralFragmenter.build_complete_field_mesh(field)
	var removed := descriptor.is_empty() or not _apply_geometry_descriptor(descriptor)
	if not removed:
		var latest_event := notifications[-1].get("event") as DamageEvent
		if latest_event != null:
			_store_thermal_cut(latest_event)
	var server := get_node_or_null("/root/Server")
	if server != null and server.has_method("on_destruction_fragment_changed"):
		server.call(
			"on_destruction_fragment_changed",
			self,
			notifications,
			{} if removed else geometry_packet(),
			removed
		)


func geometry_packet() -> Dictionary:
	var packet := _spawn_packet.duplicate(false)
	packet.erase("pos")
	packet.erase("rot")
	return packet


func _store_thermal_cut(event: DamageEvent) -> void:
	if not ThermalCutOverlay3D.is_thermal_cut_event(event):
		_spawn_packet.erase("thermal_cut")
		return
	var response_radius := _profile.response_radius(event.radius, event.energy)
	var perforated := _profile.perforates(event.energy)
	var channel_radius := maxf(
		response_radius * (
			lerpf(1.0, _profile.channel_radius_scale, 0.55) if perforated else 0.92
		),
		0.003
	)
	var channel_depth := (
		maxf(event.penetration, response_radius * 3.0) * _profile.penetration_depth_scale
		if perforated
		else response_radius * _profile.entry_depth_scale
	)
	var local_direction := global_basis.inverse() * event.direction
	_spawn_packet["thermal_cut"] = {
		"position": to_local(event.world_position),
		"direction": local_direction.normalized(),
		"radius": channel_radius,
		"depth": maxf(channel_depth, channel_radius),
		"heat": event.heat,
	}


func spawn_packet() -> Dictionary:
	var packet := _spawn_packet.duplicate(false)
	# Late joiners receive a manifest before the next unreliable motion snapshot. Seed it with the
	# current rigid transform rather than briefly resurrecting debris at its original wall position.
	packet["pos"] = global_position
	packet["rot"] = global_rotation
	return packet


func to_state_dict() -> Dictionary:
	return {
		"fragment_id": fragment_id,
		"pos": global_position,
		"rot": global_rotation,
		"linear_velocity": linear_velocity,
		"angular_velocity": angular_velocity,
	}


func to_motion_state_dict() -> Dictionary:
	# Lifecycle and geometry stay on the reliable manifest/bulk snapshot paths. This compact state is
	# only used while a player is actively carrying the fragment, matching held-item replication.
	return to_state_dict()


func on_server_grab_started() -> void:
	_active_grab_count += 1
	sleeping = false


func on_server_grab_ended() -> void:
	_active_grab_count = maxi(_active_grab_count - 1, 0)


func is_being_grabbed() -> bool:
	return _active_grab_count > 0


func _apply_spawn_impulse(impulse: Vector3) -> void:
	if is_inside_tree() and impulse.length_squared() > 0.000001:
		apply_central_impulse(impulse)
		apply_torque_impulse(Vector3(impulse.z, impulse.x, impulse.y) * 0.08)


func _physics_process(delta: float) -> void:
	# A piece being transported is gameplay loot, not disposable background debris. Pause expiry
	# while held; dropping it resumes the remaining lifetime rather than resetting it indefinitely.
	if _active_grab_count == 0:
		_age_seconds += delta
	if _age_seconds >= lifetime_seconds:
		queue_free()


func _exit_tree() -> void:
	var server := get_node_or_null("/root/Server")
	if fragment_id < 0 or server == null:
		return
	if server.has_method("release_grabs_for_body"):
		server.call("release_grabs_for_body", self)
	if server.has_method("unregister_destruction_fragment"):
		server.call("unregister_destruction_fragment", fragment_id, self)
