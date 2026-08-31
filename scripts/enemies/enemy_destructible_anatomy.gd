class_name EnemyDestructibleAnatomy
extends RefCounted

## A compact authoritative SDF anatomy for humanoid enemies. The animated skin remains a client
## presentation concern; bullets, blades, survival, and limb availability all consume these same
## finite material fields.

const FLESH_TEXTURE: DestructionTextureDefinition = preload(
	"res://resources/destruction/flesh.tres"
)
const VOXEL_SIZE := 0.045
const BRICK_CELLS := 12
const VISUAL_WOUND_LIMIT := 24
const LIMB_REMAINING_THRESHOLD := 0.38
const HEAD_REMAINING_THRESHOLD := 0.56
const TORSO_REMAINING_THRESHOLD := 0.34
const AGGREGATE_DESTRUCTION_THRESHOLD := 0.58
const CORE_AIR_MARGIN := 0.008

const PART_HEAD := &"head"
const PART_TORSO := &"torso"
const PART_LEFT_ARM := &"left_arm"
const PART_RIGHT_ARM := &"right_arm"
const PART_LEFT_LEG := &"left_leg"
const PART_RIGHT_LEG := &"right_leg"

const PART_ORDER: Array[StringName] = [
	PART_HEAD,
	PART_TORSO,
	PART_LEFT_ARM,
	PART_RIGHT_ARM,
	PART_LEFT_LEG,
	PART_RIGHT_LEG,
]

const PART_LAYOUT := {
	PART_HEAD: {
		"center": Vector3(0.0, 1.66, 0.0),
		"size": Vector3(0.40, 0.38, 0.38),
		"weight": 0.12,
		"vital": true,
	},
	PART_TORSO: {
		"center": Vector3(0.0, 1.18, 0.0),
		"size": Vector3(0.62, 0.76, 0.44),
		"weight": 0.36,
		"vital": true,
	},
	PART_LEFT_ARM: {
		"center": Vector3(-0.38, 1.22, 0.0),
		"size": Vector3(0.20, 0.70, 0.22),
		"weight": 0.09,
		"vital": false,
	},
	PART_RIGHT_ARM: {
		"center": Vector3(0.38, 1.22, 0.0),
		"size": Vector3(0.20, 0.70, 0.22),
		"weight": 0.09,
		"vital": false,
	},
	PART_LEFT_LEG: {
		"center": Vector3(-0.17, 0.48, 0.0),
		"size": Vector3(0.24, 0.90, 0.28),
		"weight": 0.17,
		"vital": false,
	},
	PART_RIGHT_LEG: {
		"center": Vector3(0.17, 0.48, 0.0),
		"size": Vector3(0.24, 0.90, 0.28),
		"weight": 0.17,
		"vital": false,
	},
}


class PartState:
	extends RefCounted

	var part_id: StringName
	var center := Vector3.ZERO
	var size := Vector3.ONE
	var weight := 0.0
	var vital := false
	var severable := false
	var remaining_threshold := 0.0
	var critical_points := PackedVector3Array()
	var definition: EnemyAnatomyPartDefinition
	var field: SparseSdfVolumeData
	var remaining_fraction := 1.0


var enemy_identity := -1
var revision := 0
var parts: Dictionary = {}
var anatomy_definition: EnemyDestructibleAnatomyDefinition
var damage_texture: DestructionTextureDefinition = FLESH_TEXTURE
var wounds: Array[Dictionary] = []
## Exact, material-space edits used to rebuild the client presentation with the same sparse SDF
## and dual-contouring backend as world destruction. `wounds` remains a compact aperture list for
## clipping the imported skinned surface; it is not a second geometry simulation.
var deformation_events: Array[Dictionary] = []
var aggregate_remaining_fraction := 1.0
var death_reason := &""
var _seen_event_ids: Dictionary[int, bool] = {}
var _seen_event_order: Array[int] = []


