class_name TerminalAimIndicator
extends RefCounted

#######################################################
# Shared first-person projection for world-space terminal screens. The terminal Control only needs
# to expose set_aim_indicator(Vector2, bool); layout/screen geometry remains caller-owned.
#######################################################


static func update(
	terminal_owner: Node3D,
	terminal_view: Object,
	screen_plane_z: float,
	screen_center: Vector2,
	screen_world_size: Vector2,
	maximum_aim_distance: float,
	screen_pixel_size: Vector2
) -> void:
	if not is_instance_valid(terminal_owner) or terminal_view == null:
		return
	var local_player: Variant = Client.get_local_player_proxy()
	if (
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or local_player == null
		or not is_instance_valid(local_player.camera)
	):
		terminal_view.call("set_aim_indicator", Vector2.ZERO, false)
		return
	var ray_origin: Vector3 = local_player.camera.global_position
	var ray_direction: Vector3 = -local_player.camera.global_basis.z.normalized()
	var local_origin: Vector3 = terminal_owner.to_local(ray_origin)
	var local_direction: Vector3 = terminal_owner.global_basis.inverse() * ray_direction
	if absf(local_direction.z) <= 0.0001:
		terminal_view.call("set_aim_indicator", Vector2.ZERO, false)
		return
	var distance: float = (screen_plane_z - local_origin.z) / local_direction.z
	if distance < 0.0 or distance > maximum_aim_distance:
		terminal_view.call("set_aim_indicator", Vector2.ZERO, false)
		return
	var hit: Vector3 = local_origin + local_direction * distance
	var left: float = screen_center.x - screen_world_size.x * 0.5
	var top: float = screen_center.y + screen_world_size.y * 0.5
	var normalized: Vector2 = Vector2(
		(hit.x - left) / screen_world_size.x,
		(top - hit.y) / screen_world_size.y
	)
	var visible: bool = (
		normalized.x >= 0.0
		and normalized.x <= 1.0
		and normalized.y >= 0.0
		and normalized.y <= 1.0
	)
	terminal_view.call(
		"set_aim_indicator",
		Vector2(
			normalized.x * screen_pixel_size.x,
			normalized.y * screen_pixel_size.y
		),
		visible
	)
