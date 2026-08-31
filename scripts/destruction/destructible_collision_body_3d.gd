class_name DestructibleCollisionBody3D
extends StaticBody3D

## Thin collision adapter that lets the projectile system reach its owning volume without scene-path
## assumptions. Generated and untouched macro-chunk bodies use the same adapter.

var destruction_volume: DestructibleVolume3D
var chunk_coordinate := Vector3i.ZERO
var _damage_call_active := false


func configure(
	owner_volume: DestructibleVolume3D,
	coordinate: Vector3i,
	surface: StringName
) -> DestructibleCollisionBody3D:
	destruction_volume = owner_volume
	chunk_coordinate = coordinate
	PhysicalSurface.apply_to(self, surface)
	set_meta(&"destructible_volume_id", owner_volume.volume_id if owner_volume != null else &"")
	set_meta(&"destruction_chunk", coordinate)
	return self


func get_destruction_volume() -> DestructibleVolume3D:
	return destruction_volume if is_instance_valid(destruction_volume) else null


func accepts_current_sdf_hit(world_position: Vector3, world_direction: Vector3) -> bool:
	return (
		destruction_volume == null
		or destruction_volume.accepts_current_sdf_hit(world_position, world_direction)
	)


func apply_damage_event(event: DamageEvent) -> Dictionary:
	if destruction_volume == null:
		return {"changed": false, "reason": &"missing_volume"}
	_damage_call_active = true
	var result := destruction_volume.apply_authoritative_damage_event(event)
	_damage_call_active = false
	return result


func damage_call_is_active() -> bool:
	return _damage_call_active