func configure(
	identity: int,
	profile: EnemyDestructibleAnatomyDefinition = null
) -> EnemyDestructibleAnatomy:
	enemy_identity = identity
	anatomy_definition = profile if profile != null and profile.has_usable_parts() else null
	damage_texture = (
		anatomy_definition.damage_texture
		if anatomy_definition != null
		else FLESH_TEXTURE
	)
	revision = 0
	parts.clear()
	wounds.clear()
	deformation_events.clear()
	aggregate_remaining_fraction = 1.0
	death_reason = &""
	_seen_event_ids.clear()
	_seen_event_order.clear()
	if anatomy_definition != null:
		for part_definition: EnemyAnatomyPartDefinition in anatomy_definition.parts:
			_configure_part(part_definition)
	else:
		for part_id: StringName in PART_ORDER:
			_configure_legacy_part(part_id, PART_LAYOUT[part_id])
	return self


func _configure_part(part_definition: EnemyAnatomyPartDefinition) -> void:
	if part_definition == null or part_definition.part_id.is_empty():
		return
	var part := PartState.new()
	part.part_id = part_definition.part_id
	part.center = part_definition.local_center
	part.size = part_definition.sanitized_size()
	part.weight = maxf(part_definition.contribution_weight, 0.0)
	part.vital = part_definition.vital
	part.severable = part_definition.severable
	part.remaining_threshold = clampf(part_definition.remaining_threshold, 0.0, 1.0)
	part.critical_points = part_definition.critical_points
	part.definition = part_definition
	part.field = SparseSdfVolumeData.new().configure(
		part.size,
		anatomy_definition.voxel_size,
		anatomy_definition.brick_cells,
		damage_texture.material_index,
		4.0
	)
	parts[part.part_id] = part


func _configure_legacy_part(part_id: StringName, descriptor: Dictionary) -> void:
	var part := PartState.new()
	part.part_id = part_id
	part.center = descriptor["center"]
	part.size = descriptor["size"]
	part.weight = float(descriptor["weight"])
	part.vital = bool(descriptor["vital"])
	part.severable = part_id != PART_TORSO
	part.remaining_threshold = (
		HEAD_REMAINING_THRESHOLD
		if part_id == PART_HEAD
		else TORSO_REMAINING_THRESHOLD if part_id == PART_TORSO
		else LIMB_REMAINING_THRESHOLD
	)
	if part_id == PART_HEAD:
		part.critical_points = PackedVector3Array([part.center])
	elif part_id == PART_TORSO:
		part.critical_points = PackedVector3Array([
			part.center + Vector3(-0.11, 0.10, -0.035),
		])
	part.field = SparseSdfVolumeData.new().configure(
		part.size,
		VOXEL_SIZE,
		BRICK_CELLS,
		FLESH_TEXTURE.material_index,
		4.0
	)
	parts[part_id] = part


func apply_damage_event(event: DamageEvent, body_transform: Transform3D) -> Dictionary:
	if event == null or not event.is_valid() or is_dead():
		return {"changed": false, "reason": &"invalid_or_dead"}
	if event.event_id > 0 and _seen_event_ids.has(event.event_id):
		return {"changed": false, "reason": &"duplicate_event"}
	_remember_event(event.event_id)
	var inverse := body_transform.affine_inverse()
	var local_hit := inverse * event.world_position
	var local_direction := body_transform.basis.inverse() * event.direction
	var local_normal := body_transform.basis.inverse() * event.normal
	var part_id := classify_part(local_hit, local_direction)
	var part := parts.get(part_id) as PartState
	if part == null:
		return {"changed": false, "reason": &"missing_part"}
	var projected_hit := _project_hit_to_part_surface(local_hit, part)
	var part_hit := projected_hit - part.center
	var part_event := _canonical_part_event(
		event,
		part_hit,
		local_direction,
		local_normal
	)
	var result := part.field.apply_damage_event(
		part_event.world_position,
		part_event.direction,
		part_event.normal,
		part_event,
		damage_texture
	)
	if not bool(result.get("changed", false)):
		return result
	part.remaining_fraction = _measure_remaining_fraction(part)
	_recalculate_aggregate_state()
	if bool(result.get("geometry_changed", true)):
		# The enemy's broad movement collider is deliberately larger than its skin. Replicate the exact
		# projected material-space point used by the SDF, never the broadphase contact floating outside it.
		_record_wound(
			part_event,
			part,
			part.center + part_event.world_position,
			part_event.direction
		)
		_record_deformation_event(part_event, part)
	revision += 1
	_evaluate_death()
	result["part_id"] = part_id
	result["part_remaining_fraction"] = part.remaining_fraction
	result["aggregate_remaining_fraction"] = aggregate_remaining_fraction
	result["anatomy_revision"] = revision
	result["fatal"] = is_dead()
	result["death_reason"] = death_reason
	return result


