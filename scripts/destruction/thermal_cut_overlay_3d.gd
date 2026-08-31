class_name ThermalCutOverlay3D
extends Node

## Fixed-capacity, event-driven molten-cut presentation shared by destructible volumes and detached
## fragments. It adds a material pass only while heat exists, so ordinary ballistic destruction has
## no shader, per-frame update, or extra draw pass.

const SHADER: Shader = preload("res://shaders/thermal_cut_overlay.gdshader")
const MAX_THERMAL_CUTS := 24
const MIN_COOL_SECONDS := 2.8
const MAX_COOL_SECONDS := 7.5
const MERGE_DISTANCE_SCALE := 0.62
const EPSILON := 0.000001

var _target_material: Material
var _previous_next_pass: Material
var _overlay_material: ShaderMaterial
var _entries := PackedVector4Array()
var _axes := PackedVector4Array()
var _lifetimes := PackedVector4Array()
var _clock_seconds := 0.0
var _latest_expiry_seconds := 0.0
var _write_index := 0
var _imprint_count := 0


func _ready() -> void:
	set_process(false)


func configure(target_material: Material) -> ThermalCutOverlay3D:
	if target_material == _target_material:
		return self
	_detach_pass()
	_target_material = target_material
	return self


func add_cut(
	local_position: Vector3,
	local_direction: Vector3,
	channel_radius: float,
	channel_depth: float,
	heat_energy: float
) -> bool:
	if (
		_target_material == null
		or not local_position.is_finite()
		or not local_direction.is_finite()
		or heat_energy <= 0.0
	):
		return false
	var direction := local_direction.normalized()
	if direction.length_squared() <= EPSILON:
		return false
	_ensure_storage()
	var radius := clampf(absf(channel_radius), 0.003, 2.0)
	var depth := clampf(absf(channel_depth), radius, 16.0)
	var intensity := clampf(1.0 - exp(-heat_energy / 11.0), 0.08, 1.0)
	var duration := clampf(
		MIN_COOL_SECONDS + sqrt(maxf(heat_energy, 0.0)) * 0.62,
		MIN_COOL_SECONDS,
		MAX_COOL_SECONDS
	)
	var slot := _find_merge_slot(local_position, direction, radius)
	if slot < 0:
		slot = _write_index
		_write_index = (_write_index + 1) % MAX_THERMAL_CUTS
		_imprint_count = mini(_imprint_count + 1, MAX_THERMAL_CUTS)
	_entries[slot] = Vector4(local_position.x, local_position.y, local_position.z, radius)
	_axes[slot] = Vector4(direction.x, direction.y, direction.z, depth)
	_lifetimes[slot] = Vector4(_clock_seconds, duration, intensity, 0.0)
	_latest_expiry_seconds = maxf(_latest_expiry_seconds, _clock_seconds + duration)
	_attach_pass()
	_upload_imprints()
	set_process(true)
	return true


func add_damage_event(
	event: DamageEvent,
	local_position: Vector3,
	local_direction: Vector3,
	channel_radius: float,
	channel_depth: float
) -> bool:
	if not is_thermal_cut_event(event):
		return false
	return add_cut(
		local_position,
		local_direction,
		channel_radius,
		channel_depth,
		event.heat
	)


func checkpoint_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(_imprint_count):
		var lifetime := _lifetimes[index]
		var elapsed := maxf(_clock_seconds - lifetime.x, 0.0)
		var remaining := lifetime.y - elapsed
		if remaining <= 0.0 or lifetime.z <= 0.0:
			continue
		result.append({
			"entry": _entries[index],
			"axis": _axes[index],
			"duration": lifetime.y,
			"elapsed": elapsed,
			"intensity": lifetime.z,
		})
	return result


