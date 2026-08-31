class_name PlasmaCutterBeam3D
extends Node3D

## Allocation-stable presentation for the replicated cutter. The server decides whether the arc is
## live and where it terminates; this node only keeps the beam attached to the selected cutter.

const ENDPOINT_RESPONSE_HZ := 34.0
const CORE_RADIUS := 0.010
const GLOW_RADIUS := 0.026
const MIN_VISIBLE_LENGTH := 0.015

var emitter: Node3D
var endpoint := Vector3.ZERO
var endpoint_initialized := false
var core: MeshInstance3D
var glow: MeshInstance3D
var impact: MeshInstance3D
var core_material: StandardMaterial3D
var glow_material: StandardMaterial3D
var impact_material: StandardMaterial3D


func _ready() -> void:
	_build_visuals()
	visible = false


func bind_emitter(next_emitter: Node3D) -> void:
	emitter = next_emitter
	endpoint_initialized = false
	if not is_instance_valid(emitter):
		visible = false


func update_beam(
	next_endpoint: Vector3,
	active: bool,
	has_hit: bool,
	heat_ratio: float,
	delta: float,
	snap_endpoint := false
) -> void:
	if not active or not is_instance_valid(emitter) or not next_endpoint.is_finite():
		visible = false
		endpoint_initialized = false
		return
	var start := emitter.global_position
	if snap_endpoint or not endpoint_initialized:
		endpoint = next_endpoint
		endpoint_initialized = true
	else:
		var response := 1.0 - exp(-ENDPOINT_RESPONSE_HZ * clampf(delta, 0.0, 0.1))
		endpoint = endpoint.lerp(next_endpoint, response)
	var beam_vector := endpoint - start
	var beam_length := beam_vector.length()
	if beam_length <= MIN_VISIBLE_LENGTH:
		visible = false
		return
	visible = true
	var axis := beam_vector / beam_length
	var basis_x := axis.cross(Vector3.UP)
	if basis_x.length_squared() < 0.000001:
		basis_x = axis.cross(Vector3.RIGHT)
	basis_x = basis_x.normalized()
	var basis_z := basis_x.cross(axis).normalized()
	var beam_basis := Basis(basis_x, axis, basis_z)
	var midpoint := start + beam_vector * 0.5
	core.global_transform = Transform3D(beam_basis, midpoint)
	glow.global_transform = Transform3D(beam_basis, midpoint)
	core.scale = Vector3(CORE_RADIUS, beam_length, CORE_RADIUS)
	glow.scale = Vector3(GLOW_RADIUS, beam_length, GLOW_RADIUS)
	impact.global_position = endpoint
	impact.visible = has_hit
	var safe_heat := clampf(heat_ratio if is_finite(heat_ratio) else 0.0, 0.0, 1.0)
	var pulse := 0.88 + sin(float(Time.get_ticks_msec()) * 0.038) * 0.12
	core_material.emission_energy_multiplier = 4.0 + safe_heat * 2.5
	glow_material.emission_energy_multiplier = (1.1 + safe_heat * 1.4) * pulse
	impact.scale = Vector3.ONE * (0.026 + pulse * 0.012)


func _build_visuals() -> void:
	if core != null:
		return
	core_material = _make_material(Color(0.76, 1.0, 0.96, 1.0), 4.0, false)
	glow_material = _make_material(Color(0.03, 0.95, 0.75, 0.20), 1.1, true)
	impact_material = _make_material(Color(1.0, 0.72, 0.24, 0.88), 5.0, true)
	core = _make_beam_mesh("Core", core_material)
	glow = _make_beam_mesh("Glow", glow_material)
	impact = MeshInstance3D.new()
	impact.name = "Impact"
	var impact_mesh := SphereMesh.new()
	impact_mesh.radius = 1.0
	impact_mesh.height = 2.0
	impact_mesh.radial_segments = 8
	impact_mesh.rings = 4
	impact_mesh.material = impact_material
	impact.mesh = impact_mesh
	impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact.visible = false
	add_child(impact)


func _make_beam_mesh(node_name: String, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	cylinder.rings = 1
	cylinder.material = material
	instance.mesh = cylinder
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


static func _make_material(
	color: Color,
	emission_energy: float,
	transparent: bool
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = emission_energy
	material.no_depth_test = false
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
