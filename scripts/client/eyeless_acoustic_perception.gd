class_name EyelessAcousticPerception
extends Control

## A non-digital sensory layer for characters without equipped eyes. It visualizes the same
## apparent positions and received levels that reach the client audio renderers. A voluntary
## mouth click also takes one bounded first-hit echo sample of nearby presentation collision;
## no ray continues through its first surface, so the sense cannot become wall vision.

const INPUT_ACTION := &"echolocation_click"
const DEFAULT_INPUT_KEY := KEY_Q
const MOUTH_CLICK_SOUND_ID := &"mouth_click"
const MAX_PULSES := 48
const MAX_SURFACE_ECHOES := 128
const MAX_CONTINUOUS_SOURCES := 12
const ECHO_RAY_COUNT := 88
const ECHO_RANGE_METERS := 18.0
const ITEM_ECHO_RANGE_METERS := 11.0
const SPEED_OF_SOUND_METERS_PER_SECOND := 343.0
const GUIDANCE_SECONDS := 5.0
const CONTINUOUS_STALE_SECONDS := 0.36
const MIN_VISIBLE_RECEIVED_DB := -54.0
const CORE_COLOR := Color(0.64, 0.82, 0.79)
const LOW_COLOR := Color(0.78, 0.75, 0.64)
const HIGH_COLOR := Color(0.61, 0.76, 0.86)
const GOLDEN_ANGLE := 2.399963229728653
const ARC_POINT_COUNT := 38


class PerceptionPulse:
	extends RefCounted

	var active := false
	var world_position := Vector3.ZERO
	var age := 0.0
	var delay := 0.0
	var lifetime := 1.0
	var strength := 0.0
	var band_gain := Vector3.ONE
	var seed := 0.0
	var pressure_layer := false


class SurfaceEcho:
	extends RefCounted

	var active := false
	var world_position := Vector3.ZERO
	var world_normal := Vector3.UP
	var age := 0.0
	var delay := 0.0
	var lifetime := 1.0
	var strength := 0.0
	var item_echo := false


class ContinuousSource:
	extends RefCounted

	var active := false
	var source_id := -1
	var world_position := Vector3.ZERO
	var strength := 0.0
	var target_strength := 0.0
	var band_gain := Vector3.ONE
	var enclosure := 0.0
	var stale_seconds := 0.0
	var phase := 0.0


var listener_camera: Camera3D
var perception_active := false
var guidance_remaining := 0.0
var _pulses: Array[PerceptionPulse] = []
var _surface_echoes: Array[SurfaceEcho] = []
var _continuous_sources: Array[ContinuousSource] = []
var _next_pulse_index := 0
var _next_surface_index := 0
var _arc_points := PackedVector2Array()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	_arc_points.resize(ARC_POINT_COUNT)
	for _index: int in range(MAX_PULSES):
		_pulses.append(PerceptionPulse.new())
	for _index: int in range(MAX_SURFACE_ECHOES):
		_surface_echoes.append(SurfaceEcho.new())
	for _index: int in range(MAX_CONTINUOUS_SOURCES):
		_continuous_sources.append(ContinuousSource.new())
	ensure_input_action()
	set_process(false)


static func ensure_input_action() -> void:
	if InputMap.has_action(INPUT_ACTION):
		return
	InputMap.add_action(INPUT_ACTION, 0.2)
	var key := InputEventKey.new()
	key.physical_keycode = DEFAULT_INPUT_KEY
	InputMap.action_add_event(INPUT_ACTION, key)


func bind_camera(value: Camera3D) -> void:
	listener_camera = value


func set_perception_active(value: bool) -> void:
	if perception_active == value:
		return
	perception_active = value
	visible = perception_active
	set_process(perception_active)
	if perception_active:
		guidance_remaining = GUIDANCE_SECONDS
	else:
		guidance_remaining = 0.0
		_clear_impressions()
	queue_redraw()


func is_perception_active() -> bool:
	return perception_active


