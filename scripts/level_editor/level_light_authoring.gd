class_name LevelLightAuthoring
extends RefCounted

const TYPE_OMNI := &"omni"
const TYPE_SPOT := &"spot"
const TYPE_DIRECTIONAL := &"directional"
const DEFAULT_COLOR := Color(1.0, 0.86, 0.68, 1.0)
const MINIMUM_ENERGY := 0.0
const MAXIMUM_ENERGY := 32.0
const MINIMUM_RANGE := 0.1
const MAXIMUM_RANGE := 250.0
const MINIMUM_SPOT_ANGLE := 1.0
const MAXIMUM_SPOT_ANGLE := 89.0


static func create_descriptor(
	light_id: int,
	type: StringName,
	position: Vector3,
	rotation: Vector3,
	display_name := ""
) -> Dictionary:
	var safe_type := sanitize_type(type)
	var safe_name := display_name.strip_edges()
	if safe_name.is_empty():
		safe_name = "%s LIGHT %03d" % [type_label(safe_type), light_id]
	return sanitize_descriptor({
		"id": light_id,
		"display_name": safe_name,
		"type": safe_type,
		"position": position,
		"rotation": rotation,
		"color": DEFAULT_COLOR,
		"energy": 2.0,
		"range": 12.0,
		"attenuation": 1.0,
		"shadows": true,
		"spot_angle": 42.0,
		"spot_angle_attenuation": 1.0,
	})


static func sanitize_descriptor(raw: Dictionary) -> Dictionary:
	var light_id := int(raw.get("id", 0))
	if light_id <= 0:
		return {}
	var type := sanitize_type(StringName(str(raw.get("type", TYPE_OMNI))))
	var display_name := str(raw.get("display_name", "")).strip_edges()
	if display_name.is_empty():
		display_name = "%s LIGHT %03d" % [type_label(type), light_id]
	return {
		"id": light_id,
		"display_name": display_name.left(80),
		"type": type,
		"position": _finite_vector3(raw.get("position", Vector3.ZERO), Vector3.ZERO),
		"rotation": _finite_vector3(raw.get("rotation", Vector3.ZERO), Vector3.ZERO),
		"color": _finite_color(raw.get("color", DEFAULT_COLOR), DEFAULT_COLOR),
		"energy": clampf(
			_finite_float(raw.get("energy", 2.0), 2.0),
			MINIMUM_ENERGY,
			MAXIMUM_ENERGY
		),
		"range": clampf(
			_finite_float(raw.get("range", 12.0), 12.0),
			MINIMUM_RANGE,
			MAXIMUM_RANGE
		),
		"attenuation": clampf(
			_finite_float(raw.get("attenuation", 1.0), 1.0),
			0.0,
			4.0
		),
		"shadows": bool(raw.get("shadows", true)),
		"spot_angle": clampf(
			_finite_float(raw.get("spot_angle", 42.0), 42.0),
			MINIMUM_SPOT_ANGLE,
			MAXIMUM_SPOT_ANGLE
		),
		"spot_angle_attenuation": clampf(
			_finite_float(raw.get("spot_angle_attenuation", 1.0), 1.0),
			0.0,
			4.0
		),
	}


static func serialize_descriptor(raw: Dictionary) -> Dictionary:
	var safe := sanitize_descriptor(raw)
	if safe.is_empty():
		return {}
	var color: Color = safe["color"]
	return {
		"id": safe["id"],
		"display_name": safe["display_name"],
		"type": str(safe["type"]),
		"position": _vector3_to_array(safe["position"]),
		"rotation": _vector3_to_array(safe["rotation"]),
		"color": [color.r, color.g, color.b, color.a],
		"energy": safe["energy"],
		"range": safe["range"],
		"attenuation": safe["attenuation"],
		"shadows": safe["shadows"],
		"spot_angle": safe["spot_angle"],
		"spot_angle_attenuation": safe["spot_angle_attenuation"],
	}