func classify_part(
	local_hit: Vector3,
	local_direction: Vector3 = Vector3.ZERO
) -> StringName:
	# ServerEnemy intentionally owns one stable movement collider. Select anatomy by the actual
	# damage ray entering the authored part volumes; comparing the broad collider contact directly
	# biases every hit toward the thick torso whenever the skin sits inside that collider.
	if local_direction.length_squared() > 0.000001:
		var nearest_ray_part := &""
		var nearest_ray_distance := INF
		for part_value: Variant in parts.values():
			var ray_part := part_value as PartState
			if ray_part == null:
				continue
			var entry_distance := _ray_entry_distance_to_part(
				local_hit,
				local_direction,
				ray_part
			)
			if entry_distance < nearest_ray_distance:
				nearest_ray_distance = entry_distance
				nearest_ray_part = ray_part.part_id
		if not nearest_ray_part.is_empty():
			return nearest_ray_part
	var best_part := &""
	var best_volume_distance := INF
	var best_center_distance := INF
	for part_value: Variant in parts.values():
		var part := part_value as PartState
		if part == null:
			continue
		var volume_distance := _distance_to_part_volume(local_hit, part)
		var center_distance := _normalized_part_center_distance(local_hit, part)
		if (
			volume_distance < best_volume_distance - 0.000001
			or (
				is_equal_approx(volume_distance, best_volume_distance)
				and center_distance < best_center_distance
			)
		):
			best_part = part.part_id
			best_volume_distance = volume_distance
			best_center_distance = center_distance
	return best_part


func _ray_entry_distance_to_part(
	origin: Vector3,
	direction: Vector3,
	part: PartState
) -> float:
	var ray := direction.normalized()
	var half := part.size * 0.5
	var minimum := part.center - half
	var maximum := part.center + half
	var entry := 0.0
	var exit := part.size.length() * 8.0 + origin.distance_to(part.center)
	for axis: int in range(3):
		var component := ray[axis]
		if absf(component) <= 0.000001:
			if origin[axis] < minimum[axis] or origin[axis] > maximum[axis]:
				return INF
			continue
		var first := (minimum[axis] - origin[axis]) / component
		var second := (maximum[axis] - origin[axis]) / component
		if first > second:
			var swap := first
			first = second
			second = swap
		entry = maxf(entry, first)
		exit = minf(exit, second)
		if exit < entry:
			return INF
	return entry if exit >= 0.0 else INF


func has_limb(part_id: StringName) -> bool:
	var part := parts.get(part_id) as PartState
	return part != null and part.remaining_fraction > part.remaining_threshold


func mobility_scale() -> float:
	var left := has_limb(PART_LEFT_LEG)
	var right := has_limb(PART_RIGHT_LEG)
	if left and right:
		return 1.0
	if left or right:
		return 0.36
	return 0.0


func is_dead() -> bool:
	return not death_reason.is_empty()


func state_dict() -> Dictionary:
	var fractions := {}
	var presence := {}
	for part_value: Variant in parts.values():
		var part := part_value as PartState
		if part == null:
			continue
		fractions[part.part_id] = part.remaining_fraction
		presence[part.part_id] = not part.severable or has_limb(part.part_id)
	return {
		"revision": revision,
		"remaining_fraction": aggregate_remaining_fraction,
		"part_fractions": fractions,
		"part_presence": presence,
		"profile_path": anatomy_definition.resource_path if anatomy_definition != null else "",
		"left_arm": has_limb(PART_LEFT_ARM),
		"right_arm": has_limb(PART_RIGHT_ARM),
		"left_leg": has_limb(PART_LEFT_LEG),
		"right_leg": has_limb(PART_RIGHT_LEG),
		"wounds": wounds.duplicate(true),
		"deformation_events": deformation_events.duplicate(true),
		"dead": is_dead(),
		"death_reason": death_reason,
	}


