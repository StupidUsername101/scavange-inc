class_name LevelAcousticEditorState
extends Node

signal changed
signal selection_changed

const AUTHORING := preload("res://scripts/level_editor/level_acoustic_authoring.gd")
const PROBE_MARKER_SCRIPT := preload(
	"res://scripts/level_editor/level_acoustic_probe_marker.gd"
)
const PORTAL_MARKER_SCRIPT := preload(
	"res://scripts/level_editor/level_acoustic_portal_marker.gd"
)

var marker_root: Node3D
var probes_by_id: Dictionary[int, LevelAcousticProbeMarker] = {}
var portals_by_id: Dictionary[int, LevelAcousticPortalMarker] = {}
var selected_probe_ids: Dictionary[int, bool] = {}
var selected_portal_id := 0
var next_id := 1
var visible_in_editor := false


func configure(root: Node3D) -> void:
	marker_root = root
	_apply_visibility()


func clear() -> void:
	selected_probe_ids.clear()
	selected_portal_id = 0
	if marker_root != null:
		for child: Node in marker_root.get_children():
			marker_root.remove_child(child)
			child.free()
	probes_by_id.clear()
	portals_by_id.clear()
	next_id = 1
	selection_changed.emit()
	changed.emit()


func load_state(
	probes: Array[Dictionary],
	portals: Array[Dictionary],
	next_acoustic_id: int
) -> void:
	_clear_nodes_only()
	var maximum_id := 0
	for raw_probe: Dictionary in probes:
		var probe := _restore_probe(raw_probe)
		if probe != null:
			maximum_id = maxi(maximum_id, probe.probe_id)
	for raw_portal: Dictionary in portals:
		var portal := _restore_portal(raw_portal)
		if portal != null:
			maximum_id = maxi(maximum_id, portal.portal_id)
	next_id = maxi(next_acoustic_id, maximum_id + 1)
	_apply_visibility()
	selection_changed.emit()
	changed.emit()


func capture_state() -> Dictionary:
	var probe_ids: Array[int] = []
	for probe_id: int in probes_by_id:
		probe_ids.append(probe_id)
	probe_ids.sort()
	var probes: Array[Dictionary] = []
	for probe_id: int in probe_ids:
		probes.append(probes_by_id[probe_id].snapshot())
	var portal_ids: Array[int] = []
	for portal_id: int in portals_by_id:
		portal_ids.append(portal_id)
	portal_ids.sort()
	var portals: Array[Dictionary] = []
	for portal_id: int in portal_ids:
		portals.append(portals_by_id[portal_id].snapshot())
	return {
		"probes": probes,
		"portals": portals,
		"next_id": next_id,
	}


func restore_state(state: Dictionary) -> void:
	load_state(
		_typed_dictionary_array(state.get("probes", [])),
		_typed_dictionary_array(state.get("portals", [])),
		int(state.get("next_id", 1))
	)


func set_editor_visible(value: bool) -> void:
	visible_in_editor = value
	_apply_visibility()


func add_probe(position: Vector3, authored := true) -> int:
	var probe_id := _allocate_id()
	var probe := _restore_probe({
		"id": probe_id,
		"position": position,
		"auto_connect": true,
		"auto_connect_radius": AUTHORING.DEFAULT_CONNECT_RADIUS,
		"sample_reflections": true,
		"reflection_sample_distance": AUTHORING.DEFAULT_REFLECTION_DISTANCE,
		"environment_influence_radius": 0.0,
		"reverb_scale": 1.0,
		"authored": authored,
	})
	if probe == null:
		return 0
	select_probe(probe_id, false)
	changed.emit()
	return probe_id


func add_portal(
	probe_a_id: int,
	probe_b_id: int,
	profile := "open",
	anchor_placement_id := 0,
	carries_guided_energy := false
) -> int:
	if (
		not probes_by_id.has(probe_a_id)
		or not probes_by_id.has(probe_b_id)
		or probe_a_id == probe_b_id
		or _portal_exists(probe_a_id, probe_b_id)
	):
		return 0
	var portal_id := _allocate_id()
	var portal := _restore_portal({
		"id": portal_id,
		"probe_a_id": probe_a_id,
		"probe_b_id": probe_b_id,
		"bidirectional": true,
		"carries_guided_energy": carries_guided_energy,
		"profile": profile,
		"anchor_placement_id": anchor_placement_id,
	})
	if portal == null:
		return 0
	select_portal(portal_id)
	changed.emit()
	return portal_id


