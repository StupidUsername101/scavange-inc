class_name ProjectileProxy
extends Node3D

const CORRECTION_SPEED := 18.0
const MAX_EXTRAPOLATION_TIME := 0.12
const TRACER_EMISSION_ENERGY := 4.0
const TRACER_RADIAL_SEGMENTS := 8
const TIP_RADIUS_SCALE := 1.65
const TIP_HEIGHT_SCALE := 3.3
const TIP_RINGS := 4
const MIN_ORIENTATION_SPEED_SQUARED := 0.0001
const VERTICAL_DIRECTION_DOT_THRESHOLD := 0.98

#######################################################
# Mirrors authoritative projectile state on clients and updates its local visual presentation.
#######################################################

var projectile_id := -1
var target_position := Vector3.ZERO
var velocity := Vector3.ZERO
var time_since_last_state := 0.0
var initialized := false
var visual_signature := ""


func apply_server_state(state: Dictionary) -> void:
	projectile_id = int(state.get("projectile_id", -1))
	target_position = state.get("pos", global_position)
	velocity = state.get("velocity", Vector3.ZERO)
	time_since_last_state = 0.0
	if not initialized:
		global_position = target_position
		initialized = true
	_apply_visual(state)
	_orient_to_velocity()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		var projectile := Server.get_server_projectile(projectile_id)
		if is_instance_valid(projectile):
			global_position = projectile.global_position
			velocity = projectile.velocity
			_orient_to_velocity()
			return

	time_since_last_state += delta
	var predicted := (
		target_position
		+ velocity * minf(
			time_since_last_state,
			MAX_EXTRAPOLATION_TIME
		)
	)
	global_position += velocity * delta
	global_position = global_position.lerp(
		predicted,
		clampf(CORRECTION_SPEED * delta, 0.0, 1.0)
	)
	_orient_to_velocity()


func _apply_visual(state: Dictionary) -> void:
	var color: Color = state.get(
		"tracer_color",
		BallisticProjectileDefinition.DEFAULT_TRACER_COLOR
	)
	var length := maxf(
		float(state.get(
			"tracer_length",
			BallisticProjectileDefinition.DEFAULT_TRACER_LENGTH
		)),
		BallisticProjectileDefinition.MIN_TRACER_LENGTH
	)
	var radius := maxf(
		float(state.get(
			"tracer_radius",
			BallisticProjectileDefinition.DEFAULT_TRACER_RADIUS
		)),
		BallisticProjectileDefinition.MIN_TRACER_RADIUS
	)
	var signature := "%s|%.4f|%.4f" % [color.to_html(), length, radius]
	if signature == visual_signature:
		return
	visual_signature = signature
	for child: Node in get_children():
		child.queue_free()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = TRACER_EMISSION_ENERGY

	var tracer_mesh := CylinderMesh.new()
	tracer_mesh.top_radius = radius
	tracer_mesh.bottom_radius = radius
	tracer_mesh.height = length
	tracer_mesh.radial_segments = TRACER_RADIAL_SEGMENTS
	tracer_mesh.material = material
	var tracer := MeshInstance3D.new()
	tracer.name = "Tracer"
	tracer.mesh = tracer_mesh
	tracer.position.z = length * 0.5
	tracer.rotation.x = deg_to_rad(90.0)
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)

	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = radius * TIP_RADIUS_SCALE
	tip_mesh.height = radius * TIP_HEIGHT_SCALE
	tip_mesh.radial_segments = TRACER_RADIAL_SEGMENTS
	tip_mesh.rings = TIP_RINGS
	tip_mesh.material = material
	var tip := MeshInstance3D.new()
	tip.name = "ProjectileTip"
	tip.mesh = tip_mesh
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tip)


func _orient_to_velocity() -> void:
	if velocity.length_squared() <= MIN_ORIENTATION_SPEED_SQUARED:
		return
	var direction := velocity.normalized()
	var up := (
		Vector3.FORWARD
		if absf(direction.dot(Vector3.UP))
		> VERTICAL_DIRECTION_DOT_THRESHOLD
		else Vector3.UP
	)
	global_basis = Basis.looking_at(direction, up)