func _project_hit_to_part_surface(local_hit: Vector3, part: PartState) -> Vector3:
	if part.definition != null:
		return part.definition.project_to_volume(local_hit)
	var half := part.size * 0.5
	var offset := local_hit - part.center
	return part.center + Vector3(
		clampf(offset.x, -half.x, half.x),
		clampf(offset.y, -half.y, half.y),
		clampf(offset.z, -half.z, half.z)
	)


func _distance_to_part_volume(local_hit: Vector3, part: PartState) -> float:
	if part.definition != null:
		return part.definition.distance_to_volume(local_hit)
	var half := part.size * 0.5
	var outside := (local_hit - part.center).abs() - half
	return Vector3(
		maxf(outside.x, 0.0),
		maxf(outside.y, 0.0),
		maxf(outside.z, 0.0)
	).length()


func _normalized_part_center_distance(local_hit: Vector3, part: PartState) -> float:
	if part.definition != null:
		return part.definition.normalized_center_distance_squared(local_hit)
	var half := part.size * 0.5
	var offset := local_hit - part.center
	return (
		offset.x * offset.x / maxf(half.x * half.x, 0.000001)
		+ offset.y * offset.y / maxf(half.y * half.y, 0.000001)
		+ offset.z * offset.z / maxf(half.z * half.z, 0.000001)
	)


func _measure_remaining_fraction(part: PartState) -> float:
	var counts := Vector3i(
		clampi(ceili(part.size.x / 0.075), 4, 12),
		clampi(ceili(part.size.y / 0.075), 4, 14),
		clampi(ceili(part.size.z / 0.075), 4, 12)
	)
	var solid := 0
	var total := counts.x * counts.y * counts.z
	for z: int in range(counts.z):
		for y: int in range(counts.y):
			for x: int in range(counts.x):
				var unit := Vector3(
					(float(x) + 0.5) / float(counts.x),
					(float(y) + 0.5) / float(counts.y),
					(float(z) + 0.5) / float(counts.z)
				)
				var position := (unit - Vector3.ONE * 0.5) * part.size
				if part.field.sample_distance(position) <= 0.0:
					solid += 1
	return float(solid) / float(maxi(total, 1))


func _recalculate_aggregate_state() -> void:
	aggregate_remaining_fraction = 0.0
	for part_value: Variant in parts.values():
		var part := part_value as PartState
		if part != null:
			aggregate_remaining_fraction += part.weight * part.remaining_fraction
	aggregate_remaining_fraction = clampf(aggregate_remaining_fraction, 0.0, 1.0)


func _evaluate_death() -> void:
	var air_margin := (
		anatomy_definition.critical_air_margin
		if anatomy_definition != null
		else CORE_AIR_MARGIN
	)
	for part_value: Variant in parts.values():
		var part := part_value as PartState
		if part == null or not part.vital:
			continue
		var core_removed := false
		for critical_point: Vector3 in part.critical_points:
			if part.field.sample_distance(critical_point - part.center) > air_margin:
				core_removed = true
				break
		if part.remaining_fraction <= part.remaining_threshold or core_removed:
			death_reason = (
				&"brain_destroyed" if part.part_id == PART_HEAD
				else &"core_destroyed" if part.part_id == PART_TORSO
				else StringName("%s_destroyed" % part.part_id)
			)
			return
	var aggregate_threshold := (
		anatomy_definition.aggregate_destruction_threshold
		if anatomy_definition != null
		else AGGREGATE_DESTRUCTION_THRESHOLD
	)
	if 1.0 - aggregate_remaining_fraction >= aggregate_threshold:
		death_reason = &"tissue_loss"