func submit_acoustic_event(packet: Dictionary) -> void:
	if not perception_active or listener_camera == null or packet.is_empty():
		return
	var received_db := clampf(
		SafeVariant.finite_float_or(
			packet.get("rendered_volume_db", packet.get("volume_db")),
			-80.0
		),
		-80.0,
		18.0
	)
	var strength := smoothstep(MIN_VISIBLE_RECEIVED_DB, -5.0, received_db)
	if strength <= 0.002:
		return
	var apparent_position := SafeVariant.vector3_strict_or(
		packet.get("apparent_position"),
		listener_camera.global_position
	)
	var band_gain := SafeVariant.vector3_strict_or(
		packet.get("band_gain"),
		Vector3.ONE
	)
	var pressure_layer := SafeVariant.strict_bool_or(
		packet.get("pressure_layer", false),
		false
	)
	_emit_pulse(
		apparent_position,
		strength * (0.62 if pressure_layer else 1.0),
		band_gain,
		0.0,
		lerpf(0.68, 1.5, strength),
		pressure_layer,
		int(packet.get("sequence", 0))
	)
	if not pressure_layer:
		_submit_early_reflections(packet, strength)
	var sound_id := StringName(str(packet.get("sound_id", "")))
	if (
		sound_id == MOUTH_CLICK_SOUND_ID
		and apparent_position.distance_squared_to(listener_camera.global_position)
		<= 2.25
	):
		capture_near_field_echo(listener_camera.global_position)
	queue_redraw()


func submit_continuous_sample(
	source_id: int,
	apparent_position: Vector3,
	received_intensity: float,
	band_gain: Vector3,
	enclosure: float
) -> void:
	if (
		not perception_active
		or source_id < 0
		or not apparent_position.is_finite()
	):
		return
	var target := clampf(received_intensity, 0.0, 1.0)
	if target <= 0.001:
		return
	var slot := _continuous_slot(source_id)
	slot.world_position = apparent_position
	slot.target_strength = target
	slot.band_gain = band_gain
	slot.enclosure = clampf(enclosure, 0.0, 1.0)
	slot.stale_seconds = 0.0


func capture_near_field_echo(origin: Vector3) -> void:
	if (
		not perception_active
		or not origin.is_finite()
		or not is_inside_tree()
		or get_viewport().world_3d == null
	):
		return
	var space_state := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = CharacterContactLayers.FOOT_CONTACT_QUERY
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.from = origin
	for ray_index: int in range(ECHO_RAY_COUNT):
		var y := 1.0 - 2.0 * (float(ray_index) + 0.5) / float(ECHO_RAY_COUNT)
		var radial := sqrt(maxf(1.0 - y * y, 0.0))
		var angle := GOLDEN_ANGLE * float(ray_index)
		var direction := Vector3(
			cos(angle) * radial,
			y,
			sin(angle) * radial
		)
		query.to = origin + direction * ECHO_RANGE_METERS
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
		var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
		var distance := origin.distance_to(hit_position)
		_emit_surface_echo(
			hit_position,
			hit_normal,
			distance,
			pow(1.0 - clampf(distance / ECHO_RANGE_METERS, 0.0, 1.0), 0.58),
			false
		)
	_capture_item_echoes(origin, space_state)


func debug_state() -> Dictionary:
	var pulse_count := 0
	var surface_count := 0
	var continuous_count := 0
	for pulse: PerceptionPulse in _pulses:
		pulse_count += 1 if pulse.active else 0
	for echo: SurfaceEcho in _surface_echoes:
		surface_count += 1 if echo.active else 0
	for source: ContinuousSource in _continuous_sources:
		continuous_count += 1 if source.active else 0
	return {
		"active": perception_active,
		"pulse_count": pulse_count,
		"surface_echo_count": surface_count,
		"continuous_source_count": continuous_count,
		"guidance_remaining": guidance_remaining,
		"echo_ray_count": ECHO_RAY_COUNT,
		"echo_range_meters": ECHO_RANGE_METERS,
	}


func _process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	guidance_remaining = maxf(guidance_remaining - safe_delta, 0.0)
	for pulse: PerceptionPulse in _pulses:
		if not pulse.active:
			continue
		pulse.age += safe_delta
		if pulse.age >= pulse.delay + pulse.lifetime:
			pulse.active = false
	for echo: SurfaceEcho in _surface_echoes:
		if not echo.active:
			continue
		echo.age += safe_delta
		if echo.age >= echo.delay + echo.lifetime:
			echo.active = false
	for source: ContinuousSource in _continuous_sources:
		if not source.active:
			continue
		source.stale_seconds += safe_delta
		source.phase = fmod(source.phase + safe_delta * lerpf(1.1, 2.8, source.strength), TAU)
		if source.stale_seconds > CONTINUOUS_STALE_SECONDS:
			source.target_strength = 0.0
		var follow_speed := 9.0 if source.target_strength > source.strength else 4.0
		source.strength = lerpf(
			source.strength,
			source.target_strength,
			1.0 - exp(-safe_delta * follow_speed)
		)
		if source.strength <= 0.002 and source.target_strength <= 0.002:
			source.active = false
	queue_redraw()