static func instantiate_light(raw: Dictionary) -> Light3D:
	var safe := sanitize_descriptor(raw)
	if safe.is_empty():
		return null
	var light: Light3D
	match safe["type"]:
		TYPE_SPOT:
			var spot := SpotLight3D.new()
			spot.spot_range = float(safe["range"])
			spot.spot_attenuation = float(safe["attenuation"])
			spot.spot_angle = float(safe["spot_angle"])
			spot.spot_angle_attenuation = float(safe["spot_angle_attenuation"])
			light = spot
		TYPE_DIRECTIONAL:
			light = DirectionalLight3D.new()
		_:
			var omni := OmniLight3D.new()
			omni.omni_range = float(safe["range"])
			omni.omni_attenuation = float(safe["attenuation"])
			light = omni
	light.name = _node_name(safe)
	light.position = safe["position"]
	light.rotation = safe["rotation"]
	light.light_color = safe["color"]
	light.light_energy = float(safe["energy"])
	light.shadow_enabled = bool(safe["shadows"])
	light.set_meta("authored_light_id", int(safe["id"]))
	light.set_meta("authored_light_type", safe["type"])
	return light


static func apply_to_light(light: Light3D, raw: Dictionary) -> bool:
	var safe := sanitize_descriptor(raw)
	if light == null or safe.is_empty() or not light_matches_type(light, safe["type"]):
		return false
	light.name = _node_name(safe)
	light.position = safe["position"]
	light.rotation = safe["rotation"]
	light.light_color = safe["color"]
	light.light_energy = float(safe["energy"])
	light.shadow_enabled = bool(safe["shadows"])
	if light is OmniLight3D:
		(light as OmniLight3D).omni_range = float(safe["range"])
		(light as OmniLight3D).omni_attenuation = float(safe["attenuation"])
	elif light is SpotLight3D:
		(light as SpotLight3D).spot_range = float(safe["range"])
		(light as SpotLight3D).spot_attenuation = float(safe["attenuation"])
		(light as SpotLight3D).spot_angle = float(safe["spot_angle"])
		(light as SpotLight3D).spot_angle_attenuation = float(
			safe["spot_angle_attenuation"]
		)
	light.set_meta("authored_light_id", int(safe["id"]))
	light.set_meta("authored_light_type", safe["type"])
	return true


static func light_matches_type(light: Light3D, type: StringName) -> bool:
	match sanitize_type(type):
		TYPE_SPOT: return light is SpotLight3D
		TYPE_DIRECTIONAL: return light is DirectionalLight3D
		_: return light is OmniLight3D


static func sanitize_type(value: StringName) -> StringName:
	return value if value in [TYPE_OMNI, TYPE_SPOT, TYPE_DIRECTIONAL] else TYPE_OMNI


static func type_label(value: StringName) -> String:
	match sanitize_type(value):
		TYPE_SPOT: return "SPOT"
		TYPE_DIRECTIONAL: return "SUN"
		_: return "POINT"


static func _node_name(safe: Dictionary) -> String:
	var text := str(safe.get("display_name", "Authored Light"))
	var result := ""
	for character: String in text:
		if character.to_lower() != character.to_upper() or character.is_valid_int():
			result += character
		elif not result.ends_with("_"):
			result += "_"
	result = result.strip_edges().trim_suffix("_")
	if result.is_empty():
		result = "AuthoredLight"
	return "%s_%03d" % [result, int(safe.get("id", 0))]


static func _finite_vector3(value: Variant, fallback: Vector3) -> Vector3:
	var result := fallback
	if value is Vector3:
		result = value
	elif value is Array and value.size() >= 3:
		result = Vector3(float(value[0]), float(value[1]), float(value[2]))
	return result if result.is_finite() else fallback


static func _finite_color(value: Variant, fallback: Color) -> Color:
	var result := fallback
	if value is Color:
		result = value
	elif value is Array and value.size() >= 3:
		result = Color(
			float(value[0]),
			float(value[1]),
			float(value[2]),
			float(value[3]) if value.size() >= 4 else 1.0
		)
	if not (
		is_finite(result.r)
		and is_finite(result.g)
		and is_finite(result.b)
		and is_finite(result.a)
	):
		return fallback
	return Color(
		clampf(result.r, 0.0, 1.0),
		clampf(result.g, 0.0, 1.0),
		clampf(result.b, 0.0, 1.0),
		clampf(result.a, 0.0, 1.0)
	)


static func _finite_float(value: Variant, fallback: float) -> float:
	var result := float(value)
	return result if is_finite(result) else fallback


static func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