func _record_wound(
	event: DamageEvent,
	part: PartState,
	local_hit: Vector3,
	local_direction: Vector3
) -> void:
	var direction := (
		local_direction.normalized()
		if local_direction.length_squared() > 0.000001
		else Vector3.FORWARD
	)
	var radius := clampf(
		damage_texture.response_radius(event.radius, event.energy),
		0.018,
		minf(part.size.x, part.size.z) * 0.48
	)
	var depth := clampf(
		maxf(maxf(event.penetration, event.length), radius * 1.4),
		radius,
		part.size.length()
	)
	var nearest_index := -1
	var nearest_distance := INF
	for wound_index: int in range(wounds.size()):
		var existing: Dictionary = wounds[wound_index]
		if StringName(str(existing.get("part", &""))) != part.part_id:
			continue
		var distance := local_hit.distance_to(existing.get("local_position", local_hit))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = wound_index
	var must_merge := (
		nearest_index >= 0
		and (
			nearest_distance <= radius + float(wounds[nearest_index].get("radius", radius)) * 0.72
				or wounds.size() >= _wound_limit()
		)
	)
	if must_merge:
		var merged := wounds[nearest_index].duplicate(false)
		var old_radius := float(merged.get("radius", radius))
		var old_position: Vector3 = merged.get("local_position", local_hit)
		var area_sum := old_radius * old_radius + radius * radius
		merged["radius"] = minf(sqrt(area_sum), minf(part.size.x, part.size.z) * 0.49)
		merged["depth"] = maxf(float(merged.get("depth", depth)), depth)
		merged["local_position"] = old_position.lerp(local_hit, radius * radius / maxf(area_sum, 0.000001))
		merged["local_direction"] = (
			(merged.get("local_direction", direction) as Vector3).lerp(direction, 0.35).normalized()
		)
		merged["event_id"] = event.event_id
		wounds[nearest_index] = merged
		return
	wounds.append({
		"event_id": event.event_id,
		"part": part.part_id,
		"local_position": local_hit,
		"local_direction": direction,
		"radius": radius,
		"depth": depth,
	})
	if wounds.size() > _wound_limit():
		wounds.pop_front()


func _record_deformation_event(
	event: DamageEvent,
	part: PartState
) -> void:
	# Keep the canonical DamageEvent rather than reverse-engineering a new brush from the visual wound
	# radius. This makes hosts, clients, and tests sample exactly the same material response, including
	# penetration, deterministic spatial warp, and weapon-specific tags.
	deformation_events.append({
		"part": part.part_id,
		"event": event.to_dict(false),
	})


func _canonical_part_event(
	source: DamageEvent,
	part_local_hit: Vector3,
	part_local_direction: Vector3,
	part_local_normal: Vector3
) -> DamageEvent:
	var state := source.to_dict(true)
	state["world_position"] = _snapped_vector3(
		part_local_hit,
		DamageEvent.NETWORK_POSITION_STEP
	)
	state["direction"] = _snapped_direction(
		part_local_direction,
		Vector3.FORWARD
	)
	state["normal"] = _snapped_direction(
		part_local_normal,
		-(state["direction"] as Vector3)
	)
	return DamageEvent.from_dict(state)


static func _snapped_direction(value: Vector3, fallback: Vector3) -> Vector3:
	var snapped := _snapped_vector3(value, DamageEvent.NETWORK_SCALAR_STEP)
	if snapped.length_squared() <= 0.000001:
		snapped = fallback
	return snapped.normalized()


static func _snapped_vector3(value: Vector3, step: float) -> Vector3:
	return Vector3(
		snappedf(value.x, step),
		snappedf(value.y, step),
		snappedf(value.z, step)
	)


func _wound_limit() -> int:
	return (
		anatomy_definition.replicated_wound_limit
		if anatomy_definition != null
		else VISUAL_WOUND_LIMIT
	)


func _remember_event(event_id: int) -> void:
	if event_id <= 0:
		return
	_seen_event_ids[event_id] = true
	_seen_event_order.append(event_id)
	if _seen_event_order.size() <= 128:
		return
	_seen_event_ids.erase(_seen_event_order.pop_front())