func apply_checkpoint_state(value: Variant) -> void:
	_clear_imprints()
	if not value is Array:
		return
	_ensure_storage()
	for raw_value: Variant in value:
		if not raw_value is Dictionary or _imprint_count >= MAX_THERMAL_CUTS:
			continue
		var descriptor := raw_value as Dictionary
		var entry_value: Variant = descriptor.get("entry", null)
		var axis_value: Variant = descriptor.get("axis", null)
		if not entry_value is Vector4 or not axis_value is Vector4:
			continue
		var entry := entry_value as Vector4
		var axis := axis_value as Vector4
		if not entry.is_finite() or not axis.is_finite():
			continue
		var duration := clampf(
			float(descriptor.get("duration", MIN_COOL_SECONDS)),
			0.05,
			MAX_COOL_SECONDS
		)
		var elapsed := clampf(float(descriptor.get("elapsed", 0.0)), 0.0, duration)
		var intensity := clampf(float(descriptor.get("intensity", 0.0)), 0.0, 1.0)
		if elapsed >= duration or intensity <= 0.0:
			continue
		var slot := _imprint_count
		_entries[slot] = entry
		_axes[slot] = axis
		_lifetimes[slot] = Vector4(_clock_seconds - elapsed, duration, intensity, 0.0)
		_latest_expiry_seconds = maxf(
			_latest_expiry_seconds,
			_clock_seconds - elapsed + duration
		)
		_imprint_count += 1
	_write_index = _imprint_count % MAX_THERMAL_CUTS
	if _imprint_count > 0:
		_attach_pass()
		_upload_imprints()
		set_process(true)


func debug_state() -> Dictionary:
	return {
		"active": _imprint_count > 0 and _target_material != null and (
			_target_material.next_pass == _overlay_material
		),
		"imprint_count": _imprint_count,
		"clock_seconds": _clock_seconds,
		"latest_expiry_seconds": _latest_expiry_seconds,
		"material": _overlay_material,
	}


func _process(delta: float) -> void:
	if _imprint_count <= 0:
		set_process(false)
		return
	_clock_seconds += maxf(delta, 0.0)
	if _overlay_material != null:
		_overlay_material.set_shader_parameter(&"thermal_clock_seconds", _clock_seconds)
	if _clock_seconds < _latest_expiry_seconds:
		return
	_clear_imprints()


func _ensure_storage() -> void:
	if _entries.size() == MAX_THERMAL_CUTS:
		return
	_entries.resize(MAX_THERMAL_CUTS)
	_axes.resize(MAX_THERMAL_CUTS)
	_lifetimes.resize(MAX_THERMAL_CUTS)


func _ensure_material() -> void:
	if _overlay_material != null:
		return
	_overlay_material = create_shader_material()


func _attach_pass() -> void:
	if _target_material == null:
		return
	_ensure_material()
	if _target_material.next_pass == _overlay_material:
		return
	_previous_next_pass = _target_material.next_pass
	_overlay_material.next_pass = _previous_next_pass
	_target_material.next_pass = _overlay_material


func _detach_pass() -> void:
	if _target_material != null and _target_material.next_pass == _overlay_material:
		_target_material.next_pass = _previous_next_pass
	if _overlay_material != null:
		_overlay_material.next_pass = null
	_previous_next_pass = null


func _upload_imprints() -> void:
	_ensure_material()
	_overlay_material.set_shader_parameter(&"cut_entries", _entries)
	_overlay_material.set_shader_parameter(&"cut_axes", _axes)
	_overlay_material.set_shader_parameter(&"cut_lifetimes", _lifetimes)
	_overlay_material.set_shader_parameter(&"cut_count", _imprint_count)
	_overlay_material.set_shader_parameter(&"thermal_clock_seconds", _clock_seconds)


func _clear_imprints() -> void:
	_imprint_count = 0
	_write_index = 0
	_latest_expiry_seconds = _clock_seconds
	if _overlay_material != null:
		_overlay_material.set_shader_parameter(&"cut_count", 0)
	_detach_pass()
	set_process(false)


func _find_merge_slot(
	local_position: Vector3,
	direction: Vector3,
	radius: float
) -> int:
	for index: int in range(_imprint_count):
		var lifetime := _lifetimes[index]
		if _clock_seconds >= lifetime.x + lifetime.y:
			continue
		var entry := _entries[index]
		var axis := _axes[index]
		var previous_position := Vector3(entry.x, entry.y, entry.z)
		var previous_direction := Vector3(axis.x, axis.y, axis.z)
		if (
			previous_position.distance_squared_to(local_position)
			<= pow(maxf(radius, entry.w) * MERGE_DISTANCE_SCALE, 2.0)
			and previous_direction.dot(direction) >= 0.82
		):
			return index
	return -1


static func is_thermal_cut_event(event: DamageEvent) -> bool:
	return (
		event != null
		and event.heat > 0.0
		and event.has_tag(DamageEvent.TAG_BLADE)
		and event.has_tag(DamageEvent.TAG_HEAT)
		and not event.has_tag(DamageEvent.TAG_BALLISTIC)
	)


static func create_shader_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"cut_count", 0)
	return material