func portal_from_placement(
	placement: LevelAssetPlacement,
	profile := "open",
	carries_guided_energy := false
) -> int:
	if placement == null:
		return 0
	var endpoints := AUTHORING.portal_endpoints_for_bounds(
		placement.global_transform,
		placement.local_bounds
	)
	if endpoints.size() != 2:
		return 0
	var probe_a_id := add_probe(endpoints[0], true)
	var probe_b_id := add_probe(endpoints[1], true)
	selected_probe_ids.clear()
	return add_portal(
		probe_a_id,
		probe_b_id,
		profile,
		placement.placement_id,
		carries_guided_energy
	)


func link_selected_probes(
	profile := "open",
	carries_guided_energy := false
) -> int:
	var ids: Array[int] = []
	for probe_id: int in selected_probe_ids:
		ids.append(probe_id)
	ids.sort()
	return add_portal(
		ids[0],
		ids[1],
		profile,
		0,
		carries_guided_energy
	) if ids.size() == 2 else 0


func regenerate_automatic_probes(
	world_bounds: Array[AABB],
	spacing: float,
	height: float
) -> int:
	var automatic_ids: Array[int] = []
	for probe_id: int in probes_by_id:
		if not bool(probes_by_id[probe_id].descriptor.get("authored", true)):
			automatic_ids.append(probe_id)
	for probe_id: int in automatic_ids:
		_remove_probe(probe_id)
	var positions := AUTHORING.automatic_ground_probe_positions(
		world_bounds,
		spacing,
		height
	)
	var added := 0
	for position: Vector3 in positions:
		if _nearest_probe_distance_squared(position) < (
			AUTHORING.MIN_PROBE_SEPARATION * AUTHORING.MIN_PROBE_SEPARATION
		):
			continue
		var probe_id := _allocate_id()
		if _restore_probe({
			"id": probe_id,
			"position": position,
			"auto_connect": true,
			"auto_connect_radius": AUTHORING.DEFAULT_CONNECT_RADIUS,
			"sample_reflections": true,
			"reflection_sample_distance": AUTHORING.DEFAULT_REFLECTION_DISTANCE,
			"environment_influence_radius": 0.0,
			"reverb_scale": 1.0,
			"authored": false,
		}) != null:
			added += 1
	selected_probe_ids.clear()
	selected_portal_id = 0
	_refresh_selection_visuals()
	changed.emit()
	return added


func select_probe(probe_id: int, additive: bool) -> void:
	if not probes_by_id.has(probe_id):
		return
	if not additive:
		selected_probe_ids.clear()
		selected_portal_id = 0
	if additive and selected_probe_ids.has(probe_id):
		selected_probe_ids.erase(probe_id)
	else:
		selected_probe_ids[probe_id] = true
	_refresh_selection_visuals()
	selection_changed.emit()


func select_portal(portal_id: int) -> void:
	selected_probe_ids.clear()
	selected_portal_id = portal_id if portals_by_id.has(portal_id) else 0
	_refresh_selection_visuals()
	selection_changed.emit()


func clear_selection() -> void:
	selected_probe_ids.clear()
	selected_portal_id = 0
	_refresh_selection_visuals()
	selection_changed.emit()


func pick(ray_origin: Vector3, ray_direction: Vector3) -> Dictionary:
	var nearest_distance := INF
	var result := {}
	for probe_id: int in probes_by_id:
		var distance := probes_by_id[probe_id].ray_distance(ray_origin, ray_direction)
		if distance < nearest_distance:
			nearest_distance = distance
			result = {"kind": &"probe", "id": probe_id, "distance": distance}
	for portal_id: int in portals_by_id:
		var distance := portals_by_id[portal_id].ray_distance(ray_origin, ray_direction)
		if distance < nearest_distance:
			nearest_distance = distance
			result = {"kind": &"portal", "id": portal_id, "distance": distance}
	return result