func _draw() -> void:
	if not perception_active or listener_camera == null:
		return
	for source: ContinuousSource in _continuous_sources:
		if source.active and source.strength > 0.002:
			_draw_continuous_source(source)
	for pulse: PerceptionPulse in _pulses:
		if pulse.active and pulse.age >= pulse.delay:
			_draw_pulse(pulse)
	for echo: SurfaceEcho in _surface_echoes:
		if echo.active and echo.age >= echo.delay:
			_draw_surface_echo(echo)
	_draw_guidance()


func _submit_early_reflections(packet: Dictionary, parent_strength: float) -> void:
	var raw_reflections: Variant = packet.get("early_reflections", [])
	if not raw_reflections is Array:
		return
	var reflection_index := 0
	for raw_value: Variant in raw_reflections as Array:
		if not raw_value is Dictionary:
			continue
		var reflection := raw_value as Dictionary
		var gain := clampf(
			SafeVariant.finite_float_or(reflection.get("gain"), 0.0),
			0.0,
			0.7
		)
		if gain <= 0.001:
			continue
		_emit_pulse(
			SafeVariant.vector3_strict_or(
				reflection.get("apparent_position"),
				packet.get("apparent_position", Vector3.ZERO)
			),
			parent_strength * sqrt(gain) * 0.72,
			SafeVariant.vector3_strict_or(
				reflection.get("band_gain"),
				Vector3.ONE
			),
			clampf(
				SafeVariant.finite_float_or(
					reflection.get("extra_delay_seconds"),
					0.0
				),
				0.0,
				0.25
			),
			lerpf(0.5, 1.15, parent_strength),
			true,
			int(packet.get("sequence", 0)) + reflection_index + 17
		)
		reflection_index += 1


func _emit_pulse(
	world_position: Vector3,
	strength: float,
	band_gain: Vector3,
	delay: float,
	lifetime: float,
	pressure_layer: bool,
	seed_value: int
) -> void:
	if not world_position.is_finite():
		return
	var pulse := _pulses[_next_pulse_index]
	_next_pulse_index = (_next_pulse_index + 1) % _pulses.size()
	pulse.active = true
	pulse.world_position = world_position
	pulse.age = 0.0
	pulse.delay = maxf(delay, 0.0)
	pulse.lifetime = maxf(lifetime, 0.1)
	pulse.strength = clampf(strength, 0.0, 1.0)
	pulse.band_gain = band_gain
	pulse.seed = fmod(absf(float(seed_value) * 0.61803398875), 1.0)
	pulse.pressure_layer = pressure_layer


func _emit_surface_echo(
	world_position: Vector3,
	world_normal: Vector3,
	distance: float,
	strength: float,
	item_echo: bool
) -> void:
	if not world_position.is_finite() or strength <= 0.003:
		return
	var echo := _surface_echoes[_next_surface_index]
	_next_surface_index = (_next_surface_index + 1) % _surface_echoes.size()
	echo.active = true
	echo.world_position = world_position
	echo.world_normal = world_normal.normalized()
	echo.age = 0.0
	echo.delay = clampf(
		2.0 * maxf(distance, 0.0) / SPEED_OF_SOUND_METERS_PER_SECOND,
		0.0,
		0.14
	)
	echo.lifetime = lerpf(1.15, 0.58, clampf(distance / ECHO_RANGE_METERS, 0.0, 1.0))
	echo.strength = clampf(strength * (1.0 if item_echo else 0.76), 0.0, 1.0)
	echo.item_echo = item_echo