func move_single_selected_probe(position: Vector3) -> bool:
	if selected_probe_ids.size() != 1:
		return false
	var probe_id := int(selected_probe_ids.keys()[0])
	var probe := probes_by_id.get(probe_id) as LevelAcousticProbeMarker
	if probe == null or not position.is_finite():
		return false
	probe.position = position
	probe.descriptor["position"] = position
	_refresh_portals_for_probe(probe_id)
	changed.emit()
	return true


func sync_anchored_portals(
	placements_by_id: Dictionary[int, LevelAssetPlacement]
) -> void:
	var changed_any := false
	for portal: LevelAcousticPortalMarker in portals_by_id.values():
		var anchor_id := int(portal.descriptor.get("anchor_placement_id", 0))
		if anchor_id <= 0:
			continue
		var placement := placements_by_id.get(anchor_id) as LevelAssetPlacement
		var probe_a := probes_by_id.get(portal.probe_a_id) as LevelAcousticProbeMarker
		var probe_b := probes_by_id.get(portal.probe_b_id) as LevelAcousticProbeMarker
		if placement == null or probe_a == null or probe_b == null:
			continue
		var endpoints := AUTHORING.portal_endpoints_for_bounds(
			placement.global_transform,
			placement.local_bounds
		)
		if endpoints.size() != 2:
			continue
		if not probe_a.position.is_equal_approx(endpoints[0]):
			probe_a.position = endpoints[0]
			probe_a.descriptor["position"] = endpoints[0]
			changed_any = true
		if not probe_b.position.is_equal_approx(endpoints[1]):
			probe_b.position = endpoints[1]
			probe_b.descriptor["position"] = endpoints[1]
			changed_any = true
		portal.refresh()
	if changed_any:
		changed.emit()


func delete_selection() -> bool:
	if selected_portal_id > 0:
		_remove_portal(selected_portal_id)
		selected_portal_id = 0
		changed.emit()
		selection_changed.emit()
		return true
	if selected_probe_ids.is_empty():
		return false
	var ids: Array[int] = []
	for probe_id: int in selected_probe_ids:
		ids.append(probe_id)
	for probe_id: int in ids:
		_remove_probe(probe_id)
	selected_probe_ids.clear()
	changed.emit()
	selection_changed.emit()
	return true


func remove_portals_anchored_to(placement_ids: Array[int]) -> int:
	var placement_set: Dictionary[int, bool] = {}
	for placement_id: int in placement_ids:
		placement_set[placement_id] = true
	var portal_ids: Array[int] = []
	var endpoint_ids: Array[int] = []
	for portal_id: int in portals_by_id:
		var portal := portals_by_id[portal_id]
		if placement_set.has(int(portal.descriptor.get("anchor_placement_id", 0))):
			portal_ids.append(portal_id)
			endpoint_ids.append(portal.probe_a_id)
			endpoint_ids.append(portal.probe_b_id)
	for portal_id: int in portal_ids:
		_remove_portal(portal_id)
	for probe_id: int in endpoint_ids:
		if probes_by_id.has(probe_id) and not _probe_has_portal(probe_id):
			_remove_probe(probe_id)
	if not portal_ids.is_empty():
		changed.emit()
		selection_changed.emit()
	return portal_ids.size()


func validation_report() -> Dictionary:
	var state := capture_state()
	return AUTHORING.validate(
		state["probes"] as Array[Dictionary],
		state["portals"] as Array[Dictionary]
	)


func selection_label() -> String:
	if selected_portal_id > 0:
		var portal := portals_by_id.get(selected_portal_id) as LevelAcousticPortalMarker
		return (
			"PORTAL %03d  //  %03d ↔ %03d  //  %s"
			% [portal.portal_id, portal.probe_a_id, portal.probe_b_id, str(portal.descriptor.get("profile", "open")).to_upper()]
		) if portal != null else "NO ACOUSTIC SELECTION"
	if selected_probe_ids.size() == 1:
		var probe_id := int(selected_probe_ids.keys()[0])
		return "PROBE %03d  //  %.1f M LINK RADIUS" % [
			probe_id,
			float(probes_by_id[probe_id].descriptor.get("auto_connect_radius", 0.0)),
		]
	if selected_probe_ids.size() > 1:
		return "%d PROBES SELECTED  //  LINK 2 TO MAKE A PORTAL" % selected_probe_ids.size()
	return "NO ACOUSTIC SELECTION"


func single_selected_probe_position() -> Vector3:
	if selected_probe_ids.size() != 1:
		return Vector3.ZERO
	var probe_id := int(selected_probe_ids.keys()[0])
	return probes_by_id[probe_id].position


func _allocate_id() -> int:
	var result := next_id
	next_id += 1
	return result


func _restore_probe(raw: Dictionary) -> LevelAcousticProbeMarker:
	var marker = PROBE_MARKER_SCRIPT.new() as LevelAcousticProbeMarker
	if not marker.configure(raw):
		marker.free()
		return null
	marker_root.add_child(marker)
	probes_by_id[marker.probe_id] = marker
	return marker


func _restore_portal(raw: Dictionary) -> LevelAcousticPortalMarker:
	var safe := AUTHORING.sanitize_portal(raw)
	if safe.is_empty():
		return null
	var probe_a := probes_by_id.get(int(safe["probe_a_id"])) as LevelAcousticProbeMarker
	var probe_b := probes_by_id.get(int(safe["probe_b_id"])) as LevelAcousticProbeMarker
	if probe_a == null or probe_b == null:
		return null
	var marker = PORTAL_MARKER_SCRIPT.new() as LevelAcousticPortalMarker
	marker_root.add_child(marker)
	if not marker.configure(safe, probe_a, probe_b):
		marker_root.remove_child(marker)
		marker.free()
		return null
	portals_by_id[marker.portal_id] = marker
	return marker


func _remove_probe(probe_id: int) -> void:
	var connected_portals: Array[int] = []
	for portal_id: int in portals_by_id:
		var portal := portals_by_id[portal_id]
		if portal.probe_a_id == probe_id or portal.probe_b_id == probe_id:
			connected_portals.append(portal_id)
	for portal_id: int in connected_portals:
		_remove_portal(portal_id)
	var marker := probes_by_id.get(probe_id) as LevelAcousticProbeMarker
	probes_by_id.erase(probe_id)
	selected_probe_ids.erase(probe_id)
	if marker != null:
		marker_root.remove_child(marker)
		marker.free()


func _remove_portal(portal_id: int) -> void:
	var marker := portals_by_id.get(portal_id) as LevelAcousticPortalMarker
	portals_by_id.erase(portal_id)
	if marker != null:
		marker_root.remove_child(marker)
		marker.free()


func _clear_nodes_only() -> void:
	selected_probe_ids.clear()
	selected_portal_id = 0
	if marker_root != null:
		for child: Node in marker_root.get_children():
			marker_root.remove_child(child)
			child.free()
	probes_by_id.clear()
	portals_by_id.clear()


func _apply_visibility() -> void:
	if marker_root != null:
		marker_root.visible = visible_in_editor


func _refresh_selection_visuals() -> void:
	for probe_id: int in probes_by_id:
		probes_by_id[probe_id].set_selected(selected_probe_ids.has(probe_id))
	for portal_id: int in portals_by_id:
		portals_by_id[portal_id].set_selected(portal_id == selected_portal_id)


func _refresh_portals_for_probe(probe_id: int) -> void:
	for portal: LevelAcousticPortalMarker in portals_by_id.values():
		if portal.probe_a_id == probe_id or portal.probe_b_id == probe_id:
			portal.refresh()


func _portal_exists(probe_a_id: int, probe_b_id: int) -> bool:
	for portal: LevelAcousticPortalMarker in portals_by_id.values():
		if (
			(portal.probe_a_id == probe_a_id and portal.probe_b_id == probe_b_id)
			or (portal.probe_a_id == probe_b_id and portal.probe_b_id == probe_a_id)
		):
			return true
	return false


func _probe_has_portal(probe_id: int) -> bool:
	for portal: LevelAcousticPortalMarker in portals_by_id.values():
		if portal.probe_a_id == probe_id or portal.probe_b_id == probe_id:
			return true
	return false


func _nearest_probe_distance_squared(position: Vector3) -> float:
	var nearest := INF
	for probe: LevelAcousticProbeMarker in probes_by_id.values():
		nearest = minf(nearest, probe.position.distance_squared_to(position))
	return nearest


static func _typed_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				result.append(item as Dictionary)
	return result