func _capture_item_echoes(origin: Vector3, space_state: PhysicsDirectSpaceState3D) -> void:
	var client := get_node_or_null("/root/Client")
	if client == null or not client.has_method("collect_echolocation_targets"):
		return
	var targets: Array = client.call(
		"collect_echolocation_targets",
		origin,
		ITEM_ECHO_RANGE_METERS
	) as Array
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = CharacterContactLayers.FOOT_CONTACT_QUERY
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.from = origin
	for target_value: Variant in targets:
		if not target_value is Dictionary:
			continue
		var target := target_value as Dictionary
		var position := SafeVariant.vector3_strict_or(
			target.get("world_position"),
			Vector3.INF
		)
		if not position.is_finite():
			continue
		var distance := origin.distance_to(position)
		if distance <= 0.05 or distance > ITEM_ECHO_RANGE_METERS:
			continue
		query.to = origin.lerp(position, maxf(1.0 - 0.18 / distance, 0.0))
		if not space_state.intersect_ray(query).is_empty():
			continue
		var target_strength := pow(
			1.0 - distance / ITEM_ECHO_RANGE_METERS,
			0.52
		)
		if SafeVariant.strict_bool_or(target.get("is_eyes", false), false):
			# Ocular housings are intentionally reflective and important to recovery, but still
			# require an unobstructed click path like every other item.
			target_strength = minf(target_strength * 1.24, 1.0)
		_emit_surface_echo(
			position,
			(origin - position).normalized(),
			distance,
			target_strength,
			true
		)


func _continuous_slot(source_id: int) -> ContinuousSource:
	var weakest := _continuous_sources[0]
	for source: ContinuousSource in _continuous_sources:
		if source.active and source.source_id == source_id:
			return source
		if not source.active:
			source.active = true
			source.source_id = source_id
			source.strength = 0.0
			source.target_strength = 0.0
			source.stale_seconds = 0.0
			source.phase = fmod(absf(float(source_id) * 0.754877666), 1.0) * TAU
			return source
		if source.strength < weakest.strength:
			weakest = source
	weakest.active = true
	weakest.source_id = source_id
	weakest.strength = 0.0
	weakest.target_strength = 0.0
	weakest.stale_seconds = 0.0
	weakest.phase = fmod(absf(float(source_id) * 0.754877666), 1.0) * TAU
	return weakest


func _draw_pulse(pulse: PerceptionPulse) -> void:
	var local_age := pulse.age - pulse.delay
	var progress := clampf(local_age / pulse.lifetime, 0.0, 1.0)
	var projected := _project_to_view(pulse.world_position)
	var center := Vector2(projected.x, projected.y)
	var on_screen := projected.z > 0.5
	var eased := 1.0 - pow(1.0 - progress, 2.2)
	var radius := lerpf(9.0, lerpf(76.0, 168.0, pulse.strength), eased)
	var alpha := pulse.strength * pow(1.0 - progress, 1.7)
	if pulse.pressure_layer:
		alpha *= 0.58
	var color := _band_color(pulse.band_gain)
	var start := pulse.seed * TAU + progress * 0.18
	var span := lerpf(1.35, 2.45, pulse.strength)
	if not on_screen:
		span *= 0.62
	for arc_index: int in range(3):
		var arc_start := start + float(arc_index) * TAU / 3.0
		_draw_organic_arc(
			center,
			radius * (1.0 - float(arc_index) * 0.025),
			arc_start,
			span,
			color,
			alpha,
			pulse.seed * TAU + float(arc_index),
			1.1 if pulse.pressure_layer else 1.55
		)


func _draw_surface_echo(echo: SurfaceEcho) -> void:
	var progress := clampf((echo.age - echo.delay) / echo.lifetime, 0.0, 1.0)
	var projected := _project_to_view(echo.world_position)
	if projected.z <= 0.5:
		return
	var center := Vector2(projected.x, projected.y)
	var to_listener := (
		listener_camera.global_position - echo.world_position
	).normalized()
	var tangent := echo.world_normal.cross(to_listener).normalized()
	if tangent.length_squared() <= 0.0001:
		tangent = listener_camera.global_basis.x.normalized()
	var half_world_length := lerpf(0.12, 0.62, echo.strength)
	var left := listener_camera.unproject_position(
		echo.world_position - tangent * half_world_length
	)
	var right := listener_camera.unproject_position(
		echo.world_position + tangent * half_world_length
	)
	var alpha := echo.strength * pow(1.0 - progress, 1.45)
	var color := CORE_COLOR.lerp(LOW_COLOR, 0.22 if echo.item_echo else 0.06)
	draw_line(left, right, Color(color, alpha * 0.12), 8.0, true)
	draw_line(left, right, Color(color, alpha * 0.55), 2.2, true)
	draw_circle(center, 2.2 + echo.strength * 2.5, Color(color, alpha * 0.32), true)
	if echo.item_echo:
		draw_arc(
			center,
			7.0 + 5.0 * progress,
			0.0,
			TAU,
			24,
			Color(color, alpha * 0.34),
			1.2,
			true
		)


func _draw_continuous_source(source: ContinuousSource) -> void:
	var projected := _project_to_view(source.world_position)
	var center := Vector2(projected.x, projected.y)
	var color := _band_color(source.band_gain)
	var breath := 0.5 + 0.5 * sin(source.phase)
	var radius := 18.0 + source.strength * 34.0 + breath * 5.0
	var alpha := source.strength * lerpf(0.26, 0.48, source.enclosure)
	var span := lerpf(1.0, 2.2, source.strength)
	for arc_index: int in range(3):
		_draw_organic_arc(
			center,
			radius + float(arc_index) * 7.0,
			source.phase * 0.22 + float(arc_index) * TAU / 3.0,
			span,
			color,
			alpha * (1.0 - float(arc_index) * 0.2),
			source.phase + float(arc_index),
			1.25
		)


func _draw_organic_arc(
	center: Vector2,
	radius: float,
	start_angle: float,
	span: float,
	color: Color,
	alpha: float,
	phase: float,
	core_width: float
) -> void:
	if alpha <= 0.001 or radius <= 0.0:
		return
	for point_index: int in range(ARC_POINT_COUNT):
		var unit := float(point_index) / float(ARC_POINT_COUNT - 1)
		var angle := start_angle + unit * span
		var breath := sin(unit * PI) * sin(angle * 3.0 + phase) * 1.35
		_arc_points[point_index] = center + Vector2(cos(angle), sin(angle)) * (
			radius + breath
		)
	draw_polyline(_arc_points, Color(color, alpha * 0.09), core_width + 7.0, true)
	draw_polyline(_arc_points, Color(color, alpha * 0.25), core_width + 2.5, true)
	draw_polyline(_arc_points, Color(color, alpha * 0.82), core_width, true)


func _draw_guidance() -> void:
	if guidance_remaining <= 0.0:
		return
	var alpha := smoothstep(0.0, 0.8, guidance_remaining) * 0.72
	var font := ThemeDB.fallback_font
	var font_size := 19
	var message := "No visual input   ·   Q to listen outward"
	var text_size := font.get_string_size(
		message,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)
	var position := Vector2(
		(size.x - text_size.x) * 0.5,
		size.y * 0.86
	)
	draw_string(
		font,
		position,
		message,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(CORE_COLOR, alpha)
	)


func _project_to_view(world_position: Vector3) -> Vector3:
	var viewport_size := size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		viewport_size = get_viewport_rect().size
	var center := viewport_size * 0.5
	var margin := Vector2(30.0, 30.0)
	var behind := listener_camera.is_position_behind(world_position)
	var projected := listener_camera.unproject_position(world_position)
	if behind:
		var local_direction := listener_camera.global_basis.inverse() * (
			world_position - listener_camera.global_position
		)
		var screen_direction := Vector2(local_direction.x, -local_direction.y)
		if screen_direction.length_squared() <= 0.0001:
			screen_direction = Vector2.DOWN
		projected = center + screen_direction.normalized() * viewport_size.length()
	var on_screen := (
		not behind
		and projected.x >= margin.x
		and projected.y >= margin.y
		and projected.x <= viewport_size.x - margin.x
		and projected.y <= viewport_size.y - margin.y
	)
	projected.x = clampf(projected.x, margin.x, viewport_size.x - margin.x)
	projected.y = clampf(projected.y, margin.y, viewport_size.y - margin.y)
	return Vector3(projected.x, projected.y, 1.0 if on_screen else 0.0)


static func _band_color(band_gain: Vector3) -> Color:
	var total := maxf(band_gain.x + band_gain.y + band_gain.z, 0.0001)
	var low_weight := clampf(band_gain.x / total * 1.8, 0.0, 1.0)
	var high_weight := clampf(band_gain.z / total * 1.8, 0.0, 1.0)
	return CORE_COLOR.lerp(LOW_COLOR, low_weight * 0.42).lerp(
		HIGH_COLOR,
		high_weight * 0.36
	)


func _clear_impressions() -> void:
	for pulse: PerceptionPulse in _pulses:
		pulse.active = false
	for echo: SurfaceEcho in _surface_echoes:
		echo.active = false
	for source: ContinuousSource in _continuous_sources:
		source.active = false
		source.strength = 0.0
		source.target_strength = 0.0
